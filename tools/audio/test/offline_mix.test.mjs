import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { BankAudio, MIX_RATE, PAN_MAX, PAN_STEP, PROMPT_UI_DUCK, PROMPT_UI_SPARED, PROMPT_VOICE_DB, SAFETY_DUCK, limit, mixdown, panGains, renderVoice, simulate, toInt16 } from '../lib/offline_mix.mjs';
import { FIXTURE_BANK, REPO, bankOf, readJson } from './helpers.mjs';

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

test('a safety prompt plays on Master and ducks Machines, Ambience, Sfx, and the UI but for what it spares', () => {
  const shared = new BankAudio(readJson(`${FIXTURE_BANK.replace(/tools[\\/]audio.*$/, '')}assets/_shared/audio/audio.json`), null);
  const b = bank({ machines: { m: { loops: [{ sound: 'hum', db: -6 }] } } });
  const sim = simulate(b, { segments: [{ rpm: 60, s: 2, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }], prompts: [{ t: 1, name: 'warning' }], shared });
  assert.deepEqual(sim.ducks.map((d) => [d.bus, d.db]), [['Machines', -14], ['Ambience', -14], ['Sfx', -20], ['UI', -10]]);
  const mix = mixdown(b, sim, { shared });
  assert.ok(firstLoud(mix.stems.Master[0]) > 0);
});

test('the preview ducks a safety prompt as WlSfx does', () => {
  const src = fs.readFileSync(path.join(REPO, 'addons', 'wattlands', 'audio', 'sfx.gd'), 'utf8');
  const attack = Number(src.match(/SAFETY_DUCK_ATTACK_S := ([\d.]+)/)[1]);
  const release = Number(src.match(/SAFETY_DUCK_RELEASE_S := ([\d.]+)/)[1]);
  const asked = [...src.matchAll(/AudioBuses\.duck\(AudioBuses\.(\w+), (-?[\d.]+), SAFETY_DUCK_ATTACK_S, SAFETY_DUCK_RELEASE_S\)/g)];
  assert.equal(asked.length, SAFETY_DUCK.length);
  for (const [i, m] of asked.entries()) {
    assert.equal(m[1].toLowerCase(), SAFETY_DUCK[i].bus.toLowerCase());
    assert.equal(Number(m[2]), SAFETY_DUCK[i].db);
    assert.equal(attack, SAFETY_DUCK[i].attack_s);
    assert.equal(release, SAFETY_DUCK[i].release_s);
  }
});

test('the preview trims the UI under a safety prompt as WlSfx does', () => {
  const src = fs.readFileSync(path.join(REPO, 'addons', 'wattlands', 'audio', 'sfx.gd'), 'utf8');
  assert.equal(Number(src.match(/SAFETY_UI_DB := (-?[\d.]+)/)[1]), PROMPT_UI_DUCK.db);
  assert.equal(Number(src.match(/SAFETY_DUCK_ATTACK_S := ([\d.]+)/)[1]), PROMPT_UI_DUCK.attack_s);
  assert.equal(Number(src.match(/SAFETY_DUCK_RELEASE_S := ([\d.]+)/)[1]), PROMPT_UI_DUCK.release_s);
  const spared = src.match(/SAFETY_UI_SPARED: Array\[String\] = \[(.*)\]/)[1].match(/"[^"]+"/g).map((q) => q.slice(1, -1));
  assert.deepEqual(spared.sort(), [...PROMPT_UI_SPARED].sort());
});

test('preview.hud: the UI sounds on its bus, a prompt takes it down, and spares the count', () => {
  const shared = new BankAudio(readJson(path.join(REPO, 'assets', '_shared', 'audio', 'audio.json')), null);
  const scene = (hud, prompts, withShared) => ({ segments: [{ rpm: 0, s: 3, params: {} }], machines: [], hud, prompts, shared: withShared ? shared : null });
  const render = (hud, prompts) => mixdown(bank({}), simulate(bank({}), scene(hud, prompts, true)), { shared }).stems.UI[0];
  const energy = (x) => x.reduce((a, v) => a + v * v, 0);
  assert.equal(energy(mixdown(bank({}), simulate(bank({}), scene([{ t: 1, sound: 'phase' }], [], false))).stems.UI[0]), 0, 'no _shared bank, no HUD');
  const phase = energy(render([{ t: 1, sound: 'phase' }], []));
  const count = energy(render([{ t: 1, sound: 'countdown' }], []));
  assert.ok(phase > 0 && count > 0);
  const downBy = (sound, alone) => 10 * Math.log10(energy(render([{ t: 1, sound }], [{ t: 0.98, name: 'warning' }])) / alone);
  assert.ok(downBy('phase', phase) < -8, `phase ${downBy('phase', phase).toFixed(2)} dB`);
  assert.ok(Math.abs(downBy('countdown', count)) < 0.01, `countdown ${downBy('countdown', count).toFixed(2)} dB`);
});

test('a loops id keeps one track across its entries: no restart, no dip at the join', () => {
  const b = bank({ loops: { l: { bus: 'Sfx', layers: [{ sound: 'hum', db: -6, db_by: [{ param: 'v', points: [[0, -6], [1, 0]] }] }] } } });
  const loops = [{ id: 'l', t0: 0, t1: 1, params: { v: 1 } }, { id: 'l', t0: 1, t1: 2, params: { v: 1 } }];
  const sim = simulate(b, { segments: [{ rpm: 0, s: 2, params: {} }], machines: [], loops });
  assert.equal(sim.tracks.length, 1);
  const at = (s) => sim.tracks[0].db[Math.round(s * 60)];
  assert.ok(Math.abs(at(1.0) - at(0.9)) < 0.01, `${at(0.9)} to ${at(1.0)}`);
  assert.ok(Math.abs(at(1.05) - at(0.9)) < 0.01, `${at(0.9)} to ${at(1.05)}`);
});

test('a safety prompt plays at the level HudLayer asks for', () => {
  const src = fs.readFileSync(path.join(REPO, 'addons', 'wattlands', 'ui', 'hud', 'hud_layer.gd'), 'utf8');
  const body = src.slice(src.indexOf('func _play(sound: String)'));
  const asked = body.match(/sfx\.play\(sound, (-?[\d.]+)\)/);
  assert.ok(asked, 'HudLayer._play plays through WlSfx with a level');
  assert.equal(PROMPT_VOICE_DB, Number(asked[1]));
  const shared = new BankAudio(readJson(path.join(REPO, 'assets', '_shared', 'audio', 'audio.json')), null);
  const sim = simulate(bank({}), { segments: [{ rpm: 0, s: 1, params: {} }], machines: [], prompts: [{ t: 0.5, name: 'rescue' }], shared });
  assert.deepEqual(sim.voices.map((v) => [v.sound, v.bus, v.db]), [['rescue', 'Master', PROMPT_VOICE_DB]]);
});

// Parity with GameAudioKit (SPEC risk 6): each of these is a place the preview once played what the game does not.

test('parity: a machine at or under STOP_RPM closes every loop, whatever its layers say', () => {
  const b = bank({ machines: { m: { loops: [{ sound: 'hum', db: -6 }, { sound: 'hum', db: -6, when: { param: 'rpm', max: 10 } }] } } });
  for (const stop of [0, 1]) {
    const sim = simulate(b, { segments: [{ rpm: 90, s: 2, params: {} }, { rpm: stop, s: 2, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }] });
    const at = (s) => Math.round(s * 60);
    assert.ok(sim.tracks[0].db[at(1.9)] > -7, 'open while it turns');
    for (const t of sim.tracks) assert.equal(t.db[at(2.12)], -60, `rpm ${stop}: closed in 120 ms`);
    const x = mixdown(b, sim, { tail: 0 }).stems.Machines[0];
    let tail = 0;
    for (let i = Math.round(2.4 * MIX_RATE); i < x.length; i++) tail = Math.max(tail, Math.abs(x[i]));
    assert.equal(tail, 0, `rpm ${stop}: silence 400 ms after the stop`);
  }
  const justOver = simulate(b, { segments: [{ rpm: 2, s: 1, params: {} }], machines: [{ id: 'a', machine: 'm', lead: true }] });
  assert.ok(justOver.tracks[0].db[50] > -7, 'just over STOP_RPM it still plays');
});

test('parity: a closing layer holds its pitch, as the kit does', () => {
  const b = bank({ machines: { m: { loops: [{ sound: 'hum', db: -6, pitch_by: [{ param: 'x', points: [[0, 1], [1, 2]] }], when: { param: 'x', max: 0.5 } }] } } });
  const sim = simulate(b, { segments: [{ rpm: 60, s: 1, params: { x: 0 } }, { rpm: 60, s: 1, params: { x: 1 } }], machines: [{ id: 'a', machine: 'm', lead: true }] });
  const t = sim.tracks[0];
  assert.equal(t.pitch[59], 1);
  assert.equal(t.pitch[63], 1, 'closing at the old pitch');
});

test('parity: only a lead cue ducks; a non-lead cue still plays, at its trim', () => {
  const b = bank({ cues: { c: { hits: [{ sound: 'tick', db: 0 }], duck: [{ bus: 'Machines', db: -4, attack_s: 0.01, release_s: 0.35 }] } } });
  const seg = [{ rpm: 0, s: 1, params: {} }];
  const lead = simulate(b, { segments: seg, machines: [], cues: [{ t: 0.5, cue: 'c' }] });
  assert.equal(lead.ducks.length, 1);
  const other = simulate(b, { segments: seg, machines: [], cues: [{ t: 0.5, cue: 'c', lead: false }] });
  assert.equal(other.ducks.length, 0);
  assert.equal(other.voices.length, 1);
  assert.equal(other.voices[0].db, -10);
});

test('parity: a named loop with lead false plays only its `other` layers, at mix.other_db', () => {
  const b = bank({ loops: { line: { bus: 'Sfx', layers: [{ sound: 'hum', db: -6, other: true }, { sound: 'hum', db: -6 }] } }, mix: { other_db: -12 } });
  const seg = [{ rpm: 0, s: 3, params: {} }];
  const at = Math.round(1.5 * 60);
  const other = simulate(b, { segments: seg, machines: [], loops: [{ id: 'line', t0: 0.5, t1: 2, params: {}, lead: false }] });
  assert.ok(Math.abs(other.tracks[0].db[at] - -18) < 0.01, `${other.tracks[0].db[at]}`);
  assert.equal(other.tracks[1].db[at], -60);
  assert.equal(other.tracks[0].db[Math.round(2.2 * 60)], -60, 'it closes when its span ends');
  const lead = simulate(b, { segments: seg, machines: [], loops: [{ id: 'line', t0: 0.5, t1: 2, params: {} }] });
  assert.ok(Math.abs(lead.tracks[0].db[at] - -6) < 0.01);
  assert.ok(Math.abs(lead.tracks[1].db[at] - -6) < 0.01);
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

test('the panned sends: the same step and reach as AudioBuses', () => {
  const src = fs.readFileSync(path.join(REPO, 'addons', 'wattlands', 'audio', 'audio_buses.gd'), 'utf8');
  assert.equal(Number(src.match(/PAN_STEP := ([\d.]+)/)[1]), PAN_STEP);
  assert.equal(Number(src.match(/PAN_MAX := ([\d.]+)/)[1]), PAN_MAX);
});

test('panGains: AudioEffectPanner on a mono voice, to the nearest send, Sfx only', () => {
  assert.deepEqual(panGains(0), [1, 1]);
  assert.deepEqual(panGains(0.1), [1, 1]);
  assert.deepEqual(panGains(-0.5), [1.5, 0.5]);
  assert.deepEqual(panGains(5), [0.25, 1.75]);
  assert.deepEqual(panGains(-0.5, 'Machines'), [1, 1]);
});

const FLIGHT_BANK = {
  sounds: { air: { dur: 1, seed: 5, loop: true, compress: 'pcm', layers: [{ src: 'noise', color: 'white' }] } },
  cues: {
    fly: { hits: [{ sound: 'air', db: -6, pan_var: 'a', flight: { dur_var: 'f', pan_to_var: 'b', gain: [[0, 0], [1, 0]], pitch: [[0, 1], [1, 1]] } }] },
    hit: { hits: [{ sound: 'tick', db: -6, pan_var: 'a' }] },
  },
};

test('a flight runs for the time it is given, longer than its loop, and moves across the screen', () => {
  const b = bank(FLIGHT_BANK);
  const sim = simulate(b, { segments: [{ rpm: 0, s: 5, params: {} }], machines: [], cues: [{ t: 0.5, cue: 'fly', vars: { f: 3, a: -0.75, b: 0.75 } }] });
  const v = sim.voices.find((x) => x.flight);
  assert.ok(Math.abs(v.end - v.t - 3) < 1e-9);
  const x = mixdown(b, sim).stems.Sfx;
  const rms = (s, from, to) => {
    let e = 0;
    for (let i = Math.round(from * MIX_RATE); i < Math.round(to * MIX_RATE); i++) e += s[i] * s[i];
    return Math.sqrt(e);
  };
  assert.ok(rms(x[0], 0.55, 0.9) > 2 * rms(x[1], 0.55, 0.9), 'on the left at the launch');
  assert.ok(rms(x[1], 3.1, 3.45) > 2 * rms(x[0], 3.1, 3.45), 'on the right at the landing');
  assert.ok(rms(x[0], 3.55, 4.5) === 0, 'nothing after it lands');
  assert.equal(renderVoice(b, v).length, Math.ceil(3 * MIX_RATE));
});

test('a plain hit stays where it is panned', () => {
  const b = bank(FLIGHT_BANK);
  const sim = simulate(b, { segments: [{ rpm: 0, s: 1, params: {} }], machines: [], cues: [{ t: 0.1, cue: 'hit', vars: { a: 0.5 } }] });
  const x = mixdown(b, sim).stems.Sfx;
  const peak = (s) => s.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
  assert.ok(Math.abs(peak(x[1]) / peak(x[0]) - 3) < 0.01);
});
