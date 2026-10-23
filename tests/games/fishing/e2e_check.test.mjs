// node --test tests/games/fishing/e2e_check.test.mjs: e2e_check.mjs on the synthetic e2e report
// in sim/fixtures/e2e/ and on broken variants of it. Independent of build/.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import * as ec from './e2e_check.mjs';
import { e2eReport } from './sim/fixtures/make_fixtures.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE = path.join(here, 'sim', 'fixtures', 'e2e', 'report.json');
const errs = (r) => ec.checkReport(r).errors.join('\n');
const gameEvents = (log) => log.filter((e) => e.type === 'game_event');

function sink() {
  let text = '';
  return { write: (s) => (text += s), get text() { return text; } };
}

test('the fixture on disk is what make_fixtures.mjs builds, and it passes', () => {
  const disk = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));
  assert.deepEqual(disk, JSON.parse(JSON.stringify(e2eReport())));
  const v = ec.checkReport(disk);
  assert.deepEqual(v.errors, []);
  assert.equal(v.info.hostEvents, 10);
  assert.equal(v.info.lanes, 3);
  assert.equal(v.info.victimEvents, 6);
  const out = sink();
  assert.equal(ec.main([FIXTURE], out, sink()), 0);
  assert.match(out.text, /e2e_check fishing: PASS/);
});

test('events_by_peer is read when the peers carry no events', () => {
  const r = e2eReport();
  r.events_by_peer = { 1: r.peers.host.events, 2: r.peers.client1.events, 3: r.peers.client2.events };
  for (const p of Object.values(r.peers)) delete p.events;
  assert.equal(ec.checkReport(r).ok, true, errs(r));
});

test('a lane without its mackerel, or with another fish, fails', () => {
  const r = e2eReport();
  for (const role of ['host', 'client1', 'client2']) r.peers[role].events = r.peers[role].events.filter((e) => !(e.event?.type === 'landed' && e.event.l === 2));
  assert.match(errs(r), /lane 2 landed nothing \(wanted one mackerel\)/);
  const t = e2eReport();
  for (const role of ['host', 'client1', 'client2']) for (const e of gameEvents(t.peers[role].events)) if (e.event.type === 'landed' && e.event.l === 1) e.event.sp = 2;
  assert.match(errs(t), /lane 1 landed tuna/);
});

test('a client whose events differ, or a restarted client that is not a tail, fails', () => {
  const r = e2eReport();
  gameEvents(r.peers.client1.events)[4].event.sp = 1;
  assert.match(errs(r), /client1: Fishing events differ from the host's/);
  const v = e2eReport();
  gameEvents(v.peers.client2.events)[0].event.l = 2;
  assert.match(errs(v), /client2: its events are not a tail/);
  const empty = e2eReport();
  empty.peers.client2.events = empty.peers.client2.events.filter((e) => e.type !== 'game_event');
  assert.equal(ec.checkReport(empty).ok, true, 'a client restarted after the last event holds an empty tail');
});

test('unknown events and non-int fields fail on any peer', () => {
  const r = e2eReport();
  r.peers.client1.events.push({ type: 'game_event', event: { type: 'kraken' }, t: 100 });
  gameEvents(r.peers.client2.events).find((e) => e.event.type === 'landed').event.points = '21';
  const msgs = errs(r);
  assert.match(msgs, /client1: applied unknown event "kraken"/);
  assert.match(msgs, /client2: .*points is not an int/);
});

test('a trip that reaches the cool-down after 135 s fails', () => {
  const r = e2eReport();
  for (const e of r.peers.host.events) if (e.type === 'phase_started' && e.peer === 3 && e.index === 4) e.t = 150;
  assert.match(errs(r), /rider 3 reached the cool-down 148.5 s after the ride out/);
  const m = e2eReport();
  m.peers.host.events = m.peers.host.events.filter((e) => !(e.type === 'phase_started' && e.index === 4 && e.peer === 2));
  assert.match(errs(m), /rider 2 never reached the cool-down/);
});

test('forbidden clamps, refusals and malformed requests fail; allowed clamps pass', () => {
  const r = e2eReport();
  r.directives[0].clamped_by = ['long_phase'];
  r.directives[1].refused = true;
  r.directives[2].requested.reason = 'sprint';
  r.peers.client1.trace.push({ t: 70, clamped_by: ['ceiling'] });
  const msgs = errs(r);
  assert.match(msgs, /host: directive 1: clamped_by long_phase \(forbidden/);
  assert.match(msgs, /client1: directive 1: refused/);
  assert.match(msgs, /client2: directive 1: reason "sprint"/);
  assert.match(msgs, /client1: trace at 70 s: clamped_by ceiling/);
  const ok = e2eReport();
  ok.directives[0].clamped_by = ['slew', 'floor', 'unverified', 'rescue', 'coasting', 'warmup', 'switch_ramp'];
  assert.equal(ec.checkReport(ok).ok, true, errs(ok));
});

test('the per-peer directive lists are read when the top-level list is empty', () => {
  const r = e2eReport();
  r.peers.client1.directives = [{ ...r.directives[0], clamped_by: ['limit_105'] }];
  r.directives = [];
  assert.match(errs(r), /client1: directive 1: clamped_by limit_105/);
});

test('a bad exit reason and the wrong FIT lap count fail', () => {
  const r = e2eReport();
  r.peers.client2.exit_reason = 'timeout';
  r.fit_check.client1.json.files[0].laps = [{}, {}, {}];
  const msgs = errs(r);
  assert.match(msgs, /client2: exit_reason "timeout"/);
  assert.match(msgs, /client1: 3 FIT laps, wanted 4/);
});

test('the CLI exits 1 on a failing report and 2 on usage or I/O errors', () => {
  const r = e2eReport();
  r.peers.host.events = r.peers.host.events.filter((e) => e.type !== 'game_event');
  const tmp = path.join(here, 'sim', 'fixtures', 'e2e', `.tmp_${process.pid}.json`);
  fs.writeFileSync(tmp, JSON.stringify(r));
  try {
    const out = sink();
    assert.equal(ec.main([tmp], out, sink()), 1);
    assert.match(out.text, /FAIL host: lane 0 landed nothing/);
  } finally {
    fs.rmSync(tmp, { force: true });
  }
  assert.equal(ec.main([], sink(), sink()), 2);
  assert.equal(ec.main([path.join(here, 'no_such_report.json')], sink(), sink()), 2);
  assert.equal(ec.checkReport({}).ok, false);
});
