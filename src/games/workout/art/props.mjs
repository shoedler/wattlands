// The world's moving props and the sprint furniture. True colour, tinted by the view, no text but the
// gantry's pixel word. Sheet layouts agree with kit.json's props block (bake.mjs).
// Shaded from the same light as the world: upper right. Colours sit a step quieter than the riders'.
import { Canvas, hex } from './raster.mjs';
import { mix } from './palette.mjs';
import { ik } from './rig.mjs';

const OUTLINE = hex('#1c1e24');

/** Cell pixels the view lines sprites up by; kit.json publishes them. */
export const SMOKE_ORIGIN = [5, 15]; // goes on a chimney's top pixel
export const CROWD_CELL = [26, 52];
export const CROWD_HAND_UP = [18, 6]; // the raised near hand in row 1
export const CROWD_HAND_DOWN_DY = 17; // the view holds a flag this far under it when the hands are down
export const FLAG_GRIP = [1, 15]; // goes on a raised hand

/** Tower 30 x 70 at (0, 0), then the rotor's 8 frames of 26 x 26 from x 30. */
export function windpump() {
  const c = new Canvas(30 + 26 * 8, 70);
  const steel = hex('#5c626c');
  const lit = hex('#8c929c');
  const dark = hex('#3a3e48');
  // Four-legged lattice tower, narrowing to the head.
  c.line(13, 12, 5, 69, steel);
  c.line(17, 12, 25, 69, lit);
  c.line(14, 12, 11, 69, dark);
  c.line(16, 12, 19, 69, dark);
  for (const [y, t] of [
    [60, 0.84],
    [48, 0.63],
    [38, 0.46],
    [28, 0.28],
    [20, 0.14],
  ]) {
    const half = 2 + t * 8;
    c.line(15 - half, y, 15 + half, y, steel);
  }
  for (const [y0, y1] of [
    [60, 48],
    [48, 38],
    [38, 28],
    [28, 20],
  ]) {
    const hw0 = 2 + ((y0 - 12) / 57) * 8;
    const hw1 = 2 + ((y1 - 12) / 57) * 8;
    c.line(15 - hw0, y0, 15 + hw1, y1, dark);
    c.line(15 + hw0, y0, 15 - hw1, y1, dark);
  }
  // The platform, the gearbox, the pump rod, the tail vane behind.
  c.rect(11, 13, 9, 1, lit);
  c.rect(13, 6, 5, 5, dark);
  c.rect(16, 6, 2, 5, lit);
  c.line(15, 12, 15, 66, lit);
  c.rect(1, 6, 13, 1, steel);
  c.polyFill(
    [
      [0, 3],
      [7, 5],
      [7, 8],
      [0, 10],
    ],
    hex('#b86a4c'),
  );
  c.line(0, 3, 0, 10, hex('#e0a080'));
  for (let f = 0; f < 8; f++) {
    // 8 vanes, 45 degree period: 8 frames step through one period.
    const a0 = (((f * 45) / 8) * Math.PI) / 180;
    const ox = 30 + f * 26 + 13;
    for (let b = 0; b < 8; b++) {
      const a = a0 + (b * Math.PI) / 4;
      const a1 = a + 0.26;
      const colour = hex(b % 2 === 0 ? '#d4d8dc' : '#9aa0a8');
      c.polyFill(
        [
          [ox + 4 * Math.cos(a), 13 + 4 * Math.sin(a)],
          [ox + 12 * Math.cos(a), 13 + 12 * Math.sin(a)],
          [ox + 12 * Math.cos(a1), 13 + 12 * Math.sin(a1)],
          [ox + 4 * Math.cos(a1), 13 + 4 * Math.sin(a1)],
        ],
        colour,
      );
    }
    c.ring(ox, 13, 12, steel);
    c.disk(ox, 13, 2, OUTLINE);
    c.px(ox + 1, 12, lit);
  }
  return c;
}

/** 12 x 9, 2 frames (graze) across, 3 coats down: a rump, a sagging belly, a lit back, a head with an ear. */
export function cattle() {
  const c = new Canvas(24, 27);
  const coats = [
    { coat: hex('#6c4a34'), dark: hex('#4a3026'), lit: hex('#96704c') },
    { coat: hex('#d8d0c0'), dark: hex('#a29a94'), lit: hex('#f4f0e4'), patch: hex('#4a4442') },
    { coat: hex('#4c443e'), dark: hex('#2c2624'), lit: hex('#7c7268'), patch: hex('#d0c8ba') },
  ];
  coats.forEach(({ coat, dark, lit, patch }, row) => {
    for (let f = 0; f < 2; f++) {
      const x = f * 12;
      const y = row * 9;
      // Far legs first, then the barrel with its belly and a rounded rump.
      c.px(x + 3, y + 7, dark);
      c.px(x + 8, y + 7, dark);
      c.rect(x + 1, y + 3, 8, 4, coat);
      c.px(x + 1, y + 3, dark);
      c.rect(x + 2, y + 7, 6, 0, dark);
      c.rect(x + 2, y + 6, 7, 1, dark);
      c.rect(x + 3, y + 3, 6, 1, lit);
      if (patch) {
        c.rect(x + 3, y + 4, 2, 2, patch);
        c.px(x + 7, y + 4, patch);
        c.px(x + 6, y + 5, patch);
      }
      // Near legs with hooves, a tail down the rump.
      c.rect(x + 2, y + 7, 1, 2, coat);
      c.rect(x + 7, y + 7, 1, 2, coat);
      c.px(x + 2, y + 8, dark);
      c.px(x + 7, y + 8, dark);
      c.px(x, y + 4, dark);
      c.px(x, y + 5, dark);
      // Head up and looking, then down in the grass.
      if (f === 0) {
        c.rect(x + 9, y + 2, 2, 3, coat);
        c.px(x + 11, y + 3, dark);
        c.px(x + 9, y + 1, dark);
        c.px(x + 10, y + 2, lit);
      } else {
        c.rect(x + 9, y + 5, 2, 3, coat);
        c.px(x + 11, y + 7, dark);
        c.px(x + 9, y + 4, dark);
      }
    }
  });
  return c;
}

export const TRACTOR_CELL = [18, 10];

/**
 * 18 x 10, 4 frames: a far tractor at the scale of the mid plane's farms, facing its way of travel. It sits
 * on the field: a shadow under the wheels, and a strip of turned earth behind it that the lugs throw up.
 */
export function tractor() {
  const [w, h] = TRACTOR_CELL;
  const c = new Canvas(w * 4, h);
  const paint = [hex('#74382c'), hex('#a4553c'), hex('#c47a58')];
  const tyre = hex('#2a2c2e');
  const lug = hex('#55585a');
  const earth = [hex('#5a4634'), hex('#7a6248')];
  for (let f = 0; f < 4; f++) {
    const x = f * w;
    const o = x + 4;
    // Ground contact: the earth it has turned, then its shadow on the row under the wheels.
    for (let i = 0; i < 6; i++) {
      c.px(x + i, 8, earth[(i + f) % 3 === 0 ? 1 : 0]);
      if ((i + f) % 2 === 0 || i > 2) c.px(x + i, 9, earth[0]);
    }
    for (let i = 1; i < 13; i++) c.px(o + i, 9, [34, 40, 30, 150]);
    // Cab, a pale glass with the driver in it, then the bonnet and its stack.
    c.rect(o + 1, 0, 5, 1, hex('#3c4044'));
    c.rect(o + 1, 1, 1, 3, tyre);
    c.rect(o + 5, 1, 1, 3, tyre);
    c.rect(o + 2, 1, 3, 2, hex('#a0b4bc'));
    c.px(o + 3, 2, hex('#4c5c6c'));
    c.rect(o + 5, 3, 7, 3, paint[1]);
    c.rect(o + 5, 3, 7, 1, paint[2]);
    c.rect(o + 5, 5, 7, 1, paint[0]);
    c.px(o + 12, 4, paint[0]);
    c.rect(o + 9, 1, 1, 2, tyre);
    c.rect(o + 1, 4, 5, 2, paint[0]);
    // The big rear wheel with one lug going round; the small front one.
    c.disk(o + 3, 6, 3, tyre);
    c.px(o + 3, 6, hex('#b49a54'));
    const a = (f * Math.PI) / 2 + 0.6;
    c.px(o + 3 + 2.6 * Math.cos(a), 6 + 2.6 * Math.sin(a), lug);
    c.rect(o + 10, 6, 3, 3, tyre);
    c.px(o + 11, 7, hex('#b49a54'));
  }
  return c;
}

/** 10 x 16, 6 frames of chimney smoke, rising, drifting with the wind and thinning. */
export function smoke() {
  const c = new Canvas(60, 16);
  const puff = hex('#c8ccd4');
  const dim = hex('#9ea2b0');
  for (let f = 0; f < 6; f++) {
    for (let i = 0; i < 3; i++) {
      const t = ((f + i * 2) % 6) / 6;
      const x = f * 10 + 5 - Math.round(3 * t);
      const y = 13 - t * 12;
      const r = 0.7 + t * 1.3;
      if (t < 0.7) {
        c.disk(x, y, r, dim);
        c.disk(x + 1, y - 1, Math.max(r - 1, 0.4), puff);
      } else {
        // Thins out into broken pixels near the top.
        c.px(x, y, dim);
        c.px(x + 2, y + 1, dim);
        c.px(x - 1, y - 1, puff);
      }
    }
    // Always a wisp sitting on the chimney's own pixel.
    c.px(f * 10 + 5, 15, dim);
    c.px(f * 10 + 5, 14, puff);
  }
  return c;
}

/** 5 x 3, 2 frames: one bird, wings up and down. */
export function flock() {
  const c = new Canvas(10, 3);
  const bird = hex('#20222a');
  c.px(0, 0, bird);
  c.px(1, 1, bird);
  c.px(2, 1, bird);
  c.px(3, 1, bird);
  c.px(4, 0, bird);
  c.px(5, 2, bird);
  c.px(6, 1, bird);
  c.px(7, 1, bird);
  c.px(8, 1, bird);
  c.px(9, 2, bird);
  return c;
}

/** 18 x 26: a day balloon, in stripes that wrap round its shape. */
export function balloon() {
  const c = new Canvas(18, 26);
  const a = [hex('#a83e28'), hex('#d8583c'), hex('#f08860')];
  const b = [hex('#b8983c'), hex('#f0d060'), hex('#fff0a0')];
  for (let j = -9; j <= 9; j++) {
    for (let i = -8; i <= 8; i++) {
      const e = (i * i) / 72 + (j * j) / (j > 0 ? 90 : 72);
      if (e > 1) continue;
      const w = Math.sqrt(Math.max(1 - (j * j) / 90, 0.01));
      const lon = Math.asin(Math.min(i / (8.3 * w), 1)) / Math.PI;
      const band = Math.floor((lon + 0.5) * 6);
      const s = (i * 0.6 - j * 0.8) / 9;
      const ramp = band % 2 === 0 ? a : b;
      c.px(9 + i, 9 + j, ramp[s > 0.42 ? 2 : s < -0.3 ? 0 : 1]);
    }
  }
  c.line(6, 17, 7, 22, OUTLINE);
  c.line(12, 17, 11, 22, OUTLINE);
  c.rect(7, 22, 5, 3, hex('#6c4a34'));
  c.rect(7, 22, 5, 1, hex('#94704c'));
  return c;
}

const SKINS = ['#e4b08a', '#c48c62', '#8c5c3c', '#eec6a2'].map(hex);
const HAIRS = { brown: hex('#46322a'), black: hex('#1e1c20'), sand: hex('#8e7048'), grey: hex('#b4b2ac'), red: hex('#7a4228') };
const CREASE_DARK = [44, 32, 58];
const SUNNY = [255, 238, 196];
// The air between the crowd and the riders: pale and cool. The crowd's every colour goes this far into it,
// so nobody on the verge comes near a rider's value range or a rider's dark edge.
const CROWD_AIR = [172, 184, 190];
const CROWD_AIR_MIX = 0.4;
const CROWD_EDGE = hex('#5e6672');
const inAir = (c) => mix(c, CROWD_AIR, CROWD_AIR_MIX);

/** Three shades: the shadow leans violet, the light warm. Quieter than the riders' kit, as befits a crowd. */
const clothRamp = (s) => {
  const c = mix(hex(s), [122, 120, 118], 0.22);
  return [mix(c, CREASE_DARK, 0.5), c, mix(c, SUNNY, 0.34)];
};
const skinRamp = (c) => [mix(c, [120, 50, 62], 0.45), c, mix(c, SUNNY, 0.3)];

// The cheering 8: each column is a small group, back figures first. `a` marks the figure whose near hand
// is at CROWD_HAND_UP in row 1, and CROWD_HAND_DOWN_DY under it in row 0: the view gives that hand a flag.
// x: feet in the cell. lift: stands that far behind the next one. f: looks left (-1, toward the riders
// coming), ahead (0), right (1). arms: [near, far] by row, hands down then hands up.
const GROUPS = [
  [{ a: true, x: 10, lift: 0, h: 44, f: -1, skin: 0, top: 'tee', shirt: '#a85a44', legs: '#b0a07c', hair: 'cap', tint: '#3c5a7c', hairCol: 'brown', far: ['hang', 'clap'], stance: 1 }],
  [
    { x: 3, lift: 2, h: 40, f: 0, skin: 3, top: 'tee', shirt: '#b49a58', legs: '#c8c0a8', hair: 'long', hairCol: 'red', near: ['hang', 'hang'], far: ['hang', 'hang'], top2: 'skirt' },
    { a: true, x: 11, lift: 0, h: 45, f: -1, skin: 1, top: 'jacket', shirt: '#3e6a8c', inner: '#c8c4b4', legs: '#5c7490', hair: 'short', hairCol: 'black', far: ['hip', 'up'], stance: 4 },
  ],
  [
    { a: true, x: 8, lift: 1, h: 43, f: -1, skin: 2, top: 'stripe', shirt: '#4a7c6a', inner: '#d8d4c4', legs: '#7c5c4c', hair: 'short', hairCol: 'black', far: ['hang', 'up'], stance: 2 },
    { x: 20, lift: 0, h: 26, f: -1, skin: 2, top: 'tee', shirt: '#c07840', legs: '#3c5a7c', hair: 'short', hairCol: 'black', near: ['hang', 'up'], far: ['hang', 'up'], shorts: true },
  ],
  [{ a: true, x: 7, lift: 3, h: 39, f: 0, skin: 3, top: 'jacket', shirt: '#7c7468', inner: '#a8a498', legs: '#8c8878', hair: 'bald', hairCol: 'grey', far: ['hang', 'hang'], stance: 1 }],
  [
    { x: 2, lift: 3, h: 42, f: 1, skin: 0, top: 'tee', shirt: '#6c5a84', legs: '#6c7050', hair: 'short', hairCol: 'sand', near: ['cross', 'clap'], far: ['cross', 'clap'], stance: 3 },
    { a: true, x: 10, lift: 1, h: 46, f: -1, skin: 0, top: 'tee', shirt: '#9c4a48', legs: '#4e5c74', hair: 'short', hairCol: 'brown', far: ['hip', 'up'], shorts: true, stance: 5 },
  ],
  [{ a: true, x: 12, lift: 2, h: 38, f: -1, skin: 3, top: 'dress', shirt: '#b4705c', legs: '#b4705c', hair: 'sunhat', tint: '#d0c49c', hairCol: 'sand', far: ['hip', 'clap'] }],
  [
    { a: true, x: 6, lift: 2, h: 46, f: -1, skin: 1, top: 'tee', shirt: '#4c7490', legs: '#b8a888', hair: 'short', hairCol: 'grey', far: ['hang', 'up'], stance: 2 },
    { x: 16, lift: 0, h: 34, f: -1, skin: 0, top: 'jacket', shirt: '#8c8c50', inner: '#d4d0bc', legs: '#70604c', hair: 'long', hairCol: 'black', near: ['hip', 'clap'], far: ['hip', 'clap'], stance: 1 },
  ],
  [{ a: true, x: 9, lift: 4, h: 42, f: 0, skin: 0, top: 'stripe', shirt: '#5c6c9c', inner: '#c8ccd4', legs: '#60708c', hair: 'beanie', tint: '#a8503c', hairCol: 'brown', far: ['hang', 'clap'], shorts: true, stance: 4 }],
];

/** Paints a capsule from a to b, shaded from the right: the crowd's sun is the world's. */
function limb(put, a, b, ra, rb, colour) {
  const lim = Math.ceil(Math.max(ra, rb)) + 1;
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const len2 = Math.max(dx * dx + dy * dy, 1e-6);
  for (let y = Math.floor(Math.min(a[1], b[1])) - lim; y <= Math.ceil(Math.max(a[1], b[1])) + lim; y++) {
    for (let x = Math.floor(Math.min(a[0], b[0])) - lim; x <= Math.ceil(Math.max(a[0], b[0])) + lim; x++) {
      const t = Math.min(Math.max(((x - a[0]) * dx + (y - a[1]) * dy) / len2, 0), 1);
      const ex = x - (a[0] + dx * t);
      const ey = y - (a[1] + dy * t);
      const r = ra + (rb - ra) * t;
      if (Math.hypot(ex, ey) > r) continue;
      put(x, y, colour((ex * 0.8 - ey * 0.6) / Math.max(r, 0.5), t));
    }
  }
}

const shadeOf = (ramp, s) => (s > 0.42 ? ramp[2] : s < -0.3 ? ramp[0] : ramp[1]);

/** Where a hand goes for a named arm pose, from the shoulder. `side`: +1 the figure's right on screen. */
function handFor(pose, sh, side, f, h, chest) {
  const reach = h * 0.37;
  switch (pose) {
    case 'up':
      return [sh[0] + side * 3, Math.max(sh[1] - reach * 0.92, 2)];
    case 'clap':
      return [chest[0] + f * 3, chest[1] - h * 0.02];
    case 'cross':
      return [chest[0] - side * 2, chest[1] + h * 0.04];
    case 'phone':
      return [chest[0] + f * 4, sh[1] - h * 0.07];
    case 'hip':
      return [sh[0] + side * 0.5, sh[1] + h * 0.27];
    default:
      return [sh[0] + side * 1, sh[1] + reach * 0.97];
  }
}

/** One spectator in three-quarter view on `c`, its own dark edge on the side away from the light. */
function person(c, spec, row) {
  const { x, lift, h, f } = spec;
  const foot = CROWD_CELL[1] - 2 - lift;
  const skin = skinRamp(SKINS[spec.skin]);
  const shirt = clothRamp(spec.shirt);
  const inner = clothRamp(spec.inner ?? spec.shirt);
  const legs = clothRamp(spec.legs);
  const hairCol = HAIRS[spec.hairCol];
  const shoe = [hex('#16161c'), hex('#2c2c34'), hex('#5c5c66')];
  const mask = new Map();
  const put = (px, py, col) => {
    const xi = Math.round(px);
    const yi = Math.round(py);
    if (xi < 0 || yi < 0 || xi >= c.w || yi >= c.h) return;
    c.px(xi, yi, col);
    mask.set(yi * c.w + xi, true);
  };
  const top = foot - h;
  const headR = Math.max(h * 0.078, 2.4);
  const headY = top + headR + (spec.hair === 'cap' || spec.hair === 'sunhat' ? 0 : 0.5);
  const shoulderY = top + h * 0.2;
  const waistY = top + h * 0.42;
  const hipY = top + h * 0.5;
  const kneeY = top + h * 0.74;
  const cx = x;
  const turn = f * 1; // the chest and the head sit a pixel toward where the figure looks
  const shoulderW = h * 0.1;
  const nearShoulder = [cx - (f || -1) * shoulderW, shoulderY + 1];
  const farShoulder = [cx + (f || -1) * shoulderW * 0.75 + turn, shoulderY + 1];
  const side = nearShoulder[0] > cx ? 1 : -1;
  const chest = [cx + turn, shoulderY + h * 0.11];
  const pose = (name) => (spec[name] ?? ['hang', 'hang'])[row];

  // The far arm goes behind the body.
  const armLen = h * 0.2;
  const arm = (sh, hand0, elbow0, ramp, sleeveEnd) => {
    // A limb stays in its cell: cut off at the edge, a hand would float free of its arm.
    const keep = (q) => [Math.min(Math.max(q[0], 2), CROWD_CELL[0] - 3), q[1]];
    const hand = keep(hand0);
    const elbow = keep(elbow0);
    limb(put, sh, elbow, 1.7, 1.3, (s, t) => (t < sleeveEnd ? shadeOf(ramp, s) : shadeOf(skin, s)));
    limb(put, elbow, hand, 1.3, 1.0, (s) => shadeOf(skin, s));
    put(hand[0], hand[1], skin[1]);
    put(hand[0], hand[1] - 1, skin[2]);
  };
  const sleeveRamp = spec.top === 'dress' ? skin : shirt;
  const farHand = handFor(pose('far'), farShoulder, -side, f || -1, h, chest);
  const farElbow = ik(farShoulder, farHand, armLen, armLen, -side * (f === 0 ? 1 : -1));
  arm(farShoulder, farHand, farElbow, shirt.map((u) => mix(u, CREASE_DARK, 0.25)), spec.top === 'jacket' ? 1 : 0.55);

  // Legs, the far one a shade back; a wide stance on some.
  // Stances differ, feet together to feet well apart, so a row of legs never turns into a fence.
  const stance = spec.stance ?? h * 0.045 + (x % 3 === 0 ? 1 : 0);
  const legEnd = spec.shorts ? 0.45 : 1;
  const bareLeg = spec.shorts || spec.top === 'dress' || spec.top2 === 'skirt';
  const leg = (dx, footDx, ramp) => {
    const hip = [cx + dx, hipY];
    const knee = [cx + (dx + footDx) * 0.55, kneeY];
    const ankle = [cx + footDx, foot - 2];
    limb(put, hip, knee, h * 0.05, h * 0.036, (s) => shadeOf(ramp, s));
    limb(put, knee, ankle, h * 0.036, h * 0.026, (s, t) => (t < (legEnd - 0.45) / 0.55 ? shadeOf(ramp, s) : shadeOf(bareLeg ? skin : ramp, s)));
    const dir = f || -1;
    for (let i = -1; i <= 2; i++) put(cx + footDx + dir * i, foot, shoe[1]);
    for (let i = -1; i <= 1; i++) put(cx + footDx + dir * i, foot - 1, shoe[i === 0 ? 2 : 1]);
  };
  const legsDark = legs.map((u) => mix(u, CREASE_DARK, 0.28));
  leg(side * -h * 0.05, side * -(stance + (x % 2 === 0 ? 1.5 : 0.5)), legsDark);
  leg(side * h * 0.05, side * stance, legs);

  // The torso: shoulders, a waist, hips; a body that turns, lit on its right side. A dress runs to the knee.
  const skirted = spec.top === 'dress' || spec.top2 === 'skirt';
  const bottom = skirted ? kneeY + 1 : hipY + 1;
  for (let y = Math.round(shoulderY); y <= bottom; y++) {
    const u = (y - shoulderY) / (waistY - shoulderY);
    const v = (y - waistY) / Math.max(bottom - waistY, 1);
    let hw = u <= 1 ? shoulderW + 1 - u * h * 0.04 : shoulderW + 1 - h * 0.04 + v * (skirted ? 3 : 1);
    if (y === Math.round(shoulderY)) hw -= 1.5;
    const mid = cx + turn * (1 - Math.min(u, 1));
    for (let px = Math.round(mid - hw); px <= Math.round(mid + hw); px++) {
      const n = (px - mid) / hw;
      let col = n > 0.5 ? shirt[2] : n < -0.45 ? shirt[0] : shirt[1];
      const rel = y - Math.round(shoulderY);
      if (spec.top === 'stripe' && rel % 4 >= 2) col = n > 0.5 ? inner[2] : n < -0.45 ? inner[0] : inner[1];
      if (spec.top === 'jacket' && Math.abs(px - (mid + turn * 2)) < 1.5) col = Math.abs(px - (mid + turn * 2)) < 0.6 ? inner[0] : inner[1];
      // Two short folds that pull toward the waist.
      if ((px + y * 1) % 9 === (x % 9) && n > -0.5 && n < 0.5 && rel > 4 && spec.top !== 'stripe') col = shirt[0];
      if (y > hipY - 2 && spec.top !== 'dress') col = n > 0.5 ? legs[2] : legs[1];
      if (spec.top2 === 'skirt' && y > hipY + 3 && (px + y) % 5 === 0) col = legs[0];
      put(px, y, col);
    }
  }

  // Neck and head.
  const headX = cx + turn;
  limb(put, [headX, shoulderY - 1], [headX, headY + headR - 1], 1.3, 1.3, (s) => shadeOf(skin, s - 0.2));
  for (let j = -Math.ceil(headR) - 1; j <= Math.ceil(headR) + 1; j++) {
    for (let i = -Math.ceil(headR) - 1; i <= Math.ceil(headR) + 1; i++) {
      if ((i * i) / (headR * headR * 0.86) + (j * j) / (headR * headR * 1.1) > 1) continue;
      const s = (i * 0.8 - j * 0.45) / headR;
      put(headX + i, headY + j, s > 0.5 ? skin[2] : s < -0.42 ? skin[0] : skin[1]);
    }
  }
  const hx = Math.round(headX);
  const hy = Math.round(headY);
  const rr = Math.round(headR);
  // The face turned the way the figure looks: an eye, a nose past the cheek, a mouth open on the cheer.
  const eyeDark = hex('#26202a');
  if (h > 34) {
    put(hx + (f || -1) * (rr - 2), hy - 1, eyeDark);
    if (f === 0) put(hx - (rr - 2) + 2 * (rr - 2), hy - 1, eyeDark);
    if (f !== 0) put(hx + f * (rr + 0), hy, skin[1]);
    put(hx + (f || 0) * (rr - 2), hy + 1 + (row === 1 ? 0 : 0), row === 1 ? hex('#6c2c30') : skin[0]);
  } else {
    put(hx + (f || -1) * (rr - 1), hy, eyeDark);
  }
  // Hair and hats, from behind the face.
  const back = -(f || -1);
  const hairLit = mix(hairCol, SUNNY, 0.25);
  const hairDark = mix(hairCol, CREASE_DARK, 0.3);
  const hatCols = clothRamp(spec.tint ?? '#808080');
  const capRow = (y, x0, x1, ramp) => {
    for (let i = x0; i <= x1; i++) put(hx + i, y, i > (x0 + x1) * 0.5 + 1 ? ramp[2] : i < x0 + 2 ? ramp[0] : ramp[1]);
  };
  if (spec.hair === 'bald') {
    capRow(hy - rr, -rr + 1, rr - 1, skin);
    put(hx + back * rr, hy, hairCol);
    put(hx + back * rr, hy + 1, hairDark);
  } else if (spec.hair === 'cap' || spec.hair === 'beanie') {
    capRow(hy - rr - 1, -rr + 1, rr - 1, hatCols);
    capRow(hy - rr, -rr, rr, hatCols);
    capRow(hy - rr + 1, -rr, rr, hatCols);
    if (spec.hair === 'cap') for (let i = 1; i <= rr + 2; i++) put(hx + (f || -1) * i, hy - rr + 2, hatCols[0]);
    else capRow(hy - rr + 2, -rr, rr, hatCols.map((u) => mix(u, CREASE_DARK, 0.2)));
    put(hx + back * rr, hy, hairDark);
  } else if (spec.hair === 'sunhat') {
    capRow(hy - rr - 2, -rr + 1, rr - 1, hatCols);
    capRow(hy - rr - 1, -rr, rr, hatCols);
    capRow(hy - rr, -rr, rr, hatCols);
    capRow(hy - rr + 1, -rr - 3, rr + 3, hatCols);
    for (let j = 0; j <= 3; j++) put(hx + back * rr, hy - rr + 2 + j, hairDark);
  } else {
    capRow(hy - rr - 1, -rr + 1, rr - 1, [hairDark, hairCol, hairLit]);
    capRow(hy - rr, -rr, rr, [hairDark, hairCol, hairLit]);
    for (let j = -rr + 1; j <= (spec.hair === 'long' ? rr + 4 : 0); j++) {
      put(hx + back * rr, hy + j, j > 2 ? hairDark : hairCol);
      if (j < rr) put(hx + back * (rr - 1), hy + j, hairCol);
      if (spec.hair === 'long') put(hx + back * (rr + 1), hy + j, hairDark);
    }
  }

  // The near arm, on top of the body; where it crosses, a dark crease keeps it apart.
  const nearHand = spec.a
    ? [CROWD_HAND_UP[0], CROWD_HAND_UP[1] + (row === 0 ? CROWD_HAND_DOWN_DY : 0)]
    : handFor(pose('near'), nearShoulder, side, f || -1, h, chest);
  // The flag hand: the upper arm hangs and the forearm comes forward, or the forearm stands straight up.
  const flagElbow = row === 0 ? [nearShoulder[0] + 1.5, nearShoulder[1] + armLen] : [nearHand[0] + 1, nearShoulder[1] + 2];
  const elbow = spec.a ? flagElbow : ik(nearShoulder, nearHand, armLen, armLen, side);
  limb(put, nearShoulder, elbow, 2.0, 1.6, () => shirt[0]);
  limb(put, elbow, nearHand, 1.6, 1.3, () => skin[0]);
  arm(nearShoulder, nearHand, elbow, sleeveRamp, spec.top === 'jacket' ? 1 : 0.55);

  // The figure's dark edge, to the left of and under it, drawn over whoever stands behind.
  const out = [];
  for (let y = 0; y < c.h; y++) {
    for (let px = 0; px < c.w; px++) {
      if (mask.has(y * c.w + px)) continue;
      if ((px + 1 < c.w && mask.has(y * c.w + px + 1)) || (y > 0 && mask.has((y - 1) * c.w + px))) out.push([px, y]);
    }
  }
  for (const [px, y] of out) c.px(px, y, CROWD_EDGE);
}

/** 26 x 56, 8 small groups across; row 0 hands down, row 1 hands up. */
export function crowd() {
  const [w, h] = CROWD_CELL;
  const c = new Canvas(w * GROUPS.length, h * 2);
  GROUPS.forEach((group, s) => {
    for (let row = 0; row < 2; row++) {
      const cell = new Canvas(w, h);
      // A soft patch of trodden shade under the feet.
      for (const spec of group) {
        const fy = h - 1 - spec.lift;
        for (let i = -6; i <= 6; i++) if (i % 2 === 0 || Math.abs(i) < 3) cell.px(spec.x + i, fy, [70, 84, 80, 80]);
      }
      for (const spec of group) person(cell, spec, row);
      // A whole step back in the air: only the riders keep full contrast.
      for (let i = 0; i < cell.data.length; i += 4) {
        if (cell.data[i + 3] !== 255) continue;
        const u = inAir([cell.data[i], cell.data[i + 1], cell.data[i + 2]]);
        cell.data[i] = u[0];
        cell.data[i + 1] = u[1];
        cell.data[i + 2] = u[2];
      }
      c.blit(cell, s * w, row * h);
    }
  });
  return c;
}

/** 12 x 16, 4 frames: a generic striped hand flag, waving. */
export function flag() {
  const c = new Canvas(48, 16);
  // In the same air as the crowd that waves it, and small: no rider's pennant is ever mistaken for one.
  const stripes = ['#ecece4', '#8094a8'].map((u) => inAir(hex(u)));
  const shade = ['#bcbcb8', '#667a90'].map((u) => inAir(hex(u)));
  for (let f = 0; f < 4; f++) {
    const x = f * 12;
    c.rect(x + FLAG_GRIP[0], 3, 1, FLAG_GRIP[1] - 2, CROWD_EDGE);
    for (let i = 0; i < 7; i++) {
      const u = ((i + f * 2) * Math.PI) / 4;
      const wave = Math.round(Math.sin(u));
      const dark = Math.cos(u) < -0.3;
      for (let j = 0; j < 5; j++) {
        const band = j < 2 || j > 2 ? 0 : 1;
        c.px(x + 2 + i, 4 + j + wave, (dark ? shade : stripes)[band]);
      }
    }
  }
  return c;
}

export const GANTRY_H = 124;

const GLYPHS = {
  S: ['01111', '10000', '10000', '01110', '00001', '00001', '11110'],
  P: ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
  R: ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
  I: ['11111', '00100', '00100', '00100', '00100', '00100', '11111'],
  N: ['10001', '11001', '10101', '10101', '10011', '10001', '10001'],
  T: ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
};

/** 200 x 124: the sprint banner high on two lattice masts, well over the riders' helmets. Dusty cloth, no slab. */
export function gantry() {
  const c = new Canvas(200, GANTRY_H);
  const steel = hex('#4a4e58');
  const lit = hex('#8a8e98');
  const dark = hex('#2a2c34');
  for (const x of [5, 190]) {
    // A lattice mast on a weighted foot.
    c.rect(x, 4, 1, GANTRY_H - 6, steel);
    c.rect(x + 4, 4, 1, GANTRY_H - 6, lit);
    for (let y = 8; y < GANTRY_H - 4; y += 6) {
      c.line(x, y, x + 4, y + 3, dark);
      c.line(x + 4, y + 3, x, y + 6, dark);
    }
    c.rect(x - 3, GANTRY_H - 3, 11, 3, dark);
    c.rect(x - 3, GANTRY_H - 3, 11, 1, steel);
  }
  // The truss over the road.
  c.rect(5, 4, 190, 1, lit);
  c.rect(5, 8, 190, 1, steel);
  for (let x = 6; x < 194; x += 6) {
    c.line(x, 5, x + 3, 7, dark);
    c.line(x + 3, 7, x + 6, 5, dark);
  }
  // The banner: faded cloth with a sag along its bottom edge, ties to the truss, folds that catch the light.
  const red = [hex('#5c3430'), hex('#8a4c40'), hex('#a8664e')];
  const hem = hex('#cfc6b0');
  const sag = (x) => Math.round(2 * Math.sin(((x - 14) / 172) * Math.PI));
  for (let x = 14; x < 186; x++) {
    const bottom = 33 + sag(x);
    for (let y = 11; y <= bottom; y++) {
      // Soft vertical folds, each with one lit and one shaded column.
      const f = (x - 14) % 43;
      let col = f === 0 || f === 22 ? red[0] : f === 1 || f === 23 ? red[2] : red[1];
      if (y === 11) col = hem;
      if (y === bottom) col = hem;
      if (y === bottom - 1) col = red[0];
      c.px(x, y, col);
    }
  }
  for (const x of [14, 57, 100, 143, 185]) c.rect(x, 9, 1, 2, dark);
  const word = 'SPRINT';
  const scale = 2;
  let x = 100 - Math.floor((word.length * 6 * scale - scale) / 2);
  for (const ch of word) {
    GLYPHS[ch].forEach((row, j) => {
      [...row].forEach((bit, i) => {
        if (bit !== '1') return;
        c.rect(x + i * scale + 1, 15 + j * scale + 1, scale, scale, red[0]);
        c.rect(x + i * scale, 15 + j * scale, scale, scale, hem);
      });
    });
    x += 6 * scale;
  }
  // A string of small pennants under the banner.
  const cols = ['#cfc6b0', '#4a7096', '#b09a50', '#4c8066'].map(hex);
  for (let i = 0; i < 16; i++) {
    const px = 16 + i * 11;
    const y = 40 + Math.round(3 * Math.sin((i / 15) * Math.PI));
    c.px(px, y - 1, dark);
    c.px(px + 5, y - 1, dark);
    for (let j = 0; j < 4; j++) {
      c.rect(px + j, y + j, Math.max(6 - j * 2, 1), 1, cols[i % 4]);
    }
  }
  return c;
}
