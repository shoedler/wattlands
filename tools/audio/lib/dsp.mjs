// The DSP primitives of the audio pipeline: seeded noise, band-limited oscillators, modal, pluck,
// chirp, grains and FM sources, envelopes, RBJ biquads and the room presets. Zero dependencies, no
// global randomness, no wall clock: every function is a pure function of its arguments.

export const TWO_PI = Math.PI * 2;
const DECAY_60DB = 6.907755278982137; // ln(1000)

// --- Noise ---

/** A seeded xorshift32 generator returning uint32. */
export function xorshift32(seed) {
  let s = seed >>> 0 || 0x2545f491;
  const next = () => {
    s ^= s << 13;
    s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5;
    s >>>= 0;
    return s;
  };
  for (let i = 0; i < 16; i++) next();
  return next;
}

/** A uniform float in [0, 1) from a xorshift32 generator. */
export function uniform(next) {
  return next() / 4294967296;
}

/** n samples of white, pink or brown noise, about +-1. */
export function noise(color, n, seed) {
  const next = xorshift32(seed);
  const out = new Float64Array(n);
  if (color === 'white') {
    for (let i = 0; i < n; i++) out[i] = 2 * uniform(next) - 1;
  } else if (color === 'pink') {
    let b0 = 0;
    let b1 = 0;
    let b2 = 0;
    let b3 = 0;
    let b4 = 0;
    let b5 = 0;
    let b6 = 0;
    for (let i = 0; i < n; i++) {
      const w = 2 * uniform(next) - 1;
      b0 = 0.99886 * b0 + w * 0.0555179;
      b1 = 0.99332 * b1 + w * 0.0750759;
      b2 = 0.969 * b2 + w * 0.153852;
      b3 = 0.8665 * b3 + w * 0.3104856;
      b4 = 0.55 * b4 + w * 0.5329522;
      b5 = -0.7616 * b5 - w * 0.016898;
      out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11;
      b6 = w * 0.115926;
    }
  } else if (color === 'brown') {
    let last = 0;
    for (let i = 0; i < n; i++) {
      const w = 2 * uniform(next) - 1;
      last = (last + 0.02 * w) / 1.02;
      out[i] = last * 3.5;
    }
  } else {
    throw new Error(`unknown noise color "${color}"`);
  }
  return out;
}

// --- Frequency tracks ---

/**
 * Per-sample frequency. spec: a number, [start, end] (with glide lin|exp over glideS or the whole
 * layer) or [[t, hz], ...] (exponential between points, held outside them).
 */
export function freqTrack(spec, n, rate, { glide = 'lin', glideS = null, pitch = 1 } = {}) {
  const out = new Float64Array(n);
  if (typeof spec === 'number') {
    out.fill(spec * pitch);
    return out;
  }
  if (!Array.isArray(spec) || spec.length === 0) throw new Error(`bad frequency ${JSON.stringify(spec)}`);
  if (Array.isArray(spec[0])) return pointsTrack(spec, n, rate, pitch);
  const [a, b] = spec;
  const span = Math.max(1, Math.round((glideS ?? n / rate) * rate));
  for (let i = 0; i < n; i++) {
    const u = Math.min(1, i / span);
    out[i] = pitch * (glide === 'exp' ? a * Math.pow(b / a, u) : a + (b - a) * u);
  }
  return out;
}

function pointsTrack(points, n, rate, scale) {
  const out = new Float64Array(n);
  let k = 0;
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    while (k + 1 < points.length && points[k + 1][0] <= t) k++;
    if (k + 1 >= points.length || t <= points[k][0]) {
      out[i] = points[k][1] * scale;
    } else {
      const [t0, f0] = points[k];
      const [t1, f1] = points[k + 1];
      out[i] = scale * f0 * Math.pow(f1 / f0, (t - t0) / (t1 - t0));
    }
  }
  return out;
}

// --- Oscillators ---

function polyBlep(t, dt) {
  if (t < dt) {
    const x = t / dt;
    return x + x - x * x - 1;
  }
  if (t > 1 - dt) {
    const x = (t - 1) / dt;
    return x * x + x + x + 1;
  }
  return 0;
}

/** wave: sine tri saw square pulse, from a per-sample frequency track. polyBLEP on the steps. */
export function oscillator(wave, track, rate, { duty = 0.5, phase = 0 } = {}) {
  const n = track.length;
  const out = new Float64Array(n);
  let p = phase;
  for (let i = 0; i < n; i++) {
    const dt = Math.min(0.5, Math.abs(track[i]) / rate);
    let v;
    switch (wave) {
      case 'sine':
        v = Math.sin(TWO_PI * p);
        break;
      case 'tri':
        v = 4 * Math.abs(p - 0.5) - 1;
        break;
      case 'saw':
        v = 2 * p - 1 - polyBlep(p, dt);
        break;
      case 'square':
      case 'pulse': {
        const d = wave === 'square' ? 0.5 : duty;
        v = (p < d ? 1 : -1) + polyBlep(p, dt) - polyBlep((p - d + 1) % 1, dt);
        break;
      }
      default:
        throw new Error(`unknown oscillator "${wave}"`);
    }
    out[i] = v;
    p += dt;
    if (p >= 1) p -= 1;
  }
  return out;
}

// --- Sources ---

/** Decaying partials: metal, wood. f[], t60[] (s), g[]. */
export function modal({ f, t60, g }, n, rate, pitch = 1) {
  const out = new Float64Array(n);
  for (let k = 0; k < f.length; k++) {
    const w = (TWO_PI * f[k] * pitch) / rate;
    if (f[k] * pitch >= rate / 2) continue;
    const t = t60[Math.min(k, t60.length - 1)];
    const a = g === undefined ? 1 : g[Math.min(k, g.length - 1)];
    const decay = Math.exp(-DECAY_60DB / (t * rate));
    let amp = a;
    for (let i = 0; i < n; i++) {
      out[i] += amp * Math.sin(w * i);
      amp *= decay;
    }
  }
  return out;
}

/** Karplus-Strong. f (Hz), decay (t60 s), bright 0..1: the ballista, a snapping line. */
export function pluck({ f, decay = 1, bright = 0.5 }, n, rate, seed, pitch = 1) {
  const smooth = 0.5 - 0.48 * Math.min(1, Math.max(0, bright));
  // The loop's delay is the line, its fractional tap and the averaging filter's own `smooth` samples.
  const target = Math.max(2, rate / (f * pitch) - smooth);
  const len = Math.floor(target);
  const frac = target - len;
  const out = new Float64Array(n);
  const burst = noise('white', len + 1, seed);
  // A darker excitation for a darker string.
  let y0 = 0;
  for (let i = 0; i <= len && i < n; i++) {
    y0 += (1 - smooth) * (burst[i] - y0);
    out[i] = y0;
  }
  const loss = Math.pow(10, (-3 * (1 / (f * pitch))) / decay);
  let prev = 0;
  for (let i = len + 1; i < n; i++) {
    const v = (1 - frac) * out[i - len] + frac * out[i - len - 1];
    out[i] = loss * ((1 - smooth) * v + smooth * prev);
    prev = v;
  }
  return out;
}

/** Log-uniform scatter of short bursts, Poisson in time: crackle, bubbling, patter, crickets. */
export function grains({ rate_hz: rateHz, f, dur_s: durS, g = [1, 1], kind = 'sine', sweep = 1 }, n, rate, seed, pitch = 1) {
  const next = xorshift32(seed);
  const out = new Float64Array(n);
  let t = 0;
  for (;;) {
    t += -Math.log(1 - uniform(next)) / rateHz;
    const at = Math.round(t * rate);
    if (at >= n) break;
    const f0 = pitch * f[0] * Math.pow(f[1] / f[0], uniform(next));
    const d = durS[0] + (durS[1] - durS[0]) * uniform(next);
    const amp = g[0] + (g[1] - g[0]) * uniform(next);
    const len = Math.min(n - at, Math.max(2, Math.round(d * rate)));
    const decay = Math.exp(-DECAY_60DB / Math.max(2, Math.round(d * rate)));
    const atk = Math.max(1, Math.round(0.0005 * rate));
    let e = amp;
    let p = 0;
    for (let i = 0; i < len; i++) {
      const u = i / len;
      const inst = f0 * Math.pow(sweep, u);
      const s = kind === 'noise' ? 2 * uniform(next) - 1 : Math.sin(TWO_PI * p);
      out[at + i] += s * e * Math.min(1, (i + 1) / atk);
      e *= decay;
      p += inst / rate;
    }
  }
  return out;
}

/** Two-operator FM: bell, horn. The index falls by index_decay (a time constant in s; 0 = fixed). */
export function fm({ ratio = 1, index = 1, index_decay: indexDecay = 0 }, track, rate) {
  const n = track.length;
  const out = new Float64Array(n);
  const k = indexDecay > 0 ? Math.exp(-1 / (indexDecay * rate)) : 1;
  let idx = index;
  let pc = 0;
  let pm = 0;
  for (let i = 0; i < n; i++) {
    out[i] = Math.sin(TWO_PI * pc + idx * Math.sin(TWO_PI * pm));
    pc += track[i] / rate;
    pm += (track[i] * ratio) / rate;
    pc -= Math.floor(pc);
    pm -= Math.floor(pm);
    idx *= k;
  }
  return out;
}

// --- Envelopes ---

/**
 * {a, h, d, s, r, curve} or {points: [[t, g], ...]}, in seconds. Linear attack, hold, decay to s
 * (curve exp|lin, default exp, reaching s exactly at the end of d), sustain, linear release ending
 * at sample n. With no s the level is 0 after d.
 */
export function envelope(spec, n, rate) {
  const out = new Float64Array(n);
  if (spec.points) {
    const pts = spec.points;
    let k = 0;
    for (let i = 0; i < n; i++) {
      const t = i / rate;
      while (k + 1 < pts.length && pts[k + 1][0] <= t) k++;
      if (k + 1 >= pts.length || t <= pts[k][0]) out[i] = pts[k][1];
      else out[i] = pts[k][1] + ((pts[k + 1][1] - pts[k][1]) * (t - pts[k][0])) / (pts[k + 1][0] - pts[k][0]);
    }
    return out;
  }
  const { a = 0, h = 0, d = 0, s = d > 0 ? 0 : 1, r = 0, curve = 'exp' } = spec;
  const aN = Math.round(a * rate);
  const hN = Math.round(h * rate);
  const dN = Math.round(d * rate);
  const rN = Math.round(r * rate);
  const relStart = n - rN;
  for (let i = 0; i < n; i++) {
    let v;
    if (i < aN) {
      v = (i + 1) / aN;
    } else if (i < aN + hN) {
      v = 1;
    } else if (i < aN + hN + dN) {
      const u = (i - aN - hN) / dN;
      const shape = curve === 'lin' ? 1 - u : (Math.exp(-DECAY_60DB * u) - 0.001) / 0.999;
      v = s + (1 - s) * shape;
    } else {
      v = s;
    }
    if (rN > 0 && i >= relStart) v *= (n - i) / rN;
    out[i] = v;
  }
  return out;
}

// --- Biquads (RBJ audio EQ cookbook) ---

/** Direct-form coefficients of an RBJ filter. type: lp hp bp notch peak highshelf. */
export function rbj(type, f, q, rate, db = 0) {
  const w = (TWO_PI * Math.min(f, 0.49 * rate)) / rate;
  const cw = Math.cos(w);
  const sw = Math.sin(w);
  const alpha = sw / (2 * q);
  let b0;
  let b1;
  let b2;
  let a0;
  let a1;
  let a2;
  switch (type) {
    case 'lp':
      b0 = (1 - cw) / 2;
      b1 = 1 - cw;
      b2 = b0;
      a0 = 1 + alpha;
      a1 = -2 * cw;
      a2 = 1 - alpha;
      break;
    case 'hp':
      b0 = (1 + cw) / 2;
      b1 = -(1 + cw);
      b2 = b0;
      a0 = 1 + alpha;
      a1 = -2 * cw;
      a2 = 1 - alpha;
      break;
    case 'bp':
      b0 = alpha;
      b1 = 0;
      b2 = -alpha;
      a0 = 1 + alpha;
      a1 = -2 * cw;
      a2 = 1 - alpha;
      break;
    case 'notch':
      b0 = 1;
      b1 = -2 * cw;
      b2 = 1;
      a0 = 1 + alpha;
      a1 = -2 * cw;
      a2 = 1 - alpha;
      break;
    case 'peak': {
      const A = Math.pow(10, db / 40);
      b0 = 1 + alpha * A;
      b1 = -2 * cw;
      b2 = 1 - alpha * A;
      a0 = 1 + alpha / A;
      a1 = -2 * cw;
      a2 = 1 - alpha / A;
      break;
    }
    case 'highshelf': {
      const A = Math.pow(10, db / 40);
      const beta = 2 * Math.sqrt(A) * alpha;
      b0 = A * (A + 1 + (A - 1) * cw + beta);
      b1 = -2 * A * (A - 1 + (A + 1) * cw);
      b2 = A * (A + 1 + (A - 1) * cw - beta);
      a0 = A + 1 - (A - 1) * cw + beta;
      a1 = 2 * (A - 1 - (A + 1) * cw);
      a2 = A + 1 - (A - 1) * cw - beta;
      break;
    }
    default:
      throw new Error(`unknown filter "${type}"`);
  }
  return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
}

/** x through one biquad, a new array. */
export function biquad(x, c) {
  const out = new Float64Array(x.length);
  let x1 = 0;
  let x2 = 0;
  let y1 = 0;
  let y2 = 0;
  for (let i = 0; i < x.length; i++) {
    const v = x[i];
    const y = c.b0 * v + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2;
    x2 = x1;
    x1 = v;
    y2 = y1;
    y1 = y;
    out[i] = y;
  }
  return out;
}

const SWEEP_BLOCK = 16;

/** A filter whose cutoff follows a per-sample track; coefficients refresh every 16 samples. */
export function sweptBiquad(x, type, track, q, rate, db = 0) {
  const out = new Float64Array(x.length);
  let x1 = 0;
  let x2 = 0;
  let y1 = 0;
  let y2 = 0;
  let c = null;
  for (let i = 0; i < x.length; i++) {
    if (i % SWEEP_BLOCK === 0) c = rbj(type, track[i], q, rate, db);
    const v = x[i];
    const y = c.b0 * v + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2;
    x2 = x1;
    x1 = v;
    y2 = y1;
    y1 = y;
    out[i] = y;
  }
  return out;
}

const BUTTER4_Q = [0.5412, 1.3066];

/** 24 dB/oct on each side: two RBJ biquads per side, Butterworth Qs. */
export function bandFilter(x, lo, hi, rate) {
  let y = x;
  for (const q of BUTTER4_Q) y = biquad(y, rbj('hp', lo, q, rate));
  for (const q of BUTTER4_Q) y = biquad(y, rbj('lp', hi, q, rate));
  return y;
}

// --- Effects ---

/** Feedback comb: y[n] = x[n] + fb * y[n - d]. A new array. */
export function comb(x, ms, fb, rate, damp = 0) {
  const d = Math.max(1, Math.round((ms / 1000) * rate));
  const out = new Float64Array(x.length);
  let lp = 0;
  for (let i = 0; i < x.length; i++) {
    let back = i >= d ? out[i - d] : 0;
    if (damp > 0) {
      lp += (1 - damp) * (back - lp);
      back = lp;
    }
    out[i] = x[i] + fb * back;
  }
  return out;
}

/** Quantize to `bits`, holding each value for `hold` samples. A new array. */
export function crush(x, bits, hold = 1) {
  const steps = Math.pow(2, bits - 1);
  const out = new Float64Array(x.length);
  let v = 0;
  for (let i = 0; i < x.length; i++) {
    if (i % hold === 0) v = Math.round(x[i] * steps) / steps;
    out[i] = v;
  }
  return out;
}

/** One `fx[]` entry, such as {"lp": {"f": 420, "q": 0.9}} or {"drive": 2.5}. A new array. */
export function applyFx(x, entry, rate) {
  const keys = Object.keys(entry);
  if (keys.length !== 1) throw new Error(`an fx entry has one key: ${JSON.stringify(entry)}`);
  const name = keys[0];
  const p = entry[name];
  switch (name) {
    case 'lp':
    case 'hp':
    case 'bp':
    case 'notch':
    case 'peak': {
      const q = p.q ?? 0.7071;
      const db = p.db ?? 0;
      if (typeof p.f === 'number') return biquad(x, rbj(name, p.f, q, rate, db));
      const track = freqTrack(p.f, x.length, rate, { glide: p.glide ?? 'exp', glideS: p.glide_s ?? null });
      return sweptBiquad(x, name, track, q, rate, db);
    }
    case 'drive': {
      const g = typeof p === 'number' ? p : p.gain;
      return x.map((v) => Math.tanh(g * v));
    }
    case 'crush':
      return crush(x, p.bits, p.hold ?? 1);
    case 'comb':
      return comb(x, p.ms, p.fb ?? 0.5, rate, p.damp ?? 0);
    case 'trem': {
      const depth = p.depth ?? 0.5;
      const w = (TWO_PI * p.hz) / rate;
      return x.map((v, i) => v * (1 - depth * (0.5 + 0.5 * Math.sin(w * i))));
    }
    case 'gain_env': {
      const e = envelope(p, x.length, rate);
      return x.map((v, i) => v * e[i]);
    }
    default:
      throw new Error(`unknown fx "${name}"`);
  }
}

// --- Rooms ---

export const ROOMS = ['none', 'iron', 'wood', 'open'];

/** The three shared room presets. iron: 18 ms and 31 ms combs. wood: 11 ms damped. open: an HF tilt. */
export function applyRoom(x, room, rate) {
  switch (room) {
    case 'none':
      return x;
    case 'iron': {
      const a = comb(x, 18, 0.38, rate);
      const b = comb(x, 31, 0.3, rate);
      return x.map((v, i) => 0.6 * v + 0.2 * (a[i] + b[i]));
    }
    case 'wood': {
      const a = comb(x, 11, 0.42, rate, 0.45);
      return x.map((v, i) => 0.7 * v + 0.3 * a[i]);
    }
    case 'open':
      return biquad(x, rbj('highshelf', 3500, 0.7071, rate, -3));
    default:
      throw new Error(`unknown room "${room}"`);
  }
}

// --- Spectrum ---

/** Radix-2 in-place FFT; re.length is a power of two. */
export function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      [re[i], re[j]] = [re[j], re[i]];
      [im[i], im[j]] = [im[j], im[i]];
    }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -TWO_PI / len;
    const wr = Math.cos(ang);
    const wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cr = 1;
      let ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const a = i + k;
        const b = a + len / 2;
        const tr = re[b] * cr - im[b] * ci;
        const ti = re[b] * ci + im[b] * cr;
        re[b] = re[a] - tr;
        im[b] = im[a] - ti;
        re[a] += tr;
        im[a] += ti;
        const nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}

const hannCache = new Map();

function hann(size) {
  let w = hannCache.get(size);
  if (!w) {
    w = new Float64Array(size);
    for (let i = 0; i < size; i++) w[i] = 0.5 - 0.5 * Math.cos((TWO_PI * i) / size);
    hannCache.set(size, w);
  }
  return w;
}

/** Hann-windowed, averaged power spectrum of x: Float64Array(size / 2 + 1). */
export function powerSpectrum(x, size = 2048) {
  const out = new Float64Array(size / 2 + 1);
  const w = hann(size);
  const hop = size / 2;
  const re = new Float64Array(size);
  const im = new Float64Array(size);
  let frames = 0;
  const last = Math.max(1, x.length - size + hop);
  for (let at = 0; at < last; at += hop) {
    for (let i = 0; i < size; i++) {
      re[i] = (at + i < x.length ? x[at + i] : 0) * w[i];
      im[i] = 0;
    }
    fft(re, im);
    for (let k = 0; k <= size / 2; k++) out[k] += re[k] * re[k] + im[k] * im[k];
    frames++;
  }
  for (let k = 0; k < out.length; k++) out[k] /= Math.max(1, frames);
  return out;
}

/** The energy of x in [loHz, hiHz), relative to its total, in dB. */
export function bandShareDb(x, rate, loHz, hiHz, size = 2048) {
  const p = powerSpectrum(x, size);
  let total = 0;
  let part = 0;
  for (let k = 0; k < p.length; k++) {
    const f = (k * rate) / size;
    total += p[k];
    if (f >= loHz && f < hiHz) part += p[k];
  }
  if (total <= 0) return -Infinity;
  return part > 0 ? 10 * Math.log10(part / total) : -Infinity;
}

export function dbToGain(db) {
  return Math.pow(10, db / 20);
}

export function gainToDb(g) {
  return g > 0 ? 20 * Math.log10(g) : -Infinity;
}
