// SPEC_AUDIO 6.2: the scorecard's D4 and D6 rows on the fixture (split from scorecard_gate.test.mjs so node
// --test runs them in parallel).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { card, fixture, row } from './scorecard_kit.mjs';

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
