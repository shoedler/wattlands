// Rider sheets, the wheel and the small rider effects. True colour: the view tints them by time of day.
//
// Rider sheet addressing (kit.json, WorkoutKit): row = pose_rows[pose] + frame / 6, col = frame % 6,
// source rect (col * 88, row * 84, 88, 84). The stop pose ignores the frame (row 12, col 0).
//
// Paint order in a frame: far arm, far leg, far crank and pedal, chain and chainring, rear cog and
// derailleur, frame tubes, fork, saddle, bars, torso, near leg, near crank and pedal, near arm, head,
// helmet. Wheels are their own sprites, drawn before the frame, so the fork and stays sit over them.
import { Canvas, hex } from './raster.mjs';
import * as R from './rig.mjs';

export const SLOT_COLORS = ['#D55E00', '#0072B2', '#F0E442', '#009E73'];
export const HOLLOW_BODY = '#f4f2ea';
const PATTERNS = ['solid', 'dashed', 'dotted', 'double'];
const SKIN = ['#e8b48c', '#c98e62', '#8e5c3a', '#f0c8a4'];
const FRAME_TUBE = { graphite: '#3a3d44', steel: '#8a95a0' };
const OUTLINE = hex('#14161c');
const SHORTS = hex('#1a1b20');
const SHORTS_HI = hex('#3a3c44');
const WHITE = hex('#f6f6f0');
const CRANK_ARM = hex('#50545c');
const CHAIN_DARK = hex('#26282e');
const CHAIN_LIGHT = hex('#8a8e96');
const RING = hex('#6a6e76');
const SADDLE = hex('#17181c');
const TAPE = hex('#22242a');
/** The pedal's own colour: tests find the pedal by it. */
export const PEDAL = [216, 220, 228];
export const WHEEL_FRAMES = 16;
export const WHEEL_CELL = 27;
export const FX_SIZE = [54, 21];

const shade = (c, k) => c.map((u) => Math.max(Math.min(Math.round(u * k), 255), 0));

/** Slot look: jersey, body, sleeve, pattern, helmet, tube, skin (BRIEF 3.9: colour plus pattern). */
export function slotLook(slot) {
  const base = slot % 4;
  const color = hex(SLOT_COLORS[base]);
  const hollow = slot >= 4;
  return {
    color,
    body: hollow ? hex(HOLLOW_BODY) : color,
    sleeve: color,
    pattern: PATTERNS[base],
    helmet: hollow ? color : WHITE,
    tube: hex(base % 2 === 0 ? FRAME_TUBE.graphite : FRAME_TUBE.steel),
    skin: hex(SKIN[base]),
  };
}

function drawArm(c, p, look, far) {
  const k = far ? 0.72 : 1;
  c.thick(p.shoulder[0] + (far ? 2 : 0), p.shoulder[1], p.elbow[0] + (far ? 2 : 0), p.elbow[1], 3, shade(look.sleeve, k));
  c.thick(p.elbow[0] + (far ? 2 : 0), p.elbow[1], p.hands[0] + (far ? 1 : 0), p.hands[1], 2, shade(look.skin, k));
  if (!far) c.rect(p.hands[0] - 1, p.hands[1] - 1, 2, 2, shade(look.skin, 0.85));
}

function drawLeg(c, l, look, far) {
  const k = far ? 0.72 : 1;
  c.thick(l.hip[0], l.hip[1], l.knee[0], l.knee[1], 4, shade(SHORTS, far ? 0.9 : 1));
  c.thick(l.knee[0], l.knee[1], l.ankle[0], l.ankle[1], 3, shade(look.skin, k));
  if (!far) c.px(l.knee[0], l.knee[1] - 1, SHORTS_HI);
  // The shoe, from the ankle down to the pedal.
  c.thick(l.ankle[0], l.ankle[1], l.pedal[0] + 1, l.pedal[1] - 1, 2, shade(WHITE, far ? 0.55 : 0.8));
}

function drawCrank(c, pedal, k) {
  const color = shade(CRANK_ARM, k);
  c.thick(R.BB[0], R.BB[1], pedal[0], pedal[1], 2, color);
  const x = Math.round(pedal[0]);
  const y = Math.round(pedal[1]);
  c.rect(x - 2, y, 4, 1, k < 1 ? shade(PEDAL, 0.6) : PEDAL);
}

function drawDrivetrain(c, frame) {
  const off = R.chainOffset(frame);
  const [hx, hy] = R.REAR_HUB;
  const [bx, by] = R.BB;
  const topY = by - R.CHAINRING_R;
  const botY = by + R.CHAINRING_R;
  const x0 = hx + 1;
  const x1 = bx - 1;
  // Top run moves toward the chainring, bottom run away from it, 2 dark then 2 light.
  for (let x = x0; x <= x1; x++) {
    const t = (x - x0) / (x1 - x0);
    const yTop = Math.round(hy - R.COG_R + (topY - (hy - R.COG_R)) * t);
    const yBot = Math.round(hy + R.COG_R + 1 + (botY - (hy + R.COG_R + 1)) * t);
    const m = R.CHAIN_PERIOD;
    c.px(x, yTop, ((x - off + 4 * m) % m) < 2 ? CHAIN_DARK : CHAIN_LIGHT);
    c.px(x, yBot, ((x + off + 4 * m) % m) < 2 ? CHAIN_DARK : CHAIN_LIGHT);
  }
  c.ring(bx, by, R.CHAINRING_R, RING);
  c.px(bx, by, CHAIN_DARK);
  // Rear cog: one dark tooth turns COG_TURNS times per crank revolution.
  c.ring(hx, hy, R.COG_R, RING);
  const cog = R.crankTheta(frame) * R.COG_TURNS;
  c.px(hx + R.COG_R * Math.cos(cog), hy + R.COG_R * Math.sin(cog), CHAIN_DARK);
  // Derailleur: two jockey wheels whose dark pixel flips every 3 frames.
  const flip = Math.floor(frame / 3) % 2;
  c.px(hx + 1, hy + 5, flip ? CHAIN_DARK : RING);
  c.px(hx + 2, hy + 5, flip ? RING : CHAIN_DARK);
  c.px(hx + 2, hy + 8, flip ? RING : CHAIN_DARK);
  c.px(hx + 3, hy + 8, flip ? CHAIN_DARK : RING);
  c.line(hx, hy + 2, hx + 2, hy + 8, RING);
}

function drawBike(c, look) {
  const t = look.tube;
  const seatCluster = [30, 46];
  const headTop = [55, 47];
  const headBottom = [57, 53];
  c.line(R.REAR_HUB[0], R.REAR_HUB[1], seatCluster[0], seatCluster[1], shade(t, 0.85));
  c.line(R.REAR_HUB[0], R.REAR_HUB[1], R.BB[0], R.BB[1], shade(t, 0.85));
  c.thick(R.BB[0], R.BB[1], seatCluster[0], seatCluster[1], 2, t);
  c.thick(seatCluster[0], seatCluster[1], headTop[0], headTop[1], 2, t);
  c.thick(R.BB[0], R.BB[1], headBottom[0], headBottom[1], 2, t);
  c.thick(headTop[0], headTop[1], headBottom[0], headBottom[1], 2, shade(t, 1.2));
  c.thick(headBottom[0], headBottom[1], R.FRONT_HUB[0], R.FRONT_HUB[1], 2, shade(t, 0.9));
  c.line(seatCluster[0], seatCluster[1], R.SADDLE[0], R.SADDLE[1], CRANK_ARM);
  c.rect(R.SADDLE[0] - 4, R.SADDLE[1] - 1, 9, 2, SADDLE);
  c.line(headTop[0], headTop[1], R.BARS[0], R.BARS[1], CRANK_ARM);
  c.line(R.BARS[0], R.BARS[1], R.HOODS[0], R.HOODS[1], TAPE);
  c.line(R.HOODS[0], R.HOODS[1], R.HOODS[0] + 2, R.HOODS[1] + 4, TAPE);
  c.line(R.HOODS[0] + 2, R.HOODS[1] + 4, R.HOODS[0] - 1, R.HOODS[1] + 6, TAPE);
}

function drawTorso(c, p, look) {
  const [hx, hy] = p.hip;
  const [sx, sy] = p.shoulder;
  c.polyFill(
    [
      [hx - 3, hy + 2],
      [hx + 3, hy + 3],
      [sx + 3, sy + 3],
      [sx - 2, sy - 2],
    ],
    look.body,
  );
  c.line(hx - 3, hy + 1, sx - 2, sy - 2, OUTLINE);
  c.thick(sx, sy, sx - (sx - hx) * 0.2, sy - (sy - hy) * 0.2, 4, look.sleeve);
  const dark = shade(look.color, 0.55);
  const at = (t) => [hx + (sx - hx) * t, hy + (sy - hy) * t];
  if (look.pattern === 'dashed') {
    for (const t of [0.3, 0.6]) {
      const q = at(t);
      c.rect(q[0], q[1], 2, 1, shade(look.color, 1.5));
    }
  } else if (look.pattern === 'dotted') {
    for (const t of [0.25, 0.45, 0.65]) {
      const q = at(t);
      c.px(q[0], q[1], dark);
    }
  } else if (look.pattern === 'double') {
    for (const t of [0.45, 0.6]) {
      const q = at(t);
      c.line(q[0] - 2, q[1] - 1, q[0] + 2, q[1] + 1, dark);
    }
  }
  c.thick(hx - 1, hy, hx + 1, hy + 1, 4, SHORTS);
}

function drawHead(c, p, look, name) {
  const [hx, hy] = p.head;
  c.disk(hx, hy, R.HEAD_R, look.skin);
  c.px(hx + 3, hy, OUTLINE);
  const down = name === 'situp' ? 1 : 0;
  // The helmet: the top half of the head, a bit wider, with one vent.
  for (let j = -R.HEAD_R - 1; j <= -1 + down; j++) {
    for (let i = -R.HEAD_R - 1; i <= R.HEAD_R; i++) {
      if (i * i + j * j <= (R.HEAD_R + 1) ** 2) c.px(hx + i, hy + j, look.helmet);
    }
  }
  c.px(hx - 1, hy - 3, shade(look.helmet, 0.6));
  c.px(hx + 1, hy + 1, shade(look.skin, 0.8));
}

/** One rider frame as an 88 x 84 Canvas: everything but the wheels. */
export function riderFrame(slot, name, k) {
  const c = new Canvas(R.CELL[0], R.CELL[1]);
  const look = slotLook(slot);
  const p = R.pose(name, k);
  drawArm(c, p, look, true);
  drawLeg(c, p.far, look, true);
  drawCrank(c, p.farPedal, 0.72);
  drawDrivetrain(c, p.frame);
  drawBike(c, look);
  drawTorso(c, p, look);
  drawLeg(c, p.near, look, false);
  drawCrank(c, p.nearPedal, 1);
  drawArm(c, p, look, false);
  drawHead(c, p, look, name);
  return c;
}

/** One slot's sheet, 528 x 1092. */
export function riderSheet(slot) {
  const sheet = new Canvas(R.COLS * R.CELL[0], R.ROWS * R.CELL[1]);
  for (const name of ['seat', 'stand', 'situp']) {
    for (let k = 0; k < R.CRANK_FRAMES; k++) {
      const row = R.POSE_ROWS[name] + Math.floor(k / R.COLS);
      sheet.blit(riderFrame(slot, name, k), (k % R.COLS) * R.CELL[0], row * R.CELL[1]);
    }
  }
  sheet.blit(riderFrame(slot, 'stop', 0), 0, R.POSE_ROWS.stop * R.CELL[1]);
  return sheet;
}

/** 27 x 27 x 16: one full turn, 6 spokes (60 deg period at 22.5 deg per frame reads forward), a valve. */
export function wheelSheet() {
  const sheet = new Canvas(WHEEL_CELL * WHEEL_FRAMES, WHEEL_CELL);
  const tyre = hex('#17181c');
  const rim = hex('#7c828c');
  const spoke = hex('#a0a6b0');
  const hub = hex('#50545c');
  const valve = hex('#e8e8e0');
  const mid = 13;
  for (let f = 0; f < WHEEL_FRAMES; f++) {
    const c = new Canvas(WHEEL_CELL, WHEEL_CELL);
    const a0 = (f * 22.5 * Math.PI) / 180;
    for (let s = 0; s < 6; s++) {
      const a = a0 + (s * Math.PI) / 3;
      c.line(mid, mid, mid + 10 * Math.cos(a), mid + 10 * Math.sin(a), spoke);
    }
    c.ring(mid, mid, R.WHEEL_R, tyre, 2);
    c.ring(mid, mid, R.WHEEL_R - 2, rim);
    c.disk(mid, mid, 1, hub);
    c.px(mid + 10 * Math.cos(a0 + Math.PI / 6), mid + 10 * Math.sin(a0 + Math.PI / 6), valve);
    sheet.blit(c, f * WHEEL_CELL, 0);
  }
  return sheet;
}

// Layout agrees with kit.fx: breath [0, 0, 8, 6, 4], dust [0, 6, 10, 6, 4], then the 9 x 9 bubbles.
export function fxSheet() {
  const sheet = new Canvas(FX_SIZE[0], FX_SIZE[1]);
  const breath = [238, 242, 250];
  const dust = [168, 150, 120];
  for (let f = 0; f < 4; f++) {
    const puff = f + 1;
    sheet.disk(f * 8 + 3, 3, Math.min(puff * 0.6, 2.2), f < 3 ? breath : shade(breath, 0.8));
    sheet.disk(f * 10 + 4, 9, Math.min(puff * 0.7, 2.4), f < 3 ? dust : shade(dust, 0.85));
  }
  const white = hex('#f6f6f0');
  const dark = hex('#14161c');
  const bubble = (x, f) => {
    sheet.rect(x + f * 9, 12, 9, 8, white);
    sheet.line(x + f * 9, 12, x + f * 9 + 8, 12, dark);
    sheet.line(x + f * 9, 19, x + f * 9 + 8, 19, dark);
    sheet.px(x + f * 9 + 4, 20, dark);
  };
  const orange = hex('#e8683c');
  for (let f = 0; f < 2; f++) {
    bubble(0, f);
    // rescue: an orange chevron that lifts on the second frame.
    sheet.line(f * 9 + 2, 17 - f, f * 9 + 4, 15 - f, orange);
    sheet.line(f * 9 + 4, 15 - f, f * 9 + 6, 17 - f, orange);
    bubble(18, f);
    // afk: a small z, then a bigger one.
    const zx = 18 + f * 9 + 2;
    sheet.line(zx, 14, zx + 2 + f, 14, dark);
    sheet.line(zx + 2 + f, 14, zx, 16 + f, dark);
    sheet.line(zx, 16 + f, zx + 2 + f, 16 + f, dark);
    bubble(36, f);
    // link: two chain ends with a gap that opens.
    const lx = 36 + f * 9 + 1;
    sheet.rect(lx, 15, 2, 2, dark);
    sheet.rect(lx + 5 + f, 15, 2, 2, dark);
    sheet.px(lx + 3, 14 - f, orange);
  }
  return sheet;
}
