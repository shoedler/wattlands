// Every reward and threat cue, the near threats and the sounds the owner named, against the room at a hard ride. A
// cue reads when it wins some third-octave band (read_over.mjs). What these numbers cannot say is whether it sounds
// right: nobody has listened.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { hardRide, openBank, readOf, SEATS } from './read_over.mjs';

const bank = openBank();
const doc = bank.doc;
const one = (id) => (s) => s === id;
// The furthest a far tank holds (destroyer, 2200 m), where these are quietest.
const FAR = -11.1;
const cue = (name, vars = {}) => ({ cues: [{ t: 1, cue: name, vars }] });

const THREATS = {
  enemy_thump: [cue('enemy_thump', { delay: 0, range_db: FAR }), one('enemy_thump'), 1, 3],
  hit_tank: [cue('hit_tank', { dmg_db: -5 }), (s) => s === 'incoming_impact_near' || s === 'hull_hit', 1, 3],
  hit_small: [cue('hit_small'), one('hull_hit'), 1, 2],
  splash_near: [cue('splash_near'), one('near_miss_thud'), 1, 3],
  shot_near_mg: [cue('shot_near_mg'), one('small_mg'), 1, 2],
  ambush: [cue('ambush'), one('near_burst'), 1, 3],
  incoming_whistle: [cue('incoming_whistle', { rate: 1 }), one('incoming_whistle'), 1, 3.6],
  breakdown: [cue('breakdown'), one('breakdown_stall'), 1, 3],
  tank_lost: [cue('tank_lost'), one('tank_lost'), 1, 3],
  boss_phase: [cue('boss_phase'), one('boss_phase'), 1, 3],
};
const REWARDS = {
  kill_far: [cue('kill_far', { delay: 0, range_db: FAR }), one('explode_big'), 1, 3.5],
  kill_near: [cue('kill_near'), one('explode_small'), 1, 3],
  hit_far_boom: [cue('hit_far', { delay: 0, range_db: FAR }), one('far_boom'), 1, 3.5],
  hit_far_metal: [cue('hit_far', { delay: 0, range_db: FAR }), one('far_hit_metal'), 1, 3],
  hit_near: [cue('hit_near'), one('far_hit_metal'), 1, 2],
  splash_far: [cue('splash_far', { delay: 0, range_db: FAR }), one('far_boom'), 1, 3.5],
  evade: [cue('evade'), one('evade_lurch'), 1, 2.5],
  repaired: [cue('repaired'), one('repaired_start'), 1, 3.5],
  patch: [cue('patch'), one('plate_press'), 1, 2.5],
  segment: [cue('segment'), one('horn_segment'), 1, 3],
};

for (const seat of SEATS) {
  for (const [name, [moment, pick, from, to, hold]] of Object.entries({ ...THREATS, ...REWARDS })) {
    test(`${name} reads over a hard ride on ${seat}`, () => {
      const r = readOf(bank, hardRide(seat, moment), pick, from, to, hold ?? 0.2);
      assert.ok(r.db > 0, `${r.db.toFixed(1)} dB at ${r.hz} Hz`);
    });
  }
}

// The near threats. Heard before anyone has to look: over the room while it is close, on every seat.
const NEAR = ['recon_engine', 'tankette_engine'];
const held = (id, dist, rev) => ({ loops: [{ id, t0: 0.5, t1: 7, params: { dist, rev } }] });

for (const seat of SEATS) {
  for (const id of NEAR) {
    test(`${id} bursts out over the room on ${seat}, and holds it while it stops to fire`, () => {
      // A small high engine, not one more low one: it wins a band above the machines' fundamentals.
      const close = readOf(bank, hardRide(seat, held(id, 30, 1)), one(id), 1.5, 5, 1, 800);
      assert.ok(close.db >= 3, `at 30 px: ${close.db.toFixed(1)} dB at ${close.hz} Hz`);
      // It stops to fire only short of flee_px, 185.
      for (const dist of [70, 120, 160]) {
        const r = readOf(bank, hardRide(seat, held(id, dist, 0)), one(id), 1.5, 5, 1);
        assert.ok(r.db > 0, `paused at ${dist} px: ${r.db.toFixed(1)} dB at ${r.hz} Hz`);
      }
      const leaving = readOf(bank, hardRide(seat, held(id, 185, 1)), one(id), 1.5, 5, 1);
      assert.ok(leaving.db > 0, `leaving at 185 px: ${leaving.db.toFixed(1)} dB at ${leaving.hz} Hz`);
    });
  }
}

for (const id of NEAR) {
  test(`${id} fades as it flees`, () => {
    const at = (dist) => readOf(bank, hardRide('diesel', held(id, dist, 1)), one(id), 1.5, 5, 1);
    const levels = [30, 185, 320, 440, 560].map((d) => at(d).fg_db);
    for (let i = 1; i < levels.length; i++) assert.ok(levels[i] < levels[i - 1] - 3, levels.map((l) => l.toFixed(1)).join(' '));
    assert.ok(at(560).db < -6, `gone into the room by the end: ${at(560).db.toFixed(1)} dB`);
  });
}

test('a near engine is higher than the machines: more above 1 kHz than a far boom', () => {
  for (const id of NEAR) {
    const r = bank.file(id, 0).data[0];
    let high = 0;
    let all = 0;
    let lp = 0;
    for (const x of r) {
      lp += 0.25 * (x - lp);
      high += (x - lp) ** 2;
      all += x * x;
    }
    assert.ok(high / all > 0.2, `${id}: ${((100 * high) / all).toFixed(1)} % above about 1 kHz`);
  }
});

// Far stays far: the shell's flight comes close only at its end, and the shot itself is a low thump.
test('a far shell is faint in the air and close only as it lands', () => {
  const m = cue('incoming_whistle', { rate: 1 });
  const early = readOf(bank, hardRide('diesel', m), one('incoming_whistle'), 1, 2);
  const late = readOf(bank, hardRide('diesel', m), one('incoming_whistle'), 3, 3.5);
  assert.ok(late.fg_db - early.fg_db >= 12, `early ${early.fg_db.toFixed(1)}, late ${late.fg_db.toFixed(1)} dB`);
  assert.ok(early.db <= 6, `the first second is no near whistle: ${early.db.toFixed(1)} dB`);
  assert.ok(late.db >= 10, `the last half second cuts through: ${late.db.toFixed(1)} dB`);
});

test('a far shot is low', () => {
  const r = readOf(bank, hardRide('diesel', cue('enemy_thump', { delay: 0, range_db: FAR })), one('enemy_thump'), 1, 3);
  assert.ok(r.hz <= 125, `best at ${r.hz} Hz`);
});

// What the owner asked for by name, on the seat each belongs to or, for the track, the hardest room.
const NAMED = {
  track_squeak: ['diesel', {}, one('track_squeak'), 1, 7, 0.15],
  shell_eject: ['dynamo', cue('shot_main'), one('shell_eject'), 1.3, 2.2, 0.1],
  shell_load: ['steam', cue('latch_load'), one('shell_load'), 1, 2.4],
  breech_close: ['steam', cue('latch_load'), one('breech_close'), 1.5, 2.5],
  diesel_valve_ex: ['diesel', {}, one('diesel_valve_ex'), 1, 7, 0.1],
  diesel_valve_in: ['diesel', {}, one('diesel_valve_in'), 1, 7, 0.1],
  turbo_whistle: ['diesel', {}, one('turbo_whistle'), 2, 7, 1],
  exhaust_crackle_over_band: ['diesel', { params: { power: 1.28, liftoff: 0.5 } }, one('exhaust_crackle'), 1, 7, 0.1],
  exhaust_crackle_lift_off: ['diesel', { params: { power: 0.45, liftoff: 0.9 } }, one('exhaust_crackle'), 1, 7, 0.1],
};

for (const [name, [seat, moment, pick, from, to, hold]] of Object.entries(NAMED)) {
  test(`${name} is audible at a hard ride`, () => {
    const r = readOf(bank, hardRide(seat, moment), pick, from, to, hold ?? 0.2);
    assert.ok(r.db > 0, `${r.db.toFixed(1)} dB at ${r.hz} Hz`);
  });
}

test('the preview plays the UI the game plays', () => {
  const sounds = new Set(doc.preview.hud.map((h) => h.sound));
  assert.ok(sounds.has('toast') && sounds.has('phase'));
  const events = doc.preview.events.map((e) => e.t);
  for (const t of [7, 15, 29, 37, 58]) assert.ok(events.includes(t), `an event at ${t} s`);
});

test('a waiver is still needed for what it says', () => {
  assert.deepEqual(Object.keys(doc.preview.waive ?? {}), ['A13']);
  assert.match(doc.preview.waive.A13, /30 repeats among 465/);
});
