extends GutTest
## The ride view (BRIEF 3.7) builds headless and draws what the state says: parallax
## layers, one pennant per rider at its distance from the local rider (slot color, shape,
## pattern), the course profile in Rolling road and the interval blocks on the ground.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const FIXTURE := "res://tests/games/workout/fixtures/rolling_snapshot.json"


func _fixture() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data is Dictionary, "fixture parses")
	return U.apply_int_fields(data, WorkoutSnapshot.INT_FIELDS)


func _client_view() -> WorkoutRideView:
	var client := U.game("rolling_road", U.players(2, 2), Wl.CLIENT, 2)
	autofree(client)
	client.apply_snapshot(_fixture())
	var view := client.make_view() as WorkoutRideView
	add_child_autofree(view)
	view.refresh()
	return view


func test_make_view_returns_a_node2d_with_layers() -> void:
	var g := U.game("easy_30", U.players(1))
	autofree(g)
	var view := g.make_view()
	assert_true(view is Node2D, "a 2D view for the PixelViewport")
	assert_true(view is WorkoutRideView)
	add_child_autofree(view)
	assert_eq(view.get_child_count(), 6, "sky, clouds, three parallax strips, track")
	var rv := view as WorkoutRideView
	assert_eq(rv.sky.texture.get_size(), Vector2(640, 360))
	assert_eq(rv.far_hills.factor, 0.06)
	assert_false(rv.model.is_empty(), "the first refresh ran in _ready")


func test_builds_from_a_fixture_snapshot() -> void:
	var view := _client_view()
	var markers: Array = view.model["markers"]
	assert_eq(markers.size(), 4, "one pennant per rider")
	assert_eq(int(markers.back()["peer"]), 2, "the local rider is drawn last")
	var me := view.marker(2)
	assert_almost_eq(float(me["x"]), WorkoutRideView.RIDER_X, 0.001)
	assert_almost_eq(float(view.marker(1)["x"]), WorkoutRideView.RIDER_X + 10.0, 0.001, "20 m ahead at 2 m per px")
	assert_almost_eq(float(view.marker(-1)["x"]), WorkoutRideView.RIDER_X + 110.0, 0.001)
	var far := view.marker(-2)
	assert_eq(int(far["edge"]), 1, "off screen to the right")
	assert_almost_eq(float(far["x"]), 640.0 - WorkoutRideView.EDGE_MARGIN_RIGHT, 0.001)


func test_pennants_carry_the_slot_look() -> void:
	var view := _client_view()
	var me := view.marker(2)
	var colors: Array = []
	for s: Dictionary in me["shapes"]:
		colors.append(s["color"])
	assert_true(colors.has(Wl.slot_look(1)["color"]), "slot 1's color")
	assert_true(colors.has(WorkoutArt.WHITE), "the local rider's caret")
	# Slot 1 is dashed: two dark stripes on the flag.
	var dark: Color = (Wl.slot_look(1)["color"] as Color).darkened(0.45)
	assert_eq(colors.count(dark), 2)
	var rescued := view.marker(-2)
	var rescued_colors: Array = []
	for s: Dictionary in rescued["shapes"]:
		rescued_colors.append(s["color"])
	assert_false(rescued_colors.has(Wl.slot_look(3)["color"]), "a rescued rider's flag is faded")
	assert_false(rescued_colors.has(WorkoutArt.GLOW), "no in-band glow during rescue")


func test_every_slot_look_is_distinct() -> void:
	var seen: Array = []
	for i in 8:
		var shapes := WorkoutArt.pennant_shapes(Wl.slot_look(i), i)
		var sig: Array = []
		for s: Dictionary in shapes:
			sig.append([s["color"], (s["points"] as PackedVector2Array).size()])
		assert_false(seen.has(sig), "slot %d differs from the others" % i)
		seen.append(sig)
	for shape: String in ["circle", "triangle", "square", "diamond"]:
		assert_gt(WorkoutArt.shape_points(shape, Vector2.ZERO, 3.0).size(), 2)


func test_the_road_follows_the_course_in_rolling_road() -> void:
	var view := _client_view()
	var road: PackedFloat64Array = view.model["road"]
	assert_eq(road.size(), 640 / WorkoutTrackLayer.COLUMN_W)
	var lo := INF
	var hi := -INF
	for y in road:
		lo = minf(lo, y)
		hi = maxf(hi, y)
		assert_true(y >= WorkoutRideView.ROAD_MIN_Y and y <= WorkoutRideView.ROAD_MAX_Y)
	assert_gt(hi - lo, 4.0, "hills on the road")
	var g := U.game("sweet_spot", U.players(1))
	autofree(g)
	U.ride(g, Callable(), 100)
	var flat := g.make_view() as WorkoutRideView
	add_child_autofree(flat)
	for y in (flat.model["road"] as PackedFloat64Array):
		assert_eq(y, WorkoutRideView.ROAD_Y, "flat outside course phases")


func test_interval_blocks_on_the_ground() -> void:
	var view := _client_view()
	var blocks: Array = view.model["blocks"]
	assert_eq(blocks.size(), 2, "the warm-up and the rolling road are on screen; the cool-down is 14 min ahead")
	assert_eq(blocks[1]["color"], WorkoutArt.ZONE_COURSE)
	assert_true(bool(blocks[1]["hatched"]))
	# Now (400 s) sits under the local rider: the rolling road started 100 s ago.
	var road_pts: PackedVector2Array = blocks[1]["points"]
	assert_almost_eq(road_pts[0].x, WorkoutRideView.RIDER_X - 100.0 * WorkoutRideView.STRIP_PX_PER_S + 1.0, 0.001)
	var warm: PackedVector2Array = blocks[0]["points"]
	assert_lt(warm[1].y, warm[0].y, "the warm-up ramp rises")


func test_parallax_scrolls_with_the_local_rider() -> void:
	var view := _client_view()
	var d := 5180.0
	assert_almost_eq(view.near_trees.scroll_x, d * WorkoutRideView.VISUAL_PX_PER_M, 0.01)
	assert_eq(view.sky.first_tile_x(), 0.0, "the sky never moves")
	assert_true(view.near_trees.first_tile_x() <= 0.0)


func test_the_view_never_changes_the_state() -> void:
	var view := _client_view()
	var before := JSON.stringify(WorkoutSnapshot.encode(view.game.state, true))
	for i in 5:
		view.refresh()
		view._process(0.016)
	assert_eq(JSON.stringify(WorkoutSnapshot.encode(view.game.state, true)), before)


func test_procedural_art_is_deterministic() -> void:
	assert_eq(WorkoutArt.far_hills_image().get_data(), WorkoutArt.far_hills_image().get_data())
	assert_eq(WorkoutArt.trees_image().get_data(), WorkoutArt.trees_image().get_data())
	var hills := WorkoutArt.mid_hills_image()
	# Seamless: the first and last columns have the same height.
	var first := -1
	var last := -1
	for y in hills.get_height():
		if first < 0 and hills.get_pixel(0, y).a > 0.5:
			first = y
		if last < 0 and hills.get_pixel(hills.get_width() - 1, y).a > 0.5:
			last = y
	assert_lt(absi(first - last), 3, "the strip tiles without a step")
