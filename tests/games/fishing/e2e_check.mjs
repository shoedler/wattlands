#!/usr/bin/env node
// tests/games/fishing/e2e_check.mjs: Turbo Reel's own check of an e2e report (BRIEF 3.6,
// 7.7; brief 4.3).
//
//   node tests/games/fishing/e2e_check.mjs build/e2e/fishing/report.json
//
// tools/e2e/run.mjs runs it after playing e2e_2min (ride out 15 s, Troll 20 s, one scheduled
// mackerel per rider, Landing 30 s, then the cool-down) with a host and two clients, one of which
// is killed and restarted. The harness checks the shared events, warm-up limits and FIT files
// itself; this checks Fishing's:
//   1. every Fishing game event on every peer is a known type with every declared int field an int
//      (contracts/fishing_events.gd), so no client applied an event it doesn't know;
//   2. the host landed exactly one mackerel per rider (slots 0..n-1, one per rider peer);
//   3. the host and the client that stayed hold the same Fishing events in the same order; the
//      restarted client's events are a tail of the host's (it misses what came while it was down);
//   4. each rider's trip reaches the cool-down (phase 4) <= 135 s after its ride out started;
//   5. every applied directive was clamped only by the allowed rules (slew, floor, unverified,
//      rescue, coasting, haptic intensity, warm-up; switch_ramp, paused and haptic_pull noted),
//      never refused (a surge's haptic pull only for haptics off, warm-up, the haptic cooldown or an
//      unsafe rider), and is a Fishing request (an ERG pull, run or jump, or a surge's pull);
//      every trace row carries only allowed clamps;
//   6. every peer that reports an exit_reason ended "complete";
//   7. when fit_check's JSON is in the report, every FIT has 4 laps (ride out, Troll, Fight, cool-down).
// Exit 0 on pass, 1 on a failed check, 2 on usage or I/O errors.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { compareSequences } from '../../../tools/e2e/lib/checks.mjs';
import {
  SP,
  SPECIES,
  appliedProblems,
  clampProblems,
  eventErrors,
  fishingEvents,
  isObj,
  isSurge,
  requestShapeProblems,
  surgeProblems,
} from './sim/fishing_sim_lib.mjs';

export const ROLES = ['host', 'client1', 'client2'];
/** e2e_2min: ride out (0), Troll (1), Fight (2), Landing (3), cool-down (4). */
export const COOLDOWN_INDEX = 4;
export const TRIP_MAX_S = 135;
/** Wall-clock slack: e2e runs at --sim-speed=1 and stamps events in each peer's real time. */
export const TRIP_TOL_S = 2;
export const E2E_LAPS = 4;

const strip = (e) => {
  const { _t, ...rest } = e;
  return rest;
};

/** {role: {raw, fishing}} for every peer in the report (peers.<role>.events, else events_by_peer). */
export function peerLogs(report) {
  const out = {};
  const byPeer = isObj(report.events_by_peer) ? report.events_by_peer : {};
  for (const role of ROLES) {
    const p = report.peers?.[role];
    if (!p) continue;
    const list = Array.isArray(p.events) && p.events.length ? p.events : byPeer[String(p.peer_id)];
    const raw = Array.isArray(list) ? list : [];
    out[role] = { raw, fishing: fishingEvents(raw) };
  }
  if (Object.keys(out).length === 0) {
    Object.entries(byPeer).forEach(([k, list], i) => {
      const raw = Array.isArray(list) ? list : [];
      out[i === 0 ? 'host' : `peer_${k}`] = { raw, fishing: fishingEvents(raw) };
    });
  }
  return out;
}

/** The rider peers the host saw (phase_started peers), sorted. */
export function riderPeers(raw) {
  const s = new Set();
  for (const e of raw) if (isObj(e) && e.type === 'phase_started' && e.peer !== undefined) s.add(Number(e.peer));
  return [...s].filter((p) => p > 0).sort((a, b) => a - b);
}

/** Every applied directive record in the report: [{role, rec}]. */
export function directiveRecords(report) {
  if (Array.isArray(report.directives) && report.directives.length) return report.directives.map((d) => ({ role: d.peer_role ?? '?', rec: d }));
  const out = [];
  for (const role of ROLES) for (const d of report.peers?.[role]?.directives ?? []) out.push({ role, rec: d });
  return out;
}

export function checkReport(report) {
  const errors = [];
  const info = {};
  const logs = peerLogs(report);
  const roles = Object.keys(logs);
  if (roles.length === 0) return { ok: false, errors: ['no events in the report'], info };
  const err = (role, msg) => errors.push(`${role}: ${msg}`);
  const hostRole = logs.host ? 'host' : roles[0];
  const victim = report.victim ?? ROLES.find((r) => report.peers?.[r]?.restarted) ?? 'client2';

  // 1. schema.
  for (const role of roles) {
    for (const raw of logs[role].raw) {
      if (isObj(raw) && raw.type === 'game_event' && !(isObj(raw.event) && fishingEvents([raw]).length)) err(role, `applied unknown event ${JSON.stringify(raw.event?.type)}`);
    }
    const seen = new Set();
    for (const e of logs[role].fishing) {
      for (const m of eventErrors(e)) {
        if (!seen.has(m)) err(role, m);
        seen.add(m);
      }
    }
  }

  // 2. one mackerel per rider on the host.
  const host = logs[hostRole].fishing;
  const riders = riderPeers(logs[hostRole].raw);
  const nLanes = riders.length || 3;
  info.hostEvents = host.length;
  info.lanes = nLanes;
  for (let lane = 0; lane < nLanes; lane++) {
    const landed = host.filter((e) => e.type === 'landed' && e.l === lane);
    if (landed.length !== 1 || landed[0].sp !== SP.mackerel) err(hostRole, `lane ${lane} landed ${landed.map((e) => SPECIES[e.sp] ?? e.sp).join(', ') || 'nothing'} (wanted one mackerel)`);
  }

  // 3. identical events; the restarted client holds a tail.
  const hostSeq = host.map(strip);
  for (const role of roles) {
    if (role === hostRole || role === victim) continue;
    const cmp = compareSequences(hostSeq, logs[role].fishing.map(strip));
    if (!cmp.ok) err(role, `Fishing events differ from the host's: ${cmp.detail}`);
  }
  if (logs[victim] && victim !== hostRole) {
    const v = logs[victim].fishing.map(strip);
    info.victimEvents = v.length;
    if (v.length > hostSeq.length) err(victim, `${v.length} Fishing events, more than the host's ${hostSeq.length}`);
    else if (v.length) {
      const cmp = compareSequences(hostSeq.slice(hostSeq.length - v.length), v);
      if (!cmp.ok) err(victim, `its events are not a tail of the host's: ${cmp.detail}`);
    }
  }

  // 4. the trip reaches the cool-down within 135 s.
  for (const peer of riders) {
    const starts = logs[hostRole].raw.filter((e) => isObj(e) && e.type === 'phase_started' && Number(e.peer) === peer);
    const t0 = starts.find((e) => Number(e.index) === 0);
    const cd = starts.find((e) => Number(e.index) === COOLDOWN_INDEX);
    if (!t0 || !cd) err(hostRole, `rider ${peer} never reached the cool-down (phase ${COOLDOWN_INDEX})`);
    else if (Number(cd.t) - Number(t0.t) > TRIP_MAX_S + TRIP_TOL_S) err(hostRole, `rider ${peer} reached the cool-down ${(Number(cd.t) - Number(t0.t)).toFixed(1)} s after the ride out (<= ${TRIP_MAX_S})`);
  }

  // 5. directives and trace clamps.
  const recs = directiveRecords(report);
  info.directives = recs.length;
  for (const { role, rec } of recs) {
    if (rec.kind !== undefined && rec.kind !== 'request') continue;
    const at = `directive ${rec.id}`;
    const surge = { accepted: rec.refused !== true, reason: rec.reason, applied: rec };
    const probs = isSurge(rec.requested) ? surgeProblems(surge).probs : appliedProblems(rec);
    for (const m of probs) err(role, `${at}: ${m}`);
    for (const m of requestShapeProblems(rec.requested)) err(role, `${at}: ${m}`);
  }
  for (const role of ROLES) {
    const rows = report.peers?.[role]?.trace ?? [];
    let n = 0;
    for (const row of rows) {
      const p = clampProblems(row?.clamped_by);
      if (p.length && n++ < 2) err(role, `trace at ${row.t} s: ${p.join('; ')}`);
    }
  }

  // 6. exit reasons.
  for (const role of roles) {
    const x = report.peers?.[role]?.exit_reason;
    if (x !== undefined && x !== 'complete') err(role, `exit_reason ${JSON.stringify(x)}, wanted "complete"`);
  }

  // 7. FIT laps.
  for (const role of roles) {
    const files = report.fit_check?.[role]?.json?.files;
    if (!Array.isArray(files)) continue;
    for (const f of files) if (Array.isArray(f.laps) && f.laps.length !== E2E_LAPS) err(role, `${f.laps.length} FIT laps, wanted ${E2E_LAPS} (ride out, Troll, Fight, cool-down)`);
  }
  return { ok: errors.length === 0, errors, info };
}

export function main(argv, out = process.stdout, errOut = process.stderr) {
  const file = argv[0];
  if (!file) {
    errOut.write('usage: node tests/games/fishing/e2e_check.mjs <report.json>\n');
    return 2;
  }
  let report;
  try {
    report = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    errOut.write(`e2e_check fishing: cannot read ${file}: ${e.message}\n`);
    return 2;
  }
  const v = checkReport(report);
  if (v.ok) {
    out.write(`e2e_check fishing: PASS (${v.info.hostEvents} Fishing events on the host, ${v.info.lanes} lanes, ${v.info.directives} directives)\n`);
    return 0;
  }
  for (const e of v.errors) out.write(`e2e_check fishing: FAIL ${e}\n`);
  return 1;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(self)) {
  process.exitCode = main(process.argv.slice(2));
}
