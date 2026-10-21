# Backlog (P2 design notes)

Design notes only (BRIEF 1: P2 is never built in this run). Game-specific P2 notes live with each game (`src/games/<id>/README.md` or `BACKLOG.md`).

## Kart Rush (a future game)

- Versus for 2 to 8 riders, with bots filling slots: lane racing on a closed loop with 3 lanes and 3 laps.
- Elevation becomes course grade (`grade_source: course` or `game`), stacked by the governor (BRIEF 4.6.6).
- Drafting: 1 to 10 m behind another kart in the same lane cuts CdA by up to 30% and scales the `cw` factor sent to the trainer by the same factor (a relative factor in [0.5, 1.0], so it can only lower resistance).
- Position-weighted items (leaders get weaker ones): Tailwind, Headwind Cloud, Fender, Tow Rope. Every resistance effect is a haptic request to the receiver's governor (at most +3% for 8 s, 15 s cooldown), never a direct grade.
- Start: a neutral roll-out at ERG 60% FTP behind a pace car (warm-up content), then a ramped switch to SIM for the race.
- Results: positions, best lap, sprint peaks; grade from position and effort compliance; FIT laps per race lap.

## Platform

- Heart-rate strap support (0x180D) and HR-based balancing.
- A Wahoo Direct Connect (Bluetooth over TCP, DIRCON) backend for KICKR CORE 2 (`DirconTransport` behind `BleTransport`).
- OpenBikeControl input.
- Host migration when the host leaves (today the session ends gracefully).
- A Cloudflare Durable Objects relay (the Node relay's protocol is small enough to port).
- Uploads to intervals.icu or Garmin Connect next to Strava.
- Split screen with two trainers on one PC (two LocalRiders, two HUD lanes).
