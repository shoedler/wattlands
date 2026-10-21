# Changelog: sim

## Unreleased (W1, 2026-10-21)

### Added

- `GestureRecognizer`: pedal_start, surge (power outside ERG, flywheel speed in ERG), coast, stop_5s and the shared not_pedaling detector, with arbitration and re-arming (BRIEF 3.5). New: `advance(t)`, `not_pedaling_s_at(t)`, `not_pedaling_since()`, `is_pedaling()`, `surge_baseline()`, signal `not_pedaling_changed(active)`.
- `SprintRule`: >= 1.2 x FTP, instantaneous or over a trailing window, with `held_s()` and `best_s()`. New: `current_w()`.
- `WorkoutImport.parse_zwo` / `parse_zwo_file`: SteadyState, Warmup, Ramp, Cooldown, IntervalsT and FreeRide (SIM flat); unsupported tags skipped with warnings; the 5-minute warm-up prefix; clamps for the warm-up limits, the 150% and long-phase caps, the 105%/120% duration limits and the 30 s switch spacing, each listed with its reason. New: `clamp_records`, `prefix_inserted`, `total_s`, `WorkoutImport.to_plan(result)`.
- `WorkoutImport` guards: a leading byte-order mark is ignored, IntervalsT `Repeat` is limited to 200 (with a warning), workouts longer than 24 h are rejected, and a missing file returns the full result shape.
- `content/strings/sim.csv`: labels, clamp lines, warnings and errors of the .zwo importer.
- `tests/fixtures/zwo/`: sample .zwo files for every tag, every clamp kind and broken files.
- Tests: gestures, sprint rule, the .zwo importer, a speed-model oracle sweep with game-feel parameters and effort scaling, and a hand-computed W' balance sequence; seeded property sweeps over random .zwo files and random gesture streams; a PlanValidator check of imported plans that runs once the real validator is merged.
- CI: `.github/workflows/sim.yml`.

### Changed

- `WorkoutImport`: a block split at the 300 s warm-up boundary keeps its full length for the 105% long-phase cap.
