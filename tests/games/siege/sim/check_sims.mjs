#!/usr/bin/env node
// tests/games/siege/sim/check_sims.mjs: asserts brief section 4's simulation matrix (S1-S7, S9,
// S10; S8 is the rules-level GUT sim) over the reports tools/run_game_sim wrote.
//
//   node tests/games/siege/sim/check_sims.mjs build/siege/sims [--only=S3,S9] [--seeds=1,2,3] [--fit]
//
// One PASS / FAIL / SKIP line per scenario (details of a failure indented below it), exit 1 when
// any scenario failed, 2 on usage or I/O errors. A scenario whose reports are all missing is
// SKIP (a subset run); one that has some but not all is FAIL. Zero dependencies, so
// `node --test` in tests/games/siege runs its unit tests (check_sims.test.mjs) anywhere.
//
// Report names (written by run_sims.sh; the scenario is read from the name, the content,
// player counts and seed are cross-checked against the report's own `args`):
//   s9_<content>_seed<n>        4 compliant Autopilot riders, content short|vo2|sweetspot|endurance
//   s2_short_<1h|2h|1h3b>_seed<n>   1 human, 2 humans, 1 human + 3 bots
//   s3_<content>_zero           4 riders at 0 W (HOST)
//   s4_short_c<90|80>_seed<n>   4 riders at compliance 0.9 / 0.8 (100% is s9_short_seed<n>)
//   s5_drill, s10_vo2_offsets   offset 0 on the drill, and vo2 at offsets +5, -10, 0, +5
//   s6_sweetspot_cadence_drop   cadence collapse to 40 rpm at 20 min
//   s7_vo2_seed1                vo2 seed 1 again, compared with s9_vo2_seed1
//   s10_vo2, s10_endurance      4 surgers
//
// Definitions (the numbers are brief 2.4 and 4):
//   Breach        a game event of type "breach" (host event log).
//   score         report.results.score.
//   T1            mean score of seeds 1-3 is in 64..89 (S1 = s9 short; S2 per variant).
//   T3            leak rate = distinct enemy ids in `leak` events that fall inside a wave phase
//                 (role "wave", the warm-up excluded) / total wave minutes of that content
//                 (sum of the wave phases' duration_s / 60). A ram that batters emits one leak
//                 per HP; it counts once. Per content: the mean over its seeds. T3 holds when
//                 every content's rate is within +-30% of the mean of the four contents' rates
//                 (all rates 0 holds).
//   T4            rams stopped = `kill` events with et 4 whose enemy id never appears in a
//                 `leak` event (it died before reaching the gate); rams spawned = the roads
//                 listed by `push` events; pooled over all S9 runs, stopped / spawned >= 0.7.
//   Overdrive     the directive {mode SIM, duration_s 30, reason overdrive, source siege}.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const CONTENTS = ['short', 'vo2', 'sweetspot', 'endurance'];
/** The seeds of the matrix (run_sims.sh SIEGE_SEEDS; `--seeds=1,2,3`). */
export const DEFAULT_SEEDS = [1, 2, 3];
/** FIT laps: lap-true phases + the cool-down (GAME_SDK 13, ADR G0.2). */
export const EXPECTED_LAPS = { short: 8, vo2: 14, sweetspot: 6, endurance: 4, drill: 3 };
export const T1_RANGE = [64, 89];
export const T3_SPREAD = 0.3;
export const T4_MIN = 0.7;
export const ENEMY_RAM = 4;
export const OD_DIRECTIVE = { mode: 'SIM', duration_s: 30, reason: 'overdrive', source: 'siege' };
export const OD_SPAN_S = 30;
export const OD_SPAN_TOL_S = 2;
export const MIN_OVERDRIVES = 3;
export const SWITCH_SPACING_S = 30;
export const WARMUP_S = 300;
export const WARMUP_MAX_PCT = 65;
export const MAX_SNAPSHOT_BYTES = 8192;
const EPS = 1e-6;

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const sum = (a) => a.reduce((x, y) => x + y, 0);
const mean = (a) => (a.length ? sum(a) / a.length : 0);
const fmt = (n) => (Number.isFinite(n) ? String(Math.round(n * 100) / 100) : String(n));

// --- reading reports --------------------------------------------------------------------------------

/** {name: report} for every *.json directly in `dir` that looks like a run_game_sim report. */
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
    if (isObj(r) && r.schema === 1 && r.game_id === 'siege') out[f.slice(0, -5)] = r;
  }
  return out;
}

/** The host's Siege game events (the `event` of each game_event), in order, with the report time. */
export function gameEvents(report) {
  const out = [];
  for (const e of report.events ?? []) {
    if (e && e.type === 'game_event' && isObj(e.event)) out.push({ ...e.event, _t: Number(e.t) });
  }
  return out;
}

export const eventsOf = (report, type) => gameEvents(report).filter((e) => e.type === type);
export const breaches = (report) => eventsOf(report, 'breach').length;
export const scoreOf = (report) => Number(report.results?.score ?? NaN);

/** The slot peers of a report in slot order (as strings, the keys of trace and phases). */
export function peersOf(report) {
  return (report.slots ?? []).map((s) => String(s.peer));
}

/** The first human peer (the host's own rider). */
export function hostPeer(report) {
  const humans = (report.slots ?? []).filter((s) => !s.is_bot);
  return String((humans[0] ?? report.slots?.[0])?.peer ?? '1');
}

/** Wave phases of the host's plan: [{index, number, duration_s, start, end}] (role "wave" only). */
export function wavePhases(report) {
  const peer = hostPeer(report);
  const plan = report.plans?.[peer]?.phases ?? [];
  const spans = report.phases?.[peer] ?? [];
  const out = [];
  let start = 0;
  plan.forEach((ph, i) => {
    const dur = Number(ph.duration_s);
    if (ph.meta?.role === 'wave') {
      const sp = spans.find((s) => s.index === i);
      out.push({
        index: i,
        number: Number(ph.meta.number ?? 0),
        duration_s: dur,
        start: sp ? Number(sp.start) : start,
        end: sp && sp.end >= 0 ? Number(sp.end) : start + dur,
      });
    }
    start += dur;
  });
  return out;
}

const inWave = (waves, t) => waves.some((w) => t >= w.start - EPS && t < w.end + EPS);

/** The distinct enemy ids that leaked inside a wave phase, and the wave minutes. */
export function leakStats(report) {
  const waves = wavePhases(report);
  const ids = new Set();
  for (const e of eventsOf(report, 'leak')) {
    if (inWave(waves, e._t)) ids.add(e.id);
  }
  const minutes = sum(waves.map((w) => w.duration_s)) / 60;
  return { leaks: ids.size, minutes, rate: minutes > 0 ? ids.size / minutes : 0 };
}

/** {spawned, stopped}: rams pushed (roads in `push` events) and rams killed before the gate. */
export function ramStats(report) {
  const leaked = new Set(eventsOf(report, 'leak').filter((e) => e.et === ENEMY_RAM).map((e) => e.id));
  const spawned = sum(eventsOf(report, 'push').map((e) => (Array.isArray(e.roads) ? e.roads.length : 0)));
  const killed = new Set(eventsOf(report, 'kill').filter((e) => e.et === ENEMY_RAM).map((e) => e.id));
  let stopped = 0;
  for (const id of killed) if (!leaked.has(id)) stopped += 1;
  return { spawned, stopped, leaked: leaked.size };
}

// --- result helpers -----------------------------------------------------------------------------------

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

/** Common sanity of one report against its name: a game id, content, player counts, seed. */
function argsProblems(name, r, want) {
  const probs = [];
  const a = r.args ?? {};
  if (want.content && r.content_id !== want.content) probs.push(`${name}: content ${r.content_id}, wanted ${want.content}`);
  if (want.players !== undefined && Number(a.players) !== want.players) probs.push(`${name}: players ${a.players}, wanted ${want.players}`);
  if (want.bots !== undefined && Number(a.bots ?? 0) !== want.bots) probs.push(`${name}: bots ${a.bots}, wanted ${want.bots}`);
  if (want.seed !== undefined && Number(r.seed) !== want.seed) probs.push(`${name}: seed ${r.seed}, wanted ${want.seed}`);
  if (want.role && r.role !== want.role) probs.push(`${name}: role ${r.role}, wanted ${want.role}`);
  return probs;
}

function completeProblems(name, r) {
  const probs = [];
  if (r.end_reason !== 'complete') probs.push(`${name}: end_reason ${r.end_reason}`);
  if (r.finished_reason !== 'complete') probs.push(`${name}: finished_reason "${r.finished_reason}"`);
  return probs;
}

// --- S1, S2: Breaches and T1 ------------------------------------------------------------------------------

function breachAndT1(id, title, entries, missing, expect) {
  const probs = missing.map((m) => `missing report ${m}`);
  const scores = [];
  for (const [name, r] of entries) {
    probs.push(...argsProblems(name, r, expect(name)));
    probs.push(...completeProblems(name, r));
    const b = breaches(r);
    if (b > 1) probs.push(`${name}: ${b} Breaches (at most 1)`);
    const s = scoreOf(r);
    if (!Number.isFinite(s)) probs.push(`${name}: no score`);
    else scores.push(s);
  }
  const m = mean(scores);
  if (scores.length && (m < T1_RANGE[0] || m > T1_RANGE[1])) probs.push(`T1: mean score ${fmt(m)} outside ${T1_RANGE[0]}-${T1_RANGE[1]}`);
  return result(id, title, probs, `${entries.length} runs, mean score ${fmt(m)}, Breaches ${entries.map(([, r]) => breaches(r)).join('/')}`);
}

export function checkS1(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'short, 4 compliant Autopilot riders';
  const { found, missing } = pick(reports, seeds.map((n) => `s9_short_seed${n}`));
  if (found.length === 0) return skip('S1', title, 'no s9_short_seed* reports');
  return breachAndT1('S1', title, found, missing, (name) => ({
    content: 'short',
    players: 4,
    bots: 0,
    seed: Number(name.match(/seed(\d+)/)[1]),
  }));
}

export const S2_VARIANTS = { '1h': [1, 0], '2h': [2, 0], '1h3b': [1, 3] };

export function checkS2(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'short with 1 human, 2 humans, 1 human + 3 bots';
  const names = [];
  for (const v of Object.keys(S2_VARIANTS)) for (const n of seeds) names.push(`s2_short_${v}_seed${n}`);
  const { found, missing } = pick(reports, names);
  if (found.length === 0) return skip('S2', title, 'no s2_short_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const parts = [];
  for (const [v, [players, bots]] of Object.entries(S2_VARIANTS)) {
    const mine = found.filter(([n]) => n.startsWith(`s2_short_${v}_`));
    if (mine.length === 0) continue;
    const r = breachAndT1(`S2 ${v}`, v, mine, [], (name) => ({
      content: 'short',
      players,
      bots,
      seed: Number(name.match(/seed(\d+)/)[1]),
      role: players >= 2 ? 'HOST' : 'SOLO',
    }));
    probs.push(...r.details.map((d) => `${v}: ${d}`));
    parts.push(`${v} mean ${r.summary.match(/mean score ([\d.]+)/)?.[1]}`);
  }
  return result('S2', title, probs, parts.join(', '));
}

// --- S3: zero input breaks the gate in the first full wave -----------------------------------------------

/** The first full wave (role wave, number 1) of the host's plan: {index, start, end} or null. */
export function firstFullWave(report) {
  return wavePhases(report).find((w) => w.number === 1) ?? null;
}

export function checkS3(reports) {
  const title = '4 riders at 0 W, a Breach in the first full wave';
  const names = CONTENTS.map((c) => `s3_${c}_zero`);
  const { found, missing } = pick(reports, names);
  if (found.length === 0) return skip('S3', title, 'no s3_*_zero reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const when = [];
  for (const [name, r] of found) {
    const content = name.slice(3, -5);
    probs.push(...argsProblems(name, r, { content, players: 4, role: 'HOST' }));
    probs.push(...completeProblems(name, r));
    const w = firstFullWave(r);
    if (!w) {
      probs.push(`${name}: no wave 1 in the plan`);
      continue;
    }
    const inside = eventsOf(r, 'breach').filter((e) => e._t >= w.start - EPS && e._t <= w.end + EPS);
    if (inside.length === 0) probs.push(`${name}: no Breach in wave 1 (${fmt(w.start)}-${fmt(w.end)} s); Breaches at ${eventsOf(r, 'breach').map((e) => fmt(e._t)).join(', ') || 'none'}`);
    else when.push(`${content} at ${fmt(inside[0]._t - w.start)} s`);
  }
  return result('S3', title, probs, when.join(', '));
}

// --- S4: compliance lowers the score -----------------------------------------------------------------------

export function checkS4(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'short at 100%, 90%, 80% compliance: the mean score falls strictly';
  const groups = {
    100: seeds.map((n) => `s9_short_seed${n}`),
    90: seeds.map((n) => `s4_short_c90_seed${n}`),
    80: seeds.map((n) => `s4_short_c80_seed${n}`),
  };
  const all = Object.values(groups).flat();
  const { found } = pick(reports, all);
  if (found.length === 0) return skip('S4', title, 'no s4_short_* reports');
  const probs = [];
  const means = {};
  for (const [c, names] of Object.entries(groups)) {
    const { found: f, missing } = pick(reports, names);
    probs.push(...missing.map((m) => `missing report ${m}`));
    for (const [name, r] of f) {
      probs.push(...argsProblems(name, r, { content: 'short', players: 4 }));
      probs.push(...completeProblems(name, r));
    }
    means[c] = mean(f.map(([, r]) => scoreOf(r)).filter(Number.isFinite));
  }
  if (!(means[100] > means[90])) probs.push(`mean score 100% (${fmt(means[100])}) is not above 90% (${fmt(means[90])})`);
  if (!(means[90] > means[80])) probs.push(`mean score 90% (${fmt(means[90])}) is not above 80% (${fmt(means[80])})`);
  return result('S4', title, probs, `100% ${fmt(means[100])}, 90% ${fmt(means[90])}, 80% ${fmt(means[80])}`);
}

// --- S5: directives, warm-up limits, plans, laps, snapshots in every run ------------------------------------

/** The plan's laps: the phases with lap true (the cool-down is one of them). */
export function planLaps(report, peer = hostPeer(report)) {
  return (report.plans?.[peer]?.phases ?? []).filter((p) => p.lap).length;
}

/** Problems with one directive entry of a Siege run (brief 2.3: only Overdrive's block). */
export function directiveProblems(name, d) {
  const probs = [];
  const at = `${name}: directive ${d?.id}`;
  if (d.kind !== 'request') return [`${at}: kind ${d.kind} (Siege only requests)`];
  const req = isObj(d.requested) ? { ...d.requested } : {};
  delete req.id;
  const keys = Object.keys(req).sort();
  const want = Object.keys(OD_DIRECTIVE).sort();
  if (JSON.stringify(keys) !== JSON.stringify(want)) probs.push(`${at}: keys ${keys.join(',')}, wanted ${want.join(',')}`);
  for (const k of want) if (req[k] !== OD_DIRECTIVE[k]) probs.push(`${at}: ${k} ${JSON.stringify(req[k])}, wanted ${JSON.stringify(OD_DIRECTIVE[k])}`);
  if (d.accepted !== true) probs.push(`${at}: not accepted (${d.reason})`);
  const rec = d.applied;
  if (!isObj(rec)) probs.push(`${at}: no applied record`);
  else {
    if (!Array.isArray(rec.clamped_by)) probs.push(`${at}: the applied record has no clamped_by list`);
    if (rec.refused === true) probs.push(`${at}: refused by the governor (${rec.reason})`);
    if (Array.isArray(rec.dropped) && rec.dropped.length) probs.push(`${at}: dropped channels ${JSON.stringify(rec.dropped)}`);
    if (!isObj(rec.applied)) probs.push(`${at}: the applied record carries no applied values`);
  }
  return probs;
}

/** Warm-up, range and haptics problems of one rider's 1 Hz trace (at most 3 messages). */
export function traceProblems(name, peer, rows, ftp) {
  const probs = [];
  const oneWatt = 100 / Math.max(ftp, 1) + EPS;
  const add = (msg) => {
    if (probs.length < 3) probs.push(`${name}: peer ${peer} ${msg}`);
  };
  for (const row of rows) {
    const gt = Number(row.game_t ?? row.t);
    const pct = Number(row.applied_pct);
    if (gt < WARMUP_S - EPS) {
      if (row.mode === 'SIM') add(`in SIM at ${fmt(gt)} s (the first ${WARMUP_S} s are ERG)`);
      if (row.mode === 'ERG' && pct > WARMUP_MAX_PCT + oneWatt) add(`at ${fmt(pct)}% FTP at ${fmt(gt)} s (warm-up max ${WARMUP_MAX_PCT})`);
    }
    if (row.mode === 'ERG' && pct > 117 + oneWatt) add(`ERG at ${fmt(pct)}% FTP at ${fmt(gt)} s (max 117)`);
    if (Number(row.haptic ?? 0) !== 0) add(`haptics at ${fmt(gt)} s (Siege sends none)`);
  }
  return probs;
}

/** Wave targets of every plan obey the offset clamps (<= 105 above 240 s, <= 117 otherwise, >= 50). */
export function planProblems(name, report) {
  const probs = [];
  for (const [peer, plan] of Object.entries(report.plans ?? {})) {
    for (const ph of plan.phases ?? []) {
      if (ph.kind !== 'WORK') continue;
      const cap = Number(ph.duration_s) > 240 ? 105 : 117;
      if (ph.target_pct > cap + EPS || ph.target_pct < 50 - EPS) probs.push(`${name}: peer ${peer} ${ph.label} at ${ph.target_pct}% (50..${cap})`);
    }
  }
  for (const [peer, w] of Object.entries(report.plan_warnings ?? {})) {
    if (Array.isArray(w) && w.length) probs.push(`${name}: peer ${peer} plan warnings ${JSON.stringify(w)}`);
  }
  return probs;
}

/** The wave offsets in `--player-options` give exactly these WORK targets (base + offset, clamped). */
export function offsetProblems(name, report) {
  const probs = [];
  const opts = report.args?.player_options;
  if (!Array.isArray(opts) || opts.length === 0) return probs;
  const base = { vo2: 112, short: 95, sweetspot: 90, endurance: 70 }[report.content_id];
  if (base === undefined) return probs;
  (report.slots ?? []).forEach((s, i) => {
    if (s.is_bot) return;
    const off = Number(opts[i]?.wave_offset ?? 0);
    const dur = (report.plans?.[String(s.peer)]?.phases ?? []).find((p) => p.kind === 'WORK')?.duration_s ?? 0;
    const want = Math.min(Math.max(base + off, 50), dur > 240 ? 105 : 117);
    for (const ph of report.plans?.[String(s.peer)]?.phases ?? []) {
      if (ph.kind === 'WORK' && Math.abs(ph.target_pct - want) > 1e-6) probs.push(`${name}: peer ${s.peer} wave target ${ph.target_pct}%, wanted ${want}% (offset ${off})`);
    }
  });
  return probs;
}

export function runProblems(name, r) {
  const probs = [];
  probs.push(...completeProblems(name, r));
  probs.push(...planProblems(name, r));
  probs.push(...offsetProblems(name, r));
  const laps = EXPECTED_LAPS[r.content_id];
  if (laps !== undefined && planLaps(r) !== laps) probs.push(`${name}: plan has ${planLaps(r)} laps, wanted ${laps}`);
  for (const d of r.directives ?? []) probs.push(...directiveProblems(name, d));
  if ((r.directives_unmatched ?? []).length) probs.push(`${name}: ${r.directives_unmatched.length} applied records match no request`);
  for (const [peer, rows] of Object.entries(r.trace ?? {})) {
    const slot = (r.slots ?? []).find((s) => String(s.peer) === peer);
    probs.push(...traceProblems(name, peer, rows, Number(slot?.ftp ?? 200)));
  }
  if ((r.oversize_snapshots ?? 0) > 0) probs.push(`${name}: ${r.oversize_snapshots} snapshots over 16 KB`);
  if (Number(r.max_snapshot_bytes ?? 0) > MAX_SNAPSHOT_BYTES) probs.push(`${name}: largest snapshot ${r.max_snapshot_bytes} B (limit ${MAX_SNAPSHOT_BYTES})`);
  if (!Array.isArray(r.fit_paths) || r.fit_paths.length !== (r.slots ?? []).filter((s) => !s.is_bot).length) probs.push(`${name}: fit_paths ${JSON.stringify(r.fit_paths)} (one per human slot)`);
  return probs;
}

export function checkS5(reports) {
  const title = 'directives clamped and exact, warm-up limits, plans, laps, snapshots, every run complete';
  const names = Object.keys(reports);
  if (names.length === 0) return skip('S5', title, 'no reports');
  const probs = [];
  for (const n of names) probs.push(...runProblems(n, reports[n]));
  const ctn = [...new Set(names.map((n) => reports[n].content_id))].sort();
  return result('S5', title, probs, `${names.length} runs (${ctn.join(', ')})`);
}

// --- S6: rescue is a stagger ---------------------------------------------------------------------------------

export function checkS6(reports) {
  const title = 'sweetspot with a cadence collapse: rescue triggers, the plan runs on';
  const name = 's6_sweetspot_cadence_drop';
  const r = reports[name];
  if (!r) return skip('S6', title, `no ${name} report`);
  const probs = argsProblems(name, r, { content: 'sweetspot' });
  probs.push(...completeProblems(name, r));
  const peer = hostPeer(r);
  const rescues = (r.events ?? []).filter((e) => e.type === 'rescue' && e.active === true);
  const traced = (r.trace?.[peer] ?? []).filter((row) => row.rescue === true);
  if (rescues.length === 0 && traced.length === 0) probs.push('rescue never triggered (no rescue event, no rescue row in the trace)');
  const first = rescues.length ? Number(rescues[0].t) : Number(traced[0]?.game_t ?? traced[0]?.t ?? 0);
  if ((rescues.length || traced.length) && first < 1200 - EPS) probs.push(`rescue at ${fmt(first)} s, before the cadence collapse at 1200 s`);
  const spans = r.phases?.[peer] ?? [];
  const plan = r.plans?.[peer]?.phases ?? [];
  if (spans.length !== plan.length) probs.push(`${spans.length} phases ran, the plan has ${plan.length}`);
  spans.forEach((s, i) => {
    if (s.index !== i) probs.push(`phase ${i} is missing or out of order (index ${s.index})`);
    if (s.ended_by !== 'duration') probs.push(`phase ${s.index} ${s.label} ended by "${s.ended_by}", not its duration`);
  });
  const odd = (r.directives ?? []).filter((d) => d.kind !== 'request' || d.requested?.reason !== 'overdrive');
  if (odd.length) probs.push(`${odd.length} directives other than Overdrive's (a rescue never rewrites the plan)`);
  return result('S6', title, probs, `rescue at ${fmt(first)} s, ${spans.length}/${plan.length} phases ran`);
}

// --- S7: determinism ------------------------------------------------------------------------------------------

export function checkS7(reports) {
  const title = 'vo2 seed 1 twice: identical hash and game events';
  const a = reports.s7_vo2_seed1;
  const b = reports.s9_vo2_seed1;
  if (!a && !b) return skip('S7', title, 'no s7_vo2_seed1 / s9_vo2_seed1 reports');
  if (!a || !b) return result('S7', title, [`missing report ${a ? 's9_vo2_seed1' : 's7_vo2_seed1'}`]);
  const probs = [];
  if (a.deterministic_hash !== b.deterministic_hash) probs.push(`deterministic_hash differs: ${a.deterministic_hash} vs ${b.deterministic_hash}`);
  const ea = JSON.stringify(gameEvents(a));
  const eb = JSON.stringify(gameEvents(b));
  if (ea !== eb) probs.push(`game events differ (${gameEvents(a).length} vs ${gameEvents(b).length} events)`);
  if (gameEvents(a).length === 0) probs.push('no game events to compare');
  return result('S7', title, probs, `${gameEvents(a).length} events, hash ${String(a.deterministic_hash).slice(0, 12)}`);
}

// --- S9: T3, T4 -------------------------------------------------------------------------------------------------

export function checkS9(reports, opts = {}) {
  const seeds = opts.seeds ?? DEFAULT_SEEDS;
  const title = 'T3 leaks per wave-minute across the shifts, T4 rams stopped';
  const names = [];
  for (const c of CONTENTS) for (const n of seeds) names.push(`s9_${c}_seed${n}`);
  const { found, missing } = pick(reports, names);
  if (found.length === 0) return skip('S9', title, 'no s9_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const rates = {};
  let spawned = 0;
  let stopped = 0;
  for (const [name, r] of found) {
    probs.push(...argsProblems(name, r, { players: 4, bots: 0 }));
    probs.push(...completeProblems(name, r));
    (rates[r.content_id] ??= []).push(leakStats(r).rate);
    const rs = ramStats(r);
    spawned += rs.spawned;
    stopped += rs.stopped;
  }
  const per = {};
  for (const c of CONTENTS) if (rates[c]) per[c] = mean(rates[c]);
  const ref = mean(Object.values(per));
  for (const [c, v] of Object.entries(per)) {
    if (Math.abs(v - ref) > T3_SPREAD * ref + EPS) probs.push(`T3: ${c} leaks ${fmt(v)}/wave-min, the mean of the shifts is ${fmt(ref)} (+-${T3_SPREAD * 100}% allowed)`);
  }
  if (Object.keys(per).length < CONTENTS.length) probs.push(`T3: only ${Object.keys(per).join(', ')} have reports`);
  if (spawned === 0) probs.push('T4: no ram was ever pushed (no push events)');
  else if (stopped / spawned < T4_MIN - EPS) probs.push(`T4: ${stopped}/${spawned} rams stopped before the gate (${fmt((100 * stopped) / spawned)}%, need ${T4_MIN * 100}%)`);
  const t3 = Object.entries(per).map(([c, v]) => `${c} ${fmt(v)}`).join(', ');
  return result('S9', title, probs, `leaks/wave-min ${t3}; rams stopped ${stopped}/${spawned}`);
}

// --- S10: Overdrive ----------------------------------------------------------------------------------------------

/** Runs of consecutive rows in `mode`: [{from, to, startIdx, endIdx}] (to = game time of the
 *  first row after the run; null when the trace ends inside it). */
export function modeSpans(rows, mode) {
  const spans = [];
  let cur = null;
  rows.forEach((row, i) => {
    const t = Number(row.game_t ?? row.t);
    if (row.mode === mode) {
      if (!cur) cur = { from: t, to: null, startIdx: i, endIdx: i };
      cur.endIdx = i;
    } else if (cur) {
      cur.to = t;
      cur.afterIdx = i;
      spans.push(cur);
      cur = null;
    }
  });
  if (cur) spans.push(cur);
  return spans;
}

/** Mode-change times of a trace: [{t, to}] for each row whose mode differs from the previous. */
export function switches(rows) {
  const out = [];
  for (let i = 1; i < rows.length; i++) {
    if (rows[i].mode !== rows[i - 1].mode) out.push({ t: Number(rows[i].game_t ?? rows[i].t), to: rows[i].mode });
  }
  return out;
}

export function overdriveDirectives(report) {
  return (report.directives ?? []).filter((d) => d.kind === 'request' && d.requested?.reason === 'overdrive');
}

/** Problems with the Overdrive behaviour of one run (S10). */
export function overdriveProblems(name, r) {
  const probs = [];
  const ods = overdriveDirectives(r);
  const starts = eventsOf(r, 'overdrive').filter((e) => e.st === 1);
  if (ods.length < MIN_OVERDRIVES) probs.push(`${name}: ${ods.length} Overdrive directives (need ${MIN_OVERDRIVES}+)`);
  if (starts.length < MIN_OVERDRIVES) probs.push(`${name}: ${starts.length} Overdrive start events (need ${MIN_OVERDRIVES}+)`);
  const byPeer = {};
  for (const d of ods) {
    const peer = String(d.peer);
    (byPeer[peer] ??= []).push(d);
    probs.push(...directiveProblems(name, d));
    const rec = d.applied;
    if (!isObj(rec)) continue;
    if (Number(d.peer) < 0) probs.push(`${name}: a bot (peer ${d.peer}) sent an Overdrive`);
    const spans = r.phases?.[peer] ?? [];
    const ph = spans.find((s) => s.index === rec.phase_index);
    const t0 = Number(rec.game_t ?? d.t);
    if (!ph) probs.push(`${name}: directive ${d.id} names phase ${rec.phase_index}, which has no span`);
    else {
      if (ph.kind !== 'WORK') probs.push(`${name}: directive ${d.id} in a ${ph.kind} phase (${ph.label})`);
      const left = (ph.end < 0 ? Infinity : Number(ph.end)) - t0;
      if (left < OD_SPAN_S - 0.1) probs.push(`${name}: directive ${d.id} with ${fmt(left)} s of ${ph.label} left (need 30)`);
    }
    const dur = rec.applied?.duration_s;
    if (typeof dur === 'number' && Math.abs(dur - OD_SPAN_S) > 0.1) probs.push(`${name}: directive ${d.id} applied ${dur} s`);
    if (rec.applied?.sim_block !== true) probs.push(`${name}: directive ${d.id} did not open a SIM block (${JSON.stringify(rec.applied)})`);
    const rows = r.trace?.[peer] ?? [];
    const rescued = rows.filter((row) => row.rescue === true && Number(row.game_t ?? row.t) >= t0 - 1.5 && Number(row.game_t ?? row.t) <= t0 + OD_SPAN_S + 1);
    if (rescued.length) probs.push(`${name}: directive ${d.id}: peer ${peer} in rescue around the Overdrive at ${fmt(rescued[0].game_t ?? rescued[0].t)} s`);
  }
  for (const [peer, list] of Object.entries(byPeer)) {
    const rows = r.trace?.[peer] ?? [];
    const sims = modeSpans(rows, 'SIM');
    if (sims.length !== list.length) probs.push(`${name}: peer ${peer} has ${list.length} Overdrive directives but ${sims.length} SIM spans on the trace`);
    for (const s of sims) {
      if (s.to === null) {
        probs.push(`${name}: peer ${peer} still in SIM when the trace ends (from ${fmt(s.from)} s)`);
        continue;
      }
      const len = s.to - s.from;
      if (Math.abs(len - OD_SPAN_S) > OD_SPAN_TOL_S + EPS) probs.push(`${name}: peer ${peer} SIM span from ${fmt(s.from)} s lasted ${fmt(len)} s (30 +- ${OD_SPAN_TOL_S})`);
      // The return to ERG is a ramped switch to the planned target.
      const back = rows[s.afterIdx];
      if (back.mode !== 'ERG') probs.push(`${name}: peer ${peer} left SIM at ${fmt(s.to)} s into ${back.mode}, not ERG`);
      const near = rows.slice(s.afterIdx, s.afterIdx + 4);
      const ramped = near.some((row) => (row.clamped_by ?? []).some((c) => c === 'switch_ramp' || c === 'slew'));
      if (!ramped) probs.push(`${name}: peer ${peer} returned to ERG at ${fmt(s.to)} s without the ramped switch (clamped_by ${JSON.stringify(back.clamped_by)})`);
      const slot = (r.slots ?? []).find((x) => String(x.peer) === peer);
      const u = slot && slot.ftp_verified === false ? 0.85 : 1;
      const plan = r.plans?.[peer]?.phases ?? [];
      const oneWatt = 100 / Math.max(Number(slot?.ftp ?? 200), 1) + 0.5;
      const window = rows.slice(s.afterIdx, s.afterIdx + 45);
      const reached = window.some((row) => {
        const tgt = plan[row.phase]?.target_pct;
        return row.mode === 'ERG' && tgt !== undefined && Math.abs(Number(row.applied_pct) - tgt * u) <= oneWatt;
      });
      if (!reached) probs.push(`${name}: peer ${peer} never got back to the planned ERG target within 45 s of ${fmt(s.to)} s`);
    }
    // Switch spacing: (ERG->SIM, SIM->ERG) is the exempt Overdrive bracket; every other pair >= 30 s.
    const sw = switches(rows);
    for (let i = 0; i + 1 < sw.length; i++) {
      const bracket = sw[i].to === 'SIM';
      if (!bracket && sw[i + 1].t - sw[i].t < SWITCH_SPACING_S - EPS) probs.push(`${name}: peer ${peer} switched ${sw[i].to} -> ${sw[i + 1].to} only ${fmt(sw[i + 1].t - sw[i].t)} s apart at ${fmt(sw[i].t)} s`);
    }
  }
  return probs;
}

export function checkS10(reports) {
  const title = 'surgers: 3+ Overdrives, exact directives, 30 s SIM spans, ramped returns, spacing';
  const names = ['s10_vo2', 's10_endurance', 's10_vo2_offsets'];
  const { found, missing } = pick(reports, names);
  if (found.length === 0) return skip('S10', title, 'no s10_* reports');
  const probs = missing.map((m) => `missing report ${m}`);
  const counts = [];
  for (const [name, r] of found) {
    const content = name === 's10_endurance' ? 'endurance' : 'vo2';
    probs.push(...argsProblems(name, r, { content, players: 4 }));
    probs.push(...completeProblems(name, r));
    probs.push(...overdriveProblems(name, r));
    counts.push(`${name} ${overdriveDirectives(r).length}`);
  }
  return result('S10', title, probs, `Overdrives: ${counts.join(', ')}`);
}

// --- FIT laps from fit_check (optional) ---------------------------------------------------------------------------

/** Runs tools/fit_check on every FIT of every report (`runner(args) -> {status, stdout}`). */
export function checkFit(reports, runner) {
  const title = 'FIT laps per content';
  const probs = [];
  let n = 0;
  for (const [name, r] of Object.entries(reports)) {
    const laps = EXPECTED_LAPS[r.content_id];
    for (const f of r.fit_paths ?? []) {
      n += 1;
      const res = runner([f, `--expect-laps=${laps}`, '--json']);
      if (res.status !== 0) probs.push(`${name}: fit_check exit ${res.status} for ${f}`);
      else {
        try {
          const j = JSON.parse(res.stdout);
          for (const file of j.files ?? []) if ((file.laps ?? []).length !== laps) probs.push(`${name}: ${file.laps?.length} laps in ${f}, wanted ${laps}`);
        } catch {
          probs.push(`${name}: fit_check printed no JSON for ${f}`);
        }
      }
    }
  }
  if (n === 0) return skip('FIT', title, 'no FIT files in the reports');
  return result('FIT', title, probs, `${n} files`);
}

function defaultFitRunner(args) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..');
  const r = spawnSync(process.execPath, [path.join(root, 'tools', 'fit_check', 'check.mjs'), ...args], { encoding: 'utf8', cwd: root });
  return { status: r.status ?? 1, stdout: r.stdout ?? '' };
}

// --- driver ---------------------------------------------------------------------------------------------------------

export const SCENARIOS = [
  ['S1', checkS1],
  ['S2', checkS2],
  ['S3', checkS3],
  ['S4', checkS4],
  ['S5', checkS5],
  ['S6', checkS6],
  ['S7', checkS7],
  ['S9', checkS9],
  ['S10', checkS10],
];

/** Runs the scenarios (`only`: ids, or null for all); returns the result objects. */
export function checkAll(reports, only = null, opts = {}) {
  const out = [];
  for (const [id, fn] of SCENARIOS) {
    if (only && !only.includes(id)) continue;
    out.push(fn(reports, opts));
  }
  if (opts.fit) out.push(checkFit(reports, opts.fitRunner ?? defaultFitRunner));
  return out;
}

export function format(results) {
  const lines = [];
  for (const r of results) {
    lines.push(`${r.status} ${r.id}  ${r.summary}`);
    for (const d of r.details) lines.push(`    - ${d}`);
  }
  return lines.join('\n');
}

export function main(argv) {
  const args = argv.filter((a) => !a.startsWith('--'));
  const seedArg = argv.find((a) => a.startsWith('--seeds='));
  const seeds = seedArg ? seedArg.slice(8).split(',').map(Number).filter(Number.isInteger) : null;
  const only = argv.find((a) => a.startsWith('--only='))?.slice(7).split(',').map((s) => s.trim().toUpperCase()) ?? null;
  const dir = args[0];
  if (!dir) {
    process.stderr.write('usage: node tests/games/siege/sim/check_sims.mjs <reports dir> [--only=S3,S9] [--fit]\n');
    return 2;
  }
  let reports;
  try {
    reports = loadReports(dir);
  } catch (err) {
    process.stderr.write(`check_sims: ${err.message}\n`);
    return 2;
  }
  if (Object.keys(reports).length === 0) {
    process.stderr.write(`check_sims: no Siege reports in ${dir}\n`);
    return 2;
  }
  const results = checkAll(reports, only, { fit: argv.includes('--fit'), ...(seeds && seeds.length ? { seeds } : {}) });
  process.stdout.write(`${format(results)}\n`);
  const failed = results.filter((r) => r.status === 'FAIL').length;
  const passed = results.filter((r) => r.status === 'PASS').length;
  process.stdout.write(`check_sims: ${passed} passed, ${failed} failed, ${results.length - passed - failed} skipped (${Object.keys(reports).length} reports)\n`);
  return failed === 0 ? 0 : 1;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(self)) {
  process.exitCode = main(process.argv.slice(2));
}
