extends GutTest
## SpinningPart, SlidingPart and ScrollingChain (BRIEF 3.9, 3.10; OWNERSHIP W2D3, W2D4):
## signed speed -1..1, reversing, rates, phase, inertia, sliding range and scroll wrap.


# --- SpinningPart --------------------------------------------------------------------------

func _spin(rpm: float = 60.0) -> SpinningPart:
	var s: SpinningPart = autofree(SpinningPart.new())
	s.max_rpm = rpm
	s.auto_process = false
	return s


func test_speed_is_clamped() -> void:
	var s := _spin()
	s.speed = 3.0
	assert_eq(s.speed, 1.0)
	s.speed = -5.0
	assert_eq(s.speed, -1.0)
	s.speed = NAN
	assert_eq(s.speed, 0.0)


func test_positive_speed_turns_clockwise_at_max_rpm() -> void:
	var s := _spin(60.0)
	s.speed = 1.0
	s.tick(0.25)
	assert_almost_eq(s.revolutions(), 0.25, 0.0001)
	assert_almost_eq(s.rotation, PI / 2.0, 0.0001, "clockwise on screen = increasing rotation")
	s.tick(0.75)
	assert_almost_eq(s.revolutions(), 1.0, 0.0001)


func test_negative_speed_runs_backwards() -> void:
	var s := _spin(60.0)
	s.speed = -0.5
	s.tick(1.0)
	assert_almost_eq(s.revolutions(), -0.5, 0.0001)
	assert_almost_eq(s.angle(), PI, 0.0001)
	s.speed = -1.0
	s.tick(0.25)
	assert_almost_eq(s.revolutions(), -0.75, 0.0001)
	assert_almost_eq(s.angle(), TAU * 0.25, 0.0001, "angle wraps into 0..TAU")


func test_speed_scales_rate() -> void:
	var a := _spin(120.0)
	var b := _spin(120.0)
	a.speed = 0.75   # cadence 90 / 120
	b.drive(90.0, 120.0)
	assert_almost_eq(b.speed, 0.75, 0.0001)
	a.tick(2.0)
	b.tick(2.0)
	assert_almost_eq(a.revolutions(), 3.0, 0.0001, "90 rpm for 2 s")
	assert_almost_eq(b.revolutions(), a.revolutions(), 0.0001)
	b.drive(1.0, 0.0)
	assert_eq(b.speed, 0.0, "zero full scale gives no speed")


func test_ratio_drives_gear_trains() -> void:
	var big := _spin(30.0)
	var small := _spin(30.0)
	small.ratio = -2.0
	big.speed = 1.0
	small.speed = 1.0
	big.tick(1.0)
	small.tick(1.0)
	assert_almost_eq(small.revolutions(), -2.0 * big.revolutions(), 0.0001)


func test_phase_offsets_angle() -> void:
	var s := _spin()
	s.phase_deg = 90.0
	assert_almost_eq(s.angle(), PI / 2.0, 0.0001)
	assert_almost_eq(s.rotation, PI / 2.0, 0.0001)


func test_inertia_follows_speed_gradually() -> void:
	var s := _spin(60.0)
	s.inertia_s = 1.0
	s.speed = 1.0
	s.tick(0.1)
	assert_gt(s.current_speed(), 0.0)
	assert_lt(s.current_speed(), 0.2)
	for i in 100:
		s.tick(0.1)
	assert_almost_eq(s.current_speed(), 1.0, 0.001)
	s.speed = -1.0
	s.tick(0.1)
	assert_gt(s.current_speed(), 0.0, "still coasting forward right after the reversal")


func test_snap_steps_quantize_angle() -> void:
	var s := _spin(60.0)
	s.snap_steps = 8
	s.speed = 1.0
	s.tick(0.1)   # 36 degrees -> nearest 45
	assert_almost_eq(s.angle(), PI / 4.0, 0.0001)
	s.snap_steps = 0
	assert_almost_eq(s.angle(), TAU * 0.1, 0.0001)


func test_zero_dt_and_reset() -> void:
	var s := _spin()
	s.speed = 1.0
	s.tick(0.0)
	assert_eq(s.revolutions(), 0.0)
	s.tick(0.5)
	s.reset()
	assert_eq(s.revolutions(), 0.0)
	assert_eq(s.rotation, 0.0)


func test_spinning_part_animates_in_tree() -> void:
	var s := SpinningPart.new()
	s.speed = 1.0
	s.max_rpm = 600.0
	s.texture = ImageTexture.create_from_image(Image.create_empty(8, 8, false, Image.FORMAT_RGBA8))
	add_child_autofree(s)
	await wait_process_frames(3)
	assert_ne(s.revolutions(), 0.0, "auto_process ticks from _process")


# --- SlidingPart ---------------------------------------------------------------------------

func _slide(mode: SlidingPart.Mode = SlidingPart.Mode.RECIPROCATE) -> SlidingPart:
	var s: SlidingPart = autofree(SlidingPart.new())
	s.mode = mode
	s.auto_process = false
	s.pixel_snap = false
	return s


func test_reciprocate_stays_in_range() -> void:
	var s := _slide()
	s.travel_px = 8.0
	s.max_cps = 1.3
	s.speed = 1.0
	var lo := INF
	var hi := -INF
	for i in 400:
		s.tick(0.01)
		lo = minf(lo, s.offset())
		hi = maxf(hi, s.offset())
	assert_true(lo >= 0.0, "never below 0")
	assert_true(hi <= 8.0 + 0.0001, "never beyond travel")
	assert_almost_eq(hi, 8.0, 0.05, "reaches the full stroke")
	assert_almost_eq(lo, 0.0, 0.05)


func test_reciprocate_half_cycle_is_full_stroke() -> void:
	var s := _slide()
	s.travel_px = 6.0
	s.max_cps = 2.0
	s.speed = 1.0
	s.tick(0.25)   # half a cycle at 2 cycles/s
	assert_almost_eq(s.offset(), 6.0, 0.0001)
	assert_almost_eq(s.travel(), 0.5, 0.0001)


func test_reciprocate_negative_speed_runs_backwards() -> void:
	var s := _slide()
	s.speed = -0.5
	s.max_cps = 1.0
	s.tick(1.0)
	assert_almost_eq(s.travel(), -0.5, 0.0001)
	assert_lt(s.current_speed(), 0.0)


func test_phase_half_cycle_moves_in_opposition() -> void:
	var a := _slide()
	var b := _slide()
	b.phase = 0.5
	for p: SlidingPart in [a, b]:
		p.travel_px = 10.0
		p.speed = 1.0
		p.tick(0.1)
	assert_almost_eq(a.offset() + b.offset(), 10.0, 0.0001)


func test_position_is_rest_plus_axis_offset() -> void:
	var s := _slide()
	s.position = Vector2(50, 20)
	s.axis = Vector2(0, -2)
	s.travel_px = 4.0
	s.max_cps = 1.0
	s.speed = 1.0
	s.tick(0.5)
	assert_eq(s.rest_position, Vector2(50, 20), "rest taken from the position")
	assert_eq(s.axis, Vector2.UP, "axis normalized")
	assert_almost_eq(s.position.y, 16.0, 0.0001)
	assert_almost_eq(s.position.x, 50.0, 0.0001)
	s.rest_position = Vector2(10, 10)
	assert_almost_eq(s.position.y, 6.0, 0.0001)


func test_zero_axis_falls_back_to_right() -> void:
	var s := _slide()
	s.axis = Vector2.ZERO
	assert_eq(s.axis, Vector2.RIGHT)


func test_scroll_wraps_and_reverses() -> void:
	var s := _slide(SlidingPart.Mode.SCROLL)
	s.max_px_s = 10.0
	s.wrap_px = 4.0
	s.speed = 1.0
	s.tick(0.3)
	assert_almost_eq(s.offset(), 3.0, 0.0001)
	s.tick(0.2)
	assert_almost_eq(s.offset(), 1.0, 0.0001, "5 px wraps to 1")
	s.speed = -1.0
	s.tick(0.2)
	assert_almost_eq(s.offset(), 3.0, 0.0001, "back past 0 wraps to 3")
	for i in 50:
		s.tick(0.037)
		assert_true(s.offset() >= 0.0 and s.offset() < 4.0)


func test_scroll_pixel_snap_stays_inside_wrap() -> void:
	var s := _slide(SlidingPart.Mode.SCROLL)
	s.pixel_snap = true
	s.max_px_s = 10.0
	s.wrap_px = 4.0
	s.speed = 1.0
	for i in 200:
		s.tick(0.013)
		var o := s.offset()
		assert_eq(o, roundf(o))
		assert_true(o >= 0.0 and o < 4.0)


func test_sliding_speed_clamped_and_drive() -> void:
	var s := _slide()
	s.speed = 2.0
	assert_eq(s.speed, 1.0)
	s.drive(-60.0, 120.0)
	assert_eq(s.speed, -0.5)


# --- ScrollingChain ------------------------------------------------------------------------

func _chain() -> ScrollingChain:
	var c: ScrollingChain = autofree(ScrollingChain.new())
	c.auto_process = false
	c.set_loop(Vector2(10, 20), 6.0, Vector2(60, 20), 6.0)
	c.pitch_px = 3.0
	c.max_px_s = 30.0
	return c


func test_loop_is_clockwise_and_measured() -> void:
	var c := _chain()
	assert_gt(ScrollingChain.screen_area(c.points), 0.0, "clockwise on screen")
	# Two straight runs of 50 px plus one full circle of radius 6 (polygonal, slightly less).
	assert_almost_eq(c.path_length(), 100.0 + TAU * 6.0, 1.5)


func test_links_are_even_and_evenly_spaced() -> void:
	var c := _chain()
	var links := c.links()
	assert_eq(links.size() % 2, 0, "an even number of links alternates colors around the loop")
	assert_almost_eq(float(links.size()) * c.effective_pitch(), c.path_length(), 0.001)
	for i in range(1, links.size()):
		assert_almost_eq(float(links[i]["d"]) - float(links[i - 1]["d"]), c.effective_pitch(), 0.0001)
		assert_ne(int(links[i]["color_index"]), int(links[i - 1]["color_index"]))


func test_chain_scrolls_with_signed_speed() -> void:
	var c := _chain()
	c.speed = 1.0
	c.tick(0.05)
	assert_almost_eq(c.travel(), 1.5, 0.0001)
	c.speed = -1.0
	c.tick(0.1)
	assert_almost_eq(c.travel(), fposmod(1.5 - 3.0, c.effective_pitch() * 2.0), 0.0001, "backwards wraps")
	for i in 30:
		c.tick(0.07)
		assert_true(c.travel() >= 0.0 and c.travel() < c.effective_pitch() * 2.0)


func test_open_chain_links_stay_on_path() -> void:
	var c: ScrollingChain = autofree(ScrollingChain.new())
	c.auto_process = false
	c.closed = false
	c.points = PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 10)])
	c.pitch_px = 4.0
	assert_eq(c.path_length(), 30.0)
	c.speed = 1.0
	for i in 10:
		c.tick(0.05)
		for l: Dictionary in c.links():
			assert_true(float(l["d"]) >= 0.0 and float(l["d"]) <= 30.0)
	assert_eq(c.point_at(25.0), Vector2(20, 5))


func test_chain_draws_in_tree() -> void:
	var c := ScrollingChain.new()
	c.set_loop(Vector2(10, 10), 4.0, Vector2(30, 10), 4.0)
	c.speed = 1.0
	add_child_autofree(c)
	await wait_process_frames(3)
	assert_ne(c.travel(), 0.0)
