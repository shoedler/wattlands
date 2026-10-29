class_name TankBallistics
extends RefCounted
## Shell flight and the aim solver (brief 2.4 Gun). Owner: rules. Units: art px, px/s, px/s^2,
## degrees; y grows downward on screen, so a shell rises with negative vy. Elevation is measured
## from the horizontal toward the facing direction (TankIds.FACE_RIGHT +1 / FACE_LEFT -1).
##
## The arc is the analytic one: position(t) = muzzle + v t + (0, g t^2 / 2). TankShells steps
## shells with the exact per-tick form of the same formula, so a shell flies the analytic arc. The
## solver returns the lower-arc elevation for a point, with lead for a target that moves relative
## to the gun (the hull frame: shells inherit the hull's velocity, see TankGun).


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


## Seconds a shell fired at `elev_deg` needs to cover `dx` px horizontally.
static func flight_time(dx: float, v0: float, elev_deg: float) -> float:
	var vx := v0 * cos(deg_to_rad(elev_deg))
	return dx / vx if vx > 0.0 else INF


## Like solve_elevation, for a target that moves relative to the muzzle: `dx` and `rise` are
## where it is now, `vel_dx` / `vel_rise` its velocity along the facing and upward (px/s). The
## target is led by its flight time at the elevation found, eight iterations deep (a target
## closing at the shell's own speed has no solution and returns NAN).
static func solve_lead(
	dx: float, rise: float, vel_dx: float, vel_rise: float, v0: float, gravity: float
) -> float:
	var e := solve_elevation(dx, rise, v0, gravity)
	for _i in 8:
		if is_nan(e):
			return NAN
		var vx := v0 * cos(deg_to_rad(e))
		if vx <= vel_dx:
			return NAN
		var t := dx / (vx - vel_dx)
		e = solve_elevation(dx + vel_dx * t, rise + vel_rise * t, v0, gravity)
	return e


## Height in px above the muzzle that a shell fired at `elev_deg` has after covering `dx` px.
static func height_at(dx: float, v0: float, elev_deg: float, gravity: float) -> float:
	var a := deg_to_rad(elev_deg)
	var t := dx / (v0 * cos(a))
	return v0 * sin(a) * t - 0.5 * gravity * t * t


## The horizontal range on ground `drop` px below the muzzle at `elev_deg` (the range rule:
## the 30 degree range must be >= 1.1 x the muzzle-to-edge distance).
static func range_px(v0: float, elev_deg: float, gravity: float, drop: float) -> float:
	var a := deg_to_rad(elev_deg)
	var vs := v0 * sin(a)
	var t := (vs + sqrt(vs * vs + 2.0 * gravity * maxf(drop, 0.0))) / gravity
	return v0 * cos(a) * t


## The dispersion half-angle in degrees at `bank` units (a tank without a dynamo passes a full bank):
## dispersion_deg[0] from low_bank up, dispersion_deg[1] below it (brief 2.4 Dynamo).
static func dispersion_deg(c: TankContent, bank: float) -> float:
	var d: Array = c.value("tanks", "dynamo.dispersion_deg", [0.5, 1.5])
	return float(d[0]) if bank >= c.num("tanks", "dynamo.low_bank", 20.0) else float(d[1])
