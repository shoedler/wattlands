// The map of Castellum Rotae v2 (metres): the fort on flat ground, its back wall built into a
// mountain with gold veins, a moat on the other three sides, one bridge to the only gate, and
// three dry dirt roads meeting at the bridgehead. Hashed integer noise: renders are identical.
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
export const MINE = { x: 72, y: 3, z: 3 };
export const ROAD_HALF = 2.8;

export const ROADS = [
  [[44, 78], [32, 85], [16, 92], [-2, 101], [-22, 112], [-50, 126], [-90, 140]],
  [[44, 78], [45, 92], [42, 108], [45, 126], [51, 146], [56, 175]],
  [[44, 78], [60, 87], [76, 97], [92, 109], [108, 125], [124, 146]],
].map((r) => r.map(([x, y]) => ({ x, y })));

const GRID_MIN = { x: -130, y: -90 };
const GRID_MAX = { x: 220, y: 200 };
const GRID_RES = 0.5;
let road = null;
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

// The mountain behind the back wall and the spur beside the right wall: a cliff behind the
// mine, peaks from large-scale noise, ridges, and terraced rock ledges.
export function mountain(x, y) {
  const back = Math.max(5 - y, 0);
  const spur = Math.max(x - 89, 0) * clamp((36 - y) / 14, 0, 1);
  const t = Math.max(back, spur * 0.9);
  if (t <= 0) return 0;
  const cliff = smoothstep(46, 60, x) * (1 - smoothstep(92, 104, x));
  let h = Math.min(t * (1.15 + 1.6 * cliff), 13 + 9 * cliff + t * 0.45);
  const peaks = fbm(x * 0.028 + 3, y * 0.028 - 5, 4);
  h *= 0.55 + 1.0 * peaks;
  const rid = 1 - Math.abs(2 * vnoise(x * 0.07, y * 0.07) - 1);
  h += rid * Math.min(h, 12) * 0.45;
  h += (vnoise(x * 0.33, y * 0.33) - 0.5) * Math.min(h, 8) * 0.5;
  const step = 3.4;
  const f = h / step;
  const fl = Math.floor(f);
  const terr = (fl + smoothstep(0.5, 1, f - fl)) * step;
  return lerp(h, terr, 0.7) * smoothstep(0, 2.5, t);
}

export function heightRaw(x, y) {
  if (x >= FORT_MIN.x && x <= FORT_MAX.x && y >= 5 && y <= FORT_MAX.y) return 0;
  let h = (fbm(x * 0.05, y * 0.05, 3) - 0.5) * 0.8;
  // low dunes in the open desert, away from the fort and the roads
  const far = smoothstep(16, 40, fortDistance(x, y));
  const dune = Math.sin(x * 0.11 + y * 0.05 + fbm(x * 0.02, y * 0.02, 2) * 6);
  h += far * (Math.max(dune, -0.3) + 0.3) * 1.6;
  h += mountain(x, y);
  const d = fortDistance(x, y);
  const moatSide = (y > 14 || x < 0) && !(x > 86 && y < 34);
  if (moatSide && d > MOAT_IN - 1 && d < MOAT_OUT + 1) {
    const e = Math.min(smoothstep(MOAT_IN - 1, MOAT_IN + 2, d), 1 - smoothstep(MOAT_OUT - 2, MOAT_OUT + 1, d));
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
  for (const poly of ROADS) for (let i = 0; i < poly.length - 1; i++) stampSegment(poly[i], poly[i + 1], ROAD_HALF);
  stampSegment(PLAZA, { x: PLAZA.x + 0.01, y: PLAZA.y }, 7.5);
  stampSegment({ x: 44, y: 74 }, { x: 44, y: 80 }, 4.5);
  hw = GRID_MAX.x - GRID_MIN.x + 1;
  hh = GRID_MAX.y - GRID_MIN.y + 1;
  hc = new Float32Array(hw * hh);
  for (let j = 0; j < hh; j++) for (let i = 0; i < hw; i++) hc[j * hw + i] = heightRaw(GRID_MIN.x + i, GRID_MIN.y + j);
}

function stampSegment(a, b, half) {
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
      const v = clamp((half + wob - d) / 1.2 + 0.5, 0, 1);
      const i = gy * gw + gx;
      if (v > road[i]) road[i] = v;
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

// Gold vein strength at a rock point (0 none, 1 core): wavy seams along the strata and
// diagonal branches in the cliff over the mine, patchy so they glitter rather than draw lines.
const fr = (v) => v - Math.floor(v);
export function vein(p) {
  const d = Math.hypot(p.x - MINE.x, (p.y - MINE.y) * 0.9) + Math.abs(p.z - 10) * 0.3;
  if (d > 38) return 0;
  const w1 = fbm(p.x * 0.07, p.y * 0.07 + p.z * 0.04, 3) * 3.2;
  const w2 = vnoise(p.x * 0.05 + 7, p.z * 0.06) * 2.5;
  const s1 = Math.abs(fr(p.z * 0.26 + w1) - 0.5);
  const s2 = Math.abs(fr((p.x + p.y) * 0.11 + p.z * 0.17 + w2) - 0.5);
  const mask = vnoise(p.x * 0.11 + 3, p.y * 0.11 + p.z * 0.09);
  let core = mask > 0.3 ? 1 - clamp(s1 / 0.1, 0, 1) : 0;
  core = Math.max(core, mask > 0.45 ? (1 - clamp(s2 / 0.05, 0, 1)) * 0.85 : 0);
  return core * (1 - clamp((d - 16) / 22, 0, 1));
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
