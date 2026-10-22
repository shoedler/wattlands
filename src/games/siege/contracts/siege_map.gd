class_name SiegeMap
extends RefCounted
## The battlefield geometry of one map (content/siege/maps/<id>.json, brief 2.9 and 3 "Scene").
## Pure and deterministic: the rules (ranges, enemy positions), Autopilot, the view (roads,
## pads, chains) and the tests all read the same numbers from here. G0 contract.
##
## Coordinates are metres on the ground plane: Vector2(x, z) with x to the east (screen
## right) and z to the south (toward the camera). The fort's centre is the origin; its gate is
## in the south wall and faces the camera. Heights are the view's business (terrain section).
##
## JSON fields (validate() enforces each):
##   id (String), name (string key), fort {size [w, d] m, wall_h_m, wall_t_m},
##   generator {pos [x, z], radius_m}, gate {pos, width_m}, plaza {center, radius_m},
##   wheels [{slot 0..3, name, pos}] (NW, NE, SW, SE), pads [{pad 1..8, pos, wall}],
##   ring [8 pad numbers, clockwise on screen: "right" / "swap" moves to the next],
##   roads [{id 0..2, name, points [[x, z], ...] spawn first, gate last}] (West, Valley, East),
##   wall_walk {nodes {id: [x, z]}, edges [[a, b], ...], wheel_nodes {"0".."3": id},
##   pad_nodes {"1".."8": id}} (chains route along it), terrain {...} and scatter {seed, area
##   [x, z, w, d], counts {cypress, olive, rocks}, road_clear_m, exclude_circles [[x, z, r]],
##   exclude_rects [[x, z, w, d]]}, lake {center, radius_m}, camera {target [x, y, z],
##   pitch_deg, fov_deg, yaw_deg}. terrain, lake and camera are the view's (B3) to read.

var id: String = ""
var data: Dictionary = {}
var fort_size: Vector2 = Vector2(64, 52)
var generator_pos: Vector2 = Vector2.ZERO
var gate_pos: Vector2 = Vector2.ZERO
var plaza_center: Vector2 = Vector2.ZERO
var plaza_radius_m: float = 12.0
## slot 0..3 -> wheel centre.
var wheels: Array[Vector2] = []
## pad 1..8 -> position (index pad - 1).
var pads: Array[Vector2] = []
## Pad numbers in clockwise screen order.
var ring: Array[int] = []
## road -> polyline (spawn first, gate last).
var roads: Array[PackedVector2Array] = []
## road -> cumulative length at each point (cum[0] == 0, cum[-1] == length).
var _cum: Array[PackedFloat32Array] = []
var _nodes: Dictionary = {}
var _adj: Dictionary = {}
var _wheel_nodes: Dictionary = {}
var _pad_nodes: Dictionary = {}


## A map from its JSON (call validate() first; a bad file gives a half-filled map).
static func from_dict(d: Dictionary) -> SiegeMap:
	var m := SiegeMap.new()
	m.data = d
	m.id = str(d.get("id", ""))
	var fort: Dictionary = d.get("fort", {})
	m.fort_size = _v2(fort.get("size", [64, 52]))
	m.generator_pos = _v2((d.get("generator", {}) as Dictionary).get("pos", [0, 0]))
	m.gate_pos = _v2((d.get("gate", {}) as Dictionary).get("pos", [0, 0]))
	var plaza: Dictionary = d.get("plaza", {})
	m.plaza_center = _v2(plaza.get("center", [0, 0]))
	m.plaza_radius_m = float(plaza.get("radius_m", 12.0))
	m.wheels.resize(4)
	for w: Variant in d.get("wheels", []):
		if w is Dictionary and int(w.get("slot", -1)) in range(4):
			m.wheels[int(w["slot"])] = _v2(w.get("pos", [0, 0]))
	m.pads.resize(SiegeIds.PAD_COUNT)
	for p: Variant in d.get("pads", []):
		if p is Dictionary and SiegeIds.is_pad(int(p.get("pad", 0))):
			m.pads[int(p["pad"]) - 1] = _v2(p.get("pos", [0, 0]))
	for n: Variant in d.get("ring", []):
		m.ring.append(int(n))
	for r: Variant in d.get("roads", []):
		var pts := PackedVector2Array()
		for q: Variant in (r as Dictionary).get("points", []) if r is Dictionary else []:
			pts.append(_v2(q))
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		m.roads.append(pts)
		m._cum.append(cum)
	var ww: Dictionary = d.get("wall_walk", {})
	for k: Variant in ww.get("nodes", {}) as Dictionary:
		m._nodes[str(k)] = _v2(ww["nodes"][k])
		m._adj[str(k)] = []
	for e: Variant in ww.get("edges", []):
		if (
			e is Array
			and (e as Array).size() == 2
			and m._adj.has(str(e[0]))
			and m._adj.has(str(e[1]))
		):
			(m._adj[str(e[0])] as Array).append(str(e[1]))
			(m._adj[str(e[1])] as Array).append(str(e[0]))
	for k: Variant in ww.get("wheel_nodes", {}) as Dictionary:
		m._wheel_nodes[int(str(k))] = str(ww["wheel_nodes"][k])
	for k: Variant in ww.get("pad_nodes", {}) as Dictionary:
		m._pad_nodes[int(str(k))] = str(ww["pad_nodes"][k])
	return m


## Problems with a map JSON (empty = valid). Checks every field listed in the class doc.
static func validate(d: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not (d is Dictionary):
		errs.append("map: not a JSON object")
		return errs
	for k: String in [
		"id", "name", "fort", "generator", "gate", "plaza", "wheels", "pads", "ring", "roads"
	]:
		if not d.has(k):
			errs.append("map: missing %s" % k)
	for k: String in ["wall_walk", "terrain", "scatter", "camera"]:
		if not (d.get(k) is Dictionary):
			errs.append("map: %s must be an object" % k)
	if not errs.is_empty():
		return errs
	if not _is_v2(d["fort"].get("size")):
		errs.append("map: fort.size must be [w, d]")
	for k: String in ["generator", "gate"]:
		if not _is_v2(d[k].get("pos")):
			errs.append("map: %s.pos must be [x, z]" % k)
	if not _is_v2(d["plaza"].get("center")) or not _num(d["plaza"].get("radius_m")):
		errs.append("map: plaza needs center [x, z] and radius_m")
	var slots := {}
	for w: Variant in d["wheels"]:
		if (
			not (w is Dictionary)
			or not _is_v2(w.get("pos"))
			or not (int(w.get("slot", -1)) in range(4))
		):
			errs.append("map: bad wheel %s" % JSON.stringify(w))
		else:
			slots[int(w["slot"])] = true
	if slots.size() != 4:
		errs.append("map: needs wheels for slots 0..3")
	var pads := {}
	for p: Variant in d["pads"]:
		if (
			not (p is Dictionary)
			or not _is_v2(p.get("pos"))
			or not SiegeIds.is_pad(int(p.get("pad", 0)))
		):
			errs.append("map: bad pad %s" % JSON.stringify(p))
		else:
			pads[int(p["pad"])] = true
	if pads.size() != SiegeIds.PAD_COUNT:
		errs.append("map: needs pads 1..%d" % SiegeIds.PAD_COUNT)
	var ring: Array = d["ring"].map(func(n: Variant) -> int: return int(n))
	var sorted := ring.duplicate()
	sorted.sort()
	if sorted != range(1, SiegeIds.PAD_COUNT + 1):
		errs.append("map: ring must list pads 1..8 once each")
	if not (d["roads"] is Array) or (d["roads"] as Array).size() != SiegeIds.ROAD_COUNT:
		errs.append("map: needs %d roads" % SiegeIds.ROAD_COUNT)
	else:
		for i in SiegeIds.ROAD_COUNT:
			var r: Variant = d["roads"][i]
			var ok: bool = (
				r is Dictionary and int(r.get("id", -1)) == i and r.get("points") is Array
			)
			if ok and (r["points"] as Array).size() >= 2:
				for q: Variant in r["points"]:
					ok = ok and _is_v2(q)
			else:
				ok = false
			if not ok:
				errs.append("map: road %d needs id %d and >= 2 points [x, z]" % [i, i])
	var ww: Dictionary = d["wall_walk"]
	for k: String in ["nodes", "wheel_nodes", "pad_nodes"]:
		if not (ww.get(k) is Dictionary):
			errs.append("map: wall_walk.%s must be an object" % k)
	if not (ww.get("edges") is Array):
		errs.append("map: wall_walk.edges must be an array")
	var sc: Dictionary = d["scatter"]
	if (
		not _num(sc.get("seed"))
		or not (sc.get("counts") is Dictionary)
		or not (sc.get("area") is Array)
	):
		errs.append("map: scatter needs seed, area and counts")
	return errs


func road_count() -> int:
	return roads.size()


func road_length(road: int) -> float:
	return float(_cum[road][-1])


## The point `prog_m` metres along `road` from its spawn, offset `lat_m` to the left of the
## direction of travel (positive = left). prog is clamped to [0, length].
func point_at(road: int, prog_m: float, lat_m: float = 0.0) -> Vector2:
	var pts := roads[road]
	var cum := _cum[road]
	var p := clampf(prog_m, 0.0, float(cum[-1]))
	var i := 1
	while i < pts.size() - 1 and float(cum[i]) < p:
		i += 1
	var seg := float(cum[i]) - float(cum[i - 1])
	var f := (p - float(cum[i - 1])) / seg if seg > 0.0 else 0.0
	var a := pts[i - 1]
	var b := pts[i]
	var at := a.lerp(b, f)
	if lat_m == 0.0:
		return at
	var dir := (b - a).normalized()
	return at + Vector2(dir.y, -dir.x) * lat_m


## Unit direction of travel at `prog_m`.
func dir_at(road: int, prog_m: float) -> Vector2:
	var pts := roads[road]
	var cum := _cum[road]
	var i := 1
	while i < pts.size() - 1 and float(cum[i]) < prog_m:
		i += 1
	return (pts[i] - pts[i - 1]).normalized()


## Shortest distance from `p` to the road's polyline.
func distance_to_road(p: Vector2, road: int) -> float:
	var pts := roads[road]
	var best := INF
	for i in range(1, pts.size()):
		best = minf(
			best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i]))
		)
	return best


func pad_pos(pad: int) -> Vector2:
	return pads[pad - 1]


## The wheel of slot 0..3 (NW, NE, SW, SE).
func wheel_pos(slot: int) -> Vector2:
	return wheels[slot % 4]


## The next (step 1) or previous (step -1) pad in ring order after `pad`; ring[0] / ring[-1]
## from the generator (TARGET_GEN).
func ring_step(pad: int, step: int) -> int:
	if ring.is_empty():
		return SiegeIds.TARGET_GEN
	var i := ring.find(pad)
	if i < 0:
		return ring[0] if step > 0 else ring[-1]
	return ring[posmod(i + step, ring.size())]


## The wall-walk polyline a tower route's chain follows from slot's wheel to `pad` (shortest
## path through wall_walk; starts at the wheel, ends at the pad). Empty if unreachable.
func chain_path(slot: int, pad: int) -> PackedVector2Array:
	var start: String = _wheel_nodes.get(slot % 4, "")
	var goal: String = _pad_nodes.get(pad, "")
	var out := PackedVector2Array()
	if start == "" or goal == "" or not _adj.has(start) or not _adj.has(goal):
		return out
	var dist := {start: 0.0}
	var prev := {}
	var open: Array[String] = [start]
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[bi]]):
				bi = i
		var u: String = open[bi]
		open.remove_at(bi)
		if u == goal:
			break
		for v: String in _adj[u]:
			var nd := float(dist[u]) + (_nodes[u] as Vector2).distance_to(_nodes[v])
			if not dist.has(v) or nd < float(dist[v]) - 1e-6:
				dist[v] = nd
				prev[v] = u
				if not open.has(v):
					open.append(v)
	if not dist.has(goal):
		return out
	var node := goal
	while true:
		out.insert(0, _nodes[node])
		if node == start:
			break
		node = prev[node]
	return out


static func _v2(a: Variant) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


static func _is_v2(a: Variant) -> bool:
	return a is Array and (a as Array).size() == 2 and _num(a[0]) and _num(a[1])


static func _num(v: Variant) -> bool:
	return v is float or v is int
