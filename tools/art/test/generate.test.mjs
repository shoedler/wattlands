// generate.mjs end to end against tools/art/mock_fal: requests, manifest, cache, --only, --reroll,
// --select, endpoint switches and billed amounts (BRIEF 3.10, 7.1; docs/OWNERSHIP.md ART1-ART5).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { DEFAULT_ENDPOINT, DRAFT_ENDPOINT, endpointLimits } from '../lib/config.mjs';
import { decodePng } from '../lib/png.mjs';
import { estimateUsd } from '../lib/prices.mjs';
import { planRequestSize } from '../lib/sizing.mjs';
import {
  childEnv,
  makeRoot,
  manifestFile,
  mockArgs,
  mockFor,
  readManifest,
  removeRoot,
  runGenerate,
  smallArt,
  writeArt,
} from './helpers.mjs';

const GAME = 'demo';

async function setup(t, art = smallArt(), mockConfig = {}) {
  const mock = await mockFor(t, mockConfig);
  const root = makeRoot(GAME, art);
  t.after(() => removeRoot(root));
  return { mock, root };
}

const gen = (root, mock, extra = [], env = childEnv()) => runGenerate(mockArgs(GAME, root, mock, extra), { env });

test('one request per sprite with the full input; the manifest records each; results cached as PNGs', async (t) => {
  const { mock, root } = await setup(t);
  const r = await gen(root, mock);
  assert.equal(r.code, 0, r.stderr + r.stdout);
  assert.equal(mock.state.counts.submit, 4);

  const m = readManifest(root, GAME);
  assert.equal(m.version, 1);
  assert.equal(m.game, GAME);
  assert.equal(m.requests.length, 4);
  const limits = endpointLimits(DEFAULT_ENDPOINT);
  const art = smallArt();
  for (const [i, s] of art.sprites.entries()) {
    const e = m.requests.find((x) => x.sprite === s.id);
    assert.ok(e, s.id);
    const req = planRequestSize(s.size, limits);
    assert.equal(e.endpoint, DEFAULT_ENDPOINT);
    assert.deepEqual(e.input, {
      prompt: `${art.style} ${s.prompt}`,
      image_size: { width: req.width, height: req.height },
      background: s.background ?? 'transparent',
      quality: 'high',
      num_images: 1,
      output_format: 'png',
    });
    // What fal received is exactly the recorded input.
    const sent = mock.state.requests.get(e.request_id);
    assert.deepEqual(sent.input, e.input, `sprite ${i}`);
    assert.equal(sent.endpoint, DEFAULT_ENDPOINT);
    assert.equal(e.status, 'ok');
    assert.equal(e.source, 'generated');
    assert.equal(e.paid, true);
    assert.equal(e.estimated_usd, estimateUsd(DEFAULT_ENDPOINT, req.width, req.height, 'high'));
    assert.equal(e.billed_usd, null);
    for (const k of ['created_at', 'submitted_at', 'completed_at', 'downloaded_at']) assert.ok(Date.parse(e[k]) > 0, k);
    assert.equal(e.selected, true);
    assert.equal(e.selected_by, 'run');
    assert.equal(e.cache, `.art_cache/${GAME}/${e.request_id}.png`);
    const png = fs.readFileSync(path.join(root, e.cache));
    const d = decodePng(png);
    assert.equal(d.width, req.width);
    assert.equal(d.height, req.height);
    assert.equal(e.width, req.width);
    assert.equal(e.bytes, png.length);
    assert.match(e.sha256, /^[0-9a-f]{64}$/);
  }
  assert.deepEqual(m.spend, { total_usd: 0.28, estimated_usd: 0.28, billed_usd: 0, paid_requests: 4 });
  assert.match(r.stdout, /generate: 4 paid, 0 cached, 0 recovered, 0 failed/);
});

test('an unchanged input returns the cached result: no request, no cost', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await gen(root, mock)).code, 0);
  const before = readManifest(root, GAME);
  const listings = mock.state.counts.listing;
  const r = await gen(root, mock);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.submit, 4);
  assert.equal(mock.state.counts.listing, listings, 'cache hits never need the history');
  assert.match(r.stdout, /0 paid, 4 cached/);
  const after = readManifest(root, GAME);
  assert.equal(after.requests.length, 4);
  assert.deepEqual(after.spend, before.spend);
});

test('a changed prompt pays for that sprite only, and the new result becomes selected', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await gen(root, mock)).code, 0);
  const art = smallArt();
  art.sprites[1].prompt = 'a tuna facing left, sharper fins';
  writeArt(root, GAME, art);
  const r = await gen(root, mock);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.submit, 5);
  assert.match(r.stdout, /1 paid, 3 cached/);
  const m = readManifest(root, GAME);
  const tuna = m.requests.filter((e) => e.sprite === 'fish_tuna');
  assert.equal(tuna.length, 2);
  assert.equal(tuna.filter((e) => e.selected).length, 1);
  assert.equal(tuna.find((e) => e.selected).input.prompt.endsWith('sharper fins'), true);
});

test('--only processes just those sprites', async (t) => {
  const { mock, root } = await setup(t);
  const r = await gen(root, mock, ['--only=boat,reef']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.submit, 2);
  const m = readManifest(root, GAME);
  assert.deepEqual(m.requests.map((e) => e.sprite).sort(), ['boat', 'reef']);
});

test('--reroll skips the cache and pays again; the newest result is selected', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await gen(root, mock)).code, 0);
  const listings = mock.state.counts.listing;
  const r = await gen(root, mock, ['--reroll=boat']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.submit, 5, 'only the rerolled sprite');
  assert.equal(mock.state.counts.listing, listings, '--reroll skips the 24-hour reuse');
  const boats = readManifest(root, GAME).requests.filter((e) => e.sprite === 'boat');
  assert.equal(boats.length, 2);
  assert.equal(boats[1].selected, true);
  assert.equal(boats[0].selected, false);
  assert.deepEqual(boats[0].input, boats[1].input, 'same input, new paid result');
  assert.notEqual(boats[0].request_id, boats[1].request_id);
});

test('--select picks a result; a cache-hit run keeps it; a new result replaces it', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await gen(root, mock)).code, 0);
  assert.equal((await gen(root, mock, ['--reroll=boat'])).code, 0);
  let boats = readManifest(root, GAME).requests.filter((e) => e.sprite === 'boat');
  const older = boats[0].request_id;
  const submits = mock.state.counts.submit;
  let r = await runGenerate([`--game=${GAME}`, `--root=${root}`, `--mock=${mock.url}`, `--select=boat:${older}`], { env: childEnv() });
  assert.equal(r.code, 0, r.stderr);
  assert.match(r.stdout, new RegExp(`boat: selected ${older}`));
  assert.equal(mock.state.counts.submit, submits, '--select contacts nothing');
  boats = readManifest(root, GAME).requests.filter((e) => e.sprite === 'boat');
  assert.equal(boats.find((e) => e.selected).request_id, older);
  assert.equal(boats.find((e) => e.selected).selected_by, 'user');

  r = await gen(root, mock);
  assert.equal(r.code, 0, r.stderr);
  assert.match(r.stdout, /boat: keeps its --select choice/);
  boats = readManifest(root, GAME).requests.filter((e) => e.sprite === 'boat');
  assert.equal(boats.find((e) => e.selected).request_id, older);

  r = await gen(root, mock, ['--reroll=boat']);
  assert.equal(r.code, 0);
  boats = readManifest(root, GAME).requests.filter((e) => e.sprite === 'boat');
  assert.equal(boats.find((e) => e.selected).request_id, boats[2].request_id);
});

test('--select rejects unknown sprites, unknown requests and flags it cannot combine with', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await gen(root, mock, ['--only=boat'])).code, 0);
  const env = childEnv();
  let r = await runGenerate([`--game=${GAME}`, `--root=${root}`, `--mock=${mock.url}`, '--select=boat:nope'], { env });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /has no request nope for boat/);
  r = await runGenerate([`--game=${GAME}`, `--root=${root}`, `--mock=${mock.url}`, '--select=ghost:x'], { env });
  assert.equal(r.code, 2);
  r = await runGenerate([`--game=${GAME}`, `--root=${root}`, `--mock=${mock.url}`, '--select=boat', '--only=boat'], { env });
  assert.equal(r.code, 2);
  r = await runGenerate([`--game=${GAME}`, `--root=${root}`, `--mock=${mock.url}`, '--select=boat:x', '--only=boat'], { env });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /--select only edits the manifest/);
});

test('flare drafts, then sunburst: the sunburst result is selected; switching back reuses the cached draft', async (t) => {
  const { mock, root } = await setup(t);
  writeArt(root, GAME, smallArt({ endpoint: DRAFT_ENDPOINT }));
  assert.equal((await gen(root, mock, ['--only=boat,fish_tuna'])).code, 0);
  let m = readManifest(root, GAME);
  assert.ok(m.requests.every((e) => e.endpoint === DRAFT_ENDPOINT));
  assert.ok(m.requests.every((e) => e.estimated_usd < 0.07), 'flare drafts are cheaper');
  writeArt(root, GAME, smallArt());
  assert.equal((await gen(root, mock)).code, 0);
  m = readManifest(root, GAME);
  for (const id of ['boat', 'fish_tuna']) {
    const sel = m.requests.filter((e) => e.sprite === id && e.selected);
    assert.equal(sel.length, 1);
    assert.equal(sel[0].endpoint, DEFAULT_ENDPOINT);
  }
  assert.equal(mock.state.counts.submit, 6);
  const submitted = mock.state.log.filter((l) => l.method === 'POST' && !l.path.startsWith('/_admin'));
  assert.equal(submitted.filter((l) => l.path === `/${DRAFT_ENDPOINT}`).length, 2);
  assert.equal(submitted.filter((l) => l.path === `/${DEFAULT_ENDPOINT}`).length, 4);
  // Back to flare for the boat: its cached draft is reused and selected again, for free.
  writeArt(root, GAME, smallArt({ endpoint: DRAFT_ENDPOINT }));
  const r = await gen(root, mock, ['--only=boat']);
  assert.equal(r.code, 0);
  assert.match(r.stdout, /boat: cached/);
  assert.equal(mock.state.counts.submit, 6);
  m = readManifest(root, GAME);
  assert.equal(m.requests.find((e) => e.sprite === 'boat' && e.selected).endpoint, DRAFT_ENDPOINT);
});

test('billed amounts are recorded beside the estimate; the spend total takes the larger of the two', async (t) => {
  const { mock, root } = await setup(t, smallArt(), { report_billed: true, billed_usd: 0.09 });
  const r = await gen(root, mock, ['--only=boat,fish_tuna']);
  assert.equal(r.code, 0, r.stderr);
  mock.configure({ billed_usd: 0.05 });
  assert.equal((await gen(root, mock, ['--only=bg_sky'])).code, 0);
  const m = readManifest(root, GAME);
  const byId = Object.fromEntries(m.requests.map((e) => [e.sprite, e]));
  assert.equal(byId.boat.billed_usd, 0.09);
  assert.equal(byId.boat.estimated_usd, 0.07);
  assert.equal(byId.bg_sky.billed_usd, 0.05);
  assert.deepEqual(m.spend, { total_usd: 0.25, estimated_usd: 0.21, billed_usd: 0.23, paid_requests: 3 });
  assert.match(r.stdout, /billed \$0\.0900/);
});

test('a model error is recorded as failed (paid, conservatively) and the run exits 1', async (t) => {
  const { mock, root } = await setup(t, smallArt(), { model_errors: 1 });
  const r = await gen(root, mock, ['--only=boat', '--concurrency=1']);
  assert.equal(r.code, 1);
  assert.match(r.stderr, /boat: failed/);
  const e = readManifest(root, GAME).requests[0];
  assert.equal(e.status, 'failed');
  assert.match(e.error, /mock model error/);
  assert.equal(e.selected, false);
  // The next run pays again (a failed request has no image) and succeeds.
  const r2 = await gen(root, mock, ['--only=boat']);
  assert.equal(r2.code, 0, r2.stderr);
  assert.equal(readManifest(root, GAME).requests.filter((x) => x.status === 'ok').length, 1);
});

test('a submit that fal rejects is not counted as spend', async (t) => {
  const { mock, root } = await setup(t, smallArt(), { fail_500: { submit: 1 } });
  const r = await gen(root, mock, ['--only=boat']);
  assert.equal(r.code, 1);
  const m = readManifest(root, GAME);
  assert.equal(m.requests[0].status, 'submit_failed');
  assert.equal(m.requests[0].paid, false);
  assert.equal(m.spend.total_usd, 0);
});

test('a slow request times out, is kept as recoverable, and the next run resumes it without paying', async (t) => {
  const { mock, root } = await setup(t, smallArt(), { polls_to_complete: 1000 });
  const r = await gen(root, mock, ['--only=boat', '--timeout-s=0.3']);
  assert.equal(r.code, 1);
  let e = readManifest(root, GAME).requests[0];
  assert.equal(e.status, 'timeout');
  assert.equal(e.paid, true);
  mock.configure({ polls_to_complete: 1 });
  const r2 = await gen(root, mock, ['--only=boat']);
  assert.equal(r2.code, 0, r2.stderr);
  assert.match(r2.stdout, /boat: recovered .* without paying again/);
  assert.equal(mock.state.counts.submit, 1);
  e = readManifest(root, GAME).requests[0];
  assert.equal(e.status, 'ok');
  assert.equal(e.selected, true);
});

test('status 500s are retried; concurrency runs several requests at once', async (t) => {
  const { mock, root } = await setup(t, smallArt(), { fail_500: { status: 2 } });
  const r = await gen(root, mock, ['--concurrency=4']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.submit, 4);
  assert.equal(readManifest(root, GAME).requests.filter((e) => e.status === 'ok').length, 4);
});

test('the manifest is valid JSON after every run and lives at assets/<id>/art_manifest.json', async (t) => {
  const { mock, root } = await setup(t);
  await gen(root, mock, ['--only=boat']);
  const text = fs.readFileSync(manifestFile(root, GAME), 'utf8');
  assert.ok(text.endsWith('\n'));
  JSON.parse(text);
  assert.deepEqual(fs.readdirSync(path.join(root, 'assets', GAME)).sort(), ['art.json', 'art_manifest.json']);
});
