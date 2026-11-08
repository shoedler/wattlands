# Turbo Reel: real-trainer checklist

The game's own checklist for a real KICKR CORE (BRIEF 4.7). `docs/HARDWARE_TEST_PLAN.md` holds the setup, the safety notes and the log template, and links here: work through its sections 1-8 first. Nothing here ran during the build (every automated run used MockTrainer with the hardware lock on). Start the app as that plan says (the exported build, or `tools/godot.ps1 --allow-hw --timeout=14400 --path .`), never from an automated run. Stop at the first failed safety check, and hold Backspace for 1 s (panic) whenever something feels wrong.

Before you start: set your FTP and preferred cadence in your profile, haptics on, and note whether your FTP is verified (an unverified FTP scales every ERG target by 0.85). Numbers are % of FTP.

## 1. Drive-out (warm-up, Free Roam)

- [ ] Start `roam_30` solo and pedal. Expected: SIM for the first 5 minutes, no ERG, no haptics, no bites; the resistance rises gently with boat speed (about 2.5 % grade at cruise, never above 3 %); the boat moves off the dock and speeds up with your power, the bow lifts when you hammer; at about 70 % FTP or more it climbs onto the plane (bow down to a flat ride, a little faster), the prop always in the water.
- [ ] Ease off below about 20 % FTP. Expected: the boat drifts to a stop within a few seconds and the resistance drops to flat; the menu chips appear next to the boat.
- [ ] Panic once while driving, then resume. Expected: trainer safe at once; the session goes on after resume.

## 2. The menu, casting, waiting

- [ ] Keyboard or gamepad: left / right moves the highlight, confirm picks. Cast at a fish: the wobbler dives (longer for deeper fish), then you wait in the lure band. Confirm while waiting reels in.
- [ ] The jig: cast after 5:00 and pedal at about 60 % FTP inside the lure band. Expected: the trainer stays in SIM the whole wait, with no change in load at all (no ERG, no jolt) while the panel says "Jig it home"; the lure comes back to the boat over about 40 s (the bar fills, the distance counts down), then casts out again to the same spot and the wait goes on. "Hold" reads 40 % of your FTP in watts; "now" turns orange under it and "In: bites come sooner" dims when you leave the band or drop under it. Bites should come about every 15-20 s with the jig on and every 25-35 s without it.
- [ ] Pedal hard (about 80 % FTP) for 2 s in the menu. Expected: Drive on.
- [ ] Pedal navigation on (Settings): the menu scans every 1.6 s, a surge picks, nothing touched auto-picks after two cycles. Pedal navigation off: none of that.
- [ ] Turn around, drive back to the dock wall. Expected: the boat stops at the wall and the menu opens.

## 3. A fight: SIM -> ERG and the pulls

- [ ] After 5:00, wait for a bite. Expected: the switch to ERG has no power spike (the governor's ramped entry); the target is the fish's pull (shallows 60-75 %, reef up to about 90 %, shelf 90-100 %); increases never faster than about 25 W/s; a new pull every 8-16 s, ramped over about 3 s; nothing feels like a jolt.
- [ ] Note your power at one target at 75 and at 95 rpm. Expected: the same watts; the lower cadence feels heavier (the strain side of the band).

## 4. Runs, jumps and the giants

- [ ] Shelf runs (tuna, wahoo). Expected: up to about 104 %, never above 105 %, for 10-30 s, then straight back to the base pull.
- [ ] Deep jumps (swordfish, marlin). Expected: 104 % for 15-30 s, at least 90 s apart, never above 105 %.
- [ ] Surges (a tuna or anything of 30 kg or more starts a run or jump, after 5:00, haptics on). Expected: one short tug, about +50 % x your intensity on top of the ERG target for 2 s, never above 150 % FTP, at most one per 15 s; the rod jerks and the line snaps taut. With haptics off: the cue, no tug. If the platform has no haptic pull yet, no tug and the session goes on.
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
- [ ] Stop pedaling while driving. Expected: the boat drifts; after 10 s the platform pauses you and the boat keeps drifting.

## 8. Time-up and the ride file

- [ ] Let `roam_10` run out during a fight. Expected: no new bites, the fight may finish (at most 5 minutes more), then the cool-down (3 minutes at 50 %) heads home.
- [ ] Save the ride and open the FIT (or upload it to Strava). Expected: laps Drive out, each Free roam stretch and each fish (species name), and the cool-down; the Strava title "WATTLANDS: Turbo Reel - Free Roam 10 min" and lines with fish caught, the biggest fish, points, rank and the furthest distance out.

## 9. Workouts and multiplayer

- [ ] `threshold`: the boat trolls during the Trolls (ERG at your `reel_pct`), four tuna at about 95 %, each fight 4-7 minutes.
- [ ] Two PCs (`docs/HARDWARE_TEST_PLAN.md` section 10): host `roam_30` with a bot, join. Expected: every boat on the same ocean, your camera on your boat; each rider's pull is a share of their own FTP.
- [ ] Kill the client mid-fight and restart it. Expected: its boat goes AFK (no pulls, no snap), it rejoins and the fight continues.

## 10. Listen

No machine can judge these, so they stay open until someone has ridden with sound on. First play `build/audio_preview/fishing.mp3` (`node tools/audio/preview.mjs --game=fishing`) on the speakers you ride with.

- [ ] Pedal at 60, then 110 rpm while driving. Expected: one putt per foot, in step with the crank on screen; it stops as soon as the reading reaches 0 (on a real KICKR that lags your feet by up to about a second, BRIEF 4.5; the sound locks to the screen).
- [ ] Sprint, then lift off. Expected: the gear whistle and crackle rise with your power; lifting off burbles once, even if you keep easing off. Stop dead instead: no burble after the crank stands still.
- [ ] Land a fish. Expected: a clunk as the clutch lever flips back to the prop. Pause at speed: the engine stops, and the sea does not keep slapping as if the boat still ran.
- [ ] Reel in a fight. Expected: the ratchet and the line's creak keep time with your feet; the line sings higher as the pull rises, the rod groans near the top; on a run the clicks stop and the drag screams.
- [ ] Ride the boat out of the harbour. Expected: gulls and rigging fade with the dock; the open sea has swell, foam, wind by speed and an occasional far gull. Do the waves read as waves and the gull as a gull?
- [ ] Trigger a rescue (section 7) in a fight on a run, and a warning while cruising near other boats. Expected: the safety prompt is plainly over everything, and the mix dips under it.
- [ ] Hold 250 W for several minutes on a long crossing. Expected: the engine and the water rise and fall every few seconds with a hull slap off the waves, with no tape-like repeat in the wash, and the strokes stay on the crank.
- [ ] Reach a Landing. Expected: a call at the start of the gaff sprint, and the catch's fanfare 15 s later. Snap a line in a fight: the new fish hooks itself aloud 5 s on.
- [ ] Wait for a bite with another rider far off. Expected: the bell you hear loud is yours.
- [ ] After an hour: is the tick a texture, or does it tire? Note the balance over your fan and trainer, and any setting you changed in the audio sliders.

## 11. The crew strips and the big game trip

- [ ] Two PCs: while the other rider fights, a strip under the leaderboard shows their fish, the line out, a reel bar, "Target N W" and "now N W" (orange when more than 5 % off their target); it stays up while you fight yourself, next to your own fight panel, and goes away when their fish is landed or lost.
- [ ] A joined rider's fight panel shows the cadence band lit with its limits, like the host's.
- [ ] `big_game_30` solo: the same 5 minute SIM drive-out; past it every cast is a tuna or a giant grouper (groupers on the floor), the zone tag says Bluewater, and the first giant grouper is the only one over 105 % FTP for the session, as in the open sea. Check the grouper's 3-4.5 minute fight against your comfort at 105-110 % before trusting it in a room.

Log: date, trainer firmware, FTP (verified or not), preferred cadence, haptic intensity, pedal navigation on or off, and each step's result in the plan's template.
