class_name SiegeBallistics
extends RefCounted
## Projectile physics shared by the host rules and the clients' shot replay
## (docs/games/siege.md 2.4 "Projectiles"). Gravity and quadratic drag at the sim step:
## v' = v + (g - k |v| v) dt, then p += (v + v') / 2 dt. Pure and deterministic.
##
## The brief's semi-implicit Euler (p += v' dt) lands a whole tick's drop early: up to 1.4% short
## of closed-form range for the ballista's flat bolts, against brief 4's 1% (ADR "trapezoidal
## position step"). Averaging the old and new velocity for the position makes the gravity part
## exact and keeps the velocity update as written.
##
## land() and the solvers integrate with the same expressions as step(), inline (no array per
## step), so a landing they predict is the one step() reaches tick by tick.

const G := 9.81
const DT := 0.05
## Longest flight anything is integrated for.
const MAX_FLIGHT_S := 20.0
const AIM_ROUNDS := 10
## solve_speed stops when the reach is this close to the distance (m).
const SPEED_TOL_M := 0.02
const SPEED_ROUNDS := 30


## Advances one projectile by `dt`; returns [pos, vel].
static func step(pos: Vector3, vel: Vector3, k: float, dt: float = DT) -> PackedVector3Array:
	var s := vel.length()
	var v := vel + (Vector3(0.0, 0.0, -G) - vel * (k * s)) * dt
	return PackedVector3Array([pos + (vel + v) * (0.5 * dt), v])


## Flies from p0 with v0 until it descends through height `floor_z` (or MAX_FLIGHT_S).
## Returns {"p": landing point (interpolated), "t": flight seconds, "steps": ticks, "v": velocity}.
static func land(p0: Vector3, v0: Vector3, k: float, floor_z: float) -> Dictionary:
	var p := p0
	var v := v0
	var t := 0.0
	var steps := 0
	var grav := Vector3(0.0, 0.0, -G)
	while t < MAX_FLIGHT_S:
		var s := v.length()
		var nv := v + (grav - v * (k * s)) * DT
		var q := p + (v + nv) * (0.5 * DT)
		if q.z <= floor_z and nv.z < 0.0:
			var f := (p.z - floor_z) / maxf(p.z - q.z, 0.0001)
			return {
				"p": p.lerp(q, clampf(f, 0.0, 1.0)), "t": t + DT * f, "steps": steps + 1, "v": nv
			}
		p = q
		v = nv
		t += DT
		steps += 1
	return {"p": p, "t": t, "steps": steps, "v": v}


## The launch velocity at `speed` that lands on `target` (low arc, or the high one), corrected for
## drag by re-aiming at the miss (AIM_ROUNDS). Vector3.ZERO when even 45 degrees falls short.
static func solve_angle(
	p0: Vector3, target: Vector3, speed: float, k: float, high: bool = false
) -> Vector3:
	return solve_angle_full(p0, target, speed, k, high).get("v", Vector3.ZERO)


## solve_angle with the flight: {"v": launch velocity, "t": flight s, "steps": ticks, "p":
## landing point}, or {} when there is no solution.
static func solve_angle_full(
	p0: Vector3, target: Vector3, speed: float, k: float, high: bool = false
) -> Dictionary:
	var ap := target
	var v0 := Vector3.ZERO
	var l := {}
	for _i in AIM_ROUNDS:
		var dx := Vector2(ap.x - p0.x, ap.y - p0.y)
		var d := maxf(dx.length(), 0.01)
		var h := ap.z - p0.z
		var v2 := speed * speed
		var disc := v2 * v2 - G * (G * d * d + 2.0 * h * v2)
		var ang := PI / 4.0
		if disc >= 0.0:
			ang = atan((v2 + (1.0 if high else -1.0) * sqrt(disc)) / (G * d))
		var u := dx / d
		v0 = Vector3(u.x * cos(ang) * speed, u.y * cos(ang) * speed, sin(ang) * speed)
		l = land(p0, v0, k, target.z)
		var miss: Vector3 = target - (l["p"] as Vector3)
		if Vector2(miss.x, miss.y).length() < 0.05:
			break
		ap += Vector3(miss.x, miss.y, 0.0)
	var lp: Vector3 = l["p"]
	if Vector2(target.x - lp.x, target.y - lp.y).length() >= 1.0:
		return {}
	return {"v": v0, "t": l["t"], "steps": l["steps"], "p": lp}


## The launch velocity at a fixed elevation `angle_deg` whose speed (within [v_min, v_max])
## lands on `target`. Vector3.ZERO when v_max falls short or v_min overshoots.
static func solve_speed(
	p0: Vector3, target: Vector3, angle_deg: float, k: float, v_min: float, v_max: float
) -> Vector3:
	return solve_speed_full(p0, target, angle_deg, k, v_min, v_max).get("v", Vector3.ZERO)


## solve_speed with the flight: {"v", "t", "steps", "p"}, or {} when there is no solution.
## The speed is found by regula falsi (Illinois) on the reach, bracketed by v_min and v_max.
static func solve_speed_full(
	p0: Vector3, target: Vector3, angle_deg: float, k: float, v_min: float, v_max: float
) -> Dictionary:
	var dx := Vector2(target.x - p0.x, target.y - p0.y)
	var d := dx.length()
	if d < 0.01:
		return {}
	var u := dx / d
	var a := deg_to_rad(angle_deg)
	var dir := Vector3(u.x * cos(a), u.y * cos(a), sin(a))
	var lo := v_min
	var hi := v_max
	var l_lo := land(p0, dir * lo, k, target.z)
	var l_hi := land(p0, dir * hi, k, target.z)
	var f_lo := _reach(p0, l_lo) - d
	var f_hi := _reach(p0, l_hi) - d
	if f_hi < -0.5 or f_lo > 0.5:
		return {}
	if f_lo >= 0.0:
		return {"v": dir * lo, "t": l_lo["t"], "steps": l_lo["steps"], "p": l_lo["p"]}
	if f_hi <= 0.0:
		return {"v": dir * hi, "t": l_hi["t"], "steps": l_hi["steps"], "p": l_hi["p"]}
	var best := l_hi
	var best_v := hi
	var side := 0
	for _i in SPEED_ROUNDS:
		var mid := (lo * f_hi - hi * f_lo) / (f_hi - f_lo)
		if not (mid > lo and mid < hi):
			mid = (lo + hi) * 0.5
		var lm := land(p0, dir * mid, k, target.z)
		var fm := _reach(p0, lm) - d
		best = lm
		best_v = mid
		if absf(fm) < SPEED_TOL_M:
			break
		if fm < 0.0:
			lo = mid
			f_lo = fm
			if side == -1:
				f_hi *= 0.5
			side = -1
		else:
			hi = mid
			f_hi = fm
			if side == 1:
				f_lo *= 0.5
			side = 1
	return {"v": dir * best_v, "t": best["t"], "steps": best["steps"], "p": best["p"]}


## The flight time of v0 from p0 down to `floor_z`.
static func flight_time(p0: Vector3, v0: Vector3, k: float, floor_z: float) -> float:
	return float(land(p0, v0, k, floor_z)["t"])


## v0 turned by `yaw_deg` about z and lifted by `pitch_deg`, speed scaled by `speed_f`: the
## spread one projectile draws from SiegeHashRng.
static func spread(v0: Vector3, yaw_deg: float, pitch_deg: float, speed_f: float) -> Vector3:
	var hz := Vector2(v0.x, v0.y)
	var horiz := hz.length()
	var elev := atan2(v0.z, horiz) + deg_to_rad(pitch_deg)
	var az := atan2(v0.y, v0.x) + deg_to_rad(yaw_deg)
	var s := v0.length() * speed_f
	return Vector3(cos(elev) * cos(az) * s, cos(elev) * sin(az) * s, sin(elev) * s)


## The launch velocities of the `n` projectiles of one shot from its base velocity and seed: each
## draws yaw += gauss(sigma), pitch += gauss(sigma), speed x (1 + range_f(-s, s)), in order, from
## SiegeHashRng(seed) (STATE_V2.md). The host and every replaying client call this.
static func shot_velocities(
	v0: Vector3, n: int, seed_value: int, sigma_deg: float, speed_spread: float
) -> PackedVector3Array:
	var out := PackedVector3Array()
	var rng := SiegeHashRng.new(seed_value)
	for _j in n:
		var dy := rng.gauss(sigma_deg)
		var dp := rng.gauss(sigma_deg)
		var sf := 1.0 + rng.range_f(-speed_spread, speed_spread)
		out.append(spread(v0, dy, dp, sf))
	return out


static func _reach(p0: Vector3, l: Dictionary) -> float:
	var p: Vector3 = l["p"]
	return Vector2(p.x - p0.x, p.y - p0.y).length()
