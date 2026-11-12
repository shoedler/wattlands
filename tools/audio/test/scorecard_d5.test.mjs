// SPEC_AUDIO 6.2: the scorecard's D5 rows on the fixture (split from scorecard_gate.test.mjs so node
// --test runs them in parallel).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BankAudio } from '../lib/offline_mix.mjs';
import { scoreBank } from '../lib/score.mjs';
import { SHARED_BANK, readJson } from './helpers.mjs';
import { card, fixture, row, shared } from './scorecard_kit.mjs';

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

test('D5 hears what HudLayer plays over the moment: preview.hud, and prompts just ahead of it', () => {
  const doc = structuredClone(fixture);
  const quiet = row(card(doc), 'D5');
  doc.preview.hud = [{ t: 10, sound: 'phase' }, { t: 10, sound: 'toast' }, { t: 10, sound: 'lap' }, { t: 10, sound: 'results' }, { t: 10, sound: 'ui_confirm' }];
  const r = row(card(doc), 'D5');
  assert.ok(r.value < quiet.value, `${r.value} against ${quiet.value}`);
  assert.match(r.note, /at (9\.6|9\.8|10) s/);
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
