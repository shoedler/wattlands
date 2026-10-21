#!/usr/bin/env node
// tools/lib/run_tests.mjs: the gate runner behind tools/run_tests (bash) and tools/run_tests.ps1.
// Zero dependencies, Node 22.12+. Both shims call this file, so the two runners behave identically;
// the bash shim runs Godot through tools/godot.sh, the PowerShell shim through tools/godot.ps1.
//
//   tools/run_tests [--only=<step,...>] [--skip=<step,...>] [--min-count=<n>] [--gdir=<res path>]
//                   [--gut-arg=<arg>]... [--strict-lint] [--no-lint] [--project=<dir>]
//
// Steps run in STEPS order. To add a step (BRIEF 7.3 scaffold check, simulation, FIT, e2e), fill in
// its function below; it returns {status: 'PASS'|'FAIL'|'SKIP'|'WARN', note}. Only FAIL fails the run.

import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { killTree } from './godot_lock.mjs';
import { evaluateGut, readGreenCount, writeGreenCount, FORBIDDEN } from './gut_gate.mjs';

const LIB = path.dirname(fileURLToPath(import.meta.url));
const TOOLS = path.dirname(LIB);
const REPO = path.dirname(TOOLS);

const STEP_NAMES = ['import', 'gut', 'scaffold', 'static', 'sim', 'fit', 'node', 'e2e'];
const LINT_DIRS = ['addons/wattlands', 'src', 'tests', 'tools'];
const NODE_SUITES = ['tools/tests', 'server/relay', 'server/mock_strava', 'tools/art'];
const NODE_SUITE_TIMEOUT_S = 1800;
const NESTED_ENV = 'WATTLANDS_RUN_TESTS_NESTED';
const ART_VARS = ['FAL_KEY', 'WATTLANDS_ALLOW_ART'];

const USAGE = `usage: tools/run_tests [options]      (tools/run_tests.ps1 in PowerShell)
  --only=<step,...>    run only these steps (${STEP_NAMES.join(', ')})
  --skip=<step,...>    skip these steps
  --min-count=<n>      required GUT test count instead of the previous green count
  --gdir=<res path>    narrower GUT run (default res://tests); does not compare or update the green count
  --gut-arg=<arg>      extra GUT argument (repeatable); also makes the run narrow
  --strict-lint        gdlint / gdformat findings fail the static step (default: reported only)
  --no-lint            skip gdlint / gdformat
  --project=<dir>      project root (default: this checkout)`;

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
    strictLint: false,
    noLint: false,
    project: REPO,
    shell: process.platform === 'win32' ? 'ps' : 'bash',
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
    else if (key === '--strict-lint' && val === null) o.strictLint = true;
    else if (key === '--no-lint' && val === null) o.noLint = true;
    else if (key === '--project' && val) o.project = path.resolve(val);
    else if (key === '--shell' && (val === 'bash' || val === 'ps')) o.shell = val;
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

/**
 * Runs a command, echoes its output and returns {code, text}. With `log`, the output is also
 * written to that file. A run past timeoutS has its process tree killed and code 124.
 */
function run(exe, args, { cwd, log = null, timeoutS = 0, env = process.env, quiet = false } = {}) {
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
    let timedOut = false;
    const timer =
      timeoutS > 0
        ? setTimeout(() => {
            timedOut = true;
            killTree(child.pid);
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
    '--headless',
    '--path',
    '.',
    '-s',
    'addons/gut/gut_cmdln.gd',
    `-gdir=${o.gdir ?? 'res://tests'}`,
    '-ginclude_subdirs',
    '-gexit',
    '-gjunit_xml_file=build/junit.xml',
    ...o.gutArgs,
  ];
  const r = await godot(o, args, { log });
  const junitXml = fs.existsSync(junit) ? fs.readFileSync(junit, 'utf8') : '';
  const previousGreen = readGreenCount(greenFile);
  const v = evaluateGut({ exitCode: r.code, log: r.text, junitXml, previousGreen, minCount: o.minCount, narrow });
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
async function stepScaffold(_o) {
  return { status: 'SKIP', note: 'not wired yet (BRIEF 7.3, lead adds it in W2)' };
}

/** static: tools/check_scripts.gd, then gdlint and gdformat --check when gdtoolkit is available. */
async function stepStatic(o) {
  const notes = [];
  let failed = false;
  if (!fs.existsSync(path.join(o.project, 'tools', 'check_scripts.gd'))) {
    return { status: 'FAIL', note: 'tools/check_scripts.gd is missing' };
  }
  const log = path.join(o.project, 'build', 'check_scripts.log');
  const r = await godot(o, ['--headless', '--path', '.', '-s', 'tools/check_scripts.gd'], { log });
  const summary = /check_scripts: (\d+) scripts, (\d+) failures/.exec(r.text);
  if (r.code !== 0 || !summary || summary[2] !== '0') {
    failed = true;
    notes.push(`check_scripts FAIL (exit ${r.code}${summary ? `, ${summary[2]} of ${summary[1]} scripts` : ', no summary line'})`);
  } else {
    notes.push(`check_scripts ${summary[1]} scripts ok`);
  }

  if (o.noLint) {
    notes.push('lint skipped (--no-lint)');
  } else {
    const lint = await lintStep(o);
    notes.push(lint.note);
    if (lint.fail) failed = true;
  }
  return { status: failed ? 'FAIL' : 'PASS', note: notes.join('; ') };
}

function findGdtoolkit() {
  const probe = (exe, args) => {
    const r = spawnSync(exe, args, { encoding: 'utf8', timeout: 90_000, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    return r.status === 0;
  };
  if (probe('gdlint', ['--version'])) return { lint: ['gdlint'], format: ['gdformat'] };
  const from = ['--from', 'gdtoolkit==4.*'];
  if (probe('uvx', [...from, 'gdlint', '--version'])) {
    return { lint: ['uvx', ...from, 'gdlint'], format: ['uvx', ...from, 'gdformat'] };
  }
  return null;
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
  const lint = await run(tk.lint[0], [...tk.lint.slice(1), ...dirs], { cwd: o.project, log: lintLog, quiet: true });
  const fmt = await run(tk.format[0], [...tk.format.slice(1), '--check', ...dirs], { cwd: o.project, log: fmtLog, quiet: true });
  const lintProblems = /(\d+) problems? found/.exec(lint.text);
  const lintNote = lint.code === 0 ? 'gdlint clean' : `gdlint ${lintProblems ? `${lintProblems[1]} problems` : `exit ${lint.code}`}`;
  const fmtCount = /(\d+) files? would be reformatted/.exec(fmt.text);
  const fmtNote = fmt.code === 0 ? 'gdformat clean' : `gdformat ${fmtCount ? `${fmtCount[1]} files to reformat` : `exit ${fmt.code}`}`;
  const dirty = lint.code !== 0 || fmt.code !== 0;
  const tail = dirty ? (o.strictLint ? ' (--strict-lint: fatal)' : ' (non-fatal; see build/gdlint.log, build/gdformat.log)') : '';
  process.stdout.write(`run_tests: ${lintNote}, ${fmtNote}${tail}\n`);
  return { fail: dirty && o.strictLint, note: `${lintNote}, ${fmtNote}${tail}` };
}

/** sim: BRIEF 7.4 simulation gates. Extension point for the lead (tools/run_game_sim). */
async function stepSim(_o) {
  return { status: 'SKIP', note: 'not wired yet (BRIEF 7.4)' };
}

/** fit: BRIEF 7.5, tools/fit_check on every FIT file the sims wrote. Extension point. */
async function stepFit(_o) {
  return { status: 'SKIP', note: 'not wired yet (BRIEF 7.5)' };
}

const TEST_FILE_RE = /(^test\.[cm]?js$)|(^test-.+\.[cm]?js$)|([.\-_]test\.[cm]?js$)/;

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

/** node: `node --test` in every Node suite directory that has tests. */
async function stepNode(o) {
  if (process.env[NESTED_ENV]) return { status: 'SKIP', note: 'nested run_tests (started from a Node suite)' };
  const results = [];
  let ran = 0;
  let failed = 0;
  for (const suite of NODE_SUITES) {
    const dir = path.join(o.project, suite);
    if (!fs.existsSync(dir)) {
      results.push(`${suite} SKIP (missing)`);
      continue;
    }
    if (!hasNodeTests(dir)) {
      results.push(`${suite} SKIP (no tests)`);
      continue;
    }
    process.stdout.write(`run_tests: node --test in ${suite}\n`);
    const log = path.join(o.project, 'build', `node_${suite.replaceAll('/', '_')}.log`);
    const r = await run(process.execPath, ['--test'], {
      cwd: dir,
      log,
      timeoutS: NODE_SUITE_TIMEOUT_S,
      env: { ...process.env, [NESTED_ENV]: '1' },
    });
    ran += 1;
    if (r.code === 0) results.push(`${suite} PASS`);
    else {
      failed += 1;
      results.push(`${suite} FAIL (exit ${r.code})`);
    }
  }
  process.stdout.write(`run_tests: node suites: ${results.join(', ')}\n`);
  if (failed > 0) return { status: 'FAIL', note: results.join(', ') };
  if (ran === 0) return { status: 'SKIP', note: results.join(', ') };
  return { status: 'PASS', note: results.join(', ') };
}

/** e2e: BRIEF 7.7, node tools/e2e/run.mjs --games=<registered games>. Extension point. */
async function stepE2e(_o) {
  return { status: 'SKIP', note: 'not wired yet (BRIEF 7.7)' };
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
  // can make a paid fal call even in a game session where Simon has set them. Only this process
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
