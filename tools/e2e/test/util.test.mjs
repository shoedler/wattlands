// node:test for tools/e2e/lib/util.mjs and the peer command line in tools/e2e/lib/game.mjs.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { childEnv, getFreePort, redact, slash, substitute, tokenize, resolveProgram } from '../lib/util.mjs';
import { parseArgs, VICTIM } from '../lib/args.mjs';
import { peerCommand, peerUserArgs, readManifest } from '../lib/game.mjs';

test('tokenize splits like a shell for plain words and quotes', () => {
  assert.deepEqual(tokenize('node server/relay/src/main.ts'), ['node', 'server/relay/src/main.ts']);
  assert.deepEqual(tokenize('  a   b\tc '), ['a', 'b', 'c']);
  assert.deepEqual(tokenize('node "C:/Program Files/x.mjs" --a="b c"'), ['node', 'C:/Program Files/x.mjs', '--a=b c']);
  assert.deepEqual(tokenize("node 'it''s'"), ['node', 'its']);
  assert.deepEqual(tokenize('node C:\\tools\\x.mjs'), ['node', 'C:\\tools\\x.mjs']);
  assert.deepEqual(tokenize('a\\ b'), ['a b']);
  assert.deepEqual(tokenize('""'), ['']);
  assert.throws(() => tokenize('node "open'), /unterminated/);
});

test('substitute replaces {port} and leaves unknown placeholders', () => {
  assert.deepEqual(substitute(['--port={port}', '{x}'], { port: 81 }), ['--port=81', '{x}']);
});

test('resolveProgram runs node as this Node', () => {
  assert.equal(resolveProgram('node'), process.execPath);
  assert.equal(resolveProgram('bash'), 'bash');
});

test('childEnv drops the art variables in any case and sets both locks', () => {
  const env = childEnv({ PATH: 'p', FAL_KEY: 'secret', fal_key: 'x', WATTLANDS_ALLOW_ART: '1', WATTLANDS_NO_HW_CONTROL: '0', wattlands_no_hw_control: '0', KEEP: 'k' }, { EXTRA: 'e' });
  assert.equal(env.FAL_KEY, undefined);
  assert.equal(env.fal_key, undefined);
  assert.equal(env.WATTLANDS_ALLOW_ART, undefined);
  assert.equal(env.wattlands_no_hw_control, undefined);
  assert.equal(env.WATTLANDS_NO_HW_CONTROL, '1');
  assert.equal(env.WATTLANDS_NO_NETWORK_INTEGRATIONS, '1');
  assert.equal(env.KEEP, 'k');
  assert.equal(env.EXTRA, 'e');
  assert.equal(env.PATH, 'p');
});

test('redact masks secrets and tokens', () => {
  assert.deepEqual(redact(['--strava-client-secret=abc', '--strava-client-id=1', '--token=x', '--a=b']), ['--strava-client-secret=***', '--strava-client-id=1', '--token=***', '--a=b']);
});

test('getFreePort returns a usable port', async () => {
  const p = await getFreePort();
  assert.ok(Number.isInteger(p) && p > 0 && p < 65536);
});

test('slash uses forward slashes', () => {
  assert.equal(slash('C:\\a\\b'), 'C:/a/b');
});

test('peer flags follow the scripted-peer contract', () => {
  const o = parseArgs(['--games=workout', '--seed=5']).opts;
  const ctx = { gameId: 'workout', content: 'e2e', code: 'K7QX2M', relayUrl: 'ws://127.0.0.1:1234/v1', stravaBase: 'http://127.0.0.1:99', profileDir: 'C:/x/host/profile', reportPath: 'C:/x/host/report.json' };
  const host = peerUserArgs(o, 'host', ctx);
  assert.equal(host[0], '--host');
  assert.equal(host[1], '--content=e2e', 'the host plays the e2e_content explicitly');
  for (const f of ['--game=workout', '--e2e', '--wait-peers=3', '--relay=ws://127.0.0.1:1234/v1', '--mock-trainer=erg:compliance=1.0', '--autopilot', '--profile-dir=C:/x/host/profile', '--sim-speed=1', '--seed=5', '--report=C:/x/host/report.json', '--strava-base=http://127.0.0.1:99']) {
    assert.ok(host.includes(f), f);
  }
  assert.ok(!host.some((a) => a.startsWith('--strava-client')), 'auto-upload is client1 by default');
  const c1 = peerUserArgs(o, 'client1', ctx);
  assert.equal(c1[0], '--join=K7QX2M');
  assert.ok(!c1.some((a) => a.startsWith('--content=')), 'the host chooses the content');
  assert.ok(c1.includes('--strava-auto-upload'));
  assert.ok(c1.some((a) => a.startsWith('--strava-client-id=')));
  assert.ok(c1.some((a) => a.startsWith('--strava-client-secret=')));
  const c2 = peerUserArgs(o, VICTIM, ctx);
  assert.ok(!c2.includes('--strava-auto-upload'));
  assert.ok(!c2.includes('--host'));
});

test('peers start through tools/godot.sh inside the lease with their own log file', () => {
  const o = parseArgs(['--games=workout']).opts;
  const { cmd, args, env } = peerCommand(o, ['--host'], { godotLog: 'C:/x/godot.log', lease: { token: '7:/tmp/lock' } });
  assert.match(cmd, /bash/);
  assert.match(args[0], /tools\/godot\.sh$/);
  assert.ok(args.includes('--headless'));
  assert.ok(args.includes(`--timeout=${o.peerTimeoutS}`));
  const lf = args.indexOf('--log-file');
  assert.equal(args[lf + 1], 'C:/x/godot.log');
  const sep = args.indexOf('--');
  assert.ok(lf < sep, '--log-file is a Godot argument, before --');
  assert.deepEqual(args.slice(sep + 1), ['--host']);
  assert.equal(args[args.indexOf('--path') + 1], slash(o.repo));
  assert.ok(!args.includes('-d') && !args.includes('--debug'));
  assert.equal(env.WATTLANDS_GODOT_LEASE_TOKEN, '7:/tmp/lock');
});

test('--peer-cmd replaces Godot for harness tests', () => {
  const o = parseArgs(['--games=workout', '--peer-cmd=node fake.mjs']).opts;
  const { cmd, args } = peerCommand(o, ['--host'], { godotLog: 'g.log', lease: null });
  assert.equal(cmd, process.execPath);
  assert.deepEqual(args, ['fake.mjs', '--', '--host']);
});

test('readManifest needs an e2e_content', () => {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-e2e-manifest-'));
  try {
    assert.equal(readManifest(repo, 'nope').ok, false);
    fs.mkdirSync(path.join(repo, 'src', 'games', 'g'), { recursive: true });
    fs.writeFileSync(path.join(repo, 'src', 'games', 'g', 'game.json'), JSON.stringify({ id: 'g' }));
    assert.match(readManifest(repo, 'g').error, /no e2e_content/);
    fs.writeFileSync(path.join(repo, 'src', 'games', 'g', 'game.json'), JSON.stringify({ id: 'g', e2e_content: 'e2e' }));
    assert.equal(readManifest(repo, 'g').content, 'e2e');
    fs.writeFileSync(path.join(repo, 'src', 'games', 'g', 'game.json'), '{oops');
    assert.equal(readManifest(repo, 'g').ok, false);
  } finally {
    fs.rmSync(repo, { recursive: true, force: true });
  }
});
