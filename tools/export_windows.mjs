#!/usr/bin/env node
// tools/export_windows.mjs: builds the Windows Desktop export into build/windows/ (BRIEF 7.10).
//
//   node tools/export_windows.mjs [--out=<dir>] [--template=<windows_release_x86_64.exe>]
//                                 [--with-vcruntime] [--smoke]
//
// Exports from a clean copy of the tracked tree (git ls-files) in build/export_src, so the
// working tree is never touched. With a standard Godot editor the preset's empty
// custom_template uses the installed export templates. The .NET editor looks for .NET
// templates, so the copy's preset points custom_template at the standard template
// (--template, or %APPDATA%/Godot/export_templates/<version>.stable/windows_release_x86_64.exe).
// Next to the exe it writes LICENSE, CREDITS.md and THIRD_PARTY_NOTICES.txt. --with-vcruntime
// copies vcruntime140.dll (and vcruntime140_1.dll if present) from System32 next to the exe
// (app-local deployment of the Visual C++ runtime that the GDBLE DLL imports). --smoke starts the
// console exe headless with a mock trainer for a few seconds and fails on a non-zero exit.
// Godot runs go through tools/godot.sh's lock helper. Zero dependencies.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const TOOLS = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.dirname(TOOLS);

function arg(name, def = null) {
  const hit = process.argv.slice(2).find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  if (!hit) return def;
  return hit.includes('=') ? hit.slice(hit.indexOf('=') + 1) : true;
}

function die(msg, code = 1) {
  process.stderr.write(`export_windows: ${msg}\n`);
  process.exit(code);
}

function godotBin() {
  if (process.env.GODOT) return process.env.GODOT;
  for (const root of [REPO, path.dirname(spawnSync('git', ['rev-parse', '--git-common-dir'], { cwd: REPO, encoding: 'utf8' }).stdout.trim())]) {
    const f = path.join(root, 'tools', 'godot_bin.local');
    if (fs.existsSync(f)) return fs.readFileSync(f, 'utf8').split(/\r?\n/)[0].trim();
  }
  return 'godot';
}

function lockRun(args, opts = {}) {
  const r = spawnSync(process.execPath, [path.join(TOOLS, 'lib', 'godot_lock.mjs'), 'run', '--timeout=900', '--', ...args], {
    cwd: REPO, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...(opts.env || {}) }, maxBuffer: 64 * 1024 * 1024,
  });
  return { code: r.status, out: `${r.stdout}${r.stderr}` };
}

const out = path.resolve(REPO, arg('out', 'build/windows'));
const src = path.join(REPO, 'build', 'export_src');
const bin = godotBin();
const probe = spawnSync(bin, ['--version'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
if (probe.error || typeof probe.stdout !== 'string') die(`cannot run Godot at "${bin}" (set GODOT or tools/godot_bin.local)`, 127);
const version = probe.stdout.trim();
if (!version.startsWith('4.7')) die(`Godot 4.7 needed, got "${version}" from ${bin}`);
const mono = version.includes('mono');
const base = version.split('.').slice(0, 3).join('.'); // 4.7.2
let template = arg('template', '');
if (!template && mono) {
  const appdata = process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
  template = path.join(appdata, 'Godot', 'export_templates', `${base}.stable`, 'windows_release_x86_64.exe');
}
if (template && !fs.existsSync(template)) die(`export template not found: ${template} (install the ${base} export templates or pass --template)`);

fs.rmSync(src, { recursive: true, force: true });
const ls = spawnSync('git', ['ls-files', '-z'], { cwd: REPO, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
for (const f of ls.stdout.split('\0').filter(Boolean)) {
  const from = path.join(REPO, f);
  if (!fs.existsSync(from) || fs.statSync(from).isDirectory()) continue;
  fs.mkdirSync(path.dirname(path.join(src, f)), { recursive: true });
  fs.copyFileSync(from, path.join(src, f));
}
if (template) {
  const presets = path.join(src, 'export_presets.cfg');
  const t = template.replaceAll('\\', '/');
  const text = fs.readFileSync(presets, 'utf8')
    .replace('custom_template/debug=""', `custom_template/debug="${t}"`)
    .replace('custom_template/release=""', `custom_template/release="${t}"`);
  fs.writeFileSync(presets, text);
}
process.stdout.write(`export_windows: Godot ${version}${template ? `, template ${template}` : ''}\n`);
// Per-checkout user dir for the copy's import, like tools/godot.sh (BRIEF 2); the export itself
// uses an explicit template path, so it needs no installed-template lookup under APPDATA.
const userdata = path.join(src, '.userdata');
fs.mkdirSync(userdata, { recursive: true });
const userEnv = process.platform === 'win32' ? { APPDATA: userdata } : { XDG_DATA_HOME: userdata };
const imp = lockRun([bin, '--headless', '--path', src, '--import'], { env: userEnv });
if (imp.code !== 0) die(`import of the copy failed (exit ${imp.code})\n${imp.out.slice(-2000)}`);
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
const exe = path.join(out, 'Wattlands.exe');
const exp = lockRun([bin, '--headless', '--path', src, '--export-release', 'Windows Desktop', exe]);
if (exp.code !== 0 || !fs.existsSync(exe)) die(`export failed (exit ${exp.code})\n${exp.out.slice(-3000)}`);

fs.copyFileSync(path.join(REPO, 'LICENSE'), path.join(out, 'LICENSE.txt'));
fs.copyFileSync(path.join(REPO, 'CREDITS.md'), path.join(out, 'CREDITS.md'));
const notices = path.join(REPO, 'docs', 'THIRD_PARTY_NOTICES.txt');
if (fs.existsSync(notices)) fs.copyFileSync(notices, path.join(out, 'THIRD_PARTY_NOTICES.txt'));
if (arg('with-vcruntime')) {
  const sys = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32');
  for (const dll of ['vcruntime140.dll', 'vcruntime140_1.dll']) {
    if (fs.existsSync(path.join(sys, dll))) fs.copyFileSync(path.join(sys, dll), path.join(out, dll));
  }
}
const files = fs.readdirSync(out).sort();
process.stdout.write(`export_windows: ${out}\n  ${files.join('\n  ')}\n`);
if (!files.some((f) => /^libgdble\.windows\.x86_64\.dll$/i.test(f))) die('the GDBLE DLL was not exported next to the exe');

if (arg('smoke')) {
  const consoleExe = path.join(out, 'Wattlands.console.exe');
  const runExe = fs.existsSync(consoleExe) ? consoleExe : exe;
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands_smoke_'));
  const smokeData = path.join(profile, 'appdata');
  fs.mkdirSync(smokeData, { recursive: true });
  const r = lockRun([runExe, '--headless', '--', '--mock-trainer=erg', '--run-seconds=8', `--profile-dir=${profile}`], {
    env: { WATTLANDS_NO_HW_CONTROL: '1', WATTLANDS_NO_NETWORK_INTEGRATIONS: '1', ...(process.platform === 'win32' ? { APPDATA: smokeData } : { XDG_DATA_HOME: smokeData }) },
  });
  fs.rmSync(profile, { recursive: true, force: true });
  const errors = (r.out.match(/SCRIPT ERROR|Parse Error/g) || []).length;
  process.stdout.write(`export_windows: smoke run exit ${r.code}, ${errors} script errors\n`);
  if (r.code !== 0 || errors > 0) die(`smoke run failed\n${r.out.slice(-3000)}`);
}
process.stdout.write('export_windows: done\n');
