// The strokes at the top of the diesel's cylinders read as a big engine, not a toy. The owner played rc.2 and heard "a
// wierd sound with the cylinders ... a little too much like a toy" when they top out. Each of the machine's six tops per
// revolution had a stroke just ahead of it: three fires with an exhaust tick, three bare inlet ticks. The rc.2 reading of
// each limit is on its right: the old bank fails here. diesel_stroke.mjs prints every number. They say where a stroke's
// energy is and how long it lasts; nobody's ear is in them.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { FIRES, HARD, IN_BAND, OVERLAY, shapeOf, STEAM_BAND, strokeOf, strokes, tonalOf, VALVES, voicesOf } from './diesel_stroke.mjs';
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
/** Each line's range: under 78 Hz far thumps go under it (cue_reads.test.mjs), and rc.2 read 97 to 140. */
const LINE_HZ = [78, 105];

for (const sound of FIRES) {
  for (const rpm of RPMS) {
    test(`${sound} at ${rpm} rpm is a thump with a body, not a snap`, () => {
      const m = strokes(bank, sound, rpm, IN_BAND);
      assert.ok(m.clickHz <= FIRE.clickHz, `first 10 ms centred at ${m.clickHz.toFixed(0)} Hz, limit ${FIRE.clickHz}`);
      assert.ok(m.bodyToClick >= FIRE.bodyToClick, `body ${m.bodyToClick.toFixed(1)} dB against the click, floor ${FIRE.bodyToClick}`);
      assert.ok(m.earShare <= FIRE.earShare, `2-8 kHz ${m.earShare.toFixed(1)} dB of its total, limit ${FIRE.earShare}`);
      assert.ok(m.ringMs >= FIRE.ringMs, `falls 30 dB in ${m.ringMs} ms, floor ${FIRE.ringMs}`);
      const [lo, hi] = LINE_HZ;
      assert.ok(m.lineHz >= lo && m.lineHz <= hi, `heard at ${m.lineHz.toFixed(0)} Hz, ${lo} to ${hi}`);
    });
  }
}

test('the three cylinders stay unequal in length and colour, not in pitch: C longest and darkest, B shortest and brightest', () => {
  const [a, b, c] = FIRES.map((s) => strokes(bank, s, 90, IN_BAND));
  assert.ok(b.ringMs < a.ringMs && a.ringMs < c.ringMs, `${a.ringMs}, ${b.ringMs}, ${c.ringMs} ms`);
  assert.ok(c.clickHz < a.clickHz && a.clickHz < b.clickHz, `${a.clickHz.toFixed(0)}, ${b.clickHz.toFixed(0)}, ${c.clickHz.toFixed(0)} Hz`);
});

/** One line per stroke, in the order the cylinders fire, for `revs` revolutions. */
function linesByCylinder(rpm, revs = 90) {
  const voices = voicesOf(bank, rpm, IN_BAND, { revs });
  return FIRES.map((s) => voices.filter((v) => v.sound === s).map((v) => tonalOf(strokeOf(bank, v)).line));
}

for (const rpm of RPMS) {
  test(`at ${rpm} rpm the cylinders play no tune: within about 1.5 semitones, no cylinder owns a pitch`, () => {
    const lines = linesByCylinder(rpm);
    const all = lines.flat();
    const spread = 12 * Math.log2(Math.max(...all) / Math.min(...all));
    assert.ok(spread <= 1.6, `${spread.toFixed(2)} semitones across the three, limit 1.6 (rc.2 and the first version, 4.6 and up)`);
    for (let i = 0; i < 3; i++) {
      for (let j = i + 1; j < 3; j++) {
        const low = Math.max(Math.min(...lines[i]), Math.min(...lines[j]));
        const high = Math.min(Math.max(...lines[i]), Math.max(...lines[j]));
        assert.ok(high > low, `${FIRES[i]} and ${FIRES[j]} share no pitch: ${low.toFixed(1)} to ${high.toFixed(1)} Hz`);
      }
    }
  });

  test(`at ${rpm} rpm no order of the three repeats every revolution: no fixed melody`, () => {
    const lines = linesByCylinder(rpm);
    const counts = {};
    const revs = Math.min(...lines.map((l) => l.length));
    for (let r = 0; r < revs; r++) {
      const order = [0, 1, 2].sort((p, q) => lines[p][r] - lines[q][r]).join('');
      counts[order] = (counts[order] ?? 0) + 1;
    }
    const top = Math.max(...Object.values(counts));
    assert.ok(Object.keys(counts).length >= 5, `orders heard: ${JSON.stringify(counts)}`);
    assert.ok(top / revs <= 0.5, `one order holds ${((100 * top) / revs).toFixed(0)} % of revolutions, limit 50 (100 in rc.2)`);
  });
}

test('a fire rings less on lines: less modal height, and no modes in near-octaves', () => {
  for (const sound of FIRES) {
    const ts = voicesOf(bank, 90, IN_BAND)
      .filter((v) => v.sound === sound)
      .map((v) => tonalOf(strokeOf(bank, v)));
    const heights = ts.map((t) => t.height).sort((p, q) => p - q);
    const flats = ts.map((t) => t.flatness).sort((p, q) => p - q);
    const height = heights[Math.floor(heights.length / 2)];
    const flat = flats[Math.floor(flats.length / 2)];
    assert.ok(height <= 30, `${sound}: line ${height.toFixed(1)} dB over its band, limit 30 (30.3 to 35.3 before; rc.2 18.1 to 23.6)`);
    assert.ok(flat >= 0.04, `${sound}: flatness ${flat.toFixed(3)}, floor 0.04 (0.014 to 0.024 before; rc.2 0.128 to 0.248)`);
    const modes = doc.sounds[sound].layers.find((l) => l.src === 'modal').f;
    for (let i = 0; i < modes.length; i++) {
      for (let j = i + 1; j < modes.length; j++) {
        const ratio = modes[j] / modes[i];
        assert.ok(ratio < 1.92 || ratio > 2.08, `${sound}: ${modes[i]} and ${modes[j]} Hz are a near-octave`);
      }
    }
  }
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

for (const rpm of RPMS) {
  for (const power of [0.5, 0.7, 0.9]) {
    test(`a knock stays under the quietest fire at ${rpm} rpm, power ${power}`, () => {
      const params = { power, ...WORKING.diesel };
      const quietest = Math.min(...FIRES.map((s) => strokes(bank, s, rpm, params).peakDb));
      for (const sound of VALVES) {
        const m = strokes(bank, sound, rpm, params);
        assert.ok(m.peakDb < quietest, `${sound} ${m.peakDb.toFixed(1)} dB, the quietest fire ${quietest.toFixed(1)} dB`);
      }
    });
  }
}

test("the two knocks don't share a line", () => {
  const line = (sound) => doc.sounds[sound].layers.find((l) => l.src === 'modal').f[0];
  assert.ok(Math.abs(line('diesel_valve_in') / line('diesel_valve_ex') - 1) > 0.1, `${line('diesel_valve_ex')} and ${line('diesel_valve_in')} Hz`);
});

test('the Loader\'s valve is a dull knock too, not a tick', () => {
  const m = strokes(bank, 'steam_valve', 90, STEAM_BAND, 'steam');
  assert.ok(m.clickHz <= 1200, `first 10 ms centred at ${m.clickHz.toFixed(0)} Hz, limit 1200 (2136)`);
  assert.ok(m.bodyToClick >= -28, `body ${m.bodyToClick.toFixed(1)} dB against the click, floor -28 (-33.9)`);
  assert.ok(m.earShare <= -25, `2-8 kHz ${m.earShare.toFixed(1)} dB of its total, limit -25 (-20)`);
  assert.ok(m.lineHz <= 300, `heard at ${m.lineHz.toFixed(0)} Hz, limit 300 (727)`);
  assert.ok(m.ringMs >= 28, `falls 30 dB in ${m.ringMs} ms, floor 28 (24)`);
  assert.ok(m.centsSpan >= 30, `${m.centsSpan.toFixed(0)} cents between strokes`);
  assert.equal(doc.sounds.steam_valve.variants % 2, 1, 'two strokes a revolution: an even count of takes gives each its own');
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
