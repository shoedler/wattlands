# Lead decisions

## 2026-10-21: Godot binary is Simon's .NET 4.7.2 build

- Decision: run and test with `C:\Projects\.tooling\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe` (reports `4.7.2.stable.mono.official.ed1daf0bf`). The wrappers resolve `$GODOT`, then `tools/godot_bin.local` (gitignored, machine-local) in this or the main checkout, then `godot` on PATH.
- Alternatives: download the standard build (BRIEF 2); require `GODOT` in every shell.
- Reason: the user named this binary for running and testing; BRIEF 2 allows a .NET build for that. Exports need the standard build's export templates (BRIEF 7.10), documented in the README.

## 2026-10-21: Frozen W0 stubs for cross-module classes

- Decision: besides `addons/wattlands/contracts/`, W0 wrote stub files with frozen public signatures for every class another module calls (governor, LocalRider, GameHost, NetSession, registry, HUD layer, pedal-scan list, pixel viewport, ...). Owners fill the bodies and may add API, never change it.
- Alternatives: contracts as abstract base classes only; let each W1 agent design its own API and reconcile in W2.
- Reason: 15 builders work in parallel; a frozen, documented call surface keeps W2 merges mechanical.

## 2026-10-21: Autoload classes are named Wl<Name>

- Decision: autoload `X` is an instance of `class_name WlX` (`WlEventBus`, `WlNetSession`, ...).
- Alternatives: no class_name on autoload scripts.
- Reason: Godot refuses a script class with an autoload's name; named classes let tests and in-process simulations create private instances (one EventBus and NetSession per simulated peer).

## 2026-10-21: Two clocks, fixed steps, no wall clock in rules

- Decision: one `SimClock` drives platform time (always runs: trainer, governor, mock riders, telemetry) and game time (stops on pause: `sim_step`, phase elapsed, directive expiry). Real-time play feeds wall deltas to `SimClock.advance`; headless runs call `step()`.
- Alternatives: `_process` deltas everywhere; `Engine.time_scale`.
- Reason: BRIEF 3.6 and 6 demand fixed 0.05 s steps and determinism; BRIEF 4.1 needs trainer I/O to keep running while the game is paused.

## 2026-10-21: Game events go through GameModule.game_event

- Decision: `GameModule` gets an additive `signal game_event(event)` and `send_event(event)`; the GameHost batches events (at most 10 messages per second), sends them in order and calls `apply_event` on clients only. Every event has a `"type"` key, which `int_fields()` uses.
- Alternatives: `ctx.events` (the EventBus) for game events.
- Reason: BRIEF 3.6 names `apply_event` but no emitter; the game briefs need ordered, batched events.

## 2026-10-21: PlayerSlot field names

- Decision: the FTP field is `ftp` (watts); the Autopilot flag is `autopilot`; the look fields are `color`, `shape`, `pattern`, `hollow`. Backticked BRIEF names are kept exactly (`ftp_verified`, `p_eff_per_w`, `rider_mass_kg`, `preferred_cadence_rpm`, `haptics_on`, `is_bot`, `options`); `haptic_intensity` is added.
- Reason: the game briefs refer to "the slot's FTP" and "Autopilot flag" without code names.

## 2026-10-21: Window base size and stretch

- Decision: base viewport 1920 x 1080, `canvas_items` stretch with `expand` aspect, window override 1280 x 720 for windowed runs.
- Alternatives: stretch disabled with the HUD scaling itself.
- Reason: HUD sizes are specified at 1080p (BRIEF 3.9); a 640 x 360 PixelViewport stays integer-scaled at 720p, 1080p and 1440p.

## 2026-10-21: Phase kinds, modes and rule names are strings

- Decision: `Wl.WARMUP`, `Wl.ERG`, `Wl.SOLO`, `Wl.CLAMP_*` and friends are String constants.
- Alternatives: GDScript enums.
- Reason: they appear verbatim in JSON content, network messages and run_game_sim reports.
