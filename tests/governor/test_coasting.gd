extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.4 coasting: not_pedaling (power < 15 W and cadence < 20 rpm) timed from the
## first sample that meets it drops ERG to its floor at 3 s (+1 tick) and pauses (solo) or
## marks AFK (multiplayer) at 10 s (+1 tick); pedaling again clears it. BRIEF 7.4.


func _stop_pedaling(rig: Rig) -> float:
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = -1.0
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0
	# The next sample carries the stop; return its time.
	var before := dev.samples_sent
	while dev.samples_sent == before:
		rig.step()
	return dev.sample_times[dev.sample_times.size() - 1]


func _resume_pedaling(rig: Rig) -> float:
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = 1.0
	dev.cadence_rpm = 90.0
	var before := dev.samples_sent
	while dev.samples_sent == before:
		rig.step()
	return dev.sample_times[dev.sample_times.size() - 1]


func test_floor_within_3_s_of_the_first_not_pedaling_sample() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 160)
	var t_s := _stop_pedaling(rig)
	var reached := rig.run_until(func() -> bool: return rig.applied_w() == 60, 6.0)
	assert_gt(reached, 0.0, "reaches the floor")
	assert_lte(reached, t_s + 3.0 + DT + 1e-6, "no later than 3 s (+1 tick) after the first sample")
	assert_gte(reached, t_s + 3.0 - 1e-6, "not before 3 s")
	assert_true(rig.s()["coasting"])
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_COASTING)
	var ev := rig.events_named("coasting_changed")
	assert_eq(ev.size(), 1)
	assert_time(float(ev[0]["t"]), t_s + 3.0)


func test_pause_requested_at_10_s_solo() -> void:
	var rig := make_rig({"multiplayer": false}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(20.0)
	var t_s := _stop_pedaling(rig)
	rig.run(15.0)
	var ev := rig.events_named("pause_requested")
	assert_eq(ev.size(), 1, "emitted once")
	assert_time(float(ev[0]["t"]), t_s + 10.0, "at 10 s (+1 tick)")
	assert_eq(ev[0]["value"], "coasting")
	assert_eq(rig.events_named("afk_changed").size(), 0, "solo riders pause, never AFK")


func test_afk_at_10_s_multiplayer_and_cleared_by_pedaling() -> void:
	var rig := make_rig({"multiplayer": true}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(20.0)
	var t_s := _stop_pedaling(rig)
	rig.run(12.0)
	var ev := rig.events_named("afk_changed")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["value"], true)
	assert_time(float(ev[0]["t"]), t_s + 10.0, "AFK at 10 s (+1 tick)")
	assert_true(rig.s()["afk"])
	assert_true(rig.gov.is_afk())
	assert_eq(rig.events_named("pause_requested").size(), 0)
	var t_p := _resume_pedaling(rig)
	rig.step()
	ev = rig.events_named("afk_changed")
	assert_eq(ev.size(), 2)
	assert_eq(ev[1]["value"], false)
	assert_time(float(ev[1]["t"]), t_p, "cleared by the first pedaling sample")
	assert_false(rig.s()["coasting"])
	assert_false(rig.s()["afk"])


func test_one_pedaling_sample_restarts_the_timer() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(20.0)
	_stop_pedaling(rig)
	rig.run(1.5)
	var t_p := _resume_pedaling(rig)
	var t_s := _stop_pedaling(rig)
	assert_gt(t_s, t_p)
	rig.run(2.5)
	assert_false(rig.s()["coasting"], "the timer restarted at the second stop")
	rig.run(1.0)
	assert_true(rig.s()["coasting"])


func test_cadence_alone_keeps_a_rider_pedaling() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(5.0)
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = -1.0
	dev.power_w = 5.0
	dev.cadence_rpm = 25.0
	rig.run(15.0)
	assert_false(rig.s()["coasting"], "25 rpm is not < 20 rpm")
	dev.cadence_rpm = -1.0
	rig.run(5.0)
	assert_true(rig.s()["coasting"], "an absent cadence counts as low")


func test_coasting_in_sim_marks_afk_but_leaves_the_grade() -> void:
	var rig := make_rig({"multiplayer": true}, follower())
	rig.start([sim(Wl.GRADE_GAME, 120.0)])
	rig.gov.set_course_grade(6.0)
	rig.run(5.0)
	var grade := float(rig.s()["applied_grade_pct"])
	assert_almost_eq(grade, 3.0, 1e-6)
	_stop_pedaling(rig)
	rig.run(4.0)
	assert_true(rig.s()["coasting"])
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), grade, 1e-6, "coasting changes ERG only")
	rig.run(7.0)
	assert_true(rig.s()["afk"])


func test_no_pause_or_afk_before_a_phase_runs() -> void:
	var dev := ScriptedDevice.new()
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0
	var rig := make_rig({}, dev)
	rig.run(15.0)
	assert_true(rig.s()["coasting"])
	assert_eq(rig.events_named("pause_requested").size(), 0, "nothing to pause in the lobby")


func test_mock_trainer_zero_rider() -> void:
	var mock := MockTrainer.from_spec("zero", 200.0, {"seed": 7})
	var first := [-1.0]
	mock.sample_received.connect(func(s: TrainerSample) -> void:
		if first[0] < 0.0:
			first[0] = s.t)
	var rig := make_rig({}, mock)
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	var reached := rig.run_until(func() -> bool: return bool(rig.s()["coasting"]), 6.0)
	assert_gt(float(first[0]), 0.0)
	assert_lte(reached, float(first[0]) + 3.0 + DT + 1e-6)
	assert_eq(rig.applied_w(), 60, "the floor")
	rig.run(8.0)
	var ev := rig.events_named("pause_requested")
	assert_eq(ev.size(), 1)
	assert_lte(float(ev[0]["t"]), float(first[0]) + 10.0 + DT + 1e-6, "paused at 10 s (+1 tick)")
