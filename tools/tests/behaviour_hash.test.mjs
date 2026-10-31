// Tests for tools/qa/behaviour_hash.mjs: the pure rows and compare, then the CLI with a stub in place of
// tools/run_game_sim. No Godot.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { TOOLS } from './helpers.mjs';
import {
  SCENARIOS,
  compareRows,
  describeMismatch,
  digest,
  firstDiff,
  selectScenarios,
} from '../qa/behaviour_hash.mjs';

const SCRIPT = path.join(TOOLS, 'qa', 'behaviour_hash.mjs');
const sha = (s) => createHash('sha256').update(s).digest('hex');

const REPORT = {
  deterministic_hash: 'abc',
  snapshots: [{ sha256: 'aa', bytes: 1 }, { sha256: 'bb', bytes: 2 }],
  events: [{ t: 1, type: 'x' }],
  directives: [{ t: 0, kind: 'request' }],
};

describe('digest', () => {
  test('hashes what the spec names', () => {
    assert.deepEqual(digest(REPORT), {
      deterministic_hash: 'abc',
      snapshots: sha('aabb'),
      events: sha(JSON.stringify(REPORT.events)),
      directives: sha(JSON.stringify(REPORT.directives)),
      n_snapshots: 2,
      n_events: 1,
    });
  });

  test('ignores everything else in a report, and survives an empty one', () => {
    assert.deepEqual(digest({ ...REPORT, meta: { wall_s: 9 }, fit_paths: ['x'] }), digest(REPORT));
    assert.equal(digest({}).n_snapshots, 0);
  });
});

describe('firstDiff', () => {
  test('finds the first differing entry, a length change included', () => {
    assert.equal(firstDiff([1, 2], [1, 2]), -1);
    assert.equal(firstDiff([1, 2, 3], [1, 9, 3]), 1);
    assert.equal(firstDiff([1], [1, 2]), 1);
    assert.equal(firstDiff([{ sha256: 'a', n: 1 }], [{ sha256: 'a', n: 2 }], (x) => x.sha256), -1);
  });
});

describe('compareRows and describeMismatch', () => {
  test('equal rows match, and only rows that ran are compared', () => {
    const row = digest(REPORT);
    assert.deepEqual(compareRows({ a: row, b: { ...row, events: 'other' } }, { a: row }), []);
  });

  test('a changed field and a row with no baseline are mismatches', () => {
    const row = digest(REPORT);
    const m = compareRows({ a: row }, { a: { ...row, events: 'other' }, b: row });
    assert.deepEqual(m.map((x) => [x.name, x.missing]), [['a', false], ['b', true]]);
    assert.deepEqual(m[0].fields, ['events']);
  });

  test('names the first differing snapshot, event and directive', () => {
    const was = REPORT;
    const now = {
      ...REPORT,
      snapshots: [{ sha256: 'aa' }, { sha256: 'cc' }],
      events: [{ t: 1, type: 'y' }],
      directives: [],
    };
    const m = compareRows({ a: digest(was) }, { a: digest(now) })[0];
    const text = describeMismatch(m, digest(was), digest(now), was, now).join('\n');
    assert.match(text, /a differs: snapshots, events, directives$/m);
    assert.match(text, /first differing snapshot: index 1/);
    assert.match(text, /first differing events\[0\]: base \{"t":1,"type":"x"\}, now \{"t":1,"type":"y"\}/);
    assert.match(text, /first differing directives\[0\]: base \{"t":0,"kind":"request"\}, now nothing/);
  });

  test('says so when the baseline report is gone', () => {
    const m = compareRows({ a: digest(REPORT) }, { a: { ...digest(REPORT), events: 'x' } })[0];
    assert.match(describeMismatch(m, digest(REPORT), { ...digest(REPORT), events: 'x' }, null, REPORT).join('\n'), /baseline report is gone/);
  });
});

describe('selectScenarios', () => {
  test('the ten scenarios, each with a unique name', () => {
    assert.equal(SCENARIOS.length, 10);
    assert.equal(new Set(SCENARIOS.map((s) => s.name)).size, 10);
    assert.equal(selectScenarios(null, null).length, 10);
  });

  test('filters by game and by name, and refuses an unknown one', () => {
    assert.deepEqual(selectScenarios('siege,_template', null).map((s) => s.name), ['siege_s7', 'siege_short', 'template']);
    assert.deepEqual(selectScenarios(null, 'tank_s7').map((s) => s.name), ['tank_s7']);
    assert.throws(() => selectScenarios('nope', null), /no scenario for game nope/);
    assert.throws(() => selectScenarios(null, 'nope'), /no scenario named nope/);
  });

  test('every scenario names a real content id', () => {
    for (const s of SCENARIOS) {
      const manifest = path.join(path.dirname(TOOLS), 'src', 'games', s.game, 'game.json');
      const contents = JSON.parse(fs.readFileSync(manifest, 'utf8')).contents;
      const content = s.flags.find((f) => f.startsWith('--content=')).slice('--content='.length);
      assert.ok(contents.includes(content), `${s.name}: ${content}`);
    }
  });
});

describe('the command line, with a stub simulation', () => {
  // The stub writes a report whose events carry STUB_EVENT and the args it got, the way run_game_sim would.
  const STUB = `#!/usr/bin/env bash
report=""
for a in "$@"; do
  case "$a" in
    --report=*) report="\${a#--report=}" ;;
    --game=broken) exit 3 ;;
  esac
done
[ "\${STUB_FAIL:-}" = "1" ] && exit 5
printf '{"deterministic_hash":"h%s","snapshots":[{"sha256":"aa"}],"events":[{"e":"%s"}],"directives":[]}' \\
  "\${STUB_EVENT:-0}" "\${STUB_EVENT:-0}" >"$report"
`;
  const setup = (t) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'behaviour_hash-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const stub = path.join(dir, 'stub.sh');
    fs.writeFileSync(stub, STUB);
    return { dir, stub };
  };
  const cli = (stub, env, ...args) =>
    spawnSync(process.execPath, [SCRIPT, `--tool=${stub}`, ...args], {
      encoding: 'utf8',
      env: { ...process.env, ...env },
    });

  test('writes a row per scenario, and a subset merges into --out', (t) => {
    const { dir, stub } = setup(t);
    const out = path.join(dir, 'base.json');
    let r = cli(stub, {}, `--out=${out}`, '--games=siege');
    assert.equal(r.status, 0, r.stdout + r.stderr);
    assert.deepEqual(Object.keys(JSON.parse(fs.readFileSync(out, 'utf8'))), ['siege_s7', 'siege_short']);
    assert.ok(fs.existsSync(path.join(dir, 'base', 'siege_s7.json')));
    r = cli(stub, {}, `--out=${out}`, '--names=template');
    assert.equal(r.status, 0, r.stdout + r.stderr);
    assert.deepEqual(Object.keys(JSON.parse(fs.readFileSync(out, 'utf8'))), ['siege_s7', 'siege_short', 'template']);
  });

  test('--compare passes on the same behaviour and fails with the first difference on another', (t) => {
    const { dir, stub } = setup(t);
    const base = path.join(dir, 'base.json');
    assert.equal(cli(stub, {}, `--out=${base}`, '--names=template').status, 0);
    const same = cli(stub, {}, `--out=${path.join(dir, 'same.json')}`, `--compare=${base}`, '--names=template');
    assert.equal(same.status, 0, same.stdout + same.stderr);
    assert.match(same.stdout, /1 scenario\(s\) match/);
    const other = cli(stub, { STUB_EVENT: '1' }, `--out=${path.join(dir, 'other.json')}`, `--compare=${base}`, '--names=template');
    assert.equal(other.status, 1, other.stdout + other.stderr);
    assert.match(other.stdout, /template differs: deterministic_hash, events/);
    assert.match(other.stdout, /first differing events\[0\]: base \{"e":"0"\}, now \{"e":"1"\}/);
  });

  test('a failed run exits 1 and writes no row for it', (t) => {
    const { dir, stub } = setup(t);
    const out = path.join(dir, 'x.json');
    const r = cli(stub, { STUB_FAIL: '1' }, `--out=${out}`, '--names=template');
    assert.equal(r.status, 1);
    assert.match(r.stdout, /template FAILED, exit 5/);
    assert.deepEqual(JSON.parse(fs.readFileSync(out, 'utf8')), {});
  });

  test('bad flags exit 2', (t) => {
    const { stub } = setup(t);
    assert.equal(cli(stub, {}).status, 2);
    assert.equal(cli(stub, {}, '--out=x.json', '--wat=1').status, 2);
    assert.equal(cli(stub, {}, '--out=x.json', '--games=nope').status, 2);
  });
});
