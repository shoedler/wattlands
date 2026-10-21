// The key never lands in a file or an output line, even when fal's answers echo it back
// (BRIEF 3.10 "never prints the key"; W3 ART-W3-1, ART-W3-2). Each case runs generate.mjs's main()
// in real mode in a child process (helpers/key_echo_run.mjs) under the no-network preload, against a
// fake fal that echoes the Authorization header: in a job's error, in the result body and image URL,
// and in a 401 body. The child's own environment never has FAL_KEY or WATTLANDS_ALLOW_ART; main()
// gets a plain env object with a dummy key.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { FalClient } from '../lib/fal.mjs';
import { checkArtLock, makeRedactor } from '../lib/locks.mjs';
import { childEnv, DUMMY_KEY, DUMMY_KEY_PARTS, makeRoot, NO_NETWORK_PRELOAD, removeRoot, TEST_DIR, walk } from './helpers.mjs';

const RUNNER = path.join(TEST_DIR, 'helpers', 'key_echo_run.mjs');

function runEcho(mode, root, key) {
  const log = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands_art_nonet_')), 'nonet.log');
  const env = childEnv({ extra: { KEY_ECHO_RUN: '1', NO_NET_LOG: log } });
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['--import', NO_NETWORK_PRELOAD, RUNNER, mode, root, JSON.stringify(key)], {
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    let out = '';
    let err = '';
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (err += d));
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`key_echo_run timed out\n${out}\n${err}`));
    }, 60000);
    child.on('close', (code) => {
      clearTimeout(timer);
      const net = fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '';
      fs.rmSync(path.dirname(log), { recursive: true, force: true });
      const line = out.trim().split('\n').pop() ?? '';
      let res = null;
      try {
        res = JSON.parse(line);
      } catch {
        reject(new Error(`no result from key_echo_run (exit ${code})\n${out}\n${err}`));
        return;
      }
      resolve({ ...res, childStderr: err, net });
    });
  });
}

function echoRoot() {
  return makeRoot('k', {
    palette: ['#000000', '#ffffff'],
    style: 'flat pixel art',
    sprites: [{ id: 'boat', prompt: 'a boat', size: [32, 32] }],
  });
}

function assertNoKey(text, where, secretOnly = false) {
  const parts = secretOnly ? [DUMMY_KEY_PARTS[2]] : DUMMY_KEY_PARTS;
  for (const p of parts) assert.equal(String(text).includes(p), false, `${where} contains part of the key`);
}

function assertNoKeyInRoot(root) {
  for (const f of walk(root)) assertNoKey(fs.readFileSync(f).toString('latin1'), path.relative(root, f));
}

for (const mode of ['status_error', 'result_echo', 'echo_401']) {
  test(`fal echoing the key (${mode}): not in stdout, stderr, the manifest or the cache`, async (t) => {
    const root = echoRoot();
    t.after(() => removeRoot(root));
    const r = await runEcho(mode, root, DUMMY_KEY);
    assert.equal(r.net, '', 'no socket, DNS lookup or real fetch');
    assert.ok(r.calls.length > 0, 'the fake fal was used');
    assertNoKey(r.stdout, 'stdout');
    assertNoKey(r.stderr, 'stderr');
    assertNoKey(r.childStderr, 'child stderr');
    assert.ok(fs.existsSync(path.join(root, 'assets', 'k', 'art_manifest.json')), 'the manifest was written');
    assertNoKeyInRoot(root);
    if (mode === 'status_error') {
      assert.equal(r.code, 1);
      const m = JSON.parse(fs.readFileSync(path.join(root, 'assets', 'k', 'art_manifest.json'), 'utf8'));
      assert.match(m.requests[0].error, /auth_error: upstream rejected header Authorization: Key \[redacted\]/);
    }
    if (mode === 'result_echo') assert.equal(r.code, 0, r.stderr);
  });
}

for (const padded of [`${DUMMY_KEY}\n`, ` ${DUMMY_KEY} `, `${DUMMY_KEY}\t`]) {
  test(`a key with surrounding whitespace (${JSON.stringify(padded)}) is redacted as it goes on the wire`, async (t) => {
    assert.equal(checkArtLock({ FAL_KEY: padded, WATTLANDS_ALLOW_ART: '1' }).ok, true);
    const root = echoRoot();
    t.after(() => removeRoot(root));
    const r = await runEcho('echo_401', root, padded);
    assert.equal(r.net, '');
    assertNoKey(r.stdout + r.stderr, 'output');
    assertNoKeyInRoot(root);
  });
}

test('makeRedactor knows the trimmed key and its trimmed parts', async () => {
  const fetchImpl = async (_url, init) => new Response(`invalid credentials: ${new Headers(init.headers).get('authorization')}`, { status: 401 });
  for (const key of [`${DUMMY_KEY}\n`, ` ${DUMMY_KEY} `]) {
    const c = new FalClient({ key, fetchImpl, redact: makeRedactor(key) });
    const err = await c.status('https://queue.fal.run/a/b/requests/x/status').catch((e) => e);
    // fetch trims only the ends of the header value: " id:secret " sends "Key  id:secret".
    assert.match(err.message, /HTTP 401 invalid credentials: Key\s+\[redacted\]$/);
    assertNoKey(err.message, 'the error');
  }
  assert.equal(makeRedactor('   ')('x'), 'x', 'a blank key redacts nothing');
});
