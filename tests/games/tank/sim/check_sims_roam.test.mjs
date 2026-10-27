// tests/games/tank/sim/check_sims_roam.test.mjs: unit tests of check_sims.mjs's free-roam scenarios (S11, S12) on
// synthetic reports. Each check passes on a clean synthetic run and fails on the violation it exists to catch.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as C from './check_sims.mjs';

const START = { 1: ['bulwark'], 2: ['diesel', 'dynamo'], 3: ['diesel', 'dynamo', 'steam'], 4: ['diesel', 'dynamo', 'steam', 'arc'] };

function roamPhase(engine, seg, minutes) {
  const minS = minutes * 60 - 300;
  const meta = { engine, mission: `roam_${minutes}`, seg, segment: seg === 'depot' ? 0 : 1, stage: seg === 'depot' ? 0 : 1 };
  const base = seg === 'depot'
    ? { duration_s: 300, kind: 'WARMUP', label: 'TANK_PHASE_DRIVE_OUT', lap: true, meta }
    : { duration_s: minS, kind: 'WORK', label: 'TANK_PHASE_ROAM', lap: true, meta, open_ended: true, min_s: minS, max_s: minS + 300 };
  if (engine === 'dynamo') return seg === 'depot' ? { ...base, mode: 'ERG', target_pct: 50, ramp_to_pct: 65 } : { ...base, mode: 'ERG', target_pct: 55, range_pct: [55, 85] };
  if (engine === 'arc') return seg === 'depot' ? { ...base, mode: 'ERG', target_pct: 50, ramp_to_pct: 65 } : { ...base, mode: 'ERG', target_pct: 65, range_pct: [65, 80] };
  return { ...base, mode: 'SIM', grade_source: engine === 'steam' ? 'flat' : 'game' };
}

/**
 * A clean free-roam run. opts: roamS (seconds of the roam phase, default min_s + 20), endedBy, points, grade (default
 * computed), patrols (in all), patrolsAtTimeUp, timeUps (count), finished, rideTag, endReason, role, events, kills.
 */
function makeRoam(crew, minutes, opts = {}) {
  const minS = minutes * 60 - 300;
  const roamS = opts.roamS ?? minS + 20;
  const coolStart = 300 + roamS;
  const end = coolStart + 180;
  const slots = [];
  const plans = {};
  const phases = {};
  const trace = {};
  for (let s = 0; s < crew; s += 1) {
    const peer = String(s + 1);
    slots.push({ slot: s, peer: s + 1, is_bot: false, ftp: 200, ftp_verified: true, haptics_on: true, autopilot: true, rider: 'erg:compliance=1.0' });
    const engine = START[crew][s];
    const plan = [roamPhase(engine, 'depot', minutes), roamPhase(engine, 'roam', minutes)];
    plan.push({ duration_s: 180, kind: 'COOLDOWN', label: 'Cool-down', lap: true, mode: 'ERG', target_pct: 50 });
    plans[peer] = { phases: plan, cooldown_appended: true };
    phases[peer] = [
      { index: 0, kind: plan[0].kind, mode: plan[0].mode, label: plan[0].label, start: 0, end: 300, ended_by: 'duration' },
      { index: 1, kind: 'WORK', mode: plan[1].mode, label: plan[1].label, start: 300, end: coolStart, ended_by: opts.endedBy ?? 'end_phase' },
      { index: 2, kind: 'COOLDOWN', mode: 'ERG', label: 'Cool-down', start: coolStart, end, ended_by: 'duration' },
    ];
    trace[peer] = [];
  }
  const ge = (time, event) => ({ type: 'game_event', t: time, pt: time, event });
  const patrols = opts.patrols ?? 6;
  const events = [];
  for (let i = 0; i < (opts.timeUps ?? 1); i += 1) events.push(ge(300 + minS, { type: 'time_up', p: opts.patrolsAtTimeUp ?? patrols }));
  for (const k of opts.kills ?? []) events.push(ge(400, { type: 'kill', id: 9, e: 1, by: k, s: 0 }));
  events.push(...(opts.events ?? []));
  const points = opts.points ?? Math.round(15 * (roamS / 60));
  const grade = opts.grade ?? C.roamGrade(points / (roamS / 60));
  return {
    schema: 1,
    game_id: 'tank',
    content_id: `roam_${minutes}`,
    role: opts.role ?? (crew >= 2 ? 'HOST' : 'SOLO'),
    seed: 1,
    args: { game: 'tank', content: `roam_${minutes}`, players: crew, bots: 0, seed: 1, riders: ['erg:compliance=1.0'] },
    slots,
    plans,
    plan_warnings: Object.fromEntries(Object.keys(plans).map((p) => [p, []])),
    end_reason: opts.endReason ?? 'complete',
    finished_reason: opts.finished ?? 'time_up',
    phases,
    directives: [],
    directives_unmatched: [],
    trace,
    events,
    snapshots: [],
    max_snapshot_bytes: 900,
    oversize_snapshots: 0,
    results: {
      grade,
      score: points,
      ride_tag: opts.rideTag ?? `Free Roam ${minutes} min`,
      rows: [],
      team: { TANK_TEAM_PATROLS: patrols, TANK_TEAM_POINTS_PER_MIN: '6.0', TANK_TEAM_ROAM_KILLS: '1/0/0/0/0' },
    },
    fit_paths: [],
    deterministic_hash: 'h',
  };
}

const s11 = (over = {}) => ({
  s11_roam10_c1: makeRoam(1, 10),
  s11_roam10_c4: makeRoam(4, 10),
  s11_roam30_c3: makeRoam(3, 30),
  ...over,
});

const zeroRun = (opts = {}) => {
  const r = makeRoam(3, 10, { endReason: 'timeout', finished: '', grade: opts.grade ?? 'D', kills: opts.kills ?? [] });
  r.phases = Object.fromEntries(Object.entries(r.phases).map(([p, sp]) => [p, opts.left ? sp.slice(0, 2) : sp.slice(0, 1)]));
  r.events.push({ type: 'paused', paused: true, reason: opts.reason ?? 'all_stopped', t: 10, pt: 15 });
  if (opts.resumed) r.events.push({ type: 'paused', paused: false, reason: '', t: 10, pt: 40 });
  r.events = r.events.filter((e) => e.event?.type !== 'time_up');
  return r;
};

test('roamMinutes and roamGrade follow valley.json (brief 2.8 x 2.5)', () => {
  assert.equal(C.roamMinutes('roam_45'), 45);
  assert.ok(Number.isNaN(C.roamMinutes('ashfall_road')));
  assert.deepEqual([22.5, 22.4, 17.5, 12.5, 7.5, 7.4, 0].map(C.roamGrade), ['S', 'A', 'A', 'B', 'C', 'D', 'D']);
});

test('S11 passes on clean roam runs and is skipped without them', () => {
  const r = C.checkS11(s11());
  assert.equal(r.status, 'PASS', r.details.join(' | '));
  assert.match(r.summary, /s11_roam30_c3 .* grade B/);
  assert.equal(C.checkS11({}).status, 'SKIP');
  const some = C.checkS11({ s11_roam10_c1: makeRoam(1, 10) });
  assert.equal(some.status, 'FAIL');
});

test('S11 fails past the overtime bound, at max_s, before min_s, without one step for every rider', () => {
  for (const [over, why] of [
    [{ s11_roam10_c1: makeRoam(1, 10, { roamS: 601 }) }, /past the overtime bound/],
    [{ s11_roam10_c1: makeRoam(1, 10, { roamS: 600, endedBy: 'max_s' }) }, /ended by max_s/],
    [{ s11_roam10_c4: makeRoam(4, 10, { roamS: 250 }) }, /before min_s/],
  ]) {
    const r = C.checkS11(s11(over));
    assert.equal(r.status, 'FAIL');
    assert.match(r.details.join(' | '), why);
  }
  const split = makeRoam(4, 10);
  split.phases['3'][1].end += 5;
  split.phases['3'][2].start += 5;
  assert.match(C.checkS11(s11({ s11_roam10_c4: split })).details.join(' | '), /different times/);
});

test('S11 fails on a patrol after time up, a missing or doubled time_up, the wrong outcome or ride tag', () => {
  for (const [opts, why] of [
    [{ patrols: 7, patrolsAtTimeUp: 6 }, /a patrol came after time up/],
    [{ timeUps: 0 }, /0 time_up events/],
    [{ timeUps: 2 }, /2 time_up events/],
    [{ finished: 'victory' }, /finished_reason/],
    [{ rideTag: 'Free Roam' }, /ride_tag/],
    [{ grade: 'S' }, /grade S for/],
  ]) {
    const r = C.checkS11(s11({ s11_roam10_c1: makeRoam(1, 10, opts) }));
    assert.equal(r.status, 'FAIL', JSON.stringify(opts));
    assert.match(r.details.join(' | '), why);
  }
});

test('S11 holds the compliant 30-min crew of 3 to B or A', () => {
  const low = makeRoam(3, 30, { points: Math.round(11 * (1520 / 60)) });
  const r = C.checkS11(s11({ s11_roam30_c3: low }));
  assert.equal(r.status, 'FAIL');
  assert.match(r.details.join(' | '), /wanted A or B/);
  const high = makeRoam(3, 30, { points: Math.round(19 * (1520 / 60)) });
  assert.equal(C.checkS11(s11({ s11_roam30_c3: high })).status, 'PASS');
  const s = makeRoam(3, 30, { points: Math.round(24 * (1520 / 60)) });
  assert.match(C.checkS11(s11({ s11_roam30_c3: s })).details.join(' | '), /wanted A or B/);
});

test('S11 needs three FIT laps and the roam phase bounds in every plan', () => {
  const r = makeRoam(1, 10);
  r.plans['1'].phases[1].lap = false;
  assert.match(C.checkS11(s11({ s11_roam10_c1: r })).details.join(' | '), /2 lap-true phases, wanted 3/);
  const b = makeRoam(1, 10);
  b.plans['1'].phases[1].max_s = 900;
  assert.match(C.checkS11(s11({ s11_roam10_c1: b })).details.join(' | '), /roam phase 300-900 s/);
});

test('S12 passes on a crew of 3 at 0 W held paused in the drive-out with no kill and grade D', () => {
  const r = C.checkS12({ s12_roam10_c3_zero: zeroRun() });
  assert.equal(r.status, 'PASS', r.details.join(' | '));
  assert.equal(C.checkS12({}).status, 'SKIP');
});

test('S12 fails on a kill by crew fire, a grade above D, a resumed pause or leaving the drive-out', () => {
  for (const [opts, why] of [
    [{ kills: [0] }, /kills by crew fire/],
    [{ grade: 'C' }, /grade C, wanted D/],
    [{ resumed: true }, /pause ended/],
    [{ left: true }, /wanted only the drive-out/],
    [{ reason: 'stop_5s' }, /never paused for all_stopped/],
  ]) {
    const r = C.checkS12({ s12_roam10_c3_zero: zeroRun(opts) });
    assert.equal(r.status, 'FAIL', JSON.stringify(opts));
    assert.match(r.details.join(' | '), why);
  }
  const barrage = C.checkS12({ s12_roam10_c3_zero: zeroRun({ kills: [C.BY_BARRAGE] }) });
  assert.equal(barrage.status, 'PASS', 'a barrage is no crew fire');
});
