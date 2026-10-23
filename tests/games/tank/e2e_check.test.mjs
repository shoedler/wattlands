// node --test tests/games/tank/e2e_check.test.mjs: e2e_check.mjs on a synthetic e2e report (the
// drill with a host and two clients, client2 killed and rejoined) and on broken variants of it.
// Independent of build/. The snapshot comes from the lead's fixtures (TankSnapshot.encode of the
// Citadel), so the schema the check pins is the one the game writes.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import * as ec from './e2e_check.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const SNAPSHOT = JSON.parse(fs.readFileSync(path.join(here, 'fixtures', 'snapshot_citadel.json'), 'utf8'));
const ge = (event) => ({ type: 'game_event', event });
const errs = (r) => ec.checkReport(r).errors.join('\n');
const clone = (v) => JSON.parse(JSON.stringify(v));

function sink() {
  let text = '';
  return { write: (s) => (text += s), get text() { return text; } };
}

/** The drill's Tank events as the host sends them. */
function drillEvents() {
  return [
    { type: 'segment', i: 0, sg: 1, st: 0 },
    { type: 'segment', i: 1, sg: 6, st: 1 },
    { type: 'shot', s: -1, sh: 5, id: 31, src: 20, e: 1 },
    { type: 'shot', s: 0, sh: 1, id: 32, src: 0, e: 0 },
    { type: 'hit', on: 1, id: 20, dmg: 20, sh: 1, b: 0, x: 3400 },
    { type: 'kill', id: 20, e: 1, by: 0, s: 0 },
    { type: 'hit', on: 0, id: 0, dmg: 4, sh: 5, b: 0, x: 120 },
    { type: 'latch', s: 2, sh: 2 },
    { type: 'kill', id: 21, e: 1, by: 0, s: 0 },
    { type: 'kill', id: 22, e: 2, by: 0, s: 1 },
    { type: 'segment', i: 2, sg: 4, st: 1 },
    { type: 'segment', i: 3, sg: 7, st: 0 },
  ];
}

function peerLog(events, extra = []) {
  return [
    { type: 'session_state', state: 'running' },
    { type: 'phase_started', index: 0 },
    ...events.map(ge),
    ...extra,
    { type: 'finished', reason: 'complete' },
    { type: 'results' },
  ];
}

function peer(id, events, over = {}) {
  return {
    peer_id: id,
    events: peerLog(events),
    exit_reason: 'complete',
    script_errors: 0,
    log_error_count: 0,
    log_errors: [],
    desync_warnings: 0,
    earlier_runs: [],
    final_state: { snapshot: clone(SNAPSHOT) },
    ...over,
  };
}

function report(over = {}) {
  const host = over.host ?? drillEvents();
  const c1 = over.client1 ?? drillEvents();
  const c2 = over.client2 ?? drillEvents().slice(4);
  return {
    schema: 1,
    game_id: 'tank',
    content_id: over.content_id ?? 'drill',
    victim: 'client2',
    peers: {
      host: peer(1, host, over.hostPeer),
      client1: peer(2, c1, over.client1Peer),
      client2: peer(3, c2, { restarted: true, ...over.client2Peer }),
    },
    directives: over.directives ?? [],
    fit_check: over.fit_check ?? {},
  };
}

test('a clean drill report passes', () => {
  const v = ec.checkReport(report());
  assert.deepEqual(v.errors, []);
  assert.equal(v.ok, true);
  assert.equal(v.info.hostEvents, 12);
  assert.equal(v.info.victimEvents, 8);
  assert.ok(v.info.snapshotBytes > 100 && v.info.snapshotBytes <= 4096);
});

test('the fixture snapshot is a valid Citadel snapshot', () => {
  assert.deepEqual(ec.snapshotErrors(SNAPSHOT, { crew: { tank: 3, riders: 3, rooms: 3 } }), []);
});

test('events_by_peer is read when the peers carry no events', () => {
  const r = report();
  r.events_by_peer = { 1: r.peers.host.events, 2: r.peers.client1.events, 3: r.peers.client2.events };
  for (const p of Object.values(r.peers)) delete p.events;
  assert.equal(ec.checkReport(r).ok, true, errs(r));
});

test('the cool-down segment event is optional, the other three are not', () => {
  const noCool = drillEvents().filter((e) => !(e.type === 'segment' && e.i === 3));
  assert.equal(ec.checkReport(report({ host: noCool, client1: noCool, client2: noCool.slice(4) })).ok, true);
  const noSkirmish = drillEvents().filter((e) => !(e.type === 'segment' && e.i === 1));
  assert.match(errs(report({ host: noSkirmish, client1: noSkirmish })), /host: segments .* wanted/);
});

test('asTankEvent unwraps game_event wrappers and raw Tank events only', () => {
  assert.deepEqual(ec.asTankEvent(ge({ type: 'breakdown' })), { type: 'breakdown' });
  assert.deepEqual(ec.asTankEvent({ type: 'breakdown' }), { type: 'breakdown' });
  assert.equal(ec.asTankEvent({ type: 'finished', reason: 'complete' }), null);
  assert.equal(ec.asTankEvent('x'), null);
  assert.equal(ec.tankEvents(null).length, 0);
});

test('an event type a client does not know fails', () => {
  const c1 = [...drillEvents().slice(0, 2), { type: 'banana', x: 1 }, ...drillEvents().slice(2)];
  assert.match(errs(report({ client1: c1 })), /client1: applied unknown event type "banana"/);
});

test('fields that are floats, strings or missing fail the schema', () => {
  const bad = drillEvents();
  bad[4] = { type: 'hit', on: 1, id: 20.5, dmg: '20', sh: 1, b: 0 };
  const m = errs(report({ host: bad, client1: bad }));
  assert.match(m, /hit: id is not an int/);
  assert.match(m, /hit: dmg is not an int/);
  assert.match(m, /hit: missing x/);
  const rot = drillEvents();
  rot[2] = { type: 'rotation', r: [[0, 2], [1]] };
  assert.match(errs(report({ host: rot, client1: rot })), /rotation: r is not rows of two ints/);
  const whole = drillEvents();
  whole[2] = { type: 'shot', s: -1.0, sh: 5, id: 31, src: 20, e: 1 };
  assert.equal(ec.eventErrors(whole[2]).length, 0, 'a whole float (JSON) is an int');
});

test('ranges: a kill of the wrong enemy code, a hit on nothing, a lever off the gearbox', () => {
  assert.match(ec.eventErrors({ type: 'kill', id: 4, e: 9, by: 0, s: 0 }).join(), /e 9 outside 1\.\.6/);
  assert.match(ec.eventErrors({ type: 'hit', on: 7, id: 0, dmg: 1, sh: 1, b: 0, x: 0 }).join(), /on 7 outside 0\.\.3/);
  assert.match(ec.eventErrors({ type: 'lever', s: 0, lv: 5 }).join(), /lv 5 outside 0\.\.2/);
  assert.match(ec.eventErrors({ type: 'ram', s: 0, ok: 2, id: 1 }).join(), /ok 2 outside 0\.\.1/);
  assert.match(ec.eventErrors({ type: 'segment', i: 1, sg: 0, st: 1 }).join(), /sg 0 outside 1\.\.7/);
  assert.deepEqual(ec.eventErrors({ type: 'breakdown' }), []);
  assert.deepEqual(ec.eventErrors({ type: 'rotation', r: [[0, 2], [1, 3], [2, 1]] }), []);
});

test('the host and the client that stayed must hold the same events in the same order', () => {
  const c1 = drillEvents();
  [c1[2], c1[3]] = [c1[3], c1[2]];
  assert.match(errs(report({ client1: c1 })), /client1: Tank events differ from the host's/);
  const missing = drillEvents();
  missing.splice(5, 1);
  assert.match(errs(report({ client1: missing })), /client1: Tank events differ/);
});

test('the rejoined client holds a tail of the host events', () => {
  assert.equal(ec.checkReport(report({ client2: drillEvents().slice(-3) })).ok, true);
  const wrong = drillEvents().slice(4);
  wrong[0] = { ...wrong[0], dmg: 99 };
  assert.match(errs(report({ client2: wrong })), /client2: its events are not a tail/);
  assert.match(errs(report({ client2: [] })), /client2: the restarted client recorded no Tank events/);
  const longer = [{ type: 'breakdown' }, ...drillEvents()];
  assert.match(errs(report({ client2: longer })), /client2: \d+ events, more than the host's/);
});

test('the drill: segments once each and in order', () => {
  const twice = [...drillEvents(), { type: 'segment', i: 1, sg: 6, st: 1 }];
  assert.match(errs(report({ host: twice, client1: twice })), /host: segments/);
  const swapped = drillEvents();
  [swapped[0], swapped[1]] = [swapped[1], swapped[0]];
  assert.match(errs(report({ host: swapped, client1: swapped })), /host: segments/);
  const wrongStage = drillEvents();
  wrongStage[1] = { type: 'segment', i: 1, sg: 6, st: 3 };
  assert.match(errs(report({ host: wrongStage, client1: wrongStage })), /host: segments/);
});

test('the drill: nothing a WARMUP session forbids', () => {
  for (const [bad, pattern] of [
    [{ type: 'ram', s: 0, ok: 1, id: 20 }, /1 ram event\(s\) in the drill/],
    [{ type: 'dodge', s: 0 }, /1 dodge event\(s\)/],
    [{ type: 'boss_phase', p: 1 }, /1 boss_phase event\(s\)/],
    [{ type: 'overrun', sg: 2, st: 1 }, /1 overrun event\(s\)/],
    [{ type: 'rotation', r: [[0, 2]] }, /1 rotation event\(s\)/],
  ]) {
    const e = [...drillEvents().slice(0, 6), bad, ...drillEvents().slice(6)];
    assert.match(errs(report({ host: e, client1: e })), pattern);
  }
  const haptic = [{ id: 7, requested: { source: 'tank', mode: 'SIM', haptic: 2, duration_s: 1.5 } }];
  assert.match(errs(report({ directives: haptic })), /1 Tank haptic directive\(s\) in the drill/);
  const other = [{ id: 8, requested: { source: 'tank', mode: 'SIM', mode_grade: 3 } }];
  assert.equal(ec.checkReport(report({ directives: other })).ok, true, 'a boiler grade is fine');
});

test('the drill: kills, repairs and the depot', () => {
  const four = [...drillEvents(), { type: 'kill', id: 23, e: 1, by: 0, s: 0 }];
  assert.match(errs(report({ host: four, client1: four })), /4 kills, the skirmish has 3 tanks/);
  const twice = drillEvents();
  twice[8] = { type: 'kill', id: 20, e: 1, by: 0, s: 0 };
  assert.match(errs(report({ host: twice, client1: twice })), /enemy 20 killed twice/);
  const orphan = [...drillEvents().slice(0, 6), { type: 'repaired', hp: 40 }, ...drillEvents().slice(6)];
  assert.match(errs(report({ host: orphan, client1: orphan })), /repaired without a breakdown/);
  const paired = [...drillEvents().slice(0, 6), { type: 'breakdown' }, { type: 'repaired', hp: 40 }, ...drillEvents().slice(6)];
  assert.equal(ec.checkReport(report({ host: paired, client1: paired, client2: paired.slice(5) })).ok, true);
  const depot = [drillEvents()[0], { type: 'hit', on: 0, id: 0, dmg: 4, sh: 5, b: 0, x: 1 }, ...drillEvents().slice(1)];
  assert.match(errs(report({ host: depot, client1: depot })), /hit in the depot/);
  const latch = [drillEvents()[0], { type: 'latch', s: 2, sh: 1 }, ...drillEvents().slice(1)];
  assert.equal(ec.checkReport(report({ host: latch, client1: latch, client2: latch.slice(5) })).ok, true, 'a latch in the depot is fine');
});

test('other content is not held to the drill story', () => {
  const long = [...drillEvents(), { type: 'rotation', r: [[0, 2], [1, 3], [2, 1]] }, { type: 'ram', s: 0, ok: 1, id: 3 }];
  const r = report({ host: long, client1: long, client2: long.slice(4), content_id: 'ashfall_road' });
  const setReason = (reason) => {
    for (const role of ['host', 'client1', 'client2']) r.peers[role].events.find((e) => e.type === 'finished').reason = reason;
  };
  setReason('victory');
  assert.equal(ec.checkReport(r).ok, true, errs(r));
  setReason('withdrawn');
  assert.equal(ec.checkReport(r).ok, true, errs(r));
  setReason('complete');
  assert.match(errs(r), /finished with reason "complete", wanted victory or withdrawn/);
});

test('final snapshots: within 2% passes, more fails', () => {
  const r = report();
  r.peers.client1.final_state.snapshot.tick = Math.round(SNAPSHOT.tick * 1.01);
  r.peers.client1.final_state.snapshot.tk[1] = Math.round(SNAPSHOT.tk[1] * 1.015);
  assert.equal(ec.checkReport(r).ok, true, errs(r));
  r.peers.client1.final_state.snapshot.tk[4] += 40;
  assert.match(errs(r), /client1: final snapshot differs from the host's by more than 2%: \.snapshot\.tk\[4\]|tk\[4\]/);
});

test('final snapshots: a float, a missing key, a short row, a wrong crew, an oversize one', () => {
  const frac = report();
  frac.peers.host.final_state.snapshot.tk[1] += 0.5;
  assert.match(errs(frac), /host: snapshot: not whole numbers: snapshot\.tk\[1\]=/);
  const missing = report();
  delete missing.peers.client1.final_state.snapshot.gl;
  assert.match(errs(missing), /client1: snapshot: missing gl/);
  const short = report();
  short.peers.client2.final_state.snapshot.r[0].pop();
  assert.match(errs(short), /client2: snapshot\.r: a row needs 6 columns/);
  const solo = report();
  for (const role of ['host', 'client1', 'client2']) solo.peers[role].final_state.snapshot.r.pop();
  assert.match(errs(solo), /host: snapshot: 2 riders, wanted 3/);
  const big = report();
  for (const role of ['host', 'client1', 'client2']) {
    big.peers[role].final_state.snapshot.e = Array.from({ length: 16 }, (_, i) => [1000 + i, 1, 99999999 + i, 160, 2, 1, 3999]);
    big.peers[role].final_state.snapshot.s = Array.from({ length: 24 }, (_, i) => [2000 + i, 3, 99999 + i, 999, 359, 359, 1]);
  }
  assert.deepEqual(ec.checkReport(big).errors.filter((m) => /bytes/.test(m)), [], 'the cap state fits in 4 KB');
  big.peers.host.final_state.snapshot.o = Array.from({ length: 200 }, (_, i) => [3000 + i, 1, 99999999, 1, 0]);
  assert.match(errs(big), /host: snapshot: \d+ bytes, over 4096/);
  const none = report();
  delete none.peers.client1.final_state;
  assert.match(errs(none), /client1: no final snapshot/);
});

test('script errors, push_error lines, desyncs and a bad exit fail', () => {
  const r = report({
    client1Peer: { script_errors: 2, log_error_count: 1, log_errors: ['ERROR: tank: boom'], desync_warnings: 1 },
    client2Peer: { exit_reason: 'host_left', earlier_runs: [{ log_errors: ['ERROR: killed run'] }] },
  });
  const m = errs(r);
  assert.match(m, /client1: report\.script_errors = 2/);
  assert.match(m, /client1: 1 error line\(s\) in its log \(a push_error\?\), first: ERROR: tank: boom/);
  assert.match(m, /client1: 1 desync warning/);
  assert.match(m, /client2: exit_reason "host_left"/);
  assert.match(m, /client2: killed run: 1 error line/);
});

test('finished must say complete in the drill and exist on the host', () => {
  const r = report();
  r.peers.client1.events.find((e) => e.type === 'finished').reason = 'victory';
  assert.match(errs(r), /client1: finished with reason "victory", wanted complete/);
  const none = report();
  none.peers.host.events = none.peers.host.events.filter((e) => e.type !== 'finished');
  assert.equal(ec.checkReport(none).ok, true, "the host's exit_reason complete counts");
  none.peers.host.exit_reason = 'timeout';
  assert.match(errs(none), /host: no finished event/);
});

test('FIT laps: the drill has four', () => {
  const ok = { host: { json: { files: [{ laps: [1, 2, 3, 4] }] } }, client1: { json: { files: [{ laps: [1, 2, 3, 4] }] } } };
  assert.equal(ec.checkReport(report({ fit_check: ok })).ok, true);
  const bad = { host: { json: { files: [{ laps: [1, 2, 3] }] } } };
  assert.match(errs(report({ fit_check: bad })), /host: 3 FIT laps, wanted 4/);
});

test('an empty report fails with one clear line', () => {
  const v = ec.checkReport({ peers: {} });
  assert.equal(v.ok, false);
  assert.deepEqual(v.errors, ['no events in the report']);
});

test('main: exit codes and output', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tank_e2e_'));
  try {
    const good = path.join(dir, 'good.json');
    fs.writeFileSync(good, JSON.stringify(report()));
    let out = sink();
    assert.equal(ec.main([good], out, sink()), 0);
    assert.match(out.text, /e2e_check tank: PASS \(12 Tank events on the host/);
    const badReport = report({ client1: drillEvents().slice(1) });
    const bad = path.join(dir, 'bad.json');
    fs.writeFileSync(bad, JSON.stringify(badReport));
    out = sink();
    assert.equal(ec.main([bad], out, sink()), 1);
    assert.match(out.text, /e2e_check tank: FAIL client1: Tank events differ/);
    const err = sink();
    assert.equal(ec.main([], sink(), err), 2);
    assert.match(err.text, /usage/);
    const err2 = sink();
    assert.equal(ec.main([path.join(dir, 'nope.json')], sink(), err2), 2);
    assert.match(err2.text, /cannot read/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
