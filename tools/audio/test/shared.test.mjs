// SPEC_AUDIO 4.5: the platform's UI set in assets/_shared/audio. Names and format are test_sfx.gd's;
// loudness is 3.6; the scale is 3.3.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { allFiles, manifestPathOf } from '../lib/bank.mjs';
import { momentaryMaxLufs } from '../lib/lufs.mjs';
import { ALERTS, UI_METERED } from '../lib/score.mjs';
import { decodeWav, deinterleave } from '../lib/wav.mjs';
import { REPO, SHARED_BANK, readJson } from './helpers.mjs';

const DIR = path.dirname(SHARED_BANK);
const doc = readJson(SHARED_BANK);

function builtinNames() {
  const src = fs.readFileSync(path.join(REPO, 'addons', 'wattlands', 'audio', 'sfx.gd'), 'utf8');
  const from = src.indexOf('= [', src.indexOf('BUILTIN_NAMES'));
  const body = src.slice(from, src.indexOf(']', from));
  return [...body.matchAll(/"([a-z_]+)"/g)].map((m) => m[1]);
}

function loaded(name) {
  const w = decodeWav(fs.readFileSync(path.join(DIR, `${name}.wav`)));
  return { w, x: deinterleave(w.samples, 1)[0] };
}

test('the bank is exactly WlSfx.BUILTIN_NAMES', () => {
  const names = builtinNames();
  assert.equal(names.length, 15);
  assert.deepEqual(Object.keys(doc.sounds).sort(), [...names].sort());
  assert.deepEqual(allFiles(doc).map((f) => f.stem).sort(), [...names].sort());
  assert.equal(doc.game, '_shared');
  assert.equal(doc.machines, undefined, '_shared has sounds only');
});

test('every file is what test_sfx.gd asks: 16-bit mono 22050, 5 ms to 1.5 s, audible, no clip', () => {
  for (const name of Object.keys(doc.sounds)) {
    const { w, x } = loaded(name);
    assert.equal(w.rate, 22050, name);
    assert.equal(w.ch, 1, name);
    const len = w.frames / w.rate;
    assert.ok(len >= 0.005 && len <= 1.5, `${name} ${len}`);
    const peak = Math.max(...x.map(Math.abs));
    assert.ok(peak > 0.05 && peak <= 1, `${name} ${peak}`);
  }
});

test('every sidecar imports as PCM, no loop, no trim', () => {
  for (const name of Object.keys(doc.sounds)) {
    const text = fs.readFileSync(path.join(DIR, `${name}.wav.import`), 'utf8');
    assert.match(text, /compress\/mode=0/, name);
    assert.match(text, /edit\/loop_mode=1/, name);
    assert.match(text, /edit\/trim=false/, name);
  }
  assert.ok(fs.existsSync(manifestPathOf(SHARED_BANK)));
});

test('the click is the metronome\'s: a 2 ms attack in a 12 ms file', () => {
  const { w, x } = loaded('click');
  assert.equal(w.frames, Math.round(0.012 * 22050));
  const attack = Math.round(0.002 * 22050);
  const early = Math.max(...x.subarray(0, Math.floor(attack / 2)).map(Math.abs));
  const late = Math.max(...x.subarray(attack, attack * 2).map(Math.abs));
  assert.ok(early < late, `${early} < ${late}`);
});

test('warning keeps its two 440 Hz pulses with a gap; rescue still falls 620 to 300 Hz', () => {
  const warn = loaded('warning').x;
  const rate = 22050;
  const crossings = (a, b, x) => {
    let n = 0;
    for (let i = a + 1; i < b; i++) if (x[i - 1] < 0 && x[i] >= 0) n++;
    return n / ((b - a) / rate);
  };
  assert.ok(Math.abs(crossings(200, 2400, warn) - 440) < 12);
  assert.ok(Math.abs(crossings(Math.round(0.19 * rate), Math.round(0.28 * rate), warn) - 440) < 15);
  const gap = warn.subarray(Math.round(0.125 * rate), Math.round(0.175 * rate));
  assert.ok(Math.max(...gap.map(Math.abs)) < 0.01, 'the gap between pulses');
  const res = loaded('rescue').x;
  const first = crossings(200, 2400, res);
  const last = crossings(Math.round(0.42 * rate), Math.round(0.48 * rate), res);
  assert.ok(first > 540 && first < 640, `${first}`);
  assert.ok(last > 280 && last < 360, `${last}`);
});

test('tonal UI sits on C major pentatonic (SPEC 3.3)', () => {
  const pcs = new Set([0, 2, 4, 7, 9]); // C D E G A
  const isOnScale = (hz) => {
    const midi = 69 + 12 * Math.log2(hz / 440);
    return Math.abs(midi - Math.round(midi)) < 0.02 && pcs.has(((Math.round(midi) % 12) + 12) % 12);
  };
  const untuned = new Set(['hit', 'boom', 'whoosh']);
  for (const [name, s] of Object.entries(doc.sounds)) {
    if (untuned.has(name)) continue;
    for (const l of s.layers) {
      if (['tri', 'pulse', 'square', 'sine'].includes(l.src) && typeof l.f === 'number') assert.ok(isOnScale(l.f), `${name} ${l.f} Hz`);
      if (l.src === 'modal') assert.ok(isOnScale(l.f[0]), `${name} ${l.f[0]} Hz`);
    }
  }
});

test('UI momentary max is -20 LUFS +-3 on both channels (ticks under 100 ms excepted)', () => {
  for (const name of UI_METERED) {
    const { x } = loaded(name);
    const v = momentaryMaxLufs([x, x], 22050);
    assert.ok(v >= -23 && v <= -17, `${name}: ${v}`);
  }
});

test('the safety prompts: louder than any other UI sound, up to -15 LUFS so D5 holds over a -18 mix', () => {
  let loudestUi = -Infinity;
  for (const name of UI_METERED) {
    const { x } = loaded(name);
    loudestUi = Math.max(loudestUi, momentaryMaxLufs([x, x], 22050));
  }
  for (const name of ALERTS) {
    const { x } = loaded(name);
    const v = momentaryMaxLufs([x, x], 22050);
    assert.ok(v > loudestUi, `${name}: ${v} over ${loudestUi}`);
    assert.ok(v >= -17 && v <= -15, `${name}: ${v}`);
  }
});

test('metered lists cover every sound on the UI bus (SPEC 1.4); the rest are named', () => {
  const sfxBus = ['coin', 'hit', 'boom', 'whoosh'];
  const unmetered = ['ui_move', 'click'];
  assert.deepEqual([...UI_METERED, ...ALERTS, ...sfxBus, ...unmetered].sort(), Object.keys(doc.sounds).sort());
});
