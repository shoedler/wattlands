// How much of a signal sits where the ear is most sensitive, and for how long. An owner called a machine that passed
// every other row ear piercing, and a game's flights became the same bed: a limit on this is a limit on that. It says
// where the energy is, not whether an hour of it is pleasant.

import { fft } from './dsp.mjs';
import { MIX_RATE } from './offline_mix.mjs';

export const EAR_BAND = [2000, 8000];
const WIN = 4096;
const HOP = 2048;

/** IEC 61672's A curve, as power. */
function aWeight(f) {
  const f2 = f * f;
  const num = 12194 ** 2 * f2 * f2;
  const den = (f2 + 20.6 ** 2) * Math.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194 ** 2);
  return ((num / den) * 10 ** (2 / 20)) ** 2;
}

function frames(x) {
  const out = [];
  const re = new Float64Array(WIN);
  const im = new Float64Array(WIN);
  for (let at = 0; at + WIN <= x.length; at += HOP) {
    for (let i = 0; i < WIN; i++) {
      re[i] = x[at + i] * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / WIN));
      im[i] = 0;
    }
    fft(re, im);
    const p = new Float64Array(WIN / 2 + 1);
    for (let k = 0; k <= WIN / 2; k++) p[k] = re[k] * re[k] + im[k] * im[k];
    out.push(p);
  }
  return out;
}

const db = (v) => 10 * Math.log10(v + 1e-30);

/**
 * `share`: the band's level against the signal's own total, in dB. `aShare`: the same with both A-weighted, which
 * stops a loud low end from flattering the number. `worst`: the loudest 186 ms frame's band against the signal's mean
 * total, so a sharp zap can't hide in an average. `level`: the band in dB under full scale.
 */
export function earBand(x, [lo, hi] = EAR_BAND, rate = MIX_RATE) {
  const all = frames(x);
  let total = 0;
  let band = 0;
  let aTotal = 0;
  let aBand = 0;
  let worst = 0;
  for (const p of all) {
    let frameBand = 0;
    for (let k = 1; k < p.length; k++) {
      const f = (k * rate) / WIN;
      const w = aWeight(f);
      total += p[k];
      aTotal += p[k] * w;
      if (f >= lo && f < hi) {
        frameBand += p[k];
        aBand += p[k] * w;
      }
    }
    band += frameBand;
    worst = Math.max(worst, frameBand);
  }
  const n = Math.max(1, all.length);
  // A Hann window keeps 3/8 of the power, and the spectrum counts each side once.
  const norm = (2 / (WIN * WIN * 0.375));
  return {
    share: db(band / (total || 1)),
    aShare: db(aBand / (aTotal || 1)),
    worst: db(worst / ((total || 1) / n)),
    level: db((band / n) * norm),
  };
}

/** Third-octave levels against the total, 63 Hz up to 8 kHz. */
export function thirdOctaves(x) {
  const centres = [];
  for (let i = 0; i < 22; i++) centres.push(63 * 2 ** (i / 3));
  const sum = new Float64Array(WIN / 2 + 1);
  for (const p of frames(x)) for (let k = 0; k < p.length; k++) sum[k] += p[k];
  let total = 0;
  for (let k = 1; k < sum.length; k++) total += sum[k];
  return centres.map((c) => {
    const lo = Math.max(1, Math.round((c * 2 ** (-1 / 6) * WIN) / MIX_RATE));
    const hi = Math.round((c * 2 ** (1 / 6) * WIN) / MIX_RATE);
    let s = 0;
    for (let k = lo; k <= hi && k < sum.length; k++) s += sum[k];
    return { hz: Math.round(c), db: Math.max(-90, db(s / (total || 1))) };
  });
}

/** The power-weighted centre of the spectrum, in Hz. */
export function centroidHz(x) {
  const sum = new Float64Array(WIN / 2 + 1);
  for (const p of frames(x)) for (let k = 0; k < p.length; k++) sum[k] += p[k];
  let a = 0;
  let b = 0;
  for (let k = 1; k < sum.length; k++) {
    const m = Math.sqrt(sum[k]);
    a += ((k * MIX_RATE) / WIN) * m;
    b += m;
  }
  return b > 0 ? a / b : 0;
}

/** The frequency of the strongest bin, in Hz. */
export function lineHz(x) {
  const sum = new Float64Array(WIN / 2 + 1);
  for (const p of frames(x)) for (let k = 0; k < p.length; k++) sum[k] += p[k];
  let best = 1;
  for (let k = 1; k < sum.length; k++) if (sum[k] > sum[best]) best = k;
  return (best * MIX_RATE) / WIN;
}

const ONSET_THIRDS = Array.from({ length: 15 }, (_, i) => 315 * 2 ** (i / 3));

/**
 * A mono mix's first 60 ms after each of `starts` (seconds), as third-octave levels against their own total, 315 Hz to
 * 6.3 kHz: what a listener has to tell one impact from another, with whatever else was playing in it. null with no start.
 */
export function onsetShape(m, starts, rate = MIX_RATE) {
  const span = Math.round(0.06 * rate);
  const bands = new Float64Array(ONSET_THIRDS.length);
  const n = 4096;
  const re = new Float64Array(n);
  const im = new Float64Array(n);
  let count = 0;
  for (const t of starts) {
    const at = Math.round(t * rate);
    if (at < 0 || at + span >= m.length) continue;
    re.fill(0);
    im.fill(0);
    for (let i = 0; i < span; i++) re[i] = m[at + i] * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / span));
    fft(re, im);
    ONSET_THIRDS.forEach((c, b) => {
      const lo = Math.round((c * 2 ** (-1 / 6) * n) / rate);
      const hi = Math.round((c * 2 ** (1 / 6) * n) / rate);
      for (let k = lo; k <= hi; k++) bands[b] += re[k] * re[k] + im[k] * im[k];
    });
    count++;
  }
  if (count === 0) return null;
  let total = 0;
  for (const b of bands) total += b;
  return Array.from(bands, (b) => db(b / total));
}

/** The rms distance of two shapes in dB; null when either has no onset. */
export function shapeApart(a, b) {
  if (!a || !b) return null;
  return Math.sqrt(a.reduce((acc, v, i) => acc + (v - b[i]) * (v - b[i]), 0) / a.length);
}
