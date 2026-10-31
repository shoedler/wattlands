// The Godot sidecar of a generated WAV. Per-file import params are written here, so no project
// default is needed. A file Godot has already imported keeps its uid, path and dest_files: only the
// lines this module owns, inside [params], are ever changed.

export const COMPRESS_MODE = { pcm: 0, qoa: 2 };
export const LOOP_MODE = { off: 1, forward: 2 };

/** The params of one file. */
export function importParams({ loop = false, compress = 'pcm' }) {
  if (!(compress in COMPRESS_MODE)) throw new Error(`unknown compress mode "${compress}"`);
  return {
    'force/8_bit': false,
    'force/mono': false,
    'force/max_rate': false,
    'force/max_rate_hz': 44100,
    'edit/trim': false,
    'edit/normalize': false,
    'edit/loop_mode': loop ? LOOP_MODE.forward : LOOP_MODE.off,
    'edit/loop_begin': 0,
    'edit/loop_end': -1,
    'compress/mode': COMPRESS_MODE[compress],
  };
}

function paramLines(params) {
  return Object.entries(params).map(([k, v]) => `${k}=${v}`);
}

/** A fresh sidecar for resPath. Godot fills in the rest on --import. */
export function importSkeleton(resPath, params) {
  return [
    '[remap]',
    '',
    'importer="wav"',
    'type="AudioStreamWAV"',
    '',
    '[deps]',
    '',
    `source_file="${resPath}"`,
    '',
    '[params]',
    '',
    ...paramLines(params),
    '',
  ].join('\n');
}

/** The [params] section of a sidecar as {key: raw string}. */
export function readImportParams(text) {
  const out = {};
  let inParams = false;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith('[')) {
      inParams = line === '[params]';
      continue;
    }
    if (!inParams || line === '') continue;
    const eq = line.indexOf('=');
    if (eq > 0) out[line.slice(0, eq)] = line.slice(eq + 1);
  }
  return out;
}

/** text with each named param set; every other line, in and out of [params], stays as it is. */
export function updateImportParams(text, params) {
  const left = new Map(Object.entries(params).map(([k, v]) => [k, String(v)]));
  const lines = text.split(/\r?\n/);
  let inParams = false;
  let sectionEnd = -1;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.startsWith('[')) {
      if (inParams) break;
      inParams = line === '[params]';
      if (inParams) sectionEnd = i + 1;
      continue;
    }
    if (!inParams) continue;
    if (line !== '') sectionEnd = i + 1;
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const key = line.slice(0, eq);
    if (left.has(key)) {
      lines[i] = `${key}=${left.get(key)}`;
      left.delete(key);
    }
  }
  if (sectionEnd < 0) throw new Error('no [params] section');
  lines.splice(sectionEnd, 0, ...[...left].map(([k, v]) => `${k}=${v}`));
  return lines.join('\n');
}

/** The params of `wanted` the sidecar text does not hold, as "key: have != want" strings. */
export function importParamMismatches(text, wanted) {
  const have = readImportParams(text);
  const out = [];
  for (const [k, v] of Object.entries(wanted)) {
    if (have[k] !== String(v)) out.push(`${k}: ${have[k]} != ${v}`);
  }
  return out;
}
