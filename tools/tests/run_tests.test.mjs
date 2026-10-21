// End-to-end tests for tools/run_tests and tools/run_tests.ps1 against a scratch project under build/
// with a fake GUT, so the gate logic, the green count, check_scripts and the step selection run
// through the real wrappers and real Godot without touching the main checkout.
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { TOOLS, IS_WIN, BASH, godotBin, makeScratchProject, runProc, powershellExe, rmQuiet } from './helpers.mjs';

const GODOT = godotBin();
const skipNoGodot = (!GODOT && 'no Godot binary') || (!BASH && 'bash not found');

// Reads res://fake_gut.json and behaves like GUT: writes the JUnit file, prints a summary, exits.
const FAKE_GUT = `extends SceneTree


func _initialize() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fake_gut.json"))
	var junit: String = ""
	var seen: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("-g"):
			seen.append(arg)
		if arg.begins_with("-gjunit_xml_file="):
			junit = arg.trim_prefix("-gjunit_xml_file=")
	var args_file: FileAccess = FileAccess.open("build/fake_gut_args.json", FileAccess.WRITE)
	var seen_env: Dictionary = {}
	for name: String in ["FAL_KEY", "WATTLANDS_ALLOW_ART", "WATTLANDS_NO_HW_CONTROL"]:
		seen_env[name] = OS.has_environment(name)
	args_file.store_string(JSON.stringify({"args": seen, "env": seen_env}))
	args_file.close()
	var n: int = int(cfg.get("tests", 0))
	if not junit.is_empty() and n >= 0:
		var f: FileAccess = FileAccess.open(junit, FileAccess.WRITE)
		f.store_string('<testsuites name="GutTests" failures="0" tests="%d"></testsuites>' % n)
		f.close()
	print(str(cfg.get("extra", "")))
	if bool(cfg.get("summary", true)):
		print("= Run Summary")
	quit(int(cfg.get("exit", 0)))
`;

let project = null;
const cleanup = [];

before(() => {
  if (skipNoGodot) return;
  project = makeScratchProject('run-tests', {
    'addons/gut/gut_cmdln.gd': FAKE_GUT,
    'tools/check_scripts.gd': fs.readFileSync(path.join(TOOLS, 'check_scripts.gd'), 'utf8'),
    'src/good.gd': 'extends RefCounted\n\n\nfunc answer() -> int:\n\treturn 42\n',
    'tests/unit/.keep': '',
  });
  cleanup.push(project);
});

after(() => {
  for (const d of cleanup) rmQuiet(d);
});

function fakeGut(cfg) {
  fs.writeFileSync(path.join(project, 'fake_gut.json'), JSON.stringify({ tests: 3, exit: 0, summary: true, extra: '', ...cfg }));
}

const green = () => {
  try {
    return Number(fs.readFileSync(path.join(project, 'build', 'green_count.txt'), 'utf8').trim());
  } catch {
    return null;
  }
};

function runTests(args, { shell = 'bash', env = {} } = {}) {
  const all = [`--project=${project}`, '--no-lint', ...args];
  const childEnv = { ...process.env };
  delete childEnv.WATTLANDS_RUN_TESTS_NESTED;
  Object.assign(childEnv, env);
  if (shell === 'ps') {
    return runProc(powershellExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(TOOLS, 'run_tests.ps1'), ...all], {
      env: childEnv,
      timeoutMs: 180_000,
    });
  }
  return runProc(BASH, [path.join(TOOLS, 'run_tests').replaceAll('\\', '/'), ...all], { env: childEnv, timeoutMs: 180_000 });
}

const row = (stdout, step) => {
  const m = new RegExp(`^  ${step}\\s+(PASS|FAIL|SKIP|WARN)\\b(.*)$`, 'm').exec(stdout);
  return m ? { status: m[1], rest: m[2] } : null;
};

describe('tools/run_tests (bash)', { skip: skipNoGodot }, () => {
  test('a green GUT run passes and records the green count', async () => {
    fakeGut({ tests: 3 });
    const r = await runTests(['--only=gut']);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.equal(row(r.stdout, 'gut').status, 'PASS');
    assert.equal(row(r.stdout, 'static').status, 'SKIP');
    assert.equal(green(), 3);
    assert.match(fs.readFileSync(path.join(project, 'build', 'gut.log'), 'utf8'), /Run Summary/);
    const seen = JSON.parse(fs.readFileSync(path.join(project, 'build', 'fake_gut_args.json'), 'utf8'));
    assert.deepEqual(seen.args, ['-gdir=res://tests', '-ginclude_subdirs', '-gexit', '-gjunit_xml_file=build/junit.xml']);
  });

  test('fewer tests than the green count fail; --min-count accepts and records the new count', async () => {
    fakeGut({ tests: 2 });
    const low = await runTests(['--only=gut']);
    assert.equal(low.code, 1);
    assert.match(row(low.stdout, 'gut').rest, /fewer than the required 3/);
    assert.equal(green(), 3, 'a red run never changes the green count');
    const ok = await runTests(['--only=gut', '--min-count=2']);
    assert.equal(ok.code, 0, ok.stdout);
    assert.equal(green(), 2);
  });

  test('a forbidden log line, a missing summary or a non-zero exit fails', async () => {
    for (const cfg of [{ extra: 'SCRIPT ERROR: boom' }, { summary: false }, { exit: 1 }, { tests: 0 }]) {
      fakeGut({ tests: 5, ...cfg });
      const r = await runTests(['--only=gut']);
      assert.equal(r.code, 1, JSON.stringify(cfg));
      assert.equal(row(r.stdout, 'gut').status, 'FAIL');
    }
    assert.equal(green(), 2);
  });

  test('--gdir runs narrow: no green-count comparison or update', async () => {
    fakeGut({ tests: 1 });
    const r = await runTests(['--only=gut', '--gdir=res://tests/unit']);
    assert.equal(r.code, 0, r.stdout);
    assert.equal(green(), 2);
    const seen = JSON.parse(fs.readFileSync(path.join(project, 'build', 'fake_gut_args.json'), 'utf8'));
    assert.equal(seen.args[0], '-gdir=res://tests/unit');
  });

  test('static: check_scripts passes clean scripts and fails a broken one', async () => {
    const ok = await runTests(['--only=static']);
    assert.equal(ok.code, 0, ok.stdout);
    assert.match(row(ok.stdout, 'static').rest, /check_scripts \d+ scripts ok/);
    const broken = path.join(project, 'src', 'broken.gd');
    fs.writeFileSync(broken, 'extends RefCounted\n\n\nfunc f() -> int:\n\treturn missing_name\n');
    try {
      const bad = await runTests(['--only=static']);
      assert.equal(bad.code, 1);
      assert.equal(row(bad.stdout, 'static').status, 'FAIL');
      assert.match(bad.stdout, /check_scripts: FAIL res:\/\/src\/broken\.gd/);
    } finally {
      fs.rmSync(broken);
    }
  });

  test('every gate runs without the art variables (OWNERSHIP TL5) and with both locks', async () => {
    fakeGut({ tests: 3 });
    const r = await runTests(['--only=gut', '--min-count=1'], { env: { FAL_KEY: 'dummy-key-123', WATTLANDS_ALLOW_ART: '1' } });
    assert.equal(r.code, 0, r.stdout);
    const seen = JSON.parse(fs.readFileSync(path.join(project, 'build', 'fake_gut_args.json'), 'utf8'));
    assert.deepEqual(seen.env, { FAL_KEY: false, WATTLANDS_ALLOW_ART: false, WATTLANDS_NO_HW_CONTROL: true });
    assert.equal(green(), 3);
  });

  test('import is never a gate', async () => {
    const r = await runTests(['--only=import']);
    assert.equal(r.code, 0, r.stdout);
    assert.match(row(r.stdout, 'import').status, /PASS|WARN/);
  });

  test('step selection, the nested-run guard and usage errors', async () => {
    const nested = await runTests(['--only=node,scaffold,e2e'], { env: { WATTLANDS_RUN_TESTS_NESTED: '1' } });
    assert.equal(nested.code, 0, nested.stdout);
    assert.match(row(nested.stdout, 'node').rest, /nested/);
    assert.equal(row(nested.stdout, 'gut').status, 'SKIP');
    const unknown = await runTests(['--only=gutt']);
    assert.equal(unknown.code, 2);
    assert.match(unknown.stderr, /unknown step "gutt"/);
  });

  test('a missing GUT install fails the gut step', async () => {
    const bare = makeScratchProject('run-tests-bare');
    cleanup.push(bare);
    const r = await runProc(BASH, [path.join(TOOLS, 'run_tests').replaceAll('\\', '/'), `--project=${bare}`, '--only=gut'], {
      timeoutMs: 60_000,
    });
    assert.equal(r.code, 1);
    assert.match(r.stdout, /GUT not vendored/);
    assert.ok(fs.existsSync(path.join(bare, 'build', '.gdignore')), 'build/.gdignore is created before Godot runs');
  });
});

describe('tools/run_tests.ps1', { skip: (!IS_WIN && 'Windows only') || skipNoGodot }, () => {
  test('runs gut and static through tools/godot.ps1', async () => {
    fakeGut({ tests: 4 });
    const r = await runTests(['--only=gut,static'], { shell: 'ps' });
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /wrapper tools\/godot\.ps1/);
    assert.equal(row(r.stdout, 'gut').status, 'PASS');
    assert.equal(row(r.stdout, 'static').status, 'PASS');
    assert.equal(green(), 4);
  });
});
