// The relay's protocol core (BRIEF 5.3): rooms, peer ids, routing, reconnect tokens and
// limits. It knows nothing about sockets: a WebSocket layer (the `ws` package or the
// built-in RFC 6455 server) hands it a RelayConn per socket and feeds it text messages.
// Every time rule reads the injected Clock; Relay.sweep() applies the time-based ones.
// It never looks inside a message's "d": msg payloads are forwarded byte for byte.

import { randomBytes } from 'node:crypto';
import type { Clock } from './clock.ts';
import { systemClock } from './clock.ts';
import { normalizeCode, randomCode } from './codes.ts';
import { memberSpan } from './json_span.ts';
import { SlidingWindowLimiter, TokenBucket } from './limits.ts';

/** Relay protocol version (hello.proto). */
export const PROTO = 1;
/** The room creator's peer id. */
export const HOST_PEER = 1;
/** msg.to for "everyone in the room except the sender" (host only). */
export const BROADCAST = 0;

export interface Limits {
  /** Seats per room, held seats of dropped peers included (BRIEF 5.3: 8). */
  maxPeers: number;
  /** Largest WebSocket message payload in bytes (16 KB). */
  maxMessageBytes: number;
  /** Sustained messages a second per connection (60) ... */
  msgsPerSecond: number;
  /** ... with this burst (120), as a token bucket. */
  msgBurst: number;
  /**
   * A connection that sends no relay message (text or binary) this long is closed (60 s).
   * WebSocket-level ping and pong frames do not count: only what a client sends to the
   * relay itself (the `ping` message every 15 s, for one) keeps a socket alive.
   */
  idleTimeoutMs: number;
  /** Join attempts per IP address ... (10) */
  joinAttemptsPerWindow: number;
  /** ... per sliding window (60 s). */
  joinWindowMs: number;
  /** A room closes this long after it was created (4 h). */
  roomLifetimeMs: number;
  /** A dropped peer's reconnect token stays valid this long (120 s). */
  reconnectMs: number;
  /** A connection whose unsent output exceeds this is closed as a slow consumer. */
  maxBufferedBytes: number;
  /** At most one rate_limited error per connection per this interval. */
  rateErrorIntervalMs: number;
  /** Open sockets on the whole relay (500); over it a new socket is refused. 0 = no cap. */
  maxConnections: number;
  /** Open sockets from one IP address (64: a venue of eight rooms). 0 = no cap. */
  maxConnectionsPerIp: number;
  /** Open rooms on the whole relay (200); over it `create` gets rate_limited. 0 = no cap. */
  maxRooms: number;
  /** Open rooms (held ones included) whose host connected from one IP address (8). 0 = no cap. */
  maxRoomsPerIp: number;
  /** Room creates per IP address ... (10) 0 = no cap. */
  roomCreatesPerWindow: number;
  /** ... per sliding window (60 s). */
  roomCreateWindowMs: number;
  /** A socket that has not sent a valid `hello` this long after opening is closed (10 s). 0 = no deadline. */
  helloDeadlineMs: number;
}

export const DEFAULT_LIMITS: Readonly<Limits> = Object.freeze({
  maxPeers: 8,
  maxMessageBytes: 16 * 1024,
  msgsPerSecond: 60,
  msgBurst: 120,
  idleTimeoutMs: 60_000,
  joinAttemptsPerWindow: 10,
  joinWindowMs: 60_000,
  roomLifetimeMs: 4 * 3600 * 1000,
  reconnectMs: 120_000,
  maxBufferedBytes: 1024 * 1024,
  rateErrorIntervalMs: 1000,
  maxConnections: 500,
  maxConnectionsPerIp: 64,
  maxRooms: 200,
  maxRoomsPerIp: 8,
  roomCreatesPerWindow: 10,
  roomCreateWindowMs: 60_000,
  helloDeadlineMs: 10_000,
});

/** WebSocket close codes the relay itself sends. */
export const CLOSE_CODES = Object.freeze({
  SHUTDOWN: 1001,
  TOO_BIG: 1009,
  /** The relay is over its connection caps (normally refused before the handshake). */
  TRY_AGAIN: 1013,
  IDLE_TIMEOUT: 4000,
  REPLACED: 4001,
  VERSION_MISMATCH: 4002,
  SLOW_CONSUMER: 4003,
});

export type ErrorCode = 'room_not_found' | 'room_full' | 'version_mismatch' | 'rate_limited' | 'bad_request';
export const ERROR_CODES: readonly ErrorCode[] = Object.freeze([
  'room_not_found',
  'room_full',
  'version_mismatch',
  'rate_limited',
  'bad_request',
]);

/** One client socket, as the WebSocket layer exposes it to the relay. */
export interface RelayConn {
  /** Send one text message. */
  send(text: string): void;
  /** Start the WebSocket closing handshake with this code. */
  close(code: number, reason: string): void;
  /** Bytes queued for sending and not yet written to the network. */
  readonly bufferedAmount: number;
}

/** What the WebSocket layer calls for one socket (returned by Relay.open). */
export interface ConnHandlers {
  onText(text: string): void;
  onBinary(): void;
  /**
   * Any frame arrived (WebSocket ping or pong included). It runs the slow-consumer check
   * but does not reset the idle timer: only a relay message does (onText, onBinary).
   */
  onActivity(): void;
  /** The socket is gone (after a close handshake, an error or a reset). */
  onClose(): void;
}

export interface RelayOptions {
  clock?: Clock;
  limits?: Partial<Limits>;
  /** Room code source (default: crypto-random Crockford codes). */
  generateCode?: () => string;
  /** Reconnect token source (default: 18 random bytes, base64url). */
  generateToken?: () => string;
  /** Operational log lines. Never receives tokens, room codes or payloads. */
  log?: (line: string) => void;
}

export interface RelayStats {
  rooms: number;
  connections: number;
  /** Seats with a live socket. */
  peers: number;
  /** Seats of dropped peers waiting for a reconnect. */
  held: number;
}

interface Seat {
  readonly peer: number;
  /** The seat's reconnect token: issued once, valid until the seat is freed. */
  readonly token: string;
  client: Client | null;
  droppedAt: number;
}

interface Room {
  readonly code: string;
  /** The IP address the host created it from (for the rooms-per-IP cap). */
  readonly ownerIp: string;
  readonly serial: number;
  readonly max: number;
  readonly createdAt: number;
  nextPeer: number;
  readonly seats: Map<number, Seat>;
  readonly tokens: Map<string, Seat>;
}

class Client {
  readonly id: number;
  readonly ip: string;
  readonly conn: RelayConn;
  readonly bucket: TokenBucket;
  readonly openedAt: number;
  lastSeen: number;
  lastRateError = Number.NEGATIVE_INFINITY;
  hello = false;
  closed = false;
  room: Room | null = null;
  seat: Seat | null = null;

  constructor(id: number, ip: string, conn: RelayConn, limits: Limits, now: number) {
    this.id = id;
    this.ip = ip;
    this.conn = conn;
    this.bucket = new TokenBucket(limits.msgsPerSecond, limits.msgBurst, now);
    this.openedAt = now;
    this.lastSeen = now;
  }
}

type Msg = Record<string, unknown>;

export class Relay {
  readonly limits: Readonly<Limits>;
  /** Running totals (also used by tests to wait until the relay processed their input). */
  readonly counters = {
    received: 0,
    sent: 0,
    rateLimited: 0,
    joinsLimited: 0,
    badRequests: 0,
    roomsCreated: 0,
    /** Sockets refused over a connection cap. */
    connectionsRefused: 0,
    /** Creates refused over a room cap or the create rate. */
    createsLimited: 0,
    /** Sockets closed for sending no valid hello in time. */
    helloTimeouts: 0,
  };

  #clock: Clock;
  #log: (line: string) => void;
  #generateCode: () => string;
  #generateToken: () => string;
  #rooms = new Map<string, Room>();
  #clients = new Set<Client>();
  #joins: SlidingWindowLimiter;
  #creates: SlidingWindowLimiter;
  #connsByIp = new Map<string, number>();
  #roomsByIp = new Map<string, number>();
  #refusalsLogged = { at: 0, connections: 0, creates: 0, hello: 0 };
  #nextClientId = 1;
  #nextRoomSerial = 1;
  #closing = false;

  constructor(opts: RelayOptions = {}) {
    this.limits = Object.freeze({ ...DEFAULT_LIMITS, ...(opts.limits ?? {}) });
    this.#clock = opts.clock ?? systemClock;
    this.#log = opts.log ?? (() => {});
    this.#generateCode = opts.generateCode ?? (() => randomCode());
    this.#generateToken = opts.generateToken ?? (() => randomBytes(18).toString('base64url'));
    this.#joins = new SlidingWindowLimiter(this.limits.joinAttemptsPerWindow, this.limits.joinWindowMs);
    this.#creates = new SlidingWindowLimiter(this.limits.roomCreatesPerWindow, this.limits.roomCreateWindowMs);
    this.#refusalsLogged.at = this.#clock.now();
  }

  /**
   * Whether a new socket from `ip` fits under the connection caps: "ok", "ip" (that address
   * holds its share) or "total" (the relay is full). The server asks before the WebSocket
   * handshake, so a refused socket costs no WebSocket state; open() asks again.
   */
  admit(ip: string): 'ok' | 'ip' | 'total' {
    const { maxConnections, maxConnectionsPerIp } = this.limits;
    if (maxConnections > 0 && this.#clients.size >= maxConnections) return 'total';
    if (maxConnectionsPerIp > 0 && (this.#connsByIp.get(ip) ?? 0) >= maxConnectionsPerIp) return 'ip';
    return 'ok';
  }

  /** The server refused a socket before the handshake (counted for the log line). */
  noteRefused(): void {
    this.counters.connectionsRefused++;
  }

  /** Register a new socket from `ip`; the WebSocket layer calls the returned handlers. */
  open(conn: RelayConn, ip: string): ConnHandlers {
    if (!this.#closing && this.admit(ip) !== 'ok') {
      this.counters.connectionsRefused++;
      try {
        conn.close(CLOSE_CODES.TRY_AGAIN, 'too many connections');
      } catch {
        // The socket is already gone.
      }
      return { onText: () => {}, onBinary: () => {}, onActivity: () => {}, onClose: () => {} };
    }
    const c = new Client(this.#nextClientId++, ip, conn, this.limits, this.#clock.now());
    this.#clients.add(c);
    this.#connsByIp.set(ip, (this.#connsByIp.get(ip) ?? 0) + 1);
    if (this.#closing) this.#close(c, CLOSE_CODES.SHUTDOWN, 'relay shutting down');
    return {
      onText: (text: string) => this.#guard(c, () => this.#onText(c, text)),
      onBinary: () => this.#guard(c, () => this.#onBinary(c)),
      onActivity: () => {
        if (c.closed) return;
        // Both layers answer WebSocket pings themselves, outside the rate limit: a client
        // that floods pings and never reads must not grow this socket's backlog forever.
        // They are not activity: a socket that only answers WebSocket pings (any proxy,
        // browser or script can) is still idle, so it can't hold a connection slot forever.
        if (c.conn.bufferedAmount > this.limits.maxBufferedBytes) this.#close(c, CLOSE_CODES.SLOW_CONSUMER, 'slow consumer');
      },
      onClose: () => this.#onSocketClosed(c),
    };
  }

  /** Apply the time rules: idle sockets, reconnect-token expiry, host hold, room lifetime. */
  sweep(): void {
    const now = this.#clock.now();
    const { helloDeadlineMs, idleTimeoutMs } = this.limits;
    for (const c of [...this.#clients]) {
      if (!c.hello && helloDeadlineMs > 0 && now - c.openedAt >= helloDeadlineMs) {
        this.counters.helloTimeouts++;
        this.#close(c, CLOSE_CODES.IDLE_TIMEOUT, 'no hello');
      } else if (now - c.lastSeen >= idleTimeoutMs) this.#close(c, CLOSE_CODES.IDLE_TIMEOUT, 'idle timeout');
    }
    for (const room of [...this.#rooms.values()]) this.#sweepRoom(room, now);
    this.#joins.sweep(now);
    this.#creates.sweep(now);
    this.#logRefusals(now);
  }

  /** At most one line a minute, with counts only (no addresses, codes or tokens). */
  #logRefusals(now: number): void {
    const prev = this.#refusalsLogged;
    if (now - prev.at < 60_000) return;
    const { connectionsRefused: conns, createsLimited: creates, helloTimeouts: hello } = this.counters;
    if (conns > prev.connections || creates > prev.creates || hello > prev.hello) {
      this.#log(
        `last minute: ${conns - prev.connections} sockets refused over a connection cap, ` +
          `${creates - prev.creates} room creates refused, ${hello - prev.hello} sockets closed without a hello`,
      );
    }
    this.#refusalsLogged = { at: now, connections: conns, creates, hello };
  }

  stats(): RelayStats {
    let peers = 0;
    let held = 0;
    for (const room of this.#rooms.values()) {
      for (const s of room.seats.values()) {
        if (s.client) peers++;
        else held++;
      }
    }
    return { rooms: this.#rooms.size, connections: this.#clients.size, peers, held };
  }

  /** Codes of the open rooms (tests and diagnostics; never logged). */
  roomCodes(): string[] {
    return [...this.#rooms.keys()];
  }

  /** Close every socket with 1001 and forget every room. */
  shutdown(): void {
    this.#closing = true;
    for (const c of [...this.#clients]) this.#close(c, CLOSE_CODES.SHUTDOWN, 'relay shutting down');
    this.#rooms.clear();
    this.#roomsByIp.clear();
  }

  // --- input -------------------------------------------------------------------

  #guard(c: Client, fn: () => void): void {
    try {
      fn();
    } catch (err) {
      this.#log(`internal error on connection ${c.id}: ${(err as Error)?.message ?? String(err)}`);
      this.#error(c, 'bad_request', 'internal error');
    }
  }

  #accept(c: Client): boolean {
    if (c.closed) return false;
    this.counters.received++;
    const now = this.#clock.now();
    c.lastSeen = now;
    if (c.bucket.take(now)) return true;
    this.counters.rateLimited++;
    if (now - c.lastRateError >= this.limits.rateErrorIntervalMs) {
      c.lastRateError = now;
      this.#error(c, 'rate_limited', `over ${this.limits.msgsPerSecond} messages a second; message dropped`);
    }
    return false;
  }

  #onBinary(c: Client): void {
    if (!this.#accept(c)) return;
    this.#error(c, 'bad_request', 'binary messages are not supported; send JSON text');
  }

  #onText(c: Client, text: string): void {
    if (!this.#accept(c)) return;
    if (Buffer.byteLength(text, 'utf8') > this.limits.maxMessageBytes) {
      this.#close(c, CLOSE_CODES.TOO_BIG, 'message too big');
      return;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      this.#error(c, 'bad_request', 'invalid JSON');
      return;
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      this.#error(c, 'bad_request', 'a message is a JSON object');
      return;
    }
    const m = parsed as Msg;
    const t = m.t;
    if (typeof t !== 'string') {
      this.#error(c, 'bad_request', 'missing string field "t"');
      return;
    }
    switch (t) {
      case 'hello':
        this.#hello(c, m);
        return;
      case 'create':
        this.#create(c, m);
        return;
      case 'join':
        this.#join(c, m);
        return;
      case 'msg':
        this.#msg(c, m, text);
        return;
      case 'ping':
        this.#ping(c, m);
        return;
      case 'leave':
        this.#leave(c);
        return;
      default:
        this.#error(c, 'bad_request', 'unknown message type', t);
    }
  }

  #hello(c: Client, m: Msg): void {
    if (typeof m.proto !== 'number' || typeof m.game !== 'string' || typeof m.build !== 'string') {
      this.#error(c, 'bad_request', 'hello needs proto (number), game and build (strings)', 'hello');
      return;
    }
    if (m.proto !== PROTO) {
      this.#send(c, {
        t: 'error',
        code: 'version_mismatch',
        detail: `this relay speaks protocol ${PROTO}`,
        re: 'hello',
        proto: PROTO,
      });
      this.#close(c, CLOSE_CODES.VERSION_MISMATCH, 'version mismatch');
      return;
    }
    c.hello = true;
  }

  /** hello received and not in a room yet. */
  #ready(c: Client, t: string): boolean {
    if (!c.hello) {
      this.#error(c, 'bad_request', 'send hello first', t);
      return false;
    }
    if (c.room) {
      this.#error(c, 'bad_request', 'already in a room; leave first', t);
      return false;
    }
    return true;
  }

  #create(c: Client, m: Msg): void {
    if (!this.#ready(c, 'create')) return;
    const max = m.max;
    if (typeof max !== 'number' || !Number.isInteger(max) || max < 1) {
      this.#error(c, 'bad_request', 'create needs an integer max >= 1', 'create');
      return;
    }
    if (m.code !== undefined && m.code !== null && typeof m.code !== 'string') {
      this.#error(c, 'bad_request', 'code must be a string or null', 'create');
      return;
    }
    const now = this.#clock.now();
    if (!this.#roomCapsAllow(c, now)) return;
    // P1: a host may ask for its previous code; it gets it when no open room has it.
    let code: string | null = typeof m.code === 'string' ? normalizeCode(m.code) : null;
    if (code !== null) {
      const existing = this.#rooms.get(code);
      if (existing) this.#sweepRoom(existing, now);
      if (this.#rooms.has(code)) code = null;
    }
    if (code === null) code = this.#newCode();
    const room: Room = {
      code,
      ownerIp: c.ip,
      serial: this.#nextRoomSerial++,
      max: Math.min(max, this.limits.maxPeers),
      createdAt: now,
      nextPeer: HOST_PEER,
      seats: new Map(),
      tokens: new Map(),
    };
    this.#rooms.set(code, room);
    this.#roomsByIp.set(c.ip, (this.#roomsByIp.get(c.ip) ?? 0) + 1);
    const seat = this.#addSeat(room, c);
    this.counters.roomsCreated++;
    this.#send(c, { t: 'created', code, peer: seat.peer, token: seat.token, max: room.max });
    this.#log(`room #${room.serial} created (max ${room.max}); rooms open: ${this.#rooms.size}`);
  }

  /**
   * The room caps for a create from `c`: total rooms, rooms from its address, creates a
   * minute from its address. A refusal is rate_limited and records nothing; an expired
   * room that the sweep has not reached yet never counts against a new one.
   */
  #roomCapsAllow(c: Client, now: number): boolean {
    const { maxRooms, maxRoomsPerIp, roomCreatesPerWindow } = this.limits;
    const over = (): string | null => {
      if (maxRooms > 0 && this.#rooms.size >= maxRooms) return 'the relay has no room for another room right now';
      if (maxRoomsPerIp > 0 && (this.#roomsByIp.get(c.ip) ?? 0) >= maxRoomsPerIp) {
        return `over ${maxRoomsPerIp} open rooms from one address`;
      }
      return null;
    };
    let why = over();
    if (why !== null) {
      for (const room of [...this.#rooms.values()]) this.#sweepRoom(room, now);
      why = over();
    }
    if (why === null && roomCreatesPerWindow > 0 && !this.#creates.allow(c.ip, now)) {
      why = `over ${roomCreatesPerWindow} room creates a minute`;
    }
    if (why === null) return true;
    this.counters.createsLimited++;
    this.#error(c, 'rate_limited', why, 'create');
    return false;
  }

  #join(c: Client, m: Msg): void {
    if (!this.#ready(c, 'join')) return;
    const code = m.code;
    const token = m.token;
    if (typeof code !== 'string') {
      this.#error(c, 'bad_request', 'join needs a code (string)', 'join');
      return;
    }
    if (token !== undefined && token !== null && typeof token !== 'string') {
      this.#error(c, 'bad_request', 'token must be a string or null', 'join');
      return;
    }
    const now = this.#clock.now();
    if (!this.#joins.allow(c.ip, now)) {
      this.counters.joinsLimited++;
      this.#error(c, 'rate_limited', `over ${this.limits.joinAttemptsPerWindow} join attempts a minute`, 'join');
      return;
    }
    const norm = normalizeCode(code);
    let room = norm === null ? undefined : this.#rooms.get(norm);
    if (room) {
      this.#sweepRoom(room, now);
      room = this.#rooms.get(room.code);
    }
    if (!room) {
      this.#error(c, 'room_not_found', 'no open room has this code', 'join');
      return;
    }
    const seat = typeof token === 'string' && token !== '' ? room.tokens.get(token) : undefined;
    if (seat) {
      this.#reclaim(c, room, seat);
      return;
    }
    if (room.seats.size >= room.max) {
      this.#error(c, 'room_full', `the room has ${room.max} seats`, 'join');
      return;
    }
    const s = this.#addSeat(room, c);
    this.#send(c, {
      t: 'joined',
      peer: s.peer,
      host: HOST_PEER,
      token: s.token,
      rejoin: false,
      peers: this.#connectedPeers(room, s.peer),
    });
    this.#broadcast(room, { t: 'peer_joined', peer: s.peer }, s.peer);
  }

  /**
   * A valid reconnect token: the client takes its old peer id back. The token stays the
   * seat's for the room's life, so a reconnect whose `joined` reply is lost (the network
   * drops again, or the app dies before saving) can simply be retried with the same token.
   */
  #reclaim(c: Client, room: Room, seat: Seat): void {
    const old = seat.client;
    if (old) {
      // The old socket is still open (the relay hasn't noticed it die): it is replaced.
      old.room = null;
      old.seat = null;
      seat.client = null;
      this.#close(old, CLOSE_CODES.REPLACED, 'replaced by a reconnect');
      this.#broadcast(room, { t: 'peer_left', peer: seat.peer, reason: 'dropped' }, seat.peer);
    }
    seat.client = c;
    seat.droppedAt = 0;
    c.room = room;
    c.seat = seat;
    this.#send(c, {
      t: 'joined',
      peer: seat.peer,
      host: HOST_PEER,
      token: seat.token,
      rejoin: true,
      peers: this.#connectedPeers(room, seat.peer),
    });
    this.#broadcast(room, { t: 'peer_joined', peer: seat.peer, rejoin: true }, seat.peer);
  }

  #msg(c: Client, m: Msg, raw: string): void {
    const room = c.room;
    const seat = c.seat;
    if (!room || !seat) {
      this.#error(c, 'bad_request', 'create or join a room first', 'msg');
      return;
    }
    const to = m.to;
    if (typeof to !== 'number' || !Number.isInteger(to) || to < 0) {
      this.#error(c, 'bad_request', 'msg needs an integer to >= 0', 'msg');
      return;
    }
    if (!Object.hasOwn(m, 'd')) {
      this.#error(c, 'bad_request', 'msg needs d', 'msg');
      return;
    }
    const from = seat.peer;
    if (from !== HOST_PEER && to !== HOST_PEER) {
      this.#error(c, 'bad_request', 'non-hosts may only send to the host', 'msg');
      return;
    }
    const span = memberSpan(raw, 'd');
    const d = span === null ? JSON.stringify(m.d) : raw.slice(span[0], span[1]);
    const out = `{"t":"msg","from":${from},"d":${d}}`;
    if (to === BROADCAST) {
      for (const s of room.seats.values()) {
        if (s.client && s.peer !== from) this.#sendText(s.client, out);
      }
      return;
    }
    const target = room.seats.get(to);
    // A peer that is gone, dropped or the sender itself: dropped silently (normal races).
    if (target?.client && target.peer !== from) this.#sendText(target.client, out);
  }

  #ping(c: Client, m: Msg): void {
    if (typeof m.ts !== 'number' || !Number.isFinite(m.ts)) {
      this.#error(c, 'bad_request', 'ping needs a numeric ts', 'ping');
      return;
    }
    this.#send(c, { t: 'pong', ts: m.ts });
  }

  #leave(c: Client): void {
    const room = c.room;
    const seat = c.seat;
    if (!room || !seat) return;
    c.room = null;
    c.seat = null;
    seat.client = null;
    if (seat.peer === HOST_PEER) {
      this.#closeRoom(room, 'left');
      return;
    }
    room.seats.delete(seat.peer);
    room.tokens.delete(seat.token);
    this.#broadcast(room, { t: 'peer_left', peer: seat.peer, reason: 'left' }, seat.peer);
  }

  // --- state changes -------------------------------------------------------------

  #addSeat(room: Room, c: Client): Seat {
    const seat: Seat = { peer: room.nextPeer++, token: this.#generateToken(), client: c, droppedAt: 0 };
    room.seats.set(seat.peer, seat);
    room.tokens.set(seat.token, seat);
    c.room = room;
    c.seat = seat;
    return seat;
  }

  #newCode(): string {
    for (let i = 0; i < 64; i++) {
      const code = this.#generateCode();
      if (normalizeCode(code) === code && !this.#rooms.has(code)) return code;
    }
    throw new Error('no free room code found');
  }

  #connectedPeers(room: Room, except: number): number[] {
    const out: number[] = [];
    for (const s of room.seats.values()) if (s.client && s.peer !== except) out.push(s.peer);
    return out;
  }

  #sweepRoom(room: Room, now: number): void {
    if (now - room.createdAt >= this.limits.roomLifetimeMs) {
      this.#closeRoom(room, 'expired');
      return;
    }
    const host = room.seats.get(HOST_PEER);
    if (!host || (host.client === null && now - host.droppedAt >= this.limits.reconnectMs)) {
      this.#closeRoom(room, 'timeout');
      return;
    }
    for (const s of [...room.seats.values()]) {
      if (s.client === null && now - s.droppedAt >= this.limits.reconnectMs) {
        room.seats.delete(s.peer);
        room.tokens.delete(s.token);
      }
    }
  }

  /** host_left to every connected peer; they stay connected, outside any room. */
  #closeRoom(room: Room, reason: string): void {
    if (this.#rooms.get(room.code) === room) {
      this.#rooms.delete(room.code);
      const left = (this.#roomsByIp.get(room.ownerIp) ?? 1) - 1;
      if (left > 0) this.#roomsByIp.set(room.ownerIp, left);
      else this.#roomsByIp.delete(room.ownerIp);
    }
    const text = JSON.stringify({ t: 'host_left', reason });
    for (const s of room.seats.values()) {
      const cl = s.client;
      if (!cl) continue;
      s.client = null;
      cl.room = null;
      cl.seat = null;
      this.#sendText(cl, text);
    }
    room.seats.clear();
    room.tokens.clear();
    this.#log(`room #${room.serial} closed (${reason}); rooms open: ${this.#rooms.size}`);
  }

  #onSocketClosed(c: Client): void {
    if (c.closed) return;
    c.closed = true;
    this.#clients.delete(c);
    const conns = (this.#connsByIp.get(c.ip) ?? 1) - 1;
    if (conns > 0) this.#connsByIp.set(c.ip, conns);
    else this.#connsByIp.delete(c.ip);
    const room = c.room;
    const seat = c.seat;
    c.room = null;
    c.seat = null;
    if (!room || !seat || seat.client !== c) return;
    seat.client = null;
    seat.droppedAt = this.#clock.now();
    if (!this.#closing) this.#broadcast(room, { t: 'peer_left', peer: seat.peer, reason: 'dropped' }, seat.peer);
  }

  #close(c: Client, code: number, reason: string): void {
    if (c.closed) return;
    try {
      c.conn.close(code, reason);
    } catch {
      // The socket is already gone; the drop below still applies.
    }
    this.#onSocketClosed(c);
  }

  // --- output --------------------------------------------------------------------

  #error(c: Client, code: ErrorCode, detail: string, re?: string): void {
    if (code === 'bad_request') this.counters.badRequests++;
    const e: Msg = { t: 'error', code, detail };
    if (re !== undefined) e.re = re.slice(0, 32);
    this.#send(c, e);
  }

  #send(c: Client, obj: Msg): void {
    this.#sendText(c, JSON.stringify(obj));
  }

  #sendText(c: Client, text: string): void {
    if (c.closed) return;
    if (c.conn.bufferedAmount > this.limits.maxBufferedBytes) {
      this.#close(c, CLOSE_CODES.SLOW_CONSUMER, 'slow consumer');
      return;
    }
    try {
      c.conn.send(text);
      this.counters.sent++;
    } catch {
      this.#onSocketClosed(c);
    }
  }

  #broadcast(room: Room, obj: Msg, exceptPeer: number): void {
    const text = JSON.stringify(obj);
    for (const s of room.seats.values()) {
      if (s.client && s.peer !== exceptPeer) this.#sendText(s.client, text);
    }
  }
}
