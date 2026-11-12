// lib/verdict_cache.mjs: a passing verdict is reused only while everything it read is unchanged, and
// the cache fails closed.

import assert from 'node:assert/strict';
import fs, { readFileSync as namedReadFileSync } from 'node:fs';
import { readFile as namedPromisesReadFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';
import { cachedVerdict, codeHash, entryPath, pruneEntries, recordReads } from '../lib/verdict_cache.mjs';
import { tempDir } from './helpers.mjs';

/** A cache dir, a data dir with two files, and a counting compute over them. */
function setup(t, { pass = () => true } = {}) {
  const root = tempDir(t);
  const cacheDir = path.join(root, 'cache');
  const data = path.join(root, 'data');
  fs.mkdirSync(data);
  fs.writeFileSync(path.join(data, 'a.txt'), 'alpha');
  fs.writeFileSync(path.join(data, 'b.bin'), Buffer.from([1, 2, 3]));
  let runs = 0;
  const compute = () => {
    runs += 1;
    const names = fs.readdirSync(data).sort();
    const a = fs.readFileSync(path.join(data, 'a.txt'), 'utf8');
    const extra = fs.existsSync(path.join(data, 'extra.txt'));
    const size = fs.statSync(path.join(data, 'b.bin')).size;
    return { pass: pass(a), seen: `${names.join(',')}|${a}|${extra}|${size}` };
  };
  const call = (over = {}) => cachedVerdict({ cacheDir, key: { k: 1 }, code: 'code-1', compute, ...over });
  return { root, cacheDir, data, call, runs: () => runs };
}

test('without a cache dir every call computes', (t) => {
  const s = setup(t);
  s.call({ cacheDir: null });
  s.call({ cacheDir: null });
  assert.equal(s.runs(), 2);
  assert.equal(fs.existsSync(s.cacheDir), false);
});

test('a pass is kept and reused while nothing it read changed', (t) => {
  const s = setup(t);
  assert.equal(s.call().cached, undefined);
  const hit = s.call();
  assert.deepEqual(hit, { pass: true, cached: true });
  assert.equal(s.runs(), 1);
});

test('a changed file, a new file in a listed folder, a probed path that appears or a new size each miss', (t) => {
  const s = setup(t);
  s.call();
  const edits = [
    () => fs.writeFileSync(path.join(s.data, 'a.txt'), 'alphA'),
    () => fs.writeFileSync(path.join(s.data, 'c.txt'), 'new'),
    () => fs.writeFileSync(path.join(s.data, 'extra.txt'), 'now here'),
    () => fs.writeFileSync(path.join(s.data, 'b.bin'), Buffer.from([1, 2, 3, 4])),
  ];
  let expected = 1;
  for (const edit of edits) {
    edit();
    assert.equal(s.call().cached, undefined, 'a miss after the edit');
    expected += 1;
    assert.equal(s.runs(), expected);
    assert.equal(s.call().cached, true, 'then a hit again');
  }
});

test('another key or another code hash misses', (t) => {
  const s = setup(t);
  s.call();
  s.call({ key: { k: 2 } });
  s.call({ code: 'code-2' });
  assert.equal(s.runs(), 3);
});

test('a failing verdict is never kept', (t) => {
  const s = setup(t, { pass: () => false });
  assert.equal(s.call().pass, false);
  assert.equal(s.call().pass, false);
  assert.equal(s.runs(), 2);
});

test('a read the recorder cannot follow keeps nothing', (t) => {
  const s = setup(t);
  const file = path.join(s.data, 'a.txt');
  const viaFd = () => {
    const fd = fs.openSync(file, 'r');
    try {
      const buf = Buffer.alloc(5);
      fs.readSync(fd, buf, 0, 5, 0);
      return { pass: true };
    } finally {
      fs.closeSync(fd);
    }
  };
  let runs = 0;
  const compute = () => {
    runs += 1;
    fs.readFileSync(file);
    return viaFd();
  };
  cachedVerdict({ cacheDir: s.cacheDir, key: 'fd', code: 'c', compute });
  cachedVerdict({ cacheDir: s.cacheDir, key: 'fd', code: 'c', compute });
  assert.equal(runs, 2);
  const r = recordReads(compute);
  assert.ok(r.unrecorded.includes('openSync'), r.unrecorded.join(','));
});

// Fails closed: the recorder follows five functions, and every other way into the file system marks the
// run unrecorded, the ones added to Node later included.
test('any fs entry point outside the recorded five keeps nothing', async (t) => {
  const s = setup(t);
  const file = path.join(s.data, 'a.txt');
  // What a use leaves running (a promise, a callback, a stream), awaited before the folder goes.
  const pending = [];
  const closed = (st) => {
    pending.push(new Promise((done) => st.on('error', done).on('close', done)));
    st.destroy();
  };
  const uses = {
    globSync: () => fs.globSync('*.txt', { cwd: s.data }),
    realpathSync: () => fs.realpathSync(file),
    'realpathSync.native': () => fs.realpathSync.native(file),
    'promises.readFile': () => pending.push(namedPromisesReadFile(file).catch(() => {})),
    'promises.readdir': () => pending.push(fs.promises.readdir(s.data).catch(() => {})),
    readFile: () => pending.push(new Promise((done) => fs.readFile(file, done))),
    ReadStream: () => closed(new fs.ReadStream(file)),
    createReadStream: () => closed(fs.createReadStream(file)),
    'readdirSync(recursive)': () => fs.readdirSync(s.data, { recursive: true }),
    accessSync: () => fs.accessSync(file),
  };
  for (const [api, use] of Object.entries(uses)) {
    let runs = 0;
    const compute = () => {
      runs += 1;
      fs.readFileSync(file);
      use();
      return { pass: true };
    };
    const r = recordReads(compute);
    assert.ok(r.unrecorded.includes(api), `${api}: ${r.unrecorded.join(',')}`);
    cachedVerdict({ cacheDir: s.cacheDir, key: api, code: 'c', compute });
    cachedVerdict({ cacheDir: s.cacheDir, key: api, code: 'c', compute });
    assert.equal(runs, 3, `${api} is never kept`);
  }
  await Promise.all(pending);
  assert.equal(fs.existsSync(s.cacheDir), false, 'nothing was stored');
  assert.equal(fs.promises.readFile, namedPromisesReadFile, 'fs/promises is put back');
  assert.equal(typeof fs.ReadStream, 'function', 'and the stream classes');
});

test('reading only through the recorded five is kept', (t) => {
  const s = setup(t);
  const r = recordReads(() => {
    fs.readFileSync(path.join(s.data, 'a.txt'));
    fs.readdirSync(s.data, { withFileTypes: true });
    fs.statSync(path.join(s.data, 'b.bin'));
    fs.lstatSync(path.join(s.data, 'b.bin'));
    return fs.existsSync(path.join(s.data, 'none'));
  });
  assert.deepEqual(r.unrecorded, []);
  assert.equal(r.deps.length, 5);
});

test('a compute that reads nothing keeps nothing', (t) => {
  const s = setup(t);
  let runs = 0;
  const compute = () => {
    runs += 1;
    return { pass: true };
  };
  cachedVerdict({ cacheDir: s.cacheDir, key: 'none', code: 'c', compute });
  cachedVerdict({ cacheDir: s.cacheDir, key: 'none', code: 'c', compute });
  assert.equal(runs, 2);
});

test('a broken entry misses and is replaced', (t) => {
  const s = setup(t);
  s.call();
  const [entry] = fs.readdirSync(s.cacheDir);
  fs.writeFileSync(path.join(s.cacheDir, entry), '{not json');
  assert.equal(s.call().cached, undefined);
  assert.equal(s.call().cached, true);
  assert.equal(s.runs(), 2);
});

test('reads through a named ESM import are recorded too, and encodings still decode', (t) => {
  const s = setup(t);
  const file = path.join(s.data, 'a.txt');
  const original = fs.readFileSync;
  const r = recordReads(() => namedReadFileSync(file, 'utf8') + fs.readFileSync(file, { encoding: 'utf8' }));
  assert.equal(r.value, 'alphaalpha');
  assert.deepEqual(
    r.deps.map((d) => d.slice(0, 2)),
    [['read', path.resolve(file)]],
  );
  assert.deepEqual(r.unrecorded, []);
  assert.equal(fs.readFileSync, original, 'fs is put back');
  assert.equal(namedReadFileSync, original, 'and so is the named export');
});

test('pruning keeps the named entries and deletes the rest', (t) => {
  const s = setup(t);
  s.call();
  s.call({ key: { k: 2 } });
  const keep = entryPath(s.cacheDir, { k: 1 }, 'code-1');
  fs.writeFileSync(path.join(s.cacheDir, 'x.json.123.tmp'), '');
  const removed = pruneEntries(s.cacheDir, [keep]);
  assert.equal(removed.length, 2, removed.join(','));
  assert.deepEqual(fs.readdirSync(s.cacheDir), [path.basename(keep)]);
  assert.equal(s.call().cached, true, 'the kept entry still hits');
  assert.deepEqual(pruneEntries(path.join(s.root, 'none'), []), [], 'no folder, nothing to do');
});

test('codeHash changes with a file and with nothing else', (t) => {
  const s = setup(t);
  const a = path.join(s.data, 'a.txt');
  const one = codeHash([a]);
  assert.equal(codeHash([a]), one);
  fs.writeFileSync(a, 'beta');
  assert.notEqual(codeHash([a]), one);
});
