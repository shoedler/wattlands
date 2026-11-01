// SPEC_AUDIO 6.2: every bank on disk with a preview block passes the scorecard, so these rows are
// permanent gates. In phase 0 that is the fixture; each game's branch adds its own bank.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { findBanks, loadBank } from '../lib/bank.mjs';
import { BankAudio } from '../lib/offline_mix.mjs';
import { detectOnsets, runtimePitches, scoreBank, scoreBankFile } from '../lib/score.mjs';
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
  for (let i = 1; i <= 17; i++) assert.ok(ids.includes(`A${i}`), `A${i}`);
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

test('D5 hears the loudest moment, not only the midpoint', () => {
  const doc = structuredClone(fixture);
  const moving = doc.preview.segments.filter((s) => s.rpm > 0).reduce((a, s) => a + s.s, 0);
  const calm = row(card(doc), 'D5');
  doc.cues = { ...doc.cues, late_blast: { hits: [{ sound: 'body', db: 12, bus: 'Sfx', priority: 6 }] } };
  doc.preview.events = [...(doc.preview.events ?? []), { t: moving - 0.5, cue: 'late_blast', vars: {} }];
  const loud = row(card(doc), 'D5');
  assert.ok(calm.pass, `${calm.value}`);
  assert.equal(loud.pass, false, `${loud.value} ${loud.note}`);
  assert.ok(loud.value < calm.value - 3, `${loud.value} against ${calm.value}`);
  const t = Number(loud.note.match(/at ([\d.]+) s/)[1]);
  assert.ok(Math.abs(t - (moving - 0.5)) < 1, `the worst of it, ${loud.note}, is on the blast at ${moving - 0.5}`);
});

test('D4 reads a stop anywhere in the cycle: a ring that few stops would meet still fails, and names the stroke', () => {
  const doc = structuredClone(fixture);
  // Once in 8 revolutions, with a ring long enough to reach past the 400 ms.
  doc.sounds.late_ring = { dur: 0.7, seed: 9, locked: true, layers: [{ src: 'sine', f: 900, gain: 0.8, env: { a: 0.001, h: 0.45, d: 0.2, curve: 'lin' } }] };
  doc.machines.slow = { bus: 'Machines', events: [{ at: [0.13], sound: 'late_ring', db: -6, lead_only: true }] };
  doc.preview.others = [...(doc.preview.others ?? []), { machine: 'slow', lead: true, rpm_scale: 1 / 8 }];
  const swept = row(card(doc), 'D4');
  assert.equal(swept.pass, false, `${swept.value} ${swept.note}`);
  assert.match(swept.note, /late_ring/);
  doc.sounds.late_ring.dur = 0.3;
  doc.sounds.late_ring.layers[0].env = { a: 0.001, d: 0.28, curve: 'lin' };
  assert.equal(row(card(doc), 'D4').pass, true, 'and a stroke that rings out in time passes');
});

test('D5 hears what HudLayer plays over the moment: preview.hud, and prompts just ahead of it', () => {
  const doc = structuredClone(fixture);
  const quiet = row(card(doc), 'D5');
  doc.preview.hud = [{ t: 10, sound: 'phase' }, { t: 10, sound: 'toast' }, { t: 10, sound: 'lap' }, { t: 10, sound: 'results' }, { t: 10, sound: 'ui_confirm' }];
  const r = row(card(doc), 'D5');
  assert.ok(r.value < quiet.value, `${r.value} against ${quiet.value}`);
  assert.match(r.note, /at (9\.6|9\.8|10) s/);
});

test("D6 has the game in it: the lead's own machines, its loops, its cues and the coast", () => {
  const doc = structuredClone(fixture);
  const bare = row(card(doc), 'D6').value;
  doc.loops = { ...(doc.loops ?? {}), a: { bus: 'Sfx', layers: [{ sound: doc.machines.engine.loops[0].sound, db: -30 }] } };
  doc.preview.loops = [...(doc.preview.loops ?? []), { id: 'a', t0: 0, t1: 1, params: {} }];
  const more = row(card(doc), 'D6').value;
  assert.equal(Number(more.split('/')[2]), Number(bare.split('/')[2]) + 1, `${bare} then ${more}: held for the whole scene`);
  doc.machines.tap = { bus: 'Sfx', events: [{ at: [0, 0.5], sound: doc.machines.engine.events[0].sound, db: -20, lead_only: true }] };
  doc.preview.others = [...(doc.preview.others ?? []), { machine: 'tap', lead: true }];
  assert.ok(Number(row(card(doc), 'D6').value.split('/')[1]) > Number(more.split('/')[1]), 'the Sfx pool counts it');
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

test('P1-P5 are n/a for a bank with no projectiles, and count flights when it has them', () => {
  const plain = card(structuredClone(fixture));
  for (const id of ['P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'P7', 'P8', 'P9']) assert.equal(row(plain, id).value, 'n/a', id);
  const doc = structuredClone(fixture);
  doc.sounds.air = { dur: 1, rate: 22050, ch: 1, seed: 9, loop: true, compress: 'pcm', layers: [{ src: 'noise', color: 'white', gain: 1, fx: [{ bp: { f: 2500, q: 0.7 } }] }] };
  const flying = { sound: 'air', db: 3, flight: { dur_var: 'f' } };
  doc.cues.flies = { hits: [flying] };
  doc.cues.silent_shot = { hits: [{ sound: Object.keys(doc.cues).length ? doc.cues.shot_main.hits[0].sound : 'air', db: 0 }] };
  doc.preview.events = [
    ...doc.preview.events,
    { t: 3, cue: 'flies', vars: { f: 2 } },
    { t: 5.5, cue: 'silent_shot' },
    { t: 8, cue: 'shot_main' },
  ];
  doc.preview.checks = { ...doc.preview.checks, projectiles: { shots: ['flies', 'silent_shot'], surfaces: { dirt: ['shot_main'], wood: ['silent_shot'] } } };
  const c2 = card(doc);
  assert.equal(row(c2, 'P1').pass, false, 'a shot with no flight fails it');
  assert.match(String(row(c2, 'P1').value), /flies 1\/1/);
  assert.match(String(row(c2, 'P1').value), /silent_shot 0\/1/);
  assert.equal(row(c2, 'P2').value, 1);
  assert.ok(row(c2, 'P3').pass, 'a loud flight over the fixture stands out');
  doc.cues.flies.hits[0].db = -40;
  assert.equal(row(card(doc), 'P3').pass, false, 'and a buried one does not');
});

test('A17 reads a file at the pitch it plays: reported for every bank, held where the bank asks', () => {
  const doc = structuredClone(fixture);
  doc.sounds.hisser = { dur: 0.5, rate: 22050, ch: 1, seed: 7, layers: [{ src: 'noise', color: 'white', gain: 1 }] };
  doc.cues.hisser = { hits: [{ sound: 'hisser', db: -30, pitch: 1.5 }] };
  doc.preview.events = [...doc.preview.events, { t: 3, cue: 'hisser' }];
  assert.ok(row(card(doc), 'A17').value > -32, 'white noise up to 9 kHz reaches 13.5 kHz');
  assert.equal(row(card(doc), 'A17').pass, true, 'only reported');
  doc.preview.checks = { ...doc.preview.checks, a17: true };
  assert.equal(row(card(doc), 'A17').pass, false, 'held');
  assert.equal(row(card(doc), 'A9').pass, true, 'A9 reads the file as it is');
});

test('runtimePitches: every place a bank plays a sound', () => {
  const pitches = runtimePitches({
    machines: { m: { events: [{ sound: 'a', pitch_table: [0, 0.1] }], loops: [{ sound: 'b', pitch_by: [{ param: 'rpm', points: [[0, 1], [10, 1.8]] }] }] } },
    beds: { x: { spots: [{ sound: 'c', pitch: [0.9, 1.3] }] } },
    cues: { y: { hits: [{ sound: 'd', pitch: 1.2, pitch_var: 'p', flight: { pitch: [[0, 1.1], [1, 0.8]] } }] } },
    preview: { events: [{ cue: 'y', vars: { p: 1.05 } }] },
  });
  assert.ok(Math.abs(pitches.get('a') - 1.1) < 1e-9);
  assert.equal(pitches.get('b'), 1.8);
  assert.equal(pitches.get('c'), 1.3);
  assert.ok(Math.abs(pitches.get('d') - 1.2 * 1.1 * 1.05) < 1e-9);
});

test('P4 hears the flights too: an impact under a loud Sfx bus does not pass', () => {
  const doc = structuredClone(fixture);
  doc.sounds.air = { dur: 1, rate: 22050, ch: 1, seed: 9, loop: true, compress: 'pcm', layers: [{ src: 'noise', color: 'white', gain: 1, fx: [{ bp: { f: 2000, q: 0.7 } }] }] };
  doc.sounds.tap = { dur: 0.1, rate: 22050, ch: 1, seed: 11, layers: [{ src: 'noise', color: 'white', env: { a: 0.001, d: 0.09 }, gain: 1, fx: [{ bp: { f: 2000, q: 0.7 } }] }] };
  doc.cues.flies = { hits: [{ sound: 'air', db: 6, flight: { dur_var: 'f' } }] };
  doc.cues.tap = { hits: [{ sound: 'tap', db: -24 }] };
  doc.preview.events = [...doc.preview.events, { t: 3, cue: 'flies', vars: { f: 2 } }, { t: 4, cue: 'tap' }];
  doc.preview.checks = { ...doc.preview.checks, projectiles: { shots: ['flies'], surfaces: { dirt: ['tap'] } } };
  assert.equal(row(card(doc), 'P4').pass, false);
  doc.preview.checks.projectiles.surfaces.dirt.push('never_played');
  assert.match(String(row(card(doc), 'P4').value), /missing never_played/);
});

test('P4 leaves crowd hits out of its medians, and no other hit', () => {
  const doc = structuredClone(fixture);
  doc.mix = { ...doc.mix, crowd_voices: 16 };
  doc.sounds.air = { dur: 1, rate: 22050, ch: 1, seed: 9, loop: true, compress: 'pcm', layers: [{ src: 'noise', color: 'white', gain: 1, fx: [{ bp: { f: 2000, q: 0.7 } }] }] };
  doc.sounds.tap = { dur: 0.1, rate: 22050, ch: 1, seed: 11, layers: [{ src: 'noise', color: 'white', env: { a: 0.001, d: 0.09 }, gain: 1, fx: [{ bp: { f: 2000, q: 0.7 } }] }] };
  doc.sounds.thud = { dur: 0.1, rate: 22050, ch: 1, seed: 12, layers: [{ src: 'noise', color: 'white', env: { a: 0.001, d: 0.09 }, gain: 1, fx: [{ bp: { f: 2000, q: 0.7 } }] }] };
  doc.cues.flies = { hits: [{ sound: 'air', db: -18, flight: { dur_var: 'f' } }] };
  doc.cues.small = { hits: [{ sound: 'tap', db: -30, crowd: true }] };
  doc.cues.big = { hits: [{ sound: 'thud', db: 6 }] };
  doc.preview.events = [...doc.preview.events, { t: 3, cue: 'flies', vars: { f: 3 } }, { t: 4, cue: 'big' }, { t: 4.2, cue: 'small' }, { t: 4.4, cue: 'small' }, { t: 4.6, cue: 'small' }];
  doc.preview.checks = { ...doc.preview.checks, projectiles: { shots: ['flies'], surfaces: { dirt: ['small', 'big'] } } };
  const withBig = row(card(doc), 'P4');
  assert.equal(withBig.pass, true, `three quiet crowd hits do not take the median down: ${withBig.note}`);
  doc.cues.small.hits[0].crowd = false;
  assert.equal(row(card(doc), 'P4').pass, false, 'the same hits, not a crowd');
});

function rowsFrom(t, reports, spec = { coverage: 0.95, contrast: 2, body_over_miss: 6 }) {
  const dir = tempDir(t);
  const names = reports.map((r, i) => {
    fs.writeFileSync(path.join(dir, `r${i}.json`), JSON.stringify(r));
    return `r${i}.json`;
  });
  const doc = structuredClone(fixture);
  doc.preview.checks = { ...doc.preview.checks, real_wave: { reports: names, ...spec } };
  return scoreBank(doc, null, { shared, root: dir });
}

const report = (coverage, contrast, body, miss) => ({ arrows: { coverage }, landing_contrast: { ratio: contrast }, one_arrow: { all_400_6000: { body: { median: body }, miss: { median: miss } } } });

test('R1-R3 read the tracked reports, every one of them', (t) => {
  const good = report(1, 3, 5, -7);
  const pass = (c, id) => row(c, id).pass;
  assert.equal(pass(rowsFrom(t, [good, good]), 'R1'), true);
  assert.equal(pass(rowsFrom(t, [good, good]), 'R2'), true);
  assert.equal(pass(rowsFrom(t, [good, good]), 'R3'), true);
  assert.equal(pass(rowsFrom(t, [good, report(0.15, 3, 5, -7)]), 'R1'), false, 'one arrow in seven');
  assert.equal(pass(rowsFrom(t, [good, report(1, 1.5, 5, -7)]), 'R2'), false, 'no more onsets where arrows land');
  assert.equal(pass(rowsFrom(t, [good, report(1, 3, 5, 2)]), 'R3'), false, 'a body no louder than a miss');
});

test('without checks.real_wave R1-R3 say so', () => {
  assert.equal(row(card(structuredClone(fixture)), 'R1').value, 'n/a');
});

test('P6 holds the 2-8 kHz of the master where a bank asks', () => {
  const doc = structuredClone(fixture);
  doc.preview.checks = { ...doc.preview.checks, projectiles: { shots: [], surfaces: {} }, ear_band: { limit: -60 } };
  assert.equal(row(card(doc), 'P6').pass, false);
  doc.preview.checks.ear_band.limit = 0;
  assert.equal(row(card(doc), 'P6').pass, true);
});

test('A14 reads the median of a cue\'s firings, not its quietest moment', () => {
  const doc = structuredClone(fixture);
  const shot = doc.preview.checks.a14.cue;
  const one = doc.preview.events.find((e) => e.cue === shot);
  doc.preview.events = [...doc.preview.events, { ...one, t: one.t + 0.05 }, { ...one, t: one.t + 0.1 }];
  assert.match(String(row(card(doc), 'A14').note), /5 firings/);
});

test('P8 hears other flights, P9 reads the ground apart from a target in the mix', () => {
  const doc = structuredClone(fixture);
  doc.sounds.air = { dur: 1, rate: 22050, ch: 1, seed: 9, loop: true, compress: 'pcm', layers: [{ src: 'noise', color: 'white', gain: 1, fx: [{ bp: { f: 1700, q: 0.7 } }] }] };
  doc.sounds.mud = { dur: 0.1, rate: 22050, ch: 1, seed: 11, layers: [{ src: 'noise', color: 'white', env: { a: 0.001, d: 0.09 }, gain: 1, fx: [{ bp: { f: 400, q: 1 } }] }] };
  doc.sounds.tok = { dur: 0.1, rate: 22050, ch: 1, seed: 12, layers: [{ src: 'noise', color: 'white', env: { a: 0.001, d: 0.09 }, gain: 1, fx: [{ bp: { f: 4000, q: 1 } }] }] };
  doc.cues.fly_own = { hits: [{ sound: 'air', db: 3, flight: { dur_var: 'f' } }] };
  doc.cues.fly_other = { hits: [{ sound: 'air', db: 12, flight: { dur_var: 'f' } }] };
  doc.cues.mud = { hits: [{ sound: 'mud', db: 0 }] };
  doc.cues.tok = { hits: [{ sound: 'tok', db: 0 }] };
  doc.preview.events = [...doc.preview.events, { t: 3, cue: 'fly_own', vars: { f: 2 } }, { t: 3, cue: 'fly_other', vars: { f: 2 } }, { t: 6, cue: 'mud' }, { t: 7, cue: 'tok' }];
  doc.preview.checks = { ...doc.preview.checks, projectiles: { shots: ['fly_own'], surfaces: { dirt: ['mud'], wood: ['tok'] }, own_flight: { cue: 'fly_own', band: [1000, 2400] } } };
  const c2 = card(doc);
  assert.equal(row(c2, 'P8').pass, false, 'a louder flight beside it');
  assert.equal(row(c2, 'P9').pass, true, row(c2, 'P9').value);
  doc.cues.tok.hits[0].sound = 'mud';
  assert.equal(row(card(doc), 'P9').pass, false, 'one sound on two surfaces');
});
