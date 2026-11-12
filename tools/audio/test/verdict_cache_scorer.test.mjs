// lib/verdict_cache.mjs with the real scorer (lib/score_worker.mjs), on the fixture bank rendered to disk:
// a kept pass is reused only while the bank's wavs, its JSON and the scoring code are as they were, and a
// failing card is never kept.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { generateBank } from '../lib/bank.mjs';
import { SCORECARD_CACHE, pruneScorecardCache, scoreBanksInParallel } from '../lib/score_worker.mjs';
import { AUDIO_DIR, FIXTURE_BANK, SHARED_BANK, readJson, rootWithBank, tempDir } from './helpers.mjs';

const entries = (cacheDir) => {
  const dir = path.join(cacheDir, SCORECARD_CACHE);
  return fs.existsSync(dir) ? fs.readdirSync(dir).sort() : [];
};

test('the real scorer through the cache: a hit until a wav, the bank or the scoring code changes', async (t) => {
  const fixture = readJson(FIXTURE_BANK);
  const { root, dir, bankPath } = rootWithBank(t, fixture.game, fixture);
  generateBank(bankPath, { root });
  // The code hash covers a copy of lib, so the test can change "the scoring code" without touching it.
  const lib = tempDir(t);
  for (const f of fs.readdirSync(path.join(AUDIO_DIR, 'lib'))) fs.copyFileSync(path.join(AUDIO_DIR, 'lib', f), path.join(lib, f));
  const cacheDir = tempDir(t);
  const bank = [{ game: fixture.game, bankPath }];
  const run = async (opts = {}) => (await scoreBanksInParallel(bank, { root, cacheDir, sharedPath: SHARED_BANK, lib, ...opts }))[0];

  // Without the _shared bank (none under this root) D5 fails: scored both times, never kept.
  const [first, failing] = await Promise.all([run(), run({ sharedPath: null })]);
  assert.deepEqual(first.fails, []);
  assert.equal(first.cached, false, 'the first run scores');
  assert.notDeepEqual(failing.fails, [], 'the card without the shared bank fails');
  assert.equal(failing.cached, false);
  assert.equal((await run({ sharedPath: null })).cached, false, 'a failing card is scored again');
  assert.equal(entries(cacheDir).length, 1, 'only the pass is kept');
  assert.deepEqual(await run(), { game: fixture.game, fails: [], cached: true }, 'unchanged: a hit');

  const wav = path.join(dir, fs.readdirSync(dir).find((f) => f.endsWith('.wav')));
  const edits = {
    'one byte of a wav': () => {
      const b = fs.readFileSync(wav);
      b[b.length - 1] ^= 1;
      fs.writeFileSync(wav, b);
    },
    'one byte of the bank JSON': () => fs.appendFileSync(bankPath, ' '),
    'one byte of a file under lib': () => fs.appendFileSync(path.join(lib, 'score.mjs'), ' '),
  };
  for (const [what, edit] of Object.entries(edits)) {
    edit();
    const miss = await run();
    assert.equal(miss.cached, false, `${what}: scored again`);
    assert.deepEqual(miss.fails, [], `${what}: still passes`);
    assert.equal((await run()).cached, true, `${what}: then a hit again`);
  }

  // The lib edit left the first entries behind; pruning keeps the current one, which still hits.
  assert.ok(entries(cacheDir).length > 1, entries(cacheDir).join(','));
  assert.ok(pruneScorecardCache(cacheDir, bank, { root, sharedPath: SHARED_BANK, lib }).length > 0);
  assert.equal(entries(cacheDir).length, 1);
  assert.equal((await run()).cached, true, 'the kept entry still hits');
  pruneScorecardCache(cacheDir, [], { root, sharedPath: SHARED_BANK, lib });
  assert.deepEqual(entries(cacheDir), [], 'a bank gone from disk takes its entry with it');
});
