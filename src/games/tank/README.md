# Diesel Domestiques (`tank`)

One to three riders crew a pedal-powered super-heavy tank, one engine each (diesel, dynamo, steam; the solo Bulwark's diesel drives everything through a three-way gearbox). Brief: `docs/games/tank.md`. Decisions: `docs/decisions/tank.md`. Contracts and the per-tick data flow: `contracts/README.md`.

Status: G0. The game plays end to end with a placeholder drive and objective (the tank rolls at a fixed speed; each open-ended segment's objective is met at 90% of its nominal length), the full effort plans (`effort/tank_plan_builder.gd`), end_phase, cadence and power bands, the snapshot, results and progress. G1 builders replace the placeholders; the lead completes this README in G4 (rules, effort tables, content schemas, tuning knobs, art regeneration, P2 notes).

## Contents

| Content | Plan | Notes |
| --- | --- | --- |
| `ashfall_road` | depot 300 s, 3 x (Advance 90-300 s, gun line 60-180 s, checkpoint 60 s), boss 120-360 s, cool-down 180 s | 30 min nominal, 41 min at most; 12 FIT laps |
| `drill` | depot 30 s, skirmish 70 s (WARMUP), checkpoint 30 s, cool-down 180 s | the e2e content, inside the warm-up limits; 4 FIT laps |

Option: `rotation` (default on) moves every rider to the next engine at each checkpoint (stations.json `rotation`).

## Commands

```bash
. tools/env.sh
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/run_tests --only=gut --gdir=res://tests/games/tank
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/run_game_sim --game=tank --content=drill --players=1 --rider=erg --seed=1 --report=build/tank/sims/drill.json
node tools/fit_check/check.mjs build/tank/sims/fit --expect-laps=4
```
