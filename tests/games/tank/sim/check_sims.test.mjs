// tests/games/tank/sim/check_sims.test.mjs: unit tests of check_sims.mjs on synthetic reports.
// Each check passes on a clean synthetic run and fails on the exact violation it exists to catch.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import * as C from './check_sims.mjs';

// --- A synthetic report builder -------------------------------------------------------------------------

const SEG_TABLE = [
  ['depot', 0, 'WARMUP', 300],
  ['advance', 1, 'WORK', 180, 90, 300],
  ['gun_line', 1, 'WORK', 120, 60, 180],
  ['checkpoint', 1, 'RECOVERY', 60],
  ['advance', 2, 'WORK', 180, 90, 300],
  ['gun_line', 2, 'WORK', 120, 60, 180],
  ['checkpoint', 2, 'RECOVERY', 60],
  ['advance', 3, 'WORK', 180, 90, 300],
  ['gun_line', 3, 'WORK', 120, 60, 180],
  ['checkpoint', 3, 'RECOVERY', 60],
  ['boss', 4, 'WORK', 240, 120, 360],
];
const DRILL_TABLE = [
  ['depot', 0, 'WARMUP', 30],
  ['skirmish', 1, 'WARMUP', 70],
  ['checkpoint', 1, 'RECOVERY', 30],
];
const ROTATION = {
  1: [['bulwark', 'bulwark', 'bulwark', 'bulwark']],
  2: [['diesel', 'dynamo', 'diesel', 'dynamo'], ['dynamo', 'diesel', 'dynamo', 'diesel']],
  3: [['diesel', 'dynamo', 'steam', 'diesel'], ['dynamo', 'steam', 'diesel', 'dynamo'], ['steam', 'diesel', 'dynamo', 'steam']],
};
const START = { 1: ['bulwark'], 2: ['diesel', 'dynamo'], 3: ['diesel', 'dynamo', 'steam'] };

function engineAt(crew, slot, i, table = SEG_TABLE) {
  const [seg, stage] = table[i];
  if (table === DRILL_TABLE) return START[crew][slot];
  const row = ROTATION[crew][slot];
  if (seg === 'checkpoint') return engineAt(crew, slot, i + 1, table);
  return stage === 0 ? START[crew][slot] : row[stage - 1];
}

function planPhase(crew, slot, i, table = SEG_TABLE) {
  const [seg, stage, kind, dur, min, max] = table[i];
  const engine = engineAt(crew, slot, i, table);
  const drill = table === DRILL_TABLE;
  const meta = { engine, mission: 'ashfall_road', seg, segment: i, stage };
  const base = { duration_s: dur, kind, label: `L${i}`, lap: true, meta };
  if (min !== undefined) Object.assign(base, { min_s: min, max_s: max, open_ended: true });
  if (seg === 'checkpoint') return { ...base, mode: 'ERG', target_pct: 50 };
  if (engine === 'dynamo') {
    if (drill) return seg === 'depot' ? { ...base, mode: 'ERG', target_pct: 50 } : { ...base, mode: 'ERG', target_pct: 55, range_pct: [55, 65] };
    if (seg === 'depot') return { ...base, mode: 'ERG', target_pct: 50, ramp_to_pct: 65 };
    return { ...base, mode: 'ERG', target_pct: 55, range_pct: [55, 100] };
  }
  if (engine === 'steam') return { ...base, mode: 'SIM', grade_source: 'flat' };
  if (seg === 'gun_line') return { ...base, mode: 'ERG', target_pct: 90 };
  return { ...base, mode: 'SIM', grade_source: seg === 'boss' ? 'flat' : 'game' };
}

/**
 * A clean compliant ashfall_road run of `crew` riders. opts: durations {advance, gun_line, boss}
 * (seconds, per run), grade, score, ended {index: how}, dynamoPct (applied % in dynamo fights),
 * events [], directives [], extraRows (fn(row, peer) -> row), seed, role, endReason.
 */
function makeRun(crew, opts = {}) {
  const table = opts.content === 'drill' ? DRILL_TABLE : SEG_TABLE;
  const d = { advance: 200, gun_line: 100, boss: 250, ...(opts.durations ?? {}) };
  const durOf = (i) => {
    const [seg, , , nominal] = table[i];
    return table === DRILL_TABLE ? nominal : d[seg] ?? nominal;
  };
  const starts = [];
  let t = 0;
  table.forEach((_, i) => {
    starts.push(t);
    t += durOf(i);
  });
  const coolStart = t;
  const end = t + 180;
  const slots = [];
  const plans = {};
  const phases = {};
  const trace = {};
  for (let s = 0; s < crew; s += 1) {
    const peer = String(s + 1);
    slots.push({ slot: s, peer: s + 1, is_bot: false, ftp: 200, ftp_verified: true, haptics_on: true, autopilot: true, rider: 'erg:compliance=1.0' });
    const plan = table.map((_, i) => planPhase(crew, s, i, table));
    plan.push({ duration_s: 180, kind: 'COOLDOWN', label: 'Cool-down', lap: true, mode: 'ERG', target_pct: 50 });
    plans[peer] = { phases: plan, cooldown_appended: true };
    phases[peer] = plan.map((ph, i) => ({
      index: i,
      kind: ph.kind,
      mode: ph.mode,
      label: ph.label,
      start: i < table.length ? starts[i] : coolStart,
      end: i < table.length ? (i + 1 < table.length ? starts[i + 1] : coolStart) : end,
      ended_by: opts.ended?.[i] ?? (ph.open_ended ? 'end_phase' : 'duration'),
    }));
    const rows = [];
    for (let sec = 0; sec <= end; sec += 1) {
      const idx = phases[peer].findLastIndex((sp) => sp.start <= sec);
      const ph = plan[idx];
      const fight = ['advance', 'gun_line', 'boss'].includes(ph.meta?.seg) && ph.meta.engine === 'dynamo';
      const pct = ph.mode === 'ERG' ? (fight ? opts.dynamoPct ?? 90 : ph.target_pct) : 0;
      let row = {
        t: sec, game_t: sec, phase: idx, kind: ph.kind, mode: ph.mode, applied_pct: pct, applied_target_w: Math.floor((pct * 200) / 100),
        applied_grade_pct: 0, clamped_by: [], rescue: false, afk: false, paused: false, haptic: 0, power_w: 150, cadence_rpm: 90, connected: true,
      };
      if (opts.extraRows) row = opts.extraRows(row, peer) ?? row;
      rows.push(row);
    }
    trace[peer] = rows;
  }
  const ge = (time, event) => ({ type: 'game_event', t: time, pt: time, event });
  const events = [];
  // Light + medium in each Advance; a heavy in gun lines 2 and 3.
  if (table === SEG_TABLE) SEG_TABLE.forEach((row, i) => {
    if (row[0] === 'advance') {
      events.push(ge(starts[i] + 20, { type: 'shot', s: -1, sh: 5, id: 1, src: 1, e: 1 }));
      events.push(ge(starts[i] + 40, { type: 'shot', s: -1, sh: 5, id: 2, src: 2, e: 2 }));
    }
    if (row[0] === 'gun_line' && row[1] >= 2) events.push(ge(starts[i] + 20, { type: 'shot', s: -1, sh: 5, id: 3, src: 3, e: 5 }));
  });
  // The loader: shots and heavy latches in each gun line / boss: first latch early, the next 24 s after the shot + 6 s.
  const directives = [...(opts.directives ?? [])];
  let id = 100;
  if (crew === 3 && table === SEG_TABLE) {
    SEG_TABLE.forEach((row, i) => {
      if (!['gun_line', 'boss'].includes(row[0])) return;
      const a = starts[i];
      const loader = Number(Object.keys(plans).find((p) => plans[p].phases[i].meta.engine === 'steam') ?? 3);
      events.push(ge(a + 10, { type: 'latch', s: loader - 1, sh: 2 }));
      events.push(ge(a + 20, { type: 'shot', s: 1, sh: 2, id: 10, src: 0, e: 0 }));
      events.push(ge(a + 20 + 6 + 24, { type: 'latch', s: loader - 1, sh: 2 }));
      for (const [tt, g] of [[a + 10, 0], [a + 26, 3], [a + 56, 0], [a + 72, 3]]) {
        directives.push({ id: id++, peer: loader, t: tt, kind: 'request', accepted: true, reason: '', requested: { mode: 'SIM', mode_grade: g, reason: 'boiler', source: 'tank', duration_s: 0 }, applied: { clamped_by: [], refused: false, applied: {} } });
      }
    });
  }
  events.push(...(opts.events ?? []));
  const report = {
    schema: 1,
    game_id: 'tank',
    content_id: opts.content ?? 'ashfall_road',
    role: opts.role ?? (crew >= 2 ? 'HOST' : 'SOLO'),
    seed: opts.seed ?? 1,
    args: { game: 'tank', content: opts.content ?? 'ashfall_road', players: crew, bots: 0, seed: opts.seed ?? 1, riders: ['erg:compliance=1.0'] },
    slots,
    plans,
    plan_warnings: Object.fromEntries(Object.keys(plans).map((p) => [p, []])),
    end_reason: opts.endReason ?? 'complete',
    finished_reason: opts.finished ?? 'victory',
    phases,
    directives,
    directives_unmatched: [],
    trace,
    events,
    snapshots: [{ seq: 1, tick: 0, sha256: 'a', bytes: 200 }, { seq: 2, tick: 2, sha256: 'b', bytes: 210 }],
    max_snapshot_bytes: 900,
    oversize_snapshots: 0,
    results: { grade: opts.grade ?? 'A', score: opts.score ?? 820, rows: [] },
    fit_paths: [],
    deterministic_hash: opts.hash ?? 'hash1',
  };
  return report;
}

const goodSet = (seeds = [1]) => {
  const reports = {};
  for (const c of C.CREWS) for (const s of seeds) reports[`s1_c${c}_seed${s}`] = makeRun(c, { seed: s });
  return reports;
};
const ids = (probs) => probs.join(' | ');

// --- loading and helpers --------------------------------------------------------------------------------

test('loadReports keeps only schema-1 tank reports and names them by file', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tank-sims-'));
  fs.writeFileSync(path.join(dir, 's1_c1_seed1.json'), JSON.stringify(makeRun(1)));
  fs.writeFileSync(path.join(dir, 'other.json'), JSON.stringify({ schema: 1, game_id: 'siege' }));
  fs.writeFileSync(path.join(dir, 'notes.txt'), 'x');
  assert.deepEqual(Object.keys(C.loadReports(dir)), ['s1_c1_seed1']);
  fs.writeFileSync(path.join(dir, 'bad.json'), '{');
  assert.throws(() => C.loadReports(dir), /cannot read/);
});

test('segmentsOf joins the plan and the spans', () => {
  const segs = C.segmentsOf(makeRun(3));
  assert.equal(segs.length, 12);
  assert.deepEqual(segs.slice(0, 3).map((s) => [s.seg, s.stage, s.dur]), [['depot', 0, 300], ['advance', 1, 200], ['gun_line', 1, 100]]);
  assert.equal(segs[11].seg, 'cooldown');
  assert.equal(C.planLaps(makeRun(3)), 12);
  assert.equal(C.phaseIndexAt(makeRun(3), '1', 310), 1);
});

// --- S1 ------------------------------------------------------------------------------------------------------------

test('S1 passes on clean compliant runs for every crew', () => {
  const r = C.checkS1(goodSet(), { seeds: [1] });
  assert.equal(r.status, 'PASS', ids(r.details));
});

test('S1 is skipped with no reports and fails with some missing', () => {
  assert.equal(C.checkS1({}, { seeds: [1] }).status, 'SKIP');
  const r = C.checkS1({ s1_c3_seed1: makeRun(3) }, { seeds: [1] });
  assert.equal(r.status, 'FAIL');
  assert.match(ids(r.details), /missing report s1_c1_seed1/);
});

test('T1 catches a slow Advance, a short gun line, a long boss, an overrun, breakdowns and a low grade', () => {
  assert.deepEqual(C.t1Problems('x', makeRun(3)), []);
  assert.match(ids(C.t1Problems('x', makeRun(3, { durations: { advance: 250 } }))), /advance 1 lasted 250/);
  assert.match(ids(C.t1Problems('x', makeRun(3, { durations: { gun_line: 70 } }))), /gun_line 1 lasted 70/);
  assert.match(ids(C.t1Problems('x', makeRun(3, { durations: { boss: 340 } }))), /boss 4 lasted 340/);
  assert.match(ids(C.t1Problems('x', makeRun(3, { ended: { 2: 'max_s' }, durations: { gun_line: 180 } }))), /gun_line 1 overran/);
  const two = [{ type: 'game_event', t: 400, event: { type: 'breakdown' } }, { type: 'game_event', t: 800, event: { type: 'breakdown' } }];
  assert.match(ids(C.t1Problems('x', makeRun(3, { events: two }))), /2 breakdowns/);
  assert.match(ids(C.t1Problems('x', makeRun(3, { grade: 'C' }))), /grade C/);
  assert.deepEqual(C.t1Problems('x', makeRun(3, { grade: 'B' })), []);
});

test('T2 needs 30 s above 80% per stage, 60 s in the boss, and a return to 65%', () => {
  assert.deepEqual(C.t2Problems('x', makeRun(3)), []);
  assert.deepEqual(C.t2Problems('x', makeRun(2)), []);
  assert.match(ids(C.t2Problems('x', makeRun(3, { dynamoPct: 70 }))), /stage 1: dynamo above 80% for 0 s/);
  // Stays at 90% after the gun line and boss ends: the next phases also read 90.
  const stuck = makeRun(3, {
    extraRows: (row) => (row.kind !== 'COOLDOWN' ? { ...row, applied_pct: 90 } : row),
  });
  assert.match(ids(C.t2Problems('x', stuck)), /stayed above 65%/);
});

test('T3 judges heavy shells: build time, the first-of-segment allowance, the grade-0 rest', () => {
  assert.deepEqual(C.t3Problems('x', makeRun(3)), []);
  const shells = C.heavyShells(makeRun(3));
  assert.ok(shells.length >= 4);
  assert.equal(shells[0].first, true);
  assert.ok(Math.abs(shells[1].buildS - 24) < 1e-6);
  const slow = makeRun(3);
  slow.events = slow.events.map((e) => (e.type === 'game_event' && e.event.type === 'latch' && e.t === 300 + 200 + 20 + 6 + 24 ? { ...e, t: e.t + 20 } : e));
  assert.match(ids(C.t3Problems('x', slow)), /took .* to build/);
  const fast = makeRun(3);
  fast.events = fast.events.map((e) => (e.type === 'game_event' && e.event.type === 'latch' && e.t === 300 + 200 + 20 + 6 + 24 ? { ...e, t: e.t - 12 } : e));
  assert.match(ids(C.t3Problems('x', fast)), /min 18/);
  const noRest = makeRun(3);
  noRest.directives = noRest.directives.map((d) => (d.requested.mode_grade === 3 ? { ...d, t: d.t - 12 } : d));
  assert.match(ids(C.t3Problems('x', noRest)), /boiler grade 0 for only/);
  const none = makeRun(3);
  none.events = none.events.filter((e) => !(e.event && e.event.type === 'latch'));
  assert.match(ids(C.t3Problems('x', none)), /no heavy shell/);
});

test('T4 reads the Bulwark lever share per Advance', () => {
  assert.deepEqual(C.t4Problems('x', makeRun(1)), []);
  const ge = (t, lv) => ({ type: 'game_event', t, event: { type: 'lever', s: 0, lv } });
  // Stage 1 Advance runs 300-500: 100 s on Turret is 50% on Drive.
  const half = makeRun(1, { events: [ge(350, 1), ge(450, 0)] });
  assert.match(ids(C.t4Problems('x', half)), /stage 1 Advance on Drive 50%/);
  const ok = makeRun(1, { events: [ge(350, 1), ge(400, 0)] });
  assert.deepEqual(C.t4Problems('x', ok), []);
  const shares = C.driveShares(makeRun(1, { events: [ge(310, 2)] }));
  assert.equal(shares.length, 3);
  assert.ok(shares[0].share < 0.1 || shares[0].share > 0.9);
});

test('T6 needs a light and a medium per Advance and a 90-180 s heavy duel in gun lines 2 and 3', () => {
  assert.deepEqual(C.t6Problems('x', makeRun(3)), []);
  const noMedium = makeRun(3);
  noMedium.events = noMedium.events.filter((e) => !(e.event?.type === 'shot' && e.event.e === 2));
  assert.match(ids(C.t6Problems('x', noMedium)), /no medium tank/);
  const noLight = makeRun(3);
  noLight.events = noLight.events.filter((e) => !(e.event?.type === 'shot' && e.event.e === 1));
  assert.match(ids(C.t6Problems('x', noLight)), /no light tank/);
  assert.match(ids(C.t6Problems('x', makeRun(3, { durations: { gun_line: 85 } }))), /heavy duel lasted 85/);
  const noHeavy = makeRun(3);
  noHeavy.events = noHeavy.events.filter((e) => !(e.event?.type === 'shot' && e.event.e === 5));
  assert.match(ids(C.t6Problems('x', noHeavy)), /no heavy tank duel/);
  assert.match(ids(C.t6Problems('x', makeRun(3), { requirePrompts: true })), /no "Surge to ram" prompt/);
  const withToast = makeRun(3);
  for (const [a] of [[300], [600], [900]]) withToast.events.push({ type: 'hud', kind: 'toast', key: 'TANK_PROMPT_RAM', peer: 1, t: a + 30 });
  withToast.events.push({ type: 'hud', kind: 'toast', key: 'TANK_PROMPT_RAM', peer: 1, t: 30 });
  const starts = C.segmentsOf(withToast).filter((s) => s.seg === 'advance').map((s) => s.start + 5);
  for (const t of starts) withToast.events.push({ type: 'hud', kind: 'toast', key: 'TANK_PROMPT_RAM', peer: 1, t });
  assert.deepEqual(C.t6Problems('x', withToast, { requirePrompts: true }), []);
});

// --- S2 --------------------------------------------------------------------------------------------------------------

function zeroCrew3() {
  const ended = {};
  const r = makeRun(3, {
    durations: { advance: 300, gun_line: 180, boss: 360 },
    finished: 'withdrawn',
    grade: 'D',
    score: 120,
    extraRows: (row) => (row.t >= 12 ? { ...row, afk: true, power_w: 0, cadence_rpm: 0 } : row),
  });
  r.args.riders = ['zero'];
  r.phases['1'].forEach((sp, i) => {
    if (r.plans['1'].phases[i].open_ended) sp.ended_by = 'max_s';
  });
  void ended;
  return r;
}

function zeroCrew1() {
  const r = makeRun(1, { endReason: 'paused', finished: '', grade: 'D', score: 0 });
  r.phases['1'] = [{ index: 0, kind: 'WARMUP', mode: 'SIM', label: 'L0', start: 0, end: -1, ended_by: '' }];
  r.trace['1'] = r.trace['1'].filter((row) => row.t <= 140).map((row) => ({ ...row, power_w: 0, cadence_rpm: 0 }));
  r.events = [{ type: 'paused', paused: true, reason: 'not_pedaling', t: 10, pt: 10 }];
  return r;
}

test('S2 passes on zero riders: crew 3 overruns every stage as AFK, crew 1 pauses in the depot', () => {
  const r = C.checkS2({ s2_c3_zero: zeroCrew3(), s2_c1_zero: zeroCrew1() });
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.equal(C.checkS2({}).status, 'SKIP');
});

test('S2 fails on a kill by crew fire, a stage that ended on its own, a grade above D and AFK-less riders', () => {
  const kill = zeroCrew3();
  kill.events.push({ type: 'game_event', t: 400, event: { type: 'kill', id: 5, e: 1, by: 0, s: 0 } });
  assert.match(ids(C.checkS2({ s2_c3_zero: kill, s2_c1_zero: zeroCrew1() }).details), /kills by crew fire/);
  const barrage = zeroCrew3();
  barrage.events.push({ type: 'game_event', t: 400, event: { type: 'kill', id: 5, e: 1, by: 2, s: -1 } });
  assert.equal(C.checkS2({ s2_c3_zero: barrage, s2_c1_zero: zeroCrew1() }).status, 'PASS');
  const ended = zeroCrew3();
  ended.phases['1'][1].ended_by = 'end_phase';
  assert.match(ids(C.checkS2({ s2_c3_zero: ended, s2_c1_zero: zeroCrew1() }).details), /advance 1 ended by end_phase/);
  const graded = zeroCrew3();
  graded.results.grade = 'C';
  assert.match(ids(C.checkS2({ s2_c3_zero: graded, s2_c1_zero: zeroCrew1() }).details), /grade C/);
  const awake = zeroCrew3();
  for (const row of awake.trace['2']) row.afk = false;
  assert.match(ids(C.checkS2({ s2_c3_zero: awake, s2_c1_zero: zeroCrew1() }).details), /peer 2 never went AFK/);
});

test('S2 crew 1: paused late, not paused, more than the depot, a kill or a grade fail', () => {
  const late = zeroCrew1();
  late.events[0].pt = 10.2;
  assert.match(ids(C.checkS2({ s2_c1_zero: late }).details), /paused at 10.2/);
  const edge = zeroCrew1();
  edge.events[0].pt = 10.05;
  assert.equal(C.checkS2({ s2_c3_zero: zeroCrew3(), s2_c1_zero: edge }).status, 'PASS', 'one tick of slack');
  const never = zeroCrew1();
  never.events = [];
  assert.match(ids(C.checkS2({ s2_c1_zero: never }).details), /never paused/);
  const more = zeroCrew1();
  more.phases['1'].push({ index: 1, kind: 'WORK', mode: 'SIM', label: 'L1', start: 300, end: -1, ended_by: '' });
  assert.match(ids(C.checkS2({ s2_c1_zero: more }).details), /2 phases started/);
  const wrong = zeroCrew1();
  wrong.end_reason = 'complete';
  assert.match(ids(C.checkS2({ s2_c1_zero: wrong }).details), /end_reason complete/);
  const kills = zeroCrew1();
  kills.events.push({ type: 'game_event', t: 5, event: { type: 'kill', id: 1, e: 1, by: 0, s: 0 } });
  assert.match(ids(C.checkS2({ s2_c1_zero: kills }).details), /kills in a paused run/);
});

// --- S3 --------------------------------------------------------------------------------------------------------------

test('S3 needs the mean score to fall strictly from 100% to 85% to 70%', () => {
  const set = (a, b, c) => ({
    s1_c3_seed1: makeRun(3, { score: a }),
    s3_c3_c85_seed1: makeRun(3, { score: b }),
    s3_c3_c70_seed1: makeRun(3, { score: c }),
  });
  assert.equal(C.checkS3(set(800, 700, 600), { seeds: [1] }).status, 'PASS');
  assert.match(ids(C.checkS3(set(800, 800, 600), { seeds: [1] }).details), /not above 85%/);
  assert.match(ids(C.checkS3(set(800, 700, 700), { seeds: [1] }).details), /not above 70%/);
  assert.match(ids(C.checkS3({ s1_c3_seed1: makeRun(3), s3_c3_c85_seed1: makeRun(3, { score: 1 }) }, { seeds: [1] }).details), /missing report s3_c3_c70_seed1/);
  assert.equal(C.checkS3({}, { seeds: [1] }).status, 'SKIP');
});

// --- S4 --------------------------------------------------------------------------------------------------------------

const req = (peer, t, requested, extra = {}) => ({ id: extra.id ?? 1, peer, t, kind: 'request', accepted: true, reason: '', requested: { source: 'tank', duration_s: 0, ...requested }, applied: { clamped_by: [], refused: false, applied: {} }, ...extra });
const dirOf = (dirs, crew = 3, over = {}) => C.directivesProblems('x', makeRun(crew, { directives: dirs, ...over }));

test('S4 passes on directives that match brief 2.3 and 2.7', () => {
  const dirs = [
    req(2, 310, { mode: 'ERG', target_pct: 70, reason: 'bank' }),
    req(3, 700, { mode: 'SIM', mode_grade: 6, reason: 'boiler' }),
    req(1, 400, { mode: 'SIM', haptic: 2.0, duration_s: 1.5, reason: 'hit' }),
    req(1, 1400, { mode: 'SIM', haptic: 3.0, duration_s: 2.0, reason: 'boss_hit' }),
    { id: 7, peer: 1, t: 320, kind: 'course_grade', requested: { grade_pct: 2 }, accepted: true, applied: null },
    { id: 8, peer: 1, t: 300, kind: 'cadence_band', requested: { lo_rpm: 60, hi_rpm: 120 }, accepted: true, applied: null },
    { id: 9, peer: 1, t: 480, kind: 'end_phase', requested: {}, accepted: true, applied: null },
  ];
  assert.deepEqual(dirOf(dirs), []);
  assert.deepEqual(dirOf([req(1, 450, { mode: 'SIM', mode_grade: 4, reason: 'hoist' })], 1), []);
});

test('S4 rejects directives outside brief 2.3 and 2.7', () => {
  assert.match(ids(dirOf([req(1, 400, { mode: 'ERG', target_pct: 80, reason: 'surprise' })])), /matches no pattern/);
  // A SIM-mode directive in an ERG phase: the diesel's gun line (phase 2 is 400-500 for peer 1: ERG 90).
  assert.match(ids(dirOf([req(1, 560, { mode: 'SIM', mode_grade: 3, reason: 'boiler' })])), /ERG phase/);
  assert.match(ids(dirOf([req(1, 560, { mode: 'SIM', haptic: 2.0, duration_s: 1.5, reason: 'hit' })])), /haptic to an ERG rider|SIM-mode\) in an ERG/);
  assert.match(ids(dirOf([req(2, 310, { mode: 'ERG', target_pct: 105, reason: 'bank' })])), /outside range_pct|outside 50-100/);
  assert.match(ids(dirOf([req(2, 310, { mode: 'ERG', target_pct: 60, reason: 'bank' })], 3, {})), /^$/);
  assert.match(ids(dirOf([req(2, 5, { mode: 'ERG', target_pct: 60, reason: 'bank' })])), /without range_pct/);
  assert.match(ids(dirOf([req(3, 700, { mode: 'SIM', mode_grade: 9, reason: 'boiler' })])), /boiler grade 9%/);
  assert.match(ids(dirOf([req(3, 100, { mode: 'SIM', mode_grade: 4, reason: 'boiler' })])), /boiler grade 4% \(max 3%\)|ERG phase/);
  assert.match(ids(dirOf([req(1, 400, { mode: 'SIM', haptic: 2.5, duration_s: 1.5, reason: 'hit' })])), /haptic 2.5/);
  assert.match(ids(dirOf([req(3, 200, { mode: 'SIM', haptic: 2.0, duration_s: 1.5, reason: 'hit' })])), /haptic in a WARMUP phase|first 300 s/);
  assert.match(ids(dirOf([req(1, 1800, { mode: 'ERG', target_pct: 50, reason: 'bank' })])), /cool-down/);
  const unclamped = req(3, 700, { mode: 'SIM', mode_grade: 6, reason: 'boiler' });
  unclamped.applied = null;
  assert.match(ids(dirOf([unclamped])), /not clamped/);
  assert.match(ids(dirOf([{ id: 3, peer: 1, t: 400, kind: 'cadence_band', requested: { lo_rpm: 40, hi_rpm: 120 }, accepted: true, applied: null }])), /band 40-120/);
  assert.match(ids(dirOf([{ id: 3, peer: 3, t: 400, kind: 'course_grade', requested: { grade_pct: 1 }, accepted: true, applied: null }])), /terrain outside/);
  assert.match(ids(dirOf([{ id: 3, peer: 1, t: 100, kind: 'end_phase', requested: {}, accepted: true, applied: null }])), /end_phase on a fixed phase/);
});

test('S4 holds haptics to SIM riders, outside the first 300 s, to riders who opted in', () => {
  const optedOut = makeRun(3, { directives: [req(1, 400, { mode: 'SIM', haptic: 2.0, duration_s: 1.5, reason: 'hit' })] });
  optedOut.slots[0].haptics_on = false;
  assert.match(ids(C.directivesProblems('x', optedOut)), /opted out/);
  optedOut.directives[0].accepted = false;
  assert.deepEqual(C.directivesProblems('x', optedOut).filter((p) => /opted out/.test(p)), []);
});

test('S4 plan, trace, switch and lap rules', () => {
  assert.deepEqual(C.planProblems('x', makeRun(3)), []);
  const hot = makeRun(2);
  hot.plans['2'].phases[1].range_pct = [55, 110];
  assert.match(ids(C.planProblems('x', hot)), /above 100% FTP/);
  assert.deepEqual(C.traceProblems('x', makeRun(3)), []);
  const over = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.t === 600 && row.mode === 'ERG' ? { ...row, applied_pct: 106 } : row) });
  assert.match(ids(C.traceProblems('x', over)), /applied ERG 106% FTP at 600 s/);
  const early = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.t === 100 ? { ...row, haptic: 2 } : row) });
  assert.match(ids(C.traceProblems('x', early)), /haptic 2 applied at 100 s/);
  const inErg = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.t === 550 ? { ...row, haptic: 2 } : row) });
  assert.match(ids(C.traceProblems('x', inErg)), /haptic applied in ERG/);
  const cool = makeRun(3, { extraRows: (row, peer) => (peer === '2' && row.t === 1700 ? { ...row, haptic: 2, mode: 'SIM' } : row) });
  assert.match(ids(C.traceProblems('x', cool)), /cool-down/);
  // A SIM -> ERG entry above the planned target: peer 1 enters the gun line (ERG 90% = 180 W) at 400 s.
  const spike = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.phase === 2 && row.t <= 502 ? { ...row, applied_target_w: 190 } : row) });
  assert.match(ids(C.traceProblems('x', spike)), /entered ERG at 500 s with 190 W/);
  const fine = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.phase === 2 && row.t <= 502 ? { ...row, applied_target_w: 180 } : row) });
  assert.deepEqual(C.traceProblems('x', fine), []);
  // Two switches 30 s apart: an ERG blip inside the SIM Advance.
  const quick = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.t >= 350 && row.t < 380 ? { ...row, mode: 'ERG' } : row) });
  assert.match(ids(C.traceProblems('x', quick)), /< 60 s/);
  assert.deepEqual(C.lapProblems('x', makeRun(3)), []);
  const lap = makeRun(3);
  lap.plans['1'].phases[3].lap = false;
  assert.match(ids(C.lapProblems('x', lap)), /11 lap-true phases, wanted 12|lap false/);
  assert.deepEqual(C.lapProblems('x', { ...makeRun(1), content_id: 'other' }), []);
});

test('S4 on the drill: at most one mode switch per rider, 4 laps', () => {
  const drill = makeRun(1, { content: 'drill' });
  assert.equal(C.planLaps(drill), 4);
  assert.deepEqual(C.lapProblems('x', drill), []);
  const ds = C.checkS4({ s4_drill_c1: drill }, { seeds: [1] });
  assert.doesNotMatch(ids(ds.details), /switches|lap/);
  const noisy = makeRun(1, { content: 'drill', extraRows: (row) => (row.t >= 10 && row.t < 20 ? { ...row, mode: 'ERG' } : row) });
  assert.match(ids(C.checkS4({ s4_drill_c1: noisy }, { seeds: [1] }).details), /switches [0-9]+ times/);
});

test('S4 as a whole: clean runs pass; refused directives, warnings and oversize snapshots fail', () => {
  const set = goodSet();
  assert.equal(C.checkS4(set, { seeds: [1] }).status, 'FAIL', 'the drill reports are missing');
  const full = { ...set };
  for (const c of C.CREWS) full[`s4_drill_c${c}`] = makeRun(c, { content: 'drill' });
  const clean = C.checkS4(full, { seeds: [1] });
  assert.equal(clean.status, 'PASS', ids(clean.details));
  const bad = structuredClone(full);
  bad.s1_c3_seed1.plan_warnings['1'] = ['switch within 30 s'];
  bad.s1_c3_seed1.max_snapshot_bytes = 5000;
  bad.s1_c3_seed1.directives.push({ id: 900, peer: 1, t: 10, kind: 'cadence_band', requested: { lo_rpm: 60, hi_rpm: 120 }, accepted: false, reason: 'cooldown', applied: null });
  const r = C.checkS4(bad, { seeds: [1] });
  assert.equal(r.status, 'FAIL');
  assert.match(ids(r.details), /plan warnings/);
  assert.match(ids(r.details), /largest snapshot 5000/);
  assert.match(ids(r.details), /refused: cooldown/);
});

// --- S5 --------------------------------------------------------------------------------------------------------------

/** A run where `peer` is in rescue from `from` to `to` seconds (applied 50% FTP, clamped by rescue). */
function rescueRun(peer, phaseStart, from, to) {
  return makeRun(3, {
    extraRows: (row, p) => (p === peer && row.t >= from && row.t < to ? { ...row, rescue: true, applied_pct: 50, clamped_by: ['rescue'] } : row),
  });
}

test('S5 passes when the collapsing rider enters rescue in the right phase, recovers, and the plan continues', () => {
  const set = { s5_c3_dynamo_drop: rescueRun('2', 500, 520, 560), s5_c3_gunline_drop: rescueRun('1', 500, 520, 560) };
  const r = C.checkS5(set);
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.equal(C.checkS5({}).status, 'SKIP');
});

test('S5 fails without rescue, with rescue that never ends, at the wrong power, and when the plan stops', () => {
  const ok = rescueRun('2', 500, 520, 560);
  const gl = rescueRun('1', 500, 520, 560);
  assert.match(ids(C.checkS5({ s5_c3_dynamo_drop: makeRun(3), s5_c3_gunline_drop: gl }).details), /never entered rescue/);
  const endless = rescueRun('2', 500, 520, 99999);
  assert.match(ids(C.checkS5({ s5_c3_dynamo_drop: endless, s5_c3_gunline_drop: gl }).details), /rescue never ended/);
  const strong = makeRun(3, { extraRows: (row, p) => (p === '2' && row.t >= 520 && row.t < 560 ? { ...row, rescue: true, applied_pct: 70, clamped_by: ['rescue'] } : row) });
  assert.match(ids(C.checkS5({ s5_c3_dynamo_drop: strong, s5_c3_gunline_drop: gl }).details), /rescue applied 70% FTP/);
  const stopped = rescueRun('2', 500, 520, 560);
  stopped.phases['2'] = stopped.phases['2'].slice(0, 5);
  assert.match(ids(C.checkS5({ s5_c3_dynamo_drop: stopped, s5_c3_gunline_drop: gl }).details), /plan phases ran/);
  const bystander = rescueRun('2', 500, 520, 560);
  for (const row of bystander.trace["3"]) if (row.t === 525) row.rescue = true;
  assert.match(ids(C.checkS5({ s5_c3_dynamo_drop: bystander, s5_c3_gunline_drop: gl }).details), /peer 3 \(not the collapsing rider\)/);
  const unclamped = makeRun(3, { extraRows: (row, p) => (p === '2' && row.t >= 520 && row.t < 560 ? { ...row, rescue: true, applied_pct: 50 } : row) });
  assert.match(ids(C.checkS5({ s5_c3_dynamo_drop: unclamped, s5_c3_gunline_drop: gl }).details), /clamped by rescue/);
  const wrongPhase = makeRun(3, { extraRows: (row, p) => (p === '1' && row.t >= 320 && row.t < 360 ? { ...row, rescue: true, applied_pct: 50, clamped_by: ["rescue"] } : row) });
  assert.match(ids(C.checkS5({ s5_c3_dynamo_drop: ok, s5_c3_gunline_drop: wrongPhase }).details), /rescue began before phase 2/);
});

// --- S6 / S7 ---------------------------------------------------------------------------------------------------------

test('S6 passes with no haptic applied to the opted-out slot and fails with one', () => {
  const clean = makeRun(3, { extraRows: (row, peer) => (peer === '2' && row.t === 800 ? { ...row, haptic: 2 } : row) });
  clean.slots[0].haptics_on = false;
  clean.args.haptics_off = [0];
  const r = C.checkS6({ s6_c3_haptics_off: clean });
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.match(r.summary, /1 haptic seconds felt/);
  const leak = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.t === 800 ? { ...row, haptic: 2 } : row) });
  leak.slots[0].haptics_on = false;
  assert.match(ids(C.checkS6({ s6_c3_haptics_off: leak }).details), /peer 1 had a haptic applied at 800/);
  const applied = makeRun(3, { directives: [req(1, 800, { mode: 'SIM', haptic: 2.0, duration_s: 1.5, reason: 'hit' }, { applied: { clamped_by: [], refused: false, applied: { haptic: 2 } } })] });
  applied.slots[0].haptics_on = false;
  assert.match(ids(C.checkS6({ s6_c3_haptics_off: applied }).details), /applied to peer 1/);
  const nobody = makeRun(3);
  assert.match(ids(C.checkS6({ s6_c3_haptics_off: nobody }).details), /0 slots with haptics off/);
  assert.equal(C.checkS6({}).status, 'SKIP');
});

test('S7 compares the deterministic hash, the game events and the snapshot hashes', () => {
  const a = makeRun(3);
  const b = makeRun(3);
  assert.equal(C.checkS7({ s1_c3_seed1: a, s7_c3_seed1: b }).status, 'PASS');
  assert.equal(C.checkS7({ s1_c3_seed1: a }).status, 'SKIP');
  assert.match(ids(C.checkS7({ s7_c3_seed1: b }).details), /missing report s1_c3_seed1/);
  const h = makeRun(3, { hash: 'other' });
  assert.match(ids(C.checkS7({ s1_c3_seed1: a, s7_c3_seed1: h }).details), /deterministic_hash differs/);
  const ev = makeRun(3);
  ev.events.push({ type: 'game_event', t: 5, event: { type: 'hit', on: 0, id: 0, dmg: 5, sh: 5, b: 0, x: 0 } });
  assert.match(ids(C.checkS7({ s1_c3_seed1: a, s7_c3_seed1: ev }).details), /game events differ/);
  const sn = makeRun(3);
  sn.snapshots[1].sha256 = 'zzz';
  assert.match(ids(C.checkS7({ s1_c3_seed1: a, s7_c3_seed1: sn }).details), /snapshot 1 \(tick 2\) differs/);
  const short = makeRun(3);
  short.snapshots.pop();
  assert.match(ids(C.checkS7({ s1_c3_seed1: a, s7_c3_seed1: short }).details), /1 snapshots|2 vs 1 snapshots/);
  const other = makeRun(3);
  other.args.seed = 9;
  assert.match(ids(C.checkS7({ s1_c3_seed1: a, s7_c3_seed1: other }).details), /not started with the same arguments/);
});

// --- FIT, arguments, main ----------------------------------------------------------------------------------------------

test('fitGroups groups existing FIT files by expected laps and skips what is not there', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tank-fit-'));
  fs.mkdirSync(path.join(dir, 'fit'));
  fs.writeFileSync(path.join(dir, 'fit', 's1_c1_seed1_slot0.fit'), 'x');
  fs.writeFileSync(path.join(dir, 'fit', 's2_c1_zero_slot0.fit'), 'x');
  const reports = { s1_c1_seed1: makeRun(1), s2_c1_zero: zeroCrew1(), s4_drill_c1: makeRun(1, { content: 'drill' }) };
  const groups = C.fitGroups(reports, dir);
  assert.deepEqual([...groups.keys()].sort(), ['12', 'none']);
  assert.equal(groups.get('12').length, 1);
  assert.equal(C.checkFit({}, dir, dir).status, 'SKIP');
});

test('parseArgs and runChecks', () => {
  assert.throws(() => C.parseArgs([]), /usage/);
  assert.throws(() => C.parseArgs(['d', '--nope']), /unknown option/);
  assert.throws(() => C.parseArgs(['d', '--only=S9']), /unknown scenario/);
  const o = C.parseArgs(['d', '--only=s1,S7', '--seeds=1,2', '--fit', '--require-prompts']);
  assert.deepEqual(o.only, ['S1', 'S7']);
  assert.deepEqual(o.seeds, [1, 2]);
  assert.equal(o.fit, true);
  const results = C.runChecks({}, { only: ['S2', 'S6'], seeds: [1] }, '.', '.');
  assert.deepEqual(results.map((r) => r.id), ['S2', 'S6']);
  assert.ok(results.every((r) => r.status === 'SKIP'));
});

test('main exits 2 on bad usage, 0 on all-skip, 1 on a failing scenario', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tank-main-'));
  const out = process.stdout.write;
  process.stdout.write = () => true;
  const err = process.stderr.write;
  process.stderr.write = () => true;
  try {
    assert.equal(C.main([]), 2);
    assert.equal(C.main([path.join(dir, 'nope')]), 2);
    assert.equal(C.main([dir]), 0);
    fs.writeFileSync(path.join(dir, 's7_c3_seed1.json'), JSON.stringify(makeRun(3)));
    assert.equal(C.main([dir, '--only=S7']), 1, 'S7 without s1_c3_seed1 fails');
  } finally {
    process.stdout.write = out;
    process.stderr.write = err;
  }
});
