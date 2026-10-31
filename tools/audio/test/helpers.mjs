// Shared by the audio pipeline's tests. No test lives here.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const TEST_DIR = path.dirname(fileURLToPath(import.meta.url));
export const AUDIO_DIR = path.resolve(TEST_DIR, '..');
export const REPO = path.resolve(AUDIO_DIR, '..', '..');
export const FIXTURE_BANK = path.join(TEST_DIR, 'fixtures', 'engine_bank.json');
export const SHARED_BANK = path.join(REPO, 'assets', '_shared', 'audio', 'audio.json');
export const PROOF_BANK = path.join(REPO, 'tests', 'audio', 'fixtures', 'import_proof_bank.json');

export function tempDir(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands_audio_test_'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

export function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

/** A one-sound bank, for recipe and generator tests. */
export function bankOf(sounds, extra = {}) {
  return { schema: 1, game: 'test', sounds, ...extra };
}

/** A project root holding one bank at assets/<game>/audio/audio.json. */
export function rootWithBank(t, game, doc) {
  const root = tempDir(t);
  const dir = path.join(root, 'assets', game, 'audio');
  fs.mkdirSync(dir, { recursive: true });
  const bankPath = path.join(dir, 'audio.json');
  fs.writeFileSync(bankPath, JSON.stringify(doc));
  return { root, dir, bankPath };
}

/** Every .mjs under dir, recursively. */
export function mjsFiles(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...mjsFiles(p));
    else if (e.name.endsWith('.mjs')) out.push(p);
  }
  return out;
}

export function sineWave(hz, seconds, rate, amp = 1) {
  const x = new Float64Array(Math.round(seconds * rate));
  for (let i = 0; i < x.length; i++) x[i] = amp * Math.sin((2 * Math.PI * hz * i) / rate);
  return x;
}

/** Zero crossings per second / 2: a tone's frequency. */
export function toneHz(x, rate) {
  let n = 0;
  for (let i = 1; i < x.length; i++) if (x[i - 1] < 0 && x[i] >= 0) n++;
  return n / (x.length / rate);
}
