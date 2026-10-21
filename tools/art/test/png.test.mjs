// The zero-dependency PNG reader and writer.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import zlib from 'node:zlib';
import { crc32, decodePng, encodePng, isPng, PNG_SIGNATURE, pngSize } from '../lib/png.mjs';

function rgba(w, h, f) {
  const px = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) px.set(f(x, y), (y * w + x) * 4);
  return px;
}

test('encode then decode round-trips RGBA8', () => {
  const px = rgba(7, 5, (x, y) => [x * 30, y * 50, (x * y) % 256, (x + y) % 2 ? 255 : 0]);
  const png = encodePng(7, 5, px);
  assert.ok(isPng(png));
  assert.deepEqual(pngSize(png), { width: 7, height: 5 });
  const d = decodePng(png);
  assert.equal(d.width, 7);
  assert.equal(d.height, 5);
  assert.deepEqual(Buffer.from(d.data), Buffer.from(px));
});

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const c = Buffer.alloc(4);
  c.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, c]);
}

function rawPng(w, h, colorType, rows, extra = []) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = colorType;
  return Buffer.concat([PNG_SIGNATURE, chunk('IHDR', ihdr), ...extra, chunk('IDAT', zlib.deflateSync(Buffer.concat(rows))), chunk('IEND', Buffer.alloc(0))]);
}

test('decodes every filter type (RGB rows with sub, up, average and paeth)', () => {
  // 2x5 RGB image; each row uses a different filter. Expected pixels are all (10, 20, 30) and (40, 50, 60).
  const want = [10, 20, 30, 40, 50, 60];
  const rows = [];
  rows.push(Buffer.from([0, ...want])); // none
  rows.push(Buffer.from([1, 10, 20, 30, 30, 30, 30])); // sub: second pixel = prev + 30
  rows.push(Buffer.from([2, 0, 0, 0, 0, 0, 0])); // up: same as the row above
  // average: first pixel = v + floor(up / 2), second = v + floor((left + up) / 2)
  rows.push(Buffer.from([3, 5, 10, 15, 15, 15, 15]));
  // paeth: first pixel predictor = up; second predictor = paeth(left, up, upleft) = up (40,50,60)
  rows.push(Buffer.from([4, 0, 0, 0, 0, 0, 0]));
  const d = decodePng(rawPng(2, 5, 2, rows));
  for (let y = 0; y < 5; y++) {
    assert.deepEqual([...d.data.slice(y * 8, y * 8 + 3)], [10, 20, 30], `row ${y}`);
    assert.deepEqual([...d.data.slice(y * 8 + 4, y * 8 + 7)], [40, 50, 60], `row ${y}`);
    assert.equal(d.data[y * 8 + 3], 255);
  }
});

test('decodes gray, gray+alpha and palette images', () => {
  let d = decodePng(rawPng(2, 1, 0, [Buffer.from([0, 7, 200])]));
  assert.deepEqual([...d.data], [7, 7, 7, 255, 200, 200, 200, 255]);
  d = decodePng(rawPng(1, 1, 4, [Buffer.from([0, 9, 128])]));
  assert.deepEqual([...d.data], [9, 9, 9, 128]);
  const plte = chunk('PLTE', Buffer.from([1, 2, 3, 4, 5, 6]));
  const trns = chunk('tRNS', Buffer.from([0]));
  d = decodePng(rawPng(2, 1, 3, [Buffer.from([0, 0, 1])], [plte, trns]));
  assert.deepEqual([...d.data], [1, 2, 3, 0, 4, 5, 6, 255]);
});

test('rejects non-PNG data and bad CRCs', () => {
  assert.equal(isPng(Buffer.from('GIF89a................')), false);
  assert.throws(() => decodePng(Buffer.from('hello')), /not a PNG/);
  const png = encodePng(1, 1, new Uint8Array([1, 2, 3, 4]));
  png[png.length - 20] ^= 0xff;
  assert.throws(() => decodePng(png));
  assert.equal(pngSize(Buffer.from('nope')), null);
});
