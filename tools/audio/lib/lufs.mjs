// Loudness per ITU-R BS.1770-4 and EBU R128: K-weighting by bilinear transform at any sample rate
// (the libebur128 prototype constants), 400 ms blocks with 75 % overlap, the -70 LUFS and -10 LU
// gates, momentary maximum, loudness range (EBU Tech 3342) and a 4x true peak.

import { TWO_PI, biquad } from './dsp.mjs';

const LUFS_OFFSET = -0.691;
const ABS_GATE = -70;
export const SILENCE_LUFS = -120;

/** The two K-weighting biquads at `rate`. At 48 kHz these are the coefficients printed in BS.1770. */
export function kWeighting(rate) {
  const shelfF = 1681.974450955533;
  const shelfG = 3.999843853973347;
  const shelfQ = 0.7071752369554196;
  let K = Math.tan((Math.PI * shelfF) / rate);
  const Vh = Math.pow(10, shelfG / 20);
  const Vb = Math.pow(Vh, 0.4996667741545416);
  let a0 = 1 + K / shelfQ + K * K;
  const shelf = {
    b0: (Vh + (Vb * K) / shelfQ + K * K) / a0,
    b1: (2 * (K * K - Vh)) / a0,
    b2: (Vh - (Vb * K) / shelfQ + K * K) / a0,
    a1: (2 * (K * K - 1)) / a0,
    a2: (1 - K / shelfQ + K * K) / a0,
  };
  const hpF = 38.13547087602444;
  const hpQ = 0.5003270373238773;
  K = Math.tan((Math.PI * hpF) / rate);
  a0 = 1 + K / hpQ + K * K;
  const hp = { b0: 1, b1: -2, b2: 1, a1: (2 * (K * K - 1)) / a0, a2: (1 - K / hpQ + K * K) / a0 };
  return { shelf, hp };
}

function weighted(channels, rate) {
  const { shelf, hp } = kWeighting(rate);
  return channels.map((x) => biquad(biquad(x, shelf), hp));
}

function energyToLufs(e) {
  return e > 0 ? LUFS_OFFSET + 10 * Math.log10(e) : SILENCE_LUFS;
}

/** Summed channel energy over sliding blocks of blockS, hop hopS; short signals get one padded block. */
function blockEnergies(k, rate, blockS, hopS) {
  const block = Math.round(blockS * rate);
  const hop = Math.max(1, Math.round(hopS * rate));
  const n = k[0].length;
  const prefix = new Float64Array(n + 1);
  for (let i = 0; i < n; i++) {
    let s = 0;
    for (const c of k) s += c[i] * c[i];
    prefix[i + 1] = prefix[i] + s;
  }
  if (n < block) return [prefix[n] / block];
  const out = [];
  for (let at = 0; at + block <= n; at += hop) out.push((prefix[at + block] - prefix[at]) / block);
  return out;
}

function gatedMean(energies, relativeLu) {
  const absolute = energies.filter((e) => energyToLufs(e) > ABS_GATE);
  if (absolute.length === 0) return 0;
  const mean = absolute.reduce((a, b) => a + b, 0) / absolute.length;
  const gate = energyToLufs(mean) + relativeLu;
  const kept = absolute.filter((e) => energyToLufs(e) > gate);
  if (kept.length === 0) return 0;
  return kept.reduce((a, b) => a + b, 0) / kept.length;
}

/** Integrated loudness in LUFS. SILENCE_LUFS when everything is gated out. */
export function integratedLufs(channels, rate) {
  const e = blockEnergies(weighted(channels, rate), rate, 0.4, 0.1);
  return energyToLufs(gatedMean(e, -10));
}

/** Momentary maximum (400 ms). A sound under 400 ms counts as padded with silence. */
export function momentaryMaxLufs(channels, rate) {
  const e = blockEnergies(weighted(channels, rate), rate, 0.4, 0.05);
  return energyToLufs(e.reduce((a, b) => Math.max(a, b), 0));
}

/** Momentary loudness of the 400 ms block starting at each hop: [{t, lufs}]. */
export function momentaryTrack(channels, rate, hopS = 0.1) {
  const e = blockEnergies(weighted(channels, rate), rate, 0.4, hopS);
  return e.map((v, i) => ({ t: i * hopS, lufs: energyToLufs(v) }));
}

/** Loudness range per EBU Tech 3342: short-term 3 s blocks, -70 and -20 gates, 10th to 95th. */
export function loudnessRange(channels, rate) {
  const e = blockEnergies(weighted(channels, rate), rate, 3, 0.1);
  const absolute = e.filter((v) => energyToLufs(v) > ABS_GATE);
  if (absolute.length === 0) return 0;
  const mean = absolute.reduce((a, b) => a + b, 0) / absolute.length;
  const gate = energyToLufs(mean) - 20;
  const kept = absolute
    .map(energyToLufs)
    .filter((l) => l > gate)
    .sort((a, b) => a - b);
  if (kept.length === 0) return 0;
  const at = (q) => kept[Math.min(kept.length - 1, Math.round(q * (kept.length - 1)))];
  return at(0.95) - at(0.1);
}

const OVERSAMPLE = 4;
const TAPS = 24;

function interpolationKernels() {
  const kernels = [];
  for (let phase = 1; phase < OVERSAMPLE; phase++) {
    const k = new Float64Array(TAPS);
    for (let t = 0; t < TAPS; t++) {
      const x = t - (TAPS / 2 - 1) - phase / OVERSAMPLE;
      const sinc = Math.sin(Math.PI * x) / (Math.PI * x);
      k[t] = sinc * (0.5 + 0.5 * Math.cos((TWO_PI * x) / TAPS));
    }
    kernels.push(k);
  }
  return kernels;
}

const KERNELS = interpolationKernels();

/** True peak in dBTP by 4x windowed-sinc oversampling. */
export function truePeakDb(channels) {
  let max = 0;
  for (const x of channels) {
    for (let i = 0; i < x.length; i++) {
      const a = Math.abs(x[i]);
      if (a > max) max = a;
    }
    for (const k of KERNELS) {
      for (let base = 0; base + TAPS <= x.length; base++) {
        let s = 0;
        for (let t = 0; t < TAPS; t++) s += k[t] * x[base + t];
        const a = Math.abs(s);
        if (a > max) max = a;
      }
    }
  }
  return max > 0 ? 20 * Math.log10(max) : -Infinity;
}
