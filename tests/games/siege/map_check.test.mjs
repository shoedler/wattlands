// node --test tests/games/siege/map_check.test.mjs: the committed map is the art's own geometry
// (brief 4: "the map JSON is not stale (export_map.mjs --check)").
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..', '..');
const mapPath = path.join(repo, 'content', 'siege', 'maps', 'rotae.json');

test('content/siege/maps/rotae.json matches export_map.mjs', () => {
  const r = spawnSync(process.execPath, [path.join(repo, 'src', 'games', 'siege', 'art', 'export_map.mjs'), '--check'], {
    cwd: repo,
    encoding: 'utf8',
  });
  assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
  assert.match(r.stdout, /map ok/);
});

test('the map has the brief 2.4 shape', () => {
  const m = JSON.parse(fs.readFileSync(mapPath, 'utf8'));
  assert.equal(m.version, 2);
  assert.equal(m.path.points.length, 98);
  assert.equal(m.stations.length, 5);
  assert.equal(m.pads.length, 4);
  assert.equal(m.wheels.length, 4);
  assert.deepEqual(m.staging.map((s) => s.id), ['camp', 'grove', 'wadi']);
  assert.ok(Math.abs(m.bridge.from_prog_m - 375.4) < 0.1);
  assert.ok(Math.abs(m.bridge.to_prog_m - 391.4) < 0.1);
});
