// Tests for tools/lib/gate_core.mjs: shards, touched games, the merged GUT verdict, the lane verdict and
// the pure rules of `tools/gate check`. No git, no Godot, no process starts.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { evaluateGut } from '../lib/gut_gate.mjs';
import {
  aggregateGut,
  checkAddedText,
  checkAppendOnly,
  checkClassNames,
  checkPaths,
  checkPins,
  checkSidecars,
  checkTestCounts,
  computePins,
  countAsserts,
  countTests,
  extractFunction,
  globToRegExp,
  groupKey,
  inferWs,
  LANE_PASS_LINE,
  LANE_SKIP_STRINGS,
  laneVerdict,
  listGutFiles,
  parseAddedLines,
  parsePlan,
  parseTestRemovals,
  planShards,
  readWeights,
  sha256Lf,
  touchedGames,
  weightsByGroup,
  wsPaths,
} from '../lib/gate_core.mjs';
import { REPO, rmQuiet } from './helpers.mjs';

const manifest = JSON.parse(fs.readFileSync(path.join(REPO, 'tools', 'lib', 'gate_manifest.json'), 'utf8'));

describe('globs', () => {
  test('** crosses /, * does not, {a,b} chooses', () => {
    assert.ok(globToRegExp('docs/games/**').test('docs/games/a/b.md'));
    assert.ok(!globToRegExp('docs/games/**').test('docs/games'));
    assert.ok(globToRegExp('tools/lib/gate*').test('tools/lib/gate_core.mjs'));
    assert.ok(!globToRegExp('tools/lib/gate*').test('tools/lib/gate/x.mjs'));
    assert.ok(globToRegExp('tests/games/*/perf/**').test('tests/games/tank/perf/test_x.gd'));
    assert.ok(!globToRegExp('tests/games/*/perf/**').test('tests/games/tank/rules/perf/test_x.gd'));
    assert.ok(globToRegExp('a/{b,c}.gd').test('a/c.gd'));
    assert.ok(!globToRegExp('a/{b,c}.gd').test('a/d.gd'));
    assert.ok(!globToRegExp('a.gd').test('axgd'), 'a dot is literal');
    assert.ok(globToRegExp('**').test('any/where.txt'));
    assert.ok(globToRegExp('**/x.gd').test('x.gd'));
  });
});

describe('listGutFiles and groupKey', () => {
  test('only test_*.gd holding a test function, sorted, forward slashes', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-list-'));
    try {
      const put = (rel, text) => {
        fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
        fs.writeFileSync(path.join(dir, rel), text);
      };
      put('tests/b/test_b.gd', 'func test_x():\n\tpass\n');
      put('tests/a/test_a.gd', '  func test_y():\n\tpass\n');
      put('tests/a/test_empty.gd', 'func helper():\n\tpass\n');
      put('tests/a/helper.gd', 'func test_z():\n\tpass\n');
      put('tests/.hidden/test_h.gd', 'func test_x():\n\tpass\n');
      assert.deepEqual(listGutFiles(dir), ['tests/a/test_a.gd', 'tests/b/test_b.gd']);
    } finally {
      rmQuiet(dir);
    }
  });

  test('groupKey', () => {
    assert.equal(groupKey('tests/games/tank/rules/test_x.gd'), 'tests/games/tank/rules');
    assert.equal(groupKey('tests/games/tank/rules/deep/test_x.gd'), 'tests/games/tank/rules');
    assert.equal(groupKey('tests/games/tank/test_x.gd'), 'tests/games/tank/(root)');
    assert.equal(groupKey('tests/core/integration/test_x.gd'), 'tests/core');
    assert.equal(groupKey('tests/app/test_x.gd'), 'tests/app');
    assert.equal(groupKey('tests/test_x.gd'), 'tests/(root)');
  });
});

describe('planShards', () => {
  const files = [
    'tests/app/test_a.gd',
    'tests/app/test_b.gd',
    'tests/core/test_c.gd',
    'tests/rides/test_d.gd',
    'tests/rides/test_e.gd',
    'tests/scenarios/test_f.gd',
    'tests/games/tank/rules/test_g.gd',
    'tests/games/tank/perf/test_h.gd',
    'tests/games/tank/test_i.gd',
  ].sort();
  const weights = { 'tests/app': 5, 'tests/core': 30, 'tests/rides': 10, 'tests/scenarios': 20, 'tests/games/tank/rules': 25, 'tests/games/tank/(root)': 1 };

  test('an exact partition', () => {
    const p = planShards(files, weights, { shards: 3 });
    assert.deepEqual([...p.shards.flat(), ...p.quiet].sort(), files);
    assert.equal(p.quiet.length, 0);
    assert.ok(p.shards.length <= 3);
  });

  test('a group never splits', () => {
    const p = planShards(files, {}, { shards: 8 });
    const shardOf = new Map();
    p.shards.forEach((s, i) => s.forEach((f) => {
      const g = groupKey(f);
      if (shardOf.has(g)) assert.equal(shardOf.get(g), i, g);
      shardOf.set(g, i);
    }));
  });

  test('longest group first into the lightest shard; files in a shard stay sorted', () => {
    const p = planShards(files, weights, { shards: 2, quiet: ['tests/games/*/perf/**'] });
    const load = p.shards.map((s) => [...new Set(s.map(groupKey))].reduce((sum, g) => sum + (weights[g] ?? 0), 0));
    assert.ok(Math.abs(load[0] - load[1]) <= 11, `balanced: ${load}`);
    assert.ok(p.shards[0].includes('tests/core/test_c.gd'), 'the heaviest group opens the first shard');
    for (const s of p.shards) assert.deepEqual(s, [...s].sort());
  });

  test('deterministic, ties by name, whatever the input order', () => {
    const a = planShards(files, {}, { shards: 3 });
    const b = planShards([...files].reverse().sort(), {}, { shards: 3 });
    assert.deepEqual(a, b);
    const c = planShards(['tests/z/test_a.gd', 'tests/y/test_a.gd'], {}, { shards: 2 });
    assert.deepEqual(c.shards, [['tests/y/test_a.gd'], ['tests/z/test_a.gd']]);
  });

  test('quiet tests come apart and never reach a shard', () => {
    const p = planShards(files, weights, { shards: 3, quiet: manifest.quiet_tests });
    assert.deepEqual(p.quiet, ['tests/games/tank/perf/test_h.gd']);
    assert.ok(!p.shards.flat().includes('tests/games/tank/perf/test_h.gd'));
    assert.deepEqual([...p.shards.flat(), ...p.quiet].sort(), files);
  });

  test('no weights: 2 s per file, so the bigger group goes first', () => {
    const fs3 = ['tests/big/test_1.gd', 'tests/big/test_2.gd', 'tests/big/test_3.gd', 'tests/mid/test_1.gd', 'tests/mid/test_2.gd', 'tests/small/test_1.gd'];
    const p = planShards(fs3, {}, { shards: 2 });
    assert.ok(p.shards[0].includes('tests/big/test_1.gd'));
    assert.ok(p.shards[1].includes('tests/mid/test_1.gd'));
    assert.ok(p.shards[1].includes('tests/small/test_1.gd'));
    assert.deepEqual(planShards(fs3, new Map([['tests/small', 100]]), { shards: 2 }).shards[0], ['tests/small/test_1.gd'], 'a Map works too');
  });

  test('pins force groups together', () => {
    const p = planShards(files, weights, { shards: 8, pins: [['tests/rides', 'tests/scenarios']] });
    const s = p.shards.find((x) => x.includes('tests/rides/test_d.gd'));
    assert.ok(s.includes('tests/scenarios/test_f.gd'));
    assert.deepEqual([...p.shards.flat()].sort(), files);
  });

  test('more shards than groups: no empty shard; a bad count throws', () => {
    assert.equal(planShards(['tests/a/test_a.gd'], {}, { shards: 8 }).shards.length, 1);
    assert.throws(() => planShards(files, {}, { shards: 0 }), /positive integer/);
  });

  test('duplicate input throws rather than running a file twice', () => {
    assert.throws(() => planShards(['tests/a/test_a.gd', 'tests/a/test_a.gd'], {}, { shards: 2 }), /planShards/);
  });

  test('the tracked weights cover the real groups, and the real plan is sound', () => {
    const real = listGutFiles(REPO);
    const weightsFile = JSON.parse(fs.readFileSync(path.join(REPO, 'tools', 'lib', 'gate_weights.json'), 'utf8'));
    const p = planShards(real, weightsFile, { shards: 8, quiet: manifest.quiet_tests, pins: manifest.shard_pins });
    assert.deepEqual([...p.shards.flat(), ...p.quiet].sort(), real);
    assert.ok(p.quiet.length >= 5, 'the wall-clock budget tests are quiet');
    for (const g of Object.keys(weightsFile)) assert.ok(Number.isFinite(weightsFile[g]), g);
    assert.equal(new Set(p.shards.flat().map(groupKey).filter((g) => g === 'tests/rides')).size, 1);
  });
});

describe('weights', () => {
  test('readWeights reads <testsuite name time>; weightsByGroup sums and sorts', () => {
    const xml = '<testsuites><testsuite name="tests/b/test_x.gd" tests="1" time="1.25" ></testsuite>'
      + '<testsuite name="tests/a/test_y.gd" tests="1" time="2" ></testsuite><testsuite name="tests/b/test_z.gd" time="0.5"></testsuite></testsuites>';
    const w = readWeights(xml);
    assert.equal(w.get('tests/b/test_x.gd'), 1.25);
    assert.deepEqual(weightsByGroup(w), { 'tests/a': 2, 'tests/b': 1.8 });
    assert.deepEqual(Object.keys(weightsByGroup(w)), ['tests/a', 'tests/b']);
    assert.equal(readWeights('').size, 0);
  });
});

describe('touchedGames', () => {
  const ids = ['fishing', 'siege', 'tank', 'workout'];

  test('a game alone', () => {
    assert.deepEqual(touchedGames(['src/games/tank/a.gd', 'tests/games/tank/test_a.gd', 'assets/tank/x.png', 'content/tank/y.json'], ids), { games: ['tank'], platform: false });
    assert.deepEqual(touchedGames(['.github/workflows/game-siege.yml', 'content/fishing/y.json'], ids), { games: ['fishing', 'siege'], platform: false });
  });

  test('the platform selects every game', () => {
    assert.deepEqual(touchedGames(['addons/wattlands/core/x.gd'], ids), { games: ids, platform: true });
    assert.deepEqual(touchedGames(['tools/lib/run_tests.mjs', 'src/games/tank/a.gd'], ids), { games: ids, platform: true });
  });

  test('docs, every .md and other workflows touch nothing', () => {
    assert.deepEqual(touchedGames(['docs/x.txt', 'README.md', 'src/games/tank/README.md', '.github/workflows/lead.yml'], ids), { games: [], platform: false });
    assert.deepEqual(touchedGames([], ids), { games: [], platform: false });
  });

  test('_template and an unregistered game are platform', () => {
    assert.equal(touchedGames(['src/games/_template/a.gd'], ids).platform, true);
    assert.equal(touchedGames(['src/games/newgame/a.gd'], ids).platform, true);
    assert.equal(touchedGames(['.github/workflows/game-nope.yml'], ids).platform, true);
    assert.deepEqual(touchedGames(['tests/games/_template/a.gd'], ids).games, ids);
  });
});

describe('aggregateGut', () => {
  const junit = (files, tests = 2) => `<testsuites name="GutTests" failures="0" tests="${tests}">${files.map((f) => `<testsuite name="${f}" tests="1" time="0.1"></testsuite>`).join('')}</testsuites>`;
  const shard = (name, files, { tests = 2, log = '= Run Summary\n', exitCode = 0, junitXml } = {}) => {
    const xml = junitXml ?? junit(files, tests);
    return { ...evaluateGut({ exitCode, log, junitXml: xml, previousGreen: null, minCount: 1, narrow: true }), name, junitXml: xml };
  };

  test('passes when exactly at the floor', () => {
    const v = aggregateGut([shard('gut:1', ['a.gd']), shard('gut:2', ['b.gd'], { tests: 3 })], { floor: 5, expectedFiles: ['a.gd', 'b.gd'] });
    assert.deepEqual(v, { pass: true, total: 5, reasons: [] });
  });

  test('a sum below the floor fails', () => {
    const v = aggregateGut([shard('gut:1', ['a.gd']), shard('gut:2', ['b.gd'], { tests: 2 })], { floor: 5, expectedFiles: ['a.gd', 'b.gd'] });
    assert.equal(v.pass, false);
    assert.equal(v.total, 4);
    assert.match(v.reasons.join(), /fewer than the floor 5/);
  });

  test('one shard with a pending test fails', () => {
    const bad = shard('gut:2', ['b.gd'], { log: '= Run Summary\nRisky/Pending   1\n' });
    const v = aggregateGut([shard('gut:1', ['a.gd']), bad], { floor: 1, expectedFiles: ['a.gd', 'b.gd'] });
    assert.equal(v.pass, false);
    assert.match(v.reasons.join(), /gut:2.*pending or risky/);
  });

  test('one shard with a FORBIDDEN line fails', () => {
    const v = aggregateGut([shard('gut:1', ['a.gd']), shard('gut:2', ['b.gd'], { log: '= Run Summary\nSCRIPT ERROR: boom\n' })], { expectedFiles: ['a.gd', 'b.gd'] });
    assert.equal(v.pass, false);
    assert.match(v.reasons.join(), /SCRIPT ERROR/);
  });

  test('a missing JUnit fails, naming the shard and its files', () => {
    const v = aggregateGut([shard('gut:1', ['a.gd']), shard('gut:2', [], { junitXml: '' })], { expectedFiles: ['a.gd', 'b.gd'] });
    assert.equal(v.pass, false);
    assert.match(v.reasons.join('\n'), /gut:2: .*no JUnit/);
    assert.match(v.reasons.join('\n'), /b\.gd is in no JUnit file/);
  });

  test('a file no JUnit names fails even with every shard green', () => {
    const v = aggregateGut([shard('gut:1', ['a.gd'])], { expectedFiles: ['a.gd', 'gone.gd'] });
    assert.equal(v.pass, false);
    assert.match(v.reasons.join(), /gone\.gd/);
  });

  test('a file in two JUnits fails, since it would pad the total', () => {
    const v = aggregateGut([shard('gut:1', ['a.gd']), shard('gut:2', ['a.gd'])], { expectedFiles: ['a.gd'] });
    assert.equal(v.pass, false);
    assert.match(v.reasons.join(), /both gut:1 and gut:2/);
  });

  test('no process at all fails; no floor means no floor rule', () => {
    assert.equal(aggregateGut([], {}).pass, false);
    assert.equal(aggregateGut([shard('gut:1', ['a.gd'])], { floor: null, expectedFiles: ['a.gd'] }).pass, true);
  });
});

describe('laneVerdict', () => {
  const summary = (rows, end = LANE_PASS_LINE) => `\nrun_tests summary\n  step  result  time     note\n${rows.map(([n, s]) => `  ${n}  ${s}    1.0s     note\n`).join('')}${end}\n`;

  test('exit 0, the pass line and a PASS row', () => {
    assert.equal(laneVerdict({ code: 0, text: summary([['gut', 'PASS']]), steps: ['gut'] }), 'PASS');
  });

  test('a non-zero exit fails whatever the text says', () => {
    assert.equal(laneVerdict({ code: 1, text: summary([['gut', 'PASS']]), steps: ['gut'] }), 'FAIL');
  });

  test('exit 0 without the pass line fails', () => {
    assert.equal(laneVerdict({ code: 0, text: summary([['gut', 'PASS']], 'run_tests: FAILED (gut)'), steps: ['gut'] }), 'FAIL');
    assert.equal(laneVerdict({ code: 0, text: '', steps: ['gut'] }), 'FAIL');
    assert.equal(laneVerdict({ code: 0, text: LANE_PASS_LINE, steps: ['gut'] }), 'FAIL', 'a pass line with no summary');
  });

  test('a SKIP row fails (a stray nested env), and a missing row', () => {
    assert.equal(laneVerdict({ code: 0, text: summary([['e2e', 'SKIP']]), steps: ['e2e'] }), 'FAIL');
    assert.equal(laneVerdict({ code: 0, text: summary([['gut', 'PASS']]), steps: ['static'] }), 'FAIL');
    assert.equal(laneVerdict({ code: 0, text: summary([['gut', 'FAIL']]), steps: ['gut'] }), 'FAIL');
  });

  test('other steps may SKIP; import may WARN; only import', () => {
    assert.equal(laneVerdict({ code: 0, text: summary([['import', 'SKIP'], ['gut', 'PASS']]), steps: ['gut'] }), 'PASS');
    assert.equal(laneVerdict({ code: 0, text: summary([['import', 'WARN']]), steps: ['import'] }), 'PASS');
    assert.equal(laneVerdict({ code: 0, text: summary([['gut', 'WARN']]), steps: ['gut'] }), 'FAIL');
  });

  test('each of the three "did not really run" strings fails', () => {
    assert.equal(LANE_SKIP_STRINGS.length, 3);
    for (const s of LANE_SKIP_STRINGS) {
      assert.equal(laneVerdict({ code: 0, text: `${s}\n${summary([['static', 'PASS']])}`, steps: ['static'] }), 'FAIL', s);
    }
  });

  test('a nested summary earlier in the text does not count: the last one decides', () => {
    const text = `${summary([['gut', 'PASS']])}${summary([['gut', 'FAIL']], 'run_tests: FAILED (gut)')}`;
    assert.equal(laneVerdict({ code: 0, text, steps: ['gut'] }), 'FAIL');
  });
});

describe('source scans', () => {
  test('countTests and countAsserts', () => {
    const src = 'func test_a():\n\tassert_eq(1, 2)\n\tassert_true(x)\n  func test_b():\n\tpass\n# func test_c():\nfunc helper_test_d():\n';
    assert.equal(countTests(src), 2);
    assert.equal(countAsserts(src), 2);
  });

  test('extractFunction: plain and export, up to the next ^}, CRLF normalised', () => {
    const src = 'const a = 1;\nexport function one(x) {\n  if (x) {\n  }\n}\nfunction two() {\r\n  return 2;\r\n}\r\n';
    assert.equal(extractFunction(src, 'one'), 'export function one(x) {\n  if (x) {\n  }\n}');
    assert.equal(extractFunction(src, 'two'), 'function two() {\n  return 2;\n}');
    assert.equal(extractFunction(src, 'three'), null);
    assert.equal(extractFunction('function on(x) {\n}\n', 'one'), null);
  });

  test('checkAppendOnly: adding passes; deleting, altering or reordering fails', () => {
    const pinned = ['a', 'b', 'c'];
    assert.deepEqual(checkAppendOnly(pinned, pinned), []);
    assert.deepEqual(checkAppendOnly(pinned, ['x', 'a', 'y', 'b', 'c', 'z']), []);
    assert.match(checkAppendOnly(pinned, ['a', 'c'])[0], /line 2 of 3.*b/);
    assert.equal(checkAppendOnly(pinned, ['a', 'B', 'c']).length, 1);
    assert.equal(checkAppendOnly(pinned, ['b', 'a', 'c']).length, 1);
    assert.equal(checkAppendOnly(['  x'], ['x']).length, 1, 'indentation counts');
  });

  test('sha256Lf ignores line endings only', () => {
    assert.equal(sha256Lf('a\r\nb\n'), sha256Lf('a\nb\n'));
    assert.notEqual(sha256Lf('a\nb\n'), sha256Lf('a\nb'));
  });
});

describe('checkPaths', () => {
  const change = (p, status = 'M') => ({ status, path: p });
  const paths = (ws, files, { commits = [], allow = [], lead = false } = {}) => checkPaths({ changes: files.map((f) => change(f)), commits, manifest, ws, allow, lead });

  test('every branch_ws row', () => {
    const rows = {
      'tooling/gate': 'gate',
      'audio/tank': 'audio',
      'cleanup/c3': 'cleanup',
      'docs/readme': 'docs',
      'wo/view': 'workout',
      'game/tank4-rules': 'tank',
      'game/tank-v4': 'tank',
      'game/workout-v2': 'workout',
      'game/siege-hud': 'siege',
      'game/fishing-x': 'fishing',
    };
    for (const [branch, ws] of Object.entries(rows)) assert.equal(inferWs(branch, manifest), ws, branch);
    assert.equal(inferWs('feature/x', manifest), null);
    assert.deepEqual([...new Set(manifest.branch_ws.map((r) => r[1]))].sort(), [...new Set(Object.values(rows))].sort(), 'this test covers every row');
  });

  test('E7: workstream gate owns its own fragments, not the lead\'s', () => {
    const gate = wsPaths(manifest, 'gate');
    assert.ok(gate.includes('docs/decisions/gate.md'));
    assert.ok(gate.includes('docs/changelog.d/gate.md'));
    assert.ok(!gate.includes('docs/decisions/lead.md'));
    assert.deepEqual(paths('gate', ['docs/decisions/gate.md', 'docs/changelog.d/gate.md', 'tools/gate', 'tools/lib/gate.mjs', 'tools/lib/run_tests.mjs']), []);
    assert.equal(paths('gate', ['docs/decisions/lead.md']).length, 1);
  });

  test('rule 1: never_edit and deny, passed only by --allow', () => {
    assert.match(paths('tank', ['docs/games/tank.md'])[0], /never edited/);
    assert.match(paths(null, ['.gitattributes'])[0], /never edited/);
    assert.match(paths(null, ['docs/BRIEF.md'], { lead: true })[0], /never edited/, 'not on a lead branch either');
    assert.deepEqual(paths('tank', ['docs/games/tank.md'], { allow: ['docs/games/**'] }), []);
    assert.match(paths('cleanup', ['addons/wattlands/trainer/control/x.gd'])[0], /denied/);
    assert.match(paths('cleanup', ['tests/governor/test_x.gd'])[0], /denied/);
    assert.match(paths('gate', ['tools/lib/safety_pins.json'])[0], /denied/);
    assert.deepEqual(paths('cleanup', ['src/app/x.gd']), []);
  });

  test('rule 2: lead_only, unless in also or allowed; a lead branch drops it', () => {
    assert.match(paths('tank', ['project.godot'])[0], /lead only/);
    assert.match(paths(null, ['tools/lib/run_tests.mjs'])[0], /lead only/);
    assert.match(paths('cleanup', ['README.md'])[0], /lead only/);
    assert.deepEqual(paths('audio', ['tools/lib/run_tests.mjs']), []);
    assert.deepEqual(paths('docs', ['README.md', 'CLAUDE.md']), []);
    assert.deepEqual(paths('tank', ['project.godot'], { allow: ['project.godot'] }), []);
    assert.deepEqual(paths(null, ['project.godot', 'tools/lib/run_tests.mjs'], { lead: true }), []);
  });

  test('rule 3: another game\'s path, unless in the ws\'s paths', () => {
    assert.match(paths('tank', ['src/games/siege/a.gd'])[0], /belongs to game siege/);
    assert.match(paths('tank', ['docs/decisions/fishing.md'])[0], /belongs to game fishing/);
    assert.match(paths('gate', ['content/workout/x.json'])[0], /belongs to game workout/);
    const noescape = checkPaths({ changes: [change('src/games/siege/a.gd')], commits: [{ sha: 'abc', subject: 'platform: x', paths: ['src/games/siege/a.gd'] }], manifest, ws: 'tank' });
    assert.equal(noescape.length, 1, 'a platform: subject does not open another game');
    assert.deepEqual(paths('audio', ['src/games/siege/audio/a.gd', 'tests/games/tank/audio/test_a.gd']), []);
    assert.deepEqual(paths('audio', ['docs/decisions/tank.md', 'docs/changelog.d/workout.md', 'docs/credits.d/siege.md']), [], 'EXECUTION_DAG 1: audio appends to these after the game lands');
    assert.match(paths('audio', ['docs/decisions/siege.md'])[0], /belongs to game siege/);
    assert.deepEqual(paths('tank', ['src/games/tank/a.gd', 'assets/tank/a.png', '.github/workflows/game-tank.yml', 'docs/credits.d/tank.md']), []);
  });

  test('rule 4: any other path needs a platform: commit that touches none of the game', () => {
    const file = 'addons/wattlands/core/x.gd';
    assert.match(paths('tank', [file])[0], /in no commit/, 'uncommitted');
    assert.match(paths('tank', [file], { commits: [{ sha: 'abcdef0123', subject: 'tank: x', paths: [file] }] })[0], /subject does not start/);
    assert.match(paths('tank', [file], { commits: [{ sha: 'abcdef0123', subject: 'platform: x', paths: [file, 'src/games/tank/a.gd'] }] })[0], /stands alone/);
    assert.deepEqual(paths('tank', [file], { commits: [{ sha: 'abcdef0123', subject: 'platform: x', paths: [file] }] }), []);
    const twoCommits = [{ sha: 'a'.repeat(9), subject: 'platform: x', paths: [file] }, { sha: 'b'.repeat(9), subject: 'tank: y', paths: [file] }];
    assert.equal(paths('tank', [file], { commits: twoCommits }).length, 1, 'every commit touching it must qualify');
  });

  test('ws-less: rules 1 and 2 only', () => {
    assert.deepEqual(paths(null, ['src/games/tank/a.gd', 'addons/wattlands/core/x.gd']), []);
  });

  test('a rename checks both paths', () => {
    const c = [{ status: 'R', oldPath: 'docs/games/a.md', path: 'src/games/tank/a.md' }];
    assert.match(checkPaths({ changes: c, commits: [], manifest, ws: 'tank' })[0], /docs\/games\/a\.md/);
  });
});

describe('checkPins', () => {
  const pins = (over = {}) => ({ globs: ['a/**', 'b.gd'], files: { 'a/x.gd': sha256Lf('x\n'), 'b.gd': sha256Lf('b\n') }, blocks: [], ...over });
  const tree = { 'a/x.gd': 'x\r\n', 'b.gd': 'b\n' };
  const read = (t) => (f) => t[f] ?? null;

  test('unchanged passes, LF-normalised', () => {
    assert.deepEqual(checkPins({ pins: pins(), read: read(tree) }), []);
  });

  test('a changed file, a gone file and a glob matching nothing fail', () => {
    assert.match(checkPins({ pins: pins(), read: read({ ...tree, 'b.gd': 'B\n' }) })[0], /b\.gd changed/);
    assert.match(checkPins({ pins: pins(), read: read({ 'a/x.gd': 'x\n' }) })[0], /b\.gd is gone/);
    assert.match(checkPins({ pins: pins({ globs: ['nope/**'] }), read: read(tree) })[0], /nope\/\*\* matches nothing/);
  });

  const check = 'export function checkS4(r) {\n  const a = 1;\n\n  if (r < 55) bad();\n}\n';
  const blocks = [{ file: 'c.mjs', function: 'checkS4', lines: ['export function checkS4(r) {', '  const a = 1;', '  if (r < 55) bad();', '}'] }];

  test('blocks: adding passes, altering a threshold fails, --allow-pin excuses that one', () => {
    const p = { blocks };
    assert.deepEqual(checkPins({ pins: p, read: read({ 'c.mjs': check }) }), []);
    const more = check.replace('  const a = 1;', '  const a = 1;\n  if (kind === 2) return;');
    assert.deepEqual(checkPins({ pins: p, read: read({ 'c.mjs': more }) }), []);
    const weak = check.replace('55', '40');
    assert.match(checkPins({ pins: p, read: read({ 'c.mjs': weak }) })[0], /checkS4.*r < 55/);
    assert.deepEqual(checkPins({ pins: p, read: read({ 'c.mjs': weak }), allowPins: ['c.mjs:checkS4'] }), []);
    assert.match(checkPins({ pins: p, read: read({ 'c.mjs': 'export function other() {\n}\n' }) })[0], /checkS4 is gone/);
    assert.match(checkPins({ pins: p, read: read({}) })[0], /c\.mjs is gone/);
  });

  test('computePins expands the globs and refuses what finds nothing', () => {
    const t = { 'a/x.gd': 'x\n', 'a/y.gd': 'y\n', 'c.mjs': check };
    const got = computePins({ globs: ['a/**'], appendOnly: { 'c.mjs': ['checkS4'] }, tracked: Object.keys(t), read: read(t) });
    assert.deepEqual(Object.keys(got.files), ['a/x.gd', 'a/y.gd']);
    assert.deepEqual(got.blocks, blocks);
    assert.deepEqual(checkPins({ pins: got, read: read(t) }), []);
    assert.throws(() => computePins({ globs: ['z/**'], tracked: Object.keys(t), read: read(t) }), /matches nothing/);
    assert.throws(() => computePins({ globs: [], appendOnly: { 'c.mjs': ['nope'] }, tracked: [], read: read(t) }), /no function nope/);
    assert.throws(() => computePins({ globs: [], appendOnly: { 'gone.mjs': ['x'] }, tracked: [], read: read(t) }), /does not exist/);
  });

  test('the real manifest pins what SPEC_GATES 6.2 and 6.3 name', () => {
    for (const glob of ['tests/governor/**', 'tests/control/**', 'tests/arch/test_no_bypass.gd', 'tools/e2e/lib/checks.mjs', 'tools/lib/godot_lock.mjs', 'tools/run_game_sim', 'gdlintrc']) {
      assert.ok(manifest.safety_pin_globs.includes(glob), glob);
    }
    assert.ok(globToRegExp(manifest.safety_pin_globs[0]).test('addons/wattlands/trainer/control/governor_clamps.gd'));
    assert.deepEqual(manifest.append_only_pins['tests/games/fishing/sim/check_sims.mjs'], ['checkAll']);
    assert.ok(manifest.append_only_pins['tests/games/tank/sim/check_sims.mjs'].includes('checkS4'));
    assert.ok(manifest.append_only_pins['tests/games/siege/sim/check_sims.mjs'].includes('checkS6'));
  });
});

describe('checkTestCounts', () => {
  const t = (n) => 'func test_x():\n\tassert_eq(a, b)\n'.repeat(n);

  test('more tests pass with nothing to say', () => {
    assert.deepEqual(checkTestCounts({ baseFiles: { 'tests/a/test_a.gd': t(1) }, headFiles: { 'tests/a/test_a.gd': t(2) } }), { problems: [], notes: [] });
  });

  test('a falling total fails, and no trailer excuses it', () => {
    const v = checkTestCounts({ baseFiles: { 'tests/a/test_a.gd': t(2) }, headFiles: { 'tests/a/test_a.gd': t(1) }, trailers: [{ area: 'tests/a', reason: 'gone' }] });
    assert.match(v.problems.join(), /total fell 2 -> 1/);
    assert.match(v.notes.join(), /tests\/a\/test_a\.gd lost tests: 2 -> 1/);
  });

  test('a falling area needs its trailer, even when the total holds', () => {
    const base = { 'tests/a/test_a.gd': t(2), 'tests/games/tank/rules/test_b.gd': t(1) };
    const head = { 'tests/a/test_a.gd': t(1), 'tests/games/tank/rules/test_b.gd': t(2) };
    assert.match(checkTestCounts({ baseFiles: base, headFiles: head }).problems.join(), /tests\/a fell 2 -> 1 with no "Test-Removal: tests\/a/);
    const ok = checkTestCounts({ baseFiles: base, headFiles: head, trailers: [{ area: 'tests/a', reason: 'rear logic went' }] });
    assert.deepEqual(ok.problems, []);
    assert.match(ok.notes.join(), /rear logic went/);
    const other = checkTestCounts({ baseFiles: base, headFiles: head, trailers: [{ area: 'tests/b', reason: 'x' }] });
    assert.equal(other.problems.length, 1, "another area's trailer does not count");
    const games = checkTestCounts({ baseFiles: { 'tests/games/tank/a/test_a.gd': t(2), 'tests/b/test_b.gd': t(1) }, headFiles: { 'tests/games/tank/a/test_a.gd': t(1), 'tests/b/test_b.gd': t(2) } });
    assert.match(games.problems.join(), /tests\/games\/tank fell/);
  });

  test('a deleted file counts; a merge revert is excused and noted', () => {
    const v = checkTestCounts({ baseFiles: { 'tests/a/test_a.gd': t(1) }, headFiles: {} });
    assert.equal(v.problems.length, 2);
    const r = checkTestCounts({ baseFiles: { 'tests/a/test_a.gd': t(1) }, headFiles: {}, revertOnly: true });
    assert.deepEqual(r.problems, []);
    assert.match(r.notes.join(), /merge revert/);
  });

  test('asserts falling over 10 % is only a note', () => {
    const a = 'func test_x():\n' + '\tassert_eq(a, b)\n'.repeat(10);
    const b = 'func test_x():\n' + '\tassert_eq(a, b)\n'.repeat(5);
    const v = checkTestCounts({ baseFiles: { 'tests/a/test_a.gd': a }, headFiles: { 'tests/a/test_a.gd': b } });
    assert.deepEqual(v.problems, []);
    assert.match(v.notes.join(), /asserts fell over 10 %: 10 -> 5/);
  });

  test('parseTestRemovals reads trailers, and needs a reason', () => {
    assert.deepEqual(parseTestRemovals('subject\n\nbody\n\nTest-Removal: tests/games/tank rear logic went\nCo-Authored-By: x\n'), [{ area: 'tests/games/tank', reason: 'rear logic went' }]);
    assert.deepEqual(parseTestRemovals('Test-Removal: tests/a\n'), []);
  });
});

describe('added text', () => {
  const FLAG_HW = `--allow-${'hw'}`;
  const FLAG_NET = `--allow-${'network'}`;
  const problemsFor = (file, line) => checkAddedText({ added: new Map([[file, [line]]]), quietTests: manifest.quiet_tests });

  test('parseAddedLines takes only added lines per file, a CR stays, a "++" line is content', () => {
    const diff = [
      'diff --git a/x.gd b/x.gd',
      '--- a/x.gd',
      '+++ b/x.gd',
      '@@ -1,2 +1,3 @@',
      '-old',
      '-old2',
      '+new\r',
      '+++ not a header',
      '+--- nor this',
      'diff --git a/gone.gd b/gone.gd',
      '--- a/gone.gd',
      '+++ /dev/null',
      '@@ -1 +0,0 @@',
      '-bye',
      'diff --git a/y.gd b/y.gd',
      '--- /dev/null',
      '+++ b/y.gd',
      '@@ -0,0 +1 @@',
      '+hello',
      '\\ No newline at end of file',
    ].join('\n');
    const added = parseAddedLines(diff);
    assert.deepEqual([...added.keys()], ['x.gd', 'y.gd']);
    assert.deepEqual(added.get('x.gd'), ['new\r', '++ not a header', '--- nor this']);
    assert.deepEqual(added.get('y.gd'), ['hello']);
  });

  test('the hardware and network flags, in code only, outside the gate and its tests', () => {
    for (const file of ['tools/x.mjs', 'a.sh', 'a.ps1', 'a.py', 'src/a.gd', '.github/workflows/a.yml', 'tools/new_tool']) {
      assert.equal(problemsFor(file, `run ${FLAG_HW}`).length, 1, file);
      assert.equal(problemsFor(file, `run ${FLAG_NET}`).length, 1, file);
    }
    for (const file of ['src/games/tank/HARDWARE_TEST.md', 'CLAUDE.md', 'tools/tests/a.mjs', 'tools/e2e/test/a.mjs', 'tools/lib/gate.mjs', 'tools/lib/gate_core.mjs']) {
      assert.deepEqual(problemsFor(file, `run ${FLAG_HW}`), [], file);
    }
  });

  test('the art variables, also outside tools/art', () => {
    const art = `WATTLANDS_ALLOW_ART=${1}`;
    const key = `FAL_${'KEY'}=abc`;
    assert.equal(problemsFor('tools/x.mjs', art).length, 1);
    assert.equal(problemsFor('tools/x.mjs', key).length, 1);
    assert.deepEqual(problemsFor('tools/art/generate.mjs', key), []);
    assert.deepEqual(problemsFor('docs/x.md', key), []);
    assert.deepEqual(problemsFor('tools/x.mjs', 'const FAL_KEY = 1;'), []);
  });

  test('empty asserts in tests/**.gd only', () => {
    assert.equal(problemsFor('tests/a/test_a.gd', '\tassert_true(true)').length, 1);
    assert.equal(problemsFor('tests/a/test_a.gd', '\tassert_eq(1, 1)').length, 1);
    assert.equal(problemsFor('tests/a/test_a.gd', '\tassert_eq(1,1)').length, 1);
    assert.deepEqual(problemsFor('tests/a/test_a.gd', '\tassert_true(true_value())').length, 1, 'errs on the strict side');
    assert.deepEqual(problemsFor('tests/a/test_a.gd', '\tassert_eq(10, x)'), []);
    assert.deepEqual(problemsFor('tools/tests/a.mjs', 'assert_true(true)'), []);
  });

  test('wall-clock budgets in quiet_tests only', () => {
    const line = '\tvar t := Time.get_ticks_usec()';
    assert.equal(problemsFor('tests/games/tank/rules/test_a.gd', line).length, 1);
    assert.deepEqual(problemsFor('tests/games/tank/perf/test_a.gd', line), []);
    assert.deepEqual(problemsFor('tests/games/tank/rules/test_tank_determinism.gd', line), []);
    assert.deepEqual(problemsFor('src/games/tank/a.gd', line), []);
  });

  test('CR, except .ps1 .bat .cmd, and never on untracked files (.gitattributes normalises them)', () => {
    assert.equal(problemsFor('src/a.gd', 'x\r').length, 1);
    assert.deepEqual(problemsFor('src/a.gd', 'x'), []);
    assert.deepEqual(problemsFor('a.ps1', 'x\r'), []);
    assert.deepEqual(problemsFor('a.bat', 'x\r'), []);
    assert.deepEqual(problemsFor('a.cmd', 'x\r'), []);
    assert.deepEqual(checkAddedText({ added: new Map(), untracked: new Map([['src/a.gd', ['x\r']]]) }), []);
    assert.equal(checkAddedText({ added: new Map(), untracked: new Map([['tools/a.mjs', [`x ${FLAG_HW}`]]]) }).length, 1, 'other rules do read untracked files');
  });
});

describe('checkSidecars', () => {
  const run = (added, deleted, current) => checkSidecars({ added, deleted, current });

  test('.gd needs .gd.uid, media needs .import', () => {
    assert.match(run(['src/a.gd'], [], ['src/a.gd'])[0], /without src\/a\.gd\.uid/);
    assert.deepEqual(run(['src/a.gd', 'src/a.gd.uid'], [], ['src/a.gd', 'src/a.gd.uid']), []);
    for (const ext of ['png', 'wav', 'ogg', 'ttf', 'mp3']) {
      assert.match(run([`a/b.${ext}`], [], [`a/b.${ext}`])[0], /\.import/, ext);
      assert.deepEqual(run([`a/b.${ext}`], [], [`a/b.${ext}`, `a/b.${ext}.import`]), [], ext);
    }
    assert.deepEqual(run(['a/b.txt'], [], ['a/b.txt']), []);
  });

  test('under a tracked .gdignore or a hidden dir nothing is needed', () => {
    assert.deepEqual(run(['assets/tank/v4/tools_src/a.gd'], [], ['assets/tank/v4/tools_src/a.gd', 'assets/tank/v4/tools_src/.gdignore']), []);
    assert.deepEqual(run(['assets/tank/v4/tools_src/deep/a.png'], [], ['assets/tank/v4/tools_src/deep/a.png', 'assets/.gdignore']), []);
    assert.deepEqual(run(['.claude/a.png'], [], ['.claude/a.png']), []);
    assert.equal(run(['assets/x/a.gd'], [], ['assets/x/a.gd', 'assets/y/.gdignore']).length, 1, "a sibling's .gdignore does not count");
  });

  test('a new sidecar needs its source; a deleted source takes its sidecar', () => {
    assert.match(run(['a/b.gd.uid'], [], ['a/b.gd.uid'])[0], /added with no a\/b\.gd/);
    assert.match(run(['a/b.png.import'], [], ['a/b.png.import'])[0], /added with no a\/b\.png/);
    assert.match(run([], ['a/b.gd'], ['a/b.gd.uid'])[0], /deleted but a\/b\.gd\.uid stays/);
    assert.match(run([], ['a/b.png'], ['a/b.png.import'])[0], /deleted but a\/b\.png\.import stays/);
    assert.deepEqual(run([], ['a/b.gd', 'a/b.gd.uid'], []), []);
    assert.deepEqual(run([], ['a/b.gd'], ['a/b.gd', 'a/b.gd.uid']), [], 'put back later in the same diff');
  });

  test('this diff only: an old orphan is not read', () => {
    assert.deepEqual(run(['src/a.gd', 'src/a.gd.uid'], [], ['src/a.gd', 'src/a.gd.uid', 'old/orphan.gd.uid']), []);
  });
});

describe('checkClassNames', () => {
  test('a name in two files fails; one file twice and different names pass', () => {
    assert.deepEqual(checkClassNames(['a.gd:1:class_name Foo', 'b.gd:3:class_name Bar extends Node']), []);
    assert.match(checkClassNames(['a.gd:1:class_name Foo', 'b.gd:3:class_name Foo extends Node'])[0], /Foo is declared in a\.gd, b\.gd/);
  });
});

describe('parsePlan', () => {
  test('arguments round-trip, and the first line per --report wins', () => {
    const line = (...a) => `${a.join('\x1f')}\x1f`;
    const text = [line('--game=x', '--rider=a b', '--report=r/a.json'), line('--game=x', '--report=r/b.json', '--options={"a":1}'), line('--game=x', '--seed=9', '--report=r/a.json'), ''].join('\n');
    assert.deepEqual(parsePlan(text), [['--game=x', '--rider=a b', '--report=r/a.json'], ['--game=x', '--report=r/b.json', '--options={"a":1}']]);
    assert.deepEqual(parsePlan(''), []);
  });
});
