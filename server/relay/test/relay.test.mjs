// The relay protocol suite (BRIEF 5.3), run against both WebSocket layers: the `ws`
// package and the built-in RFC 6455 server. Clients are Node's global WebSocket; time is
// a FakeClock advanced by the tests, so the 60 s, 120 s and 4 h rules run in milliseconds.

import assert from 'node:assert/strict';
import { afterEach, beforeEach, describe, it } from 'node:test';
import { CLOSE_CODES, HOST_PEER } from '../src/relay.ts';
import { implementations, startTestRelay, waitFor } from '../testkit/harness.ts';

const CODE_RE = /^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{6}$/;

for (const { impl, skip } of await implementations()) {
  describe(`relay over ${impl}`, { skip }, () => {
    let tr;
    let codes;
    beforeEach(async () => {
      codes = [];
      tr = await startTestRelay(impl);
    });
    afterEach(async () => {
      await tr.close();
    });

    async function room(max = 8) {
      const h = await tr.host(max);
      const b = await tr.guest(h.code);
      assert.equal(b.reply.t, 'joined');
      const c = await tr.guest(h.code);
      assert.equal(c.reply.t, 'joined');
      await h.c.take('peer_joined');
      await h.c.take('peer_joined');
      await b.c.take('peer_joined');
      return { h, b, c };
    }

    describe('create and join', () => {
      it('create returns a 6-character code, peer 1, a token and the seat count', async () => {
        const c = await tr.connect();
        c.hello();
        c.send({ t: 'create', max: 4 });
        const m = await c.take('created');
        assert.match(m.code, CODE_RE);
        assert.equal(m.peer, HOST_PEER);
        assert.equal(typeof m.token, 'string');
        assert.ok(m.token.length >= 16);
        assert.equal(m.max, 4);
      });

      it('create caps max at 8 peers', async () => {
        const c = await tr.connect();
        c.hello();
        c.send({ t: 'create', max: 50 });
        assert.equal((await c.take('created')).max, 8);
      });

      it('every room gets its own code', async () => {
        const seen = new Set();
        for (let i = 0; i < 5; i++) seen.add((await tr.host()).code);
        assert.equal(seen.size, 5);
        assert.deepEqual([...seen].sort(), tr.relay.roomCodes().sort());
      });

      it('join returns the next peer id, the host id, its own token and the connected peers', async () => {
        const h = await tr.host();
        const b = await tr.guest(h.code);
        assert.deepEqual({ ...b.reply, token: 'x' }, { t: 'joined', peer: 2, host: 1, token: 'x', rejoin: false, peers: [1] });
        assert.notEqual(b.reply.token, h.token);
        assert.deepEqual(await h.c.take('peer_joined'), { t: 'peer_joined', peer: 2 });
        const c = await tr.guest(h.code);
        assert.equal(c.reply.peer, 3);
        assert.deepEqual(c.reply.peers, [1, 2]);
        assert.deepEqual(await h.c.take('peer_joined'), { t: 'peer_joined', peer: 3 });
        assert.deepEqual(await b.c.take('peer_joined'), { t: 'peer_joined', peer: 3 });
      });

      it('join input is case-insensitive, ignores dashes and spaces, and maps O to 0 and I/L to 1', async () => {
        await tr.close();
        tr = await startTestRelay(impl, { generateCode: () => 'K7Q0X1' });
        const h = await tr.host();
        assert.equal(h.code, 'K7Q0X1');
        for (const typed of ['k7q-0x1', 'K7Q OXI', ' k7qoxl ', 'k-7-q-o-x-L']) {
          const g = await tr.guest(typed);
          assert.equal(g.reply.t, 'joined', typed);
        }
      });

      it('an unknown or malformed code gets room_not_found', async () => {
        await tr.host();
        for (const code of ['ZZZZZZ', 'K7Q', 'K7QX2MX', 'UUUUUU', '']) {
          const g = await tr.guest(code);
          assert.deepEqual([g.reply.t, g.reply.code], ['error', 'room_not_found'], code);
        }
      });

      it('room_full once every seat is taken (8 peers)', async () => {
        const h = await tr.host(8);
        for (let peer = 2; peer <= 8; peer++) assert.equal((await tr.guest(h.code)).reply.peer, peer);
        const g = await tr.guest(h.code);
        assert.deepEqual([g.reply.t, g.reply.code], ['error', 'room_full']);
        assert.equal(tr.relay.stats().peers, 8);
      });

      it('a dropped peer keeps its seat until its token expires', async () => {
        const h = await tr.host(2);
        const b = await tr.guest(h.code);
        b.c.close();
        await h.c.take((m) => m.t === 'peer_left');
        assert.equal((await tr.guest(h.code)).reply.code, 'room_full');
        await tr.advance(121_000, [h.c]);
        const g = await tr.guest(h.code);
        assert.deepEqual([g.reply.t, g.reply.peer], ['joined', 3]);
      });

      it('create and join need hello first, and a connection holds one room', async () => {
        const c = await tr.connect();
        c.send({ t: 'create', max: 8 });
        assert.equal((await c.error()).code, 'bad_request');
        c.send({ t: 'join', code: 'K7QX2M' });
        assert.equal((await c.error()).code, 'bad_request');
        c.hello();
        c.send({ t: 'create', max: 8 });
        const created = await c.take('created');
        c.send({ t: 'create', max: 8 });
        assert.equal((await c.error()).code, 'bad_request');
        c.send({ t: 'join', code: created.code });
        assert.equal((await c.error()).code, 'bad_request');
      });

      it('P1: create may ask for a previous code and gets it while it is free', async () => {
        const a = await tr.connect();
        a.hello();
        a.send({ t: 'create', max: 8, code: 'k7q-x2m' });
        assert.equal((await a.take('created')).code, 'K7QX2M');
        const b = await tr.connect();
        b.hello();
        b.send({ t: 'create', max: 8, code: 'K7QX2M' });
        const other = await b.take('created');
        assert.notEqual(other.code, 'K7QX2M');
        assert.match(other.code, CODE_RE);
        a.send({ t: 'leave' });
        await a.sync();
        const c = await tr.connect();
        c.hello();
        c.send({ t: 'create', max: 8, code: 'K7QX2M' });
        assert.equal((await c.take('created')).code, 'K7QX2M');
        c.send({ t: 'leave' });
        c.send({ t: 'create', max: 8, code: 'not a code' });
        assert.match((await c.take('created')).code, CODE_RE);
      });
    });

    describe('routing', () => {
      it('a host msg to one peer reaches only that peer, with from', async () => {
        const { h, b, c } = await room();
        h.c.send({ t: 'msg', to: 2, d: { type: 'plan', v: 1 } });
        assert.deepEqual(await b.c.take('msg'), { t: 'msg', from: 1, d: { type: 'plan', v: 1 } });
        await c.c.sync();
        await h.c.sync();
        assert.deepEqual(c.c.pending(), []);
        assert.deepEqual(h.c.pending(), []);
      });

      it('to 0 from the host reaches everyone except the host', async () => {
        const { h, b, c } = await room();
        h.c.send({ t: 'msg', to: 0, d: { type: 'snapshot', seq: 7 } });
        const want = { t: 'msg', from: 1, d: { type: 'snapshot', seq: 7 } };
        assert.deepEqual(await b.c.take('msg'), want);
        assert.deepEqual(await c.c.take('msg'), want);
        await h.c.sync();
        assert.deepEqual(h.c.pending(), []);
      });

      it('a client msg to the host reaches only the host, with from', async () => {
        const { h, b, c } = await room();
        c.c.send({ t: 'msg', to: 1, d: { type: 'telemetry', tm: { p: 200 } } });
        assert.deepEqual(await h.c.take('msg'), { t: 'msg', from: 3, d: { type: 'telemetry', tm: { p: 200 } } });
        await b.c.sync();
        assert.deepEqual(b.c.pending(), []);
      });

      it('non-hosts may only send to the host (no peer-to-peer, no to 0)', async () => {
        const { h, b, c } = await room();
        b.c.send({ t: 'msg', to: 3, d: { x: 1 } });
        const e1 = await b.c.error();
        assert.equal(e1.code, 'bad_request');
        assert.equal(e1.re, 'msg');
        b.c.send({ t: 'msg', to: 0, d: { x: 2 } });
        assert.equal((await b.c.error()).code, 'bad_request');
        await c.c.sync();
        await h.c.sync();
        assert.deepEqual(c.c.pending(), []);
        assert.deepEqual(h.c.pending(), []);
      });

      it('d is forwarded byte for byte (the relay never looks inside it)', async () => {
        const { h, b } = await room();
        const d = '{ "type":"session_start","seed":12345678901234567890, "f":1.0,"e":1e2,"s":"\\u00e9\\"}{[","n":[1,{"d":null}] }';
        h.c.sendText(`{"t":"msg","to":2,"d":${d}}`);
        await b.c.take('msg');
        assert.equal(b.c.raw.at(-1), `{"t":"msg","from":1,"d":${d}}`);
        h.c.sendText(`{"d":"first","t":"msg","to":2,"d":[ 1.50 , "x" ]}`);
        await b.c.take('msg');
        assert.equal(b.c.raw.at(-1), '{"t":"msg","from":1,"d":[ 1.50 , "x" ]}');
      });

      it('a msg to a peer that is not there is dropped silently', async () => {
        const { h, b } = await room();
        b.c.close();
        await h.c.take('peer_left');
        h.c.send({ t: 'msg', to: 2, d: {} });
        h.c.send({ t: 'msg', to: 9, d: {} });
        h.c.send({ t: 'msg', to: 1, d: {} });
        await h.c.sync();
        assert.deepEqual(h.c.pending(), []);
      });

      it('msg outside a room is a bad_request', async () => {
        const c = await tr.connect();
        c.hello();
        c.send({ t: 'msg', to: 1, d: {} });
        assert.equal((await c.error()).code, 'bad_request');
      });
    });

    describe('leave', () => {
      it('a client leave sends peer_left "left" and frees the seat for good', async () => {
        const { h, b, c } = await room();
        b.c.send({ t: 'leave' });
        assert.deepEqual(await h.c.take('peer_left'), { t: 'peer_left', peer: 2, reason: 'left' });
        assert.deepEqual(await c.c.take('peer_left'), { t: 'peer_left', peer: 2, reason: 'left' });
        const again = await tr.guest(h.code, b.reply.token);
        assert.deepEqual([again.reply.t, again.reply.peer, again.reply.rejoin], ['joined', 4, false]);
        // The socket that left can join again as a new peer.
        b.c.send({ t: 'join', code: h.code });
        assert.equal((await b.c.take('joined')).peer, 5);
      });

      it('a host leave sends host_left to everyone and closes the room', async () => {
        const { h, b, c } = await room();
        h.c.send({ t: 'leave' });
        assert.deepEqual(await b.c.take('host_left'), { t: 'host_left', reason: 'left' });
        assert.deepEqual(await c.c.take('host_left'), { t: 'host_left', reason: 'left' });
        assert.equal((await tr.guest(h.code)).reply.code, 'room_not_found');
        assert.equal((await tr.guest(h.code, h.token)).reply.code, 'room_not_found');
        // Peers stay connected outside any room and may start over.
        b.c.send({ t: 'create', max: 8 });
        assert.match((await b.c.take('created')).code, CODE_RE);
        await h.c.sync();
        assert.deepEqual(h.c.pending(), []);
      });

      it('leave outside a room does nothing', async () => {
        const c = await tr.connect();
        c.send({ t: 'leave' });
        c.hello();
        c.send({ t: 'leave' });
        await c.sync();
        assert.deepEqual(c.pending(), []);
      });
    });

    describe('reconnect and host drop', () => {
      it('a client back within 120 s keeps its peer id and its token', async () => {
        const { h, b, c } = await room();
        b.c.close();
        assert.deepEqual(await h.c.take('peer_left'), { t: 'peer_left', peer: 2, reason: 'dropped' });
        assert.deepEqual(await c.c.take('peer_left'), { t: 'peer_left', peer: 2, reason: 'dropped' });
        await tr.advance(119_000, [h.c, c.c]);
        const back = await tr.guest(h.code, b.reply.token);
        assert.equal(back.reply.t, 'joined');
        assert.equal(back.reply.peer, 2);
        assert.equal(back.reply.host, 1);
        assert.equal(back.reply.rejoin, true);
        assert.deepEqual(back.reply.peers, [1, 3]);
        assert.equal(back.reply.token, b.reply.token, 'the seat keeps its token');
        assert.deepEqual(await h.c.take('peer_joined'), { t: 'peer_joined', peer: 2, rejoin: true });
        assert.deepEqual(await c.c.take('peer_joined'), { t: 'peer_joined', peer: 2, rejoin: true });
        h.c.send({ t: 'msg', to: 2, d: { type: 'phase' } });
        assert.deepEqual(await back.c.take('msg'), { t: 'msg', from: 1, d: { type: 'phase' } });
        back.c.send({ t: 'msg', to: 1, d: { type: 'telemetry' } });
        assert.deepEqual(await h.c.take('msg'), { t: 'msg', from: 2, d: { type: 'telemetry' } });
        assert.equal(tr.relay.stats().peers, 3);
      });

      it('a reconnect retried with the same token (its joined reply lost) gets the same peer id again', async () => {
        const { h, b, c } = await room();
        b.c.close();
        await h.c.take('peer_left');
        // The first reconnect succeeds on the relay, but the socket dies before the client reads joined.
        const first = await tr.guest(h.code, b.reply.token);
        assert.deepEqual([first.reply.peer, first.reply.rejoin], [2, true]);
        first.c.close();
        await h.c.take((m) => m.t === 'peer_left' && m.peer === 2);
        // The client still only knows the token it saved first.
        await tr.advance(100_000, [h.c, c.c]);
        const second = await tr.guest(h.code, b.reply.token);
        assert.deepEqual([second.reply.t, second.reply.peer, second.reply.rejoin], ['joined', 2, true]);
        // The 120 s hold restarts at every drop: 130 s after the first drop but 30 s after the latest, still held.
        second.c.close();
        await h.c.take((m) => m.t === 'peer_left' && m.peer === 2);
        await tr.advance(30_000, [h.c, c.c]);
        const third = await tr.guest(h.code, b.reply.token);
        assert.deepEqual([third.reply.peer, third.reply.rejoin], [2, true]);
        assert.equal(tr.relay.stats().held, 0);
      });

      it('an expired token is refused even before the periodic sweep runs', async () => {
        const { h, b, c } = await room();
        b.c.close();
        await h.c.take('peer_left');
        // Keep h and c alive, then step past the 120 s without sweeping.
        for (let i = 0; i < 4; i++) {
          await h.c.sync();
          await c.c.sync();
          tr.clock.advance(30_000);
        }
        tr.clock.advance(1_000);
        const late = await tr.guest(h.code, b.reply.token);
        assert.deepEqual([late.reply.t, late.reply.peer, late.reply.rejoin], ['joined', 4, false]);
        assert.notEqual(late.reply.token, b.reply.token);
      });

      it('a peer may join while the host is away; the returning host sees it in joined.peers', async () => {
        const { h, b, c } = await room();
        h.c.close();
        await b.c.take('peer_left');
        await c.c.take('peer_left');
        const d = await tr.guest(h.code);
        assert.deepEqual([d.reply.peer, d.reply.host, d.reply.peers], [4, 1, [2, 3]]);
        assert.deepEqual(await b.c.take('peer_joined'), { t: 'peer_joined', peer: 4 });
        d.c.send({ t: 'msg', to: 1, d: 'nobody home' });
        await d.c.sync();
        const back = await tr.guest(h.code, h.token);
        assert.deepEqual([back.reply.peer, back.reply.rejoin, back.reply.peers], [1, true, [2, 3, 4]]);
        assert.deepEqual(await d.c.take('peer_joined'), { t: 'peer_joined', peer: 1, rejoin: true });
        await back.c.sync();
        assert.ok(!back.c.pending().some((m) => m.t === 'msg'), 'nothing sent while away is replayed');
      });

      it('a reconnect token expires 120 s after the drop', async () => {
        const { h, b, c } = await room();
        b.c.close();
        await h.c.take('peer_left');
        await tr.advance(121_000, [h.c, c.c]);
        const late = await tr.guest(h.code, b.reply.token);
        assert.deepEqual([late.reply.t, late.reply.peer, late.reply.rejoin], ['joined', 4, false]);
        assert.deepEqual(late.reply.peers, [1, 3]);
      });

      it('a reconnect while the old socket is still open replaces it', async () => {
        const { h, b } = await room();
        const back = await tr.guest(h.code, b.reply.token);
        assert.deepEqual([back.reply.peer, back.reply.rejoin], [2, true]);
        assert.equal((await b.c.closed).code, CLOSE_CODES.REPLACED);
        assert.deepEqual(await h.c.take('peer_left'), { t: 'peer_left', peer: 2, reason: 'dropped' });
        assert.deepEqual(await h.c.take('peer_joined'), { t: 'peer_joined', peer: 2, rejoin: true });
        back.c.send({ t: 'msg', to: 1, d: 'still here' });
        assert.deepEqual(await h.c.take('msg'), { t: 'msg', from: 2, d: 'still here' });
        assert.equal(tr.relay.stats().peers, 3);
      });

      it('a host drop sends peer_left 1 "dropped", holds the room, and the host takes peer 1 back', async () => {
        const { h, b, c } = await room();
        h.c.close();
        assert.deepEqual(await b.c.take('peer_left'), { t: 'peer_left', peer: 1, reason: 'dropped' });
        assert.deepEqual(await c.c.take('peer_left'), { t: 'peer_left', peer: 1, reason: 'dropped' });
        // While the host is away, messages to it are dropped and nobody gets host_left.
        b.c.send({ t: 'msg', to: 1, d: { lost: true } });
        await tr.advance(110_000, [b.c, c.c]);
        assert.ok(!b.c.log.some((m) => m.t === 'host_left' || m.t === 'error'));
        const back = await tr.guest(h.code, h.token);
        assert.equal(back.reply.peer, 1);
        assert.equal(back.reply.host, 1);
        assert.equal(back.reply.rejoin, true);
        assert.deepEqual(back.reply.peers, [2, 3]);
        assert.deepEqual(await b.c.take('peer_joined'), { t: 'peer_joined', peer: 1, rejoin: true });
        back.c.send({ t: 'msg', to: 0, d: { type: 'lobby_state' } });
        assert.deepEqual(await c.c.take('msg'), { t: 'msg', from: 1, d: { type: 'lobby_state' } });
        await back.c.sync();
        assert.ok(!back.c.pending().some((m) => m.t === 'msg'), 'nothing sent while away is replayed');
      });

      it('host_left goes out when the host token expires', async () => {
        const { h, b, c } = await room();
        h.c.close();
        await b.c.take('peer_left');
        await tr.advance(119_000, [b.c, c.c]);
        assert.ok(!b.c.log.some((m) => m.t === 'host_left'));
        await tr.advance(2_000, [b.c, c.c]);
        assert.deepEqual(await b.c.take('host_left'), { t: 'host_left', reason: 'timeout' });
        assert.deepEqual(await c.c.take('host_left'), { t: 'host_left', reason: 'timeout' });
        assert.equal((await tr.guest(h.code, h.token)).reply.code, 'room_not_found');
        assert.equal(tr.relay.stats().rooms, 0);
      });

      it('a room whose peers all dropped closes when the host token expires', async () => {
        const { h, b, c } = await room();
        for (const x of [h, b, c]) x.c.close();
        await waitFor(() => tr.relay.stats().held === 3, 'three held seats');
        await tr.advance(121_000);
        assert.deepEqual(tr.relay.stats(), { rooms: 0, connections: 0, peers: 0, held: 0 });
      });
    });

    describe('ping', () => {
      it('ping {ts} returns pong with the same ts, before hello too', async () => {
        const c = await tr.connect();
        c.send({ t: 'ping', ts: 123 });
        assert.deepEqual(await c.take('pong'), { t: 'pong', ts: 123 });
        c.hello();
        c.send({ t: 'ping', ts: 1729.5 });
        assert.deepEqual(await c.take('pong'), { t: 'pong', ts: 1729.5 });
      });
    });

    describe('malformed input', () => {
      async function expectBad(c, text) {
        c.sendText(text);
        const e = await c.error();
        assert.equal(e.code, 'bad_request', text);
        assert.equal(typeof e.detail, 'string');
      }

      it('bad JSON and non-object messages get bad_request and the connection stays', async () => {
        const c = await tr.connect();
        for (const text of ['{', 'hello', '', '[1,2]', '"msg"', '42', 'null', '{"t":"ping","ts":1}x']) await expectBad(c, text);
        await c.sync();
        assert.equal(c.isClosed, false);
      });

      it('a missing or unknown t gets bad_request', async () => {
        const c = await tr.connect();
        for (const text of ['{}', '{"t":5}', '{"t":null}', '{"t":"nope"}', '{"t":"created"}', '{"t":"pong","ts":1}', '{"t":"MSG"}']) {
          await expectBad(c, text);
        }
        c.send({ t: 'nope' });
        assert.equal((await c.error()).re, 'nope');
      });

      it('missing or mistyped fields get bad_request', async () => {
        const c = await tr.connect();
        for (const hello of [{ t: 'hello' }, { t: 'hello', proto: '1', game: 'wattlands', build: '0.1.0' }, { t: 'hello', proto: 1, build: '0.1.0' }, { t: 'hello', proto: 1, game: 'wattlands' }]) {
          await expectBad(c, JSON.stringify(hello));
        }
        await expectBad(c, '{"t":"ping"}');
        await expectBad(c, '{"t":"ping","ts":"now"}');
        c.hello();
        for (const create of [{ t: 'create' }, { t: 'create', max: 0 }, { t: 'create', max: 2.5 }, { t: 'create', max: '8' }, { t: 'create', max: 8, code: 7 }]) {
          await expectBad(c, JSON.stringify(create));
        }
        for (const join of [{ t: 'join' }, { t: 'join', code: 123456 }, { t: 'join', code: 'K7QX2M', token: 5 }]) {
          await expectBad(c, JSON.stringify(join));
        }
        c.send({ t: 'create', max: 8 });
        await c.take('created');
        for (const msg of [{ t: 'msg', d: {} }, { t: 'msg', to: -1, d: {} }, { t: 'msg', to: 1.5, d: {} }, { t: 'msg', to: '2', d: {} }, { t: 'msg', to: 2 }]) {
          await expectBad(c, JSON.stringify(msg));
        }
        await c.sync();
        assert.equal(c.isClosed, false);
      });

      it('a binary message gets bad_request', async () => {
        const c = await tr.connect();
        c.ws.send(new Uint8Array([1, 2, 3]));
        assert.equal((await c.error()).code, 'bad_request');
        await c.sync();
      });

      it('another protocol version gets version_mismatch and the socket is closed', async () => {
        const c = await tr.connect();
        c.hello(2);
        const e = await c.error();
        assert.equal(e.code, 'version_mismatch');
        assert.equal(e.proto, 1);
        assert.equal((await c.closed).code, CLOSE_CODES.VERSION_MISMATCH);
      });
    });

    describe('limits', () => {
      it('16 KB messages pass; a larger one closes the socket with 1009', async () => {
        const { h, b } = await room();
        const fill = (bytes, prefix, suffix) => prefix + 'x'.repeat(bytes - prefix.length - suffix.length) + suffix;
        const max = fill(16384, '{"t":"msg","to":2,"d":"', '"}');
        assert.equal(Buffer.byteLength(max), 16384);
        h.c.sendText(max);
        assert.equal((await b.c.take('msg')).d.length, 16384 - 25);
        const big = fill(16385, '{"t":"msg","to":1,"d":"', '"}');
        b.c.sendText(big);
        assert.equal((await b.c.closed).code, 1009);
        assert.deepEqual(await h.c.take('peer_left'), { t: 'peer_left', peer: 2, reason: 'dropped' });
        assert.ok(!h.c.log.some((m) => m.t === 'msg'));
      });

      it('a burst of 120 messages passes; the rest are dropped with one rate_limited error', async () => {
        const { h, b } = await room();
        // b has sent hello and join (2 of its 120 tokens); the clock does not move.
        const mark = tr.mark();
        for (let i = 0; i < 130; i++) b.c.send({ t: 'msg', to: 1, d: i });
        await tr.processed(mark, 130);
        await h.c.sync();
        const got = h.c.pending().filter((m) => m.t === 'msg');
        assert.equal(got.length, 118);
        assert.deepEqual(got.map((m) => m.d), [...Array(118).keys()]);
        await b.c.error('rate_limited');
        assert.equal(b.c.log.filter((m) => m.code === 'rate_limited').length, 1);
        assert.equal(tr.relay.counters.rateLimited, 12);
      });

      it('the bucket refills at 60 messages a second', async () => {
        const { h, b } = await room();
        let mark = tr.mark();
        for (let i = 0; i < 118; i++) b.c.send({ t: 'msg', to: 1, d: i });
        await tr.processed(mark, 118);
        tr.clock.advance(1000);
        mark = tr.mark();
        for (let i = 0; i < 61; i++) b.c.send({ t: 'msg', to: 1, d: 1000 + i });
        await tr.processed(mark, 61);
        await h.c.sync();
        const late = h.c.pending().filter((m) => m.t === 'msg' && m.d >= 1000);
        assert.equal(late.length, 60);
        assert.equal(tr.relay.counters.rateLimited, 1);
        tr.clock.advance(500);
        mark = tr.mark();
        for (let i = 0; i < 31; i++) b.c.send({ t: 'msg', to: 1, d: 2000 + i });
        await tr.processed(mark, 31);
        await h.c.sync();
        assert.equal(h.c.pending().filter((m) => m.t === 'msg' && m.d >= 2000).length, 30);
        assert.equal(tr.relay.counters.rateLimited, 2);
      });

      it('the 11th join attempt from one IP within a minute is rate_limited', async () => {
        const c = await tr.connect();
        c.hello();
        for (let i = 0; i < 10; i++) {
          c.send({ t: 'join', code: 'ZZZZZZ' });
          assert.equal((await c.error()).code, 'room_not_found');
        }
        c.send({ t: 'join', code: 'ZZZZZZ' });
        assert.equal((await c.error()).code, 'rate_limited');
        const other = await tr.connect();
        other.hello();
        other.send({ t: 'join', code: 'ZZZZZZ' });
        assert.equal((await other.error()).code, 'rate_limited', 'the limit is per IP, not per socket');
        await tr.advance(60_000, [c]);
        c.send({ t: 'join', code: 'ZZZZZZ' });
        assert.equal((await c.error()).code, 'room_not_found');
      });

      it('an idle socket is closed after 60 s; any message keeps it open', async () => {
        const c = await tr.connect();
        tr.clock.advance(59_000);
        tr.relay.sweep();
        await c.sync();
        tr.clock.advance(59_000);
        tr.relay.sweep();
        await c.sync();
        tr.clock.advance(60_000);
        tr.relay.sweep();
        assert.equal((await c.closed).code, CLOSE_CODES.IDLE_TIMEOUT);
      });

      it('an idle host counts as a drop (peer_left "dropped", room held)', async () => {
        const { h, b, c } = await room();
        tr.clock.advance(30_000);
        await b.c.sync();
        await c.c.sync();
        tr.clock.advance(30_000);
        tr.relay.sweep();
        assert.equal((await h.c.closed).code, CLOSE_CODES.IDLE_TIMEOUT);
        assert.deepEqual(await b.c.take('peer_left'), { t: 'peer_left', peer: 1, reason: 'dropped' });
        assert.equal(tr.relay.stats().rooms, 1);
        assert.equal((await tr.guest(h.code, h.token)).reply.peer, 1);
      });

      it('rooms close after 4 hours', async () => {
        await tr.close();
        tr = await startTestRelay(impl, { limits: { idleTimeoutMs: 5 * 3600_000 } });
        const { h, b } = await room();
        tr.clock.advance(4 * 3600_000 - 1000);
        tr.relay.sweep();
        b.c.send({ t: 'msg', to: 1, d: 'late' });
        assert.equal((await h.c.take('msg')).d, 'late');
        tr.clock.advance(1000);
        tr.relay.sweep();
        assert.deepEqual(await h.c.take('host_left'), { t: 'host_left', reason: 'expired' });
        assert.deepEqual(await b.c.take('host_left'), { t: 'host_left', reason: 'expired' });
        assert.equal((await tr.guest(h.code)).reply.code, 'room_not_found');
      });
    });

    describe('http', () => {
      it('GET /health reports status, protocol, implementation and counts', async () => {
        await room();
        const res = await fetch(`${tr.running.httpUrl}/health`);
        assert.equal(res.status, 200);
        assert.match(res.headers.get('content-type'), /application\/json/);
        const body = await res.json();
        assert.equal(body.status, 'ok');
        assert.equal(body.proto, 1);
        assert.equal(body.impl, impl);
        assert.equal(body.rooms, 1);
        assert.equal(body.peers, 3);
        assert.equal(body.held, 0);
        assert.equal(typeof body.uptime_s, 'number');
        assert.ok(!JSON.stringify(body).includes(tr.relay.roomCodes()[0]), 'no room codes in /health');
      });

      it('other paths: / is 200, /v1 without an upgrade is 426, anything else is 404', async () => {
        assert.equal((await fetch(`${tr.running.httpUrl}/`)).status, 200);
        assert.equal((await fetch(`${tr.running.httpUrl}/v1`)).status, 426);
        assert.equal((await fetch(`${tr.running.httpUrl}/nope`)).status, 404);
        await assert.rejects(() => (async () => {
          const ws = new WebSocket(tr.url.replace('/v1', '/v2'));
          await new Promise((resolve, reject) => {
            ws.addEventListener('open', resolve);
            ws.addEventListener('error', () => reject(new Error('refused')));
          });
        })());
      });

      it('shutdown closes every socket with 1001', async () => {
        const { h, b } = await room();
        await tr.running.close(1000);
        assert.equal((await h.c.closed).code, CLOSE_CODES.SHUTDOWN);
        assert.equal((await b.c.closed).code, CLOSE_CODES.SHUTDOWN);
      });
    });
  });
}
