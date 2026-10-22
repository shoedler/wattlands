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
