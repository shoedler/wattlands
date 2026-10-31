# Workout

The reference game (BRIEF 3.7): a group interval ride for 1–8 riders, bots optional. Everyone rides the same timeline at their own % FTP. It proves the platform's paths: ERG phases, SIM phases with virtual gears, ramped mode switches, warm-up, cool-down, rescue, laps, FIT, Strava, multiplayer and zero input. It sends no directives: the plan does all the trainer work.

On screen is one morning on a country road, in pixel art on a 960 × 540 base. Real riders on bicycles turn their cranks at each rider's own cadence, 1:1. The ride starts in the blue hour and ends in full day.

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

## What the view shows

Three clocks drive it, and they never mix:

| Clock | Source | Drives |
| --- | --- | --- |
| Cadence | `game.cranks` (`WorkoutCrankClock`), one per rider | Legs, cranks, chain, breath, the crowd's hands |
| Speed | `shown_distance` | Wheels, road, verges, poles, pennant flutter, dust |
| Environment | The view's frame time | Wind pump, smoke, cattle, grass, clouds, hand flags |

- **Poses.** Seated; out of the saddle in a sprint at 120% FTP or on a climb of 4% at 95% FTP; sitting up in rescue or AFK; a foot down when stopped. Cranks hold still when a rider coasts, disconnects, or the session pauses or ends.
- **The group.** Up to 8 riders in three lanes. Where each is drawn is view-only (`WorkoutRig.formation_dx`, `spread`): the speed model has no draft, and a rider's position changes nothing in the rules. Each rider has the slot's jersey colour and pattern and a whip pennant with the slot's shape. A caret marks your own rider. A rider off screen is its pennant and an arrow at the edge.
- **Time of day.** Session progress picks one row of a 32-row LUT (`WorkoutTod`, `workout_tod.gdshader`). Every world plane goes through it: stars go at sunrise, windows go dark by day, mist burns off. Riders and props are true colour under a tint.
- **Depth.** Back to front: sky, stars, sun, clouds, far hills, mid hills with cattle, near trees with farmhouses and wind pumps, poles, the road, the crowd, the riders, the near verge, the earth bank with the interval blocks, and a foreground. Seeded spots cross the landscape (a flock, a tractor, a balloon by day; `WorkoutSpots`), the same on every peer.
- **Sprints.** A crowd and a gantry appear for a scored sprint and never in the first 300 s (BRIEF 4.6.8; `WorkoutCrowd.cheers_for`).

On a client the other riders are drawn between two snapshots, behind the newest by their mean spacing (100 ms at 10 Hz, about 1 s under the 8-rider load; `WorkoutSnapHistory`, filled by `apply_snapshot`), and the local rider from its own prediction, blended softly toward the host (BRIEF 5.1).

## HUD

Four plates of the game's own Controls in an enamel road-sign look, placed by `WorkoutHud.LAYOUT`; no kit widgets. The platform's rescue, warm-up and link notices stay on.

- **Timeline**, top centre: this block and its target, its time left, the whole session as a block profile, what comes next.
- **Mine**, bottom left: mode, heart rate and in-band lamp; watts (a 3 s mean through `HudRiderNumbers`) with %FTP and a gauge against the band; cadence with a crank icon that turns 1:1 with the rider's legs; one instruction line; W′ and the gear (lit in SIM, `-` in ERG).
- **Crew**, bottom centre: one card per rider with watts, %FTP, lamp and time in band, or `RESCUE`, `AFK` or `LINK`. Your card is outlined.
- **Score**, bottom right: session time in band with the live grade, this block's and the group's time in band, then speed and distance, or peak watts in a sprint.

A warm-up sprint shows `FREE RIDE`, never `SPRINT` (BRIEF 4.6.8). F1 shows the help overlay, which also opens once on a rider's first session.

## Code

- `workout_game.gd`: `WorkoutGame extends GameModule`, the SDK entry point.
- `rules/`: pure, deterministic logic. `WorkoutRules.step(state, frame, dt)` scores time in band (ERG ±5% of the applied target, Rolling road 76–105% FTP, sprints cadence ≥ 60 rpm), sprints (`WorkoutSprintTracker`, 1.2 × FTP) and moves each rider with `SpeedModel` from P_eff. `WorkoutSession` loads and validates sessions, `WorkoutCourse` builds the course, `WorkoutSnapshot` encodes the all-int snapshot, `WorkoutResults` and `WorkoutProgress` build results, XP and pennant unlocks.
- `hud/`: `workout_hud.gd` (the layout and the host's banners, toasts, power bands and teammate statuses), `workout_hud_model.gd` (what each plate shows, with no drawing), `workout_hud_draw.gd`, and the four plates.
- `view/`: `workout_ride_view.gd` runs the layers (`workout_track_layer`, `_road_layer`, `_bank_layer`, `_rider_layer`, `_prop_layer`). `workout_kit.gd` reads and validates `assets/workout/kit.json`. `workout_rig.gd` holds poses, formation and frames, `workout_crank_clock.gd` the crank phases, `workout_crowd.gd`, `workout_spots.gd` and `workout_tod.gd` the rest. `workout_art.gd` draws the geometry that stays in code: pennants and the interval blocks.
- `art/`: the Node bake, zero dependencies, seeded and deterministic. It writes everything in `assets/workout/` except `hud/`:
  - `node src/games/workout/art/bake.mjs` writes the art; `--check` fails unless the decoded pixels and `kit.json` match; `--preview=<dir>` writes composites for an art round.
  - `node src/games/workout/art/hud_bake.mjs` writes the HUD type and crank icon in `assets/workout/hud/`; `--check` compares them.
- `tools/render_frames.gd`: renders the real view and HUD from synthetic snapshots, every scenario in one Godot launch (windowed, it needs a renderer):
  `tools/godot.sh --timeout=300 --path . -s src/games/workout/tools/render_frames.gd -- --out=build/workout_frames` (`--only=<id,id>` narrows it).

## Tests

- GDScript: `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/games/workout -ginclude_subdirs -gexit -gjunit_xml_file=build/junit_workout.xml`. `integration/` runs the platform's validator, importer, registry, protocol and full sims.
- Node: `node --test tests/games/workout` (the bakes and the e2e report check).
- e2e report check: `node tests/games/workout/e2e_check.mjs build/e2e/workout/report.json`.

Real-trainer checklist: `HARDWARE_TEST.md`. Decisions: `docs/decisions/workout.md`.

## Audio

`audio/workout_audio.gd` (`WorkoutAudio`) maps game state to the bank `assets/workout/audio/audio.json`, rendered by `tools/audio` (`docs/AUDIO_PIPELINE.md`). It reads three clocks, the view's own:

- **Cadence**, `game.cranks` and `game.cadence_of`, the numbers the rider sheets are drawn from, so sound and legs cannot drift. `chain_tick` at revolution fraction 0 (the near pedal on top), `pedal_press` at .25 and .75 (a pedal furthest forward), `bb_creak` under load, `chain_hum` and `chain_rattle` by rpm and power, `breath` every second revolution above FTP, and in a scored sprint `crowd_clap` and `cowbell` on the hands the crowd is drawn with. All of it stops dead at 0 rpm. Other riders carry one sound, `peer_tick` on their own crank, in a band of its own: no loops, so a group cannot swell by locking in phase.
- **Speed**, `shown_distance`: `tyre_hum`, with `tyre_grit` on rough stretches (`road_at`, by the metre), `wind_rush`, and `freewheel_tick` per 0.35 m while coasting. The wheel runs on its own distance between sim steps, so ticks fall evenly. These sit on the Sfx bus: Machines holds only what stops with your legs.
- **The view's `env_t`**: the breeze in the grass and the gusts in `wind_rush` follow `air_at`, half the picture's gust and half a slower swell, so half an hour of a steady block repeats no wave. The bed `dawn_road` crossfades `birds_dawn` to `birds_day` with session progress; spots are `chirrup` (near and far), `wood_call`, `lark`, `rooster` (start only), `dog_far`, `church_bell_far`, and `tractor_far` only while a tractor crosses the screen. The chirrups, wood calls and larks thin out as the day comes up, so the chorus is what you hear change. `spot_min_gap_s` keeps the details 2.2 s apart.

The crowd and its cheer exist only where the view draws a crowd, so never in the warm-up (BRIEF 4.6.8), and you hear it as far as you can see it. `chain_shift` follows `gear_click_up` or `gear_click_down` a quarter of a revolution later, on the crank, and not at all if the legs stop first. Events: `interval_chime`, then `interval_bell` a beat later; `crowd_cheer` and `cowbell` at a scored sprint's finish.

FTMS reports cadence about once a second, not crank angle: the sound locks to the crank on screen exactly and to your feet in rate only. Hear it: `node tools/audio/preview.mjs --game=workout`, then `build/audio_preview/workout.mp3`.
