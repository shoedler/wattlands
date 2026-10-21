// tools/art/mock_fal: queue API shapes, history listing, generated images, failure injection, admin API.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { test } from 'node:test';
import { decodePng } from '../lib/png.mjs';
import { ART_DIR, mockFor } from './helpers.mjs';

const EP = 'openai/gpt-image-2.5/sunburst/text-to-image';
const AUTH = { Authorization: 'Key mock', 'Content-Type': 'application/json' };
const input = (o = {}) => ({
  prompt: 'a test sprite',
  image_size: { width: 1024, height: 640 },
  background: 'transparent',
  quality: 'high',
  num_images: 1,
  output_format: 'png',
  ...o,
});

async function submit(mock, body = input()) {
  const r = await fetch(`${mock.url}/${EP}`, { method: 'POST', headers: AUTH, body: JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
}

async function getJson(url, headers = AUTH) {
  const r = await fetch(url, { headers });
  return { status: r.status, body: await r.json() };
}

async function runToCompletion(mock, body) {
  const s = await submit(mock, body);
  let st;
  do st = await getJson(s.body.status_url);
  while (st.body.status !== 'COMPLETED');
  return { sub: s.body, st: st.body };
}

test('submit returns fal-shaped URLs built from owner/app only', async (t) => {
  const mock = await mockFor(t);
  const s = await submit(mock);
  assert.equal(s.status, 200);
  assert.match(s.body.request_id, /^[0-9a-f-]{36}$/);
  assert.equal(s.body.status_url, `${mock.url}/openai/gpt-image-2.5/requests/${s.body.request_id}/status`);
  assert.equal(s.body.response_url, `${mock.url}/openai/gpt-image-2.5/requests/${s.body.request_id}`);
  assert.equal(s.body.cancel_url, `${mock.url}/openai/gpt-image-2.5/requests/${s.body.request_id}/cancel`);
  assert.equal(s.body.queue_position, 0);
});

test('status goes IN_PROGRESS then COMPLETED; the result lists one PNG of the requested size', async (t) => {
  const mock = await mockFor(t);
  const s = await submit(mock);
  const early = await getJson(s.body.response_url);
  assert.equal(early.status, 400);
  const a = await getJson(s.body.status_url);
  assert.equal(a.body.status, 'IN_PROGRESS');
  const b = await getJson(s.body.status_url);
  assert.equal(b.body.status, 'COMPLETED');
  assert.equal(typeof b.body.metrics.inference_time, 'number');
  const res = await getJson(s.body.response_url);
  assert.equal(res.status, 200);
  const img = res.body.images[0];
  assert.equal(img.content_type, 'image/png');
  assert.equal(img.width, 1024);
  assert.equal(img.height, 640);
  assert.equal(res.body.billing, undefined, 'no billed amount unless report_billed is set');
  const file = await fetch(img.url);
  const png = decodePng(Buffer.from(await file.arrayBuffer()));
  assert.equal(png.width, 1024);
  assert.equal(png.height, 640);
});

test('generated images honour the background and are deterministic per input', async (t) => {
  const mock = await mockFor(t);
  const t1 = await runToCompletion(mock, input());
  const o1 = await runToCompletion(mock, input({ background: 'opaque', image_size: { width: 1216, height: 608 } }));
  const t2 = await runToCompletion(mock, input());
  const load = async (sub) => {
    const res = await getJson(sub.response_url);
    return Buffer.from(await (await fetch(res.body.images[0].url)).arrayBuffer());
  };
  const tp = decodePng(await load(t1.sub));
  const op = decodePng(await load(o1.sub));
  assert.equal(op.width, 1216);
  assert.equal(op.height, 608);
  let transparent = 0;
  let opaque = 0;
  for (let i = 3; i < tp.data.length; i += 4) {
    if (tp.data[i] === 0) transparent += 1;
    else if (tp.data[i] === 255) opaque += 1;
  }
  assert.ok(transparent > 0 && opaque > 0, 'a shape on a transparent canvas');
  assert.equal(tp.data[3], 0, 'the corner is transparent (a margin to trim)');
  for (let i = 3; i < op.data.length; i += 4) assert.equal(op.data[i], 255);
  assert.deepEqual(await load(t2.sub), await load(t1.sub));
});

test("fal's input limits are enforced with 422", async (t) => {
  const mock = await mockFor(t);
  for (const bad of [
    input({ image_size: { width: 1000, height: 640 } }),
    input({ image_size: { width: 512, height: 512 } }),
    input({ image_size: { width: 3840, height: 1024 } }),
    input({ background: 'white' }),
    input({ quality: 'ultra' }),
    input({ output_format: 'gif' }),
    input({ prompt: '' }),
  ]) {
    const s = await submit(mock, bad);
    assert.equal(s.status, 422, JSON.stringify(bad));
    assert.ok(Array.isArray(s.body.detail));
  }
});

test('auth is required on the queue and the history, not on image downloads', async (t) => {
  const mock = await mockFor(t);
  const r = await fetch(`${mock.url}/${EP}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input()) });
  assert.equal(r.status, 401);
  const { sub } = await runToCompletion(mock, input());
  const res = await getJson(sub.response_url);
  const file = await fetch(res.body.images[0].url);
  assert.equal(file.status, 200);
  const l = await fetch(`${mock.url}/v1/models/requests/by-endpoint?endpoint_id=${EP}`);
  assert.equal(l.status, 401);
});

test('the by-endpoint listing: payloads, time window, status filter, pagination', async (t) => {
  const mock = await mockFor(t);
  await runToCompletion(mock, input({ prompt: 'one' }));
  await runToCompletion(mock, input({ prompt: 'two' }));
  mock.insert({ endpoint: EP, input: input({ prompt: 'old' }), ended_at: new Date(Date.now() - 25 * 3600 * 1000).toISOString() });
  const base = `${mock.url}/v1/models/requests/by-endpoint?endpoint_id=${encodeURIComponent(EP)}`;
  let l = await getJson(`${base}&expand=payloads&status=success`);
  assert.equal(l.status, 200);
  assert.equal(l.body.items.length, 2, 'the default window is the last 24 hours');
  const it = l.body.items[0];
  for (const k of ['request_id', 'endpoint_id', 'started_at', 'sent_at', 'ended_at', 'status_code', 'duration', 'json_input', 'json_output']) {
    assert.ok(k in it, k);
  }
  assert.equal(it.status_code, 200);
  assert.ok(it.json_output.images[0].url.startsWith(mock.url));
  l = await getJson(base);
  assert.equal('json_input' in l.body.items[0], false, 'payloads only with expand=payloads');
  const start = new Date(Date.now() - 48 * 3600 * 1000).toISOString();
  l = await getJson(`${base}&start=${encodeURIComponent(start)}&limit=2`);
  assert.equal(l.body.items.length, 2);
  assert.equal(l.body.has_more, true);
  const l2 = await getJson(`${base}&start=${encodeURIComponent(start)}&limit=2&cursor=${l.body.next_cursor}`);
  assert.equal(l2.body.items.length, 1);
  assert.equal(l2.body.next_cursor, null);
  l = await getJson(`${base}&status=error`);
  assert.equal(l.body.items.length, 0);
  l = await getJson(`${mock.url}/v1/models/requests/by-endpoint`);
  assert.equal(l.status, 400);
});

test('failure injection: model errors, 500s, download failures after billing', async (t) => {
  const mock = await mockFor(t);
  mock.configure({ model_errors: 1 });
  const failed = await runToCompletion(mock, input());
  assert.equal(failed.st.error, 'mock model error');
  assert.equal(failed.st.error_type, 'internal_error');
  assert.equal((await getJson(failed.sub.response_url)).status, 500);

  mock.configure({ fail_500: { submit: 1 } });
  assert.equal((await submit(mock)).status, 500);
  assert.equal((await submit(mock)).status, 200);

  mock.configure({ fail_downloads: 1 });
  const { sub } = await runToCompletion(mock, input({ prompt: 'billed' }));
  const res = await getJson(sub.response_url);
  assert.equal((await fetch(res.body.images[0].url)).status, 500);
  assert.equal((await fetch(res.body.images[0].url)).status, 200);
  const st = mock.state.requests.get(sub.request_id);
  assert.equal(st.billed_usd, 0.07, 'billed on completion even though the download failed');

  mock.configure({ fail_downloads: 1, fail_download_mode: 'reset' });
  await assert.rejects(fetch(res.body.images[0].url));
});

test('billed amounts are reported when report_billed is set', async (t) => {
  const mock = await mockFor(t, { report_billed: true, billed_usd: 0.09 });
  const { sub } = await runToCompletion(mock, input());
  const res = await getJson(sub.response_url);
  assert.deepEqual(res.body.billing, { cost_total: 0.09, currency: 'USD' });
  assert.equal(mock.state.billed_total_usd, 0.09);
});

test('admin API over HTTP: config, insert, state, reset', async (t) => {
  const mock = await mockFor(t);
  const post = (p, body) => fetch(`${mock.url}/_admin/${p}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then((r) => r.json());
  await post('config', { polls_to_complete: 1 });
  const s = await submit(mock);
  const st = await getJson(s.body.status_url);
  assert.equal(st.body.status, 'COMPLETED');
  const ins = await post('requests', { endpoint: EP, input: input({ prompt: 'x' }) });
  assert.match(ins.request_id, /^01a14c16/);
  const state = await (await fetch(`${mock.url}/_admin/state`)).json();
  assert.equal(state.counts.submit, 1);
  assert.equal(state.requests.length, 2);
  assert.ok(state.log.length >= 3);
  await post('reset', {});
  const after = await (await fetch(`${mock.url}/_admin/state`)).json();
  assert.equal(after.requests.length, 0);
  assert.equal(after.config.polls_to_complete, 2);
});

test('the CLI starts on --port=0 and prints the port', async () => {
  const child = spawn(process.execPath, [path.join(ART_DIR, 'mock_fal', 'server.mjs'), '--port=0'], { stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    const port = await new Promise((resolve, reject) => {
      let out = '';
      const timer = setTimeout(() => reject(new Error(`no port printed: ${out}`)), 10000);
      child.stdout.on('data', (d) => {
        out += d;
        const m = out.match(/MOCK_FAL_PORT=(\d+)/);
        if (m) {
          clearTimeout(timer);
          resolve(Number(m[1]));
        }
      });
    });
    assert.ok(port > 0);
    const r = await fetch(`http://127.0.0.1:${port}/_admin/state`);
    assert.equal(r.status, 200);
  } finally {
    child.kill();
  }
});
