#!/usr/bin/env node
// Cuts the picker cards from the frames tools/picker_cards/render.sh wrote. No dependencies beyond the repo's PNG code.
//
//   bash tools/picker_cards/render.sh
//   node tools/picker_cards/compose.mjs
//   tools/godot.sh --headless --path . --import
//
// A card is a 16:9 cut of a 1920 x 1080 frame, reduced by a whole factor. AppGameCard draws it with a nearest filter,
// covering a slot 225 high and as wide as the grid's column (441 and 534 today), so in the widest slot only the middle
// 75 % of the card's height shows: each subject sits inside that band. No text on a card: titles change.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { crc32, decodePng } from '../art/lib/png.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const FRAMES = path.join(ROOT, 'build/picker_cards/frames');

/**
 * crop [x, y, w, h] in frame pixels; reduce the whole factor; filter "nearest" (one sample per art pixel, for a frame
 * whose art pixels are exactly `reduce` wide) or "box" (the mean of the block, for art pixels that do not divide);
 * scale a whole-number enlargement; shadows [black, gamma] lifts the dark values, night art only.
 */
export const CARDS = {
  siege: {
    out: 'assets/siege/cards/picker_card.png',
    crop: [280, 115, 1440, 810],
    reduce: 3,
    filter: 'box',
  },
  tank: {
    out: 'assets/tank/cards/picker_card.png',
    crop: [30, 330, 960, 540],
    reduce: 2,
    filter: 'nearest',
    shadows: [10, 0.68],
  },
  fishing: {
    out: 'assets/fishing/cards/picker_card.png',
    crop: [570, 225, 720, 405],
    reduce: 3,
    filter: 'nearest',
    scale: 2,
  },
};

/** The card's RGB image: { w, h, px } with four bytes a pixel. Throws on a cut that is not 16:9 or not whole. */
export function cutCard(frame, spec) {
  const [cx, cy, cw, ch] = spec.crop;
  const f = spec.reduce;
  const up = spec.scale ?? 1;
  if (cw * 9 !== ch * 16) throw new Error(`crop ${cw} x ${ch} is not 16:9`);
  if (cw % f !== 0 || ch % f !== 0) throw new Error(`crop ${cw} x ${ch} does not divide by ${f}`);
  if (cx < 0 || cy < 0 || cx + cw > frame.width || cy + ch > frame.height) throw new Error('crop leaves the frame');
  const w = cw / f;
  const h = ch / f;
  const px = new Uint8Array(w * up * h * up * 4);
  const lut = spec.shadows ? shadowLut(spec.shadows) : null;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const rgb = sample(frame, cx + x * f, cy + y * f, f, spec.filter);
      for (let b = 0; b < up; b++) {
        for (let a = 0; a < up; a++) {
          const d = ((y * up + b) * w * up + x * up + a) * 4;
          for (let c = 0; c < 3; c++) px[d + c] = lut ? lut[rgb[c]] : rgb[c];
          px[d + 3] = 255;
        }
      }
    }
  }
  return { w: w * up, h: h * up, px };
}

function sample(frame, x0, y0, f, filter) {
  if (filter === 'nearest') {
    const s = (y0 * frame.width + x0) * 4;
    return [frame.data[s], frame.data[s + 1], frame.data[s + 2]];
  }
  if (filter !== 'box') throw new Error(`unknown filter ${filter}`);
  const sum = [0, 0, 0];
  for (let y = y0; y < y0 + f; y++) {
    for (let x = x0; x < x0 + f; x++) {
      const s = (y * frame.width + x) * 4;
      for (let c = 0; c < 3; c++) sum[c] += frame.data[s + c];
    }
  }
  return sum.map((v) => Math.round(v / (f * f)));
}

/** Values at or below `black` stay black, so a night sky keeps its depth; the rest rise along the gamma curve. */
function shadowLut([black, gamma]) {
  const lut = new Uint8Array(256);
  for (let v = 0; v < 256; v++) {
    lut[v] = Math.round(255 * Math.max((v - black) / (255 - black), 0) ** gamma);
  }
  return lut;
}

/** Median cut to at most 256 colours, no dither: flat areas stay flat and the file stays small. */
export function quantize(img) {
  const hist = new Map();
  for (let i = 0; i < img.px.length; i += 4) {
    const k = (img.px[i] << 16) | (img.px[i + 1] << 8) | img.px[i + 2];
    hist.set(k, (hist.get(k) ?? 0) + 1);
  }
  const colors = [...hist.entries()].map(([k, n]) => [(k >> 16) & 255, (k >> 8) & 255, k & 255, n]);
  const boxes = [colors];
  const weight = (box) => box.reduce((a, p) => a + p[3], 0);
  while (boxes.length < 256) {
    let best = -1;
    let bestScore = 0;
    let bestChan = 0;
    boxes.forEach((box, i) => {
      if (box.length < 2) return;
      const n = Math.sqrt(weight(box));
      for (let c = 0; c < 3; c++) {
        let lo = 255;
        let hi = 0;
        for (const p of box) {
          lo = Math.min(lo, p[c]);
          hi = Math.max(hi, p[c]);
        }
        if ((hi - lo) * n > bestScore) {
          best = i;
          bestScore = (hi - lo) * n;
          bestChan = c;
        }
      }
    });
    if (best < 0) break;
    const box = boxes[best].sort((a, b) => a[bestChan] - b[bestChan]);
    const half = weight(box) / 2;
    let run = 0;
    let cut = 1;
    for (let i = 0; i < box.length - 1; i++) {
      run += box[i][3];
      if (run >= half) {
        cut = i + 1;
        break;
      }
    }
    boxes.splice(best, 1, box.slice(0, cut), box.slice(cut));
  }
  const palette = boxes.map((box) => {
    const n = weight(box);
    return [0, 1, 2].map((c) => Math.round(box.reduce((a, p) => a + p[c] * p[3], 0) / n));
  });
  const lut = new Map();
  boxes.forEach((box, i) => {
    for (const p of box) lut.set((p[0] << 16) | (p[1] << 8) | p[2], i);
  });
  const index = new Uint8Array(img.w * img.h);
  for (let i = 0; i < index.length; i++) {
    const d = i * 4;
    index[i] = lut.get((img.px[d] << 16) | (img.px[d + 1] << 8) | img.px[d + 2]);
  }
  return { palette, index };
}

/** An 8-bit indexed PNG. */
export function encodeIndexed(w, h, { palette, index }) {
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 3;
  const raw = Buffer.alloc((w + 1) * h);
  for (let y = 0; y < h; y++) {
    Buffer.from(index.buffer, index.byteOffset + y * w, w).copy(raw, y * (w + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('PLTE', Buffer.from(palette.flat())),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function main() {
  for (const [id, spec] of Object.entries(CARDS)) {
    const dir = path.join(FRAMES, id);
    const names = fs.existsSync(dir) ? fs.readdirSync(dir).filter((n) => n.endsWith('.png')) : [];
    if (names.length !== 1) throw new Error(`${id}: expected one frame in ${dir}: run render.sh first`);
    const card = cutCard(decodePng(fs.readFileSync(path.join(dir, names[0]))), spec);
    const png = encodeIndexed(card.w, card.h, quantize(card));
    const out = path.join(ROOT, spec.out);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, png);
    console.log(`${spec.out}: ${card.w} x ${card.h}, ${Math.round(png.length / 1024)} KB`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
