// tools/gate check, SPEC_GATES 6.5 and the other invariants (floor, strict's range, sidecars, stash), on temp git repos.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { REPO } from './helpers.mjs';
import { checkAddedText } from '../lib/gate_core.mjs';
import { changedSince, fastGutSelection, parseCli, runCheck, strictBase } from '../lib/gate.mjs';
import { touchedGames } from '../lib/gate_core.mjs';
import { REAL_MANIFEST, temps, sh, write, initRepo, repo, commit, onBranch, gate, check, assertCheck, NO_PINS_MANIFEST, tests, HW_FLAG, NET_FLAG } from './gate_helpers.mjs';

describe('6.5 other invariants, through git', { concurrency: 8 }, () => {
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
    await assertCheck(dir, [], 1, /green_count_floor\.txt fell 11 -> 9/);
    write(dir, { 'tests/green_count_floor.txt': null });
    commit(dir, 'chore: gone');
    await assertCheck(dir, [], 1, /green_count_floor\.txt fell 11 -> null/);
  });

  test('a floor down in two steps fails against the highest one, though the last step rises', async () => {
    const dir = repo({ 'tests/green_count_floor.txt': '100\n' });
    sh(dir, 'checkout', '-q', '-b', 'queue');
    write(dir, { 'tests/green_count_floor.txt': '50\n' });
    commit(dir, 'chore: down');
    sh(dir, 'checkout', '-q', 'main');
    sh(dir, 'merge', '-q', '--ff-only', 'queue');
    write(dir, { 'tests/green_count_floor.txt': '60\n' });
    commit(dir, 'chore: up a little');
    await assertCheck(dir, [], 1, /fell 100 -> 60/);
  });

  test('a floor raised on the side a merge dropped still counts: `-s ours` hides it from plain git log', async () => {
    const dir = repo({ 'tests/green_count_floor.txt': '100\n' }, NO_PINS_MANIFEST);
    sh(dir, 'branch', 'queue/x');
    write(dir, { 'tests/green_count_floor.txt': '200\n' });
    const raised = commit(dir, 'chore: the floor rises');
    sh(dir, 'checkout', '-q', 'queue/x');
    sh(dir, 'merge', '-q', '-s', 'ours', '--no-edit', 'main');
    await assertCheck(dir, [], 1, /fell 200 -> 100/);
    assert.equal(strictBase(parseCli(['check', `--project=${dir}`])), sh(dir, 'rev-parse', `${raised}^`), "strict's range holds the raise and the merge");
  });

  test('strict: the commit that touched the floor is inside its check range', () => {
    const files = { 'tests/green_count_floor.txt': '100\n', 'tests/a/test_a.gd': tests(3), 'tests/a/test_a.gd.uid': 'u\n', 'tests/a/test_b.gd': tests(2), 'tests/a/test_b.gd.uid': 'u\n' };
    const dir = repo(files, NO_PINS_MANIFEST);
    const before = sh(dir, 'rev-parse', 'HEAD');
    sh(dir, 'checkout', '-q', '-b', 'queue');
    write(dir, { 'tests/green_count_floor.txt': '1\n', 'tests/a/test_b.gd': null, 'tests/a/test_b.gd.uid': null });
    commit(dir, 'chore: the floor falls');
    const o = parseCli(['check', `--project=${dir}`]);
    assert.equal(strictBase(o), before);
    const c = runCheck(o, { base: strictBase(o) });
    assert.match(c.problems.join('\n'), /the total fell 5 -> 3/);
    assert.match(c.problems.join('\n'), /tests\/a fell 5 -> 3/);
    assert.match(c.problems.join('\n'), /fell 100 -> 1/);
  });

  test('strict: a floor raised honestly passes its own check; no floor file starts at HEAD', () => {
    const dir = repo({ 'tests/green_count_floor.txt': '10\n', 'tests/a/test_a.gd': tests(3), 'tests/a/test_a.gd.uid': 'u\n' }, NO_PINS_MANIFEST);
    sh(dir, 'checkout', '-q', '-b', 'queue');
    write(dir, { 'tests/green_count_floor.txt': '11\n' });
    commit(dir, 'chore: up');
    const o = parseCli(['check', `--project=${dir}`]);
    assert.deepEqual(runCheck(o, { base: strictBase(o) }).problems, []);
    const none = repo({}, NO_PINS_MANIFEST);
    assert.equal(strictBase(parseCli(['check', `--project=${none}`])), 'HEAD');
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-root-'));
    temps.push(root);
    initRepo(root, { 'tests/green_count_floor.txt': '10\n' }, NO_PINS_MANIFEST);
    assert.equal(strictBase(parseCli(['check', `--project=${root}`])), sh(root, 'rev-parse', 'HEAD'), 'a root commit has no parent');
  });

  test('moving a platform file into a game selects the platform', () => {
    const dir = repo({ 'addons/wattlands/core/x.gd': `${'a line of code\n'.repeat(20)}`, 'src/games/tank/game.json': '{}\n' });
    sh(dir, 'checkout', '-q', '-b', 'game/tank-x');
    sh(dir, 'mv', 'addons/wattlands/core/x.gd', 'src/games/tank/x.gd');
    commit(dir, 'tank: moved');
    const changed = changedSince(parseCli(['check', `--project=${dir}`]), 'main');
    assert.ok(changed.includes('addons/wattlands/core/x.gd'), changed.join());
    assert.equal(touchedGames(changed, ['siege', 'tank']).platform, true);
  });

  test("fast's GUT selection: --games widens it, --games=all and a cross-game reference run everything", () => {
    const ids = ['fishing', 'siege', 'tank', 'workout'];
    const o = (games) => ({ ...parseCli(['fast', ...(games ? [`--games=${games}`] : [])]), project: REPO });
    const tankOnly = { changed: ['src/games/tank/a.gd'], crossRefs: [] };
    assert.deepEqual(fastGutSelection(o(null), ids, tankOnly), { all: false, games: ['tank'], reason: 'the change touches only the own paths of tank' });
    assert.deepEqual(fastGutSelection(o('siege'), ids, tankOnly).games, ['siege', 'tank'], 'a wider --games adds its games');
    assert.equal(fastGutSelection(o('siege'), ids, tankOnly).all, false);
    assert.deepEqual(fastGutSelection(o('fishing,siege,workout'), ids, tankOnly), { all: true, games: ids, reason: '--games=fishing,siege,workout' }, 'every game named is everything');
    assert.deepEqual(fastGutSelection(o('all'), ids, tankOnly), { all: true, games: ids, reason: '--games=all' });
    assert.equal(fastGutSelection(o('siege'), ids, { changed: ['tools/lib/x.mjs'], crossRefs: [] }).all, true, '--games never narrows a platform change');
    const crossed = fastGutSelection(o(null), ids, { changed: ['src/games/tank/a.gd'], crossRefs: [{ file: 'src/games/tank/a.gd', line: 1, game: 'siege', text: 'SiegeHud' }] });
    assert.equal(crossed.all, true);
    assert.match(crossed.reason, /cross-game/);
  });

  test('a new cross-game reference fails check; one the base already held is a note', async () => {
    const games = { 'src/games/tank/game.json': '{"id":"tank"}\n', 'src/games/siege/game.json': '{"id":"siege"}\n' };
    const dir = repo(games);
    onBranch(dir, 'game/tank-x', { 'src/games/tank/hud.gd': 'extends Node\n# SiegeHud is theirs\nvar id := "siege"\n', 'src/games/tank/hud.gd.uid': 'uid://a\n' });
    await assertCheck(dir, [], 0, /check: PASS/);
    write(dir, { 'src/games/tank/hud.gd': 'extends Node\nvar other: SiegeHud\n' });
    const r = await assertCheck(dir, [], 1, /FAIL cross-game: src\/games\/tank\/hud\.gd:2 names siege \(SiegeHud\)/);
    assert.doesNotMatch(r.stdout, /note: cross-game/);
    const old = repo({ ...games, 'tests/games/siege/x/test_a.gd': 'func test_a():\n\tload("res://src/games/tank/a.gd")\n' });
    onBranch(old, 'game/tank-y', { 'content/tank/b.json': '{}\n' });
    await assertCheck(old, [], 0, /note: cross-game: tests\/games\/siege\/x\/test_a\.gd:2 names tank \(res:\/\/src\/games\/tank\) \(already at the base/);
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
    const gateTests = fs.readdirSync(path.join(REPO, 'tools', 'tests')).filter((f) => /^gate(?:_\w+)?(?:\.test)?\.mjs$/.test(f)).map((f) => `tools/tests/${f}`);
    assert.ok(gateTests.length >= 10, `the gate's test files: ${gateTests.join(', ')}`);
    const own = ['tools/lib/gate.mjs', 'tools/lib/gate_core.mjs', ...gateTests, 'tools/gate'];
    const added = new Map(own.map((f) => [f, fs.readFileSync(path.join(REPO, f), 'utf8').split('\n')]));
    assert.deepEqual(checkAddedText({ added, quietTests: REAL_MANIFEST.quiet_tests }), []);
  });
});
