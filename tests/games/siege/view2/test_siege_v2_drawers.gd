extends GutTest
## The v2 view primitives without SiegeState: the crowd drawer at the 150-enemy cap, the machine
## drawer's frame choice, the depth sprite, and the world layer.

const MAP := "res://content/siege/maps/rotae.json"

var bank: SiegeBakeBank = null
var path: SiegePath = null


func before_all() -> void:
	bank = SiegeBakeBank.shared()
	path = SiegePath.load_file(MAP)


func _column(count: int) -> Dictionary:
	var types := PackedInt32Array()
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var walk := PackedFloat32Array()
	var hp := PackedFloat32Array()
	for i in count:
		var prog := 10.0 + i * 2.3
		types.append([1, 1, 1, 2, 3, 1, 4, 5][i % 8])
		pos.append(path.point_at(prog, (i % 4 - 1.5) * 1.2))
		var d := path.dir_at(prog)
		yaw.append(rad_to_deg(atan2(d.y, d.x)))
		walk.append(prog / 1.2)
		hp.append(0.5)
	return {"types": types, "pos": pos, "yaw": yaw, "walk": walk, "hp": hp}


func test_crowd_draws_150_enemies_in_one_batch() -> void:
	var crowd := SiegeV2Crowd.new(bank)
	add_child_autofree(crowd)
	var c := _column(150)
	var t0 := Time.get_ticks_usec()
	crowd.set_enemies(c["types"], c["pos"], c["yaw"], c["walk"], c["hp"])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_eq(crowd.drawn, 150)
	assert_eq(crowd.dropped, 0)
	# a shadow and a body each, and two hp bar cells per engine
	var engines := 0
	for t in c["types"]:
		if t >= 4:
			engines += 1
	assert_eq(crowd.entry_count(), 300 + engines * 2)
	assert_eq(crowd.committed_count(), crowd.entry_count())
	assert_lt(ms, 30.0, "150 enemies in %.1f ms" % ms)
	gut.p("crowd: 150 enemies, %d entries in %.2f ms" % [crowd.entry_count(), ms])


func test_crowd_caps_at_150() -> void:
	var crowd := SiegeV2Crowd.new(bank)
	add_child_autofree(crowd)
	var c := _column(220)
	crowd.set_enemies(c["types"], c["pos"], c["yaw"], c["walk"], c["hp"])
	assert_eq(crowd.drawn, SiegeV2Crowd.MAX_ENEMIES)


func test_crowd_frames_follow_facing_and_walk() -> void:
	# east on the ground runs right on screen; south (toward the camera) runs left
	assert_eq(SiegeV2Crowd.frame_for(1, 0.0, 0.0), 0)
	assert_eq(SiegeV2Crowd.frame_for(1, PI / 2.0, 0.0), 4)
	assert_eq(SiegeV2Crowd.frame_for(1, 0.0, 0.26), 1)
	assert_eq(SiegeV2Crowd.frame_for(2, 0.0, 1.76), 3, "walk frames repeat every 1")
	# a chariot heading south-east (straight down the screen) shows its front
	assert_eq(SiegeV2Crowd.frame_for(3, PI / 4.0, 0.0), 8)
	assert_eq(SiegeV2Crowd.frame_for(3, -3.0 * PI / 4.0, 0.0), 12)
	# engines turn in 8 yaws
	assert_eq(SiegeV2Crowd.frame_for(4, PI / 2.0, 0.0), 2)
	assert_eq(SiegeV2Crowd.frame_for(5, -PI / 4.0, 0.3), 7)
	for t in [1, 2, 3, 4, 5]:
		var part: String = SiegeV2Crowd.PARTS[t]
		for k in [0, 3, 7]:
			var i := SiegeV2Crowd.frame_for(t, k * PI / 4.0, 0.6)
			assert_lt(i, bank.frame_count(part), "%s frame %d" % [part, i])


func test_machines_pick_their_frames() -> void:
	var m := SiegeV2Machines.new(bank)
	add_child_autofree(m)
	var lay := bank.layout("wheel_3")
	assert_eq(m.wheel_frame(3, 0.0), 0)
	assert_eq(m.wheel_frame(3, float(lay["period_deg"])), 0, "wheel frames wrap at their period")
	assert_eq(m.wheel_frame(3, float(lay["step_deg"]) * 5.5), 5)
	assert_eq(m.wheel_frame(0, -1.0), bank.frame_count("wheel_0") - 1)
	assert_eq(SiegeV2Machines.yaw_index(114.0, 16), 5)
	assert_eq(SiegeV2Machines.yaw_index(-10.0, 16), 0)
	assert_eq(SiegeV2Machines.yaw_index(350.0, 8), 0)
	assert_eq(SiegeV2Machines.nearest_phase([0, 0.2, 0.4, 0.6, 0.8, 1], 0.71), 4)


func test_machines_draw_routes_and_stations() -> void:
	var m := SiegeV2Machines.new(bank)
	add_child_autofree(m)
	for s in 4:
		m.set_wheel(s, s * 40.0, true, s, 0.3)
	m.rebuild()
	var idle := m.entry_count()
	# 4 wheels, 4 output shafts, 6 walkers, 5 station shafts, 5 rings, 6 stations, gate, 4 pads
	assert_eq(idle, 4 + 4 + 6 + 5 + 5 + 6 + 1 + 4)
	m.set_route(0, 1)
	m.set_route(1, 2)
	m.curtain_stage = 2
	m.coat_stage = 1
	m.rebuild()
	assert_eq(m.entry_count(), idle + 2 + 2, "two routes, the curtain and the coat")
	assert_eq(m.driver(2), 1)
	assert_eq(m.driver(3), -1)
	assert_eq(m.dropped, 0)


func test_the_depth_shader_loads() -> void:
	var shader := load(SiegeBakeBank.SHADER_PATH) as Shader
	assert_not_null(shader)
	assert_false(shader.code.is_empty())


func test_world_layer_hides_points_behind_walls() -> void:
	var w := SiegeV2WorldLayer.new(bank)
	add_child_autofree(w)
	# the courtyard behind the front wall is hidden where the wall stands in front of it; a
	# point on the open road is not
	assert_false(w.occluded(path.point_at(100.0) + Vector3(0, 0, 0.4)))
	assert_true(w.occluded(Vector3(20, 52, 0.2)), "the yard just behind the 9 m front wall")
	assert_true(w.occluded(Vector3(44, 58, 1.0)), "the gate passage behind the gatehouse")
