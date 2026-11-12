// SPEC_AUDIO 6.2: every bank on disk with a preview block passes the scorecard, so these rows are
// permanent gates. In phase 0 that is the fixture; each game's branch adds its own bank.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { findBanks, loadBank } from '../lib/bank.mjs';
import { scoreBanksInParallel } from '../lib/score_worker.mjs';
import { REPO } from './helpers.mjs';

// Each bank in its own worker thread. Under tools/run_tests --node-cache (the gate's fast lane) a bank
// whose files, real-wave reports and scoring code are all as they were when it last passed is not
// scored again (lib/verdict_cache.mjs); anything else is.
test('every bank on disk with a preview block passes', async () => {
  const banks = findBanks(REPO).filter((b) => loadBank(b.bankPath).preview);
  const results = await scoreBanksInParallel(banks, { root: REPO });
  assert.equal(results.length, banks.length);
  for (const r of results) assert.deepEqual(r.fails, [], r.game);
});
