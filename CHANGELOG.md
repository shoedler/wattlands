# Changelog

Releases, newest first. Modules and games write fragments in `docs/changelog.d/<module or game id>.md`; the lead merges them here at each release and empties them.

## v0.2.2 (2026-10-25)

### Turbo Reel

- The boat is much faster (15 m/s at FTP, about 20 min end to end on a map twice as long) and reacts to power within seconds: surges kick the bow up to 8 px high with spray and a long wake, and cutting power makes it visibly brake (bow digs in, foam mound, the wake collapses).
- The sea floor has a look per zone with terraces, drops, slopes and props (moorings and anchors, seagrass and starfish, coral and a reef arch, kelp, whale bones, caves, a wreck, basalt at the edge); landmarks show on the minimap.
- The fishing line is a little rope that sags and straightens with the fight, drawn as one smooth curve from the rod tip; each rod is in its player's colour.

### Platform

- Play-test with the mock trainer from the keyboard: T/G power, Y/H cadence (hold to ramp), presets for 50 to 250 % FTP on the numpad or M , . J K L U I O, N to stop, Shift to sprint; switch it on in Settings > Trainer. A small readout shows what the mock sends.

## v0.2.1 (2026-10-24)

### Turbo Reel

- New art direction after an adversarial art review against the Nemk reference: one cool 12-colour palette with a single brass accent, flat top-lit planes, no outlines, no dither or speckle, no rotated sprites, clean pixel-stepped lines, a light sea that steps darker with depth, a seated cyclist at the drivetrain, bow-up hull poses and a wake when you push hard, a waterfall that drops through air at the edge of the world.
- The HUD matches: a hand-made 5x7 pixel font, square borderless panels on the art's pixel grid, palette-only colours.

### Platform

- `HudSpec.palette` lets a game restyle the HUD kit's neutral chrome (colours, font and sizes, corners, outline, pixel grid, phase-strip colours). Defaults are unchanged; safety banners keep their colours.

## v0.2.0 (2026-10-24)

### Turbo Reel

- Free Roam (`roam_10` to `roam_60`, default `roam_30`): one shared ocean from the harbour to the edge of the world. Pedal your boat out (power sets the speed, SIM adds a gentle water drag), stop, and a light menu offers Cast at a fish you can see, Drive on and Turn around. Fights are ERG phases built at the bite; ten species from mackerel to a giant grouper and a legendary abyss fish; points by weight, most points wins. The first 5 minutes are a bite-free drive-out, and a fight on at time-up may finish (up to 5 more minutes).
- Bots fill empty seats with one of four strategies (vibe, small, mixed, big). Workouts (`base_60`, `threshold`, `e2e_2min`) troll across an endless map and keep their plans and co-op scoring.
- New look: hand-drawn muted pixel art, a brass pedal drivetrain boat, a full-width camera on your boat, a minimap with each rider's action and a leaderboard, and a waterfall at the edge of the world. The picker shows a card per mode with Free Roam featured.
- Strava gets "Free Roam N min" or the workout name, plus lines per rider (fish, biggest catch, points, rank, farthest out).

### Platform and app

- A rider who stops pedaling for 5 s is paused: the ride timer and, solo, the game clock stop and a pause symbol shows. In multiplayer the shared clock pauses only when every human rider is paused. The safety governor's rules are unchanged.
- Heart rate: connect a Bluetooth heart rate sensor in Settings > Trainer > Sensors. It shows in the power gauge, goes into the FIT file (record, lap and session) and the results screen, and is never sent to other riders.
- Pedal navigation is now opt-in (Settings, off by default): without it menus use the keyboard and controller only. With it on, a small graph shows the surge threshold.
- Profile, Settings and other long form pages scroll to their last entries.
- Strava activities are titled `WATTLANDS: <game> - <workout or mode>` and describe the game's stats, then moving time, distance, average and normalized power, average cadence and work.
- The product name shown to players is WATTLANDS.
- Game SDK (additive): `Telemetry.heart_rate_bpm`, `PlayerSlot.pedal_nav`, `GameResults.ride_tag` and `ride_lines`, and the `content_cards` manifest key.

## v0.1.1 (2026-10-23)

- Renamed the games (display titles only; the ids `siege`, `fishing` and `tank`, save files and string keys are unchanged): Generator Siege is now **Castellum Rotae**, and its map, formerly Castellum Rotae, is now **Collis Rotarum**; Big Game Fishing is now **Turbo Reel**; the upcoming Tank Crew is **Diesel Domestiques**.
- The Diesel Domestiques brief (`docs/games/tank.md`) now asks for a dark, desaturated 2.5D look with depth of field and cold and warm glowing lights; its pixel-art concept images were removed from `docs/concept/`.
- README rewritten and shortened: the games, downloads, playing with friends in other places (Tailscale or a hosted relay).

## v0.1.0 (2026-10-21)

The first release: the Wattlands platform and the reference game Workout, built in one autonomous run (W0 foundation, W1 sixteen parallel builders, W2 integration, W3 review, W4 fixes).

### lead

- Added `tools/run_tests` and `tools/run_tests.ps1` (one Node runner, `tools/lib/run_tests.mjs`): import, the full GUT suite with the strict gate (exit code, "Run Summary", JUnit count at or above the last green count, no forbidden log line, no pending or risky test outside `tests/pending_allowlist.txt`), the 7.3 scaffold check in a throwaway copy, `check_scripts` plus gdlint and `gdformat --check` (gdtoolkit 4.5.0, `./gdlintrc`) plus a PyYAML parse of every CI workflow (through `uv`, skipped without it), `tools/run_game_sim` over every registered game's contents, `tools/fit_check` on every FIT the sims and tests wrote, every Node suite (game folders under `tests/games/` included) and the 3-peer end-to-end test.
- Added the machine-wide Godot lock behind `tools/godot.sh` and `tools/godot.ps1` (FIFO tickets, leases, a 4-slot cap on this machine, exit 75 on a lock-wait timeout) and the per-checkout `.userdata/` user dir.
- Added `tools/export_windows.mjs`: the Windows Desktop export (the GDBLE DLL, LICENSE, CREDITS and third-party notices next to the exe), `--with-vcruntime` and `--smoke`.
- Added `export_presets.cfg` with a test that the Windows preset ships the GDBLE DLL, and `.github/workflows/lead.yml`, which runs every gate on Linux.
- Wired the app end to end: autoloads, the input map, the main scene, menus to lobby to session to results, and the merged docs (README, DESIGN, ARCHITECTURE, GAME_SDK, TRAINER, PROTOCOL, HARDWARE_TEST_PLAN, DECISIONS, OWNERSHIP, DEPENDENCIES, CREDITS).
- CI hardening after the first GitHub run: a tracked GUT count floor (`tests/green_count_floor.txt`), SIGTERM-first step timeouts that can't hang a job, explicit sim and GUT wrapper timeouts, the strict gate in the sdk-runtime and art-pipeline workflows, and uv in lead.yml for the workflow YAML check.

### platform

#### Unreleased (W1)

- `WlSettings` (autoload `Settings`): `profile.json` and `settings.json` under `Paths.user_dir()` with defaults for missing and corrupt files, type and range cleaning, atomic saves, `--relay` and `--strava-base` run-only overrides, recent rooms (8, newest first), last game, content and trainer, `create_profile()`, and `changed`/EventBus signals.
- `LocalRider`: the per-rider stack (cadence estimator, gestures, W' balance, speed model, safety governor, optional ride recorder) with per-tick telemetry carrying every `Telemetry` field, gesture, intent and ack queues, band forwarding to MockTrainer and the bus, laps on lap phases and the cool-down, pause requests, `finish_ride()`, `shutdown()` and `LocalRider.live_riders()`.
- `WlTrainerService` (autoload `TrainerService`): `--mock-trainer` or FTMS auto-connect, the menu-time rider attached to the InputRouter and ticked on its own clock, `set_external_tick`, `hold_rider`, `shutdown_all`, panic and status mirroring.
- `WlApp` (autoload `App`): the state machine, boot order, scripted peers (`is_scripted`, `launch_options`), `quit()` with governor shutdown on every exit path, `--run-seconds` and a fallback `--report`.
- `FtpTest` (P1): the BRIEF 3.2 ramp test with its end rules, best 1-minute power, 0.75 x best FTP, cool-down, save countdown and `back`.
- `AutoloadLookup`: run-time access to the autoloads for injectable services.
- Hardening: the session rider becomes the menu rider again when a session hands ticking back (after its ride is saved), profile changes during a session are applied then, `LocalRider.rebind_device()` keeps a session alive when a reconnect hands over a new trainer object, rebuilds and trainer switches save a ride still recording, setup clears a reused MockTrainer's bands and phase, FIT lap names translate strings keys, settings hold JSON values only, and a dropped `FtpTest` releases its hold.
- Default relay URL per build: `node tools/export_windows.mjs --relay-url=<ws:// or wss:// url>` writes `override.cfg` next to the exe, and Settings uses it as the default relay URL (a rider's own choice and `--relay` still win), so a friend joins with only the room code.

### trainer-core

- trainer-core: `FtmsCodec`, a pure FTMS codec (Indoor Bike Data with multi-notification records, Feature, power and resistance ranges, Machine Status, control-point responses, Cycling Power; every control-point encoder) with byte-exact golden vectors in `tests/vectors/ftms.json`.
- trainer-core: `FtmsClient` runs the BRIEF 4.4 connection flow (Device Information, Cycling Power fallback), serializes control-point writes (one in flight, 2 s timeout, two retries, coalescing), reports control lost ("another app may hold control") and failures, and refuses every control write under the hardware lock while still reading and subscribing.
- trainer-core: `FtmsTrainer` maps TrainerDevice setters to control-point payloads (the only `write_control` caller) and bike data to TrainerSamples.
- trainer-core: `MockTrainer` gains the `intervals`, `noise`, `band`, `cadence_drop` and `surge` profiles, W' fatigue, sprint cadence lag, SIM speed from the speed model, seeded dropouts, keyboard offsets and simulated control loss; the W0 behaviour is unchanged.
- trainer-core: `FtmsClient` coalescing never reorders control-point writes and never drops the first write of a mode switch; service discovery times out after 10 s; `MockTrainer.restart_profile()` restarts a profile's timers at session start.

### trainer-control

#### Added

- `SafetyGovernor` implements BRIEF 4.6.1-4.6.12: whole-watt ERG targets, the floor and ceilings, the 105 % cap for long phases, the 105 % / 120 % duration limits with latching and the inclusive 120 s reset, the unverified-FTP factor, the ramp_test profile, slew, rescue with its 10 s ramp-back, coasting (floor at 3 s, pause or AFK at 10 s), panic, SIM stacking with haptic bounds, warm-up, the exit path and rule 12 precedence.
- Directive channels (BRIEF 3.6) inside the governor: ERG target, SIM block, mode grade, haptic and factors, each with its own expiry; course grades coalesced to 2 Hz; course profiles followed by distance; applied records with `clamped_by`, refusals and dropped channels.
- `TrainerController`: ERG / SIM / RESISTANCE (P1) / OFF, slew, ramped ERG <-> SIM switches, at most 2 control writes per second, immediate panic and shutdown writes.
- `VirtualGears`: 24 gears as SIM grade offsets, 7 % per step at the 30 km/h reference.
- `CadenceEstimator`: cadence from flywheel speed when absent or stale, learned ratio and 10 s calibration.
- `tests/arch/test_no_bypass.gd`: the BRIEF 4.6.11 scan over `addons/wattlands` and `src`, with bypass fixtures.
- `content/strings/governor.csv`: banner and toast strings for rescue, warm-up, coasting, AFK, panic, duration limits, the FTP test end and the gear.

#### Fixed (hardening review)

- Rescue arms when the whole-watt governed target reaches floor(60 % FTP), so a target exactly at 60 % arms it at every FTP (4.6.1's whole-watt comparison).
- Opting out of haptics ends a running haptic at once.
- The no-bypass scan also guards `TrainerDevice.request_stop` (Stop): only `TrainerController` may call it.
- New tests: the frozen W0 API surface (methods, signals, status and record keys), both duration limits resetting together, factor and mode-grade expiry, the ramp span in the default range, the paused floor counting toward the reset, and a determinism check over a busy seeded ride.
- One shared not_pedaling detector (BRIEF 3.5): the governor calls `GestureRecognizer.is_not_pedaling`, so the governor, `CadenceEstimator` and the GestureRecognizer share one copy of 15 W and 20 rpm (`GameHost`'s rejoin check calls it too); new tests pin the exact edges of not_pedaling (15 W, 20 rpm) and rescue (45 rpm, 70 rpm, 75 % of the target).

### sim

#### Unreleased (W4 final, 2026-10-21)

##### Changed

- `Bots.RIDER_SPEC` is `erg:compliance=1.0+band`: bots follow the cadence band a game publishes for them (BRIEF 3.6 `cadence_band`), reaching its centre after a 2 s lag with seeded noise within ±1.5 rpm, and ride 90 rpm (88.5-91.5 rpm with the noise) without one. In ERG, a band step up of more than about 12% (in practice about 18% and up, because of the lag) makes a bot fire the `surge` gesture, as a human following the band would. Runs with bots get new `deterministic_hash` values.

#### Unreleased (W1, 2026-10-21)

##### Added

- `GestureRecognizer`: pedal_start, surge (power outside ERG, flywheel speed in ERG), coast, stop_5s and the shared not_pedaling detector, with arbitration and re-arming (BRIEF 3.5). New: `advance(t)`, `not_pedaling_s_at(t)`, `not_pedaling_since()`, `is_pedaling()`, `surge_baseline()`, signal `not_pedaling_changed(active)`.
- `SprintRule`: >= 1.2 x FTP, instantaneous or over a trailing window, with `held_s()` and `best_s()`. New: `current_w()`.
- `ZwoImport.parse_zwo` / `parse_zwo_file` (the class was `WorkoutImport` until W4; platform classes carry no game prefix): SteadyState, Warmup, Ramp, Cooldown, IntervalsT and FreeRide (SIM flat); unsupported tags skipped with warnings; the 5-minute warm-up prefix; clamps for the warm-up limits, the 150% and long-phase caps, the 105%/120% duration limits and the 30 s switch spacing, each listed with its reason. New: `clamp_records`, `prefix_inserted`, `total_s`, `ZwoImport.to_plan(result)`.
- `ZwoImport` guards: durations are rounded to whole seconds, a leading byte-order mark is ignored, IntervalsT `Repeat` is limited to 200 (with a warning), workouts longer than 24 h are rejected, and a missing file returns the full result shape.
- `content/strings/sim.csv`: labels, clamp lines, warnings and errors of the .zwo importer.
- `tests/fixtures/zwo/`: sample .zwo files for every tag, every clamp kind and broken files.
- Tests: gestures, sprint rule, the .zwo importer, a speed-model oracle sweep with game-feel parameters and effort scaling, and a hand-computed W' balance sequence; seeded property sweeps over random .zwo files and random gesture streams; a PlanValidator check of imported plans that runs once the real validator is merged.
- CI: `.github/workflows/sim.yml`.

##### Changed

- `ZwoImport`: a block split at the 300 s warm-up boundary keeps its full length for the 105% long-phase cap.

### ble

##### Bluetooth (ble)

- `GdbleTransport`: the trainer over the vendored GDBLE 0.6.0 (`ClassDB.instantiate`, every call by name), with exactly-once link events, UUID expansion, no-adapter as a warning, adapter loss and GATT resets from `ble_event`, and writes refused under the hardware lock.
- `BridgeTransport`: the same surface over the Python trainer bridge on `ws://127.0.0.1:8765` (loopback only), with open and request timeouts.
- `FtmsConnectionManager`: backend choice (GDBLE, then the bridge, then a clear "no adapter" status), the 0x1826 / KICKR scan filter, connect -> `FtmsClient.attach` + `begin()` -> `trainer_ready`, the last device remembered and auto-connected, reconnect with 1, 2, 4, 8, 15 s backoff followed by `reconnected(device)` so the governor restores its last safe mode, and "another app may hold control" on control lost.
- `tools/trainer_bridge`: the Python GATT proxy (bleak + websockets), a read-only `probe` (control only with `--allow-control`, a typed phrase and no hardware lock), FTMS parsers with golden vectors, unittest suites, a README and a PyInstaller spec.
- Tests: `tests/ble/` (GDBLE surface introspection, transport mapping with a fake GDBLE, the bridge transport against an in-process WebSocket server, the manager with fake transports and client).
- Hardening: a connect requested during Bluetooth start-up waits for the backend; a backend that never answers is skipped after 10 s; an adapter lost while idle shows "No Bluetooth adapter found" and comes back on the next scan; auto-connect keeps looking for the remembered trainer until it appears; an adapter loss under a live GDBLE link reconnects for real; a GATT reset after a control loss no longer takes control back; bridge connects can be cancelled and are idempotent on the bridge.

### relay

##### Added (relay)

- `server/relay`: the multiplayer relay from BRIEF 5.3, written in TypeScript and run by Node's type stripping. It supports `hello`, `create`, `join`, `msg`, `ping` and `leave`, and sends `created`, `joined`, `peer_joined`, `peer_left`, `host_left`, `pong` and `error`. Room codes are 6-character Crockford codes, and the relay normalizes typed input. It holds a dropped seat for 120 s; the seat's reconnect token stays the same across reconnects, so a lost reply can be retried. A dropped host's room is held for 120 s, and `host_left` goes out on an explicit leave, on host token expiry and at the 4 h room lifetime. Every BRIEF limit is enforced: 8 peers, 16 KB, 60 messages a second with a burst of 120, a 60 s idle timeout and 10 joins a minute per IP. P1: `create` may ask for a previous code.
- The relay prefers the `ws` 8.22.0 package. Without it, it uses its own zero-dependency RFC 6455 server (`RELAY_WS_IMPL=auto|ws|builtin`).
- `GET /health` reports JSON status and counts. The WebSocket is at `/v1`, by default `ws://localhost:8787/v1`, and `PORT`, `HOST` and `RELAY_TRUST_PROXY` configure the server. On start the relay prints `WATTLANDS_RELAY <url>`.
- Additive protocol fields: `created.max`; `joined.rejoin` and `joined.peers`; `peer_joined.rejoin`; `host_left.reason` (`left`, `timeout` or `expired`); and `error.detail`, `error.re` and `error.proto` (on `version_mismatch`).
- The relay ships with a Dockerfile (`node:24-alpine`, non-root, `HEALTHCHECK` on `/health`), a README, and example `fly.toml` and `render.yaml` files.
- Tests: 180 `node:test` cases run in about a second with an injected clock. The same protocol and frame suites run against both WebSocket layers.
- CI: `.github/workflows/relay.yml` runs the suite with zero dependencies and again with `ws`, then builds the image and checks `/health`.

### net-client

##### Networking (net-client)

- `Protocol`: encode/decode for the relay envelope and every game message, required-field and type checks, schema-version rejection, int conversion (top-level ids, `*_id` keys at any depth, schema and `int_fields()` paths with `[]` and `{}`, peer-keyed dictionaries), exact round trips.
- `RelayTransport`: WebSocket client for the relay (hello, create/join, 15 s pings, error codes, drops with the reconnect token).
- `LoopbackTransport` and `LoopbackHub`: the relay's semantics in-process, for tests and simulations, with drop and latency fault injection.
- `WlNetSession`: host-authoritative lobby (slot looks, bots and bot FTP, ready-up with version checks, options and player options), offline SOLO lobby, routing rules, 16 KB limit, directive coalescing, telemetry intent caps, clock offset, snapshot buffer with interpolation, reconnect and rejoin, `session_in_progress`, graceful `host_left`.
- `NetRoster`: the 2 Hz roster builder; `LocalRelayServer`: the relay protocol served by Godot.
- `docs/PROTOCOL.md`: the relay protocol, every game message, int conversion, versioning, reconnect and limits.
- Hardening: `leave()` cancels a join or create in flight; coalesced directives hold their 100 ms at any poll rate; the lobby refuses `player_info` beyond `max_players`; `set_local_profile()` without games uses the game registry (`WlNetSession.registry`); rate-limited rejoins are retried; the host stamps `telemetry.tm.peer` with the sender; clients clear the snapshot buffer on rejoin and when a session starts or ends; `RelayRooms` keeps one reconnect token per peer; `LoopbackTransport.drop(peer)`; readable texts for every Transport reason.
- Privacy (BRIEF 3.2): no client learns another rider's shared weight in RAW either: `lobby_state` and `session_start` carry 75 kg for every other human, and `player_info` carries `weight_kg` only while the lobby is RAW (`WlNetSession.wire_player_info()`). A client's ready waits for its first `lobby_state` and follows the `player_info` for that scaling, so a RAW host never starts a rider who shared the weight at 75 kg.

### rides

##### Rides, FIT and Strava (rides)

- Ride recorder: one record per second of platform time, laps at every phase marked `lap`, every `lap_marker` and the cool-down, timer pauses, and totals (work, distance, average and maximum power, cadence and speed). A trainer dropout longer than 3 s records 0 W instead of the last power.
- FIT export in pure GDScript (protocol 2.0, header and file CRCs, file_id, device_info, timer events, records, named laps, session as a virtual cycling ride, activity), saved as `rides/<UTC start>_<game>.fit` with a JSON summary and a ride UUID.
- Strava: connect your own Strava API app through a loopback callback on 127.0.0.1, rotating token refresh, upload with processing status, duplicates counted as uploaded, recovery from expired tokens and rate limits, an offline upload queue retried at launch, auto-upload, disconnect with revoke.
- Rides history with re-upload, and an opt-in import of FTP and weight from Strava (P1).
- `server/mock_strava`: a zero-dependency mock of Strava's OAuth and upload API for tests.
- `tools/fit_check`: decodes FIT files with Garmin's FIT SDK and checks sport, records, laps and totals (`--expect-laps`, `--json`).
- Offline Strava uploads stay in the upload queue however many launches pass without a network; only real upload failures (error responses) count toward the 8-attempt limit.
- The FIT files the scenario tests write are now also decoded with Garmin's FIT SDK (copied to `build/scenarios/`, which the fit step of `tools/run_tests` checks).

### sdk-runtime

#### 0.1.0 (W1)

- GameRegistry: scans `src/games/*/game.json`, validates every field (naming the failing one), hides invalid games with a logged reason, never lists `_template`, warns about a missing or unreadable `picker_image`, loads each game's translations (reference-counted across registry instances), resolves `options`/`player_options` and picks the first-run game by `first_run_priority` (ties to `workout`, then the lowest id).
- PlanValidator: warm-up limits for the first 300 s, the 150% ceiling, the 105% cap for phases longer than 300 s, 105%/120% duration accrual with the 90%/120 s reset (open-ended phases at `max_s` and `min_s`), `range_pct` and `ramp_to_pct`, structural rules, the mode-switch warning and the appended 3-minute cool-down; finalized plans re-validate.
- GameHost: SOLO, HOST and CLIENT sessions with per-rider phase tracking (duration, `max_s`, `end_phase`, `finished`), the cool-down, SOLO pause on coasting, rescue and AFK callbacks, drops and rejoins (stale power zeroed, the phase clock restored), 10 Hz snapshots, 2 Hz roster, ordered event batches, 5 Hz client telemetry with intents, gestures and acks, results with a row per rider, `apply_progress` once per peer and FIT saving; rendering sessions read the local rider's gestures from the InputRouter and feed the metronome.
- `ctx.directives` (DirectiveRouter), `ctx.hud` (HudRouter), `ctx.intents` (IntentRouter) and `ctx.stats` (SessionStatsTracker): host-side directive checks and routing (a SIM block the governor refuses is taken back), course-grade coalescing, cadence and power bands, toasts and banners per peer, kJ, average and normalized power, best 1/5/20-minute power and time in band.
- GameSimRunner: the `tools/run_game_sim` and `tools/screenshot` engine and flag parser; SOLO or HOST with loopback clients, bots, FTPs, Autopilot, haptics, options, player options and content overrides; `complete`, `timeout` and `paused` endings; the JSON report with `deterministic_hash`; FIT files per human slot.
- `tests/sdk/test_conformance.gd` and SdkConformance: the BRIEF 3.6 / 7.3 checks for `_template` and every registered game.

### sdk-tools

#### 0.1.0

- The template game `_template` (`src/games/_template/`): a tiny 2D game that shows every SDK call in under 300 lines, with two contents, string keys, unit tests on recording fakes and integration tests through the real runtime.
- `tools/run_game_sim` and `tools/run_game_sim.ps1`: headless game sessions with MockTrainer riders, every BRIEF 3.6 flag, the locks enforced twice, relative paths from your current directory, `--echo-args`, exit codes 0/2/3/4/5.
- `tools/new_game` and `tools/new_game.ps1`: scaffold a game from the template (renamed classes, keys, paths and files; no `.uid`/`.import`/`.translation`; the game's CI workflow and docs fragments), refusing to overwrite an existing game.
- `docs/GAME_SDK.md`: the game contract, the tools, the report, the mock rider profiles, the safety rules and an FAQ for the game briefs.
- `tools/run_game_sim` exits 5 when Godot logged a script error during the run, deletes the previous report and FIT files at its `--report` path before running, checks slot lists against `--players` and `--bots`, and passes `--mock-trainer=erg`.
- `tools/new_game` refuses an id whose class names already exist in the project.
- The template validates every content phase at load.

### world-kits

##### world-kits

- `PixelViewport`: renders a 2D game view at its `pixel_base` with nearest filtering, integer device-pixel scaling and black letterbox bars; `art_rect_to_screen()`, `art_to_screen()`, `screen_to_art()`, `art_scale()` and `layout_changed` for the HUD; headless-safe `capture()` and `capture_scaled()`.
- 2D parts driven by a signed speed signal (-1..1): `SpinningPart` (gears, flywheels, cranks, reels; ratio, phase, inertia, angle snapping), `SlidingPart` (reciprocating pistons and scrolling links), `ScrollingChain` (code-drawn chains, belts and tank tracks round any number of wheels).
- `ParallaxStrip`: repeating backdrop strips at any factor >= 0 with `mirror_alternate` tiling, drift and vertical placement, scrolled by a world x.
- Shaders with helpers: `PaletteSwap` (key color ramp to a player's slot ramp) and `SpriteWobble` (pixel-snapped sine wobble with falloff; fish-tail and water presets).
- `PixelImportPreset`: checks and writes the lossless, mipmap-free import preset for pixel sprites; `PixelPainter`: procedural pixel sprites (text rows, gears, discs, dithered gradients, tileable hills).
- world3d: `LowPolyMesh` (flat-shaded vertex-colored primitives, merging per material, ground darkening, vertex haze), `MultiMeshScatter` (seeded scatter with exclusions, per-frame instance updates, path placement, walk-bob shader), `MiniatureCameraRig` (high three-quarter view, limited orbit, push-in, decaying shake) and `SkyAmbient` (Compatibility sky, ambient, shadowed sun and depth-fog haze).
- Demo scenes `addons/wattlands/world2d/demo.tscn` and `addons/wattlands/world3d/demo.tscn`, built entirely from procedural art.
- P1: `DitherDissolve` (ordered-dither fade for pixel-art effects) and `ScreenVignette` (corner darkening under the HUD, 12% by default).

### ui-hud

##### ui-hud

- Input router (`InputRouter`): keyboard and controller actions from the project input map, rebinding saved to `input.cfg`, Backspace held 1 s and View+Menu panic straight to `EventBus.panic_requested`, the local rider's pedal gestures, and pedal-UI menu input (surge confirms, coast backs out outside ERG, stop for 5 s pauses solo).
- `PedalScanList`: single-switch scanning for menus, shops and pickers, with focus moves, disabled items and ERG auto-confirm after two scan cycles (`item_chosen(..., auto)` and `item_picked(..., via)`).
- HUD kit: power gauge with a target band that glows in band, cadence with its band, W' bar, phase timeline with next-phase preview, teammate strip with slot chips (color, shape, pattern, hollow), toasts, rescue, warm-up and pause banners, big readouts and the gear indicator; `HudLayer` places them at anchors or at art-pixel rects through the `PixelViewport` and follows the session bus.
- Shared Theme and `WlTheme` sizes and colors (Godot's default font until Atkinson Hyperlegible is added).
- `Sfx`: fifteen synthesized effects, game-registered clips, looping synth clips and a cadence metronome.
- HUD: the rescue banner always shows (`show_safety_banners = false` now hides only warm-up and pause), and a lost trainer control mid-ride (Request Control 0x05 or Machine Status 0xFF) shows "another app (Zwift, the Wahoo app) may hold control" in the banner area until the trainer is ready again, also when control was already lost before the session started.

### app-shell

#### Added

- Main scene that shows the screen for `App.state`. At launch it loads the profile, applies the saved master volume, starts the trainer backend and retries the upload queue.
- Title screen with zero-touch start:
  - Hold pedaling 5 s to ride the last-played game solo.
  - On a first run, 20 s of pedaling creates the profile "Rider" (FTP 200, unverified) and starts the first-run game from the GameRegistry. A pause in pedaling restarts the 20 s instead of cancelling them.
  - Back on the title after a ride, spinning on never starts another ride: the 5 s hold starts after a stop.
- First-run, profile and settings screens. Settings covers:
  - trainer scan, connect and mock;
  - Strava client ID, secret, connect, disconnect and auto-upload;
  - haptics, control rebinding, volume and metronome;
  - relay URL, pedal-scan menus and scan interval.
- Game picker with picker images or generated title cards, summaries and player counts.
- Lobby for solo, hosting and joining:
  - The room code is shown as K7Q-X2M.
  - Code entry has an on-screen keyboard for controller and pedal-scan; a coast keeps a half-typed code.
  - Content, scaling and every game option type; int steppers stay on the option's step grid.
  - Player options and a per-session Autopilot toggle on the rider's own card.
  - Bots and the bot FTP, trainer status and ready-up per rider, and the session preview.
  - Clear messages for refusals.
  - A client resends player_info only when it changed, such as when the host changes the scaling mode, so lobby_state echoes never loop.
- Session screen around the GameHost:
  - a pause overlay (after a coasting pause, the first surge resumes);
  - an on-screen panic button;
  - the cadence metronome when it is on.
- Results screen with grade, rows, XP, unlocks, the saved ride and Upload to Strava (auto-upload honoured). A session without results shows no grade.
- Scripted peers for the end-to-end test: `--host`, `--join=<code>`, stdout lines, report JSON and exit codes. A session without results, or `--strava-auto-upload` without a Strava connection, exits 1.
- P1: Recent rooms, a LAN room list (when NetSession provides one), rides history with re-upload, and the FTP test.
- The Controls page in Settings has a Reset to defaults row (Keep / Reset confirm) that brings back every default binding, Esc and B included, and saves input.cfg; the page says Esc or B cancels a capture. Autopilot switched on in the lobby turns pedal-scan on for the lobby, the session's pause menu and results. Settings pages taller than the screen (Controls; Strava at 1080p) scroll so the highlighted row stays in view.

### art-pipeline

- Art pipeline (BRIEF 3.10): `node tools/art/generate.mjs --game=<id>` generates sprites on fal's GPT Image 2.5 (sunburst, flare for drafts) with a per-request manifest (`assets/<id>/art_manifest.json`, spend total), a local cache, recovery of paid results from fal's 24-hour history, a budget stop, `--dry-run`, `--only`, `--reroll`, `--select` and the art lock (`FAL_KEY` plus `WATTLANDS_ALLOW_ART=1`, or `--mock`).
- `tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=<id>` turns each sprite's selected result into palette-only pixel art: trim, fit/cover/tile/mirror without stretching, area averaging, Oklab quantization, parts and `sprites.json`, byte-identical on re-runs; it removes stale part files and warns when a selected result no longer matches `art.json`.
- `tools/art/mock_fal`, a zero-dependency fal stand-in for tests (queue API, generated PNGs, request history, billing and failure injection), and `node tools/art/pixelate_e2e.mjs`.
- `docs/ART_PIPELINE.md`: setup, budgets, writing `art.json`, drafts, selection, recovery, part animation and a worked example.

### workout

##### Added (Workout)

- Workout, the reference game (BRIEF 3.7): a group interval ride for 1–8 riders with bots, where everyone rides the same timeline at their own % FTP.
- Sessions Easy 30 (default, first-run and zero-input), Sweet spot, Threshold, VO2, Rolling road (30 minutes of SIM on a seeded rolling course, −2% to +6%), E2E (2 minutes inside the warm-up limits) and a sample `.zwo`; `--content=zwo:<path>` imports any `.zwo` file, with its clamps in the session preview.
- Time in band per interval and rider (ERG ±5% of the applied target, Rolling road 76–105% FTP, sprints cadence ≥ 60 rpm), sprint scoring at 1.2 × FTP, group grade S–D, kJ, average and normalized power, best 1/5/20-minute power, XP, levels and cosmetic pennant unlocks.
- A 640 × 360 side-scrolling ride view: parallax landscape, one pennant per rider (slot color, shape and pattern), the course profile in Rolling road and the interval blocks on the ground; HUD layout with timeline, power gauge, cadence, W′, teammate strip, big readouts and the gear indicator; a procedural picker card.

##### Changed (Workout)

- A client's ride view draws the other riders between snapshots, behind the newest by the snapshots' mean spacing (100 ms at 10 Hz, about 1 s under the 8-rider load), and the local rider from its own prediction, blended softly toward the host and never moving backwards (BRIEF 5.1).

### qa

##### qa

- Added `node tools/e2e/run.mjs --games=<ids>`: the multiplayer end-to-end test (BRIEF 7.7). One host and two headless clients per game under one 3-slot Godot lease, the relay and the mock Strava server on free ports, a client killed and restarted mid-session, and checks for identical events, final state, clamped directives, warm-up limits, script errors, desync, rate limits, FIT files, the single auto-upload, the reconnect and the 6-minute budget. Writes `build/e2e/<id>/report.json` and runs the game's `tests/games/<id>/e2e_check.mjs`.
- Added `tools/screenshot` and `tools/screenshot.ps1`: windowed captures of a game session at given sim seconds (with `tools/run_game_sim`'s flags), of a scene such as a kit demo, or of the title, picker and lobby screens; skips cleanly without a display.
- Added `tools/fit_decode/decode.gd`: an independent GDScript FIT decoder (CRCs, all message forms, the Wattlands activity checks) with text and JSON output, and the fallback contract `tools/fit_check/check.mjs` uses when `@garmin/fitsdk` is unavailable.
- Added the BRIEF 7.4/7.5 simulation scenarios for Workout in `tests/scenarios/` (time in band and grade per session, warm-up and duration limits, coasting floor and pause/AFK timing, the 60 % rescue rule, trainer I/O while the tree is paused, `.zwo` import, FIT checks against the recorder).
- The fallback FIT decoder reads lap names through their field description and is checked field by field against Garmin's FIT SDK on real ride files; the end-to-end test also checks the mock Strava server's verdict on the uploaded FIT.
