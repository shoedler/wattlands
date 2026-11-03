// tools/e2e/lib/services.mjs: the relay and the mock Strava server for one e2e game.
import path from 'node:path';
import { Proc } from './proc.mjs';
import { parsePort, parseUploads } from './checks.mjs';
import { childEnv, getFreePort, resolveProgram, sleep, substitute, tokenize } from './util.mjs';

/** Candidate upload listings on the mock when --strava-admin isn't given. */
export const ADMIN_CANDIDATES = ['/admin/uploads', '/__admin/uploads', '/_admin/uploads', '/__mock/uploads', '/_mock/uploads', '/mock/uploads'];

async function httpGet(url, timeoutMs = 3000) {
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
    const text = await res.text();
    return { status: res.status, text };
  } catch (err) {
    return { status: 0, text: '', error: err.message };
  }
}

function commandFor(template, vars) {
  const tokens = substitute(tokenize(template), vars);
  if (tokens.length === 0) throw new Error(`empty command "${template}"`);
  return { cmd: resolveProgram(tokens[0]), args: tokens.slice(1) };
}

/**
 * Starts the relay on a free port (or on `port`, to start it again where it was) and waits for GET /health. Returns
 * {proc, port, url (ws://127.0.0.1:<port>/v1), cmdline}.
 */
export async function startRelay({ repo, relayCmd, logFile, timeoutMs, env = process.env, echo, port: fixedPort = null }) {
  const port = fixedPort ?? (await getFreePort());
  const { cmd, args } = commandFor(relayCmd, { port, pid: process.pid });
  const proc = new Proc('relay', cmd, args, {
    cwd: repo,
    env: childEnv(env, { PORT: String(port), RELAY_PORT: String(port), HOST: '127.0.0.1' }),
    logFile,
    echo,
  });
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    if (proc.closed) {
      throw new Error(`relay exited (code ${proc.exitCode}) before answering /health; output: ${proc.text().slice(-400)}`);
    }
    const r = await httpGet(`http://127.0.0.1:${port}/health`, 1500);
    if (r.status === 200) break;
    if (Date.now() > deadline) {
      proc.kill();
      throw new Error(`relay did not answer GET /health on port ${port} within ${Math.round(timeoutMs / 1000)} s (is --relay-cmd right? it must honour PORT or {port})`);
    }
    await sleep(200);
  }
  return { proc, port, url: `ws://127.0.0.1:${port}/v1`, cmdline: [cmd === process.execPath ? 'node' : cmd, ...args] };
}

/**
 * Starts the mock Strava server. With {port} in the command the harness picks the port; otherwise
 * it reads it from the server's output (a URL, "port N" or {"port": N}). Returns
 * {proc, port, base (http://127.0.0.1:<port>), cmdline}.
 */
export async function startStrava({ repo, stravaCmd, logFile, timeoutMs, env = process.env, echo }) {
  const fixed = stravaCmd.includes('{port}') ? await getFreePort() : null;
  const { cmd, args } = commandFor(stravaCmd, fixed ? { port: fixed, pid: process.pid } : { pid: process.pid });
  const proc = new Proc('mock_strava', cmd, args, { cwd: repo, env: childEnv(env), logFile, echo });
  let port = fixed;
  if (!port) {
    const deadline = Date.now() + timeoutMs;
    while (!port) {
      for (const e of proc.lines) {
        port = parsePort(e.line);
        if (port) break;
      }
      if (port) break;
      if (proc.closed) throw new Error(`mock Strava exited (code ${proc.exitCode}) before printing its port; output: ${proc.text().slice(-400)}`);
      if (Date.now() > deadline) {
        proc.kill();
        throw new Error(`mock Strava printed no port within ${Math.round(timeoutMs / 1000)} s (it should print its URL; or put {port} in --strava-cmd)`);
      }
      await sleep(100);
    }
  }
  const base = `http://127.0.0.1:${port}`;
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const r = await httpGet(`${base}/`, 1500);
    if (r.status > 0) break;
    if (proc.closed) throw new Error(`mock Strava exited (code ${proc.exitCode}); output: ${proc.text().slice(-400)}`);
    if (Date.now() > deadline) {
      proc.kill();
      throw new Error(`mock Strava does not answer on ${base} within ${Math.round(timeoutMs / 1000)} s`);
    }
    await sleep(200);
  }
  return { proc, port, base, cmdline: [cmd === process.execPath ? 'node' : cmd, ...args] };
}

/** The mock's uploads: {path, uploads} or {error}. */
export async function queryUploads(base, adminPath = null) {
  const candidates = adminPath ? [adminPath] : ADMIN_CANDIDATES;
  const tried = [];
  for (const p of candidates) {
    const url = `${base}${p.startsWith('/') ? p : `/${p}`}`;
    const r = await httpGet(url, 3000);
    tried.push(`${p} -> ${r.status || r.error}`);
    if (r.status !== 200) continue;
    let json;
    try {
      json = JSON.parse(r.text);
    } catch {
      continue;
    }
    const uploads = parseUploads(json);
    if (uploads) return { path: p, uploads };
  }
  return { error: `no upload listing on the mock Strava server (tried ${tried.join(', ')}); pass --strava-admin=<path>` };
}

/** Stops a service and waits briefly for it to go. */
export async function stopService(svc) {
  if (!svc?.proc) return;
  svc.proc.kill();
  await svc.proc.waitExit(10_000);
}

export function serviceLog(outDir, name) {
  return path.join(outDir, `${name}.log`);
}
