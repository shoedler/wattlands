// Command-line and environment options for src/main.ts, as a pure function so they can be
// tested without starting a process.

import type { Limits } from './relay.ts';
import type { ImplChoice, ProxyTrust } from './server.ts';
import { DEFAULT_PORT, parseImpl } from './server.ts';

export const USAGE = `Wattlands relay (BRIEF 5.3)
usage: node src/main.ts [--port=<n>] [--host=<addr>] [--impl=auto|ws|builtin]
                        [--max-connections=<n>] [--max-connections-per-ip=<n>]
                        [--max-rooms=<n>] [--max-rooms-per-ip=<n>]
                        [--room-creates-per-min=<n>] [--hello-timeout=<seconds>]
env:   PORT, HOST, RELAY_WS_IMPL, RELAY_LOG=quiet,
       RELAY_TRUST_PROXY=1|<n>|fly (behind a proxy: 1 = last X-Forwarded-For entry, <n> = n-th from the right, fly = Fly-Client-IP),
       RELAY_MAX_CONNECTIONS, RELAY_MAX_CONNECTIONS_PER_IP, RELAY_MAX_ROOMS, RELAY_MAX_ROOMS_PER_IP,
       RELAY_ROOM_CREATES_PER_MIN, RELAY_HELLO_TIMEOUT_S (a whole number; 0 turns that limit off)`;

export interface MainOptions {
  help: boolean;
  /** TCP port; 0 picks a free one. */
  port: number;
  /** Interface to bind; undefined means every interface. */
  host: string | undefined;
  impl: ImplChoice;
  trustProxy: ProxyTrust;
  quiet: boolean;
  /** Limits set by flags or environment; the rest keep their defaults. */
  limits: Partial<Limits>;
}

type Env = Readonly<Record<string, string | undefined>>;

/** A limit's flag, environment variable, field and the factor from the given unit to the field's. */
const LIMIT_OPTIONS: readonly { flag: string; env: string; field: keyof Limits; factor: number }[] = [
  { flag: 'max-connections', env: 'RELAY_MAX_CONNECTIONS', field: 'maxConnections', factor: 1 },
  { flag: 'max-connections-per-ip', env: 'RELAY_MAX_CONNECTIONS_PER_IP', field: 'maxConnectionsPerIp', factor: 1 },
  { flag: 'max-rooms', env: 'RELAY_MAX_ROOMS', field: 'maxRooms', factor: 1 },
  { flag: 'max-rooms-per-ip', env: 'RELAY_MAX_ROOMS_PER_IP', field: 'maxRoomsPerIp', factor: 1 },
  { flag: 'room-creates-per-min', env: 'RELAY_ROOM_CREATES_PER_MIN', field: 'roomCreatesPerWindow', factor: 1 },
  { flag: 'hello-timeout', env: 'RELAY_HELLO_TIMEOUT_S', field: 'helloDeadlineMs', factor: 1000 },
];

const OPTIONS: readonly string[] = ['port', 'host', 'impl', ...LIMIT_OPTIONS.map((o) => o.flag)];

/** A value that is set and not blank, trimmed; otherwise undefined. */
function present(value: string | undefined): string | undefined {
  const v = value?.trim();
  return v === undefined || v === '' ? undefined : v;
}

/**
 * RELAY_TRUST_PROXY: unset, blank, 0, no or false trust nothing. 1, true or yes trust one
 * proxy (the last X-Forwarded-For entry), a larger whole number that many (the n-th entry
 * from the right), and "fly" trusts Fly-Client-IP. Anything else is an error, so a typo
 * can't silently turn the setting off or on.
 */
export function parseTrustProxy(value: string | undefined): ProxyTrust {
  const v = (value ?? '').trim().toLowerCase();
  if (['', '0', 'no', 'false'].includes(v)) return false;
  if (['1', 'true', 'yes'].includes(v)) return true;
  if (v === 'fly') return 'fly';
  if (/^[0-9]{1,2}$/.test(v)) return Number(v);
  throw new Error(`invalid RELAY_TRUST_PROXY "${value}" (use 1, a number of proxies, fly, or leave it unset)`);
}

function parseLimit(text: string, name: string): number {
  if (!/^[0-9]{1,9}$/.test(text)) throw new Error(`invalid ${name} "${text}" (a whole number; 0 turns the limit off)`);
  return Number(text);
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
    const m = /^--([a-z][a-z-]*)=(.*)$/s.exec(a);
    if (m === null || !OPTIONS.includes(m[1])) throw new Error(`unknown option "${a}"`);
    flags.set(m[1], m[2]);
  }
  const portFlag = flags.get('port');
  if (portFlag !== undefined && present(portFlag) === undefined) throw new Error('--port needs a value');
  const portText = present(portFlag) ?? present(env.PORT) ?? String(DEFAULT_PORT);
  const port = /^\d+$/.test(portText) ? Number(portText) : Number.NaN;
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error(`invalid port "${portText}"`);
  const limits: Partial<Limits> = {};
  for (const o of LIMIT_OPTIONS) {
    const flag = flags.get(o.flag);
    if (flag !== undefined && present(flag) === undefined) throw new Error(`--${o.flag} needs a value`);
    const text = present(flag) ?? present(env[o.env]);
    if (text === undefined) continue;
    limits[o.field] = parseLimit(text, present(flag) === undefined ? o.env : `--${o.flag}`) * o.factor;
  }
  return {
    help,
    port,
    host: present(flags.get('host')) ?? present(env.HOST),
    impl: parseImpl(flags.get('impl') ?? env.RELAY_WS_IMPL),
    trustProxy: parseTrustProxy(env.RELAY_TRUST_PROXY),
    quiet: (env.RELAY_LOG ?? '').trim().toLowerCase() === 'quiet',
    limits,
  };
}
