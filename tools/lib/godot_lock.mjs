#!/usr/bin/env node
// tools/lib/godot_lock.mjs: the machine-wide Godot slot lock (BRIEF 2). Zero dependencies, Node 22.12+.
//
// Library:
//   import { acquire, machineCap } from './godot_lock.mjs';
//   const lease = await acquire({ lease: 3 });   // waits first come, first served
//   try { ...start up to 3 Godot processes... } finally { lease.release(); }
//
// CLI (used by tools/godot.sh and tools/godot.ps1):
//   node tools/lib/godot_lock.mjs run [--lease=<n>] [--lock-timeout=<s>] [--timeout=<s>] [--label=<text>] -- <exe> <args...>
//   node tools/lib/godot_lock.mjs status [--json]
//   node tools/lib/godot_lock.mjs cap
//
// Lock directory: $WATTLANDS_GODOT_LOCK_DIR, else os.tmpdir()/wattlands-godot.
// Cap: $WATTLANDS_GODOT_LOCK_CAP, else 4 slots with >= 8 CPUs and >= 16 GiB free RAM, else 2.
//
// Files in the lock directory:
//   seq             the last ticket number handed out (written only under seq.mutex)
//   seq.mutex       short exclusive-create mutex around ticket numbering (stale ones are broken)
//   t-<seq>.json    one ticket per request: {seq, pid, lease, created, label}; its mtime is a heartbeat
//   h-<seq>         exists while ticket <seq> holds its slots (state "held"; no h-file means "waiting")
//
// Grant rule (strict FIFO): a ticket is granted only when no lower-numbered ticket is waiting and
// either held + lease <= cap, or lease > cap and nothing is held. A lease is granted whole.
// A ticket is dead when its pid is gone (reaped at once), or when its heartbeat has been stale for
// over STALE_MS while this waiter kept polling (guards against a reused pid).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Worker } from 'node:worker_threads';

export const DEFAULT_LOCK_TIMEOUT_S = 45 * 60;
export const DEFAULT_RUN_TIMEOUT_S = 1200;
export const LOCK_TIMEOUT_EXIT = 75;
export const RUN_TIMEOUT_EXIT = 124;
export const LOCK_TIMEOUT_MESSAGE = 'godot lock wait timeout';
export const RUN_TIMEOUT_MESSAGE = 'godot run timeout';
export const LEASE_TOKEN_ENV = 'WATTLANDS_GODOT_LEASE_TOKEN';

const POLL_MS = 200;
const HEARTBEAT_MS = 5000;
const STALE_MS = 60_000;
const POLL_GAP_RESET_MS = 5000;
const GARBAGE_MS = 30_000;
const MUTEX_STALE_MS = 10_000;
const MUTEX_WAIT_MS = 30_000;
const SEQ_WIDTH = 12;
const GIB = 1024 ** 3;
const CPU_COUNT = os.cpus().length;

const TICKET_RE = /^t-(\d+)\.json$/;
const HELD_RE = /^h-(\d+)$/;

// ---------------------------------------------------------------- configuration

export function lockDir() {
  const env = process.env.WATTLANDS_GODOT_LOCK_DIR;
  return env ? path.resolve(env) : path.join(os.tmpdir(), 'wattlands-godot');
}

/** The slot cap: WATTLANDS_GODOT_LOCK_CAP if set, else 4 with >= 8 CPUs and >= 16 GiB free RAM, else 2. */
export function machineCap() {
  const env = process.env.WATTLANDS_GODOT_LOCK_CAP;
  if (env !== undefined && env !== '') {
    const n = Number(env);
    if (Number.isInteger(n) && n >= 1) return n;
    throw new Error(`WATTLANDS_GODOT_LOCK_CAP must be a positive integer, got "${env}"`);
  }
  return CPU_COUNT >= 8 && os.freemem() >= 16 * GIB ? 4 : 2;
}

// ---------------------------------------------------------------- small helpers

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const pad = (seq) => String(seq).padStart(SEQ_WIDTH, '0');
const ticketName = (seq) => `t-${pad(seq)}.json`;
const heldName = (seq) => `h-${pad(seq)}`;
const isLease = (n) => Number.isInteger(n) && n >= 1;

export function pidAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM';
  }
}

function unlinkQuiet(file) {
  try {
    fs.unlinkSync(file);
    return true;
  } catch {
    return false;
  }
}

function readdirQuiet(dir) {
  try {
    return fs.readdirSync(dir);
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

// ---------------------------------------------------------------- ticket numbering

async function withMutex(dir, fn) {
  const mutex = path.join(dir, 'seq.mutex');
  const deadline = Date.now() + MUTEX_WAIT_MS;
  for (;;) {
    let fd;
    try {
      fd = fs.openSync(mutex, 'wx');
    } catch (err) {
      if (err.code !== 'EEXIST' && err.code !== 'EPERM') throw err;
      breakStaleMutex(mutex);
      if (Date.now() > deadline) throw new Error(`could not take ${mutex} within ${MUTEX_WAIT_MS / 1000} s`);
      await sleep(5 + Math.random() * 20);
      continue;
    }
    try {
      fs.writeSync(fd, JSON.stringify({ pid: process.pid, t: Date.now() }));
    } finally {
      fs.closeSync(fd);
    }
    try {
      return fn();
    } finally {
      unlinkQuiet(mutex);
    }
  }
}

function breakStaleMutex(mutex) {
  let st;
  let holder = null;
  try {
    st = fs.statSync(mutex);
    holder = JSON.parse(fs.readFileSync(mutex, 'utf8'));
  } catch {
    // Missing, or created but not yet written: judge by age alone.
  }
  if (!st) return;
  const age = Date.now() - st.mtimeMs;
  const dead = holder && Number.isInteger(holder.pid) && !pidAlive(holder.pid);
  if (!dead && age < MUTEX_STALE_MS) return;
  // Rename first so two breakers never both delete a fresh mutex by name.
  const aside = `${mutex}.stale-${process.pid}-${Math.random().toString(36).slice(2)}`;
  try {
    fs.renameSync(mutex, aside);
    unlinkQuiet(aside);
  } catch {
    // Someone else broke it first.
  }
}

function allocateTicket(dir, info) {
  // Runs under the mutex. The ticket file is created exclusively, so a duplicate number (only possible
  // if a stale-mutex break raced) fails here and the caller retries with the next number.
  const seqFile = path.join(dir, 'seq');
  let n = 0;
  try {
    n = Number.parseInt(fs.readFileSync(seqFile, 'utf8').trim(), 10);
  } catch {
    n = 0;
  }
  if (!Number.isSafeInteger(n) || n < 0) n = 0;
  for (const name of readdirQuiet(dir)) {
    const m = TICKET_RE.exec(name) || HELD_RE.exec(name);
    if (m) n = Math.max(n, Number(m[1]));
  }
  const seq = n + 1;
  fs.writeFileSync(seqFile, String(seq));
  const file = path.join(dir, ticketName(seq));
  const fd = fs.openSync(file, 'wx');
  try {
    fs.writeSync(fd, JSON.stringify({ ...info, seq }));
  } finally {
    fs.closeSync(fd);
  }
  return { seq, file };
}

async function newTicket(dir, info) {
  for (let attempt = 0; attempt < 50; attempt++) {
    try {
      return await withMutex(dir, () => allocateTicket(dir, info));
    } catch (err) {
      if (err.code !== 'EEXIST') throw err;
    }
  }
  throw new Error('could not allocate a godot lock ticket');
}

// ---------------------------------------------------------------- snapshots

/** Reads every ticket in the lock directory, sorted by number. */
export function readTickets(dir = lockDir()) {
  const names = readdirQuiet(dir);
  const held = new Map();
  const files = new Map();
  for (const name of names) {
    let m = HELD_RE.exec(name);
    if (m) {
      held.set(Number(m[1]), name);
      continue;
    }
    m = TICKET_RE.exec(name);
    if (m) files.set(Number(m[1]), name);
  }
  const tickets = [];
  for (const [seq, name] of files) {
    const file = path.join(dir, name);
    let mtimeMs = null;
    let info = null;
    try {
      mtimeMs = fs.statSync(file).mtimeMs;
      info = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (err) {
      if (err.code === 'ENOENT') continue; // released between readdir and read
      info = null; // being written, or unreadable for a moment: treated as waiting
    }
    tickets.push({
      seq,
      file,
      heldFile: held.has(seq) ? path.join(dir, held.get(seq)) : null,
      held: held.has(seq),
      pid: info && Number.isInteger(info.pid) ? info.pid : null,
      lease: info && isLease(info.lease) ? info.lease : null,
      label: info && typeof info.label === 'string' ? info.label : '',
      created: info && info.created ? info.created : null,
      mtimeMs,
      parsed: info !== null,
    });
  }
  tickets.sort((a, b) => a.seq - b.seq);
  const orphans = [...held.keys()].filter((seq) => !files.has(seq)).map((seq) => path.join(dir, held.get(seq)));
  return { tickets, orphans };
}

function reap(ticket, why, log) {
  if (ticket.heldFile) unlinkQuiet(ticket.heldFile);
  else unlinkQuiet(path.join(path.dirname(ticket.file), heldName(ticket.seq)));
  if (unlinkQuiet(ticket.file)) {
    log(`godot_lock: reaped ticket ${ticket.seq} (pid ${ticket.pid ?? '?'}, ${why})`);
  }
}

// ---------------------------------------------------------------- heartbeat

const HEARTBEAT_SRC = `
const { workerData, parentPort } = require('node:worker_threads');
const fs = require('node:fs');
const beat = () => { const now = new Date(); try { fs.utimesSync(workerData.file, now, now); } catch {} };
const timer = setInterval(beat, workerData.ms);
parentPort.on('message', () => { clearInterval(timer); parentPort.close(); });
`;

function startHeartbeat(file) {
  // A worker thread keeps beating even while the owner's main thread is busy in a sync call.
  try {
    const worker = new Worker(HEARTBEAT_SRC, { eval: true, workerData: { file, ms: HEARTBEAT_MS } });
    worker.unref();
    worker.on('error', () => {});
    return () => {
      try {
        worker.postMessage('stop');
      } catch {
        // already gone
      }
      worker.terminate().catch(() => {});
    };
  } catch {
    const timer = setInterval(() => {
      const now = new Date();
      try {
        fs.utimesSync(file, now, now);
      } catch {
        // ticket gone
      }
    }, HEARTBEAT_MS);
    timer.unref();
    return () => clearInterval(timer);
  }
}

// ---------------------------------------------------------------- acquire / release

const active = new Set();
let exitHookInstalled = false;

function installExitHook() {
  if (exitHookInstalled) return;
  exitHookInstalled = true;
  process.on('exit', () => {
    for (const entry of active) entry.cleanup();
  });
}

function lockTimeoutError() {
  const err = new Error(LOCK_TIMEOUT_MESSAGE);
  err.code = 'ELOCKTIMEOUT';
  return err;
}

/**
 * Waits for `lease` Godot slots and returns a handle: {seq, lease, dir, token, release()}.
 * Rejects with code ELOCKTIMEOUT ("godot lock wait timeout") after lockTimeoutS seconds; the
 * ticket is withdrawn then, so nothing was started under it.
 * @param {object} [opts]
 * @param {number} [opts.lease=1] slots to take at once
 * @param {number} [opts.lockTimeoutS=2700] how long to wait for the grant
 * @param {string} [opts.dir] lock directory (default lockDir())
 * @param {number} [opts.cap] slot cap (default machineCap(), re-read on every poll)
 * @param {string} [opts.label] shown by `status`
 * @param {(line: string) => void} [opts.log] progress lines (default: silent)
 * @param {number} [opts.pollMs=200]
 * @param {number} [opts.staleMs=60000] a live pid's ticket without a heartbeat for this long is stale
 * @param {number} [opts.staleConfirmMs=10000] ...and is reaped after looking stale for this long (test knobs)
 */
export async function acquire(opts = {}) {
  const lease = opts.lease ?? 1;
  if (!isLease(lease)) throw new TypeError(`lease must be a positive integer, got ${lease}`);
  const lockTimeoutS = opts.lockTimeoutS ?? DEFAULT_LOCK_TIMEOUT_S;
  if (!(typeof lockTimeoutS === 'number' && lockTimeoutS >= 0)) {
    throw new TypeError(`lockTimeoutS must be a number >= 0, got ${lockTimeoutS}`);
  }
  if (opts.cap !== undefined && !isLease(opts.cap)) throw new TypeError(`cap must be a positive integer, got ${opts.cap}`);
  const dir = path.resolve(opts.dir ?? lockDir());
  const log = opts.log ?? (() => {});
  const pollMs = opts.pollMs ?? POLL_MS;
  const staleMs = opts.staleMs ?? STALE_MS;
  const staleConfirmMs = opts.staleConfirmMs ?? 2 * HEARTBEAT_MS;
  const capOf = () => opts.cap ?? machineCap();
  capOf(); // validate the env override before taking a ticket
  ensureDir(dir);
  installExitHook();

  const info = {
    pid: process.pid,
    lease,
    created: new Date().toISOString(),
    label: String(opts.label ?? process.argv.slice(1).join(' ')).slice(0, 300),
  };

  const entry = { seq: 0, file: '', heldFile: '', stopBeat: () => {}, released: false, cleanup: () => {} };
  entry.cleanup = () => {
    if (entry.released) return;
    entry.released = true;
    entry.stopBeat();
    if (entry.heldFile) unlinkQuiet(entry.heldFile);
    if (entry.file) unlinkQuiet(entry.file);
    active.delete(entry);
  };
  active.add(entry);

  const takeTicket = async () => {
    entry.stopBeat();
    const t = await newTicket(dir, info);
    entry.seq = t.seq;
    entry.file = t.file;
    entry.heldFile = path.join(dir, heldName(t.seq));
    entry.stopBeat = startHeartbeat(t.file);
  };

  const started = Date.now();
  const deadline = started + lockTimeoutS * 1000;
  const suspects = new Map(); // seq -> first poll time its heartbeat looked stale
  let lastPoll = 0;
  let nextNote = started + 2000;

  try {
    await takeTicket();
    for (;;) {
      const now = Date.now();
      if (lastPoll && now - lastPoll > POLL_GAP_RESET_MS) suspects.clear(); // we were asleep or stalled
      lastPoll = now;

      const { tickets, orphans } = readTickets(dir);
      for (const orphan of orphans) {
        try {
          if (now - fs.statSync(orphan).mtimeMs > GARBAGE_MS) unlinkQuiet(orphan);
        } catch {
          // gone
        }
      }

      let mine = null;
      const live = [];
      for (const t of tickets) {
        if (t.seq === entry.seq) {
          mine = t;
          continue;
        }
        if (t.pid !== null && !pidAlive(t.pid)) {
          reap(t, 'process gone', log);
          continue;
        }
        if (!t.parsed && t.mtimeMs !== null && now - t.mtimeMs > GARBAGE_MS) {
          reap(t, 'unreadable', log);
          continue;
        }
        if (t.mtimeMs !== null && now - t.mtimeMs > staleMs) {
          const first = suspects.get(t.seq) ?? now;
          suspects.set(t.seq, first);
          if (now - first >= staleConfirmMs) {
            reap(t, `no heartbeat for ${Math.round((now - t.mtimeMs) / 1000)} s`, log);
            continue;
          }
        } else {
          suspects.delete(t.seq);
        }
        live.push(t);
      }

      if (!mine) {
        // Our ticket vanished (wrongly reaped): queue again at the back.
        log(`godot_lock: ticket ${entry.seq} disappeared, queueing again`);
        await takeTicket();
        continue;
      }

      const cap = capOf();
      let held = 0;
      let ahead = 0;
      for (const t of live) {
        if (t.held) held += t.lease ?? 1;
        else if (t.seq < entry.seq) ahead += 1;
      }
      const fits = lease <= cap ? held + lease <= cap : held === 0;
      if (ahead === 0 && fits) {
        try {
          const fd = fs.openSync(entry.heldFile, 'wx');
          try {
            fs.writeSync(fd, JSON.stringify({ seq: entry.seq, pid: process.pid, lease, granted: new Date().toISOString() }));
          } finally {
            fs.closeSync(fd);
          }
        } catch (err) {
          if (err.code !== 'EEXIST') throw err;
        }
        if (fs.existsSync(entry.file)) break; // granted
        // Reaped between our check and the grant: give the marker back and queue again.
        unlinkQuiet(entry.heldFile);
        log(`godot_lock: ticket ${entry.seq} was removed during its grant, queueing again`);
        await takeTicket();
        continue;
      }

      if (Date.now() >= deadline) throw lockTimeoutError();
      if (Date.now() >= nextNote) {
        const why = ahead > 0 ? `${ahead} earlier request(s) waiting` : `${held} of ${cap} slot(s) held`;
        log(`godot_lock: waiting for ${lease} slot(s): ${why} (ticket ${entry.seq}, waited ${Math.round((Date.now() - started) / 1000)} s)`);
        nextNote = Date.now() + 60_000;
      }
      await sleep(Math.min(pollMs, Math.max(0, deadline - Date.now())) || 1);
    }
  } catch (err) {
    entry.cleanup();
    throw err;
  }

  return {
    seq: entry.seq,
    lease,
    dir,
    waitedMs: Date.now() - started,
    /** Pass as WATTLANDS_GODOT_LEASE_TOKEN so tools/godot.sh runs inside this lease without queueing. */
    token: `${entry.seq}:${dir}`,
    release: () => entry.cleanup(),
  };
}

/** True when `token` (from a handle) names a live, held ticket. */
export function leaseTokenValid(token) {
  if (typeof token !== 'string') return false;
  const i = token.indexOf(':');
  if (i <= 0) return false;
  const seq = Number(token.slice(0, i));
  const dir = token.slice(i + 1);
  if (!Number.isSafeInteger(seq) || seq <= 0 || !dir) return false;
  try {
    const info = JSON.parse(fs.readFileSync(path.join(dir, ticketName(seq)), 'utf8'));
    return fs.existsSync(path.join(dir, heldName(seq))) && pidAlive(info.pid);
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------- process tree

export function killTree(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return;
  if (process.platform === 'win32') {
    const sys = process.env.SystemRoot || process.env.windir || 'C:\\Windows';
    const taskkill = path.join(sys, 'System32', 'taskkill.exe');
    spawnSync(fs.existsSync(taskkill) ? taskkill : 'taskkill', ['/T', '/F', '/PID', String(pid)], {
      stdio: 'ignore',
      windowsHide: true,
    });
  } else {
    try {
      process.kill(-pid, 'SIGKILL');
    } catch {
      try {
        process.kill(pid, 'SIGKILL');
      } catch {
        // already gone
      }
    }
  }
}

// ---------------------------------------------------------------- CLI

const USAGE = `usage:
  node tools/lib/godot_lock.mjs run [--lease=<n>] [--lock-timeout=<s>] [--timeout=<s>] [--label=<text>] -- <exe> <args...>
  node tools/lib/godot_lock.mjs status [--json]
  node tools/lib/godot_lock.mjs cap`;

function usage(msg) {
  if (msg) process.stderr.write(`godot_lock: ${msg}\n`);
  process.stderr.write(`${USAGE}\n`);
  process.exit(2);
}

function parseNumber(flag, value, { integer = false, min = 0 } = {}) {
  const n = Number(value);
  if (value === '' || !Number.isFinite(n) || n < min || (integer && !Number.isInteger(n))) {
    usage(`${flag} needs ${integer ? 'an integer' : 'a number'} >= ${min}, got "${value}"`);
  }
  return n;
}

function parseRunArgs(argv) {
  const opts = { lease: 1, lockTimeoutS: DEFAULT_LOCK_TIMEOUT_S, timeoutS: DEFAULT_RUN_TIMEOUT_S, label: null };
  let i = 0;
  for (; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--') {
      i += 1;
      break;
    }
    const eq = a.indexOf('=');
    const key = eq >= 0 ? a.slice(0, eq) : a;
    const val = eq >= 0 ? a.slice(eq + 1) : null;
    if (val === null) usage(`unknown or incomplete option "${a}" (options use --name=value and end with --)`);
    if (key === '--lease') opts.lease = parseNumber(key, val, { integer: true, min: 1 });
    else if (key === '--lock-timeout') opts.lockTimeoutS = parseNumber(key, val);
    else if (key === '--timeout') opts.timeoutS = parseNumber(key, val);
    else if (key === '--label') opts.label = val;
    else usage(`unknown option "${a}"`);
  }
  const cmd = argv.slice(i);
  if (cmd.length === 0) usage('missing "-- <exe> <args...>"');
  if (opts.timeoutS <= 0) usage('--timeout must be > 0');
  return { opts, cmd };
}

function signalExitCode(signal) {
  const n = os.constants.signals[signal];
  return n ? 128 + n : 1;
}

async function cmdRun(argv) {
  const { opts, cmd } = parseRunArgs(argv);
  const stderr = (line) => process.stderr.write(`${line}\n`);
  let child = null;
  let handle = null;
  let finished = false;

  const finish = (code) => {
    if (finished) return;
    finished = true;
    if (handle) handle.release();
    process.exit(code);
  };

  const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'];
  if (process.platform === 'win32') signals.push('SIGBREAK');
  for (const sig of signals) {
    process.on(sig, () => {
      if (child && child.exitCode === null) killTree(child.pid);
      finish(signalExitCode(sig)); // the exit hook withdraws a waiting ticket
    });
  }

  const token = process.env[LEASE_TOKEN_ENV];
  if (token && leaseTokenValid(token)) {
    handle = null; // run inside the caller's lease
  } else {
    if (token) stderr(`godot_lock: ignoring ${LEASE_TOKEN_ENV} (no live held lease), queueing normally`);
    try {
      handle = await acquire({
        lease: opts.lease,
        lockTimeoutS: opts.lockTimeoutS,
        label: opts.label ?? `${path.basename(cmd[0])} ${cmd.slice(1).join(' ')}`,
        log: stderr,
      });
    } catch (err) {
      if (err.code === 'ELOCKTIMEOUT') {
        stderr(LOCK_TIMEOUT_MESSAGE);
        finish(LOCK_TIMEOUT_EXIT);
        return;
      }
      stderr(`godot_lock: ${err.message}`);
      finish(1);
      return;
    }
  }

  let timedOut = false;
  // On Windows, windowsHide also hides the child's first GUI window. Godot's _console.exe starts the
  // real (windowed) exe itself, so hiding is safe for it and for headless runs; a windowed run of a
  // GUI build started directly must stay visible (screenshots, windowed perf runs).
  const hide = cmd.includes('--headless') || /_console(\.exe)?$/i.test(path.basename(cmd[0]));
  try {
    child = spawn(cmd[0], cmd.slice(1), {
      stdio: ['ignore', 'inherit', 'inherit'],
      windowsHide: hide,
      detached: process.platform !== 'win32', // own process group, so the timeout can kill the tree
    });
  } catch (err) {
    stderr(`godot_lock: cannot start ${cmd[0]}: ${err.message}`);
    finish(127);
    return;
  }
  child.on('error', (err) => {
    stderr(`godot_lock: cannot start ${cmd[0]}: ${err.code || err.message}`);
    finish(err.code === 'ENOENT' ? 127 : 126);
  });
  const timer = setTimeout(() => {
    timedOut = true;
    killTree(child.pid);
    setTimeout(() => {
      stderr(RUN_TIMEOUT_MESSAGE);
      finish(RUN_TIMEOUT_EXIT);
    }, 10_000).unref();
  }, opts.timeoutS * 1000);
  child.on('exit', (code, signal) => {
    clearTimeout(timer);
    if (timedOut) {
      stderr(RUN_TIMEOUT_MESSAGE);
      finish(RUN_TIMEOUT_EXIT);
      return;
    }
    finish(code ?? signalExitCode(signal));
  });
}

function cmdStatus(argv) {
  const dir = lockDir();
  const { tickets } = readTickets(dir);
  const now = Date.now();
  const rows = tickets.map((t) => ({
    seq: t.seq,
    state: t.held ? 'held' : 'waiting',
    lease: t.lease,
    pid: t.pid,
    alive: t.pid !== null && pidAlive(t.pid),
    heartbeat_age_s: t.mtimeMs === null ? null : Math.round((now - t.mtimeMs) / 1000),
    created: t.created,
    label: t.label,
  }));
  const cap = machineCap();
  if (argv.includes('--json')) {
    process.stdout.write(`${JSON.stringify({ dir, cap, tickets: rows }, null, 2)}\n`);
    return;
  }
  const held = rows.filter((r) => r.state === 'held').reduce((s, r) => s + (r.lease ?? 1), 0);
  process.stdout.write(`lock dir ${dir}\ncap ${cap}, held ${held}, tickets ${rows.length}\n`);
  for (const r of rows) {
    process.stdout.write(
      `  #${r.seq} ${r.state.padEnd(7)} lease ${r.lease ?? '?'} pid ${r.pid ?? '?'}${r.alive ? '' : ' (dead)'} beat ${r.heartbeat_age_s ?? '?'} s ago  ${r.label}\n`,
    );
  }
}

function isMain() {
  if (!process.argv[1]) return false;
  const norm = (p) => {
    let r = path.resolve(p);
    try {
      r = fs.realpathSync(r);
    } catch {
      // keep resolved path
    }
    return process.platform === 'win32' ? r.toLowerCase() : r;
  };
  return norm(process.argv[1]) === norm(fileURLToPath(import.meta.url));
}

if (isMain()) {
  const [command, ...rest] = process.argv.slice(2);
  if (command === 'run') {
    cmdRun(rest).catch((err) => {
      process.stderr.write(`godot_lock: ${err.stack || err}\n`);
      process.exit(1);
    });
  } else if (command === 'status') {
    cmdStatus(rest);
  } else if (command === 'cap') {
    process.stdout.write(`${machineCap()}\n`);
  } else {
    usage(command ? `unknown command "${command}"` : '');
  }
}
