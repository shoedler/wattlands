# tools/fit_check

Decodes FIT activity files with Garmin's FIT SDK and checks them (BRIEF 3.8, 7.5).

```
npm ci --prefix tools/fit_check          # once; installs the pinned @garmin/fitsdk
node tools/fit_check/check.mjs <file|dir>... [--expect-laps=<n>] [--json]
```

Directories are searched recursively for `*.fit` (any case). Exit codes: `0` every file passed, `1` any error (including a missing path, an empty directory or a lap-count mismatch), `2` a usage error.

## What it checks

With `@garmin/fitsdk` (version pinned exactly in `package.json` and `package-lock.json`; see `docs/deps.d/garmin-fitsdk.md`):

- `Decoder.isFIT`, `checkIntegrity` (header CRC, file CRC, size) and `read`, which must report zero errors;
- one `file_id` of type activity, one session, one activity;
- session `sport` cycling and `sub_sport` virtual_activity, compared by name with `Profile.types.sport[2]` and `Profile.types.subSport[58]` from the SDK's profile;
- records: at least one, timestamps never decreasing, no GPS fields, and one record per second of the session's elapsed time (floor(elapsed) + 1 records, within 1 % or 2 records);
- laps: as many lap messages as the session's `num_laps`, lap elapsed times adding up to the session's (within 1 s) and lap work to the session's (within rounding), and exactly `--expect-laps=<n>` when given;
- a timer start and a timer stop event;
- when `<same stem>.json` sits next to the FIT and is a RideRecorder summary (it has `ride_id`): the FIT's record and lap counts equal the summary's, and the session's elapsed and timer time, distance, work (kJ), average and maximum power and cadence equal the summary's within the FIT's resolution.

Expected laps for a game session (OWNERSHIP FIT1): lap-true phases that started + `lap_marker`s + 1 for the cool-down, when the plan's first phase is lap-true. A run that ends by `timeout` or `paused` before the cool-down has no cool-down lap. A plan whose first phase is lap-false has one more lap (the opening segment).

## Output

Text, per file:

```
OK   build/sims/fit/run_slot0.fit
     records 601, laps 5, cycling/virtualActivity, elapsed 600 s, timer 600 s, distance 5591.65 m, work 102.599 kJ, power avg 171 W max 260 W, cadence avg 90 max 95 rpm, matches its summary [fitsdk]
     lap 1: start 2027-01-15T08:00:00Z (+0 s), duration 120 s, "Warm-up"
fit_check: 1 file(s), 0 failed
```

`--json` prints one document:

```
{
  "ok": true,                      // every file passed
  "decoder": "fitsdk",             // or "gdscript" (fallback)
  "files": [{
    "path": "<absolute path>",
    "ok": true,
    "decoder": "fitsdk",
    "errors": ["..."],             // empty when ok
    "records": 601,
    "laps": [{"start": "<ISO UTC>", "start_unix": 0, "start_offset_s": 0, "duration_s": 120,
              "timer_s": 120, "distance_m": 0, "work_j": 0, "avg_power_w": 0, "name": "Warm-up"}],
    "session": {"sport": "cycling", "sub_sport": "virtualActivity", "start": "<ISO UTC>",
                "elapsed_s": 600, "timer_s": 600, "distance_m": 0, "work_j": 0, "kj": 0,
                "avg_power_w": 0, "max_power_w": 0, "avg_cadence_rpm": 0, "max_cadence_rpm": 0,
                "num_laps": 5},     // null if the file has no session
    "summary_checked": true        // a RideRecorder summary was compared
  }]
}
```

Lap names come from Wattlands' developer field `lap_name` (developer data index 0, field 0, string); other files show `""`.

## Fallback decoder contract

If `@garmin/fitsdk` can't be imported (npm blocked or `npm ci` not run), `check.mjs` prints `@garmin/fitsdk unavailable ...; using the GDScript decoder` on stderr and runs, once for all files:

```
tools/godot.sh --headless --path <repo> -s res://tools/fit_decode/decode.gd -- --json-out=<abs path> --file=<abs path> [--file=<abs path>...]
```

(through `$WATTLANDS_BASH`, else `bash`). The decoder (qa, `tools/fit_decode/decode.gd`) writes this JSON to `--json-out` and exits 0 even when a file is bad; `check.mjs` then applies the same checks:

```
{"files": [{
  "path": "<the --file value>",
  "is_fit": true, "integrity": true,      // header/size valid; header and file CRCs valid
  "errors": ["..."],                     // decode errors (empty when fine)
  "file_id": {"type": 4, "manufacturer": 255},
  "records": 601,
  "record_timestamps_monotonic": true,
  "has_gps": false,                      // any record with position_lat/position_long
  "laps": [{"start_time": <Unix s>, "total_elapsed_time": <s>, "total_timer_time": <s>,
            "total_distance": <m>, "total_work": <J>, "avg_power": <W>, "name": "<lap_name dev field or ''>"}],
  "session_count": 1, "activity_count": 1,
  "session": {"sport": 2, "sub_sport": 58, "start_time": <Unix s>, "total_elapsed_time": <s>,
              "total_timer_time": <s>, "total_distance": <m>, "total_work": <J>, "avg_power": <W>,
              "max_power": <W>, "avg_cadence": <rpm>, "max_cadence": <rpm>, "num_laps": 5},
  "timer_events": {"start": 1, "stop": 1}
}]}
```

Values are physical (scale and offset applied), enums are numbers, times are Unix seconds. `testdata/fake_decode.mjs` implements this contract with the SDK and is what the fallback test runs (`WATTLANDS_FIT_CHECK_SDK` and `WATTLANDS_FIT_DECODE_CMD` exist only for that test).

## Tests

`node --test` in `tools/fit_check` (needs `npm ci` first). `testdata/gdscript_ten_minute_ride.fit` and its `.json` were written by the GDScript `FitEncoder` and `RideRecorder` (`tests/rides/test_ride_recorder.gd`, `test_ten_minute_synthetic_ride`, which writes `build/rides_test/ten_minute_ride.fit` on every GUT run).

Every rides GUT run also writes `build/rides_test/paused_dropout_ride.fit` (`test_paused_ride_with_a_dropout_for_fit_check`: a jittered ~1 Hz feed, a timer pause, a trainer dropout and a cool-down without cadence). Both files have five laps, so `node tools/fit_check/check.mjs build/rides_test --expect-laps=5` checks them together (the rides CI workflow runs exactly that).
