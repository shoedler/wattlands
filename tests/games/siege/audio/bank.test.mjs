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
import { momentaryMaxLufs } from '../../../../tools/audio/lib/lufs.mjs';
import { BankAudio, MIX_RATE, mixdown, simulate } from '../../../../tools/audio/lib/offline_mix.mjs';
import { previewScenario } from '../../../../tools/audio/lib/score.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..');
const BANK = path.join(REPO, 'assets', 'siege', 'audio', 'audio.json');
const doc = loadBank(BANK);

const VARIANTS = {
  pawl_click: 3,
  tread_step: 4,
  axle_knock: 2,
  mine_pick: 3,
  ballista_twang: 2,
  scorpion_snap: 3,
  stone_impact: 2,
  arrow_swarm: 3,
  bolt_hiss: 3,
  arrow_release: 2,
  arrow_dirt: 2,
  bolt_dirt: 2,
  bolt_wood: 2,
  hit_flesh: 3,
  hit_wood: 3,
  hit_shield: 3,
  gate_hit: 4,
  hooves: 4,
  kill_thud: 4,
  crow: 3,
};
const SINGLES = [
  'wheel_rumble', 'wheel_rumble_far', 'wheel_load', 'junction_clatter', 'pump_stroke', 'tar_bubble', 'tar_pour', 'tar_hiss',
  'onager_release', 'stone_tumble', 'stone_wood', 'stone_splash', 'arrow_water', 'horn_wave', 'horn_push', 'horn_rush',
  'wave_end_bell', 'gate_crash', 'gate_restored', 'ram_thud', 'tower_creak', 'reach_alarm', 'lever_route', 'coin_clink',
  'hammer_buy', 'overdrive_on', 'overdrive_off', 'overdrive_no', 'wind_hill_lo', 'wind_hill_hi', 'crowd_far', 'banner_flap', 'lark',
];
const WEAPONS = ['bolt', 'stone', 'arrow', 'scorpion'];
const SURFACES = ['dirt', 'water', 'flesh', 'wood', 'shield'];

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
  assert.deepEqual(at.axle_knock, [0.75]);
  const step = doc.machines.treadwheel.events.find((e) => e.sound === 'tread_step');
  assert.equal(step.lead_only, true);
});

test('the mine picks twice a cycle, the pump strokes once', () => {
  assert.deepEqual(doc.machines.mine.events[0].at, [0, 0.5]);
  assert.deepEqual(doc.machines.pump.events[0].at, [0]);
});

test('other riders hear only a far rumble of a wheel, and yours is not that sound', () => {
  const others = doc.machines.treadwheel.loops.filter((l) => l.other === true);
  assert.deepEqual(others.map((l) => l.sound), ['wheel_rumble_far']);
  assert.ok(doc.machines.treadwheel.loops.every((l) => l.when?.param === 'far'), 'each layer says whose it is');
  assert.ok(doc.preview.others.find((o) => o.machine === 'treadwheel').params.far === 1, 'the preview rides another rider so');
});

test('nothing of the wheel follows the cadence in pitch: two riders a little apart would flange', () => {
  for (const l of doc.machines.treadwheel.loops) assert.equal(l.pitch_by, undefined, l.sound);
  assert.equal(doc.loops.junction_clatter.layers[0].pitch_by, undefined);
});

test('the wheel holds no tone: its strokes and loops have no oscillator, chirp or drive', () => {
  const sounds = [...doc.machines.treadwheel.events.map((e) => e.sound), ...doc.machines.treadwheel.loops.map((l) => l.sound), 'junction_clatter', 'tower_creak'];
  for (const id of sounds) {
    for (const l of doc.sounds[id].layers) {
      assert.ok(['noise', 'modal', 'grains'].includes(l.src), `${id}: ${l.src}`);
      for (const fx of l.fx ?? []) assert.equal(fx.drive, undefined, id);
    }
  }
});

test('every weapon has a release and a flight that follows the shot, on its side of the screen', () => {
  for (const w of WEAPONS) {
    const hits = doc.cues[`shot_${w}`].hits;
    const flight = hits.find((h) => h.flight);
    assert.ok(flight, `${w}: a flight`);
    assert.equal(doc.sounds[flight.sound].loop, true, `${w}: its flight is a loop`);
    assert.equal(flight.flight.dur_var, 'flight_s');
    assert.equal(flight.pan_var, 'pan0');
    assert.equal(flight.flight.pan_to_var, 'pan1');
    assert.ok(hits.some((h) => !h.flight && (h.delay_s ?? 0) === 0), `${w}: a release`);
  }
});

test('the volley flights never overlap one noise: three variants, one a volley', () => {
  assert.equal(doc.sounds.arrow_swarm.variants, 3);
  assert.equal(doc.sounds.bolt_hiss.variants, 3);
});

test('every weapon has an impact for every surface', () => {
  for (const w of WEAPONS) for (const s of SURFACES) assert.ok(doc.cues[`hit_${w}_${s}`]?.hits?.length > 0, `${w} ${s}`);
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

test('a flight sound is at most this much of the wheels: a game-long hiss is the next complaint', () => {
  for (const w of WEAPONS) {
    const flight = doc.cues[`shot_${w}`].hits.find((h) => h.flight);
    assert.ok(flight.db <= -5, `${w}: ${flight.db}`);
  }
});

test('D5 sees the worst: a volley sits in the prompt window, and the preview shows the organ at its rate', () => {
  const events = doc.preview.events;
  const volley = events.filter((e) => e.cue === 'shot_arrow').map((e) => e.t).sort((a, b) => a - b);
  assert.ok(events.some((e) => e.cue === 'shot_arrow' && e.t >= 30 && e.t < 30.6), 'a volley in 30.0..30.6 s');
  const run = volley.filter((t) => t >= 25.5 && t <= 34.5);
  assert.equal(run.length, 7);
  run.slice(1).forEach((t, i) => assert.equal(t - run[i], 1.5));
});

test('the preview ends the junction at the stop, as the adapter does', () => {
  const stop = doc.preview.segments.filter((s) => s.rpm > 0).reduce((a, s) => a + s.s, 0);
  assert.equal(doc.preview.loops.find((l) => l.id === 'junction_clatter').t1, stop);
});

test('a safety prompt clears +6 LU over each horn, a volley and a docking tower at 110 rpm', () => {
  const dir = path.dirname(BANK);
  const bank = new BankAudio(doc, dir);
  const sharedPath = path.join(REPO, 'assets', '_shared', 'audio', 'audio.json');
  const shared = new BankAudio(loadBank(sharedPath), path.dirname(sharedPath));
  const base = previewScenario(doc, {});
  const quiet = (base.cues ?? []).filter((c) => c.t < 44);
  const at = 50;
  const vars = { flight_s: 3.5, p: 1, pan0: 0.1, pan1: -0.5, lvl: 0 };
  for (const cue of ['rush', 'push', 'wave_start', 'overdrive_on', 'shot_arrow', 'dock']) {
    for (const after of [0.05, 0.2, 0.4]) {
      const t = at + after;
      const sim = simulate(bank, { ...base, cues: [...quiet, { t: at, cue, vars }], duration: t + 0.8, prompts: [{ t, name: 'warning' }], shared });
      const pm = mixdown(bank, sim, { shared, tail: 0 });
      const from = Math.round(t * MIX_RATE);
      const to = Math.round((t + 0.6) * MIX_RATE);
      const slice = (st) => [st[0].subarray(from, to), st[1].subarray(from, to)];
      const others = [new Float64Array(to - from), new Float64Array(to - from)];
      for (const bus of ['Machines', 'Ambience', 'Sfx', 'UI']) {
        const b = slice(pm.stems[bus]);
        for (let i = 0; i < to - from; i++) {
          others[0][i] += b[0][i];
          others[1][i] += b[1][i];
        }
      }
      const lu = momentaryMaxLufs(slice(pm.stems.Master), MIX_RATE) - momentaryMaxLufs(others, MIX_RATE);
      assert.ok(lu >= 6, `${cue}, prompt ${after} s in: +${lu.toFixed(2)} LU`);
    }
  }
});

test('the wheel stops rising under 60 rpm and above 340 W, where a prompt has nothing to spare', () => {
  const at = (points, x) => {
    if (x <= points[0][0]) return points[0][1];
    for (let i = 1; i < points.length; i++) {
      if (x <= points[i][0]) return points[i - 1][1] + ((points[i][1] - points[i - 1][1]) * (x - points[i - 1][0])) / (points[i][0] - points[i - 1][0]);
    }
    return points[points.length - 1][1];
  };
  const wheel = doc.machines.treadwheel;
  for (const layer of [...wheel.events, ...wheel.loops]) {
    for (const by of layer.db_by ?? []) {
      if (by.param === 'rpm') assert.equal(at(by.points, 40), at(by.points, 60), `${layer.sound}: rpm under 60`);
      if (by.param === 'p_eff') assert.equal(at(by.points, 500), at(by.points, 340), `${layer.sound}: p_eff above 340`);
    }
  }
});

// The prompt over what is running, at quarter-revolution steps across two revolutions: a stroke landing
// in the prompt's own window is what reads worst, and that depends on the phase.
function promptMargins(bank, shared, scenario, t0, rpm, name) {
  const out = [];
  for (let k = 0; k < 8; k++) {
    const t = t0 + (k * 60) / rpm / 4;
    const sim = simulate(bank, { ...scenario, duration: t + 0.8, prompts: [{ t, name }], shared });
    const pm = mixdown(bank, sim, { shared, tail: 0 });
    const from = Math.round(t * MIX_RATE);
    const to = Math.round((t + 0.6) * MIX_RATE);
    const slice = (st) => [st[0].subarray(from, to), st[1].subarray(from, to)];
    const others = [new Float64Array(to - from), new Float64Array(to - from)];
    for (const bus of ['Machines', 'Ambience', 'Sfx', 'UI']) {
      const b = slice(pm.stems[bus]);
      for (let i = 0; i < to - from; i++) {
        others[0][i] += b[0][i];
        others[1][i] += b[1][i];
      }
    }
    out.push(momentaryMaxLufs(slice(pm.stems.Master), MIX_RATE) - momentaryMaxLufs(others, MIX_RATE));
  }
  return out;
}

function ridingScenario(base, rpm, p, others) {
  const riders = [];
  for (let i = 0; i < others; i++) {
    riders.push({ id: `o${i}`, machine: 'treadwheel', lead: false, rpm_scale: 0.97 - i * 0.02, params: { p_eff: p, walkers: 2, far: 1 } });
  }
  return {
    ...base,
    cues: [],
    machines: [
      { id: 'lead', machine: 'treadwheel', lead: true },
      ...riders,
      { id: 'mine', machine: 'mine', lead: true, rpm_by: { param: 'm', points: [[0, 0], [1, 54]] } },
      { id: 'pump', machine: 'pump', lead: true, rpm_by: { param: 'tar_m', points: [[0, 0], [1, 30]] } },
    ],
    loops: [
      { id: 'junction_clatter', t0: 0, t1: 30, params: { team_w: p * (1 + others) } },
      { id: 'tar_bubble', t0: 0, t1: 30, params: { m: 0.8 } },
      { id: 'tar_pour', t0: 0, t1: 30, params: {} },
    ],
    segments: [{ rpm, s: 30, params: { p_eff: p, walkers: 2, gust: 0.5, m: 0.9, tar_m: 0.8 } }],
  };
}

const PROMPT_CASES = [
  // The preview's own slow and fast segments, nothing landing.
  { label: 'nothing landing, 60 rpm 220 W', rpm: 60, t0: 8, name: 'warning', scenario: (base) => ({ ...base, cues: [] }) },
  { label: 'nothing landing, 110 rpm 340 W', rpm: 110, t0: 50, name: 'warning', scenario: (base) => ({ ...base, cues: [] }) },
  // The brief tolerates 70-79 rpm with a small arrow.
  { label: '75 rpm 280 W with 3 others', rpm: 75, t0: 8, name: 'warning', scenario: (base) => ridingScenario(base, 75, 280, 3) },
  // The cadence the rescue prompt fires at.
  { label: 'rescue at 44 rpm 250 W', rpm: 44, t0: 8, name: 'rescue', scenario: (base) => ridingScenario(base, 44, 250, 0) },
];

for (const c of PROMPT_CASES) {
  test(`a safety prompt clears +6 LU at every quarter revolution: ${c.label}`, () => {
    const bank = new BankAudio(doc, path.dirname(BANK));
    const sharedPath = path.join(REPO, 'assets', '_shared', 'audio', 'audio.json');
    const shared = new BankAudio(loadBank(sharedPath), path.dirname(sharedPath));
    const margins = promptMargins(bank, shared, c.scenario(previewScenario(doc, {})), c.t0, c.rpm, c.name);
    const low = Math.min(...margins);
    assert.ok(low >= 6, `min +${low.toFixed(2)} LU: ${margins.map((m) => m.toFixed(2)).join(' ')}`);
  });
}

test('the recipes render as the files on disk say', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(path.dirname(BANK), 'audio_manifest.json'), 'utf8'));
  const r = renderSound('pawl_click', doc.sounds.pawl_click, 1, { game: 'siege' });
  assert.equal(manifest.pawl_click_2.frames, r.frames);
  assert.equal(manifest.pawl_click_2.locked, true);
  assert.equal(manifest.wheel_rumble.loop, true);
});
