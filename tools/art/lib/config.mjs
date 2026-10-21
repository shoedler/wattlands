// Reads tools/art/endpoints.json and tools/art/prices.json (BRIEF 3.10).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ART_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const REPO_ROOT = path.resolve(ART_DIR, '..', '..');

export const DEFAULT_ENDPOINT = 'openai/gpt-image-2.5/sunburst/text-to-image';
export const DRAFT_ENDPOINT = 'openai/gpt-image-2.5/flare/text-to-image';
export const DEFAULT_QUALITY = 'high';

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

let endpointsCache = null;
let pricesCache = null;

export function loadEndpoints(file = path.join(ART_DIR, 'endpoints.json')) {
  if (file === path.join(ART_DIR, 'endpoints.json') && endpointsCache) return endpointsCache;
  const data = readJson(file);
  if (file === path.join(ART_DIR, 'endpoints.json')) endpointsCache = data;
  return data;
}

export function loadPrices(file = path.join(ART_DIR, 'prices.json')) {
  if (file === path.join(ART_DIR, 'prices.json') && pricesCache) return pricesCache;
  const data = readJson(file);
  if (file === path.join(ART_DIR, 'prices.json')) pricesCache = data;
  return data;
}

/** The list of endpoint ids endpoints.json knows. */
export function knownEndpoints(endpoints = loadEndpoints()) {
  return Object.keys(endpoints.endpoints ?? {});
}

/**
 * Limits for one endpoint, with endpoints.json's defaults filled in.
 * Returns null for an endpoint endpoints.json doesn't list.
 */
export function endpointLimits(endpoint, endpoints = loadEndpoints()) {
  const entry = endpoints.endpoints?.[endpoint];
  if (!entry) return null;
  const d = endpoints.defaults ?? {};
  const pick = (k, fallback) => (entry[k] !== undefined ? entry[k] : d[k] !== undefined ? d[k] : fallback);
  return {
    endpoint,
    label: entry.label ?? endpoint,
    multiple: pick('multiple', 16),
    min_pixels: pick('min_pixels', 655360),
    max_pixels: pick('max_pixels', 8294400),
    max_edge: pick('max_edge', 3840),
    max_aspect: pick('max_aspect', 3),
    target_pixels: pick('target_pixels', 1048576),
    max_request_pixels: pick('max_request_pixels', 1327104),
    params: { ...(d.params ?? {}), ...(entry.params ?? {}) },
  };
}
