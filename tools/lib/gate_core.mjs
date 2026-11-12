// tools/lib/gate_core.mjs: the pure logic behind tools/gate (shards, touched games, the merged GUT
// verdict, the rules of `tools/gate check`). No git, no processes; tools/lib/gate.mjs does the I/O.
// Only listGutFiles reads the disk. Zero dependencies.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

// ---------------------------------------------------------------- globs

const GLOB_CACHE = new Map();

/** `**` crosses "/", `*` and `?` don't, `{a,b}` is a choice. Anchored at both ends. */
export function globToRegExp(glob) {
  const cached = GLOB_CACHE.get(glob);
  if (cached) return cached;
  let re = '^';
  let depth = 0;
  for (let i = 0; i < glob.length; i += 1) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      if (glob[i + 2] === '/') {
        re += '(?:.*/)?';
        i += 2;
      } else {
        re += '.*';
        i += 1;
      }
    } else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else if (c === '{') {
      re += '(?:';
      depth += 1;
    } else if (c === '}' && depth > 0) {
      re += ')';
      depth -= 1;
    } else if (c === ',' && depth > 0) re += '|';
    else re += c.replace(/[.+^$()|[\]\\{}]/g, '\\$&');
  }
  const out = new RegExp(`${re}$`);
  GLOB_CACHE.set(glob, out);
  return out;
}

export function matchesAny(file, globs) {
  return (globs ?? []).some((g) => globToRegExp(g).test(file));
}

// ---------------------------------------------------------------- GUT files and shards

/** The files GUT collects: tests/<...>/test_*.gd, no hidden directory on the way. */
export function isGutFile(file) {
  return /^tests\/(?:[^./][^/]*\/)*test_[^/]*\.gd$/.test(file);
}

/**
 * tests/<...>/test_*.gd holding at least one test function, sorted, forward slashes. No tests/ at all
 * is an empty list (the verdict then fails on "no GUT process ran"); any other read error throws, so
 * an unreadable directory can't quietly drop files from the run.
 */
export function listGutFiles(projectDir) {
  const out = [];
  const walk = (dir, rel) => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (err) {
      if (err.code === 'ENOENT') return;
      throw err;
    }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue;
      const childRel = `${rel}/${e.name}`;
      if (e.isDirectory()) walk(path.join(dir, e.name), childRel);
      else if (isGutFile(childRel) && /^\s*func test_/m.test(fs.readFileSync(path.join(dir, e.name), 'utf8'))) {
        out.push(childRel);
      }
    }
  };
  walk(path.join(projectDir, 'tests'), 'tests');
  return out.sort();
}

/** tests/games/<id>/<sub>/.. -> that dir; tests/games/<id>/test_x.gd -> tests/games/<id>/(root); else tests/<area>. */
export function groupKey(file) {
  const parts = file.split('/');
  if (parts[0] === 'tests' && parts[1] === 'games' && parts.length >= 4) {
    return parts.length === 4 ? `tests/games/${parts[2]}/(root)` : `tests/games/${parts[2]}/${parts[3]}`;
  }
  if (parts.length >= 3) return `tests/${parts[1]}`;
  return 'tests/(root)';
}

/** Map file -> seconds from a JUnit file's <testsuite name time> tags. */
export function readWeights(junitXml) {
  const out = new Map();
  for (const m of String(junitXml ?? '').matchAll(/<testsuite\b[^>]*>/g)) {
    const name = /\bname="([^"]*)"/.exec(m[0]);
    const time = /\btime="([\d.]+)"/.exec(m[0]);
    if (name && time) out.set(name[1], (out.get(name[1]) ?? 0) + Number(time[1]));
  }
  return out;
}

/**
 * May this group's files run in different processes? A game's test groups may: none of them writes a
 * shared res://build/<dir> (the platform's scenarios, rides and core stack tests do), and their temp dirs
 * carry the pid. A pinned group never splits.
 */
export function splittableGroup(group) {
  return group.startsWith('tests/games/');
}

/**
 * The content of tools/lib/gate_weights.json: {group: seconds} and, for the files of splittable groups,
 * {file: seconds}, sorted, for stable diffs. A file key ends in .gd, a group key never does.
 */
export function weightsByGroup(fileWeights) {
  const sum = new Map();
  const perFile = new Map();
  for (const [suite, seconds] of fileWeights) {
    const g = groupKey(suite);
    sum.set(g, (sum.get(g) ?? 0) + seconds);
    const file = suite.replace(/(\.gd)\..*$/, '$1');
    if (splittableGroup(g)) perFile.set(file, (perFile.get(file) ?? 0) + seconds);
  }
  const all = new Map([...sum, ...perFile]);
  const out = {};
  for (const k of [...all.keys()].sort()) out[k] = Math.round(all.get(k) * 10) / 10;
  return out;
}

const NO_DATA_S_PER_FILE = 2;

/**
 * Longest bundle first into the lightest shard, ties by name. A bundle is a group, or one file of a
 * splittable group heavier than half a shard's share (its weight from the file's own entry, else an even
 * part of the group's): so a long game group no longer sets the wall time on its own. Other groups never
 * split, so every writer of one res://build/<dir> stays in one process; nor does a game group in
 * `noSplit` (buildDirGroups: one of its files names res://build). `pins` (arrays of groups) forces
 * groups together. Files matching `quiet` (globs) come back apart. Empty shards are dropped.
 * Returns { shards: string[][], quiet: string[] }; throws unless they partition `files` exactly.
 */
export function planShards(files, groupWeights, { shards = 8, quiet = [], pins = [], noSplit = [] } = {}) {
  if (!Number.isInteger(shards) || shards < 1) throw new RangeError(`shards must be a positive integer, got ${shards}`);
  const known = (g) => (groupWeights instanceof Map ? groupWeights.get(g) : groupWeights?.[g]);
  const quietFiles = files.filter((f) => matchesAny(f, quiet));
  const groups = new Map();
  for (const f of files) {
    if (matchesAny(f, quiet)) continue;
    const g = groupKey(f);
    if (!groups.has(g)) groups.set(g, []);
    groups.get(g).push(f);
  }
  const weightOf = (g) => {
    const w = known(g);
    return Number.isFinite(w) ? w : groups.get(g).length * NO_DATA_S_PER_FILE;
  };
  const taken = new Set();
  const bundles = [];
  for (const pin of pins) {
    const present = pin.filter((g) => groups.has(g) && !taken.has(g));
    if (present.length === 0) continue;
    for (const g of present) taken.add(g);
    bundles.push({
      name: [...present].sort()[0],
      files: present.flatMap((g) => groups.get(g)),
      weight: present.reduce((s, g) => s + weightOf(g), 0),
    });
  }
  const total = [...groups.keys()].reduce((s, g) => s + weightOf(g), 0);
  const splitAbove = total / shards / 2;
  for (const g of groups.keys()) {
    if (taken.has(g)) continue;
    const members = groups.get(g);
    if (!splittableGroup(g) || noSplit.includes(g) || members.length < 2 || weightOf(g) <= splitAbove) {
      bundles.push({ name: g, files: members, weight: weightOf(g) });
      continue;
    }
    const share = weightOf(g) / members.length;
    for (const f of members) {
      const w = known(f);
      bundles.push({ name: f, files: [f], weight: Number.isFinite(w) ? w : share });
    }
  }
  bundles.sort((a, b) => b.weight - a.weight || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  const bins = Array.from({ length: shards }, () => ({ files: [], weight: 0 }));
  for (const b of bundles) {
    let best = bins[0];
    for (const bin of bins) if (bin.weight < best.weight) best = bin;
    best.files.push(...b.files);
    best.weight += b.weight;
  }
  const planned = bins.filter((b) => b.files.length > 0).map((b) => [...b.files].sort());
  const seen = [...planned.flat(), ...quietFiles];
  const want = new Set(files);
  if (seen.length !== files.length || new Set(seen).size !== seen.length || !seen.every((f) => want.has(f))) {
    throw new Error(`planShards: the shards hold ${seen.length} files, the input ${files.length}`);
  }
  return { shards: planned, quiet: quietFiles };
}

// ---------------------------------------------------------------- which game owns a path

/**
 * The one table of a game's own paths, `<id>` for the game. Every selection reads it through
 * pathOwner: the GUT selection of `fast`, the Node suites of `--node-since`, the sim and e2e games
 * (touchedGames), and the ownership rule of `check` (gamePaths). `own` is what the game builds and
 * runs; `docs` is its text beside the platform's, which runs nothing. A workflow is `.yml` only: the
 * static step parses `.github/workflows/*.yml`, so a `.yaml` is no game's and selects everything.
 */
export const GAME_PATHS = {
  own: ['src/games/<id>/**', 'content/<id>/**', 'assets/<id>/**', 'tests/games/<id>/**', '.github/workflows/game-<id>.yml'],
  docs: ['docs/decisions/<id>.md', 'docs/changelog.d/<id>.md', 'docs/credits.d/<id>.md', 'docs/games/<id>.md'],
};

/** GAME_PATHS for one game, as globs. */
export function gamePathGlobs(id, kinds = ['own', 'docs']) {
  return kinds.flatMap((k) => GAME_PATHS[k].map((p) => p.replaceAll('<id>', id)));
}

/**
 * The registered game that owns `p` by GAME_PATHS, and how: { game, kind: 'own'|'docs' }, or null
 * (the platform, _template, an unregistered game, any other doc).
 */
export function pathOwner(p, registeredIds) {
  for (const id of registeredIds) {
    for (const kind of ['own', 'docs']) {
      if (matchesAny(p, gamePathGlobs(id, [kind]))) return { game: id, kind };
    }
  }
  return null;
}

/**
 * Text that selects no sim and no e2e: docs, any Markdown, workflows other than game-*. A game-*
 * workflow that is no registered game's own (game-nope.yml, game-tank.yaml) is not text: it selects all.
 */
function isPlainText(p) {
  return p.startsWith('docs/') || p.endsWith('.md') || /^\.github\/workflows\/(?!game-)[^/]+$/.test(p);
}

/**
 * Which games a change set touches, for sim and e2e. A game's own path (pathOwner) touches that game,
 * unless it is text (its README); docs, *.md and other workflows touch nothing; anything else,
 * _template included, sets `platform` and selects every registered game. Returns { games, platform }.
 */
export function touchedGames(changedPaths, registeredIds) {
  const ids = [...new Set(registeredIds)];
  const games = new Set();
  let platform = false;
  for (const p of changedPaths) {
    if (isPlainText(p)) continue;
    const owner = pathOwner(p, ids);
    if (owner) games.add(owner.game);
    else platform = true;
  }
  return { games: platform ? [...ids].sort() : [...games].sort(), platform };
}

/**
 * Which games' GUT files a `fast` runs for a change set. Stricter than touchedGames: a doc outside a
 * game's own fragments counts as platform here. Only when every changed path is a registered game's own
 * path do the other games' tests/games/<id>/ files stay out; any other path, _template's included, and
 * an empty change set run everything. Platform files and unregistered dirs under tests/games always run.
 * Leaving a game out rests on no game referencing another: `crossRefs` (crossGameRefs over the tree)
 * holding anything runs everything, so the selection fails closed. Returns { all, games, reason }.
 */
export function gutSelection(changedPaths, registeredIds, { crossRefs = [] } = {}) {
  const ids = [...new Set(registeredIds)].sort();
  if (changedPaths.length === 0) return { all: true, games: ids, reason: 'no change against the base' };
  if (crossRefs.length > 0) {
    const first = crossRefs[0];
    return { all: true, games: ids, reason: `${crossRefs.length} cross-game references in the games' own paths (first: ${first.file}:${first.line} names ${first.game}: ${first.text})` };
  }
  const games = new Set();
  for (const p of changedPaths) {
    const owner = pathOwner(p, ids);
    if (owner === null) return { all: true, games: ids, reason: `${p} is outside the games' own paths` };
    games.add(owner.game);
  }
  const picked = [...games].sort();
  if (picked.length === ids.length) return { all: true, games: ids, reason: 'the change touches every game' };
  return { all: false, games: picked, reason: `the change touches only the own paths of ${picked.join(', ')}` };
}

/** Splits GUT files by a gutSelection: { run, skipped, skippedGames }. Only registered games' dirs are ever skipped. */
export function selectGutFiles(files, selection, registeredIds) {
  if (selection.all) return { run: [...files], skipped: [], skippedGames: [] };
  const ids = new Set(registeredIds);
  const run = [];
  const skipped = [];
  const skippedGames = new Set();
  for (const f of files) {
    const id = /^tests\/games\/([^/]+)\//.exec(f)?.[1];
    if (id !== undefined && ids.has(id) && !selection.games.includes(id)) {
      skipped.push(f);
      skippedGames.add(id);
    } else run.push(f);
  }
  return { run, skipped, skippedGames: [...skippedGames].sort() };
}

/**
 * Does a stamp's GUT selection cover what this tree needs? `stamped`: the stamp's gut_selection; `need`:
 * gutSelection of this tree against main. Returns null, or why not.
 */
export function selectionGap(stamped, need) {
  if (!stamped || typeof stamped.all !== 'boolean' || !Array.isArray(stamped.games)) return 'it records no GUT selection';
  if (stamped.all) return null;
  if (need.all) return `it left out the GUT files of ${(stamped.skipped_games ?? []).join(', ') || 'some games'}, and this tree needs every file (${need.reason})`;
  const lost = need.games.filter((id) => !stamped.games.includes(id));
  return lost.length ? `its GUT run left out ${lost.join(', ')}, which this tree touches` : null;
}

// ---------------------------------------------------------------- what the selection and the shards assume

/** The roots a game's code, tests and content live under: what crossGameRefs reads. */
export const CROSS_SCAN_ROOTS = ['src/games/<id>/', 'tests/games/<id>/', 'content/<id>/'];
const SCAN_HASH_COMMENTS = /\.(gd|sh|cfg|tscn|tres|py|ya?ml)$/;
const SCAN_SLASH_COMMENTS = /\.([cm]?js|ts|gdshader|gdshaderinc)$/;
const SCAN_DATA = /\.(json|csv|txt|tsv)$/;

/** Is `file` text the scans read: code, scenes and data, never Markdown or binaries. */
export function isScannedFile(file) {
  return SCAN_HASH_COMMENTS.test(file) || SCAN_SLASH_COMMENTS.test(file) || SCAN_DATA.test(file);
}

/**
 * `src` with its comments blanked out (line breaks kept, so line numbers hold). Strings stay: a path in
 * one is a reference. `#` comments for GDScript, shell, scenes and config; `//` and block comments for
 * JavaScript and shaders; none for data. A quote inside a comment, or a `#` inside a string, is read right.
 */
export function stripComments(file, src) {
  const hash = SCAN_HASH_COMMENTS.test(file);
  const slash = SCAN_SLASH_COMMENTS.test(file);
  if (!hash && !slash) return src;
  const quotes = hash ? ['"""', "'''", '"', "'"] : ['`', '"', "'"];
  let out = '';
  let i = 0;
  const blank = (text) => text.replace(/[^\n]/g, ' ');
  while (i < src.length) {
    const c = src[i];
    if ((hash && c === '#') || (slash && src.startsWith('//', i))) {
      const end = src.indexOf('\n', i);
      const stop = end < 0 ? src.length : end;
      out += blank(src.slice(i, stop));
      i = stop;
      continue;
    }
    if (slash && src.startsWith('/*', i)) {
      const end = src.indexOf('*/', i + 2);
      const stop = end < 0 ? src.length : end + 2;
      out += blank(src.slice(i, stop));
      i = stop;
      continue;
    }
    const q = quotes.find((x) => src.startsWith(x, i));
    if (q) {
      let j = i + q.length;
      while (j < src.length && !src.startsWith(q, j)) {
        if (src[j] === '\\') j += 1;
        else if (q.length === 1 && q !== '`' && src[j] === '\n') break; // an unclosed one-line string ends at the line
        j += 1;
      }
      const stop = Math.min(src.length, j + (src.startsWith(q, j) ? q.length : 0));
      out += src.slice(i, stop);
      i = stop;
      continue;
    }
    out += c;
    i += 1;
  }
  return out;
}

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** A game id's class prefix and string-key prefix: tank -> Tank, TANK_; big_game -> BigGame, BIG_GAME_. */
export function gamePrefixes(id) {
  const pascal = id.split(/[_-]+/).filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join('');
  return { pascal, upper: `${id.toUpperCase().replace(/-/g, '_')}_` };
}

function crossPatterns(id) {
  const { pascal, upper } = gamePrefixes(id);
  const e = escapeRe(id);
  return [
    new RegExp(`(?:res://)?(?:src/games|content|assets|tests/games)/${e}(?![\\w-])`, 'g'),
    new RegExp(`\\.\\./(?:\\.\\./)*(?:games/)?${e}/`, 'g'),
    new RegExp(`\\b${escapeRe(pascal)}[A-Z][A-Za-z0-9_]*`, 'g'),
    new RegExp(`\\b${escapeRe(upper)}[A-Z0-9][A-Z0-9_]*\\b`, 'g'),
  ];
}

/** The registered game whose own scanned root holds `file`, or null. */
function scanOwner(file, ids) {
  const m = /^(?:src\/games|tests\/games|content)\/([^/]+)\//.exec(file);
  return m && ids.includes(m[1]) ? m[1] : null;
}

/**
 * References from one game's own paths (CROSS_SCAN_ROOTS) to another registered game: its paths
 * (`res://src/games/siege/...`, `content/siege`, `../siege/`), its class names (`SiegeHud`) and its
 * string keys (`SIEGE_TITLE`). Comments are ignored; a plain id in a string (`"workout"`,
 * `game_id: 'siege'`) names no path, class or key, so it is no reference. `sources`: {path: text} or a
 * Map; files outside the roots or not isScannedFile are skipped. Returns [{file, line, game, text}].
 */
export function crossGameRefs(sources, registeredIds) {
  const ids = [...new Set(registeredIds)].sort();
  const patterns = new Map(ids.map((id) => [id, crossPatterns(id)]));
  const refs = [];
  const entries = sources instanceof Map ? [...sources] : Object.entries(sources ?? {});
  for (const [file, src] of entries.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
    const owner = scanOwner(file, ids);
    if (!owner || !isScannedFile(file) || typeof src !== 'string') continue;
    const lines = stripComments(file, src).split('\n');
    lines.forEach((text, n) => {
      for (const id of ids) {
        if (id === owner) continue;
        for (const re of patterns.get(id)) {
          re.lastIndex = 0;
          const m = re.exec(text);
          if (m) {
            refs.push({ file, line: n + 1, game: id, text: m[0] });
            break;
          }
        }
      }
    });
  }
  return refs;
}

/** A cross-game reference for a report line. */
export const formatCrossRef = (r) => `${r.file}:${r.line} names ${r.game} (${r.text})`;

/**
 * The game test groups that must stay in one process: planShards splits a game's group into files on
 * the ground that none of them shares a res://build/<dir>. A .gd under tests/games/<id>/ that names
 * res://build (comments aside) pins its group; one outside every test group (a helper folder) pins all
 * of that game's groups, since any test may call it. `sources`: {path: text} of the .gd files under
 * tests/games; `gutFiles`: the GUT files. Returns the group keys, sorted.
 */
export function buildDirGroups(sources, gutFiles) {
  const groups = new Set(gutFiles.map(groupKey));
  const out = new Set();
  const entries = sources instanceof Map ? [...sources] : Object.entries(sources ?? {});
  for (const [file, src] of entries) {
    const id = /^tests\/games\/([^/]+)\//.exec(file)?.[1];
    if (!id || !file.endsWith('.gd') || typeof src !== 'string') continue;
    if (!/res:\/\/build\b/.test(stripComments(file, src))) continue;
    const g = groupKey(file);
    if (groups.has(g)) out.add(g);
    else for (const other of groups) if (other.startsWith(`tests/games/${id}/`)) out.add(other);
  }
  return [...out].sort();
}

// ---------------------------------------------------------------- pool sizes

/**
 * How many parts of each lane run at once, from the CPU count and the Godot slot cap (machineCap with
 * the held slots counted back). Godot work follows the cap: GUT shards and matrix workers, one per slot;
 * pooled sims, at most 8 (each still takes its slot). The rest follows the CPUs, with floors so a small
 * machine still overlaps a little: Node suites (one per 2.5 CPUs, 2 to 8), static (lint and format, two
 * Python processes per part: 0.3 per CPU, 1 to 6) and the node lane's private Godot cap (a fifth, 2 to 4).
 */
export function poolSizes({ cpus, cap }) {
  const c = Number.isInteger(cpus) && cpus > 0 ? cpus : 1;
  const k = Number.isInteger(cap) && cap > 0 ? cap : 2;
  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  return {
    shards: Math.max(2, k),
    matrixJobs: Math.max(2, k),
    simJobs: clamp(k, 1, 8),
    nodeJobs: clamp(Math.floor(c / 2.5), 2, 8),
    staticJobs: clamp(Math.round(c * 0.3), 1, 6),
    nodeLockCap: clamp(Math.floor(c / 5), 2, 4),
  };
}

// ---------------------------------------------------------------- tools/gate wait

/** Exit of `tools/gate wait` with no verdict to give: none written, another gate's, or for another tree. */
export const WAIT_NO_VERDICT_EXIT = 4;
/** A gate's run.lock is beaten every few seconds; older than this, its pid is no proof of life (reused). */
export const GATE_STALE_MS = 60_000;
/** The stamps `wait --for` may name: what a gate that holds the mutex writes, check and fmt aside. */
export const WAIT_FOR_RE = /^(?:fast|strict|matrix_[a-z0-9][a-z0-9_-]*)$/;

/** Is a mutex record a live gate? Its pid runs and its heartbeat (the lock file's mtime) is fresh. */
export function gateAlive(record, { mtimeMs, now, pidAlive }) {
  if (!record || !Number.isInteger(record.pid) || record.pid <= 0) return false;
  if (!pidAlive(record.pid)) return false;
  return Number.isFinite(mtimeMs) && now - mtimeMs < GATE_STALE_MS;
}

/**
 * The verdict `tools/gate wait` may report, or why there is none. `record`: the last gate that took the
 * mutex here (current.json); `stamp`: build/gate/<record.stamp>.json, or null; `here`: the checkout now
 * ({tree, dirty, dirtyHash}); `want`: --for, or null. Only that gate's own stamp counts (its run token),
 * never check's or fmt's, never another gate's, never one for another tree or another set of changes.
 * Returns { code, why } with code null when the stamp stands (its exit_code is the verdict).
 */
export function waitVerdict({ record, stamp, here, want = null }) {
  const none = (why) => ({ code: WAIT_NO_VERDICT_EXIT, why });
  if (!record) return none(want ? `no ${want} has started in this checkout` : 'no gate has started in this checkout');
  if (!record.stamp || !WAIT_FOR_RE.test(record.stamp)) return none(`the last gate here was ${record.cmd ?? '?'}, which has no verdict to wait for${want ? ` (you asked for ${want})` : ''}`);
  if (want && record.stamp !== want) return none(`the last gate to start here was ${record.stamp}, not ${want}: a ${want} that was refused or never started has no verdict`);
  if (!stamp) return none(`${record.stamp} (pid ${record.pid}, started ${record.started ?? '?'}) ended without a stamp: refused, killed or crashed; its output is where it ran`);
  if (!record.token || stamp.run !== record.token) return none(`build/gate/${record.stamp}.json is from another run (${stamp.run ?? 'no run token'}), not the one that started ${record.started ?? '?'}`);
  if (stamp.tree !== here.tree) return none(`the stamp is for tree ${stamp.tree ?? '?'}, and this checkout's is ${here.tree}: commit or check out what it ran, or run it again`);
  if (Boolean(stamp.dirty) !== Boolean(here.dirty)) return none(`the stamp ran on a ${stamp.dirty ? 'dirty' : 'clean'} tree, and this checkout is ${here.dirty ? 'dirty' : 'clean'} now`);
  if (here.dirty && stamp.dirty_hash !== here.dirtyHash) return none('the uncommitted changes are not the ones the gate ran on');
  return { code: null, why: null };
}

function junitSuiteNames(xml) {
  const out = [];
  for (const m of String(xml ?? '').matchAll(/<testsuite\b[^>]*>/g)) {
    const name = /\bname="([^"]*)"/.exec(m[0]);
    if (name) out.push(name[1]);
  }
  return out;
}

/** Tests per file in a JUnit file: Map file -> the suite's `tests` attribute, else its testcases. Inner-class suites ("x.gd.Inner") count for x.gd. */
export function junitTestsByFile(xml) {
  const out = new Map();
  for (const m of String(xml ?? '').matchAll(/<testsuite\b([^>]*)>([\s\S]*?)<\/testsuite>/g)) {
    const name = /\bname="([^"]*)"/.exec(m[1]);
    if (!name) continue;
    const file = name[1].replace(/(\.gd)\..*$/, '$1');
    const attr = /\btests="(\d+)"/.exec(m[1]);
    const n = attr ? Number(attr[1]) : (m[2].match(/<testcase\b/g) ?? []).length;
    out.set(file, (out.get(file) ?? 0) + n);
  }
  return out;
}

/**
 * Files whose JUnit count is below their source count. GUT collects inner classes only with the `Test`
 * prefix and a config can narrow a run by test name, so a failing test can vanish while the file stays in
 * the JUnit. `sourceCounts`: {file: countTests(source)}. A file in no JUnit is junitCoverage's business.
 * problems[].
 */
export function junitCountProblems(junitXmls, sourceCounts) {
  const seen = new Map();
  for (const xml of junitXmls) {
    for (const [file, n] of junitTestsByFile(xml)) seen.set(file, (seen.get(file) ?? 0) + n);
  }
  const problems = [];
  for (const [file, want] of Object.entries(sourceCounts ?? {})) {
    const got = seen.get(file);
    if (got !== undefined && got < want) problems.push(`${file}: the JUnit holds ${got} tests, the source ${want}: GUT did not run ${want - got} (an inner class without the Test prefix? a narrowed run?)`);
  }
  return problems;
}

/** {file: test functions in its source} for files under projectDir. A file that can't be read throws. */
export function sourceTestCounts(projectDir, files) {
  return Object.fromEntries(files.map((f) => [f, countTests(fs.readFileSync(path.join(projectDir, f), 'utf8'))]));
}

/**
 * The verdict over all shards. `results`: one { name, junitXml, ...evaluateGut output } per process.
 * Fails on any failed shard, a file of `expectedFiles` in no JUnit, a file in two JUnits, a file whose
 * JUnit count is below `sourceCounts`, and a total below `floor` (null: no floor). Returns { pass, total, reasons }.
 */
export function aggregateGut(results, { floor = null, expectedFiles = [], sourceCounts = {} } = {}) {
  const reasons = [];
  if (results.length === 0) reasons.push('no GUT process ran');
  let total = 0;
  const seenIn = new Map();
  for (const r of results) {
    total += r.tests ?? 0;
    if (!r.pass) reasons.push(`${r.name}: ${(r.reasons ?? []).join('; ') || 'failed'}`);
    for (const suite of junitSuiteNames(r.junitXml)) {
      if (seenIn.has(suite)) reasons.push(`${suite} ran in both ${seenIn.get(suite)} and ${r.name}`);
      else seenIn.set(suite, r.name);
    }
  }
  for (const f of expectedFiles) {
    if (!seenIn.has(f)) reasons.push(`${f} is in no JUnit file`);
  }
  reasons.push(...junitCountProblems(results.map((r) => r.junitXml), sourceCounts));
  if (Number.isInteger(floor) && floor > 0 && total < floor) reasons.push(`the shards ran ${total} tests, fewer than the floor ${floor}`);
  return { pass: reasons.length === 0, total, reasons };
}

/** Files of `files` with no <testsuite name> in the JUnit: what GUT was expected to run and did not. problems[]. */
export function junitCoverage(junitXml, files) {
  const seen = new Set(junitSuiteNames(junitXml));
  return files.filter((f) => !seen.has(f)).map((f) => `${f} is in no JUnit suite`);
}

/** Failed testcases of a GUT JUnit file: [{file, name}]. */
export function failingCases(junitXml) {
  const out = [];
  for (const m of String(junitXml ?? '').matchAll(/<testcase\b([^>]*)>([\s\S]*?)<\/testcase>/g)) {
    const failed = /\bstatus="fail"/.test(m[1]) || /<failure\b/.test(m[2]);
    if (!failed) continue;
    out.push({ file: (/\bclassname="([^"]*)"/.exec(m[1]) ?? [])[1] ?? '', name: (/\bname="([^"]*)"/.exec(m[1]) ?? [])[1] ?? '' });
  }
  return out;
}

const GD_FUNC = /^(?:static )?func (\w+)\s*\(/;

/** A GDScript file's top-level functions: Map name -> body text. */
function gdFunctions(src) {
  const out = new Map();
  let name = null;
  let body = [];
  for (const line of String(src).replace(/\r\n/g, '\n').split('\n')) {
    const m = GD_FUNC.exec(line);
    if (m || /^(?:class|var|const|signal|enum|@)/.test(line)) {
      if (name) out.set(name, body.join('\n'));
      name = m ? m[1] : null;
      body = [];
    } else if (name) body.push(line);
  }
  if (name) out.set(name, body.join('\n'));
  return out;
}

/** Does this test measure wall time, in its own body or through a function of its file it calls? */
export function isBudgetTest(src, testName) {
  const fns = gdFunctions(src);
  const seen = new Set();
  const stack = [testName];
  while (stack.length > 0) {
    const name = stack.pop();
    if (seen.has(name) || !fns.has(name)) continue;
    seen.add(name);
    const body = fns.get(name);
    if (/\bTime\.get_ticks_usec\b/.test(body)) return true;
    for (const m of body.matchAll(/\b(\w+)\s*\(/g)) stack.push(m[1]);
  }
  return false;
}

// GUT exits 1 on failed tests. Any other code is a crash or a kill, which a rerun must not wash out.
const RETRYABLE_REASON = /^(?:GUT exit code 1|JUnit reports \d+ failed tests?)$/;

/**
 * May the quiet lane rerun after this first verdict? A budget is a claim about an unloaded machine, so a
 * rerun is for budgets only: every reason is a plain test failure (never a FORBIDDEN string, a crash or a
 * missing summary), at least one test failed, and each failed test measures wall time. `read(file)` gives
 * a test file's source. Returns { allowed, tests, why }.
 */
export function quietRetryPlan({ reasons, junitXml, read }) {
  const failed = failingCases(junitXml);
  const tests = failed.map((c) => `${c.file}::${c.name}`);
  const other = (reasons ?? []).filter((r) => !RETRYABLE_REASON.test(r));
  if (other.length > 0) return { allowed: false, tests, why: other.join('; ') };
  if (failed.length === 0) return { allowed: false, tests, why: 'no failed testcase in the JUnit file' };
  const notBudget = failed.filter((c) => !isBudgetTest(read(c.file) ?? '', c.name));
  if (notBudget.length > 0) return { allowed: false, tests, why: `not a budget test: ${notBudget.map((c) => `${c.file}::${c.name}`).join(', ')}` };
  return { allowed: true, tests, why: '' };
}

export const LANE_PASS_LINE = 'run_tests: all selected gates passed';
export const LANE_SKIP_STRINGS = ['gdtoolkit unavailable, skipped', 'workflow YAML check unavailable', 'workflow YAML check could not run'];

/**
 * A `run_tests --only=<steps>` lane: exit 0, the pass line in its last summary, every selected
 * step's row PASS (import may be WARN; a SKIP row fails, which catches a stray nested env), and none
 * of the three "the check did not really run" strings anywhere.
 */
export function laneVerdict({ code, text, steps }) {
  if (code !== 0) return 'FAIL';
  const all = String(text ?? '');
  const at = all.lastIndexOf('run_tests summary');
  if (at < 0) return 'FAIL';
  const tail = all.slice(at);
  if (!tail.includes(LANE_PASS_LINE)) return 'FAIL';
  if (LANE_SKIP_STRINGS.some((s) => all.includes(s))) return 'FAIL';
  for (const step of steps ?? []) {
    const row = new RegExp(`^  ${step}\\s+(PASS|FAIL|SKIP|WARN)\\b`, 'm').exec(tail);
    if (!row) return 'FAIL';
    if (row[1] === 'PASS' || (row[1] === 'WARN' && step === 'import')) continue;
    return 'FAIL';
  }
  return 'PASS';
}

/**
 * The checker's own rows ("PASS S4 ...", "FAIL ALL ...", "SKIP R1 ...") in a matrix's check phase. Exit 0
 * alone is no evidence: a script can skip its checker and still exit 0. Passes on at least one PASS row, no
 * FAIL row, every `required` row PASS and, in a full matrix, no SKIP row, since a scenario with all its
 * reports missing reads as SKIP. Returns { pass, rows, reasons }.
 */
export function checkerEvidence({ code, text, partial = false, required = [] }) {
  const rows = new Map();
  for (const m of String(text ?? '').matchAll(/^(PASS|FAIL|SKIP) +(\S+)/gm)) rows.set(m[2], m[1]);
  const named = (status) => [...rows].filter(([, s]) => s === status).map(([id]) => id);
  const reasons = [];
  if (code !== 0) reasons.push(`the check phase exited ${code}`);
  if (named('PASS').length === 0) reasons.push('no PASS row: the checker did not run');
  if (named('FAIL').length > 0) reasons.push(`FAIL rows: ${named('FAIL').join(', ')}`);
  if (!partial && named('SKIP').length > 0) reasons.push(`SKIP rows in a full matrix: ${named('SKIP').join(', ')}`);
  if (!partial) {
    for (const id of required) if (rows.get(id) !== 'PASS') reasons.push(`the required row ${id} is ${rows.get(id) ?? 'missing'}`);
  }
  return { pass: reasons.length === 0, rows: rows.size, passed: named('PASS'), reasons };
}

/**
 * The order a matrix pool takes its runs in: indices of `stems`, the runs with no time in `previousMs`
 * ({stem: ms} from the last matrix) first, since any of them may be long, then the longest first. Ties keep
 * the plan's order. Order changes only when a run starts, never what runs.
 */
export function longestFirst(stems, previousMs = {}) {
  const ms = (i) => {
    const v = previousMs?.[stems[i]];
    return Number.isFinite(v) ? v : Infinity;
  };
  return stems.map((_, i) => i).sort((a, b) => ms(b) - ms(a) || a - b);
}

/**
 * What the manifest asks of a game's full matrix, or null when it asks nothing: `rows` its checker must
 * pass, `minRuns` the runs its plan must hold. Both are floors: a matrix may grow, and a game's script
 * can't narrow itself (a hard-coded --only, fewer seeds or crews), since nothing else compares it.
 */
export function matrixRule(manifest, id) {
  const rows = manifest.matrix_required_rows?.[id];
  const minRuns = manifest.matrix_min_runs?.[id];
  if (rows === undefined && minRuns === undefined) return null;
  return { rows: rows ?? [], minRuns: minRuns ?? 1 };
}

/**
 * Why a `fast` run does not stand for the whole gate of its tree: anything that narrowed it. An empty
 * list means it may pass stamp-ok. `--games` wider than what the branch touches narrows nothing.
 */
export function fastNarrowing({ lanes = null, baseSha, mainSha, base = 'main', ws = null, inferredWs = null, allow = [], allowPin = [], contributor = false, games = [], requiredGames = [] }) {
  const out = [];
  if (lanes !== null) out.push(`--lanes=${lanes.join(',')}`);
  if (!mainSha || baseSha !== mainSha) out.push(`--base=${base} is not main`);
  if (ws !== null && ws !== inferredWs) out.push(`--ws=${ws} is not the branch's workstream (${inferredWs ?? 'none'})`);
  if (allow.length > 0) out.push(`--allow=${allow.join(',')}`);
  if (allowPin.length > 0) out.push(`--allow-pin=${allowPin.join(',')}`);
  if (contributor) out.push('--contributor');
  const missing = requiredGames.filter((g) => !games.includes(g));
  if (missing.length > 0) out.push(`--games leaves out ${missing.join(',')}`);
  return out;
}

const sameSet = (a, b) => {
  const x = [...new Set(a)].sort();
  const y = [...new Set(b)].sort();
  return x.length === y.length && x.every((v, i) => v === y[i]);
};

/**
 * stamp-ok with --allow/--allow-pin: a `fast` stamp stands only when its exceptions are exactly the ones the
 * caller names and they are its only narrowing. An exception reaches the check lane alone; every test lane
 * ran in full. Returns null, or why not.
 */
export function allowGap(stamp, allow = [], allowPin = []) {
  const globs = stamp.allow_globs;
  const pins = stamp.allow_pins;
  if (!Array.isArray(globs) || !Array.isArray(pins)) return 'it records no --allow and --allow-pin lists';
  if (!sameSet(globs, allow) || !sameSet(pins, allowPin)) {
    return `it ran with --allow=${globs.join(',') || 'none'} --allow-pin=${pins.join(',') || 'none'}, not the exceptions stamp-ok was given`;
  }
  if (!sameSet(stamp.allow ?? [], [...globs, ...pins])) return 'its allow list does not match its --allow and --allow-pin lists';
  const expected = fastNarrowing({ baseSha: 'base', mainSha: 'base', allow: globs, allowPin: pins });
  const reasons = Array.isArray(stamp.partial_reasons) ? stamp.partial_reasons : [];
  if (stamp.partial !== true || !sameSet(reasons, expected)) {
    const other = reasons.filter((r) => !expected.includes(r));
    return `it is partial for more than its exceptions${other.length ? ` (${other.join('; ')})` : ''}`;
  }
  return null;
}

// ---------------------------------------------------------------- source scans

export function countTests(src) {
  return (String(src).match(/^\s*func test_/gm) || []).length;
}

/** Top-level and nested `test(` and `it(` calls of a Node test file. `test.skip(` does not count, so skipping reads as a fall. */
export function countNodeTests(src) {
  return (String(src).match(/^[ \t]*(?:test|it)\(/gm) || []).length;
}

export function countAsserts(src) {
  return (String(src).match(/\bassert_\w+\(/g) || []).length;
}

/** The lines from ^(export )?function name( to the next ^}, LF-joined; null when absent. */
export function extractFunction(src, name) {
  const lines = String(src).replace(/\r\n/g, '\n').split('\n');
  const start = lines.findIndex((l) => l.startsWith(`function ${name}(`) || l.startsWith(`export function ${name}(`));
  if (start < 0) return null;
  for (let i = start; i < lines.length; i += 1) {
    if (lines[i].startsWith('}')) return lines.slice(start, i + 1).join('\n');
  }
  return null;
}

/** The statement of a top-level const: from ^(export )?const name to the line that closes it, LF-joined; null when absent. */
export function extractConst(src, name) {
  const lines = String(src).replace(/\r\n/g, '\n').split('\n');
  const re = new RegExp(`^(?:export )?const ${name}\\b`);
  const start = lines.findIndex((l) => re.test(l));
  if (start < 0) return null;
  for (let i = start; i < lines.length; i += 1) {
    if (i === start ? lines[i].trimEnd().endsWith(';') : /^[}\])]/.test(lines[i])) return lines.slice(start, i + 1).join('\n');
  }
  return null;
}

/** A table: a const whose value is an object or array literal. New entries may be appended to one. */
function isTable(statement) {
  return /^(?:export )?const \w+(?:\s*:[^=]+)?\s*=\s*[{[][\s\S]*[}\]];\s*$/.test(statement);
}

/**
 * What a checker's pinned functions rest on: the top-level functions and consts they name, followed
 * through functions and through arrow consts, but not through a table (a table of checks names every
 * check of the file). Returns { functions, consts } in file order. Names not found are ignored.
 */
export function pinClosure(src, roots) {
  const text = String(src).replace(/\r\n/g, '\n');
  const fnNames = [...text.matchAll(/^(?:export )?function (\w+)\(/gm)].map((m) => m[1]);
  const constNames = [...text.matchAll(/^(?:export )?const (\w+)\b/gm)].map((m) => m[1]);
  const fnSet = new Set(fnNames);
  const constSet = new Set(constNames);
  const functions = new Set();
  const consts = new Set();
  const stack = [...roots];
  while (stack.length > 0) {
    const name = stack.pop();
    let body = null;
    if (fnSet.has(name) && !functions.has(name)) {
      functions.add(name);
      body = extractFunction(text, name);
    } else if (constSet.has(name) && !consts.has(name)) {
      consts.add(name);
      const st = extractConst(text, name);
      body = st !== null && isTable(st) ? null : st;
    }
    if (body === null) continue;
    for (const m of body.matchAll(/\b[A-Za-z_]\w*\b/g)) {
      if ((fnSet.has(m[0]) && !functions.has(m[0])) || (constSet.has(m[0]) && !consts.has(m[0]))) stack.push(m[0]);
    }
  }
  return { functions: fnNames.filter((n) => functions.has(n)), consts: constNames.filter((n) => consts.has(n)) };
}

export function nonBlankLines(text) {
  return String(text)
    .replace(/\r\n/g, '\n')
    .split('\n')
    .filter((l) => l.trim() !== '');
}

export function sha256Lf(text) {
  return crypto.createHash('sha256').update(String(text).replace(/\r\n/g, '\n'), 'utf8').digest('hex');
}

/** The text without the named consts' statements: what a file pin hashes when a table in it may grow. */
export function maskConsts(text, names = []) {
  let out = String(text).replace(/\r\n/g, '\n');
  for (const name of names) {
    const st = extractConst(out, name);
    if (st !== null) out = out.replace(st, () => '');
  }
  return out;
}

// ---------------------------------------------------------------- 6.1 ownership

/** A workstream's paths; {game: id} expands to that game's own paths. */
export function wsPaths(manifest, ws) {
  const w = manifest.workstreams?.[ws];
  if (!w) return [];
  const own = w.game ? gamePaths(w.game) : [];
  return [...own, ...(w.paths ?? [])];
}

/** A game workstream's paths: GAME_PATHS without docs/games/<id>.md, the brief, which is never_edit. */
function gamePaths(id) {
  return gamePathGlobs(id).filter((g) => g !== `docs/games/${id}.md`);
}

/**
 * `check --contributor`: what a pull request may propose and a maintainer alone lands: maintainer-only
 * files and a changed safety-pinned file, which need `pin-safety` and an ADR. The stash rule guards the
 * maintainer's shared worktrees and means nothing in a contributor's clone. Never-edit paths, test
 * counts, locks, added text, a tampered pins file and the line and append-only pins still fail.
 */
export function isMaintainerReview(problem) {
  return /^(ownership: .*: lead only$|safety pin: .* changed \(|stash:)/.test(problem);
}

/** A maintainer-review problem in the words a contributor needs. */
export function contributorWords(problem) {
  return problem
    .replace(/: lead only$/, ': a maintainer lands this file')
    .replace(/only the lead re-pins, tools\/gate pin-safety/, 'a maintainer reads this change and updates the pin');
}

/** The workstream of a branch name: the first branch_ws regex that matches it, else null. */
export function inferWs(branch, manifest) {
  for (const [re, ws] of manifest.branch_ws ?? []) {
    if (new RegExp(re).test(branch)) return ws;
  }
  return null;
}

function otherGame(file, ws, manifest) {
  const mine = manifest.workstreams?.[ws]?.game;
  for (const [name, w] of Object.entries(manifest.workstreams ?? {})) {
    if (w.game && w.game !== mine && matchesAny(file, gamePaths(w.game))) return name;
  }
  return null;
}

/**
 * SPEC_GATES 6.1 over `changes` ([{status, path, oldPath?}]; a rename checks both paths) and
 * `commits` ([{sha, subject, paths}], no merges). `ws` null is ws-less: rules 1 and 2 only. `lead`
 * (a ws-less run on a lead branch: main, queue) drops rule 2, since everything there was landed by
 * the lead. `allow`: the lead's globs, excusing rules 1 and 2. Returns problems[].
 */
export function checkPaths({ changes, commits, manifest, ws, allow = [], lead = false }) {
  const problems = [];
  const w = ws ? manifest.workstreams?.[ws] : null;
  const paths = ws ? wsPaths(manifest, ws) : [];
  const also = w?.also ?? [];
  const game = w?.game ?? null;
  const allPaths = [...new Set(changes.flatMap((c) => (c.oldPath ? [c.oldPath, c.path] : [c.path])))].sort();
  for (const file of allPaths) {
    if (matchesAny(file, manifest.never_edit)) {
      if (!matchesAny(file, allow)) problems.push(`ownership: ${file}: never edited (never_edit)`);
      continue;
    }
    if (matchesAny(file, w?.deny)) {
      if (!matchesAny(file, allow)) problems.push(`ownership: ${file}: denied to workstream ${ws}`);
      continue;
    }
    if (matchesAny(file, manifest.lead_only)) {
      if (!lead && !matchesAny(file, also) && !matchesAny(file, allow)) problems.push(`ownership: ${file}: lead only`);
      if (!matchesAny(file, also)) continue;
    }
    if (!ws) continue;
    if (matchesAny(file, paths) || matchesAny(file, also)) continue;
    const other = otherGame(file, ws, manifest);
    if (other) {
      problems.push(`ownership: ${file}: belongs to game ${other}, outside workstream ${ws}`);
      continue;
    }
    const touching = commits.filter((c) => c.paths.includes(file));
    if (touching.length === 0) {
      problems.push(`ownership: ${file}: outside workstream ${ws} and in no commit (commit it alone, subject "platform: ...")`);
      continue;
    }
    for (const c of touching) {
      if (!c.subject.startsWith('platform:')) {
        problems.push(`ownership: ${file}: outside workstream ${ws}, in ${c.sha.slice(0, 9)} whose subject does not start "platform:"`);
      } else if (game && c.paths.some((p) => matchesAny(p, gamePaths(game)))) {
        problems.push(`ownership: ${file}: ${c.sha.slice(0, 9)} also touches game ${game}; a platform commit stands alone`);
      }
    }
  }
  return problems;
}

// ---------------------------------------------------------------- 6.2, 6.3 pins

/** Is pinnedLines an ordered subsequence of currentLines? problems[] names the first line that is gone. */
export function checkAppendOnly(pinnedLines, currentLines) {
  let at = 0;
  for (let i = 0; i < pinnedLines.length; i += 1) {
    while (at < currentLines.length && currentLines[at] !== pinnedLines[i]) at += 1;
    if (at >= currentLines.length) {
      return [`pinned line ${i + 1} of ${pinnedLines.length} was deleted, altered or moved: ${pinnedLines[i].trim()}`];
    }
    at += 1;
  }
  return [];
}

// What an added line can't hold outside a guarded branch: it would leave the function before a pinned
// line runs, or empty what the pinned lines collected.
const LEAVES_OR_EMPTIES = /\b(?:return|throw)\b|process\.exit|\.length\s*=[^=]|\.(?:splice|pop|shift)\(/;
const GUARD = /^(\s*)if \([\w.?]+ === '([^']+)'/;
const COMMENT = /^\s*(?:\/\/|\/\*.*\*\/\s*$)/;
const PLAIN_PUSH = /^\s*(?:if \([^;{]*\) )?\w+\.push\(.*\);$/;

/** A one-line "probs.push(...)", conditional or not: it adds a problem and changes no control flow. */
function isPlainPush(line) {
  if (!PLAIN_PUSH.test(line) || LEAVES_OR_EMPTIES.test(line)) return false;
  const code = line.replace(/'[^']*'|"[^"]*"|`[^`]*`/g, "''");
  return !/[^=!<>]=[^=>]/.test(code);
}

/**
 * Splits inserted lines into top-level statements by indentation and returns those that are not a branch
 * guarded by a string the pinned body never names: `if (kind === 'repair') ...`. Such a branch can't run for
 * anything the pinned lines already judge, so it may leave.
 */
function badBranches(inserted, pinnedLines, { everyLine }) {
  const bad = [];
  const pinnedText = pinnedLines.join('\n');
  let i = 0;
  while (i < inserted.length) {
    const line = inserted[i];
    const indent = /^\s*/.exec(line)[0].length;
    const guard = GUARD.exec(line);
    let end = i;
    if (/\{\s*$/.test(line)) {
      end = i + 1;
      while (end < inserted.length && !(/^\s*/.exec(inserted[end])[0].length === indent && /^\s*\}/.test(inserted[end]))) end += 1;
    }
    const block = inserted.slice(i, end + 1);
    const guarded = guard && !pinnedText.includes(`'${guard[2]}'`);
    if (!guarded && (everyLine || block.some((l) => LEAVES_OR_EMPTIES.test(l)))) bad.push(line.trim());
    i = end + 1;
  }
  return bad;
}

const stripExport = (line) => line.replace(/^export /, '');

/**
 * An append-only function body. The pinned lines stay in order, so nothing can run before a pinned line
 * that did not run before. What may be added: comments; a one-line `probs.push(...)` anywhere, which only
 * adds a problem; and any lines after the last pinned line of the body, before its final `return` (or
 * closing brace), as long as they do not leave the function or empty what it collected, except in a branch
 * guarded by a new string. `anchors` (trimmed pinned lines, the lead's list) also accept such a branch, and
 * only that, right above them. Returns problems[].
 */
export function checkPinnedBody(pinnedLines, currentLines, { anchors = [] } = {}) {
  const code = (lines) => lines.filter((l) => !COMMENT.test(l)).map((l, i) => (i === 0 ? stripExport(l) : l));
  const pinned = code(pinnedLines);
  const current = code(currentLines);
  const last = pinned.length - 1;
  const tail = last >= 2 && /^ {2}return\b/.test(pinned[last - 1]) ? last - 1 : last;
  const gone = (i) => [`pinned line ${i + 1} of ${pinned.length} was deleted, altered or moved: ${pinned[i].trim()}`];
  let at = 0;
  for (let i = 0; i < pinned.length; i += 1) {
    while (at < current.length && current[at] !== pinned[i] && isPlainPush(current[at])) at += 1;
    if (at < current.length && current[at] === pinned[i]) {
      at += 1;
      continue;
    }
    const next = current.indexOf(pinned[i], at);
    if (next < 0) return gone(i);
    const isAnchor = anchors.includes(pinned[i].trim());
    if (i !== tail && !isAnchor) {
      return [`a line was added above pinned line ${i + 1} of ${pinned.length}: ${current[at].trim()} (added lines go just before the final return; a plain probs.push may go anywhere)`];
    }
    const inserted = current.slice(at, next).filter((l) => !isPlainPush(l));
    const bad = badBranches(inserted, pinned, { everyLine: i !== tail });
    if (bad.length > 0) {
      const what = i === tail ? 'may not leave the function or empty what it collected' : "must be a branch guarded by a string the pinned lines don't name";
      return [`an added line ${what}: ${bad[0]}`];
    }
    at = next + 1;
  }
  if (at !== current.length) return [`lines were added after the closing line: ${current[at].trim()}`];
  return [];
}

function oneLine(statement) {
  return statement.split('\n').map((l) => l.trim()).filter(Boolean).join(' ');
}

/** The top-level entries of a literal's inner text, split on commas outside brackets and strings, trimmed. */
function topLevelEntries(text) {
  const entries = [];
  let depth = 0;
  let quote = null;
  let token = '';
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    if (quote) {
      if (c === quote && text[i - 1] !== '\\') quote = null;
    } else if (c === "'" || c === '"' || c === '`') quote = c;
    else if ('{[('.includes(c)) depth += 1;
    else if ('}])'.includes(c)) depth -= 1;
    else if (c === ',' && depth === 0) {
      entries.push(token.trim());
      token = '';
      continue;
    }
    token += c;
  }
  if (token.trim() !== '') entries.push(token.trim());
  return entries;
}

function tableParts(statement) {
  const text = oneLine(statement);
  const open = text.search(/=\s*[{[]/);
  const at = text.indexOf(text[open + 1] === ' ' ? text[open + 2] : text[open + 1], open);
  return { head: stripExport(text.slice(0, at + 1)), entries: topLevelEntries(text.slice(at + 1, -2)) };
}

const keyOf = (entry) => /^(['"`]?)([^'"`:]+)\1\s*:/.exec(entry)?.[2] ?? null;

/**
 * A pinned const. A table keeps every pinned entry unchanged and may gain others (the layout may change), and
 * an object table never holds a key twice, since the later one would replace the pinned entry. An array table
 * keeps its pinned entries in order. Anything else stays as it was. Returns problems[].
 */
export function checkPinnedConst(pinnedStatement, currentStatement) {
  const pinned = oneLine(pinnedStatement);
  const current = oneLine(currentStatement);
  if (stripExport(pinned) === stripExport(current)) return [];
  if (!isTable(pinnedStatement) || !isTable(currentStatement)) return [`changed: ${pinned.slice(0, 120)}`];
  const was = tableParts(pinnedStatement);
  const now = tableParts(currentStatement);
  if (was.head !== now.head) return [`changed: ${pinned.slice(0, 120)}`];
  if (was.head.endsWith('{')) {
    const keys = now.entries.map(keyOf);
    const twice = keys.find((k, i) => k !== null && keys.indexOf(k) !== i);
    if (twice) return [`a new entry replaces the pinned key ${twice}`];
    const lost = was.entries.find((e) => !now.entries.includes(e));
    return lost ? [`a pinned entry was deleted or altered: ${lost}`] : [];
  }
  const missing = checkAppendOnly(was.entries, now.entries);
  return missing.length ? [`a pinned entry was deleted, altered or moved: ${missing[0]}`] : [];
}

/** Lines elsewhere in the file that change a pinned table at run time. */
function tableMutations(text, name) {
  const re = new RegExp(`\\b${name}(?:\\.\\w+|\\[[^\\]]*\\])\\s*=[^=>]|\\bdelete\\s+${name}\\b|\\b${name}\\.(?:splice|pop|shift|length\\s*=[^=])|Object\\.assign\\(${name}\\b`);
  return String(text).split('\n').filter((l) => re.test(l)).map((l) => l.trim());
}

const importsFrom = (text, name, moved) => new RegExp(`^import \\{[^}]*\\b${name}\\b[^}]*\\} from '[^']*${moved.split('/').pop().replace('.', '\\.')}';`, 'm').test(String(text).replace(/\r\n/g, '\n'));

/** The pins' content against the tree, for the entries given. */
export function checkPinContent({ pins, read, allowPins = [] }) {
  const problems = [];
  const files = Object.keys(pins.files ?? {});
  for (const glob of pins.globs ?? []) {
    if (!files.some((f) => globToRegExp(glob).test(f))) problems.push(`safety pin: the glob ${glob} matches nothing`);
  }
  for (const file of files) {
    const text = read(file);
    if (text === null || text === undefined) problems.push(`safety pin: ${file} is gone`);
    else if (sha256Lf(maskConsts(text, pins.masked?.[file])) !== pins.files[file]) problems.push(`safety pin: ${file} changed (BRIEF 4.6, BRIEF 7: only the lead re-pins, tools/gate pin-safety)`);
  }
  for (const entry of pins.lines ?? []) {
    const text = read(entry.file);
    if (text === null || text === undefined) {
      problems.push(`line pin: ${entry.file} is gone`);
      continue;
    }
    for (const p of checkAppendOnly(entry.lines, nonBlankLines(text))) problems.push(`line pin: ${entry.file}: ${p}`);
  }
  for (const block of pins.blocks ?? []) {
    if (allowPins.includes(`${block.file}:${block.function}`)) continue;
    const text = read(block.file);
    if (text === null || text === undefined) {
      problems.push(`append-only pin: ${block.file} is gone`);
      continue;
    }
    let fn = extractFunction(text, block.function);
    if (fn === null && block.moved && importsFrom(text, block.function, block.moved)) {
      const home = read(block.moved);
      fn = home === null || home === undefined ? null : extractFunction(home, block.function);
    }
    if (fn === null) {
      problems.push(`append-only pin: ${block.file}: function ${block.function} is gone`);
      continue;
    }
    for (const p of checkPinnedBody(block.lines, nonBlankLines(fn), { anchors: block.anchors })) problems.push(`append-only pin: ${block.file}: ${block.function}: ${p}`);
  }
  for (const c of pins.consts ?? []) {
    if (allowPins.includes(`${c.file}:${c.name}`)) continue;
    const text = read(c.file);
    if (text === null || text === undefined) {
      problems.push(`append-only pin: ${c.file} is gone`);
      continue;
    }
    const st = extractConst(text, c.name);
    if (st === null) {
      if (c.moved && importsFrom(text, c.name, c.moved)) continue;
      problems.push(`append-only pin: ${c.file}: const ${c.name} is gone`);
      continue;
    }
    for (const p of checkPinnedConst(c.statement, st)) problems.push(`append-only pin: ${c.file}: ${c.name}: ${p}`);
    if (isTable(c.statement)) for (const l of tableMutations(text, c.name)) problems.push(`append-only pin: ${c.file}: ${c.name} is changed at run time: ${l}`);
  }
  return problems;
}

/**
 * tools/lib/safety_pins.json against the tree. `pins`: { globs, files: {path: sha256}, masked, lines, blocks,
 * consts }. `read(path)` returns the content or null. `allowPins` holds the lead's "<file>:<name>" exceptions
 * for blocks and consts. A pins file that pins nothing is a problem. Returns problems[].
 */
export function checkPins({ pins, read, allowPins = [] }) {
  const empty = Object.keys(pins?.files ?? {}).length === 0 && (pins?.blocks ?? []).length === 0 && (pins?.globs ?? []).length === 0;
  if (empty) return ['safety pin: the pins file pins nothing'];
  return checkPinContent({ pins, read, allowPins });
}

/** What the manifest asks to pin, for computePins. */
export function pinSpecOf(manifest) {
  return {
    globs: manifest.safety_pin_globs ?? [],
    except: manifest.safety_pin_except ?? {},
    lines: manifest.safety_pin_lines ?? {},
    appendOnly: manifest.append_only_pins ?? {},
    tables: manifest.append_only_tables ?? {},
    anchors: manifest.append_only_anchors ?? {},
    moves: manifest.append_only_moves ?? {},
  };
}

/** True when the manifest asks for any pin at all. */
export function manifestPins(manifest) {
  const s = pinSpecOf(manifest);
  return s.globs.length > 0 || Object.keys(s.appendOnly).length > 0;
}

/**
 * Writes the pins of a tree. `read(path)` as above; `tracked`: every tracked path. `appendOnly` names root
 * functions: what they rest on (pinClosure) is pinned with them. `tables` names consts pinned on their own.
 * Throws on a glob, file, function, const or line that finds nothing.
 */
export function computePins({ globs = [], except = {}, lines = {}, appendOnly = {}, tables = {}, anchors = {}, moves = {}, tracked, read }) {
  const files = {};
  for (const glob of globs) {
    const re = globToRegExp(glob);
    const hits = tracked.filter((f) => re.test(f));
    if (hits.length === 0) throw new Error(`the glob ${glob} matches nothing`);
    for (const f of hits) files[f] = sha256Lf(maskConsts(read(f), except[f]));
  }
  const lineEntries = [];
  for (const [file, wanted] of Object.entries(lines)) {
    const text = read(file);
    if (text === null || text === undefined) throw new Error(`${file} does not exist`);
    const problems = checkAppendOnly(wanted, nonBlankLines(text));
    if (problems.length > 0) throw new Error(`${file}: ${problems[0]}`);
    lineEntries.push({ file, lines: wanted });
  }
  const blocks = [];
  const consts = [];
  const pinConst = (file, text, name) => {
    const statement = extractConst(text, name);
    if (statement === null) throw new Error(`${file} has no const ${name}`);
    consts.push({ file, name, statement, ...(moves[name] ? { moved: moves[name] } : {}) });
  };
  for (const [file, names] of Object.entries(appendOnly)) {
    const text = read(file);
    if (text === null || text === undefined) throw new Error(`${file} does not exist`);
    for (const name of names) {
      if (extractFunction(text, name) === null) throw new Error(`${file} has no function ${name}`);
    }
    const closure = pinClosure(text, names);
    for (const name of closure.functions) {
      const fn = extractFunction(text, name);
      if (fn === null) continue;
      const want = anchors[file]?.[name] ?? [];
      const pinnedLines = nonBlankLines(fn);
      for (const a of want) if (!pinnedLines.some((l) => l.trim() === a)) throw new Error(`${file}: ${name} has no anchor line "${a}"`);
      blocks.push({ file, function: name, lines: pinnedLines, ...(want.length ? { anchors: want } : {}), ...(moves[name] ? { moved: moves[name] } : {}) });
    }
    for (const name of closure.consts) pinConst(file, text, name);
  }
  for (const [file, names] of Object.entries(tables)) {
    const text = read(file);
    if (text === null || text === undefined) throw new Error(`${file} does not exist`);
    for (const name of names) {
      if (!consts.some((c) => c.file === file && c.name === name)) pinConst(file, text, name);
    }
  }
  const sorted = {};
  for (const f of Object.keys(files).sort()) sorted[f] = files[f];
  const masked = Object.fromEntries(Object.entries(except).filter(([f]) => f in files));
  return { globs, files: sorted, ...(Object.keys(masked).length ? { masked } : {}), ...(lineEntries.length ? { lines: lineEntries } : {}), blocks, ...(consts.length ? { consts } : {}) };
}

/**
 * Do the pins hold everything the manifest asks for, with the values of the commit they say they were
 * taken at? This is what stops a hollowed or hand-edited pins file: `{"files":{}}`, a glob dropped, a hash
 * rewritten. `tracked` and `read` are that commit's. New files under a glob since then stay unpinned until
 * the next pin-safety; that strengthens, so it is no problem. Returns problems[].
 */
export function checkPinCoverage({ pins, manifest, tracked, read }) {
  let fresh;
  try {
    fresh = computePins({ ...pinSpecOf(manifest), tracked, read });
  } catch (err) {
    return [`safety pin: the manifest asks for what the pins at ${String(pins.pinned_at).slice(0, 9)} can't hold (${err.message}): the lead re-pins, tools/gate pin-safety`];
  }
  const problems = [];
  const missing = (what) => problems.push(`safety pin: the pins file lacks or altered ${what} (hollowed? only tools/gate pin-safety writes it)`);
  for (const glob of fresh.globs) if (!(pins.globs ?? []).includes(glob)) missing(`the manifest glob ${glob}`);
  for (const [f, sha] of Object.entries(fresh.files)) if (pins.files?.[f] !== sha) missing(`the file pin ${f}`);
  for (const f of Object.keys(fresh.masked ?? {})) if (JSON.stringify(pins.masked?.[f]) !== JSON.stringify(fresh.masked[f])) missing(`the mask of ${f}`);
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  for (const e of fresh.lines ?? []) if (!(pins.lines ?? []).some((p) => same(p, e))) missing(`the line pin ${e.file}`);
  for (const b of fresh.blocks) if (!(pins.blocks ?? []).some((p) => same(p, b))) missing(`the block ${b.file}:${b.function}`);
  for (const c of fresh.consts ?? []) if (!(pins.consts ?? []).some((p) => same(p, c))) missing(`the const ${c.file}:${c.name}`);
  return problems;
}

// ---------------------------------------------------------------- 6.4 test counts

function testArea(file) {
  const parts = file.split('/');
  if (parts[0] !== 'tests') return null;
  if (parts[1] === 'games' && parts.length >= 4) return `tests/games/${parts[2]}`;
  if (parts.length >= 3) return `tests/${parts[1]}`;
  return 'tests';
}

/** Test-Removal: <area> <reason> trailers of a commit message: [{area, reason}]. */
export function parseTestRemovals(message) {
  const out = [];
  for (const m of String(message).matchAll(/^Test-Removal:[ \t]+(\S+)[ \t]+(\S.*)$/gm)) out.push({ area: m[1], reason: m[2].trim() });
  return out;
}

/**
 * Per-file test counts at the merge base and at HEAD. `baseFiles`, `headFiles`: {path: source}. Only what
 * GUT collects counts (isGutFile), so renaming a file out of test_*.gd loses its tests here too.
 * `trailers`: parseTestRemovals. `revertOnly`: every commit in the range is the revert of a merge
 * (SPEC_GATES 3), which still answers to the floor. Returns { problems, notes }.
 */
export function checkTestCounts({ baseFiles, headFiles, trailers = [], revertOnly = false }) {
  const problems = [];
  const notes = [];
  const area = new Map();
  const bump = (file, key, n) => {
    const a = testArea(file);
    if (a === null) return;
    if (!area.has(a)) area.set(a, { baseTests: 0, headTests: 0, baseAsserts: 0, headAsserts: 0 });
    area.get(a)[key] += n;
  };
  let baseTotal = 0;
  let headTotal = 0;
  const collected = (files) => Object.entries(files).filter(([f]) => isGutFile(f));
  for (const [file, src] of collected(baseFiles)) {
    const n = countTests(src);
    baseTotal += n;
    bump(file, 'baseTests', n);
    bump(file, 'baseAsserts', countAsserts(src));
    const now = headFiles[file] === undefined ? 0 : countTests(headFiles[file]);
    if (now < n) notes.push(`tests: ${file} lost tests: ${n} -> ${now}`);
  }
  for (const [file, src] of collected(headFiles)) {
    const n = countTests(src);
    headTotal += n;
    bump(file, 'headTests', n);
    bump(file, 'headAsserts', countAsserts(src));
  }
  if (headTotal < baseTotal) {
    if (revertOnly) notes.push(`tests: the total fell ${baseTotal} -> ${headTotal} in a merge revert; the floor still applies`);
    else problems.push(`tests: the total fell ${baseTotal} -> ${headTotal}`);
  }
  for (const a of [...area.keys()].sort()) {
    const c = area.get(a);
    if (c.headTests < c.baseTests) {
      const excuse = trailers.find((t) => t.area === a);
      if (excuse) notes.push(`tests: ${a} fell ${c.baseTests} -> ${c.headTests}, Test-Removal: ${excuse.reason}`);
      else if (!revertOnly) problems.push(`tests: ${a} fell ${c.baseTests} -> ${c.headTests} with no "Test-Removal: ${a} <reason>" trailer`);
    }
    if (c.baseAsserts > 0 && c.headAsserts < c.baseAsserts * 0.9) notes.push(`tests: ${a} asserts fell over 10 %: ${c.baseAsserts} -> ${c.headAsserts}`);
  }
  return { problems, notes };
}

/** The sha of a `git revert` message's "This reverts commit <sha>", or null. */
export function revertedSha(message) {
  return /^This reverts commit ([0-9a-f]{7,64})\b/m.exec(String(message))?.[1] ?? null;
}

/**
 * The Node side of the test-total rule, over the files `node --test` runs at the merge base and at HEAD.
 * `baseFiles`, `headFiles`: {path: source}. `suiteOf(file)` names a file's suite. The total may fall only in
 * a merge revert or with a `Test-Removal: node <reason>` trailer, and a suite that held tests and holds none
 * needs `Test-Removal: <suite> <reason>`, since run_tests reads an empty suite as SKIP. Any other suite that
 * shrinks is a note: tests move between suites. Returns { problems, notes }.
 */
export function checkNodeTestCounts({ baseFiles, headFiles, suiteOf, trailers = [], revertOnly = false }) {
  const problems = [];
  const notes = [];
  const tally = (files) => {
    const bySuite = new Map();
    let total = 0;
    for (const [file, src] of Object.entries(files)) {
      const n = countNodeTests(src);
      total += n;
      const suite = suiteOf(file);
      bySuite.set(suite, (bySuite.get(suite) ?? 0) + n);
    }
    return { total, bySuite };
  };
  const base = tally(baseFiles);
  const head = tally(headFiles);
  if (head.total < base.total) {
    const excuse = trailers.find((t) => t.area === 'node');
    if (revertOnly) notes.push(`tests: the Node total fell ${base.total} -> ${head.total} in a merge revert`);
    else if (excuse) notes.push(`tests: the Node total fell ${base.total} -> ${head.total}, Test-Removal: ${excuse.reason}`);
    else problems.push(`tests: the Node total fell ${base.total} -> ${head.total} with no "Test-Removal: node <reason>" trailer`);
  }
  for (const [suite, was] of [...base.bySuite].sort()) {
    const now = head.bySuite.get(suite) ?? 0;
    if (now >= was) continue;
    const excuse = trailers.find((t) => t.area === suite);
    if (now === 0 && !excuse && !revertOnly) problems.push(`tests: the Node suite ${suite} held ${was} tests and holds none, with no "Test-Removal: ${suite} <reason>" trailer`);
    else notes.push(`tests: the Node suite ${suite} fell ${was} -> ${now}`);
  }
  return { problems, notes };
}

// ---------------------------------------------------------------- 6.4, 6.5 added text

/** Added lines per file from `git diff -U0 --src-prefix=a/ --dst-prefix=b/`: Map path -> string[] (a CR stays on its line). */
export function parseAddedLines(diffText) {
  const out = new Map();
  let current = null;
  let removedLeft = 0;
  let addedLeft = 0;
  for (const line of String(diffText).split('\n')) {
    // The hunk header's counts say what is content, so an added "++ x" never reads as a file header.
    if (removedLeft > 0 || addedLeft > 0) {
      if (line.startsWith('-')) removedLeft -= 1;
      else if (line.startsWith('+')) {
        addedLeft -= 1;
        if (current !== null) out.get(current).push(line.slice(1));
      }
      continue;
    }
    const hunk = /^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@/.exec(line);
    if (hunk) {
      removedLeft = hunk[1] === undefined ? 1 : Number(hunk[1]);
      addedLeft = hunk[2] === undefined ? 1 : Number(hunk[2]);
    } else if (line.startsWith('+++ ')) {
      let name = line.slice(4).replace(/\t.*$/, '').replace(/\r$/, '');
      if (name.startsWith('"') && name.endsWith('"')) name = name.slice(1, -1);
      current = name.startsWith('b/') ? name.slice(2) : null;
      if (current !== null && !out.has(current)) out.set(current, []);
    } else if (line.startsWith('diff --git ')) current = null;
  }
  return out;
}

const CODE_TYPES = /\.(sh|ps1|mjs|py|gd|yml)$/;
const FLAG_EXEMPT = ['tools/tests/**', 'tools/e2e/test/**', 'tools/lib/gate*'];
const ART_EXEMPT = [...FLAG_EXEMPT, 'tools/art/**'];
const CR_EXEMPT = /\.(ps1|bat|cmd)$/;

function isCodeFile(file) {
  // The extension-less tools (tools/run_game_sim, tools/gate) are bash scripts.
  return CODE_TYPES.test(file) || /^tools\/[^/.]+$/.test(file);
}

/**
 * The text rules over added lines. `added`: parseAddedLines (of the committed and the tracked
 * uncommitted diff). `untracked`: the same shape for untracked files, which skip the CR rule, since
 * .gitattributes normalises them on add. Returns problems[].
 */
export function checkAddedText({ added, untracked = new Map(), quietTests = [] }) {
  const problems = [];
  const scan = (file, lines, withCr) => {
    const isTestGd = /^tests\/.*\.gd$/.test(file);
    for (const line of lines) {
      if (isCodeFile(file) && !matchesAny(file, FLAG_EXEMPT) && /--allow-(hw|network)\b/.test(line)) {
        problems.push(`locks: ${file}: an added line holds --allow-hw or --allow-network: ${line.trim()}`);
      }
      if (isCodeFile(file) && !matchesAny(file, ART_EXEMPT) && /WATTLANDS_ALLOW_ART=1|FAL_KEY=/.test(line)) {
        problems.push(`locks: ${file}: an added line sets WATTLANDS_ALLOW_ART or FAL_KEY`);
      }
      if (isTestGd && /assert_true\(true|assert_eq\(1, *1/.test(line)) problems.push(`tests: ${file}: an empty assert was added: ${line.trim()}`);
      if (isTestGd && /Time\.get_ticks_usec/.test(line) && !matchesAny(file, quietTests)) {
        problems.push(`tests: ${file}: Time.get_ticks_usec outside quiet_tests (new budget tests go in tests/games/<id>/perf/)`);
      }
      if (withCr && line.endsWith('\r') && !CR_EXEMPT.test(file)) {
        problems.push(`text: ${file}: added text holds CR (gdformat on Windows? tools/gate fmt converts)`);
        break;
      }
    }
  };
  for (const [file, lines] of added) scan(file, lines, true);
  for (const [file, lines] of untracked) scan(file, lines, false);
  return problems;
}

// ---------------------------------------------------------------- 6.5 sidecars and class names

const IMPORTED = /\.(png|wav|ogg|ttf|mp3)$/;

function underIgnored(file, gdignoreDirs) {
  const parts = file.split('/');
  for (let i = 0; i < parts.length - 1; i += 1) {
    if (parts[i].startsWith('.')) return true; // Godot never scans a hidden dir (.github, .claude).
    if (gdignoreDirs.has(parts.slice(0, i + 1).join('/'))) return true;
  }
  return gdignoreDirs.has('');
}

/**
 * `added` and `deleted`: this diff's paths (a rename is both). `current`: every path in the tree now.
 * Added .gd needs its .gd.uid, added media its .import; a new sidecar needs its source; a source this
 * diff deleted takes its sidecar with it. Paths under a tracked .gdignore are exempt. Returns problems[].
 */
export function checkSidecars({ added, deleted, current }) {
  const problems = [];
  const now = current instanceof Set ? current : new Set(current);
  const gdignoreDirs = new Set();
  for (const f of now) {
    if (f === '.gdignore') gdignoreDirs.add('');
    else if (f.endsWith('/.gdignore')) gdignoreDirs.add(f.slice(0, -'/.gdignore'.length));
  }
  for (const f of added) {
    if (underIgnored(f, gdignoreDirs) || !now.has(f)) continue;
    if (f.endsWith('.gd') && !now.has(`${f}.uid`)) problems.push(`sidecar: ${f} was added without ${f}.uid`);
    if (IMPORTED.test(f) && !now.has(`${f}.import`)) problems.push(`sidecar: ${f} was added without ${f}.import`);
    const side = /^(.+)\.(uid|import)$/.exec(f);
    if (side && !now.has(side[1])) problems.push(`sidecar: ${f} was added with no ${side[1]}`);
  }
  for (const f of deleted) {
    if (now.has(f)) continue;
    for (const ext of f.endsWith('.gd') ? ['.uid'] : IMPORTED.test(f) ? ['.import'] : []) {
      if (now.has(f + ext)) problems.push(`sidecar: ${f} was deleted but ${f}${ext} stays`);
    }
  }
  return problems;
}

/** `git grep -n` lines of class_name declarations ("path:line:class_name X"); problems[] for a name in two files. */
export function checkClassNames(grepLines) {
  const where = new Map();
  for (const line of grepLines) {
    const m = /^(.+?):\d+:class_name\s+([A-Za-z_]\w*)/.exec(line);
    if (!m) continue;
    if (!where.has(m[2])) where.set(m[2], new Set());
    where.get(m[2]).add(m[1]);
  }
  const problems = [];
  for (const [name, files] of [...where.entries()].sort()) {
    if (files.size > 1) problems.push(`class_name: ${name} is declared in ${[...files].sort().join(', ')}`);
  }
  return problems;
}

// ---------------------------------------------------------------- matrix plan

/** Plan-capture lines (arguments joined by 0x1f) to argument arrays, keeping the first line per --report. */
export function parsePlan(text) {
  const out = [];
  const seen = new Set();
  for (const line of String(text).split(/\r?\n/)) {
    if (line === '') continue;
    const args = line.split('\x1f').filter((a) => a !== '');
    const report = args.find((a) => a.startsWith('--report='));
    if (report && seen.has(report)) continue;
    if (report) seen.add(report);
    out.push(args);
  }
  return out;
}
