// tools/e2e/lib/util.mjs: small helpers for the end-to-end harness (zero dependencies).
import dgram from 'node:dgram';
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const LIB_DIR = path.dirname(fileURLToPath(import.meta.url));
export const E2E_DIR = path.dirname(LIB_DIR);
/** The checkout that holds this harness. */
export const DEFAULT_REPO = path.resolve(E2E_DIR, '..', '..');
export const IS_WIN = process.platform === 'win32';

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, Math.max(0, ms)));

/** Forward slashes everywhere (Godot and Git Bash both take C:/x/y). */
export function slash(p) {
  return String(p).replaceAll('\\', '/');
}

/**
 * Splits a command string into argv like a POSIX shell would for plain words: whitespace
 * separates, "double" and 'single' quotes group, a backslash escapes the next character
 * outside single quotes (except before a non-special character on Windows paths, where it
 * stays). No globbing, variables or operators.
 */
export function tokenize(cmd) {
  const out = [];
  let cur = '';
  let inWord = false;
  let quote = null;
  const s = String(cmd ?? '');
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (quote) {
      if (c === quote) {
        quote = null;
      } else if (c === '\\' && quote === '"' && (s[i + 1] === '"' || s[i + 1] === '\\')) {
        cur += s[++i];
      } else {
        cur += c;
      }
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      inWord = true;
      continue;
    }
    if (/\s/.test(c)) {
      if (inWord) {
        out.push(cur);
        cur = '';
        inWord = false;
      }
      continue;
    }
    if (c === '\\' && (s[i + 1] === '"' || s[i + 1] === "'" || s[i + 1] === ' ')) {
      cur += s[++i];
      inWord = true;
      continue;
    }
    cur += c;
    inWord = true;
  }
  if (quote) throw new Error(`unterminated ${quote} quote in command: ${s}`);
  if (inWord) out.push(cur);
  return out;
}

/** Replaces {port}, {pid} (and any other {key} from vars) in every token. */
export function substitute(tokens, vars) {
  return tokens.map((t) => t.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? String(vars[k]) : m)));
}

/** The program for a command's first token: "node" means this very Node. */
export function resolveProgram(name) {
  if (name === 'node' || name === 'node.exe') return process.execPath;
  return name;
}

/** Variables no e2e child may see: the fal key and the art switch (tools/run_tests drops them too). */
export const DROPPED_ENV = ['FAL_KEY', 'WATTLANDS_ALLOW_ART'];
/** The BRIEF 1 locks every e2e child runs with. */
export const LOCK_ENV = { WATTLANDS_NO_HW_CONTROL: '1', WATTLANDS_NO_NETWORK_INTEGRATIONS: '1' };

/**
 * The environment for every child the harness starts: the caller's environment without the art
 * variables (any letter case, since Windows variable names ignore case), plus both locks, plus
 * `extra`.
 */
export function childEnv(base = process.env, extra = {}) {
  const env = {};
  const dropped = new Set(DROPPED_ENV.map((k) => k.toUpperCase()));
  for (const [k, v] of Object.entries(base)) {
    if (v === undefined) continue;
    if (dropped.has(k.toUpperCase())) continue;
    if (k.toUpperCase() in LOCK_ENV && k !== k.toUpperCase()) continue;
    env[k] = v;
  }
  Object.assign(env, LOCK_ENV, extra);
  return env;
}

// Ports this process already handed out: concurrent scenarios (faults.mjs --jobs) each pick theirs
// before binding, and a relay restarted on its own port leaves it free for a moment.
const handedOut = new Set();

function pickPort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.unref();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

/**
 * A free TCP port on 127.0.0.1 (released before returning; the caller binds it soon after), never one
 * this process handed out before.
 */
export async function getFreePort() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const port = await pickPort();
    if (!handedOut.has(port)) {
      handedOut.add(port);
      return port;
    }
  }
  throw new Error('getFreePort: the system kept offering ports this run already uses');
}

/**
 * The band the built-in relay's ports come from: below every OS's ephemeral range (Linux hands out from
 * 32768, Windows and macOS from 49152). A port from getFreePort is ephemeral, so a socket that sends
 * before it binds (a host's beacon is one) can be given that number by the OS between the probe and the
 * bind: with several built-in scenarios at once, a client's discovery listener then failed with "can't
 * listen". Nothing is handed a port in this band unless it asks for that number.
 */
export const BAND_LOW = 20000;
export const BAND_HIGH = 32000;

function probeTcp(port) {
  return new Promise((resolve) => {
    const srv = net.createServer();
    srv.unref();
    srv.once('error', () => resolve(false));
    srv.listen({ port, host: '127.0.0.1', exclusive: true }, () => srv.close(() => resolve(true)));
  });
}

function probeUdp(port) {
  return new Promise((resolve) => {
    const sock = dgram.createSocket({ type: 'udp4', reuseAddr: false });
    sock.once('error', () => {
      try {
        sock.close();
      } catch {
        // never bound
      }
      resolve(false);
    });
    sock.bind({ port, address: '127.0.0.1', exclusive: true }, () => sock.close(() => resolve(true)));
  });
}

/**
 * A port in [BAND_LOW, BAND_HIGH] that is free on 127.0.0.1 for TCP and for UDP alike (probed as each,
 * then released; the caller binds it soon after), never one this process handed out before. Loopback
 * only, so no probe reaches the LAN or raises a firewall prompt. `start` picks where the search begins
 * (default: random, so two processes rarely try the same numbers).
 */
export async function getBandPort({ start = null } = {}) {
  const span = BAND_HIGH - BAND_LOW + 1;
  let at = start ?? BAND_LOW + Math.floor(Math.random() * span);
  for (let tried = 0; tried < 400; tried += 1, at = at >= BAND_HIGH ? BAND_LOW : at + 1) {
    if (handedOut.has(at)) continue;
    handedOut.add(at); // claimed before the probes, so a concurrent call in this process skips it
    if ((await probeTcp(at)) && (await probeUdp(at))) return at;
  }
  throw new Error(`getBandPort: no port free for TCP and UDP in ${BAND_LOW}-${BAND_HIGH} after 400 tries`);
}

function which(name) {
  const exts = IS_WIN ? ['.exe', '.cmd', ''] : [''];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    for (const ext of exts) {
      const file = path.join(dir, name + ext);
      try {
        if (fs.statSync(file).isFile()) return file;
      } catch {
        // keep looking
      }
    }
  }
  return null;
}

/** Git Bash's bash.exe on Windows (never WSL's System32\bash.exe), /bin/bash elsewhere. */
export function findBash() {
  const env = process.env.WATTLANDS_BASH;
  if (env && fs.existsSync(env)) return env;
  if (!IS_WIN) return fs.existsSync('/bin/bash') ? '/bin/bash' : which('bash');
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    const low = dir.toLowerCase();
    if (!dir || low.includes('system32') || low.includes('windowsapps')) continue;
    const exe = path.join(dir, 'bash.exe');
    if (fs.existsSync(exe)) return exe;
  }
  for (const c of ['C:\\Program Files\\Git\\usr\\bin\\bash.exe', 'C:\\Program Files\\Git\\bin\\bash.exe']) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

/**
 * Strava credentials the harness gives the auto-upload peer: server/mock_strava's default test
 * client (its README), never a real app's. The mock checks the secret on the token exchange.
 */
export const STRAVA_CLIENT_ID = '12345';
export const STRAVA_CLIENT_SECRET = 'mock-client-secret';

/** argv with secrets masked, for logs and the report. */
export function redact(args) {
  return args.map((a) => {
    const m = /^(--[\w-]*(secret|token|password)[\w-]*=)(.*)$/i.exec(a);
    return m ? `${m[1]}***` : a;
  });
}

export function quoteForLog(args) {
  return args.map((a) => (/[\s"']/.test(a) ? JSON.stringify(a) : a)).join(' ');
}

export function readJson(file) {
  try {
    return { ok: true, value: JSON.parse(fs.readFileSync(file, 'utf8')) };
  } catch (err) {
    return { ok: false, error: err.code === 'ENOENT' ? `missing ${file}` : `${file}: ${err.message}` };
  }
}

export function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

export function fmtSeconds(s) {
  if (!Number.isFinite(s)) return '?';
  const m = Math.floor(s / 60);
  const r = Math.round(s - m * 60);
  return m > 0 ? `${m}m${String(r).padStart(2, '0')}s` : `${r}s`;
}

export function tail(lines, n = 30) {
  return lines.slice(Math.max(0, lines.length - n));
}
