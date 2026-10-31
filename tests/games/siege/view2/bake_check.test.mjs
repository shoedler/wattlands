// The committed v2 bake (assets/siege/bake/) and map (content/siege/maps/rotae.json) match their
// generators: bake.mjs --check (generator version, files) and export_map.mjs --check. The world
// image: the approved design frame byte for byte, ground on every pixel, the manifest's numbers.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { decodePng } from '../../../../tools/art/lib/png.mjs';

const repo = join(dirname(fileURLToPath(import.meta.url)), '../../../..');
const bakeDir = join(repo, 'assets/siege/bake');
// RGBA sha256 of the 960 x 540 frame as approved (bake version 2's whole images).
const FRAME_SHA = {
  'world.png': 'e766d5634b67edeeb2cb6867d09671450dd6e8dbb9021e7b9602b8785c94822a',
  'world_depth.png': 'e52d6ed831790386607e29f60a3a95b0c732136ae6428bc57d1b5a29f9b9ba21',
};
const manifest = () => JSON.parse(readFileSync(join(bakeDir, 'manifest.json'), 'utf8'));
const image = (name) => decodePng(readFileSync(join(bakeDir, name)));
const run = (script) => {
  const env = { ...process.env };
  delete env.FAL_KEY;
  delete env.WATTLANDS_ALLOW_ART;
  return spawnSync(process.execPath, [join(repo, 'src/games/siege/art', script), '--check'], { cwd: repo, env, encoding: 'utf8', timeout: 120000 });
};

test('bake.mjs --check passes on the committed bake', () => {
  const r = run('bake.mjs');
  assert.equal(r.status, 0, r.stderr || r.stdout);
  assert.match(r.stdout, /bake ok/);
});

test('export_map.mjs --check passes on the committed map', () => {
  const r = run('export_map.mjs');
  assert.equal(r.status, 0, r.stderr || r.stdout);
  assert.match(r.stdout, /map ok/);
});

test('the manifest names the world image: the design frame and its margin', () => {
  const m = manifest();
  assert.deepEqual(m.art_size, [960, 540]);
  assert.deepEqual(m.world.size, [1920, 1084]);
  assert.deepEqual(m.world.origin, [480, 272]);
  assert.equal(m.world.size[0], m.art_size[0] + 2 * m.world.origin[0], 'centred across');
  assert.equal(m.world.size[1], m.art_size[1] + 2 * m.world.origin[1], 'centred down');
  for (const name of ['world.png', 'world_depth.png']) {
    const png = image(name);
    assert.deepEqual([png.width, png.height], m.world.size, name);
  }
});

test('the design frame in the world image is the approved one, byte for byte', () => {
  const [fx, fy] = manifest().world.origin;
  for (const [name, sha] of Object.entries(FRAME_SHA)) {
    const png = image(name);
    const hash = createHash('sha256');
    for (let y = 0; y < 540; y++) {
      const at = ((y + fy) * png.width + fx) * 4;
      hash.update(png.data.subarray(at, at + 960 * 4));
    }
    assert.equal(hash.digest('hex'), sha, name);
  }
});

test('the bake covers its whole image with ground: no sky to show through', () => {
  const png = image('world_depth.png');
  let sky = 0;
  for (let i = 0; i < png.width * png.height; i++) {
    if (png.data[i * 4] === 0 && png.data[i * 4 + 1] === 0) sky++;
  }
  assert.equal(sky, 0, 'pixels with no depth');
});
