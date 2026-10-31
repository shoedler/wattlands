# Changelog: discard-ride

- The ride menu has "Discard the ride" under End/Leave, in every game. After a "Keep riding / Yes, discard" confirm nothing from the ride is kept for that rider: no FIT, no Strava upload, no ride history entry, no results screen, no progress; it goes to the title, and a rider still spinning there starts no new ride until they stop. "Yes, discard" takes the keyboard or gamepad: pedals never pick it. A client leaves; a host ends the session for everyone, and the other riders keep their results and FITs.
- A client whose host leaves right after sending the results now gets them, even when the leave arrives in the same network poll.
