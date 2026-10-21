// node --test tests/games/workout/e2e_check.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { checkReport, collectStreams, asWorkoutEvent, main } from './e2e_check.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const peers = [1, 2, 3];

function session() {
  const rows = (v) => peers.map((p) => [p, v]);
  return [
    { type: 'interval_start', i: 0 },
    { type: 'interval_end', i: 0, r: rows(1000) },
    { type: 'interval_start', i: 1 },
    { type: 'interval_end', i: 1, r: rows(980) },
    { type: 'interval_start', i: 2 },
    { type: 'interval_end', i: 2, r: rows(1000) },
    { type: 'sprint', i: 2, r: peers.map((p) => [p, 180, 0, 0]) },
    { type: 'interval_start', i: 3 },
  ];
}

test('a host and two clients with the whole session pass', () => {
  const report = {
    peers: [
      { role: 'host', events: [{ t: 0, type: 'session_state', state: 'running' }, ...session()] },
      { role: 'client', events: session() },
      { role: 'client', events: session() },
    ],
  };
  const v = checkReport(report);
  assert.equal(v.ok, true, v.errors.join('\n'));
  assert.equal(v.streams, 3);
});

test('wrapped events and a restarted client with a partial log pass', () => {
  const wrapped = session().map((e, k) => ({ t: k, type: 'game_event', event: e }));
  const report = { events: { host: wrapped, restarted: session().slice(5).map((e) => ({ data: e })) } };
  assert.equal(checkReport(report).ok, true);
  assert.equal(collectStreams(report).length, 2);
});

test('a missing sprint result fails', () => {
  const s = session().filter((e) => e.type !== 'sprint');
  const v = checkReport({ events: s });
  assert.equal(v.ok, false);
  assert.match(v.errors.join('\n'), /whole e2e session/);
});

test('malformed rows and indices fail', () => {
  const s = session();
  s[1] = { type: 'interval_end', i: 0, r: [[1, 1000.5]] };
  s[6] = { type: 'sprint', i: 2, r: [[1, 300, 20, 2]] };
  s.push({ type: 'interval_start', i: 9 });
  const v = checkReport({ events: s });
  assert.equal(v.ok, false);
  const text = v.errors.join('\n');
  assert.match(text, /is not 2 integers/);
  assert.match(text, /bad row/);
  assert.match(text, /phase index 9/);
});

test('a report without Workout events fails', () => {
  assert.equal(checkReport({ events: [{ type: 'phase_started', peer: 1, index: 0 }] }).ok, false);
  assert.equal(asWorkoutEvent({ type: 'interval_start' }), null, 'needs an index');
});

test('the command line', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'workout-e2e-'));
  const good = path.join(dir, 'good.json');
  const bad = path.join(dir, 'bad.json');
  fs.writeFileSync(good, JSON.stringify({ events: session() }));
  fs.writeFileSync(bad, JSON.stringify({ events: [] }));
  const script = path.join(here, 'e2e_check.mjs');
  const ok = spawnSync(process.execPath, [script, good], { encoding: 'utf8' });
  assert.equal(ok.status, 0, ok.stdout + ok.stderr);
  assert.match(ok.stdout, /PASS/);
  const fail = spawnSync(process.execPath, [script, bad], { encoding: 'utf8' });
  assert.equal(fail.status, 1);
  assert.match(fail.stdout, /FAIL/);
  assert.equal(main([]), 2);
  assert.equal(main([path.join(dir, 'missing.json')]), 2);
  fs.rmSync(dir, { recursive: true, force: true });
});
