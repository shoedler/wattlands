// A stand-in for the GDScript fallback decoder (tools/fit_decode/decode.gd), for the
// fallback tests. It implements the same command-line and JSON contract (README.md,
// "Fallback decoder contract"), decoding with @garmin/fitsdk:
//   node fake_decode.mjs -- --json-out=<abs path> --file=<abs path> [--file=...]
import fs from 'node:fs';
import { Decoder, Stream } from '@garmin/fitsdk';

const FIT_EPOCH_UNIX = 631065600;
const SPORT = { cycling: 2, running: 1 };
const SUB_SPORT = { virtualActivity: 58, generic: 0 };
const FILE = { activity: 4 };

const args = process.argv.slice(2).filter((a) => a !== '--');
const out = args.find((a) => a.startsWith('--json-out='))?.slice('--json-out='.length);
const files = args.filter((a) => a.startsWith('--file=')).map((a) => a.slice('--file='.length));
if (process.env.FAKE_DECODE_FAIL === '1') process.exit(3);

const unix = (d) => Math.round(d.getTime() / 1000);
const result = { files: [] };
for (const f of files) {
  const buf = fs.readFileSync(f);
  const isFit = Decoder.isFIT(Stream.fromBuffer(buf));
  const integrity = isFit && new Decoder(Stream.fromBuffer(buf)).checkIntegrity();
  const entry = { path: f, is_fit: isFit, integrity, errors: [] };
  if (!isFit || !integrity) {
    entry.errors.push(isFit ? 'crc' : 'not a FIT file');
    result.files.push(entry);
    continue;
  }
  const { messages: m, errors } = new Decoder(Stream.fromBuffer(buf)).read();
  entry.errors.push(...errors.map(String));
  const recs = m.recordMesgs ?? [];
  const nameKey = (m.fieldDescriptionMesgs ?? []).find((x) => x.fieldName === 'lap_name')?.key;
  entry.file_id = { type: FILE[m.fileIdMesgs?.[0]?.type] ?? null, manufacturer: 255 };
  entry.records = recs.length;
  entry.record_timestamps_monotonic = recs.every((r, i) => i === 0 || r.timestamp >= recs[i - 1].timestamp);
  entry.has_gps = recs.some((r) => r.positionLat !== undefined);
  entry.laps = (m.lapMesgs ?? []).map((l) => ({
    start_time: unix(l.startTime), total_elapsed_time: l.totalElapsedTime, total_timer_time: l.totalTimerTime,
    total_distance: l.totalDistance, total_work: l.totalWork, avg_power: l.avgPower,
    name: nameKey !== undefined ? l.developerFields?.[nameKey] ?? '' : '',
  }));
  const s = m.sessionMesgs?.[0];
  entry.session_count = m.sessionMesgs?.length ?? 0;
  entry.activity_count = m.activityMesgs?.length ?? 0;
  if (s) {
    entry.session = {
      sport: SPORT[s.sport] ?? -1, sub_sport: SUB_SPORT[s.subSport] ?? -1, start_time: unix(s.startTime),
      total_elapsed_time: s.totalElapsedTime, total_timer_time: s.totalTimerTime, total_distance: s.totalDistance,
      total_work: s.totalWork, avg_power: s.avgPower, max_power: s.maxPower, avg_cadence: s.avgCadence,
      max_cadence: s.maxCadence, num_laps: s.numLaps,
    };
  }
  const timers = (m.eventMesgs ?? []).filter((e) => e.event === 'timer');
  entry.timer_events = { start: timers.filter((e) => e.eventType === 'start').length, stop: timers.filter((e) => e.eventType !== 'start').length };
  void FIT_EPOCH_UNIX;
  result.files.push(entry);
}
fs.writeFileSync(out, JSON.stringify(result));
