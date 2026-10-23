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
