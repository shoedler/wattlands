// node --test tests/games/fishing/art/style_check.test.mjs: the style checker on small synthetic
// screenshots (encoded here at 3 screen px per art px), so its numbers mean what they say.
import test from 'node:test';
import assert from 'node:assert/strict';
import zlib from 'node:zlib';

import * as sc from './style_check.mjs';

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, body) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(body.length);
  const tb = Buffer.concat([Buffer.from(type, 'latin1'), body]);
  const c = Buffer.alloc(4);
  c.writeUInt32BE(crc(tb));
  return Buffer.concat([len, tb, c]);
}

/** A PNG (RGB, filter 0) of art grid `rows` ("rrggbb" per cell), each cell 3x3 screen px. */
function png(rows) {
  const w = rows[0].length * 3;
  const h = rows.length * 3;
  const raw = Buffer.alloc(h * (w * 3 + 1));
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const c = rows[Math.floor(y / 3)][Math.floor(x / 3)];
      const i = y * (w * 3 + 1) + 1 + x * 3;
      raw[i] = parseInt(c.slice(0, 2), 16);
      raw[i + 1] = parseInt(c.slice(2, 4), 16);
      raw[i + 2] = parseInt(c.slice(4, 6), 16);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const SKY = 'cedfd2';
const SEA = '91c2c2';
const field = (w, h, c) => Array.from({ length: h }, () => Array(w).fill(c));
const grid = (rows) => sc.artGrid(sc.decodePng(png(rows)), 3, [], []);

test('a flat two-band field is all flat, in family and passes', () => {
  const rows = [...field(20, 10, SKY), ...field(20, 10, SEA)];
  const m = sc.measure(grid(rows));
  assert.equal(m.world, 400);
  assert.equal(m.colours, 2);
  assert.equal(m.checker, 0);
  assert.equal(m.isolated, 0);
  assert.equal(m.offFamilyPct, 0);
  assert.equal(m.minValuePct, 76);
  assert.ok(m.flatPct > 80);
  assert.equal(m.lightPct, 100);
  assert.equal(m.whitePct, 50, 'the sky half is white, the surface teal half is not');
  assert.deepEqual(sc.verdict(m), []);
});

test('a checker row, specks, near-black and a warm hue are each counted', () => {
  const rows = field(20, 20, SKY);
  for (let x = 0; x < 20; x++) rows[5][x] = x % 2 ? SKY : SEA;
  for (let x = 0; x < 20; x++) rows[6][x] = x % 2 ? SEA : SKY;
  rows[12][4] = 'ebf2e7';
  rows[12][9] = 'ebf2e7';
  rows[15][15] = '121f29';
  rows[17][3] = 'd55e00';
  const m = sc.measure(grid(rows));
  assert.ok(m.checker >= 18, `checker ${m.checker}`);
  assert.ok(m.isolated >= 2);
  assert.equal(m.offPalette, 2, 'the near-black and the orange are not palette colours');
  assert.ok(m.minValuePct < 35);
  assert.ok(m.offFamilyPct > 0);
  const fails = sc.verdict(m).join(' ');
  assert.match(fails, /checker/);
});

test('the accent counts apart, and the HUD rects and mixed blocks are masked', () => {
  const rows = field(30, 20, SKY);
  for (let x = 0; x < 6; x++) rows[10][x] = sc.ACCENT;
  const g = sc.artGrid(sc.decodePng(png(rows)), 3, [[20, 0, 10, 20]], []);
  const m = sc.measure(g);
  assert.equal(g.masked, 200);
  assert.equal(m.world, 400);
  assert.equal(m.accentPct, 1.5);
  assert.equal(m.offFamilyPct, 0);
  assert.match(sc.verdict(m).join(' '), /accent/);
});

test('a popup rect is masked only when something foreign shows in it', () => {
  const rows = field(20, 10, SKY);
  const clean = sc.artGrid(sc.decodePng(png(rows)), 3, [], [[0, 0, 5, 5]]);
  assert.equal(clean.masked, 0);
  rows[2][2] = 'd55e00';
  const shown = sc.artGrid(sc.decodePng(png(rows)), 3, [], [[0, 0, 5, 5]]);
  assert.equal(shown.offPalette, 0);
  assert.equal(shown.cells.filter((c) => c === null).length, 25);
});

test('a deep-teal box off the edges is a HUD panel (text and all); a deep band is world', () => {
  const D = sc.PANEL_COLOUR;
  const rows = field(30, 30, SKY);
  for (let y = 2; y < 12; y++) for (let x = 2; x < 14; x++) rows[y][x] = D;
  rows[6][5] = 'ebf2e7';
  rows[16][3] = D;
  rows[16][4] = D;
  for (let y = 24; y < 30; y++) for (let x = 0; x < 30; x++) rows[y][x] = D;
  const g = sc.artGrid(sc.decodePng(png(rows)), 3, [], []);
  assert.equal(g.masked, 120, 'the box with its text');
  assert.equal(g.cells.filter((c) => c === D).length, 2 + 180, 'small marks and the band stay');
});

test('chrome off the art grid is counted; a non-palette block (a safety banner) is not', () => {
  const rows = field(10, 10, SKY);
  const img = sc.decodePng(png(rows));
  assert.equal(sc.frameGrid(img, 3, []).offGrid, 0);
  const at = (x, y) => (y * img.width + x) * 4;
  img.data[at(4, 4)] = 0x91;
  img.data[at(4, 4) + 1] = 0xc2;
  img.data[at(4, 4) + 2] = 0xc2;
  img.data[at(10, 10)] = 0xd5;
  img.data[at(10, 10) + 1] = 0x5e;
  img.data[at(10, 10) + 2] = 0x00;
  const m = sc.frameGrid(img, 3, []);
  assert.equal(m.offGrid, 1);
  assert.match(sc.verdict({ ...sc.measure(sc.artGrid(img, 3, [], [])), ...m }).join(' '), /off-grid/);
});

test('hsv reads the palette', () => {
  const abyss = sc.hsv('1c4d65');
  assert.ok(abyss.h > 190 && abyss.h < 210);
  assert.equal(Math.round(abyss.v * 100), 40);
});
