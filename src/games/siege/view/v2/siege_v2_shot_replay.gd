class_name SiegeV2ShotReplay
extends RefCounted
## One `shot` event replayed (docs/games/siege.md 2.6) the way the host flies it
## (combat/siege_projectiles.gd): the n launch velocities from
## SiegeBallistics.shot_velocities(v, n, sd, spread_deg, speed_spread) with the station's or
## pad's numbers (content.station_def(src), content.pad_def(PAD_SCORPION)), integrated by
## SiegeBallistics.step at the sim step. Stones and arrows land where SiegeBallistics.land puts
## them on the aim point's ground (the path's height there); bolts fly on to that ground (a
## Scorpion bolt stops at the first body, which the drawer finds). Pure and deterministic.
## Damage never comes from here.

const KIND_BOLT := 0
const KIND_STONE := 1
const KIND_ARROW := 2
const KIND_SCORPION := 3
const MAX_N := 16
## Bolts: the host drops one after this many ticks (SiegeProjectiles.MAX_BOLT_TICKS).
const MAX_BOLT_STEPS := 200
const MAX_STEPS := 400

var kind: int = 0
var src: int = 0
var tick: int = 0
var n: int = 1
var seed_value: int = 0
var origin: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var k: float = 0.0
## The height the shot comes down to: the path's z under where it lands.
var floor_z: float = 0.0
## Per projectile: positions every SiegeBallistics.DT from launch; the last is the landing point.
var flights: Array[PackedVector3Array] = []
## Per projectile: seconds from launch to landing.
var land_t := PackedFloat32Array()
## Per projectile: when a drawer stopped it early (a Scorpion bolt in a body), else INF.
var stop_t := PackedFloat32Array()


## The station's or pad's stations.json entry for a shot source (src 1..3 or 10 + pad).
static func def_for(content: SiegeContent, p_src: int) -> Dictionary:
	if content == null:
		return {}
	if p_src > SiegeIds.SRC_PAD:
		return content.pad_def(SiegeIds.PAD_SCORPION)
	return content.station_def(p_src)


## Replays a shot event (ints as in the brief: cm, mm/s, read by SiegeEvents).
static func from_event(ev: Dictionary, path: SiegePath, content: SiegeContent) -> SiegeV2ShotReplay:
	var r := SiegeV2ShotReplay.new()
	r.kind = int(ev.get("kind", 0))
	r.src = int(ev.get("src", 0))
	r.tick = int(ev.get("tk", 0))
	r.n = clampi(int(ev.get("n", 1)), 1, MAX_N)
	r.seed_value = int(ev.get("sd", 1))
	r.origin = SiegeEvents.shot_origin(ev)
	r.velocity = SiegeEvents.shot_velocity(ev)
	var def := def_for(content, r.src)
	r.k = float(def.get("k", 0.0))
	var vs := SiegeBallistics.shot_velocities(
		r.velocity,
		r.n,
		r.seed_value,
		float(def.get("spread_deg", 0.0)),
		float(def.get("speed_spread", 0.0))
	)
	r.floor_z = landing_floor(path, r.origin, r.velocity, r.k)
	for v in vs:
		r._fly(v)
	return r


## The ground the shot was aimed at: the path's height under where the unspread launch comes
## down (the host's aim point is on the path, so its floor is the path's z there).
static func landing_floor(path: SiegePath, o: Vector3, v: Vector3, k: float) -> float:
	if path == null or path.points.size() < 2:
		return 0.0
	var fz := 0.0
	for _i in 3:
		var l := SiegeBallistics.land(o, v, k, fz)
		var p: Vector3 = l["p"]
		fz = path_z_near(path, p.x, p.y)
	return fz


## The path's interpolated height at the point of the path nearest to (x, y).
static func path_z_near(path: SiegePath, x: float, y: float) -> float:
	var best := INF
	var z := 0.0
	var q := Vector2(x, y)
	for i in path.points.size() - 1:
		var a := path.points[i]
		var b := path.points[i + 1]
		var ab := Vector2(b.x - a.x, b.y - a.y)
		var l2 := maxf(ab.length_squared(), 1e-9)
		var u := clampf((q - Vector2(a.x, a.y)).dot(ab) / l2, 0.0, 1.0)
		var d := (Vector2(a.x, a.y) + ab * u).distance_squared_to(q)
		if d < best:
			best = d
			z = lerpf(a.z, b.z, u)
	return z


func _fly(v0: Vector3) -> void:
	var p := origin
	var v := v0
	var pts := PackedVector3Array([p])
	var t := 0.0
	var steps := MAX_BOLT_STEPS if kind == KIND_BOLT or kind == KIND_SCORPION else MAX_STEPS
	for _i in steps:
		var nx := SiegeBallistics.step(p, v, k)
		var q: Vector3 = nx[0]
		v = nx[1]
		if q.z <= floor_z and v.z < 0.0:
			var f := clampf((p.z - floor_z) / maxf(p.z - q.z, 0.0001), 0.0, 1.0)
			pts.append(p.lerp(q, f))
			t += SiegeBallistics.DT * f
			break
		p = q
		pts.append(p)
		t += SiegeBallistics.DT
	flights.append(pts)
	land_t.append(t)
	stop_t.append(INF)


## Where projectile j is `t` seconds after launch (where it landed or stopped once it has).
func position(j: int, t: float) -> Vector3:
	var pts := flights[j]
	var tt := minf(t, end_t(j))
	var f := clampf(tt / SiegeBallistics.DT, 0.0, float(pts.size() - 1))
	var i := mini(floori(f), pts.size() - 2)
	if i < 0:
		return pts[0]
	if tt >= land_t[j]:
		return pts[pts.size() - 1]
	return pts[i].lerp(pts[i + 1], f - float(i))


## Projectile j's unit direction of flight at `t`.
func direction(j: int, t: float) -> Vector3:
	var a := position(j, maxf(t - 0.05, 0.0))
	var b := position(j, minf(t, end_t(j)))
	var d := b - a
	if d.length_squared() < 1e-8:
		var pts := flights[j]
		d = pts[mini(1, pts.size() - 1)] - pts[0]
	return d.normalized() if d.length_squared() > 1e-8 else Vector3(1, 0, 0)


## When projectile j stops: at its landing, or earlier where a drawer stopped it.
func end_t(j: int) -> float:
	return minf(land_t[j], stop_t[j])


func landed(j: int, t: float) -> bool:
	return t >= end_t(j)


func landing(j: int) -> Vector3:
	return position(j, end_t(j))


## The longest flight of the shot (s).
func duration() -> float:
	var m := 0.0
	for j in n:
		m = maxf(m, end_t(j))
	return m
