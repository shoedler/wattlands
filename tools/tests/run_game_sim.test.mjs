// Tests for tools/run_game_sim and tools/run_game_sim.ps1 (BRIEF 1 locks, BRIEF 3.6): the wrappers'
// structure, their refusals, and (with a Godot binary) the whole chain wrapper -> godot wrapper ->
// tools/sdk/run_game_sim_main.gd, checked with --echo-args from an empty environment: the locks are
// set, --mock-trainer is added, relative --report and --override paths resolve against the caller's
// directory, and JSON and rider specs reach Godot unchanged. The session itself (GameSimRunner) is
// sdk-runtime's and is covered by tests/sdk/ and tests/games/_template/integration/.
// The real-Godot cases need this checkout imported (tools/godot.sh --headless --path . --import).
import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { REPO, TOOLS, IS_WIN, BASH, GIT, godotBin, minimalEnv, powershellExe, runProc, rmQuiet } from './helpers.mjs';

const GODOT = godotBin();
const temps = [];
after(() => {
  for (const d of temps) rmQuiet(d);
});

const read = (rel) => fs.readFileSync(path.join(REPO, rel), 'utf8');

const shells = [{ name: 'bash', ok: Boolean(BASH) }];
if (IS_WIN) shells.push({ name: 'PowerShell', ok: Boolean(powershellExe()) });

function runSim(shell, args, opts) {
  if (shell === 'bash') return runProc(BASH, [path.join(TOOLS, 'run_game_sim').replaceAll('\\', '/'), ...args], opts);
  return runProc(powershellExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(TOOLS, 'run_game_sim.ps1'), ...args], opts);
}

/** The JSON array after "run_game_sim: args " in stdout. */
function echoedArgs(stdout) {
  const line = stdout.split(/\r?\n/).find((l) => l.startsWith('run_game_sim: args '));
  assert.ok(line, `no args line in:\n${stdout}`);
  return JSON.parse(line.slice('run_game_sim: args '.length));
}

describe('structure', () => {
  test('tools/run_game_sim is a bash script with a shebang, committed executable', () => {
    const sh = read('tools/run_game_sim');
    assert.match(sh, /^#!\/usr\/bin\/env bash\n/);
    if (GIT) {
      const r = spawnSync(GIT, ['-C', REPO, 'ls-files', '-s', 'tools/run_game_sim'], { encoding: 'utf8' });
      if (r.stdout.trim()) assert.match(r.stdout, /^100755 /, 'git add --chmod=+x tools/run_game_sim');
    }
  });

  test('tools/run_game_sim.ps1 keeps CRLF', () => {
    const ps = read('tools/run_game_sim.ps1');
    assert.ok(ps.includes('\r\n') && !/[^\r]\n/.test(ps), 'CRLF only');
  });

  for (const [file, godot] of [['tools/run_game_sim', 'godot.sh'], ['tools/run_game_sim.ps1', 'godot.ps1']]) {
    test(`${file} sets both locks, adds --mock-trainer and runs the entry script through ${godot}`, () => {
      const text = read(file);
      assert.match(text, /WATTLANDS_NO_HW_CONTROL['"]? *=? *['"]?1/);
      assert.match(text, /WATTLANDS_NO_NETWORK_INTEGRATIONS['"]? *=? *['"]?1/);
      assert.ok(text.includes(godot), godot);
      assert.ok(text.includes('tools/sdk/run_game_sim_main.gd'));
      assert.ok(text.includes("'--headless'") || text.includes('--headless '), '--headless');
      assert.ok(text.includes('--mock-trainer=erg'), 'a valid profile, so nothing in the process reads a bare flag as a spec');
      assert.ok(text.includes('--caller-cwd='));
      assert.doesNotMatch(text, /FAL_KEY|WATTLANDS_ALLOW_ART/, 'the art variables are never touched');
    });
  }

  test('the entry script exists and hands over to GameSimCli.main (script errors counted)', () => {
    const main = read('tools/sdk/run_game_sim_main.gd');
    assert.match(main, /^extends SceneTree$/m);
    assert.match(main, /GameSimCli\.new\(\)\.main\(OS\.get_cmdline_user_args\(\), root\)/);
  });
});

describe('refusals before Godot starts', () => {
  for (const sh of shells) {
    for (const flag of ['--allow-hw', '--allow-network']) {
      test(`${sh.name}: ${flag} is refused with exit 2`, { skip: !sh.ok && `no ${sh.name}` }, async () => {
        const r = await runSim(sh.name, ['--game=_template', '--report=r.json', flag], { env: minimalEnv(), cwd: os.tmpdir() });
        assert.equal(r.code, 2, r.stderr);
        assert.match(r.stderr, new RegExp(`${flag} is refused`));
      });
    }
  }
});

describe('through Godot', () => {
  for (const sh of shells) {
    const skip = (!GODOT && 'no Godot binary (tools/godot_bin.local or GODOT)') || (!sh.ok && `no ${sh.name}`);

    test(`${sh.name}: the locks, --mock-trainer and resolved paths reach the entry script`, { skip, timeout: 600_000 }, async () => {
      const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-run-game-sim-'));
      temps.push(cwd);
      fs.writeFileSync(path.join(cwd, 'over.json'), '{"default.json": {"nudge_pct": 4}}');
      const options = '{"boosts":false,"track":800}';
      const players = '[{"work_offset":5},{"work_offset":-10}]';
      const r = await runSim(
        sh.name,
        ['--echo-args', '--game=_template', '--content=short', '--players=2', '--bots=1', '--rider=erg+cadence_drop:rpm=40,at_s=1200',
          '--rider=erg:compliance=0.9', '--report=out/r.json', '--override=over.json', `--options=${options}`,
          `--player-options=${players}`, '--seed=3', '--sim-speed=200', '--unverified', '--mock-trainer=false',
          '--caller-cwd=/elsewhere', '--godot-timeout=300'],
        { env: minimalEnv(), cwd, timeoutMs: 600_000 },
      );
      assert.equal(r.code, 0, r.stderr + r.stdout);
      const args = echoedArgs(r.stdout);
      const slash = (p) => p.replaceAll('\\', '/');
      assert.deepEqual(args, [
        '--game=_template', '--content=short', '--players=2', '--bots=1', '--rider=erg+cadence_drop:rpm=40,at_s=1200',
        '--rider=erg:compliance=0.9', `--report=${slash(path.join(cwd, 'out', 'r.json'))}`,
        `--override=${slash(path.join(cwd, 'over.json'))}`, `--options=${options}`, `--player-options=${players}`,
        '--seed=3', '--sim-speed=200', '--unverified',
      ]);
      assert.match(r.stdout, /run_game_sim: locks WATTLANDS_NO_HW_CONTROL=1 WATTLANDS_NO_NETWORK_INTEGRATIONS=1 mock-trainer=erg/,
        "the wrapper's own --mock-trainer=erg and --caller-cwd replace the caller's");
    });

    test(`${sh.name}: a missing --report, an unknown flag and a bad value exit 2, each named (OWNERSHIP SIM1)`, { skip, timeout: 600_000 }, async () => {
      const r = await runSim(sh.name, ['--game=_template', '--player=2', '--players=0', '--godot-timeout=300'], { env: minimalEnv(), cwd: os.tmpdir(), timeoutMs: 600_000 });
      assert.equal(r.code, 2, r.stdout + r.stderr);
      assert.match(r.stderr, /--report is required/);
      assert.match(r.stderr, /unknown flag --player\b/);
      assert.match(r.stderr, /--players=0: an integer 1\.\.8/);
    });
  }

  // The CLI end to end (BRIEF 3.6, 7.1): a real _template session, twice with one seed. It needs
  // sdk-runtime's GameSimRunner, so it skips itself while that is still the W0 stub (W1 worktrees).
  const sh = shells.find((s) => s.ok);
  const skipReal = (!GODOT && 'no Godot binary (tools/godot_bin.local or GODOT)') || (!sh && 'no shell');
  test(`${sh ? sh.name : 'bash'}: a real _template session writes its report and FIT, deterministically`, { skip: skipReal, timeout: 1_200_000 }, async (t) => {
    const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-run-game-sim-real-'));
    temps.push(cwd);
    const flags = ['--game=_template', '--content=short', '--players=1', '--bots=1', '--rider=erg', '--sim-speed=1000', '--seed=4', '--godot-timeout=600'];
    const reports = [];
    for (const name of ['a', 'b']) {
      const r = await runSim(sh.name, [...flags, `--report=out/${name}.json`], { env: minimalEnv(), cwd, timeoutMs: 900_000 });
      if (r.code === 2 && /not implemented/.test(r.stderr)) {
        t.skip("sdk-runtime's GameSimRunner is still the W0 stub");
        return;
      }
      assert.equal(r.code, 0, r.stderr + r.stdout);
      assert.match(r.stdout, /run_game_sim: end_reason=complete/);
      const report = JSON.parse(fs.readFileSync(path.join(cwd, 'out', `${name}.json`), 'utf8'));
      assert.equal(report.end_reason, 'complete');
      assert.equal(report.fit_paths.length, 1, 'one FIT per human slot, none for the bot');
      assert.ok(fs.existsSync(path.join(cwd, 'out', 'fit', `${name}_slot0.fit`)));
      reports.push(report);
    }
    assert.equal(reports[0].deterministic_hash, reports[1].deterministic_hash, 'same arguments and seed, same hash');
  });

  // lead W2 round 2: Workout VO2 in HOST (two human slots over loopback plus a bot), twice with one
  // seed through the real wrapper: the same deterministic_hash, and the same report apart from the
  // paths and the wall-clock meta the hash leaves out (so nothing it hashes hides a difference).
  test(`${sh ? sh.name : 'bash'}: Workout VO2 in HOST is deterministic`, { skip: skipReal, timeout: 1_200_000 }, async (t) => {
    const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-run-game-sim-host-'));
    temps.push(cwd);
    const flags = ['--game=workout', '--content=vo2', '--players=2', '--bots=1', '--rider=erg', '--sim-speed=100000', '--seed=42', '--godot-timeout=900'];
    const reports = [];
    for (const name of ['a', 'b']) {
      const r = await runSim(sh.name, [...flags, `--report=out/${name}.json`], { env: minimalEnv(), cwd, timeoutMs: 1_000_000 });
      if (r.code === 2 && /not implemented/.test(r.stderr)) {
        t.skip("sdk-runtime's GameSimRunner is still the W0 stub");
        return;
      }
      assert.equal(r.code, 0, r.stderr + r.stdout);
      const report = JSON.parse(fs.readFileSync(path.join(cwd, 'out', `${name}.json`), 'utf8'));
      assert.equal(report.role, 'HOST');
      assert.equal(report.end_reason, 'complete');
      assert.equal(report.slots.length, 3);
      assert.equal(report.clients.length, 1, 'one loopback client');
      assert.equal(report.fit_paths.length, 2, 'a FIT per human slot');
      reports.push(report);
    }
    assert.equal(reports[0].deterministic_hash, reports[1].deterministic_hash, 'same arguments and seed, same hash');
    const strip = (rep) => {
      const c = structuredClone(rep);
      delete c.fit_paths;
      delete c.meta;
      delete c.args.report;
      return c;
    };
    assert.deepEqual(strip(reports[0]), strip(reports[1]), 'the reports match apart from paths and meta');
  });
});
