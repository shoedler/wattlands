// Unit tests of the pure pieces: room codes, rate limiters, the d-span scanner, and the
// relay core driven through fake connections (no sockets).

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { FakeClock } from '../src/clock.ts';
import { CODE_ALPHABET, CODE_LENGTH, formatCode, normalizeCode, randomCode } from '../src/codes.ts';
import { memberSpan } from '../src/json_span.ts';
import { SlidingWindowLimiter, TokenBucket } from '../src/limits.ts';
import { CLOSE_CODES, DEFAULT_LIMITS, ERROR_CODES, Relay } from '../src/relay.ts';

describe('room codes', () => {
  it('uses the Crockford Base32 alphabet and 6 characters', () => {
    assert.equal(CODE_ALPHABET, '0123456789ABCDEFGHJKMNPQRSTVWXYZ');
    assert.equal(CODE_ALPHABET.length, 32);
    assert.equal(CODE_LENGTH, 6);
  });

  it('normalizes case, dashes, spaces and O/I/L like RoomCode.normalize', () => {
    const cases = {
      K7QX2M: 'K7QX2M',
      'k7q-x2m': 'K7QX2M',
      ' K7Q X2M ': 'K7QX2M',
      'k7q\tx2m': 'K7QX2M',
      'OOO-III': '000111',
      'oil-LOI': '011101',
      '0-1-2-3-4-5': '012345',
    };
    for (const [input, want] of Object.entries(cases)) assert.equal(normalizeCode(input), want, input);
  });

  it('rejects wrong lengths and characters outside the alphabet', () => {
    for (const input of ['', 'K7QX2', 'K7QX2MM', 'K7QX2U', 'K7Q_X2M', 'K7Q.X2M', 'ÄÖÜ123', 'K7QX2M\n', '------']) {
      assert.equal(normalizeCode(input), null, JSON.stringify(input));
    }
  });

  it('formats as K7Q-X2M', () => {
    assert.equal(formatCode('k7qx2m'), 'K7Q-X2M');
    assert.equal(formatCode('nope'), 'nope');
  });

  it('random codes are valid and use the whole alphabet', () => {
    const seen = new Set();
    for (let i = 0; i < 400; i++) {
      const c = randomCode();
      assert.equal(normalizeCode(c), c);
      for (const ch of c) seen.add(ch);
    }
    assert.equal(seen.size, 32);
    let n = 0;
    assert.equal(randomCode(() => n++ % 32), '012345');
  });
});

describe('TokenBucket', () => {
  it('starts full, allows the burst, then refills at the rate', () => {
    const b = new TokenBucket(60, 120, 0);
    for (let i = 0; i < 120; i++) assert.ok(b.take(0));
    assert.equal(b.take(0), false);
    assert.equal(b.take(16), false, '16 ms refills 0.96 tokens');
    assert.ok(b.take(17));
    assert.equal(b.take(17), false);
    assert.ok(Math.abs(b.tokens(1017) - 60.02) < 1e-9);
    assert.equal(b.tokens(1_000_000), 120, 'never above the burst');
  });
});

describe('SlidingWindowLimiter', () => {
  it('allows 10 events per key per 60 s window and forgets old keys', () => {
    const w = new SlidingWindowLimiter(10, 60_000);
    for (let i = 0; i < 10; i++) assert.ok(w.allow('1.2.3.4', i * 1000));
    assert.equal(w.allow('1.2.3.4', 30_000), false);
    assert.ok(w.allow('5.6.7.8', 30_000), 'other keys are independent');
    assert.equal(w.allow('1.2.3.4', 59_999), false);
    assert.ok(w.allow('1.2.3.4', 60_000), 'the first event left the window');
    assert.equal(w.allow('1.2.3.4', 60_000), false);
    w.sweep(200_000);
    assert.equal(w.size, 0);
  });
});

describe('memberSpan', () => {
  const span = (text, key) => {
    const s = memberSpan(text, key);
    return s === null ? null : text.slice(s[0], s[1]);
  };

  it('returns the raw text of a top-level member', () => {
    assert.equal(span('{"t":"msg","to":1,"d":{"a":[1,2,{"b":"}"}]}}', 'd'), '{"a":[1,2,{"b":"}"}]}');
    assert.equal(span('{"d":12345678901234567890}', 'd'), '12345678901234567890');
    assert.equal(span('{ "d" : 1.0 , "t":"msg" }', 'd'), '1.0');
    assert.equal(span('{"d":"a\\"b\\\\","t":1}', 'd'), '"a\\"b\\\\"');
    assert.equal(span('{"d":null}', 'd'), 'null');
    assert.equal(span('{"d":[],"x":{}}', 'x'), '{}');
  });

  it('ignores nested members, decodes escaped keys and keeps the last duplicate like JSON.parse', () => {
    assert.equal(span('{"x":{"d":1}}', 'd'), null);
    assert.equal(span('{"\\u0064":true}', 'd'), 'true');
    assert.equal(span('{"d":1,"d":[2]}', 'd'), '[2]');
    assert.equal(span('{}', 'd'), null);
    assert.equal(span('[1]', 'd'), null);
  });
});

/** A RelayConn that records what the relay does with it. */
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

function fakeRelay(opts = {}) {
  const clock = new FakeClock(0);
  const lines = [];
  const relay = new Relay({ clock, log: (l) => lines.push(l), ...opts });
  const connect = (ip = '10.0.0.1') => {
    const conn = new FakeConn();
    const h = relay.open(conn, ip);
    const send = (obj) => h.onText(typeof obj === 'string' ? obj : JSON.stringify(obj));
    const last = () => conn.sent.at(-1);
    return { conn, h, send, last };
  };
  return { clock, relay, lines, connect };
}

describe('Relay core', () => {
  it('has the BRIEF 5.3 defaults and error codes', () => {
    assert.deepEqual(
      {
        peers: DEFAULT_LIMITS.maxPeers,
        bytes: DEFAULT_LIMITS.maxMessageBytes,
        rate: DEFAULT_LIMITS.msgsPerSecond,
        burst: DEFAULT_LIMITS.msgBurst,
        idle: DEFAULT_LIMITS.idleTimeoutMs,
        joins: DEFAULT_LIMITS.joinAttemptsPerWindow,
        joinWindow: DEFAULT_LIMITS.joinWindowMs,
        life: DEFAULT_LIMITS.roomLifetimeMs,
        reconnect: DEFAULT_LIMITS.reconnectMs,
      },
      { peers: 8, bytes: 16384, rate: 60, burst: 120, idle: 60_000, joins: 10, joinWindow: 60_000, life: 14_400_000, reconnect: 120_000 },
    );
    assert.deepEqual([...ERROR_CODES], ['room_not_found', 'room_full', 'version_mismatch', 'rate_limited', 'bad_request']);
  });

  it('peer ids are never reused inside a room', () => {
    const { connect } = fakeRelay();
    const h = connect();
    h.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    h.send({ t: 'create', max: 8 });
    const code = h.last().code;
    const peers = [];
    for (let i = 0; i < 3; i++) {
      const g = connect();
      g.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
      g.send({ t: 'join', code });
      peers.push(g.last().peer);
      g.send({ t: 'leave' });
    }
    assert.deepEqual(peers, [2, 3, 4]);
  });

  it('closes a slow consumer (4003) instead of buffering without bound', () => {
    const { connect, relay } = fakeRelay();
    const h = connect();
    h.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    h.send({ t: 'create', max: 8 });
    const g = connect();
    g.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    g.send({ t: 'join', code: h.last().code });
    g.conn.bufferedAmount = DEFAULT_LIMITS.maxBufferedBytes + 1;
    h.send({ t: 'msg', to: 0, d: { big: true } });
    assert.deepEqual(g.conn.closedWith, { code: CLOSE_CODES.SLOW_CONSUMER, reason: 'slow consumer' });
    assert.deepEqual(h.last(), { t: 'peer_left', peer: 2, reason: 'dropped' });
    assert.equal(relay.stats().held, 1);
  });

  it('a socket whose send throws counts as dropped', () => {
    const { connect, relay } = fakeRelay();
    const h = connect();
    h.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    h.send({ t: 'create', max: 8 });
    const g = connect();
    g.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    g.send({ t: 'join', code: h.last().code });
    g.conn.send = () => {
      throw new Error('EPIPE');
    };
    h.send({ t: 'msg', to: 2, d: 1 });
    assert.deepEqual(h.last(), { t: 'peer_left', peer: 2, reason: 'dropped' });
    assert.equal(relay.stats().peers, 1);
  });

  it('an internal error is reported as bad_request and the relay keeps running', () => {
    let calls = 0;
    const { connect, lines } = fakeRelay({
      generateCode: () => {
        calls++;
        throw new Error('boom');
      },
    });
    const h = connect();
    h.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    h.send({ t: 'create', max: 8 });
    assert.equal(h.last().code, 'bad_request');
    assert.equal(calls, 1);
    assert.ok(lines.some((l) => l.includes('internal error')));
    h.send({ t: 'ping', ts: 5 });
    assert.deepEqual(h.last(), { t: 'pong', ts: 5 });
  });

  it('retries a generated code that is taken', () => {
    const queue = ['AAAAAA', 'AAAAAA', 'BBBBBB'];
    const { connect } = fakeRelay({ generateCode: () => queue.shift() });
    const a = connect();
    a.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    a.send({ t: 'create', max: 8 });
    const b = connect();
    b.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    b.send({ t: 'create', max: 8 });
    assert.deepEqual([a.last().code, b.last().code], ['AAAAAA', 'BBBBBB']);
  });

  it('never logs room codes, tokens or payloads', () => {
    const { connect, lines, clock, relay } = fakeRelay();
    const h = connect();
    h.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    h.send({ t: 'create', max: 8 });
    const { code, token } = h.last();
    const g = connect();
    g.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    g.send({ t: 'join', code });
    g.send({ t: 'msg', to: 1, d: { secret: 'payload-123' } });
    h.h.onClose();
    clock.advance(200_000);
    relay.sweep();
    assert.ok(lines.length >= 2, 'room created and closed are logged');
    const all = lines.join('\n');
    for (const secret of [code, token, g.conn.sent[0].token, 'payload-123']) assert.ok(!all.includes(secret), secret);
  });

  it('messages after a socket closed are ignored', () => {
    const { connect, relay } = fakeRelay();
    const c = connect();
    c.h.onClose();
    const before = relay.counters.received;
    c.send({ t: 'ping', ts: 1 });
    assert.equal(relay.counters.received, before);
    assert.equal(c.conn.sent.length, 0);
    assert.equal(relay.stats().connections, 0);
  });

  it('shutdown closes every connection with 1001 and sends no peer_left', () => {
    const { connect, relay } = fakeRelay();
    const h = connect();
    h.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    h.send({ t: 'create', max: 8 });
    const g = connect();
    g.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    g.send({ t: 'join', code: h.last().code });
    const sentBefore = h.conn.sent.length;
    relay.shutdown();
    assert.equal(h.conn.closedWith.code, 1001);
    assert.equal(g.conn.closedWith.code, 1001);
    assert.equal(h.conn.sent.length, sentBefore);
    assert.deepEqual(relay.stats(), { rooms: 0, connections: 0, peers: 0, held: 0 });
    const late = connect();
    assert.equal(late.conn.closedWith.code, 1001, 'new sockets are closed during shutdown');
  });

  it('the join limit counts per IP address', () => {
    const { connect } = fakeRelay();
    const a = connect('1.1.1.1');
    a.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    for (let i = 0; i < 10; i++) a.send({ t: 'join', code: 'ZZZZZZ' });
    a.send({ t: 'join', code: 'ZZZZZZ' });
    assert.equal(a.last().code, 'rate_limited');
    const b = connect('2.2.2.2');
    b.send({ t: 'hello', proto: 1, game: 'wattlands', build: 't' });
    b.send({ t: 'join', code: 'ZZZZZZ' });
    assert.equal(b.last().code, 'room_not_found');
  });
});
