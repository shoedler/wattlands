extends GutTest
## Client interpolation: the history keyed by snapshot tick, and the render clock behind the newest
## entry by the mean spacing (brief 2.6; like WorkoutSnapHistory).

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _state(x: float, enemy_x: float = 0.0) -> TankState:
	var s := TankFixtures.state(1)
	s.hull.x_px = x
	s.enemies.clear()
	if enemy_x != 0.0:
		var e := TankEnemyState.new()
		e.id = 5
		e.code = 1
		e.x_px = enemy_x
		s.enemies.append(e)
	return s


func test_history_interpolates_linearly_and_never_extrapolates() -> void:
	var h := TankSnapHistory.new()
	h.push(100, _state(1000.0))
	h.push(102, _state(1010.0))
	assert_almost_eq(h.hull_x_at(100 * 0.05, -1.0), 1000.0, 1e-4)
	assert_almost_eq(h.hull_x_at(101 * 0.05, -1.0), 1005.0, 1e-3)
	assert_almost_eq(h.hull_x_at(102 * 0.05, -1.0), 1010.0, 1e-4)
	assert_almost_eq(h.hull_x_at(110 * 0.05, -1.0), 1010.0, 1e-4, "after the newest: the newest")
	assert_almost_eq(h.hull_x_at(50 * 0.05, -1.0), 1000.0, 1e-4, "before the oldest: the oldest")


func test_enemies_shells_and_riders_interpolate_by_id() -> void:
	var h := TankSnapHistory.new()
	var a := _state(0.0, 400.0)
	var sh := TankShellState.new()
	sh.id = 9
	sh.x = 100.0
	sh.y = 200.0
	a.shells.append(sh)
	a.riders[0].raw_w = 100.0
	a.riders[0].cadence_rpm = 60.0
	h.push(10, a)
	var b := _state(0.0, 440.0)
	var sh2 := TankShellState.new()
	sh2.id = 9
	sh2.x = 140.0
	sh2.y = 180.0
	b.shells.append(sh2)
	b.riders[0].raw_w = 200.0
	b.riders[0].cadence_rpm = 100.0
	h.push(12, b)
	var mid := 11 * Wl.SIM_DT
	assert_almost_eq(h.enemy_x_at(5, mid, -1.0), 420.0, 1e-3)
	assert_eq(h.shell_at(9, mid, Vector2.ZERO), Vector2(120, 190))
	assert_eq(h.rider_at(a.riders[0].peer, mid, Vector2.ZERO), Vector2(150, 80))
	assert_eq(h.enemy_x_at(77, mid, 123.0), 123.0, "an unknown id gets the fallback")


func test_a_new_enemy_holds_at_its_first_position() -> void:
	var h := TankSnapHistory.new()
	h.push(10, _state(0.0))
	h.push(12, _state(0.0, 500.0))
	assert_almost_eq(h.enemy_x_at(5, 10 * Wl.SIM_DT, 0.0), 500.0, 1e-3)


func test_same_tick_replaces_an_earlier_tick_or_a_gap_starts_over() -> void:
	var h := TankSnapHistory.new()
	h.push(10, _state(1.0))
	h.push(10, _state(2.0))
	assert_eq(h.entries.size(), 1)
	assert_almost_eq(h.hull_x_at(10 * Wl.SIM_DT, 0.0), 2.0, 1e-6)
	h.push(12, _state(3.0))
	h.push(5, _state(4.0))
	assert_eq(h.entries.size(), 1, "the host's clock went back: a new session")
	h.push(5 + int(TankSnapHistory.MAX_GAP_S / Wl.SIM_DT) + 4, _state(5.0))
	assert_eq(h.entries.size(), 1, "a gap over MAX_GAP_S: a rejoin")


func test_capacity_and_mean_spacing() -> void:
	var h := TankSnapHistory.new()
	assert_eq(h.mean_spacing(), 0.0)
	for i in 20:
		h.push(i * 2, _state(float(i)))
	assert_eq(h.entries.size(), TankSnapHistory.CAPACITY)
	assert_almost_eq(h.mean_spacing(), 0.1, 1e-6)
	assert_eq(h.newest_tick(), 38)
	h.clear()
	assert_true(h.is_empty())


func test_render_clock_runs_behind_the_newest_by_the_mean_spacing() -> void:
	var h := TankSnapHistory.new()
	var c := TankRenderClock.new()
	c.min_delay_s = TankRenderClock.CLIENT_DELAY_S
	c.advance(0.016, h)
	assert_false(c.is_set(), "nothing to draw yet")
	h.push(10, _state(0.0))
	h.push(12, _state(1.0))
	c.advance(0.016, h)
	assert_true(c.is_set())
	assert_almost_eq(c.render_t, 12 * Wl.SIM_DT - 0.1, 1e-6)
	assert_almost_eq(c.delay(h), 0.1, 1e-6)


func test_render_clock_delay_grows_with_slow_snapshots_and_is_clamped() -> void:
	var h := TankSnapHistory.new()
	var c := TankRenderClock.new()
	c.min_delay_s = TankRenderClock.CLIENT_DELAY_S
	for i in 4:
		h.push(i * 20, _state(float(i)))
	assert_almost_eq(c.delay(h), 1.0, 1e-6, "snapshots a second apart: a second behind")
	var slow := TankSnapHistory.new()
	slow.push(0, _state(0.0))
	slow.push(28, _state(1.0))
	assert_almost_eq(c.delay(slow), TankRenderClock.MAX_DELAY_S, 1e-6)
	var host := TankRenderClock.new()
	assert_almost_eq(host.delay(null), Wl.SIM_DT, 1e-6, "the host sees every 50 ms tick")


func test_render_clock_never_passes_the_newest_and_resyncs_after_a_jump() -> void:
	var h := TankSnapHistory.new()
	var c := TankRenderClock.new()
	c.min_delay_s = TankRenderClock.CLIENT_DELAY_S
	h.push(10, _state(0.0))
	h.push(12, _state(1.0))
	for _i in 100:
		c.advance(0.05, h)
	assert_almost_eq(c.render_t, 12 * Wl.SIM_DT, 1e-6, "held at the newest")
	h.push(100, _state(2.0))
	assert_eq(h.entries.size(), 1, "a 4 s gap starts the history over")
	c.advance(0.016, h)
	assert_almost_eq(c.render_t, 100 * Wl.SIM_DT - 0.1, 1e-6, "jumped")


func test_render_clock_catches_up_softly_when_it_falls_behind() -> void:
	var h := TankSnapHistory.new()
	var c := TankRenderClock.new()
	c.min_delay_s = TankRenderClock.CLIENT_DELAY_S
	h.push(0, _state(0.0))
	h.push(2, _state(1.0))
	c.advance(0.016, h)
	var t0 := c.render_t
	h.push(4, _state(2.0))
	h.push(6, _state(3.0))
	var before := c.render_t
	c.advance(0.016, h)
	assert_gt(c.render_t - before, 0.016, "faster than real time while behind")
	assert_lt(c.render_t, 6 * Wl.SIM_DT - 0.1 + 1e-6, "but not past where it belongs")
	assert_gt(c.render_t, t0)


func test_a_client_view_draws_the_hull_between_two_snapshots() -> void:
	var host := TankFixtures.state(2)
	var client_state := TankFixtures.state(2)
	var g := U.make_game(client_state, Wl.CLIENT, 2)
	autofree(g)
	var v := U.make_view(self, g)
	assert_eq(v.clock.min_delay_s, TankRenderClock.CLIENT_DELAY_S)
	host.hull.x_px = 3200.0
	g.apply_snapshot(TankSnapshot.encode(host))
	host.tick += 2
	host.hull.x_px = 3210.0
	g.apply_snapshot(TankSnapshot.encode(host))
	assert_eq(v.history.entries.size(), 2, "one entry per applied snapshot")
	var rear := float(TankConst.REAR_SCREEN_X)
	var seen: Array[float] = []
	for _i in 12:
		v.advance(0.016)
		seen.append(v.cam_x)
	assert_gte(seen[0], 3200.0 - rear - 0.2)
	for i in range(1, seen.size()):
		assert_gte(seen[i], seen[i - 1] - 1e-6, "the camera never runs backwards")
	assert_lte(seen[seen.size() - 1], 3210.0 - rear + 1e-3, "and never passes the newest snapshot")


func test_the_host_view_records_every_sim_tick_it_sees() -> void:
	var s := TankFixtures.state(1)
	var v := U.view_of(self, s)
	assert_eq(v.clock.min_delay_s, TankRenderClock.HOST_DELAY_S)
	for _i in 5:
		s.tick += 1
		s.hull.x_px += 3.0
		v.advance(1.0 / 60.0)
	assert_eq(v.history.entries.size(), 6)
	assert_eq(v.history.newest_tick(), s.tick)
