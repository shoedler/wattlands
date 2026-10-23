# Generator Siege: real-trainer checklist

The game's own checklist for a real KICKR CORE (BRIEF 4.7). `docs/HARDWARE_TEST_PLAN.md` holds the firmware notes, the panic and stop advice and the log format, and links here. Nothing here ran during the build: every automated run used MockTrainer with the hardware lock set. Work through the platform plan's "Before you start", probe, connect, SIM flat, ERG, slew, rescue, coasting and panic, and mode-switch steps first, and stop at the first failed safety check.

Siege sends no haptics, mode grades or ERG target changes. Its plans are all ERG, and the one directive it ever sends is a 30 s SIM block, `{mode: SIM, duration_s: 30, reason: "overdrive", source: "siege"}` (Overdrive). So the things to confirm on a trainer are: the wave targets and their slews, the duration-limit counters across breaks, that one SIM block and its two switches, rescue, coasting and AFK, panic, and the FIT and Strava output. Items 10 and 11 need a Windows PC but not the trainer.

## 0. Setup

- [ ] Drop the locks only by hand, as the platform plan says. From source, PowerShell: `tools/godot.ps1 --allow-hw --timeout=14400 --path .`; Git Bash: `tools/godot.sh --allow-hw --timeout=14400 --path .` (without `--timeout` the wrappers stop a run after 20 minutes). `--allow-network` only for the Strava step (section 9). An exported build never sets the locks. Never pass these flags from an automated run.
- [ ] KICKR CORE, current firmware (before 1.5.5 it could spike on mode switches). Close Zwift and the Wahoo app. Know how to stop: hold Backspace for 1 s (panic), or stop pedaling.
- [ ] Set your FTP in the profile. Do the whole checklist once with it **verified** (a test result) and run steps 2 and 3 again **unverified**: waves then run at 0.85 x the planned target.
- [ ] Targets used below, at an example FTP of 250 W (scale to yours). The unverified column is 0.85 x the verified one:

| Content | Wave | Planned % FTP | Watts at FTP 250 | Unverified % | Unverified watts |
| --- | --- | --- | --- | --- | --- |
| `short` | 300 s | 95 | about 238 | 80.75 | about 202 |
| `vo2` | 120 s | 112 | 280 | 95.2 | about 238 |
| `sweetspot` | 900 s | 90 | 225 | 76.5 | about 191 |
| `endurance` | 2700 s | 70 | 175 | 59.5 | about 149 |

Every shift starts with the warm-up wave (300 s, 50% ramping to 65%) and a 120 s build break at 50%, so the first wave starts at 420 s. Breaks are 50% (sweetspot's 55%). The platform then appends a 180 s cool-down at 50%.

- [ ] Start Siege solo from the picker with the trainer connected. The wave offset (lobby card) is 0 unless a step says otherwise. Use `short` unless a step names another content.

## 1. Warm-up wave

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 1 | Start `short` and pedal from 0:00 | The warm-up banner shows. ERG ramps from 50% to 65% FTP over 300 s (125 W to about 162 W at FTP 250), rising smoothly, never above 65%. Raiders only for the first 180 s, one teaching toast a minute | |
| 2 | During the warm-up press `ability_1` (and do a surge gesture) | Nothing happens on the trainer: no switch to SIM, no gear indicator, no sprint band, no Overdrive toast (the rules refuse it outside a wave). No SIM and no haptics in the first 300 s | |
| 3 | At 5:00 the build break starts | ERG 50% (125 W at FTP 250), the shop opens with a countdown over its last 10 s, your output goes to the generator | |

## 2. Each wave at its ERG target

Run the content, wait for the first wave and compare the trainer's power (and the HUD's target) with the table in section 0.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 4 | `short`, wave 1 (7:00) | ERG 95% FTP (about 238 W at 250), rising from the break's 50% at no more than 30 W/s, decreases at once. Holds within about 5% at steady cadence. No duration-limit clamp (95% is under the 105% band) | |
| 5 | `short` unverified | Wave 1 at 80.75% of FTP (about 202 W at 250). This is the unverified-FTP 0.85 factor, which has only run against MockTrainer: log whether the trainer's target is 0.85 x 95% and that the factor only lowers it | |
| 6 | `vo2`, wave 1 | ERG 112% (280 W at 250), 120 s. Unverified: 95.2% (about 238 W) | |
| 7 | `sweetspot`, wave 1 | ERG 90% (225 W at 250), 900 s. Unverified: 76.5%. Phases over 300 s stay at or under 95% | |
| 8 | `endurance`, the wave | ERG 70% (175 W at 250) for 45 minutes. Rushes at 8, 16, 24, 32 and 40 minutes into the wave do not change the target. Unverified: 59.5% (about 149 W): below the 60% rescue threshold, so rescue is not armed in this wave; run the rescue steps (24 to 26) on another content | |
| 9 | Wave offset +5 and -10 on `short` (lobby card) | Wave targets 100% and 85%; the offset changes WORK targets only, never the warm-up or the breaks | |

## 3. The 50 to 117% step in `vo2`

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 10 | `vo2`, wave offset +5, FTP 400 (verified), the break-to-wave boundary at 7:00 | The target steps from 50% (200 W) to 117% (468 W). The slew rises 30 W/s, so the trainer takes about 9 s (268 W / 30 W/s) to reach 468 W. The wave clock does not wait for it. Decreases at the wave's end are immediate. At offset 0 the step is 200 to 448 W, about 8 s. If your FTP is lower, the step is smaller and quicker; log what you used | |
| 11 | Look for a spike or a clamp at the top | No overshoot above 468 W beyond the trainer's own ERG settling, no "limit" banner (117% is under the 120% band, so only the 105% band counts) | |

## 4. Breaks reset the duration counters

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 12 | Ride all six `vo2` waves at offset 0 (112%) and then at +5 (117%), with the full 180 s of every break at 50% | Six 120 s waves add up to 720 s above 105%, which would hit the 300 s limit in wave 3 if the counters did not reset. They reset because each break spends 180 s at 90% or less (the rule needs 120 s). Expected: waves 3 to 6 are as strong as wave 1, with no duration-limit clamp and no banner. Log the duration-limit readout if the HUD shows one | |
| 13 | In `short` (95%, never above 105%) ride the whole shift | No counter runs and nothing clamps | |

## 5. Overdrive: the ERG, SIM, ERG switch

Overdrive starts with `ability_1`, the HUD button, or a surge gesture while the prompt shows (your tower has an enemy in range, or a rush is on). It needs a wave with at least 30 s left, no rescue and a pedaling rider. After it ends the cooldown is 90 s. Use `short` (5-minute waves) and a verified FTP. Log the trainer's power with a recording or by eye at 1 s resolution around each switch.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 14 | Mid-wave, at least 30 s after any other ERG/SIM change, ride steady on the ERG target and press `ability_1` | Entry: ERG at min(applied target, your 3 s power), then SIM grade 0 and wind 0, then the stacked SIM state, in separate control writes. No power spike on any of the three. The toast "Overdrive! Sprint for 30 s" shows. The gear indicator appears. The power gauge shows the sprint band at 1.2 to 1.4 x FTP (300 to 350 W at FTP 250) | |
| 15 | During the block, shift virtual gears up and down | In SIM the grade is 0 and only the gear offset applies. Each shift changes the resistance by roughly 6 to 8% near 30 km/h. The grade never shows a hill or a haptic | |
| 16 | Sprint inside the band (at or above 1.2 x FTP) for 10 s or more | Raw power at or above FTP doubles your routed output (the towers fire faster, the drum shows it). At the end, "Overdrive sprint scored!" | |
| 17 | The 30 s block ends while you keep sprinting hard | Return: SIM flat, then ERG at min(your 3 s power, the planned target), never above the planned target (a sprint above the target returns at the target itself), then a slew up at 30 W/s if it started lower. No spike and no jump above the 95% target | |
| 18 | Repeat, but ease off to about 50% FTP in the last 3 s of the block | ERG resumes near your easier power (at the 3 s mean) and then slews up to the target at 30 W/s, not at once | |
| 19 | Try `ability_1` again right away | Refused for the 90 s cooldown (the button shows the cooldown). The next start is at least 30 s after the return to ERG, which the cooldown guarantees | |
| 20 | Start an Overdrive in the last 31 to 35 s of a wave (the earliest it is allowed is with 30 s left), so the block ends on the wave boundary into the break | The phase change ends it: an Overdrive end event, the 90 s cooldown from that moment, and the trainer returns SIM to ERG at the break's 50% target (125 W at 250) with no spike, slewing as needed. Then the break runs normally and the shop opens. In the next wave Overdrive is ready again | |
| 21 | Press `ability_1` with under 30 s of a wave left | Nothing happens: no switch on the trainer and no toast (the rules refuse it as too late) | |
| 22 | Two PCs: PC A hosts `short`, PC B (its own trainer) joins by code. On PC B press `ability_1` | The host accepts, the directive reaches B's governor, which applies SIM; the acknowledgement returns on B's next telemetry. Expected: B's trainer is in SIM within about 1 s of the press, B's gauge shows the sprint band (published from the Overdrive event). If B's governor refuses (for example the 30 s switch spacing), Overdrive is cancelled with a 30 s retry and the refusal toast shows on B only. The trainer on A is unaffected. B returns to ERG with no spike | |
| 23 | A bot rider in the session | Bots never use Overdrive | |

## 6. Rescue in a wave

Use a content and FTP where the wave target is at least 60% after the factor (`short`, `vo2`, `sweetspot`, verified or not; not unverified `endurance`).

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 24 | In a wave, drop cadence below 45 rpm for 3 s | The target drops to 50% FTP, the rescue banner and a "The workers stumble: spin back up" toast show, the wheel's workers stumble, and Overdrive is unavailable. Output still counts at your actual P_eff. The plan clock and the wave keep running | |
| 25 | Press `ability_1` during rescue | Nothing: no SIM block, no gear indicator | |
| 26 | Hold 70 rpm or more for 3 s | The target ramps from 50% back to the wave target over 10 s at no more than 30 W/s. Overdrive becomes available again once rescue ends and its cooldown is clear | |

## 7. Coasting and AFK

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 27 | Stop pedaling in a wave, solo | After 3 s the target falls to the floor (the larger of 30% FTP and 50 W). After 10 s the session pauses (pause screen, enemies stop, ERG floor). Pedal again to resume; ERG climbs from the floor at 30 W/s | |
| 28 | Two PCs: stop pedaling on PC B in a wave | B's trainer floors at 3 s. At 10 s B is marked AFK: B's wheel stops, "Your wheel stopped" shows on B, the game does not pause (log how A's HUD shows B's wheel stopped). B's routing, denarii and share of the threat budget are kept (the wave does not get easier). A running Overdrive of B ends. Pedal again: AFK clears and ERG climbs from the floor | |
| 29 | Stop pedaling during a break | The floor after 3 s; solo pauses and multiplayer marks AFK at 10 s as in a wave | |

## 8. Panic during Overdrive

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 30 | Start an Overdrive, then hold Backspace for 1 s (or View + Menu, or the on-screen PANIC button) | ERG is off and the trainer is at grade 0, wind 0, at once (under 1 s). The trainer stays safe until you resume. Log what Siege's HUD shows for the Overdrive (the rules end it on a rescue, AFK or phase change, not on panic; its clocks keep running) | |
| 31 | Resume | The next ERG command enters at the floor and slews up at 30 W/s. No spike. The game continues and the next wave's target is normal | |
| 32 | Panic during a plain ERG wave | ERG off and SIM flat at once; resume as in step 31 | |

## 9. Cool-down, FIT and Strava

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 33 | Finish a shift | The 180 s cool-down runs at 50% FTP (nothing spawns, the shop and Overdrive are closed, the workers march). The results screen shows the grade, score, Breaches, gate HP per wave and per-player stats; the first ride unlocks the swallowtail pennant at 100 XP | |
| 34 | `node tools/fit_check/check.mjs <the FIT in your rides folder> --expect-laps=<n>` | Laps are the lap-true phases plus the cool-down: `short` 8, `vo2` 14, `sweetspot` 6, `endurance` 4, `drill` 3. The laps are named like "Warm-up wave", "Build break", "Wave 1", "Break 1". Power, cadence and the lap boundaries match the ride | |
| 35 | Upload to Strava (`--allow-network` with your own API app, platform plan section 12) | A Virtual Ride with power and cadence and the same laps | |

## 10. Frame time on an integrated-graphics Windows PC (G3)

The 60 fps goal at 1080p (16.7 ms per frame) was never measured: headless runs have no renderer. Use a PC with integrated graphics, a 1920 x 1080 display, and the Compatibility renderer the project uses. No trainer or lock flag is needed.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 36 | Stress scene, 150 enemies, 8 towers, 4 wheels: `tools/godot.ps1 --timeout=300 --path . res://tests/games/siege/perf/stress_scene.tscn -- --stress-seconds=60` (Git Bash: `tools/godot.sh ...`) | The log prints the mean and 1%-low frame time against 16.7 ms, the draw calls (budget 250) and triangles (budget 400k). Pass: mean and 1%-low at or under 16.7 ms. Log all four numbers and the GPU | |
| 37 | A real 4-rider session: host `vo2` or `short` with three bots (or friends), at 1080p, mock or real trainers, watching a mid-wave and a rush or ram push with many enemies | No stutter at wave starts, the ram push or a Breach. Log the stress scene's numbers again if you can, or the on-screen frame time. Note any dropped frames | |

## 11. Listening check of the synthesized audio (G3)

All sounds are synthesized with `Sfx.synth` and were never heard on speakers. Use normal listening volume.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 38 | Spin up and slow down on the generator | A wheel creak and a generator hum that both rise in pitch with your watts (creak with the mean rider P_eff, hum with the team watts) and stop when nobody pedals. Neither loop is harsh, buzzy or clipping | |
| 39 | Towers firing: Ballista, Scorpion, Caltrop thrower | Three distinct shots (a low thump, a quick click, a soft throw); at most 4 shots sound per frame, so a busy defence does not smear into noise | |
| 40 | Horsemen, a ram at the gate, gate hits, a Breach | Hooves are audible but quiet; the ram is a slow low knock about every second; gate hits scale with the damage; a Breach is a clear boom | |
| 41 | A wave start, a road rotation (needs fewer than 3 riders), a rush | A horn at every phase change into a wave after the first one (the warm-up's start is silent); readable, not startling. A road rotation shows the "Horns!" toast but the audio module plays no horn for it: log whether you miss that (brief 2.4 says a 5 s horn) | |
| 42 | Earn denarii (generator or kills) | A coin sound each time your own denarii count goes up, at most about 3 a second, not tiring over a long shift | |
| 43 | Overall mix | Nothing drowns the others at normal volume; the loops stay under the effects | |

## Log template

Copy this block for every step.

```text
Step:
Date and time:
Trainer model / firmware:
Command:
Content / players / bots / wave offset:
FTP / verified or not:
Expected:
Observed (power, cadence, target, timings):
Pass / fail:
Notes (screenshots, spikes, anything unexpected):
```

Log: date, trainer firmware, FTP, verified or not, and each step's result. Stop at the first failed safety check (a power spike on a mode switch, an ERG step faster than 30 W/s, panic slower than 1 s, or a wave target above its table value) and report it.
