// tools/lib/run_tests.mjs: the opt-in flags that let the gate run a step's parts at once
// (--node-jobs, --sim-jobs, --static-jobs), narrow the node step to what a change can affect
// (--node-since) and let suites keep verdict caches (--node-cache). The literal run passes none of them.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { GIT, REPO, TOOLS, rmQuiet, runProc } from './helpers.mjs';
import {
  NODE_SUITES,
  NODE_SUITE_GAME_INPUTS,
  changedPaths,
  gameOfPath,
  lintChunks,
  mergeLintRuns,
  parseArgs,
  planNodeSuites,
  runPool,
  suiteTestFiles,
} from '../lib/run_tests.mjs';

const RUN_TESTS = path.join(TOOLS, 'lib', 'run_tests.mjs');
const IDS = ['fishing', 'siege', 'tank', 'workout'];

function tmp(name) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `wattlands-rt-${name}-`));
}

function write(root, files) {
  for (const [rel, text] of Object.entries(files)) {
    const f = path.join(root, rel);
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, text);
  }
}

describe('the flags', () => {
  test('every new flag is off by default, so the literal run is unchanged', () => {
    const o = parseArgs([]);
    assert.equal(o.nodeJobs, 1);
    assert.equal(o.simJobs, 1);
    assert.equal(o.staticJobs, 1);
    assert.equal(o.nodeSince, null);
    assert.equal(o.nodeCache, false);
  });

  test('they parse', () => {
    const o = parseArgs(['--node-jobs=6', '--sim-jobs=4', '--static-jobs=3', '--node-since=main', '--node-cache']);
    assert.deepEqual([o.nodeJobs, o.simJobs, o.staticJobs, o.nodeSince, o.nodeCache], [6, 4, 3, 'main', true]);
  });

  test('a bad value is a usage error (exit 2) and names the flag', () => {
    for (const bad of ['--node-jobs=0', '--sim-jobs=x', '--static-jobs=1.5', '--node-jobs=65', '--node-cache=1', '--node-since=']) {
      const r = spawnSync(process.execPath, [RUN_TESTS, bad], { encoding: 'utf8' });
      assert.equal(r.status, 2, `${bad}: ${r.stdout}${r.stderr}`);
      assert.match(r.stderr, new RegExp(bad.split('=')[0]), bad);
    }
  });
});

describe('runPool', () => {
  test('results come back in item order, at most `jobs` run at once', async () => {
    let live = 0;
    let most = 0;
    const out = await runPool([30, 5, 20, 1, 10, 2], 3, async (ms, i) => {
      live += 1;
      most = Math.max(most, live);
      await new Promise((r) => setTimeout(r, ms));
      live -= 1;
      return i * 10;
    });
    assert.deepEqual(out, [0, 10, 20, 30, 40, 50]);
    assert.equal(most, 3);
  });

  test('jobs 1 is one after another, in order; no items is no call', async () => {
    const order = [];
    await runPool(['a', 'b', 'c'], 1, async (x) => {
      order.push(`start ${x}`);
      await new Promise((r) => setTimeout(r, 2));
      order.push(`end ${x}`);
    });
    assert.deepEqual(order, ['start a', 'end a', 'start b', 'end b', 'start c', 'end c']);
    assert.deepEqual(await runPool([], 4, async () => assert.fail('called')), []);
  });
});

describe('planNodeSuites', () => {
  const units = [...NODE_SUITES, 'tests/games/fishing', 'tests/games/tank'].map((name) => ({ name, kind: 'suite', files: null }));
  units.push({ name: 'tools/art/pixelate_e2e.mjs', kind: 'extra', files: null });
  const toolsTests = ['gate.test.mjs', 'gate_core.test.mjs', 'godot_lock.test.mjs', 'run_game_sim.test.mjs', 'run_tests.test.mjs', 'wrappers.test.mjs'];
  const plan = (changed) => planNodeSuites({ changed, units, gameIds: IDS, suiteFiles: (s) => (s === 'tools/tests' ? toolsTests : []) });
  const names = (p) => p.units.map((u) => (u.files ? `${u.name}[${u.files.join(' ')}]` : u.name));

  test('a path outside every game runs everything, whole', () => {
    for (const p of ['tools/lib/x.mjs', 'addons/wattlands/a.gd', 'assets/_shared/audio/a.wav', 'src/games/_template/a.gd', 'docs/THIRD_PARTY_NOTICES.txt', 'project.godot', 'src/games/newgame/a.gd']) {
      const r = plan(['src/games/tank/a.gd', p]);
      assert.equal(r.all, true, p);
      assert.deepEqual(names(r), units.map((u) => u.name), p);
    }
  });

  test('docs Markdown alone runs nothing', () => {
    const r = plan(['docs/changelog.d/tank.md', 'docs/decisions/tank.md']);
    assert.equal(r.all, false);
    assert.deepEqual(r.units, []);
  });

  test("Tank code runs Tank's suite, what boots the project, and not the other games or the scratch-repo files", () => {
    const r = plan(['src/games/tank/rules/a.gd', 'content/tank/drill.json', 'docs/changelog.d/tank.md']);
    assert.deepEqual(names(r), ['tools/tests[run_game_sim.test.mjs]', 'tests/games/tank', 'tools/art/pixelate_e2e.mjs']);
    assert.ok(r.skipped.some((s) => s.name === 'tests/games/fishing'));
    assert.ok(r.skipped.some((s) => s.name === 'tools/audio'));
  });

  test("Tank's sim scripts reach the gate's own tests; its audio reaches tools/audio", () => {
    assert.ok(names(plan(['tests/games/tank/sim/check_sims.mjs']))[0].includes('gate.test.mjs'));
    assert.ok(names(plan(['tests/games/tank/sim/check_sims.mjs']))[0].includes('gate_core.test.mjs'));
    assert.ok(!names(plan(['tests/games/tank/rules/test_a.gd']))[0].includes('gate.test.mjs'));
    assert.ok(names(plan(['assets/tank/audio/a.wav'])).includes('tools/audio'));
    assert.ok(names(plan(['tests/games/tank/audio/real_wave.json'])).includes('tools/audio'));
    assert.ok(!names(plan(['assets/tank/sprites/a.png'])).includes('tools/audio'));
  });

  test('a suite or a file with no row reads every game path', () => {
    const extra = [...units, { name: 'tools/newthing', kind: 'suite', files: null }];
    const r = planNodeSuites({ changed: ['assets/siege/a.png'], units: extra, gameIds: IDS, suiteFiles: (s) => (s === 'tools/tests' ? [...toolsTests, 'brand_new.test.mjs'] : []) });
    const n = r.units.map((u) => u.name);
    assert.ok(n.includes('tools/newthing'));
    assert.deepEqual(r.units.find((u) => u.name === 'tools/tests').files, ['run_game_sim.test.mjs', 'brand_new.test.mjs']);
  });

  test('when every file of a per-file row is picked, the suite runs whole', () => {
    const r = planNodeSuites({ changed: ['tests/games/tank/sim/a.mjs'], units, gameIds: IDS, suiteFiles: () => ['gate.test.mjs', 'run_tests.test.mjs'] });
    assert.equal(r.units.find((u) => u.name === 'tools/tests').files, null);
  });

  test('gameOfPath knows the five kinds of game path and nothing else', () => {
    assert.equal(gameOfPath('src/games/tank/a.gd', IDS), 'tank');
    assert.equal(gameOfPath('content/siege/a.json', IDS), 'siege');
    assert.equal(gameOfPath('assets/fishing/a.png', IDS), 'fishing');
    assert.equal(gameOfPath('tests/games/workout/a.mjs', IDS), 'workout');
    assert.equal(gameOfPath('.github/workflows/game-tank.yml', IDS), 'tank');
    assert.equal(gameOfPath('.github/workflows/lead.yml', IDS), null);
    assert.equal(gameOfPath('src/games/tankx/a.gd', IDS), null);
    assert.equal(gameOfPath('assets/tank', IDS), null);
  });

  test('every NODE_SUITES entry has a row, and every per-file row names a real file', () => {
    for (const s of NODE_SUITES) assert.ok(Object.hasOwn(NODE_SUITE_GAME_INPUTS, s), s);
    for (const [suite, row] of Object.entries(NODE_SUITE_GAME_INPUTS)) {
      if (Array.isArray(row)) continue;
      const files = suiteTestFiles(path.join(REPO, suite));
      for (const f of Object.keys(row)) if (f !== '*') assert.ok(files.includes(f), `${suite}: ${f}`);
    }
  });
});

describe('suiteTestFiles and changedPaths', () => {
  test('suiteTestFiles finds what node --test runs, skipping node_modules and dot folders', () => {
    const d = tmp('suite');
    try {
      write(d, {
        'a.test.mjs': '',
        'b-test.js': '',
        'helpers.mjs': '',
        'test/c.mjs': '',
        'test/sub/d.js': '',
        'node_modules/x.test.mjs': '',
        '.hidden/e.test.mjs': '',
        'lib/f.test.cjs': '',
      });
      assert.deepEqual(suiteTestFiles(d), ['a.test.mjs', 'b-test.js', 'lib/f.test.cjs', 'test/c.mjs', 'test/sub/d.js']);
    } finally {
      rmQuiet(d);
    }
  });

  test('changedPaths: committed since the base, staged, unstaged and untracked; a bad base is an error', { skip: !GIT && 'no git' }, () => {
    const d = tmp('git');
    const git = (...args) => {
      const r = spawnSync(GIT, ['-C', d, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false', ...args], { encoding: 'utf8' });
      assert.equal(r.status, 0, r.stderr);
    };
    try {
      git('init', '-q', '-b', 'main');
      write(d, { 'a.txt': '1', 'b.txt': '1', 'c.txt': '1' });
      git('add', '.');
      git('commit', '-q', '-m', 'base');
      git('checkout', '-q', '-b', 'work');
      write(d, { 'committed/x.txt': '1' });
      git('add', '.');
      git('commit', '-q', '-m', 'work');
      write(d, { 'a.txt': '2', 'b.txt': '2', 'new dir/u.txt': '1' });
      git('add', 'a.txt');
      fs.rmSync(path.join(d, 'c.txt'));
      assert.deepEqual(changedPaths(d, 'main').paths, ['a.txt', 'b.txt', 'c.txt', 'committed/x.txt', 'new dir/u.txt']);
      assert.match(changedPaths(d, 'no-such-rev').error, /no-such-rev/);
    } finally {
      rmQuiet(d);
    }
  });
});

describe('the lint split', () => {
  test('lintChunks names exactly the files of the whole folders, over at most `jobs` lists', () => {
    const d = tmp('lint');
    try {
      write(d, {
        'src/a.gd': '',
        'src/notes.txt': '',
        'src/one/b.gd': '',
        'src/one/two/c.gd': '',
        'src/empty/readme.md': '',
        'src/.git/hooks.gd': '',
        'tests/d.gd': '',
        'tests/x/e.gd': '',
        'tests/x/f.gd': '',
      });
      const walk = (p) => {
        const abs = path.join(d, p);
        if (!fs.statSync(abs).isDirectory()) return [p];
        return fs.readdirSync(abs).filter((n) => n !== '.git').flatMap((n) => walk(`${p}/${n}`)).filter((f) => f.endsWith('.gd'));
      };
      const whole = ['src', 'tests'].flatMap(walk).sort();
      for (const jobs of [1, 2, 3, 8]) {
        const chunks = lintChunks(d, ['src', 'tests', 'nothere'], jobs);
        assert.ok(chunks.length <= jobs && chunks.length > 0, `${jobs}`);
        assert.deepEqual(chunks.flat().flatMap(walk).sort(), whole, `jobs ${jobs}`);
        assert.ok(!chunks.flat().includes('src/empty'), 'a folder with no .gd is left out');
      }
      assert.deepEqual(lintChunks(d, ['src', 'tests'], 2).map((c) => c.flatMap(walk).length).sort(), [3, 3], 'balanced by .gd count');
    } finally {
      rmQuiet(d);
    }
  });

  test('mergeLintRuns: clean only when every chunk is; counts add up; a chunk with no count line keeps its exit', () => {
    const re = /(\d+) problems? found/;
    const sum = (n) => `Failure: ${n} problems found`;
    assert.equal(mergeLintRuns([{ code: 0, text: 'ok' }, { code: 0, text: 'ok' }], re, sum).code, 0);
    const two = mergeLintRuns([{ code: 1, text: 'Failure: 2 problems found' }, { code: 0, text: 'ok' }, { code: 1, text: 'Failure: 1 problem found' }], re, sum);
    assert.equal(two.code, 1);
    assert.match(two.text, /^Failure: 3 problems found\n/);
    const crash = mergeLintRuns([{ code: 1, text: 'Failure: 2 problems found' }, { code: 2, text: 'Traceback' }], re, sum);
    assert.equal(crash.code, 2);
    assert.equal(crash.text, 'Failure: 2 problems found\nTraceback', 'no made-up total');
  });
});

describe('the node step on a scratch project', () => {
  // A project with three suites (one fails) and a NODE_EXTRA; run_tests --only=node runs them.
  function project() {
    const d = tmp('node');
    write(d, {
      'project.godot': 'config_version=5\n',
      'tools/tests/ok.test.mjs': "import { test } from 'node:test';\ntest('ok', () => {});\n",
      'tools/audio/test/cache.test.mjs': "import { test } from 'node:test';\nimport assert from 'node:assert/strict';\ntest('sees the cache dir', () => assert.ok(process.env.WATTLANDS_TEST_CACHE_DIR, 'set'));\n",
      'server/relay/broken.test.mjs': "import { test } from 'node:test';\ntest('fails', () => { throw new Error('boom on purpose'); });\n",
      'tests/games/tank/t.test.mjs': "import { test } from 'node:test';\ntest('tank', () => {});\n",
      'src/games/tank/game.json': '{"id": "tank"}\n',
    });
    return d;
  }
  const rt = (d, args) => runProc(process.execPath, [RUN_TESTS, '--only=node', `--project=${d}`, ...args], { cwd: d, timeoutMs: 120_000, env: { ...process.env, WATTLANDS_RUN_TESTS_NESTED: '' } });

  test('--node-jobs runs the suites at once, quiet, and a failing one still fails the step with its tail', async () => {
    const d = project();
    try {
      const r = await rt(d, ['--node-jobs=4', '--node-cache']);
      assert.equal(r.code, 1, r.stdout);
      assert.match(r.stdout, /run_tests: node server\/relay FAIL/);
      assert.match(r.stdout, /--- server\/relay \(last 60 lines\)[\s\S]*boom on purpose/);
      assert.match(r.stdout, /tools\/audio PASS/, '--node-cache hands the suites a cache dir');
      assert.match(r.stdout, /tests\/games\/tank PASS/);
      assert.match(r.stdout, /^ {2}node\s+FAIL/m);
    } finally {
      rmQuiet(d);
    }
  });

  test('without --node-cache no suite sees a cache dir', async () => {
    const d = project();
    try {
      fs.rmSync(path.join(d, 'server'), { recursive: true });
      const r = await rt(d, ['--node-jobs=2']);
      assert.equal(r.code, 1, r.stdout);
      assert.match(r.stdout, /tools\/audio FAIL/);
      const ok = await rt(d, ['--node-jobs=2', '--node-cache']);
      assert.equal(ok.code, 0, ok.stdout);
    } finally {
      rmQuiet(d);
    }
  });

  test('--node-since runs what the change reaches; nothing reached is a pass that says so; a bad base runs all', { skip: !GIT && 'no git' }, async () => {
    const d = project();
    const git = (...args) => spawnSync(GIT, ['-C', d, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false', ...args], { encoding: 'utf8' });
    try {
      fs.rmSync(path.join(d, 'server'), { recursive: true });
      write(d, { '.gitignore': 'build/\n' });
      git('init', '-q', '-b', 'main');
      git('add', '.');
      git('commit', '-q', '-m', 'base');
      const none = await rt(d, ['--node-since=main', '--node-cache']);
      assert.equal(none.code, 0, none.stdout);
      assert.match(none.stdout, /no suite reads the changed paths/);
      write(d, { 'src/games/tank/rules.gd': 'extends RefCounted\n' });
      const tank = await rt(d, ['--node-since=main', '--node-cache']);
      assert.equal(tank.code, 0, tank.stdout);
      assert.match(tank.stdout, /tests\/games\/tank PASS/);
      assert.match(tank.stdout, /tools\/audio SKIP \(reads no changed game path\)/);
      const bad = await rt(d, ['--node-since=nope', '--node-cache']);
      assert.match(bad.stdout, /--node-since=nope: .*every suite runs/);
      assert.match(bad.stdout, /tools\/audio PASS/);
    } finally {
      rmQuiet(d);
    }
  });
});
