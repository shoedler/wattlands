# Decisions: cleanup c8

## 2026-10-31: CI goes from 20 workflows to 7

- **Decision (the lead's ruling):** keep `lead.yml`, `game-{fishing,siege,tank,workout}.yml` and `relay.yml`, add `trainer-bridge.yml`, and delete the 14 workflows named after W1 agents, `ble.yml` among them. `lead.yml` gains `node tools/fit_check/check.mjs build/rides_test --expect-laps=5` right after `tools/run_tests`.
- **BRIEF 7.9:** it asks for "one workflow per owner" that together run unit, static, conformance, simulation, rides, relay, mock fal and end-to-end tests. `lead.yml` runs all of those through `tools/run_tests` on every push. The owners are now the lead, each game, the relay and the bridge, and each has a workflow. BRIEF itself is not edited.
- **Checked one by one, so no coverage goes:** every step of the 14 is a GUT directory, a Node suite or `check_scripts`, and `tools/run_tests` runs them all, with these exceptions, which stay: the Python bridge suite (`tools/run_tests` never runs it, so it moves to `trainer-bridge.yml` with `ble.yml`'s `addons/wattlands/trainer/ble/**` trigger kept) and the lap count from `rides.yml` (the `fit` step checks the same folder without `--expect-laps`, so it moves to `lead.yml`). `relay.yml` stays for the only `docker build` of the relay.
- **Alternatives:** keep the 14 (each repeats a part of `lead.yml`, under the name of an agent that no longer exists); one workflow for everything (the game subsets and the Docker build would have to run on every push).
- **Reason:** the owner asked for a more maintainable codebase, and 14 of the 20 repeat what `lead.yml` already runs.
- **Cost:** a push no longer gets a quick red from one module's workflow on GitHub, only `lead.yml`'s full run and the game's subset. `tools/gate fast` gives that answer locally.

## 2026-10-31: the games' lexer and sim helpers move, and only they do

- **Decision:** `lex` moves byte-identical from the Tank and Siege static suites to `TestGdLex` in `tests/lib/gd_lex.gd`. `result` and `pick` move from the Tank and Siege `check_sims.mjs` to `tools/lib/sim_report.mjs`, and `tools/gate check` follows the import to their pins. Each static suite still proves the lexer and its scans on bad snippets.
- **Left where they are:** `test_no_bypass.gd`'s own `lex` (arch tests are pinned), and in `check_sims.mjs` the pinned functions and the one-line `skip`, which the spec does not move. The suites' `files`, `read`, `first_name` and `hit` are not moved either, since the spec's row names only `lex`; the lead can add them to `TestGdLex` later.
- **Alternatives:** keep the copies (a fix to one scanner could miss the other, and these scans are the games' no-trainer-bypass check); a delegate named `lex` in each suite (a second name for one function).
- **Reason:** a third game's static suite should not need a third lexer. This touches no BRIEF 4.6 path, threshold or BRIEF 7 assertion, and the test count does not change.
