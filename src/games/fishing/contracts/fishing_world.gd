class_name FishingWorld
extends RefCounted
## The one ocean every boat shares (pure, deterministic, no rules state). Two kinds:
##
## - Roam (Free Roam contents): the fixed map from content/fishing/map.json. x runs from the dock
##   (x 0) out to sea; the boats stop at edge_x_m(); past length_m() the ocean pours off the
##   flat-earth edge into the void. map.json:
##     {"id": "roam", "label": key, "length_m": 9000, "edge_x_m": 8950,
##      "zones": [{"id": "dock", "x_m": [0, 300], "colour": "#c9b48a", "label": key}, ...],
##      "floor_m": [[x_m, depth_m], ...]}
##   zones tile [0, length_m] left to right without gaps, ids from ZONES. floor_m is a piecewise
##   linear sea-floor profile, x ascending from 0; a depth of -1 means "no floor" from that x on
##   (the abyss: floor_depth_m() returns INF there).
## - Endless (workouts): generated from the session seed so nobody has to turn around. The dock
##   sits at [0, DOCK_M]; after it the zones follow ENDLESS_TOUR again and again, each segment
##   SEG_MIN_M..SEG_MAX_M long (seeded), with no abyss and no edge (length_m() and edge_x_m() are
##   INF). The view shows a window around the boats.
##
## The floor everywhere: the profile (roam) or each zone's base depth eased across segment
## borders (endless), plus a small seeded relief (+-RELIEF_FRAC of the depth, two octaves of value
## noise), so the minimap and the scenery agree. For the view: sample_floor(x0, x1, n) and
## minimap(n) are cheap batch samplers; zone colours are "#rrggbb" defaults the view may restyle.

const ZONES: Array[String] = ["dock", "shallows", "reef", "shelf", "deep", "abyss"]
## Zone base depth (m) for the endless map, by ZONES index (the abyss never occurs there).
const ZONE_DEPTH_M: Array[float] = [4.0, 12.0, 30.0, 110.0, 420.0, 600.0]
const ZONE_COLOURS: Array[String] = [
	"#c9b48a", "#7fc4b8", "#4f9c94", "#357a86", "#22546e", "#13304a"
]
const ENDLESS_TOUR: Array[String] = ["shallows", "reef", "shelf", "deep", "shelf", "reef"]
const DOCK_M := 300.0
const SEG_MIN_M := 1200.0
const SEG_MAX_M := 2200.0
## Endless floors ease between zone depths over this many metres at each segment border.
const EASE_M := 400.0
const RELIEF_FRAC := 0.06
## Relief noise wavelengths (m).
const RELIEF_L1 := 230.0
const RELIEF_L2 := 61.0
const ROAM_MAP_ID := "roam"

var id: String = ""
var label: String = ""
var endless: bool = false
var map_seed: int = 0
var _length_m: float = INF
var _edge_x_m: float = INF
## [{id, x0, x1, colour, label}] in x order (endless: generated on demand, never shrinks).
var _zones: Array[Dictionary] = []
## Roam profile, flat: [x, depth, x, depth, ...]; depth < 0 = no floor from there on.
var _floor: PackedFloat64Array = PackedFloat64Array()
## Seeded salt for the relief noise.
var _salt: int = 0


## The fixed roam map from a parsed map.json (check errors() first; null when invalid).
static func from_map(d: Variant, p_seed: int = 0) -> FishingWorld:
	if not errors(d).is_empty():
		return null
	var w := FishingWorld.new()
	var m: Dictionary = d
	w.id = str(m.get("id", ROAM_MAP_ID))
	w.label = str(m.get("label", ""))
	w.map_seed = p_seed
	w._salt = FishingRandom.mix32(0x5EAF100D)
	w._length_m = float(m["length_m"])
	w._edge_x_m = float(m["edge_x_m"])
	for z: Dictionary in m["zones"]:
		var zi := ZONES.find(str(z["id"]))
		(
			w
			. _zones
			. append(
				{
					"id": str(z["id"]),
					"x0": float(z["x_m"][0]),
					"x1": float(z["x_m"][1]),
					"colour": str(z.get("colour", ZONE_COLOURS[zi])),
					"label": str(z.get("label", "FISHING_ZONE_%s" % str(z["id"]).to_upper())),
				}
			)
		)
	for p: Array in m["floor_m"]:
		w._floor.append(float(p[0]))
		w._floor.append(float(p[1]))
	return w


## The endless workout map for `p_seed` (the same on every peer).
static func endless_for(p_seed: int) -> FishingWorld:
	var w := FishingWorld.new()
	w.id = "endless"
	w.endless = true
	w.map_seed = p_seed
	w._salt = FishingRandom.mix32((p_seed & 0xFFFFFFFF) ^ 0x0E0D1E55)
	w._zones.append(_zone("dock", 0.0, DOCK_M))
	return w


static func _zone(zid: String, x0: float, x1: float) -> Dictionary:
	return {
		"id": zid,
		"x0": x0,
		"x1": x1,
		"colour": ZONE_COLOURS[ZONES.find(zid)],
		"label": "FISHING_ZONE_%s" % zid.to_upper(),
	}


## Map length in metres (INF on the endless map).
func length_m() -> float:
	return _length_m


## The farthest x a boat may reach (it stops there); INF on the endless map.
func edge_x_m() -> float:
	return _edge_x_m


## The zone id at x (x < 0 counts as the dock, past the map as the last zone).
func zone_at(x_m: float) -> String:
	return str(_zone_dict(x_m)["id"])


## ZONES index of zone_at(x).
func zone_index_at(x_m: float) -> int:
	return ZONES.find(zone_at(x_m))


## The zones overlapping [x0, x1] (default: the whole roam map, or the endless map's first
## 20 km), each {id, x0, x1, colour, label}, in x order. Copies: safe to keep.
func zones(x0: float = 0.0, x1: float = -1.0) -> Array[Dictionary]:
	if x1 < x0:
		x1 = _length_m if not endless else 20000.0
	_extend_to(x1)
	var out: Array[Dictionary] = []
	for z in _zones:
		if float(z["x1"]) > x0 and float(z["x0"]) <= x1:
			out.append(z.duplicate())
	return out


## Sea-floor depth in metres below the surface at x (> 0), or INF where there is no floor (the
## abyss and past the edge).
func floor_depth_m(x_m: float) -> float:
	var base := _base_depth(x_m)
	if is_inf(base):
		return INF
	return base * (1.0 + RELIEF_FRAC * _relief(x_m))


## True where the floor drops away (floor_depth_m is INF).
func has_floor(x_m: float) -> bool:
	return not is_inf(floor_depth_m(x_m))


## n floor depths evenly spaced over [x0, x1] (both ends included; n >= 2). INF entries where
## there is no floor. One call per frame per layer is cheap.
func sample_floor(x0: float, x1: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	n = maxi(n, 2)
	out.resize(n)
	for i in n:
		out[i] = floor_depth_m(lerpf(x0, x1, float(i) / float(n - 1)))
	return out


## The minimap strip: {"x0", "x1", "floor": PackedFloat32Array(n), "zones": zones(x0, x1)}.
## Roam: the whole map [0, length_m]. Endless: pass the window (x0, x1) around the boats.
func minimap(n: int, x0: float = 0.0, x1: float = -1.0) -> Dictionary:
	if x1 <= x0:
		x1 = _length_m if not endless else x0 + 4000.0
	return {"x0": x0, "x1": x1, "floor": sample_floor(x0, x1, n), "zones": zones(x0, x1)}


## Every problem with a parsed map.json ([] when valid).
static func errors(d: Variant) -> Array[String]:
	var out: Array[String] = []
	if not d is Dictionary:
		out.append("map.json: not an object")
		return out
	var m: Dictionary = d
	var length := float(m.get("length_m", 0))
	var edge := float(m.get("edge_x_m", 0))
	if length <= 0.0:
		out.append("map.json: length_m must be positive")
	if edge <= 0.0 or edge > length:
		out.append("map.json: edge_x_m must be in (0, length_m]")
	var zs: Variant = m.get("zones")
	if not zs is Array or (zs as Array).is_empty():
		out.append("map.json: zones must be a non-empty array")
	else:
		var at := 0.0
		for z: Variant in zs:
			if not z is Dictionary or not ZONES.has(str((z as Dictionary).get("id", ""))):
				out.append("map.json: a zone has an unknown id (expected one of %s)" % [ZONES])
				continue
			var xr: Variant = z.get("x_m")
			if not xr is Array or (xr as Array).size() != 2 or float(xr[1]) <= float(xr[0]):
				out.append("map.json: zone %s needs x_m [x0, x1] with x0 < x1" % z["id"])
				continue
			if absf(float(xr[0]) - at) > 1e-6:
				out.append("map.json: zone %s must start at %s (no gaps)" % [z["id"], at])
			at = float(xr[1])
		if absf(at - length) > 1e-6:
			out.append("map.json: the zones must end at length_m")
	var fl: Variant = m.get("floor_m")
	if not fl is Array or (fl as Array).size() < 2:
		out.append("map.json: floor_m needs at least two [x_m, depth_m] points")
	else:
		var px := -1.0
		for p: Variant in fl:
			if not p is Array or (p as Array).size() != 2:
				out.append("map.json: a floor point is not [x_m, depth_m]")
				break
			if float(p[0]) <= px:
				out.append("map.json: floor_m x must ascend")
				break
			if float(p[1]) == 0.0 or float(p[1]) < -1.0:
				out.append("map.json: floor depth must be positive (or -1: no floor)")
				break
			px = float(p[0])
		if (fl as Array).size() >= 2 and absf(float(fl[0][0])) > 1e-6:
			out.append("map.json: floor_m must start at x 0")
	return out


# --- internals --------------------------------------------------------------------------------


func _zone_dict(x_m: float) -> Dictionary:
	if x_m <= 0.0:
		return _zones[0]
	_extend_to(x_m)
	# Binary search: zones tile the axis in order.
	var lo := 0
	var hi := _zones.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(_zones[mid]["x0"]) <= x_m:
			lo = mid
		else:
			hi = mid - 1
	return _zones[lo]


## Endless: generates segments until x is covered (deterministic from the seed and the index).
func _extend_to(x_m: float) -> void:
	if not endless or is_inf(x_m):
		return
	while float(_zones[_zones.size() - 1]["x1"]) <= x_m:
		var k := _zones.size() - 1
		var r := FishingRandom.derive(map_seed, k, 0x7E)
		var x0 := float(_zones[k]["x1"])
		var seg_len := r.range_f(SEG_MIN_M, SEG_MAX_M)
		_zones.append(_zone(ENDLESS_TOUR[k % ENDLESS_TOUR.size()], x0, x0 + seg_len))


func _base_depth(x_m: float) -> float:
	if endless:
		return _endless_depth(x_m)
	if x_m >= _length_m:
		return INF
	var n := _floor.size() / 2
	if x_m <= _floor[0]:
		return _floor[1]
	for i in range(1, n):
		var x1 := _floor[2 * i]
		if x_m <= x1:
			var d0 := _floor[2 * i - 1]
			var d1 := _floor[2 * i + 1]
			if d1 < 0.0:
				return d0 if x_m < x1 else INF
			if d0 < 0.0:
				return INF
			var x0 := _floor[2 * i - 2]
			return lerpf(d0, d1, (x_m - x0) / (x1 - x0))
	var last := _floor[2 * n - 1]
	return INF if last < 0.0 else last


func _endless_depth(x_m: float) -> float:
	var z := _zone_dict(x_m)
	var d := ZONE_DEPTH_M[ZONES.find(str(z["id"]))]
	var x0 := float(z["x0"])
	if x_m < x0 + EASE_M and x0 > 0.0:
		var prev := _zone_dict(x0 - 1.0)
		var dp := ZONE_DEPTH_M[ZONES.find(str(prev["id"]))]
		var t := clampf((x_m - x0) / EASE_M, 0.0, 1.0)
		d = lerpf(dp, d, t * t * (3.0 - 2.0 * t))
	return d


## Two octaves of seeded value noise in [-1, 1].
func _relief(x_m: float) -> float:
	return (
		0.65 * _value_noise(x_m / RELIEF_L1, _salt)
		+ 0.35 * _value_noise(x_m / RELIEF_L2, _salt ^ 0x9E37)
	)


static func _value_noise(u: float, salt: int) -> float:
	var i := floori(u)
	var f := u - float(i)
	var a := _lattice(i, salt)
	var b := _lattice(i + 1, salt)
	return lerpf(a, b, f * f * (3.0 - 2.0 * f))


static func _lattice(i: int, salt: int) -> float:
	var h := FishingRandom.mix32((i * 0x27D4EB2D) ^ salt)
	return float(h) / 2147483647.5 - 1.0
