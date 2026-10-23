class_name TankGearboxState
extends TankDieselState
## The Bulwark's diesel with its three-way gearbox (brief 2.4 Bulwark gearbox): the lever routes
## the one engine to Drive (Dig at a gun line), Turret or Hoist.

## [snap] TankIds.LEVER_*.
var lever: int = TankIds.LEVER_DRIVE
## The position a move is heading to (== lever when still).
var lever_to: int = TankIds.LEVER_DRIVE
## [snap] Seconds left of a lever move (1 s, no power anywhere).
var move_s: float = 0.0
## [snap] The auto-lever is in charge (false for 15 s after a manual move).
var auto: bool = true
## Seconds left of the manual suspension.
var suspend_s: float = 0.0
## Seconds the lever has stayed at its position (auto-lever dwell >= 3 s).
var dwell_s: float = 0.0
## [snap] Joules lifted toward the next heavy shell (4 kJ).
var hoist_j: float = 0.0
## Game seconds on Drive in the current Advance (T4).
var drive_s: float = 0.0
