// SPEC_AUDIO 3.5, over every bank in the repo.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { allFiles, findBanks, loadBank, manifestPathOf, renderFile, wavDifference } from '../lib/bank.mjs';
import { decodeWav } from '../lib/wav.mjs';
import { FIXTURE_BANK, PROOF_BANK, REPO, readJson } from './helpers.mjs';

const onDisk = [...findBanks(REPO).map((b) => b.bankPath), PROOF_BANK];

test('every bank renders the same bytes twice in one process', () => {
  for (const bankPath of [...onDisk, FIXTURE_BANK]) {
    const doc = loadBank(bankPath);
    for (const f of allFiles(doc)) {
      const a = renderFile(doc, f);
      const b = renderFile(doc, f);
      assert.equal(a.entry.sha256, b.entry.sha256, `${doc.game} ${f.stem}`);
    }
  }
});

test('every file on disk is its recipe\'s render, within one 12-bit step', () => {
  assert.ok(onDisk.length >= 2, '_shared and the import proof at least');
  for (const bankPath of onDisk) {
    const doc = loadBank(bankPath);
    const dir = path.dirname(bankPath);
    for (const f of allFiles(doc)) {
      const diff = wavDifference(renderFile(doc, f).wav, fs.readFileSync(path.join(dir, `${f.stem}.wav`)));
      assert.equal(diff, null, `${doc.game} ${f.stem}`);
    }
  }
});

test('each manifest matches the disk', () => {
  for (const bankPath of onDisk) {
    const doc = loadBank(bankPath);
    const dir = path.dirname(bankPath);
    const m = readJson(manifestPathOf(bankPath));
    const stems = allFiles(doc).map((f) => f.stem);
    assert.deepEqual(Object.keys(m), stems, bankPath);
    for (const stem of stems) {
      const b = fs.readFileSync(path.join(dir, `${stem}.wav`));
      const w = decodeWav(b);
      assert.equal(m[stem].sha256, crypto.createHash('sha256').update(b).digest('hex'), stem);
      assert.equal(m[stem].frames, w.frames, stem);
      assert.equal(m[stem].rate, w.rate, stem);
      assert.equal(m[stem].ch, w.ch, stem);
      assert.equal(m[stem].bytes, b.length, stem);
    }
  }
});

test('a changed seed changes the bytes', () => {
  const doc = loadBank(FIXTURE_BANK);
  for (const id of ['fire_a', 'wind_lo', 'body']) {
    const f = allFiles(doc).find((x) => x.id === id);
    const before = renderFile(doc, f).entry.sha256;
    const other = { ...doc, sounds: { ...doc.sounds, [id]: { ...doc.sounds[id], seed: doc.sounds[id].seed + 1 } } };
    assert.notEqual(renderFile(other, f).entry.sha256, before, id);
  }
});
