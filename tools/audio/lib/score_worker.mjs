// Scores one bank file off the main thread, so the scorecard gate test can score every bank at once:
// scoreBanksInParallel([{game, bankPath}], {root}) resolves to [{game, fails, cached}] in input order.
// With WATTLANDS_TEST_CACHE_DIR set, a pass is kept in verdict_cache.mjs and reused while nothing the
// scoring read has changed; verdictLine() says which of the two happened, so a log shows what really ran.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { scoreBankFile } from './score.mjs';
import { CACHE_ENV, cachedVerdict, codeHash, entryPath, mjsFiles, pruneEntries } from './verdict_cache.mjs';

const LIB = path.dirname(fileURLToPath(import.meta.url));
/** The scorecard's folder under a WATTLANDS_TEST_CACHE_DIR. */
export const SCORECARD_CACHE = 'audio_scorecard';

function keyOf(bankPath, root, sharedPath) {
  const key = { what: 'scoreBankFile', bank: path.resolve(bankPath), root: path.resolve(root) };
  if (sharedPath) key.shared = path.resolve(sharedPath);
  return key;
}

/**
 * One bank's card, through the verdict cache when cacheDir is set: {fails, cached}. lib: the folder whose
 * .mjs files the verdict's code hash covers (this one; a test passes a copy of it).
 */
export function scoreBankCached(bankPath, { root, cacheDir = null, sharedPath = null, lib = LIB }) {
  const v = cachedVerdict({
    cacheDir: cacheDir ? path.join(cacheDir, SCORECARD_CACHE) : null,
    key: keyOf(bankPath, root, sharedPath),
    code: cacheDir ? codeHash(mjsFiles(lib)) : null,
    compute: () => {
      const c = scoreBankFile(bankPath, { root, sharedPath });
      return { pass: c.fails.length === 0, fails: c.fails };
    },
  });
  return { fails: v.cached ? [] : v.fails, cached: Boolean(v.cached) };
}

/** The log line for one bank's result: whether its card was scored or a kept pass was reused. */
export function verdictLine(r) {
  return `audio scorecard ${r.game}: ${r.cached ? 'cached verdict, inputs unchanged' : 'scored'}`;
}

/**
 * Deletes every scorecard cache entry that is not the current entry of one of `banks`: a bank that is
 * gone, older scoring code, a broken file. Returns the names removed.
 */
export function pruneScorecardCache(cacheDir, banks, { root, sharedPath = null, lib = LIB }) {
  if (!cacheDir) return [];
  const dir = path.join(cacheDir, SCORECARD_CACHE);
  const code = codeHash(mjsFiles(lib));
  return pruneEntries(
    dir,
    banks.map((b) => entryPath(dir, keyOf(b.bankPath, root, sharedPath), code)),
  );
}

/** Every bank in its own worker thread. A worker that throws or dies rejects. */
export function scoreBanksInParallel(banks, { root, cacheDir = process.env[CACHE_ENV] || null, sharedPath = null, lib = LIB }) {
  return Promise.all(
    banks.map(
      (b) =>
        new Promise((resolve, reject) => {
          const w = new Worker(fileURLToPath(import.meta.url), { workerData: { bankPath: b.bankPath, root, cacheDir, sharedPath, lib } });
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
