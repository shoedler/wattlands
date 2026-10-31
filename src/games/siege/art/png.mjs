// Siege's PNG helpers: a thin wrapper over the repo's one PNG codec (tools/art/lib/png.mjs).
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { encodePng } from '../../../../tools/art/lib/png.mjs';

/** rgba: Uint8Array of w*h*4. Creates the folder. */
export function writePng(path, w, h, rgba) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, encodePng(w, h, rgba, { level: 9 }));
}

/** Float RGB image (Float32Array w*h*3, 0..1) to RGBA8, optionally scaled up by an integer. */
export function toRgba8(w, h, rgb, scale = 1) {
  const W = w * scale;
  const H = h * scale;
  const out = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y++) {
    const sy = Math.floor(y / scale);
    for (let x = 0; x < W; x++) {
      const si = (sy * w + Math.floor(x / scale)) * 3;
      const di = (y * W + x) * 4;
      out[di] = Math.max(0, Math.min(255, Math.round(rgb[si] * 255)));
      out[di + 1] = Math.max(0, Math.min(255, Math.round(rgb[si + 1] * 255)));
      out[di + 2] = Math.max(0, Math.min(255, Math.round(rgb[si + 2] * 255)));
      out[di + 3] = 255;
    }
  }
  return { w: W, h: H, data: out };
}
