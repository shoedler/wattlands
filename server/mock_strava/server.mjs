#!/usr/bin/env node
// Mock Strava server for tests (BRIEF 3.8, 7.5). Zero-dependency Node on node:http.
//
//   node server/mock_strava/server.mjs [--port=0] [--host=127.0.0.1] [--port-file=<path>]
//        [--client=<id>:<secret>]... [--processing-polls=<n>] [--now=<unix s>]
//        [--parent-pid=<pid>] [--quiet]
//
// One base URL serves both halves of Strava: OAuth under /oauth/* and the API under
// /api/v3/*, so a client pointed at --strava-base=<base> uses <base>/oauth and <base>/api/v3.
// Once listening it prints "MOCK_STRAVA_PORT <port>" and writes the port to --port-file
// (written to a temp name and renamed, so readers never see a partial file).
//
// Endpoints:
//   GET  /oauth/authorize   redirects straight to redirect_uri with code, state and scope
//   POST /oauth/token       grant_type=authorization_code | refresh_token (rotating refresh tokens)
//   POST /oauth/revoke      HTTP Basic client id/secret, token=<refresh or access token>
//   POST /oauth/deauthorize Bearer access token (Strava's older revoke)
//   POST /api/v3/uploads    multipart (file, data_type, trainer, name, description, external_id)
//   GET  /api/v3/uploads/:id
//   GET  /api/v3/athlete    ftp and weight only with the profile:read_all scope
// Admin (tests only):
//   GET  /admin/state                 clock, counters
//   POST /admin/clock    {now?, advance_s?}
//   POST /admin/fault    {route, status, count?, retry_after?}  routes: authorize, token, revoke,
//                         deauthorize, upload, upload_status, athlete, * (every non-admin route). Extras:
//                         {location} answers with that redirect (status 3xx) instead; an authorize
//                         fault with status 403 redirects with error=access_denied; one with
//                         tamper_state: true redirects with a changed state
//   POST /admin/config   {processing_polls?, athlete?}
//   GET  /admin/uploads  every upload with its checks
//   GET  /admin/requests every request: method, path, route, auth kind, token_in_query, status
//   POST /admin/reset    forget everything except clients and config
//
// Access tokens last 6 hours on the mock's clock (real time unless set). API calls accept
// tokens only in the Authorization header; a token in the query or body gets a 401.
// The server never logs tokens, codes or secrets.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { checkFit } from './fit.mjs';
import { boundaryOf, parseMultipart } from './multipart.mjs';

export const DEFAULT_CLIENT_ID = '12345';
export const DEFAULT_CLIENT_SECRET = 'mock-client-secret';
export const ACCESS_TOKEN_LIFETIME_S = 21600;
const MAX_BODY = 32 * 1024 * 1024;
const DATA_TYPES = new Set(['fit', 'fit.gz', 'tcx', 'tcx.gz', 'gpx', 'gpx.gz']);
const STATUS_PROCESSING = 'Your activity is still being processed.';
const STATUS_READY = 'Your activity is ready.';
const STATUS_ERROR = 'There was an error processing your activity.';

const DEFAULT_ATHLETE = { id: 4242, firstname: 'Mock', lastname: 'Rider', ftp: 250, weight: 72.5 };

function token() {
  return crypto.randomBytes(20).toString('hex');
}

function strip(obj) {
  return JSON.parse(JSON.stringify(obj));
}

/**
 * Creates a mock Strava server (not yet listening).
 * @param {{clients?: Record<string,string>, processingPolls?: number, now?: number|null,
 *   log?: (line: string) => void}} [opts]
 */
export function createMockStrava(opts = {}) {
  const config = {
    clients: { ...(opts.clients ?? { [DEFAULT_CLIENT_ID]: DEFAULT_CLIENT_SECRET }) },
    processingPolls: opts.processingPolls ?? 1,
    athlete: { ...DEFAULT_ATHLETE },
  };
  const log = opts.log ?? (() => {});
  let clockNow = opts.now ?? null;
  let clockOffset = 0;
  let state;

  function reset() {
    state = {
      codes: new Map(),
      grants: new Map(),
      access: new Map(),
      refresh: new Map(),
      uploads: new Map(),
      activityByExternal: new Map(),
      faults: [],
      requests: [],
      nextUploadId: 1000,
      nextActivityId: 9000000,
      nextGrant: 1,
    };
  }
  reset();

  const now = () => (clockNow ?? Math.floor(Date.now() / 1000)) + clockOffset;

  function send(res, status, body, headers = {}) {
    const text = body === undefined ? '' : JSON.stringify(body);
    res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(text), ...headers });
    res.end(text);
    return status;
  }

  function authError(res, field = 'access_token') {
    return send(res, 401, {
      message: 'Authorization Error',
      errors: [{ resource: 'Athlete', field, code: 'invalid' }],
    });
  }

  function badRequest(res, resource, field, code = 'invalid') {
    return send(res, 400, { message: 'Bad Request', errors: [{ resource, field, code }] });
  }

  function takeFault(route) {
    const i = state.faults.findIndex((f) => f.count > 0 && (f.route === route || f.route === '*'));
    if (i < 0) return null;
    const f = state.faults[i];
    f.count -= 1;
    if (f.count <= 0) state.faults.splice(i, 1);
    return f;
  }

  function sendFault(res, f) {
    if (f.status === 401) return authError(res);
    if (f.status === 429) {
      const headers = { 'X-RateLimit-Limit': '200,2000', 'X-RateLimit-Usage': '201,500' };
      if (f.retry_after != null) headers['Retry-After'] = String(f.retry_after);
      return send(res, 429, {
        message: 'Rate Limit Exceeded',
        errors: [{ resource: 'Application', field: 'rate limit', code: 'exceeded' }],
      }, headers);
    }
    return send(res, f.status, { message: f.status >= 500 ? 'Internal Server Error' : 'Error', errors: [] });
  }

  function readBody(req) {
    return new Promise((resolve, reject) => {
      const chunks = [];
      let size = 0;
      req.on('data', (c) => {
        size += c.length;
        if (size > MAX_BODY) {
          reject(new Error('body too large'));
          req.destroy();
          return;
        }
        chunks.push(c);
      });
      req.on('end', () => resolve(Buffer.concat(chunks)));
      req.on('error', reject);
    });
  }

  function parseForm(req, body) {
    const ct = req.headers['content-type'] ?? '';
    if (/application\/json/i.test(ct)) {
      try {
        const obj = JSON.parse(body.toString('utf8') || '{}');
        return Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, String(v)]));
      } catch {
        return null;
      }
    }
    return Object.fromEntries(new URLSearchParams(body.toString('utf8')));
  }

  function authKind(req) {
    const h = req.headers.authorization ?? '';
    if (/^Bearer\s+/i.test(h)) return 'bearer';
    if (/^Basic\s+/i.test(h)) return 'basic';
    return null;
  }

  /** The grant behind a valid Bearer access token, or null. */
  function bearerGrant(req) {
    const m = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization ?? '');
    if (!m) return null;
    const a = state.access.get(m[1]);
    if (!a || a.expires_at <= now()) return null;
    const g = state.grants.get(a.grant);
    if (!g || g.revoked) return null;
    return g;
  }

  function issueTokens(grant) {
    const access = token();
    const refresh = token();
    const expires_at = now() + ACCESS_TOKEN_LIFETIME_S;
    state.access.set(access, { grant: grant.id, expires_at });
    if (grant.refresh) state.refresh.delete(grant.refresh);
    grant.refresh = refresh;
    state.refresh.set(refresh, grant.id);
    return { token_type: 'Bearer', access_token: access, refresh_token: refresh, expires_at, expires_in: ACCESS_TOKEN_LIFETIME_S };
  }

  function athleteSummary() {
    const { ftp: _ftp, weight: _weight, ...rest } = config.athlete;
    return { ...rest, resource_state: 2 };
  }

  // --- OAuth ----------------------------------------------------------------------

  function authorize(req, res, url, { deny = false, tamperState = false } = {}) {
    const q = url.searchParams;
    const clientId = q.get('client_id') ?? '';
    const redirect = q.get('redirect_uri') ?? '';
    if (!(clientId in config.clients)) return badRequest(res, 'Application', 'client_id');
    if (q.get('response_type') !== 'code') return badRequest(res, 'Application', 'response_type');
    let target;
    try {
      target = new URL(redirect);
    } catch {
      return badRequest(res, 'Application', 'redirect_uri');
    }
    if (!['127.0.0.1', 'localhost'].includes(target.hostname)) return badRequest(res, 'Application', 'redirect_uri');
    const scopes = (q.get('scope') ?? '').split(',').map((s) => s.trim()).filter(Boolean);
    if (!scopes.includes('activity:write')) return badRequest(res, 'Application', 'scope');
    const st = q.get('state');
    if (st) target.searchParams.set('state', tamperState ? `${st}x` : st);
    if (deny) {
      target.searchParams.set('error', 'access_denied');
    } else {
      const code = token();
      const granted = ['read', ...scopes.filter((s) => s !== 'read')];
      state.codes.set(code, { client_id: clientId, scope: granted.join(','), used: false, expires_at: now() + 600 });
      target.searchParams.set('code', code);
      target.searchParams.set('scope', granted.join(','));
    }
    res.writeHead(302, { Location: target.toString(), 'Content-Length': 0 });
    res.end();
    return 302;
  }

  async function tokenEndpoint(req, res) {
    const form = parseForm(req, await readBody(req));
    if (!form) return badRequest(res, 'Application', 'body');
    const id = form.client_id ?? '';
    if (!(id in config.clients) || config.clients[id] !== form.client_secret) {
      return send(res, 401, { message: 'Bad Request', errors: [{ resource: 'Application', field: 'client_id', code: 'invalid' }] });
    }
    if (form.grant_type === 'authorization_code') {
      const c = state.codes.get(form.code ?? '');
      if (!c || c.used || c.client_id !== id || c.expires_at <= now()) {
        return badRequest(res, 'AuthorizationCode', 'code');
      }
      c.used = true;
      const grant = { id: state.nextGrant++, client_id: id, scope: c.scope, refresh: null, revoked: false };
      state.grants.set(grant.id, grant);
      return send(res, 200, { ...issueTokens(grant), athlete: athleteSummary() });
    }
    if (form.grant_type === 'refresh_token') {
      const gid = state.refresh.get(form.refresh_token ?? '');
      const grant = gid === undefined ? null : state.grants.get(gid);
      if (!grant || grant.revoked || grant.client_id !== id) return badRequest(res, 'RefreshToken', 'refresh_token');
      return send(res, 200, issueTokens(grant));
    }
    return badRequest(res, 'Application', 'grant_type');
  }

  async function revoke(req, res) {
    const body = await readBody(req);
    const m = /^Basic\s+(\S+)$/i.exec(req.headers.authorization ?? '');
    if (!m) return send(res, 401, { message: 'Authorization Error', errors: [{ resource: 'Application', field: 'client_id', code: 'invalid' }] });
    const decoded = Buffer.from(m[1], 'base64').toString('utf8');
    const colon = decoded.indexOf(':');
    const id = decoded.slice(0, colon);
    const secret = decoded.slice(colon + 1);
    if (colon < 0 || !(id in config.clients) || config.clients[id] !== secret) {
      return send(res, 401, { message: 'Authorization Error', errors: [{ resource: 'Application', field: 'client_id', code: 'invalid' }] });
    }
    const form = parseForm(req, body) ?? {};
    const t = form.token ?? '';
    let gid = state.refresh.get(t);
    if (gid === undefined && state.access.has(t)) gid = state.access.get(t).grant;
    const grant = gid === undefined ? null : state.grants.get(gid);
    if (grant && grant.client_id === id) {
      grant.revoked = true;
      if (grant.refresh) state.refresh.delete(grant.refresh);
      for (const [k, v] of state.access) if (v.grant === grant.id) state.access.delete(k);
    }
    // RFC 7009: an unknown token is not an error.
    return send(res, 200, {});
  }

  /** Strava's older endpoint: POST /oauth/deauthorize with the access token (header only here). */
  async function deauthorize(req, res) {
    await readBody(req);
    const grant = bearerGrant(req);
    if (!grant) return authError(res);
    grant.revoked = true;
    if (grant.refresh) state.refresh.delete(grant.refresh);
    for (const [k, v] of state.access) if (v.grant === grant.id) state.access.delete(k);
    return send(res, 200, { access_token: null });
  }

  // --- API ------------------------------------------------------------------------

  function uploadJson(u) {
    return {
      id: u.id, id_str: String(u.id), external_id: u.external_id, error: u.error, status: u.status,
      activity_id: u.activity_id,
    };
  }

  async function createUpload(req, res, grant) {
    const body = await readBody(req);
    const boundary = boundaryOf(req.headers['content-type']);
    if (!boundary) return badRequest(res, 'Upload', 'file');
    let parts;
    try {
      parts = parseMultipart(body, boundary);
    } catch {
      return badRequest(res, 'Upload', 'file');
    }
    if ('access_token' in parts.fields) return authError(res);
    const file = parts.files.file;
    if (!file) return badRequest(res, 'Upload', 'file', 'missing');
    const dataType = parts.fields.data_type ?? '';
    if (!DATA_TYPES.has(dataType)) return badRequest(res, 'Upload', 'data_type');
    const fit = dataType === 'fit' ? checkFit(file.data) : { ok: true, error: null };
    const externalId = parts.fields.external_id || file.filename;
    const duplicateOf = state.activityByExternal.get(externalId) ?? null;
    const u = {
      id: state.nextUploadId++,
      athlete_grant: grant.id,
      external_id: externalId,
      filename: file.filename,
      data_type: dataType,
      trainer: parts.fields.trainer ?? null,
      name: parts.fields.name ?? null,
      description: parts.fields.description ?? null,
      bytes: file.data.length,
      sha256: crypto.createHash('sha256').update(file.data).digest('hex'),
      fit_valid: fit.ok,
      fit_error: fit.error,
      duplicate_of: duplicateOf,
      polls: 0,
      status: STATUS_PROCESSING,
      error: null,
      activity_id: null,
      created_at: now(),
    };
    state.uploads.set(u.id, u);
    return send(res, 201, uploadJson(u));
  }

  function finishUpload(u) {
    if (!u.fit_valid) {
      u.status = STATUS_ERROR;
      u.error = 'Improperly formatted data.';
    } else if (u.duplicate_of !== null || state.activityByExternal.has(u.external_id)) {
      const act = u.duplicate_of ?? state.activityByExternal.get(u.external_id);
      u.status = STATUS_ERROR;
      u.error = `${u.filename} duplicate of activity ${act}`;
    } else {
      u.activity_id = state.nextActivityId++;
      u.status = STATUS_READY;
      state.activityByExternal.set(u.external_id, u.activity_id);
    }
  }

  function uploadStatus(req, res, grant, id) {
    const u = state.uploads.get(Number(id));
    const owner = u ? state.grants.get(u.athlete_grant) : null;
    if (!u || !owner || owner.client_id !== grant.client_id) {
      return send(res, 404, { message: 'Record Not Found', errors: [{ resource: 'Upload', field: 'id', code: 'invalid' }] });
    }
    if (u.status === STATUS_PROCESSING) {
      u.polls += 1;
      if (u.polls > config.processingPolls) finishUpload(u);
    }
    return send(res, 200, uploadJson(u));
  }

  function athlete(req, res, grant) {
    const full = grant.scope.split(',').includes('profile:read_all');
    return send(res, 200, full ? { ...config.athlete, resource_state: 3 } : athleteSummary());
  }

  // --- Admin ------------------------------------------------------------------------

  async function admin(req, res, url) {
    const p = url.pathname;
    const body = req.method === 'POST' ? await readBody(req) : Buffer.alloc(0);
    let json = {};
    if (body.length) {
      try {
        json = JSON.parse(body.toString('utf8'));
      } catch {
        return send(res, 400, { error: 'invalid json' });
      }
    }
    if (p === '/admin/state' && req.method === 'GET') {
      return send(res, 200, {
        now: now(), uploads: state.uploads.size, grants: state.grants.size,
        active_grants: [...state.grants.values()].filter((g) => !g.revoked).length,
        faults: strip(state.faults), processing_polls: config.processingPolls,
      });
    }
    if (p === '/admin/clock' && req.method === 'POST') {
      if (json.now != null) {
        clockNow = Number(json.now);
        clockOffset = 0;
      }
      if (json.advance_s != null) clockOffset += Number(json.advance_s);
      return send(res, 200, { now: now() });
    }
    if (p === '/admin/fault' && req.method === 'POST') {
      const f = {
        route: String(json.route ?? '*'), status: Number(json.status ?? 500), count: Number(json.count ?? 1),
        retry_after: json.retry_after ?? null, location: json.location ?? null, tamper_state: Boolean(json.tamper_state),
      };
      state.faults.push(f);
      return send(res, 200, { faults: strip(state.faults) });
    }
    if (p === '/admin/config' && req.method === 'POST') {
      if (json.processing_polls != null) config.processingPolls = Number(json.processing_polls);
      if (json.athlete) config.athlete = { ...config.athlete, ...json.athlete };
      return send(res, 200, { processing_polls: config.processingPolls, athlete: config.athlete });
    }
    if (p === '/admin/uploads' && req.method === 'GET') {
      return send(res, 200, [...state.uploads.values()].map((u) => {
        const { athlete_grant: _g, ...rest } = u;
        return rest;
      }));
    }
    if (p === '/admin/requests' && req.method === 'GET') return send(res, 200, state.requests);
    if (p === '/admin/reset' && req.method === 'POST') {
      reset();
      clockNow = opts.now ?? null;
      clockOffset = 0;
      return send(res, 200, { ok: true });
    }
    return send(res, 404, { error: 'unknown admin route' });
  }

  // --- Routing -----------------------------------------------------------------------

  function routeOf(method, pathname) {
    if (method === 'GET' && pathname === '/oauth/authorize') return 'authorize';
    if (method === 'POST' && pathname === '/oauth/token') return 'token';
    if (method === 'POST' && pathname === '/oauth/revoke') return 'revoke';
    if (method === 'POST' && pathname === '/oauth/deauthorize') return 'deauthorize';
    if (method === 'POST' && pathname === '/api/v3/uploads') return 'upload';
    if (method === 'GET' && /^\/api\/v3\/uploads\/\d+$/.test(pathname)) return 'upload_status';
    if (method === 'GET' && pathname === '/api/v3/athlete') return 'athlete';
    return null;
  }

  async function handle(req, res) {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname.startsWith('/admin/')) return admin(req, res, url);
    const route = routeOf(req.method, url.pathname);
    const entry = {
      t: now(), method: req.method, path: url.pathname, route, auth: authKind(req),
      token_in_query: url.searchParams.has('access_token') || url.searchParams.has('refresh_token'),
      status: 0,
    };
    state.requests.push(entry);
    log(`${req.method} ${url.pathname}`);
    if (!route) return (entry.status = send(res, 404, { message: 'Record Not Found', errors: [] }));
    const fault = takeFault(route);
    if (fault && route === 'authorize' && fault.status === 403) {
      // The rider pressed Cancel: Strava redirects with error=access_denied.
      return (entry.status = authorize(req, res, url, { deny: true }));
    }
    if (fault && route === 'authorize' && fault.tamper_state) {
      // A forged callback: the state no longer matches the one the client sent.
      return (entry.status = authorize(req, res, url, { tamperState: true }));
    }
    if (fault && fault.location) {
      // A redirect somewhere else (tests that the network lock checks every hop).
      res.writeHead(fault.status, { Location: fault.location, 'Content-Length': 0 });
      res.end();
      return (entry.status = fault.status);
    }
    if (fault) {
      if (req.method === 'POST') await readBody(req);
      return (entry.status = sendFault(res, fault));
    }
    switch (route) {
      case 'authorize':
        return (entry.status = authorize(req, res, url));
      case 'token':
        return (entry.status = await tokenEndpoint(req, res));
      case 'revoke':
        return (entry.status = await revoke(req, res));
      case 'deauthorize':
        return (entry.status = await deauthorize(req, res));
      default: {
        if (entry.token_in_query) {
          if (req.method === 'POST') await readBody(req);
          return (entry.status = authError(res));
        }
        const grant = bearerGrant(req);
        if (!grant) {
          if (req.method === 'POST') await readBody(req);
          return (entry.status = authError(res));
        }
        if (route === 'upload') {
          if (!grant.scope.split(',').includes('activity:write')) {
            await readBody(req);
            return (entry.status = authError(res, 'activity:write'));
          }
          return (entry.status = await createUpload(req, res, grant));
        }
        if (route === 'upload_status') return (entry.status = uploadStatus(req, res, grant, url.pathname.split('/').pop()));
        return (entry.status = athlete(req, res, grant));
      }
    }
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((err) => {
      if (!res.headersSent) send(res, 500, { message: 'mock error', error: String(err?.message ?? err) });
      else res.destroy();
    });
  });

  return {
    server,
    config,
    get state() {
      return state;
    },
    now,
    /** Listens and resolves with the port. */
    listen(port = 0, host = '127.0.0.1') {
      return new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(port, host, () => {
          server.off('error', reject);
          resolve(server.address().port);
        });
      });
    },
    close() {
      return new Promise((resolve) => {
        server.closeAllConnections?.();
        server.close(() => resolve());
      });
    },
  };
}

function parseArgs(argv) {
  const out = { clients: {}, port: 0, host: '127.0.0.1', portFile: null, processingPolls: 1, now: null, parentPid: null, quiet: false };
  for (const a of argv) {
    const m = /^--([^=]+)(?:=(.*))?$/.exec(a);
    if (!m) throw new Error(`unknown argument ${a}`);
    const [, k, v] = m;
    switch (k) {
      case 'port': out.port = Number(v); break;
      case 'host': out.host = v; break;
      case 'port-file': out.portFile = v; break;
      case 'processing-polls': out.processingPolls = Number(v); break;
      case 'now': out.now = Number(v); break;
      case 'parent-pid': out.parentPid = Number(v); break;
      case 'quiet': out.quiet = true; break;
      case 'client': {
        const c = (v ?? '').indexOf(':');
        if (c <= 0) throw new Error('--client=<id>:<secret>');
        out.clients[v.slice(0, c)] = v.slice(c + 1);
        break;
      }
      default: throw new Error(`unknown flag --${k}`);
    }
  }
  if (!Object.keys(out.clients).length) out.clients[DEFAULT_CLIENT_ID] = DEFAULT_CLIENT_SECRET;
  return out;
}

async function main() {
  let args;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (err) {
    process.stderr.write(`mock_strava: ${err.message}\n`);
    process.exit(2);
  }
  const mock = createMockStrava({
    clients: args.clients, processingPolls: args.processingPolls, now: args.now,
    log: args.quiet ? () => {} : (line) => process.stdout.write(`mock_strava: ${line}\n`),
  });
  const port = await mock.listen(args.port, args.host);
  if (args.portFile) {
    const tmp = `${args.portFile}.${process.pid}.tmp`;
    fs.mkdirSync(path.dirname(path.resolve(args.portFile)), { recursive: true });
    fs.writeFileSync(tmp, `${port}\n`);
    fs.renameSync(tmp, args.portFile);
  }
  process.stdout.write(`MOCK_STRAVA_PORT ${port}\n`);
  process.stdout.write(`mock_strava listening on http://${args.host}:${port}\n`);
  if (args.parentPid) {
    // Exit with the process that started us (a GUT run or a harness), so no mock outlives it.
    setInterval(() => {
      try {
        process.kill(args.parentPid, 0);
      } catch {
        process.exit(0);
      }
    }, 1000);
  }
  const stop = () => mock.close().then(() => process.exit(0));
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
