// Command-line entry: node src/main.ts [--port=8787] [--host=<addr>] [--impl=auto|ws|builtin]
// Environment: PORT, HOST, RELAY_WS_IMPL, RELAY_TRUST_PROXY=1, RELAY_LOG=quiet.
// Prints "WATTLANDS_RELAY <ws url>" once it listens (harnesses read the port from it).

import type { ImplChoice } from './server.ts';
import { DEFAULT_PORT, parseImpl, startRelay } from './server.ts';

const USAGE = `Wattlands relay (BRIEF 5.3)
usage: node src/main.ts [--port=<n>] [--host=<addr>] [--impl=auto|ws|builtin]
env:   PORT, HOST, RELAY_WS_IMPL, RELAY_TRUST_PROXY=1 (behind Fly/Render), RELAY_LOG=quiet`;

function arg(name: string): string | undefined {
  const prefix = `--${name}=`;
  for (const a of process.argv.slice(2)) if (a.startsWith(prefix)) return a.slice(prefix.length);
  return undefined;
}

function fail(message: string): never {
  process.stderr.write(`relay: ${message}\n`);
  process.exit(1);
}

if (process.argv.includes('--help') || process.argv.includes('-h')) {
  process.stdout.write(`${USAGE}\n`);
  process.exit(0);
}

const portText = arg('port') ?? process.env.PORT ?? String(DEFAULT_PORT);
const port = Number(portText);
if (!Number.isInteger(port) || port < 0 || port > 65535) fail(`invalid port "${portText}"`);
const host = (arg('host') ?? process.env.HOST ?? '').trim() || undefined;
let impl: ImplChoice = 'auto';
try {
  impl = parseImpl(arg('impl') ?? process.env.RELAY_WS_IMPL);
} catch (err) {
  fail((err as Error).message);
}
const trustProxy = ['1', 'true', 'yes'].includes((process.env.RELAY_TRUST_PROXY ?? '').toLowerCase());
const quiet = (process.env.RELAY_LOG ?? '').toLowerCase() === 'quiet';
const log = (line: string): void => {
  if (!quiet) process.stdout.write(`${new Date().toISOString()} ${line}\n`);
};

try {
  const running = await startRelay({ port, host, impl, trustProxy, log });
  process.stdout.write(`WATTLANDS_RELAY ${running.url}\n`);
  let stopping = false;
  const stop = (signal: string): void => {
    if (stopping) return;
    stopping = true;
    log(`${signal}: closing every connection`);
    running.close(500).then(
      () => process.exit(0),
      () => process.exit(1),
    );
  };
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGBREAK'] as const) process.on(signal, () => stop(signal));
} catch (err) {
  fail((err as Error).message);
}
