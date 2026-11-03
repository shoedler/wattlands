# Wattlands: Torque Company game brief (v4)

Torque Company (game id `tank`) is one game module on the Wattlands platform: one to four riders crew a pedal-powered landship, one seat each of six, and bots can fill the seats nobody takes. The enemy stands far across a night valley, so the screen splits: our tank and the near road on one side, a long-lens view of the enemy on the other. The game has been through four versions of this brief. Where the versions differ, the newest wins, and `docs/decisions/tank.md` records each change with its reason. "BRIEF x.y" means a section of `docs/BRIEF.md`; this file is `docs/games/tank.md`. The game was called Diesel Domestiques until 2026-10-31. The id `tank`, the `Tank` class prefix and the paths kept the old name.

**The reference:** a 1088 × 608 image the owner made. "This is THE reference image. The game must look like this." Small tweaks are allowed so players can tell what they power. The file left the tree and stays in git history (`assets/tank/v2/source/reference.webp` at commit `0a3f1afb`). The owner's art direction, quoted from the prompt that made it:

> tank / landship from a fictional ww2 era, allied side, side profile, driving through a starry, extremely dark, blue/greenish-tinted summer night in the forest … warm headlights and searchlights and few, green and red, small position lights … strong tilt shift … many rivets and intricate details about little mechanisms, armament and creature comforts … dark brown paint, weathering … sections that allow a peek beneath the armor, showcasing the main drive diesel engine, the electric motor for turret traverse, the petrol engine for loading the shell and some more. Everything inside is just about enough illuminated by the incandescent lights inside the tank, giving an eery vibe … All the mechanisms allow the examiner of the image to imagine how they work, as they have a logical process that can be inferred from looking at the mechanisms in detail.

## How the design got here

- **v1:** four tanks by crew size, rotation of engines at checkpoints, the platform's kit HUD, a Ram.
- **v2:** the reference look as the art target, the game's own HUD, a fourth engine (the arc generator), bow guns, free roam. "Surge to evade" replaced the Ram: the legs are the input, not a button.
- **v3:** one tank for every crew size with seats the riders choose and change, a 3-round ready rack for the Loader, the rebuilt pixel-art tank on suspension, a forest world. Rotation went.
- **v4:** the far field and the split screen, difficulty and tank loss, a sixth seat (Repairs), bots and automatic seating, the Foundry Pact enemy art.
- **Since v4:** the display name, and the Secondaries as machine guns (6 rounds per pedal revolution, 2026-11-01).

## 0. Hard requirements

1. Build the game through the Game SDK only (BRIEF 3.6): a `GameModule` declared by `src/games/tank/game.json`, listed by `GameRegistry`, passing `tests/sdk/test_conformance.gd` with no change to platform tests.
2. Presentation `2d` at `pixel_base` [960, 540] with `pixel_flex` `{"min": [852, 480]}`: the reference's night diorama (section 3). The near rules work in rules px (8 per game metre) and the view scales them by 1.5 into art px. The far field has its own frame (2.4).
3. 1–4 human riders, with bots allowed to fill empty seats (`bots` is true). Every crew size rides the same tank. Play is host-authoritative through the relay with room codes (BRIEF 5).
4. Pedaling first: every crew size plays every content to the results with zero input (BRIEF 3.5).
5. Each seat has its own effort profile (2.3). Every plan and directive obeys BRIEF 4.6 and the switch rules of BRIEF 4.5. The governor outranks gameplay: change the design, never the governor.
6. Rides are saved and uploaded by the platform (BRIEF 3.8), with a lap per plan phase.
7. Original designs only, with no flags, insignia, national markings, text or numerals that could pass for real ones on vehicles, no logos, brands, real vehicle names or existing franchises. The reference's turret star and "A17" are left off. Small riders (about 20 art px tall) are drawn and animated in code inside the tank. No people outside it.
8. Testable headless with MockTrainer riders and Autopilot. Every gate in section 4 is green.
9. The game draws its own HUD with no platform kit widgets (3.6), the way Turbo Reel does.

## 1. Ground rules

- **Locks (BRIEF 1):**
  - Every process has `WATTLANDS_NO_HW_CONTROL=1` and `WATTLANDS_NO_NETWORK_INTEGRATIONS=1`.
  - Godot runs only through `tools/godot.sh` or `tools/godot.ps1`.
  - Run every non-art command with the art variables removed: `env -u FAL_KEY -u WATTLANDS_ALLOW_ART <cmd>`.
  - Never print, log or commit `FAL_KEY`.
  - `tools/godot.sh` exit 75 is a lock-wait timeout: retry.
- **Art sources:**
  - The game and its tools make no image-model request. The tank comes from the reference's own pixels, rebuilt as pixel art by scripts in the repository. Machines, riders, enemies, HUD, fonts and effects are drawn in code.
  - `docs/credits.d/tank.md` lists every source.
- **Commits** are small and conventional, prefixed `tank:`, except `platform:` and `docs:` commits.- **Owned paths:**
  - `src/games/tank/`, `content/tank/`, `assets/tank/`, `tests/games/tank/` and `.github/workflows/game-tank.yml`.
  - `docs/decisions/tank.md`, `docs/credits.d/tank.md` and `docs/changelog.d/tank.md`.
  - This file.
- **Platform changes:** only when a P0 item is blocked. Keep them minimal and additive, with tests, committed alone with the prefix `platform:` (CLAUDE.md). The game needed one: `DirectiveSink.split` ends a phase early and replans in the same tick, which seat moves use (2.2). It refuses a split that would break the 30 s switch spacing of BRIEF 4.5.
- **Release:** a version is done when it is merged into `main` and released on GitHub with the Windows build (section 5).

## 2. Game design

### 2.1 Fantasy and pillars

A dark brown, riveted landship of a fictional 1940s grinds through a starry blue-green summer night: forest roads, bases in clearings, and an enemy of field-grey factory armour far across the valley. Its hull is an x-ray cutaway. Each seat is one rider's room, and its machine visibly runs on that rider's cadence and power. Little riders work the rooms.

- **Your machine is your display.** Cadence drives its motion. Power against your target drives its heat, light, smoke and gauges (3.4). Your room lamp glows in your slot colour while you are in band.
- **Each seat feels different:**
  - the diesel is road tempo with sprints;
  - the dynamo is ERG that climbs as its capacitor bank drains;
  - the steam engine is a grade that rises with boiler pressure and resets with every shell stowed;
  - the arc generator is steady ERG tempo that lifts while an enemy stands in range;
  - the belt feed is a machine gun: six rounds a turn of the crank, so it fires as fast as you pedal;
  - the repair press is ERG that lifts while the hull is damaged.
- **Few decisions.** One decision every 10–30 s at most. Aiming, firing, latching and seating are automatic by default. Sprints are prompted: "Surge to evade" and "Surge to overpressure". Failure costs score or time, never the workout.

### 2.2 Players, seats and the tank

```json
{"id": "tank", "title": "Torque Company",
 "summary": "Crew a pedal-powered landship through a starry forest night. Six seats, one rider each, and the enemy far across the valley.",
 "version": "0.6.0", "min_players": 1, "max_players": 4, "bots": true, "presentation": "2d",
 "pixel_base": [960, 540], "pixel_flex": {"min": [852, 480]},
 "entry": "res://src/games/tank/tank_game.gd",
 "picker_image": "res://assets/tank/cards/picker_card.png",
 "contents": ["ashfall_road", "ambush_15", "roam_30", "roam_10", "roam_20", "roam_45", "roam_60", "drill"],
 "default_content": "ashfall_road", "e2e_content": "drill", "zero_input_content": "ashfall_road",
 "first_run_priority": -1,
 "options": [{"id": "difficulty", "type": "choice", "default": "auto", "choices": [auto, easy, normal, hard]}],
 "player_options": [{"id": "miniature", "type": "toggle", "default": true}],
 "content_cards": {"ashfall_road": {...featured}, "ambush_15": {...featured}, "roam_30": {...featured}, "roam_10": {...}, "roam_20": {...}, "roam_45": {...}, "roam_60": {...}, "drill": {...not featured}}}
```

The content cards use in-engine renders under `assets/tank/cards/` and `TANK_CARD_*` detail strings. `difficulty` is set by the host (2.4). `miniature` is the rider's own tilt-shift toggle (3.1).

**One tank, six seats.** Every crew size (1–4) rides the same tank, the reference landship rebuilt as pixel art. Each seat has a machine, a trainer mode and a job. An empty seat does nothing, and with at most 4 riders at least two seats are always empty.

| Seat | Engine id | Machine | Trainer | Job | Empty seat |
| --- | --- | --- | --- | --- | --- |
| Drive | `diesel` | diesel | SIM, terrain grade | moves the tank; at a holding action it digs the berm in SIM flat, and the berm absorbs hits | the tank stops |
| Gun | `dynamo` | dynamo | ERG, the bank pattern (55–100 %) | lays, chambers and fires the main gun; the bank pays for stabilizing and elevation | the gun does not fire |
| Loader | `steam` | steam | SIM flat plus boiler grade | builds shells into a ready rack of 3, about 7 s a shell at 250 W in band | no reloads |
| Lights | `arc` | arc generator | ERG 65–80 % (searchlight load) | in band the searchlights are lit: the gun reaches its full range at normal dispersion | the gun reaches less far (about 2300 m) with dispersion × 1.5 |
| Secondaries | `feed` | crank-driven twin belt feed | SIM flat | the two bow machine guns: 6 rounds per pedal revolution (540 a minute at 90 rpm), at near threats and barricades; power in band sets their slew speed | silent |
| Repairs | `repair` | rivet hammer and press | ERG 55–70 % (repair load) | rebuilds the hull per joule in band, only while it is below its maximum | no repairs |

- **Rooms, rear to front:** diesel, steam, dynamo, arc, repair (upper deck), feed.
- **Starting seats:** a crew of n starts on Drive, Gun, Loader, Lights (the first n). A solo rider is seated by the solo loop (2.5).
- **Moving seats:** any rider may move at once to an empty seat, or to a bot's seat, which the bot gives up. The HUD's picker is `<` `>` to pick, OK to sit, back to close. A move is refused only for a seat a human holds, for a rider on reserve and in the cool-down. There is no seat lock. The stations, the `seat` event, the HUD and the power follow in the same tick.
- **The trainer follows the seat** (directive pattern 9, 2.3). A move that keeps the mode splits the rider's phase at once. An ERG ↔ SIM move splits when the rider's last switch is 30 s old (BRIEF 4.5), or at the segment's end when the split's rest could not hold 30 s. Meanwhile the rider works the new seat from their own power and the seat card says "ERG in 12 s" or "ERG at stage end". Moving back cancels a waiting switch. Every split and replan passes the PlanValidator with no switch warning, and the platform ramps every ERG ↔ SIM switch (BRIEF 4.5).
- **Drops and AFK:** no join after the start. A dropped or AFK rider's seat runs on reserve (as if P_eff were 60 W, never in band) under Autopilot. If every rider is AFK or stopped, the host pauses the game.

### 2.3 Effort plan

`effort/tank_plan_builder.gd` builds one EffortPlan per rider. Mission segments:

| Segment | Kind | Length |
| --- | --- | --- |
| Depot | WARMUP | 300 s |
| Advance | WORK | open-ended, 180 s nominal (90–300 s) |
| Holding action | WORK | open-ended, 120 s nominal (60–180 s) |
| Checkpoint | RECOVERY | 60 s, ERG 50% for everyone |
| Boss | WORK | open-ended, 240 s nominal (120–360 s) |
| Cool-down | appended by the validator | |

Ashfall Road runs the depot, three stages of Advance, holding action and checkpoint, then the boss. The nominal mission is 30 min and at most 41 min. Ambush (2.9) is shorter. The rules read segments from `frame.phase` and call `end_phase` for every rider in one step once an objective is done and `min_s` has passed ("Regroup" until then). The platform cuts a phase at `max_s`; that is an overrun and costs score (an Advance tows the tank to the halt line, a holding force is barraged, the Behemoth withdraws). The ride itself never fails. Free roam has its own plan (2.10). The internal ids `gun_line`, `SEG_GUN_LINE` and `TankGunLineState` stay for the wire, the plans and the FIT; the UI says "Holding action".

| Seat | Depot (WARMUP) | Advance | Holding action | Boss | Checkpoint | Roam |
| --- | --- | --- | --- | --- | --- | --- |
| Drive | SIM `game`, terrain 0 … +2 % | SIM `game`, terrain −3 … +6 %; evade sprints | SIM flat (dig) | SIM flat; evade sprints | ERG 50 % | SIM `game`, valley grade −3 … +5 % |
| Gun | ERG 50 % → 65 % | ERG 55 %, `range_pct` [55, 100] (bank) | same | same | ERG 50 % | bank [55, 85] |
| Loader | SIM flat, boiler 3 % × pressure | SIM flat, boiler 8 % × min(pressure, 1); Overpressure and evade sprints | same | same | ERG 50 % | same |
| Lights | ERG 50 % → 65 % | ERG 65 %, `range_pct` [65, 80] (searchlight load) | same | same | ERG 50 % | same |
| Secondaries | SIM flat | SIM flat | SIM flat | SIM flat | ERG 50 % | SIM flat |
| Repairs | ERG 50 % → 65 % | ERG 55 %, `range_pct` [55, 70] (repair load) | same | same | ERG 50 % | same |

A seat move replans the rest of the rider's plan from these same tables. Difficulty never touches an effort number (2.4).

**The fight shapes the workout:**
- light tanks bring a telegraphed flank shot and short sprint prompts;
- mediums bring sustained tempo and the bank's drain;
- destroyers and heavies bring telegraphed shots to evade and long duels;
- the Behemoth is the sprint-heavy finale.

The encounter list is fixed in the mission file, so the PlanValidator checks the whole plan before the ride. Enemies never add, lengthen or harden a phase. A tank loss (2.4) changes no plan.

**In band** (glow, score, charging):

| Seat | In band when |
| --- | --- |
| Drive and Secondaries in SIM | 76–105% FTP; evade sprints count |
| Gun, Lights, Repairs (ERG) | power ≥ 95% of the applied target and cadence ≥ 60 |
| Loader, building | ≥ 90% FTP |
| Loader, idle (rack full) | cadence ≥ 50 |
| Depot and checkpoints | cadence ≥ 60 |

While the trainer waits for a seat move, an ERG seat on a SIM trainer is in band at ≥ 95% of the seat's planned target (× 0.85 while FTP is unverified) and cadence ≥ 60; a SIM seat on an ERG trainer uses the SIM band.

**Checks** (each tested, section 4):
- **4.6.1:**
  - Every target and range bound is 50–100% FTP, and nothing exceeds 105%.
  - The boss and every roam phase longer than 300 s stay under their 105% cap.
  - The schema still holds every ERG phase planned at 90% or more to 180 s, though no seat plans one now.
  - The unverified factor of 0.85 only lowers targets.
- **4.6.2:** a bank, arc or repair update moves ≤ 10 points, sent as three sub-steps 1 s apart (≤ 3.3% FTP/s).
- **4.6.3:** rescue arms in every ERG phase while the applied target is ≥ 60%.
- **4.6.6:** boiler 8% × the rider's difficulty setting ≤ +8%; terrain (−3 … +6%) × the same. The largest haptic is +3%.
- **4.6.8:** the depot stays at ERG 50–65% and SIM 0 … +3% before difficulty, with no haptics.
- **BRIEF 4.5:** per-rider ERG ↔ SIM switches are ≥ 30 s apart.

**Directive patterns** (`ctx.directives`, `source: "tank"`, sent only by `TankDirector`):
1. **Bank (Gun):** `{mode: ERG, target_pct: 55 + 45 × (1 − bank/100), reason: "bank"}` every 5 s in sub-steps, clamped to `range_pct` (roam: [55, 85]). None in the depot or checkpoints.
2. **Arc (Lights):** `{mode: ERG, target_pct: 65 + 15 × duty, reason: "arc"}` on the same schedule. `duty` is the share of the last 10 s in which an enemy stood in the main gun's range (0–1).
3. **Boiler (Loader):** `{mode: SIM, mode_grade: 8% × min(pressure, 1), reason: "boiler"}`, at most once a second, rising at most 0.5% a step; 0 at a stow and while the rack is full; 3% in WARMUP.
4. Retired (it belonged to a v1 tank's gearbox).
5. **Terrain:** `course_grade(peer, pct)` at 2 Hz in `grade_source: game` phases; 0 under a tow.
6. **Bands:** `cadence_band(peer, 60, 120)` at each segment start, and (50, 120) while the Loader idles; `power_band` 76–105% for Drive and Secondaries in WORK SIM.
7. **Haptics** (2.7).
8. **`end_phase`.**
9. **The trainer follows the seat** (2.2): `split` and `replan`.
10. **Repair (Repairs):** `{mode: ERG, target_pct: 55 + 15 × duty, reason: "repair"}` on the arc's schedule. `duty` is the share of the last 10 s in which the hull was below its maximum.

Nothing is sent in the cool-down.

**Sprints send nothing.** Evade and Overpressure sprints are the rider's own in the phase's SIM. They are unavailable in WARMUP phases and the first 300 s, and no sprint prompt shows to a rider in WARMUP or an ERG phase.

### 2.4 Rules and mechanics

Pure `step(state, inputs, dt)` classes at 0.05 s, using only `ctx.rng`, configured by parsed content dictionaries. Units: rules px (near), metres (far and game distance), seconds, P_eff watts.

**Two frames, no conversion in the rules.**

| Thing | Frame | Unit |
| --- | --- | --- |
| Hull, barricades, drill wrecks, tank traps, recon cars, tankettes, bow guns | near | rules px |
| Light, medium, destroyer, heavy, Behemoth | far | `range_m` from the hull's front |
| Far shells | far | range and height in metres |
| Near threats' rounds, the main gun at a barricade or drill wreck | near | px |

Far enemies pace the tank, so Advance lengths and terrain stand alone. Nothing spawns or moves behind the tank, and there are no stationary guns.

**Enemies** (the Foundry Pact, 3.5):

| Enemy | Behaviour |
| --- | --- |
| Light tank | Far, nearest of the far kinds. Weaves around its hold. Its first shot there is a telegraphed flank shot. Retires after a while with no credit |
| Medium tank | Far. Holds and shifts on a timer |
| Tank destroyer | Far, farthest, a casemate. Telegraphs each shot and shifts after it |
| Heavy tank | Far. Telegraphs, shifts on a timer, backs off in steps as it takes damage |
| Behemoth (boss) | Far. Three bogies, then the turret. Creeps in; each broken bogie pushes it back. Main gun every 35–45 s (25–35 s once only the turret stands), telegraphed |
| Recon car, tankette | Near. Burst from the roadside bushes, dash away with pauses, fire back while paused, then flee. Only the Secondaries hit them. One that gets away gives no reward and no penalty |

Far enemies enter in 10 s from just past their hold, fading out of the haze. A holding action is a force of far kinds on the move at long range, retiring and shifting. Its objective is every enemy of the force down; near threats run alongside by elapsed time. An Advance's objective is the halt line.

**Main gun.**
- Elevation runs −12 … +30°.
- Far shells fly at 560 m/s under 70 m/s² (real speed, gravity × 7, so the barrel visibly lays 5–16°): 800 m takes 1.43 s, 2200 m 4.06 s. `TankBallistics.far_lead` solves lead from the target's range rate.
- Auto-aim picks by priority and fires on target (never at a near threat).
- Dispersion widens on a low bank and × 1.5 in the dark (Lights seat empty or unlit). The shell lands where the error sends it: a direct hit inside the target's `hit_half_m`, else splash within `splash_m`, else a `splash` event.
- Near arcs stay for barricades and drill wrecks.
- Damage: light shell 14, heavy 35, Overpressure 70, against each enemy's armour factor.

**The shell's path.** Ours leaves the near panel as a tracer, flies on the shell screen and drops into the far panel. Theirs leaves the far panel, flies on the shell screen and comes in on the near panel: that is the telegraph to read.

**Loader.** The Loader in band builds one shell per 1750 J of P_eff into a ready rack of 3 (full at the start, and again when the crew leaves the depot). At 100% pressure the shell is stowed: a heavy shell, or a light one if latched from 40%. Inside the 5 s window after a stow the rider may surge (`over`) to take the shell back to the boiler and overpressure it (100 → 150% on 1300 J while the sprint rule holds, a double-damage shell). The Gun chambers the oldest shell in 1 s, then auto-aim lays again. A solo rider's rack is restocked to 3 at each checkpoint.

**Gun bank (Gun).** The bank fills in band (+1 per 180 J of P_eff) and drains for stabilizing (2.25 a second while a fight is on), elevation (0.5 per degree) and traverse (15 each). A low bank widens dispersion. The ERG target climbs as it drains (pattern 1). A rescue freezes the bank and the turret.

**Lights.** While the Lights rider is in band the searchlights are lit and the gun has its full range at normal dispersion. Empty or dark, the gun reaches only 2300 m with dispersion × 1.5. Rescue: the searchlights dim (toast "Arc generator stalled").

**Secondaries.** The Secondaries rider fires 6 rounds per pedal revolution (`TankFeedState.ROUNDS_PER_REV`; 540 a minute at 90 rpm), alternating the two bow guns, at the nearest near threat whose near edge is 4–200 px off the hull front, else at a barricade there. 0.375 damage a round. Power in band sets the slew speed (8 or 40°/s); a round hits within 3° of the target. Near threats and barricades are scaled to this rate: at 90 rpm a recon car (22.5 HP) takes about 6.7 s, a tankette (13.5 HP) and a barricade (36 rounds that hit) about 4 s. The bow guns never hit far enemies.

**Repairs.** The Repairs rider rebuilds 3 hull HP per kJ of P_eff in band (× the difficulty's repair rate), one patch per 4 HP, only while the hull is below its maximum. A crank-driven rivet hammer strikes once per revolution and a press closes on each patch.

**Hull and breakdown.** Hull HP is 150, and each checkpoint raises it by 30 and heals 30 (Ambush starts at 90 and adds 20). The berm (Drive, at a holding action) absorbs hits first: 250 J of P_eff a HP, up to 40 HP.

**Telegraphs.** A telegraphed shot warns before it flies:

| Shooter | Telegraph (before difficulty) |
| --- | --- |
| Light flank shot (first shot at its hold; 10 damage, 70%) | 6.5 s |
| Tank destroyer | 5 s |
| Heavy | 5 s |
| Behemoth main gun | 6 s |

The telegraph plus the shell's minimum flight is at least 6 s at Hard. Mediums fire without a telegraph.

**Surge to evade.**
- **Who sees the prompt:** during a telegraph, every peer shows the world tag "SURGE TO EVADE" over the shooter with countdown pips. The instruction line ("SURGE nnn+ W s") shows only to riders who can evade: in a SIM WORK phase of their own plan, past its first 300 s.
- **How the shot misses:** if any such rider holds the sprint rule (the last 3 s average ≥ 1.2 × FTP, BRIEF 3.5, raw W) for ≥ 2 s between the telegraph's start and the landing (≥ 3 s for the Behemoth), the shot misses. The shot is decided at landing, so a dead shooter's shell still resolves.
- **Events and results:** event `evade` `{e, ok}`. Results count evades.
- **No intent.** Autopilot never sprints, so a zero-input crew takes the hit.

**Crew scaling.** Enemy counts scale with crew size: 0.5, 0.7, 0.85 and 1.0 for 1–4 riders (rounded, at least 1), taken from each list in order, so each list puts first what a smaller crew must meet. A mission entry with `min_crew` is there only for crews of that size and up. Enemy HP is the same for every crew size. A crew takes a share of the damage: 0.62, 0.57, 0.74 and 0.74. A solo rider meets none of the missions' near threats or barricades that `min_crew` leaves out, a Behemoth with its bogies already wrecked, and a rack restocked at each checkpoint.

**Difficulty.** The lobby option `difficulty` is set by the host: `auto` (the mission's `difficulty_default`), `easy`, `normal` or `hard`. It multiplies enemy HP, damage, accuracy, counts, telegraph length and the repair rate, and sets whether a tank can be lost. It never touches an effort number, a plan or a governor input: the schema refuses any other key in a difficulty row, a static test finds no difficulty read under `effort/`, and the plans are identical at all three levels.

| | Easy | Normal | Hard |
| --- | --- | --- | --- |
| HP | × 0.6 | × 1 | × 1.25 |
| Damage | × 0.55 | × 1 | × 1.5 |
| Accuracy | × 0.75 | × 1 | × 1.2 |
| Count | × 0.6 | × 1 | × 1 |
| Telegraph | × 1.25 | × 1 | × 0.75 |
| Repair rate | × 1.5 | × 1 | × 0.7 |
| Hull at 0 | breakdown | TANK LOST | TANK LOST |

**TANK LOST.** The crew is towed back (no movement, no fire, nothing spawns, 8 s), then the stage restarts from its start with its enemies back and 70% of the hull. Rules only: same plan phase, same clock, no directive, no replan, no lap. Riders keep pedalling and the HUD says KEEP RIDING. `max_s` still cuts the phase, so a failed stage may be skipped when its time runs out. Each loss costs survival score and caps the grade at A. In free roam the field clears and the tank drives on, at the breakdown's points. A rider in rescue, AFK or dropped holds the hull at 1 HP on every difficulty (BRIEF 4.6.3), as do a won stage and every phase but WORK.

**Breakdown (Easy).** No movement or fire, damage ignored, until the mean P_eff of the manned seats has paid 5000 J; then the tank runs on 40 HP.

**Obstacles.** Wire, wrecks and tank traps stop the tank short until a heavy shell, three light shells or 36 bow-gun rounds clear them.

**Caps:** 16 enemies, 24 shells.

**Tuning targets:**
- **T1:** a compliant crew's phase times, grade and losses on each difficulty. On Ashfall Road a crew of two may hold a holding action up to 180 s, the 90% limit of the schema; every other crew 160 s.
- **T2:** the Gun's bank climbs during fights for crews 2–4.
- **T3:** shells per stage.
- **T4:** the solo loop drives and works each holding action.
- **T5:** the mean score falls strictly with rider compliance (100, 85, 70%).
- **T6:** telegraphs and duels.
- **T7:** the Lights' searchlight load.
- **T8:** near threats are killed or escape, none left unresolved.
- **T9:** no fire in checkpoints, and every tank loss lies in WORK and is followed by a restart.

Targets by difficulty, for a compliant crew: Easy wins with no losses and grade A or S; Normal usually wins with 0–1 losses and grades B or A (S with no losses); Hard shows 1–2 losses on most seeds and grades C to A, never S with a loss. A crew riding at 85% of compliance loses more tanks than a compliant one. The sim matrix checks these (S14–S17); `src/games/tank/README.md` lists the shortfalls that remain open. Hard Ambush is all but unwinnable for the Autopilot, which never sprints; it is tuned for riders who evade.

### 2.5 Autopilot, bots and automatic seating

**Autopilot.** A human counts as Autopilot until their first deliberate intent (`aim`, `target`, `fire`, `latch`, `turn` or `seat`); `over` never ends it, and neither does an intent flagged as Autopilot output. `local_intents` turns `surge` only into `over`. Autopilot:
- aims and fires the main gun;
- latches a shell when the window ends;
- seats the rider (below);
- in free roam, turns the tank at the map's ends (2.10).

It never sprints, never Overpressures and never changes effort targets.

**Automatic seating** covers Autopilot riders and humans who never sent a deliberate intent. At most once a second, never inside the minimum stay (30 s solo, 60 s in a crew), in a fight only for a move whose trainer follows at once, and never an ERG ↔ SIM move inside a warm-up. A crew's riders hold the most needed seats through a segment's opening, unless a near threat is alive or an Advance has nobody on Drive. The solo loop:
1. Drive while nothing is in reach (one stay off Drive per Advance).
2. The Loader until the rack is full, or straight to the Gun with 2 shells.
3. The Gun while it has shells and a target.
4. Repairs with the hull below 35% and nothing laid.
5. The Secondaries only with no round for the main gun.

**Bots.** `TankBots` seats bots around the humans. A bot reads their seats and how they are doing. It never holds a seat against a human and never causes an effort change for one: it acts on its own seat, on cover and on being evicted, and its trainer follows through the same seat plan. Enemy counts scale with the crew, bots included. A bot stays 30 s on a seat, moves only to an empty seat and, in a fight, only when its trainer follows at once.

| Situation | A bot goes to |
| --- | --- |
| Rack at 1 or less, human on the Gun, no human loading | Loader |
| Hull below 60%, more urgently below 35% | Repairs |
| Human on the Gun in band, a far target, no human on the Lights | Lights |
| A near threat alive, no human on the Secondaries | Secondaries |
| Human in rescue, or out of band 15 s on the Gun | Loader if the rack has room, else Lights |
| Human out of band 15 s on the Loader | Repairs, more urgently |
| Human on reserve 10 s on Drive, Gun or Loader (WORK only) | Swaps seats to cover, and gives the seat back the tick the human returns. The human's plan is untouched |

**Controls.**
- Gun: up and down lay the gun, swap (R / LB) cycles targets, OK fires.
- Loader: OK stows a light shell from 40%; ability 1 or a surge overpressures.
- Drive, in free roam: ability 1 (or OK) turns the tank.
- Every seat: `<` `>` opens the seat picker.

### 2.6 Multiplayer and network

Host-authoritative, 10 Hz full snapshots ≤ 4 KB at the caps with 4 riders, ordered events ≤ 10/s, client prediction of your own room.
- **Intents** (at most 5 a second per peer): `seat`, `aim`, `target`, `fire`, `latch`, `over`, `turn`. Each seat owns only its own: the Gun aims, targets and fires; the Loader latches and overpressures; Drive turns; every seat may ask to move.
- **Events:** `segment`, `shot`, `hit`, `kill`, `evade`, `splash`, `latch`, `breakdown`, `repaired`, `overrun`, `boss_phase`, `turn`, `time_up`, `seat`, `tank_lost`, `stage_restart`, `ambush`, `escaped`.
- **Per-peer prompts:** each peer raises its own rider's prompts from snapshots, events and local telemetry.
- **Telegraph timing:** the snapshot carries each telegraphing enemy's remaining time (and the boss's), so every peer's HUD counts down.

### 2.7 Haptics

| Event | Receivers | `haptic` | `duration_s` | `reason` |
| --- | --- | --- | --- | --- |
| Hit of ≥ 4 damage (read before the difficulty) | every rider in SIM | 2.0 | 1.5 | `hit` |
| Behemoth main-gun hit | every rider in SIM | 3.0 | 2.0 | `boss_hit` |

Never in WARMUP, the first 300 s or the cool-down, never to an ERG rider, never to a rider who opted out, never to a rider on reserve, and at least 15 s apart per receiver.

### 2.8 Results and progression

**Missions:**
- **Score** = 1000 × (0.3 band + 0.2 accuracy + 0.3 objectives + 0.2 survival). Accuracy is the main gun's alone. Survival falls with breakdowns and tank losses. Weights and cut-offs are in `scoring.json`.
- **Grade:** S ≥ 900, A ≥ 800, B ≥ 650, C ≥ 500, else D.
- **Rewards:** XP = kJ / 10 plus a grade bonus (S 60, A 40, B 25, C 10). Hull finishes unlock into `ctx.progress`: one for finishing, three by grade (B, A, S), and a machinery finish for killing the Behemoth with no breakdown and no loss. They cannot yet be equipped or seen: the garage is not built.
- **Results page:** per-rider stats and team values, with evades (tried and successful), bow-gun hits and tank losses.

**Free roam:**
- **Score:** team points (2.10), kills by type, distance, evades, breakdowns.
- **Grade:** by points per minute of WORK time: S ≥ 22.5, A ≥ 17.5, B ≥ 12.5, C ≥ 7.5, else D.
- **Outcome:** `finished("time_up")`.
- **Rewards:** XP = round(kJ / 10) plus the grade bonus. Unlocks as for missions, minus the Behemoth one.
- **Strava `ride_tag`:** "Free Roam N min".

### 2.9 Content

- **Missions:**
  - `ashfall_road` (default, zero-input): 30 min nominal, 41 at most. Normal by default.
  - `ambush_15` (featured): depot 300 s, one Advance (80–160 s), one holding action (60–120 s), a checkpoint, the Behemoth (100–190 s), cool-down 180 s. 15 min nominal. Hard by default. It starts short of plates (hull 90, 20 per checkpoint).
  - `drill` (e2e): 130 s inside the warm-up limits (depot 30 s, skirmish 70 s, checkpoint 30 s); every seat rides ERG 50 → 55% with `range_pct` [55, 65] or SIM; at most one mode switch per rider; no haptics.
- **Free roam:** `roam_10`, `roam_20`, `roam_30` (featured), `roam_45`, `roam_60` (2.10).
- **Files:** `tanks.json` (the one tank), `stations.json`, `enemies.json`, `missions/*.json` (`kind` "mission" or "roam"), `roam/valley.json` (the map), `scoring.json`, `cosmetics.json` and `strings.csv` (`TANK_*`), all validated at load by `TankContentSchema`, which also holds every effort number to BRIEF 4.6 (a bad value is a load error).

### 2.10 Free roam

**Map:** one long seeded valley road, about 6 km, built at the session start from `ctx.rng` and `content/tank/roam/valley.json`, and carried in the snapshot so clients rebuild it.
- **Zones:** pine forest at both ends, then a fir hollow, a forest camp, a lumber yard and a birch glade once each in a seeded order, each with its own terrain (−3 … +5%) and backdrop. The zone ids `lake`, `village`, `quarry` and `meadow` stay in the wire and the map.
- **The tank drives back and forth.** At either end the road stops at a turning place. A `turn` intent flips the travel direction anywhere (the Drive rider only, 30 s cooldown). Autopilot turns at the ends after 3 s, and the crew turns on its own after 12 s when a hand-playing driver does not, so a session never stalls.
- **A turn:** an 8 s stop. At its midpoint the rules mirror the frame and clear everything that moves, with no credit, so nothing is ever behind the tank. The view mirrors the tank behind a dust cloud; driving west the near stage draws mirrored and the far panel lands on the left.
- **No rotation:** each rider keeps the seat they choose; seats can change any time (2.2).

**Patrols:** seeded patrols every 90–110 s of WORK time, always ahead in the travel direction, scaled by crew and difficulty.

| Patrol | Weight |
| --- | --- |
| A light tank | 45% |
| A medium | 30% |
| A tank destroyer | 15% |
| A heavy (only after 10 min of WORK, at most one at a time) | 10% |
| A recon car, with a tankette at times, from the bushes | 25% |

- At most 6 enemies alive. Patrols use the mission rules (holds, telegraphs, evade, near threats).
- Strongpoints are holding forces of one heavy at seeded spots in the camp, the yard and the forest (at least 900 m apart, 700 m from the ends). They come onto the field within 500 m ahead and back 10 min after they fall.
- The tank halts ("Engage") while a strongpoint stands or a heavy holds within 2000 m. Otherwise it drives on.

**Effort plan per rider:**

| Phase | Kind | Length |
| --- | --- | --- |
| Drive-out | WARMUP | 300 s: the depot's targets and models, no enemies |
| Roam | WORK, open-ended | `min_s` = minutes × 60 − 300, `max_s` = `min_s` + 300 |

Each seat's roam row is in 2.3. The roam phase is over 300 s, so the 105% cap applies, and every bound is ≤ 85%.

**Time up** at `min_s`: no new patrols. A fight in progress (a far enemy within 2200 m, or a near threat) may finish, up to `max_s`. Then `end_phase` for everyone in one step, the cool-down, and `finished("time_up")`.

**Points:**

| Kill | Points |
| --- | --- |
| Recon car | 8 |
| Tankette | 6 |
| Light | 10 |
| Medium | 25 |
| Destroyer | 30 |
| Heavy | 60 |

- Evade +5; breakdown −40 (a lost tank costs the same); every full kilometre +2.
- Points are the crew's.

**HUD:** the map strip across the top (zones in profile, the tank, patrols, strongpoints), and a board with time left, points and kills (3.6).

## 3. Presentation

### 3.1 Look and resolution

The reference, at 960 × 540 art px (2× at 1080p, 4× at 4K, nearest filtering). Through `pixel_flex` (min 852 × 480), wider or narrower windows show more world. Rules px × 1.5 = art px. Nothing important sits only at the far edges, and the HUD rects use the SDK's anchoring.

**World:** the road runs through a pine forest at night, bluer and greener than the reference, with moderate tilt-shift. The road and tank sit low (ground line 385 art px), with a soft verge between the road and the foreground blur. Little bases (a fenced clearing with a bunker, lamp, crates and a barrier) stand at the depot and at free-roam strongpoints; a holding force's base stands in the far panel. Backdrops: `forest`, `forest_firs`, `forest_birches` and `base`. No people outside the tank.

**Split screen** (`TankFarMap`): at 960 wide, the near panel is 622 px, an 8 px riveted seam carries the range plate, and the far panel is 330 px. The far panel is a SubViewport with its own parallax, light and haze, and never runs the depth of field. A small shell screen in the far panel's top shows shells in flight. The tank's scale and place do not depend on the far panel and it stays whole.

**Tilt-shift:**
- each plane is blurred once at load;
- a light per-frame depth-of-field pass on the near panel softens moving things outside the road band (smoke, shells);
- the per-frame pass is a rider-facing setting (`player_options` toggle `miniature`, default on) and switches itself off if the frame time stays above 16.7 ms for 5 s.

**Light:**
- additive glows and volumetric cones for the headlight and the searchlights;
- warm incandescent room lamps and amber lamps;
- cold blue-white arcs (dynamo, arc generator);
- small green and red position lights;
- fire and muzzle flashes that light the scene for a few frames.

Lights are the only near-saturated pixels. The world's lights draw on their own layer behind the tank. The tank's lights:
- the headlight, always on;
- the turret searchlight, forward and about 11° down, and the rear searchlight, aft and about 13° down: both on while the Lights seat is manned and powered, with a 0.4 s fade and a 2 s hold, and a dim standby lens glow while off. An empty seat, a breakdown or a stalled arc puts them out at once;
- the room lamps. Unpowered, the rooms fade over 0.5 s to backup lighting: a dim multiply layer and one red emergency lamp per room;
- the position lights.

### 3.2 The tank

- **Base:** the reference landship rebuilt as pixel art (475 × 216 art px, 63 colours), baked once from the generators in `assets/tank/v3/tools_src/` into `assets/tank/v3/` with its manifest `kit.json`. The hitboxes, trunnion, muzzle and bow-gun muzzles come from the drawn tank (`r6_hitbox.json`, art px / 1.5).
- **Live parts, drawn each frame:**
  - the track and the road wheels on per-wheel suspension (`TankSuspension`);
  - the whole tank rotated as one sprite to fit the terrain (nearest filtering), bobbing on its springs;
  - the main gun with recoil, and the bow guns tilting in their armoured box;
  - each seat's lit room with its machine and rider turning on that rider's cadence, and a bare saddle and still crank on an empty seat;
  - the turret's two windows: the ready rack with its manipulator, and the breech with its rammer, following the rules' rack and loader state.
- **Terrain relief:** the view follows the rules' terrain with a height profile plus small seeded cosmetic bumps.
- **Firing:**
  - the main-gun blast: star flash, brake jets, fireball, smoke, dust, pebbles;
  - 11 px recoil, a 2° hull rock, a short screen shake and a scene flash;
  - the bow guns' per-round flashes, tracers and casings.
- **Rooms:** each seat's room has a small enamel plaque with a lamp in the rider's slot colour. The warm room glow is lit by in band.
- **Running gear:** wheels and track links move with tank speed. Hits shake the hull. A breakdown kills the lamps.

### 3.3 Riders

Riders are about 20 art px tall, procedural, and sit in each manned room working that seat's machine: pedalling, shovelling, loading, working the panel. Their poses follow the state. They never carry text or insignia.

### 3.4 Machines in sync with the riders

One machine per seat: `view/tank_mech.gd` (`TankMech`) over one class per machine (`TankMechDiesel` to `TankMechRepair`), pure Image painters. They paint the room overlay in the world and the machine card on the HUD.

- **Phase:** `phase` is the integral of rpm / 60 per second times a gear ratio per machine. It runs from local telemetry for your own room (client prediction) and from snapshots for the others.
- **Power:** `power` = watts / the rider's target.
  - Under band: dim, sooty, needles low.
  - In band: warm and steady, the lamp in the slot colour.
  - Over band: shaking, red needles, vapour, overflowing jars, the safety valve blowing.
- **Stopped:** at 0 rpm everything stands still.
- **Cost:** painting is about 1 ms per machine per frame, so in-world overlays repaint at most at 30 Hz, at most two a frame.

### 3.5 Enemies, props and effects

- **The Foundry Pact.** The enemy is one faction in our tank's hand on the opposite side: the same 1 px outline, plate-edge rule and rivet pixel, but ours is patched and open and theirs is sealed factory slab. Field grey with bands of dark yellow, grime, a mud line, welded seams, flat decks, long guns, stowage, no windows. Hatches are shut: warmth lives only in vents, the exhaust and the Behemoth's furnace, so nothing mimics our lit rooms. Slits are the cold foe signal. They are drawn by `assets/tank/v4/tools_src/` and baked into one atlas (`assets/tank/v4/enemies.json`).
- **Marks:** the Pact's mark is an invented hollow diamond. Numbers use only 0, 1 and 8, drawn to read the same mirrored (a turret's traverse and a flip mirror them), and a test refuses any that could read as a known number code or a real unit's number in either direction (`tests/games/tank/art/test_tank_v4_pact.gd`).
- **Silhouettes:** low wedge lights, tall slab mediums, long heavies, turretless destroyers, the multi-bogie Behemoth, and the small recon car and tankette.
- **Wrecks and props:** far wrecks dim and burn. Near wrecks age on sim time. The halt line is concrete teeth with a post and a hooded amber lamp.
- **Particles:**
  - muzzle flashes, smoke rings, casings, tracers and impacts;
  - the diesel exhaust by watts;
  - steam plumes and the safety valve;
  - dynamo sparks and the arc ladder;
  - the evade lurch and smoke screen;
  - dust and mud at tank speed.

  They come from pooled emitters with caps, use cosmetic randomness from the view's own RNG, and never feed the rules.

### 3.6 HUD, the game's own

No kit widgets: `hud_spec()` adds the game's own Controls with `add_control(control, Rect2i)` in art px of the 960 × 540 base and sets `shows_power = true`. The toasts and banners are placed and themed through `spec.palette`. F1 help has eight entries (nine in free roam), and the platform shows it once on a rider's first session.

**Look:**
- riveted dark-iron plates, panel `#17140f`, a 1 px brass frame `#8a6a3a` with a darker inner line and corner rivets;
- text `#e8dcc0` and dim `#a3937a`, amber accent `#e3a24a`, bar tracks `#3a3128`, red over `#c4553c`;
- rider identity only in slot colours;
- own bitmap fonts: `tank_stencil_5x7`, `tank_stencil_5x9` (rider-facing text cap ≥ 9 art px) and `tank_digits_14x24` (key numbers 24 art px tall, 48 px at 1080p), drawn procedurally by `TankHudFont`.

**Layout** (the bottom-right 200 × 60 stays clear):

| Area | Contents |
| --- | --- |
| Bottom left, my numbers | big watts with %FTP and a gauge against the band, coloured under/in/over; big cadence with its band gauge; one instruction line: HOLD 152–210 W, SPIN 60+ RPM, SURGE 240+ W 0:04, LATCH, RESERVE; SPRINT and the virtual gear (SIM) as small bars; the seat's name; your heart rate when a strap is connected. All follow your seat |
| Bottom middle, seat row | six live machine cards (Drive, Gun, Loader, Lights, Secondaries, Repairs), each with a live machine window, the rider's name in their slot colour, watts, an in-band strip and a tiny ERG or SIM tag. Empty seats are dark and marked EMPTY; bot seats say BOT. Your card carries YOU, the hint plate "< > seat  OK sit" and the switch to come ("ERG in 12 s"). Rack pips show on the Gun and Loader cards, rounds a minute on the Secondaries card and the repair rate on Repairs |
| Top left | the mission plate: stage name, stage clock, a compact stage strip, the objective, a difficulty tag and losses; in free roam, the map strip across the top |
| Top right | the hull plate (HP bar and number), kills; the Behemoth's bars under it; in free roam, the time left, points and kills board |

**In the world, not in panels:**
- the speed tag on the road behind the tank;
- the halt line's post with its distance plate, and the range plate on the seam;
- SURGE TO EVADE over a telegraphing shooter with countdown pips;
- the gun's elevation as a thin arc at the turret while the gunner aims, and a small blue-white dial for the bow guns while the Secondaries are manned (both fade in and out);
- the turn marker at the map's ends.

**Toasts and banners:** toasts sit under the mission plate, banners in the centre, and both carry the prompts ("Surge to overpressure", "Dynamo stalled", "Arc generator stalled", "Turn around"). TANK LOST and KEEP RIDING sit above the banners.

### 3.7 Audio

Every sound is rendered from the recipes in the repository (`assets/tank/audio/audio.json`, `tools/audio`, `docs/AUDIO_PIPELINE.md`). There are no third-party samples. `TankAudio` only maps state to parameters and events to cues.
- **Each seat, 1:1 with its crank:** the machine's picture and sound read the same phase, so they cannot drift. Your strokes are never thinned. Other riders' machines play 10 dB under yours, without their small details. A seat that stops, stops dead.
- **The machines:** the diesel's rumble by cadence with a turbo whistle by watts, the dynamo's whine and jars, the steam chuff and hiss, the arc's warm low thrum and relay tock (nothing it plays has much above 2 kHz, since a rider may hear it for an hour), the belt feed's machine-gun rattle, the repair hammer and press.
- **The gun and the far fight:** the main gun, shells in flight, casings, landings and kills heard after the flash at twice real sound speed.
- **Near threats** are heard before they are seen: a burst from the bushes, a small high engine, a sharp crack.
- **The track,** locked to the distance drawn.
- **The night:** wind in the pines and crickets, frogs, an owl, a far battle that stays out of the depot and the cool-down.

## 4. Testing and gates

Unit tests (GUT, `tests/games/tank/`) cover every rule and number in 2.2–2.10, including:
- plans for crews 1–4 × content × FTP {80, 200, 400} × verified/unverified, plus `drill` and every roam length;
- seat moves and the trainer following them (split, replan, waiting switches, the PlanValidator with no warning);
- the bank, arc, repair and boiler patterns and their sub-steps;
- evade (every telegraph type, the SIM-only rule, the first 300 s, ERG riders);
- far ballistics and the aim solver, the near field, the bow guns (6 rounds a revolution, the times to kill);
- difficulty (identical plans at every level) and tank loss, including the rescue shield;
- bots and automatic seating;
- the roam map generation (seeded, deterministic), patrols, the turn, time up and overtime, and roam points;
- snapshots ≤ 4 KB at the caps with 4 riders;
- intent ownership;
- every view and the HUD's controls built headless from fixtures, for crews 1–4 in mission and roam;
- the enemy art (the palette, the marks, the number codes);
- no missing string keys.

**Static tests:**
- no trainer-path references;
- no wall clock or global RNG in `rules/`, `effort/` or `combat/`;
- no difficulty read under `effort/`;
- no kit-widget kinds in `hud/`.

**Simulation matrix** (`bash tests/games/tank/sim/run_sims.sh`, `node tests/games/tank/sim/check_sims.mjs build/tank/sims`):

| Scenario | Coverage |
| --- | --- |
| S1 | compliant crews 1–4: T1–T9 |
| S2 | zero riders: the shared pause, a 10 W crew overruns every stage |
| S3 | compliance 100 / 85 / 70%: T5 |
| S4 | every directive, plan and trace rule of BRIEF 4.5 and 4.6, on every content and crew |
| S5, S10 | rescue and AFK; a client's intents applied by the host |
| S6, S7 | haptics off; the same seed twice is identical |
| S8 | enemy counts × 3: at most 16 enemies, snapshots under 4 KB |
| S9 | a scripted sprinter evades |
| S11, S12 | free roam: time up, laps, nothing behind, grade; the zero crew |
| S13 | seat switching: every move's trainer follows within 30 s |
| S14–S17 | the difficulty targets (Easy, Hard, Ambush, a crew at 85% and 70%) |
| S18 | bots, 1 + 3 and 2 + 2: nothing refused, bots act only through their seats |

**Gates (all must pass):**
1. Tank unit and static tests;
2. `check_scripts`, gdlint and gdformat;
3. SDK conformance at 1 and 4 riders, with bots;
4. the simulation matrix;
5. `tools/fit_check` on every FIT the sims wrote;
6. `node tools/e2e/run.mjs --games=tank`;
7. the full `tools/run_tests` at or above the green-count floor.

**Screenshots:** `tools/screenshot` frames of crews 1, 3 and 4 in the depot, an Advance, a holding action, the boss and free roam, compared against the reference.

**Frame cost:** the gate is relative. The split-screen view may cost about what the older single-screen view did, with no more draw calls; the per-frame depth-of-field auto-off (3.1) protects slow machines.

## 5. Definition of Done

- **Reachable:** every item in 2.2–2.10 is implemented, reachable from the game picker and tested. Every gate in section 4 is green, with nothing weakened.
- **Zero input:** a solo rider plays Ashfall Road and `roam_10` to the results with zero input. Crews of 2–4 play joined by code, and the e2e run passes.
- **Safety:** every plan passes the PlanValidator, and every directive is clamped and matches 2.3 or 2.7. No Tank code reaches the trainer except through `ctx.directives`.
- **Look:** the game looks like the reference, judged on real rendered frames, not on fixtures alone.
- **Docs:** `src/games/tank/README.md`, `HARDWARE_TEST.md`, `docs/decisions/tank.md`, `docs/credits.d/tank.md` and `docs/changelog.d/tank.md` are current.
- **Released:** merged into `main` and published as a GitHub release with the Windows build (zip).
