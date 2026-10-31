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

/** tests/<...>/test_*.gd holding at least one test function, sorted, forward slashes. */
export function listGutFiles(projectDir) {
  const out = [];
  const walk = (dir, rel) => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue;
      const childRel = `${rel}/${e.name}`;
      if (e.isDirectory()) walk(path.join(dir, e.name), childRel);
      else if (/^test_.*\.gd$/.test(e.name) && /^\s*func test_/m.test(fs.readFileSync(path.join(dir, e.name), 'utf8'))) {
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

/** The content of tools/lib/gate_weights.json: {group: seconds}, sorted, for stable diffs. */
export function weightsByGroup(fileWeights) {
  const sum = new Map();
  for (const [file, seconds] of fileWeights) {
    const g = groupKey(file);
    sum.set(g, (sum.get(g) ?? 0) + seconds);
  }
  const out = {};
  for (const g of [...sum.keys()].sort()) out[g] = Math.round(sum.get(g) * 10) / 10;
  return out;
}

const NO_DATA_S_PER_FILE = 2;

/**
 * Longest group first into the lightest shard, ties by name. A group never splits, so every writer
 * of one res://build/<dir> stays in one process. `pins` (arrays of groups) forces groups together.
 * Files matching `quiet` (globs) come back apart. Empty shards are dropped.
 * Returns { shards: string[][], quiet: string[] }; throws unless they partition `files` exactly.
 */
export function planShards(files, groupWeights, { shards = 8, quiet = [], pins = [] } = {}) {
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
  for (const g of groups.keys()) {
    if (!taken.has(g)) bundles.push({ name: g, files: groups.get(g), weight: weightOf(g) });
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

// ---------------------------------------------------------------- touched games

/**
 * Which games a change set touches. docs/**, *.md and workflows other than game-<id>.yml touch
 * nothing, checked first; a game's own paths touch that game; anything else, _template included,
 * sets `platform` and selects every registered game. Returns { games, platform }.
 */
export function touchedGames(changedPaths, registeredIds) {
  const ids = new Set(registeredIds);
  const games = new Set();
  let platform = false;
  for (const p of changedPaths) {
    const wf = /^\.github\/workflows\/([^/]+)$/.exec(p);
    const gameWf = wf && /^game-(.+)\.ya?ml$/.exec(wf[1]);
    if (p.startsWith('docs/') || p.endsWith('.md') || (wf && !gameWf)) continue;
    const own = /^(?:src\/games|content|assets|tests\/games)\/([^/]+)\//.exec(p);
    const id = gameWf ? gameWf[1] : own ? own[1] : null;
    if (id !== null && ids.has(id)) games.add(id);
    else platform = true;
  }
  return { games: platform ? [...ids].sort() : [...games].sort(), platform };
}

// ---------------------------------------------------------------- GUT verdicts

function junitSuiteNames(xml) {
  const out = [];
  for (const m of String(xml ?? '').matchAll(/<testsuite\b[^>]*>/g)) {
    const name = /\bname="([^"]*)"/.exec(m[0]);
    if (name) out.push(name[1]);
  }
  return out;
}

/**
 * The verdict over all shards. `results`: one { name, junitXml, ...evaluateGut output } per process.
 * Fails on any failed shard, a file of `expectedFiles` in no JUnit, a file in two JUnits, and a
 * total below `floor` (null: no floor). Returns { pass, total, reasons }.
 */
export function aggregateGut(results, { floor = null, expectedFiles = [] } = {}) {
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
  if (Number.isInteger(floor) && floor > 0 && total < floor) reasons.push(`the shards ran ${total} tests, fewer than the floor ${floor}`);
  return { pass: reasons.length === 0, total, reasons };
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

// ---------------------------------------------------------------- source scans

export function countTests(src) {
  return (String(src).match(/^\s*func test_/gm) || []).length;
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

export function nonBlankLines(text) {
  return String(text)
    .replace(/\r\n/g, '\n')
    .split('\n')
    .filter((l) => l.trim() !== '');
}

export function sha256Lf(text) {
  return crypto.createHash('sha256').update(String(text).replace(/\r\n/g, '\n'), 'utf8').digest('hex');
}

// ---------------------------------------------------------------- 6.1 ownership

/** A workstream's paths; {game: id} expands to that game's own paths. */
export function wsPaths(manifest, ws) {
  const w = manifest.workstreams?.[ws];
  if (!w) return [];
  const own = w.game ? gamePaths(w.game) : [];
  return [...own, ...(w.paths ?? [])];
}

function gamePaths(id) {
  return [
    `src/games/${id}/**`,
    `content/${id}/**`,
    `assets/${id}/**`,
    `tests/games/${id}/**`,
    `.github/workflows/game-${id}.yml`,
    `docs/decisions/${id}.md`,
    `docs/credits.d/${id}.md`,
    `docs/changelog.d/${id}.md`,
  ];
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

/**
 * tools/lib/safety_pins.json against the tree. `pins`: { globs, files: {path: sha256}, blocks:
 * [{file, function, lines}] }. `read(path)` returns the content or null. `allowPins` holds the lead's
 * "<file>:<function>" exceptions for blocks. Returns problems[].
 */
export function checkPins({ pins, read, allowPins = [] }) {
  const problems = [];
  const files = Object.keys(pins.files ?? {});
  for (const glob of pins.globs ?? []) {
    if (!files.some((f) => globToRegExp(glob).test(f))) problems.push(`safety pin: the glob ${glob} matches nothing`);
  }
  for (const file of files) {
    const text = read(file);
    if (text === null || text === undefined) problems.push(`safety pin: ${file} is gone`);
    else if (sha256Lf(text) !== pins.files[file]) problems.push(`safety pin: ${file} changed (BRIEF 4.6, BRIEF 7: only the lead re-pins, tools/gate pin-safety)`);
  }
  for (const block of pins.blocks ?? []) {
    if (allowPins.includes(`${block.file}:${block.function}`)) continue;
    const text = read(block.file);
    if (text === null || text === undefined) {
      problems.push(`append-only pin: ${block.file} is gone`);
      continue;
    }
    const fn = extractFunction(text, block.function);
    if (fn === null) {
      problems.push(`append-only pin: ${block.file}: function ${block.function} is gone`);
      continue;
    }
    for (const p of checkAppendOnly(block.lines, nonBlankLines(fn))) problems.push(`append-only pin: ${block.file}: ${block.function}: ${p}`);
  }
  return problems;
}

/** Writes the pins of the current tree. `read(path)` as above; `tracked`: every tracked path. Throws on a glob or function that finds nothing. */
export function computePins({ globs, appendOnly, tracked, read }) {
  const files = {};
  for (const glob of globs) {
    const re = globToRegExp(glob);
    const hits = tracked.filter((f) => re.test(f));
    if (hits.length === 0) throw new Error(`the glob ${glob} matches nothing`);
    for (const f of hits) files[f] = sha256Lf(read(f));
  }
  const blocks = [];
  for (const [file, names] of Object.entries(appendOnly ?? {})) {
    const text = read(file);
    if (text === null || text === undefined) throw new Error(`${file} does not exist`);
    for (const name of names) {
      const fn = extractFunction(text, name);
      if (fn === null) throw new Error(`${file} has no function ${name}`);
      blocks.push({ file, function: name, lines: nonBlankLines(fn) });
    }
  }
  const sorted = {};
  for (const f of Object.keys(files).sort()) sorted[f] = files[f];
  return { globs, files: sorted, blocks };
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
 * Per-file test counts at the merge base and at HEAD. `baseFiles`, `headFiles`: {path: source} of
 * tests/**.gd. `trailers`: parseTestRemovals. `revertOnly`: every commit in the range is the revert
 * of a merge (SPEC_GATES 3), which still answers to the floor. Returns { problems, notes }.
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
  for (const [file, src] of Object.entries(baseFiles)) {
    const n = countTests(src);
    baseTotal += n;
    bump(file, 'baseTests', n);
    bump(file, 'baseAsserts', countAsserts(src));
    const now = headFiles[file] === undefined ? 0 : countTests(headFiles[file]);
    if (now < n) notes.push(`tests: ${file} lost tests: ${n} -> ${now}`);
  }
  for (const [file, src] of Object.entries(headFiles)) {
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
