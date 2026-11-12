// Tests for tools/godot.sh and tools/godot.ps1 (BRIEF 1 locks, BRIEF 2, BRIEF 7.1): each wrapper is
// started from an empty environment and runs a GDScript probe in a scratch project under build/,
// never in the main checkout. Real Godot runs queue on the machine-wide lock like any other run.
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { acquire, pidAlive } from '../lib/godot_lock.mjs';
import {
  TOOLS,
  TESTS_DIR,
  IS_WIN,
  BASH,
  GIT,
  godotBin,
  minimalEnv,
  runWrapper,
  makeScratchProject,
  parseProbe,
  powershellExe,
  runProc,
  rmQuiet,
  sleep,
} from './helpers.mjs';

const GODOT = godotBin();
const shells = [{ name: 'bash', id: 'bash', ok: Boolean(BASH) }];
if (IS_WIN) shells.push({ name: 'PowerShell 5.1', id: 'ps', ok: true });

const scratch = [];
let project = null;

before(() => {
  if (!GODOT) return;
  const probes = path.join(TESTS_DIR, 'probes');
  project = makeScratchProject('wrapper-probe', {
    'print_env.gd': fs.readFileSync(path.join(probes, 'print_env.gd'), 'utf8'),
    'never_quit.gd': fs.readFileSync(path.join(probes, 'never_quit.gd'), 'utf8'),
  });
  scratch.push(project);
});

after(() => {
  for (const d of scratch) rmQuiet(d);
});

const skipNoGodot = !GODOT && 'no Godot binary (tools/godot_bin.local or GODOT)';
const norm = (x) => (IS_WIN ? x.replaceAll(path.sep, '/').toLowerCase() : x);

/** Copies the wrapper files into <root>/tools so a test can run them outside this checkout. */
function copyWrappers(root) {
  for (const rel of ['godot.sh', 'godot.ps1', 'lib/godot_lock.mjs', 'lib/wrapper_common.ps1']) {
    const dst = path.join(root, 'tools', rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(path.join(TOOLS, rel), dst);
  }
}

for (const sh of shells) {
  describe(`${sh.name} wrapper`, { skip: !sh.ok && 'shell not available' }, () => {
    const probeArgs = () => ['--headless', '--path', project, '-s', 'res://print_env.gd'];

    test('sets both locks from an empty environment and passes everything after -- untouched', { skip: skipNoGodot }, async () => {
      const env = minimalEnv({ GODOT, WATTLANDS_PROBE_PASSTHROUGH: 'pass-through-ok' });
      const userArgs = ['--game=tank', '--allow-hw', '--lease=9', '-d', '--po=[{"a":5}]', 'two words'];
      const r = await runWrapper(sh.id, [...probeArgs(), '--', ...userArgs], { env });
      assert.equal(r.code, 0, r.stderr);
      const p = parseProbe(r.stdout);
      assert.match(r.stdout, /^PROBE DONE\r?$/m);
      assert.equal(p.WATTLANDS_NO_HW_CONTROL, '1');
      assert.equal(p.WATTLANDS_NO_NETWORK_INTEGRATIONS, '1');
      assert.equal(p.WATTLANDS_PROBE_PASSTHROUGH, 'pass-through-ok', 'other variables pass through unchanged');
      assert.deepEqual(JSON.parse(p.USER_ARGS), userArgs);
      assert.ok(
        norm(p.USER_DATA_DIR).startsWith(norm(`${path.join(project, '.userdata')}/`)),
        `user dir ${p.USER_DATA_DIR} is under the checkout's .userdata`,
      );
    });

    test('--allow-hw drops only the hardware lock', { skip: skipNoGodot }, async () => {
      const env = minimalEnv({ GODOT, WATTLANDS_NO_HW_CONTROL: '1', WATTLANDS_NO_NETWORK_INTEGRATIONS: '1' });
      const r = await runWrapper(sh.id, ['--allow-hw', ...probeArgs()], { env });
      assert.equal(r.code, 0, r.stderr);
      const p = parseProbe(r.stdout);
      assert.equal(p.WATTLANDS_NO_HW_CONTROL, '<unset>');
      assert.equal(p.WATTLANDS_NO_NETWORK_INTEGRATIONS, '1');
      assert.match(r.stderr, /hardware lock dropped/);
    });

    test('--allow-network drops only the network lock', { skip: skipNoGodot }, async () => {
      const env = minimalEnv({ GODOT, WATTLANDS_NO_HW_CONTROL: '1', WATTLANDS_NO_NETWORK_INTEGRATIONS: '1' });
      const r = await runWrapper(sh.id, [...probeArgs(), '--allow-network'], { env });
      assert.equal(r.code, 0, r.stderr);
      const p = parseProbe(r.stdout);
      assert.equal(p.WATTLANDS_NO_HW_CONTROL, '1');
      assert.equal(p.WATTLANDS_NO_NETWORK_INTEGRATIONS, '<unset>');
    });

    test('refuses -d and --debug before starting anything', async () => {
      for (const flag of ['-d', '--debug']) {
        const r = await runWrapper(sh.id, ['--headless', flag, '--version'], { env: minimalEnv({ GODOT: GODOT ?? 'godot' }) });
        assert.equal(r.code, 2, `${flag}: ${r.stderr}`);
        assert.match(r.stderr, /refusing to pass/);
        assert.doesNotMatch(r.stdout, /\d+\.\d+\.\d+\.stable/);
      }
    });

    test('--timeout kills the whole Godot process tree of a run that never quits (exit 124)', { skip: skipNoGodot }, async () => {
      // Its own lock dir: the 20 s bound is about the timeout, and a wait for a shared slot (other suites'
      // Godot runs in the gate's node lane) would count against it.
      const lockDir = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-wrapper-timeout-lock-'));
      scratch.push(lockDir);
      const env = minimalEnv({ GODOT, WATTLANDS_GODOT_LOCK_DIR: lockDir, WATTLANDS_GODOT_LOCK_CAP: '2' });
      const pidFile = path.join(project, `never_quit_${sh.id}.pid`);
      const args = ['--timeout=3', '--headless', '--path', project, '-s', 'res://never_quit.gd', '--', `--pid-file=${pidFile}`];
      const r = await runWrapper(sh.id, args, { env, timeoutMs: 60_000 });
      assert.equal(r.code, 124, r.stderr);
      assert.match(r.stderr, /godot run timeout/);
      assert.ok(r.ms < 20_000, `took ${r.ms} ms`);
      const pid = Number(fs.readFileSync(pidFile, 'utf8'));
      assert.ok(pid > 0, 'the probe recorded its pid');
      const end = Date.now() + 5000;
      while (pidAlive(pid) && Date.now() < end) await sleep(100);
      assert.equal(pidAlive(pid), false, `Godot process ${pid} is gone`);
    });

    test('--lease and --lock-timeout reach the lock (exit 75 on a lock wait timeout)', { skip: skipNoGodot }, async () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-wrapper-lock-'));
      scratch.push(dir);
      const holder = await acquire({ dir, cap: 2 });
      try {
        const env = minimalEnv({ GODOT, WATTLANDS_GODOT_LOCK_DIR: dir, WATTLANDS_GODOT_LOCK_CAP: '2' });
        const blocked = await runWrapper(sh.id, ['--lease=2', '--lock-timeout=1', '--headless', '--version'], { env });
        assert.equal(blocked.code, 75, blocked.stderr);
        assert.match(blocked.stderr, /^godot lock wait timeout\r?$/m);
        assert.doesNotMatch(blocked.stdout, /\d+\.\d+\.\d+\.stable/, 'Godot never started');
        const fits = await runWrapper(sh.id, ['--lease=1', '--lock-timeout=5', '--headless', '--version'], { env });
        assert.equal(fits.code, 0, fits.stderr);
        assert.match(fits.stdout, /^4\.7\.\d+/m);
      } finally {
        holder.release();
      }
    });

    test('finds the binary through tools/godot_bin.local when GODOT is unset', { skip: skipNoGodot }, async () => {
      // A scratch copy with its own godot_bin.local, so the case also runs where only GODOT is set (CI).
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-binlocal-'));
      scratch.push(tmp);
      copyWrappers(tmp);
      fs.writeFileSync(path.join(tmp, 'tools', 'godot_bin.local'), `${GODOT}
`);
      const r = await runWrapper(sh.id, ['--headless', '--version'], { env: minimalEnv(), cwd: tmp, tools: path.join(tmp, 'tools') });
      assert.equal(r.code, 0, r.stderr);
      assert.match(r.stdout, /^4\.7\.\d+/m);
    });

    test('in a git worktree, falls back to the main checkout\'s tools/godot_bin.local', { skip: (skipNoGodot || (!GIT && 'git not found')) }, async () => {
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-worktree-'));
      scratch.push(tmp);
      const main = path.join(tmp, 'main');
      const wt = path.join(tmp, 'wt');
      fs.mkdirSync(main);
      copyWrappers(main);
      fs.writeFileSync(path.join(main, '.gitignore'), 'tools/godot_bin.local\n.userdata/\n');
      fs.writeFileSync(path.join(main, 'tools', 'godot_bin.local'), `${GODOT}\n`);
      const git = (cwd, ...args) => {
        const r = spawnSync(GIT, ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', ...args], { cwd, encoding: 'utf8' });
        assert.equal(r.status, 0, r.stderr);
      };
      git(main, 'init', '-q');
      git(main, 'add', '.');
      git(main, 'commit', '-q', '-m', 'wrappers');
      git(main, 'worktree', 'add', '-q', wt);
      assert.equal(fs.existsSync(path.join(wt, 'tools', 'godot_bin.local')), false, 'the worktree has no godot_bin.local of its own');
      const r = await runWrapper(sh.id, ['--headless', '--version'], { env: minimalEnv(), cwd: wt, tools: path.join(wt, 'tools') });
      assert.equal(r.code, 0, r.stderr);
      assert.match(r.stdout, /^4\.7\.\d+/m);
    });

    test('WATTLANDS_USERDATA_DIR moves the user dir out of the checkout, creating it', { skip: skipNoGodot }, async () => {
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-userdata-'));
      scratch.push(tmp);
      const dir = path.join(tmp, 'shard_1', 'userdata');
      const r = await runWrapper(sh.id, probeArgs(), { env: minimalEnv({ GODOT, WATTLANDS_USERDATA_DIR: dir }) });
      assert.equal(r.code, 0, r.stderr);
      const seen = norm(parseProbe(r.stdout).USER_DATA_DIR);
      assert.ok(seen.startsWith(norm(`${dir}/`)), `user dir ${seen} is under ${dir}`);
      assert.ok(fs.statSync(dir).isDirectory());
    });

    // These use node as a stand-in for Godot (the first "Godot argument" is its script): no Godot process,
    // and the exact variables the wrapper exports, export runs included, which a probe can't reach.
    describe('the user dir variable', () => {
      const variable = IS_WIN ? 'APPDATA' : 'XDG_DATA_HOME';
      let root = null;
      let probe = null;
      let lockDir = null;

      before(() => {
        root = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-userdata-var-'));
        scratch.push(root);
        lockDir = path.join(root, 'lock');
        probe = path.join(root, 'print_var.cjs');
        fs.writeFileSync(probe, `process.stdout.write('VAR=' + (process.env.${variable} ?? '<unset>') + '\\n');\n`);
      });

      const runStandIn = (extraEnv, godotArgs, opts = {}) =>
        runWrapper(sh.id, [probe, ...godotArgs], {
          env: minimalEnv({
            GODOT: process.execPath,
            WATTLANDS_GODOT_LOCK_DIR: lockDir,
            WATTLANDS_GODOT_LOCK_CAP: '4',
            [variable]: 'outer-value',
            ...extraEnv,
          }),
          ...opts,
        });
      const varOf = (r) => /^VAR=(.*?)\r?$/m.exec(r.stdout)?.[1];

      test('unset or empty: <checkout>/.userdata, as before', async () => {
        const project = path.join(root, 'project');
        fs.mkdirSync(project, { recursive: true });
        for (const extra of [{}, { WATTLANDS_USERDATA_DIR: '' }]) {
          const r = await runStandIn(extra, ['--path', project]);
          assert.equal(r.code, 0, r.stderr);
          assert.equal(norm(varOf(r)), norm(path.join(project, '.userdata')));
        }
      });

      test('set: that dir, created, and the checkout gets no .userdata', async () => {
        const project = path.join(root, 'project_set');
        fs.mkdirSync(project, { recursive: true });
        const dir = path.join(root, 'set dir', 'userdata');
        const r = await runStandIn({ WATTLANDS_USERDATA_DIR: dir }, ['--path', project]);
        assert.equal(r.code, 0, r.stderr);
        assert.equal(norm(varOf(r)), norm(dir));
        assert.ok(fs.statSync(dir).isDirectory());
        assert.equal(fs.existsSync(path.join(project, '.userdata')), false);
      });

      test('relative: resolved against the caller, not against --path', async () => {
        const project = path.join(root, 'project_rel');
        const cwd = path.join(root, 'caller');
        fs.mkdirSync(project, { recursive: true });
        fs.mkdirSync(cwd, { recursive: true });
        const r = await runStandIn({ WATTLANDS_USERDATA_DIR: 'build/shard/userdata' }, ['--path', project], { cwd });
        assert.equal(r.code, 0, r.stderr);
        const want = path.join(cwd, 'build', 'shard', 'userdata');
        assert.equal(norm(varOf(r)), norm(want));
        assert.ok(fs.statSync(want).isDirectory());
      });

      test('export runs keep the real user dir, whatever the variable says', async () => {
        const dir = path.join(root, 'never_made');
        for (const flag of ['--export-release', '--export-debug', '--export-pack', '--export-patch']) {
          const r = await runStandIn({ WATTLANDS_USERDATA_DIR: dir }, [flag, 'Windows Desktop', 'x.exe']);
          assert.equal(r.code, 0, r.stderr);
          assert.equal(varOf(r), 'outer-value', flag);
        }
        assert.equal(fs.existsSync(dir), false);
      });
    });

    test('called directly from a PowerShell prompt: keeps --, rejoins -x=res://y, leaves the session env alone', {
      skip: (sh.id !== 'ps' && 'PowerShell only') || skipNoGodot,
    }, async () => {
      const ps1 = path.join(TOOLS, 'godot.ps1').replaceAll("'", "''");
      const proj = project.replaceAll("'", "''");
      const command = [
        "$env:APPDATA = 'C:\\session-appdata'",
        "$env:WATTLANDS_NO_HW_CONTROL = 'session-value'",
        `& '${ps1}' --headless --path '${proj}' -s res://print_env.gd -gdir=res://tests -- --game=tank -gdir=res://x --only=a,b 'q r'`,
        "Write-Output \"EXIT=$LASTEXITCODE\"",
        "Write-Output \"AFTER_APPDATA=$env:APPDATA\"",
        "Write-Output \"AFTER_HW=$env:WATTLANDS_NO_HW_CONTROL\"",
      ].join('; ');
      const r = await runProc(powershellExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], {
        env: minimalEnv({ GODOT }),
      });
      assert.match(r.stdout, /^EXIT=0\r?$/m, r.stderr);
      const p = parseProbe(r.stdout);
      assert.deepEqual(JSON.parse(p.USER_ARGS), ['--game=tank', '-gdir=res://x', '--only=a,b', 'q r']);
      assert.equal(p.WATTLANDS_NO_HW_CONTROL, '1');
      assert.match(r.stdout, /^AFTER_APPDATA=C:\\session-appdata\r?$/m, 'APPDATA restored in the session');
      assert.match(r.stdout, /^AFTER_HW=session-value\r?$/m, 'the session keeps its own lock value');
    });

    test('exits 127 with a clear message when no binary can be found', async () => {
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-nobin-'));
      scratch.push(tmp);
      copyWrappers(tmp);
      const r = await runWrapper(sh.id, ['--headless', '--version'], {
        env: minimalEnv({}, { withGit: false }),
        cwd: tmp,
        tools: path.join(tmp, 'tools'),
      });
      assert.equal(r.code, 127, r.stderr);
      assert.match(r.stderr, /no Godot binary/);
    });
  });
}
