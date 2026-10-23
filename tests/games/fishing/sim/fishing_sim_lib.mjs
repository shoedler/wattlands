// tests/games/fishing/sim/fishing_sim_lib.mjs: shared pieces of Big Game Fishing's report checkers
// (check_sims.mjs over tools/run_game_sim reports, ../e2e_check.mjs over tools/e2e reports).
// Zero dependencies, so `node --test` in tests/games/fishing runs anywhere.
//
// Sources: the event schema is src/games/fishing/contracts/fishing_events.gd (FishingEvents),
// species indexes FishingConst.SPECIES, the clamp rule names addons/wattlands/contracts/wl.gd
// (CLAMP_*), the report layout docs/GAME_SDK.md 19.1 and 19.4.

/** FishingConst.SPECIES, in index order (`sp` in events). */
export const SPECIES = ['mackerel', 'mahi', 'tuna', 'marlin'];
export const SP = Object.freeze({ mackerel: 0, mahi: 1, tuna: 2, marlin: 3 });
/** FishingConst.GRADE_TROPHY / GRADE_LANDED (`grade` in landed). */
export const GRADE_TROPHY = 1;
export const GRADE_LANDED = 0;

/** FishingEvents.INT_FIELDS ("name[]" is an array of ints). */
export const INT_FIELDS = Object.freeze({
  cast: ['l', 'spot', 'st', 'd'],
  bite: ['l', 'sp'],
  strike_ok: ['l', 'sp'],
  strike_miss: ['l', 'sp'],
  hookup: ['l', 'sp', 'n', 'sch'],
  run: ['l', 'k', 'n', 'ms'],
  jump: ['l', 'k', 'n', 'ms', 'leaps'],
  snap: ['l'],
  thrown: ['l'],
  replacement: ['l', 'sp'],
  landing: ['l', 'sp'],
  landed: ['l', 'sp', 'grade', 'kg', 'points', 'hk'],
  double_hookup: ['lanes[]', 'lvl'],
  frenzy: ['l', 'ms'],
  trip_over: [],
});
export const EVENT_TYPES = Object.keys(INT_FIELDS);

/**
 * Governor clamp rules a Fishing directive or plan target may show (brief 6 "Directives"):
 * slew (4.6.2), the floor and the unverified-FTP factor (4.6.1), rescue (4.6.3), coasting (4.6.4),
 * haptic intensity (4.6.6) and the warm-up clamp (4.6.8). switch_ramp (the ramped ERG<->SIM entry,
 * BRIEF 4.5) and paused are allowed and reported. Everything else fails, and these four are what
 * the brief names explicitly: the absolute ceiling, the 105% long-phase cap and the duration limits.
 */
export const ALLOWED_CLAMPS = new Set(['slew', 'floor', 'unverified', 'rescue', 'coasting', 'haptic_intensity', 'warmup']);
export const NOTED_CLAMPS = new Set(['switch_ramp', 'paused']);
export const FORBIDDEN_CLAMPS = new Set(['ceiling', 'long_phase', 'limit_105', 'limit_120']);
/** Scenario 1 is stricter: "applied unchanged apart from slew, the floor, the unverified-FTP factor and haptic intensity". */
export const S1_CLAMPS = new Set(['slew', 'floor', 'unverified', 'haptic_intensity']);

/** Brief 2.3: every ERG directive is {mode: ERG, target_pct, duration_s, reason, source: "fishing"}. */
export const ERG_KEYS = ['duration_s', 'mode', 'reason', 'source', 'target_pct'];
export const ERG_REASONS = new Set(['pull', 'run', 'jump']);
/** Brief 2.7: the Landing's one haptic directive. */
export const HAPTIC = Object.freeze({ mode: 'SIM', haptic: 3.0, duration_s: 5, reason: 'last_run', source: 'fishing' });
export const SELF_CAP_PCT = 110;
export const MAX_SNAPSHOT_BYTES = 2048;
export const EPS = 1e-6;

export const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
export const isInt = (v) => typeof v === 'number' && Number.isInteger(v);
export const sum = (a) => a.reduce((x, y) => x + y, 0);
export const fmt = (n) => (Number.isFinite(n) ? String(Math.round(n * 100) / 100) : String(n));

export function median(values) {
  if (values.length === 0) return NaN;
  const s = [...values].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

/** The Fishing event in a report entry (a game_event wrapper or a raw event), else null. */
export function asFishingEvent(x) {
  if (!isObj(x)) return null;
  if (x.type === 'game_event' && isObj(x.event)) return EVENT_TYPES.includes(x.event.type) ? x.event : null;
  if (EVENT_TYPES.includes(x.type) && !('event' in x)) return x;
  return null;
}

/** The Fishing game events of an event list in order, each with `_t` (the wrapper's time). */
export function fishingEvents(list) {
  const out = [];
  for (const x of Array.isArray(list) ? list : []) {
    const e = asFishingEvent(x);
    if (e) out.push({ ...e, _t: Number(x.t ?? NaN) });
  }
  return out;
}

/** Problems with one Fishing event: a known type, every declared int field present and an int. */
export function eventErrors(e) {
  const type = String(e?.type);
  if (!EVENT_TYPES.includes(type)) return [`unknown event type ${JSON.stringify(e?.type)}`];
  const errs = [];
  for (const f of INT_FIELDS[type]) {
    const key = f.replace('[]', '');
    if (!(key in e)) errs.push(`${type}: missing ${key}`);
    else if (f.endsWith('[]')) {
      if (!Array.isArray(e[key]) || !e[key].every(isInt)) errs.push(`${type}: ${key} is not an array of ints`);
    } else if (!isInt(e[key])) errs.push(`${type}: ${key} is not an int (${JSON.stringify(e[key])})`);
  }
  if (errs.length) return errs;
  if ('l' in e && (e.l < 0 || e.l > 3)) errs.push(`${type}: lane ${e.l} outside 0..3`);
  if ('sp' in e && (e.sp < 0 || e.sp >= SPECIES.length)) errs.push(`${type}: species ${e.sp} outside 0..3`);
  if (type === 'landed' && e.grade !== GRADE_TROPHY && e.grade !== GRADE_LANDED) errs.push(`landed: grade ${e.grade}`);
  if (type === 'landed' && ![10, 15, 20, 25].includes(e.hk)) errs.push(`landed: hk ${e.hk} (10, 15, 20 or 25)`);
  if (type === 'double_hookup' && (e.lvl < 2 || e.lvl > 4 || e.lanes.length < e.lvl || e.lanes.length > 4)) errs.push(`double_hookup: lvl ${e.lvl} with lanes ${JSON.stringify(e.lanes)}`);
  return errs;
}

/** Clamp problems of one clamped_by list: `allowed` (default ALLOWED_CLAMPS) plus the noted ones. */
export function clampProblems(list, allowed = ALLOWED_CLAMPS) {
  const out = [];
  for (const c of Array.isArray(list) ? list : []) {
    if (allowed.has(c) || NOTED_CLAMPS.has(c)) continue;
    out.push(FORBIDDEN_CLAMPS.has(c) ? `clamped_by ${c} (forbidden: brief 6)` : `clamped_by ${c} (not an allowed rule)`);
  }
  return out;
}

/** Problems with the requested side of one Fishing request (the keys and values of brief 2.3 / 2.7). */
export function requestShapeProblems(req) {
  if (!isObj(req)) return ['no requested directive'];
  const r = { ...req };
  delete r.id;
  if (r.mode === 'SIM') {
    const probs = [];
    for (const [k, v] of Object.entries(HAPTIC)) if (r[k] !== v) probs.push(`haptic directive ${k} ${JSON.stringify(r[k])}, wanted ${JSON.stringify(v)}`);
    return probs;
  }
  const probs = [];
  const keys = Object.keys(r).sort();
  if (JSON.stringify(keys) !== JSON.stringify(ERG_KEYS)) probs.push(`keys ${keys.join(',')}, wanted ${ERG_KEYS.join(',')}`);
  if (r.mode !== 'ERG') probs.push(`mode ${JSON.stringify(r.mode)}`);
  if (r.source !== 'fishing') probs.push(`source ${JSON.stringify(r.source)}`);
  if (!ERG_REASONS.has(r.reason)) probs.push(`reason ${JSON.stringify(r.reason)} (pull, run or jump)`);
  if (typeof r.target_pct !== 'number' || r.target_pct < 50 - EPS || r.target_pct > SELF_CAP_PCT + EPS) probs.push(`target_pct ${r.target_pct} outside 50..${SELF_CAP_PCT}`);
  if (typeof r.duration_s !== 'number' || r.duration_s < 0) probs.push(`duration_s ${r.duration_s}`);
  return probs;
}

/** Problems with the applied record of a request (null when it never arrived). */
export function appliedProblems(rec, allowed = ALLOWED_CLAMPS) {
  if (!isObj(rec)) return ['no applied record'];
  const probs = [];
  if (rec.refused === true) probs.push(`refused by the governor (${rec.reason})`);
  if (!Array.isArray(rec.clamped_by)) probs.push('the applied record has no clamped_by list');
  probs.push(...clampProblems(rec.clamped_by, allowed));
  return probs;
}

/** Expected FIT laps of one rider's run (ADR G0.2): lap-true phases that started, the cool-down's
 *  lap counted only when the run completed (the platform always adds it). */
export function expectedLaps(report, peer) {
  const plan = report.plans?.[String(peer)]?.phases ?? [];
  const spans = report.phases?.[String(peer)] ?? [];
  let n = 0;
  for (const s of spans) {
    const ph = plan[s.index];
    if (!ph || !ph.lap) continue;
    if (ph.kind === 'COOLDOWN') continue;
    n += 1;
  }
  if (report.end_reason === 'complete') n += 1;
  return n;
}
