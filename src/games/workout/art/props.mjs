// The world's moving props and the sprint furniture. True colour, tinted by the view, no text but the
// gantry's pixel word. Sheet layouts agree with kit.json's props block (bake.mjs).
import { Canvas, hex } from './raster.mjs';

const OUTLINE = hex('#1c1e24');

/** Tower 30 x 70 at (0, 0), then the rotor's 8 frames of 26 x 26 from x 30. */
export function windpump() {
  const c = new Canvas(30 + 26 * 8, 70);
  const steel = hex('#6a7078');
  c.line(15, 10, 6, 69, steel);
  c.line(15, 10, 24, 69, steel);
  c.line(9, 50, 21, 50, steel);
  c.line(11, 30, 19, 30, steel);
  c.line(9, 50, 19, 30, steel);
  for (let f = 0; f < 8; f++) {
    const a0 = (f * 45 * Math.PI) / 180 / 3;
    const ox = 30 + f * 26 + 13;
    for (let b = 0; b < 6; b++) {
      const a = a0 + (b * Math.PI) / 3;
      c.line(ox, 13, ox + 11 * Math.cos(a), 13 + 11 * Math.sin(a), hex('#c8ccd0'));
    }
    c.disk(ox, 13, 1, OUTLINE);
  }
  return c;
}

/** 12 x 9, 2 frames (graze) across, 3 coats down. */
export function cattle() {
  const c = new Canvas(24, 27);
  const coats = [hex('#6c4a34'), hex('#d8d0c0'), hex('#2a2a2e')];
  coats.forEach((coat, row) => {
    for (let f = 0; f < 2; f++) {
      const x = f * 12;
      const y = row * 9;
      c.rect(x + 1, y + 3, 8, 4, coat);
      c.rect(x + 2, y + 7, 1, 2, OUTLINE);
      c.rect(x + 7, y + 7, 1, 2, OUTLINE);
      c.rect(x + 9, y + (f === 0 ? 2 : 5), 2, 3, coat);
    }
  });
  return c;
}

/** 36 x 22, 4 frames: a small tractor with a turning rear wheel. */
export function tractor() {
  const c = new Canvas(36 * 4, 22);
  for (let f = 0; f < 4; f++) {
    const x = f * 36;
    c.rect(x + 12, 7, 18, 7, hex('#b8442c'));
    c.rect(x + 8, 1, 10, 8, hex('#30343c'));
    c.disk(x + 9, 15, 6, OUTLINE);
    c.disk(x + 28, 18, 3, OUTLINE);
    const a = (f * Math.PI) / 2;
    c.px(x + 9 + 4 * Math.cos(a), 15 + 4 * Math.sin(a), hex('#c8ccd0'));
  }
  return c;
}

/** 10 x 16, 6 frames of chimney smoke, rising and thinning. */
export function smoke() {
  const c = new Canvas(60, 16);
  const puff = hex('#c8ccd4');
  for (let f = 0; f < 6; f++) {
    for (let i = 0; i < 3; i++) {
      const t = ((f + i * 2) % 6) / 6;
      c.disk(f * 10 + 5 + Math.round(2 * t), 14 - t * 12, 1 + t, puff);
    }
  }
  return c;
}

/** 5 x 3, 2 frames: one bird, wings up and down. */
export function flock() {
  const c = new Canvas(10, 3);
  const bird = hex('#20222a');
  c.line(0, 0, 2, 1, bird);
  c.line(2, 1, 4, 0, bird);
  c.line(5, 2, 7, 1, bird);
  c.line(7, 1, 9, 2, bird);
  return c;
}

/** 18 x 26: a day balloon. */
export function balloon() {
  const c = new Canvas(18, 26);
  c.disk(9, 9, 8, hex('#d8583c'));
  c.rect(7, 2, 4, 15, hex('#f0d060'));
  c.line(5, 15, 7, 22, OUTLINE);
  c.line(13, 15, 11, 22, OUTLINE);
  c.rect(7, 22, 4, 3, hex('#6c4a34'));
  return c;
}

/** 16 x 30, 8 spectators across; row 0 hands down, row 1 hands up. */
export function crowd() {
  const c = new Canvas(128, 60);
  const shirts = ['#c04848', '#3870b0', '#d8b040', '#489870', '#8850a0', '#e08848', '#5098b8', '#d0d0c8'].map(hex);
  const skins = ['#e8b48c', '#c98e62', '#8e5c3a', '#f0c8a4'].map(hex);
  for (let s = 0; s < 8; s++) {
    for (let row = 0; row < 2; row++) {
      const x = s * 16 + 8;
      const y = row * 30;
      const skin = skins[s % 4];
      c.rect(x - 2, y + 22, 2, 8, hex('#24262e'));
      c.rect(x + 1, y + 22, 2, 8, hex('#24262e'));
      c.rect(x - 3, y + 11, 7, 11, shirts[s]);
      c.disk(x, y + 7, 3, skin);
      if (row === 0) {
        c.line(x - 4, y + 12, x - 5, y + 20, skin);
        c.line(x + 5, y + 12, x + 6, y + 20, skin);
      } else {
        c.line(x - 4, y + 12, x - 6, y + 3, skin);
        c.line(x + 5, y + 12, x + 7, y + 3, skin);
      }
    }
  }
  return c;
}

/** 12 x 16, 4 frames: a generic striped hand flag, waving. */
export function flag() {
  const c = new Canvas(48, 16);
  const stripes = [hex('#f0f0e8'), hex('#3870b0')];
  for (let f = 0; f < 4; f++) {
    const x = f * 12;
    c.rect(x + 1, 1, 1, 15, OUTLINE);
    for (let i = 0; i < 9; i++) {
      const wave = Math.round(Math.sin(((i + f * 2) * Math.PI) / 4));
      for (let j = 0; j < 7; j++) c.px(x + 2 + i, 1 + j + wave, stripes[j < 3 ? 0 : 1]);
    }
  }
  return c;
}

const GLYPHS = {
  S: ['111', '100', '111', '001', '111'],
  P: ['111', '101', '111', '100', '100'],
  R: ['110', '101', '110', '101', '101'],
  I: ['111', '010', '010', '010', '111'],
  N: ['101', '111', '111', '111', '101'],
  T: ['111', '010', '010', '010', '010'],
};

/** 200 x 90: the sprint banner over the road, with a pixel word. */
export function gantry() {
  const c = new Canvas(200, 90);
  const post = hex('#3a3d44');
  c.rect(6, 6, 3, 84, post);
  c.rect(191, 6, 3, 84, post);
  c.rect(4, 8, 192, 24, hex('#d8583c'));
  c.rect(4, 8, 192, 2, hex('#f0f0e8'));
  c.rect(4, 30, 192, 2, hex('#f0f0e8'));
  const word = 'SPRINT';
  const scale = 3;
  let x = 100 - Math.floor((word.length * 4 * scale - scale) / 2);
  for (const ch of word) {
    GLYPHS[ch].forEach((row, j) => {
      [...row].forEach((bit, i) => {
        if (bit === '1') c.rect(x + i * scale, 12 + j * scale, scale, scale, hex('#f6f6f0'));
      });
    });
    x += 4 * scale;
  }
  return c;
}
