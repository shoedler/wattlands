// Tiny sprites: people about 5 px tall (the head is the one readable detail), chariots, palms.
// A sprite is {w, h, px: Array<[r,g,b] | null>}.
import { hex, rng, TAU } from './v3.mjs';

const PAL = {
  h: '#1e1a1a', s: '#8a5a3c', S: '#a87452', w: '#e6ddc6', k: '#c6bba3', d: '#9a7044', D: '#ddd0b4',
  p: '#b89a6a', g: '#b8954a', b: '#5e4428', m: '#a8843e', M: '#6e5a34', r: '#7a2e26', R: '#5e231d',
  q: '#6e2a22', t: '#d6ccb5', T: '#aea38c', n: '#5e4430', N: '#46321f', o: '#2a2420', l: '#3a2c22',
  P: '#5a3550',
};
const PALC = Object.fromEntries(Object.entries(PAL).map(([k, v]) => [k, hex(v)]));

export function fromRows(rows) {
  const w = Math.max(...rows.map((r) => r.length));
  const h = rows.length;
  const px = new Array(w * h).fill(null);
  rows.forEach((r, y) => [...r].forEach((ch, x) => { if (PALC[ch]) px[y * w + x] = PALC[ch]; }));
  return { w, h, px };
}

const ROWS = {
  spear: ['..p', '.hp', '.sp', 'dwp', '.k.', '.s.'],
  spear2: ['.p.', 'hp.', 'sp.', 'wpD', 'k..', 's..'],
  archer: ['...', '.h.', '.sb', 'wwb', '.k.', '.s.'],
  officer: ['...', '.g.', '.s.', 'gwg', '.k.', '.s.'],
  hauler: ['....', '..h.', '.ss.', 'sww.', '.k..', 's.s.'],
  roman: ['...', '.m.', '.s.', 'qrr', '.R.', '.s.'],
  roman_bow: ['...', '.m.', '.sb', 'rrb', '.R.', '.s.'],
  worker: ['...', '.n.', '.S.', 'StS', '.T.', 'S.S'],
  engineer: ['...', '.N.', '.S.', 'ttS', '.T.', '.S.'],
  fallen: ['hsww'],
  fallen2: ['wwsh'],
  chariot: ['......h.', '.n...pwg', 'nnnn.bbb', 'nnnn.bbb', 'l..l.o.o'],
  // v2 bake (bake.mjs): the shield bearer with a hide shield, the chariot toward and away from
  // the camera (the side view above faces left)
  shield: ['....', '.h..', '.sDd', 'wwDd', '.kDd', '.s..'],
  chariot_s: ['..h..', '.pwg.', 'obbbo', '.nnn.', '.nnn.', '.n.n.'],
  chariot_n: ['.n.n.', '.nnn.', '.nnn.', '..h..', 'obwbo', 'obbbo'],
};

// Four walk frames of a person or a chariot: the sprite, a stride (legs apart, or together
// where the sprite stands apart), the sprite, the stride with the hips a pixel over.
export function walkFrames(id) {
  const rows = ROWS[id];
  const legsAt = rows.length - 1;
  const stride = (row) => {
    const chars = [...row];
    const on = chars.map((ch, x) => (ch !== '.' ? x : -1)).filter((x) => x >= 0);
    const ch = chars[on[0]] ?? '.';
    const out = chars.map(() => '.');
    if (on.length === 1) {
      const c = on[0];
      out[Math.max(c - 1, 0)] = ch;
      out[Math.min(c + 1, chars.length - 1)] = ch;
    } else {
      const c = Math.round((on[0] + on[on.length - 1]) / 2);
      out[c] = ch;
    }
    return out.join('');
  };
  const sway = (row) => '.' + row.slice(0, -1);
  const a = rows;
  const b = rows.map((row, y) => (y === legsAt ? stride(row) : row));
  const d = b.map((row, y) => (y === legsAt - 1 ? sway(row) : row));
  return [fromRows(a), fromRows(b), fromRows(a), fromRows(d)];
}

// A sprite mirrored left to right.
export function flipped(s) {
  const px = new Array(s.w * s.h);
  for (let y = 0; y < s.h; y++) for (let x = 0; x < s.w; x++) px[y * s.w + x] = s.px[y * s.w + s.w - 1 - x];
  return { w: s.w, h: s.h, px };
}

const cache = new Map();

export function sprite(id) {
  if (cache.has(id)) return cache.get(id);
  let s;
  if (ROWS[id]) s = fromRows(ROWS[id]);
  else if (id.startsWith('palm')) s = palm(Number(id.slice(4)) * 7919 + 13);
  else s = { w: 1, h: 1, px: [null] };
  cache.set(id, s);
  return s;
}

// A palm: a leaning ringed trunk, a crown of drooping fronds, a few dates. Anchor (13, h - 1).
function palm(seed) {
  const r = rng(seed);
  const w = 26, h = 34;
  const px = new Array(w * h).fill(null);
  const put = (x, y, c) => {
    x = Math.round(x);
    y = Math.round(y);
    if (x >= 0 && y >= 0 && x < w && y < h) px[y * w + x] = c;
  };
  const trunkH = r.int(18, 24);
  const lean = r.range(-0.22, 0.22);
  let top = { x: 13, y: h - 1 };
  for (let i = 0; i < trunkH; i++) {
    const x = 13 + lean * i + Math.sin(i * 0.15) * 0.6;
    const y = h - 1 - i;
    put(x, y, i % 3 ? hex('#7a5a3a') : hex('#5b4128'));
    put(x + 1, y, hex('#5b4128'));
    top = { x: Math.round(x), y };
  }
  const greens = [hex('#3a5230'), hex('#4f6a3a'), hex('#647d48'), hex('#2c3e24')];
  for (let f = 0; f < 8; f++) {
    const a = (TAU * f) / 8 + r.range(-0.2, 0.2);
    const length = r.range(7, 10.5);
    const dx = Math.cos(a), dy = Math.sin(a) * 0.55;
    for (let s = 0; s < length * 2; s++) {
      const t = s / 2;
      const x = top.x + dx * t;
      const y = top.y + dy * t + t * t * 0.07 - 1;
      put(x, y, greens[f % 3]);
      if (s % 3 === 1 && t > 2) {
        const l = Math.hypot(dx, dy) || 1;
        put(x - dy / l, y + dx / l + 1, greens[3]);
      }
    }
  }
  put(top.x, top.y + 1, hex('#8a4a20'));
  put(top.x + 1, top.y + 1, hex('#6a3618'));
  return { w, h, px };
}
