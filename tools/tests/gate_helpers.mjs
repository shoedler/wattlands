// Shared helpers of the tools/gate tests (gate*.test.mjs): temp git repos, the gate CLI as a process,
// and the manifests and fixtures the files share. Not a test file: node --test runs only *.test.mjs.
import { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { BASH, GIT, TOOLS, godotBin, rmQuiet, runProc } from './helpers.mjs';

export const GATE = path.join(TOOLS, 'lib', 'gate.mjs');
export const REAL_MANIFEST = JSON.parse(fs.readFileSync(path.join(TOOLS, 'lib', 'gate_manifest.json'), 'utf8'));
export const GODOT = godotBin();
export const skipNoGodot = (!GODOT && 'no Godot binary') || (!BASH && 'bash not found');
export const temps = [];
// No process has this pid: a pid taken from a process that just exited can be in use again on a busy machine.
export const UNUSED_PID = 99999996;

export function sh(dir, ...args) {
  const r = spawnSync(GIT, ['-C', dir, ...args], { encoding: 'utf8', windowsHide: true });
  assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}

export function write(dir, files) {
  for (const [rel, text] of Object.entries(files)) {
    const file = path.join(dir, rel);
    if (text === null) {
      fs.rmSync(file, { force: true });
      continue;
    }
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  }
}

export function initRepo(dir, files, manifest) {
  sh(dir, 'init', '-q', '-b', 'main');
  sh(dir, 'config', 'user.name', 'gate test');
  sh(dir, 'config', 'user.email', 'gate@example.invalid');
  sh(dir, 'config', 'core.autocrlf', 'false');
  sh(dir, 'config', 'core.safecrlf', 'false');
  write(dir, { '.gitignore': 'build/\n.godot/\n.userdata/\n', 'tools/lib/gate_manifest.json': JSON.stringify(manifest), ...files });
  commit(dir, 'base');
}

/** A fresh repo on main with one commit, holding the real manifest (or `manifest`) and `files`. */
export function repo(files = {}, manifest = REAL_MANIFEST) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-repo-'));
  temps.push(dir);
  initRepo(dir, files, manifest);
  return dir;
}

export function commit(dir, message) {
  sh(dir, 'add', '-A');
  sh(dir, 'commit', '-q', '--allow-empty', '-m', message);
  return sh(dir, 'rev-parse', 'HEAD');
}

/** Writes `files` on a new branch and commits them. */
export function onBranch(dir, branch, files, message = 'work') {
  sh(dir, 'checkout', '-q', '-b', branch);
  write(dir, files);
  return commit(dir, message);
}

export function gateEnv(extra = {}) {
  const env = { ...process.env, ...extra };
  delete env.WATTLANDS_RUN_TESTS_NESTED;
  return env;
}

export const gate = (dir, args, { env = {}, timeoutMs = 300_000 } = {}) => runProc(process.execPath, [GATE, ...args, `--project=${dir}`], { env: gateEnv(env), cwd: dir, timeoutMs });
export const check = (dir, ...args) => gate(dir, ['check', ...args]);

export async function assertCheck(dir, args, code, pattern) {
  const r = await check(dir, ...args);
  assert.equal(r.code, code, r.stdout + r.stderr);
  if (pattern) assert.match(r.stdout, pattern);
  return r;
}

export const PIN_MANIFEST = {
  ...REAL_MANIFEST,
  safety_pin_globs: ['tests/governor/**', 'tools/godot.sh'],
  safety_pin_except: {},
  safety_pin_lines: {},
  append_only_pins: { 'tests/games/tank/sim/check_sims.mjs': ['checkS4'] },
  append_only_tables: {},
  append_only_anchors: {},
  append_only_moves: {},
};
export const NO_PINS_MANIFEST = { ...PIN_MANIFEST, safety_pin_globs: [], append_only_pins: {} };
export const CHECKER = 'export function checkS4(r) {\n  if (r.w < 55) return bad();\n  return ok();\n}\n';

export function pinnedRepo() {
  const dir = repo({ 'tests/governor/test_a.gd': 'func test_a():\n\tassert_eq(a, b)\n', 'tools/godot.sh': 'real\n', 'tests/games/tank/sim/check_sims.mjs': CHECKER }, PIN_MANIFEST);
  return dir;
}

export async function pin(dir) {
  const r = await gate(dir, ['pin-safety', '--reason=baseline']);
  assert.equal(r.code, 0, r.stdout + r.stderr);
  commit(dir, 'chore: pins');
}

export const tests = (n, name = 'x') => Array.from({ length: n }, (_, i) => `func test_${name}_${i}():\n\tassert_eq(a, b)\n`).join('\n');

export const HW_FLAG = `--allow-${'hw'}`;
export const NET_FLAG = `--allow-${'network'}`;

after(() => {
  for (const d of temps) rmQuiet(d);
});
