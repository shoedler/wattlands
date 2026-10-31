// What Workout's bank promises beyond the shared scorecard: strokes from the rider sheet's own crank,
// an hour of ticks that stays a texture, and a crank you can still hear in the whole mix.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { CRANK_FRAMES, crankTheta, pedalAt } from '../../../../src/games/workout/art/rig.mjs';
import { loadBank } from '../../../../tools/audio/lib/bank.mjs';
import { biquad, fft, powerSpectrum, rbj } from '../../../../tools/audio/lib/dsp.mjs';
import { BankAudio, FRAME_DT, MIX_RATE, mixdown, simulate } from '../../../../tools/audio/lib/offline_mix.mjs';
import { integratedLufs, loudnessRange } from '../../../../tools/audio/lib/lufs.mjs';
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

// The press's two legs, the strong one first.
const pressLegs = () => doc.machines.bike.events.filter((e) => e.sound === 'pedal_press');

test('the press sounds where the rider sheet has a pedal furthest forward', () => {
  const xs = Array.from({ length: CRANK_FRAMES }, (_, k) => pedalAt(k)[0]);
  const front = Math.max(...xs);
  const back = Math.min(...xs);
  const [near, far] = pressLegs().flatMap((e) => e.at);
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

test('others carry a tick of their own and nothing else: no loop, so nothing to lock in phase', () => {
  for (const e of doc.machines.bike.events) {
    if (e.sound !== 'chain_tick') assert.equal(e.lead_only, true, e.sound);
  }
  assert.deepEqual(doc.machines.bike.loops.filter((l) => l.other === true), [], 'no bike loop sounds for another rider');
  const peer = doc.machines.peer_bike;
  assert.deepEqual(peer.events.map((e) => e.sound), ['peer_tick']);
  assert.deepEqual(peer.events[0].at, bikeEvent('chain_tick').at, 'on the same crank fraction as a tick of your own');
  assert.equal(peer.events[0].lead_only ?? false, false);
  assert.deepEqual(peer.loops ?? [], []);
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

test('fatigue: nothing locked above 2 kHz within 16 dB of the main stroke, by energy, at any load', () => {
  const press = pressLegs()[1];
  for (const power of [0.3, 0.65, 1.0, 1.3, 1.5]) {
    const at = { power, crowd: 1, speed: 15, coast: 1, rpm: 110, road: 1 };
    const levelOf = (e) => (e.db ?? 0) + (e.db_by ?? []).reduce((a, c) => a + curveEval(c, at), 0);
    const main = energy('pedal_press', 0, 1e6) + levelOf(press);
    for (const machine of ['bike', 'breath', 'wheel']) {
      for (const e of doc.machines[machine].events) {
        const above = energy(e.sound, 2000, 1e6) + levelOf(e);
        assert.ok(above <= main - 16, `${e.sound} at ${power}: ${(above - main).toFixed(1)} dB`);
      }
    }
    // One other rider, at the kit's trim: more than two are quieter each, and they scatter.
    const peer = doc.machines.peer_bike.events[0];
    const above = energy(peer.sound, 2000, 1e6) + levelOf(peer) + doc.mix.other_db;
    assert.ok(above <= main - 16, `peer_tick at ${power}: ${(above - main).toFixed(1)} dB`);
  }
});

test('fatigue, read as the whole group: seven ticks a revolution, once the riders have scattered, against your two presses', () => {
  const peer = doc.machines.peer_bike.events[0];
  for (const power of [0.5, 0.65, 1.0]) {
    const at = { power };
    const levelOf = (e) => (e.db ?? 0) + (e.db_by ?? []).reduce((a, c) => a + curveEval(c, at), 0);
    const n = 7;
    const trim = doc.mix.other_db + doc.mix.other_doubling_db * Math.log2(n / 2);
    const perRev = 10 * Math.log10(n * peer.at.length);
    const group = energy(peer.sound, 2000, 1e6) + levelOf(peer) + trim + perRev;
    const main = energy('pedal_press', 0, 1e6) + 10 * Math.log10(pressLegs().reduce((a, e) => a + Math.pow(10, levelOf(e) / 10), 0));
    assert.ok(group <= main - 16, `seven at ${power}: ${(group - main).toFixed(1)} dB`);
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
    assert.ok(all.range >= 9, `${seg.rpm} rpm: ${all.range.toFixed(1)} dB over one revolution`);
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
  const others = scales.map((rpm_scale, i) => ({ id: `r${i}`, machine: 'peer_bike', lead: false, rpm_scale, params: { power } }));
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
  // A client reads a rider's cadence as an int, so most bots read exactly 90.
  const equal = groupLu([1, 1, 1, 1, 1, 0.989, 1.011]);
  assert.ok(equal <= -8, `five of seven at exactly equal rpm: ${equal.toFixed(2)} LU`);
});

const BOTS = [0.993, 1.004, 0.998, 1.006, 0.995, 1.002, 0.999];

// Five riders with one crank and one rpm: a resume, or a start, at the rounding of a client's snapshot.
test('no swell: five of seven at exactly equal rpm and one phase stay under the steady group', () => {
  const power = 0.65;
  const silent = { id: 'lead', machine: 'bike', lead: true, strokes: false, loops: false };
  const render = (scales) => {
    const machines = [silent, ...scales.map((rpm_scale, i) => ({ id: `r${i}`, machine: 'peer_bike', lead: false, rpm_scale, params: { power } }))];
    return mixdown(bank, simulate(bank, { segments: [{ rpm: 90, s: 30, params: { power } }], machines, seed: 1 }), { tail: 0 }).stems.Machines[0];
  };
  const steady = rmsLevel(render(BOTS), 10, 30);
  const locked = render([1, 1, 1, 1, 1, 0.989, 1.011]);
  for (const [a, b] of [[0.05, 0.75], [0.35, 1.5], [0.75, 3], [3, 10]]) {
    const over = rmsLevel(locked, a, b) - steady;
    assert.ok(over <= 1, `${a}-${b} s: ${over.toFixed(1)} dB over the steady group`);
  }
});

// Share of a stem's time and frequency cells, over 125 Hz-8 kHz, that stand 3 dB above the rest of the mix.
function clearShare(target, rest, size = 2048) {
  const a = [new Float64Array(size), new Float64Array(size)];
  const b = [new Float64Array(size), new Float64Array(size)];
  const window = Array.from({ length: size }, (_, i) => 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / size));
  const k0 = Math.ceil((125 * size) / MIX_RATE);
  const k1 = Math.floor((8000 * size) / MIX_RATE);
  const cells = [];
  let peak = 0;
  const n = Math.min(target.length, rest.length);
  for (let at = 0; at + size <= n; at += size) {
    for (let i = 0; i < size; i++) {
      a[0][i] = target[at + i] * window[i];
      a[1][i] = 0;
      b[0][i] = rest[at + i] * window[i];
      b[1][i] = 0;
    }
    fft(a[0], a[1]);
    fft(b[0], b[1]);
    for (let k = k0; k < k1; k++) {
      const pa = a[0][k] * a[0][k] + a[1][k] * a[1][k];
      const pb = b[0][k] * b[0][k] + b[1][k] * b[1][k];
      peak = Math.max(peak, pa);
      cells.push(pa, pb);
    }
  }
  let live = 0;
  let clear = 0;
  for (let i = 0; i < cells.length; i += 2) {
    if (cells[i] < peak * 1e-4) continue;
    live++;
    if (cells[i] > cells[i + 1] * 2) clear++;
  }
  return (100 * clear) / Math.max(1, live);
}

// Peak over median of the envelope synchronous with the revolution, in one band.
function revPeak(x, rpm, lo, hi, from) {
  const c = rbj('bp', Math.sqrt(lo * hi), Math.sqrt(lo * hi) / (hi - lo), MIX_RATE);
  const y = biquad(biquad(x, c), c);
  const bins = 48;
  const sum = new Float64Array(bins);
  const n = new Float64Array(bins);
  for (let i = Math.round(from * MIX_RATE); i < y.length; i++) {
    const r = (i / MIX_RATE) * (rpm / 60);
    const k = Math.floor((r - Math.floor(r)) * bins);
    sum[k] += y[i] * y[i];
    n[k]++;
  }
  const db = [...sum].map((v, k) => 10 * Math.log10(v / n[k] + 1e-30));
  return Math.max(...db) - [...db].sort((p, q) => p - q)[bins >> 1];
}

test('eight riders sound unlike one, and your own rhythm holds through them', () => {
  const power = 0.65;
  const speed = 8.5;
  const scene = {
    segments: [{ rpm: 90, s: 30, params: { power, speed, day: 0.3, coast: 0, crowd: 0, road: 0.5 } }],
    bed: 'dawn_road',
    bed_params: { gust: 0.5, tractor: 0 },
    seed: 3,
    loops: [{ id: 'tyre_hum', t0: 0, t1: 30, params: { speed, road: 0.5 } }, { id: 'wind_rush', t0: 0, t1: 30, params: { speed, gust: 0.5 } }],
  };
  const solo = mixdown(bank, simulate(bank, { ...scene, machines: [{ id: 'lead', machine: 'bike', lead: true }] }), { tail: 0 });
  const silent = { id: 'lead', machine: 'bike', lead: true, strokes: false, loops: false };
  const others = BOTS.map((rpm_scale, i) => ({ id: `r${i}`, machine: 'peer_bike', lead: false, rpm_scale, params: { power } }));
  const group = mixdown(bank, simulate(bank, { ...scene, machines: [silent, ...others] }), { tail: 0 }).stems.Machines[0];
  const rest = solo.sum[0];
  // The group's whirr this replaced read 5 %, and +0.5 dB everywhere: more of the same, not a group.
  const share = clearShare(group, rest);
  assert.ok(share >= 10, `the group clears the rest in ${share.toFixed(1)} % of its cells`);
  const both = rest.map((v, i) => v + group[i]);
  const riseAt = (hz) => {
    const c = rbj('bp', hz, 1.41, MIX_RATE);
    const e = (x) => biquad(x, c).reduce((a, v) => a + v * v, 0);
    return 10 * Math.log10(e(both) / e(rest));
  };
  assert.ok(riseAt(2800) >= riseAt(350) + 0.3, `a change of shape: ${riseAt(350).toFixed(2)} dB low, ${riseAt(2800).toFixed(2)} dB high`);
  for (const [lo, hi] of [[300, 1500], [1500, 4000]]) {
    const alone = revPeak(rest, 90, lo, hi, 3);
    const among = revPeak(both, 90, lo, hi, 3);
    assert.ok(among >= alone - 1, `${lo}-${hi} Hz: ${alone.toFixed(1)} dB alone, ${among.toFixed(1)} among them`);
  }
});

// --- what the critic could hear and the scorecard could not ----------------------------

// The rhythm in the whole mix, `s` long and read from `from`: the riders of a real ride start in one clump and scatter within a minute or two.
function rhythmAmong(scales, s, from) {
  const power = 0.65;
  const speed = 8.5;
  const scene = {
    segments: [{ rpm: 90, s, params: { power, speed, day: 0.3, coast: 0, crowd: 0, road: 0.5 } }],
    bed: 'dawn_road',
    bed_params: { gust: 0.5, tractor: 0 },
    seed: 3,
    loops: [{ id: 'tyre_hum', t0: 0, t1: s, params: { speed, road: 0.5 } }, { id: 'wind_rush', t0: 0, t1: s, params: { speed, gust: 0.5 } }],
  };
  const rest = mixdown(bank, simulate(bank, { ...scene, machines: [{ id: 'lead', machine: 'bike', lead: true }] }), { tail: 0 }).sum[0];
  const silent = { id: 'lead', machine: 'bike', lead: true, strokes: false, loops: false };
  const others = scales.map((rpm_scale, i) => ({ id: `r${i}`, machine: 'peer_bike', lead: false, rpm_scale, params: { power } }));
  // Every rider in the scene is one bot, with the bank's other_db and the doubling for its count.
  const group = mixdown(bank, simulate(bank, { ...scene, machines: [silent, ...others] }), { tail: 0 }).stems.Machines[0];
  const both = rest.map((v, i) => v + group[i]);
  return [[300, 1500], [1500, 4000]].map(([lo, hi]) => ({ lo, hi, alone: revPeak(rest, 90, lo, hi, from), among: revPeak(both, 90, lo, hi, from) }));
}

test('your own rhythm holds in a small party too: 1, 2 and 3 others cost at most 2 dB', () => {
  for (const scales of [[0.993], [0.993, 1.004], [0.993, 1.004, 0.998]]) {
    for (const r of rhythmAmong(scales, 60, 3)) {
      assert.ok(r.among >= r.alone - 2, `${scales.length} others, ${r.lo}-${r.hi} Hz: ${r.alone.toFixed(1)} dB alone, ${r.among.toFixed(1)} among them`);
    }
  }
});

test('your own rhythm holds once seven riders have scattered: at most 1 dB after 90 s', () => {
  for (const r of rhythmAmong(BOTS, 180, 90)) {
    assert.ok(r.among >= r.alone - 1, `${r.lo}-${r.hi} Hz: ${r.alone.toFixed(1)} dB alone, ${r.among.toFixed(1)} among them`);
  }
});

test('no three-beat loop: the strokes come round only after 140 revolutions', () => {
  const tick = bikeEvent('chain_tick');
  const gcd = (a, b) => (b === 0 ? a : gcd(b, a % b));
  const lcm = (a, b) => (a * b) / gcd(a, b);
  const tickRevs = lcm(doc.sounds.chain_tick.variants, tick.pitch_table.length);
  // Round-robin runs across both legs, so each leg takes every 2nd variant, one a revolution: 5 revolutions round.
  const pressRevs = pressLegs().reduce((a, leg) => lcm(a, lcm(doc.sounds.pedal_press.variants, leg.pitch_table.length)), 1);
  assert.equal(pressRevs, 20, 'the press alone: no exact repeat at 10 revolutions');
  const cycle = lcm(tickRevs, pressRevs);
  assert.equal(cycle, 140, `tick ${tickRevs}, press ${pressRevs}`);
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

// The press alone: the loudest stroke, so the one an accent would be heard in.
function pressStem(s) {
  const only = JSON.parse(JSON.stringify(doc));
  only.machines.bike.events = only.machines.bike.events.filter((e) => e.sound === 'pedal_press');
  const sim = simulate(new BankAudio(only, DIR), { segments: [{ rpm: 90, s, params: { power: 0.65 } }], machines: [{ id: 'lead', machine: 'bike', lead: true, loops: false }] });
  return { x: mixdown(bank, sim, { tail: 0 }).stems.Machines[0], voices: sim.voices };
}

function pearson(a, b) {
  const m = a.length;
  const ma = a.reduce((p, v) => p + v, 0) / m;
  const mb = b.reduce((p, v) => p + v, 0) / m;
  let ab = 0;
  let aa = 0;
  let bb = 0;
  for (let i = 0; i < m; i++) {
    ab += (a[i] - ma) * (b[i] - mb);
    aa += (a[i] - ma) * (a[i] - ma);
    bb += (b[i] - mb) * (b[i] - mb);
  }
  return ab / Math.sqrt(aa * bb + 1e-30);
}

test('no 2:3 against the tick: the press has no three-stroke accent', () => {
  assert.ok(doc.sounds.pedal_press.variants >= 5);
  const { x, voices } = pressStem(40);
  const centroids = voices.map((v) => {
    const at = Math.round(v.t * MIX_RATE);
    const p = powerSpectrum(x.subarray(at, at + 8192), 8192);
    let a = 0;
    let b = 0;
    for (let k = 0; k < p.length; k++) {
      a += k * p[k];
      b += p[k];
    }
    return (a * MIX_RATE) / 8192 / b;
  });
  const lag3 = pearson(centroids.slice(0, -3), centroids.slice(3));
  assert.ok(Math.abs(lag3) < 0.3, `centroid per stroke, lag 3: ${lag3.toFixed(2)}, was 1.00`);
  const lag = Math.round((1.5 * 60 * MIX_RATE) / 90);
  const wave = pearson(x.subarray(MIX_RATE, x.length - lag), x.subarray(MIX_RATE + lag, x.length));
  assert.ok(wave < 0.9, `waveform at 1.5 revolutions: ${wave.toFixed(2)}, was 0.97`);
});

test('each revolution has a strong leg and a weak one, within what a leg can be', () => {
  const [strong, weak] = pressLegs();
  assert.ok(strong.db - weak.db >= 1 && strong.db - weak.db <= 1.5, `${strong.db} against ${weak.db}`);
});

test('at endurance the frame creaks now and then on rough road, and never on smooth', () => {
  const run = (road) => simulate(bank, { segments: [{ rpm: 90, s: 40, params: { power: 0.65, speed: 8.5, road } }], machines: [{ id: 'lead', machine: 'bike', lead: true }] }).voices.filter((v) => v.sound === 'bb_creak');
  assert.equal(run(0.5).length, 0, 'smooth');
  const rough = run(0.85);
  assert.ok(rough.length >= 40, `${rough.length} creaks`);
  // A 7-step table on 3 variants: an exact cycle of 21, no repeat at three.
  const same = (a, b) => a.variant === b.variant && Math.abs(a.pitch - b.pitch) < 1e-9;
  assert.equal(rough.slice(3).filter((v, i) => same(v, rough[i])).length, 0);
  assert.ok(simulate(bank, { segments: [{ rpm: 90, s: 40, params: { power: 1.3, speed: 8.5, road: 0.5 } }], machines: [{ id: 'lead', machine: 'bike', lead: true }] }).voices.some((v) => v.sound === 'bb_creak'), 'under load on any road');
});

test('the most memorable sounds come round seldom in half an hour', () => {
  for (const [sound, most] of [['dog_far', 26], ['church_bell_far', 9]]) {
    for (const seed of [3, 7, 11, 19]) {
      const sim = simulate(bank, { segments: ridePlan(), machines: [{ id: 'lead', machine: 'bike', lead: true, strokes: false, loops: false }], bed: 'dawn_road', bed_params: {}, seed });
      const n = sim.events.filter((e) => e.kind === 'spot' && e.sound === sound).length;
      assert.ok(n >= 2 && n <= most, `seed ${seed}: ${sound} ${n} times in 25 minutes`);
    }
  }
});

test('no stroke comes round on three: every event with three variants has a pitch table to break them', () => {
  const scene = (machine, params, rpm) => ({ segments: [{ rpm, s: 40, params }], machines: [{ id: 'lead', machine, lead: true, loops: false }] });
  const cases = [
    ['bb_creak', scene('bike', { power: 1.3 }, 110)],
    ['breath', scene('breath', { power: 1.3 }, 55)],
    ['crowd_clap', scene('crowd', { crowd: 1 }, 110)],
    ['cowbell', scene('crowd', { crowd: 1 }, 110)],
  ];
  for (const [sound, sc] of cases) {
    assert.ok(bank.variants(sound) % 3 === 0, `${sound} has ${bank.variants(sound)} variants`);
    const strokes = simulate(bank, sc).voices.filter((v) => v.sound === sound);
    assert.ok(strokes.length > 18, `${sound}: ${strokes.length} strokes`);
    const same = (a, b) => a.variant === b.variant && Math.abs(a.pitch - b.pitch) < 1e-9;
    const atThree = strokes.slice(3).filter((v, i) => same(v, strokes[i])).length;
    assert.equal(atThree, 0, `${sound}: ${atThree} strokes repeat the one three before`);
  }
});

function ridePlan(segments = 50, each = 30) {
  return Array.from({ length: segments }, (_, i) => ({ rpm: 90, s: each, params: { power: 0.65, speed: 8.5, day: (i + 0.5) / segments, coast: 0, crowd: 0, gust: 0.5, tractor: 0, road: 0.5 } }));
}

test('the ride has an arc you can hear: a dawn chorus that thins as the day comes up, and never a silence', () => {
  const birds = new Set(['chirrup', 'wood_call', 'lark', 'rooster']);
  const total = 1500;
  for (const seed of [3, 7, 11]) {
    const sim = simulate(bank, { segments: ridePlan(), machines: [{ id: 'lead', machine: 'bike', lead: true, strokes: false, loops: false }], bed: 'dawn_road', bed_params: {}, seed, loops: [] });
    const spots = sim.events.filter((e) => e.kind === 'spot').sort((a, b) => a.t - b.t);
    const fifths = [0, 0, 0, 0, 0];
    for (const e of spots) if (birds.has(e.sound)) fifths[Math.min(4, Math.floor((e.t / total) * 5))]++;
    assert.ok(Math.min(fifths[0], fifths[1]) >= 2 * Math.max(fifths[3], fifths[4]), `seed ${seed}: birds by fifth of the ride ${fifths}`);
    const gaps = spots.slice(1).map((e, i) => e.t - spots[i].t);
    assert.ok(Math.max(...gaps) <= 30, `seed ${seed}: ${Math.max(...gaps).toFixed(1)} s with no spot`);
  }
});

test('no two details step on each other, on any seed: the bed spaces them', () => {
  const spots = doc.beds.dawn_road.spots;
  const min = doc.beds.dawn_road.spot_min_gap_s;
  assert.ok(min >= 2, `${min}`);
  const texture = new Set(spots.filter((x) => [x.gap_s].flat()[0] < min).map((x) => x.sound));
  for (let seed = 1; seed <= 12; seed++) {
    const sim = simulate(bank, { segments: ridePlan(10, 30), machines: [], bed: 'dawn_road', bed_params: {}, seed });
    const details = sim.events.filter((e) => e.kind === 'spot' && !texture.has(e.sound)).sort((a, b) => a.t - b.t);
    assert.ok(details.length > 5, `seed ${seed}`);
    for (let i = 1; i < details.length; i++) {
      if (details[i].sound === details[i - 1].sound) continue;
      assert.ok(details[i].t - details[i - 1].t >= 2, `seed ${seed}: ${details[i - 1].sound} and ${details[i].sound} at ${details[i].t.toFixed(1)}`);
    }
  }
});

test('the birds have no hole between dawn and day', () => {
  const layers = doc.beds.dawn_road.layers.filter((l) => l.sound.startsWith('birds'));
  const levelAt = (day) => 10 * Math.log10(layers.reduce((a, l) => a + Math.pow(10, (l.db + curveSumDb(l.db_by, { day })) / 10), 0));
  const quieterEnd = Math.min(levelAt(0), levelAt(1));
  for (let day = 0; day <= 1.0001; day += 0.01) {
    const db = levelAt(day);
    assert.ok(db >= quieterEnd - 2, `day ${day.toFixed(2)}: ${db.toFixed(1)} dB, the quieter end ${quieterEnd.toFixed(1)}`);
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
    segments: [{ rpm: 90, s: 12, params: { power: 0.65, speed, day: 0.3, coast: 0, crowd: 0, road: 0.5 } }],
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
  // `warning` is not in it: Workout's HudSpec silences its routine banner. The GUT test holds that through the real HUD.
  const hud = fs.readFileSync(path.resolve(HERE, '..', '..', '..', '..', 'src', 'games', 'workout', 'hud', 'workout_hud.gd'), 'utf8');
  assert.match(hud, /hs\.banner_sound = ""/);
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

// --- half an hour of it -----------------------------------------------------------------

// The adapter's own formulas. The table is shared with the GUT test that holds WorkoutAudio to it.
const roadAt = (d) => 0.5 + 0.25 * Math.sin(d / 59) + 0.15 * Math.sin(d / 157 + 1) + 0.1 * Math.sin(d / 367 + 2);
const gustAt = (t) => 0.5 + 0.5 * Math.sin(t / 11) * Math.sin(t / 3.7);
const airAt = (t) => 0.5 * gustAt(t) + 0.5 * (0.5 + 0.3 * Math.sin(t / 23) + 0.2 * Math.sin(t / 61));

test('these formulas are the table the adapter is held to', () => {
  const table = JSON.parse(fs.readFileSync(path.join(HERE, 'road_and_air.json'), 'utf8'));
  for (const [d, v] of table.road) assert.ok(Math.abs(roadAt(d) - v) < 1e-6, `road at ${d}`);
  for (const [t, v] of table.air) assert.ok(Math.abs(airAt(t) - v) < 1e-6, `air at ${t}`);
  for (let i = 0; i < 40000; i++) {
    assert.ok(roadAt(i) >= 0 && roadAt(i) <= 1, 'road within 0..1');
    assert.ok(airAt(i / 3) >= 0 && airAt(i / 3) <= 1, 'air within 0..1');
  }
});

// A steady block with air and road moving as in the game, frame by frame over the fixed parameters.
function steadyBlock(rpm, power, speed, s, day = 0.3) {
  const sim = simulate(bank, {
    segments: [{ rpm, s, params: { power, speed, day, coast: 0, crowd: 0, gust: 0.5, tractor: 0, road: 0.5 } }],
    machines: [{ id: 'lead', machine: 'bike', lead: true }, ...(power >= 1 ? [{ id: 'breath', machine: 'breath', lead: true, rpm_scale: 0.5 }] : [])],
    bed: 'dawn_road',
    bed_params: {},
    seed: 3,
    loops: [{ id: 'tyre_hum', t0: 0, t1: s, params: { speed, road: 0.5 } }, { id: 'wind_rush', t0: 0, t1: s, params: { speed, gust: 0.5 } }],
  });
  const follow = (track, layer, param, valueAt) => {
    for (const c of layer.db_by.filter((x) => x.param === param)) {
      const rest = curveEval(c, { [param]: 0.5 });
      for (let f = 0; f < track.db.length; f++) {
        if (track.db[f] > -60) track.db[f] += curveEval(c, { [param]: valueAt(f * FRAME_DT) }) - rest;
      }
    }
  };
  for (const track of sim.tracks) {
    const [kind, id, sound] = track.label.split(':');
    if (id === 'chain_rattle') follow(track, doc.machines.bike.loops.find((l) => l.sound === id), 'road', (t) => roadAt(t * speed));
    if (kind === 'loop' && id === 'tyre_hum') follow(track, doc.loops.tyre_hum.layers.find((l) => l.sound === sound), 'road', (t) => roadAt(t * speed));
    if (kind === 'loop' && id === 'wind_rush') follow(track, doc.loops.wind_rush.layers[0], 'gust', airAt);
    if (kind === 'bed' && id.startsWith('wind_grass')) follow(track, doc.beds.dawn_road.layers.find((l) => l.sound === id), 'gust', airAt);
  }
  return { sim, mix: mixdown(bank, sim, { tail: 0 }) };
}

function levels(x, step = 1) {
  const n = Math.round(step * MIX_RATE);
  const out = [];
  for (let at = 0; at + n <= x.length; at += n) {
    let e = 0;
    for (let i = at; i < at + n; i++) e += x[i] * x[i];
    out.push(10 * Math.log10(e / n + 1e-30));
  }
  return out;
}

test('a steady block repeats no swell: 1 s levels correlate under .7 at every lag from 10 to 150 s', () => {
  const { mix } = steadyBlock(90, 0.65, 8.5, 300);
  for (const [name, x] of [['the mix', mix.master[0]], ['the road', mix.stems.Sfx[0]]]) {
    const v = levels(x).slice(3);
    for (let lag = 10; lag <= 150; lag++) {
      const r = pearson(v.slice(0, v.length - lag), v.slice(lag));
      assert.ok(r < 0.7, `${name} at ${lag} s: ${r.toFixed(2)}`);
    }
  }
});

// A real steady block: ERG power, cadence wandering about a target, air and road moving as in the game, 0.5 s a step.
function rideBlock(s, { rpm = 88, power = 0.65, speed = 8.5, day = 0.5, seed = 3 } = {}) {
  const segments = [];
  const tyres = [];
  const wind = [];
  for (let k = 0; k * 0.5 < s; k++) {
    const t = k * 0.5;
    const road = roadAt(t * speed);
    const gust = airAt(t);
    segments.push({ rpm: rpm + Math.sin(t * 0.7) + 0.5 * Math.sin(t * 1.9), s: 0.5, params: { power, speed, day, coast: 0, crowd: 0, gust, road, tractor: 0 } });
    tyres.push({ id: 'tyre_hum', t0: t, t1: t + 0.5, params: { speed, road } });
    wind.push({ id: 'wind_rush', t0: t, t1: t + 0.5, params: { speed, gust } });
  }
  const sim = simulate(bank, { segments, machines: [{ id: 'lead', machine: 'bike', lead: true }], bed: 'dawn_road', bed_params: {}, seed, loops: [...tyres, ...wind] });
  return { sim, mix: mixdown(bank, sim, { tail: 0 }) };
}

// A band's level correlated with itself at a lag: what a repeating tile shows.
function bandCorrAt(x, lo, hi, lagS, from = 5) {
  const c = rbj('bp', Math.sqrt(lo * hi), Math.sqrt(lo * hi) / (hi - lo), MIX_RATE);
  const y = biquad(biquad(x, c), c);
  const hop = Math.round(0.05 * MIX_RATE);
  const v = [];
  for (let at = from * MIX_RATE; at + hop <= y.length; at += hop) {
    let e = 0;
    for (let i = at; i < at + hop; i++) e += y[i] * y[i];
    v.push(10 * Math.log10(e / hop + 1e-30));
  }
  const lag = Math.round(lagS / 0.05);
  return pearson(v.slice(0, v.length - lag), v.slice(lag));
}

function steadyRoad(s, speed = 8.5, road = 0.5) {
  const sim = simulate(bank, { segments: [{ rpm: 0, s, params: {} }], machines: [], loops: [{ id: 'tyre_hum', t0: 0, t1: s, params: { speed, road } }] });
  return mixdown(bank, sim, { tail: 0 }).stems.Sfx[0];
}

function rangeP5P95(v) {
  const sorted = [...v].sort((p, q) => p - q);
  return sorted[Math.floor(sorted.length * 0.95)] - sorted[Math.floor(sorted.length * 0.05)];
}

test('a steady ride is not monotone: three minutes of ERG at .65 has a loudness range, and every band moves', () => {
  const { mix } = rideBlock(180);
  const lra = loudnessRange(mix.master, MIX_RATE);
  assert.ok(lra >= 2, `LRA ${lra.toFixed(2)} LU, was 1.1`);
  const at = (lo, hi) => {
    const c = rbj('bp', Math.sqrt(lo * hi), Math.sqrt(lo * hi) / (hi - lo), MIX_RATE);
    return rangeP5P95(levels(biquad(biquad(mix.master[0], c), c), 3).slice(1));
  };
  for (const [lo, hi, min] of [[150, 500, 1.6], [500, 1500, 1.6], [1500, 4000, 1.9], [4000, 9000, 3]]) {
    assert.ok(at(lo, hi) >= min, `${lo}-${hi} Hz moves ${at(lo, hi).toFixed(2)} dB over 3 s steps`);
  }
});

// How far a band's level correlation at a tile's length stands over the lags just beside it: a tile, not a slow swell.
function tilePeak(x, lo, hi, lagS) {
  return bandCorrAt(x, lo, hi, lagS) - Math.max(bandCorrAt(x, lo, hi, lagS - 0.5), bandCorrAt(x, lo, hi, lagS + 0.5));
}

test('a tile does not show in its own band, on a ride or alone in the bed', () => {
  const { mix } = rideBlock(120);
  const bed = mix.stems.Ambience[0];
  // The old bank reads .72, .49 and .16 here.
  assert.ok(tilePeak(bed, 60, 300, 11) < 0.25, `the bed, 60-300 Hz at 11 s: ${tilePeak(bed, 60, 300, 11).toFixed(2)}`);
  assert.ok(tilePeak(bed, 4000, 9000, 3) < 0.2, `the bed, 4-9 kHz at 3 s: ${tilePeak(bed, 4000, 9000, 3).toFixed(2)}`);
  assert.ok(tilePeak(mix.master[0], 4000, 9000, 3) < 0.1, `the mix, 4-9 kHz at 3 s: ${tilePeak(mix.master[0], 4000, 9000, 3).toFixed(2)}`);
  // Air and road held still, nothing but the tile can show: the old bank reads .53 on the plain correlation at 9 s.
  const held = steadyRoad(120);
  assert.ok(bandCorrAt(held, 150, 500, 9.05) < 0.3, `the road, 150-500 Hz at 9 s: ${bandCorrAt(held, 150, 500, 9.05).toFixed(2)}`);
});

test('the twins add no level: two players at -3 dB for one, in the three loops that have one', () => {
  const twin = (layers, sound) => layers.filter((l) => l.sound === sound);
  for (const [layers, sound] of [[doc.loops.tyre_hum.layers, 'tyre_hum'], [doc.beds.dawn_road.layers, 'wind_grass_lo'], [doc.beds.dawn_road.layers, 'birds_day']]) {
    const [a, b] = twin(layers, sound);
    assert.ok(a && b, sound);
    assert.equal(a.db, b.db, sound);
    assert.deepEqual(a.db_by, b.db_by, sound);
    assert.ok(curveEval(b.pitch_by.at(-1), {}) > 1.05, `${sound}: at a pitch of its own`);
  }
});

test('the preview plays the HUD the game plays at a sprint end, for D5 to read', () => {
  const end = doc.preview.events.filter((e) => e.cue === 'interval_end').at(-1).t;
  const at = doc.preview.hud.filter((h) => h.t === end).map((h) => h.sound).sort();
  assert.deepEqual(at, ['phase', 'toast']);
});

// A band's 200 ms levels through a loop's own file.
function fileBandLevels(id, lo, hi) {
  const f = bank.file(id, 0);
  const c = rbj('bp', Math.sqrt(lo * hi), Math.sqrt(lo * hi) / (hi - lo), f.rate);
  const y = biquad(biquad(f.data[0], c), c);
  const hop = Math.round(0.2 * f.rate);
  const out = [];
  for (let at = 0; at + hop <= (f.loopFrames || f.frames); at += hop) {
    let e = 0;
    for (let i = at; i < at + hop; i++) e += y[i] * y[i];
    out.push(10 * Math.log10(e / hop + 1e-30));
  }
  return out;
}

test('the grass has no notch to give its 7 s away', () => {
  const v = fileBandLevels('wind_grass_hi', 1500, 8000);
  const range = Math.max(...v) - Math.min(...v);
  assert.ok(range <= 9, `${range.toFixed(1)} dB over 200 ms steps, was 13.2`);
});

function stemOf(sim, keep) {
  return mixdown(bank, { ...sim, voices: sim.voices.filter(keep), tracks: [], ducks: [] }, { tail: 0 }).sum[0];
}

test('the dawn loop sits under its birds and does not show its 4 s', () => {
  const { sim, mix } = steadyBlock(83, 0.6, 7.5, 60, 0.1);
  const c = rbj('bp', 5600, 5600 / 4000, MIX_RATE);
  const y = biquad(biquad(mix.master[0], c), c);
  const hop = Math.round(0.02 * MIX_RATE);
  const raw = [];
  for (let at = 0; at + hop <= y.length; at += hop) {
    let e = 0;
    for (let i = at; i < at + hop; i++) e += y[i] * y[i];
    raw.push(Math.log10(e / hop + 1e-30));
  }
  // Less the air's swell of many seconds, which correlates at any short lag: only a tile is left to show.
  const reach = 50;
  const v = raw.map((x, i) => {
    let sum = 0;
    let n = 0;
    for (let k = Math.max(0, i - reach); k <= Math.min(raw.length - 1, i + reach); k += 5) {
      sum += raw[k];
      n++;
    }
    return x - sum / n;
  });
  const at = (s) => {
    const lag = Math.round(s / 0.02);
    return pearson(v.slice(100, v.length - lag), v.slice(100 + lag));
  };
  assert.ok(at(4) < 0.35, `4-8 kHz at its 4 s: ${at(4).toFixed(2)}, was 0.575`);
  const loopOnly = mixdown(bank, { ...sim, voices: [], tracks: sim.tracks.filter((t) => t.sound === 'birds_dawn'), ducks: [] }, { tail: 0 }).sum[0];
  const peakOf = (x) => Math.max(...levels(x, 0.1).slice(10));
  const spots = stemOf(sim, (w) => w.sound === 'lark' || w.sound === 'chirrup' || w.sound === 'wood_call');
  assert.ok(peakOf(loopOnly) < peakOf(spots) - 3, `loop ${peakOf(loopOnly).toFixed(1)}, its birds ${peakOf(spots).toFixed(1)}`);
});

test('the load layers are heard in the real mix, road included', () => {
  // On this measure the levels that could not be heard read breath 2.5 and 3.6 %, creak 1.3 and 1.9 %.
  for (const [rpm, power, speed, breathMin, creakMin] of [[110, 1.05, 11, 5, 3], [100, 1.2, 12, 7, 4]]) {
    const { sim, mix } = steadyBlock(rpm, power, speed, 30, 0.5);
    const breath = stemOf(sim, (v) => v.sound === 'breath');
    const creak = stemOf(sim, (v) => v.sound === 'bb_creak');
    const all = mix.sum[0];
    const b = clearShare(breath, all.map((v, i) => v - breath[i]));
    const c = clearShare(creak, all.map((v, i) => v - creak[i]));
    assert.ok(b >= breathMin, `breath at ${power}: ${b.toFixed(1)} %`);
    assert.ok(c >= creakMin, `creak at ${power}: ${c.toFixed(1)} %`);
  }
});

// Best third-octave signal over the rest in a sliding 120 ms window, per play of a spot: the median play.
function bestSnr(b, sim, mix, id) {
  const spot = mixdown(b, { ...sim, voices: sim.voices.filter((v) => v.sound === id), tracks: [], ducks: [] }, { tail: 0 }).sum[0];
  const all = mix.sum[0];
  const size = 4096;
  const out = [];
  for (const v of sim.voices.filter((w) => w.sound === id)) {
    let best = -Infinity;
    const file = b.file(id, v.variant);
    const end = Math.round((v.t + file.frames / file.rate) * MIX_RATE);
    for (let at = Math.round(v.t * MIX_RATE); at + size < Math.min(end, all.length); at += 1024) {
      const a = spot.subarray(at, at + size);
      const ps = powerSpectrum(a, size);
      const pr = powerSpectrum(all.subarray(at, at + size).map((x, i) => x - a[i]), size);
      for (let hz = 200; hz < 5000; hz *= 1.26) {
        let s = 0;
        let r = 0;
        for (let k = Math.ceil((hz * size) / MIX_RATE); k < (hz * 1.26 * size) / MIX_RATE; k++) {
          s += ps[k];
          r += pr[k];
        }
        if (s > 0) best = Math.max(best, 10 * Math.log10(s / (r + 1e-30)));
      }
    }
    out.push(best);
  }
  return out.sort((p, q) => p - q)[out.length >> 1];
}

test('the far stratum reads at endurance: a dog and a bell now and then', () => {
  const near = JSON.parse(JSON.stringify(doc));
  for (const s of near.beds.dawn_road.spots) {
    if (s.sound === 'dog_far' || s.sound === 'church_bell_far') s.gap_s = [6, 9];
  }
  const b = new BankAudio(near, DIR);
  const speed = 8.5;
  const sim = simulate(b, {
    segments: [{ rpm: 90, s: 90, params: { power: 0.65, speed, day: 0.3, coast: 0, crowd: 0, gust: 0.5, tractor: 0, road: 0.5 } }],
    machines: [{ id: 'lead', machine: 'bike', lead: true }],
    bed: 'dawn_road',
    bed_params: {},
    seed: 3,
    loops: [{ id: 'tyre_hum', t0: 0, t1: 90, params: { speed, road: 0.5 } }, { id: 'wind_rush', t0: 0, t1: 90, params: { speed, gust: 0.5 } }],
  });
  const mix = mixdown(b, sim, { tail: 0 });
  const dog = bestSnr(b, sim, mix, 'dog_far');
  const bell = bestSnr(b, sim, mix, 'church_bell_far');
  // On this measure, the median play's best band, the levels that were masked read -10.9 and +3.6.
  assert.ok(dog >= -6, `dog ${dog.toFixed(1)} dB`);
  assert.ok(bell >= 5, `bell ${bell.toFixed(1)} dB`);
});

test('the far dog reads alike at every speed: near on a slow road would be as wrong as lost on a fast one', () => {
  const near = JSON.parse(JSON.stringify(doc));
  for (const x of near.beds.dawn_road.spots) {
    if (x.sound === 'dog_far') x.gap_s = [6, 9];
  }
  const b = new BankAudio(near, DIR);
  const read = (speed, rpm, power) => {
    const sim = simulate(b, {
      segments: [{ rpm, s: 90, params: { power, speed, day: 0.3, coast: 0, crowd: 0, gust: 0.5, tractor: 0, road: 0.5 } }],
      machines: [{ id: 'lead', machine: 'bike', lead: true }],
      bed: 'dawn_road',
      bed_params: {},
      seed: 3,
      loops: [{ id: 'tyre_hum', t0: 0, t1: 90, params: { speed, road: 0.5 } }, { id: 'wind_rush', t0: 0, t1: 90, params: { speed, gust: 0.5 } }],
    });
    return bestSnr(b, sim, mixdown(b, sim, { tail: 0 }), 'dog_far');
  };
  const all = [read(5.5, 60, 0.5), read(8.5, 90, 0.65), read(13, 110, 1.05)];
  assert.ok(Math.max(...all) - Math.min(...all) <= 4, `${all.map((v) => v.toFixed(1))} dB at 5.5, 8.5, 13 m/s`);
  assert.ok(Math.min(...all) >= -4, `${all.map((v) => v.toFixed(1))} dB`);
});

test('in the sprint the crowd leaves you your rhythm: the claps are on your crank, and the mids still pump', () => {
  const scenario = previewScenario(doc);
  const mix = mixdown(bank, simulate(bank, { ...scenario, shared }), { shared, tail: 0 });
  const whole = mix.sum[0];
  const times = doc.preview.segments;
  let t = 0;
  let sprintAt = -1;
  for (const seg of times) {
    if (seg.params.crowd === 1) sprintAt = t;
    t += seg.s;
  }
  assert.ok(sprintAt > 0, 'the preview has a sprint');
  const from = sprintAt + 4;
  const x = whole.subarray(Math.round(from * MIX_RATE), Math.round((from + 13.5) * MIX_RATE));
  const mids = revPeak(x, 110, 300, 1500, 0);
  const highs = revPeak(x, 110, 1500, 4000, 0);
  assert.ok(mids >= 8, `300-1500 Hz: ${mids.toFixed(1)} dB, was 7.7`);
  assert.ok(highs >= 8, `1.5-4 kHz: ${highs.toFixed(1)} dB`);
});

test('the far bell shares no note with the cues, so it is never taken for a phase change', () => {
  const partials = (id) => doc.sounds[id].layers.filter((l) => l.src === 'modal' || l.src === 'tri').flatMap((l) => [l.f].flat());
  for (const f of doc.sounds.church_bell_far.layers[0].f) {
    for (const cue of [...partials('interval_chime'), ...partials('interval_bell')]) {
      assert.ok(Math.abs(1200 * Math.log2(f / cue)) > 50, `${f} Hz against ${cue} Hz`);
    }
  }
});

test('the most audible spots have their own contours', () => {
  const contours = (id) => doc.sounds[id].per_variant.map((v) => JSON.stringify((v.layers ?? doc.sounds[id].layers)[0].points));
  assert.equal(new Set(contours('lark')).size, 2, 'lark');
  assert.equal(new Set(contours('wood_call')).size, 3, 'wood call');
});

test('the crowd pumps on no clock of its own: its claps are the only beat it has', () => {
  for (const l of doc.sounds.crowd_loop.layers) {
    assert.ok(!(l.fx ?? []).some((f) => f.trem !== undefined), 'no tremolo');
  }
  const f = bank.file('crowd_loop', 0);
  const c = rbj('bp', 1400, 1400 / 3500, f.rate);
  const y = biquad(biquad(f.data[0], c), c);
  const hop = Math.round(0.02 * f.rate);
  const v = [];
  for (let at = 0; at + hop <= f.loopFrames; at += hop) {
    let e = 0;
    for (let i = at; i < at + hop; i++) e += y[i] * y[i];
    v.push(10 * Math.log10(e / hop + 1e-30));
  }
  const smooth = v.map((_, i) => {
    let a = 0;
    for (let k = -2; k <= 2; k++) a += Math.pow(10, v[(i + k + v.length) % v.length] / 10);
    return 10 * Math.log10(a / 5);
  });
  const sorted = [...smooth].sort((p, q) => p - q);
  const range = sorted[Math.floor(sorted.length * 0.95)] - sorted[Math.floor(sorted.length * 0.05)];
  assert.ok(range <= 3, `${range.toFixed(1)} dB, 5-95 %, was 3.9`);
  const lag = Math.round(0.4 / 0.02);
  const r = pearson(smooth, [...smooth.slice(lag), ...smooth.slice(0, lag)]);
  assert.ok(r < 0.5, `at 0.4 s: ${r.toFixed(2)}, was 0.66`);
});
