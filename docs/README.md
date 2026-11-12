# Docs

A map of this folder. Live docs first, then the history.

## Live docs

These describe what `main` does. If one is wrong, that is a bug: fix the doc.

- `ARCHITECTURE.md`: the layers (app shell, GameHost, games, trainer stack), time, sessions and multiplayer.
- `GAME_SDK.md`: how to write a game. The contract between a game and the platform, with worked examples from `_template` and Workout.
- `PROTOCOL.md`: the network protocol between the host, the clients and the relay.
- `TRAINER.md`: Bluetooth FTMS, the trainer stack and the safety governor, with every constant.
- `AUDIO_PIPELINE.md`: how game audio is rendered from recipes, and the scorecard that checks it.
- `ART_PIPELINE.md`: the optional 2D art tool (image service plus pixelation).
- `HARDWARE_TEST_PLAN.md`: the checklist for a pass with a real trainer and a real Strava account. Each game also has a `HARDWARE_TEST.md` in `src/games/<id>/`.
- `DEPENDENCIES.md`: every third-party dependency, with version, license and hashes. The records are in `deps.d/`; `THIRD_PARTY_NOTICES.txt` ships with the Windows build.
- `BACKLOG.md`: ideas not built and known gaps.
- `PERFORMANCE.md`: where gate and sim time goes, what a gate should cost, and the hot spots that were found and left alone. Read it when runs get slow.
- `DESIGN.md`: the rider's view of the platform: profile, scaling, input, safety, and the numbers behind them.

## Original briefs (frozen)

Kept as written. They set out the plan, so parts are out of date. The code and the live docs win.

- `BRIEF.md`: the platform brief.
- `games/`: one brief per game (`siege.md`, `tank.md`, `fishing.md`).
- `concept/`: concept images and notes from before the games were built.
- `research.md`: the research behind the brief.

## History

Useful when you want to know why something is the way it is.

- `DECISIONS.md` and `decisions/`: the decision log. Each entry has a date, the decision, the alternatives and the reason. `decisions/<id>.md` holds one module's or game's entries; `DECISIONS.md` merges the platform ones. Entries are never rewritten, so a later entry can overrule an earlier one.
- `OWNERSHIP.md`: who owns which path (section 1, still used by `tools/gate check`), plus the inventory of what the game briefs asked of the platform (sections 2 to 4, kept for their IDs).
- `changelog.d/` and `credits.d/`: fragments merged into `CHANGELOG.md` and `CREDITS.md` at each release. Leave them alone unless you are releasing.

## Reading old comments

Comments and docs across the repo cite section numbers and IDs. They all point into the files above.

- `BRIEF 4.6` is section 4.6 of `BRIEF.md`: the safety governor. It outranks every other rule. `BRIEF 7` is the list of test assertions.
- `S4`, `T2.6`, `F3` are sections of the Siege, Tank and Fishing briefs in `games/`. `B x.y` is a section of the platform brief.
- `W0` to `W4` are the phases of the first build: W0 foundation and contracts, W1 the parallel module work, W2 integration, W3 review, W4 fixes. `W4r2` is the second fix round.
- IDs such as `GM4`, `SH2`, `C36`, `TL5` and `ART7` are rows of the inventory in `OWNERSHIP.md`. Section 2 holds rows with prefixes such as `GM`, `SH`, `CTX`, `REG`, `NET`, `AU`, `TL` and `ART` (what the game briefs needed: game rules, shared helpers, the context, the registry, network, audio, tooling, art). Section 3 holds the `C` rows, where a brief and the platform disagreed.
- IDs such as `NET-1`, `SAF-7` and `ftms-ble-3` are findings from the W3 review. The fix for each is in the decision log.
- `lead` is the maintainer who merges to `main`.
- `P0`, `P1` and `P2` are priorities in the brief: must build, should build, and design notes only.
