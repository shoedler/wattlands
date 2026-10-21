// The parts of the RFC 6455 opening handshake both WebSocket layers share. The server
// checks every upgrade request here first, so the `ws` package and the built-in server
// refuse bad handshakes with the same status codes.

import { createHash } from 'node:crypto';
import type { IncomingMessage } from 'node:http';

export const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/** A Sec-WebSocket-Key: 16 random bytes in base64. */
const KEY_RE = /^[+/0-9A-Za-z]{22}==$/;

export interface UpgradeProblem {
  status: number;
  text: string;
  headers?: Record<string, string>;
}

/** Sec-WebSocket-Accept for a client's Sec-WebSocket-Key. */
export function acceptKey(key: string): string {
  return createHash('sha1').update(key + WS_GUID).digest('base64');
}

/** null when `req` is a valid version-13 WebSocket upgrade, else the HTTP refusal. */
export function checkUpgrade(req: IncomingMessage): UpgradeProblem | null {
  if (req.method !== 'GET') return { status: 405, text: 'Method Not Allowed' };
  const upgrade = req.headers.upgrade;
  if (typeof upgrade !== 'string' || upgrade.trim().toLowerCase() !== 'websocket') {
    return { status: 400, text: 'Bad Request' };
  }
  const connection = String(req.headers.connection ?? '')
    .toLowerCase()
    .split(',')
    .map((s) => s.trim());
  if (!connection.includes('upgrade')) return { status: 400, text: 'Bad Request' };
  if (req.headers['sec-websocket-version'] !== '13') {
    return { status: 426, text: 'Upgrade Required', headers: { 'Sec-WebSocket-Version': '13' } };
  }
  const key = req.headers['sec-websocket-key'];
  if (typeof key !== 'string' || !KEY_RE.test(key)) return { status: 400, text: 'Bad Request' };
  return null;
}
