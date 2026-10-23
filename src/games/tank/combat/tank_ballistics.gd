class_name TankBallistics
extends RefCounted
## Shell flight and the aim solver (brief 2.4 Gun). Owner: rules. Units: art px, px/s, px/s^2,
## degrees; y grows downward on screen, so a shell rises with negative vy. Elevation is measured
## from the horizontal toward the facing direction (TankIds.FACE_RIGHT +1 / FACE_LEFT -1).
##
## G0 ships the analytic arc and the lower-arc solver without lead; G1 (rules) adds lead on a
## moving target, dispersion and the range rule, keeping these signatures.


## The muzzle velocity vector for `elev_deg` and `facing` at speed `v0`.
static func velocity(v0: float, elev_deg: float, facing: int) -> Vector2:
	var a := deg_to_rad(elev_deg)
	return Vector2(facing * v0 * cos(a), -v0 * sin(a))


## The shell's position `t` seconds after leaving `muzzle` with velocity `vel`.
static func position(muzzle: Vector2, vel: Vector2, gravity: float, t: float) -> Vector2:
	return muzzle + vel * t + Vector2(0.0, 0.5 * gravity * t * t)


## The lower-arc elevation in degrees that reaches a point `dx` px ahead (along the facing,
## > 0) and `rise` px above the muzzle (negative below), or NAN when out of range.
static func solve_elevation(dx: float, rise: float, v0: float, gravity: float) -> float:
	if dx <= 0.0 or v0 <= 0.0 or gravity <= 0.0:
		return NAN
	var v2 := v0 * v0
	var disc := v2 * v2 - gravity * (gravity * dx * dx + 2.0 * rise * v2)
	if disc < 0.0:
		return NAN
	return rad_to_deg(atan((v2 - sqrt(disc)) / (gravity * dx)))


## The horizontal range on ground `drop` px below the muzzle at `elev_deg` (the range rule:
## the 30 degree range must be >= 1.1 x the muzzle-to-edge distance).
static func range_px(v0: float, elev_deg: float, gravity: float, drop: float) -> float:
	var a := deg_to_rad(elev_deg)
	var vs := v0 * sin(a)
	var t := (vs + sqrt(vs * vs + 2.0 * gravity * maxf(drop, 0.0))) / gravity
	return v0 * cos(a) * t
