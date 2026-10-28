// Builds the geometry of one frame of Castellum Rotae v2 into a Raster: terrain, fort, the four
// rotae, the junction crossbar, the five stations and four build pads, the moat and bridge with
// the tar shield, the attackers' camp and siege engines.
import { v3, add, sub, mul, norm, cross, deg, TAU, clamp } from './v3.mjs';
import { F_COLOR, F_SHADOW } from './raster.mjs';
import { M } from './shade.mjs';
import * as W from './world.mjs';

export const WHEEL_X = [11, 26, 41, 56];
export const WHEEL_Y = 12;
export const WHEEL_R = 6;
export const WHEEL_HW = 1.3;
export const SHAFT_Z = 1;
// Output buses of the crossbar, in station order.
export const BUS_Y = [19, 22, 25, 28, 31];
export const ST = { MINE: 0, CATAPULT: 1, BALLISTA: 2, TAR: 3, ARROWS: 4 };
export const CATAPULT = v3(22, 44, 0);
export const BALLISTA = v3(2, 58, 15);
export const ARROWS = v3(82, 58, 15);
export const TAR_PUMP = v3(44, 58.5, 13);
const TAKEOFF_X = [64, 22, 6, 44, 78];
const TAKEOFF_STOP = [13, 41, 52, 53.5, 52];

export class Scene {
  // opts.routes[i]: the station wheel i drives (-1 none); opts.wheelAngle[i]; opts.armDeg.
  constructor(r, opts = {}) {
    this.r = r;
    this.routes = opts.routes ?? [ST.BALLISTA, ST.CATAPULT, ST.ARROWS, ST.TAR];
    this.wheelAngle = opts.wheelAngle ?? [0.3, 1.1, 2.0, 0.7];
    this.armDeg = opts.armDeg ?? 68;
    this.tar = opts.tar ?? 1;
    let s = 7;
    this.rand = () => {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      return s / 0x7fffffff;
    };
  }

  range(a, b) {
    return a + (b - a) * this.rand();
  }

  build() {
    this.terrain();
    this.water();
    this.fort();
    this.buildings();
    for (let i = 0; i < 4; i++) this.wheel(i);
    this.junction();
    this.catapult();
    this.ballista();
    this.arrowBattery();
    this.tarPump();
    this.mine();
    this.pads();
    this.bridgeAndTar();
    this.palisade();
    this.rocks();
    this.camp();
    this.siegeEngines();
  }

  // Box with yaw a about its base centre c; he = half extents (z extent rises from the base).
  ybox(c, a, he, mat, o = 0) {
    const u = v3(Math.cos(a), Math.sin(a), 0);
    const v = v3(-Math.sin(a), Math.cos(a), 0);
    this.r.obox(add(c, v3(0, 0, he.z)), u, v, v3(0, 0, 1), he, mat, o);
  }

  local(c, a, l) {
    return add(add(add(c, mul(v3(Math.cos(a), Math.sin(a), 0), l.x)), mul(v3(-Math.sin(a), Math.cos(a), 0), l.y)), v3(0, 0, l.z));
  }

  terrain() {
    const step = 2, x0 = -124, x1 = 230, y0 = -150, y1 = 196;
    const nx = Math.floor((x1 - x0) / step) + 1;
    const ny = Math.floor((y1 - y0) / step) + 1;
    const hs = new Float32Array(nx * ny);
    for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) hs[j * nx + i] = W.heightRaw(x0 + i * step, y0 + j * step);
    for (let j = 0; j < ny - 1; j++) {
      for (let i = 0; i < nx - 1; i++) {
        const x = x0 + i * step, y = y0 + j * step;
        const sp = this.r.project(v3(x + 1, y + 1, hs[j * nx + i]));
        if (sp.x < -40 || sp.x > this.r.w + 40 || sp.y > this.r.h + 40 || sp.y < -40 - Math.max(W.mountain(x + 1, y + 1), 0) * 0) continue;
        const p00 = v3(x, y, hs[j * nx + i]);
        const p10 = v3(x + step, y, hs[j * nx + i + 1]);
        const p01 = v3(x, y + step, hs[(j + 1) * nx + i]);
        const p11 = v3(x + step, y + step, hs[(j + 1) * nx + i + 1]);
        const mtn = W.mountain(x + 1, y + 1);
        if (mtn > 1.4) {
          const hc = (hs[j * nx + i] + hs[j * nx + i + 1] + hs[(j + 1) * nx + i] + hs[(j + 1) * nx + i + 1]) / 4;
          const jag = W.hash2(Math.floor(x / 2), Math.floor(y / 2));
          const steps = Math.round(hc / 2.5) + (jag > 0.88 ? 1 : jag < 0.08 ? -1 : 0);
          const hq = Math.max(steps * 2.5, 1.5);
          const lo = Math.min(hs[j * nx + i], hs[j * nx + i + 1], hs[(j + 1) * nx + i], hs[(j + 1) * nx + i + 1], hq) - 10;
          this.r.box(v3(x, y, lo), v3(x + step, y + step, hq), M.CLIFF, 3);
          continue;
        }
        const mat = W.inFort(x + 1, y + 1) && y >= 4 ? M.PAVE : M.TERRAIN;
        this.groundTri(p00, p10, p11, mat);
        this.groundTri(p00, p11, p01, mat);
      }
    }
  }

  groundTri(a, b, c, mat) {
    let n = norm(cross(sub(b, a), sub(c, a)));
    if (n.z < 0) n = mul(n, -1);
    // flat ground only receives shadows; the mountain and the banks cast them too
    const f = Math.max(a.z, b.z, c.z) > 1.2 ? F_COLOR | F_SHADOW : F_COLOR;
    this.r.tri(a, b, c, mat, 1, null, null, null, n, f);
  }

  water() {
    const z = W.WATER_Z;
    this.r.quad(v3(-18, 10, z), v3(102, 10, z), v3(102, 78, z), v3(-18, 78, z), M.WATER, 2, v3(0, 0, 1), F_COLOR);
  }

  merlonsX(x0, x1, y0, y1, z) {
    for (let x = x0 + 0.3; x + 0.8 <= x1; x += 1.7) this.r.box(v3(x, y0, z), v3(x + 0.8, y1, z + 1.1), M.WALL, 10, M.WALLTOP);
  }

  merlonsY(x0, x1, y0, y1, z) {
    for (let y = y0 + 0.3; y + 0.8 <= y1; y += 1.7) this.r.box(v3(x0, y, z), v3(x1, y + 0.8, z + 1.1), M.WALL, 10, M.WALLTOP);
  }

  tower(mn, mx, h, roof, banner = true) {
    const r = this.r;
    r.box(v3(mn.x, mn.y, 0), v3(mx.x, mx.y, h), M.WALL, 11, M.WALLTOP);
    r.box(v3(mn.x - 0.25, mn.y - 0.25, h - 2.2), v3(mx.x + 0.25, mx.y + 0.25, h - 1.8), M.WALL, 11, M.WALLTOP);
    if (roof) {
      r.pyramid({ x: mn.x - 0.6, y: mn.y - 0.6 }, { x: mx.x + 0.6, y: mx.y + 0.6 }, h, (mx.x - mn.x) * 0.55, M.ROOF, 12);
    } else {
      this.merlonsX(mn.x, mx.x, mx.y - 0.7, mx.y, h);
      this.merlonsY(mx.x - 0.7, mx.x, mn.y, mx.y - 0.7, h);
      this.merlonsX(mn.x, mx.x, mn.y, mn.y + 0.7, h);
      this.merlonsY(mn.x, mn.x + 0.7, mn.y + 0.7, mx.y - 0.7, h);
    }
    if (banner) {
      const cx = (mn.x + mx.x) / 2, yb = mx.y + 0.08;
      r.quad(v3(cx - 1, yb, h - 2.6), v3(cx + 1, yb, h - 2.6), v3(cx + 1, yb, h - 7), v3(cx - 1, yb, h - 7), M.BANNER, 13, v3(0, 1, 0));
    }
    for (let k = 0; k < 2; k++) {
      const sx = mn.x + (mx.x - mn.x) * (0.3 + 0.4 * k);
      r.quad(v3(sx - 0.15, mx.y + 0.03, h - 4), v3(sx + 0.15, mx.y + 0.03, h - 4), v3(sx + 0.15, mx.y + 0.03, h - 5.6), v3(sx - 0.15, mx.y + 0.03, h - 5.6), M.STONE_DARK, 11, v3(0, 1, 0));
      const sy = mn.y + (mx.y - mn.y) * (0.3 + 0.4 * k);
      r.quad(v3(mx.x + 0.03, sy + 0.15, h - 4), v3(mx.x + 0.03, sy - 0.15, h - 4), v3(mx.x + 0.03, sy - 0.15, h - 5.6), v3(mx.x + 0.03, sy + 0.15, h - 5.6), M.STONE_DARK, 11, v3(1, 0, 0));
    }
  }

  fort() {
    const r = this.r, wh = W.WALL_H, t = W.WALL_T;
    r.box(v3(0, 57, 0), v3(40, 60, wh), M.WALL, 10, M.WALLTOP);
    r.box(v3(48, 57, 0), v3(84, 60, wh), M.WALL, 10, M.WALLTOP);
    r.box(v3(0, 2, 0), v3(t, 57, wh), M.WALL, 10, M.WALLTOP);
    r.box(v3(84 - t, 6, 0), v3(84, 57, wh), M.WALL, 10, M.WALLTOP);
    r.box(v3(0, 2, 0), v3(60, 5, wh), M.WALL, 10, M.WALLTOP);
    this.merlonsX(0, 40, 59.3, 60, wh);
    this.merlonsX(48, 84, 59.3, 60, wh);
    this.merlonsY(83.3, 84, 6, 57, wh);
    this.merlonsY(0, 0.7, 2, 57, wh);
    this.merlonsX(0, 60, 2, 2.7, wh);
    this.tower({ x: -3, y: 53 }, { x: 7, y: 63 }, 15, false);
    this.tower({ x: 77, y: 53 }, { x: 87, y: 63 }, 15, false);
    this.tower({ x: 34, y: 55 }, { x: 40, y: 63 }, 13.5, true);
    this.tower({ x: 48, y: 55 }, { x: 54, y: 63 }, 13.5, true);
    this.tower({ x: 15, y: 56 }, { x: 21, y: 62 }, 12, false, false);
    this.tower({ x: 63, y: 56 }, { x: 69, y: 62 }, 12, false, false);
    this.tower({ x: -2, y: 27 }, { x: 5, y: 34 }, 12, false, false);
    this.tower({ x: 79, y: 31 }, { x: 86, y: 38 }, 12, false, false);
    this.tower({ x: -3, y: -1 }, { x: 6, y: 8 }, 14, true, false);
    // gatehouse block over the arch, the passage and the doors
    r.box(v3(40, 56, 6.8), v3(48, 62.5, 11.5), M.WALL, 10, M.WALLTOP);
    this.merlonsX(40, 48, 61.8, 62.5, 11.5);
    r.box(v3(40, 56, 0), v3(48, 60.6, 0.05), M.PAVE, 10);
    r.box(v3(40.2, 60.6, 0), v3(47.8, 61.2, 6.8), M.GATE, 14);
  }

  buildings() {
    const r = this.r;
    r.box(v3(4, 36, 0), v3(11, 50, 4.5), M.PLASTER, 15);
    r.gable({ x: 3.5, y: 35.5 }, { x: 11.5, y: 50.5 }, 4.5, 2.6, false, M.ROOF, M.PLASTER, 15);
    r.box(v3(70, 40, 0), v3(80, 49, 4), M.PLASTER, 15);
    r.gable({ x: 69.5, y: 39.5 }, { x: 80.5, y: 49.5 }, 4, 2.4, true, M.ROOF, M.PLASTER, 15);
    for (let i = 0; i < 6; i++) {
      const x = 60 + (i % 3) * 1.4, y = 44 + Math.floor(i / 3) * 1.4;
      r.box(v3(x, y, 0), v3(x + 1.1, y + 1.1, 1.1), M.WOOD_LIGHT, 16);
    }
    for (let i = 0; i < 4; i++) r.cylZ(v3(13 + i * 1.3, 52, 0), 0.55, 1.3, M.WOOD, 16, 8, M.WOOD_DARK);
    // tar barrels by the gate, a stable and a well on the east side, carts
    for (let i = 0; i < 6; i++) r.cylZ(v3(50 + (i % 3) * 1.3, 49 + Math.floor(i / 3) * 1.3, 0), 0.55, 1.3, M.WOOD_DARK, 16, 8, M.TAR);
    r.box(v3(66, 24, 0), v3(78, 31, 3.4), M.WOOD, 15);
    r.gable({ x: 65.5, y: 23.5 }, { x: 78.5, y: 31.5 }, 3.4, 2, true, M.ROOF, M.WOOD, 15);
    r.cylZ(v3(60, 36, 0), 1.2, 1, M.WALL, 16, 12, M.WATER);
    r.beam(v3(59, 36, 1), v3(59, 36, 3), 0.2, M.WOOD_DARK, 16);
    r.beam(v3(61, 36, 1), v3(61, 36, 3), 0.2, M.WOOD_DARK, 16);
    r.beam(v3(58.8, 36, 3), v3(61.2, 36, 3), 0.2, M.WOOD_DARK, 16);
    for (const [x, y] of [[30, 44], [56, 42]]) {
      r.box(v3(x, y, 0.5), v3(x + 1.8, y + 3, 1.4), M.WOOD, 17, M.ROCK);
      r.cyl(v3(x - 0.1, y + 0.7, 0.55), v3(x + 1.9, y + 0.7, 0.55), 0.5, M.WOOD_DARK, 17, 8);
      r.cyl(v3(x - 0.1, y + 2.3, 0.55), v3(x + 1.9, y + 2.3, 0.55), 0.5, M.WOOD_DARK, 17, 8);
    }
  }

  // --- rotae ------------------------------------------------------------------------------

  wheel(i) {
    const r = this.r;
    const c = v3(WHEEL_X[i], WHEEL_Y, WHEEL_R + 1.4);
    const acc = M.ACC0 + i;
    const ang = this.wheelAngle[i];
    const R = WHEEL_R, hw = WHEEL_HW, o = 30 + i;
    const segN = 28;
    const segL = (TAU * R) / segN;
    const spokes = [8, 12, 6, 10][i];
    const Y = v3(0, 1, 0);
    for (const side of [-1, 1]) {
      const yy = c.y + hw * side;
      const cc = v3(c.x, yy, c.z);
      for (let s = 0; s < segN; s++) {
        const am = ang + (TAU * (s + 0.5)) / segN;
        const rad = v3(Math.cos(am), 0, Math.sin(am));
        const tan = v3(-Math.sin(am), 0, Math.cos(am));
        let mat = side > 0 ? acc : M.WOOD;
        if (i === 3 && s % 4 === 0) mat = M.IRON;
        r.obox(add(cc, mul(rad, R)), tan, Y, rad, { x: segL * 0.53, y: 0.22, z: 0.32 }, mat, o);
      }
      for (let k = 0; k < spokes; k++) {
        const a = ang + (TAU * k) / spokes;
        const tip = v3(c.x + Math.cos(a) * (R - 0.2), yy, c.z + Math.sin(a) * (R - 0.2));
        r.beam(cc, tip, 0.3, M.WOOD_DARK, o, Y);
        if (i === 1) {
          const a2 = a + TAU / spokes;
          const t2 = v3(c.x + Math.cos(a2) * R * 0.62, yy, c.z + Math.sin(a2) * R * 0.62);
          r.beam(add(cc, mul(sub(tip, cc), 0.85)), t2, 0.18, M.WOOD, o, Y);
        }
      }
      if (i === 2) {
        const n2 = 18;
        for (let s = 0; s < n2; s++) {
          const am = ang + (TAU * (s + 0.5)) / n2;
          const rad = v3(Math.cos(am), 0, Math.sin(am));
          r.obox(add(cc, mul(rad, R * 0.55)), v3(-Math.sin(am), 0, Math.cos(am)), Y, rad, { x: ((TAU * R * 0.55) / n2) * 0.53, y: 0.18, z: 0.2 }, M.BRONZE, o);
        }
      }
    }
    for (let s = 0; s < segN; s++) {
      const am = ang + (TAU * (s + 0.5)) / segN;
      const rad = v3(Math.cos(am), 0, Math.sin(am));
      const tan = v3(-Math.sin(am), 0, Math.cos(am));
      if (i === 1) {
        if (s % 2 === 0) r.obox(add(c, mul(rad, R + 0.05)), tan, Y, rad, { x: 0.14, y: hw, z: 0.14 }, M.WOOD_LIGHT, o);
      } else {
        r.obox(add(c, mul(rad, R - 0.42)), tan, Y, rad, { x: segL * 0.42, y: hw - 0.05, z: 0.07 }, M.WOOD_LIGHT, o);
      }
      if (i === 3 && s % 2 === 0) r.obox(add(c, mul(rad, R + 0.55)), rad, Y, tan, { x: 0.55, y: hw * 0.9, z: 0.06 }, M.WOOD, o);
    }
    r.cyl(v3(c.x, c.y - hw - 1.2, c.z), v3(c.x, c.y + hw + 1.2, c.z), 0.45, M.BRONZE, o, 8);
    r.cyl(v3(c.x, c.y - hw - 0.2, c.z), v3(c.x, c.y - hw + 0.2, c.z), 0.9, M.BRONZE, o, 10);
    r.cyl(v3(c.x, c.y + hw - 0.2, c.z), v3(c.x, c.y + hw + 0.2, c.z), 0.9, M.BRONZE, o, 10);
    for (const side of [-1, 1]) {
      const yy = c.y + (hw + 0.9) * side;
      r.beam(v3(c.x - 3.8, yy, 0), v3(c.x, yy, c.z), 0.45, M.WOOD_DARK, o);
      r.beam(v3(c.x + 3.8, yy, 0), v3(c.x, yy, c.z), 0.45, M.WOOD_DARK, o);
      r.box(v3(c.x - 4.4, yy - 0.3, 0), v3(c.x + 4.4, yy + 0.3, 0.45), M.WOOD_DARK, o);
    }
    // pennant in the rider's colour
    const mast = v3(c.x + 4.2, c.y + hw + 0.9, 0);
    r.beam(mast, add(mast, v3(0, 0, c.z + R + 2.5)), 0.22, M.WOOD_DARK, o);
    const top = add(mast, v3(0, 0, c.z + R + 2.4));
    r.tri(top, add(top, v3(2.6, 0.4, -0.7)), add(top, v3(0, 0, -1.5)), M.LIT0 + i, o);
    // radial output: hub -> gearbox at the front of the frame -> down to the shaft
    const gy = c.y + hw + 2.2;
    const lit = this.routes[i] >= 0;
    const sm = lit ? M.LIT0 + i : M.SHAFT;
    r.beam(v3(c.x, c.y + hw + 1.2, c.z), v3(c.x, gy, c.z), 0.35, sm, o);
    r.beam(v3(c.x, gy, c.z), v3(c.x, gy, SHAFT_Z), 0.35, sm, o);
    r.box(v3(c.x - 0.55, gy - 0.55, c.z - 0.55), v3(c.x + 0.55, gy + 0.55, c.z + 0.55), M.WOOD_DARK, o, M.BRONZE);
    r.box(v3(c.x - 0.7, gy - 0.7, 0), v3(c.x + 0.7, gy + 0.7, SHAFT_Z + 0.6), M.WOOD_DARK, o, M.BRONZE);
    r.beam(v3(c.x - 0.6, gy, 0), v3(c.x - 0.6, gy, c.z - 0.5), 0.18, M.WOOD_DARK, o);
    r.beam(v3(c.x + 0.6, gy, 0), v3(c.x + 0.6, gy, c.z - 0.5), 0.18, M.WOOD_DARK, o);
  }

  // --- junction crossbar -----------------------------------------------------------------

  junction() {
    const r = this.r, o = 40;
    const yIn = WHEEL_Y + WHEEL_HW + 2.2;
    for (let i = 0; i < 4; i++) {
      const x = WHEEL_X[i];
      const j = this.routes[i];
      const yStop = j >= 0 ? BUS_Y[j] : yIn;
      if (j >= 0) r.beam(v3(x, yIn, SHAFT_Z), v3(x, yStop, SHAFT_Z), 0.32, M.LIT0 + i, o);
      r.beam(v3(x, yStop, SHAFT_Z), v3(x, BUS_Y[4] + 0.8, SHAFT_Z), 0.32, M.SHAFT, o);
    }
    for (let j = 0; j < 5; j++) {
      const y = BUS_Y[j];
      const tx = TAKEOFF_X[j];
      const x0 = Math.min(WHEEL_X[0] - 1.5, tx);
      const x1 = Math.max(WHEEL_X[3] + 1.5, tx);
      const rider = this.routes.indexOf(j);
      const bz = SHAFT_Z + 0.55;
      if (rider >= 0) {
        const xs = WHEEL_X[rider];
        r.beam(v3(Math.min(xs, tx), y, bz), v3(Math.max(xs, tx), y, bz), 0.3, M.LIT0 + rider, o);
      }
      r.beam(v3(x0, y, bz), v3(x1, y, bz), 0.26, M.SHAFT, o);
      for (let x = x0; x <= x1; x += 5) r.box(v3(x - 0.15, y - 0.4, 0), v3(x + 0.15, y + 0.4, SHAFT_Z + 0.35), M.WOOD_DARK, o);
      const stopY = TAKEOFF_STOP[j];
      const m = rider >= 0 ? M.LIT0 + rider : M.SHAFT;
      if (j === ST.MINE) {
        r.beam(v3(tx, y, bz), v3(tx, stopY, bz), 0.3, m, o);
      } else {
        r.box(v3(tx - 0.5, y - 0.5, 0), v3(tx + 0.5, y + 0.5, 2.9), M.WOOD, o, M.BRONZE);
        r.beam(v3(tx, y, 2.6), v3(tx, stopY, 2.6), 0.3, m, o);
        for (let yy = y + 3; yy < stopY; yy += 4) {
          r.box(v3(tx - 0.12, yy - 0.12, 0), v3(tx + 0.12, yy + 0.12, 2.45), M.WOOD_DARK, o);
          r.box(v3(tx - 0.5, yy - 0.12, 2.25), v3(tx + 0.5, yy + 0.12, 2.45), M.WOOD_DARK, o);
        }
      }
    }
    for (let i = 0; i < 4; i++) {
      for (let j = 0; j < 5; j++) {
        const x = WHEEL_X[i], y = BUS_Y[j];
        const on = this.routes[i] === j;
        r.box(v3(x - 0.65, y - 0.65, 0), v3(x + 0.65, y + 0.65, SHAFT_Z + 1), M.WOOD_DARK, o, on ? M.BRONZE : M.IRON);
        const lt = v3(x + 0.9, y, SHAFT_Z + (on ? 2.6 : 1.6));
        r.beam(v3(x + 0.7, y, SHAFT_Z + 0.6), lt, 0.14, M.WOOD_LIGHT, o);
        if (on) r.box(sub(lt, v3(0.2, 0.2, 0.2)), add(lt, v3(0.2, 0.2, 0.2)), M.LIT0 + i, o);
      }
    }
    const jc = v3(33.5, 25, 0);
    r.box(add(jc, v3(-2.2, -2.2, 0)), add(jc, v3(2.2, 2.2, 2.6)), M.WOOD, o, M.WOOD_DARK);
    r.cylZ(add(jc, v3(0, 0, 2.6)), 1.9, 0.35, M.BRONZE, o, 16);
    for (let k = 0; k < 16; k++) {
      const a = (TAU * k) / 16;
      const p = add(jc, v3(Math.cos(a) * 2, Math.sin(a) * 2, 2.6));
      r.box(sub(p, v3(0.2, 0.2, 0)), add(p, v3(0.2, 0.2, 0.5)), M.BRONZE, o);
    }
  }

  // --- stations ---------------------------------------------------------------------------

  catapultPivot() {
    return add(CATAPULT, v3(0, -1.4, 1.4));
  }

  catapultTip() {
    const a = deg(this.armDeg);
    return add(this.catapultPivot(), v3(0, Math.cos(a) * 9, Math.sin(a) * 9));
  }

  catapult() {
    const r = this.r, c = CATAPULT, o = 50;
    for (const side of [-1, 1]) {
      const x = c.x + 1.6 * side;
      r.box(v3(x - 0.3, c.y - 3.5, 0.5), v3(x + 0.3, c.y + 3.5, 1.2), M.WOOD, o);
      r.cyl(v3(x + 0.35 * side, c.y - 2.6, 0.7), v3(x + 0.75 * side, c.y - 2.6, 0.7), 0.7, M.WOOD_DARK, o, 8);
      r.cyl(v3(x + 0.35 * side, c.y + 2.6, 0.7), v3(x + 0.75 * side, c.y + 2.6, 0.7), 0.7, M.WOOD_DARK, o, 8);
      r.beam(v3(x, c.y + 1.2, 1.2), v3(x, c.y + 0.6, 4.6), 0.35, M.WOOD, o);
      r.beam(v3(x, c.y + 2.6, 1.2), v3(x, c.y + 0.6, 4.6), 0.3, M.WOOD_DARK, o);
    }
    r.box(v3(c.x - 1.9, c.y - 3.3, 0.6), v3(c.x + 1.9, c.y - 2.7, 1.25), M.WOOD_DARK, o);
    r.box(v3(c.x - 1.9, c.y + 2.7, 0.6), v3(c.x + 1.9, c.y + 3.3, 1.25), M.WOOD_DARK, o);
    r.beam(v3(c.x - 1.9, c.y + 0.6, 4.6), v3(c.x + 1.9, c.y + 0.6, 4.6), 0.55, M.HIDE, o);
    const pivot = this.catapultPivot();
    r.cyl(v3(c.x - 1.6, pivot.y, pivot.z), v3(c.x + 1.6, pivot.y, pivot.z), 0.55, M.ROPE, o, 10);
    const tip = this.catapultTip();
    r.beam(pivot, tip, 0.55, M.WOOD_LIGHT, o, v3(1, 0, 0));
    r.box(sub(tip, v3(0.6, 0.6, 0.3)), add(tip, v3(0.6, 0.6, 0.2)), M.HIDE, o);
    r.cyl(v3(c.x - 1.3, c.y - 3, 1.6), v3(c.x + 1.3, c.y - 3, 1.6), 0.3, M.WOOD_DARK, o, 6);
    for (let k = 0; k < 5; k++) {
      const x = c.x + 3 + (k % 2) * 0.6, y = c.y - 1 + k * 0.5;
      r.box(v3(x, y, 0), v3(x + 0.5, y + 0.5, 0.5), M.ROCK, o);
    }
    r.cyl(v3(c.x - 0.3, c.y - 3.6, 1.6), v3(c.x + 0.3, c.y - 3.6, 1.6), 0.9, M.BRONZE, o, 10);
  }

  ballistaAim() {
    return Math.atan2(42, -12);
  }

  ballista() {
    const r = this.r, b = BALLISTA, o = 51, k = 1.8;
    const a = this.ballistaAim();
    const L = (base, l) => this.local(base, a, mul(l, k));
    r.cylZ(b, 3.6, 0.4, M.WOOD_DARK, o, 14);
    this.ybox(add(b, v3(0, 0, 0.4)), a, { x: 0.5 * k, y: 0.5 * k, z: 0.9 * k }, M.WOOD, o);
    const base = add(b, v3(0, 0, 0.4 + 1.6 * k));
    const back = L(base, v3(-2.4, 0, 0));
    const front = L(base, v3(2.6, 0, 0.35));
    r.beam(back, front, 0.38 * k, M.WOOD_LIGHT, o);
    const fr = L(base, v3(1.8, 0, 0.2));
    for (const side of [-1, 1]) {
      const sp = L(fr, v3(0, 0.75 * side, -0.6));
      r.cyl(sp, add(sp, v3(0, 0, 1.4 * k)), 0.26 * k, M.ROPE, o, 8);
      r.beam(L(fr, v3(0, 0, -0.65)), L(fr, v3(0, side, -0.65)), 0.2 * k, M.BRONZE, o);
      r.beam(L(fr, v3(0, 0, 0.8)), L(fr, v3(0, side, 0.8)), 0.2 * k, M.BRONZE, o);
      const armTip = L(fr, v3(0.6, 2.6 * side, 0.1));
      r.beam(L(fr, v3(0, 0.75 * side, 0.1)), armTip, 0.2 * k, M.WOOD_DARK, o);
      r.line3(armTip, L(base, v3(2.2, 0, 0.45)), [0.85, 0.78, 0.63]);
    }
    r.cyl(L(back, v3(0.3, -0.7, 0)), L(back, v3(0.3, 0.7, 0)), 0.18 * k, M.WOOD_DARK, o, 6);
    for (let q = 0; q < 4; q++) {
      const p = add(b, v3(-2.6 + q * 0.4, -2.6, 0.45));
      r.beam(p, add(p, v3(0, 3.4, 0)), 0.14, M.WOOD_LIGHT, o);
    }
    this.ballistaMuzzle = L(base, v3(2.6, 0, 0.45));
  }

  arrowBattery() {
    const r = this.r, b = ARROWS, o = 52, k = 1.7;
    const a = Math.atan2(42, -6);
    r.cylZ(b, 3.6, 0.4, M.WOOD_DARK, o, 14);
    this.ybox(add(b, v3(0, 0, 0.4)), a, { x: 1 * k, y: 1.4 * k, z: 0.6 * k }, M.WOOD, o);
    const tilt = deg(42);
    const fwd = v3(Math.cos(a) * Math.cos(tilt), Math.sin(a) * Math.cos(tilt), Math.sin(tilt));
    const side = v3(-Math.sin(a), Math.cos(a), 0);
    let upv = norm(cross(fwd, side));
    if (upv.z < 0) upv = mul(upv, -1);
    const center = add(b, v3(0, 0, 1.4 + 1.3 * k));
    r.obox(center, fwd, side, upv, { x: 1.5 * k, y: 1.6 * k, z: 0.55 * k }, M.WOOD_LIGHT, o);
    for (let row = 0; row < 4; row++) for (let cm = 0; cm < 5; cm++) {
      const m = add(add(add(center, mul(side, (-1.2 + cm * 0.6) * k)), mul(upv, (-0.35 + row * 0.25) * k)), mul(fwd, 1.52 * k));
      r.point(m, [0.16, 0.12, 0.09], 1);
      if ((row + cm) % 2 === 0) r.point(add(m, mul(fwd, 0.5)), [0.85, 0.85, 0.8], 1);
    }
    // the magazine drum that feeds the troughs
    r.cyl(add(b, v3(1.2 * k, -1.8 * k, 1.6 * k)), add(b, v3(1.2 * k, -1.2 * k, 1.6 * k)), 0.9 * k, M.WOOD_DARK, o, 12);
    r.cyl(add(b, v3(1.2 * k, -1.85 * k, 1.6 * k)), add(b, v3(1.2 * k, -1.75 * k, 1.6 * k)), 0.95 * k, M.BRONZE, o, 12);
    this.batteryMouth = add(center, mul(fwd, 1.6 * k));
    r.box(add(b, v3(-1.4 * k, -1.6 * k, 1)), add(b, v3(0, -0.4 * k, 3.4 * k)), M.WOOD, o, M.WOOD_DARK);
    r.cyl(add(b, v3(-1.5 * k, -0.1, 1.2 * k)), add(b, v3(-1.5 * k, 0.5 * k, 1.2 * k)), 0.7 * k, M.BRONZE, o, 10);
    r.beam(add(b, v3(-1.2 * k, -0.2, 1.2 * k)), sub(center, mul(fwd, k)), 0.16 * k, M.IRON, o);
  }

  tarPump() {
    const r = this.r, p = TAR_PUMP, o = 53;
    r.cylZ(v3(p.x - 2.2, p.y - 1.8, p.z - 1.95), 1.6, 2.2, M.WOOD, o, 12, M.TAR);
    for (let k = 0; k < 3; k++) r.cylZ(v3(p.x - 2.2, p.y - 1.8, p.z - 1.75 + k * 0.75), 1.65, 0.16, M.IRON, o, 12);
    const pv = v3(p.x + 1.2, p.y - 1.6, p.z + 1.6);
    r.beam(v3(p.x + 0.2, p.y - 1.6, p.z - 2), pv, 0.25, M.WOOD_DARK, o);
    r.beam(v3(p.x + 2.2, p.y - 1.6, p.z - 2), pv, 0.25, M.WOOD_DARK, o);
    r.beam(add(pv, v3(-3, 0, 0.5)), add(pv, v3(2.4, 0, -0.4)), 0.3, M.WOOD_LIGHT, o);
    r.beam(add(pv, v3(-3, 0, 0.5)), add(pv, v3(-3.2, -0.2, -1.6)), 0.15, M.IRON, o);
    r.cyl(v3(p.x + 3.6, p.y - 2.2, p.z - 1), v3(p.x + 3.6, p.y - 1, p.z - 1), 0.6, M.BRONZE, o, 10);
    r.beam(v3(p.x - 0.8, p.y - 1.8, p.z - 1), v3(p.x - 0.8, p.y + 3.2, p.z - 1), 0.32, M.IRON, o);
    r.beam(v3(p.x - 3.8, p.y + 3.2, p.z - 1), v3(p.x + 3.8, p.y + 3.2, p.z - 1), 0.32, M.IRON, o);
    // machicolation (spout gallery) on corbels along the gate's front face
    r.box(v3(40.2, 62.5, 9.6), v3(47.8, 63.6, 10.6), M.WOOD_DARK, o, M.WOOD);
    for (let k = 0; k < 5; k++) {
      const x = 40.8 + k * 1.6;
      r.box(v3(x, 62.5, 9), v3(x + 0.4, 63.4, 9.6), M.WALL, o);
    }
  }

  mine() {
    const r = this.r, o = 54, cx = 72;
    r.quad(v3(cx - 3.2, 5.6, 6), v3(cx + 3.2, 5.6, 6), v3(cx + 3.2, 5.6, 0), v3(cx - 3.2, 5.6, 0), M.CAVE, o, v3(0, 1, 0));
    r.box(v3(cx - 3.6, 5.4, 0), v3(cx - 3, 6.2, 6.4), M.WOOD_DARK, o);
    r.box(v3(cx + 3, 5.4, 0), v3(cx + 3.6, 6.2, 6.4), M.WOOD_DARK, o);
    r.box(v3(cx - 3.9, 5.3, 6), v3(cx + 3.9, 6.3, 6.8), M.WOOD_DARK, o);
    const hf = v3(66, 12, 0);
    for (const dx of [-1.4, 1.4]) for (const dy of [-1.4, 1.4]) r.beam(add(hf, v3(dx, dy, 0)), add(hf, v3(dx * 0.4, dy * 0.4, 11)), 0.3, M.WOOD, o);
    r.box(add(hf, v3(-1, -1, 10.6)), add(hf, v3(1, 1, 11)), M.WOOD_DARK, o);
    const pul = add(hf, v3(0, 0, 11.6));
    for (let s = 0; s < 14; s++) {
      const a = (TAU * s) / 14, a2 = (TAU * (s + 1)) / 14;
      r.beam(add(pul, v3(Math.cos(a) * 1.4, 0, Math.sin(a) * 1.4)), add(pul, v3(Math.cos(a2) * 1.4, 0, Math.sin(a2) * 1.4)), 0.16, M.WOOD_DARK, o, v3(0, 1, 0));
    }
    r.beam(add(pul, v3(-1.4, 0, 0)), add(pul, v3(1.4, 0, 0)), 0.12, M.WOOD_DARK, o);
    r.beam(add(pul, v3(0, 0, -1.4)), add(pul, v3(0, 0, 1.4)), 0.12, M.WOOD_DARK, o);
    const chainA = v3(cx - 1.5, 6.5, 1);
    r.line3(chainA, add(pul, v3(1.4, 0, 0)), [0.23, 0.21, 0.2]);
    r.line3(add(pul, v3(-1.4, 0, 0)), add(hf, v3(-3, 1, 4)), [0.23, 0.21, 0.2]);
    for (let k = 0; k < 8; k++) {
      const q = add(chainA, mul(sub(add(pul, v3(1.4, 0, 0)), chainA), k / 8));
      r.box(sub(q, v3(0.25, 0.25, 0.25)), add(q, v3(0.25, 0.25, 0.1)), M.WOOD_LIGHT, o, M.GOLD);
    }
    const sm = v3(59, 13, 0);
    r.box(add(sm, v3(-2.5, -1, 0)), add(sm, v3(2.5, 1, 1.2)), M.WOOD_DARK, o, M.MINE_DIRT);
    r.box(add(sm, v3(-2.7, -0.3, 0)), add(sm, v3(-2.3, 0.3, 6)), M.WOOD, o);
    r.box(add(sm, v3(2.3, -0.3, 0)), add(sm, v3(2.7, 0.3, 6)), M.WOOD, o);
    r.box(add(sm, v3(-2.7, -0.4, 5.6)), add(sm, v3(2.7, 0.4, 6.1)), M.WOOD_DARK, o);
    r.cyl(add(sm, v3(-2.5, 0.6, 4.2)), add(sm, v3(2.5, 0.6, 4.2)), 0.25, M.IRON, o, 6);
    for (let k = 0; k < 4; k++) {
      const x = sm.x - 1.8 + k * 1.2;
      const lift = [0.2, 1.1, 0.5, 1.4][k];
      r.box(v3(x - 0.2, sm.y - 0.2, 1.3 + lift), v3(x + 0.2, sm.y + 0.2, 5.4), M.WOOD_LIGHT, o);
      r.box(v3(x - 0.35, sm.y - 0.35, 1.2 + lift), v3(x + 0.35, sm.y + 0.35, 1.9 + lift), M.IRON, o);
    }
    for (const rail of [-0.5, 0.5]) r.beam(v3(cx - 1 + rail, 6.4, 0.1), v3(cx - 1 + rail, 20, 0.1), 0.12, M.IRON, o);
    for (let k = 0; k < 2; k++) {
      const cy = 10 + k * 4.5;
      r.box(v3(cx - 2, cy, 0.4), v3(cx, cy + 2.4, 1.6), M.WOOD, o, M.GOLD);
      r.box(v3(cx - 1.8, cy + 0.2, 1.55), v3(cx - 0.2, cy + 2.2, 1.95), M.GOLD, o);
    }
    for (let k = 0; k < 9; k++) {
      const gx = 62 + (k % 3) * 0.7, gy = 17 + Math.floor(k / 3) * 0.6;
      const gh = 0.9 - Math.abs((k % 3) - 1) * 0.35 - Math.abs(Math.floor(k / 3) - 1) * 0.3;
      r.box(v3(gx, gy, 0), v3(gx + 0.7, gy + 0.6, gh), M.GOLD, o);
    }
    r.cyl(add(sm, v3(2.8, 0.6, 4.2)), add(sm, v3(3.3, 0.6, 4.2)), 1, M.BRONZE, o, 10);
  }

  pads() {
    const r = this.r;
    const pads = [v3(18, 59, 12), v3(66, 59, 12), v3(1.5, 30.5, 12), v3(82.5, 34.5, 12)];
    pads.forEach((p, k) => {
      r.cylZ(p, 1.6, 0.35, M.MARBLE, 60 + k, 12);
      if (k === 1) {
        this.ybox(add(p, v3(0, 0, 0.35)), deg(110), { x: 0.5, y: 0.5, z: 0.5 }, M.WOOD, 61);
        r.beam(add(p, v3(0.6, -0.6, 1.4)), add(p, v3(-0.5, 1.6, 1.6)), 0.2, M.WOOD_LIGHT, 61);
        r.beam(add(p, v3(-0.9, 0.6, 1.5)), add(p, v3(0.6, 1.2, 1.5)), 0.14, M.WOOD_DARK, 61);
      }
    });
  }

  bridgeAndTar() {
    const r = this.r, o = 70;
    const y0 = W.BRIDGE_Y0 + 1.2, y1 = W.BRIDGE_Y1;
    r.box(v3(40.4, y0, -0.15), v3(47.6, y1, 0.3), M.WOOD, o);
    for (const y of [64, 68, 72]) for (const x of [40.6, 47]) r.box(v3(x, y, -3), v3(x + 0.5, y + 0.5, -0.15), M.WOOD_DARK, o);
    for (const x of [40.4, 47.3]) {
      for (let y = y0 + 1; y < y1; y += 2.5) r.box(v3(x, y, 0.3), v3(x + 0.25, y + 0.25, 1.3), M.WOOD_DARK, o);
      r.box(v3(x, y0 + 1, 1.2), v3(x + 0.25, y1, 1.4), M.WOOD_DARK, o);
    }
    if (this.tar <= 0) return;
    // the tar shield: a curtain pouring from the spout gallery over the arch, and the coat it
    // leaves on the bridge, thinning toward the bridgehead
    r.quad(v3(40.0, 63.8, 9.6), v3(48.0, 63.8, 9.6), v3(48.0, 63.8, 0.32), v3(40.0, 63.8, 0.32), M.TAR_FALL, 71, v3(0, 1, 0));
    r.quad(v3(40.0, 64.6, 0.32), v3(48.0, 64.6, 0.32), v3(48.0, 63.8, 0.32), v3(40.0, 63.8, 0.32), M.TAR, 71, v3(0, 0, 1), F_COLOR);
    let k = 0;
    for (let y = 61.4; y < 72.5; y += 1) {
      const shrink = clamp((y - 66) / 6.5, 0, 1) * 2.4;
      const wob = (W.hash2(k, 3) - 0.5) * 0.8;
      r.quad(v3(40.6 + shrink + wob, y, 0.33), v3(47.4 - shrink + wob * 0.5, y, 0.33), v3(47.4 - shrink + wob * 0.5, y + 1, 0.33), v3(40.6 + shrink + wob, y + 1, 0.33), M.TAR, 71, v3(0, 0, 1), F_COLOR);
      k++;
    }
  }

  palisade() {
    for (let x = -2; x < 86; x += 0.75) if (x < 39 || x > 49) this.stake(v3(x, 62.8 + W.hash2(Math.floor(x * 3), 1) * 0.4, 0), v3(0, 0.25, 1));
    for (let y = 34; y < 62; y += 0.75) this.stake(v3(86.6 + W.hash2(Math.floor(y * 3), 2) * 0.4, y, 0), v3(0.25, 0, 1));
    for (let y = 14; y < 62; y += 0.75) this.stake(v3(-6.4, y, 0), v3(-0.25, 0, 1));
  }

  stake(base, lean) {
    const h = 2 + W.hash2(Math.floor(base.x * 7), Math.floor(base.y * 7)) * 0.6;
    this.r.beam(base, add(base, mul(norm(lean), h)), 0.32, M.WOOD, 72);
  }

  rocks() {
    for (let k = 0; k < 70; k++) {
      const p = { x: this.range(90, 160), y: this.range(30, 120) };
      if (W.roadAt(p.x, p.y) > 0.1 || W.fortDistance(p.x, p.y) < 15) continue;
      this.rock(p, this.range(0.6, 2.2));
    }
    for (let k = 0; k < 60; k++) {
      const p = { x: this.range(-110, -10), y: this.range(-40, 60) };
      if (W.fortDistance(p.x, p.y) < 16) continue;
      this.rock(p, this.range(0.6, 2.6));
    }
    for (let k = 0; k < 40; k++) {
      const p = { x: this.range(-60, 30), y: this.range(50, 100) };
      if (W.roadAt(p.x, p.y) > 0.1 || W.fortDistance(p.x, p.y) < 15) continue;
      this.rock(p, this.range(0.5, 1.6));
    }
  }

  rock(p, s) {
    const z = W.height(p.x, p.y);
    const a = this.range(0, TAU);
    const tilt = this.range(-0.3, 0.3);
    const u = norm(v3(Math.cos(a), Math.sin(a), tilt * 0.3));
    const w = norm(v3(-Math.sin(a) * tilt, Math.cos(a) * tilt, 1));
    const v = norm(cross(w, u));
    this.r.obox(v3(p.x, p.y, z + s * 0.35), u, v, w, { x: s * 0.7, y: s * 0.55, z: s * 0.45 }, M.ROCK, 80);
  }

  camp() {
    const r = this.r;
    const tents = [[18, 128], [24, 134], [14, 138], [28, 142], [8, 130], [20, 148], [4, 142], [32, 152]];
    for (const [x, y] of tents) {
      const z = W.height(x, y);
      const big = W.hash2(x, y) > 0.5;
      const hx = big ? 2.2 : 1.6, hy = big ? 1.6 : 1.2;
      r.gable({ x: x - hx, y: y - hy }, { x: x + hx, y: y + hy }, z, big ? 2.2 : 1.7, true, M.LINEN, M.LINEN, 81);
    }
    for (let k = 0; k < 3; k++) {
      const c = v3(34 + k * 3, 132 + k * 2, 0);
      c.z = W.height(c.x, c.y);
      r.box(c, add(c, v3(1.6, 2.6, 1)), M.WOOD, 82);
      r.cyl(add(c, v3(-0.1, 0.6, 0.4)), add(c, v3(1.7, 0.6, 0.4)), 0.45, M.WOOD_DARK, 82, 6);
    }
  }

  siegeEngines() {
    this.siegeTower(0, 24, 1);
    this.siegeTower(0, 46, 0.85);
    this.ram({ x: 44, y: 72.5 }, Math.PI * 1.5, 0.45);
    const p = W.roadPoint(1, 24);
    const d = W.roadDir(1, 24);
    this.ram(p, Math.atan2(-d.y, -d.x));
  }

  siegeTower(road, s, scale) {
    const r = this.r;
    const p = W.roadPoint(road, s);
    const d = W.roadDir(road, s);
    const a = Math.atan2(-d.y, -d.x);
    const c = v3(p.x, p.y, W.height(p.x, p.y) + 0.8);
    const h = 15 * scale, hw = 3 * scale;
    for (let k = 0; k < 3; k++) {
      const f0 = k / 3;
      const w0 = hw * (1 - f0 * 0.25);
      this.ybox(add(c, v3(0, 0, h * f0)), a, { x: w0, y: w0, z: h / 6 }, k % 2 === 0 ? M.HIDE : M.WOOD, 83);
      this.ybox(add(c, v3(0, 0, h * (f0 + 1 / 3) - 0.3)), a, { x: w0 + 0.15, y: w0 + 0.15, z: 0.15 }, M.WOOD_DARK, 83);
    }
    const top = add(c, v3(0, 0, h));
    const tw = hw * 0.75;
    for (const side of [-1, 1]) this.ybox(this.local(top, a, v3(0, tw * side, 0)), a, { x: tw, y: 0.12, z: 0.6 }, M.WOOD_DARK, 83);
    r.beam(this.local(top, a, v3(tw, -tw, 0.1)), this.local(top, a, v3(tw + 0.6, -tw, 3.2)), 0.2, M.WOOD, 83);
    r.beam(this.local(top, a, v3(tw, tw, 0.1)), this.local(top, a, v3(tw + 0.6, tw, 3.2)), 0.2, M.WOOD, 83);
    this.ybox(this.local(top, a, v3(tw + 0.35, 0, 0)), a, { x: 0.12, y: tw, z: 1.7 }, M.WOOD_LIGHT, 83);
    const vy = v3(-Math.sin(a), Math.cos(a), 0);
    for (const lx of [-hw * 0.7, hw * 0.7]) for (const side of [-1, 1]) {
      const wc = this.local(c, a, v3(lx, (hw + 0.2) * side, 0.1));
      r.cyl(sub(wc, mul(vy, 0.25)), add(wc, mul(vy, 0.25)), 0.9 * scale, M.WOOD_DARK, 83, 8);
    }
  }

  ram(p, a, zFixed = null) {
    const r = this.r;
    const c = v3(p.x, p.y, zFixed ?? W.height(p.x, p.y) + 0.3);
    this.ybox(add(c, v3(0, 0, 0.5)), a, { x: 3.6, y: 1.6, z: 0.9 }, M.WOOD, 84);
    const u = v3(Math.cos(a), Math.sin(a), 0);
    const v = v3(-Math.sin(a), Math.cos(a), 0);
    const rz = c.z + 2.3;
    const ridge0 = add(add(c, mul(u, -3.8)), v3(0, 0, 3.6));
    const ridge1 = add(add(c, mul(u, 3.8)), v3(0, 0, 3.6));
    for (const side of [-1, 1]) {
      const e0 = add(add(c, mul(u, -3.8)), mul(v, 1.9 * side));
      const e1 = add(add(c, mul(u, 3.8)), mul(v, 1.9 * side));
      e0.z = rz;
      e1.z = rz;
      r.quad(ridge0, ridge1, e1, e0, M.HIDE, 84);
    }
    r.cyl(add(add(c, mul(u, 1)), v3(0, 0, 1.6)), add(add(c, mul(u, 5.2)), v3(0, 0, 1.6)), 0.4, M.WOOD_LIGHT, 84, 8);
    r.cyl(add(add(c, mul(u, 5.1)), v3(0, 0, 1.6)), add(add(c, mul(u, 5.6)), v3(0, 0, 1.6)), 0.5, M.IRON, 84, 8);
    for (const lx of [-2.4, 2.4]) for (const side of [-1, 1]) {
      const wc = add(add(add(c, mul(u, lx)), mul(v, 1.75 * side)), v3(0, 0, 0.55));
      r.cyl(sub(wc, mul(v, 0.2)), add(wc, mul(v, 0.2)), 0.6, M.WOOD_DARK, 84, 8);
    }
  }
}
