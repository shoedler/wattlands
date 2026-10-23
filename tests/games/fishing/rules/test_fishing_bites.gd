extends GutTest
## Spots and bites (brief 2.4, 4.1): hints, the seeded hazard, R_min, forced bites, Frenzy, last
## call with the 40 % and 25 % caps, and Autopilot's pick.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func _free(trip: String, species: Array, t_noms: Array, lanes: int = 1, seed: int = 3) -> H:
	var probe := H.new()
	probe.content = H.load_content(trip)
	var ls: Array = []
	for _i in lanes:
		var one: Array[FishingPlanSlot] = []
		for k in species.size():
			one.append(H.make_slot(probe.content, species[k], k, t_noms[k]))
		ls.append(one)
	var h := H.new()
	h.setup(trip, lanes, seed, ls)
	for i in lanes:
		h.follow_band[i] = true
	return h


func _reel_start(h: H) -> float:
	assert_true(
		h.run_until(func() -> bool: return h.lane().state == FishingConst.ST_CAST, 400.0),
		"the first cast"
	)
	return h.state.t


func test_each_cast_shows_3_distinct_spot_types_at_40_to_80_m() -> void:
	var h := _free("free_30", ["tuna"], [300.0])
	_reel_start(h)
	var l := h.lane()
	assert_eq(l.hint_count(), 3)
	var types: Array = []
	var last_d := 0.0
	for i in 3:
		var st := int(l.hints[3 * i])
		var d := l.hints[3 * i + 1]
		var s := l.hints[3 * i + 2]
		assert_false(types.has(st), "distinct spot types")
		types.append(st)
		assert_between(d, 40.0, 80.0)
		assert_gte(d, last_d, "sorted by distance")
		last_d = d
		var aff := h.content.affinity(st, FishingConst.species_index("tuna"))
		assert_between(s, 0.7 * aff - 0.0001, aff + 0.0001, "affinity x U[0.7, 1]")


func test_autopilot_picks_the_strongest_hint_and_the_nearest_on_ties() -> void:
	var hints: Array[float] = [0.0, 60.0, 0.5, 1.0, 50.0, 0.9, 2.0, 70.0, 0.3]
	assert_eq(FishingAutopilot.pick(hints), 1)
	var tie: Array[float] = [0.0, 60.0, 0.9, 1.0, 50.0, 0.5, 2.0, 45.0, 0.9]
	assert_eq(FishingAutopilot.pick(tie), 2, "nearest of the strongest")
	assert_eq(FishingAutopilot.pick([] as Array[float]), -1)
	var h := _free("free_30", ["mahi"], [150.0])
	_reel_start(h)
	var cast := h.events_of(FishingEvents.CAST)[0] as Dictionary
	assert_eq(int(cast["spot"]), FishingAutopilot.pick(h.lane().hints), "the rules cast its pick")
	assert_eq(int(cast["st"]), int(h.lane().hints[3 * int(cast["spot"])]))


func test_hazard_follows_strength_band_frenzy_and_staggers() -> void:
	var h := _free("free_30", ["mahi"], [150.0])
	_reel_start(h)
	var l := h.lane()
	l.reel_t = 130.0
	l.spot_strength = 0.8
	l.in_band = true
	var base := (0.35 + 0.65 * 0.8) / 90.0
	assert_almost_eq(FishingRules.bite_hazard(h.state, l), base, 1e-9)
	l.in_band = false
	assert_almost_eq(FishingRules.bite_hazard(h.state, l), base / 4.0, 1e-9, "a quarter outside")
	l.frenzy_until_t = h.state.t + 10.0
	assert_almost_eq(FishingRules.bite_hazard(h.state, l), base / 2.0, 1e-9, "doubled in a Frenzy")
	l.staggered = true
	assert_eq(FishingRules.bite_hazard(h.state, l), 0.0, "0 in rescue or AFK")
	l.staggered = false
	l.reel_t = 119.0
	assert_eq(FishingRules.bite_hazard(h.state, l), 0.0, "0 before R_min")


func test_bites_are_seeded_and_come_between_r_min_and_the_forced_bite() -> void:
	var times := {}
	for seed in range(1, 9):
		var a := _free("free_30", ["mahi"], [150.0], 1, seed)
		var b := _free("free_30", ["mahi"], [150.0], 1, seed)
		var starts: Array[float] = []
		var bites: Array[float] = []
		for h: H in [a, b]:
			starts.append(_reel_start(h))
			assert_true(
				h.run_until(
					func() -> bool: return h.events_of(FishingEvents.BITE).size() > 0, 400.0
				)
			)
			bites.append(h.time_of(FishingEvents.BITE))
		assert_eq(bites[0], bites[1], "seed %d: the same bite" % seed)
		var wait := bites[0] - starts[0]
		assert_between(wait, 120.0, 120.0 + 240.0 + 1.6, "seed %d" % seed)
		times[snappedf(wait, 0.05)] = true
	assert_gt(times.size(), 3, "seeds give different bites")


func test_a_bite_is_forced_at_r_min_plus_240_s() -> void:
	var forced := 0
	for seed in range(1, 11):
		var h := _free("free_30", ["mackerel"], [80.0], 1, seed)
		h.follow_band[0] = false
		h.cadence[0] = 70.0  # out of the lure band [92, 108]: a quarter of the hazard
		var t0 := _reel_start(h)
		assert_true(
			h.run_until(func() -> bool: return h.events_of(FishingEvents.BITE).size() > 0, 400.0)
		)
		var wait := h.time_of(FishingEvents.BITE) - t0
		assert_lte(wait, 360.0 + 1.6, "seed %d" % seed)
		if wait >= 360.0 - 0.06:
			forced += 1
	assert_gt(forced, 0, "some seeds reach the forced bite")


func test_r_min_is_k_times_the_previous_fight_with_its_landing() -> void:
	for c: Array in [["free_30", 1.5], ["base_60", 3.0]]:
		var h := _free(c[0], ["mackerel", "mackerel"], [90.0, 90.0])
		var l := h.lane()
		assert_true(
			h.run_until(func() -> bool: return l.fights_started == 1 and not l.in_fight(), 1500.0)
		)
		var reel2 := h.state.t
		assert_almost_eq(l.last_fight_len_s, l.fight_t + 30.0, 0.11)
		assert_almost_eq(l.r_min_s, maxf(120.0, float(c[1]) * l.last_fight_len_s), 0.001, c[0])
		assert_true(
			h.run_until(func() -> bool: return h.events_of(FishingEvents.BITE).size() > 1, 1500.0)
		)
		assert_gte(h.time_of(FishingEvents.BITE, -1, 1) - reel2, l.r_min_s - 0.06, c[0])


func test_a_hookup_starts_a_frenzy_for_the_other_riders() -> void:
	var h := _free("free_30", ["mackerel"], [80.0], 2, 4)
	assert_true(
		h.run_until(func() -> bool: return h.events_of(FishingEvents.HOOKUP).size() > 0, 700.0)
	)
	var hk := h.events_of(FishingEvents.HOOKUP)[0] as Dictionary
	var first := int(hk["l"])
	var other := h.lane(1 - first)
	assert_almost_eq(other.frenzy_until_t, h.state.t + 60.0, 0.001)
	if other.state >= FishingConst.ST_PICK and other.state <= FishingConst.ST_REEL:
		var fr := h.events_of(FishingEvents.FRENZY)
		assert_eq(fr.size(), 1)
		assert_eq(fr[0], FishingEvents.frenzy(first))
		var doubled := FishingRules.bite_hazard(h.state, other)
		other.frenzy_until_t = 0.0
		assert_almost_eq(doubled, 2.0 * FishingRules.bite_hazard(h.state, other), 1e-9)
	else:
		assert_eq(other.state, FishingConst.ST_STRIKE, "the other lane had a bite of its own")


func test_scheduled_trips_and_solo_rides_have_no_frenzy() -> void:
	var e2e := H.new()
	e2e.setup("e2e_2min", 3, 7)
	e2e.run(100.0)
	assert_eq(e2e.events_of(FishingEvents.HOOKUP).size(), 3)
	assert_eq(e2e.events_of(FishingEvents.FRENZY).size(), 0)
	var solo := _free("free_30", ["mackerel"], [80.0])
	assert_true(
		solo.run_until(
			func() -> bool: return solo.events_of(FishingEvents.HOOKUP).size() > 0, 700.0
		)
	)
	assert_eq(solo.events_of(FishingEvents.FRENZY).size(), 0)


func test_last_call_blocks_by_overrun_and_by_the_40_and_25_percent_caps() -> void:
	var free := _free("free_30", ["tuna"], [300.0])
	var st := free.state
	var l := free.lane()
	assert_almost_eq(st.fight_budget_s, 0.4 * 1320.0, 0.001, "40 % of fishing time")
	var tuna := l.slots[0]
	var end := st.fishing_end_t
	assert_false(FishingRules.last_call_blocks(st, l, tuna, end - 271.0), "540 + 30 fits")
	assert_true(FishingRules.last_call_blocks(st, l, tuna, end - 269.0), "ends > 5 min late")
	l.fight_budget_used_s = 528.0 - 330.0
	assert_false(FishingRules.last_call_blocks(st, l, tuna, 400.0), "used + 330 = 528")
	l.fight_budget_used_s += 1.0
	assert_true(FishingRules.last_call_blocks(st, l, tuna, 400.0), "used + 330 > 528")
	var base := _free("base_60", ["mahi"], [200.0])
	assert_almost_eq(base.state.fight_budget_s, 0.25 * 3120.0, 0.001, "25 % in Base")
	var bl := base.lane()
	bl.fight_budget_used_s = 780.0 - 230.0
	assert_false(FishingRules.last_call_blocks(base.state, bl, bl.slots[0], 400.0))
	bl.fight_budget_used_s += 0.5
	assert_true(FishingRules.last_call_blocks(base.state, bl, bl.slots[0], 400.0))


func test_a_blocked_lane_reels_out_quietly() -> void:
	var cap := _free("free_30", ["tuna"], [300.0])
	cap.lane().fight_budget_used_s = 300.0
	cap.run(900.0)
	assert_eq(cap.lane().state, FishingConst.ST_IDLE, "the fight budget is spent")
	assert_eq(cap.events_of(FishingEvents.BITE).size(), 0)
	var late := _free("free_30", ["tuna"], [300.0])
	late.state.fishing_end_t = 300.0 + 220.0
	late.state.overrun_end_t = late.state.fishing_end_t + 300.0
	late.run(310.0)
	assert_eq(late.lane().state, FishingConst.ST_IDLE, "a tuna would end too late")
	late.run(590.0)
	assert_eq(late.events_of(FishingEvents.BITE).size(), 0)
	assert_eq(late.finished, "trip_over")


func test_no_bites_while_staggered() -> void:
	var h := _free("free_30", ["mahi"], [150.0])
	_reel_start(h)
	h.rescue[0] = true
	h.run(500.0)
	assert_eq(h.events_of(FishingEvents.BITE).size(), 0, "not even the forced bite")
	h.rescue[0] = false
	var t_end := h.state.t
	assert_true(
		h.run_until(func() -> bool: return h.events_of(FishingEvents.BITE).size() > 0, 15.0),
		"the overdue forced bite comes once play resumes"
	)
	assert_gte(h.time_of(FishingEvents.BITE) - t_end, 10.0 - 0.06, "10 s after the rescue")
