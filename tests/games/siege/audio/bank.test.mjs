// Siege's bank against SPEC_AUDIO 4.3 and 5: the sound list with its variants, the stroke fractions
// (the walkers' frames and the art's phases), and the fatigue rule, which the scorecard doesn't read.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { loadBank, validateBank } from '../../../../tools/audio/lib/bank.mjs';
import { bandFilter, biquad, rbj } from '../../../../tools/audio/lib/dsp.mjs';
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
  arrow_flesh: 4,
  arrow_wood: 4,
  arrow_shield: 3,
  arrow_dirt: 4,
  arrow_water: 3,
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
  'onager_release', 'stone_tumble', 'stone_wood', 'stone_splash', 'horn_wave', 'horn_push', 'horn_rush',
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

/** A train of one contour every `gap` s over a `flight` s flight: how far the sum of their power moves, in dB. */
function ripple(points, gap, flight = 4) {
  const at = (u) => {
    if (u < 0 || u > 1) return -200;
    for (let i = 1; i < points.length; i++) {
      if (u <= points[i][0]) return points[i - 1][1] + ((points[i][1] - points[i - 1][1]) * (u - points[i - 1][0])) / (points[i][0] - points[i - 1][0]);
    }
    return points[points.length - 1][1];
  };
  let lo = Infinity;
  let hi = -Infinity;
  for (let t = 0; t < gap; t += 0.01) {
    let sum = 0;
    for (let k = 0; k < 12; k++) sum += 10 ** (at((t + k * gap) / flight) / 10);
    const db = 10 * Math.log10(sum);
    lo = Math.min(lo, db);
    hi = Math.max(hi, db);
  }
  return hi - lo;
}

test('volleys read as separate volleys at the organ\'s real rate: the flight is a pass, not a bed', () => {
  const gain = doc.cues.shot_arrow.hits.find((h) => h.flight).flight.gain;
  assert.ok(ripple(gain, 0.87) >= 3.5, `0.87 s: ${ripple(gain, 0.87).toFixed(1)} dB`);
  assert.ok(ripple(gain, 1.5) >= 9, `1.5 s: ${ripple(gain, 1.5).toFixed(1)} dB`);
  assert.ok(ripple(gain, 2.3) >= 14, `2.3 s: ${ripple(gain, 2.3).toFixed(1)} dB`);
});

test('every hit cue is on the card, and another rider\'s shots are under your own without dropping out', () => {
  const listed = Object.values(doc.preview.checks.projectiles.surfaces).flat().sort();
  const hits = Object.keys(doc.cues).filter((c) => c.startsWith('hit_')).sort();
  assert.deepEqual(listed, hits);
  for (const c of [...hits, 'shot_bolt', 'shot_stone', 'shot_arrow', 'shot_scorpion']) {
    assert.ok(doc.cues[c].other_db >= -6 && doc.cues[c].other_db <= -4, `${c}: ${doc.cues[c].other_db}`);
  }
});

const ARROW_LANDINGS = ['arrow_flesh', 'arrow_wood', 'arrow_shield', 'arrow_dirt', 'arrow_water'];

test('one arrow is a very short sound, in several variants, on a crowd pool that cannot take a player from anything', () => {
  assert.ok(doc.mix.crowd_voices >= 12, `${doc.mix.crowd_voices} crowd voices`);
  assert.equal(doc.mix.sfx_voices, 16, 'Sfx keeps its cap');
  for (const id of ARROW_LANDINGS) {
    const s = doc.sounds[id];
    assert.ok(s.dur >= 0.04 && s.dur <= 0.09, `${id}: ${s.dur} s`);
    assert.ok(s.variants >= 3, id);
    assert.equal(s.compress, 'pcm', `${id}: an attack this short keeps its samples`);
  }
  for (const surface of SURFACES) {
    const hit = doc.cues[`hit_arrow_${surface}`].hits[0];
    assert.equal(hit.sound, `arrow_${surface}`);
    assert.equal(hit.crowd, true);
    assert.ok(hit.priority < 6, 'under every cue, for what a stolen player would mean');
    assert.equal(hit.pan_var, 'pan');
    assert.equal(hit.pitch_var, 'pv');
    assert.equal(hit.db_var, 'lvl');
    assert.equal(doc.cues[`hit_arrow_${surface}`].hits.length, 1);
  }
});

test('the preview lands every volley, arrow by arrow, about as a real wave does', () => {
  const events = doc.preview.events;
  const volleys = events.filter((e) => e.cue === 'shot_arrow' && e.t < 58).length;
  const landings = events.filter((e) => e.cue.startsWith('hit_arrow_')).length;
  assert.ok(Math.abs(landings - volleys * 12) <= 24, `${landings} landings of ${volleys} volleys`);
  const misses = events.filter((e) => e.cue === 'hit_arrow_dirt' || e.cue === 'hit_arrow_water').length;
  assert.ok(misses / landings >= 0.75, `${misses} of ${landings} miss, as in a real wave`);
});

test('a miss is under a hit: the small sound of the ground is quieter than a body at the same level of the mix', () => {
  const bank = new BankAudio(doc, path.dirname(BANK));
  const loudest = (id, db) => {
    const x = bandFilter(bank.file(id, 0).data[0], 400, 6000, 22050);
    const n = Math.round(0.05 * 22050);
    let best = -300;
    for (let a = 0; a + n <= x.length; a += 40) {
      let e = 0;
      for (let i = 0; i < n; i++) e += x[a + i] * x[a + i];
      best = Math.max(best, 10 * Math.log10(e / n + 1e-30));
    }
    return best + db;
  };
  const db = (cue) => doc.cues[cue].hits[0].db;
  assert.ok(loudest('arrow_dirt', db('hit_arrow_dirt')) <= loudest('arrow_flesh', db('hit_arrow_flesh')) - 6);
  assert.ok(loudest('arrow_dirt', db('hit_arrow_dirt')) <= loudest('arrow_wood', db('hit_arrow_wood')) - 6);
});

test('what a rider must hear of the gate cannot lose its voice to a flight', () => {
  for (const c of ['gate_hit', 'ram_thud', 'leak']) assert.equal(doc.cues[c].hits[0].priority, 8, c);
});

test('the Scorpion is not the arrow\'s flight at another pitch', () => {
  const pitch = doc.cues.shot_scorpion.hits.find((h) => h.flight).pitch ?? 1;
  assert.ok(pitch < 1.3, `pitch ${pitch}`);
  assert.notEqual(doc.cues.shot_scorpion.hits.find((h) => h.flight).sound, doc.cues.shot_arrow.hits.find((h) => h.flight).sound);
});

test('D5 sees the worst: a volley sits in the prompt window, and the preview fires the organ at its real rate', () => {
  const events = doc.preview.events;
  const volley = events.filter((e) => e.cue === 'shot_arrow').map((e) => e.t).sort((a, b) => a - b);
  assert.ok(events.some((e) => e.cue === 'shot_arrow' && e.t >= 30 && e.t < 31.2), 'a volley in the second before 31.2 s');
  const run = volley.filter((t) => t >= 5 && t < 55);
  assert.ok(run.length / 50 >= 0.9, `${(run.length / 50).toFixed(2)} volleys a second`);
});

test('the preview plays levels the adapter can give: every other volley under', () => {
  const levels = doc.preview.events.filter((x) => x.cue === 'shot_arrow').map((x) => x.vars.lvl);
  assert.deepEqual([...new Set(levels)].sort((x, y) => x - y), [-6, 0]);
  levels.forEach((v, i) => assert.equal(v, i % 2 === 1 ? -6 : 0, `volley ${i}`));
});

test('A14 is a waiver, with its numbers, and not a pass', () => {
  assert.match(doc.preview.waive.A14, /median/i);
  assert.ok(doc.preview.events.filter((e) => e.cue === doc.preview.checks.a14.cue).length >= 3, 'a median of real firings');
});

test('a stone on bodies is the bodies first: the ground 9 dB under', () => {
  const hits = doc.cues.hit_stone_flesh.hits;
  assert.equal(hits[0].sound, 'hit_flesh');
  assert.equal(hits[1].sound, 'stone_impact');
  assert.equal(hits[0].db - hits[1].db, 9);
});

test('a body at full level stays under the master head on its own', () => {
  for (const c of ['hit_arrow_flesh', 'hit_scorpion_flesh', 'hit_bolt_flesh', 'hit_stone_flesh']) {
    assert.ok(doc.cues[c].hits[0].db <= -2.5, c);
  }
});

const REAL = ['organ', 'auto'].map((k) => [k, JSON.parse(fs.readFileSync(new URL(`./real_wave_${k}.json`, import.meta.url), 'utf8'))]);

for (const [name, wave] of REAL) {
  test(`the real wave, rider ${name}: holds what the preview can only estimate`, () => {
    const sha = crypto.createHash('sha256').update(fs.readFileSync(BANK)).digest('hex');
    assert.equal(wave.bank_sha, sha, 'the bank has moved on: record it again, tools/audio/live_report.mjs');
    assert.ok(wave.seconds >= 150, 'a real wave, not a sample');
    assert.equal(wave.flight_starts, wave.shots, 'one flight per shot');
    assert.ok(wave.ear_band_share <= -12, `2-8 kHz ${wave.ear_band_share} dB of the master, Tank's limit -12`);
    assert.ok(wave.lufs >= -20 && wave.lufs <= -16, `${wave.lufs} LUFS`);
    assert.ok(wave.top_band_share <= -32, `above 9.8 kHz ${wave.top_band_share} dB`);
    assert.ok(wave.prompt_margin_worst >= 6, `warning ${wave.prompt_margin_worst} LU over the wave at its worst`);
    const a = wave.mix_apart_first_60ms;
    for (const k of ['flesh_dirt', 'wood_dirt']) assert.ok(a[k] >= 3, `${k} ${a[k]} dB in the mix`);
    if (name === 'organ') {
      assert.ok(a.shield_dirt >= 3, `shield_dirt ${a.shield_dirt} dB in the mix`);
      const own = wave.flights_1k_2k4.over.own_arrow_swarm_full_level;
      assert.ok(own.n >= 50, 'flights from the log');
      assert.ok(own.median >= 3, `your arrow's peak +${own.median} dB over everything, 1-2.4 kHz`);
    }
    // The owner's request withdrew the limit of 2.5 impacts a second: every arrow that lands now has its sound.
    assert.notEqual(wave.driver, 'Dummy', 'the Dummy driver mixes in 93 ms chunks: a crowd of short sounds piles up in it');
    const n = wave.arrows;
    assert.ok(n.landed >= 1000, `${n.landed} arrows landed`);
    assert.equal(n.sounds_asked, n.landed, 'every arrow that landed asked for one sound');
    assert.ok(n.landed - n.sounds_started <= 2, `${n.landed} landed, players took ${n.sounds_started}, the last frame's aside`);
    assert.equal(n.body_sounds - (n.by_sound.arrow_shield ?? 0), n.struck_by_ear, 'one body sound per arrow that struck');
    assert.ok(Math.abs(n.struck_by_ear - n.station_hits) <= Math.max(5, n.station_hits * 0.25), `${n.struck_by_ear} by ear, ${n.station_hits} by the host`);
    assert.equal(n.crowd_voiceless, 0, 'no arrow dropped');
    assert.deepEqual(Object.keys(n.stolen).filter((k) => k.startsWith('Crowd')), [], 'no arrow cut short by another');
    const one = wave.one_arrow;
    const own = name === 'organ';
    for (const sound of ['arrow_flesh', 'arrow_wood']) {
      const best = Math.max(one.all_400_6000.body.sounds[sound].median, one.low_400_1000.body.sounds[sound].median);
      // Your own arrows at P4's own +3 dB over everything else, the crowd of other arrows too; another rider's 5 dB under.
      assert.ok(best >= (own ? 3 : -2), `${sound} over the mix ${best} dB`);
    }
    // No model: what the master itself does in the 50 ms a body lands, against what any moment does.
    const rise = one.all_400_6000.body.rise - one.all_400_6000.arbitrary_rise;
    assert.ok(rise >= (own ? 6 : 4), `a body lifts the master ${rise} dB over an arbitrary moment`);
    const bodyOverMiss = one.all_400_6000.body.median - one.all_400_6000.miss.median;
    assert.ok(bodyOverMiss >= 6, `a body stands ${bodyOverMiss} dB over a miss in the same mix`);
    const f = wave.fatigue;
    assert.ok(f.lufs_30s_spread <= 2.5, `30 s levels ${f.lufs_30s.join(' ')}`);
    assert.equal(f.same_file_twice_running, 0, 'no file twice running on a surface');
    assert.ok(f.envelope_repeat.correlation < 0.6, `the arrows' band repeats at ${f.envelope_repeat.lag_s} s: ${f.envelope_repeat.correlation}`);
  });
}

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
