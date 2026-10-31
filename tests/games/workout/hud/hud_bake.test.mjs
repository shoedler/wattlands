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
const { ARM, chars, FAR_ARM, ICON, PEDAL, renderAll, RING, tallRows } = await import(
  `file://${script.replace(/\\/g, '/')}`
);
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

const WHITE = '255,255,255,255';
const isPedalInk = (v) => v[3] === 255 && v[0] === 255 && v[2] < 128;
const luma = (v) => (v[0] + v[1] + v[2]) / 3;
const inkAt = (crank, k, x, y) => crank.get(k * ICON + x, y);

// Where frame k's pedal really is, read back from its pixels: the pixels and their centre.
function pedalPixels(crank, k) {
  const px = [];
  for (let y = 0; y < ICON; y++) {
    for (let x = 0; x < ICON; x++) if (isPedalInk(inkAt(crank, k, x, y))) px.push([x, y]);
  }
  const mean = (i) => px.reduce((s, p) => s + p[i], 0) / px.length;
  return { px, x: mean(0), y: mean(1) };
}

test('the crank icon fills the plate column: 27 x 27, every frame inside its cell', () => {
  assert.equal(ICON, 27);
  const c = (ICON - 1) / 2;
  assert.ok(c + ARM + PEDAL[0] <= ICON - 1, 'a level crank keeps its whole pedal in the cell');
  assert.ok(c + ARM + PEDAL[1] <= ICON - 1, 'an upright crank too');
  assert.ok(c - ARM - PEDAL[1] >= 0);
});

test('every frame has a whole level pedal at the crank angle, so all 24 angles read', () => {
  const crank = renderAll().get('hud_crank.png');
  const c = (ICON - 1) / 2;
  const area = (2 * PEDAL[0] + 1) * (2 * PEDAL[1] + 1);
  const step = 360 / CRANK_FRAMES;
  for (let k = 0; k < CRANK_FRAMES; k++) {
    const { px, x, y } = pedalPixels(crank, k);
    assert.equal(px.length, area, `frame ${k}: the pedal is a whole, unclipped block`);
    const a = crankTheta(k);
    assert.equal(x, Math.round(c + ARM * Math.cos(a)), `frame ${k}: pedal x`);
    assert.equal(y, Math.round(c + ARM * Math.sin(a)), `frame ${k}: pedal y`);
    const shown = (Math.atan2(y - c, x - c) * 180) / Math.PI;
    const off = Math.abs(((shown - (a * 180) / Math.PI + 540) % 360) - 180);
    assert.ok(off < step / 2, `frame ${k}: the pedal shows its own angle, off by ${off} degrees`);
  }
});

test('the near arm is a thick full-ink bar from the axle to the pedal, in every frame', () => {
  const crank = renderAll().get('hud_crank.png');
  const c = (ICON - 1) / 2;
  for (let k = 0; k < CRANK_FRAMES; k++) {
    const a = crankTheta(k);
    for (let r = 2; r <= ARM - PEDAL[1] - 1; r++) {
      const x = Math.round(c + r * Math.cos(a));
      const y = Math.round(c + r * Math.sin(a));
      // the pedal's corner lies over the arm's last pixels on a diagonal, so the bar runs into it unbroken
      const v = inkAt(crank, k, x, y);
      assert.ok(String(v) === WHITE || isPedalInk(v), `frame ${k}: arm at radius ${r}`);
    }
    const mx = c + 5 * Math.cos(a);
    const my = c + 5 * Math.sin(a);
    // one pixel either side of the arm's line, across it
    for (const side of [-1, 1]) {
      const x = Math.round(mx - side * Math.sin(a));
      const y = Math.round(my + side * Math.cos(a));
      assert.equal(String(inkAt(crank, k, x, y)), WHITE, `frame ${k}: the arm is 3 px thick`);
    }
    assert.equal(inkAt(crank, k, c, c)[3], 0, `frame ${k}: the axle is a hole in the arm`);
  }
});

test('the near crank stands off the ring and is never mirrored by the far crank', () => {
  const crank = renderAll().get('hud_crank.png');
  const c = (ICON - 1) / 2;
  for (let k = 0; k < CRANK_FRAMES; k++) {
    let near = 0;
    let far = 0;
    let lit = 0;
    const a = crankTheta(k);
    for (let y = 0; y < ICON; y++) {
      for (let x = 0; x < ICON; x++) {
        const v = inkAt(crank, k, x, y);
        if (v[3] === 0) continue;
        const along = (x - c) * Math.cos(a) + (y - c) * Math.sin(a);
        if (luma(v) >= 200 || isPedalInk(v)) lit += 1;
        if (along > 7) near += luma(v);
        if (along < -7) far += luma(v);
      }
    }
    assert.ok(near > 5 * far, `frame ${k}: the pedal end outweighs the far end (${near} vs ${far})`);
    assert.ok(lit >= 45, `frame ${k}: ${lit} full-ink pixels`);
    const fx = Math.round(c - FAR_ARM * Math.cos(a));
    const fy = Math.round(c - FAR_ARM * Math.sin(a));
    const tipInk = inkAt(crank, k, fx, fy);
    assert.equal(tipInk[3], 255, `frame ${k}: the far crank is there`);
    assert.ok(luma(tipInk) < 128, `frame ${k}: and it is faint`);
    // the ring never touches the near crank: a clear pixel between them across the arm, at the ring
    const rx = c + RING * Math.cos(a);
    const ry = c + RING * Math.sin(a);
    for (const side of [-1, 1]) {
      const x = Math.round(rx - side * 3 * Math.sin(a));
      const y = Math.round(ry + side * 3 * Math.cos(a));
      assert.notEqual(String(inkAt(crank, k, x, y)), WHITE, `frame ${k}: the halo beside the arm`);
    }
  }
});

test('frame 0 has the near pedal on top, as the rider sheet does, and neighbours differ', () => {
  const crank = renderAll().get('hud_crank.png');
  const c = (ICON - 1) / 2;
  assert.equal(pedalPixels(crank, 0).x, c);
  assert.equal(pedalPixels(crank, 0).y, c - ARM);
  assert.equal(pedalPixels(crank, CRANK_FRAMES / 4).x, c + ARM, 'a quarter turn later it is forward');
  assert.equal(pedalPixels(crank, CRANK_FRAMES / 2).y, c + ARM, 'half a turn later it is at the bottom');
  for (let k = 0; k < CRANK_FRAMES; k++) {
    const a = pedalPixels(crank, k);
    const b = pedalPixels(crank, (k + 1) % CRANK_FRAMES);
    assert.ok(Math.hypot(a.x - b.x, a.y - b.y) >= 2, `frames ${k} and ${k + 1}: the pedal visibly moves`);
  }
});
