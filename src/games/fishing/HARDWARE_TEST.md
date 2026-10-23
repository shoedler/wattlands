# Big Game Fishing: real-trainer checklist

The game's own checklist for a real KICKR CORE (BRIEF 4.7). `docs/HARDWARE_TEST_PLAN.md` holds the setup, the safety notes and the log template, and links here: work through its sections 1-8 first. Nothing here ran during the autonomous build (every automated run used MockTrainer with the hardware lock on). Start the app as that plan says (the exported build, or `tools/godot.ps1 --allow-hw --timeout=14400 --path .`), never from an automated run. Stop at the first failed safety check, and hold Backspace for 1 s (panic) whenever something feels wrong.

Before you start: set your FTP and preferred cadence in your profile, haptics on, and note whether your FTP is verified (an unverified FTP scales every ERG target by 0.85). The numbers below are % of FTP.

## 1. Ride out (warm-up)

- [ ] Start `free_30` solo and pedal. Expected: ERG ramps from 50% to 65% over 5 minutes, no SIM, no haptics, no bites; the practice band (preferred cadence +- 8 rpm) shows without meters; the boat motors forward (it sits a little right of its fishing spot on the ride out) with a foam wake trailing behind the stern, and eases back to the left edge when the first pick opens.
- [ ] Panic once during the ride out, then resume. Expected: ERG off at once; the trip goes on after resume.

## 2. Picking, casting, reeling

- [ ] At the first Reel, three spots appear. Pick with left / right, then confirm. Expected: the cast, then a Reel at your `reel_pct` (default 60%) for 2-4 minutes; the lure band follows your preferred cadence.
- [ ] Next cast, touch nothing. Expected: pedal-scan highlights each spot in turn and the pick auto-confirms after two cycles; before your first button press, strikes are set for you at 0.5 s.

## 3. Pulls and ramps (a Fight)

- [ ] Hook a fish (or play `threshold`, whose first tuna bites at 9 minutes). Expected: the Reel ends, ERG moves to the fish's pull (tuna about 93-97%), increases never faster than about 25 W/s (the governor's limit is 30 W/s), decreases at once.
- [ ] Hold the band for a minute. Expected: a new pull every 8-16 s, each change ramped over about 3 s in six small steps; the target never leaves the Fight's range; nothing feels like a jolt.
- [ ] Note your power at one target at 75 and at 95 rpm. Expected: the same watts; the lower cadence feels heavier on the pedals (more torque), which is the strain side of the band.

## 4. Runs and jumps

- [ ] Mahi run (`free_*`, a mahi fight). Expected: the drag screams, the target ramps to 105-110% for 15-30 s, the band shifts up, then the target drops straight back to the base pull at the run's end. At most 90 s above 105% in the whole fight.
- [ ] Tuna run (`threshold`). Expected: up to about base x 1.08 (<= 104.8%), never above 105%, for 20-30 s, then straight back.
- [ ] Marlin jump (`free_90` or `free_120`, if a marlin bites). Expected: jumps at 104% for 20-30 s, at least 90 s apart, never above 105%.

## 5. Tension band readability

- [ ] Ride 10 rpm below the band for a few seconds, then 10 rpm above it. Expected: the strain meter (red, zigzag) fills in about 6 s, then the slack meter (yellow, loop); a full meter snaps the line or throws the hook, and a replacement fish hooks itself 5 s later in the same phase. The phase never ends early.
- [ ] Check readability at 1080p from the bike: W and rpm are large (>= 48 px), the band and your cadence marker are easy to follow, the meters read at a glance. Try `relaxed_band` (22 rpm wide) in the player options.

## 6. The Landing: ERG -> SIM and back

- [ ] Land a fish. Expected: the switch to SIM (flat, virtual gears, the gear indicator) has no power spike: the governor first holds ERG at min(current, 3 s power), then SIM at grade 0. The cadence band is cleared.
- [ ] Gaff sprint, the first 15 s. Expected: the gaff meter fills only while you are at or above 1.2 x FTP; 15 s at about 140% of CP fills it (a Trophy). Gears change the feel, nothing else.
- [ ] The last-run haptic, 3-6 s into the sprint. Expected: one short bump (+3% grade x your intensity) for 5 s, never more than +3%; never in the first 5 minutes of a trip and never in `e2e_2min`.
- [ ] Haptics off (Settings), then land another fish. Expected: no bump at all.
- [ ] After 30 s, SIM -> ERG. Expected: grade 0, then ERG at or below the next Reel's target, slewing up; no spike. ERG/SIM switches are always at least 30 s apart.

## 7. Rescue during a fight

- [ ] In a Fight at or above 60%, drop below 45 rpm for 3 s. Expected: rescue (50% FTP, the rescue banner), the fish swims out, the meters freeze, no snap, no pull change during the rescue. Hold 70 rpm for 3 s: the target ramps back over 10 s, and pulls resume about 10 s later.
- [ ] Start a rescue in the middle of a mahi run. Expected: the run is cut short; after the rescue the target is the base pull, not the run's peak.
- [ ] Stop pedaling in a Fight. Expected: the floor after 3 s, pause after 10 s (solo); resuming continues the same fish.

## 8. Cool-down and the ride file

- [ ] Let `free_30` finish. Expected: when fishing time is up and no fight is on, the trip ends, the cool-down runs 3 minutes at 50%, the boats motor home; a running fight finishes first, with its Landing (at most about 5 minutes late).
- [ ] Save the ride and open the FIT (or upload it to Strava). Expected: laps "Ride out", each "Reel n" and each "<Species> n" that ran, and the cool-down; each Landing sits inside the lap of the Fight before it; a Virtual Ride with power and cadence.

## 9. Multiplayer

- [ ] Two PCs (the relay as in `docs/HARDWARE_TEST_PLAN.md` section 10): host `free_30`, join with the room code. Expected: equal lanes in slot order on both screens, your lane highlighted with your colour, pattern and "YOU"; each rider's pull is a share of their own FTP.
- [ ] Two fights overlapping for 10 s or more. Expected: a Double Hookup toast (left of the HUD panels, never over your timeline) and a short gold flash linking the lanes' rod tips that fades out within 2 s; the landed fish scores x 1.5.
- [ ] Kill the client mid-fight and restart it. Expected: its lane goes AFK (the fish waits, no snap, no pulls), it rejoins and the fight continues; its trainer only ever took commands from its own governor.

Log: date, trainer firmware, FTP (verified or not), preferred cadence, haptic intensity, and each step's result in the plan's template.
