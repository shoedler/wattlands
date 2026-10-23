# Castellum Rotae

Co-op tower defense for 1-4 riders on Collis Rotarum, a Roman hill fort that runs on treadwheels (brief: `docs/games/siege.md`). Each rider turns one wheel; their watts go to one target at a time, a tower (defense now) or the central generator (denarii for the breaks). Waves are ERG intervals, breaks are recovery and shopping, and Overdrive is a 30 s SIM sprint block. Bots fill empty wheels, and every phase, the shop and the results work with zero input. Presentation `3d` (a procedural low-poly miniature on the Compatibility renderer), version 0.1.0. Decisions: `docs/decisions/siege.md`. Real-trainer checklist: `HARDWARE_TEST.md`.

## How to play

- **Pedal.** Your watts (P_eff) drive your wheel. A wave is an ERG interval at your own % FTP, so the trainer sets the load; you hold the cadence.
- **Aim your watts.** Everyone starts on the generator. Outside breaks:
  - `swap` or right moves to the next target clockwise (the generator, then pads 1-8, then the generator again), left to the previous one;
  - up sends you to the generator;
  - down sends you to the "hot" tower, the one with the most enemy HP in range (the Autopilot's pick).
  - Empty pads and towers that already hold 2 riders are skipped. A change reconnects after 2 s, with no output in between.
- **Overdrive.** `ability_1` or the HUD button starts a 30 s SIM sprint block when it is ready, the phase is a wave with at least 30 s left, you are not in rescue and you are pedaling. A `surge` (the ERG surge gesture) starts it too, but only while the prompt shows (your tower has an enemy in range, or a rush is on). While it runs the gauge shows a sprint band of 1.2-1.4 x FTP, virtual gears work and the HUD shows the gear. Keep your raw power at or above FTP (CP) and your routed output counts double. Hold 1.2 x FTP for 10 s and it counts as a scored sprint. The 90 s cooldown starts when it ends.
- **Breaks.** All output goes to the generator and you keep your target. The shop opens in every break (the build break included) as a pick list: the top entry is the Autopilot's recommendation and the second is "Save denarii". With pedal navigation on (Settings) it scans and picks auto-confirm after two scan cycles; off, it takes the keyboard and controller only. Directions and the surge belong to the shop while it is open.
- **Zero input works.** A rider who only pedals is routed and shopped for by the Autopilot until their first deliberate `route` (routing) or non-auto `buy` (shop). A `surge` still triggers Overdrive. Bots never use Overdrive.

## Rules summary

Numbers are the current content (`content/siege/*.json`) after the G2 balance pass. Where one differs from the brief, "Where the numbers differ from the brief" below names the ADR.

**Routing and output**
- Tower output `m = sum(P_eff x od) / 250 W` over the riders on the pad, x1.4 after upgrade 1, capped at 4.0. `od` is 2 while that rider's Overdrive is on and their raw power is at least FTP (the CP, ADR "slot.ftp is Overdrive's CP"), else 1. The fire interval is the base interval / `m`.
- An unpowered tower idles. Reserve flywheel keeps the last `m` for 10 s, Aqueduct drive gives `m = 0.25`.
- A Breach and every non-wave phase silence all towers, perks included.

**Economy**
- The generator pays 1 denarius per kJ of P_eff x (1 + 0.2 x generator level). A kill pays its bounty x `bounty_scale` (0.3), split among the tower's riders by P_eff share; riderless towers earn nothing. A kill in a rush pays double to a rider in Overdrive.
- Denarii are personal; anyone may buy anything. Each rider starts with 40.

**Towers** (hits resolve on the fire tick, damage = max(1, damage - armor), projectiles are visual)

| Tower | Cost | Range | Interval at m = 1 | Effect | Upgrade 3 |
| --- | --- | --- | --- | --- | --- |
| Ballista | 65 | 40 m | 2.2 s | 30 damage to the enemy nearest the gate, pierces up to 4 in a 1 m corridor | Ignores armor |
| Scorpion | 52 | 18 m | 0.8 s | 7 damage to each of the 3 enemies nearest the gate | Hits 5 |
| Caltrop thrower | 45 | 25 m | 4.0 s | After 1.0 s a 6 m zone for 4 s at the lead enemy's predicted spot: 40% slower, no damage, no stacking | +25% damage taken inside |

Upgrades go in order: +40% output (40), +25% range (50), then the special (70). Pad 3 starts with a Ballista and pad 4 with a Scorpion.

**Enemies** (they follow road polylines with a seeded lateral offset of +-1.5 m and don't collide)

| Enemy | HP | Armor | Speed | At the gate | Bounty | Threat |
| --- | --- | --- | --- | --- | --- | --- |
| Raiders | 20 | 0 | 2.2 m/s | 2 HP, then gone | 1 | 1 |
| Shield wall | 160 | 8 | 0.9 m/s | 8 HP, then gone | 6 | 6 |
| Horsemen | 35 | 0 | 4.5 m/s | 3 HP, then gone | 2 | 2.5 |
| Battering ram | 600 | 4 | 0.75 m/s | 3 HP/s until destroyed or the wave ends | 15 | 20 |

A destroyed ram's crew scatter as 6 Raiders.

**Waves**
- Groups spawn every 6-12 s (seeded) until 60 s before the wave ends. The threat budget is `B = c_budget (13) x sum over slots (planned P_eff / 250 W) x (wave_s - 60) / 60`. A slot's planned P_eff = planned % FTP x FTP x u x r, with u = 0.85 for an unverified FTP, r = 250 / FTP in FAIR_FTP, 1 in RAW, and the slot's latest P_eff / power (power >= 50 W) in WKG. No weight is ever read.
- Threat mix (Raiders / Shield walls / Horsemen) by third of the shift: 70/10/20, 50/25/25, 40/30/30. The drill uses Raiders and Horsemen only.
- Ram push: at 60 s left, one ram per active road enters 40 m from the gate, escorted by Raiders worth 10 threat per slot. A ram walks its 40 m in 53 s and batters the last ~7 s (about 20 HP).
- Active roads = min(3, slots). Fewer than 3 rotate every 30-60 s (seeded), announced by a 5 s horn and a toast.
- Cap: at most 150 enemies alive, extra spawns queue. At the end of a phase the queue is dropped and live enemies retreat for 3 s, then vanish without bounty or damage.
- Warm-up wave: 0.4 x B, Raiders only for 180 s then Horsemen, a push of one ram at half HP without escort, the gate never below 50 HP, one teaching toast a minute.
- Endurance rushes at 480, 960, 1440, 1920 and 2400 s of the wave: 30 s of Raiders and Horsemen worth 8% of B, taken from B.
- Drill: its 100 s phase plays as wave 1 under the normal wave rules (B from its 60% target, the push with escort, no gate floor). Its kind stays WARMUP, so no offset and no Overdrive.

**Gate and Breach**
- The gate has 130 HP; each Iron bands purchase adds 25 (max 180 with both). At 0 HP it is breached: every tower stops for 10 s, enemies arriving meanwhile vanish without damage and rams pause. Afterwards the gate is back at 30 HP and every rider loses 30% of their unspent denarii, rounded down. The wave and its ERG target run on.

**Shop** (open in every break, countdown over the last 10 s; the host resolves buys in arrival order, a refusal toasts only on the buyer's peer)

| Item | Cost | Limit |
| --- | --- | --- |
| Build a Ballista / Scorpion / Caltrop thrower | 65 / 52 / 45 | one per pad, 8 pads |
| Tower upgrade 1 / 2 / 3 | 40 / 50 / 70 | per tower |
| Generator level 1 / 2 / 3 (+20% denarii each) | 60 / 90 / 130 | team |
| Iron bands: +25 max and current gate HP | 45 | twice |
| Repair the gate: +20 HP up to the max | 20 | any |
| Reserve flywheel / Aqueduct drive (team perks) | 80 / 100 | once each |

**Overdrive** is the only directive Siege sends: `{mode: SIM, duration_s: 30, reason: "overdrive", source: "siege"}`. No `mode_grade`, haptic, ERG target, `crr` or `cw`, so the stacked grade is the virtual-gear offset alone. It is sent only in a WORK phase with at least 30 s left, never in rescue, never from the Autopilot or a bot. A refusal (host or governor) sets a 30 s retry cooldown instead of 90 s. A phase change, a rescue or going AFK ends a running one (ADR "Overdrive across a phase change, rescue or AFK"). On expiry the platform returns to the planned ERG target through its ramped switch.

**Rescue and AFK.** `on_rescue` is a stagger: the workers stumble and Overdrive is unavailable; output keeps counting at the actual P_eff. `on_afk` stops the wheel; routing, denarii and the slot's share of B are kept.

**Plans.** Every slot gets the same phases; only WORK targets differ by the rider's wave offset (-10..+5 points, clamped to at least 50%, at most 105% in waves over 240 s and 117% in waves of 240 s or less). Every phase is `lap: true`; the platform appends the 180 s cool-down at 50% (nothing spawns, the shop and Overdrive are closed, the workers march).

| Content | Waves (ERG) | Breaks (ERG) | Total before the cool-down |
| --- | --- | --- | --- |
| `short` (default, zero input) | 3 x 300 s at 95% | 2 x 180 s at 50% | 28 min |
| `vo2` | 6 x 120 s at 112% | 5 x 180 s at 50% | 34 min |
| `sweetspot` | 2 x 900 s at 90% | 1 x 300 s at 55% | 42 min |
| `endurance` | 1 x 2700 s at 70%, with rushes | none | 52 min |
| `drill` (e2e) | 100 s at 60% (WARMUP kind) | a 20 s build break at 50% | 2 min |

The first four start with a 300 s warm-up wave (ERG 50% ramping to 65%) and a 120 s build break at 50%; the totals include them. The first 300 s are ERG at no more than 65% with no SIM and no haptics (BRIEF 4.6.8).

**Score, grade, XP**
- Score (waves 1-N, warm-up excluded) = gate 40 x mean(gate HP / max at each wave end) + breaches max(0, 30 - 15 x Breaches) + earnings 30 x min(1, team denarii earned / par), where par = 0.75 x the team's planned P_eff in kJ from the warm-up to the last wave.
- Grades: S >= 90, A >= 78, B >= 64, C >= 48, otherwise D.
- XP = round(kJ / 10) + a grade bonus (S 60, A 40, B 25, C 10, D 0). Unlocks at cumulative Siege XP: 100 swallowtail pennant, 250 walnut wheel, 500 bronze chain trim, 1000 long banner (`content/siege/cosmetics.json`). `apply_progress` adds the local rider's session XP once per session id on every peer.
- Results add per-player denarii (generator vs bounties), kills, damage, scored Overdrives, wave time on the generator vs towers and towers built; team stats are score, gate HP per wave, Breaches, leaks by road and rams stopped.

**Tuning targets** (`balance.json` `tuning`): T1 a compliant Autopilot team scores 64-89 in `short`; T2 a tower-only rider earns 40-60% of a generator-only rider's denarii per minute; T3 leaks per wave-minute within 30% across the four shifts; T4 at least 70% of rams die before the gate. Status: T1, T2 and T4 met, T3 not (see "Known gaps").

### Where the numbers differ from the brief

All in `docs/decisions/siege.md`:
- "2026-10-23 G2 tuning": `c_budget` 10 to 13, gate 100 to 130 HP (max 180 with both Iron bands, not 150), ram speed 1.0 to 0.75 m/s (so an unopposed ram batters about 20 HP, not "60 HP in about 20 s"), Ballista cost 50 to 65 and interval 2.0 to 2.2 s, Scorpion cost 40 to 52 and damage 10 to 7, Caltrop cost 35 to 45. Everything else is the brief's number.
- "2026-10-23 bounty_scale 0.3": beyond the 30% limit, with the T2 evidence.
- "2026-10-22 Overdrive triggers" and "Overdrive refusal handling": `ability_1` and the button start Overdrive without the prompt, and a refusal retries after 30 s.
- "2026-10-22 Controls in breaks": no route or Overdrive intents while the shop is open.
- "2026-10-23 T3 not met" and "S10 ramped returns fail outside the balance": two open items.

## Files

| Path | What |
| --- | --- |
| `game.json` | The manifest (brief 2.2): five contents, the `wave_offset` player option, `first_run_priority` -1 |
| `siege_game.gd` | `SiegeGame` (GameModule): intents, the host loop, the Overdrive directive round trip, events and toasts, results, `apply_progress` |
| `contracts/` | `SiegeIds` (ids and codes), `SiegeMap`, `SiegeContent` (loads and validates the JSON), `SiegeRecord` and the state records (`SiegeState`, `SiegeRiderState`, `SiegeTowerState`, `SiegeEnemyState`, `SiegeZoneState`, `SiegeShot`, `SiegeSpawn`, `SiegeWaveState`), the rules input (`SiegeInputs`, `SiegeRiderInput`, `SiegePhaseInfo`), `SiegeIntents`, `SiegeIntentLimiter`, `SiegeEvents`, `SiegeSnapshotSchema` |
| `rules/` | `SiegeRules.step` (the phase clock and the tick order), `SiegePlanBuilder` (plans, offsets), `SiegeRouting`, `SiegeEconomy`, `SiegeShop`, `SiegeOverdrive` (state machine and directive), `SiegeScore`, `SiegeTune` |
| `combat/` | `SiegeCombat` (tick order, gate, Breach), `SiegeSpawner` (groups, roads, push, rushes, cap), `SiegeTowers` (output, fire, zones), `SiegeCombatTable` |
| `autopilot/` | `SiegeAutopilot`: route choice and shop picks (never Overdrive) |
| `net/` | `SiegeSnapshot` (encode and apply), `SiegeSnapHistory` (client interpolation), `SiegeRoutePredict` |
| `view/` | `SiegeView` (the 3D miniature), `world/` (terrain, fort, scatter, wheels, workers, generator drum, chains), `units/` (enemy crowds, towers, gate, effects), the palette and the draw budget |
| `hud/` | `SiegeHud` (the `HudSpec`), the HUD model, routing card, Overdrive button, teammate strip overlay, rush strip, wave info, shop model and panel |
| `audio/` | `SiegeAudio`: wheel creak and generator hum pitched by watts, tower shots, hooves, ram, gate, horns and coins, all synthesized |
| `content/siege/` | `shifts.json`, `balance.json`, `towers.json`, `enemies.json`, `waves.json`, `cosmetics.json`, `maps/rotae.json`, `strings.csv` |
| `tests/games/siege/` | `contracts/`, `rules/`, `combat/`, `module/`, `view/`, `hud/`, `integration/`, `sim/` (matrix and checker), `perf/` (stress scene), `static/`, `fixtures/`, `siege_fakes.gd`, `e2e_check.mjs` |

Rules (`rules/`, `combat/`) are pure `step(state, inputs, dt)` classes at dt 0.05 s with only `ctx.rng` (seeded), no clock and no global random, enforced by `tests/games/siege/static`. Nothing here touches the trainer; Siege reaches it only through `ctx.directives`.

## Schemas

**Intents** (`Telemetry.intents` at 5 Hz, at most 5 per 20 game ticks per peer after junk is dropped, only from peers in `ctx.players`):
- `{"k":"route","to":"gen"|1..8|"next"|"prev"|"hot"}`
- `{"k":"buy","item":"<id>","pad":n}`, with `"auto":1` when the pedal-scan list auto-confirmed it. Items: `build_ballista`, `build_scorpion`, `build_caltrop`, `upgrade` (the pad's next level), `generator`, `iron_bands`, `repair`, `reserve_flywheel`, `aqueduct_drive`. `pad` only for the first four.
- `{"k":"overdrive","via":"action"|"surge"|"button"}`
- `via: "auto"` (or `"auto":1`) marks Autopilot and auto-confirmed picks; those never end a zero-input fallback and never start Overdrive. The host normalizes everything with `int()` and drops unknown kinds, targets, items and pads (`SiegeIntents.normalize`).

**Events** (host to all peers, batched at most 10 a second, in order; ints declared in `int_fields()`): `wave_start` (`ph`, `role`, `n`, `waves`, `b`, `roads`), `wave_end` (`ph`, `n`, `hp`, `max`, `leaks`), `roads` (`roads`, `in_ms`: the horn), `push` (`roads`: the ram push started; additive to the brief's list), `rush` (`on`, `i`), `kill` (`id`, `et`, `pad`, `road`, `x2`), `leak` (`id`, `et`, `road`, `dmg`), `breach` (`n`), `gate_restored` (`hp`), `buy` (`slot`, `item`, `pad`, `ok`, `why`, `lvl`), `route` (`slot`, `to`), `overdrive` (`slot`, `st` 1 start / 0 end / 2 refused, `scored`, `why`). Every horn and toast that follows a host rule is raised from these events on each client and directly on the host for its own rider.

**Snapshot** (10 Hz, full state as integer arrays, decimetres and milliseconds; 1.2 KB mid-wave, 3.8 KB with 150 enemies, cap 8 KB):

```
{"v":1,"tick":n,"ph":phase,"pt_ms":n,"gate":[hp,max,breach_ms],"nb":breaches,"gl":gen_level,"pk":[perks],
 "w":team_watts,"r":[[slot,target,reconnect_ms,od_ms,od_cd_ms,denarii,p_eff_w,raw_w,cadence_rpm,rescue,afk]...],
 "tw":[[pad,type,level,m_x100,cd_ms]...],"e":[[id,type,road,prog_dm,lat_dm,hp]...],
 "z":[[road,prog_dm,ttl_ms]...],"f":[[pad,[target_ids]]...],"q":queued}
```

Additive optional keys, present only when not at their default so the common snapshot is unchanged: `"ro":[road ids]` (the active roads, when they are not all three; `[]` in a break) and `"ru":[1,i,left_ms]` (a rush is on). A client without `ro` has all three roads active and without `ru` no rush. `od_ms` is non-zero only while Overdrive is ACTIVE and `od_cd_ms` only while it is in COOLDOWN, so clients derive the state. `f` carries shots for visuals only; `r` carries each rider's P_eff, raw watts and cadence because other riders' telemetry never reaches a client. The layout is pinned in `contracts/siege_snapshot_schema.gd`.

**Content files** (JSON, validated at load by `SiegeContent`; an invalid set makes the module log an error and not start):
- `shifts.json`: per content `map`, `label`, `total_s` and an explicit `phases` list with `role` (`warmup_wave`, `build_break`, `wave`, `break`), `kind`, `target_pct`, `ramp_to_pct`, `duration_s`, and optionally `mix` and `rushes_at_s`.
- `balance.json`, `towers.json`, `enemies.json`, `waves.json`: the numbers in "Tuning knobs".
- `cosmetics.json`: the XP unlocks. `maps/rotae.json`: the fort, pads, wheels, wall-walk graph and the three roads. `strings.csv`: every `SIEGE_*` string.

## Tuning knobs

All in `content/siege/`, loaded at start, nothing in code:
- `balance.json`: `start_denarii` 40, `reconnect_s` 2.0, `tower_ref_w` 250, `m_cap` 4.0, `bounty_scale` 0.3, `c_budget` 13, `budget_ref_w` 250, `unverified_factor` 0.85, `wkg_min_power_w` 50; `generator` (denarii per kJ, level bonus, level costs); `gate` (`hp` 130, Iron bands, repair, `breach_s` 10, `restore_hp` 30, `breach_loss` 0.3, `warmup_floor_hp` 50); `shop` prices and the countdown; `perks`; `overdrive` (`duration_s` 30, `cooldown_s` 90, `refused_retry_s` 30, `min_left_s` 30, `od_mult` 2, `sprint_hold_s` 10, the 1.2 and 1.4 band factors); `rush`; `autopilot` (route every 1 s, switch gap 8 s, 25% margin, 2 buys per break at 4 s and 9 s into the break, repair below 50%); `score`; `xp`; `tuning` (the T1-T4 targets).
- `towers.json`: cost, range, interval, damage, targets, pierce, zone numbers, upgrade costs and effects, the starting towers.
- `enemies.json`: HP, armor, speed, gate damage, bounty, threat, the ram's crew, the 150 cap, the 3 s retreat.
- `waves.json`: group spacing, `stop_before_end_s`, threat mixes, the ram push, road rotation and horn, the warm-up wave's rules, the rush types.
- `shifts.json`: waves, breaks, targets and rushes (the PlanValidator checks every change against BRIEF 4.6 at every offset).

The G2 pass touched only these files. Never loosen a BRIEF 4.6 limit to fit a design: change the design.

## Running and testing

Run Godot only through `tools/godot.sh` or `tools/godot.ps1` (they set the hardware and network locks); source `tools/env.sh` first.

```bash
# Play with a mock trainer, then pick Castellum Rotae in the picker (add bots in the lobby)
tools/godot.sh --path . -- --mock-trainer=erg
```

- Siege's GUT tests (strict): `tools/run_tests --only=gut --gdir=res://tests/games/siege`
- Node tests (sim checker, e2e report checker): `node --test tests/games/siege/`
- Script check: `tools/godot.sh --headless --path . -s tools/check_scripts.gd`
- Format and lint: `uvx --from gdtoolkit==4.5.0 gdformat src/games/siege tests/games/siege`, then the same with `gdlint`.
- Conformance and everything else: `tools/run_tests` (it runs `tests/sdk/test_conformance.gd`).
- Simulation matrix (S1-S7, S9, S10; S8 is the rules-level GUT sim): `bash tests/games/siege/sim/run_sims.sh`. It writes reports to `build/siege/sims/`, runs `fit_check` on every FIT (laps = lap-true phases + 1: short 8, vo2 14, sweetspot 6, endurance 4, drill 3), then `check_sims.mjs`. Subsets: `bash tests/games/siege/sim/run_sims.sh s2 s5` or `SIEGE_SIMS="s9 s10"`; seeds: `SIEGE_SEEDS="1 2 3"`. Check existing reports only: `node tests/games/siege/sim/check_sims.mjs build/siege/sims [--only=S3,S9] [--seeds=1,2,3]`. A run that exits 75 lost the Godot lock wait: rerun it.
- One sim by hand: `tools/run_game_sim --game=siege --content=short --players=4 --bots=0 --rider=erg:compliance=1.0 --sim-speed=200 --seed=1 --report=build/siege/demo.json`
- End to end: `node tools/e2e/run.mjs --games=siege`
- Stress scene (150 enemies, 8 towers, 4 wheels; windowed, it prints the mean and 1%-low frame time against 16.7 ms and the draw calls and triangles against the budget): `tools/godot.sh --timeout=300 --path . res://tests/games/siege/perf/stress_scene.tscn -- --stress-seconds=60`
- Screenshots: `tools/screenshot --game=siege --content=short --at=60,360,600,690`, and a Breach shot with `--players=4 --rider=zero --at=<s>` (the 0 W riders go AFK, so the gate falls without a pause). Files land in `build/screenshots/siege/`.

## Known gaps

- **T3 is not met.** Leaks per wave-minute are not within 30% across the four shifts (short 0.22, vo2 0.03, sweetspot 0.21, endurance 0.53 at 4 compliant riders). It follows from the shift shapes: `vo2` has five 180 s shops between 2-minute waves, so a team owns every upgrade by wave 3; `endurance` shops once before a 45-minute wave whose last third is 30% Shield walls. No global knob fixes both. A per-shift `c_budget`, or shop access during endurance's wave, would (ADR "T3 not met").
- **Solo endurance is weak.** One rider at 70% FTP powers one tower for a 45-minute wave with a single shop before it. G2 tuned and measured `short` at 1, 2 and 4 riders and the 4-rider matrix for the other shifts, so solo `endurance` has not been balanced.
- **S10 ramped returns.** `check_sims.mjs` fails S10 because the 1 Hz trace after an Overdrive's SIM span carries no `switch_ramp` or `slew` label (ADR "S10 ramped returns fail outside the balance"). Whether the SIM to ERG return is unramped or only unlabelled is for the platform to say; the hardware checklist watches it on a real trainer.
- **Untested on hardware.** Every run used MockTrainer. The ERG targets, the 50 to 117% step, the Overdrive switches, rescue, coasting and panic have not met a KICKR CORE (`HARDWARE_TEST.md`). The 60 fps goal at 1080p on integrated graphics was never measured: headless runs have no renderer, so the stress scene numbers have to come from a real Windows PC.
- **Synthesized audio is unheard.** The sounds are generated and tested for their triggers, never listened to on speakers. A road rotation shows its toast but plays no horn sound (the horn plays only at a wave start).
- `content/siege/strings.csv` calls the drill "one short wave (5 min)"; it is a 2-minute run plus the cool-down.

## Not built (future work)

All of P0 (brief 2.9) is built. From P1 these are not:
- Onager (70; range 10-35 m; 3.5 s; a 1.5 s lob; 45 splash damage in 4 m; special: 6 m).
- The gate cauldron on a ninth pad over the gate (60; every 3 s, 60 damage to every enemy in the 12 m gate plaza; special: rams take double).
- The siege-tower boss (2500 HP, armor 6, 0.5 m/s, bounty 60) replacing the final ram push in shifts with waves of 300 s or more, releasing 4 Raiders every 5 s from 10 m out.
- Custom shifts set by the host as options (1-10 waves of 1-20 min at 60-105%, waves of 4 min or less up to 115%, breaks of 2-10 min at 50-60%).
- `.zwo` import through the platform's `workout_import` parser (blocks mapped to waves and breaks, clamped to the custom-shift limits).
- Equipping the unlocked cosmetics (they unlock and show on the results screen, but nothing equips them yet).

P2 notes (from the brief):
- A second map. `SiegeMap` and `maps/<id>.json` already separate the geometry from the rules; a map needs wheels, pads, a wall-walk graph and roads, and a shift names it with `map`.
- An endless mode: waves with no end, where `B` keeps growing. It needs an open-ended phase and a way to finish.
- A night siege: a dark palette, lit braziers and fog. The view only reads state, so it is mostly a `SiegeView` and palette change.
