# Backlog (P2 design notes)

Design notes only (BRIEF 1: P2 is never built in this run). Game-specific P2 notes live with each game (`src/games/<id>/README.md` or `BACKLOG.md`).

## Kart Rush (a future game)

- Versus for 2 to 8 riders, with bots filling slots: lane racing on a closed loop with 3 lanes and 3 laps.
- Elevation becomes course grade (`grade_source: course` or `game`), stacked by the governor (BRIEF 4.6.6).
- Drafting: 1 to 10 m behind another kart in the same lane cuts CdA by up to 30% and scales the `cw` factor sent to the trainer by the same factor (a relative factor in [0.5, 1.0], so it can only lower resistance).
- Position-weighted items (leaders get weaker ones): Tailwind, Headwind Cloud, Fender, Tow Rope. Every resistance effect is a haptic request to the receiver's governor (at most +3% for 8 s, 15 s cooldown), never a direct grade.
- Start: a neutral roll-out at ERG 60% FTP behind a pace car (warm-up content), then a ramped switch to SIM for the race.
- Results: positions, best lap, sprint peaks; grade from position and effort compliance; FIT laps per race lap.

## Games

- Help overlays (`HudSpec.help`, F1) for Castellum Rotae (`siege`), Workout and Diesel Domestiques (`tank`): each game's next session writes its entries (what the HUD shows, the controls, the safety stop). Turbo Reel has one.

## Platform

- HR-based balancing.
- A Wahoo Direct Connect (Bluetooth over TCP, DIRCON) backend for KICKR CORE 2 (`DirconTransport` behind `BleTransport`).
- OpenBikeControl input.
- Host migration when the host leaves (today the session ends gracefully).
- A Cloudflare Durable Objects relay (the Node relay's protocol is small enough to port).
- Uploads to intervals.icu or Garmin Connect next to Strava.
- Split screen with two trainers on one PC (two LocalRiders, two HUD lanes).

## Known gaps in v0.1.0 (follow-ups, not P2)

Found by the final Definition of Done sweep or left open by W3/W4 with a reason in `docs/DECISIONS.md`. None blocks a game session.

- Hardware and services: nothing has run against a real KICKR CORE, the real Strava API or the real fal API; `docs/HARDWARE_TEST_PLAN.md` is the first pass. CI has never run on GitHub (the workflows parse and their commands ran green locally).
- Trainer: the app never launches the `trainer_bridge` exe itself (start `trainer_bridge serve` by hand when GDBLE can't be used); RESISTANCE is never used as a fallback for a trainer without ERG or SIM support (the governor doesn't read the FTMS target-setting feature bits); `CadenceEstimator.start_calibration()` has no caller, so a trainer that never reports cadence gets no estimate (the KICKR CORE reports cadence); a SIM-block request in the first 30 s of the first ERG phase is accepted by the DirectiveRouter and then refused by the rider's governor for switch spacing (the refusal is reported, the trainer is never wrong).
- Network: LAN hosting (`LanTransport`, P1) works but no menu starts it; a client's view can't reach `NetSession.host_time()` or `snapshot_pair_at()` (no net handle in `GameContext`), so Workout interpolates on snapshot ticks; right after the host switches a lobby to RAW, a rider already marked ready counts at 75 kg for one round trip; a FIT lap is missing when a replan takes effect during a client outage; requests wait about 1 s under the 8-rider overload; `NetSession.set_trainer_status` is an uncalled API.
- Session: retrying trainer control inside a session (a pause-menu item) isn't offered; reconnect through Settings, Trainer. `QUIT_GRACE` uses a SceneTreeTimer, so its timing follows frame timing. A surge after slow soft-pedaling doesn't pick (ADR).
- Tooling: `tools/new_game` output needs one gdformat pass; `.github/workflows/sim.yml` runs with `--no-lint`; the static step's workflow YAML check needs `uv` (skipped without it, as on the Linux CI image); bleak has no wheels for Python 3.15 (the bridge probe needs 3.12-3.14).
- Content: the UI font and the audio are the BRIEF 3.9 fallbacks (Godot's default font, synthesized cues), because downloading assets needs approval in chat.
- `_template` shows every SDK call in 296 logical lines (the 300-line limit counted without blank lines, comments and wrapped continuation lines); its files hold 452 physical lines.
