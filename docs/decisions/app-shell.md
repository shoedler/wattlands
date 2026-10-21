# App shell decisions

## 2026-10-21: Screens built in code on one base, one active pedal-scan menu

- Decision: every screen (`src/app/screens/`) extends `AppScreen` and is built in code, not in `.tscn` files. A screen keeps a stack of `PedalScanList` menus (sub-menus for option values, steppers and the on-screen keyboard) and only the top one is active. Lists get `listen_to_input = false` and `set_process(false)`; the screen feeds InputRouter's actions and gestures to the active list (`feed_action`, `feed_gesture`) and drives its scan timer with `tick(dt)`.
- Alternatives: one `.tscn` per screen; every list listening to InputRouter itself.
- Reason: a screen often shows two lists (a field list and a value list); if each listened, one surge would pick in both. Driving time and input from the screen makes every screen testable headless with injected gestures and exact scan timing.

## 2026-10-21: AppServices instead of autoload names in screens

- Decision: screens reach the autoloads only through `AppServices` (App, Settings, TrainerService, NetSession, GameRegistry, Rides, Sfx, InputRouter, EventBus, plus factories for `PedalScanList`, `GameHost` and `LocalRider`). `AppServices.goto()` calls `App.goto()`; if the App did not take the state (its W0 stub), it emits `navigated` and the main scene shows the screen anyway.
- Alternatives: call the autoloads by name everywhere.
- Reason: the W1 worktree only has stubs for those modules; injection lets every flow be tested with doubles, and the same code runs against the real autoloads after W2.

## 2026-10-21: Zero-touch rules on the title screen

- Decision: "pedaling" is the pedal_start condition (cadence >= 40 rpm or power >= 30% FTP) held continuously, timed by sample time: 5 s with a saved profile, 20 s on the first run. While the countdown is armed the title's menu holds its first item, which is the same quick ride (last-played game, else `GameRegistry.first_run_game()`, with its `zero_input_content`), so a surge also starts it. A keyboard or controller action, or a coast after pedaling, disarms it for this visit; the main menu then runs on pedal-scan, so a pedal-only rider can still host, join or open settings.
- Alternatives: a separate splash screen; counting pedal_start gestures; scanning the menu during the countdown.
- Reason: scanning during the countdown would let the start-of-pedaling surge pick a random item; holding the quick ride makes the two zero-input paths agree, and coast gives pedal-only riders the full menu.

## 2026-10-21: Session seed

- Decision: the host's session seed is `--seed` when given, else `SeededRng.derive(utc_start, "<game>|<content>")` masked to 30 bits. The ride's UTC start stamp is the app's only wall-clock read (`AppServices.utc_now()`).
- Alternatives: `randi()`; a fixed seed.
- Reason: BRIEF 3.6 forbids global RNG and wall clock in rules; sessions still need variety; 30 bits survive JSON's float numbers in `session_start`.

## 2026-10-21: Who starts a session

- Decision: solo: `pedal_start` (or Start ride) readies and starts at once. Host: Start ride readies the host and starts as soon as every human is ready (`NetSession.all_ready()`) and there are at least `min_players` slots; `pedal_start` only readies, so a room never starts before friends join. Clients ready with `pedal_start` or the Ready item and follow the host's `session_start`. Coast or back on a lobby menu highlights Leave instead of leaving.
- Alternatives: auto-start a hosted room when everyone present is ready.
- Reason: zero-input solo play and hosting (a surge on Start ride) both work, and a rider who stops pedaling in the lobby never drops out of the room.

## 2026-10-21: Opening the client's GameHost

- Decision: a client opens the session screen on `session_start`, and on a rejoin when the host's `plan`, `phase` or `snapshot` arrives while it is still in the lobby. The GameHost config carries the session_start payload (players, seed, options, scaling) and the key `"session_start"`; the message that opened the session is re-emitted on `NetSession.game_message` right after `GameHost.setup()` and `start()`, so the new GameHost sees it.
- Alternatives: create the client GameHost when the lobby fills; ask the host to resend.
- Reason: messages arrive in one poll; the GameHost is created synchronously in the handler, so only the triggering message would be lost.

## 2026-10-21: Scripted peer details (end-to-end contract)

- Decision: exit codes 0 complete, 1 error, 2 `--run-seconds` hard stop, 3 refused (including `missing_game`, `version_mismatch`), 4 host left before the results. `WATTLANDS_ROOM` prints the code without the dash (`--join` accepts both). `WATTLANDS_STATE` prints `lobby`, then every GameHost/EventBus session state once per change. Report events: `session_state` {state}, `phase_started` {index}, `game_event` {event_type, event} (host: `GameModule.game_event`; clients: each `event` batch minus platform types), `results` {grade, session_id}; directives deduplicated by peer, id, kind and t; the trace samples the local rider's governor status at 1 Hz of platform time. The host lingers 2 s after its results so they reach the clients. On exit: `App.quit(code)`, then the report and `WATTLANDS_DONE`, then `SceneTree.quit(code)`. A failed or timed-out upload (150 s) or Strava connect (90 s) is an error.
- Alternatives: exit 0 on any end; the App writing the report.
- Reason: the harness needs distinct failures; writing after `App.quit` means nothing overwrites the report.

## 2026-10-21: The results screen performs the auto-upload

- Decision: with Strava connected and auto-upload on (`Rides.auto_upload_enabled()` or the profile flag), the results screen (and the scripted peer) calls `Rides.upload()` once without a prompt; a state already reported for the ride counts as started.
- Alternatives: Rides uploads on `ride_saved` by itself.
- Reason: one caller means exactly one upload (the e2e test counts them); the results screen already shows the state.

## 2026-10-21: Option editing in the lobby

- Decision: toggle and choice options and int options with at most 12 values open a value list; longer int ranges open a stepper (−step, +step, ±5 steps). A missing label key shows the option id; a missing choice label key shows the raw value; content labels fall back to the bare id (BRIEF 3.6).
- Alternatives: always a stepper; always a list.
- Reason: a value list is one pick on pedal-scan; 16 values (Siege's wave offset) at 1.6 s each would take too long to scan.

## 2026-10-21: FTP test runs on the app's rider (P1)

- Decision: the FTP test page builds `AppFtpTest`'s plan (ramp-in, 60 s steps rising 6% of FTP up to min(1000 W, trainer max)), finalizes it with `PlanValidator.finalize(plan, {"ramp_test": true})`, configures the governor with `profile: "ramp_test"` and ticks the rider in fixed 0.05 s steps itself; FTP = 0.75 x best 1-minute power, saved after 10 s unless back.
- Alternatives: a GameModule for the test.
- Reason: games live under `src/games/` and the GameHost has no ramp_test profile; the protocol logic stays pure and tested.

## 2026-10-21: Recent rooms

- Decision: `Settings` key `recent_rooms` holds up to 8 rooms {code, role, game_id, game_title}, newest first; the join page lists them; a host reclaims its last code through `NetSession.host_room(max, code)` when NetSession takes that second argument.
- Alternatives: a separate file under `Paths.user_dir()`.
- Reason: settings.json already persists through Paths; the call degrades to a new code until net-client adds the argument.
