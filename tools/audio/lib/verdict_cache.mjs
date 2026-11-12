// A cache of passing verdicts, keyed on everything the verdict read. Used by the scorecard gate test so a
// gate run does not re-render a bank nothing touched; off unless WATTLANDS_TEST_CACHE_DIR names a folder
// (tools/run_tests --node-cache sets it for the gate's fast lane only).
//
// cachedVerdict({cacheDir, key, compute}) runs compute() with node:fs reads recorded: every file read (by
// content hash), every directory listed, every path probed or stat'ed. A passing verdict ({pass: true}) is
// stored with those records under the hash of `key` and of codeFiles' contents and Node's version. A
// later call is a hit only when every record still holds; it then returns {pass: true, cached: true}
// without running compute. It fails closed: a failing verdict is never stored, a call to any fs function
// outside RECORDED (open, streams, callbacks, promises, glob, realpath, whatever a later edit reaches for)
// stores nothing, and an entry that cannot be read or checked counts as a miss.
import crypto from 'node:crypto';
import fs from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const CACHE_ENV = 'WATTLANDS_TEST_CACHE_DIR';
const SCHEMA = 2;

const sha = (data) => crypto.createHash('sha256').update(data).digest('hex');

// The only fs functions whose reads are recorded. Every other function of node:fs (and its .native
// twins), every function of node:fs/promises and the stream classes count as unrecorded.
export const RECORDED = ['readFileSync', 'existsSync', 'readdirSync', 'statSync', 'lstatSync'];
const STREAM_CLASSES = ['ReadStream', 'WriteStream', 'FileReadStream', 'FileWriteStream', 'Utf8Stream'];

// The originals, so checking an entry is never itself recorded.
const real = Object.fromEntries(RECORDED.map((name) => [name, fs[name]]));

function digestOf(kind, p, opts) {
  try {
    if (kind === 'read') return sha(real.readFileSync(p));
    if (kind === 'exists') return real.existsSync(p) ? 'yes' : 'no';
    if (kind === 'readdir') {
      const ents = real.readdirSync(p, { withFileTypes: true });
      return sha(JSON.stringify(ents.map((e) => [e.name, e.isDirectory()]).sort((a, b) => (a[0] < b[0] ? -1 : 1))));
    }
    if (kind === 'stat' || kind === 'lstat') {
      const s = (kind === 'stat' ? real.statSync : real.lstatSync)(p, opts);
      if (!s) return 'missing';
      return `${s.size}:${s.isFile()}:${s.isDirectory()}`;
    }
  } catch (err) {
    return `error:${err.code ?? 'unknown'}`;
  }
  return 'unknown-kind';
}

/**
 * Swaps every fs entry point outside RECORDED for one that calls mark(name) when it is called at depth 0
 * (depth() > 0 is a call from inside a recorded one). Returns a function that puts every original back.
 */
function markUnrecorded(mark, depth) {
  const undo = [];
  const swap = (obj, name, label) => {
    const orig = obj[name];
    const w = function (...args) {
      if (depth() === 0) mark(label);
      return new.target ? Reflect.construct(orig, args, new.target) : Reflect.apply(orig, this, args);
    };
    for (const k of Object.keys(orig)) {
      if (typeof orig[k] !== 'function') continue;
      const inner = orig[k];
      w[k] = (...args) => {
        if (depth() === 0) mark(`${label}.${k}`);
        return inner(...args);
      };
    }
    obj[name] = w;
    undo.push(() => {
      obj[name] = orig;
    });
  };
  for (const name of Object.getOwnPropertyNames(fs)) {
    const d = Object.getOwnPropertyDescriptor(fs, name);
    if (!d || !('value' in d) || typeof d.value !== 'function' || !d.writable) continue;
    // Upper case: the Dirent, Stats and Dir classes, which open nothing themselves.
    if (!/^[a-z]/.test(name) || RECORDED.includes(name)) continue;
    swap(fs, name, name);
  }
  const promises = fs.promises;
  for (const name of Object.keys(promises)) if (typeof promises[name] === 'function') swap(promises, name, `promises.${name}`);
  for (const name of STREAM_CLASSES) {
    const d = Object.getOwnPropertyDescriptor(fs, name);
    if (!d || !d.configurable) continue;
    Object.defineProperty(fs, name, {
      configurable: true,
      enumerable: d.enumerable,
      get() {
        if (depth() === 0) mark(name);
        return d.get ? d.get.call(fs) : d.value;
      },
    });
    undo.push(() => Object.defineProperty(fs, name, d));
  }
  return () => {
    for (const u of undo.reverse()) u();
  };
}

/**
 * Runs fn with fs reads recorded, each digest taken when it was read (so a file changed after the read
 * cannot be stored as read). Returns {value, deps: [[kind, path, digest]], unrecorded: [api]}.
 */
export function recordReads(fn) {
  const seen = new Map();
  const unrecorded = new Set();
  const absOf = (p) => {
    if (typeof p === 'string') return path.resolve(p);
    if (p instanceof URL) return path.resolve(fileURLToPath(p));
    if (Buffer.isBuffer(p)) return path.resolve(p.toString());
    return null;
  };
  const note = (kind, p, digest) => {
    const abs = absOf(p);
    if (abs === null) {
      unrecorded.add(`${kind}(fd)`);
      return;
    }
    const k = `${kind}\0${abs}`;
    const d = digest ?? digestOf(kind, abs);
    // The same path read twice with two contents: nothing about it can be stored.
    if (seen.has(k) && seen.get(k)[2] !== d) unrecorded.add(`${kind} changed during the run: ${abs}`);
    else if (!seen.has(k)) seen.set(k, [kind, abs, d]);
  };
  const patched = {
    readFileSync: (p, opts) => {
      const abs = absOf(p);
      if (abs === null) {
        unrecorded.add('readFileSync(fd)');
        return real.readFileSync(p, opts);
      }
      let buf;
      try {
        buf = real.readFileSync(abs);
      } catch (err) {
        note('read', abs, `error:${err.code ?? 'unknown'}`);
        throw err;
      }
      note('read', abs, sha(buf));
      const enc = typeof opts === 'string' ? opts : opts?.encoding;
      return enc ? buf.toString(enc) : buf;
    },
    existsSync: (p) => {
      note('exists', p);
      return real.existsSync(p);
    },
    readdirSync: (p, ...rest) => {
      // A recursive listing reaches folders the one-level digest does not cover.
      if (rest[0] && typeof rest[0] === 'object' && rest[0].recursive) unrecorded.add('readdirSync(recursive)');
      note('readdir', p);
      return real.readdirSync(p, ...rest);
    },
    statSync: (p, ...rest) => {
      note('stat', p);
      return real.statSync(p, ...rest);
    },
    lstatSync: (p, ...rest) => {
      note('lstat', p);
      return real.lstatSync(p, ...rest);
    },
  };
  // fs's own functions call each other through the module (readFileSync opens with fs.openSync), so a
  // call from inside a recorded one is not a read of its own.
  let depth = 0;
  const wrapped = {};
  for (const [name, fn] of Object.entries(patched)) {
    wrapped[name] = (...args) => {
      if (depth > 0) return real[name](...args);
      depth += 1;
      try {
        return fn(...args);
      } finally {
        depth -= 1;
      }
    };
  }
  // Armed only while fn runs: syncBuiltinESMExports() reads every export, the stream getters included.
  let armed = false;
  const restore = markUnrecorded(
    (name) => armed && unrecorded.add(name),
    () => depth,
  );
  Object.assign(fs, wrapped);
  syncBuiltinESMExports();
  let value;
  try {
    armed = true;
    value = fn();
  } finally {
    armed = false;
    Object.assign(fs, real);
    restore();
    syncBuiltinESMExports();
  }
  return { value, deps: [...seen.values()], unrecorded: [...unrecorded].sort() };
}

/** sha256 over Node's version and the contents of `files` (sorted), the code a verdict depends on. */
export function codeHash(files) {
  const h = crypto.createHash('sha256').update(`node ${process.version}\n`);
  for (const f of [...files].sort()) h.update(`${f}\n`).update(real.readFileSync(f)).update('\n');
  return h.digest('hex');
}

/** Every .mjs file under `dir`, recursively (absolute paths). */
export function mjsFiles(dir) {
  const out = [];
  for (const e of real.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...mjsFiles(p));
    else if (e.name.endsWith('.mjs')) out.push(p);
  }
  return out;
}

/** Where the entry for `key` under `code` lives in cacheDir. */
export function entryPath(cacheDir, key, code) {
  return path.join(cacheDir, `${sha(`${SCHEMA}\n${code}\n${JSON.stringify(key)}`)}.json`);
}

/** True when the entry at `file` exists and every record in it still holds. */
function entryHolds(file, key, code) {
  let entry;
  try {
    entry = JSON.parse(real.readFileSync(file, 'utf8'));
  } catch {
    return false;
  }
  if (!entry || entry.schema !== SCHEMA || entry.code !== code || JSON.stringify(entry.key) !== JSON.stringify(key)) return false;
  if (!entry.pass || !Array.isArray(entry.deps) || entry.deps.length === 0) return false;
  return entry.deps.every((d) => Array.isArray(d) && d.length === 3 && digestOf(d[0], d[1]) === d[2]);
}

/**
 * compute() returns a verdict object with a boolean `pass`. With no cacheDir it just runs compute().
 * code: codeHash() of what compute runs. Returns the verdict, plus cached: true on a hit.
 */
export function cachedVerdict({ cacheDir, key, code, compute }) {
  if (!cacheDir) return compute();
  const file = entryPath(cacheDir, key, code);
  if (entryHolds(file, key, code)) return { pass: true, cached: true };
  const { value, deps, unrecorded } = recordReads(compute);
  if (value && value.pass === true && unrecorded.length === 0 && deps.length > 0) {
    try {
      fs.mkdirSync(cacheDir, { recursive: true });
      const tmp = `${file}.${process.pid}.${crypto.randomBytes(6).toString('hex')}.tmp`;
      fs.writeFileSync(tmp, JSON.stringify({ schema: SCHEMA, code, key, pass: true, deps }));
      fs.renameSync(tmp, file);
    } catch {
      // A cache that cannot be written is only slower.
    }
  }
  return value;
}

/**
 * Deletes every file in cacheDir except the entries named in `keep` (entryPath() results): entries of a
 * bank that is gone, of older code, broken entries and stray temp files. Returns the names removed.
 */
export function pruneEntries(cacheDir, keep) {
  const wanted = new Set(keep.map((f) => path.basename(f)));
  let names;
  try {
    names = real.readdirSync(cacheDir);
  } catch {
    return [];
  }
  const removed = [];
  for (const name of names) {
    if (wanted.has(name)) continue;
    try {
      fs.rmSync(path.join(cacheDir, name), { force: true, recursive: true });
      removed.push(name);
    } catch {
      // Another run may hold it; the next prune tries again.
    }
  }
  return removed.sort();
}
