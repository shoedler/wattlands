class_name SiegeTowersView
extends Node3D
## The towers on the eight pads (brief 3 "Towers"): a Ballista (big bow frame), Scorpion (small
## triple frame) or Caltrop thrower (sling arm) per built pad, with 1-3 bronze bands for the
## upgrade level; an empty pad is just the marble plinth the fort mesh already draws. A new
## tower scales up over one second. Each tower turns toward what it shot at last, else toward
## the nearest enemy in reach, else outward from the fort. One MeshInstance3D per built pad
## (at most eight), sharing meshes per type and level.

const SCALE_UP_S := 1.0
const TURN_RATE := 7.0
const IDLE_RETURN_S := 3.0
## Towers are drawn larger than life so the silhouettes read from the miniature camera.
const TOWER_SCALE := 1.5

var fort: SiegeFortBuilder = null
var map: SiegeMap = null
## Pad index (pad - 1) -> the tower's node (null while empty).
var nodes: Array[MeshInstance3D] = []
var _meshes: Dictionary = {}
var _type: Array[int] = []
var _level: Array[int] = []
var _age: Array[float] = []
var _yaw: Array[float] = []
var _aim_yaw: Array[float] = []
var _since_aim: Array[float] = []
var _initialized: bool = false
var _last_pos: Dictionary = {}


func setup(p_fort: SiegeFortBuilder) -> void:
	fort = p_fort
	map = p_fort.map
	name = "Towers"
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		nodes.append(null)
		_type.append(SiegeIds.TOWER_NONE)
		_level.append(0)
		_age.append(SCALE_UP_S)
		_yaw.append(_outward_yaw(n))
		_aim_yaw.append(_outward_yaw(n))
		_since_aim.append(IDLE_RETURN_S)


## The yaw (about Y) that points a tower's -Z along (dx, dz).
static func yaw_toward(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)


func _outward_yaw(pad: int) -> float:
	var out := map.pad_pos(pad) - Vector2.ZERO
	if out.length() < 0.1:
		out = Vector2(0, 1)
	return yaw_toward(out.x, out.y)


## The muzzle of pad `pad`'s tower in world space (where bolts start).
func muzzle(pad: int) -> Vector3:
	var p := map.pad_pos(pad)
	return Vector3(p.x, fort.pad_top_y(pad) + 2.4 * TOWER_SCALE, p.y)


## The scale a tower of age `age_s` has: 0 at birth, 1 after one second (ease-out with a
## little overshoot).
static func scale_for(age_s: float) -> float:
	var u := clampf(age_s / SCALE_UP_S, 0.0, 1.0)
	if u >= 1.0:
		return 1.0
	var c := 1.70158
	var v := u - 1.0
	return maxf(1.0 + (c + 1.0) * v * v * v + c * v * v, 0.01)


func _mesh_for(type: int, level: int) -> ArrayMesh:
	var key := type * 10 + level
	if not _meshes.has(key):
		_meshes[key] = SiegeTowerMeshes.build(type, level).build()
	return _meshes[key]


## Updates every pad from `state`. `drawn` maps enemy id -> its drawn ground position (the
## enemy view's), used for aiming.
func update(state: SiegeState, dt: float, drawn: Dictionary) -> void:
	for id: int in drawn:
		_last_pos[id] = drawn[id]
	if _last_pos.size() > 600:
		_last_pos.clear()
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		var i := n - 1
		var tw := state.pad(n)
		if not tw.built():
			if nodes[i] != null:
				nodes[i].queue_free()
				nodes[i] = null
			_type[i] = SiegeIds.TOWER_NONE
			_level[i] = 0
			continue
		if nodes[i] == null:
			nodes[i] = MeshInstance3D.new()
			nodes[i].name = "Tower%d" % n
			nodes[i].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var p := map.pad_pos(n)
			nodes[i].position = Vector3(p.x, fort.pad_top_y(n), p.y)
			add_child(nodes[i])
			_age[i] = SCALE_UP_S if not _initialized else 0.0
			_type[i] = -1
		if _type[i] != tw.type or _level[i] != tw.level:
			_type[i] = tw.type
			_level[i] = tw.level
			nodes[i].mesh = _mesh_for(tw.type, tw.level)
		_age[i] += dt
		var age := minf(_age[i], tw.age_s)
		var s := scale_for(age)
		nodes[i].scale = Vector3.ONE * (s * TOWER_SCALE)
		_aim(state, n, dt, drawn)
		nodes[i].rotation.y = _yaw[i]
	_initialized = true


func _aim(state: SiegeState, n: int, dt: float, drawn: Dictionary) -> void:
	var i := n - 1
	var from := map.pad_pos(n)
	var found := false
	for shot in state.shots:
		if shot.pad != n or shot.targets.is_empty():
			continue
		var id: int = shot.targets[0]
		var at: Variant = drawn.get(id, _last_pos.get(id))
		if at is Vector2:
			var d: Vector2 = (at as Vector2) - from
			_aim_yaw[i] = yaw_toward(d.x, d.y)
			_since_aim[i] = 0.0
			found = true
			break
	if not found:
		_since_aim[i] += dt
		var reach := state.tower_range_m(n)
		var best := INF
		var best_d := Vector2.ZERO
		for e in state.enemies:
			if e.st == SiegeIds.EN_RETREAT:
				continue
			var at: Variant = drawn.get(e.id)
			var pos: Vector2 = at if at is Vector2 else e.pos
			var d := pos - from
			var dist := d.length()
			if dist <= reach and dist < best:
				best = dist
				best_d = d
		if best < INF:
			_aim_yaw[i] = yaw_toward(best_d.x, best_d.y)
			_since_aim[i] = 0.0
		elif _since_aim[i] >= IDLE_RETURN_S:
			_aim_yaw[i] = _outward_yaw(n)
	_yaw[i] = lerp_angle(_yaw[i], _aim_yaw[i], clampf(TURN_RATE * dt, 0.0, 1.0))


## How many towers are drawn.
func shown() -> int:
	var c := 0
	for nd in nodes:
		if nd != null:
			c += 1
	return c
