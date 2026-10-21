// The key never appears in output, logs or the manifest, and is only ever sent to fal's API hosts
// (BRIEF 1, 3.10; docs/OWNERSHIP.md ART7).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { FalClient } from '../lib/fal.mjs';
import { makeRedactor } from '../lib/locks.mjs';
import {
  childEnv,
  DUMMY_KEY,
  DUMMY_KEY_PARTS,
  makeRoot,
  mockArgs,
  mockFor,
  removeRoot,
  runGenerate,
  smallArt,
  walk,
} from './helpers.mjs';

const GAME = 'sec';

function assertNoKey(text, where) {
  for (const p of DUMMY_KEY_PARTS) assert.equal(String(text).includes(p), false, `${where} contains part of the key`);
}

test('a --mock run with a dummy FAL_KEY set: the key is in no output, file or request', async (t) => {
  const mock = await mockFor(t, { fail_downloads: 3, report_billed: true });
  const root = makeRoot(GAME, smallArt());
  t.after(() => removeRoot(root));
  const env = childEnv({ dummyKey: true });
  const runs = [
    await runGenerate(mockArgs(GAME, root, mock, ['--concurrency=1']), { env }),
    await runGenerate(mockArgs(GAME, root, mock), { env }),
    await runGenerate(mockArgs(GAME, root, mock, ['--dry-run']), { env }),
    await runGenerate(mockArgs(GAME, root, mock, ['--reroll=boat', '--budget=0.01']), { env }),
  ];
  assert.equal(runs[0].code, 1, 'the first run hits the injected download failure');
  assert.equal(runs[1].code, 0, runs[1].stderr);
  for (const r of runs) {
    assertNoKey(r.stdout, 'stdout');
    assertNoKey(r.stderr, 'stderr');
  }
  for (const f of walk(root)) assertNoKey(fs.readFileSync(f).toString('latin1'), path.relative(root, f));
  // The mock never received the key: --mock never reads FAL_KEY at all.
  assert.ok(mock.state.log.length > 0);
  for (const entry of mock.state.log) {
    assertNoKey(entry.headers, `request headers ${entry.path}`);
    assertNoKey(entry.body, `request body ${entry.path}`);
    assertNoKey(entry.query, `query ${entry.path}`);
  }
  // Image downloads go without credentials.
  for (const entry of mock.state.log.filter((l) => l.path.startsWith('/files/'))) assert.equal(entry.authorization, null);
});

function fakeFetch(responses) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init });
    const u = new URL(url);
    const body = responses(u, init);
    return new Response(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body), { status: 200 });
  };
  fn.calls = calls;
  return fn;
}

test('FalClient (real mode, fake fetch): the key goes to queue.fal.run and api.fal.ai only', async () => {
  const fetchImpl = fakeFetch((u) => {
    if (u.hostname === 'queue.fal.run' && u.pathname.endsWith('/status')) return { status: 'COMPLETED' };
    if (u.hostname === 'queue.fal.run' && u.pathname.includes('/requests/')) return { images: [{ url: 'https://v3.fal.media/files/x.png' }] };
    if (u.hostname === 'queue.fal.run') return { request_id: 'r1' };
    if (u.hostname === 'api.fal.ai') return { items: [], next_cursor: null };
    return Buffer.from('png');
  });
  const c = new FalClient({ key: DUMMY_KEY, fetchImpl, redact: makeRedactor(DUMMY_KEY) });
  const sub = await c.submit('openai/gpt-image-2.5/sunburst/text-to-image', { prompt: 'p' });
  assert.equal(sub.status_url, 'https://queue.fal.run/openai/gpt-image-2.5/requests/r1/status', 'tracking URLs use owner/app only');
  await c.status(sub.status_url);
  await c.result(sub.response_url);
  await c.listRequests('openai/gpt-image-2.5/sunburst/text-to-image', new Date().toISOString());
  await c.download('https://v3.fal.media/files/x.png');
  const auth = (u) => fetchImpl.calls.find((x) => x.url.startsWith(u)).init.headers.Authorization;
  assert.equal(auth('https://queue.fal.run/openai/gpt-image-2.5/sunburst'), `Key ${DUMMY_KEY}`);
  assert.equal(auth('https://api.fal.ai/'), `Key ${DUMMY_KEY}`);
  assert.equal(auth('https://v3.fal.media/'), undefined, 'no credentials to the image CDN');
  for (const call of fetchImpl.calls) {
    assert.ok(new URL(call.url).protocol === 'https:');
    assertNoKey(call.url, 'a URL');
    assert.equal(call.init.redirect, 'manual');
  }
});

test("FalClient refuses hosts that are not fal's, plain http, and the key on a non-API fal host", async () => {
  const fetchImpl = fakeFetch(() => ({}));
  const c = new FalClient({ key: DUMMY_KEY, fetchImpl, redact: makeRedactor(DUMMY_KEY) });
  await assert.rejects(c.download('https://example.com/x.png'), /refusing to contact/);
  await assert.rejects(c.download('http://v3.fal.media/x.png'), /refusing to contact/);
  await assert.rejects(c.download('https://fal.media.example.com/x.png'), /refusing to contact/);
  await assert.rejects(c.status('https://v3.fal.media/requests/x/status'), /refusing to send the fal key to v3\.fal\.media/);
  await assert.rejects(c.result('https://evil.example/requests/x'), /refusing to contact/);
  assert.equal(fetchImpl.calls.length, 0, 'nothing was fetched');
});

test('FalClient follows redirects only to allowed hosts', async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    calls.push(url);
    if (url === 'https://v3.fal.media/a.png') return new Response('', { status: 302, headers: { location: 'https://example.com/b.png' } });
    if (url === 'https://v3.fal.media/c.png') return new Response('', { status: 302, headers: { location: 'https://v3b.fal.media/c.png' } });
    return new Response('ok', { status: 200 });
  };
  const c = new FalClient({ key: DUMMY_KEY, fetchImpl });
  await assert.rejects(c.download('https://v3.fal.media/a.png'), /refusing to contact https:\/\/example\.com/);
  assert.equal((await c.download('https://v3.fal.media/c.png')).toString(), 'ok');
  assert.deepEqual(calls, ['https://v3.fal.media/a.png', 'https://v3.fal.media/c.png', 'https://v3b.fal.media/c.png']);
});

test('errors are redacted: a server that echoes the key never gets it printed', async () => {
  const fetchImpl = async (_url, init) => new Response(`bad key ${init.headers.Authorization}`, { status: 401 });
  const c = new FalClient({ key: DUMMY_KEY, fetchImpl, redact: makeRedactor(DUMMY_KEY) });
  const err = await c.status('https://queue.fal.run/a/b/requests/x/status').catch((e) => e);
  assert.match(err.message, /HTTP 401/);
  assert.match(err.message, /\[redacted\]/);
  assertNoKey(err.message, 'the error');
  assertNoKey(err.body, 'the error body');
  const thrower = async () => {
    throw new Error(`connect failed for ${DUMMY_KEY}`);
  };
  const c2 = new FalClient({ key: DUMMY_KEY, fetchImpl: thrower, redact: makeRedactor(DUMMY_KEY) });
  const err2 = await c2.status('https://queue.fal.run/a/b/requests/x/status').catch((e) => e);
  assertNoKey(err2.message, 'the network error');
});

test('a mock client never holds or sends the key', async () => {
  const fetchImpl = fakeFetch(() => ({ request_id: 'r' }));
  const c = new FalClient({ mockOrigin: 'http://127.0.0.1:1234', key: DUMMY_KEY, fetchImpl });
  assert.equal(c.key, null);
  await c.submit('a/b/c', { prompt: 'p' });
  assert.equal(fetchImpl.calls[0].init.headers.Authorization, 'Key mock');
  await assert.rejects(c.download('https://v3.fal.media/x.png'), /only the mock/);
});

test('makeRedactor removes the key and its parts', () => {
  const r = makeRedactor(DUMMY_KEY);
  const s = r(`a ${DUMMY_KEY} b dummyid-4f1c8e c dummysecret-9a7e3b55c2`);
  assertNoKey(s, 'redacted text');
  assert.equal(makeRedactor(null)('same'), 'same');
});
