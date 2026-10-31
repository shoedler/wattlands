// audio.json: load, validate (the same list as AudioBank.validate in GDScript, plus recipe checks
// only the generator cares about), the file names of its sounds, and writing or checking them.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { ROOMS } from './dsp.mjs';
import { importParamMismatches, importParams, importSkeleton, updateImportParams } from './import_file.mjs';
import { FAMILY_BAND, FAMILY_BITS, SOURCES, renderSound } from './recipe.mjs';
import { decodeWav, encodeWav } from './wav.mjs';

export const BUSES = new Set(['Master', 'Machines', 'Ambience', 'Sfx', 'UI']);
export const RATES = new Set([11025, 22050]);
export const MAX_LOOP_PLAYERS = 24;
/** Two renders agree when no sample differs by more than one 12-bit step (SPEC 3.5). */
export const DISK_TOLERANCE = 16;
const FX_NAMES = new Set(['lp', 'hp', 'bp', 'peak', 'notch', 'drive', 'crush', 'comb', 'trem', 'gain_env']);
const COMPRESS = new Set(['pcm', 'qoa']);

function validateRecipe(id, s, game, out) {
  const at = `sounds.${id}`;
  if (s.locked && s.loop) out.push(`${at}: a sound is locked or a loop, not both`);
  if (!(typeof s.dur === 'number' && s.dur > 0)) out.push(`${at}.dur: must be a number > 0`);
  if (s.variants !== undefined && !(Number.isInteger(s.variants) && s.variants >= 1)) out.push(`${at}.variants: must be an integer >= 1`);
  if (s.per_variant !== undefined && (!Array.isArray(s.per_variant) || s.per_variant.length !== (s.variants ?? 1))) {
    out.push(`${at}.per_variant: must hold one object per variant`);
  }
  if (s.compress !== undefined && !COMPRESS.has(s.compress)) out.push(`${at}.compress: "${s.compress}" is not pcm or qoa`);
  if (s.room !== undefined && !ROOMS.includes(s.room)) out.push(`${at}.room: unknown room "${s.room}"`);
  if (s.norm !== undefined && s.norm.peak === undefined && s.norm.lufs === undefined) out.push(`${at}.norm: needs peak or lufs`);
  if (s.crush !== undefined && !(Number.isInteger(s.crush) && s.crush >= 2 && s.crush <= FAMILY_BITS)) {
    out.push(`${at}.crush: must be an integer in 2..${FAMILY_BITS}`);
  }
  const rate = s.rate ?? 22050;
  if (!RATES.has(rate)) out.push(`${at}.rate: ${rate} is not 11025 or 22050`);
  else if (s.band !== undefined) {
    const top = FAMILY_BAND[rate];
    if (!Array.isArray(s.band) || s.band.length !== 2 || s.band[0] < top[0] || s.band[1] > top[1] || s.band[0] >= s.band[1]) {
      out.push(`${at}.band: must stay inside the family band ${top[0]}..${top[1]} Hz at ${rate} Hz`);
    }
  }
  const ch = s.ch ?? 1;
  if (ch !== 1 && ch !== 2) out.push(`${at}.ch: ${ch} is not 1 or 2`);
  if (game === '_shared' && (ch !== 1 || rate !== 22050)) out.push(`${at}: _shared sounds are 22050 Hz mono`);
  if (!Array.isArray(s.layers) || s.layers.length === 0) {
    if (!s.per_variant) out.push(`${at}.layers: needs at least one layer`);
  } else {
    s.layers.forEach((l, i) => {
      const la = `${at}.layers[${i}]`;
      if (!SOURCES.has(l.src)) out.push(`${la}.src: unknown source "${l.src}"`);
      for (const fx of l.fx ?? []) {
        const names = Object.keys(fx);
        if (names.length !== 1 || !FX_NAMES.has(names[0])) out.push(`${la}.fx: unknown effect ${JSON.stringify(names)}`);
      }
    });
  }
}

/** Every problem in a bank, as "key.path: reason" strings; [] when it is good. */
export function validateBank(doc) {
  const out = [];
  if (doc === null || typeof doc !== 'object') return ['audio.json: not an object'];
  if (doc.schema !== 1) out.push(`schema: ${doc.schema} is not 1`);
  if (typeof doc.game !== 'string' || doc.game === '') out.push('game: missing');
  if (doc.sounds === null || typeof doc.sounds !== 'object') return [...out, 'sounds: missing'];
  const sounds = doc.sounds;
  const stems = new Map();
  for (const [id, s] of Object.entries(sounds)) {
    validateRecipe(id, s, doc.game, out);
    for (const f of soundFiles(id, s)) {
      if (stems.has(f.stem)) out.push(`sounds.${id}: file ${f.stem}.wav is also made by ${stems.get(f.stem)}`);
      stems.set(f.stem, id);
    }
  }
  const needLoop = (where, layer) => {
    const s = sounds[layer.sound];
    if (!s) out.push(`${where}.sound: "${layer.sound}" is not in sounds`);
    else if (s.loop !== true) out.push(`${where}.sound: "${layer.sound}" is not a loop`);
  };
  const busOk = (where, bus) => {
    if (bus !== undefined && !BUSES.has(bus)) out.push(`${where}.bus: unknown bus "${bus}"`);
  };
  for (const [mid, m] of Object.entries(doc.machines ?? {})) {
    busOk(`machines.${mid}`, m.bus);
    (m.events ?? []).forEach((e, i) => {
      const where = `machines.${mid}.events[${i}]`;
      const s = sounds[e.sound];
      if (!s) out.push(`${where}.sound: "${e.sound}" is not in sounds`);
      else {
        if (s.locked !== true) out.push(`${where}.sound: "${e.sound}" is not locked`);
        if ((s.ch ?? 1) !== 1) out.push(`${where}.sound: "${e.sound}" is stereo; machine events are mono`);
      }
      if (!Array.isArray(e.at)) out.push(`${where}.at: must be an array of revolution fractions`);
      for (const a of [e.at].flat()) {
        if (!(typeof a === 'number' && a >= 0 && a < 1)) out.push(`${where}.at: ${a} is outside [0, 1)`);
      }
    });
    (m.loops ?? []).forEach((l, i) => needLoop(`machines.${mid}.loops[${i}]`, l));
  }
  for (const [lid, l] of Object.entries(doc.loops ?? {})) {
    busOk(`loops.${lid}`, l.bus);
    (l.layers ?? []).forEach((layer, i) => needLoop(`loops.${lid}.layers[${i}]`, layer));
  }
  for (const [bid, b] of Object.entries(doc.beds ?? {})) {
    (b.layers ?? []).forEach((layer, i) => needLoop(`beds.${bid}.layers[${i}]`, layer));
    (b.spots ?? []).forEach((sp, i) => {
      if (!sounds[sp.sound]) out.push(`beds.${bid}.spots[${i}].sound: "${sp.sound}" is not in sounds`);
    });
  }
  for (const [cid, c] of Object.entries(doc.cues ?? {})) {
    (c.hits ?? []).forEach((h, i) => {
      if (!sounds[h.sound]) out.push(`cues.${cid}.hits[${i}].sound: "${h.sound}" is not in sounds`);
      busOk(`cues.${cid}.hits[${i}]`, h.bus);
    });
    (c.duck ?? []).forEach((d, i) => busOk(`cues.${cid}.duck[${i}]`, d.bus));
  }
  const maxLead = Math.max(0, ...Object.values(doc.machines ?? {}).map((m) => (m.loops ?? []).length));
  const loopLayers = Object.values(doc.loops ?? {}).reduce((n, l) => n + (l.layers ?? []).length, 0);
  const maxBed = Math.max(0, ...Object.values(doc.beds ?? {}).map((b) => (b.layers ?? []).length));
  if (maxLead + loopLayers + maxBed > (doc.mix?.max_loop_players ?? MAX_LOOP_PLAYERS)) {
    out.push(`mix.max_loop_players: lead layers ${maxLead} + loops ${loopLayers} + bed ${maxBed} exceed the pool`);
  }
  return out;
}

/** The files of one sound: [{id, variant, stem}]. id.wav, or id_1.wav .. id_n.wav with variants. */
export function soundFiles(id, sound) {
  const n = sound.variants ?? 1;
  if (n <= 1) return [{ id, variant: 0, stem: id }];
  return Array.from({ length: n }, (_, v) => ({ id, variant: v, stem: `${id}_${v + 1}` }));
}

export function allFiles(doc) {
  return Object.entries(doc.sounds).flatMap(([id, s]) => soundFiles(id, s));
}

/** Parse and validate a bank file; throws with every problem named. */
export function loadBank(bankPath) {
  let doc;
  try {
    doc = JSON.parse(fs.readFileSync(bankPath, 'utf8'));
  } catch (e) {
    throw new Error(`${bankPath}: ${e.message}`);
  }
  const problems = validateBank(doc);
  if (problems.length > 0) throw new Error(`${bankPath}:\n  ${problems.join('\n  ')}`);
  return doc;
}

/** "audio.json" -> "audio_manifest.json"; "x_bank.json" -> "x_bank_manifest.json". */
export function manifestPathOf(bankPath) {
  return bankPath.replace(/\.json$/, '_manifest.json');
}

/** Every game with a bank under root, "_shared" first: [{game, bankPath}]. */
export function findBanks(root) {
  const assets = path.join(root, 'assets');
  const out = [];
  let dirs = [];
  try {
    dirs = fs.readdirSync(assets, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name).sort();
  } catch {
    return out;
  }
  for (const d of ['_shared', ...dirs.filter((x) => x !== '_shared')]) {
    const bankPath = path.join(assets, d, 'audio', 'audio.json');
    if (fs.existsSync(bankPath)) out.push({ game: d, bankPath });
  }
  return out;
}

export function bankPathOf(root, game) {
  return path.join(root, 'assets', game, 'audio', 'audio.json');
}

function resPath(root, file) {
  return `res://${path.relative(root, file).split(path.sep).join('/')}`;
}

/** One file rendered: {stem, wav (Buffer), entry (its manifest entry), params (import params)}. */
export function renderFile(doc, file) {
  const sound = doc.sounds[file.id];
  const r = renderSound(file.id, sound, file.variant, { game: doc.game });
  const wav = encodeWav(r.samples, { rate: r.rate, ch: r.ch });
  return {
    stem: file.stem,
    wav,
    params: importParams({ loop: r.loop, compress: r.compress }),
    entry: {
      sound: file.id,
      variant: file.variant,
      rate: r.rate,
      ch: r.ch,
      frames: r.frames,
      loop_frames: r.loopFrames,
      preroll: r.preroll,
      bytes: wav.length,
      sha256: crypto.createHash('sha256').update(wav).digest('hex'),
      peak_db: r.peak_db,
      lufs: r.lufs,
      loop: r.loop,
      locked: r.locked,
      compress: r.compress,
    },
  };
}

function writeManifest(manifestPath, entries) {
  fs.writeFileSync(manifestPath, `${JSON.stringify(entries, null, 2)}\n`);
}

function readManifest(manifestPath) {
  try {
    return JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  } catch {
    return null;
  }
}

/**
 * Write every (or the `only`) sound of a bank beside it. The sidecar is created if absent; on an
 * existing one only its [params] change. With no `only`, WAVs the bank no longer makes are removed.
 */
export function generateBank(bankPath, { root, only = [], prune = true } = {}) {
  const doc = loadBank(bankPath);
  const dir = path.dirname(bankPath);
  const manifestPath = manifestPathOf(bankPath);
  const files = allFiles(doc);
  const wanted = only.length > 0 ? files.filter((f) => only.includes(f.id)) : files;
  for (const id of only) {
    if (!doc.sounds[id]) throw new Error(`--only: "${id}" is not in ${bankPath}`);
  }
  const old = readManifest(manifestPath) ?? {};
  const fresh = {};
  for (const f of wanted) {
    const r = renderFile(doc, f);
    const wavPath = path.join(dir, `${r.stem}.wav`);
    fs.writeFileSync(wavPath, r.wav);
    const sidecar = `${wavPath}.import`;
    const text = fs.existsSync(sidecar) ? updateImportParams(fs.readFileSync(sidecar, 'utf8'), r.params) : importSkeleton(resPath(root, wavPath), r.params);
    fs.writeFileSync(sidecar, text);
    fresh[r.stem] = r.entry;
  }
  const entries = {};
  for (const f of files) {
    const e = fresh[f.stem] ?? old[f.stem];
    if (e) entries[f.stem] = e;
  }
  writeManifest(manifestPath, entries);
  const removed = [];
  if (prune && only.length === 0) {
    const stems = new Set(files.map((f) => f.stem));
    for (const name of fs.readdirSync(dir)) {
      if (name.endsWith('.wav') && !stems.has(name.slice(0, -4))) {
        fs.rmSync(path.join(dir, name));
        fs.rmSync(path.join(dir, `${name}.import`), { force: true });
        removed.push(name);
      }
    }
  }
  return { written: wanted.length, removed, doc };
}

/** How two WAVs differ: null if equal, or within DISK_TOLERANCE of each other. */
export function wavDifference(a, b) {
  if (a.equals(b)) return null;
  const x = decodeWav(a);
  const y = decodeWav(b);
  if (x.rate !== y.rate || x.ch !== y.ch || x.frames !== y.frames) {
    return `format differs: ${x.rate} Hz ${x.ch} ch ${x.frames} frames, disk ${y.rate} Hz ${y.ch} ch ${y.frames} frames`;
  }
  for (let i = 0; i < x.samples.length; i++) {
    const d = Math.abs(x.samples[i] - y.samples[i]);
    if (d > DISK_TOLERANCE) return `sample ${i} differs by ${d}`;
  }
  return null;
}

/** Render in memory and compare with disk; writes nothing. Returns every problem as a string. */
export function checkBank(bankPath, { only = [] } = {}) {
  const problems = [];
  const doc = loadBank(bankPath);
  const dir = path.dirname(bankPath);
  const manifest = readManifest(manifestPathOf(bankPath));
  if (!manifest) problems.push(`${path.basename(manifestPathOf(bankPath))}: missing or not JSON`);
  const files = allFiles(doc);
  const stems = new Set(files.map((f) => f.stem));
  for (const f of files) {
    if (only.length > 0 && !only.includes(f.id)) continue;
    const wavPath = path.join(dir, `${f.stem}.wav`);
    if (!fs.existsSync(wavPath)) {
      problems.push(`${f.stem}.wav: missing`);
      continue;
    }
    const r = renderFile(doc, f);
    const disk = fs.readFileSync(wavPath);
    const diff = wavDifference(r.wav, disk);
    if (diff) problems.push(`${f.stem}.wav: ${diff}`);
    const sidecar = `${wavPath}.import`;
    if (!fs.existsSync(sidecar)) problems.push(`${f.stem}.wav.import: missing`);
    else {
      for (const m of importParamMismatches(fs.readFileSync(sidecar, 'utf8'), r.params)) problems.push(`${f.stem}.wav.import: ${m}`);
    }
    if (manifest) {
      const e = manifest[f.stem];
      if (!e) problems.push(`manifest: no entry for ${f.stem}`);
      else if (e.sha256 !== crypto.createHash('sha256').update(disk).digest('hex')) problems.push(`manifest: ${f.stem} sha256 is not the file on disk`);
    }
  }
  if (only.length === 0) {
    if (manifest) {
      for (const k of Object.keys(manifest)) {
        if (!stems.has(k)) problems.push(`manifest: ${k} is not in the bank`);
      }
    }
    for (const name of fs.readdirSync(dir)) {
      if (name.endsWith('.wav') && !stems.has(name.slice(0, -4))) problems.push(`${name}: on disk but not in the bank`);
    }
  }
  return problems;
}

/** The WAV bytes of a bank's files on disk. */
export function bankWavBytes(bankPath) {
  const dir = path.dirname(bankPath);
  let total = 0;
  for (const name of fs.readdirSync(dir)) {
    if (name.endsWith('.wav')) total += fs.statSync(path.join(dir, name)).size;
  }
  return total;
}

