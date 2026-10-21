# Wattlands

Wattlands is a multiplayer fitness party app for the Wahoo KICKR CORE and KICKR CORE 2 smart trainers. Your pedaling is the controller and the trainer pushes back: games use ERG mode for steady work and simulation mode for sprints. One app hosts several games; a host shares a short room code and friends type it to join. There are no accounts. Every ride is saved as a FIT file and can go to your own Strava account.

This is version 0.1.0: the platform and the reference game, Workout (interval sessions, sprints, a rolling road and `.zwo` import). Generator Siege, Tank Crew and Big Game Fishing are built later from their briefs in `docs/games/`.

> Status: built in one autonomous run without a real trainer and without contacting the real Strava API. Follow `docs/HARDWARE_TEST_PLAN.md` before riding hard on it.

## Get the app

Wattlands runs on Windows 10/11 (x86_64). Build it once from this repository (the build is not committed):

1. Install Godot 4.7.2 (the standard editor, or the .NET editor as on this PC) and its Windows export templates (Editor, Manage Export Templates, or the `.tpz` from godotengine.org), and Node.js 22.12 or newer.
2. Put the path of Godot's console executable in `tools/godot_bin.local` (one line), or set `GODOT`.
3. Run:

```bash
node tools/export_windows.mjs --smoke
```

The build lands in `build/windows/`: `Wattlands.exe`, `Wattlands.pck`, the Bluetooth library `libgdble.windows.x86_64.dll`, `LICENSE.txt`, `CREDITS.md` and `THIRD_PARTY_NOTICES.txt`. Copy the whole folder. With the .NET editor the tool points the export at the installed standard template; `--template=<path to windows_release_x86_64.exe>` picks another one. `--with-vcruntime` also copies the Visual C++ runtime next to the exe (see Troubleshooting).

## Quick start (players)

1. Update your trainer's firmware with the Wahoo app (current firmware is needed for FTMS control and safe mode switches), then close every other app that might connect to it (Zwift, the Wahoo app).
2. Start `Wattlands.exe`. It connects to your last trainer on its own; the first time, pick it in Settings, Trainer.
3. Pedal. With no input at all, 20 seconds of pedaling on the title screen creates a profile called Rider (FTP 200 W, marked unverified) and starts an easy Workout. Holding a steady pedal for 5 seconds on the title screen starts your last game solo.
4. Set your FTP in the profile, or run the FTP test in Settings. Until it is verified, every ERG target is lowered by 15%.

Every menu, game, shop and results screen works with no input: focus moves through the options every 1.6 seconds, a short surge in effort picks the highlighted option, and coasting for 3 seconds goes back (outside ERG).

### Playing together

Multiplayer goes through a small relay server that every PC can reach. The app's default relay is `ws://localhost:8787/v1`, which only works on the PC that runs the relay.

1. One PC (or a hosted server) runs the relay. With Node.js: `node server/relay/src/main.ts` (it listens on port 8787 and prints its URL; on Node 22.12 to 22.17 add `--experimental-strip-types` after `node`). With Docker: `docker build -t wattlands-relay server/relay`, then `docker run -p 8787:8787 wattlands-relay`. Allow port 8787 through the firewall.
2. Every rider sets Settings, Network, Relay URL to `ws://<that PC's address>:8787/v1` (the relay PC itself can keep `ws://localhost:8787/v1`).
3. The host picks a game, chooses Host, and reads the room code (like `K7Q-X2M`) to the friends. They choose Join and type the code; dashes, spaces and case don't matter. Joining needs only the code.

A rider who drops can restart the app and join again with the same code within two minutes: they get their place back.

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

Every binding can be changed in Settings, Controls and is saved to `input.cfg` in your profile folder. The session screen also has an on-screen PANIC button.

Pedal gestures: pedaling for 3 seconds starts things; a surge (about 30% above your recent power for a second and a half, or a burst of flywheel speed in ERG) confirms; coasting for 3 seconds goes back outside ERG. Stopping for 5 seconds pauses a solo ride outside ERG; in ERG the trainer drops to its floor after 3 seconds and the ride pauses after 10.

### Zwift Click and Zwift Play buttons

Wattlands reads keyboard and controller input, so you can map Zwift Click or Zwift Play buttons to its keys with BikeControl (open source): map the buttons to Q and E for virtual gears, Enter for confirm and Esc for back. Zwift's own virtual shifting only works inside Zwift; Wattlands has its own 24 virtual gears.

## Strava

Uploads go to your own Strava account through your own Strava API application, so your client secret stays on your PC.

1. Go to https://www.strava.com/settings/api and create an application. Set the Authorization Callback Domain to `localhost`.
2. In Wattlands, open Settings, Strava, and enter the application's Client ID and Client Secret. Choose Connect and approve in the browser.
3. After a ride, choose Upload to Strava on the results screen, or turn on auto-upload in your profile. Rides appear as virtual rides with power, cadence and a lap per interval. Failed or offline uploads wait in a queue and retry on the next launch.

New Strava API applications serve a single athlete at first (up to 10 without review), so each rider who wants uploads should create their own application. Rides are always saved as FIT files under your profile folder (`rides/`) whether or not you use Strava.

## Troubleshooting

- "Another app may hold control": close Zwift, the Wahoo app and any other trainer app, then reconnect.
- The trainer is not found or won't connect: remove any Windows-level Bluetooth pairing of the trainer (Settings, Bluetooth & devices), keep it within a few metres, and make sure no other app is connected. If it still doesn't show up, update the trainer firmware with the Wahoo app: Wattlands talks to the trainer over the Bluetooth fitness machine service (FTMS), which older firmware doesn't offer.
- No Bluetooth trainers at all on a fresh PC: the Bluetooth library needs the Microsoft Visual C++ 2015-2022 x64 runtime. Install it from https://aka.ms/vs/17/release/vc_redist.x64.exe, or build with `node tools/export_windows.mjs --with-vcruntime`.
- Host fails or friends can't join: check that the relay runs and that everyone's Settings, Network, Relay URL points at it (see Playing together).
- Mode switches feel abrupt or power spikes: update the trainer firmware. Wattlands ramps every switch between ERG and simulation, but firmware before 1.5.5 could spike on switches.
- Panic: hold Backspace for one second (or View + Menu, or the on-screen PANIC button): ERG turns off and the grade goes flat at once.

## For developers

Read `CLAUDE.md` first, then `docs/ARCHITECTURE.md` and `docs/GAME_SDK.md`. Every Godot run goes through `tools/godot.sh` (Git Bash) or `tools/godot.ps1` (PowerShell). The wrappers set the hardware and network locks (`WATTLANDS_NO_HW_CONTROL=1`, `WATTLANDS_NO_NETWORK_INTEGRATIONS=1`) and hold a machine-wide lock on concurrent Godot processes. Only a human following `docs/HARDWARE_TEST_PLAN.md` passes `--allow-hw` or `--allow-network`.

Run the app from source with a mock trainer (no Bluetooth, no real Strava):

```bash
tools/godot.sh --path . -- --mock-trainer=erg
```

Run it from source with a real trainer and the real Strava API (hardware test plan only; the wrappers stop a run after 20 minutes unless `--timeout` says otherwise):

```bash
tools/godot.sh --allow-hw --allow-network --timeout=14400 --path .
```

Run every gate (GUT unit, contract, integration and scenario tests, the scaffold check, the script check, Workout simulations with FIT checks, the Node suites and the 3-peer end-to-end test):

```bash
tools/run_tests
```

Start the relay locally (on Node 22.12 to 22.17: `node --experimental-strip-types server/relay/src/main.ts`):

```bash
node server/relay/src/main.ts
```

Start the mock Strava server (tests only; point the app at it with `--strava-base=http://127.0.0.1:<port>`):

```bash
node server/mock_strava/server.mjs --port=8790
```

Simulate a game headless with mock riders and write a report and FIT files:

```bash
tools/run_game_sim --game=workout --content=e2e --players=1 --bots=1 --rider=erg --sim-speed=200 --seed=1 --report=build/sims/demo.json
```

Plan an art pipeline run without contacting fal (no key needed):

```bash
node tools/art/generate.mjs --game=demo --root=tools/art/examples --dry-run
```

Play the end-to-end test (relay, mock Strava, one host and two clients) for Workout:

```bash
node tools/e2e/run.mjs --games=workout
```

PowerShell twins exist for every tool (`tools/godot.ps1`, `tools/run_tests.ps1`, `tools/run_game_sim.ps1`, `tools/new_game.ps1`, `tools/screenshot.ps1`). New games start with `tools/new_game <id>`; `CLAUDE.md` explains the rest.

## License

MIT, see `LICENSE`. Third-party code and assets are listed in `CREDITS.md`, `docs/DEPENDENCIES.md` and `docs/THIRD_PARTY_NOTICES.txt`.
