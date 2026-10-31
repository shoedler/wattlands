// The rider's geometry and its inverse kinematics: scale 40 px per metre, the bike faces right, y down.
// Everything a rider sheet draws comes from pose(); the crank contract below is shared with GDScript
// (WorkoutRig.CRANK_FRAMES) and with the HUD's crank icon, which uses only crankTheta().

export const CELL = [88, 84];
export const COLS = 6;
export const CRANK_FRAMES = 24;
export const ROWS = 13; // seat 4, stand 4, situp 4, stop 1
export const POSE_ROWS = { seat: 0, stand: 4, situp: 8, stop: 12 };
export const ORIGIN = [40, 79];
export const REAR_HUB = [20, 66];
export const FRONT_HUB = [60, 66];
export const WHEEL_R = 13;
export const TYRE_ROW = 79;
export const BB = [38, 69];
export const CRANK = 7;
export const CHAINRING_R = 6;
export const COG_R = 2;
export const SADDLE = [29, 44];
export const BARS = [54, 43];
export const HOODS = [59, 42];
export const THIGH = 17;
export const SHIN = 17;
export const ANKLE_TO_PEDAL = 4;
export const UPPER_ARM = 13;
export const FOREARM = 13;
export const HEAD_R = 4;
export const PENNANT_FOOT = [15, 54];
// Over the sat-up head (the pose a bubble comes with), clear of the next rider's pennant pole.
export const BUBBLE = [38, 2];
export const REAR_CONTACT = [20, 79];

/** Chain pattern: 2 dark, 2 light, moving exactly this many px per crank revolution. */
export const CHAIN_PERIOD = 4;
export const CHAIN_PX_PER_REV = 32;
/** A brass link comes round every this many px, so the eye can follow the chain. */
export const CHAIN_LINK_PERIOD = 16;
/** The rear cog turns this many times per crank revolution. */
export const COG_TURNS = 4;

const RAD = Math.PI / 180;

/** Crank angle of frame k, radians: -90 deg + k * 15 deg, clockwise on screen. Frame 0: near pedal up. */
export const crankTheta = (k) => (-90 + k * (360 / CRANK_FRAMES)) * RAD;

/** The near pedal at frame k, in sub-pixels. The far pedal is k + 12. */
export function pedalAt(k) {
  const a = crankTheta(k);
  return [BB[0] + CRANK * Math.cos(a), BB[1] + CRANK * Math.sin(a)];
}

/** kit.rider.near_pedal: whole pixels, one per frame. */
export const nearPedalTable = () =>
  Array.from({ length: CRANK_FRAMES }, (_, k) => pedalAt(k).map((u) => Math.round(u)));

/** Chain pattern offset at frame k, whole px. Frame CRANK_FRAMES gives 0 modulo the period. */
export const chainOffset = (k) => Math.round((k * CHAIN_PX_PER_REV) / CRANK_FRAMES) % CHAIN_PERIOD;

/** Chain travel at frame k, whole px: frame CRANK_FRAMES closes on 0 modulo CHAIN_LINK_PERIOD. */
export const chainTravel = (k) => Math.round((k * CHAIN_PX_PER_REV) / CRANK_FRAMES) % CHAIN_PX_PER_REV;

const POSES = {
  seat: { hip: [30, 40], shoulder: [45, 23], hands: [59, 42], head: [49, 17] },
  stand: { hip: [39, 39], shoulder: [58, 24], hands: [61, 41], head: [63, 18] },
  situp: { hip: [28, 40], shoulder: [36, 19], hands: [52, 40], head: [37, 12] },
  stop: { hip: [36, 44], shoulder: [47, 24], hands: [59, 42], head: [51, 18] },
};

/** Where a breath puff starts, per pose: just in front of the face, so it follows the head. */
const MOUTH_FROM_HEAD = [4, 2];
export const MOUTH_BY_POSE = Object.fromEntries(
  Object.entries(POSES).map(([name, p]) => [name, [p.head[0] + MOUTH_FROM_HEAD[0], p.head[1] + MOUTH_FROM_HEAD[1]]]),
);
export const MOUTH = MOUTH_BY_POSE.seat;

/** The stop pose's cranks: the far pedal forward, so the far foot rests level on it. */
export const STOP_FRAME = 18;
export const STOP_FOOT = [30, 79];

/**
 * Two-bone IK from `a` to `b`: returns the middle joint. `bendSign` +1 bends to the forward side of
 * a downward limb (a knee), -1 to the rear side (an elbow). Past full reach the limb lies straight.
 */
export function ik(a, b, l0, l1, bendSign) {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const d = Math.hypot(dx, dy);
  if (d < 1e-6) return [a[0], a[1]];
  const ux = dx / d;
  const uy = dy / d;
  if (d >= l0 + l1) return [a[0] + ux * l0 * (d / (l0 + l1)), a[1] + uy * l0 * (d / (l0 + l1))];
  const along = (l0 * l0 - l1 * l1 + d * d) / (2 * d);
  const out = Math.sqrt(Math.max(l0 * l0 - along * along, 0));
  return [a[0] + ux * along + uy * out * bendSign, a[1] + uy * along - ux * out * bendSign];
}

// The ankle stands up and slightly behind the pedal; it swings 12 degrees over the stroke ("ankling").
function ankleOver(pedal, theta) {
  const a = (-103 + 12 * Math.sin(theta + 30 * RAD)) * RAD;
  return [pedal[0] + ANKLE_TO_PEDAL * Math.cos(a), pedal[1] + ANKLE_TO_PEDAL * Math.sin(a)];
}

function leg(hip, pedal, theta) {
  const ankle = ankleOver(pedal, theta);
  return { hip, knee: ik(hip, ankle, THIGH, SHIN, 1), ankle, pedal };
}

/**
 * Every joint of `name` at crank frame k: {hip, shoulder, hands, head, elbow, near: {hip, knee, ankle,
 * pedal}, far: {...}, nearPedal, farPedal, frame}. Same k, same cranks in every pose but stop, so a
 * pose change never jumps the legs. Hips, shoulders and head sit on whole pixels.
 */
export function pose(name, k0) {
  const k = name === 'stop' ? STOP_FRAME : k0;
  const base = POSES[name];
  const theta = crankTheta(k);
  const nearPedal = pedalAt(k);
  const farPedal = pedalAt(k + CRANK_FRAMES / 2);
  let hipDy = 0;
  let shoulderDy = 0;
  if (name === 'seat' || name === 'situp') {
    // A 1 px hip roll twice a revolution; the shoulders follow two frames later.
    hipDy = Math.sin(2 * theta) > 0 ? 1 : 0;
    shoulderDy = Math.sin(2 * crankTheta(k - 2)) > 0 ? 1 : 0;
  } else if (name === 'stand') {
    hipDy = Math.round(2 * Math.sin(2 * theta));
    shoulderDy = Math.round(Math.sin(2 * crankTheta(k - 2)));
  }
  const hip = [base.hip[0], base.hip[1] + hipDy];
  const shoulder = [base.shoulder[0], base.shoulder[1] + shoulderDy];
  const head = [base.head[0], base.head[1] + shoulderDy];
  const far = leg(hip, farPedal, theta + Math.PI);
  const near =
    name === 'stop'
      ? { hip, knee: ik(hip, [STOP_FOOT[0], STOP_FOOT[1] - ANKLE_TO_PEDAL], THIGH, SHIN, 1), ankle: [STOP_FOOT[0], STOP_FOOT[1] - ANKLE_TO_PEDAL], pedal: STOP_FOOT }
      : leg(hip, nearPedal, theta);
  return {
    frame: k,
    hip,
    shoulder,
    head,
    hands: base.hands,
    elbow: ik(shoulder, base.hands, UPPER_ARM, FOREARM, -1),
    near,
    far,
    nearPedal,
    farPedal,
  };
}
