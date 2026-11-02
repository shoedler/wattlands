![WATTLANDS: pixel-art scenes from the four games, with the name across the middle](assets/readme/hero.png)

# Wattlands

Party games for your smart trainer. You pedal, the game reacts, and the trainer pushes back: a fish pulls on the line, a shell forces a sprint, a wave of attackers becomes an interval. It runs on Windows 10/11 with a Wahoo KICKR CORE or KICKR CORE 2.

There are four games in one app. Someone hosts, reads out a room code, and friends join with it. No accounts. Riders of different strength can share a session because every target is a percentage of your own FTP, and the host can add bots to fill the empty seats.

| | Riders | |
| --- | --- | --- |
| [Turbo Reel](#turbo-reel) | 1-4 | Sport fishing on a shared ocean |
| [Castellum Rotae](#castellum-rotae) | 1-4 | Co-op tower defense, powered by treadwheels |
| [Workout](#workout) | 1-8 | Group intervals on a country road |
| [Torque Company](#torque-company) | 1-4 | Crew a pedal-powered landship at night |

## Getting started

Grab the Windows zip from the [releases page](https://github.com/shoedler/wattlands/releases), unzip the whole folder and run `Wattlands.exe`. Close Zwift, the Wahoo app and anything else that might hold the trainer, and make sure its firmware is current.

Then pedal. Twenty seconds of pedaling on the title screen creates a profile and starts a ride, and every game can play through to the end without you touching anything. A new profile starts at an FTP of 200 W. Set yours in the profile or run the FTP test in Settings. Until it's verified, ERG targets are 15% lower.

If you'd rather stay on the bike with no keyboard in reach, turn on Settings > Pedal navigation. The focus moves by itself, a short surge picks, and coasting for 3 s goes back, except during an ERG phase.

Stop pedaling for 10 seconds and a solo ride pauses until you pedal again. In a group you're marked away, and the game only stops once every rider has. Bad day? The ride menu (Esc or P) can discard a ride so nothing from it is kept. It asks first, and Yes needs the keyboard or a controller, so a sprint can't throw your ride away by accident. If you're hosting, that ends the session for everyone, though the others keep their rides.

You can pair a Bluetooth heart rate strap in Settings > Trainer > Sensors. It shows next to your power and goes in your FIT file, and other riders never see it.

No trainer handy? Run `Wattlands.exe -- --mock-trainer` (or use Settings > Trainer > Use the mock trainer) to ride a simulated rider, and add `--mock-keyboard` to steer it. [docs/TRAINER.md](docs/TRAINER.md) has the keys.

## The games

### Turbo Reel

![Turbo Reel: a boat fights a giant grouper over an old wreck, with the fight panel showing target watts, cadence band and line](assets/readme/screen_turbo_reel.png)

Pedal your boat out of the harbour, past the shallows and the reef to the deep water where the big fish live. Cast at a fish you can see and the fight starts.

The trainer holds the fish's pull in ERG, and your cadence does the work. Spin too slowly and the line snaps, too fast and the hook comes out. Stay in the band and the fish tires. Get it to the boat and you have 15 s to sprint for the gaff. Fill the meter and it's a Trophy, worth half as much again.

Free Roam is a race for points over 10 to 60 minutes. Workouts follow a plan and everyone scores together.

### Castellum Rotae

![Castellum Rotae: the fort with four colored treadwheels driving its weapons, a siege tower on the road and the HUD on](assets/readme/screen_castellum_rotae.png)

A Roman fort has one gate and one road leading to it, and attackers are coming down that road. Each rider turns a great treadwheel and couples it to the gold mine, the tree ballista, the great onager, the arrow organ or the tar works.

Waves are ERG intervals and the breaks between them are for recovering and shopping. Overdrive is a 30 s sprint that doubles your output as long as you hold your FTP. A session takes 31 to 55 minutes.

### Workout

![Workout: four riders under a SPRINT gantry with a crowd at the roadside, and the HUD plates on](assets/readme/screen_workout.png)

The plain one, and the one for up to eight. Everyone rides the same timeline at their own percentage of FTP, on a country road that goes from the blue hour to full daylight over the session. A crowd and a gantry turn out for scored sprints.

Sessions run 28 to 40 minutes: an easy ride with three sprints, sweet spot, threshold, VO2 and a rolling road. To ride your own, drop `.zwo` files in `%APPDATA%\Godot\app_userdata\WATTLANDS\workouts` and pick them under Ride in the lobby, which shows the path too.

### Torque Company

![Torque Company: the split screen, with the landship in a cutaway on the left, enemy tanks far off on the right, a shell in flight and a SURGE TO EVADE warning](assets/readme/screen_torque_company.png)

Up to four riders crew a landship through a starry forest night. The enemy stands 800 to 2400 m away, so the screen splits: your tank and the road on one side, a long-lens view of the enemy's armour on the other.

There are six seats (Drive, Gun, Loader, Lights, Secondaries, Repairs), and each one is a machine with its own feel on the trainer. Change seats whenever one is free or held by a bot and your load follows you, though a move between ERG and SIM can wait for the 30 s gap between mode switches. A plain shot gives you the 1.4 to 4 s of its flight. A telegraphed one glows first, so you get at least 6 s even on Hard, and if you're on a SIM seat (Drive, Loader, Secondaries), holding a sprint for 2 s makes it miss, 3 s against the Behemoth. There's no button for it.

The host picks Easy, Normal or Hard, which changes the enemy and the repair rate. It never changes your effort plan or its limits, though a longer fight on Hard can hold your target higher for longer. Ambush is about 15 minutes with about 6 of hard fighting, and on its default Hard you should expect to lose the tank once or twice. The ride carries on regardless. Ashfall Road takes 30 to 41 minutes, and free roam 10 to 60.

## Riding safely

This is hard exercise on a machine that pushes back. You ride at your own risk, and the software comes with no warranty ([LICENSE](LICENSE)). If you're not sure hard efforts are right for you, ask a doctor first.

Everything that changes the load goes through one safety governor on your own PC. Other riders' machines can only ask, and yours decides. These are the limits it holds in every game:

| | |
| --- | --- |
| Ramps | In ERG the target rises by at most 30 W per second and drops at once. The one exception is a haptic pull, which adds up to 50% of FTP at once for at most 3 s. In SIM the load follows the grade, and haptics add at most +3% for at most 8 s. Settings > Haptics turns all haptics off. |
| Warm-up | For your first 5 minutes of riding, ERG stays at or under 65% of FTP, grade between -2% and +3%, and haptics are off. The count starts at your first pedal stroke and starts over after 20 minutes off the bike. You can skip this in your profile. |
| Rescue | In ERG at 60% of FTP or more, if cadence falls under 45 rpm for 3 s or power under 75% of target for 5 s, the target drops to 50% of FTP. Back at 70 rpm for 3 s and it ramps up again over 10 s. A game never ends your ride for this. |
| Hard efforts | ERG tops out at 150% of FTP, with at most 5 minutes above 105% and 1 minute above 120%. After that it holds you down until you've ridden 2 minutes at 90% or less. The FTP test lifts these limits up to 1000 W or your trainer's maximum, since it ends when you fade. |
| Coasting | After 3 s, ERG drops to 30% of FTP or 50 W, whichever is higher. After 10 s a solo ride pauses, and in a group you're marked away. |
| Panic | Hold Backspace for 1 s, or View + Menu on a controller. The app sets the trainer to a flat road at once and holds it there until you resume. |
| Exit | The app sets the trainer flat and lets go of it. |

The app can only do this while it's running and connected. After a crash, a killed app, a PC going to sleep or a lost Bluetooth link, the trainer may keep its last load. Stop pedaling, and switch the trainer off at the wall if you need to.

Keep the trainer's firmware current: before version 1.5.5, a switch between ERG and SIM could spike to 2000 W.

None of this replaces your own judgement. If something feels wrong, stop pedaling.

## Playing together

Someone chooses Host a room and picks a game, then reads out the room code. Everyone else chooses Join a room and types it. On one network, that's all: the host's PC runs the room and the others find it by its code. The first time, Windows may ask to let Wattlands through the firewall. Allow it on private networks, on the host's PC and on the others.

If a friend's PC can't find the room, or they're elsewhere and share a VPN with you (Tailscale is the easy one), the host's lobby shows an address. They enter it in Settings > Network > Relay, then join with the code. Clear that setting to go back to finding rooms on your own network.

If you drop out you have two minutes to rejoin with the same code. If the host's app closes, the session ends and everyone keeps their ride. Everyone needs to be on the same release.

### Running a relay

For friends elsewhere with no VPN, one of you can run a small relay on a machine everyone can reach. It needs this repository and Node 22.18 or newer:

```bash
node server/relay/src/main.ts
```

It listens on port 8787, so allow that through your firewall. There's a Dockerfile too, and [fly.toml](server/relay/fly.toml) and [render.yaml](server/relay/render.yaml) if you'd rather host it. [Its README](server/relay/README.md) has the limits and settings.

Everyone then sets Settings > Network > Relay to `ws://<relay address>:8787/v1`, or `wss://<host>/v1` for a hosted one. With a relay, a host who drops out gets two minutes to come back before the room closes.

## Controls

| | Keyboard | Xbox controller |
| --- | --- | --- |
| Move | Arrows or WASD | Left stick or D-pad |
| Confirm / Back | Enter or Space / Esc | A / B |
| Ability 1 / 2, Item, Swap | 1 / 2, F, R | X / Y, RB, LB |
| Virtual gears down / up | Q / E | LT / RT |
| Pause | P | Menu |
| Panic | Hold Backspace 1 s | View + Menu |
| Help | F1 | Left stick click |
| Fullscreen | F11 or Alt+Enter | |

Rebind them in Settings > Controls. Zwift Click and Play buttons can map to these keys through BikeControl.

## Your rides and Strava

Every ride is saved as a FIT file in `%APPDATA%\Godot\app_userdata\WATTLANDS\rides`. To upload to Strava, create your own API application at https://www.strava.com/settings/api with the callback domain `localhost`, enter its Client ID and Secret in Settings > Strava, and choose Connect. Then upload from the results screen or turn on auto-upload.

## If something doesn't work

"Another app may hold control" means just that: close Zwift, the Wahoo app and any other trainer app, then reconnect.

If the trainer won't connect, remove any Windows Bluetooth pairing of it, keep it close and update its firmware. Wattlands talks to it over FTMS.

On a fresh PC with no Bluetooth trainers showing at all, install the [Visual C++ x64 runtime](https://aka.ms/vs/17/release/vc_redist.x64.exe).

If friends can't find your room, make sure Windows lets Wattlands through the firewall on both PCs and that you're on the same network, then try the address the lobby shows. If you use a relay, check it's running and that everyone's Relay setting points at it.

## Contributing

The game is written in Godot 4.7.2 and GDScript. Art and sound are generated from code and recipes in this repository, with no sample packs and no image or audio service at runtime. The one starting point that isn't code is the reference image behind Torque Company's landship and forest, made from a prompt, which scripts rebuild as pixel art. Turbo Reel's style follows a pixel-art guide image, and nothing from it ships. An early image-model attempt at Turbo Reel's sprites was thrown out, and no shipped art comes from one.

[CONTRIBUTING.md](CONTRIBUTING.md) gets you from a clean clone to a pull request, with or without a trainer. To find your way around, start at [docs/README.md](docs/README.md). What changed and when is in the [changelog](CHANGELOG.md). To report a safety or security problem, see [SECURITY.md](SECURITY.md).

## License

MIT, see [LICENSE](LICENSE). Third-party code and assets are listed in [CREDITS.md](CREDITS.md), [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) and [docs/THIRD_PARTY_NOTICES.txt](docs/THIRD_PARTY_NOTICES.txt).
