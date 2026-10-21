# App shell

## Added

- Main scene that shows the screen for `App.state`. At launch it loads the profile, applies the saved master volume, starts the trainer backend and retries the upload queue.
- Title screen with zero-touch start:
  - Hold pedaling 5 s to ride the last-played game solo.
  - On a first run, 20 s of pedaling creates the profile "Rider" (FTP 200, unverified) and starts the first-run game from the GameRegistry. A pause in pedaling restarts the 20 s instead of cancelling them.
  - Back on the title after a ride, spinning on never starts another ride: the 5 s hold starts after a stop.
- First-run, profile and settings screens. Settings covers:
  - trainer scan, connect and mock;
  - Strava client ID, secret, connect, disconnect and auto-upload;
  - haptics, control rebinding, volume and metronome;
  - relay URL, pedal-scan menus and scan interval.
- Game picker with picker images or generated title cards, summaries and player counts.
- Lobby for solo, hosting and joining:
  - The room code is shown as K7Q-X2M.
  - Code entry has an on-screen keyboard for controller and pedal-scan; a coast keeps a half-typed code.
  - Content, scaling and every game option type; int steppers stay on the option's step grid.
  - Player options and a per-session Autopilot toggle on the rider's own card.
  - Bots and the bot FTP, trainer status and ready-up per rider, and the session preview.
  - Clear messages for refusals.
  - A client resends player_info only when it changed, such as when the host changes the scaling mode, so lobby_state echoes never loop.
- Session screen around the GameHost:
  - a pause overlay (after a coasting pause, the first surge resumes);
  - an on-screen panic button;
  - the cadence metronome when it is on.
- Results screen with grade, rows, XP, unlocks, the saved ride and Upload to Strava (auto-upload honoured). A session without results shows no grade.
- Scripted peers for the end-to-end test: `--host`, `--join=<code>`, stdout lines, report JSON and exit codes. A session without results, or `--strava-auto-upload` without a Strava connection, exits 1.
- P1: Recent rooms, a LAN room list (when NetSession provides one), rides history with re-upload, and the FTP test.
- The Controls page in Settings has a Reset to defaults row (Keep / Reset confirm) that brings back every default binding, Esc and B included, and saves input.cfg; the page says Esc or B cancels a capture. Autopilot switched on in the lobby turns pedal-scan on for the lobby, the session's pause menu and results. Settings pages taller than the screen (Controls; Strava at 1080p) scroll so the highlighted row stays in view.
