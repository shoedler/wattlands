// The indexed world planes. Every plane stores palette indices (palette.mjs): sky bands, ridges, fields,
// trees, poles, road, verges. Seamless planes draw on a wrap-x Canvas and build heights from whole wave
// counts, so the first and last columns meet. The light comes from the upper right, where the sun climbs.
import { Canvas, bayer4, mulberry32 } from './raster.mjs';
import * as P from './palette.mjs';

const ix = P.ix;
const clamp = (u, lo, hi) => Math.min(Math.max(u, lo), hi);
const LIGHT = [0.6, -0.8];

/** A stable hash of a pixel, in [0, 1): placement that does not depend on drawing order. */
function hash2(x, y, s = 0) {
  let h = Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) + Math.imul(s | 0, 1274126177);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h = Math.imul(h ^ (h >>> 16), 2246822519);
  return ((h ^ (h >>> 15)) >>> 0) / 4294967296;
}

/** A seamless height function on [0, w): whole wave counts, phases from the seed. Returns 0..1. */
function waves(w, seed, counts, falloff = 0.6) {
  const rnd = mulberry32(seed);
  const parts = counts.map((n, i) => ({ n, phase: rnd() * Math.PI * 2, amp: falloff ** i }));
  const raw = (x) => parts.reduce((s, q) => s + q.amp * Math.sin((Math.PI * 2 * q.n * x) / w + q.phase), 0);
  let lo = Infinity;
  let hi = -Infinity;
  for (let x = 0; x < w; x++) {
    lo = Math.min(lo, raw(x));
    hi = Math.max(hi, raw(x));
  }
  return (x) => (raw(x) - lo) / Math.max(hi - lo, 1e-9);
}

/** Index base + a shade from float u, with an ordered dither between neighbours. */
function ditherShade(base, n, u, x, y, width = 0.5) {
  const v = clamp(u, 0, n - 1);
  const k = Math.floor(v);
  const f = v - k;
  const step = f > 1 - width / 2 ? 1 : f < width / 2 ? 0 : (f - width / 2) / (1 - width) > bayer4(x, y) ? 1 : 0;
  return base + clamp(k + step, 0, n - 1);
}

/** 64 x 720, y -180..540: index 0 at the top to 23 at the horizon, dithered between neighbours. */
export function skyPlane() {
  const c = new Canvas(64, 720);
  const horizon = 520; // y 340 on the stage
  for (let y = 0; y < c.h; y++) {
    // The colour changes faster toward the horizon, as a real dawn does.
    const u = Math.min(y / horizon, 1) ** 1.5 * (P.SKY_N - 1);
    const i0 = Math.floor(u);
    for (let x = 0; x < c.w; x++) {
      c.px(x, y, ix(P.SKY + Math.min(i0 + (u - i0 > bayer4(x, y) ? 1 : 0), P.SKY_N - 1)));
    }
  }
  return c;
}

/** 480 x 380: stars in three strengths and a faint band of many, fading by LUT alpha. It tiles, so no moon. */
export function starsPlane(seed) {
  const c = new Canvas(480, 380, { wrapX: true });
  const rnd = mulberry32(seed ^ 0x51a2);
  const bandAt = (x) => 150 + 90 * Math.sin((x / c.w) * Math.PI * 2);
  for (let i = 0; i < 420; i++) {
    const x = Math.floor(rnd() * c.w);
    const y = Math.floor(rnd() * c.h * 0.92);
    // Most of the stars gather into a soft diagonal band.
    const near = Math.abs(y - bandAt(x));
    if (near > 40 && rnd() < 0.7) continue;
    const pick = rnd();
    c.px(x, y, ix(P.STAR + (pick < 0.72 ? 0 : pick < 0.95 ? 1 : 2)));
  }
  for (let i = 0; i < 12; i++) {
    const x = 12 + Math.floor(rnd() * (c.w - 24));
    const y = 8 + Math.floor(rnd() * 300);
    c.px(x, y, ix(P.STAR + 2));
    c.px(x - 1, y, ix(P.STAR + 1));
    c.px(x + 1, y, ix(P.STAR + 1));
    c.px(x, y - 1, ix(P.STAR + 1));
    c.px(x, y + 1, ix(P.STAR + 1));
  }
  return c;
}

/** A cumulus: lobes over a flat base. Paints lobe by lobe so each one is lit on its upper right. */
function cumulus(c, cx, baseY, w, h, rnd, seed) {
  const lobes = [];
  const n = Math.max(5, Math.round(w / 9));
  for (let i = 0; i < n; i++) {
    const u = (i + 0.5) / n;
    const dome = Math.sin(Math.PI * u) ** 0.8;
    const r = 3 + dome * (h * 0.32) * (0.75 + rnd() * 0.5);
    lobes.push({ x: cx + (u - 0.5) * w + rnd() * 3, y: baseY - r * 0.5 - dome * h * 0.28 * rnd(), r });
    if (dome > 0.55) {
      const r2 = r * (0.55 + rnd() * 0.3);
      lobes.push({ x: cx + (u - 0.5) * w + rnd() * 5 - 2, y: baseY - r - r2 * 0.6 - dome * h * 0.2, r: r2 });
    }
  }
  // Back lobes first: the high ones, then the low front ones; left to right so the lit sides overlap.
  lobes.sort((a, b) => a.y - b.y || a.x - b.x);
  for (const q of lobes) {
    const lim = Math.ceil(q.r) + 1;
    for (let j = -lim; j <= lim; j++) {
      for (let i = -lim; i <= lim; i++) {
        const x = Math.round(q.x) + i;
        const y = Math.round(q.y) + j;
        if (y > baseY) continue;
        const d = Math.hypot(i, j) / q.r;
        if (d > 1 - 0.12 * hash2(x, y, seed)) continue;
        const s = (i * LIGHT[0] + j * LIGHT[1]) / q.r;
        // Lit crown, soft belly, and a shadowed base that gets darker toward the flat underside.
        let u = 3.1 + s * 2.2;
        u = Math.min(u, 0.7 + (baseY - y) * 0.42);
        c.px(x, y, ix(ditherShade(P.CLOUD, 6, u, x, y, 0.4)));
      }
    }
  }
}

/** Long thin streaks of high cloud: horizontal, broken, two shades. */
function cirrus(c, cx, cy, w, rnd, seed) {
  const rows = 3 + Math.floor(rnd() * 4);
  for (let r = 0; r < rows; r++) {
    const y = cy + r * 2 + Math.floor(rnd() * 2);
    // Lower rows slide ahead, so the patch leans with the wind like a mare's tail.
    const x0 = cx - w * (0.34 + rnd() * 0.12) + r * 7;
    const len = w * (0.42 + rnd() * 0.5) * (1 - Math.abs(r - rows / 2) / rows);
    for (let x = Math.round(x0); x < x0 + len; x++) {
      const t = (x - x0) / len;
      // Whole runs of 4 to 8 px come and go, thinning to the ends.
      if (hash2(x >> 3, y, seed) > Math.sin(Math.PI * t) ** 0.6 * 1.05) continue;
      c.px(x, y, ix(P.CLOUD + (hash2(x >> 3, y, seed + 1) < 0.4 ? 4 : 3)));
    }
  }
}

function cloudPlane(w, h, seed, build) {
  const c = new Canvas(w, h, { wrapX: true });
  build(c, mulberry32(seed), seed);
  return c;
}

export const cloudsHiPlane = (seed) =>
  cloudPlane(960, 140, seed ^ 0x11, (c, rnd, s) => {
    for (let k = 0; k < 9; k++) {
      const wide = 70 + rnd() * 130;
      cirrus(c, wide * 0.6 + 10 + rnd() * (c.w - wide * 1.3 - 20), 14 + rnd() * 96, wide, rnd, s + k);
    }
    for (let k = 0; k < 3; k++) {
      const wide = 40 + rnd() * 30;
      cumulus(c, wide + rnd() * (c.w - wide * 2), 60 + rnd() * 60, wide, 12 + rnd() * 6, rnd, s + 40 + k);
    }
  });

export const cloudsLoPlane = (seed) =>
  cloudPlane(960, 100, seed ^ 0x22, (c, rnd, s) => {
    for (let k = 0; k < 7; k++) {
      const wide = 60 + rnd() * 110;
      const cx = wide * 0.7 + rnd() * (c.w - wide * 1.4);
      cumulus(c, cx, 42 + rnd() * 50, wide, 26 + rnd() * 18, rnd, s + k);
    }
  });

export function farHillsPlane(seed) {
  const c = new Canvas(1440, 150, { wrapX: true });
  // Far range: sharp faces, close to the colour of the sky at the horizon.
  const range = waves(c.w, seed ^ 0x33, [3, 7, 13, 29, 61], 0.5);
  const topA = (x) => 24 + 50 * range(x);
  const gully = waves(c.w, seed ^ 0x34, [47, 83], 0.7);
  for (let x = 0; x < c.w; x++) {
    const top = Math.round(topA(x));
    for (let y = top; y < c.h; y++) {
      const d = y - top;
      // Faces follow the slope down: read the slope up the hill from here.
      const sx = x - d * 0.55;
      const slope = topA(sx + 3) - topA(sx - 3);
      const u = 1.5 + clamp(slope * 0.34, -1.3, 1.3) + (gully(sx) - 0.5) * 0.9 + d * 0.02;
      c.px(x, y, ix(ditherShade(P.RIDGE, 4, u, x, y, 0.5)));
    }
  }
  // Nearer range: rounder, wooded, with a fringe of tree tops on the crest and darker wood patches.
  const near = waves(c.w, seed ^ 0x35, [4, 9, 17], 0.5);
  const wood = waves(c.w, seed ^ 0x36, [11, 23, 41], 0.7);
  const topB = (x) => 68 + 40 * near(x);
  for (let x = 0; x < c.w; x++) {
    const bump = Math.floor(hash2(((x + 1) >> 1) % (c.w >> 1), 3, seed) * 3);
    const top = Math.round(topB(x)) - bump;
    for (let y = top; y < c.h; y++) {
      const d = y - top;
      const slope = topB(x - d * 0.3 + 4) - topB(x - d * 0.3 - 4);
      const patch = wood(x + d * 0.8) + Math.sin(d * 0.35 + x * 0.015) * 0.18;
      let u = 1.7 + clamp(slope * 0.3, -0.9, 0.9) + d * 0.012;
      if (patch > 0.56) u -= 1.1;
      if (d < 2) u += 0.7;
      c.px(x, y, ix(ditherShade(P.RIDGE_NEAR, 4, u, x, y, 0.5)));
    }
  }
  // A far village: a church tower and a few roofs on the nearer crest.
  const vx = 610;
  const vy = Math.round(topB(vx)) + 2;
  c.rect(vx, vy - 15, 4, 17, ix(P.RIDGE_NEAR + 1));
  c.rect(vx + 3, vy - 15, 1, 17, ix(P.RIDGE_NEAR + 3));
  c.polyFill(
    [
      [vx - 1, vy - 15],
      [vx + 2, vy - 25],
      [vx + 5, vy - 15],
    ],
    ix(P.RIDGE_NEAR),
  );
  c.px(vx + 2, vy - 11, ix(P.RIDGE));
  c.rect(vx - 12, vy - 4, 11, 6, ix(P.RIDGE_NEAR + 2));
  c.rect(vx - 13, vy - 6, 13, 2, ix(P.RIDGE_NEAR));
  for (const [dx, w] of [
    [7, 7],
    [16, 9],
    [-22, 8],
  ]) {
    const yy = Math.round(topB(vx + dx)) + 1;
    c.rect(vx + dx, yy - 2, w, 4, ix(P.RIDGE_NEAR + 2));
    c.rect(vx + dx, yy - 3, w, 1, ix(P.RIDGE_NEAR));
  }
  return c;
}

const CELL_TYPES = ['pasture', 'crop', 'pasture', 'plough', 'pasture', 'crop', 'meadow'];

/** One patchwork cell's pixel: flat colour plus the mark its land use leaves. */
function fieldPixel(type, x, y, depth, tone, c, seed) {
  if (type === 'plough') {
    const line = (y + (x >> 3)) % 2 === 0;
    c.px(x, y, ix(P.PLOUGH + (line ? 1 : 0)));
  } else if (type === 'crop') {
    const rows = (y + Math.floor(x / 9)) % 3 === 0;
    c.px(x, y, ix(P.CROP + clamp(tone + (rows ? 0 : 1), 0, 2)));
  } else if (type === 'meadow') {
    const u = 2.4 + (hash2(x >> 1, y, seed) < 0.12 ? 1 : 0);
    c.px(x, y, ix(P.PASTURE + clamp(Math.floor(u), 0, 3)));
  } else {
    c.px(x, y, ix(ditherShade(P.PASTURE, 4, 0.7 + tone * 0.8 + depth * 0.2, x, y, 0.4)));
  }
}

/** A hedge bush on a boundary: a 2-3 px lump lit on the upper right. */
function bush(c, x, y, r) {
  for (let j = -r; j <= r; j++) {
    for (let i = -r; i <= r; i++) {
      if (i * i + j * j > r * r + 0.5) continue;
      const lit = i - j > r * 0.6;
      c.px(x + i, y + j, ix(P.HEDGE + (lit ? 2 : j > 0 ? 0 : 1)));
    }
  }
}

export function midHillsPlane(seed) {
  const c = new Canvas(1280, 150, { wrapX: true });
  const crest = waves(c.w, seed ^ 0x44, [2, 3, 7, 13], 0.55);
  const topOf = (x) => 30 + 60 * crest(x);
  const shadow = waves(c.w, seed ^ 0x46, [5, 11], 0.6);
  // Rows widen toward the viewer, so the fields read as receding ground.
  const rowEdges = [];
  let e = 0;
  for (let r = 0; r < 12; r++) {
    rowEdges.push(e);
    e += 4 + r * 2.4;
  }
  rowEdges.push(1e9);
  const hedges = [];
  for (let x = 0; x < c.w; x++) {
    const top = Math.round(topOf(x));
    for (let y = top; y < c.h; y++) {
      const d = y - top;
      let r = 0;
      while (d >= rowEdges[r + 1]) r++;
      const cols = Math.max(5, Math.round(26 - r * 1.7));
      const cw = c.w / cols;
      const skew = (r % 2 === 0 ? 1 : -1) * 0.9 * d;
      const shift = hash2(r, 7, seed) * cw;
      const u = (((x + skew + shift) % c.w) + c.w) % c.w;
      const col = Math.floor(u / cw);
      const inRow = d - rowEdges[r];
      const inCol = u - col * cw;
      const onHedge = inRow < 1 || inCol < 1.2;
      if (onHedge) {
        c.px(x, y, ix(P.HEDGE + (inRow < 1 ? 1 : 0)));
        if (hash2(x, y, seed + 9) < 0.09 + r * 0.008) hedges.push([x, y, r > 5 ? 2 : 1]);
        continue;
      }
      const type = CELL_TYPES[Math.floor(hash2(r, col, seed + 3) * CELL_TYPES.length)];
      const tone = hash2(r, col, seed + 4) < 0.5 ? 0 : 1;
      fieldPixel(type, x, y, shadow(x) > 0.62 ? 0 : 1, tone, c, seed);
    }
    // A lit crest line and its grassy shoulder.
    c.px(x, top, ix(P.PASTURE + 3));
    if (x % 3 !== 0) c.px(x, top + 1, ix(P.PASTURE + 2));
  }
  for (const [x, y, r] of hedges) bush(c, x, y - 1, r);
  // Tiny farms in the fields, with a lit window at dawn.
  const rnd = mulberry32(seed ^ 0x45);
  for (let i = 0; i < 11; i++) {
    const x = 20 + Math.floor(rnd() * (c.w - 40));
    const y = Math.round(topOf(x)) + 14 + Math.floor(rnd() * 34);
    bush(c, x - 3, y - 4, 3);
    c.rect(x, y, 8, 5, ix(P.WALL + 2));
    c.rect(x + 7, y, 1, 5, ix(P.WALL + 3));
    c.rect(x - 1, y - 2, 10, 2, ix(P.ROOF + 1));
    c.rect(x - 1, y - 3, 8, 1, ix(P.ROOF + 2));
    c.px(x + 2, y + 2, ix(P.WINDOW));
    c.px(x + 5, y + 2, ix(P.WINDOW));
  }
  // Valley fog behind the crest: on empty pixels only, so it burns off and leaves no holes.
  for (let x = 0; x < c.w; x++) {
    const top = Math.round(topOf(x));
    for (let y = Math.max(top - 16, 0); y < top; y++) {
      const density = (1 - (top - y) / 16) * 0.55;
      if (density > bayer4(x, y)) c.px(x, y, ix(P.MIST + (density > 0.55 ? 1 : 0)));
    }
  }
  return c;
}

/** One foliage lump: lit on its upper right, dark low left, a rim on the lit edge. */
function lump(c, cx, cy, rx, ry, base, seed, shift = 0) {
  const ox = Math.round(cx);
  const oy = Math.round(cy);
  const lx = Math.ceil(rx) + 1;
  const ly = Math.ceil(ry) + 1;
  for (let j = -ly; j <= ly; j++) {
    for (let i = -lx; i <= lx; i++) {
      const nx = i / rx;
      const ny = j / ry;
      const d2 = nx * nx + ny * ny;
      const x = ox + i;
      const y = oy + j;
      if (d2 > 1 - 0.3 * hash2(x, y, seed)) continue;
      const s = nx * LIGHT[0] + ny * LIGHT[1];
      if (s > 0.62 && d2 > 0.35) {
        c.px(x, y, ix(base + 5));
      } else {
        c.px(x, y, ix(ditherShade(base, 5, 1.9 + s * 2.3 + shift, x, y, 0.35)));
      }
    }
  }
}

function poplar(c, x, base, h, seed) {
  const width = 3.4 + h * 0.035;
  c.rect(x, base - 8, 2, 8, ix(P.WOOD + 1));
  c.px(x + 1, base - 8, ix(P.WOOD + 2));
  const n = Math.round(h / 4);
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    const y = base - 5 - t * (h - 8);
    const prof = Math.sin(Math.PI * clamp(0.1 + t * 0.9, 0, 1) ** 0.72) ** 0.7;
    const rx = 1.2 + width * prof;
    const jit = (hash2(i, x, seed) - 0.5) * 2.2;
    lump(c, x + 1 + jit, y, rx, 4.2, P.POPLAR, seed + i, -0.1 + t * 0.5);
  }
}

function oak(c, x, base, r, seed) {
  const rnd = mulberry32(seed);
  c.rect(x, base - r, 3, r, ix(P.WOOD + 1));
  c.rect(x + 2, base - r, 1, r, ix(P.WOOD + 3));
  c.line(x + 1, base - r, x - 4, base - r - 4, ix(P.WOOD + 1));
  c.line(x + 1, base - r, x + 6, base - r - 5, ix(P.WOOD + 1));
  const cy = base - r - r * 0.55;
  const blobs = [];
  const n = Math.round(r * 1.5);
  for (let i = 0; i < n; i++) {
    const a = rnd() * Math.PI * 2;
    const q = Math.sqrt(rnd()) * 0.8;
    blobs.push({ x: x + 1 + Math.cos(a) * q * r * 1.1, y: cy + Math.sin(a) * q * r * 0.78, r: 3.2 + rnd() * r * 0.2 });
  }
  blobs.sort((a, b) => b.y - b.x * 0.3 - (a.y - a.x * 0.3));
  for (const [i, b] of blobs.entries()) {
    const up = (cy - b.y) / r;
    lump(c, b.x, b.y, b.r, b.r * 0.85, P.OAK, seed + i, up * 0.8);
  }
}

/** Rows of roof tiles between two heights along a slanted edge. */
function tiled(c, pts, top, bottom, seed) {
  c.polyFill(pts, ix(P.ROOF + 1));
  // Paint over the fill only where it landed.
  const lo = Math.min(...pts.map((p) => p[0]));
  const hi = Math.max(...pts.map((p) => p[0]));
  for (let y = top; y <= bottom; y++) {
    for (let x = Math.floor(lo); x <= Math.ceil(hi); x++) {
      if (c.get(x, y)[0] !== ix(P.ROOF + 1)[0] || c.get(x, y)[3] === 0) continue;
      const course = (y - top) % 2 === 0;
      if (course && (x + (y >> 1) * 2) % 3 === 0) c.px(x, y, ix(P.ROOF));
      else if (course) c.px(x, y, ix(P.ROOF + 2));
      else if (hash2(x, y, seed) < 0.12) c.px(x, y, ix(P.ROOF + 3));
    }
  }
}

/** A farmhouse with a chimney. Returns the chimney's top centre pixel: where kit.props.smoke rises from. */
function house(c, x, base, seed) {
  // Chimney first, so the roof sits in front of its foot. The stack is 10 px above the ridge line.
  c.rect(x + 19, base - 32, 3, 14, ix(P.WALL + 1));
  c.rect(x + 21, base - 32, 1, 14, ix(P.WALL + 2));
  c.rect(x + 18, base - 33, 5, 1, ix(P.ROOF));
  // The long wall, in shade, and the gable end to the sun.
  c.rect(x, base - 15, 22, 15, ix(P.WALL + 1));
  c.rect(x + 22, base - 15, 11, 15, ix(P.WALL + 3));
  c.polyFill(
    [
      [x + 22, base - 15],
      [x + 27.5, base - 23],
      [x + 33, base - 15],
    ],
    ix(P.WALL + 3),
  );
  c.line(x + 22, base - 1, x + 22, base - 15, ix(P.WALL));
  // Plaster: a stone course at the foot and a few patches.
  for (let i = 0; i < 33; i++) {
    if (i % 3 !== 0) c.px(x + i, base - 1, ix(P.WALL));
    if (hash2(x + i, base, seed) < 0.3) c.px(x + i, base - 2, ix(P.WALL + (i < 22 ? 0 : 2)));
  }
  tiled(
    c,
    [
      [x - 2, base - 15],
      [x + 3, base - 24],
      [x + 27, base - 24],
      [x + 22, base - 15],
    ],
    base - 24,
    base - 15,
    seed,
  );
  c.line(x + 3, base - 24, x + 27, base - 24, ix(P.ROOF + 3));
  c.line(x + 27, base - 24, x + 33, base - 15, ix(P.ROOF));
  c.line(x + 27, base - 24, x + 22, base - 15, ix(P.ROOF));
  // Windows with a glow on the wall round them, a door, a sill.
  for (const wx of [x + 3, x + 11]) {
    c.rect(wx - 1, base - 12, 6, 7, ix(P.GLOW));
    c.rect(wx, base - 11, 4, 5, ix(P.WINDOW));
    c.rect(wx + 2, base - 11, 1, 5, ix(P.WALL));
    c.rect(wx, base - 9, 4, 1, ix(P.WALL));
    c.rect(wx - 1, base - 5, 6, 1, ix(P.WOOD + 2));
  }
  c.rect(x + 25, base - 12, 3, 4, ix(P.WINDOW));
  c.rect(x + 18, base - 10, 3, 10, ix(P.WOOD + 1));
  c.px(x + 19, base - 5, ix(P.INSULATOR));
  return [x + 20, base - 33];
}

/** A barn: tarred planks, a big door, a tin roof. */
function barn(c, x, base, seed) {
  c.rect(x, base - 16, 34, 16, ix(P.WOOD + 1));
  for (let i = 0; i < 34; i += 3) c.rect(x + i, base - 16, 1, 16, ix(P.WOOD));
  for (let i = 1; i < 34; i += 3) {
    if (hash2(x + i, 1, seed) < 0.5) c.rect(x + i, base - 12, 1, 8, ix(P.WOOD + 2));
  }
  c.rect(x + 10, base - 12, 12, 12, ix(P.WOOD));
  c.line(x + 10, base - 12, x + 21, base - 1, ix(P.WOOD + 2));
  c.line(x + 21, base - 12, x + 10, base - 1, ix(P.WOOD + 2));
  c.rect(x + 10, base - 13, 12, 1, ix(P.WOOD + 3));
  c.polyFill(
    [
      [x - 2, base - 16],
      [x + 5, base - 26],
      [x + 29, base - 26],
      [x + 36, base - 16],
    ],
    ix(P.ROOF + 2),
  );
  for (let i = 0; i < 40; i += 4) c.line(x + i - 2, base - 16, x + 5 + (i * 24) / 40, base - 26, ix(P.ROOF + 1));
  c.line(x + 5, base - 26, x + 29, base - 26, ix(P.ROOF + 3));
}

/** The plane's Canvas also carries `chimneys`, [[x, y], ...] in strip px, which the bake writes to kit.json. */
export function nearTreesPlane(seed) {
  const c = new Canvas(1600, 150, { wrapX: true });
  const f = waves(c.w, seed ^ 0x55, [3, 8, 19], 0.5);
  const groundAt = (x) => Math.round(112 + 8 * f(x));
  for (let x = 0; x < c.w; x++) {
    const top = groundAt(x);
    for (let y = top; y < c.h; y++) {
      const d = y - top;
      c.px(x, y, ix(P.PASTURE + (d < 1 ? 3 : d < 3 ? 2 : d < 7 ? 1 : 0)));
    }
    if (hash2(x, 1, seed) < 0.25) c.px(x, top - 1, ix(P.PASTURE + 2));
  }
  // The field below the trees shows on climbs: mown strips, tufts, and a low hedge with bushes along it.
  for (let y = 112; y < c.h; y++) {
    for (let x = 0; x < c.w; x++) {
      const d = y - groundAt(x);
      if (d < 7) continue;
      const strip = ((x + y * 3) >> 5) % 2 === 0;
      const tuft = hash2(x >> 1, y, seed + 5) < 0.14;
      c.px(x, y, ix(P.PASTURE + (strip ? 1 : 0) + (tuft ? 1 : 0)));
    }
  }
  for (let x = 0; x < c.w; x++) {
    const y = 133 + Math.round(3 * f(x));
    c.px(x, y, ix(P.HEDGE));
    c.px(x, y + 1, ix(P.HEDGE));
    if (hash2(x, 2, seed) < 0.18) bush(c, x, y - 1, hash2(x, 3, seed) < 0.3 ? 3 : 2);
  }
  const rnd = mulberry32(seed ^ 0x56);
  c.chimneys = [];
  // The seam stays clear of trees, so strips meet on plain ground.
  let x = 26;
  const end = c.w - 60;
  let n = 0;
  const farms = [];
  while (x < end) {
    const pick = rnd();
    const base = groundAt(x) + 2 + Math.floor(rnd() * 3);
    if (pick < 0.42) {
      // A row of poplars along a lane.
      const count = 4 + Math.floor(rnd() * 7);
      const h0 = 52 + rnd() * 34;
      for (let i = 0; i < count && x < end; i++) {
        poplar(c, x, groundAt(x) + 3, h0 + rnd() * 14 - 7, seed + ++n * 13);
        x += 11 + Math.floor(rnd() * 5);
      }
      x += 16 + Math.floor(rnd() * 30);
    } else if (pick < 0.72) {
      const r = 11 + Math.floor(rnd() * 9);
      oak(c, x + r, base, r, seed + ++n * 17);
      x += r * 2 + 8 + Math.floor(rnd() * 26);
      if (rnd() < 0.5 && x < end) {
        const r2 = 8 + Math.floor(rnd() * 6);
        oak(c, x, groundAt(x) + 3, r2, seed + ++n * 19);
        x += r2 + 10;
      }
    } else if (pick < 0.86 && x < end - 110) {
      farms.push(x);
      x += 96;
    } else {
      // Open field: the far hills show through.
      x += 34 + Math.floor(rnd() * 70);
    }
  }
  for (const fx of farms) {
    const fb = groundAt(fx + 16) + 3;
    oak(c, fx - 2, fb - 1, 9, seed + ++n * 23);
    c.chimneys.push(house(c, fx + 10, fb, seed + n));
    barn(c, fx + 50, fb, seed + n);
    poplar(c, fx + 90, groundAt(fx + 90) + 3, 58, seed + ++n * 29);
  }
  // Ground mist in the field: opaque, it turns back into grass by day. Hanging mist on the empty pixels
  // behind the trees burns off through LUT alpha.
  const bank = waves(c.w, seed ^ 0x57, [5, 13, 29], 0.6);
  for (let xx = 0; xx < c.w; xx++) {
    const top = groundAt(xx);
    const crest = top - 5 - 16 * bank(xx);
    for (let y = Math.floor(crest); y < top; y++) {
      const density = clamp((y - crest) / Math.max(top - crest, 1), 0, 1) * 0.85 + 0.1;
      if (c.get(xx, y)[3] === 0 && density > bayer4(xx, y)) c.px(xx, y, ix(P.MIST + (density > 0.5 ? 1 : 0)));
    }
    for (let y = top; y < top + 5; y++) {
      if (bayer4(xx, y) < 0.42 - (y - top) * 0.08) c.px(xx, y, ix(P.MIST_GROUND + ((y - top) % 2)));
    }
  }
  return c;
}

/** 480 x 130: one pole every 240 px with cross arms, insulators and a stay; three wires with a catenary. */
export function polesPlane() {
  const c = new Canvas(480, 130, { wrapX: true });
  for (const [x, transformer] of [
    [60, false],
    [300, true],
  ]) {
    c.rect(x, 10, 3, 120, ix(P.WOOD + 1));
    c.rect(x + 2, 10, 1, 120, ix(P.WOOD + 3));
    c.rect(x, 10, 1, 120, ix(P.WOOD));
    for (let y = 30; y < 130; y += 17) c.px(x + 1, y, ix(P.WOOD));
    // Cross arm, its braces, three insulators on it.
    c.rect(x - 9, 15, 21, 2, ix(P.WOOD + 2));
    c.rect(x - 9, 16, 21, 1, ix(P.WOOD));
    c.line(x - 6, 17, x, 25, ix(P.WOOD));
    c.line(x + 8, 17, x + 2, 25, ix(P.WOOD));
    for (const dx of [-8, 1, 10]) {
      c.rect(x + dx, 13, 1, 2, ix(P.INSULATOR));
      c.px(x + dx, 12, ix(P.INSULATOR));
    }
    if (transformer) {
      c.rect(x - 7, 36, 7, 12, ix(P.WOOD + 1));
      c.rect(x - 7, 36, 2, 12, ix(P.WOOD));
      c.rect(x - 1, 36, 1, 12, ix(P.WOOD + 3));
      c.rect(x - 8, 35, 9, 1, ix(P.WOOD + 2));
      c.line(x - 4, 35, x - 7, 17, ix(P.WIRE));
    }
  }
  for (let x = 0; x < 480; x++) {
    const t = ((x + 180) % 240) / 240; // 0 at a pole, 1 at the next
    const sag = 9 * (1 - (2 * t - 1) ** 2);
    c.px(x, 12 + sag, ix(P.WIRE));
    c.px(x, 13 + sag * 0.92, ix(P.WIRE));
    c.px(x, 15 + sag * 0.84 + 1, ix(P.WIRE));
  }
  // Two starlings on the wire.
  for (const bx of [150, 158]) {
    const t = ((bx + 180) % 240) / 240;
    const y = Math.round(12 + 9 * (1 - (2 * t - 1) ** 2));
    c.rect(bx, y - 3, 3, 2, ix(P.WIRE));
    c.px(bx - 1, y - 3, ix(P.WIRE));
    c.px(bx + 3, y - 4, ix(P.WIRE));
  }
  return c;
}

/** 240 x 30, contact row 14 is the middle lane: far kerb, asphalt with wear, patches, cracks, centre dashes. */
export function roadPlane(seed) {
  const c = new Canvas(240, 30, { wrapX: true });
  const rnd = mulberry32(seed ^ 0x77);
  const wearA = waves(c.w, seed ^ 0x78, [2, 5, 11], 0.7);
  const wearB = waves(c.w, seed ^ 0x79, [3, 7, 13], 0.7);
  for (let y = 0; y < c.h; y++) {
    for (let x = 0; x < c.w; x++) {
      // Lighter in the two worn wheel tracks, darker along the crown and the edges.
      const track = Math.abs(y - (8 + wearA(x) * 2)) < 2 || Math.abs(y - (20 + wearB(x) * 2)) < 3;
      c.px(x, y, ix(P.ASPHALT + (track ? 3 : 2)));
    }
  }
  // Tar repairs: hard-edged, darker, with a bead of seal round the longer ones.
  for (let i = 0; i < 5; i++) {
    const x = Math.floor(rnd() * c.w);
    const y = 4 + Math.floor(rnd() * 18);
    const w = 12 + Math.floor(rnd() * 34);
    const h = 3 + Math.floor(rnd() * 4);
    c.rect(x, y, w, h, ix(P.ASPHALT + 1));
    c.rect(x, y, w, 1, ix(P.ASPHALT));
    c.rect(x, y + h - 1, w, 1, ix(P.ASPHALT));
  }
  // Aggregate: small clusters, stretched along the road by the low viewpoint.
  for (let i = 0; i < 620; i++) {
    const x = Math.floor(rnd() * c.w);
    const y = 3 + Math.floor(rnd() * 24);
    const roll = rnd();
    const run = rnd() < 0.3 ? 2 : 1;
    const index = roll < 0.45 ? P.GRIT + 1 : roll < 0.8 ? P.GRIT : P.ASPHALT;
    for (let k = 0; k < run; k++) c.px(x + k, y, ix(index));
  }
  // Long hairline cracks that wander.
  for (let i = 0; i < 4; i++) {
    let x = Math.floor(rnd() * c.w);
    let y = 4 + Math.floor(rnd() * 22);
    const n = 14 + Math.floor(rnd() * 26);
    for (let k = 0; k < n; k++) {
      c.px(x, y, ix(P.ASPHALT));
      x += 1 + Math.floor(rnd() * 2);
      if (rnd() < 0.35) y = clamp(y + (rnd() < 0.5 ? 1 : -1), 3, 26);
    }
  }
  // The far kerb, its shadow; the near edge line, the earth shoulder.
  for (let x = 0; x < c.w; x++) {
    c.px(x, 0, ix(P.PAINT + (x % 24 === 0 ? 0 : 1)));
    c.px(x, 1, ix(x % 24 === 0 ? P.ASPHALT : P.PAINT));
    c.px(x, 2, ix(P.ASPHALT));
    c.px(x, 27, ix(hash2(x >> 1, 27, seed) < 0.1 ? P.GRIT + 1 : P.PAINT + 1));
    c.px(x, 28, ix(P.EARTH + 1 + (hash2(x, 28, seed) < 0.3 ? 1 : 0)));
    c.px(x, 29, ix(P.EARTH + (hash2(x, 29, seed) < 0.3 ? 1 : 0)));
  }
  // Centre dashes, worn in places.
  for (let x = 0; x < c.w; x += 40) {
    for (let i = 0; i < 12; i++) {
      for (const y of [13, 14]) {
        if (hash2(x + i, y, seed) > 0.14) c.px(x + i, y, ix(P.PAINT + 1));
      }
    }
  }
  return c;
}

/**
 * Grass blades, back rows first so the near ones overlap: root dark, tip light. A blade's phase and height
 * come from its hash, so every wind frame has the same blades, leaned differently.
 */
function blades(c, { rows, density, seed, frame, frames, base, spread, maxH, lift = 0 }) {
  for (const y of rows) {
    for (let x = 0; x < c.w; x++) {
      if (hash2(x, y, seed) >= density) continue;
      const h = 1 + Math.floor(hash2(x, y, seed + 1) * maxH);
      const phase = hash2(x, y, seed + 2);
      const swing = Math.sin(((frame / frames + phase) * Math.PI * 2));
      const lean = h >= 3 ? Math.round(swing * (h >= 5 ? 1.4 : 0.9)) : 0;
      const tone = hash2(x, y, seed + 3) * spread;
      for (let j = 0; j <= h; j++) {
        const t = j / h;
        const idx = base + Math.round(lift + tone + t * 2.2);
        c.px(x + Math.round(lean * t), y - j, ix(clamp(idx, P.GRASS, P.GRASS + 9)));
      }
    }
  }
}

/** 240 x 26: fence posts, wire, a marker post, a marker of grass, wind frame f of 4. */
export function vergeFarPlane(seed, f) {
  const c = new Canvas(240, 26, { wrapX: true });
  for (let x = 0; x < c.w; x++) {
    const top = 8 + Math.floor(hash2(x >> 1, 2, seed) * 3);
    for (let y = top; y < c.h; y++) {
      const d = y - top;
      c.px(x, y, ix(P.GRASS + clamp(4 - (d >> 3) + (bayer4(x, y) < 0.12 ? 1 : 0), 1, 6)));
    }
  }
  // Fence: posts, two strands, one leaning post.
  c.rect(0, 9, c.w, 1, ix(P.WIRE));
  c.rect(0, 13, c.w, 1, ix(P.WIRE));
  for (let x = 24; x < c.w; x += 48) {
    const lean = x === 120 ? 1 : 0;
    for (let y = 5; y < 20; y++) {
      const px = x + (y < 10 ? lean : 0);
      c.px(px, y, ix(P.WOOD + 1));
      c.px(px + 1, y, ix(P.WOOD + 3));
    }
    c.px(x, 5, ix(P.WOOD + 2));
  }
  // A white marker post with a dark band, once a tile.
  c.rect(146, 8, 3, 13, ix(P.PAINT + 1));
  c.rect(146, 10, 3, 2, ix(P.WIRE));
  blades(c, { rows: [11, 13, 15, 17, 19, 21, 23, 25], density: 0.32, seed: seed ^ 0x88, frame: f, frames: 4, base: P.GRASS + 2, spread: 3, maxH: 5 });
  // A few taller seed stalks along the fence.
  const rnd = mulberry32(seed ^ 0x89);
  for (let i = 0; i < 16; i++) {
    const x = Math.floor(rnd() * c.w);
    const h = 6 + Math.floor(rnd() * 5);
    const phase = rnd();
    const lean = Math.round(Math.sin((f / 4 + phase) * Math.PI * 2));
    for (let j = 0; j < h; j++) c.px(x + Math.round((lean * j) / h), 15 - j, ix(P.GRASS + 6));
    c.px(x + lean, 15 - h, ix(P.CROP + 2));
  }
  return c;
}

/** 240 x 16: grass and wildflowers, wind frame f of 4. */
export function vergeNearPlane(seed, f) {
  const c = new Canvas(240, 16, { wrapX: true });
  for (let y = 0; y < c.h; y++) {
    for (let x = 0; x < c.w; x++) c.px(x, y, ix(P.GRASS + clamp(4 - (y >> 2), 1, 4)));
  }
  blades(c, { rows: [2, 4, 6, 8, 10, 12, 14, 15], density: 0.34, seed: seed ^ 0x99, frame: f, frames: 4, base: P.GRASS + 2, spread: 3.5, maxH: 4 });
  const rnd = mulberry32(seed ^ 0x9a);
  const colours = [P.PAINT + 1, P.CROP + 2, P.ROOF + 3, P.PAINT + 1, P.CROP + 2];
  for (let i = 0; i < 22; i++) {
    const x = Math.floor(rnd() * c.w);
    const y = 3 + Math.floor(rnd() * 11);
    const phase = rnd();
    const pick = colours[Math.floor(rnd() * colours.length)];
    const lean = Math.round(Math.sin((f / 4 + phase) * Math.PI * 2) * 0.8);
    c.px(x, y, ix(P.GRASS + 3));
    c.px(x + lean, y - 1, ix(P.GRASS + 4));
    c.px(x + lean, y - 2, ix(pick));
    if (i % 3 === 0) c.px(x + lean + 1, y - 2, ix(pick));
  }
  return c;
}

/** 960 x 34: grass clumps, seed heads and stones in the near foreground, wind frame f of 2. */
export function foregroundPlane(seed, f) {
  const c = new Canvas(960, 34, { wrapX: true });
  const rnd = mulberry32(seed ^ 0xaa);
  for (let i = 0; i < 46; i++) {
    const cx = Math.floor(rnd() * c.w);
    const w = 12 + Math.floor(rnd() * 34);
    const tall = 6 + Math.floor(rnd() * 12);
    const stone = rnd() < 0.24;
    // The seam stays on bare bank, so tiles meet without a cut clump.
    if (cx < w / 2 + 6 || cx > c.w - w / 2 - 6) continue;
    const stems = Math.round(w * 0.9);
    for (let k = 0; k < stems; k++) {
      const u = (k + rnd()) / stems;
      const x = cx - w / 2 + u * w;
      const edge = Math.sin(Math.PI * u) ** 0.7;
      const h = Math.max(2, Math.round(tall * edge * (0.55 + rnd() * 0.45)));
      const lean = (u - 0.5) * 4 + ((f === 1 ? 1 : -1) * (h > 7 ? 1 : 0)) * (rnd() < 0.8 ? 1 : 0);
      const tone = rnd();
      for (let j = 0; j <= h; j++) {
        const t = j / h;
        c.px(x + Math.round(lean * t), c.h - 1 - j, ix(P.GRASS + clamp(Math.round(t * 2.4 + tone * 1.4 - 0.2), 0, 4)));
      }
    }
    if (stone) {
      const sw = 5 + Math.floor(rnd() * 6);
      const sx = cx + Math.floor(rnd() * 8) - 4;
      for (let j = 0; j < 4; j++) {
        for (let k = j; k < sw - j; k++) {
          const lit = k > sw * 0.55 && j > 1;
          c.px(sx + k, c.h - 1 - j, ix(P.EARTH + (lit ? 4 : j > 1 ? 2 : 1)));
        }
      }
    }
  }
  return c;
}
