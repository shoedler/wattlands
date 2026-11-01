// Builds the README's images in this folder from the real frames in build/readme_frames/
// (assets/readme/render_frames.sh renders those). No dependencies beyond the repo's PNG reader.
//
//   bash assets/readme/render_frames.sh
//   node assets/readme/compose.mjs
//
// hero.png: four cuts of the games' own frames, with the name in Torque Company's stencil face.
// screen_*.png: the frames as rendered; only a frame over MAX_BYTES is reduced to 256 colours.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { decodePng, encodePng, crc32 } from '../../tools/art/lib/png.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const frames = path.join(root, 'build/readme_frames');
const MAX_BYTES = 600 * 1024;

const onlyPng = (dir) => {
  const names = fs.readdirSync(path.join(frames, dir)).filter((n) => n.endsWith('.png'));
  if (names.length !== 1) throw new Error(`${dir}: expected one PNG, found ${names.length}`);
  return path.join(frames, dir, names[0]);
};
const load = (file) => {
  const p = decodePng(fs.readFileSync(file));
  return { w: p.width, h: p.height, px: p.data };
};
const canvas = (w, h) => ({ w, h, px: new Uint8Array(w * h * 4) });

/** Copies a cut of src to dst where inside(x, y) holds (dst coordinates). */
function blit(dst, src, sx, sy, dx, dy, w, h, inside = () => true) {
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const tx = dx + x;
      const ty = dy + y;
      if (tx < 0 || ty < 0 || tx >= dst.w || ty >= dst.h || !inside(tx, ty)) continue;
      const s = ((sy + y) * src.w + sx + x) * 4;
      const d = (ty * dst.w + tx) * 4;
      for (let c = 0; c < 3; c++) dst.px[d + c] = src.px[s + c];
      dst.px[d + 3] = 255;
    }
  }
}

function rect(img, x0, y0, w, h, [r, g, b], inside = () => true) {
  for (let y = y0; y < y0 + h; y++) {
    for (let x = x0; x < x0 + w; x++) {
      if (x < 0 || y < 0 || x >= img.w || y >= img.h || !inside(x, y)) continue;
      const d = (y * img.w + x) * 4;
      img.px[d] = r;
      img.px[d + 1] = g;
      img.px[d + 2] = b;
      img.px[d + 3] = 255;
    }
  }
}

/** The stencil faces: 16 x 7 cells of the game's font PNG, characters from 32. */
function face(file, cellW, cellH) {
  const img = load(path.join(root, file));
  return {
    img,
    cellW,
    cellH,
    ink(ch, x, y) {
      const i = ch.charCodeAt(0) - 32;
      const sx = (i % 16) * cellW + x;
      const sy = Math.floor(i / 16) * cellH + y;
      return img.px[(sy * img.w + sx) * 4 + 3] > 127;
    },
  };
}

function textWidth(font, text, scale, track = 0) {
  return (text.length * (font.cellW + track) - 1 - track) * scale;
}

/** Draws text; colorAt(row) picks the colour by the font's pixel row. */
function text(img, font, str, x0, y0, scale, colorAt, track = 0) {
  let cx = x0;
  for (const ch of str) {
    for (let y = 0; y < font.cellH; y++) {
      for (let x = 0; x < font.cellW; x++) {
        if (font.ink(ch, x, y)) rect(img, cx + x * scale, y0 + y * scale, scale, scale, colorAt(y));
      }
    }
    cx += (font.cellW + track) * scale;
  }
}

function hero() {
  const W = 1600;
  const PANEL = 320;
  const BAND = 170;
  const H = PANEL * 2 + BAND;
  const SLANT = 40; // the seams' lean over a panel's height, in px
  const STEP = 4; // one seam step: whole art pixels at 2x
  const SEAM_W = 6;
  const out = canvas(W, H);

  const tank = load(onlyPng('tank_plate'));
  const siege = load(onlyPng('siege'));
  const road = load(path.join(frames, 'workout/sprint_4.png'));
  const ocean = load(onlyPng('fishing_wreck'));

  const seam = (y, top, centre) =>
    centre + SLANT / 2 - Math.round(((y - top) / PANEL) * (SLANT / STEP)) * STEP;
  const yTop = 0;
  const yBot = PANEL + BAND;
  const cTop = 900;
  const cBot = 800;
  const left = (top, c) => (x, y) => x < seam(y, top, c);
  const right = (top, c) => (x, y) => x >= seam(y, top, c) + SEAM_W;
  const wall = (top, c) => (x, y) => x >= seam(y, top, c) && x < seam(y, top, c) + SEAM_W;

  // Top row: the whole landship, the fort's four wheels. Bottom row: the sprint, the fish.
  // Every cut stays clear of the HUD: the fish's cut ends left of its fight panel.
  blit(out, tank, 66, 456, 0, yTop, 960, PANEL, left(yTop, cTop));
  blit(out, siege, 640, 190, 860, yTop, 740, PANEL, right(yTop, cTop));
  blit(out, road, 180, 488, 0, yBot, 860, PANEL, left(yBot, cBot));
  blit(out, ocean, 135, 580, 760, yBot, 840, PANEL, right(yBot, cBot));
  rect(out, 0, yTop, W, PANEL, [12, 14, 16], wall(yTop, cTop));
  rect(out, 0, yBot, W, PANEL, [12, 14, 16], wall(yBot, cBot));

  // The band between them: the tank's own night sky, mirrored out to the full width.
  const SKY = 1240;
  for (let y = 0; y < BAND; y++) {
    for (let x = 0; x < W; x++) {
      const sx = x < SKY ? x : 2 * SKY - 1 - x;
      const s = ((40 + y) * tank.w + sx) * 4;
      const d = ((PANEL + y) * W + x) * 4;
      for (let c = 0; c < 3; c++) out.px[d + c] = tank.px[s + c];
      out.px[d + 3] = 255;
    }
  }
  rect(out, 0, PANEL, W, 4, [176, 128, 62]);
  rect(out, 0, PANEL + BAND - 4, W, 4, [176, 128, 62]);
  for (let x = 12; x < W; x += 40) {
    rect(out, x, PANEL + 1, 2, 2, [240, 206, 140]);
    rect(out, x, PANEL + BAND - 3, 2, 2, [240, 206, 140]);
  }

  const tall = face('assets/tank/hud/tank_stencil_5x9.png', 6, 11);
  const small = face('assets/tank/hud/tank_stencil_5x7.png', 6, 9);
  const SCALE = 12;
  const title = 'WATTLANDS';
  const tw = textWidth(tall, title, SCALE);
  const tx = Math.floor((W - tw) / 2);
  const ty = PANEL + 16;
  const ramp = (row) => (row < 4 ? [245, 234, 208] : row < 7 ? [240, 208, 150] : [222, 164, 84]);
  text(out, tall, title, tx + 6, ty + 6, SCALE, () => [8, 10, 12]);
  text(out, tall, title, tx, ty, SCALE, ramp);

  const sub = 'YOUR PEDALING IS THE CONTROLLER';
  const sw = textWidth(small, sub, 3);
  const sy = ty + 9 * SCALE + 6;
  text(out, small, sub, Math.floor((W - sw) / 2) + 2, sy + 2, 3, () => [8, 10, 12]);
  text(out, small, sub, Math.floor((W - sw) / 2), sy, 3, () => [240, 208, 150]);
  return out;
}

/** Median cut to at most 256 colours, no dither: pixel art keeps its flat areas. */
function quantize(img) {
  const hist = new Map();
  for (let i = 0; i < img.px.length; i += 4) {
    const k = (img.px[i] << 16) | (img.px[i + 1] << 8) | img.px[i + 2];
    hist.set(k, (hist.get(k) ?? 0) + 1);
  }
  const colors = [...hist.entries()].map(([k, n]) => [(k >> 16) & 255, (k >> 8) & 255, k & 255, n]);
  const boxes = [colors];
  const spread = (box, c) => {
    let lo = 255;
    let hi = 0;
    for (const p of box) {
      if (p[c] < lo) lo = p[c];
      if (p[c] > hi) hi = p[c];
    }
    return hi - lo;
  };
  while (boxes.length < 256) {
    let best = -1;
    let bestScore = 0;
    let bestChan = 0;
    boxes.forEach((box, i) => {
      if (box.length < 2) return;
      const count = box.reduce((a, p) => a + p[3], 0);
      for (let c = 0; c < 3; c++) {
        const score = spread(box, c) * Math.sqrt(count);
        if (score > bestScore) {
          best = i;
          bestScore = score;
          bestChan = c;
        }
      }
    });
    if (best < 0) break;
    const box = boxes[best].sort((a, b) => a[bestChan] - b[bestChan]);
    const half = box.reduce((a, p) => a + p[3], 0) / 2;
    let run = 0;
    let cut = 1;
    for (let i = 0; i < box.length - 1; i++) {
      run += box[i][3];
      if (run >= half) {
        cut = i + 1;
        break;
      }
    }
    boxes.splice(best, 1, box.slice(0, cut), box.slice(cut));
  }
  const palette = boxes.map((box) => {
    const n = box.reduce((a, p) => a + p[3], 0);
    return [0, 1, 2].map((c) => Math.round(box.reduce((a, p) => a + p[c] * p[3], 0) / n));
  });
  const lut = new Map();
  boxes.forEach((box, i) => {
    for (const p of box) lut.set((p[0] << 16) | (p[1] << 8) | p[2], i);
  });
  const index = new Uint8Array(img.w * img.h);
  for (let i = 0; i < index.length; i++) {
    const d = i * 4;
    index[i] = lut.get((img.px[d] << 16) | (img.px[d + 1] << 8) | img.px[d + 2]);
  }
  return { palette, index };
}

function encodeIndexed(w, h, { palette, index }) {
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 3; // palette
  const raw = Buffer.alloc((w + 1) * h);
  for (let y = 0; y < h; y++) {
    Buffer.from(index.buffer, index.byteOffset + y * w, w).copy(raw, y * (w + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('PLTE', Buffer.from(palette.flat())),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function save(name, img) {
  const rgb = encodePng(img.w, img.h, img.px, { level: 9 });
  const png = rgb.length > MAX_BYTES ? encodeIndexed(img.w, img.h, quantize(img)) : rgb;
  fs.writeFileSync(path.join(here, name), png);
  console.log(`${name}: ${img.w} x ${img.h}, ${Math.round(png.length / 1024)} KB`);
}

save('hero.png', hero());
save('screen_turbo_reel.png', load(onlyPng('fishing_wreck')));
save('screen_castellum_rotae.png', load(onlyPng('siege')));
save('screen_workout.png', load(path.join(frames, 'workout/sprint_4.png')));
save('screen_torque_company.png', load(onlyPng('tank')));
