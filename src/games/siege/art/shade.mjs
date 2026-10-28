// Materials. Each picks a base colour from the world position (procedural texture), then the
// light level picks one of a few discrete tones with 4 x 4 ordered dither: the pixel palette.
// shade() returns [r, g, b], [r, g, b, emissive] or null (discard).
import { hex, cmix, cdark, clight, clamp } from './v3.mjs';
import * as W from './world.mjs';

let id = 0;
export const M = {};
for (const name of [
  'NONE', 'TERRAIN', 'WATER', 'WALL', 'WALLTOP', 'PAVE', 'ROOF', 'WOOD', 'WOOD_DARK', 'WOOD_LIGHT',
  'BRONZE', 'IRON', 'TAR', 'GOLD', 'BANNER', 'LINEN', 'CAVE', 'MINE_DIRT', 'HIDE', 'ROCK',
  'ACC0', 'ACC1', 'ACC2', 'ACC3', 'LIT0', 'LIT1', 'LIT2', 'LIT3', 'FIRE', 'STONE_DARK', 'SHAFT',
  'MARBLE', 'ROPE', 'GATE', 'TAR_FALL', 'PLASTER', 'CLIFF',
]) M[name] = id++;

const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const LEVELS = 7;
const DITHER = 0.9;

export const C = {
  SAND_A: hex('#d6ad6c'), SAND_B: hex('#c99c5c'), SAND_WET: hex('#a88b5e'), ROAD: hex('#e2c792'),
  ROCK_A: hex('#958b82'), ROCK_B: hex('#6f665f'), GOLD: hex('#f2c14a'), GOLD_D: hex('#c79a3a'), GLINT: hex('#fff0b0'),
  WATER_SH: hex('#5ccfc2'), WATER_DP: hex('#1e8a98'), FOAM: hex('#d9f3e6'),
  WALL: hex('#c4b8a2'), WALL_B: hex('#b0a48e'), WALL_HI: hex('#d3c8b2'), WALLTOP: hex('#b3a68f'), PAVE: hex('#cbb995'),
  ROOF: hex('#b4513a'), ROOF_L: hex('#cf7553'),
  WOOD: hex('#80583a'), WOOD_DK: hex('#5a3d27'), WOOD_LT: hex('#a2774b'), SHAFT: hex('#77654f'),
  BRONZE: hex('#c0904a'), PATINA: hex('#5f8f7b'), IRON: hex('#4d4c52'),
  BANNER: hex('#8c2f2c'), FRINGE: hex('#d8b25a'), LINEN: hex('#e8dfc8'), HIDE: hex('#93704c'),
  MARBLE: hex('#e8e2d4'), ROPE: hex('#b59a6a'), GATE: hex('#4a3322'), PLASTER: hex('#dcccae'),
};
// The slot colours (Okabe-Ito, as Wl.SLOT_COLORS): red, blue, yellow, green.
export const SLOT = [hex('#D55E00'), hex('#0072B2'), hex('#F0E442'), hex('#009E73')];

export const ditherT = (px, py) => (BAYER4[(py & 3) * 4 + (px & 3)] + 0.5) / 16;

// The tone of base at q (0 deep shadow, about 0.62 the base itself, 1 highlight).
export function tone(base, q) {
  if (q < 0.62) {
    const sh = [base[0] * 0.4 + 0.035, base[1] * 0.34 + 0.03, base[2] * 0.42 + 0.075];
    return cmix(sh, base, q / 0.62);
  }
  const hi = [Math.min(base[0] * 1.16 + 0.07, 1), Math.min(base[1] * 1.12 + 0.055, 1), Math.min(base[2] * 1.04 + 0.03, 1)];
  return cmix(base, hi, (q - 0.62) / 0.38);
}

export function ramp(base, light, px, py) {
  const q = clamp(Math.floor(light * LEVELS + (ditherT(px, py) - 0.5) * DITHER), 0, LEVELS) / LEVELS;
  return tone(base, q);
}

const fpm = (a, b) => ((a % b) + b) % b;

export function shade(mat, p, n, uv, light, sh, px, py) {
  switch (mat) {
    case M.TERRAIN: {
      const c = ramp(terrain(p, n), light, px, py);
      return W.vein(p) > 0.62 && p.z > 1 ? [c[0], c[1], c[2], 0.22] : c;
    }
    case M.ROCK: return ramp(rock(p, n), light, px, py);
    case M.CLIFF: {
      const c = cliff(p, n, uv);
      const r = ramp(c, light, px, py);
      return c === C.GOLD || c === C.GLINT ? [r[0], r[1], r[2], 0.45] : r;
    }
    case M.WATER: return water(p, sh, px, py);
    case M.WALL: return ramp(wall(p, n), light * (0.82 + 0.18 * clamp(p.z / 2.5, 0, 1)), px, py);
    case M.WALLTOP: return ramp(flags(p, C.WALLTOP, 1.5), light, px, py);
    case M.PAVE: return ramp(flags(p, C.PAVE, 2), light, px, py);
    case M.PLASTER: return ramp(C.PLASTER, light, px, py);
    case M.ROOF: {
      let c = fpm(Math.floor(uv.x / 0.6) + Math.floor(uv.y / 0.75), 2) < 1 ? C.ROOF : cmix(C.ROOF_L, C.ROOF, 0.5);
      if (fpm(uv.y, 0.75) < 0.22) c = cdark(c, 0.25);
      return ramp(c, light, px, py);
    }
    case M.WOOD: case M.WOOD_DARK: case M.WOOD_LIGHT: case M.SHAFT: {
      let b = mat === M.WOOD_DARK ? C.WOOD_DK : mat === M.WOOD_LIGHT ? C.WOOD_LT : mat === M.SHAFT ? C.SHAFT : C.WOOD;
      const g = W.hash2(Math.floor(uv.y / 0.5), Math.floor(uv.x / 1.7));
      b = cmix(b, cdark(b, 0.2), g * 0.6);
      if (fpm(uv.y, 0.5) < 0.12) b = cdark(b, 0.25);
      return ramp(b, light, px, py);
    }
    case M.BRONZE: {
      const c = W.vnoise(p.x * 1.7 + p.z, p.y * 1.7 - p.z) > 0.72 ? C.PATINA : C.BRONZE;
      return ramp(c, light * 1.05, px, py);
    }
    case M.IRON: return ramp(C.IRON, light, px, py);
    case M.TAR: case M.TAR_FALL: return tar(p, uv, mat === M.TAR_FALL, sh, px, py);
    case M.GOLD: {
      const c = W.hash3(Math.floor(p.x * 4), Math.floor(p.y * 4), Math.floor(p.z * 4)) > 0.9 ? hex('#fff2b8') : C.GOLD;
      return ramp(c, Math.max(light, 0.7), px, py);
    }
    case M.BANNER: {
      const c = uv.y > 3.9 || uv.x < 0.15 || uv.x > 1.85 ? C.FRINGE : C.BANNER;
      return ramp(c, light, px, py);
    }
    case M.LINEN: return ramp(C.LINEN, light, px, py);
    case M.HIDE: return ramp(cmix(C.HIDE, cdark(C.HIDE, 0.25), W.vnoise(p.x * 2 + p.z * 2, p.y * 2)), light, px, py);
    case M.CAVE: return hex('#1b1311');
    case M.MINE_DIRT: return ramp(cmix(hex('#7a6248'), hex('#5f4a37'), W.hash2(Math.floor(p.x * 3), Math.floor(p.y * 3))), light, px, py);
    case M.ACC0: case M.ACC1: case M.ACC2: case M.ACC3:
      return ramp(cmix(SLOT[mat - M.ACC0], C.WOOD_DK, 0.25), light, px, py);
    case M.LIT0: case M.LIT1: case M.LIT2: case M.LIT3: {
      let c = SLOT[mat - M.LIT0];
      if (fpm(uv.x * 1.5, 1) < 0.35) c = clight(c, 0.35);
      const r = ramp(c, Math.max(light, 0.62) + 0.1, px, py);
      return [r[0], r[1], r[2], 0.18];
    }
    case M.FIRE: return W.hash2(px, py) > 0.4 ? [1, 0.81, 0.35, 0.8] : [1, 0.54, 0.16, 0.8];
    case M.STONE_DARK: return ramp(hex('#3a302a'), light, px, py);
    case M.MARBLE: return ramp(C.MARBLE, light, px, py);
    case M.ROPE: return ramp(C.ROPE, light, px, py);
    case M.GATE: {
      let c = C.GATE;
      if (fpm(uv.x, 1) < 0.14) c = cdark(c, 0.35);
      if (fpm(uv.y + 0.5, 1.8) < 0.3) c = C.IRON;
      return ramp(c, light, px, py);
    }
    default: return [1, 0, 1];
  }
}

function terrain(p, n) {
  const road = W.roadAt(p.x, p.y);
  const big = W.vnoise(p.x * 0.04, p.y * 0.04);
  let sand = cmix(C.SAND_A, C.SAND_B, clamp(big * 1.6 - 0.4, 0, 1));
  const fine = W.hash2(Math.floor(p.x * 4), Math.floor(p.y * 4));
  if (fine > 0.94) sand = cdark(sand, 0.12);
  else if (fine < 0.05) sand = clight(sand, 0.08);
  if (p.z < -0.4) sand = cmix(sand, C.SAND_WET, clamp((-0.4 - p.z) / 1, 0, 1));
  let rockiness = clamp((0.86 - n.z) / 0.18, 0, 1);
  if (p.z > 2) rockiness = Math.max(rockiness, clamp((p.z - 2) / 3, 0, 1) * (0.4 + 0.6 * (n.z < 0.97 ? 1 : 0)));
  let c = sand;
  let isSand = true;
  if (road > 0) {
    let r = C.ROAD;
    if (W.hash2(Math.floor(p.x * 3), Math.floor(p.y * 3)) > 0.9) r = cdark(r, 0.08);
    if (road + (ditherT(Math.floor(p.x * 4), Math.floor(p.y * 4)) - 0.5) * 0.6 > 0.5) {
      c = r;
      isSand = false;
    }
  }
  if (rockiness > 0 && rockiness + (ditherT(Math.floor(p.x * 4 + p.z * 3), Math.floor(p.y * 4)) - 0.5) * 0.5 > 0.5) {
    c = rock(p, n);
    isSand = false;
  }
  if (isSand && n.z > 0.95 && p.z > -0.3) {
    if (W.hash2(Math.floor(p.x * 1.5), Math.floor(p.y * 1.5)) > 0.985 && W.vnoise(p.x * 0.08, p.y * 0.08) > 0.55) c = hex('#7d7a3c');
  }
  return c;
}

function rock(p, n = { x: 0, y: 0, z: 1 }) {
  const patch = W.vnoise(p.x * 0.06 + p.z * 0.05, p.y * 0.06);
  let c = cmix(C.ROCK_A, C.ROCK_B, clamp(patch * 1.5 - 0.25, 0, 1));
  if (n.z > 0.82) c = cmix(c, C.SAND_B, 0.5);
  if (W.hash3(Math.floor(p.x * 2), Math.floor(p.y * 2), Math.floor(p.z * 2)) > 0.95) c = cdark(c, 0.18);
  return c;
}

// The mountain's rock columns: sandy tops, faces with a dark ledge line at every step, column
// tints, cracks, and gold seams in the cliff over the mine.
function cliff(p, n, uv) {
  const col = W.hash2(Math.floor(p.x / 2 + 0.001 * n.x), Math.floor(p.y / 2 + 0.001 * n.y));
  if (n.z > 0.5) {
    let c = cmix(C.SAND_B, C.ROCK_A, 0.25 + col * 0.2);
    if (W.hash2(Math.floor(p.x * 4), Math.floor(p.y * 4)) > 0.9) c = cdark(c, 0.15);
    return c;
  }
  let c = cmix(C.ROCK_A, C.ROCK_B, clamp(col * 0.8 + W.vnoise(p.z * 0.5, p.x * 0.1 + p.y * 0.1) * 0.5 - 0.2, 0, 1));
  const step = ((p.z % 2.5) + 2.5) % 2.5;
  if (step > 2.3) c = cdark(c, 0.3);
  else if (((p.z % 0.8) + 0.8) % 0.8 < 0.12) c = cdark(c, 0.08);
  if (W.hash3(Math.floor(p.x * 3), Math.floor(p.y * 3), Math.floor(p.z * 1.2)) > 0.93) c = cdark(c, 0.22);
  const v = W.vein(p);
  if (v > 0.3) {
    c = v > 0.6 ? C.GOLD : C.GOLD_D;
    if (W.hash3(Math.floor(p.x * 4), Math.floor(p.y * 4), Math.floor(p.z * 4)) > 0.82) c = C.GLINT;
  }
  return c;
}

function wall(p, n) {
  const u = Math.abs(n.y) > Math.abs(n.x) ? p.x : p.y;
  const row = Math.floor(p.z / 0.75);
  const off = row & 1 ? 0.75 : 0;
  const colx = Math.floor((u + off) / 1.5);
  const g = W.hash2(colx * 7 + Math.round(n.x * 3), row * 13 + Math.round(n.y * 5));
  let c = cmix(C.WALL, C.WALL_B, g * 0.7);
  if (g > 0.93) c = C.WALL_HI;
  if (fpm(p.z, 0.75) < 0.22 || fpm(u + off, 1.5) < 0.2) c = cdark(c, 0.16);
  return c;
}

function flags(p, base, size) {
  const sx = Math.floor(p.x / size);
  const yy = p.y + sx * size * 0.5;
  const g = W.hash2(sx, Math.floor(yy / size));
  let c = cmix(base, cdark(base, 0.12), g);
  if (fpm(p.x, size) < 0.22 || fpm(yy, size) < 0.22) c = cdark(c, 0.14);
  return c;
}

function water(p, sh, px, py) {
  const depth = W.WATER_Z - W.height(p.x, p.y);
  let c = cmix(C.WATER_SH, C.WATER_DP, clamp(depth / 1.5, 0, 1));
  const rip = Math.sin(p.x * 1.1 + p.y * 0.6 + W.vnoise(p.x * 0.3, p.y * 0.3) * 6);
  if (rip > 0.93) c = clight(c, 0.22);
  else if (rip < -0.96) c = cdark(c, 0.08);
  if (depth < 0.22) c = ditherT(px, py) > 0.3 ? C.FOAM : clight(c, 0.3);
  if (sh < 0.5) c = [c[0] * 0.62, c[1] * 0.72, c[2] * 0.78];
  else if (W.hash2(px * 3, py * 7) > 0.995) c = hex('#f4fff8');
  return c;
}

function tar(p, uv, falling, sh, px, py) {
  let c = hex('#18120f');
  if (falling) {
    // ribbons running down the curtain (the gaps show the gate), a wet sheen catching the sun
    const streak = W.vnoise(uv.x * 2.6, uv.y * 0.22);
    const gap = W.vnoise(uv.x * 3.1 + 7, uv.y * 0.1);
    if (gap < 0.16 && uv.y < 8.8) return null;
    if (streak > 0.62) c = hex('#3b2c22');
    if (streak > 0.74) c = hex('#6e5a48');
    if (streak > 0.84) c = hex('#b9a58a');
  } else {
    const g = W.vnoise(p.x * 0.8, p.y * 1.6);
    if (g > 0.62) c = hex('#2f241d');
    if (g > 0.78) c = hex('#5a6670');
    if (W.hash2(px * 5, py * 3) > 0.975) c = hex('#c9d6dc');
  }
  if (sh < 0.5) c = cdark(c, 0.25);
  return c;
}
