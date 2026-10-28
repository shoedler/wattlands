// Minimal PNG writer (RGBA8, no filtering) for the art tool.
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const CRC = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  CRC[n] = c >>> 0;
}

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, 'ascii');
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

/** rgba: Uint8Array of w*h*4. */
export function writePng(path, w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const png = Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, png);
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
