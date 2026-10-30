// node --test tests/games/siege/hud: the committed HUD atlas is what the mock's own code bakes.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..', '..', '..');
const script = path.join(repo, 'src', 'games', 'siege', 'art', 'hud_bake.mjs');
const manifest = path.join(repo, 'assets', 'siege', 'hud', 'hud_atlas.json');

test('assets/siege/hud matches hud_bake.mjs', () => {
  const r = spawnSync(process.execPath, [script, '--check'], { cwd: repo, encoding: 'utf8' });
  assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
  assert.match(r.stdout, /hud atlas ok/);
});

test('the atlas has every face, the icons and the four slot shapes', () => {
  const m = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  assert.deepEqual(Object.keys(m.faces).sort(), ['BODY', 'KEY', 'KEY28', 'KEY36', 'LABEL', 'LINE', 'NUM']);
  assert.equal(m.faces.KEY36.cap, 36, '72 px at 1080p');
  for (const f of Object.values(m.faces)) {
    for (const ch of '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:%/-+?.,') assert.ok(f.glyphs[ch], `${f.cap}: ${ch}`);
  }
  for (const name of ['heart', 'denarius', 'mine', 'ballista', 'onager', 'arrows', 'tar', 'spear', 'shield', 'chariot', 'ram', 'tower', 'up', 'down', 'gear', 'peg']) {
    assert.ok(m.icons[name], name);
  }
  assert.equal(m.shapes.length, 4);
});

test('no rect of the atlas overlaps another', () => {
  const m = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  const rects = [...m.shapes];
  for (const f of Object.values(m.faces)) for (const g of Object.values(f.glyphs)) rects.push(g.slice(0, 4));
  for (const i of Object.values(m.icons)) {
    rects.push(i.tint);
    if (i.fixed) rects.push(i.fixed);
  }
  const taken = new Set();
  for (const [x, y, w, h] of rects) {
    assert.ok(x + w <= m.size[0] && y + h <= m.size[1], `${x},${y} inside`);
    for (let j = 0; j < h; j++) {
      for (let i = 0; i < w; i++) {
        const k = (y + j) * m.size[0] + x + i;
        assert.ok(!taken.has(k), `${x},${y} overlaps`);
        taken.add(k);
      }
    }
  }
});
