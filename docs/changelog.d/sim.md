# Changelog: sim

## Unreleased (W4 final, 2026-10-21)

### Changed

- `Bots.RIDER_SPEC` is `erg:compliance=1.0+band`: bots follow the cadence band a game publishes for them (BRIEF 3.6 `cadence_band`), reaching its centre after a 2 s lag with seeded noise within ±1.5 rpm, and ride 90 rpm (88.5-91.5 rpm with the noise) without one. In ERG, a band step up of more than about 12% (in practice about 18% and up, because of the lag) makes a bot fire the `surge` gesture, as a human following the band would. Runs with bots get new `deterministic_hash` values.

## Unreleased (W1, 2026-10-21)

### Added

- `GestureRecognizer`: pedal_start, surge (power outside ERG, flywheel speed in ERG), coast, stop_5s and the shared not_pedaling detector, with arbitration and re-arming (BRIEF 3.5). New: `advance(t)`, `not_pedaling_s_at(t)`, `not_pedaling_since()`, `is_pedaling()`, `surge_baseline()`, signal `not_pedaling_changed(active)`.
- `SprintRule`: >= 1.2 x FTP, instantaneous or over a trailing window, with `held_s()` and `best_s()`. New: `current_w()`.
- `ZwoImport.parse_zwo` / `parse_zwo_file` (the class was `WorkoutImport` until W4; platform classes carry no game prefix): SteadyState, Warmup, Ramp, Cooldown, IntervalsT and FreeRide (SIM flat); unsupported tags skipped with warnings; the 5-minute warm-up prefix; clamps for the warm-up limits, the 150% and long-phase caps, the 105%/120% duration limits and the 30 s switch spacing, each listed with its reason. New: `clamp_records`, `prefix_inserted`, `total_s`, `ZwoImport.to_plan(result)`.
- `ZwoImport` guards: durations are rounded to whole seconds, a leading byte-order mark is ignored, IntervalsT `Repeat` is limited to 200 (with a warning), workouts longer than 24 h are rejected, and a missing file returns the full result shape.
- `content/strings/sim.csv`: labels, clamp lines, warnings and errors of the .zwo importer.
- `tests/fixtures/zwo/`: sample .zwo files for every tag, every clamp kind and broken files.
- Tests: gestures, sprint rule, the .zwo importer, a speed-model oracle sweep with game-feel parameters and effort scaling, and a hand-computed W' balance sequence; seeded property sweeps over random .zwo files and random gesture streams; a PlanValidator check of imported plans that runs once the real validator is merged.
- CI: `.github/workflows/sim.yml`.

### Changed

- `ZwoImport`: a block split at the 300 s warm-up boundary keeps its full length for the 105% long-phase cap.
