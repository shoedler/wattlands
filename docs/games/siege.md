ultracode

# Wattlands: Generator Siege game brief

You are the lead engineer and orchestrator for Generator Siege, a co-op tower-defense game added as one module to the existing Wattlands platform (tag `v0.1.0` on `main`). Run the work as dynamic workflows with parallel subagents (section 5). I am not available, so never stop to ask: when something is ambiguous, choose what best serves the pillars (BRIEF 3.1 and 2.1 below), record a short ADR (date, decision, alternatives, reason) in `docs/decisions/siege.md`, and continue. Stop at the Definition of Done (section 6) or a fix-round cap, then report honestly. First read `CLAUDE.md`, `docs/GAME_SDK.md`, `docs/ARCHITECTURE.md`, `docs/ART_PIPELINE.md` (skim it: Siege uses no generated art) and `docs/BRIEF.md` sections 1, 2, 3.1–3.10, 4.2, 4.5–4.7, 5, 6 and 7. "BRIEF x.y" refers to `docs/BRIEF.md`.

## 0. Hard requirements

1. Build game `siege` in the existing Godot 4.7 project through the Game SDK only (BRIEF 3.6), and pass `tests/sdk/test_conformance.gd` (with bots, at 1 and 4 players) without changing it.
2. Presentation `3d`: a procedural low-poly miniature built with `addons/wattlands/world3d` on the Compatibility renderer, at 60 fps at 1080p on integrated graphics (BRIEF 3.9). No generated or downloaded art.
3. Co-op for 1–4 riders with one treadwheel each, bots in empty wheels, host-authoritative with room codes (BRIEF 5).
4. Pedaling first. Every phase, the shop and the results work with zero input (BRIEF 3.5).
5. Waves run in ERG and the Overdrive sprint in SIM. Every plan and directive obeys BRIEF 4.6 (see 2.3). Change the design to fit the governor, never the reverse.
6. The platform saves and uploads rides (BRIEF 3.8), with a lap at every wave and break.
7. Every section 4 gate is green, headless, with MockTrainer riders, bots and Autopilot.

## 1. Ground rules

- Every process runs with `WATTLANDS_NO_HW_CONTROL=1` and `WATTLANDS_NO_NETWORK_INTEGRATIONS=1` (source `tools/env.sh` or `tools/env.ps1`; BRIEF 1). Run Godot only through `tools/godot.sh` (or `.ps1`; BRIEF 2) under BRIEF 7's harness rules.
- Work on branch `game/siege` from the latest `main`. If the branch exists, read `docs/decisions/siege.md` and resume. Commit small and conventional with the prefix `siege:`. Never push, open pull requests or change remotes (BRIEF 1).
- You own these paths:
  - `src/games/siege/`, `content/siege/`, `assets/siege/` and `tests/games/siege/`;
  - `.github/workflows/game-siege.yml`;
  - `docs/decisions/siege.md`, `docs/credits.d/siege.md` and `docs/changelog.d/siege.md`.

  Everything else is read-only.
- Change the platform only when a P0 item is blocked. Keep the change small and additive: no renamed API, no changed default, nothing weakened in BRIEF 4.6 or 7. Add tests, update `docs/GAME_SDK.md` if needed, keep the platform suite green, commit the change alone with the prefix `platform:`, and list it in the report.
- P0 must ship. P1 ships once P0 is green. P2 goes as notes in `src/games/siege/README.md`. No "TODO: implement" on a P0 path, and never weaken a threshold or assertion.
- Art budget $0: no `tools/art` or fal calls, even if `FAL_KEY` and `WATTLANDS_ALLOW_ART=1` are set (never set them, or print, log or commit the key; BRIEF 1, 3.10), no `art.json`, no textures. Audio comes from CC0 packs if downloadable, otherwise it is synthesized (BRIEF 3.9), and is credited in `docs/credits.d/siege.md`. No new code dependencies.
- Original designs only: no brands, logos, real insignia, or emblems on banners, flags or shields; no existing characters; no gore. The enemies are generic raiders, not a named real people.

## 2. Game design

### 2.1 Fantasy and pillars

Castellum Rotae ("the wheel fort") is an alternate-history Roman frontier hill fort that runs on spinning power. In its courtyard, one treadwheel per rider drives a central bronze flywheel generator through its own shaft and gears. A rolling-drum counter on the generator shows the team's live watts ("1250 W"). Raiders climb three roads.

Each rider's watts go to one target at a time: a tower (defense now) or the generator (denarii for the breaks). Waves are the intervals, and the breaks between them are recovery and shopping.

- Watts are the currency: towers fire and the generator pays in proportion to P_eff (BRIEF 3.3).
- A decision every 10–30 s at most.
- Readable from 3 m: your pennant, your lit shaft, the drum counter and the gate's HP.
- Failure costs score and denarii, never the workout.

### 2.2 Players and slots

```json
{"id": "siege", "title": "Generator Siege",
 "summary": "Co-op tower defense on a Roman hill fort. Your watts turn a treadwheel; send them to the towers or the generator.",
 "version": "0.1.0", "min_players": 1, "max_players": 4, "bots": true, "presentation": "3d",
 "entry": "res://src/games/siege/siege_game.gd",
 "contents": ["short", "vo2", "sweetspot", "endurance", "drill"],
 "default_content": "short", "e2e_content": "drill", "zero_input_content": "short",
 "first_run_priority": -1,
 "player_options": [{"id": "wave_offset", "type": "int", "min": -10, "max": 5, "step": 1, "default": 0, "label": "SIEGE_OPT_WAVE_OFFSET"}]}
```

- `first_run_priority` −1 keeps Siege off the first run however a tie with Workout's 0 would break.
- `wave_offset` is a per-rider integer stepper. Spell its fields the way `docs/GAME_SDK.md`'s entry format does and record any difference. If the SDK has no integer type, declare it as a choice of the integers −10 … +5 instead of changing the platform. There are no P0 `options`.
- Slots 0–3 own the NW, NE, SW and SE wheels. Each wheel's pennant shows the player's color and a pattern by slot: solid, dashed, dotted and double for slots 0–3 (BRIEF 3.9 pairs colors with patterns but names none), or the platform's pairing if `docs/GAME_SDK.md` defines one. The same pattern marks the rider's chain and strip chip.
- Solo riders may add up to 3 bots, and a multiplayer host may fill empty wheels with bots. A bot is the platform's bot rider (BRIEF 4.2) at the FTP in its `PlayerSlot`, runs Autopilot, is named "Bot n" and flies a pennant with a toothed edge.
- No one joins after the start: Siege ignores telemetry and intents from any peer not in `ctx.players`. A dropped client is AFK (2.4) until it reconnects, keeping its wheel, routing, denarii and share of B, and stays AFK to the end if its reconnect token expires (BRIEF 5.3).

### 2.3 Effort plan

`rules/plan_builder.gd` builds each slot's EffortPlan, bots included, from `content/siege/shifts.json` and the slot's wave offset. Every slot gets the same phases and lengths; only WORK targets differ.

| Phase | kind | mode | Target | duration_s | label |
| --- | --- | --- | --- | --- | --- |
| Warm-up wave | WARMUP | ERG | `target_pct` 50, `ramp_to_pct` 65 | 300 | "Warm-up wave" |
| Build break | RECOVERY | ERG | 50 | 120 | "Build break" |
| Wave n | WORK | ERG | Shift's wave target + the wave offset | Shift's wave length | "Wave n" |
| Break n (between waves) | RECOVERY | ERG | Shift's break target | Shift's break length | "Break n" |

Every phase has `lap: true` and no `range_pct`, because Siege never moves an ERG target. The PlanValidator appends the cool-down (180 s at 50%); Siege never writes it.

**Wave offset** (P0): each rider's `wave_offset` (`PlayerSlot.options`, −10 … +5 points, default 0; bots 0) is added to their WORK targets only. The builder clamps the result to ≤ 105% in waves longer than 240 s and ≤ 117% in waves of 240 s or less. This also covers P1 custom shifts, whose rule likewise lets only waves of 4 min or less go above 105%.

| Content | Waves (ERG, offset 0) | Breaks (ERG) | Total | BRIEF 4.6 check, at every offset |
| --- | --- | --- | --- | --- |
| `short` (default; zero input) | 3 × 300 s at 95% | 2 × 180 s at 50% | 31 min | ≤ 100%, so no duration counter runs; no phase is longer than 300 s |
| `vo2` | 6 × 120 s at 112% | 5 × 180 s at 50% | 37 min | ≤ 117%: above 105% for at most 120 s per wave and never above 120%. Each break spends 180 s at ≤ 90%, which resets both counters |
| `sweetspot` | 2 × 900 s at 90% | 1 × 300 s at 55% | 45 min | Phases over 300 s stay ≤ 95% |
| `endurance` | 1 × 2700 s at 70%, with a rush every 480 s | None | 55 min | ≤ 75% |
| `drill` (e2e) | A 20 s build break at 50%, then a 100 s wave at 60%, both WARMUP | None | 2 min plus cool-down | ≤ 65%; no WORK phase, so no offset |

Totals include the 300 s warm-up, the 120 s build break and the 180 s cool-down (drill: its own 120 s plus the cool-down).

Every row also passes these checks:
- 4.6.8: the first 300 s are ERG at ≤ 65%, with no SIM or haptics.
- 4.6.1: targets stay within 50–117% FTP. Below an FTP of 100 W, the 50 W floor lifts the 50% targets.
- 4.6.2: the biggest step, 50% → 117%, takes ≤ 9 s at an FTP of 400 W, and wave clocks don't wait for it.
- 4.6.3: every wave is planned at ≥ 60% FTP, so rescue is armed in every wave unless the unverified factor takes the applied target below 60%. Siege treats rescue as a stagger.
- The unverified-FTP factor of 0.85 only lowers targets.
- 4.5: plans are all ERG, so the PlanValidator never warns about mode switches. At run time Overdrive's two switches bracket one directive SIM block of 30 s, which BRIEF 4.5 exempts from the 30 s spacing, and the 90 s cooldown keeps its return to ERG ≥ 90 s from the next switch to SIM.

Siege sends exactly one directive pattern through `ctx.directives.request`. Overdrive is a short SIM block, `{mode: SIM, duration_s: 30, reason: "overdrive", source: "siege"}`:
- It is sent only while `frame.phase` is a WORK phase with ≥ 30 s left, never during rescue, and never from Autopilot's own intents or from bots (a human's `surge` still triggers it with Autopilot on, 2.5).
- 4.6.6: it sets no `mode_grade` and no `haptic` (each would open its own channel, BRIEF 3.6), so the stacked grade is the virtual-gear offset alone, clamped to the user's range.
- 4.6.8: WORK phases start at 420 s.
- 4.6.1: it sets no ERG target.
- On expiry it reverts to the phase's planned target (BRIEF 3.6), through the controller's ramped switch (BRIEF 4.5) and the 4.6.2 slew. Siege sends no restore directive.

Siege sends no haptics, mode grades or target changes, and a Breach never alters a plan.

### 2.4 Rules and mechanics

Rules are pure `step(state, inputs, dt)` classes at dt 0.05 s and use only `ctx.rng` (BRIEF 3.6). The phase clock comes from `frame.phase`, the same for every slot. Units are m, s and P_eff W. Every number below lives in `content/siege/*.json`, validated at load.

**Routing**
- Each rider's target is the generator or a built pad, 1–8.
- Controls: `swap` or right moves to the next target clockwise, left to the previous one, up to the generator, and down to the "hot" tower (the Autopilot's pick). They skip empty pads and towers that already have 2 riders.
- A change reconnects after 2 s, with no output in between.
- Everyone starts on the generator. During breaks, all output goes to the generator and each rider's target is kept.

**Tower output**
- m = Σ(P_eff × od) / 250 W, × 1.4 after upgrade 1, capped at 4.0.
- od = 2 while that rider's Overdrive is on and their raw power is at least CP; otherwise 1.
- Fire interval = base interval / m.
- An unpowered tower idles. Exceptions: Reserve flywheel holds the last m for 10 s, and Aqueduct drive gives m = 0.25.

**Economy**
- The generator pays its riders 1 denarius per kJ of P_eff, × (1 + 0.2 × generator level).
- A kill pays its bounty × `bounty_scale` (start 1.0), split among the tower's riders by P_eff share. Riderless towers earn nothing.
- Denarii are personal, and anyone may buy anything. Each rider starts with 40. Pad 3 starts with a Ballista and pad 4 with a Scorpion.

**Towers (P0)**

Damage = max(1, damage − armor). Hits resolve on the fire tick; projectiles are visual only.

| Tower | Cost | Range | Interval at m = 1 | Effect | Upgrade 3 |
| --- | --- | --- | --- | --- | --- |
| Ballista | 50 | 40 m | 2.0 s | 30 damage to the enemy nearest the gate; pierces up to 4 in a 1 m corridor | Ignores armor |
| Scorpion bolt thrower | 40 | 18 m | 0.8 s | 10 damage to each of the 3 enemies nearest the gate | Hits 5 |
| Caltrop thrower | 35 | 25 m | 4.0 s | After 1.0 s, a 6 m zone at the lead enemy's predicted spot for 4 s: 40% slower, no damage, no stacking | +25% damage taken inside |

Upgrades go in order: +40% output (40), +25% range (50), then the special (70).

**Enemies (P0)**

Enemies follow road polylines with a seeded lateral offset of ±1.5 m and don't collide.

| Enemy | HP | Armor | Speed | At the gate | Bounty | Threat |
| --- | --- | --- | --- | --- | --- | --- |
| Raiders | 20 | 0 | 2.2 m/s | 2 HP, then gone | 1 | 1 |
| Shield wall | 160 | 8 | 0.9 m/s | 8 HP, then gone | 6 | 6 |
| Horsemen | 35 | 0 | 4.5 m/s | 3 HP, then gone | 2 | 2.5 |
| Battering ram | 600 | 4 | 1.0 m/s | 3 HP/s until destroyed or the wave ends | 15 | 20 |

A destroyed ram's crew scatter as 6 Raiders.

**Waves**
- Groups spawn every 6–12 s (seeded) until 60 s before the wave ends.
  - Total threat: B = `c_budget` (start 10) × Σ over slots (planned P_eff / 250 W) × (wave_s − 60) / 60.
  - A slot's planned P_eff in a phase = its planned target (% FTP; in waves the offset included, in a ramp its mean) × its FTP × u × r, so every wave length, team size, offset and scaling mode plays fair. u is 0.85 while the slot's FTP is unverified, otherwise 1 (BRIEF 4.6.1), taken from the slot's verified flag; if `PlayerSlot` has none, add it as a `platform:` change (section 1). r converts watts to P_eff without the host ever needing a weight (BRIEF 3.3): 250 / FTP in FAIR_FTP, 1 in RAW, and in WKG the slot's p_eff_w / power_w from its latest telemetry with power ≥ 50 W (1 before then).
  - Threat mix of Raiders, Shield walls and Horsemen: 70/10/20% in the first third of the shift, 50/25/25% in the middle third, 40/30/30% in the last.
- **Ram push:** at 60 s left, one ram per active road enters 40 m from the gate, escorted by Raiders worth 10 threat per slot. An unopposed ram batters the gate for about 20 s (60 HP).
- **Active roads** = min(3, slots). Fewer than 3 rotate every 30–60 s (seeded), announced by a 5 s horn and a toast.
- **Cap:** at most 150 enemies alive; extra spawns queue. At wave end the queue is dropped, and live enemies retreat for 3 s, then vanish without bounty or damage.
- **Warm-up wave:** 0.4 × B at its mean target (57.5%). Raiders only for 180 s, then Horsemen. Its push is one ram at half HP with no escort. The gate stays at or above 50 HP. Each minute shows one teaching toast.
- **Endurance rushes:** at 8, 16, 24, 32 and 40 min, 30 s of Raiders and Horsemen worth 8% of B, taken from B. Kills during a rush pay double bounty to riders in Overdrive.
- **Drill:** its 100 s phase plays as wave 1 under the normal wave rules (B from its 60% target, the push with escort, no gate floor), with Raiders and Horsemen only, and it counts as wave 1 for the score and `finished`. Its kind stays WARMUP, so it gets no offset and no Overdrive. The rules take each phase's role from `shifts.json`, not from its kind.

**Gate and Breach**
- The gate has 100 HP (150 max with Iron bands).
- At 0 HP it's breached: every tower stops for 10 s, perks included. Enemies arriving during that time vanish without damage, and rams pause.
- Afterwards the gate is back at 30 HP and every rider loses 30% of their unspent denarii, rounded down. The wave and its ERG target run on.

**Overdrive**
- Triggered by ability_1, or by `surge` while its prompt shows. The prompt shows when Overdrive is ready, the phase is WORK with at least 30 s left, the rider isn't in rescue, and their target has an enemy in range or a rush is on.
- It lasts 30 s. Virtual gears work, and the HUD shows the gear. While it is on, the rider's own peer publishes `ctx.hud.power_band(ctx.local_peer, 1.2 × FTP, 1.4 × FTP)`, so the gauge shows the sprint band.
- While raw power is at least CP, routed output counts double. W′ drains as usual (BRIEF 3.4).
- The 90 s cooldown starts when it ends.
- It counts as a scored sprint if the sprint rule (≥ 1.2 × FTP, BRIEF 3.5) held for at least 10 s.

**Shop**

Open in every break, including the build break, with a countdown over the last 10 s.

| Item | Cost | Limit |
| --- | --- | --- |
| Build a Ballista / Scorpion / Caltrop thrower | 50 / 40 / 35 | 8 pads |
| Tower upgrade 1 / 2 / 3 | 40 / 50 / 70 | Per tower |
| Generator level 1 / 2 / 3 (+20% denarii each) | 60 / 90 / 130 | Team |
| Iron bands: +25 max and current gate HP | 45 | Twice |
| Repair the gate: +20 HP, up to max | 20 | Any |
| Reserve flywheel / Aqueduct drive (team perks) | 80 / 100 | Once each |

- It runs on pedal-scan (BRIEF 3.5). The top entry is the Autopilot's recommendation and the second is "Save denarii". Picks auto-confirm after two scan cycles because breaks are ERG phases.
- The host resolves purchases in arrival order. A refused one goes out as a `buy` event with `ok` 0 and the buyer's slot, and only the buyer's peer shows the refusal toast.

**Rescue and AFK**
- `on_rescue` is a stagger: the workers stumble and Overdrive is unavailable. Output keeps counting at actual P_eff.
- `on_afk` stops the wheel. Routing, denarii and the slot's share of B are kept.

**Tuning targets** (G2 meets these)
- T1: a compliant Autopilot team scores 64–89 in `short` (mean of seeds 1–3).
- T2: a tower-only rider earns 40–60% of a generator-only rider's denarii per minute.
- T3: compliant Autopilot leaks per wave-minute stay within ±30% across the four shifts.
- T4: compliant Autopilot destroys ≥ 70% of rams before they reach the gate.

### 2.5 Autopilot and zero input

`autopilot/autopilot.gd` serves `autopilot_intents()` for Autopilot players and bots. It never changes effort targets and never triggers Overdrive.

**Routing.** Once a second, in slot order, route to the tower with the most enemy HP in range (Caltrop throwers use their throw range), within the 2-rider limit. If no tower has an enemy in range, route to the generator; ties go to the lower pad. Switch at most once per 8 s, and only for a target with at least 25% more enemy HP.

**Shop**, at most 2 items per break, in this order:
1. Repair, if the gate is below 50%.
2. Build on the road with the most gate damage: a Ballista against Shield walls or rams, a Caltrop thrower against Horsemen if that road has none, otherwise a Scorpion. With no damage yet, build Ballista, Scorpion and Caltrop thrower in turn on the least-covered road.
3. Upgrade the lowest tower on that road.
4. Generator level.
5. Iron bands.
6. Perks.
7. Save.

**Zero input.** A human counts as Autopilot for routing until their first `route` intent, and for the shop until their first `buy` intent that wasn't auto-confirmed. `overdrive` intents and PedalScanList auto-confirms never end either fallback. While a rider is on the shop fallback, the Autopilot buys for them (at most 2 items per break) and the host ignores their auto-confirmed buys, so nothing is bought twice. A rider who only pedals plays a full shift with Autopilot routing and shop picks, and `surge` still triggers Overdrive.

### 2.6 Multiplayer and network

The host simulates everything (BRIEF 5). Clients send intents in `Telemetry.intents` at 5 Hz: `{"k":"route","to":"gen"|1..8|"next"|"prev"|"hot"}`, `{"k":"buy","item":"<id>","pad":n}` and `{"k":"overdrive"}`. The host validates them and drops anything beyond 5/s per peer. A `buy` picked by the PedalScanList's ERG auto-confirm carries `"auto":1` (if the PedalScanList doesn't report auto-confirms, add that as a `platform:` change).

`snapshot()` sends the full state at 10 Hz as integer arrays:

```
{"v":1,"tick":n,"ph":phase,"pt_ms":n,"gate":[hp,max,breach_ms],"nb":breaches,"gl":gen_level,"pk":[perks],
 "w":team_watts,"r":[[slot,target,reconnect_ms,od_ms,od_cd_ms,denarii,p_eff_w,raw_w,cadence_rpm,rescue,afk]...],
 "tw":[[pad,type,level,m_x100,cd_ms]...],"e":[[id,type,road,prog_dm,lat_dm,hp]...],
 "z":[[road,prog_dm,ttl_ms]...],"f":[[pad,[target_ids]]...],"q":queued}
```

- `f` carries shots for visuals only.
- `r` carries each rider's P_eff W (wheel speed, chains), raw W (teammate strip; %FTP from the slot's FTP) and cadence (worker step rate), because other riders' telemetry never reaches a client (BRIEF 5.5).
- Declare the snapshot's and events' int fields for `Protocol.decode()` if `docs/GAME_SDK.md` offers a way (BRIEF 5.5); either way, `apply_snapshot` and `apply_event` cast every value they read with `int()`, nested arrays included.
- Caps: at most 150 enemies alive, and snapshots of at most 8 KB at that cap (the relay limit is 16 KB).
- Events are batched at no more than 10 messages a second and arrive in the same order on every peer: `wave_start`, `wave_end`, `roads` (active roads changed), `rush`, `kill`, `leak`, `breach`, `gate_restored`, `buy`, `route`, `overdrive`. Every horn and toast that follows a host-side rule is raised from these events on each client in `apply_event` and directly on the host for its own rider, never by a host-only `ctx.hud.toast`.
- `client_predict` spins the local wheel, moves its workers and shows route changes at once. Everything else interpolates road progress over 100 ms. Because every snapshot is full state, a reconnect needs no special handling.

### 2.7 Haptics

None. Waves are ERG, Overdrive is SIM flat, and gate hits are seen and heard only. Siege uses none of the 4.6.6 budget.

### 2.8 Results and progression

**Score** (waves 1–N, warm-up excluded) has three parts:
- Gate: 40 × mean(gate HP / max) at each wave end.
- Breaches: max(0, 30 − 15 × Breaches).
- Earnings: 30 × min(1, team denarii earned / par), where par = 0.75 × the team's planned P_eff (2.4) in kJ from the warm-up to the last wave. Earnings follow actual P_eff, so effort counts.

Grades: S ≥ 90, A ≥ 78, B ≥ 64, C ≥ 48, otherwise D.

**`results()`** adds custom stats to the platform's per-player rows:
- Per player: denarii from the generator vs. bounties, kills, damage, scored Overdrives, wave time on the generator vs. towers, and towers built.
- Team: gate HP per wave, Breaches, leaks by road, and rams stopped.

**XP and unlocks**
- XP = round(kJ / 10), plus a grade bonus of S 60, A 40, B 25, C 10 or D 0.
- Unlocks at cumulative Siege XP: 100 swallowtail pennant, 250 walnut wheel, 500 bronze chain trim and 1000 long banner. They're declared in `content/siege/cosmetics.json`.
- `results()` puts each slot's session XP (round(kJ / 10) from its results row, plus the grade bonus) in that slot's GameResults row. On every peer, `apply_progress(results, progress)` (BRIEF 3.6) adds the local rider's session XP to their cumulative Siege XP in `ctx.progress` and returns the cosmetics whose thresholds the new total crosses, which the results screen shows. No client's progression reaches the host.

**Signals and the end.** Siege emits `phase_changed(index)` in the step where `frame.phase` first shows a new index (every slot shares it), unless `docs/GAME_SDK.md` says the GameHost emits it. Laps come from `lap: true`, so Siege never emits `lap_marker` (it would double them). `finished("complete")` fires when the last wave ends. In the platform's cool-down (`frame.phase` kind COOLDOWN), `sim_step` still runs: nothing spawns, enemies retreat, the shop and Overdrive stay closed, and the workers wave in a victory march.

### 2.9 Content

**P0**
- Map: Castellum Rotae (`content/siege/maps/rotae.json`), with the West, Valley and East roads, eight pads and one gate.
- Shifts: the five above, and the per-rider wave offset.
- Towers: Ballista, Scorpion and Caltrop thrower.
- Enemies: Raiders, Shield wall, Horsemen and Battering ram.
- Systems: the shop, perks, Overdrive, Breach, grades and XP.

**P1**
- Onager: 70; range 10–35 m; 3.5 s; a 1.5 s lob; 45 splash damage in 4 m. Special: 6 m.
- Gate cauldron on a ninth pad over the gate: 60; every 3 s, 60 damage to every enemy in the 12 m gate plaza (pitch and steam). Special: rams take double.
- Siege-tower boss:
  - In shifts with waves ≥ 300 s, it replaces the final ram push and enters on the Valley road at the start of that wave.
  - 2500 HP, armor 6, 0.5 m/s, bounty 60.
  - 10 m from the wall, it releases 4 Raiders every 5 s.
- Custom shifts, set by the host as `options`: 1–10 waves of 1–20 min at 60–105%. Waves of ≤ 4 min may go to 115%, each followed by ≥ 3 min at ≤ 60%. Breaks last 2–10 min at 50–60%.
- `.zwo` import through the platform's `workout_import` parser (BRIEF 3.7) maps blocks to waves and breaks, clamped to the custom-shift limits and listed.
- Equipping cosmetics.

**P2:** a second map, an endless mode and a night siege.

## 3. Presentation

**Art direction**
- Layout comes from `docs/concept/siege_roman_four_wheels.jpg`: four wheels around a central drum generator, each driving it through its own shaft and bevel gears, in a walled courtyard with corner towers, terracotta roofs and the gate in the south wall, facing the camera.
- The hill and roads come from `docs/concept/siege_roman_treadwheel.jpg`: three dusty roads up a faceted ochre hill with grey rock faces, cypress and olive trees, hazy mountains, a lake and a distant aqueduct for scale.
- Apply the `docs/concept/NOTES.md` fixes (its section numbers refer to the old all-in-one brief and are historical; this brief wins):
  - plain block walls, without masonry or crenellations;
  - no emblems;
  - the readout sits on the drum itself and reads "1250 W";
  - workers walk at the bottom of the wheel;
  - no horned helmets.

**Look**
- Every mesh is a GDScript `LowPolyMesh`: primitives, flat shading, vertex colors and no textures. Merge static meshes per material.
- There's no depth of field. The miniature feel comes from a high, narrow camera, tiny people beside big machines, a warm palette, and haze (Environment fog if Compatibility supports it in 4.7, otherwise vertex colors blended toward hazy blue beyond 120 m).
- A vignette under the HUD darkens the corners by at most 12%.

**Palette**

| Role | Hex |
| --- | --- |
| Terracotta (roofs) | `#B5553A`, `#CF7A55` |
| Marble white (walls, pads) | `#E8E2D4`, shade `#CFC6B4` |
| Weathered bronze | `#8A6A3B`, `#B98C46`, patina `#5F8F7B` |
| Dark olive (trees) | `#48552B`, `#66733A` |
| Ochre ground; road dust | `#C7A15A`; `#DCC79C` |
| Hazy blue | `#9BB3C7`, `#B9CCDA`, lake `#7F9DB4` |
| Wood; rock; iron | `#7A5333`, `#563A24`; `#8E8983`; `#4A4A4E` |
| Enemy cloth, leather, shields | `#6E5E4C`, `#857A6B`, `#7A6650` |

Player colors are the only saturated hues; enemies never use them.

**Scene**

`view/siege_view.gd` returns a Node3D that only reads state.

- Map: the fort is about 64 × 52 m on a plateau. Roads run 100–120 m from off-screen spawns to a gate plaza. Pads 3 and 4 flank the gate, and every road passes within 18 m of at least two pads and within 40 m of at least four. A wall-walk graph routes the chains.
- Camera: a fixed miniature rig at a high three-quarter view (pitch about 42°, FOV 30–35°). The fort fills 55–60% of the width in the upper half, with the last 60–80 m of each road below it. There's a 4 s push-in at the start, and the view shakes by up to 0.15 m on gate hits of 8 HP or more.
- Light: one warm, shadowed sun from the front left, the `world3d` sky and ambient, and SSAO off.
- Wheels: 5 m, wooden, each with a pennant. Rim speed = 1.2 m/s × P_eff / 250 W, up to 3 m/s.
  - One to three tiny block workers in off-white tunics walk at the bottom of each wheel: one below 150 W P_eff, two up to 300 W, three above, with 20 W hysteresis.
  - Step rate = cadence / 30 Hz, and stride = rim speed / step rate, clamped.
  - No close-ups and no bicycles.
- Generator: a 6 m bronze flywheel. Four `Label3D` digit drums and a "W" plate show team raw watts (a 1 s mean), rolling with 0.4 s easing and clamped at 9999. Digits are ≥ 48 px at 1080p (BRIEF 3.9).
- Routes: a wheel's radial shaft glows in the rider's color while they route to the generator. A tower route is a MultiMesh chain along the wall-walk in the rider's color and pattern (2.2). It lights up over the 2 s reconnect, then scrolls at a rate proportional to P_eff. Only active routes show.
- Towers:
  - Silhouettes: the Ballista is a big bow frame, the Scorpion a small triple frame, the Caltrop thrower a sling arm.
  - Levels show as 1–3 bronze bands. Empty pads are marble plinths, and a new tower scales up over 1 s.
  - Caltrop zones are iron spikes inside a faint ring, and bolts are thin boxes with trails.
- Enemies: blocky and muted, with plain shields and helmets.
  - Raiders carry spears, a Shield wall is a 2 × 4 block of shields on legs, Horsemen ride blocky horses, and the ram is a roofed shed on wheels with a log and crew legs.
  - Each type is one MultiMesh with a vertex-shader walk bob.
  - HP bars appear only on damaged Shield walls, Horsemen and rams.
- Gate: dark wood. It gains iron bands with each upgrade and loses planks at 66% and 33%. On a Breach it bursts open in `CPUParticles3D` dust.
- Scatter: about 600 cypress, 400 olive trees and 300 rocks as MultiMesh, from a fixed seed in the map.
- Budget at the enemy cap: ≤ 250 draw calls, ≤ 400k triangles, ≤ 60 `Label3D`s, one shadowed light, and no per-enemy nodes for Raiders, Shield walls or Horsemen.

HUD (`hud_spec()`, kit widgets per BRIEF 3.9):

| Position | Contents |
| --- | --- |
| Top left | Phase timeline with the next-phase preview; a Siege rush-marker strip below it |
| Top right | Gate HP as a big readout, and own denarii |
| Bottom left | Power gauge with target band, cadence, W′ bar |
| Bottom center | Teammate strip: each rider's color and pattern chip, raw W, %FTP, target icon and markers |
| Bottom right (Siege) | Routing card with a 2 s connect bar; Overdrive button with cooldown and prompt |

- The kit's toasts and its rescue and warm-up banners also show. The gear indicator appears only in Overdrive.
- Where a kit widget can't carry Siege data (the strip's target icon and markers), Siege draws that part in its own Control beside the widget. The shop panel uses the platform's pedal-scan component (BRIEF 3.5, 6).
- Siege adds wave info ("Wave 2/3", remaining enemies by type, ram warning) and a shop panel with ≥ 32 px text.
- Gate HP, own watts and denarii are ≥ 48 px. The center stays clear.

Audio: a wheel creak and a generator hum, both pitched by watts; tower shots, hooves, the ram and the gate, horns and coins.

Strings: `content/siege/strings.csv`, with keys prefixed `SIEGE_*`.

## 4. Testing and gates

Unit tests (GUT, `tests/games/siege/`) cover every rule and table number in 2.3–2.8, and in particular:
- every content at FTP 80, 200 and 400, verified or not, and at wave offsets −10, 0 and +5, passes the PlanValidator with no warnings and exactly the phases, totals and 4.6 checks in 2.3 (the simulation matrix sets offsets with `--player-options`, BRIEF 3.6);
- `wave_offset` from `PlayerSlot.options` clamps to −10 … +5 (bots 0), and the first run never picks Siege; with P1 custom shifts, a 300 s wave at 105% with offset +5 builds at 105%, and a 240 s wave at 115% with +5 builds at 117%;
- no `lap_marker` is emitted; COOLDOWN spawns nothing and sends no directive; XP is added exactly once per session in `apply_progress`, on the host and on a client, including a client restarted during the cool-down, and each unlock fires once;
- tower output is linear (0.5 at 125 W, 2.0 for two riders at 250 W each) and caps at 4.0;
- the generator pays 1 denarius per kJ, ±0.1%;
- B and par follow 2.4's planned P_eff in FAIR_FTP, WKG and RAW, verified or not, without reading any weight;
- every Overdrive precondition and directive field (exactly `mode`, `duration_s`, `reason` and `source`; no `mode_grade`, `haptic`, `target_*`, `crr` or `cw` key), including refusal in warm-up, breaks, rescue and with < 30 s of the wave left;
- the grade band edges;
- Autopilot hysteresis, shop order, never using Overdrive, and the zero-input fallback: a human with Autopilot off who only pedals, triggers Overdrive by `surge` and sits through auto-confirmed shops keeps Autopilot routing and shop picks for the whole shift, with no double purchase;
- snapshots come back as ints after a JSON round trip and are ≤ 8 KB at the cap;
- a client's teammate strip shows each rider's raw W and %FTP from the snapshot; a refused purchase toasts only on the buyer's peer;
- the view builds headless from a fixture;
- the drum shows 0, 7, 1250, and 9999 for 12000;
- the wheel and worker formulas;
- no string keys are missing.

Static tests:
- Nothing in `src/games/siege/` references `TrainerController`, `SafetyGovernor`, `FtmsClient`, `write_control`, `set_target_power`, `set_simulation` or `set_resistance`.
- `rules/` and `combat/` use no `Time.`, no `OS.get_ticks*`, no global `randi`/`randf`, and no `RandomNumberGenerator.new()`.

Rules-level sims: `tests/games/siege/sim/test_siege_rules_sim.gd` (GUT collects only `test_*.gd` files) drives the helper `tests/games/siege/sim/siege_headless_sim.gd`, which steps the rules with synthetic riders, and asserts T2, the Breach and Overdrive cases, and S8.

Simulation matrix: `bash tests/games/siege/sim/run_sims.sh` calls `tools/run_game_sim --game=siege --content=<id> --players=<n> --bots=<n> --rider=<profile> --sim-speed=200 --seed=<n> --report=build/siege/sims/<name>.json` with the mock rider profiles in BRIEF 4.2: ERG followers at 100, 90 and 80% compliance (`erg:compliance=1.0`, `0.9`, `0.8`), a 0 W rider (`zero`), a cadence collapse to 40 rpm at 20 min (`erg+cadence_drop:rpm=40,at_s=1200`) and a surger (`erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=130`, which fires the ERG `surge` gesture every 60 s and rides 130% FTP while its trainer is in SIM). `--players` counts human slots and `--bots` adds bot slots after them (BRIEF 3.6). Sim riders send no `route` intents and no manual `buy` intents, so they play as Autopilot (2.5) without any flag. A run with two or more human slots runs as HOST, so a 0 W rider is marked AFK after 10 s instead of paused (BRIEF 3.6, 4.6.4, 7.4); one human slot, even with bots, runs as SOLO. S3 relies on this: a solo 0 W run would pause and end with `end_reason: paused` 120 s later (BRIEF 3.6), before the first full wave. Then `node tests/games/siege/sim/check_sims.mjs build/siege/sims` asserts:

| # | Run | Assertion |
| --- | --- | --- |
| S1 | `short`, 4 compliant Autopilot riders, seeds 1–3 | ≤ 1 Breach each; T1 holds |
| S2 | `short` with 1 human, 2 humans, and 1 human plus 3 bots (4 wheels) | ≤ 1 Breach each; T1 holds |
| S3 | `short`, `vo2`, `sweetspot` and `endurance`, with 4 riders at 0 W | A Breach in the first full wave |
| S4 | `short` at 100%, 90% and 80% compliance | The mean score falls strictly as compliance drops |
| S5 | Every content at offset 0, plus `vo2` with 4 riders at offsets +5, −10, 0 and +5 (`--player-options='[{"wave_offset":5},{"wave_offset":-10},{"wave_offset":0},{"wave_offset":5}]'`) | Every directive is clamped and matches 2.3; warm-up limits hold; one FIT lap per Siege phase (2.3), plus one for the appended cool-down if the platform laps it (G0 records which) |
| S6 | `sweetspot` with cadence collapsing to 40 rpm at 20 min | Rescue triggers as a stagger and the plan runs on |
| S7 | `vo2` twice with the same seed | Identical events and snapshot hashes |
| S8 | Rules-level sim above, not `tools/run_game_sim`: `vo2`, 4 synthetic compliant riders, `c_budget` × 3 set in the test | ≤ 150 enemies alive with the rest queued, and every snapshot ≤ 8 KB |
| S9 | `short`, `vo2`, `sweetspot` and `endurance`, 4 compliant Autopilot riders, seeds 1–3 | T3 across the four shifts; T4 |
| S10 | `vo2` and `endurance`, 4 surgers; `vo2` at offsets +5, −10, 0 and +5 (`--player-options`) | At least 3 Overdrives per run. Every Overdrive directive matches 2.3 exactly (no `mode_grade`, `haptic`, `target_*`, `crr` or `cw` key) and is applied in SIM with no refusal and no dropped channel, only in a WORK phase with ≥ 30 s left and never in rescue. Each returns to the planned ERG target through the ramped switch. Each Overdrive's SIM span on the 1 Hz trace is 30 ± 2 s (its bracketing pair is exempt from the 30 s spacing, BRIEF 4.5); every other pair of consecutive ERG↔SIM switches per rider, such as one Overdrive's return to ERG and the next one's start, is ≥ 30 s apart (the 90 s cooldown gives about 90 s) |

`run_sims.sh` and `check_sims.mjs` skip S8.

A rules step takes ≤ 1 ms at the enemy cap, so a 55-minute shift simulates in ≤ 66 s.

**Gates** (all must pass):
1. The Siege unit and static tests, under BRIEF 7's strict rules.
2. `tools/godot.sh --headless --path . -s tools/check_scripts.gd`.
3. The SDK conformance test.
4. The simulation matrix.
5. `tools/fit_check`, invoked as recorded in G0, on every FIT file the simulation runs wrote.
6. `node tools/e2e/run.mjs --games=siege`.
7. `tools/run_tests` at or above the G0 baseline plus the Siege tests, and `node tools/e2e/run.mjs --games=<every registered game id>`, with every game that passed at G0 still passing.

**P1 checks:**
- Screenshots: run `tools/screenshot --game=siege --content=short --at=<s>` at 60, 360, 600 and 690 s, and once during a Breach in a run with 4 riders at 0 W (AFK, not paused; BRIEF 4.6.4). If `tools/screenshot` can't set the rider count and profile, skip that shot and record it. Look at each image yourself.
- Performance: run `tests/games/siege/perf/stress_scene.tscn` windowed for 60 s with 150 enemies, 8 towers and 4 wheels. Log the mean and 1%-low frame times against the 16.7 ms budget.

## 5. Orchestration

Use Opus 5.5 for every agent. Never let two agents edit one file at the same time. Godot runs queue on the `tools/godot.sh` lock (BRIEF 2). Run the end-to-end gates (section 4, gates 6 and 7) only while no other agent is running Godot, because one e2e run needs three Godot processes at once.

**G0 setup** (you):
1. Check that `main` contains `v0.1.0` and that the tree is clean. If the only dirt is under `docs/games/` or `docs/concept/` (untracked or modified), commit it unchanged on `main` as `docs: planning material` before cutting the branch, and record that in `docs/decisions/siege.md`; any other dirt stops the run before G0 changes anything, and goes in the final report. Create `game/siege` from the latest `main` and run `tools/new_game siege`. On resume, check out `game/siege` instead and skip every G0 step that `docs/decisions/siege.md` records as done: never rerun `tools/new_game siege` once `src/games/siege/` exists, and never move or recreate an existing `siege-g0` tag.
2. Read the SDK docs, `src/games/_template/`, `src/games/workout/` and the `world3d` API. Record in `docs/decisions/siege.md` what `docs/GAME_SDK.md` and the code say about: the mock rider profiles; how `tools/run_game_sim` counts `--players` and `--bots`, the FTP and verified status it gives each rider, what its report holds and where it writes FIT files; how to invoke `tools/fit_check`, and whether the appended cool-down gets its own FIT lap; how a client's actions and shop picks become `Telemetry.intents`, and how a GameModule learns the local peer id; and what the GameHost does when a client drops or rejoins. Make the smallest additive `platform:` change (section 1) wherever one of these blocks hard requirement 3 or 7: a report field that a section 4 check needs (snapshot hashes and byte sizes; each rider's applied target, mode, `clamped_by` and rescue at 1 Hz; the FIT paths), a way for clients to send intents or learn their peer id, or a dropped client's last telemetry still counting as pedaling.
3. Run the platform suite and `node tools/e2e/run.mjs --games=<every registered game id>`, and record the green counts as a baseline in `docs/decisions/siege.md`. Fix red items only where they block Siege P0, under the platform-change policy in section 1.
4. Write the contracts with doc comments: `game.json`; `src/games/siege/contracts/` (state types plus the intent, snapshot and content schemas); `content/siege/maps/rotae.json`; `content/siege/strings.csv`; `tests/games/siege/fixtures/`; and a stub `src/games/siege/view/siege_view.gd`.
5. Commit, tag `siege-g0`, and record each finished G0 step in `docs/decisions/siege.md`.

**G1 build:** seven parallel builders. Each works on branch `game/siege-<agent>` from `siege-g0`, in its own worktree.
- Every prompt names the sections to read, the paths the agent owns, the contracts, the test command and the report format.
- Builders touch only their own paths and request strings or contract changes in their reports.

| Agent | Owns | Builds |
| --- | --- | --- |
| rules | `src/games/siege/rules/`, `content/siege/{shifts,balance}.json`, `tests/games/siege/rules/` | Plans with offsets, phase clock, routing, economy, gate, Overdrive, shop, grading |
| combat | `src/games/siege/combat/`, `content/siege/{towers,enemies,waves}.json`, `tests/games/siege/combat/` | Roads, enemies, towers, zones, spawner, rushes, cap |
| module | `src/games/siege/siege_game.gd`, `src/games/siege/{autopilot,net}/`, `content/siege/cosmetics.json`, `tests/games/siege/module/` | GameModule wiring, Autopilot, snapshots, events, prediction, cool-down, results, `apply_progress` |
| world | `src/games/siege/view/world/`, `tests/games/siege/view_world/` | Terrain, fort, scatter, camera, wheels, workers, generator, drum, chains |
| units | `src/games/siege/view/units/`, `tests/games/siege/view_units/` | Enemy crowds, towers, pads, projectiles, zones, gate, HP bars |
| hud | `src/games/siege/{hud,audio}/`, `assets/siege/`, `tests/games/siege/hud/` | `hud_spec`, widgets, shop panel, audio |
| qa | `tests/games/siege/{sim,perf,static}/`, `.github/workflows/game-siege.yml` | Sim helper, matrix and checker, static tests, perf scene, CI |

- **Test command:** `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/games/siege/<dir> -ginclude_subdirs -gexit -gjunit_xml_file=build/junit_siege_<agent>.xml`, then `check_scripts`, under BRIEF 7's strict rules.
- **Report:** `{agent, branch, base_sha, head_sha, summary, files, tests_added, test_command, tests_total, tests_failed, junit_path, script_check_ok, decisions, open_issues, strings_needed, contract_change_requests: [{file, change, additive, blocks_p0}], platform_needs: [{need, why, blocks_p0}]}`.
- Rerun each agent's test_command before you accept its report.

**G2 integrate** (you plus up to 3 helpers):
1. Accept additive contract changes. Accept breaking ones only if they block P0.
2. Merge in this order: rules, combat, module, world, units, hud, qa. Run the Siege tests and `check_scripts` after each merge.
3. Wire up the view, `make_view()`, `hud_spec()` and the strings, and merge the decisions.
4. Balance: tune `balance.json` and the content tables until S1–S4 and T1–T4 hold.
   - Stay within ±30% of this brief's numbers unless an ADR records the sim evidence.
   - Stop after six iterations and report any misses.
5. Loop over the section 4 gates until they pass. Progress means fewer failing checks. Stop after two rounds without progress or five rounds in total.

**G3 review:** fresh reviewers, one per dimension:
- safety: every plan, at every wave offset, and every directive against BRIEF 4.5, 4.6 and 2.3; any trainer path other than `ctx.directives` is a blocker;
- rules, determinism and balance;
- network: snapshot size, intent validation, desync, reconnect, AFK;
- zero input, Autopilot and HUD readability, from screenshots;
- presentation and the performance budget, against section 3;
- conformance with this brief: every P0 item reachable;
- code quality and test gaps, plus the platform policy: outside owned paths, `git diff main` contains only `platform:` commits.

Each finding carries severity, file and line, evidence, and a failing test, repro or static test. Findings that need hardware go into `src/games/siege/HARDWARE_TEST.md` instead of being dropped. A separate verifier confirms each finding before it's fixed; drop only what the verifier refutes.

**G4 fix**, at most two rounds of parallel fixers grouped by area, then you:
1. Fix confirmed findings with tests and rerun every gate.
2. Take the final screenshots.
3. Write `src/games/siege/README.md` (rules summary, schemas, tuning knobs and P2 notes); `src/games/siege/HARDWARE_TEST.md`, a real-trainer checklist with expected results and a log template in the style of `docs/HARDWARE_TEST_PLAN.md` (BRIEF 4.7), covering waves at their ERG targets, the 50 → 117% step and its slew in `vo2`, the Overdrive ERG → SIM → ERG switch with no power spike, rescue in a wave, coasting and AFK, panic during an Overdrive, and the G3 findings that need hardware; and `docs/credits.d/siege.md` and `docs/changelog.d/siege.md`.
4. If the Definition of Done is met, merge the latest `main` into `game/siege` and rerun every gate. Then merge into `main` with `--no-ff` and tag `siege-v0.1.0`. Otherwise leave the branch unmerged.

## 6. Definition of Done and final report

- Every P0 item in 2.9 is implemented, reachable from the game picker and tested.
- Every section 4 gate is green, or listed as failing with nothing weakened.
- A host picks Siege and a shift, adds bots and plays through to results with zero input. Two friends join by code, and each rider can set a wave offset on their lobby card.
- Every plan passes the PlanValidator at every wave offset. Every directive is clamped and matches 2.3, and Siege reaches the trainer only through `ctx.directives`.
- Rides carry a lap per wave and break and pass `tools/fit_check`.
- The platform suite stays green, and Workout and every other merged game still pass their e2e runs.
- The README, `HARDWARE_TEST.md` and the three docs fragments are written.
- `main` holds `siege-v0.1.0` locally; nothing is pushed and no remote changed.

The final report, in chat, covers:
- what was built;
- every gate's result with numbers: test totals and failures; Breaches, score and grade per sim scenario; the largest snapshot; e2e duration; frame times;
- which of T1–T4 were met;
- every `platform:` commit, and every deviation from this brief with its ADR;
- what is untested on hardware or Windows, and the top risks;
- the exact commands to play solo with a mock trainer, host, run the tests and run the sim matrix.
