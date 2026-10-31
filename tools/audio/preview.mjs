#!/usr/bin/env node
// Offline previews for ears and critics: the whole mix, the lead machine solo per rpm, the bed solo
// and the event list, in build/audio_preview/. ffmpeg makes the mp3 and spectrogram PNGs if present;
// nothing else here needs it.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { bankPathOf, findBanks, loadBank } from './lib/bank.mjs';
import { BankAudio, MIX_RATE, mixdown, simulate, toInt16 } from './lib/offline_mix.mjs';
import { applyRpms, movingSegments, previewScenario, renderSolo } from './lib/score.mjs';
import { encodeWav } from './lib/wav.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const BED_SOLO_S = 30;

const USAGE = `usage: node tools/audio/preview.mjs --game=<id>|all [--bank=<path>] [--rpm=60,90,110] [--no-mp3] [--root=<dir>]

Writes build/audio_preview/<game>.wav and .mp3, <game>_<machine>_<rpm>.wav, <game>_bed.wav and
<game>_events.json. Exit codes: 0 done, 2 usage or bank error.
`;

function writeWav(file, stem) {
  fs.writeFileSync(file, encodeWav(toInt16(stem), { rate: MIX_RATE, ch: 2 }));
}

function hasFfmpeg() {
  const r = spawnSync('ffmpeg', ['-hide_banner', '-version'], { stdio: 'ignore' });
  return r.status === 0;
}

function ffmpeg(args) {
  const r = spawnSync('ffmpeg', ['-hide_banner', '-nostats', '-y', ...args], { stdio: ['ignore', 'ignore', 'pipe'], encoding: 'utf8' });
  return r;
}

function encodeOutputs(outDir, game, soloFiles) {
  const base = path.join(outDir, game);
  ffmpeg(['-i', `${base}.wav`, '-c:a', 'libmp3lame', '-q:a', '2', `${base}.mp3`]);
  const loud = ffmpeg(['-i', `${base}.wav`, '-filter_complex', 'ebur128=peak=true', '-f', 'null', '-']);
  fs.writeFileSync(`${base}.ebur128.txt`, loud.stderr ?? '');
  ffmpeg(['-i', `${base}.wav`, '-lavfi', 'showspectrumpic=s=1600x800:legend=1:scale=log:fscale=log:stop=11025', `${base}.png`]);
  for (const f of soloFiles) ffmpeg(['-i', f, '-lavfi', 'showspectrumpic=s=1600x800:legend=1:scale=log:stop=11025', f.replace(/\.wav$/, '.png')]);
}

/** Write every preview of one bank; returns the files written. */
export function previewBank(bankPath, { root, rpms = null, mp3 = true }) {
  const doc = loadBank(bankPath);
  if (!doc.preview) throw new Error(`${bankPath}: no preview block`);
  const outDir = path.join(root, 'build', 'audio_preview');
  fs.mkdirSync(outDir, { recursive: true });
  // build/ must hold a .gdignore, or the next --import takes every preview WAV in.
  const ignore = path.join(root, 'build', '.gdignore');
  if (!fs.existsSync(ignore)) fs.writeFileSync(ignore, '');
  const bank = new BankAudio(doc, path.dirname(bankPath));
  const game = doc.game;
  const written = [];
  const sim = simulate(bank, previewScenario(doc, { rpms }));
  const mix = mixdown(bank, sim);
  const mixFile = path.join(outDir, `${game}.wav`);
  writeWav(mixFile, mix.master);
  written.push(mixFile);
  const eventsFile = path.join(outDir, `${game}_events.json`);
  fs.writeFileSync(eventsFile, `${JSON.stringify(sim.events.map(roundEvent))}\n`);
  written.push(eventsFile);
  const solos = [];
  const segs = movingSegments({ preview: { segments: applyRpms(doc.preview.segments, rpms) } });
  for (const seg of segs) {
    const solo = renderSolo(bank, doc.preview.lead, seg, { tail: 0.3 });
    const file = path.join(outDir, `${game}_${doc.preview.lead}_${Math.round(seg.rpm)}.wav`);
    writeWav(file, [solo.x, solo.x]);
    solos.push(file);
    written.push(file);
  }
  if (doc.preview.bed) {
    const bedSim = simulate(bank, {
      segments: [{ rpm: 0, s: BED_SOLO_S, params: segs[0]?.params ?? {} }],
      machines: [],
      bed: doc.preview.bed,
      bed_params: doc.preview.bed_params,
      seed: doc.preview.seed ?? 1,
    });
    const bedFile = path.join(outDir, `${game}_bed.wav`);
    writeWav(bedFile, mixdown(bank, bedSim, { tail: 0 }).stems.Ambience);
    written.push(bedFile);
  }
  if (mp3) {
    if (hasFfmpeg()) encodeOutputs(outDir, game, solos);
    else process.stdout.write(`${game}: ffmpeg not found, no mp3 or spectrograms\n`);
  }
  return written;
}

function roundEvent(e) {
  return { ...e, t: Math.round(e.t * 1e5) / 1e5, db: Math.round(e.db * 100) / 100, pos: e.pos === undefined ? undefined : Math.round(e.pos * 1e5) / 1e5 };
}

function main() {
  const o = { game: null, bank: null, rpms: null, mp3: true, root: REPO };
  for (const a of process.argv.slice(2)) {
    if (a === '--no-mp3') o.mp3 = false;
    else if (a === '--help') {
      process.stdout.write(USAGE);
      return 0;
    } else if (a.startsWith('--game=')) o.game = a.slice(7);
    else if (a.startsWith('--bank=')) o.bank = path.resolve(a.slice(7));
    else if (a.startsWith('--root=')) o.root = path.resolve(a.slice(7));
    else if (a.startsWith('--rpm=')) o.rpms = a.slice(6).split(',').map(Number);
    else {
      process.stderr.write(`preview: unknown argument "${a}"\n${USAGE}`);
      return 2;
    }
  }
  if (!o.game === !o.bank || (o.rpms && o.rpms.some((r) => !(r > 0)))) {
    process.stderr.write(USAGE);
    return 2;
  }
  try {
    const targets = [];
    if (o.bank) targets.push(o.bank);
    else if (o.game === 'all') {
      for (const b of findBanks(o.root)) {
        if (loadBank(b.bankPath).preview) targets.push(b.bankPath);
      }
    } else targets.push(bankPathOf(o.root, o.game));
    for (const t of targets) {
      const files = previewBank(t, { root: o.root, rpms: o.rpms, mp3: o.mp3 });
      process.stdout.write(`${path.basename(path.dirname(t))}: wrote ${files.length} preview file(s)\n`);
    }
  } catch (e) {
    process.stderr.write(`preview: ${e.message}\n`);
    return 2;
  }
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main();
