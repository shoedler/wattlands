// assets/<id>/art.json: schema, defaults and validation (BRIEF 3.10, docs/ART_PIPELINE.md).
import fs from 'node:fs';
import { DEFAULT_ENDPOINT, DEFAULT_QUALITY, endpointLimits, knownEndpoints, loadEndpoints } from './config.mjs';

export const MAX_PALETTE = 32;
export const ID_RE = /^[a-z0-9]+(?:_[a-z0-9]+)*$/;
export const HEX_RE = /^#[0-9a-fA-F]{6}$/;
export const POINTS = [
  'top_left',
  'top_center',
  'top_right',
  'center_left',
  'center',
  'center_right',
  'bottom_left',
  'bottom_center',
  'bottom_right',
];
export const BACKGROUNDS = ['transparent', 'opaque'];
export const DITHERS = ['none', 'ordered'];
export const MAX_SPRITE_EDGE = 4096;

const TOP_KEYS = new Set(['palette', 'style', 'endpoint', 'quality', 'dither', 'sprites', 'notes']);
const SPRITE_KEYS = new Set([
  'id',
  'prompt',
  'size',
  'background',
  'parts',
  'anchor',
  'align',
  'tile',
  'mirror',
  'dither',
  'notes',
]);

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isInt = (v) => Number.isInteger(v);

/** Throws with every problem listed when art.json is invalid. */
export class ArtJsonError extends Error {
  constructor(file, errors) {
    super(`${file}: invalid art.json\n${errors.map((e) => `  - ${e}`).join('\n')}`);
    this.errors = errors;
  }
}

function checkUnknown(obj, allowed, where, errors) {
  for (const k of Object.keys(obj)) {
    if (k.startsWith('_') || allowed.has(k)) continue;
    errors.push(`${where}: unknown key "${k}" (allowed: ${[...allowed].join(', ')}; keys starting with "_" are ignored)`);
  }
}

function checkPoint(v, size, where, errors, allowCoords) {
  if (typeof v === 'string') {
    if (!POINTS.includes(v)) errors.push(`${where}: "${v}" is not one of ${POINTS.join(', ')}`);
    return;
  }
  if (allowCoords && Array.isArray(v) && v.length === 2 && v.every((n) => typeof n === 'number' && Number.isFinite(n))) {
    if (size && (v[0] < 0 || v[1] < 0 || v[0] > size[0] || v[1] > size[1])) {
      errors.push(`${where}: [${v.join(', ')}] lies outside the sprite (0..${size[0]}, 0..${size[1]})`);
    }
    return;
  }
  errors.push(`${where}: expected ${allowCoords ? '[x, y] in art pixels or ' : ''}one of ${POINTS.join(', ')}`);
}

/**
 * Validates parsed art.json data. Returns {errors: [...], art} where art has every default filled:
 * endpoint, quality, dither, and per sprite background, parts, anchor, align, tile, mirror, dither.
 */
export function validateArt(data, endpoints = loadEndpoints()) {
  const errors = [];
  if (!isObj(data)) return { errors: ['the top level must be an object'], art: null };
  checkUnknown(data, TOP_KEYS, 'art.json', errors);

  // palette
  const palette = data.palette;
  if (!Array.isArray(palette) || palette.length === 0) {
    errors.push('palette: expected a non-empty array of "#rrggbb" colors');
  } else {
    if (palette.length > MAX_PALETTE) errors.push(`palette: ${palette.length} colors, at most ${MAX_PALETTE} allowed`);
    const seen = new Set();
    palette.forEach((c, i) => {
      if (typeof c !== 'string' || !HEX_RE.test(c)) {
        errors.push(`palette[${i}]: ${JSON.stringify(c)} is not a "#rrggbb" hex color`);
        return;
      }
      const k = c.toLowerCase();
      if (seen.has(k)) errors.push(`palette[${i}]: ${c} is listed twice`);
      seen.add(k);
    });
  }

  // style
  if (typeof data.style !== 'string' || data.style.trim() === '') {
    errors.push('style: expected a non-empty string (the prompt prefix every sprite shares)');
  }

  // endpoint and quality
  const endpoint = data.endpoint ?? DEFAULT_ENDPOINT;
  let limits = null;
  if (typeof endpoint !== 'string') {
    errors.push('endpoint: expected a string');
  } else {
    limits = endpointLimits(endpoint, endpoints);
    if (!limits) {
      errors.push(
        `endpoint: "${endpoint}" is not in tools/art/endpoints.json (known: ${knownEndpoints(endpoints).join(', ')})`,
      );
    }
  }
  const quality = data.quality ?? DEFAULT_QUALITY;
  if (typeof quality !== 'string') {
    errors.push('quality: expected a string');
  } else if (limits?.params?.quality && !limits.params.quality.includes(quality)) {
    errors.push(`quality: "${quality}" is not one of ${limits.params.quality.join(', ')}`);
  }
  const dither = data.dither ?? 'none';
  if (!DITHERS.includes(dither)) errors.push(`dither: "${dither}" is not one of ${DITHERS.join(', ')}`);
  if (data.notes !== undefined && typeof data.notes !== 'string') errors.push('notes: expected a string');

  // sprites
  const sprites = [];
  if (!Array.isArray(data.sprites) || data.sprites.length === 0) {
    errors.push('sprites: expected a non-empty array');
  } else {
    const ids = new Set();
    data.sprites.forEach((s, i) => {
      const where = `sprites[${i}]${isObj(s) && typeof s.id === 'string' ? ` (${s.id})` : ''}`;
      if (!isObj(s)) {
        errors.push(`${where}: expected an object`);
        return;
      }
      checkUnknown(s, SPRITE_KEYS, where, errors);
      if (typeof s.id !== 'string' || !ID_RE.test(s.id)) {
        errors.push(`${where}.id: expected lower-case letters and digits in words joined by single underscores, got ${JSON.stringify(s.id)}`);
      } else if (ids.has(s.id)) {
        errors.push(`${where}.id: "${s.id}" is used twice`);
      } else {
        ids.add(s.id);
      }
      if (typeof s.prompt !== 'string' || s.prompt.trim() === '') errors.push(`${where}.prompt: expected a non-empty string`);
      let size = null;
      if (
        !Array.isArray(s.size) ||
        s.size.length !== 2 ||
        !s.size.every((n) => isInt(n) && n >= 1 && n <= MAX_SPRITE_EDGE)
      ) {
        errors.push(`${where}.size: expected [width, height] in art pixels, integers 1..${MAX_SPRITE_EDGE}`);
      } else {
        size = s.size;
      }
      const background = s.background ?? 'transparent';
      if (!BACKGROUNDS.includes(background)) errors.push(`${where}.background: "${background}" is not one of ${BACKGROUNDS.join(', ')}`);
      const align = s.align ?? 'bottom_center';
      checkPoint(align, null, `${where}.align`, errors, false);
      const anchor = s.anchor ?? align;
      checkPoint(anchor, size, `${where}.anchor`, errors, true);
      const tile = s.tile ?? false;
      const mirror = s.mirror ?? false;
      if (typeof tile !== 'boolean') errors.push(`${where}.tile: expected true or false`);
      if (typeof mirror !== 'boolean') errors.push(`${where}.mirror: expected true or false`);
      if (mirror === true && tile !== true) errors.push(`${where}.mirror: needs tile: true (mirror alternates flipped tile copies)`);
      const sDither = s.dither ?? dither;
      if (!DITHERS.includes(sDither)) errors.push(`${where}.dither: "${sDither}" is not one of ${DITHERS.join(', ')}`);
      const parts = s.parts ?? {};
      if (!isObj(parts)) {
        errors.push(`${where}.parts: expected an object {name: [x, y, w, h]}`);
      } else {
        for (const [name, rect] of Object.entries(parts)) {
          if (!ID_RE.test(name)) errors.push(`${where}.parts.${name}: part names use lower-case letters, digits and single underscores`);
          if (!Array.isArray(rect) || rect.length !== 4 || !rect.every(isInt)) {
            errors.push(`${where}.parts.${name}: expected [x, y, w, h] integers in art pixels`);
            continue;
          }
          const [x, y, w, h] = rect;
          if (w < 1 || h < 1) errors.push(`${where}.parts.${name}: width and height must be at least 1`);
          if (size && (x < 0 || y < 0 || x + w > size[0] || y + h > size[1])) {
            errors.push(`${where}.parts.${name}: [${rect.join(', ')}] lies outside the ${size[0]}x${size[1]} sprite`);
          }
        }
      }
      if (s.notes !== undefined && typeof s.notes !== 'string') errors.push(`${where}.notes: expected a string`);
      sprites.push({
        id: s.id,
        prompt: s.prompt,
        size,
        background,
        parts,
        anchor,
        align,
        tile,
        mirror,
        dither: sDither,
      });
    });
  }
  if (errors.length > 0) return { errors, art: null };
  return {
    errors,
    art: {
      palette: palette.map((c) => c.toLowerCase()),
      style: data.style,
      endpoint,
      quality,
      dither,
      sprites,
    },
  };
}

/** Reads and validates an art.json file; throws ArtJsonError with every problem. */
export function loadArt(file, endpoints = loadEndpoints()) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (err) {
    throw new ArtJsonError(file, [`cannot read it: ${err.code ?? err.message}`]);
  }
  let data;
  try {
    data = JSON.parse(text);
  } catch (err) {
    throw new ArtJsonError(file, [`not valid JSON: ${err.message}`]);
  }
  const { errors, art } = validateArt(data, endpoints);
  if (errors.length > 0) throw new ArtJsonError(file, errors);
  return art;
}

/** The prompt sent to fal: the shared style prefix, then the sprite's own prompt. */
export function composePrompt(art, sprite) {
  return `${art.style.trim()} ${sprite.prompt.trim()}`;
}
