// tools/gate check, SPEC_GATES 6.4 test counts (GUT and Node) and asserts, on temp git repos.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { sh, write, repo, commit, onBranch, assertCheck, tests } from './gate_helpers.mjs';

describe('6.4 test counts, through git', { concurrency: 8 }, () => {
  test('a falling total fails; rising passes', async () => {
    const dir = repo({ 'tests/a/test_a.gd': tests(2), 'tests/a/test_a.gd.uid': 'uid\n' });
    onBranch(dir, 'game/tank-x', { 'tests/a/test_a.gd': tests(1) }, 'platform: fewer');
    await assertCheck(dir, [], 1, /the total fell 2 -> 1/);
    const ok = repo({ 'tests/a/test_a.gd': tests(2), 'tests/a/test_a.gd.uid': 'uid\n' });
    onBranch(ok, 'game/tank-x', { 'tests/a/test_a.gd': tests(3) }, 'platform: more');
    await assertCheck(ok, [], 0);
  });

  test('renaming a test file out of test_*.gd fails, with no trailer', async () => {
    const dir = repo({ 'tests/a/test_a.gd': tests(2), 'tests/a/test_a.gd.uid': 'u\n' });
    sh(dir, 'checkout', '-q', '-b', 'feature/x');
    sh(dir, 'mv', 'tests/a/test_a.gd', 'tests/a/a_checks.gd');
    sh(dir, 'mv', 'tests/a/test_a.gd.uid', 'tests/a/a_checks.gd.uid');
    commit(dir, 'rename');
    const r = await assertCheck(dir, [], 1, /the total fell 2 -> 0/);
    assert.match(r.stdout, /tests\/a fell 2 -> 0/);
    assert.match(r.stdout, /tests\/a\/test_a\.gd lost tests: 2 -> 0/);
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

  describe('the merge-revert exemption', () => {
    // main holds a real merge that brought tests/a/test_b.gd.
    function landed() {
      const dir = repo({ 'tests/a/test_a.gd': tests(2), 'tests/a/test_a.gd.uid': 'u\n', 'tests/c/test_c.gd': tests(1), 'tests/c/test_c.gd.uid': 'u\n' });
      onBranch(dir, 'topic', { 'tests/a/test_b.gd': tests(2), 'tests/a/test_b.gd.uid': 'u\n' });
      sh(dir, 'checkout', '-q', 'main');
      sh(dir, 'merge', '-q', '--no-ff', 'topic', '-m', 'Merge topic: y');
      return { dir, merge: sh(dir, 'rev-parse', 'HEAD') };
    }

    test('a real revert of a merge is excused; a revert mixed with other work is not', async () => {
      const { dir } = landed();
      sh(dir, 'checkout', '-q', '-b', 'queue');
      sh(dir, 'revert', '-m', '1', '--no-edit', 'HEAD');
      await assertCheck(dir, [], 0, /in a merge revert/);
      write(dir, { 'src/a.txt': 'a\n' });
      commit(dir, 'other work');
      await assertCheck(dir, [], 1, /the total fell/);
    });

    test('the same revert still answers to a later commit having moved other lines', async () => {
      const { dir } = landed();
      write(dir, { 'tests/a/test_a.gd': `# moved\n${tests(2)}` });
      commit(dir, 'tests: a comment');
      sh(dir, 'checkout', '-q', '-b', 'queue');
      sh(dir, 'revert', '-m', '1', '--no-edit', sh(dir, 'rev-parse', 'HEAD^'));
      await assertCheck(dir, [], 0, /in a merge revert/);
    });

    test('the subject proves nothing: no sha, no merge, or another diff all fail', async () => {
      const remove = { 'tests/c/test_c.gd': null, 'tests/c/test_c.gd.uid': null };
      const plain = landed();
      onBranch(plain.dir, 'fix/x', remove, 'Revert "Merge nothing"');
      await assertCheck(plain.dir, [], 1, /the total fell/);
      const notMerge = landed();
      onBranch(notMerge.dir, 'fix/x', remove, `Revert "Merge nothing"\n\nThis reverts commit ${sh(notMerge.dir, 'rev-parse', 'HEAD^1')}.`);
      await assertCheck(notMerge.dir, [], 1, /the total fell/);
      const other = landed();
      onBranch(other.dir, 'fix/x', remove, `Revert "Merge topic: y"\n\nThis reverts commit ${other.merge}, reversing changes.`);
      await assertCheck(other.dir, [], 1, /the total fell/);
      const unknown = landed();
      onBranch(unknown.dir, 'fix/x', remove, `Revert "Merge x"\n\nThis reverts commit ${'a'.repeat(40)}.`);
      await assertCheck(unknown.dir, [], 1, /the total fell/);
    });
  });

  describe('Node test counts', () => {
    const FILE = 'tools/tests/a.test.mjs';
    const nodeTests = (n) => Array.from({ length: n }, (_, i) => `test('t${i}', () => {});\n`).join('');

    test('the total falling fails; a trailer excuses it; test.skip reads as a fall', async () => {
      const dir = repo({ [FILE]: nodeTests(2) });
      onBranch(dir, 'fix/x', { [FILE]: nodeTests(1) });
      await assertCheck(dir, [], 1, /the Node total fell 2 -> 1 with no "Test-Removal: node/);
      const skip = repo({ [FILE]: nodeTests(2) });
      onBranch(skip, 'fix/x', { [FILE]: `${nodeTests(1)}test.skip('t1', () => {});\n` });
      await assertCheck(skip, [], 1, /the Node total fell 2 -> 1/);
      const ok = repo({ [FILE]: nodeTests(2) });
      sh(ok, 'checkout', '-q', '-b', 'fix/x');
      write(ok, { [FILE]: nodeTests(1) });
      sh(ok, 'add', '-A');
      sh(ok, 'commit', '-q', '-m', 'work', '-m', 'Test-Removal: node the tool went');
      await assertCheck(ok, [], 0, /Node total fell 2 -> 1, Test-Removal: the tool went/);
    });

    test("a game's Node tests count; a file outside the suites does not", async () => {
      const game = repo({ 'tests/games/tank/sim/a.test.mjs': nodeTests(1) });
      onBranch(game, 'fix/x', { 'tests/games/tank/sim/a.test.mjs': null });
      await assertCheck(game, [], 1, /the Node total fell 1 -> 0/);
      const outside = repo({ 'src/a.test.mjs': nodeTests(1) });
      onBranch(outside, 'fix/x', { 'src/a.test.mjs': null });
      await assertCheck(outside, [], 0);
    });

    test('a suite emptied fails though the total holds; moving tests between suites is a note', async () => {
      const dir = repo({ [FILE]: nodeTests(1), 'tools/art/b.test.mjs': nodeTests(1) });
      onBranch(dir, 'fix/x', { [FILE]: nodeTests(2), 'tools/art/b.test.mjs': null });
      await assertCheck(dir, [], 1, /the Node suite tools\/art held 1 tests and holds none/);
      const moved = repo({ [FILE]: nodeTests(1), 'tools/art/b.test.mjs': nodeTests(2) });
      onBranch(moved, 'fix/x', { [FILE]: nodeTests(2), 'tools/art/b.test.mjs': nodeTests(1) });
      await assertCheck(moved, [], 0, /the Node suite tools\/art fell 2 -> 1/);
    });
  });

  test('a .gutconfig.json fails, tracked, untracked or ignored, and --allow does not excuse it', async () => {
    const tracked = repo();
    onBranch(tracked, 'fix/x', { '.gutconfig.json': '{}' });
    await assertCheck(tracked, [], 1, /gut config: \.gutconfig\.json exists/);
    await assertCheck(tracked, ['--allow=**'], 1, /gut config/);
    const untracked = repo();
    write(untracked, { '.gutconfig.json': '{}' });
    await assertCheck(untracked, [], 1, /gut config/);
    const ignored = repo({ '.gitignore': 'build/\n.gutconfig.json\n' });
    write(ignored, { '.gutconfig.json': '{}' });
    await assertCheck(ignored, [], 1, /gut config/);
    const nested = repo();
    onBranch(nested, 'fix/x', { 'tests/a/.gutconfig.json': '{}' });
    await assertCheck(nested, [], 1, /gut config: tests\/a\/\.gutconfig\.json exists/);
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
