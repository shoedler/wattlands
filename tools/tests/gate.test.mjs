// Tests for tools/gate (tools/lib/gate.mjs): fmt, the worktree chores, the shims and the run_tests flags the
// gate adds. The rest is split by topic into gate_*.test.mjs, which node --test runs in parallel; the shared
// helpers are in gate_helpers.mjs. Nothing here reads this repo's history, so it also holds on CI's shallow clone.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { BASH, GIT, TOOLS, REPO, IS_WIN, makeScratchProject, powershellExe, runProc } from './helpers.mjs';
import { parseArgs } from '../lib/run_tests.mjs';
import { skipNoGodot, temps, UNUSED_PID, sh, write, initRepo, repo, commit, onBranch, gateEnv, gate, check, NO_PINS_MANIFEST } from './gate_helpers.mjs';

describe('fmt', () => {
  test('no changed .gd: nothing to do; lint dirs only', async () => {
    const dir = repo();
    onBranch(dir, 'feature/x', { 'docs/a.md': 'a\n', 'assets/x/tools_src/a.gd': 'extends Node\n' });
    const r = await gate(dir, ['fmt']);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /no changed \.gd/);
  });

  const noUv = spawnSync('uv', ['--version'], { windowsHide: true }).status !== 0 && 'uv not found';
  test('loads only the files it formatted, in its own lock dir, and fails on one Godot will not load', { skip: skipNoGodot || noUv }, async () => {
    const dir = makeScratchProject('gate-fmt', {
      'tools/check_scripts.gd': fs.readFileSync(path.join(TOOLS, 'check_scripts.gd'), 'utf8'),
      'src/old_broken.gd': 'extends Node\n\n\nfunc f() -> int:\n\treturn undeclared_name\n',
      'src/good.gd': 'extends Node\n',
    });
    temps.push(dir);
    initRepo(dir, {}, NO_PINS_MANIFEST);
    // Were fmt to use the caller's lock dir, it would queue here instead of on the machine's.
    const env = { WATTLANDS_GODOT_LOCK_DIR: path.join(dir, 'no_such_lock'), WATTLANDS_GODOT_LOCK_CAP: '1' };
    onBranch(dir, 'feature/x', { 'src/good.gd': 'extends Node\n\n\nfunc g() -> int:\n\treturn 1\n' });
    const ok = await gate(dir, ['fmt'], { env, timeoutMs: 300_000 });
    assert.equal(ok.code, 0, ok.stdout + ok.stderr);
    assert.match(ok.stdout, /gate fmt: 1 files, 1 loaded, clean in/, 'the broken file it did not touch is not loaded');
    const log = fs.readFileSync(path.join(dir, 'build', 'check_scripts.log'), 'utf8');
    assert.match(log, /check_scripts: 1 named scripts, 0 failures/);
    assert.doesNotMatch(log, /check_scripts: \d+ scripts, \d+ failures/, "the static gate's own summary never comes from a named run");
    assert.ok(fs.existsSync(path.join(dir, 'build', 'gate', 'fmt_lock')), 'its own lock dir');
    write(dir, { 'src/bad.gd': 'extends Node\n\n\nfunc f() -> int:\n\treturn also_undeclared\n' });
    const bad = await gate(dir, ['fmt'], { env, timeoutMs: 300_000 });
    assert.equal(bad.code, 1, bad.stdout + bad.stderr);
    assert.match(bad.stdout, /check_scripts failed .*\n.*FAIL res:\/\/src\/bad\.gd/);
    assert.equal(JSON.parse(fs.readFileSync(path.join(dir, 'build', 'gate', 'fmt.json'), 'utf8')).exit_code, 1);
  });
});

describe('worktree chores', () => {
  const tmpEnv = (dir) => ({ TEMP: dir, TMP: dir, TMPDIR: dir });

  test('wt-add makes a ready worktree: build/.gdignore, imported, clean', { skip: skipNoGodot }, async () => {
    const dir = repo({ 'project.godot': 'config_version=5\n' });
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-wt-'));
    temps.push(root);
    const r = await gate(dir, ['wt-add', 'one', 'game/one', `--wt-root=${root}`], { timeoutMs: 300_000 });
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /ready in \d+ s/);
    const wt = path.join(root, 'one');
    assert.ok(fs.existsSync(path.join(wt, 'build', '.gdignore')));
    assert.equal(sh(wt, 'rev-parse', '--abbrev-ref', 'HEAD'), 'game/one');
    assert.equal(sh(wt, 'status', '--porcelain'), '');
    const again = await gate(dir, ['wt-add', 'one', 'game/two', `--wt-root=${root}`]);
    assert.equal(again.code, 3);
    sh(dir, 'worktree', 'remove', '--force', wt);
  });

  test('wt-gc removes only merged and clean worktrees, and stale temp dirs only with a dead pid', async () => {
    const dir = repo();
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-gc-'));
    temps.push(root);
    const add = (name, branch) => {
      const p = path.join(root, name);
      sh(dir, 'worktree', 'add', '-q', '-b', branch, p, 'main');
      return p;
    };
    const merged = add('merged', 'b/merged');
    write(merged, { 'a.txt': 'a\n' });
    commit(merged, 'merged work');
    sh(dir, 'merge', '-q', '--no-ff', '--no-edit', 'b/merged');
    const ahead = add('ahead', 'b/ahead');
    write(ahead, { 'b.txt': 'b\n' });
    commit(ahead, 'unmerged work');
    const dirtyMerged = add('dirty', 'b/dirty');
    write(dirtyMerged, { 'c.txt': 'c\n' });
    commit(dirtyMerged, 'dirty work');
    sh(dir, 'merge', '-q', '--no-ff', '--no-edit', 'b/dirty');
    write(dirtyMerged, { 'uncommitted.txt': 'x\n' });
    const running = add('running', 'b/running');
    write(running, { 'd.txt': 'd\n' });
    commit(running, 'busy');
    sh(dir, 'merge', '-q', '--no-ff', '--no-edit', 'b/running');
    write(running, { 'build/gate/run.lock': String(process.pid) });
    sh(running, 'config', 'core.excludesFile', path.join(dir, '.gitignore'));
    const fresh = add('fresh', 'b/fresh');

    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-tmp-'));
    temps.push(tmp);
    const dead = UNUSED_PID;
    const old = new Date(Date.now() - 48 * 3600 * 1000);
    for (const [name, mtime] of [[`wattlands_sim_${dead}_0`, old], [`wattlands_sim_${process.pid}_0`, old], [`wattlands_new_${dead}_1`, new Date()], ['wattlands-godot', old]]) {
      fs.mkdirSync(path.join(tmp, name));
      fs.utimesSync(path.join(tmp, name), mtime, mtime);
    }

    const look = await gate(dir, ['wt-gc'], { env: tmpEnv(tmp) });
    assert.equal(look.code, 0, look.stdout + look.stderr);
    assert.match(look.stdout, /merged \| b\/merged \| yes \| 0 \| \d+ \| remove/);
    assert.match(look.stdout, /ahead \| b\/ahead \| no \| 0 \| \d+ \| keep \(ahead of base\)/);
    assert.match(look.stdout, /dirty \| b\/dirty \| yes \| 1 \| \d+ \| keep \(dirty\)/);
    assert.match(look.stdout, /uncommitted\.txt/);
    assert.match(look.stdout, /fresh \| b\/fresh \| yes \| 0 \| \d+ \| keep \(fresh: at the base tip\)/);
    assert.match(look.stdout, /1 stale temp dirs/);
    assert.ok(fs.existsSync(merged), 'without --apply nothing goes');

    const r = await gate(dir, ['wt-gc', '--apply'], { env: tmpEnv(tmp) });
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.ok(!fs.existsSync(merged));
    assert.equal(sh(dir, 'branch', '--list', 'b/merged'), '');
    assert.ok(fs.existsSync(ahead));
    assert.ok(sh(dir, 'branch', '--list', 'b/ahead').includes('b/ahead'));
    assert.ok(fs.existsSync(dirtyMerged));
    assert.ok(fs.existsSync(running), 'a live gate keeps its worktree');
    assert.ok(fs.existsSync(fresh));
    assert.ok(!fs.existsSync(path.join(tmp, `wattlands_sim_${dead}_0`)));
    assert.ok(fs.existsSync(path.join(tmp, `wattlands_sim_${process.pid}_0`)), 'a live pid stays');
    assert.ok(fs.existsSync(path.join(tmp, `wattlands_new_${dead}_1`)), 'a young dir stays');
    assert.ok(fs.existsSync(path.join(tmp, 'wattlands-godot')), 'the lock dir has no underscore and is never matched');
    for (const p of [ahead, dirtyMerged, running, fresh]) sh(dir, 'worktree', 'remove', '--force', p);
  });
});

describe('the shims', () => {
  test('tools/gate is a bash script with a shebang, committed executable', () => {
    assert.match(fs.readFileSync(path.join(TOOLS, 'gate'), 'utf8'), /^#!\/usr\/bin\/env bash\n/);
    const r = spawnSync(GIT, ['-C', REPO, 'ls-files', '-s', 'tools/gate'], { encoding: 'utf8' });
    if (r.stdout.trim()) assert.match(r.stdout, /^100755 /, 'git add --chmod=+x tools/gate');
  });

  test('tools/gate.ps1 keeps CRLF', () => {
    const ps = fs.readFileSync(path.join(TOOLS, 'gate.ps1'), 'utf8');
    assert.ok(ps.includes('\r\n') && !/[^\r]\n/.test(ps), 'CRLF only');
  });

  test('bash: check runs through the shim and passes --shell=bash', { skip: !BASH && 'bash not found' }, async () => {
    const dir = repo();
    const r = await runProc(BASH, [path.join(TOOLS, 'gate').replaceAll('\\', '/'), 'check', `--project=${dir}`], { env: gateEnv(), cwd: dir });
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /check: PASS/);
    const bad = await runProc(BASH, [path.join(TOOLS, 'gate').replaceAll('\\', '/'), 'nope'], { env: gateEnv(), cwd: dir });
    assert.equal(bad.code, 2);
  });

  test('PowerShell: the same', { skip: (!IS_WIN || !powershellExe()) && 'Windows only' }, async () => {
    const dir = repo();
    const ps = (...args) => runProc(powershellExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(TOOLS, 'gate.ps1'), ...args], { env: gateEnv(), cwd: dir });
    const r = await ps('check', `--project=${dir}`);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /check: PASS/);
    assert.equal((await ps('nope')).code, 2);
  });
});

describe('run_tests flags the gate adds', () => {
  test('defaults change nothing', () => {
    const o = parseArgs([]);
    assert.equal(o.games, null);
    assert.equal(o.simOuterS, 900);
    assert.deepEqual(parseArgs(['--games=a,b']).games, ['a', 'b']);
    assert.equal(parseArgs(['--sim-outer-timeout=3600']).simOuterS, 3600);
  });

  const gameJson = (id) => JSON.stringify({ id, contents: ['one'], e2e_content: 'one', max_players: 1 });

  function simProject() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-sim-'));
    temps.push(dir);
    write(dir, {
      'project.godot': 'config_version=5\n',
      'src/games/aaa/game.json': gameJson('aaa'),
      'src/games/bbb/game.json': gameJson('bbb'),
      'build/sims/aaa_old.json': '{}',
      'build/sims/bbb_keep.json': '{}',
      'build/sims/fit/aaa_old_slot0.fit': 'x',
      'build/sims/fit/bbb_keep_slot0.fit': 'x',
    });
    return dir;
  }
  const runTests = (dir, ...args) => runProc(process.execPath, [path.join(TOOLS, 'lib', 'run_tests.mjs'), '--shell=bash', `--project=${dir}`, ...args], { env: gateEnv({ WATTLANDS_BASH: BASH }), cwd: dir, timeoutMs: 120_000 });
  const skip = !BASH && 'bash not found';

  test('an unknown --games id fails sim and e2e, and deletes nothing it does not own', { skip }, async () => {
    const dir = simProject();
    const r = await runTests(dir, '--only=sim,e2e', '--games=nope');
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /"nope" is not a registered game/);
    assert.ok(fs.existsSync(path.join(dir, 'build', 'sims', 'bbb_keep.json')));
  });

  test("--games deletes only that game's reports, and the outer timer reaches run()", { skip }, async () => {
    const dir = simProject();
    const r = await runTests(dir, '--only=sim', '--games=aaa', '--sim-outer-timeout=0.05');
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /aaa_one: exit 124/, 'the 0.05 s timer stopped the run');
    assert.doesNotMatch(r.stdout, /bbb_one/, 'the other game does not run');
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'sims', 'aaa_old.json')));
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'sims', 'fit', 'aaa_old_slot0.fit')));
    assert.ok(fs.existsSync(path.join(dir, 'build', 'sims', 'bbb_keep.json')), "a parallel lane's report stays");
    assert.ok(fs.existsSync(path.join(dir, 'build', 'sims', 'fit', 'bbb_keep_slot0.fit')));
  });
});
