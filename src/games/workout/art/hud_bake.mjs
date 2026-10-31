#!/usr/bin/env node
// Bakes Workout's HUD type and crank icon into assets/workout/hud/. Zero dependencies, deterministic.
//   node src/games/workout/art/hud_bake.mjs           writes the PNGs
//   node src/games/workout/art/hud_bake.mjs --check   compares decoded pixels with the committed PNGs and
//                                                     the fonts' import settings, exit 1 on any difference
// The crank icon uses only rig.mjs's angle formula, so W-ART's rig numbers cannot stale it.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CELL, CELL_T, COLUMNS, DIGIT_CELL, DIGIT_CHARS, DIGITS, EXTRA, FIRST, LAST, ROWS, TEXT } from './hud_font.mjs';
import { readPng, writePng } from './png.mjs';
import { Canvas } from './raster.mjs';
import { CRANK_FRAMES, crankTheta } from './rig.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const HUD_DIR = join(here, '../../../../assets/workout/hud');

const WHITE = [255, 255, 255, 255];
const GREY = [150, 150, 150, 255];
export const ICON = 13;

/** The characters in the font's grid order. */
export const chars = () => {
  const out = [];
  for (let c = FIRST; c <= LAST; c++) out.push(String.fromCodePoint(c));
  for (const c of EXTRA) out.push(String.fromCodePoint(c));
  return out;
};

const ink = (canvas, x0, y0, rows) => {
  rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) if (row[x] === '#') canvas.px(x0 + x, y0 + y, WHITE);
  });
};

/** Glyph `ch` as its rows in the 5 x 7 face. */
const textRows = (ch) => {
  const g = TEXT[ch];
  if (g === undefined) throw new Error(`no glyph for ${ch}`);
  return g.split('/');
};

/** Glyph `ch` stretched to 11 rows (9 cap, 2 descender) by doubling two stem rows. */
export function tallRows(ch) {
  const rows = textRows(ch);
  while (rows.length < 9) rows.push('.....');
  const code = ch.codePointAt(0);
  const dup = code >= 97 && code <= 122 ? [3, 5] : [1, 4];
  const out = [];
  for (let y = 0; y < 7; y++) {
    out.push(rows[y]);
    if (dup.includes(y)) out.push(rows[y]);
  }
  out.push(rows[7], rows[8]);
  return out;
}

function faceImage(cell, rowsOf) {
  const canvas = new Canvas(COLUMNS * cell[0], ROWS * cell[1]);
  chars().forEach((ch, i) => {
    ink(canvas, (i % COLUMNS) * cell[0], Math.floor(i / COLUMNS) * cell[1], rowsOf(ch));
  });
  return canvas;
}

function digitsImage() {
  const canvas = new Canvas(DIGIT_CHARS.length * DIGIT_CELL[0], DIGIT_CELL[1]);
  [...DIGIT_CHARS].forEach((ch, i) => {
    DIGITS[ch].forEach((row, y) => {
      for (let x = 0; x < row.length; x++) {
        if (row[x] === '#') canvas.rect(i * DIGIT_CELL[0] + x * 2, y * 2, 2, 2, WHITE);
      }
    });
  });
  return canvas;
}

/** 24 frames in a row: chainring, the near crank with its pedal, the far crank. White ink: tinted when drawn. */
function crankImage() {
  const canvas = new Canvas(ICON * CRANK_FRAMES, ICON);
  for (let k = 0; k < CRANK_FRAMES; k++) {
    const frame = new Canvas(ICON, ICON);
    const c = (ICON - 1) / 2;
    frame.ring(c, c, 3, WHITE, 2);
    const a = crankTheta(k);
    const tip = (r, sign) => [c + sign * r * Math.cos(a), c + sign * r * Math.sin(a)];
    const far = tip(5, -1);
    frame.line(c, c, far[0], far[1], GREY);
    const near = tip(5, 1);
    frame.thick(c, c, near[0], near[1], 2, WHITE);
    frame.rect(Math.round(near[0]) - 2, Math.round(near[1]), 5, 1, WHITE);
    frame.px(c, c, GREY);
    for (let y = 0; y < ICON; y++) {
      for (let x = 0; x < ICON; x++) {
        const v = frame.get(x, y);
        if (v[3] > 0) canvas.px(k * ICON + x, y, v);
      }
    }
  }
  return canvas;
}

/** Everything the bake owns: Map of file name -> Canvas. */
export function renderAll() {
  return new Map([
    ['wo_text_5x7.png', faceImage(CELL, textRows)],
    ['wo_tall_5x9.png', faceImage(CELL_T, tallRows)],
    ['wo_digits_14x24.png', digitsImage()],
    ['hud_crank.png', crankImage()],
  ]);
}

const IMPORTER = 'importer="font_data_image"';
const FONT_METRICS = { 'wo_text_5x7.png': 'ascent=7', 'wo_tall_5x9.png': 'ascent=9' };

function check() {
  const problems = [];
  for (const [name, canvas] of renderAll()) {
    const path = join(HUD_DIR, name);
    if (!existsSync(path)) {
      problems.push(`${name}: missing`);
      continue;
    }
    const png = readPng(path);
    if (png.width !== canvas.w || png.height !== canvas.h) {
      problems.push(`${name}: ${png.width} x ${png.height}, wanted ${canvas.w} x ${canvas.h}`);
    } else if (Buffer.compare(Buffer.from(png.data), Buffer.from(canvas.data)) !== 0) {
      problems.push(`${name}: pixels differ`);
    }
  }
  for (const [name, metric] of Object.entries(FONT_METRICS)) {
    const path = join(HUD_DIR, `${name}.import`);
    const text = existsSync(path) ? readFileSync(path, 'utf8') : '';
    if (!text.includes(IMPORTER) || !text.includes(metric) || !text.includes('columns=16')) {
      problems.push(`${name}.import: not the font importer's settings`);
    }
  }
  return problems;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  if (process.argv.includes('--check')) {
    const problems = check();
    for (const p of problems) console.error(`hud_bake: ${p}`);
    if (problems.length > 0) process.exit(1);
    console.log('hud_bake: OK');
  } else {
    for (const [name, canvas] of renderAll()) writePng(join(HUD_DIR, name), canvas.w, canvas.h, canvas.data);
    console.log(`hud_bake: wrote ${HUD_DIR}`);
  }
}
