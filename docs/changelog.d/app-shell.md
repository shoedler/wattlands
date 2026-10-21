# App shell

## Added

- Main scene that shows the screen for `App.state` and boots the profile, the trainer backend and the upload queue.
- Title screen with zero-touch start: hold pedaling 5 s to ride the last-played game solo; on a first run, 20 s of pedaling creates the profile "Rider" (FTP 200, unverified) and starts the first-run game from the GameRegistry.
- First-run, profile and settings screens (trainer scan, connect and mock; Strava client ID, secret, connect, disconnect and auto-upload; haptics; control rebinding; volume and metronome; relay URL; pedal-scan menus and scan interval).
- Game picker with picker images or generated title cards, summaries and player counts.
- Lobby for solo, hosting and joining: room code shown as K7Q-X2M, an on-screen keyboard for controller and pedal-scan, content, scaling, every game option type, player options on the rider's own card, bots and the bot FTP, trainer status and ready-up per rider, the session preview, and clear messages for refusals.
- Session screen around the GameHost with a pause overlay and an on-screen panic button.
- Results screen with grade, rows, XP, unlocks, the saved ride and Upload to Strava (auto-upload honoured).
- Scripted peers for the end-to-end test (`--host`, `--join=<code>`, stdout lines, report JSON, exit codes).
- P1: Recent rooms, a LAN room list (when NetSession provides one), rides history with re-upload, the FTP test.

## Fixed

- A client no longer answers the host's lobby_state echo with another player_info. That loop happened for games without player options. A client now resends player_info when the host changes the scaling mode.
- On the first run, a pause in pedaling restarts the 20 s countdown instead of cancelling it.
- After a coasting pause, the first surge resumes the ride; it can no longer pick End ride or Panic.
- The on-screen keyboard keeps a half-typed code when the rider coasts: the first back only highlights Back.
- Int option steppers stay on the option's step grid.
- A session that ended without results shows no grade. A scripted peer exits 1 in that case.
- A scripted peer with --strava-auto-upload but no Strava connection exits 1 at once instead of waiting 150 s.

## Added

- A per-session Autopilot toggle on the lobby, shown on the rider's card.
- The cadence metronome plays during sessions when it is on in Settings.
- The saved master volume is applied at launch.
