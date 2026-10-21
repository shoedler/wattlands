// tools/tests/screenshot.test.mjs (qa): tools/screenshot, tools/screenshot.ps1 and their Node core
// tools/qa/screenshot.mjs: argument parsing, the refusals (no mock trainer, lock drops, headless,
// debugger), display detection (xvfb-run, skip), the Godot command through the wrappers, and both
// shims end to end with --dry-run. No Godot process is started here.
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { ENTRY, SKIPPED_MESSAGE, buildCommand, detectDisplay, parseScreenshotArgs } from '../qa/screenshot.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const IS_WIN = process.platform === 'win32';

function findBash() {
  if (!IS_WIN) return '/bin/bash';
  for (const c of ['C:\\Program Files\\Git\\usr\\bin\\bash.exe', 'C:\\Program Files\\Git\\bin\\bash.exe']) {
    try {
      if (spawnSync(c, ['-c', 'exit 0']).status === 0) return c;
    } catch {
      // next
    }
  }
  return null;
}

test('game mode needs --at; exactly one mode', () => {
  assert.equal(parseScreenshotArgs(['--game=siege', '--at=60,360']).ok, true);
  assert.equal(parseScreenshotArgs(['--game=siege', '--at=60,360']).mode, 'game');
  assert.match(parseScreenshotArgs(['--game=siege']).error, /--game needs --at/);
  assert.match(parseScreenshotArgs([]).error, /exactly one of/);
  assert.match(parseScreenshotArgs(['--game=a', '--at=1', '--scene=res://x.tscn']).error, /exactly one of/);
  assert.equal(parseScreenshotArgs(['--scene=res://addons/wattlands/world2d/demo.tscn']).mode, 'scene');
  assert.equal(parseScreenshotArgs(['--app-screen=lobby']).mode, 'app');
  assert.match(parseScreenshotArgs(['--app-screen=settings']).error, /title, picker, lobby/);
});

test('--at takes sim seconds separated by commas', () => {
  assert.equal(parseScreenshotArgs(['--game=g', '--at=0,90.5,1500']).ok, true);
  for (const bad of ['--at=', '--at=-1', '--at=1,,2', '--at=soon', '--at']) {
    assert.equal(parseScreenshotArgs(['--game=g', bad]).ok, false, bad);
  }
});

test('every run_game_sim flag passes through untouched, in order', () => {
  const flags = ['--game=tank', '--content=ashfall_road', '--at=60,400', '--players=3', '--bots=1', '--rider=erg', '--rider=erg+cadence_drop:rpm=30,at_phase=4,after_s=20,for_s=30', '--autopilot=none', '--seed=7', '--ftp=180,220', '--unverified', '--options={"rotation":true}', '--out=build/x'];
  const o = parseScreenshotArgs(flags);
  assert.equal(o.ok, true, o.error);
  assert.deepEqual(o.userArgs, flags);
});

test('wrapper flags are consumed', () => {
  const o = parseScreenshotArgs(['--game=g', '--at=1', '--mock-trainer=erg:compliance=0.9', '--size=1280x720', '--timeout=60', '--lock-timeout=30', '--dry-run', '--shell=ps']);
  assert.equal(o.ok, true, o.error);
  assert.equal(o.mockTrainer, 'erg:compliance=0.9');
  assert.equal(o.size, '1280x720');
  assert.equal(o.timeoutS, 60);
  assert.equal(o.lockTimeoutS, 30);
  assert.equal(o.dryRun, true);
  assert.equal(o.shell, 'ps');
  assert.deepEqual(o.userArgs, ['--game=g', '--at=1']);
  assert.equal(parseScreenshotArgs(['--game=g', '--at=1', '--size=big']).ok, false);
  assert.equal(parseScreenshotArgs(['--game=g', '--at=1', '--timeout=0']).ok, false);
});

test('refusals: no mock trainer, lock drops, debugger, headless', () => {
  for (const v of ['none', '', 'real', 'OFF']) {
    assert.match(parseScreenshotArgs(['--game=g', '--at=1', `--mock-trainer=${v}`]).error, /without a mock trainer/, v);
  }
  assert.match(parseScreenshotArgs(['--game=g', '--at=1', '--allow-hw']).error, /never drop/);
  assert.match(parseScreenshotArgs(['--game=g', '--at=1', '--allow-network']).error, /never drop/);
  assert.match(parseScreenshotArgs(['--game=g', '--at=1', '-d']).error, /debugger/);
  assert.match(parseScreenshotArgs(['--game=g', '--at=1', '--headless']).error, /windowed/);
  assert.match(parseScreenshotArgs(['--game=g', '--at=1', 'stray']).error, /unexpected argument/);
});

test('display detection', () => {
  assert.equal(detectDisplay({}, 'win32').kind, 'native');
  assert.equal(detectDisplay({ DISPLAY: ':0' }, 'linux').kind, 'native');
  assert.equal(detectDisplay({ WAYLAND_DISPLAY: 'wayland-0' }, 'linux').kind, 'native');
  assert.equal(detectDisplay({}, 'linux', () => true).kind, 'xvfb');
  assert.equal(detectDisplay({}, 'linux', () => false).kind, 'none');
  assert.equal(detectDisplay({ WATTLANDS_SCREENSHOT_NO_DISPLAY: '1' }, 'win32').kind, 'none');
});

test('the Godot command: windowed, through the wrapper, mock trainer first', () => {
  const o = parseScreenshotArgs(['--game=g', '--at=5']);
  const { cmd, args, env } = buildCommand(o, { kind: 'native' }, { repo: '/r', env: { FAL_KEY: 'x', WATTLANDS_ALLOW_ART: '1', PATH: 'p' }, platform: 'linux', bash: '/bin/bash' });
  assert.equal(cmd, '/bin/bash');
  assert.equal(args[0], '/r/tools/godot.sh');
  assert.ok(!args.includes('--headless'));
  assert.equal(args[args.indexOf('-s') + 1], ENTRY);
  assert.equal(args[args.indexOf('--resolution') + 1], '1920x1080');
  assert.equal(args[args.indexOf('--path') + 1], '/r');
  assert.ok(args.includes('--timeout=900'));
  const sep = args.indexOf('--');
  assert.deepEqual(args.slice(sep + 1), ['--mock-trainer=erg:compliance=1.0', '--game=g', '--at=5']);
  assert.equal(env.FAL_KEY, undefined);
  assert.equal(env.WATTLANDS_ALLOW_ART, undefined);
  assert.equal(env.WATTLANDS_NO_HW_CONTROL, '1');
  assert.equal(env.WATTLANDS_NO_NETWORK_INTEGRATIONS, '1');
});

test('the PowerShell twin runs tools/godot.ps1 with -File', () => {
  const o = parseScreenshotArgs(['--scene=res://a/b.tscn', '--shell=ps']);
  const { cmd, args } = buildCommand(o, { kind: 'native' }, { repo: 'C:\\r', env: { SystemRoot: 'C:\\Windows' }, platform: 'win32' });
  assert.match(cmd, /powershell\.exe$/i);
  assert.deepEqual(args.slice(0, 4), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File']);
  assert.match(args[4], /godot\.ps1$/);
  assert.ok(args.includes('--lock-timeout=30') === false);
});

test('under xvfb-run the command is wrapped with a screen of the capture size', () => {
  const o = parseScreenshotArgs(['--app-screen=title', '--size=1280x720']);
  const { cmd, args, env } = buildCommand(o, { kind: 'xvfb' }, { repo: '/r', env: {}, platform: 'linux', bash: '/bin/bash' });
  assert.equal(cmd, 'xvfb-run');
  assert.deepEqual(args.slice(0, 4), ['-a', '-s', '-screen 0 1280x720x24', '/bin/bash']);
  assert.equal(env.LIBGL_ALWAYS_SOFTWARE, '1');
});

const BASH = findBash();

test('tools/screenshot (bash) end to end with --dry-run', { skip: BASH ? false : 'no bash' }, () => {
  const r = spawnSync(BASH, [path.join(REPO, 'tools', 'screenshot').replaceAll('\\', '/'), '--game=siege', '--content=short', '--at=60', '--players=4', '--dry-run'], { encoding: 'utf8', env: { ...process.env, WATTLANDS_SCREENSHOT_NO_DISPLAY: '', DISPLAY: process.env.DISPLAY || ':99' } });
  assert.equal(r.status, 0, r.stderr);
  const plan = JSON.parse(r.stdout.trim().split('\n').pop());
  assert.equal(plan.shell, 'bash');
  assert.equal(plan.mode, 'game');
  const sep = plan.args.indexOf('--');
  assert.deepEqual(plan.args.slice(sep + 1), ['--mock-trainer=erg:compliance=1.0', '--game=siege', '--content=short', '--at=60', '--players=4']);
});

test('tools/screenshot refuses bad flags with exit 2 and skips without a display', { skip: BASH ? false : 'no bash' }, () => {
  const script = path.join(REPO, 'tools', 'screenshot').replaceAll('\\', '/');
  const bad = spawnSync(BASH, [script, '--game=siege'], { encoding: 'utf8' });
  assert.equal(bad.status, 2);
  assert.match(bad.stderr, /--game needs --at/);
  const noMock = spawnSync(BASH, [script, '--app-screen=title', '--mock-trainer=none'], { encoding: 'utf8' });
  assert.equal(noMock.status, 2);
  const skipped = spawnSync(BASH, [script, '--app-screen=title'], { encoding: 'utf8', env: { ...process.env, WATTLANDS_SCREENSHOT_NO_DISPLAY: '1' } });
  assert.equal(skipped.status, 0);
  assert.ok(skipped.stdout.includes(SKIPPED_MESSAGE));
  const help = spawnSync(BASH, [script, '--help'], { encoding: 'utf8' });
  assert.equal(help.status, 0);
  assert.match(help.stdout, /usage: tools\/screenshot/);
});

test('tools/screenshot.ps1 end to end with --dry-run', { skip: IS_WIN ? false : 'Windows only' }, () => {
  const sys = process.env.SystemRoot || 'C:\\Windows';
  const ps = path.join(sys, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  const r = spawnSync(ps, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(REPO, 'tools', 'screenshot.ps1'), '--scene=res://addons/wattlands/world3d/demo.tscn', '--frames=10', '--dry-run'], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const plan = JSON.parse(r.stdout.trim().split(/\r?\n/).pop());
  assert.equal(plan.shell, 'ps');
  assert.equal(plan.mode, 'scene');
  assert.ok(plan.args.some((a) => /godot\.ps1$/.test(a)));
  const sep = plan.args.indexOf('--');
  assert.deepEqual(plan.args.slice(sep + 1), ['--mock-trainer=erg:compliance=1.0', '--scene=res://addons/wattlands/world3d/demo.tscn', '--frames=10']);
  const bad = spawnSync(ps, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(REPO, 'tools', 'screenshot.ps1'), '--allow-hw', '--app-screen=title'], { encoding: 'utf8' });
  assert.equal(bad.status, 2);
});
