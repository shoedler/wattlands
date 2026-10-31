extends GutTest
## SnapRenderClock: the time a view draws at, behind the newest entry by the mean spacing (BRIEF
## 5.1). The cases come from test_tank_snap_history.gd, which still runs against TankRenderClock.


class Rows:
	extends SnapHistory

	func push(t: float, v: float) -> void:
		add(t, {"v": v})


func _history(times: Array[float]) -> SnapHistory:
	var h := SnapHistory.new()
	for t in times:
		h.add(t, {})
	return h


func test_the_constants() -> void:
	assert_eq(SnapRenderClock.CLIENT_DELAY_S, 0.1)
	assert_eq(SnapRenderClock.HOST_DELAY_S, Wl.SIM_DT)
	assert_eq(SnapRenderClock.RESYNC_S, 1.5)
	assert_almost_eq(SnapRenderClock.MAX_DELAY_S, 1.4, 1e-12)
	assert_eq(SnapRenderClock.CATCHUP_TAU_S, 0.25)
	assert_eq(SnapRenderClock.new().min_delay_s, SnapRenderClock.CLIENT_DELAY_S)


func test_it_does_nothing_without_history() -> void:
	var c := SnapRenderClock.new()
	c.advance(0.016, null)
	assert_false(c.is_set(), "no history")
	c.advance(0.016, SnapHistory.new())
	assert_false(c.is_set(), "an empty history")
	assert_eq(c.render_t, 0.0)


func test_the_first_entry_places_it_behind_the_newest() -> void:
	var h := _history([0.5, 0.6])
	var c := SnapRenderClock.new()
	c.advance(0.016, h)
	assert_true(c.is_set())
	assert_almost_eq(c.render_t, 0.5, 1e-6)
	assert_almost_eq(c.delay(h), 0.1, 1e-6)


func test_the_delay_grows_with_slow_snapshots_and_is_clamped() -> void:
	var c := SnapRenderClock.new()
	assert_almost_eq(c.delay(_history([0.0, 1.0, 2.0, 3.0])), 1.0, 1e-6, "a second apart")
	assert_almost_eq(c.delay(_history([0.0, 1.45])), 1.4, 1e-6, "never over MAX_DELAY_S")
	assert_almost_eq(c.delay(_history([0.0, 0.01])), 0.1, 1e-6, "never under min_delay_s")
	assert_almost_eq(c.delay(null), 0.1, 1e-6, "a null history has no spacing")
	c.min_delay_s = SnapRenderClock.HOST_DELAY_S
	assert_almost_eq(c.delay(null), Wl.SIM_DT, 1e-6, "the host sees every 50 ms tick")


func test_it_never_passes_the_newest_and_resyncs_after_a_jump() -> void:
	var h := _history([0.5, 0.6])
	var c := SnapRenderClock.new()
	for _i in 100:
		c.advance(0.05, h)
	assert_almost_eq(c.render_t, 0.6, 1e-6, "held at the newest")
	h.add(5.0, {})
	assert_eq(h.entries.size(), 1, "a 4 s gap starts the history over")
	c.advance(0.016, h)
	assert_almost_eq(c.render_t, 4.9, 1e-6, "jumped")


func test_it_catches_up_softly_when_it_falls_behind() -> void:
	var h := _history([0.0, 0.1])
	var c := SnapRenderClock.new()
	c.advance(0.016, h)
	h.add(0.2, {})
	h.add(0.3, {})
	var before := c.render_t
	c.advance(0.016, h)
	var moved := before + 0.016
	var want := moved + (0.2 - moved) * (1.0 - exp(-0.016 / SnapRenderClock.CATCHUP_TAU_S))
	assert_almost_eq(c.render_t, want, 1e-9, "tau toward newest - delay")
	assert_gt(c.render_t - before, 0.016, "faster than real time while behind")
	assert_lt(c.render_t, 0.2, "but not past where it belongs")


func test_a_negative_delta_does_not_move_it_back() -> void:
	var h := _history([0.5, 0.6])
	var c := SnapRenderClock.new()
	c.advance(0.0, h)
	var was := c.render_t
	c.advance(-1.0, h)
	assert_eq(c.render_t, was)


func test_a_render_t_ahead_of_its_goal_runs_on_and_never_goes_back() -> void:
	var h := _history([1.0, 1.1])
	var c := SnapRenderClock.new()
	for _i in 20:
		c.advance(0.05, h)
	assert_almost_eq(c.render_t, 1.1, 1e-6, "held at the newest")
	h.add(1.15, {})
	c.advance(0.016, h)
	assert_almost_eq(c.render_t, 1.116, 1e-6, "its goal is 1.05: it runs on by one frame")


## A new session's newest entry can land less than RESYNC_S behind render_t: the plain clock follows
## it down, a never_back clock waits.
func test_only_never_back_holds_when_the_newest_falls_behind() -> void:
	var plain := SnapRenderClock.new()
	var held := SnapRenderClock.new()
	held.never_back = true
	var h := _history([5.0, 5.1])
	plain.advance(0.0, h)
	held.advance(0.0, h)
	plain.place(5.1)
	held.place(5.1)
	var late := _history([4.7, 4.8])
	plain.advance(0.016, late)
	held.advance(0.016, late)
	assert_almost_eq(plain.render_t, 4.8, 1e-6, "stops at the newest")
	assert_almost_eq(held.render_t, 5.1, 1e-6, "never back")


func test_place_sets_the_time_and_the_flag_and_reset_clears_them() -> void:
	var c := SnapRenderClock.new()
	c.place(3.25)
	assert_true(c.is_set())
	assert_eq(c.render_t, 3.25)
	c.reset()
	assert_false(c.is_set())
	assert_eq(c.render_t, 0.0)


func test_a_subclass_of_the_history_drives_it() -> void:
	var h := Rows.new()
	h.push(0.5, 1.0)
	h.push(0.6, 2.0)
	var c := SnapRenderClock.new()
	c.advance(0.016, h)
	assert_almost_eq(c.render_t, 0.5, 1e-6)
	assert_almost_eq(float(h.sample(c.render_t, "v", null, 0.0)), 1.0, 1e-6)
