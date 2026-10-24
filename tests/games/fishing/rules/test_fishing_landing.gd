extends GutTest
## The fight's end and the Landing (brief 2.4, 2.7, 4.1): tiring to S = 0, the end at max_s, the
## gaff meter, trophies, the last-run haptic and points.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func _free(
	species: String, t_nom: float, runs: int = 0, seed: int = 3, trip: String = "base_60"
) -> H:
	var probe := H.new()
	probe.content = H.load_content(trip)
	var ls: Array[FishingPlanSlot] = [H.make_slot(probe.content, species, 0, t_nom, runs)]
	var h := H.new()
	h.setup(trip, 1, seed, [ls])
	h.follow_band[0] = true
	return h


func _to_landing(h: H) -> float:
	assert_true(h.run_to_action(0, FishingConst.A_FIGHT, 1200.0), "the fight starts")
	var t0 := h.state.t
	assert_true(h.run_to_action(0, FishingConst.A_LAND, 1500.0), "the landing starts")
	return h.state.t - t0


func test_an_ideal_in_band_rider_lands_between_t_nom_and_t_nom_plus_15() -> void:
	for c: Array in [["mackerel", 70.0], ["mahi", 150.0], ["tuna", 220.0], ["marlin", 320.0]]:
		var h := _free(c[0], c[1], 0, 3, "base_60")
		var fight_s := _to_landing(h)
		assert_between(fight_s, float(c[1]), float(c[1]) + 15.0, "%s fight %.1f s" % c)
		assert_almost_eq(h.rider().band_s, h.rider().fight_total_s, 0.06, "%s in band" % c[0])
		assert_eq(h.rider().lost_lines, 0)
		assert_eq(h.violations, [] as Array[String])


func test_the_fight_ends_with_end_phase_only_after_min_s() -> void:
	var h := _free("mackerel", 90.0)
	h.power_pct[0] = 120.0  # tires 1.2x: S = 0 at 75 s, min_s is 72
	var fight_s := _to_landing(h)
	assert_between(fight_s, 72.0, 78.0)
	assert_eq(h.ended.size(), 2, "end_phase for the Troll (hook-set) and the Fight")
	assert_eq(h.violations, [] as Array[String], "never before min_s")


func test_out_of_band_the_fish_recovers_up_to_1() -> void:
	var h := _free("mahi", 200.0)
	assert_true(h.run_to_action(0, FishingConst.A_FIGHT, 1200.0))
	var l := h.rider()
	l.fish.s = 0.5
	h.follow_band[0] = false
	h.cadence[0] = l.band_hi + 3.0
	l.cadence_ema = h.cadence[0]
	h.run(4.0)
	assert_almost_eq(l.fish.s, 0.5 + 4.0 * 0.25 / 200.0, 0.0005, "+0.25 / T_nom per second")
	l.fish.s = 0.999
	l.slack = 0.0
	h.run(4.0)
	assert_eq(l.fish.s, 1.0, "S <= 1")


func test_a_fish_never_tired_ends_at_max_s_and_is_landed_anyway() -> void:
	var h := _free("mackerel", 90.0)
	h.power_pct[0] = 0.0  # in band, no work: S stays 1
	var fight_s := _to_landing(h)
	var max_s: float = h.content.species["mackerel"].max_s
	assert_almost_eq(fight_s, max_s, 0.11, "the platform ends it at max_s")
	assert_almost_eq(h.rider().fish.s, 1.0, 0.0001)
	h.run(16.0)
	assert_eq(h.events_of(FishingEvents.LANDED).size(), 1, "the fish is spent: landed")


func test_landing_clears_the_band() -> void:
	var h := _free("mackerel", 90.0)
	_to_landing(h)
	assert_eq(h.bands.back().slice(1), [1, 0, 0], "cadence_band(peer, 0, 0)")
	assert_eq([h.rider().pub_lo, h.rider().pub_hi], [0, 0])
	assert_eq(h.events_of(FishingEvents.LANDING).size(), 1)


func test_15_s_at_140_percent_cp_fills_the_gaff_and_makes_a_trophy() -> void:
	var h := _free("mackerel", 90.0)
	h.landing_w[0] = 1.4 * h.players[0].ftp
	_to_landing(h)
	h.run(14.9)
	assert_almost_eq(h.rider().gaff, 0.993, 0.01, "filling")
	h.run(0.2)
	assert_almost_eq(h.rider().gaff, 1.0, 0.02)
	var landed := h.events_of(FishingEvents.LANDED)[0] as Dictionary
	assert_eq(int(landed["grade"]), FishingConst.GRADE_TROPHY)
	assert_eq(h.rider().trophies, 1)
	h.run(10.0)
	assert_eq(h.rider().action, FishingConst.A_LAND)
	assert_almost_eq(h.rider().gaff, 1.0, 0.001, "nothing counts after 15 s")


func test_nothing_counts_below_1_2_ftp_and_partial_sprints_partly_fill() -> void:
	assert_eq(FishingFight.gaff_rate(1.19 * 200.0, 200.0), 0.0, "below 1.2 x FTP")
	assert_almost_eq(FishingFight.gaff_rate(1.2 * 200.0, 200.0) * 15.0, 0.5, 0.0001)
	assert_almost_eq(FishingFight.gaff_rate(1.4 * 300.0, 300.0) * 15.0, 1.0, 0.0001)
	var h := _free("mackerel", 90.0)
	h.landing_w[0] = 1.19 * h.players[0].ftp
	_to_landing(h)
	h.run(16.0)
	assert_eq(h.rider().gaff, 0.0)
	var landed := h.events_of(FishingEvents.LANDED)[0] as Dictionary
	assert_eq(int(landed["grade"]), FishingConst.GRADE_LANDED)
	var half := _free("mackerel", 90.0)
	half.landing_w[0] = 1.2 * half.players[0].ftp
	_to_landing(half)
	half.run(25.0)
	assert_almost_eq(half.rider().gaff, 0.5, 0.02, "only the first 15 s count")


func test_scheduled_fish_are_never_trophies() -> void:
	var h := H.new()
	h.setup("e2e_2min", 1, 7)
	h.landing_w[0] = 1.5 * h.players[0].ftp
	h.run(120.0)
	assert_almost_eq(h.rider().gaff, 1.0, 0.001)
	var landed := h.events_of(FishingEvents.LANDED)[0] as Dictionary
	assert_eq(int(landed["grade"]), FishingConst.GRADE_LANDED)


func _haptics(h: H) -> Array:
	return h.directives.filter(func(d: Array) -> bool: return (d[2] as Dictionary).has("haptic"))


func test_one_last_run_haptic_3_to_6_s_into_the_sprint() -> void:
	var h := _free("mackerel", 90.0)
	_to_landing(h)
	var t0 := h.state.t
	h.run(30.0)
	var hp := _haptics(h)
	assert_eq(hp.size(), 1, "once per Landing")
	assert_between(float(hp[0][0]) - t0, 3.0 - 0.06, 6.0 + 0.06)
	assert_eq(hp[0][1], 1, "to the rider's peer")
	assert_eq(
		hp[0][2],
		{"mode": "SIM", "haptic": 3.0, "duration_s": 5.0, "reason": "last_run", "source": "fishing"}
	)


func test_no_haptic_when_opted_out_in_rescue_or_in_the_first_300_s() -> void:
	var off := _free("mackerel", 90.0)
	off.players[0].haptics_on = false
	off.rebuild()
	_to_landing(off)
	off.run(30.0)
	assert_eq(_haptics(off).size(), 0, "haptics off")
	var res := _free("mackerel", 90.0)
	_to_landing(res)
	res.rescue[0] = true
	res.run(30.0)
	assert_eq(_haptics(res).size(), 0, "in rescue")
	var e2e := H.new()
	e2e.setup("e2e_2min", 1, 7)
	e2e.run(120.0)
	assert_eq(e2e.events_of(FishingEvents.LANDING).size(), 1)
	assert_eq(_haptics(e2e).size(), 0, "plan_elapsed < 300 s")
	var lane := FishingRiderState.new()
	var inp := FishingRiderInput.new()
	inp.plan_elapsed_s = 299.9
	assert_false(FishingFight.haptic_allowed(lane, inp))
	inp.plan_elapsed_s = 300.0
	assert_true(FishingFight.haptic_allowed(lane, inp))


## Brief 2.3: "No request is sent during rescue or AFK"; a dropped client (stale) counts as AFK.
func test_no_haptic_to_an_afk_or_dropped_rider() -> void:
	var afk := _free("mackerel", 90.0)
	_to_landing(afk)
	afk.afk[0] = true
	afk.run(30.0)
	assert_eq(_haptics(afk).size(), 0, "no haptic while AFK")
	var gone := _free("mackerel", 90.0)
	_to_landing(gone)
	gone.connected[0] = false
	gone.age_s[0] = 4.0
	gone.run(30.0)
	assert_eq(_haptics(gone).size(), 0, "no haptic to a dropped (stale) rider")
	var lane := FishingRiderState.new()
	var inp := FishingRiderInput.new()
	inp.plan_elapsed_s = 400.0
	assert_true(FishingFight.haptic_allowed(lane, inp), "control")
	lane.afk = true
	assert_false(FishingFight.haptic_allowed(lane, inp), "on_afk")
	lane.afk = false
	inp.afk = true
	assert_false(FishingFight.haptic_allowed(lane, inp), "telemetry AFK")
	inp.afk = false
	lane.stale = true
	assert_false(FishingFight.haptic_allowed(lane, inp), "stale telemetry")


func test_points_are_base_points_times_grade_times_hookup() -> void:
	var h := _free("mahi", 150.0)
	h.landing_w[0] = 1.4 * h.players[0].ftp
	_to_landing(h)
	var f := h.rider().fish
	var slot := h.rider().slots[0]
	assert_almost_eq(f.kg, slot.kg, 0.0001, "the slot's weight")
	h.run(16.0)
	var landed := h.events_of(FishingEvents.LANDED)[0] as Dictionary
	var expect := roundi(FishingConst.base_points(f.kg) * 1.5 * 1.0)
	assert_eq(int(landed["points"]), expect)
	assert_eq(int(landed["hk"]), 10)
	assert_eq(int(landed["kg"]), roundi(f.kg * 10.0))
	assert_eq(h.state.team_points, expect)
	assert_eq(h.state.team_fish, 1)
	assert_eq(h.rider().points, expect)
	assert_eq(h.rider().fish_landed, 1)
	assert_almost_eq(h.state.expected_points, float(FishingConst.base_points(f.kg)), 0.001)
	assert_eq(h.state.fish_started, 1)
	var mahi := FishingConst.species_index("mahi")
	assert_eq(h.state.catches, [0, mahi, roundi(f.kg * 10.0), 1] as Array[int])


func test_lane_stats_and_catch_log() -> void:
	var h := _free("mackerel", 90.0)
	h.rider().records = {"mackerel": 0.1}
	_to_landing(h)
	h.run(31.0)
	var l := h.rider()
	assert_eq(l.catches.size(), 1)
	var c: Dictionary = l.catches[0]
	assert_eq(c.keys(), ["sp", "kg", "grade", "fight_s", "points"])
	assert_eq(int(c["sp"]), FishingConst.species_index("mackerel"))
	assert_almost_eq(float(c["fight_s"]), l.fight_t, 0.001)
	assert_almost_eq(l.biggest_kg, float(c["kg"]), 0.0001)
	assert_eq(l.biggest_sp, FishingConst.species_index("mackerel"))
	assert_almost_eq(l.longest_fight_s, l.fight_t, 0.001)
	assert_eq(l.new_records, 1, "beat the 0.1 kg record")
	assert_gt(l.fight_total_s, 80.0)
	assert_almost_eq(l.last_fight_len_s, l.fight_t + 30.0, 0.11, "fight plus landing")
