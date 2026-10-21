// Command-line entry: node src/main.ts [--port=8787] [--host=<addr>] [--impl=auto|ws|builtin]
// Environment: PORT, HOST, RELAY_WS_IMPL, RELAY_TRUST_PROXY=1, RELAY_LOG=quiet.
// Prints "WATTLANDS_RELAY <ws url>" once it listens (harnesses read the port from it).

import type { MainOptions } from './options.ts';
import { parseMainOptions, USAGE } from './options.ts';
import { startRelay } from './server.ts';

function fail(message: string): never {
  process.stderr.write(`relay: ${message}\n${USAGE}\n`);
  process.exit(1);
}

let opts: MainOptions;
try {
  opts = parseMainOptions(process.argv.slice(2), process.env);
} catch (err) {
  fail((err as Error).message);
}

if (opts.help) {
  process.stdout.write(`${USAGE}\n`);
  process.exit(0);
}

const log = (line: string): void => {
  // The wall clock only stamps log lines; no relay rule reads it.
  if (!opts.quiet) process.stdout.write(`${new Date().toISOString()} ${line}\n`);
};

try {
  const running = await startRelay({ port: opts.port, host: opts.host, impl: opts.impl, trustProxy: opts.trustProxy, log });
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
