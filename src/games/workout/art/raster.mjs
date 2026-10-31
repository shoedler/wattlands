// Workout's pixel canvas: whole pixels only, no anti-aliasing. A colour is [r, g, b] or [r, g, b, a],
// 0..255, and writes replace the pixel (no blending), so an index plane stays exact.
//   new Canvas(w, h, {wrapX: true})   x wraps, for seamless strips

export const hex = (s) => {
  const v = parseInt(s.replace('#', ''), 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
};

const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/** The 4 x 4 ordered-dither threshold at (x, y), in (0, 1). */
export const bayer4 = (x, y) => (BAYER4[(((y % 4) + 4) % 4) * 4 + (((x % 4) + 4) % 4)] + 0.5) / 16;

/** The repo's seeded PRNG for art: same seed, same sequence, on every machine. */
export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export class Canvas {
  constructor(w, h, { wrapX = false } = {}) {
    this.w = w;
    this.h = h;
    this.wrapX = wrapX;
    this.data = new Uint8Array(w * h * 4);
  }

  _x(x) {
    if (!this.wrapX) return x >= 0 && x < this.w ? x : -1;
    return ((x % this.w) + this.w) % this.w;
  }

  px(x0, y0, c) {
    const x = this._x(Math.round(x0));
    const y = Math.round(y0);
    if (x < 0 || y < 0 || y >= this.h) return;
    const i = (y * this.w + x) * 4;
    this.data[i] = c[0];
    this.data[i + 1] = c[1];
    this.data[i + 2] = c[2];
    this.data[i + 3] = c.length > 3 ? c[3] : 255;
  }

  /** [r, g, b, a] at (x, y), [0, 0, 0, 0] outside. */
  get(x0, y0) {
    const x = this._x(x0);
    if (x < 0 || y0 < 0 || y0 >= this.h) return [0, 0, 0, 0];
    const i = (y0 * this.w + x) * 4;
    return [this.data[i], this.data[i + 1], this.data[i + 2], this.data[i + 3]];
  }

  rect(x, y, w, h, c) {
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.px(x + i, y + j, c);
  }

  /** Bresenham. */
  line(x0, y0, x1, y1, c) {
    let x = Math.round(x0);
    let y = Math.round(y0);
    const xe = Math.round(x1);
    const ye = Math.round(y1);
    const dx = Math.abs(xe - x);
    const dy = -Math.abs(ye - y);
    const sx = x < xe ? 1 : -1;
    const sy = y < ye ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      this.px(x, y, c);
      if (x === xe && y === ye) return;
      const e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y += sy;
      }
    }
  }

  /** A line `w` pixels thick: Bresenham stamped with a small disk (w 1 is line()). */
  thick(x0, y0, x1, y1, w, c) {
    if (w <= 1) {
      this.line(x0, y0, x1, y1, c);
      return;
    }
    const steps = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0), 1);
    for (let i = 0; i <= steps; i++) {
      const t = i / steps;
      this.disk(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, w / 2 - 0.25, c);
    }
  }

  disk(cx, cy, r, c) {
    const lim = Math.ceil(r) + 1;
    const ox = Math.round(cx);
    const oy = Math.round(cy);
    for (let j = -lim; j <= lim; j++) {
      for (let i = -lim; i <= lim; i++) {
        if (i * i + j * j <= r * r + 0.25) this.px(ox + i, oy + j, c);
      }
    }
  }

  /** The pixels between radii r - 0.5 and r + 0.5 around (cx, cy), `w` thick. */
  ring(cx, cy, r, c, w = 1) {
    const lim = Math.ceil(r + w) + 1;
    const ox = Math.round(cx);
    const oy = Math.round(cy);
    for (let j = -lim; j <= lim; j++) {
      for (let i = -lim; i <= lim; i++) {
        const d = Math.sqrt(i * i + j * j);
        if (d >= r - w + 0.5 && d < r + 0.5) this.px(ox + i, oy + j, c);
      }
    }
  }

  /** Even-odd fill at pixel centres. pts: [[x, y], ...]. */
  polyFill(pts, c) {
    let lo = Infinity;
    let hi = -Infinity;
    for (const p of pts) {
      lo = Math.min(lo, p[1]);
      hi = Math.max(hi, p[1]);
    }
    for (let y = Math.floor(lo); y <= Math.ceil(hi); y++) {
      const yc = y + 0.5;
      const xs = [];
      for (let i = 0; i < pts.length; i++) {
        const a = pts[i];
        const b = pts[(i + 1) % pts.length];
        if (a[1] <= yc !== b[1] <= yc) xs.push(a[0] + ((yc - a[1]) / (b[1] - a[1])) * (b[0] - a[0]));
      }
      xs.sort((u, v) => u - v);
      for (let k = 0; k + 1 < xs.length; k += 2) {
        for (let x = Math.ceil(xs[k] - 0.5); x <= Math.floor(xs[k + 1] - 0.5); x++) this.px(x, y, c);
      }
    }
  }

  /** Copies src's opaque-or-partial pixels (alpha above 0) to (dx, dy), replacing what is there. */
  blit(src, dx, dy) {
    for (let y = 0; y < src.h; y++) {
      for (let x = 0; x < src.w; x++) {
        const i = (y * src.w + x) * 4;
        if (src.data[i + 3] > 0) {
          this.px(dx + x, dy + y, [src.data[i], src.data[i + 1], src.data[i + 2], src.data[i + 3]]);
        }
      }
    }
  }

  /** Copies src over this canvas with alpha blending (preview composites only). */
  blend(src, dx, dy) {
    for (let y = 0; y < src.h; y++) {
      for (let x = 0; x < src.w; x++) this.blendPx(dx + x, dy + y, src.get(x, y));
    }
  }

  /** Draws colour c = [r, g, b, a] over the pixel with alpha blending (preview composites only). */
  blendPx(x0, y0, c) {
    const a = c[3] / 255;
    if (a <= 0) return;
    const under = this.get(x0, y0);
    this.px(x0, y0, [
      Math.round(c[0] * a + under[0] * (1 - a)),
      Math.round(c[1] * a + under[1] * (1 - a)),
      Math.round(c[2] * a + under[2] * (1 - a)),
      255,
    ]);
  }

  /** A nearest-neighbour copy `k` times larger (previews only). */
  scaled(k) {
    const out = new Canvas(this.w * k, this.h * k);
    for (let y = 0; y < out.h; y++) {
      for (let x = 0; x < out.w; x++) out.px(x, y, this.get(Math.floor(x / k), Math.floor(y / k)));
    }
    return out;
  }
}
