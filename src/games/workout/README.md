# Workout

The reference game (BRIEF 3.7): a group interval ride for 1–8 riders, bots optional. Everyone rides the same timeline at their own % FTP. It proves the platform's paths: ERG phases, SIM phases with virtual gears, ramped mode switches, warm-up, cool-down, rescue, laps, FIT, Strava, multiplayer and zero input.

## Sessions

`content/workout/sessions/<content id>.json`, validated at load (`WorkoutSession`). Every phase has `lap: true` and a label; the platform appends the 3-minute cool-down.

| Content | Main set | Total |
| --- | --- | --- |
| `easy_30` (default, first run, zero input) | 20 min at 65% FTP with 30 s FREE sprints (SIM flat, gears) at minutes 6, 12 and 18 | 28 min |
| `sweet_spot` | 2 × 12 min at 90%, 4 min at 55% between | 36 min |
| `threshold` | 3 × 8 min at 98%, 4 min at 55% between | 40 min |
| `vo2` | 5 × 3 min at 110%, 3 min at 50% between | 35 min |
| `rolling_road` | 30 min of SIM on a seeded rolling course (−2% to +6%), band 76–105% FTP | 38 min |
| `e2e` | 60 s ramp 50 → 60%, 30 s at 65%, 30 s FREE sprint, all inside the warm-up limits | 2 min + cool-down |
| `zwo_sample` | `content/workout/zwo/sample.zwo` through `WorkoutImport`, clamps in the preview | about 35 min |

`--content=zwo:<path>` imports any `.zwo` file the same way.

## Code

- `workout_game.gd`: `WorkoutGame extends GameModule`, the SDK entry point.
- `rules/`: pure, deterministic logic. `WorkoutRules.step(state, frame, dt)` scores time in band (ERG ±5% of the applied target, Rolling road 76–105% FTP, sprints cadence ≥ 60 rpm), sprints (`WorkoutSprintTracker`, 1.2 × FTP) and moves each rider with `SpeedModel` from P_eff. `WorkoutSession` loads and validates sessions, `WorkoutCourse` builds the course, `WorkoutSnapshot` encodes the all-int snapshot, `WorkoutResults` and `WorkoutProgress` build results, XP and pennant unlocks.
- `hud/workout_hud.gd`: the HUD layout and the host's banners, toasts, power bands and teammate statuses.
- `view/`: the 640 × 360 ride view (`WorkoutRideView`) with procedural art (`WorkoutArt`).
- `tools/make_picker_card.gd`: writes `assets/workout/picker_card.png`:
  `tools/godot.sh --headless --path . -s src/games/workout/tools/make_picker_card.gd`
- `tools/render_view.gd`: renders the ride view from a snapshot fixture to a PNG (windowed, it needs a renderer):
  `tools/godot.sh --path . -s src/games/workout/tools/render_view.gd -- --out=build/workout_view.png`

## Tests

- Unit: `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/games/workout -gexit -gjunit_xml_file=build/junit_workout.xml`
- With the platform (validator, importer, registry, protocol, full sims): `-gdir=res://tests/games/workout/integration`.
- e2e report check: `node tests/games/workout/e2e_check.mjs build/e2e/workout/report.json` (its tests: `node --test tests/games/workout/e2e_check.test.mjs`).

Real-trainer checklist: `HARDWARE_TEST.md`. Decisions: `docs/decisions/workout.md`.
