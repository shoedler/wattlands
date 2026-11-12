// tools/gate stamp-ok and floor: which stamps stand for a tree, and what raises the floor.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { REAL_MANIFEST, sh, write, repo, onBranch, gate, NO_PINS_MANIFEST, pin, tests } from './gate_helpers.mjs';

describe('stamp-ok', { concurrency: 8 }, () => {
  function stamped(extra = {}) {
    const dir = repo();
    const tree = sh(dir, 'rev-parse', 'HEAD^{tree}');
    const stamp = { mode: 'fast', tree, pass: true, partial: false, dirty: false, gut_total: 5, runs: 3, checker_rows: 2, allow: [], games: [], gut_selection: { all: true, games: [] }, ...extra };
    write(dir, { 'build/gate/fast.json': JSON.stringify(stamp), 'build/gate/matrix_tank.json': JSON.stringify(stamp) });
    return dir;
  }

  test('a clean pass on this tree stands, for fast and for a matrix', async () => {
    const dir = stamped({ runs: REAL_MANIFEST.matrix_min_runs.tank, checker_passed: REAL_MANIFEST.matrix_required_rows.tank });
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

  test('a stamp short of evidence is refused, and a field missing counts as the bad value', async () => {
    for (const [extra, args, why] of [
      [{ gut_total: null }, [], /counted no GUT tests/],
      [{ gut_total: 0 }, [], /counted 0 GUT tests/],
      [{ allow: ['docs/games/**'] }, [], /ran with docs\/games/],
      [{ partial: undefined }, [], /partial/],
      [{ dirty: undefined }, [], /dirty/],
      [{ pass: 'yes' }, [], /did not pass/],
      [{ partial: true, partial_reasons: ['--base=HEAD is not main'] }, [], /--base=HEAD is not main/],
      [{ runs: 0 }, ['--matrix=tank'], /ran no sims/],
      [{ checker_rows: 0 }, ['--matrix=tank'], /no evidence that the checker ran/],
    ]) {
      const dir = stamped(extra);
      const v = await gate(dir, ['stamp-ok', dir, ...args]);
      assert.equal(v.code, 1, JSON.stringify(extra));
      assert.match(v.stdout, why);
    }
  });

  test('a dirty project is refused: its HEAD tree is not what it holds', async () => {
    const dir = stamped();
    write(dir, { 'src/a.txt': 'uncommitted\n' });
    const v = await gate(dir, ['stamp-ok', dir]);
    assert.equal(v.code, 1);
    assert.match(v.stdout, /this checkout is dirty/);
  });

  test("a GUT selection stands only for a tree that needs no more of it; so do the stamp's sim and e2e games", async () => {
    const games = { 'src/games/tank/game.json': '{"id":"tank"}\n', 'src/games/siege/game.json': '{"id":"siege"}\n', 'src/games/fishing/game.json': '{"id":"fishing"}\n' };
    const tankOnly = { all: false, games: ['tank'], skipped_games: ['fishing', 'siege'], skipped_files: 3, reason: 'the change touches only the own paths of tank' };
    const branch = (files) => {
      const dir = repo(games);
      onBranch(dir, 'game/tank-x', files);
      return dir;
    };
    const stampIn = (dir, extra) => {
      const stamp = { mode: 'fast', tree: sh(dir, 'rev-parse', 'HEAD^{tree}'), pass: true, partial: false, dirty: false, gut_total: 5, allow: [], games: ['tank'], gut_selection: tankOnly, ...extra };
      write(dir, { 'build/gate/fast.json': JSON.stringify(stamp) });
    };
    const tank = branch({ 'src/games/tank/a.gd': 'x\n' });
    stampIn(tank);
    const ok = await gate(tank, ['stamp-ok', tank]);
    assert.equal(ok.code, 0, ok.stdout);
    assert.match(ok.stdout, /note: its GUT run left out fishing, siege/);

    const platform = branch({ 'src/games/tank/a.gd': 'x\n', 'addons/wattlands/core/x.gd': 'y\n' });
    stampIn(platform, { games: ['fishing', 'siege', 'tank'] });
    const r = await gate(platform, ['stamp-ok', platform]);
    assert.equal(r.code, 1, r.stdout);
    assert.match(r.stdout, /left out the GUT files of fishing, siege, and this tree needs every file \(addons\/wattlands\/core\/x\.gd is outside/);

    const both = branch({ 'src/games/tank/a.gd': 'x\n', 'content/siege/b.json': '{}\n' });
    stampIn(both, { games: ['siege', 'tank'] });
    assert.match((await gate(both, ['stamp-ok', both])).stdout, /its GUT run left out siege, which this tree touches/);
    stampIn(both, { games: ['tank'], gut_selection: { all: true, games: ['fishing', 'siege', 'tank'] } });
    assert.match((await gate(both, ['stamp-ok', both])).stdout, /ran no sim or e2e of siege/);

    stampIn(tank, { gut_selection: undefined });
    assert.match((await gate(tank, ['stamp-ok', tank])).stdout, /records no GUT selection/);
  });

  test('--allow and --allow-pin: the same exceptions stand, others and a matrix do not', async () => {
    const extra = { partial: true, partial_reasons: ['--allow=docs/games/**'], allow: ['docs/games/**'], allow_globs: ['docs/games/**'], allow_pins: [] };
    const dir = stamped(extra);
    const plain = await gate(dir, ['stamp-ok', dir]);
    assert.equal(plain.code, 1);
    assert.match(plain.stdout, /partial \(--allow=docs\/games\/\*\*\)/);
    const same = await gate(dir, ['stamp-ok', dir, '--allow=docs/games/**']);
    assert.equal(same.code, 0, same.stdout);
    assert.match(same.stdout, /note: it ran with docs\/games\/\*\*, as stamp-ok was told/);
    assert.match((await gate(dir, ['stamp-ok', dir, '--allow=docs/**'])).stdout, /not the exceptions stamp-ok was given/);
    assert.match((await gate(dir, ['stamp-ok', dir, '--allow=docs/games/**', '--allow-pin=a.mjs:f'])).stdout, /not the exceptions/);
    const lanes = stamped({ ...extra, partial_reasons: ['--lanes=gut', '--allow=docs/games/**'] });
    assert.match((await gate(lanes, ['stamp-ok', lanes, '--allow=docs/games/**'])).stdout, /more than its exceptions \(--lanes=gut\)/);
    const matrix = stamped({ ...extra, runs: 3, checker_rows: 2 });
    assert.match((await gate(matrix, ['stamp-ok', matrix, '--matrix=tank', '--allow=docs/games/**'])).stdout, /partial/, 'a matrix takes no exceptions');
  });

  test('a quiet rerun stands, and is shown', async () => {
    const dir = stamped({ quiet_retried: true, quiet_retried_tests: ['tests/x/test_x.gd::test_budget'] });
    const v = await gate(dir, ['stamp-ok', dir]);
    assert.equal(v.code, 0, v.stdout);
    assert.match(v.stdout, /note: gut:quiet passed only on its rerun .*test_budget/);
  });
});

describe('floor', { concurrency: 8 }, () => {
  const JUNIT = '<testsuites name="GutTests" failures="0" tests="12"><testsuite name="tests/a/test_a.gd" tests="12" time="3.5"></testsuite></testsuites>';

  function floorRepo(stampOver = {}) {
    const dir = repo({ 'tests/green_count_floor.txt': '10\n' }, NO_PINS_MANIFEST);
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

  test('refuses while the manifest asks for pins and there are none', async () => {
    const dir = repo({ 'tests/green_count_floor.txt': '10\n' });
    const r = await gate(dir, ['floor', '--label=x']);
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /run tools\/gate pin-safety first/);
  });

  test('refuses a dirty tree with exit 3, and no stamp at all', async () => {
    const dir = floorRepo();
    write(dir, { 'src/a.txt': 'a\n' });
    assert.equal((await gate(dir, ['floor', '--label=x'])).code, 3);
    const none = repo();
    assert.equal((await gate(none, ['floor', '--label=x'])).code, 1);
  });
});
