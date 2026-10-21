// tools/tests/helpers.mjs: shared helpers for the tooling suites (not a test file itself).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { killTree } from '../lib/godot_lock.mjs';

export const TESTS_DIR = path.dirname(fileURLToPath(import.meta.url));
export const TOOLS = path.dirname(TESTS_DIR);
export const REPO = path.dirname(TOOLS);
export const IS_WIN = process.platform === 'win32';

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function firstLine(file) {
  try {
    const line = fs.readFileSync(file, 'utf8').split(/\r?\n/)[0].trim();
    return line && fs.existsSync(line) ? line : null;
  } catch {
    return null;
  }
}

function which(name) {
  const exts = IS_WIN ? ['.exe', '.cmd', ''] : [''];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    for (const ext of exts) {
      const file = path.join(dir, name + ext);
      try {
        if (fs.statSync(file).isFile()) return file;
      } catch {
        // keep looking
      }
    }
  }
  return null;
}

export const GIT = which('git');

/** The Godot binary the wrappers would use: tools/godot_bin.local here or in the main checkout, else $GODOT. */
export function godotBin() {
  const here = firstLine(path.join(TOOLS, 'godot_bin.local'));
  if (here) return here;
  if (GIT) {
    const r = spawnSync(GIT, ['-C', REPO, 'rev-parse', '--path-format=absolute', '--git-common-dir'], { encoding: 'utf8' });
    if (r.status === 0) {
      const main = firstLine(path.join(path.dirname(r.stdout.trim()), 'tools', 'godot_bin.local'));
      if (main) return main;
    }
  }
  return process.env.GODOT || null;
}

/** Git Bash's bash.exe on Windows (never WSL's System32\bash.exe), /bin/bash elsewhere. */
export function findBash() {
  const env = process.env.WATTLANDS_BASH;
  if (env && fs.existsSync(env)) return env;
  if (!IS_WIN) return fs.existsSync('/bin/bash') ? '/bin/bash' : which('bash');
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    const low = dir.toLowerCase();
    if (!dir || low.includes('system32') || low.includes('windowsapps')) continue;
    const exe = path.join(dir, 'bash.exe');
    if (fs.existsSync(exe)) return exe;
  }
  for (const c of ['C:\\Program Files\\Git\\usr\\bin\\bash.exe', 'C:\\Program Files\\Git\\bin\\bash.exe']) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

export const BASH = findBash();

export function powershellExe() {
  if (!IS_WIN) return null;
  const sys = process.env.SystemRoot || 'C:\\Windows';
  const exe = path.join(sys, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  return fs.existsSync(exe) ? exe : which('powershell');
}

/**
 * An "empty" environment: only what bash, PowerShell, node and Godot need to start, plus `extra`.
 * TEMP/TMP keep os.tmpdir() unchanged so real Godot runs share the machine-wide lock.
 */
export function minimalEnv(extra = {}, { withGit = true } = {}) {
  const env = {};
  const dirs = [];
  if (BASH) dirs.push(path.dirname(BASH));
  dirs.push(path.dirname(process.execPath));
  if (withGit && GIT) dirs.push(path.dirname(GIT));
  if (IS_WIN) {
    const sys = process.env.SystemRoot || 'C:\\Windows';
    env.SystemRoot = sys;
    env.TEMP = os.tmpdir();
    env.TMP = os.tmpdir();
    dirs.push(path.join(sys, 'System32'), path.join(sys, 'System32', 'WindowsPowerShell', 'v1.0'));
  } else {
    env.TMPDIR = os.tmpdir();
    dirs.push('/usr/bin', '/bin');
  }
  for (const key of ['WATTLANDS_GODOT_LOCK_DIR', 'WATTLANDS_GODOT_LOCK_CAP']) {
    if (process.env[key]) env[key] = process.env[key];
  }
  env.PATH = [...new Set(dirs)].join(path.delimiter);
  return { ...env, ...extra };
}

/** Runs a process to completion: {code, stdout, stderr, ms}. Kills the tree after timeoutMs. */
export function runProc(exe, args, { env = process.env, cwd = REPO, timeoutMs = 120_000 } = {}) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const child = spawn(exe, args, { env, cwd, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    const timer = setTimeout(() => killTree(child.pid), timeoutMs);
    child.on('error', (err) => {
      clearTimeout(timer);
      resolve({ code: 127, stdout, stderr: stderr + String(err), ms: Date.now() - t0 });
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, stdout, stderr, ms: Date.now() - t0 });
    });
  });
}

/** Starts tools/godot.sh (shell "bash") or tools/godot.ps1 (shell "ps") from `tools` (default: this checkout's). */
export function runWrapper(shell, args, opts = {}) {
  const tools = opts.tools ?? TOOLS;
  if (shell === 'ps') {
    return runProc(powershellExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(tools, 'godot.ps1'), ...args], opts);
  }
  return runProc(BASH, [path.join(tools, 'godot.sh').replaceAll('\\', '/'), ...args], opts);
}

/** A throwaway Godot project under build/ (which has a .gdignore), so tests never import the main checkout. */
export function makeScratchProject(name, files = {}) {
  const build = path.join(REPO, 'build');
  fs.mkdirSync(build, { recursive: true });
  const ignore = path.join(build, '.gdignore');
  if (!fs.existsSync(ignore)) fs.writeFileSync(ignore, '');
  const dir = fs.mkdtempSync(path.join(build, `tooling-${name}-`));
  fs.writeFileSync(path.join(dir, 'project.godot'), `config_version=5\n\n[application]\n\nconfig/name="${name}"\n`);
  for (const [rel, content] of Object.entries(files)) {
    const file = path.join(dir, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
  }
  return dir;
}

/** PROBE KEY=VALUE lines from tools/tests/probes/print_env.gd. */
export function parseProbe(stdout) {
  const out = {};
  for (const line of stdout.split(/\r?\n/)) {
    const m = /^PROBE ([A-Z_]+)=(.*)$/.exec(line);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

export function samePath(a, b) {
  const norm = (p) => {
    const r = path.resolve(p.replaceAll('/', path.sep));
    return IS_WIN ? r.toLowerCase() : r;
  };
  return norm(a) === norm(b);
}

export function rmQuiet(dir) {
  try {
    fs.rmSync(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  } catch {
    // best effort
  }
}
