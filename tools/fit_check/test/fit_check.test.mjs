// node:test suite for tools/fit_check/check.mjs (BRIEF 3.8; OWNERSHIP TL4).
// testdata/gdscript_ten_minute_ride.fit (+ .json) was written by the GDScript FitEncoder and
// RideRecorder (tests/rides/test_ride_recorder.gd); other files are built here with the SDK's
// own Encoder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Encoder, Profile } from '@garmin/fitsdk';

const here = path.dirname(fileURLToPath(import.meta.url));
const CHECK = path.join(here, '..', 'check.mjs');
const FIXTURE = path.join(here, '..', 'testdata', 'gdscript_ten_minute_ride.fit');

function run(args, env = {}) {
  const r = spawnSync(process.execPath, [CHECK, ...args], { encoding: 'utf8', env: { ...process.env, ...env } });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

function tmpdir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'fit-check-test-'));
}

/** A small activity built with the SDK's Encoder (sport configurable). */
function sdkActivity({ sport = 'cycling', subSport = 'virtualActivity', laps = 2, seconds = 20 } = {}) {
  const enc = new Encoder();
  const start = new Date('2027-01-15T08:00:00Z');
  const at = (s) => new Date(start.getTime() + s * 1000);
  enc.onMesg(Profile.MesgNum.FILE_ID, { type: 'activity', manufacturer: 'development', product: 1, timeCreated: start });
  enc.onMesg(Profile.MesgNum.EVENT, { timestamp: start, event: 'timer', eventType: 'start' });
  for (let i = 0; i <= seconds; i++) enc.onMesg(Profile.MesgNum.RECORD, { timestamp: at(i), power: 200, cadence: 90, distance: i * 8 });
  enc.onMesg(Profile.MesgNum.EVENT, { timestamp: at(seconds), event: 'timer', eventType: 'stopAll' });
  const per = seconds / laps;
  for (let l = 0; l < laps; l++) {
    enc.onMesg(Profile.MesgNum.LAP, {
      messageIndex: l, timestamp: at((l + 1) * per), startTime: at(l * per), totalElapsedTime: per, totalTimerTime: per,
      totalWork: per * 200, event: 'lap', eventType: 'stop',
    });
  }
  enc.onMesg(Profile.MesgNum.SESSION, {
    messageIndex: 0, timestamp: at(seconds), startTime: start, sport, subSport, totalElapsedTime: seconds,
    totalTimerTime: seconds, totalWork: seconds * 200, numLaps: laps, firstLapIndex: 0, event: 'session', eventType: 'stop',
  });
  enc.onMesg(Profile.MesgNum.ACTIVITY, { timestamp: at(seconds), numSessions: 1, totalTimerTime: seconds, type: 'manual', event: 'activity', eventType: 'stop' });
  return Buffer.from(enc.close());
}

test('the GDScript-encoded fixture passes with the right lap count', () => {
  const r = run([FIXTURE, '--expect-laps=5']);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^OK {3}/m);
  assert.match(r.out, /records 601, laps 5, cycling\/virtualActivity/);
  assert.match(r.out, /matches its summary/);
  assert.match(r.out, /lap 5: start 2027-01-15T08:07:00Z \(\+420 s\), duration 180 s, "Cool-down"/);
  assert.match(r.out, /fit_check: 1 file\(s\), 0 failed/);
});

test('--json output schema', () => {
  const r = run([FIXTURE, '--json']);
  assert.equal(r.code, 0);
  const j = JSON.parse(r.out);
  assert.equal(j.ok, true);
  assert.equal(j.decoder, 'fitsdk');
  assert.equal(j.files.length, 1);
  const f = j.files[0];
  assert.deepEqual(Object.keys(f).sort(), ['decoder', 'errors', 'laps', 'ok', 'path', 'records', 'session', 'summary_checked']);
  assert.equal(f.records, 601);
  assert.equal(f.summary_checked, true);
  assert.equal(f.session.sport, 'cycling');
  assert.equal(f.session.sub_sport, 'virtualActivity');
  assert.equal(f.session.elapsed_s, 600);
  assert.equal(f.session.num_laps, 5);
  assert.deepEqual(f.laps.map((l) => l.name), ['Warm-up', 'Work 1', 'Recovery', 'Work 2', 'Cool-down']);
  assert.deepEqual(f.laps.map((l) => l.start_offset_s), [0, 120, 240, 300, 420]);
  assert.deepEqual(f.laps.map((l) => l.duration_s), [120, 120, 60, 120, 180]);
});

test('a lap-count mismatch fails', () => {
  const r = run([FIXTURE, '--expect-laps=4']);
  assert.equal(r.code, 1);
  assert.match(r.out, /expected 4 laps, found 5/);
});

test('a corrupt file fails the integrity check', () => {
  const dir = tmpdir();
  const bad = path.join(dir, 'bad.fit');
  const bytes = fs.readFileSync(FIXTURE);
  bytes[100] ^= 0xff;
  fs.writeFileSync(bad, bytes);
  const r = run([bad]);
  assert.equal(r.code, 1);
  assert.match(r.out, /checkIntegrity/);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('a summary mismatch fails', () => {
  const dir = tmpdir();
  fs.copyFileSync(FIXTURE, path.join(dir, 'ride.fit'));
  const sum = JSON.parse(fs.readFileSync(FIXTURE.replace(/\.fit$/, '.json'), 'utf8'));
  sum.kj += 1;
  sum.records -= 1;
  fs.writeFileSync(path.join(dir, 'ride.json'), JSON.stringify(sum));
  const r = run([path.join(dir, 'ride.fit')]);
  assert.equal(r.code, 1);
  assert.match(r.out, /summary mismatch: records/);
  assert.match(r.out, /summary mismatch: work kJ/);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('directories are searched recursively', () => {
  const dir = tmpdir();
  fs.mkdirSync(path.join(dir, 'a', 'b'), { recursive: true });
  fs.copyFileSync(FIXTURE, path.join(dir, 'one.fit'));
  fs.copyFileSync(FIXTURE, path.join(dir, 'a', 'b', 'two.FIT'));
  fs.writeFileSync(path.join(dir, 'a', 'notes.txt'), 'x');
  const r = run([dir, '--json']);
  assert.equal(r.code, 0, r.out);
  assert.equal(JSON.parse(r.out).files.length, 2);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('sport and sub_sport come from the SDK profile', () => {
  const dir = tmpdir();
  fs.writeFileSync(path.join(dir, 'ok.fit'), sdkActivity());
  fs.writeFileSync(path.join(dir, 'run.fit'), sdkActivity({ sport: 'running', subSport: 'generic' }));
  const ok = run([path.join(dir, 'ok.fit'), '--expect-laps=2']);
  assert.equal(ok.code, 0, ok.out);
  const r = run([path.join(dir, 'run.fit')]);
  assert.equal(r.code, 1);
  assert.match(r.out, /session sport is running, expected cycling/);
  assert.match(r.out, /sub_sport is generic, expected virtualActivity/);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('too few records for the elapsed time fail', () => {
  const dir = tmpdir();
  const f = path.join(dir, 'sparse.fit');
  // 20 records for a 100 s session is not one per second.
  const enc = new Encoder();
  const start = new Date('2027-01-15T08:00:00Z');
  const at = (s) => new Date(start.getTime() + s * 1000);
  enc.onMesg(Profile.MesgNum.FILE_ID, { type: 'activity', manufacturer: 'development', product: 1, timeCreated: start });
  enc.onMesg(Profile.MesgNum.EVENT, { timestamp: start, event: 'timer', eventType: 'start' });
  for (let i = 0; i < 20; i++) enc.onMesg(Profile.MesgNum.RECORD, { timestamp: at(i * 5), power: 100 });
  enc.onMesg(Profile.MesgNum.EVENT, { timestamp: at(100), event: 'timer', eventType: 'stopAll' });
  enc.onMesg(Profile.MesgNum.LAP, { messageIndex: 0, timestamp: at(100), startTime: start, totalElapsedTime: 100, totalTimerTime: 100 });
  enc.onMesg(Profile.MesgNum.SESSION, { messageIndex: 0, timestamp: at(100), startTime: start, sport: 'cycling', subSport: 'virtualActivity', totalElapsedTime: 100, totalTimerTime: 100, numLaps: 1 });
  enc.onMesg(Profile.MesgNum.ACTIVITY, { timestamp: at(100), numSessions: 1, totalTimerTime: 100 });
  fs.writeFileSync(f, Buffer.from(enc.close()));
  const r = run([f]);
  assert.equal(r.code, 1);
  assert.match(r.out, /not one per second/);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('usage errors exit 2; missing paths and empty directories exit 1', () => {
  assert.equal(run([]).code, 2);
  assert.equal(run([FIXTURE, '--expect-laps=x']).code, 2);
  assert.equal(run([FIXTURE, '--bogus']).code, 2);
  const missing = run([path.join(os.tmpdir(), 'no-such-dir-fit-check')]);
  assert.equal(missing.code, 1);
  assert.match(missing.out, /no such file or directory/);
  const dir = tmpdir();
  const empty = run([dir]);
  assert.equal(empty.code, 1);
  assert.match(empty.err, /no \.fit files/);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('without the SDK it falls back to the GDScript decoder contract', () => {
  const env = {
    WATTLANDS_FIT_CHECK_SDK: '@garmin/no-such-fitsdk',
    WATTLANDS_FIT_DECODE_CMD: JSON.stringify([process.execPath, path.join(here, '..', 'testdata', 'fake_decode.mjs')]),
  };
  const r = run([FIXTURE, '--expect-laps=5', '--json'], env);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.err, /using the GDScript decoder/);
  const j = JSON.parse(r.out);
  assert.equal(j.decoder, 'gdscript');
  assert.equal(j.files[0].records, 601);
  assert.equal(j.files[0].summary_checked, true);
  assert.equal(j.files[0].session.sport, 'cycling');
  const wrong = run([FIXTURE, '--expect-laps=3'], env);
  assert.equal(wrong.code, 1);
  const broken = run([FIXTURE], { ...env, FAKE_DECODE_FAIL: '1' });
  assert.equal(broken.code, 1);
  assert.match(broken.out, /GDScript decoder produced no result/);
});
