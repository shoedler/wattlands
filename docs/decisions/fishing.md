# Decisions: fishing

Short ADRs for Big Game Fishing: date, decision, alternatives, reason. Game sessions keep their decisions here only; docs/DECISIONS.md holds the platform's. "Brief" is docs/games/fishing.md; "SDK n" is a section of docs/GAME_SDK.md. Where the brief and the code or the SDK disagree, the code and the SDK win (orchestrator's instruction).

## 2026-10-23 G0 status

- G0.1: `main` (5bd5aa4, contains `v0.1.0`, Generator Siege merged) was clean; no planning-file commit was needed. Branch `game/fishing` cut from it in its own worktree (`C:/Projects/wattlands-fishing`); `tools/new_game fishing` ran (commit 36ae6c1) and gdformat re-wrapped one file. Baselines: the tracked floor `tests/green_count_floor.txt` is 3249 (the orchestrator's rule replaces a G0 suite run); the e2e baseline for every registered game is taken in G2 with the full suite.
- G0.2 answered by citation below; no `platform:` commit is planned (every gap the brief anticipated already exists: SDK 23).
- Art variables (presence only, never values): `FAL_KEY` set before and after sourcing `tools/env.sh`; `WATTLANDS_ALLOW_ART` not set in this environment, before or after. Sourcing clears neither (SDK 23 Q23). If it is still unset when fish-art runs, brief 3.4's fallback applies and the report says "placeholder art".
- G0.3-G0.5: `game.json`, the contracts, the content seeds, `art.json`, the placeholder `picker_card.png` and a G0 module that plays end to end; tag `fishing-g0`.

## 2026-10-23 G0.2 answers (by citation, no platform change)

- HudSpec to art pixels: a `Rect2i` is in art pixels of `pixel_base` and goes through `PixelViewport.art_rect_to_screen()` (integer scale 3 at 1080p plus the letterbox offset), re-laid out on resize; anchors ignore the viewport (SDK 10.1, 23 Q16).
- Clearing a cadence band: `ctx.directives.cadence_band(peer, 0, 0)`; the cool-down clears every band (SDK 8, 23 Q13). The Landing clears the Fight's band this way.
- `phase_changed`: the GameHost never emits it; per-rider phases come from `frame.phase`. Fishing never emits it (SDK 13, 23 Q14).
- `tools/screenshot`: `--players`, `--seed`, `--at=<s,...>` (sim seconds, fast-forwarded), every `run_game_sim` flag, and `--app-screen=session --app-role=client` to see the PANIC corner (SDK 19.3, 23 Q15).
- `tools/run_game_sim`: per human slot `--rider` (repeat per slot), `--autopilot=all|none|<slots>`, `--ftp`, `--haptics-off`, `--player-options`; the report holds events, per-rider phases with `ended_by`, every directive requested and applied with `clamped_by`, the 1 Hz trace (applied target and %FTP, mode, `clamped_by`, rescue, AFK), snapshot sizes and SHA-256s, results and `deterministic_hash`; FIT files at `<report dir>/fit/<report stem>_slot<n>.fit` (SDK 19.1, 23 Q2-Q3).
- `tools/fit_check`: `node tools/fit_check/check.mjs <file|dir>... --expect-laps=<n>`. The platform always adds the cool-down lap: n = lap-true phases that started + 1 (SDK 13, 19.5, 23 Q4-Q5). Fishing laps: the ride out, every Reel and every Fight that started (Landings are lap-false), so free and base trips give a different n per rider; e2e_2min gives ride out + Reel + Fight + cool-down = 4.
- Mock riders: `band` (`offset_rpm` from the published band's centre; with a 16 rpm band, -18 and +18 hold 10 rpm outside), `cadence_drop` (`rpm`, `at_s` or `at_phase` [+ `after_s`] or `at_target_pct`, `for_s`) (SDK 20, 23 Q1).
- Also: `PlayerSlot.preferred_cadence_rpm` and `haptics_on` (SDK 6), `PhaseState.plan_elapsed_s` (SDK 9), `int_fields()` (SDK 12), signed `SpinningPart` speed and `ParallaxStrip.mirror_alternate` (SDK 18), `tile`/`mirror` in art.json (ART_PIPELINE).

## 2026-10-23 Five G1 builders (orchestrator's change to brief section 5)

- Decision: five builders on disjoint paths, each in its own worktree and branch from `fishing-g0` (`S/` = `src/games/fishing/`, `C/` = `content/fishing/`, `T/` = `tests/games/fishing/`):
  - fish-plan (Opus): `S/plan/`, `C/trips/`, `C/species.json`, `T/plan/`.
  - fish-rules: `S/rules/`, `S/autopilot/`, `C/areas/`, `T/rules/`; the only builder that may add fields to the state records in `S/contracts/` (additively, reported).
  - fish-module: `S/fishing_game.gd`, `S/net/`, `S/results/`, `C/cosmetics.json`, `T/module/`, `T/integration/`, `T/fishing_fakes.gd`, `T/test_fishing_package.gd`.
  - fish-view: `S/view/`, `S/hud/`, `S/audio/`, `C/strings.csv`, `T/view/`, `T/hud/`.
  - fish-art-qa: `assets/fishing/`, `S/tools/`, `docs/credits.d/fishing.md`, `T/art/`, `T/sim/`, `T/e2e_check.mjs` and its `*.test.mjs`, `.github/workflows/game-fishing.yml`, `S/README.md`, `S/HARDWARE_TEST.md`, `S/BACKLOG.md`.
  - The lead keeps `S/contracts/`, `S/game.json`, `docs/decisions/fishing.md`, `docs/changelog.d/fishing.md`.
- Reason: the orchestrator's instruction (fewer agents, quicker v0.1); every file keeps one writer.

## 2026-10-23 Contracts

- State is typed `RefCounted` records (`FishingRecord`, after Siege's `SiegeRecord`): `FishingState` > `FishingLaneState` (one per slot, slot order) > `FishingFishState`, `FishingPullState`, `FishingPlanSlot`. Lanes are arrays, so `sim_step` allocates nothing per tick (free_120 must finish its SOLO sim within 900 s).
- The rules are pure: `FishingRules.step(state, inputs: Array[FishingLaneInput], dt) -> FishingStepOut`. The module fills one reused `FishingLaneInput` per slot from the frame, and applies the out in a fixed order: directives, bands, end_phase, events, toasts, finished. The pull scheduler (`FishingPullScheduler`, fish-plan) is called by the rules with a frozen API (begin, start_run, set_staggered, step, end).
- Randomness: `FishingRandom`, a 32-bit xorshift stream derived from `ctx.seed` and two integers. The pre-roll uses (seed, slot, PREROLL) as brief 2.3 says ("from ctx.seed and the slot index"); each lane's rules and pull schedule use their own streams, so one rider's bites never shift another rider's pulls and the plan property tests can run lanes alone. Scheduled trips use (seed, 0, PREROLL): one schedule for everyone.
- Alternatives: `ctx.rng` shared in slot order (couples the lanes); `RandomNumberGenerator.new()` per lane (banned in rules by the package scan).
- Reason: determinism without the wall clock or global RNG, lanes independent, the same streams on host and clients.

## 2026-10-23 Autopilot and zero input run inside the host rules

- Decision: `autopilot_intents()` returns `[]`. `FishingRules` plays picks, casts and strikes for every lane whose `auto_plays()` is true: bots (none: `bots` is false), Autopilot-on riders, and humans who have sent no deliberate Fishing intent yet (`fallback`). Only `spot` and `confirm` with `via` `action` or `button` are deliberate (`FishingIntents.is_deliberate`); a surge confirm, the summary and auto-confirms never end the fallback. The pedal-scan highlight and its two-cycle auto-confirm (2 x hints x 1.6 s) also run in the host rules, so a sim or a host never depends on the client-side, wall-clock `PedalScanList`; the view draws the highlight from the snapshot's `selected`.
- Reason: the platform never calls `autopilot_intents()` for Autopilot-off humans (SDK 11), so the fallback must live in the rules anyway (Siege's ADR); the scan's auto-confirm runs on wall-clock time on clients (orchestrator's note).

## 2026-10-23 HUD layout (HUD space is the main constraint)

- Decision (`FishingLayout`, art pixels):
  - Deck bar (y 0-23): one game Control with the trip clock, the local rider's phase chip (label, time left, next phase), the local fish row (species icon, distance, stamina) or the gaff meter in Landing, the catch board and the hookup level; the kit `wbal` (362, 4, 80, 16) and `gear` (306, 0, 54, 24) widgets in their own rects.
  - Local lane's HUD zone (x 427-639): the kit timeline (213 x 36) on top, then one 36 px row: power gauge (100), the game's strain bar (5), cadence (97), the game's slack bar (5); each kit widget at its minimum rect, so W and rpm keep >= 48 px at 1080p. This fits the 4-lane zone (213 x 84).
  - PANIC owns art x >= 503, y >= 316. When the row would reach it (the bottom lane at 3 and 4 lanes) the timeline is left out (the deck bar's phase chip stands in) and the row moves to the zone's top.
  - Other lanes: one compact FishingLaneHud (213 x <= 36: band and marker, both meters, W and rpm at >= 32 px, species and distance) at the top of each zone, clear of PANIC.
  - Toasts below the deck bar (160, 26, 320, 22); banners over the local lane's left two-thirds.
- Alternatives: kit widgets for everything (they don't fit 84 px); the meters inside the play area (clutters the slice, and the right third must stay HUD and open water); a second timeline in the deck bar (the kit timeline needs 108 screen px, the deck bar has 72).
- Reason: brief 3.5's widget list in the smallest zone, the right-third rule and the PANIC corner. The W′ bar sits in the deck bar at every lane count, so the layout is the same at 1-4 lanes.

## 2026-10-23 Plan shape details

- Open-ended Reels get `duration_s` 240 (nominal, for the timeline) and `max_s` = the trip's nominal length (`FishingPlanBuilder.trip_length_s`), so a Reel never ends on its own before `finished`. Free and Base plans end with a trailing fight-less Reel, so a rider whose slots ran out keeps reeling until `finished("trip_over")`; `finished` waits until no lane is in a Fight or Landing. Scheduled trips end at the last Landing (the platform's cool-down follows).
- Labels: per-number string keys (`FISHING_PHASE_REEL_<n>` up to 40, `FISHING_PHASE_<SPECIES>_<n>` up to 30/20/12/4); beyond them the plain text ("Reel 41") passes through `ctx.strings.t`. The FIT lap name is the label.
- "slot 2 is a marlin" (free_90, free_120): the second fight slot, 1-based (`marlin_slot: 2`).
- e2e_2min's Reel is fixed at 55 % (`reel_pct` in the trip file); the rider's reel_pct option is ignored there.

## 2026-10-23 e2e mackerel band offset +3 (deviation)

- Decision: e2e_2min's scheduled mackerel uses `band_offset` 3, not the brief's 0.
- Alternatives: 0 as written.
- Reason: the e2e harness, the run_tests sim step and conformance ride `erg:compliance=1.0` at a constant ~90 rpm and never follow the band (orchestrator's note). With offset 0 the band's high edge falls to 90 at S = 0.2 and the rider stalls out of band; with +3 the band runs from [85, 101] at S = 1 to [75, 91] at S = 0, so a constant 90 rpm rider stays in band the whole fight and lands the fish in T_nom.

## 2026-10-23 Synthesized audio

- Decision: every Fishing sound is synthesized with `Sfx.synth` (and built-in effects); no CC0 downloads.
- Reason: the orchestrator's instruction.
