#!/usr/bin/env node
// MOCKUP: renders the Castellum Rotae v2 look into build/siege_mock/ (art resolution, x2, and a
// sharp variant without tilt-shift).   node src/games/siege/art/mock.mjs [--out=<dir>]
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Raster } from './raster.mjs';
import { Scene } from './scene.mjs';
import { Life } from './life.mjs';
import { hex } from './v3.mjs';
import * as W from './world.mjs';
import { writePng, toRgba8 } from './png.mjs';

const repo = join(dirname(fileURLToPath(import.meta.url)), '../../../..');
const arg = (k, d) => (process.argv.find((a) => a.startsWith(`--${k}=`)) ?? `=${d}`).split('=')[1];
const out = arg('out', join(repo, 'build/siege_mock'));
const t0 = Date.now();
W.build();
const r = new Raster(960, 540, Number(arg('ox', 480)), Number(arg('oy', 96)), Number(arg('k', 4.5)));
const scene = new Scene(r);
scene.build();
console.log(`mock: ${r.tris.length} triangles, built in ${Date.now() - t0} ms`);
r.render();
console.log(`mock: rendered at ${Date.now() - t0} ms`);
new Life(r, scene).run();
const post = { skyTop: hex('#c9d3d6'), skyBottom: hex('#e4d6b8') };
const sharp = r.finish({ ...post, maxBlur: 0 });
const frame = r.finish({ ...post, focusY: Number(arg('fy', 305)), focusHalf: 125, ramp: 170, maxBlur: 1.35 });
const save = (name, img, scale) => {
  const o = toRgba8(960, 540, img, scale);
  writePng(join(out, name), o.w, o.h, o.data);
};
save('frame.png', frame, 1);
save('frame_2x.png', frame, 2);
save('frame_sharp_2x.png', sharp, 2);
// detail crops of the sharp frame at x4 (art px rectangles), and a 2 x 2 sheet of four of them
const crops = {
  wheels: [430, 75, 240, 135], gate: [290, 245, 240, 135], mine: [650, 110, 240, 135], army: [20, 225, 240, 135],
  ballista: [140, 100, 240, 135], catapult: [300, 150, 240, 135],
};
const cut = ([cx, cy, cw, ch]) => {
  const sub = new Float32Array(cw * ch * 3);
  for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) {
    const sx = Math.min(Math.max(cx + x, 0), 959), sy = Math.min(Math.max(cy + y, 0), 539);
    for (let k = 0; k < 3; k++) sub[(y * cw + x) * 3 + k] = sharp[(sy * 960 + sx) * 3 + k];
  }
  return sub;
};
for (const [name, rect] of Object.entries(crops)) {
  const o = toRgba8(rect[2], rect[3], cut(rect), 4);
  writePng(join(out, `crop_${name}.png`), o.w, o.h, o.data);
}
const sheet = new Float32Array(480 * 270 * 3);
['wheels', 'gate', 'mine', 'army'].forEach((name, q) => {
  const sub = cut(crops[name]);
  const ox = (q % 2) * 240, oy = Math.floor(q / 2) * 135;
  for (let y = 0; y < 135; y++) for (let x = 0; x < 240; x++) for (let k = 0; k < 3; k++) {
    const edge = x === 0 || y === 0;
    sheet[((oy + y) * 480 + ox + x) * 3 + k] = edge ? 0.1 : sub[(y * 240 + x) * 3 + k];
  }
});
const so = toRgba8(480, 270, sheet, 4);
writePng(join(out, 'details_sheet.png'), so.w, so.h, so.data);
console.log(`mock: done in ${Date.now() - t0} ms -> ${out}`);
