import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bandShareDb } from '../lib/dsp.mjs';
import { integratedLufs } from '../lib/lufs.mjs';
import { PREROLL_S, hashId, quantize, renderSound, resolveSound } from '../lib/recipe.mjs';
import { deinterleave } from '../lib/wav.mjs';

const TONE = { dur: 0.2, seed: 5, layers: [{ src: 'tri', f: 440 }] };
const NOISE = { dur: 0.3, seed: 5, layers: [{ src: 'noise', color: 'white' }] };

test('same recipe, same samples; variants and seeds differ', () => {
  assert.deepEqual(renderSound('a', NOISE).samples, renderSound('a', NOISE).samples);
  const v = { ...NOISE, variants: 2 };
  assert.notDeepEqual(renderSound('a', v, 0).samples, renderSound('a', v, 1).samples);
  assert.notDeepEqual(renderSound('a', NOISE).samples, renderSound('a', { ...NOISE, seed: 6 }).samples);
});

test('the default seed comes from the id, so reordering a bank changes nothing', () => {
  const s = { dur: 0.1, layers: [{ src: 'noise' }] };
  assert.equal(resolveSound('abc', s).seed, hashId('abc'));
  assert.notDeepEqual(renderSound('abc', s).samples, renderSound('abd', s).samples);
});

test('defaults: compress, norm, band, crush', () => {
  const locked = resolveSound('a', { ...TONE, locked: true });
  assert.equal(locked.compress, 'pcm');
  assert.deepEqual(locked.norm, { peak: -6 });
  const loopShort = resolveSound('a', { ...TONE, loop: true, dur: 2 });
  assert.equal(loopShort.compress, 'pcm');
  assert.deepEqual(loopShort.norm, { lufs: -20 });
  assert.equal(resolveSound('a', { ...TONE, loop: true, dur: 3 }).compress, 'qoa');
  const shot = resolveSound('a', TONE);
  assert.equal(shot.compress, 'qoa');
  assert.deepEqual(shot.norm, { peak: -3 });
  assert.deepEqual(shot.band, [40, 9000]);
  assert.equal(shot.crush, 12);
  assert.deepEqual(resolveSound('a', { ...TONE, rate: 11025 }).band, [40, 5000]);
  assert.equal(resolveSound('a', TONE, 0, { game: '_shared' }).compress, 'pcm', 'UI is PCM');
});

test('a locked sound starts with exactly 80 ms of digital silence, then its attack', () => {
  const r = renderSound('a', { ...NOISE, locked: true });
  const pre = Math.round(PREROLL_S * 22050);
  assert.equal(r.preroll, pre);
  assert.equal(r.frames, pre + Math.round(0.3 * 22050));
  for (let i = 0; i < pre; i++) assert.equal(r.samples[i], 0);
  let attack = 0;
  for (let i = pre; i < pre + 20; i++) attack = Math.max(attack, Math.abs(r.samples[i]));
  assert.ok(attack > 2000, `attack within 1 ms of the pre-roll's end (${attack})`);
});

test('family depth: 12 significant bits, low nibble zero, in every format', () => {
  for (const s of [NOISE, { ...NOISE, loop: true }, { ...NOISE, ch: 2 }, { ...TONE, locked: true }]) {
    for (const v of renderSound('a', s).samples) assert.equal(v & 15, 0);
  }
  assert.equal(quantize(0.5, 12), 16384);
  assert.equal(quantize(1, 12), 32768 - 16);
  assert.equal(quantize(-1, 12), -(32768 - 16));
  assert.equal(quantize(0.5001, 8) % 256, 0);
});

test('peak norm hits its peak', () => {
  const r = renderSound('a', { ...NOISE, norm: { peak: -6 } });
  const peak = Math.max(...r.samples.map(Math.abs)) / 32768;
  assert.ok(Math.abs(20 * Math.log10(peak) + 6) < 0.05);
  assert.ok(Math.abs(r.peak_db + 6) < 0.01);
});

test('lufs norm hits its level; a loop too short to meter is tiled', () => {
  const r = renderSound('a', { dur: 3, seed: 2, loop: true, norm: { lufs: -20 }, layers: [{ src: 'noise', color: 'pink' }] });
  const [x] = deinterleave(r.samples, 1);
  assert.ok(Math.abs(integratedLufs([x], 22050) + 20) < 0.3);
  const short = renderSound('a', { dur: 0.25, seed: 2, loop: true, norm: { lufs: -20 }, layers: [{ src: 'noise', color: 'pink' }] });
  assert.ok(Math.abs(short.lufs + 20) < 0.3, `${short.lufs}`);
});

test('lufs norm never clips a sparse loop', () => {
  const r = renderSound('a', { dur: 2, seed: 2, loop: true, norm: { lufs: -6 }, layers: [{ src: 'grains', rate_hz: 2, f: [800, 900], dur_s: [0.01, 0.02], g: [1, 1] }] });
  assert.ok(Math.max(...r.samples.map(Math.abs)) < 32768);
});

test('a loop is seamless: guard frame, exact period, a quiet seam', () => {
  for (const seed of [1, 2, 3, 4, 5, 6, 7, 8]) {
    const r = renderSound('a', { dur: 1, seed, loop: true, layers: [{ src: 'noise', color: 'white' }] });
    assert.equal(r.loopFrames, 22050);
    assert.equal(r.frames, 22051);
    assert.equal(r.samples[r.loopFrames], r.samples[0], 'the frame after the loop is frame 0');
    const steps = [];
    for (let i = 1; i < r.loopFrames; i++) steps.push(Math.abs(r.samples[i] - r.samples[i - 1]));
    steps.sort((a, b) => a - b);
    const median = steps[steps.length >> 1];
    assert.ok(Math.abs(r.samples[r.loopFrames - 1] - r.samples[0]) <= 3 * median, `seed ${seed}`);
  }
});

test('a loop keeps its level across the seam: the crossfade neither drops nor bumps noise', () => {
  const r = renderSound('a', { dur: 2, seed: 9, loop: true, xfade_s: 0.5, layers: [{ src: 'noise', color: 'pink' }] });
  const [x] = deinterleave(r.samples, 1);
  const block = 4410;
  const rms = (at) => {
    let s = 0;
    for (let i = 0; i < block; i++) {
      const v = x[(at + i) % r.loopFrames];
      s += v * v;
    }
    return 10 * Math.log10(s / block);
  };
  const levels = [];
  for (let at = 0; at < r.loopFrames; at += block) levels.push(rms(at));
  const spread = Math.max(...levels) - Math.min(...levels);
  assert.ok(spread < 3, `blocks spread ${spread} dB`);
});

test('a tone in phase across the seam keeps its level too: the crossfade adapts', () => {
  const r = renderSound('a', { dur: 1, seed: 9, loop: true, xfade_s: 0.25, layers: [{ src: 'sine', f: 441 }] });
  const [x] = deinterleave(r.samples, 1);
  const block = 500;
  let lo = Infinity;
  let hi = -Infinity;
  for (let at = 0; at + block <= r.loopFrames; at += block) {
    let s = 0;
    for (let i = 0; i < block; i++) s += x[at + i] * x[at + i];
    lo = Math.min(lo, s);
    hi = Math.max(hi, s);
  }
  assert.ok(10 * Math.log10(hi / lo) < 0.5, `${10 * Math.log10(hi / lo)} dB`);
});

test('a one-shot ends at zero', () => {
  const r = renderSound('a', { dur: 0.2, seed: 1, layers: [{ src: 'square', f: 300 }] });
  assert.equal(r.samples[r.frames - 1], 0);
  assert.equal(r.loopFrames, 0);
});

test('stereo: a wide bed has two different sides, a panned spot leans', () => {
  const wide = renderSound('a', { dur: 0.5, seed: 3, ch: 2, layers: [{ src: 'noise' }] });
  const [l, r] = deinterleave(wide.samples, 2);
  assert.notDeepEqual(l, r);
  const rms = (x) => Math.sqrt(x.reduce((a, v) => a + v * v, 0) / x.length);
  const panned = deinterleave(renderSound('a', { dur: 0.3, seed: 3, ch: 2, pan: -0.8, layers: [{ src: 'tri', f: 500 }] }).samples, 2);
  assert.ok(rms(panned[0]) > 4 * rms(panned[1]));
  const mid = deinterleave(renderSound('a', { dur: 0.3, seed: 3, ch: 2, pan: 0, layers: [{ src: 'tri', f: 500 }] }).samples, 2);
  assert.deepEqual(mid[0], mid[1]);
});

test('per_variant overrides: pitch moves a variant, pan moves another', () => {
  const s = { dur: 0.3, seed: 1, ch: 2, variants: 2, layers: [{ src: 'tri', f: 500 }], per_variant: [{ pan: -1 }, { pan: 1 }] };
  const a = deinterleave(renderSound('a', s, 0).samples, 2);
  const b = deinterleave(renderSound('a', s, 1).samples, 2);
  assert.ok(Math.max(...a[1].map(Math.abs)) < 0.01);
  assert.ok(Math.max(...b[0].map(Math.abs)) < 0.01);
  const p = { dur: 0.3, seed: 1, variants: 2, layers: [{ src: 'sine', f: 500 }], per_variant: [{ pitch: 1 }, { pitch: 2 }] };
  const zc = (x) => x.reduce((n, v, i) => n + (i > 0 && x[i - 1] < 0 && v >= 0 ? 1 : 0), 0);
  const low = zc(deinterleave(renderSound('a', p, 0).samples, 1)[0]);
  const high = zc(deinterleave(renderSound('a', p, 1).samples, 1)[0]);
  assert.ok(Math.abs(high / low - 2) < 0.05);
});

test('layers: at and dur place a note, gain scales it, fx and env apply', () => {
  const r = renderSound('a', { dur: 0.4, seed: 1, norm: { peak: -3 }, layers: [{ src: 'sine', f: 500, at: 0.2, dur: 0.1, env: { a: 0.002, r: 0.01 } }] });
  const [x] = deinterleave(r.samples, 1);
  const rms = (a, b) => Math.sqrt(x.subarray(a, b).reduce((s, v) => s + v * v, 0) / (b - a));
  assert.ok(rms(0, Math.round(0.19 * 22050)) < 1e-3);
  assert.ok(rms(Math.round(0.22 * 22050), Math.round(0.28 * 22050)) > 0.1);
  assert.ok(rms(Math.round(0.33 * 22050), Math.round(0.39 * 22050)) < 1e-3);
});

test('every source renders; every source has energy in the family band', () => {
  const sources = [
    { src: 'sine', f: 300 },
    { src: 'tri', f: [300, 600], glide: 'exp' },
    { src: 'saw', f: 300 },
    { src: 'square', f: 300 },
    { src: 'pulse', f: 300, duty: 0.2 },
    { src: 'noise', color: 'pink' },
    { src: 'modal', f: [300, 700], t60: [0.3, 0.2], g: [1, 0.5] },
    { src: 'pluck', f: 200, decay: 0.8, bright: 0.6 },
    { src: 'chirp', points: [[0, 300], [0.2, 800]], vibrato: { hz: 6, cents: 30 } },
    { src: 'grains', rate_hz: 100, f: [800, 3000], dur_s: [0.002, 0.01], g: [0.5, 1] },
    { src: 'fm', f: 300, ratio: 2, index: 2, index_decay: 0.1 },
  ];
  for (const layer of sources) {
    const r = renderSound('a', { dur: 0.3, seed: 2, layers: [layer] });
    assert.ok(Math.max(...r.samples.map(Math.abs)) > 1000, layer.src);
    assert.ok(bandShareDb(deinterleave(r.samples, 1)[0], 22050, 9800, 11026) <= -32, layer.src);
  }
  assert.throws(() => renderSound('a', { dur: 0.1, layers: [{ src: 'kazoo' }] }), /unknown layer src/);
});

test('rooms and bands apply; a silent or lengthless recipe is an error', () => {
  const dry = renderSound('a', { dur: 0.2, seed: 1, layers: [{ src: 'noise', env: { d: 0.01 } }] });
  const wet = renderSound('a', { dur: 0.2, seed: 1, room: 'iron', layers: [{ src: 'noise', env: { d: 0.01 } }] });
  assert.notDeepEqual(dry.samples, wet.samples);
  const narrow = renderSound('a', { dur: 0.3, seed: 1, band: [1000, 2000], layers: [{ src: 'noise' }] });
  assert.ok(bandShareDb(deinterleave(narrow.samples, 1)[0], 22050, 40, 400) < -20);
  assert.throws(() => renderSound('a', { dur: 0.1, layers: [] }), /renders silent/);
  assert.throws(() => renderSound('a', { layers: [{ src: 'noise' }] }), /dur must be/);
  assert.throws(() => renderSound('a', { dur: 0.1, norm: {}, layers: [{ src: 'noise' }] }), /norm needs/);
});
