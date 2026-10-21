// End-to-end tests for tools/run_tests and tools/run_tests.ps1 against a scratch project under build/
// with a fake GUT, so the gate logic, the green count, check_scripts, the lint gate and the step
// selection run through the real wrappers and real Godot without touching the main checkout.
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { TOOLS, REPO, IS_WIN, BASH, godotBin, makeScratchProject, runProc, powershellExe, rmQuiet, minimalEnv } from './helpers.mjs';
import { evaluateLint, parseArgs, GDTOOLKIT_VERSION } from '../lib/run_tests.mjs';

const GODOT = godotBin();
const skipNoGodot = (!GODOT && 'no Godot binary') || (!BASH && 'bash not found');

// The runner's own detection order: gdlint on PATH at the pinned version, else uvx.
function hasGdtoolkit() {
  const ok = (exe, args) => {
    const r = spawnSync(exe, args, { encoding: 'utf8', timeout: 90_000, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    return r.status === 0 && `${r.stdout ?? ''}`.includes(GDTOOLKIT_VERSION);
  };
  return ok('gdlint', ['--version']) || ok('uvx', ['--from', `gdtoolkit==${GDTOOLKIT_VERSION}`, 'gdlint', '--version']);
}
const skipNoGdtoolkit = skipNoGodot || (!hasGdtoolkit() && `gdtoolkit ${GDTOOLKIT_VERSION} unavailable`);

describe('evaluateLint and the lint options', () => {
  test('any gdlint problem or file to reformat fails the static step', () => {
    const clean = { code: 0, text: 'Success: no problems found\n' };
    const tidy = { code: 0, text: '3 files would be left unchanged\n' };
    assert.deepEqual(evaluateLint(clean, tidy), { fail: false, note: 'gdlint clean, gdformat clean' });
    const lint = evaluateLint({ code: 1, text: 'src/a.gd:3: Error: ...\nFailure: 2 problems found\n' }, tidy);
    assert.equal(lint.fail, true);
    assert.match(lint.note, /^gdlint 2 problems, gdformat clean \(see build\/gdlint\.log, build\/gdformat\.log\)$/);
    const fmt = evaluateLint(clean, { code: 1, text: 'would reformat src/a.gd\n1 file would be reformatted, 2 files would be left unchanged.\n' });
    assert.equal(fmt.fail, true);
    assert.match(fmt.note, /gdformat 1 files to reformat/);
    assert.equal(evaluateLint({ code: 2, text: 'boom' }, tidy).note.startsWith('gdlint exit 2'), true);
  });

  test('--no-lint skips lint; --strict-lint is an accepted no-op', () => {
    assert.equal(parseArgs(['--no-lint']).noLint, true);
    const o = parseArgs(['--strict-lint']);
    assert.equal(o.noLint, false);
    assert.equal('strictLint' in o, false);
  });
});

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
    gdlintrc: fs.readFileSync(path.join(REPO, 'gdlintrc'), 'utf8'),
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

function runTests(args, { shell = 'bash', env = {}, lint = false } = {}) {
  const all = [`--project=${project}`, ...(lint ? [] : ['--no-lint']), ...args];
  const childEnv = { ...process.env };
  delete childEnv.WATTLANDS_RUN_TESTS_NESTED;
  // Windows names variables case-insensitively ("Path"): drop the old spelling of an overridden one.
  for (const key of Object.keys(env)) {
    for (const old of Object.keys(childEnv)) if (old !== key && old.toUpperCase() === key.toUpperCase()) delete childEnv[old];
  }
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

  test('static: gdlint and gdformat findings fail the step', { skip: skipNoGdtoolkit }, async () => {
    const ok = await runTests(['--only=static'], { lint: true });
    assert.equal(ok.code, 0, ok.stdout);
    assert.match(row(ok.stdout, 'static').rest, /check_scripts \d+ scripts ok; gdlint clean, gdformat clean/);
    const cases = [
      // gdformat wants two blank lines before a function; gdlint has nothing to say.
      ['unformatted.gd', 'extends RefCounted\nfunc f() -> int:\n\treturn 1\n', /gdlint clean, gdformat 1 files to reformat/],
      // gdformat leaves it alone; gdlint's function-name rule (kept by ./gdlintrc) rejects it.
      ['bad_name.gd', 'extends RefCounted\n\n\nfunc BadName() -> int:\n\treturn 1\n', /gdlint 1 problems, gdformat clean/],
    ];
    for (const [name, source, note] of cases) {
      const file = path.join(project, 'src', name);
      fs.writeFileSync(file, source);
      try {
        const bad = await runTests(['--only=static'], { lint: true });
        assert.equal(bad.code, 1, `${name}: ${bad.stdout}`);
        assert.equal(row(bad.stdout, 'static').status, 'FAIL', name);
        assert.match(row(bad.stdout, 'static').rest, note, name);
        assert.match(row(bad.stdout, 'static').rest, /check_scripts \d+ scripts ok/, name);
      } finally {
        fs.rmSync(file);
      }
    }
  });

  test('static: without gdtoolkit the lint part is skipped, not failed', async () => {
    const r = await runTests(['--only=static'], { lint: true, env: { PATH: minimalEnv().PATH } });
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.equal(row(r.stdout, 'static').status, 'PASS');
    assert.match(row(r.stdout, 'static').rest, /gdtoolkit unavailable, skipped/);
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
