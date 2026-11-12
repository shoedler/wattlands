// Shared by the scorecard_*.test.mjs files (SPEC_AUDIO 6.2), split so node --test scores them in
// parallel processes. No test lives here.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { loadBank } from '../lib/bank.mjs';
import { BankAudio } from '../lib/offline_mix.mjs';
import { scoreBank } from '../lib/score.mjs';
import { AUDIO_DIR, FIXTURE_BANK, SHARED_BANK, readJson, tempDir } from './helpers.mjs';

export const CLI = path.join(AUDIO_DIR, 'scorecard.mjs');
export const shared = new BankAudio(loadBank(SHARED_BANK), path.dirname(SHARED_BANK));

export function card(doc) {
  return scoreBank(doc, null, { shared });
}

export function row(c, id) {
  const r = c.rows.find((x) => x.id === id);
  assert.ok(r, id);
  return r;
}

export const fixture = readJson(FIXTURE_BANK);

export function rowsFrom(t, reports, spec = { coverage: 0.95, contrast: 2, body_over_miss: 6 }) {
  const dir = tempDir(t);
  const names = reports.map((r, i) => {
    fs.writeFileSync(path.join(dir, `r${i}.json`), JSON.stringify(r));
    return `r${i}.json`;
  });
  const doc = structuredClone(fixture);
  doc.preview.checks = { ...doc.preview.checks, real_wave: { reports: names, ...spec } };
  return scoreBank(doc, null, { shared, root: dir });
}

export const report = (coverage, contrast, body, miss) => ({ arrows: { coverage }, landing_contrast: { ratio: contrast }, one_arrow: { all_400_6000: { body: { median: body }, miss: { median: miss } } } });
