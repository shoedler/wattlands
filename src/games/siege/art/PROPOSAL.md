# Castellum Rotae v2: proposal (mockup stage, not approved)

What changes from v0.1.0. Read it with the frames in `build/siege_mock_r2/` (`node src/games/siege/art/mock.mjs`). Nothing here is built yet. Once approved, it becomes the new `docs/games/siege.md` sections 2.4–3.

## 1. Look

- Presentation `2d`: one fixed wide isometric view at 960 x 540 art pixels (x2 at 1080p), 3.5 px per metre. There is no camera movement, so everything must read at that size.
- The art comes from our own CPU rasterizer (`src/games/siege/art/*.mjs`, about 1 s a frame). It draws:
  - boxes, beams, cylinders and terrain;
  - sun shadows, procedural textures, dithered tone ramps and outlines;
  - tilt-shift.
- In the game:
  - the static world is baked into a colour PNG and a depth PNG, both committed;
  - moving parts (wheels, machine arms, enemies, projectiles, tar) are sprite strips rendered by the same tool;
  - a shader depth-tests the sprites against the baked depth;
  - tilt-shift is a screen shader that the player can turn off.
- Colour rule: rider hue appears only on what a rider drives. That covers their wheel's rim and hub, the powered path through the junction, and the station's moving part. Everything else stays low in saturation. The rider hues are Okabe-Ito orange, blue, yellow and green, each also paired with a pattern (BRIEF 3.9).

## 2. The machines (game scale explained)

Every machine is drawn about 1.5–2.5 times the size of a real Roman one, so it reads at 3.5 px/m. Each is either a new fictional type that is that big, or a cluster of normal-sized machines.

| Machine | Type | Size in the frame | Real reference |
| --- | --- | --- | --- |
| Rotae magnae (4) | Fictional great treadwheels, each built differently: plain six-spoke, a ladder wheel with outside rungs, a bronze inner ring, and an iron-banded paddle wheel. 1–3 walkers inside, by watts | 14 m across | Roman treadwheel cranes, about 4–5 m |
| Tree ballista | Fictional giant scorpio. Each bow arm is a whole lopped fir trunk set in a rope torsion skein as thick as a man is tall (the skeins are the part in rider hue). The string is a ship's hawser and the bolt is a stripped trunk with an iron point | 14 m stock, 17 m span | Large ballistae, about 4–6 m |
| Great onager | Fictional fixed onager. No wheels; its frame sits on a masonry bed that is a slow stone turntable. The arm is a 13 m mast with iron bands (rider hue), and the stone sits in a hide sling | 10 m bed | Onagers, about 4–5 m arm |
| Arrow organ | A cluster of three normal arrow racks (about 2.5 m each) fanned on one tower turntable and fired in ripple off a shared chain drive. The racks are in rider hue | 7 m turntable | Multi-shot racks; the chain drive follows Philo's polybolos |
| Tar works | A cluster of three 2.5 m cauldrons on one hearth, plus a two-cylinder force pump with a rocking beam. It feeds a spout gallery on corbels over the gate. The cauldrons are in rider hue | Gatehouse roof | Ctesibius' force pump (Vitruvius X.7) |
| Woodpecker mine | Two fictional cam-tripped pick hammers, 7.6 m beams with iron picks, hacking the gold seam in the quarried cliff. They share a cam shaft with a four-stamp mill. The beams are in rider hue | Courtyard, at the cliff | Tilt hammers and stamp mills, a few metres |

- **The junction:** a basalt floor with a 4 x 5 grid. Four lane shafts (one per wheel) run east–west, and five station columns run north–south beneath them.
  - At the engaged crossing, a 3.8 m clutch drum in the rider's hue couples a lane to a column.
  - The powered path is one solid bar in the rider's hue, from wheel to station; idle routes are grooves in the floor.
  - Changing station keeps the 2 s reconnect, shown as the drum lifting and dropping onto the new column.

## 3. Map: one road

- There is one dry road, 376 m long. It runs from the attackers' camp (west edge), down through a far loop to the south, then back east past the aqueduct and the vicus, to the bridgehead plaza.
- Then come the 16 m bridge over the moat and the only gate.
- At 1.8 m/s, infantry need 209 s from the camp to the gate.
- Coverage at the ranges below, measured on the mock's road:

| Station | Range | Road covered | Blind stretch |
| --- | --- | --- | --- |
| Tree ballista (NW tower) | 0–110 m | 328 m | the south-east loop by the aqueduct (s 101–149) |
| Great onager (courtyard) | 30–100 m | 262 m | the far south loop (s 108–203), the plaza and bridge, the camp end |
| Arrow organ (SE tower) | 40–115 m | 293 m | the camp end (s 293–376) |
| Tar works (gate) | bridge and plaza | 16 m bridge, 12 m plaza | everything else |
| Build pads (4, on the wall towers) | 0–60 m | 94–133 m each | most of the road |

- No station covers the whole road, so as a wave moves along it, the best station moves too. That's the strategic core.

## 4. Stations (rider caps)

| Station | Cap | Role |
| --- | --- | --- |
| Woodpecker mine | 2 | Economy: 1 gold per kJ of P_eff, x (1 + 0.2 x mine level) |
| Tree ballista | 1 | Heavy pierce in a line. Best against siege engines, and against columns where the road points at the tower |
| Great onager | 2 | Stone with a 5 m splash: area damage on infantry blocks, heavy damage to siege engines |
| Arrow organ | 2 | Ripple volleys of many small arrows. Kills infantry; weak against shields and armour |
| Tar works | 1 | The shield over the gate, and the slick bridge |

- Caps add up to 8 for 4 riders, and a team never covers all five stations. Each switch costs the 2 s reconnect.
- Output stays `m = Σ(P_eff x od) / 250 W`, capped at 4.0, with Overdrive unchanged. `m` sets each station's rate.
- An unpowered station idles. Weapons keep their winding; the mine and pump stop.

### 4.1 Projectiles (all stations)

- Shots are simulated projectiles in the rules, at the 0.05 s step:
  - gravity is 9.81 m/s²;
  - quadratic drag gives `a = −k |v| v`;
  - spread comes from `ctx.rng`.
- The aimer leads its target. It predicts the target's position along the road at its current speed, then solves the launch for that point, iterating with the drag model.
- Misses come from the world, not from dice:
  - chariots change speed;
  - every enemy weaves ±1.5 m;
  - arrows spread;
  - a target can die before the shot lands.
- Damage lands on impact: `max(1, damage − armour)`.
- Clients replay each shot from a `shot` event (tick, station, origin, launch velocity, seed). The snapshot doesn't grow, and every peer draws the same arcs.

### 4.2 Station rules

**Tree ballista.**
- Winds in 5.0 s / m. It fires a 40 kg trunk at 70 m/s (k 0.0004, almost flat) and slews at 25°/s on its turntable.
- The bolt flies on through bodies in a 1.2 m corridor. It deals 120 to the first, and each body it passes keeps a share of its momentum: 75% after infantry, 30% after a siege engine. It stops below 10.
- So a shot along a column (where the road points at the tower) kills several; across the road it hits one.
- Upgrade 3: an iron head that ignores armour.

**Great onager.**
- Winds in 7.0 s / m.
- It throws a 60 kg stone at up to 34 m/s (k 0.0016). The 30–100 m range comes from its release angle.
- It slews only 4°/s on its stone turntable. Switching from one end of the field to the other takes about 20 s, so it rewards picking a cluster and staying on it.
- Splash is 5 m: 160 damage at the centre, falling linearly to 40% at the edge. A siege engine hit directly takes x2.5.
- Flight time is 3–4 s, so chariots often leave the splash.
- Upgrade 3: a 6.5 m splash.

**Arrow organ.**
- Three racks of 12 arrows each fire in ripple, one rack every 1.5 s / m. Each rack reloads while the other two fire.
- Arrows fly at 45 m/s (k 0.006), angle 35–50° for 40–115 m, with σ 2.5° spread.
- Each arrow deals 8 to the enemy within 0.6 m of where it lands.
- Shield bearers in testudo take 30% of arrows; stones and bolts ignore testudo.
- Upgrade 3: four racks.

**Tar works.**
- *Tar supply:* the three cauldrons hold 100 L each and reheat one at a time at 1 L/s in all, with or without a rider.
- *Curtain:* the pump draws 6 L/s x m from the cauldrons into the curtain over the gate. The curtain holds 0–200 HP and is fed 1 HP per litre.
- *What the curtain does:* rams and infantry at the gate hit it before the gate. It also drains 1 HP/s on its own, since the tar runs off.
- *Bridge:* the run-off coats the bridge. A full coat slows everything on the bridge by 50%. Chariots skid, so they lose their speed changes and are easy to hit.
- One rider at m = 1 empties full cauldrons in about 60 s, and they take 5 min to refill from empty. Tar is a station you visit, not one you keep: that's the switching strategy for the fifth station.
- P1 (*fire the coat*): an arrow volley landing on a full coat lights it. That's 10 s of 15 HP/s on everything on the bridge, and the coat is gone.

**Woodpecker mine.**
- The economy station. The picks' strike rate and the stamp mill show the watts.
- The mine level is the old generator level (+20% gold each).

### 4.3 Build pads

- Four marble plinths on the wall towers either side of the gate and on the two side towers. They hold crew-wound weapons bought with gold, which fire on their own without a rider: the Scorpion today, and the Caltrop thrower (P1).
- They give the gate a last line where the riders' stations are weak (the plaza and bridge).

## 5. Enemies (Egyptian-inspired, no real insignia)

| Enemy | HP | Armour | Speed | Notes |
| --- | --- | --- | --- | --- |
| Spear block | 20 each, blocks of 12 | 0 | 1.8 m/s | Marches in ranks, so a stone or a pierce finds several |
| Shield bearers | 40 | 6 | 1.2 m/s | Testudo against arrows (30% get through) |
| Chariot | 60 | 2 | 6 m/s ± 30%, changing every 3–6 s (seeded) | The reason lead-aimed stones miss |
| Battering ram | 600 | 6 | 0.8 m/s | Hits the curtain, then the gate, at 3 HP/s. A destroyed ram's crew scatters as 6 spearmen |
| Siege tower (boss) | 1800 | 6 | 0.5 m/s | Waves of at least 300 s replace the final ram push with one. At the moat edge it drops its bridge onto the wall. Until it is destroyed, it lands 4 spearmen on the wall every 5 s, and they stop the tar works and the nearest pad |

- Archers that shoot at wall crews are P1.
- Everyone follows the road at a seeded lateral offset, with no collisions; the cap is 150 alive.

## 6. Waves on one road

- The threat budget `B`, its formula and the threat mix by third keep their shape. The mix shifts as follows:
  - Raiders become spear blocks;
  - Shield walls become shield bearers;
  - Horsemen become chariots.
- **Staging grounds:**
  - Groups enter at the camp (s 376).
  - Late in a wave, when a group could no longer reach the gate by 30 s before the end, it enters at the furthest staging ground it can still reach the gate from instead. The two staging grounds are the palm grove at s 250 and the wadi at s 150, both hidden by trees and dunes. So short waves (vo2, 120 s) still reach the gate.
- **Siege engines:** a ram (or the boss) starts the wave at the point on the road from which it reaches the moat about 60 s before the wave ends at its own speed. For example, a ram in a 300 s wave starts 192 m out, on the far loop. During the break before, it is shown being dragged into place.
- Active roads, road rotation and the three-road rules are gone.
- Wave end, retreat, the queue cap, the warm-up wave, endurance rushes and the drill keep their current rules.

## 7. Gate, Breach, economy, shop, Overdrive

- Unchanged in shape:
  - the gate (100 HP, Iron bands to 150) and Breach;
  - gold (it was denarii), now personal, earned at the mine and split from bounties by P_eff share;
  - the shop in every break;
  - Overdrive as a 30 s SIM block.
- The shop adds three things:
  - station upgrades (1: +40% output, 2: +25% range, 3: the special above);
  - mine levels;
  - pads.
- New perk: **Spare cauldron**, a fourth cauldron (+100 L), bought once.
- Reserve flywheel and Aqueduct drive stay.

## 8. Autopilot

- Once a second, in slot order, each Autopilot rider takes the station whose predicted damage over the next 10 s is highest. It works that out from the enemies its range will hold and their HP, within the caps.
- It visits the tar works when a ram or the boss is under 60 m from the gate, or when gate damage is coming and the cauldrons are at least 2/3 full.
- It takes the mine when nothing is in any station's range.
- It switches at most once per 8 s, and only for a gain of at least 25%.
- The shop order stays the same, with "station upgrade" in place of "build on the road with most damage".

## 9. Safety and what doesn't change

- Effort plans, ERG targets, the wave offset, Overdrive's one SIM directive, and every BRIEF 4.6 and BRIEF 7 check stay exactly as they are.
- This redesign changes the presentation, the map and the combat rules only.
- Score, XP and unlocks keep their formulas. The tuning targets T1–T4 stay; T4 becomes "≥ 70% of rams and towers destroyed before the gate".
- The numbers above are starting values; the simulation matrix (`tools/run_game_sim`) rebalances them.

## 10. Build plan once approved

1. **Brief:** `docs/games/siege.md` sections 2.4–3 rewritten from this proposal; ADRs in `docs/decisions/siege.md`.
2. **Art bake:** a tool step that writes the static colour and depth PNGs and every sprite strip into `assets/siege/`. It is committed, and a test checks that the files match their generator version.
3. **Rules:** `combat/` is rewritten around stations and simulated projectiles (pure, seeded, 0.05 s), with the new map JSON (one road, staging grounds, station positions and ranges) and content validation. It gets tests for every rule above, including the projectile model against closed-form ballistics with no drag.
4. **View:** a 2D view with the depth-tested sprite shader, the junction showing routes, shot replay from events, and the HUD and help overlay (F1).
5. **Gates:** the siege tests, the script check, lint, conformance, the sim matrix with retuning to T1–T4, fit_check, `e2e --games=siege`, and the full `tools/run_tests` at or above the floor.
