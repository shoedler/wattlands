// SPEC_AUDIO 6.2: the scorecard's R1-R3 rows on the fixture (split from scorecard_gate.test.mjs so node
// --test runs them in parallel).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { card, fixture, report, row, rowsFrom } from './scorecard_kit.mjs';

test('R1-R3 read the tracked reports, every one of them', (t) => {
  const good = report(1, 3, 5, -7);
  const pass = (c, id) => row(c, id).pass;
  assert.equal(pass(rowsFrom(t, [good, good]), 'R1'), true);
  assert.equal(pass(rowsFrom(t, [good, good]), 'R2'), true);
  assert.equal(pass(rowsFrom(t, [good, good]), 'R3'), true);
  assert.equal(pass(rowsFrom(t, [good, report(0.15, 3, 5, -7)]), 'R1'), false, 'one arrow in seven');
  assert.equal(pass(rowsFrom(t, [good, report(1, 1.5, 5, -7)]), 'R2'), false, 'no more onsets where arrows land');
  assert.equal(pass(rowsFrom(t, [good, report(1, 3, 5, 2)]), 'R3'), false, 'a body no louder than a miss');
});

test('without checks.real_wave R1-R3 say so', () => {
  assert.equal(row(card(structuredClone(fixture)), 'R1').value, 'n/a');
});
