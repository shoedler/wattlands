// What Workout's bank promises beyond the shared scorecard: strokes from the rider sheet's own crank,
// an hour of ticks that stays a texture, and a crank you can still hear in the whole mix.

import assert from 'node:assert/strict';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { CRANK_FRAMES, crankTheta, pedalAt } from '../../../../src/games/workout/art/rig.mjs';
import { loadBank } from '../../../../tools/audio/lib/bank.mjs';
import { biquad, powerSpectrum, rbj } from '../../../../tools/audio/lib/dsp.mjs';
import { BankAudio, MIX_RATE, mixdown, simulate } from '../../../../tools/audio/lib/offline_mix.mjs';
import { previewScenario } from '../../../../tools/audio/lib/score.mjs';
import { curveEval } from '../../../../tools/audio/lib/pattern.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DIR = path.resolve(HERE, '..', '..', '..', '..', 'assets', 'workout', 'audio');
const doc = loadBank(path.join(DIR, 'audio.json'));
const bank = new BankAudio(doc, DIR);

function bikeEvent(sound) {
  const e = doc.machines.bike.events.find((x) => x.sound === sound);
  assert.ok(e, sound);
  return e;
}

test('the press sounds where the rider sheet has a pedal furthest forward', () => {
  const xs = Array.from({ length: CRANK_FRAMES }, (_, k) => pedalAt(k)[0]);
  const front = Math.max(...xs);
  const back = Math.min(...xs);
  const [near, far] = bikeEvent('pedal_press').at;
  assert.equal(xs[Math.floor(near * CRANK_FRAMES)], front, 'near pedal forward');
  assert.equal(xs[Math.floor(far * CRANK_FRAMES)], back, 'near pedal back, so the far one forward');
  assert.equal(Math.cos(crankTheta(near * CRANK_FRAMES)), 1);
});

test('the chain ticks through the dead spot, once a revolution: the near pedal on top', () => {
  const [at, ...rest] = bikeEvent('chain_tick').at;
  assert.deepEqual(rest, []);
  assert.equal(at, 0);
  assert.ok(Math.abs(Math.sin(crankTheta(at * CRANK_FRAMES)) + 1) < 1e-9);
});

test('others carry the tick alone', () => {
  for (const e of doc.machines.bike.events) {
    if (e.sound !== 'chain_tick') assert.equal(e.lead_only, true, e.sound);
  }
  assert.equal(doc.machines.bike.events.find((e) => e.sound === 'chain_tick').lead_only ?? false, false);
  const others = doc.machines.bike.loops.filter((l) => l.other === true).map((l) => l.sound);
  assert.deepEqual(others, ['chain_hum'], 'and one quiet whirr');
});

function energy(id, lo, hi) {
  const size = 4096;
  let total = 0;
  for (let v = 0; v < bank.variants(id); v++) {
    const f = bank.file(id, v);
    const x = f.data[0].subarray(f.preroll);
    for (let at = 0; at < x.length; at += size) {
      const p = powerSpectrum(x.subarray(at, Math.min(x.length, at + size)), size);
      for (let k = 0; k < p.length; k++) {
        const hz = (k * f.rate) / size;
        if (hz >= lo && hz < hi) total += p[k];
      }
    }
  }
  return 10 * Math.log10(total / bank.variants(id) + 1e-30);
}

test('fatigue: nothing locked above 2 kHz within 16 dB of the main stroke, at its loudest', () => {
  const press = bikeEvent('pedal_press');
  const hard = { power: 1.5, crowd: 1, speed: 15, coast: 1, rpm: 110 };
  const levelOf = (e) => (e.db ?? 0) + (e.db_by ?? []).reduce((a, c) => a + curveEval(c, hard), 0);
  const main = energy('pedal_press', 0, 1e6) + levelOf(press);
  for (const machine of ['bike', 'breath', 'wheel']) {
    for (const e of doc.machines[machine].events) {
      const above = energy(e.sound, 2000, 1e6) + levelOf(e);
      assert.ok(above <= main - 16, `${e.sound}: ${(above - main).toFixed(1)} dB`);
    }
  }
});

function foldedRange(x, t0, t1, revs0, rpm, bins = 24) {
  const sum = new Float64Array(bins);
  const n = new Float64Array(bins);
  for (let i = Math.round(t0 * MIX_RATE); i < Math.round(t1 * MIX_RATE); i++) {
    const r = revs0 + ((i / MIX_RATE - t0) * rpm) / 60;
    const k = Math.floor((r - Math.floor(r)) * bins);
    sum[k] += x[i] * x[i];
    n[k]++;
  }
  const db = [...sum].map((v, k) => 10 * Math.log10(v / n[k] + 1e-20));
  return { db, range: Math.max(...db) - Math.min(...db) };
}

test('the crank can be heard in the whole mix, on small speakers too, at every cadence', () => {
  const sim = simulate(bank, previewScenario(doc));
  const mix = mixdown(bank, sim);
  const whole = mix.master[0];
  const mids = biquad(whole, rbj('bp', 900, 0.7, MIX_RATE));
  let t = 0;
  let revs = 0;
  for (const seg of doc.preview.segments.filter((s) => s.rpm > 0)) {
    // Past the bell, the crowd's arrival and the loops' opening.
    const t0 = t + 5;
    const t1 = t + seg.s - 1;
    const revs0 = revs + (5 * seg.rpm) / 60;
    const all = foldedRange(whole, t0, t1, revs0, seg.rpm);
    assert.ok(all.range >= 6, `${seg.rpm} rpm: ${all.range.toFixed(1)} dB over one revolution`);
    const press = Math.floor(0.25 * 24);
    assert.ok(all.db[press] >= Math.max(...all.db) - 3, `${seg.rpm} rpm: the press leads`);
    const mid = foldedRange(mids, t0, t1, revs0, seg.rpm);
    assert.ok(mid.range >= 3, `${seg.rpm} rpm: ${mid.range.toFixed(1)} dB in the mids`);
    t += seg.s;
    revs += (seg.s * seg.rpm) / 60;
  }
});
