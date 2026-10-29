class_name SiegeBallistics
extends RefCounted
## Projectile physics shared by the host rules and the clients' shot replay
## (docs/games/siege.md 2.4 "Projectiles"). Gravity and quadratic drag, semi-implicit Euler at
## the sim step: v += (g - k |v| v) dt, then p += v dt. Pure and deterministic.

const G := 9.81
const DT := 0.05
## Longest flight anything is integrated for.
const MAX_FLIGHT_S := 20.0
const AIM_ROUNDS := 10


## Advances one projectile by `dt`; returns [pos, vel].
static func step(pos: Vector3, vel: Vector3, k: float, dt: float = DT) -> PackedVector3Array:
	var s := vel.length()
	var v := vel + (Vector3(0.0, 0.0, -G) - vel * (k * s)) * dt
	return PackedVector3Array([pos + v * dt, v])


## Flies from p0 with v0 until it descends through height `floor_z` (or MAX_FLIGHT_S).
## Returns {"p": landing point (interpolated), "t": flight seconds, "steps": ticks, "v": velocity}.
static func land(p0: Vector3, v0: Vector3, k: float, floor_z: float) -> Dictionary:
	var p := p0
	var v := v0
	var t := 0.0
	var steps := 0
	while t < MAX_FLIGHT_S:
		var nx := step(p, v, k)
		var q := nx[0]
		if q.z <= floor_z and nx[1].z < 0.0:
			var f := (p.z - floor_z) / maxf(p.z - q.z, 0.0001)
			return {"p": p.lerp(q, clampf(f, 0.0, 1.0)), "t": t + DT * f, "steps": steps + 1, "v": nx[1]}
		p = q
		v = nx[1]
		t += DT
		steps += 1
	return {"p": p, "t": t, "steps": steps, "v": v}


## The launch velocity at `speed` that lands on `target` (low arc, or the high one), corrected for
## drag by re-aiming at the miss (AIM_ROUNDS). Vector3.ZERO when even 45 degrees falls short.
static func solve_angle(p0: Vector3, target: Vector3, speed: float, k: float, high: bool = false) -> Vector3:
	var ap := target
	var v0 := Vector3.ZERO
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
		var l := land(p0, v0, k, target.z)
		var miss: Vector3 = target - (l["p"] as Vector3)
		if Vector2(miss.x, miss.y).length() < 0.05:
			break
		ap += Vector3(miss.x, miss.y, 0.0)
	var check := land(p0, v0, k, target.z)
	var err := Vector2(target.x - check["p"].x, target.y - check["p"].y).length()
	return v0 if err < 1.0 else Vector3.ZERO


## The launch velocity at a fixed elevation `angle_deg` whose speed (bisected within
## [v_min, v_max]) lands on `target`. Vector3.ZERO when v_max falls short or v_min overshoots.
static func solve_speed(
	p0: Vector3, target: Vector3, angle_deg: float, k: float, v_min: float, v_max: float
) -> Vector3:
	var dx := Vector2(target.x - p0.x, target.y - p0.y)
	var d := dx.length()
	if d < 0.01:
		return Vector3.ZERO
	var u := dx / d
	var a := deg_to_rad(angle_deg)
	var dir := Vector3(u.x * cos(a), u.y * cos(a), sin(a))
	var reach := func(v: float) -> float:
		var l := land(p0, dir * v, k, target.z)
		return Vector2(l["p"].x - p0.x, l["p"].y - p0.y).length()
	if float(reach.call(v_max)) < d - 0.5 or float(reach.call(v_min)) > d + 0.5:
		return Vector3.ZERO
	var lo := v_min
	var hi := v_max
	for _i in 24:
		var mid := (lo + hi) * 0.5
		if float(reach.call(mid)) < d:
			lo = mid
		else:
			hi = mid
	return dir * ((lo + hi) * 0.5)


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
