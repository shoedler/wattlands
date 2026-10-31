// The world's moving props and the sprint furniture. True colour, tinted by the view, no text but the
// gantry's pixel word. Sheet layouts agree with kit.json's props block (bake.mjs).
// Shaded from the same light as the world: upper right. Colours sit a step quieter than the riders'.
import { Canvas, hex } from './raster.mjs';

const OUTLINE = hex('#1c1e24');

/** Cell pixels the view lines sprites up by; kit.json publishes them. */
export const SMOKE_ORIGIN = [5, 15]; // goes on a chimney's top pixel
export const CROWD_HAND_UP = [15, 3]; // the raised near hand in row 1
export const FLAG_GRIP = [1, 15]; // goes on a raised hand

/** Tower 30 x 70 at (0, 0), then the rotor's 8 frames of 26 x 26 from x 30. */
export function windpump() {
  const c = new Canvas(30 + 26 * 8, 70);
  const steel = hex('#5c626c');
  const lit = hex('#8c929c');
  const dark = hex('#3a3e48');
  // Four-legged lattice tower, narrowing to the head.
  c.line(13, 12, 5, 69, steel);
  c.line(17, 12, 25, 69, lit);
  c.line(14, 12, 11, 69, dark);
  c.line(16, 12, 19, 69, dark);
  for (const [y, t] of [
    [60, 0.84],
    [48, 0.63],
    [38, 0.46],
    [28, 0.28],
    [20, 0.14],
  ]) {
    const half = 2 + t * 8;
    c.line(15 - half, y, 15 + half, y, steel);
  }
  for (const [y0, y1] of [
    [60, 48],
    [48, 38],
    [38, 28],
    [28, 20],
  ]) {
    const hw0 = 2 + ((y0 - 12) / 57) * 8;
    const hw1 = 2 + ((y1 - 12) / 57) * 8;
    c.line(15 - hw0, y0, 15 + hw1, y1, dark);
    c.line(15 + hw0, y0, 15 - hw1, y1, dark);
  }
  // The platform, the gearbox, the pump rod, the tail vane behind.
  c.rect(11, 13, 9, 1, lit);
  c.rect(13, 6, 5, 5, dark);
  c.rect(16, 6, 2, 5, lit);
  c.line(15, 12, 15, 66, lit);
  c.rect(1, 6, 13, 1, steel);
  c.polyFill(
    [
      [0, 3],
      [7, 5],
      [7, 8],
      [0, 10],
    ],
    hex('#b86a4c'),
  );
  c.line(0, 3, 0, 10, hex('#e0a080'));
  for (let f = 0; f < 8; f++) {
    // 8 vanes, 45 degree period: 8 frames step through one period.
    const a0 = (((f * 45) / 8) * Math.PI) / 180;
    const ox = 30 + f * 26 + 13;
    for (let b = 0; b < 8; b++) {
      const a = a0 + (b * Math.PI) / 4;
      const a1 = a + 0.26;
      const colour = hex(b % 2 === 0 ? '#d4d8dc' : '#9aa0a8');
      c.polyFill(
        [
          [ox + 4 * Math.cos(a), 13 + 4 * Math.sin(a)],
          [ox + 12 * Math.cos(a), 13 + 12 * Math.sin(a)],
          [ox + 12 * Math.cos(a1), 13 + 12 * Math.sin(a1)],
          [ox + 4 * Math.cos(a1), 13 + 4 * Math.sin(a1)],
        ],
        colour,
      );
    }
    c.ring(ox, 13, 12, steel);
    c.disk(ox, 13, 2, OUTLINE);
    c.px(ox + 1, 12, lit);
  }
  return c;
}

/** 12 x 9, 2 frames (graze) across, 3 coats down. */
export function cattle() {
  const c = new Canvas(24, 27);
  const coats = [
    [hex('#6c4a34'), hex('#4c3226'), hex('#8c6444')],
    [hex('#d8d0c0'), hex('#a8a098'), hex('#f0ece0')],
    [hex('#2a2a2e'), hex('#18181c'), hex('#4a4a50')],
  ];
  coats.forEach(([coat, dark, lit], row) => {
    for (let f = 0; f < 2; f++) {
      const x = f * 12;
      const y = row * 9;
      c.rect(x + 1, y + 3, 8, 4, coat);
      c.rect(x + 1, y + 6, 8, 1, dark);
      c.rect(x + 3, y + 3, 5, 1, lit);
      if (row === 1) {
        c.rect(x + 2, y + 4, 2, 2, hex('#3c3634'));
        c.rect(x + 6, y + 3, 2, 2, hex('#3c3634'));
      }
      c.rect(x + 2, y + 7, 1, 2, dark);
      c.rect(x + 4, y + 7, 1, 2, dark);
      c.rect(x + 7, y + 7, 1, 2, dark);
      c.rect(x + 8, y + 7, 1, 2, dark);
      c.px(x, y + 4, dark);
      c.px(x, y + 5, dark);
      // Head up and looking, then down in the grass.
      if (f === 0) {
        c.rect(x + 9, y + 2, 2, 3, coat);
        c.px(x + 11, y + 3, dark);
        c.px(x + 9, y + 1, dark);
      } else {
        c.rect(x + 9, y + 5, 2, 3, coat);
        c.px(x + 11, y + 7, dark);
      }
    }
  });
  return c;
}

/** 36 x 22, 4 frames: a small tractor with a driver and a turning rear wheel. */
export function tractor() {
  const c = new Canvas(36 * 4, 22);
  const paint = [hex('#6c2c20'), hex('#a43e28'), hex('#d0603c')];
  for (let f = 0; f < 4; f++) {
    const x = f * 36;
    // Bonnet, grille, exhaust stack.
    c.rect(x + 15, 8, 15, 7, paint[1]);
    c.rect(x + 15, 8, 15, 1, paint[2]);
    c.rect(x + 15, 13, 15, 2, paint[0]);
    for (let i = 0; i < 4; i++) c.px(x + 18 + i * 3, 11, paint[0]);
    c.rect(x + 29, 8, 2, 7, OUTLINE);
    c.rect(x + 24, 3, 1, 5, OUTLINE);
    c.px(x + 24, 2, hex('#70747c'));
    // The cab: a roof, a glass, a driver in it.
    c.rect(x + 6, 1, 11, 1, hex('#30343c'));
    c.rect(x + 7, 2, 1, 7, OUTLINE);
    c.rect(x + 15, 2, 1, 7, OUTLINE);
    c.rect(x + 8, 2, 7, 6, hex('#7c98a4'));
    c.rect(x + 8, 2, 3, 2, hex('#b0c4cc'));
    c.rect(x + 10, 4, 3, 4, hex('#34506c'));
    c.rect(x + 10, 2, 3, 2, hex('#e0b48c'));
    c.rect(x + 7, 9, 9, 3, paint[0]);
    // Rear wheel with turning lugs; front wheel.
    c.disk(x + 9, 14, 7, OUTLINE);
    c.disk(x + 9, 14, 3, hex('#b08838'));
    c.px(x + 9, 14, OUTLINE);
    for (let l = 0; l < 8; l++) {
      const a = (f * Math.PI) / 16 + (l * Math.PI) / 4;
      c.px(x + 9 + 7.5 * Math.cos(a), 14 + 7.5 * Math.sin(a), hex('#4a4c54'));
      c.px(x + 9 + 5 * Math.cos(a), 14 + 5 * Math.sin(a), hex('#34363c'));
    }
    c.disk(x + 28, 18, 3, OUTLINE);
    c.disk(x + 28, 18, 1, hex('#b08838'));
    const a = (f * Math.PI) / 2;
    c.px(x + 28 + 2.5 * Math.cos(a), 18 + 2.5 * Math.sin(a), hex('#4a4c54'));
  }
  return c;
}

/** 10 x 16, 6 frames of chimney smoke, rising, drifting with the wind and thinning. */
export function smoke() {
  const c = new Canvas(60, 16);
  const puff = hex('#c8ccd4');
  const dim = hex('#9ea2b0');
  for (let f = 0; f < 6; f++) {
    for (let i = 0; i < 3; i++) {
      const t = ((f + i * 2) % 6) / 6;
      const x = f * 10 + 5 - Math.round(3 * t);
      const y = 13 - t * 12;
      const r = 0.7 + t * 1.3;
      if (t < 0.7) {
        c.disk(x, y, r, dim);
        c.disk(x + 1, y - 1, Math.max(r - 1, 0.4), puff);
      } else {
        // Thins out into broken pixels near the top.
        c.px(x, y, dim);
        c.px(x + 2, y + 1, dim);
        c.px(x - 1, y - 1, puff);
      }
    }
    // Always a wisp sitting on the chimney's own pixel.
    c.px(f * 10 + 5, 15, dim);
    c.px(f * 10 + 5, 14, puff);
  }
  return c;
}

/** 5 x 3, 2 frames: one bird, wings up and down. */
export function flock() {
  const c = new Canvas(10, 3);
  const bird = hex('#20222a');
  c.px(0, 0, bird);
  c.px(1, 1, bird);
  c.px(2, 1, bird);
  c.px(3, 1, bird);
  c.px(4, 0, bird);
  c.px(5, 2, bird);
  c.px(6, 1, bird);
  c.px(7, 1, bird);
  c.px(8, 1, bird);
  c.px(9, 2, bird);
  return c;
}

/** 18 x 26: a day balloon, in stripes that wrap round its shape. */
export function balloon() {
  const c = new Canvas(18, 26);
  const a = [hex('#a83e28'), hex('#d8583c'), hex('#f08860')];
  const b = [hex('#b8983c'), hex('#f0d060'), hex('#fff0a0')];
  for (let j = -9; j <= 9; j++) {
    for (let i = -8; i <= 8; i++) {
      const e = (i * i) / 72 + (j * j) / (j > 0 ? 90 : 72);
      if (e > 1) continue;
      const w = Math.sqrt(Math.max(1 - (j * j) / 90, 0.01));
      const lon = Math.asin(Math.min(i / (8.3 * w), 1)) / Math.PI;
      const band = Math.floor((lon + 0.5) * 6);
      const s = (i * 0.6 - j * 0.8) / 9;
      const ramp = band % 2 === 0 ? a : b;
      c.px(9 + i, 9 + j, ramp[s > 0.42 ? 2 : s < -0.3 ? 0 : 1]);
    }
  }
  c.line(6, 17, 7, 22, OUTLINE);
  c.line(12, 17, 11, 22, OUTLINE);
  c.rect(7, 22, 5, 3, hex('#6c4a34'));
  c.rect(7, 22, 5, 1, hex('#94704c'));
  return c;
}

/** 16 x 30, 8 spectators across; row 0 hands down, row 1 hands up. */
export function crowd() {
  const c = new Canvas(128, 60);
  const shirts = ['#b84c44', '#3c6ca4', '#c8a644', '#468c6c', '#7c5094', '#d4844c', '#4c90ac', '#c4c4b8'].map(hex);
  const trousers = ['#26303e', '#3a3028', '#22242c', '#4a4c58', '#2c3648', '#26242a', '#58483a', '#32384a'].map(hex);
  const skins = ['#e8b48c', '#c98e62', '#8e5c3a', '#f0c8a4'].map(hex);
  const hairs = ['#3a2a20', '#16161a', '#8a6a40', '#c8c8c4', '#6c3a24', '#16161a', '#b89050', '#3a2a20'].map(hex);
  const darker = (col, k) => col.map((u) => Math.round(u * k));
  for (let s = 0; s < 8; s++) {
    for (let row = 0; row < 2; row++) {
      const x = s * 16 + 8;
      const y = row * 30;
      const skin = skins[s % 4];
      const shirt = shirts[s];
      const lit = shirt.map((u) => Math.min(Math.round(u * 1.25 + 14), 255));
      // Legs: stance differs by person; shoes.
      const wide = s % 3 === 0 ? 1 : 0;
      c.rect(x - 2 - wide, y + 22, 2, 7, trousers[s]);
      c.rect(x + 1 + wide, y + 22, 2, 7, darker(trousers[s], 0.75));
      c.rect(x - 3 - wide, y + 29, 3, 1, OUTLINE);
      c.rect(x + 1 + wide, y + 29, 3, 1, OUTLINE);
      // Body, lit on the right, a jacket hem on some.
      c.rect(x - 3, y + 11, 7, 11, shirt);
      c.rect(x + 3, y + 11, 1, 11, lit);
      c.rect(x - 3, y + 11, 1, 11, darker(shirt, 0.7));
      if (s % 2 === 1) c.rect(x - 3, y + 20, 7, 2, darker(shirt, 0.75));
      if (s === 2 || s === 5) c.rect(x - 1, y + 14, 3, 1, lit);
      // Neck and head; hair or a cap.
      c.rect(x, y + 10, 2, 1, darker(skin, 0.85));
      c.disk(x, y + 7, 3, skin);
      c.px(x - 2, y + 8, darker(skin, 0.8));
      c.px(x - 1, y + 9, darker(skin, 0.8));
      if (s % 4 === 3) {
        c.rect(x - 3, y + 4, 6, 2, shirt);
        c.rect(x + 1, y + 5, 3, 1, darker(shirt, 0.7));
      } else {
        c.rect(x - 2, y + 4, 5, 1, hairs[s]);
        c.rect(x - 3, y + 5, 3, 2, hairs[s]);
        if (s % 4 === 1) c.rect(x - 3, y + 7, 2, 3, hairs[s]);
      }
      if (row === 0) {
        c.line(x - 4, y + 12, x - 5, y + 20, darker(shirt, 0.8));
        c.line(x + 5, y + 12, x + 6, y + 20, shirt);
        c.px(x - 5, y + 21, skin);
        c.px(x + 6, y + 21, skin);
      } else {
        c.line(x - 4, y + 12, x - 6, y + 3, darker(skin, 0.9));
        c.line(x + 4, y + 12, x - 8 + CROWD_HAND_UP[0], y + CROWD_HAND_UP[1], skin);
        c.px(x - 4, y + 12, darker(shirt, 0.8));
        c.px(x + 4, y + 12, shirt);
        c.px(x - 6, y + 2, skin);
        c.px(x - 8 + CROWD_HAND_UP[0], y + CROWD_HAND_UP[1] - 1, skin);
      }
    }
  }
  return c;
}

/** 12 x 16, 4 frames: a generic striped hand flag, waving. */
export function flag() {
  const c = new Canvas(48, 16);
  const stripes = [hex('#ecece4'), hex('#3870b0')];
  const shade = [hex('#bcbcb8'), hex('#285488')];
  for (let f = 0; f < 4; f++) {
    const x = f * 12;
    c.rect(x + FLAG_GRIP[0], 1, 1, FLAG_GRIP[1], OUTLINE);
    for (let i = 0; i < 9; i++) {
      const u = ((i + f * 2) * Math.PI) / 4;
      const wave = Math.round(Math.sin(u));
      const dark = Math.cos(u) < -0.3;
      for (let j = 0; j < 7; j++) {
        const band = j < 2 || j > 4 ? 0 : 1;
        c.px(x + 2 + i, 2 + j + wave, (dark ? shade : stripes)[band]);
      }
    }
  }
  return c;
}

const GLYPHS = {
  S: ['01111', '10000', '10000', '01110', '00001', '00001', '11110'],
  P: ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
  R: ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
  I: ['11111', '00100', '00100', '00100', '00100', '00100', '11111'],
  N: ['10001', '11001', '10101', '10101', '10011', '10001', '10001'],
  T: ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
};

/** 200 x 90: the sprint banner on two lattice masts, with a pixel word and a line of pennants. */
export function gantry() {
  const c = new Canvas(200, 90);
  const steel = hex('#4a4e58');
  const lit = hex('#8a8e98');
  const dark = hex('#2a2c34');
  for (const x of [5, 190]) {
    // A lattice mast on a weighted foot.
    c.rect(x, 4, 1, 84, steel);
    c.rect(x + 4, 4, 1, 84, lit);
    for (let y = 8; y < 86; y += 6) {
      c.line(x, y, x + 4, y + 3, dark);
      c.line(x + 4, y + 3, x, y + 6, dark);
    }
    c.rect(x - 3, 87, 11, 3, dark);
    c.rect(x - 3, 87, 11, 1, steel);
  }
  // The truss over the road.
  c.rect(5, 4, 190, 1, lit);
  c.rect(5, 8, 190, 1, steel);
  for (let x = 6; x < 194; x += 6) {
    c.line(x, 5, x + 3, 7, dark);
    c.line(x + 3, 7, x + 6, 5, dark);
  }
  // The banner, with a white hem and sagging shade under its edge.
  const red = [hex('#8c3424'), hex('#c04e34'), hex('#dc6c48')];
  c.rect(14, 10, 172, 26, red[1]);
  c.rect(14, 10, 172, 2, hex('#ecece4'));
  c.rect(14, 34, 172, 2, hex('#ecece4'));
  c.rect(14, 33, 172, 1, red[0]);
  c.rect(14, 12, 172, 1, red[2]);
  c.rect(14, 10, 3, 26, red[0]);
  c.rect(183, 10, 3, 26, red[2]);
  // Fold shadows in the cloth.
  for (const x of [52, 96, 140]) {
    c.rect(x, 13, 1, 20, red[0]);
    c.rect(x + 1, 13, 1, 20, red[2]);
  }
  const word = 'SPRINT';
  const scale = 2;
  let x = 100 - Math.floor((word.length * 6 * scale - scale) / 2);
  for (const ch of word) {
    GLYPHS[ch].forEach((row, j) => {
      [...row].forEach((bit, i) => {
        if (bit !== '1') return;
        c.rect(x + i * scale + 1, 16 + j * scale + 1, scale, scale, red[0]);
        c.rect(x + i * scale, 16 + j * scale, scale, scale, hex('#f6f6f0'));
      });
    });
    x += 6 * scale;
  }
  // A string of small pennants under the banner.
  const cols = ['#ecece4', '#3870b0', '#c8a644', '#468c6c'].map(hex);
  for (let i = 0; i < 16; i++) {
    const px = 16 + i * 11;
    const y = 38 + Math.round(3 * Math.sin((i / 15) * Math.PI));
    c.px(px, y - 1, dark);
    c.px(px + 5, y - 1, dark);
    for (let j = 0; j < 4; j++) {
      c.rect(px + j, y + j, Math.max(6 - j * 2, 1), 1, cols[i % 4]);
    }
  }
  return c;
}
