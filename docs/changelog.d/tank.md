# Changelog: tank

### Changed (Diesel Domestiques) v0.4.0

- The enemy is far away now. The screen splits: our tank, the near road and the bushes on one side, a long-lens view of the enemy at 800-2400 m on the other, with the range on a riveted seam between them. Shells really fly, 1.4 to 4 s, and lead and elevation matter. A small shell screen shows the arc with our shells and theirs in flight, and an incoming shell is the cue to sprint.
- New enemies, drawn to the tank's standard by a new generator with no generated images: real track runs and road wheels on suspension, turrets that traverse, guns that recoil, rivets, weathering and moonlight, a cold grey-green faction with cyan vision slits, burning wrecks, and a Behemoth with bogies you can break. Nothing comes from behind any more, and the dug-in guns are gone: gun lines are now holding actions, enemies on the move at long range.
- Recon cars and tankettes burst from the roadside bushes, drive away with their turrets firing back, and flee if you leave them. Only the Secondaries hit them. One that gets away costs nothing.
- Difficulty: Easy, Normal or Hard, set by the host. It changes enemy HP, damage, accuracy, counts, telegraph length and the repair rate, and never an effort number or your plan. On Normal and Hard a hull at 0 is TANK LOST: the crew is towed back and the stage restarts while the ride goes on. An S needs a ride with no losses. On Easy you break down instead and cannot lose. A rider in rescue, AFK or dropped keeps the hull at 1 HP on every level.
- Ambush: a new 15-minute session with the full warm-up, about 7 minutes of hard fights and the cool-down. It defaults to Hard: expect to lose the tank once or twice and still get a good workout.
- A sixth seat, Repairs, on the upper deck: a crank-driven rivet hammer and a patch press in their own copper light, ERG 55-70 %, which rebuild the hull while you stay in band. The HUD has a sixth card.
- Bots fill the empty seats and adapt to the humans: they load when the rack runs low, repair when the hull is low, take the Lights for a gunner and cover a rider who stopped. A human's move always wins, and a bot never changes a human's effort.
- Free roam follows the same rules: patrols far off, ambushes from the bushes, holding forces at the strongpoints, and a turn clears the field. The help overlay covers the new screen.

### Changed (Diesel Domestiques) v0.3.1

- No seat lock. Move to any empty seat at any time with the arrow keys and OK, on every seat; the move lands at once and your power works the new seat right away. On the Gun, target cycling moved to swap (R / LB); up/down still nudge the elevation.
- Your trainer follows your seat: a move between seats of the same mode changes its targets at once; a move between ERG and SIM switches at once if your last switch was 30 s or more ago, otherwise when the 30 s are up (BRIEF 4.5's spacing); the seat card shows "ERG in 12 s" meanwhile. Moving back cancels a waiting switch. The seat lock no longer comes back at a new stage.
- Automatic riders hold a seat at least 30 s (solo) or 60 s (in a crew) so they don't hop.
- Both searchlights burn only while the Lights seat is manned and powered; otherwise the rooms fall back to dim backup lighting with red emergency lamps. The headlight stays on.
- The gun's angle meter and the Secondaries' dial fade in and out instead of flashing.
- Heart rate: my numbers show your heart rate when a sensor is paired.

### Changed (Diesel Domestiques) v0.3.0

- One tank for every crew size: the reference landship rebuilt as pixel art, with five seats. Drive (the diesel, SIM on the terrain), Gun (the dynamo, ERG), Loader (the steam engine, SIM, fills a 3-round ready rack at about 7 s a shell), Lights (the arc generator, ERG; dark, the gun reaches only the headlight's range and misses more) and Secondaries (a new crank-driven belt feed, SIM flat: exactly 2 bow-gun rounds per pedal revolution). An empty seat does nothing. The Bulwark, Rampart, Citadel and Bastion, the gearbox lever and rotation are gone.
- Riders choose their seat: left/right picks an empty seat and confirm sits (on the Gun seat, swap opens the picker). A seat lock keeps every rider at least 60 s between trainer-mode changes; each move is a replan the platform ramps. Riders who never touch the controls, and a solo rider by default, are seated automatically: Drive, then the Loader and the Gun when a target comes, the Secondaries against light targets.
- Difficulty is the enemy count by crew size (a solo rider meets fewer enemies and a Behemoth with its bogies already wrecked); enemy HP is the same for every crew. A solo tank takes half damage and its rack is restocked at each checkpoint. Every telegraphed shot warns at least 6 s ahead (the Behemoth 8 s).
- The tank follows the ground: every road wheel rides its own suspension and the whole tank tilts on slopes, enemies too. The track runs, the diesel's pistons move with cadence, the turret shows the ready rack and the breech through two windows, both bow guns tilt in their armoured box. The main gun fires a big pixel blast with recoil, hull rock and shake; its smoke stays where the shot was fired.
- A bluer, greener forest night with little fenced bases at the depot, the gun lines and the free-roam strongpoints; no people outside the tank; the world's lamps draw behind the tank. Free-roam zones are forest variants and base clearings.
- The HUD's seat panel shows five live machine cards with ERG/SIM tags, EMPTY seats, YOU with the seat lock, the rack's shells and the Secondaries' rounds per minute. W' is now SPRINT, and the Secondaries get a small blue-white angle dial.

### Changed (Diesel Domestiques) v0.2.0

- Up to four riders. Four riders crew the Bastion: the Citadel plus an arc-generator room and a searchlight tower. The arc generator rider rides ERG at 65-80% FTP; the target rises with how often the bow guns fire. In band, the searchlights are lit and the main gun shoots straighter. A cadence collapse stalls the arc generator. With rotation on, every rider works every engine once.
- A new look built from Simon's reference image: a starry forest night at 960 x 540 art px, with a strong tilt-shift. Each plane is blurred once, and a light per-frame depth of field can be turned off with the rider's "miniature" option; it also switches itself off on slow machines. The tank is cut from the reference into four variants with x-ray engine rooms. The machines run on their riders' cadence and watts and show under, in and over band. Drawn crewmen work the diesel, shovel coal, carry shells, man the breech, the panels and the turret roof. Enemies and the Behemoth are new procedural sprites in the same style.
- The game draws its own HUD instead of the kit widgets:
  - your watts and cadence against their bands, with one instruction line;
  - a crew row with a live engine window per rider;
  - a mission plate, a hull plate and the Behemoth's bars;
  - tags in the world: SURGE TO EVADE with countdown pips, the speed tag, the halt line's distance plate and the gun's elevation arc.
  - It uses its own stencil fonts and an F1 help overlay.
- Surge to evade replaces the Ram. Some shots are telegraphed: a tank destroyer's glint (4 s), a heavy tank's muzzle glow (3 s), a light tank's flank shot (2.5 s) and the Behemoth's main gun (6 s). Hold a sprint (1.2 x FTP over 3 s) for 2 s inside the telegraph (3 s for the Behemoth) and the shot misses. The tank lurches when the diesel or the Bulwark evades; the boiler blows a smoke screen when the steam engine does. There is no button: pedaling is the input, so the Autopilot never evades.
- Every tank has two bow guns in its nose. They fire automatically at the nearest enemy 40-220 px ahead, powered by the arc generator, the dynamo's bank or the Bulwark's gearbox. They also clear wire and wrecks. The main gun now depresses to -12 degrees, so close targets can be hit.
- Enemies hold their own depth lanes, so no two overlap at a gun line, and the view draws them in the lanes the rules use. Wire and wrecks block the road until they are shot clear.
- Rebalanced on the simulation matrix for crews 1 to 4: gun-line make-up, enemy HP and guns, and the energy of the steam engine, the gearbox and the Rampart's hoist. A crew of 1 to 4 riders who hold their targets wins Ashfall Road on the Autopilot, every phase inside its target time.
- New sounds, all synthesized: the arc's crackle, the bow guns' rattle and crickets in the night.
- Free Roam (`roam_10`, `roam_20`, `roam_30`, `roam_45`, `roam_60`): a 5-minute drive-out, then one engine per rider for the whole session on a seeded 6 km valley of pine forest, lake shore, village, quarry and meadow, driven back and forth (the driver turns the tank around; it turns on its own at a road's end). Random patrols and dug-in strongpoints, crew points per kill and kilometre, time up with up to 5 minutes for a fight in progress, grades by points per minute. A map strip and a time, points and kills board replace the mission plates.
- The depot yard has a hangar, a gantry and a barrier; the road is lit under the tank; enemies stand on their own banks in depth, wrecks burn charred in the beams, and the turret turns to face the rear whole.

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
