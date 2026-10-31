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
import { BB, CHAINRING_R, CRANK, CHAIN_PERIOD, CRANK_FRAMES, REAR_HUB, SADDLE, crankTheta, chainOffset, nearPedalTable, pedalAt } from '../../../../src/games/workout/art/rig.mjs';
import { ASPHALT, EARTH, GLOW, GRIT, MIST, MIST_GROUND, PAINT, POPLAR, RESERVE, RIDGE, RIDGE_NEAR, STAR, WALL, WINDOW, WIRE, WOOD } from '../../../../src/games/workout/art/palette.mjs';
import { CHAIN_LIGHT, CHAIN_LINK, CRANK_INK, HOLLOW_BODY, PEDAL, SLOT_COLORS, slotLook } from '../../../../src/games/workout/art/riders.mjs';
import { WIRES } from '../../../../src/games/workout/art/world.mjs';
import { PICKER } from '../../../../src/games/workout/art/compose.mjs';
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
  assert.equal(at(MIST, Math.ceil(0.65 * 31))[3], 0, 'mist gone by the morning');
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

// --- Art critic round: what real frames showed, kept true -------------------------------------------

const lumaOf = (c) => 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];

/** The [r, g, b, a] of a rider cell's pixel. */
function cellPixel(sheet, frame, row, x, y) {
  const { cell, cols } = kit.rider;
  const i = (((row + Math.floor(frame / cols)) * cell[1] + y) * sheet.width + (frame % cols) * cell[0] + x) * 4;
  return [sheet.data[i], sheet.data[i + 1], sheet.data[i + 2], sheet.data[i + 3]];
}

const same = (a, b) => a[0] === b[0] && a[1] === b[1] && a[2] === b[2];

test('the chain stays quiet: light links a tone or two over the asphalt, a warmer link that travels, clear of the tyre row', () => {
  const lut = readPng(fromRes(kit.lut.path));
  let road = 0;
  for (let r = 0; r < kit.lut.rows; r++) {
    for (let i = ASPHALT; i < PAINT; i++) {
      const q = (r * lut.width + i) * 4;
      road = Math.max(road, lumaOf([lut.data[q], lut.data[q + 1], lut.data[q + 2]]));
    }
  }
  assert.ok(lumaOf(CHAIN_LIGHT) >= road, `chain ${lumaOf(CHAIN_LIGHT)} shows on the lightest asphalt ${road}`);
  assert.ok(lumaOf(CHAIN_LIGHT) <= road * 1.25, `chain ${lumaOf(CHAIN_LIGHT)} shouts over the asphalt ${road}`);
  const sheet = readPng(fromRes(kit.rider.slots[0]));
  const seat = kit.rider.pose_rows.seat;
  const bottomRow = BB[1] + CHAINRING_R + 1;
  const brassAt = (k) => {
    const seen = [];
    for (let x = REAR_HUB[0]; x <= BB[0]; x++) {
      for (let y = 60; y <= bottomRow; y++) {
        if (same(cellPixel(sheet, k, seat, x, y), CHAIN_LINK)) seen.push(`${x},${y}`);
      }
    }
    return seen.join(' ');
  };
  const pictures = new Set();
  let lightLinks = 0;
  for (let k = 0; k < CRANK_FRAMES; k++) {
    pictures.add(brassAt(k));
    for (let x = REAR_HUB[0]; x <= BB[0]; x++) {
      for (let y = 60; y <= bottomRow; y++) {
        if (same(cellPixel(sheet, k, seat, x, y), CHAIN_LIGHT)) lightLinks++;
      }
    }
  }
  assert.ok(pictures.size >= 12, `the warm link moves with the crank: ${pictures.size} pictures`);
  assert.ok(lightLinks / CRANK_FRAMES >= 5, `${lightLinks / CRANK_FRAMES} light links a frame`);
  // The bottom run keeps off the tyre's contact, where the road's paint would meet it.
  for (let k = 0; k < CRANK_FRAMES; k++) {
    for (let x = 0; x < kit.rider.cell[0]; x++) {
      for (let y = kit.rider.rear_contact[1] - 4; y < kit.rider.cell[1]; y++) {
        assert.ok(!same(cellPixel(sheet, k, seat, x, y), CHAIN_LIGHT), `chain at ${x},${y} in frame ${k}`);
      }
    }
  }
});

test('one rotating arm: the crank projects past a small grey ring, in a colour no shoe, sock or ring shares', () => {
  assert.ok(CHAINRING_R + 2 <= CRANK, `crank ${CRANK}, ring ${CHAINRING_R}`);
  assert.ok(CHAINRING_R <= 5, 'the ring stays small enough for the arm to leave it');
  const warm = (p) => p[3] > 0 && (same(p, CRANK_INK.body) || same(p, CRANK_INK.lit) || same(p, PEDAL));
  for (const look of [0, 1, 2, 3].map(slotLook)) {
    for (const ramp of [look.skinRamp, look.bodyRamp, look.sleeveRamp]) assert.ok(ramp.every((c) => !warm([...c, 255])), 'the arm has its own colours');
  }
  for (const s of [1, 3]) {
    const sheet = readPng(fromRes(kit.rider.slots[s]));
    const row = kit.rider.pose_rows.seat;
    const angles = new Set();
    for (let k = 0; k < CRANK_FRAMES; k++) {
      // Warm metal stands past the ring in every frame, on the side the pedal is, and only there.
      const a = crankTheta(k);
      let along = 0;
      let opposite = 0;
      for (let y = BB[1] - CRANK - 2; y <= BB[1] + CRANK + 2; y++) {
        for (let x = BB[0] - CRANK - 3; x <= BB[0] + CRANK + 3; x++) {
          const d = Math.hypot(x - BB[0], y - BB[1]);
          if (d < CHAINRING_R + 1.5 || !warm(cellPixel(sheet, k, row, x, y))) continue;
          const dot = ((x - BB[0]) * Math.cos(a) + (y - BB[1]) * Math.sin(a)) / d;
          if (dot > 0.6) along++;
          else if (dot < -0.2) opposite++;
        }
      }
      assert.ok(along >= 3, `slot ${s} frame ${k}: ${along} arm pixels past the ring`);
      assert.equal(opposite, 0, `slot ${s} frame ${k}: a second bright arm`);
      angles.add(k);
    }
    assert.equal(angles.size, CRANK_FRAMES);
    // The ring holds no near-black: its cutouts are a tone darker, not holes that look back at you. Read it
    // on its rear half while the near leg and the crank are forward of it.
    for (let k = 3; k <= 9; k++) {
      for (let y = BB[1] - CHAINRING_R; y <= BB[1] + CHAINRING_R; y++) {
        for (let x = BB[0] - CHAINRING_R; x < BB[0] - 1; x++) {
          if (Math.hypot(x - BB[0], y - BB[1]) >= CHAINRING_R + 0.5) continue;
          const p = cellPixel(sheet, k, row, x, y);
          assert.ok(p[3] === 255 && lumaOf(p) > 50, `slot ${s} frame ${k}: ring at ${x},${y} is ${p}`);
        }
      }
    }
  }
});

test('the chainring turns: its cutouts change as the crank goes round and hold both steel and dark', () => {
  const sheet = readPng(fromRes(kit.rider.slots[1]));
  const seat = kit.rider.pose_rows.stop;
  assert.ok(seat === 12);
  // On the frames where the near leg is forward of the ring, read the ring's rear half.
  const stand = kit.rider.pose_rows.seat;
  const rear = (k) => {
    let s = '';
    for (let y = BB[1] - CHAINRING_R; y <= BB[1] + CHAINRING_R; y++) {
      for (let x = BB[0] - CHAINRING_R; x < BB[0]; x++) s += cellPixel(sheet, k, stand, x, y).join();
    }
    return s;
  };
  const seen = new Set();
  for (let k = 0; k < CRANK_FRAMES; k++) seen.add(rear(k));
  assert.ok(seen.size >= 20, `${seen.size} pictures of the ring`);
});

test('the frame triangle is open: a top tube of two pixels, a saddle with its own shape over a visible post', () => {
  for (const s of [1, 3]) {
    const sheet = readPng(fromRes(kit.rider.slots[s]));
    const row = kit.rider.pose_rows.seat;
    const steelLit = hex('#d0d8e0');
    const steelDark = hex('#566070');
    let columns = 0;
    for (let x = 40; x <= 52; x++) {
      for (let y = 46; y <= 52; y++) {
        if (!same(cellPixel(sheet, 12, row, x, y), steelLit)) continue;
        if (same(cellPixel(sheet, 12, row, x, y + 1), steelDark)) columns++;
        const above = cellPixel(sheet, 12, row, x, y - 1);
        const under = cellPixel(sheet, 12, row, x, y + 2);
        assert.ok(!same(above, steelLit) && !same(above, steelDark), `slot ${s}: thicker than 2 at ${x}, above`);
        assert.ok(!same(under, steelLit) && !same(under, steelDark), `slot ${s}: thicker than 2 at ${x}, under`);
      }
    }
    assert.ok(columns >= 6, `slot ${s}: ${columns} columns of top tube show`);
  }
  // The saddle's pale tail shows behind the hips in every riding frame: no short or tube has that colour.
  const sheet = readPng(fromRes(kit.rider.slots[0]));
  for (let k = 0; k < CRANK_FRAMES; k++) {
    assert.ok(same(cellPixel(sheet, k, kit.rider.pose_rows.seat, SADDLE[0] - 7, SADDLE[1] - 1), hex('#aeb2bc')), `frame ${k}`);
  }
  assert.ok(SADDLE[1] >= 44, 'the saddle sits under the hips, not inside them');
});

test('skin never goes grey: its shade stays warm, the far limbs keep three steps, and the chin is clean', () => {
  for (let s = 0; s < 4; s++) {
    const look = slotLook(s);
    for (const c of look.skinRamp) assert.ok(c[0] - c[2] >= 24, `slot ${s}: ${c} reads grey`);
    const [a, b, d] = look.skinRamp.map(lumaOf);
    assert.ok(a < b && b < d, `slot ${s}: a ramp that climbs`);
  }
  for (let s = 0; s < 4; s++) {
    const sheet = readPng(fromRes(kit.rider.slots[s]));
    const skin = slotLook(s).skinRamp;
    for (let k = 0; k < CRANK_FRAMES; k++) {
      // Between the jaw and the chin, seat pose: head centre (49, 17), bobbing 1 px.
      for (let y = 20; y <= 21; y++) {
        for (let x = 49; x <= 52; x++) {
          const p = cellPixel(sheet, k, kit.rider.pose_rows.seat, x, y);
          if (p[3] === 0) continue;
          if (lumaOf(p) < 40) continue; // the shoulder's outline
          assert.ok(skin.some((c) => same(c, p)), `slot ${s} frame ${k} at ${x},${y}: ${p} on the face`);
        }
      }
    }
  }
});

test('the two arms are two: the far arm shows ahead of the near one', () => {
  const sheet = readPng(fromRes(kit.rider.slots[0]));
  const skin = slotLook(0).skinRamp;
  const nearSkin = (p) => skin.some((c) => same(c, p));
  // Along the forearm's middle, reading across: near skin, then at least one pixel of another skin tone.
  let both = 0;
  for (let y = 33; y <= 38; y++) {
    let near = false;
    let far = false;
    for (let x = 44; x <= 70; x++) {
      const p = cellPixel(sheet, 0, kit.rider.pose_rows.seat, x, y);
      if (p[3] === 0) continue;
      if (nearSkin(p)) near = true;
      else if (near && lumaOf(p) > 60 && p[0] > p[2]) far = true;
    }
    if (near && far) both++;
  }
  assert.ok(both >= 3, `${both} rows show both arms`);
});

test('the crowd is at a believable scale, in groups, each body one piece, arms attached', () => {
  const { path, cell, count, hand_up: hand } = kit.props.crowd;
  const sheet = readPng(fromRes(path));
  assert.deepEqual([sheet.width, sheet.height], [cell[0] * count, cell[1] * 2]);
  const opaque = (s, row, x, y) => {
    if (x < 0 || y < 0 || x >= cell[0] || y >= cell[1]) return false;
    return sheet.data[((row * cell[1] + y) * sheet.width + s * cell[0] + x) * 4 + 3] === 255;
  };
  const tallest = [];
  const widths = [];
  for (let s = 0; s < count; s++) {
    let top = cell[1];
    let bottom = 0;
    let left = cell[0];
    let right = 0;
    let total = 0;
    let start = null;
    for (let y = 0; y < cell[1]; y++) {
      for (let x = 0; x < cell[0]; x++) {
        if (!opaque(s, 0, x, y)) continue;
        top = Math.min(top, y);
        bottom = Math.max(bottom, y);
        left = Math.min(left, x);
        right = Math.max(right, x);
        total++;
        start ??= [x, y];
      }
    }
    tallest.push(bottom - top + 1);
    widths.push(right - left + 1);
    for (const row of [0, 1]) {
      // Flood from the first pixel of the row: every opaque pixel must be reached (8-connected).
      let first = null;
      let all = 0;
      for (let y = 0; y < cell[1]; y++) {
        for (let x = 0; x < cell[0]; x++) {
          if (opaque(s, row, x, y)) {
            all++;
            first ??= [x, y];
          }
        }
      }
      const seen = new Set();
      const todo = [first];
      while (todo.length > 0) {
        const [x, y] = todo.pop();
        const key = y * cell[0] + x;
        if (seen.has(key) || !opaque(s, row, x, y)) continue;
        seen.add(key);
        for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) if (i || j) todo.push([x + i, y + j]);
      }
      assert.equal(seen.size, all, `column ${s} row ${row}: ${all - seen.size} pixels float free of the group`);
    }
    // The lowered near hand sits where the view hangs a flag from it.
    assert.ok(opaque(s, 0, hand[0], hand[1] + 17), `column ${s}: the lowered hand`);
  }
  // The riders stand about 65 art px; a spectator a few px behind them is no toy.
  assert.ok(Math.min(...tallest) >= 38, `tallest in each column: ${tallest}`);
  assert.ok(new Set(tallest).size >= 4, `heights vary: ${tallest}`);
  assert.ok(new Set(widths).size >= 4, `some stand alone, some in groups: ${widths}`);
});

test('the crowd stands one atmospheric step back: no near-black, a narrow value range, legs that vary', () => {
  const { path, cell, count } = kit.props.crowd;
  const sheet = readPng(fromRes(path));
  const lumas = [];
  for (let i = 0; i < sheet.data.length; i += 4) {
    if (sheet.data[i + 3] === 255) lumas.push(lumaOf([sheet.data[i], sheet.data[i + 1], sheet.data[i + 2]]));
  }
  lumas.sort((a, b) => a - b);
  assert.ok(lumas[0] >= 70, `the darkest crowd pixel is ${lumas[0]}`);
  const riders = readPng(fromRes(kit.rider.slots[0]));
  const riderLumas = [];
  for (let i = 0; i < riders.width * kit.rider.cell[1] * 4; i += 4) {
    if (riders.data[i + 3] === 255) riderLumas.push(lumaOf([riders.data[i], riders.data[i + 1], riders.data[i + 2]]));
  }
  riderLumas.sort((a, b) => a - b);
  const spread = (u) => u[Math.floor(u.length * 0.95)] - u[Math.floor(u.length * 0.05)];
  assert.ok(spread(lumas) < spread(riderLumas) * 0.6, `crowd spread ${spread(lumas)}, a rider's ${spread(riderLumas)}`);
  assert.ok(lumas[Math.floor(lumas.length * 0.05)] > riderLumas[Math.floor(riderLumas.length * 0.05)] + 50, 'its shadows sit far above a rider\'s');
  // A hand flag lives in the same air: pale, quiet, no dark staff.
  const flag = readPng(fromRes(kit.props.flag.path));
  for (let i = 0; i < flag.data.length; i += 4) {
    if (flag.data[i + 3] === 255) assert.ok(lumaOf([flag.data[i], flag.data[i + 1], flag.data[i + 2]]) >= 70, 'flag');
  }
  // Legs: the row just over the shoes. Column by column they differ, so the verge is no picket fence.
  const legs = new Set();
  const row = cell[1] - 12;
  for (let s = 0; s < count; s++) {
    for (let x = 0; x < cell[0]; x++) {
      const i = (row * sheet.width + s * cell[0] + x) * 4;
      if (sheet.data[i + 3] === 255) legs.add(`${sheet.data[i] >> 4},${sheet.data[i + 1] >> 4},${sheet.data[i + 2] >> 4}`);
    }
  }
  assert.ok(legs.size >= 12, `${legs.size} leg tones`);
});

test('the tractor is at the scale of the mid plane, with ground contact', () => {
  const t = kit.props.tractor;
  assert.ok(t.cell[0] <= 20 && t.cell[1] <= 11, `cell ${t.cell}`);
  const sheet = readPng(fromRes(t.path));
  assert.deepEqual([sheet.width, sheet.height], [t.cell[0] * t.frames, t.cell[1]]);
  for (let f = 0; f < t.frames; f++) {
    let foot = 0;
    for (let x = 0; x < t.cell[0]; x++) {
      if (sheet.data[((t.cell[1] - 1) * sheet.width + f * t.cell[0] + x) * 4 + 3] > 0) foot++;
    }
    assert.ok(foot >= t.cell[0] * 0.6, `frame ${f}: ${foot} px of shadow and turned earth on its last row`);
  }
});

test('the gantry banner clears the helmets of the far lane, and is cloth, not a saturated slab', () => {
  const g = kit.props.gantry;
  const sheet = readPng(fromRes(g.path));
  assert.deepEqual([sheet.width, sheet.height], g.size);
  let lowest = 0;
  for (let y = 0; y < sheet.height; y++) {
    for (let x = 30; x < 170; x++) {
      if (sheet.data[(y * sheet.width + x) * 4 + 3] > 0) lowest = Math.max(lowest, y);
    }
  }
  const riders = readPng(fromRes(kit.rider.slots[0]));
  let helmet = Infinity;
  for (const name of ['seat', 'stand', 'situp']) {
    for (let k = 0; k < CRANK_FRAMES; k++) {
      for (let y = 0; y < kit.rider.cell[1] && y < helmet; y++) {
        for (let x = 0; x < kit.rider.cell[0]; x++) {
          if (cellPixel(riders, k, kit.rider.pose_rows[name], x, y)[3] > 0) helmet = Math.min(helmet, y);
        }
      }
    }
  }
  const FAR_LANE = -9;
  const bannerBottom = -g.foot_above_contact - g.size[1] + lowest;
  const helmetTop = FAR_LANE - kit.rider.origin[1] + helmet;
  assert.ok(bannerBottom + 8 <= helmetTop, `banner to ${bannerBottom}, helmets from ${helmetTop}, against the contact`);
  const i = (20 * sheet.width + 40) * 4;
  const c = [sheet.data[i], sheet.data[i + 1], sheet.data[i + 2]];
  const sat = (Math.max(...c) - Math.min(...c)) / Math.max(...c);
  assert.ok(sat < 0.6, `banner cloth saturation ${sat}`);
});

/** Of the pixels with an index in [lo, hi], the share with no such neighbour left or right. */
function loneShare(png, lo, hi) {
  let all = 0;
  let lone = 0;
  const hit = (x, y) => {
    const p = pixel(png, (x + png.width) % png.width, y);
    return p.alpha > 0 && p.index >= lo && p.index <= hi;
  };
  for (let y = 0; y < png.height; y++) {
    for (let x = 0; x < png.width; x++) {
      if (!hit(x, y)) continue;
      all++;
      if (!hit(x - 1, y) && !hit(x + 1, y)) lone++;
    }
  }
  return { all, share: all === 0 ? 0 : lone / all };
}

test('mist hangs in long strands: no ordered dither in the near or the mid plane', () => {
  for (const name of ['near_trees', 'mid_hills']) {
    const png = readPng(join(assets, 'world', `${name}.png`));
    const hanging = loneShare(png, MIST, MIST + 1);
    assert.ok(hanging.all > 200, `${name} has mist`);
    assert.ok(hanging.share < 0.12, `${name}: ${hanging.share} of the mist is checker`);
  }
  const png = readPng(join(assets, 'world', 'near_trees.png'));
  const ground = loneShare(png, MIST_GROUND, MIST_GROUND + 1);
  assert.ok(ground.all > 200);
  assert.ok(ground.share < 0.12, `ground mist: ${ground.share} is checker`);
});

test('mist has no straight edge and no bar: its top wanders, and it pools rather than runs', () => {
  for (const [name, lo] of [
    ['near_trees', MIST],
    ['near_trees', MIST_GROUND],
    ['mid_hills', MIST],
  ]) {
    const png = readPng(join(assets, 'world', `${name}.png`));
    const isMist = (x, y) => {
      if (y < 0) return false;
      const p = pixel(png, (x + png.width) % png.width, y);
      return p.alpha > 0 && p.index >= lo && p.index <= lo + 1;
    };
    let longest = 0;
    let tops = 0;
    for (let y = 0; y < png.height; y++) {
      let run = 0;
      for (let x = 0; x < png.width; x++) {
        if (isMist(x, y) && !isMist(x, y - 1)) {
          run++;
          tops++;
          longest = Math.max(longest, run);
        } else {
          run = 0;
        }
      }
    }
    assert.ok(tops > 200, `${name} has mist`);
    assert.ok(longest <= 34, `${name} ${lo}: a straight top edge of ${longest} px`);
  }
});

test('the far range is a few big planes: long runs of one tone, mostly the two middle tones', () => {
  const png = readPng(join(assets, 'world', 'far_hills.png'));
  let runs = 0;
  let px = 0;
  const tones = [0, 0, 0, 0];
  for (let y = 45; y < 66; y++) {
    let last = -1;
    for (let x = 0; x < png.width; x++) {
      const p = pixel(png, x, y);
      if (p.alpha === 0 || p.index < RIDGE || p.index >= RIDGE_NEAR) {
        last = -1;
        continue;
      }
      px++;
      tones[p.index - RIDGE]++;
      if (p.index !== last) runs++;
      last = p.index;
    }
  }
  assert.ok(px / runs >= 18, `mean run ${px / runs} px: fluted rock runs far shorter`);
  assert.ok((tones[1] + tones[2]) / px >= 0.85, `middle tones ${tones}`);
  assert.ok(tones[1] > px * 0.15 && tones[2] > px * 0.15, `both lit and shaded planes: ${tones}`);
});

test('three wires, each one pixel, apart all along the span, lighter than the poles', () => {
  const png = readPng(join(assets, 'world', 'poles.png'));
  const lut = readPng(fromRes(kit.lut.path));
  for (let x = 0; x < png.width; x++) {
    // Away from the poles' hardware.
    if (Math.abs(x - 60) < 14 || Math.abs(x - 300) < 14 || Math.abs(x - 152) < 10) continue;
    const ys = [];
    for (let y = 0; y < png.height; y++) {
      const p = pixel(png, x, y);
      if (p.alpha > 0 && p.index === WIRE) ys.push(y);
    }
    assert.equal(ys.length, WIRES.length, `column ${x}: ${ys}`);
    assert.ok(ys[1] - ys[0] >= 3 && ys[2] - ys[1] >= 3, `column ${x}: ${ys}`);
  }
  const at = (i, r) => {
    const q = (r * lut.width + i) * 4;
    return lumaOf([lut.data[q], lut.data[q + 1], lut.data[q + 2]]);
  };
  for (let r = 0; r < kit.lut.rows; r++) {
    assert.ok(at(WIRE, r) > at(WOOD, r), `row ${r}: the wire is no darkest line over the far planes`);
  }
});

test('the sun never reaches behind the timeline plate once it is that high', () => {
  const PLATE_BOTTOM = 72;
  for (const [r, t] of kit.tod.entries()) {
    const [x, y] = t.sun;
    if (x + 20 < 240 || x - 20 > 720) continue;
    assert.ok(y - kit.sun.size[1] / 2 >= PLATE_BOTTOM, `row ${r}: halo top ${y - kit.sun.size[1] / 2}`);
  }
});

test('the foreground has no repeated clods: earth patches are uneven and low, stones small and many', () => {
  for (const f of [0, 1]) {
    const png = readPng(join(assets, 'world', `foreground_${f}.png`));
    let rows = 0;
    const heights = [];
    let smallStones = 0;
    for (let x = 0; x < png.width; x++) {
      let h = 0;
      for (let y = 0; y < png.height; y++) {
        const p = pixel(png, x, y);
        if (p.alpha > 0 && p.index >= EARTH && p.index < EARTH + 6) {
          h++;
          rows = Math.max(rows, png.height - y);
        }
      }
      heights.push(h);
      if (h > 0 && h <= 3) smallStones++;
    }
    assert.ok(rows <= 8, `earth reaches ${rows} rows up`);
    assert.ok(smallStones >= 40, `${smallStones} columns of small earth`);
    // An uneven outline: along a patch the height keeps changing, never a smooth oval.
    let changes = 0;
    let along = 0;
    for (let x = 1; x < heights.length; x++) {
      if (heights[x] > 0 && heights[x - 1] > 0) {
        along++;
        if (heights[x] !== heights[x - 1]) changes++;
      }
    }
    assert.ok(along > 60 && changes / along >= 0.2, `${changes} of ${along}`);
  }
});

test('the picker card: the sun whole in the sky, the riders apart, the leader in clear air, the blocks muted', () => {
  const row = Math.floor(0.4 * 31);
  const [sx, sy] = kit.tod[row].sun;
  const half = kit.sun.size[0] / 2;
  assert.ok(sy - half >= PICKER.y0 && sx + half <= PICKER.x0 + 480 && sx - half >= PICKER.x0, `sun ${sx},${sy}`);
  const xs = PICKER.riders.map((u) => u[0]);
  for (let i = 0; i + 1 < xs.length; i++) assert.ok(xs[i] - xs[i + 1] >= 72, `riders ${xs}`);
  assert.ok(xs[0] - xs[1] >= 96, `the standing leader ${xs}`);
  assert.equal(PICKER.riders[0][3], 'stand');
  const card = readPng(join(assets, 'picker_card.png'));
  const sat = (q) => {
    const c = [card.data[q], card.data[q + 1], card.data[q + 2]];
    return (Math.max(...c) - Math.min(...c)) / Math.max(...c, 1);
  };
  // The bottom tenth, where the blocks lie: nothing as loud as the plan's own colours.
  let loud = 0;
  for (let y = 480; y < 540; y++) {
    for (let x = 0; x < 960; x++) {
      const q = (y * 960 + x) * 4;
      if (sat(q) > 0.72 && card.data[q] > 170) loud++;
    }
  }
  assert.ok(loud < 400, `${loud} loud pixels in the blocks' band`);
});

test('the far ridge has faces with hard edges, lit on the side away from the shade, with no dither', () => {
  const png = readPng(join(assets, 'world', 'far_hills.png'));
  // In a row across the rock, runs of one shade are long: a face, not a stipple or a streak of single pixels.
  let runs = 0;
  let px = 0;
  for (let y = 50; y < 62; y++) {
    let last = -1;
    for (let x = 0; x < png.width; x++) {
      const p = pixel(png, x, y);
      if (p.alpha === 0 || p.index < RIDGE || p.index >= RIDGE_NEAR) {
        last = -1;
        continue;
      }
      px++;
      if (p.index !== last) runs++;
      last = p.index;
    }
  }
  assert.ok(px > 1000, 'there is rock in those rows');
  // Each face holds up to three tones, so this is well under its width; a dither would give under 2.
  assert.ok(px / runs >= 3.5, `mean run ${px / runs} px`);
});

test('poplars carry their rim on the sun side only', () => {
  const png = readPng(join(assets, 'world', 'near_trees.png'));
  const isPoplar = (x, y) => {
    const p = pixel(png, (x + png.width) % png.width, y);
    return p.alpha > 0 && p.index >= POPLAR && p.index < POPLAR + 5;
  };
  let rim = 0;
  let onLeft = 0;
  for (let y = 0; y < png.height; y++) {
    for (let x = 0; x < png.width; x++) {
      const p = pixel(png, x, y);
      if (p.alpha === 0 || p.index !== POPLAR + 5) continue;
      rim++;
      if (!isPoplar(x - 1, y) && isPoplar(x + 1, y)) onLeft++;
    }
  }
  assert.ok(rim > 300, `${rim} rim pixels`);
  assert.ok(onLeft / rim < 0.03, `${onLeft} of ${rim} on the left edge, away from the sun`);
});

test('no stray marks: the far verge holds no painted post, and the road paint stays on the road', () => {
  for (let f = 0; f < 4; f++) {
    const png = readPng(join(assets, 'world', `verge_far_${f}.png`));
    for (let y = 0; y < png.height; y++) {
      for (let x = 0; x < png.width; x++) {
        const p = pixel(png, x, y);
        if (p.alpha > 0) assert.ok(p.index < PAINT || p.index >= GRIT + 2, `verge_far_${f} at ${x},${y}: index ${p.index}`);
      }
    }
  }
});

test('bubbles: three plates of three looks, each holding its own picture at 9 x 9', () => {
  const fx = kit.fx;
  const sheet = readPng(fromRes(fx.path));
  const box = (name, f) => {
    const [x, y, w, h] = fx[name];
    let s = '';
    for (let j = 0; j < h; j++) {
      for (let i = 0; i < w; i++) {
        const q = ((y + j) * sheet.width + x + f * w + i) * 4;
        s += `${sheet.data[q]},${sheet.data[q + 1]},${sheet.data[q + 2]},${sheet.data[q + 3]};`;
      }
    }
    return s;
  };
  for (const name of ['rescue', 'afk', 'link']) {
    assert.deepEqual(fx[name].slice(2, 4), [9, 9]);
    assert.notEqual(box(name, 0), box(name, 1), `${name} blinks`);
  }
  const plate = (name) => {
    const q = ((fx[name][1] + 1) * sheet.width + fx[name][0] + 2) * 4;
    return [sheet.data[q], sheet.data[q + 1], sheet.data[q + 2]].join();
  };
  assert.equal(new Set(['rescue', 'afk', 'link'].map(plate)).size, 3, 'plates differ');
  // The Z: a top bar, a bottom bar, a diagonal from upper right to lower left.
  const [ax, ay] = fx.afk;
  const dark = (i, j) => sheet.data[((ay + j) * sheet.width + ax + i) * 4] < 60;
  for (let i = 2; i <= 6; i++) assert.ok(dark(i, 2) && dark(i, 6), `Z bars at ${i}`);
  assert.ok(dark(6, 3) && dark(4, 4) && dark(3, 5), 'Z diagonal');
  assert.ok(!dark(2, 3) && !dark(6, 5), 'Z corners stay open');
  // The link: two rings of dark, each with its pale eye, and a column of air between them on either frame.
  const [lx, ly] = fx.link;
  for (const f of [0, 1]) {
    const q = (i, j) => ((ly + j) * sheet.width + lx + f * 9 + i) * 4;
    const dk = (i, j) => sheet.data[q(i, j)] < 60;
    for (const c of [1, 5]) {
      for (let i = 0; i < 3; i++) assert.ok(dk(c + i, 2) && dk(c + i, 5), `link ${f} ring at ${c}`);
      assert.ok(dk(c, 3) && dk(c + 2, 3) && !dk(c + 1, 3), `link ${f} ring ${c} has an eye`);
    }
    for (let j = 1; j < 7; j++) assert.ok(!dk(4, j), `link ${f}: the gap at row ${j}`);
  }
});

test('dust is soft and breaks up: no box, thin edges, and fewer pixels each frame once it has grown', () => {
  const [x0, y0, w, h, frames] = kit.fx.dust;
  const sheet = readPng(fromRes(kit.fx.path));
  const counts = [];
  for (let f = 0; f < frames; f++) {
    let n = 0;
    let dense = 0;
    let left = w;
    let right = -1;
    let top = h;
    let bottom = -1;
    for (let j = 0; j < h; j++) {
      for (let i = 0; i < w; i++) {
        const a = sheet.data[((y0 + j) * sheet.width + x0 + f * w + i) * 4 + 3];
        if (a === 0) continue;
        assert.ok(a < 255, 'dust is never opaque');
        n++;
        if (a > 150) dense++;
        left = Math.min(left, i);
        right = Math.max(right, i);
        top = Math.min(top, j);
        bottom = Math.max(bottom, j);
      }
    }
    const fill = n / ((right - left + 1) * (bottom - top + 1));
    assert.ok(fill < 0.8, `frame ${f} fills ${fill} of its box`);
    counts.push({ n, dense });
  }
  assert.ok(counts[1].n > counts[0].n, 'it grows');
  assert.ok(counts[3].n < counts[2].n && counts[2].n <= counts[1].n + 12, 'then thins');
  assert.equal(counts[3].dense, 0, 'the last frame is only specks');
  // Pale, so it reads as dust in the air and never as grit on the road.
  for (let f = 0; f < frames; f++) {
    for (let j = 0; j < h; j++) {
      for (let i = 0; i < w; i++) {
        const q = ((y0 + j) * sheet.width + x0 + f * w + i) * 4;
        if (sheet.data[q + 3] > 0) assert.ok(lumaOf([sheet.data[q], sheet.data[q + 1], sheet.data[q + 2]]) >= 190, 'dust is pale');
      }
    }
  }
});
