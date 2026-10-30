#!/usr/bin/env node
// tests/games/siege/e2e_check.mjs: Siege's own check of an e2e report (BRIEF 3.6, 7.7).
//
//   node tests/games/siege/e2e_check.mjs build/e2e/siege/report.json
//
// tools/e2e/run.mjs runs it after playing Siege's e2e content, the drill (a 20 s build break,
// then wave 1 for 100 s at 60%, then the cool-down) with one host and two clients, one of which
// is killed and restarted. The harness itself checks that the shared events are identical on
// every peer, the directives, the warm-up limits and the FIT files; this checks Siege's events:
//   1. every Siege game event, on every peer, is a known type with every declared field the
//      right type (the same schema as contracts/siege_events.gd), so no client applied an event
//      it does not know and no int travelled as a float or a string;
//   2. the drill's wave plays in order on the host and on the client that stayed: exactly one
//      wave_start (ph 1, n 1, role wave, waves 1) and one wave_end (ph 1, n 1), the start first;
//      combat events (push, dock, reach, shot, kill, leak, breach, gate_restored, rush) only between them (a
//      gate_restored may follow wave_end when a Breach was still running: the 10 s clock ends
//      after the wave, in the cool-down);
//   3. the host and the unrestarted client hold the same Siege events in the same order, and the
//      restarted client's events are a tail of that sequence that still reaches wave_end;
//   4. finished arrives with "complete" wherever it was recorded, and on the host (the harness's
//      recorder keeps no `finished` event, so the peer's own exit_reason "complete" counts too);
//   5. Overdrive events are well formed (each start closed before the next one, per slot) and, in
//      the drill (a WARMUP-kind wave: no Overdrive), there are none and no Siege directive was
//      requested; no shield bearer appears in the drill's spearmen-and-chariots mix;
//   6. when fit_check's JSON is in the report, every FIT has the drill's 3 laps.
// Zero dependencies besides tools/e2e/lib/checks.mjs. Exit 0 on pass, 1 on a failed check, 2 on
// usage or I/O errors.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { compareSequences } from '../../../tools/e2e/lib/checks.mjs';

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isInt = (v) => Number.isInteger(v) || (typeof v === 'number' && Number.isFinite(v) && Math.floor(v) === v);

/** Siege's event types (SiegeIds.EVENT_TYPES). */
export const EVENT_TYPES = [
  'wave_start', 'wave_end', 'rush', 'push', 'dock', 'reach', 'shot', 'kill', 'leak', 'breach', 'gate_restored', 'buy', 'route', 'overdrive',
];
/** Declared int fields per type (SiegeEvents.INT_FIELDS; "name[]" is an array of ints). */
export const INT_FIELDS = {
  wave_start: ['ph', 'n', 'waves', 'b'],
  wave_end: ['ph', 'n', 'hp', 'max', 'leaks'],
  rush: ['on', 'i'],
  push: ['id', 'et', 'prog_dm'],
  dock: ['id'],
  reach: ['id', 'et'],
  shot: ['tk', 'src', 'kind', 'o[]', 'v[]', 'n', 'sd'],
  kill: ['id', 'et', 'src', 'x2'],
  leak: ['id', 'et', 'dmg'],
  breach: ['n'],
  gate_restored: ['hp'],
  buy: ['slot', 'station', 'pad', 'ok', 'lvl'],
  route: ['slot', 'to'],
  overdrive: ['slot', 'st', 'scored'],
};
export const STRING_FIELDS = { wave_start: ['role'], buy: ['item', 'why'], overdrive: ['why'] };
export const ITEMS = ['upgrade', 'mine', 'scorpion', 'pad_upgrade', 'iron_bands', 'repair', 'reserve_flywheel', 'aqueduct_drive', 'spare_cauldron'];
export const BUY_REASONS = ['closed', 'funds', 'pad_taken', 'no_pad', 'no_station', 'max_level', 'limit', 'gate_full'];
export const COMBAT_TYPES = new Set(['push', 'dock', 'reach', 'shot', 'kill', 'leak', 'breach', 'gate_restored', 'rush']);
export const ENEMY_SHIELD = 2;
export const DRILL = { ph: 1, n: 1, waves: 1, laps: 3 };
const ROLES = ['host', 'client1', 'client2'];

/** The Siege game event in a report entry (a game_event wrapper, or a raw event), else null. */
export function asSiegeEvent(x) {
  if (!isObj(x)) return null;
  if (x.type === 'game_event' && isObj(x.event)) return x.event;
  if (EVENT_TYPES.includes(x.type)) return x;
  return null;
}

/** Every Siege game event of one peer's event list, in order. */
export function siegeEvents(list) {
  return (Array.isArray(list) ? list : []).map(asSiegeEvent).filter((e) => e !== null);
}

/** Problems with one Siege event (the schema of contracts/siege_events.gd and sane ranges). */
export function eventErrors(e) {
  const errs = [];
  const type = String(e.type);
  if (!EVENT_TYPES.includes(type)) return [`unknown event type ${JSON.stringify(e.type)}`];
  for (const f of INT_FIELDS[type]) {
    const key = f.replace('[]', '');
    if (!(key in e)) {
      errs.push(`${type}: missing ${key}`);
      continue;
    }
    if (f.endsWith('[]')) {
      if (!Array.isArray(e[key]) || !e[key].every(isInt)) errs.push(`${type}: ${key} is not an array of ints (${JSON.stringify(e[key])})`);
    } else if (!isInt(e[key])) errs.push(`${type}: ${key} is not an int (${JSON.stringify(e[key])})`);
  }
  for (const f of STRING_FIELDS[type] ?? []) if (typeof e[f] !== 'string') errs.push(`${type}: ${f} is not a string`);
  if (errs.length) return errs;
  const inRange = (name, v, lo, hi) => {
    if (v < lo || v > hi) errs.push(`${type}: ${name} ${v} outside ${lo}..${hi}`);
  };
  const src = (v) => (v >= 1 && v <= 3) || (v >= 11 && v <= 14);
  switch (type) {
    case 'wave_start':
      inRange('ph', e.ph, 0, 99);
      inRange('n', e.n, 0, 10);
      inRange('b', e.b, 0, 1e6);
      break;
    case 'wave_end':
      inRange('hp', e.hp, 0, e.max);
      inRange('leaks', e.leaks, 0, 1e6);
      break;
    case 'rush':
      inRange('on', e.on, 0, 1);
      break;
    case 'push':
      inRange('et', e.et, 4, 5);
      inRange('prog_dm', e.prog_dm, 0, 4000);
      break;
    case 'reach':
      inRange('et', e.et, 4, 4);
      break;
    case 'shot':
      if (!src(e.src)) errs.push(`shot: src ${e.src} is not a station 1..3 or a pad 11..14`);
      inRange('kind', e.kind, 0, 3);
      inRange('n', e.n, 1, 12);
      if (e.o.length !== 3 || e.v.length !== 3) errs.push('shot: o and v need 3 numbers');
      break;
    case 'kill':
      inRange('et', e.et, 1, 5);
      if (e.src !== 0 && !src(e.src)) errs.push(`kill: src ${e.src} is not a station or a pad`);
      inRange('x2', e.x2, 0, 1);
      break;
    case 'leak':
      inRange('et', e.et, 1, 5);
      inRange('dmg', e.dmg, 0, 1000);
      break;
    case 'breach':
      inRange('n', e.n, 1, 99);
      break;
    case 'gate_restored':
      inRange('hp', e.hp, 1, 1000);
      break;
    case 'buy':
      inRange('slot', e.slot, 0, 7);
      inRange('ok', e.ok, 0, 1);
      if (!ITEMS.includes(e.item)) errs.push(`buy: unknown item ${JSON.stringify(e.item)}`);
      if (e.ok === 1 && e.why !== '') errs.push(`buy: ok with a refusal reason "${e.why}"`);
      if (e.ok === 0 && !BUY_REASONS.includes(e.why)) errs.push(`buy: refused with unknown reason "${e.why}"`);
      if (e.ok === 0 && e.lvl !== 0) errs.push(`buy: a refused buy has lvl ${e.lvl}`);
      inRange('station', e.station, 0, 4);
      inRange('pad', e.pad, 0, 4);
      break;
    case 'route':
      inRange('slot', e.slot, 0, 7);
      inRange('to', e.to, 0, 4);
      break;
    case 'overdrive':
      inRange('slot', e.slot, 0, 7);
      inRange('st', e.st, 0, 2);
      inRange('scored', e.scored, 0, 1);
      if (e.st === 2 && e.why === '') errs.push('overdrive: a refusal needs a reason');
      break;
    default:
      break;
  }
  return errs;
}

/** Overdrive events of `events` close properly: per slot a start (1) is followed by an end (0) or a refusal (2). */
export function overdrivePairing(events) {
  const errs = [];
  const open = new Set();
  for (const e of events) {
    if (e.type !== 'overdrive') continue;
    if (e.st === 1) {
      if (open.has(e.slot)) errs.push(`overdrive: slot ${e.slot} started twice without an end`);
      open.add(e.slot);
    } else if (e.st === 0 || e.st === 2) {
      if (e.st === 0 && !open.has(e.slot)) errs.push(`overdrive: slot ${e.slot} ended without a start`);
      open.delete(e.slot);
    }
  }
  return errs;
}

/**
 * Order problems of one full run of the drill's wave in `events` (the host's or an unrestarted
 * client's): `tail` true accepts a log that starts after wave_start (a restarted client).
 */
export function waveOrderErrors(events, { tail = false, drill = true } = {}) {
  const errs = [];
  const starts = events.map((e, i) => (e.type === 'wave_start' ? i : -1)).filter((i) => i >= 0);
  const ends = events.map((e, i) => (e.type === 'wave_end' ? i : -1)).filter((i) => i >= 0);
  if (starts.length > 1) errs.push(`${starts.length} wave_start events (the drill has one wave)`);
  if (ends.length !== 1) errs.push(`${ends.length} wave_end events (wanted exactly 1)`);
  if (!tail && starts.length !== 1) errs.push(`${starts.length} wave_start events (wanted exactly 1)`);
  const s = starts.length ? starts[0] : -1;
  const en = ends.length ? ends[0] : -1;
  if (s >= 0 && en >= 0 && s > en) errs.push('wave_end arrived before wave_start');
  if (drill) {
    if (s >= 0) {
      const w = events[s];
      if (w.ph !== DRILL.ph || w.n !== DRILL.n || w.role !== 'wave' || w.waves !== DRILL.waves) errs.push(`wave_start is ${JSON.stringify(w)}, wanted ph ${DRILL.ph}, n ${DRILL.n}, role wave, waves ${DRILL.waves}`);
    }
    if (en >= 0) {
      const w = events[en];
      if (w.ph !== DRILL.ph || w.n !== DRILL.n) errs.push(`wave_end is ph ${w.ph} n ${w.n}, wanted ph ${DRILL.ph} n ${DRILL.n}`);
    }
  }
  // A Breach still running at wave_end ends with a gate_restored after it (the 10 s clock goes on).
  // (a restarted client's tail may have missed the breach itself.)
  let breachOpen = tail;
  events.forEach((e, i) => {
    if (en < 0 || i <= en) {
      if (e.type === 'breach') breachOpen = true;
      else if (e.type === 'gate_restored') breachOpen = false;
    }
  });
  events.forEach((e, i) => {
    if (!COMBAT_TYPES.has(e.type)) return;
    if (s >= 0 && i < s) errs.push(`${e.type} before wave_start`);
    if (en >= 0 && i > en) {
      if (e.type === 'gate_restored' && breachOpen) {
        breachOpen = false;
        return;
      }
      errs.push(`${e.type} after wave_end (nothing spawns or fires after the wave)`);
    }
  });
  return errs;
}

/** The Siege events of every peer role in a report: {role: events[]}. */
export function peerEvents(report) {
  const out = {};
  const byPeer = isObj(report.events_by_peer) ? report.events_by_peer : {};
  for (const role of ROLES) {
    const p = report.peers?.[role];
    if (!p) continue;
    const list = Array.isArray(p.events) && p.events.length ? p.events : byPeer[String(p.peer_id)];
    out[role] = { siege: siegeEvents(list), raw: Array.isArray(list) ? list : [] };
  }
  if (Object.keys(out).length === 0) {
    const vals = Object.entries(byPeer);
    vals.forEach(([k, list], i) => {
      out[i === 0 ? 'host' : `peer_${k}`] = { siege: siegeEvents(list), raw: Array.isArray(list) ? list : [] };
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

  // 1. schema of every Siege event, and wrappers with unknown types.
  for (const role of roles) {
    for (const raw of logs[role].raw) {
      if (isObj(raw) && raw.type === 'game_event') {
        const t = isObj(raw.event) ? raw.event.type : undefined;
        if (!EVENT_TYPES.includes(t)) err(role, `applied unknown event type ${JSON.stringify(t)}`);
      }
    }
    const seen = new Set();
    for (const e of logs[role].siege) {
      for (const m of eventErrors(e)) {
        if (!seen.has(m)) err(role, m);
        seen.add(m);
      }
    }
    for (const m of overdrivePairing(logs[role].siege)) err(role, m);
  }

  // 2. the wave's order on the host and every unrestarted peer; the victim holds a tail.
  const host = logs.host?.siege ?? logs[roles[0]].siege;
  if (host.length === 0) err('host', 'no Siege game events');
  for (const role of roles) {
    for (const m of waveOrderErrors(logs[role].siege, { tail: role === victim && roles.length > 1, drill })) err(role, m);
  }
  info.hostEvents = host.length;

  // 3. the same events in the same order.
  const full = roles.filter((r) => r !== 'host' && r !== victim);
  for (const role of full) {
    const cmp = compareSequences(host, logs[role].siege);
    if (!cmp.ok) err(role, `Siege events differ from the host's: ${cmp.detail}`);
  }
  if (logs[victim] && victim !== 'host') {
    const v = logs[victim].siege;
    if (v.length === 0) err(victim, 'the restarted client recorded no Siege events');
    else {
      const cmp = compareSequences(host.slice(host.length - Math.min(v.length, host.length)), v);
      if (!cmp.ok || v.length > host.length) err(victim, `its events are not a tail of the host's: ${cmp.detail}`);
      if (!v.some((e) => e.type === 'wave_end')) err(victim, 'the restarted client never saw wave_end');
    }
  }

  // 4. finished complete.
  const finished = (role) => logs[role].raw.filter((e) => isObj(e) && (e.type === 'finished' || e.type === 'game_finished' || e.type === 'wl.finished'));
  const exitReason = (role) => report.peers?.[role]?.exit_reason;
  const hostRole = logs.host ? 'host' : roles[0];
  if (finished(hostRole).length === 0 && exitReason(hostRole) !== 'complete') err('host', 'no finished event');
  for (const role of roles) {
    for (const f of finished(role)) if (f.reason !== 'complete') err(role, `finished with reason ${JSON.stringify(f.reason)}, wanted "complete"`);
    const x = exitReason(role);
    if (x !== undefined && x !== 'complete') err(role, `exit_reason ${JSON.stringify(x)}, wanted "complete"`);
  }

  // 5. the drill has no Overdrive and no Siege directive, and no shield bearer.
  if (drill) {
    for (const role of roles) {
      if (logs[role].siege.some((e) => e.type === 'overdrive')) err(role, 'an overdrive event in the drill (a WARMUP wave allows none)');
      if (logs[role].siege.some((e) => (e.type === 'kill' || e.type === 'leak') && e.et === ENEMY_SHIELD)) err(role, 'a shield bearer in the drill (spearmen and chariots only)');
    }
    const od = (report.directives ?? []).filter((d) => d?.requested?.source === 'siege' || d?.requested?.reason === 'overdrive');
    if (od.length) errors.push(`${od.length} Siege directives in the drill (it sends none)`);
  }

  // 6. FIT laps.
  if (drill) {
    for (const role of roles) {
      const files = report.fit_check?.[role]?.json?.files;
      if (!Array.isArray(files)) continue;
      for (const f of files) {
        if (Array.isArray(f.laps) && f.laps.length !== DRILL.laps) err(role, `${f.laps.length} FIT laps, wanted ${DRILL.laps} (one per phase and the cool-down)`);
      }
    }
  }
  return { ok: errors.length === 0, errors, info };
}

export function main(argv) {
  const file = argv[0];
  if (!file) {
    process.stderr.write('usage: node tests/games/siege/e2e_check.mjs <report.json>\n');
    return 2;
  }
  let report;
  try {
    report = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    process.stderr.write(`e2e_check siege: cannot read ${file}: ${err.message}\n`);
    return 2;
  }
  const v = checkReport(report);
  if (v.ok) {
    process.stdout.write(`e2e_check siege: PASS (${v.info.hostEvents} Siege events on the host)\n`);
    return 0;
  }
  for (const e of v.errors) process.stdout.write(`e2e_check siege: FAIL ${e}\n`);
  return 1;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(self)) {
  process.exitCode = main(process.argv.slice(2));
}
