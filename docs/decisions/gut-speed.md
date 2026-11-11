# Decisions: gut-speed

## 2026-11-12: Tests that read the same whole session play it once

- **Decision:** where several tests of one script each played the same whole session and only read it, the script plays it once and every test reads the shared result. `TestGameSessionSuite.shared_session()` does this for the game session suites: the first call with a set of flags plays the session, every call gets a deep copy of its report, and its report and FIT files stay until `after_all`. Rules-level suites keep a per-script cache of played games (`_played`, `_session`, `_real_wave`) that no test changes. A test that changes what it plays (a seat move, more cool-down, an applied progress no other test reads) keeps its own run. Every test function stays, with the same assertions and tolerances.
- **Alternatives:** play everything once in `before_all` (its time drops out of the JUnit per-test times, which would hide the cost rather than cut it, and a single test run alone would still pay for all of it); share across scripts with a static cache (`strict` runs every script in one process, and a cache that outlives a script is the kind of cross-file state it exists to catch).
- **Reason:** `tools/gate fast` runs the whole GUT suite, and a handful of tests that replayed the same 30-minute mission were a large part of it.

## 2026-11-12: Tests that only repeated a pinned scenario or a matrix row are gone

- **Decision:** remove the tests that played the same session with the same rider and checked a subset of what another check already holds:
  - `test_workout_sims.gd`: every built-in session graded A or better (`tests/scenarios/workout/test_workout_sessions.gd` plays every built-in session with the same compliant rider and a bot and checks the grade, time in band, the warm-up limits on every tick and that no duration limit latches, so the VO2 latch test went too), and the sample .zwo plays (`tests/scenarios/workout/test_zwo_import.gd` plays it to the end inside its clamps).
  - `test_tank_session.gd`: a crew of 4 plays Ashfall Road with zero input (the tank matrix's `s1_c4_seed1` to `s1_c4_seed3` play exactly that and check the outcome, the 13 laps, the snapshot budget and T7, the arc rider's load pattern).
  - `test_tank_sessions.gd`: the score falls with compliance 100, 85 and 70 (the matrix's T5 over `s1_c3` and `s3_c3_c85`/`s3_c3_c70`, seeds 1 to 3).
- **Alternatives:** keep them on a shorter content (they would no longer check what their names say).
- **Reason:** the scenario tests run in the same gates; the matrix runs before a tank branch reports and at every checkpoint, with the BRIEF 4.6 checkers.
