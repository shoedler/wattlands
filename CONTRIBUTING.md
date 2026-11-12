# Contributing to Wattlands

Thanks for looking. Fixes, new games, art, sound and better words are all welcome. If you're planning something big, open an issue first so nobody builds the same thing twice.

## What you need

- [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/), the standard build. Its path goes in `tools/godot_bin.local` (one line, git ignores it), or in `$GODOT`, or put `godot` on your `PATH`.
- [Node 22.18 or newer](https://nodejs.org/).
- [uv](https://docs.astral.sh/uv/), which fetches the GDScript formatter and linter. Without it those two checks are skipped and CI will catch what they would have.
- Git Bash on Windows. Every tool also has a PowerShell twin (`tools/godot.ps1`, `tools/gate.ps1`).

Windows is where the game ships. The tests run on Linux too, and CI uses it. You don't need a trainer: a mock one stands in everywhere.

## First run

```bash
git clone https://github.com/shoedler/wattlands.git
cd wattlands
. tools/env.sh
tools/godot.sh --headless --path . --import
tools/godot.sh --path . -- --mock-trainer=erg
```

Add `--mock-keyboard` to steer the mock rider. [docs/TRAINER.md](docs/TRAINER.md) has the keys.

Source `tools/env.sh` in every shell (`tools/env.ps1` in PowerShell) and always start Godot through the wrapper. They set the locks that stop an automated run from commanding a real trainer or reaching Strava. The wrapper also runs at most a few copies of Godot at once across your PC, so if a run seems to sit there, it's waiting for another one to finish. `node tools/lib/godot_lock.mjs status` shows who holds the slots.

To try multiplayer on one PC, open two copies. With no relay set they find each other on the network. Choose Host a room in one and join with its code in the other. Pass a different `--profile-dir=<absolute path>` to each so they don't share a rider.

## Making a change

1. Branch from `main`. Any branch name works.
2. Make the change, with tests. A bug fix gets a test that fails without it.
3. Check it:

   ```bash
   . tools/env.sh
   tools/gate fmt
   tools/gate check --contributor
   tools/gate fast --contributor
   ```

   `check` and `fmt` take seconds. `fast` takes several minutes on a good machine, using about three quarters of its cores. It runs the linter, the Node suites, the simulation and end-to-end runs of the games you touched, and the GUT tests: all of them, or, when you changed only a game's own files, the platform's and that game's. If your change touches a game with `tests/games/<id>/sim/run_sims.sh`, also run `tools/gate matrix --game=<id>`. If you start a gate in the background, `tools/gate wait` shows its lanes as they finish and exits with its verdict.

   Too slow for your machine? Test what you touched and let CI run the rest:

   ```bash
   tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/net -ginclude_subdirs -gexit -gjunit_xml_file=build/junit.xml
   ```

4. Open a pull request. Say what changed, why, and what you couldn't test.

CI runs the same gates on your pull request. The first time you contribute, a maintainer approves the run. The full suite takes about two hours on GitHub's runners, so expect to wait.

## What you can't change, and what to do instead

Some things are held in place on purpose. `tools/gate check --contributor` tells you when you've touched one.

| Path | Rule |
| --- | --- |
| `docs/BRIEF.md`, `docs/games/`, `docs/concept/`, `docs/research.md` | The original briefs, kept as written. Don't edit them. If one is wrong, say so in an issue. |
| Safety pins: the trainer stack, governor tests, the gates ([full list](tools/lib/gate_manifest.json)) | You may propose a change. A maintainer reviews it line by line, updates the pins and records why. |
| `README.md`, `CHANGELOG.md`, `CREDITS.md`, `project.godot`, `addons/wattlands/contracts/` and a few more | Fine to propose. A maintainer lands them. For the changelog and credits, add a fragment instead: `docs/changelog.d/<topic>.md`, `docs/credits.d/<topic>.md`. |

Two rules never bend:

- **Safety comes first.** `SafetyGovernor` (BRIEF 4.6) outranks every gameplay idea. If a design fights it, the design changes. Never lower a limit, or weaken or skip a test, to get to green. If something fails, say so in your pull request.
- **Every path to the trainer goes through the governor.** Games change the load only through `ctx.directives`. `tests/arch/test_no_bypass.gd` enforces it.

Don't send trainer control commands to real hardware from anything automated. `--allow-hw` and `--allow-network` exist for a person riding through [docs/HARDWARE_TEST_PLAN.md](docs/HARDWARE_TEST_PLAN.md), never for a script. If you've tested on a real trainer, tell us in the pull request what you rode and on which firmware. We'd love to know.

## How a pull request lands

A maintainer reviews it and lands it by merge, one branch at a time, usually in a batch with others before a release. Don't worry about the merge queue, the test floor or the safety pins. If your branch falls behind, merge `main` into it; please don't rebase once review has started.

## Where things are

| | |
| --- | --- |
| The platform | `addons/wattlands/`, with the app shell in `src/app/` |
| The games | `src/games/<id>/`, `content/<id>/`, `assets/<id>/`, `tests/games/<id>/`. The ids: `fishing` is Turbo Reel, `siege` is Castellum Rotae, `workout` is Workout, `tank` is Torque Company. |
| The relay | `server/relay/` |
| Tools | `tools/` |
| How it fits together | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and the map of everything in [docs/README.md](docs/README.md) |

### Adding a game

`tools/new_game <id>` scaffolds every path from a working template, then run `tools/gate fmt`. Read [docs/GAME_SDK.md](docs/GAME_SDK.md); it has worked examples. Keep your game inside its own paths. Sound follows [docs/AUDIO_PIPELINE.md](docs/AUDIO_PIPELINE.md) and generated art follows [docs/ART_PIPELINE.md](docs/ART_PIPELINE.md). Anything every game could use belongs in the platform, as a small, tested change with the commit prefix `platform:`.

### Style

- Static typing everywhere. `tools/gate fmt` runs gdformat, and gdlint findings get fixed in code, never with `# gdlint: disable`.
- Game rules are pure classes with `step(state, inputs, dt)`. They use `ctx.rng` and never read the clock.
- Player-facing text lives in CSV: `content/strings/<module>.csv` for the platform, `content/<id>/strings.csv` for a game, with its keys prefixed by the upper-case game id.
- Commit `*.import` and `*.uid` files. Small commits with conventional messages.

`CLAUDE.md` has the full rules. It's written for AI coding agents, and it's accurate for people too.

## Working with an AI agent

You're welcome to. Point your agent at `CLAUDE.md`; its first section is for contributors like you. You answer for what it sends: run the gates yourself, read the diff, and don't send anything it claims to have tested unless you've seen the result. Say in your pull request that an agent helped.

## Questions and reports

- Bugs and ideas: [issues](https://github.com/shoedler/wattlands/issues).
- Anything that could hurt a rider, or a security problem: see [SECURITY.md](SECURITY.md) and report it privately.
- By taking part you agree to the [code of conduct](CODE_OF_CONDUCT.md).
- Contributions are MIT licensed, like the project.
