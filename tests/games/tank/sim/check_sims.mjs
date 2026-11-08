#!/usr/bin/env node
// tests/games/tank/sim/check_sims.mjs: asserts brief section 4's simulation matrix (S1-S7 for crews 1-4, plus S9 the
// sprint half of the workout and S10 the network paths; S8 is the GUT test test_tank_s8.gd) and the tuning targets T1-T7
// over the reports tools/run_game_sim wrote.
//
//   node tests/games/tank/sim/check_sims.mjs build/tank/sims [--only=S1,S4] [--seeds=1,2,3] [--fit]
//                                           [--require-prompts]
//
// One PASS / FAIL / SKIP line per scenario (details of a failure indented below it), exit 1 when any
// scenario failed, 2 on usage or I/O errors. A scenario whose reports are all missing is SKIP (a
// subset run); one that has some but not all is FAIL. `--fit` also runs tools/fit_check on every FIT
// file the reports name (laps expected: ashfall_road 13, ambush_15 7, drill 4; none for a run that did not
// complete). Zero dependencies, so `node --test` in tests/games/tank/sim runs the unit tests
// (check_sims.test.mjs) anywhere.
//
// Report names (written by run_sims.sh; the scenario is read from the name, the content, players and
// seed are cross-checked against the report's own `args`):
//   s1_c<crew>_seed<n>     ashfall_road, compliant `erg` riders, crews 1-4 (crews 2-4 as HOST)
//   s2_c3_zero, s2_c1_zero crew 3 at 0 W (HOST: the shared pause holds the hangar), crew 1 at 0 W (SOLO: paused)
//   s2_c3_idle             crew 3 spinning at 10 W and 25 rpm (pedaling for every detector, no effort): overruns
//   s3_c3_c85_seed<n>, s3_c3_c70_seed<n>   crew 3 at compliance 0.85 / 0.70 (100% is s1_c3_seed<n>)
//   s4_drill_c<crew>       the drill, compliant, crews 1-4 (S4 also reads every s1 report)
//   s5_c3_dynamo_drop, s5_c4_arc_drop  cadence to 30 rpm in a Gun (dynamo) phase / a Lights (arc) phase
//   s6_c3_haptics_off      crew 3, slot 0 opted out of haptics
//   s7_c3_seed1            s1_c3_seed1 again
//   s9_c1_sprint           crew 1 with a scripted sprinter (intervals), the sprint half of the workout: evades,
//                          the gun line entered straight after a sprint (S8 is the GUT test test_tank_s8.gd)
//   s10_c3_clients_sprint  crew 3, every rider a scripted sprinter: the clients' Overpressure (`over` from a surge on the
//                          steam engine) arrives as telemetry intents; a client's `aim` is GUT-tested (no actions in sims)
//   s10_c3_dynamo_stop     crew 3, slot 1 stops pedaling for 60 s in the stage 1 gun line (rescue, AFK, reserve, back)
//   s13_c3_seats           crew 3 on the fallback (--autopilot=none): automatic seating through replans, clients included
//   s11_roam10_c1, s11_roam10_c4, s11_roam30_c3   free roam, compliant `erg` riders (brief 2.10): time up, the overtime
//                          bound, no patrol after time up, FIT laps, the grade (roam_30 crew 3: B or A, the tuning target)
//   s12_roam10_c3_zero     free roam roam_10, crew 3 at 0 W: the shared pause holds the drive-out, no kill, grade D
//   s14_easy_c<crew>_seed<n>   ashfall_road on Easy, crews 1-4: victory, no loss, T1
//   s15_hard_c<crew>_seed<n>   ashfall_road on Hard, crews 1-4: 1-2 losses on most seeds, phases, laps and S4 hold
//   s16_amb_<normal|hard>_c<crew>_seed<n>   ambush_15, crews 1, 3, 4: 780-1010 game seconds, 7 laps, S4
//   s17_hard_c3_c85_seed<n>    Hard, compliance 0.85: more losses than s15_hard_c3 (nobody rescues, the crew falls behind)
//   s17_hard_c3_c70_seed1      Hard, compliance 0.70: the riders sink into rescue, and rescue shields the crew (BRIEF 4.6.3)
//   s18_bots_h1b3, s18_bots_h2b2   ambush_15 on Hard with bots: complete, nothing refused, bots act only through their seats
//
// Definitions (the numbers are brief 2.3, 2.4 and 4):
//   segment       a mission segment with its span in `phases[peer]` (game seconds) and how it ended
//                 (`ended_by`: duration, end_phase or max_s: an overrun is max_s on a WORK phase); v3: a seat
//                 switch splits a segment into plan phases (the rest of it a lap-false phase), so a segment is
//                 every phase with its meta `segment` (phaseSpansOf keeps them one by one).
//   T1 (crews 1-4) every Advance 120-280 s, gun line 60-160 s (crew 2 on ashfall_road: 60-180 s, see
//                 T1_CREW2_GUN_LINE_MAX_S), boss 120-330 s (ambush_15: 80-160, 60-120, 100-190), no overrun, at most 1 tank loss, no breakdown (Normal has none; Easy, whose hull breaks down
//                 instead, at most 1), grade S/A/B. v4: a segment holding a tank_lost is not held to the range or
//                 to "no overrun": it started over and max_s is what ends it.
//   T2 (crews 2-4) the dynamo's applied ERG target (trace rows, % FTP) is above 80% for >= 30 s per
//                 stage (Advance + gun line) and >= 60 s in the boss, and is back at <= 65% within
//                 120 s after each dynamo gun line or boss ends.
//   T3 (crews 3-4, v3 the Loader's rack) the crew stows >= 3 shells per stage (Advance + gun line;
//                 latch events), and one rider's back-to-back stows (<= 15 s apart, the rack never
//                 full between them) take 4-12 s each at the median (about 7 s at 250 W P_eff).
//   T4 (crew 1, v3 the solo loop) the solo rider drives enough to make each Advance's time bound:
//                 >= 50% of each Advance on Drive (its plan phases' seat; one 60 s stay elsewhere
//                 at most), and works each holding action's guns: >= 2 main-gun shells fired (v4: the bow
//                 guns reach only near threats, so a bow kill no longer stands in for it).
//   T5            mean score falls strictly from 100% (s1_c3) to 85% to 70%.
//   T6            every Advance has a telegraphed shot (an `evade` event, v4 raised when the shell lands: a sprint
//                 prompt, from the light's flank shot or the destroyer) and a medium tank (enemy
//                 `shot` or `kill` events); crew 1, whose host rider rides SIM in every Advance, also shows the
//                 "Surge to evade" toast there (every crew with --require-prompts); stages 2 and 3 end in a heavy-tank
//                 duel: the gun line lasts 60-180 s (v3) and a heavy tank fired or died in it.
//   T7 (crew 4)   the arc rider's applied ERG target is above 72% for >= 30 s per stage (stages 1-3: Advance + gun
//                 line), and is back at <= 68% within 60 s of a fight's end (the end of an arc gun line or boss, or
//                 a kill in an Advance followed by 60 s with no enemy shot).
//   T8 (crews 2-4) near threats: an `ambush` in every Advance; each one is killed or `escaped` in its own segment,
//                 unless the segment's end or a tank loss cleared it while it could still be alive (NEAR_LIFE_S);
//                 crews 3-4 kill at least 40% of them over a run.
//   T9            no enemy `shot` in a checkpoint; `tank_lost` only in WORK; each one followed by `stage_restart`
//                 within the tow + 1 s unless the segment ended first.
//   S9 (crew 1)   the sprinting rider (scripted intervals, not a compliant one): successful evades, no Ram or
//                 dodge event and no ram haptic (v2), and every SIM -> ERG entry (v3: a move to the Gun or the
//                 Lights, a checkpoint) starts at its planned target, not at the sprint power.
//   S10 (crew 3)  every rider a sprinter: a client's Overpressure (`over` over Telemetry.intents, owned by the steam
//                 engine) latches an Overpressure shell; and a dynamo rider who stops in a gun line is rescued, goes AFK
//                 within 10 s, is announced as on reserve, comes back, with nobody else affected and the plan completing.
//   S14-S18       difficulty, the short session and bots (the list of report names above); S4's rules read them too.
//   S13 (crew 3)  seat switching (0.3.1, no seat lock): humans on the fallback (--autopilot=none) seated by the host's
//                 Autopilot, the clients' moves included: seat events (a move lands at once), every split and replan
//                 accepted with no plan warning, each rider's trainer on its new seat's plan within SWITCH_SPACING_S
//                 of the move (or at the segment's end when the switch waits for it), every ERG <-> SIM switch
//                 SWITCH_SPACING_S from the next, the plans' FIT laps unchanged (a split is a lap-false phase).

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { pick, result } from '../../../../tools/lib/sim_report.mjs';

export const CREWS = [1, 2, 3, 4];
export const DEFAULT_SEEDS = [1, 2, 3];
/** FIT laps: lap-true plan phases + the cool-down (the platform marks it lap true; ADR G0.2). */
export const EXPECTED_LAPS = { ashfall_road: 13, ambush_15: 7, drill: 4 };
/** T1's segment ranges by content; a content not listed takes ashfall_road's. */
export const T1_RANGES = {
  ashfall_road: { advance: [120, 280], gun_line: [60, 160], boss: [120, 330] },
  ambush_15: { advance: [80, 160], gun_line: [60, 120], boss: [100, 190] },
};
export const T1_CREWS = [1, 2, 3, 4];
/**
 * Lead's ruling (docs/decisions/tank.md, "v4: T1 for crew 2"): on ashfall_road a crew of two may hold a gun line up to
 * the brief's own 90% gun-line limit (docs/games/tank.md 4.6.1 checks), not the 160 s of every other crew. One rider
 * shuttles between Gun and Loader while the other repairs, and its holds reach 175 s and 168 s on two seeds; tuning
 * only moved the miss to another seed. Every other crew and every other T1 row stay as they are.
 */
export const T1_CREW2_GUN_LINE_MAX_S = 180;
export const T1_MAX_LOSSES = 1;
/** Hull at 0 on Easy is the old breakdown; the other levels lose the tank instead (TankDifficulty.tank_loss). */
export const T1_MAX_BREAKDOWNS = { easy: 1, normal: 0, hard: 0 };
/** What the "auto" option means per mission (each mission's difficulty_default). */
export const MISSION_DIFFICULTY = { ashfall_road: 'normal', ambush_15: 'hard', drill: 'easy' };
export const T6_DUEL_RANGE = [60, 180];
export const T2_ABOVE_PCT = 80;
export const T2_PER_STAGE_S = 30;
export const T2_BOSS_S = 60;
export const T2_BACK_PCT = 65;
export const T2_BACK_WITHIN_S = 120;
export const T7_ABOVE_PCT = 72;
export const T7_PER_STAGE_S = 30;
export const T7_BACK_PCT = 68;
export const T7_BACK_WITHIN_S = 60;
export const T3_BUILD_RANGE = [4, 12];
export const T3_PAIR_MAX_S = 15;
export const T3_PER_STAGE = 3;
export const T4_MIN_SHARE = 0.5;
export const T4_SHOTS_PER_GUN_LINE = 2;
export const T8_CREWS = [2, 3, 4];
export const T8_KILL_CREWS = [3, 4];
export const T8_KILL_SHARE = 0.4;
/**
 * The longest a near threat lives once it burst out (enemies.json flee_after_s, 20 s at most, plus its flight off the
 * near panel, under 4 s). One younger than this may still be out when its segment ends or the tank is lost: both clear it.
 */
export const NEAR_LIFE_S = 25;
/** tanks.json hull.tow_s: seconds from TANK LOST to the stage's restart. */
export const TOW_S = 8;
/** S15, S16: a mode's "losses 1-2" band; S15: no run above the most. */
export const HARD_LOSSES = [1, 2];
export const HARD_MOST_LOSSES = 4;
/** S16: ambush_15's whole session in game seconds, every segment at its min_s and at its max_s (SPEC_TANK 3.8). */
export const AMBUSH_GAME_S = [780, 1010];
/** Each phase change can run a tick or two past its bound, so a whole session gets a second of slack. */
export const SESSION_SLACK_S = 1;
/** One segment's bound gets the same for its own change and a split inside it. */
export const SEGMENT_SLACK_S = 0.25;
/**
 * BRIEF 4.5: a rider's ERG <-> SIM switches at least this far apart on the trainer's trace. 0.3.1 (no seat lock): the
 * trainer follows a seat move as soon as its last switch is 30 s old, the platform's rule (the PlanValidator's warning,
 * the DirectiveSink's SIM-block spacing); v1-v3 held 60 s, the tank brief's figure that went with the seat lock.
 */
export const SWITCH_SPACING_S = 30;
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
/**
 * The latest moment (sample `t`, end of its tick) a MockTrainer's first notification arrives:
 * MockTrainer.SAMPLE_MAX_S (its notifications come every 0.9-1.1 s, seeded, the first one too).
 * BRIEF 3.5 times the pause on not pedaling from the first *sample* that meets not_pedaling; the
 * report's 1 Hz trace rows before that sample carry the default 0 W telemetry, so the row at t = 0
 * is no sample. test_tank_s2_pause.gd measures the exact anchor in process and pins this value.
 */
export const FIRST_SAMPLE_MAX_S = 1.1;
/**
 * A client's ride pause reaches the host only in its telemetry, sent every GameHost.TELEMETRY_EVERY
 * (4) ticks: 0.2 s. The shared game-clock pause (BRIEF 3.5: only while every human rider is paused)
 * can therefore come up to one telemetry interval after the last rider's own 10 s pause. That pause
 * is a game-clock convenience, not a BRIEF 4.6 rule: each rider's own coasting floor, ride pause and
 * AFK stay bound to 10 s + 1 tick (test_tank_s2_pause.gd, the solo run, the platform's scenarios).
 */
export const SHARED_PAUSE_TELEMETRY_S = 0.2;
export const GRADE_ORDER = ['S', 'A', 'B', 'C', 'D'];
const EPS = 1e-6;

// Event codes (TankIds).
export const SHELL_LIGHT = 1;
export const SHELL_HEAVY = 2;
export const SHELL_OVER = 3;
export const SHELL_BOW = 4;
/** TankEvents.BY_BOW: a kill by the bow guns. */
export const BY_BOW = 3;
export const ENEMY_LIGHT = 1;
export const ENEMY_MEDIUM = 2;
export const ENEMY_HEAVY = 5;
export const BY_BARRAGE = 2;
/** v4: what bursts from the bushes: the recon car and the tankette. */
export const NEAR_CODES = [7, 8];
/** v4: what stands in the far panel, at a range in metres. */
export const FAR_CODES = [1, 2, 3, 5];
/** The dug-in turret's code: reserved, nothing may use it. */
export const DUGIN_CODE = 4;

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

/** [{index, seg, stage, kind, mode, engine, segment, start, end, dur, endedBy, overran}]: one rider's plan phases as they ran. */
export function phaseSpansOf(report, peer = hostPeer(report)) {
  const plan = planOf(report, peer);
  const last = plan.filter((p) => p.kind !== 'COOLDOWN').at(-1);
  const coolSeg = num(last?.meta?.segment, plan.length - 2) + 1;
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
      segment: ph.kind === 'COOLDOWN' ? coolSeg : num(ph.meta?.segment, num(sp.index)),
      start,
      end,
      dur: end - start,
      endedBy: sp.ended_by ?? '',
      overran: sp.ended_by === 'max_s',
    };
  });
}

/**
 * [{index (the segment), seg, stage, kind, mode, engine, start, end, dur, endedBy, overran, phases}] of one rider: its
 * plan phases merged by mission segment (v3: a seat switch splits a segment), `phases` the phase spans, `engine` and
 * `mode` the first phase's, `endedBy` the last phase's.
 */
export function segmentsOf(report, peer = hostPeer(report)) {
  const out = [];
  for (const p of phaseSpansOf(report, peer)) {
    const prev = out.at(-1);
    if (prev && prev.index === p.segment) {
      prev.end = p.end;
      prev.dur = p.end - prev.start;
      prev.endedBy = p.endedBy;
      prev.overran = p.overran;
      prev.phases.push(p);
      continue;
    }
    out.push({ ...p, index: p.segment, phases: [p] });
  }
  return out;
}

/** Plan phases with lap true (the cool-down included, ADR G0.2). */
export const planLaps = (report, peer = hostPeer(report)) => planOf(report, peer).filter((p) => p.lap).length;

// --- result helpers ------------------------------------------------------------------------------------

const skip = (id, title, why) => ({ id, status: 'SKIP', summary: `${title}: ${why}`, details: [] });

/** Sanity of one report against what its name promises: content, players, seed, role. */
export function argsProblems(name, r, want) {
  const probs = [];
  const a = r.args ?? {};
  if (want.content && r.content_id !== want.content) probs.push(`${name}: content ${r.content_id}, wanted ${want.content}`);
  if (want.players !== undefined && num(a.players) !== want.players) probs.push(`${name}: players ${a.players}, wanted ${want.players}`);
  if (want.bots !== undefined && num(a.bots ?? 0) !== want.bots) probs.push(`${name}: bots ${a.bots}, wanted ${want.bots}`);
  if (want.seed !== undefined && num(r.seed) !== want.seed) probs.push(`${name}: seed ${r.seed}, wanted ${want.seed}`);
  if (want.role && r.role !== want.role) probs.push(`${name}: role ${r.role}, wanted ${want.role}`);
  if (want.difficulty && String(a.options?.difficulty ?? 'auto') !== want.difficulty) probs.push(`${name}: difficulty ${a.options?.difficulty}, wanted ${want.difficulty}`);
  if (want.rider && (a.riders ?? [])[0] !== want.rider) probs.push(`${name}: rider ${(a.riders ?? [])[0]}, wanted ${want.rider}`);
  return probs;
}

/** The difficulty a run played at: its option, with "auto" read through the mission's default. */
export function difficultyOf(r) {
  const v = String(r.args?.options?.difficulty ?? 'auto');
  return v === 'auto' ? MISSION_DIFFICULTY[r.content_id] ?? 'normal' : v;
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
/** Times the crew lost the tank (v4, Normal and Hard). */
export const lossesOf = (r) => eventsOf(r, 'tank_lost').length;

/** The segment (segmentsOf row) running at game time `t`: the last one started by then, or null. */
export function segmentAt(segs, t) {
  let at = null;
  for (const s of segs) if (s.start <= t + EPS) at = s;
  return at;
}

/** T1 on one compliant run. A segment that holds a tank loss started over: no range and no "no overrun" for it. */
export function t1Problems(name, r) {
  const probs = [];
  const ranges = T1_RANGES[r.content_id] ?? T1_RANGES.ashfall_road;
  const crew2Hold = ranges === T1_RANGES.ashfall_road && (r.slots ?? []).length === 2;
  const segs = segmentsOf(r);
  const hit = new Set(eventsOf(r, 'tank_lost').map((e) => segmentAt(segs, e._t)?.index));
  for (const s of segs) {
    if (hit.has(s.index)) continue;
    const lim = crew2Hold && s.seg === 'gun_line' ? [ranges.gun_line[0], T1_CREW2_GUN_LINE_MAX_S] : ranges[s.seg];
    if (lim && (!(s.dur >= lim[0] - EPS) || !(s.dur <= lim[1] + EPS))) {
      probs.push(`${name}: ${s.seg} ${s.stage} lasted ${fmt(s.dur)} s (${lim[0]}-${lim[1]})`);
    }
    if (s.overran && s.kind === 'WORK') probs.push(`${name}: ${s.seg} ${s.stage} overran (ended at max_s)`);
  }
  const b = breakdowns(r);
  const mostB = T1_MAX_BREAKDOWNS[difficultyOf(r)] ?? 0;
  if (b > mostB) probs.push(`${name}: ${b} breakdowns (at most ${mostB} on ${difficultyOf(r)})`);
  const lost = lossesOf(r);
  if (lost > T1_MAX_LOSSES) probs.push(`${name}: ${lost} tank losses (at most ${T1_MAX_LOSSES})`);
  const g = gradeOf(r);
  if (GRADE_ORDER.indexOf(g) < 0 || GRADE_ORDER.indexOf(g) > GRADE_ORDER.indexOf('B')) probs.push(`${name}: grade ${g} (B or better)`);
  return probs;
}

/** The applied ERG % FTP rows of `peer` in plan phase `index`. */
const ergRows = (r, peer, index) => traceOf(r, peer).filter((row) => num(row.phase) === index && row.mode === 'ERG');

/** T2 on one compliant crew 2-4 run: seconds above 80% per stage and the return to <= 65%. */
export function t2Problems(name, r) {
  const probs = [];
  const perStage = {};
  for (const peer of humanPeers(r)) {
    const plan = planOf(r, peer);
    const spans = phaseSpansOf(r, peer);
    plan.forEach((ph, index) => {
      const seg = ph.meta?.seg;
      if (ph.meta?.engine !== 'dynamo' || !['advance', 'gun_line', 'boss'].includes(seg)) return;
      const stage = num(ph.meta.stage);
      const rows = ergRows(r, peer, index);
      perStage[stage] = (perStage[stage] ?? 0) + rows.filter((row) => num(row.applied_pct) > T2_ABOVE_PCT).length;
      const sp = spans.find((s) => s.index === index);
      // The fight ends with the segment (a seat switch out of the Gun is not a fight's end).
      const segEnd = sp && spans.find((s) => s.index === index + 1)?.segment !== sp.segment;
      if (seg !== 'advance' && sp && segEnd && Number.isFinite(sp.end)) {
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

/**
 * The Loader's stows of a run (latch events, v3 the ready rack): {perStage: {stage: shells}, gaps: [s]} where a gap is
 * the time between two stows by one rider inside one segment at most T3_PAIR_MAX_S apart (longer ones had the rack
 * full or the seat empty in between).
 */
export function loaderStows(r) {
  const spans = segmentsOf(r);
  const perStage = {};
  const gaps = [];
  const last = {};
  for (const e of eventsOf(r, 'latch')) {
    const seg = spans.find((s) => e._t >= s.start - EPS && (!Number.isFinite(s.end) || e._t < s.end + EPS));
    if (!seg || !['advance', 'gun_line', 'boss'].includes(seg.seg)) continue;
    perStage[seg.stage] = (perStage[seg.stage] ?? 0) + 1;
    const key = `${e.s}`;
    const prev = last[key];
    if (prev && prev.seg === seg.index && e._t - prev.t <= T3_PAIR_MAX_S + EPS) gaps.push(e._t - prev.t);
    last[key] = { t: e._t, seg: seg.index };
  }
  return { perStage, gaps };
}

/** T3 on one compliant crew 3-4 run (v3): shells per stage, and the median back-to-back stow time. */
export function t3Problems(name, r) {
  const probs = [];
  const { perStage, gaps } = loaderStows(r);
  for (const st of [1, 2, 3]) {
    const n = perStage[st] ?? 0;
    if (n < T3_PER_STAGE) probs.push(`${name}: stage ${st}: ${n} shells stowed (need ${T3_PER_STAGE})`);
  }
  if (gaps.length === 0) probs.push(`${name}: no back-to-back stows`);
  else {
    const sorted = [...gaps].sort((a, b) => a - b);
    const med = sorted[Math.floor(sorted.length / 2)];
    if (med < T3_BUILD_RANGE[0] - EPS || med > T3_BUILD_RANGE[1] + EPS) probs.push(`${name}: a shell takes ${fmt(med)} s at the median (${T3_BUILD_RANGE[0]}-${T3_BUILD_RANGE[1]})`);
  }
  return probs;
}

/** The solo rider's Drive share per Advance and main-gun shots per gun line (v3 the solo loop). */
export function soloLoop(r) {
  const host = hostPeer(r);
  const shots = eventsOf(r, 'shot').filter((e) => num(e.s) >= 0 && num(e.sh) !== SHELL_BOW);
  const out = [];
  for (const s of segmentsOf(r, host)) {
    if (!Number.isFinite(s.end)) continue;
    if (s.seg === 'advance') {
      const drive = sum(s.phases.filter((p) => p.engine === 'diesel').map((p) => (Number.isFinite(p.end) ? p.end : s.end) - p.start));
      out.push({ seg: s.seg, stage: s.stage, share: s.dur > 0 ? drive / s.dur : 1 });
    } else if (s.seg === 'gun_line') {
      const inS = (e) => e._t >= s.start - EPS && e._t <= s.end + EPS;
      out.push({ seg: s.seg, stage: s.stage, shots: shots.filter(inS).length });
    }
  }
  return out;
}

/** T4 on one compliant crew 1 run (v3): the solo loop drives and fights. */
export function t4Problems(name, r) {
  const rows = soloLoop(r);
  const probs = rows.some((x) => x.seg === 'advance') ? [] : [`${name}: no Advance found`];
  for (const x of rows) {
    if (x.seg === 'advance' && x.share < T4_MIN_SHARE - EPS) probs.push(`${name}: stage ${x.stage} Advance on Drive ${fmt(100 * x.share)}% (min ${100 * T4_MIN_SHARE}%)`);
    if (x.seg === 'gun_line' && x.shots < T4_SHOTS_PER_GUN_LINE) {
      probs.push(`${name}: stage ${x.stage} holding action: ${x.shots} main-gun shells fired (min ${T4_SHOTS_PER_GUN_LINE})`);
    }
  }
  return probs;
}

/** T6 on one compliant run: a telegraphed shot (light's flank, destroyer) and a medium in each Advance, a heavy duel in holding actions 2 and 3. */
export function t6Problems(name, r, opts = {}) {
  const probs = [];
  const events = gameEvents(r);
  const within = (e, s) => e._t >= s.start - EPS && e._t <= s.end + EPS;
  const seen = (s, code) => events.some((e) => (e.type === 'shot' || e.type === 'kill') && e.e === code && within(e, s));
  const toasts = (r.events ?? []).filter((e) => e && e.type === 'hud' && e.kind === 'toast' && /PROMPT_EVADE/.test(String(e.key ?? '')));
  for (const s of segmentsOf(r)) {
    if (!Number.isFinite(s.end)) continue;
    if (s.seg === 'advance') {
      if (!events.some((e) => e.type === 'evade' && within(e, s))) probs.push(`${name}: stage ${s.stage} Advance has no telegraphed shot (no sprint prompt)`);
      if (!seen(s, ENEMY_MEDIUM)) probs.push(`${name}: stage ${s.stage} Advance has no medium tank`);
      if (opts.requirePrompts && !toasts.some((e) => num(e.t) >= s.start - EPS && num(e.t) <= s.end + EPS)) {
        probs.push(`${name}: stage ${s.stage} Advance raised no "Surge to evade" prompt`);
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

/** The arc rider's fight phases of a crew 4 run: [{peer, index, seg, stage, start, end}]. */
export function arcFights(r) {
  const out = [];
  for (const peer of humanPeers(r)) {
    const plan = planOf(r, peer);
    const spans = phaseSpansOf(r, peer);
    for (const sp of spans) {
      const ph = plan[sp.index];
      // A fight ends with its segment (a seat switch out of the Lights is not a fight's end).
      const segEnd = spans.find((x) => x.index === sp.index + 1)?.segment !== sp.segment;
      if (ph?.meta?.engine === 'arc' && ['advance', 'gun_line', 'boss'].includes(ph.meta.seg)) out.push({ peer, ...sp, segEnd });
    }
  }
  return out;
}

/**
 * T7 on one compliant crew 4 run: the arc rider's applied target above 72% for >= 30 s per stage (stages 1-3, Advance +
 * gun line) and back at <= 68% within 60 s of each fight's end: an arc gun line or boss ending, or a kill in
 * an Advance after which no enemy fires for 60 s while the phase still runs.
 */
export function t7Problems(name, r) {
  const probs = [];
  const perStage = {};
  const events = gameEvents(r);
  const fights = arcFights(r);
  if (fights.length === 0) probs.push(`${name}: no arc generator stage in the plans`);
  for (const f of fights) {
    const rows = traceOf(r, f.peer).filter((row) => num(row.phase) === f.index && row.mode === 'ERG');
    perStage[f.stage] = (perStage[f.stage] ?? 0) + rows.filter((row) => num(row.applied_pct) > T7_ABOVE_PCT).length;
    const ends = [];
    if (f.seg !== 'advance' && f.segEnd && Number.isFinite(f.end)) ends.push(f.end);
    if (f.seg === 'advance' && Number.isFinite(f.end)) {
      for (const k of events.filter((e) => e.type === 'kill' && e._t >= f.start && e._t + T7_BACK_WITHIN_S <= f.end)) {
        const quiet = !events.some((e) => e.type === 'shot' && num(e.s) === -1 && e._t > k._t && e._t <= k._t + T7_BACK_WITHIN_S);
        if (quiet && !ends.some((t) => Math.abs(t - k._t) < T7_BACK_WITHIN_S)) ends.push(k._t);
      }
    }
    for (const t of ends) {
      const after = traceOf(r, f.peer).filter((row) => num(row.game_t) > t - EPS && num(row.game_t) <= t + T7_BACK_WITHIN_S + EPS);
      if (after.length && !after.some((row) => num(row.applied_pct) <= T7_BACK_PCT + EPS)) {
        probs.push(`${name}: peer ${f.peer} ${f.seg} ${f.stage}: the arc target stayed above ${T7_BACK_PCT}% for ${T7_BACK_WITHIN_S} s after the fight at ${fmt(t)} s`);
      }
    }
  }
  // "Per stage" is stages 1-3 (Advance + gun line); the boss's arc time is reported, not held to it.
  for (const st of Object.keys(perStage).map(Number).sort()) {
    if (st >= 1 && st <= 3 && perStage[st] < T7_PER_STAGE_S) probs.push(`${name}: stage ${st}: the arc target above ${T7_ABOVE_PCT}% for ${perStage[st]} s (need ${T7_PER_STAGE_S})`);
  }
  return probs;
}

/**
 * Near threats per run: `rows` one per ambush {id, e, t, seg, out: 'killed' | 'escaped' | ''} (seg the segmentsOf row it
 * burst out in), `unmatched` the near kills and escapes no ambush raised.
 */
export function nearLedger(r) {
  const segs = segmentsOf(r);
  const ends = new Map();
  for (const e of eventsOf(r, 'kill')) if (NEAR_CODES.includes(num(e.e))) ends.set(num(e.id), 'killed');
  for (const e of eventsOf(r, 'escaped')) ends.set(num(e.id), 'escaped');
  const rows = eventsOf(r, 'ambush').map((e) => ({ id: num(e.id), e: num(e.e), t: e._t, seg: segmentAt(segs, e._t), out: ends.get(num(e.id)) ?? '' }));
  const seen = new Set(rows.map((x) => x.id));
  return { rows, unmatched: [...ends.keys()].filter((id) => !seen.has(id)) };
}

/** T8 on one compliant crew 2-4 run. */
export function t8Problems(name, r, crew) {
  const probs = [];
  const { rows, unmatched } = nearLedger(r);
  const segs = segmentsOf(r);
  for (const s of segs) {
    if (s.seg === 'advance' && !rows.some((x) => x.seg?.index === s.index)) probs.push(`${name}: stage ${s.stage} Advance has no ambush`);
  }
  for (const id of unmatched) probs.push(`${name}: near threat ${id} killed or escaped with no ambush`);
  const lost = eventsOf(r, 'tank_lost');
  for (const x of rows) {
    if (x.out !== '') continue;
    // Nothing ended it: only a segment's end or a tank loss clears a near threat, and only one that could still be alive.
    const clear = lost.find((e) => e._t >= x.t - EPS && segmentAt(segs, e._t)?.index === x.seg?.index);
    const by = clear ? clear._t : x.seg?.end;
    if (!(by - x.t <= NEAR_LIFE_S + EPS)) probs.push(`${name}: near threat ${x.id} from ${fmt(x.t)} s neither killed nor escaped`);
  }
  if (T8_KILL_CREWS.includes(crew)) {
    const killed = rows.filter((x) => x.out === 'killed').length;
    if (rows.length && killed / rows.length < T8_KILL_SHARE - EPS) probs.push(`${name}: ${killed} of ${rows.length} near threats killed (at least ${100 * T8_KILL_SHARE}%)`);
  }
  return probs;
}

/** T9 on any run: no enemy shot in a checkpoint, tank losses only in WORK, each one restarted within the tow + 1 s. */
export function t9Problems(name, r) {
  const probs = [];
  const segs = segmentsOf(r);
  for (const e of eventsOf(r, 'shot')) {
    if (num(e.s) !== -1) continue;
    // Inside the checkpoint: the tick that changes the segment still belongs to the fight it ends.
    if (segmentAt(segs, e._t)?.seg === 'checkpoint' && segmentAt(segs, e._t - TICK_S)?.seg === 'checkpoint') probs.push(`${name}: an enemy shot at ${fmt(e._t)} s in a checkpoint`);
  }
  const restarts = eventsOf(r, 'stage_restart');
  for (const e of eventsOf(r, 'tank_lost')) {
    const s = segmentAt(segs, e._t);
    if (s?.kind !== 'WORK' && segmentAt(segs, e._t - TICK_S)?.kind !== 'WORK') probs.push(`${name}: tank lost at ${fmt(e._t)} s in a ${s?.kind} phase`);
    const by = e._t + TOW_S + 1;
    if (restarts.some((x) => x._t >= e._t - EPS && x._t <= by + EPS)) continue;
    if (!(num(s?.end, Infinity) <= by + EPS)) probs.push(`${name}: tank lost at ${fmt(e._t)} s with no stage_restart within ${TOW_S + 1} s and the segment still running`);
  }
  return probs;
}

/** Game time with `key` (rescue, afk) true in `peer`'s 1 Hz trace: [[first row, last row]] of each run of rows. */
export function flagSpans(r, peer, key) {
  const spans = [];
  let cur = null;
  for (const row of traceOf(r, peer)) {
    const t = num(row.game_t, num(row.t));
    if (row[key] === true) {
      if (cur) cur[1] = t;
      else cur = [t, t];
    } else if (cur) {
      spans.push(cur);
      cur = null;
    }
  }
  if (cur) spans.push(cur);
  return spans;
}

/**
 * BRIEF 4.6.3: a rider in rescue or AFK shields the crew, so no tank is lost inside such a span. A client's state
 * reaches the host's rules with its telemetry, so the shield starts up to one telemetry interval and a tick after the rider's own.
 */
export function lossesInSpans(name, r, peer, key) {
  const probs = [];
  const spans = flagSpans(r, peer, key);
  for (const e of eventsOf(r, 'tank_lost')) {
    if (spans.some(([a, b]) => e._t >= a + SHARED_PAUSE_TELEMETRY_S + TICK_S - EPS && e._t <= b + EPS)) probs.push(`${name}: tank lost at ${fmt(e._t)} s while peer ${peer} was in ${key} (BRIEF 4.6.3)`);
  }
  return probs;
}

// --- S1 ----------------------------------------------------------------------------------------------------

export function checkS1(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'ashfall_road, compliant crews 1-4: T1, T2, T3, T4, T6, T7';
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
    if (T1_CREWS.includes(crew)) probs.push(...t1Problems(name, r));
    if (crew >= 2) probs.push(...t2Problems(name, r));
    if (crew >= 3) probs.push(...t3Problems(name, r));
    if (crew === 1) probs.push(...t4Problems(name, r));
    if (crew === 4) probs.push(...t7Problems(name, r));
    if (T8_CREWS.includes(crew)) probs.push(...t8Problems(name, r, crew));
    probs.push(...t9Problems(name, r));
    // The sim report's HUD log holds only the host rider's own toasts, and v3 seats move the host rider onto ERG seats
    // (the Gun, the Lights) too: the "Surge to evade" prompt is required only with --require-prompts.
    probs.push(...t6Problems(name, r, opts));
    lines.push(`c${crew}s${seedS} ${fmt(scoreOf(r))}/${gradeOf(r)}`);
  }
  return result('S1', title, probs, `${found.length} runs: ${lines.join(', ')}`);
}

// --- S2 ----------------------------------------------------------------------------------------------------

/** The first trace row of `peer` at 0 W, or null. */
export function firstNotPedaling(r, peer) {
  return traceOf(r, peer).find((row) => num(row.power_w) <= 0 && num(row.cadence_rpm) <= 0) ?? null;
}

/**
 * The latest platform time (the tick's start, as event `pt`) at which the sample that meets
 * not_pedaling can have arrived, for a rider whose first 0 W trace row is `row`: no sample comes
 * before the trainer's first notification (FIRST_SAMPLE_MAX_S at the latest, the end of its tick),
 * and a 0 W row later in the ride shows a sample that arrived by then.
 */
export function notPedalingAnchor(row) {
  return Math.max(num(row.t), FIRST_SAMPLE_MAX_S - TICK_S);
}

/** GameHost's shared pause (BRIEF 3.5): every human rider ride-paused for not pedaling. */
export const SHARED_PAUSE_REASON = 'all_stopped';

export function checkS2(reports) {
  const title =
    'zero riders: crew 3 (the shared pause holds the hangar), crew 3 spinning at 10 W (every stage overruns, grade D), crew 1 (paused in the hangar)';
  const { found, missing } = pick(reports, ['s2_c3_zero', 's2_c3_idle', 's2_c1_zero']);
  if (found.length === 0) return skip('S2', title, 'no s2_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  // Crew 3 at 0 W: (BRIEF 3.5) every rider ride-pauses after 10 s of not pedaling and the host
  // pauses the shared game clock once all of them are, so the crew never leaves the hangar. A HOST
  // run ends only at max_sim_seconds (`timeout`), still paused. The bound stays 10 s + 1 tick
  // after the last rider's first not-pedaling sample (notPedalingAnchor: the first trainer
  // notification, not the t = 0 trace row).
  const r3 = reports.s2_c3_zero;
  if (r3) {
    const n = 's2_c3_zero';
    probs.push(...argsProblems(n, r3, { content: 'ashfall_road', players: 3, bots: 0, role: 'HOST' }));
    if (r3.end_reason !== 'timeout') probs.push(`${n}: end_reason ${r3.end_reason}, wanted timeout (paused to the end)`);
    const spans = spansOf(r3, hostPeer(r3));
    if (spans.length !== 1 || num(spans[0]?.index) !== 0) probs.push(`${n}: ${spans.length} phases started, wanted only the hangar`);
    const pauses = (r3.events ?? []).filter((e) => e && e.type === 'paused');
    const firsts = humanPeers(r3).map((peer) => firstNotPedaling(r3, peer));
    if (firsts.some((f) => !f)) probs.push(`${n}: a rider without a not-pedaling sample in the trace`);
    else if (!pauses.length || pauses[0].paused !== true || pauses[0].reason !== SHARED_PAUSE_REASON) {
      probs.push(`${n}: never paused for ${SHARED_PAUSE_REASON}`);
    } else {
      const last = Math.max(...firsts.map((f) => notPedalingAnchor(f)));
      if (num(pauses[0].pt) > last + PAUSE_AFTER_S + SHARED_PAUSE_TELEMETRY_S + TICK_S + EPS) {
        probs.push(`${n}: paused at ${fmt(num(pauses[0].pt))} s, ${fmt(num(pauses[0].pt) - last)} s after the last rider's first not-pedaling sample at ${fmt(last)} s at the latest (max ${PAUSE_AFTER_S} s + one telemetry interval ${SHARED_PAUSE_TELEMETRY_S} s + 1 tick)`);
      }
      if (pauses.some((e) => e.paused === false)) probs.push(`${n}: the shared pause ended, nobody pedaled`);
    }
    if (eventsOf(r3, 'kill').length) probs.push(`${n}: kills in a paused run`);
    if (gradeOf(r3) !== 'D') probs.push(`${n}: grade ${gradeOf(r3)}, wanted D`);
  }
  // Crew 3 spinning at 10 W: no detector sees a stopped rider (no pause, no AFK), and the game
  // must still fail them: every Advance, gun line and the boss ends at max_s, withdrawn, grade D.
  // v4: it may lose the tank on the way (Normal); the stage starts over and max_s still ends it.
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
    probs.push(...t9Problems(n, ri));
  }
  const r1 = reports.s2_c1_zero;
  if (r1) {
    const n = 's2_c1_zero';
    probs.push(...argsProblems(n, r1, { content: 'ashfall_road', players: 1, bots: 0, role: 'SOLO' }));
    if (r1.end_reason !== 'paused') probs.push(`${n}: end_reason ${r1.end_reason}, wanted paused`);
    const spans = spansOf(r1, hostPeer(r1));
    if (spans.length !== 1 || num(spans[0]?.index) !== 0) probs.push(`${n}: ${spans.length} phases started, wanted only the hangar`);
    const first = firstNotPedaling(r1, hostPeer(r1));
    const paused = (r1.events ?? []).find((e) => e && e.type === 'paused' && e.paused === true);
    if (!first) probs.push(`${n}: no not-pedaling sample in the trace`);
    else if (!paused) probs.push(`${n}: never paused`);
    else if (num(paused.pt) > notPedalingAnchor(first) + PAUSE_AFTER_S + TICK_S + EPS) {
      const at = notPedalingAnchor(first);
      probs.push(`${n}: paused at ${fmt(num(paused.pt))} s, ${fmt(num(paused.pt) - at)} s after the first not-pedaling sample at ${fmt(at)} s at the latest (max ${PAUSE_AFTER_S} s + 1 tick)`);
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
      probs.push(...t9Problems(name, r));
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

/** What one `request` directive is, by brief 2.3 / 2.7: 'bank' | 'arc' | 'repair' | 'boiler' | 'haptic' | '' (unknown; v3 retired the hoist; v4 Repairs is the director's pattern 10). */
export function classify(d) {
  const q = d.requested ?? {};
  const reason = q.reason;
  if (q.haptic !== undefined) return ['hit', 'boss_hit'].includes(reason) ? 'haptic' : '';
  if (reason === 'bank' && q.mode === 'ERG' && q.target_pct !== undefined) return 'bank';
  if (reason === 'arc' && q.mode === 'ERG' && q.target_pct !== undefined) return 'arc';
  if (reason === 'repair' && q.mode === 'ERG' && q.target_pct !== undefined) return 'repair';
  if (reason === 'boiler' && q.mode === 'SIM' && q.mode_grade !== undefined) return 'boiler';
  return '';
}

const HAPTICS = { hit: [2.0, 1.5], boss_hit: [3.0, 2.0] };

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
    case 'replan':
    case 'split':
      // v3 / 0.3.1: the trainer following a seat (seatProblems and the platform's PlanValidator judge it).
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
      // v4, pattern 10: the Repairs target, held to the same rules as the arc's, on its own seat.
      if (kind === 'repair') {
        const t = num(q.target_pct);
        if (ph.mode !== 'ERG' || ph.kind === 'RECOVERY') probs.push(`${at}: repair target outside an ERG phase`);
        if (ph.meta?.engine !== undefined && ph.meta.engine !== 'repair') probs.push(`${at}: repair target to a rider on ${ph.meta.engine}`);
        const range = ph.range_pct;
        if (!Array.isArray(range)) probs.push(`${at}: repair target in a phase without range_pct (depot or checkpoint)`);
        else if (t < range[0] - EPS || t > range[1] + EPS) probs.push(`${at}: repair target ${t}% outside range_pct ${JSON.stringify(range)}`);
        if (t > 100 + EPS || t < 50 - EPS) probs.push(`${at}: repair target ${t}% outside 50-100% FTP`);
        break;
      }
      if (kind === 'bank' || kind === 'arc') {
        const t = num(q.target_pct);
        const engine = kind === 'bank' ? 'dynamo' : 'arc';
        if (ph.mode !== 'ERG' || ph.kind === 'RECOVERY') probs.push(`${at}: ${kind} target outside an ERG phase`);
        if (ph.meta?.engine !== undefined && ph.meta.engine !== engine) probs.push(`${at}: ${kind} target to a rider on ${ph.meta.engine}`);
        const range = ph.range_pct;
        if (!Array.isArray(range)) probs.push(`${at}: ${kind} target in a phase without range_pct (depot or checkpoint)`);
        else if (t < range[0] - EPS || t > range[1] + EPS) probs.push(`${at}: ${kind} target ${t}% outside range_pct ${JSON.stringify(range)}`);
        if (t > 100 + EPS || t < 50 - EPS) probs.push(`${at}: ${kind} target ${t}% outside 50-100% FTP`);
      } else if (kind === 'boiler') {
        const g = num(q.mode_grade);
        if (ph.mode !== 'SIM') probs.push(`${at}: boiler grade in an ERG phase`);
        if (g < 0 || g > (warm ? 3 : 8) + EPS) probs.push(`${at}: boiler grade ${g}% (max ${warm ? 3 : 8}%)`);
      } else if (kind === 'haptic') {
        const want = HAPTICS[q.reason];
        if (!want || num(q.haptic) !== want[0] || num(q.duration_s) !== want[1]) probs.push(`${at}: haptic ${q.haptic} for ${q.duration_s} s as ${q.reason} (wanted ${want?.join(' for ')} s)`);
        if (ph.mode !== 'SIM') probs.push(`${at}: haptic to an ERG rider`);
        if (warm || ph.kind === 'RECOVERY') probs.push(`${at}: haptic in a ${ph.kind} phase`);
        if (num(d.t) < FIRST_S - EPS) probs.push(`${at}: haptic in the first ${FIRST_S} s of the plan`);
        if (slotOf(r, peer).haptics_on === false && !(d.accepted === false || d.applied?.refused === true)) probs.push(`${at}: haptic applied to a rider who opted out`);
      }
      if (ph.mode === 'ERG' && kind !== 'bank' && kind !== 'arc') probs.push(`${at}: a ${kind} directive (SIM-mode) in an ERG phase`);
      break;
    }
    default:
      probs.push(`${at}: unexpected directive kind`);
  }
  return probs;
}

/**
 * The governor may only lower what Tank asked for: the applied boiler mode grade, bank or arc ERG target and
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
  if (kind === 'repair') over('ERG target %', got.target_pct, q.target_pct);
  if (kind === 'bank' || kind === 'arc') over('ERG target %', got.target_pct, q.target_pct);
  else if (kind === 'boiler') over('mode grade %', got.mode_grade, q.mode_grade);
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

/** Trace rules: no applied ERG above 100% FTP, no SIM -> ERG entry above the target, no haptic early or to ERG, switches >= SWITCH_SPACING_S apart. */
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
    // v3: only the rest of a segment after a seat switch (meta offset_s) continues the segment's lap.
    if (planOf(r, peer).some((p) => p.kind !== 'COOLDOWN' && p.lap !== true && p.meta?.offset_s === undefined)) probs.push(`${name}: peer ${peer} has a plan phase with lap false that is no split`);
  }
  return probs;
}

/**
 * What a matrix report's name promises (S14-S18): {id, content, difficulty, players, bots, seed, role, rider}, or null
 * for any other report. The riders are `erg` at the compliance of the name.
 */
export function matrixRun(name) {
  const make = (id, content, difficulty, players, bots, seed, compliance = '1.0') => ({
    id, content, difficulty, players, bots, seed, role: players >= 2 ? 'HOST' : 'SOLO', rider: `erg:compliance=${compliance}`,
  });
  let m = name.match(/^s14_easy_c(\d)_seed(\d+)$/);
  if (m) return make('S14', 'ashfall_road', 'easy', Number(m[1]), 0, Number(m[2]));
  m = name.match(/^s15_hard_c(\d)_seed(\d+)$/);
  if (m) return make('S15', 'ashfall_road', 'hard', Number(m[1]), 0, Number(m[2]));
  m = name.match(/^s16_amb_(normal|hard)_c(\d)_seed(\d+)$/);
  if (m) return make('S16', 'ambush_15', m[1], Number(m[2]), 0, Number(m[3]));
  m = name.match(/^s17_hard_c3_c(85|70)_seed(\d+)$/);
  if (m) return make('S17', 'ashfall_road', 'hard', 3, 0, Number(m[2]), m[1] === '85' ? '0.85' : '0.70');
  m = name.match(/^s18_bots_h(\d)b(\d)$/);
  if (m) return make('S18', 'ambush_15', 'hard', Number(m[1]), Number(m[2]), 1);
  return null;
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
  // v4: the same rules over every S14-S18 report there is (each scenario's own check says when one is missing).
  for (const [name, r] of Object.entries(reports)) {
    const want = matrixRun(name);
    if (!want) continue;
    probs.push(...argsProblems(name, r, want));
    probs.push(...completeProblems(name, r));
    probs.push(...cleanProblems(name, r));
    probs.push(...planProblems(name, r));
    probs.push(...directivesProblems(name, r));
    probs.push(...traceProblems(name, r));
    probs.push(...lapProblems(name, r));
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
  const title = 'cadence collapse to 30 rpm in a Gun (dynamo) phase and a Lights (arc) phase: rescue, stagger, the plan continues';
  const cases = [
    { name: 's5_c3_dynamo_drop', peer: '2', players: 3 },
    { name: 's5_c4_arc_drop', peer: '4', players: 4 },
  ];
  const { found, missing } = pick(reports, cases.map((c) => c.name));
  if (found.length === 0) return skip('S5', title, 'no s5_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const notes = [];
  for (const c of cases) {
    const r = reports[c.name];
    if (!r) continue;
    const n = c.name;
    probs.push(...argsProblems(n, r, { content: 'ashfall_road', players: c.players, bots: 0, role: 'HOST' }));
    probs.push(...completeProblems(n, r));
    probs.push(...cleanProblems(n, r));
    probs.push(...lossesInSpans(n, r, c.peer, 'rescue'));
    const st = rescueStats(r, c.peer);
    if (st.rows === 0) probs.push(`${n}: peer ${c.peer} never entered rescue`);
    else {
      if (!(st.maxPct <= 50 + 100 / Math.max(num(slotOf(r, c.peer).ftp, 200), 1) + EPS)) probs.push(`${n}: rescue applied ${fmt(st.maxPct)}% FTP (wanted 50%)`);
      // Rescue arms only in ERG at 60% FTP or more (BRIEF 4.6.3): the phase it began in is an ERG phase of the Gun or Lights.
      const { ph } = phaseAt(r, c.peer, num(st.first.game_t));
      if (ph?.mode !== 'ERG' || !['dynamo', 'arc'].includes(ph?.meta?.engine)) probs.push(`${n}: rescue began in a ${ph?.mode} phase of ${ph?.meta?.engine} (wanted the Gun or the Lights in ERG)`);
      const afterRows = traceOf(r, c.peer).filter((row) => num(row.game_t) > num(st.last.game_t));
      if (!afterRows.some((row) => row.rescue !== true)) probs.push(`${n}: rescue never ended`);
      const clampedRescue = traceOf(r, c.peer).some((row) => row.rescue === true && (row.clamped_by ?? []).includes('rescue'));
      if (!clampedRescue) probs.push(`${n}: no trace row clamped by rescue`);
      notes.push(`${c.name} ${st.rows} s in rescue`);
    }
    const spans = phaseSpansOf(r, c.peer);
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

/** A trailing mean power at or above this share of FTP is a sprint (the sprint rule, 1.2 x FTP). The S9 rider (run_sims.sh) rides 12 s at 1.5 x FTP every 40 s. */
export const S9_SPRINT_SIM_FTP_PCT = 120;

/** The telegraphed shots a rider's surge made miss (`evade` ok 1; v4: raised when the far shell lands, after its `shot`). */
export const successfulEvades = (r) => eventsOf(r, 'evade').filter((e) => num(e.ok) === 1);

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
  const title = 'a sprinting solo rider: successful evades, no Ram (v2), gun lines entered after a sprint at or below their target';
  const n = 's9_c1_sprint';
  const r = reports[n];
  if (!r) return skip('S9', title, `no ${n} report`);
  const probs = [...argsProblems(n, r, { content: 'ashfall_road', players: 1, bots: 0, role: 'SOLO' }), ...completeProblems(n, r)];
  probs.push(...cleanProblems(n, r), ...planProblems(n, r), ...directivesProblems(n, r), ...traceProblems(n, r), ...lapProblems(n, r));
  const evades = successfulEvades(r);
  if (evades.length === 0) probs.push(`${n}: the sprinting rider never made a telegraphed shot miss`);
  for (const e of evades) {
    if (num(e.s) !== 0) probs.push(`${n}: evade at ${fmt(e._t)} s credited to slot ${e.s} (the solo rider is slot 0)`);
  }
  const ram = gameEvents(r).filter((e) => e.type === 'ram' || e.type === 'dodge');
  if (ram.length) probs.push(`${n}: ${ram.length} Ram or dodge events (v2 has none)`);
  const hap = (r.directives ?? []).filter((d) => d.kind === 'request' && d.requested?.reason === 'ram');
  if (hap.length) probs.push(`${n}: ${hap.length} ram haptics (v2 has none)`);
  // Every ERG phase entered from SIM (v3: a move to the Gun or the Lights, a checkpoint), above all straight after a sprint:
  // the trainer must start at the planned target, not at the sprint power.
  const host = hostPeer(r);
  const ftp = num(slotOf(r, host).ftp, 200);
  const all = switchesIntoErg(r, host);
  const entries = all.filter((sw) => sw.trailingW >= (S9_SPRINT_SIM_FTP_PCT / 100) * ftp - EPS);
  for (const sw of all) {
    const bound = enteredTargetW(r, host, sw.phase) + 1;
    const first = traceOf(r, host).filter((row) => num(row.phase) === sw.phase && row.mode === 'ERG' && num(row.game_t, num(row.t)) <= sw.t + 5);
    const worst = Math.max(0, ...first.map((row) => num(row.applied_target_w)));
    if (worst > bound + EPS) probs.push(`${n}: ERG phase ${sw.phase} at ${fmt(sw.t)} s entered after ${fmt(sw.trailingW)} W with a ${worst} W target (planned ${Math.round(bound - 1)} W)`);
  }
  const tried = eventsOf(r, 'evade').length;
  return result('S9', title, probs, `${evades.length} of ${tried} telegraphed shots evaded, ${all.length} ERG entries (${entries.length} after a sprint)`);
}

// --- S10: clients sending intents, a client that stops ---------------------------------------------------------------

/** AFK comes 10 s after the first not-pedaling sample (BRIEF 4.6.4); the trace is sampled once a second. */
export const AFK_AFTER_S = 10;
/** The engine of `peer`'s plan phase at report time t, or ''. */
const engineAt = (r, peer, t) => planOf(r, peer)[phaseIndexAt(r, peer, t)]?.meta?.engine ?? '';

/** The seat `peer` sat on at game time `t`: its last seat event's seat before `t`, else its plan's first seat (0.3.1: a move lands at once, the plan follows later). */
export function seatAt(r, peer, t) {
  const slot = num(slotOf(r, peer).slot, -1);
  let seat = engineAt(r, peer, 0);
  for (const e of eventsOf(r, 'seat')) if (num(e.s) === slot && e._t <= t + EPS) seat = ENGINE_OF_CODE[num(e.to)] ?? seat;
  return seat;
}

/** Overpressure latches (latch sh 3) whose slot was not on the steam engine then (`over` must be owned by its engine). */
export function intentOwnershipProblems(name, r) {
  const probs = [];
  for (const e of gameEvents(r)) {
    if (e.type === 'ram' || e.type === 'dodge') probs.push(`${name}: a ${e.type} event at ${fmt(e._t)} s (v2 has none)`);
    if (e.type !== 'latch' || num(e.sh) !== SHELL_OVER) continue;
    const peer = peerOfSlot(r, e.s);
    const engine = peer === null ? '' : seatAt(r, peer, e._t);
    if (engine !== 'steam') probs.push(`${name}: an Overpressure shell by slot ${e.s} at ${fmt(e._t)} s, who was on "${engine}", not the steam engine`);
  }
  return probs;
}

/** Overpressure shells (latch sh 3) latched by a client rider (slot 1 or 2): their `over` came over Telemetry.intents. */
export const clientOverpressures = (r) => eventsOf(r, 'latch').filter((e) => num(e.sh) === SHELL_OVER && num(e.s) >= 1);

export function checkS10(reports) {
  const title = 'crew 3 where the clients send the intents and one stops: client Overpressure, a station on reserve through a rescue';
  const cases = ['s10_c3_clients_sprint', 's10_c3_dynamo_stop'];
  const { found, missing } = pick(reports, cases);
  if (found.length === 0) return skip('S10', title, 'no s10_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const notes = [];
  const hygiene = (n, r) => {
    probs.push(...argsProblems(n, r, { content: 'ashfall_road', players: 3, bots: 0, role: 'HOST' }), ...completeProblems(n, r));
    probs.push(...cleanProblems(n, r), ...planProblems(n, r), ...directivesProblems(n, r), ...traceProblems(n, r), ...lapProblems(n, r));
  };

  // Every rider sprints: a client on the steam engine surges in the window, its `over` reaches the host as Telemetry.intents
  // (owned by the steam engine) and the held sprint builds an Overpressure shell.
  const sprint = reports.s10_c3_clients_sprint;
  if (sprint) {
    const n = 's10_c3_clients_sprint';
    hygiene(n, sprint);
    probs.push(...intentOwnershipProblems(n, sprint));
    const overs = clientOverpressures(sprint);
    if (overs.length === 0) probs.push(`${n}: no client rider (slot 1 or 2) latched an Overpressure shell: their over intents never reached the host`);
    notes.push(`${n} ${overs.length} client Overpressure shells`);
  }

  // Slot 1 stops pedaling on the Gun in stage 1's Advance (the dynamo, ERG 60% or more; v4's near threats can pull it off the Gun by plan phase 3): rescue, then AFK and a station on reserve, then back.
  const stop = reports.s10_c3_dynamo_stop;
  if (stop) {
    const n = 's10_c3_dynamo_stop';
    hygiene(n, stop);
    const peer = '2';
    const rows = traceOf(stop, peer);
    const span = phaseSpansOf(stop, peer).find((x) => x.index === 2);
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
    probs.push(...lossesInSpans(n, stop, peer, 'afk'));
    const st = rescueStats(stop, peer);
    if (st.rows === 0) probs.push(`${n}: peer ${peer} never entered rescue`);
    else if (!(st.maxPct <= 50 + 100 / Math.max(num(slotOf(stop, peer).ftp, 200), 1) + EPS)) probs.push(`${n}: rescue applied ${fmt(st.maxPct)}% FTP (wanted 50% or less)`);
    for (const other of humanPeers(stop)) {
      if (other === peer) continue;
      if (traceOf(stop, other).some((row) => row.rescue === true || row.afk === true)) probs.push(`${n}: peer ${other} (not the rider who stopped) was in rescue or AFK`);
    }
    if (phaseSpansOf(stop, peer).length !== planOf(stop, peer).length) probs.push(`${n}: the plan did not continue to its last phase`);
    notes.push(`${n} ${afk.length} s AFK, ${st.rows} s in rescue`);
  }
  return result('S10', title, probs, notes.join(', '));
}

// --- S11 and S12: free roam (brief 2.10) ---------------------------------------------------------------------

/** The roam phase is plan phase 1 (after the 300 s drive-out); its min_s is minutes x 60 - 300, max_s min_s + 300. */
export const ROAM_PHASE = 1;
export const ROAM_DRIVE_OUT_S = 300;
export const ROAM_OVERTIME_S = 300;
/** FIT laps of a free roam: the drive-out, the roam and the platform's cool-down. */
export const ROAM_LAPS = 3;
/** Brief 2.8 / 2.10: a compliant 30-min crew of 3 earns B or A. */
export const ROAM_TARGET_GRADES = ['A', 'B'];
/** content/tank/roam/valley.json grades: points per WORK minute (the brief's 9 / 7 / 5 / 3 x 2.5, P5 tuning). */
export const ROAM_GRADES = [['S', 22.5], ['A', 17.5], ['B', 12.5], ['C', 7.5]];

/** The minutes of a roam content id (roam_30 -> 30), or NaN. */
export const roamMinutes = (contentId) => Number(String(contentId ?? '').match(/^roam_(\d+)$/)?.[1] ?? NaN);

/** The grade of `pointsPerMin` points per WORK minute (ROAM_GRADES, else D). */
export function roamGrade(pointsPerMin) {
  for (const [g, cut] of ROAM_GRADES) if (pointsPerMin >= cut - EPS) return g;
  return 'D';
}

/** Problems of one completed free-roam run: time up, the overtime bound, no patrol after it, laps, the grade. */
export function roamProblems(name, r) {
  const probs = [];
  const minutes = roamMinutes(r.content_id);
  const minS = minutes * 60 - ROAM_DRIVE_OUT_S;
  const maxS = minS + ROAM_OVERTIME_S;
  probs.push(...completeProblems(name, r, ['time_up']));
  probs.push(...cleanProblems(name, r));
  probs.push(...planProblems(name, r));
  probs.push(...directivesProblems(name, r));
  probs.push(...traceProblems(name, r));
  for (const peer of humanPeers(r)) {
    const plan = planOf(r, peer);
    if (planLaps(r, peer) !== ROAM_LAPS) probs.push(`${name}: peer ${peer} plan has ${planLaps(r, peer)} lap-true phases, wanted ${ROAM_LAPS}`);
    // v3: the roam phase is open from 60 s (a seat switch may split it); its meta carries the segment's own min_s.
    const ph = plan[ROAM_PHASE] ?? {};
    if (num(ph.meta?.seg_min_s) !== minS || num(ph.max_s) !== maxS) probs.push(`${name}: peer ${peer} roam phase ${ph.meta?.seg_min_s}-${ph.max_s} s, wanted ${minS}-${maxS}`);
    const seg = segmentsOf(r, peer).find((x) => x.index === ROAM_PHASE);
    if (!seg) {
      probs.push(`${name}: peer ${peer} never reached the roam phase`);
      continue;
    }
    if (seg.endedBy !== 'end_phase') probs.push(`${name}: peer ${peer} roam phase ended by ${seg.endedBy || 'nothing'}, wanted end_phase`);
    if (seg.dur < minS - TICK_S - EPS) probs.push(`${name}: peer ${peer} roam phase ${fmt(seg.dur)} s, ended before min_s ${minS}`);
    if (seg.dur > maxS + EPS) probs.push(`${name}: peer ${peer} roam phase ${fmt(seg.dur)} s, past the overtime bound ${maxS}`);
  }
  const host = hostPeer(r);
  const starts = segmentsOf(r, host).filter((x) => x.index === ROAM_PHASE).map((x) => x.start);
  const ends = segmentsOf(r, host).filter((x) => x.index === ROAM_PHASE + 1).map((x) => x.start);
  const peersEnded = new Set(humanPeers(r).map((p) => fmt(segmentsOf(r, p).find((x) => x.index === ROAM_PHASE + 1)?.start ?? NaN)));
  if (peersEnded.size > 1) probs.push(`${name}: the riders left the roam phase at different times (${[...peersEnded].join(', ')}), wanted one step`);
  const ups = eventsOf(r, 'time_up');
  if (ups.length !== 1) probs.push(`${name}: ${ups.length} time_up events, wanted 1`);
  else if (starts.length && Math.abs(num(ups[0]._t) - (starts[0] + minS)) > 0.2) {
    probs.push(`${name}: time up at ${fmt(num(ups[0]._t))} s, wanted the roam start ${fmt(starts[0])} + min_s ${minS}`);
  }
  const patrols = num(r.results?.team?.TANK_TEAM_PATROLS, NaN);
  if (ups.length === 1 && Number.isFinite(patrols) && num(ups[0].p, NaN) !== patrols) {
    probs.push(`${name}: ${patrols} patrols in all but ${ups[0].p} at time up: a patrol came after time up`);
  }
  if (ends.length && ups.length === 1 && ends[0] < num(ups[0]._t) - EPS) probs.push(`${name}: the roam ended before time up`);
  const results = r.results ?? {};
  const workMin = ups.length && ends.length ? (ends[0] - (starts[0] ?? 0)) / 60 : NaN;
  const points = num(results.score, NaN);
  if (Number.isFinite(workMin) && Number.isFinite(points) && results.grade !== roamGrade(points / workMin)) {
    probs.push(`${name}: grade ${results.grade} for ${fmt(points)} points in ${fmt(workMin)} WORK minutes (${fmt(points / workMin)} a minute, wanted ${roamGrade(points / workMin)})`);
  }
  if (results.ride_tag !== `Free Roam ${minutes} min`) probs.push(`${name}: ride_tag "${results.ride_tag}", wanted "Free Roam ${minutes} min"`);
  return probs;
}

/**
 * Nothing comes from behind (v4): every far enemy's shot carries its range ahead of the hull, in metres, and no event
 * names the retired dug-in turret. An enemy behind the tank would have no such range.
 */
export function behindProblems(name, r) {
  const probs = [];
  let n = 0;
  for (const e of gameEvents(r)) {
    if ((e.type === 'shot' && num(e.s) === -1 && FAR_CODES.includes(num(e.e)) && !(num(e.rng_m) > 0)) || (['shot', 'kill', 'evade'].includes(e.type) && num(e.e) === DUGIN_CODE)) {
      n += 1;
      if (n <= 3) probs.push(`${name}: ${e.type} of enemy code ${e.e} at ${fmt(e._t)} s with range ${e.rng_m} (nothing stands behind the tank, nothing is dug in)`);
    }
  }
  if (n > 3) probs.push(`${name}: ... ${n - 3} more`);
  return probs;
}

/** One line of a roam run's numbers for the summary. */
export function roamLine(name, r) {
  const host = hostPeer(r);
  const seg = segmentsOf(r, host).find((x) => x.index === ROAM_PHASE);
  const minS = roamMinutes(r.content_id) * 60 - ROAM_DRIVE_OUT_S;
  const team = r.results?.team ?? {};
  const kills = eventsOf(r, 'kill').filter((e) => num(e.by) !== BY_BARRAGE).length;
  const turns = eventsOf(r, 'turn').length;
  return `${name} ${seg ? fmt(seg.dur) : '?'} s (overtime ${seg ? fmt(Math.max(0, seg.dur - minS)) : '?'} s), ${fmt(num(r.results?.score, NaN))} points (${team.TANK_TEAM_POINTS_PER_MIN ?? '?'}/min), ${kills} kills (${team.TANK_TEAM_ROAM_KILLS ?? '?'}), ${turns} turns, ${team.TANK_TEAM_PATROLS ?? '?'} patrols, grade ${gradeOf(r)}`;
}

export function checkS11(reports) {
  const title = 'free roam: roam_10 crews 1 and 4, roam_30 crew 3 (time up, the overtime bound, no patrol after time up, FIT laps, grade)';
  const want = [
    ['s11_roam10_c1', 'roam_10', 1, 'SOLO'],
    ['s11_roam10_c4', 'roam_10', 4, 'HOST'],
    ['s11_roam30_c3', 'roam_30', 3, 'HOST'],
  ];
  const { found, missing } = pick(reports, want.map((w) => w[0]));
  if (found.length === 0) return skip('S11', title, 'no s11_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const lines = [];
  for (const [name, content, players, role] of want) {
    const r = reports[name];
    if (!r) continue;
    probs.push(...argsProblems(name, r, { content, players, bots: 0, role }));
    probs.push(...roamProblems(name, r));
    probs.push(...behindProblems(name, r));
    if (name === 's11_roam30_c3' && !ROAM_TARGET_GRADES.includes(gradeOf(r))) {
      probs.push(`${name}: grade ${gradeOf(r)}, wanted ${ROAM_TARGET_GRADES.join(' or ')} (a compliant 30-min crew of 3)`);
    }
    lines.push(roamLine(name, r));
  }
  return result('S11', title, probs, lines.join('; '));
}

export function checkS12(reports) {
  const title = 'free roam roam_10, crew 3 at 0 W: the shared pause holds the drive-out, no kill by crew fire, grade D';
  const n = 's12_roam10_c3_zero';
  const r = reports[n];
  if (!r) return skip('S12', title, `no ${n} report`);
  const probs = argsProblems(n, r, { content: 'roam_10', players: 3, bots: 0, role: 'HOST' });
  // As s2_c3_zero: every rider ride-pauses for not pedaling and the host pauses the shared game clock, so the
  // run ends at --max-sim-seconds still paused, in the drive-out.
  if (r.end_reason !== 'timeout') probs.push(`${n}: end_reason ${r.end_reason}, wanted timeout (paused to the end)`);
  const spans = spansOf(r, hostPeer(r));
  if (spans.length !== 1 || num(spans[0]?.index) !== 0) probs.push(`${n}: ${spans.length} phases started, wanted only the drive-out`);
  const pauses = (r.events ?? []).filter((e) => e && e.type === 'paused');
  if (!pauses.length || pauses[0].paused !== true || pauses[0].reason !== SHARED_PAUSE_REASON) probs.push(`${n}: never paused for ${SHARED_PAUSE_REASON}`);
  if (pauses.some((e) => e.paused === false)) probs.push(`${n}: the shared pause ended, nobody pedaled`);
  const crewKills = eventsOf(r, 'kill').filter((e) => num(e.by) !== BY_BARRAGE);
  if (crewKills.length) probs.push(`${n}: ${crewKills.length} kills by crew fire at 0 W`);
  if (gradeOf(r) !== 'D') probs.push(`${n}: grade ${gradeOf(r)}, wanted D`);
  probs.push(...behindProblems(n, r));
  return result('S12', title, probs, `${r.end_reason}, ${crewKills.length} kills, grade ${gradeOf(r)}`);
}

// --- S13: seat switching (v3) -----------------------------------------------------------------------------------------

/** Engine codes (TankIds.ENGINE_CODES). */
export const ENGINE_OF_CODE = { 1: 'diesel', 2: 'dynamo', 3: 'steam', 5: 'arc', 6: 'feed', 7: 'repair' };
/** Plan follows: the trainer is on a moved rider's new seat within this long (the switch spacing and a tick). */
export const FOLLOW_SLACK_S = 0.2;

/**
 * The trainer follows each seat move (0.3.1): the rider's plan engine is the new seat within SWITCH_SPACING_S (and a
 * tick) of the move, or at the start of the next segment when the switch waits for the segment's end, unless the
 * rider moved again first. Every split and replan is accepted with no plan warning.
 */
export function seatProblems(name, r) {
  const probs = [];
  const seats = eventsOf(r, 'seat');
  const bySlot = {};
  for (const e of seats) (bySlot[num(e.s)] ??= []).push(e);
  for (const [slot, moves] of Object.entries(bySlot)) {
    const peer = peerOfSlot(r, num(slot));
    if (peer === null) continue;
    const spans = phaseSpansOf(r, peer);
    moves.forEach((e, k) => {
      const want = ENGINE_OF_CODE[num(e.to)];
      const next = k + 1 < moves.length ? moves[k + 1]._t : Infinity;
      const deadline = Math.min(e._t + SWITCH_SPACING_S + FOLLOW_SLACK_S, next);
      const starts = spans.filter((sp) => sp.start >= e._t - EPS && sp.start <= deadline + EPS).map((sp) => sp.start);
      let ok = [e._t + 0.06, ...starts.map((t) => t + 0.01)].some((t) => t <= deadline + EPS && engineAt(r, peer, t) === want);
      if (!ok) {
        // The switch waits for the segment's end: the next segment starts on the new seat.
        const cur = spans.find((sp) => sp.start <= e._t + EPS && (!Number.isFinite(sp.end) || sp.end > e._t));
        const after = cur ? spans.find((sp) => sp.segment !== cur.segment && sp.start >= cur.start) : null;
        ok = after !== null && after !== undefined && after.start <= next + EPS && engineAt(r, peer, after.start + 0.01) === want;
      }
      if (!ok && next === Infinity && e._t > num(r.game_seconds, Infinity) - SWITCH_SPACING_S) ok = true;
      if (!ok) probs.push(`${name}: slot ${slot} moved to ${want} at ${fmt(e._t)} s; its trainer never followed`);
    });
  }
  for (const d of r.directives ?? []) {
    if (d.kind !== 'replan' && d.kind !== 'split') continue;
    if (d.accepted === false) probs.push(`${name}: ${d.kind} ${d.id} (peer ${d.peer} at ${fmt(num(d.t))} s) refused: ${d.reason}`);
    const warn = d.requested?.warnings;
    if (Array.isArray(warn) && warn.length) probs.push(`${name}: ${d.kind} ${d.id} warned: ${warn.join('; ')}`);
  }
  return probs;
}

export function checkS13(reports) {
  const title = 'seat switching: crew 3 on the fallback seated at once, the trainer following (no lock, splits, switches, laps)';
  const n = 's13_c3_seats';
  const r = reports[n];
  if (!r) return skip('S13', title, `no ${n} report`);
  const probs = [...argsProblems(n, r, { content: 'ashfall_road', players: 3, bots: 0, role: 'HOST' }), ...completeProblems(n, r)];
  probs.push(...cleanProblems(n, r), ...planProblems(n, r), ...directivesProblems(n, r), ...traceProblems(n, r), ...lapProblems(n, r));
  probs.push(...seatProblems(n, r));
  const seats = eventsOf(r, 'seat');
  const clients = seats.filter((e) => num(e.s) >= 1);
  if (seats.length < 3) probs.push(`${n}: ${seats.length} seat moves (want at least 3)`);
  if (clients.length === 0) probs.push(`${n}: no client rider (slot 1 or 2) moved seats`);
  const follows = (r.directives ?? []).filter((d) => d.kind === 'replan' || d.kind === 'split');
  if (follows.length === 0) probs.push(`${n}: no split or replan followed the ${seats.length} moves`);
  return result('S13', title, probs, `${seats.length} moves (${clients.length} by clients), ${follows.length} splits and replans`);
}

// --- S14-S18: difficulty, the short session, bots --------------------------------------------------------------

/** How many of `n` seeds a "most seeds" target asks for: 2 of 3 (and so 1 of 1 on a one-seed subset run). */
export const mostOf = (n) => Math.ceil((2 * n) / 3);
const isWin = (r) => r.finished_reason === 'victory';

/** A matrix run's arguments and everything S4 holds it to (a complete run, directives, plans, trace, laps), plus T9. */
export function matrixProblems(name, r) {
  const want = matrixRun(name);
  return [
    ...argsProblems(name, r, want),
    ...completeProblems(name, r),
    ...cleanProblems(name, r),
    ...planProblems(name, r),
    ...directivesProblems(name, r),
    ...traceProblems(name, r),
    ...lapProblems(name, r),
    ...t9Problems(name, r),
  ];
}

/** Every open-ended segment of every human ran inside its min_s..max_s, whatever a restart or a seat split did. */
export function phaseBoundProblems(name, r) {
  const probs = [];
  for (const peer of humanPeers(r)) {
    const plan = planOf(r, peer);
    for (const s of segmentsOf(r, peer)) {
      const ph = plan[s.phases[0]?.index];
      if (!ph?.open_ended || !Number.isFinite(s.end)) continue;
      const lo = num(ph.meta?.seg_min_s, num(ph.min_s));
      const hi = num(ph.max_s, Infinity);
      if (s.dur < lo - SEGMENT_SLACK_S || s.dur > hi + SEGMENT_SLACK_S) probs.push(`${name}: peer ${peer} ${s.seg} ${s.stage} lasted ${fmt(s.dur)} s (${lo}-${hi})`);
    }
  }
  return probs;
}

/** The longest the plan can run: each segment at its max_s (a fixed one at its duration) and the cool-down. */
export function planMaxS(r, peer = hostPeer(r)) {
  const first = planOf(r, peer).filter((p) => p.meta?.offset_s === undefined);
  return sum(first.map((p) => num(p.open_ended ? p.max_s : p.duration_s)));
}

/** A session that stayed on its plan: the game clock under the plan's longest. */
export function planTotalProblems(name, r) {
  const most = planMaxS(r);
  const got = num(r.game_seconds, NaN);
  return got <= most + SESSION_SLACK_S ? [] : [`${name}: ${fmt(got)} game seconds, over the plan's longest ${fmt(most)} s`];
}

export function checkS14(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'ashfall_road on Easy, crews 1-4: victory every run, no tank loss, T1';
  const names = [];
  for (const c of CREWS) for (const s of seeds) names.push(`s14_easy_c${c}_seed${s}`);
  const { found, missing } = pick(reports, names);
  if (found.length === 0) return skip('S14', title, 'no s14_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  for (const [name, r] of found) {
    probs.push(...matrixProblems(name, r));
    if (!isWin(r)) probs.push(`${name}: finished "${r.finished_reason}", wanted victory`);
    if (lossesOf(r) !== 0) probs.push(`${name}: ${lossesOf(r)} tank losses on Easy (none)`);
    probs.push(...t1Problems(name, r));
  }
  return result('S14', title, probs, `${found.length} runs`);
}

export function checkS15(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'ashfall_road on Hard, crews 1-4: 1-2 losses on most seeds, none above 4, phases, 13 laps and S4 still hold';
  const names = [];
  for (const c of CREWS) for (const s of seeds) names.push(`s15_hard_c${c}_seed${s}`);
  const { found, missing } = pick(reports, names);
  if (found.length === 0) return skip('S15', title, 'no s15_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const lines = [];
  for (const c of CREWS) {
    const runs = found.filter(([n]) => n.startsWith(`s15_hard_c${c}_`));
    if (runs.length === 0) continue;
    for (const [name, r] of runs) {
      probs.push(...matrixProblems(name, r), ...phaseBoundProblems(name, r), ...planTotalProblems(name, r));
      if (lossesOf(r) > HARD_MOST_LOSSES) probs.push(`${name}: ${lossesOf(r)} tank losses (at most ${HARD_MOST_LOSSES})`);
    }
    const losses = runs.map(([, r]) => lossesOf(r));
    const inBand = losses.filter((n) => n >= HARD_LOSSES[0] && n <= HARD_LOSSES[1]).length;
    if (inBand < mostOf(seeds.length)) probs.push(`crew ${c}: ${inBand} of ${seeds.length} seeds with ${HARD_LOSSES.join('-')} losses (at least ${mostOf(seeds.length)}; losses ${losses.join(', ')})`);
    lines.push(`c${c} losses ${losses.join('/')}`);
  }
  return result('S15', title, probs, lines.join(', '));
}

export function checkS16(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'ambush_15, crews 1, 3, 4: Normal at most 1 loss and wins on most seeds, Hard 1-2 losses on most seeds, 780-1010 game seconds, 7 laps, S4';
  const crews = [1, 3, 4];
  const names = [];
  for (const d of ['normal', 'hard']) for (const c of crews) for (const s of seeds) names.push(`s16_amb_${d}_c${c}_seed${s}`);
  const { found, missing } = pick(reports, names);
  if (found.length === 0) return skip('S16', title, 'no s16_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const lines = [];
  const need = mostOf(seeds.length);
  for (const [name, r] of found) {
    probs.push(...matrixProblems(name, r));
    const got = num(r.game_seconds, NaN);
    if (!(got >= AMBUSH_GAME_S[0] - SESSION_SLACK_S && got <= AMBUSH_GAME_S[1] + SESSION_SLACK_S)) probs.push(`${name}: ${fmt(got)} game seconds (${AMBUSH_GAME_S.join('-')})`);
  }
  for (const d of ['normal', 'hard']) {
    for (const c of crews) {
      const runs = found.filter(([n]) => n.startsWith(`s16_amb_${d}_c${c}_`));
      if (runs.length === 0) continue;
      const losses = runs.map(([, r]) => lossesOf(r));
      if (d === 'normal') {
        for (const [name, r] of runs) {
          if (lossesOf(r) > T1_MAX_LOSSES) probs.push(`${name}: ${lossesOf(r)} tank losses (at most ${T1_MAX_LOSSES} on Normal)`);
          // "Usually wins, T1": a seed that fell short answers to the win count, not to the time ranges.
          if (isWin(r)) probs.push(...t1Problems(name, r));
        }
        const wins = runs.filter(([, r]) => isWin(r)).length;
        if (wins < need) probs.push(`normal crew ${c}: ${wins} of ${seeds.length} seeds won (at least ${need})`);
      } else {
        const inBand = losses.filter((n) => n >= HARD_LOSSES[0] && n <= HARD_LOSSES[1]).length;
        if (inBand < need) probs.push(`hard crew ${c}: ${inBand} of ${seeds.length} seeds with ${HARD_LOSSES.join('-')} losses (at least ${need}; losses ${losses.join(', ')})`);
      }
      lines.push(`${d} c${c} losses ${losses.join('/')}`);
    }
  }
  return result('S16', title, probs, lines.join(', '));
}

export function checkS17(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'crew 3 on Hard falling behind: more losses at 85% than at 100%; at 70% rescue shields the crew and it completes';
  const behind = seeds.map((s) => `s17_hard_c3_c85_seed${s}`);
  const stagger = 's17_hard_c3_c70_seed1';
  const { found, missing } = pick(reports, [...behind, stagger]);
  if (found.length === 0) return skip('S17', title, 'no s17_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  for (const [name, r] of found) probs.push(...matrixProblems(name, r));
  const base = pick(reports, seeds.map((s) => `s15_hard_c3_seed${s}`));
  probs.push(...base.missing.map((m) => `missing report ${m}`));
  const meanLow = mean(found.filter(([n]) => n !== stagger).map(([, r]) => lossesOf(r)));
  const meanFull = mean(base.found.map(([, r]) => lossesOf(r)));
  if (!(meanLow > meanFull)) probs.push(`mean losses at 85% (${fmt(meanLow)}) are not above 100% (${fmt(meanFull)})`);
  const r70 = reports[stagger];
  if (r70) for (const peer of humanPeers(r70)) probs.push(...lossesInSpans(stagger, r70, peer, 'rescue'));
  return result('S17', title, probs, `mean losses 100% ${fmt(meanFull)}, 85% ${fmt(meanLow)}${r70 ? `, 70% ${lossesOf(r70)}` : ''}`);
}

/**
 * Bots act only through their own seats (SPEC_TANK 3.7): they do move, a bot never lands on a human's seat, and a
 * human's trainer never follows anything but that human's own seat move (a split or replan with no seat event of
 * its slot before it would be an effort change a bot caused).
 */
export function botSeatProblems(name, r) {
  const probs = [];
  const seats = eventsOf(r, 'seat');
  const humans = humanPeers(r);
  const botSlots = new Set((r.slots ?? []).filter((s) => s.is_bot).map((s) => num(s.slot)));
  const botMoves = seats.filter((e) => botSlots.has(num(e.s)));
  if (botSlots.size && botMoves.length === 0) probs.push(`${name}: no bot ever moved seats`);
  for (const e of botMoves) {
    const to = ENGINE_OF_CODE[num(e.to)];
    for (const peer of humans) if (seatAt(r, peer, e._t) === to) probs.push(`${name}: bot slot ${e.s} landed on ${to} at ${fmt(e._t)} s, peer ${peer}'s seat`);
  }
  for (const d of r.directives ?? []) {
    if ((d.kind !== 'replan' && d.kind !== 'split') || !humans.includes(String(d.peer))) continue;
    const slot = num(slotOf(r, d.peer).slot, -1);
    if (!seats.some((e) => num(e.s) === slot && e._t <= num(d.t) + EPS)) probs.push(`${name}: ${d.kind} ${d.id} to human peer ${d.peer} at ${fmt(num(d.t))} s with no seat move of its own before it`);
  }
  return probs;
}

export function checkS18(reports) {
  const title = 'ambush_15 on Hard with bots (1 human + 3 bots, 2 + 2): complete, nothing refused, bots act only through their seats';
  const { found, missing } = pick(reports, ['s18_bots_h1b3', 's18_bots_h2b2']);
  if (found.length === 0) return skip('S18', title, 'no s18_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const lines = [];
  for (const [name, r] of found) {
    probs.push(...matrixProblems(name, r), ...botSeatProblems(name, r));
    lines.push(`${name} ${r.finished_reason}, ${eventsOf(r, 'seat').length} seat moves, ${lossesOf(r)} losses`);
  }
  return result('S18', title, probs, lines.join('; '));
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

export const CHECKS = { S1: checkS1, S2: checkS2, S3: checkS3, S4: checkS4, S5: checkS5, S6: checkS6, S7: checkS7, S9: checkS9, S10: checkS10, S11: checkS11, S12: checkS12, S13: checkS13, S14: checkS14, S15: checkS15, S16: checkS16, S17: checkS17, S18: checkS18 };

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
