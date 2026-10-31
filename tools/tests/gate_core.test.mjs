// Tests for tools/lib/gate_core.mjs: shards, touched games, the merged GUT verdict, the lane verdict and
// the pure rules of `tools/gate check`. No git, no Godot, no process starts.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { evaluateGut } from '../lib/gut_gate.mjs';
import {
  aggregateGut,
  checkNodeTestCounts,
  checkPinContent,
  countNodeTests,
  junitCountProblems,
  junitTestsByFile,
  matrixRule,
  revertedSha,
  checkAddedText,
  checkAppendOnly,
  checkClassNames,
  checkerEvidence,
  checkPaths,
  checkPinCoverage,
  checkPinnedBody,
  checkPinnedConst,
  checkPins,
  checkSidecars,
  checkTestCounts,
  computePins,
  countAsserts,
  countTests,
  extractConst,
  extractFunction,
  failingCases,
  fastNarrowing,
  globToRegExp,
  groupKey,
  inferWs,
  isBudgetTest,
  isGutFile,
  junitCoverage,
  LANE_PASS_LINE,
  LANE_SKIP_STRINGS,
  laneVerdict,
  listGutFiles,
  maskConsts,
  parseAddedLines,
  parsePlan,
  parseTestRemovals,
  pinClosure,
  pinSpecOf,
  planShards,
  quietRetryPlan,
  readWeights,
  sha256Lf,
  touchedGames,
  weightsByGroup,
  wsPaths,
} from '../lib/gate_core.mjs';
import { GIT, REPO, rmQuiet } from './helpers.mjs';

const manifest = JSON.parse(fs.readFileSync(path.join(REPO, 'tools', 'lib', 'gate_manifest.json'), 'utf8'));

const matchesLeadOnly = (f) => manifest.lead_only.some((g) => globToRegExp(g).test(f));

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

  test('isGutFile: what GUT collects, and nothing a rename can hide in', () => {
    for (const f of ['tests/a/test_a.gd', 'tests/test_a.gd', 'tests/games/tank/rules/test_x.gd']) assert.ok(isGutFile(f), f);
    for (const f of ['tests/a/a_checks.gd', 'tests/a/test_a.txt', 'tests/.hidden/test_a.gd', 'src/test_a.gd', 'tests/a/test_a.gd.uid']) assert.ok(!isGutFile(f), f);
  });

  test('no tests/ is an empty list, not an error', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-list-'));
    try {
      assert.deepEqual(listGutFiles(dir), []);
      assert.deepEqual(planShards([], {}, { shards: 8 }), { shards: [], quiet: [] });
      assert.match(aggregateGut([], { expectedFiles: [] }).reasons[0], /no GUT process ran/);
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

describe('JUnit counts against the source', () => {
  const xml = '<testsuites><testsuite name="tests/a/test_a.gd" tests="2" time="1">\n<testcase name="x"></testcase></testsuite>\n'
    + '<testsuite name="tests/a/test_i.gd" tests="1"></testsuite><testsuite name="tests/a/test_i.gd.TestInner" tests="2"></testsuite>'
    + '<testsuite name="tests/a/test_n.gd"><testcase name="a"></testcase><testcase name="b"></testcase></testsuite></testsuites>';

  test('junitTestsByFile: the attribute, else the testcases; inner classes count for their file', () => {
    assert.deepEqual([...junitTestsByFile(xml)], [['tests/a/test_a.gd', 2], ['tests/a/test_i.gd', 3], ['tests/a/test_n.gd', 2]]);
  });

  test('below the source is a problem; equal, above and absent are not', () => {
    assert.deepEqual(junitCountProblems([xml], { 'tests/a/test_a.gd': 2, 'tests/a/test_i.gd': 2, 'tests/a/gone.gd': 9 }), []);
    assert.match(junitCountProblems([xml], { 'tests/a/test_a.gd': 3 })[0], /test_a\.gd: the JUnit holds 2 tests, the source 3/);
  });

  test('a file split over shards adds up', () => {
    const one = '<testsuite name="a.gd" tests="1"></testsuite>';
    assert.deepEqual(junitCountProblems([one, one], { 'a.gd': 2 }), []);
  });

  test('countNodeTests counts test( and it(, not test.skip( or a word in a string', () => {
    assert.equal(countNodeTests("test('a', f);\n  it('b', f);\ntest.skip('c', f);\nconst latest = 'test(';\n"), 2);
  });

  test('revertedSha reads the line git revert writes', () => {
    assert.equal(revertedSha('Revert "Merge x"\n\nThis reverts commit abc1234, reversing changes made to def.\n'), 'abc1234');
    assert.equal(revertedSha('Revert "Merge x"\n'), null);
  });

  test('matrixRule: null for a game the manifest does not name; floors for one it does', () => {
    const m = { matrix_required_rows: { a: ['S1'] }, matrix_min_runs: { a: 3, b: 2 } };
    assert.equal(matrixRule(m, 'c'), null);
    assert.deepEqual(matrixRule(m, 'a'), { rows: ['S1'], minRuns: 3 });
    assert.deepEqual(matrixRule(m, 'b'), { rows: [], minRuns: 2 });
  });
});

describe('checkNodeTestCounts', () => {
  const suiteOf = (f) => f.split('/')[0];
  const t = (n) => "test('x', f);\n".repeat(n);

  test('a total held or risen passes; a fall needs the trailer or a merge revert', () => {
    assert.deepEqual(checkNodeTestCounts({ baseFiles: { 'a/x': t(1) }, headFiles: { 'a/x': t(2) }, suiteOf }).problems, []);
    assert.match(checkNodeTestCounts({ baseFiles: { 'a/x': t(2) }, headFiles: { 'a/x': t(1) }, suiteOf }).problems[0], /Node total fell 2 -> 1/);
    assert.deepEqual(checkNodeTestCounts({ baseFiles: { 'a/x': t(2) }, headFiles: { 'a/x': t(1) }, suiteOf, trailers: [{ area: 'node', reason: 'r' }] }).problems, []);
    assert.deepEqual(checkNodeTestCounts({ baseFiles: { 'a/x': t(2) }, headFiles: {}, suiteOf, revertOnly: true }).problems, []);
  });

  test('an emptied suite fails though the total holds; its own trailer excuses it', () => {
    const args = { baseFiles: { 'a/x': t(1), 'b/x': t(1) }, headFiles: { 'a/x': t(2) }, suiteOf };
    assert.match(checkNodeTestCounts(args).problems[0], /Node suite b held 1 tests and holds none/);
    assert.deepEqual(checkNodeTestCounts({ ...args, trailers: [{ area: 'b', reason: 'r' }] }).problems, []);
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

  test('a file whose JUnit count is below its source fails', () => {
    const xml = '<testsuites failures="0" tests="1"><testsuite name="a.gd" tests="1"></testsuite></testsuites>';
    const shard = { ...evaluateGut({ exitCode: 0, log: '= Run Summary\n', junitXml: xml, previousGreen: null, minCount: 1, narrow: true }), name: 'gut:1', junitXml: xml };
    assert.equal(aggregateGut([shard], { expectedFiles: ['a.gd'], sourceCounts: { 'a.gd': 1 } }).pass, true);
    const v = aggregateGut([shard], { expectedFiles: ['a.gd'], sourceCounts: { 'a.gd': 2 } });
    assert.equal(v.pass, false);
    assert.match(v.reasons.join(), /a\.gd: the JUnit holds 1 tests, the source 2/);
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

describe('JUnit reads', () => {
  const xml = '<testsuites failures="2" tests="4"><testsuite name="tests/a/test_a.gd" tests="4" failures="2">'
    + '<testcase name="test_ok" assertions="1" status="pass" classname="tests/a/test_a.gd" time="0.1" ></testcase>'
    + '<testcase name="test_bad" assertions="1" status="fail" classname="tests/a/test_a.gd" time="0.1" ><failure message="failed"><![CDATA[x]]></failure></testcase>'
    + '<testcase name="test_also" assertions="1" status="fail" classname="tests/b/test_b.gd" time="0.1" ></testcase>'
    + '</testsuite></testsuites>';

  test('failingCases finds what failed, by status or by a failure child', () => {
    assert.deepEqual(failingCases(xml), [{ file: 'tests/a/test_a.gd', name: 'test_bad' }, { file: 'tests/b/test_b.gd', name: 'test_also' }]);
    assert.deepEqual(failingCases(''), []);
  });

  test('junitCoverage names the files GUT did not run', () => {
    assert.deepEqual(junitCoverage(xml, ['tests/a/test_a.gd']), []);
    assert.deepEqual(junitCoverage(xml, ['tests/a/test_a.gd', 'tests/b/test_c.gd']), ['tests/b/test_c.gd is in no JUnit suite']);
    assert.equal(junitCoverage('', ['tests/a/test_a.gd']).length, 1);
  });

  test('evaluateGut reads the failure count: exit 0 and a summary do not excuse it', () => {
    const v = evaluateGut({ exitCode: 0, log: '= Run Summary\n', junitXml: '<testsuites failures="3" tests="5"></testsuites>', narrow: true });
    assert.equal(v.pass, false);
    assert.deepEqual(v.reasons, ['JUnit reports 3 failed tests']);
    assert.equal(evaluateGut({ exitCode: 0, log: '= Run Summary\n', junitXml: '<testsuites failures="0" tests="5"></testsuites>', narrow: true }).pass, true);
  });
});

describe('the quiet rerun is for budgets only', () => {
  const src = [
    'extends GutTest',
    '',
    'const LIMIT := 3',
    '',
    'func _mean_us() -> float:',
    '\tvar t0 := Time.get_ticks_usec()',
    '\treturn float(Time.get_ticks_usec() - t0)',
    '',
    'func _other() -> int:',
    '\treturn 1',
    '',
    'func test_direct() -> void:',
    '\tvar t0 := Time.get_ticks_usec()',
    '\tassert_lt(t0, 9)',
    '',
    'func test_through_a_helper() -> void:',
    '\tassert_lt(_mean_us(), 9.0)',
    '',
    'func test_determinism() -> void:',
    '\tassert_eq(_other(), 1)',
    '',
  ].join('\n');
  const failing = (...names) => `<testsuites failures="${names.length}" tests="9">${names.map((n) => `<testcase name="${n}" status="fail" classname="f.gd" ><failure/></testcase>`).join('')}</testsuites>`;
  const plan = (reasons, ...names) => quietRetryPlan({ reasons, junitXml: failing(...names), read: () => src });

  test('isBudgetTest sees wall time in the test and through its helpers', () => {
    assert.equal(isBudgetTest(src, 'test_direct'), true);
    assert.equal(isBudgetTest(src, 'test_through_a_helper'), true);
    assert.equal(isBudgetTest(src, 'test_determinism'), false);
    assert.equal(isBudgetTest(src, 'test_gone'), false);
  });

  test('budget tests alone may rerun', () => {
    const p = plan(['GUT exit code 1', 'JUnit reports 2 failed tests'], 'test_direct', 'test_through_a_helper');
    assert.equal(p.allowed, true);
    assert.deepEqual(p.tests, ['f.gd::test_direct', 'f.gd::test_through_a_helper']);
  });

  test('one test in the failure that is no budget keeps the first verdict', () => {
    const p = plan(['GUT exit code 1'], 'test_direct', 'test_determinism');
    assert.equal(p.allowed, false);
    assert.match(p.why, /not a budget test: f\.gd::test_determinism/);
  });

  test('a FORBIDDEN string, a crash or no summary never reruns, even on a budget test', () => {
    for (const reason of ['log contains "SCRIPT ERROR"', 'log contains "Parse Error"', 'log has no "Run Summary"', 'no JUnit test count (missing or empty JUnit file)', '1 pending or risky test(s)']) {
      assert.equal(plan(['GUT exit code 1', reason], 'test_direct').allowed, false, reason);
    }
  });

  test('a non-zero exit with no failed testcase is a crash', () => {
    assert.equal(plan(['GUT exit code 139']).allowed, false);
  });

  test('an exit code other than 1 is a crash, even with a failed budget test', () => {
    for (const code of [3221225477, 139, 124, 2]) {
      assert.equal(plan([`GUT exit code ${code}`, 'JUnit reports 1 failed test'], 'test_direct').allowed, false, String(code));
    }
    assert.equal(plan(['GUT exit code 1', 'JUnit reports 1 failed test'], 'test_direct').allowed, true);
  });
});

describe('checkerEvidence', () => {
  const ev = (text, over = {}) => checkerEvidence({ code: 0, text, ...over });

  test('real rows of the three checkers pass', () => {
    assert.equal(ev('PASS S4 every content\nPASS S5 rescue\ncheck_sims: 2 checks, 0 failed\n', { required: ['S4', 'S5'] }).pass, true);
    assert.equal(ev('PASS S4  short\n    - detail\ncheck_sims: 1 passed\n').rows, 1);
    assert.equal(ev('PASS ALL  every run\nPASS R1   x\n', { required: ['ALL'] }).pass, true);
  });

  test('exit 0 with no rows is no evidence', () => {
    const v = ev('');
    assert.equal(v.pass, false);
    assert.match(v.reasons.join(), /did not run/);
    assert.equal(ev('run_sims: all runs recorded\n').pass, false);
  });

  test('a FAIL row, a non-zero exit and a missing or skipped safety row fail', () => {
    assert.match(ev('PASS S1 a\nFAIL S4 b\n').reasons.join(), /FAIL rows: S4/);
    assert.match(checkerEvidence({ code: 1, text: 'PASS S1 a\n' }).reasons.join(), /exited 1/);
    assert.match(ev('PASS S1 a\n', { required: ['S4'] }).reasons.join(), /required row S4 is missing/);
    assert.match(ev('PASS S1 a\nSKIP S4 b\n', { required: ['S4'] }).reasons.join(), /required row S4 is SKIP/);
  });

  test('a SKIP row fails a full matrix, and only a full one', () => {
    assert.match(ev('PASS S1 a\nSKIP S2 no reports\n').reasons.join(), /SKIP rows in a full matrix: S2/);
    assert.equal(ev('PASS S1 a\nSKIP S2 no reports\n', { partial: true, required: ['S4'] }).pass, true);
  });
});

describe('fastNarrowing', () => {
  const clean = { baseSha: 'a', mainSha: 'a', ws: null, inferredWs: 'tank', games: ['tank'], requiredGames: ['tank'] };

  test('the default run, and a wider one, narrow nothing', () => {
    assert.deepEqual(fastNarrowing(clean), []);
    assert.deepEqual(fastNarrowing({ ...clean, games: ['fishing', 'siege', 'tank'] }), [], '--games=all');
    assert.deepEqual(fastNarrowing({ ...clean, ws: 'tank' }), [], 'the branch ws said out loud');
    assert.deepEqual(fastNarrowing({ ...clean, base: 'origin/main', baseSha: 'a' }), [], 'another name for main');
    assert.deepEqual(fastNarrowing({ ...clean, games: [], requiredGames: [] }), [], 'a docs-only branch');
  });

  test('each way to narrow a fast is named', () => {
    const one = (over, re) => {
      const v = fastNarrowing({ ...clean, ...over });
      assert.equal(v.length, 1, JSON.stringify(v));
      assert.match(v[0], re);
    };
    one({ lanes: ['gut'] }, /--lanes=gut/);
    one({ base: 'HEAD', baseSha: 'b' }, /--base=HEAD is not main/);
    one({ mainSha: null }, /is not main/);
    one({ ws: 'cleanup' }, /--ws=cleanup is not the branch's workstream \(tank\)/);
    one({ ws: 'audio', inferredWs: null }, /--ws=audio/);
    one({ allow: ['**'] }, /--allow=\*\*/);
    one({ allowPin: ['a.mjs:f'] }, /--allow-pin=a\.mjs:f/);
    one({ games: ['fishing'], requiredGames: ['fishing', 'siege', 'tank'] }, /--games leaves out siege,tank/);
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

  test('extractConst: one line, several lines, absent', () => {
    const src = 'const A = 1;\nexport const B = {\n  x: 1,\n};\nconst ABC = 2;\n';
    assert.equal(extractConst(src, 'A'), 'const A = 1;');
    assert.equal(extractConst(src, 'B'), 'export const B = {\n  x: 1,\n};');
    assert.equal(extractConst(src, 'C'), null);
    assert.equal(extractConst(src, 'ABC'), 'const ABC = 2;');
  });

  test('pinClosure follows functions and arrows, not tables', () => {
    const src = [
      'const LIMIT = 5;',
      'const UNUSED = 6;',
      'const num = (v) => Number(v) + BASE;',
      'const BASE = 0;',
      'function helper(x) {',
      '  return num(x) < LIMIT;',
      '}',
      'function other() {',
      '  return UNUSED;',
      '}',
      'export function root() {',
      '  return helper(1) && TABLE.a;',
      '}',
      'export const TABLE = { a: other };',
      '',
    ].join('\n');
    assert.deepEqual(pinClosure(src, ['root']), { functions: ['helper', 'root'], consts: ['LIMIT', 'num', 'BASE', 'TABLE'] });
  });

  test('maskConsts removes the statement and nothing else', () => {
    const a = "const S = ['a'];\nconst K = 1;\n";
    assert.equal(maskConsts(a, ['S']), '\nconst K = 1;\n');
    assert.equal(maskConsts(a), a);
    assert.equal(sha256Lf(maskConsts("const S = ['a', 'b'];\nconst K = 1;\n", ['S'])), sha256Lf(maskConsts(a, ['S'])));
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

  test('a pins file that pins nothing is a problem', () => {
    assert.match(checkPins({ pins: {} })[0], /pins nothing/);
    assert.match(checkPins({ pins: { files: {}, blocks: [] }, read: read(tree) })[0], /pins nothing/);
  });

  test('a masked const may change, the rest of its file may not', () => {
    const text = "const S = ['a'];\nconst K = 1;\n";
    const p = { files: { 'r.mjs': sha256Lf(maskConsts(text, ['S'])) }, masked: { 'r.mjs': ['S'] } };
    assert.deepEqual(checkPins({ pins: p, read: read({ 'r.mjs': "const S = ['a', 'b'];\nconst K = 1;\n" }) }), []);
    assert.match(checkPins({ pins: p, read: read({ 'r.mjs': "const S = ['a'];\nconst K = 2;\n" }) })[0], /r\.mjs changed/);
  });

  test('line pins: the lines stay, the file around them may grow', () => {
    const p = { files: { 'x.gd': sha256Lf('x') }, lines: [{ file: 's.gd', lines: ['\t"grade_max_pct": [0.0, 16.0],'] }] };
    const t = (body) => ({ 'x.gd': 'x', 's.gd': body });
    assert.deepEqual(checkPins({ pins: p, read: read(t('const A := {\n\t"bus_ui_db": 0.0,\n\t"grade_max_pct": [0.0, 16.0],\n}\n')) }), []);
    assert.match(checkPins({ pins: p, read: read(t('\t"grade_max_pct": [0.0, 40.0],\n')) })[0], /line pin: s\.gd: .*grade_max_pct/);
    assert.match(checkPins({ pins: p, read: read({ 'x.gd': 'x' }) })[0], /line pin: s\.gd is gone/);
  });

  const check = 'export function checkS4(r) {\n  const a = 1;\n\n  if (r < 55) bad();\n}\n';
  const blocks = [{ file: 'c.mjs', function: 'checkS4', lines: ['export function checkS4(r) {', '  const a = 1;', '  if (r < 55) bad();', '}'] }];

  test('blocks: adding passes, altering a threshold fails, --allow-pin excuses that one', () => {
    const p = { blocks };
    assert.deepEqual(checkPins({ pins: p, read: read({ 'c.mjs': check }) }), []);
    const more = check.replace('  if (r < 55) bad();', '  if (r < 55) bad();\n  more();');
    assert.deepEqual(checkPins({ pins: p, read: read({ 'c.mjs': more }) }), []);
    const early = check.replace('  const a = 1;', '  const a = 1;\n  if (kind === 2) return;');
    assert.match(checkPins({ pins: p, read: read({ 'c.mjs': early }) })[0], /added above pinned line/);
    const weak = check.replace('55', '40');
    assert.match(checkPins({ pins: p, read: read({ 'c.mjs': weak }) })[0], /checkS4.*r < 55/);
    assert.deepEqual(checkPins({ pins: p, read: read({ 'c.mjs': weak }), allowPins: ['c.mjs:checkS4'] }), []);
    assert.match(checkPins({ pins: p, read: read({ 'c.mjs': 'export function other() {\n}\n' }) })[0], /checkS4 is gone/);
    assert.match(checkPins({ pins: p, read: read({}) })[0], /c\.mjs is gone/);
  });

  test('a moved helper is followed through its import, and only then', () => {
    const fn = 'function result(a) {\n  return a;\n}';
    const p = { blocks: [{ file: 'c.mjs', function: 'result', lines: fn.split('\n'), moved: 'lib/sim_report.mjs' }] };
    const home = `export ${fn}\n`;
    const imported = "import { pick, result } from '../../../../tools/lib/sim_report.mjs';\n";
    assert.deepEqual(checkPins({ pins: p, read: read({ 'c.mjs': `${fn}\n` }) }), [], 'still at home');
    assert.deepEqual(checkPins({ pins: p, read: read({ 'c.mjs': imported, 'lib/sim_report.mjs': home }) }), [], 'moved byte for byte');
    assert.match(checkPins({ pins: p, read: read({ 'c.mjs': imported, 'lib/sim_report.mjs': home.replace('return a', 'return 1') }) })[0], /deleted, altered or moved/);
    assert.match(checkPins({ pins: p, read: read({ 'c.mjs': 'const result = () => 1;\n', 'lib/sim_report.mjs': home }) })[0], /function result is gone/, 'no import, a local stand-in');
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
    assert.ok(manifest.append_only_pins['tests/games/fishing/sim/check_sims.mjs'].includes('checkAll'));
    assert.ok(manifest.append_only_pins['tests/games/tank/sim/check_sims.mjs'].includes('checkS4'));
    assert.ok(manifest.append_only_pins['tests/games/siege/sim/check_sims.mjs'].includes('checkS6'));
  });
});

describe('checkPinnedBody', () => {
  const pinned = [
    'export function checkS4(reports) {',
    '  const probs = [];',
    '  for (const r of reports) {',
    "    if (r.kind === 'bank') {",
    '      probs.push(...bank(r));',
    '      continue;',
    '    }',
    '    probs.push(...other(r));',
    '  }',
    "  return result('S4', probs);",
    '}',
  ];
  const withLines = (after, ...added) => {
    const at = pinned.findIndex((l) => l.trim() === after);
    return [...pinned.slice(0, at + 1), ...added, ...pinned.slice(at + 1)];
  };
  const body = (cur, opts) => checkPinnedBody(pinned, cur, opts);

  test('unchanged passes; export may come and go on the first line only', () => {
    assert.deepEqual(body(pinned), []);
    assert.deepEqual(body(['function checkS4(reports) {', ...pinned.slice(1)]), []);
    assert.equal(body(pinned.map((l, i) => (i === 1 ? `export ${l}` : l))).length, 1);
  });

  test('the critic\'s probe: a return as the first line is refused', () => {
    const cur = withLines('export function checkS4(reports) {', '  return { status: "PASS", details: [] };');
    assert.match(body(cur)[0], /added above pinned line/);
  });

  test('any statement between pinned lines is refused', () => {
    assert.match(body(withLines('const probs = [];', '  const x = 1;'))[0], /added above/);
    assert.match(body(withLines('for (const r of reports) {', '    continue;'))[0], /added above/);
    assert.match(body(withLines("if (r.kind === 'bank') {", '      break;'))[0], /added above/);
  });

  test('after the last pinned line, before the final return: more checks pass', () => {
    const tail = [...pinned.slice(0, -2), '  const late = pick(reports);', '  for (const r of late) {', '    if (!r) continue;', '    probs.push(...third(r));', '  }', ...pinned.slice(-2)];
    assert.deepEqual(body(tail), []);
  });

  const tailAdd = (...added) => [...pinned.slice(0, -2), ...added, ...pinned.slice(-2)];

  test('the tail may not leave the function or empty what it collected', () => {
    for (const line of ['  return ok();', '  if (x) return ok();', '  throw new Error("x");', '  process.exit(0);', '  probs.length = 0;', '  probs.splice(0);', '  probs.pop();', '  while (probs.length) probs.shift();']) {
      assert.match(body(tailAdd(line))[0] ?? '', /may not leave the function or empty/, line);
    }
    assert.match(body(tailAdd('  for (const r of reports) {', '    return ok();', '  }'))[0] ?? '', /may not leave/);
  });

  test('a branch guarded by a new string may leave; a string the pinned lines name may not', () => {
    assert.deepEqual(body(tailAdd("  if (reports.kind === 'repair') return ok();")), []);
    assert.deepEqual(body(tailAdd("  if (reports.kind === 'repair') {", '    return ok();', '  }')), []);
    assert.match(body(tailAdd("  if (reports.kind === 'bank') return ok();"))[0], /may not leave/);
  });

  test('lines after the closing line are refused, and so are deleted or altered lines', () => {
    assert.match(body([...pinned, 'more();'])[0], /after the closing line/);
    assert.match(body(pinned.filter((l) => !l.includes('other(r)')))[0], /deleted, altered or moved: probs\.push\(\.\.\.other\(r\)\)/);
    assert.equal(body(pinned.map((l) => l.replace('other(r)', 'other(0)'))).length, 1);
    assert.match(body(pinned.slice(0, -2).concat(['}']))[0], /deleted, altered or moved: return result/);
  });

  test('comments may go anywhere; a plain probs.push may go anywhere; nothing else comes with it', () => {
    assert.deepEqual(body(withLines('const probs = [];', '  // why this is safe')), []);
    assert.deepEqual(body(withLines('probs.push(...other(r));', "    probs.push(...lossesInSpans(r, 'rescue'));")), []);
    assert.deepEqual(body(withLines('probs.push(...other(r));', "    if (r.a) probs.push(`${r} = x`);")), []);
    for (const line of ['    probs.push(...(i = 9, []));', '    probs.push(...(probs.length = 0, []));', '    probs.push(process.exit(0));', '    if (r.a) { probs.push(1); return; }', '    probs.push(1), probs.pop();']) {
      assert.equal(body(withLines('probs.push(...other(r));', line)).length, 1, line);
    }
  });

  test('an anchor takes a guarded branch with a new string, and nothing else', () => {
    const anchors = ["if (r.kind === 'bank') {"];
    const above = (...added) => withLines('for (const r of reports) {', ...added);
    assert.deepEqual(body(above("    if (r.kind === 'repair') {", '      probs.push(...repair(r));', '      continue;', '    }'), { anchors }), []);
    assert.deepEqual(body(above("    // the new seat", "    if (r.kind === 'repair') continue;"), { anchors }), []);
    assert.match(body(above("    if (r.kind === 'repair') continue;"))[0], /added above/, 'not without the anchor');
    assert.match(body(above("    if (r.kind === 'bank') continue;"), { anchors })[0], /guarded by a string/, 'a string the pinned lines name');
    assert.match(body(above('    if (r.x) continue;'), { anchors })[0], /guarded by a string/);
    assert.match(body(above('    const n = 1;'), { anchors })[0], /guarded by a string/);
    assert.match(body(above("    if (r.kind === 'repair') continue;", '    return;'), { anchors })[0], /guarded by a string/, 'a line past the branch');
  });
});

describe('checkPinnedConst', () => {
  test('a scalar and an arrow stay as they are', () => {
    assert.deepEqual(checkPinnedConst('const A = 16;', 'const A = 16;'), []);
    assert.deepEqual(checkPinnedConst('export const A = 16;', 'const A = 16;'), []);
    assert.match(checkPinnedConst('const A = 16;', 'const A = 40;')[0], /changed/);
    assert.match(checkPinnedConst('const f = (a) => a;', 'const f = (a) => 0;')[0], /changed/);
  });

  test('an object table keeps its entries, wherever it gains others', () => {
    const was = 'const T = { a: 12, b: 4 };';
    assert.deepEqual(checkPinnedConst(was, 'const T = { a: 12, b: 4, c: 6 };'), []);
    assert.deepEqual(checkPinnedConst(was, 'const T = { a: 12, c: 6, b: 4 };'), []);
    assert.deepEqual(checkPinnedConst(was, 'const T = {\n  a: 12,\n  b: 4,\n  c: 6,\n};'), [], 'the layout may change');
    assert.match(checkPinnedConst(was, 'const T = { a: 12 };')[0], /deleted or altered: b: 4/);
    assert.match(checkPinnedConst(was, 'const T = { a: 12, b: 5 };')[0], /deleted or altered: b: 4/);
    assert.match(checkPinnedConst(was, 'const T = { a: 12, b: 4, b: 5 };')[0], /replaces the pinned key b/);
    assert.match(checkPinnedConst(was, "const T = { a: 12, b: 4, 'b': 5 };")[0], /replaces the pinned key b/);
    assert.match(checkPinnedConst(was, 'const U = { a: 12, b: 4 };')[0], /changed/);
  });

  test('an array table keeps its entries in order, nested values whole', () => {
    const was = "const S = [['S1', one], ['S2', two]];";
    assert.deepEqual(checkPinnedConst(was, "const S = [['S1', one], ['S2', two], ['S3', three]];"), []);
    assert.deepEqual(checkPinnedConst("const N = ['a', 'b'];", "const N = ['a', 'x', 'b'];"), []);
    assert.deepEqual(checkPinnedConst(was, "const S = [\n  ['S1', one],\n  ['S2', two],\n];"), []);
    assert.equal(checkPinnedConst(was, "const S = [['S2', two]];").length, 1);
    assert.equal(checkPinnedConst(was, "const S = [['S2', two], ['S1', one]];").length, 1);
    assert.equal(checkPinnedConst(was, "const S = [['S1', noop], ['S2', two]];").length, 1);
  });

  test('a table turned into something else fails', () => {
    assert.equal(checkPinnedConst('const T = { a: 1 };', 'const T = make();').length, 1);
  });
});

describe('the real checkers under the real manifest', () => {
  const ls = spawnSync(GIT, ['-C', REPO, 'ls-files'], { encoding: 'utf8', maxBuffer: 2 ** 28 });
  const tracked = ls.stdout.split('\n').filter(Boolean);
  const readReal = (f) => {
    try {
      return fs.readFileSync(path.join(REPO, f), 'utf8');
    } catch {
      return null;
    }
  };
  const pins = computePins({ ...pinSpecOf(manifest), tracked, read: readReal });
  const TANK = 'tests/games/tank/sim/check_sims.mjs';
  const SIEGE = 'tests/games/siege/sim/check_sims.mjs';
  const FISHING = 'tests/games/fishing/sim/check_sims.mjs';
  const withEdit = (file, edit) => (f) => (f === file ? edit(readReal(f)) : readReal(f));
  const appendOnly = { blocks: pins.blocks, consts: pins.consts };
  const edited = (file, edit) => checkPins({ pins: appendOnly, read: withEdit(file, edit) });
  const swapOne = (a, b) => (text) => {
    assert.ok(text.includes(a), a);
    return text.replace(a, () => b);
  };

  test('the helpers, enforcers and pass-rule tools the pinned tests rest on are pinned', () => {
    for (const f of [
      'tests/scenarios/lib/scenario_lib.gd',
      'tests/scenarios/lib/scenario_test.gd',
      'tests/core/helpers/core_test_util.gd',
      'tests/core/helpers/fakes.gd',
      'tests/trainer/unlocked_ftms_client.gd',
      'tests/trainer/fake_kickr_transport.gd',
      'tests/sdk/helpers/session_kit.gd',
      'tests/app/app_test_base.gd',
      'addons/wattlands/core/app_state.gd',
      'addons/wattlands/core/ftp_test.gd',
      'addons/wattlands/ui/input_router.gd',
      'addons/wattlands/sdk/sdk_conformance.gd',
      'addons/wattlands/sdk/report_collector.gd',
      'tools/e2e/run.mjs',
      'tools/e2e/lib/game.mjs',
      'tools/fit_check/check.mjs',
    ]) {
      assert.ok(pins.files[f], `${f} is not pinned`);
    }
  });

  test("files others write in this run are line-pinned, never whole, and their pinned lines can't go", () => {
    const lineEdit = (file, a, b = '') => checkPinContent({ pins: { lines: pins.lines }, read: withEdit(file, swapOne(a, b)) });
    for (const f of ['addons/wattlands/core/settings.gd', 'addons/wattlands/sdk/game_host.gd', 'src/app/session_launcher.gd', 'addons/wattlands/sdk/game_sim_runner.gd', 'tests/games/tank/sim/run_sims.sh', 'tests/games/siege/sim/run_sims.sh', 'tests/games/fishing/sim/run_sims.sh']) {
      assert.equal(pins.files[f], undefined, `${f} has other writers`);
      assert.ok(pins.lines.some((e) => e.file === f), `${f} has no line pin`);
    }
    assert.match(lineEdit('addons/wattlands/core/settings.gd', 'var c := clampf(f, float(lim[0]), float(lim[1]))', 'var c := f')[0], /line pin: .*settings\.gd/);
    assert.match(lineEdit('addons/wattlands/sdk/game_host.gd', 'bus.panic_requested.connect(_on_panic)', 'pass')[0], /line pin: .*game_host\.gd/);
    assert.match(lineEdit('addons/wattlands/sdk/game_sim_runner.gd', '"skip_warmup": false', '"skip_warmup": true')[0], /line pin/);
    assert.match(lineEdit('tests/games/tank/sim/run_sims.sh', 'TANK_SEEDS:-1 2 3', 'TANK_SEEDS:-1')[0], /line pin/);
    assert.match(lineEdit('tests/games/siege/sim/run_sims.sh', 'exit "$status"', 'exit 0')[0], /line pin/);
    assert.match(lineEdit('tests/games/fishing/sim/run_sims.sh', 'node tests/games/fishing/sim/check_sims.mjs "${args[@]}"', 'true')[0], /line pin/);
    // An added line beside the pinned ones is what they are for.
    assert.deepEqual(lineEdit('addons/wattlands/core/settings.gd', 'var gmin :=', 'var added := 1\n\tvar gmin :='), []);
  });

  test('the tree as it stands passes, and every BRIEF 4.6 and BRIEF 7 path is pinned', () => {
    assert.deepEqual(checkPins({ pins, read: readReal }), []);
    for (const f of [
      'addons/wattlands/sim/gesture_recognizer.gd',
      'addons/wattlands/core/ride_pause.gd',
      'addons/wattlands/core/rider_profile.gd',
      'addons/wattlands/core/local_rider.gd',
      'addons/wattlands/core/trainer_service.gd',
      'addons/wattlands/trainer/mock_trainer.gd',
      'addons/wattlands/trainer/ble/gdble_transport.gd',
      'addons/wattlands/contracts/effort_directive.gd',
      'addons/wattlands/contracts/trainer_device.gd',
      'tests/trainer/test_ftms_client.gd',
      'tests/trainer/test_ftms_trainer.gd',
      'tests/core/integration/test_safe_unlink.gd',
      'tests/core/integration/test_trainer_stack.gd',
      'tests/core/test_locks.gd',
      'tests/app/test_session_safety.gd',
      'tools/lib/run_tests.mjs',
      'tools/run_tests',
      'tools/run_tests.ps1',
      'tools/check_scripts.gd',
      'tests/pending_allowlist.txt',
      'addons/gut/gut_cmdln.gd',
    ]) {
      assert.ok(pins.files[f], f);
    }
    assert.ok(pins.lines.some((l) => l.file === 'addons/wattlands/core/settings.gd'));
    assert.ok(!pins.files['addons/wattlands/core/settings.gd'], "audio's kit adds its bus defaults to this file");
    assert.ok(matchesLeadOnly('addons/gut/gut_cmdln.gd'));
  });

  test('settings.gd may gain a default; its grade range may not move', () => {
    const p = { files: {}, globs: [], lines: pins.lines, blocks: [{ file: TANK, function: 'classify', lines: pins.blocks.find((b) => b.function === 'classify').lines }] };
    const settings = 'addons/wattlands/core/settings.gd';
    const grow = withEdit(settings, (text) => `${text}\nconst BUS_DB := 0.0\n`);
    assert.deepEqual(checkPins({ pins: p, read: grow }), []);
    assert.match(checkPins({ pins: p, read: withEdit(settings, swapOne('[0.0, 16.0]', '[0.0, 30.0]')) })[0], /line pin/);
  });

  test('run_tests.mjs: a new node suite passes; any other edit fails', () => {
    const p = { files: { 'tools/lib/run_tests.mjs': pins.files['tools/lib/run_tests.mjs'] }, masked: pins.masked, consts: pins.consts.filter((c) => c.file === 'tools/lib/run_tests.mjs') };
    const R = 'tools/lib/run_tests.mjs';
    assert.deepEqual(checkPins({ pins: p, read: withEdit(R, swapOne("'tools/e2e']", "'tools/e2e', 'tools/new']")) }), []);
    assert.deepEqual(checkPins({ pins: p, read: withEdit(R, swapOne("'tools/art',", "'tools/art', 'tools/new',")) }), []);
    assert.match(checkPins({ pins: p, read: withEdit(R, swapOne("'server/relay', ", '')) })[0], /NODE_SUITES/);
    assert.match(checkPins({ pins: p, read: withEdit(R, swapOne('const SIM_TIMEOUT_S = 900;', 'const SIM_TIMEOUT_S = 901;')) })[0], /run_tests\.mjs changed/);
  });

  test("the critic's probes on every checker: a first-line return, an entry out of the table", () => {
    assert.match(edited(TANK, swapOne('export function checkS4(reports, opts = {}) {\n', 'export function checkS4(reports, opts = {}) {\n  return { status: "PASS", details: [] };\n')).join(), /checkS4: a line was added above/);
    assert.match(edited(TANK, swapOne(' S4: checkS4,', '')).join(), /CHECKS: a pinned entry was deleted or altered: S4: checkS4/);
    assert.match(edited(FISHING, swapOne(' R1: checkR1,', '')).join(), /CHECKS: a pinned entry/);
    assert.match(edited(FISHING, swapOne('ALL: checkAll, ', '')).join(), /CHECKS: a pinned entry/);
    assert.match(edited(SIEGE, swapOne("  ['S5', checkS5],\n", '')).join(), /SCENARIOS: a pinned entry/);
    const repeatKey = (text) => {
      const st = extractConst(text, 'CHECKS');
      return text.replace(st, () => st.replace(/,?\s*\};$/, ', S4: () => ok };'));
    };
    assert.match(edited(TANK, repeatKey).join(), /replaces the pinned key S4/);
    assert.match(edited(TANK, swapOne('export function parseArgs(argv) {', 'delete CHECKS.S4;\nexport function parseArgs(argv) {')).join(), /CHECKS is changed at run time/);
    assert.match(edited(SIEGE, swapOne('export function checkAll(reports, only = null, opts = {}) {\n', 'export function checkAll(reports, only = null, opts = {}) {\n  return [];\n')).join(), /checkAll: a line was added above/);
  });

  test('thresholds, helpers and callers are pinned, not only the named functions', () => {
    assert.match(edited(TANK, swapOne('export const TOTAL_GRADE_MAX_PCT = 16;', 'export const TOTAL_GRADE_MAX_PCT = 99;')).join(), /TOTAL_GRADE_MAX_PCT: changed/);
    assert.match(edited(TANK, swapOne('export const FIRST_ERG_MAX_PCT = 65;', 'export const FIRST_ERG_MAX_PCT = 100;')).join(), /FIRST_ERG_MAX_PCT: changed/);
    assert.match(edited(TANK, swapOne('export const DEFAULT_SEEDS = [1, 2, 3];', 'export const DEFAULT_SEEDS = [1];')).join(), /DEFAULT_SEEDS: a pinned entry/);
    assert.match(edited(SIEGE, swapOne('export const WARMUP_MAX_PCT = 65;', 'export const WARMUP_MAX_PCT = 100;')).join(), /WARMUP_MAX_PCT: changed/);
    assert.ok(pins.blocks.some((b) => b.file === FISHING && b.function === 'runProblems'), "checkAll's own rules");
    assert.ok(pins.blocks.some((b) => b.file === TANK && b.function === 'humanPeers'), 'an empty list here would switch off every rule');
    assert.ok(pins.blocks.some((b) => b.file === TANK && b.function === 'runChecks'));
    assert.ok(pins.consts.some((c) => c.file === TANK && c.name === 'traceOf'));
  });

  // Once Tank v4 lands and the lead re-pins, its lines are pinned text: this recipe has done its work.
  const tankHasRepairs = readReal(TANK).includes("'repair'");
  test("SPEC_TANK's additive recipe still passes", { skip: tankHasRepairs && 'Tank v4 has landed' }, () => {
    const recipe = (text) => [
      swapOne("  if (reason === 'boiler' && q.mode === 'SIM' && q.mode_grade !== undefined) return 'boiler';", "  if (reason === 'repair' && q.mode === 'ERG' && q.target_pct !== undefined) return 'repair';\n  if (reason === 'boiler' && q.mode === 'SIM' && q.mode_grade !== undefined) return 'boiler';"),
      swapOne("      if (kind === 'bank' || kind === 'arc') {", "      // the Repairs target\n      if (kind === 'repair') {\n        probs.push(...repairProblems(at, ph, q));\n        break;\n      }\n      if (kind === 'bank' || kind === 'arc') {"),
      swapOne("  if (kind === 'bank' || kind === 'arc') over('ERG target %', got.target_pct, q.target_pct);", "  if (kind === 'repair') over('ERG target %', got.target_pct, q.target_pct);\n  if (kind === 'bank' || kind === 'arc') over('ERG target %', got.target_pct, q.target_pct);"),
      swapOne("  return result('S4', title, probs, `${found.length} runs`);", "  const more = pick(reports, S14_NAMES);\n  for (const [name, r] of more.found) {\n    probs.push(...planProblems(name, r));\n  }\n  return result('S4', title, probs, `${found.length} runs`);"),
      swapOne('S13: checkS13 };', 'S13: checkS13, S14: checkS14 };'),
      swapOne('export const EXPECTED_LAPS = { ashfall_road: 12, drill: 4 };', 'export const EXPECTED_LAPS = { ashfall_road: 12, ambush_15: 6, drill: 4 };'),
    ].reduce((t, f) => f(t), text);
    assert.deepEqual(edited(TANK, recipe), []);
  });

  test('coverage: a hollowed or hand-edited pins file fails against the commit it names', () => {
    const cover = (p) => checkPinCoverage({ pins: p, manifest, tracked, read: readReal });
    assert.deepEqual(cover(pins), []);
    assert.match(cover({ ...pins, files: {} }).join(), /lacks or altered the file pin/);
    assert.match(cover({ ...pins, globs: pins.globs.slice(1) }).join(), /lacks or altered the manifest glob/);
    const one = Object.keys(pins.files)[0];
    assert.match(cover({ ...pins, files: { ...pins.files, [one]: sha256Lf('other') } }).join(), /lacks or altered the file pin/);
    assert.match(cover({ ...pins, blocks: pins.blocks.slice(1) }).join(), /lacks or altered the block/);
    assert.match(cover({ ...pins, blocks: pins.blocks.map((b) => ({ ...b, lines: b.lines.slice(0, 1) })) }).join(), /lacks or altered the block/);
    assert.match(cover({ ...pins, consts: [] }).join(), /lacks or altered the const/);
    assert.match(cover({ ...pins, lines: [] }).join(), /lacks or altered the line pin/);
    assert.match(cover({ ...pins, masked: {} }).join(), /lacks or altered the mask/);
    assert.match(checkPinCoverage({ pins, manifest, tracked: tracked.filter((f) => !f.startsWith('tools/env')), read: readReal }).join(), /the lead re-pins/);
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

  test('a rename out of test_*.gd loses the file\'s tests, as it does in GUT', () => {
    const v = checkTestCounts({ baseFiles: { 'tests/a/test_a.gd': t(3) }, headFiles: { 'tests/a/a_checks.gd': t(3) } });
    assert.match(v.problems.join(), /the total fell 3 -> 0/);
    assert.match(v.notes.join(), /test_a\.gd lost tests: 3 -> 0/);
    assert.deepEqual(checkTestCounts({ baseFiles: { 'tests/a/helper.gd': t(3) }, headFiles: {} }), { problems: [], notes: [] }, 'a file GUT never collected counts for nothing');
    assert.deepEqual(checkTestCounts({ baseFiles: { 'tests/a/test_a.gd': t(1) }, headFiles: { 'tests/a/test_a.gd': t(1), 'tests/a/helper.gd': t(9) } }).problems, []);
    const padded = checkTestCounts({ baseFiles: { 'tests/a/test_a.gd': t(3) }, headFiles: { 'tests/a/test_a.gd': t(1), 'tests/a/helper.gd': t(9) } });
    assert.match(padded.problems.join(), /the total fell 3 -> 1/, 'a helper file does not pad the count');
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
