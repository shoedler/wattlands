// tools/gate fast on scratch projects: the shard lanes with a fake GUT through the real wrapper.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { makeScratchProject } from './helpers.mjs';
import { REAL_MANIFEST, skipNoGodot, temps, sh, write, initRepo, commit, onBranch, gate, check, NO_PINS_MANIFEST, tests } from './gate_helpers.mjs';

// A stand-in for GUT: reads -gtest and fake_gut.json, writes one <testsuite> per file.
const FAKE_GUT = `extends SceneTree


func _initialize() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fake_gut.json"))
	var junit: String = ""
	var files: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("-gjunit_xml_file="):
			junit = arg.trim_prefix("-gjunit_xml_file=")
		if arg.begins_with("-gtest="):
			files = arg.trim_prefix("-gtest=").split(",")
	if not OS.get_cmdline_args().has("-gconfig="):
		print("SCRIPT ERROR: planted: GUT would read res://.gutconfig.json")
	var suites: String = ""
	var bad: String = str(cfg.get("forbidden_in", ""))
	var once: String = str(cfg.get("fail_once_in", ""))
	var always: String = str(cfg.get("fail_in", ""))
	var code: int = 0
	var failures: int = 0
	for file: String in files:
		var rel: String = file.trim_prefix("res://")
		var failed: bool = not always.is_empty() and rel == always
		if not bad.is_empty() and rel == bad:
			print("SCRIPT ERROR: planted")
		if not once.is_empty() and rel == once and not FileAccess.file_exists("res://build/failed_once.txt"):
			var mark: FileAccess = FileAccess.open("res://build/failed_once.txt", FileAccess.WRITE)
			mark.close()
			failed = true
		var status: String = "pass"
		var child: String = ""
		if failed:
			code = 1
			failures += 1
			status = "fail"
			child = '<failure message="failed"></failure>'
		suites += '<testsuite name="%s" tests="1" time="0.1"><testcase name="test_a" assertions="1" status="%s" classname="%s" time="0.1" >%s</testcase></testsuite>' % [rel, status, rel, child]
	var seen: FileAccess = FileAccess.open(junit.get_base_dir().path_join("env.txt"), FileAccess.WRITE)
	seen.store_string(OS.get_environment("WATTLANDS_USERDATA_DIR"))
	seen.close()
	var f: FileAccess = FileAccess.open(junit, FileAccess.WRITE)
	f.store_string('<testsuites name="GutTests" failures="%d" tests="%d">%s</testsuites>' % [failures, files.size(), suites])
	f.close()
	print("= Run Summary")
	quit(code)
`;

// Each test has its own scratch project and its own Godot lock dir inside it, so they run side by side
// and the whole-machine quiet rerun of one waits for nothing of another's.
describe('fast --lanes=gut on a scratch project', { skip: skipNoGodot, concurrency: 4 }, () => {
  const lockEnv = (dir) => ({ WATTLANDS_GODOT_LOCK_DIR: path.join(dir, 'build', 'godot_lock'), WATTLANDS_GODOT_LOCK_CAP: '2' });
  const TEST_SRC = 'func test_a():\n\tassert_eq(a, b)\n';
  const BUDGET_SRC = 'func test_a():\n\tvar t0 := Time.get_ticks_usec()\n\tassert_lt(t0, 9)\n';
  const QUIET = 'tests/games/tank/perf/test_q.gd';

  function scratch(cfg = {}, extraFiles = {}) {
    const dir = makeScratchProject('gate', {
      'addons/gut/gut_cmdln.gd': FAKE_GUT,
      'fake_gut.json': JSON.stringify(cfg),
      'tests/a/test_a.gd': TEST_SRC,
      'tests/a/test_b.gd': TEST_SRC,
      'tests/b/test_c.gd': TEST_SRC,
      'tests/c/test_d.gd': TEST_SRC,
      'tests/c/test_e.gd': 'func helper():\n\tpass\n',
      'tests/games/tank/perf/test_q.gd': TEST_SRC,
      ...extraFiles,
    });
    temps.push(dir);
    initRepo(dir, {}, REAL_MANIFEST);
    return dir;
  }
  const fast = (dir, ...args) => gate(dir, ['fast', '--lanes=gut', '--shards=2', '--games=all', ...args], { env: lockEnv(dir), timeoutMs: 400_000 });
  const stampOf = (dir) => JSON.parse(fs.readFileSync(path.join(dir, 'build', 'gate', 'fast.json'), 'utf8'));

  test('a test GUT did not collect fails gut:total though every shard passed', async () => {
    const dir = scratch({}, { 'tests/b/test_c.gd': `${TEST_SRC}\nclass Helper:\n\tfunc test_hidden():\n\t\tassert_eq(a, b)\n` });
    const r = await fast(dir);
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /FAIL gut:total/);
    assert.match(r.stdout, /tests\/b\/test_c\.gd: the JUnit holds 1 tests, the source 2/);
  });

  test('every file runs once, each shard in its own user dir, and the stamp says partial', async () => {
    const dir = scratch();
    const r = await fast(dir);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /PASS gut:1 \d+s build\/gate\/fast\/gut_1\.log/);
    assert.match(r.stdout, /PASS gut:quiet /);
    const stamp = stampOf(dir);
    assert.equal(stamp.pass, true);
    assert.equal(stamp.partial, true, '--lanes marks the stamp, so floor and stamp-ok refuse it');
    assert.deepEqual(stamp.partial_reasons, ['--lanes=gut']);
    assert.equal(stamp.gut_total, 5, 'the file with no test function is not run');
    assert.equal(stamp.quiet_retried, false);
    assert.deepEqual(stamp.lanes.map((l) => l.name).sort(), ['check', 'gut:1', 'gut:2', 'gut:quiet', 'gut:total', 'import']);
    assert.equal(stamp.tree, sh(dir, 'rev-parse', 'HEAD^{tree}'));
    const seen = fs.readFileSync(path.join(dir, 'build', 'gate', 'fast', 'shard_1', 'env.txt'), 'utf8').replaceAll('\\', '/');
    assert.match(seen, /build\/gate\/fast\/shard_1\/userdata$/);
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'green_count.txt')), 'fast never writes the green count');
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'gate', 'run.lock')), 'the mutex is released');
    assert.equal((await gate(dir, ['stamp-ok', dir])).code, 1, 'stamp-ok refuses the partial stamp');
  });

  test('a FORBIDDEN line in one shard fails the gate and prints the lane', async () => {
    const dir = scratch({ forbidden_in: 'tests/b/test_c.gd' });
    const r = await fast(dir);
    assert.equal(r.code, 1, r.stdout);
    assert.match(r.stdout, /FAIL gut:\d /);
    assert.match(r.stdout, /FAIL gut:total/);
    assert.match(r.stdout, /--- gut:\d \(last 40 lines\)/);
    assert.match(r.stdout, /gate fast: FAIL/);
    assert.equal(stampOf(dir).pass, false);
  });

  test('a total below the tracked floor fails though every shard is green', async () => {
    const dir = scratch({}, { 'tests/green_count_floor.txt': '6\n' });
    const r = await fast(dir);
    assert.equal(r.code, 1, r.stdout);
    assert.match(r.stdout, /fewer than the floor 6/);
    assert.equal(stampOf(dir).floor, 6);
  });

  test('exactly at the floor passes', async () => {
    const dir = scratch({}, { 'tests/green_count_floor.txt': '5\n' });
    const r = await fast(dir);
    assert.equal(r.code, 0, r.stdout);
  });

  test('a budget test failing once reruns under a whole-machine lease; the second verdict stands', async () => {
    const dir = scratch({ fail_once_in: QUIET }, { [QUIET]: BUDGET_SRC });
    const r = await fast(dir);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /budget tests .*test_q\.gd::test_a.*once more inside a whole-machine lease/);
    const stamp = stampOf(dir);
    assert.equal(stamp.quiet_retried, true);
    assert.deepEqual(stamp.quiet_retried_tests, [`${QUIET}::test_a`]);
    assert.equal(stamp.pass, true);
    assert.equal(stamp.lanes.filter((l) => l.name === 'gut:quiet').length, 1);
  });

  test('a budget test failing twice fails', async () => {
    const dir = scratch({ fail_in: QUIET }, { [QUIET]: BUDGET_SRC });
    const r = await fast(dir);
    assert.equal(r.code, 1, r.stdout);
    assert.equal(stampOf(dir).quiet_retried, true);
    assert.equal(stampOf(dir).pass, false);
  });

  test('a quiet file failing once on a test that is no budget stays red', async () => {
    const dir = scratch({ fail_once_in: QUIET });
    const r = await fast(dir);
    assert.equal(r.code, 1, r.stdout);
    assert.match(r.stdout, /does not rerun: not a budget test/);
    const stamp = stampOf(dir);
    assert.equal(stamp.quiet_retried, false);
    assert.equal(stamp.pass, false);
  });

  test('a SCRIPT ERROR in a quiet budget file stays red, with no rerun', async () => {
    const dir = scratch({ forbidden_in: QUIET, fail_once_in: QUIET }, { [QUIET]: BUDGET_SRC });
    const r = await fast(dir);
    assert.equal(r.code, 1, r.stdout);
    assert.match(r.stdout, /does not rerun: .*SCRIPT ERROR/);
    assert.equal(stampOf(dir).quiet_retried, false);
  });

  test('a failed test with exit 0 is red: the JUnit failure count is read', async () => {
    const dir = scratch({}, { 'addons/gut/gut_cmdln.gd': FAKE_GUT.replace('quit(code)', 'quit(0)'), 'fake_gut.json': JSON.stringify({ fail_in: 'tests/b/test_c.gd' }) });
    const r = await fast(dir);
    assert.equal(r.code, 1, r.stdout);
    assert.match(r.stdout, /JUnit reports 1 failed test/);
  });

  test('without --lanes, no test at all is a red gut:total, not a pass', async () => {
    const dir = makeScratchProject('gate-empty', { 'addons/gut/gut_cmdln.gd': FAKE_GUT, 'fake_gut.json': '{}' });
    temps.push(dir);
    initRepo(dir, {}, NO_PINS_MANIFEST);
    const r = await gate(dir, ['fast', '--games=all'], { env: lockEnv(dir), timeoutMs: 400_000 });
    assert.equal(r.code, 1, r.stdout);
    assert.match(r.stdout, /FAIL gut:total/);
    assert.match(r.stdout, /no GUT process ran/);
    const stamp = stampOf(dir);
    assert.equal(stamp.pass, false);
    assert.equal(stamp.gut_total, 0);
    assert.equal(stamp.partial, false);
  });

  test("a branch on one game's paths leaves out the other games' GUT files, honestly: not partial, the floor less what was left out", async () => {
    const games = {
      'src/games/tank/game.json': '{"id":"tank"}\n',
      'src/games/siege/game.json': '{"id":"siege"}\n',
      'src/games/fishing/game.json': '{"id":"fishing"}\n',
      'tests/games/siege/x/test_s.gd': `${TEST_SRC}\nfunc test_b():\n\tassert_eq(a, b)\n`,
      'tests/games/tank/x/test_t.gd': TEST_SRC,
      'tests/games/_template/test_m.gd': TEST_SRC,
    };
    const run = async (floor) => {
      const dir = scratch({}, { ...games, 'tests/green_count_floor.txt': `${floor}\n` });
      onBranch(dir, 'game/tank-x', { 'content/tank/a.json': '{}\n' });
      // No --games: the gate's own rule picks. --lanes keeps sim and e2e out of a scratch project.
      const r = await gate(dir, ['fast', '--lanes=gut', '--shards=2'], { env: lockEnv(dir), timeoutMs: 400_000 });
      return { dir, r, stamp: stampOf(dir) };
    };
    // 9 tests in the source: 2 of them in siege's file, left out; 7 run, so a floor of 9 holds and 10 does not.
    const at = await run(9);
    assert.equal(at.r.code, 0, at.r.stdout + at.r.stderr);
    assert.match(at.r.stdout, /GUT leaves out 1 files of siege: the change touches only the own paths of tank/);
    assert.match(at.r.stdout, /PASS gut:total 0s 7 tests, floor 9 less 2 in 1 files left out \(siege\)/);
    assert.equal(at.stamp.gut_total, 7);
    assert.deepEqual(at.stamp.gut_selection, { all: false, games: ['tank'], skipped_games: ['siege'], skipped_files: 1, reason: 'the change touches only the own paths of tank' });
    assert.deepEqual(at.stamp.partial_reasons, ['--lanes=gut'], 'the selection itself narrows nothing');
    const ran = fs.readdirSync(path.join(at.dir, 'build', 'gate', 'fast')).filter((d) => d.startsWith('shard_'))
      .flatMap((d) => [...fs.readFileSync(path.join(at.dir, 'build', 'gate', 'fast', d, 'junit.xml'), 'utf8').matchAll(/<testsuite name="([^"]+)"/g)].map((m) => m[1]));
    assert.ok(ran.includes('tests/games/_template/test_m.gd') && ran.includes('tests/games/tank/x/test_t.gd'));
    assert.ok(!ran.includes('tests/games/siege/x/test_s.gd'));
    const above = await run(10);
    assert.equal(above.r.code, 1, above.r.stdout);
    assert.match(above.r.stdout, /the shards ran 7 tests, fewer than the floor 8/);
  });

  test('a failing check fails the stamp, and the lanes still run', async () => {
    const dir = scratch();
    sh(dir, 'checkout', '-q', '-b', 'game/tank-x');
    write(dir, { 'docs/games/x.md': 'a\n' });
    commit(dir, 'tank: x');
    const r = await fast(dir);
    assert.equal(r.code, 1, r.stdout);
    assert.match(r.stdout, /FAIL check/);
    assert.match(r.stdout, /PASS gut:1/);
  });
});
