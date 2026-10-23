# Changelog: siege

### Added (Generator Siege) v0.1.0

- Generator Siege, a co-op tower defense for 1-4 riders (BRIEF 3.6, `docs/games/siege.md`): your watts turn a treadwheel in the Roman hill fort Castellum Rotae and go to one target at a time, a tower (defense now) or the generator (denarii for the breaks). Bots fill empty wheels; every phase, the shop and the results work with zero input.
- Five shifts: `short` (default and zero input, 3 waves at 95%), `vo2` (6 x 2 min at 112%), `sweetspot` (2 x 15 min at 90%), `endurance` (one 45-minute wave at 70% with rushes) and a 2-minute `drill`. Each starts with a 5-minute warm-up wave (ERG 50% to 65%) and a build break. Waves and breaks are ERG; each rider's wave offset (-10 to +5 points) sets their own targets.
- Overdrive: a 30 s SIM sprint block (virtual gears, a 1.2 to 1.4 x FTP band on the gauge, routed output doubled at or above FTP) on `ability_1`, the HUD button or a surge at the prompt. It is Siege's only directive and follows the governor's rules for ERG and SIM switches.
- Three towers (Ballista, Scorpion bolt thrower, Caltrop thrower) with three upgrades each on eight pads, four enemy types (Raiders, Shield wall, Horsemen, Battering ram), three roads, the ram push, endurance rushes, the gate with its Breach, the break shop (build, upgrade, generator levels, Iron bands, repair, two team perks) on the pedal-scan list, and Autopilot routing and shopping.
- Score and grade S to D from the gate, Breaches and earnings, kJ-based XP, and four cosmetic unlocks (swallowtail pennant, walnut wheel, bronze chain trim, long banner).
- A procedural low-poly 3D miniature (wheels with workers, a bronze generator with a rolling watt counter, chains, enemy crowds, the gate), a HUD with a routing card, Overdrive button, teammate strip, rush strip and shop panel, and synthesized audio.
- Host-authoritative multiplayer with room codes: 10 Hz integer snapshots of at most 8 KB at the 150-enemy cap, intents at 5 per second per peer, client prediction of the local wheel and route.
- Tests: GUT unit, static, integration and perf tests, a simulation matrix (`tests/games/siege/sim/run_sims.sh`) with a report checker, an e2e report check, a 150-enemy stress scene, and a real-trainer checklist (`src/games/siege/HARDWARE_TEST.md`).

### Changed (Generator Siege)

- G2 balance pass. Bounties at 0.3x, threat budget 13, a 130 HP gate, slower rams (0.75 m/s), dearer towers (65 / 52 / 45), a 2.2 s Ballista and a 7-damage Scorpion: 1- and 2-rider teams no longer breach every wave, a full team scores an A instead of an S, and tower riding pays about half the generator.

### Known gaps (Generator Siege)

- Leaks per wave-minute differ by more than 30% across the shifts (tuning target T3); solo `endurance` is weak; the simulation check S10 fails on the SIM to ERG return label in the trace.
- Not tested on a real trainer, on integrated graphics at 1080p, or by ear. Not built from P1: Onager, gate cauldron, siege-tower boss, custom shifts, `.zwo` import and equipping cosmetics.
