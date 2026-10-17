ultracode

# Wattlands: one-shot build brief (Godot + Wahoo KICKR CORE)

You are the lead engineer and orchestrator for a one-shot build of Wattlands (working title), a multiplayer fitness party game for the Wahoo KICKR CORE smart trainer, built in Godot. Run the work as a sequence of dynamic workflows with many parallel subagents (section 8). I am not available during the run: never stop to ask me anything. When something is ambiguous, choose what best serves the pillars in section 3.1, record it in docs/DECISIONS.md, and continue. Stop only when the Definition of Done (section 9) is met or the fix-round caps are reached, then give an honest final report.

## 0. Hard requirements

1. Engine: Godot 4.7.x stable (4.7.2 or a later 4.7 patch; no 4.8 pre-releases), standard build, GDScript with static typing everywhere except GDExtension classes (4.2). Primary target: Windows 10/11 desktop. Renderer: Compatibility, for modest PCs and for headless or software-rendered testing.
2. Hardware: Wahoo KICKR CORE (2018 onward, current firmware) and KICKR CORE 2, over Bluetooth LE FTMS. Use ERG mode wherever it makes the game better.
3. Input: pedaling first, plus an optional Xbox controller and light keyboard use. Solo play and hosting, including every menu, mode, upgrade shop and results screen, must work with zero input through Autopilot and pedal gestures. Joining a friend's room needs only the typed code.
4. Multiplayer from the first commit: a host gets a short room code and friends type it to join. No accounts, logins or email.
5. Modes: the P0 modes chosen in 3.6 from Generator Siege (co-op tower defense run on your watts), Tank Crew (each rider powers one subsystem of a shared tank), Big Game Fishing (reel in at a few watts, fight each fish as an interval) and Kart Rush (versus racing); specs in 3.7–3.10.
6. Rides: every ride is saved as a FIT activity file, with optional upload to the rider's own Strava account (3.11).
7. Testable without hardware or live services: a mock trainer, byte-level protocol tests, headless simulation, an automated multiplayer end-to-end test and a mock Strava server.

## 1. Ground rules for this autonomous run

- You cannot test real hardware. Never send control commands (ERG, simulation, resistance) to a real trainer during this run. Read-only probing is allowed only through the `probe` tool you build, and only if an adapter and trainer happen to be present.
- Hardware lock: every process you start in this run has `WATTLANDS_NO_HW_CONTROL=1` (set it in `tools/env.sh` and `tools/env.ps1`, and in the e2e, screenshot and smoke scripts, which also pass `--mock-trainer` and refuse to run without it). While it is set, FtmsClient refuses Request Control and every control-point write (it may scan, read and subscribe) and logs "hardware control locked". A unit test asserts this; the shipped game never sets it.
- Network lock: the same files and scripts also set `WATTLANDS_NO_NETWORK_INTEGRATIONS=1`. While it is set, the Strava client refuses every host except 127.0.0.1 and localhost, never opens a browser, and logs "network integrations locked". Never call the real Strava API or use real credentials in this run; tests use `server/mock_strava` (3.11). A unit test asserts this; the shipped game never sets it.
- Prefer boring, proven solutions. Vendor third-party code from GitHub releases or pinned commits into the repo, with licenses and SHA-256 sums recorded in `docs/deps.d/`; don't rely on the in-editor Asset Store.
- Commit early and often with small conventional commits; each implementer works in its own git worktree and branch.
- Record decisions as short ADRs (date, decision, alternatives, reason) in `docs/decisions/<agent>.md`; you merge them into `docs/DECISIONS.md`.
- If a download or tool is blocked, use the documented fallback once, record it and move on. Never loop on retries and never download Node or Python runtimes.
- Priorities: P0 must ship. P1 ships once P0 is green. P2 is design notes only, in `docs/BACKLOG.md`. No "TODO: implement" may remain on a P0 path.
- The safety rules in section 4.6 outrank every gameplay idea in this brief. Never weaken a 4.6 threshold or a section 7 assertion to reach green; report what still fails instead.

Existing files: this repo may already hold the concept phase's material: `README.md`, `CLAUDE.md`, `.gitignore`, `docs/research.md`, `docs/BRIEF.md` (this brief), `docs/concept/` (concept art with `manifest.json` and `index.html`) and `tools/concept_art/`. Keep `docs/research.md`, `docs/concept/` and `tools/concept_art/` unchanged. W0 replaces the planning `README.md`, `CLAUDE.md` and `.gitignore` with the game's versions and moves any decisions they record into `docs/DECISIONS.md`.

## 2. Environment bootstrap (part of W0)

- Detect the OS and shell. Godot: use `$GODOT` or `godot` on PATH; otherwise download the official Godot 4.7.2 (or later 4.7 patch) standard build for this OS from the godotengine GitHub releases. On Windows use the `_console.exe` binary. Verify that `--version` reports 4.7.
- Run every Godot invocation through `tools/godot.sh` (`tools/godot.ps1` on Windows). The wrapper closes stdin, applies a timeout, never passes `-d`, and holds a machine-wide lock allowing at most 2 concurrent Godot processes (4 with at least 8 cores and 16 GB free RAM); a fresh import alone can use about 750 MB. On Linux it also sets `XDG_DATA_HOME=<worktree>/.userdata` (gitignored) so parallel worktrees don't share Godot's user directory.
- Never run two imports or editors on one folder. Several game instances may run from one folder once its import has finished (the end-to-end test does this).
- Run `tools/godot.sh --headless --path . --import` after adding files and before tests to refresh caches. It does not compile GDScript, so it is never a gate; section 7 has the real checks.
- Node: use the Node on PATH if it is 22.12 or newer; never download Node. The relay, the mock Strava server and the end-to-end harness must also work with zero npm dependencies if `npm install` fails (5.3). Python 3.12+ with uv or pip is optional: if bleak, websockets, PyInstaller or gdtoolkit can't be installed, treat Python as absent for those P1 parts and say so. Docker: write the Dockerfile; build it only if `docker info` succeeds.
- Blocked downloads (fonts, audio packs) get their fallback once, without retries.
- Screenshots (P1): on Linux try `xvfb-run` with Mesa llvmpipe and the Compatibility renderer; on Windows run windowed. If neither works, skip and record it.
- `.gitignore`: `.godot/`, `.userdata/`, `build/`, `node_modules/`, `__pycache__/`, `.venv/`. Commit Godot's `*.import` and `*.uid` files (Godot 4.4+ writes a random UID per script, so uncommitted UIDs break merges). Put a `.gdignore` in `server/`, `docs/`, `build/`, `tools/e2e/`, `tools/fit_check/` and `tools/trainer_bridge/` so Godot never imports `node_modules` or Python files.
- Running on a Windows PC with a Bluetooth adapter is fine; the hardware lock still applies.

## 3. Game design

### 3.1 Pillars

1. The trainer is controller and force-feedback device: effort is input, resistance is output.
2. Fair for mixed fitness by default; raw power always visible.
3. Low attention: decisions every 10–30 s at most, a HUD readable from 3 m, Autopilot for everything.
4. Real training: sustained work in ERG, sprints in free simulation, warm-up and recovery built in.
5. Safe by construction: every path to the trainer goes through one safety governor.

### 3.2 Rider profile (local, no accounts)

`profile.json` (in `Paths.user_dir()`, section 6): display name, color, units (metric default), weight kg (default 75), FTP W (default 200, marked unverified until the rider types it in, finishes the FTP test, or imports it from Strava in P1), CP (= FTP), W′ J (default 20000), preferred cadence (90), drivetrain (cassette or single-speed cog), trainer difficulty % (50), haptic effects (accept on or off, intensity 0–100%, default on at 70%), safety caps (section 4.6 defaults), Autopilot default (off), Strava auto-upload (off; 3.11). Weight never leaves the machine unless the player opts in; the host receives only what the selected scaling needs.

FTP test (P1, in Settings): a 5-minute ramp-in from 50% to 65% FTP, then one-minute ERG steps that start at 65% of the current FTP and rise by 6% of that FTP per step. It runs under the governor's ramp_test profile: duration limits and the 150% cap are suspended because the test ends itself, the ceiling is min(1000 W, the trainer's Supported Power Range max), slew and floor rules still apply, and the unverified-FTP factor does not. The test ends when power < 90% of the applied target for 10 s, cadence < 50 for 5 s, or you coast, and a 3-minute cool-down at 50% FTP follows. FTP = 0.75 × best 1-minute power, saved after a 10 s countdown unless `back`.

### 3.3 Effort scaling (lobby setting)

- FAIR_FTP (default): effort = P / FTP. Physics uses P_eff = (P / FTP) × 250 W for a 75 kg reference rider.
- WKG: effort = P / weight. Physics uses P_eff = (P / weight) × 75 for the same reference rider.
- RAW: actual watts, and actual weight only if the rider shared it (otherwise 75 kg). Scaling changes only how effort turns into game output; ERG targets always come from each rider's own FTP.
- Each client computes its own effort and P_eff and sends both in telemetry, so the host never needs anyone's weight.
- HUD and results always show raw W, %FTP and W/kg (W/kg only if the rider opted in).

### 3.4 Stamina is W′ balance

Implement Skiba's differential model every sim tick and show it as the stamina bar. It is a display and game-resource model; it never changes trainer targets except through section 4.6.

```
if P >= CP:  wbal -= (P - CP) * dt
else:        wbal = Wp - (Wp - wbal) * exp(-dt * (CP - P) / Wp)
clamp wbal to [0, Wp]          # Wp = W' in joules, P and CP in watts
```

### 3.5 Input, gestures and Autopilot

Actions: confirm, back, up, down, left, right, ability_1, ability_2, item, swap, shift_up, shift_down, pause, panic. `swap` moves your power to the next target in Generator Siege, and you to the next free seat at a Tank Crew checkpoint.

- Keyboard: arrows or WASD move, Enter or Space confirm, Esc back, 1 and 2 abilities, F item, R swap, Q and E shift down and up, P pause, Backspace held for 1 s panic.
- Xbox controller: left stick or D-pad move, A confirm, B back, X and Y abilities, RB item, LB swap, LT and RT shift down and up, Start pause, View plus Menu together panic.
- Everything rebindable and saved to `user://input.cfg`. The README explains how to map Zwift Click or Zwift Play buttons to these keys with BikeControl (open source).

Pedal gestures (a GestureRecognizer, unit-tested on synthetic streams):

- `pedal_start`: cadence ≥ 40 rpm or power ≥ 30% FTP for 3 s.
- `surge` (confirm): in menus and outside ERG, power ≥ max(1.3 × its 10 s average, 10 s average + 40 W) for 1.5 s, which is two consecutive samples at about 1 Hz. Inside ERG power is held, so use flywheel speed ≥ 1.12 × its 10 s average for 1.5 s. A stricter sprint rule (≥ 1.2 × FTP) applies only where a mode scores a sprint (Overdrive, Ram, Overwind, the landing sprint, Kart sprints).
- `not_pedaling`: one shared detector, power < 15 W and cadence < 20 rpm. It drives `coast`, `stop_5s` and the governor's coasting rule (4.6.4).
- `coast` (back): `not_pedaling` for 3 s, except during ERG, where it never means back.
- `stop_5s` (pause): `not_pedaling` for 5 s, solo and outside ERG only.

Pedal-scan menus (single-switch scanning): with Autopilot or pedal UI on, focus cycles through the options every 1.6 s (configurable); `surge` picks and `coast` backs out. Every menu works this way, including results and the upgrade shop. Picks shown during ERG phases auto-confirm the highlighted option after two scan cycles.

Zero-touch start: on launch, auto-connect to the last trainer; with a saved profile the main menu runs in pedal-scan mode; holding `pedal_start` for 5 s on the title screen starts the last-played mode solo. First run with no input: after 20 s of pedaling on the title screen, create a profile called Rider (FTP 200, unverified) and start the default mode from 3.6 solo (a 30-minute Free trip in Big Game Fishing). Joining needs a code, so offer a controller on-screen keyboard; code entry ignores dashes and spaces. P1 adds a LAN discovery list and Recent rooms (a host can reclaim their previous code), both pedal-scan selectable.

Autopilot is per player, toggled in the profile or lobby. Each mode defines what it automates (power routing, shop picks, aiming, casting, lanes, items). Autopilot never changes effort targets.

### 3.6 Modes to build

P0 modes for this run, built in this order: Big Game Fishing (3.9), Generator Siege (3.7) and Tank Crew (3.8). Kart Rush (3.10) is P2 design notes. To change the selection, edit only this paragraph: other sections say "each P0 mode", and a mode left out here goes to `docs/BACKLOG.md` as notes. Big Game Fishing is the first-run and zero-input default; if it isn't listed, use the first listed mode.

Every mode opens with warm-up content (4.6.8), ends with a 3-minute cool-down at 50% FTP and a results screen, and saves the ride (3.11). Each spec below gives the mode's effort plan (when it uses ERG or SIM, at what intensity and for how long), what Autopilot does, and its P0 and P1 content. A game failure never changes the effort plan; it costs score or time. Siege and Tank share `src/combat`: scrap-machine enemies that follow paths or steer to a target, health and damage, projectiles with simple ballistics, wave and encounter scripts and spawners, all stepped in fixed 0.05 s ticks with seeded RNG.

### 3.7 Generator Siege (P0, co-op 1–4, bots optional)

The team defends a pedal-powered base, the Dynamo, against waves of scrap machines. Each rider's watts flow to one target at a time: a tower (defense now) or the generator (sparks to spend later). Waves are the intervals, and the upgrade breaks between them are the recovery.

- Routing: `swap`, or left and right, moves your cable to the next target; it reconnects after 2 s. At most 2 riders share a tower. A tower's fire rate scales linearly with the P_eff routed into it (1.0× at 250 W). Unpowered towers stay idle unless upgraded with Capacitor (keeps firing for 10 s after its riders leave) or Trickle (runs at 25% unpowered). Solo riders can add up to 3 bots that pedal at the lobby's bot FTP and route by the Autopilot rules.
- Economy: the generator pays 1 spark per kJ of P_eff (15 a minute at 250 W). Kills pay a bounty to the riders powering the tower that made them, tuned to about half the generator's rate. Sparks are personal, and anyone may build or upgrade anything.
- Shifts: the lobby picks a shift, and the shift is the workout (table below). Every shift opens with a 5-minute warm-up wave (ERG ramp 50→65% FTP, light enemies) and a 2-minute build break at 50% FTP, and ends with the cool-down. Spawn budgets scale with wave length and the team's planned effort, so every wave length plays fair. A per-rider offset (−10 to +5 points, default 0) adjusts that rider's wave targets.
- Overdrive (ability_1, or a `surge` while its prompt shows): 15 s with ERG off and SIM flat, virtual gears on; while your power is above CP your target's output doubles, and W′ drains as usual. It has a 90 s cooldown, never runs during warm-up, and Autopilot never triggers it. Endurance waves add a rush every 8 minutes that rewards an Overdrive.
- Base: each wave ends with a Junk Hauler push in its last 60 s. The base has 100 HP. At 0 HP a Blackout stops every tower for 10 s, reboots the base at 30 HP and costs everyone 30% of their unspent sparks, while the wave and its ERG target run on. A shift ends with a grade (S to D) from base HP, Blackouts and sparks earned, plus XP and cosmetic unlocks (hut paint, cable colors).
- Breaks: the shop opens at the break's ERG target and closes after a 10 s countdown. Build on an empty pad, upgrade a tower (three levels: +40% output, +25% range, then a special), upgrade the generator (+20% sparks per level, three levels), armor the base (+25 HP) or buy a team perk (Capacitor, Trickle). The shop runs on pedal-scan, and picks auto-confirm after two scan cycles.
- Autopilot: power the tower with the most enemy HP inside its range, otherwise the generator, swapping at most once per 8 s. In the shop, build a tower covering the path with the most leaks, then upgrade towers on that path, then the generator.
- P0 content: one map, Dynamo Ridge (three paths, eight pads). Towers: Arc Coil (short range, chains to 3 targets), Spoke Ballista (long range, pierces) and Headwind Fan (a cone that slows enemies by 40%, no damage). Enemies: Scrap Bug (swarm), Grease Slug (slow, armored), Spoke Wasp (fast flyer) and Junk Hauler (heavy, splits into bugs). P1: a second map, Pothole Mortar and Magnet towers, a boss wave, custom shifts (1–10 waves of 1–20 min at 60–115% FTP), and `.zwo` import that turns each work block into a wave of the same length and target and each recovery into a break.
- Network: snapshots carry enemy ids, path progress and HP, tower state and each rider's target, with at most 150 live enemies. Siege sends no resistance haptics; the ERG target is the wave.

| Shift | Main set (ERG) | Breaks (ERG) | Total |
| --- | --- | --- | --- |
| Short (default) | 3 waves × 5 min at 95% FTP | 3 min at 50% FTP | 31 min |
| VO2 | 6 waves × 2 min at 112% FTP | 3 min at 50% FTP | 37 min |
| Sweet spot | 2 waves × 15 min at 90% FTP | 5 min at 55% FTP | 45 min |
| Endurance | 1 wave × 45 min at 70% FTP | none | 55 min |

Totals include the warm-up wave, the build break and the cool-down.

### 3.8 Tank Crew (P0, co-op 1–3, AI crew fills empty seats)

Up to three riders crew one pedal-powered tank, the Tread Hog, through a scripted mission against the same scrap machines as Siege. Each seat powers one subsystem with its own effort profile, so the trainer feels different in each seat.

| Seat | Subsystem | Trainer | Effort profile |
| --- | --- | --- | --- |
| Driver | Motor: speed and lanes | SIM on the mission's terrain | Sustained tempo, harder on climbs |
| Gunner | Hydraulics: turret traverse and gun elevation | ERG that follows the hydraulic accumulator, 55–100% FTP | Repeated 30 s to 2 min efforts in fights |
| Loader | Wind-up cannon: a giant clockwork spring on a hamster-wheel winch | SIM, with mode grade rising as the spring winds | 10–30 s hard efforts, resting while loaded |

- Driver: P_eff drives the treads through the speed model in 3.10 (the scaling mode's rider mass plus 8 kg, CdA 0.5 m², a visual multiplier for a heavy feel), built in `src/sim` even when Kart Rush isn't. Left and right move between 3 lanes for cover and pickups. Ram (ability_1) is a 10 s sprint: a barricade hit while the sprint rule holds (≥ 1.2 × FTP, 3.5) breaks; otherwise it costs 10 HP and a 5 s stop. While the tank waits at a gate, the driver's watts charge the hull shield.
- Gunner: traverse and elevation draw pressure from the accumulator, which the gunner refills at a rate set by P_eff while in band (power ≥ 95% of the applied target, cadence ≥ 60); pressure sets the slew speed. The ERG target is 55% FTP with a full accumulator, rising linearly to 100% FTP when it is empty, updated every 5 s and ramped over 3 s. The stick or arrows aim with a trajectory arc, confirm fires once the cannon is loaded, and auto-aim is on by default.
- Loader: mode grade rises from 0% to +8% as the spring winds (scaled by difficulty, 4.6.6). A full spring stores 6 kJ of P_eff (24 s at 250 W) and latches a heavy shell; the grade then drops to 0 and the loader spins easy until the shot. Confirm latches early for a light shell, and Overwind (ability_1) winds on to 150% for double damage at the cost of W′.
- Crew: empty seats get AI crew (the bot rider model at the lobby's bot FTP). Seats change only at checkpoints. With rotation on (the default), every human moves one seat at each checkpoint (driver to gunner to loader), so one mission mixes tempo, repeated efforts and sprints; a solo rider picks a seat in the lobby and can `swap` at checkpoints.
- Mission (P0): Scrapyard Run, about 30 min. A 5-minute garage drive-out on flat road is the warm-up (no enemies, the gunner at 55% FTP, the spring held to the warm-up grade limit). Then come three 5-minute stages (rolling terrain and drone attacks, then a gate bunker to destroy), each followed by a 60 s crew-swap checkpoint at ERG 50% FTP; the Junk Walker boss (about 4 min: shoot out its legs, then its core); and a 3-minute cool-down cruise home at ERG 50% FTP.
- Damage: the tank has 100 HP. At 0 HP it breaks down for 20 s while the driver's watts power the repair, then carries on at 40 HP; breakdowns cost score, never progress. Results show time, hits, accuracy, breakdowns and each seat's effort (kJ, average %FTP), a grade (S to D), XP and cosmetic unlocks (paint, flags).
- Haptics: the driver feels terrain (course grade) and hits (haptic +2% for 1.5 s, 4.6.6); the loader feels the spring (mode grade); the gunner feels the accumulator through the ERG target.
- Autopilot: the driver steers for cover and pickups and never sprints; the gunner auto-aims at the nearest threat with a ballistic solution and fires when loaded; the loader latches at full wind and never overwinds.
- Network: the host simulates the tank. Clients send intents (lane, aim deltas, fire, abilities) and render snapshots with 100 ms interpolation; the turret's slew rate hides 100–200 ms of latency.
- P1: a garage between missions (scrap buys armor, a bigger spring, a faster pump and tread grip), a second mission (Canyon Convoy) and two tanks in one lobby.

### 3.9 Big Game Fishing (P0, solo or co-op 1–4 on one boat)

Ride out, cast, and reel in slowly at a few watts; a bite starts an interval sized by the species. In ERG the trainer holds the fish's pull, so cadence becomes the skill: at a fixed power, a lower cadence puts more torque on the line.

- Ride out: the boat trip to the fishing grounds is the warm-up (5 min, ERG ramp 50→65% FTP) and teaches the HUD; the ride home is the cool-down.
- Cast: pick one of 3–5 spots by its hints (birds, sonar marks, current) with left and right, then `surge` or confirm to cast. Autopilot picks the spot with the best hint.
- Reel: ERG at 60% FTP (configurable 50–70%). Each species likes a lure speed, shown as a cadence band offset from the rider's preferred cadence (tuna +5 rpm, grouper −10 rpm), and time in a fish's band raises its bite chance. A full retrieve takes 2–4 min; then cast again.
- Bite: a 4 s strike prompt; `surge` or confirm sets the hook, and Autopilot sets it automatically. A missed strike loses that fish.
- Fight: the species sets the interval (table below). The ERG target is the fish's pull: runs and head shakes change it by up to ±8%, ramped over at least 3 s and at most every 8 s, and each run or jump above 105% FTP is its own directive of at most 30 s. A tension band at least 16 rpm wide, never below 65 rpm, moves with the fish: up when it runs (give line by spinning faster), down when it tires (pump it in with a slower, heavier stroke). Below the band a strain meter fills; above it a slack meter fills. Each fills over 6 s and drains at half that rate in band; full strain snaps the line, and full slack lets the fish throw the hook. In band the fish tires at a rate set by P_eff, tuned so a rider in band lands it inside its fight window.
- Landing: within 10 m of the boat, a 15 s landing sprint (ERG off, SIM flat, virtual gears) fills the gaff meter with energy above CP, and the fish's last runs are haptics (4.6.6). A full meter lands it at trophy grade; skipping the sprint still lands it one grade lower. Autopilot never sprints.
- Trips: Free trip (20–120 min; random bites weighted by spot and band time; fights capped at 40% of the trip), Base trip (60 min; mackerel and mahi-mahi only; fights at most 25% of the time) and Threshold trip (about 56 min: four scheduled 6-minute tuna fights with 6 minutes of reeling between them). P1: a Marlin hunt, and `.zwo` import that schedules bites to match a workout.
- Co-op: up to 4 riders on one boat, each with their own rod and fish, a shared catch board, and a Double Hookup bonus when two fights overlap. P1: a legendary fish that needs two rods at once.
- Progression: a catch log, records per species, trophies, and cosmetic rods and boats. Results list each catch with weight and fight time, plus time in band and snapped lines.
- Zero input: Autopilot picks spots, casts, strikes and lands; the rider only pedals, and cadence still steers the tension.
- P0 content: one area, Coral Bank (4 spots, a day cycle over the trip), and the four P0 species. P1: Deep Blue Trench with night fishing and the P1 species.

| Species | Fight | ERG pull | How it fights |
| --- | --- | --- | --- |
| Mackerel | 1–2 min | 70–80% FTP | Steady; common |
| Mahi-mahi | 2–4 min | 88–95% FTP | Two or three runs |
| Yellowfin tuna | 4–8 min | 95–100% FTP | Long runs and deep pumps |
| Blue marlin (trophy, rare) | 10–20 min | 85–90% FTP, plus 4–8 jumps of 20–30 s at 110–115% FTP | Each jump lifts the band by 15 rpm |
| Giant grouper (P1) | 3–5 min | 90% FTP | A low band: a torque fight by the reef |
| Swordfish (P1) | 6–10 min | 92–100% FTP | Night only |

### 3.10 Kart Rush (P2 in this run unless 3.6 selects it; versus 2–8, bots fill)

- Tracks: P0 has one closed loop (Curve3D) with 3 lanes, 2–4 km of game distance and 3 laps; P1 adds two more. Elevation becomes course grade (stacking rule in 4.6.6).
- Speed is integrated every sim step from P_eff: `v += dt·(η·P_eff / max(v, 1) − m·g·(Crr·cosθ + sinθ) − 0.5·ρ·CdA·(v + v_wind)·|v + v_wind|) / m`, with v ≥ 0, Crr 0.004, CdA 0.32 m², ρ 1.225, η 0.97 and m = the scaling mode's rider mass plus 8 kg. Tests use the steady-state equation `P·η = v·(m·g·(Crr·cosθ + sinθ) + 0.5·ρ·CdA·(v + v_wind)²)`, solved by bisection on [0, 30] m/s, as the oracle. A configurable visual speed multiplier is allowed for game feel.
- Drafting: 1–10 m behind in the same lane cuts CdA by up to 30% (linear fade) and scales the `cw` sent to the trainer by the same factor, so the draft is felt.
- Lane changes are discrete (0.4 s tween) and blocked if the target slot is occupied within 2 m; no other collisions.
- Items, position-weighted like Mario Kart. P0: Tailwind (self: +15% speed for 5 s and a tailwind on your trainer), Headwind Cloud (rider ahead: a wind haptic and −8% speed for 6 s), Fender (blocks one attack), Tow Rope (last place: 4 s of auto-ride at reduced resistance). P1: Anvil (target: +2% grade for 5 s), Slipstream Magnet (pulls you into a draft), Puddle (next rider through loses 30% power-to-speed for 2 s), Bonk Bomb (last place only: everyone ahead gets +1% grade for 4 s).
- Every resistance effect is a haptic request to the receiver's governor (4.6.6). A receiver who opted out gets the visual and speed effect only.
- Results show position, raw W, %FTP and W/kg if shared. Sprint banners and a KOM per lap are P1.
- Autopilot picks lanes for drafts and item boxes, dodges hazards and fires items by heuristics. Bots pace from an FTP with variability and tire through W′.
- Neutral roll-out: ERG 60% FTP behind a pace car for 60 s, extended to cover any remaining warm-up (4.6.8), then a ramped switch to SIM at the start line.

### 3.11 Rides, FIT export and Strava (P0)

- Recorder (`src/rides`): every session records the local rider at 1 Hz (timestamp, power, cadence, speed, and distance from the trainer's reported speed), with a lap at each wave, stage or fight. On the results screen it writes `rides/<UTC start>_<mode>.fit` and a JSON summary under `Paths.user_dir()`. Each rider keeps only their own ride; no ride or Strava data goes to the host or the relay.
- FIT encoder (pure GDScript): protocol 2.0 with a 14-byte header, header and file CRCs (the FIT SDK's CRC-16), and the messages file_id (type activity 4, manufacturer development 255), device_info, event (timer start and stop), record, lap, session (sport cycling 2, sub_sport virtual_activity 58, totals, average and maximum power and cadence, total work) and activity. FIT timestamps count seconds from 1989-12-31 00:00:00 UTC (Unix time − 631065600). No GPS fields.
- Decoder check (`tools/fit_check`): decode every FIT file the tests write with Garmin's `@garmin/fitsdk` (npm, pinned; `Decoder.isFIT`, `checkIntegrity`, `read`), assert zero errors and the expected values, and take enum values from the SDK's profile. If npm is blocked, the qa agent writes an independent GDScript decoder for the same checks.
- Connect: Settings → Strava takes the client ID and secret of the player's own Strava API app (README: create it at strava.com/settings/api with callback domain `localhost`). Connect serves a loopback callback with `TCPServer` on 127.0.0.1 for up to 5 minutes and opens the browser at `https://www.strava.com/oauth/authorize` with `response_type=code`, `approval_prompt=auto`, `scope=activity:write`, a random `state` and `redirect_uri=http://127.0.0.1:<port>/strava/callback`. Check `state`, then POST the client ID, secret and code to `https://www.strava.com/oauth/token` (`grant_type=authorization_code`). Strava's OAuth needs the client secret (it documents no PKCE), so the secret stays on the player's PC. Strava whitelists 127.0.0.1 like localhost, and the IP avoids browsers resolving localhost to IPv6.
- Tokens: access tokens last 6 hours. Refresh with `grant_type=refresh_token` shortly before expiry and always keep the newest refresh token, because Strava rotates them. Send tokens only in the Authorization header (Strava requires headers from 2027). Keep the secret and tokens in `strava.json` under `Paths.user_dir()`, never in logs, telemetry, the relay, crash reports or git. Disconnect calls POST `https://www.strava.com/oauth/revoke` with HTTP Basic auth (client ID and secret) and the refresh token, then deletes them.
- Upload: a multipart POST to `/api/v3/uploads` (build the body for `HTTPRequest.request_raw()`) with `file`, `data_type=fit`, `trainer=1`, `name`, `description` and `external_id` (the ride's UUID), then poll GET `/api/v3/uploads/{id}` every 3 s for up to 2 minutes until it reports `activity_id` or `error`. Treat a duplicate as uploaded, refresh once on 401, back off on 429, and keep failed or offline uploads in `rides/upload_queue.json` for the next launch.
- Defaults: auto-upload is off. The results screen offers Upload to Strava (pedal-scan selectable), and a rider with auto-upload on gets it without a prompt. P1: Rides history with re-upload, and an opt-in import of FTP and weight from GET `/api/v3/athlete` (needs `profile:read_all`).
- Base URLs are settings (`strava_api_base`, `strava_oauth_base`; Strava has announced `https://api-v3.strava.com` from 4 January 2027), and `--strava-base=<url>` points both at the mock.
- Mock (`server/mock_strava`, tests only): zero-dependency Node on `node:http` serving authorize (redirects straight to the callback), token (both grants, rotating refresh tokens, a test clock for expiry), uploads (multipart parsing, a FIT header and CRC check, a processing-then-ready status, duplicates by `external_id`), upload status and revoke, with injectable 401, 429 and 500 responses.

### 3.12 Presentation

- Bright, toy-like low-poly built procedurally (primitives, ArrayMesh, simple shaders, MultiMesh scenery). Riders are stylized rider-on-bike rigs in team colors: in pedal huts cabled to their towers in Siege, in the tank's three seats, and in fighting chairs on the boat. Scrap machines, bosses and big fish are large composite shapes with readable silhouettes. No copyrighted or brand assets, no Wahoo or Zwift logos. If `docs/concept/` holds concept art, match its palette, shapes and mood; it is reference, not shipped content.
- Font: Atkinson Hyperlegible (SIL OFL) if downloadable, else Godot's default. Key numbers ≥ 48 px at 1080p; a colorblind-safe palette; state shown by shape and color.
- HUD: power gauge with target band (glows in band), cadence (with the tension band in fishing), W′ bar, a timeline of waves, stages or fights with a preview of the next one, teammate strip, toasts.
- Audio: CC0 packs if downloadable (credited), otherwise synthesized effects; optional cadence metronome.
- Target 60 fps at 1080p on integrated graphics.

### 3.13 Backlog (P2: design notes only, in `docs/BACKLOG.md`)

Kart Rush (3.10) unless 3.6 selects it, versus tank duels, a fishing tournament (biggest catch in a timed trip), a Siege endless mode, a shared garage and campaign across Siege and Tank Crew, heart-rate strap support and HR-based balancing, a Wahoo Direct Connect (Bluetooth over TCP) backend for KICKR CORE 2, OpenBikeControl input, host migration, a Cloudflare Durable Objects relay, uploads to intervals.icu or Garmin Connect, split-screen with two trainers on one PC.

## 4. Trainer integration

### 4.1 Layers

```
BleTransport (interface)        GdbleTransport | BridgeTransport | (P2) DirconTransport
  FtmsClient                    discovery, subscriptions, control-point queue, parsing
    TrainerDevice (interface)   FtmsTrainer | MockTrainer
      TrainerController         modes ERG / SIM / RESISTANCE / OFF, slew, coalescing
        SafetyGovernor          the only path that can change resistance
          game code             modes, seats and items send EffortDirective requests
```

Telemetry flows up as `TrainerSample {t, power_w, cadence_rpm?, speed_kmh?, flags}`.

Pause never uses `SceneTree.paused` for system nodes. The GDBLE manager, FtmsClient, TrainerController, SafetyGovernor, MockTrainer, NetSession and its transport, the input router and the GestureRecognizer run with `process_mode = PROCESS_MODE_ALWAYS`. Pausing stops the mode's sim clock and puts the trainer at the ERG floor or SIM flat, while telemetry, indications, reconnect and panic keep working. A test pauses the tree and asserts that mock samples and a control-point response still arrive.

### 4.2 Backends

- GdbleTransport (P0): vendor GDBLE (github.com/Fantety/GDBLE; MIT; Rust GDExtension on btleplug 0.12; Windows 10+ x86_64) into `addons/gdble`, pinned by commit with SHA-256 sums. As of 17 Oct 2026 the latest release, v0.5.5, aborts Godot 4.7.2's first headless import on a fresh `.godot` cache (exit 134), so use the prebuilt addon from main (0.6.0, commit 13c49c7 or later) or a newer tagged release that imports cleanly, keep its BUILD_INFO.json, and set `reloadable = false` in `gdble.gdextension`. If main is unusable, use v0.5.5 and run the first import twice, accepting the failed first exit only if `.godot/global_script_class_cache.cfg` exists. Code only against the 0.5.x surface both versions keep. BluetoothManager: `initialize()`, `start_scan(s)`, `stop_scan()`, `connect_device(addr)` (returns a BleDevice; then call `connect_async()`), `get_device(addr)`; signals `adapter_initialized(ok, err)`, `device_discovered(info)`, `device_connected(addr)`, `device_disconnected(addr)`. BleDevice: `connect_async()`, `discover_services()`, `read_characteristic(svc, chr)`, `write_characteristic(svc, chr, data, with_response)`, `subscribe_characteristic(svc, chr)`, `disconnect()`; signals `connected`, `disconnected`, `connection_failed(err)`, `services_discovered(list)`, `characteristic_read(chr, data)`, `characteristic_written(chr)`, `characteristic_notified(chr, data)`, `operation_failed(op, err)`. Never use GDBLE class names as static types (they fail to parse wherever the library isn't loaded): create objects with `ClassDB.instantiate("BluetoothManager")`, hold them as Node or RefCounted and call methods by name, all inside `src/trainer/ble/gdble_transport.gd`. `tests/ble/test_gdble_surface.gd` checks every method and signal above whenever the class exists. Compare UUIDs case-insensitively after expanding 16-bit UUIDs. `adapter_initialized(false, …)` means no adapter; without D-Bus it fails cleanly in about 10 ms. btleplug writes the CCCD as Indicate when a characteristic supports it, so subscribing to 0x2AD9 enables indications. There is no auto-reconnect: implement one.
- BridgeTransport plus `tools/trainer_bridge` (P1): Python 3.12, bleak and websockets; a thin GATT proxy on `ws://127.0.0.1:8765` (JSON: scan, connect, read, write, subscribe, events) behind the same interface. Add a `probe` command that scans for FTMS devices, reads device information, features and ranges, and prints parsed Indoor Bike Data for 30 s. It is read-only unless run with `--allow-control` plus a typed confirmation. Include a PyInstaller spec for a Windows exe; the game can launch it with `OS.create_process`.
- MockTrainer (P0): keyboard control (W and S ±10 W, A and D cadence); scripted profiles (constant, ramp, intervals, noise); and an ERG-follower rider model with compliance %, first-order ERG settling (τ ≈ 2 s, slight overshoot), fatigue from W′ that eventually fails high targets, about 1 Hz notifications with jitter, cadence that lags after sprints, optional dropouts, and a cadence policy (fixed, or tracking a target band with 2 s lag and noise) for the fishing tests. Bots and AI crew reuse this rider model.

### 4.3 FTMS reference

Little-endian. UUIDs are 16-bit on the Bluetooth base UUID 0000xxxx-0000-1000-8000-00805f9b34fb. Keep byte-exact golden vectors in `tests/vectors/ftms.json` and reuse them in the Python tests.

```
Service 0x1826 Fitness Machine
0x2ACC Feature (read): uint32 machine features, uint32 target-setting features
       machine bits: 1 cadence, 7 resistance level, 14 power measurement
       target bits:  2 resistance, 3 power (ERG), 13 indoor bike simulation,
                     14 wheel circumference, 15 spin down, 16 targeted cadence
0x2AD2 Indoor Bike Data (notify): uint16 flags, then fields in bit order
       bit0  More Data, INVERTED: 0 means uint16 instantaneous speed (0.01 km/h) follows
       bit1  uint16 average speed, 0.01 km/h
       bit2  uint16 instantaneous cadence, 0.5 rpm
       bit3  uint16 average cadence, 0.5 rpm
       bit4  uint24 total distance, m
       bit5  sint16 resistance level
       bit6  sint16 instantaneous power, W
       bit7  sint16 average power, W
       bit8  uint16 total energy kcal, uint16 energy per hour, uint8 energy per minute
       bit9  uint8 heart rate, bpm
       bit10 uint8 metabolic equivalent, 0.1
       bit11 uint16 elapsed time, s
       bit12 uint16 remaining time, s
       A record may span several notifications; bounds-check every field.
0x2AD6 Supported Resistance Level Range (read): sint16 min, sint16 max, uint16 step (0.1)
0x2AD8 Supported Power Range (read): sint16 min W, sint16 max W, uint16 step W
0x2AD9 Control Point (write with response + indicate); enable indications FIRST
       0x00 Request Control, must succeed before anything else
       0x01 Reset
       0x04 Set Target Resistance Level: uint8, 0.1 resolution (keep the encoding configurable)
       0x05 Set Target Power: sint16 W                          (ERG)
       0x07 Start or Resume
       0x08 Stop or Pause: uint8, 1 = stop, 2 = pause
       0x11 Set Indoor Bike Simulation: sint16 wind 0.001 m/s, sint16 grade 0.01 %,
            uint8 crr 0.0001, uint8 cw 0.01 kg/m                (SIM)
       Response indication: 0x80, request opcode, result code
            0x01 success, 0x02 not supported, 0x03 invalid parameter,
            0x04 operation failed, 0x05 control not permitted
0x2ADA Machine Status (notify), for example 0x08 target power changed,
       0x12 simulation parameters changed, 0x04 started by user,
       0x02 stopped or paused by user, 0xFF control permission lost
Optional: 0x1818 Cycling Power (0x2A63) as a power fallback; 0x180A Device
Information for diagnostics; 0x180D Heart Rate (P2).
```

### 4.4 Connection flow

Scan (advertised 0x1826, or a name containing KICKR), connect, discover, read features and ranges, subscribe to 0x2AD2 and 0x2ADA, enable indications on 0x2AD9, Request Control, set SIM flat (grade 0), ready. Serialize control-point writes: one in flight, 2 s timeout, two retries. If Request Control fails with 0x05, or status reports 0xFF, tell the player another app (Zwift, the Wahoo app) may hold control. On disconnect, reconnect with exponential backoff (1, 2, 4, 8 s, max 15 s), resubscribe, re-request control and restore the last safe mode. Remember the last device.

### 4.5 Control strategy

- ERG for sustained phases; SIM for racing, sprints and haptics; RESISTANCE only as a P1 fallback.
- KICKR facts to respect: 1800 W max; grade −10% to +16%; ERG takes seconds to settle and can overshoot at high power; bike data arrives about once per second; trainer cadence is an estimate that lags after sprints. Firmware before 1.5.5 could spike to 2000 W when switching between ERG and SIM, so the README recommends current firmware, and before any mode switch the controller first brings the ERG target to the rider's current power or sets SIM grade 0.
- SIM parameters follow the stacking rule in 4.6.6. Defaults: crr 0.004 and cw 0.51 kg/m, both configurable. The game only scales cw relatively (drafting, wind haptics); game physics uses its own CdA.
- Coalescing: at most 2 control writes per second; drop superseded commands; always send the newest.
- Virtual gears (P0, for single-speed Zwift Cog riders and useful with a cassette): 24 gears on shift_up and shift_down. Implement each gear as a grade offset in SIM, tuned so one step changes resistance at constant flywheel speed by about 6–8%; show the gear on the HUD and document the approximation. Zwift Click shifting itself works only inside Zwift.
- Cadence: use FTMS cadence when present; estimate it from speed when absent or stale (learn the speed-to-cadence ratio while both are valid, or run a 10 s calibration at 90 rpm). Gestures in ERG use relative speed change, which needs no calibration.

### 4.6 Safety governor (P0, every rule unit-tested)

1. ERG clamps: floor max(30% FTP, 50 W); absolute ceiling min(150% FTP, 1000 W, the trainer's Supported Power Range max). Duration limits count time with the applied target above 105% FTP (300 s) and above 120% FTP (60 s). When a limit is reached, the ceiling drops to that band and stays there until the applied target has been ≤ 90% FTP for 120 s, which resets both counters. Phases longer than 300 s cap at 105% FTP. While FTP is unverified, every ERG target is multiplied by 0.85. The FTP test's ramp_test profile (3.2, P1) is the only exception to the duration limits, the 150% cap and the unverified factor. Sprints happen in SIM.
2. Slew: increases at most 30 W/s; decreases immediately.
3. Rescue: in ERG with a target ≥ 60% FTP, if cadence < 45 rpm for 3 s or power < 75% of the applied target for 5 s, drop to 50% FTP, show "rescue", hold until cadence ≥ 70 for 3 s, then ramp back over 10 s. Rescue state goes out in telemetry. Modes treat rescue as a stagger, never a wipe.
4. Coasting: `not_pedaling` (3.5) for 3 s drops ERG to its floor; after 10 s, pause (solo) or mark AFK (multiplayer).
5. Panic: `SafetyGovernor.emergency_safe()` turns ERG off and sets SIM grade 0 and wind 0 immediately; the trainer stays safe until the player resumes.
6. SIM stacking: base grade = (course grade + mode grade) × difficulty (default 50%) + virtual-gear offset, clamped to the user's range (default −5% to +10%). Mode grade (the loader's spring in Tank Crew) is not a haptic. Haptic grade (hits on the tank, a fish's last runs, Kart items) × the intensity setting adds at most +3% for at most 8 s, with a 15 s cooldown per receiver; haptic wind is limited so its added force at the current speed is no more than that of +3% grade. Haptics are off during warm-up and for riders who opted out. The total is clamped to −10% … +16%.
7. The network never sends device commands. Hosts send EffortDirectives; each client validates and clamps them locally and reports what it applied.
8. Warm-up: the first 5 minutes of riding, counted from the first pedal stroke after the trainer connects, and reset after 20 minutes without pedaling. During it, ERG targets stay ≤ 65% FTP, SIM grade stays within −2% … +3%, and haptics are off. Autopilot never skips it; a player may skip it in settings. Every mode opens with warm-up content (Siege's warm-up wave, the tank's garage drive-out, the boat ride out, the Kart roll-out, the FTP test's ramp-in).
9. On exit, crash paths and disconnect: try SIM flat, then Stop (0x08 0x01).
10. Tests use MockTrainer only, and the hardware lock (section 1) blocks control writes in every process this run starts.
11. Structure: only SafetyGovernor holds TrainerController; only TrainerController calls TrainerDevice setters; only FtmsTrainer calls `FtmsClient.write_control()`. `tests/arch/test_no_bypass.gd` scans `res://src` and fails on any other call site of `write_characteristic`, `write_control`, `set_target_power`, `set_simulation` or `set_resistance`.

### 4.7 Hardware test plan

Write `docs/HARDWARE_TEST_PLAN.md`: a checklist for me with the real trainer (probe, connect, read-only data, SIM flat, ERG 100 W, slew, rescue and panic checks, each mode for 5 minutes, two-PC multiplayer, disconnect and reconnect, and one real Strava connect and upload that should appear as a Virtual Ride with power and cadence), with expected results and a log template.

## 5. Multiplayer

### 5.1 Model

Star topology through a relay. The host's game is authoritative and simulates at 20 Hz. Clients send telemetry and intents; the host sends snapshots, events and effort directives. Fitness pacing tolerates 100–200 ms of latency, so clients predict their own rider locally and reconcile softly toward the host.

### 5.2 Room codes

Six characters from the Crockford Base32 alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, displayed as `K7Q-X2M`. Input is case-insensitive and maps O to 0 and I or L to 1. The relay generates codes; in P1 a host may request their previous code if it is free.

### 5.3 Relay server (`server/relay`, P0)

Node.js 22.12+ (whatever is on PATH), TypeScript, no database. Prefer the `ws` package; if `npm install` fails, implement the server with zero dependencies on `node:http` upgrade plus `node:crypto` (RFC 6455 handshake; text, close, ping and pong frames; client masking; 16 KB maximum payload; no extensions). Run TypeScript with Node's built-in type stripping using only erasable syntax (no enums, namespaces or parameter properties; add `--experimental-strip-types` on Node 22.12–22.17). Test with `node:test` and Node's global WebSocket client. `GET /health`, WebSocket at `/v1`, default local URL `ws://localhost:8787/v1`.

```
-> {"t":"hello","proto":1,"game":"wattlands","build":"0.1.0"}
-> {"t":"create","max":8}
<- {"t":"created","code":"K7QX2M","peer":1,"token":"..."}
-> {"t":"join","code":"K7QX2M","token":null}
<- {"t":"joined","peer":3,"host":1,"token":"..."}
<- {"t":"error","code":"room_not_found|room_full|version_mismatch|rate_limited|bad_request"}
-> {"t":"msg","to":1,"d":{...}}        to: a peer id, the host id, or 0 for everyone
<- {"t":"msg","from":3,"d":{...}}      non-hosts may only send to the host
<- {"t":"peer_joined","peer":3}
<- {"t":"peer_left","peer":3,"reason":"..."}
<- {"t":"host_left"}
-> {"t":"ping","ts":123}   <- {"t":"pong","ts":123}
```

Limits: 8 peers per room, 16 KB per message, 60 messages/s per peer (burst 120), 60 s idle timeout (clients ping every 15 s), 10 join attempts per minute per IP, 4 h room lifetime. `to: 0` means everyone except the sender. A reconnect token stays valid for 120 s and keeps the same peer id; clients save it in their profile dir. When the host's socket drops, the relay sends `peer_left` for peer 1 with reason "dropped" and holds the room for 120 s; `host_left` goes out only on an explicit leave or when the host's token expires. Ship a Dockerfile, a README and tests for create, join, leave, broadcast, limits, reconnect, host drop, host_left and malformed input; example `fly.toml` and `render.yaml` are P1.

### 5.4 Godot networking (`src/net`)

`Transport` interface: signals `connected`, `disconnected(reason)`, `peer_joined(id)`, `peer_left(id)`, `message(from, data)`; methods `host()`, `join(code)`, `send(to, data)`, `poll()`. Implementations: RelayTransport (WebSocketPeer; ws or wss URL from settings or `--relay`), LoopbackTransport (tests, P0), LanTransport (P1: the host serves the same relay protocol on a local WebSocket server, plus UDP broadcast discovery). A `NetSession` autoload owns lobby state, roles, routing, clock offset (from ping), snapshot buffers and reconnect.

### 5.5 Game messages (inside `d`)

- `player_info` (client to host): name, color, FTP, weight only if opted in, Autopilot flag.
- `lobby_state` (host to all): players, trainer status, ready flags, mode, scaling, settings.
- `telemetry` (client to host, 5 Hz): t, power, cadence, speed, effort, p_eff_w, W′bal, applied_target_w, clamped_by, rescue, seconds left above 105% and 120% FTP, gestures, intents.
- `snapshot` (host to all, 10 Hz): compact mode state.
- `event` (host to all): phase changes, hits, damage, results.
- `directive` (host to one client): EffortDirective {mode, target_pct or target_wkg or target_w, mode_grade, haptic, crr, cw, duration_s, reason, source}.

`Protocol.decode()` converts peer, host, from, to, seq, proto, max and every `*_id` field to int (Godot's JSON parser returns every number as a float) and rejects any message that fails its schema. Dictionaries are keyed by int peer id, and protocol tests round-trip through `JSON.stringify` and `JSON.parse_string`. Version every schema and show a clear error on mismatch. Players ready up with `pedal_start` or confirm. If the host leaves, end the session gracefully (host migration is P2).

## 6. Project structure, ownership and conventions

```
project.godot          autoloads, input map, main scene, renderer           lead (W0, W2)
docs/BRIEF.md          this brief, verbatim                                 lead (W0)
src/contracts/         interfaces, data types, EventBus signals             lead; frozen after W0
src/core/              app state machine, Paths, profile, settings,
                       scaling, command line                                platform
src/trainer/           FTMS codec, FTMS client, MockTrainer                 trainer-core
src/trainer/control/   controller, safety governor, cadence, virtual gears  trainer-control
src/trainer/ble/       GDBLE and bridge transports, connection manager      ble
src/sim/               sim clock, physics, speed model, W' balance, bots,
                       gestures                                             sim
src/net/               transports, NetSession, lobby, codes, protocol       net-client
src/rides/             ride recorder, FIT encoder, Strava client, queue     rides
src/combat/            enemies, paths, health, projectiles, waves,
                       spawners                                             combat
src/world/             terrain, paths, water, riders, cameras, scenery,
                       VFX, audio                                           world
src/ui/menus/          menus, first-run flow, settings (incl. Strava),
                       lobby, code entry, results, pedal-scan component     ui-menus
src/ui/hud/            HUD widgets, input router, bindings                  ui-hud
src/modes/fishing/ and content/fishing/                                     mode-fishing
src/modes/siege/ and content/siege/                                         mode-siege
src/modes/tank/ and content/tank/                                           mode-tank
src/modes/kart/ and content/kart/ (only if 3.6 selects it)                  mode-kart
content/strings/<module>.csv                                                each owner
addons/                gdble and gut, vendored in W0                        lead
server/relay/          Node relay                                           relay
server/mock_strava/    Node mock of Strava OAuth and uploads (tests)        rides
tools/godot.*, tools/env.*, tools/run_tests.*, tools/check_scripts.gd       lead (W0)
tools/trainer_bridge/  Python bridge and probe                              ble
tools/fit_check/       FIT decoder check (Node, @garmin/fitsdk)             rides
tools/e2e/             multiplayer harness (Node)                           qa
tests/                 unit, simulation, arch, vectors                      each owner, qa
.github/workflows/<owner>.yml                                               each owner
docs/decisions/, docs/deps.d/, docs/credits.d/, docs/changelog.d/           each owner, append only
docs/concept/          concept art from me, reference only                  read only
docs/                  DESIGN, ARCHITECTURE, PROTOCOL, TRAINER, HARDWARE_TEST_PLAN,
                       DECISIONS, BACKLOG, DEPENDENCIES, OWNERSHIP          lead (merges fragments)
CLAUDE.md, README.md, CREDITS.md, CHANGELOG.md, LICENSE (MIT)               lead
```

Conventions:

- Static typing everywhere except GDExtension classes (4.2). Game rules are pure classes with `step(state, inputs, dt)`; the sim always advances in fixed 0.05 s steps; RNG is seeded.
- Content is JSON, validated at load. No editor-only APIs at runtime. EventBus signals instead of cross-module node paths. Unique `class_name`s. User-facing strings live in `content/strings/<module>.csv`, all loaded as translations.
- Every persisted file (profile, input.cfg, last device, recent rooms, reconnect token, rides and FIT files, the upload queue, Strava settings and tokens) goes through `Paths.user_dir()`, which honours `--profile-dir=<abs path>`. Tests use a fresh temp dir; the end-to-end harness gives each peer its own.
- System nodes run with `process_mode = PROCESS_MODE_ALWAYS` (4.1).
- Agents never edit README, CHANGELOG, `.gitignore`, `project.godot`, contracts or another module's files; they write fragments and request changes in their report.
- Put these conventions and the test-harness rules from section 7 in `CLAUDE.md` in W0, and repeat the relevant parts in every agent prompt.

Command-line flags (after `--`, read with `OS.get_cmdline_user_args()`): `--mock-trainer=<profile>`, `--autopilot`, `--host`, `--join=<code>`, `--relay=<url>`, `--mode=<siege|tank|fishing|kart>`, `--content=<id>`, `--seed=<n>`, `--sim-speed=<x>`, `--run-seconds=<n>`, `--report=<path>`, `--screenshot-dir=<dir>`, `--profile-dir=<abs path>`, `--strava-base=<url>`. `--sim-speed` runs x fixed 0.05 s steps per 0.05 s of wall time and never touches `Engine.time_scale`; don't confuse it with Godot's own `--time-scale`, which changes dt. Headless simulations call `step()` in a loop; networked runs always use `--sim-speed=1`.

## 7. Testing and verification gates

Test-harness rules (also in `CLAUDE.md`): never pass `-d` or `--debug` to an automated Godot run (a script error then hangs at the debugger prompt or exits 0); close stdin and wrap every run in a timeout. Unit tests use GUT 9.7.1, the release for Godot 4.7.x: `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=build/junit.xml`. `tools/run_tests` passes only if the exit code is 0, "Run Summary" appears in the log, the JUnit test count is above 0 and at least the previous green count, and the log contains none of "SCRIPT ERROR", "Parse Error", "Debugger Break", "Ignoring script" or "Nothing was run". GUT fails a test on any unhandled `push_error`, so tests of code that rejects bad input use `assert_push_error()`, and expected non-fatal conditions (such as no Bluetooth adapter) use `push_warning`.

1. Unit: FTMS parse and encode vectors, every governor rule (including duration-limit latching and reset, warm-up and the ramp_test profile), slew, rescue, the hardware and network locks, the no-bypass scan, W′bal, the speed integrator against the bisection oracle, scaling modes, gestures and their arbitration, haptic stacking, Siege routing and the spark economy, the tank's seat models (accumulator, spring energy, shell ballistics), the fishing tension model and its meters, the shift, mission and species schemas, the FIT encoder (CRCs, message layout, timestamps), Strava OAuth, token rotation and the upload queue, room-code utilities and protocol round trips. If 3.6 selects Kart Rush, add drafting and the track schema.
2. Static: `tools/godot.sh --headless --path . -s tools/check_scripts.gd` loads every .gd under `src/`, `tests/` and `tools/` and fails if any load returns null or `can_instantiate()` is false. Then gdlint and gdformat --check if Python is available.
3. Simulation: each P0 mode runs headless with bots and MockTrainer through its reference content at a high `--sim-speed`, with assertions. Siege: a compliant team with Autopilot routing finishes the Short shift with at most one Blackout, and a 0 W team blacks out in the first full wave. Tank: a compliant crew finishes Scrapyard Run within 40 minutes of sim time, and a 0 W crew never reaches the first checkpoint. Fishing: a mock rider tracking the band lands the reference tuna inside its fight window, one held 10 rpm below the band snaps the line, and one held 10 rpm above it loses the fish. Rescue triggers on cadence collapse in every ERG phase type, warm-up limits hold in every mode, and pausing the tree doesn't stop trainer I/O. The FTP test (P1) estimate lands within 3% of 0.75 × the mock rider's analytic best 1-minute power under its protocol, and within 10% of its CP for CP 150–350 W and W′ 15–25 kJ.
4. Rides: every simulation run writes a FIT file that `tools/fit_check` decodes with zero errors, valid CRCs, sport cycling and sub_sport virtual_activity, one record per second (within 1%) and session totals equal to the recorder's. Against `server/mock_strava`, the Strava client completes connect, upload, polling, refresh with rotation, duplicate handling and recovery from 401 and 429, and a test asserts that no request leaves loopback while `WATTLANDS_NO_NETWORK_INTEGRATIONS=1`.
5. Relay and mock Strava: their Node test suites.
6. End-to-end: `tools/e2e/run.mjs` (stdin ignored, timeouts, `WATTLANDS_NO_HW_CONTROL=1` and `WATTLANDS_NO_NETWORK_INTEGRATIONS=1`) starts the relay, the mock Strava server, one host and two clients headless with mock trainers, Autopilot, separate `--profile-dir`s and `--sim-speed=1`. It plays each P0 mode's e2e content (about 2 minutes each: a Siege wave, a three-seat tank stage, one scheduled fish per rider), then asserts the same event sequence on all peers, final mode state within tolerance, every directive clamped, no script errors, no desync warnings, a valid FIT file per peer for each mode played, exactly one mock upload from the peer set to auto-upload, and a working reconnect after one client is killed and restarted. One full run takes 12 minutes or less.
7. Visual (P1): screenshots of the title, lobby and each mode's HUD; look at the PNGs yourself and fix readability problems.
8. CI: one workflow per owner under `.github/workflows/`, together running unit, static, simulation, rides, relay and end-to-end tests on Linux.
9. Windows: `export_presets.cfg` with a Windows Desktop preset that ships the GDBLE DLL (P0). Producing and smoke-running a build in `build/windows/` is P1 and needs downloadable export templates; otherwise document the steps.

## 8. Orchestration with dynamic workflows

Run these back to back without waiting for me. Use Opus 5.5 for every agent. Never let two agents edit the same file in parallel; shared files change only in W0 and W2, and only by you. Every Godot run goes through the `tools/godot.sh` lock, so parallel agents queue for Godot instead of exhausting memory.

1. W0 Foundation (you, mostly sequential): bootstrap and the tools in section 2; commit this brief verbatim as `docs/BRIEF.md`; write `project.godot` with every autoload registered (each pointing at a stub its module fills in; names never change), the full input map with the defaults from 3.5, and the main scene; create the folder tree, `.gitignore`, `.gdignore` files and `CLAUDE.md`; write the contracts (interfaces, data types, EventBus signals, message schemas, the combat and ride-recorder APIs) with doc comments. Ship tested real implementations, not stubs, of the shared pure logic: the sim clock, seeded RNG, W′ balance, effort scaling, the speed step, the governor's absolute clamps, and a MockTrainer with constant and ramp profiles and a τ = 2 s ERG follower. Vendor GUT 9.7.1 and GDBLE (4.2). Add `tools/run_tests`, `tools/check_scripts.gd`, the hardware and network locks, the fragment folders and `docs/OWNERSHIP.md`. Commit and tag `w0-foundation`.
2. W1 Build (parallel fan-out, 16 agents, one isolated copy each): trainer-core, trainer-control, sim, ble, relay, net-client, rides (recorder, FIT, Strava client, mock server, fit_check), combat, world, ui-menus, ui-hud, platform, one agent per P0 mode in 3.6 (mode-fishing, mode-siege, mode-tank), and qa (scenario runner, end-to-end harness, screenshot tool, fallback FIT decoder). Use the runtime's isolated copies if offered; otherwise each agent runs `git worktree add` on its own branch from `w0-foundation`. Every agent prompt names the BRIEF sections to read first, the paths it owns, the contracts it uses, the exact test command and the report format. Agents implement only their own paths, adapt to an imperfect contract inside those paths, write and run their tests plus `check_scripts`, commit, and return `{branch, base_sha, head_sha, summary, files, tests_added, test_command, tests_total, tests_failed, junit_path, script_check_ok, open_issues, contract_change_requests: [{file, change, additive, blocks_p0}], project_needs: [autoloads, actions, settings]}`. You re-run each test_command before accepting a report.
3. W2 Integrate (you plus up to 3 helpers): accept additive contract changes, and breaking ones only when they block P0. Merge in this order, running the full suite after each merge: contracts, platform, trainer-core, trainer-control, sim, ble, relay, net-client, rides, world, combat, ui-hud, ui-menus, the mode agents in 3.6 order, qa. Merge the doc fragments and wire scenes and menus end to end. Then loop: run every gate in section 7 and fix failures. Progress means the count of failing checks went down; stop after two rounds without progress or five rounds in all.
4. W3 Review (parallel fresh-context reviewers, then verifiers), one reviewer per dimension: FTMS and Bluetooth against 4.2–4.4; the safety governor and every path that can command the trainer (any bypass is a blocker); network robustness; each P0 mode against its section, including its effort plan and zero-input path; profile flows; rides, FIT validity and the Strava flow, where any token or secret in logs, telemetry, the relay or git is a blocker; zero-input completeness and HUD readability; Windows packaging and README accuracy; code quality and test gaps. Each finding carries severity, file and line, evidence, and a failing test, a repro command or, for architecture and safety findings, a static test. A separate verifier confirms each finding before anyone fixes it. Safety findings that need hardware go into `docs/HARDWARE_TEST_PLAN.md` rather than being dropped; Windows-only findings stay listed as unverified unless Windows is available; drop only what the verifier refutes.
5. W4 Fix and polish (parallel fixers grouped by area, then you), at most two rounds: fix confirmed findings with tests, rerun every gate, take final screenshots, finish the docs, merge the changelog fragments and tag `v0.1.0`.

## 9. Definition of Done and final report

- Every P0 item is implemented, reachable from the menus and covered by tests. Every gate in section 7 is green (hardware excepted), or listed as known failing in the final report with no threshold or assertion weakened.
- A new player can create a profile, connect a mock or real trainer, host a room, share the code, let a friend join, and play every P0 mode in 3.6. Solo play and hosting work with zero input; a joining friend types only the code.
- Every ride is saved as a FIT file that passes `tools/fit_check`, and a rider who connects Strava can upload it from the results screen. Uploads are verified against `server/mock_strava`; no automated run contacted the real Strava API, and the first real upload is a step in `docs/HARDWARE_TEST_PLAN.md`.
- Every safety-governor rule, the hardware and network locks and the no-bypass scan are tested.
- The relay runs locally with one command. The Dockerfile is provided and built only if a Docker daemon was available; otherwise it is marked unverified.
- Docs are complete: README (player quick start, controls, BikeControl tip, Strava setup with the API app, callback domain `localhost` and the athlete limit for new apps, and troubleshooting: close other apps holding control, update trainer firmware for FTMS and safe mode switches, remove any Windows-level pairing of the trainer if connecting fails), DESIGN, ARCHITECTURE (with a mermaid diagram), PROTOCOL, TRAINER, HARDWARE_TEST_PLAN, DECISIONS, BACKLOG, DEPENDENCIES and CREDITS, and CLAUDE.md.
- Final report in chat: what was built, every gate's result with numbers, what is untested on hardware, on Windows or against the real Strava API, the top risks, and the exact commands to run the game, the tests, the relay and the mock Strava server.
