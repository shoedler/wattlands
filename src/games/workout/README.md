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
| `zwo_sample` | `content/workout/zwo/sample.zwo` through `ZwoImport`, clamps in the preview | about 35 min |

`--content=zwo:<path>` imports any `.zwo` file the same way.

## Code

- `workout_game.gd`: `WorkoutGame extends GameModule`, the SDK entry point.
- `rules/`: pure, deterministic logic. `WorkoutRules.step(state, frame, dt)` scores time in band (ERG ±5% of the applied target, Rolling road 76–105% FTP, sprints cadence ≥ 60 rpm), sprints (`WorkoutSprintTracker`, 1.2 × FTP) and moves each rider with `SpeedModel` from P_eff. `WorkoutSession` loads and validates sessions, `WorkoutCourse` builds the course, `WorkoutSnapshot` encodes the all-int snapshot, `WorkoutResults` and `WorkoutProgress` build results, XP and pennant unlocks.
- `hud/workout_hud.gd`: the HUD layout and the host's banners, toasts, power bands and teammate statuses.
- `view/`: the 640 × 360 ride view (`WorkoutRideView`) with procedural art (`WorkoutArt`). On a client it draws the other riders between two snapshots, behind the newest by their mean spacing (100 ms at 10 Hz, about 1 s under the 8-rider load; `WorkoutSnapHistory`, filled by `apply_snapshot`), and the local rider from its own prediction, blended softly toward the host (BRIEF 5.1).
- `tools/make_picker_card.gd`: writes `assets/workout/picker_card.png`:
  `tools/godot.sh --headless --path . -s src/games/workout/tools/make_picker_card.gd`
- `tools/render_view.gd`: renders the ride view from a snapshot fixture to a PNG (windowed, it needs a renderer):
  `tools/godot.sh --path . -s src/games/workout/tools/render_view.gd -- --out=build/workout_view.png`

## Tests

- Unit: `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/games/workout -gexit -gjunit_xml_file=build/junit_workout.xml`
- With the platform (validator, importer, registry, protocol, full sims): `-gdir=res://tests/games/workout/integration`.
- e2e report check: `node tests/games/workout/e2e_check.mjs build/e2e/workout/report.json` (its tests: `node --test tests/games/workout/e2e_check.test.mjs`).

Real-trainer checklist: `HARDWARE_TEST.md`. Decisions: `docs/decisions/workout.md`.

## Audio

`audio/workout_audio.gd` (`WorkoutAudio`) maps game state to the bank `assets/workout/audio/audio.json`, rendered by `tools/audio` (`docs/AUDIO_PIPELINE.md`). It reads three clocks, the view's own:

- **Cadence**, `game.cranks` and `game.cadence_of`, the numbers the rider sheets are drawn from, so sound and legs cannot drift. `chain_tick` at revolution fraction 0 (the near pedal on top), `pedal_press` at .25 and .75 (a pedal furthest forward), `bb_creak` under load, `chain_hum` and `chain_rattle` by rpm and power, `breath` every second revolution above FTP, and in a scored sprint `crowd_clap` and `cowbell` on the hands the crowd is drawn with. All of it stops dead at 0 rpm. Other riders carry the tick and a quiet whirr.
- **Speed**, `shown_distance`: `tyre_hum`, `wind_rush`, and `freewheel_tick` per 0.35 m while coasting.
- **The view's `env_t`**: the breeze in the grass follows the same gust as the picture. The bed `dawn_road` crossfades `birds_dawn` to `birds_day` with session progress; spots are `lark`, `rooster` (start only), `dog_far`, `power_line_hum`, `chirrup`, and `tractor_far` only while a tractor crosses the screen.

The crowd and its cheer exist only where the view draws a crowd, so never in the warm-up (BRIEF 4.6.8), and you hear it as far as you can see it. `chain_shift` follows `gear_click_up` or `gear_click_down` a quarter of a revolution later. Events: `interval_chime`, then `interval_bell` a beat later; `crowd_cheer` and `cowbell` at a scored sprint's finish.

FTMS reports cadence about once a second, not crank angle: the sound locks to the crank on screen exactly and to your feet in rate only. Hear it: `node tools/audio/preview.mjs --game=workout`, then `build/audio_preview/workout.mp3`.
