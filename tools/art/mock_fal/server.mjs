#!/usr/bin/env node
// tools/art/mock_fal: a local stand-in for fal.ai, for tests only (BRIEF 3.10, 7.6). Zero dependencies.
//
//   node tools/art/mock_fal/server.mjs [--port=0] [--host=127.0.0.1]
//
// prints "MOCK_FAL_PORT=<port>" and "mock_fal listening on <url>", then serves until killed.
// Tests usually import startMockFal() instead and talk to it in-process.
//
// It mirrors the parts of fal that tools/art/generate.mjs uses:
//   POST /<owner>/<app>/<path...>               queue submit (fal's limits checked: 422 on bad input)
//   GET  /<owner>/<app>/requests/<id>/status    IN_QUEUE -> IN_PROGRESS -> COMPLETED (error fields on failure)
//   GET  /<owner>/<app>/requests/<id>           the result: {images: [{url, content_type, width, height, ...}]}
//   PUT  /<owner>/<app>/requests/<id>/cancel
//   GET  /files/<id>.png                        the image: a deterministic shape honouring size and background
//   GET  /v1/models/requests/by-endpoint        request history (endpoint_id, start, end, status, request_id,
//                                               expand=payloads, limit, cursor), newest first
// and an admin API for tests:
//   GET  /_admin/state      counters, every request (no image bytes), the request log, the billing ledger
//   POST /_admin/config     {polls_to_complete, billed_usd, report_billed, fail_downloads, fail_download_mode,
//                            fail_500: {submit, status, result, listing, download}, model_errors, require_auth}
//   POST /_admin/requests   insert a finished request {endpoint, input, started_at?, ended_at?, request_id?}
//   POST /_admin/reset      forget everything
import crypto from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { encodePng } from '../lib/png.mjs';

export const MOCK_PRICE_USD = 0.07;

/** fal's stated limits for gpt-image-2.5 custom sizes; kept here independently of endpoints.json. */
export const FAL_LIMITS = { multiple: 16, min_pixels: 655360, max_pixels: 8294400, max_edge: 3840, max_aspect: 3 };
const QUALITIES = ['auto', 'low', 'medium', 'high', 'xhigh', 'max'];
const BACKGROUNDS = ['auto', 'transparent', 'opaque'];
const FORMATS = ['jpeg', 'png', 'webp'];

function defaultConfig() {
  return {
    polls_to_complete: 2,
    billed_usd: MOCK_PRICE_USD,
    report_billed: false,
    fail_downloads: 0,
    fail_download_mode: 'http500',
    fail_500: { submit: 0, status: 0, result: 0, listing: 0, download: 0 },
    model_errors: 0,
    require_auth: true,
  };
}

function hashBytes(text) {
  return crypto.createHash('sha256').update(text).digest();
}

/**
 * Renders the mock result: RGBA8 pixels of width x height. Transparent requests get a shape on a
 * transparent canvas (an outlined ellipse with a stripe), opaque ones a full scene. Colours and
 * placement come from a hash of `seedText`, so the same input always gives the same image.
 */
export function renderMockImage(width, height, background, seedText) {
  const h = hashBytes(seedText);
  const px = new Uint8Array(width * height * 4);
  const body = [64 + (h[0] % 160), 64 + (h[1] % 160), 64 + (h[2] % 160)];
  const accent = [255 - body[0], 255 - body[1], 128 + (h[3] % 120)];
  const dark = [16 + (h[4] % 24), 16 + (h[5] % 24), 32 + (h[6] % 32)];
  const set = (x, y, c, a = 255) => {
    const o = (y * width + x) * 4;
    px[o] = c[0];
    px[o + 1] = c[1];
    px[o + 2] = c[2];
    px[o + 3] = a;
  };
  if (background === 'opaque') {
    const sky = [80 + (h[7] % 100), 120 + (h[8] % 100), 200 + (h[9] % 55)];
    const ground = [90 + (h[10] % 80), 70 + (h[11] % 60), 40 + (h[12] % 40)];
    const horizon = Math.floor(height * 0.7);
    const bx0 = Math.floor(width * (0.3 + (h[13] % 20) / 100));
    const bx1 = bx0 + Math.floor(width * 0.25);
    const by0 = Math.floor(height * 0.35);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        let c;
        if (y >= horizon) c = ground;
        else if (x >= bx0 && x < bx1 && y >= by0) c = dark;
        else {
          const t = y / horizon;
          c = [Math.round(sky[0] * (1 - t * 0.4)), Math.round(sky[1] * (1 - t * 0.3)), sky[2]];
        }
        set(x, y, c);
      }
    }
    return px;
  }
  // Transparent: an ellipse in a box that leaves margins on every side (so trimming matters).
  const bw = width * 0.6;
  const bh = height * 0.7;
  const x0 = width * (0.1 + (h[14] % 20) / 100);
  const y0 = height * 0.12;
  const cx = x0 + bw / 2;
  const cy = y0 + bh / 2;
  const rx = bw / 2;
  const ry = bh / 2;
  const edge = Math.max(2, Math.min(width, height) / 60);
  for (let y = Math.floor(y0); y < Math.ceil(y0 + bh); y++) {
    for (let x = Math.floor(x0); x < Math.ceil(x0 + bw); x++) {
      const dx = (x + 0.5 - cx) / rx;
      const dy = (y + 0.5 - cy) / ry;
      const d = dx * dx + dy * dy;
      if (d > 1) continue;
      const inner = 1 - (edge / Math.min(rx, ry)) * 2;
      let c = body;
      if (d > inner) c = dark;
      else if (Math.abs(y + 0.5 - cy) < bh / 8) c = accent;
      set(x, y, c);
    }
  }
  return px;
}

function validateInput(input) {
  const errs = [];
  const bad = (loc, msg) => errs.push({ loc: ['body', loc], msg, type: 'value_error' });
  if (!input || typeof input !== 'object' || Array.isArray(input)) return [{ loc: ['body'], msg: 'expected an object', type: 'type_error' }];
  if (typeof input.prompt !== 'string' || input.prompt.trim() === '') bad('prompt', 'field required');
  const s = input.image_size;
  if (s !== undefined) {
    if (typeof s !== 'object' || !Number.isInteger(s.width) || !Number.isInteger(s.height)) {
      bad('image_size', 'expected {width, height} integers');
    } else {
      const { width: w, height: hh } = s;
      const L = FAL_LIMITS;
      if (w % L.multiple || hh % L.multiple) bad('image_size', 'Concrete sizes must have both dimensions as multiples of 16');
      if (w > L.max_edge || hh > L.max_edge) bad('image_size', `max edge ${L.max_edge}px`);
      if (w * hh < L.min_pixels || w * hh > L.max_pixels) bad('image_size', `total pixels between ${L.min_pixels} and ${L.max_pixels}`);
      if (Math.max(w / hh, hh / w) > L.max_aspect) bad('image_size', 'aspect ratio <= 3:1');
    }
  }
  if (input.background !== undefined && !BACKGROUNDS.includes(input.background)) bad('background', `expected one of ${BACKGROUNDS.join(', ')}`);
  if (input.quality !== undefined && !QUALITIES.includes(input.quality)) bad('quality', `expected one of ${QUALITIES.join(', ')}`);
  if (input.output_format !== undefined && !FORMATS.includes(input.output_format)) bad('output_format', `expected one of ${FORMATS.join(', ')}`);
  if (input.num_images !== undefined && !(Number.isInteger(input.num_images) && input.num_images >= 1 && input.num_images <= 4)) {
    bad('num_images', 'expected an integer 1..4');
  }
  return errs;
}

/** Starts the mock. Returns {url, port, state, configure(cfg), reset(), close()}. */
export async function startMockFal({ port = 0, host = '127.0.0.1', config = {} } = {}) {
  const state = {
    seq: 0,
    config: { ...defaultConfig(), ...config, fail_500: { ...defaultConfig().fail_500, ...(config.fail_500 ?? {}) } },
    requests: new Map(),
    log: [],
    counts: { submit: 0, status: 0, result: 0, download: 0, listing: 0, cancel: 0 },
    billed_total_usd: 0,
  };
  let origin = '';

  const newId = () => {
    state.seq += 1;
    return `01a14c16-0000-7000-8000-${state.seq.toString(16).padStart(12, '0')}`;
  };

  const resultBody = (r) => {
    const { width, height } = r.size;
    const body = {
      images: [
        {
          url: `${origin}/files/${r.id}.png`,
          content_type: 'image/png',
          file_name: `${r.id}.png`,
          file_size: r.png ? r.png.length : null,
          width,
          height,
        },
      ],
      prompt: r.input.prompt,
      seed: hashBytes(r.id).readUInt32BE(0),
    };
    if (state.config.report_billed && typeof r.billed_usd === 'number') body.billing = { cost_total: r.billed_usd, currency: 'USD' };
    return body;
  };

  const complete = (r) => {
    if (r.status === 'COMPLETED') return;
    r.status = 'COMPLETED';
    r.ended_at = new Date().toISOString();
    if (r.error) {
      r.status_code = 500;
      return;
    }
    r.status_code = 200;
    r.billed_usd = typeof state.config.billed_usd === 'number' ? state.config.billed_usd : MOCK_PRICE_USD;
    state.billed_total_usd = Math.round((state.billed_total_usd + r.billed_usd) * 10000) / 10000;
  };

  const pngFor = (r) => {
    if (!r.png) {
      const { width, height } = r.size;
      const bg = r.input.background === 'opaque' ? 'opaque' : 'transparent';
      r.png = encodePng(width, height, renderMockImage(width, height, bg, `${r.endpoint}|${r.input.prompt}|${width}x${height}`), { level: 1 });
    }
    return r.png;
  };

  const take500 = (kind) => {
    if (state.config.fail_500[kind] > 0) {
      state.config.fail_500[kind] -= 1;
      return true;
    }
    return false;
  };

  const send = (res, code, body, headers = {}) => {
    const buf = Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body));
    res.writeHead(code, { 'Content-Type': Buffer.isBuffer(body) ? 'image/png' : 'application/json', 'Content-Length': buf.length, ...headers });
    res.end(buf);
  };

  const publicRequest = (r) => {
    const { png, ...rest } = r;
    return { ...rest, png_bytes: png ? png.length : null };
  };

  const listing = (u, res) => {
    const q = u.searchParams;
    const eps = q.getAll('endpoint_id').flatMap((v) => v.split(',')).filter(Boolean);
    if (eps.length === 0) return send(res, 400, { error: { type: 'validation_error', message: 'endpoint_id is required' } });
    const start = q.get('start') ? Date.parse(q.get('start')) : Date.now() - 24 * 3600 * 1000;
    const end = q.get('end') ? Date.parse(q.get('end')) : Infinity;
    const status = q.get('status');
    const rid = q.get('request_id');
    const payloads = q.getAll('expand').flatMap((v) => v.split(',')).includes('payloads');
    const limit = Math.min(100, Math.max(1, Number(q.get('limit') ?? 50) || 50));
    const offset = q.get('cursor') ? Number(Buffer.from(q.get('cursor'), 'base64').toString('utf8')) || 0 : 0;
    let items = [...state.requests.values()].filter((r) => {
      if (!eps.includes(r.endpoint)) return false;
      if (rid && r.id !== rid) return false;
      const t = Date.parse(r.started_at);
      if (t < start || t >= end) return false;
      if (status === 'success' && r.status_code !== 200) return false;
      if (status === 'error' && !(r.status_code >= 500)) return false;
      if (status === 'user_error' && !(r.status_code >= 400 && r.status_code < 500)) return false;
      return true;
    });
    items.sort((a, b) => (Date.parse(b.ended_at ?? 0) || 0) - (Date.parse(a.ended_at ?? 0) || 0) || (a.id < b.id ? 1 : -1));
    const page = items.slice(offset, offset + limit);
    const next = offset + limit < items.length ? Buffer.from(String(offset + limit)).toString('base64') : null;
    items = page.map((r) => {
      const it = {
        request_id: r.id,
        endpoint_id: r.endpoint,
        started_at: r.started_at,
        sent_at: r.started_at,
        ended_at: r.ended_at ?? null,
        status_code: r.status_code ?? null,
        duration: r.ended_at ? (Date.parse(r.ended_at) - Date.parse(r.started_at)) / 1000 : null,
      };
      if (payloads) {
        it.json_input = r.input;
        it.json_output = r.status_code === 200 ? resultBody(r) : null;
      }
      return it;
    });
    return send(res, 200, { items, next_cursor: next, has_more: next !== null });
  };

  const handler = async (req, res) => {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const raw = Buffer.concat(chunks).toString('utf8');
    const u = new URL(req.url, origin);
    const parts = u.pathname.split('/').filter(Boolean);
    state.log.push({
      method: req.method,
      path: u.pathname,
      query: u.search,
      authorization: req.headers.authorization ?? null,
      headers: JSON.stringify(req.headers),
      body: raw,
      at: new Date().toISOString(),
    });
    const authed = !state.config.require_auth || /^Key \S+/.test(req.headers.authorization ?? '');
    let json = null;
    if (raw !== '') {
      try {
        json = JSON.parse(raw);
      } catch {
        if (req.method === 'POST') return send(res, 400, { detail: 'body is not JSON' });
      }
    }

    // Admin API.
    if (parts[0] === '_admin') {
      if (req.method === 'GET' && parts[1] === 'state') {
        return send(res, 200, {
          counts: state.counts,
          config: state.config,
          billed_total_usd: state.billed_total_usd,
          requests: [...state.requests.values()].map(publicRequest),
          log: state.log,
        });
      }
      if (req.method === 'POST' && parts[1] === 'config') {
        const cfg = json ?? {};
        state.config = { ...state.config, ...cfg, fail_500: { ...state.config.fail_500, ...(cfg.fail_500 ?? {}) } };
        return send(res, 200, { config: state.config });
      }
      if (req.method === 'POST' && parts[1] === 'reset') {
        api.reset();
        return send(res, 200, { ok: true });
      }
      if (req.method === 'POST' && parts[1] === 'requests') {
        const r = api.insert(json ?? {});
        return send(res, 200, { request_id: r.id });
      }
      return send(res, 404, { detail: 'unknown admin route' });
    }

    // Image downloads (no auth, like fal's CDN).
    if (req.method === 'GET' && parts[0] === 'files' && parts.length === 2) {
      state.counts.download += 1;
      const r = state.requests.get(parts[1].replace(/\.png$/, ''));
      if (!r || r.status !== 'COMPLETED' || r.error) return send(res, 404, { detail: 'file not found' });
      if (state.config.fail_downloads > 0) {
        state.config.fail_downloads -= 1;
        if (state.config.fail_download_mode === 'reset') {
          req.socket.destroy();
          return undefined;
        }
        return send(res, 500, { detail: 'mock download failure' });
      }
      if (take500('download')) return send(res, 500, { detail: 'mock 500' });
      return send(res, 200, pngFor(r));
    }

    if (!authed) return send(res, 401, { detail: 'Missing or invalid authorization header (expected "Key <key>")' });

    // Request history.
    if (req.method === 'GET' && u.pathname === '/v1/models/requests/by-endpoint') {
      state.counts.listing += 1;
      if (take500('listing')) return send(res, 500, { error: { type: 'server_error', message: 'mock 500' } });
      return listing(u, res);
    }

    // Queue: status, result, cancel.
    if (parts.length >= 4 && parts[2] === 'requests') {
      const r = state.requests.get(parts[3]);
      const app = `${parts[0]}/${parts[1]}`;
      if (!r || r.app !== app) return send(res, 404, { detail: 'Request not found' });
      if (req.method === 'GET' && parts.length === 5 && parts[4] === 'status') {
        state.counts.status += 1;
        if (take500('status')) return send(res, 500, { detail: 'mock 500' });
        if (r.status !== 'COMPLETED') {
          r.polls += 1;
          if (r.polls >= state.config.polls_to_complete) complete(r);
          else r.status = 'IN_PROGRESS';
        }
        const base = { status: r.status, request_id: r.id, response_url: `${origin}/${app}/requests/${r.id}` };
        if (r.status === 'IN_QUEUE') return send(res, 200, { ...base, queue_position: 0 });
        if (r.status === 'IN_PROGRESS') return send(res, 200, { ...base, logs: [] });
        const done = { ...base, logs: [], metrics: { inference_time: 1.25 } };
        if (r.error) Object.assign(done, { error: r.error, error_type: 'internal_error' });
        return send(res, 200, done);
      }
      if (req.method === 'GET' && parts.length === 4) {
        state.counts.result += 1;
        if (take500('result')) return send(res, 500, { detail: 'mock 500' });
        if (r.status !== 'COMPLETED') return send(res, 400, { detail: 'Request is still in progress' });
        if (r.error) return send(res, 500, { detail: r.error });
        return send(res, 200, resultBody(r));
      }
      if (req.method === 'PUT' && parts.length === 5 && parts[4] === 'cancel') {
        state.counts.cancel += 1;
        if (r.status === 'COMPLETED') return send(res, 400, { status: 'ALREADY_COMPLETED' });
        r.status = 'COMPLETED';
        r.error = 'cancelled';
        r.ended_at = new Date().toISOString();
        r.status_code = 499;
        return send(res, 200, { status: 'OK' });
      }
      return send(res, 405, { detail: 'Method not allowed' });
    }

    // Queue submit.
    if (req.method === 'POST' && parts.length >= 2) {
      state.counts.submit += 1;
      if (take500('submit')) return send(res, 500, { detail: 'mock 500' });
      const errs = validateInput(json);
      if (errs.length > 0) return send(res, 422, { detail: errs });
      const r = api.create(parts.join('/'), json);
      const app = r.app;
      return send(res, 200, {
        request_id: r.id,
        response_url: `${origin}/${app}/requests/${r.id}`,
        status_url: `${origin}/${app}/requests/${r.id}/status`,
        cancel_url: `${origin}/${app}/requests/${r.id}/cancel`,
        queue_position: 0,
      });
    }
    return send(res, 404, { detail: 'Not found' });
  };

  const api = {
    state,
    url: '',
    port: 0,
    create(endpoint, input, { id = null, started_at = null, may_fail = true } = {}) {
      const s = input.image_size && typeof input.image_size === 'object' ? input.image_size : { width: 1024, height: 768 };
      const r = {
        id: id ?? newId(),
        endpoint,
        app: endpoint.split('/').slice(0, 2).join('/'),
        input,
        size: { width: s.width, height: s.height },
        status: 'IN_QUEUE',
        polls: 0,
        error: null,
        started_at: started_at ?? new Date().toISOString(),
        ended_at: null,
        status_code: null,
        billed_usd: null,
        png: null,
      };
      if (may_fail && state.config.model_errors > 0) {
        state.config.model_errors -= 1;
        r.error = 'mock model error';
      }
      state.requests.set(r.id, r);
      return r;
    },
    /** A finished, billed request (e.g. from an earlier run whose record was lost). */
    insert({ endpoint, input, started_at = null, ended_at = null, request_id = null, billed_usd = MOCK_PRICE_USD }) {
      const r = api.create(endpoint, input, { id: request_id, started_at: started_at ?? ended_at, may_fail: false });
      r.status = 'COMPLETED';
      r.ended_at = ended_at ?? new Date().toISOString();
      r.status_code = 200;
      r.billed_usd = billed_usd;
      state.billed_total_usd = Math.round((state.billed_total_usd + billed_usd) * 10000) / 10000;
      return r;
    },
    configure(cfg) {
      state.config = { ...state.config, ...cfg, fail_500: { ...state.config.fail_500, ...(cfg.fail_500 ?? {}) } };
    },
    reset() {
      state.seq = 0;
      state.requests.clear();
      state.log.length = 0;
      for (const k of Object.keys(state.counts)) state.counts[k] = 0;
      state.billed_total_usd = 0;
      state.config = defaultConfig();
    },
    close() {
      return new Promise((resolve) => {
        server.closeAllConnections?.();
        server.close(() => resolve());
      });
    },
  };

  const server = http.createServer((req, res) => {
    handler(req, res).catch((err) => {
      if (!res.headersSent) send(res, 500, { detail: `mock crashed: ${err.message}` });
    });
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, resolve);
  });
  api.port = server.address().port;
  origin = `http://${host.includes(':') ? `[${host}]` : host}:${api.port}`;
  api.url = origin;
  api.server = server;
  return api;
}

function isMain() {
  return process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isMain()) {
  let port = 0;
  let host = '127.0.0.1';
  for (const a of process.argv.slice(2)) {
    if (a.startsWith('--port=')) port = Number(a.slice(7));
    else if (a.startsWith('--host=')) host = a.slice(7);
    else {
      process.stderr.write(`mock_fal: unknown argument ${a}\nusage: node tools/art/mock_fal/server.mjs [--port=0] [--host=127.0.0.1]\n`);
      process.exit(2);
    }
  }
  if (!['127.0.0.1', 'localhost', '::1'].includes(host)) {
    process.stderr.write('mock_fal: --host must be a loopback address\n');
    process.exit(2);
  }
  const mock = await startMockFal({ port, host });
  process.stdout.write(`MOCK_FAL_PORT=${mock.port}\nmock_fal listening on ${mock.url}\n`);
  const stop = () => mock.close().then(() => process.exit(0));
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}
