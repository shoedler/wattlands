// Scores one bank file off the main thread, so the scorecard gate test can score every bank at once:
// scoreBanksInParallel([{game, bankPath}], {root}) resolves to [{game, fails, cached}] in input order.
// With WATTLANDS_TEST_CACHE_DIR set, a pass is kept in verdict_cache.mjs and reused while nothing the
// scoring read has changed.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { scoreBankFile } from './score.mjs';
import { CACHE_ENV, cachedVerdict, codeHash, mjsFiles } from './verdict_cache.mjs';

const LIB = path.dirname(fileURLToPath(import.meta.url));

/** One bank's card, through the verdict cache when cacheDir is set: {fails, cached}. */
export function scoreBankCached(bankPath, { root, cacheDir = null }) {
  const key = { what: 'scoreBankFile', bank: path.resolve(bankPath), root: path.resolve(root) };
  const v = cachedVerdict({
    cacheDir: cacheDir ? path.join(cacheDir, 'audio_scorecard') : null,
    key,
    code: cacheDir ? codeHash(mjsFiles(LIB)) : null,
    compute: () => {
      const c = scoreBankFile(bankPath, { root });
      return { pass: c.fails.length === 0, fails: c.fails };
    },
  });
  return { fails: v.cached ? [] : v.fails, cached: Boolean(v.cached) };
}

/** Every bank in its own worker thread. A worker that throws or dies rejects. */
export function scoreBanksInParallel(banks, { root, cacheDir = process.env[CACHE_ENV] || null }) {
  return Promise.all(
    banks.map(
      (b) =>
        new Promise((resolve, reject) => {
          const w = new Worker(fileURLToPath(import.meta.url), { workerData: { bankPath: b.bankPath, root, cacheDir } });
          let got = null;
          w.once('message', (m) => {
            got = m;
          });
          w.once('error', reject);
          w.once('exit', (code) => {
            if (got && got.error) reject(new Error(`${b.game}: ${got.error}`));
            else if (got && code === 0) resolve({ game: b.game, ...got });
            else reject(new Error(`${b.game}: the scoring worker exited ${code} with no result`));
          });
        }),
    ),
  );
}

if (!isMainThread && workerData && workerData.bankPath) {
  try {
    parentPort.postMessage(scoreBankCached(workerData.bankPath, workerData));
  } catch (err) {
    parentPort.postMessage({ error: err.stack || String(err) });
  }
}
