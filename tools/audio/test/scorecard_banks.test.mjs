// SPEC_AUDIO 6.2: every bank on disk with a preview block passes the scorecard, so these rows are
// permanent gates. In phase 0 that is the fixture; each game's branch adds its own bank.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { findBanks, loadBank } from '../lib/bank.mjs';
import { pruneScorecardCache, scoreBanksInParallel, verdictLine } from '../lib/score_worker.mjs';
import { CACHE_ENV } from '../lib/verdict_cache.mjs';
import { REPO } from './helpers.mjs';

// Each bank in its own worker thread. Under tools/run_tests --node-cache (the gate's fast lane) a bank
// whose files, real-wave reports and scoring code are all as they were when it last passed is not
// scored again (lib/verdict_cache.mjs); anything else is. One line per bank says which, and entries
// that match no bank on disk are pruned.
test('every bank on disk with a preview block passes', async (t) => {
  const banks = findBanks(REPO).filter((b) => loadBank(b.bankPath).preview);
  const results = await scoreBanksInParallel(banks, { root: REPO });
  assert.equal(results.length, banks.length);
  for (const r of results) t.diagnostic(verdictLine(r));
  for (const r of results) assert.deepEqual(r.fails, [], r.game);
  const cacheDir = process.env[CACHE_ENV] || null;
  for (const name of pruneScorecardCache(cacheDir, banks, { root: REPO })) t.diagnostic(`audio scorecard cache: pruned ${name}`);
});
