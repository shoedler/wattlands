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


# ------------------------------------------------- not_pedaling edges (BRIEF 3.5, strict <)


## The rider holds `power` W (unrounded) and `cadence` rpm (-1: no cadence) from the next sample
## on; returns that sample's time.
func _hold(rig: Rig, power: float, cadence: float) -> float:
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = -1.0
	dev.round_power = false
	dev.power_w = power
	dev.cadence_rpm = cadence
	var before := dev.samples_sent
	while dev.samples_sent == before:
		rig.step()
	return dev.sample_times[dev.sample_times.size() - 1]


## A solo rig in a 50% ERG phase (below rescue's 60% arming, so only coasting reacts), 5 s in.
func _edge_rig() -> Rig:
	var rig := make_rig({"multiplayer": false}, follower())
	rig.start([erg(Wl.WORK, 50.0, 120.0)])
	rig.run(5.0)
	return rig


func test_the_shared_detector_thresholds_are_15_w_and_20_rpm() -> void:
	assert_eq(GestureRecognizer.NOT_PEDALING_W, 15.0)
	assert_eq(GestureRecognizer.NOT_PEDALING_RPM, 20.0)
	assert_eq(SafetyGovernor.NOT_PEDALING_W, 15.0, "an alias of the shared threshold")
	assert_eq(SafetyGovernor.NOT_PEDALING_RPM, 20.0, "an alias of the shared threshold")
	assert_eq(CadenceEstimator.COAST_POWER_W, 15.0, "the shared power threshold")


func test_game_host_rejoin_check_matches_the_shared_thresholds() -> void:
	# GameHost (sdk-runtime) still writes 15 W and 20 rpm for its rejoin "shows pedaling"
	# check. Until it calls GestureRecognizer.is_not_pedaling, its numbers must match; read
	# by name, so this keeps passing once the lead removes them.
	var script := load("res://addons/wattlands/sdk/game_host.gd") as Script
	assert_not_null(script, "GameHost script loads")
	if script == null:
		return
	var consts := script.get_script_constant_map()
	if consts.has("PEDAL_POWER_W"):
		assert_eq(float(consts["PEDAL_POWER_W"]), GestureRecognizer.NOT_PEDALING_W)
	if consts.has("PEDAL_CADENCE_RPM"):
		assert_eq(float(consts["PEDAL_CADENCE_RPM"]), GestureRecognizer.NOT_PEDALING_RPM)


func test_the_governor_calls_the_shared_detector() -> void:
	# BRIEF 3.5: one detector drives coast, stop_5s and 4.6.4. The governor keeps no copy.
	var path := "res://addons/wattlands/trainer/control/safety_governor.gd"
	var src := FileAccess.get_file_as_string(path)
	assert_gt(src.length(), 0, "governor source readable")
	assert_string_contains(src, "GestureRecognizer.is_not_pedaling(")
	var own := RegEx.create_from_string("<\\s*NOT_PEDALING_(W|RPM)\\b")
	assert_null(own.search(src), "no comparison against its own not_pedaling thresholds")


func test_exactly_15_w_is_pedaling() -> void:
	for cadence: float in [0.0, 19.99, -1.0]:
		var rig := _edge_rig()
		_hold(rig, 15.0, cadence)
		rig.run(12.0)
		assert_false(rig.s()["coasting"], "15 W is not < 15 W (cadence %s)" % cadence)
		assert_eq(rig.events_named("coasting_changed").size(), 0, "cadence %s" % cadence)
		assert_eq(rig.events_named("pause_requested").size(), 0, "cadence %s" % cadence)


func test_exactly_20_rpm_is_pedaling() -> void:
	for power: float in [0.0, 14.99]:
		var rig := _edge_rig()
		_hold(rig, power, 20.0)
		rig.run(12.0)
		assert_false(rig.s()["coasting"], "20 rpm is not < 20 rpm (%s W)" % power)
		assert_eq(rig.events_named("coasting_changed").size(), 0, "%s W" % power)
		assert_eq(rig.events_named("pause_requested").size(), 0, "%s W" % power)


func test_just_under_both_edges_coasts_at_3_s_and_pauses_at_10_s() -> void:
	for cadence: float in [19.99, -1.0]:
		var rig := _edge_rig()
		var t_s := _hold(rig, 14.99, cadence)
		rig.run_until(func() -> bool: return rig.t >= t_s + 2.95 - 1e-6, 5.0)
		assert_false(rig.s()["coasting"], "not before 3 s (cadence %s)" % cadence)
		rig.step()
		assert_true(rig.s()["coasting"], "14.99 W, cadence %s: coasting at 3 s" % cadence)
		assert_has(rig.s()["clamped_by"], Wl.CLAMP_COASTING)
		var ev := rig.events_named("coasting_changed")
		assert_eq(ev.size(), 1)
		assert_time(float(ev[0]["t"]), t_s + 3.0)
		rig.run(8.0)
		var pause := rig.events_named("pause_requested")
		assert_eq(pause.size(), 1, "cadence %s" % cadence)
		assert_time(float(pause[0]["t"]), t_s + 10.0, "pause at 10 s (cadence %s)" % cadence)


func test_governor_and_gesture_recognizer_agree_at_the_edges() -> void:
	# One detector: the governor's coasting and the GestureRecognizer's not_pedaling state come
	# out the same for every edge value (-1: no cadence).
	var cases := [
		[14.99, 19.99],
		[15.0, 19.99],
		[14.99, 20.0],
		[15.0, 20.0],
		[0.0, 0.0],
		[14.99, -1.0],
		[15.0, -1.0],
		[0.0, 45.0],
		[200.0, 0.0],
	]
	for c: Array in cases:
		var power := float(c[0])
		var cadence := float(c[1])
		var rig := _edge_rig()
		var g := GestureRecognizer.new()
		g.configure(200.0, true)
		rig.device.sample_received.connect(g.on_sample)
		_hold(rig, power, cadence)
		rig.run(4.0)
		var expect := GestureRecognizer.is_not_pedaling(power, cadence)
		var label := "%s W, %s rpm" % [power, cadence]
		assert_eq(g.not_pedaling(), expect, "recognizer: " + label)
		assert_eq(bool(rig.s()["coasting"]), expect, "governor: " + label)


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
	mock.sample_received.connect(
		func(s: TrainerSample) -> void:
			if first[0] < 0.0:
				first[0] = s.t
	)
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
