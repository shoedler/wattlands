# Castellum Rotae: real-trainer checklist

The game's own checklist for a real KICKR CORE (BRIEF 4.7), for v2 (version 0.3.1). `docs/HARDWARE_TEST_PLAN.md` holds the firmware notes, the panic and stop advice and the log format, and links here. Nothing here ran during the build: every automated run used MockTrainer with the hardware lock set. Work through the platform plan's "Before you start", probe, connect, SIM flat, ERG, slew, rescue, coasting and panic, and mode-switch steps first. Stop at the first failed safety check.

Siege sends no haptics, mode grades or ERG target changes. Its plans are all ERG. The one directive it ever sends is a 30 s SIM block, `{mode: SIM, duration_s: 30, reason: "overdrive", source: "siege"}` (Overdrive). Routing between stations never reaches the trainer. So the things to confirm on a trainer are: the wave targets and their slews, the duration-limit counters across breaks, the SIM block and its two switches, rescue, coasting and AFK, panic, route changes under load, and the FIT and Strava output. Sections 11 to 14 check the v2 view and sound; sections 12 and 13 need a Windows PC with integrated graphics but no trainer.

## 0. Setup

- [ ] Drop the locks only by hand, as the platform plan says. From source, PowerShell: `tools/godot.ps1 --allow-hw --timeout=14400 --path .`; Git Bash: `tools/godot.sh --allow-hw --timeout=14400 --path .` (without `--timeout` the wrappers stop a run after 20 minutes). Use `--allow-network` only for the Strava step (section 10). An exported build never sets the locks. Never pass these flags from an automated run.
- [ ] KICKR CORE, current firmware (before 1.5.5 it could spike on mode switches). Close Zwift and the Wahoo app. Know how to stop: hold Backspace for 1 s (panic), or stop pedaling.
- [ ] Set your FTP in the profile. Do the whole checklist once with it **verified** (a test result), and run sections 2 and 3 again **unverified**: waves then run at 0.85 x the planned target.
- [ ] Targets used below, at an example FTP of 250 W (scale to yours). The unverified column is 0.85 x the verified one:

| Content | Wave | Planned % FTP | Watts at FTP 250 | Unverified % | Unverified watts |
| --- | --- | --- | --- | --- | --- |
| `short` | 300 s | 95 | about 238 | 80.75 | about 202 |
| `vo2` | 120 s | 112 | 280 | 95.2 | about 238 |
| `sweetspot` | 900 s | 90 | 225 | 76.5 | about 191 |
| `endurance` | 2700 s | 70 | 175 | 59.5 | about 149 |

Every shift starts with the warm-up wave (300 s, 50% ramping to 65%) and a 120 s build break at 50%, so the first wave starts at 7:00. Breaks are 50% (sweetspot's 55%). The platform then appends a 180 s cool-down at 50%.

- [ ] Start Siege solo from the picker with the trainer connected. The lobby card has the wave offset (0 unless a step says otherwise) and "Tilt-shift blur" (on unless section 11 says otherwise). Use `short` unless a step names another content.

## 1. Warm-up wave

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 1 | Start `short` and pedal from 0:00 | The toast "Warm-up wave: spearmen on the road. Spin up the wheels!" shows. ERG ramps from 50% to 65% FTP over 300 s (125 W to about 162 W at FTP 250), rising smoothly, never above 65%. Spearmen only for the first 180 s, then chariots too. One ram at half HP comes down the road. One teaching toast a minute. The gate never falls below 50 HP | |
| 2 | During the warm-up press `ability_1` (and do a surge gesture) | Nothing happens on the trainer: no switch to SIM, no gear indicator, no sprint band, no Overdrive toast (the rules refuse it outside a WORK wave). No SIM and no haptics in the first 300 s | |
| 3 | At 5:00 the build break starts | ERG 50% (125 W at FTP 250). The shop opens with a countdown over its last 10 s. Your output goes to the mine; your powered path shows the mine | |

## 2. Each wave at its ERG target

Run the content, wait for the first wave and compare the trainer's power (and the HUD's target) with the table in section 0.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 4 | `short`, wave 1 (7:00) | ERG 95% FTP (about 238 W at 250), rising from the break's 50% at no more than 30 W/s; decreases are immediate. Holds within about 5% at steady cadence. No duration-limit clamp (95% is under the 105% band) | |
| 5 | `short` unverified | Wave 1 at 80.75% of FTP (about 202 W at 250). The 0.85 factor has only run against MockTrainer: log whether the trainer's target is 0.85 x 95% and that the factor only lowers it | |
| 6 | `vo2`, wave 1 | ERG 112% (280 W at 250) for 120 s. Unverified: 95.2% (about 238 W) | |
| 7 | `sweetspot`, wave 1 | ERG 90% (225 W at 250) for 900 s. Unverified: 76.5%. Phases over 300 s stay at or under 95% | |
| 8 | `endurance`, the wave | ERG 70% (175 W at 250) for 45 minutes. The rushes at 8, 16, 24, 32 and 40 minutes into the wave ("Rush! Spearmen and chariots charge") do not change the target. Unverified: 59.5% (about 149 W), below the 60% rescue threshold, so rescue is not armed in this wave; run the rescue steps (section 6) on another content | |
| 9 | Wave offset +5 and -10 on `short` (lobby card) | Wave targets 100% and 85%. The offset changes WORK targets only, never the warm-up or the breaks | |

## 3. The 50 to 117% step in `vo2`

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 10 | `vo2`, wave offset +5, FTP 400 (verified), the break-to-wave boundary at 7:00 | The target steps from 50% (200 W) to 117% (468 W). The slew rises at 30 W/s, so the trainer takes about 9 s (268 W / 30 W/s) to reach 468 W. The wave clock does not wait for it. Decreases at the wave's end are immediate. At offset 0 the step is 200 to 448 W, about 8 s. With a lower FTP the step is smaller and quicker; log the FTP you used | |
| 11 | Look for a spike or a clamp at the top | No overshoot above 468 W beyond the trainer's own ERG settling, and no "limit" banner (117% is under the 120% band, so only the 105% band counts) | |
| 12 | Repeat step 10 at the boundary into each later wave (the breaks are 180 s at 50%) | The same slewed step every time, with no spike | |

## 4. Breaks reset the duration counters

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 13 | Ride all six `vo2` waves at offset 0 (112%) and then at +5 (117%), with the full 180 s of every break at 50% | Six 120 s waves add up to 720 s above 105%. That would hit the 300 s limit in wave 3 if the counters did not reset. They reset because each break spends 180 s at 90% or less (the rule needs 120 s). Expected: waves 3 to 6 are as strong as wave 1, with no duration-limit clamp and no banner. Log the duration-limit readout if the HUD shows one | |
| 14 | In `short` (95%, never above 105%) ride the whole shift | No counter runs and nothing clamps | |

## 5. Overdrive: the ERG, SIM, ERG switch

Overdrive starts with `ability_1`, the HUD button, or a surge gesture while the Overdrive plate says SURGE TO START (your station has an enemy in range, the tar works a ram or tower within 60 m of the gate, or a rush is on). It needs a WORK wave with at least 30 s left, no rescue and a pedaling rider. After it ends the cooldown is 90 s. Use `short` (5-minute waves) and a verified FTP. Log the trainer's power around each switch, with a recording or by eye at 1 s resolution.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 15 | Mid-wave, at least 30 s after any other ERG/SIM change, ride steady on the ERG target and press `ability_1` | Entry: ERG at min(applied target, your 3 s power), then SIM grade 0 and wind 0, then the stacked SIM state, in separate control writes. **No power spike on any of the three.** The toast "Overdrive! Sprint for 30 s" shows. The gear indicator appears. The power gauge shows the sprint band at 1.2 to 1.4 x FTP (300 to 350 W at FTP 250). The button counts down from 30 s | |
| 16 | During the block, shift virtual gears up and down | In SIM the grade is 0 and only the gear offset applies. Each shift changes the resistance by roughly 6 to 8% near 30 km/h. The grade never shows a hill or a haptic | |
| 17 | Sprint inside the band (at or above 1.2 x FTP) for 10 s or more | Raw power at or above FTP doubles your output (your station winds faster). At the end, "Overdrive sprint scored!" | |
| 18 | The 30 s block ends while you keep sprinting hard | Return: SIM flat, then ERG at min(your 3 s power, the planned target), never above the planned target (a sprint above the target returns at the target itself), then a slew up at 30 W/s if it started lower. **No spike, and no jump above the 95% target** | |
| 19 | Repeat, but ease off to about 50% FTP in the last 3 s of the block | ERG resumes near your easier power (the 3 s mean) and then slews up to the target at 30 W/s, not at once | |
| 20 | Press `ability_1` again right away | Refused for the 90 s cooldown: the button shows "Recharging" with the seconds left. The next start is at least 30 s after the return to ERG, which the cooldown guarantees | |
| 21 | Start an Overdrive with 31 to 35 s of a wave left (the latest it is allowed is with 30 s left), so the block ends on the wave boundary into the break | The phase change ends it: "Overdrive spent", the 90 s cooldown from that moment, and the trainer returns from SIM to ERG at the break's 50% target (125 W at 250) with no spike, slewing as needed. The break runs normally and the shop opens. In the next wave Overdrive is ready again | |
| 22 | Press `ability_1` with under 30 s of a wave left | Nothing happens: no switch on the trainer and no toast (the rules refuse it as too late) | |
| 23 | Stop pedaling for a moment (under 3 s, power under 15 W and cadence under 20 rpm) and press `ability_1` | Nothing happens and no toast shows: the rules do not ask for SIM for a rider who is not pedaling (ADR "SAFE-1"). Pedal again and press: it starts | |
| 24 | Two PCs: PC A hosts `short`, PC B (its own trainer) joins by code. On PC B press `ability_1` | The host accepts, and the directive reaches B's governor, which applies SIM. B's trainer is in SIM within about 1 s of the press, and B's gauge shows the sprint band. If B's governor refuses (for example the 30 s switch spacing), Overdrive is cancelled with a 30 s retry, and "Overdrive unavailable right now" shows on B only. The trainer on A is unaffected. B returns to ERG with no spike | |
| 25 | A bot rider in the session | Bots never use Overdrive | |

## 6. Rescue in a wave

Use a content and FTP where the wave target is at least 60% after the factor (`short`, `vo2`, `sweetspot`, verified or not; not unverified `endurance`).

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 26 | In a wave, drop cadence below 45 rpm for 3 s | The target drops to 50% FTP. The rescue banner and the toast "The walkers stumble: spin back up" show, and Overdrive is unavailable. Output still counts at your actual P_eff. The plan clock and the wave keep running | |
| 27 | Press `ability_1` during rescue | Nothing: no SIM block, no gear indicator | |
| 28 | Hold 70 rpm or more for 3 s | The target ramps from 50% back to the wave target over 10 s at no more than 30 W/s. Overdrive becomes available again once rescue ends and its cooldown is clear | |
| 29 | Two PCs: trigger rescue on PC B | A's teammate strip marks B as in rescue. A's trainer is unaffected | |
| 30 | Start an Overdrive, then drop cadence below 45 rpm (rescue can't arm while the trainer is in SIM; log what happens) | If rescue starts, the Overdrive ends ("Overdrive spent") with the 90 s cooldown, and the trainer returns to ERG with no spike. Log the order of the events | |

## 7. Coasting and AFK

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 31 | Stop pedaling in a wave, solo | After 3 s the target falls to the floor (the larger of 30% FTP and 50 W). After 10 s the session pauses (pause symbol, enemies stop, ERG at the floor). Pedal again to resume; ERG climbs from the floor at 30 W/s | |
| 32 | Two PCs: stop pedaling on PC B in a wave | B's trainer floors at 3 s. At 10 s B is AFK: B's wheel stops turning on both screens, "Your wheel stopped" shows on B, and the game does not pause. B's routing, gold and share of the threat budget are kept (the wave does not get easier). A running Overdrive of B ends. Pedal again: AFK clears and ERG climbs from the floor | |
| 33 | Two PCs: stop pedaling on both | Once every human rider has stopped, the session pauses on both machines. It resumes when one rider pedals again | |
| 34 | Stop pedaling during a break | The floor after 3 s. Solo pauses and multiplayer marks AFK at 10 s, as in a wave | |

## 8. Panic during Overdrive

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 35 | Start an Overdrive, then hold Backspace for 1 s (or View + Menu, or the on-screen PANIC button) | ERG is off and the trainer is at grade 0, wind 0, at once (under 1 s). The trainer stays safe until you resume. Log what Siege's HUD shows for the Overdrive (the rules end it on a rescue, AFK or phase change, not on panic, so its clock keeps running) | |
| 36 | Resume | The next ERG command enters at the floor and slews up at 30 W/s. No spike. The game continues and the next wave's target is normal | |
| 37 | Panic during a plain ERG wave | ERG off and SIM flat at once; resume as in step 36 | |

## 9. Route changes while pedaling

Siege sends nothing to the trainer when you change station. These steps check that and the 2 s reconnect on screen. Ride steady on an ERG wave target in `short`.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 38 | Press right (or `swap`) once | Your powered path (wheel, lane, clutch drum, column, station) lights in your colour to the next station at once. The stations card shows the 2 s coupling bar, and "Coupled to the ..." shows. The new station starts working after 2 s (its winding, rack or pump moves), with no output from you in between. **The trainer's load does not change**: no control write, no step, no spike | |
| 39 | Press left, then up, then down | Left: the previous station. Up: the mine. Down: the "hot" station (the one with the thin red bar on the stations card). Each change takes 2 s to couple and lights the path at once | |
| 40 | With another rider (or bot) on the tree ballista (cap 1), route toward it | The full station is skipped; your path goes to the next one with room | |
| 41 | Change station several times in a row, quickly | The path follows each press. Your power on the trainer stays steady on the ERG target the whole time | |
| 42 | In a break, press the directions | They move the shop list, not your route. Your path shows the mine, and your target is kept for the next wave | |
| 43 | Two PCs: change station on PC B (the client) | B's path and stations card change at once (predicted), and the host's route confirms it. If the host refuses (the station filled up), B's path goes back within about 2.5 s. A sees B's path move. Neither trainer changes load | |

## 10. Cool-down, FIT and Strava

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 44 | Finish a shift | The 180 s cool-down runs at 50% FTP. Nothing spawns, enemies retreat, the shop and Overdrive are closed, and the fort's people march out over the bridge. The results screen shows the grade, score, Breaches, gate HP per wave and per-player stats. The first ride unlocks the swallowtail pennant at 100 XP | |
| 45 | `node tools/fit_check/check.mjs <the FIT in your rides folder> --expect-laps=<n>` | Laps are the lap-true phases plus the cool-down: `short` 8, `vo2` 14, `sweetspot` 6, `endurance` 4, `drill` 3. The laps are named like "Warm-up wave", "Build break", "Wave 1", "Break 1". Power, cadence and the lap boundaries match the ride | |
| 46 | Upload to Strava (`--allow-network` with your own API app, platform plan section 12) | A Virtual Ride with power and cadence and the same laps | |

## 11. The tilt-shift option

The option is "Tilt-shift blur" on the lobby card (`tilt_shift`, on by default). The view reads it when the session starts, so set it in the lobby.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 47 | Ride a wave with the option on | The top and bottom rows of the picture blur; the wide middle band with the fort stays sharp. A warm haze shows over the top and a vignette at the edges | |
| 48 | Ride a wave with the option off | The whole picture is sharp. The haze and the vignette stay | |
| 49 | Two PCs: option on for A, off for B | Each screen follows its own rider's option | |
| 50 | On an integrated-graphics PC, note the frame rate with the option on and off (section 12) | Log both. The blur is a screen shader that reads the whole screen, so it is the most likely cost | |

## 12. Frame time on an integrated-graphics Windows PC

The view has only been measured on an NVIDIA GPU. The goal is 60 fps at 1920 x 1080 with 150 enemies on integrated graphics, with the Compatibility renderer the project uses. No trainer or lock flag is needed.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 51 | The demo stress scene: `tools/godot.ps1 --timeout=300 --path . --resolution 1920x1080 res://src/games/siege/view/v2/siege_v2_demo.tscn -- --siege-demo-stress` (Git Bash: `tools/godot.sh ...` with the same arguments). Let it run for at least a minute | Every 60 frames the log prints `siege_v2_demo: <n> enemies, <n> projectiles, update <ms> ms, <n> fps, <n> draw calls`. Pass: 150 enemies at 60 fps (the display's refresh rate caps it). The ADR's draw-call figure is 7. Log the GPU, the driver, the display's refresh rate and the printed lines | |
| 52 | The same with `--siege-demo-sharp` added after `--siege-demo-stress` | The same numbers without the blur. Log the difference | |
| 53 | A real session at 1920 x 1080, full screen: host `short` with three bots (or friends), mock or real trainers. Watch the last third of a wave, a ram push, the siege tower's dock and a Breach | No stutter at a wave start, a push, the dock or a Breach. Log any dropped frames you see | |

## 13. Depth-tested sprites on an integrated GPU

Every moving sprite is drawn with a shader that hides its pixels behind the baked world. The sprite's anchor depth travels in the draw's modulate colour (16 bits in R and G), and the ramp row and sun shade in B. A GPU that stores vertex colours with less precision could hide sprites wrongly or recolour them wrongly. Check on the same integrated-graphics PC as section 12.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 54 | Capture the demo on this PC and on an NVIDIA PC: `tools/screenshot --scene=res://src/games/siege/view/v2/siege_v2_demo.tscn --frames=120` (files in `build/screenshots/scenes/`) | The two pictures match: the demo advances a fixed 1/60 s per frame, so the same `--frames` gives the same moment. Log any difference | |
| 55 | In a session, watch enemies where the road passes trees and dunes, and on the open road and the bridge | Bodies behind trees and dunes are hidden where those stand in front of them. Bodies on the open road and the bridge are drawn whole: no cut-off heads, no flicker, none drawn through a wall | |
| 56 | Watch the gate: a ram battering it, the siege tower docked with boarders on the wall walk, and the cool-down march out of the gate | The ram stays in front of the gate. Boarders stand on the wall walk, not inside the wall. The marchers come out from behind the gatehouse, hidden until they pass it | |
| 57 | Watch the onager throw | Its arm passes behind its own frame and comes back in front | |
| 58 | Four riders (or one rider and three bots) on different stations | Each wheel, powered path and station part shows its rider's colour (orange, blue, yellow, green). Parts nobody drives show timber, rope, bronze or dark stone. No magenta pixels anywhere (magenta is the key colour; it shows if the recolour fails) | |

## 14. Listening check of the audio

Every sound is rendered from `assets/siege/audio/audio.json` by `tools/audio`. The owner heard the first version and it failed (no arrows, weird wheels); this one has passed its numbers and a recording of a real session, and no person has heard it. First **listen** to `build/audio_preview/siege.mp3` (`node tools/audio/preview.mjs --game=siege`), then ride at normal listening volume.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 59 | Listen: the preview mp3, then 60 s of riding at 60, 90 and 110 rpm | A heavy timber treadwheel: a low wooden rumble, a soft footfall on planks twice a revolution with a quiet pawl under it, one gentle axle knock per revolution. No whine, no squeak, nothing that sounds like a synth, and no pitch that climbs with your cadence. Tell whether it reads as a big wooden wheel. Does the rumble drone on an hour's ride? From about 170 W a dull timber rub comes in: is it pleasant, and do you notice it? | |
| 60 | Watch your wheel while you change cadence | The walkers' stride and the strokes move together, one walk cycle per revolution; they follow the reported cadence about once a second. Stop pedalling: the wheel's strokes end at once and the groan is gone within a blink. Two honest exceptions, both following the drawn phase: with Reserve the mine and the pump run on for 10 s after a stop, and with the Aqueduct the pump never stops | |
| 61 | Each weapon firing: ballista, onager, arrow organ, a Scorpion. Put your wheel on one, then the next | Each shot: a release, a swoosh that arcs over and falls in pitch, an impact when it lands. **On the organ at 90 and 110 rpm: can you follow one volley's arc from the others, by ear?** Every other volley is 6 dB under: does that read as a pass and a quieter echo, or as a stutter? Are your own shots plainly yours, with the other riders' under them? The swoosh sits around 1-2 kHz: does it read as arrows or as wind? Do the bolt, the stone and the arrows sound different with your eyes closed? Do the swooshes move across the screen with the picture, on speakers and on headphones? Note anything you'd turn down | |
| 67 | Where a shot lands, in a wave with spearmen, shield bearers, a ram and a tower. Watch and listen | **Every arrow that lands makes its own sound, at the moment and on the side you see it land** (the owner's request; `docs/decisions/audio-siege.md`). A volley comes down as a quick patter of small thuds with about three louder ones in it, and every arrow that strikes something is one of the louder ones. **Can you count them?** When an enemy reaches the gate an alarm rings and the arrows and the wheel step back: do you hear it the first time, in a busy volley? That one is a warning you act on. That is what the accents are for: tell if they read as separate arrows or still as one rattle, and if they read as a beat you tire of. Arrows near the camera are louder than far ones, and a volley spreads a little left and right: does it? On the organ, watch one arrow strike a spearman: do you hear that one? Does a body read as a hit and a miss as a miss, with your eyes closed? On the road a soft thud with a little sand, in the moat a small plip, on spearmen a slap around 700 Hz, on a ram or a tower a wooden knock around 1 kHz, on a shield bearer who blocks a small bronze ring. A swoosh now peaks at the top of the arc, before its arrows land: does the landing come clear of it? The dock and the wave's bell are a little quieter than they were: tell if you miss them. Put your wheel on the mine: do the other riders' arrows still sound, under your own? A single miss is measured under the mix: are misses a patter you like, too quiet to matter, or too much? Ride a whole wave and then a whole `short`: is the stream of arrows tiring? Do the volleys become a pulse you wish would stop? Tell which sound you would turn down first. A heavier weapon on a body stays its own, bigger sound: Does the ring of a shield sound like bronze or like a bell? Is a ballista's release clear mid-wave? It reads about 2 dB over its moment (a waived row): tell if you miss it. A killing blow should sound like the hit before it. A stone on a ram is a timber crash. A ram or a tower going down is a bigger one. On a client (a second machine) the same | |
| 62 | The tar works and the mine working; chariots, a ram at the gate, a walking tower, gate hits, a Breach | The pump's stroke with its drawn cycle, tar bubbling and pouring, a hiss when the curtain or coat changes, the mine's picks. Soft hooves only when a chariot is close to the gate, the ram a slow low knock, heard over the flights, the tower creaks and docks with a thud, a Breach is a crash that ducks the rest. A warning or rescue prompt still cuts through all of it. Stop pedalling until the session pauses with a ram at the gate: no ram, no hooves, no war drums over the frozen picture, and no pile of drums on the resume | |
| 66 | Under load, let your cadence sag: hold a hard wave target and fall through 70 to under 45 rpm, until the rescue prompt sounds. Then the same warning at 60 rpm and at 75 rpm in a busy wave | The prompt is plain over the wheel and the battle every time, not something you have to listen for. The mix alone reaches the +6 LU target only in part of this range (ADR "A safety prompt clears", its table). Log the cadence, the power and whether you heard it at once | |
| 63 | A wave start, a siege engine's push, a rush, a wave's end | A far horn for each, the wheel ducking under it, and a bell at the end; readable, not startling. Tell whether you hear the horn over the wheel at 110 rpm: it is about level with the mix in its best octave | |
| 64 | Earn gold, buy, switch a route, Overdrive | A coin when your own gold goes up, a hammer on a purchase, a lever on a route, a horn call on Overdrive. Another rider's lever is quieter than your own | |
| 65 | The hill and the whole mix | Gusting wind, brighter between waves, crows and banners now and then, war drums growing with the enemies, the far crowd under them; a far anvil and a lark in the warm-up and between waves. Do the drums, the banners and the anvil reach you at all over the wheel in a wave? They are marginal on paper. Nothing drowns the others at normal volume; the Settings bus sliders each do what they say. Pleasant over a whole shift? Note anything tiring | |

## 15. The HUD with and without a heart rate sensor

The HUD is Siege's own (`docs/games/siege.md` 3). Run `short` with the real trainer, once with a paired heart rate sensor and once without, and read it from your riding distance.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 67 | No sensor paired: ride a wave | No heart rate cell, the cockpit is the narrow plate (344 art px); clock, watts and cadence read from 3 m | |
| 68 | Pair a sensor in Settings, ride a wave | The cell shows a muted heart and cream digits, the plate is the wide one (404 art px); the bpm follows your sensor | |
| 69 | Take the strap off or stop the watch's broadcast for 30 s | The cell stays and shows `--`, never "no sensor", then the digits come back. Log how long the sensor takes | |
| 70 | Hold steady power inside the band on the real 1 Hz data for 2 minutes | The watts number moves calmly (a 3 s mean), no up or down arrow flickers on and off at a steady effort. Log any flicker | |
| 71 | Drift 10% under the target, then 10% over | The blue up arrow, then the amber down arrow, each after about 3 s | |
| 72 | In a wave, let the cadence fall under 70 rpm | After about 1.5 s: the cadence on a red chip and SPIN UP: RESCUE AT 45. Back above 72: both clear | |
| 73 | In a break, ride at 60 rpm | No red chip: rescue is not armed at 50% FTP | |
| 74 | Trigger rescue (under 45 rpm for 3 s) | The caption reads RESCUE and the watts really applied (compare with the trainer), RPM 70+, RESCUE: SPIN 70+, THEN: RAMP BACK TO the plan's watts. The platform's rescue banner shows in its own colours | |
| 75 | Stop pedaling | PEDAL: LOAD DROPPED on the chip within about 3 s; the target caption shows the floor | |
| 76 | Start an Overdrive | SPRINT LEFT with its clock, SPRINT and the real band for your FTP, the SIM chip and the gear. Under the band: SPRINT ..., SHIFT UP; in it: HOLD ...; over it: EASE TO .... The gear changes with your shifting. Back in ERG, ERG shows and the gear is gone | |
| 77 | Pull the trainer's power for 10 s during a wave | The platform's trainer notice shows, the watts read `--`, not 0, the caption reads TARGET --, and the chip says NO TRAINER DATA: KEEP PEDALLING until data returns; never PEDAL: LOAD DROPPED | |
| 78 | Check W/kg with the opt-in off, then on (Settings) | Off: none anywhere. On: the W/kg under the %FTP | |
| 79 | The last 30 s of a break before a wave | The clock turns gold, LOAD UP IN 0:30, SPIN UP counts down; the NEXT line's watts match what the trainer then applies | |
| 80 | Ride a whole `short` on an integrated-graphics PC at 1080p with four riders | 60 fps with the HUD up, also with the shop open. Log any dropped frames | |
| 81 | Maximise the window on every monitor you have, then drag it to other sizes during a wave | No black at any size; the fort, the wheels and the road stay on screen; no plate overlaps another; tags sit over their engines, the F1 arrows on what they name | |
| 82 | Repeat step 80's fps check at a 1280 x 720 window and, if you have one, on an ultrawide | 60 fps at the largest canvas you can reach. Log the window and any dropped frames | |

## 16. The shared receipt

Use two PCs (host and client) or one PC and a bot for steps 83 to 88, in any break (the build break will do), with pedal navigation on for step 84. The receipt only changes what is bought and when; none of these steps may change the trainer's load.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 83 | In a break, pick an upgrade with the keys (or the surge), then check the trainer | The item appears on the receipt panel above the shop with your name, its cost, YES n and the total; "N ON RECEIPT" shows under your gold and your free gold drops by the cost; the shop row says ADDED. **No gold is spent yet and the trainer's load does not change** | |
| 84 | With pedal navigation on, pedal in ERG for more than two scan cycles without picking anything | The lit row moves along the list, but nothing is picked: the receipt stays as it was, and the hint says pedalling alone adds nothing. Surging picks the lit row | |
| 85 | Pick your own item again | It leaves the receipt and your held gold comes back at once | |
| 86 | Two riders: the second picks the first's item (it shows the picker's name in the shop) | The receipt shows NO 1 and, on the voter's screen, YOUR NO. With two riders the tie takes the item off at once, the picker sees "Voted off" and their gold is back. Pick it again as the picker and then vote yes: it stays | |
| 87 | Three or four riders: one no, then a second | One no leaves the item on (YES 2 NO 1 with three riders); the second no takes it off | |
| 88 | Let the break end with two or three items on the receipt | Each is bought in the order it was added, once, with a "Bought" toast to its picker, the receipt empties and your gold drops by what was held. The wave starts at its ERG target as usual | |
| 89 | A rider drops out mid-break (close their game) | Their items leave the receipt and their votes drop; the others' items stay and are bought at the end | |

## Log template

Copy this block for every step.

```text
Step:
Date and time:
Trainer model / firmware:
PC / GPU / driver (sections 11-13):
Command:
Content / players / bots / wave offset / tilt-shift:
FTP / verified or not:
Expected:
Observed (power, cadence, target, timings, fps):
Pass / fail:
Notes (screenshots, spikes, anything unexpected):
```

Log the date, trainer firmware, FTP, verified or not, and each step's result. Stop at the first failed safety check and report it: a power spike on a mode switch or a route change, an ERG step faster than 30 W/s, panic slower than 1 s, or a wave target above its table value.
