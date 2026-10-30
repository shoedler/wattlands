// The committed v2 bake (assets/siege/bake/) and map (content/siege/maps/rotae.json) match their
// generators: bake.mjs --check (generator version, files) and export_map.mjs --check.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '../../../..');
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
