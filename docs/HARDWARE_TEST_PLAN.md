# Hardware test plan

A checklist for Simon with the real KICKR CORE (or KICKR CORE 2) and a real Strava account (BRIEF 4.7). Nothing in this plan ran during the autonomous build: every automated run had the hardware and network locks set and used MockTrainer and the mock Strava server. Work through it in order; stop at the first failed safety check.

Commands that need the trainer or Strava pass `--allow-hw` or `--allow-network` to the wrappers (`tools/godot.ps1` on Windows, `tools/godot.sh` in Git Bash). Nothing else drops the locks. Run every command from the repo root.

## Before you start

- Update the trainer firmware with the Wahoo app (current firmware for FTMS control and safe ERG/SIM switches; firmware before 1.5.5 could spike to 2000 W on mode switches).
- Close Zwift, the Wahoo app and anything else that may connect to the trainer. Remove any Windows-level Bluetooth pairing of the trainer.
- Have a way to stop instantly: hold Backspace for 1 s (panic), or stop pedaling.
- Keep a heart-rate or perceived-effort check of your own; the governor protects the trainer, not your judgement.

## Log template

Copy this block for every step.

```text
Step:
Date and time:
Trainer model / firmware:
Command:
Expected:
Observed:
Pass / fail:
Notes (power numbers, timings, screenshots):
```

## 1. Probe (read-only)

How to start the app for these tests: the exported build (`node tools/export_windows.mjs`, then `build/windows/Wattlands.exe`) never sets the locks. From source, use `tools/godot.ps1 --allow-hw --allow-network --timeout=14400 --path .` (PowerShell) or `tools/godot.sh --allow-hw --allow-network --timeout=14400 --path .` (Git Bash; without `--timeout` the wrappers stop a run after 20 minutes); without those two flags the wrappers keep the hardware and network locks on.

- [ ] Run the read-only probe: `cd tools/trainer_bridge`, then `uv run --with bleak --with websockets python -m trainer_bridge probe --seconds 30` (bleak needs Python 3.12-3.14 on Windows; it has no wheels for 3.15 yet). Exit codes: 0 done, 2 no adapter or no trainer, 4 connect failed. Expected: the trainer is found by service 0x1826 or a name containing KICKR; device information, Fitness Machine Feature, Supported Power Range (max about 1800 W) and Supported Resistance Level Range print; Indoor Bike Data prints for 30 s with power, cadence and speed that match your pedaling.

## 2. Connect and read-only data in the app

- [ ] Start the app as above (exported build, or from source with `--allow-hw`). Expected: auto-connect (or connect from Settings), status "ready", live power and cadence on the title screen within 2 s of pedaling.
- [ ] Heart rate sensor: wear a chest strap, or set a Garmin watch to Broadcast Heart Rate, and pair it in Settings > Trainer > Sensors (Scan, then the sensor). Expected: status "ready" and a live bpm that matches the strap or watch. Switch the sensor off and on (or walk out of range and back). Expected: it reconnects by itself, also after an app restart. In a session the HUD shows the bpm next to the watts, and the saved FIT has heart rate in its records and avg/max heart rate in its laps and session.
- [ ] Another app holding control (start the Wahoo app first, connected): Expected: "another app may hold control" message, no crash.
- [ ] Mid-ride, start Zwift or the Wahoo app and let it take control. Expected: the session HUD shows "Another app (Zwift, the Wahoo app) may hold control of the trainer. Close it, then reconnect." in the banner area, with one warning sound, until the trainer is ready again.
- [ ] Let the Wahoo app hold control, then start a session from the lobby without regaining it. Expected: the session HUD shows the same notice from its first frame, with one warning sound, until the trainer is ready again (Settings, connect the same trainer).

## 3. SIM flat

- [ ] After connecting, the trainer should be in SIM at 0% (light, road-like). Pedal at 90 rpm in a middle gear. Expected: smooth resistance, no surges.

## 4. ERG 100 W

- [ ] Start Workout's Easy 30 with FTP set so the warm-up starts near 100 W. Expected: power settles to the target within a few seconds and holds within about 5% at steady cadence.

## 5. Slew

- [ ] Watch the step from a recovery to a work interval. Expected: increases ramp at no more than 30 W per second; decreases are immediate.

## 6. Rescue

- [ ] In an ERG work interval at or above 60% FTP, drop cadence below 45 rpm for 3 s. Expected: the target drops to 50% FTP, "rescue" shows, and the target ramps back over 10 s after you hold 70 rpm for 3 s.

## 7. Coasting and panic

- [ ] Stop pedaling in ERG. Expected: after 3 s the target falls to the floor (max(30% FTP, 50 W)); after 5 s a solo session pauses and the pause symbol shows; 1 s of pedaling at 30 rpm or more resumes it, and the target ramps back from the floor at 30 W/s.
- [ ] In a multiplayer session, stop pedaling on one machine only. Expected: that rider sees the pause symbol after 5 s and the others ride on; once every human rider has stopped, the session pauses on every machine; it resumes when one rider pedals again.
- [ ] Hold Backspace for 1 s during an ERG interval. Expected: ERG off and SIM 0% immediately; the trainer stays safe until you resume.
- [ ] During a SIM sprint, trigger panic. Expected: grade 0 and wind 0 at once.

## 8. Mode switches

- [ ] Easy 30's free sprints: ERG -> SIM -> ERG. Expected: no power spike on either switch; ERG resumes at or below the planned target and slews up.

## 9. Workout: Easy 30 for 5 minutes, VO2 for 5 minutes

- [ ] Easy 30, first 5 minutes (warm-up ramp 50 -> 65%). Expected: targets never above 65% FTP during warm-up.
- [ ] VO2, 5 minutes from the first interval (skip the warm-up only if you already warmed up, via Settings). Expected: 110% FTP targets, duration limits respected.

## 10. Two-PC multiplayer

- [ ] Run the relay (`server/relay`) on one PC or a reachable host. PC A hosts Workout; PC B joins with the room code. Expected: both ride the same timeline at their own %FTP; the teammate strip shows both riders; each rider's FIT file is saved locally.

## 11. Disconnect and reconnect

- [ ] Mid-session, switch the trainer off (or move out of range) for 10 s, then back on. Expected: reconnect with backoff (1, 2, 4, 8 s, max 15 s), control re-requested, the last safe mode restored, the session continues.
- [ ] Kill the client app on PC B and restart it with the same profile. Expected: it rejoins with its reconnect token and finishes the session.

## 12. Strava

- [ ] Create a Strava API application (callback domain `localhost`), enter its Client ID and Secret in Settings, Strava, and Connect. Expected: the browser opens Strava's authorize page; after approval the app shows "connected".
- [ ] Upload a finished ride from the results screen. Expected: it appears on Strava as a Virtual Ride with power and cadence, with laps per interval.
- [ ] Disconnect. Expected: the token is revoked and `strava.json` no longer holds tokens.

## Games

Each game keeps its own real-trainer checklist; this plan only links to it.

- Workout: `src/games/workout/HARDWARE_TEST.md` (its game checks; the platform checks in sections 4-9 above ride Workout too).
- Castellum Rotae: `src/games/siege/HARDWARE_TEST.md` (written by the Siege session).
- Diesel Domestiques: `src/games/tank/HARDWARE_TEST.md` (written by the Diesel Domestiques session).
- Turbo Reel: `src/games/fishing/HARDWARE_TEST.md` (written by the Fishing session).

## Checks only a real trainer can confirm (from the build)

The builders listed these while working against MockTrainer and fake transports. Log each like the steps above.

- [ ] FTMS link timing: subscriptions settle within the 0.25 s the client waits; discovery finishes inside the 10 s timeout on Windows; the KICKR sends one complete Indoor Bike Data record per notification (the client also reassembles split records).
- [ ] Set Target Resistance Level (RESISTANCE mode, P1 fallback): the KICKR accepts the uint8 0.1 encoding (the codec can switch to sint16).
- [ ] The control-point queue and coalescing: at most 2 writes a second against real response timing; no "operation failed" responses in a 10-minute session.
- [ ] Panic latency: from holding Backspace for 1 s to ERG off and SIM 0% on the trainer, under 1 s.
- [ ] Mode switches: ERG -> SIM -> ERG around a 30 s sprint with no power spike, ERG re-entered at or below the planned target.
- [ ] Reconnect resync: drop the Bluetooth link mid-ERG at about 200 W (switch the trainer off for 10 s). Expected: on reconnect the trainer returns to SIM flat, then ERG from the floor with 30 W/s slew back to the target, at most 2 writes a second. In a SIM phase the stacked grade returns in one write. During panic it stays at SIM flat.
- [ ] Quit with a real trainer: closing the app sends SIM flat, then Stop, within the 0.5 s grace before the process exits.
- [ ] Window close while riding ERG and hosting (W3 NET-6, W4r2): host a Workout room with a client on a second PC, and close the host's window during an ERG interval. Expected: SIM flat, then Stop reach the KICKR before the process exits (the ERG load releases at once and none comes back), and the client shows that the host left and goes to the results at once, instead of the "host lost the connection" banner for up to 120 s. Repeat with the host's window closed in the lobby: the client learns at once that the host left.
- [ ] A client restarted in the warm-up (W4r2 NET-2): 2 minutes into the 300 s warm-up ramp, quit the client on PC B and relaunch it with the same profile, then rejoin with the room code. Expected: its ERG target continues the host's ramp where the host is (about 56-60 % FTP 2-3 minutes in), not back at the ramp's 50 % start; while its new trainer connection is still in its first 5 minutes of riding, ERG stays capped at 65 % FTP even after the host's warm-up phase ends; its new FIT file starts at the rejoin with no extra lap there (`node tools/fit_check/check.mjs <file>` prints each lap's start and duration).
- [ ] The trainer bridge with its default URL (W4r2, loopback rule): the app falls back to the bridge only when GDBLE doesn't start, for example in a build without `--with-vcruntime` on a PC without the Visual C++ runtime (see the last item of this list). There, in a shell that has not sourced `tools/env.*` (the bridge refuses writes under the hardware lock), run `uv run --with bleak --with websockets python -m trainer_bridge serve` in `tools/trainer_bridge`, then start the app. Expected: the app reaches the bridge at its default `ws://127.0.0.1:8765` and connects to the trainer through it (the bridge URL must be an `http(s)://` or `ws(s)://` loopback URL; anything else is refused).
- [ ] Auto-scan finds a late trainer (W4 ftms-ble-3): with a trainer the app has connected before (remembered) switched off, start the app, then switch the trainer on 60-90 s later. Expected: the app finds and connects to it with no input; each 30 s scan window stops the previous scan before it starts the next, so the log shows no BUSY or scan error.
- [ ] Cadence estimation on a trainer that reports no cadence: the estimate tracks real cadence within a few rpm after 10 s of riding.
- [ ] Virtual gears: one shift changes resistance at constant flywheel speed by about 6-8% near 30 km/h (the approximation is documented in docs/TRAINER.md).
- [ ] Strava: the real token response, upload duplicate text and 429 headers match what the mock assumed; revoke works (the client falls back to /oauth/deauthorize).

- [ ] A clean PC without the Visual C++ 2015-2022 x64 runtime: the build made without `--with-vcruntime` shows no trainers; installing the runtime (or a `--with-vcruntime` build) fixes it.

## Safety findings that need hardware

From the W3 review (the findings and their fixes are recorded in the W4 ADRs in `docs/decisions/*.md`, merged into `docs/DECISIONS.md`):

- [ ] Silent notifications (W3 SAF-7): with the link up but no Indoor Bike Data notifications for more than 3 s (hard to provoke; a trainer that stops notifying while connected), the stack treats the rider as not pedaling, so the coasting floor and pause/AFK still apply. Confirm the KICKR never stops notifying while the flywheel turns, and log what happens when it does.
- [ ] An unanswered control-point write while ready (W3 ftms-ble-1, fixed): if the KICKR stops answering control-point writes, the app reconnects and restores the last safe mode instead of staying "ready" while dropping writes. Expected after a forced disconnect: the reconnect sequence of section 11 and the safe-mode restore above.
- [ ] Settings Disconnect, trainer switch and "use mock" (W3 SAF-8, fixed): the trainer goes to SIM flat, then Stop, before the link drops.
- [ ] A rider's own FTP on a client (W3 SAF-1, fixed): a client riding with a host whose copy of the client's FTP differs still gets ERG targets from its own profile (check the target on the client's power gauge against its own FTP).
