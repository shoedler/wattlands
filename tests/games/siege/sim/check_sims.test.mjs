// node --test tests/games/siege/sim/check_sims.test.mjs: check_sims.mjs on small synthetic
// reports (a passing and a failing case per scenario), plus the CLI.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import * as cs from './check_sims.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

// --- synthetic reports -----------------------------------------------------------------------------

const W = (d, n) => ({ role: 'wave', kind: 'WORK', d, n });
const BR = (d, n) => ({ role: 'break', kind: 'RECOVERY', d, n });
const WARM = { role: 'warmup_wave', kind: 'WARMUP', d: 300, n: 0 };
const BUILD = { role: 'build_break', kind: 'RECOVERY', d: 120, n: 0 };
const COOL = { role: 'cooldown', kind: 'COOLDOWN', d: 180, n: 0 };

const SHAPES = {
  short: [WARM, BUILD, W(300, 1), BR(180, 1), W(300, 2), BR(180, 2), W(300, 3), COOL],
  vo2: [
    WARM, BUILD,
    ...[1, 2, 3, 4, 5, 6].flatMap((n) => (n < 6 ? [W(120, n), BR(180, n)] : [W(120, n)])),
    COOL,
  ],
  sweetspot: [WARM, BUILD, W(900, 1), BR(300, 1), W(900, 2), COOL],
  endurance: [WARM, BUILD, W(2700, 1), COOL],
  drill: [
    { role: 'build_break', kind: 'WARMUP', d: 20, n: 0 },
    { role: 'wave', kind: 'WARMUP', d: 100, n: 1 },
    COOL,
  ],
};
const BASE_PCT = { short: 95, vo2: 112, sweetspot: 90, endurance: 70, drill: 60 };

function planOf(content, offset = 0) {
  return {
    cooldown_appended: true,
    phases: SHAPES[content].map((p) => {
      let target = 50;
      if (p.role === 'wave') {
        target = BASE_PCT[content];
        if (p.kind === 'WORK') target = Math.min(Math.max(target + offset, 50), p.d > 240 ? 105 : 117);
      }
      const ph = { kind: p.kind, mode: 'ERG', target_pct: target, duration_s: p.d, lap: true, label: `${p.role} ${p.n}` };
      if (p.role !== 'cooldown') ph.meta = { role: p.role, number: p.n };
      return ph;
    }),
  };
}

function spansOf(content) {
  let t = 0;
  return SHAPES[content].map((p, i) => {
    const s = { index: i, kind: p.kind, mode: 'ERG', label: `${p.role} ${p.n}`, start: t, end: t + p.d, ended_by: 'duration' };
    t += p.d;
    return s;
  });
}

const ge = (t, event) => ({ type: 'game_event', t, pt: t, event });

function report(o = {}) {
  const content = o.content ?? 'short';
  const players = o.players ?? 4;
  const bots = o.bots ?? 0;
  const slots = [];
  for (let i = 0; i < players + bots; i++) {
    slots.push({ slot: i, peer: i < players ? i + 1 : -(i - players + 1), is_bot: i >= players, ftp: 200, ftp_verified: true });
  }
  const plans = {};
  const phases = {};
  const offsets = o.offsets ?? [];
  for (const s of slots) {
    plans[String(s.peer)] = planOf(content, s.is_bot ? 0 : offsets[s.slot] ?? 0);
    phases[String(s.peer)] = spansOf(content);
  }
  return {
    schema: 1,
    game_id: 'siege',
    content_id: content,
    role: o.role ?? (players > 1 ? 'HOST' : 'SOLO'),
    seed: o.seed ?? 1,
    args: { game: 'siege', content, players, bots, seed: o.seed ?? 1, player_options: o.playerOptions ?? [] },
    slots,
    plans,
    plan_warnings: Object.fromEntries(slots.map((s) => [String(s.peer), []])),
    end_reason: o.end ?? 'complete',
    finished_reason: o.finished ?? 'complete',
    events: o.events ?? [],
    phases,
    directives: o.directives ?? [],
    directives_unmatched: [],
    trace: o.trace ?? {},
    snapshots: [],
    max_snapshot_bytes: o.maxBytes ?? 1200,
    oversize_snapshots: 0,
    results: { score: o.score ?? 75, grade: 'B' },
    fit_paths: slots.filter((s) => !s.is_bot).map((s) => `/x/fit/${s.peer}.fit`),
    deterministic_hash: o.hash ?? 'abc',
  };
}

const named = (entries) => Object.fromEntries(entries);
const by = (rs, id) => rs.find((r) => r.id === id);

function s9set(over = {}) {
  const set = {};
  for (const c of cs.CONTENTS) {
    for (const n of [1, 2, 3]) {
      set[`s9_${c}_seed${n}`] = report({ content: c, seed: n, score: 75, ...(over[c] ?? {}) });
    }
  }
  return set;
}

// --- loading ---------------------------------------------------------------------------------------

test('loadReports reads Siege reports only', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'cs-'));
  fs.writeFileSync(path.join(d, 'a.json'), JSON.stringify(report()));
  fs.writeFileSync(path.join(d, 'b.json'), JSON.stringify({ schema: 1, game_id: 'workout' }));
  fs.writeFileSync(path.join(d, 'c.txt'), 'x');
  assert.deepEqual(Object.keys(cs.loadReports(d)), ['a']);
  fs.writeFileSync(path.join(d, 'bad.json'), '{');
  assert.throws(() => cs.loadReports(d), /bad.json/);
});

// --- S1, S2 ------------------------------------------------------------------------------------------

test('S1 passes with at most one Breach per run and a mean score in 64-89', () => {
  const set = {};
  for (const n of [1, 2, 3]) {
    set[`s9_short_seed${n}`] = report({ seed: n, score: 70 + n, events: n === 2 ? [ge(500, { type: 'breach', n: 1 })] : [] });
  }
  const r = cs.checkS1(set);
  assert.equal(r.status, 'PASS', r.details.join('\n'));
});

test('S1 fails on two Breaches, on a low mean score and on a missing seed', () => {
  const two = report({ seed: 1, events: [ge(500, { type: 'breach', n: 1 }), ge(700, { type: 'breach', n: 2 })] });
  let r = cs.checkS1({ s9_short_seed1: two, s9_short_seed2: report({ seed: 2 }), s9_short_seed3: report({ seed: 3 }) });
  assert.equal(r.status, 'FAIL');
  assert.match(r.details.join('\n'), /2 Breaches/);
  r = cs.checkS1(named([1, 2, 3].map((n) => [`s9_short_seed${n}`, report({ seed: n, score: 50 })])));
  assert.match(r.details.join('\n'), /T1: mean score 50 outside 64-89/);
  r = cs.checkS1(named([1, 2].map((n) => [`s9_short_seed${n}`, report({ seed: n })])));
  assert.match(r.details.join('\n'), /missing report s9_short_seed3/);
  r = cs.checkS1({});
  assert.equal(r.status, 'SKIP');
});

test('the seeds option narrows S1, S2, S4 and S9 to the seeds that were run', () => {
  const one = { s9_short_seed1: report({ seed: 1, score: 75 }) };
  assert.equal(cs.checkS1(one).status, 'FAIL', 'three seeds by default');
  assert.equal(cs.checkS1(one, { seeds: [1] }).status, 'PASS');
  const s2 = {};
  for (const [v, [p, b]] of Object.entries(cs.S2_VARIANTS)) s2[`s2_short_${v}_seed1`] = report({ players: p, bots: b, seed: 1, score: 80 });
  assert.equal(cs.checkS2(s2, { seeds: [1] }).status, 'PASS');
  const s4 = { s9_short_seed1: report({ score: 80 }), s4_short_c90_seed1: report({ score: 70 }), s4_short_c80_seed1: report({ score: 60 }) };
  assert.equal(cs.checkS4(s4, { seeds: [1] }).status, 'PASS');
  const s9 = {};
  for (const c of cs.CONTENTS) s9[`s9_${c}_seed1`] = report({ content: c, score: 75 });
  assert.match(cs.checkS9(s9, { seeds: [1] }).details.join(' '), /no ram was ever pushed/);
  assert.doesNotMatch(cs.checkS9(s9, { seeds: [1] }).details.join(' '), /missing report/);
});

test('S1 rejects a report that was not 4 riders or did not complete', () => {
  const set = named([1, 2, 3].map((n) => [`s9_short_seed${n}`, report({ seed: n, players: n === 1 ? 2 : 4, end: n === 3 ? 'paused' : 'complete' })]));
  const d = cs.checkS1(set).details.join('\n');
  assert.match(d, /players 2, wanted 4/);
  assert.match(d, /end_reason paused/);
});

test('S2 checks each variant for Breaches and T1', () => {
  const set = {};
  for (const [v, [p, b]] of Object.entries(cs.S2_VARIANTS)) {
    for (const n of [1, 2, 3]) set[`s2_short_${v}_seed${n}`] = report({ players: p, bots: b, seed: n, score: 80 });
  }
  assert.equal(cs.checkS2(set).status, 'PASS', cs.checkS2(set).details.join('\n'));
  set.s2_short_2h_seed2 = report({ players: 2, seed: 2, score: 20 });
  set.s2_short_2h_seed3 = report({ players: 2, seed: 3, score: 20 });
  const r = cs.checkS2(set);
  assert.equal(r.status, 'FAIL');
  assert.match(r.details.join('\n'), /2h: T1/);
});

// --- S3 ------------------------------------------------------------------------------------------------

test('S3 wants a Breach inside the first full wave of every zero-input run', () => {
  const ok = named(cs.CONTENTS.map((c) => [`s3_${c}_zero`, report({ content: c, events: [ge(500, { type: 'breach', n: 1 })] })]));
  assert.equal(cs.checkS3(ok).status, 'PASS', cs.checkS3(ok).details.join('\n'));
  const early = { ...ok, s3_short_zero: report({ content: 'short', events: [ge(100, { type: 'breach', n: 1 })] }) };
  assert.match(cs.checkS3(early).details.join('\n'), /s3_short_zero: no Breach in wave 1/);
  const none = { ...ok, s3_vo2_zero: report({ content: 'vo2', events: [] }) };
  assert.equal(cs.checkS3(none).status, 'FAIL');
  const late = { ...ok, s3_vo2_zero: report({ content: 'vo2', events: [ge(700, { type: 'breach', n: 1 })] }) };
  assert.equal(cs.checkS3(late).status, 'FAIL', 'wave 1 of vo2 is 420-540 s');
});

// --- S4 --------------------------------------------------------------------------------------------------

test('S4 wants the mean score to fall strictly with compliance', () => {
  const mk = (a, b, c) => {
    const set = {};
    for (const n of [1, 2, 3]) {
      set[`s9_short_seed${n}`] = report({ seed: n, score: a });
      set[`s4_short_c90_seed${n}`] = report({ seed: n, score: b });
      set[`s4_short_c80_seed${n}`] = report({ seed: n, score: c });
    }
    return set;
  };
  assert.equal(cs.checkS4(mk(80, 70, 60)).status, 'PASS');
  const eq = cs.checkS4(mk(80, 80, 60));
  assert.equal(eq.status, 'FAIL');
  assert.match(eq.details.join('\n'), /100% \(80\) is not above 90% \(80\)/);
  assert.equal(cs.checkS4(mk(80, 70, 70)).status, 'FAIL');
  assert.equal(cs.checkS4({}).status, 'SKIP');
});

// --- S5 --------------------------------------------------------------------------------------------------

const OD = { mode: 'SIM', duration_s: 30, reason: 'overdrive', source: 'siege' };
function odDirective(id, peer, t, phase, over = {}) {
  return {
    id, peer, t, kind: 'request', requested: { ...OD, id }, accepted: true, reason: '',
    applied: { id, kind: 'request', refused: false, reason: '', clamped_by: [], t, game_t: t, phase_index: phase, applied: { sim_block: true, duration_s: 30, grade_pct: 0 }, ...over },
  };
}

test('S5 passes a clean run and checks every part', () => {
  const r = report({ content: 'drill', players: 1, directives: [] });
  assert.equal(cs.checkS5({ s5_drill: r }).status, 'PASS');
  assert.equal(cs.planLaps(r), 3);
  assert.equal(cs.planLaps(report({ content: 'vo2' })), 14);
  assert.equal(cs.planLaps(report({ content: 'short' })), 8);
  assert.equal(cs.planLaps(report({ content: 'sweetspot' })), 6);
  assert.equal(cs.planLaps(report({ content: 'endurance' })), 4);
});

test('S5 fails directives that are not exactly the Overdrive block', () => {
  const extra = odDirective(1, 1, 500, 2);
  extra.requested.mode_grade = 2;
  let d = cs.checkS5({ r: report({ directives: [extra] }) }).details.join('\n');
  assert.match(d, /keys duration_s,mode,mode_grade,reason,source/);
  const wrong = odDirective(2, 1, 500, 2);
  wrong.requested.duration_s = 20;
  d = cs.checkS5({ r: report({ directives: [wrong] }) }).details.join('\n');
  assert.match(d, /duration_s 20, wanted 30/);
  const other = { id: 3, peer: 1, t: 1, kind: 'cadence_band', requested: {}, accepted: true, applied: null };
  assert.match(cs.checkS5({ r: report({ directives: [other] }) }).details.join('\n'), /kind cadence_band/);
  const refused = odDirective(4, 1, 500, 2, { refused: true, reason: 'switch_spacing' });
  assert.match(cs.checkS5({ r: report({ directives: [refused] }) }).details.join('\n'), /refused by the governor/);
  const unclamped = odDirective(5, 1, 500, 2);
  delete unclamped.applied.clamped_by;
  assert.match(cs.checkS5({ r: report({ directives: [unclamped] }) }).details.join('\n'), /no clamped_by/);
  const dropped = odDirective(6, 1, 500, 2, { dropped: [{ channel: 'haptic' }] });
  assert.match(cs.checkS5({ r: report({ directives: [dropped] }) }).details.join('\n'), /dropped channels/);
});

test('S5 holds the warm-up limits against the trace', () => {
  const rows = (mutate) => ({
    1: Array.from({ length: 400 }, (_, i) => mutate({ t: i, game_t: i, mode: 'ERG', applied_pct: 60, haptic: 0, rescue: false, phase: 0, clamped_by: [] }, i)),
  });
  assert.equal(cs.checkS5({ r: report({ players: 1, trace: rows((x) => x) }) }).status, 'PASS');
  let d = cs.checkS5({ r: report({ players: 1, trace: rows((x, i) => (i === 100 ? { ...x, applied_pct: 70 } : x)) }) }).details.join('\n');
  assert.match(d, /at 70% FTP at 100 s \(warm-up max 65\)/);
  d = cs.checkS5({ r: report({ players: 1, trace: rows((x, i) => (i === 10 ? { ...x, mode: 'SIM' } : x)) }) }).details.join('\n');
  assert.match(d, /in SIM at 10 s/);
  d = cs.checkS5({ r: report({ players: 1, trace: rows((x, i) => (i === 350 ? { ...x, applied_pct: 118 } : x)) }) }).details.join('\n');
  assert.match(d, /max 117/);
  d = cs.checkS5({ r: report({ players: 1, trace: rows((x, i) => (i === 350 ? { ...x, haptic: 0.5 } : x)) }) }).details.join('\n');
  assert.match(d, /haptics/);
  // 70% is fine after the warm-up.
  assert.equal(cs.checkS5({ r: report({ players: 1, trace: rows((x, i) => (i === 350 ? { ...x, applied_pct: 70 } : x)) }) }).status, 'PASS');
});

test('S5 fails plan warnings, wrong laps, wrong offsets, big snapshots and runs that did not complete', () => {
  const warn = report({ players: 1 });
  warn.plan_warnings['1'] = ['a warning'];
  assert.match(cs.checkS5({ r: warn }).details.join('\n'), /plan warnings/);
  const laps = report({ content: 'vo2', players: 1 });
  laps.plans['1'].phases.pop();
  assert.match(cs.checkS5({ r: laps }).details.join('\n'), /plan has 13 laps, wanted 14/);
  const big = report({ players: 1, maxBytes: 9000 });
  assert.match(cs.checkS5({ r: big }).details.join('\n'), /largest snapshot 9000 B/);
  assert.match(cs.checkS5({ r: report({ players: 1, end: 'timeout' }) }).details.join('\n'), /end_reason timeout/);
  const offs = report({ content: 'vo2', offsets: [5, -10, 0, 5], playerOptions: [{ wave_offset: 5 }, { wave_offset: -10 }, { wave_offset: 0 }, { wave_offset: 5 }] });
  assert.equal(cs.checkS5({ r: offs }).status, 'PASS');
  assert.deepEqual(offs.plans['1'].phases.filter((p) => p.kind === 'WORK').map((p) => p.target_pct), [117, 117, 117, 117, 117, 117]);
  assert.deepEqual(offs.plans['2'].phases.filter((p) => p.kind === 'WORK').map((p) => p.target_pct), [102, 102, 102, 102, 102, 102]);
  offs.plans['2'].phases.find((p) => p.kind === 'WORK').target_pct = 112;
  assert.match(cs.checkS5({ r: offs }).details.join('\n'), /peer 2 wave target 112%, wanted 102% \(offset -10\)/);
  const over = report({ content: 'short', players: 1 });
  over.plans['1'].phases[2].target_pct = 110;
  assert.match(cs.checkS5({ r: over }).details.join('\n'), /50\.\.105/);
});

// --- S6 --------------------------------------------------------------------------------------------------

test('S6 wants a rescue after the collapse and every phase to run on', () => {
  const rescue = { type: 'rescue', t: 1230, pt: 1230, peer: 1, active: true };
  const ok = report({ content: 'sweetspot', events: [rescue] });
  assert.equal(cs.checkS6({ s6_sweetspot_cadence_drop: ok }).status, 'PASS');
  assert.equal(cs.checkS6({}).status, 'SKIP');
  const none = report({ content: 'sweetspot' });
  assert.match(cs.checkS6({ s6_sweetspot_cadence_drop: none }).details.join('\n'), /rescue never triggered/);
  const early = report({ content: 'sweetspot', events: [{ ...rescue, t: 900 }] });
  assert.match(cs.checkS6({ s6_sweetspot_cadence_drop: early }).details.join('\n'), /before the cadence collapse/);
  const skipped = report({ content: 'sweetspot', events: [rescue] });
  skipped.phases['1'][2].ended_by = 'end_phase';
  assert.match(cs.checkS6({ s6_sweetspot_cadence_drop: skipped }).details.join('\n'), /ended by "end_phase"/);
  const fewer = report({ content: 'sweetspot', events: [rescue] });
  fewer.phases['1'].splice(3, 1);
  assert.match(cs.checkS6({ s6_sweetspot_cadence_drop: fewer }).details.join('\n'), /phases ran/);
  const traceOnly = report({ content: 'sweetspot', trace: { 1: [{ game_t: 1300, t: 1300, rescue: true, mode: 'ERG' }] } });
  assert.equal(cs.checkS6({ s6_sweetspot_cadence_drop: traceOnly }).status, 'PASS');
});

// --- S7 --------------------------------------------------------------------------------------------------

test('S7 wants the same hash and the same game events', () => {
  const ev = [ge(430, { type: 'wave_start', n: 1 }), ge(540, { type: 'wave_end', n: 1 })];
  const a = report({ content: 'vo2', events: ev, hash: 'h1' });
  const b = report({ content: 'vo2', events: ev, hash: 'h1' });
  assert.equal(cs.checkS7({ s7_vo2_seed1: a, s9_vo2_seed1: b }).status, 'PASS');
  const c = report({ content: 'vo2', events: ev, hash: 'h2' });
  assert.match(cs.checkS7({ s7_vo2_seed1: a, s9_vo2_seed1: c }).details.join('\n'), /deterministic_hash differs/);
  const d = report({ content: 'vo2', events: ev.slice(0, 1), hash: 'h1' });
  assert.match(cs.checkS7({ s7_vo2_seed1: a, s9_vo2_seed1: d }).details.join('\n'), /game events differ/);
  assert.equal(cs.checkS7({ s7_vo2_seed1: a }).status, 'FAIL');
  assert.equal(cs.checkS7({}).status, 'SKIP');
  const none = report({ content: 'vo2' });
  assert.match(cs.checkS7({ s7_vo2_seed1: none, s9_vo2_seed1: none }).details.join('\n'), /no game events/);
});

// --- S9: T3, T4 ---------------------------------------------------------------------------------------------

/** Events: `leaks` distinct leaking raiders inside wave 1 plus rams pushed / killed / leaked. */
function s9events(content, leaks, rams = { push: 3, killed: 3, leaked: 0 }) {
  const w1 = { short: 430, vo2: 430, sweetspot: 430, endurance: 430 }[content];
  const evs = [];
  for (let i = 0; i < leaks; i++) evs.push(ge(w1 + 10 + i, { type: 'leak', id: 1000 + i, et: 1, road: 0, dmg: 2 }));
  evs.push(ge(w1 + 20, { type: 'push', roads: Array.from({ length: rams.push }, (_, i) => i) }));
  for (let i = 0; i < rams.killed; i++) evs.push(ge(w1 + 30 + i, { type: 'kill', id: 50 + i, et: 4, pad: 3, road: 0, x2: 0 }));
  for (let i = 0; i < rams.leaked; i++) {
    evs.push(ge(w1 + 40 + i, { type: 'leak', id: 70 + i, et: 4, road: 0, dmg: 1 }));
    evs.push(ge(w1 + 41 + i, { type: 'leak', id: 70 + i, et: 4, road: 0, dmg: 1 }));
  }
  return evs;
}

test('leakStats counts distinct enemies inside waves per wave-minute', () => {
  const r = report({ content: 'short', events: [...s9events('short', 3, { push: 0, killed: 0, leaked: 1 }), ge(10, { type: 'leak', id: 9, et: 1, road: 0, dmg: 2 })] });
  const s = cs.leakStats(r);
  assert.equal(s.minutes, 15, '3 waves of 5 min');
  assert.equal(s.leaks, 4, '3 raiders + 1 ram that battered twice; the warm-up leak at 10 s is outside a wave');
  assert.equal(s.rate, 4 / 15);
});

test('ramStats: stopped = killed rams that never leaked', () => {
  const r = report({ events: s9events('short', 0, { push: 4, killed: 3, leaked: 1 }) });
  assert.deepEqual(cs.ramStats(r), { spawned: 4, stopped: 3, leaked: 1 });
});

test('S9 passes when leak rates are within +-30% and 70% of rams are stopped', () => {
  const set = s9set({
    short: { events: s9events('short', 3) },
    vo2: { events: s9events('vo2', 1) },
    sweetspot: { events: s9events('sweetspot', 9) },
    endurance: { events: s9events('endurance', 20) },
  });
  // rates: short 3/15=.2, vo2 1/12=.083, sweetspot 9/30=.3, endurance 20/45=.44: too spread.
  assert.equal(cs.checkS9(set).status, 'FAIL');
  const flat = s9set({
    short: { events: s9events('short', 3) },
    vo2: { events: s9events('vo2', 2) },
    sweetspot: { events: s9events('sweetspot', 6) },
    endurance: { events: s9events('endurance', 9) },
  });
  // .2, .167, .2, .2
  const r = cs.checkS9(flat);
  assert.equal(r.status, 'PASS', r.details.join('\n'));
});

test('S9 fails a spread over 30%, too few rams stopped and no rams at all', () => {
  const spread = s9set({
    short: { events: s9events('short', 3) },
    vo2: { events: s9events('vo2', 2) },
    sweetspot: { events: s9events('sweetspot', 6) },
    endurance: { events: s9events('endurance', 18) },
  });
  assert.match(cs.checkS9(spread).details.join('\n'), /T3: endurance/);
  const weak = s9set({
    short: { events: s9events('short', 3, { push: 4, killed: 2, leaked: 2 }) },
    vo2: { events: s9events('vo2', 2, { push: 4, killed: 2, leaked: 2 }) },
    sweetspot: { events: s9events('sweetspot', 6, { push: 4, killed: 2, leaked: 2 }) },
    endurance: { events: s9events('endurance', 9, { push: 4, killed: 2, leaked: 2 }) },
  });
  assert.match(cs.checkS9(weak).details.join('\n'), /T4: 24\/48 rams stopped/);
  assert.match(cs.checkS9(s9set()).details.join('\n'), /no ram was ever pushed/);
  assert.equal(cs.checkS9({}).status, 'SKIP');
  // all zero leaks is within any spread.
  const zero = s9set({
    short: { events: s9events('short', 0) },
    vo2: { events: s9events('vo2', 0) },
    sweetspot: { events: s9events('sweetspot', 0) },
    endurance: { events: s9events('endurance', 0) },
  });
  assert.equal(cs.checkS9(zero).status, 'PASS');
});

// --- S10 -------------------------------------------------------------------------------------------------------

/** A vo2 trace for peer 1: ERG rows with `spans` ([from, to]) in SIM and a ramped return. */
function odTrace(spans, over = {}) {
  const rows = [];
  for (let t = 0; t < 2220; t++) {
    const sp = spans.find(([a, b]) => t >= a && t < b);
    const ret = spans.find(([, b]) => t >= b && t < b + 3);
    const phase = spansOf('vo2').find((s) => t >= s.start && t < s.end)?.index ?? 13;
    const plan = planOf('vo2').phases[phase];
    rows.push({
      t, game_t: t, phase, kind: plan.kind, mode: sp ? 'SIM' : 'ERG',
      applied_pct: sp ? 90 : ret ? plan.target_pct - 30 + (t - ret[1]) * 10 : plan.target_pct,
      clamped_by: ret ? ['switch_ramp', 'slew'] : [], rescue: false, haptic: 0, ...(over[t] ?? {}),
    });
  }
  return rows;
}

function s10report(o = {}) {
  // vo2 waves start at 420, 720, 1020, 1320, 1620, 1920 (120 s each).
  const starts = o.starts ?? [430, 730, 1030, 1330, 1630];
  const spans = starts.map((t) => [t, t + 30]);
  const directives = starts.map((t, i) => odDirective(i + 1, 1, t, spansOf('vo2').find((s) => t >= s.start && t < s.end).index));
  return report({
    content: 'vo2',
    directives: o.directives ?? directives,
    events: starts.map((t) => ge(t, { type: 'overdrive', slot: 0, st: 1, scored: 0, why: '' })),
    trace: { 1: odTrace(o.spans ?? spans, o.over ?? {}), ...(o.trace ?? {}) },
  });
}

test('modeSpans and switches read the trace', () => {
  const rows = odTrace([[100, 130], [300, 331]]);
  const sims = cs.modeSpans(rows, 'SIM');
  assert.deepEqual(sims.map((s) => [s.from, s.to]), [[100, 130], [300, 331]]);
  assert.deepEqual(cs.switches(rows).map((s) => [s.t, s.to]), [[100, 'SIM'], [130, 'ERG'], [300, 'SIM'], [331, 'ERG']]);
});

test('S10 passes a run with Overdrives that follow every rule', () => {
  const set = { s10_vo2: s10report(), s10_vo2_offsets: s10report() };
  const r = cs.checkS10(set);
  assert.equal(r.status, 'FAIL', 'the endurance report is missing');
  assert.deepEqual(r.details, ['missing report s10_endurance']);
  assert.deepEqual(cs.overdriveProblems('x', set.s10_vo2), []);
});

test('S10 needs at least 3 Overdrives per run', () => {
  const r = s10report({ starts: [450, 750] });
  const d = cs.overdriveProblems('x', r).join('\n');
  assert.match(d, /2 Overdrive directives \(need 3\+\)/);
  assert.match(d, /2 Overdrive start events/);
});

test('S10 fails a directive with the wrong keys, a refusal or a dropped channel', () => {
  const r = s10report();
  r.directives[0].requested.haptic = 0.3;
  r.directives[1].applied.refused = true;
  r.directives[2].applied.dropped = [{ channel: 'haptic', reason: 'x' }];
  const d = cs.overdriveProblems('x', r).join('\n');
  assert.match(d, /keys duration_s,haptic,mode,reason,source/);
  assert.match(d, /refused by the governor/);
  assert.match(d, /dropped channels/);
});

test('S10 fails an Overdrive outside a WORK phase or with under 30 s left', () => {
  const inBreak = s10report({ starts: [430, 590, 730, 1030, 1330] });
  // 590 s is the first break (540-720): rewrite the directive's phase index to that break.
  inBreak.directives[1].applied.phase_index = 3;
  inBreak.directives[1].applied.game_t = 590;
  assert.match(cs.overdriveProblems('x', inBreak).join('\n'), /in a RECOVERY phase/);
  const late = s10report();
  late.directives[0].applied.game_t = 525;
  assert.match(cs.overdriveProblems('x', late).join('\n'), /with 15 s of .* left \(need 30\)/);
});

test('S10 fails a rescue around an Overdrive, a SIM span that is not 30 s and a bot', () => {
  const resc = s10report({ over: { 440: { rescue: true } } });
  assert.match(cs.overdriveProblems('x', resc).join('\n'), /in rescue around the Overdrive/);
  const long = s10report({ spans: [[450, 485], [560, 590], [750, 780], [1050, 1080], [1350, 1380]] });
  assert.match(cs.overdriveProblems('x', long).join('\n'), /SIM span from 450 s lasted 35 s/);
  const short = s10report({ spans: [[430, 455], [730, 760], [1030, 1060], [1330, 1360], [1630, 1660]] });
  assert.match(cs.overdriveProblems('x', short).join('\n'), /lasted 25 s/);
  const edge = s10report({ spans: [[430, 461], [730, 759], [1030, 1060], [1330, 1360], [1630, 1660]] });
  assert.deepEqual(cs.overdriveProblems('x', edge), [], '30 +- 2 s is fine');
  const bot = s10report();
  bot.directives[0].peer = -1;
  assert.match(cs.overdriveProblems('x', bot).join('\n'), /a bot \(peer -1\) sent an Overdrive/);
  const missing = s10report({ spans: [[430, 460], [1030, 1060], [1330, 1360], [1630, 1660]] });
  assert.match(cs.overdriveProblems('x', missing).join('\n'), /5 Overdrive directives but 4 SIM spans/);
});

test('S10 wants the return to ERG ramped and back at the planned target', () => {
  const noramp = s10report({ over: { 460: { clamped_by: [] }, 461: { clamped_by: [] }, 462: { clamped_by: [] }, 463: { clamped_by: [] } } });
  assert.match(cs.overdriveProblems('x', noramp).join('\n'), /without the ramped switch/);
  const stuck = s10report();
  for (let t = 460; t < 520; t++) stuck.trace[1][t] = { ...stuck.trace[1][t], applied_pct: 70 };
  assert.match(cs.overdriveProblems('x', stuck).join('\n'), /never got back to the planned ERG target/);
});

test('S10 wants 30 s between the return to ERG and the next switch to SIM', () => {
  const close = s10report({ starts: [430, 490, 730, 1030, 1330] });
  // SIM 430-460 and 490-520: the return at 460 and the next start at 490 are exactly 30 s apart: fine.
  assert.deepEqual(cs.overdriveProblems('x', close).filter((p) => /apart/.test(p)), []);
  const tight = s10report({ starts: [450, 500, 750, 1050, 1350] });
  assert.match(cs.overdriveProblems('x', tight).join('\n'), /switched ERG -> SIM only 20 s apart at 480 s/);
});

test('S10 across the three runs', () => {
  const set = { s10_vo2: s10report(), s10_endurance: s10report(), s10_vo2_offsets: s10report() };
  set.s10_endurance.content_id = 'endurance';
  set.s10_endurance.args.content = 'endurance';
  const r = cs.checkS10(set);
  assert.equal(r.status, 'PASS', r.details.join('\n'));
  assert.equal(cs.checkS10({}).status, 'SKIP');
});

// --- FIT laps and the driver ------------------------------------------------------------------------------------

test('checkFit compares the lap count in fit_check --json with the content', () => {
  const rs = { s5_drill: report({ content: 'drill', players: 1 }) };
  const good = () => ({ status: 0, stdout: JSON.stringify({ ok: true, files: [{ laps: [{}, {}, {}] }] }) });
  assert.equal(cs.checkFit(rs, good).status, 'PASS');
  const bad = () => ({ status: 0, stdout: JSON.stringify({ ok: true, files: [{ laps: [{}, {}] }] }) });
  assert.match(cs.checkFit(rs, bad).details.join('\n'), /2 laps .* wanted 3/);
  assert.match(cs.checkFit(rs, () => ({ status: 1, stdout: '' })).details.join('\n'), /fit_check exit 1/);
  assert.match(cs.checkFit(rs, () => ({ status: 0, stdout: 'x' })).details.join('\n'), /no JSON/);
});

test('format prints one line per scenario and indents the details', () => {
  const out = cs.format([
    { id: 'S1', status: 'PASS', summary: 'ok', details: [] },
    { id: 'S3', status: 'FAIL', summary: 'bad', details: ['one', 'two'] },
    { id: 'S4', status: 'SKIP', summary: 'none', details: [] },
  ]);
  assert.deepEqual(out.split('\n'), ['PASS S1  ok', 'FAIL S3  bad', '    - one', '    - two', 'SKIP S4  none']);
});

test('the CLI exits 0 on pass, 1 on a failed scenario, 2 on usage errors, and --only selects', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'cs-cli-'));
  for (const n of [1, 2, 3]) fs.writeFileSync(path.join(d, `s9_short_seed${n}.json`), JSON.stringify(report({ seed: n, score: 80 })));
  const script = path.join(here, 'check_sims.mjs');
  const run = (...a) => spawnSync(process.execPath, [script, ...a], { encoding: 'utf8' });
  let r = run(d, '--only=S1');
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /^PASS S1 /m);
  r = run(d, '--only=S1,S3');
  assert.match(r.stdout, /SKIP S3/);
  fs.writeFileSync(path.join(d, 's9_short_seed1.json'), JSON.stringify(report({ seed: 1, score: 10 })));
  r = run(d, '--only=S1');
  assert.equal(r.status, 1);
  assert.match(r.stdout, /^FAIL S1 /m);
  assert.equal(run().status, 2);
  assert.equal(run(path.join(d, 'nope')).status, 2);
  const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'cs-empty-'));
  assert.equal(run(empty).status, 2);
});
