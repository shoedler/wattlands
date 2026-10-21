// tools/e2e/fixtures/harness.mjs: helpers for the harness's own tests (not a test file). Runs
// tools/e2e/run.mjs against the stand-ins in this folder, a throwaway repo and a private lock dir.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const RUN = path.join(HERE, '..', 'run.mjs');
const FIX = HERE.replaceAll('\\', '/');

export function makeRepo({ e2eCheck = null, gameJson = { id: 'fake', e2e_content: 'e2e' } } = {}) {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-e2e-repo-'));
  fs.mkdirSync(path.join(repo, 'src', 'games', 'fake'), { recursive: true });
  fs.writeFileSync(path.join(repo, 'src', 'games', 'fake', 'game.json'), typeof gameJson === 'string' ? gameJson : JSON.stringify(gameJson));
  if (e2eCheck !== null) {
    fs.mkdirSync(path.join(repo, 'tests', 'games', 'fake'), { recursive: true });
    fs.writeFileSync(path.join(repo, 'tests', 'games', 'fake', 'e2e_check.mjs'), e2eCheck);
  }
  return repo;
}

export function harnessArgs(repo, extra = []) {
  return [
    RUN,
    `--repo=${repo}`,
    '--games=fake',
    `--peer-cmd=node ${FIX}/fake_peer.mjs`,
    `--relay-cmd=node ${FIX}/fake_relay.mjs`,
    `--strava-cmd=node ${FIX}/fake_strava.mjs --port=0`,
    `--fit-check-cmd=node ${FIX}/fake_fit_check.mjs`,
    '--kill-after=0.3',
    '--restart-delay=0.2',
    '--boot-timeout=20',
    '--service-timeout=20',
    '--game-timeout=60',
    '--cooldown-s=0.3',
    ...extra,
  ];
}

export function runHarness(args, { env = {}, lockDir, timeoutMs = 90_000 } = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
      env: {
        ...process.env,
        WATTLANDS_GODOT_LOCK_DIR: lockDir,
        WATTLANDS_GODOT_LOCK_CAP: '4',
        FAKE_PEER_SESSION_MS: '1500',
        ...env,
      },
    });
    let out = '';
    child.stdout.on('data', (d) => {
      out += d;
    });
    child.stderr.on('data', (d) => {
      out += d;
    });
    const timer = setTimeout(() => child.kill(), timeoutMs);
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, out });
    });
  });
}

export function setup(opts) {
  const repo = makeRepo(opts);
  const lockDir = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands-e2e-lock-'));
  const cleanup = () => {
    fs.rmSync(repo, { recursive: true, force: true });
    fs.rmSync(lockDir, { recursive: true, force: true });
  };
  return { repo, lockDir, cleanup, report: () => JSON.parse(fs.readFileSync(path.join(repo, 'build', 'e2e', 'fake', 'report.json'), 'utf8')) };
}

export function check(report, name) {
  return report.checks.find((c) => c.name === name);
}
