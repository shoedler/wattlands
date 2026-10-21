// tools/tests/export_windows.test.mjs (platform): the pure part of tools/export_windows.mjs (W4fin,
// DoD 2): argument parsing, --relay-url validation, the override.cfg text and the smoke run's
// relay check, plus --help and the refusals end to end (both exit before Godot is probed). No Godot
// process is started and nothing is exported here.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { REPO, TOOLS } from './helpers.mjs';
import {
  BUILT_IN_RELAY_URL, RELAY_KEY, RELAY_LOG_PREFIX, RELAY_SECTION, USAGE, checkSmokeRelay, overrideCfg, parseExportArgs, parseRelayUrl, relayOverride,
} from '../export_windows.mjs';

const SCRIPT = path.join(TOOLS, 'export_windows.mjs');
const SETTINGS_GD = path.join(REPO, 'addons', 'wattlands', 'core', 'settings.gd');

function run(args) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000, env: { ...process.env, GODOT: 'wattlands-no-such-godot' } });
}

test('the setting matches the one Settings reads', () => {
  assert.equal(`${RELAY_SECTION}/${RELAY_KEY}`, 'wattlands/net/default_relay_url');
  assert.equal(RELAY_LOG_PREFIX, 'Settings: build default relay URL ');
  assert.equal(BUILT_IN_RELAY_URL, 'ws://localhost:8787/v1');
  const gd = fs.readFileSync(SETTINGS_GD, 'utf8');
  assert.ok(gd.includes(`const DEFAULT_RELAY_SETTING := "${RELAY_SECTION}/${RELAY_KEY}"`), 'settings.gd reads the same setting');
  assert.ok(gd.includes(`"relay_url": "${BUILT_IN_RELAY_URL}",`), 'settings.gd has the same built-in default');
  assert.ok(gd.includes(`print("${RELAY_LOG_PREFIX}%s" % relay_default)`), 'settings.gd prints the same line');
});

test('--relay-url with the built-in default parses but writes no override.cfg', () => {
  const opts = parseExportArgs([`--relay-url=${BUILT_IN_RELAY_URL}`, '--smoke']);
  assert.equal(opts.ok, true);
  assert.equal(opts.relayUrl, 'ws://localhost:8787/v1');
  assert.deepEqual(relayOverride(opts.relayUrl), {
    write: false,
    note: 'default relay URL ws://localhost:8787/v1 is already the built-in default; no override.cfg written',
  });
  assert.deepEqual(relayOverride(parseExportArgs([]).relayUrl), { write: false, note: null }, 'no --relay-url: nothing to write or say');
  const url = 'ws://192.0.2.10:8787/v1';
  assert.deepEqual(relayOverride(url), { write: true, text: overrideCfg(url), note: 'default relay URL ws://192.0.2.10:8787/v1 (override.cfg)' });
  // Settings compares the exact text, so any other spelling is another default and gets the file.
  for (const other of ['ws://localhost:8787/v1/', 'ws://127.0.0.1:8787/v1', 'wss://localhost:8787/v1', 'ws://localhost:8788/v1']) {
    assert.equal(relayOverride(other).write, true, other);
  }
});

test('--relay-url accepts ws:// and wss:// URLs with a host, unchanged', () => {
  for (const u of [
    'ws://192.0.2.10:8787/v1',
    'wss://relay.example.org/v1',
    'wss://relay.example.org',
    'ws://localhost:8787/v1',
    'ws://[::1]:8787/v1',
    'ws://[2001:db8::1]/v1',
    'wss://relay.example.org:443/v1?region=eu',
  ]) {
    assert.deepEqual(parseRelayUrl(u), { ok: true, url: u }, u);
  }
});

test('--relay-url refuses everything else', () => {
  const cases = [
    ['', /needs a value/],
    [true, /needs a value/],
    ['http://relay.example.org/v1', /must start with ws:\/\/ or wss:\/\//],
    ['https://relay.example.org/v1', /must start with ws:\/\/ or wss:\/\//],
    ['WS://relay.example.org/v1', /must start with ws:\/\/ or wss:\/\//],
    ['relay.example.org:8787/v1', /must start with ws:\/\/ or wss:\/\//],
    ['ws:relay.example.org', /must start with ws:\/\/ or wss:\/\//],
    ['ws://', /not a URL|needs a host/],
    ['ws:///v1', /not a URL|needs a host/],
    ['wss://:8787/v1', /not a URL|needs a host/],
    ['ws://relay.example.org:99999/v1', /not a URL/],
    ['ws://bad host/v1', /spaces/],
    [' ws://relay.example.org/v1', /must start with/],
    ['ws://relay.example.org/v1 ', /spaces/],
    ['ws://relay.example.org/v1\n[application]', /control characters/],
    ['ws://relay.example.org/"v1', /quotes/],
    ['ws://relay.example.org\\v1', /backslashes/],
    ['ws://user:secret@relay.example.org/v1', /user name or password/],
    ['ws://user@relay.example.org/v1', /user name or password/],
    ['ws://relay.example.org/v1#x', /fragment/],
  ];
  for (const [value, why] of cases) {
    const r = parseRelayUrl(value);
    assert.equal(r.ok, false, JSON.stringify(value));
    assert.match(r.error, why, JSON.stringify(value));
  }
});

test('override.cfg sets [wattlands] net/default_relay_url and nothing else', () => {
  const text = overrideCfg('ws://192.0.2.10:8787/v1');
  const lines = text.split('\n').filter((l) => l !== '' && !l.startsWith(';'));
  assert.deepEqual(lines, ['[wattlands]', 'net/default_relay_url="ws://192.0.2.10:8787/v1"']);
  assert.ok(text.endsWith('\n'));
  assert.ok(!text.includes('\r'));
  assert.match(text.split('\n')[0], /^; Written by tools\/export_windows\.mjs --relay-url/);
  assert.throws(() => overrideCfg('http://relay.example.org/v1'), /ws:\/\/ or wss:\/\//);
  assert.throws(() => overrideCfg('ws://x/"\n[application]\nrun/main_scene="res://evil.tscn'), /quotes|control/);
});

test('the export options parse; unknown or malformed ones are refused', () => {
  assert.deepEqual(parseExportArgs([]), { ok: true, help: false, out: 'build/windows', template: '', withVcruntime: false, relayUrl: null, smoke: false });
  assert.deepEqual(parseExportArgs(['--out=build/x', '--template=C:/t.exe', '--with-vcruntime', '--relay-url=wss://relay.example.org/v1', '--smoke']), {
    ok: true, help: false, out: 'build/x', template: 'C:/t.exe', withVcruntime: true, relayUrl: 'wss://relay.example.org/v1', smoke: true,
  });
  assert.equal(parseExportArgs(['--help']).help, true);
  assert.equal(parseExportArgs(['-h']).help, true);
  for (const [args, why] of [
    [['--relay-url'], /--relay-url needs a value/],
    [['--relay-url='], /--relay-url needs a value/],
    [['--relay-url=http://relay.example.org/v1'], /ws:\/\/ or wss:\/\//],
    [['--relay=ws://relay.example.org/v1'], /unknown option "--relay=ws:\/\/relay.example.org\/v1"/],
    [['--smoke=yes'], /--smoke takes no value/],
    [['--with-vcruntime=1'], /takes no value/],
    [['--out'], /--out needs a value/],
    [['--template='], /--template needs a value/],
    [['build/windows'], /unknown option/],
  ]) {
    const r = parseExportArgs(args);
    assert.equal(r.ok, false, args.join(' '));
    assert.match(r.error, why, args.join(' '));
  }
});

test('the smoke check wants exactly the default relay URL this export set', () => {
  const url = 'ws://192.0.2.10:8787/v1';
  const log = `Godot Engine v4.7.2\r\n${RELAY_LOG_PREFIX}${url}\r\nTrainerService: mock erg\r\n`;
  assert.deepEqual(checkSmokeRelay(log, url), { ok: true, line: `${RELAY_LOG_PREFIX}${url}` });
  assert.match(checkSmokeRelay('Godot Engine v4.7.2\n', url).error, /did not report the default relay URL ws:\/\/192\.0\.2\.10:8787\/v1 \(saw none\)/);
  assert.match(checkSmokeRelay(`${RELAY_LOG_PREFIX}wss://other.example/v1\n`, url).error, /saw wss:\/\/other\.example\/v1/);
  assert.match(checkSmokeRelay(`${RELAY_LOG_PREFIX}${url}\n${RELAY_LOG_PREFIX}wss://other.example/v1\n`, url).error, /another default relay URL/);
  assert.deepEqual(checkSmokeRelay('Godot Engine v4.7.2\n', null), { ok: true, line: 'default relay URL ws://localhost:8787/v1 (built in)' }, 'no --relay-url: the built-in default prints nothing');
  assert.match(checkSmokeRelay(`${RELAY_LOG_PREFIX}${url}\n`, null).error, /built-in default relay URL reported another one: ws:\/\/192\.0\.2\.10:8787\/v1/);
});

test('the smoke check wants no relay line after --relay-url with the built-in default', () => {
  const log = 'Godot Engine v4.7.2\r\nTrainerService: mock erg\r\n';
  assert.deepEqual(checkSmokeRelay(log, BUILT_IN_RELAY_URL), { ok: true, line: 'default relay URL ws://localhost:8787/v1 (built in)' });
  assert.match(checkSmokeRelay(`${RELAY_LOG_PREFIX}ws://192.0.2.10:8787/v1\n`, BUILT_IN_RELAY_URL).error, /built-in default relay URL reported another one: ws:\/\/192\.0\.2\.10:8787\/v1/);
  assert.equal(checkSmokeRelay(`${RELAY_LOG_PREFIX}${BUILT_IN_RELAY_URL}\n`, BUILT_IN_RELAY_URL).ok, false, 'Settings never prints the built-in default');
});

test('--help prints the usage with --relay-url and exits 0 before looking for Godot', () => {
  const r = run(['--help']);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), USAGE.trim());
  assert.match(r.stdout, /--relay-url=<url>/);
  assert.match(r.stdout, /override\.cfg/);
  assert.match(r.stdout, /net\/default_relay_url="<url>"/);
  assert.match(r.stdout, /or with the built-in ws:\/\/localhost:8787\/v1 itself \(no override\.cfg is\s+written then\)/);
});

test('a bad --relay-url or an unknown option exits 2 with the usage and builds nothing', () => {
  for (const args of [['--relay-url=http://relay.example.org/v1', '--smoke'], ['--relay-url=ws://'], ['--relay=ws://relay.example.org/v1']]) {
    const r = run(args);
    assert.equal(r.status, 2, `${args.join(' ')}: ${r.stderr}`);
    assert.match(r.stderr, /^export_windows: /);
    assert.match(r.stderr, /usage: node tools\/export_windows\.mjs/);
    assert.doesNotMatch(r.stderr + r.stdout, /cannot run Godot/, 'refused before probing Godot');
  }
});
