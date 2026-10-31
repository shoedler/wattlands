// The art contract S0 freezes: the bake reproduces the committed files, every path in kit.json exists,
// the indexed planes hold only indices, the view's anchors land on real pixels, and png.mjs stays a wrapper
// over the repo's one codec.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readPng } from '../../../../src/games/workout/art/png.mjs';
import { CRANK_FRAMES, crankTheta, chainOffset, nearPedalTable } from '../../../../src/games/workout/art/rig.mjs';
import { WALL, WINDOW } from '../../../../src/games/workout/art/palette.mjs';

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

/** One pixel of a decoded PNG: alpha and the palette index an indexed plane stores. */
function pixel(png, x, y) {
  const i = (y * png.width + x) * 4;
  return { index: png.data[i] / 2, alpha: png.data[i + 3] };
}

test('smoke rises from chimneys the near_trees plane really draws', () => {
  const smoke = kit.props.smoke;
  assert.equal(smoke.plane, 'near_trees');
  const plane = kit.planes.find((p) => p.name === smoke.plane);
  assert.ok(plane, 'the plane exists');
  const png = readPng(fromRes(plane.path));
  assert.ok(smoke.chimneys.length >= 2, 'more than one house in a 1600 px strip');
  for (const [x, y] of smoke.chimneys) {
    assert.ok(x >= 0 && x < png.width && y >= 0 && y < png.height, `${x}, ${y} is on the strip`);
    for (const dy of [0, 1, 4, 8]) {
      const p = pixel(png, x, y + dy);
      assert.equal(p.alpha, 255, `chimney at ${x}, ${y + dy}`);
      assert.ok(p.index >= WALL && p.index < WINDOW, `chimney at ${x}, ${y + dy} is wall or roof, got ${p.index}`);
    }
  }
  const sprite = readPng(fromRes(smoke.path));
  assert.equal(pixel(sprite, smoke.origin[0], smoke.origin[1]).alpha, 255, 'a puff starts on the origin');
});

test('each pose has a mouth beside its own head, and mouth stays the seat one', () => {
  const { mouth, mouth_by_pose: byPose, pose_rows: rows, cell, cols, frames, slots } = kit.rider;
  assert.deepEqual(Object.keys(byPose).sort(), Object.keys(rows).sort());
  assert.deepEqual(mouth, byPose.seat);
  const sheet = readPng(fromRes(slots[0]));
  /** The distance from a cell point to the nearest opaque pixel of that sprite frame. */
  const nearest = (frame, row, [mx, my]) => {
    let best = Infinity;
    for (let y = 0; y < cell[1]; y++) {
      for (let x = 0; x < cell[0]; x++) {
        if (pixel(sheet, (frame % cols) * cell[0] + x, row * cell[1] + y).alpha > 0) {
          best = Math.min(best, Math.hypot(x - mx, y - my));
        }
      }
    }
    return best;
  };
  for (const [name, at] of Object.entries(byPose)) {
    const count = name === 'stop' ? 1 : frames;
    for (let k = 0; k < count; k++) {
      const row = rows[name] + Math.floor(k / cols);
      assert.ok(nearest(k, row, at) <= 2.5, `${name} frame ${k}: ${at} is ${nearest(k, row, at)} px off the rider`);
    }
  }
  // The single seat point floats free of the other two riding poses, which is why the key exists.
  assert.ok(nearest(0, rows.stand, mouth) > 2.5);
  assert.ok(nearest(0, rows.situp, mouth) > 2.5);
});

test('crowd flags have a hand to go in: hand_up is a raised hand in row 1 and empty in row 0', () => {
  const { path, cell, count, hand_up: hand } = kit.props.crowd;
  const sheet = readPng(fromRes(path));
  for (let s = 0; s < count; s++) {
    assert.ok(pixel(sheet, s * cell[0] + hand[0], cell[1] + hand[1]).alpha > 0, `spectator ${s}, hands up`);
    assert.equal(pixel(sheet, s * cell[0] + hand[0], hand[1]).alpha, 0, `spectator ${s}, hands down`);
  }
  const flag = kit.props.flag;
  const flags = readPng(fromRes(flag.path));
  for (let f = 0; f < flag.frames; f++) {
    assert.ok(pixel(flags, f * flag.cell[0] + flag.grip[0], flag.grip[1]).alpha > 0, `flag frame ${f} has its pole there`);
  }
});
