// SPEC_AUDIO 6.2: the scorecard's A14, D9 and onset rows on the fixture (split from scorecard_gate.test.mjs so node
// --test runs them in parallel).

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { detectOnsets, scoreBankFile } from '../lib/score.mjs';
import { SHARED_BANK, tempDir } from './helpers.mjs';
import { card, fixture, row } from './scorecard_kit.mjs';

test('A6, A7 and A14 are not-applicable until a bank asks for them', () => {
  const doc = structuredClone(fixture);
  delete doc.preview.checks;
  const c = card(doc);
  for (const id of ['A6', 'A7', 'A14']) assert.equal(row(c, id).value, 'n/a', id);
});

test('A14 names a missing event; A16 and A12 are n/a with no bed', () => {
  const doc = structuredClone(fixture);
  doc.preview.checks.a14 = { cue: 'zz' };
  delete doc.preview.bed;
  const c = card(doc);
  assert.equal(row(c, 'A14').pass, false);
  assert.equal(row(c, 'A12').value, 'n/a');
  assert.equal(row(c, 'A16').value, 'n/a');
});

test('D9 reads the cap of a game bank', (t) => {
  const root = tempDir(t);
  const dir = path.join(root, 'assets', 'workout', 'audio');
  fs.mkdirSync(dir, { recursive: true });
  const bank = path.join(dir, 'audio.json');
  fs.writeFileSync(bank, JSON.stringify({ ...fixture, game: 'workout' }));
  fs.writeFileSync(path.join(dir, 'big.wav'), Buffer.alloc(4_100_000));
  const c = scoreBankFile(bank, { root, sharedPath: SHARED_BANK });
  assert.equal(row(c, 'D9').pass, false);
});

test('onsets: found, spaced, and a steady tone has none past its start', () => {
  const rate = 44100;
  const x = new Float64Array(rate);
  for (const at of [0.1, 0.4, 0.7]) {
    const i0 = Math.round(at * rate);
    for (let i = 0; i < 2000; i++) x[i0 + i] = Math.sin(i * 0.3) * Math.exp(-i / 500);
  }
  const on = detectOnsets(x);
  assert.equal(on.length, 3);
  on.forEach((t, i) => assert.ok(Math.abs(t - [0.1, 0.4, 0.7][i]) < 0.002));
  const tone = new Float64Array(rate);
  for (let i = 0; i < rate; i++) tone[i] = Math.sin(i * 0.1);
  assert.ok(detectOnsets(tone).length <= 1);
  assert.deepEqual(detectOnsets(new Float64Array(100)), []);
});

test('A14 reads the median of a cue\'s firings, not its quietest moment', () => {
  const doc = structuredClone(fixture);
  const shot = doc.preview.checks.a14.cue;
  const one = doc.preview.events.find((e) => e.cue === shot);
  doc.preview.events = [...doc.preview.events, { ...one, t: one.t + 0.05 }, { ...one, t: one.t + 0.1 }];
  assert.match(String(row(card(doc), 'A14').note), /5 firings/);
});
