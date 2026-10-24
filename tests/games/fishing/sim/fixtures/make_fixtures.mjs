#!/usr/bin/env node
// tests/games/fishing/sim/fixtures/make_fixtures.mjs: the synthetic tools/e2e report of e2e_2min
// that e2e_check.test.mjs checks (GAME_SDK 19.4 layout, Fishing events from fishing_events.gd).
//
//   node tests/games/fishing/sim/fixtures/make_fixtures.mjs     # rewrites e2e/report.json
//
// The test checks that the file on disk equals what this module builds, so edit the builder, then
// rerun it.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

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

export function writeAll(dir = here) {
  fs.mkdirSync(path.join(dir, 'e2e'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'e2e', 'report.json'), `${JSON.stringify(e2eReport(), null, 1)}
`);
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(self)) {
  writeAll();
  process.stdout.write(`fixtures written to ${here}
`);
}
