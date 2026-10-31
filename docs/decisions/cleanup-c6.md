# Decisions: cleanup c6

## 2026-10-31: the art-pixel HUD base and its draw helpers move to the platform

- **Decision:** add `HudArtControl`, `HudArtDraw`, `PixelFont` and `PixelPainter.line_pixels`. `TankHudCtl`, `SiegeHudCtl`, `WorkoutHudCtl` and `FishingHudControl` extend the base; the four games' `font()`, `pixels` and Tank's and Workout's `frame` delegate. Siege keeps its `_process` and `_draw` (a refresh every `REFRESH_S`, and an empty model as the guard). Fishing keeps its `place_at` (sets `design_h`, renames nothing) and its `frame`, which overdraws its corners, so a merge would change pixels at alpha. Every `bar` stays.
- **Alternatives:** leave a declared copy per game; a shared `bar`, which no two games draw alike.
- **Reason:** four copies of one Control and three of one font loop. A fifth game now inherits them.

## 2026-10-31: HudArtDraw.frame draws through frame_rects, pixels stays a plain loop

- **Decision:** add the pure `frame_rects(r, m)`, which `frame` iterates, so a test can read the geometry, including that no corner is drawn twice. `pixels` has no such helper; its test only proves it runs inside a real `_draw` with the argument order right, and the screenshot pass covers what it draws.
- **Alternatives:** a pure `pixel_rects` under `pixels` too; no geometry test at all.
- **Reason:** headless rendering has no pixels to read back and `draw_rect` cannot be intercepted. `frame` is cheap enough to allocate four rects, while `pixels` runs for every icon on every frame and a rect array for each is cost with no user.

## 2026-10-31: two sub-visible differences this batch accepts

- **Decision:** `TankHudSeats` uses `CrankClock`, so a card's crank stands still at or below `CrankClock.STOP_RPM` (1 rpm), where it used to creep at under 1/60 of a turn a second while the cadence decayed to zero. `FishingHudModel.clock` uses `HudWidget.clock_text`, whose `ceili(seconds - 1e-6)` shows a remaining time less than 1 microsecond above a whole second as that second, one tick earlier at most, where it used to round it up.
- **Alternatives:** keep both integrators and clocks as they were.
- **Reason:** both are the spec's ruling (SPEC_CLEANUP 1.3, 5.6), and both match what the view's crank and every platform clock already do. Rules, snapshots and FIT do not read either: the behaviour hash of all ten scenarios matches the C0 baseline. `TankHudDraw.clock` (no hours) and `WorkoutHudDraw.clock` stay.

## 2026-10-31: dead helpers, with what the spec's list got wrong

- **Decision:** delete `TankHudDraw.tall_shadow` and `big_r`, `FishingRig.SPRAY_AT`, and also `WorkoutHudDraw.tall_c` and `text_c`, which the per-class grep found with no caller. Keep `TankHudDraw.text_c`: the spec lists it as dead, but `TankSeam` (Tank v4) calls it.
- **Alternatives:** delete only what the list names.
- **Reason:** a word scan cannot separate `D.text_c` of one game from another, so each name was grepped per class.
