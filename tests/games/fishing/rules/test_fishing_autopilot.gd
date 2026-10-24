extends GutTest
## Autopilot and bots in Free Roam (BRIEF 3.5): the strategy table, the stop it plans, the menu
## picks, the power band a bot rides, and whole sessions played with no input at all.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func _state(content: String = "roam_30") -> FishingState:
	var c := H.load_content(content)
	var p := PlayerSlot.new()
	p.peer_id = -1
	p.is_bot = true
	p.ftp = 200.0
	var players: Array[PlayerSlot] = [p]
	var strategies: Array[int] = [0]
	return FishingRules.new_state(c, players, 5, [[]], strategies)


func _zone_of(st: FishingState, x: float) -> String:
	return st.world.zone_at(x)


func test_four_strategies_each_a_row_of_the_table() -> void:
	assert_eq(FishingAutopilot.STRATEGIES, ["vibe", "small", "mixed", "big"] as Array[String])
	for id: String in FishingAutopilot.STRATEGIES:
		var row: Dictionary = FishingAutopilot.STRATEGY_TABLE[id]
		for k in ["zones", "span", "effort", "pick", "move_on_p", "reach"]:
			assert_true(row.has(k), "%s has %s" % [id, k])
		assert_between(float(row["effort"]), 0.3, 1.0, "%s drives at a sane effort" % id)


func test_each_strategy_plans_its_stop_in_its_zone() -> void:
	var want := {
		"vibe": ["shallows"], "small": ["shallows"], "mixed": ["reef"], "big": ["deep", "abyss"]
	}
	for i in FishingAutopilot.STRATEGIES.size():
		var st := _state("roam_60")
		var r := st.riders[0]
		r.strategy = i
		FishingAutopilot.plan_stop(st, r)
		var id: String = FishingAutopilot.STRATEGIES[i]
		assert_has(want[id], _zone_of(st, r.stop_x), "%s stops at %s" % [id, r.stop_x])


func test_big_falls_back_to_a_nearer_zone_in_a_short_session() -> void:
	var st := _state("roam_10")
	var r := st.riders[0]
	r.strategy = 3
	FishingAutopilot.plan_stop(st, r)
	assert_ne(_zone_of(st, r.stop_x), "deep", "the deep is out of reach in 10 minutes")


func test_wants_stop_once_past_the_stop_in_the_heading() -> void:
	var r := FishingRiderState.new()
	r.stop_x = 500.0
	r.x_m = 499.0
	assert_false(FishingAutopilot.wants_stop(r))
	r.x_m = 500.0
	assert_true(FishingAutopilot.wants_stop(r))
	r.heading = -1
	r.x_m = 600.0
	assert_false(FishingAutopilot.wants_stop(r))
	r.stop_x = NAN
	assert_false(FishingAutopilot.wants_stop(r))


func test_menu_picks_turn_at_the_edge_and_drive_on_short_of_the_stop() -> void:
	var st := _state()
	var r := st.riders[0]
	r.menu.assign([0, FishingConst.M_DRIVE_ON, FishingConst.M_TURN])
	r.hints.assign([0.0, 10.0, 3.0, 0.5])
	r.x_m = st.world.edge_x_m()
	r.stop_x = 1000.0
	assert_eq(FishingAutopilot.menu_pick(st, r, false), 2, "turn at the edge")
	r.x_m = 1000.0
	r.stop_x = 2000.0
	assert_eq(FishingAutopilot.menu_pick(st, r, false), 1, "drive on to the stop")
	r.stop_x = 1020.0
	assert_eq(FishingAutopilot.menu_pick(st, r, false), 0, "cast here")
	st.time_up = true
	assert_eq(FishingAutopilot.menu_pick(st, r, false), -1, "time is up: wait")


func test_pick_rules_choose_the_lightest_or_heaviest_fish() -> void:
	var st := _state()
	var r := st.riders[0]
	r.x_m = 1000.0
	r.hints.assign([1.0, -20.0, 5.0, 0.9, 0.0, 10.0, 4.0, 0.2, 1.0, 30.0, 6.0, 0.1])
	r.strategy = 1
	assert_eq(FishingAutopilot.best_hint(st, r), 1, "small: the mackerel")
	r.strategy = 0
	assert_eq(FishingAutopilot.best_hint(st, r), 0, "vibe: the first")
	r.strategy = 3
	r.x_m = 2500.0
	r.hints.assign([2.0, -20.0, 5.0, 0.9, 3.0, 10.0, 4.0, 0.2])
	assert_eq(FishingAutopilot.best_hint(st, r), 1, "big: the heaviest")
	r.strategy = 2
	assert_eq(FishingAutopilot.best_hint(st, r), 1, "mixed: the heaviest (mahi)")


func test_a_bot_rides_its_strategy_effort_while_driving_and_rests_otherwise() -> void:
	var r := FishingRiderState.new()
	r.strategy = 3
	r.action = FishingConst.A_DRIVE
	assert_eq(FishingAutopilot.effort_frac(r), 1.0)
	r.action = FishingConst.A_WAIT
	assert_eq(FishingAutopilot.effort_frac(r), FishingAutopilot.REST_EFFORT)
	r.action = FishingConst.A_LAND
	r.landing_t = 2.0
	assert_eq(FishingAutopilot.effort_frac(r), FishingAutopilot.SPRINT_EFFORT, "the gaff sprint")
	r.strategy = 0
	assert_eq(FishingAutopilot.effort_frac(r), FishingAutopilot.REST_EFFORT, "vibe never sprints")


func test_bots_publish_power_bands_and_humans_do_not() -> void:
	var h := H.new()
	h.setup("roam_10", 2, 3, [], 1)
	h.run(30.0)
	assert_gt(h.power_bands.size(), 0)
	for pb: Array in h.power_bands:
		assert_eq(int(pb[1]), -2, "the bot only")
		assert_almost_eq((float(pb[2]) + float(pb[3])) / 2.0, 0.85 * 220.0, 1.0, "mixed: 85 % FTP")


func test_an_autopilot_rider_never_reengages_the_prop_by_pedaling() -> void:
	var h := H.new()
	h.setup("roam_10", 1, 3, [], 1)
	h.run(5.0)
	var r := h.rider()
	r.stop_x = r.x_m
	h.step()
	assert_eq(r.action, FishingConst.A_DRIFT)
	h.run(3.0)
	assert_ne(r.action, FishingConst.A_DRIVE, "still drifting or stopped at full power")


func test_zero_input_roam_sessions_fish_with_every_strategy() -> void:
	for i in 4:
		var h := H.new()
		var strat: Array[int] = [i]
		h.setup("roam_30", 1, 20 + i, [], 1, strat)
		h.follow_band[0] = true
		h.drive_w[0] = (
			FishingAutopilot.STRATEGY_TABLE[FishingAutopilot.STRATEGIES[i]]["effort"] * 200.0
		)
		h.run(2400.0)
		var id: String = FishingAutopilot.STRATEGIES[i]
		assert_eq(h.finished, "trip_over", id)
		assert_gt(h.rider().fish_landed, 0, "%s landed fish" % id)
		assert_eq(h.violations, [] as Array[String], id)
