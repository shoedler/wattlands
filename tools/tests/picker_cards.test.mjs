// tools/picker_cards/compose.mjs: the cut stays 16:9 and whole, and the filters do what the cards rely on.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { cutCard, encodeIndexed, quantize, CARDS } from '../picker_cards/compose.mjs';
import { decodePng } from '../art/lib/png.mjs';

/** A 32 x 18 frame whose red channel is x * 4 and green y * 4. */
function frame() {
  const data = new Uint8Array(32 * 18 * 4);
  for (let y = 0; y < 18; y++) {
    for (let x = 0; x < 32; x++) {
      data.set([x * 4, y * 4, 0, 255], (y * 32 + x) * 4);
    }
  }
  return { width: 32, height: 18, data };
}

test('every card is a whole, 16:9 cut of a 1920 x 1080 frame', () => {
  const big = { width: 1920, height: 1080, data: new Uint8Array(1920 * 1080 * 4) };
  for (const [id, spec] of Object.entries(CARDS)) {
    const card = cutCard(big, spec);
    assert.equal(card.w * 9, card.h * 16, id);
    assert.ok(card.px.every((v, i) => i % 4 !== 3 || v === 255), `${id} is opaque`);
  }
});

test('a cut that is not 16:9, not whole or off the frame is refused', () => {
  const base = { reduce: 2, filter: 'nearest' };
  assert.throws(() => cutCard(frame(), { ...base, crop: [0, 0, 16, 16] }), /16:9/);
  assert.throws(() => cutCard(frame(), { ...base, reduce: 3, crop: [0, 0, 16, 9] }), /divide/);
  assert.throws(() => cutCard(frame(), { ...base, reduce: 1, crop: [20, 0, 16, 9] }), /leaves/);
});

test('nearest takes one sample, box the mean, scale repeats whole pixels', () => {
  const near = cutCard(frame(), { crop: [2, 2, 16, 9], reduce: 1, filter: 'nearest' });
  assert.deepEqual([...near.px.slice(0, 3)], [8, 8, 0]);
  const box = cutCard(frame(), { crop: [2, 2, 16, 9], reduce: 1, filter: 'box' });
  assert.deepEqual([...box.px.slice(0, 3)], [8, 8, 0], 'a block of one is its own mean');
  const two = { crop: [0, 0, 32, 18], reduce: 2 };
  assert.deepEqual([...cutCard(frame(), { ...two, filter: 'nearest' }).px.slice(0, 3)], [0, 0, 0]);
  assert.deepEqual([...cutCard(frame(), { ...two, filter: 'box' }).px.slice(0, 3)], [2, 2, 0]);
  const up = cutCard(frame(), { crop: [2, 2, 16, 9], reduce: 1, filter: 'nearest', scale: 2 });
  assert.equal(up.w, 32);
  assert.equal(up.h, 18);
  assert.deepEqual([...up.px.slice(0, 3)], [...up.px.slice(4, 7)]);
  assert.notDeepEqual([...up.px.slice(0, 3)], [...up.px.slice(8, 11)]);
});

test('the shadow lift keeps black black and raises the middle', () => {
  const data = new Uint8Array([5, 80, 255, 255]);
  const img = { width: 16, height: 9, data: new Uint8Array(16 * 9 * 4) };
  for (let i = 0; i < img.data.length; i += 4) img.data.set(data, i);
  const card = cutCard(img, { crop: [0, 0, 16, 9], reduce: 1, filter: 'nearest', shadows: [10, 0.68] });
  assert.equal(card.px[0], 0);
  assert.ok(card.px[1] > 80);
  assert.equal(card.px[2], 255);
});

test('the indexed PNG decodes to the palette it was given', () => {
  const card = cutCard(frame(), { crop: [0, 0, 16, 9], reduce: 1, filter: 'nearest' });
  const png = decodePng(encodeIndexed(card.w, card.h, quantize(card)));
  assert.equal(png.width, 16);
  assert.equal(png.height, 9);
  assert.deepEqual([...png.data.slice(4, 8)], [4, 0, 0, 255]);
});
