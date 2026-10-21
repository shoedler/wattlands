### Rides, FIT and Strava (rides)

- Ride recorder: one record per second of platform time, laps at every phase marked `lap`, every `lap_marker` and the cool-down, timer pauses, and totals (work, distance, average and maximum power, cadence and speed). A trainer dropout longer than 3 s records 0 W instead of the last power.
- FIT export in pure GDScript (protocol 2.0, header and file CRCs, file_id, device_info, timer events, records, named laps, session as a virtual cycling ride, activity), saved as `rides/<UTC start>_<game>.fit` with a JSON summary and a ride UUID.
- Strava: connect your own Strava API app through a loopback callback on 127.0.0.1, rotating token refresh, upload with processing status, duplicates counted as uploaded, recovery from expired tokens and rate limits, an offline upload queue retried at launch, auto-upload, disconnect with revoke.
- Rides history with re-upload, and an opt-in import of FTP and weight from Strava (P1).
- `server/mock_strava`: a zero-dependency mock of Strava's OAuth and upload API for tests.
- `tools/fit_check`: decodes FIT files with Garmin's FIT SDK and checks sport, records, laps and totals (`--expect-laps`, `--json`).
- Offline Strava uploads stay in the upload queue however many launches pass without a network; only real upload failures (error responses) count toward the 8-attempt limit.
- The FIT files the scenario tests write are now also decoded with Garmin's FIT SDK (copied to `build/scenarios/`, which the fit step of `tools/run_tests` checks).
