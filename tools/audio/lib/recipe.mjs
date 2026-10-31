// A sound recipe (one entry of audio.json "sounds") -> samples. The final chain of every sound, in
// order: sum -> room -> band filter -> loop wrap (or a short tail fade) -> norm -> family crush ->
// pre-roll -> 16-bit. A seeded, pure function: same recipe, same bytes.

import { applyFx, applyRoom, bandFilter, dbToGain, envelope, fm, freqTrack, gainToDb, grains, modal, noise, oscillator, pluck } from './dsp.mjs';
import { integratedLufs } from './lufs.mjs';

export const PREROLL_S = 0.08;
export const FAMILY_BITS = 12;
export const FAMILY_BAND = { 22050: [40, 9000], 11025: [40, 5000] };
const TAIL_FADE_S = 0.002;
const WAVES = new Set(['sine', 'tri', 'saw', 'square', 'pulse']);
export const SOURCES = new Set([...WAVES, 'noise', 'modal', 'pluck', 'chirp', 'grains', 'fm']);

/** A stable 31-bit hash of a sound id, the default seed. */
export function hashId(id) {
  let h = 0x811c9dc5;
  for (let i = 0; i < id.length; i++) {
    h ^= id.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h & 0x7fffffff;
}

/** The sound with its defaults and one variant's overrides applied. */
export function resolveSound(id, sound, variant = 0, { game = '' } = {}) {
  const over = sound.per_variant ? (sound.per_variant[variant] ?? {}) : {};
  const s = { ...sound, ...over };
  const rate = s.rate ?? 22050;
  const locked = s.locked === true;
  const loop = s.loop === true;
  return {
    ...s,
    id,
    rate,
    ch: s.ch ?? 1,
    seed: s.seed ?? hashId(id),
    locked,
    loop,
    variants: sound.variants ?? 1,
    compress: s.compress ?? defaultCompress({ locked, loop, dur: s.dur, game }),
    norm: s.norm ?? (loop ? { lufs: -20 } : locked ? { peak: -6 } : { peak: -3 }),
    band: s.band ?? FAMILY_BAND[rate],
    crush: s.crush ?? FAMILY_BITS,
    room: s.room ?? 'none',
    layers: s.layers ?? [],
    pitch: s.pitch ?? 1,
  };
}

function defaultCompress({ locked, loop, dur, game }) {
  if (locked || game === '_shared') return 'pcm';
  if (loop && dur <= 2) return 'pcm';
  return 'qoa';
}

function renderSource(layer, n, rate, seed, pitch) {
  const src = layer.src;
  if (WAVES.has(src)) {
    const track = freqTrack(layer.f, n, rate, { glide: layer.glide ?? 'lin', glideS: layer.glide_s ?? null, pitch });
    return oscillator(src, track, rate, { duty: layer.duty ?? 0.5, phase: layer.phase ?? 0 });
  }
  switch (src) {
    case 'noise':
      return noise(layer.color ?? 'white', n, seed);
    case 'modal':
      return modal(layer, n, rate, pitch);
    case 'pluck':
      return pluck(layer, n, rate, seed, pitch);
    case 'grains':
      return grains(layer, n, rate, seed, pitch);
    case 'fm':
      return fm(layer, freqTrack(layer.f, n, rate, { glide: layer.glide ?? 'lin', glideS: layer.glide_s ?? null, pitch }), rate);
    case 'chirp': {
      const track = freqTrack(layer.points, n, rate, { pitch });
      if (layer.vibrato) {
        const w = (2 * Math.PI * layer.vibrato.hz) / rate;
        for (let i = 0; i < n; i++) track[i] *= Math.pow(2, (layer.vibrato.cents / 1200) * Math.sin(w * i));
      }
      return oscillator(layer.wave ?? 'sine', track, rate, { duty: layer.duty ?? 0.5 });
    }
    default:
      throw new Error(`unknown layer src "${src}"`);
  }
}

function renderChannel(spec, variant, chan, total) {
  const out = new Float64Array(total);
  spec.layers.forEach((layer, index) => {
    const at = Math.round((layer.at ?? 0) * spec.rate);
    const room = total - at;
    if (room <= 0) return;
    const n = layer.dur === undefined ? room : Math.min(room, Math.round(layer.dur * spec.rate));
    const seed = (spec.seed + variant * 1009 + index * 31 + chan * 7919) >>> 0;
    let x = renderSource(layer, n, spec.rate, seed, spec.pitch);
    if (layer.env) {
      const e = envelope(layer.env, n, spec.rate);
      for (let i = 0; i < n; i++) x[i] *= e[i];
    }
    for (const entry of layer.fx ?? []) x = applyFx(x, entry, spec.rate);
    const gain = layer.gain ?? 1;
    for (let i = 0; i < n; i++) out[at + i] += x[i] * gain;
  });
  return out;
}

/** Width 1: two independent renders. Width 0: one render on both sides. Then constant-power pan. */
function renderChannels(spec, variant, total) {
  if (spec.ch === 1) return [renderChannel(spec, variant, 0, total)];
  const width = spec.width ?? (spec.pan === undefined ? 1 : 0);
  const left = renderChannel(spec, variant, 0, total);
  const right = width > 0 ? renderChannel(spec, variant, 1, total) : left.slice();
  const theta = ((1 - width) * Math.PI) / 4;
  const a = Math.cos(theta);
  const b = Math.sin(theta);
  const angle = (((spec.pan ?? 0) + 1) * Math.PI) / 4;
  const gl = Math.cos(angle) * Math.SQRT2;
  const gr = Math.sin(angle) * Math.SQRT2;
  const l = new Float64Array(total);
  const r = new Float64Array(total);
  for (let i = 0; i < total; i++) {
    l[i] = (a * left[i] + b * right[i]) * gl;
    r[i] = (a * right[i] + b * left[i]) * gr;
  }
  return [l, r];
}

/**
 * Tail into head over xf frames, so x[N - 1] runs on into out[0]. One guard frame, a copy of frame
 * 0, follows the loop: Godot reads "next" past the loop end when it interpolates, and its
 * edit/loop_end = -1 means frames - 1, so the period is exactly N and the read lands on frame 0.
 */
function loopWrap(x, frames, xf) {
  const out = new Float64Array(frames + 1);
  for (let i = 0; i < frames; i++) out[i] = x[i];
  // Constant power for any correlation r of head and tail: linear for a tone in phase (r = 1), nearly
  // equal power for noise (r = 0), so neither bumps nor dips across the seam.
  let ab = 0;
  let aa = 0;
  let bb = 0;
  for (let i = 0; i < xf; i++) {
    ab += x[i] * x[frames + i];
    aa += x[i] * x[i];
    bb += x[frames + i] * x[frames + i];
  }
  const r = aa > 0 && bb > 0 ? ab / Math.sqrt(aa * bb) : 0;
  for (let i = 0; i < xf; i++) {
    const u = i / xf;
    const v = 1 - u;
    const den = Math.sqrt(Math.max(1e-6, u * u + v * v + 2 * r * u * v));
    out[i] = (x[i] * u + x[frames + i] * v) / den;
  }
  out[frames] = out[0];
  return out;
}

/**
 * The file starts at the quietest step of the cycle, so its seam is no louder than any other sample
 * pair: on noise, a seam left where the crossfade happens to end is 2 sigma out one time in 25.
 */
function rotateToQuietStep(channels, frames) {
  let best = 0;
  let bestStep = Infinity;
  for (let i = 0; i < frames; i++) {
    let step = 0;
    for (const x of channels) step = Math.max(step, Math.abs(x[i] - x[(i + frames - 1) % frames]));
    if (step < bestStep) {
      bestStep = step;
      best = i;
    }
  }
  return channels.map((x) => {
    const out = new Float64Array(frames + 1);
    for (let i = 0; i <= frames; i++) out[i] = x[(best + i) % frames];
    return out;
  });
}

function peakOf(channels) {
  let m = 0;
  for (const x of channels) {
    for (let i = 0; i < x.length; i++) {
      const a = Math.abs(x[i]);
      if (a > m) m = a;
    }
  }
  return m;
}

/** A loop short enough to read low on a 400 ms meter is measured tiled. */
function measureLufs(channels, rate, loopFrames) {
  const need = Math.round(rate * 1.2);
  if (!loopFrames || loopFrames >= need) return integratedLufs(channels, rate);
  const tiles = Math.ceil(need / loopFrames);
  const tiled = channels.map((x) => {
    const y = new Float64Array(loopFrames * tiles);
    for (let i = 0; i < y.length; i++) y[i] = x[i % loopFrames];
    return y;
  });
  return integratedLufs(tiled, rate);
}

function normalize(channels, spec, loopFrames) {
  const peak = peakOf(channels);
  if (peak <= 0) throw new Error(`sound "${spec.id}" renders silent`);
  let gain;
  if (spec.norm.peak !== undefined) {
    gain = dbToGain(spec.norm.peak) / peak;
  } else if (spec.norm.lufs !== undefined) {
    gain = dbToGain(spec.norm.lufs - measureLufs(channels, spec.rate, loopFrames));
    if (gain * peak > 0.98) gain = 0.98 / peak;
  } else {
    throw new Error(`sound "${spec.id}": norm needs "peak" or "lufs"`);
  }
  return channels.map((x) => x.map((v) => v * gain));
}

/** The family crush: 16-bit container, `bits` significant bits, low bits zero, no dither. */
export function quantize(v, bits) {
  const step = 1 << (16 - bits);
  const top = 32768 - step;
  const q = Math.round((v * 32768) / step) * step;
  return Math.max(-top, Math.min(top, q));
}

/**
 * Render one variant. Returns {samples (interleaved Int16Array), rate, ch, frames, loopFrames,
 * preroll (frames of leading silence), peak_db, lufs}. For a loop, frames = loopFrames + 1.
 */
export function renderSound(id, sound, variant = 0, opts = {}) {
  const spec = resolveSound(id, sound, variant, opts);
  const { rate, ch, loop, locked } = spec;
  if (!(spec.dur > 0)) throw new Error(`sound "${id}": dur must be > 0`);
  const frames = Math.round(spec.dur * rate);
  const xfS = spec.xfade_s ?? Math.min(spec.dur / 4, 0.5);
  const xf = loop ? Math.round(xfS * rate) : 0;
  const total = frames + xf;
  let channels = renderChannels(spec, variant, total);
  channels = channels.map((x) => applyRoom(x, spec.room, rate));
  channels = channels.map((x) => bandFilter(x, spec.band[0], spec.band[1], rate));
  if (loop) {
    channels = rotateToQuietStep(
      channels.map((x) => loopWrap(x, frames, xf)),
      frames,
    );
  } else {
    const fade = Math.max(1, Math.round(TAIL_FADE_S * rate));
    for (const x of channels) {
      for (let i = 0; i < fade; i++) x[frames - 1 - i] *= i / fade;
    }
  }
  channels = normalize(channels, spec, loop ? frames : 0);
  const preroll = locked ? Math.round(PREROLL_S * rate) : 0;
  const body = channels[0].length;
  const outFrames = preroll + body;
  const samples = new Int16Array(outFrames * ch);
  for (let c = 0; c < ch; c++) {
    const x = channels[c];
    for (let i = 0; i < body; i++) samples[(preroll + i) * ch + c] = quantize(x[i], spec.crush);
  }
  return {
    samples,
    rate,
    ch,
    frames: outFrames,
    loopFrames: loop ? frames : 0,
    preroll,
    compress: spec.compress,
    loop,
    locked,
    peak_db: round2(gainToDb(peakOf(channels))),
    lufs: round2(measureLufs(channels, rate, loop ? frames : 0)),
  };
}

function round2(v) {
  return Math.round(v * 100) / 100;
}
