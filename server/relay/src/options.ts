// Command-line and environment options for src/main.ts, as a pure function so they can be
// tested without starting a process.

import type { ImplChoice } from './server.ts';
import { DEFAULT_PORT, parseImpl } from './server.ts';

export const USAGE = `Wattlands relay (BRIEF 5.3)
usage: node src/main.ts [--port=<n>] [--host=<addr>] [--impl=auto|ws|builtin]
env:   PORT, HOST, RELAY_WS_IMPL, RELAY_TRUST_PROXY=1 (behind Fly/Render), RELAY_LOG=quiet`;

export interface MainOptions {
  help: boolean;
  /** TCP port; 0 picks a free one. */
  port: number;
  /** Interface to bind; undefined means every interface. */
  host: string | undefined;
  impl: ImplChoice;
  trustProxy: boolean;
  quiet: boolean;
}

type Env = Readonly<Record<string, string | undefined>>;

const OPTIONS = ['port', 'host', 'impl'] as const;

/** A value that is set and not blank, trimmed; otherwise undefined. */
function present(value: string | undefined): string | undefined {
  const v = value?.trim();
  return v === undefined || v === '' ? undefined : v;
}

/**
 * Options from `argv` (the arguments after the script) and `env`. Flags win over the
 * environment, and a blank environment value counts as unset (PORT="" means 8787, not a
 * random port). Throws an Error with a one-line message on a bad or unknown option.
 */
export function parseMainOptions(argv: readonly string[], env: Env): MainOptions {
  const flags = new Map<string, string>();
  let help = false;
  for (const a of argv) {
    if (a === '--help' || a === '-h') {
      help = true;
      continue;
    }
    const m = /^--([a-z]+)=(.*)$/s.exec(a);
    if (m === null || !(OPTIONS as readonly string[]).includes(m[1])) throw new Error(`unknown option "${a}"`);
    flags.set(m[1], m[2]);
  }
  const portFlag = flags.get('port');
  if (portFlag !== undefined && present(portFlag) === undefined) throw new Error('--port needs a value');
  const portText = present(portFlag) ?? present(env.PORT) ?? String(DEFAULT_PORT);
  const port = /^\d+$/.test(portText) ? Number(portText) : Number.NaN;
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error(`invalid port "${portText}"`);
  return {
    help,
    port,
    host: present(flags.get('host')) ?? present(env.HOST),
    impl: parseImpl(flags.get('impl') ?? env.RELAY_WS_IMPL),
    trustProxy: ['1', 'true', 'yes'].includes((env.RELAY_TRUST_PROXY ?? '').trim().toLowerCase()),
    quiet: (env.RELAY_LOG ?? '').trim().toLowerCase() === 'quiet',
  };
}
