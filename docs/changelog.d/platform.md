# Changelog: platform

## Unreleased (W1)

- `WlSettings` (autoload `Settings`): `profile.json` and `settings.json` under `Paths.user_dir()` with defaults for missing and corrupt files, type and range cleaning, atomic saves, `--relay` and `--strava-base` run-only overrides, recent rooms (8, newest first), last game, content and trainer, `create_profile()`, and `changed`/EventBus signals.
- `LocalRider`: the per-rider stack (cadence estimator, gestures, W' balance, speed model, safety governor, optional ride recorder) with per-tick telemetry carrying every `Telemetry` field, gesture, intent and ack queues, band forwarding to MockTrainer and the bus, laps on lap phases and the cool-down, pause requests, `finish_ride()`, `shutdown()` and `LocalRider.live_riders()`.
- `WlTrainerService` (autoload `TrainerService`): `--mock-trainer` or FTMS auto-connect, the menu-time rider attached to the InputRouter and ticked on its own clock, `set_external_tick`, `hold_rider`, `shutdown_all`, panic and status mirroring.
- `WlApp` (autoload `App`): the state machine, boot order, scripted peers (`is_scripted`, `launch_options`), `quit()` with governor shutdown on every exit path, `--run-seconds` and a fallback `--report`.
- `FtpTest` (P1): the BRIEF 3.2 ramp test with its end rules, best 1-minute power, 0.75 x best FTP, cool-down, save countdown and `back`.
- `AutoloadLookup`: run-time access to the autoloads for injectable services.
- Hardening: the session rider becomes the menu rider again when a session hands ticking back (after its ride is saved), profile changes during a session are applied then, `LocalRider.rebind_device()` keeps a session alive when a reconnect hands over a new trainer object, rebuilds and trainer switches save a ride still recording, setup clears a reused MockTrainer's bands and phase, FIT lap names translate strings keys, settings hold JSON values only, and a dropped `FtpTest` releases its hold.
- Default relay URL per build: `node tools/export_windows.mjs --relay-url=<ws:// or wss:// url>` writes `override.cfg` next to the exe, and Settings uses it as the default relay URL (a rider's own choice and `--relay` still win), so a friend joins with only the room code.
