// The work behind tools/art/generate.mjs (BRIEF 3.10). See docs/ART_PIPELINE.md.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { parseArgs, USAGE, UsageError } from './args.mjs';
import { ArtJsonError, composePrompt, loadArt } from './art_json.mjs';
import { endpointLimits, REPO_ROOT } from './config.mjs';
import { checkMockUrl, extractBilledUsd, FalClient } from './fal.mjs';
import { checkArtLock, EXIT_LOCKED, makeRedactor } from './locks.mjs';
import {
  inputMatches,
  loadManifest,
  manifestPath,
  RECOVERABLE,
  sameInput,
  saveManifest,
  selectedEntry,
  selectEntry,
} from './manifest.mjs';
import { isPng, pngSize } from './png.mjs';
import { estimateUsd, formatUsd, ticksToUsd, usdToTicks } from './prices.mjs';
import { planRequestSize } from './sizing.mjs';

export const EXIT_OK = 0;
export const EXIT_FAILED = 1;
export const EXIT_USAGE = 2;
export const EXIT_BUDGET = 3;
export { EXIT_LOCKED };

const DAY_MS = 24 * 60 * 60 * 1000;
const DOWNLOAD_ATTEMPTS = 3;
const STATUS_ERROR_LIMIT = 5;

const now = () => new Date().toISOString();
const ms = (iso) => {
  const t = Date.parse(iso ?? '');
  return Number.isFinite(t) ? t : 0;
};

/** The fal input for one sprite: the shared style prefix plus the sprite prompt, size and background. */
export function buildInput(art, sprite, limits, req) {
  const input = {
    prompt: composePrompt(art, sprite),
    image_size: { width: req.width, height: req.height },
    background: sprite.background,
  };
  if (limits.params.quality) input.quality = art.quality;
  input.num_images = 1;
  input.output_format = 'png';
  return input;
}

function cacheFileExists(root, entry) {
  return typeof entry.cache === 'string' && entry.cache !== '' && fs.existsSync(path.join(root, entry.cache));
}

/** When a request was made: its submit time (or, for one never submitted, its creation time). */
const requestedMs = (e) => ms(e.submitted_at) || ms(e.created_at);

/** Newest request first; "newest" is when the request was made, not when its image was fetched. */
function newestFirst(list) {
  return [...list].sort((a, b) => requestedMs(b) - requestedMs(a));
}

/** Manifest entries of `sprite` with exactly this endpoint and input. */
function matching(manifest, sprite, endpoint, input) {
  return manifest.requests.filter((r) => r.sprite === sprite && r.endpoint === endpoint && sameInput(r.input, input));
}

/** The newest usable local result for this input, if its raw image is still in .art_cache. */
export function findCacheHit(manifest, root, sprite, endpoint, input) {
  const ok = matching(manifest, sprite, endpoint, input).filter((r) => r.status === 'ok' && cacheFileExists(root, r));
  return newestFirst(ok)[0] ?? null;
}

/** Paid entries of this input whose image can still be fetched without paying again. */
function findRecoverable(manifest, root, sprite, endpoint, input) {
  return newestFirst(
    matching(manifest, sprite, endpoint, input).filter(
      (r) => (r.status === 'ok' && !cacheFileExists(root, r) && r.image_url) || RECOVERABLE.has(r.status),
    ),
  );
}

/** One plan row per sprite: request size, aspect error, input, estimate and local status. */
export function buildPlan(art, manifest, opts, root) {
  const limits = endpointLimits(art.endpoint);
  const targets = new Set([...opts.only, ...opts.reroll]);
  const reroll = new Set(opts.reroll);
  return art.sprites.map((sprite, index) => {
    const req = planRequestSize(sprite.size, limits);
    const input = buildInput(art, sprite, limits, req);
    const estimate = estimateUsd(art.endpoint, req.width, req.height, input.quality ?? art.quality);
    let status = 'new';
    if (reroll.has(sprite.id)) status = 'reroll';
    else if (findCacheHit(manifest, root, sprite.id, art.endpoint, input)) status = 'cached';
    else if (findRecoverable(manifest, root, sprite.id, art.endpoint, input).length > 0) status = 'recoverable';
    return {
      sprite,
      index,
      endpoint: art.endpoint,
      req,
      input,
      estimate,
      status,
      included: targets.size === 0 || targets.has(sprite.id),
    };
  });
}

function pad(s, n) {
  return String(s).padEnd(n);
}

function aspectText(a) {
  return a >= 1 ? `${a.toFixed(2)}:1` : `1:${(1 / a).toFixed(2)}`;
}

function pct(v) {
  const s = v.toFixed(2);
  return `${v >= 0 ? '+' : ''}${s === '-0.00' ? '0.00' : s}%`;
}

/** The --dry-run report (text or JSON). Returns {text, toPayUsd}. */
export function formatPlan(art, plan, opts, manifest) {
  const rows = plan.filter((p) => p.included);
  const budgetTicks = usdToTicks(opts.budget);
  let payTicks = 0;
  let stopAt = null;
  for (const p of rows) {
    if (p.status === 'cached') continue;
    const t = usdToTicks(p.estimate);
    if (stopAt === null && payTicks + t > budgetTicks) stopAt = p.sprite.id;
    payTicks += t;
  }
  const outside = rows.filter((p) => p.req.outside_limits);
  if (opts.json) {
    const data = {
      game: opts.game,
      endpoint: art.endpoint,
      quality: art.quality,
      budget_usd: opts.budget,
      to_pay_usd: ticksToUsd(payTicks),
      spent_usd: manifest.spend?.total_usd ?? 0,
      budget_stop_at: stopAt,
      sprites: rows.map((p) => ({
        id: p.sprite.id,
        size: p.sprite.size,
        background: p.sprite.background,
        tile: p.sprite.tile,
        request: [p.req.width, p.req.height],
        aspect_error_pct: Number(p.req.aspect_error_pct.toFixed(4)),
        outside_limits: p.req.outside_limits,
        estimate_usd: p.estimate,
        status: p.status,
      })),
      outside_limits: outside.map((p) => p.sprite.id),
    };
    return { text: `${JSON.stringify(data, null, 2)}\n`, toPayUsd: ticksToUsd(payTicks) };
  }
  const lines = [];
  lines.push(`art plan for ${opts.game}: ${art.endpoint}, quality ${art.quality} (dry run: nothing contacted)`);
  const w = Math.max(6, ...rows.map((p) => p.sprite.id.length));
  lines.push(`  ${pad('sprite', w)}  ${pad('size', 9)}  ${pad('request', 10)}  ${pad('aspect err', 10)}  ${pad('estimate', 9)}  status`);
  for (const p of rows) {
    const flag = p.req.outside_limits ? (p.sprite.tile ? ' (tile segment)' : ' (outside limits)') : '';
    lines.push(
      `  ${pad(p.sprite.id, w)}  ${pad(`${p.sprite.size[0]}x${p.sprite.size[1]}`, 9)}  ${pad(`${p.req.width}x${p.req.height}`, 10)}  ${pad(pct(p.req.aspect_error_pct), 10)}  ${pad(formatUsd(p.status === 'cached' ? 0 : p.estimate), 9)}  ${p.status}${flag}`,
    );
  }
  const paying = rows.filter((p) => p.status !== 'cached').length;
  lines.push(
    `total: ${paying} request(s) to pay, ${formatUsd(ticksToUsd(payTicks))} estimated; ${rows.length - paying} cached; budget ${formatUsd(opts.budget)}; manifest spend so far ${formatUsd(manifest.spend?.total_usd ?? 0)}`,
  );
  if (stopAt !== null) lines.push(`budget: this run would stop before ${stopAt} (raise --budget or narrow --only)`);
  else lines.push('budget: the plan fits');
  if (outside.length > 0) {
    lines.push('outside the endpoint limits (requested at the nearest allowed aspect):');
    for (const p of outside) {
      lines.push(
        `  ${p.sprite.id} ${p.sprite.size[0]}x${p.sprite.size[1]} (${aspectText(p.req.sprite_aspect)}) -> ${p.req.width}x${p.req.height} (${aspectText(p.req.request_aspect)}), aspect error ${pct(p.req.aspect_error_pct)}${p.sprite.tile ? '; tile: pixelate repeats the segment across the width' : '; consider a narrower size or tile: true'}`,
      );
    }
  } else {
    lines.push('outside the endpoint limits: none');
  }
  return { text: `${lines.join('\n')}\n`, toPayUsd: ticksToUsd(payTicks) };
}

class Run {
  constructor({ art, plan, manifest, mfile, root, game, client, opts, out, err }) {
    Object.assign(this, { art, plan, manifest, mfile, root, game, client, opts, out, err });
    this.cacheDir = path.join(root, '.art_cache', game);
    this.stats = { cached: 0, recovered: 0, paid: 0, failed: 0, skipped: [], notPaid: [] };
    this.runTicks = 0;
    this.budgetTicks = usdToTicks(opts.budget);
    this.budgetStopped = false;
    // Set when the client refused to fetch an image (a host it may not contact): paying for more
    // results whose images can't be fetched would only burn money, so the run stops paying.
    this.hostStop = null;
  }

  save() {
    saveManifest(this.mfile, this.manifest);
  }

  newEntry(p, source) {
    const e = {
      sprite: p.sprite.id,
      endpoint: p.endpoint,
      input: p.input,
      request_id: null,
      status: 'submitting',
      source,
      paid: false,
      estimated_usd: p.estimate,
      billed_usd: null,
      created_at: now(),
      submitted_at: null,
      completed_at: null,
      downloaded_at: null,
      status_url: null,
      response_url: null,
      image_url: null,
      cache: null,
      width: null,
      height: null,
      bytes: null,
      sha256: null,
      selected: false,
      error: null,
    };
    this.manifest.requests.push(e);
    return e;
  }

  /** Selects `entry` for its sprite unless the user picked another result with --select. */
  selectAfterRun(entry, isNewResult) {
    const cur = selectedEntry(this.manifest, entry.sprite);
    if (!isNewResult && cur && cur !== entry && cur.selected_by === 'user') {
      this.out(`${entry.sprite}: keeps its --select choice ${cur.request_id}`);
      return;
    }
    if (cur === entry) return;
    selectEntry(this.manifest, entry, 'run');
  }

  async download(entry) {
    let lastErr = null;
    for (let attempt = 1; attempt <= DOWNLOAD_ATTEMPTS; attempt++) {
      try {
        const buf = await this.client.download(entry.image_url);
        if (!isPng(buf)) throw new Error('the result is not a PNG');
        const size = pngSize(buf);
        fs.mkdirSync(this.cacheDir, { recursive: true });
        const file = path.join(this.cacheDir, `${entry.request_id}.png`);
        fs.writeFileSync(file, buf);
        entry.cache = path.relative(this.root, file).split(path.sep).join('/');
        entry.width = size.width;
        entry.height = size.height;
        entry.bytes = buf.length;
        entry.sha256 = crypto.createHash('sha256').update(buf).digest('hex');
        entry.downloaded_at = now();
        entry.status = 'ok';
        entry.error = null;
        return true;
      } catch (e) {
        lastErr = e;
        if (e?.refused) {
          this.hostStop ??= e.message;
          break;
        }
        if (attempt < DOWNLOAD_ATTEMPTS) await sleep(Math.min(this.opts.pollMs, 1000));
      }
    }
    entry.status = 'download_failed';
    entry.error = String(lastErr?.message ?? lastErr);
    return false;
  }

  writeResultJson(entry, body) {
    try {
      fs.mkdirSync(this.cacheDir, { recursive: true });
      fs.writeFileSync(path.join(this.cacheDir, `${entry.request_id}.json`), `${JSON.stringify(body, null, 2)}\n`);
    } catch {
      // The raw JSON is a convenience; the manifest already holds what matters.
    }
  }

  /**
   * Polls a submitted request to completion, fetches its result and downloads the image. With
   * maxWaitS 0 it asks for the status once and gives up (still recoverable) unless fal is done.
   */
  async complete(entry, maxWaitS = this.opts.timeoutS) {
    const deadline = Date.now() + maxWaitS * 1000;
    let errors = 0;
    let st = null;
    for (;;) {
      try {
        st = await this.client.status(entry.status_url);
        errors = 0;
      } catch (e) {
        errors += 1;
        if (errors >= STATUS_ERROR_LIMIT) {
          entry.status = 'timeout';
          entry.error = `status polling failed ${errors} times: ${e.message}`;
          this.save();
          return false;
        }
        st = null;
      }
      if (st?.status === 'COMPLETED') break;
      if (Date.now() >= deadline) {
        entry.status = 'timeout';
        entry.error = `not completed after ${maxWaitS} s (status ${st?.status ?? 'unknown'})`;
        this.save();
        return false;
      }
      await sleep(this.opts.pollMs);
    }
    entry.completed_at = now();
    if (st.error) {
      entry.status = 'failed';
      entry.error = `${st.error_type ?? 'error'}: ${typeof st.error === 'string' ? st.error : JSON.stringify(st.error)}`;
      const billed = extractBilledUsd(st);
      if (billed !== null) entry.billed_usd = billed;
      this.save();
      return false;
    }
    let body;
    try {
      body = await this.client.result(entry.response_url);
    } catch (e) {
      entry.status = 'result_failed';
      entry.error = e.message;
      this.save();
      return false;
    }
    const billed = extractBilledUsd(body, st);
    if (billed !== null) entry.billed_usd = billed;
    const url = body?.images?.[0]?.url;
    if (typeof url !== 'string') {
      entry.status = 'failed';
      entry.error = 'the result has no image';
      this.save();
      return false;
    }
    entry.image_url = url;
    this.writeResultJson(entry, body);
    this.save();
    const ok = await this.download(entry);
    if (ok) this.selectAfterRun(entry, true);
    this.save();
    return ok;
  }

  /** True when this run may fetch `e`'s image or resume it (a record from another host is left alone). */
  reachable(e) {
    const where = e.image_url ?? e.status_url;
    return Boolean(where) && this.client.allowed(where) && (!e.response_url || this.client.allowed(e.response_url));
  }

  /**
   * A result the user picked with --select whose raw image is missing from .art_cache (a fresh
   * clone, a cleaned cache) is fetched again from its stored image URL, for free, whatever its input.
   */
  async refetchUserSelection(id) {
    const cur = selectedEntry(this.manifest, id);
    if (!cur || cur.selected_by !== 'user' || cur.status !== 'ok' || cacheFileExists(this.root, cur)) return;
    if (!cur.image_url || !this.reachable(cur)) {
      this.err(`warning: ${id}: the selected result ${cur.request_id} has no raw image in .art_cache and no image URL this run may fetch`);
      return;
    }
    const ok = await this.download(cur);
    this.save();
    if (ok) this.out(`${id}: fetched the selected result ${cur.request_id} again (${cur.cache})`);
    else this.err(`warning: ${id}: the selected result ${cur.request_id} could not be fetched again: ${cur.error}`);
  }

  /**
   * Free paths first, newest request first: the local cache, a stored image URL, or a request that
   * was paid but never fetched (for example a --reroll whose download failed). A paid result newer
   * than the cached one is recovered and wins, so the newest result stays the default; an unfinished
   * request newer than a cached result gets one status check rather than a long wait.
   */
  async resolveLocally(p) {
    const id = p.sprite.id;
    await this.refetchUserSelection(id);
    const hit = findCacheHit(this.manifest, this.root, id, p.endpoint, p.input);
    for (const e of findRecoverable(this.manifest, this.root, id, p.endpoint, p.input)) {
      if (hit && requestedMs(e) <= requestedMs(hit)) break;
      if (!this.reachable(e)) continue;
      const wasOk = e.status === 'ok';
      let ok = false;
      if (e.image_url) {
        ok = await this.download(e);
        if (!ok && e.status !== 'ok') this.save();
      }
      if (!ok && e.status_url && e.response_url && RECOVERABLE.has(e.status) && !e.image_url) {
        ok = await this.complete(e, hit ? 0 : this.opts.timeoutS);
      }
      if (ok) {
        // Fetching an image that was already fine again is not a new result: a --select choice stays.
        this.selectAfterRun(e, !wasOk);
        this.save();
        this.stats.recovered += 1;
        this.out(`${id}: recovered ${e.request_id} without paying again (${e.cache})`);
        return true;
      }
      this.save();
    }
    if (hit) {
      this.selectAfterRun(hit, false);
      this.save();
      this.stats.cached += 1;
      this.out(`${id}: cached ${hit.request_id} (${hit.cache})`);
      return true;
    }
    return false;
  }

  async listing(endpoint) {
    if (!this.listings) this.listings = new Map();
    if (this.listings.has(endpoint)) return this.listings.get(endpoint);
    const since = new Date(Date.now() - DAY_MS).toISOString();
    let items = [];
    try {
      items = await this.client.listRequests(endpoint, since);
    } catch (e) {
      this.err(`warning: cannot read fal's request history for ${endpoint} (${e.message}); paying for new results`);
      items = [];
    }
    this.listings.set(endpoint, items);
    return items;
  }

  /** Looks for a paid result with the same input from the last 24 hours and downloads it. */
  async recoverFromHistory(p) {
    const items = await this.listing(p.endpoint);
    const cutoff = Date.now() - DAY_MS;
    const found = items
      .filter(
        (it) =>
          it &&
          it.endpoint_id === p.endpoint &&
          (it.status_code === undefined || it.status_code === null || it.status_code === 200) &&
          ms(it.ended_at ?? it.started_at) >= cutoff &&
          typeof it.json_output?.images?.[0]?.url === 'string' &&
          inputMatches(p.input, it.json_input),
      )
      .sort((a, b) => ms(b.ended_at ?? b.started_at) - ms(a.ended_at ?? a.started_at));
    for (const it of found) {
      let e = this.manifest.requests.find((r) => r.sprite === p.sprite.id && r.request_id === it.request_id);
      if (!e) {
        e = this.newEntry(p, 'recovered');
        e.request_id = it.request_id;
        e.paid = true;
        e.submitted_at = it.started_at ?? null;
        e.status = 'download_failed';
      }
      e.completed_at = it.ended_at ?? e.completed_at;
      e.image_url = it.json_output.images[0].url;
      const billed = extractBilledUsd(it.json_output, it);
      if (billed !== null) e.billed_usd = billed;
      const ok = await this.download(e);
      if (ok) {
        this.selectAfterRun(e, true);
        this.save();
        this.stats.recovered += 1;
        this.out(`${p.sprite.id}: recovered paid result ${e.request_id} from fal's request history (last 24 h)`);
        return true;
      }
      this.save();
    }
    return false;
  }

  async pay(p) {
    const e = this.newEntry(p, 'generated');
    this.save();
    try {
      const sub = await this.client.submit(p.endpoint, p.input);
      e.request_id = sub.request_id;
      e.status_url = sub.status_url;
      e.response_url = sub.response_url;
      e.status = 'submitted';
      e.paid = true;
      e.submitted_at = now();
    } catch (err) {
      // fal took no request, so nothing was paid: release this sprite's share of the budget.
      this.runTicks -= usdToTicks(p.estimate);
      e.status = 'submit_failed';
      e.error = err.message;
      this.save();
      this.stats.failed += 1;
      this.err(`${p.sprite.id}: submit failed: ${err.message}`);
      return;
    }
    this.save();
    this.out(`${p.sprite.id}: submitted ${e.request_id} at ${p.req.width}x${p.req.height} (${formatUsd(p.estimate)} estimated)`);
    const ok = await this.complete(e);
    if (typeof e.billed_usd === 'number') {
      const extra = usdToTicks(e.billed_usd) - usdToTicks(e.estimated_usd);
      if (extra > 0) this.runTicks += extra;
    }
    if (ok) {
      this.stats.paid += 1;
      this.out(`${p.sprite.id}: done ${e.request_id} ${e.width}x${e.height} -> ${e.cache}${typeof e.billed_usd === 'number' ? ` (billed ${formatUsd(e.billed_usd)})` : ''}`);
    } else {
      this.stats.failed += 1;
      this.err(`${p.sprite.id}: ${e.status} ${e.request_id}: ${e.error}`);
    }
  }

  async run() {
    const work = this.plan.filter((p) => p.included);
    const toPay = [];
    for (const p of work) {
      if (p.status !== 'reroll' && (await this.resolveLocally(p))) continue;
      toPay.push(p);
    }
    const payList = [];
    for (const p of toPay) {
      if (p.status !== 'reroll' && (await this.recoverFromHistory(p))) continue;
      payList.push(p);
    }
    let next = 0;
    const worker = async () => {
      for (;;) {
        if (this.budgetStopped || this.hostStop) return;
        const i = next;
        if (i >= payList.length) return;
        next += 1;
        const p = payList[i];
        const t = usdToTicks(p.estimate);
        if (this.runTicks + t > this.budgetTicks) {
          this.budgetStopped = true;
          this.stats.skipped = payList.slice(i).map((x) => x.sprite.id);
          this.err(
            `budget stop: ${p.sprite.id} (${formatUsd(p.estimate)}) would take this run's estimated spend from ${formatUsd(ticksToUsd(this.runTicks))} past the --budget of ${formatUsd(this.opts.budget)}; not paid: ${this.stats.skipped.join(', ')}`,
          );
          return;
        }
        this.runTicks += t;
        await this.pay(p);
      }
    };
    const n = Math.max(1, Math.min(this.opts.concurrency, payList.length || 1));
    await Promise.all(Array.from({ length: n }, () => worker()));
    this.save();
    const s = this.stats;
    if (this.hostStop) {
      s.notPaid = payList
        .slice(next)
        .map((x) => x.sprite.id)
        .filter((id) => !s.skipped.includes(id));
      this.err(
        `stopped paying: ${this.hostStop}. A result whose image can't be fetched is money lost, so no further sprite was paid${s.notPaid.length ? ` (not paid: ${s.notPaid.join(', ')})` : ''}. The paid request stays in the manifest as download_failed with its image URL; once that host is allowed, a run fetches it for free.`,
      );
    }
    this.out(
      `generate: ${s.paid} paid, ${s.cached} cached, ${s.recovered} recovered, ${s.failed} failed${s.skipped.length ? `, ${s.skipped.length} skipped by the budget stop` : ''}${s.notPaid.length ? `, ${s.notPaid.length} not paid after a refused host` : ''}; this run ${formatUsd(ticksToUsd(this.runTicks))} of ${formatUsd(this.opts.budget)} budget; manifest spend total ${formatUsd(this.manifest.spend.total_usd)}`,
    );
    if (s.failed > 0 || this.hostStop) return EXIT_FAILED;
    if (this.budgetStopped) return EXIT_BUDGET;
    return EXIT_OK;
  }
}

function applySelect(art, manifest, root, opts, out, err) {
  const problems = [];
  const chosen = [];
  for (const { sprite, request_id: rid } of opts.select) {
    if (!art.sprites.some((s) => s.id === sprite)) {
      problems.push(`--select ${sprite}:${rid}: art.json has no sprite "${sprite}"`);
      continue;
    }
    const e = manifest.requests.find((r) => r.sprite === sprite && r.request_id === rid);
    if (!e) {
      problems.push(`--select ${sprite}:${rid}: the manifest has no request ${rid} for ${sprite}`);
      continue;
    }
    if (e.status !== 'ok') {
      problems.push(`--select ${sprite}:${rid}: that request is "${e.status}", not a usable result`);
      continue;
    }
    chosen.push(e);
  }
  if (problems.length > 0) {
    for (const p of problems) err(p);
    return EXIT_USAGE;
  }
  for (const e of chosen) {
    selectEntry(manifest, e, 'user');
    out(`${e.sprite}: selected ${e.request_id}`);
    if (!cacheFileExists(root, e)) err(`warning: ${e.sprite}: the raw result ${e.cache} is missing; run generate.mjs to fetch it again before pixelating`);
  }
  saveManifest(manifestPath(root, opts.game), manifest);
  return EXIT_OK;
}

/**
 * Runs generate.mjs. `env` is the environment to read the art lock from (process.env in the CLI).
 * Returns the exit code.
 */
export async function main(argv, env, io = {}) {
  const stdout = io.stdout ?? process.stdout;
  const stderr = io.stderr ?? process.stderr;
  let opts;
  try {
    opts = parseArgs(argv);
  } catch (e) {
    if (e instanceof UsageError) {
      stderr.write(`generate.mjs: ${e.message}\n\n${USAGE}`);
      return EXIT_USAGE;
    }
    throw e;
  }
  if (opts.help) {
    stdout.write(USAGE);
    return EXIT_OK;
  }

  // The art lock comes before anything else that could reach the network.
  let mockOrigin = null;
  let key = null;
  if (opts.mock !== null) {
    try {
      mockOrigin = checkMockUrl(opts.mock);
    } catch (e) {
      stderr.write(`generate.mjs: ${e.message}\n`);
      return EXIT_USAGE;
    }
  }
  const needsFal = !opts.dryRun && opts.select.length === 0;
  if (needsFal && mockOrigin === null) {
    const lock = checkArtLock(env);
    if (!lock.ok) {
      stderr.write(lock.message);
      return EXIT_LOCKED;
    }
    key = env.FAL_KEY;
  }
  const redact = makeRedactor(key);
  const out = (line) => stdout.write(`${redact(line)}\n`);
  const err = (line) => stderr.write(`${redact(line)}\n`);

  const root = path.resolve(opts.root ?? REPO_ROOT);
  const artFile = path.join(root, 'assets', opts.game, 'art.json');
  let art;
  try {
    art = loadArt(artFile);
  } catch (e) {
    if (e instanceof ArtJsonError) {
      err(e.message);
      return EXIT_USAGE;
    }
    throw e;
  }
  const ids = new Set(art.sprites.map((s) => s.id));
  const unknown = [...opts.only, ...opts.reroll, ...opts.select.map((s) => s.sprite)].filter((id) => !ids.has(id));
  if (unknown.length > 0) {
    err(`generate.mjs: unknown sprite id(s) for ${opts.game}: ${[...new Set(unknown)].join(', ')}`);
    return EXIT_USAGE;
  }
  const mfile = manifestPath(root, opts.game);
  let manifest;
  try {
    manifest = loadManifest(mfile, opts.game);
  } catch (e) {
    err(`generate.mjs: ${e.message}`);
    return EXIT_USAGE;
  }
  if (opts.select.length > 0) return applySelect(art, manifest, root, opts, out, err);

  const plan = buildPlan(art, manifest, opts, root);
  if (opts.dryRun) {
    stdout.write(redact(formatPlan(art, plan, opts, manifest).text));
    return EXIT_OK;
  }
  const client = new FalClient({ mockOrigin, key, redact, timeoutMs: 120000 });
  out(`generate: ${opts.game} on ${mockOrigin ? `the mock at ${mockOrigin}` : 'fal'} (${art.endpoint}, quality ${art.quality}, budget ${formatUsd(opts.budget)})`);
  const run = new Run({ art, plan, manifest, mfile, root, game: opts.game, client, opts, out, err });
  return run.run();
}
