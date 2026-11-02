// RFC 6455 behaviour at the byte level (BRIEF 5.3: handshake; text, close, ping and pong
// frames; client masking; 16 KB maximum payload; no extensions), run against both layers
// so the built-in server and the ws package behave the same.

import assert from 'node:assert/strict';
import { afterEach, beforeEach, describe, it } from 'node:test';
import { CLOSE_CODES } from '../src/relay.ts';
import { implementations, startTestRelay } from '../testkit/harness.ts';
import { closePayload, clientFrame, RawClient } from '../testkit/raw.ts';

const TEXT = 0x1;
const BINARY = 0x2;
const CONT = 0x0;
const CLOSE = 0x8;
const PING = 0x9;
const PONG = 0xa;

/** A JSON ping of exactly `bytes` bytes. */
function pingOfSize(bytes) {
  const head = '{"t":"ping","ts":7,"pad":"';
  const tail = '"}';
  const text = head + 'p'.repeat(bytes - head.length - tail.length) + tail;
  assert.equal(Buffer.byteLength(text), bytes);
  return text;
}

for (const { impl, skip } of await implementations()) {
  describe(`WebSocket frames over ${impl}`, { skip }, () => {
    let tr;
    let raws;
    beforeEach(async () => {
      tr = await startTestRelay(impl);
      raws = [];
    });
    afterEach(async () => {
      for (const r of raws) r.destroy();
      await tr.close();
    });

    async function open(opts = {}) {
      const res = await RawClient.open(tr.running.port, opts);
      if (res.client) raws.push(res.client);
      return res;
    }

    async function connected() {
      const { status, client } = await open();
      assert.equal(status, 101);
      return client;
    }

    /** Wait for the server's close frame, answer it like a well-behaved client, wait for the TCP close. */
    async function expectClose(client, code) {
      const f = await client.closeFrame();
      assert.equal(f.code, code);
      if (client.socket.writable) client.send({ opcode: CLOSE, payload: closePayload(f.code) });
      await client.ended;
    }

    describe('handshake', () => {
      it('answers 101 with the right accept key and ignores extension offers', async () => {
        const { status, headers, client } = await open({
          extraHeaders: ['Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits', 'Sec-WebSocket-Protocol: chat'],
        });
        assert.equal(status, 101);
        assert.equal(headers.upgrade.toLowerCase(), 'websocket');
        assert.equal(headers['sec-websocket-extensions'], undefined);
        assert.equal(headers['sec-websocket-protocol'], undefined);
        client.sendText('{"t":"ping","ts":1}');
        assert.deepEqual(await client.json(), { t: 'pong', ts: 1 });
      });

      it('refuses a bad version (426), a missing or malformed key (400), another path (404) and POST (405)', async () => {
        const v8 = await open({ version: '8' });
        assert.equal(v8.status, 426);
        assert.equal(v8.headers['sec-websocket-version'], '13');
        assert.equal((await open({ version: null })).status, 426);
        assert.equal((await open({ key: null })).status, 400);
        assert.equal((await open({ key: 'not-a-key' })).status, 400);
        assert.equal((await open({ path: '/v2' })).status, 404);
        assert.equal((await open({ path: '/' })).status, 404);
        assert.equal((await open({ method: 'POST' })).status, 405);
        assert.equal((await open({ path: '/v1?client=godot' })).status, 101, 'a query string is fine');
      });

      it('processes frames that arrive in the same packet as the upgrade request', async () => {
        const { status, client } = await open({ firstBytes: clientFrame({ opcode: TEXT, payload: '{"t":"ping","ts":42}' }) });
        assert.equal(status, 101);
        assert.deepEqual(await client.json(), { t: 'pong', ts: 42 });
      });
    });

    describe('frames', () => {
      it('reassembles a fragmented text message, with a ping between the fragments', async () => {
        const c = await connected();
        c.send({ opcode: TEXT, payload: '{"t":"pi', fin: false });
        c.send({ opcode: PING, payload: 'mid' });
        c.send({ opcode: CONT, payload: 'ng","ts"', fin: false });
        c.send({ opcode: CONT, payload: ':3}', fin: true });
        const pong = await c.next((f) => f.opcode === PONG);
        assert.equal(pong.payload.toString(), 'mid');
        assert.deepEqual(await c.json(), { t: 'pong', ts: 3 });
      });

      it('parses frames that trickle in byte by byte and several frames in one packet', async () => {
        const c = await connected();
        c.socket.setNoDelay(true);
        const one = clientFrame({ opcode: TEXT, payload: '{"t":"ping","ts":11}' });
        for (const byte of one) {
          c.write(Buffer.from([byte]));
          await new Promise((r) => setImmediate(r));
        }
        assert.deepEqual(await c.json(), { t: 'pong', ts: 11 });
        const big = clientFrame({ opcode: TEXT, payload: pingOfSize(3000) });
        const packed = Buffer.concat([
          clientFrame({ opcode: TEXT, payload: '{"t":"ping","ts":12}' }),
          clientFrame({ opcode: TEXT, payload: '{"t":"ping","ts":13}' }),
          big.subarray(0, 3),
        ]);
        c.write(packed);
        assert.deepEqual(await c.json(), { t: 'pong', ts: 12 });
        assert.deepEqual(await c.json(), { t: 'pong', ts: 13 });
        for (let i = 3; i < big.length; i += 700) {
          c.write(big.subarray(i, i + 700));
          await new Promise((r) => setImmediate(r));
        }
        assert.deepEqual(await c.json(), { t: 'pong', ts: 7 });
      });

      it('answers a WebSocket ping with a pong carrying the same payload', async () => {
        const c = await connected();
        c.send({ opcode: PING, payload: Buffer.from([1, 2, 3, 250]) });
        const pong = await c.next((f) => f.opcode === PONG);
        assert.deepEqual([...pong.payload], [1, 2, 3, 250]);
        c.send({ opcode: PONG, payload: 'unsolicited' });
        c.sendText('{"t":"ping","ts":9}');
        assert.deepEqual(await c.json(), { t: 'pong', ts: 9 });
      });

      it('server frames are unmasked text frames', async () => {
        const c = await connected();
        c.sendText('{"t":"ping","ts":1}');
        const f = await c.next();
        assert.equal(f.opcode, TEXT);
        assert.equal(f.fin, true);
      });

      it('a binary message gets a bad_request reply', async () => {
        const c = await connected();
        c.send({ opcode: BINARY, payload: Buffer.from([0, 1, 2]) });
        const e = await c.json();
        assert.equal(e.t, 'error');
        assert.equal(e.code, 'bad_request');
      });
    });

    describe('protocol errors', () => {
      it('an unmasked client frame closes with 1002', async () => {
        const c = await connected();
        c.send({ opcode: TEXT, payload: '{"t":"ping","ts":1}', mask: false });
        await expectClose(c, 1002);
      });

      it('reserved bits without an extension close with 1002', async () => {
        const c = await connected();
        c.send({ opcode: TEXT, payload: '{"t":"ping","ts":1}', rsv: 4 });
        await expectClose(c, 1002);
      });

      it('an unknown opcode closes with 1002', async () => {
        const c = await connected();
        c.send({ opcode: 0x3, payload: 'x' });
        await expectClose(c, 1002);
      });

      it('a continuation frame without a message closes with 1002', async () => {
        const c = await connected();
        c.send({ opcode: CONT, payload: 'x' });
        await expectClose(c, 1002);
      });

      it('a new message inside a fragmented one closes with 1002', async () => {
        const c = await connected();
        c.send({ opcode: TEXT, payload: '{"t":', fin: false });
        c.send({ opcode: TEXT, payload: '"ping"}' });
        await expectClose(c, 1002);
      });

      it('a fragmented control frame closes with 1002', async () => {
        const c = await connected();
        c.send({ opcode: PING, payload: 'x', fin: false });
        await expectClose(c, 1002);
      });

      it('a control frame over 125 bytes closes with 1002', async () => {
        const c = await connected();
        c.send({ opcode: PING, payload: Buffer.alloc(126, 1) });
        await expectClose(c, 1002);
      });

      it('invalid UTF-8 in a text message closes with 1007', async () => {
        const c = await connected();
        c.send({ opcode: TEXT, payload: Buffer.from([0x7b, 0xff, 0xfe, 0x7d]) });
        await expectClose(c, 1007);
      });

      it('a close frame with a reserved code closes with 1002', async () => {
        const c = await connected();
        c.send({ opcode: CLOSE, payload: closePayload(1005) });
        await expectClose(c, 1002);
      });
    });

    describe('size limit', () => {
      it('a 16384-byte message passes', async () => {
        const c = await connected();
        c.sendText(pingOfSize(16384));
        assert.deepEqual(await c.json(), { t: 'pong', ts: 7 });
      });

      it('a 16385-byte message closes with 1009', async () => {
        const c = await connected();
        c.sendText(pingOfSize(16385));
        await expectClose(c, 1009);
      });

      it('a fragmented message over 16384 bytes closes with 1009', async () => {
        const c = await connected();
        const text = Buffer.from(pingOfSize(16385));
        c.send({ opcode: TEXT, payload: text.subarray(0, 10000), fin: false });
        c.send({ opcode: CONT, payload: text.subarray(10000), fin: true });
        await expectClose(c, 1009);
      });

      it('a fragmented message of exactly 16384 bytes passes', async () => {
        const c = await connected();
        const text = Buffer.from(pingOfSize(16384));
        c.send({ opcode: TEXT, payload: text.subarray(0, 8000), fin: false });
        c.send({ opcode: CONT, payload: text.subarray(8000, 12000), fin: false });
        c.send({ opcode: CONT, payload: text.subarray(12000), fin: true });
        assert.deepEqual(await c.json(), { t: 'pong', ts: 7 });
      });
    });

    describe('closing', () => {
      it('echoes a client close frame and ends the TCP connection', async () => {
        const c = await connected();
        c.send({ opcode: CLOSE, payload: closePayload(1000, 'bye') });
        await expectClose(c, 1000);
      });

      it('echoes an empty close frame with an empty one', async () => {
        const c = await connected();
        c.send({ opcode: CLOSE });
        const f = await c.next((x) => x.opcode === CLOSE);
        assert.equal(f.payload.length, 0);
        await c.ended;
      });

      it('a reset TCP connection counts as a drop', async () => {
        const h = await tr.host();
        const c = await connected();
        c.sendText('{"t":"hello","proto":1,"game":"wattlands","build":"0.1.0"}');
        c.sendText(`{"t":"join","code":"${h.code}"}`);
        assert.equal((await c.json()).t, 'joined');
        await h.c.take('peer_joined');
        c.destroy();
        assert.deepEqual(await h.c.take('peer_left'), { t: 'peer_left', peer: 2, reason: 'dropped' });
      });
    });

    describe('idle timeout', () => {
      const HELLO = '{"t":"hello","proto":1,"game":"wattlands","build":"0.1.0"}';

      it('WebSocket ping and pong frames are answered but are not activity', async () => {
        const c = await connected();
        c.sendText(HELLO);
        c.sendText('{"t":"ping","ts":1}');
        await c.json();
        tr.clock.advance(30_000);
        tr.relay.sweep();
        c.send({ opcode: PING, payload: 'a' });
        const pong = await c.next((f) => f.opcode === PONG);
        assert.equal(pong.payload.toString(), 'a', 'a WebSocket ping is still answered');
        tr.clock.advance(29_000);
        tr.relay.sweep();
        c.send({ opcode: PONG, payload: 'b' });
        c.send({ opcode: PING, payload: 'c' });
        await c.next((f) => f.opcode === PONG && f.payload.toString() === 'c');
        tr.clock.advance(1000);
        tr.relay.sweep();
        await expectClose(c, CLOSE_CODES.IDLE_TIMEOUT);
      });

      it('a relay message counts, a client that pings every 15 s stays connected', async () => {
        const c = await connected();
        c.sendText(HELLO);
        for (let i = 0; i < 12; i++) {
          tr.clock.advance(15_000);
          c.send({ opcode: PING, payload: 'ws' });
          c.sendText('{"t":"ping","ts":' + i + '}');
          await c.json();
          tr.relay.sweep();
        }
        assert.equal(tr.relay.stats().connections, 1, 'three minutes later the socket is still open');
        tr.clock.advance(60_000);
        tr.relay.sweep();
        await expectClose(c, CLOSE_CODES.IDLE_TIMEOUT);
      });
    });
  });
}
