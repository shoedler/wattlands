// tools/e2e/lib/proc.mjs: a child process with line capture, waits with timeouts and a tree kill.
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { spawn } from 'node:child_process';
import { killTree } from '../../lib/godot_lock.mjs';
import { IS_WIN } from './util.mjs';

/** Every Proc the harness started and has not seen exit, for the emergency cleanup. */
export const LIVE = new Set();

export function killAll() {
  for (const p of LIVE) p.kill();
}

export class Proc {
  /**
   * @param {string} name label for logs ("host", "relay", ...)
   * @param {string} cmd program
   * @param {string[]} args
   * @param {object} opts {cwd, env, logFile, echo: (line) => void}
   */
  constructor(name, cmd, args, opts = {}) {
    this.name = name;
    this.cmd = cmd;
    this.args = args;
    this.lines = [];
    this.exitCode = null;
    this.signal = null;
    this.closed = false;
    this.killed = false;
    this.spawnError = null;
    this.started = Date.now();
    this.ended = null;
    this._waiters = [];
    this._echo = opts.echo ?? null;
    this._log = null;
    if (opts.logFile) {
      fs.mkdirSync(path.dirname(opts.logFile), { recursive: true });
      this._log = fs.createWriteStream(opts.logFile, { flags: 'a' });
    }
    let resolveClose;
    this._closed = new Promise((resolve) => {
      resolveClose = resolve;
    });
    try {
      this.child = spawn(cmd, args, {
        cwd: opts.cwd,
        env: opts.env,
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
        detached: !IS_WIN, // own process group, so kill() takes the whole tree
      });
    } catch (err) {
      this.child = null;
      this._fail(err, resolveClose);
      return;
    }
    LIVE.add(this);
    this.pid = this.child.pid;
    for (const [stream, which] of [
      [this.child.stdout, 'out'],
      [this.child.stderr, 'err'],
    ]) {
      const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
      rl.on('line', (line) => this._line(line.replace(/\r$/, ''), which));
    }
    this.child.on('error', (err) => this._fail(err, resolveClose));
    this.child.on('close', (code, signal) => {
      this.exitCode = code;
      this.signal = signal;
      this._finish(resolveClose);
    });
  }

  _fail(err, resolveClose) {
    this.spawnError = err;
    this.exitCode = err.code === 'ENOENT' ? 127 : 126;
    this._line(`[e2e] cannot start ${this.cmd}: ${err.code || err.message}`, 'err');
    this._finish(resolveClose);
  }

  _finish(resolveClose) {
    if (this.closed) return;
    this.closed = true;
    this.ended = Date.now();
    LIVE.delete(this);
    if (this._log) this._log.end();
    for (const w of this._waiters.splice(0)) {
      clearTimeout(w.timer);
      w.reject(new Error(`${this.name} exited (code ${this.exitCode ?? this.signal}) before printing ${w.re}`));
    }
    resolveClose();
  }

  _line(line, stream) {
    const entry = { t: (Date.now() - this.started) / 1000, at: Date.now(), stream, line };
    this.lines.push(entry);
    if (this._log) this._log.write(`${line}\n`);
    if (this._echo) this._echo(line);
    for (const w of [...this._waiters]) {
      const m = w.re.exec(line);
      if (m) {
        this._waiters.splice(this._waiters.indexOf(w), 1);
        clearTimeout(w.timer);
        w.resolve({ match: m, entry });
      }
    }
  }

  /** Resolves with {match, entry} for the first line (already seen or new) matching re. */
  waitFor(re, timeoutMs) {
    for (const entry of this.lines) {
      const m = re.exec(entry.line);
      if (m) return Promise.resolve({ match: m, entry });
    }
    if (this.closed) {
      return Promise.reject(new Error(`${this.name} exited (code ${this.exitCode ?? this.signal}) before printing ${re}`));
    }
    return new Promise((resolve, reject) => {
      const w = { re, resolve, reject, timer: null };
      w.timer = setTimeout(() => {
        this._waiters.splice(this._waiters.indexOf(w), 1);
        reject(new Error(`${this.name} printed no line matching ${re} within ${Math.round(timeoutMs / 1000)} s`));
      }, Math.max(0, timeoutMs));
      this._waiters.push(w);
    });
  }

  /** Resolves true once the process has exited and its output is drained, false on timeout. */
  async waitExit(timeoutMs) {
    if (this.closed) return true;
    let timer;
    const timeout = new Promise((resolve) => {
      timer = setTimeout(() => resolve(false), Math.max(0, timeoutMs));
    });
    const r = await Promise.race([this._closed.then(() => true), timeout]);
    clearTimeout(timer);
    return r;
  }

  /**
   * Kills the whole process tree. Windows: taskkill /T /F. POSIX: SIGTERM to the process group
   * first, because tools/lib/godot_lock.mjs starts Godot in a group of its own and kills that tree
   * on SIGTERM; SIGKILL to the group follows after `graceMs`.
   */
  kill(graceMs = 3000) {
    if (this.closed || !this.child) return;
    this.killed = true;
    const pid = this.child.pid;
    if (IS_WIN) {
      killTree(pid);
      return;
    }
    try {
      process.kill(-pid, 'SIGTERM');
    } catch {
      try {
        process.kill(pid, 'SIGTERM');
      } catch {
        // already gone
      }
    }
    const t = setTimeout(() => {
      if (!this.closed) killTree(pid);
    }, graceMs);
    t.unref();
  }

  /** Every captured line, in arrival order. */
  text() {
    return this.lines.map((e) => e.line).join('\n');
  }
}

/** Runs a command to completion with a timeout; resolves {code, timedOut, lines, text}. */
export async function runToEnd(name, cmd, args, opts = {}) {
  const p = new Proc(name, cmd, args, opts);
  const done = await p.waitExit(opts.timeoutMs ?? 120_000);
  if (!done) {
    p.kill();
    await p.waitExit(15_000);
  }
  return { code: done ? p.exitCode : null, timedOut: !done, lines: p.lines.map((e) => e.line), text: p.text(), proc: p };
}
