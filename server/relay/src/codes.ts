// Room codes (BRIEF 5.2): six characters from the Crockford Base32 alphabet, displayed as
// K7Q-X2M. Input is case-insensitive, ignores dashes and spaces, and maps O to 0 and I or
// L to 1. Mirrors RoomCode.normalize() in addons/wattlands/net/room_code.gd.

import { randomInt } from 'node:crypto';

export const CODE_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
export const CODE_LENGTH = 6;

/** The canonical 6-character code for user input, or null if it can't be one. */
export function normalizeCode(input: string): string | null {
  let out = '';
  for (const ch of input) {
    if (ch === '-' || ch === ' ' || ch === '\t') continue;
    let c = ch >= 'a' && ch <= 'z' ? ch.toUpperCase() : ch;
    if (c === 'O') c = '0';
    else if (c === 'I' || c === 'L') c = '1';
    if (!CODE_ALPHABET.includes(c)) return null;
    out += c;
    if (out.length > CODE_LENGTH) return null;
  }
  return out.length === CODE_LENGTH ? out : null;
}

/** "K7QX2M" -> "K7Q-X2M" (input is normalized first; invalid input comes back unchanged). */
export function formatCode(code: string): string {
  const c = normalizeCode(code);
  return c === null ? code : `${c.slice(0, 3)}-${c.slice(3)}`;
}

/** A uniformly random code from a cryptographic source (or an injected one in tests). */
export function randomCode(nextInt: (max: number) => number = randomInt): string {
  let out = '';
  for (let i = 0; i < CODE_LENGTH; i++) out += CODE_ALPHABET[nextInt(CODE_ALPHABET.length)];
  return out;
}
