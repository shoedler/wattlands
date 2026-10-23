extends GutTest
## FishingRules end to end through the harness's phase clock: the e2e mackerel, the ride out,
## idle reels, the cool-down, trip_over timing and determinism.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func _h(content_id: String, lanes: int = 1, seed: int = 7, lane_slots: Array = []) -> H:
	var h := H.new()
	h.setup(content_id, lanes, seed, lane_slots)
	return h


## Free trip slots: `species` ids with T_nom each.
func _slots(h: H, species: Array, t_noms: Array) -> Array[FishingPlanSlot]:
	var out: Array[FishingPlanSlot] = []
	for i in species.size():
		out.append(H.make_slot(h.content, species[i], i, t_noms[i]))
	return out


func _free(content_id: String, lanes: int, species: Array, t_noms: Array, seed: int = 7) -> H:
	var probe := H.new()
	probe.content = H.load_content(content_id)
	var ls: Array = []
	for _i in lanes:
		ls.append(_slots(probe, species, t_noms))
	return _h(content_id, lanes, seed, ls)


func test_constant_90_rpm_erg_rider_lands_the_e2e_mackerel_in_band() -> void:
	var h := _h("e2e_2min")
	h.cadence[0] = 90.0
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 60.0), "the fight starts")
	var fight_t := h.state.t
	assert_eq(h.lane().pub_lo, 85, "band [85, 101] at S = 1 (offset +3)")
	assert_eq(h.lane().pub_hi, 101)
	assert_true(h.run_to_state(0, FishingConst.ST_LANDING, 80.0), "the landing starts")
	var fight_len := h.state.t - fight_t
	assert_between(fight_len, 45.0, 46.0, "S = 0 at T_nom 45 s")
	h.run(31.0)
	assert_eq(h.events_of(FishingEvents.LANDED).size(), 1, "one mackerel landed")
	assert_eq(h.events_of(FishingEvents.SNAP).size() + h.events_of(FishingEvents.THROWN).size(), 0)
	assert_almost_eq(h.lane().band_s, h.lane().fight_total_s, 0.06, "in band the whole fight")
	assert_eq(h.lane().state, FishingConst.ST_HOME, "the cool-down follows the landing")
	assert_lte(h.time_of(FishingEvents.LANDING), 135.0, "within the e2e budget")
	assert_eq(h.finished, "", "scheduled trips never finish on their own")
	assert_eq(h.violations, [] as Array[String])


func test_e2e_event_sequence_is_complete_and_well_formed() -> void:
	var h := _h("e2e_2min", 2)
	h.run(125.0)
	var types: Array = []
	for e: Dictionary in h.events:
		assert_eq(FishingEvents.check(e), "", str(e))
		if int(e.get("l", -1)) == 0:
			types.append(e["type"])
	assert_eq(types.slice(0, 1), [FishingEvents.CAST], "the lane casts first")
	for t: String in [
		FishingEvents.BITE,
		FishingEvents.STRIKE_OK,
		FishingEvents.HOOKUP,
		FishingEvents.LANDING,
		FishingEvents.LANDED
	]:
		assert_has(types, t)
	var hook := h.events_of(FishingEvents.HOOKUP, 0)[0] as Dictionary
	assert_eq(int(hook["sch"]), 1, "a scheduled fish")
	assert_eq(int(hook["n"]), 1)


func test_scheduled_bite_comes_four_seconds_before_the_reel_ends_and_hooks_itself() -> void:
	var h := _h("e2e_2min")
	h.lane().fallback = false
	h.run(40.0)
	var reel_end := 15.0 + 20.0
	assert_almost_eq(h.time_of(FishingEvents.BITE), reel_end - 4.0, 0.06)
	assert_eq(h.time_of(FishingEvents.STRIKE_OK), h.time_of(FishingEvents.BITE), "no strike needed")
	assert_almost_eq(h.time_of(FishingEvents.HOOKUP), reel_end, 0.11, "the plan's Fight starts it")
	assert_eq(h.ended.size(), 0, "no end_phase on a fixed Reel")


func test_ride_out_publishes_the_practice_band_and_tips_every_45_s() -> void:
	var h := _free("free_30", 1, ["mackerel"], [80.0])
	h.run(299.0)
	assert_eq(h.lane().state, FishingConst.ST_RIDE_OUT)
	assert_eq(h.bands[0].slice(1), [1, 82, 98], "preferred 90 +- 8")
	var keys: Array = []
	for t: Array in h.toasts:
		keys.append(t[1])
		assert_eq(t[3], 1, "the rider's own peer")
	assert_eq(
		keys,
		[
			"FISHING_TIP_1",
			"FISHING_TIP_2",
			"FISHING_TIP_3",
			"FISHING_TIP_4",
			"FISHING_TIP_5",
			"FISHING_TIP_6"
		]
	)
	assert_almost_eq(float(h.toasts[0][0]), 45.0, 0.06)
	assert_eq(h.events.size(), 0, "no bites in the ride out")


func test_reel_publishes_the_lure_band_for_the_next_species() -> void:
	var h := _free("free_30", 1, ["mahi"], [150.0])
	h.run(301.0)
	assert_true(h.lane().state in [FishingConst.ST_CAST, FishingConst.ST_REEL], "cast at once")
	assert_eq([h.lane().pub_lo, h.lane().pub_hi], [90, 106], "90 + 8 (mahi) +- 8")


func test_a_lane_with_no_slots_left_reels_out_quietly() -> void:
	var h := _free("free_30", 1, [], [])
	h.run(320.0)
	assert_eq(h.lane().state, FishingConst.ST_IDLE)
	assert_eq([h.lane().pub_lo, h.lane().pub_hi], [82, 98], "the practice band")
	assert_eq(h.events.size(), 0)


func test_trip_over_waits_for_fishing_time_and_emits_once() -> void:
	var h := _free("free_20", 1, [], [])
	var end_t := h.state.fishing_end_t
	assert_almost_eq(end_t, 300.0 + h.content.trip.fishing_s, 0.001)
	h.run(end_t - 1.0)
	assert_eq(h.finished, "")
	h.run(2.0)
	assert_eq(h.finished, "trip_over")
	assert_almost_eq(h.time_of(FishingEvents.TRIP_OVER), end_t, 0.051)
	h.run(10.0)
	assert_eq(h.finished_count, 1, "once")
	assert_eq(h.events_of(FishingEvents.TRIP_OVER).size(), 1)
	assert_eq(h.lane().state, FishingConst.ST_HOME, "the harness jumped to the cool-down")


func test_trip_over_waits_for_a_running_fight_and_its_landing() -> void:
	var h := _free("free_20", 1, ["mackerel"], [100.0])
	h.follow_band[0] = true
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 1000.0))
	# Fishing time ends mid-fight: the fight and its Landing finish first.
	h.state.fishing_end_t = h.state.t + 5.0
	h.state.overrun_end_t = h.state.fishing_end_t + FishingConst.LAST_CALL_OVERRUN_S
	h.run(10.0)
	assert_eq(h.finished, "", "not during the fight")
	assert_true(h.run_to_state(0, FishingConst.ST_LANDING, 200.0))
	h.run(29.0)
	assert_eq(h.finished, "", "not during the landing")
	h.run(2.0)
	assert_eq(h.finished, "trip_over")
	assert_eq(h.events_of(FishingEvents.LANDED).size(), 1, "the fish was landed first")
	var order: Array = h.events.map(func(e: Dictionary) -> String: return e["type"])
	assert_gt(order.find(FishingEvents.TRIP_OVER), order.find(FishingEvents.LANDED))


func test_cool_down_sends_no_directives_or_bands() -> void:
	var h := _free("free_20", 1, [], [])
	h.run(h.state.fishing_end_t + 1.0)
	assert_eq(h.lane().state, FishingConst.ST_HOME)
	var n_dirs := h.directives.size()
	var n_bands := h.bands.size()
	var n_ended := h.ended.size()
	h.run(60.0)
	assert_eq(h.directives.size(), n_dirs)
	assert_eq(h.bands.size(), n_bands)
	assert_eq(h.ended.size(), n_ended, "no end_phase in the cool-down")


func test_same_seed_and_inputs_give_the_same_events() -> void:
	var a := _free("free_30", 2, ["mackerel", "mahi"], [70.0, 150.0], 11)
	var b := _free("free_30", 2, ["mackerel", "mahi"], [70.0, 150.0], 11)
	for h: H in [a, b]:
		h.follow_band[0] = true
		h.cadence[1] = 84.0
		h.run(1200.0)
	assert_gt(a.events.size(), 4)
	assert_eq(a.events, b.events)
	assert_eq(a.event_t, b.event_t)
	var c := _free("free_30", 2, ["mackerel", "mahi"], [70.0, 150.0], 12)
	c.follow_band[0] = true
	c.cadence[1] = 84.0
	c.run(1200.0)
	assert_ne(a.events, c.events, "another seed plays differently")


func test_lanes_draw_from_their_own_streams() -> void:
	var solo := _free("free_30", 1, ["mackerel"], [70.0], 5)
	var none: Array[FishingPlanSlot] = []
	var duo := _h("free_30", 2, 5, [_slots(solo, ["mackerel"], [70.0]), none])
	solo.run(400.0)
	duo.cadence[1] = 60.0
	duo.run(400.0)
	var solo_casts := solo.events_of(FishingEvents.CAST, 0)
	var duo_casts := duo.events_of(FishingEvents.CAST, 0)
	assert_gt(solo_casts.size(), 0)
	assert_eq(solo_casts, duo_casts, "another rider never shifts lane 0's draws")
	assert_eq(solo.time_of(FishingEvents.BITE, 0), duo.time_of(FishingEvents.BITE, 0))
