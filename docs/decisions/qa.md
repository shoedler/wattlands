# Decisions: qa (end-to-end harness, screenshot tool, fallback FIT decoder, scenario tests)

Short ADRs for `tools/e2e/`, `tools/screenshot`, `tools/screenshot.ps1`, `tools/qa/`, `tools/fit_decode/` and `tests/scenarios/` (BRIEF 2, 3.6, 3.8, 7.4, 7.5, 7.7, 7.8).

## 2026-10-21: One Godot lease for the whole e2e run, peers through tools/godot.sh with the lease token

- Decision: `tools/e2e/run.mjs` takes one lease of 3 slots with `acquire({lease: 3})` from `tools/lib/godot_lock.mjs` before the first game and releases it after the last. Every peer, the restarted client and the GDScript FIT decoder fallback run through `tools/godot.sh` with `WATTLANDS_GODOT_LEASE_TOKEN=<handle.token>`, so none of them queues again. Each peer gets its own `--log-file <peer dir>/godot.log` (Godot 4.7.2 supports it) besides its own `--profile-dir`.
- Alternatives: one lease per game; starting the Godot binary directly.
- Reason: BRIEF 2 asks for one lease for all the harness's Godot instances; starting Godot directly would duplicate the wrapper's env, user-dir, timeout and `-d` rules (docs/decisions/tooling.md). A per-peer log file keeps three processes that share the checkout's `.userdata` from writing one `godot.log`.

## 2026-10-21: Same event sequence = the shared events, compared without arrival times

- Decision: events of types that are a peer's own view (session and app states, peer churn, uploads, rides, HUD messages, roster, snapshots; `PER_PEER_EVENT_TYPES` in `tools/e2e/lib/checks.mjs`) are left out; every other event (`phase_started` per rider, game events, `game_phase_changed`, `results`) must be identical on the host and `client1` after removing arrival-time keys (`t`, `wall_t`, ...) and the recording peer of a `results` event, numbers equal within 1e-6 relative. `final_state` is compared within 2 % (or 0.01) without the per-peer keys (`local_peer`, `fit_path`, `distance_m`, `phase_index`, ...). The restarted client must hold a tail of the host's sequence that ends with the results, after at most one replayed `phase_started` for its own rider.
- Alternatives: an inclusion list of event types; comparing raw events.
- Reason: game event types are open-ended (each game names its own), so only an exclusion list works for "any registered game"; arrival times differ by design. A rejoined client cannot have the events from before its restart; allowing more than one leading replay would hide gaps.

## 2026-10-21: Strict log scanning

- Decision: any `SCRIPT ERROR`, `Parse Error`, `Debugger Break`, `Ignoring script` or line starting with `ERROR:` / `USER ERROR:` (push_error output) in a peer's stdout, stderr or Godot log fails the run, including the killed client's output before the kill; `WARNING: ... desync` lines and `rate_limited` anywhere (peers and relay) fail too.
- Alternatives: only `SCRIPT ERROR`; an allow-list option.
- Reason: BRIEF 7.7 says "no script errors" and lists push_error output; an allow-list flag would be a way to weaken the gate (BRIEF 1, 7).

## 2026-10-21: The auto-upload peer is client1, with the mock's default test client

- Decision: exactly one peer, `client1` by default (`--auto-upload=`), gets `--strava-client-id=12345 --strava-client-secret=mock-client-secret --strava-auto-upload`. The harness lists the mock's uploads at `GET /admin/uploads` (other common admin paths are tried when that answers 404) before stopping it, and expects exactly one; the auto-upload peer's report must show one upload in state `uploaded` or `duplicate`, the others none. The secret is masked in logs and the report.
- Alternatives: the host uploads; dummy credentials.
- Reason: `client1` is never killed, so its upload runs once, from a client (the host path is covered by the rides tests). `server/mock_strava` checks the client secret on the token exchange, and these are its documented test credentials, never a real app's.

## 2026-10-21: Kill and restart

- Decision: the victim is `client2`. It is killed `--kill-after` (25) seconds after it prints `WATTLANDS_STATE running` (or `session`, `playing`, `started`, `warmup`), with its whole process tree (`taskkill /T /F` on Windows; on POSIX SIGTERM to its process group first, since the lock runner puts Godot in a group of its own and kills that tree on SIGTERM, then SIGKILL), and restarted after `--restart-delay` (3) seconds with the same `--profile-dir` and code. The reconnect passes when it prints the same `WATTLANDS_PEER` id again, is not refused with `session_in_progress`, exits 0 and gets the results.
- Reason: BRIEF 7.7 and ARCHITECTURE "Scripted peers"; a SIGKILL to the peer's group alone would orphan Godot on Linux.

## 2026-10-21: Duration excludes the cool-down as observed

- Decision: the 6-minute limit applies to the game's wall time minus the cool-down, measured from the host's `WATTLANDS_STATE cooldown` line to its next state line (or `--cooldown-s`, 180, when the host never reports it).
- Reason: BRIEF 7.7 excludes "the appended 3-minute cool-down"; measuring it avoids crediting a slow cool-down to the game.

## 2026-10-21: A test seam instead of mocking Godot

- Decision: `--peer-cmd`, `--relay-cmd`, `--strava-cmd` and `--fit-check-cmd` replace the four external programs; `tools/e2e/fixtures/` holds stand-ins that speak the same contracts and inject faults, so `node --test tools/e2e/test` exercises the whole orchestration (lease, room code, kill and restart, every check, `e2e_check.mjs`, exit codes) in about 40 s without Godot. Fixtures live outside `test/` because `node --test` treats every file under a `test/` folder as a test.
- Alternatives: unit tests of the pure parts only.
- Reason: the orchestration is where an e2e harness breaks; the real path was also smoke-run against Godot 4.7.2, the real relay and the real mock Strava from their builders' worktrees.

## 2026-10-21: tools/screenshot is a shim over one Node core

- Decision: `tools/screenshot` (bash) and `tools/screenshot.ps1` both run `tools/qa/screenshot.mjs`, which validates the flags, always adds `--mock-trainer` (refusing non-mock values, `--allow-hw`, `--allow-network`, `-d` and `--headless`), removes `FAL_KEY` and `WATTLANDS_ALLOW_ART`, and starts Godot windowed through `tools/godot.sh` or `tools/godot.ps1` with `--resolution 1920x1080 -s tools/qa/screenshot_main.gd`. On Linux without `DISPLAY` or `WAYLAND_DISPLAY` it wraps the run in `xvfb-run` (with `LIBGL_ALWAYS_SOFTWARE=1`) when installed, else prints `screenshot: skipped` and exits 0; `WATTLANDS_SCREENSHOT_NO_DISPLAY=1` forces the skip. The Godot side skips the same way on the headless display server.
- Alternatives: two parallel shell implementations.
- Reason: the same pattern as `tools/run_tests` (one tested core, identical behaviour in both shells).

## 2026-10-21: Screenshot modes and names

- Decision: game mode (`--game`, `--at`) drives `GameSimRunner` with `headless = false`, steps as fast as possible (in 50 ms slices between frames) to `--settle` (1 s) before each `--at`, then one fixed step per 0.05 s of frame time, and saves the window's frame (HUD included, the host's view) as `<game>_<content>_<players>p_<at>s.png` in `build/screenshots/<game>/`. `--scene=<res path>` saves `<folder>_<scene>.png` (so `world2d_demo.png` and `world3d_demo.png`) in `build/screenshots/scenes/` after `--frames` (30) frames; `--app-screen=title|picker|lobby` starts the main scene, switches `TrainerService` to a mock and calls `App.goto`, saving `app_<screen>.png` in `build/screenshots/app/`. The driver sets a throwaway `Paths` override in `_init` (before the autoloads start) unless `--profile-dir` is given, and deletes it on exit. Exit 0 when every shot was saved, 1 when one failed or none was taken, 2 on bad flags.
- Reason: BRIEF 3.6 and 7.8, docs/OWNERSHIP.md TL2 and C13; the user's real profile is never touched.

## 2026-10-21: The FIT decoder reports structure and Wattlands checks separately

- Decision: `QaFitDecoder` (`tools/fit_decode/lib/fit_decoder.gd`) decodes any FIT file generically (header and file CRCs, definition and data messages, compressed timestamps, both byte orders, developer fields, chained files) and keeps structural problems in `decode_errors`; `errors` adds the Wattlands checks (file_id type activity, first message file_id, records with non-decreasing timestamps, one session with sport 2 and sub_sport 58, `num_laps` matching, laps with start and duration, one activity, `--expect-laps`). Missing device_info or timer events are warnings. `decode.gd` prints a text summary or `--json` (one line; Godot prints its own header first, so `--out=<file>` is the clean way to read it), and for `tools/fit_check/check.mjs` it implements rides' fallback contract (`--file=`, `--json-out=`, decode errors only, Unix times, exit 0), documented in `tools/fit_check/README.md`.
- Alternatives: decode only the fields the encoder writes; one error list.
- Reason: an independent decoder that only knew the encoder's layout would share its bugs. check.mjs applies its own checks to the fallback's output, so that output must carry decode errors only.

JSON schema of `decode.gd --json` / `--out` (version 1):

```
{decoder: "wattlands-fit-decode-gd", version: 1, ok, failed, files: [{
  path, ok, errors: [String], decode_errors: [String], warnings: [String], is_fit, integrity,
  header: {size, protocol_version, profile_version, data_size, data_type, header_crc, header_crc_ok},
  crc_ok, segments, messages: {name: count}, file_id: {type, manufacturer, product, serial_number, time_created},
  records, record_span_s, record_gaps, record_timestamps_monotonic, has_gps, first_record_ts, last_record_ts,
  laps: [{index, name, start_time, start_s, duration_s, timer_s, distance_m, work_kj, avg_power_w, max_power_w, avg_cadence_rpm, max_cadence_rpm}],
  session: {start_time, timestamp, sport, sub_sport, elapsed_s, timer_s, distance_m, work_kj, avg_power_w, max_power_w,
            avg_cadence_rpm, max_cadence_rpm, avg_speed_mps, max_speed_mps, normalized_power_w, num_laps, first_lap_index} | {},
  sessions, activity: {timestamp, timer_s, num_sessions, type, event, event_type} | {}, activity_count,
  events, timer_starts, timer_stops, device_infos}]}
```

FIT timestamps (`start_time`, `*_ts`) are raw FIT seconds there; `start_s` is relative to the session start.

## 2026-10-21: Scenario tests live in tests/scenarios and are W2 gates

- Decision: the BRIEF 7.4/7.5 scenarios are GUT tests in `tests/scenarios/workout/` that drive `GameSimRunner` tick by tick through its frozen API and read each tick's `SafetyGovernor.status()` and MockTrainer samples on the rider's own platform clock (`GameHost.local_rider(peer)`; the map itself became private in W4 SAF-4). They decode each FIT in process with `QaFitDecoder` (no second Godot process) and compare it with `RideRecorderApi.summary()`. The decoder's and the helpers' own tests live in `tests/scenarios/unit/` so the full suite collects them; the W1 test command runs only that folder, because GameSimRunner, Workout, the governor and the recorder are stubs in this worktree. Report keys are read through one tolerant accessor file (`tests/scenarios/lib/scenario_lib.gd`) that matches sdk-runtime's report (`plans`, `phases`, `trace` keyed by peer id as strings).
- Rules encoded: compliant rider (erg 1.0, verified FTP 200, one bot) per built-in session: time in band >= 90 %, grade A or S, warm-up limits on every tick, no duration limit ever latching and an independent count of time above 105 % and 120 % FTP; coasting: floor `max(30 % FTP, 50 W)` reached within 3 s +/- one tick of the first not_pedaling sample, pause (SOLO) or AFK (two humans, HOST) within 10 s +/- one tick, for a `zero` rider and one who stops after 60 s of pedaling; rescue: one 8 s drop to 30 rpm per ERG phase (`at_target_pct=60` where a ramp crosses 60 %), rescue exactly when the applied target was >= 60 % FTP at the collapse, never a rescue without a collapse; a tree pause keeps samples and control responses flowing; a sample `.zwo` imports with listed clamps and plays inside them; FIT1 lap count (lap-true phases that started + lap markers + 1 for the cool-down).
- Reason: BRIEF 7.4 and 7.5 need tick precision (3 s plus one 0.05 s tick), which the 1 Hz report trace can't give.

## 2026-10-21: Hardening review (W1)

- **A rejoin's replayed phase may arrive late.** The relay forwards broadcasts to a client as soon as it is back, before the host has handled the rejoin and sent its `phase`, so the replayed `phase_started` can follow a few live events. `matchTail` now accepts at most one replayed `phase_started` for the rejoined rider among its first 8 events (`REPLAY_WINDOW`), and only when the host emitted that same event. *Alternative:* only a leading replay (the first version), which would fail a correct reconnect by timing alone. *Reason:* the check is about missing or reordered shared events, not about when a replay lands.
- **The upload check reads the mock's verdict.** Besides exactly one upload, `strava_upload` requires what `server/mock_strava` reports for it at `/admin/uploads`: `fit_valid` true, `data_type` fit, `trainer` 1 and no `error`, and the auto-upload peer's activity id must equal the mock's. Keys the mock doesn't report are not checked.
- **Lap names come from the field_description.** `QaFitDecoder` maps developer fields to names with the `field_description` messages and takes the lap name from the one called `lap_name`, instead of assuming developer index 0, field 0; without a description a lap has no name, as with the FIT SDK. Every timer event that isn't a start counts as a stop, matching the SDK model in `tools/fit_check/check.mjs`.
- **The decoder is checked against the FIT SDK on real files.** `tests/scenarios/unit/fixtures/` holds two FIT files the rides encoder wrote in W1 (`rides_ten_minute.fit`, a copy of rides' `tools/fit_check/testdata/gdscript_ten_minute_ride.fit`, SHA-256 6af82f30ab06435dcc29f2401fd63142f4b82c7a9d87cb264badbd36715d52bf; `rides_paused_dropout.fit`, the output of rides' `test_paused_ride_with_a_dropout_for_fit_check`, SHA-256 af1c832da4d537e179796c6b4945454964911e9bbd66bfaa9543d1634e94e888) and `rides_fit_sdk.json`, what `@garmin/fitsdk` 21.218.0 decoded from them through rides' `testdata/fake_decode.mjs` (the fallback contract's shape). `test_fit_decoder_vs_sdk.gd` requires `rides_contract()` to equal it field by field. *Alternative:* qa's own writer only. *Reason:* the writer and the decoder share one author; the SDK is the reference `check.mjs` uses, so the fallback must judge a file the same way.
- **Stricter W2 scenarios.** The session scenarios also require the governor's warm-up to be on for the first 300 s after the first pedaling sample (2 s margin) and the 150 % and long-phase 105 % caps on every tick; Workout's own `.zwo` session (found through `content/workout/sessions/<id>.json` with a `zwo` key) is played end to end through `GameSimRunner` and its clamps must appear in Workout's session preview. The tree-pause scenario checks the system nodes BRIEF 4.1 names (GameHost, LocalRider, SafetyGovernor, MockTrainer), not `GameSimRunner`, which is the test's driver, and proves the pause is real with an ordinary pausable node. The scenarios use the GameRegistry autoload, never a private registry, and make sure the game strings are registered before reading a preview (`ensure_game_strings`): a freed `WlGameRegistry` instance removes the shared Translation resources the autoload also added, so later lookups return raw keys (reported to sdk-runtime). Run against an overlay of every W1 branch (21 Oct 2026 heads), all thirteen W2 scenarios (90 tests with the unit tests) pass after these two test-side fixes.

## 2026-10-21 (W2 round 2): `--app-screen=session` shoots the app's real session screen

- Decision: `tools/screenshot --app-screen=session [--app-role=client|host|solo] [--app-game] [--content] [--at] [--app-overlay=menu|panic|none]` runs the main scene windowed and opens a real `AppSessionScreen`: as a client, the app's own lobby screen joins a room that an in-process headless host (`WlNetSession` + `GameHost` on a `LoopbackTransport` hub shared with the app's NetSession) opens, readies on `pedal_start` and follows the host's `session_start`, so the HUD is the one a client builds from that message; as a host, an in-process headless client joins the app's lobby and runs a CLIENT GameHost from the app's `session_start`. Shots at each `--at` (the app session's platform seconds, default 30) plus one with the ride menu or the panic overlay open; each prints the panic button's rect, the HUD's reserved bottom-right corner and that corner's stack. The logic lives in `tools/qa/screenshot_session.gd` (`QaScreenshotSession`).
- Alternatives: GameSimRunner windowed (its clients are always headless and it has no panic button or overlay); a scripted peer (`AppScriptedScreen` has neither).
- Reason: BRIEF 7.8 and the round-2 check of a CLIENT HUD built from `session_start`, with the panic-button corner and the overlay above the HUD, need the app's session screen itself.

## 2026-10-21 (W4): The e2e harness's relay command follows the Node version (W3 PKG-8)

- Decision: the default `--relay-cmd` is `node --experimental-strip-types server/relay/src/main.ts` on a Node without default type stripping (22.6-22.17, 23.0-23.5) and `node server/relay/src/main.ts` otherwise (`defaultRelayCmd()`); `--relay-cmd` still overrides it. `tools/e2e/test/relay_cmd.test.mjs` starts the real relay as Node 22.12 would (`--no-experimental-strip-types` first) and shows the old default fails there.
- Alternatives: raise the minimum Node to 22.18 (BRIEF 2 names 22.12).
- Reason: BRIEF 5.3 asks for the flag on 22.12-22.17; the harness never passed it. `tools/run_tests`' relay node-suite step needs the same (the lead's file).

## 2026-10-21 (W4r2): tools/screenshot --app-screen=results (W4r2 R26)

- Decision: `--app-screen=results [--app-riders=<1..8>]` opens the app's real results screen through `App.goto("results", ...)` with a Workout-like GameResults from `tools/qa/screenshot_results.gd` (`QaScreenshotResults.params`): ten intervals, best 1/5/20 min, four-digit sprint peaks, 16-character names, two unlocks, a real-length FIT path, and the host-left notice from two riders on, so the shot is the tallest page a rider can get. It prints the page height, the fit level and the lowest line, and saves `app_results_<n>p.png`.
- Alternatives: run a whole session to its results (about 30 minutes of sim time per shot).
- Reason: the results page must fit 1080p for 1 to 8 riders; a windowed screenshot shows what the headless layout test measures.
