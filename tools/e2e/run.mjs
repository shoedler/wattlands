#!/usr/bin/env node
// tools/e2e/run.mjs: the multiplayer end-to-end test (BRIEF 3.6, 7.7). Owned by qa. Zero dependencies.
//
//   node tools/e2e/run.mjs --games=<id>[,<id>...] [options]      (--help lists the options)
//
// For each game: starts the relay and the mock Strava server, then one host and two clients of the
// app headless through tools/godot.sh (each with its own --profile-dir, --log-file, report and a
// MockTrainer, all on Autopilot at --sim-speed=1), reads WATTLANDS_ROOM from the host to start the
// clients, kills one client mid-session and restarts it with the same profile and code, and then
// asserts BRIEF 7.7: the same event sequence on every peer, final state within tolerance, every
// directive clamped, every applied ERG target and SIM grade inside the warm-up limits, no script
// errors, no desync warnings, no rate_limited, a valid FIT file per peer, exactly one mock upload
// from the auto-upload peer, a working reconnect, and <= 6 minutes excluding the cool-down. It
// writes build/e2e/<id>/report.json and runs tests/games/<id>/e2e_check.mjs <report> if present.
//
// Every Godot process runs inside ONE lease of 3 slots of the machine-wide Godot lock, taken once
// for the whole run (BRIEF 2). Every child gets WATTLANDS_NO_HW_CONTROL=1 and
// WATTLANDS_NO_NETWORK_INTEGRATIONS=1 and never sees FAL_KEY or WATTLANDS_ALLOW_ART; stdin is
// closed and every wait has a timeout.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { USAGE, parseArgs } from './lib/args.mjs';
import { E2E_LEASE, LOCK_TIMEOUT_MESSAGE, takeLease } from './lib/lease.mjs';
import { readManifest, runGame } from './lib/game.mjs';
import { killAll } from './lib/proc.mjs';
import { fmtSeconds } from './lib/util.mjs';

export const EXIT_OK = 0;
export const EXIT_FAIL = 1;
export const EXIT_USAGE = 2;
export const EXIT_LOCK_TIMEOUT = 75;

const out = (line) => process.stdout.write(`${line}\n`);
const err = (line) => process.stderr.write(`${line}\n`);

export async function main(argv) {
  const parsed = parseArgs(argv);
  if (parsed.help) {
    out(USAGE);
    return EXIT_OK;
  }
  if (!parsed.ok) {
    err(`e2e: ${parsed.error}`);
    err(USAGE);
    return EXIT_USAGE;
  }
  const o = parsed.opts;
  for (const id of o.games) {
    const m = readManifest(o.repo, id);
    if (!m.ok && !fs.existsSync(path.join(o.repo, 'src', 'games', id))) {
      err(`e2e: unknown game "${id}" (no src/games/${id}/ in ${o.repo})`);
      return EXIT_USAGE;
    }
  }

  out(`e2e: waiting for ${E2E_LEASE} Godot slots (one lease for the whole run)`);
  let lease;
  try {
    lease = await takeLease({ lease: E2E_LEASE, lockTimeoutS: o.lockTimeoutS, label: `e2e run.mjs --games=${o.games.join(',')}`, log: err });
  } catch (e) {
    if (e.code === 'ELOCKTIMEOUT') {
      err(LOCK_TIMEOUT_MESSAGE);
      return EXIT_LOCK_TIMEOUT;
    }
    err(`e2e: ${e.message}`);
    return EXIT_FAIL;
  }
  out(`e2e: holding Godot lease ticket ${lease.seq} (${lease.lease} slots)`);

  const onSignal = (sig) => {
    err(`e2e: ${sig}, stopping every peer`);
    killAll();
    lease.release();
    process.exit(130);
  };
  const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'];
  if (process.platform === 'win32') signals.push('SIGBREAK');
  for (const s of signals) process.on(s, onSignal);

  const results = [];
  try {
    for (const id of o.games) {
      out(`e2e: ${id}: start`);
      const r = await runGame(o, id, lease, out);
      results.push(r);
      out(`e2e: ${id} ${r.ok ? 'PASS' : 'FAIL'} (${fmtSeconds(r.durationS)} excl. cool-down) -> ${r.reportPath}`);
      for (const f of r.failures) out(`e2e:   ${f}`);
    }
  } finally {
    killAll();
    lease.release();
    for (const s of signals) process.off(s, onSignal);
  }
  const failed = results.filter((r) => !r.ok);
  out(`e2e: ${results.length - failed.length} of ${results.length} game(s) passed${failed.length ? `; failed: ${failed.map((r) => r.gameId).join(', ')}` : ''}`);
  return failed.length ? EXIT_FAIL : EXIT_OK;
}

function isMain() {
  if (!process.argv[1]) return false;
  const norm = (p) => {
    let r = path.resolve(p);
    try {
      r = fs.realpathSync(r);
    } catch {
      // keep resolved path
    }
    return process.platform === 'win32' ? r.toLowerCase() : r;
  };
  return norm(process.argv[1]) === norm(fileURLToPath(import.meta.url));
}

if (isMain()) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e) => {
      err(`e2e: ${e.stack || e}`);
      killAll();
      process.exit(EXIT_FAIL);
    },
  );
}
