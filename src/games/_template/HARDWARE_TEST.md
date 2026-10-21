# Template: real-trainer checklist

The game's own checklist for a real KICKR CORE (BRIEF 4.7). `docs/HARDWARE_TEST_PLAN.md` holds the
setup, the safety notes and the log format, and links here. Run each step with the locks dropped as that
plan says (`--allow-hw`), never from an automated run. Rewrite this file for your game: one row per plan
phase type, mode switch, directive pattern and haptic it uses.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 1 | Start `default` solo with the trainer connected; pedal | The warm-up ramps the ERG target from 50% to 65% FTP over 5 minutes, slewed | |
| 2 | Enter the WORK phase | ERG at 75% FTP (x 0.85 if your FTP is unverified), rising at most 30 W/s | |
| 3 | 60 s into WORK | The target rises 5% for 30 s, then returns to 75% at once | |
| 4 | Drop cadence below 45 rpm for 3 s in WORK | Rescue: 50% FTP, a stagger toast, the marker waits; cadence >= 70 rpm for 3 s ramps back over 10 s | |
| 5 | Stop pedaling for 10 s | The floor after 3 s, pause after 10 s (solo) | |
| 6 | Panic (Backspace held 1 s) | ERG off at once; the trainer stays safe until you resume | |
| 7 | Finish the cool-down and save the ride | A FIT with laps: warm-up, WORK, the lap marker, cool-down | |

Log: date, trainer firmware, FTP, verified or not, and each step's result.
