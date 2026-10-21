# App shell decisions

## 2026-10-21: Screens built in code on one base, one active pedal-scan menu

- Decision: every screen (`src/app/screens/`) extends `AppScreen` and is built in code, not in `.tscn` files. A screen keeps a stack of `PedalScanList` menus (sub-menus for option values, steppers and the on-screen keyboard) and only the top one is active. Lists get `listen_to_input = false` and `set_process(false)`; the screen feeds InputRouter's actions and gestures to the active list (`feed_action`, `feed_gesture`) and drives its scan timer with `tick(dt)`.
- Alternatives: one `.tscn` per screen; every list listening to InputRouter itself.
- Reason: a screen often shows two lists (a field list and a value list); if each listened, one surge would pick in both. Driving time and input from the screen makes every screen testable headless with injected gestures and exact scan timing.
- Whether a menu scans comes from `InputRouter.pedal_ui_active()` (Autopilot or pedal UI on, or no input device used yet), with the profile's pedal UI or Autopilot flag as the fallback; the title holds its first item while the zero-touch countdown is armed.

## 2026-10-21: AppServices instead of autoload names in screens

- Decision: screens reach the autoloads only through `AppServices` (App, Settings, TrainerService, NetSession, GameRegistry, Rides, Sfx, InputRouter, EventBus, plus factories for `PedalScanList`, `GameHost` and `LocalRider`). `AppServices.goto()` calls `App.goto()`; if the App did not take the state (its W0 stub), it emits `navigated` and the main scene shows the screen anyway.
- Alternatives: call the autoloads by name everywhere.
- Reason: the W1 worktree only has stubs for those modules; injection lets every flow be tested with doubles, and the same code runs against the real autoloads after W2.

## 2026-10-21: Zero-touch rules on the title screen

- Decision: "pedaling" is the pedal_start condition (cadence >= 40 rpm or power >= 30% FTP) held continuously, timed by sample time: 5 s with a saved profile, 20 s on the first run. While the countdown is armed the title's menu holds its first item, which is the same quick ride (last-played game, else `GameRegistry.first_run_game()`, with its `zero_input_content`), so a surge also starts it. A keyboard or controller action disarms it for this visit. With a saved profile, a coast after pedaling does too, and the main menu then runs on pedal-scan, so a pedal-only rider can still host, join or open settings. On the first run a coast never disarms it (see "Coasting never takes a pedal-only rider out of a flow").
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

## 2026-10-21: A client sends player_info only when it changed

- Decision: the lobby keeps the last player_info it sent. On every lobby_state a client rebuilds its player_info (the host's scaling decides `p_eff_per_w`) and sends it only if it differs. Player-option defaults are filled in once per game, so an echo never resets an edited value.
- Alternatives: send on every lobby_state; send only on the first one.
- Reason: a host answers each player_info with a lobby_state broadcast. Sending on every lobby_state looped host and client for a game without player_options (Tank) and would hit the relay's rate limit. Sending only once left a stale `p_eff_per_w` after the host changed scaling.

## 2026-10-21: Coasting never takes a pedal-only rider out of a flow

- Decision:
  - First run: a coast never disarms the 20 s countdown; stopping only restarts the stretch. A device action still disarms it.
  - On-screen keyboard (code entry, text fields): the first back or coast only highlights Back; a second back, or picking Back, cancels.
  - Session paused by the platform (coasting, stop_5s): the overlay holds Resume and does not scan.
- Alternatives: treat coast as back everywhere (BRIEF 3.5 default).
- Reason:
  - First run: no profile means no scanning menu, so a disarmed countdown left a rider without input stuck on the title.
  - Keyboard: a rider who pauses while scanning six characters would lose the code.
  - Pause: from rest a surge (1.5 s) fires before pedal_start (3 s), so a scanning overlay could pick End ride or Panic when the rider starts pedaling again.

## 2026-10-21: Autopilot in the lobby, metronome in sessions

- Decision: the lobby has a per-session "My Autopilot" item for the local rider. It starts at the profile's default, goes out in player_info and shows on the rider's card; the profile default is not changed. The session screen starts the Sfx cadence metronome at the preferred cadence when the profile's metronome is on, and stops it when the screen goes. The main scene applies the saved master volume at boot.
- Alternatives: Autopilot only in the profile; leave the metronome to the HUD.
- Reason: BRIEF 3.5 says Autopilot is toggled "in the profile or lobby". Nothing else turned on the metronome or the saved volume, so those settings would have done nothing. Both calls are idempotent if ui-hud also makes them.

## 2026-10-21: Zero-touch hold after the launch visit needs a fresh start

- Decision: the launch visit to the title counts a pedaling stretch that is already running when the title opens. Later visits (back from a ride, the results or a menu) count the 5 s hold only after one sample without pedaling. A coast after that old stretch does not disarm the countdown. `AppServices.title_visits` counts the visits in one app run.
- Alternatives: arm the countdown only on the launch visit; arm it the same way on every visit.
- Reason: riders keep spinning after the cool-down, so a rider who picks Continue would otherwise be put into a new ride 5 s later. Arming only at launch would break "hold pedal_start 5 s on the title" for later visits.

## 2026-10-21 (W2): Sessions hand ticking to the GameHost through set_external_tick

- Decision: `AppServices.set_menu_ticking(on)` calls `WlTrainerService.set_external_tick(not on)` (the platform's name for the requested `set_menu_ticking`). The session screen, the scripted peer and the FTP test call it as before.
- Alternatives: ask platform for an alias `set_menu_ticking`; keep the duck-typed call.
- Reason: the duck-typed call found no method on the real service, so TrainerService and the GameHost both ticked the session rider on two clocks.

## 2026-10-21 (W2): The GameHost runs on wall time in every app run

- Decision: `AppSessionLauncher.build_config()` sets `config.realtime` (params `realtime`, default true): the session screen passes its `auto_process`, the scripted peer its own. Headless app runs (scripted e2e peers) therefore advance the GameHost's SimClock in `_process` like windowed ones; tests drive it by hand.
- Alternatives: step the GameHost from the screen's `_process`.
- Reason: the GameHost's default is `realtime = not headless`, meant for `GameSimRunner`; a headless app session never stepped.

## 2026-10-21 (W2): A client's GameHost gets the message that opened it

- Decision: right after `GameHost.start()` the shell re-emits on `NetSession.game_message` what made it create the client's GameHost: `params.replay` (a rejoin's plan/phase/snapshot) or else the host's `session_start` (`AppSessionLauncher.replay_messages`). The client's GameHost is still created inside that `session_start` emission, so the `plan` that follows it in the same poll reaches it directly.
- Alternatives: the GameHost reads `config.session_start` (asked of sdk-runtime in W1; its `_on_session_start` ignores a second copy, so both can coexist).
- Reason: a GameHost connects to `game_message` in `setup()`, after the `session_start` emission it was created in already went past it, so clients never left the lobby.

## 2026-10-21 (W2): SOLO and HOST sessions start after the tick that triggered them

- Decision: in the real app (screen `auto_process` on) the session screen builds its overlay at once and creates the GameHost with `call_deferred`; CLIENT sessions and tests start synchronously.
- Alternatives: harden `LocalRider.tick()` against `setup()` re-entering from its own gesture or sample signal (requested of platform as well); defer every navigation.
- Reason: Start is usually picked by a surge or the zero-touch sample, both emitted inside `LocalRider.tick()`; setting that rider up for the session there let the rest of the tick record menu time into the new ride (RideRecorder "time went backwards", the first seconds of the FIT lost).

## 2026-10-21 (W2): The session screen owns InputRouter.solo

- Decision: the session screen sets `InputRouter.solo = (role == SOLO)` at the start and back to true when it leaves.
- Alternatives: the GameHost sets it (ui-hud's W1 note; sdk-runtime's GameHost does not).
- Reason: `stop_5s` must map to pause only in a solo session (BRIEF 3.5); the shell already owns the session's lifetime.

## 2026-10-21 (W2): Scripted peers end the same way whichever clock runs out

- Decision: the scripted peer sets `App.run_seconds_exit_code = 2` and finishes through its own `finish()` on `App.quitting` (report, DONE line, exit 2 for `run_seconds`).
- Alternatives: ask platform to stop counting `--run-seconds` for scripted peers.
- Reason: `WlApp` also counts `--run-seconds` and quits on its own; without this its quit (exit 0, fallback report) could win the race.

## 2026-10-21 (W2): App tests drive the real PedalScanList

- Decision: `tests/app/fakes/fake_scan_list.gd` is the real `PedalScanList` plus read-only probes (`ids`, `text_of`, `index_of_id`, `is_disabled_id`, `picks`); `FakeRegistry.add_game` is `add_fixture`. Screens set `sounds = false` on their lists and play the UI cues themselves.
- Alternatives: keep the W1 double under private names.
- Reason: the double redeclared members of the real class and no longer compiled; the real list now exists and the screens should be tested against it.

## 2026-10-21 (W2): The GameHost reads input through the session screen

- Decision: the session screen hands its GameHost an `AppSessionInput` as `config.input_router`: the router's actions without `pause` (the screen pauses and resumes) and, while the overlay menu is open, without anything but `panic` (which always passes); gestures unchanged; `detach_rider()` at the session end re-attaches TrainerService's menu rider.
- Alternatives: let the GameHost own pause (then the overlay's confirm both picks an item and resumes); ask sdk-runtime to stop toggling pause (app-shell's W1 request, not taken).
- Reason: with the real GameHost a P press paused (screen) and resumed (GameHost, next tick), and a confirm on the overlay both picked the highlighted item and resumed; after a session the router had no rider, so results and menus lost pedal gestures.

## 2026-10-21 (W2): Overlay and panic button above the HUD

- Decision: the session screen puts its pause overlay and the panic button in a CanvasLayer at `HudLayer.LAYER + 10`; the panic button sits at the HUD margin in the bottom-right corner, grows left and up with its text, and the HudLayer keeps that corner clear (`reserve_corner`).
- Alternatives: keep them in the screen's canvas (drawn under the HudLayer CanvasLayer).
- Reason: seen in a windowed run on the real GameHost: HUD widgets and toasts drew over the overlay, the gear widget under the panic button, and the button's text ran off screen.

## 2026-10-21 (W2 round 2): The FTP test page drives the platform's FtpTest

- Decision: `AppFtpTestScreen` starts `FtpTest.run_on(rider, Settings, TrainerService)` after checking `FtpTest.build_plan()` with the PlanValidator (`ramp_test`), sets the rider up as a recorded ride (`ftp_test`), ticks it in fixed 0.05 s steps while menu ticking is handed over, and saves the ride when the cool-down ends, the rider ends it or the page is left, before handing the rider back. `src/app/ftp_test.gd` (`AppFtpTest`) is removed. The page follows FtpTest's flow: the 10 s save countdown runs as the cool-down starts (Save, Keep my old FTP), then End the cool-down; `back` cancels a running test without a result, keeps the old FTP during the countdown and ends the cool-down after it. While the test runs its menu doesn't scan and surge and coast pick nothing; stopping pedaling is FtpTest's coasting rule and keeps the result.
- Alternatives: keep the app's own protocol class; count down on a result page after the cool-down.
- Reason: two implementations had drifted (the app's ended on a cadence that never arrived, saved results from the ramp-in, and ignored rescue's own end); BRIEF 3.2 has one protocol. A hard ERG effort can read as a surge, which must not cancel or panic the test.

## 2026-10-21 (W2 round 2): W/kg opt-in on the profile page

- Decision: the profile page has a "Show my W/kg in rides" toggle for `RiderProfile.show_wkg` right after "Share weight with the host"; it is a normal pedal-scan field and saves at once.
- Alternatives: tie W/kg to `share_weight`.
- Reason: BRIEF 3.3 shows W/kg only if the rider opted in; seeing your own W/kg doesn't need your weight to leave the PC.

## 2026-10-21 (W2 round 2): The session overlay dims the HUD; the panic button looks like one

- Decision: the session overlay gets a full-screen scrim (black, 60%) under it in the top layer, and its panel is opaque (97%); an empty detail line is hidden. The on-screen panic button reads "PANIC" (the menu item keeps "PANIC: trainer safe") in white on red with a light-red border, at least 380 x 100. A test seam `AppSessionScreen.render_headless` builds the view and HUD under GUT's headless display server. The lobby's message line starts hidden.
- Alternatives: the 82% panel alone; a status-like panic label in the HUD's own colors.
- Reason: seen in tools/screenshot --app-screen=session as a client: the panic overlay's title ran into the sprint banner showing through the panel; the panic button looked like one more HUD panel, and its long label reserved 559 px of the bottom edge from the teammate strip. In the solo lobby an empty message line pushed the content down.


## 2026-10-21 (W4): A client's governor works from the rider's own profile (W3 SAF-1)

- Decision: `AppSessionLauncher.build_config` overwrites a CLIENT's own slot's `ftp`, `ftp_verified`, `haptics_on` and `haptic_intensity` with the rider's profile (`apply_own_profile`) before `LocalRider.setup`, on both the `session_start` and the rejoin (`lobby_state`) path. HOST and SOLO keep their lobby slot, which comes from their own `player_info`.
- Alternatives: trust the host's echo (an honest host only rounds the FTP); clamp the host's values to a range.
- Reason: BRIEF 3.3 ("ERG targets always come from each rider's own FTP") and 4.6.7 (each client validates locally). A host that sent FTP 5000 made the client's floor 1500 W; the host also removed the 0.85 unverified factor and turned opted-out haptics back on. The core's own check in `LocalRider.setup` and `SafetyGovernor.configure` is the trainer and core fixers' part.

## 2026-10-21 (W4): --sim-speed only drives a MockTrainer session (W3 SAF-3)

- Decision: `AppSessionLauncher.effective_sim_speed(device, requested)` gives the requested speed only for a `MockTrainer`; any other device runs the session clock at 1 and logs a warning. It is a local copy of the rule; the trainer area adds the TrainerService helper for its menu clock, and the launcher can switch to it when that lands.
- Alternatives: refuse to start; ignore the flag only above 1.
- Reason: every governor time rule runs on platform time, so x4 meant 120 W/s slew and 8 writes/s on a real trainer (BRIEF 4.5, 4.6.2), and x0.25 stretched rescue and coasting.

## 2026-10-21 (W4): Settings make the trainer safe before the link drops (W3 SAF-8)

- Decision: Disconnect, connecting another trainer and "use the mock trainer" first shut the menu rider's governor down (`LocalRider.shutdown()`: SIM flat, then Stop) and wait `SAFE_DRAIN_S` (0.5 s, the grace App.quit gives a real trainer) of screen time before the link drops; with a MockTrainer, no rider, a link that isn't ready or during a session they act at once. Leaving the page mid-wait drops the link at once (the rider is already safe). After Disconnect the shut-down menu rider is set up again (as TrainerService's menu reset does), because the manager hands the same `FtmsTrainer` back on the next connect and TrainerService then keeps its rider; without that the governor would stay dead and App.quit would skip it. After a switch the old rider stays shut down, so its commands never reach the new trainer.
- Alternatives: wait for the trainer area's TrainerService method (not merged when this round ran; the page has one helper, `make_trainer_safe_then`, to swap); drain by watching FtmsClient (the app never touches it, BRIEF 4.6.11).
- Reason: BRIEF 4.6.9 "on disconnect: try SIM flat, then Stop". Proven on the emulated KICKR CORE (`tests/app/test_settings_pages.gd`); the effect on a real trainer is a hardware check.

## 2026-10-21 (W4): Network notice on the session screen (W3 NET-6)

- Decision: the session screen draws a banner in its top layer (above the HUD): on a client `NET_HOST_DROPPED` from `peer_left(host)` until `peer_joined(host)` or `host_left`, and `NET_STATE_RECONNECTING` while its own NetSession is reconnecting (HOST and CLIENT). Sending `leave` when the host's window closes is the net area's part.
- Alternatives: a HUD toast (gone after a few seconds while the wait lasts up to 120 s); the pause overlay (the host's absence doesn't pause the client's ride).
- Reason: BRIEF 5.5; clients sat 120 s with no notice.

## 2026-10-21 (W4): Menus follow the rider's trainer mode and never ERG-auto-pick (W3 ZIH-6)

- Decision: `AppScreen.tick` passes the local rider's trainer mode (`local_trainer_mode()`: the InputRouter's attached rider; the session screen's own rider) to the active menu with `PedalScanList.set_local_mode`, without `follow_local_mode`. In ERG the hint reads "keep pedaling" and a coast doesn't back out.
- Alternatives: `follow_local_mode` (it also turns on ERG auto-confirm, which would auto-pick End ride or Panic in the ride menu).
- Reason: BRIEF 3.5 (coast never means back in ERG); the old hint told an ERG rider to stop pedaling, which only triggered the coasting floor and a pause.

## 2026-10-21 (W4): The first-run profile starts from the profile as it is (W3 PROF-3)

- Decision: both first-run paths (the 20 s rule and the form) copy the current profile (`AppFirstRunScreen.first_run_copy`) and set the name ("Rider" or the typed one) and `created`; the FTP is 200 W unverified (CP = FTP) unless it is already verified, which only an FTP test finished before the profile existed can do.
- Alternatives: copy only the Settings fields (haptics, Strava, pedal UI, audio) onto a fresh profile.
- Reason: BRIEF 3.2, 4.6.6: a haptics opt-out made in Settings before the first ride must hold; a verified FTP is more accurate than the 200 W default.

## 2026-10-21 (W4): One launch visit of the title (W3 PROF-1)

- Decision: the main scene records the state it showed before (`AppServices.previous_state`); a title built over a title (the App's deferred `boot()` shows it a second time at launch) is not a new visit.
- Alternatives: skip the App's second `goto("title")`; derive "fresh start" from the previous state alone.
- Reason: the launch visit counted twice, so a rider already pedaling at launch never got the 5 s start (BRIEF 3.5). Checked in the real app: `--mock-trainer=const:w=150,rpm=85 --run-seconds=25` with a saved profile now starts Workout and saves the ride.

## 2026-10-21 (W4): Imperial units edit the weight in pounds (W3 PROF-6)

- Decision: with `units` imperial, the profile and first-run weight fields show and step in whole lb (67-440 lb, inside the 30-200 kg range) and store kg; changing units rebuilds the field list. The weight is the only measured value the app shows the rider.
- Alternatives: remove the units choice; document it as stored only.
- Reason: BRIEF 3.2 lists units; a visible choice that changed nothing was a defect.

## 2026-10-21 (W4): Results: stats under the grid, W/kg, unlock names (W3 ZIH-1, PROF-5, ZIH-8)

- Decision: each rider's custom stats are a wrapped line under the rows grid ("Ada · ..."), the grid keeps its seven columns, and the side column with the summary line expands and wraps. When the rider opted in (`show_wkg`) an "x.x W/kg average" line follows the summary, computed from the local weight and never sent. Unlock ids show `<GAME_ID>_UNLOCK_<ID>` when the game has that string (as content labels use `<GAME_ID>_CONTENT_<CID>`), else the id.
- Alternatives: a W/kg grid column (would need every rider's weight); truncating the stats.
- Reason: a real Workout row made the grid 2599 px wide and pushed Upload, Continue and %FTP off a 1080p screen (BRIEF 3.3, 3.8, 3.9).

## 2026-10-21 (W4): Controls rows show one key and one pad binding (W3 ZIH-3, ZIH-4)

- Decision: a Controls row reads "Action: <first key>, <first pad binding>" with InputBindings' short labels; the content column lists every binding of every action. Leaving the page (coast, back, the Back item, leaving Settings) ends a capture, and the controller's B button cancels one as Esc does (so B can't be captured as a binding, like Esc).
- Alternatives: a two-line row with a detail line (14 rows would no longer fit 1080 px in height); truncating with an ellipsis.
- Reason: the long `as_text()` rows were 2635 px wide; a capture left armed rebound the next key or button pressed on Settings.

## 2026-10-21 (W4): Typing a room code needs no click (W3 ZIH-7)

- Decision: on the join page, the first key press of a code character (letters and digits, Crockford rules) while nothing has keyboard focus goes into the code field, which then takes the focus; arrows, Enter, Esc and Space keep their actions, and the on-screen keyboard keeps working for the controller and pedal-scan until the rider types.
- Alternatives: focus the field when the page opens (the screen then blocks every routed action but back and confirm, so the controller could no longer move the on-screen keyboard).
- Reason: APP_JOIN_HINT says "Type the host's code"; keys went nowhere until the field was clicked.

## 2026-10-21 (W4): A rider's own .zwo files in the lobby (W3 WO-1)

- Decision: for a game whose game.json lists the `zwo` content scheme, the host and solo lobby's content picker lists the game's contents and then every `*.zwo` in `Paths.user_dir()/workouts/` (created on demand) as `zwo:<absolute path>`, labelled by file name (`APP_CONTENT_ZWO`) and pedal-scan selectable; the page names the folder (`APP_LOBBY_ZWO_HINT`); the session preview shows the importer's clamps. The interactive lobby also takes `--content=<id>` for the game it opens, and a scripted host accepts any id `WlGameRegistry.content_allowed` accepts. A `zwo:` id whose file is gone falls back to the default content.
- Alternatives: a typed path field (long paths on the on-screen keyboard); only fixing the docs.
- Reason: BRIEF 3.7 makes .zwo import (Workout Director) P0; no app screen could produce a `zwo:` id, and HARDWARE_TEST.md 6 asks for `--content=zwo:<path>`.

## 2026-10-21 (W4): Strava FTP and weight import in Settings (W3 PROF-4)

- Decision: Settings -> Strava adds "Connect with profile access (for the import)" (`Rides.strava_connect_with_profile`), two toggles (FTP on, weight off by default) and "Import from Strava now" (`Rides.strava_import_athlete`, then the profile is saved); a status line names what was imported.
- Alternatives: import during the normal connect.
- Reason: BRIEF 3.8 P1 asks for an opt-in import; profile:read_all is only requested when the rider asks for it.

## 2026-10-21 (W4): The rides history re-uploads rides already on Strava (W3 RS-3)

- Decision: picking a ride whose upload state is uploaded or duplicate calls `Rides.reupload(ride_id)`; any other ride goes through `Rides.upload()`.
- Reason: BRIEF 3.8 P1 "Rides history with re-upload"; `upload()` only reports the stored state of an uploaded ride, so a ride deleted on Strava could not go up again.

## 2026-10-21 (W4r2): App.quit ends the tree, not the app shell (W4r2 R9/R10, W3 NET-6)

- Decision: `AppServices.quit` calls `App.quit`, then `last`, and calls `SceneTree.quit` only when the App is not quitting inside the tree (`app_ends_tree()`: a test double or a private App). A window close re-enters it through the main scene's "quitting" branch before App.quit has left the room; it now does nothing more, so App.quit leaves the hosted room, shuts the riders down and ends the tree itself after `QUIT_GRACE_S`. The "quitting" branch also freezes the current screen (`AppScreen.freeze()`: input disconnected, `_process` off on the screen and every node under it, a GameHost included), so during the grace only the TrainerService ticks the shut-down riders. `quit_hook` now stands in for `SceneTree.quit` alone.
- Alternatives: main.gd ignores "quitting" while App quits (leaves the scripted path, where AppServices.quit followed App.quit with an immediate `SceneTree.quit`, unfixed); `leave()` the screen on quitting (hands ticking back and re-sets the menu rider up before App.quit shuts it down).
- Reason: `SceneTree.quit` ends the process at the end of the frame, so the grace timer App.quit started afterwards never fired: no `host_left` reached the relay's linger and the governor's SIM flat and Stop (BRIEF 4.6.9) had no time to go out with a real trainer. `tests/app/test_quit_chain.gd` drives the real main.gd, AppServices and WlApp on a hosting loopback session.

## 2026-10-21 (W4r2): The results page fits 1080p by measured fit steps (W4r2 R16, R26)

- Decision: the results page never scrolls, so it is laid out to fit. The menu column holds the menu, the upload status and the host-left notice; the content column the grade, the local rider's summary and new unlocks, and the rows grid; the custom stats lines, the team line and "Ride saved" run the full page width below both columns (two lines for a real Workout row instead of four). While the page is taller than the screen (checked one frame after each layout change, also after a longer upload status), it takes the next fit step: a compact top row (grade at FONT_NUMBER, XP beside it), then only the local rider's custom stats (every rider's kJ, W, %FTP, NP, time in band and XP stay in the grid; each rider's own screen has their stats), then FONT_SMALL grid rows, then caps with an ellipsis (stats line 3 lines, team 1; then 1 or 2 lines everywhere). Pages with more than 3 rows start at the own-stats step. Real Workout stats (10 intervals, 4-digit sprint peaks, 16-character names, the Strava URL, unlocks, W/kg, the host-left notice) fit uncut from 1 to 8 riders; only stats as long as a 200-interval .zwo are cut. `tools/screenshot --app-screen=results --app-riders=<1..8>` shoots the real screen.
- Alternatives: a ScrollContainer (pedal-scan and zero-input riders can't scroll); fixed tiers by rider count (a long .zwo or a long status line still overflows); truncating every stats line to one line (loses the local rider's own numbers).
- Reason: W4 WO-2 made each stats line twice as long; from one rider the upload status (BRIEF 3.8) and with two or more the ride-saved line fell below a 1080 px screen.

## 2026-10-21 (W4r2): Results stats keep the game's order (W4r2 R18)

- Decision: `AppResultsScreen.stats_text` lists custom and team stats in the Dictionary's insertion order, which is the order the game added them; Protocol encodes without sorted keys, so clients show the host's order.
- Alternatives: a fixed key order in the app (the app can't know a game's keys); sorting (showed "Best 1 min, Best 20 min, Best 5 min").
- Reason: BRIEF 3.7 lists best 1-, 5- and 20-minute power in that order; WorkoutResults adds its stats in BRIEF order.

## 2026-10-21 (W4r2): Settings use TrainerService's safe unlink (W4r2 R6, R7; supersedes the W4 SAF-8 entry above)

- Decision: Settings' Connect, Disconnect and "use the mock trainer" call `TrainerService.connect_trainer(address)`, `disconnect_trainer()` and `use_mock()`, as the platform's SAF-8 decision says. The service shuts the rider down and drops the link only once the control point has sent SIM flat and Stop (up to its 3 s timeout); picking the trainer that is already linked connects at once and leaves the menu rider alone; the next ready trainer gets a new menu rider. The page's own fixed `SAFE_DRAIN_S` wait, its `_rearm_menu_rider()` and its "leaving the page drops the link at once" are gone: the wait belongs to the service and outlives the page. The page follows the service's connection manager (none with the mock) and shows "Making the trainer safe…" while `is_unlinking()`.
- Alternatives: keep the page's wait and only skip the same address (still too short for a retried write).
- Reason: a KICKR answering SIM flat later than 0.5 s lost the Stop (BRIEF 4.6.9), and re-picking the linked trainer left the menu rider shut down for good.

## 2026-10-21 (W4r2): A Strava import outlives the Settings page (W4r2 R20)

- Decision: `AppSettingsScreen.import_from_strava()` is a static coroutine that awaits `Rides.strava_import_athlete()` and then saves the profile and emits `profile_changed`; the page only shows the result. Leaving the page while GET /athlete runs still saves the import.
- Alternatives: import into a copy and apply it from the page (leaving the page would drop the import the rider asked for).
- Reason: Rides writes the values into the live profile while it waits, so a page freed mid-request left an imported, unsaved profile in memory.

## 2026-10-21 (W4r2): The Controls content column follows a rebind (W4r2 R28)

- Decision: ending a capture on the Controls page refreshes the content column (`all_bindings_text()`) as well as the rows; the unused `binding_text()` helper is removed (W4r2 R32/R44).
- Reason: InputBindings.rebind can take an input away from another action, so the list of every binding went stale until the page was reopened.

## 2026-10-21 (W4r2): Esc and the arrows keep working on the join page after typing (W4r2 R27)

- Decision: while the code field has the keyboard focus, Esc and the four arrow keys take the focus off it in the lobby's `_input` (which runs before the InputRouter autoload's) and go on unhandled, so the router routes them: Esc backs out (the first highlights Cancel, the second leaves), the arrows move the on-screen keyboard and the room lists. The next code character takes the focus back (ZIH-7). Backspace and Enter stay with the field.
- Alternatives: let WlInputRouter route these keys while a LineEdit has the focus (every text field in the app would lose its caret keys); never focus the field (the ZIH-7 typing needs it).
- Reason: WlInputRouter drops key presses while a LineEdit has the focus, so after one typed character a keyboard rider could neither back out nor reach Recent or LAN rooms.

## 2026-10-21 (W4fin): Controls get a Reset to defaults row; Esc and B still cancel a capture

- Decision: the Controls page's first row is Reset to defaults. It opens a Keep / Reset confirm with Keep highlighted, so a stray surge or Enter changes nothing; back, a coast or Keep returns unchanged. Reset calls `InputRouter.reset_bindings()` and then `save_bindings()`, which puts every project.godot default back (Esc and B on `back` included) and writes input.cfg. Esc and B keep cancelling a capture. A one-line help above the bindings list says so and names the Reset row, and the capture prompt reads "Esc or B cancels". Reset comes first because the 14 action rows and Back already run below a 1080p screen, so a last row would be scanned while off screen.
- Alternatives: let Esc and B be captured, with a timeout or an on-screen Cancel row as the only way out. A controller-only rider would lose the B-to-cancel habit that every other page keeps, and a pedal-scan rider would wait out a timeout. Reset with no confirm: one surge on the highlighted row would wipe every custom binding. Reset as the last row: off screen at 1080p.
- Reason: BRIEF 3.5 makes Esc and B the defaults for back and says everything is rebindable. `InputBindings.rebind` removes same-family inputs, so once back moved off Esc or B nothing in the UI could put them back, short of deleting input.cfg.

## 2026-10-21 (W4fin): The session's Autopilot turns pedal-scan on

- Decision: `scanning_enabled()` in the lobby, the session screen and results also counts this rider's Autopilot for the session. The lobby uses `my_autopilot`, and toggling it re-applies scanning to every open menu at once. The session uses its own slot's `autopilot` in the GameHost config (the lobby toggle, or the profile default for a quick start) and passes it to results as `params.autopilot`. It adds to `InputRouter.pedal_ui_active()` and never removes from it: switching Autopilot off for one session keeps scanning on when the profile default or pedal UI says so. An auto-pause still holds Resume without scanning.
- Alternatives: make the router aware of the session's Autopilot (an API change in ui-hud's frozen router); let the session's Autopilot also switch scanning off (a profile-default Autopilot rider who switched it off with pedals could lose the scan with no device to fall back on).
- Reason: BRIEF 3.5 says "with Autopilot or pedal UI on", and Autopilot is "toggled in the profile or lobby". Only the profile default reached the router, so a rider with pedal UI off and a device used who switched Autopilot on in the lobby got menus that didn't scan.
