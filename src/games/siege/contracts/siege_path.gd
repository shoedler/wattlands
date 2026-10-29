class_name SiegePath
extends RefCounted
## The v2 battlefield (content/siege/maps/rotae.json, docs/games/siege.md 2.4 "Map"): one enemy
## path from the camp to the gate, the bridge, the staging grounds, the five stations, the four
## pads and the wheels. The JSON is generated from the art's own geometry by
## src/games/siege/art/export_map.mjs, so rules, view and picture agree. Pure and deterministic.
##
## World metres: x east, y south (toward the camera), z up. Art pixels (960 x 540):
## sx = (x - y) k + ox, sy = (x + y) k / 2 - z k + oy; depth x + y + z (larger is nearer).
## `prog_m` runs from 0 at the camp to length_m at the gate. A lateral offset `lat_m` is measured
## along the path's left normal (dir.y, -dir.x): positive is to the left of travel.

const GROUND_REACH_M := 30.0

var id: String = ""
var data: Dictionary = {}
## Path points [x, y, z] from the camp to the gate, and the cumulative ground length at each.
var points: PackedVector3Array = PackedVector3Array()
var cum: PackedFloat32Array = PackedFloat32Array()
var length_m: float = 0.0
var bridge_from_m: float = 0.0
var bridge_to_m: float = 0.0
var moat_edge_m: float = 0.0
var plaza_center: Vector2 = Vector2.ZERO
var plaza_radius_m: float = 8.0
var gate_pos: Vector3 = Vector3.ZERO
## Staging grounds' prog_m, camp first.
var staging: PackedFloat32Array = PackedFloat32Array()
## Station id 0..4 -> pivot, muzzle offset along the aim (m), starting yaw (deg, atan2(dy, dx)).
var station_pos: Array[Vector3] = []
var station_muzzle_m: PackedFloat32Array = PackedFloat32Array()
var station_yaw0_deg: PackedFloat32Array = PackedFloat32Array()
## Pad 1..4 at index pad - 1.
var pads: Array[Vector3] = []
## Slot 0..3 -> wheel hub.
var wheels: Array[Vector3] = []
var wheel_radius_m: float = 7.0
var cam_k: float = 3.5
var cam_ox: float = 450.0
var cam_oy: float = 127.0


static func load_file(path: String) -> SiegePath:
	var text := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(text) if text != "" else null
	return from_dict(d if d is Dictionary else {})


## Errors in a map dictionary (empty when valid).
static func validate(d: Dictionary) -> PackedStringArray:
	var err := PackedStringArray()
	if int(d.get("version", 0)) != 2:
		err.append("map version must be 2")
	var pts: Variant = (d.get("path", {}) as Dictionary).get("points") if d.get("path") is Dictionary else null
	if not (pts is Array) or (pts as Array).size() < 2:
		err.append("path.points needs at least 2 points")
	else:
		for q: Variant in pts:
			if not (q is Array) or (q as Array).size() != 3:
				err.append("path.points entries are [x, y, z]")
				break
	var st: Variant = d.get("stations")
	if not (st is Array) or (st as Array).size() != 5:
		err.append("stations needs 5 entries (ids 0..4)")
	var pd: Variant = d.get("pads")
	if not (pd is Array) or (pd as Array).size() != 4:
		err.append("pads needs 4 entries")
	var wh: Variant = d.get("wheels")
	if not (wh is Array) or (wh as Array).size() != 4:
		err.append("wheels needs 4 entries")
	for k: String in ["bridge", "plaza", "gate", "camera"]:
		if not (d.get(k) is Dictionary):
			err.append("%s is missing" % k)
	if not (d.get("staging") is Array) or (d.get("staging") as Array).is_empty():
		err.append("staging is missing")
	return err


static func from_dict(d: Dictionary) -> SiegePath:
	var m := SiegePath.new()
	m.data = d
	m.id = str(d.get("id", ""))
	var path: Dictionary = d.get("path", {}) if d.get("path") is Dictionary else {}
	for q: Variant in path.get("points", []):
		if q is Array and (q as Array).size() == 3:
			m.points.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	m.cum.append(0.0)
	for i in range(1, m.points.size()):
		var a := m.points[i - 1]
		var b := m.points[i]
		m.cum.append(m.cum[i - 1] + Vector2(b.x - a.x, b.y - a.y).length())
	m.length_m = m.cum[m.cum.size() - 1] if m.points.size() > 1 else 0.0
	var br: Dictionary = d.get("bridge", {}) if d.get("bridge") is Dictionary else {}
	m.bridge_from_m = float(br.get("from_prog_m", m.length_m))
	m.bridge_to_m = float(br.get("to_prog_m", m.length_m))
	m.moat_edge_m = float(d.get("moat_edge_prog_m", m.bridge_from_m))
	var pz: Dictionary = d.get("plaza", {}) if d.get("plaza") is Dictionary else {}
	m.plaza_center = _v2(pz.get("center", [0, 0]))
	m.plaza_radius_m = float(pz.get("radius_m", 8.0))
	var gt: Dictionary = d.get("gate", {}) if d.get("gate") is Dictionary else {}
	m.gate_pos = _v3(gt.get("pos", [0, 0, 0]))
	for s: Variant in d.get("staging", []):
		if s is Dictionary:
			m.staging.append(float(s.get("prog_m", 0.0)))
	m.station_pos.resize(5)
	m.station_muzzle_m.resize(5)
	m.station_yaw0_deg.resize(5)
	for s: Variant in d.get("stations", []):
		if s is Dictionary and int(s.get("id", -1)) in range(5):
			var i := int(s["id"])
			m.station_pos[i] = _v3(s.get("pos", [0, 0, 0]))
			m.station_muzzle_m[i] = float(s.get("muzzle_m", 0.0))
			m.station_yaw0_deg[i] = float(s.get("yaw0_deg", 0.0))
	m.pads.resize(4)
	for p: Variant in d.get("pads", []):
		if p is Dictionary and int(p.get("pad", 0)) in range(1, 5):
			m.pads[int(p["pad"]) - 1] = _v3(p.get("pos", [0, 0, 0]))
	m.wheels.resize(4)
	for w: Variant in d.get("wheels", []):
		if w is Dictionary and int(w.get("slot", -1)) in range(4):
			m.wheels[int(w["slot"])] = _v3(w.get("pos", [0, 0, 0]))
			m.wheel_radius_m = float(w.get("radius_m", m.wheel_radius_m))
	var cam: Dictionary = d.get("camera", {}) if d.get("camera") is Dictionary else {}
	m.cam_k = float(cam.get("k", 3.5))
	m.cam_ox = float(cam.get("ox", 450.0))
	m.cam_oy = float(cam.get("oy", 127.0))
	return m


# --- Along the path ------------------------------------------------------------------------------


## Index i of the segment [i, i + 1] that holds `prog` (clamped to the path).
func segment_at(prog: float) -> int:
	var n := points.size()
	if n < 2:
		return 0
	var lo := 0
	var hi := n - 2
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= prog:
			lo = mid
		else:
			hi = mid - 1
	return lo


## The world point at `prog` metres from the camp, `lat` metres left of travel.
func point_at(prog: float, lat: float = 0.0) -> Vector3:
	if points.size() < 2:
		return points[0] if points.size() == 1 else Vector3.ZERO
	var p := clampf(prog, 0.0, length_m)
	var i := segment_at(p)
	var a := points[i]
	var b := points[i + 1]
	var seg := maxf(cum[i + 1] - cum[i], 0.0001)
	var at := a.lerp(b, (p - cum[i]) / seg)
	if lat != 0.0:
		var d := Vector2(b.x - a.x, b.y - a.y).normalized()
		at += Vector3(d.y, -d.x, 0.0) * lat
	return at


## Unit travel direction on the ground at `prog`.
func dir_at(prog: float) -> Vector2:
	if points.size() < 2:
		return Vector2.DOWN
	var i := segment_at(clampf(prog, 0.0, length_m))
	var a := points[i]
	var b := points[i + 1]
	return Vector2(b.x - a.x, b.y - a.y).normalized()


func dist_to_gate(prog: float) -> float:
	return maxf(length_m - prog, 0.0)


func on_bridge(prog: float) -> bool:
	return prog >= bridge_from_m and prog <= bridge_to_m


## Ground height under (x, y): the z of the nearest path point within GROUND_REACH_M, else 0.
func ground_z(x: float, y: float) -> float:
	var best := GROUND_REACH_M * GROUND_REACH_M
	var z := 0.0
	for q in points:
		var d2 := (q.x - x) * (q.x - x) + (q.y - y) * (q.y - y)
		if d2 < best:
			best = d2
			z = q.z
	return z


## Ground distance from (x, y) to the path point at `prog`.
func ground_dist(from: Vector3, prog: float) -> float:
	var p := point_at(prog)
	return Vector2(p.x - from.x, p.y - from.y).length()


# --- Stations ------------------------------------------------------------------------------------


## The launch point of station `id` aimed at `yaw_deg` (pivot + muzzle offset along the aim).
func muzzle(id: int, yaw_deg: float) -> Vector3:
	var a := deg_to_rad(yaw_deg)
	return station_pos[id] + Vector3(cos(a), sin(a), 0.0) * station_muzzle_m[id]


## Yaw in degrees (atan2(dy, dx)) from a station or pad position to a world point.
static func yaw_to(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(to.y - from.y, to.x - from.x))


# --- Art space -----------------------------------------------------------------------------------


func to_art(p: Vector3) -> Vector2:
	return Vector2((p.x - p.y) * cam_k + cam_ox, (p.x + p.y) * cam_k * 0.5 - p.z * cam_k + cam_oy)


static func depth(p: Vector3) -> float:
	return p.x + p.y + p.z


static func _v2(v: Variant) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and (v as Array).size() >= 2 else Vector2.ZERO


static func _v3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO
