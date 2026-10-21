// assets/<id>/art.json validation and defaults (BRIEF 3.10, docs/OWNERSHIP.md ART3).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { composePrompt, validateArt } from '../lib/art_json.mjs';
import { DEFAULT_ENDPOINT, DRAFT_ENDPOINT } from '../lib/config.mjs';
import { childEnv, makeRoot, mockFor, removeRoot, runGenerate, smallArt } from './helpers.mjs';

function errorsOf(art) {
  return validateArt(art).errors.join('\n');
}

test('a valid art.json gets its defaults filled', () => {
  const { errors, art } = validateArt(smallArt());
  assert.deepEqual(errors, []);
  assert.equal(art.endpoint, DEFAULT_ENDPOINT);
  assert.equal(art.quality, 'high');
  assert.equal(art.dither, 'none');
  const boat = art.sprites[0];
  assert.equal(boat.background, 'transparent');
  assert.equal(boat.align, 'bottom_center');
  assert.equal(boat.anchor, 'bottom_center', 'anchor defaults to align');
  assert.equal(boat.tile, false);
  assert.equal(boat.mirror, false);
  assert.deepEqual(boat.parts, { hull: [0, 16, 80, 16], cabin: [20, 0, 40, 16] });
  assert.equal(art.sprites[1].anchor, 'center');
  assert.equal(art.sprites[2].background, 'opaque');
  assert.equal(art.sprites[3].tile, true);
  assert.equal(art.palette[0], '#0b0b0e');
});

test('the flare endpoint and other qualities are accepted', () => {
  const { errors, art } = validateArt(smallArt({ endpoint: DRAFT_ENDPOINT, quality: 'medium' }));
  assert.deepEqual(errors, []);
  assert.equal(art.endpoint, DRAFT_ENDPOINT);
  assert.equal(art.quality, 'medium');
});

test('palette: at most 32 "#rrggbb" colors, no duplicates', () => {
  const many = Array.from({ length: 33 }, (_, i) => `#${i.toString(16).padStart(6, '0')}`);
  assert.match(errorsOf(smallArt({ palette: many })), /33 colors, at most 32/);
  assert.match(errorsOf(smallArt({ palette: ['#12345'] })), /palette\[0\].*not a "#rrggbb"/);
  assert.match(errorsOf(smallArt({ palette: ['red'] })), /not a "#rrggbb"/);
  assert.match(errorsOf(smallArt({ palette: ['#aabbcc', '#AABBCC'] })), /listed twice/);
  assert.match(errorsOf(smallArt({ palette: [] })), /palette: expected a non-empty array/);
  assert.deepEqual(validateArt(smallArt({ palette: many.slice(0, 32) })).errors, []);
});

test('style, endpoint, quality and dither are checked', () => {
  assert.match(errorsOf(smallArt({ style: '' })), /style: expected a non-empty string/);
  assert.match(errorsOf(smallArt({ endpoint: 'fal-ai/unknown' })), /not in tools\/art\/endpoints.json/);
  assert.match(errorsOf(smallArt({ quality: 'ultra' })), /quality: "ultra" is not one of/);
  assert.match(errorsOf(smallArt({ dither: 'floyd' })), /dither: "floyd"/);
  assert.match(errorsOf(smallArt({ colours: [] })), /unknown key "colours"/);
  assert.deepEqual(validateArt(smallArt({ _comment: 'ignored', notes: 'ok' })).errors, []);
});

test('sprite fields: id, prompt, size, background, align, anchor, tile, mirror', () => {
  const bad = (sprite) => errorsOf(smallArt({ sprites: [{ id: 'a', prompt: 'p', size: [8, 8], ...sprite }] }));
  assert.match(bad({ id: 'Bad Id' }), /\.id: expected lower-case/);
  assert.match(bad({ id: 'a__b' }), /\.id: expected lower-case/);
  assert.match(bad({ prompt: ' ' }), /prompt: expected a non-empty string/);
  assert.match(bad({ size: [8] }), /size: expected \[width, height\]/);
  assert.match(bad({ size: [8, 0] }), /size: expected/);
  assert.match(bad({ size: [8.5, 8] }), /size: expected/);
  assert.match(bad({ background: 'white' }), /background: "white"/);
  assert.match(bad({ align: 'middle' }), /align: "middle" is not one of/);
  assert.match(bad({ anchor: [9, 2] }), /anchor: \[9, 2\] lies outside/);
  assert.match(bad({ anchor: 'nowhere' }), /anchor: "nowhere"/);
  assert.match(bad({ tile: 'yes' }), /tile: expected true or false/);
  assert.match(bad({ mirror: true }), /mirror: needs tile: true/);
  assert.match(bad({ backround: 'opaque' }), /unknown key "backround"/);
  assert.deepEqual(validateArt(smallArt({ sprites: [{ id: 'a', prompt: 'p', size: [8, 8], anchor: [4, 8] }] })).errors, []);
  const dup = smallArt();
  dup.sprites.push({ ...dup.sprites[0] });
  assert.match(errorsOf(dup), /"boat" is used twice/);
});

test('parts: named [x, y, w, h] rectangles inside the sprite', () => {
  const bad = (parts) => errorsOf(smallArt({ sprites: [{ id: 'a', prompt: 'p', size: [16, 8], parts }] }));
  assert.match(bad({ body: [0, 0, 17, 8] }), /parts\.body: \[0, 0, 17, 8\] lies outside the 16x8 sprite/);
  assert.match(bad({ body: [0, 0, 0, 8] }), /at least 1/);
  assert.match(bad({ body: [0, 0, 8] }), /expected \[x, y, w, h\]/);
  assert.match(bad({ Body: [0, 0, 8, 8] }), /part names use lower-case/);
  assert.match(bad([1, 2]), /parts: expected an object/);
  assert.deepEqual(validateArt(smallArt({ sprites: [{ id: 'a', prompt: 'p', size: [16, 8], parts: { body: [0, 0, 12, 8], tail: [12, 0, 4, 8] } }] })).errors, []);
});

test('every problem is reported at once', () => {
  const { errors } = validateArt({ palette: ['x'], style: '', sprites: [{ id: 'A', size: [1] }] });
  assert.ok(errors.length >= 4, errors.join('\n'));
});

test('the prompt is the shared style prefix, then the sprite prompt', () => {
  const { art } = validateArt(smallArt());
  assert.equal(composePrompt(art, art.sprites[0]), `${smallArt().style} a small white boat, bow right`);
});

test('generate.mjs exits 2 with every art.json error listed and contacts nothing', async (t) => {
  const mock = await mockFor(t);
  const art = smallArt({ palette: ['#zzzzzz'] });
  art.sprites[0].size = [0, 4];
  const root = makeRoot('bad', art);
  t.after(() => removeRoot(root));
  const r = await runGenerate([`--game=bad`, `--root=${root}`, `--mock=${mock.url}`, '--poll-ms=5'], { env: childEnv() });
  assert.equal(r.code, 2, r.stderr);
  assert.match(r.stderr, /invalid art\.json/);
  assert.match(r.stderr, /palette\[0\]/);
  assert.match(r.stderr, /sprites\[0\] \(boat\)\.size/);
  assert.equal(mock.state.log.length, 0);
});

test('generate.mjs: missing art.json, unknown ids and bad flags exit 2', async (t) => {
  const mock = await mockFor(t);
  const root = makeRoot('g', smallArt());
  t.after(() => removeRoot(root));
  const env = childEnv();
  let r = await runGenerate([`--game=missing`, `--root=${root}`, `--mock=${mock.url}`], { env });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /cannot read it/);
  r = await runGenerate([`--game=g`, `--root=${root}`, `--mock=${mock.url}`, '--only=boat,nope'], { env });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /unknown sprite id\(s\) for g: nope/);
  r = await runGenerate([`--game=g`, `--root=${root}`, `--mock=${mock.url}`, '--frobnicate'], { env });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /unknown option --frobnicate/);
  r = await runGenerate([`--root=${root}`, `--mock=${mock.url}`], { env });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /--game=<id> is required/);
  r = await runGenerate([`--game=g`, `--root=${root}`, `--mock=${mock.url}`, '--budget=-1'], { env });
  assert.equal(r.code, 2);
  r = await runGenerate([`--game=g`, `--root=${root}`, '--mock=https://queue.fal.run'], { env });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /must point at a loopback host/);
  assert.equal(mock.state.log.length, 0);
});
