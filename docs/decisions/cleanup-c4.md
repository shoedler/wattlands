# Decisions: cleanup c4

## 2026-10-31: every game's snapshot history and render clock are one platform pair

- **Decision:** `SnapHistory` and `SnapRenderClock` in `addons/wattlands/sdk/`. `TankSnapHistory`, `SiegeSnapHistory`, `FishingSnapHistory` and `WorkoutSnapHistory` extend the history. `TankRenderClock` extends the clock; Siege, Fishing and Workout hold one, and their `render_t` is a property on it. Siege sets `never_back`; the others don't, because their clock already stopped only at the newest entry.
- **Alternatives:** leave four copies; give the history its own clock so every game has the same shape.
- **Reason:** the copies held the same constants and bodies. A new game now gets interpolation by naming its row. Keeping the clock separate keeps Tank's and Fishing's readers as they were.

## 2026-10-31: SAME_T_S replaces is_equal_approx in the histories

- **Decision:** two times within 1e-6 s are the same time, in all four histories. This is the one intended change in the batch, and it reaches views only.
- **Alternatives:** keep `is_equal_approx` and the old `t < newest` in Workout, Siege and Fishing, to change nothing at all.
- **Reason:** its tolerance is 1e-5 x t, wider than a 0.05 s tick from about 5000 s on, so a new tick would replace the newest entry instead of adding one. No session reaches that today (3600 s plus overtime). `test_ticks_late_in_a_long_session_still_append` holds it. A time up to 1e-6 s before the newest now replaces it instead of starting over; ticks are 0.05 s apart, so no real push lands there.

## 2026-10-31: Siege keeps only DELAY_MIN_S, and Fishing keeps no clock constants

- **Decision:** `SiegeSnapHistory` drops `DELAY_MAX_S`, `RESYNC_S` and `CATCHUP_TAU_S`, against the spec's "keep". `FishingView` drops `INTERP_DELAY_S`, `INTERP_DELAY_MAX_S`, `CLOCK_RESYNC_S`, `CLOCK_CATCHUP_TAU_S` and `interp_delay()`. Workout keeps its four as aliases of the clock's, and `interp_delay()` as a delegate.
- **Alternatives:** keep them all as aliases.
- **Reason:** Workout's stay because `test_workout_client_view.gd` reads them and tests don't change. Nothing reads the Siege or Fishing ones (word grep over `src`, `tests`, `tools` and docs), so an alias would be new dead code in a batch that removes it.

## 2026-10-31: TankSnapHistory loses boss_x_at and its row field

- **Decision:** delete `boss_x_at` and the `"boss"` field it read. The C0 scan found them; the spec doesn't list them.
- **Alternatives:** leave them for a later pass.
- **Reason:** no reader in `src`, `tests` or `tools`. The view draws the Behemoth from `boss_range_at` since v4.
