// A small CPU rasterizer for isometric pixel art (Castellum Rotae art tool).
//
// World units are metres: x east (screen down-right), y south (screen down-left), z up.
// Projection is 2:1 pixel isometric: sx = (x - y) * K + ox, sy = (x + y) * K / 2 - z * K + oy,
// so the view axis is (1, 1, 1) and depth = x + y + z (larger is nearer). Triangles are
// collected, then rendered into a sun shadow map and into the colour buffer with per-pixel
// depth. Sprites and effects are stamped afterwards with the same depth test.
import { v3, add, sub, mul, dot, cross, norm, len, lerp3, TAU, clamp } from './v3.mjs';
import { shade } from './shade.mjs';

export const K_DEFAULT = 5;
export const F_COLOR = 1;
export const F_SHADOW = 2;
export const F_TWO_SIDED = 4;
const VIEW = norm(v3(1, 1, 1));
const AMB = 0.42;
const DIF = 0.62;
const SM_RES = 0.25;

export const depthOf = (p) => p.x + p.y + p.z;

export class Raster {
  constructor(w, h, ox, oy, k = K_DEFAULT) {
    this.k = k;
    this.w = w;
    this.h = h;
    this.ox = ox;
    this.oy = oy;
    this.sun = norm(v3(-0.55, 0.35, 0.76));
    this.col = new Float32Array(w * h * 3);
    this.dep = new Float32Array(w * h).fill(-1e9);
    this.oid = new Int32Array(w * h);
    this.glow = new Float32Array(w * h * 3);
    this.tris = []; // {a, b, c, ua.., n, mat, o, f}
    this.sm = null;
  }

  project(p) {
    return { x: (p.x - p.y) * this.k + this.ox, y: (p.x + p.y) * this.k * 0.5 - p.z * this.k + this.oy };
  }

  // --- geometry ---------------------------------------------------------------------------

  tri(a, b, c, mat, o = 0, ua = null, ub = null, uc = null, n = null, flags = F_COLOR | F_SHADOW) {
    let nn = n;
    let f = flags;
    if (!nn) {
      nn = cross(sub(b, a), sub(c, a));
      if (dot(nn, nn) < 1e-12) return;
      nn = norm(nn);
      f |= F_TWO_SIDED;
    }
    const z = { x: 0, y: 0 };
    this.tris.push({ a, b, c, ua: ua || z, ub: ub || z, uc: uc || z, n: nn, mat, o, f });
  }

  // Planar quad a-b-c-d in order; uv in metres: a = uv0, b = uv0 + (|ab|, 0), d = uv0 + (0, |ad|).
  quad(a, b, c, d, mat, o = 0, n = null, flags = F_COLOR | F_SHADOW, uv0 = { x: 0, y: 0 }) {
    const lu = len(sub(b, a));
    const lv = len(sub(d, a));
    const ua = uv0;
    const ub = { x: uv0.x + lu, y: uv0.y };
    const uc = { x: uv0.x + lu, y: uv0.y + lv };
    const ud = { x: uv0.x, y: uv0.y + lv };
    this.tri(a, b, c, mat, o, ua, ub, uc, n, flags);
    this.tri(a, c, d, mat, o, ua, uc, ud, n, flags);
  }

  // Axis-aligned box; faces the camera can't see go to the shadow map only.
  box(mn, mx, mat, o = 0, topMat = -1, sideMat = -1) {
    const tm = topMat < 0 ? mat : topMat;
    const sm = sideMat < 0 ? mat : sideMat;
    const cs = F_COLOR | F_SHADOW;
    this.quad(v3(mn.x, mn.y, mx.z), v3(mx.x, mn.y, mx.z), v3(mx.x, mx.y, mx.z), v3(mn.x, mx.y, mx.z), tm, o, v3(0, 0, 1), cs, { x: mn.x, y: mn.y });
    this.quad(v3(mn.x, mx.y, mx.z), v3(mx.x, mx.y, mx.z), v3(mx.x, mx.y, mn.z), v3(mn.x, mx.y, mn.z), sm, o, v3(0, 1, 0), cs, { x: mn.x, y: -mx.z });
    this.quad(v3(mx.x, mx.y, mx.z), v3(mx.x, mn.y, mx.z), v3(mx.x, mn.y, mn.z), v3(mx.x, mx.y, mn.z), sm, o, v3(1, 0, 0), cs, { x: -mx.y, y: -mx.z });
    this.quad(v3(mn.x, mn.y, mx.z), v3(mn.x, mx.y, mx.z), v3(mn.x, mx.y, mn.z), v3(mn.x, mn.y, mn.z), sm, o, v3(-1, 0, 0), F_SHADOW);
    this.quad(v3(mx.x, mn.y, mx.z), v3(mn.x, mn.y, mx.z), v3(mn.x, mn.y, mn.z), v3(mx.x, mn.y, mn.z), sm, o, v3(0, -1, 0), F_SHADOW);
  }

  // Oriented box: centre c, unit axes u, v, w, half extents he = {x, y, z}.
  obox(c, u, v, w, he, mat, o = 0) {
    const ax = [mul(u, he.x), mul(v, he.y), mul(w, he.z)];
    const nr = [u, v, w];
    for (let i = 0; i < 3; i++) {
      const a = ax[i];
      const b = ax[(i + 1) % 3];
      const d = ax[(i + 2) % 3];
      for (const s of [-1, 1]) {
        const fc = add(c, mul(a, s));
        const n = mul(nr[i], s);
        const p0 = sub(sub(fc, b), d);
        const p1 = sub(add(fc, b), d);
        const p2 = add(add(fc, b), d);
        const p3 = add(sub(fc, b), d);
        this.quad(p0, p1, p2, p3, mat, o, n);
      }
    }
  }

  // A beam from a to b with a square section t (roll fixed by `up`).
  beam(a, b, t, mat, o = 0, up = v3(0, 0, 1)) {
    const dir = sub(b, a);
    const l = len(dir);
    if (l < 1e-4) return;
    const u = mul(dir, 1 / l);
    let ref = up;
    if (Math.abs(dot(u, ref)) > 0.95) ref = Math.abs(u.x) < 0.9 ? v3(1, 0, 0) : v3(0, 1, 0);
    const v = norm(cross(u, ref));
    const w = norm(cross(v, u));
    this.obox(mul(add(a, b), 0.5), u, v, w, { x: l * 0.5, y: t * 0.5, z: t * 0.5 }, mat, o);
  }

  // Vertical n-gon prism.
  cylZ(c, r, h, mat, o = 0, sides = 10, topMat = -1) {
    const tm = topMat < 0 ? mat : topMat;
    for (let i = 0; i < sides; i++) {
      const a0 = (TAU * i) / sides;
      const a1 = (TAU * (i + 1)) / sides;
      const p0 = add(c, v3(Math.cos(a0) * r, Math.sin(a0) * r, 0));
      const p1 = add(c, v3(Math.cos(a1) * r, Math.sin(a1) * r, 0));
      const n = v3(Math.cos((a0 + a1) / 2), Math.sin((a0 + a1) / 2), 0);
      const up = v3(0, 0, h);
      this.quad(add(p0, up), add(p1, up), p1, p0, mat, o, n, F_COLOR | F_SHADOW, { x: r * a0, y: -h });
      this.tri(add(c, up), add(p0, up), add(p1, up), tm, o, { x: c.x, y: c.y }, { x: p0.x, y: p0.y }, { x: p1.x, y: p1.y }, v3(0, 0, 1));
    }
  }

  // Cylinder along any axis from a to b.
  cyl(a, b, r, mat, o = 0, sides = 8) {
    const dir = sub(b, a);
    const l = len(dir);
    if (l < 1e-4) return;
    const u = mul(dir, 1 / l);
    const ref = Math.abs(u.z) < 0.9 ? v3(0, 0, 1) : v3(1, 0, 0);
    const v = norm(cross(u, ref));
    const w = norm(cross(v, u));
    const ring = (ang) => add(mul(v, Math.cos(ang) * r), mul(w, Math.sin(ang) * r));
    for (let i = 0; i < sides; i++) {
      const a0 = (TAU * i) / sides;
      const a1 = (TAU * (i + 1)) / sides;
      const o0 = ring(a0);
      const o1 = ring(a1);
      const n = norm(add(mul(v, Math.cos((a0 + a1) / 2)), mul(w, Math.sin((a0 + a1) / 2))));
      this.quad(add(a, o0), add(b, o0), add(b, o1), add(a, o1), mat, o, n, F_COLOR | F_SHADOW, { x: 0, y: r * a0 });
    }
    for (const [cc, nn] of [[a, mul(u, -1)], [b, u]]) {
      for (let i = 0; i < sides; i++) {
        const a0 = (TAU * i) / sides;
        const a1 = (TAU * (i + 1)) / sides;
        this.tri(cc, add(cc, ring(a0)), add(cc, ring(a1)), mat, o, null, null, null, nn);
      }
    }
  }

  pyramid(mn, mx, z, rise, mat, o = 0) {
    const apex = v3((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, z + rise);
    const c = [v3(mn.x, mn.y, z), v3(mx.x, mn.y, z), v3(mx.x, mx.y, z), v3(mn.x, mx.y, z)];
    for (let i = 0; i < 4; i++) {
      const p0 = c[i];
      const p1 = c[(i + 1) % 4];
      let n = norm(cross(sub(p1, p0), sub(apex, p0)));
      if (n.z < 0) n = mul(n, -1);
      const lb = len(sub(p1, p0));
      const sl = len(sub(mul(add(p0, p1), 0.5), apex));
      this.tri(p0, p1, apex, mat, o, { x: 0, y: sl }, { x: lb, y: sl }, { x: lb / 2, y: 0 }, n);
    }
  }

  // Gable roof along x (alongX) or y over mn..mx at height z.
  gable(mn, mx, z, rise, alongX, mat, endMat, o = 0) {
    if (alongX) {
      const ym = (mn.y + mx.y) / 2;
      const r0 = v3(mn.x, ym, z + rise);
      const r1 = v3(mx.x, ym, z + rise);
      const s = norm(v3(0, (mx.y - mn.y) / 2, rise));
      const ny = s.z;
      const nz = s.y;
      this.quad(r0, r1, v3(mx.x, mx.y, z), v3(mn.x, mx.y, z), mat, o, norm(v3(0, ny, nz)));
      this.quad(r1, r0, v3(mn.x, mn.y, z), v3(mx.x, mn.y, z), mat, o, norm(v3(0, -ny, nz)));
      this.tri(v3(mx.x, mn.y, z), v3(mx.x, mx.y, z), r1, endMat, o, null, null, null, v3(1, 0, 0));
      this.tri(v3(mn.x, mn.y, z), v3(mn.x, mx.y, z), r0, endMat, o, null, null, null, v3(-1, 0, 0));
    } else {
      const xm = (mn.x + mx.x) / 2;
      const r0 = v3(xm, mn.y, z + rise);
      const r1 = v3(xm, mx.y, z + rise);
      const s = norm(v3((mx.x - mn.x) / 2, 0, rise));
      const nx = s.z;
      const nz = s.x;
      this.quad(r0, r1, v3(mx.x, mx.y, z), v3(mx.x, mn.y, z), mat, o, norm(v3(nx, 0, nz)));
      this.quad(r1, r0, v3(mn.x, mn.y, z), v3(mn.x, mx.y, z), mat, o, norm(v3(-nx, 0, nz)));
      this.tri(v3(mn.x, mx.y, z), v3(mx.x, mx.y, z), r1, endMat, o, null, null, null, v3(0, 1, 0));
      this.tri(v3(mn.x, mn.y, z), v3(mx.x, mn.y, z), r0, endMat, o, null, null, null, v3(0, -1, 0));
    }
  }

  // --- rendering --------------------------------------------------------------------------

  render() {
    this.buildShadowMap();
    this.renderColor();
  }

  buildShadowMap() {
    const L = this.sun;
    const e1 = norm(cross(L, v3(0, 0, 1)));
    const e2 = norm(cross(e1, L));
    let mnx = 1e9, mny = 1e9, mxx = -1e9, mxy = -1e9;
    for (const t of this.tris) {
      if (!(t.f & F_SHADOW)) continue;
      for (const p of [t.a, t.b, t.c]) {
        const u = dot(p, e1);
        const v = dot(p, e2);
        if (u < mnx) mnx = u;
        if (v < mny) mny = v;
        if (u > mxx) mxx = u;
        if (v > mxy) mxy = v;
      }
    }
    const W = Math.min(Math.ceil((mxx - mnx) / SM_RES) + 2, 4096);
    const H = Math.min(Math.ceil((mxy - mny) / SM_RES) + 2, 4096);
    const sm = new Float32Array(W * H).fill(-1e9);
    for (const t of this.tris) {
      if (!(t.f & F_SHADOW)) continue;
      const sa = { x: (dot(t.a, e1) - mnx) / SM_RES, y: (dot(t.a, e2) - mny) / SM_RES };
      const sb = { x: (dot(t.b, e1) - mnx) / SM_RES, y: (dot(t.b, e2) - mny) / SM_RES };
      const sc = { x: (dot(t.c, e1) - mnx) / SM_RES, y: (dot(t.c, e2) - mny) / SM_RES };
      rasterTri(sa, sb, sc, W, H, -0.01, (x, y, w0, w1, w2) => {
        const d = dot(t.a, L) * w0 + dot(t.b, L) * w1 + dot(t.c, L) * w2;
        const i = y * W + x;
        if (d > sm[i]) sm[i] = d;
      });
    }
    this.sm = { data: sm, w: W, h: H, mnx, mny, e1, e2 };
  }

  // 1 lit, 0 shadowed, for a surface point with normal n.
  sunVis(p, n = v3(0, 0, 1)) {
    const s = this.sm;
    if (!s) return 1;
    const u = Math.floor((dot(p, s.e1) - s.mnx) / SM_RES);
    const v = Math.floor((dot(p, s.e2) - s.mny) / SM_RES);
    if (u < 0 || v < 0 || u >= s.w || v >= s.h) return 1;
    const bias = 0.2 + 0.45 * (1 - clamp(dot(n, this.sun), 0, 1));
    return dot(p, this.sun) >= s.data[v * s.w + u] - bias ? 1 : 0;
  }

  renderColor() {
    const { w, h, col, dep, oid } = this;
    for (const t of this.tris) {
      if (!(t.f & F_COLOR)) continue;
      let n = t.n;
      if (dot(n, VIEW) <= 0) {
        if (t.f & F_TWO_SIDED) n = mul(n, -1);
        else continue;
      }
      const sa = this.project(t.a);
      const sb = this.project(t.b);
      const sc = this.project(t.c);
      const ndl = Math.max(dot(n, this.sun), 0);
      const { a, b, c, ua, ub, uc, mat, o } = t;
      const da = depthOf(a), db = depthOf(b), dc = depthOf(c);
      rasterTri(sa, sb, sc, w, h, 0, (x, y, w0, w1, w2) => {
        const d = da * w0 + db * w1 + dc * w2;
        const i = y * w + x;
        if (d <= dep[i]) return;
        const wp = {
          x: a.x * w0 + b.x * w1 + c.x * w2,
          y: a.y * w0 + b.y * w1 + c.y * w2,
          z: a.z * w0 + b.z * w1 + c.z * w2,
        };
        const sh = ndl > 0 ? this.sunVis(wp, n) : 1;
        const light = AMB + DIF * ndl * sh;
        const uv = { x: ua.x * w0 + ub.x * w1 + uc.x * w2, y: ua.y * w0 + ub.y * w1 + uc.y * w2 };
        const cc = shade(mat, wp, n, uv, light, sh, x, y);
        if (!cc) return;
        col[i * 3] = cc[0];
        col[i * 3 + 1] = cc[1];
        col[i * 3 + 2] = cc[2];
        dep[i] = d;
        oid[i] = o;
        if (cc.length > 3) {
          this.glow[i * 3] += cc[0] * cc[3];
          this.glow[i * 3 + 1] += cc[1] * cc[3];
          this.glow[i * 3 + 2] += cc[2] * cc[3];
        }
      });
    }
  }

  // --- sprites and effects ----------------------------------------------------------------

  // sprite: {w, h, px: Array of [r,g,b] or null}. The anchor pixel stands on world point base.
  stamp(spr, base, ax, ay, o = 0, shadeIt = true, flip = false) {
    const s = this.project(base);
    const bx = Math.round(s.x) - ax;
    const by = Math.round(s.y) - ay;
    const bd = depthOf(base) + 0.35;
    const k = shadeIt ? 0.62 + 0.38 * this.sunVis(add(base, v3(0, 0, 0.6))) : 1;
    for (let iy = 0; iy < spr.h; iy++) {
      const y = by + iy;
      if (y < 0 || y >= this.h) continue;
      const up = (ay - iy) / this.k;
      for (let ix = 0; ix < spr.w; ix++) {
        const c = spr.px[iy * spr.w + (flip ? spr.w - 1 - ix : ix)];
        if (!c) continue;
        const x = bx + ix;
        if (x < 0 || x >= this.w) continue;
        const i = y * this.w + x;
        const d = bd + up;
        if (d <= this.dep[i]) continue;
        this.col[i * 3] = c[0] * k;
        this.col[i * 3 + 1] = c[1] * k;
        this.col[i * 3 + 2] = c[2] * k;
        this.dep[i] = d;
        this.oid[i] = o;
      }
    }
  }

  // A depth-tested point; alpha < 1 blends; emissive adds to the glow buffer.
  point(p, c, size = 1, writeDepth = true, emissive = 0, alpha = 1) {
    const s = this.project(p);
    const d = depthOf(p);
    const x0 = Math.floor(s.x - size * 0.5 + 0.5);
    const y0 = Math.floor(s.y - size * 0.5 + 0.5);
    for (let yy = 0; yy < size; yy++) {
      const y = y0 + yy;
      if (y < 0 || y >= this.h) continue;
      for (let xx = 0; xx < size; xx++) {
        const x = x0 + xx;
        if (x < 0 || x >= this.w) continue;
        const i = y * this.w + x;
        if (d <= this.dep[i]) continue;
        for (let k = 0; k < 3; k++) this.col[i * 3 + k] = this.col[i * 3 + k] * (1 - alpha) + c[k] * alpha;
        if (writeDepth) this.dep[i] = d;
        if (emissive > 0) for (let k = 0; k < 3; k++) this.glow[i * 3 + k] += c[k] * emissive;
      }
    }
  }

  line3(a, b, c, writeDepth = true, emissive = 0) {
    const sa = this.project(a);
    const sb = this.project(b);
    const steps = Math.max(Math.ceil(Math.max(Math.abs(sb.x - sa.x), Math.abs(sb.y - sa.y))), 1);
    for (let i = 0; i <= steps; i++) this.point(lerp3(a, b, i / steps), c, 1, writeDepth, emissive);
  }

  // Back-projects screen pixel (x, y) onto the plane z.
  unproject(x, y, z) {
    const d = (x - this.ox) / this.k;
    const s = (2 * (y - this.oy + z * this.k)) / this.k;
    const gx = (d + s) / 2;
    return v3(gx, gx - d, z);
  }

  // Darkens the ground in a capsule from p away from the sun, where the stored depth is the
  // ground's (sprites aren't in the shadow map).
  groundShadow(p, radius, heightM, k = 0.7) {
    const off = mul(norm(v3(-this.sun.x, -this.sun.y, 0)), heightM * 0.7);
    const c = add(p, mul(off, 0.5));
    const r = radius + len(off) * 0.5;
    const s = this.project(c);
    const rx = Math.ceil(r * this.k * 1.6) + 1;
    const ry = Math.ceil(r * this.k) + 1;
    const ol2 = dot(off, off);
    for (let yy = -ry; yy <= ry; yy++) {
      for (let xx = -rx; xx <= rx; xx++) {
        const x = Math.floor(s.x) + xx;
        const y = Math.floor(s.y) + yy;
        if (x < 0 || y < 0 || x >= this.w || y >= this.h) continue;
        const g = this.unproject(x + 0.5, y + 0.5, p.z);
        const t = ol2 > 1e-4 ? clamp(dot(sub(g, p), off) / ol2, 0, 1) : 0;
        if (len(sub(g, add(p, mul(off, t))) ) > radius) continue;
        const i = y * this.w + x;
        if (Math.abs(this.dep[i] - depthOf(g)) > 1.2) continue;
        for (let q = 0; q < 3; q++) this.col[i * 3 + q] *= k;
      }
    }
  }

  // --- post -------------------------------------------------------------------------------

  // Sky, depth-edge outline, glow, tilt-shift blur by row, grade and vignette. Returns Float32 RGB.
  finish({ skyTop, skyBottom, focusY = 300, focusHalf = 90, ramp = 150, maxBlur = 1.6, outline = true }) {
    const { w, h, dep } = this;
    const base = new Float32Array(this.col);
    for (let y = 0; y < h; y++) {
      const t = y / h;
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        if (dep[i] < -1e8) for (let k = 0; k < 3; k++) base[i * 3 + k] = skyTop[k] + (skyBottom[k] - skyTop[k]) * t;
      }
    }
    const img = new Float32Array(base);
    if (outline) {
      for (let y = 1; y < h - 1; y++) {
        for (let x = 1; x < w - 1; x++) {
          const i = y * w + x;
          const near = Math.max(dep[i - 1], dep[i + 1], dep[i - w], dep[i + w]);
          if (near > dep[i] + 2.5) {
            img[i * 3] = base[i * 3] * 0.62;
            img[i * 3 + 1] = base[i * 3 + 1] * 0.58;
            img[i * 3 + 2] = base[i * 3 + 2] * 0.62;
          }
        }
      }
    }
    const glow = blur(this.glow, w, h, 6, 3);
    const b1 = blur(img, w, h, 1, 2);
    const b2 = blur(img, w, h, 2, 3);
    const out = new Float32Array(w * h * 3);
    const cx = w / 2, cy = h / 2;
    for (let y = 0; y < h; y++) {
      const dist = Math.max(Math.abs(y - focusY) - focusHalf, 0);
      const amt = clamp(dist / ramp, 0, 1) * maxBlur;
      for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 3;
        const vx = (x - cx) / cx, vy = (y - cy) / cy;
        const vig = 1 - 0.12 * clamp(vx * vx + vy * vy - 0.35, 0, 1);
        for (let k = 0; k < 3; k++) {
          let c = img[i + k];
          if (amt > 0) c = amt <= 1 ? c + (b1[i + k] - c) * amt : b1[i + k] + (b2[i + k] - b1[i + k]) * Math.min(amt - 1, 1);
          c += glow[i + k] * 1.4 + this.glow[i + k] * 0.4;
          const warm = k === 0 ? 1.03 : k === 2 ? 0.95 : 1;
          c = c * warm + (k === 0 ? 0.01 : 0);
          c = (c - 0.5) * 1.1 + 0.5;
          out[i + k] = c * vig;
        }
        // a little more saturation
        const l = out[i] * 0.3 + out[i + 1] * 0.59 + out[i + 2] * 0.11;
        for (let k = 0; k < 3; k++) out[i + k] = clamp(l + (out[i + k] - l) * 1.1, 0, 1);
      }
    }
    return out;
  }
}

// Calls fn(x, y, w0, w1, w2) for every pixel centre inside the triangle (screen coords).
export function rasterTri(sa, sb, sc, W, H, eps, fn) {
  const area = (sb.x - sa.x) * (sc.y - sa.y) - (sb.y - sa.y) * (sc.x - sa.x);
  if (Math.abs(area) < 1e-6) return;
  const x0 = Math.max(Math.floor(Math.min(sa.x, sb.x, sc.x)), 0);
  const x1 = Math.min(Math.ceil(Math.max(sa.x, sb.x, sc.x)), W - 1);
  const y0 = Math.max(Math.floor(Math.min(sa.y, sb.y, sc.y)), 0);
  const y1 = Math.min(Math.ceil(Math.max(sa.y, sb.y, sc.y)), H - 1);
  if (x0 > x1 || y0 > y1) return;
  const inv = 1 / area;
  for (let y = y0; y <= y1; y++) {
    const py = y + 0.5;
    for (let x = x0; x <= x1; x++) {
      const px = x + 0.5;
      const w0 = ((sc.x - sb.x) * (py - sb.y) - (sc.y - sb.y) * (px - sb.x)) * inv;
      const w1 = ((sa.x - sc.x) * (py - sc.y) - (sa.y - sc.y) * (px - sc.x)) * inv;
      const w2 = 1 - w0 - w1;
      if (w0 < eps || w1 < eps || w2 < eps) continue;
      fn(x, y, w0, w1, w2);
    }
  }
}

// Separable box blur, `passes` times (about gaussian), radius r, on RGB floats.
export function blur(src, w, h, r, passes) {
  let a = new Float32Array(src);
  let b = new Float32Array(src.length);
  const n = 2 * r + 1;
  for (let p = 0; p < passes; p++) {
    for (let y = 0; y < h; y++) {
      for (let k = 0; k < 3; k++) {
        let acc = 0;
        for (let x = -r; x <= r; x++) acc += a[(y * w + clamp(x, 0, w - 1)) * 3 + k];
        for (let x = 0; x < w; x++) {
          b[(y * w + x) * 3 + k] = acc / n;
          acc += a[(y * w + clamp(x + r + 1, 0, w - 1)) * 3 + k] - a[(y * w + clamp(x - r, 0, w - 1)) * 3 + k];
        }
      }
    }
    for (let x = 0; x < w; x++) {
      for (let k = 0; k < 3; k++) {
        let acc = 0;
        for (let y = -r; y <= r; y++) acc += b[(clamp(y, 0, h - 1) * w + x) * 3 + k];
        for (let y = 0; y < h; y++) {
          a[(y * w + x) * 3 + k] = acc / n;
          acc += b[(clamp(y + r + 1, 0, h - 1) * w + x) * 3 + k] - b[(clamp(y - r, 0, h - 1) * w + x) * 3 + k];
        }
      }
    }
  }
  return a;
}
