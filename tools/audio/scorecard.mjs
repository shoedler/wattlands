#!/usr/bin/env node
// The game developer and game audio creator rows of SPEC_AUDIO 6.2, in pure JS. Writes
// build/audio_preview/<game>_scorecard.json; exit 1 on any FAIL that has no waiver.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { bankPathOf, findBanks, loadBank } from './lib/bank.mjs';
import { scoreBankFile } from './lib/score.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

const USAGE = `usage: node tools/audio/scorecard.mjs --game=<id>|all [--bank=<path>] [--root=<dir>] [--json]

Exit codes: 0 every row passes or is waived, 1 a row failed, 2 usage or bank error.
`;

function main() {
  const o = { game: null, bank: null, json: false, root: REPO };
  for (const a of process.argv.slice(2)) {
    if (a === '--json') o.json = true;
    else if (a === '--help') {
      process.stdout.write(USAGE);
      return 0;
    } else if (a.startsWith('--game=')) o.game = a.slice(7);
    else if (a.startsWith('--bank=')) o.bank = path.resolve(a.slice(7));
    else if (a.startsWith('--root=')) o.root = path.resolve(a.slice(7));
    else {
      process.stderr.write(`scorecard: unknown argument "${a}"\n${USAGE}`);
      return 2;
    }
  }
  if (!o.game === !o.bank) {
    process.stderr.write(`scorecard: give one of --game=<id>|all or --bank=<path>\n${USAGE}`);
    return 2;
  }
  const targets = [];
  try {
    if (o.bank) targets.push({ bankPath: o.bank });
    else if (o.game === 'all') {
      for (const b of findBanks(o.root)) {
        if (loadBank(b.bankPath).preview) targets.push(b);
      }
    } else targets.push({ bankPath: bankPathOf(o.root, o.game) });
  } catch (e) {
    process.stderr.write(`scorecard: ${e.message}\n`);
    return 2;
  }
  const outDir = path.join(o.root, 'build', 'audio_preview');
  fs.mkdirSync(outDir, { recursive: true });
  const ignore = path.join(o.root, 'build', '.gdignore');
  if (!fs.existsSync(ignore)) fs.writeFileSync(ignore, '');
  let failed = false;
  for (const t of targets) {
    let card;
    try {
      card = scoreBankFile(t.bankPath, { root: o.root });
    } catch (e) {
      process.stderr.write(`scorecard: ${e.message}\n`);
      return 2;
    }
    fs.writeFileSync(path.join(outDir, `${card.game}_scorecard.json`), `${JSON.stringify(card, null, 2)}\n`);
    if (o.json) process.stdout.write(`${JSON.stringify(card, null, 2)}\n`);
    else {
      process.stdout.write(`${card.game}: ${card.pass ? 'PASS' : `FAIL ${card.fails.join(' ')}`}\n`);
      for (const r of card.rows) {
        process.stdout.write(`  ${r.id.padEnd(4)} ${r.pass ? 'ok  ' : r.waived ? 'wvd ' : 'FAIL'} ${r.value}   (${r.target})${r.note ? ` ${r.note}` : ''}\n`);
      }
    }
    if (!card.pass) failed = true;
  }
  return failed ? 1 : 0;
}

process.exitCode = main();
