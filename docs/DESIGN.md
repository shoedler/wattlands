# Wattlands design

The player-facing and game-design view of the platform: what a rider sees, what the rules are, and the numbers behind them. "BRIEF x.y" is a section of `docs/BRIEF.md`. Every number here is taken from the merged code on `main`; where the code and the BRIEF differ, the code is described and the difference is listed under [Known differences](#13-known-differences). The trainer stack itself (FTMS, the governor's internals, MockTrainer) is in `docs/TRAINER.md`; the game contract is in `docs/GAME_SDK.md`.

Nothing here has run against a real trainer yet. `docs/HARDWARE_TEST_PLAN.md` is the checklist.

## 1. Pillars (BRIEF 3.1)

1. **The trainer is controller and force feedback.** Effort is the input; resistance is the output.
2. **Fair for mixed fitness by default; raw power always visible.** FAIR_FTP scaling is the default, and the HUD always shows raw W and %FTP.
3. **Low attention.** Decisions every 10–30 s at most, a HUD readable from 3 m, Autopilot for everything.
4. **Real training.** Sustained work in ERG, sprints in free simulation (SIM), warm-up and cool-down built in.
5. **Safe by construction.** Every path to the trainer goes through one `SafetyGovernor` per rider (section 11, `docs/TRAINER.md`).

## 2. Rider profile and FTP test

### 2.1 Profile (BRIEF 3.2)

`profile.json` in `Paths.user_dir()` (`RiderProfile`, loaded by `WlSettings`). No accounts. A missing file means defaults; a corrupt one means defaults plus a warning; out-of-range values are clamped.

| Field | Default | Range (load clamp) | Notes |
| --- | --- | --- | --- |
| `display_name` | Rider | 16 chars in the editor | |
| `color` | `#D55E00` | profile palette | Shown in menus only; sessions use the slot look (section 10) |
| `units` | metric | metric, imperial | |
| `weight_kg` | 75 | 20–300 | Never leaves the machine unless `share_weight` is on |
| `share_weight` | off | | Also turns on the W/kg display |
| `ftp_w` | 200 | 30–2000 (editor 50–600) | Typing it sets CP = FTP and marks it verified |
| `ftp_verified` | false | | Unverified: every ERG target × 0.85 |
| `cp_w` | = FTP | 30–2000 | CP for the W′ model |
| `wprime_j` | 20000 | 1000–100000 (editor 5–40 kJ) | |
| `preferred_cadence_rpm` | 90 | 30–160 | Metronome, bots, MockTrainer |
| `drivetrain` | cassette | cassette, single_speed | Stored only; virtual gears work for everyone |
| `difficulty_pct` | 50 | 0–100 | Scales SIM course and mode grade |
| `haptics_on`, `haptic_intensity_pct` | on, 70 | 0–100 | Settings → Haptics |
| `grade_min_pct`, `grade_max_pct` | −5, +10 | −10…0, 0…+16 | The user's SIM grade range |
| `skip_warmup` | off | | Skips the governor's warm-up caps only (plans still open with warm-up content) |
| `autopilot_default` | off | | |
| `pedal_ui`, `scan_interval_s` | on, 1.6 s | 0.5–10 s | Pedal-scan menus |
| `strava_auto_upload` | off | | |
| `metronome` | off | | Cadence metronome in sessions |

The host only receives what the session needs (`player_info`, BRIEF 5.5): name, look, FTP and `ftp_verified`, `p_eff_per_w`, preferred cadence, haptics flag, Autopilot flag, player options, installed games, and the weight only if shared.

### 2.2 FTP test (BRIEF 3.2, P1; Settings → FTP test)

The app runs `AppFtpTest` (`src/app/ftp_test.gd`) on the app's rider through `AppFtpTestScreen`, with the governor's `ramp_test` profile and the plan finalized by `PlanValidator.finalize(plan, {ramp_test: true})`.

| Part | What happens |
| --- | --- |
| Ramp-in | 300 s ERG ramp 50 → 65 % FTP (a WARMUP phase, lap) |
| Steps | 60 s ERG phases at 65 %, 71 %, 77 % … of the current FTP (+6 % FTP per step), each a lap, while the step target ≤ min(1000 W, trainer max) |
| Ends on | power < 90 % of the applied target for 10 s; cadence < 50 rpm for 5 s; a rescue trigger; the Stop item or `back`; the last step. (A `coast` would end it too, but `coast` never fires in ERG; a stop is caught by the power and cadence rules within 5–10 s.) |
| Cool-down | 180 s ERG at 50 % FTP. After a rescue, rescue's 50 % stands and never ramps back. `back` here skips to the result. |
| Result | FTP = round(0.75 × best rolling 60 s power). The result page offers Save and Keep and saves automatically when its 10 s countdown ends; `back` or Keep keeps the old FTP. Saving sets FTP, CP = FTP and `ftp_verified`. |
| `ramp_test` profile | Suspends the duration limits, the 105 % long-phase cap, the 150 % cap and the unverified factor. The ceiling is min(1000 W, trainer max). Slew, the floor, the warm-up cap, rescue, coasting and panic still apply. |

The ride is recorded (game id `ftp_test`) and saved like any other.

## 3. Effort scaling (BRIEF 3.3; `EffortScaling`)

A lobby setting chosen by the host (`scaling_mode`, default FAIR_FTP). Each client computes its own effort and P_eff and sends both in telemetry, so the host never needs anyone's weight. ERG targets always come from each rider's own FTP; scaling changes only how effort turns into game output.

| Mode | effort | P_eff (W) | `p_eff_per_w` | Speed-model mass |
| --- | --- | --- | --- | --- |
| FAIR_FTP | P / FTP | (P / FTP) × 250 | 250 / FTP | 75 kg |
| WKG | P / weight | (P / weight) × 75 | 75 / weight | 75 kg |
| RAW | P | P | 1 | weight if shared, else 75 kg |

The speed model (BRIEF 3.11, `SpeedModel`) adds 8 kg to the mass and integrates `v += dt·(η·P_eff / max(v, 1) − m·g·(Crr·cosθ + sinθ) − 0.5·ρ·CdA·(v + v_wind)·|v + v_wind|) / m` with Crr 0.004, CdA 0.32 m², ρ 1.225, η 0.97, v ≥ 0. Games may pass their own CdA, mass offset and a visual speed multiplier.

## 4. Stamina: W′ balance (BRIEF 3.4; `WBalance`)

Skiba's differential model, stepped every 0.05 s tick on the latest raw power, shown as the W′ bar:

```
if P >= CP:  wbal -= (P - CP) * dt
else:        wbal = Wp - (Wp - wbal) * exp(-dt * (CP - P) / Wp)
clamp wbal to [0, Wp]
```

CP and W′ come from the profile (bots: CP = bot FTP, W′ 20 kJ). It is a display and game resource only; it never changes trainer targets.

## 5. Input

### 5.1 Actions and bindings (BRIEF 3.5; `project.godot`, `InputBindings`)

| Action | Keyboard | Xbox controller |
| --- | --- | --- |
| up / down / left / right | arrows or W/S/A/D | left stick or D-pad |
| confirm | Enter, keypad Enter, Space | A |
| back | Esc | B |
| ability_1 / ability_2 | 1 / 2 | X / Y |
| item | F | RB |
| swap | R | LB |
| shift_down / shift_up | Q / E | LT / RT |
| pause | P | Start (Menu) |
| panic | Backspace held 1.0 s | View + Menu together (View alone never panics) |

Everything is rebindable (Settings → Controls) and saved to `input.cfg`. Actions are edge-detected (one per press). While a text field has focus, keyboard presses belong to it (no actions, no Backspace panic); controller input still passes, so View + Menu always panics. Games decide what `swap`, the abilities and `item` do.

### 5.2 Pedal gestures (`GestureRecognizer`)

Samples arrive at about 1 Hz. "For N s" is timed from the first sample of the stretch and fires on the first sample at least N s later.

| Gesture | Condition | Notes |
| --- | --- | --- |
| `not_pedaling` (state) | power < 15 W and cadence < 20 rpm (no cadence counts as low) | Drives `coast`, `stop_5s` and the governor's coasting rule |
| `pedal_start` | cadence ≥ 40 rpm or power ≥ 30 % FTP for 3 s | Once per start; re-armed by a `not_pedaling` sample |
| `surge` (= confirm) outside ERG | power ≥ max(1.3 × baseline, baseline + 40 W) | Two consecutive qualifying samples ≥ 0.5 s apart (≈ 1.5 s at 1 Hz) |
| `surge` inside ERG | flywheel speed ≥ 1.12 × baseline | Same two-sample rule |
| `coast` (= back) | `not_pedaling` for 3 s | Never in ERG |
| `stop_5s` (= pause) | `not_pedaling` for 5 s | Solo and outside ERG only |

Surge details: the baseline is the mean of the samples in the 10 s before the streak, frozen when the streak starts, counting only samples since the last stop, and it needs 5 s of that history; `pedal_start` must have fired since the last stop. So starting to pedal is never a surge, and one surge fires per streak. A stop that reaches 3 s (5 s) where `coast` (`stop_5s`) isn't allowed uses that gesture up for the rest of the stop.

`SprintRule` (where a game scores a sprint): power ≥ 1.2 × FTP, instantaneous or averaged over a trailing window.

### 5.3 Pedal-scan menus (`PedalScanList`)

- Menus scan when `InputRouter.pedal_ui_active()`: Autopilot or pedal UI is on (pedal UI defaults to on), or no keyboard or controller has been used yet.
- Focus steps through the enabled items every `scan_interval_s` (1.6 s). `surge` picks, `coast` backs out (never in ERG). Up/down/left/right move focus and pause scanning for 10 s.
- ERG auto-confirm (for game shops and pickers shown during ERG): the highlighted item is picked 2 × enabled items × scan interval after the last input or pick, then again two cycles later if the list stays open. Put the recommended item first. App-shell menus turn it off.
- App-shell exceptions for pedal-only riders: on the code keyboard the first `back`/`coast` only highlights Back; the pause overlay after a platform pause (coasting, `stop_5s`) holds Resume and does not scan; a `coast` in the lobby highlights Leave instead of leaving.

### 5.4 Zero-touch start (title screen)

- On launch the app auto-connects to the remembered trainer, rescanning in 30 s windows until it appears. The first connection is made once in Settings → Trainer (scan, then pick); after that the trainer is remembered.
- With a saved profile, holding the `pedal_start` condition (≥ 40 rpm or ≥ 30 % FTP) for 5 s starts the last-played game solo with its `zero_input_content` (the first-run game if nothing was played). While that countdown runs the menu holds its first item, the same quick ride, so a surge starts it too. A key or button press disarms it; a coast after pedaling disarms it and the menu scans. Later visits to the title (after a ride) need a stop before the 5 s hold counts, so a rider still spinning after the results doesn't start a new ride.
- First run with no profile: 20 s of continuous pedaling creates the profile "Rider" (FTP 200, unverified) and starts `GameRegistry.first_run_game()` solo (highest `first_run_priority`; ties go to `workout`, then the lowest id). A coast only restarts the 20 s.
- Joining needs a code: the join page has an on-screen keyboard that pedal-scan and controllers can drive.

### 5.5 Autopilot (BRIEF 3.5)

Per rider: the profile default, overridable per session with the lobby's "My Autopilot" item (sent in `player_info`). Each game says what it automates through `autopilot_intents(peer)`, which the host merges into the frame for Autopilot riders and bots. Autopilot never changes effort targets and never skips the warm-up. In Workout there is nothing to automate.

## 6. The Game SDK in one page

The full contract, with examples, is `docs/GAME_SDK.md`. In short:

- **A game is a module** under `src/games/<id>/`, `content/<id>/`, `assets/<id>/` and `tests/games/<id>/`, described by `game.json` (players, bots, 2D or 3D, contents, `default_content`, `e2e_content`, `zero_input_content`, options). `GameRegistry` validates it at startup; an invalid game is hidden with a logged reason.
- **`GameModule`** (extend by class name): `configure(ctx)`, `build_effort_plans()`, `sim_step(dt, frame)` at a fixed 0.05 s on the host or in solo play, `autopilot_intents`, `local_intents`, `on_rescue`/`on_afk` (a stagger, never a wipe), `snapshot`/`apply_snapshot`/`apply_event`/`client_predict`, `make_view`, `hud_spec`, `results`, `apply_progress`, and the signals `lap_marker` and `finished`.
- **Effort plans**: each rider's whole session as ERG or SIM phases (WARMUP, WORK, RECOVERY, FREE, COOLDOWN), validated by the `PlanValidator` against BRIEF 4.6 and the warm-up limits. The platform appends the 180 s cool-down at 50 % FTP and keeps calling `sim_step` during it.
- **Directives** (`ctx.directives`) are the only way to change load inside a phase: `request` (ERG target within `range_pct`, a 10–30 s SIM block, mode grade, haptic, crr/cw factors), `course_grade`, `end_phase`, `cadence_band`, `replan`. The rider's own governor clamps or refuses each one and reports what it applied.
- **HUD and input**: `hud_spec()` places kit widgets; `ctx.hud` feeds bands, teammate statuses, toasts and banners; `ctx.intents` carries the game's widget input.
- **Determinism**: rules are pure `step(state, inputs, dt)` classes using only `ctx.rng`. Conformance (`tests/sdk/test_conformance.gd`) runs every registered game headless.
- **Tools**: `tools/new_game`, `tools/run_game_sim`, `tools/screenshot`, `node tools/e2e/run.mjs`, `node tools/fit_check/check.mjs`, `tools/art`.

## 7. Multiplayer from a player's view (BRIEF 5)

- **Model.** Star topology through a relay (`server/relay`). The host's game is authoritative at 20 Hz; clients send telemetry at 5 Hz; the host sends snapshots at 10 Hz and the roster at 2 Hz. Each rider's governor runs on their own PC; the network never carries device commands.
- **Relay.** The relay URL is a setting (Settings → Network, default `ws://localhost:8787/v1`, or `--relay=<url>`). A group needs a relay that every PC can reach; `server/relay` ships with a Dockerfile. Limits: 8 peers a room, 4 h room lifetime.
- **Hosting.** The host gets a six-character code from the Crockford alphabet, shown as `K7Q-X2M` at ≥ 48 px. The host picks the content, the scaling mode, the game's options and bots (Add bot / Remove bot up to `max_players`; bot FTP defaults to the host's FTP, 50–600 W).
- **Joining.** Type the code (case-insensitive; dashes and spaces ignored; O reads as 0, I and L as 1), or pick a recent room on the join page. A rider without the game, or with another version, can't ready up and sees why.
- **Ready and start.** Riders ready with `pedal_start` or confirm. Solo: `pedal_start` (or Start ride) starts at once. Host: Start ride starts once every human is ready and there are at least `min_players` slots; `pedal_start` only readies, so a room never starts before friends arrive.
- **Slots.** Join order, then bots. A rider who drops before the start keeps their place if they come back.
- **Dropping and coming back.** A dropped client rejoins by itself (at once, then after 1, 2, 4, 8 and every 15 s) for as long as its reconnect token lives (120 s). A restarted app with the same profile reuses the saved token. The rider gets their slot, plan and phase back and starts a new FIT file from the rejoin; until fresh telemetry shows pedaling they count as AFK. After the start, a join without a valid token is refused with `session_in_progress`.
- **AFK.** A dropped rider is AFK at once (shown at 0 W). In multiplayer, 10 s of coasting marks a rider AFK instead of pausing; pedaling clears it. Slots stay until the session ends.
- **Host leaving.** The relay holds a dropped host's room for 120 s. If the host leaves, the session ends gracefully (no host migration); each client still saves its own ride.
- **Pause** is solo-only. In multiplayer, `pause` does nothing and coasting means AFK.

## 8. Rides, FIT and Strava (BRIEF 3.8)

- **Recording.** Every session records the local rider at 1 Hz (power, cadence, speed, and distance from the trainer's speed). Laps start at every `lap: true` phase, every `lap_marker` and the cool-down; the lap name (the phase label) travels in a FIT developer field. A pause stops the FIT timer; records continue. A value not refreshed for 3 s counts as 0 W or absent, so a dropout never invents work.
- **Saving.** At the results screen: `<user dir>/rides/<UTC start yyyymmddThhmmssZ>_<game>.fit` plus a JSON summary with the same stem (never overwritten: `_2`, `_3`). Each rider keeps only their own ride; nothing goes to the host or the relay.
- **FIT.** Protocol 2.0, profile 21.40; file_id (activity, manufacturer development 255), device_info, event (timer start/stop), record, lap, session (cycling, virtual_activity 58), activity. No GPS.
- **Strava connect** (Settings → Strava): the rider enters the client ID and secret of their own Strava API app (callback domain `localhost`). Connect opens the browser to Strava's authorize page with `scope=activity:write` and catches the answer on `http://127.0.0.1:<port>/strava/callback` for up to 5 minutes. Tokens and the secret stay in `strava.json`; tokens are refreshed 10 minutes before expiry and the newest refresh token is always kept. Disconnect revokes and deletes them.
- **Upload.** The results screen offers Upload to Strava (pedal-scan selectable); with auto-upload on (off by default) it uploads once without a prompt. The upload is a Virtual Ride (`trainer=1`, the ride's UUID as `external_id`), polled every 3 s for up to 2 minutes. Duplicates count as uploaded. Offline, 401, 429 and 5xx failures wait in `rides/upload_queue.json` (up to 8 attempts) and retry at the next launch or connect.
- **Rides history** (Settings → Rides, P1): every saved ride with its upload state; picking one uploads or re-uploads it.

## 9. Workout, the reference game (BRIEF 3.7)

A group interval ride for 1–8 riders, bots optional. Everyone rides the same timeline at their own %FTP. Workout sends no directives: its plans do all the trainer work.

### 9.1 Sessions (`content/workout/sessions/`)

Every session opens with a 300 s ERG ramp 50 → 65 % FTP (except `e2e`); every phase is a lap; totals include the platform's 3-minute cool-down.

| Content | Main set | Total |
| --- | --- | --- |
| `easy_30` (default, first run, zero input) | 20 min ERG 65 % as 360 / 330 / 330 / 90 s blocks, with 30 s FREE sprints (SIM flat, virtual gears) at minutes 6, 12 and 18 | 28 min |
| `sweet_spot` | 2 × 12 min at 90 %, 4 min at 55 % between | 36 min |
| `threshold` | 3 × 8 min at 98 %, 4 min at 55 % between | 40 min |
| `vo2` | 5 × 3 min at 110 %, 3 min at 50 % between | 35 min |
| `rolling_road` | 30 min SIM on a seeded rolling course, −2 % to +6 % (`grade_source: course`), power band 76–105 % FTP | 38 min |
| `e2e` | 60 s ramp 50 → 60 %, 30 s at 65 %, 30 s FREE sprint, all inside the warm-up limits | 2 min + cool-down |
| `zwo_sample` | `content/workout/zwo/sample.zwo` through `WorkoutImport` | about 35 min |

`--content=zwo:<path>` imports any `.zwo` file. The importer reads SteadyState, Warmup, Ramp, Cooldown, IntervalsT and FreeRide (as SIM), adds a warm-up prefix if needed, splits and clamps blocks to BRIEF 4.6 and the warm-up limits, and lists every clamp in the session preview.

The rolling course is three seeded sine waves sampled every 250 m over 50 km and normalized to exactly −2…+6 %. The trainer gets the course grade × difficulty (50 % by default), plus the gear offset (section 11.6).

### 9.2 In band, grade and XP

| Phase | In band when |
| --- | --- |
| ERG | power within ±5 % of the applied target (before the governor reports one: the planned target, × 0.85 if FTP is unverified) |
| Rolling road (SIM WORK) | power within 76–105 % FTP |
| FREE sprint | cadence ≥ 60 rpm |

- Rescue, AFK and a dropped connection count as out of band and nothing else. The warm-up counts; the cool-down doesn't.
- A sprint is a hit when power stays ≥ 1.2 × FTP for 3 s in a row. Rows show the peak, the best streak and the time above.
- The group grade comes from the average session time in band over every slot, bots included: S ≥ 95 %, A ≥ 90 %, B ≥ 80 %, C ≥ 65 %, otherwise D. Each row also has its own grade.
- Results rows: time in band per interval, kJ, average and normalized power, average %FTP, best 1-, 5- and 20-minute power, sprint peaks.
- XP = kJ + session time in band (%) + 10 per sprint hit. `ctx.progress` keeps totals and a level per 1000 XP. Pennant unlocks: first ride, 5 rides, a grade S, 10 sprints hit, 5000 kJ. The newest unlock is the pennant the view draws for you.

### 9.3 The ride view and HUD

- **View** (2D, 640 × 360 PixelViewport): sky, clouds and three parallax strips scroll with your distance. One pennant per rider (slot color, shape and pattern; hollow for slots 4–7) sits on the road at its distance from you (2 m per art pixel; you at x = 200). In Rolling road the road follows the course (elevation × 2.5). The interval blocks are drawn on the ground (0.5 px per plan second, about 21 minutes across) with a "now" mark. No people are drawn.
- **Movement.** Each rider moves by `SpeedModel` on their P_eff: flat in ERG and sprints, and in Rolling road on the trainer's applied SIM grade, so the hill on screen matches the hill under you.
- **HUD.**
  - Top centre: the phase timeline. Top right: watts and in-band % readouts.
  - Bottom left: power gauge, cadence, W′ bar. Bottom centre: the teammate strip. Bottom right: the gear indicator (whenever the trainer is in SIM).
  - Toasts top left, banners top centre.
  - Banners announce each interval (4 s); a sprint gets a 10 s warning. The gauge shows 76–105 % FTP in Rolling road, and 120–160 % FTP in sprints after the first 300 s (none in a warm-up sprint).

## 10. Presentation (BRIEF 3.9)

### 10.1 Slot looks (`Wl.slot_look`)

Each session slot gets a color from the Okabe-Ito colorblind-safe set, always paired with a shape and a pattern. The profile color shows only in menus.

| Slot | Color | Shape | Pattern | Hollow |
| --- | --- | --- | --- | --- |
| 0 / 4 | red (vermillion `#D55E00`) | circle | solid | no / yes |
| 1 / 5 | blue `#0072B2` | triangle | dashed | no / yes |
| 2 / 6 | yellow `#F0E442` | square | dotted | no / yes |
| 3 / 7 | green (bluish green `#009E73`) | diamond | double | no / yes |

### 10.2 HUD kit (`addons/wattlands/ui/hud`)

| Widget (`HudSpec`) | Shows |
| --- | --- |
| `power_gauge` | Raw W (key number), %FTP, W/kg if opted in; a bar with the target band that glows in band. ERG: applied target ± 5 %. SIM: the band from `ctx.hud.power_band` |
| `cadence` | rpm (key number) with the band from `ctx.directives.cadence_band` |
| `wbal` | W′ balance bar |
| `timeline` | Phase timeline with a preview of the next phase |
| `teammates` | Per rider: slot chip, raw W, %FTP, in-band, rescue, AFK, connection, the latest `teammate_status` |
| `readout` | A big number: `power_w`, `cadence_rpm`, `ftp_pct`, `wkg` or a custom value from the game |
| `gear` | Virtual gear 1–24, whenever the trainer is in SIM |

Banner and toast areas sit at any anchor. Placement is by named anchor (32 px from the edges; top anchors stack down, bottom anchors stack up) or, in 2D games, by a Rect2i in art pixels mapped through the PixelViewport. If a game's spec hides raw power, the HUD adds a power gauge bottom left anyway.

### 10.3 Readability

- Base viewport 1920 × 1080, `canvas_items` stretch: sizes are 1080p pixels.
- Key numbers 64 px and never below 48 px; big readouts 72 px; banners 56 px (never below 32 px); toasts 36 px (never below 24 px); menus 40 px; body 32 px. Text has an 8 px dark outline so it reads over any art.
- Corner toasts and banners wrap within a third of the width (610 px).
- Font: Godot's default (Atkinson Hyperlegible is a drop-in when its files are added). Sound: synthesized effects plus an optional cadence metronome at the preferred cadence.
- 2D games render at `pixel_base` with nearest filtering and integer scaling, letterboxed. 3D games use the `world3d` low-poly kit (no SSAO, no depth-of-field).

## 11. Safety from a player's view (BRIEF 4.6)

Every rule lives in your own `SafetyGovernor`; `docs/TRAINER.md` has the constants and the order.

### 11.1 Warm-up

- The first 5 minutes of riding, from your first pedal stroke in the session; it resets after 20 minutes without pedaling.
- While it lasts: ERG targets ≤ 65 % FTP, SIM grade −2…+3 %, no haptics. A purple warm-up banner shows it.
- Every plan must open with warm-up content (the PlanValidator enforces it). The profile's skip-warm-up option removes only the governor's caps.

### 11.2 Rescue

- **Armed** in ERG when the target is ≥ 60 % FTP.
- **Triggers** when cadence < 45 rpm for 3 s or power < 75 % of the target for 5 s.
- **Effect**: the target drops to 50 % FTP (never higher than it was) and an orange "rescue" banner shows. It holds until cadence ≥ 70 rpm for 3 s, then ramps back over 10 s.
- **Game side**: games treat it as a stagger, never a wipe. A SIM phase ends rescue.

### 11.3 Coasting

- After 3 s of `not_pedaling`, ERG drops to the floor.
- After 10 s: solo sessions pause (grey banner) and multiplayer riders are marked AFK. Pedaling again (or confirm) resumes a solo pause.

### 11.4 Pause

Solo only, from `pause` or `stop_5s`. The game clock stops; the trainer goes to the ERG floor or SIM flat. Telemetry, rescue, coasting and panic keep working.

### 11.5 Panic

- **Triggers**: Backspace held 1 s, View + Menu, or the always-visible on-screen panic button.
- **Effect**: ERG off, SIM grade 0 and wind 0, written at once.
- **After**: the trainer stays safe until you pick Resume trainer, which re-enters from the floor and slews up. Panic doesn't pause the game.

### 11.6 Caps you can feel

| Rule | Limit |
| --- | --- |
| Floor | ERG never below max(30 % FTP, 50 W); it wins over every cap and over rescue |
| Ceiling | ERG never above min(150 % FTP, 1000 W, trainer max) |
| Long phases | A phase longer than 300 s caps at 105 % FTP |
| Duration limits | At most 300 s above 105 % and 60 s above 120 %; 120 s of ERG at ≤ 90 % resets both |
| Unverified FTP | Every ERG target × 0.85 |
| Slew | ERG increases ≤ 30 W/s; decreases at once |
| Mode switches | ERG ↔ SIM ramped through a low ERG target and SIM grade 0; at least 30 s apart (a 10–30 s directive SIM block is the exception) |
| SIM grade | (course + mode grade) × difficulty + gear, within your range (−5…+10 %); haptics ≤ +3 % for ≤ 8 s with a 15 s cooldown; total −10…+16 % |
| Virtual gears | 24 gears; gear 12 is neutral, each step about 7 % resistance at 30 km/h (gear 1 ≈ −2.5 %, gear 24 ≈ +6 % on the flat); only while in SIM; back to 12 each session |
| Quit, crash, switching trainers | SIM flat, then Stop |

## 12. Hardware status

Everything above was built and tested against MockTrainer, the mock relay paths and the mock Strava server, with the hardware and network locks on. Before relying on any of it, work through `docs/HARDWARE_TEST_PLAN.md` and `src/games/workout/HARDWARE_TEST.md`.

## 13. Known differences

Where the code differs from the BRIEF or from what the docs promise:

1. **Double ticking in the real app (BRIEF 4.1, 4.6).**
   - Nothing calls `TrainerService.set_external_tick(true)`. `AppServices.set_menu_ticking()` targets a `TrainerService.set_menu_ticking()` that doesn't exist, so the call does nothing.
   - So in a windowed session and in the FTP test, the TrainerService keeps ticking the local rider while the GameHost (or the FTP test screen) ticks it too. The rider's platform time (governor timers, slew, write slots, warm-up, recorder seconds, MockTrainer notifications) runs at about twice wall time.
   - Headless `GameSimRunner` runs don't use the TrainerService and aren't affected. See `docs/TRAINER.md` section 9.
2. **The trainer isn't reset after a session.** After the results, or End ride, the session's governor stays the menu rider's governor. It keeps commanding the last plan phase in menus under the normal rules: normally the cool-down's 50 % FTP in ERG, after End ride the interrupted phase's target. The ADR says menus ride free at SIM flat.
3. **Warm-up restarts every session.** The governor counts the warm-up from the first pedal stroke after each session's rider set-up, not after the trainer connects (BRIEF 4.6.8), so back-to-back sessions each get a fresh warm-up.
4. **FTP test.**
   - The app uses `AppFtpTest`; the platform's `FtpTest` (`addons/wattlands/core/ftp_test.gd`) is unused.
   - The end rules run from the ramp-in on, so a test stopped during the ramp-in still produces a result (0.75 × the best ramp-in minute) that saves itself after the countdown unless Keep or `back`.
   - The countdown runs on the result page after the cool-down.
   - The cadence rule doesn't check freshness, so a trainer that reports no cadence (and no estimate yet) ends the test after 5 s.
5. **Rescue never raises a lower target.** It applies min(target, 50 % FTP); BRIEF 4.6.12 says "50 % FTP instead".
6. **Haptics are also bounded below.** −3 % as well as +3 % (BRIEF 4.6.6 bounds only the increase).
7. **Workout's ride view doesn't use the world2d kit.** It has its own parallax layer and procedural art (BRIEF 3.7 says "built from the world2d kit").
8. **P1 gaps.**
   - Hosts never reclaim their previous code: the lobby calls a two-argument `host_room()` that `WlNetSession` lacks, and doesn't call `host_room_reclaim()`.
   - The join page's LAN list is always empty: `LanTransport`/`LanDiscovery` exist, but `WlNetSession` has no `lan_rooms()`/`join_lan()`.
   - The Strava FTP and weight import (`Rides.strava_import_athlete`) has no Settings item.
   - The app doesn't launch the trainer bridge itself.
9. **Fallbacks taken.** No Atkinson Hyperlegible font and no CC0 audio pack were downloaded; BRIEF 3.9's fallbacks (Godot's font, synthesized sound) are in use.
10. **Profile fields that do nothing yet.** `drivetrain` is stored but unused. MockTrainer's keyboard control (W/S ±10 W, A/D ∓/±5 rpm) exists but nothing in the app turns it on.
