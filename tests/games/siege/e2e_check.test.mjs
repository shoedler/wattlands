// node --test tests/games/siege/e2e_check.test.mjs: e2e_check.mjs on synthetic e2e reports.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import * as ec from './e2e_check.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const ge = (event) => ({ type: 'game_event', event });

/** The drill's Siege events as the host sends them. */
function drillEvents() {
  return [
    { type: 'wave_start', ph: 1, role: 'wave', n: 1, waves: 1, b: 12 },
    { type: 'shot', tk: 500, src: 2, kind: 1, o: [3020, 4200, 1720], v: [-12000, 9000, 15000], n: 1, sd: 77 },
    { type: 'kill', id: 3, et: 1, src: 3, x2: 0 },
    { type: 'kill', id: 4, et: 3, src: 11, x2: 0 },
    { type: 'push', id: 8, et: 4, prog_dm: 3434 },
    { type: 'leak', id: 9, et: 4, dmg: 1 },
    { type: 'buy', slot: 0, item: 'repair', station: 0, pad: 0, ok: 0, why: 'gate_full', lvl: 0 },
    { type: 'wave_end', ph: 1, n: 1, hp: 90, max: 100, leaks: 1 },
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

function report(over = {}) {
  const host = over.host ?? drillEvents();
  const c1 = over.client1 ?? drillEvents();
  const c2 = over.client2 ?? drillEvents().slice(-2);
  return {
    schema: 1,
    game_id: 'siege',
    content_id: 'drill',
    victim: 'client2',
    peers: {
      host: { peer_id: 1, events: peerLog(host) },
      client1: { peer_id: 2, events: peerLog(c1) },
      client2: { peer_id: 3, restarted: true, events: peerLog(c2) },
    },
    directives: over.directives ?? [],
    fit_check: over.fit_check ?? {},
  };
}

const errs = (r) => ec.checkReport(r).errors.join('\n');

test('a clean drill report passes', () => {
  const v = ec.checkReport(report());
  assert.deepEqual(v.errors, []);
  assert.equal(v.ok, true);
  assert.equal(v.info.hostEvents, 8);
});

test('events_by_peer is read when the peers carry no events', () => {
  const r = report();
  r.events_by_peer = { 1: r.peers.host.events, 2: r.peers.client1.events, 3: r.peers.client2.events };
  for (const p of Object.values(r.peers)) delete p.events;
  assert.equal(ec.checkReport(r).ok, true);
});

test('asSiegeEvent unwraps game_event wrappers and raw Siege events only', () => {
  assert.deepEqual(ec.asSiegeEvent(ge({ type: 'breach', n: 1 })), { type: 'breach', n: 1 });
  assert.deepEqual(ec.asSiegeEvent({ type: 'breach', n: 1 }), { type: 'breach', n: 1 });
  assert.equal(ec.asSiegeEvent({ type: 'finished', reason: 'complete' }), null);
  assert.equal(ec.asSiegeEvent('x'), null);
  assert.equal(ec.siegeEvents(null).length, 0);
});

test('an event type a client does not know fails', () => {
  const host = drillEvents();
  const c1 = [...drillEvents().slice(0, 2), { type: 'banana', x: 1 }, ...drillEvents().slice(2)];
  const m = errs(report({ host, client1: c1 }));
  assert.match(m, /client1: applied unknown event type "banana"/);
});

test('fields that are floats, strings or missing fail the schema', () => {
  const bad = drillEvents();
  bad[2] = { type: 'kill', id: 3.5, et: '1', src: 3 };
  const m = errs(report({ host: bad, client1: bad }));
  assert.match(m, /kill: id is not an int/);
  assert.match(m, /kill: et is not an int/);
  assert.match(m, /kill: missing x2/);
  const arr = drillEvents();
  arr[1].o = [1, 'a', 3];
  assert.match(errs(report({ host: arr, client1: arr })), /o is not an array of ints/);
  const str = drillEvents();
  str[6] = { type: 'buy', slot: 0, item: 5, station: 0, pad: 0, ok: 0, why: 'gate_full', lvl: 0 };
  assert.match(errs(report({ host: str, client1: str })), /buy: item is not a string/);
});

test('ranges: a kill from source 9, an hp above max, a refusal without a known reason', () => {
  const bad = drillEvents();
  bad[2] = { type: 'kill', id: 3, et: 1, src: 9, x2: 0 };
  bad[7] = { type: 'wave_end', ph: 1, n: 1, hp: 120, max: 100, leaks: 0 };
  bad[6] = { type: 'buy', slot: 0, item: 'repair', station: 0, pad: 0, ok: 0, why: 'because', lvl: 0 };
  const m = errs(report({ host: bad, client1: bad }));
  assert.match(m, /src 9 is not a station or a pad/);
  assert.match(m, /hp 120 outside 0\.\.100/);
  assert.match(m, /unknown reason "because"/);
});

test('the wave must start and end once, in order, with combat in between', () => {
  const noStart = drillEvents().slice(1);
  assert.match(errs(report({ host: noStart, client1: noStart })), /host: 0 wave_start events \(wanted exactly 1\)/);
  const twice = [...drillEvents(), ...drillEvents()];
  assert.match(errs(report({ host: twice, client1: twice })), /2 wave_start events/);
  const swapped = drillEvents();
  [swapped[0], swapped[7]] = [swapped[7], swapped[0]];
  assert.match(errs(report({ host: swapped, client1: swapped })), /wave_end arrived before wave_start/);
  const late = [...drillEvents(), { type: 'kill', id: 70, et: 1, src: 3, x2: 0 }];
  assert.match(errs(report({ host: late, client1: late })), /kill after wave_end/);
  const wrong = drillEvents();
  wrong[0].n = 2;
  assert.match(errs(report({ host: wrong, client1: wrong })), /wave_start is .* wanted ph 1, n 1/);
});

test('the host and the client that stayed must hold the same events in the same order', () => {
  const c1 = drillEvents();
  [c1[2], c1[3]] = [c1[3], c1[2]];
  assert.match(errs(report({ client1: c1 })), /client1: Siege events differ from the host's/);
  const missing = drillEvents();
  missing.splice(3, 1);
  assert.match(errs(report({ client1: missing })), /client1: Siege events differ/);
});

test('the restarted client holds a tail that reaches wave_end', () => {
  assert.equal(ec.checkReport(report({ client2: drillEvents().slice(3) })).ok, true);
  const odd = drillEvents().slice(3);
  odd[0] = { type: 'kill', id: 99, et: 1, src: 3, x2: 0 };
  assert.match(errs(report({ client2: odd })), /client2: its events are not a tail of the host's/);
  const none = [];
  assert.match(errs(report({ client2: none })), /client2: the restarted client recorded no Siege events/);
  const noEnd = drillEvents().slice(1, 4);
  assert.match(errs(report({ client2: noEnd })), /client2: the restarted client never saw wave_end/);
});

test('finished must be complete and present on the host', () => {
  const r = report();
  r.peers.client1.events = r.peers.client1.events.map((e) => (e.type === 'finished' ? { type: 'finished', reason: 'timeout' } : e));
  assert.match(errs(r), /client1: finished with reason "timeout"/);
  const none = report();
  none.peers.host.events = none.peers.host.events.filter((e) => e.type !== 'finished');
  assert.match(errs(none), /host: no finished event/);
});

test('a recorder without finished events is judged by each peer exit_reason', () => {
  const r = report();
  for (const [name, p] of Object.entries(r.peers)) {
    p.events = p.events.filter((e) => e.type !== 'finished');
    p.exit_reason = 'complete';
    assert.ok(name);
  }
  assert.deepEqual(ec.checkReport(r).errors, []);
  r.peers.client1.exit_reason = 'timeout';
  assert.match(errs(r), /client1: exit_reason "timeout"/);
  r.peers.client1.exit_reason = 'complete';
  r.peers.host.exit_reason = 'error';
  assert.match(errs(r), /host: no finished event/);
});

test('a Breach running at wave_end may end with gate_restored after it, once', () => {
  const withBreach = (restore) => {
    const e = drillEvents();
    e.splice(6, 0, { type: 'breach', n: 1 });
    return restore ? [...e, { type: 'gate_restored', hp: 30 }] : e;
  };
  const ok = withBreach(true);
  assert.deepEqual(errs(report({ host: ok, client1: ok, client2: ok.slice(-3) })), '');
  // Without a Breach before wave_end the same event is a stray.
  const stray = [...drillEvents(), { type: 'gate_restored', hp: 30 }];
  assert.match(errs(report({ host: stray, client1: stray })), /gate_restored after wave_end/);
  // A second restore, or other combat, after wave_end still fails.
  const twice = [...withBreach(true), { type: 'gate_restored', hp: 30 }];
  assert.match(errs(report({ host: twice, client1: twice })), /gate_restored after wave_end/);
  const kill = [...withBreach(true), { type: 'kill', id: 70, et: 1, src: 3, x2: 0 }];
  assert.match(errs(report({ host: kill, client1: kill })), /kill after wave_end/);
});

test('the drill has no Overdrive, no Siege directive and no shield bearer', () => {
  const od = [...drillEvents().slice(0, 7), { type: 'overdrive', slot: 0, st: 1, scored: 0, why: '' }, drillEvents()[7]];
  assert.match(errs(report({ host: od, client1: od })), /an overdrive event in the drill/);
  const dir = [{ peer_role: 'host', id: 1, requested: { mode: 'SIM', duration_s: 30, reason: 'overdrive', source: 'siege' } }];
  assert.match(errs(report({ directives: dir })), /1 Siege directives in the drill/);
  const sw = drillEvents();
  sw[3] = { type: 'kill', id: 4, et: 2, src: 11, x2: 0 };
  assert.match(errs(report({ host: sw, client1: sw })), /a shield bearer in the drill/);
});

test('Overdrive events outside the drill must pair up per slot', () => {
  const pairs = (list) => ec.overdrivePairing(list.map((st) => ({ type: 'overdrive', slot: 0, st, scored: 0, why: st === 2 ? 'x' : '' })));
  assert.deepEqual(pairs([1, 0, 1, 0]), []);
  assert.deepEqual(pairs([1, 2, 1, 0]), []);
  assert.match(pairs([1, 1]).join(), /started twice/);
  assert.match(pairs([0]).join(), /ended without a start/);
  assert.deepEqual(ec.eventErrors({ type: 'overdrive', slot: 0, st: 1, scored: 0, why: '' }), []);
  assert.match(ec.eventErrors({ type: 'overdrive', slot: 0, st: 2, scored: 0, why: '' }).join(), /refusal needs a reason/);
  assert.match(ec.eventErrors({ type: 'overdrive', slot: 0, st: 3, scored: 0, why: '' }).join(), /st 3 outside/);
  // Outside the drill, Overdrive events are allowed (and the drill's phase numbers do not apply).
  const od = [...drillEvents().slice(0, 7), { type: 'overdrive', slot: 0, st: 1, scored: 0, why: '' }, { type: 'overdrive', slot: 0, st: 0, scored: 1, why: '' }, drillEvents()[7]];
  od[0] = { ...od[0], ph: 2 };
  const other = report({ host: od, client1: od, client2: od.slice(-3) });
  other.content_id = 'short';
  assert.deepEqual(ec.checkReport(other).errors, []);
});

test('FIT laps: the drill has 3', () => {
  const ok = { host: { json: { files: [{ laps: [{}, {}, {}] }] } } };
  assert.equal(ec.checkReport(report({ fit_check: ok })).ok, true);
  const bad = { host: { json: { files: [{ laps: [{}, {}] }] } } };
  assert.match(errs(report({ fit_check: bad })), /host: 2 FIT laps, wanted 3/);
});

test('every kind of event passes its own schema', () => {
  const good = [
    { type: 'wave_start', ph: 4, role: 'wave', n: 2, waves: 6, b: 100 },
    { type: 'wave_end', ph: 4, n: 2, hp: 72, max: 125, leaks: 3 },
    { type: 'dock', id: 1 },
    { type: 'reach', id: 3, et: 4 },
    { type: 'push', id: 1, et: 5, prog_dm: 2554 },
    { type: 'rush', on: 1, i: 0 },
    { type: 'kill', id: 1, et: 5, src: 2, x2: 1 },
    { type: 'leak', id: 2, et: 1, dmg: 2 },
    { type: 'breach', n: 1 },
    { type: 'gate_restored', hp: 30 },
    { type: 'buy', slot: 1, item: 'scorpion', station: 0, pad: 3, ok: 1, why: '', lvl: 0 },
    { type: 'route', slot: 2, to: 4 },
    { type: 'shot', tk: 9, src: 13, kind: 3, o: [1, 2, 3], v: [4, 5, 6], n: 2, sd: 7 },
    { type: 'overdrive', slot: 3, st: 0, scored: 1, why: 'rescue' },
  ];
  assert.equal(good.length, ec.EVENT_TYPES.length);
  for (const e of good) assert.deepEqual(ec.eventErrors(e), [], JSON.stringify(e));
  assert.match(ec.eventErrors({ type: 'nope' }).join(), /unknown event type/);
});

test('the CLI exits 0, 1 and 2', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'e2e-siege-'));
  const file = path.join(d, 'report.json');
  fs.writeFileSync(file, JSON.stringify(report()));
  const run = (...a) => spawnSync(process.execPath, [path.join(here, 'e2e_check.mjs'), ...a], { encoding: 'utf8' });
  let r = run(file);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /PASS/);
  fs.writeFileSync(file, JSON.stringify(report({ client1: drillEvents().slice(2) })));
  r = run(file);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /FAIL client1/);
  assert.equal(run().status, 2);
  assert.equal(run(path.join(d, 'missing.json')).status, 2);
  fs.writeFileSync(file, '{');
  assert.equal(run(file).status, 2);
});
