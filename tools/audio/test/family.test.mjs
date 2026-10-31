// SPEC_AUDIO 3.3: one family by construction, enforced over every bank on disk and the fixture.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { allFiles, findBanks, loadBank, renderFile } from '../lib/bank.mjs';
import { bandShareDb } from '../lib/dsp.mjs';
import { decodeWav, deinterleave } from '../lib/wav.mjs';
import { FIXTURE_BANK, REPO } from './helpers.mjs';

const banks = [...findBanks(REPO).map((b) => b.bankPath), FIXTURE_BANK];

function eachFile(fn) {
  for (const bankPath of banks) {
    const doc = loadBank(bankPath);
    for (const f of allFiles(doc)) {
      const r = renderFile(doc, f);
      fn(doc, f, decodeWav(r.wav), r);
    }
  }
}

test('rate 22050 Hz, or 11025 Hz only for a low bed layer', () => {
  eachFile((doc, f, w) => {
    assert.ok(w.rate === 22050 || w.rate === 11025, `${f.stem}`);
    if (w.rate === 11025) {
      assert.equal(doc.sounds[f.id].loop, true, `${f.stem}: 11025 Hz is for bed layers`);
    }
  });
});

test('A9: above 9.8 kHz at most -32 dB of the file, each channel', () => {
  eachFile((doc, f, w) => {
    if (w.rate !== 22050) return;
    for (const x of deinterleave(w.samples, w.ch)) {
      const share = bandShareDb(x, w.rate, 9800, 11026);
      assert.ok(share <= -32, `${doc.game} ${f.stem}: ${share}`);
    }
  });
});

test('12 significant bits: the low nibble is zero in every sample', () => {
  eachFile((doc, f, w) => {
    for (const v of w.samples) assert.equal(v & 15, 0, `${doc.game} ${f.stem}`);
  });
});

test('machine strokes are locked, mono, PCM; a loop is seamless', () => {
  eachFile((doc, f, w, r) => {
    const s = doc.sounds[f.id];
    if (s.locked) {
      assert.equal(w.ch, 1, f.stem);
      assert.equal(r.entry.compress, 'pcm', f.stem);
      assert.equal(r.entry.preroll, Math.round(0.08 * w.rate), f.stem);
    }
    if (s.loop) {
      const n = r.entry.loop_frames;
      assert.equal(w.frames, n + 1, f.stem);
      for (let c = 0; c < w.ch; c++) assert.equal(w.samples[n * w.ch + c], w.samples[c], `${f.stem}: guard frame`);
    }
  });
});

test('no sound is stereo unless it is a bed layer or a spot', () => {
  for (const bankPath of banks) {
    const doc = loadBank(bankPath);
    const ok = new Set();
    for (const b of Object.values(doc.beds ?? {})) {
      for (const l of b.layers ?? []) ok.add(l.sound);
      for (const s of b.spots ?? []) ok.add(s.sound);
    }
    for (const [id, s] of Object.entries(doc.sounds)) {
      if ((s.ch ?? 1) === 2) assert.ok(ok.has(id), `${doc.game} ${id} is stereo outside a bed`);
    }
  }
});
