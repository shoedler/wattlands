// tools/gate check, SPEC_GATES 6.2 and 6.3 safety pins and --contributor, on temp git repos.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { REAL_MANIFEST, PIN_MANIFEST, sh, write, repo, commit, onBranch, gate, check, assertCheck, CHECKER, pinnedRepo, pin, tests } from './gate_helpers.mjs';

describe('6.2 and 6.3 pins, through git', { concurrency: 8 }, () => {
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

  test('a first-line return in a pinned function fails, committed or not', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    const neutered = CHECKER.replace('{\n', '{\n  return ok();\n');
    onBranch(dir, 'game/tank-x', { 'tests/games/tank/sim/check_sims.mjs': neutered });
    await assertCheck(dir, [], 1, /append-only pin: .*checkS4: a line was added above/);
    const work = pinnedRepo();
    await pin(work);
    sh(work, 'checkout', '-q', '-b', 'game/tank-x');
    write(work, { 'tests/games/tank/sim/check_sims.mjs': neutered });
    await assertCheck(work, [], 1, /checkS4: a line was added above/);
  });

  test('a deleted pins file fails, on a lead branch and with --allow too', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'queue', { 'tools/lib/safety_pins.json': null }, 'chore: gone');
    await assertCheck(dir, [], 1, /safety_pins\.json was deleted/);
    await assertCheck(dir, ['--allow=tools/lib/safety_pins.json', '--allow=**'], 1, /safety_pins\.json was deleted/);
    const branch = pinnedRepo();
    await pin(branch);
    onBranch(branch, 'tooling/x', { 'tools/lib/safety_pins.json': null });
    await assertCheck(branch, ['--allow=tools/lib/safety_pins.json'], 1, /safety_pins\.json was deleted/);
  });

  test('a merge that drops the pins fails: `-s ours` hides the side that held them from plain git log', async () => {
    const dir = pinnedRepo();
    sh(dir, 'branch', 'queue/x');
    await pin(dir);
    sh(dir, 'checkout', '-q', 'queue/x');
    sh(dir, 'merge', '-q', '-s', 'ours', '--no-edit', 'main');
    await assertCheck(dir, [], 1, /safety_pins\.json was deleted/);
  });

  test('a branch behind the pinning commit still gets the note, since it never had them', async () => {
    const dir = pinnedRepo();
    sh(dir, 'branch', 'game/tank-old');
    await pin(dir);
    sh(dir, 'checkout', '-q', 'game/tank-old');
    write(dir, { 'src/games/tank/a.txt': 'a\n' });
    commit(dir, 'tank: x');
    await assertCheck(dir, [], 0, /not pinned yet/);
  });

  test('a hollowed pins file fails on a lead branch: {} , no files, a rewritten hash', async () => {
    for (const hollow of [
      () => ({}),
      (p) => ({ ...p, files: {} }),
      (p) => ({ ...p, globs: [] }),
      (p) => ({ ...p, blocks: [] }),
      (p) => ({ ...p, files: { ...p.files, 'tools/godot.sh': 'f'.repeat(64) } }),
      (p) => ({ ...p, pinned_at: 'f'.repeat(40) }),
    ]) {
      const dir = pinnedRepo();
      await pin(dir);
      const pins = JSON.parse(fs.readFileSync(path.join(dir, 'tools', 'lib', 'safety_pins.json'), 'utf8'));
      onBranch(dir, 'queue', { 'tools/lib/safety_pins.json': JSON.stringify(hollow(pins)) }, 'chore: pins');
      await assertCheck(dir, [], 1, /safety pin: /);
    }
  });

  test('a pins file that does not parse fails', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'queue', { 'tools/lib/safety_pins.json': '{nope' }, 'chore: pins');
    await assertCheck(dir, [], 1, /does not parse/);
  });

  test('a manifest that grew after the pin asks the lead to re-pin', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'queue', { 'tools/lib/gate_manifest.json': JSON.stringify({ ...PIN_MANIFEST, safety_pin_globs: [...PIN_MANIFEST.safety_pin_globs, 'src/new/**'] }), 'src/new/a.txt': 'a\n' }, 'chore: manifest');
    await assertCheck(dir, [], 1, /the lead re-pins/);
    await pin(dir);
    await assertCheck(dir, [], 0);
  });

  test('a real re-pin by the lead passes', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'queue', { 'tools/godot.sh': 'stronger\n' }, 'platform: stronger');
    await assertCheck(dir, [], 1, /tools\/godot\.sh changed/);
    await pin(dir);
    await assertCheck(dir, [], 0);
  });

  test('the safety pins file itself is denied to tooling branches', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'tooling/x', { 'tools/lib/safety_pins.json': '{"globs":[],"files":{},"blocks":[]}\n' });
    await assertCheck(dir, [], 1, /safety_pins\.json: denied/);
  });
});

describe('--contributor', { concurrency: 8 }, () => {
  test('a contributor branch: maintainer-only files and pins are named for review, not failed', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'fix-the-lobby', { 'tools/godot.sh': 'stronger\n', 'README.md': 'better\n' }, 'fix');
    await assertCheck(dir, [], 1, /tools\/godot\.sh changed/);
    await assertCheck(dir, ['--contributor'], 0, /maintainer review: safety pin: tools\/godot\.sh changed .*a maintainer reads this change/);
    await assertCheck(dir, ['--contributor'], 0, /maintainer review: ownership: README\.md: a maintainer lands this file/);
  });

  test('a contributor branch: a tampered pins file still fails', async () => {
    const dir = pinnedRepo();
    await pin(dir);
    onBranch(dir, 'hollow-the-pins', { 'tools/lib/safety_pins.json': '{"globs":[],"files":{},"blocks":[]}\n' }, 'hollow');
    const r = await assertCheck(dir, ['--contributor'], 1, /safety pin: /);
    assert.ok(r !== null);
  });

  test('a contributor branch: never-edit paths and falling test counts still fail', async () => {
    const dir = repo({ 'docs/BRIEF.md': 'brief\n', 'tests/a/test_a.gd': tests(2), 'tests/a/test_a.gd.uid': 'u\n' });
    onBranch(dir, 'fix-the-brief', { 'docs/BRIEF.md': 'mine\n' }, 'edit');
    await assertCheck(dir, ['--contributor'], 1, /never edited/);
    const fewer = repo({ 'tests/a/test_a.gd': tests(2), 'tests/a/test_a.gd.uid': 'u\n' });
    onBranch(fewer, 'fewer-tests', { 'tests/a/test_a.gd': tests(1) }, 'less');
    await assertCheck(fewer, ['--contributor'], 1, /the total fell 2 -> 1/);
  });
});
