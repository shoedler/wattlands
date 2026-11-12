# Decisions: sim speed

## 2026-11-12: a run_game_sim run scans only the game it rides

- **Decision:** `tools/sdk/run_game_sim_main.gd` turns the GameRegistry autoload's start-up scan off in `_initialize()` (which runs before the autoloads' `_ready`), and `GameSimCli.scan_registry()` fills it on the first frame with `WlGameRegistry.scan_only([<--game>])`. An unknown, invalid or missing `--game`, and `_template`, fall back to the full `scan()`, so setup fails with the same message as before.
- **Alternatives:** a command-line flag that GameRegistry reads in `_ready` (the app's autoload would learn a sim-only flag); a private registry per run (anything that looks the autoload up, such as a NetSession's lobby, would see an empty one).
- **Reason:** validating a game loads its entry script, which compiles everything it references. With all four games that was 2.3 to 2.6 s of every run's start-up, and a sim matrix pays it once per run (85 runs for Tank). The run's own game is still validated and its strings registered; reports and FIT files are byte-identical.
