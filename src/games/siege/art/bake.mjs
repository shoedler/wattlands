#!/usr/bin/env node
// Bakes Castellum Rotae v2's art for the game (docs/games/siege.md 3, "Art pipeline") into
// assets/siege/bake/, from the same scene the approved mock draws (mock.mjs):
//   world.png         the static world: sun shadows, AO, outlines, glow and the grade, without
//                     tilt-shift, vignette or haze (the game's screen shader adds those), and
//                     without anything that moves or takes a rider's hue. The design frame's 960 x
//                     540 pixels, plus WORLD_MARGIN of more terrain all round for the flex canvas
//                     (manifest world.origin is the frame's top-left in the image);
//   world_depth.png   per pixel: depth x + y + z in 16 bits (R high byte, G low byte) as
//                     (depth - WORLD_DEPTH.offset) * WORLD_DEPTH.scale, 0 for the sky; B is the
//                     sun (255 lit, 0 in shadow); A 255;
//   atlas_<n>.png and atlas_<n>_depth.png
//                     the dynamic parts' frames: colour RGBA (alpha 0 empty; a dark halo pixel is
//                     black at HALO_ALPHA), and each pixel's depth relative to the frame's anchor
//                     in 16 bits (R, G) as rel * SPRITE_DEPTH.scale + SPRITE_DEPTH.zero;
//   manifest.json     the generator version, the encodings, the key ramp, the slot and idle
//                     ramps, and every part: anchor, frames (atlas, rect, anchor pixel offset).
// Rider-hue pixels are written in a key ramp, (255, KEY_G0 + KEY_STEP * index, 255) with
// index = tone level * 2 + outlined: magenta, which nothing else in the art uses. The game
// maps the index to a slot's ramp when the part is powered, or to the part's idle material.
//   node src/games/siege/art/bake.mjs [--check] [--out=<dir>]
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Raster, depthOf, OUTLINE_STEP, MACHINE_STEP, EDGE_MUL, MACHINE_EDGE, gradeParams, gradeRgb } from './raster.mjs';
import { Scene, ST, WHEEL_X, WHEEL_Y, WHEEL_R, WHEEL_HW, BALLISTA, ARROWS, CATAPULT, PADS, GEAR_X, STATION_SHAFTS } from './scene.mjs';
import { Life } from './life.mjs';
import { M, C, tone, accBase, setKeyMode, ACC_MIN_LEVEL, TONE_LEVELS, setTarCurtain } from './shade.mjs';
import { sprite, walkFrames, flipped } from './sprites.mjs';
import { v3, add, sub, mul, hex, rng, TAU, deg, norm, clamp } from './v3.mjs';
import * as W from './world.mjs';
import { writePng } from './png.mjs';

// Bump when the baked art or its encodings change; `--check` compares it with the manifest.
export const BAKE_VERSION = 3;
export const GENERATOR = 'src/games/siege/art/bake.mjs';
export const WORLD_DEPTH = { offset: -400, scale: 64 };
export const SPRITE_DEPTH = { zero: 32768, scale: 256 };
export const KEY_G0 = 4;
export const KEY_STEP = 8;
export const HALO_ALPHA = 0.45;
const ART_W = 960;
const ART_H = 540;
// More world round the design frame for pixel_flex canvases: every canvas of a window up to 3840 x
// 1080 or 1703 x 1079 (src/games/siege/README.md). Multiples of 4, so the ordered dither lines up.
export const WORLD_MARGIN = { x: 480, y: 272 };
export const WORLD_W = ART_W + WORLD_MARGIN.x * 2;
export const WORLD_H = ART_H + WORLD_MARGIN.y * 2;
const CAM = W.CAMERA;
const POST = { skyTop: hex('#c8c3ba'), skyBottom: hex('#c8c3ba') };
// The mock's tilt-shift focus band (rows), also where the grade adds its in-band contrast.
export const FOCUS = { top: 95, bottom: 500, rampTop: 80, rampBottom: 40, blurTop: 3, blurBottom: 3 };
const ATLAS_W = 2048;
const ATLAS_MAX_H = 2048;
const MARGIN = 3;

const repo = join(dirname(fileURLToPath(import.meta.url)), '../../../..');
const arg = (k, d) => (process.argv.find((a) => a.startsWith(`--${k}=`)) ?? `=${d}`).split('=')[1];
const OUT = arg('out', join(repo, 'assets/siege/bake'));

// Game station ids (SiegeIds) from the art's ST ids, and back.
const GAME_OF_ART = { [ST.MINE]: 0, [ST.BALLISTA]: 1, [ST.CATAPULT]: 2, [ST.ARROWS]: 3, [ST.TAR]: 4 };
const ART_OF_GAME = [ST.MINE, ST.BALLISTA, ST.CATAPULT, ST.ARROWS, ST.TAR];

// Idle materials the key ramp falls back to when nobody drives a part.
const IDLE = { wood: C.WOOD, wood_dark: C.WOOD_DK, wood_light: C.WOOD_LT, rope: C.ROPE, bronze: C.BRONZE, stone_dark: hex('#2e2a2c') };
const RAMP_ROWS = ['slot0', 'slot1', 'slot2', 'slot3', ...Object.keys(IDLE)];
const KEY_COUNT = (TONE_LEVELS + 1) * 2;


function check() {
  const path = join(OUT, 'manifest.json');
  if (!existsSync(path)) {
    console.error(`bake: ${path} is missing: run node ${GENERATOR}`);
    return 1;
  }
  let m;
  try {
    m = JSON.parse(readFileSync(path, 'utf8'));
  } catch (e) {
    console.error(`bake: manifest.json does not parse: ${e.message}`);
    return 1;
  }
  if (m.bake_version !== BAKE_VERSION) {
    console.error(`bake: manifest.json is bake_version ${m.bake_version}, the code is ${BAKE_VERSION}: run node ${GENERATOR}`);
    return 1;
  }
  const files = ['world.png', 'world_depth.png', ...m.atlases.flatMap((a) => [a.color, a.depth])];
  const missing = files.filter((f) => !existsSync(join(OUT, f)));
  if (missing.length) {
    console.error(`bake: missing ${missing.join(', ')}: run node ${GENERATOR}`);
    return 1;
  }
  console.log(`bake ok (version ${BAKE_VERSION})`);
  return 0;
}

// --- rendering helpers -------------------------------------------------------------------------

const projArt = (p) => ({ x: (p.x - p.y) * CAM.k + CAM.ox, y: (p.x + p.y) * CAM.k * 0.5 - p.z * CAM.k + CAM.oy });
const anchorPx = (p) => {
  const s = projArt(p);
  return { x: Math.floor(s.x), y: Math.floor(s.y) };
};

// A raster that only measures: it keeps the triangles and the screen box of everything drawn.
class Probe extends Raster {
  constructor() {
    super(1, 1, CAM.ox, CAM.oy, CAM.k);
    this.bb = [1e9, 1e9, -1e9, -1e9];
  }

  grow(x, y) {
    this.bb[0] = Math.min(this.bb[0], x);
    this.bb[1] = Math.min(this.bb[1], y);
    this.bb[2] = Math.max(this.bb[2], x);
    this.bb[3] = Math.max(this.bb[3], y);
  }

  point(p, c, size = 1) {
    const s = this.project(p);
    this.grow(s.x - size, s.y - size);
    this.grow(s.x + size, s.y + size);
  }

  stamp(spr, base, ax, ay) {
    const s = this.project(base);
    this.grow(s.x - ax - 1, s.y - ay - 1);
    this.grow(s.x - ax + spr.w + 1, s.y - ay + spr.h + 1);
  }

  groundShadow() {}

  box2() {
    for (const t of this.tris) for (const p of [t.a, t.b, t.c]) {
      const s = this.project(p);
      this.grow(s.x, s.y);
    }
    return this.bb;
  }
}

let WORLD = null; // {dep: Float32Array(ART_W * ART_H)}
let STATIC_SHADOW = null; // a Raster holding the static world's shadow map

// Renders one frame of a dynamic part. spec:
//   build(r)      adds the part's geometry (and points) to raster r;
//   after(r)      optional: stamps after the render (people);
//   occluder(r)   optional: geometry that hides the part but is not part of the frame;
//   anchor        the world point the frame hangs on;
//   place         true: rendered where it stands, lit by the static world's shadows, outlined
//                 against the baked world; false: a moving sprite, lit by itself only.
function bakeFrame(spec) {
  const probe = new Probe();
  spec.build(probe);
  if (spec.after) spec.after(probe);
  const [bx0, by0, bx1, by1] = probe.box2();
  if (bx0 > bx1) return null;
  const X0 = Math.floor((Math.floor(bx0) - MARGIN) / 4) * 4;
  const Y0 = Math.floor((Math.floor(by0) - MARGIN) / 4) * 4;
  const w = Math.ceil(bx1) + MARGIN + 1 - X0;
  const h = Math.ceil(by1) + MARGIN + 1 - Y0;
  const r = new Raster(w, h, CAM.ox - X0, CAM.oy - Y0, CAM.k);
  if (spec.place && STATIC_SHADOW) r.shadowExtra = [STATIC_SHADOW];
  if (spec.occluder) {
    spec.occluder(r);
    for (const t of r.tris) t.o = 999;
  }
  spec.build(r);
  r.render();
  if (spec.after) spec.after(r);
  return postFrame(r, spec, X0, Y0);
}

// Outline, grade and key the frame's pixels, add the halo, trim, and encode colour and depth.
function postFrame(r, spec, X0, Y0) {
  const { w, h, dep, oid, col, keep, key, glow } = r;
  const n = w * h;
  const A = spec.anchor;
  const ad = depthOf(A);
  const ap = projArt(A);
  // what lies around the frame: the baked world where it stands, else flat ground at the anchor
  const outside = (x, y) => {
    if (spec.place) {
      const gx = X0 + x, gy = Y0 + y;
      if (gx < 0 || gy < 0 || gx >= ART_W || gy >= ART_H) return -1e9;
      return WORLD.dep[gy * ART_W + gx];
    }
    return ad + (2 * (Y0 + y + 0.5 - ap.y)) / CAM.k;
  };
  const has = new Uint8Array(n);
  const D = new Float32Array(n);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x;
    has[i] = dep[i] > -1e8 && oid[i] !== 999 ? 1 : 0;
    D[i] = dep[i] > -1e8 ? dep[i] : outside(x, y);
  }
  const rgba = new Uint8Array(n * 4);
  const rel = new Float32Array(n);
  const g = gradeParams();
  const c = [0, 0, 0];
  const o = [0, 0, 0];
  const nb = (i, x, y) => [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1];
  for (let y = 0; y < h; y++) {
    const row = Y0 + y;
    const inBand = !spec.place || (row >= FOCUS.top && row <= FOCUS.bottom) ? 1 : 0;
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      const ns = nb(i, x, y);
      if (has[i]) {
        let outlined = false;
        c[0] = col[i * 3];
        c[1] = col[i * 3 + 1];
        c[2] = col[i * 3 + 2];
        let near = -1e9;
        let far = 1e9;
        for (const j of ns) {
          const d = j < 0 ? outside(x, y) : D[j];
          near = Math.max(near, d);
          far = Math.min(far, d);
        }
        if (near > dep[i] + OUTLINE_STEP) {
          outlined = true;
          for (let k = 0; k < 3; k++) c[k] *= EDGE_MUL[k];
        } else if (oid[i] >= 30 && oid[i] < 55 && !keep[i] && far < dep[i] - MACHINE_STEP) {
          for (let k = 0; k < 3; k++) c[k] = c[k] * 0.3 + MACHINE_EDGE[k];
        }
        for (let k = 0; k < 3; k++) c[k] += glow[i * 3 + k] * 0.4;
        rel[i] = dep[i] - ad;
        if (key[i] && !spec.noKey) {
          const idx = (key[i] - 1) * 2 + (outlined ? 1 : 0);
          rgba.set([255, KEY_G0 + KEY_STEP * idx, 255, 255], i * 4);
          continue;
        }
        gradeRgb(c, keep[i], inBand, 0, 1, g, o);
        const b = byte3(o);
        if (b[0] >= 250 && b[2] >= 250) b[2] = 249;
        rgba.set([b[0], b[1], b[2], spec.alpha ? Math.round(255 * spec.alpha(i)) : 255], i * 4);
      } else if (!spec.noHalo && oid[i] !== 999) {
        let m = -1e9;
        for (const j of ns) if (j >= 0 && has[j]) m = Math.max(m, dep[j]);
        if (m > -1e8 && m > D[i] + OUTLINE_STEP) {
          rel[i] = m - OUTLINE_STEP - ad;
          rgba.set([0, 0, 0, Math.round(255 * HALO_ALPHA)], i * 4);
        }
      }
    }
  }
  // trim to the pixels in use
  let tx0 = w, ty0 = h, tx1 = -1, ty1 = -1;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (!rgba[(y * w + x) * 4 + 3]) continue;
    tx0 = Math.min(tx0, x);
    ty0 = Math.min(ty0, y);
    tx1 = Math.max(tx1, x);
    ty1 = Math.max(ty1, y);
  }
  if (tx1 < 0) return null;
  const fw = tx1 - tx0 + 1, fh = ty1 - ty0 + 1;
  const fc = new Uint8Array(fw * fh * 4);
  const fd = new Uint8Array(fw * fh * 4);
  for (let y = 0; y < fh; y++) for (let x = 0; x < fw; x++) {
    const si = (ty0 + y) * w + tx0 + x;
    const di = y * fw + x;
    fc.set(rgba.subarray(si * 4, si * 4 + 4), di * 4);
    const v = rgba[si * 4 + 3] ? encodeSprite(rel[si]) : SPRITE_DEPTH.zero;
    fd.set([v >> 8, v & 255, 0, 255], di * 4);
  }
  const a = anchorPx(A);
  return { w: fw, h: fh, color: fc, depth: fd, ax: a.x - (X0 + tx0), ay: a.y - (Y0 + ty0), art: [X0 + tx0, Y0 + ty0] };
}

const byte = (v) => Math.max(0, Math.min(255, Math.round(v * 255)));
const byte3 = (c) => [byte(c[0]), byte(c[1]), byte(c[2])];
export const encodeWorld = (d) => Math.max(1, Math.min(65535, Math.round((d - WORLD_DEPTH.offset) * WORLD_DEPTH.scale)));
export const encodeSprite = (rel) => Math.max(0, Math.min(65535, Math.round(rel * SPRITE_DEPTH.scale) + SPRITE_DEPTH.zero));

// Back-projects art pixel (x, y) with depth d to its world point.
function unprojectDepth(x, y, d) {
  const sx = x + 0.5, sy = y + 0.5;
  const z = (d - (2 * (sy - CAM.oy)) / CAM.k) / 3;
  const s = d - z; // x + y
  const df = (sx - CAM.ox) / CAM.k; // x - y
  return v3((s + df) / 2, (s - df) / 2, z);
}

// --- the world ---------------------------------------------------------------------------------

const DYNAMIC_LIFE = ['walkers', 'army', 'shots', 'tar', 'brazier', 'dust'];

// finish()'s grade band at a pixel of the frame's coordinates: rows 110..460 in the frame, as approved,
// with an edge that softens away from the frame's sides, so it doesn't rule a line across the margin.
function gradeBand(x, y) {
  const away = Math.max(-x, x - (ART_W - 1), 0);
  if (away === 0) return y >= 110 && y <= 460 ? 1 : 0;
  const soft = away * 0.75 + 1;
  return clamp(Math.min(y - 110, 460 - y) / soft + 0.5, 0, 1);
}

// The static world's raster over w x h pixels, the design frame's top-left at (mx, my).
function renderWorld(w, h, mx, my, margin) {
  const r = new Raster(w, h, CAM.ox + mx, CAM.oy + my, CAM.k);
  if (margin) r.hmBox = { x0: -300, y0: -320, W: 1400, H: 1400 };
  // the moving parts still cast their (mock-pose) shadows and contact shade; the siege engines
  // and the tar come and go, so they leave nothing
  r.partMode = (p) => (p === 'engines' || p === 'curtain' || p === 'coat' ? 0 : 1);
  const scene = new Scene(r, { routes: [-1, -1, -1, -1] });
  scene.build();
  if (margin) scene.marginProps();
  r.render();
  const life = new Life(r, scene, { skip: DYNAMIC_LIFE });
  life.run();
  if (margin) life.marginPalms();
  const img = r.finish({ ...POST, bandAt: (x, y) => gradeBand(x - mx, y - my), maxBlur: 0, vignette: false, haze: false });
  const color = new Uint8Array(w * h * 4);
  const depth = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    color.set([byte(img[i * 3]), byte(img[i * 3 + 1]), byte(img[i * 3 + 2]), 255], i * 4);
    if (r.dep[i] < -1e8) {
      depth.set([0, 0, 255, 255], i * 4);
      continue;
    }
    const v = encodeWorld(r.dep[i]);
    const x = (i % w) - mx, y = Math.floor(i / w) - my;
    const lit = r.sunVis(add(unprojectDepth(x, y, r.dep[i]), v3(0, 0, 0.3)));
    depth.set([v >> 8, v & 255, lit ? 255 : 0, 255], i * 4);
  }
  return { r, color, depth };
}

function bakeWorld() {
  // the design frame alone, as approved: its pixels go into the image unchanged, and the parts bake
  // against it, so a bigger world can't move one pixel of them
  const frame = renderWorld(ART_W, ART_H, 0, 0, false);
  WORLD = { dep: frame.r.dep };
  // the static world's own shadow map, for the parts rendered where they stand
  const st = new Raster(1, 1, CAM.ox, CAM.oy, CAM.k);
  st.tris = frame.r.tris.filter((t) => !t.part);
  st.buildShadowMap();
  STATIC_SHADOW = st;
  const all = renderWorld(WORLD_W, WORLD_H, WORLD_MARGIN.x, WORLD_MARGIN.y, true);
  for (let y = 0; y < ART_H; y++) {
    const at = ((y + WORLD_MARGIN.y) * WORLD_W + WORLD_MARGIN.x) * 4;
    all.color.set(frame.color.subarray(y * ART_W * 4, (y + 1) * ART_W * 4), at);
    all.depth.set(frame.depth.subarray(y * ART_W * 4, (y + 1) * ART_W * 4), at);
  }
  writePng(join(OUT, 'world.png'), WORLD_W, WORLD_H, all.color);
  writePng(join(OUT, 'world_depth.png'), WORLD_W, WORLD_H, all.depth);
}

// --- the parts ---------------------------------------------------------------------------------

const parts = [];

// A part: name, its frames' specs, and the manifest fields (anchor, place, recolor, idle, layout).
function addPart(name, info, specs) {
  const frames = [];
  for (const s of specs) frames.push(bakeFrame({ anchor: info.anchor, place: info.place, ...s }));
  parts.push({ name, info, frames });
}

const sceneFor = (r, opts = {}) => new Scene(r, opts);
const hub = (i) => v3(WHEEL_X[i], WHEEL_Y, WHEEL_R + 1.4);
const range = (n) => [...Array(n).keys()];

// Each rota turns through one repeat of its pattern: 28 rim segments, and spokes, rungs, rings or
// iron bands that repeat every 180 degrees on rotae 0..2 and every 360 on rota 3. Five frames per
// rim segment (2.57 degrees, about one pixel at the rim).
export const WHEEL_PERIOD_DEG = [180, 180, 180, 360];
export const WHEEL_STEP_DEG = 360 / 28 / 5;

function wheels() {
  for (let i = 0; i < 4; i++) {
    const n = Math.round(WHEEL_PERIOD_DEG[i] / WHEEL_STEP_DEG);
    const routes = [-1, -1, -1, -1];
    routes[i] = 0;
    addPart(`wheel_${i}`, { anchor: hub(i), place: true, recolor: true, idle: 'wood', layout: { kind: 'spin', frames: n, period_deg: WHEEL_PERIOD_DEG[i], step_deg: WHEEL_STEP_DEG } },
      range(n).map((f) => ({ build: (r) => {
        const s = sceneFor(r, { routes });
        s.wheelAngle[i] = deg(f * WHEEL_STEP_DEG);
        s.wheelRim(i);
      } })));
    // the output shaft: idle timber, then powered in the key ramp
    const sm = v3(WHEEL_X[i], 16, 5);
    addPart(`wshaft_${i}`, { anchor: sm, place: true, recolor: true, layout: { kind: 'state', frames: ['idle', 'powered'] } },
      [-1, 0].map((route) => ({ build: (r) => {
        const s = sceneFor(r, { routes: route < 0 ? [-1, -1, -1, -1] : [0, 0, 0, 0] });
        s.wheelShaft(i, 0);
        s.wheelShaft(i, 1);
      } })));
  }
}

// Walkers in rota i: up to 3 (slot k), 4 walk frames each, hidden by the near rim.
function walkers() {
  const frames = walkFrames('worker');
  for (let i = 0; i < 4; i++) {
    const c = hub(i);
    const specs = [];
    for (let k = 0; k < 3; k++) {
      const a = -Math.PI / 2 + 0.12 - k * 0.18;
      const p = add(c, v3(Math.cos(a) * (WHEEL_R - 0.5), -0.6 + k * 0.6, Math.sin(a) * (WHEEL_R - 0.5)));
      for (let f = 0; f < 4; f++) {
        specs.push({
          anchor: p,
          noKey: true,
          occluder: (r) => nearRim(r, i),
          build: () => {},
          after: (r) => r.stamp(frames[f], p, 1, frames[f].h - 1, 90, true, false),
        });
      }
    }
    const parts0 = specs.map((s) => bakeFrame({ place: true, ...s }));
    parts.push({ name: `walker_${i}`, info: { anchor: specs[0].anchor, anchors: range(3).map((k) => specs[k * 4].anchor), place: true, layout: { kind: 'walker', walkers: 3, walk: 4, index: 'walker * 4 + walk' } }, frames: parts0 });
  }
}

// The near rim of rota i (the side toward the camera), as an occluder for its walkers.
function nearRim(r, i) {
  const c = hub(i);
  const segN = 28;
  const segL = (TAU * WHEEL_R) / segN;
  const cc = v3(c.x, c.y + WHEEL_HW, c.z);
  for (let s = 0; s < segN; s++) {
    const am = (TAU * (s + 0.5)) / segN;
    const rad = v3(Math.cos(am), 0, Math.sin(am));
    const tan = v3(-Math.sin(am), 0, Math.cos(am));
    r.obox(add(cc, mul(rad, WHEEL_R)), tan, v3(0, 1, 0), rad, { x: segL * 0.53, y: 0.3, z: 0.55 }, M.WOOD, 30 + i);
  }
}

function junction() {
  for (let i = 0; i < 4; i++) {
    for (let j = 0; j < 5; j++) {
      const art = ART_OF_GAME[j];
      const routes = [-1, -1, -1, -1];
      routes[i] = art;
      addPart(`route_${i}_${j}`, { anchor: v3(GEAR_X[art], [18.8, 21.4, 24.0, 26.6][i], 2.6), place: true, recolor: true, layout: { kind: 'single' } },
        [{ build: (r) => sceneFor(r, { routes }).route(i, art) }]);
    }
  }
  const shaftMid = [v3(61, 15, 2), v3(17, 40, 5), v3(36, 32, 1.3), v3(65, 30, 8), v3(52, 45, 4)];
  for (let j = 0; j < 5; j++) {
    const art = ART_OF_GAME[j];
    addPart(`sshaft_${j}`, { anchor: shaftMid[j], place: true, recolor: true, layout: { kind: 'state', frames: ['idle', 'powered'] } },
      [false, true].map((on) => ({ build: (r) => {
        const pts = STATION_SHAFTS[art];
        for (let k = 0; k < pts.length - 1; k++) r.beam(pts[k], pts[k + 1], on ? 1.1 : 0.5, on ? M.ACC0 : M.WOOD_DARK, 40);
      } })));
  }
}

function marks() {
  const at = { 0: [v3(66.2, 11.2, 0), 5.0], 1: [BALLISTA, 4.1], 2: [CATAPULT, 9.6], 3: [ARROWS, 4.1], 4: [v3(44, 59.2, 11.5), 3.3] };
  for (let j = 0; j < 5; j++) {
    const [c, rad] = at[j];
    addPart(`mark_${j}`, { anchor: c, place: true, recolor: true, idle: 'stone_dark', layout: { kind: 'single' } },
      [{ build: (r) => sceneFor(r, { routes: [ART_OF_GAME[j], -1, -1, -1] }).stationMark(ART_OF_GAME[j], c, rad) }]);
  }
}

export const YAWS = 16;
export const BALLISTA_ARMS = [0, 1 / 3, 2 / 3, 1];
export const ONAGER_ARMS = range(12).map((k) => k / 11);
const onagerDeg = (arm) => 80 + 85 * arm;

function stations() {
  const yaws = range(YAWS).map((k) => (360 * k) / YAWS);
  const routesFor = (art) => [art, -1, -1, -1];
  addPart('ballista', { anchor: add(BALLISTA, v3(0, 0, 0.4)), place: true, recolor: true, idle: 'rope', layout: { kind: 'yaw_phase', yaws: YAWS, phases: BALLISTA_ARMS.length, phase_values: BALLISTA_ARMS, index: 'yaw * phases + phase' } },
    yaws.flatMap((y) => BALLISTA_ARMS.map((arm) => ({ build: (r) => sceneFor(r, { routes: routesFor(ST.BALLISTA), ballistaYawDeg: y, ballistaArm: arm }).ballistaFrame() }))));
  addPart('onager', { anchor: add(CATAPULT, v3(0, 0, 0.3)), place: true, recolor: true, idle: 'wood_light', layout: { kind: 'yaw_phase', yaws: YAWS, phases: ONAGER_ARMS.length, phase_values: ONAGER_ARMS, index: 'yaw * phases + phase' } },
    yaws.flatMap((y) => ONAGER_ARMS.map((arm) => ({ build: (r) => sceneFor(r, { routes: routesFor(ST.CATAPULT), catYawDeg: y, armDeg: onagerDeg(arm) }).catapultFrame() }))));
  addPart('arrows', { anchor: add(ARROWS, v3(0, 0, 0.4)), place: true, recolor: true, idle: 'wood_dark', layout: { kind: 'yaw_phase', yaws: YAWS, phases: 8, phase_values: 'rack bitmask: bit k = rack k loaded', index: 'yaw * phases + racks' } },
    yaws.flatMap((y) => range(8).map((mask) => ({ build: (r) => sceneFor(r, { routes: routesFor(ST.ARROWS), arrowsYawDeg: y, racks: mask }).arrowFrame() }))));
  addPart('tar_pots', { anchor: v3(44, 57.9, 12.1), place: true, recolor: true, idle: 'bronze', layout: { kind: 'single' } },
    [{ build: (r) => {
      for (const x of [41.5, 44, 46.5]) r.cylZ(v3(x, 57.9, 12.1), 1.25, 3.1, M.ACC0, 53, 14, M.TAR);
    } }]);
  const pumpPhases = range(6).map((k) => k / 6);
  addPart('tar_pump', { anchor: v3(44, 60.1, 14.1), place: true, layout: { kind: 'phase', frames: pumpPhases.length } },
    pumpPhases.map((ph) => ({ build: (r) => sceneFor(r, { pumpPhase: ph || 1e-6 }).pumpBeam() })));
  const minePhases = range(8).map((k) => k / 8);
  addPart('mine', { anchor: v3(66.4, 11.5, 4), place: true, recolor: true, idle: 'wood_dark', layout: { kind: 'phase', frames: minePhases.length } },
    minePhases.map((ph) => ({ build: (r) => {
      const s = sceneFor(r, { routes: routesFor(ST.MINE), minePhase: ph });
      s.mineMoving();
    } })));
}

function gateAndTar() {
  addPart('gate', { anchor: v3(44, 60.9, 2.5), place: true, layout: { kind: 'stage', frames: ['full', '66', '33', 'breached'] } },
    range(4).map((st) => ({ build: (r) => sceneFor(r, { gate: st }).gateDoors() })));
  const stages = [1 / 3, 2 / 3, 1];
  addPart('curtain', { anchor: v3(44, 63.8, 5), place: true, layout: { kind: 'stage', frames: stages } },
    stages.map((t, k) => ({ build: (r) => {
      setTarCurtain(t);
      r.quad(v3(40.0, 63.8, 9.6), v3(48.0, 63.8, 9.6), v3(48.0, 63.8, 0.32), v3(40.0, 63.8, 0.32), M.TAR_FALL, 71, v3(0, 1, 0));
      const rnd = rng(31 + k);
      for (let d = 0; d < 16 * t; d++) r.point(v3(rnd.range(40.6, 47.4), 63.9, rnd.range(1, 9.4)), hex('#120d0a'), 1);
      for (let d = 0; d < 18 * t; d++) r.point(v3(rnd.range(40.8, 47.2), rnd.range(63.9, 66.5), 0.5 + rnd.range(0, 0.6)), hex('#2a201a'), 1);
    } })));
  setTarCurtain(1);
  addPart('coat', { anchor: v3(44, 67, 0.33), place: true, layout: { kind: 'stage', frames: stages } },
    stages.map((t) => ({ build: (r) => sceneFor(r, { coat: t }).tarCoat() })));
}

function pads() {
  for (let k = 0; k < 4; k++) {
    const p = PADS[k];
    addPart(`brazier_${k + 1}`, { anchor: add(p, v3(0, 0, 0.3)), place: true, layout: { kind: 'single' } },
      [{ build: (r) => {
        sceneFor(r).brazier(p);
        fire(r, add(p, v3(0, 0, 1.3)), 1.3);
      } }]);
    addPart(`scorpion_${k + 1}`, { anchor: add(p, v3(0, 0, 0.3)), place: true, layout: { kind: 'yaw', yaws: 8 } },
      range(8).map((y) => ({ build: (r) => sceneFor(r).scorpion(p, deg(y * 45)) })));
  }
}

function fire(r, p, size) {
  r.point(p, [1, 0.6, 0.19], 2, true, 0.7 * size);
  r.point(add(p, v3(0, 0, 0.35)), [1, 0.85, 0.38], 1, true, 0.9 * size);
  r.point(add(p, v3(0, 0, 0.7)), [1, 0.94, 0.63], 1, false, 0.5 * size);
}

// --- moving sprites ----------------------------------------------------------------------------

const REF = v3(0, 0, 0);

// Persons in two facings (0 right, 1 left) x 4 walk frames.
function person(name, id) {
  const fr = walkFrames(id);
  const specs = [];
  for (const face of [0, 1]) for (let f = 0; f < 4; f++) {
    const s = face === 0 ? fr[f] : flipped(fr[f]);
    specs.push({ build: () => {}, after: (r) => r.stamp(s, REF, face === 0 ? 1 : s.w - 2, s.h - 1, 90, false, false) });
  }
  addPart(name, { anchor: REF, place: false, layout: { kind: 'facing_walk', facings: ['right', 'left'], walk: 4, index: 'facing * 4 + walk' } }, specs);
}

function chariot() {
  const side = walkFrames('chariot');
  const sets = [side.map(flipped), side, walkFrames('chariot_s'), walkFrames('chariot_n')];
  const specs = [];
  sets.forEach((fr, face) => {
    for (let f = 0; f < 4; f++) {
      const s = fr[f];
      const ax = face < 2 ? 4 : 2;
      specs.push({ build: () => {}, after: (r) => r.stamp(s, REF, ax, s.h - 1, 91, false, false) });
    }
  });
  addPart('chariot', { anchor: REF, place: false, layout: { kind: 'facing_walk', facings: ['right', 'left', 'toward', 'away'], walk: 4, index: 'facing * 4 + walk' } }, specs);
}

function engines() {
  const yaws = range(8).map((k) => deg(k * 45));
  addPart('ram', { anchor: REF, place: false, layout: { kind: 'yaw', yaws: 8 } },
    yaws.map((a) => ({ build: (r) => sceneFor(r).ram({ x: 0, y: 0 }, a, 0.3) })));
  addPart('tower', { anchor: REF, place: false, layout: { kind: 'yaw', yaws: 8 } },
    yaws.map((a) => ({ build: (r) => sceneFor(r).siegeTowerAt(REF, a, 1, false) })));
  addPart('tower_dock', { anchor: REF, place: false, layout: { kind: 'yaw', yaws: 8 } },
    yaws.map((a) => ({ build: (r) => sceneFor(r).siegeTowerAt(REF, a, 1, true) })));
}

// Ground shadows (black at their alpha), as the mock's groundShadow() casts them, lifted a little
// so uneven ground doesn't hide them.
const SHADOW_LIFT = 0.4;
function shadows() {
  const kinds = { person: [0.4, 1.6, 0.66], chariot: [1, 1.4, 0.8], ram: [2.4, 3.5, 0.7], tower: [3.4, 15, 0.7] };
  for (const [name, [rad, hgt, k]] of Object.entries(kinds)) {
    const sun = norm(v3(-0.55, 0.35, 0.76));
    const off = mul(norm(v3(-sun.x, -sun.y, 0)), hgt * 0.7);
    const pxs = [];
    const s0 = projArt(REF);
    for (let y = -40; y <= 40; y++) for (let x = -60; x <= 60; x++) {
      const gx = s0.x + x + 0.5, gy = s0.y + y + 0.5;
      const d = (gx - CAM.ox) / CAM.k, sm = (2 * (gy - CAM.oy)) / CAM.k;
      const g = v3((d + sm) / 2, (sm - d) / 2, 0);
      const ol2 = off.x * off.x + off.y * off.y;
      const t = clamp((g.x * off.x + g.y * off.y) / ol2, 0, 1);
      if (Math.hypot(g.x - off.x * t, g.y - off.y * t) <= rad) pxs.push([Math.floor(s0.x) + x, Math.floor(s0.y) + y, (2 * (gy - s0.y)) / CAM.k + SHADOW_LIFT]);
    }
    parts.push({ name: `shadow_${name}`, info: { anchor: REF, place: false, layout: { kind: 'single' } }, frames: [pixelFrame(pxs, [0, 0, 0], 1 - k, REF)] });
  }
}

// A frame from loose art pixels [x, y, relDepth] of one colour and alpha.
function pixelFrame(pxs, rgb, alpha, anchor) {
  let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (const [x, y] of pxs) {
    x0 = Math.min(x0, x);
    y0 = Math.min(y0, y);
    x1 = Math.max(x1, x);
    y1 = Math.max(y1, y);
  }
  const w = x1 - x0 + 1, h = y1 - y0 + 1;
  const color = new Uint8Array(w * h * 4);
  const depth = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) depth.set([SPRITE_DEPTH.zero >> 8, SPRITE_DEPTH.zero & 255, 0, 255], i * 4);
  for (const [x, y, rel, c, a] of pxs) {
    const i = (y - y0) * w + (x - x0);
    const cc = c ?? rgb;
    color.set([byte(cc[0]), byte(cc[1]), byte(cc[2]), Math.round(255 * (a ?? alpha))], i * 4);
    const v = encodeSprite(rel);
    depth.set([v >> 8, v & 255, 0, 255], i * 4);
  }
  const ap = anchorPx(anchor);
  return { w, h, color, depth, ax: ap.x - x0, ay: ap.y - y0, art: [x0, y0] };
}

// Effects at a ground point: dust (a stone's impact), splinters (a bolt in timber), a splash
// (anything into the moat). Stages in time; dithered translucent puffs as in life.mjs.
function effects() {
  const g = gradeParams();
  const graded = (c) => gradeRgb([...c], 0, 1, 0, 1, g, [0, 0, 0]);
  const s0 = projArt(REF);
  const sim = (seed, n, fn) => {
    const rnd = rng(seed);
    return range(n).map(() => fn(rnd));
  };
  const puffPx = (out, p, radiusM, c, density, alpha) => {
    const s = projArt(p);
    const rad = radiusM * CAM.k;
    const ir = Math.ceil(rad);
    for (let yy = -ir; yy <= ir; yy++) for (let xx = -ir; xx <= ir; xx++) {
      const q = (xx * xx + yy * yy) / Math.max(rad * rad, 0.01);
      if (q > 1) continue;
      const x = Math.floor(s.x) + xx, y = Math.floor(s.y) + yy;
      const bay = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5][(y & 3) * 4 + (x & 3)];
      if ((bay + 0.5) / 16 < density * (1 - q)) out.set(`${x},${y}`, [x, y, depthOf(p) + radiusM * 0.5, c, alpha]);
    }
  };
  const stage = (pts) => pixelFrame([...pts.values()], null, 1, REF);
  // dust: 40 grains thrown out and up, slowing in the air, and a low ring of settling dust
  const grains = sim(5, 46, (rnd) => {
    const a = rnd.range(0, TAU), up = rnd.range(0.35, 1), sp = rnd.range(3, 9);
    const h = Math.sqrt(1 - up * up);
    return { v: v3(Math.cos(a) * h * sp, Math.sin(a) * h * sp, up * sp), r: rnd.range(0.5, 1.2), c: rnd.f() < 0.66 ? hex('#ead7ab') : hex('#c8ad7c') };
  });
  const dustT = [0.08, 0.2, 0.4, 0.65, 0.95, 1.3];
  const dust = dustT.map((t) => {
    const out = new Map();
    const fade = clamp(1 - t / 1.5, 0.15, 1);
    for (const gr of grains) {
      const drag = (1 - Math.exp(-2.2 * t)) / 2.2;
      const p = v3(gr.v.x * drag, gr.v.y * drag, Math.max(gr.v.z * drag - 2 * t * t, 0.1));
      puffPx(out, p, gr.r * (0.6 + t), graded(gr.c), 0.8 * fade, 0.8);
    }
    return stage(out);
  });
  parts.push({ name: 'fx_dust', info: { anchor: REF, place: false, layout: { kind: 'time', times_s: dustT } }, frames: dust });
  const chips = sim(9, 26, (rnd) => ({ v: v3(rnd.range(-6, 6), rnd.range(-6, 6), rnd.range(3, 9)), c: rnd.f() < 0.5 ? hex('#6a5a48') : hex('#a3845e') }));
  const chipT = [0.05, 0.15, 0.3, 0.5];
  const splinters = chipT.map((t) => {
    const out = new Map();
    for (const ch of chips) {
      const p = v3(ch.v.x * t, ch.v.y * t, Math.max(1 + ch.v.z * t - 4.9 * t * t, 0));
      const s = projArt(p);
      out.set(`${Math.floor(s.x)},${Math.floor(s.y)}`, [Math.floor(s.x), Math.floor(s.y), depthOf(p), graded(ch.c), 1]);
    }
    return stage(out);
  });
  parts.push({ name: 'fx_splinters', info: { anchor: REF, place: false, layout: { kind: 'time', times_s: chipT } }, frames: splinters });
  const drops = sim(13, 30, (rnd) => ({ v: v3(rnd.range(-2.5, 2.5), rnd.range(-2.5, 2.5), rnd.range(4, 8)) }));
  const splashT = [0.05, 0.2, 0.4, 0.7];
  const splash = splashT.map((t) => {
    const out = new Map();
    const ring = 0.6 + t * 3;
    for (let k = 0; k < 24; k++) {
      const a = (TAU * k) / 24;
      const p = v3(Math.cos(a) * ring, Math.sin(a) * ring, 0);
      const s = projArt(p);
      out.set(`${Math.floor(s.x)},${Math.floor(s.y)}`, [Math.floor(s.x), Math.floor(s.y), depthOf(p), graded(hex('#a6cfc4')), clamp(1 - t, 0.3, 1)]);
    }
    for (const dr of drops) {
      const p = v3(dr.v.x * t, dr.v.y * t, dr.v.z * t - 4.9 * t * t);
      if (p.z < 0) continue;
      const s = projArt(p);
      out.set(`${Math.floor(s.x)},${Math.floor(s.y)}`, [Math.floor(s.x), Math.floor(s.y), depthOf(p), graded(hex('#e6f0ea')), 1]);
    }
    return stage(out);
  });
  parts.push({ name: 'fx_splash', info: { anchor: REF, place: false, layout: { kind: 'time', times_s: splashT } }, frames: splash });
  void s0;
}

// One pixel per projectile colour (depth 0 at the anchor): the shot drawer builds bolts, stones,
// arrows, trails, drop shadows and hp bars from them.
export const PX = ['bolt_dark', 'bolt_shaft', 'bolt_tip', 'bolt_trail', 'stone', 'stone_lit', 'stone_trail', 'dust', 'arrow', 'fletch', 'arrow_trail', 'shadow', 'hp_back', 'hp_fill', 'hp_low', 'white'];
const PX_RGB = {
  bolt_dark: hex('#3a3c40'), bolt_shaft: hex('#6b5134'), bolt_tip: hex('#e8ecf0'), bolt_trail: [1, 0.98, 0.88],
  stone: hex('#3e3833'), stone_lit: hex('#c0b6a8'), stone_trail: hex('#fff4dc'), dust: hex('#e8dcc0'),
  arrow: hex('#2e2219'), fletch: hex('#f4eedc'), arrow_trail: hex('#f2ead6'), shadow: null,
  hp_back: hex('#2a2420'), hp_fill: hex('#c8a660'), hp_low: hex('#c0503a'), white: [1, 1, 1],
};

function pixels() {
  const g = gradeParams();
  const p = projArt(REF);
  const frames = PX.map((name) => {
    const c = PX_RGB[name];
    const rgb = c === null ? [0, 0, 0] : name === 'white' ? c : gradeRgb([...c], 0, 1, 0, 1, g, [0, 0, 0]);
    return pixelFrame([[Math.floor(p.x), Math.floor(p.y), 0]], rgb, 1, REF);
  });
  parts.push({ name: 'px', info: { anchor: REF, place: false, layout: { kind: 'palette', names: PX } }, frames });
}

// --- ramps -------------------------------------------------------------------------------------

function ramps() {
  const g = gradeParams();
  const out = {};
  const entry = (c, keep) => byte3(gradeRgb([...c], keep, 1, 0, 1, g, [0, 0, 0]));
  for (let s = 0; s < 4; s++) {
    const row = [];
    for (let lv = 0; lv <= TONE_LEVELS; lv++) {
      const t = tone(accBase(s), Math.max(lv, ACC_MIN_LEVEL) / TONE_LEVELS);
      row.push(entry(t, 1), entry(t.map((v, k) => v * EDGE_MUL[k]), 1));
    }
    out[`slot${s}`] = row;
  }
  for (const [name, base] of Object.entries(IDLE)) {
    const row = [];
    for (let lv = 0; lv <= TONE_LEVELS; lv++) {
      const t = tone(base, lv / TONE_LEVELS);
      row.push(entry(t, 0), entry(t.map((v, k) => v * EDGE_MUL[k]), 0));
    }
    out[name] = row;
  }
  return out;
}

// --- packing -----------------------------------------------------------------------------------

function pack(groups) {
  const atlases = [];
  for (const [group, list] of groups) {
    const frames = list.filter((f) => f.frame).sort((a, b) => b.frame.h - a.frame.h || b.frame.w - a.frame.w);
    let atlas = null;
    let x = 0, y = 0, shelf = 0;
    const open = () => {
      atlas = { id: atlases.length, group, w: ATLAS_W, h: 0, items: [] };
      atlases.push(atlas);
      x = 0;
      y = 0;
      shelf = 0;
    };
    open();
    for (const f of frames) {
      const { w, h } = f.frame;
      if (x + w > ATLAS_W) {
        x = 0;
        y += shelf + 1;
        shelf = 0;
      }
      if (y + h > ATLAS_MAX_H) {
        open();
      }
      f.atlas = atlas.id;
      f.rect = [x, y, w, h];
      atlas.items.push(f);
      x += w + 1;
      shelf = Math.max(shelf, h);
      atlas.h = Math.max(atlas.h, y + h);
    }
  }
  for (const a of atlases) {
    a.h = Math.ceil(a.h / 4) * 4;
    const color = new Uint8Array(a.w * a.h * 4);
    const depth = new Uint8Array(a.w * a.h * 4);
    for (let i = 0; i < a.w * a.h; i++) depth.set([SPRITE_DEPTH.zero >> 8, SPRITE_DEPTH.zero & 255, 0, 255], i * 4);
    for (const f of a.items) {
      const [fx, fy, fw, fh] = f.rect;
      for (let yy = 0; yy < fh; yy++) {
        color.set(f.frame.color.subarray(yy * fw * 4, (yy + 1) * fw * 4), ((fy + yy) * a.w + fx) * 4);
        depth.set(f.frame.depth.subarray(yy * fw * 4, (yy + 1) * fw * 4), ((fy + yy) * a.w + fx) * 4);
      }
    }
    a.color = `atlas_${a.id}.png`;
    a.depth = `atlas_${a.id}_depth.png`;
    writePng(join(OUT, a.color), a.w, a.h, color);
    writePng(join(OUT, a.depth), a.w, a.h, depth);
  }
  return atlases;
}

// --- main --------------------------------------------------------------------------------------

function main() {
  const t0 = Date.now();
  mkdirSync(OUT, { recursive: true });
  W.build();
  setKeyMode(true);
  bakeWorld();
  const tWorld = Date.now() - t0;
  wheels();
  walkers();
  junction();
  marks();
  stations();
  gateAndTar();
  pads();
  person('spear', 'spear');
  person('shield', 'shield');
  person('hauler', 'hauler');
  person('walker', 'worker');
  chariot();
  engines();
  shadows();
  effects();
  pixels();
  setKeyMode(false);
  const tParts = Date.now() - t0;
  const moving = (p) => !p.info.place;
  const groups = new Map([
    ['machines', parts.filter((p) => !moving(p)).flatMap((p) => p.frames.map((frame) => ({ part: p.name, frame })))],
    ['units', parts.filter(moving).flatMap((p) => p.frames.map((frame) => ({ part: p.name, frame })))],
  ]);
  const atlases = pack(groups);
  const byPart = new Map();
  for (const list of groups.values()) for (const f of list) {
    if (!byPart.has(f.part)) byPart.set(f.part, []);
    byPart.get(f.part).push(f);
  }
  const manifest = {
    generator: GENERATOR,
    bake_version: BAKE_VERSION,
    note: 'Generated by src/games/siege/art/bake.mjs; do not edit by hand.',
    art_size: [ART_W, ART_H],
    camera: { k: CAM.k, ox: CAM.ox, oy: CAM.oy, depth: 'x + y + z (larger is nearer)' },
    focus: FOCUS,
    world: { color: 'world.png', depth: 'world_depth.png', size: [WORLD_W, WORLD_H], origin: [WORLD_MARGIN.x, WORLD_MARGIN.y] },
    depth: {
      world: { offset: WORLD_DEPTH.offset, scale: WORLD_DEPTH.scale, encode: 'v = round((depth - offset) * scale), R = v >> 8, G = v & 255; v 0 is the sky (farthest)', sun: 'B: 255 lit, 0 in the sun shadow' },
      sprite: { zero: SPRITE_DEPTH.zero, scale: SPRITE_DEPTH.scale, encode: 'v = round(rel * scale) + zero, R = v >> 8, G = v & 255; depth = anchor depth + rel' },
      outline_step_m: OUTLINE_STEP,
    },
    halo_alpha: HALO_ALPHA,
    key: {
      encode: 'R 255, B 255, G = g0 + step * index; index = tone level * 2 + outlined',
      g0: KEY_G0,
      step: KEY_STEP,
      count: KEY_COUNT,
      colors: range(KEY_COUNT).map((i) => [255, KEY_G0 + KEY_STEP * i, 255]),
    },
    ramp_rows: RAMP_ROWS,
    ramps: ramps(),
    slot_colors: ['#D55E00', '#0072B2', '#F0E442', '#009E73'],
    station_ids: { mine: 0, ballista: 1, onager: 2, arrows: 3, tar: 4 },
    atlases: atlases.map((a) => ({ id: a.id, group: a.group, color: a.color, depth: a.depth, size: [a.w, a.h] })),
    parts: {},
  };
  for (const p of parts) {
    const list = byPart.get(p.name) ?? [];
    const info = p.info;
    manifest.parts[p.name] = {
      place: !!info.place,
      anchor: [info.anchor.x, info.anchor.y, info.anchor.z].map(r3),
      depth_offset: r3(depthOf(info.anchor)),
      recolor: !!info.recolor,
      idle: info.idle ?? null,
      ...(info.anchors ? { anchors: info.anchors.map((a) => [a.x, a.y, a.z].map(r3)) } : {}),
      layout: info.layout,
      frames: p.frames.map((fr) => {
        const f = list.find((q) => q.frame === fr);
        return f ? [f.atlas, ...f.rect, fr.ax, fr.ay] : null;
      }),
    };
  }
  writeFileSync(join(OUT, 'manifest.json'), JSON.stringify(manifest, null, 1).replace(/\[[\d\s.,-]+\]/g, (m) => m.replace(/\s+/g, ' ').replace('[ ', '[').replace(' ]', ']')) + '\n');
  const frames = parts.reduce((n, p) => n + p.frames.filter(Boolean).length, 0);
  let bytes = 0;
  for (const f of readdirSync(OUT)) if (f.endsWith('.png') || f.endsWith('.json')) bytes += statSync(join(OUT, f)).size;
  console.log(`bake: world in ${tWorld} ms; ${parts.length} parts, ${frames} frames in ${tParts - tWorld} ms`);
  console.log(`bake: ${atlases.map((a) => `${a.color} ${a.w}x${a.h}`).join(', ')}`);
  console.log(`bake: ${(bytes / 1048576).toFixed(2)} MB in ${OUT}, done in ${Date.now() - t0} ms`);
}

function r3(v) {
  return Math.round(v * 1000) / 1000;
}

if (process.argv.includes('--check')) process.exit(check());
main();
