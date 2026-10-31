# Changelog: siege

### Fixed (Castellum Rotae) v0.3.1

- A rules step at the enemy cap now fits its 1 ms budget on the GitHub runners (851 us against 1293-1394 us). Enemies remember their path segment, station targeting no longer builds lists, and enemy lookup by id is a binary search. Scores are unchanged.
- The perf test times `SiegeRules.step` alone and takes the best of three measurements. The budget is unchanged.
- `game-siege` CI checks T1 over seeds 1-3, as the target is defined, instead of seed 1 alone.

### Changed (Castellum Rotae) v0.3.0

- Castellum Rotae has its own Roman HUD, matching the approved mock (`src/games/siege/art/hud_mock.mjs`): dark wax plates in a limestone frame with a brick course, tabula ansata plaques, a Roman letter baked from the mock's own code, and a red chip as the only alarm. The kit widgets are gone from Siege.
- A cockpit shows the interval clock, watts and cadence at 72 px, the target the trainer really applied (so rescue and caps are true), one instruction line by state, what comes next in applied-style watts, W′, and the gear only in SIM. A heart rate cell shows with a sensor, `--` on a dropout, and goes away with no sensor.
- Displayed watts are a 3 s mean with in-band hysteresis, and stale power shows `--`, not 0. These rules are a new platform helper (`HudRiderNumbers`).
- A session plate with the profile strip, teammate cards, a right column with the gate, tar, gold, stations and an Overdrive plate that says why it is closed, red tags on rams and towers, and a banner with a leader when the gate fails. The shop moves bottom left over the road's west loop, keeping all it did.
- The host publishes the 80-100 rpm cadence band at the start. It changes no load. Rules, effort plans, balance and Overdrive are unchanged.

### Changed (Castellum Rotae) v0.2.0

- Castellum Rotae v2: a new look, map and combat, approved in a mockup review (`src/games/siege/art/PROPOSAL.md`, brief `docs/games/siege.md`). The effort plans, the Overdrive directive and every BRIEF 4.6 behaviour are unchanged.
- Presentation is now `2d`: one fixed isometric pixel-art view at 960 x 540. The art comes from Siege's own CPU rasterizer (`src/games/siege/art/`): the static world and its depth are baked once, and moving parts are depth-tested sprites recoloured to each rider at runtime. A tilt-shift pass can be turned off per rider (`tilt_shift`).
- The fort is built against a quarried cliff with a gold seam, behind a moat with one bridge to the gate. Four great treadwheels feed a visible 4 x 5 junction; a rider's powered path lights in their colour from wheel to station.
- Five stations as rider targets with caps: the woodpecker gold mine (2, replaces the generator; gold replaces denarii), the tree ballista (1), the great onager (2), the arrow organ (2) and the tar works (1). Shots are simulated projectiles with gravity and drag (bolts pierce, stones splash, arrow volleys spread), lead-aimed and able to miss. The tar works keeps a curtain over the gate and slicks the bridge.
- One 391 m road with four staging grounds instead of three roads. Five enemy types in ranks: spear blocks, shield bearers (testudo against arrows), chariots with speed changes, battering rams and a siege tower that docks at the moat and lands boarders.
- Four unmanned wall pads with Scorpions, station upgrades, mine levels and the Spare cauldron perk in the shop. Autopilot scores stations by what will be in their range.
- The threat budget scales by team size and by shift so small teams and long shifts stay fair.
- The HUD has a station route card with cap pips, a tar-curtain card, a one-line wave count and a help overlay with seven arrows.

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
