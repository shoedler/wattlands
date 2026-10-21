// The seam between the HTTP server and a WebSocket implementation.

import type { IncomingMessage } from 'node:http';
import type { Duplex } from 'node:stream';
import type { ConnHandlers, RelayConn } from './relay.ts';

export type WsImplName = 'ws' | 'builtin';

export interface WsLayer {
  readonly name: WsImplName;
  /**
   * Finish the opening handshake for `req` (already checked by checkUpgrade) and wire
   * the socket: `accept` is called once with the connection and returns its handlers.
   */
  upgrade(req: IncomingMessage, socket: Duplex, head: Buffer, accept: (conn: RelayConn) => ConnHandlers): void;
  /** Destroy every socket this layer still holds (shutdown). */
  terminateAll(): void;
  /** Sockets currently open. */
  readonly size: number;
}
