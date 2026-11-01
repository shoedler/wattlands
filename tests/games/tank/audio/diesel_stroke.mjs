// What plays at the top of the diesel's stroke, one stroke at a time, as the machine plays it. Run it to read the numbers:
//   node tests/games/tank/audio/diesel_stroke.mjs [--wav=<dir> --label=<name>]
// --wav also writes the machine alone, its strokes and its valves alone, at 60, 90 and 110 rpm and at power 1 and 0.5, the
// Loader alone and its valve, and the crew with the diesel leading. --bank=<audio.json> renders another checkout's bank.
// diesel_stroke.test.mjs holds the strokes to these numbers. They say where a stroke's energy is and how long it lasts,
// not that it reads as a big engine: nobody's ear is in them.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fft } from '../../../../tools/audio/lib/dsp.mjs';
import { loadBank } from '../../../../tools/audio/lib/bank.mjs';
import { BankAudio, MIX_RATE, simulate, toInt16 } from '../../../../tools/audio/lib/offline_mix.mjs';
import { encodeWav } from '../../../../tools/audio/lib/wav.mjs';
import { BANK, crewMix, DIR, openBank, RPMS, soloStem, WORKING } from './ear_band.mjs';

export const FIRES = ['diesel_fire_a', 'diesel_fire_b', 'diesel_fire_c'];
export const VALVES = ['diesel_valve_ex', 'diesel_valve_in'];
export const OVERLAY = 'diesel_fire_hard';
/** In band and hard enough for the overlay, the two loads a rider spends a ride at. */
export const IN_BAND = { power: 0.9, ...WORKING.diesel };
export const HARD = { power: 1.2, ...WORKING.diesel };
export const STEAM = ['chuff_a', 'chuff_b', 'steam_valve', 'hoist_pawl'];
export const STEAM_BAND = { power: 0.9, pressure_pct: 80, loaded: 0 };

const N = 8192;
const db = (v) => 10 * Math.log10(v + 1e-30);
const hz = (k) => (k * MIX_RATE) / N;

/** One voice as the machine plays it: at its pitch and level, on its own, at the mix rate. */
export function strokeOf(bank, voice) {
  const f = bank.file(voice.sound, voice.variant);
  const d = f.data[0];
  const step = (f.rate * voice.pitch) / MIX_RATE;
  const g = 10 ** (voice.db / 20);
  const out = new Float64Array(Math.floor((d.length - f.preroll) / step));
  for (let i = 0; i < out.length; i++) {
    const p = f.preroll + i * step;
    const k = Math.floor(p);
    out[i] = g * ((d[k] ?? 0) + (p - k) * ((d[k + 1] ?? 0) - (d[k] ?? 0)));
  }
  return out;
}

/** The power spectrum of a stretch, faded out so it doesn't end on a step. */
function spectrum(x, fromS, toS) {
  const at = Math.round(fromS * MIX_RATE);
  const n = Math.min(N, Math.min(x.length, Math.round(toS * MIX_RATE)) - at);
  const re = new Float64Array(N);
  const im = new Float64Array(N);
  for (let i = 0; i < n; i++) {
    const fade = i < n * 0.1 ? 1 : 0.5 + 0.5 * Math.cos((Math.PI * (i - n * 0.1)) / (n * 0.9));
    re[i] = x[at + i] * fade;
  }
  fft(re, im);
  const p = new Float64Array(N / 2 + 1);
  for (let k = 0; k <= N / 2; k++) p[k] = re[k] * re[k] + im[k] * im[k];
  return p;
}

function rmsPower(x, fromS, toS) {
  const a = Math.round(fromS * MIX_RATE);
  const b = Math.min(x.length, Math.round(toS * MIX_RATE));
  let e = 0;
  for (let i = a; i < b; i++) e += x[i] * x[i];
  return e / Math.max(1, b - a);
}

/**
 * One stroke's shape. `clickHz`: the centre of its first 10 ms, what a tick is. `bodyToClick`: 20-120 ms against the
 * first 5 ms, in dB. `lowToHigh`: under 300 Hz against 1.5 kHz and up, in dB. `earShare`: 2-8 kHz against its own total.
 * `lineHz`: its strongest line, the pitch it is heard at. `ringMs`: how long until it has fallen 30 dB.
 */
export function shapeOf(x) {
  const click = spectrum(x, 0, 0.01);
  let a = 0;
  let b = 0;
  for (let k = 1; k < click.length; k++) {
    const m = Math.sqrt(click[k]);
    a += hz(k) * m;
    b += m;
  }
  const whole = spectrum(x, 0, x.length / MIX_RATE);
  let low = 0;
  let high = 0;
  let ear = 0;
  let total = 0;
  let line = 1;
  for (let k = 1; k < whole.length; k++) {
    const f = hz(k);
    total += whole[k];
    if (f < 300) low += whole[k];
    if (f >= 1500) high += whole[k];
    if (f >= 2000 && f < 8000) ear += whole[k];
    if (whole[k] > whole[line]) line = k;
  }
  const win = Math.round(0.005 * MIX_RATE);
  const hop = Math.round(0.002 * MIX_RATE);
  const env = [];
  for (let at = 0; at + win < x.length; at += hop) {
    let e = 0;
    for (let i = 0; i < win; i++) e += x[at + i] * x[at + i];
    env.push(e);
  }
  const top = Math.max(...env);
  let ring = 0;
  env.forEach((e, i) => {
    if (e > top * 1e-3) ring = i * 2;
  });
  let peak = 0;
  for (const v of x) peak = Math.max(peak, Math.abs(v));
  return {
    clickHz: a / (b || 1),
    bodyToClick: db(rmsPower(x, 0.02, 0.12) / (rmsPower(x, 0, 0.005) || 1e-30)),
    lowToHigh: db(low / (high || 1e-30)),
    earShare: db(ear / (total || 1)),
    lineHz: hz(line),
    ringMs: ring,
    peakDb: 20 * Math.log10(peak + 1e-30),
  };
}

const FINE = 32768;

/**
 * How tonal a stroke is. `line`: its strongest line in 50-500 Hz, 5-150 ms. `height`: that line over the band's median,
 * in dB. `flatness`: the band's geometric mean over its arithmetic mean. `twoLines`: the share of 60-150 ms within 10 Hz
 * of its two strongest lines, in percent.
 */
export function tonalOf(x) {
  const fine = (k) => (k * MIX_RATE) / FINE;
  const power = (fromS, toS) => {
    const at = Math.round(fromS * MIX_RATE);
    const n = Math.min(x.length, Math.round(toS * MIX_RATE)) - at;
    const re = new Float64Array(FINE);
    const im = new Float64Array(FINE);
    for (let i = 0; i < n; i++) re[i] = x[at + i] * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (n - 1)));
    fft(re, im);
    return Float64Array.from({ length: FINE / 2 + 1 }, (_, k) => re[k] * re[k] + im[k] * im[k]);
  };
  const body = power(0.005, 0.15);
  const band = [];
  let line = 0;
  for (let k = 0; k < body.length; k++) {
    if (fine(k) < 50 || fine(k) > 500) continue;
    band.push(body[k]);
    if (body[k] > (body[line] ?? 0) || line === 0) line = k;
  }
  const sorted = [...band].sort((p, q) => p - q);
  const arithmetic = band.reduce((a, v) => a + v, 0) / band.length;
  const geometric = Math.exp(band.reduce((a, v) => a + Math.log(v + 1e-30), 0) / band.length);
  const tail = power(0.06, 0.15);
  const strongest = (skip) => {
    let best = 0;
    for (let k = 1; k < tail.length; k++) {
      const f = fine(k);
      if (f >= 40 && f <= 500 && (skip === null || Math.abs(f - skip) >= 10) && (best === 0 || tail[k] > tail[best])) best = k;
    }
    return fine(best);
  };
  const first = strongest(null);
  const second = strongest(first);
  let near = 0;
  let total = 0;
  for (let k = 1; k < tail.length; k++) {
    const f = fine(k);
    if (f >= 30 && f < 11000) total += tail[k];
    if (Math.abs(f - first) < 10 || Math.abs(f - second) < 10) near += tail[k];
  }
  return {
    line: fine(line),
    height: 10 * Math.log10(body[line] / sorted[Math.floor(sorted.length / 2)]),
    flatness: geometric / arithmetic,
    twoLines: (100 * near) / (total || 1),
  };
}

const median = (a) => [...a].sort((p, q) => p - q)[Math.floor(a.length / 2)];

/** Every voice of the machine over `revs` revolutions. */
export function voicesOf(bank, rpm, params, { machine = 'diesel', revs = 40 } = {}) {
  const s = (revs * 60) / rpm;
  return simulate(bank, { segments: [{ rpm, s, params }], machines: [{ id: 'l', machine, lead: true }], duration: s }).voices;
}

/** Every stroke of one sound over 40 revolutions: the median shape, and how far the strokes spread from each other. */
export function strokes(bank, sound, rpm, params, machine = 'diesel') {
  const voices = voicesOf(bank, rpm, params, { machine }).filter((v) => v.sound === sound);
  const shapes = voices.map((v) => shapeOf(strokeOf(bank, v)));
  const at = (key) => median(shapes.map((m) => m[key]));
  const cents = voices.map((v) => 1200 * Math.log2(v.pitch));
  const peaks = shapes.map((m) => m.peakDb);
  return {
    count: voices.length,
    clickHz: at('clickHz'),
    bodyToClick: at('bodyToClick'),
    lowToHigh: at('lowToHigh'),
    earShare: at('earShare'),
    lineHz: at('lineHz'),
    ringMs: at('ringMs'),
    peakDb: at('peakDb'),
    centsMedian: median(cents),
    centsSpan: Math.max(...cents) - Math.min(...cents),
    peakSpan: Math.max(...peaks) - Math.min(...peaks),
  };
}

function table() {
  const bank = openBank();
  const row = (s, rpm, m) =>
    `  ${s.padEnd(17)} ${String(rpm).padStart(3)} ${m.clickHz.toFixed(0).padStart(6)} ${m.bodyToClick.toFixed(1).padStart(6)} ${m.lowToHigh.toFixed(1).padStart(6)} ${m.earShare.toFixed(1).padStart(6)} ${m.lineHz.toFixed(0).padStart(6)} ${String(m.ringMs).padStart(5)} ${m.peakDb.toFixed(1).padStart(6)} ${m.centsMedian.toFixed(0).padStart(5)} ${m.centsSpan.toFixed(0).padStart(4)} ${m.peakSpan.toFixed(1).padStart(5)}`;
  const out = ['sound             rpm  click   b/c    l/h    ear   line    t30   peak  cents span pkspan'];
  for (const s of [...FIRES, ...VALVES]) for (const rpm of RPMS) out.push(row(s, rpm, strokes(bank, s, rpm, IN_BAND)));
  for (const rpm of RPMS) out.push(row(OVERLAY, rpm, strokes(bank, OVERLAY, rpm, HARD)));
  for (const s of STEAM) out.push(row(s, 90, strokes(bank, s, 90, STEAM_BAND, 'steam')));
  out.push('tonal, 90 rpm: line Hz, its height dB, flatness, two lines %');
  for (const s of FIRES) {
    const ts = voicesOf(bank, 90, IN_BAND)
      .filter((v) => v.sound === s)
      .map((v) => tonalOf(strokeOf(bank, v)));
    const at = (k) => median(ts.map((t) => t[k]));
    out.push(`  ${s.padEnd(17)} ${at('line').toFixed(1)} ${at('height').toFixed(1)} ${at('flatness').toFixed(3)} ${at('twoLines').toFixed(0)}`);
  }
  return out.join('\n');
}

function write(dir, name, stem) {
  fs.writeFileSync(path.join(dir, `${name}.wav`), encodeWav(toInt16(stem), { rate: MIX_RATE, ch: 2 }));
}

function writeWavs(dir, label, bank) {
  fs.mkdirSync(dir, { recursive: true });
  const stroke = (s) => FIRES.includes(s) || VALVES.includes(s) || s === OVERLAY;
  for (const rpm of RPMS) {
    for (const [tag, power] of [['', 1], ['_p05', 0.5]]) {
      const params = { power, ...WORKING.diesel };
      write(dir, `${label}_machine_${rpm}${tag}`, soloStem(bank, 'diesel', rpm, params, { revs: 30 }));
      write(dir, `${label}_strokes_${rpm}${tag}`, soloStem(bank, 'diesel', rpm, params, { revs: 30, pick: stroke }));
      write(dir, `${label}_valves_${rpm}${tag}`, soloStem(bank, 'diesel', rpm, params, { revs: 30, pick: (s) => VALVES.includes(s) }));
    }
    const loader = label.replace('diesel', 'loader');
    write(dir, `${loader}_machine_${rpm}`, soloStem(bank, 'steam', rpm, { power: 1, ...WORKING.steam }, { revs: 30 }));
    write(dir, `${loader}_valve_${rpm}`, soloStem(bank, 'steam', rpm, { power: 1, ...WORKING.steam }, { revs: 30, pick: (s) => s === 'steam_valve' }));
  }
  write(dir, `${label}_crew`, crewMix(bank, 'diesel').master);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const wav = process.argv.find((a) => a.startsWith('--wav='));
  const label = process.argv.find((a) => a.startsWith('--label='));
  const from = process.argv.find((a) => a.startsWith('--bank='));
  const bankPath = from ? from.slice(7) : BANK;
  if (wav) writeWavs(wav.slice(6), label ? label.slice(8) : 'tank_diesel', new BankAudio(loadBank(bankPath), from ? path.dirname(bankPath) : DIR));
  process.stdout.write(`${table()}\n`);
}
