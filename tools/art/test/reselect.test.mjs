// W4r2 R25: a --select choice that had to give way because its image could not be fetched stays on
// record ("reselect"): a later run fetches it again for free and selects it, and --select accepts a
// paid result whose image is not fetched yet. A new result for the sprite replaces such a choice.
// Mock only: no key, no WATTLANDS_ALLOW_ART.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { childEnv, makeRoot, mockArgs, mockFor, readManifest, removeRoot, runGenerate, smallArt } from './helpers.mjs';

const GAME = 'sel';

async function setup(t) {
  const mock = await mockFor(t);
  const root = makeRoot(GAME, smallArt({ sprites: [{ id: 'boat', prompt: 'a boat', size: [80, 32] }] }));
  t.after(() => removeRoot(root));
  return { mock, root, env: childEnv() };
}

const run = (root, mock, env, extra = []) => runGenerate(mockArgs(GAME, root, mock, extra), { env });
const row = (root, rid) => readManifest(root, GAME).requests.find((e) => e.request_id === rid);

/** r1 and r2 for "boat", r1 picked with --select, then the cache wiped and r1's image host down. */
async function demoted(t) {
  const { mock, root, env } = await setup(t);
  assert.equal((await run(root, mock, env)).code, 0);
  assert.equal((await run(root, mock, env, ['--reroll=boat'])).code, 0);
  const [r1, r2] = readManifest(root, GAME).requests;
  assert.equal((await run(root, mock, env, [`--select=boat:${r1.request_id}`])).code, 0);
  fs.rmSync(path.join(root, '.art_cache'), { recursive: true, force: true });
  mock.configure({ fail_downloads: 3 });
  const a = await run(root, mock, env);
  mock.configure({ fail_downloads: 0 });
  return { mock, root, env, r1: r1.request_id, r2: r2.request_id, a };
}

test('a demoted --select choice is fetched again and selected by the next healthy run', async (t) => {
  const { mock, root, env, r1, r2, a } = await demoted(t);
  assert.match(a.stderr, new RegExp(`--select choice ${r1} is "download_failed"`));
  assert.match(a.stderr, /A later run fetches .* again for free and selects it/);
  assert.doesNotMatch(a.stderr, /--select it again/, 'no advice that cannot work');
  let e1 = row(root, r1);
  assert.equal(e1.reselect, true, 'the choice stays on record');
  assert.equal(row(root, r2).selected, true, 'the usable result is selected meanwhile');

  const b = await run(root, mock, env);
  assert.equal(b.code, 0, b.stdout + b.stderr);
  assert.match(b.stdout, new RegExp(`boat: fetched the --select choice ${r1} again and selected it`));
  e1 = row(root, r1);
  assert.equal(e1.status, 'ok');
  assert.equal(e1.selected, true);
  assert.equal(e1.selected_by, 'user');
  assert.equal(e1.reselect, undefined);
  assert.equal(mock.state.counts.submit, 2, 'nothing paid again');

  const c = await run(root, mock, env);
  assert.equal(c.code, 0);
  assert.equal(row(root, r1).selected, true, 'and it stays selected');
  const d = await run(root, mock, env, [`--select=boat:${r1}`]);
  assert.equal(d.code, 0, d.stderr);
});

test('--select accepts a paid result whose image is not fetched yet; the next run fetches and selects it', async (t) => {
  const { mock, root, env } = await setup(t);
  assert.equal((await run(root, mock, env)).code, 0);
  mock.configure({ fail_downloads: 3 });
  const rr = await run(root, mock, env, ['--reroll=boat']);
  assert.equal(rr.code, 1, 'the reroll was paid but its image could not be fetched');
  mock.configure({ fail_downloads: 0 });
  const [r1, r2] = readManifest(root, GAME).requests;
  assert.equal(r2.status, 'download_failed');
  const s = await run(root, mock, env, [`--select=boat:${r2.request_id}`]);
  assert.equal(s.code, 0, s.stderr);
  assert.match(s.stdout, /the next generate run fetches its image \(for free\) and selects it/);
  assert.equal(row(root, r2.request_id).reselect, true);
  assert.equal(row(root, r1.request_id).selected, true, 'the usable selection stays until then');
  const b = await run(root, mock, env);
  assert.equal(b.code, 0, b.stdout + b.stderr);
  assert.equal(row(root, r2.request_id).selected, true);
  assert.equal(row(root, r2.request_id).selected_by, 'user');
  assert.equal(mock.state.counts.submit, 2);
});

test('a new result for the sprite replaces a choice still waiting for its image', async (t) => {
  const { mock, root, env, r1 } = await demoted(t);
  mock.configure({ fail_downloads: 0 });
  const b = await run(root, mock, env, ['--reroll=boat']);
  assert.equal(b.code, 0, b.stdout + b.stderr);
  const m = readManifest(root, GAME);
  const newest = m.requests[m.requests.length - 1];
  assert.equal(newest.selected, true, 'the new result is selected');
  assert.equal(row(root, r1).reselect, undefined, 'the waiting choice was dropped');
});
