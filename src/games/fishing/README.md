# Turbo Reel

Sport fishing for 1-4 riders (plus bots) on one shared ocean (docs/games/fishing.md). Your stationary bike drives a pedal boat and, once a fish bites, turns the big-game reel.

- **Free Roam** (the headline mode, competitive): drive out from the harbour across the shallows, the reef, the shelf and the deep to the abyss at the edge of the world. Ease off below 20 % FTP-equivalent and the boat drifts to a stop; a light menu offers the fish you can see there (cast), Drive on and Turn around. A cast dives the wobbler to the fish, the bite starts a fight. Bigger fish live farther out and fight harder; points scale with weight, so many small fish near the dock and a few giants far out both pay. Most points when the clock runs out wins; a fight on at time-up may finish (at most 5 more minutes).
- **Workouts** (co-op): structured plans on an endless map; the boat trolls between fights and the plan's fish bite.

The fight (both modes): in ERG the trainer holds the fish's pull, so cadence is the skill: keep it inside the tension band; too slow strains the line (snap), too fast throws the hook. The fish tires while you are in band; runs and jumps are surges. At the boat a 30 s Landing in SIM gives a 15 s gaff sprint (a full gaff meter is a Trophy, x1.5 points).

Safety first (BRIEF 4.6): the game changes trainer load only through `ctx.directives`. Driving is SIM with a course grade of 0.5 % + 2 (v / 15 m/s)^2 (at most 3 %; v without the planing gain); a big fish's surge requests an ERG `haptic_pull` (+50 % FTP for 2 s, haptics on only; the governor bounds it); each fight is its own ERG phase, validated by the PlanValidator when it is replanned in; pull changes ramp at <= 25 W/s inside the phase's `range_pct`; phases longer than 300 s stay <= 105 %; only the giant grouper (105-110 % for 3-4.5 min, max 300 s) and the oarfish's runs pass 105 %, and a rider's plan never accrues more than 300 s above 105 % (a later giant caps at 105 %). The first 5 minutes are a SIM drive-out with no fights.

## Contents

| Content | What |
| --- | --- |
| `roam_30` (default), `roam_10`, `roam_20`, `roam_45`, `roam_60` | Free Roam: N minutes from the start, the first 5 the drive-out |
| `base_60` | 52 min of fishing, mackerel and mahi, nothing above 100 %, fights <= 25 % |
| `threshold` | 4 scheduled tuna at 95 % with 360 s Trolls between (55 min) |
| `e2e_2min` | the e2e content: 15 s ride out, 20 s Troll, one scheduled mackerel per rider, Landing (<= 135 s) |

`roam_30` is the zero-input and the first-run content (`first_run_priority` 10). Rider options: `reel_pct` (the workouts' Troll target, 50-70 %) and `relaxed_band` (a 22 rpm band instead of 16).

## Playing

Pedal to drive, ease off to stop. In the menu: left / right and confirm (keyboard, gamepad); with pedal navigation on (`PlayerSlot.pedal_nav`) the menu also scans every 1.6 s, a `surge` confirms and it auto-confirms after two scan cycles. Pedaling hard from a stop drives on. Confirm while waiting reels in. Autopilot riders and bots make every choice themselves; bots play one of four strategies (vibe, small, mixed, big).

```bash
. tools/env.sh
tools/godot.sh --path .                 # the app: pick Turbo Reel
tools/godot.sh --path . -- --game=fishing --content=roam_30 --mock-trainer=erg+band --autopilot
```

## Files

| Path | What |
| --- | --- |
| `game.json` | The manifest |
| `fishing_game.gd` | `FishingGame`: content, plans, the host sim, directives, snapshots, events, toasts, results (loads the view and HUD by path) |
| `contracts/` | `FishingWorld` (the roam map, the endless map), state and rider records, species, trip and slot defs, events, intents, snapshot schema v2, `FishingConst` |
| `rules/` | `FishingRules` (the Free Roam flow and the workouts), `FishingBoat` (rigid-body boat: surge, heave, pitch, planing, tow), `FishingFight` (fight, landing, points, hookups); pure, 0.05 s steps |
| `plan/` | `FishingPlanBuilder` (the roam plan and its fight tails, workout plans), `FishingPreroll` (roam slots at the bite, workout slots), `FishingPullScheduler` |
| `autopilot/` | `FishingAutopilot`: Autopilot's and the bots' choices and strategies |
| `net/`, `results/` | Snapshots; results, Strava tag and lines, XP, unlocks, progress |
| `view/`, `hud/`, `audio/` | The one-ocean view, the minimap HUD and synthesized audio |
| `tools/` | `FishingArtGrids` and `fishing_write_sprites.gd`: the hand-authored art (see `assets/fishing/README.md`) |
| `content/fishing/` | `species.json`, `map.json`, `trips/*.json`, `cosmetics.json`, `strings.csv` |

## Testing

```bash
. tools/env.sh
tools/run_tests --only=gut --gdir=res://tests/games/fishing
(cd tests/games/fishing && node --test)
tools/godot.sh --headless --path . -s tools/check_scripts.gd
node tools/e2e/run.mjs --games=fishing
```

## Simulations

`bash tests/games/fishing/sim/run_sims.sh` runs the matrix through `tools/run_game_sim` (reports in `build/fishing/sims/`) and checks it with `check_sims.mjs --fit`:

| Scenario | Run | Asserted |
| --- | --- | --- |
| R1 | `roam_30`, 1 band-tracker, Autopilot | >= 2 fish, no bite in the drive-out, one replan per bite, time-up, trip over |
| R2 | `roam_30`, 4 riders | everyone lands fish |
| R3 | `roam_30`, 1 rider + 3 bots, seeds 1-5 | every bot fishes, all four strategies appear, small and big within x2.5 |
| R4 | `roam_10`, `erg:compliance=1.0` (no band), Autopilot | the zero-input session plays through |
| R5 | `roam_30`, `--ftp=300,200 --unverified --haptics-off=1` | x0.85 on every ERG target, no haptic to the opted-out rider |
| R6 | `roam_30`, rider 2 stops pedaling at 900 s for 60 s | paused or AFK, no load meanwhile, fishes again |
| W1 / W2 / W3 | `threshold` / `base_60` / `e2e_2min` | 4 tuna, 240-420 s fights / the plan's fish / one mackerel each by 135 s |
| D | `roam_10` with bots, twice | the same `deterministic_hash` |
| FIT | every FIT | `tools/fit_check` with one lap per lap phase that ran |
| ALL | every run | no plan warnings, every directive accepted, requests inside their phase's range, course grades 0-3 % only in roam SIM phases, only allowed clamps, phases > 300 s <= 105 %, snapshots <= 2 KB |

`--quick` (CI) runs W3, D and FIT.

## Audio

All sound is rendered by `tools/audio` from `assets/fishing/audio/audio.json` (`docs/AUDIO_PIPELINE.md`); `audio/fishing_audio.gd` only maps the game to the bank's parameters and cues. Each boat is one `drivetrain` machine driven with `FishingBoatView.crank_clock`, the number its crank is drawn from, so strokes and the crank cannot drift. The sound locks to the on-screen crank exactly and to the rider's feet in rate only: FTMS reports cadence, not crank angle, about once a second.

| Param | From | Moves |
| --- | --- | --- |
| `prop` | the boat's speed, 0 once the clutch is halfway to the winch | the putt's gate, the water's level and pitch |
| `load` | `p_eff_w` over 250 W | the putt's level and pitch, the crackle, the gear whistle |
| `reel` | line coming in, smoothed, 0 unless fishing and not on a run | the ratchet |
| `tension` | the rod's shown tension | the line's creak, song and pitch, the rod's groan, the winch |
| `near` | distance to your boat, 1 within 150 m, out of earshot from 700 m | another boat's level |
| `near_dock`, `speed` | your boat (bed params) | gulls, rigging and the harbour; wind and hull slaps |

Listen: `node tools/audio/preview.mjs --game=fishing` writes `build/audio_preview/fishing.mp3` (out of the harbour, flat out, cast, bite, the fight, the catch) with a solo per rpm. `node tools/audio/scorecard.mjs --game=fishing` holds the mix to its numbers; `tests/games/fishing/audio/` holds the sync, the cue map and the sound list.
