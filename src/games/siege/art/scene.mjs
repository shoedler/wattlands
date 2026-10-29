// Builds the geometry of one frame of Castellum Rotae v2 into a Raster: terrain and the
// mountain, the Roman fort (travertine with brick courses, round corner towers, a twin-arched
// gatehouse, barracks rows and a small temple), the four rotae, the junction hall, the five
// stations and four build pads, the moat with a stone-arched bridge and the tar shield, the one
// road with its landmarks, the attackers' camp and siege engines.
import { v3, add, sub, mul, norm, cross, deg, TAU, clamp } from './v3.mjs';
import { F_COLOR, F_SHADOW } from './raster.mjs';
import { M } from './shade.mjs';
import * as W from './world.mjs';

export const WHEEL_X = [11, 26, 41, 56];
export const WHEEL_Y = 12;
export const WHEEL_R = 7;
export const WHEEL_HW = 1.6;
export const ST = { MINE: 0, CATAPULT: 1, BALLISTA: 2, TAR: 3, ARROWS: 4 };
export const CATAPULT = v3(30.2, 42, 0);
// The catapult throws toward the south-west (the bridge and the road), side-on to the camera.
const CAT_YAW = { ex: v3(Math.SQRT1_2, Math.SQRT1_2, 0), ey: v3(-Math.SQRT1_2, Math.SQRT1_2, 0) };
export const CAT_S = 2.1;
export const BALLISTA = v3(1, 59, 15);
export const ARROWS = v3(83, 59, 15);
export const TAR_PUMP = v3(44, 58.5, 13);
// The junction: a dark basalt floor with four lane shafts along x (one per rota, always turning
// in its rider's colour) and five station columns along y under them. A clutch drum at a
// crossing couples lane i to column j: the 4 x 5 grid shows every possible route at once.
const HALL = { x0: 5, x1: 64, y0: 16.5, y1: 29 };
export const LANE_Y = [18.8, 21.4, 24.0, 26.6];
const LANE_Z = 2.6;
const COL_Z = 1.3;
const OVER_Z = 4.4;
const GEAR_X = [60, 36, 17, 52, 47];
const LOW22 = Math.tan(deg(22));

export class Scene {
  // opts.routes[i]: the station wheel i drives (-1 none); opts.wheelAngle[i]; opts.armDeg.
  constructor(r, opts = {}) {
    this.r = r;
    this.routes = opts.routes ?? [ST.BALLISTA, ST.CATAPULT, ST.ARROWS, ST.TAR];
    this.wheelAngle = opts.wheelAngle ?? [0.3, 1.1, 2.0, 0.7];
    this.armDeg = opts.armDeg ?? 140;
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
    this.gatehouse();
    this.buildings();
    this.temple();
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
    this.landmarks();
    this.aqueduct();
    this.vicus();
    this.via();
    this.yardProps();
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

  // A cone (round tower roof): n triangles from the rim at z to the apex.
  cone(c, r, z, rise, mat, o = 0, sides = 14) {
    const apex = v3(c.x, c.y, z + rise);
    for (let i = 0; i < sides; i++) {
      const a0 = (TAU * i) / sides, a1 = (TAU * (i + 1)) / sides;
      const p0 = v3(c.x + Math.cos(a0) * r, c.y + Math.sin(a0) * r, z);
      const p1 = v3(c.x + Math.cos(a1) * r, c.y + Math.sin(a1) * r, z);
      const am = (a0 + a1) / 2;
      const n = norm(v3(Math.cos(am) * rise, Math.sin(am) * rise, r));
      const sl = Math.hypot(r, rise);
      this.r.tri(p0, p1, apex, mat, o, { x: r * a0, y: sl }, { x: r * a1, y: sl }, { x: r * am, y: 0 }, n);
    }
  }

  // --- ground -----------------------------------------------------------------------------

  terrain() {
    const step = 2, x0 = -124, x1 = 230, y0 = -150, y1 = 196;
    const nx = Math.floor((x1 - x0) / step) + 1;
    const ny = Math.floor((y1 - y0) / step) + 1;
    const hs = new Float32Array(nx * ny);
    for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) hs[j * nx + i] = W.heightRaw(x0 + i * step, y0 + j * step);
    for (let j = 0; j < ny - 1; j++) {
      for (let i = 0; i < nx - 1; i++) {
        const x = x0 + i * step, y = y0 + j * step;
        const h00 = hs[j * nx + i], h10 = hs[j * nx + i + 1], h01 = hs[(j + 1) * nx + i], h11 = hs[(j + 1) * nx + i + 1];
        const sp = this.r.project(v3(x + 1, y + 1, h00));
        if (sp.x < -40 || sp.x > this.r.w + 40 || sp.y > this.r.h + 40 || sp.y < -40) continue;
        if (y === 4 && x >= 0 && x < 84) {
          this.groundTri(v3(x, y, 0), v3(x + step, y, 0), v3(x + step, y + step, 0), M.PAVE);
          this.groundTri(v3(x, y, 0), v3(x + step, y + step, 0), v3(x, y + step, 0), M.PAVE);
          continue;
        }
        const mtn = Math.max(W.mountain(x, y), W.mountain(x + step, y + step)) > 1.4;
        const mat = mtn ? M.CLIFF : W.inFort(x + 1, y + 1) && y >= 4 ? M.PAVE : M.TERRAIN;
        this.groundTri(v3(x, y, h00), v3(x + step, y, h10), v3(x + step, y + step, h11), mat);
        this.groundTri(v3(x, y, h00), v3(x + step, y + step, h11), v3(x, y + step, h01), mat);
      }
    }
  }

  groundTri(a, b, c, mat) {
    let n = norm(cross(sub(b, a), sub(c, a)));
    if (n.z < 0) n = mul(n, -1);
    const f = Math.max(a.z, b.z, c.z) > 1.2 ? F_COLOR | F_SHADOW : F_COLOR;
    this.r.tri(a, b, c, mat, 1, null, null, null, n, f);
  }

  water() {
    const z = W.WATER_Z;
    this.r.quad(v3(-20, 0, z), v3(104, 0, z), v3(104, 80, z), v3(-20, 80, z), M.WATER, 2, v3(0, 0, 1), F_COLOR);
  }

  // --- fort -------------------------------------------------------------------------------

  // Rectangular merlons 1 m wide, 1.2 m tall with 0.7 m gaps, bright caps.
  merlonsX(x0, x1, y0, y1, z) {
    for (let x = x0 + 0.35; x + 1 <= x1; x += 1.7) this.r.box(v3(x, y0, z), v3(x + 1, y1, z + 1.2), M.MERLON, 10);
  }

  merlonsY(x0, x1, y0, y1, z) {
    for (let y = y0 + 0.35; y + 1 <= y1; y += 1.7) this.r.box(v3(x0, y, z), v3(x1, y + 1, z + 1.2), M.MERLON, 10);
  }

  merlonsRound(c, r, z) {
    const n = Math.floor((TAU * r) / 1.7);
    for (let i = 0; i < n; i++) {
      const a = (TAU * i) / n;
      const p = v3(c.x + Math.cos(a) * (r - 0.35), c.y + Math.sin(a) * (r - 0.35), z);
      this.r.box(sub(p, v3(0.45, 0.45, 0)), add(p, v3(0.45, 0.45, 1.2)), M.MERLON, 10);
    }
  }

  // A small dark arched window on a face (normal n), centre p.
  window(p, n) {
    const t = n.x !== 0 ? v3(0, 1, 0) : v3(1, 0, 0);
    const q = add(p, mul(n, 0.04));
    this.r.quad(add(add(q, mul(t, -0.22)), v3(0, 0, 0.45)), add(add(q, mul(t, 0.22)), v3(0, 0, 0.45)), add(add(q, mul(t, 0.22)), v3(0, 0, -0.45)), add(add(q, mul(t, -0.22)), v3(0, 0, -0.45)), M.STONE_DARK, 11, n);
  }

  squareTower(mn, mx, h, roof) {
    const r = this.r;
    r.box(v3(mn.x, mn.y, 0), v3(mx.x, mx.y, h), M.WALL, 11, M.WALLTOP);
    r.box(v3(mn.x - 0.2, mn.y - 0.2, h - 2.0), v3(mx.x + 0.2, mx.y + 0.2, h - 1.7), M.WALL, 11, M.CAP);
    if (roof) {
      const hw = (mx.x - mn.x) / 2 + 0.6;
      r.pyramid({ x: mn.x - 0.6, y: mn.y - 0.6 }, { x: mx.x + 0.6, y: mx.y + 0.6 }, h, hw * LOW22, M.ROOF, 12);
    } else {
      this.merlonsX(mn.x, mx.x, mx.y - 0.7, mx.y, h);
      this.merlonsY(mx.x - 0.7, mx.x, mn.y, mx.y - 0.7, h);
      this.merlonsX(mn.x, mx.x, mn.y, mn.y + 0.7, h);
      this.merlonsY(mn.x, mn.x + 0.7, mn.y + 0.7, mx.y - 0.7, h);
    }
    for (let k = 0; k < 2; k++) {
      const z = h - 4.2 - k * 3.6;
      if (z < 2) continue;
      this.window(v3((mn.x + mx.x) / 2, mx.y, z), v3(0, 1, 0));
      this.window(v3(mx.x, (mn.y + mx.y) / 2, z), v3(1, 0, 0));
    }
  }

  roundTower(c, rad, h, roof) {
    const r = this.r;
    r.cylZ(v3(c.x, c.y, 0), rad, h, M.ROUNDWALL, 11, 20, M.WALLTOP);
    r.cylZ(v3(c.x, c.y, h - 2.0), rad + 0.2, 0.3, M.ROUNDWALL, 11, 20, M.CAP);
    if (roof) this.cone(c, rad + 0.5, h, (rad + 0.5) * LOW22 * 1.3, M.ROOF, 12, 20);
    else this.merlonsRound(c, rad, h);
    for (const a of [deg(30), deg(75), deg(120)]) {
      const n = v3(Math.cos(a), Math.sin(a), 0);
      for (const z of [h - 4.5, h - 8.5]) {
        const p = add(v3(c.x, c.y, z), mul(n, rad + 0.03));
        const t = v3(-n.y, n.x, 0);
        r.quad(add(add(p, mul(t, -0.22)), v3(0, 0, 0.45)), add(add(p, mul(t, 0.22)), v3(0, 0, 0.45)), add(add(p, mul(t, 0.22)), v3(0, 0, -0.45)), add(add(p, mul(t, -0.22)), v3(0, 0, -0.45)), M.STONE_DARK, 11, n);
      }
    }
  }

  fort() {
    const r = this.r, wh = W.WALL_H, t = W.WALL_T;
    r.box(v3(0, 57, 0), v3(40, 60, wh), M.WALL, 10, M.WALLTOP);
    r.box(v3(48, 57, 0), v3(84, 60, wh), M.WALL, 10, M.WALLTOP);
    r.box(v3(0, 4, 0), v3(t, 57, wh), M.WALL, 10, M.WALLTOP);
    r.box(v3(84 - t, 4, 0), v3(84, 57, wh), M.WALL, 10, M.WALLTOP);
    // the courtyard's back is the quarried cut face of the massif, 11 m tall
    r.box(v3(t, 4, 0), v3(84 - t, 5, 11), M.QUARRY, 4, M.CLIFF);
    this.merlonsX(4, 40, 59.3, 60, wh);
    this.merlonsX(48, 80, 59.3, 60, wh);
    this.merlonsY(83.3, 84, 6, 54, wh);
    this.merlonsY(0, 0.7, 7, 54, wh);
    // round corner towers (ballista and arrow platforms, the back one roofed), square gate and
    // interval towers with low hip roofs or open tops for the pads
    this.roundTower(v3(1, 59, 0), 5.2, 15, false);
    this.roundTower(v3(83, 59, 0), 5.2, 15, false);
    this.squareTower({ x: 34, y: 55 }, { x: 40, y: 63 }, 13.5, true);
    this.squareTower({ x: 48, y: 55 }, { x: 54, y: 63 }, 13.5, true);
    this.squareTower({ x: 15, y: 56 }, { x: 21, y: 62 }, 12, false);
    this.squareTower({ x: 63, y: 56 }, { x: 69, y: 62 }, 12, false);
    this.squareTower({ x: -2, y: 27 }, { x: 5, y: 34 }, 12, false);
    this.squareTower({ x: 79, y: 31 }, { x: 86, y: 38 }, 12, false);
    // a row of shields hung on the front parapet either side of the gate
    for (const [a, b] of [[22, 33.5], [55, 62]]) {
      for (let x = a; x < b; x += 1.5) r.quad(v3(x, 60.04, 8.7), v3(x + 0.7, 60.04, 8.7), v3(x + 0.7, 60.04, 7.7), v3(x, 60.04, 7.7), M.SCUTUM, 13, v3(0, 1, 0));
    }
  }

  gatehouse() {
    const r = this.r;
    // block over the twin arches, its parapet, the arched front face, passage and doors
    r.box(v3(40, 56, 6.8), v3(48, 62.5, 11.5), M.WALL, 10, M.WALLTOP);
    this.merlonsX(40, 48, 61.8, 62.5, 11.5);
    r.quad(v3(40, 62.5, 6.8), v3(48, 62.5, 6.8), v3(48, 62.5, 0), v3(40, 62.5, 0), M.ARCH_GATE, 10, v3(0, 1, 0));
    r.box(v3(40, 56, 0), v3(48, 62.5, 0.05), M.PAVE, 10);
    r.box(v3(40.2, 60.6, 0), v3(47.8, 61.2, 5), M.GATE, 14);
    r.box(v3(43.6, 60.6, 0), v3(44.4, 62.4, 6.8), M.WALL, 10);
    // two vexilla on T-poles over the gatehouse
    for (const x of [41.5, 46.5]) this.vexillum(v3(x, 59.5, 11.5), 4.5);
  }

  vexillum(base, h) {
    const r = this.r;
    r.beam(base, add(base, v3(0, 0, h)), 0.16, M.WOOD_DARK, 13);
    const top = add(base, v3(0, 0, h - 0.2));
    r.beam(add(top, v3(-0.8, 0, 0)), add(top, v3(0.8, 0, 0)), 0.12, M.BRONZE, 13);
    r.quad(add(top, v3(-0.75, 0.05, -0.1)), add(top, v3(0.75, 0.05, -0.1)), add(top, v3(0.75, 0.05, -2.1)), add(top, v3(-0.75, 0.05, -2.1)), M.BANNER, 13, v3(0, 1, 0));
    r.point(add(top, v3(0, 0, 0.35)), [0.72, 0.58, 0.29], 1);
  }

  buildings() {
    const r = this.r;
    // one barracks row along the west side, a low tiled roof over a colonnaded porch
    {
      const x0 = 9.5;
      r.box(v3(x0, 35, 0), v3(x0 + 4.2, 49, 3.2), M.PLASTER, 15);
      r.gable({ x: x0 - 0.3, y: 34.6 }, { x: x0 + 5.6, y: 49.4 }, 3.2, 3 * LOW22, false, M.ROOF, M.PLASTER, 15);
      for (let y = 35.6; y < 49; y += 2.1) r.cylZ(v3(x0 + 5.2, y, 0), 0.18, 3.2, M.TEMPLE, 15, 6);
      for (let y = 37; y < 49; y += 4.2) this.window(v3(x0 + 4.2, y, 1.6), v3(1, 0, 0));
    }
    // tar barrels by the gate
    for (let i = 0; i < 6; i++) r.cylZ(v3(55.5 + (i % 3) * 1.3, 50 + Math.floor(i / 3) * 1.3, 0), 0.55, 1.3, M.WOOD_DARK, 16, 8, M.TAR);
    // a cistern and a cart
    r.box(v3(55, 34, 0), v3(58, 37, 1), M.WALL, 16, M.WATER);
    r.box(v3(38, 44, 0.5), v3(39.8, 47, 1.4), M.WOOD, 17, M.ROCK);
    r.cyl(v3(37.9, 44.7, 0.55), v3(39.9, 44.7, 0.55), 0.5, M.WOOD_DARK, 17, 8);
    r.cyl(v3(37.9, 46.3, 0.55), v3(39.9, 46.3, 0.55), 0.5, M.WOOD_DARK, 17, 8);
  }

  // A small temple (aedes) on a podium, pediment and six columns facing the gate.
  temple() {
    const r = this.r, o = 18;
    const x0 = 60, x1 = 72, y0 = 31, y1 = 45;
    r.box(v3(x0, y0, 0), v3(x1, y1, 1.2), M.WALL, o, M.WALLTOP);
    for (let k = 0; k < 3; k++) r.box(v3(x0 + 2, y1 + k * 0.5, 0), v3(x1 - 2, y1 + 0.5 + k * 0.5, 1.2 - k * 0.4), M.WALL, o, M.CAP);
    r.box(v3(x0 + 1, y0 + 1, 1.2), v3(x1 - 1, y1 - 4.5, 6.4), M.PLASTER, o);
    for (let k = 0; k < 6; k++) r.cylZ(v3(x0 + 1.3 + k * (x1 - x0 - 2.6) / 5, y1 - 0.8, 1.2), 0.32, 5.2, M.TEMPLE, o, 8);
    for (let k = 1; k < 4; k++) r.cylZ(v3(x1 - 0.8, y1 - 0.8 - k * 3, 1.2), 0.32, 5.2, M.TEMPLE, o, 8);
    r.box(v3(x0 + 0.6, y0 + 0.6, 6.4), v3(x1 - 0.6, y1 - 0.2, 7.2), M.TEMPLE, o);
    r.gable({ x: x0 + 0.3, y: y0 + 0.3 }, { x: x1 - 0.3, y: y1 + 0.1 }, 7.2, ((x1 - x0) / 2) * LOW22, false, M.ROOF, M.TEMPLE, o);
    this.vexillum(v3(x1 + 1.2, y1 + 1, 0), 6);
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
        let mat = acc;
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
      r.box(v3(c.x - 4.4, yy - 0.3, 0), v3(c.x + 4.4, yy + 0.3, 0.45), M.WALL, o);
    }
    const mast = v3(c.x + 4.2, c.y + hw + 0.9, 0);
    r.beam(mast, add(mast, v3(0, 0, c.z + R + 2.5)), 0.22, M.WOOD_DARK, o);
    const top = add(mast, v3(0, 0, c.z + R + 2.4));
    r.tri(top, add(top, v3(2.6, 0.4, -0.7)), add(top, v3(0, 0, -1.5)), M.LIT0 + i, o);
    // the output: hub -> bevel box -> down to an overpass at 4.4 m that crosses the lower lanes
    // and drops onto this wheel's own lane in the junction
    const gy = c.y + hw + 2.2;
    const sm = this.routes[i] >= 0 ? M.LIT0 + i : M.ACC0 + i;
    const ly = LANE_Y[i];
    r.beam(v3(c.x, c.y + hw + 1.2, c.z), v3(c.x, gy, c.z), 0.9, sm, o);
    r.box(v3(c.x - 0.7, gy - 0.7, c.z - 0.7), v3(c.x + 0.7, gy + 0.7, c.z + 0.7), M.WOOD_DARK, o, M.BRONZE);
    r.beam(v3(c.x, gy, c.z), v3(c.x, gy, OVER_Z), 0.9, sm, o);
    r.beam(v3(c.x, gy, OVER_Z), v3(c.x, ly, OVER_Z), 0.9, sm, o);
    r.beam(v3(c.x, ly, OVER_Z), v3(c.x, ly, LANE_Z), 0.9, sm, o);
    for (const y of [gy, ly]) r.box(v3(c.x - 0.6, y - 0.6, OVER_Z - 0.6), v3(c.x + 0.6, y + 0.6, OVER_Z + 0.6), M.BRONZE, o);
    for (const dx of [-1.4, 1.4]) r.beam(v3(c.x + dx, gy, 0), v3(c.x, gy, OVER_Z - 0.6), 0.35, M.WOOD_DARK, o);
    r.box(v3(c.x - 0.6, ly - 0.6, LANE_Z - 0.6), v3(c.x + 0.6, ly + 0.6, LANE_Z + 0.6), M.BRONZE, o);
  }

  // --- junction hall ----------------------------------------------------------------------

  // A station shaft along a 3D polyline: thick timber in the driving rider's colour (dark when
  // idle), on stone plinths every 5 m where it runs level, a bronze bevel box at each bend.
  shaft(pts, mat, o = 40) {
    const r = this.r;
    for (let i = 0; i < pts.length - 1; i++) {
      const a = pts[i], b = pts[i + 1];
      r.beam(a, b, 0.9, mat, o);
      const l = Math.hypot(b.x - a.x, b.y - a.y);
      if (Math.abs(b.z - a.z) < 0.1) {
        for (let t = 2.5; t < l - 1; t += 5) {
          const p = add(a, mul(sub(b, a), t / l));
          r.box(v3(p.x - 0.45, p.y - 0.45, 0), v3(p.x + 0.45, p.y + 0.45, p.z - 0.35), M.WALL, o, M.WALLTOP);
        }
      }
      if (i < pts.length - 2) {
        r.box(sub(b, v3(0.55, 0.55, 0.55)), add(b, v3(0.55, 0.55, 0.55)), M.WOOD_DARK, o, M.BRONZE);
        const d = norm(sub(b, a));
        r.cyl(add(b, mul(d, 0.55)), add(b, mul(d, 0.8)), 0.95, M.BRONZE, o, 14);
      }
    }
    const e = pts[pts.length - 1];
    r.box(sub(e, v3(0.6, 0.6, 0.6)), add(e, v3(0.6, 0.6, 0.6)), M.BRONZE, o);
  }

  junction() {
    const r = this.r, o = 40, h = HALL;
    r.box(v3(h.x0, h.y0, 0), v3(h.x1, h.y1, 0.5), M.WALL, o, M.BASALT);
    // the lanes on timber trestles, stone bearing blocks at both ends
    for (let i = 0; i < 4; i++) {
      const y = LANE_Y[i];
      r.beam(v3(h.x0 + 1, y, LANE_Z), v3(h.x1 - 1, y, LANE_Z), 0.5, M.SHAFT, o);
      const j = this.routes[i];
      if (j >= 0) r.beam(v3(Math.min(WHEEL_X[i], GEAR_X[j]), y, LANE_Z), v3(Math.max(WHEEL_X[i], GEAR_X[j]), y, LANE_Z), 0.9, M.LIT0 + i, o);
      for (let x = h.x0 + 4; x < h.x1 - 2; x += 7) r.box(v3(x - 0.25, y - 0.25, 0.5), v3(x + 0.25, y + 0.25, LANE_Z - 0.35), M.WOOD_DARK, o);
      for (const x of [h.x0 + 1, h.x1 - 1]) r.box(v3(x - 0.6, y - 0.6, 0.5), v3(x + 0.6, y + 0.6, LANE_Z + 0.6), M.WALL, o, M.BRONZE);
    }
    // the station columns under the lanes; at each crossing an iron collar, or, where a route is
    // engaged, a large clutch drum in the rider's colour with a bronze crown
    for (let j = 0; j < 5; j++) {
      const x = GEAR_X[j];
      const i0 = this.routes.indexOf(j);
      r.beam(v3(x, h.y0 + 0.4, COL_Z), v3(x, h.y1 - 0.4, COL_Z), 0.55, M.WOOD_DARK, o);
      if (i0 >= 0) {
        const ya = j === ST.MINE ? h.y0 + 0.4 : LANE_Y[i0], yb = j === ST.MINE ? LANE_Y[i0] : h.y1 - 0.4;
        r.beam(v3(x, ya, COL_Z), v3(x, yb, COL_Z), 0.9, M.LIT0 + i0, o);
      }
      for (let i = 0; i < 4; i++) {
        const y = LANE_Y[i];
        if (this.routes[i] === j) {
          r.cylZ(v3(x, y, COL_Z), 0.35, LANE_Z - COL_Z, M.IRON, o, 6);
          r.cylZ(v3(x, y, LANE_Z - 0.6), 1.55, 1.4, M.ACC0 + i, o, 16, M.ACC0 + i);
          r.cylZ(v3(x, y, LANE_Z + 0.8), 1.6, 0.14, M.WOOD_DARK, o, 16, M.ACC0 + i);
          for (let k = 0; k < 12; k++) {
            const a = (TAU * k) / 12;
            r.box(v3(x + Math.cos(a) * 1.6 - 0.2, y + Math.sin(a) * 1.6 - 0.2, LANE_Z + 0.8), v3(x + Math.cos(a) * 1.6 + 0.2, y + Math.sin(a) * 1.6 + 0.2, LANE_Z + 1.15), M.BRONZE, o);
          }
        } else {
          r.cylZ(v3(x, y, LANE_Z - 0.4), 0.55, 0.8, M.IRON, o, 8);
        }
      }
    }
    // outputs leave the floor toward each station; the tower stations climb on inclined shafts
    const lit = (j) => {
      const i = this.routes.indexOf(j);
      return i >= 0 ? M.LIT0 + i : M.SHAFT;
    };
    const C = COL_Z;
    this.shaft([v3(60, h.y0 + 0.4, C), v3(60, 15.4, C), v3(62.8, 15.4, C)], lit(ST.MINE));
    this.shaft([v3(36, h.y1 - 0.4, C), v3(36, 35.4, C)], lit(ST.CATAPULT));
    this.shaft([v3(17, h.y1 - 0.4, C), v3(17, 50, C), v3(4.3, 55.4, 15.2)], lit(ST.BALLISTA));
    this.shaft([v3(52, h.y1 - 0.4, C), v3(52, 50.5, C), v3(46.5, 56.4, 11.9)], lit(ST.TAR));
    this.shaft([v3(47, h.y1 - 0.4, C), v3(47, 30, C), v3(52, 30, C), v3(57, 30, 11), v3(78.2, 30, 11), v3(78.2, 54.4, 11), v3(79.7, 55.6, 15.2)], lit(ST.ARROWS));
  }

  pennant(base, h, mat, o) {
    this.r.beam(base, add(base, v3(0, 0, h)), 0.3, M.WOOD_DARK, o);
    const top = add(base, v3(0, 0, h - 0.1));
    this.r.tri(top, add(top, v3(3.6, 0.7, -1.0)), add(top, v3(0, 0, -2.3)), mat, o);
  }

  // A station's power marker: a ring of tiles in the driving rider's colour (dark when idle)
  // and, when powered, a pennant in that colour.
  stationMark(j, c, rad, flag = v3(0.7, -0.7, 0)) {
    const i = this.routes.indexOf(j);
    const mat = i >= 0 ? M.ACC0 + i : M.STONE_DARK;
    const n = Math.max(14, Math.round(rad * 5));
    for (let k = 0; k < n; k++) {
      const a = (TAU * k) / n;
      this.ybox(add(c, v3(Math.cos(a) * rad, Math.sin(a) * rad, 0)), a, { x: 0.5, y: ((TAU * rad) / n) * 0.4, z: 0.08 }, mat, 65);
    }
    if (i >= 0) this.pennant(add(c, mul(flag, rad)), 7, M.ACC0 + i, 65);
  }

  // --- stations ---------------------------------------------------------------------------

  // A point in the catapult's frame (x across, y toward the target, z up), scaled by CAT_S.
  catP(x, y, z) {
    const S = CAT_S, c = CATAPULT;
    return add(c, add(add(mul(CAT_YAW.ex, x * S), mul(CAT_YAW.ey, y * S)), v3(0, 0, z * S)));
  }

  catapultPivot() {
    return this.catP(0, -1.8, 1.8);
  }

  catapultTip(armDeg = this.armDeg) {
    const a = deg(armDeg);
    return this.catP(0, -1.8 + Math.cos(a) * 6.5, 1.8 + Math.sin(a) * 6.5);
  }

  // Where a stone leaves the sling (the arm against the crossbeam).
  catapultRelease() {
    return this.catapultTip(80);
  }

  catapult() {
    const r = this.r, c = CATAPULT, o = 50, S = CAT_S;
    const P = (x, y, z) => this.catP(x, y, z);
    const yaw = Math.atan2(CAT_YAW.ey.y, CAT_YAW.ey.x) - Math.PI / 2;
    const rail = (x0, y0, z0, x1, y1, z1, mat) => {
      const mid = this.catP((x0 + x1) / 2, (y0 + y1) / 2, z0);
      this.ybox(mid, yaw, { x: ((x1 - x0) / 2) * S, y: ((y1 - y0) / 2) * S, z: ((z1 - z0) / 2) * S }, mat, o);
    };
    this.stationMark(ST.CATAPULT, c, 9.6, v3(0.95, -0.3, 0));
    for (const side of [-1, 1]) {
      const x = 1.6 * side;
      rail(x - 0.3, -3.5, 0.5, x + 0.3, 3.5, 1.3, M.WOOD);
      for (const dy of [-2.6, 2.6]) r.cyl(P(x + 0.35 * side, dy, 0.9), P(x + 0.75 * side, dy, 0.9), 0.9 * S, M.WOOD_DARK, o, 12);
      r.beam(P(x, 1.2, 1.3), P(x, 0.6, 5.4), 0.42 * S, M.WOOD, o);
      r.beam(P(x, 2.8, 1.3), P(x, 0.6, 5.4), 0.35 * S, M.WOOD_DARK, o);
    }
    rail(-1.9, -3.4, 0.6, 1.9, -2.8, 1.3, M.WOOD_DARK);
    rail(-1.9, 2.8, 0.6, 1.9, 3.4, 1.3, M.WOOD_DARK);
    r.beam(P(-2.2, 0.6, 5.4), P(2.2, 0.6, 5.4), 0.7 * S, M.HIDE, o);
    const pivot = this.catapultPivot();
    r.cyl(P(-2, -1.8, 1.8), P(2, -1.8, 1.8), 0.42 * S, M.WOOD_DARK, o, 10);
    const tip = this.catapultTip();
    r.beam(pivot, tip, 0.55 * S, M.WOOD_LIGHT, o, v3(1, 0, 0));
    const sling = sub(tip, v3(0, 0, 2.2));
    r.line3(tip, sling, [0.62, 0.52, 0.38]);
    this.ybox(sub(sling, v3(0, 0, 0.4)), yaw, { x: 0.6, y: 0.6, z: 0.3 }, M.HIDE, o);
    r.cylZ(sub(sling, v3(0, 0, 0.1)), 0.45, 0.7, M.ROCK, o, 8);
    // the powered windlass across the back: a spur gear the input shaft turns, the rope to the arm
    r.cyl(P(-1.8, -3.9, 1.2), P(1.8, -3.9, 1.2), 0.3 * S, M.WOOD_DARK, o, 8);
    r.cyl(P(-0.25, -3.9, 1.2), P(0.25, -3.9, 1.2), 1.05 * S, M.BRONZE, o, 16);
    r.line3(P(0, -3.9, 1.5), add(pivot, mul(sub(tip, pivot), 0.25)), [0.62, 0.52, 0.38]);
    for (const side of [-1, 1]) rail(1.6 * side - 0.25, -4.2, 0, 1.6 * side + 0.25, -3.6, 1.5, M.WOOD_DARK);
  }

  ballistaAim() {
    return Math.atan2(40, -18);
  }

  ballista() {
    const r = this.r, b = BALLISTA, o = 51, k = 2.8;
    const a = this.ballistaAim();
    this.stationMark(ST.BALLISTA, b, 4.1, v3(-0.2, -0.95, 0));
    const L = (base, l) => this.local(base, a, mul(l, k));
    r.cylZ(b, 3.0, 0.4, M.WOOD_DARK, o, 16);
    this.ybox(add(b, v3(0, 0, 0.4)), a, { x: 0.5 * k, y: 0.5 * k, z: 1.25 * k }, M.WOOD, o);
    const base = add(b, v3(0, 0, 0.4 + 2.3 * k));
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
      r.line3(armTip, L(base, v3(-1.2, 0, 0.45)), [0.88, 0.85, 0.75]);
    }
    r.cyl(L(back, v3(0.3, -0.7, 0)), L(back, v3(0.3, 0.7, 0)), 0.18 * k, M.WOOD_DARK, o, 6);
    r.line3(L(base, v3(-1.2, 0, 0.5)), L(base, v3(3.4, 0, 0.5)), [0.3, 0.24, 0.18]);
    r.point(L(base, v3(3.4, 0, 0.5)), [0.75, 0.76, 0.8], 1);
    this.ballistaMuzzle = L(base, v3(2.6, 0, 0.45));
  }

  arrowBattery() {
    const r = this.r, b = ARROWS, o = 52, k = 2.6;
    const a = Math.atan2(26, -34);
    this.stationMark(ST.ARROWS, b, 4.1, v3(0.95, -0.2, 0));
    r.cylZ(b, 3.0, 0.4, M.WOOD_DARK, o, 16);
    const base = add(b, v3(0, 0, 0.4));
    const L = (l) => this.local(base, a, mul(l, k));
    // two A-frame trestles carry the rack on trunnions
    for (const side of [-1, 1]) {
      for (const dx of [-0.9, 0.9]) r.beam(L(v3(dx, 1.35 * side, 0)), L(v3(0, 1.35 * side, 1.7)), 0.22 * k, M.WOOD, o);
      r.beam(L(v3(-1, 1.35 * side, 0.1)), L(v3(1, 1.35 * side, 0.1)), 0.2 * k, M.WOOD_DARK, o);
    }
    // the rack: a slatted frame of 4 x 6 tubes raised 35 degrees, iron-banded, arrows bristling
    const tilt = deg(30);
    const fwd = v3(Math.cos(a) * Math.cos(tilt), Math.sin(a) * Math.cos(tilt), Math.sin(tilt));
    const side = v3(-Math.sin(a), Math.cos(a), 0);
    let upv = norm(cross(fwd, side));
    if (upv.z < 0) upv = mul(upv, -1);
    const center = L(v3(0, 0, 1.75));
    r.obox(center, fwd, side, upv, { x: 0.9 * k, y: 1.2 * k, z: 0.38 * k }, M.WOOD_DARK, o);
    for (const t of [-0.55, 0.55]) r.obox(add(center, mul(fwd, t * k)), fwd, side, upv, { x: 0.07 * k, y: 1.24 * k, z: 0.42 * k }, M.IRON, o);
    // the magazine: a bed of arrows on the rack's top, their heads bristling past the front
    for (let cm = 0; cm < 7; cm++) {
      const m = add(add(add(center, mul(side, (-0.96 + cm * 0.32) * k)), mul(upv, 0.42 * k)), mul(fwd, -0.8 * k));
      const tip = add(m, mul(fwd, 2.3 * k));
      r.line3(m, tip, [0.71, 0.6, 0.44]);
      r.point(tip, [0.2, 0.2, 0.23], 1);
      r.point(m, [0.95, 0.92, 0.86], 1);
    }
    // the drive: a bronze flywheel on the trunnion, turned by the shaft from the wall
    r.cyl(L(v3(0, 1.55, 1.7)), L(v3(0, 1.85, 1.7)), 0.85 * k, M.BRONZE, o, 14);
    r.cyl(L(v3(0, 1.3, 1.7)), L(v3(0, 2.0, 1.7)), 0.18 * k, M.IRON, o, 6);
  }

  tarPump() {
    const r = this.r, p = TAR_PUMP, o = 53;
    this.stationMark(ST.TAR, v3(44, 59.2, 11.5), 3.3, v3(0.95, 0.3, 0));
    r.cylZ(v3(p.x - 1.6, p.y - 1.3, p.z - 1.5), 2.6, 3.0, M.BRONZE, o, 18, M.TAR);
    for (let k = 0; k < 2; k++) r.cylZ(v3(p.x - 1.6, p.y - 1.3, p.z - 1.1 + k * 1.4), 2.66, 0.25, M.IRON, o, 18);
    const pv = v3(p.x + 1.2, p.y - 1.6, p.z + 1.6);
    r.beam(v3(p.x + 0.2, p.y - 1.6, p.z - 2), pv, 0.25, M.WOOD_DARK, o);
    r.beam(v3(p.x + 2.2, p.y - 1.6, p.z - 2), pv, 0.25, M.WOOD_DARK, o);
    r.beam(add(pv, v3(-3, 0, 0.5)), add(pv, v3(2.4, 0, -0.4)), 0.3, M.WOOD_LIGHT, o);
    r.beam(add(pv, v3(-3, 0, 0.5)), add(pv, v3(-3.2, -0.2, -1.6)), 0.15, M.IRON, o);
    r.cyl(v3(p.x + 3.6, p.y - 2.2, p.z - 1), v3(p.x + 3.6, p.y - 1, p.z - 1), 0.6, M.BRONZE, o, 10);
    r.beam(v3(p.x - 0.8, p.y - 1.8, p.z - 1), v3(p.x - 0.8, p.y + 3.2, p.z - 1), 0.32, M.IRON, o);
    r.beam(v3(p.x - 3.8, p.y + 3.2, p.z - 1), v3(p.x + 3.8, p.y + 3.2, p.z - 1), 0.32, M.IRON, o);
    // the spout gallery on corbels along the gate's front face
    r.box(v3(40.2, 62.5, 9.6), v3(47.8, 63.6, 10.6), M.WOOD_DARK, o, M.WOOD);
    for (let k = 0; k < 5; k++) {
      const x = 40.8 + k * 1.6;
      r.box(v3(x, 62.5, 9), v3(x + 0.4, 63.4, 9.6), M.WALL, o);
    }
  }

  mine() {
    const r = this.r, o = 54, cx = 72;
    // the mouth in the cliff, lamp-lit inside, under a timber portal
    r.quad(v3(cx - 2, 5.03, 5), v3(cx + 2, 5.03, 5), v3(cx + 2, 5.03, 0), v3(cx - 2, 5.03, 0), M.GLOWCAVE, o, v3(0, 1, 0));
    r.box(v3(cx - 2.6, 5, 0), v3(cx - 2, 5.8, 5.3), M.WOOD_DARK, o);
    r.box(v3(cx + 2, 5, 0), v3(cx + 2.6, 5.8, 5.3), M.WOOD_DARK, o);
    r.box(v3(cx - 2.9, 5, 5.0), v3(cx + 2.9, 5.9, 5.7), M.WOOD_DARK, o);
    // spoil heap beside the mouth
    for (let q = 0; q < 14; q++) {
      const gx = cx + 3.5 + (q % 4) * 0.8, gy = 6 + Math.floor(q / 4) * 0.8;
      r.box(v3(gx, gy, 0), v3(gx + 0.9, gy + 0.9, 1.6 - Math.floor(q / 4) * 0.35 - Math.abs((q % 4) - 1.5) * 0.25), M.MINE_DIRT, o);
    }
    // headframe with pulley, the bucket chain from the mouth
    const hf = v3(cx, 10, 0);
    this.stationMark(ST.MINE, v3(66.5, 14, 0), 5.2, v3(0.2, 0.95, 0));
    for (const dx of [-1.8, 1.8]) for (const dy of [-1.8, 1.8]) r.beam(add(hf, v3(dx, dy, 0)), add(hf, v3(dx * 0.35, dy * 0.35, 11)), 0.38, M.WOOD, o);
    for (const z of [3.5, 7]) r.box(add(hf, v3(-1.5 + z * 0.1, -1.5 + z * 0.1, z)), add(hf, v3(1.5 - z * 0.1, 1.5 - z * 0.1, z + 0.3)), M.WOOD_DARK, o);
    r.box(add(hf, v3(-1, -1, 10.8)), add(hf, v3(1, 1, 11.2)), M.WOOD_DARK, o);
    const pul = add(hf, v3(0, 0, 12.2));
    for (let s = 0; s < 16; s++) {
      const a = (TAU * s) / 16, a2 = (TAU * (s + 1)) / 16;
      r.beam(add(pul, v3(Math.cos(a) * 2, 0, Math.sin(a) * 2)), add(pul, v3(Math.cos(a2) * 2, 0, Math.sin(a2) * 2)), 0.3, M.WOOD_DARK, o, v3(0, 1, 0));
      if (s % 4 === 0) r.beam(pul, add(pul, v3(Math.cos(a) * 2, 0, Math.sin(a) * 2)), 0.18, M.WOOD, o, v3(0, 1, 0));
    }
    r.line3(v3(cx - 2, 6.3, 1), add(pul, v3(-2, 0, 0)), [0.23, 0.21, 0.2]);
    r.line3(v3(cx + 2, 9.4, 0.6), add(pul, v3(2, 0, 0)), [0.23, 0.21, 0.2]);
    // a 2 px cart track from the mouth to the mill, a cart of ore
    for (const rail of [-0.45, 0.45]) r.beam(v3(cx + rail, 5.2, 0.08), v3(cx + rail, 30, 0.08), 0.1, M.IRON, o);
    r.box(v3(cx - 0.9, 13, 0.35), v3(cx + 0.9, 15.2, 1.4), M.WOOD, o, M.ORE);
    // stamp mill with four drop hammers, fed from the mine output shaft
    const sm = v3(65.5, 15, 0);
    r.box(add(sm, v3(-2.5, -1, 0)), add(sm, v3(2.5, 1, 1.2)), M.WOOD_DARK, o, M.MINE_DIRT);
    r.box(add(sm, v3(-2.7, -0.3, 0)), add(sm, v3(-2.3, 0.3, 6)), M.WOOD, o);
    r.box(add(sm, v3(2.3, -0.3, 0)), add(sm, v3(2.7, 0.3, 6)), M.WOOD, o);
    r.box(add(sm, v3(-2.7, -0.4, 5.6)), add(sm, v3(2.7, 0.4, 6.1)), M.WOOD_DARK, o);
    for (let k = 0; k < 4; k++) {
      const x = sm.x - 1.8 + k * 1.2;
      const lift = [0.2, 1.1, 0.5, 1.4][k];
      r.box(v3(x - 0.2, sm.y - 0.2, 1.3 + lift), v3(x + 0.2, sm.y + 0.2, 5.4), M.WOOD_LIGHT, o);
      r.box(v3(x - 0.35, sm.y - 0.35, 1.2 + lift), v3(x + 0.35, sm.y + 0.35, 1.9 + lift), M.IRON, o);
    }
    // ore heaps
    for (let q = 0; q < 9; q++) {
      const gx = 75 + (q % 3) * 0.7, gy = 16 + Math.floor(q / 3) * 0.6;
      const gh = 0.8 - Math.abs((q % 3) - 1) * 0.3 - Math.abs(Math.floor(q / 3) - 1) * 0.25;
      r.box(v3(gx, gy, 0), v3(gx + 0.7, gy + 0.6, gh), M.ORE, o);
    }
  }

  pads() {
    const r = this.r;
    // build pads: dark stone plinths with bronze corner studs; two hold scorpions, two a brazier
    const pads = [v3(18, 59, 12), v3(66, 59, 12), v3(1.5, 30.5, 12), v3(82.5, 34.5, 12)];
    pads.forEach((p, k) => {
      r.box(sub(p, v3(1.5, 1.5, 0)), add(p, v3(1.5, 1.5, 0.3)), M.WALL, 60 + k, M.WALLTOP);
      for (const [dx, dy] of [[-1.3, -1.3], [1.3, -1.3], [-1.3, 1.3], [1.3, 1.3]]) r.box(add(p, v3(dx - 0.15, dy - 0.15, 0.3)), add(p, v3(dx + 0.15, dy + 0.15, 0.45)), M.BRONZE, 60 + k);
      if (k === 1 || k === 3) {
        const a = k === 1 ? deg(110) : deg(160);
        this.ybox(add(p, v3(0, 0, 0.3)), a, { x: 0.5, y: 0.5, z: 0.5 }, M.WOOD, 61);
        r.beam(this.local(p, a, v3(-0.8, 0, 1.4)), this.local(p, a, v3(1.6, 0, 1.6)), 0.2, M.WOOD_LIGHT, 61);
        r.beam(this.local(p, a, v3(0.9, -1.0, 1.5)), this.local(p, a, v3(0.9, 1.0, 1.5)), 0.14, M.WOOD_DARK, 61);
      } else {
        r.cylZ(add(p, v3(0, 0, 0.3)), 0.4, 0.9, M.BRONZE, 61, 8, M.STONE_DARK);
      }
    });
  }

  bridgeAndTar() {
    const r = this.r, o = 70;
    // stone bridge on two arches from the far bank, a timber drawbridge span at the gate
    r.box(v3(40.5, 66, 0), v3(47.5, 76, 0.3), M.WALLTOP, o);
    r.quad(v3(47.5, 76, 0.3), v3(47.5, 66, 0.3), v3(47.5, 66, -3), v3(47.5, 76, -3), M.ARCH_BRIDGE, o, v3(1, 0, 0));
    for (const y of [65.6, 70.6, 75.4]) r.box(v3(40.5, y, -3), v3(47.5, y + 0.8, 0), M.WALL, o);
    for (const x of [40.5, 47.2]) r.box(v3(x, 66, 0.3), v3(x + 0.3, 76, 1.0), M.WALL, o, M.CAP);
    r.box(v3(40.8, 62.5, 0), v3(47.2, 66, 0.3), M.WOOD, o);
    for (const x of [41.2, 46.8]) r.line3(v3(x, 62.6, 6.4), v3(x, 66, 0.35), [0.2, 0.2, 0.22]);
    if (this.tar <= 0) return;
    // the tar shield: a curtain from the spout gallery over the arches, and the coat it leaves
    r.quad(v3(40.0, 63.8, 9.6), v3(48.0, 63.8, 9.6), v3(48.0, 63.8, 0.32), v3(40.0, 63.8, 0.32), M.TAR_FALL, 71, v3(0, 1, 0));
    let k = 0;
    for (let y = 62.6; y < 71.5; y += 1) {
      const shrink = clamp((y - 66) / 5.5, 0, 1) * 2.4;
      const wob = (W.hash2(k, 3) - 0.5) * 0.8;
      r.quad(v3(40.9 + shrink + wob, y, 0.33), v3(47.1 - shrink + wob * 0.5, y, 0.33), v3(47.1 - shrink + wob * 0.5, y + 1, 0.33), v3(40.9 + shrink + wob, y + 1, 0.33), M.TAR, 71, v3(0, 0, 1), F_COLOR);
      k++;
    }
  }

  palisade() {
    // sharpened stakes along the outer bank of the moat, a gap at the bridgehead
    for (let x = 6; x < 84; x += 0.8) if (x < 38 || x > 50) this.stake(v3(x, 75.2 + W.hash2(Math.floor(x * 3), 1) * 0.5, 0), v3(0, 0.3, 1));

  }

  stake(base, lean) {
    if (W.roadAt(base.x, base.y) > 0.1) return;
    const h = 1.8 + W.hash2(Math.floor(base.x * 7), Math.floor(base.y * 7)) * 0.6;
    const z = W.height(base.x, base.y);
    this.r.beam(v3(base.x, base.y, z), add(v3(base.x, base.y, z), mul(norm(lean), h)), 0.3, M.WOOD_DARK, 72);
  }

  rocks() {
    // boulder fields on the open ground, kept off the road
    const fields = [[110, 70, 14, 26], [130, 120, 16, 22], [-60, 70, 12, 16], [-20, 160, 12, 14], [-70, -10, 14, 18], [100, 160, 12, 12]];
    for (const [cx, cy, rad, n] of fields) {
      for (let k = 0; k < n; k++) {
        const p = { x: cx + this.range(-rad, rad), y: cy + this.range(-rad, rad) };
        if (W.roadAt(p.x, p.y) > 0.05 || W.fortDistance(p.x, p.y) < 16) continue;
        this.rock(p, this.range(0.5, 2.0));
      }
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

  // Things the road bends around: an outcrop, an oasis pool, an obelisk, a ruined colonnade,
  // milestones on the paved via near the bridge.
  landmarks() {
    const r = this.r;
    // outcrop at the west bend
    for (let k = 0; k < 7; k++) this.rock({ x: -46 + this.range(-4, 4), y: 66 + this.range(-4, 4) }, this.range(1.6, 3.4));
    // oasis
    const oz = W.height(4, 128);
    r.cylZ(v3(4, 128, oz - 0.6), 3.4, 0.7, M.MINE_DIRT, 81, 14, M.WATER);
    // obelisks
    for (const [x, y, h] of [[-24, 84, 9], [62, 140, 7]]) {
      const z = W.height(x, y);
      r.box(v3(x - 0.9, y - 0.9, z), v3(x + 0.9, y + 0.9, z + 0.8), M.WALL, 82, M.WALLTOP);
      r.box(v3(x - 0.5, y - 0.5, z + 0.8), v3(x + 0.5, y + 0.5, z + h), M.PLASTER, 82);
      r.pyramid({ x: x - 0.5, y: y - 0.5 }, { x: x + 0.5, y: y + 0.5 }, z + h, 0.8, M.ORE, 82);
    }
    // a sphinx-like lion on a plinth by the camp road
    {
      const x = -40, y = 92, z = W.height(-40, 92);
      r.box(v3(x - 1.5, y - 3, z), v3(x + 1.5, y + 3, z + 1), M.WALL, 83, M.WALLTOP);
      r.box(v3(x - 0.8, y - 2.4, z + 1), v3(x + 0.8, y + 1.2, z + 2), M.PLASTER, 83);
      r.box(v3(x - 0.7, y + 0.8, z + 1), v3(x + 0.7, y + 2.6, z + 3.2), M.PLASTER, 83);
    }
    // ruined colonnade south of the hairpins
    for (let k = 0; k < 5; k++) {
      const x = 86 + k * 2.2, y = 132, z = W.height(x, y);
      r.cylZ(v3(x, y, z), 0.4, [3.5, 1.4, 2.8, 0.9, 2.2][k], M.TEMPLE, 84, 8);
    }
    // milestones on the via
    for (const s of [16, 38]) {
      const p = W.roadPoint(0, s), d = W.roadDir(0, s);
      const q = { x: p.x - d.y * 2.8, y: p.y + d.x * 2.8 };
      r.cylZ(v3(q.x, q.y, W.height(q.x, q.y)), 0.3, 1.1, M.TEMPLE, 85, 8);
    }
  }

  camp() {
    const r = this.r;
    // tents where the road starts (top left)
    const tents = [[-72, 26], [-64, 30], [-78, 36], [-56, 22], [-70, 14], [-82, 20], [-60, 6], [-76, 4], [-48, 30], [-88, 30]];
    for (const [x, y] of tents) {
      if (W.roadAt(x, y) > 0.05) continue;
      const z = W.height(x, y);
      const big = W.hash2(x, y) > 0.5;
      const hx = big ? 2.2 : 1.6, hy = big ? 1.6 : 1.2;
      r.gable({ x: x - hx, y: y - hy }, { x: x + hx, y: y + hy }, z, big ? 2.2 : 1.7, true, M.TENT, M.TENT, 81);
    }
    for (let k = 0; k < 3; k++) {
      const c = v3(-52 + k * 3, 14 + k * 2, 0);
      c.z = W.height(c.x, c.y);
      r.box(c, add(c, v3(1.6, 2.6, 1)), M.WOOD, 82);
      r.cyl(add(c, v3(-0.1, 0.6, 0.4)), add(c, v3(1.7, 0.6, 0.4)), 0.45, M.WOOD_DARK, 82, 6);
    }
  }

  // An aqueduct arcade from the foot of the massif to the moat's south-east corner.
  aqueduct() {
    const r = this.r, o = 86, x = 106, y0 = -2, y1 = 63;
    r.quad(v3(x + 1, y1, 7.2), v3(x + 1, y0, 7.2), v3(x + 1, y0, 0), v3(x + 1, y1, 0), M.ARCH_AQ, o, v3(1, 0, 0));
    r.quad(v3(x - 1, y1, 7.2), v3(x + 1, y1, 7.2), v3(x + 1, y1, 0), v3(x - 1, y1, 0), M.WALL, o, v3(0, 1, 0));
    r.box(v3(x - 1, y0, 7.2), v3(x + 1.2, y1, 8.2), M.WALL, o, M.WALLTOP);
    r.box(v3(x - 0.6, y0, 8.2), v3(x + 0.8, y1, 8.3), M.WATER, o);
    for (let y = y0; y <= y1; y += 5) r.box(v3(x - 1, y - 0.5, -0.4), v3(x + 1.2, y + 0.5, 0.6), M.WALL, o, M.WALLTOP);
    // the spill into the moat
    r.box(v3(x - 9, y1 - 1, 0), v3(x + 1, y1 + 1, 1.2), M.WALL, o, M.WATER);
  }

  // A small vicus east of the fort: mud-brick houses along a crooked lane round a well, with
  // doors, parapets and frond awnings; the wadi's boulders below it.
  vicus() {
    const r = this.r, o = 87;
    const houses = [[116, 24, 4, 5], [122.5, 22.5, 5, 4], [130, 27, 4, 4.5], [115, 33, 5, 4], [126, 33.5, 4, 5], [133.5, 36, 4, 4], [119, 42, 4.5, 4], [127.5, 45, 5, 4], [138, 29, 3.5, 4], [112, 41, 3.5, 3.5]];
    houses.forEach(([x, y, w, d], k) => {
      const z = W.height(x, y);
      const hgt = 2.5 + W.hash2(k, 9) * 1.5;
      const mat = k % 3 === 0 ? M.PLASTER : M.MUDBRICK;
      r.box(v3(x, y, z - 0.3), v3(x + w, y + d, z + hgt), mat, o);
      // parapet
      r.box(v3(x, y + d - 0.25, z + hgt), v3(x + w, y + d, z + hgt + 0.4), mat, o);
      r.box(v3(x + w - 0.25, y, z + hgt), v3(x + w, y + d, z + hgt + 0.4), mat, o);
      // door and a frond awning on the lane side
      r.quad(v3(x + w + 0.02, y + d * 0.5 + 0.4, z + 1.7), v3(x + w + 0.02, y + d * 0.5 - 0.4, z + 1.7), v3(x + w + 0.02, y + d * 0.5 - 0.4, z), v3(x + w + 0.02, y + d * 0.5 + 0.4, z), M.STONE_DARK, o, v3(1, 0, 0));
      if (k % 2 === 0) r.quad(v3(x + w, y + d * 0.5 - 1.2, z + 2.1), v3(x + w, y + d * 0.5 + 1.2, z + 2.1), v3(x + w + 1.4, y + d * 0.5 + 1.2, z + 1.7), v3(x + w + 1.4, y + d * 0.5 - 1.2, z + 1.7), M.HIDE, o);
    });
    r.cylZ(v3(124.5, 40, W.height(124.5, 40)), 0.9, 0.8, M.WALL, o, 10, M.WATER);
    const c = v3(121, 38.5, W.height(121, 38.5));
    r.box(add(c, v3(0, 0, 0.4)), add(c, v3(1.6, 2.4, 1.2)), M.WOOD, o);
    r.cyl(add(c, v3(-0.1, 0.6, 0.45)), add(c, v3(1.7, 0.6, 0.45)), 0.45, M.WOOD_DARK, o, 6);
    for (let k = 0; k < 14; k++) {
      const t = k / 14;
      const side = k % 2 ? 1 : -1;
      this.rock({ x: 112 + t * 58 + side * (2 + t * 4), y: 76 + t * 70 - side * (2 + t * 3) }, this.range(0.5, 1.4));
    }
  }

  // The paved via's last stretch: tombs on both sides and a small triumphal arch over it.
  via() {
    const r = this.r, o = 88;
    for (const s of [12, 20, 30, 40]) {
      const p = W.roadPoint(0, s), d = W.roadDir(0, s);
      for (const side of [-1, 1]) {
        const q = { x: p.x - d.y * 5.2 * side, y: p.y + d.x * 5.2 * side };
        const z = W.height(q.x, q.y);
        if (W.hash2(s, side + 3) > 0.5) {
          r.box(v3(q.x - 1, q.y - 1, z), v3(q.x + 1, q.y + 1, z + 1.8), M.WALL, o, M.CAP);
          r.pyramid({ x: q.x - 1, y: q.y - 1 }, { x: q.x + 1, y: q.y + 1 }, z + 1.8, 0.9, M.WALLTOP, o);
        } else {
          r.box(v3(q.x - 0.3, q.y - 0.6, z), v3(q.x + 0.3, q.y + 0.6, z + 2.2), M.TEMPLE, o);
        }
      }
    }
    // the arch: two piers and an attic over the road at s 24
    const p = W.roadPoint(0, 24);
    const z = W.height(p.x, p.y);
    for (const side of [-1, 1]) r.box(v3(p.x + side * 3.4 - 0.9, p.y - 1.1, z), v3(p.x + side * 3.4 + 0.9, p.y + 1.1, z + 6), M.WALL, o, M.WALLTOP);
    r.box(v3(p.x - 4.3, p.y - 1.1, z + 6), v3(p.x + 4.3, p.y + 1.1, z + 8.2), M.WALL, o, M.CAP);
    r.box(v3(p.x - 2.5, p.y + 1.05, z + 6.6), v3(p.x + 2.5, p.y + 1.15, z + 7.6), M.CAP, o);
  }

  // Clutter that makes the courtyard read as a working fort.
  yardProps() {
    const r = this.r, o = 89;
    // stone balls stacked by the catapult, bolt bundles by the ballista tower, crates and carts
    for (const [bx, by] of [[39.5, 45.5], [42.5, 43]]) {
      for (let lvl = 0; lvl < 3; lvl++) for (let a = 0; a < 3 - lvl; a++) for (let b = 0; b < 3 - lvl; b++) {
        r.box(v3(bx + a * 0.7 + lvl * 0.35, by + b * 0.7 + lvl * 0.35, lvl * 0.6), v3(bx + a * 0.7 + lvl * 0.35 + 0.6, by + b * 0.7 + lvl * 0.35 + 0.6, lvl * 0.6 + 0.6), M.ROCK, o);
      }
    }
    for (let k = 0; k < 4; k++) {
      const p = v3(14 + k * 0.6, 51 + (k % 2) * 0.5, 0);
      for (let q = 0; q < 5; q++) r.beam(add(p, v3(q * 0.1, 0, 0.1 + q * 0.06)), add(p, v3(q * 0.1, 3.2, 0.1 + q * 0.06)), 0.1, M.WOOD_LIGHT, o);
    }
    for (const [x, y] of [[55, 38], [56.3, 38], [55.6, 39.3], [70, 50], [71.2, 50.5], [37, 32]]) r.box(v3(x, y, 0), v3(x + 1.1, y + 1.1, 1.0), M.WOOD_LIGHT, o, M.WOOD);
    r.box(v3(41, 33, 0.5), v3(42.8, 36, 1.4), M.WOOD, o, M.ORE);
    r.cyl(v3(40.9, 33.7, 0.55), v3(42.9, 33.7, 0.55), 0.5, M.WOOD_DARK, o, 8);
    r.cyl(v3(40.9, 35.3, 0.55), v3(42.9, 35.3, 0.55), 0.5, M.WOOD_DARK, o, 8);
  }

  siegeEngines() {
    // a siege tower on the straight run to the bridge, one at the far hairpin, a ram in the tar
    // and one on the lower switchback
    this.siegeTower(0, 26, 1);
    this.siegeTower(0, 210, 1);
    for (const s of [36, 220]) {
      const q = W.roadPoint(0, s), dq = W.roadDir(0, s);
      this.ram(q, Math.atan2(-dq.y, -dq.x));
    }
    this.ram({ x: 44, y: 72.5 }, Math.PI * 1.5, 0.3);
    const p = W.roadPoint(0, 112);
    const d = W.roadDir(0, 112);
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
      const w0 = hw * (1 - f0 * 0.1);
      this.ybox(add(c, v3(0, 0, h * f0)), a, { x: w0, y: w0, z: h / 6 }, M.HIDE, 83);
      this.ybox(add(c, v3(0, 0, h * (f0 + 1 / 3) - 0.3)), a, { x: w0 + 0.15, y: w0 + 0.15, z: 0.15 }, M.WOOD_DARK, 83);
    }
    // plum hangings on the front faces
    for (const k of [0, 1]) {
      const w0 = hw * (1 - (k / 3) * 0.1) + 0.05;
      const z0 = c.z + h * (k / 3) + 1.0, z1 = z0 + h / 3 - 2.4;
      const f = this.local(c, a, v3(w0, 0, 0));
      const t = v3(-Math.sin(a), Math.cos(a), 0);
      r.quad(add(add(f, mul(t, -w0 * 0.5)), v3(0, 0, z1 - c.z)), add(add(f, mul(t, w0 * 0.5)), v3(0, 0, z1 - c.z)), add(add(f, mul(t, w0 * 0.5)), v3(0, 0, z0 - c.z)), add(add(f, mul(t, -w0 * 0.5)), v3(0, 0, z0 - c.z)), M.PLUM, 83, v3(Math.cos(a), Math.sin(a), 0));
    }
    const top = add(c, v3(0, 0, h));
    const tw = hw * 0.9;
    for (const side of [-1, 1]) this.ybox(this.local(top, a, v3(0, tw * side, 0)), a, { x: tw, y: 0.12, z: 0.6 }, M.WOOD_DARK, 83);
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
