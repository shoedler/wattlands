#!/usr/bin/env node
// tests/games/tank/sim/check_sims.mjs: asserts brief section 4's simulation matrix (S1-S7, plus S9 the sprint
// half of the workout and S10 the network paths; S8 is the GUT test test_tank_s8.gd) and the tuning targets T1-T6 over the reports
// tools/run_game_sim wrote.
//
//   node tests/games/tank/sim/check_sims.mjs build/tank/sims [--only=S1,S4] [--seeds=1,2,3] [--fit]
//                                           [--require-prompts]
//
// One PASS / FAIL / SKIP line per scenario (details of a failure indented below it), exit 1 when any
// scenario failed, 2 on usage or I/O errors. A scenario whose reports are all missing is SKIP (a
// subset run); one that has some but not all is FAIL. `--fit` also runs tools/fit_check on every FIT
// file the reports name (laps expected: ashfall_road 12, drill 4; none for a run that did not
// complete). Zero dependencies, so `node --test` in tests/games/tank/sim runs the unit tests
// (check_sims.test.mjs) anywhere.
//
// Report names (written by run_sims.sh; the scenario is read from the name, the content, players and
// seed are cross-checked against the report's own `args`):
//   s1_c<crew>_seed<n>     ashfall_road, compliant `erg` riders (crews 2-3 as HOST)
//   s2_c3_zero, s2_c1_zero crew 3 at 0 W (HOST: the shared pause holds the depot), crew 1 at 0 W (SOLO: paused)
//   s2_c3_idle             crew 3 spinning at 10 W and 25 rpm (pedaling for every detector, no effort): overruns
//   s3_c3_c85_seed<n>, s3_c3_c70_seed<n>   crew 3 at compliance 0.85 / 0.70 (100% is s1_c3_seed<n>)
//   s4_drill_c<crew>       the drill, compliant (S4 also reads every s1 report)
//   s5_c3_dynamo_drop, s5_c3_gunline_drop  cadence to 30 rpm in a dynamo stage / a 90% gun line
//   s6_c3_haptics_off      crew 3, slot 0 opted out of haptics
//   s7_c3_seed1            s1_c3_seed1 again
//   s9_c1_sprint           crew 1 with a scripted sprinter (intervals), the sprint half of the workout: Ram, ram haptic,
//                          the gun line entered straight after a sprint (S8 is the GUT test test_tank_s8.gd)
//   s10_c3_clients_sprint  crew 3, every rider a scripted sprinter: the clients' Rams arrive as telemetry intents
//   s10_c3_dynamo_stop     crew 3, slot 1 stops pedaling for 60 s in the stage 1 gun line (rescue, AFK, reserve, back)
//
// Definitions (the numbers are brief 2.3, 2.4 and 4):
//   segment       a plan phase with its span in `phases[peer]` (game seconds) and how it ended
//                 (`ended_by`: duration, end_phase or max_s: an overrun is max_s on a WORK phase).
//   T1            every Advance 150-240 s, gun line 80-160 s, boss 180-330 s, no overrun, at most 1
//                 breakdown (game events), grade S/A/B.
//   T2 (crews 2-3) the dynamo's applied ERG target (trace rows, % FTP) is above 80% for >= 30 s per
//                 stage (Advance + gun line) and >= 60 s in the boss, and is back at <= 65% within
//                 120 s after each dynamo gun line or boss ends.
//   T3 (crew 3)   each heavy shell (latch event, shell code 2) is built in 18-35 s: from the later of
//                 the previous main-gun shot + the 6 s breech cycle and the segment start, to the
//                 latch (the 5 s window included); a shell that is the first of its segment is only
//                 held to 35 s (pressure holds across a checkpoint). After the latch the latching
//                 rider's own boiler grade (the event's slot, not any other steam rider's) stays 0
//                 for >= 6 s (the breech cycle), unless that rider leaves SIM first (a checkpoint).
//   T4 (crew 1)   the Bulwark's lever is on Drive for >= 60% of each Advance (lever events; the
//                 lever starts on Drive).
//   T5            mean score falls strictly from 100% (s1_c3) to 85% to 70%.
//   T6            every Advance has a light and a medium tank in it (enemy `shot` or `kill`
//                 events; also a "Surge to ram" toast for crew 1, whose host rider drives, or for every
//                 crew with --require-prompts); stages 2 and 3 end in a heavy-tank duel: the gun line
//                 lasts 90-180 s and a heavy tank fired or died in it.
//   S9 (crew 1)   the sprinting rider (scripted intervals, not a compliant one): a successful Ram in every
//                 Advance, each Ram's haptic sent and accepted (S4 holds it to SIM riders), and a gun line
//                 entered while still sprinting starts at its planned target, not at the sprint power.
//   S10 (crew 3)  every rider a sprinter: a client's Ram (an intent over Telemetry.intents, owned by the diesel) destroys
//                 something; and a dynamo rider who stops in a gun line is rescued, goes AFK within 10 s, is announced
//                 as on reserve, comes back, with nobody else affected and the plan completing.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const CREWS = [1, 2, 3];
export const DEFAULT_SEEDS = [1, 2, 3];
/** FIT laps: lap-true plan phases + the cool-down (the platform marks it lap true; ADR G0.2). */
export const EXPECTED_LAPS = { ashfall_road: 12, drill: 4 };
export const T1_RANGES = { advance: [150, 240], gun_line: [80, 160], boss: [180, 330] };
export const T6_DUEL_RANGE = [90, 180];
export const T2_ABOVE_PCT = 80;
export const T2_PER_STAGE_S = 30;
export const T2_BOSS_S = 60;
export const T2_BACK_PCT = 65;
export const T2_BACK_WITHIN_S = 120;
export const T3_BUILD_RANGE = [18, 35];
export const T3_GRADE0_MIN_S = 6;
export const BREECH_CYCLE_S = 6;
export const T4_MIN_SHARE = 0.6;
export const SWITCH_SPACING_S = 60;
export const FIRST_S = 300;
/** BRIEF 4.6: the first 300 s are ERG at 65% FTP at most or SIM at -2..+3% grade; the stacked grade is -10..+16% in total (range clamp +10% before the haptic). */
export const FIRST_ERG_MAX_PCT = 65;
export const FIRST_GRADE_MIN_PCT = -2;
export const FIRST_GRADE_MAX_PCT = 3;
export const TOTAL_GRADE_MAX_PCT = 16;
export const RANGE_GRADE_MAX_PCT = 10;
export const MAX_SNAPSHOT_BYTES = 4096;
export const PAUSE_AFTER_S = 10;
export const TICK_S = 0.05;
export const GRADE_ORDER = ['S', 'A', 'B', 'C', 'D'];
const EPS = 1e-6;

// Event codes (TankIds).
export const SHELL_LIGHT = 1;
export const SHELL_HEAVY = 2;
export const SHELL_BOW = 4;
export const ENEMY_LIGHT = 1;
export const ENEMY_MEDIUM = 2;
export const ENEMY_HEAVY = 5;
export const BY_BARRAGE = 2;
export const LEVER_DRIVE = 0;

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const sum = (a) => a.reduce((x, y) => x + y, 0);
const mean = (a) => (a.length ? sum(a) / a.length : 0);
const fmt = (n) => (Number.isFinite(n) ? String(Math.round(n * 100) / 100) : String(n));
const num = (v, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);

// --- reading reports ---------------------------------------------------------------------------------

/** {name: report} for every *.json directly in `dir` that looks like a run_game_sim report of tank. */
export function loadReports(dir) {
  const out = {};
  for (const f of fs.readdirSync(dir).sort()) {
    if (!f.endsWith('.json')) continue;
    let r;
    try {
      r = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    } catch (err) {
      throw new Error(`cannot read ${path.join(dir, f)}: ${err.message}`);
    }
    if (isObj(r) && r.schema === 1 && r.game_id === 'tank') out[f.slice(0, -5)] = r;
  }
  return out;
}

/** The host's Tank game events (the `event` of each game_event), in order, with the report time `_t`. */
export function gameEvents(report) {
  const out = [];
  for (const e of report.events ?? []) {
    if (e && e.type === 'game_event' && isObj(e.event)) out.push({ ...e.event, _t: num(e.t) });
  }
  return out;
}
export const eventsOf = (report, type) => gameEvents(report).filter((e) => e.type === type);

/** Human slot peers in slot order, as strings (the keys of plans, phases and trace). */
export function humanPeers(report) {
  return (report.slots ?? []).filter((s) => !s.is_bot).map((s) => String(s.peer));
}
export const hostPeer = (report) => humanPeers(report)[0] ?? '1';
export const slotOf = (report, peer) => (report.slots ?? []).find((s) => String(s.peer) === String(peer)) ?? {};
export const planOf = (report, peer) => report.plans?.[peer]?.phases ?? [];
export const spansOf = (report, peer) => report.phases?.[peer] ?? [];
export const traceOf = (report, peer) => report.trace?.[peer] ?? [];
export const scoreOf = (report) => num(report.results?.score, NaN);
export const gradeOf = (report) => String(report.results?.grade ?? '');

/** The plan phase index `peer` is in at game time t (the last span whose start <= t), or -1. */
export function phaseIndexAt(report, peer, t) {
  let idx = -1;
  for (const sp of spansOf(report, peer)) if (num(sp.start) <= t + EPS) idx = num(sp.index);
  return idx;
}

/** [{index, seg, stage, kind, mode, engine, start, end, dur, endedBy, overran}] of one rider's plan. */
export function segmentsOf(report, peer = hostPeer(report)) {
  const plan = planOf(report, peer);
  return spansOf(report, peer).map((sp) => {
    const ph = plan[num(sp.index)] ?? {};
    const start = num(sp.start);
    const end = num(sp.end, -1) >= 0 ? num(sp.end) : NaN;
    return {
      index: num(sp.index),
      seg: ph.meta?.seg ?? (ph.kind === 'COOLDOWN' ? 'cooldown' : ''),
      stage: num(ph.meta?.stage),
      kind: ph.kind ?? sp.kind,
      mode: ph.mode ?? sp.mode,
      engine: ph.meta?.engine ?? '',
      start,
      end,
      dur: end - start,
      endedBy: sp.ended_by ?? '',
      overran: sp.ended_by === 'max_s',
    };
  });
}

/** Plan phases with lap true (the cool-down included, ADR G0.2). */
export const planLaps = (report, peer = hostPeer(report)) => planOf(report, peer).filter((p) => p.lap).length;

// --- result helpers ------------------------------------------------------------------------------------

function result(id, title, problems, extra = '') {
  const ok = problems.length === 0;
  return { id, status: ok ? 'PASS' : 'FAIL', summary: `${title}${extra ? `: ${extra}` : ''}`, details: problems };
}
const skip = (id, title, why) => ({ id, status: 'SKIP', summary: `${title}: ${why}`, details: [] });

/** [[name, report]] for `names`; `missing` lists the names not present. */
function pick(reports, names) {
  const found = [];
  const missing = [];
  for (const n of names) (reports[n] ? found : missing).push(n);
  return { found: found.map((n) => [n, reports[n]]), missing };
}

/** Sanity of one report against what its name promises: content, players, seed, role. */
export function argsProblems(name, r, want) {
  const probs = [];
  const a = r.args ?? {};
  if (want.content && r.content_id !== want.content) probs.push(`${name}: content ${r.content_id}, wanted ${want.content}`);
  if (want.players !== undefined && num(a.players) !== want.players) probs.push(`${name}: players ${a.players}, wanted ${want.players}`);
  if (want.bots !== undefined && num(a.bots ?? 0) !== want.bots) probs.push(`${name}: bots ${a.bots}, wanted ${want.bots}`);
  if (want.seed !== undefined && num(r.seed) !== want.seed) probs.push(`${name}: seed ${r.seed}, wanted ${want.seed}`);
  if (want.role && r.role !== want.role) probs.push(`${name}: role ${r.role}, wanted ${want.role}`);
  return probs;
}

/** A run that played to the end: complete, a mission outcome, clean plans, directives and snapshots. */
export function completeProblems(name, r, outcomes = ['victory', 'withdrawn', 'complete']) {
  const probs = [];
  if (r.end_reason !== 'complete') probs.push(`${name}: end_reason ${r.end_reason}`);
  if (!outcomes.includes(r.finished_reason)) probs.push(`${name}: finished_reason "${r.finished_reason}", wanted ${outcomes.join('/')}`);
  return probs;
}

/**
 * A remote rider's governor acks each terrain `course_grade` it applies with id 0 (the platform keeps no id for it).
 * An ack is paired with a request by peer, order and value, not by a fixed time window; this only bounds how stale
 * a pairing may be (the measured lag is 0.05-0.2 s, the terrain period 0.5 s), so a change in loopback latency or
 * sim speed cannot turn the acks into false failures while an ack from far away still counts as a stray.
 */
export const COURSE_GRADE_ACK_MAX_LAG_S = 2;
/** Two grade values (% grade) are the same value below this difference. */
export const GRADE_VALUE_EPS = 1e-6;

/**
 * The applied records that match no request, minus the remote governors' course-grade acks: those
 * carry id 0 and belong to pattern 4 (terrain, 2 Hz). In time order each ack takes the first still
 * unclaimed `course_grade` request of the same peer, logged no later than the ack and at most
 * COURSE_GRADE_ACK_MAX_LAG_S before it, whose `grade_pct` equals the ack's `course_grade_pct` (older
 * requests the governor never acked are passed over). An ack without such a request, a second ack for
 * one request and an ack that applied another grade than the one requested all stay problems. The request
 * it pairs with is checked on its own (directiveProblems: a grade_source game SIM phase only), so an ack
 * is always one the director was allowed to ask for.
 */
export function unmatchedAcks(r) {
  const pool = new Map();
  for (const d of r.directives ?? []) {
    if (d.kind !== 'course_grade') continue;
    const k = String(d.peer);
    if (!pool.has(k)) pool.set(k, []);
    pool.get(k).push({ t: num(d.t), grade: num(d.requested?.grade_pct, NaN) });
  }
  for (const list of pool.values()) list.sort((a, b) => a.t - b.t);
  const stray = [];
  const acks = (r.directives_unmatched ?? []).map((rec, i) => ({ rec, i })).sort((a, b) => num(a.rec.t) - num(b.rec.t) || a.i - b.i);
  for (const { rec } of acks) {
    const list = pool.get(String(rec.peer)) ?? [];
    const t = num(rec.t);
    const grade = num(rec.applied?.course_grade_pct, NaN);
    const at =
      rec.kind === 'course_grade' && num(rec.id) === 0 && rec.refused !== true && Number.isFinite(grade)
        ? list.findIndex((q) => t - q.t >= -EPS && t - q.t <= COURSE_GRADE_ACK_MAX_LAG_S + EPS && Math.abs(q.grade - grade) <= GRADE_VALUE_EPS)
        : -1;
    if (at < 0) stray.push(rec);
    else list.splice(0, at + 1);
  }
  return stray;
}

/** Plan warnings, unmatched or refused directives, oversize snapshots (S4's housekeeping). */
export function cleanProblems(name, r) {
  const probs = [];
  for (const [peer, w] of Object.entries(r.plan_warnings ?? {})) {
    if (Array.isArray(w) && w.length) probs.push(`${name}: peer ${peer} plan warnings ${JSON.stringify(w)}`);
  }
  const stray = unmatchedAcks(r);
  if (stray.length) probs.push(`${name}: ${stray.length} unmatched applied records (first: ${JSON.stringify(stray[0])})`);
  let refused = 0;
  for (const d of r.directives ?? []) {
    if (d.accepted === false) {
      refused += 1;
      if (refused <= 3) probs.push(`${name}: directive ${d.id} (${d.kind} peer ${d.peer} at ${fmt(num(d.t))} s) refused: ${d.reason}`);
    } else if (d.kind === 'request' && isObj(d.applied) && d.applied.refused === true) {
      refused += 1;
      if (refused <= 3) probs.push(`${name}: directive ${d.id} refused by the governor: ${d.applied.reason}`);
    }
  }
  if (num(r.oversize_snapshots) > 0) probs.push(`${name}: ${r.oversize_snapshots} oversize snapshots`);
  if (num(r.max_snapshot_bytes) > MAX_SNAPSHOT_BYTES) probs.push(`${name}: largest snapshot ${r.max_snapshot_bytes} B (> ${MAX_SNAPSHOT_BYTES})`);
  return probs;
}

// --- T1-T4, T6 --------------------------------------------------------------------------------------------

export const breakdowns = (r) => eventsOf(r, 'breakdown').length;

/** T1 on one compliant run. */
export function t1Problems(name, r) {
  const probs = [];
  for (const s of segmentsOf(r)) {
    const lim = T1_RANGES[s.seg];
    if (lim && (!(s.dur >= lim[0] - EPS) || !(s.dur <= lim[1] + EPS))) {
      probs.push(`${name}: ${s.seg} ${s.stage} lasted ${fmt(s.dur)} s (${lim[0]}-${lim[1]})`);
    }
    if (s.overran && s.kind === 'WORK') probs.push(`${name}: ${s.seg} ${s.stage} overran (ended at max_s)`);
  }
  const b = breakdowns(r);
  if (b > 1) probs.push(`${name}: ${b} breakdowns (at most 1)`);
  const g = gradeOf(r);
  if (GRADE_ORDER.indexOf(g) < 0 || GRADE_ORDER.indexOf(g) > GRADE_ORDER.indexOf('B')) probs.push(`${name}: grade ${g} (B or better)`);
  return probs;
}

/** The applied ERG % FTP rows of `peer` in plan phase `index`. */
const ergRows = (r, peer, index) => traceOf(r, peer).filter((row) => num(row.phase) === index && row.mode === 'ERG');

/** T2 on one compliant crew 2-3 run: seconds above 80% per stage and the return to <= 65%. */
export function t2Problems(name, r) {
  const probs = [];
  const perStage = {};
  for (const peer of humanPeers(r)) {
    const plan = planOf(r, peer);
    const spans = segmentsOf(r, peer);
    plan.forEach((ph, index) => {
      const seg = ph.meta?.seg;
      if (ph.meta?.engine !== 'dynamo' || !['advance', 'gun_line', 'boss'].includes(seg)) return;
      const stage = num(ph.meta.stage);
      const rows = ergRows(r, peer, index);
      perStage[stage] = (perStage[stage] ?? 0) + rows.filter((row) => num(row.applied_pct) > T2_ABOVE_PCT).length;
      const sp = spans.find((s) => s.index === index);
      if (seg !== 'advance' && sp && Number.isFinite(sp.end)) {
        const after = traceOf(r, peer).filter((row) => num(row.game_t) > sp.end - EPS && num(row.game_t) <= sp.end + T2_BACK_WITHIN_S + EPS);
        if (after.length && !after.some((row) => num(row.applied_pct) <= T2_BACK_PCT + EPS)) {
          probs.push(`${name}: peer ${peer} ${seg} ${stage}: the target stayed above ${T2_BACK_PCT}% for ${T2_BACK_WITHIN_S} s after the fight`);
        }
      }
    });
  }
  const stages = Object.keys(perStage).map(Number).sort();
  if (stages.length === 0) probs.push(`${name}: no dynamo stage in the plans`);
  for (const st of stages) {
    const need = st === 4 ? T2_BOSS_S : T2_PER_STAGE_S;
    if (perStage[st] < need) probs.push(`${name}: stage ${st}: dynamo above ${T2_ABOVE_PCT}% for ${perStage[st]} s (need ${need})`);
  }
  return probs;
}

/** The peer (string) of the human in slot `slot`, or null. */
export function peerOfSlot(report, slot) {
  const s = (report.slots ?? []).find((x) => num(x.slot, -1) === num(slot, -2));
  return s ? String(s.peer) : null;
}

/** Heavy shells of a crew 3 run: [{t, buildS, first, grade0S}] from latch / shot events and boiler directives. */
export function heavyShells(r) {
  const events = gameEvents(r);
  const spans = segmentsOf(r);
  const out = [];
  let lastShot = -Infinity;
  const boiler = (r.directives ?? [])
    .filter((d) => d.kind === 'request' && d.requested?.reason === 'boiler' && d.requested.mode_grade !== undefined)
    .map((d) => ({ t: num(d.t), peer: String(d.peer), grade: num(d.requested.mode_grade) }))
    .sort((a, b) => a.t - b.t);
  for (const e of events) {
    if (e.type === 'shot' && e.s >= 0 && e.sh !== SHELL_BOW) lastShot = e._t;
    if (e.type !== 'latch' || e.sh !== SHELL_HEAVY) continue;
    const seg = spans.find((s) => e._t >= s.start - EPS && (!Number.isFinite(s.end) || e._t < s.end + EPS));
    if (!seg || seg.seg === 'depot') continue;
    const ready = Math.max(lastShot + BREECH_CYCLE_S, seg.start);
    const first = lastShot + BREECH_CYCLE_S <= seg.start + EPS;
    // The latching rider's own boiler grade after the latch: the time at grade 0 until their next grade > 0. With rotation
    // every stage has another steam rider, so no other peer's requests count. The rest also ends when that rider leaves SIM
    // (a checkpoint's ERG carries no mode grade): then the 6 s breech cycle runs out with nothing to hold at 0 (`cut`).
    const peer = peerOfSlot(r, e.s);
    const leaves = peer === null ? undefined : segmentsOf(r, peer).find((s) => s.start > e._t + EPS && s.mode !== 'SIM');
    const leaveT = leaves ? leaves.start : Infinity;
    const mine = boiler.filter((b) => b.peer === peer && b.t >= e._t - EPS && b.t < leaveT - EPS);
    const zero = mine.find((b) => b.grade === 0);
    let grade0S = null;
    let cut = false;
    if (zero) {
      const next = mine.find((b) => b.t > zero.t && b.grade > 0);
      const nextT = next ? next.t : Infinity;
      cut = leaveT <= nextT;
      const stop = Math.min(nextT, leaveT);
      grade0S = (Number.isFinite(stop) ? stop : Number.isFinite(seg.end) ? seg.end : zero.t) - e._t;
    }
    out.push({ t: e._t, buildS: e._t - ready, first, grade0S, cut, seg: seg.seg });
  }
  return out;
}

/** T3 on one compliant crew 3 run. */
export function t3Problems(name, r) {
  const probs = [];
  const shells = heavyShells(r);
  if (shells.length === 0) probs.push(`${name}: no heavy shell was latched`);
  for (const s of shells) {
    const at = `${name}: heavy shell at ${fmt(s.t)} s`;
    if (s.buildS > T3_BUILD_RANGE[1] + EPS) probs.push(`${at} took ${fmt(s.buildS)} s to build (max ${T3_BUILD_RANGE[1]})`);
    if (!s.first && s.buildS < T3_BUILD_RANGE[0] - EPS) probs.push(`${at} took ${fmt(s.buildS)} s to build (min ${T3_BUILD_RANGE[0]})`);
    if (s.grade0S !== null && !s.cut && s.grade0S < T3_GRADE0_MIN_S - EPS) probs.push(`${at}: boiler grade 0 for only ${fmt(s.grade0S)} s`);
    if (s.grade0S === null) probs.push(`${at}: no boiler grade 0 after the latch`);
  }
  return probs;
}

/** The Bulwark's Drive share per Advance: [{stage, share}] from lever events (it starts on Drive). */
export function driveShares(r) {
  const levers = eventsOf(r, 'lever').sort((a, b) => a._t - b._t);
  const out = [];
  for (const s of segmentsOf(r)) {
    if (s.seg !== 'advance' || !Number.isFinite(s.end)) continue;
    let pos = LEVER_DRIVE;
    for (const e of levers) if (e._t <= s.start + EPS) pos = e.lv;
    let t = s.start;
    let drive = 0;
    for (const e of levers) {
      if (e._t <= s.start + EPS || e._t >= s.end) continue;
      if (pos === LEVER_DRIVE) drive += e._t - t;
      t = e._t;
      pos = e.lv;
    }
    if (pos === LEVER_DRIVE) drive += s.end - t;
    out.push({ stage: s.stage, share: s.dur > 0 ? drive / s.dur : 1 });
  }
  return out;
}

/** T4 on one compliant crew 1 run. */
export function t4Problems(name, r) {
  const shares = driveShares(r);
  const probs = shares.length === 0 ? [`${name}: no Advance found`] : [];
  for (const s of shares) {
    if (s.share < T4_MIN_SHARE - EPS) probs.push(`${name}: stage ${s.stage} Advance on Drive ${fmt(100 * s.share)}% (min ${100 * T4_MIN_SHARE}%)`);
  }
  return probs;
}

/** T6 on one compliant run: enemies by size in each Advance, a heavy duel in gun lines 2 and 3. */
export function t6Problems(name, r, opts = {}) {
  const probs = [];
  const events = gameEvents(r);
  const within = (e, s) => e._t >= s.start - EPS && e._t <= s.end + EPS;
  const seen = (s, code) => events.some((e) => (e.type === 'shot' || e.type === 'kill') && e.e === code && within(e, s));
  const toasts = (r.events ?? []).filter((e) => e && e.type === 'hud' && e.kind === 'toast' && /RAM/i.test(String(e.key ?? '')));
  for (const s of segmentsOf(r)) {
    if (!Number.isFinite(s.end)) continue;
    if (s.seg === 'advance') {
      if (!seen(s, ENEMY_LIGHT)) probs.push(`${name}: stage ${s.stage} Advance has no light tank`);
      if (!seen(s, ENEMY_MEDIUM)) probs.push(`${name}: stage ${s.stage} Advance has no medium tank`);
      if (opts.requirePrompts && !toasts.some((e) => num(e.t) >= s.start - EPS && num(e.t) <= s.end + EPS)) {
        probs.push(`${name}: stage ${s.stage} Advance raised no "Surge to ram" prompt`);
      }
    }
    if (s.seg === 'gun_line' && (s.stage === 2 || s.stage === 3)) {
      if (s.dur < T6_DUEL_RANGE[0] - EPS || s.dur > T6_DUEL_RANGE[1] + EPS) {
        probs.push(`${name}: stage ${s.stage} heavy duel lasted ${fmt(s.dur)} s (${T6_DUEL_RANGE[0]}-${T6_DUEL_RANGE[1]})`);
      }
      if (!seen(s, ENEMY_HEAVY)) probs.push(`${name}: stage ${s.stage} gun line has no heavy tank duel`);
    }
  }
  return probs;
}

// --- S1 ----------------------------------------------------------------------------------------------------

export function checkS1(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'ashfall_road, compliant crews 1-3: T1, T2, T3, T4, T6';
  const names = [];
  for (const c of CREWS) for (const s of seeds) names.push(`s1_c${c}_seed${s}`);
  const { found, missing } = pick(reports, names);
  if (found.length === 0) return skip('S1', title, 'no s1_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const lines = [];
  for (const [name, r] of found) {
    const [, crewS, seedS] = name.match(/^s1_c(\d)_seed(\d+)$/);
    const crew = Number(crewS);
    probs.push(...argsProblems(name, r, { content: 'ashfall_road', players: crew, bots: 0, seed: Number(seedS), role: crew >= 2 ? 'HOST' : 'SOLO' }));
    probs.push(...completeProblems(name, r));
    probs.push(...t1Problems(name, r));
    if (crew >= 2) probs.push(...t2Problems(name, r));
    if (crew === 3) probs.push(...t3Problems(name, r));
    if (crew === 1) probs.push(...t4Problems(name, r));
    // The sim report's HUD log holds only the host rider's own toasts: the "Surge to ram" prompt is the host rider's
    // only when that rider drives, which is the Bulwark of crew 1 (crews 2-3 rotate the driver away from slot 0).
    probs.push(...t6Problems(name, r, { ...opts, requirePrompts: opts.requirePrompts || crew === 1 }));
    lines.push(`c${crew}s${seedS} ${fmt(scoreOf(r))}/${gradeOf(r)}`);
  }
  return result('S1', title, probs, `${found.length} runs: ${lines.join(', ')}`);
}

// --- S2 ----------------------------------------------------------------------------------------------------

/** The first trace row of `peer` at 0 W (the not-pedaling sample), or null. */
export function firstNotPedaling(r, peer) {
  return traceOf(r, peer).find((row) => num(row.power_w) <= 0 && num(row.cadence_rpm) <= 0) ?? null;
}

/** GameHost's shared pause (BRIEF 3.5): every human rider ride-paused for not pedaling. */
export const SHARED_PAUSE_REASON = 'all_stopped';

export function checkS2(reports) {
  const title =
    'zero riders: crew 3 (the shared pause holds the depot), crew 3 spinning at 10 W (every stage overruns, grade D), crew 1 (paused in the depot)';
  const { found, missing } = pick(reports, ['s2_c3_zero', 's2_c3_idle', 's2_c1_zero']);
  if (found.length === 0) return skip('S2', title, 'no s2_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  // Crew 3 at 0 W: since v0.2 (BRIEF 3.5) every rider ride-pauses after 5 s of not pedaling and the
  // host pauses the shared game clock once all of them are, so the crew never leaves the depot. A
  // HOST run ends only at max_sim_seconds (`timeout`), still paused.
  const r3 = reports.s2_c3_zero;
  if (r3) {
    const n = 's2_c3_zero';
    probs.push(...argsProblems(n, r3, { content: 'ashfall_road', players: 3, bots: 0, role: 'HOST' }));
    if (r3.end_reason !== 'timeout') probs.push(`${n}: end_reason ${r3.end_reason}, wanted timeout (paused to the end)`);
    const spans = spansOf(r3, hostPeer(r3));
    if (spans.length !== 1 || num(spans[0]?.index) !== 0) probs.push(`${n}: ${spans.length} phases started, wanted only the depot`);
    const pauses = (r3.events ?? []).filter((e) => e && e.type === 'paused');
    const firsts = humanPeers(r3).map((peer) => firstNotPedaling(r3, peer));
    if (firsts.some((f) => !f)) probs.push(`${n}: a rider without a not-pedaling sample in the trace`);
    else if (!pauses.length || pauses[0].paused !== true || pauses[0].reason !== SHARED_PAUSE_REASON) {
      probs.push(`${n}: never paused for ${SHARED_PAUSE_REASON}`);
    } else {
      const last = Math.max(...firsts.map((f) => num(f.t)));
      if (num(pauses[0].pt) > last + PAUSE_AFTER_S + TICK_S + EPS) {
        probs.push(`${n}: paused at ${fmt(num(pauses[0].pt))} s, ${fmt(num(pauses[0].pt) - last)} s after the last rider's first not-pedaling sample (max ${PAUSE_AFTER_S} s + 1 tick)`);
      }
      if (pauses.some((e) => e.paused === false)) probs.push(`${n}: the shared pause ended, nobody pedaled`);
    }
    if (eventsOf(r3, 'kill').length) probs.push(`${n}: kills in a paused run`);
    if (gradeOf(r3) !== 'D') probs.push(`${n}: grade ${gradeOf(r3)}, wanted D`);
  }
  // Crew 3 spinning at 10 W: no detector sees a stopped rider (no pause, no AFK), and the game
  // must still fail them: every Advance, gun line and the boss ends at max_s, withdrawn, grade D.
  const ri = reports.s2_c3_idle;
  if (ri) {
    const n = 's2_c3_idle';
    probs.push(...argsProblems(n, ri, { content: 'ashfall_road', players: 3, bots: 0, role: 'HOST' }));
    probs.push(...completeProblems(n, ri, ['withdrawn']));
    if ((ri.events ?? []).some((e) => e && e.type === 'paused' && e.paused === true)) probs.push(`${n}: paused, but every rider pedals`);
    for (const s of segmentsOf(ri)) {
      if (['advance', 'gun_line', 'boss'].includes(s.seg) && !s.overran) {
        probs.push(`${n}: ${s.seg} ${s.stage} ended by ${s.endedBy || 'nothing'}, not at max_s (an overrun)`);
      }
    }
    if (gradeOf(ri) !== 'D') probs.push(`${n}: grade ${gradeOf(ri)}, wanted D`);
  }
  const r1 = reports.s2_c1_zero;
  if (r1) {
    const n = 's2_c1_zero';
    probs.push(...argsProblems(n, r1, { content: 'ashfall_road', players: 1, bots: 0, role: 'SOLO' }));
    if (r1.end_reason !== 'paused') probs.push(`${n}: end_reason ${r1.end_reason}, wanted paused`);
    const spans = spansOf(r1, hostPeer(r1));
    if (spans.length !== 1 || num(spans[0]?.index) !== 0) probs.push(`${n}: ${spans.length} phases started, wanted only the depot`);
    const first = firstNotPedaling(r1, hostPeer(r1));
    const paused = (r1.events ?? []).find((e) => e && e.type === 'paused' && e.paused === true);
    if (!first) probs.push(`${n}: no not-pedaling sample in the trace`);
    else if (!paused) probs.push(`${n}: never paused`);
    else if (num(paused.pt) > num(first.t) + PAUSE_AFTER_S + TICK_S + EPS) {
      probs.push(`${n}: paused at ${fmt(num(paused.pt))} s, ${fmt(num(paused.pt) - num(first.t))} s after the first not-pedaling sample (max ${PAUSE_AFTER_S} s + 1 tick)`);
    }
    if (eventsOf(r1, 'kill').length) probs.push(`${n}: kills in a paused run`);
    if (gradeOf(r1) !== 'D') probs.push(`${n}: grade ${gradeOf(r1)}, wanted D`);
  }
  const d3 = r3 ? `${r3.end_reason}, grade ${gradeOf(r3)}` : 'missing';
  const di = ri ? `grade ${gradeOf(ri)}` : 'missing';
  return result('S2', title, probs, `crew 3 at 0 W ${d3}, crew 3 at 10 W ${di}, crew 1 ${r1 ? r1.end_reason : 'missing'}`);
}

// --- S3 (T5) -----------------------------------------------------------------------------------------------

export function checkS3(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'crew 3 at 100%, 85%, 70% compliance: the mean score falls strictly (T5)';
  const groups = {
    100: seeds.map((n) => `s1_c3_seed${n}`),
    85: seeds.map((n) => `s3_c3_c85_seed${n}`),
    70: seeds.map((n) => `s3_c3_c70_seed${n}`),
  };
  const { found } = pick(reports, Object.values(groups).flat());
  if (found.length === 0) return skip('S3', title, 'no s3_* reports');
  const probs = [];
  const means = {};
  for (const [c, names] of Object.entries(groups)) {
    const { found: f, missing } = pick(reports, names);
    probs.push(...missing.map((m) => `missing report ${m}`));
    for (const [name, r] of f) {
      probs.push(...argsProblems(name, r, { content: 'ashfall_road', players: 3, role: 'HOST' }));
      probs.push(...completeProblems(name, r));
    }
    means[c] = mean(f.map(([, r]) => scoreOf(r)).filter(Number.isFinite));
  }
  if (!(means[100] > means[85])) probs.push(`mean score 100% (${fmt(means[100])}) is not above 85% (${fmt(means[85])})`);
  if (!(means[85] > means[70])) probs.push(`mean score 85% (${fmt(means[85])}) is not above 70% (${fmt(means[70])})`);
  return result('S3', title, probs, `100% ${fmt(means[100])}, 85% ${fmt(means[85])}, 70% ${fmt(means[70])}`);
}

// --- S4: directives, plans, haptics, switches, laps -------------------------------------------------------

/** The plan phase `peer` is in at game time t: {index, ph, span}. */
function phaseAt(r, peer, t) {
  const index = phaseIndexAt(r, peer, t);
  return { index, ph: planOf(r, peer)[index] ?? null, span: spansOf(r, peer)[index] ?? null };
}

const isWarmupKind = (ph) => ph?.kind === 'WARMUP';

/** The ERG target of the phase a rider enters, in whole watts: the plan's start value (or a directive of the first seconds). */
function enteredTargetW(r, peer, index) {
  const slot = slotOf(r, peer);
  const ph = planOf(r, peer)[index];
  const span = spansOf(r, peer)[index];
  const f = slot.ftp_verified === false ? 0.85 : 1;
  const ftp = num(slot.ftp, 200);
  let pct = num(ph?.target_pct);
  for (const d of r.directives ?? []) {
    if (d.kind === 'request' && String(d.peer) === String(peer) && d.requested?.mode === 'ERG' && d.requested.target_pct !== undefined) {
      if (num(d.t) >= num(span?.start) - EPS && num(d.t) <= num(span?.start) + 5) pct = Math.max(pct, num(d.requested.target_pct));
    }
  }
  const floor = Math.max(0.3 * ftp, 50);
  return Math.max((pct / 100) * ftp * f, floor);
}

/** What one `request` directive is, by brief 2.3 / 2.7: 'bank' | 'boiler' | 'hoist' | 'haptic' | '' (unknown). */
export function classify(d) {
  const q = d.requested ?? {};
  const reason = q.reason;
  if (q.haptic !== undefined) return ['hit', 'boss_hit', 'ram'].includes(reason) ? 'haptic' : '';
  if (reason === 'bank' && q.mode === 'ERG' && q.target_pct !== undefined) return 'bank';
  if (reason === 'boiler' && q.mode === 'SIM' && q.mode_grade !== undefined) return 'boiler';
  if (reason === 'hoist' && q.mode === 'SIM' && q.mode_grade !== undefined) return 'hoist';
  return '';
}

const HAPTICS = { hit: [2.0, 1.5], boss_hit: [3.0, 2.0], ram: [3.0, 1.0] };

/** Problems with one directive entry against brief 2.3 and 2.7 (at most a few per run are reported). */
export function directiveProblems(name, r, d) {
  const probs = [];
  const peer = String(d.peer);
  const at = `${name}: directive ${d.id} (${d.kind}, peer ${peer}, ${fmt(num(d.t))} s)`;
  const { ph } = phaseAt(r, peer, num(d.t));
  if (ph?.kind === 'COOLDOWN') return [`${at}: sent in the cool-down (nothing may be)`];
  if (!ph) return [`${at}: no plan phase`];
  const q = d.requested ?? {};
  switch (d.kind) {
    case 'cadence_band': {
      const lo = num(q.lo_rpm);
      const hi = num(q.hi_rpm);
      if (!((lo === 60 || lo === 50) && hi === 120)) probs.push(`${at}: band ${lo}-${hi} rpm (wanted 60-120, or 50-120 for the loader)`);
      break;
    }
    case 'course_grade':
      if (ph.mode !== 'SIM' || ph.grade_source !== 'game') probs.push(`${at}: terrain outside a grade_source game SIM phase`);
      break;
    case 'end_phase':
      if (!ph.open_ended) probs.push(`${at}: end_phase on a fixed phase`);
      break;
    case 'request': {
      const kind = classify(d);
      if (!kind) {
        probs.push(`${at}: matches no pattern of brief 2.3 or 2.7 ${JSON.stringify(q)}`);
        break;
      }
      if (num(q.duration_s) !== 0 && kind !== 'haptic') probs.push(`${at}: ${kind} with duration_s ${q.duration_s} (held until superseded)`);
      if (!isObj(d.applied) || !Array.isArray(d.applied.clamped_by)) probs.push(`${at}: no governor record with clamped_by (not clamped)`);
      probs.push(...appliedProblems(at, kind, q, d));
      const warm = isWarmupKind(ph);
      if (kind === 'bank') {
        const t = num(q.target_pct);
        if (ph.mode !== 'ERG' || ph.kind === 'RECOVERY') probs.push(`${at}: bank target outside a dynamo ERG phase`);
        const range = ph.range_pct;
        if (!Array.isArray(range)) probs.push(`${at}: bank target in a phase without range_pct (depot or checkpoint)`);
        else if (t < range[0] - EPS || t > range[1] + EPS) probs.push(`${at}: bank target ${t}% outside range_pct ${JSON.stringify(range)}`);
        if (t > 100 + EPS || t < 50 - EPS) probs.push(`${at}: bank target ${t}% outside 50-100% FTP`);
      } else if (kind === 'boiler') {
        const g = num(q.mode_grade);
        if (ph.mode !== 'SIM') probs.push(`${at}: boiler grade in an ERG phase`);
        if (g < 0 || g > (warm ? 3 : 8) + EPS) probs.push(`${at}: boiler grade ${g}% (max ${warm ? 3 : 8}%)`);
      } else if (kind === 'hoist') {
        const g = num(q.mode_grade);
        if (ph.mode !== 'SIM') probs.push(`${at}: hoist grade in an ERG phase (gun lines send none)`);
        if (g < 0 || g > (warm ? 1 : 4) + EPS) probs.push(`${at}: hoist grade ${g}% (max ${warm ? 1 : 4}%)`);
      } else if (kind === 'haptic') {
        const want = HAPTICS[q.reason];
        if (!want || num(q.haptic) !== want[0] || num(q.duration_s) !== want[1]) probs.push(`${at}: haptic ${q.haptic} for ${q.duration_s} s as ${q.reason} (wanted ${want?.join(' for ')} s)`);
        if (ph.mode !== 'SIM') probs.push(`${at}: haptic to an ERG rider`);
        if (warm || ph.kind === 'RECOVERY') probs.push(`${at}: haptic in a ${ph.kind} phase`);
        if (num(d.t) < FIRST_S - EPS) probs.push(`${at}: haptic in the first ${FIRST_S} s of the plan`);
        if (slotOf(r, peer).haptics_on === false && !(d.accepted === false || d.applied?.refused === true)) probs.push(`${at}: haptic applied to a rider who opted out`);
      }
      if (ph.mode === 'ERG' && kind !== 'bank') probs.push(`${at}: a ${kind} directive (SIM-mode) in an ERG phase`);
      break;
    }
    default:
      probs.push(`${at}: unexpected directive kind`);
  }
  return probs;
}

/**
 * The governor may only lower what Tank asked for: the applied boiler / hoist mode grade, bank ERG target and
 * haptic never exceed the requested value (a refused request applies nothing and is judged elsewhere).
 */
export function appliedProblems(at, kind, q, d) {
  const probs = [];
  const rec = d.applied;
  if (!isObj(rec) || rec.refused === true || d.accepted === false) return probs;
  const got = rec.applied;
  if (!isObj(got)) return [`${at}: governor record has no applied values`];
  const over = (what, applied, asked) => {
    if (applied !== undefined && !(num(applied, NaN) <= num(asked, NaN) + EPS)) probs.push(`${at}: applied ${what} ${fmt(num(applied, NaN))} above the requested ${fmt(num(asked, NaN))}`);
  };
  if (kind === 'bank') over('ERG target %', got.target_pct, q.target_pct);
  else if (kind === 'boiler' || kind === 'hoist') over('mode grade %', got.mode_grade, q.mode_grade);
  else if (kind === 'haptic') over('haptic %', got.haptic_pct, q.haptic);
  return probs;
}

/** The sum of directive problems of a run, capped at `max` messages. */
export function directivesProblems(name, r, max = 6) {
  const probs = [];
  let total = 0;
  for (const d of r.directives ?? []) {
    const p = directiveProblems(name, r, d);
    total += p.length;
    if (probs.length < max) probs.push(...p.slice(0, max - probs.length));
  }
  if (total > probs.length) probs.push(`${name}: ... ${total - probs.length} more directive problems`);
  return probs;
}

/** Plan ERG values stay in 50-100% FTP (nothing above 100). */
export function planProblems(name, r) {
  const probs = [];
  for (const peer of humanPeers(r)) {
    planOf(r, peer).forEach((ph, i) => {
      if (ph.mode !== 'ERG') return;
      const vals = [ph.target_pct, ph.ramp_to_pct, ...(ph.range_pct ?? [])].filter((v) => v !== undefined).map(Number);
      if (vals.some((v) => v > 100 + EPS)) probs.push(`${name}: peer ${peer} phase ${i} has an ERG value above 100% FTP ${JSON.stringify(vals)}`);
    });
  }
  return probs;
}

/** Trace rules: no applied ERG above 100% FTP, no SIM -> ERG entry above the target, no haptic early or to ERG, switches >= 60 s apart. */
export function traceProblems(name, r) {
  const probs = [];
  const add = (m) => {
    if (probs.length < 8) probs.push(m);
  };
  for (const peer of humanPeers(r)) {
    const rows = traceOf(r, peer);
    const slot = slotOf(r, peer);
    const ftp = num(slot.ftp, 200);
    const oneW = 100 / Math.max(ftp, 1) + EPS;
    let prev = null;
    const switches = [];
    for (const row of rows) {
      const gt = num(row.game_t, num(row.t));
      if (row.mode === 'ERG' && num(row.applied_pct) > 100 + oneW) add(`${name}: peer ${peer} applied ERG ${fmt(num(row.applied_pct))}% FTP at ${fmt(gt)} s (max 100%)`);
      if (gt < FIRST_S - EPS) {
        // BRIEF 4.6.8: the first 300 s are ERG at no more than 65% or SIM at -2..+3% grade.
        if (row.mode === 'ERG' && num(row.applied_pct) > FIRST_ERG_MAX_PCT + oneW) add(`${name}: peer ${peer} applied ERG ${fmt(num(row.applied_pct))}% FTP at ${fmt(gt)} s (max ${FIRST_ERG_MAX_PCT}% in the first ${FIRST_S} s)`);
        const g = num(row.applied_grade_pct);
        if (row.mode === 'SIM' && (g > FIRST_GRADE_MAX_PCT + EPS || g < FIRST_GRADE_MIN_PCT - EPS)) add(`${name}: peer ${peer} applied grade ${fmt(g)}% at ${fmt(gt)} s (${FIRST_GRADE_MIN_PCT} to +${FIRST_GRADE_MAX_PCT}% in the first ${FIRST_S} s)`);
      }
      if (row.mode === 'SIM') {
        // BRIEF 4.6: the stacked grade is at most the range clamp (+10%) plus the haptic, never above +16% in total.
        const g = num(row.applied_grade_pct);
        if (g > TOTAL_GRADE_MAX_PCT + EPS) add(`${name}: peer ${peer} applied grade ${fmt(g)}% at ${fmt(gt)} s (max +${TOTAL_GRADE_MAX_PCT}% in total)`);
        if (g - num(row.haptic) > RANGE_GRADE_MAX_PCT + EPS) add(`${name}: peer ${peer} applied grade ${fmt(g)}% less haptic ${fmt(num(row.haptic))}% at ${fmt(gt)} s (max +${RANGE_GRADE_MAX_PCT}% before the haptic)`);
      }
      if (num(row.haptic) !== 0) {
        if (gt < FIRST_S - EPS) add(`${name}: peer ${peer} haptic ${row.haptic} applied at ${fmt(gt)} s (none in the first ${FIRST_S} s)`);
        if (row.mode !== 'SIM') add(`${name}: peer ${peer} haptic applied in ${row.mode} at ${fmt(gt)} s`);
        if (row.kind === 'COOLDOWN') add(`${name}: peer ${peer} haptic applied in the cool-down at ${fmt(gt)} s`);
      }
      if (prev && prev.mode !== row.mode && (prev.mode === 'ERG' || prev.mode === 'SIM') && (row.mode === 'ERG' || row.mode === 'SIM')) {
        switches.push({ t: gt, from: prev.mode, to: row.mode, phase: num(row.phase) });
      }
      prev = row;
    }
    for (let i = 1; i < switches.length; i += 1) {
      if (switches[i].t - switches[i - 1].t < SWITCH_SPACING_S - 1 - EPS) {
        add(`${name}: peer ${peer} switched ${switches[i - 1].from}->${switches[i - 1].to} at ${fmt(switches[i - 1].t)} s and again at ${fmt(switches[i].t)} s (< ${SWITCH_SPACING_S} s)`);
      }
    }
    for (const sw of switches) {
      if (sw.from !== 'SIM' || sw.to !== 'ERG') continue;
      const span = spansOf(r, peer).find((s) => num(s.index) === sw.phase);
      const bound = enteredTargetW(r, peer, sw.phase) + 1;
      const first = rows.filter((row) => num(row.phase) === sw.phase && row.mode === 'ERG' && num(row.game_t, num(row.t)) <= num(span?.start, sw.t) + 5);
      for (const row of first) {
        if (num(row.applied_target_w) > bound + EPS) {
          add(`${name}: peer ${peer} entered ERG at ${fmt(sw.t)} s with ${row.applied_target_w} W, above the target ${Math.round(bound - 1)} W (or the floor)`);
          break;
        }
      }
    }
  }
  return probs;
}

/** FIT lap count of the plan: lap-true phases, equal to the content's expected laps. */
export function lapProblems(name, r) {
  const probs = [];
  const want = EXPECTED_LAPS[r.content_id];
  for (const peer of humanPeers(r)) {
    const n = planLaps(r, peer);
    if (want !== undefined && n !== want) probs.push(`${name}: peer ${peer} plan has ${n} lap-true phases, wanted ${want}`);
    if (planOf(r, peer).some((p) => p.kind !== 'COOLDOWN' && p.lap !== true)) probs.push(`${name}: peer ${peer} has a plan phase with lap false`);
  }
  return probs;
}

export function checkS4(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'every content and crew: directives, plans, haptics, switches, laps';
  const names = [];
  for (const c of CREWS) for (const s of seeds) names.push(`s1_c${c}_seed${s}`);
  for (const c of CREWS) names.push(`s4_drill_c${c}`);
  const { found, missing } = pick(reports, names);
  if (found.length === 0) return skip('S4', title, 'no s1_* or s4_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  for (const [name, r] of found) {
    const crew = Number(name.match(/_c(\d)/)[1]);
    probs.push(...argsProblems(name, r, { content: name.startsWith('s4_drill') ? 'drill' : 'ashfall_road', players: crew, bots: 0 }));
    probs.push(...completeProblems(name, r));
    probs.push(...cleanProblems(name, r));
    probs.push(...planProblems(name, r));
    probs.push(...directivesProblems(name, r));
    probs.push(...traceProblems(name, r));
    probs.push(...lapProblems(name, r));
    if (r.content_id === 'drill') {
      for (const peer of humanPeers(r)) {
        const modes = traceOf(r, peer).map((row) => row.mode).filter((m) => m === 'ERG' || m === 'SIM');
        const changes = modes.filter((m, i) => i > 0 && m !== modes[i - 1]).length;
        if (changes > 1) probs.push(`${name}: peer ${peer} switches ${changes} times (the drill allows at most one)`);
      }
    }
  }
  return result('S4', title, probs, `${found.length} runs`);
}

// --- S5: rescue, stagger, the plan continues ---------------------------------------------------------------

/** Seconds of rescue in the trace of `peer` and the applied % FTP while in rescue. */
export function rescueStats(r, peer) {
  const rows = traceOf(r, peer).filter((row) => row.rescue === true);
  return { rows: rows.length, maxPct: Math.max(0, ...rows.map((row) => num(row.applied_pct))), first: rows[0] ?? null, last: rows[rows.length - 1] ?? null };
}

export function checkS5(reports) {
  const title = 'cadence collapse to 30 rpm in a dynamo stage and in a 90% gun line: rescue, stagger, the plan continues';
  const cases = [
    { name: 's5_c3_dynamo_drop', peer: '2', engine: 'dynamo', seg: 'gun_line', phase: 2 },
    { name: 's5_c3_gunline_drop', peer: '1', engine: 'diesel', seg: 'gun_line', phase: 2 },
  ];
  const { found, missing } = pick(reports, cases.map((c) => c.name));
  if (found.length === 0) return skip('S5', title, 'no s5_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const notes = [];
  for (const c of cases) {
    const r = reports[c.name];
    if (!r) continue;
    const n = c.name;
    probs.push(...argsProblems(n, r, { content: 'ashfall_road', players: 3, bots: 0, role: 'HOST' }));
    probs.push(...completeProblems(n, r));
    probs.push(...cleanProblems(n, r));
    const plan = planOf(r, c.peer)[c.phase];
    if (plan?.meta?.engine !== c.engine || plan?.meta?.seg !== c.seg) probs.push(`${n}: peer ${c.peer} phase ${c.phase} is ${plan?.meta?.engine}/${plan?.meta?.seg}, wanted ${c.engine}/${c.seg} (the profile's at_phase)`);
    const st = rescueStats(r, c.peer);
    if (st.rows === 0) probs.push(`${n}: peer ${c.peer} never entered rescue`);
    else {
      if (!(st.maxPct <= 50 + 100 / Math.max(num(slotOf(r, c.peer).ftp, 200), 1) + EPS)) probs.push(`${n}: rescue applied ${fmt(st.maxPct)}% FTP (wanted 50%)`);
      const span = segmentsOf(r, c.peer).find((s) => s.index === c.phase);
      if (span && st.first && num(st.first.game_t) < span.start - EPS) probs.push(`${n}: rescue began before phase ${c.phase}`);
      const spanEnd = span && Number.isFinite(span.end) ? span.end : Infinity;
      if (span && st.first && num(st.first.game_t) > spanEnd + EPS) probs.push(`${n}: rescue began after the phase`);
      const afterRows = traceOf(r, c.peer).filter((row) => num(row.game_t) > num(st.last.game_t));
      if (!afterRows.some((row) => row.rescue !== true)) probs.push(`${n}: rescue never ended`);
      const clampedRescue = traceOf(r, c.peer).some((row) => row.rescue === true && (row.clamped_by ?? []).includes('rescue'));
      if (!clampedRescue) probs.push(`${n}: no trace row clamped by rescue`);
      notes.push(`${c.name} ${st.rows} s in rescue`);
    }
    const spans = segmentsOf(r, c.peer);
    if (spans.length !== planOf(r, c.peer).length) probs.push(`${n}: ${spans.length} of ${planOf(r, c.peer).length} plan phases ran (the plan must continue)`);
    for (const peer of humanPeers(r)) {
      if (peer === c.peer) continue;
      if (traceOf(r, peer).some((row) => row.rescue === true)) probs.push(`${n}: peer ${peer} (not the collapsing rider) entered rescue`);
    }
  }
  return result('S5', title, probs, notes.join(', '));
}

// --- S6: haptics off ----------------------------------------------------------------------------------------

export function checkS6(reports) {
  const title = 'crew 3 with haptics off for slot 0: no haptic applied to that rider';
  const r = reports.s6_c3_haptics_off;
  if (!r) return skip('S6', title, 'no s6_c3_haptics_off report');
  const n = 's6_c3_haptics_off';
  const probs = [...argsProblems(n, r, { content: 'ashfall_road', players: 3, bots: 0, role: 'HOST' }), ...completeProblems(n, r)];
  const off = (r.slots ?? []).filter((s) => s.haptics_on === false).map((s) => String(s.peer));
  if (off.length !== 1) probs.push(`${n}: ${off.length} slots with haptics off, wanted 1`);
  for (const peer of off) {
    const rows = traceOf(r, peer).filter((row) => num(row.haptic) !== 0);
    if (rows.length) probs.push(`${n}: peer ${peer} had a haptic applied at ${fmt(num(rows[0].game_t))} s (${rows.length} rows)`);
    for (const d of r.directives ?? []) {
      if (String(d.peer) !== peer || d.kind !== 'request' || d.requested?.haptic === undefined) continue;
      const refused = d.accepted === false || d.applied?.refused === true;
      const applied = num(d.applied?.applied?.haptic) !== 0;
      if (!refused && applied) probs.push(`${n}: haptic directive ${d.id} applied to peer ${peer}`);
    }
  }
  const others = humanPeers(r).filter((p) => !off.includes(p));
  const felt = sum(others.map((p) => traceOf(r, p).filter((row) => num(row.haptic) !== 0).length));
  return result('S6', title, probs, `${felt} haptic seconds felt by the other riders`);
}

// --- S7: determinism ---------------------------------------------------------------------------------------------

export function checkS7(reports) {
  const title = 'crew 3, same seed twice: identical events and snapshot hashes';
  const a = reports.s1_c3_seed1;
  const b = reports.s7_c3_seed1;
  if (!b) return skip('S7', title, 'no s7_c3_seed1 report');
  if (!a) return result('S7', title, ['missing report s1_c3_seed1']);
  const probs = [];
  if (a.deterministic_hash !== b.deterministic_hash) probs.push(`deterministic_hash differs: ${a.deterministic_hash} vs ${b.deterministic_hash}`);
  const ea = JSON.stringify(gameEvents(a));
  const eb = JSON.stringify(gameEvents(b));
  if (ea !== eb) probs.push(`game events differ (${gameEvents(a).length} vs ${gameEvents(b).length})`);
  const sa = (a.snapshots ?? []).map((s) => s.sha256);
  const sb = (b.snapshots ?? []).map((s) => s.sha256);
  if (sa.length !== sb.length) probs.push(`${sa.length} vs ${sb.length} snapshots`);
  else {
    const at = sa.findIndex((h, i) => h !== sb[i]);
    if (at >= 0) probs.push(`snapshot ${at} (tick ${a.snapshots[at].tick}) differs`);
  }
  const strip = (x) => JSON.stringify({ ...x.args, report: undefined });
  if (strip(a) !== strip(b)) probs.push('the two runs were not started with the same arguments');
  return result('S7', title, probs, `${gameEvents(a).length} events, ${sa.length} snapshots`);
}

// --- S9: the sprint half of the workout ---------------------------------------------------------------------------

/** A trailing mean power at or above this share of FTP is a sprint (tanks.json ram.sprint_ftp 1.2). The S9 rider (run_sims.sh) rides 12 s at 1.5 x FTP every 40 s. */
export const S9_SPRINT_SIM_FTP_PCT = 120;

/** The Ram events that destroyed something (`ok` 1). */
export const successfulRams = (r) => eventsOf(r, 'ram').filter((e) => num(e.ok) === 1);

/** SIM -> ERG switches of `peer` with the trailing mean raw power (last `n` rows before the switch). */
export function switchesIntoErg(r, peer, n = 3) {
  const rows = traceOf(r, peer);
  const out = [];
  for (let i = 1; i < rows.length; i += 1) {
    if (rows[i - 1].mode !== 'SIM' || rows[i].mode !== 'ERG') continue;
    const before = rows.slice(Math.max(0, i - n), i).map((row) => num(row.power_w));
    out.push({ t: num(rows[i].game_t, num(rows[i].t)), phase: num(rows[i].phase), trailingW: mean(before), ftp: num(slotOf(r, peer).ftp, 200) });
  }
  return out;
}

export function checkS9(reports) {
  const title = 'a sprinting solo rider: a Ram in every Advance, a ram haptic only in SIM, gun lines entered after a sprint at or below their target';
  const n = 's9_c1_sprint';
  const r = reports[n];
  if (!r) return skip('S9', title, `no ${n} report`);
  const probs = [...argsProblems(n, r, { content: 'ashfall_road', players: 1, bots: 0, role: 'SOLO' }), ...completeProblems(n, r)];
  probs.push(...cleanProblems(n, r), ...planProblems(n, r), ...directivesProblems(n, r), ...traceProblems(n, r), ...lapProblems(n, r));
  const rams = successfulRams(r);
  for (const s of segmentsOf(r)) {
    if (s.seg !== 'advance' || !Number.isFinite(s.end)) continue;
    if (!rams.some((e) => e._t >= s.start - EPS && e._t <= s.end + EPS)) probs.push(`${n}: stage ${s.stage} Advance has no successful Ram (the sprint rider should destroy a light tank)`);
  }
  const hap = (r.directives ?? []).filter((d) => d.kind === 'request' && d.requested?.reason === 'ram');
  if (hap.length === 0) probs.push(`${n}: a Ram never sent its haptic`);
  for (const d of hap) {
    if (d.accepted === false || d.applied?.refused === true) probs.push(`${n}: ram haptic ${d.id} at ${fmt(num(d.t))} s refused: ${d.reason || d.applied?.reason}`);
  }
  // A gun line (ERG) entered while the rider is still sprinting: the trainer must start at the planned target, not at the sprint power.
  const host = hostPeer(r);
  const ftp = num(slotOf(r, host).ftp, 200);
  const entries = switchesIntoErg(r, host).filter((sw) => sw.trailingW >= (S9_SPRINT_SIM_FTP_PCT / 100) * ftp - EPS && planOf(r, host)[sw.phase]?.kind === 'WORK');
  if (entries.length === 0) probs.push(`${n}: no gun line was entered straight after a sprint (the profile should sprint at one of the Advance ends)`);
  for (const sw of entries) {
    const bound = enteredTargetW(r, host, sw.phase) + 1;
    const first = traceOf(r, host).filter((row) => num(row.phase) === sw.phase && row.mode === 'ERG' && num(row.game_t, num(row.t)) <= sw.t + 5);
    const worst = Math.max(0, ...first.map((row) => num(row.applied_target_w)));
    if (worst > bound + EPS) probs.push(`${n}: gun line at ${fmt(sw.t)} s entered after a ${fmt(sw.trailingW)} W sprint with a ${worst} W target (planned ${Math.round(bound - 1)} W)`);
  }
  return result('S9', title, probs, `${rams.length} Rams, ${hap.length} ram haptics, ${entries.length} gun line entries after a sprint`);
}

// --- S10: clients sending intents, a client that stops ---------------------------------------------------------------

/** AFK comes 10 s after the first not-pedaling sample (BRIEF 4.6.4); the trace is sampled once a second. */
export const AFK_AFTER_S = 10;
/** The engine of `peer`'s plan phase at report time t, or ''. */
const engineAt = (r, peer, t) => planOf(r, peer)[phaseIndexAt(r, peer, t)]?.meta?.engine ?? '';

/** Ram and dodge events whose slot was not on a driving engine at that time (a client's intent must be owned by its engine). */
export function intentOwnershipProblems(name, r) {
  const probs = [];
  for (const e of gameEvents(r)) {
    if (e.type !== 'ram' && e.type !== 'dodge') continue;
    const peer = peerOfSlot(r, e.s);
    const engine = peer === null ? '' : engineAt(r, peer, e._t);
    if (engine !== 'diesel' && engine !== 'bulwark') probs.push(`${name}: ${e.type} by slot ${e.s} at ${fmt(e._t)} s, who was on "${engine}", not a driving engine`);
  }
  return probs;
}

export function checkS10(reports) {
  const title = 'crew 3 where the clients send the intents and one stops: client Rams, a station on reserve through a rescue';
  const cases = ['s10_c3_clients_sprint', 's10_c3_dynamo_stop'];
  const { found, missing } = pick(reports, cases);
  if (found.length === 0) return skip('S10', title, 'no s10_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const notes = [];
  const hygiene = (n, r) => {
    probs.push(...argsProblems(n, r, { content: 'ashfall_road', players: 3, bots: 0, role: 'HOST' }), ...completeProblems(n, r));
    probs.push(...cleanProblems(n, r), ...planProblems(n, r), ...directivesProblems(n, r), ...traceProblems(n, r), ...lapProblems(n, r));
  };

  // Every rider sprints: the Ram of slot 1 or 2 reaches the host as a client's Telemetry.intents and only counts on the diesel.
  const sprint = reports.s10_c3_clients_sprint;
  if (sprint) {
    const n = 's10_c3_clients_sprint';
    hygiene(n, sprint);
    probs.push(...intentOwnershipProblems(n, sprint));
    const clientRams = successfulRams(sprint).filter((e) => num(e.s) >= 1);
    if (clientRams.length === 0) probs.push(`${n}: no client rider (slot 1 or 2) destroyed anything with a Ram: their intents never reached the host`);
    notes.push(`${n} ${clientRams.length} client Rams`);
  }

  // Slot 1 stops pedaling in the stage 1 gun line (the dynamo, ERG 60% or more): rescue, then AFK and a station on reserve, then back.
  const stop = reports.s10_c3_dynamo_stop;
  if (stop) {
    const n = 's10_c3_dynamo_stop';
    hygiene(n, stop);
    const peer = '2';
    const rows = traceOf(stop, peer);
    const span = segmentsOf(stop, peer).find((x) => x.index === 2);
    const zero = rows.find((row) => num(row.game_t) >= num(span?.start, 0) - EPS && num(row.power_w) <= 0 && num(row.cadence_rpm) <= 0);
    const afk = rows.filter((row) => row.afk === true);
    if (!zero) probs.push(`${n}: peer ${peer} never stopped pedaling in the gun line`);
    else if (afk.length === 0) probs.push(`${n}: peer ${peer} never went AFK`);
    else {
      const lag = num(afk[0].game_t) - num(zero.game_t);
      if (lag > AFK_AFTER_S + 1 + EPS) probs.push(`${n}: peer ${peer} went AFK ${fmt(lag)} s after it stopped (max ${AFK_AFTER_S} s, one sample of slack)`);
      if (!rows.some((row) => num(row.game_t) > num(afk[afk.length - 1].game_t) && row.afk !== true && num(row.power_w) > 0)) probs.push(`${n}: peer ${peer} never came back from AFK`);
      if (!(stop.events ?? []).some((e) => e && e.type === 'hud' && /RESERVE/.test(String(e.key ?? '')))) probs.push(`${n}: no "on reserve" toast`);
    }
    const st = rescueStats(stop, peer);
    if (st.rows === 0) probs.push(`${n}: peer ${peer} never entered rescue`);
    else if (!(st.maxPct <= 50 + 100 / Math.max(num(slotOf(stop, peer).ftp, 200), 1) + EPS)) probs.push(`${n}: rescue applied ${fmt(st.maxPct)}% FTP (wanted 50% or less)`);
    for (const other of humanPeers(stop)) {
      if (other === peer) continue;
      if (traceOf(stop, other).some((row) => row.rescue === true || row.afk === true)) probs.push(`${n}: peer ${other} (not the rider who stopped) was in rescue or AFK`);
    }
    if (segmentsOf(stop, peer).length !== planOf(stop, peer).length) probs.push(`${n}: the plan did not continue to its last phase`);
    notes.push(`${n} ${afk.length} s AFK, ${st.rows} s in rescue`);
  }
  return result('S10', title, probs, notes.join(', '));
}

// --- FIT ------------------------------------------------------------------------------------------------------------

/** [[laps|null, [files]]] groups of the FIT files the reports name, existing on disk. */
export function fitGroups(reports, dir) {
  const groups = new Map();
  for (const [name, r] of Object.entries(reports)) {
    const complete = r.end_reason === 'complete';
    const laps = complete ? EXPECTED_LAPS[r.content_id] ?? planLaps(r) : null;
    humanPeers(r).forEach((_, i) => {
      const listed = (r.fit_paths ?? [])[i];
      const local = path.join(dir, 'fit', `${name}_slot${i}.fit`);
      const file = listed && fs.existsSync(listed) ? listed : fs.existsSync(local) ? local : null;
      if (!file) return;
      const key = laps === null ? 'none' : String(laps);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(file);
    });
  }
  return groups;
}

export function checkFit(reports, dir, repo) {
  const title = 'fit_check on every FIT file';
  const groups = fitGroups(reports, dir);
  const total = [...groups.values()].reduce((n, g) => n + g.length, 0);
  if (total === 0) return skip('FIT', title, 'no FIT files found');
  const probs = [];
  for (const [laps, files] of groups) {
    const args = [path.join(repo, 'tools', 'fit_check', 'check.mjs'), ...files];
    if (laps !== 'none') args.push(`--expect-laps=${laps}`);
    const r = spawnSync(process.execPath, args, { cwd: repo, encoding: 'utf8', timeout: 900000 });
    if (r.status !== 0) probs.push(`fit_check ${laps === 'none' ? '' : `(${laps} laps) `}exit ${r.status} on ${files.length} files: ${(r.stdout + r.stderr).trim().split('\n').slice(-6).join(' | ')}`);
  }
  return result('FIT', title, probs, `${total} files`);
}

// --- main ------------------------------------------------------------------------------------------------------------

export const CHECKS = { S1: checkS1, S2: checkS2, S3: checkS3, S4: checkS4, S5: checkS5, S6: checkS6, S7: checkS7, S9: checkS9, S10: checkS10 };

export function parseArgs(argv) {
  const o = { dir: null, only: null, seeds: DEFAULT_SEEDS, fit: false, requirePrompts: false };
  for (const a of argv) {
    if (a.startsWith('--only=')) o.only = a.slice(7).split(',').map((s) => s.trim().toUpperCase()).filter(Boolean);
    else if (a.startsWith('--seeds=')) o.seeds = a.slice(8).split(',').map(Number).filter(Number.isFinite);
    else if (a === '--fit') o.fit = true;
    else if (a === '--require-prompts') o.requirePrompts = true;
    else if (a.startsWith('--')) throw new Error(`unknown option ${a}`);
    else if (o.dir === null) o.dir = a;
    else throw new Error(`unexpected argument ${a}`);
  }
  if (!o.dir) throw new Error('usage: check_sims.mjs <reports dir> [--only=S1,S4] [--seeds=1,2,3] [--fit] [--require-prompts]');
  for (const id of o.only ?? []) if (!CHECKS[id] && id !== 'FIT') throw new Error(`unknown scenario ${id}`);
  return o;
}

export function runChecks(reports, o, dir, repo) {
  const out = [];
  for (const [id, fn] of Object.entries(CHECKS)) {
    if (o.only && !o.only.includes(id)) continue;
    out.push(fn(reports, { seeds: o.seeds, requirePrompts: o.requirePrompts }));
  }
  if (o.fit || (o.only && o.only.includes('FIT'))) out.push(checkFit(reports, dir, repo));
  return out;
}

export function main(argv) {
  let o;
  try {
    o = parseArgs(argv);
  } catch (err) {
    process.stderr.write(`${err.message}\n`);
    return 2;
  }
  let reports;
  try {
    reports = loadReports(o.dir);
  } catch (err) {
    process.stderr.write(`${err.message}\n`);
    return 2;
  }
  const here = path.dirname(fileURLToPath(import.meta.url));
  const repo = path.resolve(here, '..', '..', '..', '..');
  const results = runChecks(reports, o, o.dir, repo);
  let failed = 0;
  for (const r of results) {
    process.stdout.write(`${r.status} ${r.id} ${r.summary}\n`);
    for (const d of r.details) process.stdout.write(`    ${d}\n`);
    if (r.status === 'FAIL') failed += 1;
  }
  process.stdout.write(`check_sims: ${results.length} checks, ${failed} failed\n`);
  return failed ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  process.exitCode = main(process.argv.slice(2));
}
