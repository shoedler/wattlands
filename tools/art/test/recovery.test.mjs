// Recovering a paid result after a failed download (BRIEF 3.10, docs/OWNERSHIP.md ART9): before paying,
// generate.mjs looks for a paid result with the same input from the last 24 hours in fal's request
// history (GET /v1/models/requests/by-endpoint?expand=payloads) and downloads it instead.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { DEFAULT_ENDPOINT } from '../lib/config.mjs';
import { decodePng } from '../lib/png.mjs';
import { childEnv, makeRoot, manifestFile, mockArgs, mockFor, readManifest, removeRoot, runGenerate, smallArt } from './helpers.mjs';

const GAME = 'rec';

async function setup(t, mockConfig = {}) {
  const mock = await mockFor(t, mockConfig);
  const root = makeRoot(GAME, smallArt());
  t.after(() => removeRoot(root));
  return { mock, root };
}

const gen = (root, mock, extra = []) => runGenerate(mockArgs(GAME, root, mock, ['--concurrency=1', ...extra]), { env: childEnv() });

test('a download that fails after billing is recorded with its request id; the next run fetches it without paying', async (t) => {
  const { mock, root } = await setup(t, { fail_downloads: 3 });
  const r1 = await gen(root, mock, ['--only=boat']);
  assert.equal(r1.code, 1);
  assert.match(r1.stderr, /boat: download_failed/);
  const m1 = readManifest(root, GAME);
  const e1 = m1.requests[0];
  assert.equal(e1.status, 'download_failed');
  assert.equal(e1.paid, true);
  assert.ok(e1.request_id);
  assert.ok(e1.image_url);
  assert.equal(m1.spend.total_usd, 0.07, 'the paid request counts toward spend');
  assert.equal(mock.state.requests.get(e1.request_id).billed_usd, 0.07, 'fal billed it');

  const r2 = await gen(root, mock, ['--only=boat']);
  assert.equal(r2.code, 0, r2.stderr);
  assert.match(r2.stdout, /boat: recovered .* without paying again/);
  assert.equal(mock.state.counts.submit, 1, 'no second payment');
  const m2 = readManifest(root, GAME);
  assert.equal(m2.requests.length, 1);
  assert.equal(m2.requests[0].status, 'ok');
  assert.equal(m2.requests[0].selected, true);
  assert.equal(m2.spend.total_usd, 0.07);
  assert.ok(fs.existsSync(path.join(root, m2.requests[0].cache)));
});

test('with the record lost, the 24-hour history finds the paid result and downloads it', async (t) => {
  const { mock, root } = await setup(t, { fail_downloads: 3 });
  assert.equal((await gen(root, mock, ['--only=boat'])).code, 1);
  const paidId = readManifest(root, GAME).requests[0].request_id;
  fs.rmSync(manifestFile(root, GAME)); // a crash before the manifest was written, or a lost file
  const listings = mock.state.counts.listing;
  const logStart = mock.state.log.length;

  const r = await gen(root, mock, ['--only=boat']);
  assert.equal(r.code, 0, r.stderr);
  assert.match(r.stdout, new RegExp(`boat: recovered paid result ${paidId} from fal's request history`));
  assert.equal(mock.state.counts.submit, 1, 'no second payment');
  assert.equal(mock.state.counts.listing, listings + 1);
  const q = mock.state.log.slice(logStart).find((l) => l.path === '/v1/models/requests/by-endpoint');
  const params = new URLSearchParams(q.query);
  assert.equal(params.get('endpoint_id'), DEFAULT_ENDPOINT);
  assert.equal(params.get('expand'), 'payloads');
  assert.equal(params.get('status'), 'success');
  assert.ok(Date.now() - Date.parse(params.get('start')) <= 24 * 3600 * 1000 + 60000, 'asks for the last 24 hours');
  const m = readManifest(root, GAME);
  assert.equal(m.requests.length, 1);
  const e = m.requests[0];
  assert.equal(e.request_id, paidId);
  assert.equal(e.source, 'recovered');
  assert.equal(e.paid, true);
  assert.equal(e.status, 'ok');
  assert.equal(e.selected, true);
  assert.equal(m.spend.total_usd, 0.07);
  const png = decodePng(fs.readFileSync(path.join(root, e.cache)));
  assert.equal(png.width, e.input.image_size.width);
});

test('a paid result from another run with the same input is reused, a different input is not', async (t) => {
  const { mock, root } = await setup(t);
  // Find the exact input generate.mjs would send for the boat, via a dry run's plan.
  const plan = JSON.parse((await runGenerate([`--game=${GAME}`, `--root=${root}`, `--mock=${mock.url}`, '--dry-run', '--json'], { env: childEnv() })).stdout);
  const boat = plan.sprites.find((s) => s.id === 'boat');
  const art = smallArt();
  const input = {
    prompt: `${art.style} ${art.sprites[0].prompt}`,
    image_size: { width: boat.request[0], height: boat.request[1] },
    background: 'transparent',
    quality: 'high',
    num_images: 1,
    output_format: 'png',
  };
  const same = mock.insert({ endpoint: DEFAULT_ENDPOINT, input, ended_at: new Date(Date.now() - 3600 * 1000).toISOString() });
  mock.insert({ endpoint: DEFAULT_ENDPOINT, input: { ...input, prompt: `${input.prompt} (other)` } });
  const r = await gen(root, mock, ['--only=boat,fish_tuna']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.submit, 1, 'only the tuna is paid');
  const m = readManifest(root, GAME);
  assert.equal(m.requests.find((e) => e.sprite === 'boat').request_id, same.id);
  assert.equal(m.requests.find((e) => e.sprite === 'boat').source, 'recovered');
});

test('results older than 24 hours are not reused', async (t) => {
  const { mock, root } = await setup(t, { fail_downloads: 3 });
  assert.equal((await gen(root, mock, ['--only=boat'])).code, 1);
  const old = readManifest(root, GAME).requests[0];
  fs.rmSync(manifestFile(root, GAME));
  const req = mock.state.requests.get(old.request_id);
  const longAgo = new Date(Date.now() - 25 * 3600 * 1000).toISOString();
  req.started_at = longAgo;
  req.ended_at = longAgo;
  const r = await gen(root, mock, ['--only=boat']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.submit, 2, 'paid again');
  assert.notEqual(readManifest(root, GAME).requests[0].request_id, old.request_id);
});

test('--reroll skips the history and pays', async (t) => {
  const { mock, root } = await setup(t, { fail_downloads: 3 });
  assert.equal((await gen(root, mock, ['--only=boat'])).code, 1);
  fs.rmSync(manifestFile(root, GAME));
  const listings = mock.state.counts.listing;
  const r = await gen(root, mock, ['--reroll=boat']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.listing, listings);
  assert.equal(mock.state.counts.submit, 2);
});

test('a history that cannot be read is a warning, not a failure', async (t) => {
  const { mock, root } = await setup(t, { fail_500: { listing: 5 } });
  const r = await gen(root, mock, ['--only=boat']);
  assert.equal(r.code, 0, r.stderr);
  assert.match(r.stderr, /warning: cannot read fal's request history/);
  assert.equal(mock.state.counts.submit, 1);
});

test('a dropped connection during the download is recoverable too', async (t) => {
  const { mock, root } = await setup(t, { fail_downloads: 3, fail_download_mode: 'reset' });
  const r1 = await gen(root, mock, ['--only=fish_tuna']);
  assert.equal(r1.code, 1);
  assert.equal(readManifest(root, GAME).requests[0].status, 'download_failed');
  const r2 = await gen(root, mock, ['--only=fish_tuna']);
  assert.equal(r2.code, 0, r2.stderr);
  assert.equal(mock.state.counts.submit, 1);
});

test('a missing cache file with a known image URL is fetched again for free', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await gen(root, mock, ['--only=boat'])).code, 0);
  const e = readManifest(root, GAME).requests[0];
  fs.rmSync(path.join(root, '.art_cache'), { recursive: true });
  const r = await gen(root, mock, ['--only=boat']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.submit, 1);
  assert.ok(fs.existsSync(path.join(root, e.cache)));
});

test('a record from another host (real fal in a mock run) is left alone and never contacted', async (t) => {
  const { mock, root } = await setup(t, { polls_to_complete: 1000 });
  assert.equal((await gen(root, mock, ['--only=boat', '--timeout-s=0.2'])).code, 1);
  const m = readManifest(root, GAME);
  const e = m.requests[0];
  assert.equal(e.status, 'timeout');
  e.status_url = `https://queue.fal.run/openai/gpt-image-2.5/requests/${e.request_id}/status`;
  e.response_url = `https://queue.fal.run/openai/gpt-image-2.5/requests/${e.request_id}`;
  fs.writeFileSync(manifestFile(root, GAME), JSON.stringify(m, null, 2));
  mock.configure({ polls_to_complete: 1 });
  const r = await gen(root, mock, ['--only=boat']);
  assert.equal(r.code, 0, r.stderr);
  assert.doesNotMatch(r.stderr, /refusing/);
  assert.equal(mock.state.counts.submit, 2, 'paid for a new result instead');
  const after = readManifest(root, GAME).requests;
  assert.equal(after[0].status, 'timeout');
  assert.equal(after[0].status_url, e.status_url);
  assert.equal(after[1].status, 'ok');
  assert.equal(after[1].selected, true);
});

test('a --reroll whose download failed is recovered by the next run and wins over the older cached result', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await gen(root, mock, ['--only=boat'])).code, 0);
  const first = readManifest(root, GAME).requests[0].request_id;
  mock.configure({ fail_downloads: 3 });
  assert.equal((await gen(root, mock, ['--reroll=boat'])).code, 1);
  let boats = readManifest(root, GAME).requests;
  assert.equal(boats[1].status, 'download_failed');
  assert.equal(boats.find((e) => e.selected).request_id, first, 'the failed reroll is not selected yet');
  const r = await gen(root, mock, ['--only=boat']);
  assert.equal(r.code, 0, r.stderr);
  assert.match(r.stdout, new RegExp(`boat: recovered ${boats[1].request_id} without paying again`));
  assert.equal(mock.state.counts.submit, 2, 'the paid reroll is fetched, not paid again');
  boats = readManifest(root, GAME).requests;
  assert.equal(boats.length, 2);
  assert.equal(boats.find((e) => e.selected).request_id, boats[1].request_id, 'the newest paid result is selected');
  // From now on the newer result is the cache hit.
  const again = await gen(root, mock, ['--only=boat']);
  assert.match(again.stdout, new RegExp(`boat: cached ${boats[1].request_id}`));
});

test('an unfinished newer request gets one status check, not a long wait, while an older result is cached', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await gen(root, mock, ['--only=boat'])).code, 0);
  const first = readManifest(root, GAME).requests[0].request_id;
  mock.configure({ polls_to_complete: 1000 });
  assert.equal((await gen(root, mock, ['--reroll=boat', '--timeout-s=0.2'])).code, 1);
  const pending = readManifest(root, GAME).requests[1];
  assert.equal(pending.status, 'timeout');
  const statusBefore = mock.state.counts.status;
  const started = Date.now();
  const r = await gen(root, mock, ['--only=boat', '--timeout-s=60', '--poll-ms=200']);
  assert.equal(r.code, 0, r.stderr);
  assert.ok(Date.now() - started < 20000, 'no wait for the unfinished request');
  assert.equal(mock.state.counts.status - statusBefore, 1, 'one status check');
  assert.match(r.stdout, new RegExp(`boat: cached ${first}`));
  assert.equal(readManifest(root, GAME).requests[1].status, 'timeout', 'still recoverable');
  // Once fal has finished it, the next run fetches it for free and selects it.
  mock.configure({ polls_to_complete: 1 });
  const r2 = await gen(root, mock, ['--only=boat']);
  assert.equal(r2.code, 0, r2.stderr);
  assert.match(r2.stdout, new RegExp(`boat: recovered ${pending.request_id}`));
  assert.equal(mock.state.counts.submit, 2);
  assert.equal(readManifest(root, GAME).requests.find((e) => e.selected).request_id, pending.request_id);
});

test('a --select choice whose raw image is missing is fetched again for free and stays selected', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await gen(root, mock, ['--only=boat'])).code, 0);
  assert.equal((await gen(root, mock, ['--reroll=boat'])).code, 0);
  const [older, newer] = readManifest(root, GAME).requests;
  const sel = await runGenerate([`--game=${GAME}`, `--root=${root}`, `--mock=${mock.url}`, `--select=boat:${older.request_id}`], { env: childEnv() });
  assert.equal(sel.code, 0, sel.stderr);
  fs.rmSync(path.join(root, older.cache));
  const r = await gen(root, mock, ['--only=boat']);
  assert.equal(r.code, 0, r.stderr);
  assert.match(r.stdout, new RegExp(`boat: fetched the selected result ${older.request_id} again`));
  assert.equal(mock.state.counts.submit, 2);
  const m = readManifest(root, GAME);
  const selected = m.requests.find((e) => e.selected);
  assert.equal(selected.request_id, older.request_id);
  assert.equal(selected.selected_by, 'user');
  assert.ok(fs.existsSync(path.join(root, older.cache)));
  // Re-fetching an image that was already fine (the newer one, after a cache wipe) keeps the choice too.
  fs.rmSync(path.join(root, '.art_cache'), { recursive: true });
  const r2 = await gen(root, mock, ['--only=boat']);
  assert.equal(r2.code, 0, r2.stderr);
  assert.equal(readManifest(root, GAME).requests.find((e) => e.selected).request_id, older.request_id);
  assert.ok(fs.existsSync(path.join(root, older.cache)));
  assert.ok(fs.existsSync(path.join(root, newer.cache)));
  assert.equal(mock.state.counts.submit, 2);
});
