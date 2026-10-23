extends GutTest
## Co-op scoring (brief 2.4, 2.8): Double Hookups, the hookup level, expected points, the catch
## board, and a long solo trip.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func _e2e(lanes: int) -> H:
	var h := H.new()
	h.setup("e2e_2min", lanes, 7)
	for i in lanes:
		h.follow_band[i] = true
	return h


func test_double_hookup_multipliers_by_overlapping_fights() -> void:
	for c: Array in [[2, 15], [3, 20], [4, 25]]:
		var n: int = c[0]
		var h := _e2e(n)
		assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 60.0))
		var hook_t := h.state.t
		assert_eq(h.state.hookup_level, n, "every fight is on")
		h.run(9.9)
		assert_eq(h.events_of(FishingEvents.DOUBLE_HOOKUP).size(), 0, "not before 10 s")
		h.run(0.2)
		var dh := h.events_of(FishingEvents.DOUBLE_HOOKUP)
		assert_eq(dh.size(), 1, "%d lanes: one event" % n)
		var lanes: Array[int] = []
		for i in n:
			lanes.append(i)
		assert_eq(dh[0], FishingEvents.double_hookup(lanes, n))
		assert_almost_eq(h.time_of(FishingEvents.DOUBLE_HOOKUP) - hook_t, 10.0, 0.11)
		h.run(80.0)
		var landed := h.events_of(FishingEvents.LANDED)
		assert_eq(landed.size(), n)
		var sum := 0
		for e: Dictionary in landed:
			assert_eq(int(e["hk"]), int(c[1]), "x%.1f" % (c[1] / 10.0))
			var kg := int(e["kg"]) / 10.0
			var want := roundi(20.0 * sqrt(kg)) * float(c[1]) / 10.0
			assert_almost_eq(float(int(e["points"])), want, 1.01)
			sum += int(e["points"])
		assert_eq(h.state.team_points, sum)
		assert_eq(h.state.team_fish, n)
		assert_eq(h.state.fish_started, n)
		assert_almost_eq(
			h.state.team_points / h.state.expected_points, 1.0, 0.02, "expected includes the bonus"
		)
		assert_eq(h.state.hookup_level, 0, "no fights on after the landings")


func test_a_solo_fight_scores_no_bonus() -> void:
	var h := _e2e(1)
	h.run(120.0)
	var landed := h.events_of(FishingEvents.LANDED)[0] as Dictionary
	assert_eq(int(landed["hk"]), 10)
	assert_eq(h.events_of(FishingEvents.DOUBLE_HOOKUP).size(), 0)


func test_the_catch_board_keeps_the_last_5_and_a_long_trip_runs_through() -> void:
	var probe := H.new()
	probe.content = H.load_content("free_60")
	var one: Array[FishingPlanSlot] = []
	for k in 7:
		one.append(H.make_slot(probe.content, "mackerel", k, 60.0))
	var h := H.new()
	h.setup("free_60", 1, 9, [one])
	h.follow_band[0] = true
	assert_true(h.run_until(func() -> bool: return h.finished != "", 3600.0 + 400.0))
	h.step()
	var l := h.lane()
	assert_eq(l.fish_landed, 7, "every slot caught")
	assert_eq(h.state.team_fish, 7)
	assert_eq(h.state.catches.size(), 15, "the last 5 catches")
	assert_eq(h.state.catches.slice(0, 3), [0, 0, 0] as Array[int])
	assert_eq(l.catches.size(), 7, "the lane's log keeps every catch")
	assert_eq(l.state, FishingConst.ST_HOME)
	assert_eq(h.violations, [] as Array[String])
	assert_lte(l.fight_budget_used_s, h.state.fight_budget_s, "inside the 40 % cap")


func test_hookup_overlap_needs_10_s() -> void:
	var h := _e2e(2)
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 60.0))
	h.run(5.0)
	# Lane 1's fight is cut short: lane 0's fish overlapped only 5 s.
	h.lane(1).fish.sp = FishingConst.SP_NONE
	h.run(10.0)
	assert_eq(h.lane(0).hookup_count, 1)
	assert_eq(h.events_of(FishingEvents.DOUBLE_HOOKUP).size(), 0)
	assert_eq(h.state.hookup_level, 1)
