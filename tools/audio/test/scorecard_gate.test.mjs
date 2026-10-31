// SPEC_AUDIO 6.2: every bank on disk with a preview block passes the scorecard, so these rows are
// permanent gates. In phase 0 that is the fixture; each game's branch adds its own bank.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { findBanks, loadBank } from '../lib/bank.mjs';
import { BankAudio } from '../lib/offline_mix.mjs';
import { detectOnsets, scoreBank, scoreBankFile } from '../lib/score.mjs';
import { AUDIO_DIR, FIXTURE_BANK, REPO, SHARED_BANK, readJson, tempDir } from './helpers.mjs';

const CLI = path.join(AUDIO_DIR, 'scorecard.mjs');
const shared = new BankAudio(loadBank(SHARED_BANK), path.dirname(SHARED_BANK));

function card(doc) {
  return scoreBank(doc, null, { shared });
}

function row(c, id) {
  const r = c.rows.find((x) => x.id === id);
  assert.ok(r, id);
  return r;
}

const fixture = readJson(FIXTURE_BANK);

test('the fixture passes every row, and every row is there', () => {
  const c = scoreBankFile(FIXTURE_BANK, { root: REPO });
  assert.deepEqual(c.fails, []);
  assert.equal(c.pass, true);
  const ids = c.rows.map((r) => r.id);
  for (let i = 1; i <= 10; i++) assert.ok(ids.includes(`D${i}`), `D${i}`);
  for (let i = 1; i <= 16; i++) assert.ok(ids.includes(`A${i}`), `A${i}`);
});

test('every bank on disk with a preview block passes', () => {
  for (const { game, bankPath } of findBanks(REPO)) {
    const doc = loadBank(bankPath);
    if (!doc.preview) continue;
    const c = scoreBankFile(bankPath, { root: REPO });
    assert.deepEqual(c.fails, [], game);
  }
});

test('D1 is computed from the audio: a stroke with no attack of its own loses its onsets', () => {
  const doc = structuredClone(fixture);
  doc.sounds.valve = { dur: 1.5, seed: 1, locked: true, layers: [{ src: 'sine', f: 800, env: { a: 0.3 } }] };
  const r = row(card(doc), 'D1');
  assert.equal(r.pass, false);
  assert.match(r.note, /valve@/);
});

test('D4 catches a ring past the stop', () => {
  const doc = structuredClone(fixture);
  doc.sounds.fire_a.dur = 0.9;
  doc.sounds.fire_a.layers.push({ src: 'sine', f: 90, gain: 1.0 });
  assert.equal(row(card(doc), 'D4').pass, false);
});

test('a preview with no stop fails D4 plainly', () => {
  const doc = structuredClone(fixture);
  doc.preview.segments = doc.preview.segments.filter((s) => s.rpm > 0);
  const r = row(card(doc), 'D4');
  assert.equal(r.pass, false);
  assert.equal(r.value, 'no stop');
});

test('D5 needs the _shared bank, and fails a mix that buries the prompts', () => {
  const none = scoreBank(fixture, null, { shared: null });
  assert.equal(row(none, 'D5').pass, false);
  const doc = structuredClone(fixture);
  doc.machines.engine.events[0].db = 14;
  doc.machines.engine.loops[0].db = 6;
  assert.equal(row(card(doc), 'D5').pass, false);
});

test('D4: a machine layer with no min_rpm still stops dead, as the kit stops it', () => {
  const doc = structuredClone(fixture);
  for (const l of doc.machines.engine.loops) delete l.min_rpm;
  assert.equal(row(card(doc), 'D4').pass, true);
});

test('D5 reads the prompts as HudLayer plays them, 4 dB under the file', () => {
  const sharedDoc = readJson(SHARED_BANK);
  const quiet = structuredClone(sharedDoc);
  for (const name of ['warning', 'rescue']) quiet.sounds[name].norm.peak -= 4;
  const asFiled = row(scoreBank(fixture, null, { shared: new BankAudio(sharedDoc, null) }), 'D5');
  const down = row(scoreBank(fixture, null, { shared: new BankAudio(quiet, null) }), 'D5');
  assert.ok(asFiled.pass && asFiled.value >= 6, `${asFiled.value}`);
  assert.ok(Math.abs(asFiled.value - down.value - 4) < 0.1, `${asFiled.value} vs ${down.value}`);
  assert.equal(down.pass, false, 'files 4 dB down, the levels from before the voice was counted, fail');
});

test('A rows see a monotone drone: flux, crest and level', () => {
  const doc = structuredClone(fixture);
  doc.sounds.body.layers = [{ src: 'sine', f: 110, gain: 0.7 }];
  doc.machines.engine.events = [];
  doc.machines.engine.loops = [{ sound: 'body', db: 0, min_rpm: 8, other: true, pitch_by: [{ param: 'rpm', ratio: 90 }] }];
  const c = card(doc);
  assert.equal(row(c, 'A3').pass, false, 'flux');
  assert.equal(row(c, 'A4').pass, false, 'crest');
  assert.equal(row(c, 'A5').pass, false, 'nothing repeats per revolution');
});

test('A5 catches a machine gun: every stroke identical', () => {
  const doc = structuredClone(fixture);
  doc.machines.engine.loops = [];
  doc.machines.engine.events = [{ at: [0.25], sound: 'one' }];
  doc.sounds.one = { dur: 0.05, seed: 1, locked: true, layers: [{ src: 'noise', env: { a: 0.0005, d: 0.04 } }] };
  const r = row(card(doc), 'A5');
  assert.equal(r.pass, false, String(r.value));
});

test('A1 and A2 read levels', () => {
  const doc = structuredClone(fixture);
  doc.machines.engine.events[0].db -= 14;
  doc.machines.engine.loops[0].db -= 14;
  const c = card(doc);
  assert.equal(row(c, 'A1').pass, false);
  assert.equal(row(c, 'A2').pass, false);
});

test('A9 and A11 cannot be waived; other A rows can, and it shows', () => {
  const doc = structuredClone(fixture);
  doc.machines.engine.events[0].db -= 14;
  doc.machines.engine.loops[0].db -= 14;
  doc.preview.waive = { A1: 'not allowed', A2: 'a stated musical reason' };
  const c = card(doc);
  assert.equal(row(c, 'A2').waived, 'a stated musical reason');
  assert.equal(row(c, 'A1').waived, undefined);
  assert.ok(c.fails.includes('A1'));
  assert.ok(!c.fails.includes('A2'));
});

test('a D row never takes a waiver', () => {
  const doc = structuredClone(fixture);
  doc.preview.segments = doc.preview.segments.filter((s) => s.rpm > 0);
  doc.preview.waive = { D4: 'no' };
  assert.ok(card(doc).fails.includes('D4'));
});

test('A6, A7 and A14 are not-applicable until a bank asks for them', () => {
  const doc = structuredClone(fixture);
  delete doc.preview.checks;
  const c = card(doc);
  for (const id of ['A6', 'A7', 'A14']) assert.equal(row(c, id).value, 'n/a', id);
});

test('A14 names a missing event; A16 and A12 are n/a with no bed', () => {
  const doc = structuredClone(fixture);
  doc.preview.checks.a14 = { cue: 'zz' };
  delete doc.preview.bed;
  const c = card(doc);
  assert.equal(row(c, 'A14').pass, false);
  assert.equal(row(c, 'A12').value, 'n/a');
  assert.equal(row(c, 'A16').value, 'n/a');
});

test('D9 reads the cap of a game bank', (t) => {
  const root = tempDir(t);
  const dir = path.join(root, 'assets', 'workout', 'audio');
  fs.mkdirSync(dir, { recursive: true });
  const bank = path.join(dir, 'audio.json');
  fs.writeFileSync(bank, JSON.stringify({ ...fixture, game: 'workout' }));
  fs.writeFileSync(path.join(dir, 'big.wav'), Buffer.alloc(4_100_000));
  const c = scoreBankFile(bank, { root, sharedPath: SHARED_BANK });
  assert.equal(row(c, 'D9').pass, false);
});

test('onsets: found, spaced, and a steady tone has none past its start', () => {
  const rate = 44100;
  const x = new Float64Array(rate);
  for (const at of [0.1, 0.4, 0.7]) {
    const i0 = Math.round(at * rate);
    for (let i = 0; i < 2000; i++) x[i0 + i] = Math.sin(i * 0.3) * Math.exp(-i / 500);
  }
  const on = detectOnsets(x);
  assert.equal(on.length, 3);
  on.forEach((t, i) => assert.ok(Math.abs(t - [0.1, 0.4, 0.7][i]) < 0.002));
  const tone = new Float64Array(rate);
  for (let i = 0; i < rate; i++) tone[i] = Math.sin(i * 0.1);
  assert.ok(detectOnsets(tone).length <= 1);
  assert.deepEqual(detectOnsets(new Float64Array(100)), []);
});

test('the CLI writes the card and its exit code is the verdict', (t) => {
  const root = tempDir(t);
  fs.mkdirSync(path.join(root, 'assets', '_shared', 'audio'), { recursive: true });
  for (const f of fs.readdirSync(path.dirname(SHARED_BANK))) fs.copyFileSync(path.join(path.dirname(SHARED_BANK), f), path.join(root, 'assets', '_shared', 'audio', f));
  const good = spawnSync(process.execPath, [CLI, `--bank=${FIXTURE_BANK}`, `--root=${root}`], { encoding: 'utf8' });
  assert.equal(good.status, 0, good.stdout + good.stderr);
  const saved = readJson(path.join(root, 'build', 'audio_preview', 'fixture_scorecard.json'));
  assert.equal(saved.pass, true);
  assert.ok(fs.existsSync(path.join(root, 'build', '.gdignore')));
  const doc = structuredClone(fixture);
  doc.machines.engine.events[0].db -= 14;
  doc.machines.engine.loops[0].db -= 14;
  const bad = path.join(root, 'bad.json');
  fs.writeFileSync(bad, JSON.stringify(doc));
  const r = spawnSync(process.execPath, [CLI, `--bank=${bad}`, `--root=${root}`, '--json'], { encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.equal(JSON.parse(r.stdout).pass, false);
  assert.equal(spawnSync(process.execPath, [CLI], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync(process.execPath, [CLI, '--wat'], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync(process.execPath, [CLI, '--game=nope', `--root=${root}`], { encoding: 'utf8' }).status, 2);
});
