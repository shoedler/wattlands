// node:test for tools/e2e/faults.mjs --jobs: scenarios at once, each still judged on its own, and the
// ports concurrent scenarios pick never repeat within one run.
import test from 'node:test';
import assert from 'node:assert/strict';
import { runScenarios, startOrder } from '../faults.mjs';
import { parseFaultArgs } from '../lib/fault_args.mjs';
import dgram from 'node:dgram';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { FaultEnv } from '../lib/fault_env.mjs';
import { BAND_HIGH, BAND_LOW, getBandPort, getFreePort } from '../lib/util.mjs';

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

// Two built-in scenarios at once: a client's discovery listener failed with "can't listen" because its
// UDP port came from a TCP probe in the ephemeral range, where the OS gives numbers to sockets that send
// before they bind (the other scenario's host beacon is one).
test('two built-in scenarios started together get four ports of their own, outside the ephemeral range, free for TCP and UDP', async () => {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-faults-pool-'));
  try {
    const envs = ['builtin:siege', 'host_killed_builtin'].map((name) => new FaultEnv({ out }, name, null, () => {}));
    const lans = await Promise.all(envs.map((e) => e.useBuiltin()));
    const ports = lans.flatMap((l) => [l.port, l.discoveryPort]);
    assert.equal(new Set(ports).size, 4, JSON.stringify(lans));
    for (const p of ports) {
      assert.ok(p >= BAND_LOW && p <= BAND_HIGH, `${p} is in the band`);
      const udp = dgram.createSocket('udp4');
      await new Promise((resolve, reject) => {
        udp.once('error', reject);
        udp.bind(p, '127.0.0.1', resolve);
      });
      udp.close();
      const tcp = net.createServer();
      await new Promise((resolve, reject) => {
        tcp.once('error', reject);
        tcp.listen(p, '127.0.0.1', resolve);
      });
      await new Promise((resolve) => tcp.close(resolve));
    }
  } finally {
    fs.rmSync(out, { recursive: true, force: true });
  }
});

test('a band port taken for UDP alone, or for TCP alone, is skipped', async () => {
  const udp = dgram.createSocket('udp4');
  const held = await new Promise((resolve) => udp.bind(0, '127.0.0.1', () => resolve(udp.address().port)));
  udp.close();
  // Find a band port, hold it for one protocol, and ask from there.
  const p = await getBandPort();
  const sock = dgram.createSocket('udp4');
  await new Promise((resolve) => sock.bind(p, '127.0.0.1', resolve));
  try {
    const next = await getBandPort({ start: p });
    assert.notEqual(next, p, 'held for UDP: skipped');
  } finally {
    sock.close();
  }
  const q = await getBandPort();
  const srv = net.createServer();
  await new Promise((resolve) => srv.listen(q, '127.0.0.1', resolve));
  try {
    assert.notEqual(await getBandPort({ start: q }), q, 'held for TCP: skipped');
  } finally {
    await new Promise((resolve) => srv.close(resolve));
  }
  assert.ok(held < BAND_LOW || held > BAND_HIGH, `an OS-chosen UDP port (${held}) is never in the band`);
});

test('sockets that send before they bind never get a band port', async () => {
  const seen = [];
  for (let i = 0; i < 20; i += 1) {
    const s = dgram.createSocket('udp4');
    await new Promise((resolve) => s.send(Buffer.from('x'), 9, '127.0.0.1', resolve));
    seen.push(s.address().port);
    s.close();
  }
  for (const p of seen) assert.ok(p < BAND_LOW || p > BAND_HIGH, String(p));
});
