extends GutTest
## Tension (brief 2.4, 4.1): the band's width, low edge and slide; the meters' fill and drain;
## snaps, thrown hooks and replacements; rescue, AFK and stale freezes.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


## An e2e mackerel fight under way (scheduled, T_nom 45 s, band offset +3).
func _fight(preferred: float = 90.0, relaxed: bool = false) -> H:
	var h := H.new()
	h.setup("e2e_2min", 1, 7)
	if preferred != 90.0 or relaxed:
		h.players[0].preferred_cadence_rpm = preferred
		h.players[0].options["relaxed_band"] = relaxed
		h.rebuild()
	h.follow_band[0] = true
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 60.0), "the fight starts")
	return h


## A Free mackerel fight under way (a fish that could be a trophy).
func _free_fight() -> H:
	var probe := H.new()
	probe.content = H.load_content("free_30")
	var ls: Array[FishingPlanSlot] = [H.make_slot(probe.content, "mackerel", 0, 100.0, 0, 1.6)]
	var h := H.new()
	h.setup("free_30", 1, 3, [ls])
	h.follow_band[0] = true
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 900.0), "the fight starts")
	return h


## Holds the lane's cadence (and its EMA) at `rpm`.
func _hold(h: H, rpm: float) -> void:
	h.follow_band[0] = false
	h.cadence[0] = rpm
	h.lane().cadence_ema = rpm


func test_band_is_16_wide_with_its_low_edge_8_under_the_centre() -> void:
	var h := _fight()
	var l := h.lane()
	assert_almost_eq(l.band_center, 93.0, 0.01, "preferred 90 + offset 3 at S = 1")
	assert_almost_eq(l.band_lo, 85.0, 0.01)
	assert_almost_eq(l.band_hi - l.band_lo, FishingConst.BAND_WIDTH, 0.001)
	assert_eq([l.pub_lo, l.pub_hi], [85, 101])
	assert_eq(h.bands.back().slice(1), [1, 85, 101], "published with cadence_band")


func test_relaxed_band_is_22_wide() -> void:
	var h := _fight(90.0, true)
	assert_almost_eq(h.lane().band_hi - h.lane().band_lo, FishingConst.BAND_WIDTH_RELAXED, 0.001)
	assert_eq([h.lane().pub_lo, h.lane().pub_hi], [85, 107])


func test_low_edge_never_drops_below_65() -> void:
	var h := _fight(70.0)
	assert_almost_eq(h.lane().band_lo, 65.0, 0.001, "max(65, 73 - 8)")
	h.lane().fish.s = 0.2
	h.run(10.0)
	assert_almost_eq(h.lane().band_lo, 65.0, 0.001, "the centre fell, the low edge holds")
	assert_almost_eq(h.lane().band_hi, 81.0, 0.001)


func test_band_centre_slides_at_most_3_rpm_per_second() -> void:
	var h := _fight()
	_hold(h, 90.0)
	var l := h.lane()
	var c0 := l.band_center
	l.fish.s = 0.0  # target centre 10 rpm lower
	h.run(1.0)
	assert_almost_eq(l.band_center, c0 - 3.0, 0.02, "3 rpm in 1 s")
	h.run(2.0)
	assert_almost_eq(l.band_center, c0 - 9.0, 0.02)
	h.run(1.0)
	assert_almost_eq(l.band_center, c0 - 10.0, 0.02, "stops at the target")


func test_band_is_republished_only_when_its_rounded_edges_change() -> void:
	var h := _fight()
	var before := h.bands.size()
	h.run(1.0)
	assert_lte(h.bands.size() - before, 1, "S falls 1/45 per s: at most one integer step")
	var last := -1
	for b: Array in h.bands:
		var key := int(b[2]) * 1000 + int(b[3])
		assert_ne(key, last, "consecutive publishes differ")
		last = key


func test_strain_fills_in_6_s_below_the_band_and_snaps() -> void:
	var h := _fight()
	h.run(2.0)
	_hold(h, 60.0)
	var t0 := h.state.t
	h.run(3.0)
	assert_almost_eq(h.lane().strain, 0.5, 0.001, "1/6 per second")
	assert_eq(h.events_of(FishingEvents.SNAP).size(), 0)
	h.run(3.0)
	assert_eq(h.events_of(FishingEvents.SNAP).size(), 1)
	assert_almost_eq(h.time_of(FishingEvents.SNAP) - t0, 6.0, 0.051, "full at 6 s")


func test_slack_fills_in_6_s_above_the_band_and_throws_the_hook() -> void:
	var h := _fight()
	h.run(2.0)
	_hold(h, 120.0)
	var t0 := h.state.t
	h.run(7.0)
	assert_eq(h.events_of(FishingEvents.THROWN).size(), 1)
	assert_almost_eq(h.time_of(FishingEvents.THROWN) - t0, 6.0, 0.051)
	assert_eq(h.events_of(FishingEvents.SNAP).size(), 0)


func test_meters_drain_in_12_s() -> void:
	var h := _fight()
	_hold(h, 93.0)
	h.lane().strain = 0.5
	h.run(3.0)
	assert_almost_eq(h.lane().strain, 0.25, 0.001, "1/12 per second in band")
	h.run(3.0)
	assert_almost_eq(h.lane().strain, 0.0, 0.001)
	h.lane().slack = 0.5
	_hold(h, 60.0)
	h.run(3.0)
	assert_almost_eq(h.lane().slack, 0.25, 0.001, "slack drains while strain fills")
	assert_almost_eq(h.lane().strain, 0.5, 0.001)


func test_a_snap_costs_the_fish_and_a_lighter_replacement_hooks_itself_5_s_later() -> void:
	var h := _fight()
	h.run(5.0)
	var l := h.lane()
	var kg0 := l.fish.kg
	_hold(h, 60.0)
	assert_true(h.run_until(func() -> bool: return l.fish.off_line, 7.0), "snapped")
	var s0 := l.fish.s
	var t_snap := h.state.t
	assert_eq(l.lost_lines, 1)
	assert_eq([l.strain, l.slack], [0.0, 0.0], "the meters reset")
	h.follow_band[0] = true
	h.run(4.9)
	assert_true(l.fish.off_line, "nothing on the line for 5 s")
	assert_almost_eq(l.fish.s, s0, 0.0001, "S waits")
	assert_true(h.run_until(func() -> bool: return not l.fish.off_line, 0.2))
	assert_almost_eq(h.time_of(FishingEvents.REPLACEMENT) - t_snap, 5.0, 0.051)
	assert_true(l.fish.replacement)
	assert_almost_eq(l.fish.s, s0, 0.0012, "the replacement keeps S (one tick of tiring)")
	assert_almost_eq(l.fish.kg, kg0 * FishingConst.REPLACEMENT_KG, 0.0001, "x 0.75 kg")
	assert_eq(l.state, FishingConst.ST_FIGHT, "the same phase")
	var rep := h.events_of(FishingEvents.REPLACEMENT)[0] as Dictionary
	assert_eq(int(rep["sp"]), 0, "same species")
	assert_true(h.run_to_state(0, FishingConst.ST_LANDING, 120.0), "the replacement is landed")
	h.run(16.0)
	var landed := h.events_of(FishingEvents.LANDED)[0] as Dictionary
	assert_eq(int(landed["kg"]), roundi(kg0 * 0.75 * 10.0))


func test_a_replacement_is_never_a_trophy() -> void:
	var h := _free_fight()
	var l := h.lane()
	_hold(h, 50.0)
	assert_true(h.run_until(func() -> bool: return l.fish.off_line, 7.0))
	h.follow_band[0] = true
	h.landing_w[0] = 1.4 * h.players[0].ftp
	assert_true(h.run_to_state(0, FishingConst.ST_LANDING, 200.0))
	h.run(16.0)
	assert_almost_eq(l.gaff, 1.0, 0.001, "the gaff meter filled")
	var landed := h.events_of(FishingEvents.LANDED)[0] as Dictionary
	assert_eq(int(landed["grade"]), FishingConst.GRADE_LANDED, "but no trophy")
	assert_eq(l.trophies, 0)


func test_rescue_freezes_s_meters_and_band_and_the_fish_swims_out() -> void:
	var h := _fight()
	h.run(5.0)
	var l := h.lane()
	l.strain = 0.3
	var s0 := l.fish.s
	var c0 := l.band_center
	var d0 := l.fish.d
	h.rescue[0] = true
	h.follow_band[0] = false
	h.cadence[0] = 30.0
	h.run(8.0)
	assert_true(l.staggered)
	assert_almost_eq(l.fish.s, s0, 0.0001, "S frozen")
	assert_almost_eq(l.strain, 0.3, 0.0001, "meters frozen: a rescue never snaps a line")
	assert_almost_eq(l.band_center, c0, 0.0001, "band frozen")
	assert_almost_eq(l.fish.d, minf(d0 + 8.0, l.fish.d_max), 0.06, "swims out at 1 m/s")
	assert_eq(h.events_of(FishingEvents.SNAP).size(), 0)
	h.rescue[0] = false
	h.follow_band[0] = true
	h.run(9.9)
	assert_true(l.staggered, "still frozen until 10 s after the rescue")
	assert_almost_eq(l.fish.s, s0, 0.0001)
	h.run(0.3)
	assert_false(l.staggered, "play resumes")
	h.run(1.0)
	assert_lt(l.fish.s, s0, "tiring again")


func test_module_rescue_flag_counts_too() -> void:
	var h := _fight()
	h.run(3.0)
	var l := h.lane()
	var s0 := l.fish.s
	l.rescue = true
	h.run(2.0)
	assert_true(l.staggered)
	assert_almost_eq(l.fish.s, s0, 0.0001)


func test_afk_flags_and_stale_telemetry_stagger_the_lane() -> void:
	for how: String in ["telemetry_afk", "module_afk", "stale", "disconnected"]:
		var h := _fight()
		h.run(3.0)
		var l := h.lane()
		var s0 := l.fish.s
		match how:
			"telemetry_afk":
				h.afk[0] = true
			"module_afk":
				l.afk = true
			"stale":
				h.age_s[0] = 3.5
			"disconnected":
				h.connected[0] = false
		h.run(2.0)
		assert_true(l.staggered, how)
		assert_almost_eq(l.fish.s, s0, 0.0001, how)
		assert_eq(h.lane().stale, how in ["stale", "disconnected"], how)


func test_fresh_telemetry_under_3_s_is_no_stagger() -> void:
	var h := _fight()
	h.age_s[0] = 2.9
	h.run(2.0)
	assert_false(h.lane().staggered)


func test_stale_cadence_freezes_only_the_meters() -> void:
	var h := _fight()
	h.run(3.0)
	var l := h.lane()
	_hold(h, 60.0)
	h.cadence_age_s[0] = 3.5
	l.strain = 0.2
	var s0 := l.fish.s
	h.run(4.0)
	assert_true(l.cadence_stale)
	assert_almost_eq(l.strain, 0.2, 0.0001, "meters frozen")
	assert_false(l.staggered, "no stagger")
	assert_gt(l.fish.s, s0, "out of band the fish still recovers")
