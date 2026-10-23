// node --test tests/games/fishing/sim/check_sims.test.mjs: check_sims.mjs on the synthetic reports
// of fixtures/ (pass/ passes every scenario, fail/ fails the ones FAILURES names) and on in-memory
// variants. Independent of build/.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import * as cs from './check_sims.mjs';
import { expectedLaps, clampProblems, eventErrors, requestShapeProblems, median } from './fishing_sim_lib.mjs';
import { FAILURES, buildRun, failing, passing, s11Run } from './fixtures/make_fixtures.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const FIX = path.join(here, 'fixtures');
const byId = (results) => Object.fromEntries(results.map((r) => [r.id, r]));
const run = (reports, only = null, opts = {}) => byId(cs.checkAll(reports, only, opts));
const details = (r) => r.details.join('\n');

function sink() {
  let text = '';
  return { write: (s) => (text += s), get text() { return text; } };
}

test('the fixture files on disk are what make_fixtures.mjs builds', () => {
  for (const [sub, set] of [['pass', passing()], ['fail', failing()]]) {
    const files = fs.readdirSync(path.join(FIX, sub)).filter((f) => f.endsWith('.json')).sort();
    assert.deepEqual(files, Object.keys(set).map((n) => `${n}.json`).sort(), `${sub}/ file list`);
    for (const [name, r] of Object.entries(set)) {
      const disk = JSON.parse(fs.readFileSync(path.join(FIX, sub, `${name}.json`), 'utf8'));
      assert.deepEqual(disk, JSON.parse(JSON.stringify(r)), `${sub}/${name}.json (rerun make_fixtures.mjs)`);
    }
  }
});

test('every scenario passes on the passing fixtures, FIT included', () => {
  const reports = cs.loadReports(path.join(FIX, 'pass'));
  assert.equal(Object.keys(reports).length, 17);
  const calls = [];
  const runner = (args) => {
    calls.push(args);
    const laps = Number(args[1].split('=')[1]);
    return { status: 0, stdout: JSON.stringify({ ok: true, files: [{ path: args[0], ok: true, errors: [], laps: Array(laps).fill({}) }] }) };
  };
  const res = cs.checkAll(reports, null, { fit: true, fitRunner: runner });
  for (const r of res) assert.equal(r.status, 'PASS', `${r.id}: ${r.summary}\n${details(r)}`);
  assert.deepEqual(res.map((r) => r.id), ['ALL', 'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S10', 'S11', 'S9']);
  // s1 2, s2 1 + 1, s3 4 x 5, s4 2, s5 2, s6 1, s7 1, s8 2 + 2, s10 3, s11 2 FIT files
  assert.equal(calls.length, 39);
  // e2e: ride out + Reel + Fight + cool-down.
  const e2e = calls.find((c) => c[0].includes('s10_e2e_slot0'));
  assert.equal(e2e[1], '--expect-laps=4');
});

test('the CLI exits 0 on pass/, 1 on fail/ naming each defect, 2 without reports', () => {
  const ok = sink();
  assert.equal(cs.main([path.join(FIX, 'pass')], ok, sink()), 0, ok.text);
  assert.match(ok.text, /check_sims: 11 passed, 0 failed/);
  const bad = sink();
  assert.equal(cs.main([path.join(FIX, 'fail')], bad, sink()), 1);
  for (const [name, msgs] of Object.entries(FAILURES)) {
    for (const m of msgs) assert.ok(bad.text.includes(m), `${name}: "${m}" in\n${bad.text}`);
  }
  assert.match(bad.text, /FAIL S1 /);
  assert.match(bad.text, /FAIL S2 /);
  assert.match(bad.text, /FAIL S6 /);
  assert.match(bad.text, /FAIL S10 /);
  assert.match(bad.text, /FAIL S11 /);
  assert.match(bad.text, /SKIP S3 /);
  const err = sink();
  assert.equal(cs.main([], sink(), err), 2);
  assert.equal(cs.main([path.join(FIX)], sink(), sink()), 2, 'no reports directly in fixtures/');
});

test('--only limits the scenarios but ALL always runs', () => {
  const res = run(passing(), ['S10']);
  assert.deepEqual(Object.keys(res), ['ALL', 'S10']);
});

test('a missing report is SKIP, a partial set is FAIL', () => {
  const p = passing();
  assert.equal(run({ s10_e2e: p.s10_e2e }).S1.status, 'SKIP');
  const partial = { s3_free30_seed1: p.s3_free30_seed1 };
  const s3 = run(partial).S3;
  assert.equal(s3.status, 'FAIL');
  assert.match(details(s3), /missing report s3_free30_seed2/);
  assert.equal(run(partial, null, { seeds: [1] }).S3.status, 'PASS');
});

test('ALL: forbidden and unknown clamps fail in applied records and trace rows; noted ones pass', () => {
  const p = passing();
  const r = p.s10_e2e;
  r.directives[1].applied.clamped_by = ['ceiling'];
  r.trace['2'][0].clamped_by = ['limit_120'];
  r.trace['3'][0].clamped_by = ['grade_limit'];
  r.trace['1'][0].clamped_by = ['switch_ramp', 'paused', 'warmup'];
  const all = run({ s10_e2e: r }).ALL;
  assert.equal(all.status, 'FAIL');
  assert.match(details(all), /clamped_by ceiling \(forbidden/);
  assert.match(details(all), /clamped_by limit_120 \(forbidden/);
  assert.match(details(all), /clamped_by grade_limit \(not an allowed rule\)/);
  assert.doesNotMatch(details(all), /switch_ramp|paused|warmup \(/);
  assert.deepEqual(clampProblems(['slew', 'floor', 'unverified', 'rescue', 'coasting', 'haptic_intensity', 'warmup', 'switch_ramp', 'paused']), []);
  assert.equal(clampProblems(['long_phase', 'limit_105']).length, 2);
});

test('ALL: a request outside range_pct, in a phase without one, refused or malformed fails', () => {
  const r = passing().s8_free30_a;
  const d = r.directives[0];
  d.requested.target_pct = 79;
  const one = run({ s8_free30_a: r }).ALL;
  assert.match(details(one), /outside phase \d+'s range_pct \[72, 78\]/);
  d.requested.target_pct = 75;
  d.applied.phase_index = 1;
  assert.match(details(run({ s8_free30_a: r }).ALL), /which has no range_pct/);
  d.applied.phase_index = 2;
  d.applied.refused = true;
  d.accepted = false;
  d.requested.source = 'siege';
  d.requested.reason = 'boost';
  const msgs = details(run({ s8_free30_a: r }).ALL);
  assert.match(msgs, /refused by the governor/);
  assert.match(msgs, /not accepted/);
  assert.match(msgs, /source "siege"/);
  assert.match(msgs, /reason "boost"/);
  d.applied = null;
  assert.match(details(run({ s8_free30_a: r }).ALL), /no applied record/);
});

test('request shape: ERG keys and values, and the Landing haptic', () => {
  assert.deepEqual(requestShapeProblems({ mode: 'ERG', target_pct: 80, duration_s: 0, reason: 'pull', source: 'fishing', id: 3 }), []);
  assert.deepEqual(requestShapeProblems({ mode: 'SIM', haptic: 3.0, duration_s: 5, reason: 'last_run', source: 'fishing', id: 9 }), []);
  assert.match(requestShapeProblems({ mode: 'SIM', haptic: 4, duration_s: 5, reason: 'last_run', source: 'fishing' })[0], /haptic 4/);
  assert.match(requestShapeProblems({ mode: 'ERG', target_pct: 115, duration_s: 0, reason: 'run', source: 'fishing' })[0], /outside 50..110/);
  assert.match(requestShapeProblems({ mode: 'ERG', target_pct: 80, duration_s: 0, reason: 'pull', source: 'fishing', grade: 2 })[0], /keys/);
});

test('ALL: incomplete runs, plan warnings, bad events, big snapshots and missing FITs fail', () => {
  const r = passing().s4_ap_all;
  r.end_reason = 'timeout';
  r.plan_warnings['1'] = ['w'];
  r.events.push({ t: 5, type: 'game_event', event: { type: 'landed', l: 0, sp: 0, grade: 0, kg: 1.5, points: 3, hk: 10 } });
  r.events.push({ t: 6, type: 'game_event', event: { type: 'cast', l: 0 } });
  r.max_snapshot_bytes = 4000;
  r.fit_paths = [];
  r.directives_unmatched = [{ id: 99 }];
  const msgs = details(run({ s4_ap_all: r }).ALL);
  for (const m of ['end_reason timeout', 'plan warnings', 'kg is not an int', 'cast: missing spot', 'largest snapshot 4000', 'fit_paths', 'match no request']) {
    assert.ok(msgs.includes(m), `${m} in\n${msgs}`);
  }
});

test('event schema: types, ints, ranges', () => {
  assert.deepEqual(eventErrors({ type: 'double_hookup', lanes: [0, 2], lvl: 2 }), []);
  assert.match(eventErrors({ type: 'double_hookup', lanes: [0, 2, 3], lvl: 2 })[0], /lvl 2/);
  assert.match(eventErrors({ type: 'whale' })[0], /unknown event type/);
  assert.match(eventErrors({ type: 'bite', l: 5, sp: 0 })[0], /lane 5/);
  assert.match(eventErrors({ type: 'landed', l: 0, sp: 1, grade: 0, kg: 10, points: 1, hk: 12 })[0], /hk 12/);
  assert.deepEqual(eventErrors({ type: 'trip_over' }), []);
});

test('S1: fight lengths, snaps and the stricter clamp set', () => {
  const r = passing().s1_threshold;
  r.directives[2].applied.clamped_by = ['rescue'];
  r.events.push({ t: 600, type: 'game_event', event: { type: 'snap', l: 0 } });
  const s1 = run({ s1_threshold: r }).S1;
  assert.match(details(s1), /lane 0 snapped 1 lines/);
  assert.match(details(s1), /clamped_by rescue/);
  const long = buildRun({ name: 'x', content: 'threshold', scheduled: true, lanes: [{ fights: [0, 1, 2, 3].map((k) => ({ species: 'tuna', reel: 240, len: k === 0 ? 200 : 300 })) }] });
  assert.match(details(run({ s1_threshold: long }).S1), /TUNA_1 lasted 200 s \(240-420\)/);
});

test('S2: a throw where a snap belongs, and a shortened phase, fail', () => {
  const p = passing();
  const s2 = p.s2_high;
  const f = s2.phases['1'].find((x) => x.label === 'FISHING_PHASE_TUNA_2');
  f.end = f.start + 100;
  s2.events.push({ t: 2000, type: 'game_event', event: { type: 'snap', l: 0 } });
  const msgs = details(run({ s2_low: p.s2_low, s2_high: s2 }).S2);
  assert.match(msgs, /TUNA_2 lasted 100 s, shorter than its min_s 276/);
  assert.match(msgs, /1 snap events \(wanted only thrown\)/);
});

test('S3: the median, the Double Hookup, the 40% cap and the 35-minute end', () => {
  const p = passing();
  const reps = Object.fromEntries(Object.entries(p).filter(([n]) => n.startsWith('s3_')));
  for (const r of Object.values(reps)) r.events = r.events.filter((e) => !(e.type === 'game_event' && ['landed', 'double_hookup'].includes(e.event.type) && e.event.l !== 0));
  const msgs = details(run(reps).S3);
  assert.match(msgs, /median 0 fish per rider/);
  assert.match(msgs, /no Double Hookup/);
  const big = buildRun({ name: 'b', content: 'free_30', seed: 1, players: 4, fishingS: 1320, lanes: [0, 1, 2, 3].map(() => ({ fights: [{ species: 'tuna', reel: 200, len: 560, shape: { minS: 300, maxS: 600 } }] })) });
  big.game_seconds = 2200;
  const m2 = details(cs.checkS3({ s3_free30_seed1: big }, { seeds: [1] }));
  assert.match(m2, /fought 560 s \(40% of fishing is 528\)/);
  assert.match(m2, /the trip took 2200 s/);
  assert.equal(median([1, 2, 3, 4]), 2.5);
});

test('S4 and S5: no fish, the wrong Autopilot flag, and targets above 100%', () => {
  const p = passing();
  p.s4_ap_none.events = p.s4_ap_none.events.filter((e) => e.event?.type !== 'landed');
  p.s4_ap_all.slots[0].autopilot = false;
  const s4 = details(run({ s4_ap_none: p.s4_ap_none, s4_ap_all: p.s4_ap_all }).S4);
  assert.match(s4, /s4_ap_none: no fish landed/);
  assert.match(s4, /s4_ap_all: slot 0 autopilot false, wanted true/);
  const r = p.s5_base60;
  r.trace['1'].push({ t: 2000, game_t: 2000, mode: 'ERG', applied_pct: 103, clamped_by: [] });
  r.directives[1].requested.target_pct = 101;
  const s5 = details(run({ s5_base60: r }).S5);
  assert.match(s5, /applied 103%/);
  assert.match(s5, /requests 101%/);
});

test('S6: jump count, length, peak and time above 105%', () => {
  const r = passing().s6_free120_marlin;
  r.events = r.events.filter((e) => !(e.event?.type === 'jump' && e.event.k > 3));
  r.events.find((e) => e.event?.type === 'jump').event.ms = 31000;
  r.trace['1'].push({ t: 3000, game_t: 3000, mode: 'ERG', applied_pct: 106, clamped_by: [] });
  const msgs = details(run({ s6_free120_marlin: r }).S6);
  assert.match(msgs, /3 jumps \(4-8\)/);
  assert.match(msgs, /lasts 31000 ms/);
  assert.match(msgs, /1 s applied above 105%/);
  const none = passing().s6_free120_marlin;
  none.events = none.events.filter((e) => e.event?.sp !== 3);
  assert.match(details(run({ s6_free120_marlin: none }).S6), /no marlin was hooked/);
});

test('S7: no rescue, a snap during the stagger, the fight not resumed', () => {
  const p = passing();
  const a = p.s7_threshold_drop;
  a.events = a.events.filter((e) => e.type !== 'rescue');
  assert.match(details(run({ s7_threshold_drop: a }).S7), /rescue never started/);
  const b = passing().s7_threshold_drop;
  b.events.push({ t: 615, type: 'game_event', event: { type: 'snap', l: 0 } });
  b.events = b.events.filter((e) => !(e.event?.type === 'landed' && e.t < 1000));
  const msgs = details(run({ s7_threshold_drop: b }).S7);
  assert.match(msgs, /snap at 615 s during the stagger/);
  assert.match(msgs, /was not landed after the rescue/);
});

test('S8: the hash covers events, phases, applied directives and results', () => {
  const p = passing();
  assert.equal(cs.runHash(p.s8_free30_a), cs.runHash(p.s8_free30_b));
  p.s8_free30_b.directives[0].applied.clamped_by = ['floor'];
  p.s8_free30_b.deterministic_hash = 'x';
  const msgs = details(run({ s8_free30_a: p.s8_free30_a, s8_free30_b: p.s8_free30_b }).S8);
  assert.match(msgs, /deterministic_hash differs/);
  assert.match(msgs, /applied directives or results differ/);
  assert.match(details(run({ s8_e2e_a: p.s10_e2e }).S8), /missing report s8_e2e_b/);
});

test('S9: expected laps per rider and fit_check failures', () => {
  const p = passing();
  // threshold: ride out + 4 Reels + 4 Fights + cool-down; free_30 s8: ride out, Reel, Fight, trailing Reel, cool-down.
  assert.equal(expectedLaps(p.s1_threshold, '1'), 10);
  assert.equal(expectedLaps(p.s8_free30_a, '1'), 5);
  const timedOut = { ...p.s10_e2e, end_reason: 'timeout' };
  assert.equal(expectedLaps(timedOut, '1'), 3);
  const res = cs.checkFit({ s10_e2e: p.s10_e2e }, () => ({ status: 1, stdout: JSON.stringify({ files: [{ laps: [{}, {}], errors: ['CRC mismatch'] }] }) }));
  assert.equal(res.status, 'FAIL');
  assert.match(details(res), /CRC mismatch/);
  assert.match(details(res), /expected 4 laps, got 2/);
  assert.equal(cs.checkFit({}, () => ({ status: 0, stdout: '' })).status, 'SKIP');
});

test('S10: a second fish or a late cool-down fails', () => {
  const r = passing().s10_e2e;
  r.events.push({ t: 100, type: 'game_event', event: { type: 'landed', l: 1, sp: 1, grade: 0, kg: 70, points: 30, hk: 10 } });
  r.phases['3'].find((x) => x.kind === 'COOLDOWN').start = 150;
  const msgs = details(run({ s10_e2e: r }).S10);
  assert.match(msgs, /lane 1 landed mackerel, mahi/);
  assert.match(msgs, /lane 2 reached the cool-down at 150 s/);
});

test('S11: unverified factor, FTPs, haptics off and forbidden clamps', () => {
  const ok = s11Run();
  assert.equal(run({ s11_threshold_unverified: ok }).S11.status, 'PASS');
  const r = s11Run();
  r.args.unverified = false;
  r.slots[0].ftp = 200;
  r.slots[1].ftp_verified = true;
  const e1 = r.directives.find((d) => d.peer === 2 && d.requested.mode === 'ERG');
  e1.applied.clamped_by = ['unverified', 'long_phase'];
  r.trace['2'] = r.trace['2'].map((row) => (row.phase === 2 ? { ...row, clamped_by: [] } : row));
  r.directives = r.directives.filter((d) => !(d.peer === 1 && d.requested.mode === 'SIM'));
  const msgs = details(run({ s11_threshold_unverified: r }).S11);
  for (const m of ['args.unverified false, wanted true', 'slot 0 FTP 200, wanted 300', 'slot 1 ftp_verified true', 'clamped_by long_phase (forbidden', 'slot 0 (haptics on) got no Landing haptic', 'Fight trace rows without the unverified clamp']) {
    assert.ok(msgs.includes(m), `${m} in
${msgs}`);
  }
  // The floor may lift a target above x0.85; nothing else may.
  const fl = s11Run();
  const e2 = fl.directives.find((d) => d.peer === 1 && d.requested.mode === 'ERG');
  e2.applied.applied.target_w = 260;
  e2.applied.clamped_by = ['unverified', 'floor'];
  assert.equal(run({ s11_threshold_unverified: fl }).S11.status, 'PASS');
  e2.applied.clamped_by = ['unverified'];
  assert.match(details(run({ s11_threshold_unverified: fl }).S11), /applied 260 W for 95% of 300 W/);
});
