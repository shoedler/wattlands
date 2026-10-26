#!/usr/bin/env node
// tests/games/fishing/sim/check_sims.mjs: asserts Turbo Reel's simulation matrix over the reports
// tools/run_game_sim wrote (run_sims.sh names them).
//
//   node tests/games/fishing/sim/check_sims.mjs build/fishing/sims [--only=ALL,R1,W3] [--fit]
//
// One PASS / FAIL / SKIP line per scenario (details of a failure indented below it); exit 1 when
// any scenario failed, 2 on usage or I/O errors. A scenario without its reports is SKIP.
//
// Report names (run_sims.sh):
//   r1_roam30_solo            roam_30, 1 band-tracker, Autopilot
//   r2_roam30_four            roam_30, 4 band-trackers
//   r3_roam30_bots_seed<n>    roam_30, 1 band-tracker + 3 bots, seeds 1-5
//   r4_roam10_autopilot       roam_10, 1 rider at erg:compliance=1.0 (no band), Autopilot
//   r5_roam30_unverified      roam_30, 2 band-trackers, --ftp=300,200 --unverified --haptics-off=1
//   r6_roam30_paused          roam_30, 2 band-trackers, slot 1 stops pedaling at 900 s for 60 s
//   w1_threshold              threshold, 2 band-trackers
//   w2_base60                 base_60, 2 band-trackers
//   w3_e2e                    e2e_2min, 3 band-trackers
//   d_roam_a, d_roam_b        roam_10, 2 band-trackers + 2 bots, seed 7, twice
// FIT (--fit): tools/fit_check on every FIT with each rider's expected laps.
//
// Every run (ALL): completed; no plan warnings; every directive accepted (a surge's haptic pull
// may be refused); each request is a Fishing ERG pull/run/jump inside its phase's range_pct (or
// the Landing's haptic, or a surge's +50 % FTP 2 s haptic pull) and is applied
// clamped only by the allowed rules (never ceiling, long_phase, limit_105, limit_120); every trace
// row likewise; every course grade 0..3 % and only in a Free Roam SIM game phase; every ERG phase
// of the final plans obeys BRIEF 4.6.1 (longer than 300 s: <= 105 %); events valid; snapshots
// <= 2 KB; one FIT per human slot.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import {
  EPS,
  GRADE_MAX_PCT,
  MAX_SNAPSHOT_BYTES,
  SP,
  SPECIES,
  appliedProblems,
  clampProblems,
  eventErrors,
  expectedLaps,
  fishingEvents,
  fmt,
  gradeOf,
  isObj,
  isSurge,
  median,
  requestShapeProblems,
  sum,
} from './fishing_sim_lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const REPO = path.resolve(here, '..', '..', '..', '..');
export const DEFAULT_SEEDS = [1, 2, 3, 4, 5];
/** Bot strategy efforts (FishingAutopilot.STRATEGY_TABLE): the driving power band / FTP. */
export const STRATEGY_EFFORT = { vibe: 0.55, small: 0.75, mixed: 0.85, big: 1.0 };
export const W1 = { tuna: 4, fightMin: 240, fightMax: 420 };
export const W3 = { riders: 3, cooldownByS: 135 };
export const R5 = { ftp: [300, 200], factor: 0.85, tolW: 1.5, hapticsOffPeer: 2 };
export const R6 = { peer: 2, at: 900, forS: 60 };
export const TOL_S = 0.051;
const ROAM_LABELS = new Set(['FISHING_PHASE_DRIVE_OUT', 'FISHING_PHASE_ROAM']);

// --- reading reports ---------------------------------------------------------------------------

/** {name: report} for every *.json directly in `dir` that is a Fishing run_game_sim report. */
export function loadReports(dir) {
  const out = {};
  for (const f of fs.readdirSync(dir).sort()) {
    if (!f.endsWith('.json')) continue;
    let r;
    try {
      r = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    } catch {
      continue;
    }
    if (isObj(r) && r.game_id === 'fishing' && r.schema === 1) out[f.slice(0, -5)] = r;
  }
  return out;
}

/** [{lane, peer, ftp, bot}] in slot order. */
export function lanes(r) {
  return (r.slots ?? []).map((s) => ({ lane: s.slot, peer: String(s.peer), ftp: Number(s.ftp), bot: s.is_bot === true }));
}

export const eventsOf = (r, type, lane = -1) => fishingEvents(r.events).filter((e) => e.type === type && (lane < 0 || e.l === lane));

/** The phase span of `peer` running at game time t (null when none). */
export function spanAt(r, peer, t) {
  for (const s of r.phases?.[peer] ?? []) if (t + EPS >= s.start && (s.end < 0 || t < s.end - EPS)) return s;
  return null;
}

export function cooldownStart(r, peer) {
  const s = (r.phases?.[peer] ?? []).find((x) => x.kind === 'COOLDOWN');
  return s ? s.start : NaN;
}

const result = (id, title, probs, info = '') => ({ id, title, ok: probs.length === 0, skip: false, probs, info });
const skip = (id, title, why) => ({ id, title, ok: true, skip: true, probs: [], info: why });

// --- ALL ------------------------------------------------------------------------------------------

export function runProblems(name, r) {
  const probs = [];
  if (r.end_reason !== 'complete') probs.push(`${name}: end_reason ${r.end_reason}`);
  for (const [peer, w] of Object.entries(r.plan_warnings ?? {})) if (w.length) probs.push(`${name}: plan warnings for ${peer}: ${w.join('; ')}`);
  const plans = r.plans ?? {};
  for (const [peer, plan] of Object.entries(plans)) {
    for (const [i, ph] of (plan.phases ?? []).entries()) {
      if (ph.mode !== 'ERG' || ph.kind === 'COOLDOWN') continue;
      const top = Math.max(ph.target_pct ?? 0, ...(ph.range_pct ?? []));
      const len = ph.open_ended ? ph.max_s : ph.duration_s;
      if (len > 300 + EPS && top > 105 + EPS) probs.push(`${name}: ${peer} phase ${i} ${ph.label}: ${fmt(top)} % in a ${fmt(len)} s phase`);
      if (top > 110 + EPS) probs.push(`${name}: ${peer} phase ${i} above 110 %`);
    }
  }
  for (const d of r.directives ?? []) {
    const at = `${name}: ${d.kind} #${d.id} peer ${d.peer} t ${fmt(d.t)}`;
    // A surge's haptic pull is a feel the governor may refuse (a governor without the haptic
    // pull channel, the 15 s haptic spacing): its shape is checked, its outcome is not.
    const surge = d.kind === 'request' && isSurge(d.requested);
    if (d.accepted !== true && !surge) probs.push(`${at}: refused (${d.reason})`);
    if (d.kind === 'request') {
      for (const p of requestShapeProblems(d.requested)) probs.push(`${at}: ${p}`);
      if (!surge || d.accepted === true) for (const p of appliedProblems(d.applied)) probs.push(`${at}: ${p}`);
      const req = d.requested ?? {};
      if (req.mode === 'ERG' && isObj(d.applied)) {
        const ph = plans[String(d.peer)]?.phases?.[d.applied.phase_index];
        const range = ph?.range_pct ?? [ph?.target_pct, ph?.target_pct];
        if (!ph || req.target_pct < range[0] - EPS || req.target_pct > range[1] + EPS) probs.push(`${at}: target ${fmt(req.target_pct)} outside phase ${d.applied.phase_index} ${JSON.stringify(range)}`);
      }
    } else if (d.kind === 'course_grade') {
      const g = gradeOf(d);
      if (!(g >= -EPS && g <= GRADE_MAX_PCT + EPS)) probs.push(`${at}: grade ${g}`);
      const span = spanAt(r, String(d.peer), d.t);
      if (!span || span.mode !== 'SIM' || !ROAM_LABELS.has(span.label)) probs.push(`${at}: a course grade outside a Free Roam SIM phase (${span?.label})`);
    }
  }
  // A remote rider acks its course grades with id 0 (the platform routes them without a governor
  // request id), so only other unmatched records count.
  const unmatched = (r.directives_unmatched ?? []).filter((x) => x.kind !== 'course_grade');
  if (unmatched.length) probs.push(`${name}: ${unmatched.length} unmatched applied records`);
  for (const [peer, rows] of Object.entries(r.trace ?? {})) {
    for (const row of rows) for (const p of clampProblems(row.clamped_by)) probs.push(`${name}: trace ${peer} t ${fmt(row.t)}: ${p}`);
  }
  for (const e of fishingEvents(r.events)) for (const p of eventErrors(e)) probs.push(`${name}: event at ${fmt(e._t)}: ${p}`);
  if ((r.max_snapshot_bytes ?? 0) > MAX_SNAPSHOT_BYTES) probs.push(`${name}: a snapshot of ${r.max_snapshot_bytes} bytes`);
  const humans = lanes(r).filter((l) => !l.bot).length;
  if ((r.fit_paths ?? []).length !== humans) probs.push(`${name}: ${(r.fit_paths ?? []).length} FITs for ${humans} humans`);
  return probs.slice(0, 40);
}

export function checkAll(reports) {
  const title = 'every run: completed, valid plans and replans, directives, grades, clamps, events, snapshots, FITs';
  const names = Object.keys(reports);
  if (!names.length) return skip('ALL', title, 'no reports');
  const probs = names.flatMap((n) => runProblems(n, reports[n]));
  return result('ALL', title, probs, `${names.length} runs`);
}

// --- scenarios ---------------------------------------------------------------------------------

export function landedBy(r) {
  const out = {};
  for (const { lane } of lanes(r)) out[lane] = eventsOf(r, 'landed', lane);
  return out;
}

export function roamBasics(name, r, content) {
  const probs = [];
  if (r.content_id !== content) probs.push(`${name}: content ${r.content_id}, wanted ${content}`);
  if (r.finished_reason !== 'trip_over') probs.push(`${name}: finished ${JSON.stringify(r.finished_reason)}`);
  if (eventsOf(r, 'time_up').length !== 1) probs.push(`${name}: time_up ${eventsOf(r, 'time_up').length} times`);
  const replans = (r.directives ?? []).filter((d) => d.kind === 'replan');
  const bites = eventsOf(r, 'bite').length;
  if (replans.length !== bites) probs.push(`${name}: ${replans.length} replans for ${bites} bites`);
  return probs;
}

export function checkR1(reports) {
  const title = 'roam_30 solo Autopilot band-tracker: drives out, casts, hooks, lands fish, time-up, trip over';
  const name = 'r1_roam30_solo';
  const r = reports[name];
  if (!r) return skip('R1', title, `no ${name} report`);
  const probs = roamBasics(name, r, 'roam_30');
  const landed = landedBy(r)[0] ?? [];
  if (landed.length < 2) probs.push(`${name}: ${landed.length} fish landed (>= 2)`);
  if (eventsOf(r, 'cast').length < landed.length) probs.push(`${name}: fewer casts than catches`);
  const firstBite = eventsOf(r, 'bite')[0]?._t ?? NaN;
  if (!(firstBite >= 300 - TOL_S)) probs.push(`${name}: a bite at ${fmt(firstBite)} s, in the drive-out`);
  return result('R1', title, probs, `${landed.length} fish, ${sum(landed.map((e) => e.points))} points`);
}

export function checkR2(reports) {
  const title = 'roam_30, 4 riders on one ocean: everyone fishes, snapshots stay small';
  const name = 'r2_roam30_four';
  const r = reports[name];
  if (!r) return skip('R2', title, `no ${name} report`);
  const probs = roamBasics(name, r, 'roam_30');
  const by = landedBy(r);
  for (const [lane, l] of Object.entries(by)) if (l.length < 1) probs.push(`${name}: rider ${lane} landed nothing`);
  if (lanes(r).length !== 4) probs.push(`${name}: ${lanes(r).length} riders`);
  return result('R2', title, probs, `fish ${Object.values(by).map((l) => l.length).join('/')}, max snapshot ${r.max_snapshot_bytes} B`);
}

/** Each bot's strategy, from the highest power band it rode while driving (W / FTP). */
export function botStrategies(r) {
  const out = {};
  for (const { lane, peer, ftp, bot } of lanes(r)) {
    if (!bot) continue;
    const bands = (r.events ?? []).filter((e) => e.type === 'hud' && e.kind === 'power_band' && String(e.peer) === peer);
    const efforts = bands.map((e) => (e.lo_w + e.hi_w) / 2 / ftp).filter((x) => x < 1.2);
    const top = efforts.length ? Math.max(...efforts) : NaN;
    let best = '';
    for (const [id, eff] of Object.entries(STRATEGY_EFFORT)) if (Math.abs(top - eff) < 0.02) best = id;
    out[lane] = best;
  }
  return out;
}

export function checkR3(reports, seeds = DEFAULT_SEEDS) {
  const title = 'roam_30 with 3 bots: every bot fishes, all four strategies show up, both small and big pay';
  const names = seeds.map((s) => `r3_roam30_bots_seed${s}`).filter((n) => reports[n]);
  if (!names.length) return skip('R3', title, 'no r3 reports');
  const probs = [];
  const seen = {};
  for (const name of names) {
    const r = reports[name];
    probs.push(...roamBasics(name, r, 'roam_30'));
    const by = landedBy(r);
    const strat = botStrategies(r);
    for (const [lane, id] of Object.entries(strat)) {
      if (!id) probs.push(`${name}: bot ${lane} rode no strategy's power band`);
      const pts = sum((by[lane] ?? []).map((e) => e.points));
      if ((by[lane] ?? []).length < 1) probs.push(`${name}: bot ${lane} (${id}) landed nothing`);
      (seen[id] ??= []).push(pts);
    }
  }
  if (names.length >= 4) for (const id of Object.keys(STRATEGY_EFFORT)) if (!seen[id]) probs.push(`no bot played ${id} in ${names.length} seeds`);
  const med = Object.fromEntries(Object.entries(seen).map(([k, v]) => [k, median(v)]));
  if (med.small > 0 && med.big > 0) {
    const ratio = Math.max(med.small, med.big) / Math.min(med.small, med.big);
    if (ratio > 2.5) probs.push(`small (${med.small}) and big (${med.big}) are not both viable (ratio ${fmt(ratio)})`);
  }
  const info = Object.entries(med).map(([k, v]) => `${k} ${fmt(v)}`).join(', ');
  return result('R3', title, probs, `median points: ${info}`);
}

export function checkR4(reports) {
  const title = 'roam_10 Autopilot without a band (zero input): the session plays through';
  const name = 'r4_roam10_autopilot';
  const r = reports[name];
  if (!r) return skip('R4', title, `no ${name} report`);
  const probs = roamBasics(name, r, 'roam_10');
  const landed = landedBy(r)[0] ?? [];
  if (landed.length < 1) probs.push(`${name}: landed nothing`);
  return result('R4', title, probs, `${landed.length} fish`);
}

export function checkR5(reports) {
  const title = 'roam_30 unverified FTPs (x0.85) at 300 and 200 W, no haptic to the opted-out rider';
  const name = 'r5_roam30_unverified';
  const r = reports[name];
  if (!r) return skip('R5', title, `no ${name} report`);
  const probs = roamBasics(name, r, 'roam_30');
  let n = 0;
  for (const d of r.directives ?? []) {
    if (d.kind !== 'request') continue;
    const req = d.requested ?? {};
    if ((req.mode === 'SIM' || isSurge(req)) && String(d.peer) === String(R5.hapticsOffPeer)) probs.push(`${name}: a haptic for the opted-out rider at ${fmt(d.t)}`);
    if (req.mode !== 'ERG' || !isObj(d.applied)) continue;
    const clamps = d.applied.clamped_by ?? [];
    if (!clamps.includes('unverified')) probs.push(`${name}: #${d.id} has no unverified clamp`);
    const ftp = R5.ftp[Number(d.peer) - 1];
    const want = Math.floor((req.target_pct / 100) * ftp * R5.factor);
    const got = Number(d.applied.applied?.target_w ?? NaN);
    if (clamps.length === 1 && Math.abs(got - want) > R5.tolW) probs.push(`${name}: #${d.id} applied ${got} W for ${fmt(req.target_pct)} % of ${ftp} W (want ${want})`);
    n += 1;
  }
  if (n === 0) probs.push(`${name}: no ERG request`);
  return result('R5', title, probs.slice(0, 20), `${n} ERG requests`);
}

export function checkR6(reports) {
  const title = 'roam_30, a rider stops pedaling for 60 s: staggered (paused or AFK), no load sent meanwhile, fishes again';
  const name = 'r6_roam30_paused';
  const r = reports[name];
  if (!r) return skip('R6', title, `no ${name} report`);
  const probs = roamBasics(name, r, 'roam_30');
  const peer = String(R6.peer);
  const rows = (r.trace?.[peer] ?? []).filter((x) => x.game_t >= R6.at && x.game_t <= R6.at + R6.forS + 5);
  const out = rows.filter((x) => x.paused || x.afk);
  if (!out.length) probs.push(`${name}: rider ${peer} never paused or AFK`);
  else {
    const t0 = Math.min(...out.map((x) => x.game_t));
    const t1 = Math.max(...out.map((x) => x.game_t));
    const sent = (r.directives ?? []).filter((d) => d.kind === 'request' && String(d.peer) === peer && d.requested?.mode === 'ERG' && d.t > t0 + 1 && d.t < t1);
    if (sent.length) probs.push(`${name}: ${sent.length} ERG requests to the stopped rider between ${fmt(t0)} and ${fmt(t1)} s`);
  }
  const landed = landedBy(r)[1] ?? [];
  if (landed.length < 1) probs.push(`${name}: rider ${peer} landed nothing`);
  return result('R6', title, probs, `${out.length} stopped trace rows, rider 2 landed ${landed.length}`);
}

export function checkW1(reports) {
  const title = 'threshold, 2 riders: 4 tuna each, every fight 240-420 s';
  const name = 'w1_threshold';
  const r = reports[name];
  if (!r) return skip('W1', title, `no ${name} report`);
  const probs = [];
  for (const { lane, peer } of lanes(r)) {
    const tuna = eventsOf(r, 'landed', lane).filter((e) => e.sp === SP.tuna);
    if (tuna.length !== W1.tuna) probs.push(`${name}: rider ${lane} landed ${tuna.length} tuna`);
    for (const s of (r.phases?.[peer] ?? []).filter((x) => x.mode === 'ERG' && x.kind === 'WORK')) {
      const len = s.end - s.start;
      if (len < W1.fightMin - TOL_S || len > W1.fightMax + TOL_S) probs.push(`${name}: rider ${lane} fight of ${fmt(len)} s`);
    }
  }
  return result('W1', title, probs);
}

export function checkW2(reports) {
  const title = "base_60, 2 riders: the plan's fish bite and land, trip over";
  const name = 'w2_base60';
  const r = reports[name];
  if (!r) return skip('W2', title, `no ${name} report`);
  const probs = [];
  if (r.finished_reason !== 'trip_over') probs.push(`${name}: finished ${JSON.stringify(r.finished_reason)}`);
  for (const [lane, l] of Object.entries(landedBy(r))) if (l.length < 2) probs.push(`${name}: rider ${lane} landed ${l.length}`);
  for (const e of eventsOf(r, 'landed')) if (![SP.mackerel, SP.mahi].includes(e.sp)) probs.push(`${name}: a ${SPECIES[e.sp]} in base_60`);
  return result('W2', title, probs);
}

export function checkW3(reports) {
  const title = 'e2e_2min, 3 riders: one mackerel each, the cool-down by 135 s';
  const name = 'w3_e2e';
  const r = reports[name];
  if (!r) return skip('W3', title, `no ${name} report`);
  const probs = [];
  for (const { lane, peer } of lanes(r)) {
    const landed = eventsOf(r, 'landed', lane);
    if (landed.length !== 1 || landed[0].sp !== SP.mackerel) probs.push(`${name}: rider ${lane} landed ${landed.map((e) => SPECIES[e.sp]).join(', ') || 'nothing'}`);
    const cd = cooldownStart(r, peer);
    if (!(cd <= W3.cooldownByS + TOL_S)) probs.push(`${name}: rider ${lane} reached the cool-down at ${fmt(cd)} s`);
  }
  return result('W3', title, probs);
}

export function checkD(reports) {
  const title = 'the same roam run twice gives the same report hash';
  const a = reports.d_roam_a;
  const b = reports.d_roam_b;
  if (!a || !b) return skip('D', title, 'no d_roam_a/b reports');
  const probs = [];
  if (!a.deterministic_hash || a.deterministic_hash !== b.deterministic_hash) probs.push(`hashes differ: ${a.deterministic_hash} vs ${b.deterministic_hash}`);
  return result('D', title, probs);
}

/** tools/fit_check on every FIT with each rider's expected laps (`runner(args) -> {status, stdout}`). */
export function checkFit(reports, runner = defaultFitRunner) {
  const title = 'FIT: every file passes fit_check with one lap per lap phase that ran, plus the cool-down';
  const probs = [];
  let n = 0;
  for (const [name, r] of Object.entries(reports)) {
    const humans = lanes(r).filter((l) => !l.bot);
    (r.fit_paths ?? []).forEach((f, i) => {
      const peer = humans[i]?.peer ?? String(i + 1);
      const laps = expectedLaps(r, peer);
      n += 1;
      const res = runner([f, `--expect-laps=${laps}`, '--json']);
      if (res.status !== 0) probs.push(`${name}: fit_check exit ${res.status} for ${path.basename(f)} (expected ${laps} laps): ${res.stdout.slice(0, 200)}`);
    });
  }
  if (n === 0) return skip('FIT', title, 'no FIT files in the reports');
  return result('FIT', title, probs, `${n} files`);
}

function defaultFitRunner(args) {
  const r = spawnSync(process.execPath, [path.join(REPO, 'tools', 'fit_check', 'check.mjs'), ...args], { encoding: 'utf8', cwd: REPO });
  return { status: r.status ?? 1, stdout: r.stdout ?? '' };
}

export const CHECKS = { ALL: checkAll, R1: checkR1, R2: checkR2, R3: checkR3, R4: checkR4, R5: checkR5, R6: checkR6, W1: checkW1, W2: checkW2, W3: checkW3, D: checkD };

export function main(argv, out = process.stdout, err = process.stderr) {
  const dir = argv.find((a) => !a.startsWith('--'));
  if (!dir) {
    err.write('usage: check_sims.mjs <report dir> [--only=ALL,R1] [--fit] [--seeds=1,2,3]\n');
    return 2;
  }
  let reports;
  try {
    reports = loadReports(dir);
  } catch (e) {
    err.write(`check_sims: ${e.message}\n`);
    return 2;
  }
  const only = argv.find((a) => a.startsWith('--only='))?.slice(7).split(',');
  const seedsArg = argv.find((a) => a.startsWith('--seeds='));
  const seeds = seedsArg ? seedsArg.slice(8).split(',').map(Number) : DEFAULT_SEEDS;
  const results = [];
  for (const [id, fn] of Object.entries(CHECKS)) if (!only || only.includes(id) || id === 'ALL') results.push(id === 'R3' ? fn(reports, seeds) : fn(reports));
  if (argv.includes('--fit')) results.push(checkFit(reports));
  let failed = 0;
  for (const res of results) {
    const tag = res.skip ? 'SKIP' : res.ok ? 'PASS' : 'FAIL';
    if (!res.ok) failed += 1;
    out.write(`${tag} ${res.id.padEnd(4)} ${res.title}${res.info ? ` (${res.info})` : ''}\n`);
    for (const p of res.probs.slice(0, 15)) out.write(`       ${p}\n`);
  }
  return failed ? 1 : 0;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(self)) process.exit(main(process.argv.slice(2)));
