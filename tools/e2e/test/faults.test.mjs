// node:test for tools/e2e/run.mjs: each BRIEF 7.7 assertion fails the run when its condition
// breaks (stand-in peers inject the fault through FAKE_PEER_FAULT / FAKE_RELAY_FAULT).
import test from 'node:test';
import assert from 'node:assert/strict';
import { check, harnessArgs, runHarness, setup } from '../fixtures/harness.mjs';

for (const [fault, name, pattern] of [
  ['script_error', 'script_errors', /SCRIPT ERROR/],
  ['push_error', 'script_errors', /ERROR: something went wrong/],
  ['desync', 'desync', /desync warning/],
  ['event_mismatch', 'same_events', /client1: event \d+ differs/],
  ['warmup', 'warmup_limits', /above 65%/],
  ['double_upload', 'strava_upload', /2 uploads/],
  ['state', 'final_state', /score/],
  ['host_exit', 'peers_exit', /host exited with 1/],
  ['no_fit', 'fit_files', /client1: report lists no FIT file/],
  ['wrong_peer', 'reconnect', /came back as peer 9, not 3/],
  ['bad_fit', 'fit_files', /client1: .* exited 1.*not a FIT file/],
  ['unclamped', 'directives_clamped', /host directives\[0\]: no clamped_by list/],
  ['missing_ack', 'directives_clamped', /directive 2 for peer 2 has no applied record in client1's report/],
  ['bad_upload', 'strava_upload', /rejected the FIT file \(not a FIT file\)/],
]) {
  test(`a fault fails the run: ${fault}`, async () => {
    const s = setup();
    try {
      const r = await runHarness(harnessArgs(s.repo), { lockDir: s.lockDir, env: { FAKE_PEER_FAULT: fault } });
      assert.equal(r.code, 1, r.out);
      assert.match(r.out, /e2e: fake FAIL/);
      const rep = s.report();
      assert.equal(rep.ok, false);
      const c = check(rep, name);
      assert.equal(c?.ok, false, `${name} should fail: ${JSON.stringify(rep.checks)}`);
      assert.match(c.details.join('\n'), pattern);
    } finally {
      s.cleanup();
    }
  });
}

test('rate_limited in the relay output fails the run', async () => {
  const s = setup();
  try {
    const r = await runHarness(harnessArgs(s.repo), { lockDir: s.lockDir, env: { FAKE_RELAY_FAULT: 'rate' } });
    assert.equal(r.code, 1, r.out);
    assert.equal(check(s.report(), 'rate_limited').ok, false);
  } finally {
    s.cleanup();
  }
});
