// Options of `node src/main.ts` (flags and environment), tested without a process.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { parseMainOptions, USAGE } from '../src/options.ts';
import { DEFAULT_PORT, WS_PATH } from '../src/server.ts';

describe('main options', () => {
  it('defaults to port 8787 on every interface, the auto layer, no proxy trust and the log on', () => {
    assert.equal(DEFAULT_PORT, 8787);
    assert.equal(WS_PATH, '/v1');
    assert.deepEqual(parseMainOptions([], {}), { help: false, port: 8787, host: undefined, impl: 'auto', trustProxy: false, quiet: false });
  });

  it('reads PORT, HOST, RELAY_WS_IMPL, RELAY_TRUST_PROXY and RELAY_LOG', () => {
    const o = parseMainOptions([], { PORT: '9000', HOST: '127.0.0.1', RELAY_WS_IMPL: 'builtin', RELAY_TRUST_PROXY: '1', RELAY_LOG: 'quiet' });
    assert.deepEqual(o, { help: false, port: 9000, host: '127.0.0.1', impl: 'builtin', trustProxy: true, quiet: true });
    assert.equal(parseMainOptions([], { PORT: '0' }).port, 0, 'PORT=0 picks a free port');
    for (const v of ['true', 'YES', ' 1 ']) assert.equal(parseMainOptions([], { RELAY_TRUST_PROXY: v }).trustProxy, true, v);
    for (const v of ['', '0', 'no']) assert.equal(parseMainOptions([], { RELAY_TRUST_PROXY: v }).trustProxy, false, v);
  });

  it('a blank PORT or HOST counts as unset (the default port, not a random one)', () => {
    assert.equal(parseMainOptions([], { PORT: '' }).port, 8787);
    assert.equal(parseMainOptions([], { PORT: '  ' }).port, 8787);
    assert.equal(parseMainOptions([], { HOST: ' ' }).host, undefined);
  });

  it('flags win over the environment', () => {
    const o = parseMainOptions(['--port=0', '--host=::1', '--impl=ws'], { PORT: '9000', HOST: '127.0.0.1', RELAY_WS_IMPL: 'builtin' });
    assert.deepEqual([o.port, o.host, o.impl], [0, '::1', 'ws']);
  });

  it('refuses bad ports, unknown implementations and unknown options', () => {
    for (const port of ['99999', '-1', '80.5', 'abc', '0x50', '1e3']) {
      assert.throws(() => parseMainOptions([`--port=${port}`], {}), /invalid port/, port);
      assert.throws(() => parseMainOptions([], { PORT: port }), /invalid port/, port);
    }
    assert.throws(() => parseMainOptions(['--port='], {}), /--port needs a value/);
    assert.throws(() => parseMainOptions(['--impl=uws'], {}), /unknown WebSocket implementation/);
    assert.throws(() => parseMainOptions([], { RELAY_WS_IMPL: 'uws' }), /unknown WebSocket implementation/);
    for (const a of ['--prot=1', '--port', '8787', '-p=1', '--PORT=1']) assert.throws(() => parseMainOptions([a], {}), /unknown option/, a);
  });

  it('--help and -h ask for the usage text', () => {
    assert.equal(parseMainOptions(['--help'], {}).help, true);
    assert.equal(parseMainOptions(['-h', '--port=0'], {}).help, true);
    assert.match(USAGE, /usage: node src\/main\.ts/);
  });
});
