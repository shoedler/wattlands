#!/usr/bin/env node
// tools/e2e/faults.mjs: the multiplayer failure paths, proved with real processes. Owned by qa.
// Zero dependencies.
//
//   node tools/e2e/faults.mjs [--games=a,b] [--scenarios=x,y] [options]      (--help lists them)
//
// Plays each scenario (builtin, wrong_code, late_join, relay_dies, relay_restarts,
// host_killed_relay, host_killed_builtin) with headless peers through tools/godot.sh (mock trainer,
// Autopilot, --sim-speed=1, a fresh profile under build/e2e_faults/) on the built-in relay or on
// server/relay, checks what happened on every peer (exit code, WATTLANDS_* lines, report JSON, error
// lines, FIT files) and writes build/e2e_faults/report.json: one named pass or fail per scenario.
//
// Every scenario holds one lease (2 Godot slots, 3 for late_join) of the machine-wide lock (BRIEF 2)
// and its peers run inside it. Every child gets WATTLANDS_NO_HW_CONTROL=1 and WATTLANDS_NO_NETWORK_INTEGRATIONS=1
// (the built-in relay then binds and beacons on 127.0.0.1 only), never sees FAL_KEY or
// WATTLANDS_ALLOW_ART, and has stdin closed.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FAULTS_USAGE, familyOf, parseFaultArgs } from './lib/fault_args.mjs';
import { FaultEnv, leaseFor } from './lib/fault_env.mjs';
import { scenarioFor } from './lib/fault_scenarios.mjs';
import { runVerdict, scenarioVerdict } from './lib/fault_verdicts.mjs';
import { LOCK_TIMEOUT_MESSAGE, takeLease } from './lib/lease.mjs';
import { killAll } from './lib/proc.mjs';
import { fmtSeconds, writeJson } from './lib/util.mjs';

export const EXIT_OK = 0;
export const EXIT_FAIL = 1;
export const EXIT_USAGE = 2;
export const EXIT_LOCK_TIMEOUT = 75;
export const REPORT_SCHEMA = 1;

const out = (line) => process.stdout.write(`${line}\n`);
const err = (line) => process.stderr.write(`${line}\n`);

/** Runs one scenario inside its own lease; always returns a verdict (a crash is a failed check). */
export async function runScenario(o, name, log = out) {
  const fn = scenarioFor(name);
  const lease = await takeLease({ lease: leaseFor(name), lockTimeoutS: o.lockTimeoutS, label: `e2e faults.mjs ${name}`, log: err });
  const t0 = Date.now();
  const env = new FaultEnv(o, name, lease, log);
  let checks = [];
  let peers = [];
  let crash = null;
  try {
    const r = await fn(env);
    checks = r.checks;
    peers = r.peers;
  } catch (e) {
    crash = e.message;
    log(`faults: ${name}: ${crash}`);
  } finally {
    await env.cleanup();
    lease.release();
  }
  if (crash !== null) {
    const states = env.runs.map((r) => `${r.name} ${r.proc.closed ? `exited ${r.proc.exitCode}` : 'running'}`).join('; ');
    checks.unshift({ name: 'run', ok: false, details: [`${crash}${states ? ` (${states})` : ''}`] });
    // Whatever the peers did before the crash is still evidence.
    try {
      for (const run of env.runs) {
        const o2 = await env.outcome(run, { fit: false });
        peers.push({ name: o2.name, exit_code: o2.exitCode, exit_reason: o2.exitReason, states: o2.states, error_lines: o2.errorLines.slice(0, 10), godot_log: run.godotLog });
      }
    } catch {
      // keep the crash message
    }
  }
  const v = scenarioVerdict(name, checks, {
    duration_s: Math.round((Date.now() - t0) / 100) / 10,
    out_dir: env.dir,
    timeline: env.timeline,
    relays: env.relayRuns.map((r) => ({ url: r.url, cmd: r.cmdline.join(' ') })),
    lan: env.lan,
    peers,
  });
  return v;
}

/**
 * Runs `names` through runOne(name), at most `jobs` at once (--jobs; each scenario holds its own
 * lease, ports, relay and output folder). onDone(verdict) as each one ends. A lock wait timeout
 * (runOne throws code ELOCKTIMEOUT) starts nothing more; what already runs finishes. Resolves
 * {lockTimeout}.
 */
export async function runScenarios(names, jobs, runOne, onDone) {
  let next = 0;
  let lockTimeout = false;
  const worker = async () => {
    while (!lockTimeout && next < names.length) {
      const name = names[next];
      next += 1;
      try {
        onDone(await runOne(name));
      } catch (e) {
        if (e.code !== 'ELOCKTIMEOUT') throw e;
        lockTimeout = true;
      }
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(jobs, names.length)) }, worker));
  return { lockTimeout };
}

// The scenarios that ride out the 120 s windows and the cool-down (5 to 6 minutes each, README).
const LONG_FAMILIES = ['relay_dies', 'relay_restarts', 'host_killed_relay', 'host_killed_builtin'];

/** The order scenarios start in: as given one at a time; with --jobs above 1 the long ones first. */
export function startOrder(names, jobs) {
  if (jobs <= 1) return names;
  const long = (n) => LONG_FAMILIES.includes(familyOf(n));
  return [...names.filter(long), ...names.filter((n) => !long(n))];
}

export async function main(argv) {
  const parsed = parseFaultArgs(argv);
  if (parsed.help) {
    out(FAULTS_USAGE);
    return EXIT_OK;
  }
  if (!parsed.ok) {
    err(`faults: ${parsed.error}`);
    err(FAULTS_USAGE);
    return EXIT_USAGE;
  }
  const { opts: o, names } = parsed;
  const reportPath = path.join(o.out, 'report.json');
  fs.mkdirSync(o.out, { recursive: true });
  const started = new Date().toISOString();
  const results = [];
  let lockTimeout = false;
  const write = () =>
    writeJson(reportPath, {
      schema: REPORT_SCHEMA,
      started,
      ok: results.length > 0 && results.every((r) => r.ok) && !lockTimeout,
      games: o.games,
      scenarios: results,
      pending: names.filter((n) => !results.some((r) => r.name === n)),
    });
  const onSignal = (sig) => {
    err(`faults: ${sig}, stopping every peer`);
    killAll();
    process.exit(130);
  };
  const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'];
  if (process.platform === 'win32') signals.push('SIGBREAK');
  for (const s of signals) process.on(s, onSignal);
  try {
    const one = async (name) => {
      out(`faults: ${name}: start`);
      try {
        return await runScenario(o, name);
      } catch (e) {
        if (e.code === 'ELOCKTIMEOUT') throw e;
        err(`faults: ${e.stack || e}`);
        return { name, ok: false, failures: [`harness: ${e.message}`], checks: [{ name: 'run', ok: false, details: [e.message] }], evidence: {} };
      }
    };
    const done = (v) => {
      results.push(v);
      results.sort((a, b) => names.indexOf(a.name) - names.indexOf(b.name));
      write();
      out(`faults: ${v.name} ${v.ok ? 'PASS' : 'FAIL'} (${fmtSeconds(v.evidence.duration_s ?? NaN)})`);
      for (const f of v.failures) out(`faults:   ${f}`);
    };
    const r = await runScenarios(startOrder(names, o.jobs), o.jobs, one, done);
    if (r.lockTimeout) {
      err(LOCK_TIMEOUT_MESSAGE);
      lockTimeout = true;
    }
  } finally {
    killAll();
    for (const s of signals) process.off(s, onSignal);
  }
  write();
  const verdict = runVerdict(results, { lockTimeout });
  out(`${verdict.line} -> ${reportPath}`);
  return verdict.code;
}

function isMain() {
  if (!process.argv[1]) return false;
  const norm = (p) => {
    let r = path.resolve(p);
    try {
      r = fs.realpathSync(r);
    } catch {
      // keep resolved path
    }
    return process.platform === 'win32' ? r.toLowerCase() : r;
  };
  return norm(process.argv[1]) === norm(fileURLToPath(import.meta.url));
}

if (isMain()) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e) => {
      err(`faults: ${e.stack || e}`);
      killAll();
      process.exit(EXIT_FAIL);
    },
  );
}
