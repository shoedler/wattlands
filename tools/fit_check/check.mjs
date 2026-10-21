#!/usr/bin/env node
// tools/fit_check/check.mjs: decode and check FIT activity files (BRIEF 3.8, 7.5).
//
//   node tools/fit_check/check.mjs <file|dir>... [--expect-laps=<n>] [--json]
//
// Directories are searched recursively for *.fit. Each file is decoded with Garmin's FIT SDK
// (@garmin/fitsdk, pinned in package.json; `npm ci` in tools/fit_check): Decoder.isFIT,
// checkIntegrity and read, which must report zero errors. Then:
//   - file_id type activity; exactly one session and one activity;
//   - session sport cycling and sub_sport virtual_activity (names taken from the SDK profile);
//   - records: at least one, timestamps never decreasing, no GPS fields, and one record per
//     second of elapsed time (within 1 %);
//   - laps: as many as session.num_laps, covering the session's elapsed time and work, and
//     exactly --expect-laps=<n> when given;
//   - timer start and stop events;
//   - when <same stem>.json (a RideRecorder summary) sits next to the file, the FIT's record
//     and lap counts and session totals equal the summary's.
// Prints per file its errors, record count, laps (start, duration) and session totals, or
// with --json one JSON document (schema in tools/fit_check/README.md). Exit codes: 0 every
// file passed, 1 any error, 2 usage error.
//
// If @garmin/fitsdk can't be imported (npm blocked), the same checks run on the output of the
// GDScript decoder (tools/fit_decode/decode.gd, run through tools/godot.sh; contract in the
// README). WATTLANDS_FIT_CHECK_SDK overrides the module specifier and WATTLANDS_FIT_DECODE_CMD
// (a JSON array) the decoder command; both exist for tests.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const FIT_EPOCH_UNIX = 631065600;
const SPORT_CYCLING = 2;
const SUB_SPORT_VIRTUAL_ACTIVITY = 58;
const FILE_ACTIVITY = 4;
// Names for the GDScript fallback (the SDK profile supplies them otherwise).
const FALLBACK_NAMES = { sport: { 2: 'cycling' }, subSport: { 58: 'virtualActivity' }, file: { 4: 'activity' } };

export function parseArgs(argv) {
  const out = { paths: [], expectLaps: null, json: false };
  for (const a of argv) {
    if (a === '--json') out.json = true;
    else if (a.startsWith('--expect-laps=')) {
      const v = a.slice('--expect-laps='.length);
      if (!/^\d+$/.test(v)) throw new UsageError(`--expect-laps needs a whole number, got ${JSON.stringify(v)}`);
      out.expectLaps = Number(v);
    } else if (a === '--help' || a === '-h') out.help = true;
    else if (a.startsWith('--')) throw new UsageError(`unknown flag ${a}`);
    else out.paths.push(a);
  }
  return out;
}

class UsageError extends Error {}

/** Every .fit file under the given paths (directories recursively), sorted; missing paths are reported. */
export function collectFiles(paths) {
  const files = [];
  const missing = [];
  const walk = (p) => {
    for (const e of fs.readdirSync(p, { withFileTypes: true })) {
      const full = path.join(p, e.name);
      if (e.isDirectory()) walk(full);
      else if (e.isFile() && e.name.toLowerCase().endsWith('.fit')) files.push(full);
    }
  };
  for (const p of paths) {
    let st;
    try {
      st = fs.statSync(p);
    } catch {
      missing.push(p);
      continue;
    }
    if (st.isDirectory()) walk(p);
    else files.push(p);
  }
  return { files: [...new Set(files.map((f) => path.resolve(f)))].sort(), missing };
}

// --- Decoding ---------------------------------------------------------------------------

async function loadSdk() {
  const spec = process.env.WATTLANDS_FIT_CHECK_SDK || '@garmin/fitsdk';
  try {
    const sdk = await import(spec);
    if (!sdk.Decoder || !sdk.Stream || !sdk.Profile) throw new Error('not the FIT SDK');
    return sdk;
  } catch (err) {
    return { error: err };
  }
}

const unixOf = (d) => (d instanceof Date ? Math.round(d.getTime() / 1000) : typeof d === 'number' ? d + FIT_EPOCH_UNIX : null);

/** Decodes one file with the SDK into the normalized model. */
function decodeWithSdk(sdk, file) {
  const { Decoder, Stream, Profile } = sdk;
  const model = emptyModel(file, 'fitsdk');
  const buf = fs.readFileSync(file);
  model.is_fit = Decoder.isFIT(Stream.fromBuffer(buf));
  model.integrity = model.is_fit && new Decoder(Stream.fromBuffer(buf)).checkIntegrity();
  if (!model.is_fit) model.errors.push('Decoder.isFIT: not a FIT file');
  if (model.is_fit && !model.integrity) model.errors.push('Decoder.checkIntegrity: header or file CRC, or size, is wrong');
  if (!model.is_fit) return model;
  const { messages, errors } = new Decoder(Stream.fromBuffer(buf)).read();
  for (const e of errors) model.errors.push(`Decoder.read: ${e?.message ?? e}`);
  const m = messages ?? {};
  model.expected = {
    sport: Profile.types.sport[SPORT_CYCLING],
    sub_sport: Profile.types.subSport[SUB_SPORT_VIRTUAL_ACTIVITY],
    file: Profile.types.file[FILE_ACTIVITY],
  };
  model.file_type = m.fileIdMesgs?.[0]?.type ?? null;
  model.file_ids = m.fileIdMesgs?.length ?? 0;
  const recs = m.recordMesgs ?? [];
  model.records = recs.length;
  model.has_gps = recs.some((r) => r.positionLat !== undefined || r.positionLong !== undefined);
  let prev = -Infinity;
  for (const r of recs) {
    const t = unixOf(r.timestamp);
    if (t === null || t < prev) model.records_monotonic = false;
    prev = t ?? prev;
  }
  model.first_record_unix = recs.length ? unixOf(recs[0].timestamp) : null;
  model.last_record_unix = recs.length ? unixOf(recs[recs.length - 1].timestamp) : null;
  const nameKey = (m.fieldDescriptionMesgs ?? []).find((f) => f.fieldName === 'lap_name')?.key;
  model.laps = (m.lapMesgs ?? []).map((l) => ({
    start_unix: unixOf(l.startTime),
    duration_s: l.totalElapsedTime ?? null,
    timer_s: l.totalTimerTime ?? null,
    distance_m: l.totalDistance ?? null,
    work_j: l.totalWork ?? null,
    avg_power_w: l.avgPower ?? null,
    name: nameKey !== undefined ? (l.developerFields?.[nameKey] ?? '') : '',
  }));
  const s = m.sessionMesgs?.[0];
  model.sessions = m.sessionMesgs?.length ?? 0;
  model.activities = m.activityMesgs?.length ?? 0;
  if (s) model.session = normalizedSession(s, s.sport, s.subSport);
  for (const e of m.eventMesgs ?? []) {
    if (e.event !== 'timer') continue;
    if (e.eventType === 'start') model.timer_events.start += 1;
    else model.timer_events.stop += 1;
  }
  return model;
}

function normalizedSession(s, sport, subSport) {
  return {
    sport,
    sub_sport: subSport,
    start_unix: unixOf(s.startTime ?? s.start_time),
    elapsed_s: s.totalElapsedTime ?? s.total_elapsed_time ?? null,
    timer_s: s.totalTimerTime ?? s.total_timer_time ?? null,
    distance_m: s.totalDistance ?? s.total_distance ?? null,
    work_j: s.totalWork ?? s.total_work ?? null,
    avg_power_w: s.avgPower ?? s.avg_power ?? null,
    max_power_w: s.maxPower ?? s.max_power ?? null,
    avg_cadence_rpm: s.avgCadence ?? s.avg_cadence ?? null,
    max_cadence_rpm: s.maxCadence ?? s.max_cadence ?? null,
    num_laps: s.numLaps ?? s.num_laps ?? null,
  };
}

function emptyModel(file, decoder) {
  return {
    path: file, decoder, errors: [], is_fit: false, integrity: false, file_type: null, file_ids: 0,
    records: 0, records_monotonic: true, has_gps: false, first_record_unix: null, last_record_unix: null,
    laps: [], session: null, sessions: 0, activities: 0, timer_events: { start: 0, stop: 0 },
    expected: { sport: FALLBACK_NAMES.sport[2], sub_sport: FALLBACK_NAMES.subSport[58], file: FALLBACK_NAMES.file[4] },
  };
}

/**
 * Fallback: runs the GDScript decoder (tools/fit_decode/decode.gd) through tools/godot.sh:
 *   tools/godot.sh --headless --path <repo> -s res://tools/fit_decode/decode.gd --
 *     --json-out=<abs path> --file=<abs path> [--file=<abs path>...]
 * It writes {"files": [<file result>]} (see README) and exits 0 even when a file is bad.
 */
function decodeWithGdscript(files) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fit_check_'));
  const out = path.join(tmp, 'decoded.json');
  const userArgs = ['--', `--json-out=${out}`, ...files.map((f) => `--file=${f}`)];
  let cmd;
  let args;
  if (process.env.WATTLANDS_FIT_DECODE_CMD) {
    const prefix = JSON.parse(process.env.WATTLANDS_FIT_DECODE_CMD);
    [cmd, ...args] = prefix;
    args = [...args, ...userArgs];
  } else {
    cmd = process.env.WATTLANDS_BASH || 'bash';
    args = [path.join(REPO, 'tools', 'godot.sh'), '--headless', '--path', REPO, '-s', 'res://tools/fit_decode/decode.gd', ...userArgs];
  }
  const r = spawnSync(cmd, args, { cwd: REPO, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8', timeout: 15 * 60 * 1000 });
  let decoded = null;
  try {
    decoded = JSON.parse(fs.readFileSync(out, 'utf8'));
  } catch {
    decoded = null;
  }
  fs.rmSync(tmp, { recursive: true, force: true });
  if (!decoded || !Array.isArray(decoded.files)) {
    const why = r.error ? r.error.message : `exit ${r.status}`;
    return files.map((f) => {
      const m = emptyModel(f, 'gdscript');
      m.errors.push(`GDScript decoder produced no result (${why}); stderr: ${(r.stderr || '').trim().split('\n').slice(-3).join(' | ')}`);
      return m;
    });
  }
  return files.map((f) => {
    const d = decoded.files.find((x) => path.resolve(x.path) === path.resolve(f));
    const m = emptyModel(f, 'gdscript');
    if (!d) {
      m.errors.push('GDScript decoder skipped the file');
      return m;
    }
    m.errors.push(...(d.errors ?? []));
    m.is_fit = d.is_fit ?? (d.errors ?? []).length === 0;
    m.integrity = d.integrity ?? m.is_fit;
    m.file_type = FALLBACK_NAMES.file[d.file_id?.type] ?? d.file_id?.type ?? null;
    m.file_ids = d.file_id ? 1 : 0;
    m.records = d.records ?? 0;
    m.records_monotonic = d.record_timestamps_monotonic ?? true;
    m.has_gps = Boolean(d.has_gps);
    m.laps = (d.laps ?? []).map((l) => ({
      start_unix: l.start_time ?? null, duration_s: l.total_elapsed_time ?? null, timer_s: l.total_timer_time ?? null,
      distance_m: l.total_distance ?? null, work_j: l.total_work ?? null, avg_power_w: l.avg_power ?? null, name: l.name ?? '',
    }));
    m.sessions = d.session_count ?? (d.session ? 1 : 0);
    m.activities = d.activity_count ?? 0;
    if (d.session) {
      m.session = normalizedSession(d.session,
        FALLBACK_NAMES.sport[d.session.sport] ?? d.session.sport,
        FALLBACK_NAMES.subSport[d.session.sub_sport] ?? d.session.sub_sport);
    }
    m.timer_events = { start: d.timer_events?.start ?? 0, stop: d.timer_events?.stop ?? 0 };
    return m;
  });
}

// --- Checks -------------------------------------------------------------------------------

const near = (a, b, tol) => a !== null && b !== null && a !== undefined && b !== undefined && Math.abs(Number(a) - Number(b)) <= tol;

/** Adds every check's failures to model.errors. */
export function checkModel(model, { expectLaps = null } = {}) {
  const e = model.errors;
  if (!model.is_fit || !model.integrity) return model;
  if (model.file_ids !== 1) e.push(`expected 1 file_id message, found ${model.file_ids}`);
  if (model.file_type !== model.expected.file) e.push(`file_id type is ${model.file_type}, expected ${model.expected.file}`);
  if (model.sessions !== 1) e.push(`expected 1 session, found ${model.sessions}`);
  if (model.activities !== 1) e.push(`expected 1 activity, found ${model.activities}`);
  const s = model.session;
  if (s) {
    if (s.sport !== model.expected.sport) e.push(`session sport is ${s.sport}, expected ${model.expected.sport}`);
    if (s.sub_sport !== model.expected.sub_sport) e.push(`session sub_sport is ${s.sub_sport}, expected ${model.expected.sub_sport}`);
  }
  if (model.records < 1) e.push('no records');
  if (!model.records_monotonic) e.push('record timestamps go backwards');
  if (model.has_gps) e.push('records carry GPS fields');
  if (s && s.elapsed_s !== null && model.records > 0) {
    const expected = Math.floor(s.elapsed_s + 1e-6) + 1;
    const tol = Math.max(2, Math.ceil(expected * 0.01));
    if (Math.abs(model.records - expected) > tol) {
      e.push(`${model.records} records for ${s.elapsed_s} s elapsed: not one per second (expected ${expected} within ${tol})`);
    }
  }
  if (s && s.num_laps !== null && s.num_laps !== model.laps.length) {
    e.push(`session num_laps ${s.num_laps} but ${model.laps.length} lap messages`);
  }
  if (model.laps.length === 0) e.push('no laps');
  if (s && model.laps.length > 0) {
    const dur = model.laps.reduce((a, l) => a + (l.duration_s ?? 0), 0);
    if (!near(dur, s.elapsed_s, 1.0)) e.push(`laps cover ${dur.toFixed(3)} s but the session ${s.elapsed_s} s`);
    if (s.work_j !== null && model.laps.every((l) => l.work_j !== null)) {
      const work = model.laps.reduce((a, l) => a + l.work_j, 0);
      if (!near(work, s.work_j, model.laps.length + 1)) e.push(`lap work adds up to ${work} J but the session has ${s.work_j} J`);
    }
  }
  if (expectLaps !== null && model.laps.length !== expectLaps) {
    e.push(`expected ${expectLaps} laps, found ${model.laps.length}`);
  }
  if (model.timer_events.start < 1 || model.timer_events.stop < 1) {
    e.push(`timer events: ${model.timer_events.start} start, ${model.timer_events.stop} stop (need both)`);
  }
  compareSummary(model);
  return model;
}

/** Compares with <stem>.json (a RideRecorder summary) when it exists. */
function compareSummary(model) {
  const jsonPath = model.path.replace(/\.fit$/i, '.json');
  if (!fs.existsSync(jsonPath)) return;
  let sum;
  try {
    sum = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  } catch {
    model.errors.push(`summary ${path.basename(jsonPath)} is not valid JSON`);
    return;
  }
  if (!sum || typeof sum !== 'object' || !('ride_id' in sum)) return;
  model.summary_checked = true;
  const s = model.session;
  const e = model.errors;
  const diff = (label, a, b, tol) => {
    if (!near(a, b, tol)) e.push(`summary mismatch: ${label} FIT ${a} vs summary ${b}`);
  };
  if (Number(sum.records) !== model.records) e.push(`summary mismatch: records FIT ${model.records} vs summary ${sum.records}`);
  if (Array.isArray(sum.laps) && sum.laps.length !== model.laps.length) {
    e.push(`summary mismatch: laps FIT ${model.laps.length} vs summary ${sum.laps.length}`);
  }
  if (!s) return;
  diff('elapsed s', s.elapsed_s, sum.duration_s, 0.002);
  if (sum.timer_s !== undefined) diff('timer s', s.timer_s, sum.timer_s, 0.002);
  diff('distance m', s.distance_m, sum.distance_m, 0.02);
  diff('work kJ', s.work_j / 1000, sum.kj, 0.0015);
  diff('avg power W', s.avg_power_w, sum.avg_power_w, 0.51);
  diff('max power W', s.max_power_w, sum.max_power_w, 0.51);
  if (Number(sum.avg_cadence_rpm) >= 0) diff('avg cadence rpm', s.avg_cadence_rpm, sum.avg_cadence_rpm, 0.51);
  if (Number(sum.max_cadence_rpm) >= 0) diff('max cadence rpm', s.max_cadence_rpm, sum.max_cadence_rpm, 0.51);
}

// --- Output ---------------------------------------------------------------------------------

function iso(unix) {
  return unix === null || unix === undefined ? '?' : new Date(unix * 1000).toISOString().replace('.000Z', 'Z');
}

export function resultJson(model) {
  const s = model.session;
  const start = s?.start_unix ?? model.laps[0]?.start_unix ?? null;
  return {
    path: model.path,
    ok: model.errors.length === 0,
    decoder: model.decoder,
    errors: model.errors,
    records: model.records,
    laps: model.laps.map((l) => ({
      start: iso(l.start_unix), start_unix: l.start_unix,
      start_offset_s: start !== null && l.start_unix !== null ? l.start_unix - start : null,
      duration_s: l.duration_s, timer_s: l.timer_s, distance_m: l.distance_m, work_j: l.work_j,
      avg_power_w: l.avg_power_w, name: l.name,
    })),
    session: s
      ? {
        sport: s.sport, sub_sport: s.sub_sport, start: iso(s.start_unix), elapsed_s: s.elapsed_s, timer_s: s.timer_s,
        distance_m: s.distance_m, work_j: s.work_j, kj: s.work_j === null ? null : s.work_j / 1000,
        avg_power_w: s.avg_power_w, max_power_w: s.max_power_w, avg_cadence_rpm: s.avg_cadence_rpm,
        max_cadence_rpm: s.max_cadence_rpm, num_laps: s.num_laps,
      }
      : null,
    summary_checked: Boolean(model.summary_checked),
  };
}

function printText(results, out) {
  for (const r of results) {
    out.write(`${r.ok ? 'OK  ' : 'FAIL'} ${r.path}\n`);
    for (const err of r.errors) out.write(`     error: ${err}\n`);
    const s = r.session;
    out.write(`     records ${r.records}, laps ${r.laps.length}`);
    if (s) {
      out.write(`, ${s.sport}/${s.sub_sport}, elapsed ${s.elapsed_s} s, timer ${s.timer_s} s, distance ${s.distance_m} m, work ${s.kj} kJ, power avg ${s.avg_power_w} W max ${s.max_power_w} W, cadence avg ${s.avg_cadence_rpm} max ${s.max_cadence_rpm} rpm`);
    }
    out.write(`${r.summary_checked ? ', matches its summary' : ''} [${r.decoder}]\n`);
    r.laps.forEach((l, i) => {
      out.write(`     lap ${i + 1}: start ${l.start} (+${l.start_offset_s} s), duration ${l.duration_s} s${l.name ? `, "${l.name}"` : ''}\n`);
    });
  }
  const bad = results.filter((r) => !r.ok).length;
  out.write(`fit_check: ${results.length} file(s), ${bad} failed\n`);
}

export async function main(argv, out = process.stdout, err = process.stderr) {
  let args;
  try {
    args = parseArgs(argv);
  } catch (e) {
    if (e instanceof UsageError) {
      err.write(`fit_check: ${e.message}\nusage: node tools/fit_check/check.mjs <file|dir>... [--expect-laps=<n>] [--json]\n`);
      return 2;
    }
    throw e;
  }
  if (args.help || args.paths.length === 0) {
    err.write('usage: node tools/fit_check/check.mjs <file|dir>... [--expect-laps=<n>] [--json]\n');
    return args.help ? 0 : 2;
  }
  const { files, missing } = collectFiles(args.paths);
  const results = [];
  for (const m of missing) {
    results.push({ path: path.resolve(m), ok: false, decoder: null, errors: ['no such file or directory'], records: 0, laps: [], session: null, summary_checked: false });
  }
  if (files.length === 0 && missing.length === 0) {
    err.write(`fit_check: no .fit files under ${args.paths.join(', ')}\n`);
    return 1;
  }
  const sdk = await loadSdk();
  let models;
  if (sdk.error) {
    err.write(`fit_check: @garmin/fitsdk unavailable (${sdk.error.message.split('\n')[0]}); using the GDScript decoder\n`);
    models = files.length ? decodeWithGdscript(files) : [];
  } else {
    models = files.map((f) => {
      try {
        return decodeWithSdk(sdk, f);
      } catch (e) {
        const m = emptyModel(f, 'fitsdk');
        m.errors.push(`decoder threw: ${e.message}`);
        return m;
      }
    });
  }
  for (const m of models) results.push(resultJson(checkModel(m, { expectLaps: args.expectLaps })));
  results.sort((a, b) => a.path.localeCompare(b.path));
  const ok = results.every((r) => r.ok);
  if (args.json) out.write(`${JSON.stringify({ ok, decoder: sdk.error ? 'gdscript' : 'fitsdk', files: results }, null, 2)}\n`);
  else printText(results, out);
  return ok ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then((code) => {
    process.exitCode = code;
  });
}
