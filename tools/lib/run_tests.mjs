#!/usr/bin/env node
// tools/lib/run_tests.mjs: the gate runner behind tools/run_tests (bash) and tools/run_tests.ps1.
// Zero dependencies, Node 22.12+. Both shims call this file, so the two runners behave identically;
// the bash shim runs Godot through tools/godot.sh, the PowerShell shim through tools/godot.ps1.
//
//   tools/run_tests [--only=<step,...>] [--skip=<step,...>] [--min-count=<n>] [--gdir=<res path>]
//                   [--gut-arg=<arg>]... [--no-lint] [--project=<dir>]
//
// Steps run in STEPS order. To add a step (BRIEF 7.3 scaffold check, simulation, FIT, e2e), fill in
// its function below; it returns {status: 'PASS'|'FAIL'|'SKIP'|'WARN', note}. Only FAIL fails the run.

import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { killTree } from './godot_lock.mjs';
import { evaluateGut, readGreenCount, writeGreenCount, readPendingAllowlist, FORBIDDEN } from './gut_gate.mjs';
import { globToRegExp } from './gate_core.mjs';

const LIB = path.dirname(fileURLToPath(import.meta.url));
const TOOLS = path.dirname(LIB);
const REPO = path.dirname(TOOLS);

const STEP_NAMES = ['import', 'gut', 'scaffold', 'static', 'sim', 'fit', 'node', 'e2e'];
const LINT_DIRS = ['addons/wattlands', 'src', 'tests', 'tools'];
export const NODE_SUITES = ['tools/tests', 'server/relay', 'server/mock_strava', 'tools/art', 'tools/audio', 'tools/fit_check', 'tools/e2e'];
// Suites with a package-lock.json get `npm ci` first when their node_modules is missing; a failed
// install is reported and the suite runs anyway (the relay and fit_check have zero-dependency
// fallbacks, BRIEF 5.3, 3.8).
const NPM_DIRS = ['server/relay', 'tools/fit_check'];
// Extra Node commands run after the suites, from the project root (each may start Godot through
// the wrapper itself, one slot at a time).
const NODE_EXTRA = [['tools/art/pixelate_e2e.mjs']];
const SIM_SPEED = 2000;
const SIM_TIMEOUT_S = 900;
// The full GUT run's wrapper timeout (the wrapper default is 1200 s; Linux CI took 675 s at 2720
// tests, and every game adds its own).
const GUT_TIMEOUT_S = 3600;
const SCAFFOLD_TIMEOUT_S = 1800;
const E2E_TIMEOUT_S = 3600;
const NODE_SUITE_TIMEOUT_S = 1800;
const NESTED_ENV = 'WATTLANDS_RUN_TESTS_NESTED';
const ART_VARS = ['FAL_KEY', 'WATTLANDS_ALLOW_ART'];

const USAGE = `usage: tools/run_tests [options]      (tools/run_tests.ps1 in PowerShell)
  --only=<step,...>    run only these steps (${STEP_NAMES.join(', ')})
  --skip=<step,...>    skip these steps
  --min-count=<n>      required GUT test count instead of the previous green count
  --gdir=<res path>    narrower GUT run (default res://tests); does not compare or update the green count
  --gut-arg=<arg>      extra GUT argument (repeatable); also makes the run narrow
  --no-lint            skip gdlint / gdformat --check (otherwise any finding fails the static step
                       whenever gdtoolkit is available; gdlint reads ./gdlintrc)
  --strict-lint        no-op, kept for compatibility (lint is always fatal)
  --project=<dir>      project root (default: this checkout)
  --games=<id,...>     sim and e2e: only these registered games
  --sim-outer-timeout=<s>  sim: the timer on one run, lock wait included (default ${SIM_TIMEOUT_S})
  --sim-jobs=<n>       sim: run up to n tools/run_game_sim runs at once, each still through the
                       machine-wide Godot lock (default 1, one after another)
  --node-jobs=<n>      node: run up to n suites at once, each quiet with its own log (default 1)
  --node-since=<rev>   node: only the suites a change since <rev> can affect (NODE_SUITE_GAME_INPUTS);
                       a path outside one game's own folders runs them all (default: all)
  --node-cache         node: let suites keep verdict caches under build/test_cache (default off)
  --static-jobs=<n>    static: check_scripts, gdlint, gdformat and the workflow check at once, with
                       gdlint and gdformat each split over n processes (default 1, one after another)`;

// ---------------------------------------------------------------- options

function fail(msg) {
  process.stderr.write(`run_tests: ${msg}\n${USAGE}\n`);
  process.exit(2);
}

export function parseArgs(argv) {
  const o = {
    only: null,
    skip: [],
    minCount: null,
    gdir: null,
    gutArgs: [],
    noLint: false,
    project: REPO,
    shell: process.platform === 'win32' ? 'ps' : 'bash',
    games: null,
    simOuterS: SIM_TIMEOUT_S,
    simJobs: 1,
    nodeJobs: 1,
    nodeSince: null,
    nodeCache: false,
    staticJobs: 1,
  };
  const jobs = (key, val) => {
    const n = Number(val);
    if (!Number.isInteger(n) || n < 1 || n > 64) fail(`${key} needs an integer 1..64, got "${val}"`);
    return n;
  };
  const list = (v) => v.split(',').map((s) => s.trim()).filter(Boolean);
  for (const a of argv) {
    const eq = a.indexOf('=');
    const key = eq >= 0 ? a.slice(0, eq) : a;
    const val = eq >= 0 ? a.slice(eq + 1) : null;
    if (key === '--help' || key === '-h') {
      process.stdout.write(`${USAGE}\n`);
      process.exit(0);
    } else if (key === '--only' && val !== null) o.only = list(val);
    else if (key === '--skip' && val !== null) o.skip = list(val);
    else if (key === '--min-count' && val !== null) {
      const n = Number(val);
      if (!Number.isInteger(n) || n < 0) fail(`--min-count needs an integer >= 0, got "${val}"`);
      o.minCount = n;
    } else if (key === '--gdir' && val) o.gdir = val;
    else if (key === '--gut-arg' && val) o.gutArgs.push(val);
    else if (key === '--strict-lint' && val === null) {
      // No-op since lint became part of the gate (docs/decisions/lead.md, 2026-10-21).
    }
    else if (key === '--no-lint' && val === null) o.noLint = true;
    else if (key === '--project' && val) o.project = path.resolve(val);
    else if (key === '--shell' && (val === 'bash' || val === 'ps')) o.shell = val;
    else if (key === '--games' && val) o.games = list(val);
    else if (key === '--sim-outer-timeout' && val) {
      const n = Number(val);
      if (!(Number.isFinite(n) && n > 0)) fail(`--sim-outer-timeout needs a number of seconds, got "${val}"`);
      o.simOuterS = n;
    }
    else if (key === '--sim-jobs' && val) o.simJobs = jobs(key, val);
    else if (key === '--node-jobs' && val) o.nodeJobs = jobs(key, val);
    else if (key === '--static-jobs' && val) o.staticJobs = jobs(key, val);
    else if (key === '--node-since' && val) o.nodeSince = val;
    else if (key === '--node-cache' && val === null) o.nodeCache = true;
    else fail(`unknown option "${a}"`);
  }
  for (const name of [...(o.only ?? []), ...o.skip]) {
    if (!STEP_NAMES.includes(name)) fail(`unknown step "${name}"`);
  }
  return o;
}

// ---------------------------------------------------------------- processes

function powershellExe() {
  const sys = process.env.SystemRoot || process.env.windir || 'C:\\Windows';
  const exe = path.join(sys, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  return fs.existsSync(exe) ? exe : 'powershell';
}

/** The command line that runs tools/godot.sh (bash mode) or tools/godot.ps1 (ps mode). */
function wrapperCommand(o, args) {
  if (o.shell === 'ps') {
    return [powershellExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(TOOLS, 'godot.ps1'), ...args]];
  }
  const bash = process.env.WATTLANDS_BASH || 'bash';
  return [bash, [path.join(TOOLS, 'godot.sh').replaceAll('\\', '/'), ...args]];
}

// Grace between the SIGTERM and the SIGKILL of a timed-out run, and the wait after the SIGKILL
// before run() gives up on the pipes closing (POSIX).
const KILL_GRACE_MS = 10_000;
const CLOSE_WAIT_MS = 5_000;

/**
 * Stops a timed-out run. Windows: taskkill /T /F takes the tree. POSIX: the wrappers exec into
 * tools/lib/godot_lock.mjs, which runs Godot in its own process group and kills that group on
 * SIGTERM, so SIGTERM goes first and SIGKILL (killTree) follows after KILL_GRACE_MS.
 */
function stopTree(pid) {
  if (process.platform === 'win32') {
    killTree(pid);
    return;
  }
  try {
    process.kill(pid, 'SIGTERM');
  } catch {
    return;
  }
  setTimeout(() => killTree(pid), KILL_GRACE_MS).unref();
}

/**
 * Runs a command, echoes its output and returns {code, text}. With `log`, the output is also
 * written to that file. A run past timeoutS is stopped (stopTree) and returns code 124, even if
 * an orphan still holds its pipes open.
 */
function run(exe, args, { cwd, log = null, timeoutS = 0, env = process.env, quiet = false, onSpawn = null } = {}) {
  return new Promise((resolve) => {
    const chunks = [];
    const out = log ? fs.createWriteStream(log) : null;
    let child;
    try {
      child = spawn(exe, args, { cwd, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    } catch (err) {
      resolve({ code: 127, text: `cannot start ${exe}: ${err.message}\n` });
      return;
    }
    if (onSpawn) onSpawn(child);
    let timedOut = false;
    let giveUp = null;
    const timer =
      timeoutS > 0
        ? setTimeout(() => {
            timedOut = true;
            stopTree(child.pid);
            giveUp = setTimeout(() => {
              child.stdout.destroy();
              child.stderr.destroy();
              done(124);
            }, KILL_GRACE_MS + CLOSE_WAIT_MS);
          }, timeoutS * 1000)
        : null;
    const onData = (stream) => (buf) => {
      chunks.push(buf);
      if (out) out.write(buf);
      if (!quiet) stream.write(buf);
    };
    child.stdout.on('data', onData(process.stdout));
    child.stderr.on('data', onData(process.stderr));
    let settled = false;
    const done = (code) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      if (giveUp) clearTimeout(giveUp);
      const text = Buffer.concat(chunks).toString('utf8');
      if (out) out.end();
      resolve({ code: timedOut ? 124 : code, text });
    };
    child.on('error', (err) => {
      chunks.push(Buffer.from(`cannot start ${exe}: ${err.code || err.message}\n`));
      done(127);
    });
    child.on('close', (code, signal) => done(code ?? (signal ? 128 : 1)));
  });
}

function godot(o, args, opts = {}) {
  const [exe, argv] = wrapperCommand(o, args);
  return run(exe, argv, { cwd: o.project, ...opts });
}

function rel(o, file) {
  return path.relative(o.project, file).replaceAll('\\', '/');
}

/** fn(item, index) over items, at most `jobs` at once; the results in item order. jobs 1 is a plain loop. */
export async function runPool(items, jobs, fn) {
  const results = new Array(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next;
      next += 1;
      results[i] = await fn(items[i], i);
    }
  };
  const n = Math.max(1, Math.min(jobs, items.length));
  await Promise.all(Array.from({ length: n }, worker));
  return results;
}

/** The last `n` lines of a text, for a quiet run that failed. */
function tailOf(text, n = 60) {
  return text.split(/\r?\n/).slice(-n).join('\n');
}

// ---------------------------------------------------------------- steps

/** import: refresh Godot's caches. Never a gate (BRIEF 2): a non-zero exit is a warning. */
async function stepImport(o) {
  const log = path.join(o.project, 'build', 'import.log');
  const r = await godot(o, ['--headless', '--path', '.', '--import'], { log });
  if (r.code === 0) return { status: 'PASS', note: `log ${rel(o, log)}` };
  return { status: 'WARN', note: `exit ${r.code}, not a gate (log ${rel(o, log)})` };
}

/** gut: the unit suite under BRIEF 7's strict rules. */
async function stepGut(o) {
  if (!fs.existsSync(path.join(o.project, 'addons', 'gut', 'gut_cmdln.gd'))) {
    return { status: 'FAIL', note: 'addons/gut/gut_cmdln.gd is missing (GUT not vendored)' };
  }
  const build = path.join(o.project, 'build');
  const junit = path.join(build, 'junit.xml');
  const log = path.join(build, 'gut.log');
  const greenFile = path.join(build, 'green_count.txt');
  const narrow = o.gdir !== null || o.gutArgs.length > 0;
  fs.rmSync(junit, { force: true });
  const args = [
    `--timeout=${GUT_TIMEOUT_S}`,
    '--headless',
    '--path',
    '.',
    '-s',
    'addons/gut/gut_cmdln.gd',
    '-gconfig=', // never res://.gutconfig.json: it could narrow the run or stop errors failing a test
    `-gdir=${o.gdir ?? 'res://tests'}`,
    '-ginclude_subdirs',
    '-gexit',
    '-gjunit_xml_file=build/junit.xml',
    ...o.gutArgs,
  ];
  const r = await godot(o, args, { log });
  const junitXml = fs.existsSync(junit) ? fs.readFileSync(junit, 'utf8') : '';
  const previousGreen = greenFloor(readGreenCount(greenFile), readGreenCount(path.join(o.project, GREEN_FLOOR_FILE)));
  const pendingAllowlist = readPendingAllowlist(path.join(o.project, 'tests', 'pending_allowlist.txt'));
  const v = evaluateGut({ exitCode: r.code, log: r.text, junitXml, previousGreen, minCount: o.minCount, narrow, pendingAllowlist });
  const counts =
    `tests ${v.tests}` +
    (v.failures !== null ? `, failures ${v.failures}` : '') +
    `, required >= ${v.required}` +
    (narrow ? ' (narrow run)' : `, previous green ${previousGreen ?? 'none'}`);
  process.stdout.write(`run_tests: gut ${counts}\n`);
  for (const reason of v.reasons) process.stdout.write(`run_tests: gut FAIL: ${reason}\n`);
  if (!v.pass) return { status: 'FAIL', note: `${counts}; ${v.reasons.join('; ')}` };
  if (!narrow) {
    if (previousGreen !== null && v.tests < previousGreen) {
      process.stdout.write(`run_tests: green count lowered from ${previousGreen} to ${v.tests} (--min-count)\n`);
    }
    writeGreenCount(greenFile, v.tests);
  }
  return { status: 'PASS', note: counts };
}

/**
 * scaffold: BRIEF 7.3. Extension point, wired by the lead once tools/new_game exists: copy
 * `git ls-files -co --exclude-standard` into build/scaffold_check/, run tools/new_game demo there,
 * import the copy through the wrapper, run GUT on res://tests/sdk/test_conformance.gd, delete the copy.
 */
async function stepScaffold(o) {
  if (process.env[NESTED_ENV]) return { status: 'SKIP', note: 'nested run_tests' };
  if (!fs.existsSync(path.join(o.project, 'tools', 'lib', 'new_game.mjs'))) {
    return { status: 'FAIL', note: 'tools/lib/new_game.mjs is missing' };
  }
  const copy = path.join(o.project, 'build', 'scaffold_check');
  fs.rmSync(copy, { recursive: true, force: true });
  const ls = spawnSync('git', ['ls-files', '-co', '--exclude-standard', '-z'], {
    cwd: o.project, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  if (ls.status !== 0) return { status: 'FAIL', note: `git ls-files failed: ${ls.stderr}` };
  const files = ls.stdout.split('\0').filter(Boolean);
  for (const f of files) {
    const src = path.join(o.project, f);
    if (!fs.existsSync(src) || fs.statSync(src).isDirectory()) continue;
    const dst = path.join(copy, f);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(src, dst);
  }
  if (fs.existsSync(path.join(o.project, 'src', 'games', 'demo'))) {
    return { status: 'FAIL', note: 'the live tree holds a demo game' };
  }
  const notes = [`copied ${files.length} files`];
  const ng = await run(process.execPath, [path.join(copy, 'tools', 'lib', 'new_game.mjs'), 'demo'], {
    cwd: copy, log: path.join(o.project, 'build', 'scaffold_new_game.log'), timeoutS: 300,
  });
  if (ng.code !== 0) return { status: 'FAIL', note: `tools/new_game demo exited ${ng.code} (copy kept in build/scaffold_check)` };
  let imp = await godot(o, ['--headless', '--path', copy, '--import'], {
    log: path.join(o.project, 'build', 'scaffold_import.log'), timeoutS: SCAFFOLD_TIMEOUT_S,
  });
  notes.push(`import exit ${imp.code}`);
  if (imp.code !== 0) {
    // BRIEF 2/4.2's first-import rule: a fresh import that fails is run once more (a 4.7.2 first
    // import crashed once mid-run here); the copy must then import cleanly.
    imp = await godot(o, ['--headless', '--path', copy, '--import'], {
      log: path.join(o.project, 'build', 'scaffold_import2.log'), timeoutS: SCAFFOLD_TIMEOUT_S,
    });
    notes.push(`second import exit ${imp.code}`);
    if (imp.code !== 0) return { status: 'FAIL', note: `${notes.join(', ')} (copy kept in build/scaffold_check)` };
  }
  fs.mkdirSync(path.join(copy, 'build'), { recursive: true });
  fs.writeFileSync(path.join(copy, 'build', '.gdignore'), '');
  const junit = path.join(copy, 'build', 'junit_scaffold.xml');
  const log = path.join(o.project, 'build', 'scaffold_gut.log');
  const r = await godot(
    o,
    ['--headless', '--path', copy, '-s', 'addons/gut/gut_cmdln.gd', '-gconfig=', '-gtest=res://tests/sdk/test_conformance.gd',
      '-gexit', '-gdisable_colors', `-gjunit_xml_file=${junit}`],
    { log, timeoutS: SCAFFOLD_TIMEOUT_S },
  );
  const junitXml = fs.existsSync(junit) ? fs.readFileSync(junit, 'utf8') : '';
  const v = evaluateGut({ exitCode: r.code, log: r.text, junitXml, previousGreen: null, minCount: 1, narrow: true });
  const demoOk = /conformance: demo ok/.test(r.text);
  if (!v.pass) {
    return { status: 'FAIL', note: `${notes.join(', ')}; conformance in the copy failed: ${v.reasons.join('; ')} (copy kept in build/scaffold_check)` };
  }
  if (!demoOk) return { status: 'FAIL', note: `${notes.join(', ')}; the log never says "conformance: demo ok" (copy kept)` };
  fs.rmSync(copy, { recursive: true, force: true });
  return { status: 'PASS', note: `${notes.join(', ')}; demo conforms (tests ${v.tests}); copy deleted` };
}

/**
 * static: tools/check_scripts.gd, then gdlint and gdformat --check when gdtoolkit is available, then
 * the workflow YAML check. With --static-jobs above 1 the parts run at once and gdlint and gdformat
 * are each split over that many processes; the verdict is the same: any finding anywhere fails.
 */
async function stepStatic(o) {
  if (!fs.existsSync(path.join(o.project, 'tools', 'check_scripts.gd'))) {
    return { status: 'FAIL', note: 'tools/check_scripts.gd is missing' };
  }
  const parts = [
    () => checkScriptsStep(o),
    () => (o.noLint ? { fail: false, note: 'lint skipped (--no-lint)' } : lintStep(o)),
    () => workflowStep(o),
  ];
  const results = o.staticJobs > 1 ? await Promise.all(parts.map((p) => p())) : await runPool(parts, 1, (p) => p());
  const failed = results.some((r) => r.fail);
  return { status: failed ? 'FAIL' : 'PASS', note: results.map((r) => r.note).join('; ') };
}

async function checkScriptsStep(o) {
  const log = path.join(o.project, 'build', 'check_scripts.log');
  const r = await godot(o, ['--headless', '--path', '.', '-s', 'tools/check_scripts.gd'], { log, quiet: o.staticJobs > 1 });
  const summary = /check_scripts: (\d+) scripts, (\d+) failures/.exec(r.text);
  if (r.code !== 0 || !summary || summary[2] !== '0') {
    if (o.staticJobs > 1) process.stdout.write(`${tailOf(r.text)}\n`);
    return { fail: true, note: `check_scripts FAIL (exit ${r.code}${summary ? `, ${summary[2]} of ${summary[1]} scripts` : ', no summary line'})` };
  }
  return { fail: false, note: `check_scripts ${summary[1]} scripts ok` };
}

// BRIEF 7.9: every CI workflow parses as YAML. tools/lib/check_workflows.py runs with a pinned
// PyYAML through uv when uv is on PATH (the same opt-in pattern as gdtoolkit); without uv, or when
// uv can't run the script, the check is skipped and says so. A file PyYAML rejects fails the step.
export const PYYAML_VERSION = '6.0.2';

/** The repo's CI workflow files (.github/workflows/*.yml|yaml), sorted, as project paths. */
export function workflowFiles(project) {
  let names;
  try {
    names = fs.readdirSync(path.join(project, '.github', 'workflows'));
  } catch {
    return [];
  }
  return names.filter((n) => /\.ya?ml$/.test(n)).sort().map((n) => `.github/workflows/${n}`);
}

/** The verdict from check_workflows.py's run ({code, text}). Returns {fail, skipped, note}. */
export function evaluateWorkflows(r) {
  const m = /workflows: (\d+) parsed, (\d+) failed/.exec(r.text);
  if (!m) return { fail: false, skipped: true, note: `workflow YAML check could not run (exit ${r.code}), skipped` };
  if (r.code === 0 && m[2] === '0') return { fail: false, skipped: false, note: `workflows ${m[1]} YAML ok` };
  return { fail: true, skipped: false, note: `workflows ${m[2]} of ${m[1]} YAML failed (see build/workflows.log)` };
}

async function workflowStep(o) {
  const files = workflowFiles(o.project);
  if (files.length === 0) return { fail: false, note: 'workflows: none' };
  const uv = spawnSync('uv', ['--version'], { encoding: 'utf8', timeout: 60_000, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  if (uv.status !== 0) {
    process.stdout.write('run_tests: workflow YAML check unavailable (no uv), skipped\n');
    return { fail: false, note: 'workflow YAML check unavailable (no uv), skipped' };
  }
  const script = path.join(LIB, 'check_workflows.py');
  const args = ['run', '--no-project', '--quiet', '--with', `pyyaml==${PYYAML_VERSION}`, 'python', '-I', script, ...files];
  const log = path.join(o.project, 'build', 'workflows.log');
  const r = await run('uv', args, { cwd: o.project, log, quiet: true, timeoutS: 300 });
  const v = evaluateWorkflows(r);
  process.stdout.write(`run_tests: ${v.note}\n`);
  return v;
}

// gdformat's output differs between gdtoolkit releases, so the fatal format check uses the pinned
// release: gdlint and gdformat on PATH count only when both report it; otherwise uvx fetches it.
export const GDTOOLKIT_VERSION = '4.5.0';

function findGdtoolkit() {
  const probe = (exe, args) => {
    const r = spawnSync(exe, args, { encoding: 'utf8', timeout: 90_000, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    return r.status === 0 && `${r.stdout ?? ''}`.includes(GDTOOLKIT_VERSION);
  };
  if (probe('gdlint', ['--version']) && probe('gdformat', ['--version'])) return { lint: ['gdlint'], format: ['gdformat'] };
  const from = ['--from', `gdtoolkit==${GDTOOLKIT_VERSION}`];
  if (probe('uvx', [...from, 'gdlint', '--version'])) {
    return { lint: ['uvx', ...from, 'gdlint'], format: ['uvx', ...from, 'gdformat'] };
  }
  // Windows application control can block the gdlint/gdformat launcher executables; the same
  // pinned release still runs as Python modules.
  const viaPython = ['run', '--no-project', '--with', `gdtoolkit==${GDTOOLKIT_VERSION}`, 'python', '-m'];
  if (probe('uv', [...viaPython, 'gdtoolkit.linter', '--version'])) {
    return { lint: ['uv', ...viaPython, 'gdtoolkit.linter'], format: ['uv', ...viaPython, 'gdtoolkit.formatter'] };
  }
  return null;
}

/**
 * The lint verdict from the gdlint and gdformat --check runs ({code, text} each). Any gdlint
 * problem or file gdformat would change fails the static step. Returns {fail, note}.
 */
export function evaluateLint(lint, fmt) {
  const lintProblems = /(\d+) problems? found/.exec(lint.text);
  const lintNote = lint.code === 0 ? 'gdlint clean' : `gdlint ${lintProblems ? `${lintProblems[1]} problems` : `exit ${lint.code}`}`;
  const fmtCount = /(\d+) files? would be reformatted/.exec(fmt.text);
  const fmtNote = fmt.code === 0 ? 'gdformat clean' : `gdformat ${fmtCount ? `${fmtCount[1]} files to reformat` : `exit ${fmt.code}`}`;
  const dirty = lint.code !== 0 || fmt.code !== 0;
  const tail = dirty ? ' (see build/gdlint.log, build/gdformat.log)' : '';
  return { fail: dirty, note: `${lintNote}, ${fmtNote}${tail}` };
}

async function lintStep(o) {
  const tk = findGdtoolkit();
  if (!tk) {
    process.stdout.write('run_tests: gdtoolkit unavailable, skipped\n');
    return { fail: false, note: 'gdtoolkit unavailable, skipped' };
  }
  const dirs = LINT_DIRS.filter((d) => fs.existsSync(path.join(o.project, d)));
  if (dirs.length === 0) return { fail: false, note: 'lint: nothing to check' };
  const lintLog = path.join(o.project, 'build', 'gdlint.log');
  const fmtLog = path.join(o.project, 'build', 'gdformat.log');
  let lint;
  let fmt;
  if (o.staticJobs > 1) {
    const chunks = lintChunks(o.project, dirs, o.staticJobs);
    const each = (cmd, extra) => Promise.all(chunks.map((c) => run(cmd[0], [...cmd.slice(1), ...extra, ...c], { cwd: o.project, quiet: true })));
    const [lints, fmts] = await Promise.all([each(tk.lint, []), each(tk.format, ['--check'])]);
    lint = mergeLintRuns(lints, /(\d+) problems? found/, (n) => `Failure: ${n} problems found`);
    fmt = mergeLintRuns(fmts, /(\d+) files? would be reformatted/, (n) => `${n} files would be reformatted`);
    fs.writeFileSync(lintLog, lint.text);
    fs.writeFileSync(fmtLog, fmt.text);
  } else {
    lint = await run(tk.lint[0], [...tk.lint.slice(1), ...dirs], { cwd: o.project, log: lintLog, quiet: true });
    fmt = await run(tk.format[0], [...tk.format.slice(1), '--check', ...dirs], { cwd: o.project, log: fmtLog, quiet: true });
  }
  const v = evaluateLint(lint, fmt);
  process.stdout.write(`run_tests: ${v.note}\n`);
  return v;
}

// gdtoolkit's own walk (gdtoolkit.common.utils.find_gd_files_from_paths): every *.gd under a directory,
// skipping directories by these names. A directory's children, passed instead of it, give the same files.
const GDTOOLKIT_SKIPPED_DIRS = new Set(['.git']);

function countGd(dir) {
  let n = 0;
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return 0;
  }
  for (const e of entries) {
    if (e.isDirectory()) {
      if (!GDTOOLKIT_SKIPPED_DIRS.has(e.name)) n += countGd(path.join(dir, e.name));
    } else if (e.name.endsWith('.gd')) n += 1;
  }
  return n;
}

/** A directory's children as lint items: subdirectories holding *.gd (weighted by count) and its own *.gd files. */
function lintChildren(project, d) {
  const out = [];
  let entries = [];
  try {
    entries = fs.readdirSync(path.join(project, d), { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const relPath = `${d}/${e.name}`;
    if (e.isDirectory()) {
      if (GDTOOLKIT_SKIPPED_DIRS.has(e.name)) continue;
      const weight = countGd(path.join(project, relPath));
      if (weight > 0) out.push({ path: relPath, weight, dir: true });
    } else if (e.name.endsWith('.gd')) out.push({ path: relPath, weight: 1, dir: false });
  }
  return out;
}

/**
 * The lint targets (`dirs`, project paths) split into at most `jobs` lists of about the same *.gd
 * count: each directory becomes its children (subdirectories and its own *.gd files), a child heavier
 * than a share is split the same way, and the items go heaviest first onto the lightest list.
 * Together the lists name exactly the files `dirs` would.
 */
export function lintChunks(project, dirs, jobs) {
  let items = dirs.flatMap((d) => lintChildren(project, d));
  const share = items.reduce((n, it) => n + it.weight, 0) / Math.max(1, jobs) / 2;
  for (let heavy = items.find((it) => it.dir && it.weight > share); heavy; heavy = items.find((it) => it.dir && it.weight > share)) {
    // Its children hold all its weight, so this always ends at files.
    const kids = lintChildren(project, heavy.path);
    items = items.flatMap((it) => (it === heavy ? kids : [it]));
  }
  items.sort((a, b) => b.weight - a.weight || a.path.localeCompare(b.path));
  const bins = Array.from({ length: Math.max(1, jobs) }, () => ({ paths: [], weight: 0 }));
  for (const it of items) {
    let best = bins[0];
    for (const b of bins) if (b.weight < best.weight) best = b;
    best.paths.push(it.path);
    best.weight += it.weight;
  }
  return bins.filter((b) => b.paths.length > 0).map((b) => b.paths.sort());
}

/**
 * One {code, text} from the runs of one tool over the chunks: the first non-zero exit, every output,
 * and the summed count of `countRe` first (evaluateLint reads the first count) when every failing run
 * printed one.
 */
export function mergeLintRuns(runs, countRe, summary) {
  const bad = runs.find((r) => r.code !== 0);
  const text = runs.map((r) => r.text).join('\n');
  if (!bad) return { code: 0, text };
  const failing = runs.filter((r) => r.code !== 0);
  const counts = failing.map((r) => countRe.exec(r.text));
  if (counts.every(Boolean)) {
    const total = counts.reduce((sum, m) => sum + Number(m[1]), 0);
    return { code: bad.code, text: `${summary(total)}\n${text}` };
  }
  return { code: failing.find((r, i) => !counts[i]).code, text };
}

/** sim: BRIEF 7.4 simulation gates. Extension point for the lead (tools/run_game_sim). */
async function stepSim(o) {
  // The BRIEF 7.4 assertions run as GUT tests (tests/scenarios, tests/core/integration) in the gut
  // step. This step drives the real CLI, tools/run_game_sim, through every registered game's
  // contents in SOLO (one rider plus a bot) and once in HOST (two riders plus a bot), writes the
  // reports and FIT files to build/sims/ for the fit step, and checks that every run completed.
  if (process.env[NESTED_ENV]) return { status: 'SKIP', note: 'nested run_tests' };
  const out = path.join(o.project, 'build', 'sims');
  // Concurrent --games lanes share build/sims, so each deletes only its own game's files.
  if (o.games) clearSimFiles(out, o.games);
  else fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(out, { recursive: true });
  const games = selectedGames(o);
  if (games.length === 0) return { status: 'SKIP', note: 'no registered games' };
  const runs = [];
  for (const g of games) {
    for (const c of g.contents) runs.push({ game: g.id, content: c, players: 1, bots: 1 });
    const hostBots = g.bots ? Math.min(1, Math.max(0, g.max_players - 2)) : 0;
    if (g.max_players >= 2) runs.push({ game: g.id, content: g.e2e_content, players: 2, bots: hostBots, tag: 'host' });
  }
  // --sim-jobs runs several at once; each run still queues on the machine-wide Godot lock.
  const simUserBase = process.env.WATTLANDS_USERDATA_DIR
    ? path.join(process.env.WATTLANDS_USERDATA_DIR, 'sim_runs')
    : path.join(o.project, 'build', 'sim_userdata');
  const results = await runPool(runs, o.simJobs, async (sim) => {
    const bots = games.find((g) => g.id === sim.game).bots ? sim.bots : 0;
    const stem = `${sim.game}_${sim.content}${sim.tag ? `_${sim.tag}` : ''}`.replace(/[^A-Za-z0-9_.-]/g, '_');
    const report = path.join(out, `${stem}.json`);
    const args = [
      `--game=${sim.game}`, `--content=${sim.content}`, `--players=${sim.players}`, `--bots=${bots}`,
      '--rider=erg:compliance=1.0', `--sim-speed=${SIM_SPEED}`, '--seed=1', `--report=${report}`,
      `--godot-timeout=${SIM_TIMEOUT_S - 60}`,
    ];
    const tool = o.shell === 'ps'
      ? [powershellExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(TOOLS, 'run_game_sim.ps1'), ...args]]
      : [process.env.WATTLANDS_BASH || 'bash', [path.join(TOOLS, 'run_game_sim').replaceAll('\\', '/'), ...args]];
    process.stdout.write(`run_tests: sim ${stem}\n`);
    const t0 = Date.now();
    // Godot processes at once must not share a user dir (CLAUDE.md): each pooled run gets its own.
    const env = o.simJobs > 1 ? { ...process.env, WATTLANDS_USERDATA_DIR: path.join(simUserBase, stem) } : process.env;
    const r = await run(tool[0], tool[1], { cwd: o.project, log: path.join(out, `${stem}.log`), timeoutS: o.simOuterS, quiet: true, env });
    let endReason = '';
    try {
      endReason = JSON.parse(fs.readFileSync(report, 'utf8')).end_reason ?? '';
    } catch {
      endReason = '(no report)';
    }
    const ok = r.code === 0 && endReason === 'complete';
    if (o.simJobs > 1) process.stdout.write(`run_tests: sim ${stem} ${ok ? 'ok' : 'FAIL'} ${((Date.now() - t0) / 1000).toFixed(1)}s\n`);
    return ok ? null : `${stem}: exit ${r.code}, end_reason ${endReason}`;
  });
  const bad = results.filter(Boolean);
  const note = `${runs.length - bad.length}/${runs.length} run_game_sim runs complete (build/sims)`;
  if (bad.length) return { status: 'FAIL', note: `${note}; ${bad.join('; ')}` };
  return { status: 'PASS', note };
}

/** Registered games (every src/games/<id>/game.json except _template) with what the steps need. */
function registeredGames(o) {
  const root = path.join(o.project, 'src', 'games');
  const out = [];
  let entries = [];
  try {
    entries = fs.readdirSync(root, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    if (!e.isDirectory() || e.name === '_template' || e.name.startsWith('.')) continue;
    const file = path.join(root, e.name, 'game.json');
    try {
      const m = JSON.parse(fs.readFileSync(file, 'utf8'));
      out.push({
        id: m.id ?? e.name,
        contents: Array.isArray(m.contents) ? m.contents : [],
        e2e_content: m.e2e_content ?? m.default_content,
        max_players: Number(m.max_players ?? 1),
        bots: Boolean(m.bots),
      });
    } catch {
      // An invalid game.json is the conformance test's to report.
    }
  }
  return out.sort((a, b) => a.id.localeCompare(b.id));
}

/** registeredGames narrowed by --games; an id that is not registered throws (the step then fails). */
function selectedGames(o) {
  const all = registeredGames(o);
  if (!o.games) return all;
  for (const id of o.games) {
    if (!all.some((g) => g.id === id)) throw new Error(`--games: "${id}" is not a registered game`);
  }
  return all.filter((g) => o.games.includes(g.id));
}

/** Deletes build/sims/<id>_* and build/sims/fit/<id>_* of these games, nothing else. */
function clearSimFiles(out, ids) {
  for (const dir of [out, path.join(out, 'fit')]) {
    let names = [];
    try {
      names = fs.readdirSync(dir);
    } catch {
      continue;
    }
    for (const n of names) {
      if (ids.some((id) => n.startsWith(`${id}_`))) fs.rmSync(path.join(dir, n), { recursive: true, force: true });
    }
  }
}

/** `npm ci` in a suite dir with a lockfile and no node_modules. Returns 'ok', 'installed' or the error. */
async function ensureNpm(o, dir) {
  const abs = path.join(o.project, dir);
  if (!fs.existsSync(path.join(abs, 'package-lock.json')) || fs.existsSync(path.join(abs, 'node_modules'))) return 'ok';
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const r = spawnSync(npm, ['ci', '--no-audit', '--no-fund'], {
    cwd: abs, encoding: 'utf8', shell: process.platform === 'win32', timeout: 600_000,
  });
  return r.status === 0 ? 'installed' : `npm ci failed (exit ${r.status})`;
}

/** fit: BRIEF 7.5, tools/fit_check on every FIT file the sims wrote. Extension point. */
async function stepFit(o) {
  // BRIEF 7.5: every FIT the simulations wrote must decode with zero errors.
  const dirs = ['build/sims', 'build/rides_test', 'build/scenarios', 'build/core_stack_test'].filter((d) =>
    fs.existsSync(path.join(o.project, d)),
  );
  if (dirs.length === 0) return { status: 'SKIP', note: 'no FIT files written (run the sim step first)' };
  const npm = await ensureNpm(o, 'tools/fit_check');
  const r = await run(process.execPath, ['tools/fit_check/check.mjs', ...dirs], {
    cwd: o.project, log: path.join(o.project, 'build', 'fit_check.log'), timeoutS: 900, quiet: true,
  });
  const fitFiles = (r.text.match(/\.fit/g) || []).length;
  const note = `${dirs.join(', ')} (npm: ${npm}; log build/fit_check.log)`;
  if (r.code !== 0) return { status: 'FAIL', note: `exit ${r.code}; ${note}` };
  if (fitFiles === 0) return { status: 'FAIL', note: `no FIT files found; ${note}` };
  return { status: 'PASS', note };
}

export const TEST_FILE_RE = /(^test\.[cm]?js$)|(^test-.+\.[cm]?js$)|([.\-_]test\.[cm]?js$)/;

/**
 * The full GUT run's floor: the larger of this checkout's last green count (build/, gitignored)
 * and the tracked floor tests/green_count_floor.txt, so CI and fresh worktrees enforce the same
 * minimum. null when neither exists. --min-count still overrides both.
 */
export const GREEN_FLOOR_FILE = 'tests/green_count_floor.txt';
export function greenFloor(local, tracked) {
  const counts = [local, tracked].filter((n) => Number.isInteger(n) && n > 0);
  return counts.length ? Math.max(...counts) : null;
}

/**
 * Every tests/games/<id>/ folder that holds Node tests (sorted), so a game's own Node tests (its
 * e2e_check unit tests, for example) run in the node step next to NODE_SUITES.
 */
export function gameNodeSuites(project) {
  let entries;
  try {
    entries = fs.readdirSync(path.join(project, 'tests', 'games'), { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((e) => e.isDirectory() && !e.name.startsWith('.'))
    .map((e) => `tests/games/${e.name}`)
    .filter((d) => hasNodeTests(path.join(project, d)))
    .sort();
}

function hasNodeTests(dir) {
  const walk = (d, inTestDir) => {
    let entries;
    try {
      entries = fs.readdirSync(d, { withFileTypes: true });
    } catch {
      return false;
    }
    for (const e of entries) {
      if (e.name.startsWith('.') || e.name === 'node_modules') continue;
      if (e.isDirectory()) {
        if (walk(path.join(d, e.name), inTestDir || e.name === 'test')) return true;
      } else if (TEST_FILE_RE.test(e.name) || (inTestDir && /\.[cm]?js$/.test(e.name))) {
        return true;
      }
    }
    return false;
  };
  return walk(dir, false);
}

// ---------------------------------------------------------------- node suites a change can affect
//
// --node-since=<rev> runs only the suites (and the NODE_EXTRA commands) that the paths changed since
// <rev> can affect. A changed path that is neither one registered game's own (GAME_OWN_PATHS) nor a
// docs Markdown file selects everything, so this table only answers for game paths: per suite, the
// game paths (`<id>` is any game) that can change its result. A suite or command with no row, and a
// test file with no row inside a row that has per-file entries ('*' is the rest), reads every game
// path. A game's own suite, tests/games/<id>, runs when that game changed. --node-since never
// narrows strict or the literal run: neither passes it.
const GAME_OWN_PATHS = ['src/games/<id>/**', 'content/<id>/**', 'assets/<id>/**', 'tests/games/<id>/**', '.github/workflows/game-<id>.yml'];
export const NODE_SUITE_GAME_INPUTS = {
  'tools/tests': {
    // run_game_sim.test.mjs, pixelate and the screenshot dry runs start Godot on the real project,
    // whose GameRegistry loads every game's game.json and entry script.
    '*': GAME_OWN_PATHS,
    // The real run_sims.sh plans and check_sims.mjs checkers; the rest runs on scratch repos.
    'gate.test.mjs': ['tests/games/<id>/sim/**'],
    // listGutFiles over the real tests/ and the pins of the real manifest.
    'gate_core.test.mjs': ['tests/games/<id>/**'],
    // gameNodeSuites over the real tests/games/; Godot runs on scratch projects.
    'run_tests.test.mjs': ['tests/games/<id>/**'],
    'godot_lock.test.mjs': [],
    'gut_gate.test.mjs': [],
    'wrappers.test.mjs': [],
    'run_tests_steps.test.mjs': [],
  },
  'server/relay': [],
  'server/mock_strava': [],
  'tools/art': [],
  // findBanks over assets/<id>/audio, and the real-wave reports a bank names under tests/games/<id>/.
  'tools/audio': ['assets/<id>/audio/**', 'tests/games/<id>/audio/**'],
  'tools/fit_check': [],
  'tools/e2e': [],
};

function gameGlobs(patterns, id) {
  return patterns.map((p) => globToRegExp(p.replaceAll('<id>', id)));
}

/** Which registered game owns `p` (GAME_OWN_PATHS), or null. */
export function gameOfPath(p, gameIds) {
  for (const id of gameIds) {
    if (gameGlobs(GAME_OWN_PATHS, id).some((re) => re.test(p))) return id;
  }
  return null;
}

/**
 * The node step's plan for a change set. units: [{name, kind: 'suite'|'extra', files}] in the order
 * given; `files` null means the whole suite, else the test files (suite-relative) to pass to
 * `node --test`. suiteFiles(suite) lists a suite's test files (for rows with per-file entries).
 * Returns {all, units, skipped: [{name, why}], why}.
 */
export function planNodeSuites({ changed, units, gameIds, suiteFiles = () => [] }) {
  const games = new Set();
  const platform = [];
  for (const p of changed) {
    if (/^docs\/.*\.md$/.test(p)) continue;
    const id = gameOfPath(p, gameIds);
    if (id === null) platform.push(p);
    else games.add(id);
  }
  const whole = (u) => ({ ...u, files: null });
  if (platform.length > 0) {
    return { all: true, units: units.map(whole), skipped: [], why: `${platform[0]} is not one game's own path` };
  }
  const hit = (patterns) => changed.some((p) => [...games].some((id) => gameGlobs(patterns, id).some((re) => re.test(p))));
  const out = [];
  const skipped = [];
  for (const u of units) {
    const own = /^tests\/games\/([^/]+)$/.exec(u.name);
    if (own && u.kind === 'suite') {
      if (games.has(own[1])) out.push(whole(u));
      else skipped.push({ name: u.name, why: 'another game' });
      continue;
    }
    const row = Object.hasOwn(NODE_SUITE_GAME_INPUTS, u.name) ? NODE_SUITE_GAME_INPUTS[u.name] : GAME_OWN_PATHS;
    if (Array.isArray(row)) {
      if (hit(row)) out.push(whole(u));
      else skipped.push({ name: u.name, why: 'reads no changed game path' });
      continue;
    }
    const files = suiteFiles(u.name);
    const picked = files.filter((f) => hit(Object.hasOwn(row, f) ? row[f] : (row['*'] ?? GAME_OWN_PATHS)));
    if (picked.length === files.length) out.push(whole(u));
    else if (picked.length > 0) out.push({ ...u, files: picked });
    else skipped.push({ name: u.name, why: 'reads no changed game path' });
  }
  const why = games.size ? `game paths of ${[...games].sort().join(', ')}` : 'no path any suite reads';
  return { all: false, units: out, skipped, why };
}

/**
 * The test files `node --test` finds in a suite (TEST_FILE_RE, or any script under a test/ folder),
 * suite-relative with forward slashes, sorted.
 */
export function suiteTestFiles(dir) {
  const out = [];
  const walk = (d, relDir, inTestDir) => {
    let entries = [];
    try {
      entries = fs.readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (e.name.startsWith('.') || e.name === 'node_modules') continue;
      const relPath = relDir ? `${relDir}/${e.name}` : e.name;
      if (e.isDirectory()) walk(path.join(d, e.name), relPath, inTestDir || e.name === 'test');
      else if (TEST_FILE_RE.test(e.name) || (inTestDir && /\.[cm]?js$/.test(e.name))) out.push(relPath);
    }
  };
  walk(dir, '', false);
  return out.sort();
}

/** The paths changed since `base`: committed (base...HEAD), staged, unstaged and untracked. {paths} or {error}. */
export function changedPaths(project, base) {
  const git = (args) => spawnSync('git', ['-C', project, ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, windowsHide: true });
  const committed = git(['diff', '--name-only', '--no-renames', '-z', `${base}...HEAD`]);
  const first = (stderr) => (stderr || '').trim().split(/\r?\n/)[0];
  if (committed.status !== 0) return { error: `git diff ${base}...HEAD failed: ${first(committed.stderr)}` };
  const status = git(['status', '--porcelain', '-z', '--untracked-files=all', '--no-renames']);
  if (status.status !== 0) return { error: `git status failed: ${first(status.stderr)}` };
  const paths = new Set(committed.stdout.split('\0').filter(Boolean));
  for (const entry of status.stdout.split('\0').filter(Boolean)) paths.add(entry.slice(3));
  return { paths: [...paths].sort() };
}

/** node: `node --test` in every Node suite directory that has tests, then NODE_EXTRA. */
async function stepNode(o) {
  if (process.env[NESTED_ENV]) return { status: 'SKIP', note: 'nested run_tests (started from a Node suite)' };
  const results = [];
  const units = [];
  for (const suite of [...NODE_SUITES, ...gameNodeSuites(o.project)]) {
    const dir = path.join(o.project, suite);
    if (!fs.existsSync(dir)) results.push(`${suite} SKIP (missing)`);
    else if (!hasNodeTests(dir)) results.push(`${suite} SKIP (no tests)`);
    else units.push({ name: suite, kind: 'suite', files: null });
  }
  for (const extra of NODE_EXTRA) {
    if (fs.existsSync(path.join(o.project, extra[0]))) units.push({ name: extra[0], kind: 'extra', files: null, argv: extra });
  }
  let selected = units;
  if (o.nodeSince) {
    const ch = changedPaths(o.project, o.nodeSince);
    if (ch.error) {
      process.stdout.write(`run_tests: --node-since=${o.nodeSince}: ${ch.error}; every suite runs\n`);
    } else {
      const ids = registeredGames(o).map((g) => g.id);
      const plan = planNodeSuites({ changed: ch.paths, units, gameIds: ids, suiteFiles: (s) => suiteTestFiles(path.join(o.project, s)) });
      selected = plan.units;
      process.stdout.write(`run_tests: --node-since=${o.nodeSince}: ${ch.paths.length} changed paths, ${plan.all ? 'every suite' : `${plan.units.length} of ${units.length}`} (${plan.why})\n`);
      for (const s of plan.skipped) results.push(`${s.name} SKIP (${s.why})`);
    }
  }
  for (const u of selected) {
    if (u.kind === 'suite' && NPM_DIRS.includes(u.name)) {
      const npm = await ensureNpm(o, u.name);
      if (npm !== 'ok') process.stdout.write(`run_tests: ${u.name}: ${npm}\n`);
    }
  }
  const parallel = o.nodeJobs > 1;
  const env = { ...process.env, [NESTED_ENV]: '1' };
  // A `node --test` that inherits the test runner's child marker reports to a parent that is not
  // there and exits 0 whatever its tests did (run_tests started from inside a Node test).
  delete env.NODE_TEST_CONTEXT;
  if (o.nodeCache) env.WATTLANDS_TEST_CACHE_DIR = path.join(o.project, 'build', 'test_cache');
  else delete env.WATTLANDS_TEST_CACHE_DIR;
  // Node 22.12-22.17 strips TypeScript types only with the flag (the relay's suite imports .ts).
  const [maj, min] = process.versions.node.split('.').map(Number);
  const strip = maj === 22 && min < 18 ? ['--experimental-strip-types'] : [];
  // The longest suites first, so a pool never ends on one of them.
  const order = parallel ? [...selected].sort((a, b) => nodeRank(a.name) - nodeRank(b.name)) : selected;
  const outcomes = await runPool(order, o.nodeJobs, async (u) => {
    const t0 = Date.now();
    let r;
    if (u.kind === 'suite') {
      const label = u.files ? `${u.name} (${u.files.length} files)` : u.name;
      process.stdout.write(`run_tests: node --test in ${label}\n`);
      const log = path.join(o.project, 'build', `node_${u.name.replaceAll('/', '_')}.log`);
      r = await run(process.execPath, [...strip, '--test', ...(u.files ?? [])], {
        cwd: path.join(o.project, u.name), log, timeoutS: NODE_SUITE_TIMEOUT_S, env, quiet: parallel,
      });
    } else {
      process.stdout.write(`run_tests: node ${u.argv.join(' ')}\n`);
      const log = path.join(o.project, 'build', `node_${path.basename(u.argv[0])}.log`);
      r = await run(process.execPath, u.argv, { cwd: o.project, log, timeoutS: NODE_SUITE_TIMEOUT_S, env, quiet: parallel });
    }
    const s = ((Date.now() - t0) / 1000).toFixed(1);
    const ok = r.code === 0;
    if (parallel) {
      process.stdout.write(`run_tests: node ${u.name} ${ok ? 'PASS' : 'FAIL'} ${s}s\n`);
      if (!ok) process.stdout.write(`--- ${u.name} (last 60 lines)\n${tailOf(r.text)}\n`);
    }
    const part = u.files ? ` (${u.files.length} files)` : '';
    return { name: u.name, ok, text: ok ? `${u.name}${part} PASS ${s}s` : `${u.name}${part} FAIL (exit ${r.code})` };
  });
  const byName = new Map(outcomes.map((x) => [x.name, x]));
  results.push(...selected.map((u) => byName.get(u.name).text));
  const failed = outcomes.filter((x) => !x.ok).length;
  process.stdout.write(`run_tests: node suites: ${results.join(', ')}\n`);
  if (failed > 0) return { status: 'FAIL', note: results.join(', ') };
  // --node-since that selects nothing is a verdict (no suite reads what changed); otherwise no suite is a SKIP.
  if (outcomes.length === 0 && units.length > 0 && selected !== units) return { status: 'PASS', note: `no suite reads the changed paths: ${results.join(', ')}` };
  if (outcomes.length === 0) return { status: 'SKIP', note: results.join(', ') || 'no suite' };
  return { status: 'PASS', note: results.join(', ') };
}

// Pool order of the node step: these first (the longest, from the v1.1.0 literal run), the rest as listed.
const NODE_SLOW = ['tools/tests', 'tools/audio', 'tools/art/pixelate_e2e.mjs', 'tools/e2e', 'tests/games/tank', 'tests/games/workout'];
function nodeRank(name) {
  const i = NODE_SLOW.indexOf(name);
  return i < 0 ? NODE_SLOW.length : i;
}

/** e2e: BRIEF 7.7, node tools/e2e/run.mjs --games=<registered games>. Extension point. */
async function stepE2e(o) {
  // BRIEF 7.7: one host and two clients per registered game; holds 3 Godot slots, so it runs last.
  if (process.env[NESTED_ENV]) return { status: 'SKIP', note: 'nested run_tests' };
  const games = selectedGames(o).map((g) => g.id);
  if (games.length === 0) return { status: 'SKIP', note: 'no registered games' };
  if (!fs.existsSync(path.join(o.project, 'tools', 'e2e', 'run.mjs'))) return { status: 'FAIL', note: 'tools/e2e/run.mjs is missing' };
  await ensureNpm(o, 'server/relay');
  await ensureNpm(o, 'tools/fit_check');
  const logName = o.games ? `e2e_${games.join('_')}.log` : 'e2e.log';
  const r = await run(process.execPath, ['tools/e2e/run.mjs', `--games=${games.join(',')}`], {
    cwd: o.project, log: path.join(o.project, 'build', logName), timeoutS: E2E_TIMEOUT_S,
  });
  if (r.code === 0) return { status: 'PASS', note: `games ${games.join(', ')} (log build/${logName})` };
  if (r.code === 75) return { status: 'FAIL', note: 'godot lock wait timeout (exit 75)' };
  return { status: 'FAIL', note: `exit ${r.code} for games ${games.join(', ')} (log build/${logName})` };
}

export const STEPS = [
  { name: 'import', run: stepImport },
  { name: 'gut', run: stepGut },
  { name: 'scaffold', run: stepScaffold },
  { name: 'static', run: stepStatic },
  { name: 'sim', run: stepSim },
  { name: 'fit', run: stepFit },
  { name: 'node', run: stepNode },
  { name: 'e2e', run: stepE2e },
];

// ---------------------------------------------------------------- main

function ensureBuildDir(project) {
  const build = path.join(project, 'build');
  fs.mkdirSync(build, { recursive: true });
  const ignore = path.join(build, '.gdignore');
  if (!fs.existsSync(ignore)) fs.writeFileSync(ignore, '');
}

function printSummary(rows) {
  const w = Math.max(4, ...rows.map((r) => r.name.length));
  process.stdout.write('\nrun_tests summary\n');
  process.stdout.write(`  ${'step'.padEnd(w)}  result  time     note\n`);
  for (const r of rows) {
    const t = `${(r.ms / 1000).toFixed(1)}s`.padEnd(7);
    process.stdout.write(`  ${r.name.padEnd(w)}  ${r.status.padEnd(6)}  ${t}  ${r.note ?? ''}\n`);
  }
}

export async function main(argv) {
  const o = parseArgs(argv);
  process.env.WATTLANDS_NO_HW_CONTROL = '1';
  process.env.WATTLANDS_NO_NETWORK_INTEGRATIONS = '1';
  // docs/OWNERSHIP.md TL5: every gate runs without the art pipeline's key and permission, so no test
  // can make a paid fal call even in a game session where someone has set them. Only this process
  // tree loses them; the caller's shell keeps both (tools/env.* and the Godot wrappers never touch them).
  for (const name of ART_VARS) delete process.env[name];
  if (!fs.existsSync(path.join(o.project, 'project.godot'))) fail(`no project.godot in ${o.project}`);
  ensureBuildDir(o.project);
  const selected = STEPS.filter((s) => (o.only ? o.only.includes(s.name) : true) && !o.skip.includes(s.name));
  process.stdout.write(
    `run_tests: project ${o.project}, wrapper ${o.shell === 'ps' ? 'tools/godot.ps1' : 'tools/godot.sh'}, steps ${selected.map((s) => s.name).join(', ') || '(none)'}\n`,
  );
  const rows = [];
  for (const step of STEPS) {
    if (!selected.includes(step)) {
      rows.push({ name: step.name, status: 'SKIP', ms: 0, note: o.only ? 'not in --only' : '--skip' });
      continue;
    }
    process.stdout.write(`\n=== run_tests: ${step.name} ===\n`);
    const t0 = Date.now();
    let result;
    try {
      result = await step.run(o);
    } catch (err) {
      result = { status: 'FAIL', note: `step crashed: ${err.message}` };
    }
    rows.push({ name: step.name, ms: Date.now() - t0, ...result });
  }
  printSummary(rows);
  const failedSteps = rows.filter((r) => r.status === 'FAIL').map((r) => r.name);
  process.stdout.write(failedSteps.length ? `run_tests: FAILED (${failedSteps.join(', ')})\n` : 'run_tests: all selected gates passed\n');
  return failedSteps.length ? 1 : 0;
}

// Exported for tests.
export { FORBIDDEN, hasNodeTests };
// For tools/lib/gate.mjs.
export { wrapperCommand, run, ensureNpm, registeredGames, ensureBuildDir, selectedGames };

const isMain = (() => {
  if (!process.argv[1]) return false;
  const norm = (p) => (process.platform === 'win32' ? path.resolve(p).toLowerCase() : path.resolve(p));
  return norm(process.argv[1]) === norm(fileURLToPath(import.meta.url));
})();

if (isMain) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (err) => {
      process.stderr.write(`run_tests: ${err.stack || err}\n`);
      process.exit(1);
    },
  );
}
