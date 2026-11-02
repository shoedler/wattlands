// tools/e2e/lib/fault_args.mjs: the command line of tools/e2e/faults.mjs (pure, unit-tested).
import path from 'node:path';
import { GAME_ID_RE, defaultRelayCmd } from './args.mjs';
import { DEFAULT_REPO } from './util.mjs';

/** The four games the built-in relay scenario plays. */
export const FAULT_GAMES = ['fishing', 'siege', 'tank', 'workout'];

/** Scenario families in run order; a family may run as several named variants (see variantsOf). */
export const SCENARIO_FAMILIES = ['builtin', 'wrong_code', 'late_join', 'relay_dies', 'relay_restarts', 'host_killed_relay', 'host_killed_builtin'];

/** The named variants of one family: "builtin:<game>", "wrong_code:relay|builtin", "late_join:relay|builtin". */
export function variantsOf(family, games = FAULT_GAMES) {
  if (family === 'builtin') return games.map((g) => `builtin:${g}`);
  if (family === 'wrong_code' || family === 'late_join') return [`${family}:relay`, `${family}:builtin`];
  return [family];
}

/** The family a scenario name belongs to ("builtin:siege" is "builtin"). */
export function familyOf(name) {
  return String(name).split(':')[0];
}

export const FAULTS_USAGE = `usage: node tools/e2e/faults.mjs [--games=<id>[,<id>...]] [--scenarios=<name>[,<name>...]] [options]

Proves the multiplayer failure paths with real headless peers (tools/godot.sh, mock trainers,
Autopilot) on the built-in relay and on server/relay. Writes build/e2e_faults/report.json: one named
pass or fail per scenario, with the evidence (exit codes, WATTLANDS_* lines, report JSON, error lines,
FIT files) of every peer.

scenarios (a family runs all its variants; "builtin:siege" or "wrong_code:relay" picks one):
  builtin             host on the built-in relay, a client joins by code over loopback beacons, the
                      client is killed and restarted and comes back as the same peer (per game)
  wrong_code          a client joining a code that does not exist is refused with room_not_found
                      (variants relay, builtin)
  late_join           a third peer joining a running room is refused with session_in_progress and the
                      session is unharmed (variants relay, builtin)
  relay_dies          workout on server/relay: the relay is killed mid-session and stays dead (minutes)
  relay_restarts      workout: the relay is killed and started again on its port (rooms gone)
  host_killed_relay   workout: the host is killed on the relay (the relay holds the room 120 s)
  host_killed_builtin workout: the host is killed on the built-in relay

options:
  --games=<ids>          games of the builtin scenario (default fishing,siege,tank,workout)
  --scenarios=<names>    what to run (default all)
  --out=<dir>            output root (default <repo>/build/e2e_faults)
  --seed=<n>             session seed (default 1)
  --run-seconds=<n>      hard stop of the short scenarios, platform seconds (default 70)
  --kill-after=<s>       kill the victim this long after its session starts (default 8)
  --restart-delay=<s>    restart it after this pause (default 3)
  --boot-timeout=<s>     wait this long for a peer's room or peer line (default 120)
  --end-timeout=<s>      wait this long for the peers of a short scenario to end (default 150)
  --long-timeout=<s>     the same for the scenarios that ride out a cool-down or the relay's 120 s
                         windows (default 900)
  --relay-cmd=<cmd>      relay command; {port} is replaced and PORT is set (default as run.mjs)
  --service-timeout=<s>  wait this long for the relay (default 30)
  --lock-timeout=<s>     wait this long for the Godot slots (default 2700): exit 75
  --peer-cmd=<cmd>       start peers with this instead of tools/godot.sh (harness tests only)
  --repo=<dir>           the checkout to run (default: this harness's checkout)
  --verbose              echo every peer's output
  --help

exit codes: 0 every scenario passed, 1 one failed, 2 usage error, 75 Godot lock wait timeout.`;

const NUMERIC = {
  '--seed': ['seed', { integer: true, min: 0 }],
  '--run-seconds': ['runSeconds', { min: 5 }],
  '--kill-after': ['killAfterS', { min: 0 }],
  '--restart-delay': ['restartDelayS', { min: 0 }],
  '--boot-timeout': ['bootTimeoutS', { min: 1 }],
  '--end-timeout': ['endTimeoutS', { min: 1 }],
  '--long-timeout': ['longTimeoutS', { min: 1 }],
  '--service-timeout': ['serviceTimeoutS', { min: 1 }],
  '--lock-timeout': ['lockTimeoutS', { min: 0 }],
};
const STRINGS = { '--out': 'out', '--relay-cmd': 'relayCmd', '--peer-cmd': 'peerCmd', '--repo': 'repo' };

export const FAULT_DEFAULTS = Object.freeze({
  games: FAULT_GAMES,
  scenarios: null,
  seed: 1,
  runSeconds: 70,
  killAfterS: 8,
  restartDelayS: 3,
  bootTimeoutS: 120,
  endTimeoutS: 150,
  longTimeoutS: 900,
  serviceTimeoutS: 30,
  lockTimeoutS: 2700,
  mockTrainer: 'erg:compliance=1.0',
  out: null,
  relayCmd: null,
  peerCmd: null,
  repo: null,
  verbose: false,
  waitPeers: 2,
});

/**
 * Parses argv. Returns {ok: true, opts, names} (names: the scenario variants to run, in order),
 * {ok: true, help: true} or {ok: false, error}.
 */
export function parseFaultArgs(argv) {
  const o = { ...FAULT_DEFAULTS };
  let games = null;
  let wanted = null;
  for (const a of argv) {
    if (a === '--help' || a === '-h') return { ok: true, help: true };
    if (a === '--allow-hw' || a === '--allow-network') {
      return { ok: false, error: `refusing ${a}: the fault test never drops the hardware or network lock (BRIEF 1)` };
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
      games = [];
      for (const g of val.split(',').map((s) => s.trim()).filter(Boolean)) {
        if (!GAME_ID_RE.test(g)) return { ok: false, error: `bad game id "${g}" (ids match ${GAME_ID_RE})` };
        if (!FAULT_GAMES.includes(g)) return { ok: false, error: `unknown game "${g}" (the builtin scenario plays ${FAULT_GAMES.join(', ')})` };
        if (!games.includes(g)) games.push(g);
      }
      if (games.length === 0) return { ok: false, error: '--games needs at least one game id' };
    } else if (key === '--scenarios') {
      wanted = val.split(',').map((s) => s.trim()).filter(Boolean);
      if (wanted.length === 0) return { ok: false, error: '--scenarios needs at least one scenario name' };
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
  if (games) o.games = games;
  const all = SCENARIO_FAMILIES.flatMap((f) => variantsOf(f, o.games));
  const everyVariant = SCENARIO_FAMILIES.flatMap((f) => variantsOf(f, FAULT_GAMES));
  let names;
  if (wanted === null) names = all;
  else {
    names = [];
    for (const w of wanted) {
      const picked = SCENARIO_FAMILIES.includes(w) ? variantsOf(w, o.games) : everyVariant.includes(w) ? [w] : null;
      if (!picked) return { ok: false, error: `unknown scenario "${w}" (known: ${SCENARIO_FAMILIES.join(', ')}, or a variant such as wrong_code:relay)` };
      for (const n of picked) if (!names.includes(n)) names.push(n);
    }
    names.sort((x, y) => all.concat(everyVariant).indexOf(x) - all.concat(everyVariant).indexOf(y));
  }
  o.repo = path.resolve(o.repo ?? DEFAULT_REPO);
  o.out = path.resolve(o.repo, o.out ?? path.join('build', 'e2e_faults'));
  o.relayCmd ??= defaultRelayCmd();
  o.peerTimeoutS = Math.max(o.longTimeoutS, o.endTimeoutS) + 120;
  return { ok: true, opts: o, names };
}
