// The abuse limits: connection, room and room-create caps, the deadline for a first hello,
// and /health under load. Run against both WebSocket layers, with time on a FakeClock.

import assert from 'node:assert/strict';
import { afterEach, describe, it } from 'node:test';
import { FakeClock } from '../src/clock.ts';
import { CLOSE_CODES, DEFAULT_LIMITS, Relay } from '../src/relay.ts';
import { implementations, startTestRelay, waitFor } from '../testkit/harness.ts';
import { RawClient } from '../testkit/raw.ts';

const HELLO = '{"t":"hello","proto":1,"game":"wattlands","build":"0.1.0"}';

describe('default caps', () => {
  it('are set, and roomy enough for a venue (8 rooms and 64 sockets from one address)', () => {
    assert.deepEqual(
      {
        conns: DEFAULT_LIMITS.maxConnections,
        connsIp: DEFAULT_LIMITS.maxConnectionsPerIp,
        rooms: DEFAULT_LIMITS.maxRooms,
        roomsIp: DEFAULT_LIMITS.maxRoomsPerIp,
        creates: DEFAULT_LIMITS.roomCreatesPerWindow,
        createWindow: DEFAULT_LIMITS.roomCreateWindowMs,
        hello: DEFAULT_LIMITS.helloDeadlineMs,
      },
      { conns: 500, connsIp: 64, rooms: 200, roomsIp: 8, creates: 10, createWindow: 60_000, hello: 10_000 },
    );
  });
});

class FakeConn {
  sent = [];
  closedWith = null;
  bufferedAmount = 0;
  send(text) {
    this.sent.push(JSON.parse(text));
  }
  close(code, reason) {
    this.closedWith = { code, reason };
  }
}

describe('the relay core under its caps (no sockets)', () => {
  function core(limits = {}) {
    const clock = new FakeClock(0);
    const lines = [];
    const relay = new Relay({ clock, limits, log: (l) => lines.push(l) });
    const connect = (ip = '10.0.0.1') => {
      const conn = new FakeConn();
      const h = relay.open(conn, ip);
      const send = (obj) => h.onText(JSON.stringify(obj));
      return { conn, h, send, last: () => conn.sent.at(-1) };
    };
    const host = (ip) => {
      const c = connect(ip);
      c.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
      c.send({ t: 'create', max: 8 });
      return c;
    };
    return { clock, relay, lines, connect, host };
  }

  it('open() closes a socket over the cap with 1013 and keeps no state for it', () => {
    const { relay, connect } = core({ maxConnectionsPerIp: 2, maxConnections: 3 });
    connect('1.1.1.1');
    connect('1.1.1.1');
    const third = connect('1.1.1.1');
    assert.deepEqual(third.conn.closedWith, { code: CLOSE_CODES.TRY_AGAIN, reason: 'too many connections' });
    assert.equal(relay.stats().connections, 2);
    connect('2.2.2.2');
    const full = connect('3.3.3.3');
    assert.equal(full.conn.closedWith.code, CLOSE_CODES.TRY_AGAIN);
    assert.equal(relay.stats().connections, 3);
    assert.equal(relay.counters.connectionsRefused, 2);
    third.send({ t: 'ping', ts: 1 });
    third.h.onClose();
    assert.deepEqual(third.conn.sent, [], 'a refused socket gets nothing and its close changes nothing');
    assert.equal(relay.stats().connections, 3);
  });

  it('a closed socket frees its slot, for its address too', () => {
    const { relay, connect } = core({ maxConnectionsPerIp: 1 });
    const a = connect('1.1.1.1');
    assert.equal(relay.admit('1.1.1.1'), 'ip');
    assert.equal(relay.admit('2.2.2.2'), 'ok');
    a.h.onClose();
    assert.equal(relay.admit('1.1.1.1'), 'ok');
  });

  it('the total cap wins over the per-address one when both are met', () => {
    const { relay, connect } = core({ maxConnectionsPerIp: 1, maxConnections: 1 });
    connect('1.1.1.1');
    assert.equal(relay.admit('1.1.1.1'), 'total');
  });

  it('0 turns a cap off', () => {
    const { relay, connect, host } = core({
      maxConnections: 0,
      maxConnectionsPerIp: 0,
      maxRooms: 0,
      maxRoomsPerIp: 0,
      roomCreatesPerWindow: 0,
      helloDeadlineMs: 0,
    });
    for (let i = 0; i < 100; i++) connect('1.1.1.1');
    for (let i = 0; i < 30; i++) assert.equal(host('1.1.1.1').last().t, 'created');
    assert.equal(relay.stats().rooms, 30);
  });

  it('a create over the room caps gets rate_limited, keeps the socket and records nothing', () => {
    const { relay, host, connect } = core({ maxRoomsPerIp: 2, maxRooms: 3, roomCreatesPerWindow: 0 });
    host('1.1.1.1');
    host('1.1.1.1');
    const refused = host('1.1.1.1');
    assert.equal(refused.last().t, 'error');
    assert.equal(refused.last().code, 'rate_limited');
    assert.equal(refused.last().re, 'create');
    assert.equal(refused.conn.closedWith, null);
    assert.equal(relay.stats().rooms, 2);
    assert.equal(host('2.2.2.2').last().t, 'created', 'another address still has its share');
    const full = host('3.3.3.3');
    assert.equal(full.last().code, 'rate_limited', 'the relay-wide cap');
    assert.equal(relay.counters.createsLimited, 2);
    // The refused socket may try again once a room of its address is gone.
    const other = connect('1.1.1.1');
    other.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    other.send({ t: 'create', max: 4 });
    assert.equal(other.last().code, 'rate_limited');
  });

  it('a room that ends frees its address share and the relay-wide one', () => {
    const { relay, host } = core({ maxRoomsPerIp: 1, roomCreatesPerWindow: 0 });
    const a = host('1.1.1.1');
    assert.equal(host('1.1.1.1').last().code, 'rate_limited');
    a.send({ t: 'leave' });
    assert.equal(relay.stats().rooms, 0);
    assert.equal(host('1.1.1.1').last().t, 'created');
  });

  it('a held room (host dropped) still counts, and the host reclaims it with its token', () => {
    const { relay, host, connect, clock } = core({ maxRoomsPerIp: 1 });
    const h = host('1.1.1.1');
    const { code, token } = h.last();
    h.h.onClose();
    assert.equal(relay.stats().held, 1);
    assert.equal(host('1.1.1.1').last().code, 'rate_limited', 'the held room is still one of its rooms');
    clock.advance(30_000);
    const back = connect('1.1.1.1');
    back.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    back.send({ t: 'join', code, token });
    assert.deepEqual([back.last().t, back.last().peer, back.last().rejoin], ['joined', 1, true]);
    assert.equal(relay.counters.createsLimited, 1, 'the reclaim hit no room limit');
    // When the hold runs out, its share is free again.
    back.h.onClose();
    clock.advance(121_000);
    relay.sweep();
    assert.equal(relay.stats().rooms, 0);
    assert.equal(host('1.1.1.1').last().t, 'created');
  });

  it('the create rate is per address and per minute; refused creates do not count', () => {
    const { host, clock } = core({ roomCreatesPerWindow: 3, maxRoomsPerIp: 0 });
    for (let i = 0; i < 3; i++) {
      const h = host('1.1.1.1');
      assert.equal(h.last().t, 'created');
      h.send({ t: 'leave' });
    }
    assert.equal(host('1.1.1.1').last().code, 'rate_limited');
    assert.equal(host('2.2.2.2').last().t, 'created', 'the limit is per address');
    clock.advance(59_999);
    assert.equal(host('1.1.1.1').last().code, 'rate_limited');
    clock.advance(1);
    assert.equal(host('1.1.1.1').last().t, 'created', 'a minute after the first create');
  });

  it('an expired room the sweep has not reached yet does not count against a new one', () => {
    const { host, relay, clock } = core({ maxRooms: 1, maxRoomsPerIp: 1, roomCreatesPerWindow: 0, idleTimeoutMs: 1e12 });
    host('1.1.1.1');
    assert.equal(host('1.1.1.1').last().code, 'rate_limited');
    clock.advance(DEFAULT_LIMITS.roomLifetimeMs);
    assert.equal(host('1.1.1.1').last().t, 'created');
    assert.equal(relay.stats().rooms, 1);
  });

  it('a join and a rejoin never touch the room caps or the create rate', () => {
    const { host, connect } = core({ maxRooms: 1, roomCreatesPerWindow: 1 });
    const h = host('1.1.1.1');
    const code = h.last().code;
    for (let i = 0; i < 7; i++) {
      const g = connect('1.1.1.1');
      g.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
      g.send({ t: 'join', code });
      assert.equal(g.last().t, 'joined');
    }
  });

  it('a socket without a valid hello is closed when the deadline passes; the others live on', () => {
    const { relay, connect, clock } = core({ helloDeadlineMs: 10_000 });
    const silent = connect();
    const pinger = connect();
    const badHello = connect();
    const ok = connect();
    ok.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    badHello.send({ t: 'hello', proto: 1 });
    for (let s = 1; s <= 9; s++) {
      clock.advance(1000);
      pinger.send({ t: 'ping', ts: s });
      ok.send({ t: 'ping', ts: s });
      relay.sweep();
    }
    assert.equal(silent.conn.closedWith, null);
    clock.advance(1000);
    pinger.send({ t: 'ping', ts: 10 });
    ok.send({ t: 'ping', ts: 10 });
    relay.sweep();
    for (const c of [silent, pinger, badHello]) {
      assert.deepEqual(c.conn.closedWith, { code: CLOSE_CODES.IDLE_TIMEOUT, reason: 'no hello' });
    }
    assert.equal(ok.conn.closedWith, null);
  });

  it('logs refusals once a minute as counts only', () => {
    const { relay, connect, host, lines, clock } = core({
      maxConnectionsPerIp: 3,
      maxRoomsPerIp: 1,
      roomCreatesPerWindow: 0,
      idleTimeoutMs: 1e12,
    });
    host('1.1.1.1');
    host('1.1.1.1'); // its room is refused
    connect('1.1.1.1'); // never says hello
    connect('1.1.1.1'); // a fourth socket: refused
    host('2.2.2.2');
    host('2.2.2.2'); // its room is refused
    relay.sweep();
    assert.ok(!lines.some((l) => l.includes('last minute')), 'nothing yet');
    clock.advance(60_000);
    relay.sweep();
    const line = lines.find((l) => l.includes('last minute'));
    assert.ok(line, 'one summary line');
    assert.match(line, /1 sockets refused over a connection cap, 2 room creates refused, 1 sockets closed without a hello/);
    assert.ok(!/1.1.1.1|2.2.2.2|rate_limited/.test(line), 'no addresses and no error codes');
    const count = lines.length;
    clock.advance(60_000);
    relay.sweep();
    assert.equal(lines.length, count, 'a quiet minute logs nothing');
  });
});

for (const { impl, skip } of await implementations()) {
  describe(`caps over ${impl}`, { skip }, () => {
    let tr;
    const raws = [];
    afterEach(async () => {
      for (const r of raws.splice(0)) r.destroy();
      await tr.close();
    });

    async function raw(headers = []) {
      const res = await RawClient.open(tr.running.port, { extraHeaders: headers });
      if (res.client) raws.push(res.client);
      return res;
    }

    async function health() {
      const res = await fetch(`${tr.running.httpUrl}/health`);
      return { status: res.status, body: await res.json() };
    }

    it('a socket over the total cap is refused before the handshake with 503; /health still answers', async () => {
      tr = await startTestRelay(impl, { limits: { maxConnections: 3 } });
      for (let i = 0; i < 3; i++) await tr.connect();
      const over = await raw();
      assert.equal(over.status, 503);
      assert.equal(over.client, null);
      assert.equal(over.headers['retry-after'], '30');
      await assert.rejects(() => tr.connect(), /could not connect/);
      const h = await health();
      assert.equal(h.status, 200);
      assert.equal(h.body.connections, 3);
      assert.equal(tr.relay.counters.connectionsRefused, 2);
    });

    it('a socket over its address cap gets 429; closing one makes room', async () => {
      tr = await startTestRelay(impl, { limits: { maxConnectionsPerIp: 2 } });
      const a = await tr.connect();
      await tr.connect();
      const over = await raw();
      assert.equal(over.status, 429);
      a.close();
      await waitFor(() => tr.relay.stats().connections === 1, 'the closed socket to be gone');
      assert.equal((await raw()).status, 101);
    });

    it('behind a proxy the cap counts the address the proxy appended; a forged first entry changes nothing', async () => {
      tr = await startTestRelay(impl, { trustProxy: true, limits: { maxConnectionsPerIp: 1 } });
      assert.equal((await raw(['X-Forwarded-For: 9.9.9.9, 1.1.1.1'])).status, 101);
      assert.equal((await raw(['X-Forwarded-For: 2.2.2.2, 1.1.1.1'])).status, 429, 'the same address behind the proxy');
      assert.equal((await raw(['X-Forwarded-For: 1.1.1.1, 3.3.3.3'])).status, 101, 'a different one');
      assert.equal((await raw(['X-Forwarded-For: 4.4.4.4'])).status, 101);
    });

    it('without proxy trust a forwarded header is ignored: every client counts as its socket address', async () => {
      tr = await startTestRelay(impl, { limits: { maxConnectionsPerIp: 1 } });
      assert.equal((await raw(['X-Forwarded-For: 1.1.1.1'])).status, 101);
      assert.equal((await raw(['X-Forwarded-For: 2.2.2.2'])).status, 429);
    });

    it('eight riders behind one address always fit, with a host reconnect on top, under the defaults', async () => {
      tr = await startTestRelay(impl);
      const h = await tr.host(8);
      const guests = [];
      for (let i = 0; i < 7; i++) {
        const g = await tr.guest(h.code);
        assert.equal(g.reply.t, 'joined');
        guests.push(g);
      }
      // The host's wifi drops and it comes back with its token while the old socket lingers.
      const back = await tr.guest(h.code, h.token);
      assert.equal(back.reply.rejoin, true);
      assert.equal(back.reply.peer, 1);
      const s = tr.relay.stats();
      assert.deepEqual([s.rooms, s.peers, s.held], [1, 8, 0]);
      assert.equal(tr.relay.counters.connectionsRefused + tr.relay.counters.createsLimited, 0);
    });

    it('a host that drops and reclaims its room hits no limit, even at one room and one create a minute', async () => {
      tr = await startTestRelay(impl, { limits: { maxRoomsPerIp: 1, maxRooms: 1, roomCreatesPerWindow: 1, maxConnectionsPerIp: 3 } });
      const h = await tr.host(4);
      for (let i = 0; i < 4; i++) {
        h.c.close();
        await waitFor(() => tr.relay.stats().held === 1, 'the host seat to be held');
        const back = await tr.guest(h.code, h.token);
        assert.deepEqual([back.reply.t, back.reply.peer, back.reply.rejoin], ['joined', 1, true]);
        h.c = back.c;
        // Past the join limit of 10 a minute only after many drops: keep the clock moving.
        await tr.advance(10_000, [back.c]);
      }
      assert.equal(tr.relay.counters.createsLimited, 0);
    });

    it('a create over the room cap is rate_limited on the wire and the same socket can still join', async () => {
      tr = await startTestRelay(impl, { limits: { maxRoomsPerIp: 1 } });
      const h = await tr.host();
      const c = await tr.connect();
      c.hello();
      c.send({ t: 'create', max: 8 });
      const e = await c.error('rate_limited');
      assert.equal(e.re, 'create');
      c.send({ t: 'join', code: h.code });
      assert.equal((await c.take('joined')).peer, 2);
    });

    it('a socket that never says hello is closed after 10 s with 4000; a rider that did is not', async () => {
      tr = await startTestRelay(impl);
      const silent = await tr.connect();
      const rider = await tr.connect();
      rider.hello();
      await rider.sync();
      await tr.advance(9_000, [rider]);
      assert.equal(silent.isClosed, false);
      await tr.advance(1_000, [rider]);
      assert.equal((await silent.closed).code, CLOSE_CODES.IDLE_TIMEOUT);
      assert.equal((await silent.closed).reason, 'no hello');
      assert.equal(rider.isClosed, false);
      assert.equal(tr.relay.counters.helloTimeouts, 1);
    });

    it('/health is counts only: fixed fields, no room codes, no addresses', async () => {
      tr = await startTestRelay(impl);
      const h = await tr.host();
      await tr.guest(h.code);
      const { status, body } = await health();
      assert.equal(status, 200);
      assert.deepEqual(Object.keys(body).sort(), ['connections', 'held', 'impl', 'peers', 'proto', 'rooms', 'status', 'uptime_s']);
      for (const k of ['connections', 'held', 'peers', 'rooms']) assert.equal(Number.isInteger(body[k]), true, k);
      const text = JSON.stringify(body);
      assert.ok(!text.includes(h.code) && !text.includes(h.token) && !text.includes('127.0.0.1'));
      const res = await fetch(`${tr.running.httpUrl}/health`, { method: 'HEAD' });
      assert.equal(res.status, 200);
    });

    it('/health stays cheap: many requests while the relay holds its maximum of rooms', async () => {
      tr = await startTestRelay(impl, { limits: { maxRooms: 40, maxRoomsPerIp: 0, roomCreatesPerWindow: 0 } });
      for (let i = 0; i < 40; i++) await tr.host(8);
      const started = performance.now();
      const answers = await Promise.all(Array.from({ length: 200 }, () => health()));
      assert.ok(answers.every((a) => a.status === 200 && a.body.rooms === 40));
      assert.ok(performance.now() - started < 5000, 'two hundred health checks in a few seconds at the most');
    });
  });
}
