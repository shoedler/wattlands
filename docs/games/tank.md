# Wattlands: Diesel Domestiques game brief (v2)

Diesel Domestiques (game id `tank`) is one game module on the Wattlands platform: one to four riders crew a pedal-powered landship, one engine each. v1 (`tank-v0.1.0`, `tank-v0.1.1`) shipped from the first version of this brief. This is v2. Simon approved it on 2026-10-27 from the round 1 and round 2 mockups (published plan page "Diesel Domestiques v2 Plan"), and he authorized this rewrite: "all of those old decisions for that tank game can be amended as we please. We build it right, even if we break the brief rules." Where v2 differs from v1, v2 wins. The ADRs dated 2026-10-27 in `docs/decisions/tank.md` record each change. "BRIEF x.y" means a section of `docs/BRIEF.md`; this file is `docs/games/tank.md`.

**THE reference:** `assets/tank/v2/source/reference.webp` (1088 × 608, Simon's image). "This is THE reference image. The game must look like this." Small tweaks are allowed so players can tell what they power. Simon's art direction, quoted from the prompt that made it:

> tank / landship from a fictional ww2 era, allied side, side profile, driving through a starry, extremely dark, blue/greenish-tinted summer night in the forest … warm headlights and searchlights and few, green and red, small position lights … strong tilt shift … many rivets and intricate details about little mechanisms, armament and creature comforts … dark brown paint, weathering … sections that allow a peek beneath the armor, showcasing the main drive diesel engine, the electric motor for turret traverse, the petrol engine for loading the shell and some more. Everything inside is just about enough illuminated by the incandescent lights inside the tank, giving an eery vibe … All the mechanisms allow the examiner of the image to imagine how they work, as they have a logical process that can be inferred from looking at the mechanisms in detail.

## v3 (2026-10-28): what changes from v2

Simon played v2 and chose v3 from mockups (the "Diesel Domestiques v3 Options" page, rounds 1 to 4). Where this section and the v2 sections below differ, this section wins. The mockup code lives on local branches `mock/tank3-tank` (the tank generator, `assets/tank/v3/tools_src/`, round r6) and `mock/tank3-env` (forest planes, layout, light layers, seat HUD, `assets/tank/v3env/`, `src/games/tank/view/tank_v3_env.gd`, `src/games/tank/hud/tank_hud_seats.gd`).

### One tank, five seats
- **Tank:** every crew size (1-4) rides the same tank, the reference landship rebuilt as pixel art (`r6`: 475 × 216 art px, base art plus live parts). The Bulwark, Rampart, Citadel and Bastion variants and the Bulwark gearbox go.
- **Seats:** five, with fixed trainer modes:

  | Seat | Engine id | Machine | Trainer | Job | Empty seat |
  | --- | --- | --- | --- | --- | --- |
  | Drive | `diesel` | diesel | SIM, terrain grade | moves the tank; in a gun line it digs the berm | the tank stops |
  | Gun | `dynamo` | dynamo | ERG, the bank pattern (55-100 %) | traverses and elevates the main gun, fires what is in the rack | the gun stays where it is and does not fire |
  | Loader | `steam` | steam | SIM, boiler grade | reloads into a 3-round ready rack, about 7 s a shell in band | no reloads |
  | Lights | `arc` | arc generator | ERG 65-80 % (searchlight load) | the searchlights: full gun range and normal dispersion | the gun reaches only the headlight's range (about 260 rules px), dispersion x2 |
  | Secondaries | `feed` (new) | crank-driven twin belt feed | SIM, flat | the two bow guns: exactly 2 rounds per pedal revolution (rounds per minute = 2 × cadence); power in band sets their slew speed | silent |

- **An empty seat does nothing.** With at most 4 riders at least one seat is always empty.
- **Rotation is gone;** seat choice replaces it.

### Seat choice and switching
- **Moving:** any rider moves to an empty seat with left/right (pick) and confirm (sit), only while their seat lock is open.
- **Seat lock:** a rider may change seats only 60 s or more after their last trainer-mode change of any kind (a seat switch or a plan boundary). A switch that would bring a mode change within 60 s of a planned one (a segment boundary such as a checkpoint) is refused. The HUD shows the lock as a timer.
- **Effort:** each switch is a `replan` for that rider. The rest of the current phase continues with the new seat's mode and targets, and the platform ramps every ERG <-> SIM switch (BRIEF 4.5). The PlanValidator must pass every replanned plan with no switch warning.
- **Automatic seating:** a rider who has never sent a seat or deliberate intent (Autopilot, and the solo rider by default) is seated automatically. The rule (solo loop):
  1. Drive while no target is in range.
  2. When a target comes and the rack is not full, the Loader until the rack is full.
  3. Then the Gun while the rack holds shells and a target is in range.
  4. The Secondaries when only light targets are within 220 px.

  Every stay is at least 60 s. With 2-4 riders the automatic riders fill the most needed empty seat: Drive first, then Gun, Loader, Lights, Secondaries.

### Combat changes
- **Main gun reload:** the Loader in band fills a 3-round ready rack, one shell per `steam.full_j` (tuned so a shell takes about 7 s at 250 W). The Gun fires from the rack. Each shot chambers the next shell in 1 s at the loading elevation, after which the gun re-lays. Overpressure stays (a sprint for a double-damage shell).
- **Secondaries:** two bow guns. Each pedal revolution of the Secondaries rider fires 2 rounds (alternating guns) at the nearest enemy 40-220 px ahead. Damage is per round, tuned for balance.
- **Telegraphs:** every telegraphed shot warns at least 6 s ahead:

  | Shooter | Telegraph |
  | --- | --- |
  | Light flank shot | 6 s |
  | Heavy | 6 s |
  | Destroyer | 7 s |
  | Behemoth | 8 s |

  The evade rule is unchanged: hold the sprint 2 s inside the warning (3 s for the Behemoth).
- **Difficulty is enemy count:** enemy counts scale with the crew size (1 rider 0.5, 2 riders 0.7, 3 riders 0.85, 4 riders 1.0, rounded, at least 1). Enemy HP is the same for every crew size.
- **Hitbox:** the rules' hull, turret and track-run rects come from the drawn tank (`r6_hitbox.json`, art px / 1.5), as do the trunnion, muzzle and bow-gun muzzles.
- **Terrain relief:** the view follows the rules' terrain with a height profile plus small seeded cosmetic bumps.
  - Every road wheel rides its own suspension arm.
  - The hull rotates as a whole sprite (nearest filtering) to fit the wheels, and bobs on the springs.
  - Enemies do the same.
  - The rules may use the ground height for the aim solver; otherwise the relief is cosmetic.

### World
- **Forest, mostly:** the road runs through a pine forest at night, bluer and greener, with moderate tilt-shift. The road and tank sit lower (ground line 385 art px), with a soft verge between the road and the foreground blur.
- **Little bases:** a fenced clearing with a bunker, lamp, crates and barrier stands at the depot start, at gun lines where it fits, and at the free-roam strongpoints.
- **Removed:** the village, quarry, lake and foundry-town backdrops and zone planes.
- **No people outside the tank.**
- **Ashfall Road** keeps its segments, gun lines and the Behemoth, through the forest.
- **Free-roam zones** become forest variants and base clearings. The strip names change to match.
- **Lights:** the world's lights draw on their own layer behind the tank (the v2 layering bug). The tank's lights:
  - the room lamps;
  - the headlight;
  - the turret searchlight, forward and about 11° down, on while Lights is manned and in band;
  - the rear searchlight, aft and about 13° down, always on as a work light;
  - v2's position lights.

### The tank, in the view
- **Base:** the r6 base art (re-pixelled from the reference, 63 colours).
- **Live parts, drawn each frame:**
  - the track and the road wheels on their suspension;
  - the main gun with recoil;
  - the bow guns tilting in their armoured box;
  - each seat's machine moving with its rider (the diesel's pistons on cadence);
  - a rider on each manned seat, and a bare saddle and still crank on an empty one;
  - the turret's two windows: the ready rack with its manipulator, and the breech with its rammer, following the rules' rack and loader state;
  - both bow guns' receivers.
- **Firing:**
  - the r6 main-gun blast: star flash, brake jets, fireball, smoke, dust, pebbles;
  - 11 px recoil, a 2° hull rock, a short screen shake and a scene flash;
  - the bow guns' per-round flashes, tracers and casings.

### HUD
- **Seat row:** seat panel A replaces the crew row: five live machine cards (Drive, Gun, Loader, Lights, Secondaries), each with a tiny ERG or SIM tag.
  - Empty seats are dark and marked EMPTY.
  - Your card carries YOU and the lock timer, and the hint plate reads "seat locked" or "< > move  OK sit".
  - The rack pips show on the Gun and Loader cards, and rounds per minute on the Secondaries card.
- **My numbers** follow your seat.
- **W' becomes SPRINT.**
- **Secondaries dial:** a small cold blue-white dial next to the main gun's arc.

### Effort plan (per seat, mission segments)

| Seat | Depot (WARMUP) | Advance | Gun line | Boss | Checkpoint |
| --- | --- | --- | --- | --- | --- |
| Drive | SIM game 0..+2 % | SIM game -3..+6 % | SIM flat (dig) | SIM flat | ERG 50 % |
| Gun | ERG 50 % -> 65 % | ERG bank [55, 100] | same | same | ERG 50 % |
| Loader | SIM flat, boiler 3 % × p | SIM flat, boiler 8 % × min(p, 1) | same | same | ERG 50 % |
| Lights | ERG 50 % -> 65 % | ERG [65, 80] | same | same | ERG 50 % |
| Secondaries | SIM flat | SIM flat | SIM flat | SIM flat | ERG 50 % |

- **Free roam:** each seat's work mode for the whole roam phase. The Gun's bank range is [55, 85].
- **v2's 90 % ERG gun-line block for the diesel is gone:** gun lines are now the Gun seat's bank work and the Drive seat's dig.
- **Unchanged:** every BRIEF 4.6 and 4.5 check in 2.3 applies to every replanned plan.

## 0. Hard requirements

1. Build the game through the Game SDK only (BRIEF 3.6): a `GameModule` declared by `src/games/tank/game.json`, listed by `GameRegistry`, passing `tests/sdk/test_conformance.gd` with no change to platform tests.
2. Presentation `2d` at `pixel_base` [960, 540] with `pixel_flex` `{"min": [852, 480]}`: the reference's night diorama (section 3). The rules keep their 640 × 360 units; the view scales them by 1.5.
3. 1–4 human riders, no AI crew and no bots. The crew size picks the tank. Play is host-authoritative through the relay with room codes (BRIEF 5).
4. Pedaling first: every crew size plays every content to the results with zero input (BRIEF 3.5).
5. Each engine has its own effort profile (2.3). Every plan and directive obeys BRIEF 4.6 and the switch rules of BRIEF 4.5. The governor outranks gameplay: change the design, never the governor.
6. Rides are saved and uploaded by the platform (BRIEF 3.8), with a lap per plan phase.
7. Original designs only, with no flags, insignia, national markings, text or numerals on vehicles, logos, brands, real vehicle names or existing franchises. The reference's turret star and "A17" are left off. Small crewmen (about 20 art px tall) are drawn and animated in code. People are allowed in v2.
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
  - Procedural first. The tank comes from the reference's own pixels. Machines, crew, HUD, fonts, effects and enemies are drawn in code.
  - fal is only a fallback for a backdrop plane the critic finds weak, starting from Simon's prompt. The cap is $10 for v2.
- **Branches:**
  - The integration branch is `game/tank2` (worktree `C:/Projects/wt/tank2`). Builders use their own worktrees and branches.
  - Never touch the main checkout `C:/Projects/wattlands`, except for git reads and, only while it is clean and on `main`, the final merge. Another session works there.
  - Never touch `C:/Projects/wt/reel*`, `C:/Projects/wt/v030*` or `C:/Projects/wt/exe`.
  - Never use `git stash`: the stash list is shared across worktrees.
  - Commits are small and conventional, prefixed `tank:`, except `platform:` changes and `docs:` commits.
- **Owned paths:**
  - `src/games/tank/`, `content/tank/`, `assets/tank/`, `tests/games/tank/` and `.github/workflows/game-tank.yml`.
  - `docs/decisions/tank.md`, `docs/credits.d/tank.md` and `docs/changelog.d/tank.md`.
  - This file.
- **Platform changes:** only when a P0 item is blocked. Keep them minimal and additive, with tests, committed alone with the prefix `platform:` (CLAUDE.md). None is expected: `pixel_flex`, the game's own HUD Controls, `shows_power` and `help` exist on `main`.
- **Release:** v2 is done when it is merged into `main`, tagged `tank-v0.2.0` and published as a GitHub release with a Windows build and screenshots (section 6). Push only `main` and the tag. Never force-push. If a push is rejected, stop and report.

## 2. Game design

### 2.1 Fantasy and pillars

A dark brown, riveted landship of a fictional 1940s grinds through a starry blue-green summer night: forest roads, a lake under pale cliffs, a village and a quarry. Its hull is an x-ray cutaway. Each engine room is one rider's station, and its machine visibly runs on that rider's cadence and power. Little crewmen work the rooms.

- **Your machine is your display.** Cadence drives its motion. Power against your target drives its heat, light, smoke and gauges (3.4). Your room lamp glows in your slot colour while you are in band.
- **Each engine feels different:**
  - the diesel is road tempo with sprints and ERG 90% while dug in;
  - the dynamo is ERG that climbs as its capacitor bank drains;
  - the steam engine is a grade that rises with boiler pressure and resets with every shell;
  - the arc generator is steady ERG tempo that lifts while the bow guns fire.
- **Few decisions.** One decision every 10–30 s at most. Aiming, firing, latching and the solo lever are automatic by default. Sprints are prompted: "Surge to evade" and "Surge to overpressure". Failure costs score or time, never the workout.

### 2.2 Players, slots and tanks

```json
{"id": "tank", "title": "Diesel Domestiques",
 "summary": "Crew a pedal-powered landship through a starry forest night. One engine per rider: diesel, dynamo, steam, arc generator.",
 "version": "0.2.0", "min_players": 1, "max_players": 4, "bots": false, "presentation": "2d",
 "pixel_base": [960, 540], "pixel_flex": {"min": [852, 480]},
 "entry": "res://src/games/tank/tank_game.gd",
 "picker_image": "res://assets/tank/v2/picker_card.png",
 "contents": ["ashfall_road", "roam_30", "roam_10", "roam_20", "roam_45", "roam_60", "drill"],
 "default_content": "ashfall_road", "e2e_content": "drill", "zero_input_content": "ashfall_road",
 "first_run_priority": -1,
 "options": [{"id": "rotation", "type": "toggle", "default": true, "label": "TANK_OPT_ROTATION"}],
 "content_cards": {"ashfall_road": {...featured}, "roam_30": {...featured}, "roam_10": {...}, "roam_20": {...}, "roam_45": {...}, "roam_60": {...}, "drill": {...not featured}}}
```

The content cards use in-engine renders under `assets/tank/v2/` and `TANK_CARD_*` detail strings. `rotation` applies to missions only. Free roam never rotates (Simon's decision).

| Crew | Tank | Engine rooms, rear to front | Notes |
| --- | --- | --- | --- |
| 1 | Bulwark | bulwark (the diesel with a three-way gearbox) | the short tank |
| 2 | Rampart | diesel, dynamo | |
| 3 | Citadel | diesel, steam, dynamo | the reference tank |
| 4 | Bastion | diesel, steam, dynamo, arc | the Citadel plus an arc-generator room and a searchlight tower |

- The modules are cut from the reference (3.2). The art kit measures hull sizes and anchors, and `tanks.json` takes them in rules px (art px / 1.5).
- **Starting engines by slot:** 0 diesel, 1 dynamo, 2 steam, 3 arc. The room order above is the art's; the slot-to-engine map is independent of it.
- **Rotation** (missions, default on): at each checkpoint everyone moves to the next engine in slot order: diesel → dynamo → steam → arc → diesel, among the tank's engines. It is fixed at the start, with no `replan`. With 4 riders and 4 stages every rider works every engine once.
- **Engine roles:**
  - Diesel: tracks, and the dozer blade at a gun line.
  - Dynamo: turret traverse and gun elevation; the hoist in the Rampart; the bow guns in the Rampart and the Citadel.
  - Steam: the loader in the Citadel and the Bastion.
  - Arc generator: the searchlights and the bow guns in the Bastion.
  - The Bulwark's diesel does everything through its gearbox.
- **Drops and AFK:** no join after the start. A dropped or AFK rider's station runs on reserve (as if P_eff 60 W, never in band) under Autopilot. If every rider is AFK, nothing has power.

### 2.3 Effort plan

`effort/tank_plan_builder.gd` builds one EffortPlan per rider. Mission segments are unchanged from v1:

| Segment | Kind | Length |
| --- | --- | --- |
| Depot | WARMUP | 300 s |
| Advance | WORK | open-ended, 180 s nominal (90–300 s) |
| Gun line | WORK | open-ended, 120 s nominal (60–180 s) |
| Checkpoint | RECOVERY | 60 s, ERG 50% for everyone |
| Boss | WORK | open-ended, 240 s nominal (120–360 s) |
| Cool-down | appended by the validator | |

The nominal mission is 30 min and at most 41 min. The rules read segments from `frame.phase` and call `end_phase` for every rider in one step once an objective is done and `min_s` has passed. Free roam has its own plan (2.10).

| Engine | Depot (WARMUP) | Advance | Gun line | Boss |
| --- | --- | --- | --- | --- |
| Diesel | SIM `game`, terrain 0 … +2% | SIM `game`, terrain −3 … +6%; evade sprints | ERG 90% (dig in) | SIM `flat`; evade sprints |
| Dynamo | ERG 50%, `ramp_to_pct` 65 | ERG 55%, `range_pct` [55, 100] (bank) | same | same |
| Steam | SIM `flat`, boiler 3% × pressure | SIM `flat`, boiler 8% × min(pressure, 1); Overpressure and evade sprints | same | same |
| Arc generator | ERG 50%, `ramp_to_pct` 65 | ERG 65%, `range_pct` [65, 80] (arc load) | same | same |
| Bulwark | SIM `game`, terrain 0 … +2%; lever drills | SIM `game` + Hoist grade 4%; evade sprints | ERG 90% | SIM `flat` + Hoist 4% or 0; evade sprints |

**Enemies shape the workout:**
- light tanks bring short sprint prompts (their flank shot, 2.4);
- mediums bring sustained tempo;
- heavy tanks bring the 90% gun-line duel;
- the Behemoth is the sprint-heavy finale.

The encounter list is fixed in the mission file, so the PlanValidator checks the whole plan before the ride. Enemies never add, lengthen or harden a phase. Tank calls no `replan`.

**In band** (glow, score, charging):

| Engine | In band when |
| --- | --- |
| Diesel and Bulwark in SIM | 76–105% FTP; evade sprints count |
| Dynamo, arc generator, and every 90% gun line | power ≥ 95% of the applied target and cadence ≥ 60 |
| Steam, building | ≥ 90% FTP |
| Steam, loaded or cycling | cadence ≥ 50 |
| Depot and checkpoints | cadence ≥ 60 |

**Checks** (each tested, section 4):
- **4.6.1:**
  - Every target and range bound is 50–100% FTP, and nothing exceeds 105%.
  - The boss and every roam phase longer than 300 s stay under their 105% cap.
  - 90% gun lines last ≤ 180 s.
  - The unverified factor of 0.85 only lowers targets.
- **4.6.2:** a bank or arc update moves ≤ 10 points, sent as three sub-steps 1 s apart (≤ 3.3% FTP/s).
- **4.6.3:** rescue arms in dynamo and arc phases while the applied target is ≥ 60% FTP, and in every 90% gun line.
- **4.6.6:** steam 8% × difficulty ≤ +8%; diesel (−3 … +6%) × difficulty; Bulwark (6 + 4)% × difficulty ≤ +10%. The largest haptic is +3%.
- **4.6.8:** the depot stays at ERG 50–65% and SIM 0 … +3% before difficulty, with no haptics.
- **BRIEF 4.5:** per-rider ERG ↔ SIM switches are ≥ 60 s apart.

**Directive patterns** (`ctx.directives`, `source: "tank"`):
1. **Bank (dynamo):** `{mode: ERG, target_pct: 55 + 45 × (1 − bank/100), reason: "bank"}` every 5 s in sub-steps, inside `range_pct` (roam: [55, 85], 2.10). None in the depot or checkpoints.
2. **Arc:** `{mode: ERG, target_pct: 65 + 15 × duty, reason: "arc"}` every 5 s in sub-steps. `duty` is the share of the last 10 s in which the bow guns were firing (0–1). None in the depot or checkpoints.
3. **Boiler:** `{mode: SIM, mode_grade: 8% × min(pressure, 1), reason: "boiler"}`, as in v1.
4. **Hoist (Bulwark):** as in v1.
5. **Terrain:** `course_grade(peer, pct)` at 2 Hz.
6. **Cadence:** `cadence_band(peer, 60, 120)` at each segment start, and (50, 120) for a loaded or cycling loader.
7. **Haptics** (2.7).
8. **`end_phase`.**

Nothing is sent in the cool-down.

**Sprints send nothing.** Evade and Overpressure sprints are the rider's own in the phase's SIM. They are unavailable in WARMUP phases and the first 300 s, and no sprint prompt shows to a rider in WARMUP or an ERG phase.

### 2.4 Rules and mechanics

Pure `step(state, inputs, dt)` classes at 0.05 s, using only `ctx.rng`, configured by parsed content dictionaries. Units: rules px (640 × 360 world), game metres, seconds, P_eff watts. The v1 rules carry over unless changed here: drive and speed model, dig in and berm, the dynamo bank, steam pressure and Overpressure, the Bulwark gearbox and auto-lever, damage, breakdown, overrun, enemies, gun lines and the boss.

**Removed: the Ram.** This covers its rules, state, intents (`ram`, ability_1 for the diesel), cues, haptic, events (`ram`, `dodge`), HUD cell, sound, content keys, strings and tests. Obstacles (wire, wrecks) stop the tank until a heavy shell, three light shells or 4 s of bow-gun fire within range clears them. The Bulwark's boss lunge is gone.

**New: Surge to evade.**
- **Telegraphed shots:**

  | Shooter | Telegraph |
  | --- | --- |
  | Tank destroyer | 4 s glint |
  | Heavy tank | 3 s muzzle glow |
  | Behemoth main gun | 6 s |
  | Light tank | 2.5 s flank shot: its first shot after it reaches its hold distance (8 damage, 70%) |

- **Who sees the prompt:** during a telegraph, every peer shows the world tag "SURGE TO EVADE" over the shooter with countdown pips. The instruction line ("SURGE nnn+ W s") shows only to riders who can evade: in a SIM WORK phase, past the first 300 s.
- **How the shot misses:** if any such rider holds the sprint rule (≥ 1.2 × FTP over the last 3 s, BRIEF 3.5, raw W) for ≥ 2 s inside the telegraph (≥ 3 s for the Behemoth), the shot misses. The tank lurches (diesel or Bulwark) or the boiler blows a smoke screen (steam).
- **Events and results:** event `evade` `{e, ok}`. Results count evades.
- **No intent.** Autopilot never sprints, so a zero-input crew takes the hit.

**Gun:**
- Elevation runs −12 … +30° (v1: −5).
- **Bow guns:** two short guns in the nose, as in the reference, on every tank. They replace the Citadel's fore and aft secondaries.
- A burst does 5 damage every 2 s at the nearest enemy ahead from 40 to 220 px off the hull front, auto-aimed. Mediums take 50%; heavies, destroyers and Behemoth parts take 25%.
- **Power source by tank:**

  | Tank | Bow guns run on |
  | --- | --- |
  | Bastion | the arc generator: full rate in band, half rate under band, none while AFK |
  | Rampart and Citadel | the dynamo bank, 2 units per burst, none below 10 |
  | Bulwark | its gearbox, at half rate, free |

- Shell code 4 is the bow-gun round (`SHELL_BOW`, formerly `SHELL_SECONDARY`).
- The main gun traverses for rear enemies, as in v1 (auto-aim).

**Arc generator (Bastion):**
- **Arc load:** `duty` (2.3) rises while the bow guns fire.
- **Searchlights:** while the arc rider is in band, the searchlights are lit, which halves the main gun's dispersion.
- **Rescue:** the bow guns stop and the searchlights dim (toast "Arc generator stalled").

**Enemies:**
- **Scale:** HP and counts are scaled by tank: Bulwark 0.75, Rampart 0.8, Citadel 1.0, Bastion 1.2 (counts rounded, at least 1).
- **Spacing:** enemies keep their own depth lanes and spacing, so none overlap at a gun line (the round 2 mock's fix).
- **Caps:** 16 enemies, 24 shells.

**Tuning targets:**
- **T1–T5:** as in v1, including crew 4 (T1 crews 1–4; T2 crews 2–4).
- **T6:** every Advance has at least one sprint prompt (a telegraphed shot) and one medium. Stages 2 and 3 end in a heavy-tank duel lasting 90–180 s for a compliant crew.
- **T7 (arc):** a compliant arc rider's applied target spends ≥ 30 s above 72% FTP per stage and is back to ≤ 68% within 60 s of a fight's end.

### 2.5 Autopilot and zero input

As in v1, minus the Ram:
- auto-aim aims and fires;
- the boiler latches a heavy shell when the window ends;
- the auto-lever runs the Bulwark;
- the bow guns fire on their own;
- in free roam, Autopilot turns the tank at the map's ends (2.10).

Autopilot never sprints, never Overpressures and never changes effort targets. A human counts as Autopilot until their first `lever`, `aim`, `target`, `traverse`, `fire`, `latch` or `turn` intent; `over` never ends it. `local_intents` turns `surge` only into `over`.

### 2.6 Multiplayer and network

As in v1 (host-authoritative, 10 Hz full snapshots ≤ 4 KB at the caps with 4 riders, ordered events ≤ 10/s, client prediction of your own room).
- **Intents:** `lever`, `aim`, `target`, `traverse`, `fire`, `latch`, `over`, `turn`.
- **Events:** `segment`, `rotation`, `shot`, `hit`, `kill`, `evade`, `breakdown`, `repaired`, `overrun`, `boss_phase`, `turn`, `time_up`.
- **Per-peer prompts:** each peer raises its own rider's prompts from snapshots, events and local telemetry.
- **Telegraph timing:** the snapshot carries each telegraphing enemy's remaining time (and the boss's), so every peer's HUD counts down.

### 2.7 Haptics

| Event | Receivers | `haptic` | `duration_s` | `reason` |
| --- | --- | --- | --- | --- |
| Hit of ≥ 8 damage | every rider in SIM | 2.0 | 1.5 | `hit` |
| Behemoth main-gun hit | every rider in SIM | 3.0 | 2.0 | `boss_hit` |

The v1 rules otherwise hold (never in WARMUP, the first 300 s or the cool-down, or to an ERG rider; opt-out respected; 15 s spacing). The Ram haptic is gone.

### 2.8 Results and progression

**Missions:** as in v1. Ram counts are replaced by evades (tried and successful), and bow-gun hits are added. Score, grades, XP and unlocks are unchanged.

**Free roam:**
- **Score:** team points (2.10), kills by type, distance, evades, breakdowns.
- **Grade:** by points per minute of WORK time: S ≥ 22.5, A ≥ 17.5, B ≥ 12.5, C ≥ 7.5, else D (tuned in P5 so a compliant 30-min crew of 3 earns B or A).
- **Outcome:** `finished("time_up")`.
- **Rewards:** XP = round(kJ / 10) plus the grade bonus. Unlocks as for missions, minus the Behemoth one.
- **Strava `ride_tag`:** "Free Roam N min".

### 2.9 Content

- **Missions:** Ashfall Road (v1's stages, retuned for evade and the bow guns) and `drill` (e2e, 130 s inside warm-up limits; the arc rider rides ERG 50 → 55% with `range_pct` [55, 65]).
- **Free roam:** `roam_10`, `roam_20`, `roam_30`, `roam_45`, `roam_60` (2.10).
- **Files:** `tanks.json` (4 tanks), `stations.json` (+ arc), `enemies.json`, `missions/*.json` (`kind` "mission" or "roam"), `roam/valley.json` (the map), `scoring.json`, `cosmetics.json` and `strings.csv` (`TANK_*`), all validated at load.

### 2.10 Free roam

**Map:** one long seeded valley road, about 6 km, built at the session start from `ctx.rng` and `content/tank/roam/valley.json`.
- **Zones:** pine forest road, lake shore under the cliffs, a village, a quarry, open meadow, each with its own terrain points (−3 … +5%) and backdrop set.
- **The tank drives back and forth.** At either end the road stops at a turning place; a `turn` intent flips the travel direction anywhere (the diesel or Bulwark rider only, 30 s cooldown). Autopilot turns at the ends after 3 s.
- **A turn:** an 8 s stop, during which the view mirrors the tank behind a dust cloud. The camera follows the tank, and the world scrolls with the travel direction.
- **No rotation:** each rider keeps one engine for the whole session.

**Patrols:** seeded random patrols every 50–110 s of WORK time, entering ahead in the travel direction (most) or behind.

| Patrol | Weight |
| --- | --- |
| 1–2 lights | 45% |
| a medium (± a light) | 30% |
| a tank destroyer | 15% |
| a heavy tank (only after 10 min, at most one at a time) | 10% |

- At most 6 enemies alive. Patrols use the mission rules (holds, telegraphs, evade, bow guns).
- Dug-in strongpoints sit at fixed map spots and come back 10 min after they fall.
- The tank halts while a strongpoint or a heavy is within range ("Engage"). Otherwise it drives on.

**Effort plan per rider:**

| Phase | Kind | Length |
| --- | --- | --- |
| Drive-out | WARMUP | 300 s: the depot's targets and models, no enemies |
| Roam | WORK, open-ended | `min_s` = minutes × 60 − 300, `max_s` = `min_s` + 300 |

| Engine | Roam phase |
| --- | --- |
| Diesel | SIM `game` on the map's grade |
| Dynamo | ERG, `range_pct` [55, 85] |
| Steam | SIM `flat` + boiler |
| Arc generator | ERG, [65, 80] |
| Bulwark | the Advance's |

- The roam phase is over 300 s, so the 105% cap applies, and every bound is ≤ 100%.
- **Time up** at `min_s`: no new patrols. A fight in progress (an enemy within 400 px) may finish, up to `max_s`. Then `end_phase` for everyone in one step, the cool-down, and `finished("time_up")`.

**Points:**

| Kill | Points |
| --- | --- |
| Light | 10 |
| Medium | 25 |
| Destroyer | 30 |
| Dug-in | 20 |
| Heavy | 60 |

- Evade +5; breakdown −40; every full kilometre +2.
- Points are the crew's.

**HUD:** the map strip across the top (zones in profile, the tank, patrols, strongpoints), and a board with time left, points and kills (3.6).

## 3. Presentation

### 3.1 Look and resolution

The reference, at 960 × 540 art px (2× at 1080p, 4× at 4K, nearest filtering). Through `pixel_flex` (min 852 × 480), wider or narrower windows show more world (2560 × 1440 → 3× 853 × 480; 3440 × 1440 → 3× 1146 × 480). Rules px × 1.5 = art px. Nothing important sits only at the far edges, and the HUD rects use the SDK's anchoring.

**Planes, back to front:**

| Plane | Treatment |
| --- | --- |
| Starry sky with the Milky Way | blurred |
| Dark mountains | blurred |
| The pale cliff and the misty lake (a landmark piece) | blurred |
| Soft pine forest | blurred |
| The road band | sharp; the tank, enemies and props live here |
| Dark foreground shrubs, pines and rocks | strongly blurred and darkened |

- **Sources:** the planes start from the reference's own layers (round 1 kit) and extend procedurally into long seamless strips.
- **Free roam:** zones swap the near planes (village, quarry, meadow, lake shore) from the same procedural kit.

**Tilt-shift, strong:**
- each plane is blurred once at load (radii in the kit manifest);
- a light per-frame depth-of-field pass on the art-resolution frame softens moving things outside the road band (smoke, shells, far enemies);
- the per-frame pass is a rider-facing setting (`player_options` toggle `miniature`, default on) and switches itself off if the frame time stays above 16.7 ms for 5 s.

**Light:**
- additive glows and volumetric cones for the headlight and searchlights;
- warm incandescent room lamps and amber lamps;
- cold blue-white arcs (dynamo, arc generator);
- small green and red position lights;
- fire and muzzle flashes that light the scene for a few frames.

Lights are the only near-saturated pixels.

### 3.2 The tank

- **Cut from the reference:** the tank is cut from the reference's pixels at its bulkheads into modules: rear (engine), rooms, front (glacis, bow guns, headlight, sprocket), turret body and barrel. The variants 1–4 are assembled from them and stay extremely close to the reference (the Citadel is the reference tank). This is the round 1 kit, `assets/tank/v2/` (formerly the mock's `v2mock`), with its generator scripts in `assets/tank/v2/tools_src/` (`.gdignore`d) and `kit.json` (rects, anchors, rooms, muzzles, lights).
- **Code on top:** machines, crew, lamps, beams, exhaust, track motion, the barrel at its elevation and the turret's traverse.
- **Rooms:** each station's room has a small enamel plaque with a lamp in the rider's slot colour. The warm room glow is lit by in band.
- **Running gear:** wheels and track links move with tank speed. Hits shake the hull. A breakdown kills the lamps, and the crew work the repair.

### 3.3 Crew

Crewmen are about 20 art px tall, procedural, from the mock's `crew20` sheet. Their poses follow the state:

| Crewman | Action |
| --- | --- |
| Engineer | works the diesel with a wrench |
| Stoker | shovels coal at the firebox on cadence |
| Loader | carries a shell up the hoist |
| Gunner | at the breech, recoils with each shot |
| Dynamo tech | at the panel |
| Arc tech | at the switchboard |
| Commander | on the turret roof, sweeping the searchlight |

They never carry text or insignia.

### 3.4 Engines in sync with the riders

One machine per station: `view/tank_mech.gd` (`TankMech`, from the mock's `TankV2MockMech`), a pure Image painter for diesel, dynamo, steam and arc. It paints the room overlay in the world and the engine window on the HUD.

- **Phase:** `phase` is the integral of rpm / 60 per second times a gear ratio per machine:

  | Machine | Gear ratio |
  | --- | --- |
  | Diesel | ×2, three firings per revolution |
  | Dynamo armature | ×3 |
  | Steam | 1 shell-hoist step per revolution |
  | Arc | 2 ladder climbs per revolution |

  It runs from local telemetry for your own room (client prediction) and from snapshots for the others.
- **Power:** `power` = watts / the rider's target (in band 0.84–1.17).
  - Under band: dim, sooty, needles low.
  - In band: warm and steady, the lamp in the slot colour.
  - Over band: shaking, red needles, vapour, overflowing jars, the safety valve blowing.
- **Stopped:** at 0 rpm everything stands still.
- **Cost:** painting is about 1 ms per machine per frame, so in-world overlays repaint at most at 30 Hz.

### 3.5 Enemies, props and effects

- **Enemies and the Behemoth:** procedural sprites in the reference's style (the mock's enemy kit). Each has its own silhouette: low wedge lights, tall slab mediums, long heavies, turretless destroyers, dug-in turrets behind concrete, and the multi-bogie Behemoth.
- **Wrecks and the halt line:** wrecks age on sim time into debris heaps. The halt line is concrete teeth with a post and a hooded amber lamp.
- **Particles:**
  - muzzle flashes, smoke rings, casings, tracers and impacts;
  - the diesel exhaust by watts;
  - steam plumes and the safety valve;
  - dynamo sparks and the arc ladder;
  - the evade lurch and smoke screen;
  - dust and mud at tank speed.

  They come from pooled emitters with caps, use cosmetic randomness from the view's own RNG, and never feed the rules.

### 3.6 HUD, the game's own

No kit widgets: `hud_spec()` adds the game's own Controls with `add_control(control, Rect2i)` in art px of the 960 × 540 base and sets `shows_power = true`. The toasts and banners are placed and themed through `spec.palette`, and `help` has 3–6 entries.

**Look:**
- riveted dark-iron plates, panel `#17140f`, a 1 px brass frame `#8a6a3a` with a darker inner line and corner rivets;
- text `#e8dcc0` and dim `#a3937a`, amber accent `#e3a24a`, bar tracks `#3a3128`, red over `#c4553c`;
- rider identity only in slot colours;
- own bitmap fonts: `tank_stencil_5x7`, `tank_stencil_5x9` (rider-facing text cap ≥ 9 art px) and `tank_digits_14x24` (key numbers 24 art px tall, 48 px at 1080p), drawn procedurally into PNGs under `assets/tank/v2/hud/`.

**Layout** (art px; the bottom-right 200 × 60 stays clear; the tank band, y 150–360, stays clear):

| Area | Contents |
| --- | --- |
| Bottom left, my numbers | big watts with %FTP and a gauge against the band, coloured under/in/over; big cadence with its band gauge; one instruction line: HOLD 152–210 W, SPIN 60+ RPM, SURGE 240+ W 0:04, LATCH, RESERVE; W′ and the virtual gear (SIM) as small bars; the station name |
| Bottom middle, crew row | one card per rider in room order (rear to front = left to right): a live engine window (`TankMech`, 112 × 64) in a riveted frame, the rider's name in their slot colour (truncated with an ellipsis to fit), watts, and an in-band strip (green in band, blue under, red over); yours is marked YOU |
| Top left, mission plate | stage name, stage clock, a compact stage strip and the objective; in free roam, the map strip across the top |
| Top right | the hull plate (HP bar and number), kills; the boss bars when the Behemoth is up; in free roam, the time left, points and kills board |

**In the world, not in panels:**
- the speed tag on the road behind the tank;
- the halt line's post with its distance plate;
- SURGE TO EVADE over a telegraphing shooter with countdown pips;
- the gun's elevation as a thin arc at the turret while the gunner aims (drawn clear of the barrel, with its label);
- the turn marker at the map's ends.

**Toasts and banners:** toasts sit under the mission plate, banners in the centre, and both carry the prompts ("Surge to overpressure", "Dynamo stalled", "Arc generator stalled", "Turn around").

### 3.7 Audio

As in v1 (diesel rumble by cadence, dynamo whine, steam chuff and hiss, cannon, shells, casings, explosions, tracks, lever, hoist), plus:
- the arc's crackle and hum;
- the bow guns' rattle;
- night ambience (crickets, wind in the pines).

Sounds are synthesized or CC0.

## 4. Testing and gates

Unit tests (GUT, `tests/games/tank/`) cover every rule and number in 2.2–2.10, including:
- plans for crews 1–4 × rotation on/off × FTP {80, 200, 400} × verified/unverified, plus `drill` and every roam length;
- the arc pattern and its sub-steps;
- evade (every telegraph type, the SIM-only rule, the first 300 s, ERG riders);
- bow guns per tank and power source;
- elevation −12°, with the solver able to hit a light tank at its hold distance;
- the roam map generation (seeded, deterministic), patrols, the turn, time up and overtime, and roam points;
- snapshots ≤ 4 KB at the caps with 4 riders;
- intent ownership for `turn`;
- every tank's view built headless from fixtures;
- the HUD's controls for crews 1–4 in mission and roam;
- no missing string keys.

The Ram's tests go with it.

**Static tests:** as in v1, without the art.json palette checks (the art is procedural):
- no trainer-path references;
- no wall clock or global RNG in `rules/`, `effort/` or `combat/`;
- no kit-widget kinds in `hud/`.

**Simulation matrix** (`bash tests/games/tank/sim/run_sims.sh`, `node tests/games/tank/sim/check_sims.mjs build/tank/sims`):

| Scenario | Coverage |
| --- | --- |
| S1–S8 | as in v1, extended to crew 4 |
| S9 | crew 1 sprinting rider: successful evades and no SIM → ERG entry above target |
| S10 | crew 3 network paths: a client's intents (aim, over, turn in roam) applied by the host |
| S11 | free roam: `roam_10` for crews 1 and 4, `roam_30` for crew 3 (time up, overtime bound, no patrol after time up, FIT laps, grade) |
| S12 | `roam_10` crew 3 at 0 W: no kills by crew fire, grade D |

**Gates (all must pass):**
1. Tank unit and static tests;
2. `check_scripts`, gdlint and gdformat;
3. SDK conformance at 1 and 4 riders;
4. the simulation matrix;
5. `tools/fit_check` on every FIT the sims wrote;
6. `node tools/e2e/run.mjs --games=tank`;
7. the full `tools/run_tests` at or above the floor (the floor is lowered once, by exactly the removed v1 art, Ram and kit-HUD tests, with an ADR).

**Screenshots:** `tools/screenshot` frames of crews 1, 3 and 4 in the depot, an Advance, a gun line, the boss and free roam, reviewed by an adversarial art critic against the reference. The perf gate is set aside for v2 (Simon, 2026-10-26); the per-frame DoF auto-off (3.1) protects slow machines.

## 5. Orchestration (v2)

The lead integrates on `game/tank2` and runs builders in their own worktrees from the P0 commit. Each builder touches only its listed paths, reports conflicts and requests instead of editing outside them, and commits locally. Phases:

| Phase | What | Owner |
| --- | --- | --- |
| P0 | this brief and the ADRs | lead |
| P1 + P2 | the art kit (`assets/tank/v2/`, cleaned from the mock kit, the 4 tank variants, planes, crew, enemies, the Behemoth, the picker card) and the view rebuild (planes and tilt-shift, the modular tank, rooms and lamps, `TankMech`, crew, beams, effects, `pixel_flex`); the old art and its tests are removed | view builder |
| P3 | the custom HUD (plates, fonts, crew row, world tags, toasts and banners, help); the kit HUD is removed | hud builder |
| P4 | gameplay (Ram out, evade, −12°, bow guns, enemy spacing, the 4th rider and the arc plan, contracts, net, autopilot, content, sims) | rules builder |
| P5 | free roam, full stack | roam builder after the P2–P4 merge |
| P6 | cleanup (the removal table on the plan page), local worktrees and branches of v1 and the mocks | lead |
| P7 | the critic, balance (T1–T7), sims, e2e, the full suite, export, smoke, merge, tag `tank-v0.2.0`, the GitHub release | lead |

## 6. Definition of Done

- **Reachable:** every item in 2.2–2.10 is implemented, reachable from the game picker and tested. Every gate in section 4 is green, with nothing weakened.
- **Zero input:** a solo rider plays Ashfall Road and `roam_10` to the results with zero input. Crews of 2–4 play joined by code, and the e2e run passes.
- **Safety:** every plan passes the PlanValidator, and every directive is clamped and matches 2.3 or 2.7. No Tank code reaches the trainer except through `ctx.directives`.
- **Look:** the game looks like the reference: an art critic scores fidelity, HUD, engine windows and variants ≥ 7/10 on the final screenshots.
- **Docs:** `src/games/tank/README.md`, `HARDWARE_TEST.md` (adds the arc ERG pattern, evade sprints and the roam phase), `docs/decisions/tank.md`, `docs/credits.d/tank.md` and `docs/changelog.d/tank.md` are current.
- **Released:**
  - `game/tank2` is merged into `main` (`--no-ff`) and the GUT floor is updated;
  - `main` and the tag `tank-v0.2.0` are pushed;
  - a GitHub release `tank-v0.2.0` carries the Windows build (zip) and screenshots.
