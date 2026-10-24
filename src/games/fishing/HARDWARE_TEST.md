# Turbo Reel: real-trainer checklist

The game's own checklist for a real KICKR CORE (BRIEF 4.7). `docs/HARDWARE_TEST_PLAN.md` holds the setup, the safety notes and the log template, and links here: work through its sections 1-8 first. Nothing here ran during the build (every automated run used MockTrainer with the hardware lock on). Start the app as that plan says (the exported build, or `tools/godot.ps1 --allow-hw --timeout=14400 --path .`), never from an automated run. Stop at the first failed safety check, and hold Backspace for 1 s (panic) whenever something feels wrong.

Before you start: set your FTP and preferred cadence in your profile, haptics on, and note whether your FTP is verified (an unverified FTP scales every ERG target by 0.85). Numbers are % of FTP.

## 1. Drive-out (warm-up, Free Roam)

- [ ] Start `roam_30` solo and pedal. Expected: SIM for the first 5 minutes, no ERG, no haptics, no bites; the resistance rises gently with boat speed (about 2.5 % grade at cruise, never above 3 %); the boat moves off the dock and speeds up with your power, the bow lifts when you hammer.
- [ ] Ease off below about 20 % FTP. Expected: the boat drifts to a stop within about 15 s and the resistance drops to flat; the menu chips appear next to the boat.
- [ ] Panic once while driving, then resume. Expected: trainer safe at once; the session goes on after resume.

## 2. The menu, casting, waiting

- [ ] Keyboard or gamepad: left / right moves the highlight, confirm picks. Cast at a fish: the wobbler dives (longer for deeper fish), then you wait in the lure band. Confirm while waiting reels in.
- [ ] Pedal hard (about 80 % FTP) for 2 s in the menu. Expected: Drive on.
- [ ] Pedal navigation on (Settings): the menu scans every 1.6 s, a surge picks, nothing touched auto-picks after two cycles. Pedal navigation off: none of that.
- [ ] Turn around, drive back to the dock wall. Expected: the boat stops at the wall and the menu opens.

## 3. A fight: SIM -> ERG and the pulls

- [ ] After 5:00, wait for a bite. Expected: the switch to ERG has no power spike (the governor's ramped entry); the target is the fish's pull (shallows 60-75 %, reef up to about 90 %, shelf 90-100 %); increases never faster than about 25 W/s; a new pull every 8-16 s, ramped over about 3 s; nothing feels like a jolt.
- [ ] Note your power at one target at 75 and at 95 rpm. Expected: the same watts; the lower cadence feels heavier (the strain side of the band).

## 4. Runs, jumps and the giants

- [ ] Shelf runs (tuna, wahoo). Expected: up to about 104 %, never above 105 %, for 10-30 s, then straight back to the base pull.
- [ ] Deep jumps (swordfish, marlin). Expected: 104 % for 15-30 s, at least 90 s apart, never above 105 %.
- [ ] Giant grouper (deep, near the floor). Expected: 105-110 % for 3-4.5 minutes, never longer than 5 minutes; a second giant in the same session stays at or below 105 %.

## 5. Tension band readability

- [ ] Ride 10 rpm below the band, then 10 rpm above it. Expected: the strain meter fills in about 6 s, then the slack meter; a full meter snaps the line or throws the hook, and a replacement fish hooks itself 5 s later. The phase never ends early.
- [ ] Check readability at 1080p from the bike; try `relaxed_band` (22 rpm wide).

## 6. The Landing: ERG -> SIM and back to the menu

- [ ] Land a fish. Expected: SIM flat with no spike; the gaff meter fills only at or above 1.2 x FTP in the first 15 s (about 140 % of CP for 15 s makes a Trophy).
- [ ] The last-run haptic 3-6 s into the sprint: one bump (+3 % x your intensity) for 5 s; never in the first 5 minutes, never with haptics off.
- [ ] After 30 s you are back in the menu with fresh fish; ERG/SIM switches are always at least 30 s apart.

## 7. Rescue, pause, AFK

- [ ] In a fight at or above 60 %, drop below 45 rpm for 3 s. Expected: rescue (50 %), the meters freeze, the fish swims out, no pull change during the rescue; pulls resume about 10 s after you hold 70 rpm again.
- [ ] Stop pedaling while driving. Expected: the boat drifts; after 5 s the platform pauses you and the boat keeps drifting.

## 8. Time-up and the ride file

- [ ] Let `roam_10` run out during a fight. Expected: no new bites, the fight may finish (at most 5 minutes more), then the cool-down (3 minutes at 50 %) heads home.
- [ ] Save the ride and open the FIT (or upload it to Strava). Expected: laps Drive out, each Free roam stretch and each fish (species name), and the cool-down; the Strava title "WATTLANDS: Turbo Reel - Free Roam 10 min" and lines with fish caught, the biggest fish, points, rank and the furthest distance out.

## 9. Workouts and multiplayer

- [ ] `threshold`: the boat trolls during the Trolls (ERG at your `reel_pct`), four tuna at about 95 %, each fight 4-7 minutes.
- [ ] Two PCs (`docs/HARDWARE_TEST_PLAN.md` section 10): host `roam_30` with a bot, join. Expected: every boat on the same ocean, your camera on your boat; each rider's pull is a share of their own FTP.
- [ ] Kill the client mid-fight and restart it. Expected: its boat goes AFK (no pulls, no snap), it rejoins and the fight continues.

Log: date, trainer firmware, FTP (verified or not), preferred cadence, haptic intensity, pedal navigation on or off, and each step's result in the plan's template.
