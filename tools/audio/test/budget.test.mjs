// SPEC_AUDIO 3.4: repo WAV bytes per game and in total.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { bankWavBytes, findBanks } from '../lib/bank.mjs';
import { WAV_CAPS_MB, WAV_TOTAL_CAP_MB } from '../lib/score.mjs';
import { AUDIO_DIR, PROOF_BANK, REPO } from './helpers.mjs';

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

test('the caps are the spec\'s', () => {
  assert.deepEqual(WAV_CAPS_MB, { tank: 7.0, fishing: 4.5, siege: 4.5, workout: 4.0, _shared: 0.3 });
  assert.equal(WAV_TOTAL_CAP_MB, 20.5);
});

test('each game\'s WAV bytes stay under its cap, and every bank has a cap', () => {
  let total = 0;
  for (const { game, bankPath } of findBanks(REPO)) {
    const cap = WAV_CAPS_MB[game];
    assert.notEqual(cap, undefined, `no cap for ${game}: a new game needs one in lib/score.mjs`);
    const mb = bankWavBytes(bankPath) / 1e6;
    assert.ok(mb <= cap, `${game}: ${mb.toFixed(2)} MB > ${cap} MB`);
    total += mb;
  }
  assert.ok(total <= WAV_TOTAL_CAP_MB, `total ${total.toFixed(2)} MB`);
});

test('the import proof stays small', () => {
  assert.ok(bankWavBytes(PROOF_BANK) / 1e6 <= 0.2);
});

test('no WAV under tools/audio: Godot would import it', () => {
  assert.deepEqual(walk(AUDIO_DIR).filter((f) => f.endsWith('.wav')), []);
});

test('no MP3, OGG or other encoded audio ships under assets', () => {
  const assets = path.join(REPO, 'assets');
  const bad = walk(assets).filter((f) => /[\\/]audio[\\/]/.test(f) && /\.(mp3|ogg|flac|opus)$/.test(f));
  assert.deepEqual(bad, []);
});
