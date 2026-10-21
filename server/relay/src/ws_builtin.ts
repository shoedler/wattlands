// A zero-dependency RFC 6455 WebSocket server on node:http's upgrade event (BRIEF 5.3).
// Scope: version 13 handshake; text, binary, continuation, close, ping and pong frames;
// client frames must be masked; one message carries at most `maxPayload` bytes across its
// fragments; no extensions and no subprotocols (permessage-deflate offers are ignored).
// Protocol errors close with 1002, oversize messages with 1009, invalid UTF-8 with 1007.

import type { IncomingMessage } from 'node:http';
import type { Duplex } from 'node:stream';
import { acceptKey } from './handshake.ts';
import type { ConnHandlers, RelayConn } from './relay.ts';
import type { WsLayer } from './ws_layer.ts';

export const OP = Object.freeze({ CONT: 0x0, TEXT: 0x1, BINARY: 0x2, CLOSE: 0x8, PING: 0x9, PONG: 0xa });

/** How long a closing socket waits for the peer's close frame before it is destroyed. */
const CLOSE_WAIT_MS = 2000;

const utf8 = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
const EMPTY = Buffer.alloc(0);

/** An unmasked server frame. */
export function encodeFrame(opcode: number, payload: Buffer, fin = true): Buffer {
  const len = payload.length;
  let header: Buffer;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[1] = len;
  } else if (len < 0x10000) {
    header = Buffer.alloc(4);
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[1] = 127;
    header.writeUInt32BE(Math.floor(len / 0x100000000), 2);
    header.writeUInt32BE(len >>> 0, 6);
  }
  header[0] = (fin ? 0x80 : 0) | opcode;
  return Buffer.concat([header, payload]);
}

/** Close codes a peer may send in a close frame (RFC 6455 7.4, IANA registry). */
export function isValidCloseCode(code: number): boolean {
  return (code >= 1000 && code <= 1014 && code !== 1004 && code !== 1005 && code !== 1006) || (code >= 3000 && code <= 4999);
}

interface SocketLike extends Duplex {
  setNoDelay?: (noDelay?: boolean) => unknown;
  setTimeout?: (ms: number) => unknown;
}

export class BuiltinSocket implements RelayConn {
  #socket: SocketLike;
  #maxPayload: number;
  #onGone: () => void;
  #handlers: ConnHandlers | null = null;
  /** Received bytes not parsed yet, joined only once a whole frame (or header) is there. */
  #chunks: Buffer[] = [];
  #chunkBytes = 0;
  /** Bytes the frame being received needs before parsing can continue. */
  #need = 2;
  #buf: Buffer = EMPTY;
  #fragOpcode = 0;
  #fragments: Buffer[] = [];
  #fragBytes = 0;
  #closeSent = false;
  #closeReceived = false;
  #failed = false;
  #finished = false;
  #closeTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(socket: Duplex, maxPayload: number, onGone: () => void) {
    this.#socket = socket as SocketLike;
    this.#maxPayload = maxPayload;
    this.#onGone = onGone;
    this.#socket.setTimeout?.(0);
    this.#socket.setNoDelay?.(true);
    socket.on('data', (chunk: Buffer) => this.feed(chunk));
    socket.on('error', () => {
      // A reset or write error; 'close' follows and reports the drop.
    });
    socket.on('end', () => {
      if (this.#socket.writable) this.#socket.end();
    });
    socket.on('close', () => this.#finish());
  }

  attach(handlers: ConnHandlers): void {
    this.#handlers = handlers;
  }

  get bufferedAmount(): number {
    return this.#socket.writableLength ?? 0;
  }

  send(text: string): void {
    if (this.#closeSent || this.#finished || !this.#socket.writable) return;
    this.#socket.write(encodeFrame(OP.TEXT, Buffer.from(text, 'utf8')));
  }

  close(code: number, reason: string): void {
    if (this.#finished) return;
    if (!this.#closeSent) this.#sendClose(code, reason);
    if (this.#closeReceived) {
      this.#socket.end();
      return;
    }
    this.#armCloseTimer();
  }

  terminate(): void {
    this.#socket.destroy();
  }

  /** Parse incoming bytes (also used for the bytes that came with the upgrade request). */
  feed(chunk: Buffer): void {
    if (this.#failed || this.#closeReceived || this.#finished) return;
    this.#chunks.push(chunk);
    this.#chunkBytes += chunk.length;
    // A frame trickling in byte by byte is joined once, not once per byte.
    if (this.#chunkBytes < this.#need) return;
    this.#buf = this.#chunks.length === 1 ? this.#chunks[0] : Buffer.concat(this.#chunks, this.#chunkBytes);
    this.#chunks = [];
    this.#chunkBytes = 0;
    while (!this.#failed && !this.#closeReceived && this.#parseOne()) {
      // one frame per iteration
    }
    if (!this.#failed && !this.#closeReceived && this.#buf.length > 0) {
      this.#chunks = [this.#buf];
      this.#chunkBytes = this.#buf.length;
    }
    this.#buf = EMPTY;
  }

  /** Consume one complete frame from the buffer; false when more bytes are needed or on error. */
  #parseOne(): boolean {
    const buf = this.#buf;
    this.#need = 2;
    if (buf.length < 2) return false;
    const b0 = buf[0];
    const b1 = buf[1];
    const fin = (b0 & 0x80) !== 0;
    const opcode = b0 & 0x0f;
    if ((b0 & 0x70) !== 0) return this.#fail(1002, 'reserved bits must be clear');
    if ((b1 & 0x80) === 0) return this.#fail(1002, 'client frames must be masked');
    const control = (opcode & 0x08) !== 0;
    if (control) {
      if (opcode !== OP.CLOSE && opcode !== OP.PING && opcode !== OP.PONG) return this.#fail(1002, 'unknown opcode');
      if (!fin) return this.#fail(1002, 'control frames must not be fragmented');
    } else {
      if (opcode !== OP.CONT && opcode !== OP.TEXT && opcode !== OP.BINARY) return this.#fail(1002, 'unknown opcode');
      if (opcode === OP.CONT && this.#fragOpcode === 0) return this.#fail(1002, 'continuation without a message');
      if (opcode !== OP.CONT && this.#fragOpcode !== 0) return this.#fail(1002, 'expected a continuation frame');
    }
    let len = b1 & 0x7f;
    let off = 2;
    if (len === 126) {
      this.#need = 4;
      if (buf.length < 4) return false;
      len = buf.readUInt16BE(2);
      off = 4;
    } else if (len === 127) {
      this.#need = 10;
      if (buf.length < 10) return false;
      const hi = buf.readUInt32BE(2);
      if ((hi & 0x80000000) !== 0) return this.#fail(1002, 'invalid payload length');
      if (hi !== 0) return this.#fail(1009, 'message too big');
      len = buf.readUInt32BE(6);
      off = 10;
    }
    if (control && len > 125) return this.#fail(1002, 'control frame payload too long');
    if (!control) {
      const total = (opcode === OP.CONT ? this.#fragBytes : 0) + len;
      if (total > this.#maxPayload) return this.#fail(1009, 'message too big');
    }
    const end = off + 4 + len;
    this.#need = end;
    if (buf.length < end) return false;
    const m0 = buf[off];
    const m1 = buf[off + 1];
    const m2 = buf[off + 2];
    const m3 = buf[off + 3];
    const payload = Buffer.allocUnsafe(len);
    const start = off + 4;
    for (let i = 0; i < len; i++) {
      const k = (i & 3) === 0 ? m0 : (i & 3) === 1 ? m1 : (i & 3) === 2 ? m2 : m3;
      payload[i] = buf[start + i] ^ k;
    }
    this.#buf = buf.subarray(end);
    this.#need = 2;
    this.#handlers?.onActivity();
    switch (opcode) {
      case OP.TEXT:
      case OP.BINARY:
        if (fin) this.#deliver(opcode, payload);
        else {
          this.#fragOpcode = opcode;
          this.#fragments = [payload];
          this.#fragBytes = len;
        }
        break;
      case OP.CONT: {
        this.#fragments.push(payload);
        this.#fragBytes += len;
        if (fin) {
          const op = this.#fragOpcode;
          const data = Buffer.concat(this.#fragments);
          this.#fragOpcode = 0;
          this.#fragments = [];
          this.#fragBytes = 0;
          this.#deliver(op, data);
        }
        break;
      }
      case OP.PING:
        if (!this.#closeSent && this.#socket.writable) this.#socket.write(encodeFrame(OP.PONG, payload));
        break;
      case OP.PONG:
        break;
      case OP.CLOSE:
        this.#onCloseFrame(payload);
        break;
    }
    return !this.#failed;
  }

  #deliver(opcode: number, data: Buffer): void {
    if (opcode === OP.BINARY) {
      this.#handlers?.onBinary();
      return;
    }
    let text: string;
    try {
      text = utf8.decode(data);
    } catch {
      this.#fail(1007, 'invalid UTF-8');
      return;
    }
    this.#handlers?.onText(text);
  }

  #onCloseFrame(payload: Buffer): void {
    this.#closeReceived = true;
    let code = 1005;
    if (payload.length === 1) {
      this.#fail(1002, 'invalid close frame');
      return;
    }
    if (payload.length >= 2) {
      code = payload.readUInt16BE(0);
      if (!isValidCloseCode(code)) {
        this.#fail(1002, 'invalid close code');
        return;
      }
      try {
        utf8.decode(payload.subarray(2));
      } catch {
        this.#fail(1007, 'invalid UTF-8 in close reason');
        return;
      }
    }
    if (!this.#closeSent) {
      this.#closeSent = true;
      if (this.#socket.writable) {
        this.#socket.write(encodeFrame(OP.CLOSE, code === 1005 ? Buffer.alloc(0) : payload.subarray(0, 2)));
      }
    }
    // The server closes the TCP connection once both close frames have been exchanged.
    if (this.#socket.writable) this.#socket.end();
    this.#armCloseTimer();
  }

  #fail(code: number, reason: string): false {
    this.#failed = true;
    this.#buf = EMPTY;
    this.#chunks = [];
    this.#chunkBytes = 0;
    this.#fragments = [];
    if (!this.#closeSent) this.#sendClose(code, reason);
    if (this.#socket.writable) this.#socket.end();
    this.#armCloseTimer();
    return false;
  }

  #sendClose(code: number, reason: string): void {
    this.#closeSent = true;
    if (!this.#socket.writable) return;
    const r = Buffer.from(reason, 'utf8').subarray(0, 123);
    const p = Buffer.alloc(2 + r.length);
    p.writeUInt16BE(code, 0);
    r.copy(p, 2);
    this.#socket.write(encodeFrame(OP.CLOSE, p));
  }

  #armCloseTimer(): void {
    if (this.#closeTimer !== null || this.#finished) return;
    this.#closeTimer = setTimeout(() => this.#socket.destroy(), CLOSE_WAIT_MS);
    this.#closeTimer.unref?.();
  }

  #finish(): void {
    if (this.#finished) return;
    this.#finished = true;
    if (this.#closeTimer !== null) clearTimeout(this.#closeTimer);
    this.#closeTimer = null;
    this.#onGone();
    this.#handlers?.onClose();
  }
}

/** The built-in layer; `maxPayload` is the largest message in bytes (16 KB for the relay). */
export function createBuiltinLayer(maxPayload: number): WsLayer {
  const sockets = new Set<BuiltinSocket>();
  return {
    name: 'builtin',
    upgrade(req: IncomingMessage, socket: Duplex, head: Buffer, accept: (conn: RelayConn) => ConnHandlers): void {
      const key = String(req.headers['sec-websocket-key']);
      socket.write(
        'HTTP/1.1 101 Switching Protocols\r\n' +
          'Upgrade: websocket\r\n' +
          'Connection: Upgrade\r\n' +
          `Sec-WebSocket-Accept: ${acceptKey(key)}\r\n\r\n`,
      );
      const ws = new BuiltinSocket(socket, maxPayload, () => sockets.delete(ws));
      sockets.add(ws);
      ws.attach(accept(ws));
      if (head.length > 0) ws.feed(Buffer.from(head));
    },
    terminateAll(): void {
      for (const s of [...sockets]) s.terminate();
    },
    get size(): number {
      return sockets.size;
    },
  };
}
