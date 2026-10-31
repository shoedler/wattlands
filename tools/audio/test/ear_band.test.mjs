import assert from 'node:assert/strict';
import { test } from 'node:test';
import { earBand } from '../lib/ear_band.mjs';
import { MIX_RATE } from '../lib/offline_mix.mjs';

function tone(hz, seconds = 1) {
  const x = new Float64Array(Math.round(seconds * MIX_RATE));
  for (let i = 0; i < x.length; i++) x[i] = 0.5 * Math.sin((2 * Math.PI * hz * i) / MIX_RATE);
  return x;
}

test('a tone in the band is all of it; a tone under it hardly any', () => {
  assert.ok(earBand(tone(3000)).share > -0.1);
  assert.ok(earBand(tone(200)).share < -40);
});

test('level is under full scale, and a band can be asked for', () => {
  assert.ok(Math.abs(earBand(tone(3000)).level - -9) < 0.5);
  assert.ok(earBand(tone(3000), [100, 500]).share < -40);
});
