# Performance notes

Read this when the gates or the sims feel slow again. It says where the time goes, what was already done about it, and what was found but left alone.

Written on 2026-11-12, after the gate speed-up (pull request 1). The numbers are from a 20-core, 64 GB Windows machine.

## What a gate costs

| Gate | Before | Quiet machine | Three gates at once |
|---|---|---|---|
| `fast`, game branch | 16.7 to 43.6 min | 5.7 to 6.2 min | 5.8 to 7.3 min |
| `matrix --game=tank` (85 runs) | 15.9 to 50.6 min | 4.4 min | 10.2 min |
| `matrix --game=siege` (37 runs) | 11.4 to 15.9 min | 4.1 min | 9.9 min |
| `matrix --game=fishing` | 2.4 to 7.5 min | 1.1 min | not measured |
| `faults.mjs --jobs=6`, one game | 20 to 31 min | 5.3 min | not measured |
| `strict` | 33 min | 21 min | not measured |
| `fmt`, a few files | about 60 s | about 6 s | |

If a gate takes much longer than this, check these first:

- **The slot cap.** `node tools/lib/godot_lock.mjs status` shows it. A checkout on code from before the speed-up computes a cap of 4 and holds up every other gate on the machine when its turn comes. Merge main into it, or set a cap file with `set-cap <n>`. A stale cap file or `WATTLANDS_GODOT_LOCK_CAP` does the same.
- **How many gates run at once.** Sims are CPU work, and three gates fill 20 cores. A matrix that takes 4 minutes alone takes 10 beside two others.
- **Whether `fast` ran everything.** A change inside one game's own paths runs only that game's tests. Any file outside them, or a reference from one game to another, selects the whole suite. The gate prints a line when it leaves files out.
- **Each lane's time.** Every gate prints them, and the stamp in `build/gate/<gate>.json` keeps them. A matrix stamp holds each run's `run_ms`.

## Floors

- **A full `fast` on a game branch can't go under about 5.5 minutes.** The multiplayer e2e run plays at real time (BRIEF 6) and ends with the 180 s cool-down that `PlanValidator` appends. Every other lane finishes inside that.
- **A sim run is single-threaded GDScript.** A Tank crew-of-three run is about 45 s. More slots only help while cores are free.

## Found and left alone: two hot spots in the rider stack

A profile of sim runs put 25 to 43 percent of a step in the rider stack (the governor, `LocalRider`, `MockTrainer`). Two things in it do work nobody uses. Both files are safety-pinned, so they were not touched. Their gain was not measured.

1. **`LocalRider` builds a telemetry object on every step for a signal almost nobody hears.** The rider's tick in `addons/wattlands/core/local_rider.gd` ends with `telemetry_updated.emit(_build_telemetry())`. Only `FtpTest` connects to that signal. Building the object also calls `governor.status()`, which is the second hot spot. An idea: build it only when the signal has a connection.
2. **`SafetyGovernor.status()` deep-copies its dictionary on every call.** `status()` in `addons/wattlands/trainer/control/safety_governor.gd` returns `_status.duplicate(true)`. `LocalRider._status()` calls it for every `telemetry()`, and `GameHost` asks a rider for `telemetry()` several times in one step. Ideas: keep one telemetry object per step in `LocalRider`, or give the governor typed getters for the few fields the rider reads, and keep the copy for callers outside.

What a change there needs:

- The safety-reviewer reads it. Nothing in BRIEF 4.6 may move, and the governor must still hand out a copy to anything that could write to it.
- Proof that behaviour is the same: equal `deterministic_hash` in same-seed `tools/run_game_sim` reports before and after, for every game.
- `tools/gate pin-safety` and an ADR, since `local_rider.gd` and everything under `addons/wattlands/trainer/` are pinned.

## Smaller things, measured and left out

Together these were 1 to 3 percent of a run, so they were not merged. Each kept reports byte-identical.

- **`Protocol.apply_int_fields()` splits every int path into tokens on every call.** Clients apply the same paths to every snapshot and event. Keeping the tokens per path saves the splitting.
- **`deterministic_hash` deep-copies the whole report** to erase a few top-level keys. A shallow copy of the report and of its `args` gives the same hash.
- **`TankGame` names `TankView` and `TankHud` by class,** so a headless run compiles the view and the HUD it never builds, about 0.7 s per run. Loading them by path in `make_view()` and `hud_spec()`, as Fishing does, avoids it.

## Other levers

Each of these is the maintainer's call.

- **A shorter e2e run:** a cool-down or a sim speed for the multiplayer e2e that differs from BRIEF 6. This is the only way under the 5.5 minute floor.
- **Fewer red matrix runs:** failed runs cost 3.7 hours of the v1.1.0 release. Naming the balance targets in a builder's brief means fewer runs that fail on balance.
- **The literal `tools/run_tests`** stays serial on purpose. `--node-jobs`, `--sim-jobs` and `--static-jobs` exist and are off by default.

## Where the reasoning is

`docs/decisions/gate.md`, `gut-speed.md` and `sim-speed.md` hold the decisions of the speed-up, with what was tried and dropped.
