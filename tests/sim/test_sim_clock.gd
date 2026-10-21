extends GutTest
## SimClock (BRIEF 3.6, 6; ARCHITECTURE "Time"): fixed 0.05 s steps, --sim-speed, the
## wall-clock accumulator, the per-frame cap and the two times (platform, game).


func test_dt_is_the_platform_step() -> void:
	assert_eq(SimClock.DT, Wl.SIM_DT)
	assert_almost_eq(SimClock.DT, 0.05, 1e-12)


func test_create_clamps_negative_speed() -> void:
	assert_eq(SimClock.create(2.5).sim_speed, 2.5)
	assert_eq(SimClock.create(-3.0).sim_speed, 0.0)
	assert_eq(SimClock.create(-3.0).advance(10.0), 0, "speed 0 never yields steps")


func test_advance_at_speed_1_gives_one_step_per_dt() -> void:
	var c := SimClock.create(1.0)
	assert_eq(c.advance(0.05), 1)
	assert_eq(c.advance(0.10), 2)
	assert_eq(c.advance(0.0), 0)
	assert_eq(c.advance(-1.0), 0, "negative wall time counts as 0")


func test_advance_at_speed_10_gives_ten_steps_per_dt() -> void:
	var c := SimClock.create(10.0)
	assert_eq(c.advance(0.05), 10)
	assert_eq(c.advance(0.5), 100)


func test_accumulator_carries_partial_steps() -> void:
	var c := SimClock.create(1.0)
	assert_eq(c.advance(0.03), 0)
	assert_eq(c.advance(0.03), 1, "0.06 s holds one step and carries 0.01 s")
	assert_eq(c.advance(0.035), 0, "0.045 s carried")
	assert_eq(c.advance(0.005), 1, "the carried 0.045 s plus 0.005 s make a step")


func test_accumulator_has_no_long_run_drift() -> void:
	for speed: float in [1.0, 10.0, 0.5]:
		var c := SimClock.create(speed)
		var total := 0
		for i in 600:  # 10 s of 60 fps frames
			total += c.advance(1.0 / 60.0)
		var expected := roundi(10.0 * speed / SimClock.DT)
		assert_between(total, expected - 1, expected, "speed %s" % speed)


func test_max_steps_per_frame_caps_and_drops_the_backlog() -> void:
	var c := SimClock.create(1.0)
	assert_eq(c.advance(1000.0), SimClock.MAX_STEPS_PER_FRAME)
	assert_eq(c.advance(0.0), 0, "the backlog beyond the cap is dropped")
	assert_eq(c.advance(0.05), 1)
	var fast := SimClock.create(1000.0)
	assert_eq(fast.advance(1.0), SimClock.MAX_STEPS_PER_FRAME, "20000 due steps capped")


func test_step_advances_both_times() -> void:
	var c := SimClock.create()
	for i in 20:
		c.step()
	assert_eq(c.platform_tick, 20)
	assert_eq(c.game_tick, 20)
	assert_almost_eq(c.platform_time(), 1.0, 1e-9)
	assert_almost_eq(c.game_time(), 1.0, 1e-9)


func test_pause_stops_game_time_but_not_platform_time() -> void:
	var c := SimClock.create()
	for i in 10:
		c.step()
	c.set_game_paused(true)
	assert_true(c.game_paused)
	for i in 40:
		c.step()
	assert_eq(c.platform_tick, 50)
	assert_eq(c.game_tick, 10)
	c.set_game_paused(false)
	for i in 5:
		c.step()
	assert_eq(c.platform_tick, 55)
	assert_eq(c.game_tick, 15)
	assert_almost_eq(c.platform_time(), 2.75, 1e-9)
	assert_almost_eq(c.game_time(), 0.75, 1e-9)


func test_pause_does_not_change_advance() -> void:
	var c := SimClock.create(1.0)
	c.set_game_paused(true)
	assert_eq(c.advance(0.2), 4, "platform steps stay due while the game is paused")


func test_reset() -> void:
	var c := SimClock.create(1.0)
	c.advance(0.03)
	c.step()
	c.set_game_paused(true)
	c.step()
	c.reset()
	assert_eq(c.platform_tick, 0)
	assert_eq(c.game_tick, 0)
	assert_false(c.game_paused)
	assert_eq(c.advance(0.03), 0, "the accumulator was cleared")
