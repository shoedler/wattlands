#!/usr/bin/env node
// tools/export_windows.mjs: builds the Windows Desktop export into build/windows/ (BRIEF 7.10).
//
//   node tools/export_windows.mjs [--out=<dir>] [--template=<windows_release_x86_64.exe>]
//                                 [--with-vcruntime] [--relay-url=<ws:// or wss:// url>] [--smoke]
//
// Exports from a clean copy of the tracked tree (git ls-files) in build/export_src, so the
// working tree is never touched. With a standard Godot editor the preset's empty
// custom_template uses the installed export templates. The .NET editor looks for .NET
// templates, so the copy's preset points custom_template at the standard template
// (--template, or %APPDATA%/Godot/export_templates/<version>.stable/windows_release_x86_64.exe).
// Next to the exe it writes LICENSE, CREDITS.md and THIRD_PARTY_NOTICES.txt. --with-vcruntime
// copies vcruntime140.dll (and vcruntime140_1.dll if present) from System32 next to the exe
// (app-local deployment of the Visual C++ runtime that the GDBLE DLL imports). --relay-url
// writes override.cfg next to the exe with [wattlands] net/default_relay_url="<url>"; Godot
// reads override.cfg from the folder of the exe and .pck at startup, and Settings uses that
// project setting as the default relay URL (a rider's own choice and --relay=<url> still win),
// so a friend's copy needs only the room code. The built-in ws://localhost:8787/v1 needs no
// override.cfg, so --relay-url with exactly that value writes none and says so. --smoke starts
// the exported app headless with a mock trainer for a few seconds (it hosts and joins nothing, so
// it connects to no relay) and fails on a non-zero exit, a script error, or a default relay URL
// other than the one this export set (none for the built-in default). Godot runs go through
// tools/godot.sh's lock helper. Zero dependencies.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const TOOLS = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.dirname(TOOLS);

// The project setting Settings reads its default relay URL from (addons/wattlands/core/settings.gd).
export const RELAY_SECTION = 'wattlands';
export const RELAY_KEY = 'net/default_relay_url';
// The line Settings.load_all prints when the default relay URL is not the built-in one.
export const RELAY_LOG_PREFIX = 'Settings: build default relay URL ';
// Settings.DEFAULTS.relay_url. Settings prints no line for exactly this value, so no
// override.cfg is written for it and --smoke expects no line.
export const BUILT_IN_RELAY_URL = 'ws://localhost:8787/v1';

export const USAGE = `usage: node tools/export_windows.mjs [options]
  --out=<dir>            output folder (default build/windows; emptied first)
  --template=<exe>       windows_release_x86_64.exe export template (default: the installed
                         <version>.stable template when the editor is a .NET build)
  --with-vcruntime       copy vcruntime140.dll (and vcruntime140_1.dll) from System32 next to the exe
  --relay-url=<url>      the default relay URL of this build: a ws:// or wss:// URL with a host
                         (no spaces, quotes, backslashes, user name, password or #fragment), for
                         example wss://relay.example.org/v1 or ws://192.168.1.10:8787/v1. Writes
                         override.cfg next to the exe:
                           [${RELAY_SECTION}]
                           ${RELAY_KEY}="<url>"
                         Godot reads it at startup and Settings uses it as the default relay URL,
                         so a friend who runs this copy types only the room code. A relay URL the
                         rider set in Settings > Network and --relay=<url> still win. Without it,
                         or with the built-in ${BUILT_IN_RELAY_URL} itself (no override.cfg is
                         written then), the build keeps ${BUILT_IN_RELAY_URL}.
  --smoke                run the exported app headless with a mock trainer for 8 s (it hosts and
                         joins nothing, so it connects to no relay) and check the exit code, script
                         errors and the default relay URL the build reports
  -h, --help             show this help`;

// {ok, url} for a usable --relay-url value, else {ok: false, error}.
export function parseRelayUrl(value) {
  if (typeof value !== 'string' || value === '') return { ok: false, error: '--relay-url needs a value: --relay-url=<ws:// or wss:// url>' };
  if (!value.startsWith('ws://') && !value.startsWith('wss://')) return { ok: false, error: `--relay-url must start with ws:// or wss://, got "${value}"` };
  if (/[\s"\\\x00-\x1f\x7f]/.test(value)) return { ok: false, error: `--relay-url must not contain spaces, control characters, quotes or backslashes: "${value}"` };
  // The host as Settings reads it: between the scheme's // and the first / ? or # (the URL parser
  // alone would take "ws:///v1" as host "v1").
  const authority = value.slice(value.indexOf('//') + 2).split(/[/?#]/)[0];
  const hostPort = authority.slice(authority.lastIndexOf('@') + 1);
  if ((hostPort.startsWith('[') ? hostPort : hostPort.split(':')[0]) === '') return { ok: false, error: `--relay-url needs a host: "${value}"` };
  let u;
  try {
    u = new URL(value);
  } catch {
    return { ok: false, error: `--relay-url is not a URL: "${value}"` };
  }
  if (u.protocol !== 'ws:' && u.protocol !== 'wss:') return { ok: false, error: `--relay-url must be a ws:// or wss:// URL, got "${value}"` };
  if (!u.hostname) return { ok: false, error: `--relay-url needs a host: "${value}"` };
  if (u.username || u.password) return { ok: false, error: `--relay-url must not carry a user name or password: "${value}"` };
  if (value.includes('#')) return { ok: false, error: `--relay-url must not have a #fragment: "${value}"` };
  return { ok: true, url: value };
}

// The override.cfg text that sets this build's default relay URL (`url` from parseRelayUrl).
export function overrideCfg(url) {
  const r = parseRelayUrl(url);
  if (!r.ok) throw new Error(r.error);
  return [
    '; Written by tools/export_windows.mjs --relay-url. Godot reads override.cfg next to the exe at',
    '; startup; Settings uses this as the default relay URL (a rider\'s own choice and --relay win).',
    '',
    `[${RELAY_SECTION}]`,
    '',
    `${RELAY_KEY}="${r.url}"`,
    '',
  ].join('\n');
}

// What --relay-url (`relayUrl` from parseExportArgs) writes next to the exe: {write: true, text,
// note} for override.cfg, else {write: false, note}: note null without --relay-url, and a note
// that it already is the default for the built-in value.
export function relayOverride(relayUrl) {
  if (!relayUrl) return { write: false, note: null };
  if (relayUrl === BUILT_IN_RELAY_URL) {
    return { write: false, note: `default relay URL ${relayUrl} is already the built-in default; no override.cfg written` };
  }
  return { write: true, text: overrideCfg(relayUrl), note: `default relay URL ${relayUrl} (override.cfg)` };
}

// {ok, help, out, template, withVcruntime, relayUrl, smoke} or {ok: false, error}. Unknown
// options are refused, so a typo never builds a copy that silently keeps the localhost default.
export function parseExportArgs(argv) {
  const o = { ok: true, help: false, out: 'build/windows', template: '', withVcruntime: false, relayUrl: null, smoke: false };
  for (const a of argv) {
    const eq = a.indexOf('=');
    const name = eq >= 0 ? a.slice(0, eq) : a;
    const value = eq >= 0 ? a.slice(eq + 1) : null;
    const flag = (set) => {
      if (value !== null) return `${name} takes no value`;
      set();
      return null;
    };
    const valued = (set) => {
      if (value === null || value === '') return `${name} needs a value: ${name}=<...>`;
      set(value);
      return null;
    };
    let error = null;
    switch (name) {
      case '-h':
      case '--help':
        o.help = true;
        break;
      case '--out':
        error = valued((v) => { o.out = v; });
        break;
      case '--template':
        error = valued((v) => { o.template = v; });
        break;
      case '--with-vcruntime':
        error = flag(() => { o.withVcruntime = true; });
        break;
      case '--smoke':
        error = flag(() => { o.smoke = true; });
        break;
      case '--relay-url': {
        const r = parseRelayUrl(value === null ? '' : value);
        if (r.ok) o.relayUrl = r.url;
        else error = r.error;
        break;
      }
      default:
        error = `unknown option "${a}"`;
    }
    if (error) return { ok: false, error };
  }
  return o;
}

// Checks the smoke run's output for the default relay URL the build reports: `relayUrl` when
// --relay-url set one other than the built-in default, else none (the built-in default prints
// nothing).
export function checkSmokeRelay(output, relayUrl) {
  const seen = String(output).split(/\r?\n/).filter((l) => l.startsWith(RELAY_LOG_PREFIX)).map((l) => l.slice(RELAY_LOG_PREFIX.length).trim());
  if (relayUrl && relayUrl !== BUILT_IN_RELAY_URL) {
    if (!seen.includes(relayUrl)) return { ok: false, error: `the exported app did not report the default relay URL ${relayUrl} (saw ${seen.length ? seen.join(', ') : 'none'})` };
    if (seen.some((u) => u !== relayUrl)) return { ok: false, error: `the exported app reported another default relay URL: ${seen.join(', ')}` };
    return { ok: true, line: `${RELAY_LOG_PREFIX}${relayUrl}` };
  }
  if (seen.length) return { ok: false, error: `a build with the built-in default relay URL reported another one: ${seen.join(', ')}` };
  return { ok: true, line: `default relay URL ${BUILT_IN_RELAY_URL} (built in)` };
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

function main(argv) {
  const opts = parseExportArgs(argv);
  if (!opts.ok) die(`${opts.error}\n${USAGE}`, 2);
  if (opts.help) {
    process.stdout.write(`${USAGE}\n`);
    return;
  }
  const out = path.resolve(REPO, opts.out);
  const src = path.join(REPO, 'build', 'export_src');
  const bin = godotBin();
  const probe = spawnSync(bin, ['--version'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (probe.error || typeof probe.stdout !== 'string') die(`cannot run Godot at "${bin}" (set GODOT or tools/godot_bin.local)`, 127);
  const version = probe.stdout.trim();
  if (!version.startsWith('4.7')) die(`Godot 4.7 needed, got "${version}" from ${bin}`);
  const mono = version.includes('mono');
  const base = version.split('.').slice(0, 3).join('.'); // 4.7.2
  let template = opts.template;
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
  if (opts.withVcruntime) {
    const sys = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32');
    for (const dll of ['vcruntime140.dll', 'vcruntime140_1.dll']) {
      if (fs.existsSync(path.join(sys, dll))) fs.copyFileSync(path.join(sys, dll), path.join(out, dll));
    }
  }
  const relayCfg = relayOverride(opts.relayUrl);
  if (relayCfg.write) fs.writeFileSync(path.join(out, 'override.cfg'), relayCfg.text);
  if (relayCfg.note) process.stdout.write(`export_windows: ${relayCfg.note}\n`);
  const files = fs.readdirSync(out).sort();
  process.stdout.write(`export_windows: ${out}\n  ${files.join('\n  ')}\n`);
  if (!files.some((f) => /^libgdble\.windows\.x86_64\.dll$/i.test(f))) die('the GDBLE DLL was not exported next to the exe');

  if (opts.smoke) {
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
    const relay = checkSmokeRelay(r.out, opts.relayUrl);
    if (!relay.ok) die(`smoke run failed: ${relay.error}\n${r.out.slice(-3000)}`);
    process.stdout.write(`export_windows: smoke ${relay.line}\n`);
  }
  process.stdout.write('export_windows: done\n');
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

if (isMain()) main(process.argv.slice(2));
