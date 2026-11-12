#!/usr/bin/env node
// tools/lib/gate.mjs: the CLI behind tools/gate (bash) and tools/gate.ps1. Concurrent lanes over the
// same verdict code as tools/run_tests, the bulletproofing rules of `check`, and the worktree chores.
// The logic lives in gate_core.mjs; this file is git, processes and printing. Zero dependencies.
// docs/decisions/gate.md says why; tools/run_tests stays the literal, serial gate.
//
// Exit: 0 pass, 1 fail, 2 usage, 3 refused (dirty tree, another gate in this checkout), 4 `wait` has no
// verdict to give (none written, another gate's, or for another tree), 75 lock timeout, 124 `wait` timed
// out while the gate still runs.

import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Worker } from 'node:worker_threads';
import { acquire, killTree, LEASE_TOKEN_ENV, LOCK_TIMEOUT_MESSAGE, lockDir, machineCap, pidAlive, readTickets, WHOLE_MACHINE_LEASE } from './godot_lock.mjs';
import { evaluateGut, junitCounts, readGreenCount, readPendingAllowlist } from './gut_gate.mjs';
import { ensureBuildDir, ensureNpm, GDTOOLKIT_VERSION, greenFloor, GREEN_FLOOR_FILE, NODE_SUITES, registeredGames, run, TEST_FILE_RE, wrapperCommand } from './run_tests.mjs';
import {
  aggregateGut,
  allowGap,
  buildDirGroups,
  checkAddedText,
  checkClassNames,
  checkerEvidence,
  checkNodeTestCounts,
  checkPaths,
  checkPinContent,
  checkPinCoverage,
  checkPins,
  crossGameRefs,
  CROSS_SCAN_ROOTS,
  formatCrossRef,
  gateAlive,
  checkSidecars,
  checkTestCounts,
  computePins,
  fastNarrowing,
  inferWs,
  isScannedFile,
  isGutFile,
  junitCountProblems,
  junitCoverage,
  laneVerdict,
  longestFirst,
  listGutFiles,
  manifestPins,
  matrixRule,
  parseAddedLines,
  parsePlan,
  parseTestRemovals,
  pinSpecOf,
  planShards,
  poolSizes,
  globToRegExp,
  gutSelection,
  selectGutFiles,
  selectionGap,
  quietRetryPlan,
  readWeights,
  revertedSha,
  sourceTestCounts,
  touchedGames,
  WAIT_FOR_RE,
  WAIT_NO_VERDICT_EXIT,
  waitVerdict,
  weightsByGroup,
  isMaintainerReview,
  contributorWords,
} from './gate_core.mjs';

const LIB = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.dirname(path.dirname(LIB));
const MANIFEST_FILE = 'tools/lib/gate_manifest.json';
const WEIGHTS_FILE = 'tools/lib/gate_weights.json';
const PINS_FILE = 'tools/lib/safety_pins.json';
const GUT_CONFIG = '.gutconfig.json';
const LANE_CEILING_S = 2 * 60 * 60;
const SHARD_TIMEOUT_S = 1800;
const SIM_OUTER_TIMEOUT_S = 3600;
const E2E_STAGGER_MS = 2000;
const NPM_DIRS = ['server/relay', 'tools/fit_check'];
const LINT_DIRS = ['addons/wattlands/', 'src/', 'tests/', 'tools/'];
const FMT_BATCH = 100;
const FMT_NAMED_MAX = 150; // above this, one command line gets long: fmt loads every script instead
const LARGE_FILE_BYTES = 5 * 1024 * 1024;
const AUDIO_BUDGET_BYTES = 40 * 1024 * 1024;
const TEMP_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const COAUTHOR = 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>';

const USAGE = `usage: tools/gate <command> [options]      (tools/gate.ps1 in PowerShell)
  check  [--base=main] [--ws=<id>] [--contributor] [--allow=<glob>]... [--allow-pin=<file>:<function>]...
  fast   [--base=main] [--ws=<id>] [--contributor] [--allow=..]... [--allow-pin=..]... [--games=<ids>|all] [--shards=<n>] [--lanes=<names>]
  strict [--ws=<id>] [--allow=..]... [--allow-pin=..]... [--serial-gut]
  matrix --game=<id> [--jobs=<n>] [--scenarios=s1,s4]
  stamp-ok <worktree> [--matrix=<id>] [--allow=..]... [--allow-pin=..]...
  floor  --label="<text>"
  fmt    [--base=main]
  wait   [--for=fast|strict|matrix_<id>] [--timeout=540]
  wt-add <name> <branch> [--from=main] [--wt-root=<dir>]
  wt-gc  [--apply] [--base=main]
  pin-safety --reason="<text>"
Every command also takes --project=<dir> (default: this checkout).
Exit: 0 pass, 1 fail, 2 usage, 3 refused, 4 wait has no verdict (none written, another gate's, another tree),
75 lock timeout, 124 wait timed out (the gate still runs: wait again).
fast narrows GUT and the Node suites to what the change since --base reaches, and keeps audio verdicts in
build/test_cache: --games=all (or deleting that folder) runs and scores everything.`;

const CHECK_FLAGS = ['base', 'ws', 'allow', 'allowPin', 'contributor'];
const COMMANDS = {
  check: { flags: CHECK_FLAGS, positional: 0 },
  fast: { flags: [...CHECK_FLAGS, 'games', 'shards', 'lanes'], positional: 0 },
  strict: { flags: ['ws', 'allow', 'allowPin', 'serialGut'], positional: 0 },
  matrix: { flags: ['game', 'jobs', 'scenarios'], positional: 0 },
  'stamp-ok': { flags: ['matrix', 'allow', 'allowPin'], positional: 1 },
  floor: { flags: ['label'], positional: 0 },
  fmt: { flags: ['base'], positional: 0 },
  wait: { flags: ['timeout', 'for'], positional: 0 },
  'wt-add': { flags: ['from', 'wtRoot'], positional: 2 },
  'wt-gc': { flags: ['apply', 'base'], positional: 0 },
  'pin-safety': { flags: ['reason'], positional: 0 },
};
const FLAG_KEYS = {
  '--base': 'base',
  '--ws': 'ws',
  '--allow': 'allow',
  '--allow-pin': 'allowPin',
  '--contributor': 'contributor',
  '--games': 'games',
  '--shards': 'shards',
  '--lanes': 'lanes',
  '--serial-gut': 'serialGut',
  '--game': 'game',
  '--jobs': 'jobs',
  '--scenarios': 'scenarios',
  '--matrix': 'matrix',
  '--label': 'label',
  '--from': 'from',
  '--wt-root': 'wtRoot',
  '--apply': 'apply',
  '--reason': 'reason',
  '--timeout': 'timeout',
  '--for': 'for',
};
const BARE_FLAGS = new Set(['serialGut', 'apply', 'contributor']);

class Exit extends Error {
  constructor(code, message = '') {
    super(message);
    this.code = code;
  }
}

const usageError = (msg) => new Exit(2, `gate: ${msg}\n${USAGE}`);
const out = (text) => process.stdout.write(`${text}\n`);

// ---------------------------------------------------------------- options

export function parseCli(argv) {
  const o = {
    cmd: null,
    positional: [],
    shell: process.platform === 'win32' ? 'ps' : 'bash',
    project: REPO,
    base: 'main',
    ws: null,
    allow: [],
    allowPin: [],
    games: null,
    shards: null,
    lanes: null,
    serialGut: false,
    game: null,
    jobs: null,
    scenarios: [],
    matrix: null,
    label: null,
    from: 'main',
    wtRoot: null,
    apply: false,
    reason: null,
    timeout: null,
    for: null,
  };
  const given = [];
  const list = (v) => v.split(',').map((s) => s.trim()).filter(Boolean);
  const positiveInt = (flag, v) => {
    const n = Number(v);
    if (!Number.isInteger(n) || n < 1) throw usageError(`${flag} needs a positive integer, got "${v}"`);
    return n;
  };
  for (const a of argv) {
    if (a === '--help' || a === '-h') throw new Exit(0, USAGE);
    if (!a.startsWith('--')) {
      if (o.cmd === null) o.cmd = a;
      else o.positional.push(a);
      continue;
    }
    const eq = a.indexOf('=');
    const flag = eq >= 0 ? a.slice(0, eq) : a;
    const val = eq >= 0 ? a.slice(eq + 1) : null;
    if (flag === '--shell' && (val === 'bash' || val === 'ps')) {
      o.shell = val;
      continue;
    }
    if (flag === '--project' && val) {
      o.project = path.resolve(val);
      continue;
    }
    const key = FLAG_KEYS[flag];
    if (!key) throw usageError(`unknown option "${a}"`);
    if (BARE_FLAGS.has(key) !== (val === null) || val === '') throw usageError(`bad option "${a}"`);
    given.push(key);
    if (key === 'allow' || key === 'allowPin') o[key].push(val);
    else if (BARE_FLAGS.has(key)) o[key] = true;
    else if (key === 'shards' || key === 'jobs' || key === 'timeout') o[key] = positiveInt(flag, val);
    else if (key === 'games' || key === 'lanes' || key === 'scenarios') o[key] = list(val);
    else o[key] = val;
  }
  if (o.cmd === null) throw usageError('no command');
  const spec = COMMANDS[o.cmd];
  if (!spec) throw usageError(`unknown command "${o.cmd}"`);
  for (const key of given) {
    if (!spec.flags.includes(key)) throw usageError(`${o.cmd} does not take --${key}`);
  }
  if (o.positional.length !== spec.positional) throw usageError(`${o.cmd} takes ${spec.positional} argument(s)`);
  if (o.cmd === 'matrix' && !o.game) throw usageError('matrix needs --game=<id>');
  if (o.cmd === 'floor' && !o.label) throw usageError('floor needs --label=<text>');
  if (o.cmd === 'pin-safety' && !o.reason) throw usageError('pin-safety needs --reason=<text>');
  if (o.for !== null && !WAIT_FOR_RE.test(o.for)) throw usageError(`--for takes fast, strict or matrix_<id>, got "${o.for}"`);
  return o;
}

// ---------------------------------------------------------------- environment

/** Git Bash's bash.exe on Windows, never WSL's System32\bash.exe. */
function findBash() {
  const env = process.env.WATTLANDS_BASH;
  if (env && (fs.existsSync(env) || fs.existsSync(`${env}.exe`))) return env;
  if (process.platform !== 'win32') return 'bash';
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    const low = dir.toLowerCase();
    if (!dir || low.includes('system32') || low.includes('windowsapps')) continue;
    const exe = path.join(dir, 'bash.exe');
    if (fs.existsSync(exe)) return exe;
  }
  for (const c of ['C:\\Program Files\\Git\\usr\\bin\\bash.exe', 'C:\\Program Files\\Git\\bin\\bash.exe']) {
    if (fs.existsSync(c)) return c;
  }
  return 'bash';
}

/** What every child starts from: both locks on, no art key or permission, not nested in a run_tests. */
function childEnv(extra = {}) {
  const env = { ...process.env, ...extra };
  env.WATTLANDS_NO_HW_CONTROL = '1';
  env.WATTLANDS_NO_NETWORK_INTEGRATIONS = '1';
  for (const name of ['FAL_KEY', 'WATTLANDS_ALLOW_ART', 'WATTLANDS_RUN_TESTS_NESTED', 'WATTLANDS_SIM_PLAN']) delete env[name];
  return env;
}

/** Drops every <ID>_* variable: a game's sim script reads those to narrow or skip its matrix. */
function withoutGameVars(env, upper) {
  for (const key of Object.keys(env)) {
    if (key.toUpperCase().startsWith(`${upper}_`)) delete env[key];
  }
  return env;
}

/** A shell script's own tools (dirname, mkdir) are beside its bash; a PowerShell caller's PATH may lack them. */
function withBashPath(env, bash) {
  if (!path.isAbsolute(bash)) return env;
  const key = Object.keys(env).find((k) => k.toUpperCase() === 'PATH') ?? 'PATH';
  env[key] = `${path.dirname(bash)}${path.delimiter}${env[key] ?? ''}`;
  return env;
}

// ---------------------------------------------------------------- git

function gitRaw(cwd, args, { input } = {}) {
  return spawnSync('git', ['-c', 'core.quotepath=off', ...args], { cwd, input, maxBuffer: 2 ** 31 - 1, windowsHide: true });
}

function git(cwd, args, opts) {
  const r = gitRaw(cwd, args, opts);
  if (r.status !== 0) throw new Exit(2, `gate: git ${args.join(' ')} failed: ${String(r.stderr).trim()}`);
  return r.stdout.toString('utf8');
}

const gitLine = (cwd, args) => git(cwd, args).trim();
const zList = (text) => text.split('\0').filter(Boolean);

function treeOf(cwd, rev = 'HEAD') {
  return gitLine(cwd, ['rev-parse', `${rev}^{tree}`]);
}

function statusLines(cwd) {
  return git(cwd, ['status', '--porcelain', '--untracked-files=all']).split('\n').map((l) => l.replace(/\r$/, '')).filter(Boolean);
}

/** {spec -> Buffer|null} for specs of the form rev:path, through one `git cat-file --batch`. */
function catBlobs(cwd, specs) {
  const outMap = new Map();
  if (specs.length === 0) return outMap;
  const r = gitRaw(cwd, ['cat-file', '--batch'], { input: `${specs.join('\n')}\n` });
  if (r.status !== 0) throw new Exit(2, `gate: git cat-file failed: ${String(r.stderr).trim()}`);
  const buf = r.stdout;
  let at = 0;
  for (const spec of specs) {
    const nl = buf.indexOf(10, at);
    const head = buf.toString('utf8', at, nl);
    at = nl + 1;
    const m = /^[0-9a-f]+ \w+ (\d+)$/.exec(head);
    if (!m) {
      outMap.set(spec, null);
      continue;
    }
    const size = Number(m[1]);
    outMap.set(spec, buf.subarray(at, at + size));
    at += size + 1;
  }
  return outMap;
}

function readAt(cwd, rev, file) {
  const b = catBlobs(cwd, [`${rev}:${file}`]).get(`${rev}:${file}`);
  return b ? b.toString('utf8') : null;
}

function gdSourcesAt(cwd, rev) {
  const files = zList(git(cwd, ['ls-tree', '-r', '--name-only', '-z', rev, '--', 'tests'])).filter(isGutFile);
  const blobs = catBlobs(cwd, files.map((f) => `${rev}:${f}`));
  const srcs = {};
  for (const f of files) srcs[f] = blobs.get(`${rev}:${f}`)?.toString('utf8') ?? '';
  return srcs;
}

/** The suite `node --test` runs a file in, or null: NODE_SUITES, then tests/games/<id>. */
function nodeSuiteOf(file) {
  const suite = NODE_SUITES.find((s) => file.startsWith(`${s}/`));
  if (suite) return suite;
  return /^tests\/games\/[^/]+(?=\/)/.exec(file)?.[0] ?? null;
}

/** The test files of the Node suites at a rev, as run_tests finds them: {path: source}. */
function nodeSourcesAt(cwd, rev) {
  const roots = [...NODE_SUITES, 'tests/games'];
  const isTestFile = (f) => {
    const parts = f.split('/');
    if (parts.some((p) => p.startsWith('.') || p === 'node_modules')) return false;
    return TEST_FILE_RE.test(parts.at(-1)) || (parts.slice(0, -1).includes('test') && /\.[cm]?js$/.test(f));
  };
  const files = zList(git(cwd, ['ls-tree', '-r', '--name-only', '-z', rev, '--', ...roots])).filter((f) => nodeSuiteOf(f) !== null && isTestFile(f));
  const blobs = catBlobs(cwd, files.map((f) => `${rev}:${f}`));
  const srcs = {};
  for (const f of files) srcs[f] = blobs.get(`${rev}:${f}`)?.toString('utf8') ?? '';
  return srcs;
}

function parseNameStatus(text) {
  const parts = zList(text);
  const changes = [];
  for (let i = 0; i < parts.length; ) {
    const status = parts[i];
    if (status[0] === 'R' || status[0] === 'C') {
      changes.push({ status: status[0], oldPath: status[0] === 'R' ? parts[i + 1] : undefined, path: parts[i + 2] });
      i += 3;
    } else {
      changes.push({ status: status[0], path: parts[i + 1] });
      i += 2;
    }
  }
  return changes;
}

function uncommittedChanges(cwd) {
  const parts = zList(git(cwd, ['status', '--porcelain=v1', '-z', '--untracked-files=all', '--no-renames']));
  return parts.map((p) => {
    const xy = p.slice(0, 2);
    const file = p.slice(3);
    if (xy === '??') return { status: 'A', path: file, untracked: true };
    if (xy.includes('D')) return { status: 'D', path: file };
    if (xy.includes('A')) return { status: 'A', path: file };
    return { status: 'M', path: file };
  });
}

function commitsInRange(cwd, base) {
  const text = git(cwd, ['log', '--no-merges', '--no-renames', '--format=%x1e%H%x1f%s%x1f%B%x1f', '--name-only', `${base}..HEAD`]);
  const commits = [];
  for (const chunk of text.split('\x1e')) {
    if (!chunk.trim()) continue;
    const [sha, subject, message, rest] = chunk.split('\x1f');
    commits.push({ sha, subject, message, paths: (rest ?? '').split('\n').map((l) => l.trim()).filter(Boolean) });
  }
  return commits;
}

// ---------------------------------------------------------------- check (SPEC_GATES 6)

function loadJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function loadManifest(project) {
  const m = loadJson(path.join(project, MANIFEST_FILE)) ?? loadJson(path.join(REPO, MANIFEST_FILE));
  if (!m) throw new Exit(2, `gate: no readable ${MANIFEST_FILE}`);
  return m;
}

const TEXT_READ_LIMIT = 8 * 1024 * 1024;

/** The lines of an untracked text file; null for a binary or very large one. */
function untrackedLines(project, file) {
  let buf;
  try {
    if (fs.statSync(path.join(project, file)).size > TEXT_READ_LIMIT) return null;
    buf = fs.readFileSync(path.join(project, file));
  } catch {
    return null;
  }
  if (buf.subarray(0, 8000).includes(0)) return null;
  return buf.toString('utf8').split('\n');
}

function diffAdded(project, args) {
  const text = git(project, ['diff', '-U0', '--no-color', '--no-ext-diff', '--no-textconv', '-M', '--src-prefix=a/', '--dst-prefix=b/', ...args]);
  return parseAddedLines(text);
}

function mergeAdded(a, b) {
  const merged = new Map(a);
  for (const [f, lines] of b) merged.set(f, [...(merged.get(f) ?? []), ...lines]);
  return merged;
}

function grepLines(project, pattern, pathspecs) {
  const r = gitRaw(project, ['grep', '-n', '-E', '--untracked', pattern, '--', ...pathspecs]);
  if (r.status === 1) return [];
  if (r.status !== 0) throw new Exit(2, `gate: git grep failed: ${String(r.stderr).trim()}`);
  return r.stdout.toString('utf8').split('\n').map((l) => l.replace(/\r$/, '')).filter(Boolean);
}

const globMatch = (glob, file) => globToRegExp(glob).test(file);

const parseFloor = (text) => {
  const n = Number.parseInt(String(text ?? '').trim(), 10);
  return Number.isInteger(n) ? n : null;
};

function floorAt(project, rev) {
  return parseFloor(readAt(project, rev, GREEN_FLOOR_FILE));
}

/** The highest floor any commit in HEAD's history held, or null. The count never goes down, in steps or at once. */
function highestFloor(project) {
  // --full-history: plain `git log -- <file>` drops the side of a merge that holds the evidence (`-s ours`).
  const shas = git(project, ['log', '--full-history', '--format=%H', '--', GREEN_FLOOR_FILE]).split('\n').map((l) => l.trim()).filter(Boolean);
  const blobs = catBlobs(project, shas.map((sha) => `${sha}:${GREEN_FLOOR_FILE}`));
  let top = null;
  for (const b of blobs.values()) {
    const n = b ? parseFloor(b.toString('utf8')) : null;
    if (n !== null && (top === null || n > top)) top = n;
  }
  return top;
}

/** tracked paths now: index plus untracked, without what the work tree deleted. */
function currentFiles(project) {
  const gone = new Set(zList(git(project, ['ls-files', '-d', '-z'])));
  return new Set(zList(git(project, ['ls-files', '-c', '-o', '--exclude-standard', '-z'])).filter((f) => !gone.has(f)));
}

function readQuiet(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return null;
  }
}

/** The roots of crossGameRefs for these games: src/games/<id>/, tests/games/<id>/, content/<id>/. */
const scanRoots = (ids) => ids.flatMap((id) => CROSS_SCAN_ROOTS.map((r) => r.replaceAll('<id>', id)));

/** {path: text} of the files the cross-game scan reads, as the work tree holds them now. */
function gameSourcesNow(project, ids, files = currentFiles(project)) {
  const roots = scanRoots(ids);
  const out = {};
  for (const f of files) {
    if (!isScannedFile(f) || !roots.some((r) => f.startsWith(r))) continue;
    try {
      out[f] = fs.readFileSync(path.join(project, f), 'utf8');
    } catch {
      // deleted in the work tree
    }
  }
  return out;
}

/** The same files at a commit. */
function gameSourcesAt(project, rev, ids) {
  const roots = scanRoots(ids);
  const files = zList(git(project, ['ls-tree', '-r', '--name-only', '-z', rev, '--', ...roots])).filter(isScannedFile);
  const blobs = catBlobs(project, files.map((f) => `${rev}:${f}`));
  return Object.fromEntries(files.map((f) => [f, blobs.get(`${rev}:${f}`)?.toString('utf8') ?? '']));
}

/** crossGameRefs over this checkout's work tree, for the registered games. */
function crossRefsNow(o, ids) {
  return crossGameRefs(gameSourcesNow(o.project, ids), ids);
}

/**
 * A cross-game reference the branch adds is a failure: fast's GUT selection leaves other games' tests
 * out on the ground that there is none. One the base already held is a note (fast then runs everything).
 */
function crossGameProblems(o, mb, files, problems, notes) {
  const ids = registeredGames(o).map((r) => r.id);
  const refs = crossGameRefs(gameSourcesNow(o.project, ids, files), ids);
  if (refs.length === 0) return;
  const key = (r) => `${r.file}\0${r.game}\0${r.text}`;
  const before = new Set(crossGameRefs(gameSourcesAt(o.project, mb, ids), ids).map(key));
  for (const r of refs) {
    if (before.has(key(r))) notes.push(`cross-game: ${formatCrossRef(r)} (already at the base; fast runs every GUT file while any is left)`);
    else problems.push(`cross-game: ${formatCrossRef(r)}: a game's own code, tests and content may not name another game's paths, classes or string keys`);
  }
}

function sizeNotes(project, added) {
  const notes = [];
  if (added.length === 0) return notes;
  const sizes = new Map();
  for (const line of git(project, ['ls-tree', '-r', '-l', '-z', 'HEAD']).split('\0')) {
    const m = /^\S+ \S+ \S+\s+(\d+)\t(.+)$/.exec(line);
    if (m) sizes.set(m[2], Number(m[1]));
  }
  let budget = 0;
  for (const f of added) {
    let size = sizes.get(f);
    if (size === undefined) {
      try {
        size = fs.statSync(path.join(project, f)).size;
      } catch {
        continue;
      }
    }
    if (size > LARGE_FILE_BYTES) notes.push(`size: ${f} is ${(size / 1048576).toFixed(1)} MB`);
    if (f.startsWith('assets/') || f.startsWith('tools/audio/')) budget += size;
  }
  if (budget > AUDIO_BUDGET_BYTES) notes.push(`size: ${(budget / 1048576).toFixed(1)} MB added under assets/ and tools/audio (the export budget is 40 MB)`);
  return notes;
}

function pinPaths(pins) {
  const named = [...(pins.blocks ?? []), ...(pins.consts ?? []), ...(pins.lines ?? [])];
  return [...new Set([...Object.keys(pins.files ?? {}), ...named.map((b) => b.file), ...named.map((b) => b.moved).filter(Boolean)])];
}

function pinProblems(o, manifest, uncommitted, notes) {
  const project = o.project;
  const pinsText = readAt(project, 'HEAD', PINS_FILE);
  if (pinsText === null) {
    // Deleted is a failure, whatever --allow says. Not pinned yet is the one window the note is for.
    const ever = git(project, ['log', '-1', '--full-history', '--format=%H', '--', PINS_FILE]).trim();
    if (ever) return [`safety pin: ${PINS_FILE} was deleted (it was in ${ever.slice(0, 9)})`];
    if (manifestPins(manifest)) notes.push(`no ${PINS_FILE} at HEAD: not pinned yet, pin rules inactive until the lead runs tools/gate pin-safety`);
    return [];
  }
  let pins;
  try {
    pins = JSON.parse(pinsText);
  } catch (err) {
    return [`safety pin: ${PINS_FILE} does not parse: ${err.message}`];
  }
  const out = [];
  if (manifestPins(manifest)) out.push(...pinCoverage(project, pins, manifest));
  const paths = pinPaths(pins);
  const blobs = catBlobs(project, paths.map((f) => `HEAD:${f}`));
  out.push(...checkPins({ pins, allowPins: o.allowPin, read: (f) => blobs.get(`HEAD:${f}`)?.toString('utf8') ?? null }));
  const dirty = new Set(uncommitted.map((c) => c.path));
  const dirtyFile = (e) => dirty.has(e.file) || (e.moved && dirty.has(e.moved));
  const dirtyPins = {
    files: Object.fromEntries(Object.entries(pins.files ?? {}).filter(([f]) => dirty.has(f))),
    masked: pins.masked,
    lines: (pins.lines ?? []).filter(dirtyFile),
    blocks: (pins.blocks ?? []).filter(dirtyFile),
    consts: (pins.consts ?? []).filter(dirtyFile),
  };
  const readWork = (f) => {
    try {
      return fs.readFileSync(path.join(project, f), 'utf8');
    } catch {
      return null;
    }
  };
  return [...new Set([...out, ...checkPinContent({ pins: dirtyPins, allowPins: o.allowPin, read: readWork })])];
}

/** The pins against the manifest, at the commit they name: stops a hollowed or hand-edited file. */
function pinCoverage(project, pins, manifest) {
  const at = pins.pinned_at;
  if (typeof at !== 'string' || gitRaw(project, ['merge-base', '--is-ancestor', at, 'HEAD']).status !== 0) {
    return [`safety pin: ${PINS_FILE} names ${at ?? 'no'} pinned_at, which is not in this history (only tools/gate pin-safety writes it)`];
  }
  const tracked = zList(git(project, ['ls-tree', '-r', '--name-only', '-z', at]));
  const spec = pinSpecOf(manifest);
  const wanted = tracked.filter((f) => spec.globs.some((g) => globMatch(g, f)));
  const named = [...Object.keys(spec.lines), ...Object.keys(spec.appendOnly), ...Object.keys(spec.tables), ...Object.values(spec.moves)];
  const blobs = catBlobs(project, [...new Set([...wanted, ...named])].map((f) => `${at}:${f}`));
  return checkPinCoverage({ pins, manifest, tracked, read: (f) => blobs.get(`${at}:${f}`)?.toString('utf8') ?? null });
}

/** A diff as plain added and removed lines, per file: what stays the same when other commits moved the lines. */
function plainDiff(project, from, to) {
  const text = git(project, ['diff', '-U0', '--no-color', '--no-ext-diff', '--no-textconv', '--no-renames', '--src-prefix=a/', '--dst-prefix=b/', from, to]);
  return text.split('\n').filter((l) => !l.startsWith('@@') && !l.startsWith('index ')).join('\n');
}

/**
 * Is this commit `git revert -m 1` of a merge in HEAD's history? The subject proves nothing. Its message
 * must name the merge and its diff must be the reverse of what that merge brought to its first parent.
 */
function isMergeRevert(project, commit) {
  if (!commit.subject.startsWith('Revert "Merge ')) return false;
  const named = revertedSha(commit.message);
  const merge = named ? revOf({ project }, named) : null;
  if (!merge || gitRaw(project, ['merge-base', '--is-ancestor', merge, 'HEAD']).status !== 0) return false;
  if (gitLine(project, ['rev-list', '--parents', '-n', '1', merge]).split(' ').length < 3) return false;
  return plainDiff(project, `${commit.sha}^`, commit.sha) === plainDiff(project, merge, `${merge}^1`);
}

/** Every rule of SPEC_GATES 6. Returns {problems, notes, ws, base, branch}. */
export function runCheck(o, { base = o.base } = {}) {
  const project = o.project;
  const manifest = loadManifest(project);
  const mb = gitLine(project, ['merge-base', base, 'HEAD']);
  const branch = gitLine(project, ['rev-parse', '--abbrev-ref', 'HEAD']);
  if (o.ws && !manifest.workstreams?.[o.ws]) throw usageError(`unknown workstream "${o.ws}"`);
  const ws = o.ws ?? inferWs(branch, manifest);
  const lead = !ws && (manifest.lead_branches ?? []).some((re) => new RegExp(re).test(branch));
  const problems = [];
  const notes = [];
  if (!ws && !o.contributor) notes.push(lead ? `lead branch ${branch}: only never_edit of the ownership rules applies` : `ws-less branch ${branch}: only ownership rules 1 and 2 apply`);

  const committed = parseNameStatus(git(project, ['diff', '--name-status', '-z', '-M', `${mb}..HEAD`]));
  const uncommitted = uncommittedChanges(project);
  const commits = commitsInRange(project, mb);

  problems.push(...checkPaths({ changes: [...committed, ...uncommitted], commits, manifest, ws, allow: o.allow, lead }));

  // 6.2, 6.3: pins as of HEAD, against HEAD, and against the work tree for what is uncommitted.
  problems.push(...pinProblems(o, manifest, uncommitted, notes));

  // 6.4: test counts at the merge base and at HEAD.
  const trailers = commits.flatMap((c) => parseTestRemovals(c.message));
  const revertOnly = commits.length > 0 && commits.every((c) => isMergeRevert(project, c));
  const counts = checkTestCounts({ baseFiles: gdSourcesAt(project, mb), headFiles: gdSourcesAt(project, 'HEAD'), trailers, revertOnly });
  problems.push(...counts.problems);
  notes.push(...counts.notes);
  const nodeCounts = checkNodeTestCounts({ baseFiles: nodeSourcesAt(project, mb), headFiles: nodeSourcesAt(project, 'HEAD'), suiteOf: nodeSuiteOf, trailers, revertOnly });
  problems.push(...nodeCounts.problems);
  notes.push(...nodeCounts.notes);

  // 6.4, 6.5: added text.
  const added = mergeAdded(diffAdded(project, [`${mb}..HEAD`]), diffAdded(project, ['HEAD']));
  const untracked = new Map();
  for (const c of uncommitted) {
    if (!c.untracked) continue;
    const lines = untrackedLines(project, c.path);
    if (lines) untracked.set(c.path, lines);
  }
  problems.push(...checkAddedText({ added, untracked, quietTests: manifest.quiet_tests }));

  const lint = grepLines(project, 'gdlint:[[:space:]]*disable', LINT_DIRS.map((d) => `${d}*.gd`));
  for (const l of lint) problems.push(`lint: ${l.split(':').slice(0, 2).join(':')}: gdlint: disable (fix the finding in code)`);

  // Against the highest floor in HEAD's history, not only the base: strict's range and a fall in two steps.
  const topFloor = highestFloor(project);
  const headFloor = floorAt(project, 'HEAD');
  if (topFloor !== null && (headFloor === null || headFloor < topFloor)) problems.push(`floor: ${GREEN_FLOOR_FILE} fell ${topFloor} -> ${headFloor}`);

  const now = currentFiles(project);
  crossGameProblems(o, mb, now, problems, notes);
  // GUT loads res://.gutconfig.json unless told not to. Every gate passes -gconfig=, and none may exist: it could
  // narrow a run or stop errors failing a test. fs too, for an ignored one. Not excused by --allow.
  const gutConfigs = [...now].filter((f) => f.split('/').at(-1) === GUT_CONFIG);
  if (fs.existsSync(path.join(project, GUT_CONFIG)) && !gutConfigs.includes(GUT_CONFIG)) gutConfigs.push(GUT_CONFIG);
  for (const f of gutConfigs) problems.push(`gut config: ${f} exists; GUT's options come from the gates' command lines only`);
  const allChanges = [...committed, ...uncommitted];
  const addedPaths = [...new Set(allChanges.filter((c) => c.status === 'A' || c.status === 'R' || c.status === 'C').map((c) => c.path))];
  const deletedPaths = [...new Set(allChanges.flatMap((c) => (c.status === 'D' ? [c.path] : c.status === 'R' ? [c.oldPath] : [])))];
  problems.push(...checkSidecars({ added: addedPaths, deleted: deletedPaths, current: now }));
  problems.push(...checkClassNames(grepLines(project, '^class_name[[:space:]]+[A-Za-z_]', ['*.gd'])));

  const stash = git(project, ['stash', 'list']).trim();
  if (stash) problems.push(`stash: the shared stash list is not empty (${stash.split('\n').length}); never git stash`);

  notes.push(...sizeNotes(project, addedPaths));
  const addonLines = [...added.keys(), ...untracked.keys()].some((f) => f.startsWith('addons/wattlands/'));
  if (addonLines && !allChanges.some((c) => c.path.startsWith('tests/'))) notes.push('tests: addons/wattlands changed with no change under tests/');

  // A pull request from outside can propose these; only a maintainer lands them. Named, not failed.
  const review = o.contributor ? problems.filter(isMaintainerReview) : [];
  notes.push(...review.map((p) => `maintainer review: ${contributorWords(p)}`));
  return { problems: problems.filter((p) => !review.includes(p)), notes, ws, base: mb, branch, paths: allChanges.length };
}

function formatCheck(c, contributor = false) {
  const lines = [...c.notes.map((n) => `note: ${n}`), ...c.problems.map((p) => `FAIL ${p}`)];
  if (contributor && c.problems.length === 0 && c.notes.some((n) => n.startsWith('maintainer review:'))) {
    lines.push('Nothing to fix for these reviews: open your pull request and say why you changed them.');
  }
  lines.push(`check: ${c.problems.length ? 'FAIL' : 'PASS'} ws ${c.ws ?? 'none'}, base ${c.base.slice(0, 9)}, ${c.paths} changes, ${c.problems.length} problems`);
  return lines.join('\n');
}

function stampBase(o, mode) {
  const sha = gitLine(o.project, ['rev-parse', 'HEAD']);
  const dirty = statusLines(o.project).length > 0;
  // The hash of the uncommitted changes is for `wait`, which never reports a check.
  const hash = dirty && mode !== 'check' ? dirtyHash(o.project) : null;
  return { mode, sha, tree: treeOf(o.project), dirty, dirty_hash: hash, started: new Date().toISOString() };
}

/** Writes a file whole or not at all: a reader (`tools/gate wait`) never sees half of it. */
function writeAtomic(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  fs.writeFileSync(tmp, text);
  for (let attempt = 0; ; attempt += 1) {
    try {
      fs.renameSync(tmp, file);
      return;
    } catch (err) {
      // Windows refuses a rename over a file another process has open for a moment.
      if (attempt >= 20 || (err.code !== 'EPERM' && err.code !== 'EBUSY' && err.code !== 'EACCES')) {
        fs.rmSync(tmp, { force: true });
        throw err;
      }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
    }
  }
}

/** A stamp, with the run token of the gate that holds the mutex (what `wait` matches it by). */
function writeStamp(o, name, stamp) {
  const file = path.join(o.project, 'build', 'gate', `${name}.json`);
  writeAtomic(file, `${JSON.stringify(o.runToken ? { ...stamp, run: o.runToken } : stamp, null, 2)}\n`);
}

/**
 * A hash of what is uncommitted: the diff against HEAD and every untracked file, so a stamp of a dirty
 * tree is matched only by the same changes. null on a clean tree.
 */
function dirtyHash(project) {
  if (statusLines(project).length === 0) return null;
  const h = crypto.createHash('sha256');
  h.update(gitRaw(project, ['diff', 'HEAD', '--binary', '--no-ext-diff', '--no-textconv', '--no-color']).stdout);
  for (const f of zList(git(project, ['ls-files', '-o', '--exclude-standard', '-z'])).sort()) {
    h.update(`\0${f}\0`);
    try {
      h.update(crypto.createHash('sha256').update(fs.readFileSync(path.join(project, f))).digest('hex'));
    } catch {
      h.update('unreadable');
    }
  }
  return h.digest('hex');
}

/** This checkout now, as `wait` compares it with a stamp. */
function checkoutState(project) {
  const dirty = statusLines(project).length > 0;
  return { tree: treeOf(project), dirty, dirtyHash: dirty ? dirtyHash(project) : null };
}

function cmdCheck(o) {
  const start = stampBase(o, 'check');
  const c = runCheck(o);
  out(formatCheck(c, o.contributor));
  const pass = c.problems.length === 0;
  ensureBuildDir(o.project);
  writeStamp(o, 'check', { ...start, ws: c.ws, pass, contributor: Boolean(o.contributor), problems: c.problems, allow: [...o.allow, ...o.allowPin], ended: new Date().toISOString() });
  return pass ? 0 : 1;
}

// ---------------------------------------------------------------- the mutex and the lanes

const CURRENT_FILE = 'current.json';
const PROGRESS_FILE = 'progress.txt';
const WAIT_DEFAULT_S = 540;
const WAIT_GRACE_MS = 5000;
const WAIT_TIMEOUT_EXIT = 124;

/** The stamp a mutex-holding command writes under build/gate/, or null. */
function stampNameOf(o) {
  if (o.cmd === 'matrix') return `matrix_${o.game}`;
  return ['fast', 'strict', 'fmt'].includes(o.cmd) ? o.cmd : null;
}

const RUN_LOCK = 'run.lock';
const BEAT_MS = 5000;
// The heartbeat runs in a worker thread, so it keeps beating while the gate's own thread is in a sync call.
const BEAT_SRC = `
const { workerData, parentPort } = require('node:worker_threads');
const fs = require('node:fs');
const beat = () => { const now = new Date(); try { fs.utimesSync(workerData.file, now, now); } catch {} };
const timer = setInterval(beat, workerData.ms);
parentPort.on('message', () => { clearInterval(timer); parentPort.close(); });
`;

/** The mutex file: {record, mtimeMs}, or null when there is none. A pre-record lock held a bare pid. */
function readRunLock(file) {
  let text;
  let mtimeMs;
  try {
    text = fs.readFileSync(file, 'utf8');
    mtimeMs = fs.statSync(file).mtimeMs;
  } catch {
    return null;
  }
  let record = null;
  try {
    record = JSON.parse(text);
  } catch {
    // half a record, or none: the caller judges it by age
  }
  if (record === null || typeof record !== 'object') {
    const pid = Number(text.trim());
    record = Number.isInteger(pid) && pid > 0 ? { pid, cmd: '?', stamp: null, started: null, token: null } : null;
  }
  return { record, mtimeMs };
}

/** Is the mutex in `gateDir` held by a live gate? Its record, or null. */
function liveGate(gateDir) {
  const held = readRunLock(path.join(gateDir, RUN_LOCK));
  if (!held?.record) return null;
  return gateAlive(held.record, { mtimeMs: held.mtimeMs, now: Date.now(), pidAlive }) ? held.record : null;
}

/** Creates `file` holding `text` only if it does not exist, whole: a reader never sees it half written. */
function createExclusive(file, text) {
  const tmp = `${file}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  fs.writeFileSync(tmp, text);
  try {
    fs.linkSync(tmp, file);
    return true;
  } catch (err) {
    if (err.code === 'EEXIST') return false;
    // No hard links on this file system: exclusive create, written at once.
    try {
      fs.writeFileSync(file, text, { flag: 'wx' });
      return true;
    } catch (err2) {
      if (err2.code === 'EEXIST') return false;
      throw err2;
    }
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}

/**
 * Takes build/gate/run.lock, the one-gate-per-checkout mutex. The lock holds the run's record (pid, cmd,
 * stamp, started, a random token), created whole, and a worker beats its mtime: a holder whose pid is gone,
 * or whose heartbeat stopped for GATE_STALE_MS (a hard kill, the pid reused), is reaped. current.json gets
 * the same record, atomically, after the lock is ours: it names the last gate that started, which is what
 * `tools/gate wait` reports on. A refused start writes neither.
 */
function takeMutex(o) {
  const dir = path.join(o.project, 'build', 'gate');
  const file = path.join(dir, RUN_LOCK);
  fs.mkdirSync(dir, { recursive: true });
  const token = `${process.pid}-${Date.now().toString(36)}-${crypto.randomBytes(6).toString('hex')}`;
  const record = { pid: process.pid, cmd: o.cmd, stamp: stampNameOf(o), started: new Date().toISOString(), token };
  const text = `${JSON.stringify(record)}\n`;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    if (createExclusive(file, text)) {
      o.runToken = token;
      writeAtomic(path.join(dir, CURRENT_FILE), text);
      let worker = null;
      try {
        worker = new Worker(BEAT_SRC, { eval: true, workerData: { file, ms: BEAT_MS } });
        worker.unref();
        worker.on('error', () => {});
      } catch {
        const timer = setInterval(() => {
          const now = new Date();
          try {
            fs.utimesSync(file, now, now);
          } catch {
            // gone
          }
        }, BEAT_MS);
        timer.unref();
      }
      process.on('exit', () => {
        try {
          worker?.postMessage('stop');
        } catch {
          // already gone
        }
        if (readRunLock(file)?.record?.token === token) fs.rmSync(file, { force: true });
      });
      return;
    }
    const held = readRunLock(file);
    if (!held) continue; // released between the two calls
    const young = Date.now() - held.mtimeMs < 10_000;
    const alive = held.record ? gateAlive(held.record, { mtimeMs: held.mtimeMs, now: Date.now(), pidAlive }) : young;
    if (alive) throw new Exit(3, `gate: another gate runs in this checkout (${held.record?.cmd ?? '?'}, pid ${held.record?.pid ?? '?'}, ${path.relative(o.project, file)})`);
    // Aside first, then gone: a reaper that lost the race moves a fresh lock, sees its token and puts it back.
    const aside = `${file}.stale-${process.pid}-${crypto.randomBytes(4).toString('hex')}`;
    try {
      fs.renameSync(file, aside);
    } catch {
      continue;
    }
    const moved = readRunLock(aside);
    if (moved?.record?.token && moved.record.token !== held.record?.token) {
      try {
        fs.linkSync(aside, file);
      } catch {
        // someone else holds it now
      }
    }
    fs.rmSync(aside, { force: true });
  }
  throw new Exit(3, 'gate: could not take build/gate/run.lock');
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** The Godot slot cap now, with the slots held right now counted back in (as acquire counts them). */
function currentCap() {
  const dir = lockDir();
  let held = 0;
  try {
    for (const t of readTickets(dir).tickets) if (t.held && (t.pid === null || pidAlive(t.pid))) held += t.lease ?? 1;
  } catch {
    // no lock dir yet
  }
  return machineCap(dir, { heldSlots: held });
}

/** The pools of this run: GUT shards and matrix workers per slot, the rest per CPU (poolSizes). */
function pools() {
  return poolSizes({ cpus: typeof os.availableParallelism === 'function' ? os.availableParallelism() : os.cpus().length, cap: currentCap() });
}

/** One gate run: its lane rows, its live children (for SIGINT), its log dir. */
class Run {
  constructor(o, mode) {
    this.o = o;
    this.mode = mode;
    this.dirRel = `build/gate/${mode}`;
    this.dir = path.join(o.project, 'build', 'gate', mode);
    this.rows = [];
    this.tails = [];
    this.lockTimeout = false;
    this.live = new Set();
    this.started = Date.now();
    this.pools = pools();
    fs.rmSync(path.join(o.project, 'build', 'gate', `${mode}.json`), { force: true });
    fs.rmSync(this.dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
    fs.mkdirSync(this.dir, { recursive: true });
    // The run's token heads its progress, so `wait` never shows rows of an earlier run of this dir.
    fs.writeFileSync(path.join(this.dir, PROGRESS_FILE), `# run ${o.runToken ?? '-'}\n`);
    const stop = () => {
      for (const child of this.live) killTree(child.pid);
      process.exit(130);
    };
    process.on('SIGINT', stop);
    process.on('SIGTERM', stop);
  }

  row(name, status, ms, log, tail = '') {
    const row = { name, status, ms, log };
    const at = this.rows.findIndex((r) => r.name === name);
    if (at >= 0) this.rows[at] = row;
    else this.rows.push(row);
    const line = `${status} ${name} ${Math.round(ms / 1000)}s ${log}`;
    out(line);
    try {
      fs.appendFileSync(path.join(this.dir, PROGRESS_FILE), `${line}\n`); // what `tools/gate wait` shows while it runs
    } catch {
      // the log dir went away: the row is on stdout anyway
    }
    if (status !== 'PASS' && tail) this.tails.push({ name, tail });
    return row;
  }

  /** Starts one process; output goes to its log only. judge(r) returns 'PASS' or 'FAIL'. */
  async lane(name, exe, args, { env = childEnv(), judge, logName = name.replaceAll(':', '_') } = {}) {
    const rel = `${this.dirRel}/${logName}.log`;
    const t0 = Date.now();
    const r = await run(exe, args, {
      cwd: this.o.project,
      log: path.join(this.o.project, rel),
      timeoutS: LANE_CEILING_S,
      env,
      quiet: true,
      onSpawn: (child) => this.live.add(child),
    });
    const status = judge(r);
    if (status !== 'PASS' && r.text.includes(LOCK_TIMEOUT_MESSAGE)) this.lockTimeout = true;
    const tail = r.text.split(/\r?\n/).slice(-40).join('\n');
    this.row(name, status, Date.now() - t0, rel, tail);
    return { status, code: r.code, text: r.text };
  }

  /** A `node tools/lib/run_tests.mjs --only=<steps>` lane under laneVerdict. */
  runTests(name, steps, { extra = [], env } = {}) {
    const args = [path.join(LIB, 'run_tests.mjs'), `--only=${steps.join(',')}`, `--shell=${this.o.shell}`, `--project=${this.o.project}`, ...extra];
    return this.lane(name, process.execPath, args, { env, judge: (r) => laneVerdict({ code: r.code, text: r.text, steps }) });
  }

  /**
   * The node lane: its own lock dir, since its short test timers can't wait in the machine FIFO, with its
   * own small cap (poolSizes: a fifth of the CPUs, 2 to 4): its suites run several at once, and the Godot
   * runs of some (tools/tests, pixelate) overlap.
   * `since` narrows the suites to what changed since that rev and lets them keep verdict caches (fast only:
   * strict and the literal run run every suite in full).
   */
  nodeLane({ since = null } = {}) {
    const env = childEnv({ WATTLANDS_GODOT_LOCK_DIR: path.join(this.dir, 'node_lock'), WATTLANDS_GODOT_LOCK_CAP: String(this.pools.nodeLockCap) });
    const extra = [`--node-jobs=${this.pools.nodeJobs}`, ...(since ? [`--node-since=${since}`, '--node-cache'] : [])];
    return this.runTests('node', ['node'], { env, extra });
  }

  pass() {
    return this.rows.length > 0 && this.rows.every((r) => r.status === 'PASS');
  }

  finish(stamp) {
    const pass = this.pass();
    const lanes = this.rows.map((r) => ({ name: r.name, status: r.status, ms: r.ms, log: r.log }));
    for (const t of this.tails) out(`\n--- ${t.name} (last 40 lines)\n${t.tail}`);
    const w = Math.max(4, ...lanes.map((l) => l.name.length));
    out(`\ngate ${this.mode}`);
    for (const l of lanes) out(`  ${l.name.padEnd(w)}  ${l.status.padEnd(4)}  ${`${Math.round(l.ms / 1000)}s`.padEnd(6)}  ${l.log}`);
    out(`gate ${this.mode}: ${pass ? 'PASS' : 'FAIL'} in ${Math.round((Date.now() - this.started) / 1000)} s`);
    return { ...stamp, pass, exit_code: this.exitCode(), lanes, ended: new Date().toISOString() };
  }

  exitCode() {
    if (this.pass()) return 0;
    return this.lockTimeout ? 75 : 1;
  }
}

function endState(o, start) {
  const dirty = start.dirty || statusLines(o.project).length > 0 || treeOf(o.project) !== start.tree;
  // What `wait` matches a dirty stamp by: the same uncommitted changes, not only the same HEAD. Changes
  // that moved while it ran match nothing: the run saw neither the first set nor the last whole.
  const hash = dirty ? dirtyHash(o.project) : null;
  const moved = start.dirty && hash !== start.dirty_hash;
  return { dirty, dirty_hash: moved ? `moved during the run (${hash})` : hash };
}

/** The check as a lane: the rules are in-process, so its row and log are written here. */
function checkLane(g, o, base) {
  const t0 = Date.now();
  const rel = `${g.dirRel}/check.log`;
  let text;
  let status;
  try {
    const c = runCheck(o, { base });
    text = formatCheck(c);
    status = c.problems.length ? 'FAIL' : 'PASS';
  } catch (err) {
    if (!(err instanceof Exit)) throw err;
    text = err.message;
    status = 'FAIL';
  }
  fs.writeFileSync(path.join(o.project, rel), `${text}\n`);
  g.row('check', status, Date.now() - t0, rel, text.split('\n').slice(-40).join('\n'));
}

async function installNode(o) {
  for (const dir of NPM_DIRS) {
    const res = await ensureNpm(o, dir);
    if (res !== 'ok') out(`gate: ${dir}: ${res}`);
  }
}

function currentGreenFloor(o) {
  return greenFloor(readGreenCount(path.join(o.project, 'build', 'green_count.txt')), readGreenCount(path.join(o.project, GREEN_FLOOR_FILE)));
}

// ---------------------------------------------------------------- fast (SPEC_GATES 2.5)

/** The commit of a rev, or null when it does not exist. */
function revOf(o, rev) {
  const r = gitRaw(o.project, ['rev-parse', '--verify', '--quiet', `${rev}^{commit}`]);
  return r.status === 0 ? r.stdout.toString('utf8').trim() : null;
}

export function changedSince(o, base) {
  // --no-renames: moving a platform file into src/games/<id>/ must select "platform", which only its old path says.
  const committed = git(o.project, ['diff', '--name-only', '--no-renames', '-z', `${base}...HEAD`]);
  return [...new Set([...zList(committed), ...uncommittedChanges(o.project).map((c) => c.path)])];
}

function pickGames(o, registered) {
  const ids = registered.map((g) => g.id);
  if (o.games === null) return touchedGames(changedSince(o, o.base), ids).games;
  if (o.games.length === 1 && o.games[0] === 'all') return ids;
  for (const id of o.games) if (!ids.includes(id)) throw usageError(`--games: "${id}" is not a registered game`);
  return [...o.games].sort();
}

/**
 * The GUT selection of a `fast`: by the change against --base (gutSelection), all with --games=all, and
 * widened by an explicit --games. The queue's stamp-ok recomputes it against main for the merged tree.
 */
export function fastGutSelection(o, ids, { changed = null, crossRefs = null } = {}) {
  if (o.games !== null && o.games.length === 1 && o.games[0] === 'all') return { all: true, games: ids, reason: '--games=all' };
  const sel = gutSelection(changed ?? changedSince(o, o.base), ids, { crossRefs: crossRefs ?? crossRefsNow(o, ids) });
  if (sel.all || o.games === null) return sel;
  const games = [...new Set([...sel.games, ...o.games])].sort();
  return games.length === ids.length ? { all: true, games: ids, reason: `--games=${o.games.join(',')}` } : { ...sel, games };
}

/** One GUT process over `files`, with its own user dir and JUnit file. Returns the evaluateGut verdict. */
async function gutLane(g, name, files, subdir, { extraEnv = {}, pendingAllowlist }) {
  const o = g.o;
  const dir = path.join(g.dir, subdir);
  fs.rmSync(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  fs.mkdirSync(dir, { recursive: true });
  const junit = path.join(dir, 'junit.xml');
  const args = [
    `--timeout=${SHARD_TIMEOUT_S}`,
    '--headless',
    '--path',
    '.',
    '-s',
    'addons/gut/gut_cmdln.gd',
    '-gconfig=', // never res://.gutconfig.json: it could narrow the run or stop errors failing a test
    `-gtest=${files.map((f) => `res://${f}`).join(',')}`,
    '-gexit',
    `-gjunit_xml_file=${g.dirRel}/${subdir}/junit.xml`,
  ];
  const [exe, argv] = wrapperCommand(o, args);
  let verdict = null;
  await g.lane(name, exe, argv, {
    env: childEnv({ WATTLANDS_USERDATA_DIR: path.join(dir, 'userdata'), ...extraEnv }),
    logName: subdir === 'quiet_retry' ? 'gut_quiet_retry' : name.replaceAll(':', '_'),
    judge: (r) => {
      const junitXml = fs.existsSync(junit) ? fs.readFileSync(junit, 'utf8') : '';
      const v = evaluateGut({ exitCode: r.code, log: r.text, junitXml, previousGreen: null, minCount: 1, narrow: true, pendingAllowlist });
      verdict = { ...v, name, junitXml };
      return v.pass ? 'PASS' : 'FAIL';
    },
  });
  return verdict;
}

async function quietLane(g, files, pendingAllowlist) {
  const first = await gutLane(g, 'gut:quiet', files, 'quiet', { pendingAllowlist });
  if (first.pass) return { verdict: first, retried: false };
  // A budget is a claim about an unloaded machine: one rerun with the whole machine to itself, and the
  // second verdict stands (SPEC_GATES 2.4). Budgets only: a real failure, a SCRIPT ERROR or a crash in
  // these files keeps its first verdict, so a flaky determinism failure can't read as green.
  const read = (f) => {
    try {
      return fs.readFileSync(path.join(g.o.project, f), 'utf8');
    } catch {
      return null;
    }
  };
  const plan = quietRetryPlan({ reasons: first.reasons, junitXml: first.junitXml, read });
  if (!plan.allowed) {
    out(`gate: gut:quiet failed and does not rerun: ${plan.why}`);
    return { verdict: first, retried: false, tests: plan.tests };
  }
  out(`gate: gut:quiet failed on budget tests (${plan.tests.join(', ')}); once more inside a whole-machine lease`);
  g.tails = g.tails.filter((t) => t.name !== 'gut:quiet');
  let lease;
  try {
    lease = await acquire({ lease: WHOLE_MACHINE_LEASE, label: 'tools/gate quiet rerun' });
  } catch (err) {
    if (err.code !== 'ELOCKTIMEOUT') throw err;
    g.lockTimeout = true;
    return { verdict: first, retried: false, tests: plan.tests };
  }
  try {
    const second = await gutLane(g, 'gut:quiet', files, 'quiet_retry', { extraEnv: { [LEASE_TOKEN_ENV]: lease.token }, pendingAllowlist });
    return { verdict: second, retried: true, tests: plan.tests };
  } finally {
    lease.release();
  }
}

async function cmdFast(o) {
  takeMutex(o);
  ensureBuildDir(o.project);
  const start = stampBase(o, 'fast');
  const g = new Run(o, 'fast');
  const someLanes = o.lanes !== null;
  const want = (name) => !someLanes || o.lanes.includes(name) || o.lanes.includes(name.split(':')[0]);
  checkLane(g, o, o.base);
  // What the branch touches, read before the import: a sidecar it writes must not pick the selection.
  const registered = registeredGames(o);
  const games = pickGames(o, registered);
  const ids = registered.map((r) => r.id);
  const selection = fastGutSelection(o, ids);
  const requiredGames = revOf(o, 'main') ? touchedGames(changedSince(o, 'main'), ids).games : ids;
  await installNode(o);
  await g.runTests('import', ['import']);

  const manifest = loadManifest(o.project);
  const weights = loadJson(path.join(o.project, WEIGHTS_FILE)) ?? {};
  const { run: files, skipped, skippedGames } = selectGutFiles(listGutFiles(o.project), selection, ids);
  const shards = o.shards ?? g.pools.shards;
  // A game group whose files share a res://build dir stays in one process (buildDirGroups).
  const gdUnderGames = Object.fromEntries([...currentFiles(o.project)].filter((f) => f.startsWith('tests/games/') && f.endsWith('.gd')).map((f) => [f, readQuiet(path.join(o.project, f))]));
  const noSplit = buildDirGroups(gdUnderGames, files);
  if (noSplit.length > 0) out(`gate fast: these game groups name res://build and stay whole: ${noSplit.join(', ')}`);
  const plan = planShards(files, weights, { shards, quiet: manifest.quiet_tests, pins: manifest.shard_pins, noSplit });
  if (skipped.length > 0) out(`gate fast: GUT leaves out ${skipped.length} files of ${skippedGames.join(', ')}: ${selection.reason}`);
  const pendingAllowlist = readPendingAllowlist(path.join(o.project, 'tests', 'pending_allowlist.txt'));

  const tasks = [];
  const gutResults = [];
  const gutFiles = [];
  // Start order sets the FIFO order of the Godot lock.
  for (const id of games) {
    if (!want(`e2e:${id}`)) continue;
    tasks.push(g.runTests(`e2e:${id}`, ['e2e'], { extra: [`--games=${id}`] }));
    await sleep(E2E_STAGGER_MS); // getFreePort is pick-then-bind
  }
  for (let n = 0; n < plan.shards.length; n += 1) {
    const name = `gut:${n + 1}`;
    if (!want(name)) continue;
    gutFiles.push(...plan.shards[n]);
    tasks.push(gutLane(g, name, plan.shards[n], `shard_${n + 1}`, { pendingAllowlist }).then((v) => gutResults.push(v)));
    await sleep(50);
  }
  if (want('static')) tasks.push(g.runTests('static', ['static'], { extra: [`--static-jobs=${g.pools.staticJobs}`] }));
  // --games=all asks for everything, so the node lane is not narrowed either.
  const allGames = o.games !== null && o.games.length === 1 && o.games[0] === 'all';
  if (want('node')) tasks.push(g.nodeLane({ since: allGames ? null : o.base }));
  for (const id of games) {
    if (!want(`sim:${id}`)) continue;
    const env = childEnv({ WATTLANDS_USERDATA_DIR: path.join(g.dir, `sim_${id}`, 'userdata') });
    tasks.push(g.runTests(`sim:${id}`, ['sim'], { extra: [`--games=${id}`, `--sim-outer-timeout=${SIM_OUTER_TIMEOUT_S}`, `--sim-jobs=${g.pools.simJobs}`], env }));
  }
  await Promise.all(tasks);

  let quietRetried = false;
  let quietTests = [];
  if (plan.quiet.length > 0 && want('gut:quiet')) {
    const q = await quietLane(g, plan.quiet, pendingAllowlist);
    gutResults.push(q.verdict);
    gutFiles.push(...plan.quiet);
    quietRetried = q.retried;
    quietTests = q.retried ? q.tests : [];
  }
  if (want('fit')) await g.runTests('fit', ['fit']);

  const floor = currentGreenFloor(o);
  let gutTotal = null;
  // Without --lanes the verdict always runs: no shard at all means no test ran, never a pass.
  if (!someLanes || gutResults.length > 0) {
    const everyShard = gutFiles.length === files.length;
    // Files left out by the selection count by their source toward the floor: the rest must make up the difference.
    const skippedTests = Object.values(sourceTestCounts(o.project, skipped)).reduce((s, n) => s + n, 0);
    const gutFloor = everyShard && Number.isInteger(floor) ? floor - skippedTests : null;
    const v = aggregateGut(gutResults, { floor: gutFloor, expectedFiles: gutFiles, sourceCounts: sourceTestCounts(o.project, gutFiles) });
    gutTotal = v.total;
    const floorText = !everyShard ? 'partial' : floor === null ? 'none' : skipped.length ? `${floor} less ${skippedTests} in ${skipped.length} files left out (${skippedGames.join(', ')})` : floor;
    // Say why every file ran when the change alone did not ask for it (a cross-game reference: fail closed).
    const why = selection.all && /cross-game/.test(selection.reason) ? `; every file: ${selection.reason}` : '';
    g.row('gut:total', v.pass ? 'PASS' : 'FAIL', 0, `${v.total} tests, floor ${floorText}${why}`, v.reasons.join('\n'));
  }
  const end = endState(o, start);
  const partialReasons = fastNarrowing({
    lanes: o.lanes,
    base: o.base,
    baseSha: revOf(o, o.base),
    mainSha: revOf(o, 'main'),
    ws: o.ws,
    inferredWs: inferWs(gitLine(o.project, ['rev-parse', '--abbrev-ref', 'HEAD']), manifest),
    allow: o.allow,
    allowPin: o.allowPin,
    contributor: o.contributor,
    games,
    requiredGames,
  });
  const stamp = g.finish({
    ...start,
    ...end,
    partial: partialReasons.length > 0,
    partial_reasons: partialReasons,
    base: o.base,
    ws: o.ws,
    games,
    gut_selection: { all: selection.all, games: selection.games, skipped_games: skippedGames, skipped_files: skipped.length, reason: selection.reason },
    shards: plan.shards.length,
    gut_total: gutTotal,
    floor,
    quiet_retried: quietRetried,
    quiet_retried_tests: quietTests,
    allow: [...o.allow, ...o.allowPin],
    allow_globs: o.allow,
    allow_pins: o.allowPin,
  });
  writeStamp(o, 'fast', stamp);
  return g.exitCode();
}

// ---------------------------------------------------------------- strict (SPEC_GATES 2.6)

/**
 * strict's check range starts just before the last commit that touched the floor file, so that commit is in
 * the range: from the commit itself, a commit that lowered the floor and deleted tests would compare clean.
 */
export function strictBase(o) {
  const floorCommit = gitLine(o.project, ['log', '-1', '--full-history', '--format=%H', '--', GREEN_FLOOR_FILE]);
  if (!floorCommit) return 'HEAD';
  return revOf(o, `${floorCommit}^`) ?? floorCommit;
}

async function cmdStrict(o) {
  takeMutex(o);
  ensureBuildDir(o.project);
  const dirtyNow = statusLines(o.project);
  if (dirtyNow.length) throw new Exit(3, `gate: strict needs a clean tree:\n${dirtyNow.slice(0, 20).join('\n')}`);
  const start = stampBase(o, 'strict');
  const g = new Run(o, 'strict');
  checkLane(g, o, strictBase(o));
  await installNode(o);
  await g.runTests('import', ['import']);

  const games = registeredGames(o).map((r) => r.id);
  const others = async () => {
    const tasks = [];
    for (const id of games) {
      tasks.push(g.runTests(`e2e:${id}`, ['e2e'], { extra: [`--games=${id}`] }));
      await sleep(E2E_STAGGER_MS);
    }
    tasks.push(g.runTests('static', ['static'], { extra: [`--static-jobs=${g.pools.staticJobs}`] }));
    tasks.push(g.runTests('sim', ['sim'], { extra: [`--sim-outer-timeout=${SIM_OUTER_TIMEOUT_S}`, `--sim-jobs=${g.pools.simJobs}`] }));
    tasks.push(g.nodeLane());
    await Promise.all(tasks);
  };
  // The monolith is the point: only it catches cross-file state leaks.
  if (o.serialGut) {
    await g.runTests('gut', ['gut']);
    await others();
  } else {
    const gut = g.runTests('gut', ['gut']);
    await sleep(50);
    await Promise.all([gut, others()]);
  }
  // BRIEF 7.3: these start after the GUT process has exited.
  await g.runTests('scaffold', ['scaffold']);
  await g.runTests('fit', ['fit']);

  const after = statusLines(o.project);
  if (after.length) {
    g.row('tree', 'FAIL', 0, 'the run rewrote the tree the verdict is about', after.slice(0, 20).join('\n'));
  } else g.row('tree', 'PASS', 0, 'still clean');

  const junit = path.join(o.project, 'build', 'junit.xml');
  const junitXml = fs.existsSync(junit) ? fs.readFileSync(junit, 'utf8') : '';
  const counts = junitXml ? junitCounts(junitXml) : null;
  // The monolith must have run every file the shards would: a file GUT dropped is no failing test.
  const gutFiles = listGutFiles(o.project);
  const uncovered = [...junitCoverage(junitXml, gutFiles), ...junitCountProblems([junitXml], sourceTestCounts(o.project, gutFiles))];
  g.row('gut:files', uncovered.length ? 'FAIL' : 'PASS', 0, uncovered.length ? `${uncovered.length} files GUT did not run in full` : 'every test of every file is in the JUnit', uncovered.slice(0, 40).join('\n'));
  const stamp = g.finish({
    ...start,
    ...endState(o, start),
    partial: false,
    games,
    gut_total: counts ? counts.tests : null,
    floor: currentGreenFloor(o),
    serial_gut: o.serialGut,
    allow: [...o.allow, ...o.allowPin],
  });
  writeStamp(o, 'strict', stamp);
  return g.exitCode();
}

// ---------------------------------------------------------------- matrix (SPEC_GATES 2.8)

function reportStem(args, i) {
  const report = args.find((a) => a.startsWith('--report='));
  return report ? path.basename(report.slice('--report='.length)).replace(/\.json$/, '') : `run_${i}`;
}

async function cmdMatrix(o) {
  const id = o.game;
  const script = `tests/games/${id}/sim/run_sims.sh`;
  const rule = matrixRule(loadManifest(o.project), id);
  if (!fs.existsSync(path.join(o.project, script))) {
    if (rule) {
      out(`gate matrix: FAIL: the manifest requires a matrix of ${id}, and ${script} is missing`);
      return 1;
    }
    out(`gate matrix: no matrix for ${id} (no ${script})`);
    return 0;
  }
  takeMutex(o);
  ensureBuildDir(o.project);
  const name = `matrix_${id}`;
  const start = stampBase(o, 'matrix');
  // Read before Run deletes it: the last matrix's run times order this one's pool.
  const previousMs = loadJson(path.join(o.project, 'build', 'gate', `${name}.json`))?.run_ms ?? {};
  const g = new Run(o, name);
  const bash = findBash();
  const upper = id.toUpperCase();
  // Nothing in the shell may narrow or skip a matrix: <ID>_SKIP_CHECK, <ID>_SEEDS, <ID>_SIMS, <ID>_FIT, ...
  const planEnv = (planFile, extra = {}) => {
    const env = withBashPath(withoutGameVars(childEnv({ WATTLANDS_BASH: bash }), upper), bash);
    env.WATTLANDS_SIM_PLAN = planFile;
    return { ...env, ...extra };
  };
  const scriptRun = (logName, env) => run(bash, [script, ...o.scenarios], {
    cwd: o.project,
    log: path.join(g.dir, `${logName}.log`),
    timeoutS: LANE_CEILING_S,
    env,
    quiet: true,
    onSpawn: (child) => g.live.add(child),
  });

  await g.runTests('import', ['import']);
  fs.rmSync(path.join(o.project, 'build', id, 'sims'), { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });

  // Phase 1: the script's real logic decides the runs; tools/run_game_sim only records them.
  const planFile = path.join(g.dir, 'plan.txt').replaceAll('\\', '/');
  const t0 = Date.now();
  fs.writeFileSync(planFile, '');
  const planned = await scriptRun('plan', planEnv(planFile, { [`${upper}_SKIP_CHECK`]: '1' }));
  const lines = parsePlan(fs.readFileSync(planFile, 'utf8'));
  // tools/run_game_sim refuses a plan variable with no file, so a value left in a shell can't skip real runs.
  fs.renameSync(planFile, path.join(g.dir, 'plan_used.txt'));
  const partial = o.scenarios.length > 0;
  const tooFew = !partial && rule !== null && lines.length < rule.minRuns;
  const planOk = planned.code === 0 && lines.length > 0 && !tooFew;
  const planNote = `exit ${planned.code}, ${lines.length} runs${tooFew ? `, below the manifest's ${rule.minRuns} (matrix_min_runs): the script narrowed its matrix` : ''}`;
  g.row('plan', planOk ? 'PASS' : 'FAIL', Date.now() - t0, `${g.dirRel}/plan.log`, `${planNote}\n${planned.text.split(/\r?\n/).slice(-40).join('\n')}`);

  // Phase 2: a pool; a failed run does not stop the others.
  const failed = [];
  const tool = 'tools/run_game_sim';
  let next = 0;
  const logDir = path.join(g.dir, 'runs');
  fs.mkdirSync(logDir, { recursive: true });
  const runMs = {};
  // Longest first, by the last matrix's times, so no long run starts last and sets the wall time alone.
  const order = longestFirst(lines.map((args, i) => reportStem(args, i)), previousMs);
  const worker = async (k) => {
    const env = withBashPath(withoutGameVars(childEnv({ WATTLANDS_BASH: bash, WATTLANDS_USERDATA_DIR: path.join(g.dir, `w${k}`, 'userdata') }), upper), bash);
    while (next < lines.length) {
      const i = order[next];
      next += 1;
      const args = lines[i];
      const stem = reportStem(args, i);
      const t = Date.now();
      const report = args.find((a) => a.startsWith('--report='));
      if (report) fs.mkdirSync(path.dirname(path.resolve(o.project, report.slice('--report='.length))), { recursive: true });
      const r = await run(bash, [tool, ...args], {
        cwd: o.project,
        log: path.join(logDir, `${stem}.log`),
        timeoutS: LANE_CEILING_S,
        env,
        quiet: true,
        onSpawn: (child) => g.live.add(child),
      });
      runMs[stem] = Date.now() - t;
      if (r.code !== 0) {
        failed.push(`${stem}: exit ${r.code}`);
        if (r.code === 75) g.lockTimeout = true;
      }
    }
  };
  const t1 = Date.now();
  // One worker per slot: more would only wait in the lock, fewer would leave slots idle.
  const jobs = Math.min(o.jobs ?? g.pools.matrixJobs, Math.max(1, lines.length));
  await Promise.all(Array.from({ length: jobs }, (_, k) => worker(k)));
  // A run that exits non-zero fails the verdict even when it left a report the checker accepts.
  g.row('pool', failed.length ? 'FAIL' : 'PASS', Date.now() - t1, `${g.dirRel}/runs/ (${lines.length} runs, ${jobs} workers)`, failed.join('\n'));

  // Phase 3: the same script again, still recording only, now with its checker over the reports.
  const t2 = Date.now();
  const planCheck = path.join(g.dir, 'plan_check.txt').replaceAll('\\', '/');
  fs.writeFileSync(planCheck, '');
  const checked = await scriptRun('check', planEnv(planCheck));
  fs.rmSync(planCheck, { force: true });
  // Exit 0 is no evidence: the checker's own rows must be in its output.
  const evidence = checkerEvidence({ code: checked.code, text: checked.text, partial, required: rule?.rows ?? [] });
  g.row('check_sims', evidence.pass ? 'PASS' : 'FAIL', Date.now() - t2, `${g.dirRel}/check.log`, [...evidence.reasons, ...checked.text.split(/\r?\n/).slice(-40)].join('\n'));

  const stamp = g.finish({ ...start, ...endState(o, start), game: id, partial, runs: lines.length, failed_runs: failed, checker_rows: evidence.rows, checker_passed: evidence.passed, jobs, run_ms: runMs });
  writeStamp(o, name, stamp);
  return g.exitCode();
}

// ---------------------------------------------------------------- stamp-ok

/**
 * Why a stamp does not stand for this tree, or null. `need` (fast only): { gut, games } that this tree
 * needs against main. `allow`/`allowPin`: the exceptions the caller names; a stamp whose only narrowing
 * was exactly those stands, since they reach the check lane alone.
 */
function stampRefusal(stamp, matrix, tree, rule = null, { need = null, allow = [], allowPin = [] } = {}) {
  if (!stamp) return 'no stamp';
  if (stamp.pass !== true) return 'it did not pass';
  const excused = !matrix && (allow.length > 0 || allowPin.length > 0);
  if (excused) {
    const gap = allowGap(stamp, allow, allowPin);
    if (gap) return gap;
  } else if (stamp.partial !== false) return `it is partial${stamp.partial_reasons?.length ? ` (${stamp.partial_reasons.join('; ')})` : ''}`;
  if (stamp.dirty !== false) return 'it was dirty';
  if (stamp.tree !== tree) return `tree ${stamp.tree} is not ${tree}`;
  if (matrix) {
    if (!(stamp.runs > 0)) return 'it ran no sims';
    if (!(stamp.checker_rows > 0)) return 'it holds no evidence that the checker ran';
    if (rule && stamp.runs < rule.minRuns) return `it ran ${stamp.runs} sims, below the manifest's ${rule.minRuns}`;
    const lost = (rule?.rows ?? []).filter((id) => !(stamp.checker_passed ?? []).includes(id));
    if (lost.length > 0) return `its checker did not pass ${lost.join(', ')}`;
    return null;
  }
  if (!Number.isInteger(stamp.gut_total) || stamp.gut_total <= 0) return `it counted ${stamp.gut_total ?? 'no'} GUT tests`;
  if (!excused && (stamp.allow ?? []).length > 0) return `it ran with ${stamp.allow.join(', ')}`;
  if (need) {
    const gap = selectionGap(stamp.gut_selection, need.gut);
    if (gap) return gap;
    const lost = need.games.filter((id) => !(stamp.games ?? []).includes(id));
    if (lost.length > 0) return `it ran no sim or e2e of ${lost.join(', ')}, which this tree touches`;
  }
  return null;
}

/** What a `fast` of this checkout's tree must cover, against main: the GUT selection and the games for sim and e2e. */
function fastNeed(o) {
  const ids = registeredGames(o).map((r) => r.id);
  if (!revOf(o, 'main')) return { gut: { all: true, games: ids, reason: 'no main' }, games: ids };
  const changed = changedSince(o, 'main');
  return { gut: gutSelection(changed, ids, { crossRefs: crossRefsNow(o, ids) }), games: touchedGames(changed, ids).games };
}

function cmdStampOk(o) {
  const worktree = path.resolve(o.positional[0]);
  const name = o.matrix ? `matrix_${o.matrix}` : 'fast';
  const stamp = loadJson(path.join(worktree, 'build', 'gate', `${name}.json`));
  const dirtyHere = statusLines(o.project);
  if (dirtyHere.length > 0) {
    out(`gate stamp-ok: ${name} in ${worktree}: refused: this checkout is dirty (${dirtyHere.length} paths), so its tree is not HEAD's`);
    return 1;
  }
  const matrix = o.matrix !== null;
  const why = stampRefusal(stamp, matrix, treeOf(o.project), matrix ? matrixRule(loadManifest(o.project), o.matrix) : null, {
    need: matrix ? null : fastNeed(o),
    allow: o.allow,
    allowPin: o.allowPin,
  });
  if (why) {
    out(`gate stamp-ok: ${name} in ${worktree}: refused: ${why}`);
    return 1;
  }
  if (!matrix && stamp.allow?.length) out(`note: it ran with ${stamp.allow.join(', ')}, as stamp-ok was told`);
  if (!matrix && stamp.gut_selection && !stamp.gut_selection.all) out(`note: its GUT run left out ${(stamp.gut_selection.skipped_games ?? []).join(', ')} (${stamp.gut_selection.reason}), which this tree does not need`);
  if (stamp.quiet_retried) out(`note: gut:quiet passed only on its rerun under a whole-machine lease: ${(stamp.quiet_retried_tests ?? []).join(', ') || 'budget tests'}`);
  out(`gate stamp-ok: ${name} in ${worktree} stands for this tree`);
  return 0;
}

// ---------------------------------------------------------------- floor

function cmdFloor(o) {
  takeMutex(o);
  const dirty = statusLines(o.project);
  if (dirty.length) throw new Exit(3, `gate floor: the tree is dirty:\n${dirty.slice(0, 20).join('\n')}`);
  if (manifestPins(loadManifest(o.project)) && readAt(o.project, 'HEAD', PINS_FILE) === null) {
    out(`gate floor: refused: no ${PINS_FILE} at HEAD, so the strict gate checked no pin: run tools/gate pin-safety first`);
    return 1;
  }
  const stamp = loadJson(path.join(o.project, 'build', 'gate', 'strict.json'));
  const head = gitLine(o.project, ['rev-parse', 'HEAD']);
  const floorFile = path.join(o.project, GREEN_FLOOR_FILE);
  const current = readGreenCount(floorFile) ?? 0;
  const n = stamp?.gut_total;
  const why = !stamp
    ? 'no strict stamp'
    : stamp.mode !== 'strict'
      ? `the stamp's mode is ${stamp.mode}`
      : !stamp.pass
        ? 'the strict gate did not pass'
        : stamp.partial
          ? 'the stamp is partial'
          : stamp.dirty
            ? 'the stamp is dirty'
            : stamp.sha !== head
              ? `the stamp is for ${stamp.sha}, HEAD is ${head}`
              : !Number.isInteger(n) || n < current
                ? `${n} tests is below the floor ${current}`
                : null;
  if (why) {
    out(`gate floor: refused: ${why}`);
    return 1;
  }
  const junit = path.join(o.project, 'build', 'junit.xml');
  if (!fs.existsSync(junit)) {
    out('gate floor: refused: no build/junit.xml');
    return 1;
  }
  fs.writeFileSync(path.join(o.project, WEIGHTS_FILE), `${JSON.stringify(weightsByGroup(readWeights(fs.readFileSync(junit, 'utf8'))), null, 2)}\n`);
  if (n > current) fs.writeFileSync(floorFile, `${n}\n`);
  git(o.project, ['add', '--', GREEN_FLOOR_FILE, WEIGHTS_FILE]);
  if (git(o.project, ['diff', '--cached', '--name-only']).trim() === '') {
    out(`gate floor: nothing to commit (floor ${current})`);
    return 0;
  }
  const subject = n > current ? `chore: the GUT floor rises to ${n} (${o.label})` : `chore: the gate's shard weights refresh (${o.label})`;
  git(o.project, ['commit', '-m', subject, '-m', COAUTHOR, '--', GREEN_FLOOR_FILE, WEIGHTS_FILE]);
  out(`gate floor: ${subject}`);
  return 0;
}

// ---------------------------------------------------------------- fmt

function uvModule(o, module, files) {
  return spawnSync('uv', ['run', '--no-project', '--with', `gdtoolkit==${GDTOOLKIT_VERSION}`, 'python', '-m', module, ...files], {
    cwd: o.project,
    encoding: 'utf8',
    maxBuffer: 2 ** 28,
    windowsHide: true,
    env: childEnv(),
  });
}

/** uvModule without blocking the event loop, so gdlint runs beside check_scripts. */
function uvModuleAsync(o, module, files) {
  return new Promise((resolve) => {
    const child = spawn('uv', ['run', '--no-project', '--with', `gdtoolkit==${GDTOOLKIT_VERSION}`, 'python', '-m', module, ...files], { cwd: o.project, windowsHide: true, env: childEnv() });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('error', (error) => resolve({ status: null, error, stdout, stderr }));
    child.on('close', (status) => resolve({ status, stdout, stderr }));
  });
}

/** Is a file under a folder with a .gdignore? Godot imports none of those, and check_scripts skips them. */
function gdignored(project, file) {
  const parts = file.split('/').slice(0, -1);
  for (let i = 1; i <= parts.length; i += 1) {
    if (fs.existsSync(path.join(project, ...parts.slice(0, i), '.gdignore'))) return true;
  }
  return false;
}

async function cmdFmt(o) {
  const t0 = Date.now();
  takeMutex(o);
  ensureBuildDir(o.project);
  fs.rmSync(path.join(o.project, 'build', 'gate', 'fmt.json'), { force: true });
  const r = await fmtSteps(o);
  if (r === null) return 0;
  out(`gate fmt: ${r.note}, ${r.failed ? 'FAIL' : 'clean'} in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  writeStamp(o, 'fmt', { mode: 'fmt', pass: !r.failed, exit_code: r.failed ? 1 : 0, files: r.files, ended: new Date().toISOString() });
  return r.failed ? 1 : 0;
}

/** gdformat, then gdlint beside check_scripts on the formatted files. Returns null with nothing to do, else {failed, files, note}. */
async function fmtSteps(o) {
  const changed = zList(git(o.project, ['diff', '--name-only', '--diff-filter=d', '-z', o.base]));
  const untracked = zList(git(o.project, ['ls-files', '-o', '--exclude-standard', '-z']));
  const files = [...new Set([...changed, ...untracked])].filter((f) => f.endsWith('.gd') && LINT_DIRS.some((d) => f.startsWith(d))).sort();
  if (files.length === 0) {
    out('gate fmt: no changed .gd files');
    return null;
  }
  let failed = false;
  const report = (module, r) => {
    if (r.status === 0) return;
    failed = true;
    out(`gate fmt: ${module} exit ${r.status ?? r.error?.code}\n${`${r.stdout ?? ''}${r.stderr ?? ''}`.split(/\r?\n/).slice(-40).join('\n')}`);
  };
  for (let i = 0; i < files.length; i += FMT_BATCH) report('gdtoolkit.formatter', uvModule(o, 'gdtoolkit.formatter', files.slice(i, i + FMT_BATCH)));
  for (const f of files) {
    const abs = path.join(o.project, f);
    const text = fs.readFileSync(abs);
    if (text.includes(13)) fs.writeFileSync(abs, text.toString('utf8').replaceAll('\r\n', '\n').replaceAll('\r', ''));
  }
  // The formatted files only, which is where gdformat can break a script; the static lane of fast loads them
  // all. Its own lock dir, like the node lane: one short Godot run must not queue behind every gate.
  const loadable = files.filter((f) => !gdignored(o.project, f));
  const named = loadable.length <= FMT_NAMED_MAX;
  const check = async () => {
    if (loadable.length === 0) return;
    const userArgs = named ? ['--', `--files=${loadable.map((f) => `res://${f}`).join(',')}`] : [];
    const [exe, argv] = wrapperCommand(o, ['--headless', '--path', '.', '-s', 'tools/check_scripts.gd', ...userArgs]);
    const env = childEnv({ WATTLANDS_GODOT_LOCK_DIR: path.join(o.project, 'build', 'gate', 'fmt_lock'), WATTLANDS_GODOT_LOCK_CAP: '1' });
    const r = await run(exe, argv, { cwd: o.project, log: path.join(o.project, 'build', 'check_scripts.log'), env, quiet: true, timeoutS: 1800 });
    const summary = (named ? /check_scripts: (\d+) named scripts, (\d+) failures/ : /check_scripts: (\d+) scripts, (\d+) failures/).exec(r.text);
    if (r.code !== 0 || !summary || summary[2] !== '0') {
      failed = true;
      out(`gate fmt: check_scripts failed (exit ${r.code}, build/check_scripts.log)\n${r.text.split(/\r?\n/).filter((l) => /FAIL/.test(l)).slice(-40).join('\n')}`);
    }
  };
  const lint = async () => {
    for (let i = 0; i < files.length; i += FMT_BATCH) report('gdtoolkit.linter', await uvModuleAsync(o, 'gdtoolkit.linter', files.slice(i, i + FMT_BATCH)));
  };
  await Promise.all([check(), lint()]);
  const loaded = loadable.length === 0 ? 'none loaded (all under a .gdignore)' : named ? `${loadable.length} loaded` : 'every script loaded';
  return { failed, files: files.length, note: `${files.length} files, ${loaded}` };
}

// ---------------------------------------------------------------- wait

/** Prints a stamp's lanes, its partial reasons and the tail of each lane that did not pass; returns its exit code. */
function printStamp(o, name, stamp) {
  const lanes = Array.isArray(stamp.lanes) ? stamp.lanes : [];
  for (const l of lanes) {
    if (l.status === 'PASS' || !l.log) continue;
    const log = path.join(o.project, l.log.split(' ')[0]);
    if (!fs.existsSync(log) || !fs.statSync(log).isFile()) continue;
    out(`\n--- ${l.name} (last 30 lines of ${l.log.split(' ')[0]})\n${fs.readFileSync(log, 'utf8').split(/\r?\n/).slice(-30).join('\n')}`);
  }
  const w = Math.max(4, ...lanes.map((l) => l.name.length));
  out(`\ngate ${name} (stamp build/gate/${name}.json, started ${stamp.started ?? '?'}, ended ${stamp.ended ?? '?'})`);
  out(`sha ${stamp.sha ?? '?'}, tree ${stamp.tree ?? '?'}${stamp.dirty ? ', dirty' : ''}`);
  for (const l of lanes) out(`  ${l.name.padEnd(w)}  ${String(l.status).padEnd(4)}  ${`${Math.round((l.ms ?? 0) / 1000)}s`.padEnd(6)}  ${l.log}`);
  if (stamp.partial) out(`partial: ${(stamp.partial_reasons ?? []).join('; ') || 'yes'}`);
  if (stamp.gut_selection && !stamp.gut_selection.all) out(`GUT left out: ${(stamp.gut_selection.skipped_games ?? []).join(', ')} (${stamp.gut_selection.reason})`);
  if (Number.isInteger(stamp.gut_total)) out(`gut_total: ${stamp.gut_total}`);
  const code = Number.isInteger(stamp.exit_code) ? stamp.exit_code : stamp.pass === true ? 0 : 1;
  out(`gate ${name}: ${stamp.pass === true ? 'PASS' : 'FAIL'} (exit ${code})`);
  return code;
}

/**
 * Blocks until the gate running in this checkout ends, or --timeout seconds pass (exit 124: it still runs,
 * wait again), printing its lane rows as they finish; then prints its stamp and exits with its verdict.
 * With no gate running (after a short grace for one just started in the background) it reports on the
 * last gate that started here (current.json). Only that run's own stamp, for this tree and these changes,
 * is a verdict; anything else exits WAIT_NO_VERDICT_EXIT and says why (waitVerdict). `--for` names the
 * gate the caller started, so a refused start never reads as another gate's verdict.
 */
async function cmdWait(o) {
  const timeoutS = o.timeout ?? WAIT_DEFAULT_S;
  const deadline = Date.now() + timeoutS * 1000;
  const dir = path.join(o.project, 'build', 'gate');
  const noVerdict = (why) => {
    out(`gate wait: no verdict: ${why}`);
    return WAIT_NO_VERDICT_EXIT;
  };
  let cur = liveGate(dir);
  for (const graceEnd = Date.now() + WAIT_GRACE_MS; !cur && Date.now() < graceEnd; ) {
    await sleep(250);
    cur = liveGate(dir);
  }
  if (cur) {
    if (o.for && cur.stamp !== o.for) return noVerdict(`${cur.stamp ?? cur.cmd} runs in this checkout (pid ${cur.pid}), not ${o.for}: a ${o.for} started beside it was refused (exit 3)`);
    out(`gate wait: ${cur.cmd} (pid ${cur.pid}) runs since ${cur.started ?? '?'}; waiting up to ${timeoutS} s`);
    const progress = cur.stamp ? path.join(dir, cur.stamp, PROGRESS_FILE) : null;
    const header = `# run ${cur.token ?? '-'}`;
    let shown = 0;
    const show = () => {
      let lines;
      try {
        lines = fs.readFileSync(progress, 'utf8').split('\n').filter(Boolean);
      } catch {
        return;
      }
      // Rows of an earlier run in this dir, before this one wiped it, are not this run's.
      if (lines[0] !== header) {
        shown = 0;
        return;
      }
      for (const l of lines.slice(1 + shown)) out(`  ${l}`);
      shown = lines.length - 1;
    };
    // Until its lock goes or changes hands, its pid dies or its heartbeat stops (a hard kill, a reused pid).
    while (liveGate(dir)?.token === cur.token) {
      if (progress) show();
      if (Date.now() >= deadline) {
        out(`gate wait: ${cur.cmd} still runs after ${timeoutS} s (pid ${cur.pid}); run tools/gate wait again`);
        return WAIT_TIMEOUT_EXIT;
      }
      await sleep(1000);
    }
    if (progress) show();
  }
  const record = cur ?? loadJson(path.join(dir, CURRENT_FILE));
  const stamp = record?.stamp && WAIT_FOR_RE.test(record.stamp) ? loadJson(path.join(dir, `${record.stamp}.json`)) : null;
  const v = waitVerdict({ record, stamp, here: checkoutState(o.project), want: o.for });
  if (v.code !== null) return noVerdict(v.why);
  if (!cur) out(`gate wait: no gate runs in this checkout; the last one to start was ${record.stamp} (pid ${record.pid}, ${record.started ?? '?'})`);
  return printStamp(o, record.stamp, stamp);
}

// ---------------------------------------------------------------- pin-safety

function cmdPinSafety(o) {
  const manifest = loadManifest(o.project);
  const dirty = statusLines(o.project).filter((l) => !l.endsWith(PINS_FILE));
  if (dirty.length) throw new Exit(3, `gate pin-safety: the tree is dirty:\n${dirty.slice(0, 20).join('\n')}`);
  const tracked = zList(git(o.project, ['ls-files', '-z']));
  const read = (f) => {
    try {
      return fs.readFileSync(path.join(o.project, f), 'utf8');
    } catch {
      return null;
    }
  };
  let pins;
  try {
    pins = computePins({ ...pinSpecOf(manifest), tracked, read });
  } catch (err) {
    out(`gate pin-safety: refused: ${err.message}`);
    return 1;
  }
  const doc = { reason: o.reason, pinned_at: gitLine(o.project, ['rev-parse', 'HEAD']), date: new Date().toISOString().slice(0, 10), ...pins };
  fs.writeFileSync(path.join(o.project, PINS_FILE), `${JSON.stringify(doc, null, 1)}\n`);
  out(`gate pin-safety: ${Object.keys(pins.files).length} files, ${pins.blocks.length} append-only functions, ${(pins.consts ?? []).length} consts in ${PINS_FILE}. Commit it alone, with an ADR.`);
  return 0;
}

// ---------------------------------------------------------------- worktrees (SPEC_GATES 4)

function mainCheckout(o) {
  const common = gitLine(o.project, ['rev-parse', '--path-format=absolute', '--git-common-dir']);
  return path.dirname(common);
}

function worktreeWrapper(o, target, args) {
  const here = fs.existsSync(path.join(target, 'tools', 'godot.sh'));
  const tools = here ? path.join(target, 'tools') : path.join(REPO, 'tools');
  if (o.shell === 'ps') {
    const sys = process.env.SystemRoot || 'C:\\Windows';
    return [path.join(sys, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(tools, 'godot.ps1'), ...args]];
  }
  return [findBash(), [path.join(tools, 'godot.sh').replaceAll('\\', '/'), ...args]];
}

async function cmdWtAdd(o) {
  const t0 = Date.now();
  const [name, branch] = o.positional;
  const root = o.wtRoot ? path.resolve(o.wtRoot) : path.join(path.dirname(mainCheckout(o)), 'wt');
  const target = path.join(root, name);
  if (fs.existsSync(target)) throw new Exit(3, `gate wt-add: ${target} already exists`);
  fs.mkdirSync(root, { recursive: true });
  git(o.project, ['worktree', 'add', '-b', branch, target, o.from]);
  ensureBuildDir(target);
  const imp = worktreeWrapper(o, target, ['--headless', '--path', '.', '--import']);
  let r = await run(imp[0], imp[1], { cwd: target, log: path.join(target, 'build', 'import.log'), env: childEnv(), quiet: true, timeoutS: 1800 });
  if (r.code !== 0) {
    // BRIEF 2's first-import rule: a fresh import that fails runs once more.
    out(`gate wt-add: first import exit ${r.code}, importing again`);
    r = await run(imp[0], imp[1], { cwd: target, log: path.join(target, 'build', 'import2.log'), env: childEnv(), quiet: true, timeoutS: 1800 });
    if (r.code !== 0) {
      out(`gate wt-add: second import exit ${r.code} (build/import2.log in ${target})`);
      return 1;
    }
  }
  const dirty = statusLines(target);
  if (dirty.length) {
    out(`gate wt-add: ${target} is dirty after import:\n${dirty.slice(0, 20).join('\n')}`);
    return 1;
  }
  out(`gate wt-add: ${target} on ${branch} from ${o.from}, ready in ${Math.round((Date.now() - t0) / 1000)} s`);
  return 0;
}

function parseWorktrees(text) {
  const rows = [];
  let cur = null;
  for (const line of text.split('\n')) {
    if (line.startsWith('worktree ')) {
      cur = { path: path.resolve(line.slice('worktree '.length)), branch: null, head: null, locked: false };
      rows.push(cur);
    } else if (cur && line.startsWith('HEAD ')) cur.head = line.slice(5).trim();
    else if (cur && line.startsWith('branch refs/heads/')) cur.branch = line.slice('branch refs/heads/'.length).trim();
    else if (cur && line.startsWith('locked')) cur.locked = true;
  }
  return rows;
}

function dirSizeMb(dir) {
  let total = 0;
  const walk = (d) => {
    let entries;
    try {
      entries = fs.readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else {
        try {
          total += fs.statSync(p).size;
        } catch {
          // gone
        }
      }
    }
  };
  walk(dir);
  return Math.round(total / 1048576);
}

function gateRunning(worktree) {
  return liveGate(path.join(worktree, 'build', 'gate')) !== null;
}

function cmdWtGc(o) {
  const main = mainCheckout(o);
  const norm = (p) => (process.platform === 'win32' ? path.resolve(p).toLowerCase() : path.resolve(p));
  const baseTip = gitLine(o.project, ['rev-parse', o.base]);
  const self = norm(o.project);
  const rows = parseWorktrees(git(o.project, ['worktree', 'list', '--porcelain'])).filter((w) => norm(w.path) !== norm(main));
  out('worktree | branch | in base | dirty | MB | action');
  const removed = [];
  for (const w of rows) {
    const inBase = gitRaw(o.project, ['merge-base', '--is-ancestor', w.head, o.base]).status === 0;
    const exists = fs.existsSync(w.path);
    const dirty = exists ? statusLines(w.path) : [];
    let action = 'keep';
    let why = inBase ? '' : 'ahead of base';
    if (!exists) why = 'missing';
    else if (w.locked) why = 'locked';
    else if (norm(w.path) === self) why = 'this checkout';
    else if (w.head === baseTip) why = 'fresh: at the base tip'; // a builder that has just started
    else if (gateRunning(w.path)) why = 'a gate is running';
    else if (dirty.length) why = 'dirty';
    else if (inBase) {
      action = 'remove';
      why = '';
    }
    out(`${path.basename(w.path)} | ${w.branch ?? '(detached)'} | ${inBase ? 'yes' : 'no'} | ${dirty.length} | ${exists ? dirSizeMb(w.path) : 0} | ${action}${why ? ` (${why})` : ''}`);
    if (dirty.length) out(dirty.slice(0, 30).map((l) => `    ${l}`).join('\n'));
    if (action === 'remove' && o.apply) {
      const r = gitRaw(o.project, ['worktree', 'remove', w.path]);
      if (r.status !== 0) {
        out(`  could not remove: ${String(r.stderr).trim()}`);
        continue;
      }
      removed.push(w.path);
      if (w.branch) {
        const d = gitRaw(o.project, ['branch', '-d', w.branch]);
        if (d.status !== 0) out(`  kept branch ${w.branch}: ${String(d.stderr).trim()}`);
      }
    }
  }
  const root = path.join(path.dirname(main), 'wt');
  const registered = new Set(rows.map((w) => norm(w.path)));
  let names = [];
  try {
    names = fs.readdirSync(root);
  } catch {
    // no worktree root
  }
  for (const n of names) {
    const p = path.join(root, n);
    if (registered.has(norm(p))) continue;
    let empty = false;
    try {
      empty = fs.statSync(p).isDirectory() && fs.readdirSync(p).length === 0;
    } catch {
      continue;
    }
    if (empty) {
      out(`${n} | empty, not registered | ${o.apply ? 'removed' : 'would remove'}`);
      if (o.apply) fs.rmdirSync(p);
    }
  }
  // Test and sim temp dirs: wattlands_<what>_<pid>_<n>. The lock dir, wattlands-godot, has no underscore.
  const tmp = os.tmpdir();
  let stale = 0;
  let cleared = 0;
  for (const n of fs.readdirSync(tmp)) {
    const m = /^wattlands_.*_(\d+)_\d+$/.exec(n);
    if (!m || pidAlive(Number(m[1]))) continue;
    const p = path.join(tmp, n);
    let old = false;
    try {
      old = Date.now() - fs.statSync(p).mtimeMs > TEMP_MAX_AGE_MS;
    } catch {
      continue;
    }
    if (!old) continue;
    stale += 1;
    if (o.apply) {
      try {
        fs.rmSync(p, { recursive: true, force: true });
        cleared += 1;
      } catch {
        // in use after all
      }
    }
  }
  out(o.apply ? `gate wt-gc: removed ${removed.length} worktrees, ${cleared} of ${stale} stale temp dirs` : `gate wt-gc: ${stale} stale temp dirs; --apply removes them and the worktrees marked remove`);
  return 0;
}

// ---------------------------------------------------------------- main

export async function main(argv) {
  const o = parseCli(argv);
  process.env.WATTLANDS_NO_HW_CONTROL = '1';
  process.env.WATTLANDS_NO_NETWORK_INTEGRATIONS = '1';
  for (const name of ['FAL_KEY', 'WATTLANDS_ALLOW_ART', 'WATTLANDS_RUN_TESTS_NESTED']) delete process.env[name];
  if (o.shell === 'bash' && !process.env.WATTLANDS_BASH) process.env.WATTLANDS_BASH = findBash();
  // Fails fast outside a git checkout, for every command.
  git(o.project, ['rev-parse', '--git-dir']);
  switch (o.cmd) {
    case 'check':
      return cmdCheck(o);
    case 'fast':
      return cmdFast(o);
    case 'strict':
      return cmdStrict(o);
    case 'matrix':
      return cmdMatrix(o);
    case 'stamp-ok':
      return cmdStampOk(o);
    case 'floor':
      return cmdFloor(o);
    case 'fmt':
      return cmdFmt(o);
    case 'wait':
      return cmdWait(o);
    case 'wt-add':
      return cmdWtAdd(o);
    case 'wt-gc':
      return cmdWtGc(o);
    case 'pin-safety':
      return cmdPinSafety(o);
    default:
      throw usageError(`unknown command "${o.cmd}"`);
  }
}

const isMain = (() => {
  if (!process.argv[1]) return false;
  const norm = (p) => (process.platform === 'win32' ? path.resolve(p).toLowerCase() : path.resolve(p));
  return norm(process.argv[1]) === norm(fileURLToPath(import.meta.url));
})();

if (isMain) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (err) => {
      if (err instanceof Exit) {
        (err.code === 0 ? process.stdout : process.stderr).write(`${err.message}\n`);
        process.exit(err.code);
      }
      process.stderr.write(`gate: ${err.stack || err}\n`);
      process.exit(1);
    },
  );
}
