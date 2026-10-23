# Big Game Fishing

A co-op sport-fishing game for 1-4 riders (docs/games/fishing.md). You skipper a small boat in a tropical bay; a stationary bike bolted to the deck turns the big-game reel. Ride out, pick one of three spots, cast and reel at an easy spin; when a fish bites, the fight is the interval. In ERG the trainer holds the fish's pull, so cadence is the skill: keep it inside the tension band, low cadence strains the line (snap), high cadence lets it go slack (thrown hook). The fish tires while you are in band; at the boat a 30 s Landing in SIM gives a 15 s gaff sprint (a full gaff meter makes a Trophy). Pulls are shares of each rider's FTP and fish tire by compliance, so every FTP plays fair. A shared catch board, Double Hookups (overlapping fights score more) and Frenzies make it co-op.

Safety comes first (BRIEF 4.6): the game changes trainer load only through `ctx.directives`. Every pull is an ERG directive inside the Fight's `range_pct`, increases ramp at <= 25 W/s, only the mahi's runs pass 105% (<= 90 s per fight), marlin jumps stop at 104% (the 105% long-phase cap), the only sprint is in SIM, and the one haptic (+3% for 5 s) comes in the Landing, never in the warm-up.

## Trips (content ids)

| Trip | What |
| --- | --- |
| `free_20` ... `free_120` | 5 min ride out, (N - 8) min fishing, cool-down; mackerel, mahi, tuna (free_90 / free_120: a marlin as slot 2 with p = 0.3); fights <= 40% of fishing |
| `base_60` | 52 min fishing, mackerel and mahi, nothing above 100%, fights <= 25% |
| `threshold` | ride out, then 4 scheduled tuna at 95% with 360 s Reels between (55 min) |
| `e2e_2min` | the e2e content: 15 s ride out, 20 s Reel, one scheduled mackerel per rider, Landing (<= 135 s) |

`free_30` is the default, the zero-input and the first-run content (`first_run_priority` 10). Rider options: `reel_pct` (50-70% in steps of 5) and `relaxed_band` (a 22 rpm band instead of 16).

## Playing

Zero input works: a rider who only pedals plays as Autopilot (it picks the strongest spot, casts, strikes at 0.5 s) until their first button or key action; cadence still steers the tension. Controls: left / right or pedal-scan to pick a spot, confirm or a `surge` to cast and to set the hook; the gaff sprint is pedaling hard in the Landing's first 15 s.

```bash
. tools/env.sh
tools/godot.sh --path .                 # the app: pick Big Game Fishing
tools/godot.sh --path . -- --game=fishing --content=free_30 --mock-trainer=erg+band --autopilot
```

## Files

| Path | What |
| --- | --- |
| `game.json` | The manifest (contents, player options, picker image) |
| `fishing_game.gd` | `FishingGame`, the GameModule entry: plans, the host sim, snapshots, events, results |
| `contracts/` | Frozen G0 records: state, lanes, fish, species and trip defs, plan slots, events, snapshot schema, constants, `FishingRandom` |
| `plan/` | `FishingPreroll` (per-rider fight slots), `FishingPlanBuilder` (phases), `FishingPullScheduler` (pull changes, runs, jumps) |
| `rules/` | `FishingRules.step(state, inputs, dt)`: spots, bites, tension, meters, tiring, losses, landing, points (pure, 0.05 s steps) |
| `autopilot/` | Autopilot and the zero-input fallback (played inside the host rules) |
| `net/` | Snapshots (<= 2 KB at 4 lanes) and events |
| `results/` | Grades, rows, XP, unlocks |
| `view/`, `hud/` | The 640 x 360 view (one lane per rider), the HUD, synthesized audio |
| `tools/` | `FishingFallbackSprites` (brief 3.4's code-drawn fallback art) and the tool that writes it |
| `HARDWARE_TEST.md` | The real-trainer checklist |
| `BACKLOG.md` | P1 and P2 items not in v0.1 |
| `content/fishing/` | `species.json`, `areas/coral_bank.json`, `trips/*.json`, `cosmetics.json`, `strings.csv` (keys `FISHING_*`) |
| `assets/fishing/` | `art.json`, `art_manifest.json`, `sprites/` (see its README) |
| `tests/games/fishing/` | GUT tests per area, `art/` (sprite palette), `sim/` (the 4.2 matrix), `e2e_check.mjs` |

## Testing

```bash
. tools/env.sh
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/run_tests --only=gut --gdir=res://tests/games/fishing   # GUT, strict rules
(cd tests/games/fishing && node --test)                                                           # sim and e2e checkers
tools/godot.sh --headless --path . -s tools/check_scripts.gd
node tools/e2e/run.mjs --games=fishing                                                            # host + 2 clients, e2e_2min
```

## Simulations (brief 4.2)

`bash tests/games/fishing/sim/run_sims.sh` runs the matrix through `tools/run_game_sim` (reports in `build/fishing/sims/`) and asserts it with `node tests/games/fishing/sim/check_sims.mjs build/fishing/sims --fit`:

| Scenario | Run | Asserted |
| --- | --- | --- |
| S1 | `threshold`, 2 band-trackers | 4 tuna landed per rider, fights 240-420 s, no snaps, clamps only slew / floor / unverified / haptic |
| S2 | `threshold` at `erg+band:offset_rpm=-18` / `=18` | a snap / a thrown hook within 8 s of every hookup; no phase shortened |
| S3 | `free_30`, 4 riders, seeds 1-5 (`--full`: 1-20) | trip <= 35 min, fights <= 40%, median >= 2 fish, a Double Hookup |
| S4 | `free_30` solo, `erg:compliance=1.0`, Autopilot off and on | >= 1 fish each |
| S5 | `base_60` | nothing above 100%, fights <= 25% |
| S6 | `free_120` on a marlin seed (`sim/fishing_marlin_seed.gd`, the pure pre-roll) | 4-8 jumps of 20-30 s at 104%, 0 s above 105% |
| S7 | `threshold`, 40 rpm for 20 s from 600 s | rescue, no snap during the stagger, the fight resumes and lands |
| S8 | the same run twice | identical events, phases, applied directives, results and `deterministic_hash` |
| S9 | every FIT | `tools/fit_check` with one lap per ride out, Reel and Fight that ran, plus the cool-down |
| S10 | `e2e_2min`, 3 riders | one mackerel per rider, the cool-down by 135 s |
| ALL | every run | requests exact and inside the phase's `range_pct`; `clamped_by` only slew, floor, unverified, rescue, coasting, haptic_intensity, warmup (switch_ramp, paused noted), never ceiling, long_phase, limit_105, limit_120 |

`--quick` (CI) runs S10, the S8 pair on `e2e_2min` and S9. The matrix stays out of `tools/run_tests`.

## Art

v0.1 ships generated art: every sprite in `assets/fishing/art.json`, `picker_card` included, made with GPT Image 2.5 through fal and pixelated to the 32-colour palette (53 paid requests, $3.56 of the $10 budget; `assets/fishing/art_manifest.json`, credits in `docs/credits.d/fishing.md`). `FishingFallbackSprites` (`tools/fishing_fallback_sprites.gd`) stays as brief 3.4's fallback: `FishingSprites` draws a sprite from it only when its PNG is missing. `assets/fishing/README.md` has the commands to regenerate or re-roll a sprite with `tools/art/generate.mjs` and `tools/art/pixelate.gd`.

The boat's rig is fitted to the generated `boat.png` in `view/fishing_rig.gd` (its header lists the measured parts), and `tests/games/fishing/view/test_fishing_rig_art.gd` checks the mount points against the PNGs, so a re-rolled boat, bike or angler fails there until the numbers are retuned. The hull's PaletteSwap maps the key ramp plus the trim's coral, pink and peach shades (`FishingPalette.HULL_KEYS`).
