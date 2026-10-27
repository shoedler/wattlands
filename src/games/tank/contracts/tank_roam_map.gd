class_name TankRoamMap
extends RefCounted
## The free-roam valley (brief 2.10 Map): one long road, about 6 km, built at the session start
## from a seed and content/tank/roam/valley.json. Every peer builds the same map from the same seed
## (the host draws it from ctx.rng; the snapshot carries it), so the rules, the view and the HUD agree
## without sending the map. Pure: a small LCG of its own (never a new engine RNG object, never
## the global RNG), seeded only by `map_seed`.
##
## Layout, west (0 m) to east (length_m): the forest at both ends (each with its turning place),
## and between them the lake shore, the village, the quarry and the meadow once each in a seeded
## order, some of them separated by more forest (valley.json forest_between). Zone lengths are drawn
## from each zone's len_m and scaled so they fill the road. Terrain points ([m, grade %] for travel
## east, valley.json terrain_step_m apart) are drawn from each zone's terrain_pct, change at most
## terrain_max_step_pct from one point to the next and are 0 over end_flat_m at both ends; travelling
## west the grade is the negation (TankTerrain.for_roam clamps it to the valley's terrain_pct). The
## strongpoints sit at fixed spots inside the zones valley.json strongpoints.zones lists.

const LCG_A := 1103515245
const LCG_C := 12345
const LCG_M := 0x7FFFFFFF

var map_seed: int = 0
var length_m: float = 6000.0
## [{id, label, from_m, to_m}] west to east, contiguous, covering 0..length_m.
var zones: Array[Dictionary] = []
## [[m, grade_pct], ...] ascending, for travel east (dir +1).
var terrain: Array = []
## Strongpoint spots (the centre of each, m), ascending.
var strongpoints: PackedFloat32Array = PackedFloat32Array()
## Where the hull's centre may stand: the road stops at the turning places.
var lo_m: float = 60.0
var hi_m: float = 5940.0

var _s: int = 1


## The valley of `valley` (validated valley.json) for `seed`.
static func build(valley: Dictionary, seed_value: int) -> TankRoamMap:
	var m := TankRoamMap.new()
	m.map_seed = seed_value
	m._s = (absi(seed_value) % LCG_M) + 1
	m._generate(valley)
	return m


func _next() -> float:
	_s = (_s * LCG_A + LCG_C) & LCG_M
	return float(_s) / float(LCG_M + 1)


func _range(r: Variant, fallback: Array) -> Vector2:
	var a: Array = r if r is Array and (r as Array).size() == 2 else fallback
	return Vector2(float(a[0]), float(a[1]))


func _between(r: Vector2) -> float:
	return r.x + (r.y - r.x) * _next()


func _generate(valley: Dictionary) -> void:
	length_m = roundf(_between(_range(valley.get("length_m"), [6000, 6000])))
	var end_m := float(valley.get("end_m", 60.0))
	lo_m = end_m
	hi_m = length_m - end_m
	_zones(valley)
	_terrain(valley)
	_strongpoints(valley)


func _zones(valley: Dictionary) -> void:
	var defs: Dictionary = valley.get("zones", {})
	var middle: Array = (valley.get("middle", []) as Array).duplicate()
	# A seeded shuffle (Fisher-Yates on the map's own LCG).
	for i in range(middle.size() - 1, 0, -1):
		var j := mini(int(_next() * float(i + 1)), i)
		var t: Variant = middle[i]
		middle[i] = middle[j]
		middle[j] = t
	var order: Array[String] = [str(valley.get("first_zone", TankIds.ZONE_FOREST))]
	var between := float(valley.get("forest_between", 0.5))
	for k in middle.size():
		order.append(str(middle[k]))
		if k < middle.size() - 1 and _next() < between:
			order.append(TankIds.ZONE_FOREST)
	order.append(str(valley.get("last_zone", TankIds.ZONE_FOREST)))
	var lens: Array[float] = []
	var total := 0.0
	for id in order:
		var d: Dictionary = defs.get(id, {})
		var l := _between(_range(d.get("len_m"), [800, 800]))
		lens.append(l)
		total += l
	var k_scale := length_m / maxf(total, 1.0)
	var at := 0.0
	zones.clear()
	for i in order.size():
		var to := length_m if i == order.size() - 1 else roundf(at + lens[i] * k_scale)
		var d2: Dictionary = defs.get(order[i], {})
		zones.append({"id": order[i], "label": str(d2.get("label", "")), "from_m": at, "to_m": to})
		at = to


func _terrain(valley: Dictionary) -> void:
	var defs: Dictionary = valley.get("zones", {})
	var step := _range(valley.get("terrain_step_m"), [200, 200])
	var max_step := float(valley.get("terrain_max_step_pct", 2.5))
	var bounds := _range(valley.get("terrain_pct"), [-3, 5])
	var flat := float(valley.get("end_flat_m", 200.0))
	terrain = [[0.0, 0.0], [flat, 0.0]]
	var m := flat
	var g := 0.0
	while true:
		m += _between(step)
		if m >= length_m - flat:
			break
		var zr := _range((defs.get(zone_at(m), {}) as Dictionary).get("terrain_pct"), [0, 0])
		var want := _between(zr)
		g = clampf(want, g - max_step, g + max_step)
		g = clampf(g, maxf(zr.x, bounds.x), minf(zr.y, bounds.y))
		terrain.append([roundf(m), snappedf(g, 0.1)])
	terrain.append([length_m - flat, 0.0])
	terrain.append([length_m, 0.0])


func _strongpoints(valley: Dictionary) -> void:
	var sp: Dictionary = valley.get("strongpoints", {})
	var allowed: Array = sp.get("zones", [])
	var gap := float(sp.get("min_gap_m", 800.0))
	var clear := float(sp.get("clear_ends_m", 600.0))
	var spots: Array[float] = []
	for z: Dictionary in zones:
		if not allowed.has(z["id"]):
			continue
		var a := maxf(float(z["from_m"]) + 100.0, clear)
		var b := minf(float(z["to_m"]) - 100.0, length_m - clear)
		if b <= a:
			continue
		var at := roundf(a + (b - a) * (0.3 + 0.4 * _next()))
		var ok := true
		for s in spots:
			if absf(s - at) < gap:
				ok = false
		if ok:
			spots.append(at)
	spots.sort()
	strongpoints = PackedFloat32Array(spots)


# --- Queries --------------------------------------------------------------------------------------


## The zone at `m` (its id), the first or last zone past either end.
func zone_at(m: float) -> String:
	var i := zone_index_at(m)
	return str(zones[i]["id"]) if i >= 0 else TankIds.ZONE_FOREST


## The index of the zone at `m` in `zones` (-1 without zones).
func zone_index_at(m: float) -> int:
	if zones.is_empty():
		return -1
	for i in zones.size():
		if m < float(zones[i]["to_m"]):
			return i
	return zones.size() - 1


## The raw grade (% before difficulty, unclamped) under `m` for travel in `dir` (+1 east, -1 west).
func grade_at(m: float, dir: int) -> float:
	var g := TankTerrain.grade_at(terrain, m)
	return g if dir >= 0 else -g


## The road's height profile for the HUD's map strip: `n` heights 0..1 at even steps (the grade
## integrated from the west end, normalized).
func profile(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if n < 2:
		return out
	var h := 0.0
	var lo := 0.0
	var hi := 0.0
	var step := length_m / float(n - 1)
	var raw: Array[float] = [0.0]
	for i in range(1, n):
		var m := step * float(i)
		h += TankTerrain.grade_at(terrain, m - step * 0.5) / 100.0 * step
		raw.append(h)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	for v in raw:
		out.append((v - lo) / maxf(hi - lo, 1.0))
	return out
