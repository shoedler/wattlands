// tools/e2e/lib/game.mjs: one game's end-to-end run (BRIEF 7.7, docs/ARCHITECTURE.md "Scripted peers").
import fs from 'node:fs';
import path from 'node:path';
import { Proc, runToEnd } from './proc.mjs';
import { queryUploads, serviceLog, startRelay, startStrava, stopService } from './services.mjs';
import * as C from './checks.mjs';
import { PEER_ROLES, VICTIM } from './args.mjs';
import { leaseEnv } from './lease.mjs';
import {
  STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, childEnv, findBash, quoteForLog, readJson, redact, resolveProgram,
  slash, sleep, tokenize, writeJson,
} from './util.mjs';

export const ROOM_RE = /^WATTLANDS_ROOM\s+(\S+)/;
export const PEER_RE = /^WATTLANDS_PEER\s+(-?\d+)/;
export const STATE_RE = /^WATTLANDS_STATE\s+(\S+)/;
export const DONE_RE = /^WATTLANDS_DONE\b\s*(.*)$/;
/** The session states after which the victim may be killed. */
export const RUNNING_RE = /^WATTLANDS_STATE\s+(running|session|playing|started|in_session|warmup|riding)\b/i;
export const REPORT_SCHEMA = 1;

function isObj(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

/** The game's manifest, which must name an e2e_content. */
export function readManifest(repo, gameId) {
  const file = path.join(repo, 'src', 'games', gameId, 'game.json');
  const r = readJson(file);
  if (!r.ok) return { ok: false, error: `game "${gameId}" is not registered (${r.error})` };
  if (!isObj(r.value)) return { ok: false, error: `src/games/${gameId}/game.json is not a JSON object` };
  const content = r.value.e2e_content;
  if (typeof content !== 'string' || content === '') {
    return { ok: false, error: `src/games/${gameId}/game.json has no e2e_content` };
  }
  return { ok: true, manifest: r.value, content };
}

/** The scripted-peer flags after "--" (docs/ARCHITECTURE.md "Scripted peers"). */
export function peerUserArgs(o, role, ctx) {
  const a = [];
  if (role === 'host') a.push('--host');
  else a.push(`--join=${ctx.code}`);
  a.push(
    `--game=${ctx.gameId}`,
    '--e2e',
    `--wait-peers=${o.waitPeers}`,
    `--relay=${ctx.relayUrl}`,
    `--mock-trainer=${o.mockTrainer}`,
    '--autopilot',
    `--profile-dir=${ctx.profileDir}`,
    '--sim-speed=1',
    `--seed=${o.seed}`,
    `--report=${ctx.reportPath}`,
    `--strava-base=${ctx.stravaBase}`,
    `--run-seconds=${o.runSeconds}`,
  );
  if (role === o.autoUpload) {
    a.push(`--strava-client-id=${STRAVA_CLIENT_ID}`, `--strava-client-secret=${STRAVA_CLIENT_SECRET}`, '--strava-auto-upload');
  }
  return a;
}

/**
 * How a peer is started: tools/godot.sh inside the held lease (its own --log-file and a run
 * timeout), or --peer-cmd for the harness's own tests. Returns {cmd, args, env}.
 */
export function peerCommand(o, userArgs, { godotLog, lease }) {
  if (o.peerCmd) {
    const t = tokenize(o.peerCmd);
    return { cmd: resolveProgram(t[0]), args: [...t.slice(1), '--', ...userArgs], env: leaseEnv(lease) };
  }
  const bash = findBash();
  if (!bash) throw new Error('bash not found (Git Bash on Windows) to run tools/godot.sh');
  return {
    cmd: bash,
    args: [
      slash(path.join(o.repo, 'tools', 'godot.sh')),
      `--timeout=${o.peerTimeoutS}`,
      '--headless',
      '--path',
      slash(o.repo),
      '--log-file',
      godotLog,
      '--',
      ...userArgs,
    ],
    env: leaseEnv(lease),
  };
}

function lastMatch(proc, re) {
  let m = null;
  for (const e of proc.lines) {
    const x = re.exec(e.line);
    if (x) m = x;
  }
  return m;
}

function readLines(file) {
  try {
    return fs.readFileSync(file, 'utf8').split(/\r?\n/);
  } catch {
    return [];
  }
}

/**
 * Plays one game. Returns {gameId, ok, failures: [String], reportPath, durationS, checks}.
 * `lease` is the held 3-slot handle; `log` prints progress lines.
 */
export async function runGame(o, gameId, lease, log = () => {}) {
  const outDir = path.join(o.out, gameId);
  if (!o.keep) fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });
  const reportPath = path.join(outDir, 'report.json');
  const t0 = Date.now();
  const rel = (t) => (t ? Math.round((t - t0) / 100) / 10 : null);
  const echo = (name) => (o.verbose ? (line) => process.stdout.write(`[${gameId} ${name}] ${line}\n`) : null);
  const checks = [];
  const add = (name, ok, details) => checks.push({ name, ok, details: Array.isArray(details) ? details : [String(details)] });
  const timings = { started: new Date(t0).toISOString() };
  const runs = {}; // role -> [run, run2?]
  let relay = null;
  let strava = null;
  let uploads = null;
  let content = null;
  let code = null;

  const man = readManifest(o.repo, gameId);
  if (man.ok) content = man.content;

  const startPeer = (role, attempt, ctx) => {
    const dir = path.join(outDir, role);
    const profileDir = slash(path.join(dir, 'profile'));
    fs.mkdirSync(profileDir, { recursive: true });
    const suffix = attempt > 0 ? '_restart' : '';
    const report = slash(path.join(dir, role === VICTIM && attempt === 0 ? 'report_killed.json' : 'report.json'));
    const godotLog = slash(path.join(dir, `godot${suffix}.log`));
    const userArgs = peerUserArgs(o, role, { ...ctx, gameId, profileDir, reportPath: report });
    const { cmd, args, env } = peerCommand(o, userArgs, { godotLog, lease });
    const name = attempt > 0 ? `${role}#2` : role;
    log(`e2e: ${gameId}: starting ${name}`);
    const proc = new Proc(name, cmd, args, {
      cwd: o.repo,
      env: childEnv(process.env, env),
      logFile: path.join(dir, `stdout${suffix}.log`),
      echo: echo(name),
    });
    const run = {
      role, attempt, dir, profileDir, reportPath: report, godotLog, userArgs, proc,
      cmdline: quoteForLog(redact([cmd === process.execPath ? 'node' : cmd, ...args])),
      started: Date.now(),
    };
    (runs[role] ??= []).push(run);
    return run;
  };

  let flowError = null;
  try {
    if (!man.ok) throw new Error(man.error);
    relay = await startRelay({ repo: o.repo, relayCmd: o.relayCmd, logFile: serviceLog(outDir, 'relay'), timeoutMs: o.serviceTimeoutS * 1000, echo: echo('relay') });
    timings.relay_ready_s = rel(Date.now());
    log(`e2e: ${gameId}: relay on ${relay.url}`);
    strava = await startStrava({ repo: o.repo, stravaCmd: o.stravaCmd, logFile: serviceLog(outDir, 'mock_strava'), timeoutMs: o.serviceTimeoutS * 1000, echo: echo('strava') });
    timings.strava_ready_s = rel(Date.now());
    log(`e2e: ${gameId}: mock Strava on ${strava.base}`);
    const ctx = { relayUrl: relay.url, stravaBase: strava.base, code: null };

    const host = startPeer('host', 0, ctx);
    const room = await host.proc.waitFor(ROOM_RE, o.bootTimeoutS * 1000);
    code = room.match[1];
    ctx.code = code;
    timings.room_s = rel(room.entry.at);
    log(`e2e: ${gameId}: room ${code}`);

    startPeer('client1', 0, ctx);
    const victim = startPeer(VICTIM, 0, ctx);
    const running = await victim.proc.waitFor(RUNNING_RE, o.bootTimeoutS * 1000);
    timings.victim_running_s = rel(running.entry.at);
    await sleep(o.killAfterS * 1000);
    if (victim.proc.closed) throw new Error(`${VICTIM} exited (code ${victim.proc.exitCode}) before it could be killed for the reconnect test`);
    victim.peerIdBeforeKill = lastMatch(victim.proc, PEER_RE)?.[1] ?? null;
    log(`e2e: ${gameId}: killing ${VICTIM} (peer ${victim.peerIdBeforeKill ?? '?'})`);
    timings.kill_s = rel(Date.now());
    victim.proc.kill();
    if (!(await victim.proc.waitExit(20_000))) throw new Error(`${VICTIM} did not exit within 20 s of being killed`);
    await sleep(o.restartDelayS * 1000);
    timings.restart_s = rel(Date.now());
    startPeer(VICTIM, 1, ctx);

    const finals = () => PEER_ROLES.map((r) => runs[r][runs[r].length - 1]);
    const deadline = t0 + o.gameTimeoutS * 1000;
    let grace = null;
    while (finals().some((r) => !r.proc.closed)) {
      if (Date.now() > deadline) throw new Error(`the game did not finish within --game-timeout=${o.gameTimeoutS} s`);
      if (!grace && runs.host[0].proc.closed && runs.host[0].proc.exitCode !== 0) grace = Date.now() + 30_000;
      if (grace && Date.now() > grace) throw new Error(`the host exited with code ${runs.host[0].proc.exitCode}; the clients did not finish within 30 s after it`);
      await sleep(250);
    }
    timings.peers_done_s = rel(Date.now());
    const q = await queryUploads(strava.base, o.stravaAdmin);
    uploads = q.uploads ?? null;
    if (q.error) log(`e2e: ${gameId}: ${q.error}`);
    timings.uploads_query = q.error ? q.error : q.path;
  } catch (err) {
    flowError = err.message;
    log(`e2e: ${gameId}: ${flowError}`);
  } finally {
    for (const list of Object.values(runs)) for (const r of list) r.proc.kill();
    await Promise.all(Object.values(runs).flat().map((r) => r.proc.waitExit(20_000)));
    await stopService(strava);
    await stopService(relay);
  }
  const t1 = Date.now();
  timings.total_s = rel(t1);

  // ------------------------------------------------------------------ gather
  const peers = {};
  for (const role of PEER_ROLES) {
    const list = runs[role] ?? [];
    const final = list[list.length - 1];
    if (!final) continue;
    const rep = readJson(final.reportPath);
    const r = rep.ok && isObj(rep.value) ? rep.value : null;
    const lines = [...final.proc.lines.map((e) => e.line), ...readLines(final.godotLog)];
    const scan = C.scanLog(lines);
    const earlier = list.slice(0, -1).map((run) => {
      const scanEarly = C.scanLog([...run.proc.lines.map((e) => e.line), ...readLines(run.godotLog)]);
      return {
        attempt: run.attempt,
        killed: run.proc.killed,
        exit_code: run.proc.exitCode,
        peer_id: run.peerIdBeforeKill ?? lastMatch(run.proc, PEER_RE)?.[1] ?? null,
        stdout_log: path.join(run.dir, 'stdout.log'),
        godot_log: run.godotLog,
        cmdline: run.cmdline,
        log_errors: scanEarly.errors.slice(0, 20),
        rate_limited: scanEarly.rateLimited.length,
        refused: scanEarly.refused.length,
      };
    });
    peers[role] = {
      role,
      peer_id: r?.peer_id ?? lastMatch(final.proc, PEER_RE)?.[1] ?? null,
      exit_code: final.proc.exitCode,
      killed_by_harness: final.proc.killed,
      exit_reason: r?.exit_reason ?? lastMatch(final.proc, DONE_RE)?.[1] ?? null,
      done_line: lastMatch(final.proc, DONE_RE)?.[0] ?? null,
      states: final.proc.lines.filter((e) => STATE_RE.test(e.line)).map((e) => ({ t: e.t, state: STATE_RE.exec(e.line)[1] })),
      report_path: final.reportPath,
      report_error: rep.ok ? (r ? null : 'not a JSON object') : rep.error,
      stdout_log: path.join(final.dir, final.attempt ? 'stdout_restart.log' : 'stdout.log'),
      godot_log: final.godotLog,
      cmdline: final.cmdline,
      started_s: rel(final.started),
      exited_s: rel(final.proc.ended),
      events: Array.isArray(r?.events) ? r.events : [],
      directives: Array.isArray(r?.directives) ? r.directives : [],
      trace: Array.isArray(r?.trace) ? r.trace : [],
      fit_paths: Array.isArray(r?.fit_paths) ? r.fit_paths.map(String) : [],
      uploads: Array.isArray(r?.uploads) ? r.uploads : [],
      final_state: r?.final_state ?? null,
      desync_warnings: r?.desync_warnings ?? null,
      script_errors: r?.script_errors ?? null,
      log_errors: scan.errors.slice(0, 20),
      log_error_count: scan.errors.length,
      desync_lines: scan.desync.slice(0, 10),
      rate_limited: scan.rateLimited.length,
      refused: scan.refused.length,
      restarted: list.length > 1,
      earlier_runs: earlier,
      auto_upload: role === o.autoUpload,
      content_id: r?.content_id ?? null,
      room: r?.room ?? null,
    };
  }
  const cooldownObs = runs.host ? C.observedCooldownS(runs.host[0].proc.lines) : null;
  timings.cooldown_observed_s = cooldownObs;
  timings.duration_excl_cooldown_s = Math.round(C.durationExclCooldown((t1 - t0) / 1000, cooldownObs, o.cooldownS) * 10) / 10;

  // ------------------------------------------------------------------ checks
  if (flowError) add('run', false, flowError);
  else add('run', true, `room ${code}, ${PEER_ROLES.length} peers, ${VICTIM} killed and restarted`);
  const have = PEER_ROLES.filter((r) => peers[r]);
  const fitRuns = {};
  if (!flowError) {
    const exitBad = have.filter((r) => peers[r].exit_code !== 0).map((r) => `${r} exited with ${peers[r].exit_code}`);
    add('peers_exit', exitBad.length === 0, exitBad.length ? exitBad : 'every peer quit with exit code 0');
    const repBad = have.filter((r) => peers[r].report_error).map((r) => `${r}: ${peers[r].report_error}`);
    add('reports', repBad.length === 0 && have.length === PEER_ROLES.length, repBad.length ? repBad : 'every peer wrote its report');

    const errs = [];
    for (const r of have) {
      const p = peers[r];
      if (p.log_error_count) errs.push(`${r}: ${p.log_error_count} error line(s), first: ${p.log_errors[0]}`);
      if (Number(p.script_errors) > 0) errs.push(`${r}: report.script_errors = ${p.script_errors}`);
      for (const e of p.earlier_runs) if (e.log_errors.length) errs.push(`${r} (killed run): ${e.log_errors.length} error line(s), first: ${e.log_errors[0]}`);
    }
    add('script_errors', errs.length === 0, errs.length ? errs : 'no SCRIPT ERROR, Parse Error or push_error output');

    const des = [];
    for (const r of have) {
      const p = peers[r];
      if (p.desync_warnings === null) des.push(`${r}: report has no desync_warnings`);
      else if (Number(p.desync_warnings) !== 0) des.push(`${r}: ${p.desync_warnings} desync warning(s)`);
      if (p.desync_lines.length) des.push(`${r}: ${p.desync_lines[0]}`);
    }
    add('desync', des.length === 0, des.length ? des : 'no desync warnings');

    const rl = have.filter((r) => peers[r].rate_limited || peers[r].earlier_runs.some((e) => e.rate_limited)).map((r) => `${r} saw rate_limited`);
    if (relay && C.scanLog(relay.proc.lines.map((e) => e.line)).rateLimited.length) rl.push('the relay logged rate_limited');
    add('rate_limited', rl.length === 0, rl.length ? rl : 'no rate_limited');

    const ev = C.checkSameEvents(Object.fromEntries(have.map((r) => [r, peers[r].events])), { reference: 'host', partial: [VICTIM], peerIds: Object.fromEntries(have.map((r) => [r, peers[r].peer_id])) });
    add('same_events', ev.ok, ev.details);

    const fs_ = C.checkFinalState(Object.fromEntries(have.map((r) => [r, peers[r].final_state])), { reference: 'host' });
    add('final_state', fs_.ok, fs_.details);

    const dir = C.checkDirectives(Object.fromEntries(have.map((r) => [r, peers[r]])), { reference: 'host', partial: [VICTIM] });
    add('directives_clamped', dir.ok, dir.ok ? [`${dir.total} applied record(s), each clamped by its rider's governor`, ...dir.warnings] : [...dir.problems, ...dir.warnings]);

    const wu = [];
    let wuOk = true;
    for (const r of have) {
      const w = C.checkWarmup(peers[r].trace, peers[r].directives);
      if (!w.ok) {
        wuOk = false;
        wu.push(...w.violations.slice(0, 5).map((v) => `${r}: ${v}`));
      } else {
        wu.push(`${r}: ${w.erg} ERG and ${w.sim} SIM trace entries inside the warm-up limits`);
      }
    }
    add('warmup_limits', wuOk, wu);

    const mt = [];
    for (const list of Object.values(runs)) for (const run of list) if (!run.userArgs.some((a) => a.startsWith('--mock-trainer='))) mt.push(`${run.role} ran without --mock-trainer`);
    add('mock_trainer', mt.length === 0, mt.length ? mt : `every peer rode --mock-trainer=${o.mockTrainer}`);

    const up = C.checkUploads(uploads, Object.fromEntries(have.map((r) => [r, peers[r]])), o.autoUpload);
    add('strava_upload', up.ok, up.details);

    const rc = [];
    const v = runs[VICTIM] ?? [];
    if (v.length < 2) rc.push(`${VICTIM} was not restarted`);
    else {
      const first = v[0];
      const second = v[1];
      if (!first.proc.killed) rc.push(`${VICTIM}'s first run was not killed by the harness`);
      const before = first.peerIdBeforeKill;
      const after = lastMatch(second.proc, PEER_RE)?.[1] ?? (peers[VICTIM]?.peer_id != null ? String(peers[VICTIM].peer_id) : null);
      if (before === null) rc.push(`${VICTIM} printed no WATTLANDS_PEER before it was killed`);
      if (after === null) rc.push(`${VICTIM} printed no WATTLANDS_PEER after its restart`);
      if (before !== null && after !== null && String(before) !== String(after)) rc.push(`${VICTIM} came back as peer ${after}, not ${before}`);
      if (peers[VICTIM]?.refused) rc.push(`${VICTIM} was refused with session_in_progress`);
      if (second.proc.exitCode !== 0) rc.push(`${VICTIM}'s restarted run exited with ${second.proc.exitCode}`);
      if (!C.comparableEvents(peers[VICTIM]?.events).some((e) => C.eventType(e) === 'results')) rc.push(`${VICTIM}'s restarted run never got the results`);
    }
    const rcOk = rc.length === 0;
    if (rcOk) rc.push(`${VICTIM} rejoined as peer ${lastMatch(v[1].proc, PEER_RE)?.[1] ?? peers[VICTIM]?.peer_id} and finished`);
    add('reconnect', rcOk, rc);

    const fitDetails = [];
    let fitOk = true;
    for (const r of have) {
      const p = peers[r];
      const existing = p.fit_paths.filter((f) => fs.existsSync(f));
      if (p.fit_paths.length === 0) {
        fitOk = false;
        fitDetails.push(`${r}: report lists no FIT file`);
        continue;
      }
      if (existing.length !== p.fit_paths.length) {
        fitOk = false;
        fitDetails.push(`${r}: missing FIT file(s): ${p.fit_paths.filter((f) => !existing.includes(f)).join(', ')}`);
      }
      if (existing.length === 0) continue;
      const fc = await runFitCheck(o, r, existing, lease, outDir);
      fitRuns[r] = fc;
      if (!fc.ok) {
        fitOk = false;
        fitDetails.push(`${r}: ${fc.label} exited ${fc.code}${fc.timedOut ? ' (timeout)' : ''}: ${fc.errors.slice(0, 3).join('; ') || fc.tail.slice(-3).join(' | ')}`);
      } else {
        fitDetails.push(`${r}: ${existing.length} FIT file(s) valid (${fc.label})`);
      }
    }
    add('fit_files', fitOk && have.length === PEER_ROLES.length, fitDetails);

    const dur = timings.duration_excl_cooldown_s;
    add('duration', dur <= o.maxDurationS, `${dur} s excluding the cool-down (limit ${o.maxDurationS} s; total ${timings.total_s} s)`);
  }

  // ------------------------------------------------------------------ report
  const report = {
    schema: REPORT_SCHEMA,
    game_id: gameId,
    content_id: content,
    seed: o.seed,
    room: code,
    ok: false,
    failures: [],
    checks,
    timings,
    services: {
      relay: relay ? { url: relay.url, cmd: quoteForLog(relay.cmdline), log: serviceLog(outDir, 'relay') } : null,
      mock_strava: strava ? { base: strava.base, cmd: quoteForLog(strava.cmdline), log: serviceLog(outDir, 'mock_strava'), uploads } : null,
    },
    auto_upload_peer: o.autoUpload,
    victim: VICTIM,
    peers,
    events_by_peer: Object.fromEntries(have.map((r) => [String(peers[r].peer_id ?? r), peers[r].events])),
    directives: have.flatMap((r) => peers[r].directives.map((d) => ({ peer_role: r, ...d }))),
    fit_paths: Object.fromEntries(have.map((r) => [r, peers[r].fit_paths])),
    fit_check: fitRuns,
    e2e_check: null,
  };
  const finish = () => {
    report.failures = checks.filter((c) => !c.ok).map((c) => `${c.name}: ${c.details.join('; ')}`);
    report.ok = report.failures.length === 0;
    writeJson(reportPath, report);
  };
  finish();

  const checkFile = path.join(o.repo, 'tests', 'games', gameId, 'e2e_check.mjs');
  if (!flowError && fs.existsSync(checkFile)) {
    const r = await runToEnd('e2e_check', process.execPath, [checkFile, reportPath], {
      cwd: o.repo,
      env: childEnv(process.env),
      timeoutMs: 120_000,
      logFile: path.join(outDir, 'e2e_check.log'),
      echo: echo('e2e_check'),
    });
    report.e2e_check = { path: checkFile, exit_code: r.code, timed_out: r.timedOut, output: r.lines.slice(-40) };
    add('e2e_check', r.code === 0, r.code === 0 ? `${path.relative(o.repo, checkFile)} passed` : `${path.relative(o.repo, checkFile)} exited ${r.code}${r.timedOut ? ' (timeout)' : ''}: ${r.lines.slice(-3).join(' | ')}`);
    finish();
  }
  return { gameId, ok: report.ok, failures: report.failures, reportPath, durationS: timings.duration_excl_cooldown_s, checks };
}

/**
 * Runs the FIT checker on one peer's files: tools/fit_check/check.mjs (or --fit-check-cmd), else
 * the GDScript decoder through tools/godot.sh. Both run with the lease token, so a checker that
 * falls back to Godot runs inside the held lease. Returns {ok, code, timedOut, label, json, errors, tail}.
 */
export async function runFitCheck(o, role, files, lease, outDir) {
  const dir = path.join(outDir, role);
  fs.mkdirSync(dir, { recursive: true });
  const jsonOut = slash(path.join(dir, 'fit_check.json'));
  fs.rmSync(jsonOut, { force: true });
  const checkMjs = path.join(o.repo, 'tools', 'fit_check', 'check.mjs');
  let cmd;
  let args;
  let label;
  if (o.fitCheckCmd) {
    const t = tokenize(o.fitCheckCmd);
    cmd = resolveProgram(t[0]);
    args = [...t.slice(1), ...files, '--json'];
    label = o.fitCheckCmd;
  } else if (fs.existsSync(checkMjs)) {
    cmd = process.execPath;
    args = [checkMjs, ...files, '--json'];
    label = 'tools/fit_check/check.mjs';
  } else {
    const bash = findBash();
    if (!bash) return { ok: false, code: null, timedOut: false, label: 'fit_decode', json: null, errors: ['bash not found'], tail: [] };
    cmd = bash;
    args = [slash(path.join(o.repo, 'tools', 'godot.sh')), '--timeout=300', '--headless', '--path', slash(o.repo), '-s', 'tools/fit_decode/decode.gd', '--', ...files.map(slash), '--json', `--out=${jsonOut}`];
    label = 'tools/fit_decode/decode.gd';
  }
  const r = await runToEnd(`fit_check_${role}`, cmd, args, {
    cwd: o.repo,
    env: childEnv(process.env, leaseEnv(lease)),
    timeoutMs: 300_000,
    logFile: path.join(dir, 'fit_check.log'),
  });
  let json = null;
  const fromFile = readJson(jsonOut);
  if (fromFile.ok) json = fromFile.value;
  else {
    for (let i = r.lines.length - 1; i >= 0 && json === null; i--) {
      const line = r.lines[i].trim();
      if (!line.startsWith('{')) continue;
      try {
        json = JSON.parse(line);
      } catch {
        // keep looking
      }
    }
  }
  const errors = [];
  if (isObj(json) && Array.isArray(json.files)) {
    for (const f of json.files) {
      if (isObj(f) && Array.isArray(f.errors)) for (const e of f.errors) errors.push(`${path.basename(String(f.path ?? f.file ?? ''))}: ${e}`);
    }
  }
  const ok = r.code === 0 && !r.timedOut && errors.length === 0;
  return { ok, code: r.code, timedOut: r.timedOut, label, json, errors, tail: r.lines.slice(-20) };
}
