// Cost estimates from prices.json (BRIEF 3.10).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DEFAULT_ENDPOINT, DRAFT_ENDPOINT } from '../lib/config.mjs';
import { ceilTicks, estimateUsd, formatUsd, ticksToUsd, usdToTicks } from '../lib/prices.mjs';

test('sunburst at high quality: $0.07 an image up to 1536 x 864', () => {
  assert.equal(estimateUsd(DEFAULT_ENDPOINT, 1536, 864, 'high'), 0.07);
  assert.equal(estimateUsd(DEFAULT_ENDPOINT, 1024, 640, 'high'), 0.07);
  assert.equal(estimateUsd(DEFAULT_ENDPOINT, 1776, 592, 'high'), 0.07);
});

test('sunburst scales by pixel count above 1536 x 864 and rounds up to $0.0001', () => {
  assert.equal(estimateUsd(DEFAULT_ENDPOINT, 3072, 1728, 'high'), 0.28);
  const odd = estimateUsd(DEFAULT_ENDPOINT, 2048, 1024, 'high');
  assert.ok(odd >= (0.07 * (2048 * 1024)) / (1536 * 864));
  assert.ok(odd - (0.07 * (2048 * 1024)) / (1536 * 864) < 0.0001);
});

test('sunburst qualities: never below high; auto priced as max', () => {
  assert.ok(estimateUsd(DEFAULT_ENDPOINT, 1024, 1024, 'low') >= 0.07);
  assert.ok(estimateUsd(DEFAULT_ENDPOINT, 1024, 1024, 'xhigh') > 0.07);
  assert.equal(estimateUsd(DEFAULT_ENDPOINT, 1024, 1024, 'auto'), estimateUsd(DEFAULT_ENDPOINT, 1024, 1024, 'max'));
});

test("flare uses its listed table: the dearest row up to the smallest that holds the size, plus prompt text", () => {
  // 1024x640 fits in 1024x768: $0.03612 + $0.002.
  assert.equal(estimateUsd(DRAFT_ENDPOINT, 1024, 640, 'high'), 0.0382);
  // 1776x592 (1.05 MP) needs the 1024x1536 row; the 1024x1024 row before it is dearer ($0.05268).
  assert.equal(estimateUsd(DRAFT_ENDPOINT, 1776, 592, 'high'), 0.0547);
  // Flare is cheaper than sunburst at the sizes generate.mjs requests.
  assert.ok(estimateUsd(DRAFT_ENDPOINT, 1600, 640, 'high') < estimateUsd(DEFAULT_ENDPOINT, 1600, 640, 'high'));
  // Beyond the largest row it scales by pixel count.
  assert.ok(estimateUsd(DRAFT_ENDPOINT, 3840, 2160, 'high') <= estimateUsd(DRAFT_ENDPOINT, 3840, 3840, 'high'));
});

test('an endpoint without prices uses the sunburst figure', () => {
  assert.equal(estimateUsd('someone/else/text-to-image', 1536, 864, 'high'), 0.07);
});

test('money helpers', () => {
  assert.equal(usdToTicks(0.07), 700);
  assert.equal(ticksToUsd(700), 0.07);
  assert.equal(ceilTicks(0.07), 700);
  assert.equal(ceilTicks(0.07001), 701);
  assert.equal(formatUsd(0.07), '$0.0700');
});
