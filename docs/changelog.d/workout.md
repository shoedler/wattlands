### Changed (Workout) v0.2.0

- Workout is pixel art now, on a 960 × 540 base that flexes with the window: real riders on bicycles instead of flags, up to 8 in a loose group, each by the slot's jersey and whip pennant, with a caret over your own helmet.
- Legs, cranks and chain turn 1:1 on each rider's own cadence, from one crank clock, and stop dead when the rider coasts, disconnects or the session pauses. Wheels and spokes turn by speed. Riders stand out of the saddle in sprints and on steep climbs, sit up in rescue and AFK, and put a foot down when stopped.
- One morning per ride: blue hour to clear day through a colour table, with stars, lit windows and mist that burns off; parallax hills, poplars, farmhouses, wind pumps, cattle, poles, a painted earth bank, and seeded flocks, a tractor and a balloon.
- A roadside crowd and a gantry at scored sprints, never in the warm-up.
- A new HUD in an enamel road-sign look: timeline, my numbers with a crank icon that turns with your legs, the crew and the score. Watts are a 3 s mean through `HudRiderNumbers`; stale power shows `--`. The kit widgets are gone from Workout.
- A help overlay on F1 and on a rider's first session of the game.
- A regenerated picker card. Rules, session plans, snapshots and balance are unchanged.

### Added (Workout)

- Workout, the reference game (BRIEF 3.7): a group interval ride for 1–8 riders with bots, where everyone rides the same timeline at their own % FTP.
- Sessions Easy 30 (default, first-run and zero-input), Sweet spot, Threshold, VO2, Rolling road (30 minutes of SIM on a seeded rolling course, −2% to +6%), E2E (2 minutes inside the warm-up limits) and a sample `.zwo`; `--content=zwo:<path>` imports any `.zwo` file, with its clamps in the session preview.
- Time in band per interval and rider (ERG ±5% of the applied target, Rolling road 76–105% FTP, sprints cadence ≥ 60 rpm), sprint scoring at 1.2 × FTP, group grade S–D, kJ, average and normalized power, best 1/5/20-minute power, XP, levels and cosmetic pennant unlocks.
- A 640 × 360 side-scrolling ride view: parallax landscape, one pennant per rider (slot color, shape and pattern), the course profile in Rolling road and the interval blocks on the ground; HUD layout with timeline, power gauge, cadence, W′, teammate strip, big readouts and the gear indicator; a procedural picker card.

### Changed (Workout)

- A client's ride view draws the other riders between snapshots, behind the newest by the snapshots' mean spacing (100 ms at 10 Hz, about 1 s under the 8-rider load), and the local rider from its own prediction, blended softly toward the host and never moving backwards (BRIEF 5.1).
