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
  ['hangar', 0, 'WARMUP', 180],
  ['rollout', 0, 'WARMUP', 120],
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
  ['hangar', 0, 'WARMUP', 30],
  ['skirmish', 1, 'WARMUP', 70],
  ['checkpoint', 1, 'RECOVERY', 30],
];
// v4: the 15-minute session (SPEC_TANK 3.8), nominal 900 s with the cool-down.
const AMBUSH_TABLE = [
  ['hangar', 0, 'WARMUP', 180],
  ['rollout', 0, 'WARMUP', 120],
  ['advance', 1, 'WORK', 120, 80, 160],
  ['gun_line', 1, 'WORK', 90, 60, 120],
  ['checkpoint', 1, 'RECOVERY', 60],
  ['boss', 4, 'WORK', 150, 100, 190],
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
  const meta = { engine, mission: table === AMBUSH_TABLE ? 'ambush_15' : 'ashfall_road', seg, segment: i, stage };
  const base = { duration_s: dur, kind, label: `L${i}`, lap: true, meta };
  if (min !== undefined) Object.assign(base, { min_s: min, max_s: max, open_ended: true });
  if (seg === 'checkpoint') return { ...base, mode: 'ERG', target_pct: 50 };
  if (engine === 'dynamo') {
    if (drill) return seg === 'hangar' ? { ...base, mode: 'ERG', target_pct: 50 } : { ...base, mode: 'ERG', target_pct: 55, range_pct: [55, 65] };
    if (seg === 'hangar') return { ...base, mode: 'ERG', target_pct: 50, ramp_to_pct: 59 };
    if (seg === 'rollout') return { ...base, mode: 'ERG', target_pct: 59, ramp_to_pct: 65 };
    return { ...base, mode: 'ERG', target_pct: 55, range_pct: [55, 100] };
  }
  if (engine === 'arc') {
    if (drill) return seg === 'hangar' ? { ...base, mode: 'ERG', target_pct: 50 } : { ...base, mode: 'ERG', target_pct: 55, range_pct: [55, 65] };
    if (seg === 'hangar') return { ...base, mode: 'ERG', target_pct: 50, ramp_to_pct: 59 };
    if (seg === 'rollout') return { ...base, mode: 'ERG', target_pct: 59, ramp_to_pct: 65 };
    return { ...base, mode: 'ERG', target_pct: 65, range_pct: [65, 80] };
  }
  if (engine === 'steam' || engine === 'feed') return { ...base, mode: 'SIM', grade_source: 'flat' };
  // v3: Drive digs in at a gun line in SIM flat.
  return { ...base, mode: 'SIM', grade_source: seg === 'boss' || seg === 'gun_line' || seg === 'hangar' ? 'flat' : 'game' };
}

/**
 * A clean compliant ashfall_road run of `crew` riders. opts: durations {advance, gun_line, boss}
 * (seconds, per run), grade, score, ended {index: how}, dynamoPct (applied % in dynamo fights), arcPct (in arc fights),
 * events [], directives [], extraRows (fn(row, peer) -> row), seed, role, endReason; v4: content 'ambush_15', options (the
 * run's --options), rider (--rider), bots (bot slots after the humans).
 */
function makeRun(crew, opts = {}) {
  const table = opts.content === 'drill' ? DRILL_TABLE : opts.content === 'ambush_15' ? AMBUSH_TABLE : SEG_TABLE;
  const d = { advance: 200, gun_line: 100, boss: 250, ...(opts.durations ?? {}) };
  const durOf = (i) => {
    const [seg, , , nominal] = table[i];
    if (table === DRILL_TABLE) return nominal;
    if (table === AMBUSH_TABLE) return opts.durations?.[seg] ?? nominal;
    return d[seg] ?? nominal;
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
  // v4: two near threats in each Advance from crew 2 up: a recon car killed, shooting until it dies, a tankette that gets away.
  if (crew >= 2 && table === SEG_TABLE) {
    SEG_TABLE.forEach((row, i) => {
      if (row[0] !== 'advance') return;
      const a = starts[i];
      events.push(ge(a + 60, { type: 'ambush', id: 900 + i, e: 7 }));
      events.push(ge(a + 64, { type: 'shot', s: -1, sh: 5, id: 800 + i, src: 900 + i, e: 7, rng_m: 0 }));
      events.push(ge(a + 70, { type: 'kill', id: 900 + i, e: 7, by: 3, s: 1 }));
      events.push(ge(a + 74, { type: 'shot', s: -1, sh: 5, id: 820 + i, src: 950 + i, e: 8, rng_m: 0 }));
      events.push(ge(a + 72, { type: 'ambush', id: 950 + i, e: 8 }));
      events.push(ge(a + 95, { type: 'escaped', id: 950 + i, e: 8 }));
    });
  }
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
  for (let k = 0; k < (opts.bots ?? 0); k += 1) {
    slots.push({ slot: crew + k, peer: -(k + 1), is_bot: true, ftp: 200, ftp_verified: true, haptics_on: true, autopilot: true, rider: 'erg:compliance=1.0+band' });
  }
  const report = {
    schema: 1,
    game_id: 'tank',
    content_id: opts.content ?? 'ashfall_road',
    role: opts.role ?? (crew >= 2 ? 'HOST' : 'SOLO'),
    seed: opts.seed ?? 1,
    args: { game: 'tank', content: opts.content ?? 'ashfall_road', players: crew, bots: opts.bots ?? 0, seed: opts.seed ?? 1, riders: [opts.rider ?? 'erg:compliance=1.0'], options: opts.options ?? {} },
    slots,
    plans,
    plan_warnings: Object.fromEntries(Object.keys(plans).map((p) => [p, []])),
    end_reason: opts.endReason ?? 'complete',
    finished_reason: opts.finished ?? 'victory',
    game_seconds: end,
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
  assert.equal(segs.length, 13);
  assert.deepEqual(segs.slice(0, 4).map((s) => [s.seg, s.stage, s.dur]), [['hangar', 0, 180], ['rollout', 0, 120], ['advance', 1, 200], ['gun_line', 1, 100]]);
  assert.equal(segs[12].seg, 'cooldown');
  assert.equal(C.planLaps(makeRun(3)), 13);
  assert.equal(C.phaseIndexAt(makeRun(3), '1', 310), 2);
});

/** Crew 3 where peer 1 moves from Drive to the Loader's seat 100 s into the stage 1 Advance (v3: a split phase). */
function splitRun() {
  const r = makeRun(3);
  const plan = r.plans['1'].phases;
  const rest = { ...plan[2], lap: false, mode: 'SIM', grade_source: 'flat', min_s: 0.05, max_s: 200, meta: { ...plan[2].meta, engine: 'feed', offset_s: 100 } };
  plan.splice(3, 0, rest);
  const spans = r.phases['1'];
  const adv = spans[2];
  const second = { ...adv, index: 3, start: adv.start + 100 };
  adv.end = adv.start + 100;
  adv.ended_by = 'end_phase';
  spans.splice(3, 0, second);
  for (let i = 4; i < spans.length; i += 1) spans[i].index = i;
  for (const row of r.trace['1']) if (row.phase >= 3 || (row.phase === 2 && row.t >= adv.end)) row.phase += 1;
  r.events.push({ type: 'game_event', t: adv.end, pt: adv.end, event: { type: 'seat', s: 0, from: 1, to: 6 } });
  return r;
}

test('segmentsOf merges a split segment (v3 seats); phaseSpansOf keeps its phases', () => {
  const r = splitRun();
  const segs = C.segmentsOf(r, '1');
  assert.equal(segs.length, 13, 'still one entry per segment');
  assert.deepEqual([segs[2].seg, segs[2].dur, segs[2].phases.length], ['advance', 200, 2]);
  assert.deepEqual(segs[2].phases.map((p) => p.engine), ['diesel', 'feed']);
  assert.equal(segs[3].seg, 'gun_line');
  assert.equal(C.phaseSpansOf(r, '1').length, 14);
  assert.equal(C.planLaps(r, '1'), 13, 'the split continues the lap');
  assert.deepEqual(C.lapProblems('x', r), []);
  const bad = splitRun();
  delete bad.plans['1'].phases[3].meta.offset_s;
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
  assert.match(ids(C.t1Problems('x', makeRun(3, { ended: { 3: 'max_s' }, durations: { gun_line: 180 } }))), /gun_line 1 overran/);
  const two = [{ type: 'game_event', t: 400, event: { type: 'breakdown' } }, { type: 'game_event', t: 800, event: { type: 'breakdown' } }];
  assert.match(ids(C.t1Problems('x', makeRun(3, { events: two }))), /2 breakdowns/);
  assert.match(ids(C.t1Problems('x', makeRun(3, { grade: 'C' }))), /grade C/);
  assert.deepEqual(C.t1Problems('x', makeRun(3, { grade: 'B' })), []);
});

test('T1 lets crew 2 hold a gun line up to 180 s on ashfall_road, and nobody else', () => {
  const hold = (crew, s, content) => C.t1Problems('x', makeRun(crew, { durations: { gun_line: s }, content }));
  assert.deepEqual(hold(2, 175), [], 'crew 2 at 175');
  assert.deepEqual(hold(2, 180), [], "crew 2 at the brief's own limit");
  assert.match(ids(hold(2, 181)), /gun_line 1 lasted 181 s \(60-180\)/);
  assert.match(ids(hold(3, 175)), /gun_line 1 lasted 175 s \(60-160\)/);
  assert.match(ids(hold(1, 175)), /gun_line 1 lasted 175 s \(60-160\)/);
  assert.match(ids(hold(4, 175)), /gun_line 1 lasted 175 s \(60-160\)/);
  assert.match(ids(hold(2, 50)), /gun_line 1 lasted 50 s \(60-180\)/, 'the short end stays');
  assert.match(ids(C.t1Problems('x', makeRun(2, { durations: { advance: 290 } }))), /advance 1 lasted 290 s \(120-280\)/);
  assert.match(ids(C.t1Problems('x', makeRun(2, { durations: { boss: 340 } }))), /boss 4 lasted 340 s \(120-330\)/);
  assert.match(ids(hold(2, 130, 'ambush_15')), /gun_line 1 lasted 130 s \(60-120\)/, 'ambush_15 stays');
});

test('T1 holds every crew, the solo rider (crew 1) included', () => {
  assert.deepEqual(C.T1_CREWS, [1, 2, 3, 4]);
  const set = { s1_c1_seed1: makeRun(1, { grade: 'C' }) };
  const r = C.checkS1(set, { seeds: [1] });
  assert.match(ids(r.details), /s1_c1_seed1: grade C \(B or better\)/);
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

test('T4 (v4) reads the solo loop: Drive share per Advance, main-gun shells per holding action', () => {
  assert.deepEqual(C.t4Problems('x', makeRun(1)), []);
  // Stage 1 Advance 300-500: the solo rider leaves Drive for the Loader at 330 s and comes back at 470 s (30% on Drive).
  const r = makeRun(1);
  const plan = r.plans['1'].phases;
  const spans = r.phases['1'];
  const adv = spans[2];
  plan.splice(3, 0, { ...plan[2], lap: false, mode: 'SIM', grade_source: 'flat', meta: { ...plan[2].meta, engine: 'steam', offset_s: 30 } });
  plan.splice(4, 0, { ...plan[2], lap: false, meta: { ...plan[2].meta, offset_s: 170 } });
  spans.splice(3, 0, { ...adv, index: 3, start: 330, end: 470 }, { ...adv, index: 4, start: 470, end: adv.end });
  adv.end = 330;
  for (let i = 5; i < spans.length; i += 1) spans[i].index = i;
  assert.match(ids(C.t4Problems('x', r)), /stage 1 Advance on Drive 30%/);
  const quiet = makeRun(1);
  quiet.events = quiet.events.filter((e) => !(e.event?.type === 'shot' && e.event.s === 0));
  assert.match(ids(C.t4Problems('x', quiet)), /stage 1 holding action: 0 main-gun shells fired \(min 2\)/);
  const gl1 = C.segmentsOf(quiet).find((s) => s.seg === 'gun_line' && s.stage === 1);
  quiet.events.push({ type: 'game_event', t: gl1.start + 5, pt: gl1.start + 5, event: { type: 'kill', id: 99, e: 7, by: 3, s: 0 } });
  assert.match(ids(C.t4Problems('x', quiet)), /stage 1 holding action/, 'v4: a bow kill no longer stands in for the main gun');
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

/** Crew 3 at 0 W: the shared pause (all_stopped) holds the hangar until max_sim_seconds. */
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

test('S2 passes on zero riders: crew 3 held in the hangar by the shared pause, crew 3 at 10 W overruns, crew 1 pauses', () => {
  const r = C.checkS2(allS2());
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.equal(C.checkS2({}).status, 'SKIP');
  assert.match(ids(C.checkS2({ s2_c3_zero: zeroCrew3(), s2_c1_zero: zeroCrew1() }).details), /missing report s2_c3_idle/);
});

test('S2 crew 3 at 0 W fails when the run completes, leaves the hangar, never pauses for all_stopped, resumes, kills or grades above D', () => {
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
  ended.phases['1'][2].ended_by = 'end_phase';
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

test('S2 crew 1: paused late, not paused, more than the hangar, a kill or a grade fail', () => {
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
  assert.deepEqual(dirOf([{ id: 11, peer: 1, t: 400, kind: 'split', requested: {}, accepted: true, applied: null }]), [], 'a seat split (S13 judges it)');
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
  const spike = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.phase === 4 && row.t <= 602 ? { ...row, applied_target_w: 110 } : row) });
  assert.match(ids(C.traceProblems('x', spike)), /entered ERG at 600 s with 110 W/);
  const fine = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.phase === 4 && row.t <= 602 ? { ...row, applied_target_w: 100 } : row) });
  assert.deepEqual(C.traceProblems('x', fine), []);
  // Two switches 20 s apart: an ERG blip inside the SIM Advance (0.3.1: BRIEF 4.5's 30 s).
  assert.equal(C.SWITCH_SPACING_S, 30);
  const quick = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.t >= 350 && row.t < 370 ? { ...row, mode: 'ERG' } : row) });
  assert.match(ids(C.traceProblems('x', quick)), /< 30 s/);
  const spaced = makeRun(3, { extraRows: (row, peer) => (peer === '1' && row.t >= 350 && row.t < 381 ? { ...row, mode: 'ERG' } : row) });
  assert.doesNotMatch(ids(C.traceProblems('x', spaced)), /switched/, '31 s apart');
  assert.deepEqual(C.lapProblems('x', makeRun(3)), []);
  const lap = makeRun(3);
  lap.plans['1'].phases[4].lap = false;
  assert.match(ids(C.lapProblems('x', lap)), /12 lap-true phases, wanted 13|lap false/);
  assert.deepEqual(C.lapProblems('x', { ...makeRun(1), content_id: 'other' }), []);
});

test('S4 trace: warm-up grade -2..+3%, warm-up ERG <= 65%, +16% total, +10% before the haptic', () => {
  const at = (peer, t, patch) => (row, p) => (p === peer && row.t === t ? { ...row, ...patch } : row);
  const probs = (peer, t, patch) => ids(C.traceProblems('x', makeRun(3, { extraRows: at(peer, t, patch) })));
  // Peer 1 (diesel) is in the SIM hangar at 100 s; peer 2 (dynamo) is in an ERG hangar.
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
  // Rescue in a SIM phase (the Drive rider in the hangar) is not the Gun's or the Lights'.
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
  const sw = C.switchesIntoErg(sprintRun(), '1').filter((x) => x.phase === 4);
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
  const spike = sprintRun({ rows: (row) => (row.phase === 4 && row.t <= 602 ? { ...row, applied_target_w: 300 } : row) });
  assert.match(ids(C.checkS9({ s9_c1_sprint: spike }).details), /ERG phase 4 at 600 s entered after 300 W with a 300 W target \(planned 100 W\)/);
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

test('S13 passes on moves whose trainer follows through accepted replans and splits', () => {
  const r = C.checkS13({ s13_c3_seats: seatRun() });
  assert.equal(r.status, 'FAIL', 'two moves only');
  assert.match(ids(r.details), /2 seat moves \(want at least 3\)/);
  const three = seatRun();
  three.events.push({ type: 'game_event', t: 1500, pt: 1500, event: { type: 'seat', s: 1, from: 5, to: 5 } });
  three.directives.push({ id: 902, peer: 2, t: 1499, kind: 'split', accepted: true, reason: '', requested: { warnings: [] } });
  const ok = C.checkS13({ s13_c3_seats: three });
  assert.equal(ok.status, 'PASS', ids(ok.details));
  assert.equal(C.checkS13({}).status, 'SKIP');
});

test('S13 (0.3.1, no lock) fails on a move its trainer never follows, a refused replan or a warned split', () => {
  const r = seatRun();
  r.events.push({ type: 'game_event', t: 1050, pt: 1050, event: { type: 'seat', s: 1, from: 5, to: 5 } });
  assert.doesNotMatch(ids(C.seatProblems('x', r)), /1050/, 'no seat lock: moving again 30 s later is fine');
  const wrong = seatRun();
  wrong.events.push({ type: 'game_event', t: 1600, pt: 1600, event: { type: 'seat', s: 2, from: 3, to: 1 } });
  assert.match(ids(C.seatProblems('x', wrong)), /slot 2 moved to diesel at 1600 s; its trainer never followed/);
  const refused = seatRun();
  refused.directives.push({ id: 903, peer: 3, t: 1700, kind: 'replan', accepted: false, reason: 'plan_invalid', requested: {} });
  assert.match(ids(C.seatProblems('x', refused)), /replan 903 \(peer 3 at 1700 s\) refused: plan_invalid/);
  const warned = seatRun();
  warned.directives.push({ id: 904, peer: 3, t: 1710, kind: 'split', accepted: true, reason: '', requested: { warnings: ['switches 10 s apart'] } });
  assert.match(ids(C.seatProblems('x', warned)), /split 904 warned: switches 10 s apart/);
});

// --- v4: T1, T8, T9, the Repairs directive, rescue and AFK shield the crew ------------------------------------------

const ge4 = (t, event) => ({ type: 'game_event', t, pt: t, event });
/** A tank loss at \`t\` and, unless \`restart\` is false, the restart after the 8 s tow. */
const lostAt = (t, n = 1, restart = true) => [ge4(t, { type: 'tank_lost', n, sg: 2, st: 1 }), ...(restart ? [ge4(t + 8, { type: 'stage_restart', sg: 2, st: 1, hp: 70 })] : [])];

test('T1 ranges are keyed by content; ambush_15 has its own', () => {
  assert.deepEqual(C.T1_RANGES.ambush_15, { advance: [80, 160], gun_line: [60, 120], boss: [100, 190] });
  assert.deepEqual(C.T1_RANGES.ashfall_road, { advance: [120, 280], gun_line: [60, 160], boss: [120, 330] });
  assert.deepEqual(C.EXPECTED_LAPS, { ashfall_road: 13, ambush_15: 7, drill: 4 });
  assert.deepEqual(C.t1Problems('x', makeRun(3, { content: 'ambush_15' })), []);
  assert.match(ids(C.t1Problems('x', makeRun(3, { content: 'ambush_15', durations: { advance: 170 } }))), /advance 1 lasted 170 s \(80-160\)/);
  assert.deepEqual(C.t1Problems('x', makeRun(3, { durations: { advance: 170 } })), [], 'inside ashfall_road range');
});

test('T1 lets a segment that lost the tank run long, holds at most one loss and no breakdown on Normal', () => {
  // The stage 1 Advance (300-590) would be over its range and overrun: it holds the loss, so neither counts.
  const long = makeRun(3, { durations: { advance: 290 }, ended: { 2: 'max_s' }, events: lostAt(350) });
  const probs = C.t1Problems('x', long);
  assert.doesNotMatch(ids(probs), /advance 1/);
  assert.match(ids(probs), /advance 2 lasted 290/, 'a segment without one still answers');
  assert.match(ids(C.t1Problems('x', makeRun(3, { events: [...lostAt(350), ...lostAt(1000, 2)] }))), /2 tank losses \(at most 1\)/);
  const one = [ge4(400, { type: 'breakdown' })];
  assert.match(ids(C.t1Problems('x', makeRun(3, { events: one }))), /1 breakdowns \(at most 0 on normal\)/);
  assert.deepEqual(C.t1Problems('x', makeRun(3, { events: one, options: { difficulty: 'easy' } })), [], 'Easy keeps the old breakdown');
  const two = [...one, ge4(800, { type: 'breakdown' })];
  assert.match(ids(C.t1Problems('x', makeRun(3, { events: two, options: { difficulty: 'easy' } }))), /2 breakdowns \(at most 1 on easy\)/);
});

test('difficultyOf reads the option, and auto through the mission', () => {
  assert.equal(C.difficultyOf(makeRun(1)), 'normal');
  assert.equal(C.difficultyOf(makeRun(1, { options: { difficulty: 'auto' } })), 'normal');
  assert.equal(C.difficultyOf(makeRun(1, { content: 'ambush_15' })), 'hard');
  assert.equal(C.difficultyOf(makeRun(1, { content: 'ambush_15', options: { difficulty: 'normal' } })), 'normal');
  assert.equal(C.difficultyOf(makeRun(1, { content: 'drill' })), 'easy');
});

test('T8 needs an ambush in every Advance, each threat accounted for, and 40% killed by crews 3-4', () => {
  assert.deepEqual(C.t8Problems('x', makeRun(3), 3), []);
  assert.deepEqual(C.t8Problems('x', makeRun(2), 2), []);
  const none = makeRun(3);
  none.events = none.events.filter((e) => !(e.event?.type === 'ambush' && e.t < 600));
  const p = ids(C.t8Problems('x', none, 3));
  assert.match(p, /stage 1 Advance has no ambush/);
  assert.match(p, /killed or escaped with no ambush/);
  const open = makeRun(3);
  open.events = open.events.filter((e) => !(e.event?.type === 'escaped' && e.t < 600));
  assert.match(ids(C.t8Problems('x', open, 3)), /near threat 952 from 372 s neither killed nor escaped/);
  const rows = C.nearLedger(makeRun(3)).rows;
  assert.deepEqual(rows.slice(0, 2).map((x) => [x.id, x.out, x.seg.seg]), [[902, 'killed', 'advance'], [952, 'escaped', 'advance']]);
});

test('T8 forgives only a threat young enough to be out when its segment ends or the tank is lost', () => {
  const late = (t) => [ge4(t, { type: 'ambush', id: 5, e: 8 })];
  // The stage 1 holding action: 500-600.
  assert.deepEqual(C.t8Problems('x', makeRun(3, { events: late(590) }), 3), [], 'cut off by the segment change, 10 s old');
  assert.match(ids(C.t8Problems('x', makeRun(3, { events: late(560) }), 3)), /near threat 5 from 560 s/, '40 s old: it should be gone');
  assert.deepEqual(C.t8Problems('x', makeRun(3, { events: [...late(520), ...lostAt(530)] }), 3), [], 'the tank loss cleared it');
  assert.match(ids(C.t8Problems('x', makeRun(3, { events: [...late(520), ...lostAt(570)] }), 3)), /near threat 5 from 520 s/, 'alive 50 s before the loss');
});

test('T8 crews 3-4 kill at least 40%; a crew of 2 is not held to it', () => {
  const noKills = (crew) => {
    const r = makeRun(crew);
    for (const e of r.events) if (e.event?.type === 'kill' && e.event.e === 7) e.event = { type: 'escaped', id: e.event.id, e: 7 };
    return r;
  };
  assert.match(ids(C.t8Problems('x', noKills(3), 3)), /0 of 6 near threats killed \(at least 40%\)/);
  assert.deepEqual(C.t8Problems('x', noKills(2), 2), []);
  assert.match(ids(C.checkS1({ s1_c3_seed1: noKills(3) }, { seeds: [1] }).details), /s1_c3_seed1: 0 of 6 near threats killed/);
});

test('T9: no enemy shot in a checkpoint, losses only in WORK, each one restarted unless the segment ended', () => {
  assert.deepEqual(C.t9Problems('x', makeRun(3, { events: lostAt(350) })), []);
  // The stage 1 checkpoint: 600-660; the tick that changes the segment still belongs to the holding action.
  const shot = (t, s = -1) => [ge4(t, { type: 'shot', s, sh: 5, id: 7, src: 1, e: 2 })];
  assert.match(ids(C.t9Problems('x', makeRun(3, { events: shot(620) }))), /enemy shot at 620 s in a checkpoint/);
  assert.deepEqual(C.t9Problems('x', makeRun(3, { events: shot(600) })), []);
  assert.deepEqual(C.t9Problems('x', makeRun(3, { events: shot(620, 1) })), [], 'our own shell');
  assert.match(ids(C.t9Problems('x', makeRun(3, { events: lostAt(100) }))), /tank lost at 100 s in a WARMUP phase/);
  assert.match(ids(C.t9Problems('x', makeRun(3, { events: lostAt(630) }))), /tank lost at 630 s in a RECOVERY phase/);
  assert.match(ids(C.t9Problems('x', makeRun(3, { events: lostAt(350, 1, false) }))), /no stage_restart within 9 s/);
  assert.deepEqual(C.t9Problems('x', makeRun(3, { events: lostAt(595, 1, false) })), [], 'the segment ended inside the tow');
  const slow = makeRun(3, { events: [ge4(350, { type: 'tank_lost', n: 1, sg: 2, st: 1 }), ge4(361, { type: 'stage_restart', sg: 2, st: 1, hp: 70 })] });
  assert.match(ids(C.t9Problems('x', slow)), /no stage_restart within 9 s/);
  assert.match(ids(C.checkS1({ s1_c3_seed1: makeRun(3, { events: lostAt(350, 1, false) }) }, { seeds: [1] }).details), /no stage_restart/);
});

test('S2 (v4): the idle crew may lose the tank; every stage still overruns, grade D', () => {
  const idle = idleCrew3();
  idle.events.push(...lostAt(350));
  const r = C.checkS2(allS2({ s2_c3_idle: idle }));
  assert.equal(r.status, 'PASS', ids(r.details));
  const lazy = idleCrew3();
  lazy.events.push(...lostAt(350, 1, false));
  assert.match(ids(C.checkS2(allS2({ s2_c3_idle: lazy })).details), /s2_c3_idle: tank lost at 350 s with no stage_restart/);
});

/** A Repairs phase for peer 3 in the stage 1 holding action: its pattern 10 target. */
function repairRun(directives) {
  const r = makeRun(3, { directives });
  r.directives = r.directives.filter((d) => !(d.requested?.reason === 'boiler' && d.t >= 500 && d.t < 600));
  const ph = r.plans['3'].phases[3];
  r.plans['3'].phases[3] = { ...ph, mode: 'ERG', target_pct: 55, range_pct: [55, 70], grade_source: undefined, meta: { ...ph.meta, engine: 'repair' } };
  return r;
}
const repairReq = (t, pct, extra = {}) => ({
  id: 77,
  peer: 3,
  t,
  kind: 'request',
  accepted: true,
  reason: '',
  requested: { mode: 'ERG', target_pct: pct, reason: 'repair', source: 'tank', duration_s: 0 },
  applied: { clamped_by: [], refused: false, applied: { target_pct: pct } },
  ...extra,
});

test('S4 (v4) knows the Repairs target: pattern 10, inside its range, on its own seat', () => {
  assert.equal(C.classify(repairReq(510, 60)), 'repair');
  assert.equal(C.classify({ requested: { mode: 'SIM', target_pct: 60, reason: 'repair' } }), '', 'ERG only');
  assert.deepEqual(C.directivesProblems('x', repairRun([repairReq(510, 60)])), []);
  assert.match(ids(C.directivesProblems('x', repairRun([repairReq(510, 75)]))), /repair target 75% outside range_pct \[55,70\]/);
  // Peer 3 is on the Loader (SIM) in the next Advance: no such target there, nor in a checkpoint.
  assert.match(ids(C.directivesProblems('x', repairRun([repairReq(310, 60)]))), /repair target outside an ERG phase/);
  assert.match(ids(C.directivesProblems('x', repairRun([repairReq(610, 60)]))), /repair target outside an ERG phase/);
  const onGun = repairReq(510, 60);
  onGun.peer = 2;
  const r = repairRun([onGun]);
  assert.match(ids(C.directivesProblems('x', r)), /repair target to a rider on dynamo/);
  const raised = repairReq(510, 60, { applied: { clamped_by: [], refused: false, applied: { target_pct: 65 } } });
  assert.match(ids(C.directivesProblems('x', repairRun([raised]))), /applied ERG target % 65 above the requested 60/);
  const unnamed = repairReq(510, 60);
  unnamed.requested = { ...unnamed.requested, duration_s: 5 };
  assert.match(ids(C.directivesProblems('x', repairRun([unnamed]))), /repair with duration_s 5/);
});

test('flagSpans and lossesInSpans read the 1 Hz trace, with the telemetry lag at a span start', () => {
  const r = rescueRun('2', 500, 520, 560);
  assert.deepEqual(C.flagSpans(r, '2', 'rescue'), [[520, 559]]);
  assert.deepEqual(C.flagSpans(r, '3', 'rescue'), []);
  const at = (t) => {
    const x = rescueRun('2', 500, 520, 560);
    x.events.push(...lostAt(t));
    return C.lossesInSpans('x', x, '2', 'rescue');
  };
  assert.match(ids(at(540)), /tank lost at 540 s while peer 2 was in rescue/);
  assert.match(ids(at(520.3)), /520\.3/);
  assert.deepEqual(at(520.1), [], 'the host has not heard yet');
  assert.deepEqual(at(561), []);
});

test('S5 (v4) and S10 (v4): no tank lost while a dropped rider is in rescue or AFK', () => {
  const dyn = rescueRun('2', 500, 520, 560);
  dyn.events.push(...lostAt(540));
  const r5 = C.checkS5({ s5_c3_dynamo_drop: dyn, s5_c4_arc_drop: arcRescueRun() });
  assert.match(ids(r5.details), /s5_c3_dynamo_drop: tank lost at 540 s while peer 2 was in rescue/);
  const stop = stopRun();
  stop.events.push(...lostAt(550));
  const r10 = C.checkS10(s10Set(clientSprintRun(), stop));
  assert.match(ids(r10.details), /s10_c3_dynamo_stop: tank lost at 550 s while peer 2 was in afk/);
  const before = stopRun();
  before.events.push(...lostAt(350));
  assert.equal(C.checkS10(s10Set(clientSprintRun(), before)).status, 'PASS');
});

test('S9 (v4) counts an evade at its landing, after the shot', () => {
  const landed = [300, 660, 1020].flatMap((a, i) => [ge4(a + 40, { type: 'shot', s: -1, sh: 5, id: 40 + i, src: 10 + i, e: 3, rng_m: 1800, flight_s: 3.3 }), ge4(a + 43.3, { type: 'evade', id: 10 + i, e: 3, ok: 1, s: 0 })]);
  const r = C.checkS9({ s9_c1_sprint: sprintRun({ events: landed }) });
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.match(r.summary, /3 of 6 telegraphed shots evaded/);
});

test('S13 (v4) follows a move to the sixth seat', () => {
  assert.equal(C.ENGINE_OF_CODE[7], 'repair');
  assert.deepEqual(Object.values(C.ENGINE_OF_CODE).sort(), ['arc', 'diesel', 'dynamo', 'feed', 'repair', 'steam']);
  const r = seatRun();
  const plan3 = r.plans['3'].phases;
  for (let i = 7; i < plan3.length - 1; i += 1) plan3[i] = { ...plan3[i], meta: { ...plan3[i].meta, engine: 'repair' } };
  r.events.push(ge4(1020, { type: 'seat', s: 2, from: 3, to: 7 }));
  r.directives.push({ id: 905, peer: 3, t: 990, kind: 'replan', accepted: true, reason: '', requested: {} });
  assert.deepEqual(C.seatProblems('x', r), []);
  assert.equal(C.seatAt(r, '3', 1100), 'repair');
});

// --- S14-S18 -----------------------------------------------------------------------------------------------------

/** The clean report \`name\` promises, by its name. */
function matrixReport(name, over = {}) {
  const w = C.matrixRun(name);
  return makeRun(w.players, { content: w.content, options: { difficulty: w.difficulty }, bots: w.bots, seed: w.seed, rider: w.rider, ...over });
}
const seedsOf = [1, 2, 3];

test('matrixRun reads a report name into what it promises, and nothing else', () => {
  assert.deepEqual(C.matrixRun('s14_easy_c1_seed2'), { id: 'S14', content: 'ashfall_road', difficulty: 'easy', players: 1, bots: 0, seed: 2, role: 'SOLO', rider: 'erg:compliance=1.0' });
  assert.deepEqual(C.matrixRun('s16_amb_normal_c4_seed3'), { id: 'S16', content: 'ambush_15', difficulty: 'normal', players: 4, bots: 0, seed: 3, role: 'HOST', rider: 'erg:compliance=1.0' });
  assert.equal(C.matrixRun('s17_hard_c3_c85_seed1').rider, 'erg:compliance=0.85');
  assert.equal(C.matrixRun('s17_hard_c3_c70_seed1').rider, 'erg:compliance=0.70');
  assert.deepEqual(C.matrixRun('s18_bots_h1b3'), { id: 'S18', content: 'ambush_15', difficulty: 'hard', players: 1, bots: 3, seed: 1, role: 'SOLO', rider: 'erg:compliance=1.0' });
  assert.equal(C.matrixRun('s18_bots_h2b2').role, 'HOST');
  for (const n of ['s1_c3_seed1', 's4_drill_c1', 's14_hard_c1_seed1', 's16_amb_easy_c1_seed1']) assert.equal(C.matrixRun(n), null, n);
  assert.deepEqual([C.mostOf(3), C.mostOf(1), C.mostOf(2)], [2, 1, 2]);
});

test('argsProblems (v4) checks the difficulty and the rider a run was started with', () => {
  const r = matrixReport('s15_hard_c3_seed1');
  assert.deepEqual(C.argsProblems('x', r, C.matrixRun('s15_hard_c3_seed1')), []);
  assert.match(ids(C.argsProblems('x', r, C.matrixRun('s14_easy_c3_seed1'))), /difficulty hard, wanted easy/);
  assert.match(ids(C.argsProblems('x', r, { rider: 'erg:compliance=0.85' })), /rider erg:compliance=1\.0, wanted erg:compliance=0\.85/);
});

test('S4 (v4) reads the S14-S18 reports too, with their real content and bots', () => {
  const set = { ...goodSet(seedsOf), s4_drill_c1: makeRun(1, { content: 'drill' }), s4_drill_c2: makeRun(2, { content: 'drill' }), s4_drill_c3: makeRun(3, { content: 'drill' }), s4_drill_c4: makeRun(4, { content: 'drill' }) };
  // goodSet's drill-less report shape would flag its 12 laps on the drill: only the new reports are under test here.
  const base = C.checkS4(set, { seeds: seedsOf }).details.length;
  const clean = { ...set, s18_bots_h1b3: matrixReport('s18_bots_h1b3'), s16_amb_hard_c3_seed1: matrixReport('s16_amb_hard_c3_seed1') };
  assert.equal(C.checkS4(clean, { seeds: seedsOf }).details.length, base, 'clean matrix reports add nothing, and the bot name does not throw');
  const refused = matrixReport('s18_bots_h1b3', { directives: [req(1, 310, { mode: 'SIM', mode_grade: 3, reason: 'boiler', source: 'tank', duration_s: 0 }, { accepted: false, reason: 'nope', id: 5 })] });
  assert.match(ids(C.checkS4({ ...set, s18_bots_h1b3: refused }, { seeds: seedsOf }).details), /s18_bots_h1b3: directive 5 .* refused: nope/);
  const wrong = matrixReport('s15_hard_c1_seed1', { options: { difficulty: 'easy' } });
  assert.match(ids(C.checkS4({ ...set, s15_hard_c1_seed1: wrong }, { seeds: seedsOf }).details), /s15_hard_c1_seed1: difficulty easy, wanted hard/);
  const laps = matrixReport('s16_amb_hard_c1_seed1');
  laps.plans['1'].phases[2].lap = false;
  delete laps.plans['1'].phases[2].meta.offset_s;
  assert.match(ids(C.checkS4({ ...set, s16_amb_hard_c1_seed1: laps }, { seeds: seedsOf }).details), /s16_amb_hard_c1_seed1: peer 1 plan has 6 lap-true phases, wanted 7/);
  const fast = matrixReport('s14_easy_c1_seed1', { extraRows: (row) => (row.mode === 'ERG' ? { ...row, applied_pct: 120, applied_target_w: 240 } : row) });
  assert.match(ids(C.checkS4({ ...set, s14_easy_c1_seed1: fast }, { seeds: seedsOf }).details), /s14_easy_c1_seed1: peer 1 applied ERG 120% FTP/);
});

const s14Set = (over = {}) => {
  const out = {};
  for (const c of C.CREWS) for (const s of seedsOf) out[`s14_easy_c${c}_seed${s}`] = matrixReport(`s14_easy_c${c}_seed${s}`);
  return { ...out, ...over };
};

test('S14 Easy: victory every run, no loss, T1', () => {
  const r = C.checkS14(s14Set(), { seeds: seedsOf });
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.equal(C.checkS14({}, { seeds: seedsOf }).status, 'SKIP');
  const { s14_easy_c1_seed1: _gone, ...some } = s14Set();
  assert.match(ids(C.checkS14(some, { seeds: seedsOf }).details), /missing report s14_easy_c1_seed1/);
  const n = 's14_easy_c3_seed2';
  assert.match(ids(C.checkS14(s14Set({ [n]: matrixReport(n, { finished: 'withdrawn' }) }), { seeds: seedsOf }).details), /s14_easy_c3_seed2: finished "withdrawn", wanted victory/);
  assert.match(ids(C.checkS14(s14Set({ [n]: matrixReport(n, { events: lostAt(350) }) }), { seeds: seedsOf }).details), /1 tank losses on Easy/);
  assert.match(ids(C.checkS14(s14Set({ [n]: matrixReport(n, { grade: 'C' }) }), { seeds: seedsOf }).details), /grade C/);
  assert.match(ids(C.checkS14(s14Set({ [n]: matrixReport(n, { durations: { boss: 340 } }) }), { seeds: seedsOf }).details), /boss 4 lasted 340/);
});

const s15Set = (lossesBySeed = [1, 2, 1], over = {}) => {
  const out = {};
  for (const c of C.CREWS) {
    seedsOf.forEach((s, i) => {
      const events = [];
      for (let k = 0; k < lossesBySeed[i]; k += 1) events.push(...lostAt(320 + 50 * k, k + 1));
      out[`s15_hard_c${c}_seed${s}`] = matrixReport(`s15_hard_c${c}_seed${s}`, { events });
    });
  }
  return { ...out, ...over };
};

test('S15 Hard: 1-2 losses on at least 2 of 3 seeds per crew, none above 4, phases and the plan hold', () => {
  const r = C.checkS15(s15Set(), { seeds: seedsOf });
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.match(r.summary, /c3 losses 1\/2\/1/);
  assert.equal(C.checkS15({}, { seeds: seedsOf }).status, 'SKIP');
  assert.equal(C.checkS15(s15Set([0, 1, 2]), { seeds: seedsOf }).status, 'PASS', 'one easy seed is allowed');
  assert.match(ids(C.checkS15(s15Set([0, 0, 1]), { seeds: seedsOf }).details), /crew 1: 1 of 3 seeds with 1-2 losses \(at least 2; losses 0, 0, 1\)/);
  assert.match(ids(C.checkS15(s15Set([3, 3, 1]), { seeds: seedsOf }).details), /crew 3: 1 of 3 seeds with 1-2 losses/);
  assert.match(ids(C.checkS15(s15Set([5, 1, 1]), { seeds: seedsOf }).details), /s15_hard_c1_seed1: 5 tank losses \(at most 4\)/);
  // A subset run: one seed, one crew's worth of target.
  assert.equal(C.checkS15(Object.fromEntries(Object.entries(s15Set()).filter(([n]) => n.endsWith('seed1'))), { seeds: [1] }).status, 'PASS');
});

test('phaseBoundProblems holds every open segment to min_s..max_s, through a split; planMaxS is the longest plan', () => {
  assert.deepEqual(C.phaseBoundProblems('x', makeRun(3)), []);
  assert.match(ids(C.phaseBoundProblems('x', makeRun(3, { durations: { advance: 310 } }))), /peer 1 advance 1 lasted 310 s \(90-300\)/);
  assert.match(ids(C.phaseBoundProblems('x', makeRun(3, { durations: { gun_line: 50 } }))), /peer 1 gun_line 1 lasted 50 s \(60-180\)/);
  assert.deepEqual(C.phaseBoundProblems('x', makeRun(3, { durations: { advance: 300.05 } })), [], 'a tick past max_s');
  assert.deepEqual(C.phaseBoundProblems('x', splitRun()), [], 'a split segment is one segment');
  // 300 + 3 x (300 + 180 + 60) + 360 + the cool-down.
  assert.equal(C.planMaxS(makeRun(3)), 300 + 3 * 540 + 360 + 180);
  assert.equal(C.planMaxS(splitRun()), 300 + 3 * 540 + 360 + 180, 'the rest of a split adds nothing');
  assert.equal(C.planMaxS(makeRun(3, { content: 'ambush_15' })), 1010);
  const over = makeRun(3);
  over.game_seconds = 2500;
  assert.match(ids(C.planTotalProblems('x', over)), /2500 game seconds, over the plan's longest 2460 s/);
  assert.deepEqual(C.planTotalProblems('x', makeRun(3)), []);
  const s = s15Set();
  s.s15_hard_c2_seed1.game_seconds = 2500;
  assert.match(ids(C.checkS15(s, { seeds: seedsOf }).details), /s15_hard_c2_seed1: 2500 game seconds/);
});

const s16Set = (over = {}) => {
  const out = {};
  for (const c of [1, 3, 4]) {
    for (const s of seedsOf) {
      out[`s16_amb_normal_c${c}_seed${s}`] = matrixReport(`s16_amb_normal_c${c}_seed${s}`);
      out[`s16_amb_hard_c${c}_seed${s}`] = matrixReport(`s16_amb_hard_c${c}_seed${s}`, { events: lostAt(320) });
    }
  }
  return { ...out, ...over };
};

test('S16 ambush_15: Normal at most a loss and mostly wins, Hard 1-2 losses mostly, 780-1010 game seconds', () => {
  const r = C.checkS16(s16Set(), { seeds: seedsOf });
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.equal(C.checkS16({}, { seeds: seedsOf }).status, 'SKIP');
  const d = (over) => ids(C.checkS16(s16Set(over), { seeds: seedsOf }).details);
  const nn = (s) => `s16_amb_normal_c3_seed${s}`;
  assert.match(d({ [nn(1)]: matrixReport(nn(1), { events: [...lostAt(320), ...lostAt(500, 2)] }) }), /s16_amb_normal_c3_seed1: 2 tank losses \(at most 1 on Normal\)/);
  // One seed may fall short, and is not then held to T1's times; two may not.
  const short = (s) => matrixReport(nn(s), { finished: 'withdrawn', grade: 'D', durations: { boss: 190 }, ended: { 5: 'max_s' } });
  assert.equal(C.checkS16(s16Set({ [nn(1)]: short(1) }), { seeds: seedsOf }).status, 'PASS');
  assert.match(d({ [nn(1)]: short(1), [nn(2)]: short(2) }), /normal crew 3: 1 of 3 seeds won \(at least 2\)/);
  assert.match(d({ [nn(1)]: matrixReport(nn(1), { durations: { advance: 170 } }) }), /advance 1 lasted 170/, 'T1 holds a win');
  const hh = (s) => `s16_amb_hard_c4_seed${s}`;
  assert.match(d({ [hh(1)]: matrixReport(hh(1)), [hh(2)]: matrixReport(hh(2)) }), /hard crew 4: 1 of 3 seeds with 1-2 losses/);
  const longest = matrixReport(nn(1));
  longest.game_seconds = 1020;
  assert.match(d({ [nn(1)]: longest }), /s16_amb_normal_c3_seed1: 1020 game seconds \(780-1010\)/);
  const shortest = matrixReport(nn(1));
  shortest.game_seconds = 770;
  assert.match(d({ [nn(1)]: shortest }), /770 game seconds/);
});

const s17Set = (over = {}) => {
  const out = {};
  for (const s of seedsOf) {
    out[`s15_hard_c3_seed${s}`] = matrixReport(`s15_hard_c3_seed${s}`, { events: lostAt(320) });
    out[`s17_hard_c3_c85_seed${s}`] = matrixReport(`s17_hard_c3_c85_seed${s}`, { events: [...lostAt(320), ...lostAt(800, 2)] });
  }
  out.s17_hard_c3_c70_seed1 = matrixReport('s17_hard_c3_c70_seed1');
  return { ...out, ...over };
};

test('S17: strictly more losses at 85% than at 100%; at 70% no loss inside anyone\'s rescue', () => {
  const r = C.checkS17(s17Set(), { seeds: seedsOf });
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.match(r.summary, /mean losses 100% 1, 85% 2, 70% 0/);
  assert.equal(C.checkS17({}, { seeds: seedsOf }).status, 'SKIP');
  const same = {};
  for (const s of seedsOf) same[`s17_hard_c3_c85_seed${s}`] = matrixReport(`s17_hard_c3_c85_seed${s}`, { events: lostAt(320) });
  assert.match(ids(C.checkS17(s17Set(same), { seeds: seedsOf }).details), /mean losses at 85% \(1\) are not above 100% \(1\)/);
  const { s15_hard_c3_seed2: _gone, ...noBase } = s17Set();
  assert.match(ids(C.checkS17(noBase, { seeds: seedsOf }).details), /missing report s15_hard_c3_seed2/);
  const n = 's17_hard_c3_c70_seed1';
  const inRescue = (row, p) => (p === '3' && row.t >= 700 && row.t < 760 ? { ...row, rescue: true } : row);
  const wiped = matrixReport(n, { extraRows: inRescue, events: lostAt(720) });
  assert.match(ids(C.checkS17(s17Set({ [n]: wiped }), { seeds: seedsOf }).details), /tank lost at 720 s while peer 3 was in rescue/);
  const outside = matrixReport(n, { extraRows: inRescue, events: lostAt(330) });
  assert.equal(C.checkS17(s17Set({ [n]: outside }), { seeds: seedsOf }).status, 'PASS');
  assert.match(ids(C.checkS17(s17Set({ [n]: matrixReport(n, { endReason: 'timeout' }) }), { seeds: seedsOf }).details), /end_reason timeout/);
  assert.match(ids(C.checkS17(s17Set({ [n]: matrixReport(n, { rider: 'erg:compliance=0.85' }) }), { seeds: seedsOf }).details), /rider erg:compliance=0\.85, wanted erg:compliance=0\.70/);
});

/** Crew of one human and three bots: bot slot 1 moves to the Secondaries, slot 2 to Repairs. */
function botRun(over = {}) {
  const moves = [ge4(340, { type: 'seat', s: 1, from: 2, to: 6 }), ge4(400, { type: 'seat', s: 2, from: 3, to: 7 })];
  return matrixReport('s18_bots_h1b3', { events: over.events ?? moves, directives: over.directives ?? [] });
}
const s18Set = (a = botRun(), b = matrixReport('s18_bots_h2b2', { events: [ge4(340, { type: 'seat', s: 2, from: 3, to: 6 })] })) => ({ s18_bots_h1b3: a, s18_bots_h2b2: b });

test('S18 bots: complete, nothing refused, bots act only through their own seats', () => {
  const r = C.checkS18(s18Set());
  assert.equal(r.status, 'PASS', ids(r.details));
  assert.match(r.summary, /s18_bots_h1b3 victory, 2 seat moves, 0 losses/);
  assert.equal(C.checkS18({}).status, 'SKIP');
  assert.match(ids(C.checkS18({ s18_bots_h1b3: botRun() }).details), /missing report s18_bots_h2b2/);
  const stuck = matrixReport('s18_bots_h1b3', { endReason: 'timeout' });
  assert.match(ids(C.checkS18(s18Set(stuck)).details), /end_reason timeout/);
  const refused = botRun({ directives: [req(1, 310, { mode: 'SIM', mode_grade: 3, reason: 'boiler', source: 'tank', duration_s: 0 }, { accepted: false, reason: 'nope', id: 5 })] });
  assert.match(ids(C.checkS18(s18Set(refused)).details), /directive 5 .* refused: nope/);
  const idle = matrixReport('s18_bots_h1b3');
  assert.match(ids(C.botSeatProblems('x', idle)), /no bot ever moved seats/);
});

test('S18: a bot on a human\'s seat, or a human\'s trainer moved with no move of its own, fails', () => {
  // The human (slot 0) starts on Drive (code 1).
  const onHuman = botRun({ events: [ge4(340, { type: 'seat', s: 1, from: 2, to: 1 })] });
  assert.match(ids(C.botSeatProblems('x', onHuman)), /bot slot 1 landed on diesel at 340 s, peer 1's seat/);
  // A cover swap: the human moves off in the same tick, so the bot takes a seat that is free.
  const swap = botRun({ events: [ge4(340, { type: 'seat', s: 0, from: 1, to: 6 }), ge4(340, { type: 'seat', s: 3, from: 6, to: 1 })] });
  assert.deepEqual(C.botSeatProblems('x', swap), []);
  const split = { id: 9, peer: 1, t: 350, kind: 'split', accepted: true, reason: '', requested: {} };
  assert.match(ids(C.botSeatProblems('x', botRun({ directives: [split] }))), /split 9 to human peer 1 at 350 s with no seat move of its own/);
  const own = botRun({ events: [ge4(340, { type: 'seat', s: 0, from: 1, to: 6 }), ge4(345, { type: 'seat', s: 1, from: 2, to: 7 })], directives: [split] });
  assert.deepEqual(C.botSeatProblems('x', own), []);
  const botSplit = { id: 10, peer: -1, t: 350, kind: 'split', accepted: true, reason: '', requested: {} };
  assert.deepEqual(C.botSeatProblems('x', botRun({ directives: [botSplit] })), [], 'a bot follows its own seat on its own trainer');
});

// --- FIT, arguments, main ----------------------------------------------------------------------------------------------

test('fitGroups groups existing FIT files by expected laps and skips what is not there', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tank-fit-'));
  fs.mkdirSync(path.join(dir, 'fit'));
  fs.writeFileSync(path.join(dir, 'fit', 's1_c1_seed1_slot0.fit'), 'x');
  fs.writeFileSync(path.join(dir, 'fit', 's2_c1_zero_slot0.fit'), 'x');
  const reports = { s1_c1_seed1: makeRun(1), s2_c1_zero: zeroCrew1(), s4_drill_c1: makeRun(1, { content: 'drill' }) };
  const groups = C.fitGroups(reports, dir);
  assert.deepEqual([...groups.keys()].sort(), ['13', 'none']);
  assert.equal(groups.get('13').length, 1);
  assert.equal(C.checkFit({}, dir, dir).status, 'SKIP');
});

test('parseArgs and runChecks', () => {
  assert.throws(() => C.parseArgs([]), /usage/);
  assert.throws(() => C.parseArgs(['d', '--nope']), /unknown option/);
  assert.throws(() => C.parseArgs(['d', '--only=S8']), /unknown scenario/);
  assert.deepEqual(C.parseArgs(['d', '--only=s14,S15,s16,S17,s18']).only, ['S14', 'S15', 'S16', 'S17', 'S18']);
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
