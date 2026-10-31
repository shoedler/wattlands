// Workout's indexed world palette and its time-of-day LUT.
//
// A world PNG stores a palette index in R (R = index * 2, G = B = 0, alpha 0 or 255). tod_lut.png is
// 128 x 32: column = index, row = time of day. workout_tod.gdshader recolours at draw time, so a
// plane never needs a second copy for dawn and day, and LUT alpha fades stars and mist exactly.
//
// Index map (128):
//   0-23 sky bands, 24-27 stars and moon, 28-33 cloud, 34-41 far ridge, 42-53 far fields and hedges,
//   54-65 tree greens, 66-73 walls and roofs, 74-75 lit window, 76-79 mist, 80-85 wood, poles, wire,
//   86-95 asphalt, paint, grit, 96-105 verge grass, 106-111 earth, 112-127 reserve.
import { Canvas, hex } from './raster.mjs';

export const LUT_SIZE = 128;
export const LUT_ROWS = 32;

export const SKY = 0;
export const SKY_N = 24;
export const STAR = 24;
export const CLOUD = 28;
export const RIDGE = 34;
export const FIELD = 42;
export const TREE = 54;
export const WALL = 66;
export const ROOF = 70;
export const WINDOW = 74;
export const MIST = 76;
export const WOOD = 80;
export const ASPHALT = 86;
export const PAINT = 92;
export const GRIT = 94;
export const GRASS = 96;
export const EARTH = 106;
export const RESERVE = 112;

/** The pixel a world PNG stores for palette index i. */
export const ix = (i) => [i * 2, 0, 0, 255];

// --- OKLab ---------------------------------------------------------------------------------------

const toLin = (u) => (u <= 0.04045 ? u / 12.92 : ((u + 0.055) / 1.055) ** 2.4);
const toSrgb = (u) => (u <= 0.0031308 ? 12.92 * u : 1.055 * u ** (1 / 2.4) - 0.055);

function oklab([r8, g8, b8]) {
  const r = toLin(r8 / 255);
  const g = toLin(g8 / 255);
  const b = toLin(b8 / 255);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

function fromOklab([L, a, b]) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  const rgb = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
  return rgb.map((u) => Math.round(Math.min(Math.max(toSrgb(Math.max(u, 0)), 0), 1) * 255));
}

/** Colour between two [r, g, b]s in OKLab, snapped to 8 bit. */
export function mix(c0, c1, t) {
  const a = oklab(c0);
  const b = oklab(c1);
  return fromOklab([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]);
}

const ramp = (from, to, n) => Array.from({ length: n }, (_, i) => mix(hex(from), hex(to), n > 1 ? i / (n - 1) : 0));

// --- the morning ---------------------------------------------------------------------------------

// Each key: the colours of the index groups (dark to light unless noted) and the alphas that fade.
const KEYS = [
  {
    p: 0.0, // blue hour
    sky: ['#1b2340', '#6b5a78'],
    star: 1.0,
    window: ['#ffc56a', 1.0],
    mist: ['#8488a8', 1.0],
    cloud: ['#2a2f50', '#5a5a80'],
    ridge: ['#2c3050', '#464a70'],
    field: ['#1f2c3c', '#34485a'],
    tree: ['#141f2c', '#2c4048'],
    wall: ['#3a3c50', '#585a70'],
    roof: ['#26283a', '#3e3e54'],
    wood: ['#1a1a26', '#34344a'],
    asphalt: ['#20222e', '#3c3e4e'],
    paint: ['#6a6c80', '#8c8e9e'],
    grit: ['#2a2c3a', '#4c4e5e'],
    grass: ['#16262c', '#2c4644'],
    earth: ['#2a2430', '#463c48'],
    bank: '#10181f',
    bankHi: '#22303a',
    tint: [0.74, 0.76, 0.92],
  },
  {
    p: 0.1, // first light
    sky: ['#3a3566', '#e8a27a'],
    star: 0.4,
    window: ['#ffc56a', 1.0],
    mist: ['#c2a4b0', 1.0],
    cloud: ['#5a4a78', '#d09aa0'],
    ridge: ['#544a78', '#8a7094'],
    field: ['#2c3c4c', '#50646c'],
    tree: ['#1a2a34', '#3c5458'],
    wall: ['#5a5464', '#8a7c84'],
    roof: ['#3a3444', '#5a4c5c'],
    wood: ['#262430', '#4c4450'],
    asphalt: ['#2c2c3a', '#50505e'],
    paint: ['#88848e', '#b0a8a8'],
    grit: ['#3a3a48', '#646270'],
    grass: ['#22363a', '#40605a'],
    earth: ['#3a3038', '#5c4c50'],
    bank: '#182228',
    bankHi: '#30423f',
    tint: [0.84, 0.8, 0.86],
  },
  {
    p: 0.22, // sunrise
    sky: ['#5c7390', '#f2a14e'],
    star: 0.0,
    window: ['#d09a5a', 0.5],
    mist: ['#f2c49a', 0.7],
    cloud: ['#a07a80', '#ffd2a0'],
    ridge: ['#8a7a88', '#c49a84'],
    field: ['#4a5a44', '#94905a'],
    tree: ['#2a3e30', '#6c7a44'],
    wall: ['#8a6c5c', '#e0b080'],
    roof: ['#54403c', '#8a5e48'],
    wood: ['#38302c', '#6a5444'],
    asphalt: ['#3c3a3e', '#6a6264'],
    paint: ['#b0a490', '#e0cca4'],
    grit: ['#4c484a', '#807670'],
    grass: ['#35502c', '#86923e'],
    earth: ['#54402e', '#86684a'],
    bank: '#26321e',
    bankHi: '#4c5a2c',
    tint: [1.0, 0.92, 0.82],
  },
  {
    p: 0.4, // golden
    sky: ['#6fa3cf', '#f6d9a0'],
    star: 0.0,
    window: ['#5c5a58', 0.0],
    mist: ['#f6e6c8', 0.3],
    cloud: ['#c4b8b0', '#fff4dc'],
    ridge: ['#92a8b8', '#c0c4bc'],
    field: ['#5c7c3e', '#b8b45a'],
    tree: ['#2c4c2c', '#86a044'],
    wall: ['#a08a70', '#f0d8a8'],
    roof: ['#6a4c40', '#a86c4c'],
    wood: ['#44382c', '#80684c'],
    asphalt: ['#44444a', '#747078'],
    paint: ['#c8c0a8', '#f0e8c8'],
    grit: ['#54545a', '#8a8684'],
    grass: ['#3e6a2c', '#a0b444'],
    earth: ['#604a30', '#987850'],
    bank: '#2c421e',
    bankHi: '#5c7a2c',
    tint: [1.0, 1.0, 1.0],
  },
  {
    p: 0.65, // morning
    sky: ['#4f93d6', '#cfe3ea'],
    star: 0.0,
    window: ['#4c5258', 0.0],
    mist: ['#e8f0f0', 0.0],
    cloud: ['#b8c8d8', '#ffffff'],
    ridge: ['#8aa8c8', '#b8cce0'],
    field: ['#4c8444', '#a0bc58'],
    tree: ['#28502e', '#6ca044'],
    wall: ['#9a9488', '#ece6d4'],
    roof: ['#68483e', '#a4644c'],
    wood: ['#40382e', '#786850'],
    asphalt: ['#44464c', '#74767c'],
    paint: ['#cccac0', '#f4f2e8'],
    grit: ['#54565c', '#8a8c8e'],
    grass: ['#37702e', '#8cb844'],
    earth: ['#5c4a34', '#927a58'],
    bank: '#2a4620',
    bankHi: '#507e2e',
    tint: [1.0, 1.0, 1.0],
  },
  {
    p: 1.0, // day
    sky: ['#3f86d6', '#bfe0ee'],
    star: 0.0,
    window: ['#40484e', 0.0],
    mist: ['#e8f4f8', 0.0],
    cloud: ['#c4d4e4', '#ffffff'],
    ridge: ['#86a8d0', '#b4cce4'],
    field: ['#4a8a48', '#9cc05c'],
    tree: ['#285630', '#68a848'],
    wall: ['#9e9a90', '#f2eee0'],
    roof: ['#684a40', '#a4644e'],
    wood: ['#40382e', '#78684e'],
    asphalt: ['#46484e', '#76787e'],
    paint: ['#d0cec6', '#f8f6ee'],
    grit: ['#56585e', '#8c8e90'],
    grass: ['#387632', '#8cbc48'],
    earth: ['#5e4c36', '#947c5a'],
    bank: '#2a4a22',
    bankHi: '#4e8230',
    tint: [1.0, 1.0, 1.0],
  },
];

/** One key's 128 colours: [r, g, b, a], a 0..255. */
function keyColors(k) {
  const out = [];
  const add = (cols, a = 255) => {
    for (const c of cols) out.push([c[0], c[1], c[2], a]);
  };
  add(ramp(k.sky[0], k.sky[1], SKY_N));
  add(ramp('#f4f4ff', '#ffffff', 2).concat(ramp('#e8e6d8', '#f8f4e0', 2)), Math.round(k.star * 255));
  add(ramp(k.cloud[0], k.cloud[1], 6));
  add(ramp(k.ridge[0], k.ridge[1], 8));
  add(ramp(k.field[0], k.field[1], 12));
  add(ramp(k.tree[0], k.tree[1], 12));
  add(ramp(k.wall[0], k.wall[1], 4));
  add(ramp(k.roof[0], k.roof[1], 4));
  // 74 is the pane: it stays opaque and goes dark by day. 75 is its glow, which fades away.
  add(ramp(k.window[0], k.window[0], 1));
  add(ramp(k.window[0], '#fff0c0', 1), Math.round(k.window[1] * 255));
  add(ramp(k.mist[0], k.mist[0], 4), Math.round(k.mist[1] * 255));
  add(ramp(k.wood[0], k.wood[1], 6));
  add(ramp(k.asphalt[0], k.asphalt[1], 6));
  add(ramp(k.paint[0], k.paint[1], 2));
  add(ramp(k.grit[0], k.grit[1], 2));
  add(ramp(k.grass[0], k.grass[1], 10));
  add(ramp(k.earth[0], k.earth[1], 6));
  // The reserve is loud on purpose: a flat rect under the shader shows up at once.
  add(Array.from({ length: LUT_SIZE - RESERVE }, () => [255, 0, 255]));
  return out;
}

function keyPair(p) {
  let i = 0;
  while (i + 2 < KEYS.length && p >= KEYS[i + 1].p) i++;
  const a = KEYS[i];
  const b = KEYS[i + 1];
  return [a, b, Math.min(Math.max((p - a.p) / (b.p - a.p), 0), 1)];
}

/** p (0..1) of LUT row r: the row covers floor(p * 31) = r. */
export const rowP = (r) => r / (LUT_ROWS - 1);

/** The LUT as a Canvas of 128 x 32. */
export function buildLut() {
  const c = new Canvas(LUT_SIZE, LUT_ROWS);
  const colors = KEYS.map(keyColors);
  for (let r = 0; r < LUT_ROWS; r++) {
    const [ka, kb, t] = keyPair(rowP(r));
    const ca = colors[KEYS.indexOf(ka)];
    const cb = colors[KEYS.indexOf(kb)];
    for (let i = 0; i < LUT_SIZE; i++) {
      const rgb = mix(ca[i], cb[i], t);
      c.px(i, r, [rgb[0], rgb[1], rgb[2], Math.round(ca[i][3] + (cb[i][3] - ca[i][3]) * t)]);
    }
  }
  return c;
}

const round3 = (u) => Math.round(u * 1000) / 1000;
const floats = (c) => c.map((u) => round3(u / 255));

// Where the sun stands on the sky plane: behind the hills at blue hour, on the ridge at sunrise.
const SUN_X = [700, 540];
const SUN_Y = [
  [0.0, 345],
  [0.22, 240],
  [0.4, 170],
  [1.0, 70],
];

function sunAt(p) {
  let i = 0;
  while (i + 2 < SUN_Y.length && p >= SUN_Y[i + 1][0]) i++;
  const [p0, y0] = SUN_Y[i];
  const [p1, y1] = SUN_Y[i + 1];
  const y = y0 + ((y1 - y0) * (p - p0)) / (p1 - p0);
  return [Math.round(SUN_X[0] + (SUN_X[1] - SUN_X[0]) * p), Math.round(y)];
}

/** kit.tod: 32 rows of {sky_top, rider_tint, bank, bank_hi, sun, breath}, colours 0..1. */
export function buildTod() {
  const out = [];
  for (let r = 0; r < LUT_ROWS; r++) {
    const p = rowP(r);
    const [a, b, t] = keyPair(p);
    const tint = a.tint.map((u, i) => round3(u + (b.tint[i] - u) * t));
    out.push({
      sky_top: floats(mix(hex(a.sky[0]), hex(b.sky[0]), t)),
      rider_tint: tint,
      bank: floats(mix(hex(a.bank), hex(b.bank), t)),
      bank_hi: floats(mix(hex(a.bankHi), hex(b.bankHi), t)),
      sun: sunAt(p),
      breath: p < 0.3,
    });
  }
  return out;
}

/** A plane's indexed Canvas recoloured by LUT row `row`, for previews and the picker card. */
export function recolour(plane, lut, row) {
  const out = new Canvas(plane.w, plane.h);
  for (let y = 0; y < plane.h; y++) {
    for (let x = 0; x < plane.w; x++) {
      const p = plane.get(x, y);
      if (p[3] === 0) continue;
      const c = lut.get(p[0] >> 1, row);
      if (c[3] > 0) out.px(x, y, c);
    }
  }
  return out;
}
