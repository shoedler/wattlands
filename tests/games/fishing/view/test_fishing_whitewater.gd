extends GutTest
## Turbo Reel's boat water (FishingWhitewater, mockups E4 and E7): the level follows speed and
## planing with hysteresis, the long-shaft prop stays under water in every pose and heave, the
## water grows with the level, a frame is a pure function of travel and time, the wake streams
## back and fades, towing piles the mound at the transom and throws a reverse wake, and every
## lump stays on the palette and the grid.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")


func after_each() -> void:
	FishingWhitewater.recording = false
	FishingWhitewater.drawn.clear()


func _boat(pose_deg: float = 0.0, heave: int = 0, heading: int = 1) -> FishingBoatView:
	var b := FishingBoatView.new()
	add_child_autofree(b)
	b.position = Vector2(320, FishingScenery.SURF_Y)
	b.heading = heading
	b.pitch_deg = pose_deg
	b.heave_px = heave
	b.advance(0.0)
	b.advance(0.0)
	return b


func _state(v: float, plane: float = 0.0, tow: float = 0.0, odo: float = 100.0) -> Dictionary:
	return {"slot": 0, "odo": odo, "t": 3.0, "v": v, "plane": plane, "tow": tow, "brake": 0}


## The rects FishingWhitewater draws for one frame (front and behind).
func _draw(b: FishingBoatView, s: Dictionary, w: FishingWhitewater = null) -> Array:
	var ww := w if w != null else FishingWhitewater.new()
	FishingWhitewater.recording = true
	FishingWhitewater.drawn.clear()
	ww.paint_behind(null, b, s)
	ww.paint_front(null, b, s)
	FishingWhitewater.recording = false
	return FishingWhitewater.drawn.duplicate()


func _area(rects: Array) -> float:
	var a := 0.0
	for e: Array in rects:
		a += (e[0] as Rect2).get_area()
	return a


func test_the_level_follows_speed_and_planing_with_hysteresis() -> void:
	assert_eq(FishingWhitewater.level(0.0, 0.0), FishingWhitewater.NONE)
	assert_eq(FishingWhitewater.level(2.0, 0.0), FishingWhitewater.IDLE)
	assert_eq(FishingWhitewater.level(8.0, 0.0), FishingWhitewater.CRUISE)
	assert_eq(FishingWhitewater.level(11.0, 0.0), FishingWhitewater.HUMP)
	assert_eq(FishingWhitewater.level(11.0, 0.8), FishingWhitewater.PLANE)
	assert_eq(FishingWhitewater.level(-8.0, 0.0), FishingWhitewater.CRUISE, "astern counts too")
	assert_eq(
		FishingWhitewater.level(10.3, 0.0, FishingWhitewater.HUMP),
		FishingWhitewater.HUMP,
		"holds the hump just under its edge"
	)
	assert_eq(
		FishingWhitewater.level(10.3, 0.0, FishingWhitewater.CRUISE), FishingWhitewater.CRUISE
	)
	assert_eq(FishingWhitewater.level(9.8, 0.0, FishingWhitewater.HUMP), FishingWhitewater.CRUISE)


func test_the_long_shaft_prop_stays_under_water_in_every_pose_and_heave() -> void:
	for pose in range(FishingRig.POSE_MIN, FishingRig.POSE_MAX + 1):
		for heave: int in [FishingView.HEAVE_UP_PX, 0, -FishingView.HEAVE_DOWN_PX]:
			var dy := FishingRig.tilt_dy(pose, int(FishingRig.PROP_AT.x)) - heave
			var top := int(FishingRig.PROP_AT.y) + dy
			assert_gt(top, FishingRig.WATERLINE, "pose %d heave %d: prop under" % [pose, heave])
	var r := Rect2(FishingRig.PROP_AT, Vector2(FishingSprites.size_of("boat_prop")))
	assert_true(Rect2(Vector2.ZERO, Vector2(FishingRig.HULL_SIZE)).encloses(r))


func test_the_water_grows_from_idle_to_the_plane() -> void:
	var idle := _area(_draw(_boat(), _state(2.0)))
	var cruise := _area(_draw(_boat(2.0), _state(8.0)))
	var hump := _area(_draw(_boat(9.0, -2), _state(11.0)))
	var plane := _area(_draw(_boat(3.5, 4), _state(13.0, 1.0)))
	assert_gt(idle, 0.0)
	assert_gt(cruise, idle * 3.0)
	assert_gt(hump, cruise)
	assert_gt(plane, cruise)
	assert_eq(_draw(_boat(), _state(0.0)).size(), 0, "still water: no whitewater")


func test_a_frame_is_a_pure_function_of_travel_and_time() -> void:
	var b := _boat(3.5, 4)
	var a := _draw(b, _state(13.0, 1.0, 0.0, 345.0))
	var again := _draw(b, _state(13.0, 1.0, 0.0, 345.0))
	assert_eq(a, again, "no flicker: the same frame draws the same lumps")
	var on := _draw(b, _state(13.0, 1.0, 0.0, 351.0))
	assert_ne(a, on, "the wake streams on as the boat travels")


func test_lumps_are_whole_pixels_in_the_whitewater_colours_behind_the_stern() -> void:
	var b := _boat(2.0)
	var allowed := [
		FishingPalette.FOAM, FishingPalette.SKY, FishingPalette.HAZE, FishingPalette.SURFACE
	]
	var stern := b.pixel_of(Vector2i(FishingRig.STERN_X, FishingRig.WATERLINE)).x
	var behind := 0.0
	for e: Array in _draw(b, _state(8.0)):
		var r: Rect2 = e[0]
		assert_eq(r.position, r.position.round(), "on the grid")
		assert_eq(r.size, r.size.round())
		assert_has(allowed, e[1] as Color)
		if r.end.x <= stern:
			behind += r.get_area()
	assert_gt(behind, 200.0, "the wake and the mound trail behind the transom")


func test_heading_home_mirrors_the_water() -> void:
	var out := _draw(_boat(2.0, 0, 1), _state(8.0))
	var home := _draw(_boat(2.0, 0, -1), _state(-8.0))
	assert_eq(out.size(), home.size())
	assert_almost_eq(_area(out), _area(home), 0.01)


func test_a_towing_fish_piles_the_mound_at_the_transom_and_wakes_the_bow() -> void:
	var b := _boat(2.0, -3)
	var g := FishingWhitewater.geometry(b)
	var towed := _draw(b, _state(1.5, 0.0, 0.8))
	var mound := 0.0
	var ahead := 0.0
	for e: Array in towed:
		var r: Rect2 = e[0]
		if absf(r.get_center().x - float(g["T"])) < 30.0:
			mound += r.get_area()
		if r.position.x > float(g["B"]):
			ahead += r.get_area()
	assert_gt(mound, 300.0, "a big mound against the transom")
	assert_gt(ahead, 20.0, "a reverse wake off the bow")


func test_the_view_draws_the_water_without_errors() -> void:
	var g := FX.make_game(2)
	add_child_autofree(g)
	FX.set_drive(g.state.rider(0), 6000.0, 13.0)
	g.state.rider(0).plane = 1.0
	g.state.rider(0).heave_m = 0.06
	FX.set_fight(g.state.rider(1), 6050.0, 8, 30.0, 200.0)
	g.state.rider(1).tow_n = 400.0
	var v := FishingView.new()
	v.game = g
	add_child_autofree(v)
	for i in 10:
		g.state.rider(0).x_m += 0.6
		v.advance(0.05)
	await wait_physics_frames(2)
	assert_gt(float(v.water_state(0)["odo"]), 5.0, "the odometer counts the travel")
	assert_eq(float(v.water_state(1)["tow"]), 0.8)
