# Changelog: tank

### Changed (Diesel Domestiques) v0.1.1

- New art in the brief's dark 2.5D diorama style, replacing the procedural placeholders:
  - All 61 sprites are generated with OpenAI GPT Image 2.5 through fal ($8.04 of a $10 cap) and pixelated into the 32-colour palette.
  - Load-time grading gives seamed, riveted grey-black steel, and the depth-of-field blur and haze is applied per plane.
  - The near planes are composed without mirroring: Poplar Road, Kettle Ford, Quarry Ridge, the depot yard and the foundry town.
  - Smoke banks are lit by distant fires.
  - The cutaway machinery is readable: steam cylinder and crosshead, pressure dial, brass shells, the Bulwark's lever and lit output, and a bus bar to the dynamo.
  - Seeded flame masses, ragged smoke rings, brass casings with a glint, and hit sparks that stay on the armour.
  - The picker card is the generated Citadel cutaway.
- An adversarial art critic reviewed every round against the brief's art direction: 3 style rounds and 6 scene rounds, ending with every criterion at 7 or more and no people, text, flags or icon-like marks.

### Added (Diesel Domestiques) v0.1.0

- Diesel Domestiques, a co-op tank game for 1-3 riders (BRIEF 3.6, `docs/games/tank.md`): the crew size picks the tank (Bulwark, Rampart, Citadel) and every rider pedals one engine of a pedal-powered super-heavy tank. The diesel drives (SIM, Ram sprints, ERG 90% while dug in at a gun line), the dynamo aims (ERG that climbs as its capacitor bank drains) and the steam engine loads (a SIM boiler grade that rises with pressure and drops to 0 at every latch). A solo rider gets the Bulwark, whose diesel does everything through a three-way gearbox with a Hoist.
- Ashfall Road: a 5-minute depot, three stages of Advance, gun line and checkpoint, then the Behemoth, then the platform's 3-minute cool-down (30 to 41 minutes, 12 FIT laps). Light tanks are short sprints, mediums sustained tempo, heavy tanks a 90% threshold block, the Behemoth a sprint-heavy finale. Plus a 130-second `drill` for end-to-end runs. Engines rotate at each checkpoint (lobby option, default on).
- Every load change goes through `ctx.directives` and the safety governor: ERG targets 50-100% FTP (bank updates of at most 10 points as three sub-steps, the depot ramp 50 to 65%), boiler and Hoist grades with their rise and drop rules, terrain at 2 Hz, cadence and power bands, three haptics (hit, Behemoth hit, Ram) only for SIM riders after the first 300 s, and `end_phase` once an objective is done. The first 300 s stay inside the warm-up limits and the platform ramps every ERG and SIM switch.
- Zero input: Autopilot plays rear traverses and obstacle shots; the defaults aim, fire, latch and drive; a rider who stops goes AFK after 10 s and their station runs on reserve. Rescue, stagger, overruns, breakdowns and a lost mission cost score, never the workout. Grades S to D, XP and five hull finishes (the garage that equips them is not built).
- 2D dark diorama at 640 x 360: parallax planes with blur and haze, cutaway engine rooms with glowing wall lamps, additive lights, pooled particles for shots, impacts and exhaust, a HUD around the kit widgets clear of the PANIC corner, and synthesized audio. The art is procedural placeholders (no fal run was made); `assets/tank/art.json` is ready for a real pass.
- Host-authoritative multiplayer: 10 Hz integer snapshots well under 4 KB, intents owned by the engine and limited to 5 per second, events in order, interpolated rendering, rejoin by snapshot.
- Tests: GUT unit and property tests (plans, directives, rules, combat, module, net, HUD, view, art, static checks, a stress test, the rules-step cost), the brief 4.2 simulation matrix with its checker (`tests/games/tank/sim/run_sims.sh`: compliant crews, zero riders, compliance sweeps, directive and trace rules, rescue, haptics off, determinism, a sprinting rider, client intents and a stopped rider), an e2e report check, CI (`.github/workflows/game-tank.yml`) and a real-trainer checklist (`src/games/tank/HARDWARE_TEST.md`).

### Known gaps (Diesel Domestiques)

- Not tested on a real trainer or against the real Strava API: the real-trainer checklist ends with the items only a human can judge (sprint gestures, audio mix, frame pacing on integrated graphics, network loss).
- Synthesized audio only. P1 content is not built: the garage and the hull finish picker, Viaduct Crossing, and two tanks in one lobby.
