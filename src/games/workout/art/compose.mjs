// Composites from the baked parts, without Godot: the picker card and the previews for art rounds.
// It places things the way the view does: road tile top c - contact_row, far verge top c - above, near
// verge top c + below, bank top c + 32 (kit.road), rider cell at contact - origin.
import { Canvas, hex } from './raster.mjs';
import { recolour } from './palette.mjs';
import * as R from './rig.mjs';

const W = 960;
const H = 540;
const STAGE_TOP = -180;

/** Tiles a recoloured plane across the canvas at top y, scrolled by `scroll` px. */
function tile(out, plane, top, scroll = 0) {
  for (let y = 0; y < plane.h; y++) {
    const yy = top + y;
    if (yy < 0 || yy >= H) continue;
    for (let x = 0; x < W; x++) {
      const c = plane.get(((x + scroll) % plane.w + plane.w) % plane.w, y);
      if (c[3] > 0) out.blendPx(x, yy, c);
    }
  }
}

function bankFill(out, contact, tod) {
  const c = tod.bank.map((u) => Math.round(u * 255));
  const hi = tod.bank_hi.map((u) => Math.round(u * 255));
  for (let x = 0; x < W; x++) {
    const top = Math.round(contact(x)) + 32;
    for (let y = top; y < H; y++) out.px(x, y, y === top ? hi : c);
  }
}

function roadRows(out, plane, contact, topOf, scroll) {
  for (let x = 0; x < W; x++) {
    const col = (x + scroll) % plane.w;
    const top = topOf(Math.round(contact(x)));
    for (let y = 0; y < plane.h; y++) {
      const c = plane.get(col, y);
      if (c[3] > 0) out.blendPx(x, top + y, c);
    }
  }
}

function tint(c, t) {
  return [Math.round(c[0] * t[0]), Math.round(c[1] * t[1]), Math.round(c[2] * t[2]), c[3]];
}

function stamp(out, src, sx, sy, w, h, dx, dy, t = [1, 1, 1]) {
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const c = src.get(sx + x, sy + y);
      if (c[3] > 0) out.blendPx(dx + x, dy + y, tint(c, t));
    }
  }
}

/** One rider standing on `contact` with its wheels on the road at draw x `x`. */
function drawRider(out, parts, r, contact, t) {
  const rearY = Math.round(contact(r.x - 20)) + r.lane;
  const frontY = Math.round(contact(r.x + 20)) + r.lane;
  const wheelFrame = r.wheel ?? 0;
  const wheelAt = (hub, y) => {
    stamp(out, parts.wheel, wheelFrame * 27, 0, 27, 27, r.x - R.ORIGIN[0] + hub - 13, y - 13 - 13, t);
  };
  wheelAt(R.REAR_HUB[0], rearY);
  wheelAt(R.FRONT_HUB[0], frontY);
  const row = R.POSE_ROWS[r.pose] + (r.pose === 'stop' ? 0 : Math.floor(r.frame / R.COLS));
  const col = r.pose === 'stop' ? 0 : r.frame % R.COLS;
  const pitch = Math.max(Math.min(frontY - rearY, 6), -6);
  const slices = Math.abs(pitch) + 1;
  const sliceW = Math.ceil(R.CELL[0] / slices);
  for (let s = 0; s < slices; s++) {
    const dy = Math.round((pitch * s) / Math.max(slices - 1, 1));
    stamp(
      out,
      parts.sheets[r.slot],
      col * R.CELL[0] + s * sliceW,
      row * R.CELL[1],
      Math.min(sliceW, R.CELL[0] - s * sliceW),
      R.CELL[1],
      r.x - R.ORIGIN[0] + s * sliceW,
      rearY - R.TYRE_ROW + dy,
      t,
    );
  }
}

/** A backdrop plus riders at LUT row `row`. `contact(x)` is the middle lane's contact y. */
export function scene(parts, kit, row, { contact = () => 384, scroll = 0, riders = [], blocks = [], crowd = false }) {
  const out = new Canvas(W, H);
  const tod = kit.tod[row];
  const planeOf = (name) => recolour(parts.planes[name], parts.lut, row);
  const sky = planeOf('sky');
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) out.px(x, y, sky.get(x % sky.w, y - STAGE_TOP));
  }
  tile(out, planeOf('stars'), STAGE_TOP);
  stamp(out, parts.sun, 0, 0, 40, 40, tod.sun[0] - 20, tod.sun[1] - 20);
  for (const p of kit.planes) {
    if (p.name === 'sky' || p.name === 'stars' || p.name === 'foreground') continue;
    tile(out, planeOf(p.name), p.y, Math.round(scroll * p.factor));
  }
  const vergeFar = planeOf('verge_far_0');
  const road = planeOf('road');
  const vergeNear = planeOf('verge_near_0');
  roadRows(out, vergeFar, contact, (c) => c - kit.road.verge_far.above, scroll);
  roadRows(out, road, contact, (c) => c - kit.road.contact_row, scroll);
  if (crowd) {
    for (let i = 0; i < 40; i++) {
      const x = 12 + i * 23;
      stamp(out, parts.props.crowd, (i % 8) * 16, (i % 3 === 0 ? 1 : 0) * 30, 16, 30, x - 8, Math.round(contact(x)) - kit.props.crowd.foot_above_contact - 30, tod.rider_tint);
    }
  }
  const order = [...riders].sort((a, b) => a.lane - b.lane || a.x - b.x);
  for (const r of order) drawRider(out, parts, r, contact, tod.rider_tint);
  roadRows(out, vergeNear, contact, (c) => c + kit.road.verge_near.below, scroll);
  bankFill(out, contact, tod);
  tile(out, planeOf('foreground_0'), 396, Math.round(scroll * 1.35));
  for (const b of blocks) {
    const color = hex(b.color);
    const bottom = 460;
    for (let x = b.x0; x < b.x1; x++) {
      for (let y = bottom - b.h; y < bottom; y++) out.px(x, y, y === bottom - b.h ? color.map((u) => Math.min(u + 40, 255)) : color);
    }
  }
  return out;
}

const FORMATION = [
  [0, 0],
  [-34, 9],
  [-68, -9],
  [-102, 0],
];

/** The picker card: golden hour, a road rising to the right, four riders, a crowd, blocks. No text. */
export function pickerCard(parts, kit) {
  const contact = (x) => 400 - 30 * (x / W) - 8 * Math.sin((x / W) * Math.PI * 2);
  const frames = [3, 9, 15, 21];
  const riders = FORMATION.map(([dx, lane], i) => ({
    x: 560 + dx,
    lane,
    slot: i,
    pose: i === 0 ? 'stand' : 'seat',
    frame: frames[i],
    wheel: (i * 5) % 16,
  }));
  const blocks = [
    [0, 120, 16, '#4fa36a'],
    [120, 300, 28, '#e88a3a'],
    [300, 380, 12, '#8fa3b8'],
    [380, 560, 32, '#d4553f'],
    [560, 640, 12, '#8fa3b8'],
    [640, 690, 40, '#b45fc4'],
    [690, 860, 28, '#e88a3a'],
    [860, 960, 12, '#6f8296'],
  ].map(([x0, x1, h, color]) => ({ x0: x0 + 1, x1, h, color }));
  return scene(parts, kit, Math.floor(0.4 * 31), { contact, riders, blocks, crowd: true, scroll: 340 });
}

const PREVIEW_RIDERS = FORMATION.map(([dx, lane], i) => ({
  x: 360 + dx,
  lane,
  slot: i,
  pose: 'seat',
  frame: (i * 6 + 3) % 24,
  wheel: i * 3,
}));

function pose24(parts, pose) {
  const n = pose === 'stop' ? 1 : R.CRANK_FRAMES;
  const sheet = new Canvas(R.COLS * R.CELL[0], Math.ceil(n / R.COLS) * R.CELL[1]);
  for (let k = 0; k < n; k++) {
    const x = (k % R.COLS) * R.CELL[0];
    const y = Math.floor(k / R.COLS) * R.CELL[1];
    const row = R.POSE_ROWS[pose] + Math.floor(k / R.COLS);
    for (const hub of [R.REAR_HUB[0], R.FRONT_HUB[0]]) stamp(sheet, parts.wheel, 0, 0, 27, 27, x + hub - 13, y + R.REAR_HUB[1] - 13);
    stamp(sheet, parts.sheets[0], (k % R.COLS) * R.CELL[0], row * R.CELL[1], R.CELL[0], R.CELL[1], x, y);
    // The crank angle tick: the near pedal's table position, in a colour no rider uses.
    const [px, py] = R.pedalAt(k).map((u) => Math.round(u));
    sheet.px(x + px, y + py - 1, [255, 0, 255]);
  }
  return sheet.scaled(4);
}

/** Every preview, by file name. */
export function previews(parts, kit) {
  const out = new Map();
  for (const [name, p] of [
    ['tod_00', 0],
    ['tod_22', 0.22],
    ['tod_40', 0.4],
    ['tod_65', 0.65],
    ['tod_100', 1],
  ]) {
    out.set(`${name}.png`, scene(parts, kit, Math.floor(Math.min(p, 1) * 31), { riders: PREVIEW_RIDERS, scroll: 340 }));
  }
  for (const pose of ['seat', 'stand', 'situp', 'stop']) out.set(`rider_contact_${pose}.png`, pose24(parts, pose));
  const slots = new Canvas(8 * R.CELL[0], R.CELL[1]);
  parts.sheets.forEach((sheet, s) => stamp(slots, sheet, 0, 0, R.CELL[0], R.CELL[1], s * R.CELL[0], 0));
  out.set('slots.png', slots.scaled(4));
  const props = new Canvas(480, 300);
  let y = 2;
  for (const key of ['windpump', 'cattle', 'tractor', 'smoke', 'flock', 'balloon', 'flag']) {
    props.blit(parts.props[key], 2, y);
    y += parts.props[key].h + 2;
  }
  props.blit(parts.props.crowd, 262, 2);
  props.blit(parts.props.gantry, 262, 70);
  out.set('props.png', props);
  return out;
}

