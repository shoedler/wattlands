#!/usr/bin/env node
// Turbo Reel's art style check on 1920x1080 screenshots of the 640x360 view (3 screen px per
// art px): the rubric's numeric checks on the world layer with the HUD masked.
//
//   node tests/games/fishing/art/style_check.mjs <png>... [--json]
//
// The world is every art pixel whose 3x3 screen block is one colour, outside the HUD rects and
// not a HUD panel (the abyss at 85 % over a palette colour); HUD text and panels are counted as
// masked, and world colours outside the palette are counted as off-palette.
// Per screenshot: unique world colours, off-family share (non-accent pixels outside hue 140-215
// unless near-neutral, or above 75 % saturation), the lowest value, checker cells (3x2 windows alternating both ways; a 1:1 line is not one), isolated pixels (differing
// from all four neighbours), the accent and player-colour shares, and the flat share (pixels
// whose eight neighbours, where they are world, are the same colour). Zero dependencies (node:zlib).
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

export const PALETTE = {
  ebf2e7: 'foam', cedfd2: 'sky', b6d7cf: 'haze', '90c1c1': 'surface', '6fa3a6': 'upper',
  '4b858f': 'mid', '2c6778': 'deep', '1c4d65': 'abyss', a7bfb3: 'sage', '627179': 'wood',
  '4e5c67': 'slate', c98a5e: 'accent', '7f9cbf': 'player_slate', '9fb07a': 'player_moss',
  a68aa8: 'player_plum',
};
export const ACCENT = 'c98a5e';
export const PLAYERS = ['7f9cbf', '9fb07a', 'a68aa8'];
// HUD rects in art px (FishingHud and the kit widgets, with a margin): minimap, board, the
// bottom-left stack (power, cadence, meters, gear, timeline), the fight panel, the PANIC corner.
export const HUD_RECTS = [
  [2, 0, 418, 34],
  [422, 0, 218, 52],
  [0, 258, 220, 102],
  [218, 318, 210, 42],
  [500, 312, 140, 48],
];
export const SCALE = 3;
// Below this saturation a colour is a near-neutral (foam, sky) whose hue is not meaningful.
export const NEUTRAL_S = 0.1;

/** Decodes an 8-bit RGB or RGBA PNG: {width, height, data (RGBA bytes)}. */
export function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
  let off = 8;
  let width = 0;
  let height = 0;
  let ctype = 0;
  const idat = [];
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('latin1', off + 4, off + 8);
    const body = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      if (body[8] !== 8 || body[12] !== 0) throw new Error('only 8-bit non-interlaced PNGs');
      ctype = body[9];
      if (ctype !== 2 && ctype !== 6) throw new Error(`colour type ${ctype} not supported`);
    } else if (type === 'IDAT') {
      idat.push(body);
    } else if (type === 'IEND') {
      break;
    }
    off += 12 + len;
  }
  const bpp = ctype === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * bpp;
  const px = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) {
    const f = raw[y * (stride + 1)];
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? px[y * stride + i - bpp] : 0;
      const b = y > 0 ? px[(y - 1) * stride + i] : 0;
      const c = i >= bpp && y > 0 ? px[(y - 1) * stride + i - bpp] : 0;
      let v = src[i];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      px[y * stride + i] = v & 255;
    }
  }
  const data = Buffer.alloc(width * height * 4);
  for (let i = 0, j = 0; i < width * height; i++, j += bpp) {
    data[i * 4] = px[j];
    data[i * 4 + 1] = px[j + 1];
    data[i * 4 + 2] = px[j + 2];
    data[i * 4 + 3] = bpp === 4 ? px[j + 3] : 255;
  }
  return { width, height, data };
}

const hex = (r, g, b) => ((r << 16) | (g << 8) | b).toString(16).padStart(6, '0');

/** HSV of a "rrggbb" string: {h (deg), s, v} with s and v in 0..1. */
export function hsv(h6) {
  const r = parseInt(h6.slice(0, 2), 16) / 255;
  const g = parseInt(h6.slice(2, 4), 16) / 255;
  const b = parseInt(h6.slice(4, 6), 16) / 255;
  const mx = Math.max(r, g, b);
  const mn = Math.min(r, g, b);
  const d = mx - mn;
  let h = 0;
  if (d > 0) {
    if (mx === r) h = ((g - b) / d) % 6;
    else if (mx === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
  }
  return { h, s: mx > 0 ? d / mx : 0, v: mx };
}

const rgbOf = (h6) => [0, 2, 4].map((i) => parseInt(h6.slice(i, i + 2), 16));
// A HUD panel: the abyss at PANEL_ALPHA over a palette colour.
export const PANEL_ALPHA = 0.85;
const PANEL_BLENDS = Object.keys(PALETTE).map((p) => {
  const a = rgbOf('1c4d65');
  return rgbOf(p).map((v, i) => PANEL_ALPHA * a[i] + (1 - PANEL_ALPHA) * v);
});
export function isPanel(h6) {
  const c = rgbOf(h6);
  return PANEL_BLENDS.some((b) => b.every((v, i) => Math.abs(v - c[i]) <= 3));
}

/** The art-pixel grid of a screenshot: {w, h, cells: Array<string|null>} (null: masked). */
export function artGrid(img, scale = SCALE, hudRects = HUD_RECTS) {
  const w = Math.floor(img.width / scale);
  const h = Math.floor(img.height / scale);
  const cells = new Array(w * h).fill(null);
  let masked = 0;
  let offPalette = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (hudRects.some(([rx, ry, rw, rh]) => x >= rx && x < rx + rw && y >= ry && y < ry + rh)) {
        masked++;
        continue;
      }
      let first = null;
      let uniform = true;
      for (let dy = 0; dy < scale && uniform; dy++) {
        for (let dx = 0; dx < scale; dx++) {
          const i = ((y * scale + dy) * img.width + x * scale + dx) * 4;
          const c = hex(img.data[i], img.data[i + 1], img.data[i + 2]);
          if (first === null) first = c;
          else if (c !== first) {
            uniform = false;
            break;
          }
        }
      }
      if (!uniform) {
        masked++;
        continue;
      }
      if (!(first in PALETTE)) {
        if (isPanel(first)) {
          masked++;
          continue;
        }
        offPalette++;
      }
      cells[y * w + x] = first;
    }
  }
  return { w, h, cells, masked, offPalette };
}

/** The rubric's numbers for an art grid. */
export function measure(grid) {
  const { w, h, cells } = grid;
  const at = (x, y) => (x < 0 || y < 0 || x >= w || y >= h ? null : cells[y * w + x]);
  const counts = new Map();
  let world = 0;
  let offFamily = 0;
  let minV = 1;
  let accent = 0;
  let players = 0;
  let flat = 0;
  let isolated = 0;
  let checker = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const c = at(x, y);
      if (c === null) continue;
      world++;
      counts.set(c, (counts.get(c) || 0) + 1);
      const { h: hue, s, v } = hsv(c);
      minV = Math.min(minV, v);
      if (c === ACCENT) accent++;
      else if (PLAYERS.includes(c)) players++;
      else if ((s >= NEUTRAL_S && (hue < 140 || hue > 215)) || s > 0.75) offFamily++;
      const n4 = [at(x - 1, y), at(x + 1, y), at(x, y - 1), at(x, y + 1)];
      if (n4.every((n) => n !== null) && n4.every((n) => n !== c)) isolated++;
      let same = true;
      for (let dy = -1; dy <= 1 && same; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const n = at(x + dx, y + dy);
          if (n !== null && n !== c) {
            same = false;
            break;
          }
        }
      }
      if (same) flat++;
      const b = at(x + 1, y);
      if (b !== null && b !== c && at(x + 2, y) === c && at(x, y + 1) === b) {
        if (at(x + 1, y + 1) === c && at(x + 2, y + 1) === b) checker++;
      }
    }
  }
  const pct = (n) => (world > 0 ? Math.round((1000 * n) / world) / 10 : 0);
  return {
    world,
    masked: grid.masked,
    offPalette: grid.offPalette,
    colours: counts.size,
    offFamilyPct: pct(offFamily),
    minValuePct: Math.round(minV * 100),
    checker,
    isolated,
    accentPct: pct(accent),
    playerPct: pct(players),
    flatPct: pct(flat),
    palette: [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 20)
      .map(([c, n]) => `${PALETTE[c] || c}:${pct(n)}`),
  };
}

/** Pass/fail against the rubric's numeric limits. */
export function verdict(m) {
  const fails = [];
  if (m.colours > 16) fails.push(`colours ${m.colours} > 16`);
  if (m.offPalette > 0) fails.push(`off-palette pixels ${m.offPalette}`);
  if (m.offFamilyPct > 0) fails.push(`off-family ${m.offFamilyPct}%`);
  if (m.minValuePct < 35) fails.push(`min value ${m.minValuePct}% < 35%`);
  if (m.checker > 0) fails.push(`checker cells ${m.checker}`);
  if (m.isolated > 20) fails.push(`isolated pixels ${m.isolated} > 20`);
  if (m.accentPct > 1) fails.push(`accent ${m.accentPct}% > 1%`);
  if (m.flatPct < 60) fails.push(`flat ${m.flatPct}% < 60%`);
  return fails;
}

export function checkFile(file) {
  const m = measure(artGrid(decodePng(fs.readFileSync(file))));
  return { file: path.basename(file), ...m, fails: verdict(m) };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const files = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  const json = process.argv.includes('--json');
  let bad = 0;
  for (const f of files) {
    const r = checkFile(f);
    bad += r.fails.length > 0 ? 1 : 0;
    if (json) {
      console.log(JSON.stringify(r));
      continue;
    }
    console.log(
      `${r.file}: colours ${r.colours}, off-family ${r.offFamilyPct}%, min V ${r.minValuePct}%, ` +
        `checker ${r.checker}, isolated ${r.isolated}, accent ${r.accentPct}%, players ${r.playerPct}%, ` +
        `flat ${r.flatPct}%, off-palette ${r.offPalette}, masked ${r.masked} ` +
        `${r.fails.length ? 'FAIL: ' + r.fails.join('; ') : 'ok'}`,
    );
    console.log(`  ${r.palette.join(' ')}`);
  }
  process.exit(bad > 0 ? 1 : 0);
}
