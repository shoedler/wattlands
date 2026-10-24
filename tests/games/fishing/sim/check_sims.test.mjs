// node --test tests/games/fishing/sim/check_sims.test.mjs: check_sims.mjs and fishing_sim_lib.mjs
// on small in-memory reports in the GAME_SDK 19.1 layout. Independent of build/.
import test from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';

import * as cs from './check_sims.mjs';
import { SP, SPECIES, clampProblems, eventErrors, expectedLaps, gradeOf, median, requestShapeProblems } from './fishing_sim_lib.mjs';

const erg = (target, reason = 'pull', duration = 0) => ({ mode: 'ERG', target_pct: target, duration_s: duration, reason, source: 'fishing' });
const fight = { kind: 'WORK', mode: 'ERG', label: 'FISHING_SPECIES_MACKEREL', lap: true, open_ended: true, min_s: 48, max_s: 120, target_pct: 63, range_pct: [60, 66] };
const plan = {
  phases: [
    { kind: 'WARMUP', mode: 'SIM', label: 'FISHING_PHASE_DRIVE_OUT', lap: true, duration_s: 300, grade_source: 'game' },
    { kind: 'FREE', mode: 'SIM', label: 'FISHING_PHASE_ROAM', lap: true, open_ended: true, min_s: 5, max_s: 1860, grade_source: 'game' },
    fight,
    { kind: 'WORK', mode: 'SIM', label: 'FISHING_PHASE_LANDING', lap: false, duration_s: 30, grade_source: 'flat' },
    { kind: 'FREE', mode: 'SIM', label: 'FISHING_PHASE_ROAM', lap: true, open_ended: true, min_s: 5, max_s: 1500, grade_source: 'game' },
    { kind: 'COOLDOWN', mode: 'ERG', label: 'Cool-down', lap: true, duration_s: 180, target_pct: 50 },
  ],
  cooldown_appended: true,
};
const spans = [
  { index: 0, kind: 'WARMUP', mode: 'SIM', label: 'FISHING_PHASE_DRIVE_OUT', start: 0, end: 300, ended_by: 'duration' },
  { index: 1, kind: 'FREE', mode: 'SIM', label: 'FISHING_PHASE_ROAM', start: 300, end: 320, ended_by: 'end_phase' },
  { index: 2, kind: 'WORK', mode: 'ERG', label: 'FISHING_SPECIES_MACKEREL', start: 320, end: 400, ended_by: 'end_phase' },
  { index: 3, kind: 'WORK', mode: 'SIM', label: 'FISHING_PHASE_LANDING', start: 400, end: 430, ended_by: 'duration' },
  { index: 4, kind: 'FREE', mode: 'SIM', label: 'FISHING_PHASE_ROAM', start: 430, end: 1800, ended_by: 'finished' },
  { index: 5, kind: 'COOLDOWN', mode: 'ERG', label: 'Cool-down', start: 1800, end: 1980, ended_by: 'duration' },
];
const ev = (t, event) => ({ t, pt: t, type: 'game_event', event });

/** A minimal passing roam_30 solo report (r1_roam30_solo). */
function roamReport() {
  return {
    schema: 1,
    game_id: 'fishing',
    content_id: 'roam_30',
    end_reason: 'complete',
    finished_reason: 'trip_over',
    slots: [{ slot: 0, peer: 1, ftp: 200, is_bot: false }],
    plans: { 1: plan },
    plan_warnings: { 1: [] },
    phases: { 1: spans },
    directives: [
      { id: 1, peer: 1, t: 10, kind: 'course_grade', requested: { grade_pct: 2.1 }, accepted: true, applied: null },
      { id: 2, peer: 1, t: 318, kind: 'replan', requested: { plan: {} }, accepted: true, applied: null },
      { id: 3, peer: 1, t: 330, kind: 'request', requested: { ...erg(64), id: 3 }, accepted: true, applied: { clamped_by: ['slew'], refused: false, phase_index: 2, applied: { target_w: 128 } } },
      { id: 4, peer: 1, t: 500, kind: 'course_grade', requested: { grade_pct: 0 }, accepted: true, applied: null },
    ],
    directives_unmatched: [],
    trace: { 1: [{ t: 1, game_t: 1, clamped_by: [] }] },
    events: [
      ev(310, { type: 'cast', l: 0, sp: 0, dx: 120, z: 40 }),
      ev(318, { type: 'bite', l: 0, sp: 0 }),
      ev(320, { type: 'hookup', l: 0, sp: 0, n: 1, sch: 0 }),
      ev(400, { type: 'landing', l: 0, sp: 0 }),
      ev(415, { type: 'landed', l: 0, sp: 0, grade: 0, kg: 12, points: 28, hk: 10 }),
      ev(450, { type: 'cast', l: 0, sp: 1, dx: -90, z: 60 }),
      ev(600, { type: 'landed', l: 0, sp: 1, grade: 1, kg: 30, points: 50, hk: 10 }),
      ev(1800, { type: 'time_up' }),
      ev(1800, { type: 'trip_over' }),
    ],
    max_snapshot_bytes: 600,
    fit_paths: ['a.fit'],
  };
}

test('the library knows every v2 species and event', () => {
  assert.equal(SPECIES.length, 10);
  assert.equal(SP.grouper, 8);
  assert.deepEqual(eventErrors({ type: 'turn', l: 1, h: -1 }), []);
  assert.deepEqual(eventErrors({ type: 'cast', l: 0, sp: 3, dx: -120, z: 55 }), []);
  assert.match(eventErrors({ type: 'strike_ok', l: 0, sp: 0 })[0], /unknown event type/);
  assert.match(eventErrors({ type: 'landed', l: 0, sp: 12, grade: 0, kg: 1, points: 1, hk: 10 })[0], /species 12/);
  assert.match(eventErrors({ type: 'turn', l: 0, h: 2 })[0], /heading/);
  assert.match(eventErrors({ type: 'bite', l: 7, sp: 0 })[0], /slot 7/);
});

test('request shapes, clamps and grades', () => {
  assert.deepEqual(requestShapeProblems(erg(105.5, 'run', 20)), []);
  assert.ok(requestShapeProblems(erg(111)).some((p) => /target_pct/.test(p)));
  assert.ok(requestShapeProblems({ ...erg(80), extra: 1 }).some((p) => /keys/.test(p)));
  assert.deepEqual(requestShapeProblems({ mode: 'SIM', haptic: 3, duration_s: 5, reason: 'last_run', source: 'fishing' }), []);
  assert.deepEqual(clampProblems(['slew', 'switch_ramp', 'grade_range']), []);
  assert.match(clampProblems(['long_phase'])[0], /forbidden/);
  assert.equal(gradeOf({ requested: { grade_pct: 1.5 } }), 1.5);
  assert.equal(median([3, 1, 2]), 2);
});

test('expected laps count the lap phases that ran plus the cool-down', () => {
  assert.equal(expectedLaps(roamReport(), '1'), 5, 'drive out, roam, fight, roam, cool-down');
});

test('a clean roam report passes ALL and R1', () => {
  const r = roamReport();
  assert.deepEqual(cs.runProblems('r1', r), []);
  const res = cs.checkR1({ r1_roam30_solo: r });
  assert.equal(res.ok, true, res.probs.join('\n'));
  assert.match(res.info, /2 fish, 78 points/);
});

test('ALL catches refusals, out-of-range targets, forbidden clamps and stray grades', () => {
  const r = roamReport();
  r.directives[2].requested.target_pct = 70;
  r.directives[2].applied.clamped_by = ['limit_105'];
  r.directives.push({ id: 9, peer: 1, t: 350, kind: 'course_grade', requested: { grade_pct: 1 }, accepted: true, applied: null });
  r.directives.push({ id: 10, peer: 1, t: 351, kind: 'end_phase', requested: {}, accepted: false, reason: 'before_min_s', applied: null });
  r.max_snapshot_bytes = 3000;
  const probs = cs.runProblems('x', r).join('\n');
  assert.match(probs, /outside phase 2/);
  assert.match(probs, /limit_105/);
  assert.match(probs, /course grade outside a Free Roam SIM phase/);
  assert.match(probs, /refused \(before_min_s\)/);
  assert.match(probs, /3000 bytes/);
});

test('ALL rejects an ERG phase over 300 s above 105 %', () => {
  const r = roamReport();
  r.plans[1] = { ...plan, phases: plan.phases.map((p, i) => (i === 2 ? { ...p, max_s: 420, range_pct: [100, 108] } : p)) };
  assert.match(cs.runProblems('x', r).join('\n'), /108 % in a 420 s phase/);
});

test('R1 wants a replan per bite and no bite in the drive-out', () => {
  const r = roamReport();
  r.events.splice(1, 0, ev(200, { type: 'bite', l: 0, sp: 0 }));
  const res = cs.checkR1({ r1_roam30_solo: r });
  assert.equal(res.ok, false);
  const text = res.probs.join('\n');
  assert.match(text, /1 replans for 2 bites/);
  assert.match(text, /in the drive-out/);
});

test('bot strategies come from their driving power band', () => {
  const r = roamReport();
  r.slots.push({ slot: 1, peer: -1, ftp: 200, is_bot: true }, { slot: 2, peer: -2, ftp: 200, is_bot: true });
  r.events.push({ t: 2, type: 'hud', kind: 'power_band', peer: -1, lo_w: 95, hi_w: 105 });
  r.events.push({ t: 2, type: 'hud', kind: 'power_band', peer: -1, lo_w: 190, hi_w: 210 });
  r.events.push({ t: 2, type: 'hud', kind: 'power_band', peer: -2, lo_w: 142.5, hi_w: 157.5 });
  r.events.push({ t: 900, type: 'hud', kind: 'power_band', peer: -2, lo_w: 247, hi_w: 273 });
  assert.deepEqual(cs.botStrategies(r), { 1: 'big', 2: 'small' });
});

test('R3 flags a bot that never fished and a lopsided strategy', () => {
  const r = roamReport();
  r.slots.push({ slot: 1, peer: -1, ftp: 200, is_bot: true });
  r.events.push({ t: 2, type: 'hud', kind: 'power_band', peer: -1, lo_w: 142.5, hi_w: 157.5 });
  const res = cs.checkR3({ r3_roam30_bots_seed1: r }, [1]);
  assert.equal(res.ok, false);
  assert.match(res.probs.join('\n'), /bot 1 \(small\) landed nothing/);
});

test('R5 passes 0.85 x the target and fails a haptic to slot 1', () => {
  const r = roamReport();
  r.slots.push({ slot: 1, peer: 2, ftp: 200, is_bot: false });
  r.directives[2].applied = { clamped_by: ['unverified'], refused: false, phase_index: 2, applied: { target_w: 163 } };
  let res = cs.checkR5({ r5_roam30_unverified: r });
  assert.equal(res.ok, true, res.probs.join('\n'));
  r.directives.push({ id: 11, peer: 2, t: 425, kind: 'request', requested: { mode: 'SIM', haptic: 3, duration_s: 5, reason: 'last_run', source: 'fishing' }, accepted: true, applied: { clamped_by: [], refused: false } });
  r.directives[2].applied.applied.target_w = 192;
  res = cs.checkR5({ r5_roam30_unverified: r });
  const text = res.probs.join('\n');
  assert.match(text, /haptic for the opted-out rider/);
  assert.match(text, /applied 192 W/);
});

test('D compares the deterministic hashes', () => {
  assert.equal(cs.checkD({ d_roam_a: { deterministic_hash: 'x' }, d_roam_b: { deterministic_hash: 'x' } }).ok, true);
  assert.equal(cs.checkD({ d_roam_a: { deterministic_hash: 'x' }, d_roam_b: { deterministic_hash: 'y' } }).ok, false);
  assert.equal(cs.checkD({}).skip, true);
});

test('FIT runs fit_check with the expected laps', () => {
  const calls = [];
  const res = cs.checkFit({ r1: roamReport() }, (args) => {
    calls.push(args);
    return { status: 0, stdout: '{}' };
  });
  assert.equal(res.ok, true);
  assert.deepEqual(calls[0].slice(1), ['--expect-laps=5', '--json']);
});

test('main prints one line per scenario and skips missing ones', () => {
  let text = '';
  const out = { write: (s) => (text += s) };
  assert.equal(cs.main([], out, out), 2);
  text = '';
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fishing-sims-'));
  assert.equal(cs.main([dir, '--only=ALL,W3'], out, out), 0);
  fs.rmSync(dir, { recursive: true, force: true });
  assert.match(text, /SKIP ALL/);
  assert.match(text, /SKIP W3/);
});
