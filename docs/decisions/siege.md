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

## 2026-10-29 v2 rules: engine entry before the camp
- Decision: a siege engine whose entry point (where it reaches the moat edge `push_lead_s` before the wave ends at its speed) would lie before the camp enters at the camp later instead, at the time that keeps the same arrival (a 900 s sweetspot ram at 371 s, the endurance tower at 1889 s).
- Alternatives: enter at the camp at the wave start and arrive early; skip the engine.
- Reason: brief 2.4 fixes the arrival, not the start; waves longer than about 530 s (rams) or 810 s (towers) can't place it on the road at the start.

## 2026-10-29 v2 rules: the ram pair and escorts
- Decision: two rams stand 25 m apart centred on the entry point (one arrives 15.6 s earlier, one later); escort spearmen (10 threat per slot) are split over the wave's engines and enter in 4-wide ranks behind each; the siege tower gets the escort too; engines and escorts come on top of B.
- Alternatives: both rams at the entry point; escorts drawn from B.
- Reason: "two (25 m apart)" leaves the anchor open; v0.1.0 also kept the push outside B, and the tower "replaces the rams", escort included.

## 2026-10-29 v2 rules: a docked siege tower
- Decision: a docked tower does no gate damage. Its boarders stop the tar works (no pump; Autopilot scores the tar works 0) and pads 1 and 2 until it is destroyed; it takes x1.5 from the onager; it retreats with everyone at the wave end.
- Alternatives: boarders battering the gate.
- Reason: brief 2.4 lists only those effects; T4 counts the dock as reaching the gate.

## 2026-10-29 v2 rules: groups as formations
- Decision: each group (6..12 s apart) adds its share of the budget left (over the groups left, x0.8..1.2) to an account; formations spawn while the account covers the next one, whose type was drawn with weight fraction / formation threat (the expected threat split equals the mix). Formations of one group stand one behind the other, the rear rank on the staging ground. The warm-up's "then chariots too" is the `raiders_horsemen` row of its third. A formation that no staging ground can bring to the gate in time is dropped and its threat counted in `wave.dropped`.
- Alternatives: random bodies per group (v0.1.0); a formation per group sized to the share.
- Reason: brief 2.4's ranks (12 / 6 / 2) are bigger than a group's share in short waves; the account keeps B's total and the mix exact over the wave.

## 2026-10-29 v2 rules: caps gate routing only
- Decision: the caps (2/1/2/2/1) refuse routing onto a full station; they never push anyone off, so four riders start on the mine (cap 2). Autopilot never switches between equal scores, so riders kept off a full mine don't wander between idle stations.
- Alternatives: only two riders deliver at the mine.
- Reason: brief 2.4 "everyone starts on the mine" with a mine cap of 2.

## 2026-10-29 v2 rules: bounties by fire-time shares; the mine in a Breach
- Decision: a projectile remembers the riders delivering to its station when it left and their P_eff shares; its kill pays them (and their damage credit), even if they switched before impact. Perk-driven shots (no rider) pay nothing. The mine stops in a Breach like every other station.
- Alternatives: pay the riders delivering at impact; keep the mine running.
- Reason: a 4 s stone flight would otherwise pay whoever just coupled in; brief 2.4 says every station stops.

## 2026-10-29 v2 rules: aiming, slew and targets
- Decision: a weapon turns only while powered (m > 0) and tracks the lead point predicted with its last flight time; at fire time it solves the full 3-round lead (SiegeAim). Targets: every 1 s, the live enemy in band with the highest stations.json `prefer` weight (ballista: engines, shields, blocks, then chariots; onager: engines, then the most HP inside its splash; arrows: spearmen and chariots), nearest the gate on ties; a held target is kept unless a better-preferred type is in range; a target its solver can't reach is skipped once. Pads turn at once.
- Alternatives: fire whenever wound at the nearest enemy; free slew.
- Reason: the brief leaves the target choice open; preferences match brief 2.5's matchups, and keeping the onager on its target respects its 4 deg/s turntable.

## 2026-10-29 v2 rules: upgrade 2 reaches the wider band
- Decision: upgrade 2 widens the band by 25% and lifts the stone's top speed to 39 m/s and the arrows' to 50 m/s (`v_max_upgraded`); arrows that 40 degrees can't reach fall back to the low arc at top speed.
- Alternatives: the band only (stones and arrows could not reach its new edge).
- Reason: physics: 34 m/s stones top out near 100-110 m, 45 m/s arrows near 123 m.

## 2026-10-29 v2 rules: trapezoidal position step (foundation fix)
- Decision: `SiegeBallistics.step` and `land` move the position by the mean of the old and new velocity (v' = v + (g - k|v|v) dt; p += (v + v') / 2 dt); the API is unchanged, so the view replays with the same code.
- Alternatives: the brief's semi-implicit Euler (p += v' dt).
- Reason: semi-implicit Euler at 0.05 s lands about one tick early, up to 1.4% short of closed form for the ballista's flat bolts; brief 4 requires 1%. The trapezoidal step is exact for gravity.

## 2026-10-29 v2 rules: impacts
- Decision: stones and arrows fly to a landing decided at fire time (`SiegeBallistics.land` onto the aim point's ground height) and resolve that many ticks later; bolts fly tick by tick and hit a body when the path passes within 0.6 m plus its body radius of its axis and below its height (`body_r_m` / `body_h_m` in enemies.json; infantry radius 0, so "within 0.6 m" is literal). Splash distance is to the body centre. The testudo is drawn per arrow at fire time from a second hash stream (seed xor 0x5bd1e995). Projectiles in flight are dropped when a phase ends. Ground height is the path's z at the aim point.
- Alternatives: per-tick integration of every arrow (12 per volley); impact checks at spawn time.
- Reason: identical outcomes for ballistic flights at a fraction of the cost (brief 4's 1 ms step); bolts need the per-tick check for pierce.

## 2026-10-29 v2 rules: tar works details
- Decision: the pump stops at the curtain's top (no tar wasted); the cauldrons reheat in every phase; the tar station's `wind` and `arm` show the cauldron fill; leak events report the damage the curtain and the gate took together.
- Reason: the brief leaves these open; the view needs one 0..1 number per station.

## 2026-10-29 v2 rules: the Scorpion
- Decision: spread 0.3 deg and +-0.5% speed (as the bolt), aim point 0.9 m up, the second bolt of upgrade 3 at the same target (one shot event, n 2); a Scorpion bolt hits the first body its path passes, like a bolt that stops.
- Reason: brief 2.4 gives no Scorpion spread.

## 2026-10-29 v2 rules: events and snapshot
- Decision: `push` is one event per engine {id, et, prog_dm} when it spawns; `dock` {id}; `kill` carries `src` (station 1..3, 10 + pad); `buy` carries `station` and `pad`. Snapshot v2 as brief 2.6 with `gd` = this wave's gate damage and two optional keys: `ru` (a rush) and `rk` (the arrow organ's next rack, absent at 0).
- Alternatives: one push event per wave listing the engines.
- Reason: engines can enter at different times (camp entries); T4 counts pushes; the view needs the rack and clients the rush.

## 2026-10-29 v2 rules: Autopilot scores
- Decision: `autopilot.weights` (ballista: shields 2, engines 3; onager: blocks 1.5, engines 3; arrows: spearmen 2, chariots 1.5), samples at 0, 5 and 10 s of the look-ahead, the tar works' score = 20 x (gate_hp of infantry within 40 m + the threat of engines within 60 m), the mine 40.
- Reason: brief 2.5 leaves the scales open; the tar works compete with weapon scores in the hundreds.

## 2026-10-29 v2 tuning (sim evidence)
- Decision: c_budget 32 (13 in v0.1.0), bounty_scale 0.18 (0.3), the ram 780 HP and 3.9 HP/s (+30%), the staging margin 21 s (-30%), the ballista's chariot preference 0.5.
- Alternatives: c_budget within +-30% of 13.
- Reason: at c_budget 13 the v2 defense let nothing through: zero leaks in all four shifts, gate full at every wave end, mean scores 93-100 (headless rules sim, 4 compliant riders, seeds 1-3). c_budget 30-40 brought short to 85-90 while sweetspot stayed near 90 and endurance fell to 50-65 (one 45 min wave without a shop); 60 flooded the long shifts (16-46 Breaches). Bounties scale with kills, so bounty_scale came down with the larger budget to keep T2 at 0.45.

## 2026-10-29 v2 tests replace v0.1.0's
- Decision: 263 v0.1.0 test functions in files that tested the three-road map, towers, hit-scan combat and the 3D view were removed with them; the kept files were rewritten. The rules builder's v2 suite has 585 GUT test functions (v0.1.0: 530 in all, view and HUD included) plus 55 Node tests; the view builder adds its own.
- Reason: brief 4's gate on the floor (the floor minus exactly the deliberately removed tests, with an ADR).

## 2026-10-30 v2 view: baked art with depth-tested sprites
- Decision: `src/games/siege/art/bake.mjs` renders the approved mock's scene into `assets/siege/bake/`: the static world (colour and 16-bit depth, no tilt-shift, vignette or haze) and every moving or rider-hue part as frames with per-pixel depth. The view draws them with one canvas item per atlas (`SiegeDepthBatch`); a canvas shader discards sprite pixels behind the baked world's depth. The anchor's depth rides in the draw's modulate colour (16 bits in R and G), the ramp row and sun shade in B.
- Alternatives: one Sprite2D per part with y-sorting; a SubViewport per machine rendered in 3D; per-sprite shader uniforms (one material per sprite).
- Reason: the mock's look comes from per-pixel depth (walls hide the army, the onager's arm passes behind its frame); one material per atlas keeps a whole fort, 150 enemies and 100+ projectiles at 7 draw calls in the Compatibility renderer.

## 2026-10-30 v2 view: one frame for four riders (key ramp)
- Decision: rider-hue pixels bake as a magenta key ramp (R = B = 255, G = 4 + 8 x index; index = tone level x 2 + outlined); the shader maps them to the slot's ramp when a rider drives the part, else to the part's idle material (timber, rope, bronze, dark stone). The ramps are graded in the bake, so a recoloured pixel matches the mock's.
- Alternatives: PaletteSwap's 8-key uniforms; baking every part four times.
- Reason: 16 tone levels with and without the outline; four times the atlas otherwise.

## 2026-10-30 v2 view: shot replay lands like the host
- Decision: the view replays a `shot` with `SiegeBallistics.shot_velocities` and the station's or pad's numbers from `stations.json`, steps every projectile with `SiegeBallistics.step`, and lands it on the path's height under where the unspread launch comes down (the host's floor is the aim point's ground, which the event does not carry; the replay finds it within 2 cm). A Scorpion bolt stops in the first drawn body on its path.
- Alternatives: a `floor_z` field in the shot event (asked of the rules side); landing at z 0.
- Reason: arcs and impacts on every peer match the host's damage to a few centimetres without a protocol change.

## 2026-10-30 v2 HUD layout
- Decision: kit timeline, Siege's rush strip and wave info top left; the gate readout, a tar-curtain card (48 px number) and the gold readout top right; power, cadence and W' bottom left; Siege's own teammate strip bottom centre (the kit's card strip left out); the route card (five stations, caps, chips, the coupling bar, four buttons) and the Overdrive button bottom right, both hidden in breaks, when the shop (5 rows at 32 px, Autopilot's pick first, "Save gold" second) takes their place east of the fort.
- Reason: brief 3's table; the fort, the junction and the road's last loop stay clear.

## 2026-10-30 A fourth staging ground by the arch (lead decision)
- Decision: `export_map.mjs` adds `{ id: 'arch', prog_m: progAtRoadS(95) }` (prog 281.3, about 110 m from the gate) to its staging list; the map is regenerated. The brief's staging rule is otherwise unchanged.
- Alternatives: dropping vo2's slow formations (round 1).
- Reason: in 120 s vo2 waves spearmen (62 s from the arch) and shield bearers (92 s) can now reach the gate in time. Sim evidence (headless rules sim, 4 compliant riders, seeds 1-3): vo2 leaks per wave-minute stay at 0.03-0.06 with or without the arch; the defense kills the short-range formations before the gate.

## 2026-10-30 Long shifts: a per-shift budget factor (lead decision 2)
- Decision: waves.json `budget_factor` (content id -> factor on B, 1 when absent, validated > 0): endurance 0.75, sweetspot 0.85. `SiegeRules.budget` multiplies B by it.
- Alternatives: mid-wave relief (a repair or shop window inside the 45 min wave; a new mechanic outside the brief); a lower global c_budget (then short stays near 90, T1 fails).
- Reason: one long wave saturates the defense and leaks pile up while the short shifts' waves end and reset. Sim evidence at c_budget 50: endurance at factor 0.6 leaked 0.94 per wave-minute, at 0.75 1.45 (short 1.96, within -26%); sweetspot at 1.0 flooded in one seed of three (11.9 per wave-minute, 23 Breaches; mean 4.57), at 0.75 0.13 and at 0.85 0.24 with no Breach. The factor is the smallest lever: one number per shift, no new rule.

## 2026-10-30 S3 under the shared pause (lead decision 3)
- Decision: S3's runs are `s3_<content>_weak` with `--rider=erg:compliance=0.3 --rider=zero --rider=zero --rider=zero` (4 humans, HOST, seed 1): slot 0 pedals at 30% of its ERG target, slots 1-3 go AFK. check_sims S3 checks that rider list as well; its assertions (complete, HOST, 4 players, a Breach inside wave 1) are unchanged.
- Alternatives: four 0 W riders (round 1: the platform's `all_stopped` pause holds the session in the warm-up until the run times out); bots (they ride at full compliance).
- Reason: S3's intent is "a team that barely pedals is breached in the first full wave"; one rider must pedal so the session runs, and slot 0 carries the shared phase. Trial (short, seed 1): complete, the first Breach at 532 s (wave 1 is 420-720 s), all FITs with 8 laps.

## 2026-10-30 run_sims.sh runs the checks after a fit_check failure (lead decision 5)
- Decision: a failed fit_check sets the exit status; check_sims still runs, and the script exits non-zero if either failed.
- Reason: round 1's matrix stopped at fit_check and the scenario results had to be checked by hand.

## 2026-10-30 v2 tuning, round 2 (lead decision 4)
- Decision: c_budget 50, bounty_scale 0.115, plus the budget factors above.
- Alternatives: c_budget about 35 (round 1's c_budget 32 gave short 89.3 on the platform matrix, 86.9 on the rules sim).
- Reason: with the arch, c_budget 36 raised short to 91.6 on the rules sim (more kills, more bounty, still almost no leaks); c_budget 50 with bounty_scale 0.115 gave short 74.8 (gate 25.4 of 40 points) and T2 0.53. Bounties scale with kills, so the bounty came down as the budget went up. Five tuning iterations this round.

## 2026-10-30 Slot factor on B (lead decision 1)
- Decision: waves.json `slot_factor` [0.62, 0.58, 0.8, 1.0] multiplies B by the slot count 1..4 (bots count as slots; validated: 4 factors > 0). Brief 2.4's B line names it. Autopilot's routing stays as in brief 2.5.
- Alternatives: the lead's start [0.45, 0.7, 0.88, 1.0]; Autopilot spreading riders by coverage.
- Reason: one rider mans one station, so a small team covers one or two range bands while B grows with every slot. On the headless rules sim (short, seeds 1-3) the start values gave 1 rider 90.5 and 2 riders 33.0 (Breaches); [0.55, 0.5, 0.75, 1.0] gave 86.8 / 87.7; the chosen values gave 87.1 / 78.7 and 83.5 for 1 human + 3 bots. Total B still grows with every slot (0.62, 1.16, 2.4, 4). Platform matrix: S2 1 human 84.5, 2 humans 75.3, 1 human + 3 bots 80.5, no Breaches.

## 2026-10-30 T3: per-shift budget factors, round 3 (lead decision 2)
- Decision: `budget_factor` short 0.92, vo2 1.1, sweetspot 0.85, endurance 0.7.
- Reason: platform matrix. Round 2 (short 1.0, vo2 1.0, sweetspot 0.85, endurance 0.75): leaks per wave-minute 2.02 / 0.72 / 0.79 / 1.56. Short 0.92, vo2 1.1, endurance 0.6: 0.82 / 1.22 / 0.79 / 1.18, T3 held (mean 1.0, all within 22%). Endurance 0.52 with vo2 1.05: vo2 rose to 1.5 (vo2's leaks are noisy over three seeds). The final set (endurance 0.7 with the rush share below): 0.82 / 1.22 / 0.79 / 0.55; T3 misses by 5-14 points at both ends (vo2 +44%, endurance -35%). T1 stays at 82.1.

## 2026-10-30 Endurance: the rush share (lead decision 3)
- Decision: `rush.budget_frac` 0.056 (brief 8%, -30%); the endurance budget factor 0.7.
- Alternatives: a lower endurance budget factor alone.
- Reason: endurance's Breaches came in its rushes (30 s bursts of 8% of B each). Platform matrix: budget factor 0.6 with an 8% rush gave C, C, D (seed 3: 1 Breach, 32.7); 0.52 with 8% gave C, D, D (two runs with 1 Breach each, 37.8 and 38.1). Headless, factor 0.7 with a 5.6% rush gave B, B, B, B, C over seeds 1-5 with no Breach. Platform: B, B, B (70.1, 75.3, 65.8), no Breach. The rush share is taken from B, so it spreads the same threat more evenly instead of cutting it.

## 2026-10-30 S4 stays on seeds 1-3 (lead decision 4)
- Decision: S4 keeps seeds 1-3.
- Reason: with the slot and shift factors S4 falls strictly on the platform: 100% 82.11, 90% 70.86, 80% 61.76, so the extension to seeds 1-5 was not needed.

## 2026-10-30 Round 3 iterations
- Six tuning iterations: three headless rounds on the slot factor and the shift factors, then three on endurance and vo2 (each checked on the headless sim, the second, third and sixth also on the platform matrix).

## 2026-10-30 Breach gold cut at the start; the restore never lowers the gate (review 3)
- Decision: the 30% cut of unspent gold (rounded down) lands when the Breach starts; at its end the gate becomes max(its HP, restore_hp 30).
- Alternatives: record the gold at the start and cut it at the end; cut at the end as before.
- Reason: a Breach late in a wave ends inside the break, where the old restore set the gate to 30 over repairs and Iron bands already bought, and its cut came after the purchases, so buying first dodged it. Cutting at the start needs no extra state, and brief 2.4's "afterwards" outcome (30 HP, 30% less gold) is unchanged when nothing was bought.

## 2026-10-30 Rush double bounty by the rush clock (review 4)
- Decision: a kill pays the rush double when `state.rush_on()` at the kill (to riders in Overdrive), not by the body's spawn flag.
- Reason: brief 2.4 "Kills during a rush pay double".

## 2026-10-30 Snapshot rider flags and the next rush (reviews 5, 6, 9)
- Decision: the rider row grows two additive columns, `connected` and `shop_fallback` (0/1; 13 columns, an 11-column row still applies with the defaults); the optional key `rn` carries the next rush's index (absent at 0).
- Alternatives: derive the next rush from the phase clock and the shift's rush times on clients.
- Reason: a client shop panel needs the shop fallback ("Picks in 4 s" forever after a manual buy), the view needs a dropped peer's path dark, and a restarted client needs the rush marker; one int per rider and one key stay far under 8 KB (3.9 KB at the 150-enemy cap).

## 2026-10-30 The mine turns in breaks (review 10)
- Decision: in a break the mine's `m` (and `arm`) show the sum of every delivering rider's P_eff / 250 W (capped at 4), since all output goes to the mine then; it stays 0 in a Breach and in the cool-down. Payment is unchanged (SiegeEconomy pays by P_eff).
- Reason: the view showed a still mine while it paid.

## 2026-10-30 Reach event (review 13)
- Decision: a ram that reaches the gate raises `reach` {id, et}; the cue fires for it like every event; check_sims T4 counts reach, dock and an engine's leak as reaching the gate, which is exactly the rules' `engines_stopped`.
- Alternatives: a `leak` with dmg 0 and a reach flag.
- Reason: a ram that reached the gate and died before its first whole HP of battering raised no event, so T4 counted it as stopped. A new event keeps `leak` as the gate-damage event and T3's distinct-id count unchanged.

## 2026-10-30 WKG warm-up budget (review, unconfirmed item)
- Decision: a rider's WKG ratio r starts at its slot's `p_eff_per_w` instead of 1.0, until telemetry of >= 50 W replaces it.
- Reason: a real defect. Brief 2.4: r in WKG is the latest p_eff_w / power_w; GAME_SDK 6: `p_eff_per_w` is that ratio (75 / weight) and the host has every rider's value. The warm-up wave's B is computed on its first tick, before any telemetry of >= 50 W, so every WKG rider counted at r = 1.0.
