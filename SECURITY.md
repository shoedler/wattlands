# Security and rider safety

Wattlands commands a real exercise machine, so a software bug here can hurt someone. Please report these privately.

## What to report privately

**Rider safety:**

- The trainer's load going above a limit in [Riding safely](README.md#riding-safely), or not dropping when it should.
- A way to reach the trainer that skips `SafetyGovernor`.
- A way for another rider, a host, a relay or a file to raise your load beyond those limits.
- Panic, rescue or the coasting floor not working.

**Security:**

- Anything a stranger can do to your PC or your data through the game, a relay, a room code, a `.zwo` file or a save file.
- Your Strava tokens or anything else from your profile leaving your machine.
- A crash or memory exhaustion another rider or a relay can cause on purpose.

## How to report

[Open a private report on GitHub](https://github.com/shoedler/wattlands/security/advisories/new). Tell us what happens, how to make it happen, the version, and for trainer problems the trainer model and firmware. Please don't open a public issue or send a pull request for these until there's a fix.

You'll get an answer within a week. This is a hobby project with no bug bounty. We'll credit you in the changelog if you'd like.

## If it's happening on your bike right now

Stop pedaling. Hold Backspace for a second, or View + Menu on a controller, to set the trainer safe. If that doesn't help, switch the trainer off at the wall.

## What's supported

The latest release. Older ones don't get fixes.

## What to know about multiplayer

A room code is the only thing that keeps a room private, so share it only with people you're riding with. Other riders' machines can only ask your trainer for something, and your own PC decides. Everything in [Riding safely](README.md#riding-safely) holds whoever is hosting. A host can still ask for hard riding inside those limits, as any workout can, so ride with people you trust, and stop pedaling if a session feels wrong.

Traffic to a `ws://` relay and to a room on a host's PC isn't encrypted, so use them on networks you trust, or a VPN. Use `wss://` for a relay on the internet.
