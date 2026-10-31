// Workout's indexed world palette and its time-of-day LUT.
//
// A world PNG stores a palette index in R (R = index * 2, G = B = 0, alpha 0 or 255). tod_lut.png is
// 128 x 32: column = index, row = time of day. workout_tod.gdshader recolours at draw time, so a
// plane never needs a second copy for dawn and day, and LUT alpha fades stars and mist exactly.
//
// Index map (128):
//   0-23 sky bands
//   24-27 stars (dim, mid, bright) and the moon; alpha falls by sunrise
//   28-33 cloud, shadow to lit
//   34-37 far ridge, 38-41 nearer ridge
//   42-44 hedge, 45-48 pasture, 49-51 crop, 52-53 plough
//   54-58 poplar shades, 59 its lit rim; 60-64 round tree shades, 65 its rim
//   66-69 walls, 70-73 roofs
//   74 window pane: lit at dawn, dark by day, always opaque
//   75 the glow on the wall round a pane: warm at dawn, plain wall by day, always opaque (no holes)
//   76-77 hanging mist on empty pixels, alpha falls; 78-79 ground mist on land, opaque, turns into grass
//   80-83 wood, 84 wire, 85 insulator
//   86-91 asphalt, 92-93 paint, 94-95 grit
//   96-105 grass, 106-111 earth, 112-127 reserve
import { Canvas, hex } from './raster.mjs';

export const LUT_SIZE = 128;
export const LUT_ROWS = 32;

export const SKY = 0;
export const SKY_N = 24;
export const STAR = 24;
export const CLOUD = 28;
export const RIDGE = 34;
export const RIDGE_NEAR = 38;
export const FIELD = 42;
export const HEDGE = 42;
export const PASTURE = 45;
export const CROP = 49;
export const PLOUGH = 52;
export const TREE = 54;
export const POPLAR = 54;
export const OAK = 60;
export const WALL = 66;
export const ROOF = 70;
export const WINDOW = 74;
export const GLOW = 75;
export const MIST = 76;
export const MIST_GROUND = 78;
export const WOOD = 80;
export const WIRE = 84;
export const INSULATOR = 85;
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

/** n colours through two or more stops, evenly spaced in OKLab. */
function ramp(stops, n) {
  const cs = stops.map(hex);
  return Array.from({ length: n }, (_, i) => {
    const u = n > 1 ? (i / (n - 1)) * (cs.length - 1) : 0;
    const k = Math.min(Math.floor(u), cs.length - 2);
    return mix(cs[k], cs[k + 1], u - k);
  });
}

// --- the morning ---------------------------------------------------------------------------------

// Each key: the colours of the index groups, dark to light. Shadows lean blue and violet, lights lean
// warm, and far planes sit close to the sky's own horizon colour, so depth comes from the palette.
const KEYS = [
  {
    p: 0.0, // blue hour
    sky: ['#1b2340', '#3b3a66', '#6b5a78'],
    star: 1.0,
    pane: '#ffc56a',
    glow: '#8a7458',
    mist: ['#4c5078', 1.0],
    mistGround: ['#3c4860', '#4c5670'],
    cloud: ['#232850', '#5c5a82'],
    ridgeFar: ['#45446e', '#5c5480'],
    ridgeNear: ['#2e3158', '#454668'],
    hedge: ['#16222f', '#233240'],
    pasture: ['#1c2a3a', '#36485a'],
    crop: ['#343c4c', '#525664'],
    plough: ['#252636', '#363546'],
    poplar: ['#0d1622', '#22343e', '#3a5458'],
    oak: ['#101a26', '#283c42', '#42585a'],
    wall: ['#353850', '#5a5c74'],
    roof: ['#20223a', '#3c3c56'],
    wood: ['#191a26', '#36364c'],
    wire: '#2c2e46',
    insulator: '#7c7e94',
    asphalt: ['#1c1e2a', '#363848'],
    paint: ['#62647a', '#8c8e9e'],
    grit: ['#282a38', '#4c4e5e'],
    grass: ['#101e26', '#1f3338', '#385252'],
    earth: ['#262230', '#463c48'],
    bank: '#101e26',
    bankHi: '#1f3338',
    tint: [0.74, 0.76, 0.92],
  },
  {
    p: 0.1, // first light
    sky: ['#3a3566', '#8a5f86', '#e8a27a'],
    star: 0.4,
    pane: '#ffc56a',
    glow: '#b08a70',
    mist: ['#8e7c9c', 1.0],
    mistGround: ['#7c7486', '#94858f'],
    cloud: ['#54467a', '#e0a4a0'],
    ridgeFar: ['#7a6490', '#a47f9c'],
    ridgeNear: ['#4e4874', '#6e5c84'],
    hedge: ['#1f2d38', '#34464a'],
    pasture: ['#2c3c48', '#50645f'],
    crop: ['#55585e', '#7c7868'],
    plough: ['#34303c', '#4c4448'],
    poplar: ['#121e2a', '#2c4248', '#557066'],
    oak: ['#16222c', '#344c4c', '#5e7468'],
    wall: ['#56505f', '#96808a'],
    roof: ['#34303f', '#5a4c5c'],
    wood: ['#262430', '#4c4450'],
    wire: '#4a4458',
    insulator: '#a8a0a8',
    asphalt: ['#282835', '#4c4c5a'],
    paint: ['#88848e', '#b0a8a8'],
    grit: ['#363644', '#605e6c'],
    grass: ['#182a2e', '#2c4a46', '#587a62'],
    earth: ['#3a3038', '#5c4c50'],
    bank: '#182a2e',
    bankHi: '#2c4a46',
    tint: [0.84, 0.8, 0.86],
  },
  {
    p: 0.22, // sunrise
    sky: ['#5c7390', '#d09a8a', '#f2a14e'],
    star: 0.0,
    pane: '#c89a62',
    glow: '#b88a68',
    mist: ['#c4a08e', 0.7],
    mistGround: ['#8c8a58', '#a89a68'],
    cloud: ['#a07a80', '#ffd8a8'],
    ridgeFar: ['#a88a90', '#d0a48c'],
    ridgeNear: ['#7a6f80', '#9c8484'],
    hedge: ['#34442e', '#50603a'],
    pasture: ['#4a5f3c', '#8c9450'],
    crop: ['#a08450', '#d0ae64'],
    plough: ['#54403a', '#7a5c48'],
    poplar: ['#1c2e28', '#3f5a34', '#b8a048'],
    oak: ['#22342a', '#4c6638', '#cca84c'],
    wall: ['#7c6258', '#f0c08c'],
    roof: ['#503c3c', '#9c6448'],
    wood: ['#38302c', '#7a5c44'],
    wire: '#74645e',
    insulator: '#e0c8a8',
    asphalt: ['#38363c', '#66605f'],
    paint: ['#b0a490', '#e8d0a4'],
    grit: ['#4c484a', '#8a7e72'],
    grass: ['#243a20', '#46652c', '#a09c40'],
    earth: ['#54402e', '#8c6a4a'],
    bank: '#243a20',
    bankHi: '#46652c',
    tint: [1.0, 0.92, 0.82],
  },
  {
    p: 0.4, // golden
    sky: ['#6fa3cf', '#c8cfc0', '#f6d9a0'],
    star: 0.0,
    pane: '#4c4c50',
    glow: '#c8b088',
    mist: ['#e4d6bc', 0.3],
    mistGround: ['#54762f', '#7c9a44'],
    cloud: ['#c4b8b0', '#fff4dc'],
    ridgeFar: ['#a0b4c4', '#c4cac4'],
    ridgeNear: ['#86a0a8', '#a4b4ac'],
    hedge: ['#3c5a30', '#5a7a3c'],
    pasture: ['#5c7c3e', '#a0b050'],
    crop: ['#a89a4c', '#d4c674'],
    plough: ['#604a34', '#8c6e4c'],
    poplar: ['#21402a', '#3f6a30', '#a8b848'],
    oak: ['#26462a', '#4e7a34', '#b8c44c'],
    wall: ['#8c7860', '#f4dcac'],
    roof: ['#64483e', '#b0704c'],
    wood: ['#44382c', '#80684c'],
    wire: '#7c7a78',
    insulator: '#f0e8d0',
    asphalt: ['#3e3e46', '#6e6c72'],
    paint: ['#c8c0a8', '#f4ecc8'],
    grit: ['#50505a', '#8a8684'],
    grass: ['#2a4a20', '#4e7a2c', '#b0bc48'],
    earth: ['#604a30', '#987850'],
    bank: '#2a4a20',
    bankHi: '#4e7a2c',
    tint: [1.0, 1.0, 1.0],
  },
  {
    p: 0.65, // morning
    sky: ['#4f93d6', '#94c0e0', '#cfe3ea'],
    star: 0.0,
    pane: '#3c444c',
    glow: '#c4bcac',
    mist: ['#e8f0f0', 0.0],
    mistGround: ['#3f7a30', '#5a9a38'],
    cloud: ['#a8bcd4', '#ffffff'],
    ridgeFar: ['#8fb0d0', '#b8d0e4'],
    ridgeNear: ['#6e98b4', '#94b8c8'],
    hedge: ['#356434', '#508044'],
    pasture: ['#4c8444', '#94bc58'],
    crop: ['#a4ac50', '#d0d47c'],
    plough: ['#5c4a34', '#866c4e'],
    poplar: ['#1c4428', '#38702e', '#86b040'],
    oak: ['#204a2a', '#447c30', '#98bc48'],
    wall: ['#8c887c', '#f0ead8'],
    roof: ['#60443c', '#a4644c'],
    wood: ['#40382e', '#786850'],
    wire: '#7a8088',
    insulator: '#eef0e8',
    asphalt: ['#40424a', '#70727a'],
    paint: ['#cccac0', '#f6f4ea'],
    grit: ['#50525a', '#8a8c8e'],
    grass: ['#27502a', '#3f7a2c', '#94bc44'],
    earth: ['#5c4a34', '#927a58'],
    bank: '#27502a',
    bankHi: '#3f7a2c',
    tint: [1.0, 1.0, 1.0],
  },
  {
    p: 1.0, // day
    sky: ['#3f86d6', '#84b8e4', '#bfe0ee'],
    star: 0.0,
    pane: '#323a42',
    glow: '#c8c4b4',
    mist: ['#e8f4f8', 0.0],
    mistGround: ['#408232', '#609f3c'],
    cloud: ['#b4c8dc', '#ffffff'],
    ridgeFar: ['#8ab0da', '#b4d0e8'],
    ridgeNear: ['#6a9cc0', '#90bcd0'],
    hedge: ['#386c3a', '#548a48'],
    pasture: ['#4a8a48', '#98c45c'],
    crop: ['#a4b054', '#d0d880'],
    plough: ['#5e4c36', '#887050'],
    poplar: ['#1c4a2c', '#387830', '#84b844'],
    oak: ['#205030', '#448434', '#98c44c'],
    wall: ['#8e8c82', '#f4f0e2'],
    roof: ['#624640', '#a4644e'],
    wood: ['#40382e', '#78684e'],
    wire: '#7c848e',
    insulator: '#f0f2ea',
    asphalt: ['#42444c', '#72747c'],
    paint: ['#d0cec6', '#f8f6ee'],
    grit: ['#52545c', '#8c8e90'],
    grass: ['#285430', '#408032', '#90c048'],
    earth: ['#5e4c36', '#947c5a'],
    bank: '#285430',
    bankHi: '#408032',
    tint: [1.0, 1.0, 1.0],
  },
];

/** One key's 128 colours: [r, g, b, a], a 0..255. */
function keyColors(k) {
  const out = [];
  const add = (cols, a = 255) => {
    for (const c of cols) out.push([c[0], c[1], c[2], a]);
  };
  add(ramp(k.sky, SKY_N));
  const starAlpha = Math.round(k.star * 255);
  add(['#8a8cb0', '#c0c4dc', '#f4f4ff', '#f8f4e0'].map(hex), starAlpha);
  add(ramp(k.cloud, 6));
  add(ramp(k.ridgeFar, 4));
  add(ramp(k.ridgeNear, 4));
  add(ramp(k.hedge, 3));
  add(ramp(k.pasture, 4));
  add(ramp(k.crop, 3));
  add(ramp(k.plough, 2));
  // Five shades through the middle stop, then the lit rim on its own.
  add(ramp(k.poplar.slice(0, 2), 5));
  add([hex(k.poplar[2])]);
  add(ramp(k.oak.slice(0, 2), 5));
  add([hex(k.oak[2])]);
  add(ramp(k.wall, 4));
  add(ramp(k.roof, 4));
  add([hex(k.pane)]);
  add([hex(k.glow)]);
  add([hex(k.mist[0]), mix(hex(k.mist[0]), [255, 255, 255], 0.2)], Math.round(k.mist[1] * 255));
  add(k.mistGround.map(hex));
  add(ramp(k.wood, 4));
  add([hex(k.wire)]);
  add([hex(k.insulator)]);
  add(ramp(k.asphalt, 6));
  add(ramp(k.paint, 2));
  add(ramp(k.grit, 2));
  add(ramp(k.grass, 10));
  add(ramp(k.earth, 6));
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

// Where the sun stands on the sky plane: behind the hills at blue hour, on the ridge at sunrise. Late in the
// day its halo still clears the timeline plate, whose bottom edge is at y 72.
const SUN_X = [700, 540];
const SUN_Y = [
  [0.0, 345],
  [0.22, 240],
  [0.4, 170],
  [1.0, 106],
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
