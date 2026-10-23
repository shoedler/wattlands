# Wattlands

Wattlands is a multiplayer fitness party app for the Wahoo KICKR CORE (and KICKR CORE 2). Your pedaling is the controller and the trainer pushes back: games use ERG for steady work and simulation mode for sprints. A host shares a short room code and friends join with it; there are no accounts. Every ride is saved as a FIT file and can go to your own Strava account.

## Games

| Game | Players | What it is |
| --- | --- | --- |
| **Turbo Reel** | 1-4 | Co-op sport fishing. Your bike turns the big-game reel; the trainer holds the fish's pull, and keeping your cadence in the band tires it. The first-run game. |
| **Castellum Rotae** | 1-4 | Co-op tower defense on a Roman hill fort. Your watts turn a treadwheel; send them to the towers or the generator. |
| **Workout** | 1-8 | Group interval rides, sprints, a rolling road and `.zwo` import. |
| Diesel Domestiques | 1-3 | Coming next: crew a pedal-powered super-heavy tank, one engine per rider (brief in `docs/games/tank.md`). |

> Status: built and tested with mock trainers only, without a real KICKR and without the real Strava API. Follow `docs/HARDWARE_TEST_PLAN.md` and each game's `src/games/<id>/HARDWARE_TEST.md` before riding hard on it.

## Quick start

1. Download the latest Windows zip from the [releases](https://github.com/shoedler/wattlands/releases), unzip the whole folder and run `Wattlands.exe` (Windows 10/11, x86_64).
2. Update the trainer's firmware with the Wahoo app, then close every other app that might connect to it (Zwift, the Wahoo app).
3. Pedal. With no input at all, 20 seconds of pedaling on the title screen creates a profile and starts a ride. Every menu and game works with no input: the focus moves every 1.6 s, a short surge picks, coasting for 3 s goes back (outside ERG).
4. Set your FTP in the profile, or run the FTP test in Settings. Until it is verified, every ERG target is lowered by 15%.

## Playing together

Multiplayer goes through a small relay that every rider's PC can reach.

1. One PC runs the relay: `node server/relay/src/main.ts` from this repository (port 8787), or `docker build -t wattlands-relay server/relay` and `docker run -p 8787:8787 wattlands-relay`. Allow port 8787 through the firewall.
2. Every rider sets Settings > Network > Relay URL to `ws://<relay PC's address>:8787/v1`. A build exported with `--relay-url=<url>` has that relay as its default, so its riders change nothing.
3. The host picks a game, chooses Host and reads out the room code; friends choose Join and type it. A rider who drops can rejoin with the same code within two minutes.

Friends in another place: the relay must be reachable from their PC. The simplest way is Tailscale: share only the relay PC with your friend (they use their own Tailscale account) and use its Tailscale address (`tailscale ip -4`) in the Relay URL. A hosted relay works too (`server/relay/fly.toml`, `render.yaml`, then `wss://<host>/v1`). Everyone must run the same release.

## Controls

| Action | Keyboard | Xbox controller |
| --- | --- | --- |
| Move | Arrows or WASD | Left stick or D-pad |
| Confirm / Back | Enter or Space / Esc | A / B |
| Ability 1 / 2, Item, Swap | 1 / 2, F, R | X / Y, RB, LB |
| Virtual gears down / up | Q / E | LT / RT |
| Pause | P | Start |
| Panic (trainer to safe at once) | Hold Backspace 1 s | View + Menu |

Bindings can be changed in Settings > Controls. The session screen also has an on-screen PANIC button. Zwift Click or Play buttons can be mapped to these keys with BikeControl.

## Strava

Uploads use your own Strava API application: create one at https://www.strava.com/settings/api (callback domain `localhost`), enter its Client ID and Secret in Settings > Strava and choose Connect. Then upload from the results screen or turn on auto-upload. Rides are always saved as FIT files in your profile's `rides/` folder.

## Troubleshooting

- "Another app may hold control": close Zwift, the Wahoo app and any other trainer app, then reconnect.
- The trainer won't connect: remove any Windows-level Bluetooth pairing of it, keep it close, and update its firmware (Wattlands needs FTMS).
- No Bluetooth trainers at all on a fresh PC: install the Microsoft Visual C++ 2015-2022 x64 runtime (https://aka.ms/vs/17/release/vc_redist.x64.exe).
- Host fails or friends can't join: check that the relay runs and that every Relay URL points at it.

## For developers

Read `CLAUDE.md`, then `docs/ARCHITECTURE.md` and `docs/GAME_SDK.md`. Godot 4.7.2 runs only through `tools/godot.sh` (or `tools/godot.ps1`), which sets the hardware and network locks.

```bash
tools/godot.sh --path . -- --mock-trainer=erg
```

```bash
tools/run_tests
```

```bash
node tools/export_windows.mjs --smoke
```

The first runs the app with a mock trainer, the second runs every gate, the third builds `build/windows/` (with a standard Godot 4.7.2 editor and its export templates; see `docs/deps.d/godot.md`). New games start with `tools/new_game <id>`; game briefs live in `docs/games/`.

## License

MIT, see `LICENSE`. Third-party code and assets are listed in `CREDITS.md`, `docs/DEPENDENCIES.md` and `docs/THIRD_PARTY_NOTICES.txt`.
