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

/**
 * `check --contributor`: what a pull request may propose and a maintainer alone lands: maintainer-only
 * files and safety pins, which need `pin-safety` and an ADR. The stash rule guards the maintainer's
 * shared worktrees and means nothing in a contributor's clone. Never-edit paths, test counts, locks
 * and added text still fail.
 */
export function isMaintainerReview(problem) {
  return /^(ownership: .*: lead only$|safety pin|line pin|append-only pin|stash:)/.test(problem);
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
