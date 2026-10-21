// node:test: the harness's default relay command starts the real relay (server/relay, TypeScript)
// on a Node without default type stripping (22.12-22.17), emulated here with
// --no-experimental-strip-types (W3 PKG-8). The command for a newer Node fails the same way the old
// default did on those versions, which shows the emulation is faithful.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { defaultRelayCmd } from '../lib/args.mjs';
import { startRelay } from '../lib/services.mjs';
import { DEFAULT_REPO } from '../lib/util.mjs';

/** "node ..." as a Node whose type stripping is off by default would run it. */
const asOldNode = (cmd) => cmd.replace(/^node /, 'node --no-experimental-strip-types ');

async function tryRelay(relayCmd, t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands_e2e_relay_'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  try {
    const relay = await startRelay({ repo: path.resolve(DEFAULT_REPO), relayCmd, logFile: path.join(dir, 'relay.log'), timeoutMs: 20000 });
    relay.proc.kill();
    return { ok: true, url: relay.url };
  } catch (e) {
    return { ok: false, error: String(e?.message ?? e) };
  }
}

test('the default relay command for Node 22.12 starts the relay without default type stripping', async (t) => {
  const r = await tryRelay(asOldNode(defaultRelayCmd('22.12.0')), t);
  assert.equal(r.ok, true, r.error);
  assert.match(r.url, /^ws:\/\/127\.0\.0\.1:\d+\/v1$/);
});

test('without the flag the relay does not start on such a Node (the old default)', async (t) => {
  const r = await tryRelay(asOldNode(defaultRelayCmd('22.18.0')), t);
  assert.equal(r.ok, false, 'the emulation must reproduce the failure');
  assert.match(r.error, /relay exited|ERR_UNKNOWN_FILE_EXTENSION|did not answer/);
});
