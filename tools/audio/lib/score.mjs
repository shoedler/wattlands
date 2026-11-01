// The scorecard: SPEC_AUDIO 6.2's game developer (D) and audio creator (A) rows, computed in pure JS
// from a bank's preview block. A row is {id, pass, value, target, note}. D8 and D10 live elsewhere
// (a GUT test and a bench). A failed A row may carry a waiver in preview.waive, except A1, A9, A11
// and A15; a D row never may.

import fs from 'node:fs';
import path from 'node:path';
import { allFiles, bankWavBytes, loadBank } from './bank.mjs';
import { bandFilter, bandShareDb, fft, gainToDb, powerSpectrum } from './dsp.mjs';
import { integratedLufs, loudnessRange, momentaryMaxLufs, momentaryTrack, truePeakDb } from './lufs.mjs';
import { earBand, onsetShape, shapeApart } from './ear_band.mjs';
import { BankAudio, MIX_RATE, PROMPT_VOICE_DB, STROKE_HORIZON_S, mixdown, renderVoice, segmentsLength, simulate } from './offline_mix.mjs';
import { curveEval, curvePasses } from './pattern.mjs';

/** Repo WAV caps in MB (SPEC 3.4). */
export const WAV_CAPS_MB = { tank: 7.0, fishing: 4.5, siege: 4.5, workout: 4.0, _shared: 0.3 };
export const WAV_TOTAL_CAP_MB = 20.5;
const UNWAIVABLE = new Set(['A1', 'A9', 'A11', 'A15']);
/** UI-bus built-ins held to the UI loudness row. A tick under 100 ms reads nothing on a 400 ms meter. */
export const UI_METERED = ['ui_confirm', 'ui_back', 'toast', 'phase', 'countdown', 'lap', 'results'];
/** The safety prompts, metered as HudLayer plays them. D5 needs them 6 LU over a -18 mix, ducks counted, which -17 cannot reach: see the ADR. */
export const ALERTS = ['warning', 'rescue'];
const SOLO_REVS = 10;
const LEVELS = { mix: [-20, -16], lra: [4, 14], tp: -1, machines: [-24, -20], other: [8, 12], ambience: [-35, -29], sfx: [-17, -11], ui: [-23, -17], alert: [-23, -15] };

function round(v, d = 2) {
  const k = Math.pow(10, d);
  return Math.round(v * k) / k;
}

function mono(stem) {
  return stem[0].map((v, i) => (v + stem[1][i]) * 0.5);
}

function rmsDb(x, from = 0, to = x.length) {
  let s = 0;
  for (let i = from; i < to; i++) s += x[i] * x[i];
  return to > from ? 10 * Math.log10(s / (to - from) + 1e-30) : -300;
}

function peakDb(x) {
  let m = 0;
  for (let i = 0; i < x.length; i++) m = Math.max(m, Math.abs(x[i]));
  return gainToDb(m);
}

const D5_WINDOW_S = 0.6;
const D5_OTHER_BUSES = ['Machines', 'Ambience', 'Sfx', 'UI'];
/** Where D5 plays a prompt, from the start of the loudest 400 ms, and from each moment HudLayer sounds. */
const D5_AROUND_LOUDEST_S = [-0.4, -0.2, 0];
const D5_AROUND_HUD_S = [-0.4, -0.2, 0];
/** D4 reads the Machines bus this long after the stop. */
const D4_LATER_S = 0.4;
/** Long enough for a machine's strokes to go through their variants and pitch tables. */
const D4_SWEEP_S = 25;
/** D6: the ride, then a coast if the preview has one. */
const D6_RIDE_S = 30;
const D6_STOP_S = 10;

function sumOfBuses(mix, buses, from, to) {
  const out = [new Float64Array(to - from), new Float64Array(to - from)];
  for (const bus of buses) {
    for (let c = 0; c < 2; c++) {
      const b = mix.stems[bus][c];
      for (let i = from; i < to; i++) out[c][i - from] += b[i];
    }
  }
  return out;
}

/** The start of the loudest 400 ms of everything a safety prompt plays over. */
function loudestMomentS(mix) {
  let best = { t: 0, lufs: -Infinity };
  const n = mix.stems.Machines[0].length;
  for (const m of momentaryTrack(sumOfBuses(mix, D5_OTHER_BUSES, 0, n), MIX_RATE)) {
    if (m.lufs > best.lufs) best = m;
  }
  return best.t;
}

function leadMachine(p) {
  return { id: 'lead', machine: p.lead, lead: true };
}

function otherMachines(p) {
  return (p.others ?? []).map((o, i) => ({ id: `other${i}`, machine: o.machine, lead: o.lead === true, rpm_scale: o.rpm_scale, rpm_by: o.rpm_by, params: o.params }));
}

/** The preview scenario: lead, others, bed, scripted cues. */
export function previewScenario(doc, { rpms = null } = {}) {
  const p = doc.preview;
  return {
    segments: applyRpms(p.segments, rpms),
    machines: [leadMachine(p), ...otherMachines(p)],
    bed: p.bed,
    bed_params: p.bed_params,
    cues: p.events ?? [],
    loops: p.loops ?? [],
    hud: p.hud ?? [],
    seed: p.seed ?? 1,
  };
}

/** The Machines bus's loudest 20 ms from `later` s after a stop on, for `span` s. */
function levelAfterStop(mix, stopAt, later, span) {
  const m = mono(mix.stems.Machines);
  const from = Math.round((stopAt + later) * MIX_RATE);
  const to = Math.min(m.length, Math.round((stopAt + later + span) * MIX_RATE));
  let level = -300;
  for (let i = from; i + 882 <= to; i += 882) level = Math.max(level, rmsDb(m, i, i + 882));
  return level;
}

/** The loudest 20 ms of a stroke's own ring, `after` s from its start on. */
function ringDb(file, v, after) {
  const step = (file.rate * v.pitch) / MIX_RATE;
  const x = file.data[0];
  let worst = -300;
  for (let at = Math.round(after * MIX_RATE); ; at += 882) {
    const pos = file.preroll + at * step;
    if (pos >= file.frames) break;
    let e = 0;
    let n = 0;
    for (let i = 0; i < 882; i++) {
      const k = Math.floor(pos + i * step);
      if (k >= file.frames) break;
      e += x[k] * x[k];
      n++;
    }
    worst = Math.max(worst, 10 * Math.log10(e / n + 1e-30) + v.db);
  }
  return worst;
}

/**
 * D4 for a stop anywhere in the cycle, not only where the preview happens to stop, without rendering a
 * stop per stroke: the worst stop for a stroke is the one just before it, which starts it up to a horizon
 * late. Every stroke of the machines at each cadence, under the preview's hardest load, its last segment's.
 */
function d4Sweep(bank, p, moving) {
  const params = moving[moving.length - 1]?.params ?? {};
  let worst = { level: -300, note: '' };
  for (const rpm of new Set(moving.map((s) => s.rpm))) {
    const sim = simulate(bank, { segments: [{ rpm, s: D4_SWEEP_S, params }], machines: [leadMachine(p), ...otherMachines(p)] });
    for (const v of sim.voices) {
      if (v.bus !== 'Machines') continue;
      const level = ringDb(bank.file(v.sound, v.variant), v, D4_LATER_S - STROKE_HORIZON_S);
      if (level > worst.level) worst = { level, note: `${v.sound} at ${rpm} rpm` };
    }
  }
  return worst;
}

/** D6's eight riders as the game has them: the lead's own other machines, its loops, its cues, and a coast. */
function eightRiderScenario(p, moving, seg) {
  const ride = moving[moving.length - 1]?.params ?? {};
  const stop = seg.find((s) => s.rpm <= 0);
  const pool = (p.others ?? []).filter((o) => o.lead !== true);
  const riders = [];
  for (let i = 0; i < 7; i++) {
    const o = pool.length > 0 ? pool[i % pool.length] : { machine: p.lead };
    riders.push({ id: `rider${i}`, machine: o.machine, lead: false, rpm_scale: (88 + (24 * i) / 6) / 100, params: o.params });
  }
  const held = new Map();
  for (const l of p.loops ?? []) held.set(l.id, { ...l, t0: 0, t1: Infinity });
  return {
    segments: [{ rpm: 100, s: D6_RIDE_S, params: ride }, ...(stop ? [{ rpm: 0, s: D6_STOP_S, params: stop.params }] : [])],
    machines: [leadMachine(p), ...otherMachines(p).filter((m) => m.lead), ...riders],
    bed: p.bed,
    bed_params: p.bed_params,
    loops: [...held.values()],
    cues: (p.events ?? []).map((e) => ({ ...e, t: e.t % D6_RIDE_S })),
    seed: 2,
  };
}

/** --rpm=60,90,110 replaces the moving segments' rpm in order; the rest (a stop) stay. */
export function applyRpms(segments, rpms) {
  if (!rpms) return segments;
  let k = 0;
  return segments.map((s) => (s.rpm > 0 && k < rpms.length ? { ...s, rpm: rpms[k++] } : s));
}

export function movingSegments(doc) {
  return doc.preview.segments.filter((s) => s.rpm > 0);
}

/** One machine alone, SOLO_REVS revolutions at rpm: {sum, sim, duration, seconds per rev}. */
export function renderSolo(bank, machine, seg, { strokes = true, loops = true, tail = 0 } = {}) {
  const duration = (SOLO_REVS * 60) / seg.rpm;
  const sim = simulate(bank, {
    segments: [{ rpm: seg.rpm, s: duration, params: seg.params ?? {} }],
    machines: [{ id: 'lead', machine, lead: true, strokes, loops }],
    duration,
  });
  const mix = mixdown(bank, sim, { tail });
  return { x: mono(mix.stems.Machines), sim, duration, perRev: 60 / seg.rpm };
}

/** A copy of the bank whose machine holds a single event entry, no loops. */
function oneEntryBank(bank, machine, ev, at) {
  const def = bank.doc.machines[machine];
  const doc = { ...bank.doc, machines: { ...bank.doc.machines, [machine]: { ...def, events: [{ ...ev, at: [at] }], loops: [] } } };
  const copy = new BankAudio(doc, bank.dir);
  copy._cache = bank._cache;
  return copy;
}

/** How many k + f lie in (0, revs]. */
function patternCount(f, revs) {
  return Math.floor(revs - f) + (f > 0 ? 1 : 0);
}

// --- Onsets ---

/** Attack times of a strokes-only signal: a sharp rise of a fast envelope, min 20 ms apart. */
export function detectOnsets(x, rate = MIX_RATE) {
  const peak = x.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
  if (peak <= 0) return [];
  const floor = peak * 0.08;
  const gap = Math.round(0.02 * rate);
  const fast = 1 / (0.0007 * rate);
  const slow = 1 / (0.012 * rate);
  let e = 0;
  let s = 0;
  const out = [];
  let last = -gap;
  for (let i = 0; i < x.length; i++) {
    const a = Math.abs(x[i]);
    e += (a - e) * (a > e ? fast : fast * 0.4);
    s += (a - s) * slow;
    if (i - last >= gap && a > floor && e > 2.2 * s) {
      out.push(i / rate);
      last = i;
    }
  }
  return out;
}

/** D1, D2: each event entry of the machine alone, at each rpm, against k + f. */
function strokeRows(bank, doc, rows) {
  const p = doc.preview;
  const def = doc.machines[p.lead];
  let worstCount = 0;
  let worstIoi = 0;
  const notes = [];
  for (const seg of movingSegments(doc)) {
    const params = { ...seg.params, rpm: seg.rpm };
    const seen = new Set();
    for (const ev of def.events ?? []) {
      for (const at of [ev.at].flat()) {
        const key = `${ev.sound}@${at}`;
        if (seen.has(key)) continue;
        seen.add(key);
        if (!curvePasses(ev.when, params)) continue;
        const solo = renderSolo(oneEntryBank(bank, p.lead, ev, at), p.lead, seg, { loops: false, tail: 0.5 });
        const onsets = detectOnsets(solo.x);
        // The plan runs one horizon past the end of the render: count only the pattern's own strokes.
        const fires = patternCount(at, SOLO_REVS);
        const planned = solo.sim.voices.filter((v) => v.t <= solo.duration + 1e-6).length;
        const seen2 = onsets.filter((t) => t <= solo.duration + 0.001).length;
        const miss = Math.max(Math.abs(seen2 - fires), Math.abs(planned - fires));
        if (miss > worstCount) {
          worstCount = miss;
          notes.push(`${key} at ${seg.rpm} rpm: ${seen2} onsets, ${planned} planned, ${fires} in the pattern`);
        }
        const per = 60 / seg.rpm;
        for (let i = 1; i < onsets.length; i++) worstIoi = Math.max(worstIoi, Math.abs(onsets[i] - onsets[i - 1] - per));
      }
    }
  }
  rows.push({ id: 'D1', pass: worstCount === 0, value: worstCount, target: 'onsets per revolution exact', note: notes.slice(0, 3).join('; ') });
  rows.push({ id: 'D2', pass: worstIoi * 1000 <= 1, value: round(worstIoi * 1000, 3), target: 'inter-onset error <= 1 ms' });
}

// --- Envelope helpers ---

function envelopeOf(x, smoothS, rate = MIX_RATE, hop = 32) {
  const k = 1 - Math.exp(-1 / (smoothS * rate));
  const out = new Float64Array(Math.floor(x.length / hop));
  let e = 0;
  for (let i = 0; i < out.length * hop; i++) {
    e += (Math.abs(x[i]) - e) * k;
    if (i % hop === 0) out[i / hop] = e;
  }
  return { env: out, rate: rate / hop };
}

function corr(a, b) {
  const n = Math.min(a.length, b.length);
  let ma = 0;
  let mb = 0;
  for (let i = 0; i < n; i++) {
    ma += a[i];
    mb += b[i];
  }
  ma /= n;
  mb /= n;
  let num = 0;
  let da = 0;
  let db = 0;
  for (let i = 0; i < n; i++) {
    const x = a[i] - ma;
    const y = b[i] - mb;
    num += x * y;
    da += x * x;
    db += y * y;
  }
  return da > 0 && db > 0 ? num / Math.sqrt(da * db) : 0;
}

/**
 * Flux stdev / (mean + 2 % of the frame's magnitude). The window resolves a 55 Hz drone, so a steady
 * tone has next to no flux, and the floor keeps the ratio of two tiny numbers from reading as motion.
 */
function spectralFluxRatio(x, size = 2048, hop = 512) {
  const re = new Float64Array(size);
  const im = new Float64Array(size);
  const prev = new Float64Array(size / 2 + 1);
  const flux = [];
  let magnitude = 0;
  for (let at = 0; at + size <= x.length; at += hop) {
    for (let i = 0; i < size; i++) {
      re[i] = x[at + i] * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / size));
      im[i] = 0;
    }
    fft(re, im);
    let f = 0;
    for (let k = 0; k <= size / 2; k++) {
      const m = Math.sqrt(re[k] * re[k] + im[k] * im[k]);
      f += Math.max(0, m - prev[k]);
      magnitude += m;
      prev[k] = m;
    }
    flux.push(f);
  }
  flux.shift();
  const count = Math.max(1, flux.length);
  const mean = flux.reduce((a, b) => a + b, 0) / count;
  const v = flux.reduce((a, b) => a + (b - mean) * (b - mean), 0) / count;
  const floor = (0.02 * magnitude) / (count + 1);
  return mean + floor > 0 ? Math.sqrt(v) / (mean + floor) : 0;
}

function centroid(x, rate = MIX_RATE, size = 4096) {
  const p = powerSpectrum(x, size);
  let a = 0;
  let b = 0;
  for (let k = 0; k < p.length; k++) {
    const m = Math.sqrt(p[k]);
    a += ((k * rate) / size) * m;
    b += m;
  }
  return b > 0 ? a / b : 0;
}

function bandDb(x, lo, hi, rate = MIX_RATE, size = 4096) {
  const p = powerSpectrum(x, size);
  let s = 0;
  for (let k = 0; k < p.length; k++) {
    const f = (k * rate) / size;
    if (f >= lo && f < hi) s += p[k];
  }
  return 10 * Math.log10(s + 1e-30);
}

const THIRD_OCTAVES = Array.from({ length: 22 }, (_, i) => 63 * Math.pow(2, i / 3)).filter((f) => f <= 8000);

/** 1/3-octave levels, normalized to the total, floored at -60 dB. */
function thirdOctaveShape(power, rate, size) {
  const bands = THIRD_OCTAVES.map(() => 0);
  let total = 0;
  for (let k = 0; k < power.length; k++) {
    const f = (k * rate) / size;
    total += power[k];
    THIRD_OCTAVES.forEach((c, i) => {
      if (f >= c * Math.pow(2, -1 / 6) && f < c * Math.pow(2, 1 / 6)) bands[i] += power[k];
    });
  }
  return bands.map((b) => Math.max(-60, 10 * Math.log10(b / (total || 1) + 1e-12)));
}

function averageShape(bank, ids) {
  const size = 2048;
  const sum = new Float64Array(size / 2 + 1);
  let rate = 22050;
  for (const id of ids) {
    const f = bank.file(id, 0);
    rate = f.rate;
    const p = powerSpectrum(f.data[0].subarray(f.preroll), size);
    let total = 0;
    for (let k = 0; k < p.length; k++) total += p[k];
    for (let k = 0; k < p.length; k++) sum[k] += total > 0 ? p[k] / total : 0;
  }
  return thirdOctaveShape(sum, rate, size);
}

// --- Projectiles ---

const P_FLIGHT_MARGIN_DB = 3;
const P_IMPACT_MARGIN_DB = 3;
const P_SURFACE_APART_DB = 3;
const P_FLIGHTS_APART_DB = 3;
const P_PEAK_OVER_ALL_DB = 3;
const P_MIX_APART_DB = 3;
const P_FLIGHT_BAND = [800, 6000];
const P_IMPACT_BAND = [400, 6000];

/** A voice's loudest `span` s in a band, against the (already band-limited) background in the same moment: dB over it. */
function voiceOverBackground(bank, v, background, band, span) {
  const x = bandFilter(renderVoice(bank, v), band[0], band[1], MIX_RATE);
  const at = Math.max(0, Math.round(v.t * MIX_RATE));
  const win = Math.min(Math.round(span * MIX_RATE), x.length);
  let best = -Infinity;
  let bestAt = 0;
  for (let a = 0; a + win <= x.length; a += Math.max(1, Math.round(win / 2))) {
    const level = rmsDb(x, a, a + win);
    if (level > best) {
      best = level;
      bestAt = a;
    }
  }
  return best - rmsDb(background, at + bestAt, Math.min(background.length, at + bestAt + win));
}

/** The same against everything else that is playing: `whole` is the unfiltered mix of the voice's bus and the rest, the voice in it. */
function voiceOverRest(bank, v, whole, band, span) {
  const voice = renderVoice(bank, v);
  const at = Math.max(0, Math.round(v.t * MIX_RATE));
  const lead = Math.round(0.05 * MIX_RATE);
  const from = Math.max(0, at - lead);
  const to = Math.min(whole.length, at + voice.length);
  const rest = Float64Array.from(whole.subarray(from, to));
  for (let i = 0; i < voice.length && at - from + i < rest.length; i++) rest[at - from + i] -= voice[i];
  const back = bandFilter(rest, band[0], band[1], MIX_RATE);
  const x = bandFilter(voice, band[0], band[1], MIX_RATE);
  const win = Math.min(Math.round(span * MIX_RATE), x.length);
  let best = -Infinity;
  let bestAt = 0;
  for (let a = 0; a + win <= x.length; a += Math.max(1, Math.round(win / 2))) {
    const level = rmsDb(x, a, a + win);
    if (level > best) {
      best = level;
      bestAt = a;
    }
  }
  return best - rmsDb(back, at - from + bestAt, Math.min(back.length, at - from + bestAt + win));
}

function median(sorted) {
  const n = sorted.length;
  if (n === 0) return -Infinity;
  return n % 2 === 1 ? sorted[(n - 1) / 2] : 0.5 * (sorted[n / 2 - 1] + sorted[n / 2]);
}

/** A flight's own loop as it plays, at the pitch its curve is at halfway: what a rider hears mid-air. */
function flightShape(bank, hit) {
  const f = bank.file(hit.sound, 0);
  const p = (hit.pitch ?? 1) * (hit.flight.pitch ? curveEval({ param: 'u', points: hit.flight.pitch }, { u: 0.5 }) : 1);
  const size = 2048;
  const power = powerSpectrum(f.data[0], size);
  // A pitch moves every bin up by p: read the spectrum at the bin the shifted one came from.
  const moved = new Float64Array(power.length);
  for (let k = 0; k < power.length; k++) {
    const from = k / p;
    const i = Math.floor(from);
    moved[k] = i + 1 < power.length ? power[i] + (power[i + 1] - power[i]) * (from - i) : 0;
  }
  return thirdOctaveShape(moved, f.rate, size);
}

function shapeDistance(a, b) {
  return Math.sqrt(a.reduce((acc, v, k) => acc + (v - b[k]) * (v - b[k]), 0) / a.length);
}

/**
 * P1-P9, for a bank whose preview says preview.checks.projectiles: {shots: [cue...], surfaces: {name: [cue...]}}. An
 * offline card passed a game nobody could hear arrows in, because nothing asked whether a shot had a sound that lasted
 * its flight, or whether that sound stood out of the mix. These ask.
 */
function projectileRows(bank, p, sim, mix, rows) {
  const spec = p.checks?.projectiles;
  const targets = {
    P1: 'flight sounds started per shot: 1 for every weapon',
    P2: 'a flight sound lasts its flight',
    P3: `a flight's loudest 250 ms is >= +${P_FLIGHT_MARGIN_DB} dB over the wheels and the bed, ${P_FLIGHT_BAND.join('-')} Hz (not over other flights: P8)`,
    P4: `every impact cue is in the preview, each surface's median impact >= +${P_IMPACT_MARGIN_DB} dB over everything else that plays, ${P_IMPACT_BAND.join('-')} Hz`,
    P5: `surfaces differ: spectra >= ${P_SURFACE_APART_DB} dB apart`,
    P6: `2-8 kHz of the master <= ${p.checks?.ear_band?.limit ?? '?'} dB of its total`,
    P7: `flights differ: spectra at their pitch >= ${P_FLIGHTS_APART_DB} dB apart`,
    P8: `the rider's own flight at full level, its loudest 250 ms over everything else, flights too, in its band: median >= +${P_PEAK_OVER_ALL_DB} dB`,
    P9: `in the mix, first 60 ms of an impact: a target >= ${P_MIX_APART_DB} dB apart from the ground`,
  };
  if (!spec) {
    for (const id of Object.keys(targets)) rows.push({ id, pass: true, value: 'n/a', target: 'preview.checks.projectiles not set' });
    return;
  }
  const events = p.events ?? [];
  const perShot = spec.shots.map((cue) => {
    const shots = events.filter((e) => e.cue === cue).length;
    const flights = sim.voices.filter((v) => v.cue === cue && v.flight).length;
    return { cue, shots, flights, ratio: shots > 0 ? flights / shots : 0 };
  });
  rows.push({ id: 'P1', pass: perShot.every((s) => s.ratio === 1), value: perShot.map((s) => `${s.cue} ${s.flights}/${s.shots}`).join(', '), target: targets.P1 });
  const flights = sim.voices.filter((v) => v.flight && spec.shots.includes(v.cue));
  let shortest = flights.length > 0 ? Infinity : 0;
  for (const v of flights) shortest = Math.min(shortest, (v.end - v.t) / v.flight.dur);
  rows.push({ id: 'P2', pass: shortest >= 0.99, value: round(shortest), target: targets.P2 });

  const n = mix.n;
  const whole = new Float64Array(n);
  for (const bus of ['Machines', 'Ambience']) {
    const stem = mono(mix.stems[bus]);
    for (let i = 0; i < n; i++) whole[i] += stem[i];
  }
  const flightBack = bandFilter(whole, P_FLIGHT_BAND[0], P_FLIGHT_BAND[1], MIX_RATE);
  // An impact has to rise out of the flights as well as the wheel.
  const everything = Float64Array.from(whole);
  const sfxStem = mono(mix.stems.Sfx);
  for (let i = 0; i < n; i++) everything[i] += sfxStem[i];
  let quiet = Infinity;
  let quietWhat = '';
  for (const v of flights) {
    const over = voiceOverBackground(bank, v, flightBack, P_FLIGHT_BAND, 0.25);
    if (over < quiet) {
      quiet = over;
      quietWhat = `${v.sound} at ${round(v.t, 1)} s`;
    }
  }
  rows.push({ id: 'P3', pass: quiet >= P_FLIGHT_MARGIN_DB, value: `+${round(quiet)} dB`, target: targets.P3, note: quietWhat });

  const surfaces = Object.entries(spec.surfaces);
  const missing = surfaces.flatMap(([, cues]) => cues).filter((cue) => !events.some((e) => e.cue === cue));
  // Per surface the median impact: a stroke of the wheel can land on any one of them, and that is no fault of the sound.
  let quietHit = Infinity;
  let quietHitWhat = '';
  let worstOne = Infinity;
  const medians = [];
  for (const [surface, cues] of surfaces) {
    const overs = [];
    for (const v of sim.voices.filter((x) => cues.includes(x.cue) && x.sound === bank.doc.cues[x.cue].hits[0].sound)) {
      overs.push(voiceOverRest(bank, v, everything, P_IMPACT_BAND, 0.05));
    }
    overs.sort((x, y) => x - y);
    const mid = median(overs);
    medians.push(`${surface} ${round(mid)}`);
    if (overs.length > 0) worstOne = Math.min(worstOne, overs[0]);
    if (mid < quietHit) {
      quietHit = mid;
      quietHitWhat = surface;
    }
  }
  rows.push({
    id: 'P4',
    pass: missing.length === 0 && quietHit >= P_IMPACT_MARGIN_DB,
    value: missing.length > 0 ? `missing ${missing.join(', ')}` : `${surfaces.length} surfaces, quietest median +${round(quietHit)} dB`,
    target: targets.P4,
    note: `${medians.join(', ')}; the worst single impact ${round(worstOne)} dB`,
  });
  const shapes = surfaces.map(([surface, cues]) => {
    const sounds = cues.map((c) => bank.doc.cues[c]?.hits?.[0]?.sound).filter(Boolean);
    return { surface, shape: averageShape(bank, sounds) };
  });
  let closest = Infinity;
  let closestWhat = '';
  for (let i = 0; i < shapes.length; i++) {
    for (let j = i + 1; j < shapes.length; j++) {
      const a = shapes[i].shape;
      const b = shapes[j].shape;
      const d = Math.sqrt(a.reduce((acc, v, k) => acc + (v - b[k]) * (v - b[k]), 0) / a.length);
      if (d < closest) {
        closest = d;
        closestWhat = `${shapes[i].surface} and ${shapes[j].surface}`;
      }
    }
  }
  rows.push({ id: 'P5', pass: closest >= P_SURFACE_APART_DB, value: round(closest), target: targets.P5, note: closestWhat });

  const limit = p.checks?.ear_band?.limit;
  if (limit === undefined) rows.push({ id: 'P6', pass: true, value: 'n/a', target: 'preview.checks.ear_band not set' });
  else {
    const e = earBand(mono(mix.master));
    rows.push({ id: 'P6', pass: e.share <= limit, value: round(e.share), target: targets.P6, note: `loudest frame ${round(e.worst)}` });
  }

  const own = spec.own_flight;
  if (!own) rows.push({ id: 'P8', pass: true, value: 'n/a', target: 'preview.checks.projectiles.own_flight not set' });
  else {
    const mine = sim.voices.filter((v) => v.flight && v.cue === own.cue && v.lead);
    const top = Math.max(-200, ...mine.map((v) => v.db));
    const overs = mine.filter((v) => v.db >= top - 1).map((v) => voiceOverRest(bank, v, everything, own.band, 0.25)).sort((x, y) => x - y);
    const mid = median(overs);
    rows.push({ id: 'P8', pass: mid >= P_PEAK_OVER_ALL_DB, value: `${mid >= 0 ? '+' : ''}${round(mid)} dB`, target: `${targets.P8}, ${own.band.join('-')} Hz`, note: `${overs.length} flights of ${own.cue}` });
  }

  const ground = spec.surfaces.dirt;
  const masterMono = mono(mix.master);
  const starts = (cues) => sim.voices.filter((v) => cues.includes(v.cue) && v.sound === bank.doc.cues[v.cue].hits[0].sound).map((v) => v.t);
  if (!ground) rows.push({ id: 'P9', pass: true, value: 'n/a', target: 'no dirt surface' });
  else {
    const groundShape = onsetShape(masterMono, starts(ground));
    let nearest = Infinity;
    let nearestWhat = '';
    const parts = [];
    for (const [surface, cues] of surfaces) {
      if (surface === 'dirt' || surface === 'water') continue;
      const d = shapeApart(onsetShape(masterMono, starts(cues)), groundShape);
      if (d === null) continue;
      parts.push(`${surface} ${round(d)}`);
      if (d < nearest) {
        nearest = d;
        nearestWhat = surface;
      }
    }
    rows.push({ id: 'P9', pass: nearest >= P_MIX_APART_DB, value: parts.join(', '), target: targets.P9, note: `nearest: ${nearestWhat}` });
  }

  const flightHits = spec.shots.flatMap((cue) => (bank.doc.cues[cue]?.hits ?? []).filter((h) => h.flight).map((h) => ({ cue, hit: h })));
  const flightShapes = flightHits.map(({ cue, hit }) => ({ cue, shape: flightShape(bank, hit) }));
  let flightsApart = Infinity;
  let flightsWhat = '';
  for (let i = 0; i < flightShapes.length; i++) {
    for (let j = i + 1; j < flightShapes.length; j++) {
      const d = shapeDistance(flightShapes[i].shape, flightShapes[j].shape);
      if (d < flightsApart) {
        flightsApart = d;
        flightsWhat = `${flightShapes[i].cue} and ${flightShapes[j].cue}`;
      }
    }
  }
  if (flightShapes.length < 2) rows.push({ id: 'P7', pass: true, value: 'n/a', target: 'fewer than two flights' });
  else rows.push({ id: 'P7', pass: flightsApart >= P_FLIGHTS_APART_DB, value: round(flightsApart), target: targets.P7, note: flightsWhat });
}

// --- The card ---

/** A curve's highest value, or 1 for none. */
function curvesMax(curves) {
  return (curves ?? []).reduce((acc, c) => acc * Math.max(...(c.points ?? [[0, 1]]).map((pt) => pt[1])), 1);
}

/**
 * Each sound's highest pitch at runtime, from every place the bank plays it: a loop's pitch_by, a stroke's pitch_table, a
 * spot's range, a cue hit's pitch with its flight's curve and the largest value its pitch_var takes in the preview.
 */
export function runtimePitches(doc) {
  const out = new Map();
  const up = (id, p) => out.set(id, Math.max(out.get(id) ?? 1, p));
  for (const m of Object.values(doc.machines ?? {})) {
    for (const ev of m.events ?? []) up(ev.sound, Math.min(1.2, (ev.pitch ?? 1) * (1 + Math.max(0, ...(ev.pitch_table ?? [0])))));
    for (const l of m.loops ?? []) up(l.sound, curvesMax(l.pitch_by));
  }
  for (const l of Object.values(doc.loops ?? {})) for (const layer of l.layers ?? []) up(layer.sound, curvesMax(layer.pitch_by));
  for (const b of Object.values(doc.beds ?? {})) {
    for (const layer of b.layers ?? []) up(layer.sound, curvesMax(layer.pitch_by));
    for (const s of b.spots ?? []) up(s.sound, Array.isArray(s.pitch) ? s.pitch[1] : (s.pitch ?? 1));
  }
  const vars = new Map();
  for (const e of doc.preview?.events ?? []) {
    for (const [k, v] of Object.entries(e.vars ?? {})) vars.set(k, Math.max(vars.get(k) ?? 1, Number(v) || 1));
  }
  for (const c of Object.values(doc.cues ?? {})) {
    for (const h of c.hits ?? []) {
      const bend = h.flight?.pitch ? Math.max(...h.flight.pitch.map((pt) => pt[1])) : 1;
      up(h.sound, (h.pitch ?? 1) * bend * (h.pitch_var ? (vars.get(h.pitch_var) ?? 1) : 1));
    }
  }
  return out;
}

function fixedRows(doc, dir, rows, root) {
  // A9, A11: every file of the bank. A17 reads A9 where a file plays: a pitch of 1.4 moves 7 kHz up over 9.8.
  let worstA9 = -Infinity;
  let worstA9File = '';
  let worstA17 = -Infinity;
  let worstA17File = '';
  let worstA11 = 0;
  let worstA11File = '';
  const bank = new BankAudio(doc, dir);
  const pitches = runtimePitches(doc);
  for (const f of allFiles(doc)) {
    const a = bank.file(f.id, f.variant);
    if (a.rate === 22050) {
      const top = 9800 / (pitches.get(f.id) ?? 1);
      for (const x of a.data) {
        const pitched = bandShareDb(x, a.rate, top, 11026);
        if (pitched > worstA17) {
          worstA17 = pitched;
          worstA17File = f.stem;
        }
        const share = bandShareDb(x, a.rate, 9800, 11026);
        if (share > worstA9) {
          worstA9 = share;
          worstA9File = f.stem;
        }
      }
    }
    if (a.loopFrames > 0) {
      for (const x of a.data) {
        const n = a.loopFrames;
        const steps = new Float64Array(n - 1);
        for (let i = 1; i < n; i++) steps[i - 1] = Math.abs(x[i] - x[i - 1]);
        steps.sort();
        const median = steps[Math.floor(steps.length / 2)] || 1 / 32768;
        const ratio = Math.abs(x[n - 1] - x[0]) / median;
        if (ratio > worstA11) {
          worstA11 = ratio;
          worstA11File = f.stem;
        }
      }
    }
  }
  rows.push({ id: 'A9', pass: worstA9 <= -32, value: round(worstA9), target: '>9.8 kHz <= -32 dB', note: worstA9File });
  // Reported for every bank; held where the bank asks, so a game whose engine loop climbs an octave is not failed by a row it never met.
  const a17Held = doc.preview?.checks?.a17 === true;
  rows.push({
    id: 'A17',
    pass: !a17Held || worstA17 <= -32,
    value: round(worstA17),
    target: a17Held ? '>9.8 kHz at runtime pitch <= -32 dB' : '>9.8 kHz at runtime pitch: reported, preview.checks.a17 holds it to -32 dB',
    note: worstA17File,
  });
  rows.push({ id: 'A11', pass: worstA11 <= 3, value: round(worstA11), target: 'loop seam <= 3x median step', note: worstA11File });
  if (root && WAV_CAPS_MB[doc.game] !== undefined) {
    const mb = bankWavBytes(path.join(root, 'assets', doc.game, 'audio', 'audio.json')) / 1e6;
    rows.push({ id: 'D9', pass: mb <= WAV_CAPS_MB[doc.game], value: round(mb, 3), target: `<= ${WAV_CAPS_MB[doc.game]} MB` });
  } else {
    rows.push({ id: 'D9', pass: true, value: 'n/a', target: 'no cap for this bank' });
  }
}

/** Score one bank that has a preview block. shared: the _shared bank (BankAudio). */
export function scoreBank(doc, dir, { shared, root = null, rpms = null, stems = null } = {}) {
  const rows = [];
  const bank = new BankAudio(doc, dir);
  const p = doc.preview;
  const scenario = previewScenario(doc, { rpms });
  const sim = simulate(bank, { ...scenario, shared });
  const mix = mixdown(bank, sim, { shared });
  const mixRate = MIX_RATE;
  const seg = applyRpms(p.segments, rpms);
  const moving = seg.filter((s) => s.rpm > 0);

  strokeRows(bank, { ...doc, preview: { ...p, segments: seg } }, rows);

  // Lead solos: D3, A3, A4, A5.
  let d3 = 0;
  let a3 = Infinity;
  let a4 = Infinity;
  let a5Lo = Infinity;
  let a5Hi = -Infinity;
  const leadRender = simulate(bank, { segments: seg, machines: [leadMachine(p)], seed: 1 });
  for (const s of moving) {
    const solo = renderSolo(bank, p.lead, s);
    const { env, rate } = envelopeOf(solo.x, 0.004);
    const per = solo.perRev;
    const lagC = Math.round(per * rate);
    const span = Math.round(0.12 * lagC);
    let best = lagC;
    let bestV = -Infinity;
    const mean = env.reduce((a, b) => a + b, 0) / env.length;
    for (let lag = lagC - span; lag <= lagC + span; lag++) {
      let v = 0;
      for (let i = 0; i + lag < env.length; i++) v += (env[i] - mean) * (env[i + lag] - mean);
      v /= env.length - lag;
      if (v > bestV) {
        bestV = v;
        best = lag;
      }
    }
    d3 = Math.max(d3, Math.abs(best / rate - per) / per);
    // From the second revolution: the loops' 100 ms opening is not the engine's motion.
    a3 = Math.min(a3, spectralFluxRatio(solo.x.subarray(Math.round(per * MIX_RATE))));
    a4 = Math.min(a4, peakDb(solo.x) - rmsDb(solo.x));
    const revSamples = Math.round(per * rate);
    let c = 0;
    let cn = 0;
    for (let k = 1; k + 1 < SOLO_REVS; k++) {
      c += corr(env.subarray(k * revSamples, (k + 1) * revSamples), env.subarray((k + 1) * revSamples, (k + 2) * revSamples));
      cn++;
    }
    const rr = c / Math.max(1, cn);
    a5Lo = Math.min(a5Lo, rr);
    a5Hi = Math.max(a5Hi, rr);
  }
  rows.push({ id: 'D3', pass: d3 <= 0.01, value: round(d3 * 100, 3), target: 'autocorrelation peak within 1 % of 60/rpm' });

  // D4: the Machines bus after the stop.
  const stopAt = (() => {
    let t = 0;
    for (const s of seg) {
      if (s.rpm <= 0) return t;
      t += s.s;
    }
    return null;
  })();
  if (stopAt === null) rows.push({ id: 'D4', pass: false, value: 'no stop', target: 'preview needs a 0 rpm segment' });
  else {
    const here = levelAfterStop(mix, stopAt, D4_LATER_S, 2);
    const swept = d4Sweep(bank, p, moving);
    const level = Math.max(here, swept.level);
    rows.push({ id: 'D4', pass: level < -60, value: round(level), target: 'Machines below -60 dBFS 400 ms after a stop anywhere in the cycle', note: swept.note });
  }

  // D5: the safety prompts over the mix, ducking counted: at the mix's midpoint, and on and just before its loudest moment, where a duck that is already releasing meets what is coming.
  if (shared) {
    let worst = Infinity;
    let worstAt = null;
    const midT = segmentsLength(moving) / 2;
    const loudest = loudestMomentS(mix);
    const lengthS = segmentsLength(seg);
    const atHud = (p.hud ?? []).flatMap((h) => D5_AROUND_HUD_S.map((d) => h.t + d));
    const times = [...new Set([midT, ...D5_AROUND_LOUDEST_S.map((d) => loudest + d), ...atHud])].filter((t) => t >= 0 && t + D5_WINDOW_S <= lengthS);
    for (const name of ['warning', 'rescue']) {
      for (const t of times) {
        const promptSim = simulate(bank, { ...scenario, prompts: [{ t, name }], shared });
        const pm = mixdown(bank, promptSim, { shared });
        const from = Math.round(t * mixRate);
        const to = Math.round((t + D5_WINDOW_S) * mixRate);
        const slice = (st) => [st[0].subarray(from, to), st[1].subarray(from, to)];
        const others = sumOfBuses(pm, D5_OTHER_BUSES, from, to);
        const diff = momentaryMaxLufs(slice(pm.stems.Master), mixRate) - momentaryMaxLufs(others, mixRate);
        if (diff < worst) {
          worst = diff;
          worstAt = `${name} at ${round(t)} s`;
        }
      }
    }
    rows.push({ id: 'D5', pass: worst >= 6, value: round(worst), target: 'warning, rescue >= +6 LU over the mix, midpoint and loudest moment', note: worstAt });
  } else {
    rows.push({ id: 'D5', pass: false, value: 'no _shared bank', target: 'warning, rescue >= +6 LU over the mix, midpoint and loudest moment' });
  }

  // D6, D7: eight riders.
  const pool = (p.others ?? []).filter((o) => o.lead !== true);
  const ridersSim = simulate(bank, eightRiderScenario(p, moving, seg));
  const crowdCap = doc.mix?.crowd_voices ?? 0;
  const d6Pass = ridersSim.voicePeak.Machines <= 16 && ridersSim.voicePeak.Sfx <= 16 && ridersSim.loopPeak <= (doc.mix?.max_loop_players ?? 24) && ridersSim.voicePeak.Crowd <= crowdCap;
  rows.push({
    id: 'D6',
    pass: d6Pass,
    value: `${ridersSim.voicePeak.Machines}/${ridersSim.voicePeak.Sfx}/${ridersSim.loopPeak}${crowdCap > 0 ? `, crowd ${ridersSim.voicePeak.Crowd}` : ''}`,
    target: `Machines <= 16, Sfx <= 16, loops <= 24${crowdCap > 0 ? `, crowd <= ${crowdCap}` : ''}`,
  });
  const otherStarts = ridersSim.events.filter((e) => e.kind === 'stroke' && e.lead === false && !e.thinned).length;
  const perS = otherStarts / D6_RIDE_S;
  rows.push({ id: 'D7', pass: perS <= 16.7 + 1e-6, value: round(perS), target: 'other strokes <= 16.7 per s' });

  // A1, A2, A8, A15.
  const lufs = integratedLufs(mix.master, mixRate);
  const lra = loudnessRange(mix.master, mixRate);
  const tp = truePeakDb(mix.master);
  rows.push({
    id: 'A1',
    pass: lufs >= LEVELS.mix[0] && lufs <= LEVELS.mix[1] && lra >= LEVELS.lra[0] && lra <= LEVELS.lra[1] && tp <= LEVELS.tp,
    value: `${round(lufs)} LUFS, LRA ${round(lra)}, ${round(tp)} dBTP`,
    target: '-18 LUFS +-2, LRA 4-14, <= -1 dBTP',
  });
  const leadMix = mixdown(bank, leadRender);
  const machinesLufs = integratedLufs(leadMix.stems.Machines, mixRate);
  const a2 = [];
  let a2Pass = machinesLufs >= LEVELS.machines[0] && machinesLufs <= LEVELS.machines[1];
  a2.push(`Machines ${round(machinesLufs)}`);
  if (pool.length > 0) {
    // A lead that makes no sound keeps the other rider at other_db, not the spectators' +4.
    const silentLead = { id: 'lead', machine: p.lead, lead: true, strokes: false, loops: false };
    const oneSim = simulate(bank, { segments: seg, machines: [silentLead, otherMachines(p).find((m) => !m.lead)], seed: 1 });
    const oneLufs = integratedLufs(mixdown(bank, oneSim).stems.Machines, mixRate);
    const diff = machinesLufs - oneLufs;
    a2.push(`other -${round(diff)} LU`);
    if (diff < LEVELS.other[0] || diff > LEVELS.other[1]) a2Pass = false;
  }
  const amb = integratedLufs(mix.stems.Ambience, mixRate);
  a2.push(`Ambience ${round(amb)}`);
  if (amb < LEVELS.ambience[0] || amb > LEVELS.ambience[1]) a2Pass = false;
  if ((p.events ?? []).length > 0) {
    const sfx = momentaryMaxLufs(mix.stems.Sfx, mixRate);
    a2.push(`Sfx ${round(sfx)}`);
    if (sfx < LEVELS.sfx[0] || sfx > LEVELS.sfx[1]) a2Pass = false;
  }
  if (shared) {
    let lo = Infinity;
    let hi = -Infinity;
    for (const name of UI_METERED) {
      const f = shared.file(name, 0);
      const v = momentaryMaxLufs([f.data[0], f.data[0]], f.rate);
      lo = Math.min(lo, v);
      hi = Math.max(hi, v);
    }
    a2.push(`UI ${round(lo)}..${round(hi)}`);
    if (lo < LEVELS.ui[0] || hi > LEVELS.ui[1]) a2Pass = false;
    for (const name of ALERTS) {
      const f = shared.file(name, 0);
      const v = momentaryMaxLufs([f.data[0], f.data[0]], f.rate) + PROMPT_VOICE_DB;
      a2.push(`${name} ${round(v)}`);
      if (v < LEVELS.alert[0] || v > LEVELS.alert[1]) a2Pass = false;
    }
  }
  rows.push({ id: 'A2', pass: a2Pass, value: a2.join(', '), target: 'Machines -22 +-2, other -8..-12 LU, Ambience -32 +-3, Sfx -14 +-3, UI -20 +-3, prompts as played -23..-15' });
  rows.push({ id: 'A3', pass: a3 >= 0.35, value: round(a3), target: 'spectral flux stdev/mean >= 0.35' });
  rows.push({ id: 'A4', pass: a4 >= 8, value: round(a4), target: 'crest factor >= 8 dB' });
  rows.push({ id: 'A5', pass: a5Lo >= 0.6 && a5Hi <= 0.97, value: `${round(a5Lo)}..${round(a5Hi)}`, target: 'successive-revolution correlation 0.60..0.97' });

  const checks = p.checks ?? {};
  // A6, A7: load response at 90 rpm.
  const loadSolo = (param, value) => {
    const base = moving.find((s) => s.rpm === 90) ?? moving[0];
    return renderSolo(bank, p.lead, { rpm: base.rpm, params: { ...base.params, [param]: value } }).x;
  };
  if (checks.a6) {
    const lo = centroid(loadSolo(checks.a6.param, checks.a6.from));
    const hi = centroid(loadSolo(checks.a6.param, checks.a6.to));
    const rise = (hi / lo - 1) * 100;
    rows.push({ id: 'A6', pass: rise >= 20, value: `+${round(rise)} %`, target: 'centroid rises >= 20 % with load' });
  } else rows.push({ id: 'A6', pass: true, value: 'n/a', target: 'preview.checks.a6 not set' });
  if (checks.a7) {
    const lo = bandDb(loadSolo(checks.a7.param, checks.a7.from), 2000, 5000);
    const hi = bandDb(loadSolo(checks.a7.param, checks.a7.to), 2000, 5000);
    rows.push({ id: 'A7', pass: hi - lo >= 6, value: `+${round(hi - lo)} dB`, target: '2-5 kHz rises >= 6 dB with load' });
  } else rows.push({ id: 'A7', pass: true, value: 'n/a', target: 'preview.checks.a7 not set' });

  const shape = powerSpectrum(mono(mix.master), 4096);
  const share = (lo, hi) => {
    let part = 0;
    let total = 0;
    for (let k = 0; k < shape.length; k++) {
      const f = (k * mixRate) / 4096;
      total += shape[k];
      if (f >= lo && f < hi) part += shape[k];
    }
    return (100 * part) / (total || 1);
  };
  const shares = [share(0, 80), share(80, 500), share(500, 4000), share(4000, 1e6)];
  rows.push({
    id: 'A8',
    pass: shares[0] <= 35 && shares[1] >= 25 && shares[1] <= 60 && shares[2] >= 15 && shares[2] <= 45 && shares[3] >= 2 && shares[3] <= 20,
    value: shares.map((v) => `${round(v, 1)} %`).join(' / '),
    target: '<80 Hz <= 35, 80-500 25-60, 500-4k 15-45, >4k 2-20',
  });

  fixedRows(doc, dir, rows, root);

  // A10: this game's cue sounds against the UI family.
  const cueSounds = [...new Set(Object.values(doc.cues ?? {}).flatMap((c) => (c.hits ?? []).map((h) => h.sound)))];
  if (shared && cueSounds.length > 0) {
    const a = averageShape(bank, cueSounds);
    const b = averageShape(shared, Object.keys(shared.doc.sounds));
    const d = Math.sqrt(a.reduce((acc, v, i) => acc + (v - b[i]) * (v - b[i]), 0) / a.length);
    rows.push({ id: 'A10', pass: d <= 9, value: round(d), target: 'spectrum distance to the UI family <= 9 dB' });
  } else rows.push({ id: 'A10', pass: true, value: 'n/a', target: 'no cues' });

  // A12: the bed's envelope at each layer's length, on a 30 s solo or two lengths if longer.
  if (p.bed) {
    const layers = doc.beds[p.bed].layers ?? [];
    const lengths = layers.map((l) => bank.file(l.sound, 0)).map((f) => (f.loopFrames || f.frames) / f.rate);
    const len = Math.max(30, 2.2 * Math.max(0, ...lengths));
    const bedSim = simulate(bank, { segments: [{ rpm: 0, s: len, params: moving[0]?.params ?? {} }], machines: [], bed: p.bed, bed_params: p.bed_params, seed: p.seed ?? 1 });
    const { env, rate } = envelopeOf(mono(mixdown(bank, bedSim, { tail: 0 }).stems.Ambience), 0.05);
    let worst = -1;
    for (const l of lengths) {
      const lag = Math.round(l * rate);
      if (lag < env.length) worst = Math.max(worst, corr(env.subarray(0, env.length - lag), env.subarray(lag)));
    }
    rows.push({ id: 'A12', pass: worst < 0.5, value: round(worst), target: 'bed envelope autocorrelation at the loop length < 0.5' });

    // A16: spot density over 60 s. A spot whose own gap can fall under 2 s is a texture (cricket trains) and is left out of the "no 2 in 2 s" count.
    const spots = doc.beds[p.bed].spots ?? [];
    const dense = simulate(bank, { segments: [{ rpm: 0, s: 60, params: moving[0]?.params ?? {} }], machines: [], bed: p.bed, bed_params: { ...p.bed_params }, seed: p.seed ?? 1 });
    const spotEvents = dense.events.filter((e) => e.kind === 'spot');
    const kinds = new Set(spotEvents.map((e) => e.sound));
    const texture = new Set(spots.filter((s) => [s.gap_s].flat()[0] < 2).map((s) => s.sound));
    const details = spotEvents.filter((e) => !texture.has(e.sound));
    let close = 0;
    for (let i = 1; i < details.length; i++) {
      if (details[i].t - details[i - 1].t < 2 && details[i].sound !== details[i - 1].sound) close++;
    }
    rows.push({ id: 'A16', pass: kinds.size >= 3 && close === 0, value: `${kinds.size} sounds, ${close} close`, target: '>= 3 spot sounds per 60 s, no 2 in 2 s' });
  } else {
    rows.push({ id: 'A12', pass: true, value: 'n/a', target: 'no bed' });
    rows.push({ id: 'A16', pass: true, value: 'n/a', target: 'no bed' });
  }

  // A13: round-robin never repeats a variant in a set of 2 or more.
  let repeats = 0;
  const lastBy = new Map();
  for (const e of sim.events) {
    if (e.thinned || bank.variants(e.sound) < 2) continue;
    const key = `${e.machine ?? e.kind}:${e.sound}`;
    if (lastBy.get(key) === e.variant) repeats++;
    lastBy.set(key, e.variant);
  }
  rows.push({ id: 'A13', pass: repeats === 0, value: repeats, target: 'same variant twice running: 0' });

  // A14: the shot's 1-4 kHz over the 500 ms before it.
  if (checks.a14) {
    // Every firing of the cue, its median: one shot placed in a quiet moment says nothing about a wave.
    const evs = (p.events ?? []).filter((e) => e.cue === checks.a14.cue);
    if (evs.length === 0) rows.push({ id: 'A14', pass: false, value: 'no such event', target: `preview.events has no ${checks.a14.cue}` });
    else {
      const m = mono(mix.master);
      const reads = evs.map((ev) => {
        const at = Math.round(ev.t * mixRate);
        const before = bandDb(m.subarray(Math.max(0, at - Math.round(0.5 * mixRate)), at), 1000, 4000);
        const after = bandDb(m.subarray(at, at + Math.round(0.25 * mixRate)), 1000, 4000);
        return after - before;
      }).sort((x, y) => x - y);
      const mid = median(reads);
      rows.push({ id: 'A14', pass: mid >= 6, value: `+${round(mid)} dB`, target: 'event 1-4 kHz >= +6 dB over the background, median of its firings', note: `${reads.length} firings` });
    }
  } else rows.push({ id: 'A14', pass: true, value: 'n/a', target: 'preview.checks.a14 not set' });

  // A15: clipping before the limiter.
  let clipped = 0;
  const sumN = mix.sum[0].length;
  for (let i = 0; i < sumN; i++) {
    if (Math.abs(mix.sum[0][i]) > 1 || Math.abs(mix.sum[1][i]) > 1) clipped++;
  }
  const clipPct = (100 * clipped) / Math.max(1, sumN);
  rows.push({ id: 'A15', pass: clipPct <= 0.1, value: `${round(clipPct, 3)} %`, target: 'clipped before the limiter <= 0.1 %' });

  projectileRows(bank, p, sim, mix, rows);

  rows.push({ id: 'D8', pass: true, value: 'external', target: 'event coverage: the game GUT test' });
  rows.push({ id: 'D10', pass: true, value: 'external', target: 'commit cost: a bench' });

  const waive = p.waive ?? {};
  for (const r of rows) {
    if (!r.pass && r.id.startsWith('A') && !UNWAIVABLE.has(r.id) && waive[r.id]) {
      r.waived = waive[r.id];
    }
  }
  rows.sort((a, b) => a.id[0].localeCompare(b.id[0]) * -1 || Number(a.id.slice(1)) - Number(b.id.slice(1)));
  const fails = rows.filter((r) => !r.pass && !r.waived).map((r) => r.id);
  if (stems) stems.mix = mix;
  return { game: doc.game, pass: fails.length === 0, fails, rows };
}

/** Score the bank at bankPath; the _shared bank comes from sharedPath, or root's assets. */
export function scoreBankFile(bankPath, { root, sharedPath = null, rpms = null } = {}) {
  const doc = loadBank(bankPath);
  const sp = sharedPath ?? path.join(root, 'assets', '_shared', 'audio', 'audio.json');
  const shared = fs.existsSync(sp) ? new BankAudio(loadBank(sp), path.dirname(sp)) : null;
  const dir = path.dirname(bankPath);
  const inAssets = root && path.resolve(dir) === path.resolve(root, 'assets', doc.game, 'audio');
  return scoreBank(doc, dir, { shared, root: inAssets ? root : null, rpms });
}
