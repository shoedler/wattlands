// Rider sheets, the wheel and the small rider effects. True colour: the view tints them by time of day.
//
// Rider sheet addressing (kit.json, WorkoutKit): row = pose_rows[pose] + frame / 6, col = frame % 6,
// source rect (col * 88, row * 84, 88, 84). The stop pose ignores the frame (row 12, col 0).
//
// Paint order in a frame: far arm, far leg, far crank and pedal, chain and chainring, rear cog and
// derailleur, frame tubes, fork, saddle, bars, torso, near leg, near crank and pedal, near arm, head,
// helmet. Wheels are their own sprites, drawn before the frame, so the fork and stays sit over them.
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
const SADDLE = hex('#17181c');
/** The pedal's own colour: tests find the pedal by it. */
export const PEDAL = [216, 220, 228];
export const WHEEL_FRAMES = 16;
export const WHEEL_CELL = 27;
export const FX_SIZE = [54, 21];

const LIGHT = [0.42, -0.91];
const COOL = [34, 30, 74];
const WARM = [255, 240, 200];

const clamp = (u, lo, hi) => Math.min(Math.max(u, lo), hi);

/** A three-shade ramp around a colour: shadows lean violet, lights lean warm. */
const rampOf = (c, dark = 0.42, light = 0.38) => [mix(c, COOL, dark), c, mix(c, WARM, light)];
/** The same ramp in the far side's shade (the far limbs sit two steps back). */
const farOf = (ramp) => ramp.map((c) => mix(c, COOL, 0.42));

const SHORTS = [hex('#0d0e13'), hex('#1a1b20'), hex('#44464f')];
const SOCK = rampOf(WHITE, 0.3, 0);
const SHOE = [hex('#14151b'), hex('#2c2e38'), hex('#7c8090')];
const GLOVE = [hex('#101116'), hex('#22242b'), hex('#3a3c44')];
const TUBES = {
  graphite: [hex('#1f2128'), hex('#3a3d44'), hex('#767b88')],
  steel: [hex('#566070'), hex('#8a95a0'), hex('#d0d8e0')],
};
const METAL = [hex('#34373f'), hex('#5a5e68'), hex('#a4a8b2')];
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
    skinRamp: rampOf(hex(SKIN[base]), 0.34, 0.3),
    helmetRamp: rampOf(hollow ? color : WHITE, hollow ? 0.42 : 0.34, hollow ? 0.45 : 0),
  };
}

/**
 * Paints a capsule from a to b, radius ra to rb. `paint(s, t, u)` gets the shading value s (-1..1 toward
 * the light), the position along the bone t (0..1) and the signed distance off it u, and returns a colour
 * or null. `mask` marks the rider's body pixels for the outline pass.
 */
function capsule(c, a, b, ra, rb, paint, mask = null, across = false) {
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
      if (mask && x >= 0 && y >= 0 && x < c.w && y < c.h) mask[y * c.w + x] = 1;
    }
  }
}

const flat = (ramp) => (s) => pick(ramp, s);

function drawArm(c, p, look, far, mask) {
  const sleeve = far ? farOf(look.sleeveRamp) : look.sleeveRamp;
  const skin = far ? farOf(look.skinRamp) : look.skinRamp;
  const gx = far ? 2 : 0;
  const shoulder = [p.shoulder[0] + gx, p.shoulder[1] + (far ? 1 : 0)];
  const elbow = [p.elbow[0] + gx, p.elbow[1]];
  const hand = [p.hands[0] + (far ? 1 : 0), p.hands[1]];
  capsule(c, shoulder, elbow, 2.7, 1.8, (s, t) => (t < 0.72 ? pick(sleeve, s) : pick(skin, s)), mask);
  capsule(c, elbow, hand, 1.7, 1.2, flat(skin), mask);
  if (!far) {
    // Fingerless glove on the hood, the thumb a lighter pixel.
    c.rect(hand[0] - 1, hand[1] - 1, 3, 2, GLOVE[1]);
    c.px(hand[0] + 1, hand[1] - 1, GLOVE[2]);
    c.px(hand[0] - 1, hand[1], skin[1]);
  }
}

/** The shoe under the ankle: heel, sole on the pedal, toe past it. */
function drawShoe(c, l, far, mask) {
  const k = far ? farOf(SHOE) : SHOE;
  const ax = l.ankle[0];
  const ay = l.ankle[1];
  const dirx = l.pedal[0] - ax;
  // The foot points forward of the ankle-to-pedal line, tipping with the ankle swing.
  const tilt = clamp(dirx * 0.22, -0.5, 0.5);
  const heel = [ax - 2.2, ay + 1.4];
  const toe = [l.pedal[0] + 3.4, l.pedal[1] - 1.2 + tilt];
  capsule(c, heel, toe, 1.5, 1.05, (s) => (s < -0.5 ? k[0] : s > 0.5 ? k[2] : k[1]), mask);
  // The dark sole.
  c.line(heel[0], heel[1] + 1, toe[0], toe[1] + 1, k[0]);
}

function drawLeg(c, l, look, far, mask) {
  const skin = far ? farOf(look.skinRamp) : look.skinRamp;
  const shorts = far ? farOf(SHORTS) : SHORTS;
  const sock = far ? farOf(SOCK) : SOCK;
  // The calf bulges behind the shin, a third of the way down: two capsules with different radii.
  const calf = [l.knee[0] + (l.ankle[0] - l.knee[0]) * 0.36 - 0.5, l.knee[1] + (l.ankle[1] - l.knee[1]) * 0.36];
  capsule(c, l.knee, calf, 2.1, 2.4, flat(skin), mask);
  capsule(c, calf, l.ankle, 2.4, 1.2, (s, t) => (t > 0.66 ? pick(sock, s) : pick(skin, s)), mask);
  capsule(c, l.hip, l.knee, 3.6, 2.5, (s, t) => (t < 0.8 ? pick(shorts, s) : pick(skin, s)), mask);
  drawShoe(c, l, far, mask);
  if (!far) {
    // The kneecap catches the light, the short's hem a dark line.
    c.px(l.knee[0] + 1, l.knee[1] - 1, look.skinRamp[2]);
  }
}

function drawCrank(c, pedal, far) {
  const metal = far ? farOf(METAL) : METAL;
  capsule(c, R.BB, pedal, 1.3, 1.0, flat(metal));
  const x = Math.round(pedal[0]);
  const y = Math.round(pedal[1]);
  c.rect(x - 2, y, 4, 1, far ? mix(PEDAL, COOL, 0.45) : PEDAL);
  c.rect(x - 1, y + 1, 2, 1, metal[0]);
}

/** Both chain runs, the chainring with its turning teeth and spider, the cog, the derailleur. */
function drawDrivetrain(c, frame) {
  const off = R.chainOffset(frame);
  const [hx, hy] = R.REAR_HUB;
  const [bx, by] = R.BB;
  const CHAIN_DARK = hex('#22242a');
  const CHAIN_LIGHT = hex('#a0a4ac');
  const m = R.CHAIN_PERIOD;
  const theta = R.crankTheta(frame);
  const topStart = [hx, hy - R.COG_R - 1];
  const topEnd = [bx, by - R.CHAINRING_R - 1];
  const jockey0 = [hx + 2, hy + 5];
  const jockey1 = [hx + 4, hy + 9];
  const botEnd = [bx, by + R.CHAINRING_R + 1];
  // Top run moves toward the chainring, bottom run away from it, 2 dark then 2 light.
  for (let x = topStart[0]; x <= topEnd[0]; x++) {
    const t = (x - topStart[0]) / (topEnd[0] - topStart[0]);
    const y = Math.round(topStart[1] + (topEnd[1] - topStart[1]) * t);
    c.px(x, y, ((x - off + 4 * m) % m) < 2 ? CHAIN_DARK : CHAIN_LIGHT);
  }
  for (let x = jockey1[0]; x <= botEnd[0]; x++) {
    const t = (x - jockey1[0]) / (botEnd[0] - jockey1[0]);
    const y = Math.round(jockey1[1] + 1 + (botEnd[1] - jockey1[1] - 1) * t);
    c.px(x, y, ((x + off + 4 * m) % m) < 2 ? CHAIN_DARK : CHAIN_LIGHT);
  }
  // The chainring: a toothed rim that turns with the crank, four spider arms inside it.
  for (let j = -R.CHAINRING_R - 1; j <= R.CHAINRING_R + 1; j++) {
    for (let i = -R.CHAINRING_R - 1; i <= R.CHAINRING_R + 1; i++) {
      const d = Math.hypot(i, j);
      if (d < R.CHAINRING_R - 0.5 || d >= R.CHAINRING_R + 0.5) continue;
      const a = Math.atan2(j, i) - theta;
      const tooth = Math.floor(((a + Math.PI * 4) / (Math.PI * 2)) * 16) % 2 === 0;
      c.px(bx + i, by + j, tooth ? METAL[2] : METAL[0]);
    }
  }
  for (let a = 0; a < 4; a++) {
    const q = theta + (a * Math.PI) / 2 + Math.PI / 4;
    c.line(bx, by, bx + 3.4 * Math.cos(q), by + 3.4 * Math.sin(q), METAL[1]);
  }
  c.px(bx, by, METAL[0]);
  // Rear cog: one dark tooth turns COG_TURNS times per crank revolution.
  c.ring(hx, hy, R.COG_R, METAL[1]);
  c.px(hx, hy, METAL[2]);
  const cog = theta * R.COG_TURNS;
  c.px(hx + R.COG_R * Math.cos(cog), hy + R.COG_R * Math.sin(cog), CHAIN_DARK);
  // Derailleur: hanger, cage, two jockey wheels whose dark pixel flips every 3 frames.
  const flip = Math.floor(frame / 3) % 2;
  c.line(hx, hy + 1, jockey0[0], jockey0[1], METAL[1]);
  c.line(jockey0[0], jockey0[1], jockey1[0], jockey1[1], METAL[0]);
  for (const [i, jw] of [jockey0, jockey1].entries()) {
    c.rect(jw[0] - 1, jw[1] - 1, 2, 2, METAL[1]);
    c.px(jw[0] - 1 + ((flip + i) % 2), jw[1] - 1, CHAIN_DARK);
    c.px(jw[0] - ((flip + i) % 2), jw[1], METAL[2]);
  }
}

function drawBike(c, look) {
  const tube = TUBES[look.tube];
  const shade = flat(tube);
  const cluster = [31, 47];
  const headTop = [55, 47];
  const headBottom = [57, 53];
  const crown = [57.5, 55];
  // The whip flag's staff bracket on the rear axle: the view plants the pennant on its tip.
  c.line(R.REAR_HUB[0], R.REAR_HUB[1] - 2, R.PENNANT_FOOT[0], R.PENNANT_FOOT[1], METAL[0]);
  // Stays, thin; then the main triangle, thicker, with a slot-colour band on the seat tube.
  capsule(c, R.REAR_HUB, cluster, 0.7, 0.7, flat([tube[0], tube[0], tube[1]]));
  capsule(c, R.REAR_HUB, R.BB, 0.8, 0.8, flat([tube[0], tube[0], tube[1]]));
  capsule(c, R.BB, cluster, 1.2, 1.1, shade);
  capsule(c, cluster, headTop, 0.95, 1.1, shade);
  capsule(c, R.BB, headBottom, 1.4, 1.2, (s, t) => (t > 0.62 && t < 0.86 ? pick(look.sleeveRamp, s) : pick(tube, s)));
  // The bottle in its cage on the down tube.
  capsule(c, [43, 60], [46, 58], 1.3, 1.3, (s) => (s > 0.3 ? hex('#b4b8c4') : s < -0.3 ? hex('#5c606c') : hex('#8a8e9a')));
  c.px(47, 57, METAL[0]);
  // Head tube, spacers, fork with a curve to the dropout, a brake at the crown.
  capsule(c, headTop, headBottom, 1.3, 1.3, (s) => pick(tube, s + 0.3));
  c.line(headBottom[0], headBottom[1], crown[0], crown[1], tube[1]);
  const fork = [crown, [58.2, 60], [59.2, 63.5], R.FRONT_HUB];
  for (let i = 0; i + 1 < fork.length; i++) capsule(c, fork[i], fork[i + 1], 1.0, 0.8, shade);
  c.px(56, 55, METAL[2]);
  c.px(R.FRONT_HUB[0], R.FRONT_HUB[1], METAL[2]);
  c.px(cluster[0] - 2, cluster[1] + 3, METAL[2]);
  // Seat post and a saddle with a nose and a kicked-up tail.
  c.line(cluster[0], cluster[1], R.SADDLE[0] + 1, R.SADDLE[1] + 1, METAL[1]);
  c.rect(R.SADDLE[0] - 4, R.SADDLE[1], 11, 1, SADDLE);
  c.rect(R.SADDLE[0] - 5, R.SADDLE[1] - 1, 6, 1, SADDLE);
  c.rect(R.SADDLE[0] - 2, R.SADDLE[1] + 1, 5, 1, SADDLE);
  c.px(R.SADDLE[0] - 5, R.SADDLE[1] - 1, hex('#3a3c44'));
  // Stem and spacers.
  c.rect(headTop[0] - 1, headTop[1] - 2, 2, 2, METAL[0]);
  c.line(headTop[0], headTop[1] - 2, R.BARS[0] + 1, R.BARS[1], METAL[1]);
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

/** The torso, spine t 0 at the hip to 1 at the shoulder, u across it: the pattern lives in (t, u). */
function drawTorso(c, p, look, mask) {
  const [hx, hy] = p.hip;
  const [sx, sy] = p.shoulder;
  // The back arches: a mid point pushed away from the bars.
  const mid = [hx + (sx - hx) * 0.5 - 1.2, hy + (sy - hy) * 0.5 - 1.2];
  const spine = Math.hypot(sx - hx, sy - hy);
  const paintAt = (t0, t1) => (s, t, u) => {
    const tt = t0 + (t1 - t0) * t;
    if (tt < 0.08) return pick(SHORTS, s);
    const shoulder = tt > 0.8;
    let ramp = shoulder ? look.sleeveRamp : look.bodyRamp;
    let col = pick(ramp, s);
    const px = Math.round(tt * spine);
    const across = Math.round(u);
    // Folds at the waist and under the shoulder blade: short dark creases.
    if (!shoulder && ((px === 3 && across > -3 && across < 0) || (px === 6 && across > -3 && across < -1))) col = ramp[0];
    if (shoulder || look.pattern === 'solid') return col;
    const mark = look.hollow ? look.sleeveRamp[1] : null;
    if (look.pattern === 'dashed') {
      // 2 x 1 light breaks along the back.
      if (across === 2 && px % 5 < 2) return mark ?? look.sleeveRamp[2];
    } else if (look.pattern === 'dotted') {
      // 1 px dots on a staggered grid.
      if ((px + (((across % 2) + 2) % 2) * 2) % 4 === 0 && ((across % 2) + 2) % 2 === 0) return look.sleeveRamp[0];
    } else if (look.pattern === 'double') {
      // Two chest bands across the spine.
      if (px === 10 || px === 11 || px === 15 || px === 16) return mark ?? look.sleeveRamp[0];
    }
    return col;
  };
  capsule(c, p.hip, mid, 4.0, 4.5, paintAt(0, 0.5), mask, true);
  capsule(c, mid, p.shoulder, 4.5, 3.8, paintAt(0.5, 1), mask, true);
  // The collar, and the jersey's zip line down the chest.
  c.px(sx + 2, sy - 1, look.sleeveRamp[0]);
  c.px(sx - 1, sy - 3, look.sleeveRamp[2]);
}

function drawHead(c, p, look, name, mask) {
  const [hx, hy] = p.head;
  const skin = look.skinRamp;
  const down = name === 'situp' ? 1 : 0;
  const shoulder = p.shoulder;
  capsule(c, [shoulder[0] + 1, shoulder[1] - 2], [hx - 1, hy + 2], 1.7, 1.6, flat(skin), mask);
  // The face in profile, looking along the road, with a nose and a chin.
  capsule(c, [hx, hy], [hx, hy + 1], 3.3, 3.0, flat(skin), mask);
  c.px(hx + 4, hy + 1 + down, skin[1]);
  c.px(hx + 3, hy + 3 + down, skin[0]);
  c.px(hx + 2, hy + 3 + down, skin[1]);
  c.px(hx - 2, hy + 1, skin[0]);
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
  // The strap, from under the helmet down the cheek to the jaw.
  c.px(hx - 1, hy + 1 + down, skin[0]);
  c.px(hx, hy + 2 + down, OUTLINE);
  c.px(hx + 1, hy + 3 + down, skin[0]);
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
  drawCrank(c, p.farPedal, true);
  drawDrivetrain(c, p.frame);
  drawBike(c, look);
  drawTorso(c, p, look, mask);
  drawLeg(c, p.near, look, false, mask);
  drawCrank(c, p.nearPedal, false);
  drawArm(c, p, look, false, mask);
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

// Layout agrees with kit.fx: breath [0, 0, 8, 6, 4], dust [0, 6, 10, 6, 4], then the 9 x 9 bubbles.
export function fxSheet() {
  const sheet = new Canvas(FX_SIZE[0], FX_SIZE[1]);
  const breath = [238, 242, 250];
  const dust = [176, 156, 124];
  const breathDim = mix(breath, COOL, 0.3);
  const dustDim = mix(dust, COOL, 0.25);
  for (let f = 0; f < 4; f++) {
    // A puff that grows, then breaks apart.
    const bx = f * 8 + 3;
    const dx = f * 10 + 4;
    if (f < 3) {
      sheet.disk(bx, 3, 0.6 + f * 0.55, f === 2 ? breathDim : breath);
      sheet.disk(dx, 9, 0.7 + f * 0.65, f === 2 ? dustDim : dust);
      sheet.px(bx + 1, 2, breath);
      sheet.px(dx + 1, 8, dust);
    } else {
      for (const [i, j] of [
        [-2, -1],
        [1, -2],
        [2, 1],
        [-1, 2],
        [0, 0],
      ]) {
        sheet.px(bx + i, 3 + j, breathDim);
        sheet.px(dx + i + (i > 0 ? 1 : 0), 9 + j, dustDim);
      }
    }
  }
  const white = hex('#f6f6f0');
  const shade = hex('#c8ccd8');
  const dark = hex('#14161c');
  const bubble = (x, f) => {
    const ox = x + f * 9;
    sheet.rect(ox + 1, 12, 7, 8, dark);
    sheet.rect(ox, 13, 9, 6, dark);
    sheet.rect(ox + 1, 13, 7, 6, white);
    sheet.rect(ox + 1, 18, 7, 1, shade);
    sheet.px(ox + 4, 20, dark);
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
    sheet.rect(lx + 5 - (1 - f), 15, 2, 2, dark);
    sheet.px(lx + 3, 14 - f, orange);
  }
  return sheet;
}
