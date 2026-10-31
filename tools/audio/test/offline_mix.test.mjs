import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BankAudio, MIX_RATE, limit, mixdown, simulate, toInt16 } from '../lib/offline_mix.mjs';
import { FIXTURE_BANK, bankOf, readJson } from './helpers.mjs';

const TICK = { dur: 0.04, seed: 1, locked: true, norm: { peak: -6 }, layers: [{ src: 'noise', env: { a: 0.0003, d: 0.03 } }] };
const LOOP = { dur: 1, seed: 2, loop: true, compress: 'pcm', layers: [{ src: 'sine', f: 441 }] };

function bank({ sounds = {}, ...rest }) {
  return new BankAudio(bankOf({ tick: TICK, hum: LOOP, ...sounds }, rest), null);
}

function firstLoud(x, from = 0, thresh = 0.02) {
  for (let i = from; i < x.length; i++) if (Math.abs(x[i]) > thresh) return i;
  return -1;
}

const ONE = { machines: { m: { events: [{ at: [0.5], sound: 'tick' }] } } };

test('a stroke lands on its revolution fraction, the pre-roll skipped', () => {
  const b = bank(ONE);
  const sim = simulate(b, { segments: [{ rpm: 60, s: 3, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }] });
  assert.deepEqual(sim.voices.map((v) => Math.round(v.t * 1000) / 1000), [0.5, 1.5, 2.5]);
  const mix = mixdown(b, sim);
  const at = firstLoud(mix.stems.Machines[0]);
  assert.ok(Math.abs(at / MIX_RATE - 0.5) < 0.001, `${at / MIX_RATE}`);
  const again = firstLoud(mix.stems.Machines[0], Math.round(1.2 * MIX_RATE));
  assert.ok(Math.abs(again / MIX_RATE - 1.5) < 0.001);
});

test('stop is dead: no stroke after rpm 0; loops close', () => {
  const b = bank({ machines: { m: { events: ONE.machines.m.events, loops: [{ sound: 'hum', db: -6, min_rpm: 8 }] } } });
  const sim = simulate(b, { segments: [{ rpm: 90, s: 2, params: {} }, { rpm: 0, s: 2, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }] });
  assert.ok(sim.voices.every((v) => v.t <= 2.05));
  const mix = mixdown(b, sim, { tail: 0 });
  const x = mix.stems.Machines[0];
  let tail = 0;
  for (let i = Math.round(2.3 * MIX_RATE); i < x.length; i++) tail = Math.max(tail, Math.abs(x[i]));
  assert.equal(tail, 0);
});

test('other riders: quieter by other_db, lead_only gone, loops only with `other`', () => {
  const doc = {
    machines: { m: { events: [{ at: [0], sound: 'tick', db: 0 }, { at: [0.5], sound: 'tick', db: 0, lead_only: true }], loops: [{ sound: 'hum', db: 0, other: false }] } },
    mix: { other_db: -10 },
  };
  const b = bank(doc);
  const lead = simulate(b, { segments: [{ rpm: 60, s: 3, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }] });
  const other = simulate(b, { segments: [{ rpm: 60, s: 3, params: {} }], machines: [{ id: 'l', machine: 'm', lead: true, strokes: false, loops: false }, { id: 'o', machine: 'm', lead: false }] });
  assert.equal(lead.voices.length, 6, '1, 2, 3 and .5, 1.5, 2.5: the last is inside the horizon');
  assert.equal(other.voices.length, 3);
  assert.ok(other.voices.every((v) => v.db === -10));
  assert.ok(other.voices.every((v) => v.priority === 3));
  assert.ok(lead.tracks[0].db.some((d) => d > -1));
  assert.ok(other.tracks.every((t) => t.db.every((d) => d === -60)));
});

test('more than two others: the doubling rule; no lead: the spectator rise', () => {
  const b = bank({ machines: { m: { events: [{ at: [0], sound: 'tick' }] } }, mix: { other_db: -10, other_doubling_db: -3, other_min_gap_s: 0 } });
  const riders = (n, lead) => Array.from({ length: n }, (_, i) => ({ id: `r${i}`, machine: 'm', lead: lead && i === 0 }));
  const seg = [{ rpm: 60, s: 1.5, params: {} }];
  const four = simulate(b, { segments: seg, machines: riders(5, true) });
  assert.ok(four.voices.filter((v) => !v.lead).every((v) => Math.abs(v.db - -13) < 1e-9), 'n = 4: -10 - 3 log2(2)');
  const spect = simulate(b, { segments: seg, machines: riders(2, false) });
  assert.ok(spect.voices.every((v) => v.db === -6));
});

test('thinning: other strokes at most 1 / other_min_gap_s, the lead never thinned, first come first served', () => {
  const b = bank({ machines: { m: { events: [{ at: [0, 0.5], sound: 'tick' }] } }, mix: { other_min_gap_s: 0.06 } });
  const machines = [{ id: 'l', machine: 'm', lead: true }];
  for (let i = 0; i < 7; i++) machines.push({ id: `o${i}`, machine: 'm', lead: false, rpm_scale: (88 + 4 * i) / 100 });
  const sim = simulate(b, { segments: [{ rpm: 100, s: 60, params: {} }], machines });
  assert.ok(sim.thinned > 0);
  const others = sim.events.filter((e) => e.kind === 'stroke' && !e.thinned && e.machine !== 'l');
  assert.ok(others.length / 60 <= 1 / 0.06);
  const lead = sim.events.filter((e) => e.machine === 'l');
  assert.ok(lead.every((e) => !e.thinned));
  assert.equal(lead.length, 200);
  for (let i = 1; i < others.length; i++) assert.ok(others[i].t - others[i - 1].t >= 0.06 - 1e-9);
  assert.ok(sim.voicePeak.Machines <= 16);
});

test('voice pools: a full pool steals the oldest of lowest priority; a lead is safe from others', () => {
  const b = bank({
    sounds: { long: { dur: 1, seed: 3, locked: true, layers: [{ src: 'noise' }] } },
    machines: { m: { events: [{ at: [0, 0.25, 0.5, 0.75], sound: 'long' }] } },
    mix: { machine_voices: 2 },
  });
  const sim = simulate(b, { segments: [{ rpm: 120, s: 2, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }] });
  assert.equal(sim.voicePeak.Machines, 2);
  const sorted = [...sim.voices].sort((x, y) => x.t - y.t);
  assert.ok(sorted[0].end <= sorted[2].t + 1e-9, 'the oldest was cut');
});

test('cues: delay, vars, pitch, variant round-robin; a stem per bus', () => {
  const b = bank({
    sounds: { boom: { dur: 0.1, seed: 4, variants: 2, layers: [{ src: 'noise', env: { d: 0.05 } }] } },
    cues: { c: { hits: [{ sound: 'boom', db: -6, pitch: 1.0, bus: 'Sfx', delay_s: 0.1, delay_var: 'wait', pitch_var: 'p', db_var: 'd' }], other_db: -8 } },
  });
  const sim = simulate(b, {
    segments: [{ rpm: 0, s: 2, params: {} }],
    machines: [],
    cues: [{ t: 0.5, cue: 'c', vars: { wait: 0.2, p: 1.5, d: 3 } }, { t: 1.0, cue: 'c', lead: false }],
  });
  const [v0, v1] = sim.voices;
  assert.ok(Math.abs(v0.t - 0.8) < 0.02);
  assert.equal(v0.pitch, 1.5);
  assert.equal(v0.db, -3);
  assert.equal(v0.variant, 0);
  assert.equal(v1.variant, 1);
  assert.equal(v1.db, -14);
  const mix = mixdown(b, sim);
  assert.ok(firstLoud(mix.stems.Sfx[0]) > 0);
  assert.equal(firstLoud(mix.stems.Machines[0]), -1);
});

test('a duck pulls its bus down and lets go; the deepest of several wins', () => {
  const b = bank({ machines: { m: { loops: [{ sound: 'hum', db: -6 }] } }, cues: { d: { hits: [], duck: [{ bus: 'Machines', db: -12, attack_s: 0.01, release_s: 0.2 }, { bus: 'Machines', db: -3, attack_s: 0.01, release_s: 0.2 }] } } });
  const sim = simulate(b, { segments: [{ rpm: 60, s: 2, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }], cues: [{ t: 1, cue: 'd' }] });
  const x = mixdown(b, sim, { tail: 0 }).stems.Machines[0];
  const rms = (t) => {
    const at = Math.round(t * MIX_RATE);
    let s = 0;
    for (let i = 0; i < 200; i++) s += x[at + i] * x[at + i]; // two periods of 441 Hz
    return 10 * Math.log10(s / 200);
  };
  const open = rms(0.8);
  assert.ok(Math.abs(rms(1.02) - (open - 12)) < 1.5, `${rms(1.02)} vs ${open}`);
  assert.ok(Math.abs(rms(1.5) - open) < 0.5, 'released');
});

test('a safety prompt plays on Master and ducks Machines, Ambience, Sfx', () => {
  const shared = new BankAudio(readJson(`${FIXTURE_BANK.replace(/tools[\\/]audio.*$/, '')}assets/_shared/audio/audio.json`), null);
  const b = bank({ machines: { m: { loops: [{ sound: 'hum', db: -6 }] } } });
  const sim = simulate(b, { segments: [{ rpm: 60, s: 2, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }], prompts: [{ t: 1, name: 'warning' }], shared });
  assert.deepEqual(sim.ducks.map((d) => [d.bus, d.db]), [['Machines', -6], ['Ambience', -6], ['Sfx', -4]]);
  const mix = mixdown(b, sim, { shared });
  assert.ok(firstLoud(mix.stems.Master[0]) > 0);
});

test('a looping track: pitch follows, no click at the wrap', () => {
  const b = bank({ machines: { m: { loops: [{ sound: 'hum', db: -6, pitch_by: [{ param: 'rpm', ratio: 90 }] }] } } });
  const sim = simulate(b, { segments: [{ rpm: 180, s: 3, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }] });
  const x = mixdown(b, sim, { tail: 0 }).stems.Machines[0];
  let n = 0;
  const from = MIX_RATE;
  const to = 2 * MIX_RATE;
  for (let i = from; i < to; i++) if (x[i - 1] < 0 && x[i] >= 0) n++;
  assert.ok(Math.abs(n - 882) < 6, `${n} Hz`);
  let worst = 0;
  for (let i = from; i < to; i++) worst = Math.max(worst, Math.abs(x[i] - x[i - 1]));
  const pure = (2 * Math.PI * 882) / MIX_RATE;
  const amp = Math.max(...x.subarray(from, to).map(Math.abs));
  assert.ok(worst < amp * pure * 1.5, 'the seam is no bigger than a step of the tone');
});

test('the bed: layers on Ambience, seeded spots, the spot pool caps', () => {
  const b = bank({
    sounds: { spot: { dur: 2, seed: 5, layers: [{ src: 'noise' }] } },
    beds: { f: { layers: [{ sound: 'hum', db: -20 }], spots: [{ sound: 'spot', gap_s: 0.1, db: -20 }] } },
    mix: { spot_voices: 3 },
  });
  const a = simulate(b, { segments: [{ rpm: 0, s: 6, params: {} }], machines: [], bed: 'f', seed: 3 });
  const c = simulate(b, { segments: [{ rpm: 0, s: 6, params: {} }], machines: [], bed: 'f', seed: 3 });
  assert.deepEqual(a.voices.map((v) => v.t), c.voices.map((v) => v.t));
  assert.ok(a.voicePeak.Ambience <= 3);
  assert.ok(a.tracks[0].db[200] > -21);
  assert.ok(firstLoud(mixdown(b, a).stems.Ambience[0]) >= 0);
});

test('named loops open and close on their own span', () => {
  const b = bank({ loops: { scream: { bus: 'Sfx', layers: [{ sound: 'hum', db: -6 }] } } });
  const sim = simulate(b, { segments: [{ rpm: 0, s: 3, params: {} }], machines: [], loops: [{ id: 'scream', t0: 1, t1: 2, params: {} }] });
  const x = mixdown(b, sim, { tail: 0 }).stems.Sfx[0];
  const level = (t) => Math.abs(x[Math.round(t * MIX_RATE)]) + Math.abs(x[Math.round(t * MIX_RATE) + 25]);
  assert.equal(level(0.5), 0);
  assert.ok(level(1.5) > 0);
  assert.equal(level(2.5), 0);
});

test('limit: nothing passes the ceiling; a quiet signal is untouched', () => {
  const n = MIX_RATE;
  const loud = [new Float64Array(n), new Float64Array(n)];
  for (let i = 0; i < n; i++) {
    loud[0][i] = 2 * Math.sin((2 * Math.PI * 500 * i) / MIX_RATE);
    loud[1][i] = loud[0][i];
  }
  const out = limit(loud);
  assert.ok(Math.max(...out[0].map(Math.abs)) <= Math.pow(10, -1 / 20));
  const quiet = [loud[0].map((v) => v * 0.1), loud[1].map((v) => v * 0.1)];
  assert.deepEqual(limit(quiet)[0], quiet[0]);
});

test('toInt16 clamps', () => {
  assert.deepEqual([...toInt16([Float64Array.from([2, -2]), Float64Array.from([0.5, 0])])], [32767, 16384, -32768, 0]);
});

test('unknown names are errors', () => {
  const b = bank({});
  assert.throws(() => simulate(b, { segments: [{ rpm: 0, s: 1, params: {} }], machines: [{ id: 'a', machine: 'zz', lead: true }] }), /no machine/);
  assert.throws(() => simulate(b, { segments: [{ rpm: 0, s: 1, params: {} }], machines: [], cues: [{ t: 0, cue: 'zz' }] }), /no cue/);
  assert.throws(() => simulate(b, { segments: [{ rpm: 0, s: 1, params: {} }], machines: [], loops: [{ id: 'zz', t0: 0, t1: 1 }] }), /no loops entry/);
  assert.throws(() => b.file('zz'), /no sound/);
});
