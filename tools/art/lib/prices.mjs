// Conservative cost estimates from tools/art/prices.json (BRIEF 3.10). Money is handled in integer
// units of $0.0001 ("ticks") so budget sums never drift.
import { loadPrices } from './config.mjs';

export const TICKS_PER_USD = 10000;

export function usdToTicks(usd) {
  return Math.round(Number(usd) * TICKS_PER_USD);
}

export function ticksToUsd(ticks) {
  return Math.round(ticks) / TICKS_PER_USD;
}

/** Rounds a dollar amount up to the next $0.0001 (fal rounds its own totals the same way). */
export function ceilTicks(usd) {
  return Math.ceil(Number(usd) * TICKS_PER_USD - 1e-6);
}

export function formatUsd(usd) {
  return `$${Number(usd).toFixed(4)}`;
}

function priceFor(table, quality) {
  const v = table?.[quality];
  if (typeof v === 'number') return v;
  // An unknown quality is priced at the dearest one the table lists.
  return Math.max(...Object.values(table ?? {}).filter((x) => typeof x === 'number'));
}

function perImage(entry, width, height, quality) {
  const base = priceFor(entry.usd, quality);
  const scale = Math.max(1, (width * height) / entry.base_pixels);
  return base * scale;
}

function fromTable(entry, width, height, quality) {
  const px = width * height;
  const rows = [...entry.rows].map((r) => ({ px: r.width * r.height, usd: priceFor(r.usd, quality) }));
  rows.sort((a, b) => a.px - b.px);
  const allowance = Number(entry.prompt_allowance_usd ?? 0);
  const holder = rows.findIndex((r) => r.px >= px);
  if (holder === -1) {
    const last = rows[rows.length - 1];
    const dearest = Math.max(...rows.map((r) => r.usd));
    return Math.max(dearest, last.usd * (px / last.px)) + allowance;
  }
  const dearest = Math.max(...rows.slice(0, holder + 1).map((r) => r.usd));
  return dearest + allowance;
}

/**
 * Estimated price in USD (rounded up to $0.0001) of one image at width x height and quality on
 * endpoint. Endpoints without a prices.json entry use the fallback endpoint's figure.
 */
export function estimateUsd(endpoint, width, height, quality, prices = loadPrices()) {
  let entry = prices.endpoints?.[endpoint];
  if (!entry) entry = prices.endpoints?.[prices.fallback];
  if (!entry) throw new Error(`prices.json has no entry for ${endpoint} and no fallback`);
  const raw = entry.kind === 'table' ? fromTable(entry, width, height, quality) : perImage(entry, width, height, quality);
  return ticksToUsd(ceilTicks(raw));
}
