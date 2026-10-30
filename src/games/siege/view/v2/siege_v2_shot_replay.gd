class_name SiegeV2ShotReplay
extends RefCounted
## One `shot` event replayed (docs/games/siege.md 2.6): the flight of each of its `n`
## projectiles from the origin and launch velocity, with the per-projectile spread drawn in order
## from SiegeHashRng(sd) (STATE_V2.md: yaw += gauss(sigma), pitch += gauss(sigma),
## speed * (1 + range_f(-s, s))), integrated by SiegeBallistics at the sim step until it
## descends through the ground height (SiegePath.ground_z). Pure and deterministic: the same
## event gives the same arcs on every peer. Damage never comes from here.

const KIND_BOLT := 0
const KIND_STONE := 1
const KIND_ARROW := 2
const KIND_SCORPION := 3
## Placeholder spread until content/siege/stations.json exists: [sigma deg, speed spread s].
const SPREAD := {0: [0.3, 0.005], 1: [0.6, 0.015], 2: [2.5, 0.03], 3: [0.3, 0.005]}
## Drag k (1/m) by kind (docs/games/siege.md 2.4 "Stations", "Pads").
const DRAG := {0: 0.0004, 1: 0.0016, 2: 0.006, 3: 0.001}
const MAX_N := 16
const MAX_STEPS := 400

var kind: int = 0
var src: int = 0
var tick: int = 0
var n: int = 1
var seed_value: int = 0
var origin: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Per projectile: positions every SiegeBallistics.DT from launch; the last is the landing point.
var flights: Array[PackedVector3Array] = []
## Per projectile: seconds from launch to landing.
var land_t := PackedFloat32Array()


## Replays a shot event (ints as in the brief: cm, mm/s). `spread` overrides SPREAD[kind].
static func from_event(ev: Dictionary, path: SiegePath, spread: Array = []) -> SiegeV2ShotReplay:
	var r := SiegeV2ShotReplay.new()
	r.kind = int(ev.get("kind", 0))
	r.src = int(ev.get("src", 0))
	r.tick = int(ev.get("tk", 0))
	r.n = clampi(int(ev.get("n", 1)), 1, MAX_N)
	r.seed_value = int(ev.get("sd", 1))
	var o: Array = ev.get("o", [0, 0, 0])
	var v: Array = ev.get("v", [0, 0, 0])
	r.origin = Vector3(float(o[0]), float(o[1]), float(o[2])) / 100.0
	r.velocity = Vector3(float(v[0]), float(v[1]), float(v[2])) / 1000.0
	var sp: Array = spread if spread.size() == 2 else SPREAD.get(r.kind, [0.0, 0.0])
	r._fly(path, float(sp[0]), float(sp[1]), float(DRAG.get(r.kind, 0.001)))
	return r


func _fly(path: SiegePath, sigma: float, s: float, k: float) -> void:
	var rng := SiegeHashRng.new(seed_value)
	var top := -1.0e9
	if path != null:
		for q in path.points:
			top = maxf(top, q.z)
	else:
		top = 0.0
	for _j in n:
		var dyaw := rng.gauss(sigma)
		var dpitch := rng.gauss(sigma)
		var sf := 1.0 + rng.range_f(-s, s)
		var v := SiegeBallistics.spread(velocity, dyaw, dpitch, sf)
		var p := origin
		var pts := PackedVector3Array([p])
		var t := 0.0
		for _i in MAX_STEPS:
			var nx := SiegeBallistics.step(p, v, k)
			var q: Vector3 = nx[0]
			v = nx[1]
			if v.z < 0.0 and q.z < top + 0.5:
				var gz := path.ground_z(q.x, q.y) if path != null else 0.0
				if q.z <= gz:
					var f := clampf((p.z - gz) / maxf(p.z - q.z, 0.0001), 0.0, 1.0)
					pts.append(p.lerp(q, f))
					t += SiegeBallistics.DT * f
					break
			p = q
			pts.append(p)
			t += SiegeBallistics.DT
		flights.append(pts)
		land_t.append(t)


## Where projectile j is `t` seconds after launch (its landing point once it has landed).
func position(j: int, t: float) -> Vector3:
	var pts := flights[j]
	var f := clampf(t / SiegeBallistics.DT, 0.0, float(pts.size() - 1))
	var i := mini(floori(f), pts.size() - 2)
	if i < 0:
		return pts[0]
	if t >= land_t[j]:
		return pts[pts.size() - 1]
	return pts[i].lerp(pts[i + 1], f - float(i))


## Projectile j's unit direction of flight at `t`.
func direction(j: int, t: float) -> Vector3:
	var a := position(j, maxf(t - 0.05, 0.0))
	var b := position(j, minf(t, land_t[j]))
	var d := b - a
	if d.length_squared() < 1e-8:
		var pts := flights[j]
		d = pts[mini(1, pts.size() - 1)] - pts[0]
	return d.normalized() if d.length_squared() > 1e-8 else Vector3(1, 0, 0)


func landed(j: int, t: float) -> bool:
	return t >= land_t[j]


func landing(j: int) -> Vector3:
	return flights[j][flights[j].size() - 1]


## The longest flight of the shot (s).
func duration() -> float:
	var m := 0.0
	for t in land_t:
		m = maxf(m, t)
	return m
