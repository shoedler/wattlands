// The WebSocket layer on the `ws` package (preferred, BRIEF 5.3). Configured to match the
// built-in server: 16 KB messages, no permessage-deflate, UTF-8 validation on.

import type { IncomingMessage } from 'node:http';
import type { Duplex } from 'node:stream';
import type { ConnHandlers, RelayConn } from './relay.ts';
import type { WsLayer } from './ws_layer.ts';

type Listener = (...args: never[]) => void;

interface WsSocket {
  send(data: string): void;
  close(code?: number, reason?: string): void;
  terminate(): void;
  readonly bufferedAmount: number;
  on(event: string, listener: Listener): unknown;
}

interface WsServer {
  handleUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer, cb: (ws: WsSocket) => void): void;
  readonly clients: Set<WsSocket>;
}

type WsServerCtor = new (options: Record<string, unknown>) => WsServer;

function serverClass(mod: unknown): WsServerCtor {
  const m = mod as { WebSocketServer?: unknown; default?: { WebSocketServer?: unknown; Server?: unknown }; Server?: unknown };
  const ctor = m.WebSocketServer ?? m.default?.WebSocketServer ?? m.Server ?? m.default?.Server;
  if (typeof ctor !== 'function') throw new Error('the ws module has no WebSocketServer');
  return ctor as WsServerCtor;
}

/** A layer on an imported `ws` module (`await import('ws')`). */
export function createWsPackageLayer(mod: unknown, maxPayload: number): WsLayer {
  const Server = serverClass(mod);
  const wss = new Server({
    noServer: true,
    clientTracking: true,
    maxPayload,
    perMessageDeflate: false,
    skipUTF8Validation: false,
  });
  return {
    name: 'ws',
    upgrade(req: IncomingMessage, socket: Duplex, head: Buffer, accept: (conn: RelayConn) => ConnHandlers): void {
      wss.handleUpgrade(req, socket, head, (ws: WsSocket) => {
        const conn: RelayConn = {
          send: (text: string) => ws.send(text),
          close: (code: number, reason: string) => ws.close(code, reason),
          get bufferedAmount(): number {
            return ws.bufferedAmount;
          },
        };
        const h = accept(conn);
        ws.on('message', ((data: Buffer | ArrayBuffer | Buffer[], isBinary: boolean) => {
          h.onActivity();
          if (isBinary) h.onBinary();
          else h.onText(Buffer.isBuffer(data) ? data.toString('utf8') : Buffer.from(data as ArrayBuffer).toString('utf8'));
        }) as Listener);
        ws.on('ping', (() => h.onActivity()) as Listener);
        ws.on('pong', (() => h.onActivity()) as Listener);
        ws.on('error', (() => {
          // ws closes the socket itself (1002, 1007, 1009); 'close' reports the drop.
        }) as Listener);
        ws.on('close', (() => h.onClose()) as Listener);
      });
    },
    terminateAll(): void {
      for (const ws of [...wss.clients]) ws.terminate();
    },
    get size(): number {
      return wss.clients.size;
    },
  };
}
