// Siege's bank against SPEC_AUDIO 4.3 and 5: the sound list with its variants, the stroke fractions
// (the walkers' frames and the art's phases), and the fatigue rule, which the scorecard doesn't read.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { loadBank, validateBank } from '../../../../tools/audio/lib/bank.mjs';
import { biquad, rbj } from '../../../../tools/audio/lib/dsp.mjs';
import { renderSound } from '../../../../tools/audio/lib/recipe.mjs';
import { BankAudio } from '../../../../tools/audio/lib/offline_mix.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..');
const BANK = path.join(REPO, 'assets', 'siege', 'audio', 'audio.json');
const doc = loadBank(BANK);

const VARIANTS = {
  pawl_click: 3,
  wheel_creak: 5,
  tread_step: 4,
  mine_pick: 3,
  ballista_twang: 3,
  scorpion_snap: 3,
  stone_impact: 3,
  arrow_whistle: 6,
  gate_hit: 4,
  hooves: 4,
  kill_thud: 4,
  crow: 3,
};
const SINGLES = [
  'timber_groan', 'junction_clatter', 'pump_stroke', 'tar_bubble', 'tar_pour', 'tar_hiss', 'bolt_whoosh', 'onager_release',
  'stone_whoosh', 'arrow_release', 'arrow_patter', 'horn_wave', 'horn_push', 'horn_rush', 'wave_end_bell', 'gate_crash',
  'gate_restored', 'ram_thud', 'tower_creak', 'reach_alarm', 'lever_route', 'coin_clink', 'hammer_buy', 'overdrive_on',
  'overdrive_off', 'overdrive_no', 'wind_hill_lo', 'wind_hill_hi', 'crowd_far', 'banner_flap', 'lark',
];

test('the bank is valid', () => {
  assert.deepEqual(validateBank(doc), []);
});

test('every sound of the list is there, with its variants', () => {
  for (const [id, n] of Object.entries(VARIANTS)) assert.equal(doc.sounds[id]?.variants, n, id);
  for (const id of SINGLES) assert.ok(doc.sounds[id], id);
});

test('the wheel strokes fall where the walkers plant their feet', () => {
  const at = Object.fromEntries(doc.machines.treadwheel.events.map((e) => [e.sound, e.at]));
  assert.deepEqual(at.pawl_click, [0, 0.5]);
  assert.deepEqual(at.tread_step, [0, 0.5]);
  assert.deepEqual(at.wheel_creak, [0.25]);
  const step = doc.machines.treadwheel.events.find((e) => e.sound === 'tread_step');
  assert.equal(step.lead_only, true);
});

test('the mine picks twice a cycle, the pump strokes once', () => {
  assert.deepEqual(doc.machines.mine.events[0].at, [0, 0.5]);
  assert.deepEqual(doc.machines.pump.events[0].at, [0]);
});

test('other riders hear only the groan of a wheel', () => {
  const others = doc.machines.treadwheel.loops.filter((l) => l.other === true);
  assert.deepEqual(others.map((l) => l.sound), ['timber_groan']);
});

test('a volley is three staggered whistles and a delayed patter', () => {
  const hits = doc.cues.shot_arrow.hits;
  assert.deepEqual(hits.filter((h) => h.sound === 'arrow_whistle').map((h) => h.delay_s ?? 0), [0, 0.07, 0.15]);
  assert.equal(hits.find((h) => h.sound === 'arrow_patter').delay_var, 'flight_s');
  assert.equal(doc.cues.shot_stone.hits.find((h) => h.sound === 'stone_impact').delay_var, 'flight_s');
});

test('a breach ducks everything but UI and Master; a stone ducks the machines', () => {
  assert.deepEqual(doc.cues.breach.duck.map((d) => d.bus).sort(), ['Ambience', 'Machines', 'Sfx']);
  assert.ok(doc.cues.breach.duck.every((d) => d.db <= -6 && d.db >= -9));
  assert.deepEqual(doc.cues.shot_stone.duck.map((d) => [d.bus, d.db]), [['Machines', -3]]);
});

test('tonal fanfares sit on C major pentatonic', () => {
  const pentatonic = (hz) => {
    const midi = 69 + 12 * Math.log2(hz / 440);
    return [0, 2, 4, 7, 9].includes(((Math.round(midi) % 12) + 12) % 12) && Math.abs(midi - Math.round(midi)) < 0.1;
  };
  const longest = (id, i = 0) => doc.sounds[id].layers[i].points;
  // Each horn's held note is its second point: the first is the lip coming up to it.
  assert.ok(pentatonic(longest('horn_wave')[1][1]), 'horn_wave');
  assert.ok(pentatonic(longest('horn_push', 0)[1][1]) && pentatonic(longest('horn_push', 1)[1][1]), 'horn_push');
  assert.ok(pentatonic(longest('horn_rush', 0)[1][1]) && pentatonic(longest('horn_rush', 2)[1][1]), 'horn_rush');
  assert.ok(pentatonic(doc.sounds.wave_end_bell.layers[0].f[0]), 'wave_end_bell');
  assert.ok(pentatonic(doc.sounds.reach_alarm.layers[0].f[0]), 'reach_alarm');
});

function energyDb(x, hpHz, rate) {
  let y = x;
  if (hpHz > 0) for (let i = 0; i < 2; i++) y = biquad(y, rbj('hp', hpHz, Math.SQRT1_2, rate));
  let e = 0;
  for (const v of y) e += v * v;
  return 10 * Math.log10(e + 1e-30);
}

test('fatigue: nothing locked above 2 kHz exceeds -16 dB of the main stroke', () => {
  const bank = new BankAudio(doc, path.dirname(BANK));
  const body = (id, k) => {
    const f = bank.file(id, k);
    return { x: Float64Array.from(f.data[0].subarray(f.preroll)), rate: f.rate };
  };
  const events = doc.machines.treadwheel.events;
  const main = events.find((e) => e.sound === 'pawl_click');
  const m = body('pawl_click', 0);
  const ref = energyDb(m.x, 0, m.rate) + main.db;
  for (const machine of Object.values(doc.machines)) {
    for (const ev of machine.events) {
      const n = doc.sounds[ev.sound].variants ?? 1;
      for (let k = 0; k < n; k++) {
        const s = body(ev.sound, k);
        const rel = energyDb(s.x, 2000, s.rate) + ev.db - ref;
        assert.ok(rel <= -16, `${ev.sound} variant ${k}: ${rel.toFixed(1)} dB`);
      }
    }
  }
});

test('each stroke rings out inside what the dead stop allows', () => {
  for (const machine of Object.values(doc.machines)) {
    for (const ev of machine.events) {
      const s = doc.sounds[ev.sound];
      for (const v of [{}, ...(s.per_variant ?? [])]) {
        assert.ok((v.dur ?? s.dur) <= 0.45, `${ev.sound} ${v.dur ?? s.dur} s`);
      }
    }
  }
});

test('the recipes render as the files on disk say', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(path.dirname(BANK), 'audio_manifest.json'), 'utf8'));
  const r = renderSound('pawl_click', doc.sounds.pawl_click, 1, { game: 'siege' });
  assert.equal(manifest.pawl_click_2.frames, r.frames);
  assert.equal(manifest.pawl_click_2.locked, true);
  assert.equal(manifest.timber_groan.loop, true);
});
