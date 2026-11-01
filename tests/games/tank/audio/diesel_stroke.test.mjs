// The strokes at the top of the diesel's cylinders read as a big engine, not a toy. The owner played rc.2 and heard "a
// wierd sound with the cylinders ... a little too much like a toy" when they top out. Each of the machine's six tops per
// revolution had a stroke just ahead of it: three fires with an exhaust tick, three bare inlet ticks. The rc.2 reading of
// each limit is on its right: the old bank fails here. diesel_stroke.mjs prints every number. They say where a stroke's
// energy is and how long it lasts; nobody's ear is in them.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { FIRES, HARD, IN_BAND, OVERLAY, shapeOf, strokeOf, strokes, VALVES } from './diesel_stroke.mjs';
import { crewMix, earBand, openBank, RPMS, solo, soloLufs, toMono, WORKING } from './ear_band.mjs';
import { simulate } from '../../../../tools/audio/lib/offline_mix.mjs';

const bank = openBank();
const doc = bank.doc;
const events = doc.machines.diesel.events;
const eventOf = (sound) => events.find((e) => e.sound === sound);

const FIRE = {
  clickHz: 1300, // 1946 to 2698
  bodyToClick: -10, // -24.1 to -10.8
  earShare: -13.5, // -22.4 to -8.1
  ringMs: 85, // 52 to 74
};
/** Their lowest and highest lines: a fundamental under far thumps would mask them (cue_reads.test.mjs). */
const LINE_HZ = { diesel_fire_a: [78, 100], diesel_fire_b: [88, 115], diesel_fire_c: [72, 90] }; // 108-118, 129-140, 92-97

for (const sound of FIRES) {
  for (const rpm of RPMS) {
    test(`${sound} at ${rpm} rpm is a thump with a body, not a snap`, () => {
      const m = strokes(bank, sound, rpm, IN_BAND);
      assert.ok(m.clickHz <= FIRE.clickHz, `first 10 ms centred at ${m.clickHz.toFixed(0)} Hz, limit ${FIRE.clickHz}`);
      assert.ok(m.bodyToClick >= FIRE.bodyToClick, `body ${m.bodyToClick.toFixed(1)} dB against the click, floor ${FIRE.bodyToClick}`);
      assert.ok(m.earShare <= FIRE.earShare, `2-8 kHz ${m.earShare.toFixed(1)} dB of its total, limit ${FIRE.earShare}`);
      assert.ok(m.ringMs >= FIRE.ringMs, `falls 30 dB in ${m.ringMs} ms, floor ${FIRE.ringMs}`);
      const [lo, hi] = LINE_HZ[sound];
      assert.ok(m.lineHz >= lo && m.lineHz <= hi, `heard at ${m.lineHz.toFixed(0)} Hz, ${lo} to ${hi}`);
    });
  }
}

test('the three cylinders stay unequal: C lowest and longest, B highest and shortest', () => {
  const [a, b, c] = FIRES.map((s) => strokes(bank, s, 90, IN_BAND));
  assert.ok(c.lineHz < a.lineHz && a.lineHz < b.lineHz, `lines ${a.lineHz.toFixed(0)}, ${b.lineHz.toFixed(0)}, ${c.lineHz.toFixed(0)} Hz`);
  assert.ok(b.ringMs < a.ringMs && a.ringMs < c.ringMs, `${a.ringMs}, ${b.ringMs}, ${c.ringMs} ms`);
  assert.ok(c.earShare < a.earShare && a.earShare < b.earShare, `${a.earShare.toFixed(1)}, ${b.earShare.toFixed(1)}, ${c.earShare.toFixed(1)} dB`);
});

for (const sound of FIRES) {
  test(`${sound} doesn't wind up with the cadence, and no two strokes match`, () => {
    const low = strokes(bank, sound, 60, IN_BAND);
    const high = strokes(bank, sound, 110, IN_BAND);
    const rise = high.centsMedian - low.centsMedian;
    assert.ok(rise <= 40, `${rise.toFixed(0)} cents from 60 to 110 rpm, limit 40 (129 in rc.2)`);
    assert.ok(high.centsSpan >= 30 && high.peakSpan >= 1.5, `${high.centsSpan.toFixed(0)} cents, ${high.peakSpan.toFixed(1)} dB between strokes`);
  });
}

for (const sound of VALVES) {
  test(`${sound} is a dull knock with some weight, not a tick`, () => {
    const m = strokes(bank, sound, 90, IN_BAND);
    assert.ok(m.clickHz <= 1200, `first 10 ms centred at ${m.clickHz.toFixed(0)} Hz, limit 1200 (2923 and 2570)`);
    assert.ok(m.bodyToClick >= -28, `body ${m.bodyToClick.toFixed(1)} dB against the click, floor -28 (-39.1 and -45.8)`);
    assert.ok(m.lowToHigh >= 15, `under 300 Hz ${m.lowToHigh.toFixed(1)} dB over 1.5 kHz and up, floor 15 (-8.7)`);
    assert.ok(m.earShare <= -25, `2-8 kHz ${m.earShare.toFixed(1)} dB of its total, limit -25 (-15.7 and -14.1)`);
    assert.ok(m.lineHz <= 300, `heard at ${m.lineHz.toFixed(0)} Hz, limit 300 (964 and 1206)`);
    assert.ok(m.ringMs >= 28, `falls 30 dB in ${m.ringMs} ms, floor 28 (20 and 14)`);
  });

  test(`${sound} differs stroke to stroke and doesn't swell with the cadence`, () => {
    const low = strokes(bank, sound, 60, IN_BAND);
    const high = strokes(bank, sound, 110, IN_BAND);
    assert.ok(high.centsSpan >= 30, `${high.centsSpan.toFixed(0)} cents between strokes, floor 30 (0)`);
    assert.ok(high.peakSpan >= 1, `${high.peakSpan.toFixed(1)} dB between strokes, floor 1 (0)`);
    const swell = high.peakDb - low.peakDb;
    assert.ok(swell <= 3, `${swell.toFixed(1)} dB from 60 to 110 rpm, limit 3 (5)`);
    // Three strokes a revolution: three takes would give each cylinder its own for good, and a table can't hide that.
    assert.notEqual(doc.sounds[sound].variants % 3, 0, 'takes in step with the cylinders');
  });
}

test('a knock stays under the cylinder it comes with', () => {
  const quietestFire = Math.min(...FIRES.map((s) => strokes(bank, s, 90, IN_BAND).peakDb));
  for (const sound of VALVES) {
    const m = strokes(bank, sound, 90, IN_BAND);
    assert.ok(m.peakDb < quietestFire, `${sound} ${m.peakDb.toFixed(1)} dB, the quietest fire ${quietestFire.toFixed(1)} dB`);
  }
});

test('the overlay over 100 % FTP thickens the stroke, with no blip on top', () => {
  const m = strokes(bank, OVERLAY, 90, HARD);
  assert.ok(m.clickHz <= 1400, `first 10 ms centred at ${m.clickHz.toFixed(0)} Hz, limit 1400 (4322)`);
  assert.ok(m.earShare <= -15, `2-8 kHz ${m.earShare.toFixed(1)} dB of its total, limit -15 (-2.2)`);
  assert.ok(m.ringMs >= 35, `falls 30 dB in ${m.ringMs} ms, floor 35 (26)`);
});

test("no stroke of the diesel is a chip's pulse or square", () => {
  for (const sound of [...FIRES, ...VALVES, OVERLAY]) {
    for (const layer of doc.sounds[sound].layers) assert.ok(!['pulse', 'square'].includes(layer.src), `${sound}: ${layer.src}`);
  }
});

test('every stroke keeps its phase, one for one with the crank', () => {
  const at = Object.fromEntries(events.map((e) => [e.sound, e.at]));
  assert.deepEqual(at.diesel_fire_a, [0.2778]);
  assert.deepEqual(at.diesel_fire_b, [0.6111]);
  assert.deepEqual(at.diesel_fire_c, [0.9444]);
  assert.deepEqual(at.diesel_fire_hard, [0.2778, 0.6111, 0.9444]);
  assert.deepEqual(at.diesel_valve_ex, [0.3, 0.6333, 0.9667]);
  assert.deepEqual(at.diesel_valve_in, [0.1111, 0.4444, 0.7778]);
  for (const rpm of RPMS) {
    const s = (20 * 60) / rpm;
    const sim = simulate(bank, { segments: [{ rpm, s, params: IN_BAND }], machines: [{ id: 'l', machine: 'diesel', lead: true }], duration: s });
    for (const sound of FIRES) {
      const n = sim.voices.filter((v) => v.sound === sound && v.t <= s).length;
      assert.equal(n, 20, `${sound} at ${rpm} rpm`);
    }
  }
});

/** The machine alone, rc.2: 2-8 kHz against its total, its loudest moment, its level. */
const RC2_EAR = {
  60: { 1: { share: -10.22, worst: -1.33, level: -34.44 }, 1.2: { share: -8.45, worst: -0.67, level: -31.01 } },
  90: { 1: { share: -10.64, worst: -2.85, level: -33.38 }, 1.2: { share: -9.07, worst: -2.17, level: -30.23 } },
  110: { 1: { share: -10.84, worst: -3.59, level: -33.03 }, 1.2: { share: -9.38, worst: -3.02, level: -30.04 } },
};

for (const rpm of RPMS) {
  for (const power of [1, 1.2]) {
    test(`the engine seat at ${rpm} rpm, power ${power}, has no more in 2-8 kHz than rc.2`, () => {
      const was = RC2_EAR[rpm][power];
      const e = earBand(solo(bank, 'diesel', rpm, { power, ...WORKING.diesel }));
      assert.ok(e.share <= was.share, `share ${e.share.toFixed(2)}, rc.2 ${was.share}`);
      assert.ok(e.worst <= was.worst - 3, `loudest moment ${e.worst.toFixed(2)}, 3 dB under rc.2's ${was.worst}`);
      assert.ok(e.level <= was.level, `level ${e.level.toFixed(2)}, rc.2 ${was.level}`);
    });
  }
}

test('a full crew with the diesel leading has no more in 2-8 kHz than rc.2', () => {
  const e = earBand(toMono(crewMix(bank, 'diesel').master));
  assert.ok(e.share <= -11.0, `share ${e.share.toFixed(2)}, rc.2 -11.0`);
  assert.ok(e.level <= -32.5, `level ${e.level.toFixed(2)}, rc.2 -32.5`);
});

test('it is the same size of engine in the mix: heavier, not just quieter', () => {
  const lufs = soloLufs(bank, 'diesel', 90, { power: 1, ...WORKING.diesel });
  assert.ok(lufs >= -21.3 && lufs <= -20.1, `${lufs.toFixed(2)} LUFS at 90 rpm, rc.2 -20.70`);
});

test('the shape reads a tick as a tick: the measure itself', () => {
  const rate = 44100;
  const tick = new Float64Array(Math.round(0.03 * rate));
  const thump = new Float64Array(Math.round(0.2 * rate));
  for (let i = 0; i < tick.length; i++) tick[i] = Math.sin((2 * Math.PI * 1500 * i) / rate) * Math.exp(-i / (0.003 * rate));
  for (let i = 0; i < thump.length; i++) thump[i] = Math.sin((2 * Math.PI * 80 * i) / rate) * Math.exp(-i / (0.04 * rate));
  const t = shapeOf(tick);
  const h = shapeOf(thump);
  assert.ok(t.clickHz > h.clickHz, `${t.clickHz.toFixed(0)} against ${h.clickHz.toFixed(0)} Hz`);
  assert.ok(h.bodyToClick > t.bodyToClick);
  assert.ok(h.ringMs > t.ringMs);
  assert.ok(Math.abs(h.lineHz - 80) < 6, `line ${h.lineHz.toFixed(1)} Hz`);
  assert.ok(strokeOf(bank, { sound: 'diesel_valve_in', variant: 0, pitch: 1, db: 0 }).length > 0);
});
