// The map of Castellum Rotae v2 (metres): the fort on flat ground, its back wall built into a
// mountain with a gold vein at the mine, a moat on the other three sides, one bridge to the only
// gate, and one long road from the attackers' camp. Hashed integer noise: renders are identical.
import { clamp, lerp, smoothstep, dist2 } from './v3.mjs';

export const FORT_MIN = { x: 0, y: 2 };
export const FORT_MAX = { x: 84, y: 60 };
export const WALL_T = 3;
export const WALL_H = 9;
export const MOAT_IN = 4;
export const MOAT_OUT = 14;
export const MOAT_DEPTH = 3.2;
export const WATER_Z = -1.4;
export const BRIDGE_Y0 = 60;
export const BRIDGE_Y1 = 76;
export const PLAZA = { x: 44, y: 81 };
export const MINE = { x: 72, y: 4.5, z: 3 };
export const ROAD_HALF = 2.0;
// The mockup camera: pixels per metre and the screen position of the world origin.
export const CAMERA = { k: 3.5, ox: 450, oy: 127 };

// One long road that snakes from the attackers' camp (top left, off screen) down the west side,
// around an outcrop and an oasis, across the foreground in two hairpins and up a straight
// final run to the bridgehead. Placed in screen pixels for the mockup camera, kept in metres.
const ROAD_SCREEN = [
  [-30, 60], [60, 85], [130, 130], [80, 190], [50, 240], [40, 300], [110, 345], [40, 430],
  [200, 500], [400, 505], [440, 470], [330, 440], [200, 415], [233, 390],
];
const toWorld = ([sx, sy]) => {
  const d = (sx - CAMERA.ox) / CAMERA.k;
  const sm = (sy - CAMERA.oy) / (CAMERA.k / 2);
  return [(sm + d) / 2, (sm - d) / 2];
};
const ROAD_CTRL = [...ROAD_SCREEN.map(toWorld), [44, 92], [44, 79]];

// Catmull-Rom through the control points, sampled every metre or so, plaza end first.
function spline(ctrl, step = 1) {
  const p = ctrl.map(([x, y]) => ({ x, y })).reverse();
  const out = [];
  for (let i = 0; i < p.length - 1; i++) {
    const p0 = p[Math.max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[Math.min(i + 2, p.length - 1)];
    const n = Math.max(Math.ceil(Math.hypot(p2.x - p1.x, p2.y - p1.y) / step), 1);
    for (let k = 0; k < n; k++) {
      const t = k / n, t2 = t * t, t3 = t2 * t;
      const f = (a, b, c, d) => 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
      out.push({ x: f(p0.x, p1.x, p2.x, p3.x), y: f(p0.y, p1.y, p2.y, p3.y) });
    }
  }
  out.push(p[p.length - 1]);
  return out;
}

export const ROADS = [spline(ROAD_CTRL)];

export function roadLength(r = 0) {
  let l = 0;
  for (let i = 0; i < ROADS[r].length - 1; i++) l += dist2(ROADS[r][i], ROADS[r][i + 1]);
  return l;
}

const GRID_MIN = { x: -130, y: -90 };
const GRID_MAX = { x: 220, y: 200 };
const GRID_RES = 0.5;
let road = null;
let roadSGrid = null;
let gw = 0;
let gh = 0;
let hc = null;
let hw = 0;
let hh = 0;

export function hash2(ix, iy) {
  let n = (Math.imul(ix | 0, 374761393) + Math.imul(iy | 0, 668265263)) | 0;
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  n ^= n >>> 16;
  return (n & 0xffffff) / 16777215;
}

export const hash3 = (ix, iy, iz) => hash2(ix + Math.imul(iz | 0, 912931), iy - Math.imul(iz | 0, 271));

export function vnoise(x, y) {
  const ix = Math.floor(x);
  const iy = Math.floor(y);
  let fx = x - ix;
  let fy = y - iy;
  fx = fx * fx * (3 - 2 * fx);
  fy = fy * fy * (3 - 2 * fy);
  const a = lerp(hash2(ix, iy), hash2(ix + 1, iy), fx);
  const b = lerp(hash2(ix, iy + 1), hash2(ix + 1, iy + 1), fx);
  return lerp(a, b, fy);
}

export function fbm(x, y, oct = 4) {
  let s = 0, amp = 0.5, f = 1, nrm = 0;
  for (let i = 0; i < oct; i++) {
    s += vnoise(x * f + i * 17.3, y * f - i * 9.1) * amp;
    nrm += amp;
    amp *= 0.5;
    f *= 2;
  }
  return s / nrm;
}

export function fortDistance(x, y) {
  const dx = Math.max(FORT_MIN.x - x, x - FORT_MAX.x, 0);
  const dy = Math.max(FORT_MIN.y - y, y - FORT_MAX.y, 0);
  return Math.sqrt(dx * dx + dy * dy);
}

export const inFort = (x, y) => x >= FORT_MIN.x && x <= FORT_MAX.x && y >= FORT_MIN.y && y <= FORT_MAX.y;

// Gullies: dark clefts running down the massif toward the fort (x positions with a wiggle).
const GULLIES = [18, 48, 80];
export function gully(x, y) {
  let g = 0;
  for (const gx of GULLIES) {
    const cx = gx + Math.sin(y * 0.15 + gx) * 3 - y * 0.12;
    g = Math.max(g, 1 - clamp(Math.abs(x - cx) / 3.2, 0, 1));
  }
  return g;
}

// The massif behind the fort. Inside the fort's width the courtyard ends at a quarried cut face
// 11 m tall (y 4..5); above and behind it the rock rises in big masses toward the top right,
// terraced with steps of 3-12 m whose risers dominate, cut by gullies, and falling away to
// scree at either end.
export function mountain(x, y) {
  const back = Math.max(4.2 - y, 0);
  const span = smoothstep(-46, -16, x) * (1 - smoothstep(88, 106, x));
  const t = back * span;
  if (t <= 0) return 0;
  const inQuarry = x > 2 && x < 82;
  if (inQuarry && t < 0.5) return 11;
  let h = (inQuarry ? 11 : 0) + Math.min(t * 1.7, 34) * (0.55 + 0.9 * fbm(x * 0.025 + 3, y * 0.03 - 5, 3));
  h *= 0.75 + 0.45 * smoothstep(-20, 90, x);
  h += (1 - Math.abs(2 * vnoise(x * 0.03, y * 0.03) - 1)) * Math.min(h, 16) * 0.45;
  // gullies cut down the face (not into the quarry rim)
  h -= gully(x, y) * 5 * smoothstep(2, 10, t);
  const step = 3 + 9 * vnoise(x * 0.04 + 9, y * 0.04);
  const f = h / step;
  const fl = Math.floor(f);
  const terr = (fl + smoothstep(0.35, 1, f - fl)) * step;
  h = lerp(h, terr, 0.75);
  const rim = inQuarry ? 11 : 0;
  return Math.max(h, rim) * (inQuarry ? 1 : smoothstep(0, 3, t));
}

// The dry wadi east of the fort, running to the bottom-right corner (0..1 at its bed).
export function wadi(x, y) {
  const a = { x: 108, y: 70 }, b = { x: 175, y: 150 };
  const abx = b.x - a.x, aby = b.y - a.y;
  const t = clamp(((x - a.x) * abx + (y - a.y) * aby) / (abx * abx + aby * aby), 0, 1);
  const cx = a.x + abx * t + Math.sin(t * 9) * 5, cy = a.y + aby * t - Math.sin(t * 9) * 4;
  const half = 0.6 + t * 3.4;
  return 1 - clamp((Math.hypot(x - cx, y - cy) - half) / 3, 0, 1);
}

export function heightRaw(x, y) {
  if (x >= FORT_MIN.x && x <= FORT_MAX.x && y > 4.01 && y <= FORT_MAX.y) return 0;
  let h = (fbm(x * 0.05, y * 0.05, 3) - 0.5) * 0.8;
  // low dunes in the open desert, away from the fort and the road
  const far = smoothstep(16, 40, fortDistance(x, y));
  const dune = Math.sin(x * 0.07 + y * 0.04 + fbm(x * 0.015, y * 0.015, 3) * 9);
  h += far * (Math.max(dune, -0.3) + 0.3) * 1.3 * vnoise(x * 0.012 + 3, y * 0.012);
  h += mountain(x, y);
  h -= wadi(x, y) * 1.6;
  const d = fortDistance(x, y);
  const moatSide = (y > 14 || x < 0 || x > 84) && y > 4;
  const outer = MOAT_OUT + (vnoise(x * 0.08, y * 0.08) - 0.5) * 3;
  if (moatSide && d > MOAT_IN - 1 && d < outer + 1) {
    const e = Math.min(smoothstep(MOAT_IN - 1, MOAT_IN + 2, d), 1 - smoothstep(outer - 2, outer + 1, d));
    h -= MOAT_DEPTH * e;
  }
  const r = roadAt(x, y);
  h = lerp(h, Math.min(h, 0) - 0.08, r * 0.8);
  return h;
}

export function build() {
  gw = Math.floor((GRID_MAX.x - GRID_MIN.x) / GRID_RES);
  gh = Math.floor((GRID_MAX.y - GRID_MIN.y) / GRID_RES);
  road = new Float32Array(gw * gh);
  roadSGrid = new Float32Array(gw * gh).fill(1e9);
  for (const poly of ROADS) {
    let s0 = 0;
    for (let i = 0; i < poly.length - 1; i++) {
      stampSegment(poly[i], poly[i + 1], ROAD_HALF, s0);
      s0 += dist2(poly[i], poly[i + 1]);
    }
  }
  stampSegment({ x: 44, y: 74 }, { x: 44, y: 82 }, ROAD_HALF);
  hw = GRID_MAX.x - GRID_MIN.x + 1;
  hh = GRID_MAX.y - GRID_MIN.y + 1;
  hc = new Float32Array(hw * hh);
  for (let j = 0; j < hh; j++) for (let i = 0; i < hw; i++) hc[j * hw + i] = heightRaw(GRID_MIN.x + i, GRID_MIN.y + j);
}

function stampSegment(a, b, half, s0 = 0) {
  const pad = half + 2;
  const gx0 = Math.max(Math.floor((Math.min(a.x, b.x) - pad - GRID_MIN.x) / GRID_RES), 0);
  const gx1 = Math.min(Math.floor((Math.max(a.x, b.x) + pad - GRID_MIN.x) / GRID_RES), gw - 1);
  const gy0 = Math.max(Math.floor((Math.min(a.y, b.y) - pad - GRID_MIN.y) / GRID_RES), 0);
  const gy1 = Math.min(Math.floor((Math.max(a.y, b.y) + pad - GRID_MIN.y) / GRID_RES), gh - 1);
  const abx = b.x - a.x, aby = b.y - a.y;
  const l2 = Math.max(abx * abx + aby * aby, 1e-6);
  for (let gy = gy0; gy <= gy1; gy++) {
    for (let gx = gx0; gx <= gx1; gx++) {
      const px = GRID_MIN.x + gx * GRID_RES;
      const py = GRID_MIN.y + gy * GRID_RES;
      const t = clamp(((px - a.x) * abx + (py - a.y) * aby) / l2, 0, 1);
      const d = Math.hypot(px - (a.x + abx * t), py - (a.y + aby * t));
      const wob = (vnoise(px * 0.35, py * 0.35) - 0.5) * 1.6;
      const v = clamp((half + wob * 0.12 - d) / 0.7 + 0.5, 0, 1);
      const i = gy * gw + gx;
      if (v > road[i]) road[i] = v;
      if (v > 0 && s0 + t * Math.sqrt(l2) < roadSGrid[i]) roadSGrid[i] = s0 + t * Math.sqrt(l2);
    }
  }
}

export function roadAt(x, y) {
  if (!road) return 0;
  const gx = Math.floor((x - GRID_MIN.x) / GRID_RES);
  const gy = Math.floor((y - GRID_MIN.y) / GRID_RES);
  if (gx < 0 || gy < 0 || gx >= gw || gy >= gh) return 0;
  return road[gy * gw + gx];
}

// Arc length (m from the bridgehead) of the road at x, y (1e9 off the road).
export function roadS(x, y) {
  if (!roadSGrid) return 1e9;
  const gx = Math.floor((x - GRID_MIN.x) / GRID_RES);
  const gy = Math.floor((y - GRID_MIN.y) / GRID_RES);
  if (gx < 0 || gy < 0 || gx >= gw || gy >= gh) return 1e9;
  return roadSGrid[gy * gw + gx];
}

export function height(x, y) {
  const fx = x - GRID_MIN.x;
  const fy = y - GRID_MIN.y;
  const i = Math.floor(fx);
  const j = Math.floor(fy);
  if (!hc || i < 0 || j < 0 || i >= hw - 1 || j >= hh - 1) return heightRaw(x, y);
  const tx = fx - i, ty = fy - j;
  const a = lerp(hc[j * hw + i], hc[j * hw + i + 1], tx);
  const b = lerp(hc[(j + 1) * hw + i], hc[(j + 1) * hw + i + 1], tx);
  return lerp(a, b, ty);
}

// The gold-bearing band (0 none, 1 core): one band along a stratum across the quarry face and
// the rock over the mine mouth, gently wavy, nowhere else.
export function vein(p) {
  const d = Math.hypot(p.x - MINE.x, (p.y - MINE.y) * 0.8);
  if (d > 22) return 0;
  const zc = 6.5 + (p.x - MINE.x) * 0.12 + (vnoise(p.x * 0.08, p.y * 0.08) - 0.5) * 2;
  const core = 1 - clamp(Math.abs(p.z - zc) / 0.75, 0, 1);
  return core * (1 - clamp((d - 14) / 8, 0, 1));
}

// A point on a road by arc length (m) from the plaza end, and the direction there.
export function roadPoint(r, s) {
  const poly = ROADS[r];
  let left = s;
  for (let i = 0; i < poly.length - 1; i++) {
    const l = dist2(poly[i], poly[i + 1]);
    if (left <= l) {
      const t = left / l;
      return { x: poly[i].x + (poly[i + 1].x - poly[i].x) * t, y: poly[i].y + (poly[i + 1].y - poly[i].y) * t };
    }
    left -= l;
  }
  return poly[poly.length - 1];
}

export function roadDir(r, s) {
  const a = roadPoint(r, s - 1);
  const b = roadPoint(r, s + 1);
  const l = Math.hypot(b.x - a.x, b.y - a.y) || 1;
  return { x: (b.x - a.x) / l, y: (b.y - a.y) / l };
}
