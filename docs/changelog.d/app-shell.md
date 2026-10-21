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
