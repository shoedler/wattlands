// tools/gate wait, the mutex of one gate per checkout, usage errors and refusals.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { UNUSED_PID, sh, write, repo, commit, gate } from './gate_helpers.mjs';

describe('wait', { concurrency: 4 }, () => {
  const stampJson = (extra = {}) => JSON.stringify({ mode: 'fast', pass: true, exit_code: 0, ended: 'now', gut_total: 7, dirty: false, lanes: [{ name: 'gut:1', status: 'PASS', ms: 3000, log: 'build/gate/fast/gut_1.log' }], ...extra });
  const treeOf = (dir) => sh(dir, 'rev-parse', 'HEAD^{tree}');
  /** The record a gate leaves in current.json when it takes the mutex. */
  const recordOf = (token, extra = {}) => ({ pid: UNUSED_PID, cmd: 'fast', stamp: 'fast', started: 'then', token, ...extra });
  /** A finished gate: its record in current.json and its own stamp, for this tree. */
  function finished(dir, { token = 'tok-1', stamp = {}, record = {} } = {}) {
    const rec = recordOf(token, record);
    write(dir, {
      'build/gate/current.json': JSON.stringify(rec),
      [`build/gate/${rec.stamp}.json`]: stampJson({ run: token, tree: treeOf(dir), sha: sh(dir, 'rev-parse', 'HEAD'), ...stamp }),
    });
    return rec;
  }

  /**
   * A stand-in gate: takes the mutex as tools/gate does (its record in run.lock and current.json), writes a
   * progress row under its run's header, then after `ms` its stamp, and exits. `stale` leaves an earlier
   * run's rows in the progress file until it rewrites the file after 1.5 s; the lock is beaten every second.
   */
  function holder(dir, { ms, stamp, stale = false }) {
    const gateDir = path.join(dir, 'build', 'gate');
    fs.mkdirSync(path.join(gateDir, 'fast'), { recursive: true });
    if (stale) fs.writeFileSync(path.join(gateDir, 'fast', 'progress.txt'), '# run old\nPASS stale 9s build/gate/fast/old.log\n');
    const script = path.join(dir, 'build', 'holder.cjs');
    fs.writeFileSync(script, [
      "const fs = require('fs');",
      "const p = require('path');",
      `const d = ${JSON.stringify(gateDir)};`,
      "const token = 'tok-' + process.pid;",
      "const rec = JSON.stringify({ pid: process.pid, cmd: 'fast', stamp: 'fast', started: 'then', token });",
      "fs.writeFileSync(p.join(d, 'run.lock'), rec);",
      "fs.writeFileSync(p.join(d, 'current.json'), rec);",
      "const progress = () => fs.writeFileSync(p.join(d, 'fast', 'progress.txt'), ['# run ' + token, 'PASS check 1s build/gate/fast/check.log', ''].join(String.fromCharCode(10)));",
      `if (${stale}) setTimeout(progress, 1500); else progress();`,
      "setInterval(() => { const now = new Date(); try { fs.utimesSync(p.join(d, 'run.lock'), now, now); } catch {} }, 1000);",
      `const stamp = ${JSON.stringify(stamp)};`,
      `setTimeout(() => { fs.writeFileSync(p.join(d, 'fast.json'), JSON.stringify({ ...JSON.parse(stamp), run: token })); fs.rmSync(p.join(d, 'run.lock')); process.exit(0); }, ${ms});`,
      '',
    ].join('\n'));
    return spawn(process.execPath, [script], { stdio: 'ignore', windowsHide: true });
  }

  /** Resolves once the stand-in holds the mutex (its token is in current.json). */
  async function holding(dir, child) {
    const started = Date.now();
    const file = path.join(dir, 'build', 'gate', 'current.json');
    while (!(fs.existsSync(file) && fs.readFileSync(file, 'utf8').includes(`tok-${child.pid}`))) {
      assert.ok(Date.now() - started < 20_000, 'the stand-in took the mutex');
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }

  test('no gate and no stamp: says so and exits 4 (no verdict), after the grace for a gate just started', async () => {
    const dir = repo();
    const r = await gate(dir, ['wait']);
    assert.equal(r.code, 4, r.stdout + r.stderr);
    assert.match(r.stdout, /gate wait: no verdict: no gate has started in this checkout/);
    assert.ok(r.ms >= 4000, `waited ${r.ms} ms for a gate to appear`);
  });

  test("no gate: the last gate's own stamp, its lanes, sha, tree and verdict, with the tail of a lane that failed", async () => {
    const dir = repo();
    finished(dir);
    const ok = await gate(dir, ['wait']);
    assert.equal(ok.code, 0, ok.stdout);
    assert.match(ok.stdout, /the last one to start was fast/);
    assert.match(ok.stdout, new RegExp(`sha ${sh(dir, 'rev-parse', 'HEAD')}, tree ${treeOf(dir)}`));
    assert.match(ok.stdout, /gut:1 +PASS +3s/);
    assert.match(ok.stdout, /gate fast: PASS \(exit 0\)/);
    finished(dir, { stamp: { pass: false, exit_code: 75, lanes: [{ name: 'e2e:tank', status: 'FAIL', ms: 1, log: 'build/gate/fast/e2e_tank.log' }] } });
    write(dir, { 'build/gate/fast/e2e_tank.log': 'line one\ngodot lock wait timeout\n' });
    const bad = await gate(dir, ['wait', '--for=fast']);
    assert.equal(bad.code, 75, bad.stdout);
    assert.match(bad.stdout, /--- e2e:tank \(last 30 lines of build\/gate\/fast\/e2e_tank\.log\)\nline one\ngodot lock wait timeout/);
  });

  test('a running gate: its rows as they come, then its stamp and its exit code', async () => {
    const dir = repo();
    const child = holder(dir, { ms: 3500, stale: true, stamp: stampJson({ pass: false, exit_code: 1, tree: treeOf(dir) }) });
    try {
      const r = await gate(dir, ['wait', '--for=fast']);
      assert.equal(r.code, 1, r.stdout + r.stderr);
      assert.match(r.stdout, /gate wait: fast \(pid \d+\) runs since then/);
      assert.match(r.stdout, / {2}PASS check 1s/);
      assert.doesNotMatch(r.stdout, /stale/, "an earlier run's rows in the same dir are not this run's");
      assert.match(r.stdout, /gate fast: FAIL \(exit 1\)/);
    } finally {
      child.kill();
    }
  });

  test('--timeout: exit 124 while the gate still runs', async () => {
    const dir = repo();
    const child = holder(dir, { ms: 60_000, stamp: stampJson() });
    try {
      const r = await gate(dir, ['wait', '--timeout=1']);
      assert.equal(r.code, 124, r.stdout + r.stderr);
      assert.match(r.stdout, /still runs after 1 s .*run tools\/gate wait again/);
    } finally {
      child.kill();
    }
  });

  test("a killed gate wrote no stamp: no verdict, though an older run's stamp of the same gate is there", async () => {
    const dir = repo();
    finished(dir, { token: 'tok-old' });
    const child = holder(dir, { ms: 60_000, stamp: stampJson({ tree: treeOf(dir) }) });
    const exited = new Promise((resolve) => child.on('exit', resolve));
    try {
      await holding(dir, child);
    } finally {
      child.kill('SIGKILL'); // no exit hook: its run.lock stays
    }
    await exited;
    assert.ok(fs.existsSync(path.join(dir, 'build', 'gate', 'run.lock')), 'the hard kill left its lock');
    const r = await gate(dir, ['wait', '--for=fast', '--timeout=30']);
    assert.equal(r.code, 4, r.stdout + r.stderr);
    assert.match(r.stdout, /no verdict: build\/gate\/fast\.json is from another run \(tok-old\)/);
  });

  test("a foreign newest stamp is never the verdict: check's, fmt's, another gate's", async () => {
    const dir = repo();
    write(dir, { 'build/gate/current.json': JSON.stringify(recordOf('tok-1')) });
    for (const name of ['check', 'fmt', 'matrix_tank']) write(dir, { [`build/gate/${name}.json`]: stampJson({ mode: name, run: 'tok-1', tree: treeOf(dir) }) });
    const r = await gate(dir, ['wait']);
    assert.equal(r.code, 4, r.stdout + r.stderr);
    assert.match(r.stdout, /no verdict: fast \(pid \d+, started then\) ended without a stamp/);
    // The last gate was fmt: it has no verdict, whatever its stamp says.
    write(dir, { 'build/gate/current.json': JSON.stringify(recordOf('tok-1', { cmd: 'fmt', stamp: 'fmt' })) });
    assert.match((await gate(dir, ['wait'])).stdout, /the last gate here was fmt, which has no verdict to wait for/);
    // A matrix was the last to start: a caller waiting for its fast gets no verdict from it.
    finished(dir, { record: { cmd: 'matrix', stamp: 'matrix_tank' } });
    const m = await gate(dir, ['wait', '--for=fast']);
    assert.equal(m.code, 4, m.stdout);
    assert.match(m.stdout, /the last gate to start here was matrix_tank, not fast/);
    assert.equal((await gate(dir, ['wait', '--for=matrix_tank'])).code, 0);
  });

  test("a reused pid: the lock's pid runs but its heartbeat stopped, so wait does not follow it and the next gate reaps it", async () => {
    const dir = repo();
    finished(dir, { token: 'tok-gone', stamp: { run: 'tok-older' } });
    // This test's own pid is alive, as a reused pid would be; the lock has not beaten for two minutes.
    write(dir, { 'build/gate/run.lock': JSON.stringify({ pid: process.pid, cmd: 'fast', stamp: 'fast', started: 'then', token: 'tok-gone' }) });
    const old = new Date(Date.now() - 120_000);
    fs.utimesSync(path.join(dir, 'build', 'gate', 'run.lock'), old, old);
    const r = await gate(dir, ['wait', '--timeout=20']);
    assert.equal(r.code, 4, r.stdout + r.stderr);
    assert.doesNotMatch(r.stdout, /runs since/, 'not followed');
    assert.match(r.stdout, /from another run/);
    write(dir, { 'build/gate/strict.json': '{}' });
    const floor = await gate(dir, ['floor', '--label=x']);
    assert.doesNotMatch(floor.stderr, /another gate/, floor.stderr);
    assert.ok(!fs.existsSync(path.join(dir, 'build', 'gate', 'run.lock')), 'reaped, then released at exit');
  });

  test('a refused start is no verdict for what was asked: strict on a dirty tree, a fast beside a running gate', async () => {
    const dir = repo();
    finished(dir);
    write(dir, { 'src/a.txt': 'uncommitted\n' });
    const strict = await gate(dir, ['strict']);
    assert.equal(strict.code, 3, strict.stdout + strict.stderr);
    const ws = await gate(dir, ['wait', '--for=strict']);
    assert.equal(ws.code, 4, ws.stdout);
    assert.match(ws.stdout, /no verdict: strict \(pid \d+, started .*\) ended without a stamp/);
    const wf = await gate(dir, ['wait', '--for=fast']);
    assert.equal(wf.code, 4, wf.stdout);
    assert.match(wf.stdout, /the last gate to start here was strict, not fast/, "the earlier fast's PASS does not answer");
    fs.rmSync(path.join(dir, 'src'), { recursive: true });
    const child = holder(dir, { ms: 60_000, stamp: stampJson() });
    try {
      await holding(dir, child);
      const r = await gate(dir, ['wait', '--for=matrix_tank', '--timeout=20']);
      assert.equal(r.code, 4, r.stdout + r.stderr);
      assert.match(r.stdout, /fast runs in this checkout \(pid \d+\), not matrix_tank/);
      const second = await gate(dir, ['floor', '--label=x']);
      assert.equal(second.code, 3, 'the second gate is refused');
      assert.match(fs.readFileSync(path.join(dir, 'build', 'gate', 'current.json'), 'utf8'), new RegExp(`tok-${child.pid}`), 'and leaves current.json alone');
    } finally {
      child.kill();
    }
  });

  test('a stale tree is no verdict: a commit after the stamp, or changes it did not run on', async () => {
    const dir = repo();
    finished(dir);
    assert.equal((await gate(dir, ['wait'])).code, 0);
    write(dir, { 'src/b.txt': 'new\n' });
    const dirty = await gate(dir, ['wait']);
    assert.equal(dirty.code, 4, dirty.stdout);
    assert.match(dirty.stdout, /ran on a clean tree, and this checkout is dirty now/);
    commit(dir, 'more');
    const moved = await gate(dir, ['wait']);
    assert.equal(moved.code, 4, moved.stdout);
    assert.match(moved.stdout, /the stamp is for tree [0-9a-f]+, and this checkout's is [0-9a-f]+/);
  });
});

describe('usage and refusals', { concurrency: 4 }, () => {
  test('usage errors exit 2', async () => {
    const dir = repo();
    for (const args of [[], ['nope'], ['check', '--nope'], ['check', 'extra'], ['strict', '--lanes=gut'], ['strict', '--min-count=1'], ['strict', '--gdir=res://tests'], ['strict', '--games=all'],
      ['matrix'], ['floor'], ['pin-safety'], ['fast', '--shards=0'], ['fast', '--serial-gut'], ['stamp-ok'], ['wt-add', 'a'], ['wait', '--for=nope'], ['wait', '--for=check'], ['fast', '--for=fast']]) {
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
    const dead = String(UNUSED_PID);
    write(dir, { 'build/gate/run.lock': dead, 'build/gate/strict.json': '{}' });
    const r = await gate(dir, ['floor', '--label=x']);
    assert.doesNotMatch(r.stderr, /another gate/);
    assert.ok(!fs.existsSync(lock), 'reaped, then released at exit');
  });
});
