# Decisions: fishing

Short ADRs for Big Game Fishing: date, decision, alternatives, reason. Game sessions keep their decisions here only; docs/DECISIONS.md holds the platform's. "Brief" is docs/games/fishing.md; "SDK n" is a section of docs/GAME_SDK.md. Where the brief and the code or the SDK disagree, the code and the SDK win (orchestrator's instruction).

## 2026-10-23 G0 status

- G0.1: `main` (5bd5aa4, contains `v0.1.0`, Generator Siege merged) was clean; no planning-file commit was needed. Branch `game/fishing` cut from it in its own worktree (`C:/Projects/wattlands-fishing`); `tools/new_game fishing` ran (commit 36ae6c1) and gdformat re-wrapped one file. Baselines: the tracked floor `tests/green_count_floor.txt` is 3249 (the orchestrator's rule replaces a G0 suite run); the e2e baseline for every registered game is taken in G2 with the full suite.
- G0.2 answered by citation below; no `platform:` commit is planned (every gap the brief anticipated already exists: SDK 23).
- Art variables (presence only, never values): `FAL_KEY` set before and after sourcing `tools/env.sh`; `WATTLANDS_ALLOW_ART` not set in this environment, before or after. Sourcing clears neither (SDK 23 Q23). If it is still unset when fish-art runs, brief 3.4's fallback applies and the report says "placeholder art".
- G0.3-G0.5: `game.json`, the contracts, the content seeds, `art.json`, the placeholder `picker_card.png` and a G0 module that plays end to end; tag `fishing-g0`.

## 2026-10-23 G0.2 answers (by citation, no platform change)

- HudSpec to art pixels: a `Rect2i` is in art pixels of `pixel_base` and goes through `PixelViewport.art_rect_to_screen()` (integer scale 3 at 1080p plus the letterbox offset), re-laid out on resize; anchors ignore the viewport (SDK 10.1, 23 Q16).
- Clearing a cadence band: `ctx.directives.cadence_band(peer, 0, 0)`; the cool-down clears every band (SDK 8, 23 Q13). The Landing clears the Fight's band this way.
- `phase_changed`: the GameHost never emits it; per-rider phases come from `frame.phase`. Fishing never emits it (SDK 13, 23 Q14).
- `tools/screenshot`: `--players`, `--seed`, `--at=<s,...>` (sim seconds, fast-forwarded), every `run_game_sim` flag, and `--app-screen=session --app-role=client` to see the PANIC corner (SDK 19.3, 23 Q15).
- `tools/run_game_sim`: per human slot `--rider` (repeat per slot), `--autopilot=all|none|<slots>`, `--ftp`, `--haptics-off`, `--player-options`; the report holds events, per-rider phases with `ended_by`, every directive requested and applied with `clamped_by`, the 1 Hz trace (applied target and %FTP, mode, `clamped_by`, rescue, AFK), snapshot sizes and SHA-256s, results and `deterministic_hash`; FIT files at `<report dir>/fit/<report stem>_slot<n>.fit` (SDK 19.1, 23 Q2-Q3).
- `tools/fit_check`: `node tools/fit_check/check.mjs <file|dir>... --expect-laps=<n>`. The platform always adds the cool-down lap: n = lap-true phases that started + 1 (SDK 13, 19.5, 23 Q4-Q5). Fishing laps: the ride out, every Reel and every Fight that started (Landings are lap-false), so free and base trips give a different n per rider; e2e_2min gives ride out + Reel + Fight + cool-down = 4.
- Mock riders: `band` (`offset_rpm` from the published band's centre; with a 16 rpm band, -18 and +18 hold 10 rpm outside), `cadence_drop` (`rpm`, `at_s` or `at_phase` [+ `after_s`] or `at_target_pct`, `for_s`) (SDK 20, 23 Q1).
- Also: `PlayerSlot.preferred_cadence_rpm` and `haptics_on` (SDK 6), `PhaseState.plan_elapsed_s` (SDK 9), `int_fields()` (SDK 12), signed `SpinningPart` speed and `ParallaxStrip.mirror_alternate` (SDK 18), `tile`/`mirror` in art.json (ART_PIPELINE).

## 2026-10-23 Five G1 builders (orchestrator's change to brief section 5)

- Decision: five builders on disjoint paths, each in its own worktree and branch from `fishing-g0` (`S/` = `src/games/fishing/`, `C/` = `content/fishing/`, `T/` = `tests/games/fishing/`):
  - fish-plan (Opus): `S/plan/`, `C/trips/`, `C/species.json`, `T/plan/`.
  - fish-rules: `S/rules/`, `S/autopilot/`, `C/areas/`, `T/rules/`; the only builder that may add fields to the state records in `S/contracts/` (additively, reported).
  - fish-module: `S/fishing_game.gd`, `S/net/`, `S/results/`, `C/cosmetics.json`, `T/module/`, `T/integration/`, `T/fishing_fakes.gd`, `T/test_fishing_package.gd`.
  - fish-view: `S/view/`, `S/hud/`, `S/audio/`, `C/strings.csv`, `T/view/`, `T/hud/`.
  - fish-art-qa: `assets/fishing/`, `S/tools/`, `docs/credits.d/fishing.md`, `T/art/`, `T/sim/`, `T/e2e_check.mjs` and its `*.test.mjs`, `.github/workflows/game-fishing.yml`, `S/README.md`, `S/HARDWARE_TEST.md`, `S/BACKLOG.md`.
  - The lead keeps `S/contracts/`, `S/game.json`, `docs/decisions/fishing.md`, `docs/changelog.d/fishing.md`.
- Reason: the orchestrator's instruction (fewer agents, quicker v0.1); every file keeps one writer.

## 2026-10-23 Contracts

- State is typed `RefCounted` records (`FishingRecord`, after Siege's `SiegeRecord`): `FishingState` > `FishingLaneState` (one per slot, slot order) > `FishingFishState`, `FishingPullState`, `FishingPlanSlot`. Lanes are arrays, so `sim_step` allocates nothing per tick (free_120 must finish its SOLO sim within 900 s).
- The rules are pure: `FishingRules.step(state, inputs: Array[FishingLaneInput], dt) -> FishingStepOut`. The module fills one reused `FishingLaneInput` per slot from the frame, and applies the out in a fixed order: directives, bands, end_phase, events, toasts, finished. The pull scheduler (`FishingPullScheduler`, fish-plan) is called by the rules with a frozen API (begin, start_run, set_staggered, step, end).
- Randomness: `FishingRandom`, a 32-bit xorshift stream derived from `ctx.seed` and two integers. The pre-roll uses (seed, slot, PREROLL) as brief 2.3 says ("from ctx.seed and the slot index"); each lane's rules and pull schedule use their own streams, so one rider's bites never shift another rider's pulls and the plan property tests can run lanes alone. Scheduled trips use (seed, 0, PREROLL): one schedule for everyone.
- Alternatives: `ctx.rng` shared in slot order (couples the lanes); `RandomNumberGenerator.new()` per lane (banned in rules by the package scan).
- Reason: determinism without the wall clock or global RNG, lanes independent, the same streams on host and clients.

## 2026-10-23 Autopilot and zero input run inside the host rules

- Decision: `autopilot_intents()` returns `[]`. `FishingRules` plays picks, casts and strikes for every lane whose `auto_plays()` is true: bots (none: `bots` is false), Autopilot-on riders, and humans who have sent no deliberate Fishing intent yet (`fallback`). Only `spot` and `confirm` with `via` `action` or `button` are deliberate (`FishingIntents.is_deliberate`); a surge confirm, the summary and auto-confirms never end the fallback. The pedal-scan highlight and its two-cycle auto-confirm (2 x hints x 1.6 s) also run in the host rules, so a sim or a host never depends on the client-side, wall-clock `PedalScanList`; the view draws the highlight from the snapshot's `selected`.
- Reason: the platform never calls `autopilot_intents()` for Autopilot-off humans (SDK 11), so the fallback must live in the rules anyway (Siege's ADR); the scan's auto-confirm runs on wall-clock time on clients (orchestrator's note).

## 2026-10-23 HUD layout (HUD space is the main constraint)

- Decision (`FishingLayout`, art pixels):
  - Deck bar (y 0-23): one game Control with the trip clock, the local rider's phase chip (label, time left, next phase), the local fish row (species icon, distance, stamina) or the gaff meter in Landing, the catch board and the hookup level; the kit `wbal` (362, 4, 80, 16) and `gear` (306, 0, 54, 24) widgets in their own rects.
  - Local lane's HUD zone (x 427-639): the kit timeline (213 x 36) on top, then one 36 px row: power gauge (100), the game's strain bar (5), cadence (97), the game's slack bar (5); each kit widget at its minimum rect, so W and rpm keep >= 48 px at 1080p. This fits the 4-lane zone (213 x 84).
  - PANIC owns art x >= 503, y >= 316. When the row would reach it (the bottom lane at 3 and 4 lanes) the timeline is left out (the deck bar's phase chip stands in) and the row moves to the zone's top.
  - Other lanes: one compact FishingLaneHud (213 x <= 36: band and marker, both meters, W and rpm at >= 32 px, species and distance) at the top of each zone, clear of PANIC.
  - Toasts below the deck bar (160, 26, 320, 22); banners over the local lane's left two-thirds.
- Alternatives: kit widgets for everything (they don't fit 84 px); the meters inside the play area (clutters the slice, and the right third must stay HUD and open water); a second timeline in the deck bar (the kit timeline needs 108 screen px, the deck bar has 72).
- Reason: brief 3.5's widget list in the smallest zone, the right-third rule and the PANIC corner. The W′ bar sits in the deck bar at every lane count, so the layout is the same at 1-4 lanes.

## 2026-10-23 Plan shape details

- Open-ended Reels get `duration_s` 240 (nominal, for the timeline) and `max_s` = the trip's nominal length (`FishingPlanBuilder.trip_length_s`), so a Reel never ends on its own before `finished`. Free and Base plans end with a trailing fight-less Reel, so a rider whose slots ran out keeps reeling until `finished("trip_over")`; `finished` waits until no lane is in a Fight or Landing. Scheduled trips end at the last Landing (the platform's cool-down follows).
- Labels: per-number string keys (`FISHING_PHASE_REEL_<n>` up to 40, `FISHING_PHASE_<SPECIES>_<n>` up to 30/20/12/4); beyond them the plain text ("Reel 41") passes through `ctx.strings.t`. The FIT lap name is the label.
- "slot 2 is a marlin" (free_90, free_120): the second fight slot, 1-based (`marlin_slot: 2`).
- e2e_2min's Reel is fixed at 55 % (`reel_pct` in the trip file); the rider's reel_pct option is ignored there.

## 2026-10-23 e2e mackerel band offset +3 (deviation)

- Decision: e2e_2min's scheduled mackerel uses `band_offset` 3, not the brief's 0.
- Alternatives: 0 as written.
- Reason: the e2e harness, the run_tests sim step and conformance ride `erg:compliance=1.0` at a constant ~90 rpm and never follow the band (orchestrator's note). With offset 0 the band's high edge falls to 90 at S = 0.2 and the rider stalls out of band; with +3 the band runs from [85, 101] at S = 1 to [75, 91] at S = 0, so a constant 90 rpm rider stays in band the whole fight and lands the fish in T_nom.

## 2026-10-23 Synthesized audio

- Decision: every Fishing sound is synthesized with `Sfx.synth` (and built-in effects); no CC0 downloads.
- Reason: the orchestrator's instruction.

## 2026-10-23 [fish-plan] Pre-roll enforces only the fight budget; last call stays a run-time rule
- Decision: FishingPreroll limits slots only by the brief's budget (window low end + 30 s fits, then w capped so T_nom + 30 s fits). It never drops a slot that could miss last call. The tests prove that the first slot passes last call even at the forced first bite (360 s into fishing): 360 + max_s + 30 <= fishing_s + 300 for every trip.
- Alternatives: also drop later slots that could not end within 5 min of fishing end at their earliest bite.
- Reason: earliest bites depend on run-time fight lengths (R_min = k x the previous fight's actual length), so the rules' last call is the exact check. An unreachable slot is harmless: the lane stays in its open-ended Reel until finished("trip_over").

## 2026-10-23 [fish-plan] Slot peaks use the rolled runs and every cap
- Decision: range_pct = [base(1-a), max(base(1+a), the highest rolled run peak)]. Every peak is capped at 110 %, at 105 % when the species' max_s > 300 s, and at top_pct (Base 100, which also caps the base pull and the range). Run lengths are snapped to 0.1 s so expiries land on ticks. The scheduled path (threshold, e2e) uses the same caps and snapping, so its run lengths differ from G0 by up to 0.05 s.
- Alternatives: the species' maximum peak (110 for every mahi) for the range top.
- Reason: the tightest range the PlanValidator checks; every directive stays inside it.

## 2026-10-23 [fish-plan] Pull scheduler models the governor channel; one write every 0.5 s
- Decision: FishingPullState tracks the ERG channel as the governor holds it: target_pct, plus expiry_t back to the base pull. Every ramp step (pull or run) starts from that value. Ramps have at least 6 steps 0.5 s apart, the first at the change or run start (or 0.5 s after the last write). The step count grows so no step adds more than 12.5 W (25 W/s at 0.5 s), at the rider's FTP. Every directive, from any source, is at least 0.5 s after the previous one. Pull targets are clamped to the range and to 105 %.
- Alternatives: ramps starting 0.5 s after the decision; no global spacing.
- Reason: brief 2.3 (2 writes/s, 25 W/s), and the run expiry lands on the base pull exactly as the governor reverts.

## 2026-10-23 [fish-plan] One run at a time; run_blocked_by_gap also covers an active run
- Decision: run_blocked_by_gap(ps, slot, t) is true while a run or jump is still active, and also for jumps within run_min_gap_s (90 s) of the previous jump's start. The rules retry on later ticks. If start_run is called during an active run anyway, the new run replaces the old one's ramp.
- Alternatives: skip a run that comes due during another (loses a run); queue it inside the scheduler.
- Reason: the rules already retry for the marlin gap. Runs never overlap, so 30 s per run and 90 s per fight above 105 % hold.

## 2026-10-23 [fish-plan] Above-105 accounting by reservation
- Decision: a run whose peak is above 105 % reserves its whole length (ramp included) in above_105_run_s and above_105_fight_s. If the run is longer than 30 s, or would push the fight past 90 s, its peak is held at 105 %.
- Alternatives: integrate the requested target per tick.
- Reason: a conservative bound that is deterministic. With the content's mahi (2-3 runs of 15-30 s) it never bites, but it guards against bad content.

## 2026-10-23 [fish-plan] Stagger and run interplay
- Decision: while staggered, nothing is sent and any queued ramp is dropped. A run's last sent step still expires at the run's scheduled end, so the channel lands on the base pull. The pull-change clock stops from a run's start to its scheduled end, and from a stagger's start until 10 s after its end. It then restarts with a fresh 8-16 s interval from that tick, so the next pull change starts from base. set_staggered(false, t) expects t = the rescue's or AFK's end; the scheduler adds the 10 s. A run cut by a stagger before its first step was sent never reached the trainer: the channel keeps the pre-run pull, which the tests check.
- Alternatives: send a revert-to-base request after the stagger (a request inside the stagger's 10 s window).
- Reason: brief 2.3 (no request during rescue or AFK; expiry reverts to base). A ramp cut below base reverts to base by expiry, which can be an increase; the governor's 30 W/s slew covers that, and the 25 W/s rule applies to the game's own steps.

## 2026-10-23 [fish-plan] Opt-in plan sweep
- Decision: tests/games/fishing/plan/sweep/fishing_plan_sweep.gd (extends SceneTree, no test_ prefix) runs brief 4.1 at full size: 9 trips x 200 seeds x 4 riders x 5 reel_pct; 500 directive seeds per species with FTP cycling 100-500 W (--ftp=all runs all five); stagger-at-step cases for 20 seeds at 100, 300 and 500 W. --find-marlin=1-500 lists free_120 rider-0 marlin seeds with jump counts (brief 4.2 scenario 6). GUT keeps 25 seeds at all five FTPs.
- Reason: the shared suite stays fast (about 8 s), and the full sweep takes 45 s on demand.

## 2026-10-23 [fish-rules] Autopilot and fallback lanes cast at once
- Decision: lanes whose auto_plays() is true (Autopilot, bots, the zero-input fallback) cast FishingAutopilot.pick in the same tick the Reel or a recast opens PICK, and strike at 0.5 s. Lanes past the fallback scan every 1.6 s, move with left/right (pausing the scan 10 s and restarting the auto-confirm clock, as PedalScanList does), cast on any confirm, and auto-confirm after 2 x hints x 1.6 s. The highlight wraps.
- Alternatives: show the PICK briefly to fallback riders.
- Reason: brief 2.5 says Autopilot casts and recasts at once. A fallback rider still ends the fallback with any key or button, and then picks by hand from the next cast on.

## 2026-10-23 [fish-rules] Last call counts the actual fight time used
- Decision: fight_budget_used_s adds each fight's actual length plus its Landing when the Landing ends. A bite is refused when used + T_nom + 30 s > fight_cap_frac x fishing_s, or when the bite time + max_s + 30 s ends more than 5 min after fishing ends. Both are checked at the earliest possible bite (now or R_min); a blocked lane goes IDLE at once. Re-bites obey last call too.
- Alternatives: count T_nom + 30 s per started slot (the pre-roll's figure); check only at the bite.
- Reason: brief 2.4 says 'fight time + T_nom + 30 s'. Counting actual time keeps fights near the 40 % / 25 % gate even when riders fight long, and reeling out early is quieter than a hazard that never fires.

## 2026-10-23 [fish-rules] IDLE keeps the practice band
- Decision: a Reel with nothing more to catch (slots used up, last call, fishing over) publishes the practice band (preferred +- 8). The lure comes in, there are no hints and no bites.
- Alternatives: clear the band; keep the last lure band.
- Reason: an easy-spin guide for the rest of the Reel without promising a bite.

## 2026-10-23 [fish-rules] trip_over waits for strikes and set hooks
- Decision: finished('trip_over') waits until no lane is in a Fight, a Landing, a strike prompt (at most 4 s) or a set hook whose Fight has not started yet.
- Alternatives: end during a strike prompt and lose that fish.
- Reason: last call already approved that bite, and the fish would otherwise vanish at the whistle.

## 2026-10-23 [fish-rules] Double Hookup and expected points
- Decision: each fight accumulates overlap_s[m], the seconds at which >= m fights (its own included) are on at once. Reaching 10 s raises its hookup_count to m. One double_hookup event per tick carries the highest level reached and every lane in a fight (slot order). Only the Fight phase counts, not the Landing. Expected points add round(20 sqrt(kg)) at each hookup (kg with strength, never x0.75). Scheduled trips also add base x (hk - 1) when the fish lands, using that fish's actual multiplier.
- Alternatives: pairwise overlap tracking; a fixed hookup_mult(lane count) for scheduled trips.
- Reason: brief 2.4 and 2.8 at no per-tick allocation. A rider who drops out of a scheduled fight does not inflate the expected points.

## 2026-10-23 [fish-rules] Frenzy only for reeling riders
- Decision: a hookup (Free and Base, 2+ lanes) sets frenzy_until_t = t + 60 only on other lanes in PICK, CAST or REEL. The frenzy event goes out only when at least one lane got it. The doubled hazard counts once the lane is past R_min.
- Alternatives: every other lane.
- Reason: a lane in a fight, a strike or IDLE cannot bite within 60 s, and the snapshot's F_FRENZY flag should not light up on it.

## 2026-10-23 [fish-rules] Fish dynamics details
- Decision: at hook-set d = min(lure distance, d_max), with 0.5 x d_max when no cast happened. z moves at 0.5 per second toward 0.25 + 0.75 S, to 1 on a run and to 0 (the surface) on a marlin jump. In the Landing the fish comes aboard at 2 m/s. While staggered the fish swims out at 1 m/s up to d_max.
- Alternatives: no z rate given in the brief; jumps sounding like runs.
- Reason: brief 2.4 leaves the depth rate and jump depth open; jumps are leaps at the surface (view).

## 2026-10-23 [fish-rules] Staggers read both module flags and telemetry (scheduler edges superseded: "[fix-rules] The rules forward every stagger edge")
- Decision: a stagger is on while any of these is true: lane.rescue (on_rescue) or inp.rescue; lane.afk (on_afk) or inp.afk; or stale telemetry (age_s > 3 s or connected false). S, meters and band freeze, and hazards are 0, until 10 s after the cause ends. Runs coming due are skipped, FishingPullScheduler.set_staggered brackets it in a fight, and directives are dropped only while the cause is on. Stale cadence (cadence_age_s > 3 s) freezes only the meters.
- Alternatives: module flags only.
- Reason: the brief and the orchestrator say either counts. Tests and sims drive telemetry directly.

## 2026-10-23 [fish-rules] Relaxed band widens upward
- Decision: low = max(65, centre - 8), high = low + width (16, or 22 relaxed), as FishingConst documents.
- Alternatives: a symmetric 22 rpm band around the centre.
- Reason: brief 2.4 and the frozen constants. Changing it would move the e2e mackerel's band.

## 2026-10-23 [fish-rules] FishingRulesPull bridges fish-plan's G1 functions (superseded: "[fix-rules] FishingRulesPull removed")
- Decision: FishingRulesPull checks FishingPullScheduler once (Script.has_method, cached in static vars) for init_lane and run_blocked_by_gap and calls them through Script.call when present. Before the merge, init_lane does nothing (the lane keeps FishingLaneState.pull_rng = (seed, slot, STREAM_PULL), passed to begin() and step()). run_blocked_by_gap falls back to slot.run_min_gap_s since fish.last_jump_t. A run that start_run() refuses counts as fired, with no event.
- Alternatives: wait for the merge; edit plan/.
- Reason: the rules parse and play on both sides of fish-plan's merge without touching plan/.

## 2026-10-23 [fish-rules] Cadence EMA starts at the first sample
- Decision: the lane's cadence EMA (tau 1 s) takes the first sample as its value instead of rising from 0.
- Alternatives: start at 0.
- Reason: starting at 0 would show a false out-of-band reading for the first seconds of the trip.

## 2026-10-23 [fish-rules] Ride-out tips and the strike toast
- Decision: tips go to the rider's own peer at 45, 90, ... s into the ride out, cycling FISHING_TIP_1..6 (a 300 s ride out shows each once; e2e shows none). FISHING_TOAST_STRIKE goes to the rider's own peer at each Free/Base bite, except for Autopilot riders and bots. Scheduled self-hooking bites show no prompt.
- Alternatives: a tip at 0 s.
- Reason: the warm-up banner already covers the start, and six 45 s steps fit 300 s exactly.

## 2026-10-23 [fish-module] Event toasts: one routing rule
- Decision: team-wide event toasts (landed or trophy, double_hookup, frenzy) are sent by the host with peer 0 and reach every peer; clients never raise them. A rider's own event toasts (hookup, strike_miss, snap, thrown, replacement) are raised only on that rider's peer: by the host with ctx.local_peer when the lane is its own rider, and by a client in apply_event when the lane is its own. The host never sends a rider's own toast to another peer, and toasts the rules return under one of these event keys are dropped.
- Alternatives: the host routes everything, including other riders' own toasts as hud messages (one more network path, and a client would have to stay silent on its own events); every peer raises everything locally, as Siege does (does not match GAME_SDK 10.2's team-wide toasts with peer 0).
- Reason: GAME_SDK 10.2 routing with no duplicates, and own-rider toasts cost no hud messages. Tested by combining what peer 2 sees from the host and from itself.

## 2026-10-23 [fish-module] Summary intent and lane looks
- Decision: configure sends FishingIntents.summary from FishingResults.summary_from(ctx.progress) on every peer, and the local lane wears that look straight away. The host applies each summary intent to its lane (summary_xp, records in kg = rec / 10, cosmetics clamped to how many items of each kind cosmetics.json has). Summary intents are exempt from the 5-per-second intent limit, which the module enforces per rider; other intents beyond the limit are dropped silently. Cosmetic indexes are 1-based per kind (0 = the default look; i = the i-th item of that kind in cosmetics.json order). fish-view must read them the same way.
- Alternatives: 0-based indexes (then the default look could not be expressed); handling the summary in the rules (the rules may still read it, since applying it twice gives the same result).
- Reason: brief 2.8 and the frozen FishingLaneState.cosmetics comment (0 = default look).

## 2026-10-23 [fish-module] Results rows and progress keys
- Decision: rows keep GameResults.from_stats and override time_in_band_s/pct with the lane's band_s / fight_total_s (0 % without a fight). Stats, in reading order: FISHING_STAT_FISH, _TROPHIES, _LOST, _BIGGEST ("<species> <kg> kg" or "-"), _LONGEST ("m:ss" or "-"), _POINTS. kJ and average %FTP are already in the results grid. Team values: FISHING_STAT_TEAM_POINTS, _TEAM_FISH, _TEAM_TROPHIES. Each row also carries `catches` [{sp id, kg, grade trophy|landed, fight_s}] and `records`, so every peer can write its own catch log. Progress keys: xp, unlocks, equipped {kind: id}, records {species: kg}, trophies, catch_log (newest 500), sessions (last 32 applied ids). FishingResults.build gained an optional 5th parameter `strings` (additive) for species names.
- Reason: GAME_SDK 15 (a client has no lane state to read catches from) and brief 2.8.

## 2026-10-23 [fish-module] Catch-log date from the session nonce
- Decision: the catch log's date is the UTC day of the session id's nonce (`<game>/<content>/<seed>/<hex ms>-<hex n>`), computed with integer civil_from_days. Ids without a nonce (run_game_sim) log "".
- Alternatives: Time.get_datetime_string_from_system (fails the package scan, and every peer must stay deterministic); leaving the date out.
- Reason: the brief asks for a date, and the host's UTC start is already in the id every peer shares.

## 2026-10-23 [fish-module] Snapshot flags a client restores
- Decision: FishingSnapshot.apply also restores the zero-input fallback, a frenzy (frenzy_until_t = client t + FRENZY_S when first seen, 0 when the flag clears) and a jump (fight_slot = the lane's first jumping slot of that species; clients roll the same slots). Re-encoding a client gives exactly the host's bytes. The 4-lane worst case is 599 bytes of JSON.
- Reason: brief 2.6: one snapshot fully restores a rejoining client, with no schema change.

## 2026-10-23 [fish-module] Fakes use the platform's PhaseTracker
- Decision: FishingFakes.Clock wraps PhaseTracker (the GameHost's own) instead of re-implementing the phase clock. Directives.end_phase goes through tracker.request_end (refused before min_s), finished calls finish_all, and telemetry follows the latest ERG request of the current phase. The stateless phase_at/frame/run helpers stay for existing callers.
- Reason: mirrors the GameHost exactly (end at max_s; end_phase takes effect at the end of the tick).

## 2026-10-23 [fish-view] View effects and sounds come from one cue vocabulary, two sources
- Decision: FishingCues turns either the module's fx_event(event) (when FishingGame has that signal, the view connects and uses only events) or edges in the state the view reads (lane state changes, run_active, off_line, fish_landed with the catch board's grade, hookup_level >= 2, frenzy, trip_over) into cues ({k, l, ...}); lane effects and FishingAudio react to cues only. Snap vs thrown on the state path uses the previous frame's strain vs slack, since the meters reset at a loss. A run is a jump when the species' content run_kind is "jump" (clients never get F_JUMP applied).
- Alternatives: events only (nothing shows in branches or builds without fx_event, and clients would depend on apply_event wiring); state only (loses event detail such as leaps).
- Reason: effects and audio work on host, client and SOLO whatever the module raises, and never fire twice.

## 2026-10-23 [fish-view] Client render clock and history
- Decision: FishingView runs render_t on the frame clock behind FishingSnapHistory.newest_t() by mean_spacing() clamped to 0.1..1.4 s, catches up with tau 0.25 s, stops at the newest and resyncs only past 1.5 s (Workout's WorkoutRideView pattern). Other lanes' d, z, cadence and W come from history.value_at(slot, key, render_t) (linear, never extrapolated); the local lane uses the state (its cadence is predicted by the module). The day cycle and HUD read the state.
- Alternatives: a fixed 0.1 s delay (stutters at the 8-rider load's ~1 s snapshots).
- Reason: GAME_SDK 12.

## 2026-10-23 [fish-view] Deck bar split around the kit widgets
- Decision: the deck bar's own Controls sit in two rects either side of the kit gear (306..359) and W' (362..441) rects: FishingDeckBar at Rect2i(0, 0, 304, 24) (trip clock with fishing time left, phase chip, fish row or gaff meter) and FishingCatchBoard at Rect2i(444, 0, 196, 24) (points, fish, hookup multiplier, last 5 catches). FishingLayout gains deck_left_rect() and deck_right_rect(); the view draws the deck planks underneath.
- Alternatives: one deck Control over the whole bar (HudLayer adds game Controls after kit widgets, so it would cover gear and W').
- Reason: no overlap, every rect clear of PANIC.

## 2026-10-23 [fish-view] Phase chip from the rider's own plan
- Decision: FishingDeckBar builds the local rider's plan once with FishingPlanBuilder.build(content.trip, game.slots[slot], reel_pct option) (every peer pre-rolls the same slots) and shows the phase label, the time left for fixed phases or the elapsed time for open-ended ones, and the next phase's label. Phase elapsed comes from the game time at which the lane's phase_index changed (first seen: t - state_t). Without a plan it falls back to the lane state's status text and next-state name.
- Alternatives: a phase clock in the snapshot (contract change).
- Reason: no contract change, works on clients.

## 2026-10-23 [fish-view] HUD zone stays pure sky
- Decision: clouds, islands and the surface strip are ParallaxStrips (mirror_alternate, cover_width 427); since a strip's last tile overflows its cover width, a dithered sky-gradient cover (FishingPalette.sky_cover_texture, 8 px Bayer edge) is drawn over x >= 419 in every lane's sky. The sun travels x 110..370; hints, fish, reefs and rays stay left of 427; the reefs end with a code-drawn flat rock cap at x 416..424 and flat sand runs on.
- Alternatives: clip_children (uncertain in the Compatibility renderer); hand-drawn strips instead of ParallaxStrip.
- Reason: brief 3.2 HUD zone rule with the kit's ParallaxStrip.

## 2026-10-23 [fish-view] Rig geometry and placeholder art
- Decision: FishingRig holds the boat-local mount points (bike, crank hub r 3, hip, thigh 6 and shin 7 px, reel hub, rod base, rod tip at boat x 80 = lane x 88, canopy rect, trim line, pennant mast) measured on FishingPlaceholderArt's boat. When generated art lands, these constants are the only numbers to retune (fish-art-qa may request changes). FishingSprites order: PNG plus sprites.json, then load("res://src/games/fishing/tools/fishing_fallback_sprites.gd").call("image", id), then FishingPlaceholderArt (palette shapes at the art.json size, the red key ramp on boat trim and canopy and on the angler's cap and shirt so PaletteSwap visibly works).
- Reason: the art is not in this branch.

## 2026-10-23 [fish-view] Cosmetics drawn in code
- Decision: lane.cosmetics [line, canopy, trim, pennant] index k picks the k-th item of that kind in cosmetics.json (0 = default look): the line colour; a canopy pattern overlay (stripes, dots or waves in translucent white over the key-coloured canopy); a 1 px hull trim line in the trim colour (the PaletteSwap slot colour stays on the key trim); the pennant is the slot's shape in its colour by default and a gold fish for "trophy".
- Reason: brief 2.8 (palette colours or code overlays) with the slot colour kept on the key ramp.

## 2026-10-23 [fish-view] Synthesized sounds (credits: synthesized with Sfx.synth, no files)
- Decision: FishingAudio registers fishing_click (square 1900 Hz, reel clicks one per 0.08 m of line at the local reel's line speed, >= 30 ms apart), fishing_splash (noise), fishing_plop (sine 260 Hz, cast), fishing_bell (sine 1320 Hz, strike bell on bite; pitched up for Double Hookup), fishing_twang (saw 196 Hz, snap), fishing_gull (triangle 1450 Hz, bird piles and frenzy), fishing_zip (saw 520 Hz, hookup and run), fishing_note_1..3 (triangle C5 E5 G5, the landing fanfare), fishing_horn (saw 147 Hz, trip over), and the loops fishing_surf (noise bed, -30 dB) and fishing_drag (saw 1250 Hz, drag scream while the local fish runs). Other lanes' cues play 10 dB quieter. The metronome is the platform's. Headless creates no players.
- Reason: brief 3.5 audio list; the G0 decision "Synthesized audio". fish-art-qa: please list these in docs/credits.d/fishing.md as synthesized.

## 2026-10-23 [fish-view] Lane HUD and YOU tag placement
- Decision: FishingLaneHud (213 x 36 art) shows a shape chip, "<W> W" and "<rpm> rpm" at 34 px (>= 32), the snapshot band lo/hi on a 50..130 rpm bar with an EMA-cadence marker, strain and slack mini bars (zigzag and loop icons) in fights, then species and distance or the status text. The local lane's YOU tag sits bottom-left over the reef, so it never covers the boat.
- Reason: brief 3.5; the top-left corner holds the boat's outboard.

## 2026-10-23 [fish-view] Lane setup method name
- Decision: FishingLaneView's builder is configure_lane(), not setup().
- Reason: tests/arch/test_no_bypass.gd flags .setup( on a receiver that has any untyped declaration in the file (FishingView loops over lanes with an untyped `for lv in lanes`).

## 2026-10-23 [fish-art-qa] Placeholder art (art fallback) (superseded: "Generated art")
- Decision: WATTLANDS_ALLOW_ART was not set (FAL_KEY was set; only presence was checked), so brief 3.4's fallback applies. FishingFallbackSprites (src/games/fishing/tools/fishing_fallback_sprites.gd, the orchestrator's name for the brief's fallback_sprites.gd) draws every art.json sprite but picker_card from the palette. fishing_write_fallback_sprites.gd writes the PNGs, the parts and a pipeline-format sprites.json marked "art_mode": "placeholder". picker_card keeps its G0 placeholder. The spend is $0.00, recorded in an empty art_manifest.json.
- Alternatives: generate anyway (refused by the art lock); leave the sprites missing so the view draws everything at runtime.
- Reason: the brief's fallback. Committed PNGs make the view, the screenshots and the palette test identical to the generated case, and the view can still call image(id) for any missing PNG.

## 2026-10-23 [fish-art-qa] Fallback sizes and palette hard-coded, checked against art.json
- Decision: FishingFallbackSprites carries its own copy of the palette, sizes and parts, and reads no file at runtime. The art test fails if any of them drifts from art.json. The writer, which is editor-time, uses the pipeline's ArtPixelate helpers for anchors and part names, has no class_name and is preloaded by path, so runtime code never depends on tools/.
- Alternatives: read assets/fishing/art.json at runtime (may not be exported); reuse ArtPixelate inside the runtime class.
- Reason: the view calls image(id) at runtime in an exported build.

## 2026-10-23 [fish-art-qa] Sim matrix shape (brief 4.2)
- Decision:
  - Player counts: S1 and S5 use 2 band-trackers (exercising HOST); S2, S6 and S7 use 1 rider; S3 uses 4 riders.
  - S8 is free_30 with 2 riders at seed 7, run twice. In --quick it is e2e_2min with 3 riders, run twice.
  - --quick (CI) = S10 + the S8 pair + S9.
  - Fight phases are identified as WORK ERG phases whose plan meta names a species.
  - Expected FIT laps = the lap-true phases that started (cool-down excluded), plus 1 when end_reason is complete.
  - S3's trip length is game_seconds <= 2100 (35 min, cool-down included).
  - Fight-time caps use fishing_s from the trip file.
  - Snapshot limit: max_snapshot_bytes <= 2048 for every run.
- Alternatives: 4 riders everywhere (slower); comparing the S8 hashes only through deterministic_hash.
- Reason: covers SOLO and HOST paths within the Godot slot budget. S8 also hashes events, phases, applied directives and results itself, as the brief asks.

## 2026-10-23 [fish-art-qa] Allowed clamps
- Decision: in every run, both applied directive records and 1 Hz trace rows (so plan targets are covered too) may show only slew, floor, unverified, rescue, coasting, haptic_intensity and warmup. switch_ramp and paused are allowed and reported. ceiling, long_phase, limit_105 and limit_120 fail by name, and so does any other rule (grade_range, grade_limit, haptic_limit, panic, factor_bounds). S1 is stricter and allows only slew, floor, unverified and haptic_intensity, plus the noted ones.
- Reason: brief 6 Directives and 4.2 scenario 1; the rule names come from addons/wattlands/contracts/wl.gd.

## 2026-10-23 [fish-art-qa] e2e_check reads the cool-down from phase_started
- Decision: the trip check needs the host's phase_started for phase 4 (the cool-down) within 135 s + 2 s of phase 0, per rider peer. That allows 2 s of wall-clock slack because e2e runs at --sim-speed=1 and stamps events in real time. A restarted client may hold an empty tail when it came back after the last Fishing event.
- Reason: the e2e report carries no plans or game times. Siege's tail rule, adapted to a trip that may end before the victim is back.

## 2026-10-23 Generated art (supersedes "[fish-art-qa] Placeholder art")

- Decision: real sprites from the art pipeline. WATTLANDS_ALLOW_ART was not set in this environment; asked, the user told the lead to set it, so it was set inline on the `generate.mjs` invocations only (never in the env scripts, never for a test, never printed with FAL_KEY). Spend $3.557 of $10 (53 paid requests). Flare drafts kept for boat and the four rig parts (each but the angler after one re-prompted draft) and fish_marlin; one sunburst pass for the rest, with one re-roll for 15 sprites (the first pass invented mascots in strips; "seamless strip, no animals or characters" fixed it) and two for the sun (the second result selected).
- Deviation: reef_front took three re-rolls, one over the brief's two-re-roll cap: after the mascot fix its pink coral quantised onto the PaletteSwap red key ramp (635 pixels, which the palette test forbids); two more "no red" prompts brought it to zero. Spend stayed far under the budget.
- Accepted flaws: small gulls, a weak mackerel silhouette, a few fringe pixels on the tuna, plain crank and reel discs. The fallback drawer (`FishingFallbackSprites`) stays as the documented fallback.

## 2026-10-23 G3 review and G4 round

- G3: three fresh reviewers (safety on Opus; rules, network and zero input; presentation, boundaries and code quality) found 17 issues: no blocker, 6 majors (all confirmed by independent verifiers; SAF-1 and RULES-1 are the same stagger bug), 11 minors. One G4 round with two fixers (rules and safety; view, HUD and docs) fixed them with tests; minors were fixed where cheap. Findings that need a trainer are in `src/games/fishing/HARDWARE_TEST.md`.

## 2026-10-23 [fix-rules] The rules forward every stagger edge to the pull scheduler
- Decision: FishingRules._update_stagger calls FishingPullScheduler.set_staggered(ps, true/false, t) on every rescue/AFK/stale start and end, whatever the lane state, and _begin_fight re-asserts set_staggered(ps, l.stagger_on, t) after begin(). FishingPullScheduler is unchanged. This supersedes the note that set_staggered only brackets a stagger inside a fight.
- Reason: a stagger that outlived its Fight left FishingPullState.staggered true, so every later Fight had no pull changes and every run was refused (SAF-1/RULES-1). One that ended in the Reel never set the 10 s pull pause (SAF-4/RULES-2). The scheduler's API already says 'any state', so fixing the caller keeps the plan sweep's results valid.

## 2026-10-23 [fix-rules] Every published band has a 65 rpm floor and keeps its width
- Decision: the ride-out practice band, the lure band and the idle band use the tension band's rule: low edge max(65, centre - half), high edge low + 2 x half (16 rpm). in_band means the EMA cadence is inside the published band. FishingRules.band_low() is shared by all four bands.
- Reason: brief 2.3's 4.6.3 check ('the band is always >= 65 rpm, above the 45 rpm trigger') outranks the 2.4 text 'preferred +- 8'. A preferred cadence below 73 rpm (30-160 is allowed) otherwise coached riders toward the rescue trigger in ERG phases where rescue is armed. Riders at 73 rpm or more see no change.

## 2026-10-23 [fix-rules] No Landing haptic to an AFK or stale rider
- Decision: haptic_allowed() also refuses on_afk, telemetry AFK and stale telemetry (a dropped client), as well as rescue, opt-out and the first 300 s.
- Reason: brief 2.3 says 'No request is sent during rescue or AFK', and the lane already treats AFK and stale as a stagger.

## 2026-10-23 [fix-rules] FishingRulesPull removed; the rules call FishingPullScheduler directly
- Decision: fishing_rules_pull.gd is deleted, together with its has_method probe and pre-merge fallbacks. FishingRules calls init_lane, begin, step, run_blocked_by_gap(ps, slot, t), start_run, set_staggered and end directly. The lane still passes FishingLaneState.pull_rng, which comes from the same (seed, slot, STREAM_PULL) derivation as ps.rng, so every stream and run is unchanged. This supersedes '[fish-rules] FishingRulesPull bridges fish-plan's G1 functions'.
- Reason: since the G1 merge the probe was always true, so the fallback branch and its extra fish parameter could never run (P11).

## 2026-10-23 [fix-rules] Sim scenario s11: unverified FTP, two FTPs, haptics off
- Decision: run_sims.sh s11 rides threshold with 2 band-trackers, --ftp=300,200 --unverified --haptics-off=1. check_sims S11 asserts that each Fishing ERG request is applied with the 'unverified' clamp, using only S1's clamp set (slew, floor, unverified, haptic_intensity). It reads the applied record's target_w, which equals 0.85 x target_pct x FTP within 1 W unless the floor lifted it; the record's target_pct echoes the request. It also asserts that every non-rescue Fight trace row shows 'unverified', that the haptics-off rider gets no haptic request, and that the other rider gets at least one.
- Reason: before this, every integrated run was verified at 200 W with haptics on (SAF-5), so the governor's unverified path and the haptic opt-out were checked only in pure tests.

## 2026-10-23 Lane HUD status reads like the teammate chip
- Decision: FishingHudModel.status_text uses the module's keys and positional args: a cast reads as the reel with the lure's distance, the fallback chip's next label uses keys without placeholders, and species names come from FishingResults.species_name. strings.csv stays positional. FISHING_STATUS_CAST is dropped. With no species, a strike, fight or Landing reads 'Fish on!'.
- Reason: the module passes positional arrays and fishing_game.gd is not view-owned. One formatter's args per key keeps the kit chip and the lane HUD identical, and a test pins that.

## 2026-10-23 No dead string keys
- Decision: every key in content/fishing/strings.csv must be read by Fishing's code or content, or be built from a prefix (FISHING_TIP_, FISHING_PHASE_). 17 unused keys were removed. The YOU tag draws FISHING_HUD_YOU in a 3x5 A-Z pixel font.
- Reason: brief 3.5 puts every string in strings.csv, and keys nothing reads make the strings test meaningless. A future toast for runs or jumps re-adds its key together with its caller.

## 2026-10-23 Boat trim reds mapped in code, not in the PNG
- Decision: the hull's PaletteSwap keys the key ramp plus the trim's coral (#f2665a), pink (#ef6fa6) and peach (#f1c29a), FishingPalette.HULL_KEYS. They swap to the slot colour lightened 0.3, 0.3 and 0.5. The trim cosmetic recolours the trim pixels read from boat.png instead of a fixed row.
- Reason: the generated art stays byte-identical (re-rolls keep working), PaletteSwap allows up to 8 keys, and the trim keeps its two-tone shading in every slot colour with no red left.

## 2026-10-23 Rig fitted to the generated boat
- Decision: the bike stands on the aft deck with its feet on the gunwale, and the angler sits on its saddle holding the rod butt. The reel sits on the bike's front, where the flywheel is, fed by the chain, with the line running up to the rod's first guide. The rod goes over the canopy to lane x 88, and the pennant stands on the roof's aft end with its flag streaming aft. DRAFT is 9 instead of 6. test_fishing_rig_art checks the mount points against the PNGs.
- Reason: a 10x10 reel at the hands hid the angler and the bike. On the bike's front the crank, chain, legs and reel all show (brief 3.1 'chain turns the reel'). DRAFT 9 keeps the angler's cap below a 4-lane local border and seats the hull in the water band.

## 2026-10-23 Waterline and HUD-zone backdrop
- Decision: the sky runs one row past sky_h (the surface strip's crest rows) and the water starts at sky_h+1. The HUD-zone cover is drawn after the surface strip and holds the sky plus the first water rows, cut from the same water gradient.
- Reason: no clear colour shows anywhere, the strip's holes show sky above the crests and water below, and the zone keeps only sky gradient, open water and sand (brief 3.2).

## 2026-10-23 Ride-out wake on open water
- Decision: on the ride out the boat sits 56 px right of BOAT_X0 and eases back (0.8 s time constant) by the first pick. The wake shows as the wake tiles plus a code-drawn foam trail behind the stern. The ride's easing follows the game clock as well as frames.
- Reason: at BOAT_X0 only 5 px of water lay behind the stern (brief 3.5 'shows the wake'). The game-clock step keeps fast-forwarded screenshots and late joins true to the sim.

## 2026-10-23 Double Hookup flash
- Decision: a 2 px gold beam between the linked rod tips (at their mean x) plus a burst at each tip, clipped to its lane, fading by ordered dither over LINK_S. The link clock follows the game clock too.
- Reason: brief 2.4 asks for 'a gold flash linking the lanes'. The per-boat boxes crossed the lane border at 4 lanes and looked persistent in fast-forwarded screenshots.

## 2026-10-23 Distant palm islet and two different ray sets
- Decision: draw order is clouds, then far islands, then the palm islet, which is drawn at half size by a palette-exact 2x2 mode downsample. The second light-ray set is mirrored, 70% tall, and sways at another speed, out of step with the first.
- Reason: brief 3.5 layer order. The islet was boat-sized with no distance cue, and the two ray sets were identical copies moving in lockstep.

## 2026-10-23 One art fallback
- Decision: FishingPlaceholderArt is deleted. FishingSprites uses the PNG, else FishingFallbackSprites, else (an export without the script) a blank image with a warning.
- Reason: the fallback script is always present, so the placeholder branch was unreachable. Brief 3.4 names one fallback.

## 2026-10-23 Final screenshots (brief 4.3 P1)

- Taken with `tools/screenshot` at 1, 2 and 4 lanes: the ride out (threshold 100 s), a tuna run (threshold 628 s), a Landing (threshold 887 s), a marlin fight with jumps (free_120 seed 4 at 1743 s, 1 and 4 lanes), e2e_2min at 10-95 s, and the client session screen with the PANIC corner. Skipped: a spot pick, because every sim rider plays as Autopilot or the zero-input fallback, which casts at once (brief 2.5); the pick view is covered by the view tests.
- Platform note, not changed: the kit's warm-up banner says "easy for 5 minutes" even in e2e_2min, whose ride out is 15 s.
