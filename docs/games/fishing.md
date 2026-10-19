ultracode

# Wattlands: Big Game Fishing game brief

You are the lead engineer and orchestrator for Big Game Fishing, one game module of Wattlands, a multiplayer fitness party game for the Wahoo KICKR CORE. The platform already exists in this repo, tagged `v0.1.0` or later on `main`: Godot 4.7, the app shell, the Game SDK, the art pipeline and the reference game Workout. Run the work as dynamic workflows with parallel subagents (section 5). I am not available, so never stop to ask. When something is ambiguous, choose what best serves the pillars (BRIEF 3.1, and 2.1 below), record it in `docs/decisions/fishing.md` (date, decision, alternatives, reason) and continue. Stop at the Definition of Done (section 6) or at the fix-round caps, then give an honest final report.

Read these first: `CLAUDE.md`, `docs/GAME_SDK.md`, `docs/ART_PIPELINE.md`, `docs/ARCHITECTURE.md`, and `docs/BRIEF.md` sections 1, 2, 3.1–3.10, 4.2, 4.5, 4.6, 5, 6 and 7. "BRIEF x.y" means that section of `docs/BRIEF.md`. On platform rules BRIEF wins; record any conflict.

## 0. Hard requirements

1. Build game `fishing` as a GameModule (BRIEF 3.6) on branch `game/fishing`, cut from the local `main` (G0). It depends on no other game.
2. Co-op for 1–4 players. Each player has their own boat, lane, rod and fish. No bots.
3. 2D pixel art at `pixel_base` [640, 360], with one equal-height lane per player. Every screen shows all lanes and highlights the local one. Sprites come from the art pipeline (BRIEF 3.10).
4. ERG for reeling and fights; SIM only for the 30 s Landing and its 15 s sprint. Every phase and directive passes BRIEF 4.6 (2.3).
5. Zero input: every trip plays through Autopilot and pedal-scan (BRIEF 3.5). `zero_input_content` is a 30-minute Free trip, and `first_run_priority: 10` makes fishing the first-run game (2.5).
6. Every game gate in BRIEF 7 passes (section 4), and the platform suite stays green.

## 1. Ground rules

- **BRIEF 1 applies, with two exceptions:** real fal calls are allowed under the art rule below (BRIEF 3.10), and decisions go only to `docs/decisions/fishing.md`, never to `docs/DECISIONS.md` or `docs/deps.d/`. That covers the hardware and network locks, `tools/env.*` for every process, `tools/godot.sh` or `.ps1` for every Godot run, the BRIEF 7 harness rules, and small conventional commits from one worktree and branch per builder. Commit locally only: never push, open pull requests or change remotes.
- **You own:**
  - `src/games/fishing/`, `content/fishing/`, `assets/fishing/` and `tests/games/fishing/`;
  - `.github/workflows/game-fishing.yml`;
  - `docs/decisions/fishing.md`, `docs/credits.d/fishing.md` and `docs/changelog.d/fishing.md`.

  Everything else is read-only.
- **Platform changes** are allowed only when a genuine gap blocks a P0 item (known candidates: the mock rider profiles and `tools/run_game_sim` report fields in 4.2, a rider's preferred cadence in PlayerSlot and `player_info` (2.4), and `tools/env.*` keeping the art variables (G0)). Make the smallest additive change, with tests and a `docs/GAME_SDK.md` update, in its own commit prefixed `platform:`. Record it and list it in the final report. Never change behaviour that Workout relies on.
- **Art budget: $10,** summed from `assets/fishing/art_manifest.json`. Pass `--budget=<10 − spent>` on every run. Real fal calls need `FAL_KEY` and `WATTLANDS_ALLOW_ART=1`, which Simon sets; never set them yourself. `generate.mjs` ignores the network lock (BRIEF 3.10), so keep it on for every process. Never print, log or commit `FAL_KEY`. If either variable is missing, or after two failed runs, use the fallback in 3.4. Run every test and gate command, the platform suite included, with `FAL_KEY` and `WATTLANDS_ALLOW_ART` removed from that process's environment, so no test can reach the real fal; only `generate.mjs` art runs keep them.
- **Originality:** prompts and strings describe original designs only. No brands, logos, insignia, real flags, existing characters or franchises.
- **Priorities:** P0 ships. P1 ships once P0 is green. P2 goes as notes in `src/games/fishing/BACKLOG.md`. No "TODO: implement" stays on a P0 path.
- **Resume:** if `game/fishing` exists, check it out, read `docs/decisions/fishing.md` and the last commits, and resume at the first unfinished step.
- **BRIEF 4.6 outranks this brief.** Change the design, never the governor. Never weaken a threshold or an assertion; report what fails instead.

## 2. Game design

### 2.1 Fantasy and pillars

You skipper a small sport-fishing boat in a tropical bay. A stationary bike is bolted to the deck, and its chain turns the big-game reel. Ride out, cast to the best-looking spot and reel at an easy spin; when a fish bites, the fight is the interval. In ERG the trainer holds the fish's pull, so cadence becomes the skill: at a fixed power, a lower cadence puts more torque on the line.

- **The trainer is the rod:** the pull is the ERG target, a run is a surge and the gaff is a sprint.
- **Fair:** pulls are shares of each rider's FTP, and fish tire by compliance, so the scaling mode (BRIEF 3.3) never decides who lands what.
- **Low attention:** pick a spot every 2–4 minutes, and otherwise just keep cadence in the band.
- **Co-op:** a shared catch board, Double Hookups and Frenzies.

### 2.2 Players and slots

1–4 humans, each with Autopilot on or off. Lane order follows slot order from the top, the same on every screen. Each slot color is paired with a pennant shape (circle, triangle, square, diamond) and a border pattern (solid, dashed, dotted, double). Players join in the lobby only. A dropped rider's lane is AFK (2.4) until they reconnect.

### 2.3 Effort plan

`build_effort_plans()` returns one plan per rider. Free and Base plans are pre-rolled per rider from `ctx.seed` and the slot index; Threshold and e2e fish schedules are the same for everyone. Fishing never calls `replan`: open-ended phases absorb the variation. The PlanValidator appends the cool-down (BRIEF 3.6).

| Phase | Kind | Mode | Target | Length | Lap |
| --- | --- | --- | --- | --- | --- |
| Ride out | WARMUP | ERG | 50%, `ramp_to_pct` 65 | 300 s | "Ride out" |
| Reel | RECOVERY | ERG | `reel_pct` (default 60%; e2e 55%) | Free/Base: `open_ended`, `min_s` 120, `max_s` = the trip length; `end_phase` at the hook-set. Threshold, e2e: fixed | "Reel n" |
| Fight | WORK | ERG | species base pull, with `range_pct` | `open_ended`, `min_s` = floor(0.8 × T_nom), species `max_s`; `end_phase` at landing | "<Species> n" |
| Landing | WORK | SIM `flat` | grade 0 + gear offset | 30 s after every Fight: 15 s sprint, 15 s spin | — |

Phases labelled in the last column set `lap`. `min_s` never exceeds the fastest landing (S falls at most 1.2 / T_nom) or the earliest bite (120 s), and a Reel's `max_s` outlasts fishing time plus overrun. The 30 s Landing keeps ERG/SIM switches 30 s apart, so BRIEF 4.5's mode-switch warning never fires.

| Species | T_nom window | `max_s` | Base pull | Changes | Runs or jumps | Band | kg | 4.6 check |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Mackerel | 60–120 s | 150 | 70–80% | ±4% | none | +10 | 0.5–2 | peak 83.2% |
| Mahi-mahi | 120–240 s | 270 | 88–95% | ±8% | 2–3 runs, 15–30 s at 105–110%, band +8 | +8 | 7–20 | phase ≤ 300 s; ≤ 90 s above 105%, none above 120% |
| Yellowfin tuna | 240–480 s | 540 | 93–97% | ±8% | 2–4 runs, 20–30 s at base × 1.08, band +10, sounding deep | +5 | 30–90 | 105% cap: 97 × 1.08 = 104.8% |
| Blue marlin | 600–1200 s | 1320 | 85–90% | ±8% | 4–8 jumps, 20–30 s at 104%, ≥ 90 s apart, band +15 | −2 | 150–400 | 105% cap: 90 × 1.08 = 97.2%, jumps at 104% |

Each fight slot draws w ∈ [0, 1] at plan time: base pull = lo + w × (hi − lo), and T_nom = lo + 0.8 × w × (hi − lo), so a rider who is mostly in band lands inside the window. Jumps = min(rolled, floor(T_nom / 115 s)). In Free and Base, the pre-roll draws each slot's species only from those whose window low end + 30 s fits the fight budget (40% of fishing time; Base 25%) left after the earlier slots' T_nom + 30 s, then caps w so T_nom + 30 s fits; slots stop when no species fits. The first slot therefore always passes last call (2.4); without this, about 23% of `free_20` riders would draw a tuna that never bites.

**Why marlin jumps stop at 104%:** 4.6.1 measures an open-ended phase by its `max_s`, so the marlin's 1320 s fight is a phase over 300 s, and the 105% cap covers every directive in it, jumps included. 104% keeps a point of margin so rounding never reaches the cap. The same rule holds both tunas to ≤ 105%; only the mahi (`max_s` 270) may run to 110%.

| Trip (content id) | Structure | Fish | Total |
| --- | --- | --- | --- |
| Free (`free_20`, `free_30`, `free_45`, `free_60`, `free_90`, `free_120`) | ride out, (N − 8) min fishing, cool-down | mackerel 45, mahi 30, tuna 25; in `free_90` and `free_120`, slot 2 is a marlin with p = 0.3; fights ≤ 40% of fishing | N min, plus ≤ 5 min last-fight overrun |
| Base (`base_60`) | ride out, 52 min fishing | mackerel 60, mahi 40; fights ≤ 25%; nothing above 100% | 60 min |
| Threshold (`threshold`) | ride out, Reel 240 s, then 4 × (Fight + Landing) with 360 s Reels between | scheduled tuna at 95% (T_nom 345 s, `max_s` 420, 3 runs, peak 102.6%) | 55 min, ≤ 60 |
| e2e (`e2e_2min`) | ride out 15 s at 50%, Reel 20 s at 55%, scheduled mackerel at 62% ±4% (band offset 0, T_nom 45 s, `max_s` 70), Landing 30 s | 1 per rider | ≤ 135 s |

Load changes go through `ctx.directives.request`; the rules use the applied target from telemetry. Every ERG directive is `{mode: ERG, target_pct, duration_s, reason: "pull" | "run" | "jump", source: "fishing"}`.
- **Range:** each Fight's `range_pct` is [base × (1 − a), max(base × (1 + a), run peak)], with run peaks 110% (mahi), base × 1.08 (tuna) and 104% (marlin), topped at 100% in Base. The PlanValidator checks it; every directive stays inside it.
- **Pull change:** a new multiplier in [−a, +a] every 8–16 s, ramped over 3 s as six directives 0.5 s apart (BRIEF 4.5 allows 2 writes/s), each with `duration_s` 0 so it holds until the next. Stretch the ramp so increases stay ≤ 25 W/s.
- **Run or jump:** the same ramp up, but every ramp step carries `duration_s` = the seconds left to the run's scheduled end. Each step then replaces the last with the same expiry (BRIEF 3.6), and at that end the target reverts to the base pull at once (decreases are immediate, 4.6.2), even when a rescue or AFK stopped the ramp part-way. At most 30 s above 105% per run, ramps included.
- **Pauses:** the pull-change clock stops from a run's first ramp step until the run's scheduled end (also when a rescue or AFK cut its ramp short), and from the start of a rescue or AFK until 10 s after it ends (2.4); then it restarts with a fresh 8–16 s interval. No `request` is sent during rescue or AFK.
- **Self-imposed caps:** everything ≤ 110%; haptics only in Landing (2.7).

The remaining 4.6 checks:
- **Warm-up (4.6.8):** the ride out ramps from 50% to 65% over 300 s, with no SIM and no haptics. The whole e2e trip falls inside it (62 × 1.04 = 64.5%), and the governor clamps its Landing gears to −2…+3%; the game sends no haptic there (2.7).
- **Targets (4.6.1):** every target and `range_pct` is 50–110%, inside the 30% floor and the 150% ceiling.
- **Duration limits (4.6.1):** only mahi runs pass 105%, for ≤ 90 s per fight against the 300 s limit; even 270 s at its `range_pct` top stays under it. Every Reel after a fight lasts ≥ 120 s at ≤ 70%, which resets both counters, so the PlanValidator's worst case passes too.
- **Slew (4.6.2):** 25 W/s, under the 30 W/s limit.
- **Rescue (4.6.3):** the band is always ≥ 65 rpm, above the 45 rpm trigger.
- **Haptics (4.6.6):** one +3% × intensity for 5 s per Landing (limit 8 s); Landings are minutes apart, so the cooldown never blocks it. Worst case 10 + 3 = 13% ≤ 16%.
- **Sprint (4.6.1):** the only sprint runs in SIM.

### 2.4 Rules and mechanics

Rules are pure classes with `step(state, inputs, dt)` at 0.05 s, using only `ctx.rng`; each rider's phase comes from `frame.phase`. Preferred cadence is each rider's profile value (BRIEF 3.2), which the host reads from their PlayerSlot (`preferred_cadence_rpm`, or the name `docs/GAME_SDK.md` uses). Band tests use cadence through an EMA with τ = 1 s. When cadence is stale for more than 3 s, the meters freeze; when a rider's telemetry is stale for more than 3 s (a dropped client), their lane is AFK (the stagger below) until it is fresh again, whether or not `on_afk` fires. Each band below is published with `ctx.directives.cadence_band` when its rounded edges change.

**Ride out.** The boat motors right, with parallax following trainer speed. A HUD tip shows every 45 s, and a practice band (preferred cadence ± 8 rpm) appears without meters. No bites.

**Spots.** Each cast shows 3 of Coral Bank's 4 spot types at seeded distances of 40–80 m: Bird Pile (gulls over a bait ball), Current Seam (a foam line), Reef Edge (shallow sonar marks) and Drop-off (deep sonar marks). Their affinities for mackerel, mahi, tuna and marlin:

| Spot | Mackerel | Mahi | Tuna | Marlin |
| --- | --- | --- | --- | --- |
| Bird Pile | 0.4 | 1.0 | 0.8 | 0.6 |
| Current Seam | 0.3 | 0.6 | 1.0 | 1.0 |
| Reef Edge | 1.0 | 0.3 | 0.3 | 0.1 |
| Drop-off | 0.5 | 0.4 | 0.8 | 0.8 |

A spot's strength is its affinity for the next slot's species × U[0.7, 1.0]. It shows in 4 steps: 1–4 gulls, 1–4 marks, or a longer seam. The plan fixes the species; the spot only sets how fast it bites and how heavy it is. Pick with left and right or pedal-scan, and cast with confirm or `surge`. Picks auto-confirm after two scan cycles (BRIEF 3.5).

**Reel.** The lure comes in at 0.35 m/s × cadence / 90, so a retrieve takes 2–4 min; recast at 5 m. The lure band is preferred cadence + the species offset, ± 8 rpm.

**Bite.**
- Hazard per second is (0.35 + 0.65 × strength) / 90 in the lure band and a quarter of that outside it. It is 0 while casting, in rescue or AFK.
- No bite comes before R_min = max(120 s, k × the previous fight's actual length, landing included), with k = 1.5 (Free) or 3 (Base). A bite is forced at R_min + 240 s.
- **Frenzy:** a hookup doubles every other rider's hazard for 60 s, once they are past R_min.
- **Last call:** no bite if the fight's `max_s` + 30 s would end more than 5 min after fishing ends, or if fight time + T_nom + 30 s would pass 40% of fishing time (Base: 25%). The trip then reels out quietly.
- **Scheduled trips:** the bite comes 4 s before the Reel ends.

**Strike.** A 4 s prompt. Confirm or `surge` sets the hook, and Autopilot sets it at 0.5 s. In Free and Base, the hook-set calls `end_phase` to start the Fight; a miss loses the fish, and the same species bites again 20–40 s later. A scheduled fish hooks itself but can't be a trophy.

**Fight state.** The fish has stamina S (starting at 1), distance d (m) and depth z (0 = surface, 1 = reef). At hook-set, d = min(the lure's distance, d_max).
- d moves toward 10 + (d_max − 10) × S, or to d_max on a run, at ≤ 4 m/s out and ≤ 2 m/s in. d_max is 40, 80, 120 and 200 m, mackerel to marlin.
- z moves toward 0.25 + 0.75 × S, or to 1 on a run. Each marlin jump is 2–3 leaps.

**Tension band.** The center is preferred cadence + species offset + run shift − 10 × (1 − S) rpm. The low edge is max(65, center − 8). The width is 16 rpm, or 22 with the rider's `relaxed_band` option. The center slides at ≤ 3 rpm/s.

**Meters.** Strain fills at 1/6 per second below the band, and slack at 1/6 per second above it. Whichever isn't filling drains at 1/12 per second. Full strain snaps the line; full slack throws the hook.

**Tiring.** In band, dS/dt = −min(1.2, power / applied target) / T_nom. Out of band, dS/dt = +0.25 / T_nom, with S ≤ 1. Run k of n fires at S = 1 − k / (n + 1).

**A loss costs the fish, never the work.** On a snap or a thrown hook, the fish is logged as lost and the meters reset. After 5 s a same-species replacement hooks itself in the same phase, keeping S and the pull schedule. It weighs 25% less and can't be a trophy. The plan never changes (v1 ended the fight instead).

**Rescue and AFK are staggers** (`on_rescue`, `on_afk`; BRIEF 4.6.3–4.6.4). S, the meters and the band freeze, the fish swims out at 1 m/s, and runs that come due are skipped. Play resumes 10 s after rescue ends, matching the governor's ramp-back. A rescue can never snap a line.

**Landing.** A fight ends at S = 0 with d ≤ 10 m (`end_phase`), or at `max_s` with the fish spent. The 30 s Landing runs in SIM flat with virtual gears, the gear indicator and no cadence band: a 15 s gaff sprint, then 15 s of easy spin as the fish comes aboard. At Landing start, clear the published band as `docs/GAME_SDK.md` defines; if it defines no way, leave the Fight's band published (nothing reads it in Landing) and record that.
- The gaff meter fills by ∫ max(0, P − CP) dt / (0.4 × CP × 15 s), counted only in the first 15 s and while P ≥ 1.2 × FTP (BRIEF 3.5). 15 s at 140% CP fills it.
- At 15 s a full meter makes a Trophy; otherwise the fish is Landed.
- Autopilot never sprints.

**Points.**
- Score = round(20 × √kg) × grade (Trophy 1.5, Landed 1.0) × hookup.
- kg = drawn weight × (1 + 0.15 × strength), × 0.75 for a replacement.
- **Double Hookup:** a fight that overlapped another rider's fight for ≥ 10 s scores × 1.5, or × 2 and × 2.5 when three or four fights overlap. It shows a toast and a gold flash linking the lanes.

**End.** When fishing time is up and no Fight or Landing is on, emit `finished("trip_over")`, and the platform skips to the cool-down. A running fight finishes first, with its Landing, and unused slots never start. Plan phases make their own FIT laps, so never emit `lap_marker` for them. Rules never depend on `phase_changed`: each rider's phase comes from `frame.phase`. If `docs/GAME_SDK.md` defines `phase_changed` for per-rider plans, follow it; otherwise never emit it (the GameHost already tracks each rider's phase and laps) and record that. In the cool-down (`frame.phase` kind COOLDOWN, directives ignored) the rules only motor the boats home.

### 2.5 Autopilot and zero input

- **Autopilot** (`autopilot_intents`) picks the strongest hint (the nearest on ties), casts and recasts at once, and strikes at 0.5 s. It never sprints, shifts or changes targets. Cadence still steers the tension.
- **No input:** a human who has sent no Fishing intent counts as Autopilot for picks, casts and strikes until their first intent, as in Siege and Tank, so a rider who only pedals hooks every bite at 0.5 s. The automatic `summary` doesn't count, and neither does a `surge` cast or strike or a pick that auto-confirmed (BRIEF 3.5); only a button or key action ends the fallback (`local_intents` gets gestures apart from actions, so tag gesture-made intents; if a surge also arrives as `confirm` in the same tick, treat it as the surge). After the fallback ends, picks still auto-confirm (BRIEF 3.5), scheduled fish hook themselves and a missed fish bites again 20–40 s later, so every trip finishes. `zero_input_content` is `free_30`.
- **First-run default:** `first_run_priority: 10` in `game.json` (Workout is 0) makes a fresh profile's first run play `free_30` (BRIEF 3.5).
- **Rider options** (`player_options`, read from each PlayerSlot's `options`): `reel_pct`, the Reel target, 50–70% in steps of 5 (default 60), and `relaxed_band`, which widens the tension band to 22 rpm (default off). No session-wide `options`.

### 2.6 Multiplayer and network

The host simulates all lanes at 20 Hz (BRIEF 5). Clients send telemetry and intents: spot left or right, confirm, and the `summary` (2.8).

- **Snapshot per lane:** phase index, state, species, d and z (0.1 m ints), S, strain, slack and gaff (each 0–255), band low and high (rpm), raw power (W) and EMA cadence (rpm), as ints, cosmetic ids, the selected spot, and hints [type, distance, strength] while picking. Team fields: points, fish count, hookup level and the last 5 catches as [lane, species, grade]. At most 2 KB for 4 lanes.
- **Events,** in the same order on every peer: `cast`, `bite`, `strike_ok`, `strike_miss`, `hookup`, `run`, `jump`, `snap`, `thrown`, `replacement`, `landing`, `landed {grade, kg, points}`, `double_hookup`, `frenzy`, `trip_over`.
- **Clients:** other lanes are interpolated 100 ms behind. `client_predict` moves only the local cadence marker; the host owns the meters. `apply_snapshot` restores a rejoining client; it and `apply_event` cast the integer fields back to int unless `docs/GAME_SDK.md` declares them for `Protocol.decode()` (BRIEF 5.5).

### 2.7 Haptics

Landing only: the fish's last run is one directive `{mode: SIM, haptic: 3.0, duration_s: 5, reason: "last_run", source: "fishing"}`, sent at a seeded 3–6 s into the sprint; the governor scales it by the rider's intensity (BRIEF 4.6.6). Never send it in the first 300 s of the plan (so never in `e2e_2min`), while the rider's telemetry shows rescue, or to a rider whose PlayerSlot shows haptics off; if PlayerSlot carries no haptics setting, send it and let the governor drop it for an opted-out rider (BRIEF 4.6.6). During fights, ERG pull changes do the work.

### 2.8 Results and progression

- **Grade:** team points ÷ expected points, where expected means every started fish Landed with no bonuses; in scheduled trips (`threshold`, `e2e_2min`), whose shared schedule makes fights overlap, expected points include each fish's Double Hookup multiplier. S ≥ 1.25, A ≥ 1.0, B ≥ 0.8, C ≥ 0.6, otherwise D. With no started fish the grade is D.
- **Rows:** kJ, average %FTP, time in band (% of fight time), fish landed, trophies, lost lines, biggest fish, longest fight.
- **XP:** 1 per kJ, 10 per fish, 25 per trophy, 50 per new species record. Every 500 XP unlocks the next item in `content/fishing/cosmetics.json`: 4 line colors, 3 canopy patterns, 3 hull trims and a trophy pennant, all palette colors or code overlays. Each kind's newest unlock is equipped.
- **Saved per rider** in `ctx.progress` (local, under `Paths.user_dir()/games/fishing/`): total XP, unlocks, a catch log (species, kg, grade, fight length, trip, date), species records and trophies. Only a `summary` intent (total XP, species records, equipped cosmetic ids) goes to the host, for record XP, unlocks and each lane's look. Each client saves only its own row.

### 2.9 Content

- **P0:** Coral Bank (4 spot types, a day cycle over the trip), the 4 species, the Free, Base, Threshold and e2e trips, and cosmetics. Files: `content/fishing/species.json`, `areas/coral_bank.json`, `trips/*.json`, `cosmetics.json` and `strings.csv`, all validated at load.
- **P1:**
  - **Deep Blue Trench at night:** giant grouper (180–300 s, `max_s` 330, 90%, band −10, peak 97.2%) and swordfish (360–600 s, `max_s` 660, 92–97%, band −5; v1's 100% top would peak at 108%).
  - **`marlin_hunt`** (75 min): a marlin bites 15–20 min in, with T_nom 900 s and 6 jumps.
  - **`.zwo` bite scheduling** through the platform's workout parser (BRIEF 3.7): work blocks ≥ 60 s become fights at the block's target and length; blocks above 105% lasting ≤ 30 s become runs; recoveries become reels; the PlanValidator decides.
  - **A legendary fish for two rods:** 2+ riders only, 88–92% ±8%, 8–12 min. It tires 1.5× while both riders are in band and 0.5× while one is.
- **P2 notes:** a tournament trip, hats and boat models, weather.

## 3. Presentation

### 3.1 Art direction

Start from `docs/concept/fishing_split_2p.jpg`, `fishing_split_4p.jpg` and the fishing section of `docs/concept/NOTES.md`. Keep the side-view slice: a boat on the left, the sea surface, a water column with light rays, reef and sand, and the line from rod to fish showing the fight. Fix what the concepts got wrong: the angler visibly pedals a stationary bike whose chain turns the reel, all lanes are equal, and the right third of each lane stays open water. Use 16-bit-style pixel art, a bright and cheerful tropical palette of at most 32 colors, and a dark navy outline. All players share one boat sprite, recolored with `PaletteSwap`.

### 3.2 Layout (art pixels)

- **Deck bar:** y 0–23. Each lane is h = 336 / n tall (336, 168, 112 or 84); lane i starts at y = 24 + i × h.
- **Lane rows, top to bottom:**
  - sky: max(30, round(0.28 h));
  - surface: 4 px;
  - water: the rest (38 px at 4 lanes);
  - reef: max(12, round(0.14 h)).

  Sprites are a fixed size, so fewer players means deeper water and more sky.
- **Boat:** x 8–88, rod tip near x 88.
- **Fish:** mouth x = 96 + (d / d_max) × (324 − fish width), so the whole fish stays left of x 420. Its y maps z onto the water rows.
- **Hints and the lure:** centered at x = 96 + (d / 80 m) × 300, so 80 m sits at x 396.
- **HUD zone:** x 427–639, full lane height, holding only sky gradient, open water and flat sand.
- **Borders:** the local lane gets a 3 px border in the player's color and pattern and a "YOU" tag; other lanes get 1 px navy.

### 3.3 Sprites (`assets/fishing/art.json`)

`style`: "Clean 16-bit pixel art game sprite, side view, bright cheerful tropical colors, flat colors, dark navy outline, chunky readable shapes, no fine detail, single subject centered and filling the frame, no text, letters, numbers, logos, emblems or flags." The PaletteSwap key is one 2-color red ramp, used only for the boat's trim and canopy and the angler's cap and shirt. Every sprite is transparent except `picker_card`.

| id and size | Prompt essentials |
| --- | --- |
| `boat` 80×32 | small white sport-fishing boat, exact side view, bow right, outboard at left stern, empty aft deck, canopy on two posts; red only on trim and canopy |
| `rig_bike` 24×16 | stationary exercise bike bolted to a deck, facing right, no crank or pedals |
| `rig_angler` 14×12 | cheerful angler's upper body seated on a saddle, facing right, red cap and shirt, arms forward on a rod handle, no rod |
| `rig_crank` 10×10, `rig_reel` 10×10 | chainring with two crank arms and pedals; big-game reel drum (circle, hub, four bold spokes, small chain sprocket) |
| `fish_mackerel` 24×8, `fish_mahi` 40×16, `fish_tuna` 44×16, `fish_marlin` 64×22 | exact profile facing left, tail at the right edge: striped mackerel; green-yellow mahi; navy-silver tuna with yellow finlets; blue marlin with bill and sail. Parts `body` (left 75%) and `tail` |
| `gull_up`, `gull_down` 10×8; `bait_ball` 32×12; `sonar_mark` 8×5; `current_seam` 48×4 | white gull, wings up or down; silver bait school; green arch echo; foam streak |
| `splash` 20×12, `spray` 32×24, `catch_flash` 24×24, `trophy_badge` 16×16 | water splash; spray burst; gold sparkle; gold fish trophy |
| `clouds` 320×24, `islands_far` 256×12, `island_palm` 80×24, `sun` 12×12, `wake` 32×6 | cumulus row; hazy islands; palm islet; sun; boat wake |
| `surface_strip` 64×6, `light_rays` 128×64, `reef_back` 416×28, `reef_front` 416×18, `sand_strip` 64×8 | wave crest with foam; light shafts; dark distant reef; colorful corals and rocks (both reefs flat at the right end); pale sand |
| `picker_card` 160×90 | one lane: angler pedaling a stationary bike on deck, the bike's chain visibly turning the reel, line to a leaping tuna, right third open water; it is `game.json`'s `picker_image` |

Animation by parts (BRIEF 3.10):
- `SpinningPart`: the crank, driven by cadence, and the reel, driven by line speed and reversed on runs (if `SpinningPart` can't reverse, fish-view turns the reel itself).
- `SpriteWobble`: fish tails, the bait ball and light rays.
- `ParallaxStrip`: clouds and islands, with mirrored tiling for the strips (if it has none, fish-view alternates normal and flipped copies).
- Gulls toggle at 4 Hz, and effects end in a dither dissolve.

Code draws, in palette colors and pixel-snapped:
- sky and water, as bands with ordered dither;
- legs, as two 2 px segments solved from hip to pedal;
- the chain, a dotted loop scrolling with cadence;
- the rod, which bends with tension;
- the line, which sags with slack and goes straight under strain.

P1 sprites: `fish_grouper` 40×18, `fish_swordfish` 64×20, `fish_legend` 96×30, `moon`, `trench_back`, `plankton`.

### 3.4 Asset procedure

1. In G0, write `art.json` and run `node tools/art/generate.mjs --game=fishing --dry-run`. Check the plan's request sizes: any sprite requested at an aspect more than 5% off its `size` (several 3.3 strips are 8:1 to 23:1) becomes a narrower tile the endpoint can draw at its own aspect, repeated in code by `ParallaxStrip` or a tiled draw; the reefs then end in a code-drawn flat cap at the right end. Record any change.
2. Draft `rig_*`, `boat` and `fish_marlin` on flare: set `endpoint` to `openai/gpt-image-2.5/flare/text-to-image` and run with `--only`. Pixelate the drafts and look at each one at 4×. Fix the prompts, set `endpoint` to `openai/gpt-image-2.5/sunburst/text-to-image`, and generate every other sprite, plus each draft that failed review, with `--only`; a flare draft that passes review stays.
3. Pixelate with `tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=fishing`. Re-roll a sprite at most twice, and only if it fails review (wrong facing, unclear silhouette, red outside the key parts, or rocks in the HUD zone): sharpen its prompt each time, because an unchanged input returns the same paid result (BRIEF 3.10), and run with `--only=<id>` so kept sprites, flare drafts included, are not regenerated. Stop at the budget.
4. Credit the art as generated with OpenAI's GPT Image 2.5 through fal, in `docs/credits.d/fishing.md`.
5. Fallback: `src/games/fishing/tools/fallback_sprites.gd` draws each id at its size from palette shapes, except `picker_card`, which keeps its G0 placeholder. If used, report "placeholder art".

### 3.5 View, HUD and audio

**View.** `make_view()` returns a Node2D: the deck bar plus one FishingLaneView per slot. Each lane draws, back to front:

1. sky, sun, clouds, islands and gulls;
2. water and light rays;
3. `reef_back`;
4. hints;
5. the fish;
6. `reef_front` and sand;
7. the boat with rig, rod and line;
8. effects.

The view only reads state, interpolating snapshots. Cosmetic randomness uses its own RNG seeded from `ctx.seed`. The day cycle moves the sun and steps the sky through 3 palette variants at thirds of the trip, with a 2 s dithered wipe. The ride out scrolls with trainer speed and shows the wake. In the cool-down the boats motor home with the wake.

**HUD.** `hud_spec()` puts the kit widgets (BRIEF 3.9) in the local lane's HUD zone: the phase timeline with next-phase preview, cadence with the band published by `cadence_band`, the power gauge, the W′ bar, and the gear indicator during Landing. Game widgets go beside them:
- a strain meter (red, zigzag icon) left of the band;
- a slack meter (yellow, loop icon) right of the band;
- a fish row: species icon, distance in m, stamina;
- the gaff meter during Landing.

In the local lane, W and rpm are ≥ 48 px at 1080p. Other lanes get a compact `FishingLaneHud`: band and marker, both meters, W and rpm at ≥ 32 px (the lane's snapshot W and rpm, 2.6, which also place its cadence marker), species and distance. The deck bar shows the trip clock, the catch board (team points, fish count, the last 5 catches as icons in lane colors) and the hookup level. Toasts appear below the deck bar. Warm-up and rescue banners cover the local lane's left two-thirds. All strings go in `content/fishing/strings.csv`, with keys prefixed `FISHING_`.

**Audio:** reel clicks at a rate set by line speed, drag screams on runs, gulls, splashes, a strike bell, a snap twang, a landing fanfare, a surf bed and the optional metronome. Use CC0 packs (credited) when available, otherwise synthesize (BRIEF 3.9).

## 4. Testing and gates

**4.1 Unit tests** (`tests/games/fishing/`, GUT through `tools/run_tests`):
- **Plan properties:** every trip × 200 seeds × 4 riders × each `reel_pct` passes the PlanValidator with no warnings and every directive rule and 4.6 check in 2.3. Reachable directives are enumerated, and ramps are checked at FTP 100–500 W.
- **Directives:** every species × 500 seeds stays inside its `range_pct`; runs expire back to the base pull; no pull change lands inside a run, a rescue or AFK; a rescue, and separately an AFK, starting at each ramp step of a mahi run and of a marlin jump leaves the applied target at the base pull from the run's scheduled end on (or, if the rescue or AFK outlasts that end, once it is over and the governor has ramped back), with ≤ 30 s per run and ≤ 90 s per fight above 105%, and no `request` sent during the rescue or AFK.
- **Phases:** `end_phase` timing against `min_s`, `cadence_band` updates, one lap per ride out and per Reel and Fight that ran.
- **Tension:** band width, low edge and slide; meters fill in 6 s and drain in 12 s; snap, throw and replacement (S kept, × 0.75, never a trophy); rescue and AFK freezes.
- **Tiring:** an ideal in-band rider reaches Landing between T_nom and T_nom + 15 s; out-of-band recovery; the end at `max_s`.
- **Bites:** seeded hazard, R_min, forced bites, Frenzy, last call, the 40% and 25% caps, and Autopilot's pick.
- **Gaff:** 15 s at 140% CP gives 1.0 ± 0.02; nothing counts below 1.2 × FTP.
- **Also:**
  - points, hookups, grades, XP, unlocks, `player_options`, the zero-intent Autopilot fallback (2.5), including that a rider who surges at a cast and at a strike, and whose pick auto-confirms, keeps Autopilot's picks, casts and strikes, while a key or button intent ends it, and `ctx.progress` with the `summary` intent;
  - snapshot round trips through `JSON.stringify` and `JSON.parse_string` (≤ 2 KB at 4 lanes);
  - content schemas, with bad files rejected via `assert_push_error`;
  - lane layout for n = 1–4;
  - string keys;
  - sprite PNGs that use only palette colors and transparency.

**4.2 Simulation:** `bash tests/games/fishing/sim/run_sims.sh` runs `tools/run_game_sim --game=fishing --content=<id> --players=<n> --bots=0 --rider=<profile> --sim-speed=200 --seed=<n> --report=build/fishing/sims/<name>.json` for each scenario below, and `node tests/games/fishing/sim/check_sims.mjs build/fishing/sims` asserts them. No GUT test under `tests/` reads `build/`, so the shared suite never depends on sim reports. Riders send no intents, so they play as Autopilot (2.5), and they follow `cadence_band` with MockTrainer's band-tracking `band` profile unless a scenario says otherwise.
1. **`threshold`, band-tracking rider:** 4 tuna landed, fights 240–420 s, no snaps. Every directive is applied unchanged apart from slew, the floor, the unverified-FTP factor and haptic intensity; `clamped_by` never names the absolute ceiling, the 105% long-phase cap or a duration limit.
2. **Off the band** (`threshold`): held 10 rpm below the band's low edge, the line snaps within 8 s of the hookup; held 10 rpm above its high edge, the hook is thrown within 8 s. The phase is not shortened.
3. **`free_30`, 4 band-trackers, seeds 1–20:** each trip ends ≤ 35 min, fights take ≤ 40% of fishing time, the median is ≥ 2 fish per rider, and at least one Double Hookup happens.
4. **`free_30` solo, no input,** with Autopilot off (and on, if `tools/run_game_sim` can set it): ≥ 1 fish landed in each run.
5. **`base_60`:** nothing above 100% is applied, and fights take ≤ 25%.
6. **`free_120` with a marlin seed** (search 1–500): 4–8 jumps of 20–30 s at 104%, 0 s above 105%.
7. **Cadence collapse mid-tuna** (`threshold`, 40 rpm for 20 s from 600 s, which is 60 s into the first Fight): rescue, then a stagger with no snap, then the fight resumes.
8. **Determinism:** the same seed and inputs give the same hash over the report's events, phases, applied directives and results (no wall-clock fields).
9. **FIT:** every FIT file the simulations write passes `tools/fit_check` (invoked as recorded in G0), with one lap per ride out and per Reel and Fight that ran, plus the cool-down's lap if the platform adds one (record which).
10. **`e2e_2min`, 3 riders:** one mackerel landed per rider, and the trip ends ≤ 135 s before the cool-down.

Profiles come from `docs/GAME_SDK.md` (BRIEF 4.2). Scenario 2 uses BRIEF 4.2's `band`, whose `offset_rpm` is measured from the published band's center (the low edge + 8 rpm at the default 16 rpm width): `erg+band:offset_rpm=-18` holds 10 rpm below the low edge and `erg+band:offset_rpm=18` 10 rpm above the high edge. Scenario 7 needs a cadence collapse at a set time for a set length (BRIEF 4.2's `cadence_drop`). If a profile is missing, or `tools/run_game_sim` or its report lacks something a scenario needs (each rider's applied target, mode and `clamped_by` over time, snapshot hashes, the FIT files it writes), add it as a `platform:` commit with tests (section 1).

**4.3 Platform gates (BRIEF 7):**
- `tools/run_tests` (strict rules), `tools/check_scripts.gd` and `tests/sdk/test_conformance.gd` (Autopilot slots at 1 and 4 players, as `bots` is false), whose log must show that `fishing` ran, so a hidden game can't pass;
- `node tools/e2e/run.mjs --games=fishing`: host plus two clients, one scheduled mackerel each (checked from the harness's per-peer event logs if it writes them; otherwise 4.2 scenario 10 covers it), identical events, every directive clamped, a valid FIT per peer, and a reconnect;
- `node tools/e2e/run.mjs --games=<every registered game>` (Workout, Fishing and any other merged game), green for every game that was green at the G0 baseline;
- the platform suite, with ≥ the G0 baseline count;
- `game-fishing.yml`, running unit, sim and e2e tests on Linux. Nothing is pushed, so it never runs on GitHub here: check that it parses as YAML and that each test command in it passes locally, and report it as verified locally only;
- P1: `tools/screenshot` at 1, 2 and 4 lanes during the ride out, a pick, a tuna run, a marlin jump and a Landing. Look at every PNG yourself. If it can't set the player count, seed or time a shot needs, take what it can (1 lane at least) and record what was skipped.

## 5. Orchestration

Use Opus 5.5 for every agent. Never let two agents edit one file in parallel. Godot runs queue through the wrapper lock. Run the e2e gates in 4.3 only while no builder, helper or fixer is running Godot, because one e2e run leases three Godot slots at once (BRIEF 2).

1. **G0 setup** (you, sequential):
   1. Check out the local `main` (never `origin/main`) and confirm it contains `v0.1.0` and the tree is clean. If the only dirty paths are planning files left uncommitted (`docs/games/`, `docs/concept/`, `docs/research.md`), commit them unchanged on `main` as `docs: add planning files` before cutting the branch, because builders' worktrees need `docs/games/fishing.md`, and record it. Record any other dirty path and keep it out of every commit. Record baselines: the platform suite's green count and `node tools/e2e/run.mjs --games=<every registered game>`. Then cut `game/fishing` (on resume, check it out), run `tools/new_game fishing` and read the SDK docs. On resume, skip every G0 step whose result is already committed, never rerun `tools/new_game fishing` once `src/games/fishing/` exists, and never move or re-create the `fishing-g0` tag.
   2. Record in the decisions file what `docs/GAME_SDK.md` says on:
      - how HudSpec positions map to PixelViewport art pixels;
      - clearing a cadence band, and `phase_changed` with per-rider plans;
      - a player count, seed and time for `tools/screenshot`;
      - what `tools/run_game_sim` lets you set per rider (profile, Autopilot), what its report holds and where it writes FIT files, and the `tools/fit_check` command line;
      - the mock rider profiles (`band` and its `offset_rpm`, `cadence_drop`).

      Also record whether `FAL_KEY` and `WATTLANDS_ALLOW_ART` are set, before and after sourcing `tools/env.sh` (or `.ps1`), never their values. If sourcing clears either, make `tools/env.*` leave both untouched in a `platform:` commit (section 1), since pipeline sprites are P0.
   3. Write `game.json`:
      - `id` fishing, `title` "Big Game Fishing", a one-line `summary`, `version` "0.1.0";
      - `min_players` 1, `max_players` 4, `bots` false;
      - `presentation` "2d", `pixel_base` [640, 360];
      - `entry` `res://src/games/fishing/fishing_game.gd`;
      - `contents`: all trips in 2.3;
      - `default_content` and `zero_input_content`: `free_30`;
      - `e2e_content`: `e2e_2min`;
      - `first_run_priority`: 10;
      - `picker_image`: `res://assets/fishing/sprites/picker_card.png`, the placeholder from step 5 until the art lands;
      - `player_options` (2.5), in the entry format of `docs/GAME_SDK.md` (if a field name differs, use the doc's spelling and record it; if the format has no `step`, make `reel_pct` a choice of 50, 55, 60, 65 and 70): `[{"id": "reel_pct", "type": "int", "min": 50, "max": 70, "step": 5, "default": 60, "label": "FISHING_OPT_REEL_PCT"}, {"id": "relaxed_band", "type": "toggle", "default": false, "label": "FISHING_OPT_RELAXED_BAND"}]`.
   4. Freeze `src/games/fishing/contracts/`: FishingLaneState, FishingFishState, FishingSpeciesDef, FishingTripDef, FishingPlanSlot, events, snapshot schema, constants. Every `class_name` under `src/games/fishing/` starts with `Fishing` (BRIEF 6).
   5. Write `art.json`, then a 160×90 opaque placeholder `assets/fishing/sprites/picker_card.png` in its palette colors (sky, sea and a boat shape), and import it, so `picker_image` never points at a missing file. fish-art replaces it, and it stays if art falls back (3.4).
   6. Commit and tag `fishing-g0`.
2. **G1 build:** 7 builders in parallel, each in a worktree on its own branch from `fishing-g0`.

   In the table, `S/` = `src/games/fishing/`, `C/` = `content/fishing/` and `T/` = `tests/games/fishing/`.

   | Agent | Owns | Builds |
   | --- | --- | --- |
   | fish-plan | `S/plan/`, `C/trips/`, `C/species.json`, `T/plan/` | plan builder, pre-roll, directive scheduler, 2.3 property tests |
   | fish-rules | `S/rules/`, `C/areas/`, `T/rules/` | spots, bites, tension, meters, tiring, runs, loss, landing, points |
   | fish-module | `S/fishing_game.gd`, `S/autopilot/`, `S/net/`, `S/results/`, `C/cosmetics.json`, `T/module/` | GameModule wiring, Autopilot, snapshots, events, results, progression |
   | fish-art | `assets/fishing/` except `audio/`, `S/tools/`, `docs/credits.d/fishing.md`, `T/art/` | 3.3–3.4 within budget, fallback, palette test, credits (audio credits from fish-view's report) |
   | fish-view | `S/view/`, `assets/fishing/audio/`, `T/view/` | 3.2 and the 3.5 view and audio, on placeholders until art lands |
   | fish-hud | `S/hud/`, `C/strings.csv`, `T/hud/` | the 3.5 HUD |
   | fish-qa | `T/sim/`, `.github/workflows/game-fishing.yml`, `S/README.md`, `S/HARDWARE_TEST.md`, `S/BACKLOG.md` | 4.2, CI, docs, real-trainer checklist (pulls, landing mode switch, haptic) |

   Each builder prompt names:
   - the sections to read;
   - the owned paths;
   - the contracts;
   - the test command: `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/games/fishing/<dir> -ginclude_subdirs -gexit -gjunit_xml_file=build/junit_fishing_<agent>.xml`, then `tools/godot.sh --headless --path . -s tools/check_scripts.gd`, under BRIEF 7's strict rules (fish-qa, whose folder holds no GUT tests, runs its 4.2 checker against fixture reports with Node instead);
   - the report format.

   Builders stay inside their paths and adapt to imperfect contracts. They list any string keys they need in their report's `strings_needed`, and fish-hud or you add them. Each builder commits and returns `{agent, branch, base_sha, head_sha, summary, files, tests_added, test_command, tests_total, tests_failed, junit_path, script_check_ok, decisions, open_issues, strings_needed, contract_change_requests: [{file, change, additive, blocks_p0}], platform_change_requests: [{file, change, blocked_p0_item}], art_spend_usd}`. Re-run each `test_command` before accepting.
3. **G2 integrate** (you plus up to 2 helpers):
   - Accept additive contract changes, and breaking ones only if they block P0. Write the `platform:` commits yourself.
   - Merge in order plan, rules, module, art, view, hud, qa, running the fishing tests after each merge.
   - Merge every builder's `decisions` into `docs/decisions/fishing.md`, and the audio credits from fish-view's report into `docs/credits.d/fishing.md`.
   - Loop over every gate in section 4. Progress means fewer failing checks. Stop after 2 rounds without progress or 5 rounds in all.
4. **G3 review:** one fresh-context reviewer per dimension:
   - safety against BRIEF 4.6 (any bypass or unchecked directive is a blocker);
   - rules and numbers against section 2;
   - network, determinism and reconnect;
   - zero input and pedal-scan;
   - presentation against section 3;
   - platform boundary;
   - code quality and test gaps.

   Each finding needs severity, file and line, evidence, and a failing test or a repro. A separate verifier confirms each finding before it is fixed, and only refuted findings are dropped. Findings that need hardware go to `HARDWARE_TEST.md`.
5. **G4 fix** (area fixers, then you; at most 2 rounds):
   - Fix confirmed findings with tests, rerun every gate and take the final screenshots.
   - Write the changelog fragment.
   - If every other Definition of Done item is met: merge the latest local `main` (never `origin/main`) into `game/fishing` if it moved and rerun every gate; if they still pass, merge into `main` locally with `--no-ff` and tag `fishing-v0.1.0`. Otherwise leave `game/fishing` unmerged and give the reason in the final report. Push nothing (section 1).

## 6. Definition of Done and final report

- **Built:** every P0 item is implemented, reachable from the game picker and tested.
- **Gates:** every section 4 gate is green (hardware excepted), or listed as failing with nothing weakened. The platform suite count is ≥ the baseline.
- **Players:** 1–4 players play every P0 trip through a room code, with equal lanes and the local lane highlighted. Solo play and hosting work with zero input, and a fresh profile's first run plays `free_30`.
- **Directives:** in every simulation, the governor changed the game's directives only through slew (4.6.2), the floor and the unverified-FTP factor (4.6.1), rescue (4.6.3), coasting (4.6.4), haptic intensity (4.6.6) and the warm-up clamp (4.6.8); `clamped_by` never names the absolute ceiling, the 105% long-phase cap or a duration limit.
- **Art:** P0 sprites use ≤ 32 palette colors; spend is ≤ $10 and recorded; credits are written; any fallback is disclosed.
- **Rides:** FIT files carry one lap per ride out and per Reel and Fight that ran (plus the platform's cool-down lap, if it adds one), and upload from the platform's results screen (BRIEF 3.8).
- **Docs:** the decisions file, the credits and changelog fragments, and `README.md`, `HARDWARE_TEST.md` and `BACKLOG.md` in `src/games/fishing/`.
- **Release:** merged into `main` and tagged `fishing-v0.1.0` locally; nothing pushed.
- **Final report in chat:**
  - what was built (P0 and P1);
  - every gate, with numbers;
  - art spend and sprite count, with any placeholders;
  - each `platform:` commit and why it was needed;
  - every deviation from this brief, with its decision;
  - what is untested on hardware, Windows or real fal;
  - top risks;
  - the exact commands to play fishing, run its tests and sims, and regenerate its art.
