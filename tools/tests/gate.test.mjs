// Tests for tools/gate (tools/lib/gate.mjs) on temp git repos and scratch projects: every rule of
// SPEC_GATES section 6 with one failing and one passing case, the mutex, the stamps, floor, the shard
// lanes with a fake GUT through the real wrapper, the matrix pool with a fake run_game_sim, and the
// worktree chores. Nothing here reads this repo's history, so it also holds on CI's shallow Linux clone.
import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { BASH, GIT, TOOLS, REPO, IS_WIN, godotBin, makeScratchProject, powershellExe, rmQuiet, runProc } from './helpers.mjs';
import { checkAddedText } from '../lib/gate_core.mjs';
import { parseArgs } from '../lib/run_tests.mjs';

const GATE = path.join(TOOLS, 'lib', 'gate.mjs');
const REAL_MANIFEST = JSON.parse(fs.readFileSync(path.join(TOOLS, 'lib', 'gate_manifest.json'), 'utf8'));
const GODOT = godotBin();
const skipNoGodot = (!GODOT && 'no Godot binary') || (!BASH && 'bash not found');
const temps = [];

after(() => {
  for (const d of temps) rmQuiet(d);
});

function sh(dir, ...args) {
  const r = spawnSync(GIT, ['-C', dir, ...args], { encoding: 'utf8', windowsHide: true });
  assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}

function write(dir, files) {
  for (const [rel, text] of Object.entries(files)) {
    const file = path.join(dir, rel);
    if (text === null) {
      fs.rmSync(file, { force: true });
      continue;
    }
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  }
}

function initRepo(dir, files, manifest) {
  sh(dir, 'init', '-q', '-b', 'main');
  sh(dir, 'config', 'user.name', 'gate test');
  sh(dir, 'config', 'user.email', 'gate@example.invalid');
  sh(dir, 'config', 'core.autocrlf', 'false');
  sh(dir, 'config', 'core.safecrlf', 'false');
  write(dir, { '.gitignore': 'build/\n.godot/\n.userdata/\n', 'tools/lib/gate_manifest.json': JSON.stringify(manifest), ...files });
  commit(dir, 'base');
}

/** A fresh repo on main with one commit, holding the real manifest (or `manifest`) and `files`. */
function repo(files = {}, manifest = REAL_MANIFEST) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-repo-'));
  temps.push(dir);
  initRepo(dir, files, manifest);
  return dir;
}

function commit(dir, message) {
  sh(dir, 'add', '-A');
  sh(dir, 'commit', '-q', '--allow-empty', '-m', message);
  return sh(dir, 'rev-parse', 'HEAD');
}

/** Writes `files` on a new branch and commits them. */
function onBranch(dir, branch, files, message = 'work') {
  sh(dir, 'checkout', '-q', '-b', branch);
  write(dir, files);
  return commit(dir, message);
}

function gateEnv(extra = {}) {
  const env = { ...process.env, ...extra };
  delete env.WATTLANDS_RUN_TESTS_NESTED;
  return env;
}

const gate = (dir, args, { env = {}, timeoutMs = 300_000 } = {}) => runProc(process.execPath, [GATE, ...args, `--project=${dir}`], { env: gateEnv(env), cwd: dir, timeoutMs });
const check = (dir, ...args) => gate(dir, ['check', ...args]);

async function assertCheck(dir, args, code, pattern) {
  const r = await check(dir, ...args);
  assert.equal(r.code, code, r.stdout + r.stderr);
  if (pattern) assert.match(r.stdout, pattern);
  return r;
}

describe('6.1 ownership, through git', { concurrency: 4 }, () => {
  test('never_edit fails; --allow passes it and the stamp records it', async () => {
    const dir = repo({ 'docs/games/tank.md': 'a\n' });
    onBranch(dir, 'game/tank-x', { 'docs/games/tank.md': 'b\n' });
    await assertCheck(dir, [], 1, /docs\/games\/tank\.md: never edited/);
    await assertCheck(dir, ['--allow=docs/games/**'], 0);
    const stamp = JSON.parse(fs.readFileSync(path.join(dir, 'build', 'gate', 'check.json'), 'utf8'));
    assert.deepEqual(stamp.allow, ['docs/games/**']);
  });

  test('deny fails for cleanup; a free path passes', async () => {
    const dir = repo();
    onBranch(dir, 'cleanup/c1', { 'tests/governor/test_a.txt': 'a\n' });
    await assertCheck(dir, [], 1, /denied to workstream cleanup/);
    const ok = repo();
    onBranch(ok, 'cleanup/c1', { 'src/app/a.txt': 'a\n' });
    await assertCheck(ok, [], 0);
  });

  test('lead_only fails; a ws with it in also passes; a lead branch passes', async () => {
    const dir = repo();
    onBranch(dir, 'game/tank-x', { 'project.godot': 'a\n' });
    await assertCheck(dir, [], 1, /project\.godot: lead only/);
    const audio = repo();
    onBranch(audio, 'audio/kit', { 'tools/lib/run_tests.mjs': 'a\n' });
    await assertCheck(audio, [], 0);
    const queue = repo();
    onBranch(queue, 'queue', { 'project.godot': 'a\n', 'tools/lib/run_tests.mjs': 'a\n' });
    await assertCheck(queue, [], 0, /lead branch queue/);
  });

  test("another game's path fails; audio's paths pass it", async () => {
    const dir = repo();
    onBranch(dir, 'game/tank-x', { 'src/games/siege/a.txt': 'a\n' });
    await assertCheck(dir, [], 1, /belongs to game siege/);
    const audio = repo();
    onBranch(audio, 'audio/siege', { 'src/games/siege/audio/a.txt': 'a\n' });
    await assertCheck(audio, [], 0);
  });

  test('a path outside the ws needs a lone platform: commit', async () => {
    const dir = repo();
    onBranch(dir, 'game/tank-x', { 'addons/wattlands/a.txt': 'a\n' }, 'tank: x');
    await assertCheck(dir, [], 1, /whose subject does not start "platform:"/);
    const mixed = repo();
    onBranch(mixed, 'game/tank-x', { 'addons/wattlands/a.txt': 'a\n', 'src/games/tank/a.txt': 'a\n' }, 'platform: x');
    await assertCheck(mixed, [], 1, /a platform commit stands alone/);
    const ok = repo();
    onBranch(ok, 'game/tank-x', { 'addons/wattlands/a.txt': 'a\n' }, 'platform: x');
    write(ok, { 'src/games/tank/a.txt': 'a\n' });
    commit(ok, 'tank: y');
    await assertCheck(ok, [], 0);
  });

  test('an uncommitted path counts, untracked too', async () => {
    const dir = repo();
    onBranch(dir, 'game/tank-x', { 'src/games/tank/a.txt': 'a\n' });
    await assertCheck(dir, [], 0);
    write(dir, { 'addons/wattlands/new.txt': 'a\n' });
    await assertCheck(dir, [], 1, /addons\/wattlands\/new\.txt: outside workstream tank and in no commit/);
  });

  test('--ws beats the branch name; an unknown ws is a usage error; ws-less says so', async () => {
    const dir = repo();
    onBranch(dir, 'feature/x', { 'src/games/siege/a.txt': 'a\n' });
    await assertCheck(dir, [], 0, /ws-less branch feature\/x/);
    await assertCheck(dir, ['--ws=tank'], 1, /belongs to game siege/);
    await assertCheck(dir, ['--ws=siege'], 0);
    const r = await check(dir, '--ws=nope');
    assert.equal(r.code, 2);
    assert.match(r.stderr, /unknown workstream/);
  });

  test('main merged in does not count against the branch', async () => {
    const dir = repo();
    onBranch(dir, 'game/tank-x', { 'src/games/tank/a.txt': 'a\n' });
    sh(dir, 'checkout', '-q', 'main');
    write(dir, { 'project.godot': 'landed\n' });
    commit(dir, 'chore: lead');
    sh(dir, 'checkout', '-q', 'game/tank-x');
    sh(dir, 'merge', '-q', '--no-edit', 'main');
    await assertCheck(dir, [], 0);
  });

  test('each branch_ws row reaches its workstream', async () => {
    const rows = { 'tooling/x': 'gate', 'audio/x': 'audio', 'cleanup/x': 'cleanup', 'docs/x': 'docs', 'wo/x': 'workout', 'game/tank4-x': 'tank', 'game/workout-x': 'workout', 'game/siege-x': 'siege', 'game/fishing-x': 'fishing' };
    const dir = repo();
    assert.equal(Object.keys(rows).length, REAL_MANIFEST.branch_ws.length, 'one branch per row');
    for (const [branch, ws] of Object.entries(rows)) {
      sh(dir, 'checkout', '-q', '-B', branch, 'main');
      const r = await check(dir);
      assert.match(r.stdout, new RegExp(`check: PASS ws ${ws},`), branch);
    }
  });
});

const PIN_MANIFEST = {
  ...REAL_MANIFEST,
  safety_pin_globs: ['tests/governor/**', 'tools/godot.sh'],
  append_only_pins: { 'tests/games/tank/sim/check_sims.mjs': ['checkS4'] },
};
const CHECKER = 'export function checkS4(r) {\n  if (r.w < 55) return bad();\n  return ok();\n}\n';

function pinnedRepo() {
  const dir = repo({ 'tests/governor/test_a.gd': 'func test_a():\n\tassert_eq(a, b)\n', 'tools/godot.sh': 'real\n', 'tests/games/tank/sim/check_sims.mjs': CHECKER }, PIN_MANIFEST);
  return dir;
}

async function pin(dir) {
  const r = await gate(dir, ['pin-safety', '--reason=baseline']);
  assert.equal(r.code, 0, r.stdout + r.stderr);
  commit(dir, 'chore: pins');
}

describe('6.2 and 6.3 pins, through git', { concurrency: 4 }, () => {
  test('no pins at HEAD is a note, not a failure', async () => {
    const dir = pinnedRepo();
    onBranch(dir, 'game/tank-x', { 'src/games/tank/a.txt': 'a\n' });
    await assertCheck(dir, [], 0, /no tools\/lib\/safety_pins\.json at HEAD/);
  });

  test('pin-safety records hashes and blocks, and an untouched tree passes', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    const pins = JSON.parse(fs.readFileSync(path.join(dir, 'tools', 'lib', 'safety_pins.json'), 'utf8'));
    assert.equal(pins.reason, 'baseline');
    assert.deepEqual(Object.keys(pins.files), ['tests/governor/test_a.gd', 'tools/godot.sh']);
    assert.equal(pins.blocks[0].function, 'checkS4');
    assert.equal(pins.pinned_at.length, 40);
    onBranch(dir, 'game/tank-x', { 'src/games/tank/a.txt': 'a\n' });
    await assertCheck(dir, [], 0);
  });

  test('a changed pinned file fails, committed or not; CRLF alone does not', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'tooling/x', { 'tools/godot.sh': 'weaker\n' });
    await assertCheck(dir, [], 1, /safety pin: tools\/godot\.sh changed/);
    const work = pinnedRepo();
    await pin(work);
    sh(work, 'checkout', '-q', '-b', 'tooling/x');
    write(work, { 'tools/godot.sh': 'weaker\n' });
    await assertCheck(work, [], 1, /safety pin: tools\/godot\.sh changed/);
    write(work, { 'tools/godot.sh': 'real\r\n' });
    const r = await check(work);
    assert.doesNotMatch(r.stdout, /safety pin/);
  });

  test('a deleted pinned file fails', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'tooling/x', { 'tools/godot.sh': null });
    await assertCheck(dir, [], 1, /safety pin: tools\/godot\.sh is gone/);
  });

  test('a glob matching nothing: pin-safety refuses it, and a pins file holding one fails', async () => {
    const dir = repo({}, { ...REAL_MANIFEST, safety_pin_globs: ['tests/none/**'] });
    const r = await gate(dir, ['pin-safety', '--reason=x']);
    assert.equal(r.code, 1);
    assert.match(r.stdout, /matches nothing/);
    write(dir, { 'tools/lib/safety_pins.json': JSON.stringify({ globs: ['tests/none/**'], files: {}, blocks: [] }) });
    commit(dir, 'chore: pins');
    await assertCheck(dir, [], 1, /the glob tests\/none\/\*\* matches nothing/);
  });

  test('pin-safety refuses a dirty tree', async () => {
    const dir = pinnedRepo();
    write(dir, { 'src/a.txt': 'a\n' });
    const r = await gate(dir, ['pin-safety', '--reason=x']);
    assert.equal(r.code, 3);
  });

  test('append-only: adding lines passes; altering a threshold fails; --allow-pin excuses it', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    const more = CHECKER.replace('  return ok();', "  if (r.kind === 'repair') return ok();\n  return ok();");
    onBranch(dir, 'game/tank-x', { 'tests/games/tank/sim/check_sims.mjs': more });
    await assertCheck(dir, [], 0);
    write(dir, { 'tests/games/tank/sim/check_sims.mjs': CHECKER.replace('55', '40') });
    commit(dir, 'tank: weaker');
    await assertCheck(dir, [], 1, /append-only pin: .*checkS4.*r\.w < 55/);
    await assertCheck(dir, ['--allow-pin=tests/games/tank/sim/check_sims.mjs:checkS4'], 0);
  });

  test('the safety pins file itself is denied to tooling branches', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'tooling/x', { 'tools/lib/safety_pins.json': '{"globs":[],"files":{},"blocks":[]}\n' });
    await assertCheck(dir, [], 1, /safety_pins\.json: denied/);
  });
});

const tests = (n, name = 'x') => Array.from({ length: n }, (_, i) => `func test_${name}_${i}():\n\tassert_eq(a, b)\n`).join('\n');

describe('6.4 test counts, through git', { concurrency: 4 }, () => {
  test('a falling total fails; rising passes', async () => {
    const dir = repo({ 'tests/a/test_a.gd': tests(2), 'tests/a/test_a.gd.uid': 'uid\n' });
    onBranch(dir, 'game/tank-x', { 'tests/a/test_a.gd': tests(1) }, 'platform: fewer');
    await assertCheck(dir, [], 1, /the total fell 2 -> 1/);
    const ok = repo({ 'tests/a/test_a.gd': tests(2), 'tests/a/test_a.gd.uid': 'uid\n' });
    onBranch(ok, 'game/tank-x', { 'tests/a/test_a.gd': tests(3) }, 'platform: more');
    await assertCheck(ok, [], 0);
  });

  test('a falling area needs Test-Removal; the trailer passes it and is shown', async () => {
    const files = { 'tests/games/tank/test_a.gd': tests(2), 'tests/games/tank/test_a.gd.uid': 'u\n', 'tests/games/tank/rules/test_b.gd': tests(1), 'tests/games/tank/rules/test_b.gd.uid': 'u\n', 'tests/games/siege/test_c.gd': tests(2), 'tests/games/siege/test_c.gd.uid': 'u\n' };
    const change = { 'tests/games/siege/test_c.gd': tests(1), 'tests/games/tank/test_a.gd': tests(4) };
    const dir = repo(files);
    onBranch(dir, 'feature/x', change);
    await assertCheck(dir, [], 1, /tests\/games\/siege fell 2 -> 1 with no "Test-Removal/);
    const ok = repo(files);
    sh(ok, 'checkout', '-q', '-b', 'feature/x');
    write(ok, change);
    sh(ok, 'add', '-A');
    sh(ok, 'commit', '-q', '-m', 'work', '-m', 'Test-Removal: tests/games/siege the rear logic went');
    const r = await assertCheck(ok, [], 0, /Test-Removal: the rear logic went/);
    assert.match(r.stdout, /tests\/games\/siege\/test_c\.gd lost tests: 2 -> 1/);
  });

  test('the revert of a merge is excused; a revert mixed with other work is not', async () => {
    const dir = repo({ 'tests/a/test_a.gd': tests(2), 'tests/a/test_a.gd.uid': 'u\n' });
    onBranch(dir, 'queue', { 'tests/a/test_a.gd': tests(1) }, 'Revert "Merge game/x: y"');
    await assertCheck(dir, [], 0, /in a merge revert/);
    write(dir, { 'src/a.txt': 'a\n' });
    commit(dir, 'other work');
    await assertCheck(dir, [], 1, /the total fell/);
  });

  test('an empty assert added in a test fails; in tools/tests it does not', async () => {
    const dir = repo();
    onBranch(dir, 'feature/x', { 'tests/a/test_a.gd': 'func test_a():\n\tassert_true(true)\n', 'tests/a/test_a.gd.uid': 'u\n' });
    await assertCheck(dir, [], 1, /an empty assert was added/);
    const ok = repo();
    onBranch(ok, 'feature/x', { 'tools/tests/a.mjs': 'assert_true(true)\n', 'tests/a/test_a.gd': 'func test_a():\n\tassert_true(x)\n', 'tests/a/test_a.gd.uid': 'u\n' });
    await assertCheck(ok, [], 0);
  });

  test('asserts falling over 10 % is a note', async () => {
    const big = `func test_a():\n${'\tassert_eq(a, b)\n'.repeat(10)}`;
    const small = `func test_a():\n${'\tassert_eq(a, b)\n'.repeat(5)}`;
    const dir = repo({ 'tests/a/test_a.gd': big, 'tests/a/test_a.gd.uid': 'u\n' });
    onBranch(dir, 'feature/x', { 'tests/a/test_a.gd': small });
    await assertCheck(dir, [], 0, /note: tests: tests\/a asserts fell over 10 %/);
  });
});

const HW_FLAG = `--allow-${'hw'}`;
const NET_FLAG = `--allow-${'network'}`;

describe('6.5 other invariants, through git', { concurrency: 4 }, () => {
  const failing = [
    ['gdlint disable', { 'src/a.gd': `# gdlint:  ${'disable'}=x\n`, 'src/a.gd.uid': 'u\n' }, /gdlint: disable/],
    ['a .gd with no .uid', { 'src/a.gd': 'extends Node\n' }, /src\/a\.gd was added without src\/a\.gd\.uid/],
    ['a .png with no .import', { 'assets/a.png': 'x' }, /assets\/a\.png was added without/],
    ['an orphan .uid', { 'src/b.gd.uid': 'u\n' }, /added with no src\/b\.gd/],
    ['a hardware flag in code', { 'tools/x.mjs': `run('${HW_FLAG}')\n` }, /--allow-hw or --allow-network/],
    ['a network flag in a workflow', { '.github/workflows/x.yml': `run: ${NET_FLAG}\n` }, /--allow-hw or --allow-network/],
    ['the art permission in code', { 'tools/x.sh': `WATTLANDS_ALLOW_ART=${1} x\n` }, /sets WATTLANDS_ALLOW_ART or FAL_KEY/],
    ['the art key in code', { 'tools/x.py': `FAL_${'KEY'}=abc\n` }, /sets WATTLANDS_ALLOW_ART or FAL_KEY/],
    ['a wall-clock budget outside quiet_tests', { 'tests/a/test_a.gd': 'func test_a():\n\tvar t := Time.get_ticks_usec()\n\tassert_eq(t, t)\n', 'tests/a/test_a.gd.uid': 'u\n' }, /Time\.get_ticks_usec outside quiet_tests/],
    ['committed CR', { 'tools/a.txt': 'a\r\nb\r\n' }, /added text holds CR/],
  ];
  for (const [name, files, pattern] of failing) {
    test(`${name} fails`, async () => {
      const dir = repo();
      onBranch(dir, 'feature/x', files);
      await assertCheck(dir, [], 1, pattern);
    });
  }

  const passing = [
    ['a .gd with its .uid', { 'src/a.gd': 'extends Node\n', 'src/a.gd.uid': 'u\n' }],
    ['a .gd under a .gdignore', { 'assets/x/tools_src/.gdignore': '', 'assets/x/tools_src/a.gd': 'extends Node\n' }],
    ['a .png with its .import', { 'assets/a.png': 'x', 'assets/a.png.import': 'y\n' }],
    ['the flags in Markdown and the gate tests', { 'docs/x.md': `${HW_FLAG}\n`, 'tools/tests/x.mjs': `${NET_FLAG}\n` }],
    ['the art variables in tools/art', { 'tools/art/x.mjs': `FAL_${'KEY'}=abc\nWATTLANDS_ALLOW_ART=${1}\n` }],
    ['a wall-clock budget in perf/', { 'tests/games/tank/perf/test_a.gd': 'func test_a():\n\tvar t := Time.get_ticks_usec()\n\tassert_eq(t, t)\n', 'tests/games/tank/perf/test_a.gd.uid': 'u\n' }],
    ['CR in a .ps1', { 'tools/a.ps1': 'a\r\nb\r\n' }],
    ['a binary file holding CR', { 'tools/a.bin': Buffer.from([0, 13, 10, 0, 13, 10]) }],
  ];
  for (const [name, files] of passing) {
    test(`${name} passes`, async () => {
      const dir = repo();
      onBranch(dir, 'feature/x', files);
      await assertCheck(dir, [], 0);
    });
  }

  test('a floor lower than at base fails; equal or higher passes', async () => {
    const dir = repo({ 'tests/green_count_floor.txt': '10\n' });
    sh(dir, 'checkout', '-q', '-b', 'queue');
    write(dir, { 'tests/green_count_floor.txt': '11\n' });
    commit(dir, 'chore: up');
    await assertCheck(dir, [], 0);
    write(dir, { 'tests/green_count_floor.txt': '9\n' });
    commit(dir, 'chore: down');
    await assertCheck(dir, [], 1, /green_count_floor\.txt fell 10 -> 9/);
    write(dir, { 'tests/green_count_floor.txt': null });
    commit(dir, 'chore: gone');
    await assertCheck(dir, [], 1, /green_count_floor\.txt fell 10 -> null/);
  });

  test('a duplicate class_name fails, though neither branch adds both; distinct names pass', async () => {
    const dir = repo({ 'src/a.gd': 'class_name Foo\n', 'src/a.gd.uid': 'u\n' });
    onBranch(dir, 'feature/x', { 'src/b.gd': 'class_name Foo\nextends Node\n', 'src/b.gd.uid': 'u\n' });
    await assertCheck(dir, [], 1, /class_name: Foo is declared in src\/a\.gd, src\/b\.gd/);
    write(dir, { 'src/b.gd': 'class_name Bar\nextends Node\n' });
    commit(dir, 'rename');
    await assertCheck(dir, [], 0);
  });

  test('a deleted source whose sidecar stays fails; deleted together passes; moved together passes', async () => {
    const base = { 'src/a.gd': 'class_name Aaa\n', 'src/a.gd.uid': 'u\n' };
    const dir = repo(base);
    onBranch(dir, 'feature/x', { 'src/a.gd': null });
    await assertCheck(dir, [], 1, /src\/a\.gd was deleted but src\/a\.gd\.uid stays/);
    write(dir, { 'src/a.gd.uid': null });
    commit(dir, 'both');
    await assertCheck(dir, [], 0);
    const moved = repo(base);
    sh(moved, 'checkout', '-q', '-b', 'feature/x');
    sh(moved, 'mv', 'src/a.gd', 'src/b.gd');
    sh(moved, 'mv', 'src/a.gd.uid', 'src/b.gd.uid');
    commit(moved, 'move');
    await assertCheck(moved, [], 0);
  });

  test('a non-empty stash list fails; empty passes', async () => {
    const dir = repo();
    await assertCheck(dir, [], 0);
    const head = sh(dir, 'rev-parse', 'HEAD');
    sh(dir, 'update-ref', '--create-reflog', 'refs/stash', head);
    await assertCheck(dir, [], 1, /never git stash/);
  });

  test('a file over 5 MB is a note', async () => {
    const dir = repo();
    onBranch(dir, 'feature/x', { 'assets/x/big.bin': Buffer.alloc(5 * 1024 * 1024 + 1, 1) });
    await assertCheck(dir, [], 0, /note: size: assets\/x\/big\.bin is 5\.0 MB/);
  });

  test('addons changed with no change under tests/ is a note', async () => {
    const dir = repo();
    onBranch(dir, 'feature/x', { 'addons/wattlands/a.txt': 'a\n' });
    await assertCheck(dir, [], 0, /note: tests: addons\/wattlands changed with no change under tests/);
  });

  test("the gate's own source passes its own text rules", () => {
    const own = ['tools/lib/gate.mjs', 'tools/lib/gate_core.mjs', 'tools/tests/gate.test.mjs', 'tools/tests/gate_core.test.mjs', 'tools/gate'];
    const added = new Map(own.map((f) => [f, fs.readFileSync(path.join(REPO, f), 'utf8').split('\n')]));
    assert.deepEqual(checkAddedText({ added, quietTests: REAL_MANIFEST.quiet_tests }), []);
  });
});

describe('usage and refusals', { concurrency: 4 }, () => {
  test('usage errors exit 2', async () => {
    const dir = repo();
    for (const args of [[], ['nope'], ['check', '--nope'], ['check', 'extra'], ['strict', '--lanes=gut'], ['strict', '--min-count=1'], ['strict', '--gdir=res://tests'], ['strict', '--games=all'],
      ['matrix'], ['floor'], ['pin-safety'], ['fast', '--shards=0'], ['fast', '--serial-gut'], ['stamp-ok'], ['wt-add', 'a']]) {
      const r = await gate(dir, args);
      assert.equal(r.code, 2, `${args.join(' ')}: ${r.stdout}${r.stderr}`);
    }
  });

  test('--help exits 0 and lists every command', async () => {
    const r = await gate(repo(), ['--help']);
    assert.equal(r.code, 0);
    for (const c of ['check', 'fast', 'strict', 'matrix', 'stamp-ok', 'floor', 'fmt', 'wt-add', 'wt-gc', 'pin-safety']) assert.match(r.stdout, new RegExp(c));
  });

  test('strict refuses a dirty tree with exit 3 before anything starts', async () => {
    const dir = repo();
    write(dir, { 'src/a.txt': 'a\n' });
    const r = await gate(dir, ['strict']);
    assert.equal(r.code, 3, r.stdout + r.stderr);
    assert.match(r.stderr, /clean tree/);
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'gate', 'strict.json')));
  });

  test('a second gate in one checkout exits 3; a dead holder is reaped', async () => {
    const dir = repo();
    const lock = path.join(dir, 'build', 'gate', 'run.lock');
    write(dir, { 'build/gate/run.lock': String(process.pid) });
    for (const args of [['fast'], ['strict'], ['floor', '--label=x'], ['matrix', '--game=x', '--jobs=1']]) {
      if (args[0] === 'matrix') write(dir, { 'tests/games/x/sim/run_sims.sh': 'exit 0\n' });
      const r = await gate(dir, args);
      assert.equal(r.code, 3, `${args.join(' ')}: ${r.stdout}${r.stderr}`);
      assert.match(r.stderr, /another gate runs in this checkout/);
    }
    assert.equal(fs.readFileSync(lock, 'utf8'), String(process.pid), "the holder's lock stays");
    fs.rmSync(path.join(dir, 'tests'), { recursive: true });
    const dead = spawnSync(process.execPath, ['-e', 'process.stdout.write(String(process.pid))'], { encoding: 'utf8' }).stdout;
    write(dir, { 'build/gate/run.lock': dead, 'build/gate/strict.json': '{}' });
    const r = await gate(dir, ['floor', '--label=x']);
    assert.doesNotMatch(r.stderr, /another gate/);
    assert.ok(!fs.existsSync(lock), 'reaped, then released at exit');
  });
});

describe('stamp-ok', { concurrency: 4 }, () => {
  function stamped(extra = {}) {
    const dir = repo();
    const tree = sh(dir, 'rev-parse', 'HEAD^{tree}');
    const stamp = { mode: 'fast', tree, pass: true, partial: false, dirty: false, ...extra };
    write(dir, { 'build/gate/fast.json': JSON.stringify(stamp), 'build/gate/matrix_tank.json': JSON.stringify(stamp) });
    return dir;
  }

  test('a clean pass on this tree stands, for fast and for a matrix', async () => {
    const dir = stamped();
    assert.equal((await gate(dir, ['stamp-ok', dir])).code, 0);
    assert.equal((await gate(dir, ['stamp-ok', dir, '--matrix=tank'])).code, 0);
  });

  test('another worktree with the same tree stands: the queue merge case', async () => {
    const dir = stamped();
    const here = repo();
    assert.equal(sh(here, 'rev-parse', 'HEAD^{tree}'), sh(dir, 'rev-parse', 'HEAD^{tree}'));
    assert.equal((await gate(here, ['stamp-ok', dir])).code, 0);
  });

  test('refuses another tree, a failed, partial or dirty stamp, and no stamp', async () => {
    const other = repo({ 'src/a.txt': 'other\n' });
    const r = await gate(other, ['stamp-ok', stamped()]);
    assert.equal(r.code, 1);
    assert.match(r.stdout, /tree .* is not/);
    for (const [extra, why] of [[{ pass: false }, /did not pass/], [{ partial: true }, /partial/], [{ dirty: true }, /dirty/]]) {
      const dir = stamped(extra);
      const v = await gate(dir, ['stamp-ok', dir]);
      assert.equal(v.code, 1, JSON.stringify(extra));
      assert.match(v.stdout, why);
    }
    const none = repo();
    assert.equal((await gate(none, ['stamp-ok', none])).code, 1);
    assert.equal((await gate(none, ['stamp-ok', stamped(), '--matrix=siege'])).code, 1, 'that game has no stamp');
  });
});

describe('floor', { concurrency: 4 }, () => {
  const JUNIT = '<testsuites name="GutTests" failures="0" tests="12"><testsuite name="tests/a/test_a.gd" tests="12" time="3.5"></testsuite></testsuites>';

  function floorRepo(stampOver = {}) {
    const dir = repo({ 'tests/green_count_floor.txt': '10\n' });
    const head = sh(dir, 'rev-parse', 'HEAD');
    write(dir, {
      'build/gate/strict.json': JSON.stringify({ mode: 'strict', sha: head, pass: true, partial: false, dirty: false, gut_total: 12, ...stampOver }),
      'build/junit.xml': JUNIT,
    });
    return dir;
  }
  const floorOf = (dir) => fs.readFileSync(path.join(dir, 'tests', 'green_count_floor.txt'), 'utf8').trim();

  test('a strict pass raises the floor, writes the weights and commits both, alone', async () => {
    const dir = floorRepo();
    const r = await gate(dir, ['floor', '--label=v0.9.1']);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.equal(floorOf(dir), '12');
    assert.equal(sh(dir, 'log', '-1', '--format=%s'), 'chore: the GUT floor rises to 12 (v0.9.1)');
    assert.deepEqual(sh(dir, 'show', '--name-only', '--format=', 'HEAD').split('\n').sort(), ['tests/green_count_floor.txt', 'tools/lib/gate_weights.json']);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(dir, 'tools', 'lib', 'gate_weights.json'), 'utf8')), { 'tests/a': 3.5 });
    assert.match(sh(dir, 'log', '-1', '--format=%b'), /Co-Authored-By: /);
    assert.equal(sh(dir, 'status', '--porcelain'), '');
  });

  test('at the same count it only refreshes the weights, and never lowers', async () => {
    const dir = floorRepo({ gut_total: 10 });
    assert.equal((await gate(dir, ['floor', '--label=x'])).code, 0);
    assert.equal(floorOf(dir), '10');
    assert.match(sh(dir, 'log', '-1', '--format=%s'), /weights refresh/);
  });

  for (const [name, over, why] of [
    ['a partial stamp', { partial: true }, /partial/],
    ['a failed stamp', { pass: false }, /did not pass/],
    ['a dirty stamp', { dirty: true }, /dirty/],
    ['a stale sha', { sha: 'f'.repeat(40) }, /the stamp is for/],
    ['a lower count', { gut_total: 9 }, /9 tests is below the floor 10/],
    ['a fast stamp', { mode: 'fast' }, /mode is fast/],
  ]) {
    test(`refuses ${name}`, async () => {
      const dir = floorRepo(over);
      const r = await gate(dir, ['floor', '--label=x']);
      assert.equal(r.code, 1, r.stdout + r.stderr);
      assert.match(r.stdout, why);
      assert.equal(floorOf(dir), '10');
    });
  }

  test('refuses a dirty tree with exit 3, and no stamp at all', async () => {
    const dir = floorRepo();
    write(dir, { 'src/a.txt': 'a\n' });
    assert.equal((await gate(dir, ['floor', '--label=x'])).code, 3);
    const none = repo();
    assert.equal((await gate(none, ['floor', '--label=x'])).code, 1);
  });
});

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
	var suites: String = ""
	var bad: String = str(cfg.get("forbidden_in", ""))
	var once: String = str(cfg.get("fail_once_in", ""))
	var code: int = 0
	for file: String in files:
		var rel: String = file.trim_prefix("res://")
		suites += '<testsuite name="%s" tests="1" time="0.1"></testsuite>' % rel
		if not bad.is_empty() and rel == bad:
			print("SCRIPT ERROR: planted")
		if not once.is_empty() and rel == once and not FileAccess.file_exists("res://build/failed_once.txt"):
			var mark: FileAccess = FileAccess.open("res://build/failed_once.txt", FileAccess.WRITE)
			mark.close()
			code = 1
	var seen: FileAccess = FileAccess.open(junit.get_base_dir().path_join("env.txt"), FileAccess.WRITE)
	seen.store_string(OS.get_environment("WATTLANDS_USERDATA_DIR"))
	seen.close()
	var f: FileAccess = FileAccess.open(junit, FileAccess.WRITE)
	f.store_string('<testsuites name="GutTests" failures="0" tests="%d">%s</testsuites>' % [files.size(), suites])
	f.close()
	print("= Run Summary")
	quit(code)
`;

describe('fast --lanes=gut on a scratch project', { skip: skipNoGodot }, () => {
  const lockDir = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-lock-'));
  temps.push(lockDir);
  const lockEnv = { WATTLANDS_GODOT_LOCK_DIR: lockDir, WATTLANDS_GODOT_LOCK_CAP: '2' };
  const TEST_SRC = 'func test_a():\n\tassert_eq(a, b)\n';

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
  const fast = (dir, ...args) => gate(dir, ['fast', '--lanes=gut', '--shards=2', '--games=all', ...args], { env: lockEnv, timeoutMs: 400_000 });
  const stampOf = (dir) => JSON.parse(fs.readFileSync(path.join(dir, 'build', 'gate', 'fast.json'), 'utf8'));

  test('every file runs once, each shard in its own user dir, and the stamp says partial', async () => {
    const dir = scratch();
    const r = await fast(dir);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /PASS gut:1 \d+s build\/gate\/fast\/gut_1\.log/);
    assert.match(r.stdout, /PASS gut:quiet /);
    const stamp = stampOf(dir);
    assert.equal(stamp.pass, true);
    assert.equal(stamp.partial, true, '--lanes marks the stamp, so floor and stamp-ok refuse it');
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

  test('a quiet test failing once reruns under a whole-machine lease; the second verdict stands', async () => {
    const dir = scratch({ fail_once_in: 'tests/games/tank/perf/test_q.gd' });
    const r = await fast(dir);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /once more inside a whole-machine lease/);
    const stamp = stampOf(dir);
    assert.equal(stamp.quiet_retried, true);
    assert.equal(stamp.pass, true);
    assert.equal(stamp.lanes.filter((l) => l.name === 'gut:quiet').length, 1);
  });

  test('a quiet test failing twice fails', async () => {
    const dir = scratch({ forbidden_in: 'tests/games/tank/perf/test_q.gd' });
    const r = await fast(dir);
    assert.equal(r.code, 1, r.stdout);
    assert.equal(stampOf(dir).quiet_retried, true);
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

// tools/run_game_sim's plan capture, then a report and an exit code from --exit=<n>.
const FAKE_SIM = `#!/usr/bin/env bash
if [ -n "\${WATTLANDS_SIM_PLAN:-}" ]; then
  printf '%s\\x1f' "$@" >>"$WATTLANDS_SIM_PLAN"
  printf '\\n' >>"$WATTLANDS_SIM_PLAN"
  exit 0
fi
code=0
report=""
for a in "$@"; do
  case "$a" in
    --report=*) report="\${a#--report=}" ;;
    --exit=*) code="\${a#--exit=}" ;;
  esac
done
mkdir -p "$(dirname "$report")"
printf '{"end_reason":"complete"}' >"$report"
printf '%s %s\\n' "$report" "\${WATTLANDS_USERDATA_DIR:-none}" >>build/pool_runs.txt
exit "$code"
`;

function simsScript(lines, { checker = 'exit 0' } = {}) {
  return `#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
cd "$repo"
out=build/mygame/sims
mkdir -p "$out"
run() { tools/run_game_sim --game=mygame "--report=$out/$1.json" "\${@:2}"; }
have() { [ -f "$out/$1.json" ]; }
printf '%s\\n' "$@" >>build/script_args.txt
${lines}
if [ "\${MYGAME_SKIP_CHECK:-0}" != "1" ]; then
  printf 'checked\\n' >>build/checked.txt
  ls "$out" >>build/checked.txt
  ${checker}
fi
`;
}

describe('matrix', { skip: !BASH && 'bash not found' }, () => {
  function matrixRepo(script) {
    const dir = repo({ 'project.godot': 'config_version=5\n', 'tests/games/mygame/sim/run_sims.sh': script, 'tools/run_game_sim': FAKE_SIM });
    fs.chmodSync(path.join(dir, 'tools', 'run_game_sim'), 0o755);
    fs.mkdirSync(path.join(dir, 'build'), { recursive: true });
    return dir;
  }
  const matrix = (dir, ...args) => gate(dir, ['matrix', '--game=mygame', ...args], { env: { WATTLANDS_GODOT_LOCK_DIR: path.join(dir, 'build', 'lock'), WATTLANDS_GODOT_LOCK_CAP: '4' }, timeoutMs: 300_000 });
  const stampOf = (dir) => JSON.parse(fs.readFileSync(path.join(dir, 'build', 'gate', 'matrix_mygame.json'), 'utf8'));
  const poolRuns = (dir) => fs.readFileSync(path.join(dir, 'build', 'pool_runs.txt'), 'utf8').trim().split('\n');

  test('no run_sims.sh prints "no matrix", exits 0 and writes no stamp', async () => {
    const dir = repo({ 'project.godot': '' });
    const r = await gate(dir, ['matrix', '--game=workout']);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /no matrix/);
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'gate', 'matrix_workout.json')));
  });

  test('plan, pool, check: every run once in its worker\'s user dir, then the checker over real reports', async () => {
    const dir = matrixRepo(simsScript('run a --seed=1\nrun b "--rider=x y"\nrun c --seed=2\nhave a || run a --seed=1\nrun d'));
    const r = await matrix(dir, '--jobs=2');
    assert.equal(r.code, 0, r.stdout + r.stderr);
    const runs = poolRuns(dir);
    assert.equal(runs.length, 4, 'a dependency planned twice runs once');
    for (const line of runs) {
      const userdata = line.slice(line.indexOf(' ') + 1).replaceAll('\\', '/');
      assert.match(userdata, /build\/gate\/matrix_mygame\/w[01]\/userdata$/);
      assert.ok(path.isAbsolute(userdata), userdata);
    }
    const stamp = stampOf(dir);
    assert.equal(stamp.pass, true);
    assert.equal(stamp.runs, 4);
    assert.equal(stamp.partial, false);
    assert.deepEqual(stamp.failed_runs, []);
    const checked = fs.readFileSync(path.join(dir, 'build', 'checked.txt'), 'utf8');
    assert.equal(checked.match(/checked/g).length, 1, 'the checker runs once, in phase 3');
    assert.match(checked, /a\.json/);
    assert.equal((await gate(dir, ['stamp-ok', dir, '--matrix=mygame'])).code, 0);
  });

  test('a run exiting 5 fails the verdict though the checker passes; the others still run', async () => {
    const dir = matrixRepo(simsScript('run a --exit=5\nrun b\nrun c'));
    const r = await matrix(dir, '--jobs=1');
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /FAIL pool/);
    assert.match(r.stdout, /a: exit 5/);
    assert.match(r.stdout, /PASS check_sims/);
    assert.equal(poolRuns(dir).length, 3);
    const stamp = stampOf(dir);
    assert.equal(stamp.pass, false);
    assert.deepEqual(stamp.failed_runs, ['a: exit 5']);
    assert.equal((await gate(dir, ['stamp-ok', dir, '--matrix=mygame'])).code, 1);
  });

  test('a failing checker fails the verdict though every run passed', async () => {
    const dir = matrixRepo(simsScript('run a', { checker: 'exit 7' }));
    const r = await matrix(dir);
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /PASS pool/);
    assert.match(r.stdout, /FAIL check_sims/);
  });

  test('--scenarios reach the script, and the stamp is partial', async () => {
    const dir = matrixRepo(simsScript('run a'));
    const r = await matrix(dir, '--scenarios=s1,s4');
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.deepEqual(fs.readFileSync(path.join(dir, 'build', 'script_args.txt'), 'utf8').trim().split('\n'), ['s1', 's4', 's1', 's4']);
    assert.equal(stampOf(dir).partial, true, 'a subset never stands in for the whole matrix');
    assert.equal((await gate(dir, ['stamp-ok', dir, '--matrix=mygame'])).code, 1);
  });

  test('a script that plans nothing fails', async () => {
    const dir = matrixRepo(simsScript('true'));
    const r = await matrix(dir);
    assert.equal(r.code, 1, r.stdout);
    assert.match(r.stdout, /FAIL plan/);
  });

  test('old reports are deleted first', async () => {
    const dir = matrixRepo(simsScript('run a'));
    write(dir, { 'build/mygame/sims/stale.json': '{}' });
    await matrix(dir);
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'mygame', 'sims', 'stale.json')));
  });
});

describe('fmt', () => {
  test('no changed .gd: nothing to do; lint dirs only', async () => {
    const dir = repo();
    onBranch(dir, 'feature/x', { 'docs/a.md': 'a\n', 'assets/x/tools_src/a.gd': 'extends Node\n' });
    const r = await gate(dir, ['fmt']);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /no changed \.gd/);
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
    const dead = Number(spawnSync(process.execPath, ['-e', 'process.stdout.write(String(process.pid))'], { encoding: 'utf8' }).stdout);
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
