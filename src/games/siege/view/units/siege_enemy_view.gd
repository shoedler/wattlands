class_name SiegeEnemyView
extends Node3D
## The enemy crowds (brief 3 "Enemies"): one MultiMesh per type (Raiders, Shield wall,
## Horsemen, ram), each with the vertex-shader walk bob, and two MultiMeshes of hit-point bars
## that only damaged Shield walls, Horsemen and rams get. There is no node per enemy: every
## frame rewrites the instance buffers from the state. Positions are the state's own on the host
## and in SOLO; on a client they come from the module's SiegeSnapHistory (one interpolation path).

const CAPACITY := 170
const BAR_CAPACITY := 170
const BAR_SIZE := Vector2(2.4, 0.28)
## Enemies are drawn a little larger than life so the crowds read from the miniature camera.
const UNIT_SCALE := 1.4
## type -> [bob height m, steps per second].
const BOB := {1: [0.1, 3.0], 2: [0.07, 2.0], 3: [0.12, 3.6], 4: [0.05, 0.8]}

var map: SiegeMap = null
var terrain: SiegeTerrain = null
## Enemy type code -> MultiMeshScatter (1..4).
var crowds: Dictionary = {}
var bars_back: MultiMeshScatter = null
var bars_fill: MultiMeshScatter = null
var _mats: Dictionary = {}
var _time: float = 0.0
## The ground position the last update drew each enemy at (id -> Vector2), for bolts.
var drawn: Dictionary = {}


func setup(p_map: SiegeMap, p_terrain: SiegeTerrain) -> void:
	map = p_map
	terrain = p_terrain
	name = "Enemies"
	var meshes := {
		SiegeIds.ENEMY_RAIDERS: SiegeUnitMeshes.raider(),
		SiegeIds.ENEMY_SHIELD_WALL: SiegeUnitMeshes.shield_wall(),
		SiegeIds.ENEMY_HORSEMEN: SiegeUnitMeshes.horseman(),
		SiegeIds.ENEMY_RAM: SiegeUnitMeshes.ram(),
	}
	for type: int in meshes:
		var mm := MultiMeshScatter.new()
		mm.name = SiegeIds.ENEMY_NAMES[type].capitalize().replace(" ", "")
		mm.setup((meshes[type] as LowPolyMesh).build(), CAPACITY, true, true)
		var bob: Array = BOB[type]
		var mat := MultiMeshScatter.walk_bob_material(float(bob[0]), 1.0, 0.45)
		MultiMeshScatter.set_walk_time(mat, 0.0)
		mm.material_override = mat
		_mats[type] = mat
		add_child(mm)
		crowds[type] = mm
	bars_back = _bar_layer("BarsBack")
	bars_fill = _bar_layer("BarsFill")


func _bar_layer(layer_name: String) -> MultiMeshScatter:
	var lp := LowPolyMesh.new()
	lp.use_surface(&"bar", LowPolyMesh.unshaded_material())
	lp.add_box(Vector3(1.0, 1.0, 0.05), Color.WHITE)
	var mm := MultiMeshScatter.new()
	mm.name = layer_name
	mm.setup(lp.build(), BAR_CAPACITY, true, false)
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm)
	return mm


## Road progress (m) of `e` as drawn: the history's (null: the state's own).
static func drawn_prog(e: SiegeEnemyState, history: SiegeSnapHistory) -> float:
	return e.prog_m if history == null else history.prog_of(e.id, e.prog_m)


## Ground position (x, z) of `e` as drawn: the history's (null: the state's own).
static func ground_pos(e: SiegeEnemyState, p_map: SiegeMap, history: SiegeSnapHistory) -> Vector2:
	var own := p_map.point_at(e.road, e.prog_m, e.lat_m)
	return own if history == null else history.pos_of(e.id, own)


## Redraws every crowd from `state`; `history` (a client's snapshot history, its render clock
## advanced by the caller) or null for the state's own positions.
func update(state: SiegeState, dt: float, history: SiegeSnapHistory = null) -> void:
	_time += dt
	var xf: Dictionary = {}
	var cu: Dictionary = {}
	var co: Dictionary = {}
	for type: int in crowds:
		xf[type] = [] as Array[Transform3D]
		cu[type] = PackedColorArray()
		co[type] = PackedColorArray()
	var bar_xf: Array[Transform3D] = []
	var bar_back_xf: Array[Transform3D] = []
	var bar_col := PackedColorArray()
	drawn.clear()
	for e in state.enemies:
		if not xf.has(e.type):
			continue
		var prog := drawn_prog(e, history)
		var p := ground_pos(e, map, history)
		drawn[e.id] = p
		var dir := map.dir_at(e.road, minf(prog, map.road_length(e.road) - 0.05))
		if e.st == SiegeIds.EN_RETREAT:
			dir = -dir
		var y := terrain.height_at(p.x, p.y)
		var pos := Vector3(p.x, y, p.y)
		if e.st == SiegeIds.EN_BATTER:
			# The ram heaves its log into the gate.
			pos += Vector3(dir.x, 0.0, dir.y) * (0.35 * sin(_time * 3.2))
		var basis := (
			Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP)
			* Basis().scaled(Vector3.ONE * UNIT_SCALE)
		)
		(xf[e.type] as Array[Transform3D]).append(Transform3D(basis, pos))
		var tint := Color(0.72, 0.72, 0.72) if e.st == SiegeIds.EN_RETREAT else Color.WHITE
		(cu[e.type] as PackedColorArray).append(tint)
		(co[e.type] as PackedColorArray).append(
			Color(fposmod(float(e.id) * 0.618034, 1.0), 0, 0, 0)
		)
		if (
			(
				e.type == SiegeIds.ENEMY_SHIELD_WALL
				or e.type == SiegeIds.ENEMY_HORSEMEN
				or e.type == SiegeIds.ENEMY_RAM
			)
			and e.max_hp > 0.0
			and e.hp < e.max_hp
			and bar_xf.size() < BAR_CAPACITY
		):
			var frac := clampf(e.hp / e.max_hp, 0.0, 1.0)
			var top := Vector3(
				pos.x, pos.y + float(SiegeUnitMeshes.BAR_HEIGHT_M[e.type]) * UNIT_SCALE, pos.z
			)
			var w := BAR_SIZE.x
			bar_back_xf.append(Transform3D(Basis().scaled(Vector3(w, BAR_SIZE.y, 1.0)), top))
			var fw := maxf(w * frac, 0.05)
			bar_xf.append(
				Transform3D(
					Basis().scaled(Vector3(fw, BAR_SIZE.y * 0.6, 1.0)),
					top + Vector3(-(w - fw) * 0.5, 0.0, 0.06)
				)
			)
			bar_col.append(SiegePalette.TERRACOTTA_LIGHT if frac < 0.34 else Color("#E8E2D4"))
	for type: int in crowds:
		var mm: MultiMeshScatter = crowds[type]
		mm.set_instances(xf[type], cu[type], co[type])
		var bob: Array = BOB[type]
		MultiMeshScatter.set_walk_time(_mats[type], _time * float(bob[1]))
	var back_cols := PackedColorArray()
	back_cols.resize(bar_back_xf.size())
	back_cols.fill(SiegePalette.shade(SiegePalette.IRON, 0.4))
	bars_back.set_instances(bar_back_xf, back_cols)
	bars_fill.set_instances(bar_xf, bar_col)


## How many instances of enemy type `type` are drawn.
func shown(type: int) -> int:
	return (crowds[type] as MultiMeshScatter).visible_count() if crowds.has(type) else 0


func bars_shown() -> int:
	return bars_fill.visible_count()
