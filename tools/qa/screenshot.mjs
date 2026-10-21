#!/usr/bin/env node
// tools/qa/screenshot.mjs: the shared core of tools/screenshot (bash) and tools/screenshot.ps1
// (BRIEF 3.6, 7.8). Owned by qa. Zero dependencies.
//
//   tools/screenshot --game=<id> --content=<id> --at=<s>[,<s>...] [--players=<n>] [--bots=<n>]
//                    [--rider=<profile>] [--autopilot=all|none] [--seed=<n>] [--out=<dir>]
//   tools/screenshot --scene=<res path> [--frames=<n>]
//   tools/screenshot --app-screen=title|picker|lobby [--app-game=<id>]
//   tools/screenshot --app-screen=session [--app-role=client|host|solo] [--app-game=<id>]
//                    [--content=<id>] [--at=<s>,...] [--app-overlay=menu|panic|none]
//
// Runs Godot windowed (never headless) through tools/godot.sh (bash) or tools/godot.ps1
// (PowerShell) with tools/qa/screenshot_main.gd, one Godot slot of the machine-wide lock, both
// locks set and FAL_KEY / WATTLANDS_ALLOW_ART removed. On Linux without DISPLAY or
// WAYLAND_DISPLAY it uses xvfb-run (llvmpipe) when installed, and otherwise prints
// "screenshot: skipped" and exits 0 (BRIEF 2). Wrapper flags: --mock-trainer=<profile> (default
// erg:compliance=1.0; never off), --size=<W>x<H> (default 1920x1080), --timeout=<s> (default
// 900), --lock-timeout=<s>, --dry-run (print the command as JSON and exit).
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { killTree } from '../lib/godot_lock.mjs';
import { childEnv, findBash, slash } from '../e2e/lib/util.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const REPO = path.resolve(HERE, '..', '..');
export const ENTRY = 'tools/qa/screenshot_main.gd';
export const DEFAULT_MOCK = 'erg:compliance=1.0';
export const SKIPPED_MESSAGE = 'screenshot: skipped (no display: set DISPLAY or install xvfb-run)';

export const USAGE = `usage: tools/screenshot --game=<id> --at=<s>[,<s>...] [--content=<id>] [--players=<n>] [--bots=<n>]
                        [--rider=<profile>]... [--autopilot=all|none] [--seed=<n>] [--out=<dir>]
                        [any other tools/run_game_sim flag]
       tools/screenshot --scene=<res://path.tscn> [--frames=<n>] [--out=<dir>]
       tools/screenshot --app-screen=title|picker|lobby [--app-game=<id>] [--frames=<n>] [--out=<dir>]
       tools/screenshot --app-screen=session [--app-role=client|host|solo] [--app-game=<id>] [--content=<id>]
                        [--at=<s>[,<s>...]] [--app-overlay=menu|panic|none] [--out=<dir>]
wrapper flags: --mock-trainer=<profile> (default ${DEFAULT_MOCK}), --size=<W>x<H> (default 1920x1080),
               --timeout=<s> (default 900), --lock-timeout=<s>, --dry-run
PNGs go to build/screenshots/<game>/<game>_<content>_<players>p_<at>s.png (game mode),
build/screenshots/scenes/ or build/screenshots/app/ unless --out is given. (PowerShell: tools\\screenshot.ps1)`;

const NOT_A_MOCK = /^(|none|off|no|false|0|real|ftms|ble|hw|hardware|trainer)$/i;
const APP_SCREENS = ['title', 'picker', 'lobby', 'session'];

/**
 * Splits wrapper flags from the flags for screenshot_main.gd and checks the mode.
 * Returns {ok, error?, help?, shell, dryRun, mockTrainer, size, timeoutS, lockTimeoutS, userArgs, mode}.
 */
export function parseScreenshotArgs(argv) {
  const o = { ok: true, shell: null, dryRun: false, mockTrainer: DEFAULT_MOCK, size: '1920x1080', timeoutS: 900, lockTimeoutS: null, userArgs: [], mode: null };
  const fail = (error) => ({ ...o, ok: false, error });
  let game = false;
  let scene = false;
  let app = false;
  let at = false;
  for (const a of argv) {
    if (a === '--help' || a === '-h') return { ...o, help: true };
    if (a === '--dry-run') {
      o.dryRun = true;
      continue;
    }
    if (a === '--allow-hw' || a === '--allow-network') return fail(`refusing ${a}: screenshots never drop the hardware or network lock (BRIEF 1)`);
    if (a === '-d' || a === '--debug') return fail(`refusing ${a}: automated runs never start the debugger (BRIEF 7)`);
    if (a === '--headless') return fail('screenshots run windowed; --headless would capture nothing');
    if (a === '--') continue;
    const eq = a.indexOf('=');
    const key = eq >= 0 ? a.slice(0, eq) : a;
    const val = eq >= 0 ? a.slice(eq + 1) : null;
    switch (key) {
      case '--shell':
        if (!['bash', 'ps'].includes(val)) return fail('--shell must be bash or ps');
        o.shell = val;
        continue;
      case '--mock-trainer':
        if (val === null || NOT_A_MOCK.test(val.trim())) return fail(`refusing to run without a mock trainer (--mock-trainer=${val ?? ''})`);
        o.mockTrainer = val.trim();
        continue;
      case '--size':
        if (!/^\d{2,5}x\d{2,5}$/.test(val ?? '')) return fail(`--size needs <W>x<H>, got "${val}"`);
        o.size = val;
        continue;
      case '--timeout':
      case '--lock-timeout': {
        const n = Number(val);
        if (val === null || val === '' || !Number.isFinite(n) || n <= 0) return fail(`${key} needs seconds > 0, got "${val}"`);
        if (key === '--timeout') o.timeoutS = n;
        else o.lockTimeoutS = n;
        continue;
      }
      default:
        break;
    }
    if (!a.startsWith('--')) return fail(`unexpected argument "${a}" (flags look like --name=value)`);
    if (key === '--game') game = true;
    if (key === '--scene') scene = true;
    if (key === '--app-screen') {
      app = true;
      if (!APP_SCREENS.includes(val)) return fail(`--app-screen must be one of ${APP_SCREENS.join(', ')}`);
    }
    if (key === '--at') {
      at = true;
      if (!val || !val.split(',').every((s) => s.trim() !== '' && Number.isFinite(Number(s)) && Number(s) >= 0)) {
        return fail(`--at needs sim seconds >= 0 separated by commas, got "${val ?? ''}"`);
      }
    }
    o.userArgs.push(a);
  }
  const modes = [game, scene, app].filter(Boolean).length;
  if (modes !== 1) return fail('give exactly one of --game=<id> (with --at), --scene=<res path> or --app-screen=title|picker|lobby|session');
  if (game && !at) return fail('--game needs --at=<sim seconds>[,<s>...]');
  o.mode = game ? 'game' : scene ? 'scene' : 'app';
  return o;
}

function onPath(name, env) {
  for (const dir of (env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    try {
      if (fs.statSync(path.join(dir, name)).isFile()) return true;
    } catch {
      // keep looking
    }
  }
  return false;
}

/**
 * How Godot can show a window here: {kind: "native" | "xvfb" | "none", reason}.
 * WATTLANDS_SCREENSHOT_NO_DISPLAY=1 forces "none" (tests, CI without a display).
 */
export function detectDisplay(env = process.env, platform = process.platform, hasXvfb = () => onPath('xvfb-run', env)) {
  if (env.WATTLANDS_SCREENSHOT_NO_DISPLAY === '1') return { kind: 'none', reason: 'WATTLANDS_SCREENSHOT_NO_DISPLAY=1' };
  if (platform === 'win32' || platform === 'darwin') return { kind: 'native', reason: platform };
  if (env.DISPLAY || env.WAYLAND_DISPLAY) return { kind: 'native', reason: env.DISPLAY ? `DISPLAY=${env.DISPLAY}` : 'WAYLAND_DISPLAY' };
  if (hasXvfb()) return { kind: 'xvfb', reason: 'no DISPLAY; using xvfb-run' };
  return { kind: 'none', reason: 'no DISPLAY and no xvfb-run' };
}

/** The Godot command for parsed options: {cmd, args, env}. */
export function buildCommand(o, display, { repo = REPO, env = process.env, platform = process.platform, bash = null, powershell = null } = {}) {
  const shell = o.shell ?? (platform === 'win32' && !(bash ?? findBash()) ? 'ps' : 'bash');
  const godotArgs = [`--timeout=${o.timeoutS}`];
  if (o.lockTimeoutS !== null) godotArgs.push(`--lock-timeout=${o.lockTimeoutS}`);
  godotArgs.push('--path', slash(repo), '--resolution', o.size, '-s', ENTRY, '--', `--mock-trainer=${o.mockTrainer}`, ...o.userArgs);
  let cmd;
  let args;
  if (shell === 'ps') {
    const sys = env.SystemRoot || env.windir || 'C:\\Windows';
    cmd = powershell ?? path.join(sys, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
    args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(repo, 'tools', 'godot.ps1'), ...godotArgs];
  } else {
    cmd = bash ?? findBash() ?? 'bash';
    args = [slash(path.join(repo, 'tools', 'godot.sh')), ...godotArgs];
  }
  const extra = {};
  if (display.kind === 'xvfb') {
    args = ['-a', '-s', `-screen 0 ${o.size}x24`, cmd, ...args];
    cmd = 'xvfb-run';
    extra.LIBGL_ALWAYS_SOFTWARE = '1';
  }
  return { cmd, args, env: childEnv(env, extra), shell };
}

export async function main(argv, { stdout = process.stdout, stderr = process.stderr } = {}) {
  const o = parseScreenshotArgs(argv);
  if (o.help) {
    stdout.write(`${USAGE}\n`);
    return 0;
  }
  if (!o.ok) {
    stderr.write(`screenshot: ${o.error}\n${USAGE}\n`);
    return 2;
  }
  const display = detectDisplay();
  if (display.kind === 'none') {
    stdout.write(`${SKIPPED_MESSAGE} [${display.reason}]\n`);
    return 0;
  }
  const { cmd, args, env, shell } = buildCommand(o, display);
  if (o.dryRun) {
    stdout.write(`${JSON.stringify({ cmd, args, shell, display: display.kind, mode: o.mode })}\n`);
    return 0;
  }
  return await new Promise((resolve) => {
    const child = spawn(cmd, args, { cwd: REPO, env, stdio: ['ignore', 'inherit', 'inherit'] });
    const stop = () => killTree(child.pid);
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
    child.on('error', (e) => {
      stderr.write(`screenshot: cannot start ${cmd}: ${e.code || e.message}\n`);
      resolve(127);
    });
    child.on('exit', (code, signal) => resolve(code ?? (signal ? 130 : 1)));
  });
}

function isMain() {
  if (!process.argv[1]) return false;
  const norm = (p) => {
    let r = path.resolve(p);
    try {
      r = fs.realpathSync(r);
    } catch {
      // keep resolved path
    }
    return process.platform === 'win32' ? r.toLowerCase() : r;
  };
  return norm(process.argv[1]) === norm(fileURLToPath(import.meta.url));
}

if (isMain()) {
  main(process.argv.slice(2)).then((code) => process.exit(code));
}
