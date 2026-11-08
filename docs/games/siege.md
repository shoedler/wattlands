# Wattlands: Castellum Rotae game brief

Castellum Rotae (game id `siege`) is a co-op tower-defense game in the Wattlands platform: a pixel-art Roman wheel fort with one road, five stations and simulated projectiles. This brief describes the game as it ships in v1.0.0. The look, the map and the combat were approved in a mockup review (frames from `node src/games/siege/art/mock.mjs`).

Background reading: `CONTRIBUTING.md`, `docs/GAME_SDK.md`, `docs/ARCHITECTURE.md` and BRIEF sections 3.1–3.10, 4.5–4.7, 5, 6 and 7. "BRIEF x.y" refers to `docs/BRIEF.md`.

## 0. Hard requirements

1. Build through the Game SDK only (BRIEF 3.6), and pass `tests/sdk/test_conformance.gd` (with bots, at 1 and 4 players) without changing it.
2. **Presentation `2d`.**
   - The view is a fixed isometric pixel-art view designed at 960 × 540 art pixels (x2 at 1080p, 3.5 px per metre). The canvas flexes with the window at a whole scale (`pixel_flex` min 852 × 480), so there are no black bars (3 "Flex canvas").
   - The art comes from our own CPU rasterizer in `src/games/siege/art/`. It is baked to PNGs in `assets/siege/` and committed.
   - There are no fal calls, no downloaded art and no copied reference material.
   - It runs at 60 fps at 1080p on integrated graphics (BRIEF 3.9).
3. Co-op for 1–4 riders, one great treadwheel each, with bots in empty wheels. It is host-authoritative, with room codes (BRIEF 5).
4. Pedaling first: every phase, the shop and the results work with zero input (BRIEF 3.5).
5. Waves run in ERG and the Overdrive sprint in SIM. Every plan and directive obeys BRIEF 4.6 (2.3). Change the design to fit the governor, never the reverse.
6. The platform saves and uploads rides (BRIEF 3.8), with a lap at every wave and break.
7. Every section 4 gate is green, headless, with MockTrainer riders, bots and Autopilot.

## 1. Ground rules

- Automated runs keep the hardware and network locks (`CONTRIBUTING.md`) and never reach fal. Godot runs only through `tools/godot.sh` or `tools/godot.ps1`.
- The game lives in:
  - `src/games/siege/`, `content/siege/`, `assets/siege/` and `tests/games/siege/`;
  - `.github/workflows/game-siege.yml`;
  - this brief;
  - `docs/decisions/siege.md`, `docs/credits.d/siege.md` and `docs/changelog.d/siege.md`.
- Everything else is read-only for the game. A platform change is allowed only when a P0 item is blocked, and then as a separate small additive `platform:` commit.
- Original designs only:
  - attackers are Egyptian-inspired (linen, dark hair, hide shields, fan standards), with no real insignia;
  - no brands, logos or emblems;
  - no gore.
- Rules are pure classes with `step(state, inputs, dt)` at 0.05 s. Every random draw comes from `ctx.rng` or from a seeded hash in the rules. No `Time.*`, `OS.get_ticks*`, global `randi`/`randf` or `RandomNumberGenerator.new()` in `rules/` or `combat/`.

## 2. Game design

### 2.1 Fantasy and pillars

An alternate-history Roman frontier fort runs on spinning power.
- It is built against a quarried cliff with a gold seam, behind a moat, with one bridge to its only gate.
- In its courtyard stand four great treadwheels (*rotae magnae*), one per rider. Each feeds a mechanical junction that can couple any wheel to any of five stations.
- Egyptian-inspired attackers come in waves down one long, winding dry road, bringing siege engines.

- Watts are the currency: a station works in proportion to the P_eff routed to it (BRIEF 3.3).
- Five stations, four riders, caps on each: every switch is a choice.
- Shots are simulated projectiles with gravity and drag. They can miss, and how they miss is physical.
- Readable from 3 m: your wheel's colour, your powered path through the junction, your station's moving part in your colour, the gate's HP.
- Failure costs score and gold, never the workout.

### 2.2 Players and slots

```json
{"id": "siege", "title": "Castellum Rotae",
 "summary": "Co-op siege defense at a Roman wheel fort. Your watts turn a great treadwheel; couple it to a ballista, an onager, an arrow organ, the tar works or the gold mine.",
 "version": "0.6.0", "min_players": 1, "max_players": 4, "bots": true, "presentation": "2d", "pixel_base": [960, 540],
 "pixel_flex": {"min": [852, 480]},
 "entry": "res://src/games/siege/siege_game.gd",
 "contents": ["short", "vo2", "sweetspot", "endurance", "drill"],
 "default_content": "short", "e2e_content": "drill", "zero_input_content": "short",
 "first_run_priority": -1,
 "picker_image": "res://assets/siege/cards/picker_card.png",
 "player_options": [{"id": "wave_offset", "type": "int", "min": -10, "max": 5, "step": 1, "default": 0, "label": "SIEGE_OPT_WAVE_OFFSET"},
                    {"id": "tilt_shift", "type": "toggle", "default": true, "label": "SIEGE_OPT_TILT_SHIFT"}]}
```

- Slots 0–3 own wheels 0–3, west to east. Each wheel's rim and hub are in the slot's colour (Okabe-Ito orange, blue, yellow, green). They are paired with the slot's pattern on the HUD chips and the stations card.
- Solo riders may add up to 3 bots, and a host may fill empty wheels with bots (BRIEF 4.2).
- No one joins after the start. A dropped client is AFK until it reconnects (BRIEF 5.3).

### 2.3 Effort plan

`rules/siege_plan_builder.gd` builds each slot's EffortPlan from `content/siege/shifts.json` and the slot's wave offset.

| Phase | kind | mode | Target | duration_s | label |
| --- | --- | --- | --- | --- | --- |
| Warm-up wave | WARMUP | ERG | `target_pct` 50, `ramp_to_pct` 65 | 300 | "Warm-up wave" |
| Build break | RECOVERY | ERG | 50 | 120 | "Build break" |
| Wave n | WORK | ERG | Shift's wave target + the wave offset | Shift's wave length | "Wave n" |
| Break n | RECOVERY | ERG | Shift's break target | Shift's break length | "Break n" |

Every phase has `lap: true` and no `range_pct`. The PlanValidator appends the cool-down (180 s at 50%).

- **Wave offset:** −10 … +5 points (bots 0), added to WORK targets only. It is clamped to at least 50%, and to ≤ 105% in waves over 240 s and ≤ 117% in waves of 240 s or less.

| Content | Waves (ERG, offset 0) | Breaks (ERG) | Total | BRIEF 4.6 check, at every offset |
| --- | --- | --- | --- | --- |
| `short` | 3 × 300 s at 95% | 2 × 180 s at 50% | 31 min | ≤ 100%; no phase longer than 300 s |
| `vo2` | 6 × 120 s at 112% | 5 × 180 s at 50% | 37 min | ≤ 117%, above 105% for at most 120 s per wave; each break 180 s at ≤ 90% |
| `sweetspot` | 2 × 900 s at 90% | 1 × 300 s at 55% | 45 min | Phases over 300 s stay ≤ 95% |
| `endurance` | 1 × 2700 s at 70%, a rush every 480 s | None | 55 min | ≤ 75% |
| `drill` (e2e) | A 20 s build break at 50%, then a 100 s wave at 60%, both WARMUP | None | 2 min plus cool-down | ≤ 65%; no WORK phase, no offset |

The first four contents start with the warm-up wave and the build break, and their totals include them and the cool-down.

Every row also passes 4.6.8 (the first 300 s ERG ≤ 65%), 4.6.1, 4.6.2, 4.6.3 (rescue is a stagger) and 4.5. Siege sends exactly one load directive pattern, Overdrive: `{mode: SIM, duration_s: 30, reason: "overdrive", source: "siege"}`, and publishes one cadence band (80–100 rpm) once at the start, which changes no load (3, HUD).
- It is sent only in a WORK phase with ≥ 30 s left, never in rescue, never for a rider who is not pedaling, and never for bots or from Autopilot.
- It carries no `mode_grade`, `haptic` or target.
- It reverts on expiry; Siege sends no restore.

Siege sends no haptics, mode grades or target changes.

### 2.4 Rules and mechanics

Units are m, s and P_eff W. Every number below lives in `content/siege/*.json`, validated at load. Each started as a value for the sims to tune within ±30%; a value beyond that has an ADR with sim evidence in `docs/decisions/siege.md`.

**Map** (`content/siege/maps/rotae.json`, generated by `src/games/siege/art/export_map.mjs` from the art's own geometry; a test checks it is not stale)
- World metres: x east, y south (toward the camera), z up. Screen: `sx = (x − y)·3.5 + 450`, `sy = (x + y)·1.75 − 3.5·z + 127`, depth `x + y + z` (larger is nearer).
- **Path:** one polyline of 98 points `[x, y, z]`, 391.4 m. Progress `prog` is 0 at the camp (west edge) and 391.4 at the gate.
  - The road is the first 375 m.
  - The bridge runs from `prog` 375.4 to 391.4, and the moat edge is at 375.4.
  - The plaza is at (44, 81), radius 8.
  - Staging grounds are at `prog` 0 (camp), 126 (palm grove), 226 (wadi) and 281 (arch, about 110 m from the gate).
- **Stations (ids):** 0 mine, 1 tree ballista, 2 great onager, 3 arrow organ, 4 tar works. Each has a position (the pivot), a muzzle offset along its aim, and a starting yaw.
- **Pads 1–4:** on the gate's flanking towers (1, 2) and the side towers (3, 4).

**Routing**
- A rider's target is a station 0–4. Caps per station: mine 2, ballista 1, onager 2, arrow organ 2, tar works 1 (sum 8).
- Controls:
  - `swap` or right: the next station (0 → 1 → 2 → 3 → 4 → 0);
  - left: the previous one;
  - up: the mine;
  - down: the "hot" station (Autopilot's pick).
- They skip full stations. A cap only refuses routing onto a full station; it never pushes anyone off.
- A change reconnects after 2 s, with no output in between (`reconnect_s`).
- Everyone starts on the mine, so four riders can all start there. During breaks all output goes to the mine, and each rider's target is kept.

**Output**
- m = Σ(P_eff × od) / 250 W, × 1.4 after the station's upgrade 1, capped at 4.0. od = 2 while that rider's Overdrive is on and their raw power is at least CP (the game uses the rider's FTP as CP), otherwise 1.
- An unpowered weapon keeps its winding and stops winding; the mine and pump stop.
- Exceptions:
  - Reserve flywheel: a station holds its last m for 10 s;
  - Aqueduct drive: every unpowered weapon station gets m = 0.25.

**Economy (gold)**
- The mine pays its riders 1 gold per kJ of P_eff, × (1 + 0.2 × mine level).
- A kill pays its bounty × `bounty_scale` (0.115), split by P_eff share among the riders who were delivering to the killing station when the projectile left it. Pad kills and perk-driven shots pay nothing.
- Gold is personal, and anyone may pick anything for the team's shared receipt (see the Shop). Each rider starts with 40.

**Projectiles** (`combat/siege_ballistics.gd`, shared by the rules and the view)
- Integrated at 0.05 s:
  - `v' = v + (gravity (0, 0, −9.81) − k·|v|·v)·dt`;
  - `p += (v + v')/2·dt` (a trapezoidal step, exact for gravity; semi-implicit Euler landed up to 1.4% short of closed form).
- Ground height: the z of the nearest path point within 30 m of the projectile, else 0.
- **Aiming:**
  - The station predicts its target's `prog` after the flight time at the target's current speed. Path progress is exact.
  - It solves the launch for that point by iterating the drag flight, like `aim()` in `src/games/siege/art/life.mjs`.
  - It repeats the prediction with the new flight time (3 rounds).
- Spread is drawn from `ctx.rng` per shot as a seed. Every projectile's own spread comes from a small deterministic hash RNG (`SiegeHashRng`) seeded with it, so clients replay identical arcs.
- Damage = `max(1, damage − armour)`. It lands at impact, never at fire time, and a target can die or leave before then.
- Weapons turn toward their target at their slew rate, only while powered, and fire only when aligned within 2° and wound. Each picks a target once a second by the `prefer` weights in `stations.json` (the ballista favours engines and shield bearers, the onager engines and the most HP inside its splash, the arrow organ spearmen and chariots).

**Stations**

| Station | Wind or rate at m = 1 | Range | Slew | Projectile | Effect |
| --- | --- | --- | --- | --- | --- |
| Tree ballista | wind 5.0 s | 0–110 m | 25°/s | bolt 70 m/s, k 0.0004 | Pierces: 120 to the first body within 0.6 m of its path; after each body it keeps 75% (infantry) or 30% (engine) of that; it stops below 10 or at the ground |
| Great onager | wind 7.0 s | 30–100 m | 4°/s | stone, up to 34 m/s, k 0.0016 | At ground impact: 160 × (1 − 0.6·d/5 m) to every enemy within 5 m; an engine within 2 m takes × 2.5 |
| Arrow organ | one rack of 12 every 1.5 s, cycling 3 racks | 40–115 m | 30°/s | arrows 45 m/s, k 0.006, σ 2.5° | Each arrow: 8 to the nearest enemy within 0.6 m of its landing point; shield bearers block 70% of arrows (hash RNG) |
| Tar works | pump 6 L/s | gate, bridge | none | none | Curtain and slick bridge (below) |
| Mine | none | none | none | none | Gold (above) |

- Upgrades are per station, team-wide, in order:
  - 1: +40% output;
  - 2: +25% range (tar: curtain max +25%); stones then fly up to 39 m/s and arrows up to 50 m/s to reach it;
  - 3: the special.
- The specials:
  - ballista: an iron head that ignores armour;
  - onager: a 6.5 m splash;
  - arrow organ: a fourth rack (a volley every 1.125 s);
  - tar: a full coat slows 65%.
- Speed spread: arrows ±3%, stones ±1.5%, bolts ±0.5%. Angular σ: stones 0.6°, bolts 0.3°.

**Tar works**
- The cauldrons hold 300 L (+100 with the Spare cauldron perk). They reheat at 1 L/s, with or without a rider.
- The pump moves 6 L/s × m into the curtain, while there is tar. It stops at the curtain's top.
- The curtain holds 0–200 HP (1 HP per litre). It drains 1 HP/s on its own.
- Gate damage hits the curtain first.
- Bridge coat = min(1, curtain / 100). Everything on the bridge moves at × (1 − 0.5 × coat). Chariots on a coated bridge lose their speed changes.

**Pads** (crew-wound, no rider)
- The Scorpion costs 40 gold. It fires a 50 m/s bolt (k 0.001, 10 damage, no pierce) every 2.4 s at the enemy nearest the gate within 0–60 m.
- Upgrades: +40% rate, +25% range, then a second bolt per shot.
- Pad 1 starts with a Scorpion. The Caltrop thrower is P1 and is not built (2.9).

**Enemies** (`content/siege/enemies.json`)
- Every body is its own enemy on the path at a seeded lateral offset of ±1.8 m. Bodies don't collide.
- Groups spawn in ranks: spear blocks are 4 wide × 3 deep, 1.2 m apart; shield bearers 3 × 2; chariots in pairs 6 m apart.

| Enemy | HP | Armour | Speed | At the gate | Bounty | Threat |
| --- | --- | --- | --- | --- | --- | --- |
| Spearman (blocks of 12) | 20 | 0 | 1.8 m/s | 2 HP, then gone | 1 | 1 |
| Shield bearer (groups of 6) | 40 | 6 | 1.2 m/s | 6 HP, then gone | 3 | 3 |
| Chariot (pairs) | 60 | 2 | 6 m/s × (1 ± 0.3), redrawn every 3–6 s, 2 m/s² accel | 4 HP, then gone | 3 | 3 |
| Battering ram | 780 | 6 | 0.8 m/s | 3.9 HP/s until destroyed or the wave ends | 15 | 20 |
| Siege tower (boss) | 1800 | 6 | 0.5 m/s | Docks at the moat edge (below) | 60 | 60 |

- A destroyed ram's crew scatters as 6 spearmen.
- **Siege tower:** it stops at the moat edge and docks (event `dock`). A docked tower does no gate damage. While docked, it lands boarders on the wall. They stop the tar works and pads 1 and 2 until the tower is destroyed, and the tower takes ×1.5 damage from the onager.

**Waves**
- Groups spawn every 6–12 s (seeded), from 3 s into the wave until 60 s before it ends. Each group adds its share of the threat left (× 0.8–1.2) to an account, and formations spawn while the account covers the next one. The mix and the total stay exact over the wave.
- Total threat: B = `c_budget` (50) × `budget_factor`[shift] × `slot_factor`[slots] × Σ over slots (planned P_eff / 250 W) × (wave_s − 60) / 60. The planned P_eff is the slot's planned target (% FTP) × FTP × u × r, where:
  - u is 0.85 for an unverified FTP;
  - r is 250 / FTP in FAIR_FTP, 1 in RAW, and in WKG the latest p_eff_w / power_w ratio.
- `slot_factor` by slot count 1–4, bots included, is 0.62, 0.58, 0.8, 1.0. One rider mans one station, so a small team covers fewer range bands, while total B still grows with every slot.
- `budget_factor` by shift: `short` 0.92, `vo2` 1.0, `sweetspot` 0.85, `endurance` 0.72. A long wave saturates the defence, while short waves end and reset. Both factors are in `waves.json`.
- Mix by third of the shift (spear / shield / chariot threat fractions): standard 0.7/0.1/0.2, 0.5/0.25/0.25, 0.4/0.3/0.3. The `raiders_horsemen` mix (warm-up, drill, rushes) has spearmen and chariots only: 0.8/0/0.2, 0.7/0/0.3, 0.6/0/0.4.
- **Staging:** a formation enters at the furthest staging ground from which it can still reach the gate 21 s before the wave ends at its speed. If it can't from any, it doesn't spawn and its threat is dropped.
- **Siege engines:**
  - At the wave start, rams enter at the `prog` from which they reach the moat edge `push_lead_s` (60) before the wave ends: one ram for 1–2 slots, two (25 m apart) for 3–4. An engine whose entry point would lie before the camp enters at the camp later, so it still arrives on time.
  - Escort spearmen worth 10 threat per slot enter behind them. Engines and escorts come on top of B.
  - In the last wave of a shift whose waves are ≥ 300 s, the siege tower replaces the rams.
  - Event `push` on spawn.
- Cap: at most 150 enemies alive; extra spawns queue. At wave end the queue is dropped, and live enemies retreat for 3 s, then vanish without bounty or damage.
- **Warm-up wave:** 0.4 × B at its mean target. Spearmen only for 180 s, then chariots too. One ram at half HP, no escort. The gate stays at or above 50 HP. A teaching toast each minute.
- **Endurance rushes:** at 480, 960, 1440, 1920 and 2400 s of the wave, 30 s of spearmen and chariots worth 5.6% of B each, taken from B. Kills during a rush pay double bounty to riders in Overdrive.
- **Drill:** its 100 s phase plays as wave 1 (B from its 60% target, the push with escort, no gate floor) with spearmen and chariots only. It counts as wave 1 for the score and `finished`.

**Gate and Breach**
- The gate has 130 HP (+25 per Iron bands, twice).
- At 0 HP it is breached: every station (the mine too) and pad stops for 10 s, perks included. Arrivals vanish without damage, and rams pause.
- Every rider loses 30% of their unspent gold (rounded down) when the Breach starts, so buying first can't dodge it. Afterwards the gate is back at 30 HP, or at its current HP if that is higher. The wave and its ERG target run on.

**Overdrive**
- Triggered by ability_1, or by `surge` while its prompt shows. The prompt shows when Overdrive is ready, the phase is WORK with ≥ 30 s left, the rider isn't in rescue, isn't coasting, and their station has an enemy in range (the tar works: a ram or tower within 60 m of the gate) or a rush is on.
- It lasts 30 s. The sprint band is 1.2–1.4 × FTP on the rider's own peer. Output counts double while raw ≥ CP. The cooldown is 90 s.
- It is scored if ≥ 1.2 × FTP held for ≥ 10 s.
- A refusal (by the host or the governor) sets a 30 s retry instead of the 90 s cooldown and toasts only on that rider's peer. A phase change, rescue or going AFK ends a running Overdrive, with the 90 s cooldown from that moment.

**Shop** (every break, including the build break, with a 10 s countdown)

| Item | Cost | Limit |
| --- | --- | --- |
| Station upgrade 1 / 2 / 3 (ballista, onager, arrow organ, tar works) | 40 / 50 / 70 | Per station |
| Mine level 1 / 2 / 3 (+20% gold each) | 60 / 90 / 130 | Team |
| Build a Scorpion on an empty pad | 40 | 4 pads |
| Pad upgrade 1 / 2 / 3 | 40 / 50 / 70 | Per pad |
| Iron bands: +25 max and current gate HP | 45 | Twice |
| Repair the gate: +20 HP, up to max | 20 | Any |
| Reserve flywheel / Aqueduct drive / Spare cauldron (team perks) | 80 / 100 / 60 | Once each |

- It runs on pedal-scan (BRIEF 3.5). The top entry is Autopilot's pick and the second is "Save gold". Pedalling alone picks nothing: the list's ERG auto-confirm is off here, and a pick that still arrives tagged `auto` is ignored.
- **The shared receipt.** A pick does not spend gold. It puts the item on a receipt every rider sees and holds the picker's gold for it ("40 ON RECEIPT" under GOLD).
  - Picking your own item again takes it back and frees the gold.
  - Picking someone else's item votes no on it, and picking it again returns your vote to yes.
  - The voters are the connected riders and bots in slot order, everyone starting at yes (`TeamVote`, GAME_SDK 12.2), and the picker counts as yes. The moment "no" outnumbers "yes" or the two tie, the item leaves the receipt and its gold is the picker's again. A rejected item is never shown on the receipt. A solo rider's own pick can never be rejected.
  - Bots and Autopilot add their picks like anyone and vote yes.
  - When the break ends the host buys what is left in the order the items were added (slot order within a tick), each from its picker's gold. One line per item (item plus station or pad), so nothing is on the receipt twice or past its limit, and a pick never takes more than the picker has free, so gold never goes negative. A pick while the shop is closed is ignored.
  - A rider who leaves (disconnects) takes their items off the receipt and their votes drop; their gold was never spent.
- The host resolves picks in arrival order (slot order, then each rider's intents in order). A pick the shop would refuse goes out as a `buy` event with `ok` 0, and only the buyer's peer toasts it; each purchase at the break's end is a `buy` event too. Receipt changes are `receipt` events; a voted-off item toasts its picker.

**Rescue and AFK:** `on_rescue` is a stagger: the walkers stumble, and Overdrive is unavailable. `on_afk` stops the wheel, keeping the routing, the gold and the slot's share of B.

**Tuning targets** (the sims meet these)
- T1: a compliant Autopilot team scores 64–89 in `short` (mean of seeds 1–3).
- T2: a weapon-only rider earns 40–60% of a mine-only rider's gold per minute.
- T3: compliant Autopilot leaks per wave-minute stay within ±30% across the four shifts.
- T4: compliant Autopilot destroys ≥ 70% of rams and siege towers before they reach the gate (a tower counts as reaching it when it docks).

### 2.5 Autopilot and zero input

`autopilot/siege_autopilot.gd` serves Autopilot riders and bots. It never changes effort and never triggers Overdrive.

**Routing.** Once a second, in slot order, each Autopilot rider takes the station with the highest *score*, within the caps.
- Weapons: the sum over enemies that will be within the station's range band during the next 10 s (at their current speed), of their HP × the station's weight for that enemy type. The weights are `autopilot.weights` in `balance.json`: the ballista favours engines and shield bearers, the onager blocks and engines, the arrow organ spearmen and chariots.
- Tar works: scored when a ram or siege tower is within 60 m of the gate, or any enemy within 40 m, and the cauldrons hold ≥ 2/3. Its score is then the gate threat those enemies carry.
- Mine: a small constant (`autopilot.mine_score`). It wins when nothing is in reach.
- Switch at most once per 8 s, and only for a score at least 25% higher.

**Shop**, at most 2 items per break, at 4 s and 9 s into it, in this order:
1. repair, if the gate is below 50%;
2. an upgrade for the station that did the most damage last wave;
3. a Scorpion on the first empty pad;
4. a mine level;
5. Iron bands;
6. perks;
7. save.

**Zero input.**
- A human counts as Autopilot for routing until their first `route` intent, and for the shop until their first non-auto `pick` intent. `overdrive` intents and auto-confirms never end either fallback.
- While a rider is on the shop fallback, Autopilot adds picks to the receipt for them; an auto-confirmed pick never reaches the receipt, fallback or not. Autopilot picks with the gold the rider has free and never picks an item already on the receipt.

### 2.6 Multiplayer and network

The host simulates everything (BRIEF 5). Clients send intents in `Telemetry.intents` at 5 Hz:
- `{"k":"route","to":"mine"|0..4|"next"|"prev"|"hot"}` (`"gen"` is accepted as `"mine"`);
- `{"k":"pick","item":"<id>","station":n}` or `"pad":n` (adds the item to the receipt, takes your own back, or votes on someone else's; `"buy"` is the old word for it);
- `{"k":"overdrive"}`.

The host validates them and drops anything beyond 5/s per peer. No route or Overdrive intents are sent while the shop is open. Snapshots at 10 Hz carry ints only:

```
{"v":2,"tick":n,"ph":phase,"pt_ms":n,"gate":[hp,max,breach_ms],"nb":breaches,"ib":iron_bands,"ml":mine_level,"pk":[perks],
 "w":team_watts,"r":[[slot,target,reconnect_ms,od_ms,od_cd_ms,gold,p_eff_w,raw_w,cadence_rpm,rescue,afk,connected,shop_fallback]...],
 "st":[[station,level,wind_pm,yaw_cdeg,m_x100,arm_pm]...],
 "pd":[[pad,type,level,cd_ms,yaw_cdeg]...],
 "tar":[cauldron_dl,curtain_dhp,coat_pm,boarded],
 "e":[[id,type,prog_dm,lat_dm,hp,st]...],"q":queued,"gd":gate_damage_dm,"dw":[[station,damage]...]}
```

- `wind_pm` is the winding in per mille.
- `arm_pm` is the station's animation phase in per mille (onager arm throw, ballista string, arrow rack reload), so the view can show it.
- `dw` holds each station's damage in the current or last wave (Autopilot's upgrade pick on clients).
- Optional keys, present only when not at their default: `"ru":[1,i,left_ms]` (a rush is on), `"rn":n` (the next rush's index) `"rk":n` (the arrow organ's next rack) and `"rc":[[item_code,at,cost,slot,no_slot...]...]` (the shared receipt in the order the items were added: the item's code 1..9, the station or pad it is for, the gold held, the picker's slot, then the slots that voted no in slot order).
- **Shots:** each fired projectile (a rack of arrows is one event with `n` 12) is an event `{"type":"shot","tk":tick,"src":station 1..3 or 10 + pad,"kind":0 bolt|1 stone|2 arrow|3 scorpion,"o":[x_cm,y_cm,z_cm],"v":[vx_mms,vy_mms,vz_mms],"n":count,"sd":seed}`.
  - Clients replay the flight with `SiegeBallistics` and the same seed.
  - Damage and kills come from the snapshot and `kill` events, never from the replay.
- Events, batched and in order: `wave_start`, `wave_end`, `rush`, `push`, `reach` (a ram at the gate), `dock`, `shot`, `kill`, `leak`, `breach`, `gate_restored`, `buy`, `receipt`, `route`, `overdrive`.
- Every toast that follows a host-side rule is raised from these events.
- Caps: 150 enemies, and snapshots ≤ 8 KB at the cap.
- `client_predict` spins the local wheel and shows route changes at once. Everything else interpolates over 100 ms.

### 2.7 Haptics

None.

### 2.8 Results and progression

- **Score:**
  - Gate: 40 × mean(gate HP / max) at each wave end.
  - Breaches: max(0, 30 − 15 × Breaches).
  - Earnings: 30 × min(1, team gold earned / par), where par = 0.75 × the team's planned P_eff in kJ from the warm-up to the last wave.
- Grades: S ≥ 90, A ≥ 78, B ≥ 64, C ≥ 48, otherwise D.
- **Per player:** gold from the mine vs. bounties, kills, damage, scored Overdrives, wave time on the mine vs. weapons, and the station they spent most time on.
- **Team:** gate HP per wave, Breaches, leaks, engines stopped (rams and towers), and shots fired and hit per station.
- **XP** = round(kJ / 10) plus the grade bonus (S 60, A 40, B 25, C 10, D 0). Unlocks at 100, 250, 500 and 1000 cumulative XP (`cosmetics.json`). They unlock, but can't be equipped yet.
- `apply_progress` adds the session XP once per session id.
- `finished("complete")` fires when the last wave ends. In the cool-down nothing spawns, enemies retreat, and the walkers march.

### 2.9 Content

**P0** (built)
- The map above (one road, staging grounds, five stations, four pads).
- The five shifts and the wave offset.
- The stations, the Scorpion pad weapon, and the five enemy types including the siege tower.
- The shop, perks, Overdrive, Breach, grades and XP.
- The help overlay (`HudSpec.help`).

**P1** (not built)
- The Caltrop thrower pad weapon.
- *Fire the coat*: an arrow volley landing on a full coat lights it, for 10 s of 15 HP/s on the bridge, and the coat is gone.
- Archers that shoot at wall crews (a station they hit loses 30% output for 5 s).
- Custom shifts and `.zwo` import.

**P2:** a night siege, an endless mode.

## 3. Presentation

**Art pipeline** (`src/games/siege/art/`, Node, our own code)
- `scene.mjs`, `life.mjs`, `world.mjs`, `shade.mjs` and `raster.mjs` draw the world (the approved mockup).
- `bake.mjs` writes `assets/siege/bake/`:
  - `world.png`: the static world without anything that moves or changes colour, with sun shadows and outlines.
  - `world_depth.png`: depth as 16 bits in R and G, the encoding in the manifest.
  - Sprite atlases with a colour PNG and a depth PNG each, for:
    - wheels in rotation frames;
    - the junction's 20 route overlays and 4 output shafts;
    - every station's moving parts in yaw and animation frames;
    - the tar curtain and coat stages;
    - the gate's damage stages;
    - pad weapons;
    - enemy bodies (a few px tall, 4 walk frames each);
    - siege engines;
    - effects.
  - `manifest.json`: every frame's atlas rect, its anchor in world metres, its depth offset and the generator version.
- Rider-hue materials are drawn in a key ramp and recoloured at runtime with `PaletteSwap`: the slot ramp when powered, timber when idle. So one frame serves all four colours.
- `bake.mjs --check` verifies the committed files match the generator version.

**Flex canvas.** The canvas follows the window at a whole scale (`pixel_flex` min 852 × 480). `world.png` and `world_depth.png` are 1920 × 1084: the 960 × 540 design frame, unchanged, with more terrain all round from the same rasterizer. The world-to-screen math in 2.4 still measures from the design frame's top-left, which the view places on the canvas without hiding the road's west bend, the fort, the wheels and the hamlet. Past the bake, each edge mirrors its margin: there is no black and no second fort. The HUD plates anchor to the canvas and don't overlap down to 852 × 480.

**View** (`view/`, a Node2D in the platform's `PixelViewport`)
- The baked world is a sprite. Every dynamic sprite is drawn with a canvas shader that discards pixels behind the world's depth (sprite depth = its frame depth + the depth of its world anchor). This is how enemies vanish behind walls and the arm passes behind the frame.
- The view only reads state:
  - the wheel angle from P_eff (rim speed 1.2 m/s × P_eff / 250 W, up to 3 m/s), with 1–3 walkers by P_eff (150 / 300 W, 20 W hysteresis);
  - the powered path of each rider (wheel → lane → clutch drum → column → station), lit through the 2 s reconnect;
  - stations at their yaw and animation phase;
  - enemies from `prog` and lateral offset (interpolated);
  - projectiles replayed from `shot` events;
  - impacts (dust, splinters);
  - the tar curtain and coat from the `tar` fields;
  - the gate's damage stage;
  - the siege tower's dock.
- Tilt-shift and depth of field come from a screen shader, with the fort in the sharp band. The local rider's `tilt_shift` option turns it off.
- Budget at the cap: ≤ 400 canvas items, 60 fps at 1080p on integrated graphics.

**HUD** (`hud_spec()`): the game's own Roman HUD, no kit widgets, like Torque Company's (`docs/games/tank.md` 3.6). The approved mock is the spec: `src/games/siege/art/hud_mock.mjs` and `hud_font.mjs`, art px on 960 x 540, 2x at 1080p. `hud_bake.mjs` bakes the letter, icons and slot shapes from that code into `assets/siege/hud/`.

Materials: dark wax panels in a limestone frame with a brick course; tabula ansata plaques; a red chip with light text is the only alarm, never coloured text alone; riders only in slot colours with their shape. Text is upper-cased at draw time; a character outside the atlas falls back; rider names are cut to fit.

| Position (art px) | Contents |
| --- | --- |
| Top left (150, 8, 258 wide) | Session plate: title plaque, ENDS IN with the cool-down (nominal length minus elapsed), the profile strip with block height as effort and rushes as ticks, enemy icons with counts, a plain cream warning |
| Top centre (470, 8) | Teammate cards, teammates only: vexillum in the slot colour, shape, name, raw W, %FTP, station icon, a lamp for in band (with hysteresis) or a mark: OD with its clock, a RESCUE chip, AFK |
| Under the cards (464, 69, 286 wide, 27 high) | The platform's banners, in the kit's colours and font; the toasts below them in the mock's palette |
| Right column (804, 8, 148 wide, ending on the base's middle row) | Gate plate (a filled chip behind the number and an alarm frame when low) with the tar row; gold; stations card (your row in bronze, the hot station as a thin red bar on the left edge, slot shapes and hollow pegs, the coupling bar); Overdrive plate (ready, prompt, active, recharging, closed with its honest reason; a press sends the same intent as `ability_1`) |
| Bottom centre (479, 420, 112 high) | Cockpit: interval clock, watts and cadence at 72 px (KEY36), one source for each value; the heart rate cell; the band gauge with a needle; the instruction line; the next line; W′ or, in SIM, the gear |
| Bottom left, breaks only (8, 368, 364 wide, 150 high) | Shop, over the road's west loop, which is empty in breaks; its header reads "QUARTERMASTER  PICK TO ADD" and its rows are marked ADDED (yours) or with the picker's name |
| Left, breaks only (8, 270, 364 wide, up to 209 high, growing up from just above the shop) | The shared receipt: "RECEIPT  EVERYONE SEES THIS", "BOUGHT WHEN THE BREAK ENDS (m:ss)", each item with its cost, its picker and YES n / NO n (your own no says YOUR NO), up to four rows (more fold into "+N more on the receipt"), the total and the two rules "A MAJORITY NO (OR A TIE) TAKES IT OFF AT ONCE." and "PICK YOURS AGAIN TO TAKE IT BACK." |
| On the world | A red tag on the nearest live tower and ram within 200 m ("TOWER 110 M"); while the gate is failing in a wave, the oxblood banner with a leader to the gate |

- **Cockpit rules.** The target caption is the applied target from telemetry (`applied_target_w`), never the plan, so rescue and caps are true. Displayed watts are a 3 s mean with in-band hysteresis; stale power shows `--`, not 0 (`HudRiderNumbers`, GAME_SDK 10.4). W/kg shows only if the rider opted in. The reserve is a thin bar with a number only below 50%. The gear shows only in SIM.
- **Heart rate.** Sensor present: the cell, a muted heart and cream digits. Dropout (a sensor seen this session or known to the platform): `--`. No sensor: no cell, and the plate is 344 px wide instead of 404.
- **The instruction line**, one line by state, first match wins: no data "NO TRAINER DATA: KEEP PEDALLING" (a silent stream also reads as coasting; a rider who is pedalling must not be told to pedal, and the target caption shows none); coasting "PEDAL: LOAD DROPPED" (its floor wins over rescue, BRIEF 4.6.12); rescue "RESCUE: SPIN 70+" with the caption RPM 70+; Overdrive by where the 3 s power sits in the real band: under "SPRINT 240-280 W, SHIFT UP", in "HOLD 240-280 W", over "EASE TO 240-280 W"; low cadence "SPIN UP: RESCUE AT 45", only while rescue is armed (ERG at 60% FTP or more), after 1.5 s under 70 rpm, half of rescue's 3 s under 45; cool-down "SPIN IT OUT"; the last 30 s before a step up "LOAD UP IN 0:30, SPIN UP" with the clock in gold; warm-up "SETTLE IN, SPIN 80-100"; else "SPIN 80-100". No data, coasting, rescue and low cadence sit on the red chip. A cadence of 70-79 in a wave gets a small up arrow and no chip.
- **The next line.** "NEXT: BREAK, 3:00 AT 100 W", in applied-style watts: the plan's percent, this rider's FTP, the unverified factor, whole watts, floor and ceiling. In rescue "THEN: RAMP BACK TO 190 W", in Overdrive "THEN: ERG AT 190 W", at the end "NEXT: RESULTS".
- **Gold's size.** NUM (28 px) in waves, where it can't be spent; KEY (48 px) while the shop is open, where it is the number that decides. The plate grows with it and the cards under it move down. The number is the gold the rider has free; while their items hold gold on the receipt, "N ON RECEIPT" sits under GOLD.
- **Shop.** The platform's PedalScanList does the picking (2.4), with its ERG auto-confirm off; the plate draws its rows in the BODY face (24 px cap height), five to a page, with the coin in a fixed column and BEST and "N MORE" notes.
- **Cadence band.** The host publishes 80-100 rpm once at the session's start with `ctx.directives.cadence_band`. It changes no load: the metronome, bots and a MockTrainer `band` rider follow it.
- Budget: a plate redraws only when what it shows changes.
- **Help overlay** (`HudSpec.help`, shown on F1 and on a rider's first Siege session). Short texts with arrows to:
  - your wheel;
  - your powered path;
  - the five stations;
  - the road;
  - the gate and curtain;
  - the stations card;
  - the shop.

**Audio:** rendered from recipes in `assets/siege/audio/audio.json` (`docs/AUDIO_PIPELINE.md`), with no samples.
- The wheel is locked 1:1 to each rider's cadence: a footfall, a pawl and one axle knock a revolution, over a low timber rumble that gets louder with cadence and load and never changes pitch. Other riders' wheels sit about 11 LU under yours.
- Every shot has a release, a flight that crosses the screen with it, and an impact chosen by what it lands on: flesh, wood, a shield's ring, the ground or the moat. Every arrow that lands makes its own sound, so a volley of twelve can be counted. Your own station's shots sit over everyone else's.
- The siege: far horns on a wave, a push and a rush, the ram, a walking tower's creak and its docking, gate hits, the Breach and the gate alarm (which duck the arrows and the wheel), tar, coins, and the junction's clatter by team watts. Over it all: a hill bed of wind, a far crowd and drums by enemy count.
- A safety prompt stays at least 6 LU over the battle. A pause stops the battle's sound with the picture.

**Strings:** `content/siege/strings.csv`, keys `SIEGE_*`.

## 4. Testing and gates

Unit tests (GUT, `tests/games/siege/`) cover every rule and table number in 2.3–2.8, and in particular:
- **Plans:** every content at FTP 80, 200 and 400, verified or not, and at offsets −10, 0 and +5, passes the PlanValidator with exactly the phases and 4.6 checks of 2.3. The offset clamps, and the first run never picks Siege.
- **Projectiles:**
  - with k = 0, `SiegeBallistics` matches closed-form ballistics within 1% of range;
  - with drag, aim then fly lands within 0.5 m of a stationary aim point across each station's range;
  - lead aim hits a constant-speed target on a straight road and on the path's hairpins;
  - spread replay from a seed is identical on two instances.
- **Stations:** linear output (0.5 at 125 W, 2.0 for two riders at 250 W) and the cap of 4.0; caps per station; winding and slew times; ballista pierce falloff; onager splash falloff and the engine multiplier; arrow hits and testudo; the tar flow, the curtain absorbing gate damage, the coat slowing the bridge, cauldron refill; the mine's 1 gold per kJ ±0.1%.
- **Enemies and waves:** ranks and lateral offsets; chariot speed changes; staging-ground choice; engine entry so they reach the moat 60 s before the end; one or two rams by slot count; the siege tower in the last long wave, docking and boarders; the cap and queue; retreat; the warm-up gate floor; rushes; the drill.
- B and par in FAIR_FTP, WKG and RAW, verified or not, without reading any weight.
- Overdrive preconditions and the exact directive fields (no `mode_grade`, `haptic`, `target_*`, `crr` or `cw`), including refusal in warm-up, breaks, rescue, while coasting and with < 30 s left.
- Grade edges, XP once per session (host, client, a restarted client), each unlock once.
- Autopilot scores, hysteresis, shop order, never Overdrive, and the zero-input fallback with no double purchase (an auto-confirm never reaches the receipt).
- The receipt: a pick holds the picker's gold, picking your own item again takes it back, someone else's votes no and again yes, a majority no or a tie (two riders) takes the item off at once with its gold, a solo rider's own pick never rejects, bots vote yes, an item is never on it twice or past its limit, a pick while the shop is closed is ignored, a rider who leaves takes their items and their votes with them, the break's end buys what is left in the order it was added (and an empty receipt buys nothing), gold never goes negative, and a replay gives the same events and state.
- Snapshots come back as ints after a JSON round trip, ≤ 8 KB at the cap. Shot events replay identically.
- A client's teammate strip shows raw W and %FTP from the snapshot, a refused purchase toasts only on the buyer's peer, a voted-off item toasts only its picker, and every peer's receipt follows the host's snapshot.
- The map JSON is not stale (`export_map.mjs --check`), and the bake manifest matches its generator version.
- The view builds headless from a fixture. Sprite anchors project to the right art pixels. The wheel and walker formulas hold.
- No string keys are missing.

Static tests:
- nothing in `src/games/siege/` references `TrainerController`, `SafetyGovernor`, `FtmsClient`, `write_control`, `set_target_power`, `set_simulation` or `set_resistance`;
- `rules/` and `combat/` use no wall clock or unseeded RNG.

Rules-level sims: `tests/games/siege/sim/test_siege_rules_sim.gd` drives `siege_headless_sim.gd`.

Simulation matrix: `bash tests/games/siege/sim/run_sims.sh` and `node tests/games/siege/sim/check_sims.mjs build/siege/sims` assert S1–S10. The matrix holds the BRIEF 4.6 sim assertions, so it must pass with no check weakened.
- S1: `short` with 4 compliant Autopilot riders, seeds 1–3: the session completes, at most 1 Breach per run, and T1 holds.
- S2: `short` with 1 human, 2 humans, and 1 human + 3 bots: the same checks.
- S3: a team that barely pedals (one rider at 30% of the ERG target, three at 0 W) is breached in the first full wave of every shift.
- S4: `short` at 100%, 90% and 80% compliance: the mean score falls strictly.
- S5: in every run, only the Overdrive and cadence-band directives, the warm-up limits (BRIEF 4.6.8), the plans, the laps and the snapshots. The drill at offset 0 is its own run.
- S6: `sweetspot` with a cadence collapse to 40 rpm: rescue is a stagger and the plan runs on.
- S7: `vo2` seed 1 twice: identical hash and game events.
- S8: the rules sim at `c_budget` × 3 (≤ 150 alive, snapshots ≤ 8 KB).
- S9: T3 and T4 as defined above.
- S10: surgers on `vo2` and `endurance`, and `vo2` at offsets +5, −10, 0, +5: exact directives, 30 s SIM spans, a return to ERG that never goes above the plan, and the governor's switch spacing.

**Gates** (all must pass):
1. The Siege unit and static tests.
2. `tools/check_scripts.gd`.
3. SDK conformance.
4. The sim matrix.
5. `tools/fit_check` on every sim FIT.
6. `node tools/e2e/run.mjs --games=siege`.
7. `tools/run_tests` at or above the floor.

Visual checks: screenshots at 60, 360, 600 and 690 s of `short` and during a Breach, each looked at; the perf scene with 150 enemies.

## 5. Definition of Done

- Every P0 item in 2.9 is implemented, reachable and tested, and every section 4 gate is green (or listed failing with nothing weakened).
- A host picks Siege and a shift, adds bots and plays to results with zero input. Two friends join by code.
- Every plan passes the PlanValidator at every offset. Every directive matches 2.3, and the trainer is reached only through `ctx.directives`.
- Rides carry a lap per wave and break and pass `tools/fit_check`.
- The platform suite stays green, and other games still pass e2e.
- `src/games/siege/HARDWARE_TEST.md` lists what only a real trainer, screen and ear can check.
