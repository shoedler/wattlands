// node:test for tools/e2e/lib/checks.mjs: event sequences, final state, warm-up limits, directive
// records, log scanning, port and upload parsing, durations.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as C from '../lib/checks.mjs';

const ps = (peer, index, t = 0) => ({ t, type: 'phase_started', peer, index });
const ge = (n, t = 0) => ({ t, type: 'fish_hooked', n, w: 0.5 });
const results = (t = 0) => ({ t, type: 'results', grade: 'A', rows: [{ peer_id: 1, kj: 12.3 }] });

const HOST = [
  { t: 0, type: 'session_state', state: 'running' },
  ps(1, 0), ps(2, 0), ps(3, 0), ge(1), ps(1, 1), ps(2, 1), ps(3, 1), ge(2), results(),
];

test('comparableEvents drops per-peer types and volatile keys', () => {
  const c = C.comparableEvents([{ t: 1, type: 'session_state' }, { t: 2.5, wall_t: 9, type: 'phase_started', peer: 1, index: 0 }, { no: 'type' }, 'x']);
  assert.deepEqual(c, [{ type: 'phase_started', peer: 1, index: 0 }]);
  assert.deepEqual(C.comparableEvents(null), []);
});

test('identical sequences with different arrival times match', () => {
  const client = HOST.map((e) => ({ ...e, t: e.t + 0.37 }));
  assert.equal(C.compareSequences(C.comparableEvents(HOST), C.comparableEvents(client)).ok, true);
});

test('a reordered, missing or changed event is reported with its index', () => {
  const ref = C.comparableEvents(HOST);
  const swapped = [...ref];
  [swapped[1], swapped[2]] = [swapped[2], swapped[1]];
  const r1 = C.compareSequences(ref, swapped);
  assert.equal(r1.ok, false);
  assert.equal(r1.index, 1);
  const r2 = C.compareSequences(ref, ref.slice(0, -1));
  assert.equal(r2.ok, false);
  assert.match(r2.detail, /missing/);
  const changed = ref.map((e) => (e.type === 'fish_hooked' && e.n === 2 ? { ...e, n: 3 } : e));
  assert.equal(C.compareSequences(ref, changed).ok, false);
  assert.equal(C.compareSequences(ref, [...ref, results()]).ok, false);
});

test('numbers compare with a tiny tolerance and int vs float never matters', () => {
  assert.equal(C.eventsEqual({ a: 1 }, { a: 1.0 }), true);
  assert.equal(C.eventsEqual({ a: 0.1 + 0.2 }, { a: 0.3 }), true);
  assert.equal(C.eventsEqual({ a: 1 }, { a: 1.01 }), false);
});

test('a rejoined client must hold a tail of the host sequence', () => {
  const ref = C.comparableEvents(HOST);
  const tail = ref.slice(5);
  assert.equal(C.matchTail(ref, tail).ok, true);
  // A rejoin after the last game event replays the rider's current phase first.
  const replay = [{ type: 'phase_started', peer: 3, index: 1 }, ...ref.slice(8)];
  const r = C.matchTail(ref, replay);
  assert.equal(r.ok, true);
  assert.equal(r.skipped, 1);
  assert.equal(C.matchTail(ref, replay, { replayPeer: 3 }).ok, true);
  assert.equal(C.matchTail(ref, replay, { replayPeer: 2 }).ok, false, "only the rejoined rider's own phase is replayed");
  // A gap after the rejoin is not a tail, even when it starts with phase events.
  const gap = [...ref.slice(5, 7), ...ref.slice(8)];
  assert.equal(C.matchTail(ref, gap).ok, false);
  assert.equal(C.matchTail(ref, []).ok, false);
});

test('checkSameEvents: host, a full client and a rejoined client', () => {
  const client1 = HOST.map((e) => ({ ...e, t: e.t + 1 }));
  const client2 = [{ type: 'session_state', state: 'running' }, ps(3, 1), ge(2), results()];
  const ok = C.checkSameEvents({ host: HOST, client1, client2 }, { partial: ['client2'] });
  assert.equal(ok.ok, true, ok.details.join('\n'));
  const bad = C.checkSameEvents({ host: HOST, client1: client1.slice(0, -2), client2 }, { partial: ['client2'] });
  assert.equal(bad.ok, false);
  assert.match(bad.details.join('\n'), /client1/);
  const noResults = C.checkSameEvents({ host: HOST.slice(0, -1), client1: HOST.slice(0, -1) });
  assert.equal(noResults.ok, false);
  assert.match(noResults.details.join('\n'), /no "results"/);
  const empty = C.checkSameEvents({ host: [], client1: [] });
  assert.equal(empty.ok, false);
});

test('checkFinalState: tolerance, per-peer keys, missing state', () => {
  const host = { score: 100, distance_m: 1000, local_peer: 1, fish: [{ hp: 10 }], local_cam: 3 };
  const near = { score: 100, distance_m: 1010, local_peer: 2, fish: [{ hp: 10.05 }], local_cam: 9 };
  assert.equal(C.checkFinalState({ host, client1: near }).ok, true);
  const far = { ...near, distance_m: 1100 };
  const r = C.checkFinalState({ host, client1: far });
  assert.equal(r.ok, false);
  assert.match(r.details[0], /distance_m/);
  assert.equal(C.checkFinalState({ host, client1: { ...near, fish: [] } }).ok, false);
  assert.equal(C.checkFinalState({ host, client1: null }).ok, false);
  assert.equal(C.checkFinalState({ host: null }).ok, false);
});

test('checkWarmup: ERG <= 65% FTP and SIM grade -2..+3', () => {
  const good = [
    { t: 0, mode: 'ERG', applied_pct: 50 },
    { t: 1, mode: 'ERG', applied_pct: 65 },
    { t: 2, mode: 'SIM', applied_grade_pct: -2 },
    { t: 3, mode: 'SIM', applied_grade_pct: 3 },
    { t: 4, mode: 'OFF' },
  ];
  const r = C.checkWarmup(good);
  assert.equal(r.ok, true, r.violations.join('\n'));
  assert.equal(r.erg, 2);
  assert.equal(r.sim, 2);
  assert.equal(C.checkWarmup([{ t: 0, mode: 'ERG', applied_pct: 65.5 }]).ok, false);
  assert.equal(C.checkWarmup([{ t: 0, mode: 'SIM', applied_grade_pct: 3.2 }]).ok, false);
  assert.equal(C.checkWarmup([{ t: 0, mode: 'SIM', applied_grade_pct: -2.5 }]).ok, false);
  assert.match(C.checkWarmup([{ t: 0, mode: 'ERG' }]).violations[0], /without applied_pct/);
  assert.match(C.checkWarmup([]).violations[0], /no trace/);
  const dir = [{ id: 4, applied: { target_pct: 70 }, clamped_by: [] }, { id: 5, refused: true, reason: 'x', applied: { target_pct: 99 } }];
  const d = C.checkWarmup(good, dir);
  assert.equal(d.ok, false);
  assert.equal(d.violations.length, 1);
  assert.match(d.violations[0], /id=4/);
  assert.equal(C.checkWarmup(good, [{ id: 6, applied: { grade_pct: 4 }, clamped_by: [] }]).ok, false);
});

test('checkDirectives: every record clamped or refused with a reason', () => {
  const host = { peer_id: 1, directives: [
    { id: 1, peer: 1, applied: { target_pct: 60 }, clamped_by: [] },
    { id: 2, peer: 2, applied: { target_pct: 60 }, clamped_by: ['warmup'] },
    { id: 3, peer: -1, applied: {}, clamped_by: [] },
  ] };
  const client1 = { peer_id: 2, directives: [{ id: 2, applied: { target_pct: 60 }, clamped_by: ['warmup'] }] };
  assert.equal(C.checkDirectives({ host, client1 }).ok, true);
  const missing = C.checkDirectives({ host, client1: { peer_id: 2, directives: [] } });
  assert.equal(missing.ok, false);
  assert.match(missing.problems[0], /directive 2 for peer 2/);
  const partial = C.checkDirectives({ host, client1: { peer_id: 2, directives: [] } }, { partial: ['client1'] });
  assert.equal(partial.ok, true);
  assert.equal(partial.warnings.length, 1);
  const bad = C.checkDirectives({ host: { peer_id: 1, directives: [{ id: 9, refused: true }, { id: 10, applied: {} }, 7] } });
  assert.equal(bad.ok, false);
  assert.equal(bad.problems.length, 3);
});

test('scanLog finds script errors, push_error output, desync warnings and rate limits', () => {
  const r = C.scanLog([
    'Godot Engine v4.7.2',
    'SCRIPT ERROR: Invalid call',
    'ERROR: push_error says hi',
    '   at: push_error (core/variant/variant_utility.cpp:1098)',
    'USER ERROR: older style',
    'WARNING: snapshot desync on peer 2',
    'WARNING: a harmless warning',
    'relay: rate_limited',
    'refused: session_in_progress',
    'Parse Error: Expected ...',
    'desync_warnings: 0',
  ]);
  assert.equal(r.errors.length, 4);
  assert.equal(r.desync.length, 1);
  assert.equal(r.rateLimited.length, 1);
  assert.equal(r.refused.length, 1);
  assert.deepEqual(C.scanLog(['all fine', 'WATTLANDS_DONE complete']).errors, []);
});

test('parsePort reads URLs, "port N" and JSON', () => {
  assert.equal(C.parsePort('mock strava listening on http://127.0.0.1:53211'), 53211);
  assert.equal(C.parsePort('listening at http://localhost:8080/'), 8080);
  assert.equal(C.parsePort('{"port": 4321}'), 4321);
  assert.equal(C.parsePort('{"url": "http://127.0.0.1:999"}'), 999);
  assert.equal(C.parsePort('server port=5555 ready'), 5555);
  assert.equal(C.parsePort('Server listening on 0.0.0.0:7777'), 7777);
  assert.equal(C.parsePort('nothing here'), null);
  assert.equal(C.parsePort('port 99999'), null);
});

test('parseUploads accepts arrays, wrapped arrays and counts', () => {
  assert.deepEqual(C.parseUploads([{ id: 1 }]), [{ id: 1 }]);
  assert.deepEqual(C.parseUploads({ uploads: [{ id: 2 }] }), [{ id: 2 }]);
  assert.equal(C.parseUploads({ count: 2 }).length, 2);
  assert.equal(C.parseUploads({ other: 1 }), null);
  assert.equal(C.parseUploads('x'), null);
});

test('checkUploads: exactly one, from the auto-upload peer only', () => {
  const peers = { host: { uploads: [] }, client1: { uploads: [{ state: 'uploaded', activity_id: 5 }] }, client2: { uploads: [] } };
  assert.equal(C.checkUploads([{ id: 1 }], peers, 'client1').ok, true);
  assert.equal(C.checkUploads([], peers, 'client1').ok, false);
  assert.equal(C.checkUploads([{}, {}], peers, 'client1').ok, false);
  assert.equal(C.checkUploads(null, peers, 'client1').ok, false);
  assert.equal(C.checkUploads([{}], { ...peers, host: { uploads: [{ state: 'uploaded' }] } }, 'client1').ok, false);
  assert.equal(C.checkUploads([{}], { ...peers, client1: { uploads: [{ state: 'failed' }] } }, 'client1').ok, false);
});

test('durations exclude the cool-down', () => {
  assert.equal(C.durationExclCooldown(500, 181, 180), 319);
  assert.equal(C.durationExclCooldown(500, null, 180), 320);
  assert.equal(C.durationExclCooldown(100, null, 180), 0);
  const lines = [
    { t: 1, line: 'WATTLANDS_STATE running' },
    { t: 120, line: 'WATTLANDS_STATE cooldown' },
    { t: 300, line: 'WATTLANDS_STATE results' },
    { t: 305, line: 'WATTLANDS_DONE complete' },
  ];
  assert.equal(C.observedCooldownS(lines), 180);
  assert.equal(C.observedCooldownS(lines.slice(0, 2)), 0);
  assert.equal(C.observedCooldownS([{ t: 1, line: 'x' }]), null);
});
