// What tools/audio/live_report.mjs reads off a recording, on signals small enough to reason about.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { headEpisodes, panGains } from '../live_report.mjs';

test('a pan send gives a mono voice what AudioEffectPanner gives it', () => {
  assert.deepEqual(panGains('Sfx'), [1, 1]);
  assert.deepEqual(panGains('Sfx-0.50'), [1.5, 0.5]);
  assert.deepEqual(panGains('Sfx+0.25'), [0.75, 1.25]);
  const [l, r] = panGains('Sfx-0.75');
  assert.equal(l + r, 2, 'the mid stays the voice');
});

test('a moment over on both channels is one over, and a later one another', () => {
  const rate = 1000;
  const a = new Float64Array(1000);
  const b = new Float64Array(1000);
  a[100] = 1;
  b[100] = 1;
  b[101] = 1;
  assert.equal(headEpisodes([a, b], rate), 1);
  a[500] = 1;
  assert.equal(headEpisodes([a, b], rate), 2);
});
