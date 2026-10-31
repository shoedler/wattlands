// hud_bake.mjs's contract: the committed HUD art is what the bake makes, the type's bowls are closed,
// and the crank icon turns with rig.mjs's angle. Paths resolve from import.meta.url (the node step's cwd
// is tests/games/workout).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { TEXT } from '../../../../src/games/workout/art/hud_font.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, '../../../../src/games/workout/art/hud_bake.mjs');
const { chars, ICON, renderAll, tallRows } = await import(`file://${script.replace(/\\/g, '/')}`);
const { crankTheta, CRANK_FRAMES } = await import(
  `file://${join(here, '../../../../src/games/workout/art/rig.mjs').replace(/\\/g, '/')}`
);

test('hud_bake --check passes on the committed files', () => {
  const r = spawnSync(process.execPath, [script, '--check'], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
});

test('every grid cell has a glyph, in the importer order', () => {
  const all = chars();
  assert.equal(all.length, 99);
  for (const ch of all) assert.ok(TEXT[ch] !== undefined, `no glyph for ${ch}`);
  assert.ok(all.length <= 16 * 7);
});

test('the bowls of B D O P Q R are closed and the zero is plain', () => {
  for (const ch of 'BDOPQR') {
    const top = TEXT[ch].split('/')[0];
    assert.ok(!top.includes('#.#'), `${ch} still has a stencil break: ${top}`);
  }
  assert.equal(TEXT['0'], '.###./#...#/#...#/#...#/#...#/#...#/.###.');
});

test('the tall face has 9 cap rows and 2 descender rows', () => {
  for (const ch of ['A', 'g', '0', '%']) assert.equal(tallRows(ch).length, 11, ch);
});

test('sizes match the importer settings and the digit strip', () => {
  const files = renderAll();
  assert.deepEqual([files.get('wo_text_5x7.png').w, files.get('wo_text_5x7.png').h], [96, 63]);
  assert.deepEqual([files.get('wo_tall_5x9.png').w, files.get('wo_tall_5x9.png').h], [96, 77]);
  assert.deepEqual([files.get('wo_digits_14x24.png').w, files.get('wo_digits_14x24.png').h], [182, 24]);
  assert.deepEqual([files.get('hud_crank.png').w, files.get('hud_crank.png').h], [ICON * CRANK_FRAMES, ICON]);
});

test('the crank icon has one frame per rider frame and its near crank follows the angle', () => {
  const crank = renderAll().get('hud_crank.png');
  const c = (ICON - 1) / 2;
  for (let k = 0; k < CRANK_FRAMES; k++) {
    const a = crankTheta(k);
    const x = Math.round(c + 5 * Math.cos(a));
    const y = Math.round(c + 5 * Math.sin(a));
    assert.equal(crank.get(k * ICON + x, y)[0], 255, `frame ${k}: white ink at the crank's tip`);
  }
  // frame 0 has the near pedal on top, as the rider sheet does
  assert.equal(crank.get(c, 1)[0], 255);
  assert.equal(crank.get(c, 11)[3], 255, 'the far crank points down');
  assert.notEqual(crank.get(c, 11)[0], 255, 'and is dimmer');
});
