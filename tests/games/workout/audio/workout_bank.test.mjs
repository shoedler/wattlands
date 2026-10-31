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
import { integratedLufs } from '../../../../tools/audio/lib/lufs.mjs';
import { previewScenario } from '../../../../tools/audio/lib/score.mjs';
import { curveEval, curveSumDb } from '../../../../tools/audio/lib/pattern.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DIR = path.resolve(HERE, '..', '..', '..', '..', 'assets', 'workout', 'audio');
const doc = loadBank(path.join(DIR, 'audio.json'));
const bank = new BankAudio(doc, DIR);
const SHARED_DIR = path.resolve(DIR, '..', '..', '_shared', 'audio');
const shared = new BankAudio(loadBank(path.join(SHARED_DIR, 'audio.json')), SHARED_DIR);

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
    // The short steps of the gust sweep are too short to fold.
    if (seg.s < 10) {
      t += seg.s;
      revs += (seg.s * seg.rpm) / 60;
      continue;
    }
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

// --- the group -------------------------------------------------------------------------

function groupLu(scales, power = 0.65) {
  const base = { segments: [{ rpm: 90, s: 30, params: { power } }], seed: 1 };
  const machinesOf = (sim) => integratedLufs(mixdown(bank, sim).stems.Machines, MIX_RATE);
  const lead = machinesOf(simulate(bank, { ...base, machines: [{ id: 'lead', machine: 'bike', lead: true }] }));
  const silent = { id: 'lead', machine: 'bike', lead: true, strokes: false, loops: false };
  const others = scales.map((rpm_scale, i) => ({ id: `r${i}`, machine: 'bike', lead: false, rpm_scale, params: { power } }));
  return machinesOf(simulate(bank, { ...base, machines: [silent, ...others] })) - lead;
}

test('your own bike leads: one other rider and all seven stay at least 8 LU under it', () => {
  const one = groupLu([0.97]);
  assert.ok(one <= -8 && one >= -12, `one other: ${one.toFixed(2)} LU`);
  // The real bots' cluster (90 rpm, noise sd 0.6) and the scorecard's spread of 88-112 rpm.
  const bots = groupLu([0.993, 1.004, 0.998, 1.006, 0.995, 1.002, 0.999]);
  assert.ok(bots <= -8, `seven bots: ${bots.toFixed(2)} LU`);
  const spread = groupLu([88, 92, 96, 100, 104, 108, 112].map((rpm) => rpm / 90));
  assert.ok(spread <= -8, `seven at 88-112 rpm: ${spread.toFixed(2)} LU`);
});

// --- what the critic could hear and the scorecard could not ----------------------------

test('no three-beat loop: the strokes come round only after 105 revolutions', () => {
  const tick = bikeEvent('chain_tick');
  const press = bikeEvent('pedal_press');
  const gcd = (a, b) => (b === 0 ? a : gcd(b, a % b));
  const lcm = (a, b) => (a * b) / gcd(a, b);
  const tickRevs = lcm(doc.sounds.chain_tick.variants, tick.pitch_table.length);
  const pressStrokes = lcm(doc.sounds.pedal_press.variants, press.pitch_table.length);
  const pressRevs = lcm(pressStrokes, press.at.length) / press.at.length;
  const cycle = lcm(tickRevs, pressRevs);
  assert.equal(cycle, 105, `tick ${tickRevs}, press ${pressRevs}`);
  const levels = doc.sounds.chain_tick.per_variant.map((v) => v.norm.peak);
  assert.ok(Math.max(...levels) - Math.min(...levels) <= 1.5, 'no accent the legs do not have');
  const sim = simulate(bank, { segments: [{ rpm: 90, s: 30, params: { power: 0.65 } }], machines: [{ id: 'lead', machine: 'bike', lead: true, loops: false }] });
  const x = mixdown(bank, sim, { tail: 0 }).stems.Machines[0];
  const corrAt = (revs) => {
    const lag = Math.round((revs * 60 * MIX_RATE) / 90);
    let ab = 0;
    let aa = 0;
    let bb = 0;
    for (let i = MIX_RATE; i + lag < x.length; i++) {
      ab += x[i] * x[i + lag];
      aa += x[i] * x[i];
      bb += x[i + lag] * x[i + lag];
    }
    return ab / Math.sqrt(aa * bb);
  };
  assert.ok(corrAt(12) < 0.95, `12 revolutions: ${corrAt(12).toFixed(3)}, was 0.999`);
});

test('the birds have no hole between dawn and day', () => {
  const layers = doc.beds.dawn_road.layers.filter((l) => l.sound.startsWith('birds'));
  for (let day = 0; day <= 1.0001; day += 0.01) {
    const sum = layers.reduce((a, l) => a + Math.pow(10, (l.db + curveSumDb(l.db_by, { day })) / 10), 0);
    const db = 10 * Math.log10(sum);
    assert.ok(db >= -24.5, `day ${day.toFixed(2)}: ${db.toFixed(1)} dB`);
  }
});

function rmsRange(x, t0, t1, step) {
  const out = [];
  for (let t = t0; t + step <= t1; t += step) {
    let e = 0;
    const a = Math.round(t * MIX_RATE);
    const b = Math.round((t + step) * MIX_RATE);
    for (let i = a; i < b; i++) e += x[i] * x[i];
    out.push(10 * Math.log10(e / (b - a) + 1e-30));
  }
  return Math.max(...out) - Math.min(...out);
}

test('a steady block moves: the preview sweeps gust and road at one power and one speed', () => {
  let t = 0;
  let from = -1;
  let to = -1;
  for (const seg of doc.preview.segments) {
    if (seg.params.gust !== undefined) {
      if (from < 0) from = t;
      to = t + seg.s;
    }
    t += seg.s;
  }
  assert.ok(to - from >= 30, 'half a minute of it');
  const mix = mixdown(bank, simulate(bank, previewScenario(doc)));
  const road = biquad(mix.stems.Sfx[0], rbj('bp', 3200, 0.8, MIX_RATE));
  const range = rmsRange(road, from + 0.5, to, 3);
  assert.ok(range >= 3, `the road's 2-5 kHz moves ${range.toFixed(2)} dB over 3 s steps`);
});

test('everything that rolls on a coast keeps sounding after the legs stop', () => {
  const stops = doc.preview.segments.findIndex((s) => s.rpm <= 0);
  const stop = doc.preview.segments[stops];
  assert.ok(stop.params.speed > 2, 'the preview stops at speed');
  assert.equal(stop.params.coast, 1);
  const stopAt = doc.preview.segments.slice(0, stops).reduce((a, s) => a + s.s, 0);
  const ends = doc.preview.loops.filter((l) => l.id === 'tyre_hum' || l.id === 'wind_rush').map((l) => l.t1);
  assert.ok(Math.max(...ends) >= stopAt + stop.s, 'tyres and wind run through the stop');
  const sim = simulate(bank, previewScenario(doc));
  const mix = mixdown(bank, sim);
  const level = (st) => rmsLevel(st[0], stopAt + 1, stopAt + stop.s - 1);
  assert.ok(level(mix.stems.Machines) < -60, `Machines ${level(mix.stems.Machines).toFixed(1)}`);
  assert.ok(level(mix.stems.Sfx) > -40, `the road ${level(mix.stems.Sfx).toFixed(1)}`);
  assert.ok(sim.events.some((e) => e.sound === 'freewheel_tick' && e.t > stopAt), 'the ratchet');
});

function rmsLevel(x, t0, t1) {
  let e = 0;
  const a = Math.round(t0 * MIX_RATE);
  const b = Math.round(t1 * MIX_RATE);
  for (let i = a; i < b; i++) e += x[i] * x[i];
  return 10 * Math.log10(e / (b - a) + 1e-30);
}

// --- the stack at a phase change --------------------------------------------------------

// A phase change in the game: the chime on Sfx, HudLayer's `phase` and `toast` on UI at its -4 dB, at
// once, and the bell a beat later. The preview block cannot play a _shared sound, so it is added here.
function stack(cues, ui) {
  const T = 8;
  const speed = 8.5;
  const sim = simulate(bank, {
    segments: [{ rpm: 90, s: 12, params: { power: 0.65, speed, day: 0.3, coast: 0, crowd: 0 } }],
    machines: [{ id: 'lead', machine: 'bike', lead: true }],
    bed: 'dawn_road',
    bed_params: { gust: 0.5, tractor: 0 },
    seed: 12,
    shared,
    loops: [{ id: 'tyre_hum', t0: 0, t1: 12, params: { speed, road: 0.5 } }, { id: 'wind_rush', t0: 0, t1: 12, params: { speed, gust: 0.5 } }],
    cues: cues.map((cue) => ({ t: T, cue, vars: {} })),
  });
  for (const name of ui) {
    const f = shared.file(name, 0);
    sim.voices.push({ shared: true, sound: name, variant: 0, t: T, db: -4, pitch: 1, bus: 'UI', priority: 6, lead: true, end: T + f.frames / f.rate });
  }
  return { T, mix: mixdown(bank, sim, { shared }) };
}

function bandDb(x, t0, t1, lo, hi) {
  const size = 8192;
  const p = powerSpectrum(x.subarray(Math.round(t0 * MIX_RATE), Math.round(t1 * MIX_RATE)), size);
  let e = 0;
  for (let k = 0; k < p.length; k++) {
    const hz = (k * MIX_RATE) / size;
    if (hz >= lo && hz < hi) e += p[k];
  }
  return 10 * Math.log10(e + 1e-30);
}

test('a phase change reads through its real stack: chime, phase, toast, then the bell', () => {
  const quiet = stack([], []);
  const all = stack(['interval_end', 'interval_start'], ['phase', 'toast']);
  const T = all.T;
  const before = bandDb(quiet.mix.master[0], T - 0.5, T, 1000, 4000);
  const chime = bandDb(all.mix.master[0], T, T + 0.25, 1000, 4000) - before;
  const bell = bandDb(all.mix.master[0], T + 0.42, T + 0.67, 1000, 4000) - before;
  assert.ok(chime >= 6, `the stack's first 250 ms: +${chime.toFixed(1)} dB`);
  assert.ok(bell >= 6, `the bell: +${bell.toFixed(1)} dB`);
  // The game's chime sits on top of the platform's two: in its own band they do not cover it.
  const own = bandDb(stack(['interval_end'], []).mix.stems.Sfx[0], T, T + 0.25, 1000, 1500);
  const ui = bandDb(stack([], ['phase', 'toast']).mix.stems.UI[0], T, T + 0.25, 1000, 1500);
  assert.ok(own >= ui + 6, `chime ${own.toFixed(1)}, phase and toast ${ui.toFixed(1)}`);
  let clipped = 0;
  for (const v of all.mix.sum[0]) if (Math.abs(v) > 1) clipped++;
  assert.equal(clipped, 0, 'and nothing clips');
});
