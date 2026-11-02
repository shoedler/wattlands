// tools/e2e/lib/fault_scenarios.mjs: the multiplayer failure scenarios of tools/e2e/faults.mjs.
// Each scenario drives real headless peers through a FaultEnv and returns {checks, peers}; the
// verdict logic is in fault_verdicts.mjs. What each scenario expects is in its header comment and
// in tools/e2e/README.md.
import { familyOf } from './fault_args.mjs';
import {
  EXIT, SESSION_STATES, checkClean, checkExit, checkFit, checkNotRefused, checkSamePeer, checkState,
} from './fault_verdicts.mjs';
import { sleep } from './util.mjs';

/** A code no room has: valid Crockford, and a fresh relay hands out random ones. */
export const MISSING_CODE = 'ZZZZZZ';

/** The game the relay scenarios play: the one with a 3 minute cool-down to ride out. */
export const RELAY_GAME = 'workout';

/** Error lines a fault scenario expects (none by default: a failure path must not push_error). */
export const EXPECTED_ERRORS = [];

/** A compact record of one peer's outcome for report.json. */
export function peerEvidence(out, run) {
  return {
    name: out.name,
    role: out.role,
    exit_code: out.exitCode,
    exit_reason: out.exitReason,
    killed_by_harness: out.killed,
    done_line: out.doneLine,
    peer_id: out.peerId,
    room: out.room,
    states: out.states,
    started_s: out.startedS,
    exited_s: out.endedS,
    report_path: run?.reportPath ?? null,
    stdout_log: run ? `${run.dir}/stdout${run.attempt ? `_${run.attempt + 1}` : ''}.log` : null,
    godot_log: run?.godotLog ?? null,
    cmdline: run?.cmdline ?? null,
    error_lines: out.errorLines.slice(0, 10),
    script_errors: out.scriptErrors,
    desync_warnings: out.desyncWarnings,
    fit_paths: out.fitPaths,
    fit_check: out.fitCheck,
    report_error: out.reportError,
  };
}

async function finish(env, runs, checks, { fit = true } = {}) {
  const outs = [];
  for (const r of runs) outs.push(await env.outcome(r, { fit }));
  return { outs, evidence: outs.map((o, i) => peerEvidence(o, runs[i])) };
}

function lateNote(late, what) {
  return late.length ? `${late.map((r) => r.name).join(', ')} did not end within ${what}` : null;
}

// ---------------------------------------------------------------------------------- builtin

/**
 * builtin:<game>: the host runs no --relay, so it hosts on its own PC (LanTransport, loopback
 * while the network lock is set); a client joins by code from the beacons; the session starts; the
 * client is killed and restarted inside the window and comes back as the same peer. --run-seconds
 * ends it: the host stops with run_seconds, the restarted client with run_seconds or host_left.
 */
export async function builtinScenario(env) {
  const gameId = env.name.split(':')[1];
  const o = env.o;
  const checks = [];
  await env.useBuiltin();
  const { host, code } = await env.startHost({ gameId, runSeconds: o.runSeconds });
  const first = env.spawnPeer({ role: 'client', base: 'client', gameId, code, runSeconds: o.runSeconds });
  await env.inRoom(first);
  await env.inSession(first);
  await sleep(o.killAfterS * 1000);
  if (first.proc.closed) throw new Error(`the client exited (code ${first.proc.exitCode}) before it could be killed`);
  await env.killPeer(first, 'killing the client in the session');
  await sleep(o.restartDelayS * 1000);
  const second = env.spawnPeer({ role: 'client', base: 'client', gameId, code, runSeconds: o.runSeconds });
  await env.inRoom(second);
  await env.inSession(second);
  const late = await env.waitAll([host, second], o.endTimeoutS * 1000);
  const { outs } = await finish(env, [host, first, second], checks);
  const [h, c1, c2] = outs;
  if (lateNote(late, `${o.endTimeoutS} s`)) checks.push({ name: 'peers end', ok: false, details: [lateNote(late, `${o.endTimeoutS} s`)] });
  checks.push(checkState(h, SESSION_STATES, { label: 'host' }));
  checks.push(checkState(c1, SESSION_STATES, { label: 'client' }));
  checks.push(checkExit(h, { label: 'host', codes: [EXIT.TIMEOUT], reason: 'run_seconds' }));
  checks.push(checkState(c2, SESSION_STATES, { label: 'restarted client' }));
  checks.push(checkSamePeer(c1, c2));
  checks.push(checkNotRefused(c2, { label: 'restarted client' }));
  checks.push(checkExit(c2, { label: 'restarted client', codes: [EXIT.TIMEOUT, EXIT.HOST_LEFT], reason: /^(run_seconds|host_left)$/ }));
  checks.push(checkClean(h, { label: 'host', allow: EXPECTED_ERRORS }));
  checks.push(checkClean(c1, { label: 'killed client', allow: EXPECTED_ERRORS, needReport: false }));
  checks.push(checkClean(c2, { label: 'restarted client', allow: EXPECTED_ERRORS }));
  checks.push(checkFit(h, { label: 'host' }));
  checks.push(checkFit(c2, { label: 'restarted client' }));
  return { checks, peers: outs.map((x, i) => peerEvidence(x, [host, first, second][i])) };
}

// ---------------------------------------------------------------------------------- wrong_code

/**
 * wrong_code:relay|builtin: a client joining a code that no room has exits 3 with the reason
 * room_not_found, while a real room waits in its lobby, unharmed.
 */
export async function wrongCodeScenario(env) {
  const variant = env.name.split(':')[1];
  const o = env.o;
  const checks = [];
  if (variant === 'relay') await env.startRelay();
  else await env.useBuiltin();
  const { host, code } = await env.startHost({ gameId: RELAY_GAME, runSeconds: 0 });
  if (code.replace(/-/g, '') === MISSING_CODE) throw new Error('the host got the code the test meant to be missing');
  await env.inRoom(host);
  const stray = env.spawnPeer({ role: 'client', base: 'stray', gameId: RELAY_GAME, code: MISSING_CODE, runSeconds: 0 });
  const late = await env.waitAll([stray], o.endTimeoutS * 1000);
  await sleep(2000);
  const hostAlive = !host.proc.closed;
  const { outs } = await finish(env, [stray], checks, { fit: false });
  const [s] = outs;
  if (lateNote(late, `${o.endTimeoutS} s`)) checks.push({ name: 'client ends', ok: false, details: [lateNote(late, `${o.endTimeoutS} s`)] });
  checks.push(checkExit(s, { label: 'stray client', codes: [EXIT.REFUSED], reason: 'refused:room_not_found' }));
  checks.push(checkClean(s, { label: 'stray client', allow: EXPECTED_ERRORS }));
  checks.push({
    name: 'room unharmed',
    ok: hostAlive,
    details: [hostAlive ? 'the real room still waits in its lobby after the refusal' : `the host exited (code ${host.proc.exitCode}) when a client asked for a missing code`],
  });
  await env.killPeer(host, 'stopping the waiting host');
  const [h] = (await finish(env, [host], checks, { fit: false })).outs;
  checks.push(checkClean(h, { label: 'host', allow: EXPECTED_ERRORS, needReport: false }));
  return { checks, peers: [peerEvidence(s, stray), peerEvidence(h, host)] };
}

// ---------------------------------------------------------------------------------- late_join

/**
 * late_join:relay|builtin: a third peer with a fresh profile joins a running room: it exits 3 with
 * session_in_progress, and the host and the first client keep riding (alive after the refusal, no
 * error, a FIT each) to the --run-seconds stop.
 */
export async function lateJoinScenario(env) {
  const variant = env.name.split(':')[1];
  const o = env.o;
  const checks = [];
  if (variant === 'relay') await env.startRelay();
  else await env.useBuiltin();
  const { host, code } = await env.startHost({ gameId: RELAY_GAME, runSeconds: o.runSeconds });
  const client = env.spawnPeer({ role: 'client', base: 'client', gameId: RELAY_GAME, code, runSeconds: o.runSeconds });
  await env.inRoom(client);
  await env.inSession(client);
  await env.inSession(host);
  await sleep(o.killAfterS * 1000);
  const late = env.spawnPeer({ role: 'client', base: 'late', gameId: RELAY_GAME, code, runSeconds: o.runSeconds });
  const lateEnded = await env.waitAll([late], o.endTimeoutS * 1000);
  await sleep(5000);
  const stillRiding = !host.proc.closed && !client.proc.closed;
  env.note(`after the refusal: host ${host.proc.closed ? 'gone' : 'riding'}, client ${client.proc.closed ? 'gone' : 'riding'}`);
  const rest = await env.waitAll([host, client], o.endTimeoutS * 1000);
  const { outs } = await finish(env, [host, client, late], checks);
  const [h, c, l] = outs;
  if (lateNote(lateEnded, `${o.endTimeoutS} s`)) checks.push({ name: 'third peer ends', ok: false, details: [lateNote(lateEnded, `${o.endTimeoutS} s`)] });
  if (lateNote(rest, `${o.endTimeoutS} s`)) checks.push({ name: 'peers end', ok: false, details: [lateNote(rest, `${o.endTimeoutS} s`)] });
  checks.push(checkExit(l, { label: 'third peer', codes: [EXIT.REFUSED], reason: 'refused:session_in_progress' }));
  checks.push(checkClean(l, { label: 'third peer', allow: EXPECTED_ERRORS }));
  checks.push({
    name: 'session unharmed',
    ok: stillRiding,
    details: [stillRiding ? 'the host and the first client were still riding 5 s after the refusal' : 'the host or the first client was gone 5 s after the third peer was refused'],
  });
  checks.push(checkExit(h, { label: 'host', codes: [EXIT.TIMEOUT], reason: 'run_seconds' }));
  checks.push(checkExit(c, { label: 'client', codes: [EXIT.TIMEOUT, EXIT.HOST_LEFT], reason: /^(run_seconds|host_left)$/ }));
  checks.push(checkClean(h, { label: 'host', allow: EXPECTED_ERRORS }));
  checks.push(checkClean(c, { label: 'client', allow: EXPECTED_ERRORS }));
  checks.push(checkFit(h, { label: 'host' }));
  checks.push(checkFit(c, { label: 'client' }));
  return { checks, peers: outs.map((x, i) => peerEvidence(x, [host, client, late][i])) };
}

// ---------------------------------------------------------------------------------- relay faults

async function startRelayRoom(env, { builtin }) {
  if (builtin) await env.useBuiltin();
  else await env.startRelay();
  const { host, code } = await env.startHost({ gameId: RELAY_GAME, runSeconds: 0 });
  const client = env.spawnPeer({ role: 'client', base: 'client', gameId: RELAY_GAME, code, runSeconds: 0 });
  await env.inRoom(client);
  await env.inSession(client);
  await env.inSession(host);
  await sleep(env.o.killAfterS * 1000);
  return { host, client, code };
}

/**
 * What a peer that lost its room for good must do: end by itself, keep a FIT, write its report,
 * and print no error. `codes` lists the exit codes a clean end may have.
 */
function lostRoomChecks(h, c, { hostCodes, clientCodes, clientCooldown = true }) {
  const checks = [];
  checks.push(checkExit(h, { label: 'host', codes: hostCodes }));
  checks.push(checkExit(c, { label: 'client', codes: clientCodes }));
  if (clientCooldown) checks.push(checkState(c, ['cooldown'], { label: 'client' }));
  checks.push(checkClean(h, { label: 'host', allow: EXPECTED_ERRORS }));
  checks.push(checkClean(c, { label: 'client', allow: EXPECTED_ERRORS }));
  checks.push(checkFit(h, { label: 'host' }));
  checks.push(checkFit(c, { label: 'client' }));
  return checks;
}

/**
 * relay_dies: workout on server/relay; the relay is killed mid-session and stays dead. Both peers
 * retry for the token's 120 s, then the client rides its cool-down here and ends, saving a FIT, and
 * the host carries on to its results.
 */
export async function relayDiesScenario(env) {
  const o = env.o;
  const { host, client } = await startRelayRoom(env, { builtin: false });
  await env.killRelay('killing the relay for good');
  const killedAt = env.now();
  const late = await env.waitAll([host, client], o.longTimeoutS * 1000);
  const { outs, evidence } = await finish(env, [host, client], []);
  const [h, c] = outs;
  const checks = [];
  if (lateNote(late, `${o.longTimeoutS} s`)) checks.push({ name: 'peers end', ok: false, details: [lateNote(late, `${o.longTimeoutS} s`)] });
  checks.push(...lostRoomChecks(h, c, { hostCodes: [EXIT.OK, EXIT.REFUSED, EXIT.HOST_LEFT], clientCodes: [EXIT.REFUSED, EXIT.HOST_LEFT] }));
  checks.push(timing('after the relay died', killedAt, h, c));
  return { checks, peers: evidence };
}

/**
 * relay_restarts: the relay is killed and started again on the same port, so its rooms are gone.
 * Every peer's rejoin gets room_not_found; each must still end by itself with a FIT and no error.
 */
export async function relayRestartsScenario(env) {
  const o = env.o;
  const { host, client } = await startRelayRoom(env, { builtin: false });
  const port = env.relay.port;
  await env.killRelay('killing the relay, to start it again');
  await sleep(2000);
  await env.startRelay({ port });
  const restartedAt = env.now();
  const late = await env.waitAll([host, client], o.longTimeoutS * 1000);
  const { outs, evidence } = await finish(env, [host, client], []);
  const [h, c] = outs;
  const checks = [];
  if (lateNote(late, `${o.longTimeoutS} s`)) checks.push({ name: 'peers end', ok: false, details: [lateNote(late, `${o.longTimeoutS} s`)] });
  checks.push(...lostRoomChecks(h, c, { hostCodes: [EXIT.OK, EXIT.REFUSED, EXIT.HOST_LEFT], clientCodes: [EXIT.REFUSED, EXIT.HOST_LEFT] }));
  checks.push(timing('after the relay restarted', restartedAt, h, c));
  return { checks, peers: evidence };
}

/**
 * host_killed_relay: the host is killed on the relay. The relay holds the room 120 s, then sends
 * host_left: the client must end clean (host_left) with a FIT.
 */
export async function hostKilledRelayScenario(env) {
  const o = env.o;
  const { host, client } = await startRelayRoom(env, { builtin: false });
  await env.killPeer(host, 'killing the host');
  const killedAt = env.now();
  const late = await env.waitAll([client], o.longTimeoutS * 1000);
  const { outs, evidence } = await finish(env, [host, client], []);
  const [h, c] = outs;
  const checks = [];
  if (lateNote(late, `${o.longTimeoutS} s`)) checks.push({ name: 'client ends', ok: false, details: [lateNote(late, `${o.longTimeoutS} s`)] });
  checks.push(checkExit(c, { label: 'client', codes: [EXIT.HOST_LEFT, EXIT.REFUSED] }));
  checks.push(checkClean(c, { label: 'client', allow: EXPECTED_ERRORS }));
  checks.push(checkFit(c, { label: 'client' }));
  checks.push(checkClean(h, { label: 'killed host', allow: EXPECTED_ERRORS, needReport: false }));
  checks.push(timing('after the host was killed', killedAt, c));
  return { checks, peers: evidence };
}

/**
 * host_killed_builtin: the host is killed on the built-in relay, which dies with it. The client must
 * end clean; how long it took is in the evidence.
 */
export async function hostKilledBuiltinScenario(env) {
  const o = env.o;
  const { host, client } = await startRelayRoom(env, { builtin: true });
  await env.killPeer(host, 'killing the host');
  const killedAt = env.now();
  const late = await env.waitAll([client], o.longTimeoutS * 1000);
  const { outs, evidence } = await finish(env, [host, client], []);
  const [h, c] = outs;
  const checks = [];
  if (lateNote(late, `${o.longTimeoutS} s`)) checks.push({ name: 'client ends', ok: false, details: [lateNote(late, `${o.longTimeoutS} s`)] });
  checks.push(checkExit(c, { label: 'client', codes: [EXIT.HOST_LEFT, EXIT.REFUSED] }));
  checks.push(checkClean(c, { label: 'client', allow: EXPECTED_ERRORS }));
  checks.push(checkFit(c, { label: 'client' }));
  checks.push(checkClean(h, { label: 'killed host', allow: EXPECTED_ERRORS, needReport: false }));
  checks.push(timing('after the host was killed', killedAt, c));
  return { checks, peers: evidence };
}

/** An informational check: how long each peer lasted after the fault (always passes when they ended). */
function timing(label, faultAt, ...outs) {
  const parts = outs.map((o) => `${o.name} ${o.endedS === null ? 'did not end' : `ended ${Math.round((o.endedS - faultAt) * 10) / 10} s`}`);
  return { name: 'timing', ok: outs.every((o) => o.endedS !== null), details: [`${label}: ${parts.join(', ')}`] };
}

/** The scenario function for a scenario name. */
export function scenarioFor(name) {
  switch (familyOf(name)) {
    case 'builtin':
      return builtinScenario;
    case 'wrong_code':
      return wrongCodeScenario;
    case 'late_join':
      return lateJoinScenario;
    case 'relay_dies':
      return relayDiesScenario;
    case 'relay_restarts':
      return relayRestartsScenario;
    case 'host_killed_relay':
      return hostKilledRelayScenario;
    case 'host_killed_builtin':
      return hostKilledBuiltinScenario;
    default:
      return null;
  }
}
