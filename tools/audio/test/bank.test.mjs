import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { allFiles, findBanks, loadBank, manifestPathOf, soundFiles, validateBank, wavDifference } from '../lib/bank.mjs';
import { encodeWav } from '../lib/wav.mjs';
import { FIXTURE_BANK, PROOF_BANK, SHARED_BANK, bankOf, readJson, tempDir } from './helpers.mjs';

const LOCKED = { dur: 0.1, rate: 22050, ch: 1, locked: true, layers: [{ src: 'noise' }] };
const LOOP = { dur: 1, rate: 22050, ch: 1, loop: true, layers: [{ src: 'noise' }] };
const ONE = { dur: 0.1, rate: 22050, ch: 1, layers: [{ src: 'noise' }] };

function problems(doc) {
  return validateBank(doc).join('\n');
}

test('the repo\'s banks validate', () => {
  for (const p of [FIXTURE_BANK, SHARED_BANK, PROOF_BANK]) assert.deepEqual(validateBank(readJson(p)), [], p);
});

test('only schema, game and sounds are required', () => {
  assert.deepEqual(validateBank({ schema: 1, game: 'x', sounds: {} }), []);
  assert.match(problems({ schema: 2, game: 'x', sounds: {} }), /schema: 2/);
  assert.match(problems({ schema: 1, sounds: {} }), /game: missing/);
  assert.match(problems({ schema: 1, game: 'x' }), /sounds: missing/);
});

test('rejects what AudioBank.validate rejects, naming the key path', () => {
  const m = (ev) => bankOf({ a: LOCKED, b: ONE, s: { ...LOCKED, ch: 2 } }, { machines: { d: { events: [ev] } } });
  assert.match(problems(m({ at: [0.5], sound: 'zz' })), /machines\.d\.events\[0\]\.sound: "zz" is not in sounds/);
  assert.match(problems(m({ at: [0.5], sound: 'b' })), /"b" is not locked/);
  assert.match(problems(m({ at: [1.0], sound: 'a' })), /\.at: 1 is outside \[0, 1\)/);
  assert.match(problems(m({ at: [-0.1], sound: 'a' })), /outside/);
  assert.match(problems(m({ at: [0], sound: 's' })), /stereo/);
  assert.match(problems(m({ at: 0.5, sound: 'a' })), /\.at: must be a list/);
  assert.deepEqual(validateBank(m({ at: [0, 0.5], sound: 'a' })), []);
  assert.match(problems(bankOf({ a: { ...ONE, rate: 44100 } })), /sounds\.a\.rate: 44100/);
  assert.match(problems(bankOf({ a: { ...ONE, ch: 3 } })), /sounds\.a\.ch: 3/);
  const { rate: _r, ch: _c, ...bare } = ONE;
  assert.match(problems(bankOf({ a: bare })), /sounds\.a\.rate: undefined/, 'rate is explicit, as AudioBank wants');
  assert.match(problems(bankOf({ a: bare })), /sounds\.a\.ch: undefined/);
  assert.match(problems(m({ at: [], sound: 'a' })), /must be a list/);
  assert.match(problems(m({ at: [0.5, 0.5], sound: 'a' })), /appears twice/);
  assert.match(problems(bankOf({ a: { ...LOCKED, compress: 'qoa' } })), /locked sound stays PCM/);
  assert.match(problems(bankOf({ a: ONE }, { cues: { c: { hits: [{ sound: 'a', bus: 'Master' }] } } })), /unknown bus "Master"/);
  assert.match(problems(bankOf({ a: ONE }, { cues: { c: { duck: [{ bus: 'UI', db: -3 }] } } })), /UI is never ducked/);
  assert.match(problems(bankOf({ a: ONE }, { machines: { d: { bus: 'Nope' } } })), /unknown bus "Nope"/);
  assert.match(problems(bankOf({ a: ONE }, { cues: { c: { hits: [{ sound: 'a', bus: 'Nope' }] } } })), /unknown bus/);
  assert.match(problems(bankOf({ a: ONE }, { cues: { c: { hits: [{ sound: 'zz' }] } } })), /cues\.c\.hits\[0\]\.sound/);
  assert.match(problems(bankOf({ a: ONE }, { beds: { f: { spots: [{ sound: 'zz' }] } } })), /beds\.f\.spots\[0\]\.sound/);
  assert.match(problems(bankOf({ a: ONE }, { loops: { l: { layers: [{ sound: 'zz' }] } } })), /loops\.l\.layers\[0\]\.sound/);
  assert.match(problems(bankOf({ a: ONE }, { machines: { d: { loops: [{ sound: 'a' }] } } })), /"a" is not a loop/);
  assert.match(problems(bankOf({ a: ONE }, { beds: { f: { layers: [{ sound: 'a' }] } } })), /"a" is not a loop/);
});

test('a file name two sounds would make is a duplicate id', () => {
  assert.match(problems(bankOf({ a: { ...ONE, variants: 2 }, a_1: ONE })), /a_1\.wav is also made by/);
});

test('the loop-player budget is checked', () => {
  const many = Array.from({ length: 20 }, () => ({ sound: 'l' }));
  const doc = bankOf({ l: LOOP }, { machines: { d: { loops: many } }, beds: { f: { layers: many.slice(0, 5) } } });
  assert.match(problems(doc), /max_loop_players/);
  assert.deepEqual(validateBank({ ...doc, mix: { max_loop_players: 25 } }), []);
});

test('recipe rules: family band, depth, sources, effects, shape', () => {
  assert.match(problems(bankOf({ a: { ...ONE, band: [40, 10000] } })), /family band/);
  assert.match(problems(bankOf({ a: { ...ONE, band: [10, 9000] } })), /family band/);
  assert.match(problems(bankOf({ a: { ...ONE, rate: 11025, band: [40, 9000] } })), /family band 40\.\.5000/);
  assert.deepEqual(validateBank(bankOf({ a: { ...ONE, band: [200, 4000] } })), []);
  assert.match(problems(bankOf({ a: { ...ONE, crush: 16 } })), /crush/);
  assert.match(problems(bankOf({ a: { ...ONE, layers: [{ src: 'kazoo' }] } })), /unknown source "kazoo"/);
  assert.match(problems(bankOf({ a: { ...ONE, layers: [{ src: 'noise', fx: [{ wah: 1 }] }] } })), /unknown effect/);
  assert.match(problems(bankOf({ a: { ...ONE, layers: [] } })), /needs at least one layer/);
  assert.match(problems(bankOf({ a: { ...ONE, dur: undefined } })), /dur: must be/);
  assert.match(problems(bankOf({ a: { ...LOCKED, loop: true } })), /locked or a loop/);
  assert.match(problems(bankOf({ a: { ...ONE, compress: 'ogg' } })), /not pcm or qoa/);
  assert.match(problems(bankOf({ a: { ...ONE, room: 'cave' } })), /unknown room/);
  assert.match(problems(bankOf({ a: { ...ONE, norm: {} } })), /norm: needs/);
  assert.match(problems(bankOf({ a: { ...ONE, variants: 0 } })), /variants/);
  assert.match(problems(bankOf({ a: { ...ONE, variants: 2, per_variant: [{}] } })), /per_variant/);
  assert.match(problems({ schema: 1, game: '_shared', sounds: { a: { ...ONE, ch: 2 } } }), /_shared sounds are 22050 Hz mono/);
});

test('file names: a plain sound is id.wav, variants id_1 .. id_n', () => {
  assert.deepEqual(soundFiles('a', ONE), [{ id: 'a', variant: 0, stem: 'a' }]);
  assert.deepEqual(soundFiles('a', { ...ONE, variants: 2 }).map((f) => f.stem), ['a_1', 'a_2']);
  assert.equal(allFiles(bankOf({ a: { ...ONE, variants: 3 }, b: ONE })).length, 4);
  assert.equal(manifestPathOf('x/audio.json'), 'x/audio_manifest.json');
  assert.equal(manifestPathOf('x/proof_bank.json'), 'x/proof_bank_manifest.json');
});

test('findBanks: _shared first, then each game with a bank', (t) => {
  const root = tempDir(t);
  for (const g of ['zed', '_shared', 'alpha']) {
    fs.mkdirSync(path.join(root, 'assets', g, 'audio'), { recursive: true });
    fs.writeFileSync(path.join(root, 'assets', g, 'audio', 'audio.json'), '{}');
  }
  fs.mkdirSync(path.join(root, 'assets', 'noaudio'));
  assert.deepEqual(findBanks(root).map((b) => b.game), ['_shared', 'alpha', 'zed']);
  assert.deepEqual(findBanks(path.join(root, 'none')), []);
});

test('loadBank names the file and every problem', (t) => {
  const dir = tempDir(t);
  const bad = path.join(dir, 'bad.json');
  fs.writeFileSync(bad, '{"schema":3,"game":"x","sounds":{}}');
  assert.throws(() => loadBank(bad), /bad\.json:\n {2}schema: 3/);
  fs.writeFileSync(bad, 'not json');
  assert.throws(() => loadBank(bad), /bad\.json/);
});

test('wavDifference: equal, within one 12-bit step, past it, another format', () => {
  const a = encodeWav(Int16Array.from([0, 160, 320]), { rate: 22050, ch: 1 });
  assert.equal(wavDifference(a, a), null);
  assert.equal(wavDifference(a, encodeWav(Int16Array.from([16, 160, 304]), { rate: 22050, ch: 1 })), null);
  assert.match(wavDifference(a, encodeWav(Int16Array.from([32, 160, 320]), { rate: 22050, ch: 1 })), /sample 0 differs by 32/);
  assert.match(wavDifference(a, encodeWav(Int16Array.from([0, 160]), { rate: 22050, ch: 1 })), /format differs/);
});
