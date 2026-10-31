// Turbo Reel's bank against SPEC_AUDIO's sound list and mix rules. tools/audio's own suites hold it to
// the family and the scorecard; these are the rules particular to this game.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { loadBank, renderFile, soundFiles } from '../../../../tools/audio/lib/bank.mjs';
import { bandShareDb } from '../../../../tools/audio/lib/dsp.mjs';
import { integratedLufs, momentaryMaxLufs } from '../../../../tools/audio/lib/lufs.mjs';
import * as offlineMix from '../../../../tools/audio/lib/offline_mix.mjs';
import { previewScenario } from '../../../../tools/audio/lib/score.mjs';
import { decodeWav, deinterleave } from '../../../../tools/audio/lib/wav.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..');
const BANK = path.join(REPO, 'assets', 'fishing', 'audio', 'audio.json');
const doc = loadBank(BANK);
const machine = doc.machines.drivetrain;
const { BankAudio, MIX_RATE, mixdown, simulate } = offlineMix;
const bank = new BankAudio(doc, path.dirname(BANK));
const SHARED = path.join(REPO, 'assets', '_shared', 'audio');
const shared = new BankAudio(loadBank(path.join(SHARED, 'audio.json')), SHARED);
// D5's row is +6 LU. WlSfx's duck on main (-6, -6, -4) cannot reach it at this game's loud moments, so each floor below pins
// what that duck gives and rises by itself to +6 when the deeper duck lands: offline_mix then exports SAFETY_DUCK (see the ADR).
const floorLu = (today) => (offlineMix.SAFETY_DUCK ? 6 : today);

const VARIANTS = { gear_tick: 3, outboard_chug: 3, reel_ratchet: 3, line_creak: 4, hull_slap: 5, gull: 4 };
const LIST = [
  'crank_knock', 'outboard_body', 'prop_churn', 'winch_gear', 'line_tension', 'rod_groan', 'drag_scream', 'plane_wash',
  'splash_small', 'splash_big', 'plop', 'reel_clunk', 'bite_bell', 'zip', 'snap_twang', 'turn_clunk',
  'fanfare_1', 'fanfare_2', 'fanfare_3', 'horn_short', 'horn_long', 'bell_double',
  'waves_lo', 'waves_wash', 'wind_sea', 'harbour', 'buoy_bell', 'rigging_tick',
];

function eventOf(sound) {
  return machine.events.find((e) => e.sound === sound);
}

function layerOf(sound) {
  return machine.loops.find((l) => l.sound === sound);
}

function samples(id, variant = 0) {
  const f = soundFiles(id, doc.sounds[id])[variant];
  const r = renderFile(doc, f);
  const w = decodeWav(r.wav);
  return { x: deinterleave(w.samples, w.ch)[0], rate: w.rate, preroll: r.entry.preroll };
}

function rms(x) {
  let s = 0;
  for (const v of x) s += v * v;
  return s / x.length;
}

function maxDb(ev) {
  let db = ev.db;
  for (const c of ev.db_by ?? []) db += Math.max(...c.points.map((p) => p[1]));
  return db;
}

test('the sound list: every sound of SPEC_AUDIO 4.2, with its variants', () => {
  for (const id of LIST) assert.ok(doc.sounds[id], id);
  for (const [id, n] of Object.entries(VARIANTS)) assert.equal(doc.sounds[id].variants, n, id);
  assert.equal(doc.sounds.snap_twang.layers.some((l) => l.src === 'pluck'), true, 'snap_twang is a pluck');
});

test('the drivetrain strokes sit where the spec and the art put them', () => {
  assert.deepEqual(eventOf('gear_tick').at, [0]);
  assert.deepEqual(eventOf('crank_knock').at, [0.5]);
  assert.equal(eventOf('crank_knock').lead_only, true);
  assert.deepEqual(eventOf('outboard_chug').at, [0, 0.5]);
  assert.deepEqual(eventOf('outboard_chug').when, { param: 'prop', min: 0.05 });
  assert.deepEqual(eventOf('reel_ratchet').at, [0, 0.1667, 0.3333, 0.5, 0.6667, 0.8333]);
  assert.deepEqual(eventOf('line_creak').at, [0.25, 0.75]);
  assert.deepEqual(eventOf('line_creak').when, { param: 'tension', min: 0.25 });
});

test('the loops open as the spec says, and rise with what drives them', () => {
  const body = layerOf('outboard_body');
  assert.deepEqual(body.pitch_by, [{ param: 'rpm', ratio: 90 }]);
  assert.deepEqual(layerOf('winch_gear').when, { param: 'fishing', min: 0.5 });
  assert.deepEqual(layerOf('winch_gear').pitch_by, [{ param: 'rpm', ratio: 90 }]);
  const wire = layerOf('line_tension');
  assert.deepEqual(wire.when, { param: 'tension', min: 0.35 });
  assert.equal(wire.slew_s, 0.2);
  assert.equal(wire.other ?? false, false, 'the line tension is lead only');
  assert.deepEqual(wire.pitch_by[0].points.map((p) => p[1]), [0.8, 1.5]);
  assert.deepEqual(layerOf('rod_groan').when, { param: 'tension', min: 0.6 });
  assert.equal(doc.loops.drag_scream.layers[0].sound, 'drag_scream');
  assert.equal(doc.loops.drag_scream.bus, 'Sfx');
  // Fishing: 3 others x at most 2 layers + lead at most 6 + bed 4 + 2 named loops stay in the pool.
  assert.ok(machine.loops.length <= 6);
  assert.ok(machine.loops.filter((l) => l.other).length <= 3);
  assert.ok(machine.loops.length + 3 * 2 + doc.beds.open_sea.layers.length + 2 <= doc.mix.max_loop_players);
});

test('a locked stroke above 2 kHz stays 16 dB under the main stroke: an hour of ticking is a texture', () => {
  const chug = eventOf('outboard_chug');
  const main = samples('outboard_chug');
  const mainPower = 10 * Math.log10(rms(main.x.subarray(main.preroll))) + maxDb(chug);
  const seen = [];
  for (const ev of machine.events) {
    if (ev.sound === 'outboard_chug') continue;
    const s = samples(ev.sound);
    const body = s.x.subarray(s.preroll);
    const whole = 10 * Math.log10(rms(body));
    const high = whole + bandShareDb(body, s.rate, 2000, 11026);
    const over = high + maxDb(ev) - mainPower;
    seen.push(`${ev.sound} ${over.toFixed(1)}`);
    assert.ok(over <= -16, `${ev.sound}: ${over.toFixed(1)} dB against the main stroke`);
  }
  assert.ok(seen.length >= 5, seen.join(', '));
});

test('the bed has its gulls near the dock, a far one at sea, and a hull slap per speed band', () => {
  const spots = doc.beds.open_sea.spots;
  const near = spots.find((s) => s.sound === 'gull');
  assert.deepEqual(near.when, { param: 'near_dock', min: 0.03 });
  assert.equal(near.db_by[0].param, 'near_dock');
  const far = spots.find((s) => s.sound === 'gull_far');
  assert.equal(far.when, undefined);
  assert.ok(far.gap_s[0] > near.gap_s[1], 'the far ones are rare');
  const slaps = spots.filter((s) => s.sound === 'hull_slap');
  assert.equal(slaps.length, 3);
  assert.ok(slaps[0].gap_s[0] > slaps[1].gap_s[0] && slaps[1].gap_s[0] > slaps[2].gap_s[0], 'faster with speed');
  const buoy = spots.find((s) => s.sound === 'buoy_bell');
  assert.deepEqual(buoy.gap_s, [40, 90]);
  assert.equal(spots.find((s) => s.sound === 'rigging_tick').when.param, 'near_dock');
  // Loop lengths co-prime in tenths of a second: the bed takes minutes to repeat. The second wash is the same file at another pitch.
  const layers = [...new Set(doc.beds.open_sea.layers.map((l) => l.sound))].map((id) => Math.round(doc.sounds[id].dur * 10));
  const gcd = (a, b) => (b === 0 ? a : gcd(b, a % b));
  for (let i = 0; i < layers.length; i++) for (let j = i + 1; j < layers.length; j++) assert.ok(gcd(layers[i], layers[j]) <= 10, `${layers}`);
});

test('the cues keep their spec delays and ducks', () => {
  const fanfare = doc.cues.landed.hits.filter((h) => h.sound.startsWith('fanfare')).map((h) => h.delay_s ?? 0);
  assert.deepEqual(fanfare, [0, 0.16, 0.32]);
  assert.deepEqual(doc.cues.snap.duck.map((d) => [d.bus, d.db]), [['Machines', -4]]);
  assert.equal(doc.cues.run.hits[0].pitch, 1.3);
  for (const id of ['landed', 'hookup', 'jump', 'thrown']) {
    assert.ok(doc.cues[id].hits.some((h) => h.sound.startsWith('splash_')), `${id} splashes`);
  }
});

test('the fanfare and the bells sit on C major pentatonic', () => {
  const NOTES = [523.25, 587.33, 659.25, 783.99, 880];
  const onScale = (hz) => [0.25, 0.5, 1, 2, 4].some((o) => NOTES.some((n) => Math.abs(hz * o - n) < 0.5));
  for (const id of ['fanfare_1', 'fanfare_2', 'fanfare_3', 'fanfare_4', 'bite_bell', 'bell_double']) {
    for (const l of doc.sounds[id].layers) assert.ok(onScale(l.f), `${id}: ${l.f} Hz`);
  }
});

test('routine cues carry the distance of the boat they come from; a catch and the bells do not', () => {
  for (const id of ['cast', 'hookup', 'thrown', 'run', 'jump', 'jump_1', 'jump_3', 'snap', 'turn']) {
    for (const h of doc.cues[id].hits) assert.equal(h.db_var, 'far_db', `${id}: ${h.sound}`);
  }
  for (const id of ['bite', 'double_hookup', 'landed', 'landed_trophy', 'time_up', 'trip_over', 'clutch']) {
    for (const h of doc.cues[id].hits) assert.equal(h.db_var, undefined, `${id}: ${h.sound}`);
  }
});

test('nothing in the machine repeats on a short cycle: the putt, the body and the winch', () => {
  assert.equal(eventOf('outboard_chug').pitch_table.length, 7, 'a 21 revolution cycle against the 3 takes');
  for (const [id, cycles] of [['outboard_body', [87, 130]], ['winch_gear', [187]]]) {
    const hz = doc.sounds[id].layers.filter((l) => typeof l.f === 'number').map((l) => l.f);
    assert.equal(hz.length, cycles.length, id);
    hz.forEach((f, i) => assert.ok(Math.abs(f * doc.sounds[id].dur - cycles[i]) < 1e-3, `${id}: ${f} Hz stays whole cycles`));
  }
  const pitches = doc.sounds.line_creak.per_variant.map((v) => v.pitch);
  assert.ok(Math.log2(Math.max(...pitches) / Math.min(...pitches)) * 12 < 2.5, 'the creak is no 4-note riff');
});

test('with nothing on the line the sea leads over the crank', () => {
  const seg = { rpm: 70, s: 40, params: { near: 1, fishing: 1, tension: 0.15, speed: 0.6, near_dock: 0, prop: 0, load: 0.5 } };
  const sim = simulate(bank, { segments: [seg], machines: [{ id: 'lead', machine: 'drivetrain', lead: true }], bed: 'open_sea', bed_params: {}, seed: 8 });
  const m = mixdown(bank, sim, { tail: 0 });
  assert.ok(integratedLufs(m.stems.Machines, MIX_RATE) <= integratedLufs(m.stems.Ambience, MIX_RATE), 'machines at or under the bed');
});

/** D5's own metric: `warning` over everything else, ducks counted, in a 600 ms window from each time. */
function promptMargins(scenario, ts) {
  const sim = simulate(bank, { ...scenario, prompts: ts.map((t) => ({ t, name: 'warning' })), shared });
  const pm = mixdown(bank, sim, { shared });
  return ts.map((t) => {
    const from = Math.round(t * MIX_RATE);
    const to = Math.round((t + 0.6) * MIX_RATE);
    const others = [new Float64Array(to - from), new Float64Array(to - from)];
    for (const bus of ['Machines', 'Ambience', 'Sfx', 'UI']) {
      for (let c = 0; c < 2; c++) {
        const src = pm.stems[bus][c];
        for (let i = from; i < to; i++) others[c][i - from] += src[i];
      }
    }
    const master = [pm.stems.Master[0].subarray(from, to), pm.stems.Master[1].subarray(from, to)];
    return momentaryMaxLufs(master, MIX_RATE) - momentaryMaxLufs(others, MIX_RATE);
  });
}

const LEAD = { id: 'lead', machine: 'drivetrain', lead: true };
const DRIVE = { near: 1, prop: 1.5, load: 1, fishing: 0, tension: 0, reel: 0 };
const bots = (params) => Array.from({ length: 7 }, (_, i) => ({ id: `b${i}`, machine: 'drivetrain', lead: false, rpm_scale: 0.88 + (0.24 * i) / 6, params }));

test('a safety prompt clears steady riding, alone and among seven boats', () => {
  const ts = [2, 6, 10, 14, 18, 22];
  for (const [rpm, load, speed] of [[60, 0.45, 3.2], [90, 1, 12], [110, 1.15, 15], [110, 1.4, 16], [140, 1.4, 16]]) {
    const seg = { rpm, s: 24, params: { ...DRIVE, load, speed, near_dock: 0 } };
    for (const [who, machines, today] of [['alone', [LEAD], 4.7], ['with 7', [LEAD, ...bots(DRIVE)], 3.7]]) {
      const worst = Math.min(...promptMargins({ segments: [seg], machines, bed: 'open_sea', bed_params: {}, seed: 8 }, ts));
      assert.ok(worst >= floorLu(today), `${rpm} rpm, load ${load}, ${who}: ${worst.toFixed(2)} LU`);
    }
  }
});

test('a safety prompt clears every cue, on it and around it', () => {
  const names = Object.keys(doc.cues);
  const cues = names.map((cue, i) => ({ t: 3 + i * 5, cue, vars: {} }));
  const seg = { rpm: 70, s: 3 + names.length * 5, params: { near: 1, fishing: 1, tension: 0.15, speed: 0.6, near_dock: 0, prop: 0, load: 0.5 } };
  const scenario = { segments: [seg], machines: [LEAD], bed: 'open_sea', bed_params: {}, cues, seed: 8 };
  for (const off of [-0.4, -0.2, 0, 0.16, 0.32, 0.48]) {
    promptMargins(scenario, names.map((_, i) => 3 + i * 5 + off)).forEach((d, i) => {
      assert.ok(d >= floorLu(1.2), `${names[i]}, prompt at ${off} s: ${d.toFixed(2)} LU`);
    });
  }
});

test('a safety prompt clears the preview at its worst moments, not only at the midpoint', () => {
  const scenario = previewScenario(doc);
  for (const off of [0, 1.5, 3]) {
    const ts = [];
    for (let t = 1 + off; t < 107; t += 4) ts.push(t);
    promptMargins(scenario, ts).forEach((d, i) => assert.ok(d >= floorLu(1.6), `at ${ts[i]} s: ${d.toFixed(2)} LU`));
  }
});

test('the audio test folder is not imported as assets: only assets/ holds WAV', () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  assert.equal(fs.readdirSync(here).some((f) => f.endsWith('.wav')), false);
});
