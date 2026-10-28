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
// v3: one tank, every slot on its start seat for the whole plan (no rotation; seat switches replan).
const START = { 1: ['diesel'], 2: ['diesel', 'dynamo'], 3: ['diesel', 'dynamo', 'steam'], 4: ['diesel', 'dynamo', 'steam', 'arc'] };

function engineAt(crew, slot) {
  return START[crew][slot];
}

function planPhase(crew, slot, i, table = SEG_TABLE) {
  const [seg, stage, kind, dur, min, max] = table[i];
  const engine = engineAt(crew, slot);
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
  if (engine === 'arc') {
    if (drill) return seg === 'depot' ? { ...base, mode: 'ERG', target_pct: 50 } : { ...base, mode: 'ERG', target_pct: 55, range_pct: [55, 65] };
    if (seg === 'depot') return { ...base, mode: 'ERG', target_pct: 50, ramp_to_pct: 65 };
    return { ...base, mode: 'ERG', target_pct: 65, range_pct: [65, 80] };
  }
  if (engine === 'steam' || engine === 'feed') return { ...base, mode: 'SIM', grade_source: 'flat' };
  // v3: Drive digs in at a gun line in SIM flat.
  return { ...base, mode: 'SIM', grade_source: seg === 'boss' || seg === 'gun_line' ? 'flat' : 'game' };
}

/**
 * A clean compliant ashfall_road run of `crew` riders. opts: durations {advance, gun_line, boss}
 * (seconds, per run), grade, score, ended {index: how}, dynamoPct (applied % in dynamo fights), arcPct (in arc fights),
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
      const fighting = ['advance', 'gun_line', 'boss'].includes(ph.meta?.seg);
      const fight = fighting && ph.meta.engine === 'dynamo';
      const arcFight = fighting && ph.meta.engine === 'arc';
      const pct = ph.mode === 'ERG' ? (fight ? opts.dynamoPct ?? 90 : arcFight ? opts.arcPct ?? 76 : ph.target_pct) : 0;
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
  // A telegraphed shot (light flank shot: evade then shot) + a medium in each Advance; a heavy in gun lines 2 and 3.
  if (table === SEG_TABLE) SEG_TABLE.forEach((row, i) => {
    if (row[0] === 'advance') {
      events.push(ge(starts[i] + 20, { type: 'evade', id: 1, e: 1, ok: 0, s: -1 }));
      events.push(ge(starts[i] + 20, { type: 'shot', s: -1, sh: 5, id: 1, src: 1, e: 1 }));
      events.push(ge(starts[i] + 40, { type: 'shot', s: -1, sh: 5, id: 2, src: 2, e: 2 }));
    }
    if (row[0] === 'gun_line' && row[1] >= 2) events.push(ge(starts[i] + 20, { type: 'shot', s: -1, sh: 5, id: 3, src: 3, e: 5 }));
  });
  // The Loader (v3, slot 2): three shells stowed 7 s apart in each Advance, gun line and the boss, with the boiler
  // grade rising and dropping; the Gun (slot 1) fires in each gun line and the boss.
  const directives = [...(opts.directives ?? [])];
  let id = 100;
  if (crew >= 3 && table === SEG_TABLE) {
    SEG_TABLE.forEach((row, i) => {
      if (!['advance', 'gun_line', 'boss'].includes(row[0])) return;
      const a = starts[i];
      for (const k of [0, 1, 2]) events.push(ge(a + 10 + 7 * k, { type: 'latch', s: 2, sh: 2 }));
      if (row[0] !== 'advance') events.push(ge(a + 40, { type: 'shot', s: 1, sh: 2, id: 10, src: 0, e: 0 }));
      for (const [tt, g] of [[a + 10, 0], [a + 14, 3], [a + 17, 0], [a + 21, 3]]) {
        directives.push({ id: id++, peer: 3, t: tt, kind: 'request', accepted: true, reason: '', requested: { mode: 'SIM', mode_grade: g, reason: 'boiler', source: 'tank', duration_s: 0 }, applied: { clamped_by: [], refused: false, applied: {} } });
      }
    });
  }
  // The solo loop (v3): the solo rider fires twice in each gun line.
  if (crew === 1 && table === SEG_TABLE) {
    SEG_TABLE.forEach((row, i) => {
      if (row[0] !== 'gun_line') return;
      for (const k of [0, 1]) events.push(ge(starts[i] + 30 + 20 * k, { type: 'shot', s: 0, sh: 2, id: 20 + k, src: 0, e: 0 }));
    });
  }
  // Crew 1's host rider drives in SIM: its "Surge to evade" prompt shows in every Advance (the report's hud log is the host rider's).
  if (crew === 1 && table === SEG_TABLE) {
    SEG_TABLE.forEach((row, i) => {
      if (row[0] === 'advance') events.push({ type: 'hud', kind: 'toast', key: 'TANK_PROMPT_EVADE', peer: 1, t: starts[i] + 5 });
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

/** Crew 3 where peer 1 moves from Drive to the Loader's seat 100 s into the stage 1 Advance (v3: a split phase). */
function splitRun() {
  const r = makeRun(3);
  const plan = r.plans['1'].phases;
  const rest = { ...plan[1], lap: false, mode: 'SIM', grade_source: 'flat', min_s: 0.05, max_s: 200, meta: { ...plan[1].meta, engine: 'feed', offset_s: 100 } };
  plan.splice(2, 0, rest);
  const spans = r.phases['1'];
  const adv = spans[1];
  const second = { ...adv, index: 2, start: adv.start + 100 };
  adv.end = adv.start + 100;
  adv.ended_by = 'end_phase';
  spans.splice(2, 0, second);
  for (let i = 3; i < spans.length; i += 1) spans[i].index = i;
  for (const row of r.trace['1']) if (row.phase >= 2 || (row.phase === 1 && row.t >= adv.end)) row.phase += 1;
  r.events.push({ type: 'game_event', t: adv.end, pt: adv.end, event: { type: 'seat', s: 0, from: 1, to: 6 } });
  return r;
}

test('segmentsOf merges a split segment (v3 seats); phaseSpansOf keeps its phases', () => {
  const r = splitRun();
  const segs = C.segmentsOf(r, '1');
  assert.equal(segs.length, 12, 'still one entry per segment');
  assert.deepEqual([segs[1].seg, segs[1].dur, segs[1].phases.length], ['advance', 200, 2]);
  assert.deepEqual(segs[1].phases.map((p) => p.engine), ['diesel', 'feed']);
  assert.equal(segs[2].seg, 'gun_line');
  assert.equal(C.phaseSpansOf(r, '1').length, 13);
  assert.equal(C.planLaps(r, '1'), 12, 'the split continues the lap');
  assert.deepEqual(C.lapProblems('x', r), []);
  const bad = splitRun();
  delete bad.plans['1'].phases[2].meta.offset_s;
  assert.match(ids(C.lapProblems('x', bad)), /lap false that is no split/);
  assert.deepEqual(C.t1Problems('x', r), []);
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
  assert.match(ids(C.t1Problems('x', makeRun(3, { durations: { advance: 290 } }))), /advance 1 lasted 290/);
  assert.match(ids(C.t1Problems('x', makeRun(3, { durations: { gun_line: 170 } }))), /gun_line 1 lasted 170/);
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

test('T3 (v3) needs 3 shells stowed per stage and about 7 s a shell back to back', () => {
  assert.deepEqual(C.t3Problems('x', makeRun(3)), []);
  const st = C.loaderStows(makeRun(3));
  assert.equal(st.perStage[1], 6, 'Advance and gun line');
  assert.ok(st.gaps.every((g) => Math.abs(g - 7) < 1e-6));
  const few = makeRun(3);
  few.events = few.events.filter((e) => !(e.event?.type === 'latch' && e.t > 300 && e.t < 600 && e.t !== 310));
  assert.match(ids(C.t3Problems('x', few)), /stage 1: 1 shells stowed \(need 3\)/);
  const fast = makeRun(3);
  for (const e of fast.events) if (e.event?.type === 'latch') e.t = Math.floor(e.t / 7) * 7 + (e.t % 7) / 4;
  const slow = makeRun(3);
  const lat = slow.events.filter((e) => e.event?.type === 'latch');
  lat.forEach((e, k) => {
    e.t += (k % 3) * 6;
  });
  assert.match(ids(C.t3Problems('x', slow)), /a shell takes 13 s at the median/);
  const none = makeRun(3);
  none.events = none.events.filter((e) => e.event?.type !== 'latch');
  assert.match(ids(C.t3Problems('x', none)), /no back-to-back stows/);
});

test('T4 (v3) reads the solo loop: Drive share per Advance, main-gun shells or a bow kill per gun line', () => {
  assert.deepEqual(C.t4Problems('x', makeRun(1)), []);
  // Stage 1 Advance 300-500: the solo rider leaves Drive for the Loader at 330 s and comes back at 470 s (30% on Drive).
  const r = makeRun(1);
  const plan = r.plans['1'].phases;
  const spans = r.phases['1'];
  const adv = spans[1];
  plan.splice(2, 0, { ...plan[1], lap: false, mode: 'SIM', grade_source: 'flat', meta: { ...plan[1].meta, engine: 'steam', offset_s: 30 } });
  plan.splice(3, 0, { ...plan[1], lap: false, meta: { ...plan[1].meta, offset_s: 170 } });
  spans.splice(2, 0, { ...adv, index: 2, start: 330, end: 470 }, { ...adv, index: 3, start: 470, end: adv.end });
  adv.end = 330;
  for (let i = 4; i < spans.length; i += 1) spans[i].index = i;
  assert.match(ids(C.t4Problems('x', r)), /stage 1 Advance on Drive 30%/);
  const quiet = makeRun(1);
  quiet.events = quiet.events.filter((e) => !(e.event?.type === 'shot' && e.event.s === 0));
  assert.match(ids(C.t4Problems('x', quiet)), /stage 1 gun line: 0 main-gun shells fired and no bow-gun kill/);
  const gl1 = C.segmentsOf(quiet).find((s) => s.seg === 'gun_line' && s.stage === 1);
  quiet.events.push({ type: 'game_event', t: gl1.start + 5, pt: gl1.start + 5, event: { type: 'kill', id: 99, e: 4, by: 3, s: 0 } });
  assert.doesNotMatch(ids(C.t4Problems('x', quiet)), /stage 1 gun line/, 'the bow guns worked it');
  assert.equal(C.soloLoop(makeRun(1)).filter((x) => x.seg === 'gun_line').length, 3);
});

test('T6 needs a telegraphed shot and a medium per Advance and a 90-180 s heavy duel in gun lines 2 and 3', () => {
  assert.deepEqual(C.t6Problems('x', makeRun(3)), []);
  const noMedium = makeRun(3);
  noMedium.events = noMedium.events.filter((e) => !(e.event?.type === 'shot' && e.event.e === 2));
  assert.match(ids(C.t6Problems('x', noMedium)), /no medium tank/);
  const noTelegraph = makeRun(3);
  noTelegraph.events = noTelegraph.events.filter((e) => e.event?.type !== 'evade');
  assert.match(ids(C.t6Problems('x', noTelegraph)), /no telegraphed shot/);
  assert.match(ids(C.t6Problems('x', makeRun(3, { durations: { gun_line: 185 } }))), /heavy duel lasted 185/);
  const noHeavy = makeRun(3);
  noHeavy.events = noHeavy.events.filter((e) => !(e.event?.type === 'shot' && e.event.e === 5));
  assert.match(ids(C.t6Problems('x', noHeavy)), /no heavy tank duel/);
  assert.match(ids(C.t6Problems('x', makeRun(3), { requirePrompts: true })), /no "Surge to evade" prompt/);
  const withToast = makeRun(3);
  withToast.events.push({ type: 'hud', kind: 'toast', key: 'TANK_PROMPT_EVADE', peer: 1, t: 30 });
  const starts = C.segmentsOf(withToast).filter((s) => s.seg === 'advance').map((s) => s.start + 5);
  for (const t of starts) withToast.events.push({ type: 'hud', kind: 'toast', key: 'TANK_PROMPT_EVADE', peer: 1, t });
  assert.deepEqual(C.t6Problems('x', withToast, { requirePrompts: true }), []);
});

// --- S2 --------------------------------------------------------------------------------------------------------------

/** Crew 3 at 0 W: the shared pause (all_stopped) holds the depot until max_sim_seconds. */
function zeroCrew3() {
  const r = makeRun(3, { endReason: 'timeout', finished: '', grade: 'D', score: 0 });
  r.args.riders = ['zero'];
  for (const peer of ['1', '2', '3']) {
    r.phases[peer] = [{ index: 0, kind: 'WARMUP', mode: 'SIM', label: 'L0', start: 0, end: -1, ended_by: '' }];
    r.trace[peer] = r.trace[peer].filter((row) => row.t <= 300).map((row) => ({ ...row, power_w: 0, cadence_rpm: 0, paused: row.t >= 6 }));
  }
  r.events = [{ type: 'paused', paused: true, reason: 'all_stopped', t: 6.25, pt: 6.25 }];
  return r;
}

/** Crew 3 spinning at 10 W: every stage overruns, withdrawn, grade D, never paused. */
function idleCrew3() {
  const r = makeRun(3, {
    durations: { advance: 300, gun_line: 180, boss: 360 },
    finished: 'withdrawn',
    grade: 'D',
    score: 120,
    extraRows: (row) => ({ ...row, power_w: 10, cadence_rpm: 25 }),
  });
  r.args.riders = ['const:w=10,rpm=25'];
  for (const peer of ['1', '2', '3']) {
    r.phases[peer].forEach((sp, i) => {
      if (r.plans[peer].phases[i].open_ended) sp.ended_by = 'max_s';
    });
  }
  return r;
}

function zeroCrew1() {
  const r = makeRun(1, { endReason: 'paused', finished: '', grade: 'D', score: 0 });
  r.phases['1'] = [{ index: 0, kind: 'WARMUP', mode: 'SIM', label: 'L0', start: 0, end: -1, ended_by: '' }];
  r.trace['1'] = r.trace['1'].filter((row) => row.t <= 140).map((row) => ({ ...row, power_w: 0, cadence_rpm: 0 }));
  r.events = [{ type: 'paused', paused: true, reason: 'stop_5s', t: 10, pt: 10 }];
  return r;
}

const allS2 = (over = {}) => ({ s2_c3_zero: zeroCrew3(), s2_c3_idle: idleCrew3(), s2_c1_zero: zeroCrew1(), ...over });

test('S2 passes on zero riders: crew 3 held in the depot by the shared pause, crew 3 at 10 W overruns, crew 1 pauses', () => {
  const r = C.checkS2(allS2());
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.equal(C.checkS2({}).status, 'SKIP');
  assert.match(ids(C.checkS2({ s2_c3_zero: zeroCrew3(), s2_c1_zero: zeroCrew1() }).details), /missing report s2_c3_idle/);
});

test('S2 crew 3 at 0 W fails when the run completes, leaves the depot, never pauses for all_stopped, resumes, kills or grades above D', () => {
  const done = zeroCrew3();
  done.end_reason = 'complete';
  assert.match(ids(C.checkS2(allS2({ s2_c3_zero: done })).details), /s2_c3_zero: end_reason complete, wanted timeout/);
  const more = zeroCrew3();
  more.phases['1'].push({ index: 1, kind: 'WORK', mode: 'SIM', label: 'L1', start: 300, end: -1, ended_by: '' });
  assert.match(ids(C.checkS2(allS2({ s2_c3_zero: more })).details), /s2_c3_zero: 2 phases started/);
  const other = zeroCrew3();
  other.events[0].reason = 'user';
  assert.match(ids(C.checkS2(allS2({ s2_c3_zero: other })).details), /never paused for all_stopped/);
  const late = zeroCrew3();
  late.events[0].pt = 11.4;
  assert.match(ids(C.checkS2(allS2({ s2_c3_zero: late })).details), /paused at 11.4/);
  const edge = zeroCrew3();
  edge.events[0].pt = 11.1;
  assert.equal(C.checkS2(allS2({ s2_c3_zero: edge })).status, 'PASS', '10 s + 1 tick after the latest first notification');
  const resumed = zeroCrew3();
  resumed.events.push({ type: 'paused', paused: false, reason: 'resume', t: 50, pt: 50 });
  assert.match(ids(C.checkS2(allS2({ s2_c3_zero: resumed })).details), /the shared pause ended/);
  const kill = zeroCrew3();
  kill.events.push({ type: 'game_event', t: 4, event: { type: 'kill', id: 5, e: 1, by: 2, s: -1 } });
  assert.match(ids(C.checkS2(allS2({ s2_c3_zero: kill })).details), /s2_c3_zero: kills in a paused run/);
  const graded = zeroCrew3();
  graded.results.grade = 'C';
  assert.match(ids(C.checkS2(allS2({ s2_c3_zero: graded })).details), /s2_c3_zero: grade C/);
});

test('S2 crew 3 at 10 W fails on a stage that ended on its own, a pause, another outcome or a grade above D', () => {
  const ended = idleCrew3();
  ended.phases['1'][1].ended_by = 'end_phase';
  assert.match(ids(C.checkS2(allS2({ s2_c3_idle: ended })).details), /s2_c3_idle: advance 1 ended by end_phase/);
  const paused = idleCrew3();
  paused.events.push({ type: 'paused', paused: true, reason: 'all_stopped', t: 400, pt: 400 });
  assert.match(ids(C.checkS2(allS2({ s2_c3_idle: paused })).details), /s2_c3_idle: paused, but every rider pedals/);
  const won = idleCrew3();
  won.finished_reason = 'victory';
  assert.match(ids(C.checkS2(allS2({ s2_c3_idle: won })).details), /s2_c3_idle: finished_reason "victory"/);
  const graded = idleCrew3();
  graded.results.grade = 'C';
  assert.match(ids(C.checkS2(allS2({ s2_c3_idle: graded })).details), /s2_c3_idle: grade C/);
});

test('S2 anchors the pause on the first not-pedaling sample: the first trainer notification, not the t = 0 row', () => {
  assert.equal(C.notPedalingAnchor({ t: 0 }), C.FIRST_SAMPLE_MAX_S - C.TICK_S);
  assert.equal(C.notPedalingAnchor({ t: 60 }), 60, 'a rider who stops later: the 0 W row');
  const lastRun = zeroCrew1();
  lastRun.events[0].pt = 10.95;
  assert.equal(C.checkS2(allS2({ s2_c1_zero: lastRun })).status, 'PASS', 'sample at 1.0 s, paused 10 s later');
});

test('S2 crew 1: paused late, not paused, more than the depot, a kill or a grade fail', () => {
  const late = zeroCrew1();
  late.events[0].pt = 11.15;
  assert.match(ids(C.checkS2({ s2_c1_zero: late }).details), /paused at 11.15/);
  const edge = zeroCrew1();
  edge.events[0].pt = 11.1;
  assert.equal(C.checkS2(allS2({ s2_c1_zero: edge })).status, 'PASS', 'one tick of slack');
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
  assert.match(ids(dirOf([req(1, 450, { mode: 'SIM', mode_grade: 4, reason: 'hoist' })], 1)), /matches no pattern/, 'v3 retired the hoist');
  assert.deepEqual(dirOf([{ id: 10, peer: 1, t: 400, kind: 'replan', requested: {}, accepted: true, applied: null }]), [], 'a seat replan (S13 judges it)');
});

test('S4 rejects directives outside brief 2.3 and 2.7', () => {
  assert.match(ids(dirOf([req(1, 400, { mode: 'ERG', target_pct: 80, reason: 'surprise' })])), /matches no pattern/);
  // A SIM-mode directive in an ERG phase: the Gun's gun line (peer 2, ERG with the bank).
  assert.match(ids(dirOf([req(2, 560, { mode: 'SIM', mode_grade: 3, reason: 'boiler' })])), /ERG phase/);
  assert.match(ids(dirOf([req(2, 560, { mode: 'SIM', haptic: 2.0, duration_s: 1.5, reason: 'hit' })])), /haptic to an ERG rider|SIM-mode\) in an ERG/);
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
  const inErg = makeRun(3, { extraRows: (row, peer) => (peer === '2' && row.t === 550 ? { ...row, haptic: 2 } : row) });
  assert.match(ids(C.traceProblems('x', inErg)), /haptic applied in ERG/);
  const cool = makeRun(3, { extraRows: (row, peer) => (peer === '2' && row.t === 1700 ? { ...row, haptic: 2, mode: 'SIM' } : row) });
  assert.match(ids(C.traceProblems('x', cool)), /cool-down/);
  // A SIM -> ERG entry above the planned target: peer 1 (Drive) enters the checkpoint (ERG 50% = 100 W) at 600 s.
  const spike = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.phase === 3 && row.t <= 602 ? { ...row, applied_target_w: 110 } : row) });
  assert.match(ids(C.traceProblems('x', spike)), /entered ERG at 600 s with 110 W/);
  const fine = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.phase === 3 && row.t <= 602 ? { ...row, applied_target_w: 100 } : row) });
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

test('S4 trace: warm-up grade -2..+3%, warm-up ERG <= 65%, +16% total, +10% before the haptic', () => {
  const at = (peer, t, patch) => (row, p) => (p === peer && row.t === t ? { ...row, ...patch } : row);
  const probs = (peer, t, patch) => ids(C.traceProblems('x', makeRun(3, { extraRows: at(peer, t, patch) })));
  // Peer 1 (diesel) is in the SIM depot at 100 s; peer 2 (dynamo) is in an ERG depot.
  assert.match(probs('1', 100, { applied_grade_pct: 3.5 }), /applied grade 3.5% at 100 s \(-2 to \+3% in the first 300 s\)/);
  assert.match(probs('1', 100, { applied_grade_pct: -2.5 }), /applied grade -2.5% at 100 s/);
  assert.equal(probs('1', 100, { applied_grade_pct: 3 }), '');
  assert.equal(probs('1', 100, { applied_grade_pct: -2 }), '');
  assert.match(probs('2', 100, { applied_pct: 70, applied_target_w: 140 }), /applied ERG 70% FTP at 100 s \(max 65% in the first 300 s\)/);
  assert.equal(probs('2', 100, { applied_pct: 65, applied_target_w: 130 }), '');
  // After 300 s the warm-up bounds no longer apply; the total and the pre-haptic bounds always do.
  assert.equal(probs('1', 350, { applied_grade_pct: 8 }), '');
  assert.match(probs('1', 350, { applied_grade_pct: 16.5, haptic: 3 }), /max \+16% in total/);
  assert.match(probs('1', 350, { applied_grade_pct: 12, haptic: 1 }), /less haptic 1% at 350 s \(max \+10% before the haptic\)/);
  assert.equal(probs('1', 350, { applied_grade_pct: 12, haptic: 2.1 }), '');
});

test('S4 applied values never exceed what was requested', () => {
  const withApplied = (requested, applied, t = 310, peer = 2) => req(peer, t, requested, { applied: { clamped_by: ['slew'], refused: false, applied } });
  const run = (d, crew = 3) => ids(dirOf([d], crew));
  assert.equal(run(withApplied({ mode: 'ERG', target_pct: 70, reason: 'bank' }, { mode: 'ERG', target_pct: 65, target_w: 130 })), '');
  assert.match(run(withApplied({ mode: 'ERG', target_pct: 70, reason: 'bank' }, { mode: 'ERG', target_pct: 80, target_w: 160 })), /applied ERG target % 80 above the requested 70/);
  assert.equal(run(withApplied({ mode: 'SIM', mode_grade: 6, reason: 'boiler' }, { mode: 'SIM', mode_grade: 6, grade_pct: 3 }, 700, 3)), '');
  assert.match(run(withApplied({ mode: 'SIM', mode_grade: 6, reason: 'boiler' }, { mode: 'SIM', mode_grade: 7.5, grade_pct: 3 }, 700, 3)), /applied mode grade % 7.5 above the requested 6/);
  assert.match(run(withApplied({ mode: 'ERG', target_pct: 70, reason: 'arc' }, { mode: 'ERG', target_pct: 75 }, 310, 4), 4), /applied ERG target % 75 above the requested 70/);
  assert.equal(run(withApplied({ mode: 'SIM', haptic: 3, duration_s: 2, reason: 'boss_hit' }, { mode: 'SIM', haptic_pct: 2.1, haptic_s: 2 }, 1400, 1)), '');
  assert.match(run(withApplied({ mode: 'SIM', haptic: 2, duration_s: 1.5, reason: 'hit' }, { mode: 'SIM', haptic_pct: 3.4, haptic_s: 1.5 }, 400, 1)), /applied haptic % 3.4 above the requested 2/);
  // A refused request applies nothing and is judged by the refusal check.
  const refused = withApplied({ mode: 'SIM', haptic: 2, duration_s: 1.5, reason: 'hit' }, { mode: 'SIM', haptic_pct: 9 }, 400, 1);
  refused.applied.refused = true;
  assert.equal(run(refused), '');
  assert.match(run(withApplied({ mode: 'SIM', mode_grade: 6, reason: 'boiler' }, undefined, 700, 3)), /no applied values/);
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

test('unmatchedAcks accepts only the remote governors course-grade acks of a logged request', () => {
  const cg = (t, peer = 2) => ({ id: 7, peer, t, kind: 'course_grade', requested: { grade_pct: 1 }, accepted: true, applied: null });
  const ack = (t, peer = 2, extra = {}) => ({ id: 0, peer, t, kind: 'course_grade', applied: { course_grade_pct: 1 }, clamped_by: [], refused: false, requested: {}, ...extra });
  const base = { directives: [cg(10), cg(10.5)], directives_unmatched: [ack(10.05), ack(10.55)] };
  assert.deepEqual(C.unmatchedAcks(base), []);
  assert.equal(C.unmatchedAcks({ ...base, directives_unmatched: [ack(10.05), ack(10.07)] }).length, 1, 'a second ack of one request');
  assert.equal(C.unmatchedAcks({ ...base, directives_unmatched: [ack(13)] }).length, 1, 'no request within the lag bound before it');
  assert.equal(C.unmatchedAcks({ ...base, directives_unmatched: [ack(9.9)] }).length, 1, 'an ack before its request');
  assert.equal(C.unmatchedAcks({ ...base, directives_unmatched: [ack(10.05, 2, { applied: { course_grade_pct: 9 } }), ack(10.55)] }).length, 1, 'an ack that applied another grade than requested');
  assert.equal(C.unmatchedAcks({ ...base, directives_unmatched: [ack(10.05, 2, { applied: {} })] }).length, 1, 'an ack without a value');
  // The pairing follows peer, order and value, not a latency: acks 0.05 s, 0.3 s or 1 s late are still paired.
  for (const late of [0.05, 0.3, 1]) {
    const slow = { ...base, directives_unmatched: base.directives_unmatched.map((a) => ({ ...a, t: a.t + late })) };
    assert.deepEqual(C.unmatchedAcks(slow), [], `${late} s later`);
  }
  // A request the governor never acked is passed over; the ack of the next one with the same value pairs with it.
  const varied = [1, 2, 3].map((g, i) => ({ ...cg(30 + 0.5 * i), requested: { grade_pct: g } }));
  const acks = (vals) => vals.map(([t, v]) => ack(t, 2, { applied: { course_grade_pct: v } }));
  assert.deepEqual(C.unmatchedAcks({ directives: varied, directives_unmatched: acks([[30.1, 1], [31.1, 3]]) }), [], 'the 2% request was dropped');
  assert.equal(C.unmatchedAcks({ directives: varied, directives_unmatched: acks([[31.1, 3], [31.2, 1]]) }).length, 1, 'order matters: 1% cannot follow 3%');
  assert.equal(C.unmatchedAcks({ ...base, directives_unmatched: [ack(10.05, 1)] }).length, 1, 'another peer');
  assert.equal(C.unmatchedAcks({ ...base, directives_unmatched: [ack(10.05, 2, { kind: 'request' })] }).length, 1, 'another kind');
  assert.equal(C.unmatchedAcks({ ...base, directives_unmatched: [ack(10.05, 2, { id: 9 })] }).length, 1, 'an id that matched nothing');
  assert.equal(C.unmatchedAcks({ ...base, directives_unmatched: [ack(10.05, 2, { refused: true })] }).length, 1, 'a refused one');
  const full = { ...goodSet() };
  for (const c of C.CREWS) full['s4_drill_c' + c] = makeRun(c, { content: 'drill' });
  full.s1_c3_seed1.directives.push(cg(20, 1));
  full.s1_c3_seed1.directives_unmatched.push(ack(20.05, 1), ack(300, 1));
  const r = C.checkS4(full, { seeds: [1] });
  assert.equal(r.status, 'FAIL');
  assert.match(ids(r.details), /1 unmatched applied records/);
});

// --- S5 --------------------------------------------------------------------------------------------------------------

/** A run where `peer` is in rescue from `from` to `to` seconds (applied 50% FTP, clamped by rescue). */
function rescueRun(peer, phaseStart, from, to) {
  return makeRun(3, {
    extraRows: (row, p) => (p === peer && row.t >= from && row.t < to ? { ...row, rescue: true, applied_pct: 50, clamped_by: ['rescue'] } : row),
  });
}

/** Crew 4 where the Lights rider (peer 4) is in rescue in the stage 1 Advance. */
function arcRescueRun(from = 320, to = 360) {
  const r = makeRun(4, {
    extraRows: (row, p) => (p === '4' && row.t >= from && row.t < to ? { ...row, rescue: true, applied_pct: 50, clamped_by: ['rescue'] } : row),
  });
  return r;
}

test('S5 passes when the collapsing rider enters rescue in the right phase, recovers, and the plan continues', () => {
  const set = { s5_c3_dynamo_drop: rescueRun('2', 500, 520, 560), s5_c4_arc_drop: arcRescueRun() };
  const r = C.checkS5(set);
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.equal(C.checkS5({}).status, 'SKIP');
});

test('S5 fails without rescue, with rescue that never ends, at the wrong power, and when the plan stops', () => {
  const gl = arcRescueRun();
  const set = (dyn) => ({ s5_c3_dynamo_drop: dyn, s5_c4_arc_drop: gl });
  assert.match(ids(C.checkS5(set(makeRun(3))).details), /never entered rescue/);
  const endless = rescueRun('2', 500, 520, 99999);
  assert.match(ids(C.checkS5(set(endless)).details), /rescue never ended/);
  const strong = makeRun(3, { extraRows: (row, p) => (p === '2' && row.t >= 520 && row.t < 560 ? { ...row, rescue: true, applied_pct: 70, clamped_by: ['rescue'] } : row) });
  assert.match(ids(C.checkS5(set(strong)).details), /rescue applied 70% FTP/);
  const stopped = rescueRun('2', 500, 520, 560);
  stopped.phases['2'] = stopped.phases['2'].slice(0, 5);
  assert.match(ids(C.checkS5(set(stopped)).details), /plan phases ran/);
  const bystander = rescueRun('2', 500, 520, 560);
  for (const row of bystander.trace['3']) if (row.t === 525) row.rescue = true;
  assert.match(ids(C.checkS5(set(bystander)).details), /peer 3 \(not the collapsing rider\)/);
  const unclamped = makeRun(3, { extraRows: (row, p) => (p === '2' && row.t >= 520 && row.t < 560 ? { ...row, rescue: true, applied_pct: 50 } : row) });
  assert.match(ids(C.checkS5(set(unclamped)).details), /clamped by rescue/);
  // Rescue in a SIM phase (the Drive rider in the depot) is not the Gun's or the Lights'.
  const wrongPhase = makeRun(3, { extraRows: (row, p) => (p === '2' && row.t >= 100 && row.t < 140 ? { ...row, rescue: true, applied_pct: 50, clamped_by: ['rescue'] } : row) });
  wrongPhase.plans['2'].phases[0] = { ...wrongPhase.plans['2'].phases[0], mode: 'SIM', meta: { ...wrongPhase.plans['2'].phases[0].meta, engine: 'diesel' } };
  assert.match(ids(C.checkS5(set(wrongPhase)).details), /rescue began in a SIM phase of diesel/);
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

// --- T7 ---------------------------------------------------------------------------------------------------------------

test('T7 needs the arc target above 72% for 30 s per stage and back at 68% within 60 s of a fight', () => {
  assert.deepEqual(C.t7Problems('x', makeRun(4)), []);
  assert.equal(C.arcFights(makeRun(4)).length, 7, 'three Advances, three gun lines and the boss, each on its own arc rider');
  assert.match(ids(C.t7Problems('x', makeRun(4, { arcPct: 70 }))), /stage 1: the arc target above 72% for 0 s/);
  const stuck = makeRun(4, { extraRows: (row) => (row.kind !== 'COOLDOWN' ? { ...row, mode: 'ERG', applied_pct: 76 } : row) });
  assert.match(ids(C.t7Problems('x', stuck)), /stayed above 68%/);
  // A kill in an arc Advance followed by 60 s with no enemy shot is a fight's end too.
  const ge = (t, event) => ({ type: 'game_event', t, pt: t, event });
  const quiet = makeRun(4, { events: [ge(400, { type: "kill", id: 4, e: 1, by: 0, s: 1 })] });
  assert.match(ids(C.t7Problems('x', quiet)), /advance 1: the arc target stayed above 68% for 60 s after the fight at 400 s/);
  const busy = makeRun(4, { events: [ge(400, { type: "kill", id: 4, e: 1, by: 0, s: 1 }), ge(420, { type: "shot", s: -1, sh: 5, id: 9, src: 2, e: 2 })] });
  assert.deepEqual(C.t7Problems('x', busy), [], 'another enemy still fires: the fight goes on');
  assert.match(ids(C.t7Problems('x', makeRun(3))), /no arc generator stage/);
});

// --- S9 ---------------------------------------------------------------------------------------------------------------

/** A clean sprinting solo run: an evaded telegraphed shot in each Advance, power 300 W at the end of the stage 1 gun line (the ERG checkpoint at 600 s). */
function sprintRun(over = {}) {
  const ge = (t, event) => ({ type: 'game_event', t, pt: t, event });
  const starts = [300, 660, 1020];
  const events = starts.map((a, i) => ge(a + 40, { type: 'evade', id: 10 + i, e: 3, ok: 1, s: 0 }));
  const r = makeRun(1, {
    events: over.events ?? events,
    directives: over.directives ?? [],
    extraRows: (row) => {
      let out = row;
      if (row.t >= 594 && row.t < 600) out = { ...out, power_w: 300 };
      if (over.rows) out = over.rows(out) ?? out;
      return out;
    },
  });
  return r;
}

test('S9 passes on a sprinter that evades and enters every ERG phase at its target', () => {
  const r = C.checkS9({ s9_c1_sprint: sprintRun() });
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.match(r.summary, /3 of 6 telegraphed shots evaded, 4 ERG entries \(1 after a sprint\)/);
  assert.equal(C.checkS9({}).status, 'SKIP');
  assert.deepEqual(C.successfulEvades(sprintRun()).map((e) => e.id), [10, 11, 12]);
  const sw = C.switchesIntoErg(sprintRun(), '1').filter((x) => x.phase === 3);
  assert.equal(sw.length, 1);
  assert.ok(sw[0].trailingW >= 300 - 1e-6, 'the 3 s before the checkpoint are the sprint');
});

test('S9 fails without an evade, or with a Ram event or haptic', () => {
  const ge = (t, event) => ({ type: 'game_event', t, pt: t, event });
  const failedOnly = [300, 660, 1020].map((a, i) => ge(a + 40, { type: 'evade', id: 10 + i, e: 3, ok: 0, s: -1 }));
  assert.match(ids(C.checkS9({ s9_c1_sprint: sprintRun({ events: failedOnly }) }).details), /never made a telegraphed shot miss/);
  const ram = [ge(340, { type: 'evade', id: 10, e: 3, ok: 1, s: 0 }), ge(345, { type: 'ram', s: 0, ok: 1, id: 3 })];
  assert.match(ids(C.checkS9({ s9_c1_sprint: sprintRun({ events: ram }) }).details), /1 Ram or dodge events/);
  const hap = [req(1, 340, { mode: 'SIM', haptic: 3.0, duration_s: 1.0, reason: 'ram' })];
  assert.match(ids(C.checkS9({ s9_c1_sprint: sprintRun({ directives: hap }) }).details), /1 ram haptics/);
  const calm = sprintRun({ rows: (row) => (row.t >= 594 && row.t < 600 ? { ...row, power_w: 150 } : row) });
  assert.equal(C.checkS9({ s9_c1_sprint: calm }).status, 'PASS', 'an ERG entry after a sprint is not required (v3)');
});

test('S9 fails when an ERG phase is entered at the sprint power, or a haptic goes to an ERG rider', () => {
  const spike = sprintRun({ rows: (row) => (row.phase === 3 && row.t <= 602 ? { ...row, applied_target_w: 300 } : row) });
  assert.match(ids(C.checkS9({ s9_c1_sprint: spike }).details), /ERG phase 3 at 600 s entered after 300 W with a 300 W target \(planned 100 W\)/);
  const erg = [req(1, 620, { mode: "SIM", haptic: 2.0, duration_s: 1.5, reason: "hit" })];
  const r = sprintRun({ directives: erg });
  assert.match(ids(C.checkS9({ s9_c1_sprint: r }).details), /haptic to an ERG rider|SIM-mode\) in an ERG/);
  const wrongRun = sprintRun();
  wrongRun.args.players = 3;
  assert.match(ids(C.checkS9({ s9_c1_sprint: wrongRun }).details), /players 3, wanted 1/);
});

test('S1 holds every crew to the "Surge to evade" prompt only with --require-prompts (v3: the host rider changes seats)', () => {
  assert.equal(C.checkS1(goodSet(), { seeds: [1] }).status, 'PASS');
  const set = goodSet();
  set.s1_c1_seed1.events = set.s1_c1_seed1.events.filter((e) => e.type !== 'hud');
  assert.equal(C.checkS1(set, { seeds: [1] }).status, 'PASS');
  assert.match(ids(C.checkS1(set, { seeds: [1], requirePrompts: true }).details), /s1_c1_seed1: stage 1 Advance raised no "Surge to evade" prompt/);
  assert.match(ids(C.checkS1(goodSet(), { seeds: [1], requirePrompts: true }).details), /s1_c3_seed1: stage 1 Advance raised no/);
});

// --- S10 --------------------------------------------------------------------------------------------------------------

const over = (t, slot, sh = 3) => ({ type: 'game_event', t, pt: t, event: { type: 'latch', s: slot, sh } });

/** Crew 3 with every rider sprinting: slot 2 works the Loader (the steam engine) all along. */
function clientSprintRun(events) {
  return makeRun(3, { events: events ?? [over(400, 2), over(700, 2)] });
}

/** Crew 3 where peer 2 (the dynamo of the stage 1 gun line, 500-600 s) stops dead from 520 s to 580 s. */
function stopRun(patch = {}) {
  const r = makeRun(3, {
    extraRows: (row, peer) => {
      if (peer !== '2' || row.t < 520 || (row.t >= 580 && patch.back !== false)) return row;
      let out = { ...row, power_w: 0, cadence_rpm: 0, applied_pct: 30, applied_target_w: 60 };
      if (row.t >= 523) out = { ...out, rescue: true, clamped_by: ['rescue'] };
      if (row.t >= 530 && patch.afk !== false) out = { ...out, afk: true };
      if (row.t >= 575 && patch.back !== false) out = { ...out, power_w: 100, cadence_rpm: 90 };
      return out;
    },
  });
  if (patch.toast !== false) r.events.push({ type: 'hud', kind: 'toast', key: 'TANK_TOAST_RESERVE', peer: 1, t: 531 });
  return r;
}

const s10Set = (a, b) => ({ s10_c3_clients_sprint: a, s10_c3_dynamo_stop: b });

test('S10 passes on client Overpressure owned by the steam engine and a dynamo rider who stops and returns', () => {
  const r = C.checkS10(s10Set(clientSprintRun(), stopRun()));
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.match(r.summary, /2 client Overpressure shells/);
  assert.equal(C.checkS10({}).status, 'SKIP');
  assert.equal(C.peerOfSlot(clientSprintRun(), 2), '3');
  assert.deepEqual(C.intentOwnershipProblems('x', clientSprintRun()), [], 'slot 2 is the Loader');
  assert.equal(C.intentOwnershipProblems('x', clientSprintRun([over(700, 0)])).length, 1, 'slot 0 drives');
});

test('S10 fails when no client Overpressure lands, one comes from a rider off the steam engine, or a Ram shows up', () => {
  const none = clientSprintRun([over(1100, 0), over(400, 2, 2)]);
  assert.match(ids(C.checkS10(s10Set(none, stopRun())).details), /no client rider .* latched an Overpressure shell/);
  const wrong = clientSprintRun([over(400, 1), over(700, 2)]);
  assert.match(ids(C.checkS10(s10Set(wrong, stopRun())).details), /Overpressure shell by slot 1 at 400 s, who was on "dynamo"/);
  const ram = clientSprintRun([over(400, 2), { type: 'game_event', t: 450, pt: 450, event: { type: 'ram', s: 0, ok: 1, id: 7 } }]);
  assert.match(ids(C.checkS10(s10Set(ram, stopRun())).details), /a ram event at 450 s/);
  const fine = clientSprintRun([over(400, 2)]);
  assert.equal(C.checkS10(s10Set(fine, stopRun())).status, 'PASS');
});

test('S10 fails when the stopped rider never goes AFK, never returns, has no reserve toast, or drags others in', () => {
  assert.match(ids(C.checkS10(s10Set(clientSprintRun(), stopRun({ afk: false }))).details), /never went AFK/);
  assert.match(ids(C.checkS10(s10Set(clientSprintRun(), stopRun({ back: false }))).details), /never came back from AFK/);
  assert.match(ids(C.checkS10(s10Set(clientSprintRun(), stopRun({ toast: false }))).details), /no "on reserve" toast/);
  const late = stopRun();
  for (const row of late.trace['2']) if (row.t >= 530 && row.t < 545) row.afk = false;
  assert.match(ids(C.checkS10(s10Set(clientSprintRun(), late)).details), /went AFK 25 s after it stopped/);
  const drag = stopRun();
  for (const row of drag.trace['3']) if (row.t === 540) row.rescue = true;
  assert.match(ids(C.checkS10(s10Set(clientSprintRun(), drag)).details), /peer 3 \(not the rider who stopped\)/);
  const calm = makeRun(3);
  assert.match(ids(C.checkS10(s10Set(clientSprintRun(), calm)).details), /never stopped pedaling in the gun line/);
  const stuck = stopRun();
  stuck.phases['2'] = stuck.phases['2'].slice(0, 5);
  assert.match(ids(C.checkS10(s10Set(clientSprintRun(), stuck)).details), /plan did not continue/);
  assert.match(ids(C.checkS10({ s10_c3_clients_sprint: clientSprintRun() }).details), /missing report s10_c3_dynamo_stop/);
});

// --- S13 seat switching ---------------------------------------------------------------------------------------------

/** splitRun as the s13 run: crew 3 on the fallback, peer 1 (slot 0) moves to the Secondaries, peer 2 (a client) later too. */
function seatRun() {
  const r = splitRun();
  r.args.autopilot = 'none';
  r.directives.push({ id: 900, peer: 1, t: 399.95, kind: 'replan', accepted: true, reason: '', requested: {} });
  // Peer 2 (slot 1) moves at the stage 2 checkpoint's end (a boundary landing) to the Lights.
  const plan2 = r.plans['2'].phases;
  for (let i = 7; i < plan2.length - 1; i += 1) plan2[i] = { ...plan2[i], meta: { ...plan2[i].meta, engine: 'arc' } };
  r.events.push({ type: 'game_event', t: 1020, pt: 1020, event: { type: 'seat', s: 1, from: 2, to: 5 } });
  r.directives.push({ id: 901, peer: 2, t: 990, kind: 'replan', accepted: true, reason: '', requested: {} });
  return r;
}

test('S13 passes on moves that respect the lock, land on their seat and come from accepted replans', () => {
  const r = C.checkS13({ s13_c3_seats: seatRun() });
  assert.equal(r.status, 'FAIL', 'two moves only');
  assert.match(ids(r.details), /2 seat moves \(want at least 3\)/);
  const three = seatRun();
  three.events.push({ type: 'game_event', t: 1500, pt: 1500, event: { type: 'seat', s: 1, from: 5, to: 5 } });
  three.directives.push({ id: 902, peer: 2, t: 1499, kind: 'replan', accepted: true, reason: '', requested: {} });
  const ok = C.checkS13({ s13_c3_seats: three });
  assert.equal(ok.status, 'PASS', ids(ok.details));
  assert.equal(C.checkS13({}).status, 'SKIP');
});

test('S13 fails on a move inside the lock, a move its plan does not show, or a refused replan', () => {
  const r = seatRun();
  r.events.push({ type: 'game_event', t: 1050, pt: 1050, event: { type: 'seat', s: 1, from: 5, to: 5 } });
  assert.match(ids(C.seatProblems('x', r)), /slot 1 moved at 1020 s and again at 1050 s/);
  const wrong = seatRun();
  wrong.events.push({ type: 'game_event', t: 1600, pt: 1600, event: { type: 'seat', s: 2, from: 3, to: 1 } });
  assert.match(ids(C.seatProblems('x', wrong)), /slot 2 moved to diesel at 1600 s but its plan says steam/);
  const refused = seatRun();
  refused.directives.push({ id: 903, peer: 3, t: 1700, kind: 'replan', accepted: false, reason: 'plan_invalid', requested: {} });
  assert.match(ids(C.seatProblems('x', refused)), /replan 903 \(peer 3 at 1700 s\) refused: plan_invalid/);
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
  assert.throws(() => C.parseArgs(['d', '--only=S8']), /unknown scenario/);
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

test('S2 crew 3 allows one telemetry interval for the shared pause, not more', () => {
  const onTime = zeroCrew3();
  onTime.events[0].pt = 11.25;
  assert.equal(C.checkS2(allS2({ s2_c3_zero: onTime })).status, 'PASS', 'the last rider pauses at 11.1 s, the host learns it 0.2 s later');
});
