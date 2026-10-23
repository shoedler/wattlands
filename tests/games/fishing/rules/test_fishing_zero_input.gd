extends GutTest
## Strikes, pedal-scan picks and the zero-intent Autopilot fallback (brief 2.4, 2.5, 4.1).

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")

const SURGE := {"k": "confirm", "via": "surge"}
const BUTTON := {"k": "confirm", "via": "button"}
const KEY := {"k": "confirm", "via": "action"}


func _free(species: Array, t_noms: Array, seed: int = 3) -> H:
	var probe := H.new()
	probe.content = H.load_content("free_30")
	var one: Array[FishingPlanSlot] = []
	for k in species.size():
		one.append(H.make_slot(probe.content, species[k], k, t_noms[k]))
	var h := H.new()
	h.setup("free_30", 1, seed, [one])
	h.follow_band[0] = true
	return h


func _until_state(h: H, st: int, max_s: float) -> bool:
	return h.run_to_state(0, st, max_s)


func test_the_fallback_plays_picks_casts_and_strikes_at_0_5_s() -> void:
	var h := _free(["mackerel"], [80.0])
	assert_true(h.lane().fallback, "starts on")
	h.run(300.0)
	h.step()
	assert_eq(h.events_of(FishingEvents.CAST).size(), 1, "casts at once")
	assert_true(_until_state(h, FishingConst.ST_STRIKE, 400.0))
	assert_true(h.run_until(func() -> bool: return h.lane().hook_set, 1.0))
	var bite_t := h.time_of(FishingEvents.BITE)
	assert_almost_eq(h.time_of(FishingEvents.STRIKE_OK) - bite_t, 0.5, 0.051, "strikes at 0.5 s")
	assert_eq(h.ended.size(), 1, "the hook-set ends the Reel")


func test_surges_and_the_summary_never_end_the_fallback() -> void:
	var h := _free(["mackerel", "mackerel"], [80.0, 80.0])
	h.send(0, {"k": "summary", "xp": 10, "rec": {}, "cos": [0, 0, 0, 0]})
	h.run(300.0)
	h.send(0, SURGE)  # a surge at the cast
	h.step()
	assert_true(h.lane().fallback)
	var cast := h.events_of(FishingEvents.CAST)[0] as Dictionary
	assert_eq(int(cast["spot"]), FishingAutopilot.pick(h.lane().hints), "still Autopilot's pick")
	assert_true(_until_state(h, FishingConst.ST_STRIKE, 400.0))
	h.send(0, SURGE)  # a surge at the strike sets the hook at once
	h.step()
	assert_true(h.lane().hook_set)
	assert_almost_eq(h.time_of(FishingEvents.STRIKE_OK) - h.time_of(FishingEvents.BITE), 0.05, 0.01)
	assert_true(h.lane().fallback, "a surge never ends the fallback")
	# The next Reel: Autopilot still picks and casts at once.
	var casts := h.events_of(FishingEvents.CAST).size()
	assert_true(
		h.run_until(func() -> bool: return h.events_of(FishingEvents.CAST).size() > casts, 900.0)
	)
	assert_true(h.lane().fallback)
	assert_eq(h.lane().state, FishingConst.ST_CAST)
	var cast2 := h.events_of(FishingEvents.CAST).back() as Dictionary
	assert_eq(int(cast2["spot"]), FishingAutopilot.pick(h.lane().hints))


func test_a_button_or_key_intent_ends_the_fallback() -> void:
	for intent: Dictionary in [BUTTON, KEY, {"k": "spot", "dir": 1, "via": "action"}]:
		var h := _free(["mackerel"], [80.0])
		h.run(10.0)
		h.send(0, intent)
		h.step()
		assert_false(h.lane().fallback, str(intent))
	assert_true(FishingIntents.is_deliberate(BUTTON))
	assert_false(FishingIntents.is_deliberate(SURGE))


func test_a_surge_with_a_confirm_in_one_tick_counts_as_the_surge() -> void:
	var h := _free(["mackerel"], [80.0])
	h.run(10.0)
	h.send(0, KEY)
	h.send(0, SURGE)
	h.step()
	assert_true(h.lane().fallback, "normalize_tick dropped the confirm")


func test_after_the_fallback_picks_scan_every_1_6_s_and_auto_confirm_after_two_cycles() -> void:
	var h := _free(["mackerel"], [80.0])
	h.send(0, BUTTON)  # ends the fallback in the ride out (a confirm there does nothing)
	h.run(300.0)
	h.step()
	var l := h.lane()
	assert_false(l.fallback)
	assert_eq(l.state, FishingConst.ST_PICK, "no instant cast")
	assert_eq(l.selected, 0)
	var t0 := h.state.t
	h.run(1.6)
	assert_eq(l.selected, 1, "the highlight steps every 1.6 s")
	h.run(1.6)
	assert_eq(l.selected, 2)
	h.run(1.6)
	assert_eq(l.selected, 0, "wraps")
	assert_eq(h.events_of(FishingEvents.CAST).size(), 0)
	assert_almost_eq(FishingRules.auto_confirm_s(3), 9.6, 0.0001)
	assert_true(h.run_until(func() -> bool: return l.state == FishingConst.ST_CAST, 6.0))
	assert_almost_eq(h.state.t - t0, 9.6, 0.051, "auto-confirm after 2 x 3 x 1.6 s")
	assert_false(l.fallback, "an auto-confirm makes no intent")


func test_left_right_move_the_highlight_pause_the_scan_and_confirm_casts_it() -> void:
	var h := _free(["mackerel"], [80.0])
	h.send(0, BUTTON)
	h.run(300.0)
	h.step()
	var l := h.lane()
	h.send(0, {"k": "spot", "dir": -1, "via": "action"})
	h.step()
	assert_eq(l.selected, 2, "left from 0 wraps to 2")
	h.run(9.0)
	assert_eq(l.selected, 2, "the scan pauses 10 s")
	assert_eq(l.state, FishingConst.ST_PICK, "a move restarts the auto-confirm clock")
	h.send(0, KEY)
	h.step()
	assert_eq(l.state, FishingConst.ST_CAST)
	var cast := h.events_of(FishingEvents.CAST)[0] as Dictionary
	assert_eq(int(cast["spot"]), 2)
	assert_almost_eq(int(cast["d"]) / 10.0, l.hints[7], 0.051)


func test_a_missed_strike_bites_again_20_to_40_s_later() -> void:
	var h := _free(["mahi"], [150.0])
	h.send(0, BUTTON)
	assert_true(_until_state(h, FishingConst.ST_STRIKE, 800.0))
	var bite_t := h.state.t
	assert_true(
		h.run_until(func() -> bool: return h.events_of(FishingEvents.STRIKE_MISS).size() > 0, 5.0)
	)
	var miss_t := h.time_of(FishingEvents.STRIKE_MISS)
	assert_almost_eq(miss_t - bite_t, 4.0, 0.051, "the 4 s prompt")
	assert_true(
		h.run_until(func() -> bool: return h.events_of(FishingEvents.BITE).size() > 1, 60.0)
	)
	var again := h.time_of(FishingEvents.BITE, -1, 1) - miss_t
	assert_between(again, 20.0 - 0.06, 40.0 + 11.2, "20-40 s (plus a recast at most)")
	var b2 := h.events_of(FishingEvents.BITE)[1] as Dictionary
	assert_eq(int(b2["sp"]), FishingConst.species_index("mahi"), "the same species")
	h.send(0, BUTTON)
	h.step()
	assert_true(h.lane().hook_set, "a button sets the hook")


func test_strike_prompt_toasts_the_rider_but_not_an_autopilot_rider() -> void:
	var h := _free(["mackerel"], [80.0])
	assert_true(_until_state(h, FishingConst.ST_STRIKE, 800.0))
	var strike := h.toasts.filter(func(t: Array) -> bool: return t[1] == "FISHING_TOAST_STRIKE")
	assert_eq(strike.size(), 1)
	assert_eq(strike[0][3], 1, "to the rider's own peer")
	var ap := _free(["mackerel"], [80.0])
	ap.players[0].autopilot = true
	ap.rebuild()
	assert_true(_until_state(ap, FishingConst.ST_STRIKE, 800.0))
	assert_eq(
		ap.toasts.filter(func(t: Array) -> bool: return t[1] == "FISHING_TOAST_STRIKE").size(), 0
	)


func test_end_phase_waits_for_the_reel_min_s() -> void:
	var h := _free(["mackerel"], [80.0])
	h.run(300.1)
	h.lane().rebite_t = h.state.t + 5.0  # a bite long before the Reel's min_s of 120 s
	assert_true(h.run_until(func() -> bool: return h.lane().hook_set, 300.0))
	var hook_t := h.state.t
	assert_lt(hook_t, 300.0 + 120.0, "hooked early")
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 200.0))
	assert_almost_eq(h.ended[0][0], 300.0 + 120.0, 0.11, "end_phase once elapsed >= min_s")
	assert_eq(h.violations, [] as Array[String])


func test_summary_is_stored_once() -> void:
	var h := _free(["mackerel"], [80.0])
	h.send(0, {"k": "summary", "xp": 1200, "rec": {"tuna": 455, "bogus": 3}, "cos": [1, 2, 0, 1]})
	h.step()
	h.send(0, {"k": "summary", "xp": 5, "rec": {}, "cos": [3, 3, 3, 3]})
	h.step()
	var l := h.lane()
	assert_eq(l.summary_xp, 1200)
	assert_eq(l.records, {"tuna": 45.5})
	assert_eq(l.cosmetics, [1, 2, 0, 1] as Array[int])
	assert_true(l.fallback)
