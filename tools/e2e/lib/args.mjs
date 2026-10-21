// tools/e2e/lib/args.mjs: the harness's command line (pure, unit-tested).
import path from 'node:path';
import { DEFAULT_REPO } from './util.mjs';

export const USAGE = `usage: node tools/e2e/run.mjs --games=<id>[,<id>...] [options]

Plays each game's e2e_content with one host and two clients (headless Godot, mock trainers,
Autopilot, --sim-speed=1) through a local relay and the mock Strava server, under one Godot lock
lease of 3 slots, kills and restarts one client mid-session, and checks the BRIEF 7.7 assertions.
Writes build/e2e/<id>/report.json and runs tests/games/<id>/e2e_check.mjs <report> if it exists.

options:
  --games=<ids>             comma list of registered game ids (required)
  --seed=<n>                session seed (default 1)
  --mock-trainer=<profile>  every peer's MockTrainer profile (default erg:compliance=1.0; never off)
  --auto-upload=<peer>      the peer that connects the mock Strava and auto-uploads: host, client1
                            or client2 (default client1)
  --out=<dir>               output root (default <repo>/build/e2e)
  --relay-cmd=<cmd>         relay command; {port} is replaced and PORT is set
                            (default "node server/relay/src/main.ts", with --experimental-strip-types
                            on a Node without default type stripping: 22.12-22.17, 23.0-23.5)
  --strava-cmd=<cmd>        mock Strava command; with {port} the harness picks the port, otherwise
                            it reads it from the output; {pid} is the harness's pid
                            (default "node server/mock_strava/server.mjs --port=0 --parent-pid={pid}")
  --strava-admin=<path>     the mock's upload listing (default: tries /admin/uploads, /__admin/uploads, ...)
  --fit-check-cmd=<cmd>     FIT checker; FIT paths and --json are appended
                            (default node tools/fit_check/check.mjs, else tools/fit_decode/decode.gd)
  --kill-after=<s>          kill the victim client this long after its session starts (default 25)
  --restart-delay=<s>       restart it after this pause (default 3)
  --game-timeout=<s>        hard limit for one game, cool-down included (default 660)
  --max-duration=<s>        allowed time per game excluding the cool-down (default 360)
  --cooldown-s=<s>          cool-down length used when the host doesn't report it (default 180)
  --boot-timeout=<s>        wait this long for a peer to report its room or session (default 180)
  --service-timeout=<s>     wait this long for the relay and mock Strava (default 30)
  --lock-timeout=<s>        wait this long for the 3 Godot slots (default 2700): exit 75
  --peer-cmd=<cmd>          start peers with this instead of tools/godot.sh (harness tests only)
  --repo=<dir>              the checkout to run (default: this harness's checkout)
  --keep                    keep the previous build/e2e/<id> output instead of clearing it
  --verbose                 echo every peer's output
  --help

exit codes: 0 every game passed, 1 a game failed, 2 usage error, 75 Godot lock wait timeout.`;

/**
 * True when this Node runs the relay's TypeScript only with --experimental-strip-types: the flag
 * exists from 22.6, and type stripping is on by default from 22.18 and 23.6 (BRIEF 5.3;
 * server/relay/README.md; W3 PKG-8).
 */
export function needsStripTypesFlag(version = process.versions.node) {
  const [major, minor] = String(version).replace(/^v/, '').split('.').map((n) => Number(n));
  if (!Number.isFinite(major) || !Number.isFinite(minor)) return false;
  if (major === 22) return minor >= 6 && minor < 18;
  if (major === 23) return minor < 6;
  return false;
}

/** The relay command for this Node (see needsStripTypesFlag). */
export function defaultRelayCmd(version = process.versions.node) {
  return needsStripTypesFlag(version)
    ? 'node --experimental-strip-types server/relay/src/main.ts'
    : 'node server/relay/src/main.ts';
}

export const PEER_ROLES = ['host', 'client1', 'client2'];
/** The client that is killed and restarted. */
export const VICTIM = 'client2';

export const DEFAULTS = Object.freeze({
  games: [],
  seed: 1,
  mockTrainer: 'erg:compliance=1.0',
  autoUpload: 'client1',
  out: null,
  relayCmd: defaultRelayCmd(),
  stravaCmd: 'node server/mock_strava/server.mjs --port=0 --parent-pid={pid}',
  stravaAdmin: null,
  fitCheckCmd: null,
  killAfterS: 25,
  restartDelayS: 3,
  gameTimeoutS: 660,
  maxDurationS: 360,
  cooldownS: 180,
  bootTimeoutS: 180,
  serviceTimeoutS: 30,
  lockTimeoutS: 2700,
  peerCmd: null,
  repo: null,
  keep: false,
  verbose: false,
  waitPeers: 3,
});

const NUMERIC = {
  '--seed': ['seed', { integer: true, min: 0 }],
  '--kill-after': ['killAfterS', { min: 0 }],
  '--restart-delay': ['restartDelayS', { min: 0 }],
  '--game-timeout': ['gameTimeoutS', { min: 1 }],
  '--max-duration': ['maxDurationS', { min: 1 }],
  '--cooldown-s': ['cooldownS', { min: 0 }],
  '--boot-timeout': ['bootTimeoutS', { min: 1 }],
  '--service-timeout': ['serviceTimeoutS', { min: 1 }],
  '--lock-timeout': ['lockTimeoutS', { min: 0 }],
};

const STRINGS = {
  '--out': 'out',
  '--relay-cmd': 'relayCmd',
  '--strava-cmd': 'stravaCmd',
  '--strava-admin': 'stravaAdmin',
  '--fit-check-cmd': 'fitCheckCmd',
  '--peer-cmd': 'peerCmd',
  '--repo': 'repo',
};

export const GAME_ID_RE = /^[a-z][a-z0-9_]*$/;
/** Values that would mean "no mock trainer": the harness refuses them (BRIEF 1). */
const NOT_A_MOCK = /^(|none|off|no|false|0|real|ftms|ble|hw|hardware|trainer)$/i;

/**
 * Parses argv. Returns {ok: true, opts} or {ok: false, error} or {ok: true, help: true}.
 * opts.repo and opts.out are absolute; opts.peerTimeoutS and opts.runSeconds are derived.
 */
export function parseArgs(argv) {
  const o = { ...DEFAULTS, games: [] };
  let gamesSeen = false;
  for (const a of argv) {
    if (a === '--help' || a === '-h') return { ok: true, help: true };
    if (a === '--allow-hw' || a === '--allow-network') {
      return { ok: false, error: `refusing ${a}: the end-to-end test never drops the hardware or network lock (BRIEF 1)` };
    }
    if (a === '--keep') {
      o.keep = true;
      continue;
    }
    if (a === '--verbose') {
      o.verbose = true;
      continue;
    }
    const eq = a.indexOf('=');
    if (!a.startsWith('--') || eq < 0) return { ok: false, error: `unknown argument "${a}" (options use --name=value)` };
    const key = a.slice(0, eq);
    const val = a.slice(eq + 1);
    if (key === '--games') {
      gamesSeen = true;
      for (const g of val.split(',').map((s) => s.trim()).filter(Boolean)) {
        if (!GAME_ID_RE.test(g)) return { ok: false, error: `bad game id "${g}" (ids match ${GAME_ID_RE})` };
        if (!o.games.includes(g)) o.games.push(g);
      }
    } else if (key === '--mock-trainer') {
      if (NOT_A_MOCK.test(val.trim())) {
        return { ok: false, error: `refusing to run without a mock trainer (--mock-trainer=${val}); every peer rides a MockTrainer (BRIEF 1)` };
      }
      o.mockTrainer = val.trim();
    } else if (key === '--auto-upload') {
      if (!PEER_ROLES.includes(val)) return { ok: false, error: `--auto-upload must be one of ${PEER_ROLES.join(', ')}` };
      o.autoUpload = val;
    } else if (key in NUMERIC) {
      const [field, rule] = NUMERIC[key];
      const n = Number(val);
      if (val.trim() === '' || !Number.isFinite(n) || n < rule.min || (rule.integer && !Number.isInteger(n))) {
        return { ok: false, error: `${key} needs ${rule.integer ? 'a whole number' : 'a number'} >= ${rule.min}, got "${val}"` };
      }
      o[field] = n;
    } else if (key in STRINGS) {
      if (val.trim() === '') return { ok: false, error: `${key} needs a value` };
      o[STRINGS[key]] = val;
    } else {
      return { ok: false, error: `unknown option "${key}"` };
    }
  }
  if (!gamesSeen || o.games.length === 0) return { ok: false, error: '--games=<id>[,<id>...] is required' };
  if (o.mockTrainer.includes(' ')) return { ok: false, error: '--mock-trainer must not contain spaces' };
  o.repo = path.resolve(o.repo ?? DEFAULT_REPO);
  o.out = path.resolve(o.repo, o.out ?? path.join('build', 'e2e'));
  o.peerTimeoutS = o.gameTimeoutS + 60;
  o.runSeconds = o.gameTimeoutS;
  return { ok: true, opts: o };
}
