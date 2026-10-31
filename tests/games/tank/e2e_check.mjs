#!/usr/bin/env node
// tests/games/tank/e2e_check.mjs: Tank's own check of an e2e report (GAME_SDK 19.4, BRIEF 7.7).
//
//   node tests/games/tank/e2e_check.mjs build/e2e/tank/report.json
//
// tools/e2e/run.mjs runs it after playing Tank's e2e content, the drill (a 30 s depot, a 70 s
// skirmish against two light tanks and a medium, a 30 s checkpoint, then the cool-down) with a
// host and two clients (a crew of 3 on the v3 landship), Autopilot and mock trainers; client2 is killed at about 25 s
// and rejoins. The harness checks the generic things (same shared events on every peer, final
// state, directives, warm-up limits, FIT files); this checks Tank's:
//   1. every Tank game event, on every peer, is a known type with every declared field the right
//      type (the schema of contracts/tank_events.gd: whole numbers, rotation rows of two), so no
//      client applied an event it does not know and no int travelled as a float or a string;
//   2. the host and the client that stayed hold the same Tank events in the same order, and the
//      rejoined client's events are a tail of that sequence;
//   3. the drill's story: the group's segments come once each, in order (depot, skirmish,
//      checkpoint, then the cool-down's own event if the rules send one); nothing a WARMUP phase forbids happens (no Ram, dodge
//      (v2 never emits them), no successful evade (nobody can evade in WARMUP), boss event
//      or overrun, no haptic directive); no more kills than the skirmish has tanks, none twice;
//      every repair follows a breakdown; no hit or kill in the depot; no rotation event (v3
//      retired rotation; the name stays reserved); seat moves (v3) carry known seats; no tank loss, restart or
//      near threat (v4: the drill is a warm-up, so its hull cannot be lost, and it has no recon car or tankette);
//   4. every peer's final snapshot is a well-formed Tank snapshot (the schema of
//      contracts/tank_snapshot_schema.gd, whole numbers, at most 4 KB, three riders and the
//      landship's six rooms) and matches the host's within 2%;
//   5. no push_error or script error on any peer (killed run included), no desync warning, every
//      peer finished complete;
//   6. when fit_check's JSON is in the report, every FIT has the drill's 4 laps.
// Zero dependencies besides tools/e2e/lib/checks.mjs. Exit 0 on pass, 1 on a failed check, 2 on
// usage or I/O errors.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { compareSequences, deepDiff } from '../../../tools/e2e/lib/checks.mjs';

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isInt = (v) => Number.isInteger(v) || (typeof v === 'number' && Number.isFinite(v) && Math.floor(v) === v);

/** Tank's event types (TankEvents.TYPES). */
export const EVENT_TYPES = [
  'segment', 'rotation', 'shot', 'hit', 'kill', 'ram', 'dodge', 'breakdown', 'repaired', 'overrun', 'boss_phase', 'latch', 'lever',
  'evade', 'turn', 'time_up', 'seat', 'tank_lost', 'stage_restart', 'ambush', 'escaped', 'splash',
];
/** Declared int fields per type (TankEvents.INT_FIELDS; "r[][]" is rows of ints). */
export const INT_FIELDS = {
  segment: ['i', 'sg', 'st'],
  rotation: ['r[][]'],
  shot: ['s', 'sh', 'id', 'src', 'e', 'rng_m'],
  hit: ['on', 'id', 'dmg', 'sh', 'b', 'x'],
  kill: ['id', 'e', 'by', 's'],
  ram: ['s', 'ok', 'id'],
  dodge: ['s'],
  breakdown: [],
  repaired: ['hp'],
  overrun: ['sg', 'st'],
  boss_phase: ['p'],
  latch: ['s', 'sh'],
  lever: ['s', 'lv'],
  evade: ['id', 'e', 'ok', 's'],
  turn: ['s', 'dir'],
  time_up: [],
  seat: ['s', 'from', 'to'],
  tank_lost: ['n', 'sg', 'st'],
  stage_restart: ['sg', 'st', 'hp'],
  ambush: ['id', 'e'],
  escaped: ['id', 'e'],
  splash: ['r', 'sh', 'f'],
};
/** Segment codes (TankIds.SEG_CODES). */
export const SEG = { none: 0, depot: 1, advance: 2, gun_line: 3, checkpoint: 4, boss: 5, skirmish: 6, cooldown: 7 };
/** The drill's group segments in order: index, code, stage (the cool-down's event is optional). */
export const DRILL_SEGMENTS = [
  { i: 0, sg: SEG.depot, st: 0 },
  { i: 1, sg: SEG.skirmish, st: 1 },
  { i: 2, sg: SEG.checkpoint, st: 1 },
  { i: 3, sg: SEG.cooldown, st: 0 },
];
/** The drill's enemies: 2 light tanks and a medium, all at scale 1.0 (v3: one tank). */
export const DRILL_ENEMIES = 3;
export const DRILL_LAPS = 4;
export const SNAPSHOT_MAX_BYTES = 4096;
const CREW3 = { tank: 5, riders: 3, rooms: 6 };
const ENEMY_CODES = [1, 2, 3, 4, 5, 6, 7, 8];
const SNAPSHOT_KEYS = ['v', 'tick', 'sg', 'tk', 'r', 'st', 'e', 's', 'o', 'gl', 'b', 'sc'];
/** Column counts of TankSnapshotSchema. */
export const SNAPSHOT_WIDTHS = { sg: 5, tk: 18, gl: 4, b: 8, sc: 5 };
export const ROW_WIDTHS = { r: 9, st: 9, e: 9, s: 10, o: 5 };
const ROLES = ['host', 'client1', 'client2'];
const COMBAT = new Set(['hit', 'kill']);

/** The Tank game event in a report entry (a game_event wrapper, or a raw event), else null. */
export function asTankEvent(x) {
  if (!isObj(x)) return null;
  if (x.type === 'game_event' && isObj(x.event)) return x.event;
  if (EVENT_TYPES.includes(x.type)) return x;
  return null;
}

/** Every Tank game event of one peer's event list, in order. */
export function tankEvents(list) {
  return (Array.isArray(list) ? list : []).map(asTankEvent).filter((e) => e !== null);
}

/** Problems with one Tank event (the schema of contracts/tank_events.gd and sane ranges). */
export function eventErrors(e) {
  const errs = [];
  const type = String(e.type);
  if (!EVENT_TYPES.includes(type)) return [`unknown event type ${JSON.stringify(e.type)}`];
  for (const f of INT_FIELDS[type]) {
    const key = f.replace(/(\[\])+$/, '');
    if (!(key in e)) {
      errs.push(`${type}: missing ${key}`);
      continue;
    }
    if (f === 'r[][]') {
      const rows = e[key];
      if (!Array.isArray(rows) || rows.length === 0 || !rows.every((r) => Array.isArray(r) && r.length === 2 && r.every(isInt))) {
        errs.push(`${type}: ${key} is not rows of two ints (${JSON.stringify(rows)})`);
      }
    } else if (!isInt(e[key])) errs.push(`${type}: ${key} is not an int (${JSON.stringify(e[key])})`);
  }
  // v4: a far shot's flight time, the one event number that is not whole (TankEvents.FLOAT_FIELDS).
  if (type === 'shot' && 'flight_s' in e && !(typeof e.flight_s === 'number' && e.flight_s > 0)) {
    errs.push(`shot: flight_s is not a positive number (${JSON.stringify(e.flight_s)})`);
  }
  if (errs.length) return errs;
  const inRange = (name, v, lo, hi) => {
    if (v < lo || v > hi) errs.push(`${type}: ${name} ${v} outside ${lo}..${hi}`);
  };
  switch (type) {
    case 'segment':
      inRange('i', e.i, 0, 99);
      inRange('sg', e.sg, 1, 7);
      inRange('st', e.st, 0, 4);
      break;
    case 'rotation':
      for (const [slot, engine] of e.r) {
        inRange('slot', slot, 0, 2);
        inRange('engine', engine, 1, 6);
      }
      break;
    case 'shot':
      inRange('s', e.s, -1, 2);
      inRange('sh', e.sh, 1, 6);
      inRange('id', e.id, 1, 1e9);
      inRange('src', e.src, 0, 1e9);
      inRange('e', e.e, 0, 8);
      break;
    case 'hit':
      inRange('on', e.on, 0, 3);
      inRange('dmg', e.dmg, 0, 1000);
      inRange('sh', e.sh, 1, 6);
      inRange('b', e.b, 0, 1000);
      break;
    case 'kill':
      inRange('id', e.id, 1, 1e9);
      inRange('e', e.e, 1, 8);
      inRange('by', e.by, 0, 3);
      inRange('s', e.s, -1, 2);
      break;
    case 'ram':
      inRange('s', e.s, 0, 2);
      inRange('ok', e.ok, 0, 1);
      break;
    case 'dodge':
      inRange('s', e.s, 0, 2);
      break;
    case 'evade':
      inRange('e', e.e, 1, 8);
      inRange('ok', e.ok, 0, 1);
      inRange('s', e.s, -1, 3);
      break;
    case 'repaired':
      inRange('hp', e.hp, 1, 1000);
      break;
    case 'overrun':
      inRange('sg', e.sg, 1, 7);
      inRange('st', e.st, 0, 4);
      break;
    case 'boss_phase':
      inRange('p', e.p, 1, 4);
      break;
    case 'latch':
      inRange('s', e.s, 0, 2);
      inRange('sh', e.sh, 1, 3);
      break;
    case 'lever':
      inRange('s', e.s, 0, 2);
      inRange('lv', e.lv, 0, 2);
      break;
    case 'seat':
      inRange('s', e.s, 0, 3);
      inRange('from', e.from, 1, 7);
      inRange('to', e.to, 1, 7);
      break;
    case 'tank_lost':
      inRange('n', e.n, 1, 99);
      inRange('sg', e.sg, 1, 8);
      inRange('st', e.st, 0, 4);
      break;
    case 'stage_restart':
      inRange('sg', e.sg, 1, 8);
      inRange('st', e.st, 0, 4);
      inRange('hp', e.hp, 1, 1000);
      break;
    case 'ambush':
    case 'escaped':
      inRange('e', e.e, 7, 8);
      break;
    case 'splash':
      inRange('r', e.r, 0, 3000);
      inRange('f', e.f, 0, 1);
      break;
    default:
      break;
  }
  return errs;
}

/** Problems with a Tank snapshot (null or not an object is one). */
export function snapshotErrors(snap, { crew = null } = {}) {
  if (!isObj(snap)) return ['no snapshot object'];
  const errs = [];
  for (const k of SNAPSHOT_KEYS) if (!(k in snap)) errs.push(`snapshot: missing ${k}`);
  if (errs.length) return errs;
  for (const [k, n] of Object.entries(SNAPSHOT_WIDTHS)) {
    if (!Array.isArray(snap[k]) || snap[k].length !== n) errs.push(`snapshot.${k}: needs ${n} columns`);
  }
  for (const [k, n] of Object.entries(ROW_WIDTHS)) {
    if (!Array.isArray(snap[k])) errs.push(`snapshot.${k}: not an array of rows`);
    else if (!snap[k].every((r) => Array.isArray(r) && r.length === n)) errs.push(`snapshot.${k}: a row needs ${n} columns`);
  }
  const bad = [];
  const walk = (node, at) => {
    if (Array.isArray(node)) node.forEach((x, i) => walk(x, `${at}[${i}]`));
    else if (isObj(node)) Object.entries(node).forEach(([k, x]) => walk(x, `${at}.${k}`));
    else if (!isInt(node)) bad.push(`${at}=${JSON.stringify(node)}`);
  };
  walk(snap, 'snapshot');
  if (bad.length) errs.push(`snapshot: not whole numbers: ${bad.slice(0, 3).join(', ')}`);
  const bytes = Buffer.byteLength(JSON.stringify(snap), 'utf8');
  if (bytes > SNAPSHOT_MAX_BYTES) errs.push(`snapshot: ${bytes} bytes, over ${SNAPSHOT_MAX_BYTES}`);
  if (Array.isArray(snap.e) && snap.e.length > 16) errs.push(`snapshot: ${snap.e.length} enemies, over 16`);
  if (Array.isArray(snap.s) && snap.s.length > 24) errs.push(`snapshot: ${snap.s.length} shells, over 24`);
  if (Array.isArray(snap.e) && !snap.e.every((r) => ENEMY_CODES.includes(r[1]))) errs.push('snapshot: an enemy with an unknown code');
  if (crew && !errs.length) {
    if (snap.tk[0] !== crew.tank) errs.push(`snapshot: tank code ${snap.tk[0]}, wanted ${crew.tank}`);
    if (snap.r.length !== crew.riders) errs.push(`snapshot: ${snap.r.length} riders, wanted ${crew.riders}`);
    if (snap.st.length !== crew.rooms) errs.push(`snapshot: ${snap.st.length} rooms, wanted ${crew.rooms}`);
  }
  return errs;
}

/** Order and content problems of the Tank events of one full drill run (host or unrestarted client). */
export function drillErrors(events, { tail = false } = {}) {
  const errs = [];
  const segs = events.filter((e) => e.type === 'segment');
  if (!tail) {
    // The group's segments, once each and in order; the cool-down's own event is optional.
    const got = segs.map((e) => [e.i, e.sg, e.st]);
    const want = DRILL_SEGMENTS.slice(0, 3).map((s) => [s.i, s.sg, s.st]);
    const head = got.slice(0, 3);
    const coolOk = got.length === 3 || (got.length === 4 && got[3][0] === 3 && got[3][1] === SEG.cooldown);
    if (!coolOk || JSON.stringify(head) !== JSON.stringify(want)) {
      errs.push(`segments ${JSON.stringify(got)}, wanted [index, code, stage] ${JSON.stringify(want)} once each, in order, then optionally the cool-down (3, ${SEG.cooldown})`);
    }
  } else {
    const idx = segs.map((e) => e.i);
    if (idx.some((v, k) => k > 0 && v <= idx[k - 1])) errs.push(`segments out of order: ${JSON.stringify(idx)}`);
    if (new Set(idx).size !== idx.length) errs.push(`a segment twice: ${JSON.stringify(idx)}`);
  }
  for (const t of ['ram', 'dodge', 'boss_phase', 'overrun', 'rotation', 'tank_lost', 'stage_restart', 'ambush', 'escaped']) {
    const n = events.filter((e) => e.type === t).length;
    if (n > 0) errs.push(`${n} ${t} event(s) in the drill (a WARMUP-only session with no boss and no near threats; v3 has no rotation)`);
  }
  const evaded = events.filter((e) => e.type === 'evade' && e.ok === 1).length;
  if (evaded > 0) errs.push(`${evaded} evaded shot(s) in the drill (nobody can evade in a WARMUP phase)`);
  const kills = events.filter((e) => e.type === 'kill');
  if (kills.length > DRILL_ENEMIES) errs.push(`${kills.length} kills, the skirmish has ${DRILL_ENEMIES} tanks`);
  const ids = new Set();
  for (const k of kills) {
    if (ids.has(k.id)) errs.push(`enemy ${k.id} killed twice`);
    ids.add(k.id);
  }
  let broken = 0;
  let fixed = 0;
  for (const e of events) {
    if (e.type === 'breakdown') broken += 1;
    if (e.type === 'repaired') {
      fixed += 1;
      if (fixed > broken && !tail) errs.push('repaired without a breakdown before it');
    }
  }
  // Nothing is hit or killed in the depot: the drill puts no enemy there. (A shell may latch there:
  // v3, the Loader stows shells into the ready rack.)
  let seg = tail ? -1 : null;
  for (const e of events) {
    if (e.type === 'segment') seg = e.i;
    else if (COMBAT.has(e.type) && seg === 0) errs.push(`${e.type} in the depot (no enemies there)`);
  }
  return errs;
}

/** The Tank events of every peer role in a report: {role: {tank, raw}}. */
export function peerEvents(report) {
  const out = {};
  const byPeer = isObj(report.events_by_peer) ? report.events_by_peer : {};
  for (const role of ROLES) {
    const p = report.peers?.[role];
    if (!p) continue;
    const list = Array.isArray(p.events) && p.events.length ? p.events : byPeer[String(p.peer_id)];
    out[role] = { tank: tankEvents(list), raw: Array.isArray(list) ? list : [] };
  }
  if (Object.keys(out).length === 0) {
    Object.entries(byPeer).forEach(([k, list], i) => {
      out[i === 0 ? 'host' : `peer_${k}`] = { tank: tankEvents(list), raw: Array.isArray(list) ? list : [] };
    });
  }
  return out;
}

export function checkReport(report) {
  const errors = [];
  const info = {};
  const logs = peerEvents(report);
  const roles = Object.keys(logs);
  if (roles.length === 0) return { ok: false, errors: ['no events in the report'], info };
  const drill = (report.content_id ?? 'drill') === 'drill';
  const victim = report.victim ?? (ROLES.find((r) => report.peers?.[r]?.restarted) ?? 'client2');
  const err = (role, msg) => errors.push(`${role}: ${msg}`);
  const hostRole = logs.host ? 'host' : roles[0];

  // 1. schema of every Tank event, and wrappers with unknown types.
  for (const role of roles) {
    for (const raw of logs[role].raw) {
      if (isObj(raw) && raw.type === 'game_event') {
        const t = isObj(raw.event) ? raw.event.type : undefined;
        if (!EVENT_TYPES.includes(t)) err(role, `applied unknown event type ${JSON.stringify(t)}`);
      }
    }
    const seen = new Set();
    for (const e of logs[role].tank) {
      for (const m of eventErrors(e)) {
        if (!seen.has(m)) err(role, m);
        seen.add(m);
      }
    }
  }

  // 2. the same events in the same order on the host and every unrestarted client; the victim holds a tail.
  const host = logs[hostRole].tank;
  if (host.length === 0) err(hostRole, 'no Tank game events');
  info.hostEvents = host.length;
  const full = roles.filter((r) => r !== hostRole && r !== victim);
  for (const role of full) {
    const cmp = compareSequences(host, logs[role].tank);
    if (!cmp.ok) err(role, `Tank events differ from the host's: ${cmp.detail}`);
  }
  if (logs[victim] && victim !== hostRole) {
    const v = logs[victim].tank;
    info.victimEvents = v.length;
    if (v.length === 0) err(victim, 'the restarted client recorded no Tank events');
    else if (v.length > host.length) err(victim, `${v.length} events, more than the host's ${host.length}`);
    else {
      const cmp = compareSequences(host.slice(host.length - v.length), v);
      if (!cmp.ok) err(victim, `its events are not a tail of the host's: ${cmp.detail}`);
    }
  }

  // 3. the drill's story.
  if (drill) {
    for (const role of roles) {
      for (const m of drillErrors(logs[role].tank, { tail: role === victim && roles.length > 1 })) err(role, m);
    }
    const haptics = (report.directives ?? []).filter((d) => d?.requested?.source === 'tank' && d?.requested?.haptic !== undefined);
    if (haptics.length) errors.push(`${haptics.length} Tank haptic directive(s) in the drill (every phase lies in the first 300 s)`);
  }

  // 4. final snapshots.
  const finals = {};
  for (const role of roles) finals[role] = report.peers?.[role]?.final_state?.snapshot;
  for (const role of roles) {
    if (finals[role] === undefined) {
      err(role, 'no final snapshot');
      continue;
    }
    for (const m of snapshotErrors(finals[role], { crew: drill ? CREW3 : null })) err(role, m);
  }
  if (isObj(finals[hostRole])) {
    info.snapshotBytes = Buffer.byteLength(JSON.stringify(finals[hostRole]), 'utf8');
    for (const role of roles) {
      if (role === hostRole || !isObj(finals[role])) continue;
      const diffs = deepDiff(finals[hostRole], finals[role], { relTol: 0.02, absTol: 0.01, limit: 5 });
      if (diffs.length) err(role, `final snapshot differs from the host's by more than 2%: ${diffs.map((d) => `${d.path} ${JSON.stringify(d.a)} vs ${JSON.stringify(d.b)}`).join('; ')}`);
    }
  }

  // 5. errors, desyncs and the ending.
  for (const role of roles) {
    const p = report.peers?.[role];
    if (!p) continue;
    if (Number(p.script_errors) > 0) err(role, `report.script_errors = ${p.script_errors}`);
    if (Number(p.log_error_count) > 0) err(role, `${p.log_error_count} error line(s) in its log (a push_error?), first: ${(p.log_errors ?? [])[0]}`);
    for (const e of p.earlier_runs ?? []) if ((e.log_errors ?? []).length) err(role, `killed run: ${e.log_errors.length} error line(s), first: ${e.log_errors[0]}`);
    if (Number(p.desync_warnings) > 0) err(role, `${p.desync_warnings} desync warning(s)`);
    const x = p.exit_reason;
    if (x !== undefined && x !== null && x !== 'complete') err(role, `exit_reason ${JSON.stringify(x)}, wanted "complete"`);
  }
  const finished = (role) => logs[role].raw.filter((e) => isObj(e) && (e.type === 'finished' || e.type === 'game_finished' || e.type === 'wl.finished'));
  for (const role of roles) {
    for (const f of finished(role)) {
      const want = drill ? ['complete'] : ['victory', 'withdrawn'];
      if (!want.includes(f.reason)) err(role, `finished with reason ${JSON.stringify(f.reason)}, wanted ${want.join(' or ')}`);
    }
  }
  if (finished(hostRole).length === 0 && report.peers?.[hostRole]?.exit_reason !== 'complete') err(hostRole, 'no finished event');

  // 6. FIT laps.
  if (drill) {
    for (const role of roles) {
      const files = report.fit_check?.[role]?.json?.files;
      if (!Array.isArray(files)) continue;
      for (const f of files) {
        if (Array.isArray(f.laps) && f.laps.length !== DRILL_LAPS) err(role, `${f.laps.length} FIT laps, wanted ${DRILL_LAPS} (one per phase and the cool-down)`);
      }
    }
  }
  return { ok: errors.length === 0, errors, info };
}

export function main(argv, out = process.stdout, errStream = process.stderr) {
  const file = argv[0];
  if (!file) {
    errStream.write('usage: node tests/games/tank/e2e_check.mjs <report.json>\n');
    return 2;
  }
  let report;
  try {
    report = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    errStream.write(`e2e_check tank: cannot read ${file}: ${err.message}\n`);
    return 2;
  }
  const v = checkReport(report);
  if (v.ok) {
    out.write(`e2e_check tank: PASS (${v.info.hostEvents} Tank events on the host, final snapshot ${v.info.snapshotBytes ?? '?'} bytes)\n`);
    return 0;
  }
  for (const e of v.errors) out.write(`e2e_check tank: FAIL ${e}\n`);
  return 1;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(self)) {
  process.exitCode = main(process.argv.slice(2));
}
