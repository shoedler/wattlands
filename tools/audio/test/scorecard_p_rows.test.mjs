// SPEC_AUDIO 6.2: the scorecard's P1-P5 rows on the fixture (split from scorecard_gate.test.mjs so node
// --test runs them in parallel).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { card, fixture, row } from './scorecard_kit.mjs';

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
