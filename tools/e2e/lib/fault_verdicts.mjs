// tools/e2e/lib/fault_verdicts.mjs: what one peer did, and the pass/fail checks a fault scenario
// makes of it (pure, unit-tested from fake peer outputs). docs/ARCHITECTURE.md "Scripted peers"
// has the WATTLANDS_* lines; the exit codes are the top of src/app/scripted/scripted_peer.gd.
import path from 'node:path';
import { scanLog } from './checks.mjs';

export const EXIT = Object.freeze({ OK: 0, ERROR: 1, TIMEOUT: 2, REFUSED: 3, HOST_LEFT: 4 });
const EXIT_NAMES = { 0: 'complete', 1: 'error', 2: 'run_seconds', 3: 'refused', 4: 'host_left' };

export const ROOM_LINE = /^WATTLANDS_ROOM\s+(\S+)/;
export const PEER_LINE = /^WATTLANDS_PEER\s+(-?\d+)/;
export const STATE_LINE = /^WATTLANDS_STATE\s+(\S+)/;
export const DONE_LINE = /^WATTLANDS_DONE\b\s*(.*)$/;
/** The states that mean the session itself began (the lobby is over). */
export const SESSION_STATES = ['setup', 'running', 'warmup', 'riding', 'session', 'playing', 'started', 'in_session'];

export function describeExit(code) {
  if (code === null || code === undefined) return 'no exit code';
  return EXIT_NAMES[code] ? `${code} (${EXIT_NAMES[code]})` : String(code);
}

function lastOf(lines, re) {
  let m = null;
  for (const l of lines) {
    const x = re.exec(l);
    if (x) m = x;
  }
  return m;
}

/**
 * The outcome of one peer process run.
 * raw: {name, role, exitCode, killed, lines (stdout and stderr), logLines (the Godot log),
 *       report (parsed JSON or null), reportError, fitExists ({path: bool}), startedS, endedS}.
 */
export function peerOutcome(raw) {
  const lines = raw.lines ?? [];
  const all = [...lines, ...(raw.logLines ?? [])];
  const scan = scanLog(all);
  const rep = raw.report && typeof raw.report === 'object' ? raw.report : null;
  const done = lastOf(lines, DONE_LINE);
  const states = lines.map((l) => STATE_LINE.exec(l)?.[1]).filter(Boolean);
  const fitPaths = Array.isArray(rep?.fit_paths) ? rep.fit_paths.map(String) : [];
  const peerLine = lastOf(lines, PEER_LINE)?.[1] ?? null;
  const exitReason = rep?.exit_reason ?? done?.[1] ?? null;
  return {
    name: raw.name,
    role: raw.role,
    exitCode: raw.exitCode ?? null,
    killed: Boolean(raw.killed),
    exited: raw.exitCode !== null && raw.exitCode !== undefined,
    room: lastOf(lines, ROOM_LINE)?.[1] ?? rep?.room ?? null,
    peerId: peerLine !== null ? Number(peerLine) : rep?.peer_id ?? null,
    states,
    sawSession: states.some((s) => SESSION_STATES.includes(s)),
    doneLine: done ? done[0] : null,
    exitReason,
    refusedReason: typeof exitReason === 'string' && exitReason.startsWith('refused:') ? exitReason.slice('refused:'.length) : null,
    report: rep,
    reportError: raw.reportError ?? (rep ? null : 'no report'),
    errorLines: scan.errors,
    desyncLines: scan.desync,
    rateLimited: scan.rateLimited.length,
    scriptErrors: Number.isFinite(Number(rep?.script_errors)) ? Number(rep.script_errors) : null,
    desyncWarnings: Number.isFinite(Number(rep?.desync_warnings)) ? Number(rep.desync_warnings) : null,
    fitPaths,
    fitMissing: fitPaths.filter((f) => raw.fitExists?.[f] !== true),
    fitCheck: raw.fitCheck ?? null,
    startedS: raw.startedS ?? null,
    endedS: raw.endedS ?? null,
    lines,
    logLines: raw.logLines ?? [],
  };
}

const chk = (name, ok, details) => ({ name, ok: Boolean(ok), details: Array.isArray(details) ? details : [String(details)] });

/** The peer exited with one of `codes`, and (when given) with a matching exit reason. */
export function checkExit(out, { label = out.name, codes, reason = null }) {
  const want = codes.map(describeExit).join(' or ');
  if (!out.exited) return chk(`${label} exit`, false, `${label} did not exit (wanted ${want})`);
  if (!codes.includes(out.exitCode)) {
    return chk(`${label} exit`, false, `${label} exited ${describeExit(out.exitCode)}, wanted ${want}${out.exitReason ? `; reason ${out.exitReason}` : ''}${out.doneLine ? `; ${out.doneLine}` : ''}`);
  }
  if (reason !== null) {
    const re = reason instanceof RegExp ? reason : new RegExp(`^${String(reason).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`);
    if (!re.test(out.exitReason ?? '')) {
      return chk(`${label} exit`, false, `${label} exited ${describeExit(out.exitCode)} with reason "${out.exitReason ?? ''}", wanted ${re}`);
    }
  }
  return chk(`${label} exit`, true, `${label} exited ${describeExit(out.exitCode)}${out.exitReason ? ` (${out.exitReason})` : ''}`);
}

/** The peer wrote its report and left no script error, push_error line or desync warning (beyond `allow`). */
export function checkClean(out, { label = out.name, allow = [], needReport = true } = {}) {
  const problems = [];
  const bad = out.errorLines.filter((l) => !allow.some((re) => re.test(l)));
  if (bad.length) problems.push(`${label}: ${bad.length} error line(s), first: ${bad[0]}`);
  if (out.scriptErrors) problems.push(`${label}: report.script_errors = ${out.scriptErrors}`);
  if (out.desyncLines.length) problems.push(`${label}: ${out.desyncLines[0]}`);
  if (out.desyncWarnings) problems.push(`${label}: ${out.desyncWarnings} desync warning(s)`);
  if (out.rateLimited) problems.push(`${label}: saw rate_limited`);
  if (needReport && !out.report) problems.push(`${label}: ${out.reportError ?? 'no report'}`);
  const allowed = out.errorLines.length - bad.length;
  return chk(`${label} clean`, problems.length === 0, problems.length ? problems : `${label}: no script error or push_error${allowed ? ` (${allowed} expected line(s) ignored)` : ''}, report written`);
}

/** The peer's ride is on disk: fit_paths in its report, every file present and (if checked) valid. */
export function checkFit(out, { label = out.name } = {}) {
  const problems = [];
  if (out.fitPaths.length === 0) problems.push(`${label}: report lists no FIT file`);
  if (out.fitMissing.length) problems.push(`${label}: missing FIT file(s): ${out.fitMissing.map((f) => path.basename(f)).join(', ')}`);
  if (out.fitCheck && out.fitCheck.ok === false) problems.push(`${label}: FIT check failed: ${(out.fitCheck.errors ?? []).slice(0, 3).join('; ') || `exit ${out.fitCheck.code}`}`);
  const checked = out.fitCheck?.ok ? ', checked' : '';
  return chk(`${label} fit`, problems.length === 0, problems.length ? problems : `${label}: ${out.fitPaths.length} FIT file(s) present${checked}`);
}

/** The peer printed a WATTLANDS_STATE of `states` (any of them). */
export function checkState(out, states, { label = out.name } = {}) {
  const ok = out.states.some((s) => states.includes(s));
  return chk(`${label} state`, ok, ok ? `${label} reached ${out.states.filter((s) => states.includes(s))[0]} (states: ${out.states.join(' > ')})` : `${label} never reached ${states.join('/')} (states: ${out.states.join(' > ') || 'none'})`);
}

/** The killed run and the restarted run had the same WATTLANDS_PEER id. */
export function checkSamePeer(before, after, { label = 'restarted client' } = {}) {
  if (before.peerId === null) return chk(`${label} same peer`, false, `${label}: the first run printed no WATTLANDS_PEER`);
  if (after.peerId === null) return chk(`${label} same peer`, false, `${label}: the restarted run printed no WATTLANDS_PEER`);
  const ok = Number(before.peerId) === Number(after.peerId);
  return chk(`${label} same peer`, ok, ok ? `${label}: peer ${after.peerId} before the kill and after the restart` : `${label} came back as peer ${after.peerId}, not ${before.peerId}`);
}

/** The peer was not refused (a rejoin must not hit session_in_progress). */
export function checkNotRefused(out, { label = out.name } = {}) {
  const refused = out.refusedReason !== null || out.lines.some((l) => /session_in_progress/.test(l));
  return chk(`${label} not refused`, !refused, refused ? `${label} was refused: ${out.exitReason ?? 'session_in_progress in its output'}` : `${label} was not refused`);
}

/**
 * Wraps a scenario's checks into its verdict: {name, ok, failures, checks, evidence}.
 * A scenario passes only when it has at least one check and every check passed.
 */
export function scenarioVerdict(name, checks, evidence = {}) {
  const failures = checks.filter((c) => !c.ok).map((c) => `${c.name}: ${c.details.join('; ')}`);
  const ok = checks.length > 0 && failures.length === 0;
  if (checks.length === 0) failures.push('the scenario made no checks');
  return { name, ok, failures, checks, evidence };
}

/** The process exit code and one-line summary of a whole run. */
export function runVerdict(results, { lockTimeout = false } = {}) {
  if (lockTimeout) return { code: 75, line: 'faults: Godot lock wait timeout' };
  const failed = results.filter((r) => !r.ok);
  const line = `faults: ${results.length - failed.length} of ${results.length} scenario(s) passed${failed.length ? `; failed: ${failed.map((r) => r.name).join(', ')}` : ''}`;
  return { code: failed.length || results.length === 0 ? 1 : 0, line };
}

/** The scripted-peer flags after "--" for one fault peer (docs/ARCHITECTURE.md "Scripted peers"). */
export function faultPeerArgs(o, spec) {
  const a = [];
  if (spec.role === 'host') {
    a.push('--host');
    if (spec.content) a.push(`--content=${spec.content}`);
  } else {
    a.push(`--join=${spec.code}`);
  }
  a.push(`--game=${spec.gameId}`, '--e2e', `--wait-peers=${o.waitPeers}`);
  if (spec.relayUrl) a.push(`--relay=${spec.relayUrl}`);
  if (spec.lan) {
    if (spec.role === 'host' && spec.lan.port) a.push(`--lan-port=${spec.lan.port}`);
    if (spec.lan.discoveryPort) a.push(`--lan-discovery-port=${spec.lan.discoveryPort}`);
  }
  a.push(
    `--mock-trainer=${o.mockTrainer}`,
    '--autopilot',
    `--profile-dir=${spec.profileDir}`,
    '--sim-speed=1',
    `--seed=${o.seed}`,
    `--report=${spec.reportPath}`,
  );
  if (spec.runSeconds) a.push(`--run-seconds=${spec.runSeconds}`);
  return a;
}
