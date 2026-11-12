// tools/gate matrix: the plan, the pool with a fake run_game_sim, the checker's evidence, and the real scripts' plans.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { BASH, REPO } from './helpers.mjs';
import { parsePlan } from '../lib/gate_core.mjs';
import { REAL_MANIFEST, temps, write, repo, commit, gate, check, tests } from './gate_helpers.mjs';

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

function simsScript(lines, { checker = "printf 'PASS S1 fake\\n'" } = {}) {
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
printf '[%s][%s][%s]\\n' "\${MYGAME_SEEDS:-}" "\${MYGAME_SIMS:-}" "\${MYGAME_FIT:-}" >>build/script_env.txt
${lines}
if [ "\${MYGAME_SKIP_CHECK:-0}" != "1" ]; then
  printf 'checked\\n' >>build/checked.txt
  ls "$out" >>build/checked.txt
  ${checker}
fi
`;
}

// Each test has its own repo and lock dir (matrixEnv), so they run side by side.
describe('matrix', { skip: !BASH && 'bash not found', concurrency: 4 }, () => {
  function matrixRepo(script, manifest = REAL_MANIFEST) {
    const dir = repo({ 'project.godot': 'config_version=5\n', 'tests/games/mygame/sim/run_sims.sh': script, 'tools/run_game_sim': FAKE_SIM }, manifest);
    fs.chmodSync(path.join(dir, 'tools', 'run_game_sim'), 0o755);
    commit(dir, 'executable');
    fs.mkdirSync(path.join(dir, 'build'), { recursive: true });
    return dir;
  }
  const matrixEnv = (dir, extra = {}) => ({ WATTLANDS_GODOT_LOCK_DIR: path.join(dir, 'build', 'lock'), WATTLANDS_GODOT_LOCK_CAP: '4', ...extra });
  const matrix = (dir, ...args) => gate(dir, ['matrix', '--game=mygame', ...args], { env: matrixEnv(dir), timeoutMs: 300_000 });
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
    assert.equal(stamp.checker_rows, 1);
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'gate', 'matrix_mygame', 'plan.txt')), 'no plan file outlives its phase');
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'gate', 'matrix_mygame', 'plan_check.txt')));
    assert.ok(fs.existsSync(path.join(dir, 'build', 'gate', 'matrix_mygame', 'plan_used.txt')));
    const checked = fs.readFileSync(path.join(dir, 'build', 'checked.txt'), 'utf8');
    assert.equal(checked.match(/checked/g).length, 1, 'the checker runs once, in phase 3');
    assert.match(checked, /a\.json/);
    assert.equal((await gate(dir, ['stamp-ok', dir, '--matrix=mygame'])).code, 0);
  });

  test("the stamp keeps each run's time, and the next matrix starts the longest first; the default is a worker per slot", async () => {
    const dir = matrixRepo(simsScript('run a --seed=1\nrun b --seed=2\nrun c --seed=3'));
    const first = await matrix(dir);
    assert.equal(first.code, 0, first.stdout + first.stderr);
    const stamp = stampOf(dir);
    assert.equal(stamp.jobs, 3, 'cap 4, 3 runs: one worker per run');
    assert.deepEqual(Object.keys(stamp.run_ms).sort(), ['a', 'b', 'c']);
    // Pretend c was the long one and b the short one last time.
    write(dir, { 'build/gate/matrix_mygame.json': JSON.stringify({ ...stamp, run_ms: { a: 2000, b: 1000, c: 9000 } }), 'build/pool_runs.txt': null });
    const second = await matrix(dir, '--jobs=1');
    assert.equal(second.code, 0, second.stdout + second.stderr);
    assert.deepEqual(poolRuns(dir).map((l) => path.basename(l.split(' ')[0], '.json')), ['c', 'a', 'b']);
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

  test('a checker that printed no row fails: exit 0 is no evidence', async () => {
    const dir = matrixRepo(simsScript('run a', { checker: 'true' }));
    const r = await matrix(dir);
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /FAIL check_sims/);
    assert.match(r.stdout, /no PASS row: the checker did not run/);
    assert.equal((await gate(dir, ['stamp-ok', dir, '--matrix=mygame'])).code, 1);
  });

  test('no run_sims.sh fails for a game the manifest requires, and writes no stamp', async () => {
    const dir = repo({ 'project.godot': '' });
    const r = await gate(dir, ['matrix', '--game=tank']);
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /requires a matrix of tank/);
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'gate', 'matrix_tank.json')));
  });

  test("a plan below the manifest's minimum fails; a subset does not answer to it; stamp-ok compares too", async () => {
    const manifest = { ...REAL_MANIFEST, matrix_required_rows: { mygame: ['S1'] }, matrix_min_runs: { mygame: 2 } };
    const few = matrixRepo(simsScript('run a'), manifest);
    const r = await matrix(few);
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /FAIL plan/);
    assert.match(r.stdout, /below the manifest's 2/);
    assert.equal((await gate(few, ['stamp-ok', few, '--matrix=mygame'])).code, 1);
    const subset = matrixRepo(simsScript('run a'), manifest);
    assert.equal((await matrix(subset, '--scenarios=s1')).code, 0);
    const dir = matrixRepo(simsScript('run a\nrun b'), manifest);
    const v = await matrix(dir);
    assert.equal(v.code, 0, v.stdout + v.stderr);
    assert.deepEqual(stampOf(dir).checker_passed, ['S1']);
    assert.equal((await gate(dir, ['stamp-ok', dir, '--matrix=mygame'])).code, 0);
    const file = path.join(dir, 'build', 'gate', 'matrix_mygame.json');
    const good = stampOf(dir);
    fs.writeFileSync(file, JSON.stringify({ ...good, runs: 1 }));
    assert.match((await gate(dir, ['stamp-ok', dir, '--matrix=mygame'])).stdout, /below the manifest's 2/);
    fs.writeFileSync(file, JSON.stringify({ ...good, checker_passed: [] }));
    assert.match((await gate(dir, ['stamp-ok', dir, '--matrix=mygame'])).stdout, /its checker did not pass S1/);
  });

  test('the real scripts plan at least the runs the manifest asks, and the real checkers hold its rows', () => {
    for (const [id, minRuns] of Object.entries(REAL_MANIFEST.matrix_min_runs)) {
      const upper = id.toUpperCase();
      const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'wgate-plan-'));
      temps.push(scratch);
      const plan = path.join(scratch, 'plan.txt').replaceAll('\\', '/');
      fs.writeFileSync(plan, '');
      const env = { ...process.env, WATTLANDS_SIM_PLAN: plan, [`${upper}_SKIP_CHECK`]: '1', [`${upper}_SIMS_OUT`]: path.join(scratch, 'out').replaceAll('\\', '/') };
      const r = spawnSync(BASH, [`tests/games/${id}/sim/run_sims.sh`], { cwd: REPO, env, encoding: 'utf8', windowsHide: true, timeout: 120_000 });
      assert.equal(r.status, 0, `${id}: ${r.stdout}${r.stderr}`);
      assert.ok(parsePlan(fs.readFileSync(plan, 'utf8')).length >= minRuns, `${id} plans fewer than ${minRuns} runs`);
      const checker = fs.readFileSync(path.join(REPO, `tests/games/${id}/sim/check_sims.mjs`), 'utf8');
      for (const row of REAL_MANIFEST.matrix_required_rows[id]) {
        assert.match(checker, new RegExp(`\\b${row}: check|\\['${row}', check|'${row}'`), `${id} has no row ${row}`);
      }
    }
  });

  test('a SKIP row fails a full matrix; a required row must be PASS', async () => {
    const skip = matrixRepo(simsScript('run a', { checker: "printf 'PASS S1 a\\nSKIP S4 no reports\\n'" }));
    const r = await matrix(skip);
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /SKIP rows in a full matrix: S4/);
    const safety = matrixRepo(simsScript('run a'), { ...REAL_MANIFEST, matrix_required_rows: { mygame: ['S4'] } });
    const v = await matrix(safety);
    assert.equal(v.code, 1, v.stdout + v.stderr);
    assert.match(v.stdout, /the required row S4 is missing/);
  });

  test('nothing in the shell skips the checker or narrows the runs', async () => {
    const dir = matrixRepo(simsScript('run a'));
    const r = await gate(dir, ['matrix', '--game=mygame'], { env: matrixEnv(dir, { MYGAME_SKIP_CHECK: '1', MYGAME_SEEDS: '1', MYGAME_SIMS: 's1', MYGAME_FIT: '0', MYGAME_SIMS_OUT: 'build/elsewhere' }), timeoutMs: 300_000 });
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(fs.readFileSync(path.join(dir, 'build', 'checked.txt'), 'utf8'), /checked/, 'phase 3 ran its checker');
    assert.deepEqual([...new Set(fs.readFileSync(path.join(dir, 'build', 'script_env.txt'), 'utf8').trim().split('\n'))], ['[][][]']);
    assert.equal(stampOf(dir).partial, false);
  });

  test('--scenarios reach the script, and the stamp is partial', async () => {
    const dir = matrixRepo(simsScript('run a'));
    const r = await matrix(dir, '--scenarios=s1,s4');
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.deepEqual(fs.readFileSync(path.join(dir, 'build', 'script_args.txt'), 'utf8').trim().split('\n'), ['s1', 's4', 's1', 's4']);
    assert.equal(stampOf(dir).partial, true, 'a subset never stands in for the whole matrix');
    assert.equal((await gate(dir, ['stamp-ok', dir, '--matrix=mygame'])).code, 1);
    const skip = matrixRepo(simsScript('run a', { checker: "printf 'PASS S1 a\\nSKIP S4 not this subset\\n'" }));
    assert.equal((await matrix(skip, '--scenarios=s1')).code, 0, 'a subset may skip what it did not run');
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
