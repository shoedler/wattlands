// A byte-level WebSocket client for frame tests: it writes the handshake and frames by hand
// (masked or not, fragmented, with reserved bits) and parses the server's frames.

import { createHash, randomBytes } from 'node:crypto';
import net from 'node:net';

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

export interface Frame {
  fin: boolean;
  opcode: number;
  payload: Buffer;
}

export interface FrameSpec {
  opcode: number;
  payload?: Buffer | string;
  fin?: boolean;
  mask?: boolean;
  rsv?: number;
}

/** A client frame (masked unless mask is false). */
export function clientFrame(spec: FrameSpec): Buffer {
  const payload = typeof spec.payload === 'string' ? Buffer.from(spec.payload, 'utf8') : (spec.payload ?? Buffer.alloc(0));
  const fin = spec.fin ?? true;
  const mask = spec.mask ?? true;
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
    header.writeUInt32BE(0, 2);
    header.writeUInt32BE(len, 6);
  }
  header[0] = (fin ? 0x80 : 0) | ((spec.rsv ?? 0) << 4) | spec.opcode;
  if (!mask) return Buffer.concat([header, payload]);
  header[1] |= 0x80;
  const key = randomBytes(4);
  const body = Buffer.alloc(len);
  for (let i = 0; i < len; i++) body[i] = payload[i] ^ key[i & 3];
  return Buffer.concat([header, key, body]);
}

export function closePayload(code: number, reason = ''): Buffer {
  const r = Buffer.from(reason, 'utf8');
  const p = Buffer.alloc(2 + r.length);
  p.writeUInt16BE(code, 0);
  r.copy(p, 2);
  return p;
}

export interface HandshakeOptions {
  path?: string;
  method?: string;
  key?: string | null;
  version?: string | null;
  extraHeaders?: string[];
  /** Bytes written in the same packet right after the request (the upgrade's "head"). */
  firstBytes?: Buffer;
}

export interface HandshakeResult {
  status: number;
  headers: Record<string, string>;
  client: RawClient | null;
}

export class RawClient {
  readonly socket: net.Socket;
  readonly frames: Frame[] = [];
  readonly ended: Promise<void>;
  #buf: Buffer;
  #wake: (() => void) | null = null;

  constructor(socket: net.Socket, leftover: Buffer) {
    this.socket = socket;
    this.#buf = leftover;
    this.ended = new Promise((resolve) => socket.once('close', () => resolve()));
    socket.on('data', (chunk: Buffer) => {
      this.#buf = Buffer.concat([this.#buf, chunk]);
      this.#parse();
    });
    socket.on('close', () => this.#wake?.());
    this.#parse();
  }

  static async open(port: number, opts: HandshakeOptions = {}): Promise<HandshakeResult> {
    const socket = net.connect({ port, host: '127.0.0.1' });
    socket.on('error', () => {});
    await new Promise<void>((resolve, reject) => {
      socket.once('connect', () => resolve());
      socket.once('error', reject);
    });
    const key = opts.key === undefined ? randomBytes(16).toString('base64') : opts.key;
    const lines = [
      `${opts.method ?? 'GET'} ${opts.path ?? '/v1'} HTTP/1.1`,
      `Host: 127.0.0.1:${port}`,
      'Upgrade: websocket',
      'Connection: Upgrade',
    ];
    if (key !== null) lines.push(`Sec-WebSocket-Key: ${key}`);
    const version = opts.version === undefined ? '13' : opts.version;
    if (version !== null) lines.push(`Sec-WebSocket-Version: ${version}`);
    lines.push(...(opts.extraHeaders ?? []));
    const request = Buffer.from(`${lines.join('\r\n')}\r\n\r\n`, 'latin1');
    socket.write(opts.firstBytes ? Buffer.concat([request, opts.firstBytes]) : request);

    let buf = Buffer.alloc(0);
    const head = await new Promise<string>((resolve, reject) => {
      const onData = (chunk: Buffer) => {
        buf = Buffer.concat([buf, chunk]);
        const end = buf.indexOf('\r\n\r\n');
        if (end >= 0) {
          socket.off('data', onData);
          const text = buf.subarray(0, end).toString('latin1');
          buf = buf.subarray(end + 4);
          resolve(text);
        }
      };
      socket.on('data', onData);
      socket.once('close', () => reject(new Error('closed before the handshake reply')));
    });
    const [statusLine, ...headerLines] = head.split('\r\n');
    const status = Number(statusLine.split(' ')[1]);
    const headers: Record<string, string> = {};
    for (const l of headerLines) {
      const i = l.indexOf(':');
      if (i > 0) headers[l.slice(0, i).trim().toLowerCase()] = l.slice(i + 1).trim();
    }
    if (status !== 101) {
      socket.destroy();
      return { status, headers, client: null };
    }
    if (key !== null && headers['sec-websocket-accept'] !== createHash('sha1').update(key + GUID).digest('base64')) {
      throw new Error('bad Sec-WebSocket-Accept');
    }
    return { status, headers, client: new RawClient(socket, buf) };
  }

  send(spec: FrameSpec): void {
    this.socket.write(clientFrame(spec));
  }

  sendText(text: string): void {
    this.send({ opcode: 1, payload: text });
  }

  write(bytes: Buffer): void {
    this.socket.write(bytes);
  }

  /** The next frame matching `pred` (frames before it stay queued). */
  async next(pred: (f: Frame) => boolean = () => true, timeoutMs = 3000): Promise<Frame> {
    const deadline = performance.now() + timeoutMs;
    for (;;) {
      const i = this.frames.findIndex(pred);
      if (i >= 0) return this.frames.splice(i, 1)[0];
      if (this.socket.destroyed) throw new Error('socket closed before the expected frame arrived');
      const left = deadline - performance.now();
      if (left <= 0) throw new Error(`timed out waiting for a frame; have ${this.frames.map((f) => f.opcode).join(',')}`);
      await new Promise<void>((resolve) => {
        const t = setTimeout(resolve, left);
        this.#wake = () => {
          clearTimeout(t);
          this.#wake = null;
          resolve();
        };
      });
    }
  }

  /** Wait for the server's close frame: {code, reason}. */
  async closeFrame(): Promise<{ code: number; reason: string }> {
    const f = await this.next((x) => x.opcode === 8);
    return {
      code: f.payload.length >= 2 ? f.payload.readUInt16BE(0) : 1005,
      reason: f.payload.subarray(2).toString('utf8'),
    };
  }

  /** The next text frame, parsed as JSON. */
  async json(): Promise<Record<string, unknown>> {
    const f = await this.next((x) => x.opcode === 1);
    return JSON.parse(f.payload.toString('utf8')) as Record<string, unknown>;
  }

  destroy(): void {
    this.socket.destroy();
  }

  #parse(): void {
    for (;;) {
      const b = this.#buf;
      if (b.length < 2) break;
      let len = b[1] & 0x7f;
      let off = 2;
      if (len === 126) {
        if (b.length < 4) break;
        len = b.readUInt16BE(2);
        off = 4;
      } else if (len === 127) {
        if (b.length < 10) break;
        len = b.readUInt32BE(6);
        off = 10;
      }
      if ((b[1] & 0x80) !== 0) throw new Error('server frames must not be masked');
      if (b.length < off + len) break;
      this.frames.push({ fin: (b[0] & 0x80) !== 0, opcode: b[0] & 0x0f, payload: Buffer.from(b.subarray(off, off + len)) });
      this.#buf = b.subarray(off + len);
    }
    this.#wake?.();
  }
}
