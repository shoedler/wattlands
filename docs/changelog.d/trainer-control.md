# trainer-control

## Added

- `SafetyGovernor` implements BRIEF 4.6.1-4.6.12: whole-watt ERG targets, the floor and ceilings, the 105 % cap for long phases, the 105 % / 120 % duration limits with latching and the inclusive 120 s reset, the unverified-FTP factor, the ramp_test profile, slew, rescue with its 10 s ramp-back, coasting (floor at 3 s, pause or AFK at 10 s), panic, SIM stacking with haptic bounds, warm-up, the exit path and rule 12 precedence.
- Directive channels (BRIEF 3.6) inside the governor: ERG target, SIM block, mode grade, haptic and factors, each with its own expiry; course grades coalesced to 2 Hz; course profiles followed by distance; applied records with `clamped_by`, refusals and dropped channels.
- `TrainerController`: ERG / SIM / RESISTANCE (P1) / OFF, slew, ramped ERG <-> SIM switches, at most 2 control writes per second, immediate panic and shutdown writes.
- `VirtualGears`: 24 gears as SIM grade offsets, 7 % per step at the 30 km/h reference.
- `CadenceEstimator`: cadence from flywheel speed when absent or stale, learned ratio and 10 s calibration.
- `tests/arch/test_no_bypass.gd`: the BRIEF 4.6.11 scan over `addons/wattlands` and `src`, with bypass fixtures.
- `content/strings/governor.csv`: banner and toast strings for rescue, warm-up, coasting, AFK, panic, duration limits, the FTP test end and the gear.

## Fixed (hardening review)

- Rescue arms when the whole-watt governed target reaches floor(60 % FTP), so a target exactly at 60 % arms it at every FTP (4.6.1's whole-watt comparison).
- Opting out of haptics ends a running haptic at once.
- The no-bypass scan also guards `TrainerDevice.request_stop` (Stop): only `TrainerController` may call it.
- New tests: the frozen W0 API surface (methods, signals, status and record keys), both duration limits resetting together, factor and mode-grade expiry, the ramp span in the default range, the paused floor counting toward the reset, and a determinism check over a busy seeded ride.
- One shared not_pedaling detector (BRIEF 3.5): the governor calls `GestureRecognizer.is_not_pedaling`, so the governor, `CadenceEstimator` and the GestureRecognizer share one copy of 15 W and 20 rpm (`GameHost`'s rejoin check still has its own, pinned equal by a test); new tests pin the exact edges of not_pedaling (15 W, 20 rpm) and rescue (45 rpm, 70 rpm, 75 % of the target).
