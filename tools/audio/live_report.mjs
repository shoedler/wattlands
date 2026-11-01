#!/usr/bin/env node
// Reads what tools/audio/live_mix.gd recorded and prints the numbers a preview can only estimate: the real mix's loudness,
// range, 2-8 kHz share, top band and how the Sfx bus moves. --out writes them as JSON, with the sha of the bank they
// describe, so a test can hold a game to its real wave and notice when the bank has moved on.
//   node tools/audio/live_report.mjs build/audio_live/<name> [--bank=assets/<id>/audio/audio.json] [--out=<file>]

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { bandFilter, bandShareDb } from './lib/dsp.mjs';
import { earBand, onsetShape, shapeApart } from './lib/ear_band.mjs';
import { integratedLufs, loudnessRange, momentaryMaxLufs } from './lib/lufs.mjs';
import { SAFETY_DUCK } from './lib/offline_mix.mjs';
import { decodeWav, deinterleave } from './lib/wav.mjs';

const round = (v) => Math.round(v * 100) / 100;
/** The warning prompt's momentary level at HudLayer's voice (the A2 row reads it from the bank). */
const WARNING_AS_PLAYED = -16.23;

function load(base, bus) {
  const w = decodeWav(fs.readFileSync(`${base}_${bus}.wav`));
  return { rate: w.rate, x: deinterleave(w.samples, w.ch) };
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

/** A sound's first ONE_ARROW_S in a band, all variants, as power at 0 dB on the mix's scale. */
function fileBandPower(doc, dir, sound, lo, hi) {
  const n = doc.sounds[sound]?.variants ?? 1;
  let sum = 0;
  for (let k = 0; k < n; k++) {
    const stem = n > 1 ? `${sound}_${k + 1}` : sound;
    const w = decodeWav(fs.readFileSync(`${dir}/${stem}.wav`));
    const x = deinterleave(w.samples, w.ch)[0];
    const y = bandFilter(x, lo, hi, w.rate);
    const span = Math.min(y.length, Math.round(ONE_ARROW_S * w.rate));
    let e = 0;
    for (let i = 0; i < span; i++) e += y[i] * y[i];
    sum += e / Math.round(ONE_ARROW_S * w.rate);
  }
  return sum / n;
}

/**
 * One arrow over the mix at the level the code plays it: the file at its logged level against the master in the same
 * 50 ms, less the file, so it holds in a crowd of other arrows. `rise` needs no model: the master's own 50 ms against the
 * 180 ms before it, beside what an arbitrary moment reads. The medians hear every arrow that landed there.
 */
export function oneArrow(m, rate, doc, dir, log, sets = ARROW_SOUNDS) {
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
    const y = bandFilter(m, lo, hi, rate);
    const row = {};
    for (const [group, sounds] of Object.entries(sets)) {
      const overs = [];
      const rises = [];
      const per = {};
      for (const sound of sounds) {
        if (!doc.sounds[sound]) continue;
        const file = fileBandPower(doc, dir, sound, lo, hi);
        const mine = [];
        for (const [t, id, dbv] of log) {
          if (id !== sound) continue;
          const at = Math.round(t * rate);
          const own = file * 10 ** (dbv / 10);
          const all = power(y, at, span);
          mine.push(db10(own / Math.max(all - own, all * 0.02)));
          rises.push(db10(all) - db10(power(y, at - before, before - gap)));
        }
        if (mine.length > 0) per[sound] = { n: mine.length, median: median(mine), p10: round(pct(mine, 0.1)) };
        overs.push(...mine);
      }
      row[group] = { n: overs.length, median: median(overs), p10: round(pct(overs, 0.1)), rise: median(rises), sounds: per };
    }
    const arbitrary = [];
    for (let at = before; at + span < y.length; at += Math.round(0.37 * rate)) arbitrary.push(db10(power(y, at, span)) - db10(power(y, at - before, before - gap)));
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
  const stems = (live.start_log ?? []).filter((e) => all.has(String(e[1]).replace(/_\d+$/, ''))).map((e) => e[1]);
  let twice = 0;
  const last = {};
  for (const stem of stems) {
    const sound = stem.replace(/_\d+$/, '');
    if (last[sound] === stem) twice++;
    last[sound] = stem;
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
  };
}

function liveFigures(base, master, m, doc, dir, live) {
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
  let over = 0;
  let last = -Infinity;
  const ceiling = 10 ** (-1 / 20);
  for (const ch of master.x) {
    for (let i = 0; i < ch.length; i++) {
      if (Math.abs(ch[i]) > ceiling) {
        if (i / rate - last > 0.05) over++;
        last = i / rate;
      }
    }
  }
  out.head_episodes_per_min = round((over / seconds) * 60);
  out.a14_ballista = a14Read(m, rate, startsOf(['ballista_twang']));
  out.arrows = arrowCounts(live);
  out.fatigue = fatigueFigures(master, m, rate, live);
  const dirSounds = dir;
  if (doc && dirSounds) {
    out.flights_1k_2k4 = flightFigures(m, rate, doc, dirSounds, live, 1000, 2400);
    const sfx = mono(load(base, 'sfx').x);
    const machines = mono(load(base, 'machines').x);
    out.sfx_over_machines_1k_2k = busOver(sfx, machines, rate, 1000, 2000);
    out.one_arrow = oneArrow(m, rate, doc, dirSounds, log);
  }
  return out;
}

export function report(base, doc = null, dir = null) {
  const master = load(base, 'master');
  const sfx = load(base, 'sfx');
  const m = mono(master.x);
  const e = earBand(m, undefined, master.rate);
  const live = JSON.parse(fs.readFileSync(`${base}.json`, 'utf8'));
  return {
    ...liveFigures(base, master, m, doc, dir, live),
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
