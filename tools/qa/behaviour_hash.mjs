#!/usr/bin/env node
// tools/qa/behaviour_hash.mjs: a fingerprint of what the rules do, to prove a refactor changed nothing.
//
//   node tools/qa/behaviour_hash.mjs --out=build/behaviour/<label>.json [--compare=<file>] [--games=tank,siege]
//                                    [--names=<scenario,...>]
//
// Runs SCENARIOS serially through tools/run_game_sim (reports in build/behaviour/<label>/<name>.json) and writes
// {name: {deterministic_hash, snapshots, events, directives, n_snapshots, n_events}}. --games and --names run a subset
// and merge its rows into an existing --out, so a long run can be split across shell calls. --compare checks only the
// rows this call ran. On a mismatch it prints the first differing snapshot index, events[] and directives[] entry,
// read from the reports beside the --compare file, and exits 1. Exit 2 means bad flags.
//
// The fingerprint is blind to views: headless runs have none. Hashes need one binary, so never compare mono against
// standard. --tool replaces tools/run_game_sim and is for tools/tests/behaviour_hash.test.mjs only.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const TOOLS = path.dirname(HERE);
const PROJECT = path.dirname(TOOLS);
const ERG = '--rider=erg:compliance=1.0';
const GODOT_TIMEOUT_S = 900;

export const SCENARIOS = [
  { name: 'tank_s7', game: 'tank', flags: ['--content=ashfall_road', '--players=3', '--bots=0', ERG, '--seed=1'] },
  { name: 'tank_drill', game: 'tank', flags: ['--content=drill', '--players=1', '--bots=0', ERG, '--seed=2'] },
  { name: 'tank_roam', game: 'tank', flags: ['--content=roam_10', '--players=4', '--bots=0', ERG, '--seed=3'] },
  {
    name: 'tank_hard',
    game: 'tank',
    flags: ['--content=ambush_15', '--players=2', '--bots=2', ERG, '--options={"difficulty":"hard"}', '--seed=4'],
  },
  { name: 'siege_s7', game: 'siege', flags: ['--content=vo2', '--players=4', '--bots=0', ERG, '--seed=1'] },
  { name: 'siege_short', game: 'siege', flags: ['--content=short', '--players=1', '--bots=3', ERG, '--seed=2'] },
  { name: 'fishing_d', game: 'fishing', flags: ['--content=roam_10', '--players=2', '--bots=2', ERG, '--seed=7'] },
  { name: 'workout_e2e', game: 'workout', flags: ['--content=e2e', '--players=3', '--bots=0', ERG, '--seed=1'] },
  {
    name: 'workout_course',
    game: 'workout',
    flags: ['--content=rolling_road', '--players=1', '--bots=0', ERG, '--seed=2'],
  },
  { name: 'template', game: '_template', flags: ['--content=short', '--players=1', '--bots=0', ERG, '--seed=1'] },
];

const FIELDS = ['deterministic_hash', 'snapshots', 'events', 'directives', 'n_snapshots', 'n_events'];
const sha256 = (text) => createHash('sha256').update(text).digest('hex');
const short = (v) => {
  const s = JSON.stringify(v) ?? 'nothing';
  return s.length > 400 ? `${s.slice(0, 400)}...` : s;
};

/** One report's row. */
export function digest(report) {
  const snapshots = report.snapshots ?? [];
  const events = report.events ?? [];
  return {
    deterministic_hash: report.deterministic_hash ?? '',
    snapshots: sha256(snapshots.map((s) => s.sha256 ?? '').join('')),
    events: sha256(JSON.stringify(events)),
    directives: sha256(JSON.stringify(report.directives ?? [])),
    n_snapshots: snapshots.length,
    n_events: events.length,
  };
}

/** Index of the first entry where two arrays differ, -1 when equal. `key` picks what is compared. */
export function firstDiff(a, b, key = (x) => JSON.stringify(x)) {
  const n = Math.max(a.length, b.length);
  for (let i = 0; i < n; i += 1) {
    if (i >= a.length || i >= b.length || key(a[i]) !== key(b[i])) return i;
  }
  return -1;
}

/** The fields of `base` and `now` that differ, for the rows in `now`. A row with no baseline lists every field. */
export function compareRows(base, now) {
  const out = [];
  for (const [name, row] of Object.entries(now)) {
    const was = base[name];
    const fields = was ? FIELDS.filter((f) => was[f] !== row[f]) : [...FIELDS];
    if (fields.length > 0) out.push({ name, fields, missing: !was });
  }
  return out;
}

/** The lines that explain one mismatch, given both reports (the baseline's may be null). */
export function describeMismatch(m, baseRow, row, baseReport, report) {
  const lines = [`behaviour_hash: ${m.name} differs: ${m.fields.join(', ')}`];
  if (m.missing) return [`behaviour_hash: ${m.name} has no baseline row`];
  for (const f of m.fields) lines.push(`  ${f}: base ${baseRow[f]}, now ${row[f]}`);
  if (!baseReport) {
    lines.push('  the baseline report is gone, so no first difference can be named');
    return lines;
  }
  const s = firstDiff(baseReport.snapshots ?? [], report.snapshots ?? [], (x) => x.sha256);
  if (s >= 0) lines.push(`  first differing snapshot: index ${s}`);
  for (const key of ['events', 'directives']) {
    const a = baseReport[key] ?? [];
    const b = report[key] ?? [];
    const i = firstDiff(a, b);
    if (i >= 0) lines.push(`  first differing ${key}[${i}]: base ${short(a[i])}, now ${short(b[i])}`);
  }
  return lines;
}

function parseArgs(argv) {
  const o = { games: null, names: null, compare: null, out: null, tool: null };
  for (const a of argv) {
    const m = a.match(/^--(out|compare|games|names|tool)=(.*)$/);
    if (!m) throw new Error(`unknown flag ${a}`);
    o[m[1]] = m[2];
  }
  if (!o.out) throw new Error('--out=<file> is required');
  return o;
}

export function selectScenarios(games, names) {
  const g = games ? games.split(',').filter(Boolean) : null;
  const n = names ? names.split(',').filter(Boolean) : null;
  for (const x of g ?? []) {
    if (!SCENARIOS.some((s) => s.game === x)) throw new Error(`no scenario for game ${x}`);
  }
  for (const x of n ?? []) {
    if (!SCENARIOS.some((s) => s.name === x)) throw new Error(`no scenario named ${x}`);
  }
  return SCENARIOS.filter((s) => (!g || g.includes(s.game)) && (!n || n.includes(s.name)));
}

const slashes = (p) => p.replaceAll('\\', '/');

function runScenario(s, reportPath, tool) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  const args = [
    slashes(tool),
    `--game=${s.game}`,
    ...s.flags,
    '--sim-speed=200',
    `--report=${slashes(reportPath)}`,
    `--godot-timeout=${GODOT_TIMEOUT_S}`,
  ];
  const r = spawnSync(process.env.WATTLANDS_BASH || 'bash', args, {
    cwd: PROJECT,
    encoding: 'utf8',
    maxBuffer: 1 << 28,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  fs.writeFileSync(reportPath.replace(/\.json$/, '.log'), `${r.stdout ?? ''}${r.stderr ?? ''}`);
  return r.status;
}

const readJson = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));

function main(argv) {
  let o;
  let chosen;
  try {
    o = parseArgs(argv);
    chosen = selectScenarios(o.games, o.names);
  } catch (e) {
    process.stderr.write(`behaviour_hash: ${e.message}\n`);
    return 2;
  }
  const out = path.resolve(o.out);
  const dir = out.replace(/\.json$/, '');
  const tool = o.tool ? path.resolve(o.tool) : path.join(TOOLS, 'run_game_sim');
  const subset = chosen.length < SCENARIOS.length;
  const rows = subset && fs.existsSync(out) ? readJson(out) : {};
  const ran = {};
  let bad = 0;
  for (const s of chosen) {
    const report = path.join(dir, `${s.name}.json`);
    fs.rmSync(report, { force: true });
    const t0 = Date.now();
    const status = runScenario(s, report, tool);
    const secs = ((Date.now() - t0) / 1000).toFixed(0);
    if (status !== 0 || !fs.existsSync(report)) {
      process.stdout.write(`behaviour_hash: ${s.name} FAILED, exit ${status} (${report.replace(/\.json$/, '.log')})\n`);
      bad += 1;
      continue;
    }
    ran[s.name] = digest(readJson(report));
    rows[s.name] = ran[s.name];
    process.stdout.write(`behaviour_hash: ${s.name} ${secs} s, ${ran[s.name].n_snapshots} snapshots\n`);
  }
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const sorted = Object.fromEntries(Object.keys(rows).sort().map((k) => [k, rows[k]]));
  fs.writeFileSync(out, `${JSON.stringify(sorted, null, 2)}\n`);
  if (o.compare) {
    const cmp = path.resolve(o.compare);
    const base = readJson(cmp);
    const baseDir = cmp.replace(/\.json$/, '');
    const mismatches = compareRows(base, ran);
    for (const m of mismatches) {
      const baseFile = path.join(baseDir, `${m.name}.json`);
      const baseReport = fs.existsSync(baseFile) ? readJson(baseFile) : null;
      const lines = describeMismatch(m, base[m.name], ran[m.name], baseReport, readJson(path.join(dir, `${m.name}.json`)));
      process.stdout.write(`${lines.join('\n')}\n`);
    }
    bad += mismatches.length;
    if (mismatches.length === 0) process.stdout.write(`behaviour_hash: ${Object.keys(ran).length} scenario(s) match ${o.compare}\n`);
  }
  process.stdout.write(`behaviour_hash: ${bad === 0 ? 'ok' : `${bad} problem(s)`}, wrote ${o.out}\n`);
  return bad === 0 ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
