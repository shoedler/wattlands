// Request sizing for many sizes and aspects (BRIEF 3.10, docs/OWNERSHIP.md ART8).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DEFAULT_ENDPOINT, DRAFT_ENDPOINT, endpointLimits, loadEndpoints } from '../lib/config.mjs';
import { isValidRequestSize, planRequestSize } from '../lib/sizing.mjs';
import { FAL_LIMITS } from '../mock_fal/server.mjs';

const limits = endpointLimits(DEFAULT_ENDPOINT);

// Every sprite size the Tank and Fishing briefs name, plus odd ones.
const BRIEF_SIZES = [
  [192, 72], [240, 76], [288, 80], [88, 36], [104, 40], [120, 44], [44, 22], [128, 48], [96, 48], [80, 48],
  [88, 48], [56, 32], [36, 36], [20, 20], [24, 24], [16, 16], [32, 28], [40, 28], [40, 32], [20, 16],
  [16, 20], [32, 40], [18, 18], [22, 22], [80, 40], [104, 52], [112, 44], [72, 36], [320, 100], [152, 56],
  [64, 32], [64, 24], [64, 20], [72, 32], [48, 16], [40, 16], [160, 120], [640, 200], [960, 120], [960, 140],
  [960, 80], [960, 48], [320, 180], [32, 20], [64, 64], [32, 24], [240, 80], [144, 48],
  [80, 32], [24, 16], [14, 12], [10, 10], [24, 8], [40, 16], [44, 16], [64, 22], [10, 8], [32, 12], [8, 5],
  [48, 4], [20, 12], [32, 24], [24, 24], [16, 16], [320, 24], [256, 12], [80, 24], [12, 12], [32, 6],
  [64, 6], [128, 64], [416, 28], [416, 18], [64, 8], [160, 90], [40, 18], [64, 20], [96, 30],
];

test('endpoints.json: both GPT Image 2.5 endpoints with fal limits (16 px multiples, 655,360 px, 3840 px, 3:1)', () => {
  for (const ep of [DEFAULT_ENDPOINT, DRAFT_ENDPOINT]) {
    const l = endpointLimits(ep);
    assert.ok(l, ep);
    assert.equal(l.multiple, 16);
    assert.equal(l.min_pixels, 655360);
    assert.equal(l.max_edge, 3840);
    assert.equal(l.max_aspect, 3);
    assert.ok(l.params.quality.includes('high'));
    assert.ok(l.params.background.includes('transparent') && l.params.background.includes('opaque'));
  }
  assert.equal(endpointLimits('nope/nope'), null);
  assert.equal(loadEndpoints().defaults.max_aspect, 3);
});

test('every planned size is valid for fal (independent check) and keeps the base price', () => {
  for (const size of BRIEF_SIZES) {
    const r = planRequestSize(size, limits);
    assert.ok(isValidRequestSize(r.width, r.height, limits), `${size}: ${r.width}x${r.height}`);
    assert.ok(isValidRequestSize(r.width, r.height, FAL_LIMITS), `${size} vs the mock's limits`);
    assert.ok(r.pixels <= limits.max_request_pixels, `${size}: ${r.pixels} px`);
    assert.equal(r.width % 16, 0);
    assert.equal(r.height % 16, 0);
  }
});

test('sprites within 3:1 keep their aspect within 1 % (Tank checks 2 %, Fishing 5 %)', () => {
  for (const size of BRIEF_SIZES) {
    const a = size[0] / size[1];
    if (a > 3 || a < 1 / 3) continue;
    const r = planRequestSize(size, limits);
    assert.equal(r.outside_limits, false, String(size));
    assert.ok(Math.abs(r.aspect_error_pct) < 1, `${size}: ${r.aspect_error_pct.toFixed(3)} %`);
  }
});

test('a sweep of aspects from 1:3 to 3:1 stays within 1 %', () => {
  for (let w = 1; w <= 60; w++) {
    for (let h = 1; h <= 60; h++) {
      const a = w / h;
      if (a > 3 || a < 1 / 3) continue;
      const r = planRequestSize([w, h], limits);
      assert.ok(isValidRequestSize(r.width, r.height, limits));
      assert.ok(Math.abs(r.aspect_error_pct) < 1, `${w}x${h}: ${r.aspect_error_pct}`);
    }
  }
});

test('exact aspects come out exact', () => {
  for (const [size, aspect] of [
    [[16, 16], 1],
    [[96, 48], 2],
    [[240, 80], 3],
    [[80, 240], 1 / 3],
    [[160, 90], 16 / 9],
    [[64, 22], 64 / 22],
  ]) {
    const r = planRequestSize(size, limits);
    assert.ok(Math.abs(r.width / r.height - aspect) < 1e-9, `${size}: ${r.width}x${r.height}`);
    assert.equal(r.aspect_error_pct === 0 || Math.abs(r.aspect_error_pct) < 1e-9, true);
  }
});

test('strips beyond 3:1 are requested at 3:1 and flagged outside the limits', () => {
  for (const size of [[960, 80], [416, 18], [48, 4], [960, 48], [320, 24], [256, 12], [640, 200]]) {
    const r = planRequestSize(size, limits);
    assert.equal(r.outside_limits, true, String(size));
    assert.ok(Math.abs(r.request_aspect - 3) < 0.005, `${size}: ${r.request_aspect}`);
    assert.ok(r.aspect_error_pct < 0);
  }
  // Tall sprites clamp to 1:3.
  const tall = planRequestSize([10, 100], limits);
  assert.equal(tall.outside_limits, true);
  assert.ok(Math.abs(tall.request_aspect - 1 / 3) < 0.005);
});

test('the reported aspect error is (request aspect / sprite aspect - 1) * 100', () => {
  const r = planRequestSize([640, 200], limits);
  assert.ok(Math.abs(r.aspect_error_pct - ((r.width / r.height) / 3.2 - 1) * 100) < 1e-9);
  assert.ok(Math.abs(r.aspect_error_pct - -6.25) < 0.1);
});

test('without max_request_pixels room it falls back to larger valid sizes', () => {
  const tight = { ...limits, max_request_pixels: 1000 };
  const r = planRequestSize([2, 1], tight);
  assert.ok(isValidRequestSize(r.width, r.height, limits));
  assert.ok(Math.abs(r.width / r.height - 2) < 1e-9);
});

test('custom limits: a 2:1 endpoint and a 32 px multiple', () => {
  const custom = { ...limits, multiple: 32, max_aspect: 2 };
  const r = planRequestSize([300, 100], custom);
  assert.equal(r.width % 32, 0);
  assert.equal(r.height % 32, 0);
  assert.ok(r.width / r.height <= 2);
  assert.equal(r.outside_limits, true);
});

test('sizing is deterministic', () => {
  for (const size of BRIEF_SIZES) assert.deepEqual(planRequestSize(size, limits), planRequestSize(size, limits));
});

test('invalid sprite sizes throw', () => {
  assert.throws(() => planRequestSize([0, 10], limits));
  assert.throws(() => planRequestSize([10, -1], limits));
});
