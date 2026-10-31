class_name TankShellPath
extends RefCounted
## v4: a far shell's way across the three surfaces (SPEC_TANK 4.4), from snapshot fields only: `x` the
## range in m, `y` the height in m, `vx` dR/dt, `vy` up, `left_s` the seconds until it lands. It flies a
## parabola over flat ground, launched and landing at height 0, so the flight's length and age follow
## from `left_s` and `vy` on every peer, and where it lands from `x + vx * left_s` (`impact_r` is host only).
##
##              our shell                                theirs
## first LEAVE_S    near panel: muzzle to the near edge      far panel: their muzzle to the near-side edge
## all of it        the PiP's arc                            the PiP's arc, red
## last ARRIVE_S    far panel: top corner to where it lands  near panel: the near edge to the tank or road

const LEAVE_S := 0.3
const ARRIVE_S := 0.35


## The whole flight's seconds.
static func flight_s(left_s: float, vy: float, g: float) -> float:
	return maxf(2.0 * (left_s - vy / g), left_s)


## Seconds since it left the gun.
static func age_s(left_s: float, vy: float, g: float) -> float:
	return flight_s(left_s, vy, g) - left_s


## The range it lands at (m).
static func landing_m(x: float, vx: float, left_s: float) -> float:
	return x + vx * left_s


## The range it left from (m): 0 for ours, the shooter's for theirs.
static func launch_m(x: float, vx: float, age: float) -> float:
	return x - vx * age


## 0..1 through its first LEAVE_S, -1 after them.
static func leave_k(age: float) -> float:
	return age / LEAVE_S if age >= 0.0 and age < LEAVE_S else -1.0


## 0..1 through its last ARRIVE_S, -1 before them.
static func arrive_k(left_s: float) -> float:
	return 1.0 - left_s / ARRIVE_S if left_s >= 0.0 and left_s < ARRIVE_S else -1.0


## The height (m) of the arc through (x, y) at range `r`.
static func height_at(r: float, x: float, y: float, vx: float, vy: float, g: float) -> float:
	if vx == 0.0:
		return y
	var t := (r - x) / vx
	return maxf(y + vy * t - 0.5 * g * t * t, 0.0)
