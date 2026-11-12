// SPEC_AUDIO 6.2: the scorecard's CLI and A17 row on the fixture (split from scorecard_gate.test.mjs so node
// --test runs them in parallel).

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { runtimePitches } from '../lib/score.mjs';
import { FIXTURE_BANK, SHARED_BANK, readJson, tempDir } from './helpers.mjs';
import { card, CLI, fixture, row } from './scorecard_kit.mjs';

test('the CLI writes the card and its exit code is the verdict', (t) => {
  const root = tempDir(t);
  fs.mkdirSync(path.join(root, 'assets', '_shared', 'audio'), { recursive: true });
  for (const f of fs.readdirSync(path.dirname(SHARED_BANK))) fs.copyFileSync(path.join(path.dirname(SHARED_BANK), f), path.join(root, 'assets', '_shared', 'audio', f));
  const good = spawnSync(process.execPath, [CLI, `--bank=${FIXTURE_BANK}`, `--root=${root}`], { encoding: 'utf8' });
  assert.equal(good.status, 0, good.stdout + good.stderr);
  const saved = readJson(path.join(root, 'build', 'audio_preview', 'fixture_scorecard.json'));
  assert.equal(saved.pass, true);
  assert.ok(fs.existsSync(path.join(root, 'build', '.gdignore')));
  const doc = structuredClone(fixture);
  doc.machines.engine.events[0].db -= 14;
  doc.machines.engine.loops[0].db -= 14;
  const bad = path.join(root, 'bad.json');
  fs.writeFileSync(bad, JSON.stringify(doc));
  const r = spawnSync(process.execPath, [CLI, `--bank=${bad}`, `--root=${root}`, '--json'], { encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.equal(JSON.parse(r.stdout).pass, false);
  assert.equal(spawnSync(process.execPath, [CLI], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync(process.execPath, [CLI, '--wat'], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync(process.execPath, [CLI, '--game=nope', `--root=${root}`], { encoding: 'utf8' }).status, 2);
});

test('A17 reads a file at the pitch it plays: reported for every bank, held where the bank asks', () => {
  const doc = structuredClone(fixture);
  doc.sounds.hisser = { dur: 0.5, rate: 22050, ch: 1, seed: 7, layers: [{ src: 'noise', color: 'white', gain: 1 }] };
  doc.cues.hisser = { hits: [{ sound: 'hisser', db: -30, pitch: 1.5 }] };
  doc.preview.events = [...doc.preview.events, { t: 3, cue: 'hisser' }];
  assert.ok(row(card(doc), 'A17').value > -32, 'white noise up to 9 kHz reaches 13.5 kHz');
  assert.equal(row(card(doc), 'A17').pass, true, 'only reported');
  doc.preview.checks = { ...doc.preview.checks, a17: true };
  assert.equal(row(card(doc), 'A17').pass, false, 'held');
  assert.equal(row(card(doc), 'A9').pass, true, 'A9 reads the file as it is');
});

test('runtimePitches: every place a bank plays a sound', () => {
  const pitches = runtimePitches({
    machines: { m: { events: [{ sound: 'a', pitch_table: [0, 0.1] }], loops: [{ sound: 'b', pitch_by: [{ param: 'rpm', points: [[0, 1], [10, 1.8]] }] }] } },
    beds: { x: { spots: [{ sound: 'c', pitch: [0.9, 1.3] }] } },
    cues: { y: { hits: [{ sound: 'd', pitch: 1.2, pitch_var: 'p', flight: { pitch: [[0, 1.1], [1, 0.8]] } }] } },
    preview: { events: [{ cue: 'y', vars: { p: 1.05 } }] },
  });
  assert.ok(Math.abs(pitches.get('a') - 1.1) < 1e-9);
  assert.equal(pitches.get('b'), 1.8);
  assert.equal(pitches.get('c'), 1.3);
  assert.ok(Math.abs(pitches.get('d') - 1.2 * 1.1 * 1.05) < 1e-9);
});
