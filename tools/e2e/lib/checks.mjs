// tools/e2e/lib/checks.mjs: the BRIEF 7.7 assertions as pure functions over peer reports and logs.
// Game sessions' tests/games/<id>/e2e_check.mjs may import these too.

/** BRIEF 4.6.8 warm-up limits the e2e content must stay inside. */
export const WARMUP_LIMITS = Object.freeze({ ergMaxPct: 65, gradeMinPct: -2, gradeMaxPct: 3 });
const EPS = 1e-6;

/**
 * Event types that are a peer's own view, not part of the shared session sequence: session and
 * app states, network and lobby churn, rides and uploads, HUD messages addressed to one peer.
 * Everything else (phase_started per rider, game events, game_phase_changed, results) must arrive
 * in the same order on every peer.
 */
export const PER_PEER_EVENT_TYPES = new Set([
  'session_state', 'state', 'app_state', 'net_state', 'lobby', 'lobby_state', 'peer_joined', 'peer_left',
  'peer', 'joined', 'rejoined', 'reconnected', 'reconnect', 'disconnected', 'connected', 'local',
  'upload', 'upload_state', 'ride_saved', 'fit_saved', 'unlocks', 'progress', 'roster', 'snapshot',
  'hud', 'toast', 'banner', 'telemetry', 'afk', 'afk_changed', 'rescue', 'rescue_changed', 'paused',
  'paused_changed', 'pause', 'resume', 'log', 'warning', 'desync',
]);

/** Keys that differ between peers for the same event (arrival times, local clocks). */
export const VOLATILE_EVENT_KEYS = new Set([
  't', 'time', 'ts', 'at', 'wall', 'wall_t', 'wall_ms', 'received_t', 'local_t', 'arrived_t', 'recv_t',
]);

/** final_state keys that legitimately differ per peer. */
export const PER_PEER_STATE_KEYS = new Set(['role', 'local_peer', 'peer_id', 't', 'time', 'wall', 'meta', 'local', 'is_host']);

function isObj(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

export function num(v) {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Number(v);
  return null;
}

/** The event's type, or "" when it has none. */
export function eventType(e) {
  return isObj(e) && typeof e.type === 'string' ? e.type : '';
}

/** Shared-sequence events of one peer, with volatile keys removed. */
export function comparableEvents(events) {
  if (!Array.isArray(events)) return [];
  const out = [];
  for (const e of events) {
    if (!isObj(e)) continue;
    const type = eventType(e);
    if (type === '' || PER_PEER_EVENT_TYPES.has(type)) continue;
    const c = {};
    for (const [k, v] of Object.entries(e)) {
      if (!VOLATILE_EVENT_KEYS.has(k)) c[k] = v;
    }
    out.push(c);
  }
  return out;
}

/**
 * Differences between a and b as [{path, a, b}] (at most `limit`). Numbers match within
 * max(absTol, relTol * max(|a|, |b|)); keys in `ignoreKeys` (or starting with "local_" when
 * ignoreLocal) are skipped at every depth. int vs float never matters (JSON).
 */
export function deepDiff(a, b, opts = {}, pathStr = '', out = []) {
  const { relTol = 1e-9, absTol = 1e-9, ignoreKeys = new Set(), ignoreLocal = false, limit = 20 } = opts;
  if (out.length >= limit) return out;
  if (typeof a === 'number' && typeof b === 'number') {
    const tol = Math.max(absTol, relTol * Math.max(Math.abs(a), Math.abs(b)));
    if (!(Math.abs(a - b) <= tol) && !(Number.isNaN(a) && Number.isNaN(b))) out.push({ path: pathStr || '.', a, b });
    return out;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) {
      out.push({ path: `${pathStr || '.'}.length`, a: a.length, b: b.length });
      return out;
    }
    for (let i = 0; i < a.length && out.length < limit; i++) deepDiff(a[i], b[i], opts, `${pathStr}[${i}]`, out);
    return out;
  }
  if (isObj(a) && isObj(b)) {
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of [...keys].sort()) {
      if (out.length >= limit) break;
      if (ignoreKeys.has(k) || (ignoreLocal && k.startsWith('local_'))) continue;
      if (!(k in a)) out.push({ path: `${pathStr}.${k}`, a: undefined, b: b[k] });
      else if (!(k in b)) out.push({ path: `${pathStr}.${k}`, a: a[k], b: undefined });
      else deepDiff(a[k], b[k], opts, `${pathStr}.${k}`, out);
    }
    return out;
  }
  if (a !== b) out.push({ path: pathStr || '.', a, b });
  return out;
}

const EVENT_TOL = { relTol: 1e-6, absTol: 1e-9 };

export function eventsEqual(a, b) {
  return deepDiff(a, b, { ...EVENT_TOL, limit: 1 }).length === 0;
}

function brief(e) {
  const s = JSON.stringify(e);
  return s && s.length > 160 ? `${s.slice(0, 157)}...` : s;
}

/** Exact sequence equality: {ok, detail, index}. */
export function compareSequences(ref, other) {
  const n = Math.min(ref.length, other.length);
  for (let i = 0; i < n; i++) {
    if (!eventsEqual(ref[i], other[i])) {
      return { ok: false, index: i, detail: `event ${i} differs: expected ${brief(ref[i])}, got ${brief(other[i])}` };
    }
  }
  if (ref.length !== other.length) {
    const extra = ref.length > other.length ? `missing ${brief(ref[n])}` : `extra ${brief(other[n])}`;
    return { ok: false, index: n, detail: `${other.length} events instead of ${ref.length} (${extra} at ${n})` };
  }
  return { ok: true, index: -1, detail: `${ref.length} events identical` };
}

/**
 * For a client that rejoined mid-session: its sequence must be the tail of the reference, after at
 * most one leading phase_started event that the rejoin replays (its own current phase, from the
 * `phase` message; when `replayPeer` is given, only one for that peer). The tail must not be empty.
 */
export function matchTail(ref, other, { replayPeer = null, maxReplay = 1 } = {}) {
  for (let skip = 0; skip <= Math.min(maxReplay, other.length); skip++) {
    if (skip > 0) {
      const e = other[skip - 1];
      if (eventType(e) !== 'phase_started') break;
      if (replayPeer !== null && String(e.peer) !== String(replayPeer)) break;
    }
    const tailSeq = other.slice(skip);
    if (tailSeq.length === 0) continue;
    const from = ref.length - tailSeq.length;
    if (from < 0) continue;
    if (compareSequences(ref.slice(from), tailSeq).ok) {
      return { ok: true, skipped: skip, from, detail: `the last ${tailSeq.length} of ${ref.length} events match (from ${from}, ${skip} replayed)` };
    }
  }
  const last = other.length ? brief(other[other.length - 1]) : 'none';
  return { ok: false, skipped: 0, from: -1, detail: `its ${other.length} events are not a tail of the host's ${ref.length} (last: ${last})` };
}

/**
 * The shared-sequence check over peers: {ok, details: [String]}. `partial` names rejoined peers,
 * `peerIds` maps roles to peer ids (for the rejoin's replayed phase).
 */
export function checkSameEvents(byRole, { reference = 'host', partial = [], peerIds = {} } = {}) {
  const details = [];
  let ok = true;
  const ref = comparableEvents(byRole[reference]);
  if (ref.length === 0) {
    return { ok: false, details: [`${reference} reported no shared events (phase_started, game events, results)`] };
  }
  if (!ref.some((e) => eventType(e) === 'results')) {
    ok = false;
    details.push(`${reference}'s events hold no "results" event`);
  }
  if (!ref.some((e) => eventType(e) === 'phase_started')) {
    ok = false;
    details.push(`${reference}'s events hold no "phase_started" event`);
  }
  for (const [role, events] of Object.entries(byRole)) {
    if (role === reference) continue;
    const seq = comparableEvents(events);
    const r = partial.includes(role) ? matchTail(ref, seq, { replayPeer: peerIds[role] ?? null }) : compareSequences(ref, seq);
    if (partial.includes(role) && r.ok && !seq.some((e) => eventType(e) === 'results')) {
      ok = false;
      details.push(`${role}: no "results" event after its rejoin`);
      continue;
    }
    if (!r.ok) ok = false;
    details.push(`${role}: ${r.detail}`);
  }
  return { ok, details };
}

/** final_state of every peer against the reference, within tolerance. */
export function checkFinalState(byRole, { reference = 'host', relTol = 0.02, absTol = 0.01 } = {}) {
  const ref = byRole[reference];
  const details = [];
  let ok = true;
  if (!isObj(ref)) return { ok: false, details: [`${reference} reported no final_state object`] };
  for (const [role, st] of Object.entries(byRole)) {
    if (role === reference) continue;
    if (!isObj(st)) {
      ok = false;
      details.push(`${role}: no final_state object`);
      continue;
    }
    const diffs = deepDiff(ref, st, { relTol, absTol, ignoreKeys: PER_PEER_STATE_KEYS, ignoreLocal: true, limit: 5 });
    if (diffs.length) {
      ok = false;
      details.push(`${role}: ${diffs.map((d) => `${d.path}: ${JSON.stringify(d.a)} vs ${JSON.stringify(d.b)}`).join('; ')}`);
    } else {
      details.push(`${role}: within tolerance`);
    }
  }
  return { ok, details };
}

/**
 * BRIEF 4.6.8 warm-up limits over a peer's 1 Hz trace and applied directive records: every ERG
 * entry's applied %FTP <= 65 and every SIM entry's applied grade within -2..+3.
 */
export function checkWarmup(trace, directives = [], limits = WARMUP_LIMITS) {
  const violations = [];
  let erg = 0;
  let sim = 0;
  if (!Array.isArray(trace) || trace.length === 0) {
    return { ok: false, erg, sim, violations: ['no trace entries (the report must hold the local rider\'s 1 Hz trace)'] };
  }
  trace.forEach((e, i) => {
    if (!isObj(e)) return;
    const mode = String(e.mode ?? '').toUpperCase();
    const where = `trace[${i}] t=${e.t ?? '?'}`;
    if (mode === 'ERG') {
      erg++;
      const pct = num(e.applied_pct ?? e.applied_ftp_pct);
      if (pct === null) violations.push(`${where}: ERG entry without applied_pct`);
      else if (pct > limits.ergMaxPct + EPS) violations.push(`${where}: ERG target ${pct}% FTP above ${limits.ergMaxPct}%`);
    } else if (mode === 'SIM') {
      sim++;
      const g = num(e.applied_grade_pct ?? e.applied_grade);
      if (g === null) violations.push(`${where}: SIM entry without applied_grade_pct`);
      else if (g < limits.gradeMinPct - EPS || g > limits.gradeMaxPct + EPS) {
        violations.push(`${where}: SIM grade ${g}% outside ${limits.gradeMinPct}..+${limits.gradeMaxPct}%`);
      }
    }
  });
  (Array.isArray(directives) ? directives : []).forEach((r, i) => {
    if (!isObj(r) || r.refused === true || !isObj(r.applied)) return;
    const a = r.applied;
    const where = `directives[${i}] id=${r.id ?? '?'}`;
    const pct = num(a.target_pct ?? a.applied_pct);
    if (pct !== null && pct > limits.ergMaxPct + EPS) violations.push(`${where}: applied ERG ${pct}% FTP above ${limits.ergMaxPct}%`);
    for (const key of ['grade_pct', 'applied_grade_pct', 'mode_grade', 'course_grade']) {
      const g = num(a[key]);
      if (g !== null && (g < limits.gradeMinPct - EPS || g > limits.gradeMaxPct + EPS)) {
        violations.push(`${where}: applied ${key} ${g}% outside ${limits.gradeMinPct}..+${limits.gradeMaxPct}%`);
      }
    }
  });
  return { ok: violations.length === 0, erg, sim, violations };
}

/**
 * Every directive went through a governor: each record is refused with a reason, or carries the
 * applied values and a clamped_by list. When the host's records name a remote peer, that peer's
 * report must hold the same id (a rejoined peer may miss the ones from before its restart).
 */
export function checkDirectives(peers, { reference = 'host', partial = [] } = {}) {
  const problems = [];
  const warnings = [];
  let total = 0;
  const idsByPeerId = new Map();
  for (const [role, p] of Object.entries(peers)) {
    const recs = Array.isArray(p?.directives) ? p.directives : [];
    const ids = new Set();
    recs.forEach((r, i) => {
      total++;
      const where = `${role} directives[${i}]`;
      if (!isObj(r)) {
        problems.push(`${where}: not an object`);
        return;
      }
      if (r.id !== undefined) ids.add(String(r.id));
      if (r.refused === true) {
        if (!r.reason) problems.push(`${where}: refused without a reason`);
        return;
      }
      if (!isObj(r.applied)) problems.push(`${where}: no applied values`);
      if (!Array.isArray(r.clamped_by)) problems.push(`${where}: no clamped_by list`);
    });
    if (p && p.peer_id !== undefined && p.peer_id !== null) idsByPeerId.set(String(p.peer_id), { role, ids });
  }
  const host = peers[reference];
  const hostPeer = host?.peer_id !== undefined ? String(host.peer_id) : null;
  for (const r of Array.isArray(host?.directives) ? host.directives : []) {
    if (!isObj(r) || r.peer === undefined || r.id === undefined) continue;
    const target = String(r.peer);
    if (target === hostPeer || Number(target) < 0) continue; // the host's own rider or a bot
    const owner = idsByPeerId.get(target);
    if (!owner) continue;
    if (!owner.ids.has(String(r.id))) {
      const msg = `directive ${r.id} for peer ${target} has no applied record in ${owner.role}'s report`;
      if (partial.includes(owner.role)) warnings.push(msg);
      else problems.push(msg);
    }
  }
  return { ok: problems.length === 0, total, problems, warnings };
}

/** Lines that fail an e2e run: script errors, parse errors, push_error output, debugger breaks. */
export const ERROR_LINE_RE = /SCRIPT ERROR|Parse Error|Debugger Break|^\s*(USER )?ERROR:|Ignoring script/;
export const DESYNC_LINE_RE = /^\s*(USER )?WARNING:.*\bdesync/i;
export const RATE_LIMITED_RE = /rate_limited/;
export const REFUSED_RE = /session_in_progress/;

/** Problem lines in a peer's output (stdout, stderr and its Godot log). */
export function scanLog(lines) {
  const out = { errors: [], desync: [], rateLimited: [], refused: [] };
  for (const raw of lines) {
    const line = String(raw);
    if (ERROR_LINE_RE.test(line)) out.errors.push(line);
    if (DESYNC_LINE_RE.test(line)) out.desync.push(line);
    if (RATE_LIMITED_RE.test(line)) out.rateLimited.push(line);
    if (REFUSED_RE.test(line)) out.refused.push(line);
  }
  return out;
}

/** A listening port in a line of server output (a URL, "port 1234" or {"port": 1234}). */
export function parsePort(line) {
  const s = String(line).trim();
  const valid = (p) => Number.isInteger(p) && p > 0 && p < 65536;
  if (s.startsWith('{')) {
    try {
      const j = JSON.parse(s);
      const p = Number(j.port ?? j.listening?.port ?? j.address?.port);
      if (valid(p)) return p;
      if (typeof j.url === 'string') return parsePort(j.url);
    } catch {
      // not JSON after all
    }
  }
  let m = /https?:\/\/(?:127\.0\.0\.1|localhost|\[::1\]|0\.0\.0\.0):(\d{1,5})/i.exec(s);
  if (m && valid(Number(m[1]))) return Number(m[1]);
  m = /\bport\b\D{0,3}(\d{2,5})\b/i.exec(s);
  if (m && valid(Number(m[1]))) return Number(m[1]);
  m = /\blistening\b.*?:(\d{2,5})\b/i.exec(s);
  if (m && valid(Number(m[1]))) return Number(m[1]);
  return null;
}

/** The uploads in a mock admin response: an array, {uploads|items|data: [...]}, or {count}. */
export function parseUploads(json) {
  if (Array.isArray(json)) return json;
  if (isObj(json)) {
    for (const k of ['uploads', 'items', 'data', 'results']) if (Array.isArray(json[k])) return json[k];
    const c = num(json.count ?? json.total);
    if (c !== null) return Array.from({ length: c }, () => ({}));
  }
  return null;
}

/** Wall time spent on the session excluding the cool-down. */
export function durationExclCooldown(totalS, cooldownObservedS, cooldownDefaultS) {
  const cd = Number.isFinite(cooldownObservedS) && cooldownObservedS > 0 ? cooldownObservedS : cooldownDefaultS;
  return Math.max(0, totalS - cd);
}

/**
 * The cool-down's wall time from a peer's stdout lines [{t, line}]: from WATTLANDS_STATE cooldown
 * to the next WATTLANDS_STATE line (or the last line). null when the peer never reported it.
 */
export function observedCooldownS(entries) {
  let start = null;
  for (const e of entries) {
    const m = /^WATTLANDS_STATE\s+(\S+)/.exec(e.line);
    if (!m) continue;
    if (start === null && /^cool[_-]?down$/i.test(m[1])) start = e.t;
    else if (start !== null && !/^cool[_-]?down$/i.test(m[1])) return e.t - start;
  }
  if (start === null) return null;
  const last = entries.length ? entries[entries.length - 1].t : start;
  return last - start;
}

/** Upload checks: exactly one mock upload, made by the auto-upload peer and by nobody else. */
export function checkUploads(mockUploads, peers, autoRole) {
  const details = [];
  let ok = true;
  if (!Array.isArray(mockUploads)) {
    return { ok: false, details: ['the mock Strava server listed no uploads (admin API unavailable)'] };
  }
  if (mockUploads.length !== 1) {
    ok = false;
    details.push(`the mock Strava server holds ${mockUploads.length} uploads, expected exactly 1`);
  } else {
    details.push('the mock Strava server holds exactly 1 upload');
  }
  for (const [role, p] of Object.entries(peers)) {
    const ups = Array.isArray(p?.uploads) ? p.uploads : [];
    if (role === autoRole) {
      const good = ups.filter((u) => isObj(u) && /^(uploaded|duplicate|ready|done|complete)$/i.test(String(u.state ?? '')));
      if (ups.length !== 1 || good.length !== 1) {
        ok = false;
        details.push(`${role} (auto-upload) reported ${ups.length} upload(s) (${ups.map((u) => u?.state).join(', ') || 'none'}), expected one finished upload`);
      } else {
        details.push(`${role} uploaded (activity ${good[0].activity_id ?? '?'})`);
      }
    } else if (ups.length > 0) {
      ok = false;
      details.push(`${role} reported ${ups.length} upload(s) but auto-upload was off for it`);
    }
  }
  return { ok, details };
}
