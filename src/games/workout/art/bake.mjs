#!/usr/bin/env node
// Bakes Workout's pixel art into assets/workout/: rider sheets, the indexed world, the time-of-day LUT,
// props, kit.json and the picker card. Deterministic: its own seeded PRNG, no Math.random, no clock.
//
//   node src/games/workout/art/bake.mjs                     writes assets/workout/
//   node src/games/workout/art/bake.mjs --check             re-renders in memory; exit 1 unless the decoded
//                                                           pixels of every PNG and kit.json match
//   node src/games/workout/art/bake.mjs --preview=<dir>     writes the composites for an art round
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { encodePng, readPng, writePng } from './png.mjs';
import { LUT_ROWS, LUT_SIZE, buildLut, buildTod } from './palette.mjs';
import * as R from './rig.mjs';
import { SLOT_COLORS, WHEEL_CELL, WHEEL_FRAMES, fxSheet, riderSheet, wheelSheet } from './riders.mjs';
import * as W from './world.mjs';
import * as Props from './props.mjs';
import { Canvas } from './raster.mjs';
import { pickerCard, previews } from './compose.mjs';

export const SEED = 7342;
const SLOTS = 8;
const VERGE_FRAMES = 4;
const FOREGROUND_FRAMES = 2;

const repo = join(dirname(fileURLToPath(import.meta.url)), '../../../..');
export const ASSETS = join(repo, 'assets/workout');
const res = (path) => `res://assets/workout/${path}`;

function sunSprite() {
  const c = new Canvas(40, 40);
  for (const [r, col] of [
    [19, [255, 214, 150, 50]],
    [15, [255, 222, 160, 110]],
    [11, [255, 240, 196, 255]],
    [9, [255, 250, 226, 255]],
  ]) {
    c.disk(19.5, 19.5, r, col);
  }
  return c;
}

const PLANE_FILES = {
  sky: 'world/sky.png',
  stars: 'world/stars.png',
  clouds_hi: 'world/clouds_hi.png',
  clouds_lo: 'world/clouds_lo.png',
  far_hills: 'world/far_hills.png',
  mid_hills: 'world/mid_hills.png',
  near_trees: 'world/near_trees.png',
  poles: 'world/poles.png',
  road: 'world/road.png',
};
const PROP_FILES = {
  windpump: 'props/windpump.png',
  cattle: 'props/cattle.png',
  tractor: 'props/tractor.png',
  smoke: 'props/smoke.png',
  flock: 'props/flock.png',
  balloon: 'props/balloon.png',
  crowd: 'props/crowd.png',
  flag: 'props/flag.png',
  gantry: 'props/gantry.png',
};

function renderParts() {
  const planes = {
    sky: W.skyPlane(),
    stars: W.starsPlane(SEED),
    clouds_hi: W.cloudsHiPlane(SEED),
    clouds_lo: W.cloudsLoPlane(SEED),
    far_hills: W.farHillsPlane(SEED),
    mid_hills: W.midHillsPlane(SEED),
    near_trees: W.nearTreesPlane(SEED),
    poles: W.polesPlane(),
    road: W.roadPlane(SEED),
  };
  for (let f = 0; f < VERGE_FRAMES; f++) {
    planes[`verge_far_${f}`] = W.vergeFarPlane(SEED, f);
    planes[`verge_near_${f}`] = W.vergeNearPlane(SEED, f);
  }
  for (let f = 0; f < FOREGROUND_FRAMES; f++) planes[`foreground_${f}`] = W.foregroundPlane(SEED, f);
  const props = {};
  for (const key of Object.keys(PROP_FILES)) props[key] = Props[key]();
  return {
    lut: buildLut(),
    sun: sunSprite(),
    planes,
    sheets: Array.from({ length: SLOTS }, (_, s) => riderSheet(s)),
    wheel: wheelSheet(),
    fx: fxSheet(),
    props,
  };
}

const vergePaths = (name) => Array.from({ length: VERGE_FRAMES }, (_, f) => res(`world/${name}_${f}.png`));

/** kit.json. S0 froze the keys; the values may be tuned. */
function buildKit() {
  const prop = (key, rest) => ({ path: res(PROP_FILES[key]), ...rest });
  return {
    version: 1,
    base: [960, 540],
    lut: { path: res('world/tod_lut.png'), size: LUT_SIZE, rows: LUT_ROWS },
    tod: buildTod(),
    rider: {
      cell: R.CELL,
      cols: R.COLS,
      frames: R.CRANK_FRAMES,
      origin: R.ORIGIN,
      rear_hub: R.REAR_HUB,
      front_hub: R.FRONT_HUB,
      pennant_foot: R.PENNANT_FOOT,
      mouth: R.MOUTH,
      bubble: R.BUBBLE,
      rear_contact: R.REAR_CONTACT,
      pose_rows: R.POSE_ROWS,
      slots: Array.from({ length: SLOTS }, (_, s) => res(`riders/slot_${s}.png`)),
      slot_colors: SLOT_COLORS,
      near_pedal: R.nearPedalTable(),
    },
    wheel: {
      path: res('riders/wheel.png'),
      cell: [WHEEL_CELL, WHEEL_CELL],
      frames: WHEEL_FRAMES,
      center: [13, 13],
      radius: R.WHEEL_R,
    },
    fx: {
      path: res('riders/fx.png'),
      breath: [0, 0, 8, 6, 4],
      dust: [0, 6, 10, 6, 4],
      rescue: [0, 12, 9, 9, 2],
      afk: [18, 12, 9, 9, 2],
      link: [36, 12, 9, 9, 2],
    },
    planes: [
      { name: 'sky', path: res(PLANE_FILES.sky), y: -180, factor: 0.0, drift: 0.0 },
      { name: 'stars', path: res(PLANE_FILES.stars), y: -180, factor: 0.0, drift: 0.0 },
      { name: 'clouds_hi', path: res(PLANE_FILES.clouds_hi), y: 20, factor: 0.01, drift: 1.5 },
      { name: 'clouds_lo', path: res(PLANE_FILES.clouds_lo), y: 90, factor: 0.02, drift: 2.5 },
      { name: 'far_hills', path: res(PLANE_FILES.far_hills), y: 170, factor: 0.03, drift: 0.0 },
      { name: 'mid_hills', path: res(PLANE_FILES.mid_hills), y: 215, factor: 0.07, drift: 0.0 },
      { name: 'near_trees', path: res(PLANE_FILES.near_trees), y: 225, factor: 0.18, drift: 0.0 },
      { name: 'poles', path: res(PLANE_FILES.poles), y: 235, factor: 0.45, drift: 0.0 },
      {
        name: 'foreground',
        paths: Array.from({ length: FOREGROUND_FRAMES }, (_, f) => res(`world/foreground_${f}.png`)),
        y: 396,
        factor: 1.35,
        drift: 0.0,
      },
    ],
    sun: { path: res('world/sun.png'), size: [40, 40] },
    road: {
      path: res(PLANE_FILES.road),
      tile: [240, 30],
      contact_row: 14,
      verge_far: { paths: vergePaths('verge_far'), tile: [240, 26], above: 40 },
      verge_near: { paths: vergePaths('verge_near'), tile: [240, 16], below: 16 },
    },
    props: {
      windpump: prop('windpump', { plane: 'near_trees', tower: [0, 0, 30, 70], rotor: [30, 0, 26, 26, 8], hub: [15, 8], base_y: 345 }),
      cattle: prop('cattle', { plane: 'mid_hills', cell: [12, 9], frames: 2, colors: 3, base_y: 320 }),
      tractor: prop('tractor', { cell: [36, 22], frames: 4, base_y: 310 }),
      smoke: prop('smoke', { cell: [10, 16], frames: 6 }),
      flock: prop('flock', { cell: [5, 3], frames: 2 }),
      balloon: prop('balloon', { cell: [18, 26], frames: 1, tod_min_row: 16 }),
      crowd: prop('crowd', { cell: [16, 30], count: 8, foot_above_contact: 16 }),
      flag: prop('flag', { cell: [12, 16], frames: 4 }),
      gantry: prop('gantry', { size: [200, 90], foot_above_contact: 12 }),
    },
  };
}

/** Everything the bake owns: Map of path under assets/workout -> Canvas, plus the kit's JSON text. */
export function render() {
  const parts = renderParts();
  const kit = buildKit();
  const files = new Map();
  files.set('world/tod_lut.png', parts.lut);
  files.set('world/sun.png', parts.sun);
  for (const [name, file] of Object.entries(PLANE_FILES)) files.set(file, parts.planes[name]);
  for (let f = 0; f < VERGE_FRAMES; f++) {
    files.set(`world/verge_far_${f}.png`, parts.planes[`verge_far_${f}`]);
    files.set(`world/verge_near_${f}.png`, parts.planes[`verge_near_${f}`]);
  }
  for (let f = 0; f < FOREGROUND_FRAMES; f++) files.set(`world/foreground_${f}.png`, parts.planes[`foreground_${f}`]);
  parts.sheets.forEach((sheet, s) => files.set(`riders/slot_${s}.png`, sheet));
  files.set('riders/wheel.png', parts.wheel);
  files.set('riders/fx.png', parts.fx);
  for (const [key, file] of Object.entries(PROP_FILES)) files.set(file, parts.props[key]);
  files.set('picker_card.png', pickerCard(parts, kit));
  return { parts, kit, kitText: `${JSON.stringify(kit, null, 1)}\n`, files };
}

function check() {
  const { files, kitText } = render();
  const bad = [];
  for (const [file, canvas] of files) {
    const path = join(ASSETS, file);
    if (!existsSync(path)) {
      bad.push(`${file}: missing`);
      continue;
    }
    const png = readPng(path);
    if (png.width !== canvas.w || png.height !== canvas.h) {
      bad.push(`${file}: ${png.width} x ${png.height}, the bake makes ${canvas.w} x ${canvas.h}`);
    } else if (Buffer.compare(Buffer.from(png.data), Buffer.from(canvas.data)) !== 0) {
      bad.push(`${file}: pixels differ`);
    }
  }
  const kitPath = join(ASSETS, 'kit.json');
  if (!existsSync(kitPath) || readFileSync(kitPath, 'utf8') !== kitText) bad.push('kit.json differs');
  for (const line of bad) console.error(`bake --check: ${line}`);
  if (bad.length > 0) console.error('bake --check: run node src/games/workout/art/bake.mjs');
  else console.log(`bake --check: ${files.size} PNGs and kit.json match`);
  return bad.length === 0 ? 0 : 1;
}

function write() {
  const { files, kitText } = render();
  let bytes = 0;
  for (const [file, canvas] of files) {
    writePng(join(ASSETS, file), canvas.w, canvas.h, canvas.data);
    bytes += encodePng(canvas.w, canvas.h, canvas.data, { level: 9 }).length;
  }
  writeFileSync(join(ASSETS, 'kit.json'), kitText);
  console.log(`bake: ${files.size} PNGs and kit.json in assets/workout (${(bytes / 1e6).toFixed(2)} MB)`);
  return 0;
}

function preview(dir) {
  const { parts, kit } = render();
  const out = resolve(dir);
  mkdirSync(out, { recursive: true });
  for (const [name, canvas] of previews(parts, kit)) writePng(join(out, name), canvas.w, canvas.h, canvas.data);
  console.log(`bake: previews in ${out}`);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const previewArg = process.argv.find((a) => a.startsWith('--preview='));
  let code;
  if (process.argv.includes('--check')) code = check();
  else if (previewArg) code = preview(previewArg.slice('--preview='.length));
  else code = write();
  process.exit(code);
}
