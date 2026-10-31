# gate

- Added a machine-wide cap file for the Godot lock: `node tools/lib/godot_lock.mjs set-cap <n>` (`0` deletes it, and the default stays as it was with no file). `WATTLANDS_GODOT_LOCK_CAP` still wins.
- Added `WATTLANDS_USERDATA_DIR` to `tools/godot.sh` and `tools/godot.ps1`, for concurrent runs in one checkout.
- `tools/screenshot` now opens at most 4 windows at once on a machine; further runs wait for a free one.
- Added `tools/gate` and `tools/gate.ps1`: `check` (ownership, safety pins, append-only checker pins, test counts, sidecars, class names, locks in added code), `fast` (all GUT in 8 shards, plus sim and e2e of the touched games), `strict` (every step, with one GUT process), `matrix` (a game's `run_sims.sh` in a pool), `stamp-ok`, `floor`, `fmt`, `wt-add`, `wt-gc` and `pin-safety`. `tools/run_tests` stays the literal serial gate.
- Added `--games` and `--sim-outer-timeout` to `tools/run_tests`, and `WATTLANDS_SIM_PLAN` to `tools/run_game_sim` (records the arguments and starts nothing). With neither set, both behave as before.
