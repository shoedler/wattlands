// node:test for tools/e2e/lib/lease.mjs: one 3-slot lease for the whole run, with a fake lock dir.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { E2E_LEASE, LEASE_TOKEN_ENV, leaseEnv, leaseTokenValid, takeLease, withLease } from '../lib/lease.mjs';
import { readTickets } from '../../lib/godot_lock.mjs';

function lockDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-e2e-lock-'));
}

test('the e2e lease is three slots', () => {
  assert.equal(E2E_LEASE, 3);
  assert.equal(LEASE_TOKEN_ENV, 'WATTLANDS_GODOT_LEASE_TOKEN');
});

test('withLease holds 3 slots, hands out a valid token and releases', async () => {
  const dir = lockDir();
  try {
    let token = null;
    await withLease({ dir, cap: 4, lockTimeoutS: 5 }, async (h) => {
      token = h.token;
      assert.equal(h.lease, 3);
      assert.ok(leaseTokenValid(h.token), 'the token names a live, held lease');
      const { tickets } = readTickets(dir);
      assert.equal(tickets.length, 1);
      assert.equal(tickets[0].held, true);
      assert.equal(tickets[0].lease, 3);
      assert.deepEqual(leaseEnv(h), { WATTLANDS_GODOT_LEASE_TOKEN: h.token });
    });
    assert.equal(leaseTokenValid(token), false, 'released after the run');
    assert.equal(readTickets(dir).tickets.length, 0);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('withLease releases when the run throws', async () => {
  const dir = lockDir();
  try {
    await assert.rejects(withLease({ dir, cap: 4, lockTimeoutS: 5 }, async () => {
      throw new Error('boom');
    }), /boom/);
    assert.equal(readTickets(dir).tickets.length, 0);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('a lease above the cap is granted only while nothing else is held', async () => {
  const dir = lockDir();
  try {
    const h = await takeLease({ dir, cap: 2, lockTimeoutS: 5 });
    assert.equal(h.lease, 3);
    h.release();
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('waiting behind held slots times out with ELOCKTIMEOUT and leaves no ticket', async () => {
  const dir = lockDir();
  try {
    const other = await takeLease({ dir, cap: 4, lease: 2, lockTimeoutS: 5 });
    await assert.rejects(takeLease({ dir, cap: 4, lockTimeoutS: 0.5 }), (e) => e.code === 'ELOCKTIMEOUT');
    const { tickets } = readTickets(dir);
    assert.equal(tickets.length, 1, 'only the other holder remains');
    other.release();
    const h = await takeLease({ dir, cap: 4, lockTimeoutS: 5 });
    h.release();
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('leaseEnv of no handle is empty', () => {
  assert.deepEqual(leaseEnv(null), {});
});
