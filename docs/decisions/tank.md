# Decisions: tank

Short ADRs for the tank game: date, decision, alternatives, reason. Game sessions keep their decisions here only; docs/DECISIONS.md holds the platform's. "Brief" is docs/games/tank.md; "SDK n" is a section of docs/GAME_SDK.md; "notes" are Simon's run notes for this run, which override the brief where they differ.

## 2026-10-23 G0 status

- G0.1 no-op (notes): the planning files were already committed and the tree was clean; `game/tank` was scaffolded by `tools/new_game tank` (7f34579).
- G0.2 answered by citation (next ADR); no `platform:` change was needed.
- G0.3 skipped (notes): full runs must reach max(`tests/green_count_floor.txt`, `build/green_count.txt`), 3506 after Siege and Fishing merged.
- G0.4 moot (notes; SDK 23 Q23): `tools/env.*` and the Godot wrappers never touch `FAL_KEY` or `WATTLANDS_ALLOW_ART`; only `tools/run_tests` strips them. Brief line 21 is moot: `generate.mjs` never reads the network lock. Every G0 command ran with `env -u FAL_KEY -u WATTLANDS_ALLOW_ART`.
- G0.5 done: `game.json`, `src/games/tank/contracts/`, the cross-builder stubs (plus a working skeleton so the game plays end to end), draft content, `strings.csv`, `assets/tank/art.json` and `rigs.json`, `tests/games/tank/fixtures/`. The `tank-g0` tag is the orchestrator's.

## 2026-10-23 G0.2 answers (by citation, no platform change)

- SDK names: every name the brief uses is spelled as SDK 23 Q17 says (PlanPhase fields, option entries, `course_grade`, `end_phase`, `cadence_band`, `frame.phase`, `ctx.options`, `ctx.progress`, `ctx.hud.power_band`, `local_intents`, `apply_progress`, `picker_image`).
- HUD (SDK 10, Q9, Q16): kit widgets at anchors or art-px `Rect2i`s; `power_band(peer, lo_w, hi_w)` sets the gauge's SIM band; the teammate strip is roster-driven plus `teammate_status {in_band, icon, text}` with a `res://` icon path (notes: the strip can show the engine icon); `toast(key, args, peer)` and `banner(key, args, seconds, peer)` take a peer (notes), default every peer; on the host pass `ctx.local_peer` for the host rider's own prompts, clients raise their own.
- Intents and local peer (SDK 11, Q6, Q7): `local_intents` and `ctx.intents.send` reach `frame.players[peer].intents` once each, in order, never int-converted; no platform rate limit (Tank enforces 5/s); `ctx.local_peer`.
- Remote directives (Q10): `course_grade` and `cadence_band` travel as `directive` messages, `end_phase` as the rider's `phase` message; only `request`s come back as applied records.
- Drops (Q8): a dropped peer gets `on_afk(peer, true)` at once, `connected` false and 0 W.
- Haptics (SDK 8.1, Q11, notes): a channel of their own; a haptic over a held `mode_grade` changes only the haptic term and its expiry ends only the haptic, so no re-send ADR is needed. The host refuses `haptic_in_erg` and `haptics_off`; the governor drops haptics in warm-up and within its 15 s cooldown.
- `apply_progress` (SDK 15, Q12): once per session on every peer; skip a repeated `session_id`.
- `phase_changed` (SDK 13, Q14, notes): the GameHost never emits it; Tank emits the group's phase (the lowest index any rider is in). An overrun is `PhaseState.prev_ended_by == "max_s"`; "the first 300 s" is `plan_elapsed_s < 300`.
- Mock riders and `run_game_sim` (SDK 19.1, 20, Q1-Q3): `erg` rides compliance x the centre of the published power band in SIM, else exactly 90% FTP; `cadence_drop` takes `at_phase` and `at_target_pct`; `--haptics-off`, `--override`, `--rider` per slot; 2+ humans run HOST; one FIT per human slot. FIT laps (notes): ashfall_road 12, drill 4 (checked on the G0 drill run: 4 laps, fit_check clean).

## 2026-10-23 Run overrides (orchestrator and notes)

- Five G1 builders instead of the brief's eight: effort, rules (rules and combat), module (module, net, Autopilot), view (view, HUD, audio), artqa (art and qa), with the paths listed in `src/games/tank/contracts/README.md`. The lead alone edits `game.json`, `strings.csv`, this file, `docs/changelog.d/tank.md`, `src/games/tank/README.md` and `contracts/`. Reason: fewer, disjoint owners keep every file single-writer; the brief's view/hud and art/qa splits share too many files.
- Model split: effort (plans, directives, haptics: the safety-critical builder) runs on Opus; the other builders run on the model the orchestrator assigns (the notes allow Sonnet). Reason: cost, with the BRIEF 4.6 paths on the strongest model.
- Sims reuse the platform as it is: `tools/run_game_sim` already has every flag the matrix needs (notes), so the S1-S8 scripts follow Siege's `run_sims.sh` / `check_sims.mjs` pattern and need no `platform:` change.
- Art: `WATTLANDS_ALLOW_ART` is not set this run, so no fal call happens. Every sprite id ships as a procedural placeholder (`view/placeholder_art.gd`), the view must work with placeholders for every id, and `art.json` is ready for a later art pass (dry-run estimate $4.27 for 61 sunburst requests).
- Audio is synthesized (`Sfx.synth`), no downloads (notes).

## 2026-10-23 P0 simplifications (none touches BRIEF 4.6, 4.5, a plan shape, a directive pattern, a gate or a check)

- Decision, so a crew can play a full ashfall_road early:
  1. Enemy movement is kinematic: an enemy enters from its edge at `speed_px_s`, picks its hold distance once (from `hold_px` with `ctx.rng`), then keeps station with the hull (Advance) or stays fixed in world space (gun lines); lights weave sinusoidally by `weave_px`; no pathing and no enemy-enemy collision (the view draws overlaps on two depth rows). Destroyers hold at the screen edge and shift `move_after_shot_px` after each shot; heavies roll to their hold, telegraph 3 s, back off 30 px per 50 damage.
  2. Encounters come only from the mission's fixed lists, keyed by metres driven into the Advance (`at_m`); gun-line enemies spawn at the segment start. No random spawns.
  3. Hits: enemy hit rolls at fire time (the brief's rule) with the shell as a visual projectile that lands on the tank or 20-40 px off; friendly shells hit by projectile point against target boxes each tick, splash by distance at impact. The ground is flat at y 296 for ballistics (terrain grade moves only effort and speed); no occlusion.
  4. Boss: the brief's choreography (creep 2 px/s to 120 px, 24 px push-back per broken bogie, phase 2 immobile, main gun every 35-45 s / 25-35 s after a 6 s telegraph, secondary 3 every 5 s at 60%); auto-aim takes the frontmost standing bogie, then the turret.
  5. Depot drills are scripted: drive 0-120 s with no enemies, an aim drill on two drill wrecks 120-240 s (auto-aim slews to them; no damage, no score), a fire drill 240-300 s (each loaded shell fires at a drill wreck); one teaching toast per station at fixed times. Nothing in the depot changes effort or score.
  6. Manual controls are minimal but present: every brief 2.6 intent (lever, aim nudge 1 degree with the 5 s auto-aim pause, target cycle, traverse, fire, latch, ram, over) works through `local_intents`; the only on-screen control surface is the station card and the trajectory dots.
  7. Overruns: an Advance tow snaps the hull to the halt line at the next segment start (the fade is view-only); a gun-line support barrage removes the remaining gun-line enemies at the next segment start with no kill credit; a Behemoth withdrawal is `finished("withdrawn")` and the view shows it leaving during the cool-down.
  8. Breakdown repair counts the P_eff of whichever station drives (diesel or Bulwark), the reserve's 60 W included.
  9. Unlimited ammunition, one shell in the breech; the Rampart's hoist always lifts heavy shells automatically once the breech cycle is over; the Citadel's secondaries are automatic only.
- Stays exact: every BRIEF 4.6 and 4.5 rule (Tank only asks; the governor clamps), the segment table, the engine table, the rotation tables and the drill (2.3, 2.9), every directive pattern with its numbers (bank sub-steps, boiler, hoist, terrain at 2 Hz, cadence bands, haptics, end_phase), the in-band rules, every number in the 2.4 tables (HP, damage, gun timings, hit chances, energies, caps), the score, XP and unlock formulas, intent ownership and the 5/s limit, the 4 KB snapshot budget, the events, and every gate and check (T1-T6, S1-S8, static tests, conformance, e2e).
- Alternatives: full enemy AI with pathing and cover; a physics hit model with terrain occlusion; interactive depot drills.
- Reason: the brief's pillars are the workout and the cutaway machinery; these cuts remove work that changes neither, and none moves an effort target, a phase or a check.

## 2026-10-23 Who calls end_phase

- Decision: the rules (`TankRules.step`) set `state.seg.objective_done` (Advance: the halt line reached; gun line: every gun down; boss: the Behemoth dead) and `regroup` while min_s has not passed; the effort director (`TankDirector.step`, the only Tank code that calls `ctx.directives`) calls `end_phase(peer)` for every rider of the group's phase in one step once `objective_done` and the group's `elapsed_s >= min_s`, once per phase. The platform ends a phase at `max_s` on its own; the rules see that as `prev_ended_by == "max_s"` on the next phase and play the overrun. The module emits `finished(state.outcome)` once every rider is in the cool-down (`victory`, `withdrawn`, or `complete` for the drill, which has no boss).
- Alternatives: the module calls end_phase; the rules call it through a sink.
- Reason: one owner for every trainer-facing call keeps the no-bypass and directive checks in one place; the rules stay pure; all riders share boundaries, so one step ends them together.

## 2026-10-23 Steam 90% float tolerance

- Decision: steam "building" is `power_w >= 0.90 x FTP - max(1 W, 0.5% x FTP)` (`TankConst.steam_building`; `tanks.json` `in_band.steam_build_tol_pct` / `_tol_w`). Never compare with float equality at 90%.
- Alternatives: exact `>= 90%`; a published steam power band (the mock would ride its centre).
- Reason: the SIM mock rides exactly 90% FTP with no band (notes, SDK 20) and power arrives in whole watts, so an exact comparison flips on rounding. The tolerance (1 W at FTP 200, 2 W at 400) is far below the 85% compliance gap (76.5% never builds), so T3 and T5 keep their meaning. The brief keeps the steam band off the power gauge, so no band is published for steam riders (the director clears it).

## 2026-10-23 Plan shape details

- Decision: one lap-true phase per mission segment for every rider (same kinds, lengths, min_s and max_s), modes and numbers from `stations.json` by the rider's engine in that segment; `PlanPhase.meta = {seg, stage, segment, engine, mission}`. The depot uses the slot's start engine; stage n uses the rotation table's column n and the boss column 4; a checkpoint already carries the next segment's engine (the crew moves at the checkpoint, so the station card shows the new engine during the 60 s at 50%). WARMUP-kind segments (the depot, the drill's skirmish) use the depot numbers for the boiler (3% x pressure), the hoist (1%) and terrain (0..+2%). The drill uses `stations.json` `drill_plans` (dynamo ERG 50 then 55 in `[55, 65]`) and ignores rotation.
- Checked (G0 integration test): every crew x rotation on/off x content validates with no warning; the first 300 s stay within 4.6.8; per rider every ERG <-> SIM switch is >= 60 s apart with each open phase at its min_s and at its max_s.
- Reason: brief 2.3's tables, with the checkpoint's engine the only free choice.

## 2026-10-23 Bands set by the host

- Decision: the director publishes `cadence_band(peer, 60, 120)` at each segment start for every rider and `power_band(peer, 76% FTP, 105% FTP)` for diesel and Bulwark riders in SIM phases, `(0, 0)` otherwise, all from the host (SDK 10.2 routes a remote rider's band to its peer).
- Alternatives: each client sets its own band (brief 3 wording).
- Reason: the host knows every rider's engine at the segment start; the routed band reaches the client's gauge and MockTrainer just the same, and simulations (HOST with loopback clients) follow it.

## 2026-10-23 HUD layout (art px at 640 x 360)

- Decision: explicit `Rect2i`s (`TankHud.RECTS`), HUD only in y 0-60 and 300-360, nothing in the PANIC corner (x >= 503 and y >= 316), every kit widget at least its 1080p minimum / 3 rounded up: power gauge 300x106 -> 100x36, cadence 290x98 -> 97x33, timeline 380x108 -> 127x36, readout 170x108 -> 57x36, W' 240x40 -> 80x14, gear 150x42 -> 50x14, teammate card 130x62 -> 44x21 (3 cards + 2 half-scale gaps of about 2 px = 134x21). Toast text 36 px -> 12 px, banners 56 px -> 19 px.

| Widget | Rect2i (x, y, w, h) | Arithmetic |
| --- | --- | --- |
| Timeline | (4, 2, 200, 36) | x 4..204, y 2..38; >= 127x36 |
| Hull HP readout (custom `hull_hp`, key number) | (206, 2, 60, 36) | x 206..266; >= 57x36 |
| Teammate strip (engine icon via `teammate_status`) | (268, 2, 140, 22) | x 268..408; >= 134x21 |
| Boss bars (Tank Control) | (410, 2, 226, 22) | x 410..636 |
| Toasts (prompts "Surge to ram/dodge/overpressure") | (268, 26, 368, 13) | y 26..39; 12 px text |
| Banners | (206, 40, 430, 19) | y 40..59 <= 60 |
| Power gauge with band | (4, 302, 100, 36) | y 302..338; >= 100x36 |
| Cadence with band | (106, 302, 98, 36) | x 106..204; >= 97x33 |
| Big watts readout | (206, 302, 60, 36) | x 206..266; >= 57x36 |
| W' | (4, 342, 100, 15) | y 342..357; >= 80x14 |
| Gear (SIM) | (106, 342, 98, 15) | >= 50x14 |
| Station card (Tank Control, key number >= 16 px) | (268, 302, 232, 56) | x 268..500 < 503, y 302..358 |
| Objective line (Tank Control) | (504, 300, 132, 15) | x 504..636, y 300..315 < 316 |

- Free: (206..266, 340..358) and the PANIC corner (503..640, 316..360). No rects overlap (tested).
- Alternatives: anchors (they stack and can't keep the PANIC corner and the 60 px bands at once).
- Reason: the notes call HUD space the tightest constraint; explicit rows make it testable.

## 2026-10-23 Art sizes beyond 3:1 and the range rule

- Decision: strips wider than 3:1 are `tile: true, mirror: true` segments at the brief's sizes (`bg_hills_far`, the six near strips, `bg_ground`, `fg_debris`); the transparent sprites slightly beyond 3:1 (`hull_rampart` 3.16, `hull_citadel` 3.6, `boss_hull` 3.2, `prop_wire` 3.2) keep their sizes and are requested at 3:1 with prompts that fill the width with empty space above and below, so pixelate's trim keeps the aspect; the opaque `bg_sky` (3.2) is cover-cropped (about 6% of its height). `--dry-run` lists them; estimate $4.27 for 61 requests. The view also tiles with `ParallaxStrip.mirror_alternate`.
- Range rule (brief 2.4): with the estimated muzzles in `rigs.json` (screen (208, 196), (248, 190), (288, 184); 100-112 px above the ground) the 30 degree range at v0 360 px/s and gravity 300 px/s^2 is about 503, 509 and 515 px against 1.1 x the muzzle-to-edge distances 475, 431 and 387 px, so `tanks.json` keeps the brief's 360 px/s; the rules builder re-checks it on the measured anchors.
- Reason: no tiles on hulls (a repeated hull reads wrong); the brief allows narrower segments, but tile + mirror keeps the brief's sizes.

## 2026-10-23 Smaller G0 choices

- Drill outcome: the drill has no boss, so it finishes `complete` once every rider is in the cool-down; its WORK time is 0, so its band score is 0 by the brief's formula (the drill grade is D for every crew; fine for e2e, which checks events and state, not grade).
- Results keys: per-rider stats and team values are keyed by `TANK_STAT_*` / `TANK_TEAM_*` strings in the results screen's order; `time_in_band` rows use Tank's in-band rule over WORK time.
- Snapshot units (`TankSnapshotSchema`): dpx (0.1 px), ms, cm/s, x10 grades and angles, HP rounded up. The Citadel fixture is 452 bytes; the cap fixture (16 enemies, 24 shells, large coordinates) is 1582 bytes, under 4 KB.
- Strings: the package test counts only quoted `"TANK_..."` literals as keys, so constant names such as `TankIds.TANK_BULWARK` are not mistaken for keys.
