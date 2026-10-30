class_name SiegeV2Demo
extends Control
## A standalone look at the v2 view primitives (no SiegeState): the baked world, the rotae
## turning in their riders' hues with walkers, two powered routes, every station animating and
## slewing, a column of attackers walking the road (SiegePath.point_at), shots replayed from
## shot events, and the tilt-shift pass. Time advances a fixed 1/60 s per frame from START_S, so
## a capture after n frames is always the same picture.
##   tools/screenshot --scene=res://src/games/siege/view/v2/siege_v2_demo.tscn --frames=<n>
## User args: --siege-demo-t=<s> (start time), --siege-demo-sharp (tilt-shift off),
## --siege-demo-stress (150 attackers and a shot every 0.15 s; prints the cost of an update),
## --siege-demo-mock-pose (the machines posed as in the approved mock, no attackers or shots, to
## compare a capture with build/siege_mock_r2/frame_sharp_2x.png).

const START_S := 6.0
const FRAME_DT := 1.0 / 60.0
const MAP_PATH := "res://content/siege/maps/rotae.json"
const SHOT_EVERY_S := 0.9
## The demo's column: [type, prog at t 0 (m), speed (m/s), ranks, files].
const COLUMN := [
	[5, 150.0, 0.5, 1, 1],
	[4, 262.0, 0.8, 1, 1],
	[1, 300.0, 1.8, 3, 4],
	[2, 278.0, 1.2, 2, 3],
	[1, 236.0, 1.8, 3, 4],
	[3, 170.0, 6.0, 1, 2],
	[1, 118.0, 1.8, 3, 4],
	[2, 92.0, 1.2, 2, 3],
	[1, 52.0, 1.8, 3, 4],
	[3, 30.0, 6.0, 1, 2],
]
const SPACING_M := 1.2

var bank: SiegeBakeBank = null
var path: SiegePath = null
var pixel_viewport: PixelViewport = null
var view: Node2D = null
var world: SiegeV2WorldLayer = null
var machines: SiegeV2Machines = null
var crowd: SiegeV2Crowd = null
var shots: SiegeV2Shots = null
var tilt: SiegeV2TiltShift = null
var time_s: float = START_S

var _types := PackedInt32Array()
var _prog0 := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _lat := PackedFloat32Array()
var _fired: int = -1
var _last_fire := PackedFloat32Array([-9, -9, -9, -9, -9])
var _stress: bool = false
var _mock_pose: bool = false
var _shot_every: float = SHOT_EVERY_S
var _usec: int = 0
var _frames: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var sharp := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--siege-demo-t="):
			time_s = float(a.get_slice("=", 1))
		elif a == "--siege-demo-sharp":
			sharp = true
		elif a == "--siege-demo-mock-pose":
			_mock_pose = true
		elif a == "--siege-demo-stress":
			_stress = true
			_shot_every = 0.15
	bank = SiegeBakeBank.shared()
	path = SiegePath.load_file(MAP_PATH)
	pixel_viewport = PixelViewport.new()
	pixel_viewport.pixel_base = SiegeBakeBank.ART_SIZE
	pixel_viewport.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pixel_viewport)
	build_view()
	tilt.enabled = not sharp
	pixel_viewport.set_game_view(view)
	_make_column()
	_fired = floori((time_s - 8.0) / _shot_every)
	update_at(time_s)


## The view: world, machines, crowd, shots, then the screen pass.
func build_view() -> void:
	view = Node2D.new()
	view.name = "SiegeV2View"
	world = SiegeV2WorldLayer.new(bank)
	machines = SiegeV2Machines.new(bank)
	crowd = SiegeV2Crowd.new(bank)
	shots = SiegeV2Shots.new(bank)
	shots.path = path
	shots.content = SiegeContent.from_dicts(SiegeContent.read_files(), "short")
	tilt = SiegeV2TiltShift.new(SiegeBakeBank.ART_SIZE, bank.manifest.get("focus", {}))
	for n: Node in [world, machines, crowd, shots, tilt]:
		view.add_child(n)


func _process(_delta: float) -> void:
	time_s += FRAME_DT
	var t0 := Time.get_ticks_usec()
	update_at(time_s)
	_usec += Time.get_ticks_usec() - t0
	_frames += 1
	if _stress and _frames % 60 == 0:
		print(
			(
				"siege_v2_demo: %d enemies, %d projectiles, update %.2f ms, %d fps, %d draw calls"
				% [
					crowd.drawn,
					shots.in_flight(),
					_usec / 60000.0,
					Engine.get_frames_per_second(),
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				]
			)
		)
		_usec = 0


func update_at(t: float) -> void:
	if _mock_pose:
		pose_as_mock()
		return
	_update_machines(t)
	_update_crowd(t)
	_fire_until(t)
	shots.set_time(t)


## The approved mock's moment (scene.mjs and life.mjs defaults): every slot routed, the
## stations at their mock yaws, a full curtain and coat, scorpions on pads 2 and 4.
func pose_as_mock() -> void:
	var angles := [0.3, 1.1, 2.0, 0.7]
	var walkers := [2, 3, 2, 1]
	var routes := [1, 2, 3, 4]
	for s in 4:
		machines.set_wheel(s, rad_to_deg(angles[s]), true, walkers[s], 0.0)
		machines.set_route(s, routes[s])
	machines.set_station(1, rad_to_deg(atan2(40.0, -18.0)), 1.0)
	machines.set_station(2, 135.0, (105.0 - 80.0) / 85.0)
	machines.set_station(3, rad_to_deg(atan2(26.0, -34.0)), 1.0)
	machines.racks = 7
	machines.mine_phase = 0.0
	machines.pump_phase = 0.0
	machines.gate_stage = 0
	machines.curtain_stage = 3
	machines.coat_stage = 3
	machines.set_pad(1, 0, 0.0)
	machines.set_pad(2, 1, 110.0)
	machines.set_pad(3, 0, 0.0)
	machines.set_pad(4, 1, 160.0)
	machines.rebuild()
	crowd.set_enemies(
		PackedInt32Array(),
		PackedVector3Array(),
		PackedFloat32Array(),
		PackedFloat32Array(),
		PackedFloat32Array()
	)
	shots.shots.clear()
	shots.set_time(0.0)


func _make_column() -> void:
	var copies := 3 if _stress else 1
	for c in copies:
		_add_column(c * 37.0)


func _add_column(shift: float) -> void:
	for g: Array in COLUMN:
		if _types.size() >= SiegeV2Crowd.MAX_ENEMIES:
			return
		for i in int(g[3]):
			for j in int(g[4]):
				_types.append(int(g[0]))
				var deep := SPACING_M * (5.0 if int(g[0]) == 3 else 1.0)
				_prog0.append(float(g[1]) - i * deep + shift)
				_speed.append(float(g[2]))
				_lat.append((j - (int(g[4]) - 1) * 0.5) * (2.4 if int(g[0]) == 3 else SPACING_M))


func enemy_prog(i: int, t: float) -> float:
	return fposmod(_prog0[i] + _speed[i] * t, path.moat_edge_m - 4.0)


func _update_crowd(t: float) -> void:
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var walk := PackedFloat32Array()
	var hp := PackedFloat32Array()
	for i in _types.size():
		var pr := enemy_prog(i, t)
		pos.append(path.point_at(pr, _lat[i]))
		var d := path.dir_at(pr)
		yaw.append(rad_to_deg(atan2(d.y, d.x)))
		walk.append(pr / (3.0 if _types[i] == 3 else SPACING_M))
		hp.append(0.6 if _types[i] >= 4 else 1.0)
	crowd.set_enemies(_types, pos, yaw, walk, hp)


func _update_machines(t: float) -> void:
	var walkers := [2, 3, 1, 2]
	for s in 4:
		machines.set_wheel(s, rad_to_deg(t * (1.2 + 0.35 * s) / 7.0), true, walkers[s], t * 1.6)
	machines.set_route(0, 1)
	machines.set_route(1, 2)
	machines.set_route(2, -1)
	machines.set_route(3, -1)
	for id in [1, 2, 3]:
		var target := _target_for(id, t)
		var yaw := SiegePath.yaw_to(path.station_pos[id], target)
		machines.set_station(id, yaw, clampf((t - _last_fire[id]) / (SHOT_EVERY_S * 3.0), 0.0, 1.0))
	machines.racks = 7 & ~(1 << (floori(t / 0.5) % 3))
	machines.mine_phase = fposmod(t * 0.6, 1.0)
	machines.pump_phase = fposmod(t * 0.4, 1.0)
	machines.gate_stage = 1
	machines.curtain_stage = 3
	machines.coat_stage = 2
	machines.set_pad(1, 1, SiegePath.yaw_to(path.pads[0], _target_for(11, t)))
	machines.set_pad(2, 1, SiegePath.yaw_to(path.pads[1], _target_for(12, t)))
	machines.set_pad(3, 0, 0.0)
	machines.set_pad(4, 0, 0.0)
	machines.rebuild()


## The enemy a station (1..3) or pad (10 + pad) aims at: a different group each.
func _target_for(src: int, t: float) -> Vector3:
	var pick := {1: 0, 2: 2, 3: 4, 11: 3, 12: 6}
	var group: int = pick.get(src, 0)
	var i := 0
	for g in group:
		i += int(COLUMN[g][3]) * int(COLUMN[g][4])
	return path.point_at(enemy_prog(i, t), _lat[i])


func _fire_until(t: float) -> void:
	while (_fired + 1) * _shot_every <= t:
		_fired += 1
		var ft := _fired * _shot_every
		var src: int = [1, 2, 3, 3, 11, 2, 12, 3][posmod(_fired, 8)]
		var ev := shot_event(src, ft)
		if not ev.is_empty():
			shots.add_event(ev)
			if src < 10:
				_last_fire[src] = ft


## A shot event as the rules would send it (docs/games/siege.md 2.6), aimed at the target's
## position at fire time.
func shot_event(src: int, ft: float) -> Dictionary:
	var target := _target_for(src, ft)
	var o: Vector3
	var v := Vector3.ZERO
	var kind := 0
	var n := 1
	if src >= 10:
		o = path.pads[src - 11] + Vector3(0, 0, 1.5)
		kind = 3
		v = SiegeBallistics.solve_angle(o, target, 50.0, 0.001)
	else:
		o = path.muzzle(src, SiegePath.yaw_to(path.station_pos[src], target))
		match src:
			1:
				v = SiegeBallistics.solve_angle(o, target + Vector3(0, 0, 1.0), 70.0, 0.0004)
			2:
				kind = 1
				v = SiegeBallistics.solve_speed(o, target, 45.0, 0.0016, 8.0, 34.0)
			3:
				kind = 2
				n = 12
				v = SiegeBallistics.solve_speed(o, target, 42.0, 0.006, 15.0, 60.0)
	if v == Vector3.ZERO:
		return {}
	var tk := floori(ft / SiegeBallistics.DT)
	return {
		"type": "shot",
		"tk": tk,
		"src": src,
		"kind": kind,
		"o": [roundi(o.x * 100.0), roundi(o.y * 100.0), roundi(o.z * 100.0)],
		"v": [roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0)],
		"n": n,
		"sd": 1000 + _fired * 7919,
	}
