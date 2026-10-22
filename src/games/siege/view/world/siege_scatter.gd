class_name SiegeScatter
extends RefCounted
## Cypress, olive trees and rocks on the hill (brief 3 "Scatter"): about 600 + 400 + 300
## MultiMesh instances from the map's fixed seed, kept off the fort, the gate plaza and the
## roads. Three draw calls, no nodes per tree. The area is the map's scatter area clipped to
## what the miniature camera can see, so the trees stay dense where they show.

## What the camera can see around the fort (x, z, w, d), in metres.
const VIEW_RECT := Rect2(-170.0, -140.0, 340.0, 330.0)
const ROAD_EXCLUDE_STEP_M := 7.0
const ROAD_EXCLUDE_EXTRA_M := 3.5


static func cypress_mesh() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	m.add_cylinder(0.25, 0.2, 1.0, 5, SiegePalette.WOOD_DARK, _at(0.0, 0.5, 0.0))
	m.add_cylinder(1.0, 0.0, 6.0, 6, SiegePalette.OLIVE_DARK, _at(0.0, 4.0, 0.0))
	m.darken_near_ground(0.0, 1.6, 0.4)
	return m


static func olive_mesh() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	m.add_cylinder(0.3, 0.22, 1.4, 5, SiegePalette.WOOD, _at(0.0, 0.7, 0.0))
	m.add_sphere(
		1.9,
		3,
		6,
		SiegePalette.OLIVE,
		Transform3D(Basis().scaled(Vector3(1.2, 0.8, 1.2)), Vector3(0.0, 2.3, 0.0))
	)
	m.darken_near_ground(0.0, 1.8, 0.4)
	return m


static func rock_mesh() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	m.add_sphere(
		1.0,
		2,
		5,
		SiegePalette.ROCK,
		Transform3D(Basis().scaled(Vector3(1.3, 0.7, 1.0)), Vector3(0.0, 0.25, 0.0))
	)
	m.darken_near_ground(0.0, 0.5, 0.35)
	return m


## The exclusion zones for the map: the fort and plaza rects/circles from the map data, plus a
## chain of circles along each road.
static func exclusions(map: SiegeMap) -> Array:
	var sc: Dictionary = map.data.get("scatter", {})
	var out: Array = []
	for r: Variant in sc.get("exclude_rects", []):
		out.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	for c: Variant in sc.get("exclude_circles", []):
		out.append(Vector3(float(c[0]), float(c[1]), float(c[2])))
	var clear := float(sc.get("road_clear_m", 5.0)) + ROAD_EXCLUDE_EXTRA_M
	for road in map.road_count():
		var length := map.road_length(road)
		var d := 0.0
		while d <= length:
			var p := map.point_at(road, d)
			out.append(Vector3(p.x, p.y, clear))
			d += ROAD_EXCLUDE_STEP_M
	return out


## Builds the three scatter MultiMeshes: [cypress, olive, rocks].
static func build(map: SiegeMap, terrain: SiegeTerrain) -> Array[MultiMeshScatter]:
	var sc: Dictionary = map.data.get("scatter", {})
	var counts: Dictionary = sc.get("counts", {})
	var base_seed := int(sc.get("seed", 7331))
	var area_v: Array = sc.get("area", [-220, -200, 440, 400])
	var area := Rect2(float(area_v[0]), float(area_v[1]), float(area_v[2]), float(area_v[3]))
	area = area.intersection(VIEW_RECT)
	var excl := exclusions(map)
	var kinds: Array[Dictionary] = [
		{
			"name": "Cypress",
			"mesh": cypress_mesh(),
			"count": int(counts.get("cypress", 600)),
			"scale": Vector2(0.55, 1.0),
			"spacing": 3.0,
			"colors": PackedColorArray([Color.WHITE, Color(0.9, 0.95, 0.85)]),
		},
		{
			"name": "Olive",
			"mesh": olive_mesh(),
			"count": int(counts.get("olive", 400)),
			"scale": Vector2(0.7, 1.15),
			"spacing": 4.0,
			"colors": PackedColorArray([Color.WHITE, Color(1.05, 1.0, 0.9)]),
		},
		{
			"name": "Rocks",
			"mesh": rock_mesh(),
			"count": int(counts.get("rocks", 300)),
			"scale": Vector2(0.6, 2.0),
			"spacing": 2.5,
			"colors": PackedColorArray([Color.WHITE, Color(0.85, 0.85, 0.85)]),
		},
	]
	var out: Array[MultiMeshScatter] = []
	var idx := 0
	for k in kinds:
		var mm := MultiMeshScatter.new()
		mm.name = str(k["name"])
		var lp: LowPolyMesh = k["mesh"]
		mm.setup(lp.build(), int(k["count"]), true, false)
		(
			mm
			. scatter(
				{
					"seed": SeededRng.derive(base_seed, str(k["name"])),
					"count": int(k["count"]),
					"area": area,
					"exclude": excl,
					"min_spacing": float(k["spacing"]),
					"scale": k["scale"],
					"height_jitter": 0.15,
					"tilt_deg": 4.0,
					"colors": k["colors"],
					"color_jitter": 0.06,
					"height": terrain.height_at,
					"y_offset": -0.1,
				}
			)
		)
		out.append(mm)
		idx += 1
	return out


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))
