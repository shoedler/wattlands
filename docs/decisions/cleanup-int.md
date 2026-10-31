# Decisions: cleanup integration

## 2026-10-31: the wrappers the batches kept for their tests go

- **Decision:** after the senior review of `cleanup/int`, remove `TankRenderClock`, `WorkoutRideView`'s four clock aliases, `SiegeSnapHistory.DELAY_MIN_S`, `FishingHudControl.ap`, `FishingRig.bresenham`, `HudHelp.line_pixels` and `TankMech`'s nine forwarders to `TankMechRepair`. Callers and tests name `SnapRenderClock`, `u()`, `PixelPainter` and `TankMechRepair` directly. `SnapRenderClock` gains an optional constructor argument for its smallest delay, so Tank's view still starts at one tick. This overrides SPEC_CLEANUP 5.4 and 5.6, which kept them so that tests would not change. `test_the_help_overlay_draws_the_same_line` compared the forwarder with its target; it becomes `test_a_line_and_its_reverse_span_the_same_length`, so the count holds.
- **Kept:** `TankRecord`, `SiegeRecord` and `FishingRecord`, which name the G0 contract base. `interp_delay()` on `WorkoutRideView`, which reads a clock and is not a forwarder of a constant.
- **Alternatives:** keep the wrappers (a second name for each thing, which the next reader has to look through).
- **Reason:** the cleanup's purpose is one name per thing. No number moves: `behaviour_hash`, the GUT view suites and the unchanged constants are the proof.

## 2026-10-31: IntentValue holds the intent readers, before GAME_SDK documents the API

- **Decision:** `truthy` moves from `IntentRateLimiter` to a new `IntentValue`, joined by `whole`, which Tank and Siege each held as `_whole`. `IntentRateLimiter` does only rate limiting.
- **Alternatives:** leave `truthy` where C5 put it (a game's `normalize()` would call a rate limiter to read a flag); merge `whole` with `WlGameRegistry.is_whole` (it also caps the magnitude, so it could refuse an intent that passes today).
- **Reason:** renaming after C9 documents it would break the additive rule.

## 2026-10-31: tests/lib holds what the games' test suites share

- **Decision:** `TestGameFakes` (the recording `Hud`, `Intents`, `Stats`, `option_defaults`, `with_cooldown`, `plans_of`), `TestGameSuite` (file walk, `csv_keys`, the option-entry check, the required manifest fields), `TestGameStaticSuite` (the trainer name list, the clock and RNG patterns, the lexer and determinism proofs) and `TestGameSessionSuite` (temp dirs, runner cleanup, `run_session`). Tank, Siege, Fishing and the template extend them, so a new game starts without these copies. Tank's extra `Hud` fields (`t`, `power_band_at`) are now on the shared one: the others ignore them. Every test function stays in its game's file, and each game's scans still run on its own folders, so the trainer scan stays per game and no count falls.
- **Left per game:** `frame` and `phase_at` (Fishing's and the template's match, Tank's and Siege's differ), each `Directives`, each game's `WORLD` pattern and its self-test (it names that game's classes), the real scans, Siege's `_csv_keys` (another return type), Fishing's `_run` (it watches `fx_event` during the run). `e2e_check.mjs` stays too: only one-liners match once the game's events are set aside, and `tools/e2e/lib/checks.mjs` is pinned.
- **Reason:** 500 lines of copies, and a fix to one scanner could miss the other. These scans are the no-trainer-bypass check for games, so the list lives in one place and each suite still proves it on bad snippets.

## 2026-10-31: three view-only changes in this release, all sub-visible

- **Decision:** the changelog names all three: `SAME_T_S` in `SnapHistory` (C4), the Tank card crank standing still at or below 1 rpm (C6), `FishingHudModel.clock` through `HudWidget.clock_text` (C6). The batch ADRs hold the reasons. None is read by rules, directives, effort, FIT or snapshots.

## 2026-10-31: WorkoutHudTimeline's missing super() is not fixed here

- **Decision:** `WorkoutHudTimeline._init` does not call `super()`, so it skips `HudArtControl`'s setup. Adding it was tried and measured with `tools/screenshot --game=workout --content=e2e --seed=1`: a repeat of the same frame differs by 0 px at 30 s, and the fix changes about 1,190 px there, all in the plate. Its text goes from blurred to sharp and the rest stays, so it is right, but it moves pixels, which this pass may not do. It goes to the lead as a request.
- **Alternatives:** land it here (this pass's rule is no pixel moves).
