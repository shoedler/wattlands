// Materials. Each picks a base colour from the world position (procedural texture), then the
// light level picks one of a few discrete tones with 4 x 4 ordered dither: the pixel palette.
// shade() returns [r, g, b], [r, g, b, emissive] or null (discard).
//
// Palette (art critic round 1): big surfaces desaturated and cooler, travertine walls with opus
// mixtum brick courses, low-chroma terracotta and oxblood, a dark green-grey moat, rock about
// a quarter darker than the fort. The rider colours stay the only saturated hues.
import { hex, cmix, cdark, clight, clamp } from './v3.mjs';
import * as W from './world.mjs';

let id = 0;
export const M = {};
for (const name of [
  'NONE', 'TERRAIN', 'WATER', 'WALL', 'WALLTOP', 'PAVE', 'ROOF', 'WOOD', 'WOOD_DARK', 'WOOD_LIGHT',
  'BRONZE', 'IRON', 'TAR', 'GOLD', 'BANNER', 'LINEN', 'CAVE', 'MINE_DIRT', 'HIDE', 'ROCK',
  'ACC0', 'ACC1', 'ACC2', 'ACC3', 'LIT0', 'LIT1', 'LIT2', 'LIT3', 'FIRE', 'STONE_DARK', 'SHAFT',
  'MARBLE', 'ROPE', 'GATE', 'TAR_FALL', 'PLASTER', 'CLIFF', 'ROUNDWALL', 'MERLON', 'ARCH_GATE',
  'ARCH_BRIDGE', 'TEMPLE', 'SCUTUM', 'PLUM', 'TENT', 'ORE', 'GLOWCAVE', 'BRICK', 'QUARRY', 'MUDBRICK',
  'ARCH_AQ', 'BASALT',
]) M[name] = id++;

// Materials whose pixels keep their saturation through the grade (the riders' colours).
export const KEEP = new Set([M.ACC0, M.ACC1, M.ACC2, M.ACC3, M.LIT0, M.LIT1, M.LIT2, M.LIT3]);

const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const LEVELS = 7;
const DITHER = 0.9;

export const C = {
  SAND: hex('#c9a677'), SAND_L: hex('#d9c098'), GRAVEL: hex('#a8977c'), MUD: hex('#6e5a44'),
  DUNE: hex('#a88a60'), WADI: hex('#b39572'), SCREE: hex('#8c857a'), SHOULDER: hex('#cdb48c'),
  ROAD: hex('#9a8363'), RUT: hex('#7a664b'), VIA: hex('#ada391'), KERB: hex('#8a8272'),
  ROCK_A: hex('#8a7f72'), ROCK_B: hex('#6a6058'), ROCK_D: hex('#4e4650'), CLEFT: hex('#3a3440'), LEDGE: hex('#9e8c70'),
  HOST: hex('#6e5a40'), NUGGET: hex('#c8a660'),
  MUDB: hex('#b8a07c'), MUDR: hex('#a08866'),
  GOLD: hex('#c99a3a'), ORE: hex('#b8892e'), GLINT: hex('#f3e2b0'),
  WATER_SH: hex('#3f7f79'), WATER_MD: hex('#2d5f5e'), WATER_DP: hex('#1f4248'), WGLINT: hex('#a6cfc4'),
  WALL: hex('#bfb199'), WALL_B: hex('#b3a58c'), MORTAR: hex('#8c8170'), WALLTOP: hex('#b3a68f'), CAP: hex('#e8e0cf'),
  BRICK: hex('#8e4e3c'), BRICK_D: hex('#7a4232'),
  PAVE: hex('#a39985'), PAVE_B: hex('#8f8572'), JOINT: hex('#7a705f'),
  ROOF: hex('#9c5a46'), ROOF_D: hex('#80463a'),
  WOOD: hex('#8a6b49'), WOOD_DK: hex('#6a4f35'), WOOD_LT: hex('#a3845e'), SHAFT: hex('#5a4a3a'), SHAFT_T: hex('#6b4a2e'),
  BRONZE: hex('#b8954a'), PATINA: hex('#5f8274'), IRON: hex('#4a4a52'),
  OXBLOOD: hex('#7a2e26'), FRINGE: hex('#b8954a'), LINEN: hex('#e6ddc6'), HIDE: hex('#b09468'),
  PLUM: hex('#5a3550'), TENT: hex('#d8ccb2'),
  MARBLE: hex('#d9d2c3'), ROPE: hex('#a89070'), GATE: hex('#46321f'), PLASTER: hex('#c9b79a'), TEMPLE: hex('#e0d6c2'),
};
// The slot colours (Okabe-Ito, as Wl.SLOT_COLORS): red, blue, yellow, green.
export const SLOT = [hex('#D55E00'), hex('#0072B2'), hex('#F0E442'), hex('#009E73')];

export const ditherT = (px, py) => (BAYER4[(py & 3) * 4 + (px & 3)] + 0.5) / 16;

// The tone of base at q (0 deep shadow, about 0.62 the base itself, 1 highlight).
export function tone(base, q) {
  if (q < 0.62) {
    const sh = [base[0] * 0.4 + 0.035, base[1] * 0.38 + 0.035, base[2] * 0.42 + 0.07];
    return cmix(sh, base, q / 0.62);
  }
  const hi = [Math.min(base[0] * 1.12 + 0.06, 1), Math.min(base[1] * 1.1 + 0.055, 1), Math.min(base[2] * 1.06 + 0.04, 1)];
  return cmix(base, hi, (q - 0.62) / 0.38);
}

export function ramp(base, light, px, py) {
  const q = clamp(Math.floor(light * LEVELS + (ditherT(px, py) - 0.5) * DITHER), 0, LEVELS) / LEVELS;
  return tone(base, q);
}

const fpm = (a, b) => ((a % b) + b) % b;

// Arched openings in a face, in its uv (u across, v down from the top): returns 'open', 'ring'
// (the voussoirs) or null.
function arch(u, z, arches, spring, r) {
  for (const cx of arches) {
    const du = u - cx;
    if (Math.abs(du) > r + 0.5) continue;
    const dz = z - spring;
    const d = dz > 0 ? Math.hypot(du, dz) : Math.abs(du);
    if (d < r) return 'open';
    if (d < r + 0.45 && (dz > -0.1 || Math.abs(du) > r)) return dz > -0.1 ? 'ring' : null;
  }
  return null;
}

export function shade(mat, p, n, uv, light, sh, px, py) {
  switch (mat) {
    case M.TERRAIN: return ramp(terrain(p, n), light, px, py);
    case M.ROCK: return ramp(rock(p, n), light, px, py);
    case M.CLIFF: {
      const c = cliff(p, n);
      const r = ramp(c, light, px, py);
      return c === C.NUGGET ? [r[0], r[1], r[2], 0.15] : r;
    }
    case M.WATER: return water(p, sh, px, py);
    case M.WALL: return ramp(wall(p, n, Math.abs(n.y) > Math.abs(n.x) ? p.x : p.y), light * ao(p.z), px, py);
    case M.ROUNDWALL: return ramp(wall(p, n, uv.x), light * ao(p.z), px, py);
    case M.BRICK: return ramp(fpm(Math.floor(p.z / 0.25) + Math.floor((p.x + p.y) / 0.6), 2) ? C.BRICK : C.BRICK_D, light, px, py);
    case M.MERLON: return n.z > 0.5 ? ramp(C.CAP, light, px, py) : ramp(wall(p, n, Math.abs(n.y) > Math.abs(n.x) ? p.x : p.y), light, px, py);
    case M.WALLTOP: return ramp(flags(p, C.WALLTOP, C.WALLTOP, 1.5), light, px, py);
    case M.PAVE: return ramp(slabs(p), light, px, py);
    case M.QUARRY: {
      // the quarried cut face: dark rock with horizontal tool courses and the gold seams
      let c = W.vnoise(p.x * 0.12, p.z * 0.2) > 0.5 ? C.ROCK_B : cmix(C.ROCK_B, C.ROCK_D, 0.5);
      if (fpm(p.z, 1.4) < 0.18) c = C.ROCK_D;
      if (W.hash2(Math.floor(p.x * 1.5), Math.floor(p.z / 1.4)) > 0.86) c = cmix(c, C.ROCK_A, 0.5);
      const v = W.vein(p);
      if (v > 0.3) c = vein(c, v, p);
      const r = ramp(c, light, px, py);
      return c === C.NUGGET ? [r[0], r[1], r[2], 0.3] : r;
    }
    case M.MUDBRICK: return ramp(n.z > 0.5 ? C.MUDR : fpm(p.z, 0.5) < 0.08 ? cdark(C.MUDB, 0.1) : C.MUDB, light, px, py);
    case M.ARCH_AQ: {
      // aqueduct arcade: piers every 5 m, arches of 3.6 m springing at 3.2 m, a channel on top
      const z = 7.2 - uv.y;
      const u = fpm(uv.x, 5) - 2.5;
      const a = arch(u, z, [0], 3.2, 1.8);
      if (a === 'open') return null;
      if (a === 'ring' || (z > 6.4 && z < 6.7)) return ramp(C.CAP, light, px, py);
      return ramp(wall(p, n, uv.x), light, px, py);
    }
    case M.PLASTER: return ramp(C.PLASTER, light, px, py);
    case M.TEMPLE: return ramp(C.TEMPLE, light, px, py);
    case M.ARCH_GATE: case M.ARCH_BRIDGE: {
      // gate: two portals of 3.2 m springing at 3.4 m; bridge: two spans over the water
      const gate = mat === M.ARCH_GATE;
      const z = gate ? 6.8 - uv.y : 0.3 - uv.y;
      const a = gate ? arch(uv.x, z, [2.0, 6.0], 3.4, 1.6) : arch(uv.x, z, [2.6, 7.4], -1.6, 1.6);
      if (a === 'open') return null;
      if (a === 'ring') return ramp(C.CAP, light, px, py);
      return ramp(wall(p, n, uv.x), light, px, py);
    }
    case M.ROOF: {
      let c = fpm(Math.floor(uv.x / 0.6) + Math.floor(uv.y / 0.75), 2) < 1 ? C.ROOF : cmix(C.ROOF, C.ROOF_D, 0.5);
      if (fpm(uv.y, 0.75) < 0.22) c = cdark(c, 0.22);
      return ramp(c, light, px, py);
    }
    case M.WOOD: case M.WOOD_DARK: case M.WOOD_LIGHT: case M.SHAFT: {
      let b = mat === M.WOOD_DARK ? C.WOOD_DK : mat === M.WOOD_LIGHT ? C.WOOD_LT : mat === M.SHAFT ? C.SHAFT : C.WOOD;
      const g = W.hash2(Math.floor(uv.y / 0.5), Math.floor(uv.x / 1.7));
      b = cmix(b, cdark(b, 0.18), g * 0.6);
      if (fpm(uv.y, 0.5) < 0.12) b = cdark(b, 0.22);
      return ramp(b, light, px, py);
    }
    case M.BRONZE: {
      const c = W.vnoise(p.x * 1.7 + p.z, p.y * 1.7 - p.z) > 0.74 ? C.PATINA : C.BRONZE;
      return ramp(c, light * 1.05, px, py);
    }
    case M.IRON: return ramp(C.IRON, light, px, py);
    case M.TAR: case M.TAR_FALL: return tar(p, uv, mat === M.TAR_FALL, sh, px, py);
    case M.GOLD: case M.ORE: {
      const c = W.hash3(Math.floor(p.x * 4), Math.floor(p.y * 4), Math.floor(p.z * 4)) > 0.88 ? C.GLINT : C.ORE;
      return ramp(c, Math.max(light, 0.66), px, py);
    }
    case M.BANNER: {
      const c = uv.y > 1.9 || uv.y < 0.15 || uv.x < 0.12 || uv.x > 1.38 ? C.FRINGE : C.OXBLOOD;
      return ramp(c, light, px, py);
    }
    case M.SCUTUM: {
      const c = Math.hypot(uv.x - 0.35, uv.y - 0.5) < 0.16 ? C.BRONZE : uv.x < 0.06 || uv.x > 0.64 ? C.FRINGE : C.OXBLOOD;
      return ramp(c, light, px, py);
    }
    case M.PLUM: return ramp(C.PLUM, light, px, py);
    case M.TENT: return ramp(fpm(uv.x, 1.2) < 0.15 ? cdark(C.TENT, 0.1) : C.TENT, light, px, py);
    case M.LINEN: return ramp(C.LINEN, light, px, py);
    case M.HIDE: return ramp(cmix(C.HIDE, cdark(C.HIDE, 0.22), W.vnoise(p.x * 2 + p.z * 2, p.y * 2)), light, px, py);
    case M.CAVE: return hex('#1e1a1a');
    case M.GLOWCAVE: {
      // the mine mouth: dark, with a lamp-lit warm floor near the entrance
      const warm = clamp((uv.y - 3.2) / 2.5, 0, 1);
      const c = cmix(hex('#1e1a1a'), hex('#6a3a1c'), warm * 0.8);
      return [c[0], c[1], c[2], 0.25 * warm];
    }
    case M.MINE_DIRT: return ramp(cmix(hex('#6e5d4a'), hex('#57493a'), W.hash2(Math.floor(p.x * 3), Math.floor(p.y * 3))), light, px, py);
    case M.ACC0: case M.ACC1: case M.ACC2: case M.ACC3:
      return ramp(cmix(SLOT[mat - M.ACC0], C.WOOD_DK, 0.1), Math.max(light, 0.5), px, py);
    case M.LIT0: case M.LIT1: case M.LIT2: case M.LIT3: {
      // a powered shaft: timber wrapped in the rider's colour, 0.4 m timber gaps every 1.2 m
      const slot = SLOT[mat - M.LIT0];
      const band = fpm(uv.x, 1.2) < 0.8;
      const c = band ? slot : n.z > 0.6 ? cmix(C.SHAFT_T, slot, 0.35) : C.SHAFT_T;
      return ramp(c, Math.max(light, 0.5), px, py);
    }
    case M.FIRE: return W.hash2(px, py) > 0.4 ? [1, 0.81, 0.35, 0.8] : [1, 0.54, 0.16, 0.8];
    case M.STONE_DARK: return ramp(hex('#2e2a2c'), light, px, py);
    case M.BASALT: {
      // the junction floor: dark dressed basalt in 2 m slabs, so the lit shafts read on it
      const j = fpm(p.x, 2) < 0.12 || fpm(p.y, 2) < 0.12;
      const g = W.hash2(Math.floor(p.x / 2), Math.floor(p.y / 2));
      return ramp(j ? hex('#26262c') : cmix(hex('#3a3a42'), hex('#34343b'), g), light, px, py);
    }
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

const ao = (z) => 0.84 + 0.16 * clamp(z / 2.5, 0, 1);

function terrain(p, n) {
  const road = W.roadAt(p.x, p.y);
  // big tonal patches (30-60 m, about 6% of value), dune lee shading, ripples, gravel plains
  const big = W.vnoise(p.x * 0.022, p.y * 0.022);
  let sand = cmix(C.SAND, C.SAND_L, clamp(big * 1.4 - 0.5, 0, 1) * 0.6);
  sand = cdark(sand, (W.vnoise(p.x * 0.012 + 40, p.y * 0.012) - 0.5) * 0.12);
  if (n.z < 0.99 && n.x > 0.06) sand = cmix(sand, C.DUNE, 0.2);
  if (fpm(p.x * 0.7 + p.y * 0.35 + W.vnoise(p.x * 0.2, p.y * 0.2) * 1.5, 1) < 0.08) sand = cdark(sand, 0.04);
  const plain = W.vnoise(p.x * 0.015 + 11, p.y * 0.015 - 7);
  if (plain > 0.64) sand = cmix(sand, C.GRAVEL, 0.45 * smoothT(plain, 0.64, 0.72));
  if (W.hash2(Math.floor(p.x * 4), Math.floor(p.y * 4)) > 0.975) sand = cdark(sand, 0.1);
  // the wadi bed, scree at the foot of the massif
  const wd = W.wadi(p.x, p.y);
  if (wd > 0.4) sand = W.hash2(Math.floor(p.x * 3), Math.floor(p.y * 3)) > 0.86 ? C.GRAVEL : cmix(sand, C.WADI, 0.7);
  const foot = W.mountain(p.x, p.y - 8) > 1 || W.mountain(p.x, p.y - 15) > 4;
  if (foot && W.hash2(Math.floor(p.x * 2), Math.floor(p.y * 2)) > 0.6) sand = C.SCREE;
  // the moat banks are mud and stones
  if (p.z < -0.3 && W.fortDistance(p.x, p.y) < 22) {
    sand = cmix(sand, C.MUD, clamp((-0.3 - p.z) / 0.8, 0, 1));
    if (W.hash2(Math.floor(p.x * 2), Math.floor(p.y * 2)) > 0.78) sand = C.ROCK_B;
  }
  let rockiness = clamp((0.86 - n.z) / 0.18, 0, 1) * (p.z > -0.2 ? 1 : 0.3);
  if (p.z > 2) rockiness = Math.max(rockiness, clamp((p.z - 2) / 3, 0, 1));
  let c = sand;
  let isSand = true;
  if (road > 0) {
    const s = W.roadS(p.x, p.y);
    const paved = s < 46;
    if (road > 0.5) {
      isSand = false;
      if (paved) c = road < 0.68 ? C.KERB : flags(p, C.VIA, cdark(C.VIA, 0.07), 1.2);
      else {
        c = C.ROAD;
        if (Math.abs(road - 0.82) < 0.05 || W.hash2(Math.floor(p.x * 3), Math.floor(p.y * 3)) > 0.9) c = C.RUT;
      }
    } else if (road > 0.3 && !paved) {
      c = C.SHOULDER;
    }
  }
  if (rockiness > 0 && rockiness + (ditherT(Math.floor(p.x * 4 + p.z * 3), Math.floor(p.y * 4)) - 0.5) * 0.5 > 0.5) {
    c = rock(p, n);
    isSand = false;
  }
  if (isSand && n.z > 0.95 && p.z > -0.3) {
    if (W.hash2(Math.floor(p.x * 1.5), Math.floor(p.y * 1.5)) > 0.982 && W.vnoise(p.x * 0.08, p.y * 0.08) > 0.5) c = hex('#6e7048');
  }
  return c;
}

const smoothT = (v, a, b) => clamp((v - a) / (b - a), 0, 1);

// Courtyard flagstones: 3-4 m slabs with irregular joints.
function slabs(p) {
  const row = Math.floor(p.y / 3.4);
  const off = W.hash2(row, 17) * 3.6;
  const col = Math.floor((p.x + off) / (3 + W.hash2(row, 5) * 1.2));
  const g = W.hash2(col * 3 + 1, row * 7 + 2);
  let c = cmix(C.PAVE, C.PAVE_B, g * 0.8);
  const fy = fpm(p.y, 3.4);
  const fx = fpm(p.x + off, 3 + W.hash2(row, 5) * 1.2);
  if (fy < 0.2 || fx < 0.2) c = cmix(c, C.JOINT, 0.7);
  return c;
}

function rock(p, n = { x: 0, y: 0, z: 1 }) {
  const patch = W.vnoise(p.x * 0.06 + p.z * 0.05, p.y * 0.06);
  let c = cmix(C.ROCK_A, C.ROCK_B, clamp(patch * 1.5 - 0.25, 0, 1));
  if (n.z > 0.82) c = cmix(c, C.SAND, 0.45);
  if (W.hash3(Math.floor(p.x * 2), Math.floor(p.y * 2), Math.floor(p.z * 2)) > 0.95) c = C.CLEFT;
  return c;
}

// The massif in three planar tones by its normal (lit tops, faces turned to the sun, faces in
// shade), sparse cracks on steep faces only, sand drifted onto ledges and into the gullies,
// and the gold-bearing band near the mine.
function cliff(p, n) {
  const g = W.gully(p.x, p.y);
  const drift = W.vnoise(p.x * 0.1, p.y * 0.1);
  if (n.z > 0.72) return n.z > 0.86 && drift > 0.5 ? C.LEDGE : C.ROCK_A;
  if (g > 0.45 && drift > 0.35) return cmix(C.LEDGE, C.ROCK_B, 0.35);
  let c = n.x > 0.2 ? C.ROCK_D : n.y > 0.45 ? C.ROCK_B : cmix(C.ROCK_B, C.ROCK_D, 0.5);
  if (g > 0.6) c = C.CLEFT;
  if (n.z < 0.35 && W.hash3(Math.floor(p.x * 1.2), Math.floor(p.y * 1.2), Math.floor(p.z * 0.6)) > 0.965) c = C.CLEFT;
  const v = W.vein(p);
  if (v > 0.3) c = vein(c, v, p);
  return c;
}

// The gold-bearing band: a dark host band with clustered nuggets.
function vein(c, v, p) {
  if (v < 0.3) return c;
  const cluster = W.vnoise(p.x * 0.9 + p.z, p.y * 0.9) > 0.55;
  return v > 0.6 && cluster && W.hash3(Math.floor(p.x * 4), Math.floor(p.y * 4), Math.floor(p.z * 4)) > 0.45 ? C.NUGGET : C.HOST;
}

// Travertine ashlar (0.9 m courses of 1.8 m blocks, two tones per face) with an opus mixtum
// course of brick every 3.6 m of height.
function wall(p, n, u) {
  if (Math.abs(n.z) < 0.5 && fpm(p.z, 3.6) > 3.16 && p.z > 1.5) {
    const br = fpm(Math.floor(p.z / 0.22) + Math.floor((u + (Math.floor(p.z / 0.22) & 1) * 0.3) / 0.6), 2);
    return br ? C.BRICK : C.BRICK_D;
  }
  const row = Math.floor(p.z / 0.9);
  const off = row & 1 ? 0.9 : 0;
  const colx = Math.floor((u + off) / 1.8);
  const g = W.hash2(colx * 7 + Math.round(n.x * 3), row * 13 + Math.round(n.y * 5));
  let c = g > 0.7 ? C.WALL_B : C.WALL;
  if (fpm(p.z, 0.9) < 0.2 || fpm(u + off, 1.8) < 0.2) c = cmix(c, C.MORTAR, 0.35);
  return c;
}

function flags(p, base, alt, size) {
  const sx = Math.floor(p.x / size);
  const yy = p.y + sx * size * 0.5;
  const g = W.hash2(sx, Math.floor(yy / size));
  let c = cmix(base, alt, g);
  if (fpm(p.x, size) < 0.18 || fpm(yy, size) < 0.18) c = cmix(c, C.JOINT, 0.6);
  return c;
}

function water(p, sh, px, py) {
  const depth = W.WATER_Z - W.height(p.x, p.y);
  let c = depth < 0.6 ? cmix(C.WATER_SH, C.WATER_MD, depth / 0.6) : cmix(C.WATER_MD, C.WATER_DP, clamp((depth - 0.6) / 1.2, 0, 1));
  const rip = Math.sin(p.x * 1.1 + p.y * 0.6 + W.vnoise(p.x * 0.3, p.y * 0.3) * 6);
  if (rip > 0.95) c = clight(c, 0.12);
  if (depth < 0.15) c = cmix(c, C.MUD, 0.5);
  if (sh < 0.5) c = [c[0] * 0.7, c[1] * 0.76, c[2] * 0.82];
  else if (W.hash2(px * 3, py * 7) > 0.996) c = C.WGLINT;
  return c;
}

function tar(p, uv, falling, sh, px, py) {
  let c = hex('#2a1a10');
  if (falling) {
    // ribbons running down the curtain (the gaps show the arches), a wet sheen catching the sun
    const streak = W.vnoise(uv.x * 2.6, uv.y * 0.22);
    const gap = W.vnoise(uv.x * 3.1 + 7, uv.y * 0.1);
    if (gap < 0.22 && uv.y < 8.8) return null;
    c = hex('#2a1a10');
    if (streak > 0.66) c = hex('#4a3020');
    if (streak > 0.8) c = hex('#8a6a40');
  } else {
    const g = W.vnoise(p.x * 0.8, p.y * 1.6);
    c = hex('#2a1a10');
    if (g > 0.62) c = hex('#3e2a1a');
    if (g > 0.8) c = hex('#8a6a40');
  }
  if (sh < 0.5) c = cdark(c, 0.25);
  return c;
}
