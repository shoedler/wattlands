#!/usr/bin/env node
// Reads what tools/audio/live_mix.gd recorded and prints the numbers a preview can only estimate: the real mix's loudness,
// range, 2-8 kHz share, top band and how the Sfx bus moves. --out writes them as JSON, with the sha of the bank they
// describe, so a test can hold a game to its real wave and notice when the bank has moved on.
//   node tools/audio/live_report.mjs build/audio_live/<name> [--bank=assets/<id>/audio/audio.json] [--out=<file>]

import crypto from 'node:crypto';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
import { bandFilter, bandShareDb } from './lib/dsp.mjs';
import { earBand } from './lib/ear_band.mjs';
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

export function report(base) {
  const master = load(base, 'master');
  const sfx = load(base, 'sfx');
  const m = mono(master.x);
  const e = earBand(m);
  return {
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
  const out = report(base);
  const bank = args.find((a) => a.startsWith('--bank='))?.slice(7);
  if (bank) out.bank_sha = crypto.createHash('sha256').update(fs.readFileSync(bank)).digest('hex');
  const live = JSON.parse(fs.readFileSync(`${base}.json`, 'utf8'));
  out.shots = live.cues?.shot ?? 0;
  out.flight_starts = live.flight_starts ?? 0;
  out.voiceless = live.voiceless ?? 0;
  const file = args.find((a) => a.startsWith('--out='))?.slice(6);
  if (file) fs.writeFileSync(file, `${JSON.stringify(out, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(out, null, 2)}\n`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = main();
