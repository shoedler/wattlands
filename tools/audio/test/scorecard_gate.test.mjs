// SPEC_AUDIO 6.2: the scorecard's rows on the fixture. Every bank on disk is scored in
// scorecard_banks.test.mjs; the other rows' tests are in scorecard_*.test.mjs, split so node --test
// runs them in parallel.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { scoreBank, scoreBankFile } from '../lib/score.mjs';
import { FIXTURE_BANK, REPO } from './helpers.mjs';
import { card, fixture, row, shared } from './scorecard_kit.mjs';

test('the fixture passes every row, and every row is there', () => {
  const c = scoreBankFile(FIXTURE_BANK, { root: REPO });
  assert.deepEqual(c.fails, []);
  assert.equal(c.pass, true);
  const ids = c.rows.map((r) => r.id);
  for (let i = 1; i <= 10; i++) assert.ok(ids.includes(`D${i}`), `D${i}`);
  for (let i = 1; i <= 17; i++) assert.ok(ids.includes(`A${i}`), `A${i}`);
});

test('D1 is computed from the audio: a stroke with no attack of its own loses its onsets', () => {
  const doc = structuredClone(fixture);
  doc.sounds.valve = { dur: 1.5, seed: 1, locked: true, layers: [{ src: 'sine', f: 800, env: { a: 0.3 } }] };
  const r = row(card(doc), 'D1');
  assert.equal(r.pass, false);
  assert.match(r.note, /valve@/);
});

test('D4 catches a ring past the stop', () => {
  const doc = structuredClone(fixture);
  doc.sounds.fire_a.dur = 0.9;
  doc.sounds.fire_a.layers.push({ src: 'sine', f: 90, gain: 1.0 });
  assert.equal(row(card(doc), 'D4').pass, false);
});

test('a preview with no stop fails D4 plainly', () => {
  const doc = structuredClone(fixture);
  doc.preview.segments = doc.preview.segments.filter((s) => s.rpm > 0);
  const r = row(card(doc), 'D4');
  assert.equal(r.pass, false);
  assert.equal(r.value, 'no stop');
});

test('D5 needs the _shared bank, and fails a mix that buries the prompts', () => {
  const none = scoreBank(fixture, null, { shared: null });
  assert.equal(row(none, 'D5').pass, false);
  const doc = structuredClone(fixture);
  doc.machines.engine.events[0].db = 14;
  doc.machines.engine.loops[0].db = 6;
  assert.equal(row(card(doc), 'D5').pass, false);
});
