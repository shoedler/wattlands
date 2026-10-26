#!/usr/bin/env node
// Turbo Reel's art style check on screenshots of the view at 3 screen px per art px (1920x1080
// for the 640x360 base; any flex art size: the art size is the image size / 3): the rubric's
// numeric checks on the world layer with the HUD masked.
//
//   node tests/games/fishing/art/style_check.mjs <png>... [--json] [--hud=x,y,w,h;...]
//
// The HUD rects follow FishingHud.layout() for the image's art size (hudRects()); --hud adds
// rects (art px) for HUD drawn at a moving spot (the speed behind the stern). A framed HUD panel
// (a deep-teal box in a one-pixel surface-teal frame, the fight panel under the boat) is masked
// wherever it is.
// The world is every art pixel whose 3x3 screen block is one colour, outside the HUD rects and
// not a HUD panel (a deep-teal box over the view: a chip or the game banner); HUD text and
// panels are counted as masked, and world colours outside the palette are counted as
// off-palette. Over the whole frame (HUD included) it also counts the off-grid cells (a 3x3
// block of palette colours that is not one colour: chrome drawn off the art pixel grid; blocks
// holding a non-palette colour, the kit's safety banners, are left out) and the HUD panels'
// share of the frame.
// Per screenshot: unique world colours, off-family share (non-accent pixels outside hue 140-215
// unless near-neutral, or above 75 % saturation), the lowest value, checker cells (3x2 windows alternating both ways; a 1:1 line is not one), isolated pixels (differing
// from all eight neighbours, so a 1:1 line is not a speck), the accent and player-colour shares, and the flat share (pixels
// whose eight neighbours, where they are world, are the same colour) and the light share (value
// at least LIGHT_V). Zero dependencies (node:zlib).
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

export const PALETTE = {
  ebf2e7: 'foam', cedfd2: 'sky', b6d7cf: 'haze', '91c2c2': 'surface', '6fa3a6': 'upper',
  '4b858f': 'mid', '2c6778': 'deep', '1c4d65': 'abyss', a7bfb3: 'sage', '627179': 'wood',
  '4e5c67': 'slate', c98a5e: 'accent', '7f9cbf': 'player_slate', '9fb07a': 'player_moss',
  a68aa8: 'player_plum',
};
export const ACCENT = 'c98a5e';
// The one colour outside the palette the HUD may use (the heart rate box's muted red heart):
// a palette colour for the HUD's grid check, off-palette anywhere in the world.
export const HUD_ONLY = ['b5675f'];
export const PLAYERS = ['7f9cbf', '9fb07a', 'a68aa8'];
// HUD rects in art px for art size w x h (FishingHud.layout(), with a margin): the minimap, the
// board, the bottom-left stack (the cruise box, its zone tag, the gear, the workout timeline),
// the PANIC corner.
export function hudRects(w = 640, h = 360) {
  return [
    [2, 0, w - 220, 34],
    [w - 218, 0, 218, 62],
    [0, h - 102, 312, 102],
    [w - 140, h - 48, 140, 48],
  ];
}
// The kit's toast and banner rects (FishingHud.layout() toasts, banners): masked only when
// something that is not world (text, off-palette panels) shows inside them.
export function popupRects(w = 640, h = 360) {
  const mm = w - 228;
  const tw = Math.min(296, mm - 16);
  const bw = Math.min(400, w - 8);
  return [
    [4 + Math.floor((mm - tw) / 2) - 2, 36, tw + 4, 26],
    [Math.floor((w - bw) / 2) - 2, 148, bw + 4, 64],
  ];
}
export const HUD_RECTS = hudRects();
export const POPUP_RECTS = popupRects();
export const SCALE = 3;
// The value mass: world pixels at or above this value (the surface teal and lighter) should
// cover at least 60 % of the world, like the reference's light field.
export const LIGHT_V = 0.755;
// The crisp white field: the sky and the foam-white water (value 87 and up), which should cover
// most of a shallow shot, like the reference's sky and snow (reported, not judged: deep shots
// are darker by design).
export const WHITE_V = 0.87;
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

/** The art-pixel grid of a screenshot: {w, h, cells: Array<string|null>} (null: masked). */
export function artGrid(img, scale = SCALE, hudRects = HUD_RECTS, popups = POPUP_RECTS) {
  const g = artCells(img, scale, hudRects);
  const inside = (x, y, [rx, ry, rw, rh]) => x >= rx && x < rx + rw && y >= ry && y < ry + rh;
  for (const r of popups) {
    if (!g.foreign.some(([x, y]) => inside(x, y, r))) continue;
    for (let y = r[1]; y < Math.min(r[1] + r[3], g.h); y++) {
      for (let x = r[0]; x < Math.min(r[0] + r[2], g.w); x++) {
        const c = g.cells[y * g.w + x];
        if (c !== null && !(c in PALETTE)) g.offPalette--;
        if (c !== null || g.foreignAt.has(y * g.w + x)) {
          g.cells[y * g.w + x] = null;
          if (!g.foreignAt.has(y * g.w + x)) g.masked++;
        }
      }
    }
  }
  g.masked += maskPanels(g.cells, g.w, g.h);
  return { w: g.w, h: g.h, cells: g.cells, masked: g.masked, offPalette: g.offPalette };
}

// HUD panels are one exact colour, the deep teal (FishingPalette.HUD_PANEL). The world uses it
// too, in wide bands and big floors that reach the frame's edge; a deep-teal region over
// PANEL_MIN_PX art pixels that stays off the edges and at most PANEL_MAX_ROWS tall is a panel
// (a chip, the game banner), masked with its bounding box (its text included). A taller one is
// a panel when a one-pixel surface-teal frame (FRAME_COLOUR) runs round at least FRAME_SHARE of
// its bounding box: it is masked with its frame.
export const PANEL_COLOUR = '2c6778';
export const FRAME_COLOUR = '91c2c2';
export const PANEL_MIN_PX = 60;
export const PANEL_MAX_ROWS = 24;
export const FRAME_SHARE = 0.9;
export function maskPanels(cells, w, h) {
  const seen = new Uint8Array(w * h);
  let masked = 0;
  for (let i = 0; i < w * h; i++) {
    if (seen[i] || cells[i] !== PANEL_COLOUR) continue;
    const region = [];
    const stack = [i];
    seen[i] = 1;
    let [x0, y0, x1, y1] = [w, h, -1, -1];
    while (stack.length) {
      const j = stack.pop();
      region.push(j);
      const x = j % w;
      const y = (j - x) / w;
      x0 = Math.min(x0, x);
      x1 = Math.max(x1, x);
      y0 = Math.min(y0, y);
      y1 = Math.max(y1, y);
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx;
        const ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        const k = ny * w + nx;
        if (!seen[k] && cells[k] === PANEL_COLOUR) {
          seen[k] = 1;
          stack.push(k);
        }
      }
    }
    const edge = x0 === 0 || y0 === 0 || x1 === w - 1 || y1 === h - 1;
    if (region.length <= PANEL_MIN_PX || edge) continue;
    let pad = 0;
    if (y1 - y0 + 1 > PANEL_MAX_ROWS) {
      if (frameShare(cells, w, h, x0 - 1, y0 - 1, x1 + 1, y1 + 1) < FRAME_SHARE) continue;
      pad = 1;
    }
    for (let y = y0 - pad; y <= y1 + pad; y++) {
      for (let x = x0 - pad; x <= x1 + pad; x++) {
        if (cells[y * w + x] !== null) {
          cells[y * w + x] = null;
          masked++;
        }
      }
    }
  }
  return masked;
}

/** The share of the rectangle's outline cells that are the surface-teal frame colour. */
function frameShare(cells, w, h, x0, y0, x1, y1) {
  if (x0 < 0 || y0 < 0 || x1 >= w || y1 >= h) return 0;
  let n = 0;
  let hit = 0;
  for (let x = x0; x <= x1; x++) {
    for (const y of [y0, y1]) {
      n++;
      hit += cells[y * w + x] === FRAME_COLOUR ? 1 : 0;
    }
  }
  for (let y = y0 + 1; y < y1; y++) {
    for (const x of [x0, x1]) {
      n++;
      hit += cells[y * w + x] === FRAME_COLOUR ? 1 : 0;
    }
  }
  return n > 0 ? hit / n : 0;
}

/** Off-grid cells and the HUD panels' share over a whole screenshot (see the header). */
export function frameGrid(img, scale = SCALE, hudRects = HUD_RECTS) {
  const w = Math.floor(img.width / scale);
  const h = Math.floor(img.height / scale);
  let offGrid = 0;
  let panel = 0;
  const inHud = (x, y) => hudRects.some(([rx, ry, rw, rh]) => x >= rx && x < rx + rw && y >= ry && y < ry + rh);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const seen = new Set();
      for (let dy = 0; dy < scale; dy++) {
        for (let dx = 0; dx < scale; dx++) {
          const i = ((y * scale + dy) * img.width + x * scale + dx) * 4;
          seen.add(hex(img.data[i], img.data[i + 1], img.data[i + 2]));
        }
      }
      if (seen.size > 1 && [...seen].every((c) => c in PALETTE || HUD_ONLY.includes(c))) offGrid++;
      if (seen.size === 1 && seen.has(PANEL_COLOUR) && inHud(x, y)) panel++;
    }
  }
  return { offGrid, panelPct: Math.round((1000 * panel) / (w * h)) / 10 };
}

function artCells(img, scale, hudRects) {
  const w = Math.floor(img.width / scale);
  const h = Math.floor(img.height / scale);
  const cells = new Array(w * h).fill(null);
  let masked = 0;
  let offPalette = 0;
  const foreign = [];
  const foreignAt = new Set();
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
        foreign.push([x, y]);
        foreignAt.add(y * w + x);
        continue;
      }
      if (!(first in PALETTE)) {
        offPalette++;
        foreign.push([x, y]);
      }
      cells[y * w + x] = first;
    }
  }
  return { w, h, cells, masked, offPalette, foreign, foreignAt };
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
  let light = 0;
  let white = 0;
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
      if (v >= LIGHT_V) light++;
      if (v >= WHITE_V) white++;
      if (c === ACCENT) accent++;
      else if (PLAYERS.includes(c)) players++;
      else if ((s >= NEUTRAL_S && (hue < 140 || hue > 215)) || s > 0.75) offFamily++;
      const n4 = [at(x - 1, y), at(x + 1, y), at(x, y - 1), at(x, y + 1)];
      const d4 = [at(x - 1, y - 1), at(x + 1, y - 1), at(x - 1, y + 1), at(x + 1, y + 1)];
      const lone = n4.every((n) => n !== null && n !== c) && d4.every((n) => n !== c);
      if (lone) isolated++;
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
    lightPct: pct(light),
    whitePct: pct(white),
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
  if (m.lightPct < 60) fails.push(`light ${m.lightPct}% < 60%`);
  if (m.offGrid > 0) fails.push(`off-grid cells ${m.offGrid}`);
  return fails;
}

/** The rects of a --hud=x,y,w,h;... argument ([] without one). */
export function parseRects(arg) {
  if (!arg) return [];
  return arg
    .split(';')
    .filter((s) => s.trim() !== '')
    .map((s) => s.split(',').map((v) => parseInt(v, 10)));
}

export function checkFile(file, extra = []) {
  const img = decodePng(fs.readFileSync(file));
  const w = Math.floor(img.width / SCALE);
  const h = Math.floor(img.height / SCALE);
  const hud = [...hudRects(w, h), ...extra];
  const m = { ...measure(artGrid(img, SCALE, hud, popupRects(w, h))), ...frameGrid(img, SCALE, hud) };
  return { file: path.basename(file), art: `${w}x${h}`, ...m, fails: verdict(m) };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const files = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  const json = process.argv.includes('--json');
  const hudArg = process.argv.find((a) => a.startsWith('--hud='));
  const extra = parseRects(hudArg ? hudArg.slice(6) : '');
  let bad = 0;
  for (const f of files) {
    const r = checkFile(f, extra);
    bad += r.fails.length > 0 ? 1 : 0;
    if (json) {
      console.log(JSON.stringify(r));
      continue;
    }
    console.log(
      `${r.file} (${r.art}): colours ${r.colours}, off-family ${r.offFamilyPct}%, min V ${r.minValuePct}%, ` +
        `checker ${r.checker}, isolated ${r.isolated}, accent ${r.accentPct}%, players ${r.playerPct}%, ` +
        `flat ${r.flatPct}%, light ${r.lightPct}%, white ${r.whitePct}%, off-palette ${r.offPalette}, masked ${r.masked}, ` +
        `off-grid ${r.offGrid}, panels ${r.panelPct}% ` +
        `${r.fails.length ? 'FAIL: ' + r.fails.join('; ') : 'ok'}`,
    );
    console.log(`  ${r.palette.join(' ')}`);
  }
  process.exit(bad > 0 ? 1 : 0);
}
