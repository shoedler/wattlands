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
import { BB, CRANK, CHAIN_PERIOD, CRANK_FRAMES, crankTheta, chainOffset, nearPedalTable, pedalAt } from '../../../../src/games/workout/art/rig.mjs';
import { GLOW, MIST, MIST_GROUND, RESERVE, STAR, WALL, WINDOW } from '../../../../src/games/workout/art/palette.mjs';
import { HOLLOW_BODY, PEDAL, SLOT_COLORS, slotLook } from '../../../../src/games/workout/art/riders.mjs';
import { hex } from '../../../../src/games/workout/art/raster.mjs';

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

/** How many pixels of the cell at (cx, cy) have exactly this [r, g, b]. */
function countColour(png, cx, cy, w, h, [r, g, b]) {
  let n = 0;
  for (let y = cy; y < cy + h; y++) {
    for (let x = cx; x < cx + w; x++) {
      const i = (y * png.width + x) * 4;
      if (png.data[i + 3] > 0 && png.data[i] === r && png.data[i + 1] === g && png.data[i + 2] === b) n++;
    }
  }
  return n;
}

test('a pedal-coloured pixel sits within 1 px of near_pedal in every seat and stand frame', () => {
  const { pose_rows: rows, cell, cols, frames, slots, near_pedal: table } = kit.rider;
  for (const path of slots) {
    const sheet = readPng(fromRes(path));
    for (const name of ['seat', 'stand']) {
      for (let k = 0; k < frames; k++) {
        const cx = (k % cols) * cell[0];
        const cy = (rows[name] + Math.floor(k / cols)) * cell[1];
        const [px, py] = table[k];
        assert.ok(countColour(sheet, cx + px - 2, cy + py - 1, 5, 3, PEDAL) > 0, `${path} ${name} frame ${k}`);
      }
    }
  }
});

test('near_pedal follows the angle formula; the far pedal is opposite', () => {
  for (let k = 0; k < CRANK_FRAMES; k++) {
    const a = ((-90 + k * 15) * Math.PI) / 180;
    const [x, y] = kit.rider.near_pedal[k];
    assert.ok(Math.abs(x - (BB[0] + CRANK * Math.cos(a))) <= 1, `frame ${k} x`);
    assert.ok(Math.abs(y - (BB[1] + CRANK * Math.sin(a))) <= 1, `frame ${k} y`);
    const near = pedalAt(k);
    const far = pedalAt(k + CRANK_FRAMES / 2);
    assert.ok(Math.abs(near[0] + far[0] - 2 * BB[0]) < 1e-9 && Math.abs(near[1] + far[1] - 2 * BB[1]) < 1e-9, `frame ${k}`);
  }
});

test('frame 23 runs into frame 0: the chain and the cranks close the revolution with the same step', () => {
  const step = (a, b) => (b - a + CHAIN_PERIOD) % CHAIN_PERIOD;
  const steps = [];
  for (let k = 0; k < CRANK_FRAMES; k++) steps.push(step(chainOffset(k), chainOffset((k + 1) % CRANK_FRAMES)));
  for (const s of steps) assert.ok(s === 1 || s === 2, `steps ${steps}`);
  assert.equal(steps.reduce((u, v) => u + v, 0), 32, 'exactly 32 px of chain per revolution');
  // The pixels agree: frames 23 and 0 differ by about as much as any neighbouring frames do.
  const sheet = readPng(fromRes(kit.rider.slots[0]));
  const { cell, cols } = kit.rider;
  const diff = (a, b) => {
    let n = 0;
    for (let y = 0; y < cell[1]; y++) {
      for (let x = 0; x < cell[0]; x++) {
        const ia = ((Math.floor(a / cols) * cell[1] + y) * sheet.width + (a % cols) * cell[0] + x) * 4;
        const ib = ((Math.floor(b / cols) * cell[1] + y) * sheet.width + (b % cols) * cell[0] + x) * 4;
        if (sheet.data[ia] !== sheet.data[ib] || sheet.data[ia + 3] !== sheet.data[ib + 3]) n++;
      }
    }
    return n;
  };
  const inner = [];
  for (let k = 0; k < CRANK_FRAMES - 1; k++) inner.push(diff(k, k + 1));
  assert.ok(diff(23, 0) <= Math.max(...inner), `seam ${diff(23, 0)}, the largest inner step ${Math.max(...inner)}`);
  assert.ok(diff(23, 0) > 0, 'the frames do move');
});

test('slot looks: colours and patterns as Wl.slot_look; jersey colours are on the sprite', () => {
  const wl = readFileSync(join(repo, 'addons/wattlands/contracts/wl.gd'), 'utf8');
  const block = wl.slice(wl.indexOf('const SLOT_COLORS'), wl.indexOf('const SLOT_COLOR_NAMES'));
  const colours = [...block.matchAll(/Color\("(#[0-9A-Fa-f]{6})"\)/g)].map((m) => m[1].toUpperCase());
  assert.deepEqual(SLOT_COLORS, colours);
  assert.deepEqual(kit.rider.slot_colors, colours);
  const patterns = [...wl.match(/SLOT_PATTERNS: Array\[String\] = \[(.*)\]/)[1].matchAll(/"(\w+)"/g)].map((m) => m[1]);
  const { cell, slots } = kit.rider;
  slots.forEach((path, s) => {
    const look = slotLook(s);
    assert.equal(look.pattern, patterns[s % 4], `slot ${s}`);
    const sheet = readPng(fromRes(path));
    const colour = hex(SLOT_COLORS[s % 4]);
    if (s < 4) {
      assert.ok(countColour(sheet, 0, 0, cell[0], cell[1], colour) >= 40, `slot ${s} wears its colour`);
    } else {
      assert.ok(countColour(sheet, 0, 0, cell[0], cell[1], hex(HOLLOW_BODY)) >= 25, `slot ${s} has the hollow body`);
      assert.ok(countColour(sheet, 0, 0, cell[0], cell[1], colour) >= 8, `slot ${s} keeps its colour on the sleeve`);
    }
  });
  // Same colour, different pattern or body: no two sheets are the same.
  const first = slots.map((p) => Buffer.from(readPng(fromRes(p)).data).toString('latin1'));
  assert.equal(new Set(first).size, slots.length);
});

/** Palette index and height of a column's first opaque pixel; mist that burns off does not count. */
function firstLand(png, x) {
  for (let y = 0; y < png.height; y++) {
    const p = pixel(png, x, y);
    if (p.alpha > 0 && p.index !== MIST && p.index !== MIST + 1) return { y, index: p.index };
  }
  return null;
}

test('strips are seamless: the first and last columns meet within 3 px', () => {
  const files = ['clouds_hi', 'clouds_lo', 'far_hills', 'mid_hills', 'near_trees', 'poles', 'road'];
  for (let f = 0; f < 4; f++) files.push(`verge_far_${f}`, `verge_near_${f}`);
  files.push('foreground_0', 'foreground_1');
  for (const name of files) {
    const png = readPng(join(assets, 'world', `${name}.png`));
    const a = firstLand(png, 0);
    const b = firstLand(png, png.width - 1);
    assert.equal(a === null, b === null, `${name}: one edge is empty`);
    if (a) assert.ok(Math.abs(a.y - b.y) <= 3, `${name}: ${a.y} against ${b.y}`);
  }
});

test('no world plane uses a reserved index', () => {
  for (const path of walk(join(assets, 'world')).filter((p) => p.endsWith('.png') && !/tod_lut|sun/.test(p))) {
    const { data } = readPng(path);
    for (let i = 0; i < data.length; i += 4) {
      if (data[i + 3] > 0) assert.ok(data[i] / 2 < RESERVE, `${path}: index ${data[i] / 2}`);
    }
  }
});

test('one morning in the LUT: stars gone by sunrise, windows lit then dark, mist burns off, no holes', () => {
  const lut = readPng(fromRes(kit.lut.path));
  assert.equal(kit.lut.rows, 32);
  const at = (index, row) => {
    const i = (row * lut.width + index) * 4;
    return [lut.data[i], lut.data[i + 1], lut.data[i + 2], lut.data[i + 3]];
  };
  const luma = (c) => 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  const sunrise = Math.floor(0.22 * 31);
  assert.equal(at(STAR, 0)[3], 255, 'stars at blue hour');
  assert.equal(at(STAR, sunrise + 1)[3], 0, 'no stars after sunrise');
  assert.equal(at(MIST, 0)[3], 255, 'mist at blue hour');
  assert.equal(at(MIST, Math.floor(0.65 * 31))[3], 0, 'mist gone by the morning');
  assert.ok(luma(at(WINDOW, 0)) > 150, 'windows lit at dawn');
  assert.ok(luma(at(WINDOW, 31)) < 80, 'windows dark by day');
  for (let r = 0; r < 32; r++) {
    for (const i of [WINDOW, GLOW, MIST_GROUND, MIST_GROUND + 1]) assert.equal(at(i, r)[3], 255, `index ${i} row ${r} would be a hole`);
  }
  const sky = (row) => luma(at(0, row));
  assert.ok(sky(0) < sky(6) && sky(6) < sky(12), 'the top of the sky lightens through the morning');
});

test('every wheel frame has its valve and a different picture', () => {
  const wheel = readPng(fromRes(kit.wheel.path));
  const seen = new Set();
  for (let f = 0; f < kit.wheel.frames; f++) {
    assert.ok(countColour(wheel, f * 27, 0, 27, 27, [232, 232, 224]) >= 1, `frame ${f}`);
    let s = '';
    for (let y = 0; y < 27; y++) for (let x = 0; x < 27; x++) s += wheel.data[(y * wheel.width + f * 27 + x) * 4];
    seen.add(s);
  }
  assert.equal(seen.size, kit.wheel.frames);
});
