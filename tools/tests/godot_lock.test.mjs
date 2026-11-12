// Tests for tools/lib/godot_lock.mjs (BRIEF 2, BRIEF 7.1): FIFO grants, multi-slot leases, the lock
// wait timeout, dead-ticket reaping and the CLI runner. Every test uses its own temp lock directory.
import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { acquire, capFile, CAP_FLOOR, defaultCap, machineCap, setCapFile, readTickets, pidAlive, LOCK_TIMEOUT_MESSAGE, WHOLE_MACHINE_LEASE } from '../lib/godot_lock.mjs';
import { TOOLS, IS_WIN, sleep, runProc, rmQuiet } from './helpers.mjs';

const LOCK_JS = path.join(TOOLS, 'lib', 'godot_lock.mjs');
const dirs = [];

function tmpLockDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-lock-test-'));
  dirs.push(dir);
  return dir;
}

after(() => {
  for (const d of dirs) rmQuiet(d);
});

const maxSeq = (dir) => readTickets(dir).tickets.reduce((m, t) => Math.max(m, t.seq), 0);

function restoreEnv(key, value) {
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

async function until(pred, timeoutMs = 5000, what = 'condition') {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    if (await pred()) return;
    await sleep(25);
  }
  throw new Error(`timed out waiting for ${what}`);
}

/** Starts acquire() and resolves once its ticket exists, so arrival order is deterministic. */
async function enqueue(dir, opts, record) {
  const before = maxSeq(dir);
  const entry = { at: null, handle: null, error: null };
  entry.promise = acquire({ dir, ...opts }).then(
    (h) => {
      entry.at = performance.now();
      entry.handle = h;
      if (record) record.push(entry);
      return h;
    },
    (err) => {
      entry.error = err;
    },
  );
  await until(() => maxSeq(dir) > before, 5000, 'the new ticket');
  return entry;
}

function cliEnv(dir, cap) {
  return { ...process.env, WATTLANDS_GODOT_LOCK_DIR: dir, WATTLANDS_GODOT_LOCK_CAP: String(cap) };
}

/** A child process that takes a lease from `dir` and holds it until killed. Resolves once it holds or waits. */
function lockChild(dir, { lease = 1, cap = 1, waitFor = 'HELD' } = {}) {
  const code = `import(${JSON.stringify(pathToFileURL(LOCK_JS).href)}).then(async (m) => {
    process.stdout.write('QUEUED\\n');
    await m.acquire({ dir: ${JSON.stringify(dir)}, lease: ${lease}, cap: ${cap} });
    process.stdout.write('HELD\\n');
    setInterval(() => {}, 1000);
  });`;
  const child = spawn(process.execPath, ['-e', code], { stdio: ['ignore', 'pipe', 'inherit'] });
  let out = '';
  child.stdout.on('data', (d) => (out += d));
  const ready = until(() => out.includes(waitFor), 10_000, `child ${waitFor}`);
  const exited = new Promise((resolve) => child.on('exit', resolve));
  return { child, ready, exited };
}

describe('godot lock: grants', () => {
  test('grants strictly first come, first served', async () => {
    const dir = tmpLockDir();
    const order = [];
    const a = await acquire({ dir, cap: 1 });
    const b = await enqueue(dir, { cap: 1 }, order);
    const c = await enqueue(dir, { cap: 1 }, order);
    const d = await enqueue(dir, { cap: 1 }, order);
    await sleep(300);
    assert.equal(order.length, 0, 'nothing is granted while the only slot is held');
    a.release();
    await b.promise;
    await sleep(300);
    assert.deepEqual(order, [b], 'only the oldest waiter gets the freed slot');
    b.handle.release();
    await c.promise;
    c.handle.release();
    await d.promise;
    d.handle.release();
    assert.deepEqual(order, [b, c, d]);
    assert.equal(readTickets(dir).tickets.length, 0, 'every ticket is gone after release');
  });

  // BRIEF 7.1: a multi-slot lease queued behind held slots is granted as soon as enough slots free,
  // while 1-slot requests keep arriving, and no later 1-slot request gets a slot before it.
  const cases = [
    { name: '4-slot lease, cap 4, behind 1 held slot', cap: 4, held: [1], big: 4 },
    { name: '3-slot lease, cap 4, behind 2 held slots', cap: 4, held: [1, 1], big: 3 },
    { name: '3-slot lease above cap 2, behind 1 held slot', cap: 2, held: [1], big: 3 },
  ];
  for (const k of cases) {
    test(`multi-slot lease holds back later 1-slot requests: ${k.name}`, async () => {
      const saved = process.env.WATTLANDS_GODOT_LOCK_CAP;
      process.env.WATTLANDS_GODOT_LOCK_CAP = String(k.cap); // the env override, as the brief asks
      const dir = tmpLockDir();
      try {
        assert.equal(machineCap(), k.cap);
        const holders = [];
        for (const lease of k.held) holders.push(await acquire({ dir, lease }));
        const big = await enqueue(dir, { lease: k.big });
        const smalls = [];
        let releasedAt = null;
        for (let i = 0; i < 6; i++) {
          smalls.push(await enqueue(dir, { lease: 1 }));
          await sleep(120);
          if (i === 2) {
            releasedAt = performance.now();
            holders.shift().release();
          }
        }
        await big.promise;
        assert.ok(big.at - releasedAt < 1000, `granted ${Math.round(big.at - releasedAt)} ms after the slot freed`);
        for (const s of smalls) {
          assert.ok(s.at === null || s.at >= big.at, 'no later 1-slot request was granted before the big lease');
        }
        const remaining = holders.reduce((sum, h) => sum + h.lease, 0);
        await sleep(600);
        assert.equal(smalls.filter((s) => s.at !== null).length, 0, 'the big lease leaves no room for 1-slot requests');
        big.handle.release();
        const free = k.cap - remaining;
        await until(() => smalls.filter((s) => s.at !== null).length >= free, 3000, 'small grants');
        await sleep(400);
        const granted = smalls.filter((s) => s.at !== null);
        assert.equal(granted.length, free, 'grants fill the cap exactly');
        assert.deepEqual(granted.map((s) => smalls.indexOf(s)), [...Array(free).keys()], '1-slot grants stay in arrival order');
        // Drain: release everything as it gets granted.
        for (const h of holders) h.release();
        while (smalls.some((s) => s.at === null)) {
          for (const s of smalls) if (s.handle) s.handle.release();
          await sleep(100);
        }
        for (const s of smalls) s.handle.release();
        assert.equal(readTickets(dir).tickets.length, 0);
      } finally {
        if (saved === undefined) delete process.env.WATTLANDS_GODOT_LOCK_CAP;
        else process.env.WATTLANDS_GODOT_LOCK_CAP = saved;
      }
    });
  }

  test('a lease larger than the cap is granted only while nothing is held', async () => {
    const dir = tmpLockDir();
    const solo = await acquire({ dir, cap: 2, lease: 5, lockTimeoutS: 2 });
    assert.equal(solo.lease, 5, 'granted at once on an idle machine');
    const one = await enqueue(dir, { cap: 2, lease: 1 });
    await sleep(400);
    assert.equal(one.at, null, 'a 1-slot request waits while the oversized lease holds');
    solo.release();
    await one.promise;
    const big = await enqueue(dir, { cap: 2, lease: 3 });
    await sleep(400);
    assert.equal(big.at, null, 'not granted while one slot is held');
    one.handle.release();
    await big.promise;
    big.handle.release();
  });

  test('machineCap honours WATTLANDS_GODOT_LOCK_CAP and otherwise follows the hardware', () => {
    // A fresh lock dir: the machine's real one can hold a cap file (set-cap), which would answer instead.
    const saved = process.env.WATTLANDS_GODOT_LOCK_CAP;
    const savedDir = process.env.WATTLANDS_GODOT_LOCK_DIR;
    process.env.WATTLANDS_GODOT_LOCK_DIR = tmpLockDir();
    try {
      process.env.WATTLANDS_GODOT_LOCK_CAP = '3';
      assert.equal(machineCap(), 3);
      process.env.WATTLANDS_GODOT_LOCK_CAP = 'lots';
      assert.throws(() => machineCap(), /positive integer/);
      delete process.env.WATTLANDS_GODOT_LOCK_CAP;
      // One reading of free RAM for every call compared: two os.freemem() reads differ on a busy machine.
      const freeBytes = os.freemem();
      const cap = machineCap(undefined, { freeBytes });
      assert.ok(Number.isInteger(cap) && cap >= CAP_FLOOR, `cap ${cap}`);
      assert.ok(cap <= Math.max(CAP_FLOOR, Math.floor(os.cpus().length * 0.75)), `cap ${cap} on ${os.cpus().length} CPUs`);
      assert.ok(machineCap(undefined, { heldSlots: 6, freeBytes }) >= cap, 'held slots never lower the cap');
    } finally {
      restoreEnv('WATTLANDS_GODOT_LOCK_CAP', saved);
      restoreEnv('WATTLANDS_GODOT_LOCK_DIR', savedDir);
    }
  });

  test('the default cap: 3/4 of the CPUs, bounded by free RAM, never below 2', () => {
    const GiB = 1024 ** 3;
    assert.equal(defaultCap({ cpus: 20, freeBytes: 34 * GiB }), 15, 'this machine: the CPUs bound it');
    assert.equal(defaultCap({ cpus: 20, freeBytes: 18 * GiB }), 10, 'RAM bounds it: 1 GiB a slot above an 8 GiB reserve');
    assert.equal(defaultCap({ cpus: 8, freeBytes: 16 * GiB }), 6);
    assert.equal(defaultCap({ cpus: 4, freeBytes: 64 * GiB }), 3);
    assert.equal(defaultCap({ cpus: 2, freeBytes: 64 * GiB }), CAP_FLOOR, 'the floor');
    assert.equal(defaultCap({ cpus: 64, freeBytes: 4 * GiB }), CAP_FLOOR, 'the floor, below the reserve');
    // The held slots' processes already ate into free RAM: their budget comes back, so a full cap holds.
    assert.equal(defaultCap({ cpus: 20, freeBytes: 15 * GiB, heldSlots: 12 }), 15);
    assert.equal(defaultCap({ cpus: 20, freeBytes: 15 * GiB }), 7);
    assert.equal(defaultCap({ cpus: 20, freeBytes: 15 * GiB, heldSlots: WHOLE_MACHINE_LEASE }), 7, 'a whole-machine lease adds no budget');
  });

  // With free RAM 1 GiB above the reserve, the computed cap is the floor while nothing is held. Two held
  // slots give their 2 GiB back (their processes ate it), so a third request fits beside them.
  test('acquire counts the held slots back into the computed cap', { skip: os.cpus().length < 4 && 'needs 4 CPUs for a cap of 3' }, async () => {
    const saved = process.env.WATTLANDS_GODOT_LOCK_CAP;
    delete process.env.WATTLANDS_GODOT_LOCK_CAP;
    const dir = tmpLockDir();
    const freeBytes = 9 * 1024 ** 3;
    try {
      assert.equal(defaultCap({ freeBytes }), CAP_FLOOR, 'nothing held: the floor');
      assert.equal(defaultCap({ freeBytes, heldSlots: 2 }), 3, 'two held: their budget back');
      const a = await acquire({ dir, freeBytes, lockTimeoutS: 2 });
      const b = await acquire({ dir, freeBytes, lockTimeoutS: 2 });
      // The same request at the bare cap of 2 waits out its timeout: the add-back is what grants it.
      await assert.rejects(acquire({ dir, cap: CAP_FLOOR, lockTimeoutS: 0.5 }), { code: 'ELOCKTIMEOUT' });
      const c = await acquire({ dir, freeBytes, lockTimeoutS: 3 });
      for (const h of [a, b, c]) h.release();
      assert.equal(readTickets(dir).tickets.length, 0);
    } finally {
      restoreEnv('WATTLANDS_GODOT_LOCK_CAP', saved);
    }
  });

  test('a whole-machine lease waits for every held slot, and holds back later grants', async () => {
    const dir = tmpLockDir();
    const one = await acquire({ dir, cap: 16, lease: 1, lockTimeoutS: 2 });
    const whole = await enqueue(dir, { cap: 16, lease: WHOLE_MACHINE_LEASE });
    await sleep(400);
    assert.equal(whole.at, null, 'not granted while one slot is held');
    one.release();
    await whole.promise;
    const later = await enqueue(dir, { cap: 16, lease: 1 });
    await sleep(400);
    assert.equal(later.at, null, 'nothing else runs beside it');
    whole.handle.release();
    await later.promise;
    later.handle.release();
  });
});

describe('godot lock: cap file', () => {
  /** Runs fn with no env cap set, restoring it after. */
  async function withoutEnvCap(fn) {
    const saved = process.env.WATTLANDS_GODOT_LOCK_CAP;
    delete process.env.WATTLANDS_GODOT_LOCK_CAP;
    try {
      return await fn();
    } finally {
      restoreEnv('WATTLANDS_GODOT_LOCK_CAP', saved);
    }
  }

  /** Runs fn collecting everything written to stderr. */
  function captureStderr(fn) {
    const lines = [];
    const real = process.stderr.write;
    process.stderr.write = (chunk) => {
      lines.push(String(chunk));
      return true;
    };
    try {
      fn();
    } finally {
      process.stderr.write = real;
    }
    return lines;
  }

  /** The environment of a shell with no cap variable, on the lock dir `dir`. */
  function shellEnv(dir) {
    const env = { ...process.env, WATTLANDS_GODOT_LOCK_DIR: dir };
    delete env.WATTLANDS_GODOT_LOCK_CAP;
    return env;
  }

  test('the file is respected, with or without a line ending', () =>
    withoutEnvCap(() => {
      const dir = tmpLockDir();
      assert.equal(capFile(dir), path.join(dir, 'cap'));
      for (const [text, want] of [['16', 16], ['16\n', 16], ['  7\r\n', 7]]) {
        fs.writeFileSync(capFile(dir), text);
        assert.equal(machineCap(dir), want, JSON.stringify(text));
      }
    }));

  test('the env variable beats the file, and a bad env value still throws', () =>
    withoutEnvCap(() => {
      const dir = tmpLockDir();
      fs.writeFileSync(capFile(dir), '16\n');
      process.env.WATTLANDS_GODOT_LOCK_CAP = '3';
      assert.equal(machineCap(dir), 3);
      process.env.WATTLANDS_GODOT_LOCK_CAP = 'lots';
      assert.throws(() => machineCap(dir), /WATTLANDS_GODOT_LOCK_CAP must be a positive integer/);
    }));

  test('a garbage file is ignored with one stderr note per content', () =>
    withoutEnvCap(() => {
      const dir = tmpLockDir();
      const freeBytes = os.freemem();
      const none = machineCap(tmpLockDir(), { freeBytes });
      for (const garbage of ['lots', '', '0', '-3', '2.5', '1e3', '4 8', '99999999999999999999']) {
        fs.writeFileSync(capFile(dir), garbage);
        const notes = captureStderr(() => {
          for (let i = 0; i < 5; i++) assert.equal(machineCap(dir, { freeBytes }), none, JSON.stringify(garbage));
        });
        assert.equal(notes.length, 1, `one note for ${JSON.stringify(garbage)}: ${notes}`);
        assert.match(notes[0], /ignoring cap file/);
      }
    }));

  test('a directory in place of the file is ignored too', () =>
    withoutEnvCap(() => {
      const dir = tmpLockDir();
      const freeBytes = os.freemem();
      const none = machineCap(tmpLockDir(), { freeBytes });
      fs.mkdirSync(capFile(dir));
      const notes = captureStderr(() => assert.equal(machineCap(dir, { freeBytes }), none));
      assert.equal(notes.length, 1);
    }));

  test('tickets ignore the file: it is no ticket and blocks no grant', () =>
    withoutEnvCap(async () => {
      const dir = tmpLockDir();
      setCapFile(2, dir);
      assert.deepEqual(readTickets(dir), { tickets: [], orphans: [] });
      const h = await acquire({ dir, lockTimeoutS: 2 });
      assert.deepEqual(readTickets(dir).tickets.map((t) => t.seq), [h.seq]);
      h.release();
      assert.equal(fs.readFileSync(capFile(dir), 'utf8'), '2\n', 'a run leaves the file alone');
    }));

  test('acquire reads the cap of its own dir, and a waiter sees a change at once', () =>
    withoutEnvCap(async () => {
      const dir = tmpLockDir();
      setCapFile(1, dir);
      const first = await acquire({ dir });
      const second = await enqueue(dir, {});
      await sleep(400);
      assert.equal(second.at, null, 'cap 1 from the file holds the second request back');
      setCapFile(2, dir);
      await second.promise;
      assert.ok(second.handle, 'granted after the file changed, without a new request');
      second.handle.release();
      first.release();
    }));

  test('an explicit cap beats the file', () =>
    withoutEnvCap(async () => {
      const dir = tmpLockDir();
      setCapFile(1, dir);
      const a = await acquire({ dir, cap: 2 });
      const b = await acquire({ dir, cap: 2, lockTimeoutS: 2 });
      b.release();
      a.release();
    }));

  test('CLI: set-cap writes the file, cap and status read it, another process obeys it', async () => {
    const dir = tmpLockDir();
    const env = shellEnv(dir);
    const set = await runProc(process.execPath, [LOCK_JS, 'set-cap', '1'], { env });
    assert.equal(set.code, 0, set.stderr);
    assert.match(set.stdout, /set to 1; cap 1/);
    assert.equal(fs.readFileSync(capFile(dir), 'utf8'), '1\n');
    assert.deepEqual(fs.readdirSync(dir), ['cap'], 'no temp file stays behind');
    const cap = await runProc(process.execPath, [LOCK_JS, 'cap'], { env });
    assert.equal(cap.stdout.trim(), '1');
    const status = await runProc(process.execPath, [LOCK_JS, 'status', '--json'], { env });
    assert.equal(JSON.parse(status.stdout).cap, 1);
    const holder = await acquire({ dir, cap: 1 });
    const args = [LOCK_JS, 'run', '--lock-timeout=1', '--', process.execPath, '-e', 'process.exit(0)'];
    const blocked = await runProc(process.execPath, args, { env });
    assert.equal(blocked.code, 75, 'a shell with no cap variable obeys the file');
    assert.equal((await runProc(process.execPath, [LOCK_JS, 'set-cap', '2'], { env })).code, 0);
    assert.equal((await runProc(process.execPath, args, { env })).code, 0, 'and sees the new value');
    holder.release();
  });

  test('CLI: set-cap 0 deletes the file, and is fine with no file', async () => {
    const dir = tmpLockDir();
    const env = shellEnv(dir);
    setCapFile(16, dir);
    const del = await runProc(process.execPath, [LOCK_JS, 'set-cap', '0'], { env });
    assert.equal(del.code, 0, del.stderr);
    assert.match(del.stdout, /deleted/);
    assert.equal(fs.existsSync(capFile(dir)), false);
    const freeBytes = os.freemem();
    await withoutEnvCap(() => assert.equal(machineCap(dir, { freeBytes }), defaultCap({ freeBytes }), 'back to the computed default'));
    const again = await runProc(process.execPath, [LOCK_JS, 'set-cap', '0'], { env });
    assert.equal(again.code, 0, again.stderr);
  });

  test('CLI: set-cap says when the env variable overrides it', async () => {
    const dir = tmpLockDir();
    const r = await runProc(process.execPath, [LOCK_JS, 'set-cap', '16'], { env: cliEnv(dir, 2) });
    assert.equal(r.code, 0, r.stderr);
    assert.match(r.stdout, /set to 16; cap 2/);
    assert.match(r.stderr, /overrides the cap file/);
  });

  test('CLI: set-cap refuses anything but one integer >= 0', async () => {
    const dir = tmpLockDir();
    const env = shellEnv(dir);
    for (const bad of [[], ['-1'], ['1.5'], ['lots'], ['1', '2'], ['99999999999999999999']]) {
      const r = await runProc(process.execPath, [LOCK_JS, 'set-cap', ...bad], { env });
      assert.equal(r.code, 2, `set-cap ${bad.join(' ')}`);
    }
    assert.equal(fs.existsSync(capFile(dir)), false);
  });
});

describe('godot lock: wait timeout', () => {
  test('library: rejects with "godot lock wait timeout" and withdraws its ticket', async () => {
    const dir = tmpLockDir();
    const holder = await acquire({ dir, cap: 1 });
    const t0 = Date.now();
    await assert.rejects(acquire({ dir, cap: 1, lockTimeoutS: 0.5 }), (err) => {
      assert.equal(err.code, 'ELOCKTIMEOUT');
      assert.equal(err.message, LOCK_TIMEOUT_MESSAGE);
      return true;
    });
    assert.ok(Date.now() - t0 < 3000);
    assert.deepEqual(readTickets(dir).tickets.map((t) => t.seq), [holder.seq], 'only the holder remains');
    holder.release();
  });

  test('CLI: prints "godot lock wait timeout", exits 75 and starts nothing', async () => {
    const dir = tmpLockDir();
    const holder = await acquire({ dir, cap: 1 });
    const marker = path.join(dir, 'started.txt');
    const r = await runProc(
      process.execPath,
      [LOCK_JS, 'run', '--lock-timeout=1', '--', process.execPath, '-e', `require('fs').writeFileSync(${JSON.stringify(marker)}, 'x')`],
      { env: cliEnv(dir, 1) },
    );
    assert.equal(r.code, 75, r.stderr);
    assert.match(r.stderr, /^godot lock wait timeout$/m);
    assert.equal(fs.existsSync(marker), false, 'the command never ran');
    assert.deepEqual(readTickets(dir).tickets.map((t) => t.seq), [holder.seq]);
    holder.release();
  });
});

describe('godot lock: dead tickets', () => {
  test('a killed holder\'s ticket is reaped', async () => {
    const dir = tmpLockDir();
    const c = lockChild(dir, { cap: 1 });
    await c.ready;
    c.child.kill('SIGKILL');
    await c.exited;
    assert.equal(readTickets(dir).tickets.length, 1, 'the dead holder left its ticket behind');
    const t0 = Date.now();
    const h = await acquire({ dir, cap: 1, lockTimeoutS: 5 });
    assert.ok(Date.now() - t0 < 2000, 'granted promptly after reaping');
    h.release();
  });

  test('a killed waiter\'s ticket no longer holds back later requests', async () => {
    const dir = tmpLockDir();
    const holder = await acquire({ dir, cap: 1 });
    const before = maxSeq(dir);
    const c = lockChild(dir, { cap: 1, waitFor: 'QUEUED' });
    await c.ready;
    await until(() => maxSeq(dir) > before, 5000, 'child ticket');
    const later = await enqueue(dir, { cap: 1 });
    c.child.kill('SIGKILL');
    await c.exited;
    holder.release();
    await later.promise;
    later.handle.release();
  });

  test('a live pid whose heartbeat stopped (a reused pid) is reaped', async () => {
    const dir = tmpLockDir();
    const ticket = path.join(dir, 't-000000000001.json');
    fs.writeFileSync(ticket, JSON.stringify({ seq: 1, pid: process.pid, lease: 1, label: 'fake' }));
    fs.writeFileSync(path.join(dir, 'h-000000000001'), '{}');
    fs.writeFileSync(path.join(dir, 'seq'), '1');
    const old = new Date(Date.now() - 180_000);
    fs.utimesSync(ticket, old, old);
    const h = await acquire({ dir, cap: 1, lockTimeoutS: 10, staleMs: 2000, staleConfirmMs: 500 });
    assert.ok(h.seq > 1);
    assert.equal(fs.existsSync(ticket), false);
    h.release();
  });

  test('a stale ticket mutex left by a dead process is broken', async () => {
    const dir = tmpLockDir();
    const dead = spawn(process.execPath, ['-e', '0']);
    await new Promise((resolve) => dead.on('exit', resolve));
    assert.equal(pidAlive(dead.pid), false);
    fs.writeFileSync(path.join(dir, 'seq.mutex'), JSON.stringify({ pid: dead.pid, t: 0 }));
    const t0 = Date.now();
    const h = await acquire({ dir, cap: 1, lockTimeoutS: 5 });
    assert.ok(Date.now() - t0 < 2000);
    h.release();
  });

  test('a live holder keeps its ticket fresh (heartbeat)', async () => {
    const dir = tmpLockDir();
    const h = await acquire({ dir, cap: 1 });
    const file = readTickets(dir).tickets[0].file;
    const old = new Date(Date.now() - 600_000);
    fs.utimesSync(file, old, old);
    await until(() => Date.now() - fs.statSync(file).mtimeMs < 60_000, 8000, 'heartbeat');
    h.release();
  });
});

describe('godot lock: CLI runner', () => {
  test('passes the exit code through and releases the lease', async () => {
    const dir = tmpLockDir();
    const r = await runProc(process.execPath, [LOCK_JS, 'run', '--', process.execPath, '-e', 'process.exit(7)'], { env: cliEnv(dir, 2) });
    assert.equal(r.code, 7, r.stderr);
    assert.equal(readTickets(dir).tickets.length, 0);
  });

  test('the run timeout kills the whole process tree and exits 124', async () => {
    const dir = tmpLockDir();
    const pidFile = path.join(dir, 'grandchild.pid');
    const code = `const { spawn } = require('child_process');
      const c = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
      require('fs').writeFileSync(${JSON.stringify(pidFile)}, String(c.pid));
      setInterval(() => {}, 1000);`;
    const t0 = Date.now();
    const r = await runProc(process.execPath, [LOCK_JS, 'run', '--timeout=2', '--', process.execPath, '-e', code], { env: cliEnv(dir, 2) });
    assert.equal(r.code, 124, r.stderr);
    assert.match(r.stderr, /godot run timeout/);
    assert.ok(Date.now() - t0 < 15_000);
    const grandchild = Number(fs.readFileSync(pidFile, 'utf8'));
    await until(() => !pidAlive(grandchild), 5000, 'the grandchild to die');
    assert.equal(readTickets(dir).tickets.length, 0);
  });

  test('usage errors exit 2; a missing program exits 127', async () => {
    const dir = tmpLockDir();
    const bad = await runProc(process.execPath, [LOCK_JS, 'run', '--lease=0', '--', 'x'], { env: cliEnv(dir, 2) });
    assert.equal(bad.code, 2);
    const missing = await runProc(process.execPath, [LOCK_JS, 'run', '--', 'definitely-not-a-program-wattlands'], { env: cliEnv(dir, 2) });
    assert.equal(missing.code, 127);
    assert.equal(readTickets(dir).tickets.length, 0);
  });

  test('WATTLANDS_GODOT_LEASE_TOKEN runs inside a held lease without queueing', async () => {
    const dir = tmpLockDir();
    const holder = await acquire({ dir, cap: 1 });
    const args = [LOCK_JS, 'run', '--lock-timeout=1', '--', process.execPath, '-e', 'process.exit(0)'];
    const inside = await runProc(process.execPath, args, { env: { ...cliEnv(dir, 1), WATTLANDS_GODOT_LEASE_TOKEN: holder.token } });
    assert.equal(inside.code, 0, inside.stderr);
    const outside = await runProc(process.execPath, args, { env: cliEnv(dir, 1) });
    assert.equal(outside.code, 75);
    holder.release();
    const stale = await runProc(process.execPath, args, { env: { ...cliEnv(dir, 1), WATTLANDS_GODOT_LEASE_TOKEN: holder.token } });
    assert.equal(stale.code, 0, 'a released token falls back to normal queueing');
    assert.match(stale.stderr, /ignoring WATTLANDS_GODOT_LEASE_TOKEN/);
  });

  test('SIGTERM while waiting withdraws the ticket (POSIX)', { skip: IS_WIN && 'signals cannot be sent to a process on Windows' }, async () => {
    const dir = tmpLockDir();
    const holder = await acquire({ dir, cap: 1 });
    const child = spawn(process.execPath, [LOCK_JS, 'run', '--', process.execPath, '-e', '0'], { env: cliEnv(dir, 1), stdio: 'ignore' });
    await until(() => readTickets(dir).tickets.length === 2, 5000, 'the waiting ticket');
    child.kill('SIGTERM');
    const code = await new Promise((resolve) => child.on('exit', (c) => resolve(c)));
    assert.equal(code, 143);
    assert.equal(readTickets(dir).tickets.length, 1);
    holder.release();
  });
});
