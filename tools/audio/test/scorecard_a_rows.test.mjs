// SPEC_AUDIO 6.2: the scorecard's A rows and waivers on the fixture (split from scorecard_gate.test.mjs so node
// --test runs them in parallel).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { card, fixture, row } from './scorecard_kit.mjs';

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
