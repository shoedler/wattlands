// tools/gate check, SPEC_GATES 6.1 ownership, on temp git repos.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { REAL_MANIFEST, sh, write, repo, commit, onBranch, gate, check, assertCheck, tests } from './gate_helpers.mjs';

describe('6.1 ownership, through git', { concurrency: 8 }, () => {
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
