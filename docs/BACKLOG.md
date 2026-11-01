# Backlog (P2 design notes)

Design notes only (BRIEF 1: P2 is never built in this run). Game-specific P2 notes live with each game (`src/games/<id>/README.md` or `BACKLOG.md`).

## Kart Rush (a future game)

- Versus for 2 to 8 riders, with bots filling slots: lane racing on a closed loop with 3 lanes and 3 laps.
- Elevation becomes course grade (`grade_source: course` or `game`), stacked by the governor (BRIEF 4.6.6).
- Drafting: 1 to 10 m behind another kart in the same lane cuts CdA by up to 30% and scales the `cw` factor sent to the trainer by the same factor (a relative factor in [0.5, 1.0], so it can only lower resistance).
- Position-weighted items (leaders get weaker ones): Tailwind, Headwind Cloud, Fender, Tow Rope. Every resistance effect is a haptic request to the receiver's governor (at most +3% for 8 s, 15 s cooldown), never a direct grade.
- Start: a neutral roll-out at ERG 60% FTP behind a pace car (warm-up content), then a ramped switch to SIM for the race.
- Results: positions, best lap, sprint peaks; grade from position and effort compliance; FIT laps per race lap.

## Platform

- HR-based balancing.
- A Wahoo Direct Connect (Bluetooth over TCP, DIRCON) backend for KICKR CORE 2 (`DirconTransport` behind `BleTransport`).
- OpenBikeControl input.
- Host migration when the host leaves (today the session ends gracefully).
- A Cloudflare Durable Objects relay (the Node relay's protocol is small enough to port).
- Uploads to intervals.icu or Garmin Connect next to Strava.
- Split screen with two trainers on one PC (two LocalRiders, two HUD lanes).

## Known gaps (follow-ups, not P2)

Found by the final Definition of Done sweep or left open by W3/W4 with a reason in `docs/DECISIONS.md`. None blocks a game session.

- Hardware and services: automated runs can't reach a real KICKR CORE or the real Strava API; `docs/HARDWARE_TEST_PLAN.md` and each game's `HARDWARE_TEST.md` are the pass to ride.
- Trainer: the app never launches the `trainer_bridge` exe itself (start `trainer_bridge serve` by hand when GDBLE can't be used); RESISTANCE is never used as a fallback for a trainer without ERG or SIM support (the governor doesn't read the FTMS target-setting feature bits); `CadenceEstimator.start_calibration()` has no caller, so a trainer that never reports cadence gets no estimate (the KICKR CORE reports cadence); a SIM-block request in the first 30 s of the first ERG phase is accepted by the DirectiveRouter and then refused by the rider's governor for switch spacing (the refusal is reported, the trainer is never wrong).
- Network: LAN hosting (`LanTransport`, P1) works but no menu starts it; a client's view can't reach `NetSession.host_time()` or `snapshot_pair_at()` (no net handle in `GameContext`), so games interpolate on snapshot ticks (`SnapHistory`); right after the host switches a lobby to RAW, a rider already marked ready counts at 75 kg for one round trip; a FIT lap is missing when a replan takes effect during a client outage; requests wait about 1 s under the 8-rider overload; `NetSession.set_trainer_status` is an uncalled API.
- Session: retrying trainer control inside a session (a pause-menu item) isn't offered; reconnect through Settings, Trainer. `QUIT_GRACE_S` uses a SceneTreeTimer, so its timing follows frame timing. A surge after slow soft-pedaling doesn't pick (ADR).
- Tooling: `tools/new_game` output needs one gdformat pass; the static step's workflow YAML check needs `uv` (skipped without it); bleak has no wheels for Python 3.15 (the bridge probe needs 3.12-3.14).
- Content: the platform's UI font is the BRIEF 3.9 fallback (Godot's default font), because downloading assets needs approval in chat.
- Audio, shared: the first-come 60 ms gap between a crew's sounds could give each machine a share, since a mate's machine gun can lose its strokes under Drive in a full crew (9 of 24 cadence mixes read under -1 dB; `seat_levels.test.mjs` reads one); `shapeOf` and `strokeOf` in `tests/games/tank/audio/diesel_stroke.mjs` could move to `tools/audio/lib/`; `SiegeAudio`'s arrow spread, shuffle, pile step and the alarm's crowd step could move to the kit; `live_report`'s arrow names could come from a bank field; crowd voices start on Godot's 512-sample grid (a 93.75 Hz line in 4-8 kHz, not yet heard); output above 13 kHz shows resampler images of 22 kHz files, which A9 and A17 can't see, in every game; A1 reads only the preview, while Castellum Rotae's solo session plays under its floor.
- Torque Company art: `TankEnemyDraw._hatch` stays only for `test_tank_art_round2`; the HALT LINE touches at 852 px (`advance_far`, `bow_duel`); the `near_ambush` seam clips the recon at 852 px; `TankForest.draw_base` floats a comb in `far_duel`; a tankette behind a recon in `near_ambush` can't be told apart.
- Ride menus: a recovery surge can still pick Resume, Panic or End in the ride menu; a surge can pick "Resume the trainer" on the panic menu (check it against BRIEF 4.6.5); the title's held first item takes a surge while `need_fresh` is true.
- Audio: A17 reads the top band at runtime pitch and holds only Siege, because the others would fail: Tank -27.41 (`turbo_whistle`), Fishing -18.26 (`prop_churn`), Workout -31.72 (`wind_rush`), against -32. Siege's A14 is waived with its numbers on the card. A ram's battering is unmeasured in a real wave. Torque Company's Steam seat is the next highest in the band its Lights left (loudest 186 ms +5.8 / +4.4 / +3.7 dB at 60 / 90 / 110 rpm).
- Shared code that could move: `quantize` and `encodeIndexed` to `tools/art/lib`; a help-point mapping hook and a per-game composition offset; `earBand` as a scorecard row of its own; the `SiegeShotSounds` pattern for any game with projectiles.
- `AppGameCard`'s image slot width varies with the title (441 and 534 today). `tools/picker_cards/` has no owner in `docs/OWNERSHIP.md` or the gate manifest.
- `docs/games/siege.md` still asks for a fixed 960x540 canvas and a creak pitched by watts; the owner's overrides are in `docs/decisions/siege.md` and `docs/decisions/audio-siege.md`.
- `_template` shows every SDK call in under 300 logical lines (`tests/tools/test_template_size.gd`: the limit counts without blank lines, comments and wrapped continuation lines); its files hold about 450 physical lines.
