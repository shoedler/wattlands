// tools/e2e/lib/fault_env.mjs: the processes of one fault scenario: peers through tools/godot.sh
// inside a Godot lease, the relay, the built-in relay's ports, and the evidence read back from them.
import fs from 'node:fs';
import path from 'node:path';
import { Proc } from './proc.mjs';
import { serviceLog, startRelay, stopService } from './services.mjs';
import { runFitCheck, peerCommand } from './game.mjs';
import { childEnv, getFreePort, quoteForLog, readJson, redact, slash, sleep } from './util.mjs';
import { faultPeerArgs, peerOutcome, ROOM_LINE, PEER_LINE, SESSION_STATES } from './fault_verdicts.mjs';

/** The Godot slots a scenario holds: its most concurrent peers (the host and a client; late_join adds a third). */
export function leaseFor(name) {
  return name.startsWith('late_join') ? 3 : 2;
}

const SESSION_RE = new RegExp(`^WATTLANDS_STATE\\s+(${SESSION_STATES.join('|')})\\b`);

function readLines(file) {
  try {
    return fs.readFileSync(file, 'utf8').split(/\r?\n/);
  } catch {
    return [];
  }
}

function isObj(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

export class FaultEnv {
  /**
   * @param {object} o parsed options (fault_args.mjs)
   * @param {string} name scenario name ("builtin:siege")
   * @param {object} lease the held lease handle
   * @param {(line: string) => void} log progress lines
   */
  constructor(o, name, lease, log) {
    this.o = o;
    this.name = name;
    this.lease = lease;
    this.log = log;
    this.dir = path.join(o.out, name.replace(/[^\w.-]+/g, '_'));
    fs.rmSync(this.dir, { recursive: true, force: true });
    fs.mkdirSync(this.dir, { recursive: true });
    this.t0 = Date.now();
    this.runs = []; // every peer run, in start order
    this.relay = null;
    this.relayRuns = []; // every relay process, in start order
    this.lan = null;
    this.timeline = [];
  }

  /** Seconds since the scenario started (one decimal). */
  now() {
    return Math.round((Date.now() - this.t0) / 100) / 10;
  }

  note(text) {
    this.timeline.push({ t: this.now(), text });
    this.log(`faults: ${this.name}: ${text}`);
  }

  /** The built-in relay's two ports: the host's relay (TCP) and the beacons (UDP). */
  async useBuiltin() {
    const port = await getFreePort();
    let discoveryPort = await getFreePort();
    while (discoveryPort === port) discoveryPort = await getFreePort();
    this.lan = { port, discoveryPort };
    return this.lan;
  }

  async startRelay({ port = null } = {}) {
    const n = this.relayRuns.length + 1;
    const svc = await startRelay({
      repo: this.o.repo,
      relayCmd: this.o.relayCmd,
      logFile: serviceLog(this.dir, n === 1 ? 'relay' : `relay_${n}`),
      timeoutMs: this.o.serviceTimeoutS * 1000,
      echo: this.o.verbose ? (line) => process.stdout.write(`[${this.name} relay] ${line}\n`) : null,
      port,
    });
    this.relay = svc;
    this.relayRuns.push(svc);
    this.note(`relay ${n} on ${svc.url}`);
    return svc;
  }

  /** Where peers connect: the relay's URL, or null for the built-in relay. */
  get relayUrl() {
    return this.relay ? this.relay.url : null;
  }

  /**
   * Starts one peer. spec: {role: host|client, base (the folder and report name, a restart of the
   * same base reuses the profile), gameId, code, runSeconds, content}. Returns the run.
   */
  spawnPeer(spec) {
    const attempt = this.runs.filter((r) => r.base === spec.base).length;
    const dir = path.join(this.dir, spec.base);
    const profileDir = slash(path.join(dir, 'profile'));
    fs.mkdirSync(profileDir, { recursive: true });
    const suffix = attempt > 0 ? `_${attempt + 1}` : '';
    const reportPath = slash(path.join(dir, `report${suffix}.json`));
    const godotLog = slash(path.join(dir, `godot${suffix}.log`));
    const userArgs = faultPeerArgs(this.o, {
      ...spec,
      profileDir,
      reportPath,
      relayUrl: this.relayUrl,
      lan: this.relay ? null : this.lan,
    });
    const { cmd, args, env } = peerCommand(this.o, userArgs, { godotLog, lease: this.lease });
    const name = attempt > 0 ? `${spec.base}#${attempt + 1}` : spec.base;
    this.note(`starting ${name}`);
    const proc = new Proc(name, cmd, args, {
      cwd: this.o.repo,
      env: childEnv(process.env, env),
      logFile: path.join(dir, `stdout${suffix}.log`),
      echo: this.o.verbose ? (line) => process.stdout.write(`[${this.name} ${name}] ${line}\n`) : null,
    });
    const run = {
      ...spec,
      name,
      attempt,
      dir,
      profileDir,
      reportPath,
      godotLog,
      userArgs,
      proc,
      cmdline: quoteForLog(redact([cmd === process.execPath ? 'node' : cmd, ...args])),
      startedAt: Date.now(),
    };
    this.runs.push(run);
    return run;
  }

  /** Starts the host and returns {host, code} once it printed its room. */
  async startHost(spec) {
    const host = this.spawnPeer({ role: 'host', base: 'host', ...spec });
    const room = await host.proc.waitFor(ROOM_LINE, this.o.bootTimeoutS * 1000);
    this.note(`host room ${room.match[1]}`);
    return { host, code: room.match[1] };
  }

  /** Waits for a peer's WATTLANDS_PEER line (it is in the room). */
  async inRoom(run) {
    const r = await run.proc.waitFor(PEER_LINE, this.o.bootTimeoutS * 1000);
    this.note(`${run.name} is peer ${r.match[1]}`);
    return Number(r.match[1]);
  }

  /** Waits until the session itself started on this peer. */
  async inSession(run) {
    await run.proc.waitFor(SESSION_RE, this.o.bootTimeoutS * 1000);
    this.note(`${run.name} session started`);
  }

  /** Waits for every run in `runs` to exit, up to `timeoutMs` in all; resolves the ones that did not. */
  async waitAll(runs, timeoutMs) {
    const deadline = Date.now() + timeoutMs;
    const late = [];
    for (const r of runs) {
      if (!(await r.proc.waitExit(deadline - Date.now()))) late.push(r);
    }
    return late;
  }

  async killPeer(run, why = 'killing') {
    this.note(`${why} ${run.name}`);
    run.proc.kill();
    if (!(await run.proc.waitExit(20_000))) throw new Error(`${run.name} did not exit within 20 s of being killed`);
  }

  async killRelay(why = 'killing the relay') {
    if (!this.relay) return;
    this.note(why);
    await stopService(this.relay);
  }

  /** Reads one run back: the Godot log, the report JSON and the FIT files (checked when `fit`). */
  async outcome(run, { fit = false } = {}) {
    const rep = readJson(run.reportPath);
    const report = rep.ok && isObj(rep.value) ? rep.value : null;
    const fitPaths = Array.isArray(report?.fit_paths) ? report.fit_paths.map(String) : [];
    const fitExists = Object.fromEntries(fitPaths.map((f) => [f, fs.existsSync(f)]));
    let fitCheck = null;
    const existing = fitPaths.filter((f) => fitExists[f]);
    if (fit && existing.length) {
      const fc = await runFitCheck({ repo: this.o.repo, fitCheckCmd: null }, run.name.replace(/#/g, '_'), existing, this.lease, this.dir);
      fitCheck = { ok: fc.ok, code: fc.code, label: fc.label, errors: fc.errors };
    }
    return peerOutcome({
      name: run.name,
      role: run.role,
      exitCode: run.proc.closed ? run.proc.exitCode : null,
      killed: run.proc.killed,
      lines: run.proc.lines.map((e) => e.line),
      logLines: readLines(run.godotLog),
      report,
      reportError: report ? null : rep.ok ? 'report is not a JSON object' : rep.error,
      fitExists,
      fitCheck,
      startedS: Math.round((run.startedAt - this.t0) / 100) / 10,
      endedS: run.proc.ended ? Math.round((run.proc.ended - this.t0) / 100) / 10 : null,
    });
  }

  /** Kills what is still running (the scenario is over). */
  async cleanup() {
    for (const r of this.runs) r.proc.kill();
    await Promise.all(this.runs.map((r) => r.proc.waitExit(20_000)));
    for (const svc of this.relayRuns) await stopService(svc);
  }
}

export { sleep };
