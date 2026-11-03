// node:test for tools/e2e/faults.mjs: its command line and the scenario verdicts, from fake peer
// outputs (no Godot, no relay). tools/e2e/test/faults.test.mjs is run.mjs's fault suite.
import test from 'node:test';
import assert from 'node:assert/strict';
import { FAULT_GAMES, SCENARIO_FAMILIES, familyOf, parseFaultArgs, variantsOf } from '../lib/fault_args.mjs';
import {
  EXIT, checkClean, checkExit, checkFit, checkNoFlood, checkNotRefused, checkSamePeer, checkState, faultPeerArgs, peerOutcome,
  runVerdict, scenarioVerdict,
} from '../lib/fault_verdicts.mjs';

const stdout = (...extra) => ['WATTLANDS_PEER 2', 'WATTLANDS_STATE lobby', 'WATTLANDS_STATE running', ...extra];

function peer(over = {}) {
  return peerOutcome({
    name: 'client',
    role: 'client',
    exitCode: 0,
    lines: stdout('WATTLANDS_DONE complete'),
    logLines: [],
    report: { exit_reason: 'complete', peer_id: 2, fit_paths: ['/x/a.fit'], script_errors: 0, desync_warnings: 0 },
    fitExists: { '/x/a.fit': true },
    ...over,
  });
}

// ------------------------------------------------------------------------------- arguments

test('every scenario runs by default, builtin once per game', () => {
  const r = parseFaultArgs([]);
  assert.equal(r.ok, true);
  assert.deepEqual(r.names, [
    'builtin:fishing', 'builtin:siege', 'builtin:tank', 'builtin:workout',
    'wrong_code:relay', 'wrong_code:builtin', 'late_join:relay', 'late_join:builtin',
    'relay_dies', 'relay_restarts', 'host_killed_relay', 'host_killed_builtin',
  ]);
});

test('--games narrows the builtin scenario only', () => {
  const r = parseFaultArgs(['--games=tank,workout']);
  assert.deepEqual(r.names.filter((n) => n.startsWith('builtin')), ['builtin:tank', 'builtin:workout']);
  assert.ok(r.names.includes('relay_dies'));
  assert.equal(parseFaultArgs(['--games=chess']).ok, false);
  assert.match(parseFaultArgs(['--games=Chess']).error, /bad game id/);
});

test('--scenarios takes a family or one variant, in run order, without repeats', () => {
  const r = parseFaultArgs(['--scenarios=host_killed_builtin,wrong_code:builtin,late_join,wrong_code:builtin']);
  assert.deepEqual(r.names, ['wrong_code:builtin', 'late_join:relay', 'late_join:builtin', 'host_killed_builtin']);
  assert.equal(parseFaultArgs(['--scenarios=nope']).ok, false);
  assert.match(parseFaultArgs(['--scenarios=builtin:chess']).error, /unknown scenario/);
  assert.equal(parseFaultArgs(['--scenarios=']).ok, false);
});

test('the hardware and network locks are never dropped', () => {
  for (const f of ['--allow-hw', '--allow-network']) {
    const r = parseFaultArgs([f]);
    assert.equal(r.ok, false);
    assert.match(r.error, /never drops/);
  }
});

test('numbers, strings and unknown options are validated', () => {
  assert.equal(parseFaultArgs(['--run-seconds=40']).opts.runSeconds, 40);
  assert.equal(parseFaultArgs(['--run-seconds=2']).ok, false);
  assert.equal(parseFaultArgs(['--seed=1.5']).ok, false);
  assert.equal(parseFaultArgs(['--out=']).ok, false);
  assert.equal(parseFaultArgs(['--bogus=1']).ok, false);
  assert.equal(parseFaultArgs(['stray']).ok, false);
  assert.equal(parseFaultArgs(['--help']).help, true);
  const o = parseFaultArgs([]).opts;
  assert.equal(o.waitPeers, 2);
  assert.equal(o.mockTrainer, 'erg:compliance=1.0');
  assert.match(o.out.replaceAll('\\', '/'), /build\/e2e_faults$/);
});

test('variants and families', () => {
  assert.deepEqual(variantsOf('builtin', ['siege']), ['builtin:siege']);
  assert.deepEqual(variantsOf('relay_dies'), ['relay_dies']);
  assert.equal(familyOf('wrong_code:relay'), 'wrong_code');
  assert.equal(SCENARIO_FAMILIES.length, 7);
  assert.deepEqual(FAULT_GAMES, ['fishing', 'siege', 'tank', 'workout']);
});

test('peer flags: a host on the built-in relay has the LAN ports and no --relay', () => {
  const o = parseFaultArgs(['--seed=4']).opts;
  const a = faultPeerArgs(o, {
    role: 'host', gameId: 'siege', profileDir: 'P', reportPath: 'R', lan: { port: 5001, discoveryPort: 5002 }, runSeconds: 60,
  });
  assert.deepEqual(a, [
    '--host', '--game=siege', '--e2e', '--wait-peers=2', '--lan-port=5001', '--lan-discovery-port=5002',
    '--mock-trainer=erg:compliance=1.0', '--autopilot', '--profile-dir=P', '--sim-speed=1', '--seed=4', '--report=R',
    '--run-seconds=60',
  ]);
  assert.ok(!a.some((x) => x.startsWith('--relay')));
});

test('peer flags: a client joins by code, hears beacons on the discovery port only, and may have no run limit', () => {
  const o = parseFaultArgs([]).opts;
  const a = faultPeerArgs(o, {
    role: 'client', code: 'K7QX2M', gameId: 'workout', profileDir: 'P', reportPath: 'R', lan: { port: 5001, discoveryPort: 5002 }, runSeconds: 0,
  });
  assert.ok(a.includes('--join=K7QX2M'));
  assert.ok(a.includes('--lan-discovery-port=5002'));
  assert.ok(!a.some((x) => x.startsWith('--lan-port') || x.startsWith('--run-seconds') || x.startsWith('--host')));
  const viaRelay = faultPeerArgs(o, { role: 'client', code: 'K7QX2M', gameId: 'workout', profileDir: 'P', reportPath: 'R', relayUrl: 'ws://127.0.0.1:9/v1' });
  assert.ok(viaRelay.includes('--relay=ws://127.0.0.1:9/v1'));
  assert.ok(!viaRelay.some((x) => x.startsWith('--lan')));
  for (const x of [...a, ...viaRelay]) assert.ok(!/allow-hw|allow-network/.test(x));
});

// ------------------------------------------------------------------------------- outcomes

test('an outcome reads the WATTLANDS lines and the report', () => {
  const p = peer();
  assert.equal(p.peerId, 2);
  assert.deepEqual(p.states, ['lobby', 'running']);
  assert.equal(p.sawSession, true);
  assert.equal(p.exitReason, 'complete');
  assert.equal(p.doneLine, 'WATTLANDS_DONE complete');
  assert.deepEqual(p.fitMissing, []);
});

test('a refusal is read from the exit reason', () => {
  const p = peer({ exitCode: 3, report: { exit_reason: 'refused:room_not_found' }, lines: ['WATTLANDS_DONE refused:room_not_found'] });
  assert.equal(p.refusedReason, 'room_not_found');
  assert.equal(p.sawSession, false);
  const noReport = peer({ exitCode: 3, report: null, lines: ['WATTLANDS_DONE refused:session_in_progress'] });
  assert.equal(noReport.exitReason, 'refused:session_in_progress', 'the DONE line stands in for a missing report');
});

// ------------------------------------------------------------------------------- checks

test('checkExit wants the right code and reason', () => {
  const refused = peer({ exitCode: 3, report: { exit_reason: 'refused:room_not_found' } });
  assert.equal(checkExit(refused, { codes: [EXIT.REFUSED], reason: 'refused:room_not_found' }).ok, true);
  const wrongReason = checkExit(refused, { codes: [EXIT.REFUSED], reason: 'refused:session_in_progress' });
  assert.equal(wrongReason.ok, false);
  assert.match(wrongReason.details[0], /wanted/);
  const asError = peer({ exitCode: 1, report: { exit_reason: 'error:net:room_not_found' }, lines: ['WATTLANDS_DONE error:net:room_not_found'] });
  const c = checkExit(asError, { label: 'stray client', codes: [EXIT.REFUSED], reason: 'refused:room_not_found' });
  assert.equal(c.ok, false);
  assert.match(c.details[0], /stray client exited 1 \(error\), wanted 3 \(refused\); reason error:net:room_not_found/);
  const anyOf = checkExit(peer({ exitCode: 4, report: { exit_reason: 'host_left' } }), { codes: [2, 4], reason: /^(run_seconds|host_left)$/ });
  assert.equal(anyOf.ok, true);
  const running = peer({ exitCode: null });
  assert.equal(checkExit(running, { codes: [0] }).ok, false);
  assert.match(checkExit(running, { codes: [0] }).details[0], /did not exit/);
});

test('checkClean fails on a script error, a push_error line, a desync or a missing report', () => {
  assert.equal(checkClean(peer()).ok, true);
  const se = checkClean(peer({ logLines: ['SCRIPT ERROR: Invalid call.'] }));
  assert.equal(se.ok, false);
  assert.match(se.details[0], /SCRIPT ERROR/);
  assert.equal(checkClean(peer({ lines: ['ERROR: something went wrong'] })).ok, false);
  assert.equal(checkClean(peer({ logLines: ['WARNING: GameHost: desync: gap'] })).ok, false);
  assert.equal(checkClean(peer({ report: { exit_reason: 'complete', script_errors: 2 } })).ok, false);
  assert.equal(checkClean(peer({ lines: ['rate_limited by the relay'] })).ok, false);
  const none = checkClean(peer({ report: null, reportError: 'missing report.json' }));
  assert.equal(none.ok, false);
  assert.match(none.details[0], /missing report.json/);
  assert.equal(checkClean(peer({ report: null }), { needReport: false }).ok, true, 'a killed peer has no report');
});

test('checkClean ignores only the errors a scenario allows', () => {
  const lines = ['ERROR: relay hiccup (expected)', 'ERROR: something else'];
  const p = peer({ logLines: lines });
  assert.equal(checkClean(p, { allow: [/relay hiccup/] }).ok, false);
  const q = peer({ logLines: [lines[0]] });
  const c = checkClean(q, { allow: [/relay hiccup/] });
  assert.equal(c.ok, true);
  assert.match(c.details[0], /1 expected line/);
});

test('checkNoFlood fails on a warning printed once per tick', () => {
  assert.equal(checkNoFlood(peer()).ok, true);
  const flood = Array.from({ length: 60 }, () => 'WARNING: NetSession.broadcast: only the host broadcasts');
  const c = checkNoFlood(peer({ logLines: flood }), { label: 'host' });
  assert.equal(c.ok, false);
  assert.match(c.details[0], /host: 60 x WARNING: NetSession.broadcast/);
  assert.equal(checkNoFlood(peer({ logLines: flood.slice(0, 50) })).ok, true, 'the limit itself is allowed');
  const notWarnings = Array.from({ length: 80 }, () => 'frame');
  assert.equal(checkNoFlood(peer({ logLines: notWarnings })).ok, true);
});

test('checkFit wants a FIT file in the report, on disk and valid', () => {
  assert.equal(checkFit(peer()).ok, true);
  assert.match(checkFit(peer({ report: { fit_paths: [] } })).details[0], /no FIT file/);
  const missing = checkFit(peer({ fitExists: { '/x/a.fit': false } }));
  assert.equal(missing.ok, false);
  assert.match(missing.details[0], /a\.fit/);
  const bad = checkFit(peer({ fitCheck: { ok: false, code: 1, errors: ['a.fit: bad CRC'] } }));
  assert.equal(bad.ok, false);
  assert.match(bad.details[0], /bad CRC/);
  assert.match(checkFit(peer({ fitCheck: { ok: true, code: 0, errors: [] } })).details[0], /checked/);
});

test('checkState sees the session begin', () => {
  assert.equal(checkState(peer(), ['running']).ok, true);
  const lobbyOnly = peer({ lines: ['WATTLANDS_STATE lobby'] });
  const c = checkState(lobbyOnly, ['running', 'cooldown'], { label: 'client' });
  assert.equal(c.ok, false);
  assert.match(c.details[0], /never reached running\/cooldown \(states: lobby\)/);
});

test('a restarted client must come back as the same peer and not be refused', () => {
  const before = peer({ exitCode: null, killed: true });
  const same = peer();
  assert.equal(checkSamePeer(before, same).ok, true);
  const other = peer({ lines: ['WATTLANDS_PEER 3', 'WATTLANDS_STATE running'] });
  const c = checkSamePeer(before, other);
  assert.equal(c.ok, false);
  assert.match(c.details[0], /came back as peer 3, not 2/);
  assert.equal(checkSamePeer(peer({ lines: [], report: null }), same).ok, false);
  assert.equal(checkNotRefused(same).ok, true);
  assert.equal(checkNotRefused(peer({ lines: ['WATTLANDS_DONE refused:session_in_progress'] })).ok, false);
});

// ------------------------------------------------------------------------------- verdicts

test('a scenario passes only with checks and every check passing', () => {
  const ok = scenarioVerdict('x', [{ name: 'a', ok: true, details: ['fine'] }]);
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.failures, []);
  const bad = scenarioVerdict('x', [{ name: 'a', ok: true, details: ['fine'] }, { name: 'b', ok: false, details: ['broken', 'twice'] }], { duration_s: 3 });
  assert.equal(bad.ok, false);
  assert.deepEqual(bad.failures, ['b: broken; twice']);
  assert.equal(bad.evidence.duration_s, 3);
  const empty = scenarioVerdict('x', []);
  assert.equal(empty.ok, false);
  assert.match(empty.failures[0], /no checks/);
});

test('a wrong-code scenario from fake peers: refused passes, a net error fails', () => {
  const good = peer({ name: 'stray', exitCode: 3, lines: ['WATTLANDS_DONE refused:room_not_found'], report: { exit_reason: 'refused:room_not_found' } });
  const bad = peer({ name: 'stray', exitCode: 1, lines: ['WATTLANDS_DONE error:net:room_not_found'], report: { exit_reason: 'error:net:room_not_found' } });
  const checks = (p) => [checkExit(p, { label: 'stray client', codes: [EXIT.REFUSED], reason: 'refused:room_not_found' }), checkClean(p, { label: 'stray client' })];
  assert.equal(scenarioVerdict('wrong_code:relay', checks(good)).ok, true);
  const v = scenarioVerdict('wrong_code:relay', checks(bad));
  assert.equal(v.ok, false);
  assert.match(v.failures[0], /stray client exit: stray client exited 1/);
});

test('a late-join scenario from fake peers: the session must survive the refusal', () => {
  const third = peer({ name: 'late', exitCode: 3, lines: ['WATTLANDS_DONE refused:session_in_progress'], report: { exit_reason: 'refused:session_in_progress' } });
  assert.equal(checkExit(third, { codes: [EXIT.REFUSED], reason: 'refused:session_in_progress' }).ok, true);
  const hostHarmed = peer({ name: 'host', role: 'host', exitCode: 1, logLines: ['SCRIPT ERROR: x'], report: { exit_reason: 'error:setup' } });
  assert.equal(checkClean(hostHarmed).ok, false);
  assert.equal(checkExit(hostHarmed, { codes: [EXIT.TIMEOUT], reason: 'run_seconds' }).ok, false);
});

test('the run verdict: exit 0 only if all pass, 1 on a failure or no scenario, 75 on a lock timeout', () => {
  assert.deepEqual(runVerdict([{ name: 'a', ok: true }]), { code: 0, line: 'faults: 1 of 1 scenario(s) passed' });
  const f = runVerdict([{ name: 'a', ok: true }, { name: 'b', ok: false }]);
  assert.equal(f.code, 1);
  assert.match(f.line, /failed: b/);
  assert.equal(runVerdict([]).code, 1);
  assert.equal(runVerdict([{ name: 'a', ok: true }], { lockTimeout: true }).code, 75);
});
