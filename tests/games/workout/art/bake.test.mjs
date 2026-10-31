// The art contract S0 freezes: the bake reproduces the committed files, every path in kit.json exists,
// the indexed planes hold only indices, and png.mjs stays a wrapper over the repo's one codec.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readPng } from '../../../../src/games/workout/art/png.mjs';
import { CRANK_FRAMES, crankTheta, chainOffset, nearPedalTable } from '../../../../src/games/workout/art/rig.mjs';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');
const assets = join(repo, 'assets/workout');
const kit = JSON.parse(readFileSync(join(assets, 'kit.json'), 'utf8'));
const fromRes = (p) => join(repo, p.replace('res://', ''));

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path, out);
    else out.push(path);
  }
  return out;
}

/** Every res:// string in a JSON value. */
function resPaths(v, out = []) {
  if (typeof v === 'string' && v.startsWith('res://')) out.push(v);
  else if (Array.isArray(v)) v.forEach((u) => resPaths(u, out));
  else if (v && typeof v === 'object') Object.values(v).forEach((u) => resPaths(u, out));
  return out;
}

test('bake --check passes on the committed art', () => {
  const r = spawnSync(process.execPath, [join(repo, 'src/games/workout/art/bake.mjs'), '--check'], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
});

test('png.mjs wraps the repo codec and has no PNG code of its own', () => {
  const text = readFileSync(join(repo, 'src/games/workout/art/png.mjs'), 'utf8');
  assert.match(text, /tools\/art\/lib\/png\.mjs/);
  assert.doesNotMatch(text, /deflate|inflate|crc/i);
});

test('kit.json has every key, and every path in it exists', () => {
  for (const k of ['version', 'base', 'lut', 'tod', 'rider', 'wheel', 'fx', 'planes', 'sun', 'road', 'props']) {
    assert.ok(k in kit, k);
  }
  const paths = resPaths(kit);
  assert.ok(paths.length > 30);
  for (const p of paths) assert.ok(existsSync(fromRes(p)), p);
  assert.equal(kit.tod.length, 32);
  for (const row of kit.tod) {
    for (const k of ['sky_top', 'rider_tint', 'bank', 'bank_hi', 'sun', 'breath']) assert.ok(k in row, k);
    for (const u of row.rider_tint) assert.ok(u >= 0.72, 'slot colours stay readable');
  }
  for (const [name, prop] of Object.entries(kit.props)) assert.ok(prop.path.startsWith('res://'), name);
});

test('sheet sizes match the kit', () => {
  for (const p of kit.rider.slots) {
    const png = readPng(fromRes(p));
    assert.deepEqual([png.width, png.height], [528, 1092], p);
  }
  const wheel = readPng(fromRes(kit.wheel.path));
  assert.deepEqual([wheel.width, wheel.height], [27 * kit.wheel.frames, 27]);
  const lut = readPng(fromRes(kit.lut.path));
  assert.deepEqual([lut.width, lut.height], [kit.lut.size, kit.lut.rows]);
  const card = readPng(join(assets, 'picker_card.png'));
  assert.deepEqual([card.width, card.height], [960, 540]);
});

test('world planes hold only palette indices: G = B = 0, R even and under 256, alpha 0 or 255', () => {
  const planes = walk(join(assets, 'world')).filter((p) => p.endsWith('.png') && !/tod_lut|sun/.test(p));
  assert.ok(planes.length >= 18);
  for (const path of planes) {
    const { data } = readPng(path);
    for (let i = 0; i < data.length; i += 4) {
      if (data[i + 3] === 0) continue;
      assert.equal(data[i + 3], 255, path);
      assert.equal(data[i + 1] | data[i + 2], 0, path);
      assert.equal(data[i] & 1, 0, path);
    }
  }
});

test('the crank contract: frame 0 up, frame 6 forward, frame 12 down, clockwise', () => {
  assert.equal(kit.rider.frames, CRANK_FRAMES);
  const pedal = nearPedalTable();
  assert.deepEqual(kit.rider.near_pedal, pedal);
  assert.deepEqual(pedal[0], [38, 62]);
  assert.deepEqual(pedal[6], [45, 69]);
  assert.deepEqual(pedal[12], [38, 76]);
  assert.ok(Math.abs(crankTheta(0) + Math.PI / 2) < 1e-9);
  assert.equal(chainOffset(CRANK_FRAMES), 0, 'the chain pattern closes after a revolution');
});

test('assets/workout stays small, audio apart', () => {
  const audio = join(assets, 'audio') + sep;
  let bytes = 0;
  for (const path of walk(assets)) {
    if (!path.startsWith(audio)) bytes += statSync(path).size;
  }
  assert.ok(bytes < 6e6, `${bytes} bytes`);
});
