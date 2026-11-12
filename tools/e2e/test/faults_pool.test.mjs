// node:test for tools/e2e/faults.mjs --jobs: scenarios at once, each still judged on its own, and the
// ports concurrent scenarios pick never repeat within one run.
import test from 'node:test';
import assert from 'node:assert/strict';
import { runScenarios, startOrder } from '../faults.mjs';
import { parseFaultArgs } from '../lib/fault_args.mjs';
import { getFreePort } from '../lib/util.mjs';

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

test('--jobs parses, defaults to 1 and refuses what is not a whole number from 1', () => {
  assert.equal(parseFaultArgs([]).opts.jobs, 1);
  assert.equal(parseFaultArgs(['--jobs=4']).opts.jobs, 4);
  for (const bad of ['--jobs=0', '--jobs=1.5', '--jobs=x']) {
    const r = parseFaultArgs([bad]);
    assert.equal(r.ok, false, bad);
    assert.match(r.error, /--jobs/);
  }
});

test('runScenarios runs at most `jobs` at once and reports every one', async () => {
  let live = 0;
  let most = 0;
  const seen = [];
  const names = ['a', 'b', 'c', 'd', 'e'];
  const r = await runScenarios(names, 2, async (name) => {
    live += 1;
    most = Math.max(most, live);
    await wait(name === 'a' ? 30 : 5);
    live -= 1;
    return { name, ok: name !== 'c' };
  }, (v) => seen.push(v));
  assert.deepEqual(r, { lockTimeout: false });
  assert.equal(most, 2);
  assert.deepEqual(seen.map((v) => v.name).sort(), names);
  assert.equal(seen.find((v) => v.name === 'c').ok, false, 'a failure stays a failure');
});

test('jobs 1 runs them in order, one after another', async () => {
  const order = [];
  await runScenarios(['x', 'y', 'z'], 1, async (name) => {
    order.push(`start ${name}`);
    await wait(2);
    order.push(`end ${name}`);
    return { name, ok: true };
  }, () => {});
  assert.deepEqual(order, ['start x', 'end x', 'start y', 'end y', 'start z', 'end z']);
});

test('a lock wait timeout starts nothing more, and what runs finishes', async () => {
  const started = [];
  const done = [];
  const r = await runScenarios(['slow', 'locked', 'never1', 'never2'], 2, async (name) => {
    started.push(name);
    if (name === 'locked') {
      const e = new Error('godot lock wait timeout');
      e.code = 'ELOCKTIMEOUT';
      throw e;
    }
    await wait(20);
    return { name, ok: true };
  }, (v) => done.push(v.name));
  assert.equal(r.lockTimeout, true);
  assert.deepEqual(started, ['slow', 'locked']);
  assert.deepEqual(done, ['slow']);
});

test('any other error from a scenario runner is not swallowed', async () => {
  await assert.rejects(runScenarios(['a'], 2, async () => {
    throw new Error('harness bug');
  }, () => {}), /harness bug/);
});

test('getFreePort never hands out one port twice in a run', async () => {
  const ports = await Promise.all(Array.from({ length: 40 }, () => getFreePort()));
  assert.equal(new Set(ports).size, ports.length);
  for (const p of ports) assert.ok(Number.isInteger(p) && p > 0 && p < 65536, String(p));
});

test('with --jobs the long scenarios start first; one at a time keeps the run order', () => {
  const names = parseFaultArgs([]).names;
  assert.deepEqual(startOrder(names, 1), names);
  const pooled = startOrder(names, 4);
  assert.deepEqual([...pooled].sort(), [...names].sort());
  assert.deepEqual(pooled.slice(0, 4), ['relay_dies', 'relay_restarts', 'host_killed_relay', 'host_killed_builtin']);
});
