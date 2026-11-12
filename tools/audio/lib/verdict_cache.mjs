// A cache of passing verdicts, keyed on everything the verdict read. Used by the scorecard gate test so a
// gate run does not re-render a bank nothing touched; off unless WATTLANDS_TEST_CACHE_DIR names a folder
// (tools/run_tests --node-cache sets it for the gate's fast lane only).
//
// cachedVerdict({cacheDir, key, compute}) runs compute() with node:fs reads recorded: every file read (by
// content hash), every directory listed, every path probed or stat'ed. A passing verdict ({pass: true}) is
// stored with those records under the hash of `key` and of codeFiles' contents and Node's version. A
// later call is a hit only when every record still holds; it then returns {pass: true, cached: true}
// without running compute. It fails closed: a failing verdict is never stored, a read through an API the
// recorder does not follow (open, streams, callbacks, promises) stores nothing, and an entry that cannot
// be read or checked counts as a miss.
import crypto from 'node:crypto';
import fs from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const CACHE_ENV = 'WATTLANDS_TEST_CACHE_DIR';
const SCHEMA = 2;

const sha = (data) => crypto.createHash('sha256').update(data).digest('hex');

// The originals, so checking an entry is never itself recorded.
const real = {
  readFileSync: fs.readFileSync,
  existsSync: fs.existsSync,
  readdirSync: fs.readdirSync,
  statSync: fs.statSync,
  lstatSync: fs.lstatSync,
};

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

// The fs APIs a compute() may read through without being recorded: using one makes the run uncacheable.
const UNRECORDED = ['openSync', 'readSync', 'readFile', 'createReadStream', 'opendirSync', 'readdir', 'stat', 'access', 'accessSync', 'readvSync'];

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
  const saved = {};
  for (const name of UNRECORDED) {
    saved[name] = fs[name];
    fs[name] = (...args) => {
      if (depth === 0) unrecorded.add(name);
      return saved[name](...args);
    };
  }
  Object.assign(fs, wrapped);
  syncBuiltinESMExports();
  let value;
  try {
    value = fn();
  } finally {
    Object.assign(fs, real, saved);
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

function entryPath(cacheDir, key, code) {
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
