extends GutTest
## BRIEF 5.1 on a client's ride view: the other riders are drawn between the two snapshots
## around render_t (100 ms behind the newest snapshot, never past it), the local rider from its
## own prediction blended softly toward the host's value (it snaps only past LOCAL_SNAP_M and
## never moves backwards otherwise). The host and SOLO draw the state as it is.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const FRAME := 1.0 / 60.0
const V := preload("res://src/games/workout/view/workout_ride_view.gd")

var _game: WorkoutGame = null
var _view: WorkoutRideView = null


func before_each() -> void:
	_game = U.game("easy_30", U.players(2, 1), Wl.CLIENT, 2)
	autofree(_game)
	_view = _game.make_view() as WorkoutRideView
	add_child_autofree(_view)
	# Frames come only from advance(), at known deltas.
	_view.set_process(false)


## A snapshot row: [peer, distance_dm, course_dm, speed_cm_s, flags, tib, power, cadence, itib].
static func _row(peer: int, d_m: float, v_mps: float) -> Array:
	return [peer, int(round(d_m * 10.0)), 0, int(round(v_mps * 100.0)), 1, 1000, 160, 90, 1000]


## A snapshot at host tick `tick` (0.05 s each): local rider 2 at `me`, rider 1 at `one`, the
## bot at `bot`, all with speed `v`.
static func _snap(tick: int, one: float, me: float, bot: float, v: float = 0.0) -> Dictionary:
	return {
		"t": tick,
		"p": 0,
		"pt": int(float(tick) / 2.0),
		"r": [_row(1, one, v), _row(2, me, v), _row(-1, bot, v)],
	}


func _x(peer: int) -> float:
	return float(_view.marker(peer)["x"])


func test_other_riders_are_drawn_between_two_snapshots() -> void:
	_game.apply_snapshot(_snap(20, 100.0, 100.5, 120.0))
	_game.apply_snapshot(_snap(22, 101.0, 100.5, 122.0))
	_view.advance(FRAME)
	assert_almost_eq(_view.render_t, 1.0, 1e-9, "the first frame starts 0.1 s behind the newest")
	assert_almost_eq(_view.shown_distance(1), 100.0, 1e-9, "the older snapshot at its own time")
	_view.advance(0.05)
	assert_almost_eq(_view.render_t, 1.05, 1e-9, "the midpoint of the two snapshots")
	assert_almost_eq(_view.shown_distance(1), 100.5, 1e-9, "halfway from 100 m to 101 m")
	assert_almost_eq(_view.shown_distance(-1), 121.0, 1e-9, "halfway from 120 m to 122 m")
	assert_almost_eq(_x(1), V.RIDER_X + (100.5 - 100.5) / V.MAP_M_PER_PX, 1e-6)
	assert_almost_eq(_x(-1), V.RIDER_X + (121.0 - 100.5) / V.MAP_M_PER_PX, 1e-6)
	assert_true(
		_x(1) > V.RIDER_X - 0.25 and _x(1) < V.RIDER_X + 0.25,
		"between the two snapshots' markers (199.75 and 200.25)"
	)
	assert_eq(_game.state.rider(1).distance_m(), 101.0, "the state keeps the newest snapshot")
	# Past the newest snapshot it holds there: no extrapolation.
	_view.advance(0.1)
	assert_almost_eq(_view.render_t, 1.1, 1e-9)
	assert_almost_eq(_view.shown_distance(1), 101.0, 1e-9)
	_view.advance(0.1)
	assert_almost_eq(_view.render_t, 1.1, 1e-9, "never past the newest snapshot")
	# The next snapshot arrives late: render_t goes on from where it held, without a jump.
	_game.apply_snapshot(_snap(24, 102.0, 100.5, 124.0))
	_view.advance(FRAME)
	assert_almost_eq(_view.render_t, 1.1 + FRAME, 1e-9)
	assert_almost_eq(_view.shown_distance(1), 101.0 + FRAME / 0.1, 1e-9, "a small step on")


func test_render_time_catches_up_softly_and_resyncs_after_a_gap() -> void:
	_game.apply_snapshot(_snap(20, 100.0, 100.0, 100.0))
	_view.advance(FRAME)
	assert_almost_eq(_view.render_t, 0.9, 1e-9)
	# Three snapshots arrive in one burst: render_t (0.9) is 0.15 s behind its new goal
	# (1.15 - 0.1) and closes the gap with CLOCK_CATCHUP_TAU_S, not at once.
	for tick in [21, 22, 23]:
		_game.apply_snapshot(_snap(tick, 100.0 + float(tick - 20), 100.0, 100.0))
	var before := 0.9 + FRAME
	var goal := 1.15 - V.INTERP_DELAY_S
	var expected := before + (goal - before) * (1.0 - exp(-FRAME / V.CLOCK_CATCHUP_TAU_S))
	_view.advance(FRAME)
	assert_almost_eq(_view.render_t, expected, 1e-9, "a soft catch-up")
	for i in 60:
		_view.advance(FRAME)
	assert_almost_eq(_view.render_t, 1.15, 1e-9, "caught up, and held at the newest snapshot")
	# A rejoin brings a snapshot 10 s later: past CLOCK_RESYNC_S render_t jumps, and past
	# MAX_GAP_S the history starts over, so nothing is drawn between 1.15 s and 11.15 s.
	_game.apply_snapshot(_snap(223, 300.0, 300.0, 300.0))
	_view.advance(FRAME)
	assert_almost_eq(_view.render_t, 223.0 * Wl.SIM_DT - V.INTERP_DELAY_S, 1e-9)
	assert_eq(_game.history.entries.size(), 1)
	assert_almost_eq(_view.shown_distance(1), 300.0, 1e-9, "the only entry")


func test_the_local_rider_converges_toward_the_host() -> void:
	_game.apply_snapshot(_snap(20, 50.0, 100.0, 60.0))
	_view.advance(FRAME)
	assert_eq(_view.local_d, 100.0, "the first frame starts at the state")
	# The host's value is 1 m ahead of the drawn rider (inside LOCAL_SNAP_M).
	_game.apply_snapshot(_snap(22, 50.0, 101.0, 60.0))
	var k := 1.0 - exp(-FRAME / V.LOCAL_BLEND_TAU_S)
	_view.advance(FRAME)
	assert_almost_eq(_view.local_d, 100.0 + k, 1e-9, "one frame moves 5.4% of the 1 m error")
	assert_lt(_view.local_d, 100.1, "no snap")
	assert_almost_eq(_x(2), V.RIDER_X, 1e-9, "the local marker stays under the camera")
	assert_almost_eq(_view.near_trees.world_x, _view.local_d * V.VISUAL_PX_PER_M, 1e-6)
	var last := _view.local_d
	for i in 59:
		_view.advance(FRAME)
		assert_true(_view.local_d >= last, "frame %d never moves backwards" % (i + 2))
		last = _view.local_d
	# After N = 60 frames (1 s) the error is exp(-1 / 0.3) of 1 m, 3.6 cm.
	assert_almost_eq(_view.local_d, 101.0 - exp(-60.0 * FRAME / V.LOCAL_BLEND_TAU_S), 1e-9)
	assert_lt(101.0 - _view.local_d, 0.04, "within 4 cm of the host after 60 frames")
	assert_eq(_game.state.rider(2).distance_m(), 101.0, "the view never changes the state")


func test_the_local_rider_moves_on_its_own_prediction_and_never_backwards() -> void:
	_game.apply_snapshot(_snap(20, 50.0, 100.0, 60.0, 6.0))
	_view.advance(FRAME)
	_view.advance(FRAME)
	var k := 1.0 - exp(-FRAME / V.LOCAL_BLEND_TAU_S)
	var moved := 100.0 + 6.0 * FRAME
	assert_almost_eq(
		_view.local_d,
		moved + (100.0 - moved) * k,
		1e-9,
		"moved by its predicted 6 m/s between state updates, pulled toward the state"
	)
	# A snapshot 1 m behind the drawn rider: it slows down, it does not go back.
	var at := _view.local_d
	_game.apply_snapshot(_snap(22, 50.0, at - 1.0, 60.0, 6.0))
	for i in 5:
		var prev := _view.local_d
		_view.advance(FRAME)
		var step := _view.local_d - prev
		assert_gt(step, 0.0, "frame %d still moves forward" % i)
		assert_lt(step, 6.0 * FRAME, "frame %d slower than the predicted speed" % i)
	# The state stops moving (a pause, no prediction): past LOCAL_STALE_S the rider stops too,
	# ahead of the state, and holds there instead of sliding back.
	for i in 30:
		_view.advance(FRAME)
	var held := _view.local_d
	assert_gt(held, at - 1.0, "still ahead of the state")
	for i in 30:
		_view.advance(FRAME)
	assert_eq(_view.local_d, held, "holds, never backwards")


func test_the_local_rider_snaps_past_the_threshold() -> void:
	_game.apply_snapshot(_snap(20, 50.0, 100.0, 60.0))
	_view.advance(FRAME)
	assert_eq(V.LOCAL_SNAP_M, 10.0)
	_game.apply_snapshot(_snap(22, 50.0, 100.0 + V.LOCAL_SNAP_M + 5.0, 60.0))
	_view.advance(FRAME)
	assert_eq(_view.local_d, 115.0, "a 15 m error snaps in one frame")
	# Just inside the threshold it blends.
	_game.apply_snapshot(_snap(24, 50.0, 115.0 + 9.5, 60.0))
	_view.advance(FRAME)
	var k := 1.0 - exp(-FRAME / V.LOCAL_BLEND_TAU_S)
	assert_almost_eq(_view.local_d, 115.0 + 9.5 * k, 1e-9, "a 9.5 m error blends")
	# Far behind (a rejoin to an older host value) snaps back too.
	_game.apply_snapshot(_snap(26, 50.0, 60.0, 60.0))
	_view.advance(FRAME)
	assert_eq(_view.local_d, 60.0)


func test_before_the_first_frame_a_client_draws_the_state() -> void:
	_game.apply_snapshot(_snap(20, 100.0, 100.0, 140.0))
	_game.apply_snapshot(_snap(22, 102.0, 101.0, 144.0))
	_view.refresh()
	assert_almost_eq(_x(1), V.RIDER_X + 0.5, 1e-9, "the newest snapshot, as before")
	assert_almost_eq(_x(-1), V.RIDER_X + 21.5, 1e-9)


## The host and SOLO views draw the state as it is: no render clock, no blending, a jump in
## the state shows in full on the next frame.
func test_host_and_solo_views_draw_the_state_unchanged() -> void:
	for role: String in [Wl.HOST, Wl.SOLO]:
		var g := U.game("rolling_road", U.players(2, 1), role, 1)
		autofree(g)
		U.ride(g, Callable(), 6200)
		var view := g.make_view() as WorkoutRideView
		add_child_autofree(view)
		view.set_process(false)
		for step in 3:
			view.advance(FRAME)
			var cam_d := g.state.rider(1).distance_m()
			assert_almost_eq(
				view.near_trees.world_x, cam_d * V.VISUAL_PX_PER_M, 1e-9, "%s camera" % role
			)
			for peer: int in g.state.order:
				var x := clampf(
					V.RIDER_X + (g.state.rider(peer).distance_m() - cam_d) / V.MAP_M_PER_PX,
					V.EDGE_MARGIN_LEFT,
					float(WorkoutArt.W) - V.EDGE_MARGIN_RIGHT
				)
				assert_almost_eq(
					float(view.marker(peer)["x"]),
					x,
					1e-9,
					"%s peer %d step %d" % [role, peer, step]
				)
				assert_eq(view.shown_distance(peer), g.state.rider(peer).distance_m())
			# A jump a client would blend over several frames.
			g.state.rider(1).speed.distance_m += 30.0
			g.state.rider(-1).speed.distance_m += 4.0
		assert_eq(view.render_t, 0.0, "%s runs no render clock" % role)
		assert_eq(view.local_d, 0.0, "%s blends nothing" % role)
		assert_true(g.history.is_empty(), "%s keeps no snapshot history" % role)


func test_snap_history_keeps_eight_and_interpolates() -> void:
	var h := WorkoutSnapHistory.new()
	var s := WorkoutState.create(null, U.players(1, 1))
	assert_eq(h.distance_at(1, 1.0, 7.0), 7.0, "empty: the fallback")
	for i in 10:
		s.rider(1).speed.distance_m = 10.0 * float(i)
		h.push(0.1 * float(i), s)
	assert_eq(h.entries.size(), WorkoutSnapHistory.CAPACITY, "the last 8 (0.8 s)")
	assert_almost_eq(h.newest_t(), 0.9, 1e-9)
	assert_almost_eq(h.distance_at(1, 0.55, 0.0), 55.0, 1e-9, "linear between 0.5 and 0.6")
	assert_almost_eq(h.distance_at(1, 0.0, 0.0), 20.0, 1e-9, "before the oldest: the oldest")
	assert_almost_eq(h.distance_at(1, 5.0, 0.0), 90.0, 1e-9, "after the newest: the newest")
	assert_eq(h.distance_at(3, 0.5, -1.0), -1.0, "an unknown peer: the fallback")
	s.rider(1).speed.distance_m = 95.0
	h.push(0.9, s)
	assert_eq(h.entries.size(), WorkoutSnapHistory.CAPACITY, "the same time replaces the newest")
	assert_almost_eq(h.distance_at(1, 0.9, 0.0), 95.0, 1e-9)
	h.push(0.2, s)
	assert_eq(h.entries.size(), 1, "the host's time went back: a new history")
	h.push(0.15 + WorkoutSnapHistory.MAX_GAP_S, s)
	assert_eq(h.entries.size(), 2, "a gap just under MAX_GAP_S still interpolates")
	h.push(0.3 + 2.0 * WorkoutSnapHistory.MAX_GAP_S, s)
	assert_eq(h.entries.size(), 1, "a longer gap starts over")
	h.clear()
	assert_true(h.is_empty())
