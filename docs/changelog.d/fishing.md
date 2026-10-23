# Changelog: fishing

### Added (Big Game Fishing) v0.1.0

- Big Game Fishing, a co-op sport-fishing game for 1-4 riders (BRIEF 3.6, `docs/games/fishing.md`): each rider skippers a boat whose stationary bike turns the big-game reel. The trainer is the rod: ERG holds the fish's pull, cadence is the skill (keep it in the tension band), runs and jumps are surges, and the 30 s Landing is a SIM gaff sprint.
- Fishing is now the first-run and quick-ride game for every fresh profile (`first_run_priority` 10, zero-input content `free_30`).
- Trips: Free (`free_20` to `free_120`, pre-rolled per rider, fights at most 40 % of fishing time), Base (`base_60`, nothing above 100 %, fights at most 25 %), Threshold (`threshold`, four scheduled 95 % tunas) and a 2-minute `e2e_2min`. Every trip opens with a 5-minute ride out (50 to 65 %); Reels are easy ERG spins at the rider's `reel_pct` (50-70 %).
- Coral Bank with four spot types, four species (mackerel, mahi-mahi, yellowfin tuna, blue marlin), spot picks by pedal-scan or left/right, bites, strikes, a tension band with strain and slack meters, runs, marlin jumps, lost lines with same-species replacements, Frenzies, Double Hookups, a shared catch board, grades S to D, XP and 11 cosmetic unlocks.
- Every load change goes through `ctx.directives` inside each Fight's `range_pct`: pull changes ramped at 25 W/s or less, runs that expire back to the base pull, at most 30 s per run and 90 s per fight above 105 % (mahi only), marlin jumps at 104 %, one 3 % last-run haptic per Landing after the warm-up.
- Zero input: Autopilot, and a zero-input fallback, pick, cast and strike in the host rules; picks auto-confirm after two scan cycles.
- 2D pixel art from the art pipeline (GPT Image 2.5 through fal), one equal lane per rider with the local lane highlighted, a deck bar, compact HUD controls around the kit widgets clear of the PANIC corner, and synthesized audio.
- Host-authoritative multiplayer: 10 Hz integer snapshots under 2 KB at 4 lanes, events in order, interpolated lanes, rejoin by snapshot.
- Tests: GUT unit and property tests (plans, the pull scheduler, rules, module, view, HUD, art), an opt-in 200-seed plan sweep, the brief 4.2 simulation matrix (`tests/games/fishing/sim/run_sims.sh`) with its checker, an e2e report check, CI (`.github/workflows/game-fishing.yml`) and a real-trainer checklist (`src/games/fishing/HARDWARE_TEST.md`).

### Known gaps (Big Game Fishing)

- Not tested on a real trainer or against the real Strava API. P1 content (Deep Blue Trench, `marlin_hunt`, `.zwo` bite scheduling, the legendary two-rod fish) is not built: see `src/games/fishing/BACKLOG.md`.
