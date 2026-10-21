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

The commands in this plan are finalised in W4 together with the README.

- [ ] Run the read-only probe (Python bridge, `tools/trainer_bridge`). Expected: the trainer is found by service 0x1826 or a name containing KICKR; device information, Fitness Machine Feature, Supported Power Range (max about 1800 W) and Supported Resistance Level Range print; Indoor Bike Data prints for 30 s with power, cadence and speed that match your pedaling.

## 2. Connect and read-only data in the app

- [ ] Start the app with `--allow-hw`. Expected: auto-connect (or connect from Settings), status "ready", live power and cadence on the title screen within 2 s of pedaling.
- [ ] Another app holding control (start the Wahoo app first, connected): Expected: "another app may hold control" message, no crash.

## 3. SIM flat

- [ ] After connecting, the trainer should be in SIM at 0% (light, road-like). Pedal at 90 rpm in a middle gear. Expected: smooth resistance, no surges.

## 4. ERG 100 W

- [ ] Start Workout's Easy 30 with FTP set so the warm-up starts near 100 W. Expected: power settles to the target within a few seconds and holds within about 5% at steady cadence.

## 5. Slew

- [ ] Watch the step from a recovery to a work interval. Expected: increases ramp at no more than 30 W per second; decreases are immediate.

## 6. Rescue

- [ ] In an ERG work interval at or above 60% FTP, drop cadence below 45 rpm for 3 s. Expected: the target drops to 50% FTP, "rescue" shows, and the target ramps back over 10 s after you hold 70 rpm for 3 s.

## 7. Coasting and panic

- [ ] Stop pedaling in ERG. Expected: after 3 s the target falls to the floor (max(30% FTP, 50 W)); after 10 s a solo session pauses.
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

- Workout: covered by sections 4-9 above.
- Generator Siege: `src/games/siege/HARDWARE_TEST.md` (written by the Siege session).
- Tank Crew: `src/games/tank/HARDWARE_TEST.md` (written by the Tank Crew session).
- Big Game Fishing: `src/games/fishing/HARDWARE_TEST.md` (written by the Fishing session).

## Safety findings that need hardware

Findings from the W3 review that can only be confirmed on the real trainer are added here in W4.
