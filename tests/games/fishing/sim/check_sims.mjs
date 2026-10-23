#!/usr/bin/env node
// tests/games/fishing/sim/check_sims.mjs: asserts brief section 4.2's simulation matrix over the
// reports tools/run_game_sim wrote (run_sims.sh names them).
//
//   node tests/games/fishing/sim/check_sims.mjs build/fishing/sims [--only=S1,S10] [--fit] [--seeds=1,2,3]
//
// One PASS / FAIL / SKIP line per scenario (details of a failure indented below it); exit 1 when
// any scenario failed, 2 on usage or I/O errors. A scenario whose reports are all missing is SKIP
// (a subset run); one with some but not all of them is FAIL. ALL (every run) always runs.
//
// Report names:
//   s1_threshold               2 band-trackers
//   s2_low, s2_high            threshold, 1 rider at erg+band:offset_rpm=-18 / +18
//   s3_free30_seed<n>          4 band-trackers, seeds 1-5 (--full: 1-20)
//   s4_ap_none, s4_ap_all      free_30 solo, erg:compliance=1.0, --autopilot=none / all
//   s5_base60                  2 band-trackers
//   s6_free120_marlin          1 band-tracker on the seed fishing_marlin_seed.gd found
//   s7_threshold_drop          1 rider, erg+band+cadence_drop:rpm=40,at_s=600,for_s=20
//   s8_<x>_a, s8_<x>_b         the same run twice (x: free30 in the full matrix, e2e in --quick)
//   s10_e2e                    e2e_2min, 3 band-trackers
// Scenario 9 (FIT) runs tools/fit_check on every FIT of every report with --fit.
//
// Every run (ALL): the run completed; the plans carry no validator warnings; each request is
// {mode ERG, target_pct, duration_s, reason pull|run|jump, source fishing} (or the Landing's
// haptic), accepted, and its ERG target lies inside the range_pct of the rider's phase; each
// applied record and each 1 Hz trace row is clamped only by the allowed rules (fishing_sim_lib
// ALLOWED_CLAMPS; never ceiling, long_phase, limit_105 or limit_120); no applied record is left
// unmatched; snapshots stay <= 2 KB; one FIT per human slot. Fight phases are the plan's WORK ERG
// phases whose meta names a species.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import {
  EPS,
  MAX_SNAPSHOT_BYTES,
  S1_CLAMPS,
  SP,
  SPECIES,
  appliedProblems,
  clampProblems,
  eventErrors,
  expectedLaps,
  fishingEvents,
  fmt,
  isObj,
  median,
  requestShapeProblems,
  sum,
} from './fishing_sim_lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const REPO = path.resolve(here, '..', '..', '..', '..');
export const DEFAULT_SEEDS = [1, 2, 3, 4, 5];
/** Fishing time per Free/Base trip (content/fishing/trips/<id>.json fishing_s), the fallback when
 *  the file can't be read. */
export const FISHING_S = { free_20: 720, free_30: 1320, free_45: 2220, free_60: 3120, free_90: 4920, free_120: 6720, base_60: 3120 };
export const FIGHT_CAP = { free: 0.4, base: 0.25 };
export const S1 = { tuna: 4, fightMin: 240, fightMax: 420 };
export const S2_WINDOW_S = 8;
export const S3 = { endMaxS: 35 * 60, medianFish: 2, doubleHookups: 1 };
export const S6 = { jumpsMin: 4, jumpsMax: 8, jumpMsMin: 20000, jumpMsMax: 30000, jumpPct: 104, capPct: 105 };
export const S7 = { at: 600, forS: 20, rescueBy: 625, calmAfterS: 10 };
export const S10 = { lanes: 3, cooldownByS: 135 };
export const TOL_S = 0.051;

// --- reading reports ---------------------------------------------------------------------------

/** {name: report} for every *.json directly in `dir` that is a Fishing run_game_sim report. */
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
    if (isObj(r) && r.schema === 1 && r.game_id === 'fishing') out[f.slice(0, -5)] = r;
  }
  return out;
}

/** fishing_s of a trip: its content file, else FISHING_S. */
export function fishingSeconds(contentId) {
  try {
    const t = JSON.parse(fs.readFileSync(path.join(REPO, 'content', 'fishing', 'trips', `${contentId}.json`), 'utf8'));
    if (Number(t.fishing_s) > 0) return Number(t.fishing_s);
  } catch {
    // fall through to the table
  }
  return FISHING_S[contentId] ?? NaN;
}

export const gameEvents = (r) => fishingEvents(r.events);
export const eventsOf = (r, type, lane = null) => gameEvents(r).filter((e) => e.type === type && (lane === null || e.l === lane));

/** [{lane, peer}] of the human slots in slot order (the lane is the slot index). */
export function lanes(r) {
  return (r.slots ?? []).filter((s) => !s.is_bot).map((s) => ({ lane: Number(s.slot), peer: String(s.peer) }));
}

/** One rider's phases joined with the plan: [{index, kind, mode, label, start, end, ended_by, plan}]. */
export function riderPhases(r, peer) {
  const plan = r.plans?.[String(peer)]?.phases ?? [];
  return (r.phases?.[String(peer)] ?? []).map((s) => ({ ...s, plan: plan[s.index] ?? {} }));
}

export const isFight = (p) => p.kind === 'WORK' && p.mode === 'ERG' && typeof p.plan?.meta?.species === 'string';
export const fights = (r, peer) => riderPhases(r, peer).filter(isFight);
const spanEnd = (p, r) => (p.end >= 0 ? Number(p.end) : Number(r.game_seconds ?? Infinity));
export const fightSeconds = (r, peer) => sum(fights(r, peer).map((p) => spanEnd(p, r) - Number(p.start)));

/** The rider's phase at game time t (the last one started at or before t). */
export function phaseAt(r, peer, t) {
  let at = null;
  for (const p of riderPhases(r, peer)) if (Number(p.start) <= t + EPS) at = p;
  return at;
}

export function cooldownStart(r, peer) {
  const cd = riderPhases(r, peer).find((p) => p.kind === 'COOLDOWN');
  return cd ? Number(cd.start) : NaN;
}

// --- result helpers ------------------------------------------------------------------------------

function result(id, title, problems, extra = '') {
  return { id, status: problems.length === 0 ? 'PASS' : 'FAIL', summary: `${title}${extra ? `: ${extra}` : ''}`, details: problems };
}
const skip = (id, title, why) => ({ id, status: 'SKIP', summary: `${title}: ${why}`, details: [] });

function pick(reports, names) {
  const found = [];
  const missing = [];
  for (const n of names) (reports[n] ? found : missing).push(n);
  return { found: found.map((n) => [n, reports[n]]), missing };
}

function argsProblems(name, r, want) {
  const probs = [];
  const a = r.args ?? {};
  if (want.content && r.content_id !== want.content) probs.push(`${name}: content ${r.content_id}, wanted ${want.content}`);
  if (want.players !== undefined && Number(a.players) !== want.players) probs.push(`${name}: players ${a.players}, wanted ${want.players}`);
  if (want.seed !== undefined && Number(r.seed) !== want.seed) probs.push(`${name}: seed ${r.seed}, wanted ${want.seed}`);
  return probs;
}

const completeProblems = (name, r) => (r.end_reason === 'complete' ? [] : [`${name}: end_reason ${r.end_reason}`]);

// --- ALL: every run ------------------------------------------------------------------------------

/** Problems with one directive entry (brief 2.3, 2.7, 6). `allowed` narrows the clamp rules. */
export function directiveProblems(name, r, d, allowed = undefined) {
  if (d.kind !== 'request') return [];
  const at = `${name}: directive ${d.id} (peer ${d.peer}, t ${fmt(Number(d.t))})`;
  const probs = requestShapeProblems(d.requested).map((p) => `${at}: ${p}`);
  if (d.accepted !== true) probs.push(`${at}: not accepted (${d.reason})`);
  probs.push(...appliedProblems(d.applied, allowed).map((p) => `${at}: ${p}`));
  const req = d.requested ?? {};
  if (req.mode === 'ERG' && typeof req.target_pct === 'number') {
    const idx = isObj(d.applied) && Number.isInteger(d.applied.phase_index) ? d.applied.phase_index : phaseAt(r, d.peer, Number(d.t))?.index;
    const ph = r.plans?.[String(d.peer)]?.phases?.[idx];
    const range = ph?.range_pct;
    if (!Array.isArray(range) || range.length !== 2) probs.push(`${at}: ERG ${req.target_pct}% in phase ${idx} (${ph?.label}), which has no range_pct`);
    else if (req.target_pct < range[0] - EPS || req.target_pct > range[1] + EPS) probs.push(`${at}: ERG ${req.target_pct}% outside phase ${idx}'s range_pct [${range.join(', ')}]`);
  }
  return probs;
}

/** Problems of one run that every scenario shares. */
export function runProblems(name, r) {
  const probs = [...completeProblems(name, r)];
  for (const [peer, w] of Object.entries(r.plan_warnings ?? {})) if (Array.isArray(w) && w.length) probs.push(`${name}: peer ${peer} plan warnings ${JSON.stringify(w)}`);
  for (const d of r.directives ?? []) probs.push(...directiveProblems(name, r, d));
  if ((r.directives_unmatched ?? []).length) probs.push(`${name}: ${r.directives_unmatched.length} applied records match no request`);
  for (const [peer, rows] of Object.entries(r.trace ?? {})) {
    let n = 0;
    for (const row of rows) {
      const p = clampProblems(row.clamped_by);
      if (p.length && n < 3) probs.push(`${name}: peer ${peer} at ${fmt(Number(row.game_t ?? row.t))} s: ${p.join('; ')}`);
      if (p.length) n += 1;
    }
    if (n > 3) probs.push(`${name}: peer ${peer}: ${n} trace rows with clamps that are not allowed`);
  }
  const seen = new Set();
  for (const e of gameEvents(r)) {
    for (const m of eventErrors(e)) {
      if (!seen.has(m)) probs.push(`${name}: event ${m}`);
      seen.add(m);
    }
  }
  if (Number(r.max_snapshot_bytes ?? 0) > MAX_SNAPSHOT_BYTES) probs.push(`${name}: largest snapshot ${r.max_snapshot_bytes} B (limit ${MAX_SNAPSHOT_BYTES})`);
  const humans = lanes(r).length;
  if (!Array.isArray(r.fit_paths) || r.fit_paths.length !== humans) probs.push(`${name}: fit_paths ${JSON.stringify(r.fit_paths)} (one per human slot)`);
  return probs;
}

export function checkAllRuns(reports) {
  const title = 'every run: complete, directives exact and in range, clamps allowed, events well formed, snapshots <= 2 KB';
  const names = Object.keys(reports);
  if (names.length === 0) return skip('ALL', title, 'no reports');
  const probs = [];
  let requests = 0;
  const noted = new Set();
  for (const n of names) {
    probs.push(...runProblems(n, reports[n]));
    for (const d of reports[n].directives ?? []) {
      if (d.kind !== 'request') continue;
      requests += 1;
      for (const c of d.applied?.clamped_by ?? []) if (c === 'switch_ramp' || c === 'paused') noted.add(c);
    }
  }
  const extra = `${names.length} runs, ${requests} requests${noted.size ? `, noted clamps: ${[...noted].join(', ')}` : ''}`;
  return result('ALL', title, probs, extra);
}

// --- S1: threshold, band-tracking riders -----------------------------------------------------------

export function checkS1(reports) {
  const title = 'threshold, band-trackers: 4 tuna landed per rider, fights 240-420 s, no snaps, clamps only slew/floor/unverified/haptic';
  const name = 's1_threshold';
  const r = reports[name];
  if (!r) return skip('S1', title, `no ${name} report`);
  const probs = [...argsProblems(name, r, { content: 'threshold' }), ...completeProblems(name, r)];
  const parts = [];
  for (const { lane, peer } of lanes(r)) {
    const tuna = eventsOf(r, 'landed', lane).filter((e) => e.sp === SP.tuna).length;
    if (tuna !== S1.tuna) probs.push(`${name}: lane ${lane} landed ${tuna} tuna (wanted ${S1.tuna})`);
    const fs4 = fights(r, peer);
    if (fs4.length !== S1.tuna) probs.push(`${name}: lane ${lane} ran ${fs4.length} fights (wanted ${S1.tuna})`);
    for (const f of fs4) {
      const len = spanEnd(f, r) - Number(f.start);
      if (len < S1.fightMin - TOL_S || len > S1.fightMax + TOL_S) probs.push(`${name}: lane ${lane} ${f.label} lasted ${fmt(len)} s (${S1.fightMin}-${S1.fightMax})`);
    }
    const snaps = eventsOf(r, 'snap', lane).length;
    if (snaps) probs.push(`${name}: lane ${lane} snapped ${snaps} lines`);
    parts.push(`lane ${lane}: ${tuna} tuna, fights ${fs4.map((f) => fmt(spanEnd(f, r) - f.start)).join('/')} s`);
  }
  for (const d of r.directives ?? []) {
    if (d.kind !== 'request' || !isObj(d.applied)) continue;
    const bad = clampProblems(d.applied.clamped_by, S1_CLAMPS);
    if (bad.length) probs.push(`${name}: directive ${d.id}: ${bad.join('; ')}`);
  }
  return result('S1', title, probs, parts.join('; '));
}

// --- S2: off the band ----------------------------------------------------------------------------------

/** Losses of `type` within S2_WINDOW_S after each hookup of `lane`, and fights never shortened. */
export function offBandProblems(name, r, type) {
  const probs = [];
  const { lane, peer } = lanes(r)[0] ?? { lane: 0, peer: '1' };
  const hookups = eventsOf(r, 'hookup', lane);
  const losses = eventsOf(r, type, lane);
  if (hookups.length === 0) probs.push(`${name}: no hookup on lane ${lane}`);
  const delays = [];
  for (const h of hookups) {
    const loss = losses.find((e) => e._t > h._t - EPS && e._t <= h._t + S2_WINDOW_S + EPS);
    if (!loss) probs.push(`${name}: hookup at ${fmt(h._t)} s: no ${type} within ${S2_WINDOW_S} s`);
    else delays.push(loss._t - h._t);
  }
  const other = type === 'snap' ? 'thrown' : 'snap';
  if (eventsOf(r, other, lane).length) probs.push(`${name}: ${eventsOf(r, other, lane).length} ${other} events (wanted only ${type})`);
  for (const f of fights(r, peer)) {
    const len = spanEnd(f, r) - Number(f.start);
    const minS = Number(f.plan?.min_s ?? 0);
    if (len < minS - TOL_S) probs.push(`${name}: ${f.label} lasted ${fmt(len)} s, shorter than its min_s ${minS}`);
    if (f.ended_by === 'end_phase' && losses.some((e) => Math.abs(e._t - spanEnd(f, r)) < 1)) probs.push(`${name}: ${f.label} ended at a ${type}`);
  }
  return { probs, delays };
}

export function checkS2(reports) {
  const title = 'threshold off the band: 10 rpm low snaps, 10 rpm high throws, within 8 s; phases not shortened';
  const { found, missing } = pick(reports, ['s2_low', 's2_high']);
  if (found.length === 0) return skip('S2', title, 'no s2_low / s2_high reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const parts = [];
  for (const [name, r] of found) {
    probs.push(...argsProblems(name, r, { content: 'threshold' }), ...completeProblems(name, r));
    const type = name === 's2_low' ? 'snap' : 'thrown';
    const o = offBandProblems(name, r, type);
    probs.push(...o.probs);
    parts.push(`${name}: ${type} after ${o.delays.map(fmt).join('/') || '-'} s`);
  }
  return result('S2', title, probs, parts.join('; '));
}

// --- S3: free_30 x 4 band-trackers -----------------------------------------------------------------------

export function checkS3(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'free_30, 4 band-trackers: trip <= 35 min, fights <= 40%, median >= 2 fish, a Double Hookup';
  const { found, missing } = pick(reports, seeds.map((n) => `s3_free30_seed${n}`));
  if (found.length === 0) return skip('S3', title, 'no s3_free30_seed* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const fish = [];
  let doubles = 0;
  const cap = FIGHT_CAP.free * fishingSeconds('free_30');
  for (const [name, r] of found) {
    probs.push(...argsProblems(name, r, { content: 'free_30', players: 4, seed: Number(name.match(/seed(\d+)/)[1]) }));
    probs.push(...completeProblems(name, r));
    if (Number(r.game_seconds) > S3.endMaxS + TOL_S) probs.push(`${name}: the trip took ${fmt(r.game_seconds)} s (<= ${S3.endMaxS})`);
    for (const { lane, peer } of lanes(r)) {
      fish.push(eventsOf(r, 'landed', lane).length);
      const fsec = fightSeconds(r, peer);
      if (fsec > cap + TOL_S) probs.push(`${name}: lane ${lane} fought ${fmt(fsec)} s (40% of fishing is ${fmt(cap)})`);
    }
    doubles += eventsOf(r, 'double_hookup').length;
  }
  const med = median(fish);
  if (!(med >= S3.medianFish)) probs.push(`median ${fmt(med)} fish per rider (>= ${S3.medianFish})`);
  if (doubles < S3.doubleHookups) probs.push('no Double Hookup in any run');
  return result('S3', title, probs, `${found.length} runs, median ${fmt(med)} fish per rider, ${doubles} Double Hookups`);
}

// --- S4: free_30 solo with no input -------------------------------------------------------------------

export function checkS4(reports) {
  const title = 'free_30 solo with no input, Autopilot off and on: >= 1 fish landed in each run';
  const { found, missing } = pick(reports, ['s4_ap_none', 's4_ap_all']);
  if (found.length === 0) return skip('S4', title, 'no s4_ap_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const parts = [];
  for (const [name, r] of found) {
    probs.push(...argsProblems(name, r, { content: 'free_30', players: 1 }), ...completeProblems(name, r));
    const want = name === 's4_ap_all';
    if (r.slots?.[0]?.autopilot !== want) probs.push(`${name}: slot 0 autopilot ${r.slots?.[0]?.autopilot}, wanted ${want}`);
    const n = eventsOf(r, 'landed', 0).length;
    if (n < 1) probs.push(`${name}: no fish landed`);
    parts.push(`${name} ${n} fish`);
  }
  return result('S4', title, probs, parts.join(', '));
}

// --- S5: base_60 --------------------------------------------------------------------------------------

export function checkS5(reports) {
  const title = 'base_60: nothing above 100% applied or requested, fights <= 25%';
  const name = 's5_base60';
  const r = reports[name];
  if (!r) return skip('S5', title, `no ${name} report`);
  const probs = [...argsProblems(name, r, { content: 'base_60' }), ...completeProblems(name, r)];
  let top = 0;
  for (const [peer, rows] of Object.entries(r.trace ?? {})) {
    const slot = (r.slots ?? []).find((s) => String(s.peer) === peer);
    const oneW = 100 / Math.max(Number(slot?.ftp ?? 200), 1);
    const over = rows.filter((row) => row.mode === 'ERG' && Number(row.applied_pct) > 100 + oneW + EPS);
    for (const row of rows) if (row.mode === 'ERG') top = Math.max(top, Number(row.applied_pct));
    if (over.length) probs.push(`${name}: peer ${peer} applied ${fmt(Number(over[0].applied_pct))}% at ${fmt(Number(over[0].game_t ?? over[0].t))} s (${over.length} rows above 100%)`);
  }
  for (const d of r.directives ?? []) {
    if (d.kind === 'request' && d.requested?.mode === 'ERG' && Number(d.requested.target_pct) > 100 + EPS) probs.push(`${name}: directive ${d.id} requests ${d.requested.target_pct}%`);
  }
  const cap = FIGHT_CAP.base * fishingSeconds('base_60');
  const parts = [];
  for (const { lane, peer } of lanes(r)) {
    const fsec = fightSeconds(r, peer);
    if (fsec > cap + TOL_S) probs.push(`${name}: lane ${lane} fought ${fmt(fsec)} s (25% of fishing is ${fmt(cap)})`);
    parts.push(`lane ${lane} ${fmt(fsec)} s`);
  }
  return result('S5', title, probs, `top ${fmt(top)}%, fights ${parts.join(', ')}`);
}

// --- S6: free_120 marlin -----------------------------------------------------------------------------

export function checkS6(reports) {
  const title = 'free_120 marlin: 4-8 jumps of 20-30 s at 104%, 0 s above 105%';
  const name = 's6_free120_marlin';
  const r = reports[name];
  if (!r) return skip('S6', title, `no ${name} report (fishing_marlin_seed.gd found no seed?)`);
  const probs = [...argsProblems(name, r, { content: 'free_120' }), ...completeProblems(name, r)];
  const hook = eventsOf(r, 'hookup').find((e) => e.sp === SP.marlin);
  if (!hook) return result('S6', title, [...probs, `${name}: no marlin was hooked`]);
  const lane = hook.l;
  const peer = lanes(r).find((x) => x.lane === lane)?.peer ?? '1';
  const jumps = eventsOf(r, 'jump', lane);
  if (jumps.length < S6.jumpsMin || jumps.length > S6.jumpsMax) probs.push(`${name}: ${jumps.length} jumps (${S6.jumpsMin}-${S6.jumpsMax})`);
  for (const j of jumps) if (j.ms < S6.jumpMsMin || j.ms > S6.jumpMsMax) probs.push(`${name}: jump ${j.k} lasts ${j.ms} ms (20-30 s)`);
  const jd = (r.directives ?? []).filter((d) => d.kind === 'request' && String(d.peer) === peer && d.requested?.reason === 'jump');
  const peak = Math.max(0, ...jd.map((d) => Number(d.requested.target_pct)));
  if (jd.some((d) => Number(d.requested.target_pct) > S6.jumpPct + EPS)) probs.push(`${name}: a jump directive above ${S6.jumpPct}% (${fmt(peak)}%)`);
  if (jumps.length && Math.abs(peak - S6.jumpPct) > 0.5) probs.push(`${name}: jumps peak at ${fmt(peak)}%, wanted ${S6.jumpPct}%`);
  let above = 0;
  for (const [p, rows] of Object.entries(r.trace ?? {})) {
    const slot = (r.slots ?? []).find((s) => String(s.peer) === p);
    const oneW = 100 / Math.max(Number(slot?.ftp ?? 200), 1);
    above += rows.filter((row) => row.mode === 'ERG' && Number(row.applied_pct) > S6.capPct + oneW + EPS).length;
  }
  if (above) probs.push(`${name}: ${above} s applied above ${S6.capPct}%`);
  if (!eventsOf(r, 'landed', lane).some((e) => e.sp === SP.marlin)) probs.push(`${name}: the marlin was not landed`);
  return result('S6', title, probs, `seed ${r.seed}, lane ${lane}: ${jumps.length} jumps (${jumps.map((j) => fmt(j.ms / 1000)).join('/')} s), peak ${fmt(peak)}%, ${above} s above 105%`);
}

// --- S7: cadence collapse mid-tuna ----------------------------------------------------------------------

export function checkS7(reports) {
  const title = 'threshold, 40 rpm for 20 s from 600 s: rescue, a stagger with no snap, the fight resumes';
  const name = 's7_threshold_drop';
  const r = reports[name];
  if (!r) return skip('S7', title, `no ${name} report`);
  const probs = [...argsProblems(name, r, { content: 'threshold' }), ...completeProblems(name, r)];
  const { lane, peer } = lanes(r)[0] ?? { lane: 0, peer: '1' };
  const resc = (r.events ?? []).filter((e) => e.type === 'rescue' && String(e.peer) === peer);
  const on = resc.find((e) => e.active === true && Number(e.t) >= S7.at - EPS);
  if (!on) return result('S7', title, [...probs, `${name}: rescue never started after ${S7.at} s`]);
  const t0 = Number(on.t);
  const offEv = resc.find((e) => e.active === false && Number(e.t) > t0);
  const t1 = offEv ? Number(offEv.t) : NaN;
  if (t0 > S7.rescueBy + EPS) probs.push(`${name}: rescue started at ${fmt(t0)} s (by ${S7.rescueBy})`);
  if (!offEv) probs.push(`${name}: rescue never ended`);
  const fight = phaseAt(r, peer, t0);
  if (!fight || !isFight(fight)) probs.push(`${name}: the rescue at ${fmt(t0)} s fell in ${fight?.label ?? 'no phase'}, not a Fight`);
  const calmTo = (offEv ? t1 : t0) + S7.calmAfterS;
  const losses = gameEvents(r).filter((e) => (e.type === 'snap' || e.type === 'thrown') && e.l === lane && e._t >= t0 - 1 && e._t <= calmTo);
  if (losses.length) probs.push(`${name}: ${losses[0].type} at ${fmt(losses[0]._t)} s during the stagger`);
  if (fight && isFight(fight) && offEv) {
    if (spanEnd(fight, r) <= t1 + EPS) probs.push(`${name}: ${fight.label} ended at ${fmt(spanEnd(fight, r))} s, before the rescue was over`);
    const landed = eventsOf(r, 'landed', lane).find((e) => e._t > t1 && e._t <= spanEnd(fight, r) + 31);
    if (!landed) probs.push(`${name}: the fish of ${fight.label} was not landed after the rescue`);
  }
  return result('S7', title, probs, `rescue ${fmt(t0)}-${fmt(t1)} s in ${fight?.label ?? '?'}`);
}

// --- S8: determinism ----------------------------------------------------------------------------------

/** SHA-256 of the canonical JSON (sorted keys) of a run's events, phases, applied directives and results. */
export function runHash(r) {
  const canon = (v) => {
    if (Array.isArray(v)) return v.map(canon);
    if (isObj(v)) return Object.fromEntries(Object.keys(v).sort().map((k) => [k, canon(v[k])]));
    return v;
  };
  const body = { events: r.events ?? [], phases: r.phases ?? {}, applied: (r.directives ?? []).map((d) => d.applied ?? null), results: r.results ?? {} };
  return crypto.createHash('sha256').update(JSON.stringify(canon(body))).digest('hex');
}

export function checkS8(reports) {
  const title = 'the same seed and inputs twice: identical events, phases, applied directives, results and deterministic_hash';
  const pairs = new Set(Object.keys(reports).filter((n) => /^s8_.+_[ab]$/.test(n)).map((n) => n.slice(0, -2)));
  if (pairs.size === 0) return skip('S8', title, 'no s8_*_a / s8_*_b reports');
  const probs = [];
  const parts = [];
  for (const base of [...pairs].sort()) {
    const a = reports[`${base}_a`];
    const b = reports[`${base}_b`];
    if (!a || !b) {
      probs.push(`missing report ${base}_${a ? 'b' : 'a'}`);
      continue;
    }
    if (JSON.stringify(a.args?.riders) !== JSON.stringify(b.args?.riders) || a.seed !== b.seed || a.content_id !== b.content_id) probs.push(`${base}: the two runs differ in content, seed or riders`);
    if (a.deterministic_hash !== b.deterministic_hash) probs.push(`${base}: deterministic_hash differs`);
    const ha = runHash(a);
    if (ha !== runHash(b)) probs.push(`${base}: events, phases, applied directives or results differ`);
    if (gameEvents(a).length === 0) probs.push(`${base}: no Fishing game events to compare`);
    parts.push(`${base} ${gameEvents(a).length} game events, ${ha.slice(0, 12)}`);
  }
  return result('S8', title, probs, parts.join('; '));
}

// --- S9: FIT --------------------------------------------------------------------------------------------

/** tools/fit_check on every FIT with each rider's expected laps (`runner(args) -> {status, stdout}`). */
export function checkFit(reports, runner) {
  const title = 'FIT: every file passes fit_check with one lap per ride out, Reel and Fight that ran, plus the cool-down';
  const probs = [];
  let n = 0;
  for (const [name, r] of Object.entries(reports)) {
    const ls = lanes(r);
    (r.fit_paths ?? []).forEach((f, i) => {
      const peer = ls[i]?.peer ?? String(i + 1);
      const laps = expectedLaps(r, peer);
      n += 1;
      const res = runner([f, `--expect-laps=${laps}`, '--json']);
      let got = '?';
      try {
        const j = JSON.parse(res.stdout);
        got = (j.files ?? []).map((x) => (x.laps ?? []).length).join(',');
        for (const file of j.files ?? []) for (const e of file.errors ?? []) probs.push(`${name}: ${path.basename(f)}: ${e}`);
      } catch {
        // reported below
      }
      if (res.status !== 0) probs.push(`${name}: fit_check exit ${res.status} for ${path.basename(f)} (expected ${laps} laps, got ${got})`);
    });
  }
  if (n === 0) return skip('S9', title, 'no FIT files in the reports');
  return result('S9', title, probs, `${n} files`);
}

function defaultFitRunner(args) {
  const r = spawnSync(process.execPath, [path.join(REPO, 'tools', 'fit_check', 'check.mjs'), ...args], { encoding: 'utf8', cwd: REPO });
  return { status: r.status ?? 1, stdout: r.stdout ?? '' };
}

// --- S10: e2e_2min, 3 riders -------------------------------------------------------------------------------

export function checkS10(reports) {
  const title = 'e2e_2min, 3 riders: one mackerel landed per rider, the trip ends <= 135 s before the cool-down';
  const name = 's10_e2e';
  const r = reports[name];
  if (!r) return skip('S10', title, `no ${name} report`);
  const probs = [...argsProblems(name, r, { content: 'e2e_2min', players: S10.lanes }), ...completeProblems(name, r)];
  const parts = [];
  for (const { lane, peer } of lanes(r)) {
    const landed = eventsOf(r, 'landed', lane);
    const mack = landed.filter((e) => e.sp === SP.mackerel).length;
    if (mack !== 1 || landed.length !== 1) probs.push(`${name}: lane ${lane} landed ${landed.map((e) => SPECIES[e.sp]).join(', ') || 'nothing'} (wanted one mackerel)`);
    const cd = cooldownStart(r, peer);
    if (!(cd <= S10.cooldownByS + TOL_S)) probs.push(`${name}: lane ${lane} reached the cool-down at ${fmt(cd)} s (<= ${S10.cooldownByS})`);
    parts.push(`lane ${lane} ${mack} mackerel, cool-down at ${fmt(cd)} s`);
  }
  return result('S10', title, probs, parts.join('; '));
}

// --- driver -------------------------------------------------------------------------------------------------

export const SCENARIOS = [
  ['ALL', checkAllRuns],
  ['S1', checkS1],
  ['S2', checkS2],
  ['S3', checkS3],
  ['S4', checkS4],
  ['S5', checkS5],
  ['S6', checkS6],
  ['S7', checkS7],
  ['S8', checkS8],
  ['S10', checkS10],
];

/** Runs the scenarios (`only`: ids, or null for all; ALL always runs). */
export function checkAll(reports, only = null, opts = {}) {
  const out = [];
  for (const [id, fn] of SCENARIOS) {
    if (only && id !== 'ALL' && !only.includes(id)) continue;
    out.push(fn(reports, opts));
  }
  if (opts.fit && (!only || only.includes('S9'))) out.push(checkFit(reports, opts.fitRunner ?? defaultFitRunner));
  return out;
}

export function format(results) {
  const lines = [];
  for (const r of results) {
    lines.push(`${r.status} ${r.id}  ${r.summary}`);
    for (const d of r.details.slice(0, 40)) lines.push(`    - ${d}`);
    if (r.details.length > 40) lines.push(`    - ... ${r.details.length - 40} more`);
  }
  return lines.join('\n');
}

export function main(argv, out = process.stdout, err = process.stderr) {
  const args = argv.filter((a) => !a.startsWith('--'));
  const seedArg = argv.find((a) => a.startsWith('--seeds='));
  const seeds = seedArg ? seedArg.slice(8).split(',').map(Number).filter(Number.isInteger) : null;
  const only = argv.find((a) => a.startsWith('--only='))?.slice(7).split(',').map((s) => s.trim().toUpperCase()) ?? null;
  const dir = args[0];
  if (!dir) {
    err.write('usage: node tests/games/fishing/sim/check_sims.mjs <reports dir> [--only=S1,S10] [--fit] [--seeds=1,2]\n');
    return 2;
  }
  let reports;
  try {
    reports = loadReports(dir);
  } catch (e) {
    err.write(`check_sims: ${e.message}\n`);
    return 2;
  }
  if (Object.keys(reports).length === 0) {
    err.write(`check_sims: no Fishing reports in ${dir}\n`);
    return 2;
  }
  const results = checkAll(reports, only, { fit: argv.includes('--fit'), ...(seeds && seeds.length ? { seeds } : {}) });
  out.write(`${format(results)}\n`);
  const failed = results.filter((r) => r.status === 'FAIL').length;
  const passed = results.filter((r) => r.status === 'PASS').length;
  out.write(`check_sims: ${passed} passed, ${failed} failed, ${results.length - passed - failed} skipped (${Object.keys(reports).length} reports)\n`);
  return failed === 0 ? 0 : 1;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(self)) {
  process.exitCode = main(process.argv.slice(2));
}
