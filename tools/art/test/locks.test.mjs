// The art lock (BRIEF 1, 3.10, 7.1; docs/OWNERSHIP.md ART7): real calls need both FAL_KEY and
// WATTLANDS_ALLOW_ART=1, else generate.mjs refuses before any socket opens; --mock runs need neither;
// generate.mjs never reads WATTLANDS_NO_NETWORK_INTEGRATIONS, so it behaves the same with it set or unset.
//
// The art-lock cases below run without --mock and without WATTLANDS_ALLOW_ART, under a preload that
// makes every connection attempt throw and records it: the refusals, and one case showing that
// --dry-run and --select (which contact nothing) need neither the variables nor --mock.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { checkArtLock, EXIT_LOCKED } from '../lib/locks.mjs';
import {
  ART_DIR,
  childEnv,
  DUMMY_KEY_PARTS,
  makeRoot,
  mockArgs,
  mockFor,
  NO_NETWORK_PRELOAD,
  readManifest,
  removeRoot,
  runGenerate,
  smallArt,
  walk,
} from './helpers.mjs';

const GAME = 'lock';

function noNetLog(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands_nonet_'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return path.join(dir, 'attempts.log');
}

function rootFor(t) {
  const root = makeRoot(GAME, smallArt());
  t.after(() => removeRoot(root));
  return root;
}

async function refusal(t, { dummyKey, extra = {} }) {
  const root = rootFor(t);
  const log = noNetLog(t);
  const r = await runGenerate([`--game=${GAME}`, `--root=${root}`], {
    env: childEnv({ dummyKey, extra: { ...extra, NO_NET_LOG: log } }),
    preload: NO_NETWORK_PRELOAD,
  });
  return { r, log, root };
}

test('the preload really blocks and records connections (sanity check of the harness)', async (t) => {
  const log = noNetLog(t);
  const probe = path.join(path.dirname(log), 'probe.mjs');
  fs.writeFileSync(probe, "await fetch('http://127.0.0.1:9/').catch(() => {});\nprocess.exit(0);\n");
  const { spawn } = await import('node:child_process');
  const code = await new Promise((resolve) => {
    const c = spawn(process.execPath, ['--import', NO_NETWORK_PRELOAD, probe], { env: { ...childEnv(), NO_NET_LOG: log }, stdio: 'ignore' });
    c.on('close', resolve);
  });
  assert.equal(code, 0);
  assert.match(fs.readFileSync(log, 'utf8'), /fetch/);
});

test('dummy key, no WATTLANDS_ALLOW_ART, no --mock: refused before any socket opens', async (t) => {
  const { r, log, root } = await refusal(t, { dummyKey: true });
  assert.equal(r.code, EXIT_LOCKED, r.stdout + r.stderr);
  assert.match(r.stderr, /refusing to call fal: WATTLANDS_ALLOW_ART is not 1/);
  assert.equal(fs.existsSync(log), false, `connection attempts: ${fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : ''}`);
  for (const p of DUMMY_KEY_PARTS) assert.equal((r.stdout + r.stderr).includes(p), false, 'the key is never printed');
  assert.equal(fs.existsSync(path.join(root, 'assets', GAME, 'art_manifest.json')), false);
  assert.equal(fs.existsSync(path.join(root, '.art_cache')), false);
});

test('no key and no WATTLANDS_ALLOW_ART: refused, naming both', async (t) => {
  const { r, log } = await refusal(t, { dummyKey: false });
  assert.equal(r.code, EXIT_LOCKED);
  assert.match(r.stderr, /FAL_KEY is not set and WATTLANDS_ALLOW_ART is not 1/);
  assert.match(r.stderr, /--dry-run/);
  assert.equal(fs.existsSync(log), false);
});

test('the refusal is identical with WATTLANDS_NO_NETWORK_INTEGRATIONS=1 set or unset', async (t) => {
  const a = await refusal(t, { dummyKey: true, extra: { WATTLANDS_NO_NETWORK_INTEGRATIONS: '1' } });
  const b = await refusal(t, { dummyKey: true, extra: { WATTLANDS_NO_NETWORK_INTEGRATIONS: null } });
  assert.equal(a.r.code, EXIT_LOCKED);
  assert.equal(b.r.code, a.r.code);
  assert.equal(b.r.stderr, a.r.stderr);
  assert.equal(b.r.stdout, a.r.stdout);
});

test('checkArtLock: anything short of both variables refuses', () => {
  for (const env of [
    {},
    { FAL_KEY: 'x' },
    { FAL_KEY: '' },
    { FAL_KEY: '   ' },
    { WATTLANDS_ALLOW_ART: '1' },
    { FAL_KEY: 'x', WATTLANDS_ALLOW_ART: '0' },
    { FAL_KEY: 'x', WATTLANDS_ALLOW_ART: 'true' },
    { FAL_KEY: 'x', WATTLANDS_ALLOW_ART: 'yes' },
    { FAL_KEY: 'x', WATTLANDS_ALLOW_ART: '' },
  ]) {
    const res = checkArtLock(env);
    assert.equal(res.ok, false, JSON.stringify(Object.keys(env)));
    assert.equal(res.message.includes('x\n'), false);
  }
  assert.match(checkArtLock({ WATTLANDS_ALLOW_ART: '1' }).message, /FAL_KEY is not set/);
  assert.doesNotMatch(checkArtLock({ WATTLANDS_ALLOW_ART: '1' }).message, /ALLOW_ART is not 1/);
});

test('--mock runs need neither variable', async (t) => {
  const mock = await mockFor(t);
  const root = rootFor(t);
  const r = await runGenerate(mockArgs(GAME, root, mock, ['--only=boat']), { env: childEnv() });
  assert.equal(r.code, 0, r.stderr);
  assert.equal(readManifest(root, GAME).requests[0].status, 'ok');
});

test('--select and --dry-run need neither variable and no --mock', async (t) => {
  const root = rootFor(t);
  const log = noNetLog(t);
  const env = childEnv({ extra: { NO_NET_LOG: log } });
  const dry = await runGenerate([`--game=${GAME}`, `--root=${root}`, '--dry-run'], { env, preload: NO_NETWORK_PRELOAD });
  assert.equal(dry.code, 0, dry.stderr);
  const sel = await runGenerate([`--game=${GAME}`, `--root=${root}`, '--select=boat:abc'], { env, preload: NO_NETWORK_PRELOAD });
  assert.equal(sel.code, 2, 'no such request, but no refusal either');
  assert.match(sel.stderr, /has no request abc/);
  assert.equal(fs.existsSync(log), false);
});

function normalize(text, mockUrl) {
  return text
    .split(mockUrl)
    .join('<mock>')
    .replace(/\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+Z/g, '<time>');
}

test('generation behaves identically with WATTLANDS_NO_NETWORK_INTEGRATIONS=1 set or unset', async (t) => {
  const results = [];
  for (const value of ['1', null]) {
    const mock = await mockFor(t);
    const root = rootFor(t);
    const r = await runGenerate(mockArgs(GAME, root, mock, ['--concurrency=1']), {
      env: childEnv({ extra: { WATTLANDS_NO_NETWORK_INTEGRATIONS: value } }),
    });
    assert.equal(r.code, 0, r.stderr);
    const m = readManifest(root, GAME);
    results.push({
      stdout: normalize(r.stdout, mock.url),
      stderr: normalize(r.stderr, mock.url),
      manifest: normalize(JSON.stringify(m), mock.url),
      submits: mock.state.counts.submit,
    });
  }
  assert.equal(results[0].submits, 4);
  assert.deepEqual(results[1], results[0]);
});

test('the art pipeline never reads the network lock variable', () => {
  const files = [path.join(ART_DIR, 'generate.mjs'), ...walk(path.join(ART_DIR, 'lib'))].filter((f) => f.endsWith('.mjs'));
  assert.ok(files.length >= 8);
  const name = ['WATTLANDS', 'NO', 'NETWORK', 'INTEGRATIONS'].join('_');
  for (const f of files) assert.equal(fs.readFileSync(f, 'utf8').includes(name), false, f);
});
