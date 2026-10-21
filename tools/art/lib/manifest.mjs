// assets/<id>/art_manifest.json: every fal request, its input, cost and result (BRIEF 3.10,
// docs/OWNERSHIP.md ART4, ART5, C38).
import fs from 'node:fs';
import path from 'node:path';
import { usdToTicks, ticksToUsd } from './prices.mjs';

export const MANIFEST_VERSION = 1;

/** Statuses of a request that was paid (or may have been) and whose image may still be fetched. */
export const RECOVERABLE = new Set(['submitted', 'result_failed', 'download_failed', 'timeout']);

export function manifestPath(root, game) {
  return path.join(root, 'assets', game, 'art_manifest.json');
}

export function emptyManifest(game) {
  return { version: MANIFEST_VERSION, game, updated_at: null, spend: computeSpend({ requests: [] }), requests: [] };
}

export function loadManifest(file, game) {
  if (!fs.existsSync(file)) return emptyManifest(game);
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!data || typeof data !== 'object' || !Array.isArray(data.requests)) {
    throw new Error(`${file}: not an art manifest (no "requests" array)`);
  }
  data.version ??= MANIFEST_VERSION;
  data.game ??= game;
  return data;
}

/**
 * The spend total (docs/OWNERSHIP.md C38): for every paid request id, the larger of the estimate
 * and the billed amount, summed. Also the estimate and billed sums on their own.
 */
export function computeSpend(m) {
  const seen = new Set();
  let total = 0;
  let est = 0;
  let billed = 0;
  let n = 0;
  for (const r of m.requests) {
    if (!r.paid || !r.request_id || seen.has(r.request_id)) continue;
    seen.add(r.request_id);
    const e = usdToTicks(r.estimated_usd ?? 0);
    const b = typeof r.billed_usd === 'number' ? usdToTicks(r.billed_usd) : 0;
    total += Math.max(e, b);
    est += e;
    billed += b;
    n += 1;
  }
  return { total_usd: ticksToUsd(total), estimated_usd: ticksToUsd(est), billed_usd: ticksToUsd(billed), paid_requests: n };
}

/** Writes the manifest atomically (temp file, then rename), with the spend total refreshed. */
export function saveManifest(file, m) {
  m.spend = computeSpend(m);
  m.updated_at = new Date().toISOString();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(m, null, 2)}\n`);
  fs.renameSync(tmp, file);
}

/** JSON with object keys sorted at every level, for comparing inputs. */
export function canonicalJson(v) {
  if (Array.isArray(v)) return `[${v.map(canonicalJson).join(',')}]`;
  if (v && typeof v === 'object') {
    return `{${Object.keys(v)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonicalJson(v[k])}`)
      .join(',')}}`;
  }
  return JSON.stringify(v);
}

export function sameInput(a, b) {
  return canonicalJson(a) === canonicalJson(b);
}

/** True when every field of `ours` equals the same field of `theirs` (fal may add defaults). */
export function inputMatches(ours, theirs) {
  let t = theirs;
  if (typeof t === 'string') {
    try {
      t = JSON.parse(t);
    } catch {
      return false;
    }
  }
  if (!t || typeof t !== 'object') return false;
  return Object.keys(ours).every((k) => canonicalJson(ours[k]) === canonicalJson(t[k]));
}

export function entriesFor(m, sprite) {
  return m.requests.filter((r) => r.sprite === sprite);
}

export function selectedEntry(m, sprite) {
  return m.requests.find((r) => r.sprite === sprite && r.selected === true) ?? null;
}

/** Marks `entry` as the one selected result of its sprite. `by` is "run" or "user". */
export function selectEntry(m, entry, by) {
  for (const r of m.requests) {
    if (r.sprite === entry.sprite) {
      r.selected = false;
      delete r.selected_by;
    }
  }
  entry.selected = true;
  entry.selected_by = by;
}
