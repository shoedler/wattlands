#!/usr/bin/env node
// tests/games/fishing/sim/fixtures/make_fixtures.mjs: small synthetic run_game_sim reports for
// check_sims.test.mjs, in the GAME_SDK 19.1 layout, with Fishing's events (fishing_events.gd).
//
//   node tests/games/fishing/sim/fixtures/make_fixtures.mjs     # rewrites pass/ and fail/
//
// pass/ holds one passing report per scenario of brief 4.2 (s1 ... s10, with s3 at seeds 1-5 and
// the s8 pair); fail/ holds broken copies, each with the defects listed in FAILURES. The test
// checks that the files on disk equal what this module builds, so edit the builder, then rerun it.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const SP = { mackerel: 0, mahi: 1, tuna: 2, marlin: 3 };
const LABEL = { mackerel: 'MACKEREL', mahi: 'MAHI', tuna: 'TUNA', marlin: 'MARLIN' };
export const FTP = 200;

/** Default fight shapes per species: base pull, range_pct, min_s, max_s. */
export const SHAPES = {
  mackerel: { base: 75, lo: 72, hi: 78, minS: 64, maxS: 150 },
  mahi: { base: 90, lo: 82.8, hi: 110, minS: 128, maxS: 270 },
  tuna: { base: 95, lo: 87.4, hi: 102.6, minS: 276, maxS: 420 },
  marlin: { base: 88, lo: 80.96, hi: 104, minS: 720, maxS: 1320 },
};

const round3 = (x) => Math.round(x * 1000) / 1000;

/**
 * One run report. o: {content, players, seed, autopilot, rideOutS, rideOutPct, cooldownAt,
 * lanes: [{fights: [{species, reel, len, endedBy, landed, events: [{dt, ...event}], directives:
 * [{dt, target, reason, duration}]}]}], events: [extra report events], clamps, trace: {peer: rows}}.
 * Times in each lane run: ride out, then per fight its Reel, Fight and 30 s Landing; the last Reel
 * runs to the cool-down (Free trips), which starts at cooldownAt or after the latest Landing.
 */
export function buildRun(o) {
  const players = o.players ?? o.lanes.length;
  const rideOutS = o.rideOutS ?? 300;
  const lanes = o.lanes;
  const slots = [];
  const plans = {};
  const phases = {};
  const trace = {};
  const directives = [];
  const fit = [];
  const gameEv = [];
  const sysEv = [];
  let dirId = 1;
  // Lane timelines first, to find the cool-down start.
  const timelines = lanes.map((ln) => {
    let t = rideOutS;
    const segs = [];
    for (const f of ln.fights) {
      const reelStart = t;
      const fightStart = reelStart + f.reel;
      const fightEnd = fightStart + f.len;
      segs.push({ f, reelStart, fightStart, fightEnd, landEnd: fightEnd + 30 });
      t = fightEnd + 30;
    }
    return { segs, end: t };
  });
  const latest = Math.max(rideOutS, ...timelines.map((x) => x.end));
  const cooldownAt = o.cooldownAt ?? (o.scheduled ? latest : Math.max(latest, rideOutS + (o.fishingS ?? 0)));
  const end = cooldownAt + 180;
  lanes.forEach((ln, lane) => {
    const peer = String(lane + 1);
    slots.push({ slot: lane, peer: lane + 1, name: `Rider ${lane + 1}`, is_bot: false, ftp: FTP, ftp_verified: true, rider: o.rider ?? 'erg+band', autopilot: o.autopilot ?? true, haptics_on: true, options: { reel_pct: 60, relaxed_band: false } });
    const plan = [{ kind: 'WARMUP', mode: 'ERG', label: 'FISHING_PHASE_RIDE_OUT', lap: true, duration_s: rideOutS, target_pct: o.rideOutPct ?? 50 }];
    const spans = [{ index: 0, kind: 'WARMUP', mode: 'ERG', label: 'FISHING_PHASE_RIDE_OUT', start: 0, end: rideOutS, ended_by: 'duration' }];
    const rows = [{ t: 1, game_t: 1, phase: 0, kind: 'WARMUP', mode: 'ERG', applied_target_w: 100, applied_pct: 50, applied_grade_pct: 0, clamped_by: o.warmupClamps ?? [], rescue: false, afk: false, paused: false, haptic: 0, power_w: 100, cadence_rpm: 90, connected: true }];
    const segs = timelines[lane].segs;
    segs.forEach((s, k) => {
      const sh = { ...SHAPES[s.f.species], ...(s.f.shape ?? {}) };
      const reelIdx = plan.length;
      const reelEnd = s.fightStart;
      plan.push({ kind: 'RECOVERY', mode: 'ERG', label: `FISHING_PHASE_REEL_${k + 1}`, lap: true, duration_s: o.scheduled ? s.f.reel : 240, target_pct: 60 });
      spans.push({ index: reelIdx, kind: 'RECOVERY', mode: 'ERG', label: `FISHING_PHASE_REEL_${k + 1}`, start: s.reelStart, end: reelEnd, ended_by: o.scheduled ? 'duration' : 'end_phase' });
      const fIdx = plan.length;
      const label = `FISHING_PHASE_${LABEL[s.f.species]}_${k + 1}`;
      plan.push({ kind: 'WORK', mode: 'ERG', label, lap: true, duration_s: s.f.len, open_ended: true, min_s: sh.minS, max_s: sh.maxS, target_pct: sh.base, range_pct: [sh.lo, sh.hi], meta: { slot: k, species: s.f.species } });
      spans.push({ index: fIdx, kind: 'WORK', mode: 'ERG', label, start: s.fightStart, end: s.fightEnd, ended_by: s.f.endedBy ?? 'end_phase' });
      plan.push({ kind: 'WORK', mode: 'SIM', label: 'FISHING_PHASE_LANDING', lap: false, duration_s: 30 });
      spans.push({ index: fIdx + 1, kind: 'WORK', mode: 'SIM', label: 'FISHING_PHASE_LANDING', start: s.fightEnd, end: s.landEnd, ended_by: 'duration' });
      gameEv.push({ t: s.fightStart, event: { type: 'hookup', l: lane, sp: SP[s.f.species], n: k + 1, sch: o.scheduled ? 1 : 0 } });
      for (const e of s.f.events ?? []) {
        const { dt, ...ev } = e;
        gameEv.push({ t: round3(s.fightStart + dt), event: { l: lane, ...ev } });
      }
      if (s.f.landed !== false) {
        gameEv.push({ t: s.fightEnd, event: { type: 'landing', l: lane, sp: SP[s.f.species] } });
        gameEv.push({ t: s.landEnd, event: { type: 'landed', l: lane, sp: SP[s.f.species], grade: 0, kg: 12, points: 20, hk: s.f.hk ?? 10 } });
      }
      const ds = s.f.directives ?? [{ dt: 10, target: sh.base, reason: 'pull', duration: 0 }];
      for (const d of ds) {
        const id = dirId++;
        const requested = { mode: 'ERG', target_pct: d.target, duration_s: d.duration ?? 0, reason: d.reason ?? 'pull', source: 'fishing', id };
        const tt = round3(s.fightStart + d.dt);
        directives.push({ id, peer: lane + 1, t: tt, kind: 'request', requested, accepted: true, reason: '', applied: { id, kind: 'request', requested, applied: { target_pct: d.target }, clamped_by: d.clamps ?? o.clamps ?? ['slew'], refused: false, reason: '', t: tt, game_t: tt, phase_index: fIdx } });
        rows.push({ t: tt + 1, game_t: tt + 1, phase: fIdx, kind: 'WORK', mode: 'ERG', applied_target_w: (d.target * FTP) / 100, applied_pct: d.target, applied_grade_pct: 0, clamped_by: [], rescue: false, afk: false, paused: false, haptic: 0, power_w: (d.target * FTP) / 100, cadence_rpm: 90, connected: true });
      }
    });
    if (!o.scheduled) {
      const k = segs.length;
      const start = timelines[lane].end;
      plan.push({ kind: 'RECOVERY', mode: 'ERG', label: `FISHING_PHASE_REEL_${k + 1}`, lap: true, duration_s: 240, target_pct: 60 });
      spans.push({ index: plan.length - 1, kind: 'RECOVERY', mode: 'ERG', label: `FISHING_PHASE_REEL_${k + 1}`, start, end: cooldownAt, ended_by: 'finished' });
    }
    plan.push({ kind: 'COOLDOWN', mode: 'ERG', label: 'Cool-down', lap: true, duration_s: 180, target_pct: 50 });
    spans.push({ index: plan.length - 1, kind: 'COOLDOWN', mode: 'ERG', label: 'Cool-down', start: cooldownAt, end, ended_by: 'duration' });
    plans[peer] = { phases: plan, cooldown_appended: true };
    phases[peer] = spans;
    trace[peer] = [...rows, ...(o.trace?.[peer] ?? [])].sort((a, b) => a.t - b.t);
    fit.push(`/fixtures/fit/${o.name ?? 'run'}_slot${lane}.fit`);
    for (const sp of spans) sysEv.push({ t: sp.start, pt: sp.start, type: 'phase_started', peer: lane + 1, index: sp.index, kind: sp.kind, ended_by: 'start' });
  });
  for (const e of o.events ?? []) sysEv.push({ pt: e.t, ...e });
  const all = [
    ...sysEv,
    ...gameEv.map((g) => ({ t: g.t, pt: g.t, type: 'game_event', event: g.event })),
  ].sort((a, b) => a.t - b.t);
  const events = [{ t: 0, pt: 0, type: 'session_start', role: players > 1 ? 'HOST' : 'SOLO', players }, ...all, { t: end, pt: end, type: 'session_end', reason: 'complete' }];
  const report = {
    schema: 1,
    args: { game: 'fishing', content: o.content, players, bots: 0, riders: [o.rider ?? 'erg+band'], seed: o.seed ?? 1, autopilot: o.autopilot === false ? 'none' : 'all' },
    game_id: 'fishing',
    content_id: o.content,
    role: players > 1 ? 'HOST' : 'SOLO',
    seed: o.seed ?? 1,
    slots,
    plans,
    plan_warnings: Object.fromEntries(Object.keys(plans).map((p) => [p, []])),
    overrides: {},
    end_reason: o.endReason ?? 'complete',
    finished_reason: 'trip_over',
    sim_seconds: end,
    game_seconds: end,
    max_sim_seconds: end + 600,
    events,
    phases,
    directives,
    directives_unmatched: [],
    trace,
    snapshots: [],
    max_snapshot_bytes: 900 + 250 * players,
    oversize_snapshots: 0,
    results: { grade: 'B', score: 100, summary_key: 'FISHING_RESULTS', rows: [], team: { fish: gameEv.filter((g) => g.event.type === 'landed').length } },
    unlocks: {},
    clients: [],
    fit_paths: fit,
    meta: { wall_s: 1 },
  };
  report.deterministic_hash = crypto.createHash('sha256').update(JSON.stringify([report.events, report.phases, report.directives])).digest('hex');
  return report;
}

const tunaThreshold = (len = 300, extra = {}) => ({ species: 'tuna', len, ...extra });
const thresholdLane = (fights) => ({ fights: fights.map((f, k) => ({ reel: k === 0 ? 240 : 360, ...f })) });

/** Reports that pass every scenario, by name. */
export function passing() {
  const out = {};
  out.s1_threshold = buildRun({ name: 's1_threshold', content: 'threshold', scheduled: true, lanes: [0, 1].map(() => thresholdLane([0, 1, 2, 3].map(() => tunaThreshold(330)))) });
  const lossFights = (type) => [0, 1, 2, 3].map(() => tunaThreshold(420, { endedBy: 'max_s', events: [{ dt: 6, type }, { dt: 11, type: 'replacement', sp: SP.tuna }, { dt: 17, type }] }));
  out.s2_low = buildRun({ name: 's2_low', content: 'threshold', scheduled: true, rider: 'erg+band:offset_rpm=-18', lanes: [thresholdLane(lossFights('snap'))] });
  out.s2_high = buildRun({ name: 's2_high', content: 'threshold', scheduled: true, rider: 'erg+band:offset_rpm=18', lanes: [thresholdLane(lossFights('thrown'))] });
  for (let seed = 1; seed <= 5; seed++) {
    const lane = (k) => ({ fights: [{ species: 'mackerel', reel: 200 + 10 * k, len: 90 }, { species: 'mahi', reel: 300, len: 150, hk: seed === 1 && k < 2 ? 15 : 10 }] });
    const events = [];
    const r = buildRun({ name: `s3_free30_seed${seed}`, content: 'free_30', seed, fishingS: 1320, lanes: [0, 1, 2, 3].map(lane), events });
    if (seed === 1) {
      r.events.splice(r.events.length - 1, 0, { t: 900, pt: 900, type: 'game_event', event: { type: 'double_hookup', lanes: [0, 1], lvl: 2 } });
    }
    out[`s3_free30_seed${seed}`] = r;
  }
  const solo = (ap) => buildRun({ name: `s4_ap_${ap ? 'all' : 'none'}`, content: 'free_30', autopilot: ap, rider: 'erg:compliance=1.0', fishingS: 1320, lanes: [{ fights: [{ species: 'mackerel', reel: 240, len: 100 }] }] });
  out.s4_ap_none = solo(false);
  out.s4_ap_all = solo(true);
  const baseLane = { fights: [{ species: 'mackerel', reel: 300, len: 100 }, { species: 'mahi', reel: 400, len: 200, shape: { hi: 100, lo: 82.8 }, directives: [{ dt: 10, target: 90 }, { dt: 40, target: 100, reason: 'run', duration: 20 }] }] };
  out.s5_base60 = buildRun({ name: 's5_base60', content: 'base_60', fishingS: 3120, lanes: [baseLane, baseLane] });
  const jumps = [1, 2, 3, 4, 5].map((k) => ({ dt: 100 * k, type: 'jump', k, n: 5, ms: 25000, leaps: 2 }));
  const jumpDirs = [{ dt: 10, target: 88 }];
  for (let k = 1; k <= 5; k++) for (const [i, p] of [96, 100, 104].entries()) jumpDirs.push({ dt: 100 * k + 0.5 * i, target: p, reason: 'jump', duration: 25 - 0.5 * i });
  out.s6_free120_marlin = buildRun({ name: 's6_free120_marlin', content: 'free_120', seed: 42, fishingS: 6720, lanes: [{ fights: [{ species: 'mackerel', reel: 300, len: 100 }, { species: 'marlin', reel: 400, len: 900, events: jumps, directives: jumpDirs }] }] });
  out.s7_threshold_drop = buildRun({
    name: 's7_threshold_drop',
    content: 'threshold',
    scheduled: true,
    rider: 'erg+band+cadence_drop:rpm=40,at_s=600,for_s=20',
    lanes: [thresholdLane([0, 1, 2, 3].map(() => tunaThreshold(340)))],
    events: [
      { t: 603, type: 'rescue', peer: 1, active: true },
      { t: 628, type: 'rescue', peer: 1, active: false },
    ],
    trace: { 1: [{ t: 610, game_t: 610, phase: 2, kind: 'WORK', mode: 'ERG', applied_target_w: 100, applied_pct: 50, applied_grade_pct: 0, clamped_by: ['rescue'], rescue: true, afk: false, paused: false, haptic: 0, power_w: 100, cadence_rpm: 40, connected: true }] },
  });
  const det = () => buildRun({ name: 's8_free30', content: 'free_30', seed: 7, fishingS: 1320, lanes: [0, 1].map(() => ({ fights: [{ species: 'mackerel', reel: 250, len: 95 }] })) });
  out.s8_free30_a = det();
  out.s8_free30_b = det();
  const e2eLane = { fights: [{ species: 'mackerel', reel: 20, len: 45, hk: 20, shape: { base: 62, lo: 59.52, hi: 64.48, minS: 36, maxS: 70 } }] };
  out.s10_e2e = buildRun({ name: 's10_e2e', content: 'e2e_2min', scheduled: true, rideOutS: 15, warmupClamps: ['warmup'], clamps: ['warmup'], lanes: [e2eLane, e2eLane, e2eLane] });
  return out;
}

/** A passing tools/e2e report of e2e_2min (GAME_SDK 19.4 layout): host and client1 saw every
 *  event; client2 was restarted after the hookups and holds the tail. */
export function e2eReport() {
  const lanes = [0, 1, 2];
  const fishing = [
    ...lanes.map((l) => ({ type: 'hookup', l, sp: 0, n: 1, sch: 1 })),
    { type: 'double_hookup', lanes: [0, 1, 2], lvl: 3 },
    ...lanes.map((l) => ({ type: 'landing', l, sp: 0 })),
    ...lanes.map((l) => ({ type: 'landed', l, sp: 0, grade: 0, kg: 11, points: 21, hk: 20 })),
  ];
  const times = [37, 37, 37, 47, 82, 82, 83, 112, 112, 113];
  const phases = [0, 17, 37, 82, 113];
  const log = (from, offset) => {
    const ev = [{ type: 'session_state', state: 'running', t: offset }];
    phases.forEach((t, index) => {
      for (const peer of [1, 2, 3]) if (t + offset >= from) ev.push({ type: 'phase_started', peer, index, t: t + offset });
    });
    fishing.forEach((e, i) => {
      if (times[i] + offset >= from) ev.push({ type: 'game_event', event: { ...e }, event_type: e.type, peer: 1, t: times[i] + offset });
    });
    ev.push({ type: 'results', peer: 1, t: 300 + offset });
    return ev.sort((a, b) => a.t - b.t);
  };
  const dir = (role, id, target, clamps) => {
    const requested = { mode: 'ERG', target_pct: target, duration_s: 0, reason: 'pull', source: 'fishing', id };
    return { peer_role: role, id, kind: 'request', requested, applied: { target_pct: target }, clamped_by: clamps, refused: false, reason: '', t: 50, game_t: 50, phase_index: 2 };
  };
  const trace = [{ t: 2, mode: 'ERG', applied_pct: 50, clamped_by: ['warmup'] }, { t: 60, mode: 'ERG', applied_pct: 62, clamped_by: [] }];
  const fitc = { ok: true, json: { files: [{ ok: true, laps: [{}, {}, {}, {}] }] } };
  const peer = (role, id, events, restarted = false) => ({ role, peer_id: id, exit_code: 0, exit_reason: 'complete', events, directives: [], trace, restarted });
  return {
    schema: 1,
    game_id: 'fishing',
    content_id: 'e2e_2min',
    seed: 1,
    ok: true,
    failures: [],
    victim: 'client2',
    peers: { host: peer('host', 1, log(0, 1.5)), client1: peer('client1', 2, log(0, 1.6)), client2: peer('client2', 3, log(60, 0.4), true) },
    events_by_peer: {},
    directives: [dir('host', 1, 62, ['warmup']), dir('client1', 1, 63.5, ['slew', 'warmup']), dir('client2', 1, 61, [])],
    fit_paths: {},
    fit_check: { host: fitc, client1: fitc, client2: fitc },
    e2e_check: null,
  };
}

/** The defects in fail/, by report: what check_sims must report. */
export const FAILURES = {
  s1_threshold: ['lane 1 landed 3 tuna', 'clamped_by long_phase'],
  s10_e2e: ['lane 2 landed nothing', 'reached the cool-down at 140'],
  s6_free120_marlin: ['a jump directive above 104%', 'outside phase'],
  s2_low: ['no snap within 8 s'],
};

/** Broken copies of some passing reports. */
export function failing() {
  const p = passing();
  const out = {};
  // s1: lane 1's last tuna is lost (no landing) and one pull is clamped by the long-phase cap.
  const s1 = p.s1_threshold;
  s1.events = s1.events.filter((e) => !(e.type === 'game_event' && e.event.l === 1 && e.event.type === 'landed' && e.t > 2500));
  s1.directives[0].applied.clamped_by = ['slew', 'long_phase'];
  out.s1_threshold = s1;
  // s10: lane 2 never lands its mackerel, and its fight runs 30 s longer.
  const lane = { fights: [{ species: 'mackerel', reel: 20, len: 45, hk: 20, shape: { base: 62, lo: 59.52, hi: 64.48, minS: 36, maxS: 70 } }] };
  const slow = { fights: [{ ...lane.fights[0], len: 75, landed: false, endedBy: 'max_s' }] };
  out.s10_e2e = buildRun({ name: 's10_e2e', content: 'e2e_2min', scheduled: true, rideOutS: 15, clamps: ['warmup'], lanes: [lane, lane, slow] });
  // s6: a jump step at 105 % (outside the marlin's range_pct, above the 104 % jump peak).
  const s6 = p.s6_free120_marlin;
  const j = s6.directives.find((d) => d.requested.reason === 'jump');
  j.requested.target_pct = 105;
  j.applied.requested = j.requested;
  out.s6_free120_marlin = s6;
  // s2_low: the line holds after the first hookup (the snap comes 12 s later).
  const s2 = p.s2_low;
  const first = s2.events.find((e) => e.type === 'game_event' && e.event.type === 'snap');
  first.t += 6;
  first.pt += 6;
  out.s2_low = s2;
  return out;
}

export function writeAll(dir = here) {
  for (const [sub, set] of [['pass', passing()], ['fail', failing()]]) {
    const d = path.join(dir, sub);
    fs.mkdirSync(d, { recursive: true });
    for (const f of fs.readdirSync(d)) if (f.endsWith('.json')) fs.rmSync(path.join(d, f));
    for (const [name, r] of Object.entries(set)) fs.writeFileSync(path.join(d, `${name}.json`), `${JSON.stringify(r)}\n`);
  }
  fs.mkdirSync(path.join(dir, 'e2e'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'e2e', 'report.json'), `${JSON.stringify(e2eReport(), null, 1)}\n`);
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(self)) {
  writeAll();
  process.stdout.write(`fixtures written to ${here}\n`);
}
