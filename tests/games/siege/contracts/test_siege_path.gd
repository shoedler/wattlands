extends GutTest
## SiegePath, the v2 map (brief 2.4 "Map"): one 391 m path of 98 points, the bridge and moat
## edge, the plaza, the staging grounds, the five stations, four pads, four wheels, path progress,
## lateral offsets, the art projection and depth.

const F := preload("res://tests/games/siege/siege_fakes.gd")

var _p: SiegePath


func before_all() -> void:
	_p = SiegePath.load_file("res://content/siege/maps/rotae.json")


func test_the_map_validates() -> void:
	var d: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/siege/maps/rotae.json")
	)
	assert_eq(SiegePath.validate(d), PackedStringArray())


func test_a_broken_map_is_reported() -> void:
	var errs := SiegePath.validate({"version": 1})
	assert_gt(errs.size(), 4)
	assert_true(str(errs).contains("version"))


func test_the_path_has_98_points_and_is_391_m() -> void:
	assert_eq(_p.points.size(), 98)
	assert_almost_eq(_p.length_m, 391.4, 0.5)
	assert_eq(_p.cum.size(), 98)
	assert_eq(_p.cum[0], 0.0)


func test_the_bridge_and_moat_edge() -> void:
	assert_almost_eq(_p.bridge_from_m, 375.4, 0.1)
	assert_almost_eq(_p.bridge_to_m, 391.4, 0.1)
	assert_almost_eq(_p.moat_edge_m, 375.4, 0.1)
	assert_true(_p.on_bridge(380.0))
	assert_false(_p.on_bridge(300.0))


func test_the_road_is_the_first_375_m() -> void:
	assert_almost_eq(_p.bridge_from_m, 375.0, 1.0)


func test_the_plaza() -> void:
	assert_eq(_p.plaza_center, Vector2(44, 81))
	assert_eq(_p.plaza_radius_m, 8.0)


func test_four_staging_grounds_camp_first() -> void:
	assert_eq(_p.staging.size(), 4)
	assert_eq(_p.staging[0], 0.0)
	assert_almost_eq(_p.staging[1], 126.0, 0.5)
	assert_almost_eq(_p.staging[2], 226.0, 0.5)
	assert_almost_eq(_p.dist_to_gate(_p.staging[3]), 110.0, 1.0, "the arch, about 110 m out")


func test_five_stations_with_positions() -> void:
	assert_eq(_p.station_pos.size(), 5)
	for i in 5:
		assert_ne(_p.station_pos[i], Vector3.ZERO, "station %d" % i)
	assert_eq(_p.station_muzzle_m[SiegeIds.STATION_BALLISTA], 7.0)
	assert_eq(_p.station_yaw0_deg[SiegeIds.STATION_ONAGER], 135.0)


func test_four_pads_and_four_wheels() -> void:
	assert_eq(_p.pads.size(), 4)
	assert_eq(_p.wheels.size(), 4)
	for w in _p.wheels:
		assert_ne(w, Vector3.ZERO)
	assert_lt(_p.wheels[0].x, _p.wheels[3].x, "slots 0..3 west to east")
	assert_eq(_p.wheel_radius_m, 7.0)


func test_point_at_runs_from_the_camp_to_the_gate() -> void:
	assert_eq(_p.point_at(0.0), _p.points[0])
	assert_true(_p.point_at(_p.length_m).distance_to(_p.points[97]) < 0.01)
	assert_true(_p.point_at(-5.0).distance_to(_p.points[0]) < 0.01, "clamped before")
	assert_true(_p.point_at(9999.0).distance_to(_p.points[97]) < 0.01, "clamped after")


func test_point_at_follows_the_cumulative_length() -> void:
	for i in range(1, 97, 7):
		assert_true(_p.point_at(_p.cum[i]).distance_to(_p.points[i]) < 0.01, "point %d" % i)


func test_progress_is_exact_along_a_segment() -> void:
	var a := _p.point_at(100.0)
	var b := _p.point_at(101.0)
	assert_almost_eq(Vector2(b.x - a.x, b.y - a.y).length(), 1.0, 0.02)


func test_the_lateral_offset_is_left_of_travel() -> void:
	var c := _p.point_at(150.0)
	var l := _p.point_at(150.0, 1.8)
	var d := _p.dir_at(150.0)
	assert_almost_eq(Vector2(l.x - c.x, l.y - c.y).length(), 1.8, 0.001)
	var left := Vector2(d.y, -d.x)
	assert_almost_eq(Vector2(l.x - c.x, l.y - c.y).normalized().dot(left), 1.0, 0.001)


func test_dir_at_is_a_unit_vector() -> void:
	for p in [0.0, 50.0, 200.0, 390.0]:
		assert_almost_eq(_p.dir_at(p).length(), 1.0, 0.001)


func test_segment_at_brackets_prog() -> void:
	for p in [0.0, 33.3, 200.0, 391.0]:
		var i := _p.segment_at(p)
		assert_true(_p.cum[i] <= p + 1e-4 or i == 0)
		assert_true(i + 1 < _p.points.size())


func test_the_path_ends_at_the_gate() -> void:
	var end := _p.point_at(_p.length_m)
	assert_lt(Vector2(end.x - _p.gate_pos.x, end.y - _p.gate_pos.y).length(), 3.0)
	assert_eq(_p.dist_to_gate(_p.length_m), 0.0)
	assert_almost_eq(_p.dist_to_gate(_p.length_m - 60.0), 60.0, 0.001)


func test_ground_height_follows_the_path() -> void:
	var q := _p.points[40]
	assert_almost_eq(_p.ground_z(q.x, q.y), q.z, 0.001)
	assert_eq(_p.ground_z(-500.0, -500.0), 0.0, "nothing within 30 m: 0")


func test_the_path_is_nearly_flat() -> void:
	for q in _p.points:
		assert_between(q.z, -1.0, 1.0)


func test_art_projection_matches_the_brief() -> void:
	var p := Vector3(10, 20, 3)
	assert_eq(_p.to_art(p), Vector2((10 - 20) * 3.5 + 450, (10 + 20) * 1.75 - 3.5 * 3 + 127))
	assert_eq(SiegePath.depth(p), 33.0)


func test_the_road_stays_on_the_art_canvas() -> void:
	for q in _p.points:
		var a := _p.to_art(q)
		assert_between(a.x, -40.0, 1000.0)
		assert_between(a.y, -40.0, 580.0)


func test_muzzle_is_along_the_aim() -> void:
	var m := _p.muzzle(SiegeIds.STATION_BALLISTA, 90.0)
	var c := _p.station_pos[SiegeIds.STATION_BALLISTA]
	assert_almost_eq(m.x, c.x, 0.001)
	assert_almost_eq(m.y, c.y + 7.0, 0.001)
	assert_eq(m.z, c.z)


func test_yaw_to() -> void:
	assert_almost_eq(SiegePath.yaw_to(Vector3.ZERO, Vector3(0, 10, 0)), 90.0, 0.001)
	assert_almost_eq(SiegePath.yaw_to(Vector3.ZERO, Vector3(-10, 0, 0)), 180.0, 0.001)


func test_ground_dist() -> void:
	var at := _p.point_at(120.0)
	assert_almost_eq(_p.ground_dist(at, 120.0), 0.0, 0.001)


func test_the_content_carries_the_same_path() -> void:
	var c := F.content()
	assert_eq(c.path.points, _p.points)
	assert_eq(c.path.length_m, _p.length_m)
