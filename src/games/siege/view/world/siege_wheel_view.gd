class_name SiegeWheelView
extends Node3D
## One rider's treadwheel (brief 3 "Wheels"): a 5 m wooden wheel with a pennant in the slot
## color and pattern (a toothed edge for bots), one to three block workers walking at the
## bottom, and a glowing shaft while the rider routes to the generator. The wheel's rim speed
## follows the rider's P_eff (SiegeWheelMath), the workers' step rate their cadence. An empty
## wheel (no rider in that slot) stands idle. The node sits at the wheel's ground position,
## yawed so its local +Z points at the generator; it only reads SiegeRiderState.

const WHEEL_SEGMENTS := 16
const SLATS := 12
const MAST_TOP_Y := 7.7
## 1.5 times the first cut: a 3.2 x 1.9 m flag was too small to tell slots apart from 3 m away.
const FLAG_SIZE := Vector2(4.8, 2.85)
const FLAG_BASE_W := 3.2
const WORKER_SCALE := 1.3

var slot: int = 0
var fort: SiegeFortBuilder = null
var wheel: MeshInstance3D = null
var workers: MultiMeshScatter = null
var pennant: MeshInstance3D = null
var glow: MeshInstance3D = null
## The wheel's angle (rad) and the worker step phase (steps taken) now.
var angle: float = 0.0
var step_phase: float = 0.0
var rim_speed: float = 0.0
var step_rate: float = 0.0
var stride: float = 0.0
var worker_count: int = 1
var occupied: bool = false

var _walk_mat: ShaderMaterial = null
var _glow_mat: StandardMaterial3D = null
var _time: float = 0.0
var _shown_rider: bool = false
var _is_bot: bool = false
var _look: Dictionary = {}


## Builds the wheel for `p_slot`; `look` is Wl.slot_look(slot), `is_bot` picks the toothed
## pennant.
func setup(p_slot: int, p_fort: SiegeFortBuilder, look: Dictionary, p_is_bot: bool) -> void:
	slot = p_slot
	fort = p_fort
	_look = look
	_is_bot = p_is_bot
	name = "Wheel%d" % slot
	transform = fort.wheel_transform(slot)
	wheel = build_wheel_mesh().make_instance("Rim")
	wheel.position = Vector3(0.0, SiegeFortBuilder.WHEEL_Y, 0.0)
	add_child(wheel)
	_build_workers()
	_build_glow()
	_build_pennant()
	apply_look(look, p_is_bot)
	_set_occupied(false)


## The wheel's wooden body around local Z: two rims, tread slats, spokes and a bronze hub.
static func build_wheel_mesh() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	var r := SiegeWheelMath.WHEEL_RADIUS_M
	var half := SiegeFortBuilder.WHEEL_DEPTH_M * 0.5
	for zs: float in [-1.0, 1.0]:
		m.add_ring(
			r,
			0.3,
			0.3,
			WHEEL_SEGMENTS,
			SiegePalette.WOOD,
			Transform3D(Basis(), Vector3(0.0, 0.0, zs * half))
		)
		for k in 6:
			var a := TAU * float(k) / 6.0
			var b := Basis(Vector3.BACK, a)
			m.add_box(
				Vector3(0.2, r - 0.2, 0.2),
				SiegePalette.WOOD_DARK,
				Transform3D(
					b, b * Vector3(0.0, (r - 0.2) * 0.5, 0.0) + Vector3(0.0, 0.0, zs * half)
				)
			)
	for k in SLATS:
		var a := TAU * float(k) / float(SLATS)
		var b := Basis(Vector3.BACK, a)
		var col := SiegePalette.WOOD if k % 2 == 0 else SiegePalette.WOOD_DARK
		m.add_box(
			Vector3(0.62, 0.16, SiegeFortBuilder.WHEEL_DEPTH_M),
			col,
			Transform3D(b, b * Vector3(0.0, -(r - 0.1), 0.0))
		)
	m.add_cylinder(
		0.5,
		0.5,
		SiegeFortBuilder.WHEEL_DEPTH_M + 0.6,
		8,
		SiegePalette.BRONZE_DARK,
		Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	)
	return m


## The pennant (a flag on the mast) for a slot look: a block of the slot color with the
## pattern in off-white marks; bots get a toothed trailing edge.
static func build_pennant_mesh(look: Dictionary, is_bot: bool) -> LowPolyMesh:
	var m := LowPolyMesh.new()
	var col: Color = look.get("color", Color.WHITE)
	var mark := Color("#F4F0E4") if col.get_luminance() < 0.6 else Color("#2B2622")
	var w := FLAG_SIZE.x
	var h := FLAG_SIZE.y
	var pattern := str(look.get("pattern", "solid"))
	# The marks were laid out for FLAG_BASE_W wide; k scales them with the flag.
	var k := w / FLAG_BASE_W
	# Both faces, as one thin slab.
	m.add_box(Vector3(w, h, 0.06), col, Transform3D(Basis(), Vector3(w * 0.5, 0.0, 0.0)))
	if is_bot:
		var teeth := 4
		for i in teeth:
			var y := -h * 0.5 + h * (float(i) + 0.5) / float(teeth)
			var p0 := Vector3(w, y - h / float(teeth) * 0.5, 0.0)
			var p1 := Vector3(w + 0.38 * k, y, 0.0)
			var p2 := Vector3(w, y + h / float(teeth) * 0.5, 0.0)
			m.add_triangle(p0, p1, p2, col, Vector3(0, 0, 1))
			m.add_triangle(p0, p1, p2, col, Vector3(0, 0, -1))
	var z := 0.045
	match pattern:
		"dashed":
			for i in 3:
				for zs: float in [-1.0, 1.0]:
					m.add_box(
						Vector3(0.7 * k, 0.26 * k, 0.04),
						mark,
						Transform3D(Basis(), Vector3((0.5 + float(i) * 0.95) * k, 0.0, zs * z))
					)
		"dotted":
			for i in 4:
				for zs: float in [-1.0, 1.0]:
					m.add_box(
						Vector3(0.3 * k, 0.3 * k, 0.04),
						mark,
						Transform3D(Basis(), Vector3((0.45 + float(i) * 0.75) * k, 0.0, zs * z))
					)
		"double":
			for yy: float in [-0.55 * k, 0.55 * k]:
				for zs: float in [-1.0, 1.0]:
					m.add_box(
						Vector3(w - 0.3 * k, 0.2 * k, 0.04),
						mark,
						Transform3D(Basis(), Vector3(w * 0.5, yy, zs * z))
					)
	# The mast stub: runs past the flag at both ends, so the flag hangs from a visible pole.
	m.add_box(
		Vector3(0.16, h + 1.1, 0.16),
		SiegePalette.WOOD_DARK,
		Transform3D(Basis(), Vector3(0.0, 0.2, 0.0))
	)
	return m


func apply_look(look: Dictionary, p_is_bot: bool) -> void:
	_look = look
	_is_bot = p_is_bot
	if pennant != null:
		pennant.mesh = build_pennant_mesh(look, p_is_bot).build()
	if _glow_mat != null:
		_glow_mat.albedo_color = look.get("color", Color.WHITE)


func _build_workers() -> void:
	workers = MultiMeshScatter.new()
	workers.name = "Workers"
	workers.setup(SiegeUnitMeshes.worker().build(), SiegeWheelMath.MAX_WORKERS, true, true)
	_walk_mat = MultiMeshScatter.walk_bob_material(0.1, 1.0, 0.3)
	MultiMeshScatter.set_walk_time(_walk_mat, 0.0)
	workers.material_override = _walk_mat
	add_child(workers)


func _build_glow() -> void:
	glow = MeshInstance3D.new()
	glow.name = "ShaftGlow"
	var dist := fort.map.wheel_pos(slot).distance_to(fort.map.generator_pos)
	var z0 := SiegeFortBuilder.WHEEL_DEPTH_M * 0.5 + 0.35
	var z1 := dist - SiegeFortBuilder.GEN_RADIUS_M - 0.35
	_glow_mat = LowPolyMesh.unshaded_material()
	_glow_mat.albedo_color = Color.WHITE
	var lp := LowPolyMesh.new()
	lp.use_surface(&"glow", _glow_mat)
	lp.add_cylinder(
		0.42,
		0.42,
		z1 - z0,
		8,
		Color.WHITE,
		Transform3D(
			Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, SiegeFortBuilder.WHEEL_Y, (z0 + z1) * 0.5)
		)
	)
	glow.mesh = lp.build()
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	glow.visible = false


func _build_pennant() -> void:
	pennant = MeshInstance3D.new()
	pennant.name = "Pennant"
	pennant.position = Vector3(0.0, MAST_TOP_Y - 1.1, SiegeFortBuilder.MAST_Z)
	pennant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pennant)


func _set_occupied(on: bool) -> void:
	occupied = on
	pennant.visible = on
	workers.visible = on
	if not on:
		glow.visible = false


## Reads the rider (null: an empty wheel) and advances the wheel, workers and glow by `dt`.
## `victory` (the cool-down) keeps the workers striding at a steady pace.
func update(rider: SiegeRiderState, dt: float, victory: bool = false) -> void:
	_time += dt
	var has_rider := rider != null
	if has_rider != _shown_rider:
		_shown_rider = has_rider
		_set_occupied(has_rider)
	if not has_rider:
		rim_speed = 0.0
		step_rate = 0.0
		return
	var stopped := rider.afk or not rider.connected
	var p := 0.0 if stopped else rider.p_eff_w
	var cadence := 0.0 if stopped else rider.cadence_rpm
	if victory and not stopped:
		p = maxf(p, 150.0)
		cadence = maxf(cadence, 70.0)
	rim_speed = SiegeWheelMath.rim_speed(p)
	step_rate = SiegeWheelMath.step_rate_hz(cadence)
	stride = SiegeWheelMath.stride_m(rim_speed, step_rate)
	# The bottom of the wheel runs toward -x (workers walk toward +x).
	angle -= rim_speed / SiegeWheelMath.WHEEL_RADIUS_M * dt
	wheel.rotation.z = angle
	step_phase += step_rate * dt
	MultiMeshScatter.set_walk_time(_walk_mat, step_phase)
	worker_count = SiegeWheelMath.worker_count(p, worker_count)
	_update_workers(rider)
	_update_glow(rider)
	pennant.rotation.y = -rotation.y + sin(_time * 2.6 + float(slot)) * 0.16


func _update_workers(rider: SiegeRiderState) -> void:
	var xforms: Array[Transform3D] = []
	var customs := PackedColorArray()
	var y := SiegeFortBuilder.WHEEL_Y - SiegeWheelMath.WHEEL_RADIUS_M + 0.28
	var offsets := SiegeWheelMath.worker_offsets(worker_count)
	for i in offsets.size():
		# Each worker paces forward by one stride per step and resets (the tread carries it back).
		var pace := (fposmod(step_phase + float(i) * 0.37, 1.0) - 0.5) * stride
		var z := -0.55 + 0.55 * float(i % 3)
		var lean := 0.0
		if rider.rescue:
			lean = sin(_time * 9.0 + float(i)) * 0.35
		var b := (
			Basis(Vector3.UP, -PI * 0.5)
			* Basis(Vector3.RIGHT, lean)
			* Basis().scaled(Vector3.ONE * WORKER_SCALE)
		)
		xforms.append(Transform3D(b, Vector3(offsets[i] + pace, y, z)))
		customs.append(Color(float(i) * 0.31, 0.0, 0.0, 0.0))
	workers.set_instances(xforms, PackedColorArray(), customs)


func _update_glow(rider: SiegeRiderState) -> void:
	var routed := rider.target == SiegeIds.TARGET_GEN and not rider.afk and rider.connected
	glow.visible = routed
	if routed:
		var lit := 1.0 - clampf(rider.reconnect_s / 2.0, 0.0, 1.0)
		var base: Color = _look.get("color", Color.WHITE)
		_glow_mat.albedo_color = SiegePalette.BRONZE_DARK.lerp(base, lit)


## How many workers are on the tread right now (the multimesh's visible count).
func workers_shown() -> int:
	return workers.visible_count() if workers.visible else 0
