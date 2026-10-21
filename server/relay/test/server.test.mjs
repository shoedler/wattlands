// The server entry: choosing the WebSocket layer (including the zero-dependency fallback
// when ws can't be imported), client IPs behind a proxy, and `node src/main.ts` itself.

import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { clientIp, loadWsLayer, parseImpl, startRelay } from '../src/server.ts';
import { implementations, TestClient } from '../testkit/harness.ts';

const RELAY_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const wsMissing = (await implementations()).find((x) => x.impl === 'ws').skip;
// Node 22.12-22.17 strip types only with this flag; `npm test` passes it, and the relay
// processes these tests start need it too.
const NODE_FLAGS = process.execArgv.includes('--experimental-strip-types') ? ['--experimental-strip-types'] : [];

/** Start `node src/main.ts` in `cwd`; resolves with the URL from its WATTLANDS_RELAY line. */
function startMain(cwd, args = [], env = {}) {
  const childEnv = { ...process.env, RELAY_LOG: 'quiet', ...env };
  for (const [k, v] of Object.entries(env)) if (v === undefined) delete childEnv[k];
  const child = spawn(process.execPath, [...NODE_FLAGS, 'src/main.ts', ...args], { cwd, env: childEnv, stdio: ['ignore', 'pipe', 'pipe'] });
  let out = '';
  let err = '';
  child.stderr.on('data', (d) => (err += d));
  const url = new Promise((resolve, reject) => {
    child.stdout.on('data', (d) => {
      out += d;
      const m = /WATTLANDS_RELAY (\S+)/.exec(out);
      if (m) resolve(m[1]);
    });
    child.once('exit', (code) => reject(new Error(`relay exited with ${code}: ${err}`)));
  });
  const exited = new Promise((resolve) => child.once('exit', (code) => resolve({ code, out, err: () => err })));
  return { child, url, exited };
}

async function healthOf(wsUrl) {
  const res = await fetch(wsUrl.replace('ws://', 'http://').replace(/\/v1$/, '/health'));
  return res.json();
}

describe('choosing the WebSocket layer', () => {
  it('parseImpl accepts auto, ws and builtin (default auto)', () => {
    assert.equal(parseImpl(undefined), 'auto');
    assert.equal(parseImpl(''), 'auto');
    assert.equal(parseImpl(' Builtin '), 'builtin');
    assert.equal(parseImpl('ws'), 'ws');
    assert.throws(() => parseImpl('uws'), /unknown WebSocket implementation/);
  });

  it('auto falls back to the built-in server when ws cannot be imported', async () => {
    const missing = () => Promise.reject(Object.assign(new Error("Cannot find package 'ws'"), { code: 'ERR_MODULE_NOT_FOUND' }));
    const { layer, note } = await loadWsLayer('auto', 16384, missing);
    assert.equal(layer.name, 'builtin');
    assert.match(note, /ERR_MODULE_NOT_FOUND/);
    await assert.rejects(() => loadWsLayer('ws', 16384, missing), /can't be imported/);
    assert.equal((await loadWsLayer('builtin', 16384, () => assert.fail('not imported'))).layer.name, 'builtin');
  });

  it('auto uses ws when it imports', { skip: wsMissing }, async () => {
    assert.equal((await loadWsLayer('auto', 16384)).layer.name, 'ws');
  });

  it('RELAY_WS_IMPL=builtin forces the built-in server', async () => {
    const saved = process.env.RELAY_WS_IMPL;
    process.env.RELAY_WS_IMPL = 'builtin';
    try {
      const r = await startRelay({ port: 0, host: '127.0.0.1', sweepMs: 0 });
      assert.equal(r.impl, 'builtin');
      await r.close();
    } finally {
      if (saved === undefined) delete process.env.RELAY_WS_IMPL;
      else process.env.RELAY_WS_IMPL = saved;
    }
  });

  it('a relay whose import of ws fails still serves a whole room', async () => {
    const r = await startRelay({ port: 0, host: '127.0.0.1', impl: 'auto', sweepMs: 0, importWs: () => Promise.reject(new Error('no ws')) });
    try {
      assert.equal(r.impl, 'builtin');
      const h = await TestClient.connect(r.url);
      h.hello();
      h.send({ t: 'create', max: 2 });
      const { code } = await h.take('created');
      const g = await TestClient.connect(r.url);
      g.hello();
      g.send({ t: 'join', code });
      await g.take('joined');
      g.send({ t: 'msg', to: 1, d: { ok: true } });
      assert.deepEqual(await h.take('msg'), { t: 'msg', from: 2, d: { ok: true } });
      h.close();
      g.close();
    } finally {
      await r.close();
    }
  });
});

describe('the periodic sweep (real clock)', () => {
  it('startRelay sweeps on its own: an idle socket is closed with 4000', async () => {
    const r = await startRelay({ port: 0, host: '127.0.0.1', impl: 'builtin', sweepMs: 20, limits: { idleTimeoutMs: 150 } });
    try {
      const c = await TestClient.connect(r.url);
      const started = performance.now();
      const { code } = await c.closed;
      assert.equal(code, 4000);
      assert.ok(performance.now() - started < 2000);
    } finally {
      await r.close();
    }
  });
});

describe('client IP for the join limit', () => {
  const req = (headers, remoteAddress = '::ffff:10.1.2.3') => ({ headers, socket: { remoteAddress } });

  it('uses the socket address (IPv4-mapped addresses unwrapped) unless a proxy is trusted', () => {
    assert.equal(clientIp(req({ 'x-forwarded-for': '1.2.3.4' }), false), '10.1.2.3');
    assert.equal(clientIp(req({}, '::1'), false), '::1');
  });

  it('behind a trusted proxy uses Fly-Client-IP, then the first X-Forwarded-For entry', () => {
    assert.equal(clientIp(req({ 'fly-client-ip': '5.6.7.8', 'x-forwarded-for': '1.2.3.4' }), true), '5.6.7.8');
    assert.equal(clientIp(req({ 'x-forwarded-for': '1.2.3.4, 10.0.0.1' }), true), '1.2.3.4');
    assert.equal(clientIp(req({}), true), '10.1.2.3');
  });
});

describe('node src/main.ts', () => {
  it('runs with zero npm dependencies (a copy without node_modules uses the built-in server)', async (t) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-relay-'));
    fs.cpSync(path.join(RELAY_DIR, 'src'), path.join(dir, 'src'), { recursive: true });
    fs.copyFileSync(path.join(RELAY_DIR, 'package.json'), path.join(dir, 'package.json'));
    const run = startMain(dir, [], { PORT: '0', HOST: '127.0.0.1', RELAY_WS_IMPL: undefined, NODE_PATH: undefined });
    t.after(async () => {
      run.child.kill();
      await run.exited;
      fs.rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 50 });
    });
    const url = await run.url;
    assert.match(url, /^ws:\/\/127\.0\.0\.1:\d+\/v1$/);
    const health = await healthOf(url);
    assert.equal(health.impl, 'builtin');
    assert.equal(health.status, 'ok');
    const c = await TestClient.connect(url);
    c.hello();
    c.send({ t: 'create', max: 8 });
    assert.match((await c.take('created')).code, /^[0-9A-Z]{6}$/);
    c.close();
  });

  it('honours --impl, --port and --host', async (t) => {
    const run = startMain(RELAY_DIR, ['--impl=builtin', '--port=0', '--host=127.0.0.1']);
    t.after(() => run.child.kill());
    const url = await run.url;
    assert.equal((await healthOf(url)).impl, 'builtin');
  });

  it('uses ws by default when it is installed', { skip: wsMissing }, async (t) => {
    const run = startMain(RELAY_DIR, [], { PORT: '0', HOST: '127.0.0.1', RELAY_WS_IMPL: undefined });
    t.after(() => run.child.kill());
    assert.equal((await healthOf(await run.url)).impl, 'ws');
  });

  it('exits non-zero on a bad option and prints usage on --help', async () => {
    const bad = startMain(RELAY_DIR, ['--impl=uws', '--port=0']);
    bad.url.catch(() => {});
    const r = await bad.exited;
    assert.equal(r.code, 1);
    assert.match(r.err(), /unknown WebSocket implementation/);
    const badPort = startMain(RELAY_DIR, ['--port=99999']);
    badPort.url.catch(() => {});
    assert.equal((await badPort.exited).code, 1);
    const typo = startMain(RELAY_DIR, ['--prot=0']);
    typo.url.catch(() => {});
    const t = await typo.exited;
    assert.equal(t.code, 1);
    assert.match(t.err(), /unknown option "--prot=0"[\s\S]*usage:/);
    const help = startMain(RELAY_DIR, ['--help']);
    help.url.catch(() => {});
    const h = await help.exited;
    assert.equal(h.code, 0);
    assert.match(h.out, /usage: node src\/main\.ts/);
  });

  it('exits non-zero when the port is taken', async (t) => {
    const first = await startRelay({ port: 0, host: '127.0.0.1', impl: 'builtin', sweepMs: 0 });
    t.after(() => first.close());
    const second = startMain(RELAY_DIR, [`--port=${first.port}`, '--host=127.0.0.1']);
    second.url.catch(() => {});
    const r = await second.exited;
    assert.equal(r.code, 1);
    assert.match(r.err(), /EADDRINUSE/);
  });
});
