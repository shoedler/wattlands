// Command line of tools/art/generate.mjs. Flags are "--key=value" or a bare "--flag", as everywhere
// in this repo (CmdLine); "--key value" is not supported.

export const USAGE = `usage: node tools/art/generate.mjs --game=<id> [options]

  --game=<id>                 the game whose assets/<id>/art.json to generate (required)
  --only=<ids>                comma list of sprite ids to process (default: every sprite)
  --dry-run                   print the plan (request sizes, aspect error, cost) and contact nothing
  --json                      with --dry-run: print the plan as JSON
  --budget=<usd>              stop before this run's estimated spend would pass <usd> (default 10)
  --reroll=<ids>              comma list: skip the cache and the 24-hour reuse, pay for new results
  --select=<sprite id>:<request id>
                              mark that result as the sprite's selected one (repeatable or comma
                              list); edits the manifest only, contacts nothing
  --mock=<url>                talk to tools/art/mock_fal at <url> (a loopback URL) instead of fal;
                              needs neither FAL_KEY nor WATTLANDS_ALLOW_ART and never sends the key
  --root=<dir>                project root holding assets/ and .art_cache/ (default: this repo)
  --concurrency=<n>           requests in flight at once (default 4)
  --poll-ms=<ms>              status poll interval (default 1500)
  --timeout-s=<s>             give up waiting for one request after <s> seconds (default 900)
  --help                      this text

Real fal calls need both FAL_KEY and WATTLANDS_ALLOW_ART=1. Exit codes: 0 done, 1 some sprites
failed, 2 usage or art.json error, 3 budget stop, 4 refused by the art lock.
`;

export class UsageError extends Error {}

const VALUE_FLAGS = new Set(['game', 'only', 'budget', 'reroll', 'select', 'mock', 'root', 'concurrency', 'poll-ms', 'timeout-s']);
const BARE_FLAGS = new Set(['dry-run', 'json', 'help']);

function list(v) {
  return v
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s !== '');
}

function num(name, v, { min = 0, integer = false } = {}) {
  const n = Number(v);
  if (v.trim() === '' || !Number.isFinite(n) || n < min || (integer && !Number.isInteger(n))) {
    throw new UsageError(`--${name}: expected ${integer ? 'an integer' : 'a number'} >= ${min}, got "${v}"`);
  }
  return n;
}

export function parseArgs(argv) {
  const o = {
    game: null,
    only: [],
    reroll: [],
    select: [],
    dryRun: false,
    json: false,
    budget: 10,
    mock: null,
    root: null,
    concurrency: 4,
    pollMs: 1500,
    timeoutS: 900,
    help: false,
  };
  for (const a of argv) {
    if (!a.startsWith('--')) throw new UsageError(`unexpected argument "${a}"`);
    const body = a.slice(2);
    const eq = body.indexOf('=');
    const key = eq >= 0 ? body.slice(0, eq) : body;
    const val = eq >= 0 ? body.slice(eq + 1) : null;
    if (BARE_FLAGS.has(key)) {
      if (val !== null) throw new UsageError(`--${key} takes no value`);
      if (key === 'dry-run') o.dryRun = true;
      else if (key === 'json') o.json = true;
      else o.help = true;
      continue;
    }
    if (!VALUE_FLAGS.has(key)) throw new UsageError(`unknown option --${key}`);
    if (val === null || val === '') throw new UsageError(`--${key} needs a value: --${key}=<value>`);
    switch (key) {
      case 'game':
        if (!/^[a-z0-9_]+$/.test(val)) throw new UsageError(`--game: "${val}" is not a game id`);
        o.game = val;
        break;
      case 'only':
        o.only.push(...list(val));
        break;
      case 'reroll':
        o.reroll.push(...list(val));
        break;
      case 'select':
        for (const item of list(val)) {
          const i = item.indexOf(':');
          if (i <= 0 || i === item.length - 1) throw new UsageError(`--select: expected <sprite id>:<request id>, got "${item}"`);
          o.select.push({ sprite: item.slice(0, i), request_id: item.slice(i + 1) });
        }
        break;
      case 'budget':
        o.budget = num(key, val);
        break;
      case 'mock':
        o.mock = val;
        break;
      case 'root':
        o.root = val;
        break;
      case 'concurrency':
        o.concurrency = num(key, val, { min: 1, integer: true });
        break;
      case 'poll-ms':
        o.pollMs = num(key, val, { min: 1, integer: true });
        break;
      case 'timeout-s':
        o.timeoutS = num(key, val, { min: 0.01 });
        break;
      default:
        break;
    }
  }
  if (o.help) return o;
  if (!o.game) throw new UsageError('--game=<id> is required');
  if (o.select.length > 0 && (o.only.length > 0 || o.reroll.length > 0 || o.dryRun)) {
    throw new UsageError('--select only edits the manifest; run it without --only, --reroll or --dry-run');
  }
  if (o.json && !o.dryRun) throw new UsageError('--json works with --dry-run only');
  return o;
}
