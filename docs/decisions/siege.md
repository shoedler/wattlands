# Decisions: siege

Short ADRs for the siege game: date, decision, alternatives, reason. Game sessions keep their decisions here only; docs/DECISIONS.md holds the platform's. "Brief" is docs/games/siege.md; "SDK n" is a section of docs/GAME_SDK.md.

## 2026-10-22 G0 status

- G0.1 done, no-op: the tree was clean; branch `game/siege` was cut from `main` (v0.1.0) and `tools/new_game siege` ran (commit dbfe1e3, gdformat applied). Nothing under `docs/games/` or `docs/concept/` needed committing.
- G0.2 done by citation (next ADR): every question is answered in SDK 23 (Q1-Q25 and "Siege-specific"). No `platform:` change.
- G0.3 skipped by the orchestrator: the full suite must stay at or above `tests/green_count_floor.txt` (2720).
- G0.4 done: `game.json` per brief 2.2, `src/games/siege/contracts/`, the content seeds and `maps/rotae.json`, `strings.csv`, `tests/games/siege/fixtures/`, the stub view, plus a G0 module so the game plays end to end (conformance green, `run_game_sim` drill SOLO ends `complete`, fit_check 3 laps).
- G0.5: commits on `game/siege`; the `siege-g0` tag is left to the orchestrator.

## 2026-10-22 G0.2 answers (by citation, no platform change)

- Mock rider profiles: SDK 20 and 23 Q1 (`erg`, `zero`, `const`, `ramp`, `intervals`, `noise`, `band`, `cadence_drop`, `surge` with `sim_pct`).
- `run_game_sim` slots: SDK 19.1 "Slots and roles" and 23 Q2. `--players` humans first, `--bots` after; FTP 200 unless `--ftp`; humans verified unless `--unverified`; bots verified, ride `erg:compliance=1.0+band`, always Autopilot; humans Autopilot per `--autopilot` (default all). One human = SOLO, two or more = HOST with loopback clients.
- Report: SDK 19.1 report table and 23 Q3. It already holds snapshot sizes and SHA-256s, the 1 Hz trace (applied target and %FTP, mode, `clamped_by`, rescue, AFK), every directive requested and applied, and `fit_paths`; nothing the section 4 checks need is missing.
- FIT path: SDK 19.1 "FIT files": `<report dir>/fit/<report stem>_slot<n>.fit`, one per human slot.
- fit_check: SDK 19.5 and 23 Q4: `node tools/fit_check/check.mjs <dir> --expect-laps=<n>`. The cool-down laps itself (SDK 13, 23 Q5), so n = lap-true phases + 1: short 8, vo2 14, sweetspot 6, endurance 4, drill 3 (checked on the G0 drill run: 3 laps).
- Intents: SDK 11 and 23 Q6: `local_intents()` and `ctx.intents.send()` are batched into `Telemetry.intents` at 5 Hz and reach `frame.players[peer].intents` once each, in order, never int-converted; the platform has no rate limit (Siege enforces 5/s). PedalScanList reports auto-confirms (`item_picked(index, id, via)` with `via == "auto"`, SDK 10.3, 23 Q19).
- Local peer id: `ctx.local_peer` (SDK 5, 23 Q7).
- Drop and rejoin: SDK 14 and 23 Q8: `on_afk(peer, true)` at once, `connected` false and 0 W (never pedaling); a rejoin gets `session_start`, its plan and phase, the latest snapshot and its bands, then `on_afk(peer, false)` once it pedals; after the token expires the slot stays AFK.
- Also confirmed: `int` options with `step` (SDK 3, Q20; `wave_offset` is spelled as in brief 2.2), `PlayerSlot.ftp_verified` (SDK 6, Q18), `Wl.slot_look` colors and patterns (SDK 6), `int_fields()` with `f[][]` and `f[][][]` (SDK 12), `teammate_status` (SDK 10.1), the kit gear widget shows itself in SIM (SDK 10.1), Environment fog in world3d on Compatibility (world3d README), the `.zwo` parser `ZwoImport` (SDK 18).

## 2026-10-22 slot.ftp is Overdrive's CP

- Decision: "raw power is at least CP" (brief 2.4) uses `PlayerSlot.ftp`.
- Alternatives: a CP from W' telemetry; a new PlayerSlot field (a platform change).
- Reason: games can't see the rider's CP; FTP is the closest published value, the same on every peer, and needs no platform change.

## 2026-10-22 Siege emits phase_changed

- Decision: the module emits `phase_changed(index)` in the step where `frame.phase` (slot 0's; every slot shares fixed, equal phases) first shows a new index, the cool-down included.
- Reason: the GameHost never emits it (SDK 4, 13, 23 Q14). Siege has no open-ended phases, so slots never drift apart.

## 2026-10-22 Synthesized audio

- Decision: every Siege sound is synthesized at runtime with `Sfx.synth` (and the built-in effects); no CC0 downloads.
- Reason: the orchestrator's instruction; no downloads, no licences to track, works headless.

## 2026-10-22 Autopilot runs inside the host rules

- Decision: `SiegeRules.step` runs `SiegeAutopilot.route_choice` (once a second, slot order) and `shop_picks` (breaks, at most 2 per break) for every rider whose `route_fallback` / `shop_fallback` is set: bots, Autopilot-on humans and humans who have not routed or bought by hand yet. `autopilot_intents()` returns `[]`. A deliberate (non-auto) `route` clears `route_fallback`; a `buy` without `auto` clears `shop_fallback`; Overdrive intents and auto-confirms clear neither; auto-confirmed buys from a rider still on the shop fallback are ignored (no double purchase).
- Alternatives: Autopilot through `autopilot_intents()` plus a second path in the rules for Autopilot-off humans.
- Reason: the platform never calls `autopilot_intents()` for Autopilot-off humans (SDK 11), so the fallback must live in the rules anyway; one path keeps the brief's "in slot order" 2-rider limit exact and lets the rules-level sim (B4) play Autopilot without the module.

## 2026-10-22 Overdrive triggers

- Decision: `ability_1` (and the HUD button) start Overdrive whenever the safety gate holds (READY, a human, a WORK phase with at least 30 s left, no rescue, delivering); a `surge` also needs the prompt (the target has an enemy in range, or a rush is on). Intents tagged `auto` never start it; bots never do.
- Reason: surges happen incidentally (cadence-band steps, shop picks); the prompt keeps them from wasting Overdrive, while a deliberate button press is honoured. Both obey every brief 2.3 safety condition.

## 2026-10-22 Overdrive refusal handling

- Decision: the rules start Overdrive as PENDING and queue the peer (`state.od_requests`); the module sends `{mode: SIM, duration_s: 30, reason: overdrive, source: siege}` in the same tick and reports the `DirectiveResult` to `SiegeOverdrive.on_request_result` (accepted: ACTIVE for 30 s; refused: cancelled). Every applied record reaches the module through `ctx.events.directive_applied(peer, record)`: for a local rider (the host's own, bots) the router emits it inside `request()`, before the id is returned; for a remote rider the GameHost emits it when the rider's `Telemetry.acks` arrive (after `DirectiveRouter.on_ack`, at least one telemetry later). The module queues records and drains them after each request and at the start of every `sim_step` into `SiegeOverdrive.on_applied`; a refused record with the running Overdrive's id cancels it.
- A refusal (host or governor) sets a 30 s retry cooldown (`overdrive.refused_retry_s`), not the 90 s one, takes the Overdrive back out of `od_count`, sends an `overdrive` event with `st` 2 and the reason, clears the sprint band, and toasts only on that rider's own peer.
- Alternatives: no cooldown on refusal (a surge would retry into the same refusal every tick); the full 90 s (punishes the rider for a safety rule).
- Reason: 30 s is the governor's ERG/SIM switch spacing, so the retry can't fail on spacing again; a rider who didn't get the sprint doesn't lose 90 s.

## 2026-10-22 Overdrive across a phase change, rescue or AFK

- Decision: the rules end a running Overdrive when the phase index changes, when rescue starts or when the rider goes AFK: an `overdrive` event `st` 0 with `why`, and the 90 s cooldown from that moment. Siege sends no directive: the SIM block expires on its own, and every channel resets at a phase change (SDK 8.1).
- Reason: Overdrive needs at least 30 s left, so a phase change only coincides with its natural end (or `finished`); rescue can't arm in SIM, so it mostly arrives as a remote rider's late flag; Siege sends exactly one directive pattern (brief 2.3).

## 2026-10-22 The sprint band comes from the overdrive event

- Decision: on an `overdrive` start event for its own slot, each peer calls `ctx.hud.power_band(ctx.local_peer, 1.2 x FTP, 1.4 x FTP)` (the host directly where it sends the event, clients in `apply_event`), and `(0, 0)` on the end or a refusal.
- Reason: brief 2.4 says the rider's own peer publishes it; the event reaches every peer in order, and MockTrainer riders ride the band's centre in SIM.

## 2026-10-22 Four G1 builders (orchestrator's change to brief section 5)

- Decision: B1 "rules" owns `src/games/siege/rules/` (except `siege_plan_builder.gd` and `siege_overdrive.gd`), `src/games/siege/combat/`, `content/siege/{shifts,balance,towers,enemies,waves}.json`, `tests/games/siege/{rules,combat}/`. B2 "module" owns `src/games/siege/siege_game.gd`, `src/games/siege/{autopilot,net}/`, `content/siege/cosmetics.json`, `tests/games/siege/module/`. B3 "view" owns `src/games/siege/view/` (with `world/` and `units/`), `src/games/siege/{hud,audio}/`, `assets/siege/`, `tests/games/siege/{view,hud}/`. B4 "qa" owns `tests/games/siege/{sim,perf,static}/` and `.github/workflows/game-siege.yml`. The G0 architect's files (`contracts/`, the two rules files above, `content/siege/maps/`, `content/siege/strings.csv`, `tests/games/siege/{contracts,fixtures,integration}/`, `siege_fakes.gd`, `test_siege_package.gd`) change only through the lead.
- Reason: the brief's seven builders split the module, view and HUD finer than the contracts need; four disjoint owners keep every file single-writer.

## 2026-10-22 State as typed records

- Decision: `SiegeState` and its parts are typed `RefCounted` records (`SiegeRecord` base with `to_dict` / `load_dict`), not Dictionaries.
- Reason: typed member access keeps a rules step with 150 enemies under 1 ms, the compiler checks every builder against the contract, and fixtures still serialize to JSON.

## 2026-10-22 Castellum Rotae geometry

- Decision: ground plane x east, z south (toward the camera); fort 64 x 52 m centred on the generator; gate (0, 26) in the south wall; plaza (0, 34), radius 12 m; wheels NW (-12, -10), NE (12, -10), SW (-12, 10), SE (12, 10). Pads sit on the wall walk, numbered clockwise on screen: 1 east wall, 2 SE corner, 3 gate east (8, 26), 4 gate west (-8, 26), 5 SW corner, 6 west wall, 7 NW corner, 8 NE corner; `ring` is that order. The West (116.5 m) and East (118.1 m) roads come round the side walls from off-screen spawns beside the fort's flanks, the Valley road (105.0 m) straight up the hill; all end at the gate. Each road passes within 18 m of at least 2 pads and 40 m of at least 4 (tested). Chains follow the `wall_walk` graph (wheel, two stairs, the wall ring).
- Reason: side roads make the side pads worth building; numbering pads by screen angle makes "right = clockwise" read naturally.

## 2026-10-22 Shifts as explicit phase lists

- Decision: `shifts.json` lists every phase with its `role`; `SiegePlanBuilder` writes `PlanPhase.meta` `{role, number, waves, last_wave, mix, rushes_at_s, shift}` and the labels `SIEGE_PHASE_WARMUP_WAVE`, `SIEGE_PHASE_BUILD_BREAK`, `SIEGE_PHASE_WAVE_<n>`, `SIEGE_PHASE_BREAK_<n>` (n 1..10; break n follows wave n). Endurance rushes are wave-elapsed times 480, 960, 1440, 1920 and 2400 s (the brief's "every 480 s"). The wave offset applies to WORK waves only and is clamped to at least 50% as well as at most 105 / 117%.
- Reason: the drill's WARMUP-kind wave and P1 custom shifts need roles that don't follow from `kind`; per-number keys give readable FIT lap names.

## 2026-10-22 Wire formats

- Snapshot exactly per brief 2.6 (`SiegeSnapshotSchema`): od_ms is non-zero only while ACTIVE and od_cd_ms only while COOLDOWN (clients derive the state), a zone's ttl_ms is its flight delay plus its life, shots are kept 0.1 s so each 10 Hz snapshot carries every shot once, and q is the queue length (`SiegeState.queued()`). The mid-wave fixture's snapshot is 1.2 KB; 150 enemies give 3.8 KB.
- Events: the brief's eleven types plus an additive `push` (the ram push started), with the fields in `SiegeEvents`; every number is declared in `int_fields()`.
- Intents: `SiegeIntents.normalize` gives `{k, to, item, pad, auto, via}`; `auto` is set by `"auto": 1` or `via: "auto"`. `SiegeIntentLimiter` allows 5 intents per 20 game ticks per peer, after junk is dropped.

## 2026-10-22 Controls in breaks

- Decision: `local_intents` sends no routing or Overdrive intents while the shop is open; directions and surges belong to the shop's PedalScanList then.
- Reason: the same actions move the shop focus and pick items; Overdrive is closed in breaks anyway.

## 2026-10-23 G2 tuning

- Decision (one tuning iteration, confirmed by the full `run_sims.sh` matrix): `balance.json` `bounty_scale` 1.0 -> 0.3 (next ADR), `c_budget` 10 -> 13 (+30%), `gate.hp` 100 -> 130 (+30%; with both Iron bands the max is now 180, not 150); `enemies.json` ram `speed_mps` 1.0 -> 0.75 (-25%); `towers.json` Ballista cost 50 -> 65 (+30%) and interval 2.0 -> 2.2 s (+10%), Scorpion cost 40 -> 52 (+30%) and damage 10 -> 7 (-30%), Caltrop thrower cost 35 -> 45 (+30%). Everything else stays at the brief's number. Derived brief statements that move with it: an unopposed ram now walks its 40 m in 53 s and batters the last ~7 s of the wave (~20 HP), not "about 20 s (60 HP)"; the shop's build prices are 65 / 52 / 45.
- Measured, baseline (4ba691a) -> tuned, `run_game_sim` at sim-speed 200: S1/T1 `short` 4 riders, seeds 1-3: 87.7 / 97.2 / 94.5 (mean 93.2, T1 fail) -> 87.4 / 81.1 / 85.1 (mean 84.6). S2 1 human: 30.0 / 30.3 / 33.9 with 3 / 2 / 2 Breaches -> 73.0 / 69.3 / 69.8, no Breach (mean 70.7). S2 2 humans: 33.9 / 36.5 / 37.8 with 2 Breaches each -> 65.4 / 63.6 / 71.8, no Breach (mean 66.9). S2 1 human + 3 bots: = S1. S4 means 93.2 > 85.4 > 59.5 -> 84.6 > 77.1 > 66.8. T4 103/120 (0.86) -> 95/120 (0.79). Drill 1 rider 73.7 B -> 90.4 S; the rules-level drill with 3 riders 45.0 D with a Breach at 112 s -> 79.7, no Breach. Rules-level T2 1.47 -> 0.45.
- How it was found: about 40 content variants on SiegeHeadlessSim first (it reproduces `run_game_sim` scores to 0.1 for compliant riders), each over T2, `short` with 4 / 2 / 1 riders and mostly seeds 1-8. Findings: a team's defence per rider grows with team size (two riders both take the Ballista with the most enemy HP in range and leave the Scorpion idle; bigger teams power more towers and upgrade the shared ones faster), so 4 riders scored about 20 points above 2 riders in every variant, and the T1 window (25 wide) has to hold both. The ram push was what breached 1-2 rider teams (every ram reached the gate, and 2 rams batter 120 HP); the slower ram cuts that most for small teams, the 130 HP gate absorbs the rest. `c_budget`, the Ballista interval, the Scorpion damage and the build prices then bring 4 riders back under 89 (they hit the bigger team's spread of towers more). Seeds 1-8 at the rules level: 4 riders 87.7, 2 riders 67.5, 1 rider 70, no Breach in any.
- Alternatives: ram HP 420 (T4 up, but 4 riders reached 93); escort 7 Raiders per slot (no measurable effect on small teams once rams are slower; kept at 10); Ballista pierce 3 (hurt 2 riders more than 4); a 2.4 s Ballista (4 riders 77-82, 2 riders 48-64 with Breaches); higher upgrade, Iron band, repair or generator prices (4 riders moved under 1 point; upgrades at +30% cost 1 rider 3.5); Horsemen or Shield wall stats (+-1 point); per-team-size prices or Autopilot changes (rules, not knobs).
- Reason: the only set found that holds T1 for every S2 configuration and ≤ 1 Breach each, keeps S3 (Breach in the first full wave), S4 and T4, and brings T2 into range; every number stays within 30% of the brief except `bounty_scale`.

## 2026-10-23 bounty_scale 0.3 (beyond 30% of the brief's 1.0)

- Decision: `bounty_scale` 0.3.
- Evidence: the T2 rider pair (`test_siege_rules_sim.gd`: two riders on the starting Ballista and Scorpion, two on the generator, 180 s waves) earned 21.00 vs 14.25 denarii per wave-minute at 1.0 (ratio 1.47). Bounties are roughly one denarius per point of threat, and B spends about 10-13 threat per rider-minute, so the two tower riders split the whole wave's bounties. At 0.7 (the 30% limit) the ratio is about 1.0; per-enemy bounties at -30% on top give 0.72. 0.3 gives 6.43 vs 14.25 = 0.45 with the tuned content (0.35 gave 0.51-0.68 depending on the other knobs). The generator's 1 denarius per kJ is a brief rule and stays.
- Alternatives: lower per-enemy bounties too (still above 0.6 within their 30%); a lower `c_budget` (fewer kills, but T1 needs harder waves, not easier).
- Reason: `bounty_scale` is the brief's knob for exactly this ratio ("start 1.0"); it also takes the earnings part of the score off its cap (team earnings 1.2-1.5 x par before, 0.7-0.85 after), so effort and compliance show in the score (S4).

## 2026-10-23 Autopilot routing churn is the brief's rule

- Decision: no change to `SiegeAutopilot.route_choice`. Checked against brief 2.5: it runs once a second in slot order, skips towers with 2 other riders, routes to the generator only when no tower has an enemy in range, keeps at least 8 s between switches (the smallest gap between one rider's route events is exactly 8 s in every report) and needs 25% more enemy HP than the current tower for a tower-to-tower switch.
- Measured: `short` 4 riders seed 1: 91-109 route events per rider before, 87-114 after (402 in all, 112 of them to the generator); 1 rider: 59 -> 63. Most are tower-to-tower: enemy HP in range changes by more than 25% within 8 s as groups walk through overlapping ranges. Each costs the 2 s reconnect, which the tuning above already includes.
- Alternatives: a longer hold or a larger margin (changes brief 2.5's numbers for Autopilot only; the orchestrator classed it a bug fix only if the rule deviated, and it doesn't).

## 2026-10-23 T3 not met

- Decision: leave T3 (leaks per wave-minute within 30% across the four shifts) failing and record it.
- Measured (S9, 4 compliant Autopilot riders, seeds 1-3, distinct enemies leaked in wave phases per wave-minute): baseline short 0.22, vo2 0.03, sweetspot 0.09, endurance 0.16 (mean 0.13); tuned short 0.22, vo2 0.03, sweetspot 0.21, endurance 0.53 (mean 0.25: short -12%, sweetspot -16%, vo2 -88%, endurance +112%).
- Why: it follows from the shift shapes and the brief's rules, not a number. vo2 has 5 shops of 180 s between 2-minute waves, whose B spends threat for only 60 s ((120 - 60) / 60), so a 4-rider team owns every upgrade by wave 3 and leaks 0-1 enemies in 12 wave-minutes. Endurance shops once, before a 45-minute wave whose last third is 30% Shield walls, so its towers fall behind. Rules-level probes on top of the tuning: ram HP 780 (vo2 0.08, endurance 0.62), escort 13 per slot (vo2 0.00), `stop_before_end_s` 42 (vo2 0.00), rush budget 0.104 (endurance 0.86), all three together (vo2 0.06, endurance 0.87); no global knob moves vo2 up without breaching small teams or endurance.
- Alternatives (not knobs, for the lead): per-shift `c_budget`, or shop access during endurance's wave (e.g. at its rushes).

## 2026-10-23 S10 ramped returns fail outside the balance

- Finding: S10's Overdrive count holds (vo2 20, endurance 57, vo2 offsets 24 Overdrives; baseline 16 / 60 / 14) and every directive is exact, but `check_sims.mjs` fails S10 on every Overdrive's return to ERG: the 1 Hz trace rows after the SIM span carry `clamped_by: []`, never `switch_ramp` or `slew`, both before and after the tuning (e.g. `s10_vo2_offsets` peer 1 at 512 s: SIM at 260 W back to ERG 234 W). The platform's trace does label the warm-up's ramp, so the SIM -> ERG return is either not ramped or not labelled (BRIEF 4.5). Not a content number; left to the lead with the check unchanged.

## 2026-10-23 G4 net: Iron bands and gate damage ride in the snapshot (NET-1)

- Decision: three additive optional snapshot keys, absent at their defaults like `ro` / `ru`: `"ib": n` (Iron bands bought, 1 or 2), `"gd": [dm per road]` (gate damage by road in 0.1 HP, west / valley / east) and `"gt": [mask per road]` (per road, a bit mask over the enemy type codes that damaged the gate there, bit `1 << type`). `SiegeSnapshotSchema.OPTIONAL_KEYS` and `INT_PATHS` list them; `SiegeSnapshot.apply` reads them with `int()` (a missing key means 0), so an older host's snapshot still applies. Cost at the 150-enemy cap: 3793 bytes without the three keys, 3858 with them and `ro` / `ru` set (limit 8192; pinned by `test_a_snapshot_stays_under_8_kb_at_the_enemy_cap_with_every_key`); a full-length short run's largest snapshot went 1694 -> 1721 bytes.
- Why: a client's shop recommendation (`SiegeShopModel.cost_of`, `SiegeAutopilot.shop_picks` through the HUD shop panel) and the gate view's Iron bands read `iron_bands` and `gate_damage_by_road`, which the snapshot lacked, so a client priced a third Iron band at 45 and recommended the wrong road. `test_a_clients_shop_recommendation_equals_the_hosts_after_a_json_round_trip` now feeds six scenarios through a JSON round trip and compares picks, target road, build type, pad suggestion and every `cost_of`.
- Decisions follow from replicated values only: roads are ranked on `SiegeState.gate_damage_dm()` (0.1 HP, what the snapshot carries) in `SiegeAutopilot`, and `ShopPlan` starts from `ceil(gate_hp)` (the snapshot carries the HP rounded up), so host and client cannot disagree on a near tie or on the 50% repair threshold. The host's own results are unaffected (the full-length sims score and buy exactly as before).
- Alternatives: carry the floats (bigger snapshot, no gain at 0.1 HP); send always (changes the common mid-wave snapshot the brief pins); a `gate_damage_by_road_type[road][type]` matrix (what the build rule needs is only "did a heavy / a horseman ever damage the gate on this road", a 3-int mask).
- Not covered, for the HUD owner: `SiegeShopModel.cost_of(ITEM_REPAIR)` and `suggest_pad` read the unrounded floats on the host (`gate_hp >= gate_max`, `gate_damage_by_road` ties); the client sees the rounded ones. Only a gate between 129 and 130 HP or a tie closer than 0.05 HP can differ, and only in the non-recommended entries. The snapshot fixture `tests/games/siege/fixtures/mid_wave_snapshot.json` gained `"ib": 1` (the fixture state has one band); that is the only fixture change.

## 2026-10-23 G4 autopilot: the build type follows the enemy types that damaged the gate (AP-1)

- Decision: `SiegeState.gate_damage_types_by_road` (mask, filled by `SiegeState.note_gate_damage` in the combat where `gate_damage_by_road` grows, wave phases only, only when HP was actually applied) replaces the live enemies on the road in `ShopPlan.build_type_for`. Brief 2.5 exactly: on the road with the most gate damage, a Ballista if Shield walls or rams damaged the gate there, a Caltrop thrower if Horsemen did and those did not, otherwise a Scorpion; no damage yet: Ballista, Scorpion, Caltrop in turn by the type built least. The previous rule read the enemies on the road, which a shop (a break) never has, so it always fell to "a Ballista in a break" and the Caltrop / Scorpion branches were unreachable.
- Effect: none on the sims. Every road with damage has a ram (each wave pushes one up each active road), so the rule picks a Ballista exactly where the old one did; the full-length S9/S10 sims at seed 1 buy the same items and score the same (short 87.44, vo2 97.59, sweetspot 84.80, endurance 70.80, s10_vo2 98.33). The Caltrop / Scorpion branches are covered by unit tests (`test_the_tower_type_follows_the_enemies_that_damaged_the_gate_on_the_road`).
- Alternatives: remember damage per type in HP (a 3x4 float matrix, 12 snapshot ints) - the rule needs only presence; reset the mask each wave (the road is picked on the run's total damage, so the types are too).

## 2026-10-23 G4 safety: Overdrive is not started for a rider who is not pedaling (SAFE-1)

- Decision: `SiegeOverdrive.blocked_reason` returns the new `WHY_COASTING` ("coasting") when `GestureRecognizer.is_not_pedaling(rider.raw_w, rider.cadence_rpm)` (power < 15 W and cadence < 20 rpm, the platform's shared detector), after the AFK check. It applies to every trigger (surge, ability_1, the button) and to the prompt, so a coasting rider sees no prompt either. There is no player-facing string for it: like the other `WHY_*` reasons it is internal (no toast, the rider simply stays READY), which is the point.
- Why: the governor refuses a SIM block (`sim_block_unsafe`) once the rider has coasted 3 s (its coasting flag) and marks a multiplayer rider AFK only after 10 s, so a HOST rider coasting 3-10 s who pressed the button reached the sink, was refused, got the "Overdrive unavailable" toast and sat out the 30 s retry. The rules now do not ask: no request, no toast, no retry. The check is instantaneous on the rider's latest telemetry, a superset of the governor's 3 s rule, so it can only refuse earlier (never allow what the governor would refuse); BRIEF 4.6 thresholds are untouched. A rider who pedals again can press again at once.
- Alternatives: track the governor's own coasting flag (needs a new input from the frame; `Telemetry.coasting` is not in `SiegeRiderInput`); mirror the 3 s timer in the rules (a second copy of the threshold in time, which BRIEF 3.5 wants kept in one place).

## 2026-10-23 G4 content: Overdrive cooldown and duration are bounded (SAFE-2)

- Decision: `SiegeContent.validate_balance` requires `overdrive.cooldown_s >= 30` (the governor's ERG/SIM switch spacing; a shorter cooldown could only produce `switch_spacing` refusals) and pins `overdrive.duration_s` to exactly 30 (brief 2.3 fixes the directive at 30 s; the old "10..30" was the platform's SIM-block range, not Siege's contract). `refused_retry_s >= 30` and `min_left_s >= duration_s` stay. Tests: `test_overdrive_balance_is_bounded_by_the_briefs_and_the_governor`.
- Alternatives: leave duration free within the platform range (lets a content tweak change the brief's Overdrive silently).

## 2026-10-23 G4 sim: S10 judges the return to ERG on the applied target (supersedes "S10 ramped returns fail outside the balance")

- Verified in the governor and controller (read only): on SIM -> ERG `TrainerController._next_erg_write` writes grade 0, then ERG at `max(floor, min(3 s power, governed target))` and slews up at 30 W/s (`_update_slew`); `SafetyGovernor._update_clamped_by` adds `switch_ramp` / `slew` only while the entry target is still below the governed one (`entry_active`) or the mode has not switched. A surger riding 130% FTP in SIM has a 3 s power above the plan (260 W vs 234 W in `s10_vo2_offsets` at 512 s), so the entry is exactly the plan, GAME_SDK 8.2's "a target exactly at a cap is neither clamped nor counted" applies and `clamped_by: []` is the correct platform behaviour. The old check looked for a label that a surger's return never has. The previous ADR's guess ("not ramped or not labelled") is withdrawn: it is ramped when it needs to be, and not labelled when there is nothing to clamp.
- Decision: `check_sims.mjs` `returnProblems` asserts the requirement itself on the 1 Hz rows' `applied_target_w`, per Overdrive: (1) no row of the phase after the SIM span, while it stays in ERG, is above the planned target (plan `target_pct` of the row's phase x 0.85 if the FTP is unverified x FTP, the per-rider wave offset already in the plan) + 1 W; (2) the first ERG row is at most `max(floor, min(mean power_w of the last 3 SIM rows, plan)) + 30 W + 1 W` (the floor is max(30% FTP, 50 W); 30 W is one row of slew, a row being up to a second after the write); (3) a row at the plan +-1 W follows within `(plan - first) / 30 + 2` s of the first ERG row. A return that spikes above the plan, jumps straight to the plan from a lower 3 s power, or never reaches it fails; `clamped_by` is not read. The other S10 sub-checks (directives, 30 s spans, rescue, spacing, counts) are unchanged. `check_sims.test.mjs` has pass cases (surger on the plan with `clamped_by: []`, a slower rider ramped at 30 W/s, the floor) and fail cases (spike on the first row, spike on a later row, +2 W, break-phase plan, unramped jump, slow ramp, stuck, unverified FTP, missing `applied_target_w`).
- Result on the existing reports (`C:/Projects/wattlands-siege/build/siege/it1`, read only, and `base`): S10 PASS (Overdrives s10_vo2 20, s10_endurance 57, s10_vo2_offsets 24; baseline 16 / 60 / 14). A fresh `s10_vo2` run of this branch: no problems.

## 2026-10-23 G4 module: SiegeGame.predict_route for the HUD

- Decision: `SiegeGame.predict_route(to: Variant) -> bool` is public (it was the private `_predict_route(to: int)` that only `local_intents` called). It takes a route intent dictionary (as the HUD route card builds it with `via "button"`), a wire target ("gen", "next", "prev", "hot", a pad) or a normalized `SiegeIds` target, acts only on a CLIENT, and returns whether it set a prediction. `local_intents` calls it too, so button routes are predicted exactly like control routes (same target, same 2 s reconnect, same hold and host override). The HUD route card (not in this change's file list) should call `game.predict_route(intent)` where it sends the intent.

## 2026-10-23 G4: platform test change (tests/app/test_lobby.gd), Siege's option label

- Decision: `test_long_int_player_option_uses_a_stepper` compared the lobby row with the hard-coded text "Wave offset (% FTP)". It now formats `AppScreen.t("SIEGE_OPT_WAVE_OFFSET")`, so it follows `content/siege/strings.csv`. A platform test file, changed in its own `platform:` commit; it affects only that one test and weakens no assertion (same row text, read from the strings file).

## 2026-10-23 G4: dead code removed

- Decision: `SiegePhaseInfo.is_break()` and `SiegeIds.perk_code()` deleted (no caller in src, tests or tools; `is_wave` / `is_cooldown` and `tower_code` / `enemy_code` stay, which are used).

## 2026-10-22 Snapshot roads and rush (additive keys)
- Decision: the snapshot gains optional `ro` (active road ids, only when not all three; `[]` in a break) and `ru` (`[1, rush index, ms left]`, only while a rush is on); a client without them has all roads active and no rush. Both are `int_fields` paths.
- Alternatives: clients learn roads and rushes only from events (a rejoining client would miss them until the next event).
- Reason: the HUD, horns and view need the road rotation and rush on clients without growing the common snapshot.

## 2026-10-22 Push event
- Decision: an additive `push` event (roads that got a ram) at the ram push.
- Alternatives: derive the push from spawned rams in snapshots.
- Reason: the push toast and ram warning need the moment, and T4 counts rams spawned from it.

## 2026-10-23 G4 camera framing (brief numbers in conflict)
- Decision: camera pitch 41, FOV 35, target z 38, distance fitted (`SiegeFraming`, pure 16:9 pinhole) so the fort with its corner towers spans 55.5 % of the width in the upper half. About 47 m of the Valley road shows below the gate; the West and East roads show beyond 60 m.
- Alternatives: pitch about 36, or a fort share under 50 %, to show 60-80 m of the Valley road.
- Reason: brief section 3's pitch about 42, fort share 55-60 % and 60-80 m of road below cannot all hold for the Valley road with this map; the pitch and the fort share carry the miniature look, so they win. The projection test in `tests/games/siege/view/test_siege_view_build.gd` pins the result. The far hill and haze stay out of frame at this pitch.

## 2026-10-23 One teammate strip
- Decision: Siege's own strip (colour and pattern chip, raw W, %FTP, target icon, markers; numbers from the snapshot on clients) replaces the kit `teammates` widget in the HudSpec.
- Alternatives: the kit strip plus a Siege overlay (showed every rider's W and %FTP twice in a 1070 x 350 px block over the gate plaza).
- Reason: G3 finding P3; one row about 93 px tall keeps the roads and the centre clear.

## 2026-10-23 Shop and banner placement
- Decision: the break shop sits below the fort's front wall (Rect2i 660,458 600x490 at 1080p, text >= 32 px); the kit banners go to the top-left stack under the wave info.
- Alternatives: the shop at the centre (covered the generator, drum and wheels).
- Reason: G3 finding P4: the centre and the drum stay readable during breaks and rescue.

## 2026-10-23 Road-change horn
- Decision: the audio plays the horn when a road change is announced (`wave.horn_s` rising), as well as at a wave start.
- Reason: brief 2.4's 5 s horn; the docs pass found only the toast fired.

## 2026-10-23 Shop model rounding (minor, kept)
- Decision: `SiegeShopModel` reads the unrounded gate HP and per-road damage; only a gate between max-1 and max HP, or a damage tie closer than 0.05 HP, can show a different non-recommended entry on a client. The recommendation itself uses the replicated values.
- Reason: cosmetic; not worth a change this round.
