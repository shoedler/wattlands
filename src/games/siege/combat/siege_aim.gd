class_name SiegeAim
extends RefCounted
## Lead aiming for the stations and pads (brief 2.4 "Aiming"). Pure.
##
## The aimer predicts its target's `prog` after the flight time at the target's current speed
## (path progress is exact, so the lead follows the road through its hairpins), solves the launch
## for that point with the drag flight (SiegeBallistics), and repeats the prediction with the new
## flight time (lead_rounds, 3). A spec says how a weapon solves:
##   {"aim": "angle", "speed_mps", "k", "aim_dz_m"}   a fixed speed, the low arc (bolts);
##   {"aim": "speed", "elev_deg", "v_min", "v_max", "k", "aim_dz_m"?, "fallback"?}   a fixed
##   elevation, the speed solved in [v_min, v_max] (stones; arrows at 40 degrees, falling back to
##   the low arc at v_max when 40 degrees can't reach).

const DEFAULT_ROUNDS := 3


## Where enemy `e` will be after `t` seconds at its current speed (prog clamped to where it
## stops: the moat edge for a siege tower, the gate for everyone else).
static func predict_prog(path: SiegePath, e: SiegeEnemyState, t: float) -> float:
	if e.st != SiegeIds.EN_WALK:
		return e.prog_m
	var stop := path.moat_edge_m if e.type == SiegeIds.ENEMY_TOWER else path.length_m
	return clampf(e.prog_m + e.speed_mps * t, 0.0, stop)


## The world point to aim at for `e` after `t` seconds: on the path at its lateral offset, `dz`
## metres above the ground.
static func aim_point(path: SiegePath, e: SiegeEnemyState, t: float, dz: float) -> Vector3:
	var p := path.point_at(predict_prog(path, e, t), e.lat_m)
	p.z += dz
	return p


## The lead solution for `e` fired from `pivot` with the muzzle `muzzle_m` along the aim:
## {"o": launch point, "v": launch velocity, "t": flight s, "steps": ticks, "p": predicted
## landing, "aim": aim point, "yaw": deg}, or {} when the weapon cannot reach it.
static func lead(
	path: SiegePath,
	pivot: Vector3,
	muzzle_m: float,
	e: SiegeEnemyState,
	spec: Dictionary,
	guess_t: float,
	rounds: int = DEFAULT_ROUNDS
) -> Dictionary:
	var t := maxf(guess_t, 0.0)
	var sol := {}
	var dz := float(spec.get("aim_dz_m", 0.0))
	for _i in maxi(rounds, 1):
		var aim := aim_point(path, e, t, dz)
		var yaw := SiegePath.yaw_to(pivot, aim)
		var a := deg_to_rad(yaw)
		var o := pivot + Vector3(cos(a), sin(a), 0.0) * muzzle_m
		sol = solve(o, aim, spec)
		if sol.is_empty():
			return {}
		sol["o"] = o
		sol["aim"] = aim
		sol["yaw"] = yaw
		t = float(sol["t"])
	return sol


## The launch from `o` onto `aim` for `spec` ({} when out of reach).
static func solve(o: Vector3, aim: Vector3, spec: Dictionary) -> Dictionary:
	var k := float(spec.get("k", 0.0))
	if str(spec.get("aim", "angle")) == "speed":
		var sol := SiegeBallistics.solve_speed_full(
			o,
			aim,
			float(spec.get("elev_deg", 45.0)),
			k,
			float(spec.get("v_min", 10.0)),
			float(spec.get("v_max", 34.0))
		)
		if sol.is_empty() and bool(spec.get("fallback", false)):
			sol = SiegeBallistics.solve_angle_full(o, aim, float(spec.get("v_max", 45.0)), k)
		return sol
	return SiegeBallistics.solve_angle_full(o, aim, float(spec.get("speed_mps", 50.0)), k)
