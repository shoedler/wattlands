// The indexed world planes. Every plane stores palette indices (palette.mjs): sky bands, ridges, fields,
// trees, poles, road, verges. Seamless planes draw on a wrap-x Canvas and build heights from whole wave
// counts, so the first and last columns meet.
import { Canvas, bayer4, mulberry32 } from './raster.mjs';
import * as P from './palette.mjs';

const ix = P.ix;

/** A seamless height function on [0, w): whole wave counts, phases from the seed. Returns 0..1. */
function waves(w, seed, counts) {
  const rnd = mulberry32(seed);
  const parts = counts.map((n, i) => ({ n, phase: rnd() * Math.PI * 2, amp: 1 / (i + 1) }));
  const raw = (x) => parts.reduce((s, q) => s + q.amp * Math.sin((Math.PI * 2 * q.n * x) / w + q.phase), 0);
  let lo = Infinity;
  let hi = -Infinity;
  for (let x = 0; x < w; x++) {
    lo = Math.min(lo, raw(x));
    hi = Math.max(hi, raw(x));
  }
  return (x) => (raw(x) - lo) / Math.max(hi - lo, 1e-9);
}

/** 64 x 720, y -180..540: index 0 at the top to 23 at the horizon, dithered between neighbours. */
export function skyPlane() {
  const c = new Canvas(64, 720);
  const horizon = 520; // y 340 on the stage
  for (let y = 0; y < c.h; y++) {
    const f = (Math.min(y / horizon, 1) * (P.SKY_N - 1)) % 1;
    const i0 = Math.min(Math.floor((Math.min(y / horizon, 1)) * (P.SKY_N - 1)), P.SKY_N - 1);
    for (let x = 0; x < c.w; x++) {
      c.px(x, y, ix(P.SKY + Math.min(i0 + (f > bayer4(x, y) ? 1 : 0), P.SKY_N - 1)));
    }
  }
  return c;
}

/** 480 x 380: scattered stars and a thin moon, fading by LUT alpha. */
export function starsPlane(seed) {
  const c = new Canvas(480, 380, { wrapX: true });
  const rnd = mulberry32(seed ^ 0x51a2);
  for (let i = 0; i < 180; i++) {
    const x = Math.floor(rnd() * c.w);
    const y = Math.floor(rnd() * c.h * (1 - 0.3 * rnd()));
    c.px(x, y, ix(P.STAR + (rnd() < 0.2 ? 1 : 0)));
  }
  c.disk(120, 60, 4, ix(P.STAR + 3));
  c.disk(122, 59, 4, [0, 0, 0, 0]);
  return c;
}

function cloudPlane(w, h, seed, n) {
  const c = new Canvas(w, h, { wrapX: true });
  const rnd = mulberry32(seed);
  for (let k = 0; k < n; k++) {
    const cx = rnd() * w;
    const cy = 16 + rnd() * (h - 40);
    const puffs = 3 + Math.floor(rnd() * 4);
    for (let i = 0; i < puffs; i++) {
      const px = cx + i * (8 + rnd() * 10);
      const py = cy + rnd() * 6 - 3;
      const r = 5 + rnd() * 7;
      c.disk(px, py + 2, r, ix(P.CLOUD + 1));
      c.disk(px, py, r - 1, ix(P.CLOUD + 5));
    }
  }
  return c;
}

export const cloudsHiPlane = (seed) => cloudPlane(960, 140, seed ^ 0x11, 7);
export const cloudsLoPlane = (seed) => cloudPlane(960, 100, seed ^ 0x22, 5);

/** A band of land: a seamless top line, then `bands` indices from the top down. */
function ridgePlane(w, h, seed, counts, minTop, maxTop, base, bands) {
  const c = new Canvas(w, h, { wrapX: true });
  const f = waves(w, seed, counts);
  for (let x = 0; x < w; x++) {
    const top = Math.round(minTop + (maxTop - minTop) * f(x));
    for (let y = top; y < h; y++) {
      const band = Math.min(Math.floor(((y - top) / Math.max(h - top, 1)) * bands), bands - 1);
      // Lighter on the crest, darker toward the foot.
      c.px(x, y, ix(base + bands - 1 - band));
    }
  }
  return c;
}

export function farHillsPlane(seed) {
  const c = ridgePlane(1440, 150, seed ^ 0x33, [2, 5, 9], 20, 90, P.RIDGE, 8);
  // A far church tower on the ridge.
  c.rect(610, 60, 6, 40, ix(P.RIDGE + 7));
  c.polyFill(
    [
      [609, 60],
      [613, 48],
      [617, 60],
    ],
    ix(P.RIDGE + 6),
  );
  return c;
}

export function midHillsPlane(seed) {
  const c = ridgePlane(1280, 150, seed ^ 0x44, [2, 3, 7], 30, 90, P.FIELD, 12);
  const rnd = mulberry32(seed ^ 0x45);
  for (let i = 0; i < 9; i++) {
    const x = Math.floor(rnd() * c.w);
    c.rect(x, 110 + Math.floor(rnd() * 20), 7, 5, ix(P.WALL + 2));
    c.rect(x - 1, 107 + Math.floor(rnd() * 2) + 3, 9, 2, ix(P.ROOF + 1));
  }
  return c;
}

function poplar(c, x, base, h) {
  c.rect(x, base - 6, 2, 6, ix(P.WOOD + 1));
  c.polyFill(
    [
      [x + 1, base - h],
      [x + 5, base - h * 0.4],
      [x + 1, base - 4],
      [x - 4, base - h * 0.4],
    ],
    ix(P.TREE + 3),
  );
  c.line(x + 2, base - h + 3, x + 4, base - h * 0.4, ix(P.TREE + 11));
}

/** A farmhouse with a chimney. Returns the chimney's top centre pixel: where kit.props.smoke rises from. */
function house(c, x, base) {
  c.rect(x + 19, base - 28, 3, 8, ix(P.WALL + 1));
  c.rect(x + 18, base - 29, 5, 1, ix(P.ROOF));
  c.rect(x, base - 16, 26, 16, ix(P.WALL + 2));
  c.polyFill(
    [
      [x - 2, base - 16],
      [x + 13, base - 26],
      [x + 28, base - 16],
    ],
    ix(P.ROOF + 1),
  );
  c.rect(x + 4, base - 11, 3, 4, ix(P.WINDOW));
  c.rect(x + 18, base - 11, 3, 4, ix(P.WINDOW));
  c.rect(x + 3, base - 12, 5, 1, ix(P.WINDOW + 1));
  c.rect(x + 17, base - 12, 5, 1, ix(P.WINDOW + 1));
  return [x + 20, base - 29];
}

/** The plane's Canvas also carries `chimneys`, [[x, y], ...] in strip px, which the bake writes to kit.json. */
export function nearTreesPlane(seed) {
  const c = new Canvas(1600, 150, { wrapX: true });
  const f = waves(c.w, seed ^ 0x55, [3, 8]);
  for (let x = 0; x < c.w; x++) {
    const top = Math.round(118 + 12 * f(x));
    for (let y = top; y < c.h; y++) c.px(x, y, ix(P.TREE + (y - top < 3 ? 6 : 1)));
  }
  const rnd = mulberry32(seed ^ 0x56);
  c.chimneys = [];
  let x = 6;
  while (x < c.w - 40) {
    if (rnd() < 0.12) {
      c.chimneys.push(house(c, x, 128));
      x += 40;
    } else {
      poplar(c, x, 124, 40 + rnd() * 50);
      x += 16 + Math.floor(rnd() * 34);
    }
  }
  // The mist band hanging in the fields; it burns off through LUT alpha.
  for (let y = 136; y < 146; y++) {
    for (let xx = 0; xx < c.w; xx++) {
      if ((xx + y * 3) % 4 !== 0) c.px(xx, y, ix(P.MIST + (y < 141 ? 0 : 1)));
    }
  }
  return c;
}

/** 480 x 130: one pole every 240 px, three wires with a catenary. */
export function polesPlane() {
  const c = new Canvas(480, 130, { wrapX: true });
  const wire = ix(P.WOOD + 2);
  for (const x of [60, 300]) {
    c.rect(x, 10, 2, 120, ix(P.WOOD + 1));
    c.rect(x - 8, 14, 18, 2, ix(P.WOOD + 3));
    for (const dx of [-8, 0, 9]) c.px(x + dx, 13, ix(P.WOOD + 5));
  }
  for (let x = 0; x < 480; x++) {
    const t = ((x + 180) % 240) / 240; // 0 at a pole, 1 at the next
    const sag = 8 * (1 - (2 * t - 1) ** 2);
    for (const h of [13, 16, 19]) c.px(x, h + sag, wire);
  }
  return c;
}

/** 240 x 30, contact row 14 is the middle lane: far kerb, asphalt grit, centre dashes, near edge line. */
export function roadPlane(seed) {
  const c = new Canvas(240, 30, { wrapX: true });
  const rnd = mulberry32(seed ^ 0x77);
  for (let y = 0; y < c.h; y++) for (let x = 0; x < c.w; x++) c.px(x, y, ix(P.ASPHALT + 2));
  c.rect(0, 0, c.w, 2, ix(P.PAINT));
  c.rect(0, 2, c.w, 1, ix(P.ASPHALT));
  c.rect(0, 27, c.w, 1, ix(P.PAINT + 1));
  c.rect(0, 28, c.w, 2, ix(P.EARTH + 1));
  for (let i = 0; i < 420; i++) {
    c.px(Math.floor(rnd() * c.w), 3 + Math.floor(rnd() * 24), ix(rnd() < 0.5 ? P.GRIT : P.GRIT + 1));
  }
  for (let x = 0; x < c.w; x += 40) c.rect(x, 13, 12, 2, ix(P.PAINT + 1));
  return c;
}

function grassTufts(c, frame, seed, density) {
  const rnd = mulberry32(seed);
  for (let i = 0; i < density; i++) {
    const x = Math.floor(rnd() * c.w);
    const y = Math.floor(c.h * 0.3 + rnd() * c.h * 0.65);
    const h = 2 + Math.floor(rnd() * 4);
    // The wind leans a tuft by one pixel, a different phase per tuft.
    const lean = (frame + Math.floor(rnd() * 4)) % 4 < 2 ? 0 : 1;
    c.line(x, y, x + lean, y - h, ix(P.GRASS + 3 + Math.floor(rnd() * 6)));
  }
}

/** 240 x 26: fence posts plus grass, wind frame f of 4. */
export function vergeFarPlane(seed, f) {
  const c = new Canvas(240, 26, { wrapX: true });
  for (let y = 8; y < c.h; y++) for (let x = 0; x < c.w; x++) c.px(x, y, ix(P.GRASS + 2));
  c.rect(0, 12, c.w, 1, ix(P.WOOD + 1));
  c.rect(0, 16, c.w, 1, ix(P.WOOD + 1));
  for (let x = 0; x < c.w; x += 48) c.rect(x, 8, 2, 14, ix(P.WOOD + 2));
  grassTufts(c, f, seed ^ 0x88, 60);
  return c;
}

/** 240 x 16: grass and wildflowers, wind frame f of 4. */
export function vergeNearPlane(seed, f) {
  const c = new Canvas(240, 16, { wrapX: true });
  for (let y = 0; y < c.h; y++) for (let x = 0; x < c.w; x++) c.px(x, y, ix(P.GRASS + 4));
  grassTufts(c, f, seed ^ 0x99, 70);
  const rnd = mulberry32(seed ^ 0x9a);
  for (let i = 0; i < 12; i++) c.px(Math.floor(rnd() * c.w), 2 + Math.floor(rnd() * 12), ix(P.WALL + 3));
  return c;
}

/** 960 x 34: soft grass clumps and stones in the near foreground, wind frame f of 2. */
export function foregroundPlane(seed, f) {
  const c = new Canvas(960, 34, { wrapX: true });
  const rnd = mulberry32(seed ^ 0xaa);
  for (let i = 0; i < 40; i++) {
    const x = Math.floor(rnd() * c.w);
    const w = 10 + Math.floor(rnd() * 30);
    const h = 4 + Math.floor(rnd() * 8);
    c.polyFill(
      [
        [x, c.h],
        [x + w * 0.5 + f, c.h - h],
        [x + w, c.h],
      ],
      ix(P.GRASS + 1 + Math.floor(rnd() * 3)),
    );
    if (rnd() < 0.2) c.rect(x + 4, c.h - 3, 4, 3, ix(P.EARTH + 3));
  }
  return c;
}
