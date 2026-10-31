import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { decodeWav } from '../lib/wav.mjs';
import { AUDIO_DIR, FIXTURE_BANK, readJson, rootWithBank, tempDir } from './helpers.mjs';

const CLI = path.join(AUDIO_DIR, 'preview.mjs');

function run(...args) {
  const r = spawnSync(process.execPath, [CLI, ...args], { encoding: 'utf8' });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

test('usage errors', () => {
  assert.equal(run().code, 2);
  assert.equal(run('--wat').code, 2);
  assert.equal(run('--game=a', '--bank=b').code, 2);
  assert.equal(run('--game=a', '--rpm=0').code, 2);
  assert.equal(run('--help').code, 0);
});

test('a preview writes the mix, one solo per rpm, the bed and the events; build/ gets its .gdignore', (t) => {
  const root = tempDir(t);
  const r = run(`--bank=${FIXTURE_BANK}`, `--root=${root}`, '--no-mp3');
  assert.equal(r.code, 0, r.err);
  const out = path.join(root, 'build', 'audio_preview');
  assert.ok(fs.existsSync(path.join(root, 'build', '.gdignore')), 'or --import takes every preview WAV in');
  for (const name of ['fixture.wav', 'fixture_engine_60.wav', 'fixture_engine_90.wav', 'fixture_engine_110.wav', 'fixture_bed.wav', 'fixture_events.json']) {
    assert.ok(fs.existsSync(path.join(out, name)), name);
  }
  const mix = decodeWav(fs.readFileSync(path.join(out, 'fixture.wav')));
  assert.equal(mix.rate, 44100);
  assert.equal(mix.ch, 2);
  assert.ok(mix.frames / mix.rate > 27);
  const bed = decodeWav(fs.readFileSync(path.join(out, 'fixture_bed.wav')));
  assert.ok(Math.abs(bed.frames / bed.rate - 30) < 0.01);
  const events = readJson(path.join(out, 'fixture_events.json'));
  assert.ok(events.some((e) => e.kind === 'stroke' && e.machine === 'lead' && e.thinned === false));
  assert.ok(events.some((e) => e.kind === 'cue' && e.cue === 'shot_main'));
  assert.ok(events.some((e) => e.kind === 'spot'));
  for (let i = 1; i < events.length; i++) assert.ok(events[i].t >= events[i - 1].t);
  assert.ok(!fs.existsSync(path.join(out, 'fixture.mp3')), '--no-mp3');
});

test('a preview is deterministic', (t) => {
  const a = tempDir(t);
  const b = tempDir(t);
  run(`--bank=${FIXTURE_BANK}`, `--root=${a}`, '--no-mp3');
  run(`--bank=${FIXTURE_BANK}`, `--root=${b}`, '--no-mp3');
  const read = (r) => fs.readFileSync(path.join(r, 'build', 'audio_preview', 'fixture.wav'));
  assert.ok(read(a).equals(read(b)));
});

test('--rpm overrides the moving segments', (t) => {
  const root = tempDir(t);
  assert.equal(run(`--bank=${FIXTURE_BANK}`, `--root=${root}`, '--no-mp3', '--rpm=70,100,125').code, 0);
  const out = path.join(root, 'build', 'audio_preview');
  for (const rpm of [70, 100, 125]) assert.ok(fs.existsSync(path.join(out, `fixture_engine_${rpm}.wav`)));
  assert.ok(!fs.existsSync(path.join(out, 'fixture_engine_60.wav')));
});

test('a solo holds exactly ten revolutions plus its tail', (t) => {
  const root = tempDir(t);
  run(`--bank=${FIXTURE_BANK}`, `--root=${root}`, '--no-mp3');
  const w = decodeWav(fs.readFileSync(path.join(root, 'build', 'audio_preview', 'fixture_engine_60.wav')));
  assert.ok(Math.abs(w.frames / w.rate - 10.3) < 0.01);
});

test('--game=all skips a bank with no preview; a bank-less game is exit 2', (t) => {
  const doc = readJson(FIXTURE_BANK);
  const made = rootWithBank(t, 'demo', { ...doc, game: 'demo' });
  fs.mkdirSync(path.join(made.root, 'assets', '_shared', 'audio'), { recursive: true });
  fs.writeFileSync(path.join(made.root, 'assets', '_shared', 'audio', 'audio.json'), JSON.stringify({ schema: 1, game: '_shared', sounds: {} }));
  const r = run('--game=all', `--root=${made.root}`, '--no-mp3');
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /wrote 6 preview/);
  assert.ok(fs.existsSync(path.join(made.root, 'build', 'audio_preview', 'demo.wav')));
  assert.equal(run('--game=nope', `--root=${made.root}`).code, 2);
  assert.match(run('--game=_shared', `--root=${made.root}`).err, /no preview block/);
});

test('ffmpeg, where present, makes the mp3 and spectrograms; never required', (t) => {
  const has = spawnSync('ffmpeg', ['-hide_banner', '-version'], { stdio: 'ignore' }).status === 0;
  if (!has) {
    t.skip('no ffmpeg on this machine');
    return;
  }
  const root = tempDir(t);
  assert.equal(run(`--bank=${FIXTURE_BANK}`, `--root=${root}`).code, 0);
  const out = path.join(root, 'build', 'audio_preview');
  for (const name of ['fixture.mp3', 'fixture.png', 'fixture_engine_90.png', 'fixture.ebur128.txt']) assert.ok(fs.existsSync(path.join(out, name)), name);
  assert.ok(fs.statSync(path.join(out, 'fixture.mp3')).size > 1000);
});
