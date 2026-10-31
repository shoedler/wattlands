// How a sound reads over the room: its best third-octave band against everything else in that band at the same
// moment, through the same offline mix as the scorecard, its own ducks counted. A cue that wins one band by a few dB
// can be picked out, however loud the room is across the rest; nobody has listened to prove it.

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadBank } from '../../../../tools/audio/lib/bank.mjs';
import { BankAudio, MIX_RATE, mixdown, simulate } from '../../../../tools/audio/lib/offline_mix.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
export const BANK = path.join(REPO, 'assets/tank/audio/audio.json');
export const DIR = path.dirname(BANK);

const WIN = 2048;
const HOP = 512;
const BANDS = [];
for (let i = -13; i <= 9; i++) BANDS.push(1000 * 2 ** (i / 3));

function fftPower(x, from) {
  const re = new Float64Array(WIN);
  const im = new Float64Array(WIN);
  for (let i = 0; i < WIN; i++) re[i] = (x[from + i] ?? 0) * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (WIN - 1)));
  for (let i = 1, j = 0; i < WIN; i++) {
    let bit = WIN >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      [re[i], re[j]] = [re[j], re[i]];
      [im[i], im[j]] = [im[j], im[i]];
    }
  }
  for (let len = 2; len <= WIN; len <<= 1) {
    const ang = (-2 * Math.PI) / len;
    for (let i = 0; i < WIN; i += len) {
      for (let k = 0; k < len / 2; k++) {
        const wr = Math.cos(ang * k);
        const wi = Math.sin(ang * k);
        const a = i + k;
        const b = a + len / 2;
        const tr = re[b] * wr - im[b] * wi;
        const ti = re[b] * wi + im[b] * wr;
        re[b] = re[a] - tr;
        im[b] = im[a] - ti;
        re[a] += tr;
        im[a] += ti;
      }
    }
  }
  const p = new Float64Array(BANDS.length);
  for (let b = 0; b < BANDS.length; b++) {
    const lo = Math.max(1, Math.round((BANDS[b] / 2 ** (1 / 6) / MIX_RATE) * WIN));
    const hi = Math.min(WIN / 2, Math.round(((BANDS[b] * 2 ** (1 / 6)) / MIX_RATE) * WIN));
    for (let k = lo; k <= hi; k++) p[b] += re[k] * re[k] + im[k] * im[k];
  }
  return p;
}

function mono(stems, buses) {
  const n = stems[buses[0]][0].length;
  const out = new Float64Array(n);
  for (const bus of buses) {
    const [l, r] = stems[bus];
    for (let i = 0; i < n; i++) out[i] += 0.5 * (l[i] + r[i]);
  }
  return out;
}

/**
 * The foreground's loudest `holdS` in each band, against the background in that band over the same stretch. Returns
 * the best band: {db, hz, at}. `fg` and `bg` are mono at the mix rate; `from`, `to` in seconds.
 */
export function bestBand(fg, bg, from, to, holdS = 0.2, minHz = 0) {
  const frames = [];
  for (let at = Math.round(from * MIX_RATE); at + WIN <= Math.round(to * MIX_RATE); at += HOP) {
    frames.push({ at, f: fftPower(fg, at), b: fftPower(bg, at) });
  }
  const hold = Math.max(1, Math.round((holdS * MIX_RATE) / HOP));
  let best = { db: -Infinity, hz: 0, at: 0 };
  for (let band = 0; band < BANDS.length; band++) {
    if (BANDS[band] < minHz) continue;
    let bestF = -1;
    let bestI = 0;
    let sum = 0;
    for (let i = 0; i < frames.length; i++) {
      sum += frames[i].f[band];
      if (i >= hold) sum -= frames[i - hold].f[band];
      if (i >= hold - 1 && sum > bestF) {
        bestF = sum;
        bestI = i;
      }
    }
    let bgSum = 0;
    for (let i = Math.max(0, bestI - hold + 1); i <= bestI; i++) bgSum += frames[i].b[band];
    const db = 10 * Math.log10((bestF + 1e-30) / (bgSum + 1e-30));
    if (db > best.db) best = { db, hz: Math.round(BANDS[band]), at: frames[bestI]?.at / MIX_RATE };
  }
  return best;
}

/** A level in dB over the stretch, all bands. */
function rms(x, from, to) {
  let e = 0;
  const a = Math.round(from * MIX_RATE);
  const b = Math.round(to * MIX_RATE);
  for (let i = a; i < b; i++) e += x[i] * x[i];
  return 10 * Math.log10(e / Math.max(1, b - a) + 1e-30);
}

const CREW = {
  diesel: {},
  dynamo: {},
  steam: { pressure_pct: 80, loaded: 1 },
  arc: { reach: 0.9 },
  feed: { rounds: 12, firing: 1 },
  repair: { repairing: 1 },
};
export const SEATS = Object.keys(CREW);

/**
 * A hard ride: a full crew on six seats at 100 rpm, the rider leading `seat` at 1.1 of target, the track at speed
 * and the night. `cues`, `loops`, `params`: the moment measured.
 */
export function hardRide(seat, { cues = [], loops = [], params = {}, seconds = 8, rpm = 100, power = 1.1, speed = 5 } = {}) {
  const machines = [{ id: 'lead', machine: seat, lead: true, params: { ...CREW[seat], power, ...params } }];
  for (const m of SEATS) {
    if (m !== seat) machines.push({ id: m, machine: m, lead: false, rpm_scale: 0.97, params: { ...CREW[m], power: 0.95 } });
  }
  machines.push({ id: 'track', machine: 'track', lead: true, rpm_by: { param: 'speed', ratio: 0.04 } });
  return {
    segments: [{ rpm, s: seconds, params: { power, speed, liftoff: 0, ...params } }],
    machines,
    bed: 'night_forest',
    bed_params: { gust: 0.5, combat: 1 },
    cues,
    loops,
    seed: 3,
  };
}

export function openBank(edit = null) {
  const doc = loadBank(BANK);
  if (edit) edit(doc);
  return new BankAudio(doc, DIR);
}

/**
 * Renders a scenario, splits the voices and tracks `pick` chooses from the rest, and scores them over `from`..`to`.
 * Ducks stay on the rest, as in the game. `minHz`: only bands from there up count.
 */
export function readOf(bank, scenario, pick, from, to, holdS = 0.2, minHz = 0) {
  const sim = simulate(bank, scenario);
  const isFg = (x) => pick(x.sound);
  const fgSim = { ...sim, voices: sim.voices.filter(isFg), tracks: sim.tracks.filter(isFg), ducks: sim.ducks.filter((d) => d.bus !== 'Machines' && d.bus !== 'Ambience') };
  const bgSim = { ...sim, voices: sim.voices.filter((v) => !isFg(v)), tracks: sim.tracks.filter((t) => !isFg(t)) };
  const buses = ['Machines', 'Ambience', 'Sfx'];
  const fg = mono(mixdown(bank, fgSim).stems, buses);
  const bg = mono(mixdown(bank, bgSim).stems, buses);
  return { ...bestBand(fg, bg, from, to, holdS, minHz), fg_db: rms(fg, from, to), bg_db: rms(bg, from, to) };
}
