import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { decodeWav } from '../lib/wav.mjs';
import { AUDIO_DIR, bankOf, readJson, rootWithBank, tempDir } from './helpers.mjs';

const CLI = path.join(AUDIO_DIR, 'generate.mjs');

function run(...args) {
  const r = spawnSync(process.execPath, [CLI, ...args], { encoding: 'utf8' });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

const SOUNDS = {
  loop_a: { dur: 0.5, seed: 1, loop: true, layers: [{ src: 'noise' }] },
  stroke: { dur: 0.1, seed: 2, locked: true, variants: 2, layers: [{ src: 'noise', env: { d: 0.05 } }] },
  shot: { dur: 0.3, seed: 3, layers: [{ src: 'noise', env: { d: 0.2 } }] },
};

function game(t) {
  const made = rootWithBank(t, 'demo', bankOf(SOUNDS, { game: 'demo' }));
  return { ...made, args: [`--game=demo`, `--root=${made.root}`] };
}

test('--help and usage errors', (t) => {
  assert.equal(run('--help').code, 0);
  assert.equal(run().code, 2);
  assert.equal(run('--wat').code, 2);
  assert.equal(run('--game=Bad Id').code, 2);
  assert.equal(run('--game=a', '--bank=b').code, 2);
  assert.match(run(`--game=nope`, `--root=${tempDir(t)}`).err, /audio\.json/);
});

test('writes each WAV, its sidecar and the manifest', (t) => {
  const g = game(t);
  const r = run(...g.args);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /demo: wrote 4 file/);
  for (const stem of ['loop_a', 'stroke_1', 'stroke_2', 'shot']) {
    assert.ok(fs.existsSync(path.join(g.dir, `${stem}.wav`)), stem);
    const text = fs.readFileSync(path.join(g.dir, `${stem}.wav.import`), 'utf8');
    assert.ok(text.includes(`source_file="res://assets/demo/audio/${stem}.wav"`), stem);
  }
  const m = readJson(path.join(g.dir, 'audio_manifest.json'));
  assert.deepEqual(Object.keys(m), ['loop_a', 'stroke_1', 'stroke_2', 'shot']);
  const e = m.stroke_2;
  assert.equal(e.sound, 'stroke');
  assert.equal(e.variant, 1);
  assert.equal(e.rate, 22050);
  assert.equal(e.ch, 1);
  assert.equal(e.preroll, 1764);
  assert.equal(e.frames, 1764 + 2205);
  assert.match(e.sha256, /^[0-9a-f]{64}$/);
  assert.equal(m.loop_a.loop_frames, 11025);
  assert.equal(m.loop_a.frames, 11026);
  assert.equal(decodeWav(fs.readFileSync(path.join(g.dir, 'loop_a.wav'))).frames, 11026);
});

test('--check passes on a fresh render and writes nothing', (t) => {
  const g = game(t);
  run(...g.args);
  const before = fs.statSync(path.join(g.dir, 'shot.wav')).mtimeMs;
  const r = run(...g.args, '--check');
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /demo: matches disk/);
  assert.equal(fs.statSync(path.join(g.dir, 'shot.wav')).mtimeMs, before);
});

test('--check fails on a changed sample, a missing file, a stray file, changed params and a stale manifest', (t) => {
  const g = game(t);
  run(...g.args);
  const wav = path.join(g.dir, 'shot.wav');
  const good = fs.readFileSync(wav);
  const bad = Buffer.from(good);
  bad.writeInt16LE(bad.readInt16LE(44 + 400) + 320, 44 + 400);
  fs.writeFileSync(wav, bad);
  let r = run(...g.args, '--check');
  assert.equal(r.code, 1);
  assert.match(r.out, /shot\.wav: sample 200 differs/);
  fs.writeFileSync(wav, good);

  fs.rmSync(path.join(g.dir, 'stroke_1.wav'));
  r = run(...g.args, '--check');
  assert.equal(r.code, 1);
  assert.match(r.out, /stroke_1\.wav: missing/);
  run(...g.args);

  fs.writeFileSync(path.join(g.dir, 'stray.wav'), good);
  r = run(...g.args, '--check');
  assert.equal(r.code, 1);
  assert.match(r.out, /stray\.wav: on disk but not in the bank/);
  fs.rmSync(path.join(g.dir, 'stray.wav'));

  const side = path.join(g.dir, 'shot.wav.import');
  const text = fs.readFileSync(side, 'utf8');
  fs.writeFileSync(side, text.replace('edit/trim=false', 'edit/trim=true'));
  r = run(...g.args, '--check');
  assert.equal(r.code, 1);
  assert.match(r.out, /edit\/trim: true != false/);
  fs.writeFileSync(side, text);

  const mf = path.join(g.dir, 'audio_manifest.json');
  const m = readJson(mf);
  m.shot.sha256 = 'f'.repeat(64);
  fs.writeFileSync(mf, JSON.stringify(m));
  r = run(...g.args, '--check');
  assert.equal(r.code, 1);
  assert.match(r.out, /manifest: shot sha256/);
});

test('--check tolerates one 12-bit step, the Node-version allowance', (t) => {
  const g = game(t);
  run(...g.args);
  const wav = path.join(g.dir, 'shot.wav');
  const b = fs.readFileSync(wav);
  const m = readJson(path.join(g.dir, 'audio_manifest.json'));
  b.writeInt16LE(b.readInt16LE(44 + 400) + 16, 44 + 400);
  fs.writeFileSync(wav, b);
  const r = run(...g.args, '--check');
  assert.match(r.out, /manifest: shot sha256/, 'the manifest must match the file itself');
  assert.ok(!r.out.includes('differs'));
  assert.ok(m.shot);
});

test('generating again keeps what Godot wrote into a sidecar', (t) => {
  const g = game(t);
  run(...g.args);
  const side = path.join(g.dir, 'shot.wav.import');
  const filled = fs.readFileSync(side, 'utf8').replace('type="AudioStreamWAV"\n', 'type="AudioStreamWAV"\nuid="uid://keepme"\npath="res://.godot/imported/x.sample"\n');
  fs.writeFileSync(side, filled);
  run(...g.args);
  assert.equal(fs.readFileSync(side, 'utf8'), filled);
});

test('a sound that changes format updates its params, keeps the uid', (t) => {
  const g = game(t);
  run(...g.args);
  const side = path.join(g.dir, 'shot.wav.import');
  fs.writeFileSync(side, fs.readFileSync(side, 'utf8').replace('type="AudioStreamWAV"\n', 'type="AudioStreamWAV"\nuid="uid://keepme"\n'));
  const doc = bankOf({ ...SOUNDS, shot: { ...SOUNDS.shot, compress: 'pcm' } }, { game: 'demo' });
  fs.writeFileSync(g.bankPath, JSON.stringify(doc));
  run(...g.args);
  const text = fs.readFileSync(side, 'utf8');
  assert.match(text, /uid="uid:\/\/keepme"/);
  assert.match(text, /compress\/mode=0/);
});

test('--only renders the named sound and keeps the other manifest entries', (t) => {
  const g = game(t);
  run(...g.args);
  fs.rmSync(path.join(g.dir, 'shot.wav'));
  const r = run(...g.args, '--only=shot');
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /wrote 1 file/);
  assert.ok(fs.existsSync(path.join(g.dir, 'shot.wav')));
  assert.equal(Object.keys(readJson(path.join(g.dir, 'audio_manifest.json'))).length, 4);
  assert.equal(run(...g.args, '--only=nope').code, 2);
  assert.equal(run(...g.args, '--only=shot', '--check').code, 0);
});

test('a sound dropped from the bank takes its files with it', (t) => {
  const g = game(t);
  run(...g.args);
  const { shot: _gone, ...rest } = SOUNDS;
  fs.writeFileSync(g.bankPath, JSON.stringify(bankOf(rest, { game: 'demo' })));
  const r = run(...g.args);
  assert.match(r.out, /removed shot\.wav/);
  assert.ok(!fs.existsSync(path.join(g.dir, 'shot.wav')));
  assert.ok(!fs.existsSync(path.join(g.dir, 'shot.wav.import')));
  assert.equal(run(...g.args, '--check').code, 0);
});

test('--game=all takes every bank; --bank takes one and prunes nothing', (t) => {
  const g = game(t);
  const shared = path.join(g.root, 'assets', '_shared', 'audio');
  fs.mkdirSync(shared, { recursive: true });
  fs.writeFileSync(path.join(shared, 'audio.json'), JSON.stringify(bankOf({ tick: { dur: 0.05, seed: 3, layers: [{ src: 'noise' }] } }, { game: '_shared' })));
  const r = run('--game=all', `--root=${g.root}`);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /_shared: wrote 1[\s\S]*demo: wrote 4/);
  assert.equal(run('--game=all', `--root=${g.root}`, '--check').code, 0);

  const dir = tempDir(t);
  const bank = path.join(dir, 'p_bank.json');
  fs.writeFileSync(bank, JSON.stringify(bankOf({ tick: SOUNDS.shot })));
  fs.writeFileSync(path.join(dir, 'other.wav'), 'x');
  assert.equal(run(`--bank=${bank}`, `--root=${dir}`).code, 0);
  assert.ok(fs.existsSync(path.join(dir, 'other.wav')));
  assert.ok(fs.existsSync(path.join(dir, 'p_bank_manifest.json')));
});

test('a bad bank is exit 2 with its key path', (t) => {
  const made = rootWithBank(t, 'demo', { schema: 1, game: 'demo', sounds: { a: { dur: 1, rate: 8000, layers: [{ src: 'noise' }] } } });
  const r = run('--game=demo', `--root=${made.root}`);
  assert.equal(r.code, 2);
  assert.match(r.err, /sounds\.a\.rate: 8000/);
});
