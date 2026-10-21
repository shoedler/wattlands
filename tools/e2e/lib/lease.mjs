// tools/e2e/lib/lease.mjs: one Godot lock lease for the whole e2e run (BRIEF 2).
// The host, both clients and the restarted client run inside it through
// WATTLANDS_GODOT_LEASE_TOKEN, so they never queue again (docs/decisions/tooling.md).
import { acquire, leaseTokenValid, LEASE_TOKEN_ENV, LOCK_TIMEOUT_MESSAGE } from '../../lib/godot_lock.mjs';

/** Godot processes one game runs at once: the host and two clients. */
export const E2E_LEASE = 3;

export { LEASE_TOKEN_ENV, LOCK_TIMEOUT_MESSAGE, leaseTokenValid };

/**
 * Takes `lease` slots (waiting first come, first served) and returns the handle
 * {seq, lease, token, release()}. Rejects with code ELOCKTIMEOUT after lockTimeoutS.
 * opts: {lease, lockTimeoutS, label, log, dir, cap} (dir and cap are for tests).
 */
export async function takeLease(opts = {}) {
  const handle = await acquire({
    lease: opts.lease ?? E2E_LEASE,
    lockTimeoutS: opts.lockTimeoutS,
    label: opts.label ?? 'e2e run.mjs',
    log: opts.log,
    dir: opts.dir,
    cap: opts.cap,
  });
  return handle;
}

/** Runs fn(handle) inside a lease and always releases it. */
export async function withLease(opts, fn) {
  const handle = await takeLease(opts);
  try {
    return await fn(handle);
  } finally {
    handle.release();
  }
}

/** The environment entry that lets tools/godot.sh run inside the held lease. */
export function leaseEnv(handle) {
  return handle ? { [LEASE_TOKEN_ENV]: handle.token } : {};
}
