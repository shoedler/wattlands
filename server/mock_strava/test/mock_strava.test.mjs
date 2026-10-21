// node:test suite for the mock Strava server (BRIEF 3.8, 7.6).
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createMockStrava, DEFAULT_CLIENT_ID, DEFAULT_CLIENT_SECRET, ACCESS_TOKEN_LIFETIME_S } from '../server.mjs';
import { fitCrc16, checkFit } from '../fit.mjs';
import { parseMultipart, boundaryOf } from '../multipart.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const NOW = 1_800_000_000;

let mock;
let base;

before(async () => {
  mock = createMockStrava({ now: NOW });
  const port = await mock.listen(0);
  base = `http://127.0.0.1:${port}`;
});

after(async () => {
  await mock.close();
});

beforeEach(async () => {
  await post('/admin/reset', {});
  await post('/admin/config', { processing_polls: 1 });
});

/** A minimal valid FIT file: header, a file_id definition and data message, CRC. */
export function tinyFit({ corruptCrc = false } = {}) {
  const body = Buffer.from([
    0x40, 0x00, 0x00, 0x00, 0x00, 0x02, // definition: local 0, file_id, 2 fields
    0x00, 0x01, 0x00, // type enum
    0x01, 0x02, 0x84, // manufacturer uint16
    0x00, 0x04, 0xff, 0x00, // data: activity, manufacturer 255
  ]);
  const header = Buffer.alloc(14);
  header[0] = 14;
  header[1] = 0x20;
  header.writeUInt16LE(2140, 2);
  header.writeUInt32LE(body.length, 4);
  header.write('.FIT', 8, 'ascii');
  header.writeUInt16LE(fitCrc16(header, 0, 12), 12);
  const all = Buffer.concat([header, body]);
  const crc = Buffer.alloc(2);
  crc.writeUInt16LE(fitCrc16(all) ^ (corruptCrc ? 1 : 0), 0);
  return Buffer.concat([all, crc]);
}

function post(p, json, headers = {}) {
  return fetch(base + p, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(json),
  });
}

function form(p, fields, headers = {}) {
  return fetch(base + p, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...headers },
    body: new URLSearchParams(fields).toString(),
  });
}

async function connect(scope = 'activity:write') {
  const redirect = 'http://127.0.0.1:5555/strava/callback';
  const q = new URLSearchParams({
    client_id: DEFAULT_CLIENT_ID, response_type: 'code', redirect_uri: redirect,
    approval_prompt: 'auto', scope, state: 'st4te',
  });
  const r = await fetch(`${base}/oauth/authorize?${q}`, { redirect: 'manual' });
  assert.equal(r.status, 302);
  const loc = new URL(r.headers.get('location'));
  assert.equal(loc.origin + loc.pathname, redirect);
  assert.equal(loc.searchParams.get('state'), 'st4te');
  const code = loc.searchParams.get('code');
  assert.ok(code);
  const t = await form('/oauth/token', {
    client_id: DEFAULT_CLIENT_ID, client_secret: DEFAULT_CLIENT_SECRET, code, grant_type: 'authorization_code',
  });
  assert.equal(t.status, 200);
  return t.json();
}

function multipart(fields, file) {
  const boundary = '----mockboundary42';
  const parts = [];
  for (const [k, v] of Object.entries(fields)) {
    parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`));
  }
  if (file) {
    parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${file.name}"\r\nContent-Type: application/octet-stream\r\n\r\n`));
    parts.push(file.data, Buffer.from('\r\n'));
  }
  parts.push(Buffer.from(`--${boundary}--\r\n`));
  return { body: Buffer.concat(parts), type: `multipart/form-data; boundary=${boundary}` };
}

async function upload(access, externalId, data = tinyFit(), extra = {}) {
  const mp = multipart({ data_type: 'fit', trainer: '1', name: 'Ride', description: 'd', external_id: externalId, ...extra }, { name: `${externalId}.fit`, data });
  return fetch(`${base}/api/v3/uploads`, {
    method: 'POST', headers: { Authorization: `Bearer ${access}`, 'Content-Type': mp.type }, body: mp.body,
  });
}

function status(access, id) {
  return fetch(`${base}/api/v3/uploads/${id}`, { headers: { Authorization: `Bearer ${access}` } });
}

test('fitCrc16 matches the CRC-16/ARC check value', () => {
  assert.equal(fitCrc16(Buffer.from('123456789')), 0xbb3d);
  assert.equal(fitCrc16(Buffer.alloc(0)), 0);
});

test('checkFit accepts a valid file and rejects bad CRCs and headers', () => {
  assert.equal(checkFit(tinyFit()).ok, true);
  assert.match(checkFit(tinyFit({ corruptCrc: true })).error, /file CRC/);
  const badHeader = tinyFit();
  badHeader[12] ^= 0xff;
  assert.match(checkFit(badHeader).error, /header CRC/);
  const badType = tinyFit();
  badType[9] = 0x58;
  assert.match(checkFit(badType).error, /data type/);
  assert.equal(checkFit(Buffer.from([1, 2, 3])).ok, false);
});

test('multipart parsing keeps fields and file bytes', () => {
  const data = Buffer.from([0, 1, 2, 0x0d, 0x0a, 255]);
  const mp = multipart({ a: 'x', b: 'y z' }, { name: 'f.fit', data });
  const parsed = parseMultipart(mp.body, boundaryOf(mp.type));
  assert.deepEqual(parsed.fields, { a: 'x', b: 'y z' });
  assert.equal(parsed.files.file.filename, 'f.fit');
  assert.deepEqual([...parsed.files.file.data], [...data]);
});

test('authorize redirects straight to the loopback callback with code and state', async () => {
  const tokens = await connect();
  assert.equal(tokens.token_type, 'Bearer');
  assert.equal(tokens.expires_at, NOW + ACCESS_TOKEN_LIFETIME_S);
  assert.ok(tokens.access_token && tokens.refresh_token);
  assert.equal(tokens.athlete.id, 4242);
});

test('authorize rejects a non-loopback redirect, a missing scope and an unknown client', async () => {
  const q = (o) => new URLSearchParams({ client_id: DEFAULT_CLIENT_ID, response_type: 'code', redirect_uri: 'http://127.0.0.1:1/strava/callback', scope: 'activity:write', state: 's', ...o });
  for (const bad of [{ redirect_uri: 'http://evil.example/cb' }, { scope: 'read' }, { client_id: '999' }, { response_type: 'token' }]) {
    const r = await fetch(`${base}/oauth/authorize?${q(bad)}`, { redirect: 'manual' });
    assert.equal(r.status, 400, JSON.stringify(bad));
  }
});

test('an authorize fault of 403 redirects with error=access_denied', async () => {
  await post('/admin/fault', { route: 'authorize', status: 403 });
  const q = new URLSearchParams({ client_id: DEFAULT_CLIENT_ID, response_type: 'code', redirect_uri: 'http://127.0.0.1:1/strava/callback', scope: 'activity:write', state: 's' });
  const r = await fetch(`${base}/oauth/authorize?${q}`, { redirect: 'manual' });
  const loc = new URL(r.headers.get('location'));
  assert.equal(loc.searchParams.get('error'), 'access_denied');
  assert.equal(loc.searchParams.get('code'), null);
});

test('faults can tamper with the state or redirect elsewhere', async () => {
  const q = new URLSearchParams({ client_id: DEFAULT_CLIENT_ID, response_type: 'code', redirect_uri: 'http://127.0.0.1:1/strava/callback', scope: 'activity:write', state: 's' });
  await post('/admin/fault', { route: 'authorize', status: 302, tamper_state: true });
  const r1 = await fetch(base + "/oauth/authorize?" + q, { redirect: 'manual' });
  assert.equal(new URL(r1.headers.get('location')).searchParams.get('state'), 'sx');
  await post('/admin/fault', { route: 'authorize', status: 307, location: 'https://example.com/elsewhere' });
  const r2 = await fetch(base + "/oauth/authorize?" + q, { redirect: 'manual' });
  assert.equal(r2.status, 307);
  assert.equal(r2.headers.get('location'), 'https://example.com/elsewhere');
});

test('codes are single use and need the right secret', async () => {
  const q = new URLSearchParams({ client_id: DEFAULT_CLIENT_ID, response_type: 'code', redirect_uri: 'http://127.0.0.1:1/strava/callback', scope: 'activity:write', state: 's' });
  const r = await fetch(`${base}/oauth/authorize?${q}`, { redirect: 'manual' });
  const code = new URL(r.headers.get('location')).searchParams.get('code');
  const wrong = await form('/oauth/token', { client_id: DEFAULT_CLIENT_ID, client_secret: 'nope', code, grant_type: 'authorization_code' });
  assert.equal(wrong.status, 401);
  const ok = await form('/oauth/token', { client_id: DEFAULT_CLIENT_ID, client_secret: DEFAULT_CLIENT_SECRET, code, grant_type: 'authorization_code' });
  assert.equal(ok.status, 200);
  const again = await form('/oauth/token', { client_id: DEFAULT_CLIENT_ID, client_secret: DEFAULT_CLIENT_SECRET, code, grant_type: 'authorization_code' });
  assert.equal(again.status, 400);
});

test('refresh rotates the refresh token and the old one stops working', async () => {
  const t1 = await connect();
  const r = await form('/oauth/token', { client_id: DEFAULT_CLIENT_ID, client_secret: DEFAULT_CLIENT_SECRET, refresh_token: t1.refresh_token, grant_type: 'refresh_token' });
  assert.equal(r.status, 200);
  const t2 = await r.json();
  assert.notEqual(t2.refresh_token, t1.refresh_token);
  assert.notEqual(t2.access_token, t1.access_token);
  const old = await form('/oauth/token', { client_id: DEFAULT_CLIENT_ID, client_secret: DEFAULT_CLIENT_SECRET, refresh_token: t1.refresh_token, grant_type: 'refresh_token' });
  assert.equal(old.status, 400);
});

test('access tokens expire on the test clock', async () => {
  const t = await connect();
  assert.equal((await status(t.access_token, 1)).status, 404, 'valid token, unknown upload');
  await post('/admin/clock', { advance_s: ACCESS_TOKEN_LIFETIME_S });
  assert.equal((await status(t.access_token, 1)).status, 401);
  const clock = await (await post('/admin/clock', {})).json();
  assert.equal(clock.now, NOW + ACCESS_TOKEN_LIFETIME_S);
});

test('upload: processing, then ready with an activity id', async () => {
  const t = await connect();
  const r = await upload(t.access_token, 'ride-1');
  assert.equal(r.status, 201);
  const u = await r.json();
  assert.equal(u.status, 'Your activity is still being processed.');
  assert.equal(u.activity_id, null);
  assert.equal(u.external_id, 'ride-1');
  const s1 = await (await status(t.access_token, u.id)).json();
  assert.equal(s1.activity_id, null, 'first poll still processing');
  const s2 = await (await status(t.access_token, u.id)).json();
  assert.ok(s2.activity_id > 0);
  assert.equal(s2.status, 'Your activity is ready.');
  const list = await (await fetch(`${base}/admin/uploads`)).json();
  assert.equal(list.length, 1);
  assert.equal(list[0].fit_valid, true);
  assert.equal(list[0].trainer, '1');
  assert.equal(list[0].data_type, 'fit');
  assert.equal(list[0].name, 'Ride');
});

test('duplicates by external_id end in a duplicate error', async () => {
  await post('/admin/config', { processing_polls: 0 });
  const t = await connect();
  const first = await (await upload(t.access_token, 'dup-1')).json();
  const done = await (await status(t.access_token, first.id)).json();
  assert.ok(done.activity_id);
  const second = await (await upload(t.access_token, 'dup-1')).json();
  const s = await (await status(t.access_token, second.id)).json();
  assert.equal(s.activity_id, null);
  assert.match(s.error, new RegExp(`duplicate of activity ${done.activity_id}$`));
});

test('a corrupt FIT ends in a processing error', async () => {
  await post('/admin/config', { processing_polls: 0 });
  const t = await connect();
  const u = await (await upload(t.access_token, 'bad-1', tinyFit({ corruptCrc: true }))).json();
  const s = await (await status(t.access_token, u.id)).json();
  assert.equal(s.error, 'Improperly formatted data.');
  const list = await (await fetch(`${base}/admin/uploads`)).json();
  assert.equal(list[0].fit_valid, false);
  assert.match(list[0].fit_error, /CRC/);
});

test('tokens in the query string or body are refused', async () => {
  const t = await connect();
  const q = await fetch(`${base}/api/v3/athlete?access_token=${t.access_token}`);
  assert.equal(q.status, 401);
  const mp = multipart({ data_type: 'fit', external_id: 'x', access_token: t.access_token }, { name: 'x.fit', data: tinyFit() });
  const b = await fetch(`${base}/api/v3/uploads`, { method: 'POST', headers: { 'Content-Type': mp.type }, body: mp.body });
  assert.equal(b.status, 401);
  const reqs = await (await fetch(`${base}/admin/requests`)).json();
  assert.ok(reqs.some((r) => r.token_in_query));
});

test('upload validation: missing file and bad data_type', async () => {
  const t = await connect();
  const noFile = multipart({ data_type: 'fit', external_id: 'x' }, null);
  const r1 = await fetch(`${base}/api/v3/uploads`, { method: 'POST', headers: { Authorization: `Bearer ${t.access_token}`, 'Content-Type': noFile.type }, body: noFile.body });
  assert.equal(r1.status, 400);
  const r2 = await upload(t.access_token, 'x', tinyFit(), { data_type: 'zip' });
  assert.equal(r2.status, 400);
});

test('injected 401, 429 and 500 responses, counted down', async () => {
  const t = await connect();
  await post('/admin/fault', { route: 'upload', status: 429, count: 2, retry_after: 1 });
  const a = await upload(t.access_token, 'f-1');
  assert.equal(a.status, 429);
  assert.equal(a.headers.get('retry-after'), '1');
  assert.ok(a.headers.get('x-ratelimit-limit'));
  assert.equal((await upload(t.access_token, 'f-1')).status, 429);
  assert.equal((await upload(t.access_token, 'f-1')).status, 201);
  await post('/admin/fault', { route: 'upload_status', status: 500 });
  assert.equal((await status(t.access_token, 1000)).status, 500);
  await post('/admin/fault', { route: '*', status: 401 });
  assert.equal((await fetch(`${base}/api/v3/athlete`, { headers: { Authorization: `Bearer ${t.access_token}` } })).status, 401);
});

test('athlete: ftp and weight only with profile:read_all', async () => {
  const plain = await connect();
  const a1 = await (await fetch(`${base}/api/v3/athlete`, { headers: { Authorization: `Bearer ${plain.access_token}` } })).json();
  assert.equal(a1.ftp, undefined);
  const full = await connect('activity:write,profile:read_all');
  const a2 = await (await fetch(`${base}/api/v3/athlete`, { headers: { Authorization: `Bearer ${full.access_token}` } })).json();
  assert.equal(a2.ftp, 250);
  assert.equal(a2.weight, 72.5);
});

test('revoke needs HTTP Basic client auth and kills the grant', async () => {
  const t = await connect();
  const body = new URLSearchParams({ token: t.refresh_token, token_type_hint: 'refresh_token' }).toString();
  const noAuth = await fetch(`${base}/oauth/revoke`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
  assert.equal(noAuth.status, 401);
  const basic = Buffer.from(`${DEFAULT_CLIENT_ID}:${DEFAULT_CLIENT_SECRET}`).toString('base64');
  const ok = await fetch(`${base}/oauth/revoke`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Authorization: `Basic ${basic}` }, body });
  assert.equal(ok.status, 200);
  assert.equal((await status(t.access_token, 1)).status, 401, 'access token revoked with the grant');
  const refresh = await form('/oauth/token', { client_id: DEFAULT_CLIENT_ID, client_secret: DEFAULT_CLIENT_SECRET, refresh_token: t.refresh_token, grant_type: 'refresh_token' });
  assert.equal(refresh.status, 400);
});

test('deauthorize revokes the grant with the access token in the header', async () => {
  const t = await connect();
  const r = await fetch(base + '/oauth/deauthorize', { method: 'POST', headers: { Authorization: 'Bearer ' + t.access_token } });
  assert.equal(r.status, 200);
  assert.equal((await status(t.access_token, 1)).status, 401);
  assert.equal((await fetch(base + '/oauth/deauthorize', { method: 'POST' })).status, 401);
});

test('the request log records the auth kind and never a token', async () => {
  const t = await connect();
  await upload(t.access_token, 'log-1');
  const raw = await (await fetch(`${base}/admin/requests`)).text();
  assert.ok(!raw.includes(t.access_token));
  assert.ok(!raw.includes(t.refresh_token));
  const reqs = JSON.parse(raw);
  assert.equal(reqs.find((r) => r.route === 'upload').auth, 'bearer');
});

test('CLI: --port=0 prints the port, writes --port-file and serves', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mock-strava-'));
  const portFile = path.join(dir, 'port.txt');
  const child = spawn(process.execPath, [path.join(here, '..', 'server.mjs'), '--port=0', `--port-file=${portFile}`, '--quiet', `--parent-pid=${process.pid}`], { stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    let timer;
    const port = await new Promise((resolve, reject) => {
      let out = '';
      child.stdout.on('data', (d) => {
        out += d;
        const m = /MOCK_STRAVA_PORT (\d+)/.exec(out);
        if (m) resolve(Number(m[1]));
      });
      child.on('exit', (code) => reject(new Error(`exited ${code}`)));
      timer = setTimeout(() => reject(new Error('timeout')), 10000);
    });
    clearTimeout(timer);
    assert.equal(Number(fs.readFileSync(portFile, 'utf8').trim()), port);
    const r = await fetch(`http://127.0.0.1:${port}/admin/state`);
    assert.equal(r.status, 200);
  } finally {
    child.kill();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
