# Castellum Rotae

Co-op tower defense for 1-4 riders at a Roman wheel fort (brief: `docs/games/siege.md`). Each rider turns one great treadwheel. A junction couples the wheel to one of five stations: the gold mine, the tree ballista, the great onager, the arrow organ or the tar works. Attackers march down one long road to the only gate. Waves are ERG intervals, breaks are recovery and shopping, and Overdrive is a 30 s SIM sprint block. Bots fill empty wheels, and every phase, the shop and the results work with zero input.

Presentation `2d`: a fixed isometric pixel-art view designed at 960 x 540 art pixels (x2 at 1080p, 3.5 px per metre) whose canvas flexes with the window (`pixel_flex`, see "The flex canvas"), drawn by Siege's own CPU rasterizer and baked to PNGs. Version 0.3.1 (v2 with its own Roman HUD). v0.1.0 had a 3D fort, three roads, eight pads, a generator and denarii; v2 replaces all of that. Decisions: `docs/decisions/siege.md`. Real-trainer checklist: `HARDWARE_TEST.md`.

## How to play

- **Pedal.** Your watts (P_eff) turn your wheel. A wave is an ERG interval at your own % FTP, so the trainer sets the load and you hold the cadence. Your wheel's rim and hub are in your slot's colour.
- **Couple your wheel.** Everyone starts on the mine. Outside breaks:
  - `swap` or right: the next station (mine, ballista, onager, arrow organ, tar works, then the mine again);
  - left: the previous one;
  - up: the mine;
  - down: the "hot" station (the Autopilot's pick).
  - Full stations are skipped. A change reconnects after 2 s, with no output in between. Your powered path (wheel, lane, clutch drum, column, station) lights in your colour at once, and the stations card shows a 2 s coupling bar.
- **Overdrive.** `ability_1` or the HUD button starts a 30 s SIM sprint block when it is ready, the phase is a wave with at least 30 s left, you are not in rescue and you are pedaling. A `surge` (the ERG surge gesture) starts it too, but only while the Overdrive plate says SURGE TO START. While it runs, the cockpit shows a sprint band of 1.2-1.4 x FTP, virtual gears work and the HUD shows the gear. Keep your raw power at or above FTP and your output counts double. Hold 1.2 x FTP for 10 s and it counts as a scored sprint. The 90 s cooldown starts when it ends.
- **Breaks.** All output goes to the mine, and you keep your target. The shop opens in every break, the build break included. It is a pick list: the top entry is the Autopilot's pick and the second is "Save gold". With pedal navigation on (Settings) it scans, and picks auto-confirm after two scan cycles. While the shop is open, the directions and the surge belong to it.
- **Zero input works.** A rider who only pedals is routed and shopped for by the Autopilot until their first deliberate `route` (routing) or non-auto `buy` (shop). Bots never use Overdrive.
- **Help.** F1 shows the help overlay: arrows to your wheel, your powered path, the five stations, the road, the gate and curtain, the stations card and the shop. It also shows once on a rider's first Siege session.

## Rules summary

Numbers are the current content in `content/siege/*.json` (committed state). Where one differs from the brief, "Where the numbers differ from the brief" names the ADR.

**Map** (`content/siege/maps/rotae.json`, generated from the art's geometry)
- World metres: x east, y south (toward the camera), z up. Screen: `sx = (x - y) x 3.5 + 450`, `sy = (x + y) x 1.75 - 3.5 x z + 127`. Depth is `x + y + z` (larger is nearer).
- One path of 98 points, 391.4 m. `prog` is 0 at the camp (west edge) and 391.4 at the gate. The bridge runs from `prog` 375.4 to 391.4; the moat edge is at 375.4.
- Four staging grounds: camp (`prog` 0), palm grove (126.3), wadi (226.3) and arch (281.3).
- Wheels 0-3 stand west to east in the courtyard. Pads 1 and 2 are on the gate's flanking towers, pads 3 and 4 on the side towers.

**Stations and caps**
- A rider's target is a station: 0 mine, 1 tree ballista, 2 great onager, 3 arrow organ, 4 tar works.
- Caps: mine 2, ballista 1, onager 2, arrow organ 2, tar works 1. A cap refuses routing onto a full station; it never pushes anyone off. So four riders can start on the mine.

**Output**
- `m = sum(P_eff x od) / 250 W` over the riders on the station, x1.4 after the station's upgrade 1, capped at 4.0. `od` is 2 while that rider's Overdrive is on and their raw power is at least their FTP (the CP; ADR "slot.ftp is Overdrive's CP"), otherwise 1.
- An unpowered weapon keeps its winding and stops winding; the mine and the pump stop. Reserve flywheel: a station holds its last `m` for 10 s. Aqueduct drive: every unpowered weapon gets `m = 0.25`.

**Economy (gold)**
- The mine pays its riders 1 gold per kJ of P_eff, x (1 + 0.2 x mine level).
- A kill pays its bounty x `bounty_scale` (0.115). It is split among the riders who delivered to the station when the projectile left, by P_eff share. Pad kills and perk-driven shots pay nothing. A kill during a rush pays double to a rider in Overdrive.
- Gold is personal, and anyone may buy anything. Each rider starts with 40.

**Projectiles** (`combat/siege_ballistics.gd`, shared by the rules and the view)
- Integrated at 0.05 s: `v' = v + (g - k|v|v) dt`, then `p += (v + v') / 2 x dt` (a trapezoidal step; ADR "trapezoidal position step"). Gravity is 9.81 m/s².
- Aiming: the station predicts the target's `prog` after the flight time, solves the drag flight for that point, and repeats 3 rounds (`SiegeAim`).
- Spread: the rules draw one seed per shot from `ctx.rng`. Each projectile's spread comes from `SiegeHashRng` seeded with it, so clients replay the same arcs.
- Damage = `max(1, damage - armour)`. It lands at impact, never at fire time. A target can die or leave before then.
- A weapon turns only while powered, at its slew rate. It fires when it is wound and aligned within 2°. It picks a target once a second by the `prefer` weights in `stations.json`.

| Station | Wind or rate at m = 1 | Range | Slew | Projectile | Effect |
| --- | --- | --- | --- | --- | --- |
| Tree ballista | wind 5.0 s | 0-110 m | 25°/s | bolt 70 m/s, k 0.0004 | Pierces: 120 to the first body within 0.6 m of its path, then keeps 75% (infantry) or 30% (engine) after each body; stops below 10 or at the ground |
| Great onager | wind 7.0 s | 30-100 m | 4°/s | stone up to 34 m/s, k 0.0016 | At impact 160 x (1 - 0.6 x d / 5 m) to every enemy within 5 m; an engine within 2 m takes x2.5; a docked siege tower takes x1.5 |
| Arrow organ | one rack of 12 every 1.5 s, 3 racks | 40-115 m | 30°/s | arrows 45 m/s, k 0.006, σ 2.5° | Each arrow: 8 to the nearest enemy within 0.6 m of where it lands; shield bearers block 70% of arrows |
| Tar works | pump 6 L/s | gate, bridge | none | none | Curtain and slick bridge (below) |
| Mine | none | none | none | none | Gold (above) |

- Upgrades are per station and team-wide, in order: 1 is +40% output; 2 is +25% range (stones then fly up to 39 m/s and arrows up to 50 m/s; tar: curtain max +25%); 3 is the special. Specials: the ballista's iron head ignores armour; the onager's splash grows to 6.5 m; the arrow organ gets a fourth rack; the tar coat slows 65%.
- Spread: arrows ±3% speed, stones ±1.5% and 0.6°, bolts ±0.5% and 0.3°.

**Tar works**
- The cauldrons hold 300 L (400 with the Spare cauldron perk) and reheat at 1 L/s, with or without a rider.
- The pump moves 6 L/s x m into the curtain while there is tar. It stops at the curtain's top.
- The curtain holds 0-200 HP (1 HP per litre) and drains 1 HP/s on its own. Gate damage hits the curtain first.
- Bridge coat = min(1, curtain / 100). Everything on the bridge moves at x (1 - 0.5 x coat). Chariots on a coated bridge lose their speed changes.

**Pads** (crew-wound, no rider)
- The Scorpion costs 40 gold. It fires a 50 m/s bolt (k 0.001, 10 damage, no pierce) every 2.4 s at the enemy nearest the gate within 0-60 m.
- Pad upgrades: +40% rate, +25% range, then a second bolt per shot. Pad 1 starts with a Scorpion.

**Enemies** (`content/siege/enemies.json`; every body is its own enemy at a seeded lateral offset of ±1.8 m; bodies don't collide)

| Enemy | Formation | HP | Armour | Speed | At the gate | Bounty | Threat |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Spearman | blocks of 4 x 3, 1.2 m apart | 20 | 0 | 1.8 m/s | 2 HP, then gone | 1 | 1 |
| Shield bearer | groups of 3 x 2 | 40 | 6 | 1.2 m/s | 6 HP, then gone | 3 | 3 |
| Chariot | pairs, 6 m apart | 60 | 2 | 6 m/s x (1 ± 0.3), redrawn every 3-6 s, 2 m/s² | 4 HP, then gone | 3 | 3 |
| Battering ram | alone or a pair | 780 | 6 | 0.8 m/s | 3.9 HP/s until destroyed or the wave ends | 15 | 20 |
| Siege tower | alone | 1800 | 6 | 0.5 m/s | Docks at the moat edge | 60 | 60 |

- A destroyed ram's crew scatters as 6 spearmen.
- A docked siege tower does no gate damage. Its boarders stop the tar works and pads 1 and 2 until it is destroyed.

**Waves and staging**
- Groups come every 6-12 s (seeded) from 3 s into the wave until 60 s before its end. Each group adds its share of the budget left (x0.8-1.2) to an account. Formations enter while the account covers the next one. The expected threat split equals the mix.
- Mix (spear / shield / chariot threat) by third of the shift: 0.7/0.1/0.2, then 0.5/0.25/0.25, then 0.4/0.3/0.3. The `raiders_horsemen` mix (warm-up, drill, rushes) has spearmen and chariots only: 0.8/0/0.2, 0.7/0/0.3, 0.6/0/0.4.
- **Staging:** a formation enters at the furthest staging ground from which it still reaches the gate 21 s before the wave ends at its speed. If none can, it is dropped and its threat is counted as dropped.
- **Siege engines:** at the wave start, rams enter where they reach the moat edge 60 s before the wave ends. One ram for 1-2 slots, two (25 m apart) for 3-4. Escort spearmen worth 10 threat per slot enter behind them. In the last wave of a shift whose waves are 300 s or longer, the siege tower replaces the rams. An engine whose entry point would lie before the camp enters at the camp later, so it still arrives on time. Engines and escorts come on top of B. Each engine raises a `push` event.
- **Cap:** at most 150 enemies alive; extra spawns queue. At the wave end the queue is dropped, and live enemies retreat for 3 s, then vanish without bounty or damage. Projectiles in flight are dropped too.
- **Warm-up wave:** 0.4 x B at its mean target. Spearmen only for 180 s, then chariots too. One ram at half HP, no escort. The gate stays at or above 50 HP. A teaching toast each minute.
- **Endurance rushes:** at 480, 960, 1440, 1920 and 2400 s of the wave, 30 s of spearmen and chariots worth 5.6% of B each, taken from B.
- **Drill:** its 100 s phase plays as wave 1 (B from its 60% target, the push with escort, no gate floor), spearmen and chariots only. Its kind is WARMUP, so there is no offset and no Overdrive.

**The threat budget, with the slot and shift factors**
- `B = c_budget x budget_factor[shift] x slot_factor[slots] x sum over slots (planned P_eff / 250 W) x (wave_s - 60) / 60`.
- `c_budget` is 50.
- `slot_factor` by slot count 1-4, bots included: 0.62, 0.58, 0.8, 1.0. One rider mans one station, so a small team covers fewer range bands. Total B still grows with every slot (0.62, 1.16, 2.4, 4.0 slot units).
- `budget_factor` by shift: short 0.92, vo2 1.0, sweetspot 0.85, endurance 0.72. Long waves saturate the defense while short ones reset.
- A slot's planned P_eff = planned % FTP x FTP x u x r. u is 0.85 for an unverified FTP. r is 250 / FTP in FAIR_FTP, 1 in RAW, and the slot's latest P_eff / power (power ≥ 50 W) in WKG. No weight is ever read.
- Example: `short`, 4 verified riders in FAIR_FTP, offset 0: each slot plans 0.95 x 250 W, so B = 50 x 0.92 x 1.0 x 3.8 x 4 = about 699 threat a wave. A solo rider: 50 x 0.92 x 0.62 x 0.95 x 4 = about 108.

**Gate and Breach**
- The gate has 130 HP; each Iron bands purchase adds 25 (180 with both).
- At 0 HP it is breached: every station (the mine too) and pad stops for 10 s, perks included. Arrivals vanish without damage, and rams pause.
- Afterwards the gate is back at 30 HP, and every rider loses 30% of their unspent gold (rounded down). The wave and its ERG target run on.

**Shop** (every break, including the build break; countdown over the last 10 s)

| Item | Cost | Limit |
| --- | --- | --- |
| Station upgrade 1 / 2 / 3 (ballista, onager, arrow organ, tar works) | 40 / 50 / 70 | Per station |
| Mine level 1 / 2 / 3 (+20% gold each) | 60 / 90 / 130 | Team |
| Build a Scorpion on an empty pad | 40 | 4 pads |
| Pad upgrade 1 / 2 / 3 | 40 / 50 / 70 | Per pad |
| Iron bands: +25 max and current gate HP | 45 | Twice |
| Repair the gate: +20 HP, up to max | 20 | Any |
| Reserve flywheel / Aqueduct drive / Spare cauldron (team perks) | 80 / 100 / 60 | Once each |

The host resolves purchases in arrival order. A refused one goes out as a `buy` event with `ok` 0, and only the buyer's peer toasts it. The Autopilot buys at most 2 items per break, at 4 s and 9 s into it, in brief 2.5's order: repair below 50%, an upgrade for the station that did the most damage last wave, a Scorpion on the first empty pad, a mine level, Iron bands, perks, save.

**Overdrive** is the only load directive Siege sends (it also publishes the 80-100 rpm cadence band once at the start, which changes no load): `{mode: SIM, duration_s: 30, reason: "overdrive", source: "siege"}`. It has no `mode_grade`, haptic, ERG target, `crr` or `cw`, so the stacked grade is the virtual-gear offset alone.
- It is sent only in a WORK phase with at least 30 s left, never in rescue, never for a rider who is not pedaling (ADR "SAFE-1"), never from the Autopilot or a bot.
- The prompt shows when Overdrive is ready and your station has an enemy in range (the tar works: a ram or tower within 60 m of the gate) or a rush is on.
- A refusal (host or governor) sets a 30 s retry instead of the 90 s cooldown, and toasts only on that rider's peer.
- A phase change, a rescue or going AFK ends a running one, with the 90 s cooldown from that moment. On expiry the platform returns to the planned ERG target through its ramped switch. Siege sends no restore.

**Rescue and AFK.** `on_rescue` is a stagger: the toast "The walkers stumble: spin back up" shows, the teammate strip marks the rider, and Overdrive is unavailable. Output keeps counting at the actual P_eff. `on_afk` stops the wheel and keeps the routing, the gold and the slot's share of B.

**Plans.** Every slot gets the same phases; only WORK targets differ by the rider's wave offset (-10 to +5 points; bots 0). The offset is clamped to at least 50%, at most 105% in waves over 240 s and at most 117% in waves of 240 s or less. Every phase is `lap: true`. The platform appends a 180 s cool-down at 50%: nothing spawns, enemies retreat, the shop and Overdrive are closed, and the fort's people march out over the bridge.

| Content | Waves (ERG, offset 0) | Breaks (ERG) | Total with the cool-down |
| --- | --- | --- | --- |
| `short` (default, zero input) | 3 x 300 s at 95% | 2 x 180 s at 50% | 31 min |
| `vo2` | 6 x 120 s at 112% | 5 x 180 s at 50% | 37 min |
| `sweetspot` | 2 x 900 s at 90% | 1 x 300 s at 55% | 45 min |
| `endurance` | 1 x 2700 s at 70%, with rushes | none | 55 min |
| `drill` (e2e) | 100 s at 60% (WARMUP kind) | a 20 s build break at 50% (WARMUP kind) | 5 min |

The first four start with a 300 s warm-up wave (ERG 50% ramping to 65%) and a 120 s build break at 50%; the totals include them. The first 300 s are ERG at no more than 65%, with no SIM and no haptics (BRIEF 4.6.8).

**Score, grade, XP**
- Score (waves 1-N, the warm-up excluded) = gate + breaches + earnings:
  - gate: 40 x mean(gate HP / max at each wave end);
  - breaches: max(0, 30 - 15 x Breaches);
  - earnings: 30 x min(1, team gold earned / par), where par = 0.75 x the team's planned P_eff in kJ from the warm-up to the last wave.
- Grades: S ≥ 90, A ≥ 78, B ≥ 64, C ≥ 48, otherwise D.
- XP = round(kJ / 10) + a grade bonus (S 60, A 40, B 25, C 10, D 0). Unlocks at cumulative Siege XP: 100 swallowtail pennant, 250 walnut wheel, 500 bronze chain trim, 1000 long banner (`content/siege/cosmetics.json`). `apply_progress` adds the session XP once per session id.
- Per player: gold from the mine vs. bounties, kills, damage, scored Overdrives, wave time on the mine vs. weapons, the station they spent most time on. Team: gate HP per wave, Breaches, leaks, engines stopped, shots fired and hit per station.

**Tuning targets** (`balance.json` `tuning`)
- T1: a compliant Autopilot team scores 64-89 in `short` (mean of seeds 1-3).
- T2: a weapon-only rider earns 40-60% of a mine-only rider's gold per minute.
- T3: leaks per wave-minute stay within ±30% across the four shifts.
- T4: at least 70% of rams and siege towers are destroyed before they reach the gate (a docked tower counts as reaching it).
- Status (final matrix, 2026-10-30, all of S1-S10 passing): T1 met (`short` mean 82.1); T2 0.44 (rules sim); T3 met (leaks per wave-minute: short 0.82, vo2 0.72, sweetspot 0.79, endurance 0.64); T4 met (75/75 siege engines stopped). S4's scores fall strictly with compliance: 82.11, 70.86, 61.76 at 100%, 90%, 80%.

### Where the numbers differ from the brief

All in `docs/decisions/siege.md`:
- "v2 tuning (sim evidence)" and "v2 tuning, round 2": `c_budget` 50 and `bounty_scale` 0.115 (beyond 30% of v0.1.0's 13 and 0.3, with sim evidence), the ram 780 HP and 3.9 HP/s (brief 600 and 3), the staging margin 21 s (brief 30 s), the ballista's chariot preference 0.5.
- "A fourth staging ground by the arch": a fourth staging ground at `prog` 281.3, about 110 m from the gate.
- "Long shifts: a per-shift budget factor" and "T3: per-shift budget factors, round 3": `budget_factor` per shift.
- "Slot factor on B": `slot_factor` (brief 2.4's B line names it).
- "Endurance: the rush share": rushes take 5.6% of B each (brief 8%).
- "trapezoidal position step": the brief's semi-implicit Euler landed up to 1.4% short of closed form.
- "upgrade 2 reaches the wider band": upgrade 2 also lifts the stone's and the arrows' top speed.
- "engine entry before the camp", "the ram pair and escorts", "caps gate routing only", "bounties by fire-time shares; the mine in a Breach": rules the brief leaves open.
- From v0.1.0, still in force: "Overdrive triggers", "Overdrive refusal handling", "Overdrive across a phase change, rescue or AFK", "SAFE-1", "SAFE-2", "Controls in breaks".

## Files

| Path | What |
| --- | --- |
| `game.json` | The manifest (brief 2.2): five contents, the `wave_offset` and `tilt_shift` player options, `first_run_priority` -1, `pixel_base` 960 x 540, `pixel_flex` min 852 x 480 |
| `siege_game.gd` | `SiegeGame` (GameModule): intents, the host loop, the Overdrive directive round trip, events, cues and toasts, results, `apply_progress` |
| `contracts/` | `STATE_V2.md` (what the view and HUD read), `SiegeIds`, `SiegePath` (the map), `SiegeContent` (loads and validates the JSON), the state records (`SiegeState`, `SiegeRiderState`, `SiegeStationState`, `SiegePadState`, `SiegeEnemyState`, `SiegeTarState`, `SiegeProjectile`, `SiegeSpawn`, `SiegeWaveState`), the rules input (`SiegeInputs`, `SiegeRiderInput`, `SiegePhaseInfo`), `SiegeIntents`, `SiegeIntentLimiter`, `SiegeEvents`, `SiegeSnapshotSchema` |
| `rules/` | `SiegeRules.step` (the phase clock, the tick order, B), `SiegePlanBuilder`, `SiegeRouting`, `SiegeEconomy`, `SiegeShop`, `SiegeOverdrive`, `SiegeScore`, `SiegeTune` |
| `combat/` | `SiegeCombat` (the tick's combat order, gate, Breach), `SiegeSpawner` (formations, staging, engines, rushes, cap), `SiegeStations`, `SiegeProjectiles`, `SiegeBallistics`, `SiegeAim`, `SiegeHashRng`, `SiegePads`, `SiegeTarWorks`, `SiegeCombatTable` |
| `autopilot/` | `SiegeAutopilot`: station scores, route choice and shop picks (never Overdrive) |
| `net/` | `SiegeSnapshot` (encode and apply), `SiegeSnapHistory` (client interpolation), `SiegeRoutePredict` |
| `view/` | `SiegeView` and `SiegeViewMath`; `v2/` holds the bake bank, the depth-tested batch and sprite, the shaders, the world layer, machines, crowd, shots and shot replay, the tilt-shift pass and a standalone demo scene |
| `hud/` | `SiegeHud` (the `HudSpec`, palette and help); `SiegeHudCtl` (the base Control) and the plates `SiegeHudSession`, `SiegeHudCrew`, `SiegeHudColumn`, `SiegeHudCockpit`, `SiegeHudWorld`, `SiegeShopPanel`; `SiegeHudModel`, `SiegeCockpitModel` and `SiegeShopModel` (what they say, as data); `SiegeHudDraw` and `SiegeHudType` (the materials and the baked letter) |
| `audio/` | `SiegeAudio`: the adapter around `GameAudioKit`; the sounds are data in `assets/siege/audio/audio.json` |
| `art/` | The CPU rasterizer and its tools: `mock.mjs`, `hud_mock.mjs` (the HUD's approved mock), `hud_font.mjs`, `hud_parts.mjs`, `hud_bake.mjs`, `bake.mjs`, `export_map.mjs`, and `scene.mjs`, `life.mjs`, `world.mjs`, `shade.mjs`, `raster.mjs`, `sprites.mjs`, `png.mjs`, `v3.mjs` |
| `content/siege/` | `shifts.json`, `balance.json`, `stations.json`, `enemies.json`, `waves.json`, `cosmetics.json`, `maps/rotae.json`, `strings.csv` |
| `assets/siege/bake/` | `world.png`, `world_depth.png`, `atlas_0.png` and `atlas_1.png` with their `_depth` twins, `manifest.json` |
| `assets/siege/hud/` | `hud_atlas.png` and `hud_atlas.json`: the HUD's letter, icons and slot shapes |
| `assets/siege/audio/` | `audio.json` (recipes, stroke patterns, loops, bed, cues) and the WAVs it renders to |
| `tests/games/siege/` | `contracts/`, `rules/`, `combat/`, `autopilot/`, `module/`, `hud/`, `view2/`, `integration/`, `sim/` (matrix, checker, headless rules sim), `static/`, `fixtures/`, `siege_fakes.gd`, `siege_kit.gd`, `test_siege_package.gd`, `e2e_check.mjs`, `map_check.test.mjs` |

The rules (`rules/`, `combat/`) are pure `step(state, inputs, dt)` classes at dt 0.05 s. They use only `ctx.rng` (seeded) and `SiegeHashRng`, with no clock and no global random; `tests/games/siege/static` enforces it. Nothing here touches the trainer; Siege reaches it only through `ctx.directives`.

## Content schemas

JSON in `content/siege/`, validated at load by `SiegeContent`. An invalid set makes the host log an error and the module not start.
- `shifts.json`: per content `map`, `label`, `total_s` and an explicit `phases` list. Each phase has `role` (`warmup_wave`, `build_break`, `wave`, `break`), `kind`, `target_pct`, `duration_s`, and optionally `ramp_to_pct`, `mix` and `rushes_at_s`.
- `balance.json`: start gold, routing, output, budget and scaling numbers, `mine`, `gate`, `shop`, `perks`, `overdrive`, `rush`, `autopilot`, `score`, `xp`, `tuning`.
- `stations.json`: the shared aiming and upgrade numbers, one object per station, and `pads` (the Scorpion, pad upgrade costs, the starting pads).
- `enemies.json`: one object per enemy type, plus `lateral_m`, `cap` and `retreat_s`.
- `waves.json`: group timing, `budget_factor`, `slot_factor`, the mixes, `staging`, `engines`, `warmup`, `rush`.
- `cosmetics.json`: the XP unlocks.
- `maps/rotae.json`: generated by `art/export_map.mjs`; never edit it by hand.
- `strings.csv`: every `SIEGE_*` string.

## Tuning knobs

All in `content/siege/`, loaded at start, nothing in code. Never loosen a BRIEF 4.6 limit to fit a design: change the design.
- `balance.json`: `start_gold` 40, `reconnect_s` 2.0, `ref_w` 250, `m_cap` 4.0, `bounty_scale` 0.115, `c_budget` 50, `budget_ref_w` 250, `unverified_factor` 0.85, `wkg_min_power_w` 50.
  - `mine`: 1.0 gold per kJ, `level_bonus` 0.2, level costs 60 / 90 / 130.
  - `gate`: `hp` 130, `iron_bands_hp` 25, `iron_bands_max` 2, `repair_hp` 20, `breach_s` 10, `restore_hp` 30, `breach_loss` 0.3, `warmup_floor_hp` 50.
  - `shop`: Iron bands 45, repair 20, Reserve flywheel 80, Aqueduct drive 100, Spare cauldron 60, `countdown_s` 10.
  - `perks`: `reserve_hold_s` 10, `aqueduct_m` 0.25.
  - `overdrive`: `duration_s` 30 (pinned), `cooldown_s` 90 (at least 30), `refused_retry_s` 30, `min_left_s` 30, `od_mult` 2, `sprint_hold_s` 10, band 1.2-1.4 x FTP.
  - `rush`: `budget_frac` 0.056, `duration_s` 30, `od_bounty_mult` 2.
  - `autopilot`: route every 1 s, switch at most every 8 s and only for a 25% better score, 2 buys per break at 4 s and 9 s, repair below 50%, a 10 s look-ahead, `mine_score` 40, tar works scored with the cauldrons at least 0.667 full, engines within 60 m or any enemy within 40 m, `tar_scale` 20, and the per-station `weights`.
  - `score`, `xp` and `tuning`: the numbers in "Score, grade, XP" and "Tuning targets".
- `stations.json`: `align_deg` 2.0, `retarget_s` 1.0, `lead_rounds` 3, upgrade costs 40 / 50 / 70, `upgrade_out_mult` 1.4, `upgrade_range_mult` 1.25; per station its cap, wind or rack time, range, slew, projectile (speed or speed range, `k`, spread), damage and effect numbers, and `prefer` weights; the tar works' pump, cauldron, curtain and coat numbers; the Scorpion's cost, interval, range, bolt and upgrade numbers.
- `enemies.json`: HP, armour, speed, gate damage, bounty, threat, body size, ranks and spacing per type; the chariot's speed spread, redraw and acceleration; the ram's crew; `lateral_m` 1.8, `cap` 150, `retreat_s` 3.
- `waves.json`: `group_every_s` 6-12, `first_group_s` 3, `stop_before_end_s` 60, `budget_factor`, `slot_factor`, `group_var` 0.8-1.2, the mixes, `staging.reach_before_end_s` 21 and `formation_gap_m` 3, `engines` (`push_lead_s` 60, `pair_gap_m` 25, two rams from 3 slots, `escort_threat_per_slot` 10, `tower_min_wave_s` 300, `crew_back_m` 2-6), `warmup` (`budget_frac` 0.4, `spear_only_s` 180, `ram_hp_frac` 0.5, no escort, `gate_floor_hp` 50, a toast every 60 s), `rush` (spearmen and chariots, a group every 3 s).
- `shifts.json`: waves, breaks, targets and rushes. The PlanValidator checks every change against BRIEF 4.6 at every offset.

## Art pipeline

The art comes from Siege's own CPU rasterizer in `art/` (Node, no dependencies, no fal calls, no downloaded art). `scene.mjs`, `life.mjs`, `world.mjs`, `shade.mjs` and `raster.mjs` draw the world of the approved mockup. Run these from the repo root:

```bash
# Re-render the mockup into build/siege_mock_r2/ (frame.png, frame_2x.png, frame_sharp_2x.png,
# crop_*.png detail crops at x4, details_sheet.png)
node src/games/siege/art/mock.mjs [--out=<dir>]

# Re-bake the game's art into assets/siege/bake/
node src/games/siege/art/bake.mjs [--out=<dir>]

# Render the HUD's mock, one PNG per state; re-bake its letter and icons into assets/siege/hud/
node src/games/siege/art/hud_mock.mjs --out=<dir>
node src/games/siege/art/hud_bake.mjs [--check]

# Regenerate content/siege/maps/rotae.json from the art's geometry
node src/games/siege/art/export_map.mjs
```

- `bake.mjs` writes `world.png` (the static world with sun shadows, AO, outlines and the grade, without tilt-shift, vignette or haze, and without anything that moves or takes a rider's hue), `world_depth.png` (depth `x + y + z` in 16 bits in R and G, the sun in B), two sprite atlases with depth twins (`atlas_0` machines, `atlas_1` units), and `manifest.json` (the generator version, the encodings, the key ramp, the slot and idle ramps, and every part's anchor and frames).
- After a re-bake, refresh Godot's import cache with `tools/godot.sh --headless --path . --import` and commit the PNGs, the manifest and the `.import` files. Bump `BAKE_VERSION` in `bake.mjs` whenever the baked art or its encodings change.
- `node src/games/siege/art/bake.mjs --check` exits 1 when the manifest is missing, does not parse, has another `bake_version` than the code, or names a missing file. It does not compare pixels.
- `node src/games/siege/art/export_map.mjs --check` exits 1 when the committed map differs from the generator's output ("rotae.json is stale"). The rules read only the map, so the picture and the rules can't drift apart.
- Both checks run in the Node tests (`tests/games/siege/view2/bake_check.test.mjs`, `tests/games/siege/map_check.test.mjs`).

## The flex canvas

There are no black bars: the canvas follows the window at a whole scale (`pixel_flex` min 852 x 480).

| Window | Scale | Canvas | Design frame's offset |
| --- | --- | --- | --- |
| 1280 x 720 | 1 | 1280 x 720 | 160, 90 |
| 1920 x 1080 | 2 | 960 x 540 | 0, 0 |
| 2560 x 1440 | 3 | 853 x 480 | -29, -36 |
| 3440 x 1440 | 3 | 1146 x 480 | 93, -36 |
| 3840 x 1080 | 2 | 1920 x 540 | 480, 0 |
| 3840 x 2160 | 4 | 960 x 540 | 0, 0 |

- **World-to-screen math stays.** `to_art()`, the map, every frame and the HUD's tags still measure from the design frame's top-left. `SiegeViewMath.view_offset` puts that corner on the canvas: centred, as the HUD's rects across the middle are, and moved no further than keeps `MUST_SHOW` on the canvas. `MUST_SHOW` (29, 36, 852 x 480) is the road's west bend and lowest loop, the fort, the wheels and the hamlet, and its size is the `pixel_flex` min.
- **The bake.** `world.png` and `world_depth.png` are 1920 x 1084: the design frame byte for byte (the test pins its hash), at `world.origin` (480, 272), and more terrain all round from the same rasterizer. The road's tail west of the camp is art only (`world.mjs` `ROAD_TAIL`): the rules' road still starts at the camp. The atlases bake against the frame alone and don't change. Attackers fade in over the road's first 6 m, on screen on a wide canvas.
- **What it covers.** Any canvas up to 1920 x 1084: every usual window up to 7680 x 4320. A window with a low or tall shape stays at scale 1 and can pass that (3440 x 900 is a 3440 x 900 canvas). Past the bake each edge continues with that edge's margin mirrored back and forth (`SiegeV2WorldLayer.tiles`): you can see the mirror, but there is no black and no second fort.
- **The screen pass.** `SiegeV2TiltShift.set_canvas` covers the canvas. A short canvas keeps the design frame's focus band in focus; a tall one keeps the base's blurred rows at its edges, so there are never more blurred rows than at the base.
- **The HUD.** The HudLayer anchors the rects. They fit at 852 x 480 with no overlap: the column ends on the base's middle row so it stays at the top right, the cockpit starts left of the middle so it stays centred, and the banners fit between the session plate and the column. `SiegeHudWorld` adds `shift()` to the anchored rect to reach the view's offset, for its tags, its banner and the help's points on the world.

## View architecture

`SiegeView` is a Node2D in the platform's `PixelViewport`; its origin is the design frame's top-left (see "The flex canvas"). It only reads `SiegeState` (`contracts/STATE_V2.md`) and the module's `cue` signal. Its children, in draw order:
1. **Baked world** (`SiegeV2WorldLayer`): `world.png` as one sprite at art pixel 0, 0.
2. **Depth-tested sprites**: `SiegeV2Machines` (wheels, walkers, the junction's 20 route overlays and station shafts, stations at their yaw and animation phase, the tar works, the gate's damage stage, curtain and coat, pads), `SiegeV2Crowd` (up to 150 enemies, a docked tower, boarders, the march home) and `SiegeV2Shots` (projectiles and impacts). Each is a `SiegeDepthBatch`: one RenderingServer canvas item per atlas with that atlas's material, sorted far to near. The ADR measured a whole fort, 150 enemies and 100+ projectiles at 7 draw calls.
3. **Tilt-shift** (`SiegeV2TiltShift`): a screen shader with the fort in the sharp band (rows 95-500), plus haze and a vignette. The local rider's `tilt_shift` option off keeps the picture sharp and keeps the haze and vignette.

How the depth test works (`view/v2/siege_depth_sprite.gdshader`):
- Every atlas frame has a depth twin: each pixel's depth relative to the frame's anchor.
- The drawer passes the anchor's world depth in the draw's modulate colour: 16 bits in R and G, in the world encoding. B holds the ramp row x 16 + the sun shade (0-15); A is the opacity.
- The shader adds the two depths and discards the pixel when it lies behind `world_depth.png` at that art pixel (bias 0.04 m). So enemies vanish behind walls, trees and dunes, and the onager's arm passes behind its frame.
- The shader uses plain textures and `texelFetch` only, for the Compatibility renderer.

Key-ramp recolour:
- Rider-hue pixels bake as a magenta key ramp: R = B = 255, G = 4 + 8 x index, where index = tone level x 2 + outlined.
- The shader maps the index to the ramp row from B: a slot's ramp (Okabe-Ito orange, blue, yellow, green) when a rider drives the part, otherwise the part's idle material (timber, rope, bronze, dark stone). One frame serves all four riders.

What the view shows: each wheel turning at rim speed 1.2 m/s x P_eff / 250 W (at most 3 m/s), with 1-3 walkers by P_eff (150 / 300 W, 20 W hysteresis); each rider's powered path to their target, lit through the 2 s reconnect (the mine in breaks and the cool-down); the station's moving part in the hue of the first rider routed to it; enemies from `prog` and lateral offset, interpolated over 100 ms on clients (`SiegeSnapHistory`); projectiles replayed from `shot` cues with `SiegeBallistics.shot_velocities` and the station's numbers, landing within a few centimetres of the host's impact; the tar curtain and coat; the gate's damage stage; the siege tower's dock.

A standalone demo needs no session: `tools/screenshot --scene=res://src/games/siege/view/v2/siege_v2_demo.tscn --frames=<n>`. Its user args are `--siege-demo-t=<s>`, `--siege-demo-sharp` (tilt-shift off), `--siege-demo-stress` (150 attackers, a shot every 0.15 s, and a printed line every 60 frames with the update cost, fps and draw calls) and `--siege-demo-mock-pose` (to compare with `build/siege_mock_r2/frame_sharp_2x.png`).

## Net format

The host simulates everything. Snapshots at 10 Hz, events batched in order, intents from clients.

**Intents** (`Telemetry.intents` at 5 Hz; at most 5 per second per peer after junk is dropped, only from peers in `ctx.players`; `SiegeIntents.normalize` casts with `int()` and drops unknown kinds, targets, items, stations and pads):
- `{"k":"route","to":"mine"|0..4|"next"|"prev"|"hot"}` (`"gen"` is accepted as `"mine"`);
- `{"k":"buy","item":"<id>","station":n}` for `upgrade` (stations 1-4), `{"k":"buy","item":"<id>","pad":n}` for `scorpion` and `pad_upgrade` (pads 1-4); other items: `mine`, `iron_bands`, `repair`, `reserve_flywheel`, `aqueduct_drive`, `spare_cauldron`. `"auto":1` marks a pedal-scan auto-confirm;
- `{"k":"overdrive","via":"action"|"surge"|"button"}`.
- `via: "auto"` (or `"auto":1`) intents never end a zero-input fallback and never start Overdrive. No route or Overdrive intents are sent while the shop is open.

**Snapshot** (`SiegeSnapshotSchema`, ints only; decimetres, milliseconds, centidegrees, per mille; at most 8 KB at the 150-enemy cap, pinned by tests):

```
{"v":2,"tick":n,"ph":phase,"pt_ms":n,"gate":[hp,max,breach_ms],"nb":breaches,"ib":iron_bands,"ml":mine_level,"pk":[perks],
 "w":team_watts,"r":[[slot,target,reconnect_ms,od_ms,od_cd_ms,gold,p_eff_w,raw_w,cadence_rpm,rescue,afk]...],
 "st":[[station,level,wind_pm,yaw_cdeg,m_x100,arm_pm]...],
 "pd":[[pad,type,level,cd_ms,yaw_cdeg]...],
 "tar":[cauldron_dl,curtain_dhp,coat_pm,boarded],
 "e":[[id,type,prog_dm,lat_dm,hp,st]...],"q":queued,"gd":gate_damage_dm,"dw":[[station,damage]...]}
```

- `st` has all five stations in id order; `pd` only built pads; `e` the live enemies in spawn order.
- `wind_pm` is the winding; `arm_pm` the animation phase (onager arm, ballista string, arrow rack reload). `gd` is this wave's gate damage in 0.1 HP; `dw` each weapon's damage in the current or last wave.
- `od_ms` is non-zero only while Overdrive is ACTIVE and `od_cd_ms` only in COOLDOWN, so clients derive the state.
- Optional keys, present only when not at their default: `"ru":[1,i,left_ms]` (a rush is on) and `"rk":n` (the arrow organ's next rack, absent at 0).

**Events** (host to all peers, batched and in order; every number declared in `int_fields()`):
- `wave_start` (`ph`, `role`, `n`, `waves`, `b`), `wave_end` (`ph`, `n`, `hp`, `max`, `leaks`), `rush` (`on`, `i`);
- `push` (`id`, `et`, `prog_dm`: one per siege engine as it enters), `dock` (`id`);
- `shot` (`tk`, `src` station 1-3 or 10 + pad, `kind` 0 bolt / 1 stone / 2 arrow / 3 scorpion, `o` [x_cm, y_cm, z_cm], `v` [vx_mms, vy_mms, vz_mms] before spread, `n` count, `sd` the spread seed). A rack of arrows is one event with `n` 12. Clients replay the flight; damage and kills come only from snapshots and `kill` events;
- `kill` (`id`, `et`, `src`, `x2`), `leak` (`id`, `et`, `dmg`), `breach` (`n`), `gate_restored` (`hp`);
- `buy` (`slot`, `item`, `station`, `pad`, `ok`, `why`, `lvl`), `route` (`slot`, `to`), `overdrive` (`slot`, `st` 1 start / 0 end / 2 refused, `scored`, `why`).

Every toast that follows a host rule is raised from these events: on the host where it sends them (its own rider), on each client in `apply_event`. `client_predict` spins the local wheel and shows route changes at once.

## Running and testing

Source `tools/env.sh` (Git Bash) or `tools/env.ps1` (PowerShell) first. Run Godot only through `tools/godot.sh` or `tools/godot.ps1`; they set the hardware and network locks.

**Play solo with a mock trainer.** Start the app, then pick Castellum Rotae ("Choose a game"). Add bots in the lobby if you like.

```bash
tools/godot.sh --path . -- --mock-trainer=erg
```

In PowerShell: `tools/godot.ps1 --path . -- --mock-trainer=erg`. Other profiles are in `docs/GAME_SDK.md` section 20 (for example `--mock-trainer=erg+hr` for a heart rate).

**Host.** Start the relay with `node server/relay/src/main.ts` (it prints `WATTLANDS_RELAY ws://127.0.0.1:8787/v1`; the app uses `ws://localhost:8787/v1` by default). Start the app on each PC as above, adding `--relay=<ws url>` when the relay runs elsewhere. One rider picks "Host a room", chooses Castellum Rotae and a shift, and reads out the room code; the others pick "Join a room" and type it. The host can add bots to empty wheels. No one joins after the start.

**Tests.**
- Siege's GUT tests (strict rules): `tools/run_tests --only=gut --gdir=res://tests/games/siege`. Narrow it with `--gdir=res://tests/games/siege/<dir>`.
- Node tests (sim checker, e2e checker, map and bake checks): `node --test` in `tests/games/siege`.
- Script check: `tools/godot.sh --headless --path . -s tools/check_scripts.gd`.
- Format and lint: `uvx --from gdtoolkit==4.5.0 gdformat src/games/siege tests/games/siege`, then the same with `gdlint`.
- Everything else, conformance included: `tools/run_tests`.
- End to end (host and two clients on the drill; holds three Godot slots): `node tools/e2e/run.mjs --games=siege`.

**Simulation matrix** (S1-S7, S9, S10; S8 is the rules-level GUT sim in `tests/games/siege/sim/test_siege_rules_sim.gd`):
- All of it: `bash tests/games/siege/sim/run_sims.sh`. Reports go to `build/siege/sims/` (`SIEGE_SIMS_OUT`). It runs `fit_check` on every FIT with the expected laps (lap-true phases + 1: short 8, vo2 14, sweetspot 6, endurance 4, drill 3), then `check_sims.mjs`. A failed `fit_check` still runs the checks; the script then exits non-zero.
- Subsets: `bash tests/games/siege/sim/run_sims.sh s2 s5` or `SIEGE_SIMS="s9 s10"`. Seeds: `SIEGE_SEEDS="1 2 3"`. Runs only: `SIEGE_SKIP_CHECK=1`. No `fit_check`: `SIEGE_FIT=0`. Per-run timeout: `SIEGE_GODOT_TIMEOUT` (default 1800 s).
- Scenarios: s9 (four shifts x 4 compliant Autopilot riders x seeds; also S1, S4 at 100%, S5, T1, T3, T4), s2 (`short` with 1 human, 2 humans, 1 human + 3 bots), s3 (a team that barely pedals: one rider at compliance 0.3, three at 0 W), s4 (compliance 0.9 and 0.8), s5 (the drill), s6 (sweetspot with a cadence drop to 40 rpm at 20 min), s7 (vo2 seed 1 again, for determinism), s10 (surgers on vo2 and endurance, and vo2 at offsets +5, -10, 0, +5).
- Check existing reports only: `node tests/games/siege/sim/check_sims.mjs build/siege/sims [--only=S3,S9] [--seeds=1,2,3]`.
- A run that exits 75 lost the Godot lock wait: rerun it.
- One run by hand: `tools/run_game_sim --game=siege --content=short --players=4 --bots=0 --rider=erg:compliance=1.0 --sim-speed=200 --seed=1 --report=build/siege/demo.json`.

**Screenshots.** `tools/screenshot --game=siege --content=short --at=60,360,600,690` (files in `build/screenshots/siege/`). For a Breach, use S3's riders: `--players=4 --rider=erg:compliance=0.3 --rider=zero --rider=zero --rider=zero`; S3's trial (seed 1) first breached at 532 s, and a Breach lasts 10 s.

## Known gaps

- **Endurance is uneven for a compliant team.** At `budget_factor` 0.72 seeds 1-3 grade D (one Breach), A and B. 0.70 gave B, B, B but put endurance 35% under the T3 mean; 0.74 kept T3 but graded D, C, D (ADR "Final T3 factors").
- **Untested on hardware.** Every run used MockTrainer. The ERG targets, the 50 to 117% step, the Overdrive switches, rescue, coasting and panic have not met a KICKR CORE (`HARDWARE_TEST.md`).
- **The renderer is unmeasured on integrated graphics.** The view has only been measured on an NVIDIA GPU. 60 fps at 1080p on integrated graphics with 150 enemies, and the depth test (the anchor depth travels in the modulate colour), need a real check (`HARDWARE_TEST.md` sections 12 and 13).
- **The audio overhaul is unheard.** The owner heard the first version and it failed: no arrows, odd wheels. This one was measured in real sessions and against the scorecard, and read as spectrograms, but no person has listened to it yet (`HARDWARE_TEST.md` section 14, `docs/decisions/audio-siege.md`).
- **`bake.mjs --check` checks the version and the files, not the pixels.** A change to the art code without a version bump and a re-bake passes the check.
- **Cosmetics unlock but can't be equipped.**

## Not built (brief 2.9)

All of P0 is built. From P1 these are not:
- The Caltrop thrower pad weapon (`SiegeIds.PAD_CALTROP` is reserved; `stations.json` has no entry).
- *Fire the coat*: an arrow volley landing on a full coat lights it, for 10 s of 15 HP/s on the bridge, and the coat is gone.
- Archers that shoot at wall crews (a station they hit loses 30% output for 5 s).
- Custom shifts and `.zwo` import, as planned in v0.1.0.

P2 notes:
- A night siege. The view only reads state, but the art is baked, so it needs a second bake (world, atlases and ramps) and a switch in the view.
- An endless mode: waves with no end, where B keeps growing. It needs an open-ended phase and a way to finish.

## Audio

Everything is rendered from `assets/siege/audio/audio.json` by `tools/audio` (`docs/AUDIO_PIPELINE.md`): no samples, no downloads. `SiegeAudio` maps state to parameters and events to cues; `SiegeShotSounds` works out what each shot lands on.

- **The wheel, 1:1 with cadence.** `SiegeView.cranks[slot]` integrates the rider's cadence; the walkers' frames and the strokes read the same `revs`, so they cannot drift. Each revolution: a soft footfall on the planks and a quiet pawl at 0 and .5, one gentle knock of the axle at .75. Under them a low timber rumble that gets louder with cadence and load and never changes pitch, and from about 170 W a dull rub of loaded timber on your own wheel. Nothing in it is an oscillator: every part is noise, a struck body or short grains. The strokes stop dead at 0 rpm. The wheel's own turning stays by watts: the wheel is load, the walkers are legs. FTMS reports cadence about once a second, so the strokes lock to the walkers on screen exactly and to the rider's feet in rate only.
- **Others' wheels** play the pawl and a farther rumble (its own noise, so it can't comb with yours) about 11 LU under yours, without footfalls or the knock.
- **Detail locked to the art:** the mine's picks and the pump's strokes follow their own drawn phase.
- **Shots:** every shot of every weapon has three parts. A release: the ballista's twang, the onager's beam, the organ's rack of twelve strings, the Scorpion's snap. A flight: a looping swoosh with its own variants that runs for exactly as long as the replayed flight, passes over in a short arc in the middle of it, falls in pitch and moves from the launch to the landing across the screen. Every other volley of the organ passes 6 dB under the one before, so you can follow one volley. An impact chosen by what is there when it lands (`SiegeShotSounds`, the host's own tests over what every peer knows, bodies killed in the last 0.3 s included, because the rules take them off the list before any view runs): a slap for spearmen, wood for rams, towers and chariots, a bronze ring for a shield bearer's block, a dull thud and a little sand for the ground, water in the moat. **Every arrow that lands makes its own sound**, at its own moment and on its side of the screen: very short files (60-90 ms) with several variants, a small pitch and level of its own, on a voice pool of its own that takes nothing from the flights, the releases, the stones or the gate. A volley that strikes anything is its hit, at most one of a surface, and one that strikes nothing is one patter, never both.
- **Whose shot:** a shot from the station your wheel lights is yours: release, flight and landing at full level, and only your own stone ducks your wheel. Everyone else's, and a pad's Scorpion, which nobody drives, play 4 to 5 dB under. Other riders' arrows all sound, 5 dB under; their other impacts play at most one per 0.7 s, and the kills one per 1.5 s. A ram or a tower going down always plays. None of this touches the sim.
- **The flights stay out of 2-8 kHz:** they sit around 1-2 kHz, because an owner has already rejected a bed up there in Torque Company's Lights. A real wave holds -12 dB of the master or less there (`tests/games/siege/audio/real_wave_*.json`).
- **The siege:** far horns on a wave, a push and a rush, each ducking the wheel while it blows, soft hooves for a chariot near the gate, the ram, a walking tower's creak and its docking, gate hits (at most one a ram stroke, the same for a host and a client), the Breach (ducks everything but the prompts), a body falling for each kill and a timber crash for a ram or a tower, tar bubbling, pouring and hissing, the junction's clatter louder with team watts.
- **The hill:** gusting wind in two layers of co-prime length, brighter between waves, the far crowd and war drums by enemy count, crows and banners; a far anvil and a lark in the warm-up and the breaks.
- **A pause** stops the battle's sound with the picture, drums included; a safety prompt reads at least 6 LU over the horns, the volleys and the wheel at the cadences and powers the preview rides (the numbers, and the low-cadence, high-power and busy-wave moments that stay under until the prompts duck deeper: `docs/decisions/audio-siege.md`).

`node tools/audio/preview.mjs --game=siege` writes `build/audio_preview/siege.mp3`. `tools/audio/live_mix.gd` records what a real wave plays, bus by bus (`docs/AUDIO_PIPELINE.md`).
