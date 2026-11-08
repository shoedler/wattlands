extends GutTest
## The Hangar and the Roll-out's first seconds as the view draws them (TankHangar): the hull on its stand with
## its tracks spinning, the white ceiling bars, the countdown (bars dark, beacons, hull lowered, door), the
## roll-out sliding the hangar away, the far panel's gate, and the art files the draw code reads.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const HANGAR := 0
const ROLLOUT := 1
const ADVANCE := 2


func _state(index: int, elapsed: float, crew: int = 2) -> TankState:
	var c := TankFixtures.content()
	var s := TankFixtures._base(c, crew, index, elapsed)
	s.hull.x_px = 0.0
	s.hull.distance_m = 0.0
	s.hull.speed_mps = 0.0
	s.enemies.clear()
	return s


func _view(index: int, elapsed: float, size: Vector2 = Vector2(960, 540)) -> TankView:
	return U.view_of(self, _state(index, elapsed), Wl.SOLO, 1, size)


func _lk(v: TankView) -> Dictionary:
	return v.hangar_look


# --- The look through the countdown --------------------------------------------------------------------


func test_the_hangar_is_on_with_the_hull_up_and_the_bars_lit() -> void:
	var v := _view(HANGAR, 60.0)
	var lk := _lk(v)
	assert_true(bool(lk["on"]))
	assert_true(bool(lk["far_on"]))
	assert_eq(float(lk["lift"]), TankHangar.STAND_LIFT, "on its stand")
	assert_eq(float(lk["dark"]), 0.0, "the bars are lit")
	assert_eq(float(lk["beacon"]), 0.0)
	assert_eq(float(lk["door"]), 0.0, "the door is shut")
	assert_eq(float(lk["end_x"]), TankHangar.END_X)


func test_the_countdown_darkens_the_bars_turns_the_beacons_lowers_the_hull_and_opens_the_door(
) -> void:
	var rows := {}
	for left: float in [10.0, 9.0, 7.0, 5.0, 3.0, 1.0, 0.0]:
		var v := _view(HANGAR, 180.0 - left)
		rows[left] = _lk(v)
	assert_eq(float(rows[10.0]["dark"]), 0.0, "the countdown starts lit")
	assert_gt(float(rows[7.0]["dark"]), 0.9, "the bars are dark within 3 s")
	assert_eq(float(rows[5.0]["dark"]), 1.0)
	assert_gt(float(rows[9.0]["beacon"]), 0.0, "the beacons come on first")
	assert_eq(float(rows[5.0]["beacon"]), 1.0)
	var lift_prev := TankHangar.STAND_LIFT + 1.0
	for left: float in [10.0, 9.0, 7.0, 5.0, 3.0, 1.0, 0.0]:
		assert_lte(float(rows[left]["lift"]), lift_prev, "the hull only goes down (%s)" % left)
		lift_prev = float(rows[left]["lift"])
	assert_eq(float(rows[5.0]["lift"]), 0.0, "lowered by 5 s before the end")
	assert_eq(float(rows[10.0]["door"]), 0.0)
	assert_between(float(rows[3.0]["door"]), 0.2, 0.9, "the door is on its way")
	assert_eq(float(rows[0.0]["door"]), 1.0, "open when the hangar ends")


func test_the_rollout_keeps_the_hangar_behind_the_tank_and_then_drops_it() -> void:
	var v := _view(ROLLOUT, 1.0)
	var lk := _lk(v)
	assert_true(bool(lk["on"]))
	assert_eq(float(lk["lift"]), 0.0, "off its stand")
	assert_eq(float(lk["door"]), 1.0, "through the open door")
	assert_eq(float(lk["dark"]), 1.0, "the bars stay dark")
	assert_gt(float(lk["beacon"]), 0.9, "the beacons turn until it is out")
	var s := v.game.state
	s.seg.elapsed_s = 60.0
	s.hull.x_px = 900.0
	s.hull.distance_m = 900.0 / TankConst.PX_PER_M
	U.run(v, 40)
	assert_false(bool(_lk(v)["on"]), "the end wall has slid off the stage")
	assert_eq(float(_lk(v)["beacon"]), 0.0)
	var adv := _view(ADVANCE, 1.0)
	assert_false(bool(_lk(adv)["on"]), "nothing in an Advance")
	assert_false(bool(_lk(adv)["far_on"]))


func test_the_end_wall_stands_near_the_panels_edge_on_every_canvas() -> void:
	for size: Vector2 in [Vector2(960, 540), Vector2(1280, 680), Vector2(852, 480)]:
		var v := _view(HANGAR, 60.0, size)
		var end_x := float(_lk(v)["end_x"])
		assert_lte(end_x, TankFarMap.near_end_x(size.x), "inside the near panel at %s" % size)
		assert_gte(
			end_x, v.tank_pos.x + TankHangar.END_NOSE_GAP - 0.5, "clear of the nose at %s" % size
		)
	assert_eq(float(_lk(_view(HANGAR, 60.0))["end_x"]), TankHangar.END_X, "the base canvas")


func test_the_end_wall_slides_left_with_the_hull() -> void:
	var v := _view(ROLLOUT, 1.0)
	var x0 := float(_lk(v)["end_x"])
	var s := v.game.state
	s.hull.x_px = 100.0
	U.run(v, 40)
	assert_almost_eq(float(_lk(v)["end_x"]), x0 - 100.0 * TankView.S, 0.5, "the world's scale")


func test_the_hangar_is_never_drawn_in_free_roam_or_a_fight() -> void:
	var g: TankGame = autofree(U.roam_game(U.roam_state(3)))
	var v := U.make_view(self, g)
	assert_false(bool(_lk(v)["on"]))
	assert_false(bool(_lk(v)["far_on"]))


# --- The tank on its stand ----------------------------------------------------------------------------------


func test_the_hull_rides_the_stand_height_higher_than_on_the_floor() -> void:
	var up := _view(HANGAR, 60.0)
	var down := _view(ROLLOUT, 1.0)
	U.run(up, 4)
	U.run(down, 4)
	var dy := down.xf.origin.y - up.xf.origin.y
	assert_almost_eq(dy, TankHangar.STAND_LIFT, 3.0, "the hull is lifted by the stand's height")


func test_the_tracks_turn_in_the_air_and_the_hull_goes_nowhere() -> void:
	var v := _view(HANGAR, 60.0)
	var s := v.game.state
	s.hull.speed_mps = 8.0
	var t0 := v.travel
	U.run(v, 60)
	assert_gt(v.travel - t0, 80.0, "the tracks run at 8 m/s: 96 art px in a second")
	assert_eq(v.hull_x, 0.0, "the hull has not moved")
	assert_eq(v.scroll_px, 0.0, "nor has the world")


func test_the_hangar_floor_is_flat_and_the_road_outside_is_not() -> void:
	var v := _view(HANGAR, 60.0)
	for x in range(0, 560, 40):
		assert_eq(v.ground.lift(float(x)), 0.0, "flat at %d" % x)
	var r := _view(ROLLOUT, 1.0)
	r.game.state.hull.x_px = 1500.0
	U.run(r, 40)
	var any := false
	for x in range(0, 560, 20):
		any = any or absf(r.ground.lift(float(x))) > 0.01
	assert_true(any, "the road has its bumps once the hangar is behind")


# --- The ceiling bars ---------------------------------------------------------------------------------------


func test_the_bars_stand_every_150_px_and_scroll_with_the_world() -> void:
	var v := _view(HANGAR, 60.0)
	var xs := TankHangar.bar_xs(_lk(v), v.canvas.x, TankHangar.END_X - 8.0)
	assert_gte(xs.size(), 3, "a few across the near panel")
	for i in range(1, xs.size()):
		assert_almost_eq(xs[i] - xs[i - 1], TankHangar.BAR_PITCH, 0.01)
	var r := _view(ROLLOUT, 1.0)
	var before := TankHangar.bar_xs(_lk(r), r.canvas.x, 1000.0)
	r.game.state.hull.x_px = 60.0
	U.run(r, 40)
	var after := TankHangar.bar_xs(_lk(r), r.canvas.x, 1000.0)
	assert_lt(after[0], before[0] + 0.01, "they went left")


# --- The far panel -----------------------------------------------------------------------------------------


func test_the_far_gate_stands_centred_in_the_hangar_and_slides_away_on_the_roll_out() -> void:
	var v := _view(HANGAR, 60.0)
	assert_almost_eq(
		float(_lk(v)["far_x"]), v.far.far_w * 0.5, 0.01, "the gate faces the far panel"
	)
	var r := _view(ROLLOUT, 1.0)
	var x0 := float(_lk(r)["far_x"])
	r.game.state.hull.x_px = 400.0
	U.run(r, 40)
	assert_lt(float(_lk(r)["far_x"]), x0, "it goes off at the far parallax")
	r.game.state.hull.x_px = 6000.0
	U.run(r, 40)
	assert_false(bool(_lk(r)["far_on"]), "and is gone")


func test_the_far_panel_shows_the_depot_base_nowhere_in_the_hangar() -> void:
	var v := _view(HANGAR, 60.0)
	assert_true(is_nan(TankForest.far_base(v, v.game.state)))


# --- The art ---------------------------------------------------------------------------------------------------


func test_the_baked_art_is_the_size_the_draw_code_reads() -> void:
	var want := {
		TankHangar.ROOM: Vector2i(480, int(TankHangar.ROOM_H)),
		TankHangar.END: Vector2i(int(TankHangar.END_W), int(TankHangar.ROOM_H)),
		TankHangar.DOOR: Vector2i(int(TankHangar.DOOR_W), int(TankHangar.DOOR_H)),
		TankHangar.GATE: Vector2i(int(TankHangar.GATE_W), int(TankHangar.GATE_H)),
		TankHangar.SHUTTER: Vector2i(32, 8),
	}
	for path: String in want:
		var t := TankHangar.tex(path)
		assert_not_null(t, path)
		if t != null:
			assert_eq(Vector2i(t.get_width(), t.get_height()), want[path], path)


func test_the_doorway_and_the_gate_opening_are_clear_and_the_rest_is_solid() -> void:
	var end := TankHangar.tex(TankHangar.END).get_image()
	var mid_y := int((TankHangar.VOID_TOP + TankHangar.VOID_BOT) * 0.5)
	var mid_x := int((TankHangar.VOID_X0 + TankHangar.VOID_X1) * 0.5)
	assert_eq(end.get_pixel(mid_x, mid_y).a, 0.0, "the doorway is clear")
	assert_eq(end.get_pixel(mid_x, 40).a, 1.0, "the wall above it is solid")
	assert_eq(end.get_pixel(mid_x, int(TankHangar.VOID_BOT) + 10).a, 1.0, "and the floor slab")
	var gate := TankHangar.tex(TankHangar.GATE).get_image()
	var gx := int((TankHangar.AP_X0 + TankHangar.AP_X1) * 0.5)
	var gy := int(TankHangar.VOID_TOP - TankHangar.GATE_Y0) + 100
	assert_eq(gate.get_pixel(gx, gy).a, 0.0, "the gate's opening is clear")
	assert_eq(gate.get_pixel(5, gy).a, 1.0, "its jamb is solid")
	var room := TankHangar.tex(TankHangar.ROOM).get_image()
	for y in [10, 100, 300, 400]:
		assert_eq(room.get_pixel(200, y).a, 1.0, "the room tile is opaque at y %d" % y)
