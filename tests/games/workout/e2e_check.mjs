#!/usr/bin/env node
// tests/games/workout/e2e_check.mjs: Workout's own check of an e2e report (BRIEF 3.6, 7.7).
//
//   node tests/games/workout/e2e_check.mjs build/e2e/workout/report.json
//
// tools/e2e/run.mjs runs it after playing Workout's e2e content (a 60 s ramp, 30 s at 65%,
// a 30 s sprint, then the cool-down). The harness itself checks that every peer saw the
// same events; this checks Workout's events: some peer's event log holds the whole session
// in order (interval starts and ends for phases 0-2, the sprint result for phase 2, the
// cool-down start as phase 3), and every Workout event anywhere is well formed (integer
// phase indices, rows of [peer, permille] or [peer, peak_w, best_ds, hit]). It reads any
// report layout: events may sit directly in an array or one level inside a wrapper object.
// Zero dependencies. Exit 0 on pass, 1 on a failed check, 2 on usage or I/O errors.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const TYPES = new Set(['interval_start', 'interval_end', 'sprint']);
export const EXPECTED = [
  ['interval_start', 0], ['interval_end', 0],
  ['interval_start', 1], ['interval_end', 1],
  ['interval_start', 2], ['interval_end', 2], ['sprint', 2],
  ['interval_start', 3],
];
const PHASES = 4; // e2e: 3 phases plus the appended cool-down

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/** The Workout event in `x` (itself, or one level inside a wrapper object), or null. */
export function asWorkoutEvent(x) {
  if (!isObj(x)) return null;
  if (TYPES.has(x.type) && 'i' in x) return x;
  for (const v of Object.values(x)) {
    if (isObj(v) && TYPES.has(v.type) && 'i' in v) return v;
  }
  return null;
}

/** Every array in the report that holds Workout events, as the ordered list of those events. */
export function collectStreams(report) {
  const streams = [];
  const walk = (node) => {
    if (Array.isArray(node)) {
      const evs = node.map(asWorkoutEvent).filter((e) => e !== null);
      if (evs.length > 0) streams.push(evs);
      node.forEach(walk);
    } else if (isObj(node)) {
      Object.values(node).forEach(walk);
    }
  };
  walk(report);
  return streams;
}

const isInt = (v) => Number.isInteger(v);

/** Problems with one event ([] when well formed). */
export function eventErrors(e) {
  const errs = [];
  if (!isInt(e.i) || e.i < 0 || e.i >= PHASES) errs.push(`${e.type}: phase index ${JSON.stringify(e.i)} is not 0..${PHASES - 1}`);
  if (e.type === 'interval_end' || e.type === 'sprint') {
    if (!Array.isArray(e.r) || e.r.length === 0) {
      errs.push(`${e.type} ${e.i}: no rider rows`);
      return errs;
    }
    for (const row of e.r) {
      const n = e.type === 'sprint' ? 4 : 2;
      if (!Array.isArray(row) || row.length !== n || !row.every(isInt)) {
        errs.push(`${e.type} ${e.i}: row ${JSON.stringify(row)} is not ${n} integers`);
        continue;
      }
      if (e.type === 'interval_end' && (row[1] < 0 || row[1] > 1000)) errs.push(`interval_end ${e.i}: permille ${row[1]} outside 0..1000`);
      if (e.type === 'sprint' && (row[1] < 0 || row[2] < 0 || (row[3] !== 0 && row[3] !== 1))) errs.push(`sprint ${e.i}: bad row ${JSON.stringify(row)}`);
    }
  }
  if (e.type === 'sprint' && e.i !== 2) errs.push(`sprint result for phase ${e.i}; e2e's sprint is phase 2`);
  return errs;
}

/** True if `stream` holds EXPECTED in order (other events may sit between). */
export function holdsSession(stream) {
  let k = 0;
  for (const e of stream) {
    if (k < EXPECTED.length && e.type === EXPECTED[k][0] && e.i === EXPECTED[k][1]) k += 1;
  }
  return k === EXPECTED.length;
}

export function checkReport(report) {
  const errors = [];
  const streams = collectStreams(report);
  if (streams.length === 0) {
    return { ok: false, errors: ['no Workout events in the report'], streams: 0 };
  }
  const seen = new Set();
  for (const s of streams) {
    for (const e of s) {
      for (const err of eventErrors(e)) seen.add(err);
    }
  }
  errors.push(...seen);
  if (!streams.some(holdsSession)) {
    errors.push(`no peer's event log holds the whole e2e session in order: ${EXPECTED.map(([t, i]) => `${t} ${i}`).join(', ')}`);
  }
  return { ok: errors.length === 0, errors, streams: streams.length };
}

export function main(argv) {
  const file = argv[0];
  if (!file) {
    process.stderr.write('usage: node tests/games/workout/e2e_check.mjs <report.json>\n');
    return 2;
  }
  let report;
  try {
    report = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    process.stderr.write(`e2e_check workout: cannot read ${file}: ${err.message}\n`);
    return 2;
  }
  const v = checkReport(report);
  if (v.ok) {
    process.stdout.write(`e2e_check workout: PASS (${v.streams} event logs)\n`);
    return 0;
  }
  for (const e of v.errors) process.stdout.write(`e2e_check workout: FAIL ${e}\n`);
  return 1;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(self)) {
  process.exitCode = main(process.argv.slice(2));
}
