// Workout's PNG helpers: a thin wrapper over the repo's one PNG codec (tools/art/lib/png.mjs).
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { decodePng, encodePng } from '../../../../tools/art/lib/png.mjs';

export { decodePng, encodePng };

/** rgba: Uint8Array of w * h * 4. Creates the folder. */
export function writePng(path, w, h, rgba) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, encodePng(w, h, rgba, { level: 9 }));
}

/** Returns {width, height, data: Uint8Array RGBA8}. */
export function readPng(path) {
  return decodePng(readFileSync(path));
}
