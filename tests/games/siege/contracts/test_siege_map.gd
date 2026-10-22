extends GutTest
## Castellum Rotae (content/siege/maps/rotae.json; brief 2.9, 3 "Scene"): the geometry the rules,
## Autopilot and the view share.

const F := preload("res://tests/games/siege/siege_fakes.gd")

var _map: SiegeMap
var _raw: Dictionary


func before_all() -> void:
	_raw = SiegeContent.read_files()["map"]
	_map = SiegeMap.from_dict(_raw)


func test_the_map_validates() -> void:
	assert_eq(SiegeMap.validate(_raw), [] as Array[String])
	assert_eq(_map.id, "rotae")
	assert_eq(_map.road_count(), 3)


func test_the_fort_is_64_by_52_with_the_generator_in_the_middle() -> void:
	assert_eq(_map.fort_size, Vector2(64, 52))
	assert_eq(_map.generator_pos, Vector2.ZERO)


func test_the_gate_is_in_the_south_wall_facing_the_camera() -> void:
	assert_eq(_map.gate_pos.y, _map.fort_size.y / 2.0, "on the south wall (+z, toward the camera)")
	assert_almost_eq(_map.gate_pos.x, 0.0, 1e-6)
	assert_gt(_map.plaza_center.y, _map.gate_pos.y, "the plaza is outside, in front of the gate")


func test_four_wheels_nw_ne_sw_se() -> void:
	var w := _map.wheels
	assert_true(w[0].x < 0 and w[0].y < 0, "slot 0 NW")
	assert_true(w[1].x > 0 and w[1].y < 0, "slot 1 NE")
	assert_true(w[2].x < 0 and w[2].y > 0, "slot 2 SW")
	assert_true(w[3].x > 0 and w[3].y > 0, "slot 3 SE")
	for p in w:
		assert_lt(absf(p.x), _map.fort_size.x / 2.0)
		assert_lt(absf(p.y), _map.fort_size.y / 2.0)


func test_pads_3_and_4_flank_the_gate() -> void:
	var p3 := _map.pad_pos(3)
	var p4 := _map.pad_pos(4)
	assert_true(p3.x > _map.gate_pos.x and p4.x < _map.gate_pos.x, "one on each side")
	assert_lte(p3.distance_to(_map.gate_pos), 12.0)
	assert_lte(p4.distance_to(_map.gate_pos), 12.0)
	for n in range(1, 9):
		var d := _map.pad_pos(n)
		assert_true(
			absf(absf(d.x) - 32.0) < 1e-6 or absf(absf(d.y) - 26.0) < 1e-6,
			"pad %d sits on the wall" % n
		)


func test_roads_run_100_to_120_m_from_off_screen_to_the_gate_plaza() -> void:
	for r in _map.road_count():
		var length := _map.road_length(r)
		assert_between(length, 100.0, 120.0, "road %d length" % r)
		var pts := _map.roads[r]
		assert_lte(
			pts[pts.size() - 1].distance_to(_map.plaza_center),
			_map.plaza_radius_m,
			"road %d ends in the plaza" % r
		)
		assert_gte(pts[0].length(), 70.0, "road %d spawns far outside the fort" % r)
		assert_eq(_map.point_at(r, length), pts[pts.size() - 1])
		assert_eq(_map.point_at(r, 0.0), pts[0])


func test_every_road_passes_within_18_m_of_2_pads_and_40_m_of_4() -> void:
	for r in _map.road_count():
		var near := 0
		var mid := 0
		for n in range(1, 9):
			var d := _map.distance_to_road(_map.pad_pos(n), r)
			near += int(d <= 18.0)
			mid += int(d <= 40.0)
		assert_gte(near, 2, "road %d: pads within 18 m" % r)
		assert_gte(mid, 4, "road %d: pads within 40 m" % r)


func test_the_ring_is_clockwise_on_screen() -> void:
	var angles: Array[float] = []
	for n in _map.ring:
		var p := _map.pad_pos(n)
		angles.append(fposmod(rad_to_deg(atan2(p.x, -p.y)), 360.0))
	var turns := 0
	for i in angles.size():
		var a := angles[i]
		var b := angles[(i + 1) % angles.size()]
		turns += int(b < a)
	assert_eq(turns, 1, "angles increase around the ring exactly once: %s" % [angles])
	assert_eq(_map.ring_step(1, 1), 2)
	assert_eq(_map.ring_step(8, 1), 1)
	assert_eq(_map.ring_step(1, -1), 8)
	assert_eq(_map.ring_step(SiegeIds.TARGET_GEN, 1), _map.ring[0])
	assert_eq(_map.ring_step(SiegeIds.TARGET_GEN, -1), _map.ring[-1])


func test_every_wheel_reaches_every_pad_along_the_wall_walk() -> void:
	for slot in 4:
		for n in range(1, 9):
			var path := _map.chain_path(slot, n)
			assert_gte(path.size(), 2, "slot %d -> pad %d" % [slot, n])
			if path.size() >= 2:
				assert_eq(path[0], _map.wheel_pos(slot))
				assert_eq(path[path.size() - 1], _map.pad_pos(n))


func test_point_at_offsets_to_the_left_of_travel() -> void:
	var a := _map.point_at(1, 50.0)
	var dir := _map.dir_at(1, 50.0)
	var left := _map.point_at(1, 50.0, 1.5)
	assert_almost_eq(a.distance_to(left), 1.5, 1e-4)
	assert_almost_eq((left - a).dot(dir), 0.0, 1e-4)
	assert_almost_eq(_map.distance_to_road(a, 1), 0.0, 1e-4)


func test_scatter_and_view_sections() -> void:
	var sc: Dictionary = _raw["scatter"]
	assert_eq(sc["counts"], {"cypress": 600.0, "olive": 400.0, "rocks": 300.0})
	assert_true(sc.has("seed"))
	assert_gt((sc["exclude_rects"] as Array).size(), 0, "the fort is excluded")
	assert_gt(float(sc["road_clear_m"]), 0.0, "roads are kept clear")
	var cam: Dictionary = _raw["camera"]
	assert_almost_eq(float(cam["pitch_deg"]), 42.0, 1.0)
	assert_between(float(cam["fov_deg"]), 30.0, 35.0)


func test_validate_rejects_a_broken_map() -> void:
	var bad := _raw.duplicate(true)
	bad.erase("roads")
	assert_gt(SiegeMap.validate(bad).size(), 0)
	bad = _raw.duplicate(true)
	(bad["ring"] as Array).pop_back()
	assert_gt(SiegeMap.validate(bad).size(), 0)
	bad = _raw.duplicate(true)
	(bad["pads"] as Array).pop_back()
	assert_gt(SiegeMap.validate(bad).size(), 0)
	assert_gt(SiegeMap.validate("nope").size(), 0)
