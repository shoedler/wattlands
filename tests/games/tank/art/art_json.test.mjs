// tests/games/tank/art/art_json.test.mjs: assets/tank/art.json stays valid for tools/art/generate.mjs.
// Runs the generator with --dry-run only, with FAL_KEY and WATTLANDS_ALLOW_ART removed from its
// environment, so no fal call can happen; it writes nothing (no manifest, no sprites).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..', '..', '..');
const artPath = path.join(repo, 'assets', 'tank', 'art.json');
const art = JSON.parse(fs.readFileSync(artPath, 'utf8'));

test('art.json: 61 unique sprites, a 32-colour palette, sizes and the style clause', () => {
  assert.equal(art.sprites.length, 61);
  assert.equal(new Set(art.sprites.map((s) => s.id)).size, 61);
  assert.ok(art.palette.length <= 32 && art.palette.length >= 1);
  assert.equal(new Set(art.palette.map((c) => c.toLowerCase())).size, art.palette.length);
  for (const c of art.palette) assert.match(c, /^#[0-9a-fA-F]{6}$/);
  for (const s of art.sprites) {
    assert.ok(Array.isArray(s.size) && s.size.length === 2 && s.size.every((n) => Number.isInteger(n) && n > 0), s.id);
    assert.ok(typeof s.prompt === 'string' && s.prompt.length > 20, `${s.id} has a prompt`);
  }
  for (const clause of ['No people, figures or faces', 'no text, letters, numbers, flags, insignia']) {
    assert.ok(art.style.includes(clause), `style keeps "${clause}"`);
  }
});

test('art.json: no prompt asks for people, text or insignia', () => {
  const bad = /\b(soldier|crew member|driver|person|human|faces|facial|flag|logo|swastika|emblem|insignia|lettering|text|number)\b/i;
  for (const s of art.sprites) {
    const p = String(s.prompt).replace(/\bno\s+[^;.]*?(people|figures|faces|text|letters|numbers|flags|insignia|emblems|markings|logos)[^;.]*/gi, '');
    assert.doesNotMatch(p, bad, `${s.id}: ${s.prompt}`);
  }
});

test('art.json: strips wider than 3:1 are tile + mirror segments', () => {
  for (const s of art.sprites) {
    const wide = s.size[0] / s.size[1] > 3.3 && s.id.startsWith('bg_') && s.id !== 'bg_sky';
    if (wide || s.id === 'fg_debris') assert.ok(s.tile === true && s.mirror === true, `${s.id} tiles with mirror`);
  }
});

test('generate.mjs --dry-run accepts art.json and plans within the $15 budget (no fal call)', () => {
  const env = { ...process.env };
  delete env.FAL_KEY;
  delete env.WATTLANDS_ALLOW_ART;
  const r = spawnSync(process.execPath, [path.join(repo, 'tools', 'art', 'generate.mjs'), '--game=tank', '--dry-run'], {
    cwd: repo,
    env,
    encoding: 'utf8',
    timeout: 60000,
  });
  assert.equal(r.status, 0, r.stderr + r.stdout);
  assert.match(r.stdout, /budget: the plan fits/);
  assert.equal(fs.existsSync(path.join(repo, 'assets', 'tank', 'art_manifest.json')), false, 'a dry run writes no manifest');
  assert.equal(fs.existsSync(path.join(repo, 'assets', 'tank', 'sprites')), false, 'no sprites from placeholders');
});
