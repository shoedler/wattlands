// Options of `node src/main.ts` (flags and environment), tested without a process.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { parseMainOptions, USAGE } from '../src/options.ts';
import { DEFAULT_PORT, WS_PATH } from '../src/server.ts';

describe('main options', () => {
  it('defaults to port 8787 on every interface, the auto layer, no proxy trust and the log on', () => {
    assert.equal(DEFAULT_PORT, 8787);
    assert.equal(WS_PATH, '/v1');
    assert.deepEqual(parseMainOptions([], {}), { help: false, port: 8787, host: undefined, impl: 'auto', trustProxy: false, quiet: false, limits: {} });
  });

  it('reads PORT, HOST, RELAY_WS_IMPL, RELAY_TRUST_PROXY and RELAY_LOG', () => {
    const o = parseMainOptions([], { PORT: '9000', HOST: '127.0.0.1', RELAY_WS_IMPL: 'builtin', RELAY_TRUST_PROXY: '1', RELAY_LOG: 'quiet' });
    assert.deepEqual(o, { help: false, port: 9000, host: '127.0.0.1', impl: 'builtin', trustProxy: true, quiet: true, limits: {} });
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

  it('RELAY_TRUST_PROXY: 1 trusts one proxy, a number that many, fly the Fly header; a typo is an error', () => {
    const trust = (v) => parseMainOptions([], { RELAY_TRUST_PROXY: v }).trustProxy;
    for (const v of ['false', ' No ', '00']) assert.equal(trust(v), v.trim() === '00' ? 0 : false, v);
    assert.equal(trust('2'), 2);
    assert.equal(trust('10'), 10);
    assert.equal(trust(' FLY '), 'fly');
    for (const v of ['fly,1', 'cloudflare', '-1', '1.5', '100', 'on']) {
      assert.throws(() => trust(v), /invalid RELAY_TRUST_PROXY/, v);
    }
  });

  it('every limit has a flag and an environment variable, and the flag wins', () => {
    const flags = [
      '--max-connections=10',
      '--max-connections-per-ip=5',
      '--max-rooms=7',
      '--max-rooms-per-ip=3',
      '--room-creates-per-min=4',
      '--hello-timeout=20',
    ];
    const want = { maxConnections: 10, maxConnectionsPerIp: 5, maxRooms: 7, maxRoomsPerIp: 3, roomCreatesPerWindow: 4, helloDeadlineMs: 20_000 };
    assert.deepEqual(parseMainOptions(flags, {}).limits, want);
    const env = {
      RELAY_MAX_CONNECTIONS: '10',
      RELAY_MAX_CONNECTIONS_PER_IP: '5',
      RELAY_MAX_ROOMS: '7',
      RELAY_MAX_ROOMS_PER_IP: '3',
      RELAY_ROOM_CREATES_PER_MIN: '4',
      RELAY_HELLO_TIMEOUT_S: '20',
    };
    assert.deepEqual(parseMainOptions([], env).limits, want);
    assert.deepEqual(parseMainOptions(['--max-rooms=99'], env).limits.maxRooms, 99);
    assert.deepEqual(parseMainOptions([], { RELAY_MAX_ROOMS: '1' }).limits, { maxRooms: 1 }, 'the rest keep their defaults');
  });

  it('0 turns a limit off, and a blank environment value counts as unset', () => {
    assert.deepEqual(parseMainOptions([], { RELAY_MAX_ROOMS: '0', RELAY_HELLO_TIMEOUT_S: '0' }).limits, { maxRooms: 0, helloDeadlineMs: 0 });
    assert.deepEqual(parseMainOptions([], { RELAY_MAX_ROOMS: '', RELAY_MAX_CONNECTIONS: '  ' }).limits, {});
  });

  it('refuses a limit that is not a whole number, and a flag with no value', () => {
    for (const v of ['-1', '1.5', 'many', '1e3', '0x10', '9999999999']) {
      assert.throws(() => parseMainOptions([`--max-rooms=${v}`], {}), /invalid --max-rooms/, v);
      assert.throws(() => parseMainOptions([], { RELAY_MAX_ROOMS: v }), /invalid RELAY_MAX_ROOMS/, v);
    }
    assert.throws(() => parseMainOptions(['--max-connections='], {}), /--max-connections needs a value/);
    assert.throws(() => parseMainOptions(['--max-room=3'], {}), /unknown option/);
    assert.throws(() => parseMainOptions(['--Max-Rooms=3'], {}), /unknown option/);
  });

  it('the usage text names every new flag and variable', () => {
    for (const name of ['--max-connections', '--max-connections-per-ip', '--max-rooms', '--max-rooms-per-ip', '--room-creates-per-min', '--hello-timeout']) {
      assert.ok(USAGE.includes(name), name);
    }
    for (const name of ['RELAY_MAX_CONNECTIONS', 'RELAY_MAX_CONNECTIONS_PER_IP', 'RELAY_MAX_ROOMS', 'RELAY_MAX_ROOMS_PER_IP', 'RELAY_ROOM_CREATES_PER_MIN', 'RELAY_HELLO_TIMEOUT_S', 'RELAY_TRUST_PROXY']) {
      assert.ok(USAGE.includes(name), name);
    }
  });

  it('--help and -h ask for the usage text', () => {
    assert.equal(parseMainOptions(['--help'], {}).help, true);
    assert.equal(parseMainOptions(['-h', '--port=0'], {}).help, true);
    assert.match(USAGE, /usage: node src\/main\.ts/);
  });
});
