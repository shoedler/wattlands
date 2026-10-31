// SPEC_AUDIO 3.1: zero dependencies and no way out of the machine. This file holds the forbidden
// words only as built strings, so it can read itself too.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { AUDIO_DIR, mjsFiles } from './helpers.mjs';

const files = mjsFiles(AUDIO_DIR);
const FORBIDDEN = [`fe${'tch'}`, `ht${'tp'}`, `FA${'L_'}`, `Math.ran${'dom'}`, `Da${'te'}`, `WebSo${'cket'}`];

test('the pipeline has its files', () => {
  const names = files.map((f) => path.relative(AUDIO_DIR, f).split(path.sep).join('/'));
  for (const want of ['generate.mjs', 'preview.mjs', 'scorecard.mjs', 'lib/dsp.mjs', 'lib/recipe.mjs', 'lib/wav.mjs', 'lib/import_file.mjs', 'lib/lufs.mjs', 'lib/pattern.mjs', 'lib/offline_mix.mjs']) {
    assert.ok(names.includes(want), want);
  }
});

test('imports are node: built-ins and relative files only', () => {
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    for (const m of src.matchAll(/^\s*(?:import|export)\s[^'"]*from\s+['"]([^'"]+)['"]/gm)) {
      const spec = m[1];
      assert.ok(spec.startsWith('node:') || spec.startsWith('./') || spec.startsWith('../'), `${f}: ${spec}`);
    }
    assert.doesNotMatch(src, /\brequire\(/, f);
  }
});

test('no network, no art service, no wall clock, no global randomness', () => {
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    for (const word of FORBIDDEN) assert.ok(!src.includes(word), `${f} holds "${word}"`);
  }
});

test('only preview.mjs starts another process, and only ffmpeg', () => {
  for (const f of files) {
    if (f.includes(`${path.sep}test${path.sep}`)) continue;
    const src = fs.readFileSync(f, 'utf8');
    if (path.basename(f) === 'preview.mjs') {
      assert.deepEqual([...src.matchAll(/spawnSync\('([^']+)'/g)].map((m) => m[1]).filter((c) => c !== 'ffmpeg'), []);
    } else {
      assert.ok(!src.includes('child_process'), f);
    }
  }
});
