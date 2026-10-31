// The JS port of the kit's pure classes. The parity table is the same one tests/audio/test_audio_parity.gd
// asserts on the GDScript side (SPEC_AUDIO 2.6): if this file and that one both pass, preview and game agree.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { AmbienceBed, CadenceVoice, CrankClock, LATE_MAX_S, LayeredLoop, OFF_DB, STOP_RPM, curveEval, curvePasses, curveProduct, curveSumDb } from '../lib/pattern.mjs';

const DT = 0.05;
const HORIZON = 0.05;

/** Each frame: advance revs by dt, then plan. Returns the attack times. */
function attacks(rpmOf, seconds, pattern) {
  const clock = new CrankClock();
  const voice = new CadenceVoice([{ at: pattern, sound: 's' }]);
  const out = [];
  const frames = Math.round(seconds / DT);
  for (let i = 0; i < frames; i++) {
    const t = i * DT;
    const rpm = rpmOf(t);
    clock.advance(rpm, DT);
    const now = (i + 1) * DT;
    for (const ev of voice.plan(clock.revs, rpm, HORIZON, {}, true)) out.push(now + ev.at_s);
  }
  return out;
}

function close(a, b, tol = 1e-6) {
  assert.equal(a.length, b.length, `${a} vs ${b}`);
  a.forEach((v, i) => assert.ok(Math.abs(v - b[i]) <= tol, `${v} vs ${b[i]} at ${i}`));
}

test('parity A: 90 rpm for 2.0 s, [.25, .75]', () => {
  close(attacks(() => 90, 2, [0.25, 0.75]), [1 / 6, 0.5, 5 / 6, 7 / 6, 1.5, 11 / 6]);
});

test('parity B: 60 until t=1.0, then 120 until 2.0, [0, .5]', () => {
  close(attacks((t) => (t < 1 - 1e-9 ? 60 : 120), 2, [0, 0.5]), [0.5, 1.0, 1.25, 1.5, 1.75, 2.0]);
});

test('parity C: 90 until t=1.0, 0 until 2.0, 90 until 3.0, [.25, .75]', () => {
  close(attacks((t) => (t < 1 - 1e-9 || t >= 2 - 1e-9 ? 90 : 0), 3, [0.25, 0.75]), [1 / 6, 0.5, 5 / 6, 13 / 6, 2.5, 17 / 6]);
});

test('CrankClock: stands still at or below STOP_RPM, counts crossings', () => {
  const c = new CrankClock();
  assert.equal(c.advance(STOP_RPM, 1), 0);
  assert.equal(c.advance(0, 1), 0);
  assert.equal(c.revs, 0);
  assert.equal(c.advance(60, 2.5), 2);
  assert.equal(c.frac(), 0.5);
  assert.equal(c.advance(60, -1), 0);
});

test('no event is lost or doubled across rpm and frame times, jittery frames too', () => {
  for (const rpm of [30, 60, 90, 140]) {
    for (const dt of [1 / 144, 1 / 60, 1 / 30, 0.05]) {
      const clock = new CrankClock();
      const voice = new CadenceVoice([{ at: [0.2778, 0.6111, 0.9444], sound: 's' }]);
      const seen = [];
      const frames = Math.round(30 / dt);
      for (let i = 0; i < frames; i++) {
        clock.advance(rpm, dt);
        for (const ev of voice.plan(clock.revs, rpm, 0.05, {}, true)) seen.push(ev.pos);
      }
      const to = voice._to;
      let expect = 0;
      for (let k = 0; k <= Math.floor(to); k++) for (const f of [0.2778, 0.6111, 0.9444]) if (k + f <= to) expect++;
      assert.equal(voice.fired, expect, `${rpm} rpm ${dt}`);
      assert.equal(new Set(seen.map((p) => p.toFixed(6))).size, seen.length);
      assert.equal(voice.dropped, 0);
    }
  }
});

test('a hitch drops what is older than LATE_MAX_S; fired + dropped stays exact', () => {
  const clock = new CrankClock();
  const voice = new CadenceVoice([{ at: [0, 0.25, 0.5, 0.75], sound: 's' }]);
  const rpm = 140;
  for (let i = 0; i < 60; i++) {
    clock.advance(rpm, 1 / 60);
    voice.plan(clock.revs, rpm, 0.025, {}, true);
  }
  const firedBefore = voice.fired;
  clock.advance(rpm, 1.0);
  const burst = voice.plan(clock.revs, rpm, 0.025, {}, true);
  assert.ok(voice.dropped > 0);
  assert.ok(burst.length <= Math.ceil((rpm / 60) * (LATE_MAX_S + 0.025) * 4) + 1, 'no burst');
  const expect = Math.floor(voice._to * 4) + 0;
  assert.equal(voice.fired + voice.dropped, expect);
  assert.ok(voice.fired > firedBefore);
});

test('stop: nothing is planned at rest, restart has no burst', () => {
  const clock = new CrankClock();
  const voice = new CadenceVoice([{ at: [0.5], sound: 's' }]);
  for (let i = 0; i < 60; i++) {
    clock.advance(60, 1 / 60);
    voice.plan(clock.revs, 60, 0.025, {}, true);
  }
  for (let i = 0; i < 300; i++) {
    clock.advance(0, 1 / 60);
    assert.deepEqual(voice.plan(clock.revs, 0, 0.025, {}, true), []);
  }
  const fired = voice.fired;
  clock.advance(60, 1 / 60);
  assert.deepEqual(voice.plan(clock.revs, 60, 0.025, {}, true), []);
  assert.equal(voice.fired, fired);
});

test('a reset source reprimes with no burst and no error', () => {
  const voice = new CadenceVoice([{ at: [0.5], sound: 's' }]);
  voice.plan(100, 60, 0.025, {}, true);
  assert.deepEqual(voice.plan(0, 60, 0.025, {}, true), []);
  assert.equal(voice.plan(0.49, 60, 0.025, {}, true).length, 1);
});

test('gates: lead_only, when; the gated count is kept', () => {
  const v = new CadenceVoice([{ at: [0.5], sound: 's', lead_only: true }]);
  v.plan(0, 60, 0, {}, false);
  assert.deepEqual(v.plan(0, 60, 0.6, {}, false), []);
  assert.equal(v.gated, 1);
  const w = new CadenceVoice([{ at: [0.5], sound: 's', when: { param: 'power', min: 0.5 } }]);
  w.plan(0, 60, 0, {}, true);
  assert.deepEqual(w.plan(0, 60, 0.6, { power: 0.1 }, true), []);
  assert.equal(w.plan(0, 60, 1.6, { power: 0.5 }, true).length, 1);
});

test('emit: round-robin variants per sound, a cycling pitch table, db and pitch curves', () => {
  const v = new CadenceVoice(
    [{ at: [0, 0.5], sound: 's', db: -3, db_by: [{ param: 'power', points: [[0, -9], [1, 0]] }], pitch_by: [{ param: 'rpm', ratio: 60 }], pitch_table: [0, 0.1], priority: 7 }],
    () => 3,
  );
  v.plan(0, 60, 0, {}, true);
  const evs = v.plan(0, 60, 2.25, { power: 1, rpm: 60 }, true);
  assert.deepEqual(evs.map((e) => e.pos), [0.5, 1, 1.5, 2]);
  assert.deepEqual(evs.map((e) => e.variant), [0, 1, 2, 0]);
  assert.equal(evs[0].db, -3);
  assert.equal(evs[0].priority, 7);
  assert.equal(evs[0].pitch, 1);
  assert.ok(Math.abs(evs[1].pitch - 1.1) < 1e-9);
  assert.equal(evs[2].pitch, 1);
  assert.equal(evs[0].sound, 's');
});

test('events come out sorted and a late one is counted', () => {
  const v = new CadenceVoice([{ at: [0.75, 0.25], sound: 's' }]);
  v.plan(0, 60, 0, {}, true);
  const evs = v.plan(0.05, 60, 0.9, {}, true);
  assert.deepEqual(evs.map((e) => e.pos), [0.25, 0.75]);
  assert.equal(v.late, 0);
  const u = new CadenceVoice([{ at: [0.04], sound: 's' }]);
  u.plan(0, 60, 0, {}, true);
  u.plan(0.05, 60, 0, {}, true);
  assert.equal(u.late, 1, 'due before now: at_s is 0');
});

test('AudioCurve', () => {
  const pts = { param: 'p', points: [[0, -10], [1, 0], [2, 4]] };
  assert.equal(curveEval(pts, { p: -1 }), -10);
  assert.equal(curveEval(pts, { p: 0.5 }), -5);
  assert.equal(curveEval(pts, { p: 1.5 }), 2);
  assert.equal(curveEval(pts, { p: 9 }), 4);
  assert.equal(curveEval(pts, {}), -10, 'missing reads 0');
  assert.equal(curveEval({ param: 'rpm', ratio: 90 }, { rpm: 45 }), 0.5);
  assert.equal(curveSumDb([pts, pts], { p: 0.5 }), -10);
  assert.equal(curveSumDb([], {}), 0);
  assert.equal(curveProduct([{ param: 'a', ratio: 2 }, { param: 'b', ratio: 4 }], { a: 1, b: 2 }), 0.25);
  assert.equal(curveProduct([], {}), 1);
  assert.ok(curvePasses({}, {}));
  assert.ok(curvePasses({ param: 'p', min: 1, max: 2 }, { p: 1 }));
  assert.ok(curvePasses({ param: 'p', min: 1, max: 2 }, { p: 2 }));
  assert.ok(!curvePasses({ param: 'p', min: 1 }, { p: 0.9 }));
  assert.ok(!curvePasses({ param: 'p', max: 1 }, { p: 1.1 }));
});

test('LayeredLoop: closes under 120 ms at a stop; other layers obey `other`', () => {
  const l = new LayeredLoop([{ db: 0, min_rpm: 8, other: true, pitch_by: [{ param: 'rpm', ratio: 90 }] }, { db: 0, min_rpm: 8 }]);
  for (let i = 0; i < 60; i++) l.update({ rpm: 90 }, 0, true, 1 / 60);
  assert.ok(Math.abs(l.db[0]) < 0.1);
  assert.equal(l.on[0], 1);
  let frames = 0;
  while (l.on[0] === 1) {
    l.update({ rpm: 0 }, 0, true, 1 / 60);
    frames++;
  }
  assert.ok(frames / 60 <= 0.12, `${frames} frames`);
  assert.equal(l.db[0], OFF_DB);
  for (let i = 0; i < 60; i++) l.update({ rpm: 90 }, -10, false, 1 / 60);
  assert.ok(Math.abs(l.db[0] + 10) < 0.2, 'other layer plays at the trim');
  assert.equal(l.on[1], 0, 'a lead layer stays off for another rider');
});

test('LayeredLoop: a layer that was off takes its pitch at once, then slews slowly', () => {
  const l = new LayeredLoop([{ db: 0, pitch_by: [{ param: 'rpm', ratio: 90 }], slew_s: 0.25 }]);
  l.update({ rpm: 90 }, 0, true, 1 / 60);
  assert.equal(l.pitch[0], 1);
  l.update({ rpm: 93 }, 0, true, 1 / 60);
  const step = Math.abs(l.pitch[0] - 1);
  assert.ok(step > 0 && step < 0.01, 'a 3 rpm step moves it under 1 % a frame');
});

test('AmbienceBed: spot_min_gap_s keeps details apart, bursts counted, and leaves a texture alone', () => {
  const spots = [
    { sound: 'a', gap_s: [3, 5], db: -10, burst: 2, burst_gap_s: 0.7 },
    { sound: 'b', gap_s: [3, 5], db: -10 },
    { sound: 'c', gap_s: [3, 5], db: -10 },
    { sound: 'tex', gap_s: [0.5, 1], db: -10 },
  ];
  const run = (spec, seed) => {
    const bed = new AmbienceBed(spec, seed);
    const out = [];
    for (let i = 0; i < 60 * 300; i++) for (const e of bed.update({}, 1 / 60)) out.push({ ...e, t: i / 60 + e.at_s });
    return out.sort((x, y) => x.t - y.t);
  };
  const closest = (evs) => {
    const d = evs.filter((e) => e.sound !== 'tex');
    let m = Infinity;
    for (let i = 1; i < d.length; i++) if (d[i].sound !== d[i - 1].sound) m = Math.min(m, d[i].t - d[i - 1].t);
    return m;
  };
  assert.ok(closest(run({ spots }, 5)) < 1, 'off by default, the timers run free');
  const spaced = run({ spots, spot_min_gap_s: 2 }, 5);
  assert.ok(closest(spaced) >= 2 - 1 / 60, `${closest(spaced)}`);
  for (const s of ['a', 'b', 'c']) assert.ok(spaced.filter((e) => e.sound === s).length > 15, s);
  const tex = spaced.filter((e) => e.sound === 'tex');
  assert.ok(tex.length > 300, `a texture keeps its pace: ${tex.length}`);
});

test('AmbienceBed: a sound split into two spots by `when` keeps its round-robin across the switch', () => {
  const spec = { spots: [{ sound: 'a', gap_s: 1, when: { param: 'x', max: 0.5 } }, { sound: 'a', gap_s: 1, when: { param: 'x', min: 0.5 } }] };
  const bed = new AmbienceBed(spec, 3, () => 3);
  const out = [];
  for (let i = 0; i < 60 * 10; i++) out.push(...bed.update({ x: i < 60 * 5 ? 0 : 1 }, 1 / 60));
  assert.ok(out.length >= 8);
  for (let i = 0; i < out.length; i++) assert.equal(out[i].variant, i % 3);
});

test('AmbienceBed: seeded spots, bursts, `when`', () => {
  const spec = { layers: [], spots: [{ sound: 'a', gap_s: [0.5, 1], db: [-20, -10], pitch: [0.9, 1.1], burst: [2, 3], burst_gap_s: 0.09 }, { sound: 'b', gap_s: 0.5, db: -5, when: { param: 'x', min: 1 } }] };
  const run = (seed, x) => {
    const bed = new AmbienceBed(spec, seed, () => 2);
    const out = [];
    for (let i = 0; i < 600; i++) out.push(...bed.update({ x }, 1 / 60));
    return out;
  };
  assert.deepEqual(run(4, 0), run(4, 0));
  assert.notDeepEqual(run(4, 0), run(5, 0));
  const a = run(4, 0);
  assert.ok(a.length > 10);
  assert.ok(a.every((e) => e.sound === 'a' && e.db >= -20 && e.db <= -10 && e.pitch >= 0.9 && e.pitch <= 1.1));
  assert.ok(a.some((e) => e.at_s > 0), 'bursts');
  assert.ok(a.every((e) => e.at_s <= 1));
  assert.ok(a.some((e) => e.variant === 1) && a.some((e) => e.variant === 0));
  assert.ok(run(4, 1).some((e) => e.sound === 'b'));
});
