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
const FAINT = [92, 92, 92, 255];
// The pedal keeps its own colour through the tint, so it stands off the arm even when the two line up.
const PEDAL_INK = [255, 176, 48, 255];
const CLEAR = [0, 0, 0, 0];
// The crank icon: 27 px fills the plate's cadence column from its rule (y 16) to the gauge's needle (y 45).
export const ICON = 27;
export const ARM = 10;
export const FAR_ARM = 9;
export const RING = 6;
export const TEETH = 8;
// Half width and half height of the level pedal, around the crank's tip.
export const PEDAL = [3, 2];

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

/** A level rectangle around (x, y): half widths `hw`, `hh`. */
const box = (frame, x, y, hw, hh, ink) => frame.rect(x - hw, y - hh, 2 * hw + 1, 2 * hh + 1, ink);

/**
 * One frame, in draw order: the far crank, faint and with no pedal, so the icon is never symmetric; the
 * chainring, grey, with teeth that turn; a clear halo; then the near crank and its level pedal in full
 * ink, with the axle as a hole in the arm so the arm reads as an arm and not as an arrow.
 */
function crankFrame(k) {
  const frame = new Canvas(ICON, ICON);
  const c = (ICON - 1) / 2;
  const a = crankTheta(k);
  const along = (r) => [Math.round(c + r * Math.cos(a)), Math.round(c + r * Math.sin(a))];
  frame.thick(c, c, ...along(-FAR_ARM), 3, FAINT);
  frame.ring(c, c, RING, GREY, 2);
  for (let t = 0; t < TEETH; t++) {
    const ta = a + (t * 2 * Math.PI) / TEETH;
    frame.px(c + (RING + 1) * Math.cos(ta), c + (RING + 1) * Math.sin(ta), GREY);
  }
  const tip = along(ARM);
  const tail = along(-2);
  frame.thick(...tail, ...tip, 6, CLEAR);
  box(frame, tip[0], tip[1], PEDAL[0] + 1, PEDAL[1] + 1, CLEAR);
  frame.thick(...tail, ...tip, 4, WHITE);
  box(frame, tip[0], tip[1], PEDAL[0], PEDAL[1], PEDAL_INK);
  frame.px(c, c, CLEAR);
  return frame;
}

/** 24 frames in a row. White ink: tinted when drawn, so stale cadence dims it. */
function crankImage() {
  const canvas = new Canvas(ICON * CRANK_FRAMES, ICON);
  for (let k = 0; k < CRANK_FRAMES; k++) {
    const frame = crankFrame(k);
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
