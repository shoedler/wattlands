extends Node3D
## world3d kit demo (BRIEF 3.9): a small low-poly miniature in the style Siege will use.
## A plateau with a plain-walled fort, four treadwheels in the slot colors driving a bronze
## generator drum, roads, ~650 scattered trees and rocks (three MultiMeshes), a column of
## walking figures (one MultiMesh with the walk-bob shader), the miniature camera rig with a
## push-in and an occasional shake, the Compatibility sky, ambient, sun and depth-fog haze,
## and a 12% corner vignette. Every mesh is a LowPolyMesh; static geometry merges into one mesh per material.
## After 30 frames it prints one "world3d demo:" line with the draw calls and primitives.
## tools/screenshot captures this scene.

const SEED := 20261021
const MARBLE := Color("#e8e2d4")
const MARBLE_SHADE := Color("#cfc6b4")
const TERRACOTTA := Color("#b5553a")
const TERRACOTTA_LIGHT := Color("#cf7a55")
const BRONZE := Color("#b98c46")
const BRONZE_DARK := Color("#8a6a3b")
const OLIVE_DARK := Color("#48552b")
const OLIVE := Color("#66733a")
const OCHRE := Color("#c7a15a")
const DUST := Color("#dcc79c")
const WOOD := Color("#7a5333")
const WOOD_DARK := Color("#563a24")
const ROCK := Color("#8e8983")
const IRON := Color("#4a4a4e")
const CLOTH := Color("#6e5e4c")
const PLATEAU_Y := 4.0
const FORT_CENTER := Vector3(0, PLATEAU_Y, -6)
const FORT_SIZE := Vector2(64, 52)

var sky: SkyAmbient = null
var rig: MiniatureCameraRig = null
var wheels: Array[Node3D] = []
var drum: Node3D = null
var trees: Array[MultiMeshScatter] = []
var marchers: MultiMeshScatter = null
var road_path: PackedVector3Array = PackedVector3Array()

var _t: float = 0.0
var _frames: int = 0
var _next_shake: float = 6.0
var _walk_material: ShaderMaterial = null


func _ready() -> void:
	sky = SkyAmbient.new()
	add_child(sky)
	rig = MiniatureCameraRig.new()
	rig.target = Vector3(0, PLATEAU_Y, 14)
	rig.pitch_deg = 42.0
	rig.fov_deg = 32.0
	rig.fit_width(150.0)
	add_child(rig)
	rig.push_in(1.5, 4.0)

	road_path = _road_points()
	var scenery := LowPolyMesh.new()
	_add_terrain(scenery)
	_add_roads(scenery)
	_add_fort(scenery)
	_add_machines(scenery)
	sky.haze_mesh(scenery, rig.camera_position())
	add_child(scenery.make_instance("Scenery"))
	_add_scatter()
	_add_marchers()
	add_child(ScreenVignette.new())
	_add_caption()


func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	var power := 0.65 + 0.35 * sin(_t * 0.5)
	for i in wheels.size():
		wheels[i].rotation.z = -_t * (0.9 + 0.25 * i) * power
	drum.rotation.z = _t * 1.6 * power
	_update_marchers()
	if _t >= _next_shake:
		_next_shake += 7.0
		rig.shake(0.15, 0.6)
	if _frames == 30:
		print(
			(
				"world3d demo: draw calls %d, primitives %d, objects %d, scenery triangles %d"
				% [
					int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
					int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
					int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
					_scenery_triangles(),
				]
			)
		)


## Ground height (deterministic): a flat plateau under the fort that falls away to rolling
## ground.
func height_at(x: float, z: float) -> float:
	var d := Vector2(x - FORT_CENTER.x, (z - FORT_CENTER.z) * 1.15).length()
	var rolling := 1.6 * sin(x * 0.045 + 0.4) * cos(z * 0.05 - 0.3) + 0.8 * sin(x * 0.11 + z * 0.07)
	var t := clampf((d - 46.0) / 40.0, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(PLATEAU_Y, rolling, t)


func _terrain_color(center: Vector3, normal: Vector3) -> Color:
	var n := (
		sin(center.x * 0.21) * cos(center.z * 0.17) + 0.5 * sin(center.x * 0.05 - center.z * 0.08)
	)
	var base := OCHRE
	if center.y < 1.0 and n > 0.2:
		base = OLIVE
	elif n > 0.75:
		base = OCHRE.lerp(OLIVE, 0.45)
	var steep := clampf((1.0 - normal.y) * 6.0, 0.0, 1.0)
	return base.darkened(0.18 * steep)


func _add_terrain(lp: LowPolyMesh) -> void:
	lp.add_grid(Vector2(300, 300), Vector2i(60, 60), height_at, OCHRE, _terrain_color)


func _road_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var xz: Array[Vector2] = [
		Vector2(0, 21),
		Vector2(0, 40),
		Vector2(-8, 62),
		Vector2(-4, 84),
		Vector2(10, 104),
		Vector2(18, 140),
	]
	for p: Vector2 in xz:
		pts.append(Vector3(p.x, height_at(p.x, p.y), p.y))
	return pts


func _add_roads(lp: LowPolyMesh) -> void:
	# Short quads that follow the ground, a little above it.
	for i in road_path.size() - 1:
		var a := road_path[i]
		var b := road_path[i + 1]
		var steps := int(ceil(a.distance_to(b) / 4.0))
		for s in steps:
			var p0 := a.lerp(b, float(s) / float(steps))
			var p1 := a.lerp(b, float(s + 1) / float(steps))
			var side := (p1 - p0).cross(Vector3.UP).normalized() * 3.0
			var q: Array[Vector3] = [p0 - side, p0 + side, p1 + side, p1 - side]
			var pts: Array[Vector3] = []
			for v: Vector3 in q:
				pts.append(Vector3(v.x, height_at(v.x, v.z) + 0.08, v.z))
			lp.add_quad(pts[0], pts[1], pts[2], pts[3], DUST, Vector3.UP)


func _add_fort(lp: LowPolyMesh) -> void:
	var c := FORT_CENTER
	var hw := FORT_SIZE.x * 0.5
	var hd := FORT_SIZE.y * 0.5
	var wall_h := 7.0
	var thick := 2.5
	var wall := LowPolyMesh.new()
	# North, west and east walls; the south wall leaves an 8 m gate gap.
	wall.add_box(
		Vector3(FORT_SIZE.x, wall_h, thick),
		MARBLE,
		_at(Vector3(0, wall_h * 0.5, -hd)),
		MARBLE_SHADE
	)
	wall.add_box(
		Vector3(thick, wall_h, FORT_SIZE.y),
		MARBLE,
		_at(Vector3(-hw, wall_h * 0.5, 0)),
		MARBLE_SHADE
	)
	wall.add_box(
		Vector3(thick, wall_h, FORT_SIZE.y), MARBLE, _at(Vector3(hw, wall_h * 0.5, 0)), MARBLE_SHADE
	)
	var seg := (FORT_SIZE.x - 8.0) * 0.5
	wall.add_box(
		Vector3(seg, wall_h, thick),
		MARBLE,
		_at(Vector3(-4.0 - seg * 0.5, wall_h * 0.5, hd)),
		MARBLE_SHADE
	)
	wall.add_box(
		Vector3(seg, wall_h, thick),
		MARBLE,
		_at(Vector3(4.0 + seg * 0.5, wall_h * 0.5, hd)),
		MARBLE_SHADE
	)
	wall.darken_near_ground(0.0, 2.0, 0.3)
	lp.append(wall, _at(c))

	var tower := LowPolyMesh.new()
	tower.add_box(Vector3(8, 11, 8), MARBLE, _at(Vector3(0, 5.5, 0)), MARBLE_SHADE)
	tower.add_cone(
		6.6, 4.5, 4, TERRACOTTA, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 13.25, 0))
	)
	tower.darken_near_ground(0.0, 2.5, 0.32)
	for corner: Vector2 in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(-hw, hd), Vector2(hw, hd)]:
		lp.append(tower, _at(c + Vector3(corner.x, 0, corner.y)))
	# Gate towers and the gate.
	var gate_tower := LowPolyMesh.new()
	gate_tower.add_box(Vector3(5, 9, 5), MARBLE, _at(Vector3(0, 4.5, 0)), MARBLE_SHADE)
	gate_tower.add_cone(
		4.2,
		3.0,
		4,
		TERRACOTTA_LIGHT,
		Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 10.5, 0))
	)
	gate_tower.darken_near_ground(0.0, 2.0, 0.3)
	lp.append(gate_tower, _at(c + Vector3(-6.5, 0, hd)))
	lp.append(gate_tower, _at(c + Vector3(6.5, 0, hd)))
	var gate := LowPolyMesh.new()
	gate.add_box(Vector3(8, 6, 0.8), WOOD_DARK, _at(Vector3(0, 3, 0)))
	gate.add_box(Vector3(8.2, 0.4, 0.9), IRON, _at(Vector3(0, 2, 0)))
	gate.add_box(Vector3(8.2, 0.4, 0.9), IRON, _at(Vector3(0, 4.4, 0)))
	gate.darken_near_ground(0.0, 1.5, 0.3)
	lp.append(gate, _at(c + Vector3(0, 0, hd + 0.4)))
	# Barracks blocks inside, with terracotta roofs (wedges back to back).
	var block := LowPolyMesh.new()
	block.add_box(Vector3(14, 4, 7), MARBLE_SHADE, _at(Vector3(0, 2, 0)))
	block.add_wedge(
		Vector3(14.6, 2.0, 3.8),
		TERRACOTTA,
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 5, -1.85))
	)
	block.add_wedge(Vector3(14.6, 2.0, 3.8), TERRACOTTA, _at(Vector3(0, 5, 1.85)))
	block.darken_near_ground(0.0, 1.5, 0.3)
	lp.append(block, _at(c + Vector3(-18, 0, -16)))
	lp.append(block, _at(c + Vector3(18, 0, -16)))


func _add_machines(lp: LowPolyMesh) -> void:
	var c := FORT_CENTER + Vector3(0, 0, 4)
	# Generator: a plinth with two bearing posts and a 6 m bronze flywheel facing the camera.
	var plinth := LowPolyMesh.new()
	plinth.add_box(Vector3(9, 1.2, 6), MARBLE_SHADE, _at(Vector3(0, 0.6, 0)))
	plinth.add_box(Vector3(1, 5, 1), BRONZE_DARK, _at(Vector3(0, 3.5, -1.2)))
	plinth.add_box(Vector3(1, 5, 1), BRONZE_DARK, _at(Vector3(0, 3.5, 1.2)))
	plinth.darken_near_ground(0.0, 1.0, 0.3)
	lp.append(plinth, _at(c))
	var fly := LowPolyMesh.new()
	fly.add_ring(3.0, 0.6, 0.9, 20, BRONZE)
	for k in 8:
		fly.add_box(Vector3(0.3, 2.5, 0.3), BRONZE_DARK, _spoke(TAU * float(k) / 8.0, 1.25, 0.0))
	fly.add_cylinder(
		0.7, 0.7, 1.2, 10, BRONZE_DARK, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	)
	var fly_mi := fly.make_instance("Flywheel")
	fly_mi.position = c + Vector3(0, 5.2, 0)
	add_child(fly_mi)
	drum = fly_mi
	# Four treadwheels around it, one per slot color, axles pointing at the generator.
	var spots: Array[Vector3] = [
		Vector3(-17, 0, -3), Vector3(-9, 0, 8), Vector3(9, 0, 8), Vector3(17, 0, -3)
	]
	for i in 4:
		var color: Color = Wl.slot_look(i)["color"]
		var frame := LowPolyMesh.new()
		frame.add_box(Vector3(0.5, 3.4, 0.5), WOOD_DARK, _at(Vector3(0, 1.7, -1.4)))
		frame.add_box(Vector3(0.5, 3.4, 0.5), WOOD_DARK, _at(Vector3(0, 1.7, 1.4)))
		frame.add_box(Vector3(5.6, 0.4, 3.4), WOOD_DARK, _at(Vector3(0, 0.2, 0)))
		frame.add_cylinder(0.08, 0.08, 4.5, 4, WOOD, _at(Vector3(0, 5.6, 1.7)))
		frame.add_box(Vector3(1.6, 0.9, 0.05), color, _at(Vector3(0.85, 7.4, 1.7)))
		frame.darken_near_ground(0.0, 1.0, 0.3)
		var yaw := atan2(spots[i].x, spots[i].z)
		lp.append(frame, Transform3D(Basis(Vector3.UP, yaw), c + spots[i]))
		var wheel_lp := LowPolyMesh.new()
		wheel_lp.add_ring(2.5, 0.35, 2.2, 16, WOOD)
		for k in 8:
			wheel_lp.add_box(
				Vector3(0.18, 2.2, 0.18), WOOD_DARK, _spoke(TAU * float(k) / 8.0, 1.1, -0.9)
			)
			wheel_lp.add_box(
				Vector3(0.18, 2.2, 0.18), WOOD_DARK, _spoke(TAU * float(k) / 8.0, 1.1, 0.9)
			)
		wheel_lp.add_box(Vector3(0.3, 0.3, 3.0), IRON, _at(Vector3.ZERO))
		var wheel := Node3D.new()
		wheel.name = "Wheel%d" % i
		wheel.position = c + spots[i] + Vector3(0, 3.0, 0)
		wheel.rotation.y = yaw
		add_child(wheel)
		var mi := wheel_lp.make_instance("Mesh")
		wheel.add_child(mi)
		wheels.append(mi)


## A spoke transform: a box centred `radius` out from the Z axis at `angle`, at depth z.
static func _spoke(angle: float, radius: float, z: float) -> Transform3D:
	var b := Basis(Vector3.BACK, angle)
	return Transform3D(b, b * Vector3(0, radius, 0) + Vector3(0, 0, z))


func _add_scatter() -> void:
	var fort_rect := Rect2(FORT_CENTER.x - 42, FORT_CENTER.z - 34, 84, 70)
	var excludes: Array = [fort_rect]
	for p: Vector3 in road_path:
		excludes.append(Vector3(p.x, p.z, 8.0))
	for i in road_path.size() - 1:
		var a := road_path[i]
		var b := road_path[i + 1]
		for s in 6:
			var m := a.lerp(b, (s + 0.5) / 6.0)
			excludes.append(Vector3(m.x, m.z, 6.0))
	var cypress := LowPolyMesh.new()
	cypress.add_cylinder(0.25, 0.2, 1.2, 5, WOOD_DARK, _at(Vector3(0, 0.6, 0)))
	cypress.add_cylinder(1.1, 0.0, 7.0, 6, OLIVE_DARK, _at(Vector3(0, 4.6, 0)))
	cypress.darken_near_ground(0.0, 1.6, 0.4)
	var olive := LowPolyMesh.new()
	olive.add_cylinder(0.3, 0.22, 1.6, 5, WOOD, _at(Vector3(0, 0.8, 0)))
	olive.add_sphere(
		2.0, 3, 6, OLIVE, Transform3D(Basis().scaled(Vector3(1.2, 0.8, 1.2)), Vector3(0, 2.6, 0))
	)
	olive.darken_near_ground(0.0, 1.8, 0.4)
	var rock := LowPolyMesh.new()
	rock.add_sphere(
		1.0, 2, 5, ROCK, Transform3D(Basis().scaled(Vector3(1.3, 0.6, 1.0)), Vector3(0, 0.2, 0))
	)
	rock.darken_near_ground(0.0, 0.5, 0.35)
	var kinds: Array[Dictionary] = [
		{
			"mesh": cypress,
			"count": 300,
			"seed": 1,
			"scale": Vector2(0.7, 1.3),
			"colors": PackedColorArray([Color.WHITE, Color(0.9, 0.95, 0.85)])
		},
		{
			"mesh": olive,
			"count": 220,
			"seed": 2,
			"scale": Vector2(0.7, 1.2),
			"colors": PackedColorArray([Color.WHITE, Color(1.05, 1.0, 0.9)])
		},
		{
			"mesh": rock,
			"count": 140,
			"seed": 3,
			"scale": Vector2(0.5, 1.6),
			"colors": PackedColorArray([Color.WHITE, Color(0.85, 0.85, 0.85)])
		},
	]
	for k: Dictionary in kinds:
		var mm := MultiMeshScatter.new()
		mm.name = "Scatter%d" % int(k["seed"])
		var lp: LowPolyMesh = k["mesh"]
		mm.setup(lp.build(), int(k["count"]), true, false)
		(
			mm
			. scatter(
				{
					"seed": SeededRng.derive(SEED, "scatter%d" % int(k["seed"])),
					"count": int(k["count"]),
					"area": Rect2(-145, -145, 290, 290),
					"exclude": excludes,
					"min_spacing": 3.0,
					"scale": k["scale"],
					"height_jitter": 0.15,
					"tilt_deg": 4.0,
					"colors": k["colors"],
					"color_jitter": 0.06,
					"height": height_at,
					"y_offset": -0.1,
				}
			)
		)
		add_child(mm)
		trees.append(mm)


func _add_marchers() -> void:
	var figure := LowPolyMesh.new()
	figure.add_box(Vector3(0.5, 0.8, 0.35), CLOTH, _at(Vector3(0, 0.75, 0)))
	figure.add_box(Vector3(0.2, 0.35, 0.2), Color("#857a6b"), _at(Vector3(-0.13, 0.18, 0)))
	figure.add_box(Vector3(0.2, 0.35, 0.2), Color("#857a6b"), _at(Vector3(0.13, 0.18, 0)))
	figure.add_sphere(0.22, 2, 5, Color("#c9a27e"), _at(Vector3(0, 1.35, 0)))
	figure.add_box(Vector3(0.08, 1.9, 0.08), WOOD, _at(Vector3(0.32, 1.0, 0)))
	figure.add_cylinder(
		0.32,
		0.32,
		0.08,
		8,
		Color("#7a6650"),
		Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.3, 0.8, -0.05))
	)
	marchers = MultiMeshScatter.new()
	marchers.name = "Marchers"
	marchers.setup(figure.build(), 40, false, true)
	_walk_material = MultiMeshScatter.walk_bob_material(0.12, 2.2, 0.3)
	marchers.material_override = _walk_material
	add_child(marchers)
	_update_marchers()


func _update_marchers() -> void:
	# Walk the road from its far end toward the gate, in a column of pairs.
	var reversed := road_path.duplicate()
	reversed.reverse()
	var spots := MultiMeshScatter.along_path(reversed, 2.4, _t * 1.4)
	var xforms: Array[Transform3D] = []
	var customs := PackedColorArray()
	var shown := 0
	for i in spots.size():
		# Only the stretch in view, between the gate and the bottom of the frame.
		if spots[i].origin.z > 88.0 or spots[i].origin.z < 26.0 or shown >= 20:
			continue
		shown += 1
		for side: float in [-0.7, 0.7]:
			var t := spots[i]
			var p := t.origin + t.basis.x.normalized() * side
			p.y = height_at(p.x, p.z)
			xforms.append(Transform3D(t.basis, p))
			customs.append(Color(fposmod(float(i) * 0.37 + side, 1.0), 0, 0, 0))
	marchers.set_instances(xforms, PackedColorArray(), customs)


func _add_caption() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = tr("WORLD_DEMO_3D_CAPTION")
	label.position = Vector2(32, 24)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color("#fff6e0"))
	label.add_theme_color_override("font_outline_color", Color("#2b2622"))
	label.add_theme_constant_override("outline_size", 8)
	layer.add_child(label)


func _scenery_triangles() -> int:
	var n := 0
	var s := get_node_or_null("Scenery") as MeshInstance3D
	if s != null and s.mesh != null:
		for i in s.mesh.get_surface_count():
			n += floori((s.mesh as ArrayMesh).surface_get_array_len(i) / 3.0)
	return n


static func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis(), p)
