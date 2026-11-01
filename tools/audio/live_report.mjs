#!/usr/bin/env node
// Reads what tools/audio/live_mix.gd recorded and prints the numbers a preview can only estimate: the real mix's loudness,
// range, 2-8 kHz share, top band and how the Sfx bus moves. --out writes them as JSON, with the sha of the bank they
// describe, so a test can hold a game to its real wave and notice when the bank has moved on.
//   node tools/audio/live_report.mjs build/audio_live/<name> [--bank=assets/<id>/audio/audio.json] [--out=<file>]

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { bandFilter, bandShareDb, fft } from './lib/dsp.mjs';
import { earBand, onsetShape, shapeApart } from './lib/ear_band.mjs';
import { integratedLufs, loudnessRange, momentaryMaxLufs } from './lib/lufs.mjs';
import { SAFETY_DUCK } from './lib/offline_mix.mjs';
import { decodeWav, deinterleave, readCapture } from './lib/wav.mjs';

const round = (v) => Math.round(v * 100) / 100;
/** The warning prompt's momentary level at HudLayer's voice (the A2 row reads it from the bank). */
const WARNING_AS_PLAYED = -16.23;

function load(base, bus) {
  const w = readCapture(fs.readFileSync(`${base}_${bus}.wav`));
  return { rate: w.rate, x: w.x };
}

function mono(x) {
  const out = new Float64Array(x[0].length);
  for (let i = 0; i < out.length; i++) out[i] = x.length > 1 ? 0.5 * (x[0][i] + x[1][i]) : x[0][i];
  return out;
}

/** The band's 50 ms levels in dB, p10, p50, p90 and their spread, so a bed reads as a small spread. */
export function movement(x, rate, lo, hi) {
  const y = bandFilter(x, lo, hi, rate);
  const n = Math.round(0.05 * rate);
  const levels = [];
  for (let at = 0; at + n <= y.length; at += n) {
    let e = 0;
    for (let i = 0; i < n; i++) e += y[at + i] * y[at + i];
    levels.push(10 * Math.log10(e / n + 1e-12));
  }
  levels.sort((a, b) => a - b);
  const at = (p) => levels[Math.floor(p * (levels.length - 1))];
  return { p10: round(at(0.1)), p50: round(at(0.5)), p90: round(at(0.9)), spread: round(at(0.9) - at(0.1)) };
}

/** The mix under a prompt at each 250 ms of the run: each bus with the prompt's own duck, loudest 600 ms. The captures sit before the buses' volume. */
function mixUnderPrompt(base, rate) {
  const buses = Object.fromEntries(['Machines', 'Ambience', 'Sfx'].map((b) => [b, load(base, b.toLowerCase()).x]));
  const n = buses.Sfx[0].length;
  const levels = [];
  for (let t = 1; t + 0.7 < n / rate; t += 0.25) {
    const from = Math.round(t * rate);
    const to = Math.round((t + 0.6) * rate);
    const out = [new Float64Array(to - from), new Float64Array(to - from)];
    for (const d of SAFETY_DUCK) {
      const x = buses[d.bus];
      const fade = d.attack_s * rate;
      for (let c = 0; c < 2; c++) {
        for (let i = from; i < to; i++) {
          out[c][i - from] += x[c][i] * 10 ** ((d.db * Math.min((i - from) / fade, 1)) / 20);
        }
      }
    }
    levels.push(momentaryMaxLufs(out, rate));
  }
  return levels;
}

function evalCurve(points, u) {
  if (u <= points[0][0]) return points[0][1];
  for (let i = 1; i < points.length; i++) {
    if (u <= points[i][0]) return points[i - 1][1] + ((points[i][1] - points[i - 1][1]) * (u - points[i - 1][0])) / (points[i][0] - points[i - 1][0]);
  }
  return points[points.length - 1][1];
}

function bandPower(x, rate, lo, hi) {
  const y = bandFilter(x, lo, hi, rate);
  const n = Math.round(0.05 * rate);
  const out = new Float64Array(Math.floor(y.length / n));
  for (let k = 0; k < out.length; k++) {
    let e = 0;
    for (let i = 0; i < n; i++) e += y[k * n + i] * y[k * n + i];
    out[k] = e / n;
  }
  return out;
}

const db10 = (v) => 10 * Math.log10(v + 1e-14);

function pct(values, p) {
  const s = [...values].sort((a, b) => a - b);
  return s.length > 0 ? s[Math.floor(p * (s.length - 1))] : 0;
}

/**
 * What each flight adds to one band, from the log and the bank: its loop's level there, its logged db, the contour over
 * its logged seconds. The master's capture can't separate a flight from what plays with it; this can.
 */
function flightPowers(doc, dir, live, rate, frames, lo, hi) {
  const files = new Map();
  const contour = new Map();
  for (const cue of Object.values(doc.cues ?? {})) {
    for (const h of cue.hits ?? []) if (h.flight && !contour.has(`${h.sound}`)) contour.set(h.sound, h.flight.gain ?? [[0, 0]]);
  }
  const level = (sound) => {
    if (files.has(sound)) return files.get(sound);
    const v = (doc.sounds[sound].variants ?? 1) > 1 ? `${sound}_1` : sound;
    const w = decodeWav(fs.readFileSync(`${dir}/${v}.wav`));
    const y = bandFilter(deinterleave(w.samples, w.ch)[0], lo, hi, w.rate);
    let e = 0;
    for (const a of y) e += a * a;
    files.set(sound, e / y.length);
    return e / y.length;
  };
  return (live.flight_log ?? []).map(([t, sound, dur, dbv, lead]) => {
    const curve = contour.get(sound) ?? [[0, 0]];
    const from = Math.round(t / 0.05);
    const n = Math.max(1, Math.round(dur / 0.05));
    const p = new Float64Array(n);
    // The pitch moves a loop's band a little: the level is taken at its middle, where the contour peaks.
    for (let k = 0; k < n; k++) p[k] = level(sound) * 10 ** ((dbv + evalCurve(curve, k / n)) / 10);
    return { t, sound, dur, db: dbv, lead: lead === 1, from, p, frames };
  });
}

/** The rider's own flights at their peak against everything else in the band at that moment, and how the flights alone move. */
function flightFigures(m, rate, doc, dir, live, lo, hi) {
  const master = bandPower(m, rate, lo, hi);
  const flights = flightPowers(doc, dir, live, rate, master.length, lo, hi);
  const sum = new Float64Array(master.length);
  for (const f of flights) for (let k = 0; k < f.p.length; k++) if (f.from + k < sum.length) sum[f.from + k] += f.p[k];
  const air = Array.from(sum).filter((v) => v > 0).map(db10);
  const overs = {};
  // The loudest level each sound was played at: a rider who alternates volleys is judged on the ones meant to be heard.
  const top = {};
  for (const f of flights) top[f.sound] = Math.max(top[f.sound] ?? -200, f.db);
  for (const f of flights) {
    let peak = 0;
    for (let k = 1; k < f.p.length; k++) if (f.p[k] > f.p[peak]) peak = k;
    const at = f.from + peak;
    if (at >= master.length) continue;
    // Over the next 150 ms: the master minus this flight is everything else.
    let own = 0;
    let all = 0;
    for (let k = 0; k < 3 && at + k < master.length; k++) {
      own += f.p[Math.min(peak + k, f.p.length - 1)];
      all += master[at + k];
    }
    const rest = Math.max(all - own, all * 0.02);
    const key = `${f.lead ? 'own' : 'other'}_${f.sound}`;
    (overs[key] ??= []).push(db10(own / rest));
    if (f.lead && f.db >= top[f.sound] - 1) (overs[`${key}_full_level`] ??= []).push(db10(own / rest));
  }
  const med = {};
  for (const [k, v] of Object.entries(overs)) med[k] = { n: v.length, median: round(pct(v, 0.5)), p90: round(pct(v, 0.9)) };
  return { over: med, ripple_p90_p10: round(pct(air, 0.9) - pct(air, 0.1)) };
}

/** Bus against bus in one band. */
function busOver(a, b, rate, lo, hi) {
  const pa = bandPower(a, rate, lo, hi).reduce((acc, v) => acc + v, 0);
  const pb = bandPower(b, rate, lo, hi).reduce((acc, v) => acc + v, 0);
  return round(db10(pa) - db10(pb));
}

/** A14 as the scorecard reads it, at each real start of a sound: its median over the wave. */
function a14Read(m, rate, starts) {
  const span = (a, b) => {
    const y = bandFilter(m.subarray(Math.max(0, a), Math.min(m.length, b)), 1000, 4000, rate);
    let e = 0;
    for (const v of y) e += v * v;
    return e / Math.max(1, y.length);
  };
  const reads = starts.filter((t) => t > 1).map((t) => {
    const at = Math.round(t * rate);
    return db10(span(at, at + Math.round(0.25 * rate))) - db10(span(at - Math.round(0.5 * rate), at));
  });
  return { n: reads.length, median: round(pct(reads, 0.5)) };
}

const IMPACT_SOUNDS = new Set(['arrow_flesh', 'arrow_wood', 'arrow_shield', 'arrow_dirt', 'arrow_water', 'hit_flesh', 'hit_wood', 'hit_shield', 'bolt_dirt', 'bolt_wood', 'stone_impact', 'stone_wood', 'stone_splash']);
/** The sounds of one arrow that lands, on a body and on nothing. */
export const ARROW_SOUNDS = { body: ['arrow_flesh', 'arrow_wood', 'arrow_shield'], miss: ['arrow_dirt', 'arrow_water'] };
/** Where a body is heard: P4's whole band, then under and over the flights' 1-2.4 kHz. */
const ONE_ARROW_BANDS = { all_400_6000: [400, 6000], low_400_1000: [400, 1000], high_2400_6000: [2400, 6000] };
const ONE_ARROW_S = 0.05;

function median(values) {
  return round(pct(values, 0.5));
}

/** A file's first `seconds` in a band, as power at 0 dB on the mix's scale. */
function fileBandPower(dir, stem, lo, hi, seconds = ONE_ARROW_S) {
  const w = decodeWav(fs.readFileSync(`${dir}/${stem}.wav`));
  const y = bandFilter(deinterleave(w.samples, w.ch)[0], lo, hi, w.rate);
  const span = Math.min(y.length, Math.round(seconds * w.rate));
  let e = 0;
  for (let i = 0; i < span; i++) e += y[i] * y[i];
  return e / Math.round(seconds * w.rate);
}

/** What a panned send of Sfx gives a mono voice in each channel: AudioEffectPanner, with its name read off the bus. */
export function panGains(bus) {
  const pan = Number(String(bus).match(/[+-]\d+\.\d+$/)?.[0] ?? 0);
  const lvol = Math.min(Math.max(1 - pan, 0), 1);
  const rvol = Math.min(Math.max(1 + pan, 0), 1);
  return [lvol + (1 - rvol), rvol + (1 - lvol)];
}

/**
 * One arrow over the mix at the level the code plays it: the file at its logged level against the master in the same
 * 50 ms, less the file, so it holds in a crowd of other arrows. `rise` needs no model: the master's own 50 ms against the
 * 180 ms before it, beside what an arbitrary moment reads. The medians hear every arrow that landed there. Each is read
 * in the channel its pan puts it in, from the players' own log: a voice on the left stands out on the left.
 */
export function oneArrow(x, rate, dir, starts, sets = ARROW_SOUNDS) {
  const out = {};
  const span = Math.round(ONE_ARROW_S * rate);
  const before = Math.round(0.2 * rate);
  const gap = Math.round(0.02 * rate);
  const power = (y, a, n) => {
    let e = 0;
    const from = Math.max(0, a);
    const to = Math.min(y.length, a + n);
    for (let i = from; i < to; i++) e += y[i] * y[i];
    return e / Math.max(1, to - from);
  };
  for (const [band, [lo, hi]] of Object.entries(ONE_ARROW_BANDS)) {
    const y = x.map((c) => bandFilter(c, lo, hi, rate));
    const files = new Map();
    const fileOf = (stem) => {
      if (!files.has(stem)) files.set(stem, fileBandPower(dir, stem, lo, hi));
      return files.get(stem);
    };
    const row = {};
    for (const [group, sounds] of Object.entries(sets)) {
      const overs = [];
      const rises = [];
      const per = {};
      const accents = { yes: [], no: [] };
      for (const sound of sounds) {
        const mine = [];
        for (const s of starts) {
          const [t, stem, bus, dbv, , tag] = s;
          if (stem.replace(/_\d+$/, '') !== sound) continue;
          const gains = panGains(bus);
          const c = gains[0] >= gains[1] ? 0 : 1;
          const at = Math.round(t * rate);
          const own = fileOf(stem) * 10 ** (dbv / 10) * gains[c] * gains[c];
          const all = power(y[c], at, span);
          mine.push(db10(own / Math.max(all - own, all * 0.02)));
          const rise = db10(all) - db10(power(y[c], at - before, before - gap));
          rises.push(rise);
          (tag ? accents.yes : accents.no).push(rise);
        }
        if (mine.length > 0) per[sound] = { n: mine.length, median: median(mine), p10: round(pct(mine, 0.1)) };
        overs.push(...mine);
      }
      row[group] = { n: overs.length, median: median(overs), p10: round(pct(overs, 0.1)), rise: median(rises), rise_accented: median(accents.yes), rise_plain: median(accents.no), accented: accents.yes.length, sounds: per };
    }
    const arbitrary = [];
    for (let at = before; at + span < y[0].length; at += Math.round(0.37 * rate)) {
      const c = at % 2;
      arbitrary.push(db10(power(y[c], at, span)) - db10(power(y[c], at - before, before - gap)));
    }
    row.arbitrary_rise = median(arbitrary);
    out[band] = row;
  }
  return out;
}

/** Does it tire: how the master's level holds over 30 s and 3 s, how evenly arrows come, and whether anything repeats. */
export function fatigueFigures(master, m, rate, live, sets = ARROW_SOUNDS) {
  const n30 = Math.round(30 * rate);
  const lufs30 = [];
  for (let at = 0; at + n30 <= m.length; at += n30) lufs30.push(round(integratedLufs(master.x.map((c) => c.subarray(at, at + n30)), rate)));
  const n3 = Math.round(3 * rate);
  const short = [];
  for (let at = 0; at + n3 <= m.length; at += rate) short.push(integratedLufs(master.x.map((c) => c.subarray(at, at + n3)), rate));
  const all = new Set([...sets.body, ...sets.miss]);
  const log = (live.played_log ?? []).filter((e) => all.has(e[1]));
  const per30 = [];
  for (let k = 0; k * 30 < m.length / rate - 1; k++) per30.push(log.filter((e) => e[0] >= k * 30 && e[0] < (k + 1) * 30).length / 30);
  const gaps = [];
  for (let i = 1; i < log.length; i++) gaps.push(log[i][0] - log[i - 1][0]);
  // The envelope of the arrows' band against itself: a peak near 1 at some lag is a metronome.
  const env = bandPower(m, rate, 400, 6000).map(db10);
  const mean = env.reduce((a, b) => a + b, 0) / Math.max(1, env.length);
  let bestLag = 0;
  let best = -1;
  let var0 = 0;
  for (const v of env) var0 += (v - mean) * (v - mean);
  for (let lag = 10; lag < Math.min(env.length / 2, 600); lag++) {
    let c = 0;
    for (let i = 0; i + lag < env.length; i++) c += (env[i] - mean) * (env[i + lag] - mean);
    c /= var0 || 1;
    if (c > best) {
      best = c;
      bestLag = lag;
    }
  }
  // The log reads the pools once a frame, so inside one frame its order isn't the order they started in. A repeat is only
  // certain from a frame with one start of a surface to the next with one.
  const frames = new Map();
  for (const e of live.start_log ?? []) {
    const sound = String(e[1]).replace(/_\d+$/, '');
    if (!all.has(sound)) continue;
    const key = `${sound}@${e[0]}`;
    frames.set(key, [...(frames.get(key) ?? []), e[1]]);
  }
  let twice = 0;
  const last = {};
  for (const [key, list] of frames) {
    const sound = key.split('@')[0];
    if (list.length === 1 && last[sound] === list[0]) twice++;
    last[sound] = list.length === 1 ? list[0] : null;
  }
  return {
    lufs_30s: lufs30,
    lufs_30s_spread: lufs30.length > 0 ? round(Math.max(...lufs30) - Math.min(...lufs30)) : 0,
    lufs_3s_p10_p90: [round(pct(short, 0.1)), round(pct(short, 0.9))],
    arrows_per_s_30s: per30.map(round),
    gap_ms_p10_p50_p90: [0.1, 0.5, 0.9].map((p) => Math.round(pct(gaps, p) * 1000)),
    envelope_repeat: { lag_s: round(bestLag * 0.05), correlation: round(best) },
    same_file_twice_running: twice,
  };
}

const ONSET_HOP_S = 0.005;
const ONSET_WIN_S = 0.02;

/**
 * The master's onsets, per 5 ms frame: over the third octaves 250-8000 Hz, the rise of the log level over 15 ms against
 * the 50 ms before it, less 1 dB, the rises added up. Heard rather than modelled: it knows nothing of what played.
 */
export function onsetTrack(m, rate) {
  const nw = Math.floor(ONSET_WIN_S * rate);
  const nh = Math.floor(ONSET_HOP_S * rate);
  const nfft = Math.max(1024, nw);
  const hann = Float64Array.from({ length: nw }, (_, i) => 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / nw));
  const norm = hann.reduce((a, b) => a + b, 0) ** 2;
  const centres = Array.from({ length: 16 }, (_, i) => 250 * 2 ** (i / 3));
  const bins = centres.map((c) => {
    const lo = (c / 2 ** (1 / 6)) * (nfft / rate);
    const hi = c * 2 ** (1 / 6) * (nfft / rate);
    return [Math.ceil(lo), Math.max(Math.ceil(lo) + 1, Math.ceil(hi))];
  });
  const frames = Math.max(0, Math.floor((m.length - nw) / nh) + 1);
  const hopTrue = nh / rate;
  const out = new Float64Array(Math.round(frames * (hopTrue / ONSET_HOP_S)));
  const L = centres.map(() => new Float64Array(frames));
  const re = new Float64Array(nfft);
  const im = new Float64Array(nfft);
  for (let k = 0; k < frames; k++) {
    re.fill(0);
    im.fill(0);
    for (let i = 0; i < nw; i++) re[i] = m[k * nh + i] * hann[i];
    fft(re, im);
    for (let b = 0; b < bins.length; b++) {
      let p = 0;
      for (let q = bins[b][0]; q < bins[b][1]; q++) p += re[q] * re[q] + im[q] * im[q];
      L[b][k] = 10 * Math.log10(Math.max(p / norm, 1e-9));
    }
  }
  const raw = new Float64Array(frames);
  for (const level of L) {
    const sum = new Float64Array(frames + 1);
    for (let i = 0; i < frames; i++) sum[i + 1] = sum[i] + level[i];
    const mean = (a, b) => {
      const from = Math.max(0, a);
      const to = Math.min(frames, b);
      return to > from ? (sum[to] - sum[from]) / (to - from) : level[Math.min(Math.max(a, 0), frames - 1)];
    };
    for (let i = 0; i < frames; i++) raw[i] += Math.max(mean(i - 1, i + 2) - mean(i - 13, i - 3) - 1, 0);
  }
  for (let k = 0; k < out.length; k++) out[k] = raw[Math.min(Math.round((k * ONSET_HOP_S) / hopTrue), frames - 1)];
  return out;
}

/** The peaks of a track at or over `height`, at least `distance` frames apart, the highest kept first. */
function strongPeaks(track, height, distance) {
  const candidates = [];
  for (let i = 1; i < track.length - 1; i++) {
    if (track[i] >= height && track[i] > track[i - 1] && track[i] >= track[i + 1]) candidates.push(i);
  }
  candidates.sort((a, b) => track[b] - track[a]);
  const taken = new Uint8Array(track.length);
  const out = [];
  for (const i of candidates) {
    if (taken[i]) continue;
    out.push(i);
    for (let k = Math.max(0, i - distance + 1); k < Math.min(track.length, i + distance); k++) taken[k] = 1;
  }
  return out.sort((a, b) => a - b);
}

/**
 * Strong onsets a second inside landing windows, -200 to +300 ms around each flight's end, over those outside. Strong:
 * over the p90 of the same track at arbitrary moments. A rider who can hear volleys land gets a figure well over 1.
 */
export function landingContrast(m, rate, live, sound = 'arrow_swarm') {
  const track = onsetTrack(m, rate);
  const seconds = m.length / rate;
  const arbitrary = [];
  for (let k = 0; k < 4000; k++) {
    const i = Math.floor((3 + ((seconds - 6) * k) / 4000) / ONSET_HOP_S);
    let best = 0;
    for (let j = i - 6; j < i + 6; j++) best = Math.max(best, track[j] ?? 0);
    arbitrary.push(best);
  }
  const threshold = pct(arbitrary, 0.9);
  const peaks = strongPeaks(track, threshold, 6);
  const inside = new Uint8Array(track.length);
  let volleys = 0;
  for (const f of live.flight_log ?? []) {
    if (f[1] !== sound) continue;
    const t = f[0] + f[2];
    if (t <= 3 || t >= seconds - 1) continue;
    volleys++;
    const at = Math.floor(t / ONSET_HOP_S);
    inside.fill(1, Math.max(0, at - 40), Math.min(track.length, at + 60));
  }
  let frames = 0;
  for (const v of inside) frames += v;
  let hits = 0;
  for (const p of peaks) hits += inside[p];
  const inRate = hits / Math.max(frames * ONSET_HOP_S, 1e-9);
  const outRate = (peaks.length - hits) / Math.max((track.length - frames) * ONSET_HOP_S, 1e-9);
  return { ratio: round(inRate / Math.max(outRate, 1e-9)), inside_per_s: round(inRate), outside_per_s: round(outRate), duty: round(frames / track.length), volleys };
}

/** The prompts of a battle a rider acts on or waits for. */
export const EVENT_SOUNDS = ['horn_wave', 'horn_push', 'horn_rush', 'wave_end_bell', 'tower_dock', 'reach_alarm', 'gate_crash', 'gate_restored'];
const EVENT_S = 0.3;
const EVENT_OCTAVES = [[250, 500], [500, 1000], [1000, 2000], [2000, 4000], [4000, 8000]];

/**
 * Each start of those over the mix: the master's own rise, its first 300 ms against the 500 ms before it, whole and in its
 * best octave, and the arrows that land inside it. A long sound with a slow attack reads low on the first: read the second.
 */
export function eventFigures(x, rate, starts, sets = ARROW_SOUNDS) {
  const m = mono(x);
  const out = {};
  const span = Math.round(EVENT_S * rate);
  const before = Math.round(0.5 * rate);
  const level = (y, a, n) => {
    let e = 0;
    const from = Math.max(0, a);
    const to = Math.min(y.length, a + n);
    for (let i = from; i < to; i++) e += y[i] * y[i];
    return db10(e / Math.max(1, to - from));
  };
  const bands = EVENT_OCTAVES.map(([lo, hi]) => bandFilter(m, lo, hi, rate));
  const arrows = new Set([...sets.body, ...sets.miss]);
  const landings = starts.filter((s) => arrows.has(s[1].replace(/_\d+$/, ''))).map((s) => s[0]);
  for (const sound of EVENT_SOUNDS) {
    const list = starts.filter((s) => s[1].replace(/_\d+$/, '') === sound && s[0] > 0.6);
    if (list.length === 0) continue;
    out[sound] = list.map(([t, , , dbv]) => {
      const at = Math.round(t * rate);
      const best = Math.max(...bands.map((y) => level(y, at, span) - level(y, at - before, before)));
      return { t: round(t), db: dbv, rise: round(level(m, at, span) - level(m, at - before, before)), best_octave: round(best), arrows_around: landings.filter((l) => l >= t - 0.1 && l < t + EVENT_S).length };
    });
  }
  return out;
}

/** Every arrow that landed, against the sounds it got and the players that took them. */
function arrowCounts(live, sets = ARROW_SOUNDS) {
  const sounds = [...sets.body, ...sets.miss];
  const asked = {};
  for (const [, id] of live.played_log ?? []) if (sounds.includes(id)) asked[id] = (asked[id] ?? 0) + 1;
  const started = {};
  for (const [stem, v] of Object.entries(live.voice_starts ?? {})) {
    const id = stem.replace(/_\d+$/, '');
    if (sounds.includes(id)) started[id] = (started[id] ?? 0) + v.playing;
  }
  const sum = (o, ids) => ids.reduce((a, id) => a + (o[id] ?? 0), 0);
  return {
    landed: live.arrows?.landed ?? 0,
    struck_by_ear: live.arrows?.struck ?? 0,
    station_hits: live.arrows?.station_hits ?? 0,
    sounds_asked: sum(asked, sounds),
    sounds_started: sum(started, sounds),
    body_sounds: sum(asked, sets.body),
    miss_sounds: sum(asked, sets.miss),
    by_sound: asked,
    crowd_voiceless: live.crowd_voiceless ?? 0,
    stolen: live.stolen ?? {},
    crowd_voices: live.voices?.Crowd ?? null,
    coverage: (live.arrows?.landed ?? 0) > 0 ? round(sum(started, sounds) / live.arrows.landed) : 0,
  };
}

/** How often the head of the mix goes over the limiter's ceiling. Linked: a moment over on both channels counts once. */
export function headEpisodes(x, rate) {
  const ceiling = 10 ** (-1 / 20);
  let over = 0;
  let last = -Infinity;
  for (let i = 0; i < x[0].length; i++) {
    if (Math.abs(x[0][i]) > ceiling || (x[1] && Math.abs(x[1][i]) > ceiling)) {
      if (i / rate - last > 0.05) over++;
      last = i / rate;
    }
  }
  return over;
}

function liveFigures(base, master, m, doc, dir, live, sets = ARROW_SOUNDS) {
  const rate = master.rate;
  const log = live.played_log ?? [];
  const startsOf = (ids) => log.filter((e) => ids.includes(e[1])).map((e) => e[0]);
  const seconds = m.length / rate;
  const out = {};
  // Where one voice can be told from another: the mix, not the file.
  const shapes = {
    flesh: onsetShape(m, startsOf(['arrow_flesh', 'hit_flesh']), rate),
    dirt: onsetShape(m, startsOf(['arrow_dirt', 'bolt_dirt']), rate),
    wood: onsetShape(m, startsOf(['arrow_wood', 'hit_wood', 'bolt_wood', 'stone_wood']), rate),
    shield: onsetShape(m, startsOf(['arrow_shield', 'hit_shield']), rate),
  };
  const apart = (a, b) => {
    const d = shapeApart(shapes[a], shapes[b]);
    return d === null ? null : round(d);
  };
  out.mix_apart_first_60ms = { flesh_dirt: apart('flesh', 'dirt'), wood_dirt: apart('wood', 'dirt'), flesh_wood: apart('flesh', 'wood'), shield_dirt: apart('shield', 'dirt') };
  const impacts = log.filter((e) => IMPACT_SOUNDS.has(e[1]));
  out.impacts_per_s = round(impacts.length / seconds);
  out.kills_per_s = round(log.filter((e) => e[1] === 'kill_thud').length / seconds);
  out.head_episodes_per_min = round((headEpisodes(master.x, rate) / seconds) * 60);
  out.a14_ballista = a14Read(m, rate, startsOf(['ballista_twang']));
  out.arrows = arrowCounts(live, sets);
  out.fatigue = fatigueFigures(master, m, rate, live, sets);
  out.landing_contrast = landingContrast(m, rate, live);
  const dirSounds = dir;
  if (doc && dirSounds) {
    out.flights_1k_2k4 = flightFigures(m, rate, doc, dirSounds, live, 1000, 2400);
    const sfx = mono(load(base, 'sfx').x);
    const machines = mono(load(base, 'machines').x);
    out.sfx_over_machines_1k_2k = busOver(sfx, machines, rate, 1000, 2000);
    out.one_arrow = oneArrow(master.x, rate, dirSounds, live.start_log ?? [], sets);
    out.events = eventFigures(master.x, rate, live.start_log ?? [], sets);
  }
  return out;
}

export function report(base, doc = null, dir = null, sets = ARROW_SOUNDS) {
  const master = load(base, 'master');
  const sfx = load(base, 'sfx');
  const m = mono(master.x);
  const e = earBand(m, undefined, master.rate);
  const live = JSON.parse(fs.readFileSync(`${base}.json`, 'utf8'));
  return {
    ...liveFigures(base, master, m, doc, dir, live, sets),
    seconds: round(m.length / master.rate),
    lufs: round(integratedLufs(master.x, master.rate)),
    lra: round(loudnessRange(master.x, master.rate)),
    ear_band_share: round(e.share),
    ear_band_worst: round(e.worst),
    ear_band_a_share: round(e.aShare),
    top_band_share: round(bandShareDb(m, master.rate, 9800, master.rate / 2 + 1, 4096)),
    sfx_lufs: round(integratedLufs(sfx.x, sfx.rate)),
    sfx_movement_1k_4k: movement(mono(sfx.x), sfx.rate, 1000, 4000),
    prompt_margin_worst: round(WARNING_AS_PLAYED - Math.max(...mixUnderPrompt(base, master.rate))),
  };
}

function main() {
  const args = process.argv.slice(2);
  const base = args.find((a) => !a.startsWith('--'));
  if (!base) {
    process.stderr.write('usage: node tools/audio/live_report.mjs build/audio_live/<name> [--bank=<audio.json>] [--out=<file>]\n');
    return 2;
  }
  const bank = args.find((a) => a.startsWith('--bank='))?.slice(7);
  const out = report(base, bank ? JSON.parse(fs.readFileSync(bank, 'utf8')) : null, bank ? path.dirname(bank) : null);
  if (bank) out.bank_sha = crypto.createHash('sha256').update(fs.readFileSync(bank)).digest('hex');
  const live = JSON.parse(fs.readFileSync(`${base}.json`, 'utf8'));
  out.driver = live.driver ?? '';
  out.shots = live.cues?.shot ?? 0;
  out.flight_starts = live.flight_starts ?? 0;
  out.voiceless = live.voiceless ?? 0;
  const file = args.find((a) => a.startsWith('--out='))?.slice(6);
  if (file) fs.writeFileSync(file, `${JSON.stringify(out, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(out, null, 2)}\n`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = main();
