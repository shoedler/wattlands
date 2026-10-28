// Tiny sprites: people about 5 px tall (the head is the one readable detail), chariots, palms.
// A sprite is {w, h, px: Array<[r,g,b] | null>}.
import { hex, rng, TAU } from './v3.mjs';

const PAL = {
  h: '#1e1a1a', s: '#8a5a3c', S: '#a87452', w: '#e6ddc6', k: '#c6bba3', d: '#9a7044', D: '#ddd0b4',
  p: '#a8843e', g: '#b8954a', b: '#5e4428', m: '#a8843e', M: '#6e5a34', r: '#7a2e26', R: '#5e231d',
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
};

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
