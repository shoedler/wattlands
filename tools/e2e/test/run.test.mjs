// node:test for tools/e2e/run.mjs end to end, with stand-ins for the relay, the mock Strava server,
// the Godot peers and the FIT checker (tools/e2e/fixtures), a private Godot lock directory and a
// throwaway repo: the orchestration (lease, room code, kill and restart, reports, e2e_check.mjs),
// usage errors and the lock wait timeout. faults.test.mjs covers each failing assertion.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { acquire } from '../../lib/godot_lock.mjs';
import { RUN, check, harnessArgs, runHarness, setup } from '../fixtures/harness.mjs';

test('a clean run passes every check and writes the report', async () => {
  const s = setup();
  try {
    // FAL_KEY in the harness's environment must never reach a peer (the fake peer exits 6).
    const r = await runHarness(harnessArgs(s.repo), { lockDir: s.lockDir, env: { FAL_KEY: 'dummy', WATTLANDS_ALLOW_ART: '1' } });
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /e2e: fake PASS/);
    assert.match(r.out, /1 of 1 game\(s\) passed/);
    const rep = s.report();
    assert.equal(rep.ok, true, JSON.stringify(rep.failures));
    assert.equal(rep.game_id, 'fake');
    assert.equal(rep.content_id, 'e2e');
    assert.equal(rep.room, 'K7QX2M');
    for (const name of ['run', 'peers_exit', 'reports', 'script_errors', 'desync', 'rate_limited', 'same_events', 'final_state', 'directives_clamped', 'warmup_limits', 'mock_trainer', 'strava_upload', 'reconnect', 'fit_files', 'duration']) {
      assert.equal(check(rep, name)?.ok, true, `${name}: ${JSON.stringify(check(rep, name))}`);
    }
    assert.deepEqual(Object.keys(rep.peers).sort(), ['client1', 'client2', 'host']);
    assert.equal(rep.peers.client2.restarted, true);
    assert.equal(rep.peers.client2.earlier_runs[0].killed, true);
    assert.equal(String(rep.peers.client2.earlier_runs[0].peer_id), '3');
    assert.ok(rep.events_by_peer['1'].length > 0, 'events per peer');
    assert.ok(rep.events_by_peer['2'].length > 0);
    assert.equal(rep.directives.length, 3, "the host's two records and client1's acknowledgement");
    assert.equal(rep.services.mock_strava.uploads[0].fit_valid, true);
    assert.equal(rep.fit_paths.host.length, 1);
    assert.equal(rep.services.mock_strava.uploads.length, 1);
    for (const k of ['total_s', 'room_s', 'kill_s', 'restart_s', 'duration_excl_cooldown_s']) assert.equal(typeof rep.timings[k], 'number', k);
    assert.ok(!JSON.stringify(rep).includes('mock-client-secret'), 'the Strava secret is never written to the report');
    // Per-peer logs exist.
    const out = path.join(s.repo, 'build', 'e2e', 'fake');
    for (const f of ['host/stdout.log', 'client1/stdout.log', 'client2/stdout.log', 'client2/stdout_restart.log', 'relay.log', 'mock_strava.log']) {
      assert.ok(fs.existsSync(path.join(out, f)), f);
    }
    // The lease is gone.
    assert.deepEqual(fs.readdirSync(s.lockDir).filter((f) => f.startsWith('t-') || f.startsWith('h-')), []);
  } finally {
    s.cleanup();
  }
});

test('a rejoined client whose replayed phase arrives after a live event still passes', async () => {
  const s = setup();
  try {
    const r = await runHarness(harnessArgs(s.repo), { lockDir: s.lockDir, env: { FAKE_PEER_FAULT: 'late_replay' } });
    assert.equal(r.code, 0, r.out);
    const c = check(s.report(), 'same_events');
    assert.equal(c.ok, true, c.details.join('\n'));
    assert.match(c.details.join('\n'), /client2: the last \d+ of \d+ events match \(from \d+, 1 replayed\)/);
  } finally {
    s.cleanup();
  }
});

test('a victim that finishes before the kill fails the run clearly', async () => {
  const s = setup();
  try {
    const r = await runHarness(harnessArgs(s.repo, ['--kill-after=1']), { lockDir: s.lockDir, env: { FAKE_PEER_FAULT: 'fast_victim' } });
    assert.equal(r.code, 1, r.out);
    const detail = check(s.report(), 'run').details[0];
    assert.match(detail, /client2 exited .* before it could be killed/);
    // Where each peer had got to, for debugging a stuck session.
    assert.match(detail, /last states: host \w+; client1 \w+; client2 \w+, exited 0\)/);
  } finally {
    s.cleanup();
  }
});

test('the duration limit excludes the cool-down and fails when exceeded', async () => {
  const s = setup();
  try {
    const r = await runHarness(harnessArgs(s.repo, ['--max-duration=1']), { lockDir: s.lockDir });
    assert.equal(r.code, 1, r.out);
    assert.match(check(s.report(), 'duration').details[0], /limit 1 s/);
  } finally {
    s.cleanup();
  }
});

test("the game's e2e_check.mjs runs with the report path and its exit code counts", async () => {
  const pass = setup({ e2eCheck: "import fs from 'node:fs';\nconst r = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));\nif (r.game_id !== 'fake' || !r.events_by_peer['3']) process.exit(3);\nconsole.log('fake e2e check ok');\n" });
  try {
    const r = await runHarness(harnessArgs(pass.repo), { lockDir: pass.lockDir });
    assert.equal(r.code, 0, r.out);
    const rep = pass.report();
    assert.equal(check(rep, 'e2e_check').ok, true);
    assert.equal(rep.e2e_check.exit_code, 0);
    assert.ok(rep.e2e_check.output.includes('fake e2e check ok'));
  } finally {
    pass.cleanup();
  }
  const fail = setup({ e2eCheck: "console.error('mackerel missing');\nprocess.exit(4);\n" });
  try {
    const r = await runHarness(harnessArgs(fail.repo), { lockDir: fail.lockDir });
    assert.equal(r.code, 1, r.out);
    const c = check(fail.report(), 'e2e_check');
    assert.equal(c.ok, false);
    assert.match(c.details[0], /exited 4.*mackerel missing/);
  } finally {
    fail.cleanup();
  }
});

test('a game without e2e_content fails without starting anything', async () => {
  const s = setup({ gameJson: { id: 'fake' } });
  try {
    const r = await runHarness(harnessArgs(s.repo), { lockDir: s.lockDir });
    assert.equal(r.code, 1, r.out);
    assert.match(check(s.report(), 'run').details[0], /no e2e_content/);
    assert.equal(fs.existsSync(path.join(s.repo, 'build', 'e2e', 'fake', 'host')), false);
  } finally {
    s.cleanup();
  }
});

test('usage errors exit 2 before taking the lock', async () => {
  const s = setup();
  try {
    const unknown = await runHarness([RUN, `--repo=${s.repo}`, '--games=nope'], { lockDir: s.lockDir });
    assert.equal(unknown.code, 2, unknown.out);
    assert.match(unknown.out, /unknown game "nope"/);
    const noMock = await runHarness([RUN, `--repo=${s.repo}`, '--games=fake', '--mock-trainer=none'], { lockDir: s.lockDir });
    assert.equal(noMock.code, 2);
    assert.match(noMock.out, /refusing to run without a mock trainer/);
    const hw = await runHarness([RUN, '--games=fake', '--allow-hw'], { lockDir: s.lockDir });
    assert.equal(hw.code, 2);
    const help = await runHarness([RUN, '--help'], { lockDir: s.lockDir });
    assert.equal(help.code, 0);
    assert.match(help.out, /usage: node tools\/e2e\/run\.mjs/);
    assert.deepEqual(fs.readdirSync(s.lockDir), [], 'no ticket was ever taken');
  } finally {
    s.cleanup();
  }
});

test('the lock wait times out with exit 75 and starts nothing', async () => {
  const s = setup();
  const prevDir = process.env.WATTLANDS_GODOT_LOCK_DIR;
  try {
    const held = await acquire({ dir: s.lockDir, cap: 4, lease: 2, lockTimeoutS: 5 });
    try {
      const r = await runHarness(harnessArgs(s.repo, ['--lock-timeout=1']), { lockDir: s.lockDir });
      assert.equal(r.code, 75, r.out);
      assert.match(r.out, /godot lock wait timeout/);
      assert.equal(fs.existsSync(path.join(s.repo, 'build', 'e2e', 'fake')), false);
    } finally {
      held.release();
    }
  } finally {
    if (prevDir === undefined) delete process.env.WATTLANDS_GODOT_LOCK_DIR;
    else process.env.WATTLANDS_GODOT_LOCK_DIR = prevDir;
    s.cleanup();
  }
});
