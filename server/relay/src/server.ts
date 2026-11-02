// The relay's HTTP server: GET /health, the WebSocket endpoint at /v1, and the choice of
// WebSocket layer (the `ws` package when it can be imported, else the built-in server;
// RELAY_WS_IMPL=ws|builtin|auto forces a choice).

import http from 'node:http';
import type { AddressInfo } from 'node:net';
import type { Duplex } from 'node:stream';
import type { Clock } from './clock.ts';
import { systemClock } from './clock.ts';
import { checkUpgrade } from './handshake.ts';
import type { Limits } from './relay.ts';
import { DEFAULT_LIMITS, PROTO, Relay } from './relay.ts';
import { createBuiltinLayer } from './ws_builtin.ts';
import type { WsImplName, WsLayer } from './ws_layer.ts';
import { createWsPackageLayer } from './ws_package.ts';

export type ImplChoice = 'auto' | WsImplName;

/**
 * Where the client's address comes from. false: the socket's own address. true or a number
 * n: the n-th entry from the right of X-Forwarded-For (true is 1), the one the nearest
 * trusted proxy appended; an entry further left is whatever the client sent. "fly":
 * Fly-Client-IP, which Fly's proxy always sets itself.
 */
export type ProxyTrust = boolean | number | 'fly';

export const DEFAULT_PORT = 8787;
export const WS_PATH = '/v1';

export interface StartOptions {
  /** TCP port (default 8787; 0 picks a free one). */
  port?: number;
  /** Interface to bind (default: all interfaces, IPv4 and IPv6). */
  host?: string;
  /** WebSocket layer (default: RELAY_WS_IMPL, else "auto"). */
  impl?: ImplChoice;
  clock?: Clock;
  limits?: Partial<Limits>;
  /** Period of Relay.sweep() in ms (default 1000; 0 = never, the caller sweeps). */
  sweepMs?: number;
  /** Where the client IP comes from behind a proxy (default: the socket address). */
  trustProxy?: ProxyTrust;
  log?: (line: string) => void;
  generateCode?: () => string;
  generateToken?: () => string;
  /** How the `ws` package is imported (tests replace it to simulate a missing package). */
  importWs?: () => Promise<unknown>;
}

export interface RunningRelay {
  /** ws://host:port/v1 for local clients. */
  readonly url: string;
  readonly httpUrl: string;
  readonly port: number;
  readonly impl: WsImplName;
  /** Why this layer was chosen. */
  readonly implNote: string;
  readonly relay: Relay;
  readonly server: http.Server;
  readonly layer: WsLayer;
  /** Close every socket (1001), wait up to `graceMs` for close handshakes, stop listening. */
  close(graceMs?: number): Promise<void>;
}

/** "auto" (default), "ws" or "builtin" from an option or environment value. */
export function parseImpl(value: string | undefined): ImplChoice {
  const v = (value ?? '').trim().toLowerCase();
  if (v === '' || v === 'auto') return 'auto';
  if (v === 'ws' || v === 'builtin') return v;
  throw new Error(`unknown WebSocket implementation "${value}" (use auto, ws or builtin)`);
}

/** Pick the WebSocket layer. "auto" falls back to the built-in server when ws is missing. */
export async function loadWsLayer(
  choice: ImplChoice,
  maxPayload: number,
  importWs: () => Promise<unknown> = () => import('ws'),
): Promise<{ layer: WsLayer; note: string }> {
  if (choice === 'builtin') return { layer: createBuiltinLayer(maxPayload), note: 'built-in RFC 6455 server (forced)' };
  try {
    const mod = await importWs();
    return { layer: createWsPackageLayer(mod, maxPayload), note: 'ws package' };
  } catch (err) {
    const why = (err as { code?: string; message?: string })?.code ?? (err as Error)?.message ?? String(err);
    if (choice === 'ws') throw new Error(`the ws package can't be imported (${why}); install it or use RELAY_WS_IMPL=builtin`);
    return { layer: createBuiltinLayer(maxPayload), note: `built-in RFC 6455 server (ws unavailable: ${why})` };
  }
}

/** An address as a map key: IPv4-mapped IPv6 unwrapped, and nothing longer than an IPv6 address. */
function ipKey(text: string | undefined): string | undefined {
  const t = text?.trim();
  if (!t || t.length > 45) return undefined;
  return t.toLowerCase().startsWith('::ffff:') && t.includes('.') ? t.slice(7) : t;
}

/**
 * The client's IP for the per-address limits (joins, connections, rooms). Behind a proxy
 * only the part the proxy wrote can be trusted: with `trust` n the n-th entry from the
 * right of X-Forwarded-For, never the leftmost, which a client can set to anything. With
 * fewer entries than that, or a missing header, the socket address is used.
 */
export function clientIp(req: http.IncomingMessage, trust: ProxyTrust = false): string {
  const hops = trust === true ? 1 : typeof trust === 'number' ? Math.floor(trust) : 0;
  let forwarded: string | undefined;
  if (trust === 'fly') {
    const fly = req.headers['fly-client-ip'];
    forwarded = ipKey(Array.isArray(fly) ? fly[fly.length - 1] : fly);
  } else if (hops > 0) {
    const xff = req.headers['x-forwarded-for'];
    const entries = (Array.isArray(xff) ? xff.join(',') : (xff ?? '')).split(',').map((e) => e.trim());
    // A header that is absent or has an empty slot (a stray comma) is not a proxy's doing.
    if (entries.length >= hops) forwarded = ipKey(entries[entries.length - hops]);
  }
  return forwarded ?? ipKey(req.socket.remoteAddress) ?? 'unknown';
}

function pathOf(url: string | undefined): string {
  try {
    return new URL(url ?? '/', 'http://relay').pathname;
  } catch {
    return '';
  }
}

function refuse(socket: Duplex, status: number, text: string, headers: Record<string, string> = {}): void {
  const body = `${status} ${text}\n`;
  let head = `HTTP/1.1 ${status} ${text}\r\nConnection: close\r\nContent-Type: text/plain\r\nContent-Length: ${body.length}\r\n`;
  for (const [k, v] of Object.entries(headers)) head += `${k}: ${v}\r\n`;
  if (socket.writable) socket.end(`${head}\r\n${body}`);
  else socket.destroy();
}

function urlHost(host: string | undefined): string {
  if (host === undefined || host === '' || host === '0.0.0.0' || host === '::') return '127.0.0.1';
  return host.includes(':') ? `[${host}]` : host;
}

export async function startRelay(opts: StartOptions = {}): Promise<RunningRelay> {
  const clock = opts.clock ?? systemClock;
  const limits = { ...DEFAULT_LIMITS, ...(opts.limits ?? {}) };
  const log = opts.log ?? (() => {});
  const choice = opts.impl ?? parseImpl(process.env.RELAY_WS_IMPL);
  const { layer, note } = await loadWsLayer(choice, limits.maxMessageBytes, opts.importWs);
  const relay = new Relay({
    clock,
    limits,
    log,
    generateCode: opts.generateCode,
    generateToken: opts.generateToken,
  });
  const trustProxy: ProxyTrust = opts.trustProxy ?? false;
  const startedAt = clock.now();
  let closing = false;

  const server = http.createServer((req, res) => {
    const path = pathOf(req.url);
    if (path === '/health' && (req.method === 'GET' || req.method === 'HEAD')) {
      const body = JSON.stringify({
        status: closing ? 'closing' : 'ok',
        proto: PROTO,
        impl: layer.name,
        uptime_s: Math.floor((clock.now() - startedAt) / 1000),
        ...relay.stats(),
      });
      res.writeHead(closing ? 503 : 200, {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
        'Content-Length': Buffer.byteLength(body),
      });
      res.end(req.method === 'HEAD' ? undefined : body);
      return;
    }
    if (path === WS_PATH) {
      res.writeHead(426, { 'Content-Type': 'text/plain', Upgrade: 'websocket', Connection: 'Upgrade' });
      res.end('This is the Wattlands relay WebSocket endpoint; connect with ws:// or wss://.\n');
      return;
    }
    if (path === '/') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(`Wattlands relay (protocol ${PROTO}). WebSocket: ${WS_PATH}. Health: /health.\n`);
      return;
    }
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end('{"error":"not_found"}');
  });

  server.on('upgrade', (req: http.IncomingMessage, socket: Duplex, head: Buffer) => {
    socket.on('error', () => {});
    if (closing) return refuse(socket, 503, 'Service Unavailable');
    if (pathOf(req.url) !== WS_PATH) return refuse(socket, 404, 'Not Found');
    const problem = checkUpgrade(req);
    if (problem) return refuse(socket, problem.status, problem.text, problem.headers);
    const ip = clientIp(req, trustProxy);
    const verdict = relay.admit(ip);
    if (verdict !== 'ok') {
      relay.noteRefused();
      const full = verdict === 'total';
      return refuse(socket, full ? 503 : 429, full ? 'Service Unavailable' : 'Too Many Requests', { 'Retry-After': '30' });
    }
    layer.upgrade(req, socket, head, (conn) => relay.open(conn, ip));
  });

  server.on('clientError', (_err: Error, socket: Duplex) => {
    if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
    else socket.destroy();
  });

  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen({ port: opts.port ?? DEFAULT_PORT, host: opts.host }, () => {
      server.off('error', reject);
      resolve();
    });
  });

  const port = (server.address() as AddressInfo).port;
  const sweepMs = opts.sweepMs ?? 1000;
  const timer = sweepMs > 0 ? setInterval(() => relay.sweep(), sweepMs) : null;
  timer?.unref();
  let closed: Promise<void> | null = null;

  const running: RunningRelay = {
    url: `ws://${urlHost(opts.host)}:${port}${WS_PATH}`,
    httpUrl: `http://${urlHost(opts.host)}:${port}`,
    port,
    impl: layer.name,
    implNote: note,
    relay,
    server,
    layer,
    close(graceMs = 0): Promise<void> {
      if (closed) return closed;
      closing = true;
      if (timer) clearInterval(timer);
      closed = (async () => {
        const stopped = new Promise<void>((resolve) => server.close(() => resolve()));
        relay.shutdown();
        const deadline = performance.now() + graceMs;
        while (layer.size > 0 && performance.now() < deadline) await new Promise((r) => setTimeout(r, 20));
        layer.terminateAll();
        server.closeAllConnections();
        await stopped;
      })();
      return closed;
    },
  };
  log(`relay listening on ${running.url}; WebSocket layer: ${note}`);
  const cap = (n: number): string => (n > 0 ? String(n) : 'off');
  log(
    `caps: ${cap(limits.maxConnections)} connections (${cap(limits.maxConnectionsPerIp)} per address), ` +
      `${cap(limits.maxRooms)} rooms (${cap(limits.maxRoomsPerIp)} per address), ` +
      `${cap(limits.roomCreatesPerWindow)} room creates a minute per address; proxy trust: ${String(trustProxy)}`,
  );
  return running;
}
