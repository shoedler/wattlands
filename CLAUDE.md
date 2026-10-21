# Wattlands

Wattlands is a multiplayer fitness party app for the Wahoo KICKR CORE smart trainer, built in Godot 4.7 (GDScript, Compatibility renderer, Windows first). One app hosts several games through the Game SDK. `docs/BRIEF.md` is the platform brief; `docs/games/<id>.md` are the game briefs. "BRIEF x.y" means a section of `docs/BRIEF.md`.

Read `docs/ARCHITECTURE.md` for the layers and `docs/GAME_SDK.md` for the game contract. `docs/OWNERSHIP.md` maps every path to its owner and lists what the game briefs need from the platform. Decisions live in `docs/DECISIONS.md` (merged from the fragments in `docs/decisions/`).

## Safety comes first

- BRIEF 4.6 (the safety governor) outranks every gameplay idea, in every brief. Change a design to fit it, never the other way round. Never weaken a 4.6 threshold or a BRIEF 7 assertion to reach green; report what fails instead.
- Every path to the trainer goes through `SafetyGovernor`. Only `SafetyGovernor` holds `TrainerController`, only `TrainerController` calls `TrainerDevice` setters, only `FtmsTrainer` calls `FtmsClient.write_control()`. `tests/arch/test_no_bypass.gd` enforces this. Games change trainer load only through `ctx.directives`.

## Locks (BRIEF 1)

- Source `tools/env.sh` (Git Bash) or `tools/env.ps1` (PowerShell) in every shell. They set `WATTLANDS_NO_HW_CONTROL=1` and `WATTLANDS_NO_NETWORK_INTEGRATIONS=1`. The Godot wrappers and `tools/run_tests` set both themselves too.
- Hardware lock: while `WATTLANDS_NO_HW_CONTROL=1`, `FtmsClient` refuses Request Control and every control-point write and logs "hardware control locked". Never send ERG, simulation or resistance commands to a real trainer from an automated run.
- Network lock: while `WATTLANDS_NO_NETWORK_INTEGRATIONS=1`, the Strava client talks only to 127.0.0.1 or localhost, never opens a browser, and logs "network integrations locked". Tests use `server/mock_strava`.
- Art lock: `tools/art/generate.mjs` makes real fal calls only with both `FAL_KEY` and `WATTLANDS_ALLOW_ART=1`; tests always pass `--mock`. The env scripts and Godot wrappers never set, unset or print `FAL_KEY` or `WATTLANDS_ALLOW_ART`; `tools/run_tests` removes both from the environment of the processes it starts, so no test can reach the real fal. Never print, log or commit the key.
- Only `--allow-hw` and `--allow-network`, passed to the wrappers by a human following `docs/HARDWARE_TEST_PLAN.md`, drop the locks. No agent ever passes either.

## Running Godot and tests (BRIEF 2, 7)

- Run Godot only through `tools/godot.sh` (Git Bash) or `tools/godot.ps1` (PowerShell). The wrapper resolves the binary (`$GODOT`, then `tools/godot_bin.local` in this or the main checkout, then `godot` on PATH), closes stdin, applies a timeout that kills the whole process tree, never passes `-d`, sets a per-checkout user dir (`.userdata/`), and queues on a machine-wide lock (`--lease=<n>`, `--lock-timeout=<s>`; exit 75 on a lock wait timeout).
- Never pass `-d` or `--debug` to an automated run. Close stdin and wrap every run in a timeout. No Godot process starts another Godot process: a check that needs its own Godot run is a separate step of `tools/run_tests`.
- Never run two imports or editors on one folder. Refresh caches with `tools/godot.sh --headless --path . --import` after adding files; it is not a gate.
- Full suite: `tools/run_tests` (or `tools/run_tests.ps1`). It passes only if GUT exits 0, the log has "Run Summary", the JUnit count is above 0 and at least the previous green count, and the log has none of "SCRIPT ERROR", "Parse Error", "Debugger Break", "Ignoring script" or "Nothing was run".
- GUT only: `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=build/junit.xml`. Narrow it with `-gdir=res://tests/<dir>`.
- Script check: `tools/godot.sh --headless --path . -s tools/check_scripts.gd` loads every .gd under `addons/wattlands/`, `src/`, `tests/` and `tools/`.
- GUT fails a test on any unhandled `push_error`. Code that rejects bad input uses `push_error` and its tests use `assert_push_error()`; expected non-fatal conditions (no Bluetooth adapter, a refused directive) use `push_warning`.
- Node suites: `node --test` in `server/relay`, `server/mock_strava`, `tools/art`, `tools/tests` (no npm dependencies needed).

## Conventions (BRIEF 6)

- Static typing everywhere except GDExtension classes (GDBLE objects are created with `ClassDB.instantiate()` and held as `Object`/`Node`/`RefCounted`, only inside `addons/wattlands/trainer/ble/gdble_transport.gd`).
- Game rules are pure classes with `step(state, inputs, dt)`. The sim always advances in fixed 0.05 s steps on the platform's sim clock. RNG is seeded (`ctx.rng`); rules never read wall-clock time (`Time.*`, `OS.get_ticks*`), global `randi`/`randf` or `RandomNumberGenerator.new()`.
- Content is JSON, validated at load. No editor-only APIs at runtime. Cross-module communication uses `EventBus` signals, never node paths into another module.
- Unique `class_name`s. Game classes carry their game's prefix (`SiegeTower`, `TankShell`, `FishingLaneState`, `WorkoutRideView`). Platform classes never use a game prefix.
- User-facing strings: `content/strings/<module>.csv` for the platform, `content/<id>/strings.csv` for games. Game keys start with the upper-case game id and an underscore (`WORKOUT_`, `SIEGE_`, `TANK_`, `FISHING_`); platform keys never do.
- Every persisted file goes through `Paths.user_dir()` (honours `--profile-dir=<abs path>`). Tests use a fresh temp dir.
- System nodes (trainer stack, governor, MockTrainer, NetSession and transports, GameHost, input router, gesture recognizer) run with `process_mode = PROCESS_MODE_ALWAYS`. Pause never uses `SceneTree.paused` for them.
- Commit `*.import` and `*.uid` files. Commit small, conventional commits.
- Decisions: short ADRs (date, decision, alternatives, reason) in `docs/decisions/<agent or game id>.md`; the lead merges them into `docs/DECISIONS.md`. Credits and changelog entries go in `docs/credits.d/` and `docs/changelog.d/` fragments.
- Command-line flags come after `--` and are read with `OS.get_cmdline_user_args()` through `CmdLine`: `--mock-trainer=<profile>`, `--autopilot`, `--host`, `--join=<code>`, `--relay=<url>`, `--game=<id>`, `--content=<id>`, `--seed=<n>`, `--sim-speed=<x>`, `--run-seconds=<n>`, `--report=<path>`, `--screenshot-dir=<dir>`, `--profile-dir=<abs path>`, `--strava-base=<url>`. `--sim-speed` runs x fixed steps per 0.05 s of wall time and never touches `Engine.time_scale`.

## Ownership

`docs/OWNERSHIP.md` lists who owns each path. Agents edit only their own paths. Nobody but the lead edits `README.md`, `CHANGELOG.md`, `.gitignore`, `project.godot`, `addons/wattlands/contracts/` or another module's files: write fragments and put requests in your report. Contracts are frozen after W0; changes are additive and go through the lead.

Never edit `docs/BRIEF.md` copies, `docs/games/`, `docs/concept/`, `docs/research.md`, `.gitattributes` or `.claude/settings.json`.

## Adding a game

A game session adds one game under its own paths and changes nothing else:

- Paths it owns: `src/games/<id>/` (code, `game.json`, the GameModule entry script, `README.md`, `HARDWARE_TEST.md`), `content/<id>/` (JSON content, `strings.csv`), `assets/<id>/` (art, audio, `art.json`), `tests/games/<id>/`, `.github/workflows/game-<id>.yml`, and the fragments `docs/decisions/<id>.md`, `docs/credits.d/<id>.md` and `docs/changelog.d/<id>.md`.
- Start with `tools/new_game <id>` (scaffolds every path from `src/games/_template/`; refuses if any target exists). Read `docs/GAME_SDK.md` (the contract, with worked examples from `_template` and Workout), `docs/ART_PIPELINE.md` for 2D art, and `docs/ARCHITECTURE.md`.
- SDK: extend `GameModule` by class name. Change trainer load only through `ctx.directives` (`request`, `course_grade`, `end_phase`, `cadence_band`, `replan`). Feed the HUD through `ctx.hud`, send widget intents through `ctx.intents`, keep per-rider progression in `ctx.progress`.
- Tools: `tools/run_game_sim`, `tools/new_game`, `tools/screenshot`, `tools/run_tests` (bash, plus `.ps1` twins), `node tools/e2e/run.mjs --games=<ids>`, `node tools/fit_check/check.mjs`, `node tools/art/generate.mjs` and `tools/art/pixelate.gd`.
- Gates: the game's own tests under `tests/games/<id>/`, `tools/check_scripts.gd`, `tests/sdk/test_conformance.gd` (unchanged), the game's simulation matrix through `tools/run_game_sim`, `tools/fit_check` on every FIT the sims wrote, `node tools/e2e/run.mjs --games=<id>`, and the full `tools/run_tests` at or above the previous green count.
- Write `src/games/<id>/HARDWARE_TEST.md`, a real-trainer checklist in the style of `docs/HARDWARE_TEST_PLAN.md`; the platform plan only links to it.
- Platform-change policy: change the platform only when a game's P0 item is blocked. Keep it small, additive and tested (no renamed API, no changed default, nothing weakened in BRIEF 4.6 or 7), update `docs/GAME_SDK.md` if the API grows, keep the platform suite green, and commit it alone with the prefix `platform:`.
