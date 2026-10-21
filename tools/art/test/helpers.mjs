// Shared helpers for the tools/art node:test suite. Importing this file has no side effects.
//
// Safety rules (BRIEF 7.1): every test starts generate.mjs with an explicit child environment that
// removes WATTLANDS_ALLOW_ART and removes FAL_KEY or sets a dummy, and passes --mock except in the
// refusal cases. No test ever sets WATTLANDS_ALLOW_ART.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { startMockFal } from '../mock_fal/server.mjs';

export const TEST_DIR = path.dirname(fileURLToPath(import.meta.url));
export const ART_DIR = path.resolve(TEST_DIR, '..');
export const REPO_ROOT = path.resolve(ART_DIR, '..', '..');
export const GENERATE = path.join(ART_DIR, 'generate.mjs');
export const NO_NETWORK_PRELOAD = pathToFileURL(path.join(TEST_DIR, 'helpers', 'no_network_preload.mjs')).href;

/** A dummy key in fal's "<id>:<secret>" shape. It is never valid anywhere. */
export const DUMMY_KEY = 'dummyid-4f1c8e:dummysecret-9a7e3b55c2';
export const DUMMY_KEY_PARTS = [DUMMY_KEY, 'dummyid-4f1c8e', 'dummysecret-9a7e3b55c2'];

/**
 * The child environment for generate.mjs: the parent's environment without WATTLANDS_ALLOW_ART and
 * FAL_KEY, plus FAL_KEY=<dummy> when `dummyKey` is true, plus `extra` (which may not name
 * WATTLANDS_ALLOW_ART).
 */
export function childEnv({ dummyKey = false, extra = {} } = {}) {
  if (Object.hasOwn(extra, 'WATTLANDS_ALLOW_ART')) throw new Error('tests never set WATTLANDS_ALLOW_ART');
  if (Object.hasOwn(extra, 'FAL_KEY')) throw new Error('use dummyKey: true for FAL_KEY');
  const env = { ...process.env };
  delete env.WATTLANDS_ALLOW_ART;
  delete env.FAL_KEY;
  if (dummyKey) env.FAL_KEY = DUMMY_KEY;
  for (const [k, v] of Object.entries(extra)) {
    if (v === undefined || v === null) delete env[k];
    else env[k] = String(v);
  }
  return env;
}

/**
 * Runs generate.mjs in a child process (async, so an in-process mock keeps serving).
 * Options: env (required: from childEnv), preload (a module URL for --import), timeoutMs.
 */
export function runGenerate(args, { env, preload = null, timeoutMs = 60000 } = {}) {
  if (!env) throw new Error('runGenerate needs an explicit env from childEnv()');
  if (Object.hasOwn(env, 'WATTLANDS_ALLOW_ART')) throw new Error('tests never pass WATTLANDS_ALLOW_ART to generate.mjs');
  const nodeArgs = preload ? ['--import', preload, GENERATE, ...args] : [GENERATE, ...args];
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, nodeArgs, { env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`generate.mjs timed out after ${timeoutMs} ms\n${stdout}\n${stderr}`));
    }, timeoutMs);
    child.on('error', reject);
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, stdout, stderr });
    });
  });
}

/** A fresh temp project root with assets/<game>/art.json. */
export function makeRoot(game, art) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands_art_'));
  const dir = path.join(root, 'assets', game);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'art.json'), `${JSON.stringify(art, null, 2)}\n`);
  return root;
}

export function writeArt(root, game, art) {
  fs.writeFileSync(path.join(root, 'assets', game, 'art.json'), `${JSON.stringify(art, null, 2)}\n`);
}

export function removeRoot(root) {
  fs.rmSync(root, { recursive: true, force: true });
}

export function readManifest(root, game) {
  return JSON.parse(fs.readFileSync(path.join(root, 'assets', game, 'art_manifest.json'), 'utf8'));
}

export function manifestFile(root, game) {
  return path.join(root, 'assets', game, 'art_manifest.json');
}

export const PALETTE = ['#0b0b0e', '#3e3e46', '#a9a6aa', '#d6d2cf', '#a33412', '#f08a2c', '#2a5aa8', '#6fb4ff'];

/** A small art.json: two transparent sprites (one with parts), one opaque backdrop, one tile strip. */
export function smallArt(overrides = {}) {
  return {
    palette: PALETTE,
    style: 'Side-view 2D game sprite in chunky pixel art, flat shading, no text or logos.',
    sprites: [
      { id: 'boat', prompt: 'a small white boat, bow right', size: [80, 32], parts: { hull: [0, 16, 80, 16], cabin: [20, 0, 40, 16] } },
      { id: 'fish_tuna', prompt: 'a tuna facing left', size: [44, 16], anchor: 'center' },
      { id: 'bg_sky', prompt: 'a pale sky', size: [320, 120], background: 'opaque' },
      { id: 'reef', prompt: 'a coral reef strip', size: [416, 18], tile: true, mirror: true },
    ],
    ...overrides,
  };
}

/** Starts a mock for one test and stops it afterwards. */
export async function mockFor(t, config = {}) {
  const mock = await startMockFal({ config });
  t.after(() => mock.close());
  return mock;
}

/** Common generate.mjs arguments for a mock run. */
export function mockArgs(game, root, mock, extra = []) {
  return [`--game=${game}`, `--root=${root}`, `--mock=${mock.url}`, '--poll-ms=5', ...extra];
}

/** Every file under dir, recursively, as absolute paths. */
export function walk(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}
