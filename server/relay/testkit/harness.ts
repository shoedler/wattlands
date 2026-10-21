// Test helpers: a relay on a free port with a FakeClock (no periodic sweep: tests advance
// the clock and call sweep themselves), and a JSON client on Node's global WebSocket.
// Lives outside test/ so `node --test` doesn't run it as a test file.

import { FakeClock } from '../src/clock.ts';
import type { Relay } from '../src/relay.ts';
import { startRelay } from '../src/server.ts';
import type { RunningRelay, StartOptions } from '../src/server.ts';
import type { WsImplName } from '../src/ws_layer.ts';

export type Msg = Record<string, unknown> & { t?: string };
type Pred = string | ((m: Msg) => boolean);

const DEFAULT_WAIT_MS = 3000;

/** The implementations the suites run against, with a skip reason for a missing ws. */
export async function implementations(): Promise<{ impl: WsImplName; skip: string | false }[]> {
  let wsSkip: string | false = false;
  try {
    await import('ws');
  } catch {
    if (process.env.RELAY_REQUIRE_WS === '1') throw new Error('RELAY_REQUIRE_WS=1 but the ws package is not installed (npm ci)');
    wsSkip = 'the ws package is not installed (run npm ci in server/relay to test it)';
  }
  return [
    { impl: 'builtin', skip: false },
    { impl: 'ws', skip: wsSkip },
  ];
}

export async function waitFor(cond: () => boolean, what = 'condition', timeoutMs = DEFAULT_WAIT_MS): Promise<void> {
  const deadline = performance.now() + timeoutMs;
  while (!cond()) {
    if (performance.now() > deadline) throw new Error(`timed out waiting for ${what}`);
    await new Promise((r) => setTimeout(r, 2));
  }
}

let syncSeq = 0;

export class TestClient {
  readonly ws: WebSocket;
  /** Every message received, parsed, in order (taken or not). */
  readonly log: Msg[] = [];
  /** Every message received as raw text. */
  readonly raw: string[] = [];
  readonly closed: Promise<{ code: number; reason: string }>;
  isClosed = false;
  #inbox: Msg[] = [];
  #waiters: { pred: (m: Msg) => boolean; resolve: (m: Msg) => void }[] = [];

  constructor(ws: WebSocket) {
    this.ws = ws;
    ws.addEventListener('message', (ev: MessageEvent) => {
      const text = String(ev.data);
      this.raw.push(text);
      const m = JSON.parse(text) as Msg;
      this.log.push(m);
      const i = this.#waiters.findIndex((w) => w.pred(m));
      if (i >= 0) {
        const [w] = this.#waiters.splice(i, 1);
        w.resolve(m);
      } else this.#inbox.push(m);
    });
    this.closed = new Promise((resolve) => {
      ws.addEventListener('close', (ev: CloseEvent) => {
        this.isClosed = true;
        resolve({ code: ev.code, reason: ev.reason });
      });
    });
  }

  static async connect(url: string): Promise<TestClient> {
    const ws = new WebSocket(url);
    const c = new TestClient(ws);
    await new Promise<void>((resolve, reject) => {
      ws.addEventListener('open', () => resolve(), { once: true });
      ws.addEventListener('error', () => reject(new Error(`could not connect to ${url}`)), { once: true });
    });
    return c;
  }

  send(obj: unknown): void {
    this.ws.send(JSON.stringify(obj));
  }

  sendText(text: string): void {
    this.ws.send(text);
  }

  hello(proto: unknown = 1): void {
    this.send({ t: 'hello', proto, game: 'wattlands', build: '0.1.0' });
  }

  /** Wait for the first message (not yet taken) matching `pred` and remove it from the inbox. */
  take(pred: Pred, timeoutMs = DEFAULT_WAIT_MS): Promise<Msg> {
    const p = typeof pred === 'string' ? (m: Msg) => m.t === pred : pred;
    const i = this.#inbox.findIndex(p);
    if (i >= 0) return Promise.resolve(this.#inbox.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { pred: p, resolve: (m: Msg) => {
        clearTimeout(timer);
        resolve(m);
      } };
      const timer = setTimeout(() => {
        const k = this.#waiters.indexOf(waiter);
        if (k >= 0) this.#waiters.splice(k, 1);
        reject(new Error(`timed out waiting for ${typeof pred === 'string' ? pred : 'a matching message'}; inbox: ${JSON.stringify(this.#inbox)}`));
      }, timeoutMs);
      this.#waiters.push(waiter);
    });
  }

  /** The next error message (by code if given). */
  error(code?: string): Promise<Msg> {
    return this.take((m) => m.t === 'error' && (code === undefined || m.code === code));
  }

  /** Messages received and not taken yet. */
  pending(): Msg[] {
    return [...this.#inbox];
  }

  /** Round trip a ping: everything the relay sent this client before it has arrived. */
  async sync(): Promise<void> {
    const ts = ++syncSeq + 0.25;
    this.send({ t: 'ping', ts });
    await this.take((m) => m.t === 'pong' && m.ts === ts);
  }

  close(): void {
    if (!this.isClosed) this.ws.close();
  }
}

export interface TestRelay {
  readonly running: RunningRelay;
  readonly relay: Relay;
  readonly clock: FakeClock;
  readonly url: string;
  connect(): Promise<TestClient>;
  /** Connect, hello and create; returns the host client and the created message. */
  host(max?: number, extra?: Record<string, unknown>): Promise<{ c: TestClient; code: string; token: string }>;
  /** Connect, hello and join; returns the client and its joined (or error) reply. */
  guest(code: string, token?: string | null): Promise<{ c: TestClient; reply: Msg }>;
  /** Advance the fake clock in steps of at most 30 s, keeping `alive` clients pinged, sweeping each step. */
  advance(ms: number, alive?: TestClient[]): Promise<void>;
  /** Wait until the relay processed `n` more messages than when `mark()` was taken. */
  mark(): number;
  processed(mark: number, n: number): Promise<void>;
  close(): Promise<void>;
}

export async function startTestRelay(impl: WsImplName, opts: Partial<StartOptions> = {}): Promise<TestRelay> {
  const clock = new FakeClock(1_000_000);
  const running = await startRelay({ port: 0, host: '127.0.0.1', impl, clock, sweepMs: 0, ...opts });
  const clients: TestClient[] = [];
  const tr: TestRelay = {
    running,
    relay: running.relay,
    clock,
    url: running.url,
    async connect() {
      const c = await TestClient.connect(running.url);
      clients.push(c);
      return c;
    },
    async host(max = 8, extra = {}) {
      const c = await tr.connect();
      c.hello();
      c.send({ t: 'create', max, ...extra });
      const m = await c.take('created');
      return { c, code: String(m.code), token: String(m.token) };
    },
    async guest(code, token = null) {
      const c = await tr.connect();
      c.hello();
      c.send({ t: 'join', code, token });
      const reply = await c.take((m) => m.t === 'joined' || m.t === 'error');
      return { c, reply };
    },
    async advance(ms, alive = []) {
      let left = ms;
      while (left > 0) {
        const step = Math.min(left, 30_000);
        for (const c of alive) if (!c.isClosed) await c.sync();
        clock.advance(step);
        running.relay.sweep();
        left -= step;
      }
      for (const c of alive) if (!c.isClosed) await c.sync();
    },
    mark() {
      return running.relay.counters.received;
    },
    processed(mark, n) {
      return waitFor(() => running.relay.counters.received >= mark + n, `${n} processed messages`);
    },
    async close() {
      for (const c of clients) c.close();
      await running.close(0);
    },
  };
  return tr;
}
