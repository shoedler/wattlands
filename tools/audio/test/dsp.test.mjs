import assert from 'node:assert/strict';
import { test } from 'node:test';
import { applyFx, applyRoom, bandFilter, bandShareDb, biquad, comb, crush, envelope, fft, fm, freqTrack, gainToDb, grains, modal, noise, oscillator, pluck, powerSpectrum, rbj, xorshift32 } from '../lib/dsp.mjs';
import { sineWave, toneHz } from './helpers.mjs';

const RATE = 22050;

function rms(x) {
  return Math.sqrt(x.reduce((a, v) => a + v * v, 0) / x.length);
}

test('xorshift32 is deterministic and a zero seed still runs', () => {
  const a = xorshift32(7);
  const b = xorshift32(7);
  for (let i = 0; i < 100; i++) assert.equal(a(), b());
  assert.notEqual(xorshift32(0)(), 0);
});

test('noise is seeded: same seed same samples, another seed others', () => {
  for (const color of ['white', 'pink', 'brown']) {
    assert.deepEqual(noise(color, 500, 3), noise(color, 500, 3), color);
    assert.notDeepEqual(noise(color, 500, 3), noise(color, 500, 4), color);
  }
  assert.throws(() => noise('purple', 10, 1), /unknown noise color/);
});

test('noise colours tilt the way their names say', () => {
  const low = (c) => bandShareDb(noise(c, RATE * 4, 5), RATE, 0, 500);
  assert.ok(low('white') < low('pink'));
  assert.ok(low('pink') < low('brown'));
});

test('freqTrack: a number, a glide, points', () => {
  assert.equal(freqTrack(440, 10, RATE)[9], 440);
  assert.equal(freqTrack(440, 10, RATE, { pitch: 2 })[0], 880);
  const lin = freqTrack([100, 200], 101, RATE);
  assert.ok(Math.abs(lin[50] - 150) < 1);
  const exp = freqTrack([100, 400], 101, RATE, { glide: 'exp' });
  assert.ok(Math.abs(exp[50] - 200) < 2, 'an octave a half');
  const pts = freqTrack([[0, 100], [1, 400]], RATE, RATE);
  assert.ok(Math.abs(pts[RATE / 2] - 200) < 1);
  assert.throws(() => freqTrack('x', 4, RATE), /bad frequency/);
});

test('every oscillator runs at its frequency and stays in range', () => {
  for (const wave of ['sine', 'tri', 'saw', 'square', 'pulse']) {
    const x = oscillator(wave, freqTrack(441, RATE, RATE), RATE);
    assert.ok(Math.abs(toneHz(x, RATE) - 441) < 3, wave);
    assert.ok(Math.max(...x.map(Math.abs)) < 1.35, wave);
  }
  assert.throws(() => oscillator('kazoo', freqTrack(1, 4, RATE), RATE), /unknown oscillator/);
});

test('polyBLEP takes the worst aliasing off a high saw', () => {
  const blep = oscillator('saw', freqTrack(3100, RATE, RATE), RATE);
  const naive = new Float64Array(RATE);
  for (let i = 0; i < RATE; i++) naive[i] = 2 * ((i * 3100) / RATE - Math.floor((i * 3100) / RATE)) - 1;
  // The harmonics of 3100 Hz are at multiples of it: anything under the fundamental is alias.
  assert.ok(bandShareDb(blep, RATE, 40, 2800) < bandShareDb(naive, RATE, 40, 2800) - 3);
});

test('pulse duty sets the mean', () => {
  const x = oscillator('pulse', freqTrack(100, RATE, RATE), RATE, { duty: 0.25 });
  const mean = x.reduce((a, v) => a + v, 0) / x.length;
  assert.ok(Math.abs(mean - -0.5) < 0.02);
});

test('modal partials ring for their t60', () => {
  const x = modal({ f: [1000], t60: [0.5], g: [1] }, RATE, RATE);
  const at = (t) => rms(x.subarray(Math.round(t * RATE), Math.round(t * RATE) + 220));
  const drop = gainToDb(at(0.5) / at(0));
  assert.ok(Math.abs(drop + 60) < 3, `dropped ${drop} dB`);
});

test('modal skips a partial over Nyquist and scales pitch', () => {
  const x = modal({ f: [20000], t60: [1], g: [1] }, 100, RATE);
  assert.equal(Math.max(...x.map(Math.abs)), 0);
  const y = modal({ f: [500], t60: [10] }, RATE, RATE, 2);
  assert.ok(Math.abs(toneHz(y, RATE) - 1000) < 3);
});

test('pluck sounds at its frequency and decays', () => {
  const x = pluck({ f: 220, decay: 1, bright: 0.8 }, RATE, RATE, 11);
  const seg = x.subarray(1000, 12000);
  let best = 0;
  let bestV = -Infinity;
  for (let lag = 40; lag < 300; lag++) {
    let s = 0;
    for (let i = 0; i + lag < seg.length; i++) s += seg[i] * seg[i + lag];
    if (s > bestV) {
      bestV = s;
      best = lag;
    }
  }
  assert.ok(Math.abs(RATE / best - 220) < 3, `${RATE / best} Hz`);
  assert.ok(rms(x.subarray(RATE - 2000)) < rms(x.subarray(0, 2000)) / 4);
  assert.deepEqual(pluck({ f: 220 }, 500, RATE, 2), pluck({ f: 220 }, 500, RATE, 2));
});

test('grains scatter at about their rate, seeded', () => {
  const spec = { rate_hz: 50, f: [1000, 2000], dur_s: [0.002, 0.002], g: [1, 1] };
  const x = grains(spec, RATE * 4, RATE, 9);
  assert.deepEqual(x, grains(spec, RATE * 4, RATE, 9));
  let bursts = 0;
  let quiet = 0;
  for (const v of x) {
    if (Math.abs(v) > 0.2 && quiet > 20) bursts++;
    quiet = Math.abs(v) > 0.2 ? 0 : quiet + 1;
  }
  assert.ok(bursts > 120 && bursts < 260, `${bursts} bursts`);
  const n = grains({ ...spec, kind: 'noise', sweep: 2 }, 2000, RATE, 3);
  assert.ok(Math.max(...n.map(Math.abs)) > 0);
});

test('fm: index 0 is a sine, an index adds sidebands that decay', () => {
  const track = freqTrack(1000, RATE, RATE);
  const plain = fm({ ratio: 2, index: 0 }, track, RATE);
  assert.ok(bandShareDb(plain, RATE, 900, 1100) > -0.5);
  const rich = fm({ ratio: 2, index: 3, index_decay: 0.1 }, track, RATE);
  assert.ok(bandShareDb(rich.subarray(0, 1024), RATE, 900, 1100) < -1);
  assert.ok(bandShareDb(rich.subarray(RATE - 4096), RATE, 900, 1100) > -0.5, 'the index has fallen');
});

test('envelope: attack, hold, exp decay to sustain, release', () => {
  const e = envelope({ a: 0.01, h: 0.01, d: 0.1, s: 0.5, r: 0.05 }, RATE, RATE);
  assert.ok(e[0] < 0.01);
  assert.ok(Math.abs(e[Math.round(0.015 * RATE)] - 1) < 1e-9);
  assert.ok(Math.abs(e[Math.round(0.5 * RATE)] - 0.5) < 1e-9);
  assert.ok(e[RATE - 1] < 0.001, 'release ends at sample n');
});

test('envelope: decay with no sustain reaches exactly 0; linear curve; no decay holds 1', () => {
  const e = envelope({ d: 0.1 }, RATE, RATE);
  assert.equal(e[Math.round(0.1 * RATE) + 1], 0);
  const lin = envelope({ d: 1, curve: 'lin' }, RATE, RATE);
  assert.ok(Math.abs(lin[RATE / 2] - 0.5) < 1e-3);
  assert.equal(envelope({ a: 0 }, 10, RATE)[5], 1);
});

test('envelope points are linear and hold at the ends', () => {
  const e = envelope({ points: [[0, 0], [1, 1], [2, 0.5]] }, RATE * 3, RATE);
  assert.ok(Math.abs(e[RATE / 2] - 0.5) < 1e-3);
  assert.ok(Math.abs(e[Math.round(1.5 * RATE)] - 0.75) < 1e-3);
  assert.equal(e[RATE * 3 - 1], 0.5);
});

function gainAt(hz, c) {
  const out = biquad(sineWave(hz, 1, RATE), c);
  return gainToDb(rms(out.subarray(4000)) / Math.SQRT1_2);
}

test('RBJ filters: -3 dB at the cutoff, shape as named', () => {
  assert.ok(Math.abs(gainAt(1000, rbj('lp', 1000, 0.7071, RATE)) + 3) < 0.3);
  assert.ok(Math.abs(gainAt(1000, rbj('hp', 1000, 0.7071, RATE)) + 3) < 0.3);
  assert.ok(gainAt(4000, rbj('lp', 1000, 0.7071, RATE)) < -20);
  assert.ok(gainAt(200, rbj('hp', 1000, 0.7071, RATE)) < -20);
  assert.ok(Math.abs(gainAt(1000, rbj('bp', 1000, 2, RATE))) < 0.3);
  assert.ok(gainAt(1000, rbj('notch', 1000, 2, RATE)) < -30);
  assert.ok(Math.abs(gainAt(1000, rbj('peak', 1000, 1, RATE, 6)) - 6) < 0.3);
  assert.ok(Math.abs(gainAt(9000, rbj('highshelf', 3000, 0.7071, RATE, -6)) + 6) < 0.6);
  assert.throws(() => rbj('xx', 1000, 1, RATE), /unknown filter/);
});

test('the family band filter is 24 dB/oct each side and white noise meets A9', () => {
  const x = bandFilter(noise('white', RATE * 3, 21), 40, 9000, RATE);
  assert.ok(bandShareDb(x, RATE, 9800, 11026) <= -32);
  const low = bandFilter(sineWave(20, 2, RATE), 40, 9000, RATE);
  assert.ok(gainToDb(rms(low.subarray(RATE)) / Math.SQRT1_2) < -20, '20 Hz, an octave under the corner');
  const mid = bandFilter(sineWave(1000, 1, RATE), 40, 9000, RATE);
  assert.ok(Math.abs(gainToDb(rms(mid.subarray(4000)) / Math.SQRT1_2)) < 0.2);
});

test('comb repeats at its delay with its feedback', () => {
  const x = new Float64Array(2000);
  x[0] = 1;
  const y = comb(x, 10, 0.5, RATE);
  const d = Math.round(0.01 * RATE);
  assert.equal(y[d], 0.5);
  assert.equal(y[2 * d], 0.25);
});

test('crush quantizes and holds', () => {
  const y = crush(Float64Array.from([0.13, 0.14, -0.61, 0.9]), 2, 2);
  assert.deepEqual([...y], [0, 0, -0.5, -0.5]);
});

test('applyFx: every effect by name, a sweep, and refusals', () => {
  const x = noise('white', 4000, 2);
  for (const e of [{ lp: { f: 800 } }, { hp: { f: 800 } }, { bp: { f: 800, q: 2 } }, { notch: { f: 800 } }, { peak: { f: 800, db: 3 } }, { drive: 2 }, { drive: { gain: 2 } }, { crush: { bits: 6 } }, { comb: { ms: 5, fb: 0.3 } }, { trem: { hz: 5, depth: 1 } }, { gain_env: { d: 0.1 } }]) {
    const y = applyFx(x, e, RATE);
    assert.equal(y.length, x.length);
    assert.notDeepEqual(y, x, JSON.stringify(e));
  }
  const swept = applyFx(noise('white', RATE, 2), { lp: { f: [200, 8000], glide: 'exp' } }, RATE);
  assert.ok(rms(swept.subarray(0, 2000)) < rms(swept.subarray(RATE - 2000)));
  assert.throws(() => applyFx(x, { wah: 1 }, RATE), /unknown fx/);
  assert.throws(() => applyFx(x, { lp: { f: 1 }, hp: { f: 1 } }, RATE), /one key/);
});

test('rooms: none is the same array; iron and wood add tails; open tilts', () => {
  const x = new Float64Array(4000);
  x[0] = 1;
  assert.equal(applyRoom(x, 'none', RATE), x);
  const iron = applyRoom(x, 'iron', RATE);
  assert.ok(Math.abs(iron[Math.round(0.018 * RATE)]) > 0);
  assert.ok(Math.abs(iron[Math.round(0.031 * RATE)]) > 0);
  const wood = applyRoom(x, 'wood', RATE);
  assert.ok(Math.abs(wood[Math.round(0.011 * RATE)]) > 0);
  const bright = sineWave(9000, 1, RATE);
  assert.ok(rms(applyRoom(bright, 'open', RATE).subarray(1000)) < rms(bright.subarray(1000)));
  assert.throws(() => applyRoom(x, 'cave', RATE), /unknown room/);
});

test('fft finds a tone; powerSpectrum averages it', () => {
  const n = 1024;
  const re = Float64Array.from({ length: n }, (_, i) => Math.cos((2 * Math.PI * 32 * i) / n));
  const im = new Float64Array(n);
  fft(re, im);
  assert.ok(Math.abs(re[32] - n / 2) < 1e-6);
  assert.ok(Math.abs(re[33]) < 1e-6);
  const p = powerSpectrum(sineWave(RATE / 8, 1, RATE), 1024);
  assert.equal(p.indexOf(Math.max(...p)), 128);
});
