#!/usr/bin/env node
// Render audio recipes (assets/<id>/audio/audio.json) to WAV, sidecar and manifest. Seeded and
// deterministic. No network, no ffmpeg, no art service. See docs/AUDIO_PIPELINE.md.

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { bankPathOf, checkBank, findBanks, generateBank } from './lib/bank.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

const USAGE = `usage: node tools/audio/generate.mjs --game=<id>|all [options]

  --game=<id>|all    a game's assets/<id>/audio/audio.json; "_shared" is the UI set; all is every bank
  --bank=<path>      one bank file instead of --game (the import proof fixtures); no pruning
  --only=<ids>       comma list of sound ids
  --check            render in memory and compare with disk, writing nothing; exit 1 on a mismatch
  --root=<dir>       project root (default: this repo)
  --help             this text

Exit codes: 0 done, 1 --check found a mismatch, 2 usage or bank error.
`;

function parse(argv) {
  const o = { game: null, bank: null, only: [], check: false, root: REPO, help: false };
  for (const a of argv) {
    if (a === '--check') o.check = true;
    else if (a === '--help') o.help = true;
    else if (a.startsWith('--game=')) o.game = a.slice(7);
    else if (a.startsWith('--bank=')) o.bank = a.slice(7);
    else if (a.startsWith('--only=')) o.only = a.slice(7).split(',').map((s) => s.trim()).filter(Boolean);
    else if (a.startsWith('--root=')) o.root = path.resolve(a.slice(7));
    else throw new Error(`unknown argument "${a}"`);
  }
  if (!o.help && !o.game === !o.bank) throw new Error('give one of --game=<id>|all or --bank=<path>');
  if (o.game && o.game !== 'all' && !/^[a-z0-9_]+$/.test(o.game)) throw new Error(`--game: "${o.game}" is not a game id`);
  return o;
}

function targets(o) {
  if (o.bank) return [{ game: path.basename(o.bank), bankPath: path.resolve(o.bank), prune: false }];
  if (o.game === 'all') return findBanks(o.root).map((b) => ({ ...b, prune: true }));
  return [{ game: o.game, bankPath: bankPathOf(o.root, o.game), prune: true }];
}

function main() {
  let o;
  try {
    o = parse(process.argv.slice(2));
  } catch (e) {
    process.stderr.write(`generate: ${e.message}\n${USAGE}`);
    return 2;
  }
  if (o.help) {
    process.stdout.write(USAGE);
    return 0;
  }
  let failed = false;
  try {
    for (const t of targets(o)) {
      if (o.check) {
        const problems = checkBank(t.bankPath, { only: o.only });
        for (const p of problems) process.stdout.write(`${t.game}: ${p}\n`);
        if (problems.length > 0) failed = true;
        else process.stdout.write(`${t.game}: matches disk\n`);
      } else {
        const r = generateBank(t.bankPath, { root: o.root, only: o.only, prune: t.prune });
        process.stdout.write(`${t.game}: wrote ${r.written} file(s)${r.removed.length > 0 ? `, removed ${r.removed.join(', ')}` : ''}\n`);
      }
    }
  } catch (e) {
    process.stderr.write(`generate: ${e.message}\n`);
    return 2;
  }
  return failed ? 1 : 0;
}

process.exitCode = main();
