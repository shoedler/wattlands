// fal client for generate.mjs: queue API (submit, status, result), image download and the request
// history listing (GET /v1/models/requests/by-endpoint?expand=payloads). It talks only to fal's hosts
// (or, with --mock, only to the mock's origin), sends the key only to queue.fal.run and api.fal.ai,
// never to an image host, and redacts the key from every error it raises.

export const QUEUE_BASE = 'https://queue.fal.run';
export const API_BASE = 'https://api.fal.ai';
export const AUTH_HOSTS = new Set(['queue.fal.run', 'api.fal.ai']);
const FAL_DOMAINS = ['fal.run', 'fal.ai', 'fal.media'];
export const MOCK_HOSTS = new Set(['127.0.0.1', 'localhost', '[::1]', '::1']);

export class FalError extends Error {
  /** `refused`: the client itself refused (a host it may not contact, or the key to a non-API host). */
  constructor(message, { status = 0, body = '', refused = false } = {}) {
    super(message);
    this.status = status;
    this.body = body;
    this.refused = refused;
  }
}

export function isFalHost(hostname) {
  const h = hostname.toLowerCase();
  return FAL_DOMAINS.some((d) => h === d || h.endsWith(`.${d}`));
}

/** Throws unless `url` is an http(s) URL on a loopback host (the only place --mock may point). */
export function checkMockUrl(url) {
  let u;
  try {
    u = new URL(url);
  } catch {
    throw new Error(`--mock: "${url}" is not a URL`);
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') throw new Error(`--mock: "${url}" must be http or https`);
  if (!MOCK_HOSTS.has(u.hostname)) throw new Error(`--mock: "${url}" must point at a loopback host (127.0.0.1, localhost or [::1])`);
  return u.origin;
}

export class FalClient {
  /**
   * @param {object} o
   * @param {string|null} o.mockOrigin loopback origin of tools/art/mock_fal, or null for real fal
   * @param {string|null} o.key the fal key (real mode only; never used with a mock)
   * @param {Function} [o.fetchImpl] fetch implementation (tests inject one)
   * @param {Function} [o.redact] text -> text with the key removed
   * @param {number} [o.timeoutMs] per-request timeout
   */
  constructor({ mockOrigin = null, key = null, fetchImpl = globalThis.fetch, redact = (s) => String(s), timeoutMs = 120000 }) {
    this.mock = mockOrigin;
    this.key = mockOrigin ? null : key;
    this.fetch = fetchImpl;
    this.redact = redact;
    this.timeoutMs = timeoutMs;
    this.queueBase = mockOrigin ?? QUEUE_BASE;
    this.apiBase = mockOrigin ?? API_BASE;
  }

  /** True when this client may contact `url` at all. */
  allowed(url) {
    let u;
    try {
      u = new URL(url);
    } catch {
      return false;
    }
    if (this.mock) return u.origin === this.mock;
    return u.protocol === 'https:' && isFalHost(u.hostname);
  }

  _authHeader(u) {
    if (this.mock) return 'Key mock';
    if (!AUTH_HOSTS.has(u.hostname.toLowerCase())) {
      throw new FalError(`refusing to send the fal key to ${u.hostname} (only ${[...AUTH_HOSTS].join(' and ')})`, { refused: true });
    }
    return `Key ${this.key}`;
  }

  async _request(method, url, { json = undefined, auth = true, as = 'json' } = {}) {
    let target = url;
    let res;
    let u;
    // Redirects are followed by hand, at most 3, and only to hosts this client may contact.
    for (let hop = 0; ; hop++) {
      if (!this.allowed(target)) {
        throw new FalError(
          `refusing to contact ${this.redact(target)}: ${this.mock ? `only the mock at ${this.mock}` : "only fal's hosts"} may be contacted`,
          { refused: true },
        );
      }
      u = new URL(target);
      const headers = { Accept: as === 'json' ? 'application/json' : '*/*' };
      if (auth) headers.Authorization = this._authHeader(u);
      if (json !== undefined) headers['Content-Type'] = 'application/json';
      try {
        res = await this.fetch(target, {
          method,
          headers,
          body: json === undefined ? undefined : JSON.stringify(json),
          redirect: 'manual',
          signal: AbortSignal.timeout(this.timeoutMs),
        });
      } catch (err) {
        const cause = err?.cause?.code ?? err?.cause?.message ?? err?.message ?? String(err);
        throw new FalError(this.redact(`${method} ${u.origin}${u.pathname} failed: ${cause}`));
      }
      const loc = res.headers?.get?.('location');
      if (res.status >= 300 && res.status < 400 && loc && method === 'GET' && hop < 3) {
        await res.arrayBuffer().catch(() => null);
        target = new URL(loc, target).href;
        continue;
      }
      break;
    }
    const buf = Buffer.from(await res.arrayBuffer());
    if (!res.ok) {
      const text = this.redact(buf.toString('utf8').slice(0, 300));
      throw new FalError(this.redact(`${method} ${u.origin}${u.pathname}: HTTP ${res.status} ${text}`), { status: res.status, body: text });
    }
    if (as === 'buffer') return { status: res.status, body: buf };
    try {
      return { status: res.status, body: JSON.parse(buf.toString('utf8')) };
    } catch {
      throw new FalError(this.redact(`${method} ${u.origin}${u.pathname}: response is not JSON`), { status: res.status });
    }
  }

  /** POST https://queue.fal.run/<endpoint>. Returns {request_id, status_url, response_url, ...}. */
  async submit(endpoint, input) {
    const { body } = await this._request('POST', `${this.queueBase}/${endpoint}`, { json: input });
    if (!body || typeof body.request_id !== 'string') throw new FalError('submit: response has no request_id');
    const appBase = `${this.queueBase}/${endpoint.split('/').slice(0, 2).join('/')}/requests/${body.request_id}`;
    return {
      request_id: body.request_id,
      status_url: typeof body.status_url === 'string' ? body.status_url : `${appBase}/status`,
      response_url: typeof body.response_url === 'string' ? body.response_url : appBase,
      queue_position: body.queue_position ?? null,
    };
  }

  async status(statusUrl) {
    return (await this._request('GET', statusUrl)).body;
  }

  async result(responseUrl) {
    return (await this._request('GET', responseUrl)).body;
  }

  /** Downloads a result image without credentials. */
  async download(url) {
    return (await this._request('GET', url, { auth: false, as: 'buffer' })).body;
  }

  /**
   * Successful requests of `endpoint` that started at or after `startIso`, with their payloads,
   * newest pages first, following next_cursor up to maxPages pages.
   */
  async listRequests(endpoint, startIso, { maxPages = 10, limit = 100 } = {}) {
    const items = [];
    let cursor = null;
    for (let page = 0; page < maxPages; page++) {
      const q = new URLSearchParams({ endpoint_id: endpoint, expand: 'payloads', status: 'success', start: startIso, limit: String(limit) });
      if (cursor) q.set('cursor', cursor);
      const { body } = await this._request('GET', `${this.apiBase}/v1/models/requests/by-endpoint?${q}`);
      if (Array.isArray(body?.items)) items.push(...body.items);
      cursor = body?.next_cursor ?? null;
      if (!cursor) break;
    }
    return items;
  }
}

/**
 * A billed amount in USD if a fal response reports one, else null. fal documents no per-request
 * cost today; this reads `cost_total` (the name fal's usage API uses) at the top level or under
 * `billing` or `metrics`, which is where tools/art/mock_fal reports it.
 */
export function extractBilledUsd(...bodies) {
  for (const b of bodies) {
    if (!b || typeof b !== 'object') continue;
    for (const v of [b.billing?.cost_total, b.metrics?.cost_total, b.cost_total]) {
      if (typeof v === 'number' && Number.isFinite(v) && v >= 0) return v;
    }
  }
  return null;
}
