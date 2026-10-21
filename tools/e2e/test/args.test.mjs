// node:test for tools/e2e/lib/args.mjs: the harness's command line.
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { DEFAULTS, defaultRelayCmd, needsStripTypesFlag, parseArgs } from '../lib/args.mjs';
import { DEFAULT_REPO } from '../lib/util.mjs';

test('--games is required', () => {
  assert.equal(parseArgs([]).ok, false);
  assert.match(parseArgs([]).error, /--games/);
  assert.equal(parseArgs(['--games=']).ok, false);
});

test('a comma list of games, deduplicated in order', () => {
  const r = parseArgs(['--games=workout,siege, workout ,tank']);
  assert.equal(r.ok, true);
  assert.deepEqual(r.opts.games, ['workout', 'siege', 'tank']);
});

test('bad game ids are refused', () => {
  for (const g of ['Workout', '1x', 'a-b', '../x', '_template']) {
    const r = parseArgs([`--games=${g}`]);
    assert.equal(r.ok, false, g);
    assert.match(r.error, /bad game id/);
  }
});

test('defaults', () => {
  const r = parseArgs(['--games=workout']);
  assert.equal(r.ok, true);
  const o = r.opts;
  assert.equal(o.seed, DEFAULTS.seed);
  assert.equal(o.mockTrainer, 'erg:compliance=1.0');
  assert.equal(o.autoUpload, 'client1');
  assert.equal(o.relayCmd, defaultRelayCmd(process.versions.node));
  if (!needsStripTypesFlag()) assert.equal(o.relayCmd, 'node server/relay/src/main.ts');
  assert.equal(o.stravaCmd, 'node server/mock_strava/server.mjs --port=0 --parent-pid={pid}');
  assert.equal(o.repo, path.resolve(DEFAULT_REPO));
  assert.equal(o.out, path.join(path.resolve(DEFAULT_REPO), 'build', 'e2e'));
  assert.equal(o.maxDurationS, 360);
  assert.equal(o.cooldownS, 180);
  assert.equal(o.waitPeers, 3);
  assert.equal(o.peerTimeoutS, o.gameTimeoutS + 60);
  assert.equal(o.runSeconds, o.gameTimeoutS);
  assert.equal(o.keep, false);
  assert.equal(o.verbose, false);
});

test('numbers are validated', () => {
  assert.equal(parseArgs(['--games=w', '--seed=7']).opts.seed, 7);
  assert.equal(parseArgs(['--games=w', '--kill-after=0.5']).opts.killAfterS, 0.5);
  for (const bad of ['--seed=1.5', '--seed=-1', '--seed=', '--kill-after=x', '--game-timeout=0', '--lock-timeout=-3']) {
    const r = parseArgs(['--games=w', bad]);
    assert.equal(r.ok, false, bad);
  }
});

test('refuses to run without a mock trainer', () => {
  for (const v of ['', 'none', 'OFF', 'real', 'ftms', 'false', '0']) {
    const r = parseArgs(['--games=w', `--mock-trainer=${v}`]);
    assert.equal(r.ok, false, v);
    assert.match(r.error, /refusing to run without a mock trainer/);
  }
  assert.equal(parseArgs(['--games=w', '--mock-trainer=erg:compliance=0.9+band']).opts.mockTrainer, 'erg:compliance=0.9+band');
});

test('never drops the locks', () => {
  for (const a of ['--allow-hw', '--allow-network']) {
    const r = parseArgs(['--games=w', a]);
    assert.equal(r.ok, false);
    assert.match(r.error, /never drops/);
  }
});

test('--auto-upload names a peer', () => {
  assert.equal(parseArgs(['--games=w', '--auto-upload=host']).opts.autoUpload, 'host');
  assert.equal(parseArgs(['--games=w', '--auto-upload=client3']).ok, false);
});

test('unknown options and bare words are refused', () => {
  assert.match(parseArgs(['--games=w', '--frob=1']).error, /unknown option/);
  assert.match(parseArgs(['--games=w', 'extra']).error, /unknown argument/);
  assert.match(parseArgs(['--games=w', '--seed']).error, /unknown argument/);
});

test('flags and paths', () => {
  const r = parseArgs(['--games=w', '--keep', '--verbose', '--repo=some/where', '--out=elsewhere', '--strava-admin=/x']);
  assert.equal(r.ok, true);
  assert.equal(r.opts.keep, true);
  assert.equal(r.opts.verbose, true);
  assert.equal(r.opts.repo, path.resolve('some/where'));
  assert.equal(r.opts.out, path.resolve('some/where', 'elsewhere'));
  assert.equal(r.opts.stravaAdmin, '/x');
});

test('--help', () => {
  assert.deepEqual(parseArgs(['--games=w', '--help']), { ok: true, help: true });
});

// W3 PKG-8: the relay is TypeScript; Node 22.12-22.17 (and 23.0-23.5) strip types only with the flag.
test('the default relay command adds --experimental-strip-types where Node needs it', () => {
  for (const v of ['22.12.0', '22.17.1', 'v22.14.0', '23.0.0', '23.5.0']) {
    assert.equal(needsStripTypesFlag(v), true, v);
    assert.equal(defaultRelayCmd(v), 'node --experimental-strip-types server/relay/src/main.ts', v);
  }
  for (const v of ['22.18.0', '22.20.1', '23.6.0', '24.0.0', '26.12.0']) {
    assert.equal(needsStripTypesFlag(v), false, v);
    assert.equal(defaultRelayCmd(v), 'node server/relay/src/main.ts', v);
  }
  assert.equal(needsStripTypesFlag('nonsense'), false);
  assert.equal(parseArgs(['--games=workout', '--relay-cmd=node x.mjs']).opts.relayCmd, 'node x.mjs', '--relay-cmd still wins');
});
