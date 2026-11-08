extends GutTest
## Free Roam's flow: drive, drift, the menu, the cast, the wait, the bite that replans the rest of
## the plan, the fight and landing, back to the menu; turning, the edge, the course grade, time-up
## and the overtime.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


## A human in roam_10 (no Autopilot), driving at `drive_w`.
func _human(drive_w: float = 200.0, content: String = "roam_10") -> H:
	var h := H.new()
	h.setup(content, 1, 3)
	h.drive_w[0] = drive_w
	h.follow_band[0] = true
	return h


## Drives out to `x`, then stops pedaling until the menu opens.
func _stop_at(h: H, x: float) -> void:
	assert_true(h.run_until(func() -> bool: return h.rider().x_m >= x, 900.0), "drove to %s" % x)
	h.drive_w[0] = 20.0
	assert_true(h.run_to_action(0, FishingConst.A_MENU, 60.0), "the menu opens")


## Picks menu entry `item` with left/right and confirm.
func _pick(h: H, item: int) -> void:
	var r := h.rider()
	var want := r.menu.find(item)
	assert_gte(want, 0, "item %d is in the menu" % item)
	while r.selected != want:
		h.send(0, FishingIntents.spot(1))
		h.step()
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_ACTION))
	h.step()


func test_the_session_starts_with_a_drive_out_and_every_boat_at_the_dock() -> void:
	var h := H.new()
	h.setup("roam_30", 3, 1)
	assert_eq(h.violations, [] as Array[String], "the roam plans validate without warnings")
	assert_eq(h.phase(0).kind, Wl.WARMUP)
	assert_eq(h.phase(0).grade_source, Wl.GRADE_GAME)
	h.step()
	for i in 3:
		assert_eq(h.rider(i).action, FishingConst.A_DRIVE)
		assert_almost_eq(h.rider(i).x_m, FishingRules.start_x(i), 0.5)
	assert_eq(h.state.play_end_t, 1800.0)
	assert_eq(h.state.overtime_end_t, 2100.0)


func test_every_slot_has_its_own_berth_at_the_dock() -> void:
	for i in 4:
		assert_eq(FishingRules.start_x(i), FishingRules.start_x(i), "deterministic")
		assert_lt(FishingRules.start_x(i), 300.0, "inside the harbour")
		if i > 0:
			var gap := FishingRules.start_x(i) - FishingRules.start_x(i - 1)
			assert_between(gap, 40.0, 45.0, "a berth apart, clear of the boat ahead")


func test_pedaling_drives_and_easing_off_drifts_to_the_menu() -> void:
	var h := _human()
	h.run(150.0)
	var r := h.rider()
	assert_eq(r.action, FishingConst.A_DRIVE)
	assert_gt(r.v_mps, 4.0, "200 W at FTP 200 is 250 W of P_eff")
	h.drive_w[0] = 30.0  # under 20 % FTP-equivalent
	h.step()
	assert_eq(r.action, FishingConst.A_DRIFT)
	assert_true(h.run_to_action(0, FishingConst.A_MENU, 30.0), "stopped within 30 s")
	assert_eq(r.menu.slice(r.menu.size() - 2), [FishingConst.M_DRIVE_ON, FishingConst.M_TURN])
	assert_eq(r.hint_count(), FishingConst.HINTS_PER_STOP, "shallows fish on offer")


func test_pedaling_again_while_drifting_engages_the_prop() -> void:
	var h := _human()
	h.run(30.0)
	h.drive_w[0] = 0.0
	h.step()
	assert_eq(h.rider().action, FishingConst.A_DRIFT)
	h.drive_w[0] = 150.0
	h.step()
	assert_eq(h.rider().action, FishingConst.A_DRIVE)


func test_casting_dives_the_wobbler_to_the_fish_then_waits() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	var r := h.rider()
	var sp := int(r.hints[0])
	var depth := r.hints[2]
	_pick(h, 0)
	assert_eq(r.action, FishingConst.A_CAST)
	assert_eq(r.target_sp, sp)
	var cast := h.events_of(FishingEvents.CAST)[0] as Dictionary
	assert_eq(int(cast["sp"]), sp)
	assert_eq(int(cast["z"]), roundi(depth * 10.0))
	assert_almost_eq(r.cast_s, minf(1.5 + depth / 60.0, 8.0), 1e-6)
	assert_true(h.run_to_action(0, FishingConst.A_WAIT, 10.0))
	h.step()
	assert_almost_eq(r.lure_depth, depth, 1e-6, "at depth")
	assert_gt(r.pub_hi, 0, "the lure band is up")


func test_confirm_while_waiting_reels_in_to_the_menu() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	_pick(h, 0)
	assert_true(h.run_to_action(0, FishingConst.A_WAIT, 10.0))
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_ACTION))
	h.step()
	assert_eq(h.rider().action, FishingConst.A_MENU)
	assert_eq(h.rider().lure_depth, 0.0)
	assert_eq([h.rider().pub_lo, h.rider().pub_hi], [0, 0], "the band clears")


func test_no_bite_in_the_drive_out() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	_pick(h, 0)
	h.run(300.0 - h.state.t - 5.0)
	assert_lt(h.state.t, FishingConst.WARMUP_S)
	assert_eq(h.rider().action, FishingConst.A_WAIT, "still waiting in the warm-up")
	assert_eq(h.events_of(FishingEvents.BITE).size(), 0)


func test_a_bite_replans_fight_landing_roam_and_ends_the_roam_phase() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	_pick(h, 0)
	assert_true(h.run_to_phase(0, Wl.WORK, 400.0, Wl.ERG), "the fight phase starts")
	assert_eq(h.violations, [] as Array[String], "the replan validated without warnings")
	assert_eq(h.replans.size(), 1)
	var plan: EffortPlan = h.replans[0][2]
	assert_eq(
		plan.phases.map(func(p: PlanPhase) -> String: return p.kind + p.mode),
		["WORKERG", "WORKSIM", "FREESIM"]
	)
	var bite_t := h.time_of(FishingEvents.BITE)
	assert_gte(bite_t, FishingConst.WARMUP_S + FishingConst.ROAM_MIN_S)
	assert_eq(h.ended.size(), 1, "end_phase for the Roam phase")
	assert_eq(h.rider().action, FishingConst.A_FIGHT)
	assert_eq(h.events_of(FishingEvents.HOOKUP).size(), 1)
	var slot := h.rider().slots[0]
	assert_eq(slot.sp, h.rider().fish.sp)
	assert_almost_eq(h.rider().fish.hook_depth_m, slot.depth_m, 1e-6)


func test_after_the_landing_the_menu_offers_fresh_fish_at_the_same_spot() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	var x := h.rider().x_m
	_pick(h, 0)
	assert_true(h.run_to_action(0, FishingConst.A_LAND, 900.0))
	assert_true(h.run_to_action(0, FishingConst.A_MENU, 40.0))
	assert_eq(h.events_of(FishingEvents.LANDED).size(), 1)
	assert_almost_eq(h.rider().x_m, x, 15.0, "the boat stayed put")
	assert_eq(h.rider().hint_count(), FishingConst.HINTS_PER_STOP)
	assert_eq(h.phase(0).kind, Wl.FREE)
	assert_true(h.rider().just_landed)


func test_drive_on_and_turn_around() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	h.drive_w[0] = 200.0
	_pick(h, FishingConst.M_DRIVE_ON)
	assert_eq(h.rider().action, FishingConst.A_DRIVE)
	assert_eq(h.rider().menu, [] as Array[int])
	h.drive_w[0] = 0.0
	assert_true(h.run_to_action(0, FishingConst.A_MENU, 30.0))
	h.drive_w[0] = 200.0
	_pick(h, FishingConst.M_TURN)
	assert_eq(h.rider().heading, -1)
	assert_eq(h.events_of(FishingEvents.TURN)[0], FishingEvents.turn(0, -1))
	h.run(10.0)
	assert_lt(h.rider().v_mps, -1.0, "heading home")


func test_pedaling_hard_from_a_stop_drives_on() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	h.drive_w[0] = 0.85 * h.players[0].ftp  # 85 % FTP-equivalent
	h.run(FishingConst.DRIVE_ON_S + 0.1)
	assert_eq(h.rider().action, FishingConst.A_DRIVE)


func test_pedaling_easy_in_the_menu_keeps_the_boat_stopped() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	h.drive_w[0] = 0.6 * h.players[0].ftp
	h.run(10.0)
	assert_eq(h.rider().action, FishingConst.A_MENU)
	assert_lt(absf(h.rider().v_mps), FishingConst.STOP_SPEED)


func test_driving_into_the_dock_wall_opens_the_menu() -> void:
	var h := _human()
	_stop_at(h, 400.0)
	h.drive_w[0] = 200.0
	_pick(h, FishingConst.M_TURN)
	assert_true(h.run_to_action(0, FishingConst.A_MENU, 200.0))
	assert_eq(h.rider().x_m, 0.0)


func test_the_course_grade_follows_the_speed_while_driving_and_is_0_when_stopped() -> void:
	var h := _human()
	h.run(60.0)
	assert_eq(h.violations, [] as Array[String], "grades only in game phases")
	var last: Array = h.grades.back()
	var r := h.rider()
	assert_almost_eq(float(last[2]), snappedf(FishingBoat.grade_for(r.v_mps, r.plane), 0.1), 0.11)
	for g: Array in h.grades:
		assert_between(float(g[2]), 0.0, FishingConst.GRADE_MAX_PCT)
	for k in range(1, h.grades.size()):
		var dt := float(h.grades[k][0]) - float(h.grades[k - 1][0])
		assert_gte(dt, 0.5 - 1e-6, "at most twice a second")
	h.drive_w[0] = 0.0
	h.run(20.0)
	assert_eq(float(h.grades.back()[2]), 0.0, "no load while drifting or stopped")


func test_time_up_brings_the_lines_in_and_ends_the_session() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	_pick(h, 0)
	h.rider().wait_t = -100000.0  # this fish never bites
	assert_true(h.run_until(func() -> bool: return h.state.time_up, 700.0))
	assert_eq(h.rider().action, FishingConst.A_MENU, "the line came in")
	assert_eq(h.rider().menu, [FishingConst.M_DRIVE_ON, FishingConst.M_TURN], "no fish offered")
	assert_eq(h.finished, "trip_over")
	assert_eq(h.events_of(FishingEvents.TIME_UP).size(), 1)
	assert_eq(h.events_of(FishingEvents.TRIP_OVER).size(), 1)


func test_a_fight_on_at_time_up_may_finish_first() -> void:
	var h := _human()
	h.drive_w[0] = 220.0
	_stop_at(h, 800.0)
	_pick(h, 0)
	assert_true(h.run_to_action(0, FishingConst.A_FIGHT, 400.0))
	h.state.play_end_t = h.state.t + 1.0
	h.state.overtime_end_t = h.state.play_end_t + FishingConst.OVERTIME_S
	h.run(2.0)
	assert_true(h.state.time_up)
	assert_eq(h.finished, "", "the fight goes on")
	assert_true(h.run_until(func() -> bool: return h.finished != "", 400.0))
	assert_eq(h.events_of(FishingEvents.LANDED).size(), 1, "landed in overtime")
	assert_eq(h.finished_count, 1)


func test_the_overtime_ends_after_5_minutes_whatever_is_on() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	_pick(h, 0)
	assert_true(h.run_to_action(0, FishingConst.A_FIGHT, 400.0))
	h.cadence[0] = 40.0
	h.follow_band[0] = false
	h.state.play_end_t = h.state.t
	h.state.overtime_end_t = h.state.t + 10.0
	h.run(10.5)
	assert_eq(h.finished, "trip_over")
	assert_eq(h.rider().action, FishingConst.A_HOME)
	assert_eq(h.rider().heading, -1, "everyone heads for the dock")


func test_the_lure_is_jigged_home_and_recast_while_waiting() -> void:
	var h := _human()
	_stop_at(h, 800.0)
	_pick(h, 0)
	assert_true(h.run_to_action(0, FishingConst.A_WAIT, 10.0))
	var r := h.rider()
	var dx0 := r.jig_dx0
	assert_almost_eq(r.lure_dx, dx0, absf(dx0) * 0.05, "the lure starts out at the hint")
	r.wait_t = -100000.0  # this fish never bites
	h.run(FishingConst.JIG_HOME_S / 2.0)
	assert_lt(absf(r.lure_dx), absf(dx0) * 0.6, "on its way home")
	assert_true(h.run_to_action(0, FishingConst.A_CAST, FishingConst.JIG_HOME_S), "recast")
	assert_eq(h.events_of(FishingEvents.CAST).size(), 2, "the first cast and the recast")
	assert_almost_eq(r.lure_dx, dx0, 1e-6)
	assert_true(h.run_to_action(0, FishingConst.A_WAIT, 10.0))
	assert_eq(h.replans.size(), 0, "no replan: the jig is SIM")
