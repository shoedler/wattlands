# Wattlands

Wattlands is a multiplayer fitness party app for the Wahoo KICKR CORE and KICKR CORE 2 smart trainers. Your pedaling is the controller and the trainer pushes back: games use ERG mode for steady work and simulation mode for sprints. One app hosts several games; a host shares a short room code and friends type it to join. There are no accounts. Every ride is saved as a FIT file and can go to your own Strava account.

This is version 0.1.0: the platform and the reference game, Workout. Generator Siege, Tank Crew and Big Game Fishing are built later from their briefs in `docs/games/`.

> Status: built in one autonomous run without a real trainer. Follow `docs/HARDWARE_TEST_PLAN.md` before riding hard on it.

## Quick start (players)

1. Update your trainer's firmware with the Wahoo app (current firmware is needed for FTMS control and safe mode switches), then close every other app that might connect to it (Zwift, the Wahoo app).
2. Start Wattlands. It connects to your last trainer on its own; the first time, pick it from the list in Settings.
3. Pedal. With no input at all, 20 seconds of pedaling on the title screen creates a profile called Rider (FTP 200 W, marked unverified) and starts an easy Workout. Holding a steady pedal for 5 seconds on the title screen starts your last game solo.
4. Set your FTP in the profile, or run the FTP test in Settings. Until it is verified, every ERG target is lowered by 15%.
5. To ride together: pick a game, choose Host, and read the room code (like `K7Q-X2M`) to your friends. They choose Join and type the code; dashes, spaces and case don't matter.

Every menu, game, shop and results screen works with no input: focus moves through the options every 1.6 seconds, a short surge in effort picks the highlighted option and coasting for 3 seconds goes back.

## Controls

| Action | Keyboard | Xbox controller |
| --- | --- | --- |
| Move | Arrows or WASD | Left stick or D-pad |
| Confirm | Enter or Space | A |
| Back | Esc | B |
| Ability 1 / 2 | 1 / 2 | X / Y |
| Item | F | RB |
| Swap | R | LB |
| Shift down / up (virtual gears) | Q / E | LT / RT |
| Pause | P | Start |
| Panic (trainer to safe at once) | Hold Backspace 1 s | View + Menu together |

Every binding can be changed in Settings and is saved to `input.cfg` in your profile folder.

Pedal gestures: pedaling for 3 seconds starts things; a surge (about 30% above your recent power for a second and a half, or a burst of flywheel speed in ERG) confirms; coasting for 3 seconds goes back (never during ERG); stopping for 5 seconds pauses a solo ride.

### Zwift Click and Zwift Play buttons

Wattlands reads keyboard and controller input, so you can map Zwift Click or Zwift Play buttons to its keys with BikeControl (open source): map the buttons to Q and E for virtual gears, Enter for confirm and Esc for back. Zwift's own virtual shifting only works inside Zwift; Wattlands has its own 24 virtual gears.

## Strava

Uploads go to your own Strava account through your own Strava API application, so your client secret stays on your PC.

1. Go to https://www.strava.com/settings/api and create an application. Set the Authorization Callback Domain to `localhost`.
2. In Wattlands, open Settings, Strava, and enter the application's Client ID and Client Secret. Choose Connect and approve in the browser.
3. After a ride, choose Upload to Strava on the results screen, or turn on auto-upload. Rides appear as virtual rides with power and cadence. Failed or offline uploads wait in a queue and retry on the next launch.

New Strava API applications serve a single athlete at first (up to 10 without review), so each rider who wants uploads should create their own application. Rides are always saved as FIT files under your profile folder whether or not you use Strava.

## Troubleshooting

- "Another app may hold control": close Zwift, the Wahoo app and any other trainer app, then reconnect.
- The trainer is not found or won't connect: remove any Windows-level Bluetooth pairing of the trainer (Settings, Bluetooth & devices), keep it within a few metres, and make sure no other app is connected.
- Mode switches feel abrupt or power spikes: update the trainer firmware. Wattlands ramps every switch between ERG and simulation, but firmware before 1.5.5 could spike on switches.
- Panic: hold Backspace for one second (or View + Menu): ERG turns off and the grade goes flat at once.

## For developers

Read `CLAUDE.md` first, then `docs/ARCHITECTURE.md` and `docs/GAME_SDK.md`. Every Godot run goes through `tools/godot.sh` (Git Bash) or `tools/godot.ps1` (PowerShell), which hold the safety locks and a machine-wide lock on concurrent Godot processes.

```bash
tools/run_tests
```

The full gate suite: GUT unit, simulation and SDK tests, the script check, and the Node suites. More commands (the app with a mock trainer, the relay, the mock Strava server, a game simulation, the art pipeline's dry run) are in `docs/GAME_SDK.md` and the final sections of this README once the build completes.

## License

MIT, see `LICENSE`. Third-party code and assets are listed in `CREDITS.md` and `docs/DEPENDENCIES.md`.
