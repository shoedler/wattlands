// Everything stamped after the geometry: people (attackers, defenders, walkers in the wheels,
// station crews), palms, and one moment of a wave's physics: a catapult stone in flight, the
// dust of its previous hit, a ballista bolt, an arrow volley, the tar curtain's drips and
// fumes, torches and road dust. Flights are integrated with gravity and quadratic drag from
// solved launch velocities, as the rules would.
import { v3, add, sub, mul, norm, lerp3, rng, TAU, deg, hex } from './v3.mjs';
import { depthOf } from './raster.mjs';
import { ditherT } from './shade.mjs';
import { sprite } from './sprites.mjs';
import * as W from './world.mjs';
import * as S from './scene.mjs';

const G = 9.81;
const DT = 0.05;

// Positions every DT from p0 with velocity v0, gravity and drag k (1/m): a = g - k|v|v.
export function fly(p0, v0, k, steps) {
  const out = [p0];
  let p = { ...p0 };
  let v = { ...v0 };
  for (let i = 0; i < steps; i++) {
    for (let s = 0; s < 4; s++) {
      const h = DT / 4;
      const sp = Math.hypot(v.x, v.y, v.z);
      v = { x: v.x - k * sp * v.x * h, y: v.y - k * sp * v.y * h, z: v.z + (-G - k * sp * v.z) * h };
      p = { x: p.x + v.x * h, y: p.y + v.y * h, z: p.z + v.z * h };
    }
    out.push(p);
  }
  return out;
}

function landing(p0, v0, k, z) {
  const path = fly(p0, v0, k, 400);
  for (let i = 1; i < path.length; i++) {
    if (path[i].z <= z && path[i - 1].z > z) {
      const t = (path[i - 1].z - z) / Math.max(path[i - 1].z - path[i].z, 1e-6);
      return { p: lerp3(path[i - 1], path[i], t), steps: i };
    }
  }
  return { p: path[path.length - 1], steps: path.length - 1 };
}

// A launch velocity at `speed` that lands on target despite drag, by re-aiming at the target
// plus the previous miss. Returns {v0, steps}.
export function aim(p0, target, speed, high, k) {
  let ap = { ...target };
  let v0 = v3();
  let steps = 0;
  for (let it = 0; it < 10; it++) {
    const dx = ap.x - p0.x, dy = ap.y - p0.y;
    const d = Math.hypot(dx, dy);
    const h = ap.z - p0.z;
    const v2 = speed * speed;
    const disc = v2 * v2 - G * (G * d * d + 2 * h * v2);
    let ang = Math.PI / 4;
    if (disc >= 0) ang = Math.atan((v2 + (high ? 1 : -1) * Math.sqrt(disc)) / (G * d));
    v0 = v3((dx / d) * Math.cos(ang) * speed, (dy / d) * Math.cos(ang) * speed, Math.sin(ang) * speed);
    const l = landing(p0, v0, k, target.z);
    steps = l.steps;
    ap = add(ap, sub(target, l.p));
  }
  return { v0, steps };
}

export class Life {
  constructor(r, scene, opts = {}) {
    this.r = r;
    this.scene = scene;
    this.rnd = rng(11);
    this.t = opts.t ?? 0.58; // where in its flight the catapult stone is
    this.workers = opts.workers ?? [2, 3, 2, 1];
  }

  run() {
    this.palms();
    this.defenders();
    this.wheelWalkers();
    this.crews();
    this.army();
    this.effects();
  }

  ground(p) {
    return v3(p.x, p.y, W.height(p.x, p.y));
  }

  person(id, p, shadow = true) {
    const s = sprite(id);
    this.r.stamp(s, p, 1, s.h - 1, 90, true, this.rnd.f() < 0.5);
    if (shadow) this.r.groundShadow(p, 0.4, 1.6, 0.66);
  }

  block(road, s, ranks, files, kinds, sp = 0.95) {
    const d = W.roadDir(road, s);
    const side = { x: -d.y, y: d.x };
    for (let i = 0; i < ranks; i++) {
      for (let j = 0; j < files; j++) {
        const ss = s + i * sp + this.rnd.range(-0.08, 0.08);
        const c = W.roadPoint(road, ss);
        const off = (j - (files - 1) / 2) * sp;
        const p = { x: c.x + side.x * off + this.rnd.range(-0.06, 0.06), y: c.y + side.y * off + this.rnd.range(-0.06, 0.06) };
        this.person(kinds[Math.floor(this.rnd.f() * kinds.length)], this.ground(p));
      }
    }
    // a fan standard beside the block
    const c = W.roadPoint(road, s + ranks * sp * 0.5);
    const base = this.ground({ x: c.x + side.x * files * sp * 0.5, y: c.y + side.y * files * sp * 0.5 });
    this.r.line3(base, add(base, v3(0, 0, 3.4)), hex('#46321f'));
    this.r.point(add(base, v3(0, 0, 3.6)), hex('#b8954a'), 2);
    this.r.point(add(base, v3(-0.4, 0.4, 3.2)), hex('#5a3550'), 2);
  }

  crew(road, s0, n, perRank, spread) {
    for (let k = 0; k < n; k++) {
      const s = s0 + (k % perRank) * 1.2;
      const d = W.roadDir(road, s);
      const c = W.roadPoint(road, s);
      const off = (Math.floor(k / perRank) - (Math.ceil(n / perRank) - 1) / 2) * spread;
      this.person('hauler', this.ground({ x: c.x - d.y * off, y: c.y + d.x * off }));
    }
  }

  army() {
    const inf = ['spear', 'spear', 'spear2', 'spear', 'officer'];
    const arch = ['archer', 'archer', 'spear'];
    // West road: two siege towers pushed by their crews, blocks behind
    // the one road, bridgehead first: shields at the bridgehead, a block under the arrows, a
    // siege tower on the straight, blocks down the hairpins, a ram, chariots, the second tower
    // and the column still leaving the camp
    this.block(0, 8, 6, 4, inf);
    this.block(0, 15, 6, 4, inf);
    this.crew(0, 30.5, 14, 4, 1.4);
    this.block(0, 40, 6, 4, inf);
    this.block(0, 62, 6, 4, arch);
    this.block(0, 86, 6, 4, inf);
    for (let k = 0; k < 10; k++) {
      const s = 116 + (k % 5) * 1.4;
      const d = W.roadDir(0, s);
      const c = W.roadPoint(0, s);
      const off = k < 5 ? 2.2 : -2.2;
      this.person('hauler', this.ground({ x: c.x - d.y * off, y: c.y + d.x * off }));
    }
    this.block(0, 128, 6, 4, inf);
    for (let k = 0; k < 5; k++) {
      const s = 150 + k * 5;
      const d = W.roadDir(0, s);
      const c = W.roadPoint(0, s);
      const off = k % 2 === 0 ? 1.1 : -1.1;
      const p = this.ground({ x: c.x - d.y * off, y: c.y + d.x * off });
      const spr = sprite('chariot');
      this.r.stamp(spr, p, 4, spr.h - 1, 91, true, d.x < 0);
      this.r.groundShadow(p, 1, 1.4, 0.8);
    }
    this.block(0, 185, 6, 4, arch);
    this.crew(0, 214.5, 14, 4, 1.4);
    this.block(0, 228, 6, 4, inf);
    this.block(0, 262, 6, 4, inf);
    this.block(0, 300, 6, 4, inf);
    this.block(0, 335, 6, 4, arch);
    // on the bridge: the ram's crew stuck in the tar; shields at the bridgehead
    for (let k = 0; k < 8; k++) this.person('hauler', v3(44 + (k % 2 === 0 ? 2.3 : -2.3), 71 + Math.floor(k / 2) * 1.2, 0.4), false);
    // villagers in the vicus
    for (let k = 0; k < 12; k++) this.person(k % 2 ? 'worker' : 'engineer', this.ground({ x: this.rnd.range(116, 140), y: this.rnd.range(22, 48) }));
    // the camp
    for (let k = 0; k < 40; k++) {
      const p = { x: this.rnd.range(-90, -46), y: this.rnd.range(0, 38) };
      if (W.roadAt(p.x, p.y) > 0.3) continue;
      this.person(['spear', 'hauler', 'archer'][k % 3], this.ground(p));
    }
  }

  defenders() {
    // two drilling squads in the courtyard, oxblood shields, 3 x 6
    for (const [x0, y0] of [[44, 37], [55, 46]]) {
      for (let i = 0; i < 6; i++) for (let j = 0; j < 3; j++) this.person('roman', v3(x0 + i * 0.95, y0 + j * 0.95, 0));
    }
    const wz = W.WALL_H;
    for (let x = 1; x < 83; x += 1.6) {
      if ((x < 39 || x > 49) && this.rnd.f() < 0.55) this.person(this.rnd.f() < 0.6 ? 'roman' : 'roman_bow', v3(x, 58.2, wz), false);
    }
    for (let y = 8; y < 56; y += 2) {
      if (this.rnd.f() < 0.35) this.person('roman', v3(82.5, y, wz), false);
      if (this.rnd.f() < 0.3) this.person('roman', v3(1.5, y, wz), false);
    }
    for (const p of [v3(17, 57.5, 12), v3(19.5, 60, 12), v3(64, 58, 12), v3(67, 60.5, 12), v3(1, 28.5, 12), v3(83, 36, 12), v3(42, 61.5, 11.5), v3(46, 61.5, 11.5)]) this.person('roman_bow', p, false);
  }

  wheelWalkers() {
    for (let i = 0; i < 4; i++) {
      const c = v3(S.WHEEL_X[i], S.WHEEL_Y, S.WHEEL_R + 1.4);
      for (let k = 0; k < this.workers[i]; k++) {
        const a = -Math.PI / 2 + 0.12 - k * 0.18;
        const p = add(c, v3(Math.cos(a) * (S.WHEEL_R - 0.5), -0.6 + k * 0.6, Math.sin(a) * (S.WHEEL_R - 0.5)));
        this.person('worker', p, false);
      }
    }
  }

  crews() {
    const spots = [
      v3(25, 36, 0), v3(38.5, 38, 0), v3(21.5, 47, 0), v3(33, 50.5, 0),
      v3(-1, 56.5, 15), v3(2.5, 61.5, 15),
      v3(81, 56.5, 15), v3(85, 60.5, 15),
      v3(40.6, 59.6, 11.5), v3(47.2, 59.9, 11.5),
      v3(68, 17, 0), v3(74, 18, 0), v3(70.5, 8, 0),
      v3(33, 27.2, 0.5), v3(19, 27.2, 0.5), v3(49, 27.2, 0.5), v3(28, 18.2, 0.5), v3(55, 18.2, 0.5),
      v3(14.5, 30, 0), v3(16, 31, 0), v3(66, 47, 0), v3(37, 50, 0), v3(52, 46, 0),
    ];
    for (const p of spots) this.person('engineer', p, p.z < 0.5);
  }

  palms() {
    const groves = [[123, 41], [4, 128], [8, 122], [-2, 134], [-24, 92], [106, 90], [120, 70], [64, 104], [96, 150], [130, 110], [-30, 40], [-60, 54], [-80, 46], [30, 98], [112, 128]];
    let n = 0;
    for (const [gx, gy] of groves) {
      const count = this.rnd.int(3, 6);
      for (let k = 0; k < count; k++) {
        const p = { x: gx + this.rnd.range(-6, 6), y: gy + this.rnd.range(-6, 6) };
        if (W.roadAt(p.x, p.y) > 0.2 || W.height(p.x, p.y) < -0.6) continue;
        const s = sprite(`palm${n % 7}`);
        const base = this.ground(p);
        this.r.stamp(s, base, 13, s.h - 1, 95, true, this.rnd.f() < 0.5);
        this.r.groundShadow(base, 1.2, 6, 0.8);
        n++;
      }
    }
  }

  // --- effects ----------------------------------------------------------------------------

  // A dithered translucent puff (dust, smoke): pixel-art transparency without alpha.
  puff(p, radiusM, c, density) {
    const r = this.r;
    const s = r.project(p);
    const rad = radiusM * r.k;
    const d = depthOf(p);
    const ir = Math.ceil(rad);
    for (let yy = -ir; yy <= ir; yy++) {
      for (let xx = -ir; xx <= ir; xx++) {
        const q = (xx * xx + yy * yy) / Math.max(rad * rad, 0.01);
        if (q > 1) continue;
        const x = Math.floor(s.x) + xx, y = Math.floor(s.y) + yy;
        if (x < 0 || y < 0 || x >= r.w || y >= r.h) continue;
        const i = y * r.w + x;
        if (d + radiusM < r.dep[i]) continue;
        if (ditherT(x, y) < density * (1 - q)) for (let k = 0; k < 3; k++) r.col[i * 3 + k] += (c[k] - r.col[i * 3 + k]) * 0.75;
      }
    }
  }

  fire(p, size) {
    this.r.point(p, [1, 0.6, 0.19], 2, true, 0.7 * size);
    this.r.point(add(p, v3(0, 0, 0.35)), [1, 0.85, 0.38], 1, true, 0.9 * size);
    this.r.point(add(p, v3(0, 0, 0.7)), [1, 0.94, 0.63], 1, false, 0.5 * size);
  }

  effects() {
    const r = this.r;
    // catapult: the stone part-way through its flight to the leading block of the far loop
    const stoneK = 0.0016;
    const tip = this.scene.catapultRelease();
    const tgt = this.ground(W.roadPoint(0, 279));
    const shot = aim(tip, tgt, 34, false, stoneK);
    const path = fly(tip, shot.v0, stoneK, shot.steps);
    const now = Math.floor(shot.steps * this.t);
    this.stoneNow = path[now];
    for (let i = Math.max(1, now - 16); i < now; i++) {
      const t = (i - now + 16) / 16;
      if (i % 2 === 0) r.point(path[i], hex('#fff4dc'), 1, false, 0, 0.15 + 0.45 * t);
      if (i > now - 12 && i % 2 === 0) this.puff(path[i], 0.35 + t * 0.2, hex('#e8dcc0'), 0.45 * t);
    }
    r.point(path[now], hex('#3e3833'), 4);
    r.point(add(path[now], v3(-0.15, 0.15, 0.3)), hex('#c0b6a8'), 2);
    this.dropShadow(path[now], 1.0);
    // a faint dithered ring where it will land
    for (let k = 0; k < 28; k += 2) {
      const a = (TAU * k) / 28;
      const q = v3(tgt.x + Math.cos(a) * 4, tgt.y + Math.sin(a) * 4, 0);
      q.z = W.height(q.x, q.y) + 0.05;
      r.point(q, hex('#fff2c8'), 1, false);
    }
    // the previous stone's impact further along the same loop
    this.impact(this.ground(W.roadPoint(0, 300)), 0.32);
    // ballista: a bolt three quarters of the way to the first siege tower, streak behind it
    const bp = add(S.BALLISTA, v3(0, 0, 6));
    const st = W.roadPoint(0, 26);
    const stHit = v3(st.x, st.y, W.height(st.x, st.y) + 10);
    const bk = 0.0004;
    const bshot = aim(bp, stHit, 78, false, bk);
    const bpath = fly(bp, bshot.v0, bk, Math.max(bshot.steps, 8) + 2);
    const bt = 0.75 * bshot.steps;
    const bi = Math.floor(bt);
    const bpos = lerp3(bpath[bi], bpath[bi + 1], bt - bi);
    const bdir = norm(sub(bpath[bi + 1], bpath[bi]));
    for (let k = 0; k < 30; k++) r.point(sub(bpos, mul(bdir, 2.4 + k * 0.5)), [1, 0.98 - k * 0.008, 0.88 - k * 0.012], 1, false, 0.3 * (1 - k / 30), 1 - k / 34);
    for (let q = 0; q < 14; q++) r.point(sub(bpos, mul(bdir, q * 0.4)), hex(q < 2 ? '#3a3c40' : '#6b5134'), 2);
    r.point(bpos, hex('#e8ecf0'), 1);
    this.dropShadow(bpos, 0.6);
    r.point(bpos, hex('#cfd2d6'), 1);
    r.line3(add(stHit, v3(-1.5, 0.8, -3)), add(stHit, v3(-0.2, -0.6, -2.6)), hex('#4a3322'));
    // arrow battery: a volley of 20 arrows dropping on the East road block
    const ap = add(S.ARROWS, v3(0, 0, 2.8));
    const at = this.ground(W.roadPoint(0, 17));
    const ak = 0.006;
    for (let k = 0; k < 28; k++) {
      const jit = v3(this.rnd.range(-4, 4), this.rnd.range(-4, 4), 0);
      const a = aim(ap, add(at, jit), 21, false, ak);
      const apath = fly(ap, a.v0, ak, a.steps + 1);
      const ft = Math.min(0.72 + this.rnd.range(-0.1, 0.08), 0.98) * a.steps;
      const ai = Math.floor(ft);
      const apos = lerp3(apath[ai], apath[ai + 1], ft - ai);
      const adir = norm(sub(apath[ai + 1], apath[ai]));
      for (let q = Math.max(ai - 6, 1); q < ai; q++) r.point(apath[q], hex('#f2ead6'), 1, false, 0, 0.12 + 0.3 * ((q - ai + 6) / 6));
      if (k % 3 === 0) this.dropShadow(apos, 0.35);
      r.line3(sub(apos, mul(adir, 1.3)), apos, hex('#2e2219'));
      r.point(sub(apos, mul(adir, 1.3)), hex('#f4eedc'), 1);
      for (let q = 1; q < 4; q++) r.point(sub(apos, mul(adir, 1.3 + q * 0.8)), hex('#efe6cf'), 1, false, 0, 0.25 / q);
    }
    for (let k = 0; k < 16; k++) {
      const p = add(at, v3(this.rnd.range(-6, 6), this.rnd.range(-6, 6), 0));
      p.z = W.height(p.x, p.y);
      r.line3(p, add(p, v3(0.15, 0.15, 0.7)), hex('#3a2c20'));
    }
    r.stamp(sprite('fallen'), add(at, v3(2, -1, 0.1)), 1, 0, 92);
    r.stamp(sprite('fallen2'), add(at, v3(-1.5, 2, 0.1)), 1, 0, 92);
    // tar: drips from the spouts, splashes on the bridge, fumes off the hot coat
    if (this.scene.tar > 0) {
      for (let k = 0; k < 16; k++) r.point(v3(this.rnd.range(40.6, 47.4), 63.9, this.rnd.range(1, 9.4)), hex('#120d0a'), 1);
      for (let k = 0; k < 18; k++) r.point(v3(this.rnd.range(40.8, 47.2), this.rnd.range(63.9, 66.5), 0.5 + this.rnd.range(0, 0.6)), hex('#2a201a'), 1);
      for (let k = 0; k < 9; k++) this.puff(v3(this.rnd.range(41, 47), this.rnd.range(62, 70), 1.2 + k * 0.7), 0.9 + k * 0.12, hex('#b8b0a8'), 0.28);
    }
    // torches every 8 m along the wall tops, braziers on the open towers and the empty pads
    for (let x = 8; x < 80; x += 8) if (x < 38 || x > 50) this.fire(v3(x, 59.6, 9.3), 0.7);
    for (let y = 12; y < 54; y += 8) this.fire(v3(83.6, y, 9.3), 0.7);
    for (const p of [v3(18, 59, 13.3), v3(1.5, 30.5, 13.3), v3(40.5, 63.7, 6), v3(47.5, 63.7, 6), v3(73, 46, 1.6), v3(59.4, 46, 1.6), v3(72, 5.4, 1.2)]) this.fire(p, 1.3);
    for (const [x, y] of [[-66, 22], [-58, 12], [-78, 28], [-50, 26]]) {
      this.fire(add(this.ground({ x, y }), v3(1.5, 1, 0.3)), 1.5);
      const b = this.ground({ x, y });
      this.fire(add(b, v3(0, 0, 0.3)), 1.2);
      for (let k = 0; k < 8; k++) this.puff(add(b, v3(k * 0.8, -k * 0.3, 1.5 + k * 1.4)), 0.7 + k * 0.18, hex('#8f8a86'), 0.32 - k * 0.02);
    }
    for (const s of [36, 58, 92, 124, 160, 190, 222, 244, 268, 306]) this.puff(add(this.ground(W.roadPoint(0, s)), v3(0, 0, 0.8)), 2.2, hex('#e6d2a6'), 0.22);
  }

  // A projectile's shadow on the ground straight below it (reads its height).
  dropShadow(p, size) {
    this.r.groundShadow(this.ground(p), size * 0.5, 0, 0.6);
  }

  impact(p, t) {
    const r = this.r;
    for (let k = 0; k < 40; k++) {
      const a = this.rnd.range(0, TAU);
      const d = Math.sqrt(this.rnd.f()) * 3;
      const q = v3(p.x + Math.cos(a) * d, p.y + Math.sin(a) * d, 0);
      q.z = W.height(q.x, q.y) + 0.02;
      r.point(q, hex('#9c7c50'), 1, false);
    }
    const n = Math.floor(t / DT) + 1;
    for (let k = 0; k < 140; k++) {
      const a = this.rnd.range(0, TAU);
      const up = this.rnd.range(0.35, 1);
      const sp = this.rnd.range(5, 16);
      const h = Math.sqrt(1 - up * up);
      const path = fly(add(p, v3(0, 0, 0.3)), v3(Math.cos(a) * h * sp, Math.sin(a) * h * sp, up * sp), 0.09, n);
      this.puff(path[path.length - 1], this.rnd.range(0.8, 1.9), k % 3 ? hex('#ead7ab') : hex('#c8ad7c'), 0.75);
    }
    for (let k = 0; k < 30; k++) {
      const a = this.rnd.range(0, TAU);
      const v = v3(Math.cos(a) * this.rnd.range(3, 9), Math.sin(a) * this.rnd.range(3, 9), this.rnd.range(4, 11));
      const path = fly(add(p, v3(0, 0, 0.3)), v, 0.004, n);
      r.point(path[path.length - 1], hex('#6a5a48'), 1);
    }
    for (let k = 0; k < 3; k++) {
      const a = (TAU * k) / 3 + 0.4;
      const path = fly(add(p, v3(0, 0, 0.5)), v3(Math.cos(a) * 4, Math.sin(a) * 4, 5), 0.01, n);
      r.stamp(sprite('fallen'), path[path.length - 1], 1, 0, 92, true, k === 1);
    }
    for (let k = 0; k < 4; k++) {
      const q = v3(p.x + this.rnd.range(-4, 4), p.y + this.rnd.range(-4, 4), 0);
      q.z = W.height(q.x, q.y) + 0.1;
      r.stamp(sprite(k % 2 ? 'fallen2' : 'fallen'), q, 1, 0, 92);
    }
  }
}
