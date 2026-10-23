ultracode

# Wattlands: Diesel Domestiques game brief

You are the lead engineer and orchestrator for Diesel Domestiques, one game module on the existing Wattlands platform (tag `v0.1.0` on `main`): one to three riders crew a pedal-powered super-heavy tank, one engine each. Run the work as dynamic workflows with parallel subagents (section 5). I am not available: never stop to ask. When something is ambiguous, choose what best serves the pillars (BRIEF 3.1, 2.1 below), record a short ADR (date, decision, alternatives, reason) in `docs/decisions/tank.md`, and continue. Stop only at the Definition of Done (section 6) or a fix-round cap, then give an honest final report. First read `CLAUDE.md`, `docs/GAME_SDK.md`, `docs/ART_PIPELINE.md`, `docs/ARCHITECTURE.md` and `docs/BRIEF.md` sections 1, 2, 3.1–3.6, 3.8–3.11, 4.2, 4.5–4.7, 5, 6 and 7. "BRIEF x.y" means that section of `docs/BRIEF.md`; this file is `docs/games/tank.md`.

## 0. Hard requirements

1. Build the game `tank` through the Game SDK only (BRIEF 3.6): a `GameModule` declared by `src/games/tank/game.json`, listed by `GameRegistry`, passing `tests/sdk/test_conformance.gd` with no change to platform tests.
2. Presentation `2d` at `pixel_base` [640, 360] (BRIEF 3.9), drawn as a dark 2.5D diorama: sprite planes in depth with depth-of-field blur, haze and glowing lights (section 3). Sprites come from the art pipeline (BRIEF 3.10) for at most $15, animated by parts, at 60 fps at 1080p on integrated graphics (Compatibility renderer).
3. 1–3 human riders, no AI crew, no bots; the crew size picks the tank. Host-authoritative through the relay with room codes (BRIEF 5).
4. Pedaling first: every crew size plays to the results with zero input (BRIEF 3.5).
5. Each engine has its own effort profile (2.3). Every plan and directive obeys BRIEF 4.6 and the switch rules of BRIEF 4.5. The governor outranks gameplay: change the design, never the governor.
6. Rides are saved and uploaded by the platform (BRIEF 3.8), with a lap per mission segment.
7. Original designs only: no people drawn anywhere; no flags, insignia, national markings, text, logos, brands, real vehicle names or existing franchises.
8. Testable headless with MockTrainer riders and Autopilot; every gate in section 4 green.

## 1. Ground rules

- Locks (BRIEF 1): every process has `WATTLANDS_NO_HW_CONTROL=1` and `WATTLANDS_NO_NETWORK_INTEGRATIONS=1` (source `tools/env.sh` or `tools/env.ps1`). Godot runs only through `tools/godot.sh` / `tools/godot.ps1` (BRIEF 2) under BRIEF 7's harness rules.
- Art lock (BRIEF 1, 3.10): real fal calls need `FAL_KEY` and `WATTLANDS_ALLOW_ART=1` already in this session's environment (Simon sets both). Never set `WATTLANDS_ALLOW_ART` yourself; never print, log or commit the key. `generate.mjs` ignores `WATTLANDS_NO_NETWORK_INTEGRATIONS` (BRIEF 3.10), so every process, art runs included, keeps both locks. If either variable is missing, ship placeholder art (section 3) and say so. Only `generate.mjs` runs keep the two art variables: run everything else, the platform suite and e2e included, with `FAL_KEY` and `WATTLANDS_ALLOW_ART` removed from its environment (for example `env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/run_tests`), so no test can reach the real fal. If `generate.mjs` refuses because of the network lock, that contradicts BRIEF 3.10: fix it as a `platform:` change rather than unsetting the lock.
- Branch `game/tank` from the latest `main`; if it exists, resume from `docs/decisions/tank.md` and the last commits. Builders use their own worktrees. Small conventional commits prefixed `tank:`, except `platform:` changes (below) and G0's one `docs:` commit of planning files. Commit locally; never push, open pull requests or change remotes (BRIEF 1). Simon pushes after reading the report.
- Owned paths: `src/games/tank/`, `content/tank/`, `assets/tank/`, `tests/games/tank/`, `.github/workflows/game-tank.yml`, `docs/decisions/tank.md`, `docs/credits.d/tank.md`, `docs/changelog.d/tank.md`. Everything else is read-only, including this file.
- Platform changes: only when a P0 item is blocked by a platform bug or missing SDK feature. The smallest additive change (no renamed or removed API, no changed default, never a weaker BRIEF 4.6 rule or BRIEF 7 assertion), with tests and a `docs/GAME_SDK.md` update if the API grows, the full platform suite green, committed alone with the prefix `platform:` and listed in the final report.
- P0 must ship; P1 once P0 is green; P2 is notes in `src/games/tank/README.md`. No "TODO: implement" on a P0 path. Never weaken a threshold or assertion to reach green.
- Art budget: $15 of estimated fal spend per session, summed from `assets/tank/art_manifest.json`; each generate run passes `--budget=<15 − spent>`. Audio: CC0 if downloadable, else synthesized (BRIEF 3.9). No new code dependencies.

## 2. Game design

### 2.1 Fantasy and pillars

Dark, oily alternate-history 1940s. A colossal brutalist super-heavy tank grinds through a landscape and sometimes a village or city toward an enemy super-heavy. The hull is an x-ray cutaway: each engine room is one rider's station, its machinery runs visibly on that rider's cadence and watts, and chains and shafts link it to its job (diesel to tracks, dynamo to turret ring, steam engine to shell hoist). No people are drawn; the machines are the crew.

- The cutaway is the display: you watch your engine work, and its room glows when you are in band.
- Each engine feels different: the diesel is road tempo with sprints and ERG 90% while dug in, the dynamo is ERG that climbs as its capacitor bank drains, the steam engine is a grade that rises with boiler pressure and resets with every shell.
- One decision every 10–30 s at most; aiming, firing, latching and the solo lever are automatic by default. Failure costs score or time, never the workout.

### 2.2 Players and slots

```json
{"id": "tank", "title": "Diesel Domestiques",
 "summary": "Crew a pedal-powered super-heavy tank through burning countryside and villages. One engine per rider: diesel, dynamo, steam.",
 "version": "0.1.0", "min_players": 1, "max_players": 3, "bots": false, "presentation": "2d", "pixel_base": [640, 360],
 "entry": "res://src/games/tank/tank_game.gd", "contents": ["ashfall_road", "drill"],
 "default_content": "ashfall_road", "e2e_content": "drill", "zero_input_content": "ashfall_road",
 "first_run_priority": -1,
 "options": [{"id": "rotation", "type": "toggle", "default": true, "label": "TANK_OPT_ROTATION"}]}
```

- The host sets `rotation` in the lobby; the rules read `ctx.options`. Spell the entry's fields (`type`, `default`, `label`) as `docs/GAME_SDK.md` does, and add `TANK_OPT_ROTATION` to `content/tank/strings.csv`. No `player_options`. `first_run_priority` −1, as in Siege, keeps Tank off the first run however a tie with Workout's 0 would break. G0 writes `game.json` without `picker_image` (optional, BRIEF 3.6), since a path to a missing file could hide the game; in G2 you add `"picker_image": "res://assets/tank/sprites/picker_card.png"` once that PNG exists.

| Crew | Tank | Hull (art px) | Engine rooms, rear to front | Turrets |
| --- | --- | --- | --- | --- |
| 1 | Bulwark | 192 × 72 | diesel with a three-way gearbox | main |
| 2 | Rampart | 240 × 76 | diesel, dynamo | main |
| 3 | Citadel | 288 × 80 | diesel, dynamo, steam | main, secondaries fore and aft |

- Diesel: tracks, and the dozer blade at a gun line. Dynamo: turret traverse and gun elevation, plus the hoist in the Rampart and the secondaries in the Citadel. Steam: the Citadel's loader. The Bulwark's diesel does everything through its gearbox.
- Starting engines by slot: 0 diesel, 1 dynamo, 2 steam. Rotation (the `rotation` option, default on) moves everyone to the next engine at each checkpoint. Plans cover the whole session (BRIEF 3.6), so rotation is fixed at the start (no `replan`):

| Slot | Rampart: stages 1, 2, 3, boss | Citadel: stages 1, 2, 3, boss |
| --- | --- | --- |
| 0 | diesel, dynamo, diesel, dynamo | diesel, dynamo, steam, diesel |
| 1 | dynamo, diesel, dynamo, diesel | dynamo, steam, diesel, dynamo |
| 2 | — | steam, diesel, dynamo, steam |

- No join after the start. A dropped or AFK rider's station runs on reserve (as if P_eff 60 W, never in band) under Autopilot and keeps its plan until reconnect. If every rider is AFK nothing has power: the bank and pressure freeze and no gun fires, secondaries included.

### 2.3 Effort plan

`effort/plan_builder.gd` builds one EffortPlan per rider. All plans share the segments below, so `phase_changed` means the same segment for everyone. Every phase has `lap` true and a strings label.

| Segment | kind | Length |
| --- | --- | --- |
| Depot roll-out | WARMUP | `duration_s` 300 |
| Stage n Advance (n = 1–3) | WORK | `open_ended`, nominal `duration_s` 180, `min_s` 90, `max_s` 300 |
| Stage n Gun line | WORK | `open_ended`, nominal 120, `min_s` 60, `max_s` 180 |
| Checkpoint n | RECOVERY | 60 s, ERG 50% for everyone |
| Boss | WORK | `open_ended`, nominal 240, `min_s` 120, `max_s` 360 |
| Cool-down | appended by the PlanValidator (180 s at 50%); the view stays (2.4) | |

Nominal 300 + 3 × (180 + 120 + 60) + 240 + 180 = 1800 s (30 min); at most 2460 s (41 min). The rules read segments from `frame.phase`. Once an objective is done and `min_s` has passed (until then the tank holds: "Regroup"), the game calls `ctx.directives.end_phase(peer)` for every rider in one step; if the platform ends a phase at `max_s`, the rules play the overrun (2.4). It emits `finished` (`victory` or `withdrawn`) only when the boss, the last plan phase, ends.

| Engine | Depot (WARMUP) | Advance | Gun line | Boss |
| --- | --- | --- | --- | --- |
| Diesel | SIM `game`, terrain 0 … +2% | SIM `game`, rolling −3 … +6%; Ram sprints | ERG 90% (Dig in) | SIM `flat`; dodge sprints |
| Dynamo | ERG 50%, `ramp_to_pct` 65 | ERG 55%, `range_pct` [55, 100] (bank) | same | same |
| Steam | SIM `flat`, boiler 3% × pressure | SIM `flat`, boiler 8% × min(pressure, 1); Overpressure sprints | same | same |
| Bulwark | SIM `game`, terrain 0 … +2%; lever drills (Hoist 1%) | SIM `game` + Hoist mode grade 4%; Ram sprints | ERG 90% (lever: Dig, Turret, Hoist) | SIM `flat` + Hoist 4% or 0; dodge sprints |

Terrain is `grade_source: game`, not `course` (which follows the platform's speed model), because the tank stops for obstacles, stalls, breakdowns and the Bulwark's other lever positions; pattern 4 pushes the grade under it. Grades are before difficulty; the governor applies 4.6.6 stacking and the 4.6.8 clamp (its clamp wins if warm-up outlasts the depot). Virtual gears work in every SIM phase (BRIEF 4.5). Every crew size, solo included, rides three blocks of about 3 min tempo plus 2 min at 90%, a climbing ERG or boiler work, 60 s recoveries, then a sprint-heavy boss.

**Enemies of every size shape the workout, not only the super-heavy at the end.** Each stage is a mix of ordinary enemies, and their size tells the rider what effort comes: light tanks are short sprints (a Ram on "Surge to ram", 10 s window), mediums are sustained tempo in the Advance (hold the 76-105% band while they keep station), heavy tanks are a threshold block (the stage's gun line becomes a heavy-tank duel at ERG 90%, 90-180 s), and the Behemoth is the sprint-heavy finale. This changes no mechanic and no safety rule, as long as three things hold: (1) the encounter list is fixed in the mission file, so `effort/plan_builder.gd` knows every segment before the ride starts and the PlanValidator checks the whole plan (enemies never add, lengthen or harden a phase at run time; Tank calls no `replan`); (2) every effort an enemy asks for is one the segment table above already allows: sprints are the rider's own in the SIM Advance, tempo is the Advance band, the heavy duel is the existing 90% gun line, so all targets stay 50-100% FTP, nothing exceeds 105% and no duration counter runs; (3) the segment order and the >= 60 s ERG/SIM spacing stay as they are. A mission that wants more blocks adds whole stages (Advance, gun line, checkpoint), not mid-phase effort changes, and keeps the total within 41 min.

In band (glow, score, bank charging): diesel and Bulwark in SIM 76–105% FTP (Ram sprints count); dynamo in stages and boss, and every 90% gun line: power ≥ 95% of the applied target and cadence ≥ 60; steam building: ≥ 90% FTP, loaded or cycling: cadence ≥ 50; depot and checkpoints: cadence ≥ 60.

Checks (each tested in section 4):
- 4.6.1: every `target_pct`, `ramp_to_pct` and `range_pct` bound is 50–100% FTP (at low FTP the governor lifts targets to its floor, max(30% FTP, 50 W)); nothing exceeds 105%, so no duration counter runs, and the boss (length `max_s` 360, the only phase over 300 s) stays under its 105% cap with every directive. 90% gun lines last ≤ 180 s. The unverified factor 0.85 only lowers targets.
- 4.6.2: a bank update moves ≤ 10 points, sent as three sub-steps 1 s apart: ≤ 3.3% FTP/s, so ≤ 30 W/s up to FTP 900 W; the governor slews any excess. The depot ramp climbs 15 points in 300 s.
- 4.6.3: rescue arms in dynamo phases while the applied target (after the 0.85 unverified factor) is ≥ 60% FTP, and in every 90% gun line (76.5% applied when unverified); staggers in 2.4.
- 4.6.6: steam 8% × difficulty ≤ +8%; diesel (−3 … +6%) × difficulty; Bulwark (6 + 4)% × difficulty ≤ +10%; all inside the default range −5 … +10% before haptics, and ≤ +13% < +16% with the largest haptic (+3%, 2.7).
- 4.6.8: depot ERG 50–65%, SIM 0 … +3% before difficulty, no haptics; `drill` keeps every limit (2.9).
- BRIEF 4.5: the platform ramps each ERG ↔ SIM switch; per rider they are ≥ 60 s apart (no PlanValidator 30 s warning). The closest pair brackets a checkpoint (60 s of ERG between SIM segments); Advance → Gun line is ≥ 90 s after the Advance starts; Boss → cool-down ≥ 120 s after the boss starts.

Directive patterns (`ctx.directives`, `source: "tank"`; 1–3 are `request`s with `duration_s` 0, holding until superseded or the phase ends):
1. Bank: `{mode: ERG, target_pct: 55 + 45 × (1 − bank/100), reason: "bank"}` every 5 s in sub-steps, inside `range_pct`; none in the depot or checkpoints.
2. Boiler: `{mode: SIM, mode_grade: 8% × min(pressure, 1) (3% × pressure in the depot), reason: "boiler"}`, only in that rider's SIM phases (never in checkpoints or the cool-down), ≤ once per second; increases ≤ 0.5% per step; decreases, including the drop to 0 when a shell latches, go in one step; 0 while loaded or cycling.
3. Hoist (Bulwark): `{mode: SIM, mode_grade: 4% (1% in the depot), reason: "hoist"}` reached at +1%/s while on Hoist in a SIM phase; 0 on leaving. In a gun line (ERG 90%) Hoist sends nothing and lifts on the rider's ERG work (4 kJ per heavy shell, 2.4).
4. Terrain: `course_grade(peer, pct)` at 2 Hz in `grade_source: game` phases, the grade under the tank.
5. `cadence_band(peer, 60, 120)` at each segment start; (50, 120) for a loaded or cycling loader.
6. Haptics (2.7). 7. `end_phase` (above). Nothing in the cool-down.

Ram, dodges and Overpressure send nothing; the rider sprints in the phase's own SIM. They are unavailable in WARMUP phases and the first 300 s (ability_1 and `surge` do nothing there), and no sprint prompt shows in WARMUP or ERG phases.

### 2.4 Rules and mechanics

Pure `step(state, inputs, dt)` classes at 0.05 s, using only `ctx.rng`, configured by parsed dictionaries. Units: art px, game metres, seconds, P_eff watts. Numbers live in `content/tank/*.json`; these starting values are tuned by G2 within ±50% to meet T1–T5.

Drive (diesel; Bulwark on Drive):
- BRIEF 3.11 speed model with m = scaling-mode rider mass + 8 kg, CdA 0.5 m², the terrain grade under the tank; identical in all tanks. The world scrolls at 0.4 × game speed, 20 art px per visual metre (80% FTP on the flat ≈ 8.2 m/s ≈ 66 px/s).
- Evasive: while the driver is in band, enemy hit chances × 0.7.
- Ram (ability_1, or `surge` on "Surge to ram"; SIM only; 30 s cooldown): a 10 s window. Reaching a light tank or obstacle within 120 px while the sprint rule holds (≥ 1.2 × FTP over the last 3 s, BRIEF 3.5) destroys it; otherwise 10 HP and a 5 s stall. Obstacles (wire, wrecks) stop the tank until a heavy shell, three light shells or a Ram.
- Dig in (gun line): tracks locked; the dozer blade raises a mud berm, +1 HP per 250 J of P_eff in band, max 40, absorbing hits first; when the last gun falls the blade shoves the tank traps aside. Rescue: the berm stops growing.
- Boss: the tank holds position; a Ram is a 24 px lunge, and one with the sprint rule held ≥ 3 s inside the main gun's 6 s telegraph makes that shot miss.

Dynamo (gunner):
- Bank 100 units, +1 per 150 J of P_eff in band (1.67/s at 250 W). Drains: 1.5/s stabilizer while an enemy is in range, 0.5 per degree of elevation, 15 per traverse, 25 per Rampart hoist (always heavy shells), 2 per Citadel secondary shot (secondaries stop below 10).
- Elevation 8°/s and traverse 2.5 s at ≥ 50 units, linear to 2°/s and 8 s at 0; dispersion ±0.5°, ±1.5° below 20 units; Rampart hoist 10 s at ≥ 50 units, 20 s at 0.
- In the depot the bank fills to 100% on a script and the target follows the plan's ramp. Rescue: turret frozen, bank not charging, toast "Dynamo stalled".

Steam (Citadel loader):
- Pressure fills with P_eff; 100% = 6 kJ (24 s at 250 W). At 100% the boiler holds for a 5 s window with "Surge to overpressure" shown; without a surge in it, a heavy shell latches when the window ends and rides the hoist to the breech. In WARMUP phases and the first 300 s there is no window: the shell latches at 100% at once. Pressure can't build again until the shot plus a 6 s breech cycle. Confirm at ≥ 40% latches a light shell. In checkpoints pressure holds (it neither builds nor bleeds).
- Overpressure (ability_1, or `surge`, inside the window): pressure builds from 100 to 150% on 3 kJ counted only while the sprint rule holds, and otherwise bleeds 2%/s toward 100%; the shell latches at 150% or after 30 s. A shell latched at 150% deals Overpressure damage (double); below 150% it is a heavy shell. The mode grade stays 8% (2.3: 8% × min(pressure, 1)); W′ pays.

Bulwark gearbox (solo):
- Lever Drive (Dig at a gun line), Turret, Hoist; a move takes 1 s with no power anywhere; `swap` cycles, left and right step. Off Drive the tank coasts. Turret slews at full speed from P_eff ≥ 200 W, linear below. Hoist: 4 kJ lifts a heavy shell (in a gun line from the ERG work, with no mode grade), confirm at ≥ 40% latches light; 6 s breech cycle.
- Auto-lever (default on): Hoist when unloaded with a target in range; Turret when loaded and > 0.5° off or facing away; else Drive. Dwell ≥ 3 s; in an Advance, Drive whenever nothing is within 300 px. A manual move suspends it 15 s; a breakdown forces Drive. Rescue (gun line): nothing gets power.

Gun:
- The main turret faces right or left; traverse flips it. Elevation −5 … +30°. Shells are projectiles from the muzzle anchor in `assets/tank/rigs.json`, 360 art px/s, gravity 300 px/s²; tune v0 so the 30° range is ≥ 1.1 × each tank's muzzle-to-edge distance.
- Auto-aim (default on): priority tank destroyer in telegraph, dug-in, medium, light, obstacle, nearer first; lower arc with lead; slews and fires when loaded and within 0.5°. Manual: up/down nudge (auto-aim pauses 5 s), left/right cycle targets (`item` in the Bulwark), ability_2 traverses, confirm fires.
- Damage: light 20, heavy 50, Overpressure 100; splash 16 px at 50%. Mediums take 50% from light shells and secondaries; heavy tanks, tank destroyers and the Behemoth take 25% from them. Heavy and Overpressure shells deal full damage to every target. Citadel secondaries (fore right, aft left): 5 every 3 s at the nearest enemy within 240 px.

Enemies, tanks only; HP and counts × 0.6 (Bulwark), 0.8 (Rampart), 1.0 (Citadel), counts rounded, at least 1:

| Enemy | HP | Behavior | Gun |
| --- | --- | --- | --- |
| Light tank | 30 | rushes to 90–140 px, weaves; some from the rear; rammable | 4 every 4 s, 60% |
| Medium tank | 80 | holds 260–340 px | 8 every 6 s, 70% |
| Tank destroyer | 50 | stops at the screen edge, 4 s glint telegraph, moves after each shot | 15 every 8 s, each shot after the 4 s telegraph, 90% |
| Dug-in tank | 50 | gun line; only the turret above concrete is a hitbox | 10 every 7 s, 75% |
| Heavy tank | 160 | gun line duel: rolls in to 300-380 px and halts, a 3 s muzzle-glow telegraph before each shot, backs off 30 px after taking 50 damage | 12 every 7 s, 75% |
| Behemoth (boss) | 3 bogies × 100, turret 300 | see the mission | main 20; secondary 3 every 5 s, 60% |

- Distances run from the hull's nearer end (its front for enemies ahead, its rear for enemies behind) to the enemy's near edge. A held distance is clamped so an enemy ahead ends at x ≤ 632 and at least 24 px of an enemy behind shows at the left edge (the Behemoth excepted).
- In an Advance enemies keep station relative to the tank; obstacles, gun lines and the boss are fixed in world space. Caps: 16 enemies, 24 shells. Enemy hits roll with `ctx.rng` at fire time; the shell lands on the tank or 20–40 px off.
- Hull 100 HP, +20 per checkpoint. At 0 HP: breakdown (no movement or fire, damage ignored) while the diesel's P_eff repairs 5 kJ (12–30 s), then 40 HP.
- Overrun at `max_s`: an Advance tows the tank to the halt line behind a fade, a gun line falls to a support barrage, the Behemoth withdraws; each costs score.

Mission P0, Ashfall Road (`content/tank/missions/ashfall_road.json`; terrain as [distance_m, grade_pct] points, the `course_profile` format):
- Depot roll-out: from a brutalist concrete depot in a forest clearing onto a muddy country road at dusk, no enemies; drive (0–120 s), traverse and elevation drills on two wrecks (120–240 s), load and fire (240–300 s); one teaching toast per station.
- Stage 1, Poplar Road: open fields, hedgerows and a poplar-lined road past a burning farmstead; 1300 m on −2 … +3%; 2 light rushes, 1 medium, 1 wire barricade. Gun line: 3 dug-in behind a farm wall.
- Stage 2, Kettle Ford (the occasional village): down through orchards, over a stone bridge and up one cobbled street past a church spire and lit windows; 1300 m on −3 … +5%; 2 mediums, 1 tank destroyer, 1 light from the rear, 1 wreck barricade. Gun line: a heavy tank in the village square and 2 dug-in.
- Stage 3, Quarry Ridge: climbing through pine woods and a terraced quarry under power pylons, a sawmill burning below; 1400 m on −3 … +6%; 2 mediums, 1 tank destroyer, 2 lights (one from the rear). Gun line: a heavy tank on the ridge, 2 dug-in and a tank destroyer.
- Boss, Foundry Gate (flat): on the valley floor at the gate of a small, lamp-lit foundry town, the one town of the trip; the Behemoth, its 320 px hull partly past the right edge. Phase 1: while a bogie stands it creeps toward the tank at 2 px/s until 120 px away; each broken bogie pushes it back 24 px. Phase 2: immobile; shoot the turret. Main gun every 35–45 s (25–35 s in phase 2) after a 6 s telegraph (muzzle glow, "Surge to dodge").
- Cool-down (kind COOLDOWN, 180 s): the view stays; the tank rolls through the broken gate into the town's lamp-lit streets (or back up the road, if the Behemoth withdrew), no enemies, machinery on each rider's cadence; no score, nothing sent.

Tuning targets:
- T1: compliant Autopilot crews of 1, 2, 3 (seeds 1–3): every Advance 150–240 s, gun line 80–160 s, boss 180–330 s; no overrun; ≤ 1 breakdown; grade ≥ B.
- T2: the dynamo's applied target spends ≥ 30 s above 80% FTP per stage and ≥ 60 s in the boss, and is back to ≤ 65% within 120 s of a fight's end.
- T3: a compliant loader builds each heavy shell in 18–35 s (the 5 s window included) and gets ≥ 6 s at grade 0 per shell.
- T4: a compliant solo rider spends ≥ 60% of each Advance on Drive.
- T5: mean score falls strictly from 100% to 85% to 70% compliance.
- T6: every stage has at least one light-tank sprint prompt and one medium during its Advance; stages 2 and 3 end in a heavy-tank duel at the gun line lasting 90-180 s for a compliant crew.

### 2.5 Autopilot and zero input

The defaults play every station with no input: the diesel drives on watts and digs in, auto-aim aims and fires, the boiler latches a heavy shell at 100% (when the window ends, 2.4), the auto-lever runs the Bulwark. `autopilot/autopilot.gd` (`autopilot_intents()`) adds rear traverses, obstacle shots when no enemy is in range, never an early latch, and never a manual lever; it never Rams, dodges or Overpressures (a human `surge` on a prompt still can) and never changes effort targets (BRIEF 3.5). A human counts as Autopilot until their first `lever`, `aim`, `target`, `traverse`, `fire` or `latch` intent; `ram` and `over` never end it, and `local_intents` turns `surge` only into `ram` or `over`, never `fire` or `latch`. With Tank last played, a solo `pedal_start` plays `ashfall_road` in the Bulwark (BRIEF 3.5). Results use the platform's pedal-scan.

### 2.6 Multiplayer and network

The host simulates everything (BRIEF 5). Intents in `Telemetry.intents` (`lever`, `aim`, `target`, `traverse`, `fire`, `latch`, `ram`, `over`) are accepted only from the rider on the matching engine, at most 5 per second per peer, applied next tick. `snapshot()` at 10 Hz is full state in compact integer arrays (tank; riders, each with engine, raw W, cadence, in band, rescue and AFK; enemies, shells, obstacles, gun line, boss parts), ≤ 4 KB of JSON at the caps; `apply_snapshot` casts numbers to int. Events (`segment`, `rotation`, `shot`, `hit`, `kill`, `ram`, `dodge`, `breakdown`, `repaired`, `overrun`, `boss_phase`) go to every peer, ≤ 10 messages a second, in the same order on all peers (BRIEF 7). `client_predict` drives your own room's machinery and glow from local telemetry; the rest renders from snapshots with 100 ms interpolation, the turret's slew hiding 100–200 ms. Each peer raises its own rider's prompts and toasts ("Surge to ram", "Surge to dodge", "Surge to overpressure", "Dynamo stalled") from snapshots, events and its local telemetry, because `ctx.hud.toast` and `banner` take no peer. Full snapshots make reconnects need no special path.

### 2.7 Haptics

Within BRIEF 4.6.6, only to riders in a SIM phase. Each haptic is a `request` `{mode: SIM, haptic, duration_s, reason, source: "tank"}`:

| Event | Receivers | `haptic` | `duration_s` | `reason` |
| --- | --- | --- | --- | --- |
| Hit of ≥ 8 damage | every rider in SIM | 2.0 | 1.5 | `hit` |
| Behemoth main-gun hit | every rider in SIM | 3.0 | 2.0 | `boss_hit` |
| Ram impact | the driver | 3.0 | 1.0 | `ram` |

The governor multiplies `haptic` by the rider's intensity setting (BRIEF 4.6.6); the game never scales it. A haptic changes only the haptic term: the boiler, hoist and terrain grades stay, and its expiry ends only the haptic. If `docs/GAME_SDK.md` gives haptics no channel of their own, send each haptic with the rider's current `mode_grade`, re-send the boiler or hoist directive when it expires, and record that in an ADR.

Never in WARMUP segments, the first 300 s or the cool-down, or to an ERG rider. A rider who opted out never feels one: the game skips them when `PlayerSlot` carries the setting (`docs/GAME_SDK.md`), and their governor drops any that arrive (BRIEF 4.6.6). The game drops a haptic that would start within 15 s of the end of the receiver's last one (the governor enforces its own cooldown too). The largest, +3% for 2 s, is inside +3% for 8 s. Terrain (course grade) and the boiler (mode grade) are not haptics.

### 2.8 Results and progression

- Mission outcome: the ride itself never fails (the workout always runs to the cool-down), but the mission can: it is **won** when the Behemoth dies (`finished("victory")`) and **lost** when the boss phase reaches `max_s` and the Behemoth withdraws (`finished("withdrawn")`). The results screen says which ("Foundry Gate taken" or "The Behemoth got away"); overruns, breakdowns and a lost mission cost score and grade, never effort.
- Score = 1000 × (0.3 band + 0.2 accuracy + 0.3 objectives + 0.2 survival): band = crew mean of WORK time in band (0 with no WORK time); accuracy = main-gun hits / shots, or 0 when no shot was fired; objectives = 0.6 × stages completed without overrun / 3 + 0.4 if the Behemoth died; survival = max(0, 1 − 0.25 × breakdowns). S ≥ 900, A ≥ 800, B ≥ 650, C ≥ 500, else D.
- `results()`: the grade, the platform rows (kJ, average %FTP, time in band), time per engine, Rams, berm absorbed, shots, hits, accuracy, shells by type; team: HP per segment, breakdowns, overruns, kills by type. XP = round(kJ / 10) + S 60, A 40, B 25, C 10, D 0.
- Unlocks (hull finishes, `content/tank/cosmetics.json`, reported as `GameResults` cosmetic unlocks): Soot on the first finish, Rust at B, Ash at A, Mud stripe at S, Brass machinery for a Behemoth kill with no breakdown. `results()` lists the unlocks each rider's session earned (finish, grade, Behemoth kill with no breakdown); each peer's module adds only its own rider's XP and those unlocks to `ctx.progress` in `apply_progress` (BRIEF 3.6), which the platform calls once on every peer, and reports as new only those it didn't already hold; nothing goes to the host. Equipping a finish on the hull is P1 (the garage's finish picker, 2.9).
- `phase_changed` at every segment start, unless `docs/GAME_SDK.md` says the GameHost emits it (the index is the same for every rider, 2.3); FIT laps come from each phase's `lap`, so Tank emits no `lap_marker` (it would double them).

### 2.9 Content

- P0: Ashfall Road (2.4). `drill` for e2e, 130 s inside warm-up limits: depot 30 s, a fixed 70 s skirmish (kind WARMUP) against 2 light tanks and 1 medium, a 30 s checkpoint at 50%; diesel terrain 0 … +2%, dynamo ERG 50% in the depot then 55% with `range_pct` [55, 65], boiler 3% × pressure, no haptics, `rotation` ignored, at most one mode switch per rider. Files: `tanks.json`, `stations.json`, `enemies.json`, `missions/*.json`, `scoring.json`, `cosmetics.json`, `strings.csv` (`TANK_*`), validated at load.
- P1: a garage between missions (scrap buys +10 HP armor ×3, +20 bank units, −10% boiler energy, the finish picker); Viaduct Crossing (a river viaduct, an armored train as the gun line); two tanks in one lobby (up to 6 riders, the second on a rear ground line 40 px higher, enemy scales summed).
- P2 notes: tank duels across a ruined town square.

## 3. Presentation

Art direction (there are no reference images; this text is the direction): dark, desaturated and lit from within. The scene is a 2.5D diorama in side view: flat sprite planes stacked in depth (sky, far hills and woods, near fields or a village, the tank's plane with enemies and props, foreground debris), each in parallax and graded by distance.

- **Depth of field:** only the tank's plane is sharp. Planes behind it blur and fade into haze and smoke the farther they are; the foreground debris blurs strongly and darkens. The Compatibility renderer has no depth-of-field post effect (`addons/wattlands/world3d/README.md`), so fake it cheaply: blur each plane once at load (a separable blur into a cached texture per plane) and tint it toward the haze colour; no per-frame full-screen blur. Record the blur radii in an ADR.
- **Light:** lamps, the diesel cylinders, the dynamo's arc, the open firebox, muzzle flashes, burning farmsteads, a village's lit windows, a foundry town's lamps and each rider's wall lamp glow through the dark with soft halos (additive glow sprites, or `PointLight2D` if it holds 60 fps on Compatibility: measure it). Some lights are cold (blue-white arc light, moonlit steel), some warm (amber lamps, fire). Everything else stays low in saturation; lights are the only near-saturated pixels. Flooded craters and wet steel catch the lamps' reflections.
- **Particles:** shooting and exhaust are particle effects, not only sprites. Firing: a muzzle flash that lights the scene for a few frames, a smoke ring and drifting powder smoke, sparks, dust kicked up under the muzzle, recoil shake on the hull, a glowing tracer on the shell, and brass casings ejected and tumbling with a glint (with the spent-casing sound). Impacts: sparks and hot fragments on armour, dirt sprays and clods on the ground, a smoke column from a wreck. Exhaust: the diesel's stacks puff black-grey smoke at a rate and thickness set by that rider's watts (a sprint is a visible black plume), with a faint heat shimmer; the steam engine vents white plumes per stroke and a hiss cloud when a shell latches; the dynamo throws blue sparks; track dust and mud flicks at tank speed. Particles on the tank's plane are sharp; those that drift back or forward take the depth-of-field blur and haze of their plane and are lit by the nearby glows. Use pooled `CPUParticles2D` (or the view's own pooled sprites), cosmetic randomness from the view's own RNG seeded from `ctx.seed`, and caps (about 400 live particles, fewer emitters when the frame time rises) so 60 fps holds on integrated graphics; the view only reads state, and particles never affect the rules.
- **Keep:** slab-sided riveted hulls and boxy turrets in grey-black, rust and soot; a landscape of rolling fields, hedgerows, poplar rows and pine woods under smoke, now and then a village (church spire, stone bridge, cobbles) or a small foundry town; fires, black smoke, mud, flooded craters and wire on stakes; the cutaway engine rooms with walls between them, dark, so each engine's own light marks it; the rider's wall lamp glowing in their colour when in band; visible links (diesel chain to the drive sprocket, a dynamo shaft to the turret ring, a hoist rail from the steam engine to the breech); each tank longer than the last; enemies with their own silhouettes and sizes (low wedge lights, tall slab mediums, long twin-bogie heavies, turretless casemate destroyers).
- **Not chunky pixel art:** sprites stay low-resolution art pixels at 640 x 360 with nearest filtering, so shapes read at a glance, but with soft, muted shading instead of a flat 16-bit look; the runtime blur, haze and glow add the in-between tones.

Layout: `view/tank_view.gd` returns the PixelViewport's Node2D and only reads state. Ground line y 296, the tank's rear at x 16, enemies entering right (rear rushers left). The HUD covers only y 0–60 and 300–360.

Cutaway: rooms are opaque backdrops at rects from `assets/tank/rigs.json` with code-drawn riveted frames; machinery sprites sit on them. `SpinningPart`/`SlidingPart` speed = cadence / 120 (0–1), brightness by %FTP. Diesel: pistons, crankshaft, flywheel, cylinder glow and exhaust by watts, the track chain at tank speed. Dynamo: armature, sparks by watts, capacitor jars showing the bank, the turret-ring shaft while slewing. Steam: flame by watts, gauge needle, a puff per pedal stroke, the shell cradle climbing the hoist rail with pressure to reach the breech at 100%. Bulwark: the lever points at its position; only the active output shaft spins. In band, the room brightens and a wall lamp in the rider's color lights with the rider's shape badge (BRIEF 3.9), pulsing at cadence (white sprites tinted at runtime). Wheels spin with tank speed under a code-drawn track belt; wrecks darken and smoke; the berm is a growing mud polygon; the trajectory arc is dots in the gunner's color. `ParallaxStrip` factors (each plane with its blur and haze from the art direction above): sky 0.05, far hills 0.2, near fields or village 0.5, ground 1.0, debris 1.3, alternating normal and flipped copies so edges match (if the kit's `ParallaxStrip` has no mirror option, the view tiles flipped copies itself).

`assets/tank/art.json`: `endpoint` `openai/gpt-image-2.5/sunburst/text-to-image`; `style` "Side-view 2D game sprite, orthographic, low resolution with soft muted shading, desaturated colours and deep shadows. Dark brutalist alternate-history 1940s: riveted steel, soot, rust, mud, wet surfaces. Light sources are bright glowing shapes, warm amber or cold blue-white. Single object, centered. No people, figures or faces; no text, letters, numbers, flags, insignia, emblems, markings or logos."; `palette` (32, desaturated; adjust after the style check, never more) `#07080a #0e1013 #161a1e #1f2429 #2a3036 #363d44 #444b52 #565c62 #6c7176 #878b8f #a7aaac #cfd0cf #17130f #241d17 #33291f #443628 #574634 #6b5842 #2b2a24 #3d3c33 #545246 #3a2a24 #5a3a2e #7d4f3a #e8743a #ffb35c #ffd99a #fff3d6 #2f4a5e #5d86a3 #9fc4dd #e6f3fb` (greys, muted browns and olives, rust, and the only bright ones: fire and warm lamp light, cold arc light). 61 sprites, transparent unless opaque; tanks face right, enemies left; one object per sprite except the picker card, wheels and gears face-on:

| Group | ids and sizes (art px) |
| --- | --- |
| Hulls (skirts cut flat at the bottom; no wheels, tracks or turret) | `hull_bulwark` 192×72, `hull_rampart` 240×76, `hull_citadel` 288×80 |
| Turrets (no barrel) | `turret_bulwark` 88×36, `turret_rampart` 104×40, `turret_citadel` 120×44, `turret_secondary` 44×22 |
| Rooms (opaque back walls, empty middle) | `room_bulwark` 128×48, `room_diesel` 96×48, `room_dynamo` 80×48, `room_steam` 88×48 |
| Machinery | `diesel_block` 56×32 (empty cylinder windows), `flywheel_large` 36×36, `flywheel_small` 20×20, `gear_large` 24×24, `gear_medium` 16×16, `gearbox` 32×28, `dynamo_housing` 40×28, `dynamo_armature` 20×20, `spark` 16×16, `boiler` 40×32, `firebox` 20×16, `firebox_flame` 16×16, `governor` 16×20, `steam_puff` 16×16, `shell_rack` 32×40 |
| Running gear | `road_wheel` 18×18, `drive_sprocket` 22×22, `idler_wheel` 20×20 |
| Enemies | `enemy_light` 80×40, `enemy_medium` 104×52, `enemy_heavy` 136×60, `enemy_destroyer` 112×44, `enemy_dugin` 72×36 (behind a concrete revetment) |
| Boss | `boss_hull` 320×100, `boss_turret`, `boss_turret_broken` 152×56, `boss_bogie`, `boss_bogie_broken` 64×32 |
| Props | `prop_tank_traps` 64×24, `prop_wire` 64×20, `prop_wreck_barricade` 72×32, `prop_crater` 48×16, `prop_rubble` 40×16, `depot_gate` 160×120 |
| Backdrops | `bg_sky` 640×200 (opaque), `bg_hills_far` 960×120 (hills and woods under smoke), `bg_fields_near` (Poplar Road), `bg_village_near` (Kettle Ford), `bg_quarry_near` (Quarry Ridge), `bg_town_near` (the foundry town), `bg_depot_near` 960×140, `bg_ground` 960×80 (opaque), `fg_debris` 960×48 |
| Picker | `picker_card` 320×180 (opaque): the Citadel in cutaway rolling right along a country road past a burning village at dusk |
| Effects (animated by scale, alpha, flips, particles) | `muzzle_flash` 32×20, `explosion_large` 64×64, `explosion_small` 32×32, `smoke_puff` 16×16, `fire_small` 16×16, `dirt_spray` 32×24 |

- Code-drawn in palette colors (under 16 px, or lines): barrels, pistons, crankshaft, rods, chains, shafts, track links, shells, capacitor levels, needles, the lever, the hoist rail and cradle, spark arcs, trajectory dots, room frames, the berm.
- Process: (1) `--dry-run`, record the estimate (about $0.07 per sunburst image, so about $4 a pass) and check that every planned request keeps its sprite's aspect within 2%; a strip the endpoint can't match becomes a narrower segment at the widest aspect it allows (for example `bg_ground` 240×80 and `fg_debris` 144×48 at 3:1), which `ParallaxStrip` repeats with flips; record the sizes in an ADR; (2) style check with `endpoint` set to `openai/gpt-image-2.5/flare/text-to-image` and `--only=hull_citadel,room_diesel,diesel_block,enemy_medium,bg_village_near,explosion_large`: pixelate, look at the PNGs at 3×, fix style and palette, then set `endpoint` back to `openai/gpt-image-2.5/sunburst/text-to-image`; (3) full sunburst pass and pixelation, making sure pixelate uses the sunburst result rather than the flare draft for the six style-check sprites (`docs/ART_PIPELINE.md` says how it picks); (4) look at every sprite, reroll failures (people, text, insignia, wrong facing, wheels on a hull, mush, a squashed aspect) at most twice, each time with a changed prompt (an unchanged input returns the cached or reused result, BRIEF 3.10); (5) measure anchors (muzzles, turret rings, wheel lines, cylinder windows, room rects) into `rigs.json`; (6) credit OpenAI's GPT Image 2.5 through fal in `docs/credits.d/tank.md`. Stop at $15.
- `view/placeholder_art.gd` draws any missing sprite at its size from palette shapes and logs once. No test depends on generated art.

HUD (`hud_spec()`): kit widgets (BRIEF 3.9) bottom left: power gauge with the target band (ERG: applied target; SIM: the engine's band), cadence with the band from `cadence_band`, W′, gear in SIM, big watts. Top: phase timeline with preview, hull HP, teammate strip (color and shape chip, engine icon, %FTP, in band, rescue, AFK, reconnect), boss bars. Kit toasts and banners carry the prompts "Surge to ram", "Surge to dodge", "Surge to overpressure". Tank widgets bottom right: the station card (diesel speed, distance to halt line, berm; dynamo bank and target; steam dial with 40/100/150% marks and the loaded shell; Bulwark lever with auto marker and hoist progress) and the objective line ("Gun line 2/4"). Hull HP, own watts and the station's key number ≥ 48 px at 1080p. Each peer sets its own diesel or Bulwark rider's SIM band, 76–105% FTP, with `ctx.hud.power_band` (BRIEF 3.6). The steam engine's open-ended band shows on the station card only, so the `erg` mock keeps riding 90% FTP there. Where the kit can't show a Tank value (such as an engine icon that `teammate_status` can't carry), the hud agent draws it in a Tank Control widget instead.

Audio: diesel rumble by cadence, dynamo whine by armature speed, steam chuff per stroke and latch hiss, cannon boom, shell whistle, spent casing/brass, explosions, track clank, lever clunk, hoist ratchet; your own station loudest. Strings in `content/tank/strings.csv`.

## 4. Testing and gates

Unit tests (GUT, `tests/games/tank/`) cover every rule and number in 2.2–2.8, at least: plans for crews 1–3 × `rotation` on/off × FTP {80, 200, 400} × verified/unverified plus `drill` (the PlanValidator passes with no switch warning; shared segment boundaries; rotation tables; `ramp_to_pct`, `range_pct` and `grade_source` per 2.3; with each open-ended phase at its min and its max, per-rider ERG ↔ SIM switches ≥ 60 s apart; the first 300 s within 4.6.8); `end_phase` (all riders, one step, never before `min_s`), overrun at `max_s`; the first run never picks Tank; the bank, boiler, gearbox, terrain-grade and cadence-band models and every directive's exact fields; no SIM-mode directive is ever sent in an ERG phase (Bulwark gun lines, checkpoints); speed-model wiring against the BRIEF 3.11 oracle; Ram, dodge, berm, breakdown, overrun, reserve and all-AFK; Ram, dodge and Overpressure do nothing in WARMUP phases and the first 300 s; ballistics against the analytic arc, the solver within 0.5° with lead, the range rule; damage and enemies; haptic rules; results, XP and unlocks in `ctx.progress`; snapshot round trip, ints and ≤ 4 KB at the caps; intent ownership; a human whose only intents are surge-sent `ram` and `over` keeps Autopilot's rear traverses and obstacle shots; every tank's view built headless from fixtures; a placeholder per sprite id; no missing string keys.

Static tests (`tests/games/tank/static/`): nothing under `src/games/tank/` references `TrainerController`, `SafetyGovernor`, `FtmsClient`, `write_control`, `set_target_power`, `set_simulation` or `set_resistance`; `rules/`, `effort/` and `combat/` use no `Time.`, `OS.get_ticks*`, global `randi`/`randf` or `RandomNumberGenerator.new()` outside `ctx.rng`; `art.json` has ≤ 32 colors and keeps the no-people, no-text clause.

Simulation matrix: `bash tests/games/tank/sim/run_sims.sh` runs `tools/run_game_sim --game=tank --content=<id> --players=<n> --bots=0 --rider=<profile> --sim-speed=200 --seed=<n> --report=build/tank/sims/<name>.json` with the mock rider profiles and flags in `docs/GAME_SDK.md`. Human slots that send no intent play as Autopilot (2.5), so S1 needs no Autopilot flag. The runs also need: crews 2–3 run as a host with that many riders, so a 0 W rider goes AFK instead of pausing the run (BRIEF 4.6.4); S5's cadence collapse to 30 rpm, triggered by segment and applied target rather than clock time (Tank's segments are open-ended); haptics off for one slot (S6); and, in each report, every rider's applied target, mode and grade at 1 Hz, every directive as requested and as applied with `clamped_by`, the snapshot hashes, and the FIT files written. Add whatever is missing as one `platform:` change with tests. `node tests/games/tank/sim/check_sims.mjs build/tank/sims` asserts:

| # | Run | Assertion |
| --- | --- | --- |
| S1 | `ashfall_road`, compliant, Autopilot, crews 1–3, seeds 1–3 | T1; T2 (crews 2–3); T3 (crew 3); T4 (crew 1) |
| S2 | crews 1 and 3 at 0 W | crew 3: no kill by crew fire, every stage ends by overrun, grade D; crew 1: paused in the depot no later than 10 s (+1 tick) after the first `not_pedaling` sample (BRIEF 4.6.4, 7.4); the report's `end_reason` is `paused`, no phase after the depot starts, and its results show no kills and grade D |
| S3 | crew 3 at 100, 85, 70% compliance, seeds 1–3 | T5 |
| S4 | every content and crew, compliant | every applied directive matches 2.3 or 2.7 and is clamped; no SIM-mode directive in an ERG phase; no ERG target above 100% FTP in any plan phase or directive; no applied ERG target above 100% FTP at any time, and no SIM → ERG entry above the planned or directed target of the phase it enters (or the floor, if that is higher; BRIEF 4.5, 7.1); no haptic in the first 300 s or to an ERG rider; nothing sent in the cool-down; per-rider switches ≥ 60 s apart; one FIT lap per plan phase with `lap` true (the appended cool-down counts only if the platform marks it so) |
| S5 | crew 3: cadence drops to 30 rpm in a dynamo stage once the dynamo's applied target is ≥ 60% FTP (verified FTP; the profile waits for it), and in a 90% gun line | rescue, stagger, plan continues |
| S6 | crew 3, haptics off for one slot | no haptic applied to that rider |
| S7 | crew 3, same seed twice | identical events and snapshot hashes |
| S8 | crew 3, enemy counts × 3, as a GUT test in `tests/games/tank/sim/` that steps the GameModule with synthetic compliant riders on `ashfall_road` with every count × 3 in memory (a stress content in `contents` would show in the picker; `tools/run_game_sim --override` is an alternative) | ≤ 16 enemies, snapshots ≤ 4 KB |

The rules step takes ≤ 1 ms at the caps.

Gates (all must pass): (1) Tank unit and static tests under BRIEF 7's strict rules; (2) `tools/godot.sh --headless --path . -s tools/check_scripts.gd`; (3) SDK conformance (Autopilot human slots at 1 and 3 riders, as `bots` is false), with `tank` listed by GameRegistry and present in the conformance log, so the gate can't pass with Tank hidden; (4) the simulation matrix; (5) `tools/fit_check`, invoked as BRIEF 3.8 or `docs/GAME_SDK.md` documents, on every FIT file the sims wrote, at least one per run that reaches the results (if `tools/run_game_sim` writes none, add FIT output as a `platform:` change); (6) `node tools/e2e/run.mjs --games=tank` (host plus two clients, the Citadel, Autopilot, mock trainers, `drill`); (7) the full platform suite (`tools/run_tests` ≥ the G0 baseline plus the Tank tests) and `node tools/e2e/run.mjs --games=<the G0 list>,tank`, with every game that passed at G0 still passing.

P1 checks: `tools/screenshot --game=tank --content=ashfall_road --at=<s>` at 60, 400, 560 and 1500 s (depot, skirmish, gun line, boss) solo; a shot that lands in another segment (the HUD's phase label shows which) is retaken at an adjusted time, at most twice, and recorded; use the tool's fast-forward option if `docs/GAME_SDK.md` documents one. Shoot the Citadel at 3 riders if the tool can set the player count (`docs/GAME_SDK.md`); otherwise shoot solo only and record it. Look at each: every engine identifiable at a glance, links and glow visible, the HUD clear of the tank, no people, text or insignia. Then 60 s windowed at the caps: mean and 1%-low frame times against 16.7 ms.

## 5. Orchestration

Opus 5.5 for every agent; no two agents edit one file in parallel; every Godot run goes through the `tools/godot.sh` lock; run the end-to-end gates (section 4, gates 6 and 7) only while no builder, helper or fixer is running Godot, because one e2e run holds three Godot slots at once (BRIEF 2).

G0 setup (you, sequential):
1. If the only uncommitted files are Simon's planning files under `docs/games/` or `docs/concept/`, commit them unchanged to `main` in one `docs:` commit and record it in `docs/decisions/tank.md` and the final report. Check `main` contains `v0.1.0` and a committed `docs/games/tank.md`, and the tree is clean; if `game/tank` doesn't exist, cut it from `main` and run `tools/new_game tank`; if it exists, check it out and resume, skipping every G0 step its commits already cover, never re-running `tools/new_game` over `src/games/tank/`, and never moving or re-creating `tank-g0`.
2. Read the SDK docs, `_template`, `workout`, `world2d` and the art pipeline. Check that the SDK names this brief uses (PlanPhase fields, the `options` entry fields, `course_grade`, `end_phase`, `cadence_band`, `frame.phase`, `ctx.options`, `ctx.progress`, `ctx.hud.power_band`, `local_intents`, `apply_progress`, `picker_image`) match `docs/GAME_SDK.md`; if one differs, use the doc's spelling and record it. Also record what the doc says on: how `hud_spec()` places kit widgets, sets the power gauge's band in SIM, fills the teammate strip and posts toasts and banners; how a client's actions become `Telemetry.intents` and how the module learns its local peer id; how `course_grade`, `cadence_band` and `end_phase` reach a remote rider's governor; whether a dropped peer gets `on_afk`; how a haptic stacks with a mode grade (2.7); and how `apply_progress` is called on host and clients (2.8). Record which mock rider profiles and `tools/run_game_sim` flags exist and what it sets per rider.
3. Run the full platform suite and `node tools/e2e/run.mjs --games=<every registered game except tank>`; record the baseline (counts, and which games' e2e pass) in `docs/decisions/tank.md`. If red, fix only what blocks Tank P0 under the platform-change policy.
4. Record, without printing values, whether `FAL_KEY` and `WATTLANDS_ALLOW_ART` are set, before and after sourcing `tools/env.sh` (or `.ps1`). If sourcing clears either, art runs export `WATTLANDS_NO_HW_CONTROL=1` and `WATTLANDS_NO_NETWORK_INTEGRATIONS=1` directly instead of sourcing it; record that.
5. Write the contracts with doc comments: `game.json`; `src/games/tank/contracts/` (state, tank, station, enemy, shell, segment; intent, event and snapshot schemas; content schemas); `assets/tank/art.json` (style, palette, 59 ids and sizes, draft prompts) and `rigs.json` with estimated anchors; `content/tank/strings.csv`; `tests/games/tank/fixtures/`; stubs for `tank_game.gd` and `view/tank_view.gd`.
6. Commit and tag `tank-g0` (only if the tag doesn't exist).

G1 build: eight builders in parallel, each on `game/tank-<agent>` from `tank-g0` in its own worktree. Each prompt names this file's sections, the owned paths, the contracts, the test command and the report format. Builders touch only their paths, adapt to an imperfect contract inside them, and request strings or contract changes in their report.

| Agent | Owns | Builds |
| --- | --- | --- |
| effort | `src/games/tank/effort/`, `content/tank/stations.json`, `tests/games/tank/effort/` | plan builder, rotation, bank, boiler, gearbox routing, terrain grade, cadence bands, directives, haptics |
| rules | `src/games/tank/rules/`, `content/tank/{tanks,scoring,cosmetics}.json`, `tests/games/tank/rules/` | segments, phase ends, drive, Ram, berm, obstacles, damage, breakdown, overrun, reserve, scoring, XP |
| combat | `src/games/tank/{combat,content}/`, `content/tank/enemies.json`, `content/tank/missions/`, `tests/games/tank/combat/` | content loader, ballistics, auto-aim, enemies, encounters, boss, Ashfall Road, `drill` |
| module | `src/games/tank/tank_game.gd`, `src/games/tank/{autopilot,net}/`, `tests/games/tank/module/` | GameModule wiring, options, Autopilot, snapshots, events, client prediction, results, `ctx.progress` |
| art | `assets/tank/` except `audio/`, `src/games/tank/view/placeholder_art.gd`, `tests/games/tank/art/`, `docs/credits.d/tank.md` | generation, pixelation, review, anchors, placeholders, credits (audio credits from view's report) |
| view | `src/games/tank/view/` except `placeholder_art.gd`, `src/games/tank/audio/`, `assets/tank/audio/`, `tests/games/tank/view/` | parallax, tank rigs, cutaways, machinery, enemies, effects, audio |
| hud | `src/games/tank/hud/`, `tests/games/tank/hud/` | `hud_spec`, station card, lever, objective line, boss bars, prompts |
| qa | `tests/games/tank/{sim,static,perf}/`, `.github/workflows/game-tank.yml`, `src/games/tank/HARDWARE_TEST.md` | sim scripts and checker, static tests, perf scene, CI on Linux, the real-trainer checklist |

Test command: `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/games/tank/<dir> -ginclude_subdirs -gexit -gjunit_xml_file=build/junit_tank_<agent>.xml`, then `check_scripts`, under BRIEF 7's strict rules. Report: `{agent, branch, base_sha, head_sha, summary, files, tests_added, test_command, tests_total, tests_failed, junit_path, script_check_ok, decisions, open_issues, strings_needed, art_spend_usd, contract_change_requests: [{file, change, additive, blocks_p0}], platform_needs: [{need, why, blocks_p0}]}`. Re-run each test_command before accepting a report.

G2 integrate (you plus up to 3 helpers): accept additive contract changes, breaking ones only when they block P0; merge effort, rules, combat, module, art, view, hud, qa in that order, running the Tank tests and `check_scripts` after each; wire `make_view()`, `hud_spec()` and the strings; add `picker_image` to `game.json` once `assets/tank/sprites/picker_card.png` exists; merge decisions into `docs/decisions/tank.md`. Balance: tune content until T1–T5 hold, within ±50% of this brief's values unless an ADR records the sim evidence; stop after six iterations and report misses. Then loop over every gate; progress means fewer failing checks; stop after two rounds without progress or five in all.

G3 review: fresh-context reviewers, one per dimension: safety (plans and directives against BRIEF 4.6, 4.5 and 2.3, haptics against 2.7; any trainer path other than `ctx.directives` is a blocker); effort design (2.3–2.4, the solo training shape, T2–T4); rules, combat, determinism and balance; network (snapshot size, intent ownership, desync, reconnect, AFK); zero input and Autopilot for crews 1–3; presentation (section 3 on screenshots and sprites: no people, text, insignia or flags, ≤ 32 colors in the sprites, desaturated grading, depth-of-field blur and cold and warm glows readable at 60 fps, links readable, HUD clear of the tank, spend ≤ $15); code quality, test gaps and ownership (`git diff main` outside owned paths is only `platform:` commits). Each finding has severity, file and line, evidence, and a failing test, repro command or static test; a separate verifier confirms it before any fix, and only refuted findings are dropped. Findings that need hardware go to `src/games/tank/HARDWARE_TEST.md` rather than being dropped.

G4 fix (parallel fixers by area, then you), at most two rounds: fix confirmed findings with tests and rerun every gate; take final screenshots; write `src/games/tank/README.md` (rules, effort tables, content schemas, tuning knobs, art regeneration, P2 notes); finish `src/games/tank/HARDWARE_TEST.md` (a real-trainer checklist in BRIEF 4.7's format, with expected results and a log template: each crew size's ERG ↔ SIM switches at checkpoints, gun lines and the boss (ERG entered at or below the planned target and slewed up with no spike, including a gun line straight after a Ram sprint); the bank's sub-steps; boiler and hoist grades and the drop at a latch; terrain grades; Ram sprints; rescue in a dynamo stage and a gun line; each haptic); and write `docs/credits.d/tank.md` and `docs/changelog.d/tank.md`. If the Definition of Done is met, merge the latest `main` into `game/tank`, rerun every gate, merge into `main` with `--no-ff` and tag `tank-v0.1.0`; otherwise leave the branch unmerged.

## 6. Definition of Done and final report

- Every P0 item in 2.9 is implemented, reachable from the game picker and tested; every gate in section 4 is green or listed as failing, with nothing weakened.
- A solo rider plays Ashfall Road in the Bulwark to the results with zero input; a host plus one friend plays the Rampart and plus two the Citadel, joining by code, with rotation; the e2e run passes.
- Every plan passes the PlanValidator; every directive is clamped and matches 2.3 or 2.7; no Tank code reaches the trainer except through `ctx.directives`.
- Rides carry a lap per segment and pass `tools/fit_check`.
- All 61 sprites are generated and reviewed within $15, or the rest are placeholders with the reason recorded; none shows people, text, insignia or flags.
- The platform suite is green; Workout and other merged games are unaffected.
- `src/games/tank/README.md`, `src/games/tank/HARDWARE_TEST.md`, `docs/decisions/tank.md`, `docs/credits.d/tank.md` and `docs/changelog.d/tank.md` are complete.
- `game/tank` is merged into `main` and tagged `tank-v0.1.0`; nothing is pushed.

Final report in chat: what was built; every gate's result with numbers (tests total and failed; per sim scenario and crew size, segment times, breakdowns, score and grade; T1–T5 met or missed; the largest snapshot; the e2e duration; frame times); art generated, rerolled and placeholder, and the spend; every `platform:` commit and every deviation with its ADR; what is untested on hardware or Windows; the top risks; the exact commands to play solo with a mock trainer, host, run the tests and the sim matrix, and regenerate the art.
