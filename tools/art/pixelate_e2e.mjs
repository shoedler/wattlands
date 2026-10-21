#!/usr/bin/env node
// End-to-end check of the art pipeline (BRIEF 3.10, 7.1): generate.mjs against tools/art/mock_fal,
// then tools/art/pixelate.gd through the Godot wrapper, twice, on a temp project root built from
// tests/art/fixtures/e2e/art.json. Checks every sprite and part: size, palette-only colors, alpha
// only 0 or 255, fit and align, cover, tiling, sprites.json, and byte-identical re-runs.
//
//   node tools/art/pixelate_e2e.mjs [--shell=sh|ps] [--keep]
//
// Run it after the project's import and after GUT, never from inside a Godot process (BRIEF 7).
// --shell=ps uses tools/godot.ps1 (Windows PowerShell) instead of tools/godot.sh; --keep keeps the
// temp root. Prints "pixelate_e2e: PASS" and exits 0, or lists the failures and exits 1.
import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { decodePng } from './lib/png.mjs';
import { startMockFal } from './mock_fal/server.mjs';

const ART_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(ART_DIR, '..', '..');
const GAME = 'e2e';
const FIXTURE = path.join(REPO, 'tests', 'art', 'fixtures', 'e2e', 'art.json');

const args = process.argv.slice(2);
const shell = (args.find((a) => a.startsWith('--shell=')) ?? '--shell=sh').slice(8);
const keep = args.includes('--keep');
const failures = [];
const check = (cond, msg) => {
  if (!cond) failures.push(msg);
};

function run(cmd, cmdArgs, { env = process.env, cwd = REPO, timeoutMs = 15 * 60 * 1000 } = {}) {
  return new Promise((resolve) => {
    const child = spawn(cmd, cmdArgs, { cwd, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    let out = '';
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (out += d));
    const timer = setTimeout(() => child.kill(), timeoutMs);
    child.on('error', (e) => {
      clearTimeout(timer);
      resolve({ code: 127, out: `${out}\ncannot start ${cmd}: ${e.message}` });
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, out });
    });
  });
}

/** Generation never reaches fal: no key, no permission, and --mock. */
function artEnv() {
  const env = { ...process.env };
  delete env.FAL_KEY;
  delete env.WATTLANDS_ALLOW_ART;
  return env;
}

function pixelate(root) {
  const user = ['--', `--game=${GAME}`, `--root=${root.split(path.sep).join('/')}`];
  const godot = ['--headless', '--path', REPO, '-s', 'tools/art/pixelate.gd', ...user];
  if (shell === 'ps') {
    return run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(REPO, 'tools', 'godot.ps1'), ...godot]);
  }
  return run('bash', [path.join(REPO, 'tools', 'godot.sh').split(path.sep).join('/'), ...godot]);
}

function hashDir(dir) {
  const out = {};
  for (const f of fs.readdirSync(dir).sort()) out[f] = crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, f))).digest('hex');
  return out;
}

function bbox(img, alphaMin = 255) {
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -1;
  let y1 = -1;
  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      if (img.data[(y * img.width + x) * 4 + 3] >= alphaMin) {
        x0 = Math.min(x0, x);
        y0 = Math.min(y0, y);
        x1 = Math.max(x1, x);
        y1 = Math.max(y1, y);
      }
    }
  }
  return x1 < 0 ? null : { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

function checkPixels(name, img, palette) {
  let bad = 0;
  for (let i = 0; i < img.data.length; i += 4) {
    const a = img.data[i + 3];
    const rgb = `#${[img.data[i], img.data[i + 1], img.data[i + 2]].map((v) => v.toString(16).padStart(2, '0')).join('')}`;
    if (a === 0) {
      if (rgb !== '#000000') bad += 1;
    } else if (a !== 255 || !palette.has(rgb)) {
      bad += 1;
    }
  }
  check(bad === 0, `${name}: ${bad} pixel(s) are neither a palette color at alpha 255 nor (0, 0, 0, 0)`);
}

async function main() {
  const art = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));
  const palette = new Set(art.palette.map((c) => c.toLowerCase()));
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands_art_e2e_'));
  fs.mkdirSync(path.join(root, 'assets', GAME), { recursive: true });
  fs.copyFileSync(FIXTURE, path.join(root, 'assets', GAME, 'art.json'));
  const mock = await startMockFal();
  try {
    const gen = await run(process.execPath, [path.join(ART_DIR, 'generate.mjs'), `--game=${GAME}`, `--root=${root}`, `--mock=${mock.url}`, '--poll-ms=5'], { env: artEnv() });
    process.stdout.write(gen.out);
    check(gen.code === 0, `generate.mjs exited ${gen.code}`);
    check(mock.state.counts.submit === art.sprites.length, `expected ${art.sprites.length} requests, mock saw ${mock.state.counts.submit}`);
    if (gen.code !== 0) return root;

    const p1 = await pixelate(root);
    process.stdout.write(p1.out);
    check(p1.code === 0, `pixelate.gd exited ${p1.code}`);
    for (const bad of ['SCRIPT ERROR', 'Parse Error', 'Debugger Break']) check(!p1.out.includes(bad), `pixelate output contains "${bad}"`);
    const dir = path.join(root, 'assets', GAME, 'sprites');
    if (p1.code !== 0 || !fs.existsSync(dir)) return root;

    const index = JSON.parse(fs.readFileSync(path.join(dir, 'sprites.json'), 'utf8'));
    for (const s of art.sprites) {
      const file = path.join(dir, `${s.id}.png`);
      if (!fs.existsSync(file)) {
        check(false, `${s.id}.png is missing`);
        continue;
      }
      const img = decodePng(fs.readFileSync(file));
      check(img.width === s.size[0] && img.height === s.size[1], `${s.id}: ${img.width}x${img.height}, expected ${s.size.join('x')}`);
      checkPixels(s.id, img, palette);
      const box = bbox(img);
      check(box !== null, `${s.id}: no opaque pixels`);
      if (box) {
        if (s.background === 'opaque' || s.tile) {
          check(box.x === 0 && box.y === 0 && box.w === s.size[0] && box.h === s.size[1], `${s.id}: ${s.tile ? 'tile' : 'cover'} leaves transparent pixels ${JSON.stringify(box)}`);
        } else {
          const align = s.align ?? 'bottom_center';
          const fits = box.w === s.size[0] || box.h === s.size[1] || box.w >= s.size[0] - 1 || box.h >= s.size[1] - 1;
          check(fits, `${s.id}: content ${JSON.stringify(box)} does not fill the sprite along one axis`);
          if (align.startsWith('bottom')) check(box.y + box.h === s.size[1], `${s.id}: not bottom aligned ${JSON.stringify(box)}`);
          if (align.endsWith('left')) check(box.x === 0, `${s.id}: not left aligned ${JSON.stringify(box)}`);
          if (align.endsWith('center') || align === 'center') {
            const left = box.x;
            const right = s.size[0] - (box.x + box.w);
            check(Math.abs(left - right) <= 1, `${s.id}: not centred horizontally ${JSON.stringify(box)}`);
          }
        }
      }
      const entry = index.sprites?.[s.id];
      check(entry && entry.file === `${s.id}.png`, `${s.id}: missing from sprites.json`);
      for (const [part, rect] of Object.entries(s.parts ?? {})) {
        const pf = path.join(dir, `${s.id}__${part}.png`);
        if (!fs.existsSync(pf)) {
          check(false, `${s.id}__${part}.png is missing`);
          continue;
        }
        const pi = decodePng(fs.readFileSync(pf));
        check(pi.width === rect[2] && pi.height === rect[3], `${s.id}__${part}: ${pi.width}x${pi.height}`);
        checkPixels(`${s.id}__${part}`, pi, palette);
        let same = true;
        for (let y = 0; y < rect[3] && same; y++) {
          const a = Buffer.from(pi.data.buffer, pi.data.byteOffset + y * rect[2] * 4, rect[2] * 4);
          const o = ((rect[1] + y) * img.width + rect[0]) * 4;
          const b = Buffer.from(img.data.buffer, img.data.byteOffset + o, rect[2] * 4);
          same = a.equals(b);
        }
        check(same, `${s.id}__${part}: pixels differ from the sprite's region`);
        check(entry?.parts?.[part]?.file === `${s.id}__${part}.png`, `${s.id}.${part}: missing from sprites.json`);
      }
    }
    check(JSON.stringify(index.sprites?.turret_tall?.anchor) === '[8,40]', 'turret_tall: anchor [8, 40] in sprites.json');
    check(JSON.stringify(index.sprites?.fish_marlin?.anchor) === '[32,11]', 'fish_marlin: centre anchor [32, 11] in sprites.json');

    const first = hashDir(dir);
    const p2 = await pixelate(root);
    check(p2.code === 0, `second pixelate.gd run exited ${p2.code}`);
    const second = hashDir(dir);
    check(JSON.stringify(first) === JSON.stringify(second), 'a second run changed the output bytes');
    return root;
  } finally {
    await mock.close();
  }
}

const root = await main();
if (failures.length > 0) {
  for (const f of failures) process.stderr.write(`pixelate_e2e: FAIL ${f}\n`);
  process.stderr.write(`pixelate_e2e: ${failures.length} failure(s); temp root kept at ${root}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write('pixelate_e2e: PASS\n');
  if (!keep) fs.rmSync(root, { recursive: true, force: true });
  else process.stdout.write(`pixelate_e2e: temp root kept at ${root}\n`);
}
