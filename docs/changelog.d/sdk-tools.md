# Changelog: sdk-tools

## 0.1.0

- The template game `_template` (`src/games/_template/`): a tiny 2D game that shows every SDK call in under 300 lines, with two contents, string keys, unit tests on recording fakes and integration tests through the real runtime.
- `tools/run_game_sim` and `tools/run_game_sim.ps1`: headless game sessions with MockTrainer riders, every BRIEF 3.6 flag, the locks enforced twice, relative paths from your current directory, `--echo-args`, exit codes 0/2/3/4/5.
- `tools/new_game` and `tools/new_game.ps1`: scaffold a game from the template (renamed classes, keys, paths and files; no `.uid`/`.import`/`.translation`; the game's CI workflow and docs fragments), refusing to overwrite an existing game.
- `docs/GAME_SDK.md`: the game contract, the tools, the report, the mock rider profiles, the safety rules and an FAQ for the game briefs.
- `tools/run_game_sim` exits 5 when Godot logged a script error during the run, deletes the previous report and FIT files at its `--report` path before running, checks slot lists against `--players` and `--bots`, and passes `--mock-trainer=erg`.
- `tools/new_game` refuses an id whose class names already exist in the project.
- The template validates every content phase at load.
