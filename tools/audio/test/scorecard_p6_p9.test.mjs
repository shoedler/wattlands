// SPEC_AUDIO 6.2: the scorecard's P6, P8 and P9 rows on the fixture (split from scorecard_gate.test.mjs so node
// --test runs them in parallel).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { card, fixture, row } from './scorecard_kit.mjs';

test('P6 holds the 2-8 kHz of the master where a bank asks', () => {
  const doc = structuredClone(fixture);
  doc.preview.checks = { ...doc.preview.checks, projectiles: { shots: [], surfaces: {} }, ear_band: { limit: -60 } };
  assert.equal(row(card(doc), 'P6').pass, false);
  doc.preview.checks.ear_band.limit = 0;
  assert.equal(row(card(doc), 'P6').pass, true);
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
