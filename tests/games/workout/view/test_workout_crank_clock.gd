extends GutTest
## One integrator per rider (WorkoutCrankClock), no drift at any frame rate, and the rules for
## whose cadence the legs follow (WorkoutGame.cadence_of): the sim must be alive, the rider
## connected, and a client's own legs follow its own telemetry.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const RATES: Array[float] = [30.0, 45.0, 60.0, 75.0, 90.0, 110.0, 120.0, 140.0]
const FRAME := 1.0 / 60.0


func _steps(clock: WorkoutCrankClock, rpm: float, dt: float) -> void:
	for i in roundi(60.0 / dt):
		clock.step(1, rpm, dt)


func test_a_minute_gives_exactly_the_rpm_at_every_cadence_and_frame_rate() -> void:
	for rpm in RATES:
		for dt: float in [1.0 / 60.0, 1.0 / 30.0, 1.0 / 144.0]:
			var clock := WorkoutCrankClock.new()
			_steps(clock, rpm, dt)
			assert_almost_eq(clock.revs(1), rpm, 1e-6, "%.0f rpm at %.4f s" % [rpm, dt])


func test_zero_rpm_stops_dead_in_one_step() -> void:
	var clock := WorkoutCrankClock.new()
	clock.step(1, 90.0, 1.0)
	var held := clock.revs(1)
	clock.step(1, 0.0, FRAME)
	assert_eq(clock.revs(1), held, "no easing")
	clock.step(1, -20.0, FRAME)
	assert_eq(clock.revs(1), held, "never backwards")


func test_the_frame_index_runs_up_and_wraps_once_a_revolution() -> void:
	var clock := WorkoutCrankClock.new()
	var last := WorkoutRig.crank_frame(clock.revs(1))
	var wraps := 0
	var seen := {}
	for i in 60:  # one second at 90 rpm: 1.5 revolutions
		clock.step(1, 90.0, FRAME)
		var f := WorkoutRig.crank_frame(clock.revs(1))
		assert_true(f >= 0 and f < WorkoutRig.CRANK_FRAMES)
		seen[f] = true
		if f < last:
			wraps += 1
		else:
			assert_lte(f - last, 1, "no skipped frame at 90 rpm and 60 fps")
		last = f
	assert_eq(wraps, 1)
	assert_eq(seen.size(), WorkoutRig.CRANK_FRAMES)


func test_two_peers_are_independent_and_clear_resets() -> void:
	var clock := WorkoutCrankClock.new()
	clock.step(1, 60.0, 1.0)
	clock.step(2, 120.0, 1.0)
	assert_almost_eq(clock.revs(1), 1.0, 1e-9)
	assert_almost_eq(clock.revs(2), 2.0, 1e-9)
	assert_eq(clock.revs(3), 0.0, "an unknown peer is at 0")
	clock.clear()
	assert_eq(clock.revs(1), 0.0)


func _snap(rpm: int) -> Dictionary:
	var rows: Array = []
	for peer: int in [1, 2]:
		rows.append([peer, 1000, 0, 800, 1, 900, 180, rpm, 900])
	return {"t": 100, "p": 0, "pt": 50, "r": rows}


func test_a_client_uses_its_own_cadence_only_for_the_local_rider() -> void:
	var g := U.game("easy_30", U.players(2), Wl.CLIENT, 2)
	autofree(g)
	g.apply_snapshot(_snap(70))
	assert_eq(g.cadence_of(2), 70.0, "no telemetry yet: the snapshot's")
	var t := Telemetry.new()
	t.peer_id = 2
	t.cadence_rpm = 95.0
	g.client_predict(0.05, t)
	assert_eq(g.cadence_of(2), 95.0, "the client's own legs")
	assert_eq(g.cadence_of(1), 70.0, "the others from the snapshot")
	assert_eq(g.local_tm, t)
	g.client_predict(0.05, null)
	assert_null(g.local_tm, "a null telemetry is allowed")
	assert_eq(g.cadence_of(2), 95.0, "the last one holds")


func test_the_host_uses_the_state_even_for_the_local_rider() -> void:
	var g := U.game("easy_30", U.players(1))
	autofree(g)
	g.state.rider(1).cadence_rpm = 88.0
	g.local_rpm = 40.0
	assert_eq(g.cadence_of(1), 88.0)


func test_a_quiet_sim_stops_every_rider_and_a_live_one_turns_them() -> void:
	var g := U.game("easy_30", U.players(2), Wl.CLIENT, 2)
	autofree(g)
	g.apply_snapshot(_snap(90))
	for i in 60:
		g.sim_alive()
		g.tick_cranks(FRAME)
	assert_almost_eq(g.cranks.revs(1), 1.5, 1e-6, "one second at 90 rpm")
	assert_eq(g.rider_revs(1), g.cranks.revs(1))
	assert_eq(g.rider_rpm(1), g.cadence_of(1))
	# A pause: no sim_alive. The state still says 90 rpm.
	for i in 30:
		g.tick_cranks(FRAME)
	var held := g.cranks.revs(1)
	assert_eq(g.cadence_of(1), 0.0, "quiet past SIM_ALIVE_S")
	g.tick_cranks(FRAME)
	assert_eq(g.cranks.revs(1), held, "the legs hold")
	assert_eq(g.state.rider(1).cadence_rpm, 90.0, "the state keeps the last cadence")
	g.apply_snapshot(_snap(90))
	assert_eq(g.cadence_of(1), 90.0, "a snapshot wakes it")


func test_a_disconnected_rider_holds_and_an_unknown_peer_is_still() -> void:
	var g := U.game("easy_30", U.players(2))
	autofree(g)
	g.state.rider(2).cadence_rpm = 90.0
	g.state.rider(2).connected = false
	g.sim_alive()
	assert_eq(g.cadence_of(2), 0.0)
	assert_eq(g.cadence_of(99), 0.0)
	g.tick_cranks(1.0)
	assert_eq(g.cranks.revs(2), 0.0)


func test_configure_resets_the_cranks() -> void:
	var g := U.game("easy_30", U.players(1))
	autofree(g)
	g.cranks.step(1, 60.0, 1.0)
	g.local_rpm = 90.0
	g.sim_quiet_s = 5.0
	g.configure(g.ctx)
	assert_eq(g.cranks.revs(1), 0.0)
	assert_eq(g.local_rpm, -1.0)
	assert_null(g.local_tm)
	assert_eq(g.sim_quiet_s, 0.0)


func test_the_view_steps_the_cranks_on_every_role_and_refresh_does_not() -> void:
	for role: String in [Wl.SOLO, Wl.CLIENT]:
		var g := U.game("easy_30", U.players(1), role, 1)
		autofree(g)
		g.state.rider(1).cadence_rpm = 60.0
		var view := g.make_view() as WorkoutRideView
		add_child_autofree(view)
		view.set_process(false)
		view.refresh()
		assert_eq(g.cranks.revs(1), 0.0, "%s: refresh leaves the cranks" % role)
		g.sim_alive()
		view.advance(0.1)
		assert_almost_eq(g.cranks.revs(1), 0.1, 1e-9, "%s: advance moves them" % role)


func test_events_become_cues_on_the_host_and_on_a_client() -> void:
	var host := U.game("e2e", U.players(1))
	autofree(host)
	var seen: Array[String] = []
	host.cue.connect(func(kind: String, _data: Dictionary) -> void: seen.append(kind))
	var events := U.ride(host, Callable(), 1300)
	assert_gt(events.size(), 0, "the ride has events")
	assert_eq(seen.size(), events.size(), "every event once")
	assert_true(seen.has(WorkoutRules.EV_INTERVAL_START))
	assert_not_null(host.local_tm, "the host stores the local rider's telemetry")

	var client := U.game("e2e", U.players(2), Wl.CLIENT, 2)
	autofree(client)
	var got: Array[Dictionary] = []
	client.cue.connect(
		func(kind: String, data: Dictionary) -> void: got.append({"k": kind, "d": data})
	)
	var e := {"type": WorkoutRules.EV_SPRINT, "i": 2, "r": []}
	client.apply_event(e)
	assert_eq(got.size(), 1)
	assert_eq(got[0]["k"], WorkoutRules.EV_SPRINT)
	assert_eq(got[0]["d"], e)
