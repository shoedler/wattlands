// Rider sheets, the wheel and the small rider effects. True colour: the view tints them by time of day.
//
// Rider sheet addressing (kit.json, WorkoutKit): row = pose_rows[pose] + frame / 6, col = frame % 6,
// source rect (col * 88, row * 84, 88, 84). The stop pose ignores the frame (row 12, col 0).
//
// Paint order in a frame: far arm, far leg, far crank and pedal, frame tubes, fork, saddle, bars, chain
// and chainring, rear cog and derailleur, torso, near crank arm, near leg and shoe, near pedal, near arm,
// head, helmet. The foot stands outboard of the crank, so the shoe covers the arm's end, never the reverse.
// The bike faces right, so its drive side faces the viewer: the drivetrain sits over the frame. Wheels are
// their own sprites, drawn before the frame, so the fork and stays sit over them.
//
// Limbs are capsules shaded per pixel from one light (upper right, where the sun climbs): three shades,
// hue-shifted, dark on the side away from the light, which also carries the only outline.
import { Canvas, hex } from './raster.mjs';
import { mix } from './palette.mjs';
import * as R from './rig.mjs';

export const SLOT_COLORS = ['#D55E00', '#0072B2', '#F0E442', '#009E73'];
export const HOLLOW_BODY = '#f4f2ea';
const PATTERNS = ['solid', 'dashed', 'dotted', 'double'];
const SKIN = ['#e8b48c', '#c98e62', '#8e5c3a', '#f0c8a4'];
const OUTLINE = hex('#14161c');
const WHITE = hex('#f6f6f0');
const SADDLE = hex('#1d1e24');
const SADDLE_LIT = hex('#5e626e');
const SADDLE_TAIL = hex('#aeb2bc');
/** The pedal's own colour, the top of the crank's amber: tests find the pedal by it. */
export const PEDAL = [255, 214, 128];
/** The chain's light links: a tone or two over the asphalt, so the chain moves and never shouts. */
export const CHAIN_LIGHT = [124, 128, 140];
/** Every 16 px one link a little warmer, for the eye to follow. */
export const CHAIN_LINK = [164, 152, 122];
export const WHEEL_FRAMES = 16;
export const WHEEL_CELL = 27;
export const FX_SIZE = [54, 21];

const LIGHT = [0.42, -0.91];
const COOL = [34, 30, 74];
const WARM = [255, 240, 200];

const clamp = (u, lo, hi) => Math.min(Math.max(u, lo), hi);

/** A three-shade ramp around a colour: shadows lean violet, lights lean warm. */
const rampOf = (c, dark = 0.42, light = 0.38) => [mix(c, COOL, dark), c, mix(c, WARM, light)];
/** Skin shades toward a warm red, so a shadow on a face stays a shadow and never turns to grey. */
const skinOf = (c) => [mix(c, [122, 48, 62], 0.52), c, mix(c, WARM, 0.32)];
/** The same ramp in the far side's shade: two steps back and hue-shifted, its three steps kept apart. */
const FAR_SHADE = [64, 34, 78];
const farOf = (ramp) => [mix(ramp[0], FAR_SHADE, 0.42), mix(ramp[1], FAR_SHADE, 0.3), mix(ramp[2], FAR_SHADE, 0.2)];

const SHORTS = [hex('#0d0e13'), hex('#1a1b20'), hex('#44464f')];
// Socks stay off-white: the crank is what the eye follows down there.
const SOCK = rampOf(hex('#cfd0d0'), 0.34, 0.1);
const SHOE = [hex('#14151b'), hex('#2c2e38'), hex('#50535f')];
/** The sole under a dark shoe: a light line, one row above the pedal, so the foot reads apart from the arm. */
export const SOLE = hex('#c4c8d0');
const GLOVE = [hex('#101116'), hex('#22242b'), hex('#3a3c44')];
const TUBES = {
  graphite: [hex('#1f2128'), hex('#3a3d44'), hex('#767b88')],
  steel: [hex('#566070'), hex('#8a95a0'), hex('#d0d8e0')],
};
const METAL = [hex('#34373f'), hex('#5a5e68'), hex('#a4a8b2')];
const RING = [hex('#464a54'), hex('#737985'), hex('#979ca8')];
// One amber arm, the only warm metal on the bike: no shoe, sock, ring or tube shares it.
export const CRANK_INK = { edge: hex('#4a2c20'), body: hex('#d98a2a'), lit: hex('#f6b450') };
const RIM = hex('#0b0c10');
const CREASE = hex('#231a2c');
const CHAIN_DARK = hex('#2a2b33');
const TAPE = [hex('#101116'), hex('#22242a'), hex('#4a4c56')];

const pick = (ramp, s) => (s > 0.34 ? ramp[2] : s < -0.34 ? ramp[0] : ramp[1]);

/** Slot look: jersey, body, sleeve, pattern, helmet, tube, skin (BRIEF 3.9: colour plus pattern). */
export function slotLook(slot) {
  const base = slot % 4;
  const color = hex(SLOT_COLORS[base]);
  const hollow = slot >= 4;
  const body = hollow ? hex(HOLLOW_BODY) : color;
  return {
    color,
    hollow,
    body,
    sleeve: color,
    pattern: PATTERNS[base],
    helmet: hollow ? color : WHITE,
    tube: base % 2 === 0 ? 'graphite' : 'steel',
    skin: hex(SKIN[base]),
    bodyRamp: rampOf(body, hollow ? 0.3 : 0.42, hollow ? 0 : 0.38),
    sleeveRamp: rampOf(color),
    skinRamp: skinOf(hex(SKIN[base])),
    helmetRamp: rampOf(hollow ? color : WHITE, hollow ? 0.42 : 0.34, hollow ? 0.45 : 0),
  };
}

/**
 * Paints a capsule from a to b, radius ra to rb. `paint(s, t, u)` gets the shading value s (-1..1 toward
 * the light), the position along the bone t (0..1) and the signed distance off it u, and returns a colour
 * or null. `mask` marks the rider's body pixels for the outline pass.
 */
function capsule(c, a, b, ra, rb, paint, mask = null, across = false, tag = 1) {
  const lim = Math.ceil(Math.max(ra, rb)) + 1;
  const x0 = Math.floor(Math.min(a[0], b[0])) - lim;
  const x1 = Math.ceil(Math.max(a[0], b[0])) + lim;
  const y0 = Math.floor(Math.min(a[1], b[1])) - lim;
  const y1 = Math.ceil(Math.max(a[1], b[1])) + lim;
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const len2 = Math.max(dx * dx + dy * dy, 1e-6);
  const len = Math.sqrt(len2);
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const t = clamp(((x - a[0]) * dx + (y - a[1]) * dy) / len2, 0, 1);
      const qx = a[0] + dx * t;
      const qy = a[1] + dy * t;
      const r = ra + (rb - ra) * t;
      const ex = x - qx;
      const ey = y - qy;
      const d = Math.hypot(ex, ey);
      if (d > r) continue;
      const u = (ex * dy - ey * dx) / len;
      // `across`: shade from the distance off the bone only, so two capsules in a row join without a seam.
      const nx = across ? (u * dy) / len : ex;
      const ny = across ? (-u * dx) / len : ey;
      const s = (nx * LIGHT[0] + ny * LIGHT[1]) / Math.max(r, 0.5);
      const col = paint(s, t, u);
      if (!col) continue;
      c.px(x, y, col);
      if (mask && x >= 0 && y >= 0 && x < c.w && y < c.h) mask[y * c.w + x] = tag;
    }
  }
}

// Which limb a mask pixel belongs to, so a near limb can cut a crease into what lies behind it.
const TAG_FAR = 2;
const TAG_TORSO = 3;
const TAG_NEAR_LEG = 4;
const TAG_NEAR_ARM = 5;

/** Darkens the `under` pixels that touch an `over` pixel and still show what `snap` held there. */
function crease(c, mask, over, under, snap, colour) {
  const hits = [];
  for (let y = 1; y < c.h - 1; y++) {
    for (let x = 1; x < c.w - 1; x++) {
      const p = y * c.w + x;
      if (mask[p] !== under) continue;
      const q = p * 4;
      if (c.data[q] !== snap[q] || c.data[q + 1] !== snap[q + 1] || c.data[q + 2] !== snap[q + 2]) continue;
      const near = [p - 1, p + 1, p - c.w, p + c.w].some((n) => mask[n] === over);
      if (near) hits.push([x, y]);
    }
  }
  for (const [x, y] of hits) c.px(x, y, colour);
}

const flat = (ramp) => (s) => pick(ramp, s);

function drawArm(c, p, look, far, mask) {
  const sleeve = far ? farOf(look.sleeveRamp) : look.sleeveRamp;
  const skin = far ? farOf(look.skinRamp) : look.skinRamp;
  // The far arm reaches past the near one, so a sliver of it stays in sight ahead of the near arm.
  const tag = far ? TAG_FAR : TAG_NEAR_ARM;
  const shoulder = far ? [p.shoulder[0] + 3, p.shoulder[1] + 1] : p.shoulder;
  const elbow = far ? [p.elbow[0] + 5, p.elbow[1] - 1] : p.elbow;
  const hand = far ? [p.hands[0] + 2, p.hands[1] - 1] : p.hands;
  capsule(c, shoulder, elbow, 2.6, 1.7, (s, t) => (t < 0.72 ? pick(sleeve, s) : pick(skin, s)), mask, false, tag);
  capsule(c, elbow, hand, 1.6, 1.2, flat(skin), mask, false, tag);
  if (!far) {
    // Fingerless glove on the hood, the thumb a lighter pixel.
    c.rect(hand[0] - 1, hand[1] - 1, 3, 2, GLOVE[1]);
    c.px(hand[0] + 1, hand[1] - 1, GLOVE[2]);
    c.px(hand[0] - 1, hand[1], skin[1]);
  }
}

/** The shoe from the ankle: a heel behind it, the ball over the pedal, the toe past it, a light sole under. */
function drawShoe(c, l, far, mask) {
  const k = far ? farOf(SHOE) : SHOE;
  const sole = far ? mix(SOLE, FAR_SHADE, 0.55) : SOLE;
  const tag = far ? TAG_FAR : TAG_NEAR_LEG;
  const ax = l.ankle[0];
  const ay = l.ankle[1];
  // The toe tips up and down a little with the ankle's swing: the foot is ridden, not bolted on.
  const tilt = clamp((ay - l.pedal[1] + 3.9) * 0.8, -0.6, 0.6);
  const heel = [ax - 0.8, l.pedal[1] - 2.6];
  const toe = [l.pedal[0] + 3.4, l.pedal[1] - 2.2 + tilt];
  capsule(c, heel, toe, 1.5, 1.05, (s) => (s < -0.5 ? k[0] : s > 0.5 ? k[2] : k[1]), mask, false, tag);
  // The ankle into the shoe, so the sock meets it without a step.
  capsule(c, [ax, ay], heel, 1.3, 1.4, () => k[1], mask, false, tag);
  const soleY = Math.round(l.pedal[1]) - 1;
  c.line(Math.round(heel[0]) - 1, soleY, Math.round(toe[0]) - 2, soleY, sole);
  c.line(Math.round(toe[0]) - 2, soleY, Math.round(toe[0]), soleY + Math.round(tilt), sole);
}

function drawLeg(c, l, look, far, mask) {
  const skin = far ? farOf(look.skinRamp) : look.skinRamp;
  const shorts = far ? farOf(SHORTS) : SHORTS;
  const sock = far ? farOf(SOCK) : SOCK;
  const hem = far ? farOf(look.sleeveRamp) : look.sleeveRamp;
  const tag = far ? TAG_FAR : TAG_NEAR_LEG;
  // The calf bulges behind the shin, a third of the way down: two capsules with different radii.
  const calf = [l.knee[0] + (l.ankle[0] - l.knee[0]) * 0.36 - 0.5, l.knee[1] + (l.ankle[1] - l.knee[1]) * 0.36];
  capsule(c, l.knee, calf, 2.1, 2.4, flat(skin), mask, false, tag);
  capsule(c, calf, l.ankle, 2.4, 1.2, (s, t) => (t > 0.66 ? pick(sock, s) : pick(skin, s)), mask, false, tag);
  // The short's gripper in the slot colour, between the black short and the skin.
  const thigh = (s, t) => (t < 0.72 ? pick(shorts, s) : t < 0.8 ? hem[1] : pick(skin, s));
  capsule(c, l.hip, l.knee, 3.6, 2.5, thigh, mask, false, tag);
  drawShoe(c, l, far, mask);
  if (!far) {
    // The kneecap catches the light.
    c.px(l.knee[0] + 1, l.knee[1] - 1, look.skinRamp[2]);
  }
}

/** The far crank and its pedal, behind the frame and dim. */
function drawFarCrank(c, pedal) {
  const x = Math.round(pedal[0]);
  const y = Math.round(pedal[1]);
  const steel = farOf(METAL);
  c.line(R.BB[0], R.BB[1], x, y, steel[0]);
  c.rect(x - 2, y, 4, 1, steel[1]);
}

/**
 * The near crank arm, one clean stroke from the axle to the pedal: amber body, lit side up or to the right,
 * a thin dark edge on the other side, so it stands off the ring. The shoe goes over its end.
 */
function drawCrankArm(c, pedal) {
  const x = Math.round(pedal[0]);
  const y = Math.round(pedal[1]);
  const [bx, by] = R.BB;
  const steep = Math.abs(y - by) > Math.abs(x - bx);
  const [ox, oy] = steep ? [1, 0] : [0, -1];
  c.line(bx - ox, by - oy, x - ox, y - oy, CRANK_INK.edge);
  c.line(bx, by, x, y, CRANK_INK.body);
  c.line(bx + ox, by + oy, x + ox, y + oy, CRANK_INK.lit);
  c.px(bx, by, CRANK_INK.edge);
}

/** The near pedal under the sole. */
function drawPedal(c, pedal) {
  const x = Math.round(pedal[0]);
  const y = Math.round(pedal[1]);
  c.rect(x - 2, y + 1, 5, 1, CRANK_INK.edge);
  c.rect(x - 2, y, 5, 1, PEDAL);
}

/** One run of chain, one pixel high: 2 dark, 2 light, and a warmer link every 16 px to follow. */
function chainRun(c, from, to, sign, frame) {
  const off = R.chainOffset(frame);
  const travel = R.chainTravel(frame);
  const m = R.CHAIN_PERIOD;
  const m2 = R.CHAIN_LINK_PERIOD;
  for (let x = from[0]; x <= to[0]; x++) {
    const t = (x - from[0]) / Math.max(to[0] - from[0], 1);
    const y = Math.round(from[1] + (to[1] - from[1]) * t);
    const u = x - sign * off;
    const v = x - sign * travel;
    const brass = ((v % m2) + m2) % m2 < 2;
    c.px(x, y, brass ? CHAIN_LINK : ((u % m) + m) % m < 2 ? CHAIN_DARK : CHAIN_LIGHT);
  }
}

/**
 * The chainring, a mid grey disc well inside the crank's reach: teeth that turn, a lit upper right, and
 * three cutouts one tone darker, never black, so it stays a ring and does not turn into a face.
 */
function drawChainring(c, theta) {
  const [bx, by] = R.BB;
  const r = R.CHAINRING_R;
  for (let j = -r; j <= r; j++) {
    for (let i = -r; i <= r; i++) {
      const d = Math.hypot(i, j);
      if (d >= r + 0.5) continue;
      const a = ((Math.atan2(j, i) - theta) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
      const lit = (i * LIGHT[0] + j * LIGHT[1]) / Math.max(d, 1);
      if (d >= r - 0.5) {
        // Teeth: one in two is cut back a tone.
        c.px(bx + i, by + j, Math.floor((a / (Math.PI * 2)) * 12) % 2 === 0 ? RING[1] : RING[0]);
      } else if (d >= r - 1.5) {
        c.px(bx + i, by + j, lit > 0.25 ? RING[2] : RING[1]);
      } else {
        const window = (a % ((Math.PI * 2) / 3)) < 1.0;
        c.px(bx + i, by + j, window ? RING[0] : RING[1]);
      }
    }
  }
}

/** Both chain runs, the chainring, the cog, the derailleur. */
function drawDrivetrain(c, frame) {
  const [hx, hy] = R.REAR_HUB;
  const [bx, by] = R.BB;
  const theta = R.crankTheta(frame);
  // A short cage: the bottom run stays well above the tyre's contact and the road's paint.
  const jockey0 = [hx + 2, hy + 4];
  const jockey1 = [hx + 3, hy + 7];
  // Top run moves toward the chainring, bottom run away from it.
  chainRun(c, [hx, hy - R.COG_R - 1], [bx, by - R.CHAINRING_R - 1], 1, frame);
  chainRun(c, [jockey1[0], jockey1[1] + 1], [bx, by + R.CHAINRING_R + 1], -1, frame);
  drawChainring(c, theta);
  // Rear cog: one dark tooth turns COG_TURNS times per crank revolution.
  c.disk(hx, hy, R.COG_R + 1, CHAIN_DARK);
  c.ring(hx, hy, R.COG_R, RING[2], 1);
  c.px(hx, hy, RING[1]);
  const cog = theta * R.COG_TURNS;
  c.px(hx + R.COG_R * Math.cos(cog), hy + R.COG_R * Math.sin(cog), RIM);
  // Derailleur: hanger, cage, two jockey wheels whose dark pixel flips every 3 frames.
  const flip = Math.floor(frame / 3) % 2;
  c.line(hx, hy + 2, jockey0[0], jockey0[1], RING[0]);
  c.line(jockey0[0], jockey0[1], jockey1[0], jockey1[1], RING[1]);
  for (const [i, jw] of [jockey0, jockey1].entries()) {
    c.rect(jw[0] - 1, jw[1] - 1, 2, 2, RING[2]);
    c.px(jw[0] - 1 + ((flip + i) % 2), jw[1] - 1, RIM);
    c.px(jw[0] - ((flip + i) % 2), jw[1], RING[1]);
  }
}

/** A tube exactly two pixels thick along a shallow line: the lit row on top, the body row under it. */
function tube2(c, a, b, tube) {
  for (let x = Math.round(a[0]); x <= Math.round(b[0]); x++) {
    const t = (x - a[0]) / Math.max(b[0] - a[0], 1);
    const y = Math.round(a[1] + (b[1] - a[1]) * t);
    c.px(x, y, tube[2]);
    c.px(x, y + 1, tube[0]);
  }
}

/** The saddle under the hips: a kicked-up tail, a flat top, a thin nose, on two rails over the post. */
function drawSaddle(c) {
  const [x, y] = R.SADDLE;
  // The rails and the clamp.
  c.line(x - 3, y + 2, x + 3, y + 2, METAL[2]);
  c.px(x, y + 3, METAL[1]);
  // The shell: tail back and up, belly under the seat, a nose that thins out toward the bars.
  c.rect(x - 7, y - 1, 3, 1, SADDLE);
  c.rect(x - 6, y, 15, 1, SADDLE);
  c.rect(x - 5, y + 1, 8, 1, SADDLE);
  // The light on its top line, and the tail's pale patch, which no short or tube has.
  c.line(x + 3, y, x + 8, y, SADDLE_LIT);
  c.rect(x - 7, y - 1, 2, 1, SADDLE_TAIL);
  c.px(x - 6, y, SADDLE_TAIL);
}

function drawBike(c, look) {
  const tube = TUBES[look.tube];
  const shade = flat(tube);
  const cluster = [31, 50];
  const headTop = [55, 49];
  const headBottom = [57, 54];
  const crown = [57.5, 56];
  // The whip flag's staff bracket on the rear axle: the view plants the pennant on its tip.
  c.line(R.REAR_HUB[0], R.REAR_HUB[1] - 2, R.PENNANT_FOOT[0], R.PENNANT_FOOT[1], METAL[0]);
  // Stays, thin; then the main triangle: an open one, the top tube two pixels. The slot's colour is only a
  // muted band high on the down tube, a long way from warm: the crank stays the one warm mark down there.
  const band = look.sleeveRamp.map((u, i) => mix(u, tube[i], 0.72));
  capsule(c, R.REAR_HUB, cluster, 0.6, 0.6, flat([tube[0], tube[0], tube[1]]));
  capsule(c, R.REAR_HUB, R.BB, 0.8, 0.8, flat([tube[0], tube[0], tube[1]]));
  capsule(c, R.BB, cluster, 1.0, 0.9, shade);
  tube2(c, cluster, headTop, tube);
  capsule(c, R.BB, headBottom, 1.4, 1.2, (s, t) => (t > 0.66 && t < 0.86 ? pick(band, s) : pick(tube, s)));
  // The bottle in its cage over the down tube.
  capsule(c, [43, 60], [47, 57], 1.4, 1.4, (s) => (s > 0.3 ? hex('#c4c8d4') : s < -0.3 ? hex('#5c606c') : hex('#8e929e')));
  c.px(48, 56, METAL[0]);
  // Head tube, fork with a curve to the dropout, a brake at the crown.
  capsule(c, headTop, headBottom, 1.3, 1.3, (s) => pick(tube, s + 0.3));
  c.line(headBottom[0], headBottom[1], crown[0], crown[1], tube[1]);
  const fork = [crown, [58.2, 60], [59.2, 63.5], R.FRONT_HUB];
  for (let i = 0; i + 1 < fork.length; i++) capsule(c, fork[i], fork[i + 1], 1.0, 0.8, shade);
  c.px(56, 56, METAL[2]);
  c.px(R.FRONT_HUB[0], R.FRONT_HUB[1], METAL[2]);
  // The seat post, a bright line between the saddle and the top tube.
  c.line(cluster[0], cluster[1], R.SADDLE[0] + 1, R.SADDLE[1] + 2, METAL[2]);
  c.px(cluster[0] - 1, cluster[1] + 1, METAL[2]);
  drawSaddle(c);
  // Spacers and stem.
  c.rect(headTop[0] - 1, headTop[1] - 3, 2, 3, METAL[0]);
  c.line(headTop[0], headTop[1] - 3, R.BARS[0] + 1, R.BARS[1], METAL[1]);
  // Drop bars in wrapped tape: tops, hood, the hook down and back. A brake lever in front.
  const bar = [
    [R.BARS[0], R.BARS[1]],
    [R.HOODS[0], R.HOODS[1] + 1],
    [R.HOODS[0] + 2, R.HOODS[1] + 3],
    [R.HOODS[0] + 2, R.HOODS[1] + 6],
    [R.HOODS[0], R.HOODS[1] + 8],
    [R.HOODS[0] - 3, R.HOODS[1] + 8],
  ];
  for (let i = 0; i + 1 < bar.length; i++) {
    const a = bar[i];
    const b = bar[i + 1];
    const n = Math.max(Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]), 1);
    for (let k = 0; k <= n; k++) {
      const x = Math.round(a[0] + ((b[0] - a[0]) * k) / n);
      const y = Math.round(a[1] + ((b[1] - a[1]) * k) / n);
      c.px(x, y, (x + y) % 3 === 0 ? TAPE[2] : TAPE[1]);
    }
  }
  c.line(R.HOODS[0] + 1, R.HOODS[1] + 1, R.HOODS[0], R.HOODS[1] + 5, METAL[2]);
  c.rect(R.HOODS[0], R.HOODS[1], 2, 2, TAPE[0]);
}

/** The torso, spine t 0 at the hip to 1 at the shoulder, u across it (u > 0 is the back): the pattern lives in (t, u). */
function drawTorso(c, p, look, mask) {
  const [hx, hy] = p.hip;
  const [sx, sy] = p.shoulder;
  // The back arches: a mid point pushed away from the bars.
  const mid = [hx + (sx - hx) * 0.5 - 1.2, hy + (sy - hy) * 0.5 - 1.2];
  const spine = Math.hypot(sx - hx, sy - hy);
  const lighter = mix(look.color, [255, 255, 255], 0.66);
  const darker = mix(look.color, [48, 28, 40], 0.62);
  const paintAt = (t0, t1) => (s, t, u) => {
    const tt = t0 + (t1 - t0) * t;
    if (tt < 0.08) return pick(SHORTS, s);
    const shoulder = tt > 0.8;
    const ramp = shoulder ? look.sleeveRamp : look.bodyRamp;
    let col = pick(ramp, s);
    const px = Math.round(tt * spine);
    const across = Math.round(u);
    // The side panel under the arm stays in shade, so the waist narrows and the torso turns; the hem of the
    // rear pockets sits low on the back.
    if (!shoulder && across <= -3) col = ramp[0];
    if (!shoulder && px === 4 && across >= 0) col = ramp[0];
    if (!shoulder && px < 4 && across === 2) col = ramp[0];
    if (shoulder) return col;
    const mark = look.hollow ? look.sleeveRamp[1] : null;
    if (look.pattern === 'dashed') {
      // Long light breaks along the back, two rows deep.
      if ((across === 1 || across === 2) && px > 5 && px % 6 < 3) return mark ?? lighter;
    } else if (look.pattern === 'dotted') {
      // Two-pixel dots on a staggered grid.
      const row = Math.floor(px / 3);
      if (px % 3 < 2 && (((across + row * 2) % 4) + 4) % 4 < 2 && px > 4) return mark ?? darker;
    } else if (look.pattern === 'double') {
      // Two chest bands across the spine, three pixels each.
      if ((px >= 7 && px <= 9) || (px >= 12 && px <= 14)) return mark ?? lighter;
    }
    return col;
  };
  capsule(c, p.hip, mid, 4.0, 4.5, paintAt(0, 0.5), mask, true, TAG_TORSO);
  capsule(c, mid, p.shoulder, 4.5, 3.8, paintAt(0.5, 1), mask, true, TAG_TORSO);
  // Two long folds pulled from the waist toward the shoulder blade, each with a lit edge above it.
  const along = [(sx - hx) / spine, (sy - hy) / spine];
  const back = [along[1], -along[0]];
  const at = (t, u) => [hx + along[0] * spine * t + back[0] * u, hy + along[1] * spine * t + back[1] * u];
  const stroke = (a, b, col) => {
    const n = Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]));
    for (let k = 0; k <= n; k++) {
      const x = Math.round(a[0] + ((b[0] - a[0]) * k) / n);
      const y = Math.round(a[1] + ((b[1] - a[1]) * k) / n);
      if (mask[y * c.w + x] === TAG_TORSO) c.px(x, y, col);
    }
  };
  for (const [t0, u0, t1, u1] of [
    [0.26, -2.6, 0.5, 0.8],
    [0.46, -2.8, 0.7, 0.2],
  ]) {
    if (look.pattern === 'solid') stroke(at(t0 + 0.05, u0), at(t1 + 0.05, u1), look.bodyRamp[2]);
    stroke(at(t0, u0), at(t1, u1), look.bodyRamp[0]);
  }
  // The collar, and the jersey's zip line down the chest.
  c.px(sx + 2, sy - 1, look.sleeveRamp[0]);
  c.px(sx - 1, sy - 3, look.sleeveRamp[2]);
}

function drawHead(c, p, look, name, mask) {
  const [hx, hy] = p.head;
  const skin = look.skinRamp;
  const down = name === 'situp' ? 1 : 0;
  const shoulder = p.shoulder;
  // The neck, in the head's shadow.
  capsule(c, [shoulder[0] + 1, shoulder[1] - 2], [hx - 1, hy + 2], 1.7, 1.6, (s) => (s < -0.2 ? skin[0] : skin[1]), mask);
  // The face in profile, looking along the road: one flat plane, the shade only down the back of the
  // jaw, the light only on the cheekbone. A nose and a chin, and nothing else on the skin.
  capsule(c, [hx, hy], [hx, hy + 1], 3.3, 3.0, (s, t, u) => (u > 1.6 ? skin[0] : skin[1]), mask);
  c.px(hx + 4, hy + 1 + down, skin[1]);
  c.px(hx + 3, hy + 3 + down, skin[1]);
  c.px(hx + 2, hy + 3 + down, skin[1]);
  c.px(hx + 2, hy + 1 + down, skin[2]);
  // Glasses: a dark band with a glint on the lens.
  c.rect(hx + 1, hy + down - 1, 3, 2, OUTLINE);
  c.px(hx + 3, hy + down - 1, hex('#6a7890'));
  c.px(hx, hy + down - 1, OUTLINE);
  // The helmet: longer than the head, tail low behind, a peak in front, three vents.
  const helmet = look.helmetRamp;
  const cx = hx - 1;
  const cy = hy - 2 + down;
  for (let j = -5; j <= 3; j++) {
    for (let i = -7; i <= 6; i++) {
      const e = (i * i) / 40 + (j * j) / 13;
      if (e > 1) continue;
      const x = cx + i;
      const y = cy + j;
      // Cut away below the brim, which falls toward the tail.
      if (j > 0.6 - i * 0.36) continue;
      const s = (i * LIGHT[0]) / 6 + (j * LIGHT[1]) / 3.6;
      c.px(x, y, s > 0.4 ? helmet[2] : s < -0.2 ? helmet[0] : helmet[1]);
      // The tail stays clear of the outline, so it does not fatten the helmet's back.
      if (i > -6) mask[y * c.w + x] = 1;
    }
  }
  const vent = look.hollow ? hex('#14161c') : mix(WHITE, COOL, 0.65);
  c.px(cx - 3, cy - 1, vent);
  c.px(cx - 2, cy - 1, vent);
  c.px(cx, cy - 2, vent);
  c.px(cx + 1, cy - 2, vent);
  c.px(cx + 3, cy - 1, vent);
}

/** Dark pixels on the side away from the light, on empty pixels only: lifts the rider off the world. */
function outlinePass(c, mask) {
  const w = c.w;
  const out = [];
  for (let y = 0; y < c.h; y++) {
    for (let x = 0; x < w; x++) {
      if (c.get(x, y)[3] !== 0) continue;
      const right = x + 1 < w && mask[y * w + x + 1];
      const above = y > 0 && mask[(y - 1) * w + x];
      if (right || above) out.push([x, y]);
    }
  }
  for (const [x, y] of out) c.px(x, y, OUTLINE);
}

/** The bike's shadow on the road, under the contact row: one soft row, a shorter one below it. */
function drawGroundShadow(c) {
  const dark = [14, 16, 26, 120];
  for (let x = 8; x <= 72; x++) c.px(x, 80, dark);
  for (let x = 16; x <= 64; x += 1) if (x % 2 === 0) c.px(x, 81, [14, 16, 26, 90]);
}

/** One rider frame as an 88 x 84 Canvas: everything but the wheels. */
export function riderFrame(slot, name, k) {
  const c = new Canvas(R.CELL[0], R.CELL[1]);
  const mask = new Uint8Array(c.w * c.h);
  const look = slotLook(slot);
  const p = R.pose(name, k);
  drawGroundShadow(c);
  drawArm(c, p, look, true, mask);
  drawLeg(c, p.far, look, true, mask);
  drawFarCrank(c, p.farPedal);
  const farPixels = c.data.slice();
  drawBike(c, look);
  drawDrivetrain(c, p.frame);
  drawTorso(c, p, look, mask);
  const torsoPixels = c.data.slice();
  drawCrankArm(c, p.nearPedal);
  drawLeg(c, p.near, look, false, mask);
  crease(c, mask, TAG_NEAR_LEG, TAG_FAR, farPixels, CREASE);
  drawPedal(c, p.nearPedal);
  drawArm(c, p, look, false, mask);
  crease(c, mask, TAG_NEAR_ARM, TAG_FAR, farPixels, CREASE);
  crease(c, mask, TAG_NEAR_ARM, TAG_TORSO, torsoPixels, look.bodyRamp[0]);
  drawHead(c, p, look, name, mask);
  outlinePass(c, mask);
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

/**
 * 27 x 27 x 16: one full turn, 6 spokes (60 deg period at 22.5 deg per frame reads forward), a deep-section
 * rim with a light that stays put, one valve dot and a rim decal that turn with the wheel.
 */
export function wheelSheet() {
  const sheet = new Canvas(WHEEL_CELL * WHEEL_FRAMES, WHEEL_CELL);
  const tyre = hex('#17181c');
  const tread = hex('#34363e');
  const rim = [hex('#30333b'), hex('#555a64'), hex('#b4bac4')];
  const spoke = hex('#8a909a');
  const hub = hex('#50545c');
  const valve = hex('#e8e8e0');
  const decal = hex('#d8dce4');
  const mid = 13;
  for (let f = 0; f < WHEEL_FRAMES; f++) {
    const c = new Canvas(WHEEL_CELL, WHEEL_CELL);
    const a0 = (f * 22.5 * Math.PI) / 180;
    for (let s = 0; s < 6; s++) {
      const a = a0 + (s * Math.PI) / 3;
      c.line(mid + 2 * Math.cos(a), mid + 2 * Math.sin(a), mid + 9 * Math.cos(a), mid + 9 * Math.sin(a), spoke);
    }
    for (let j = -14; j <= 14; j++) {
      for (let i = -14; i <= 14; i++) {
        const d = Math.hypot(i, j);
        if (d >= R.WHEEL_R + 0.5) continue;
        const s = (i * LIGHT[0] + j * LIGHT[1]) / Math.max(d, 1);
        if (d >= R.WHEEL_R - 1.5) {
          c.px(mid + i, mid + j, d >= R.WHEEL_R - 0.5 && s > 0.55 ? tread : tyre);
        } else if (d >= R.WHEEL_R - 3.5) {
          let col = s > 0.5 ? rim[2] : s < -0.2 ? rim[0] : rim[1];
          // The decal: a short bright arc that turns, so the eye has something to follow.
          const a = ((Math.atan2(j, i) - a0) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
          if (a < 0.5 && d < R.WHEEL_R - 2) col = decal;
          c.px(mid + i, mid + j, col);
        }
      }
    }
    c.disk(mid, mid, 1, hub);
    c.px(mid, mid, rim[2]);
    c.px(mid + 10 * Math.cos(a0 + Math.PI / 6), mid + 10 * Math.sin(a0 + Math.PI / 6), valve);
    sheet.blit(c, f * WHEEL_CELL, 0);
  }
  return sheet;
}

// Hand-placed little pictures: one character per pixel. Dust: X dense, x thin; bubbles: see below.
// Breath: the view trails a puff back by about 2 px a frame, so each frame sits further along its cell and
// the cloud hangs just ahead of the face, thinning out, never over it.
const BREATH_FRAMES = [
  ['........', '........', '.X......', '.Xx.....', '........', '........'],
  ['........', '...x....', '..XXx...', '..XXx...', '...x....', '........'],
  ['....x...', '...xXx..', '...XXxx.', '...xxx..', '....x...', '........'],
  ['......x.', '....x...', '.....x.x', '......x.', '....x...', '........'],
];
// Dust leaves the road: each frame sits higher and further back in its cell, and breaks up on the way.
const DUST_FRAMES = [
  ['..........', '..........', '..........', '......x...', '.....xXx..', '......xx..'],
  ['..........', '..........', '...x.xx...', '....xXXx..', '...xXXx...', '.....x....'],
  ['..x.......', '.x..x.....', '...xX.x...', '.x..xx....', '....x.....', '..........'],
  ['x.........', '...x......', '.x........', '....x.....', '..........', '..........'],
];
const BUBBLES = {
  // Orange plate, a white chevron that lifts: the rider is being eased back up.
  rescue: [
    ['.#######.', '#ooooooo#', '#oooWooo#', '#ooWWWoo#', '#oWWoWWo#', '#oWoooWo#', '#ooooooo#', '.#######.', '....#....'],
    ['.#######.', '#oooWooo#', '#ooWWWoo#', '#oWWoWWo#', '#oWoooWo#', '#ooooooo#', '#ooooooo#', '.#######.', '....#....'],
  ],
  // White plate, one big dark Z that bobs: asleep.
  afk: [
    ['.#######.', '#wwwwwww#', '#w#####w#', '#wwww##w#', '#www##ww#', '#ww##www#', '#w#####w#', '.#######.', '....#....'],
    ['.#######.', '#w#####w#', '#wwww##w#', '#www##ww#', '#ww##www#', '#w#####w#', '#wwwwwww#', '.#######.', '....#....'],
  ],
  // A pale plate and two dark chain links with clear air between them; a red spark blinks in the gap: broken.
  link: [
    ['.-------.', '-ggggggg-', '-###g###-', '-#g#g#g#-', '-#g#g#g#-', '-###g###-', '-ggggggg-', '.-------.', '....-....'],
    ['.-------.', '-ggggggg-', '-###g###-', '-#g#r#g#-', '-#g#r#g#-', '-###g###-', '-ggggggg-', '.-------.', '....-....'],
  ],
};

function picture(sheet, ox, oy, rows, colours) {
  rows.forEach((row, j) => {
    [...row].forEach((ch, i) => {
      if (colours[ch]) sheet.px(ox + i, oy + j, colours[ch]);
    });
  });
}

// Layout agrees with kit.fx: breath [0, 0, 8, 6, 4], dust [0, 6, 10, 6, 4], then the 9 x 9 bubbles.
export function fxSheet() {
  const sheet = new Canvas(FX_SIZE[0], FX_SIZE[1]);
  const breathColours = { X: [238, 242, 250, 170], x: [214, 220, 234, 95] };
  // Pale and airy: a puff that hangs over the road, never a chip of grit on it.
  const dustColours = { X: [232, 224, 206, 165], x: [220, 212, 196, 90] };
  for (let f = 0; f < 4; f++) {
    picture(sheet, f * 8, 0, BREATH_FRAMES[f], breathColours);
    picture(sheet, f * 10, 6, DUST_FRAMES[f], dustColours);
  }
  const colours = {
    '#': hex('#14161c'),
    '-': hex('#62666f'),
    o: hex('#e0642e'),
    W: hex('#fff8ec'),
    w: hex('#f2f4fa'),
    g: hex('#ccd8e8'),
    r: hex('#d8342c'),
  };
  for (const [name, x] of [
    ['rescue', 0],
    ['afk', 18],
    ['link', 36],
  ]) {
    BUBBLES[name].forEach((rows, f) => picture(sheet, x + f * 9, 12, rows, colours));
  }
  return sheet;
}
