extends GutTest
## FishingSnapHistory (client interpolation of other lanes) and FishingView's render clock: behind
## the newest snapshot by the history's mean spacing, never past the newest, never backwards.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")


func _state_with(game: FishingGame, d: float, cad: float) -> FishingState:
	for l in game.state.lanes:
		l.fish.d = d
		l.cadence_ema = cad
	return game.state


func test_push_keeps_capacity_and_mean_spacing() -> void:
	var game: FishingGame = autofree(FX.make_game(2))
	var h := FishingSnapHistory.new()
	assert_true(h.is_empty())
	assert_eq(h.mean_spacing(), 0.0)
	for k in 12:
		h.push(0.1 * k, _state_with(game, float(k), 80.0))
	assert_eq(h.entries.size(), FishingSnapHistory.CAPACITY)
	assert_almost_eq(h.mean_spacing(), 0.1, 0.0001)
	assert_almost_eq(h.newest_t(), 1.1, 0.0001)


func test_value_at_interpolates_and_never_extrapolates() -> void:
	var game: FishingGame = autofree(FX.make_game(2))
	var h := FishingSnapHistory.new()
	h.push(1.0, _state_with(game, 10.0, 80.0))
	h.push(1.1, _state_with(game, 20.0, 90.0))
	assert_almost_eq(h.value_at(1, "d", 1.05, -1.0), 15.0, 0.001)
	assert_almost_eq(h.value_at(1, "cad", 1.075, -1.0), 87.5, 0.001)
	assert_eq(h.value_at(1, "d", 0.5, -1.0), 10.0, "before the oldest: the oldest")
	assert_eq(h.value_at(1, "d", 3.0, -1.0), 20.0, "after the newest: the newest")
	assert_eq(h.value_at(7, "d", 1.05, -1.0), -1.0, "an unknown lane: the fallback")


func test_a_gap_or_a_clock_going_back_starts_over_and_equal_times_replace() -> void:
	var game: FishingGame = autofree(FX.make_game(1))
	var h := FishingSnapHistory.new()
	h.push(1.0, _state_with(game, 1.0, 80.0))
	h.push(1.1, _state_with(game, 2.0, 80.0))
	h.push(1.1, _state_with(game, 3.0, 80.0))
	assert_eq(h.entries.size(), 2, "the same time replaces")
	assert_eq(h.value_at(0, "d", 1.1, 0.0), 3.0)
	h.push(0.5, _state_with(game, 4.0, 80.0))
	assert_eq(h.entries.size(), 1, "time went back")
	h.push(0.5 + FishingSnapHistory.MAX_GAP_S + 0.1, _state_with(game, 5.0, 80.0))
	assert_eq(h.entries.size(), 1, "a long gap")


func test_render_clock_runs_behind_the_newest_and_never_backwards() -> void:
	var game: FishingGame = autofree(FX.make_game(2, 1, Wl.CLIENT))
	var view := FX.make_view(game, self)
	autofree(view)
	var t := 10.0
	for k in 5:
		game.history.push(t + 0.1 * k, game.state)
	view.advance(0.016)
	assert_almost_eq(
		view.render_t, game.history.newest_t() - 0.1, 0.001, "starts one spacing behind"
	)
	var last := view.render_t
	var newest := game.history.newest_t()
	for f in 120:
		if f % 6 == 0:
			newest += 0.1
			game.state.t = newest
			game.history.push(newest, game.state)
		view.advance(1.0 / 60.0)
		assert_gte(view.render_t, last - 0.00001, "never backwards (frame %d)" % f)
		assert_lte(view.render_t, game.history.newest_t() + 0.00001, "never past the newest")
		last = view.render_t
	assert_between(game.history.newest_t() - view.render_t, 0.0, 0.3, "about one spacing behind")


func test_render_clock_waits_at_the_newest_when_snapshots_stop() -> void:
	var game: FishingGame = autofree(FX.make_game(2, 1, Wl.CLIENT))
	var view := FX.make_view(game, self)
	autofree(view)
	for k in 3:
		game.history.push(5.0 + 0.1 * k, game.state)
	for f in 90:
		view.advance(1.0 / 60.0)
	assert_almost_eq(view.render_t, game.history.newest_t(), 0.0001)


func test_other_lanes_draw_between_snapshots_and_the_local_lane_from_state() -> void:
	var game: FishingGame = autofree(FX.make_game(2, 1, Wl.CLIENT))
	var view := FX.make_view(game, self)
	autofree(view)
	var other := game.state.lane(0)
	FX.set_fight(other, 1, 20.0)
	FX.set_fight(game.state.lane(1), 1, 33.0)
	game.history.push(1.0, game.state)
	other.fish.d = 40.0
	game.history.push(1.1, game.state)
	view.advance(0.0)
	assert_almost_eq(
		view.lane_view(0).shown_d, 20.0, 0.001, "other lane at render_t = newest - 0.1"
	)
	view.advance(0.05)
	assert_almost_eq(view.lane_view(0).shown_d, 30.0, 0.5, "half way")
	assert_eq(view.lane_view(1).shown_d, 33.0, "the local lane uses the state")
