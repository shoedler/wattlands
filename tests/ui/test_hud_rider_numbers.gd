extends GutTest
## HudRiderNumbers (GAME_SDK 10.4): the 3 s mean, stale power, in-band hysteresis, the heart rate's
## three states, the low-cadence warning and the W/kg opt-in.


func _tm(t: float, w: float, rpm: float = 90.0) -> Telemetry:
	var tm := Telemetry.new()
	tm.t = t
	tm.power_w = w
	tm.cadence_rpm = rpm
	tm.mode = Wl.ERG
	tm.applied_target_w = 190
	return tm


func _ride(n: HudRiderNumbers, from_s: float, to_s: float, w: float, rpm: float = 90.0) -> void:
	var t := from_s
	while t <= to_s + 1e-6:
		n.feed(_tm(t, w, rpm))
		t += 0.05


func test_the_mean_covers_three_seconds_of_samples() -> void:
	var n := HudRiderNumbers.new()
	_ride(n, 0.0, 5.0, 100.0)
	assert_almost_eq(n.mean_power_w(), 100.0, 0.01)
	_ride(n, 5.05, 6.5, 200.0)
	assert_almost_eq(n.mean_power_w(), 150.0, 3.0, "half the window at each value")
	_ride(n, 6.55, 9.0, 200.0)
	assert_almost_eq(n.mean_power_w(), 200.0, 0.01, "the old value has left the window")


func test_one_hertz_data_averages_without_jumping_a_full_step() -> void:
	var n := HudRiderNumbers.new()
	var t := 0.0
	var seen := []
	for i in 10:
		for k in 20:
			n.feed(_tm(t, 180.0 if i % 2 == 0 else 200.0))
			t += 0.05
		if i >= 4:
			seen.append(n.mean_power_w())
	assert_lt(seen.max() - seen.min(), 8.0, "the mean swings far less than the 20 W samples")


func test_a_first_sample_counts_alone() -> void:
	var n := HudRiderNumbers.new()
	n.feed(_tm(1.0, 123.0))
	assert_eq(n.mean_power_w(), 123.0)


func test_stale_power_is_not_zero_watts() -> void:
	var n := HudRiderNumbers.new()
	_ride(n, 0.0, 3.0, 150.0)
	assert_false(n.is_stale())
	var gone := _tm(3.1, 0.0, 0.0)
	gone.cadence_age_s = 3.5
	n.feed(gone)
	assert_true(n.is_stale(), "0 W with a stale cadence is no data")
	assert_eq(n.mean_power_w(), 0.0)
	assert_eq(n.band_state(), HudRiderNumbers.IN_BAND)
	n.feed(_tm(4.0, 150.0))
	assert_false(n.is_stale(), "data is back")
	assert_eq(n.mean_power_w(), 150.0, "the mean restarted, the gap left no zeros in it")


func test_a_stopped_rider_with_fresh_cadence_really_is_zero() -> void:
	var n := HudRiderNumbers.new()
	n.feed(_tm(1.0, 0.0, 0.0))
	assert_false(n.is_stale())
	assert_eq(n.mean_power_w(), 0.0)


func test_a_dropped_or_silent_peer_is_stale() -> void:
	var dropped := _tm(1.0, 120.0)
	dropped.connected = false
	assert_true(HudRiderNumbers.telemetry_stale(dropped))
	var silent := _tm(1.0, 120.0)
	silent.age_s = 3.5
	assert_true(HudRiderNumbers.telemetry_stale(silent))
	assert_false(HudRiderNumbers.telemetry_stale(_tm(1.0, 120.0)))


func test_hysteresis_holds_the_state_near_the_edge() -> void:
	var n := HudRiderNumbers.new()
	n.set_band(180.0, 200.0)
	n.push_power(0.0, 190.0)
	assert_true(n.in_band())
	# margin is 5 W on a 20 W band: dipping 2 W out stays in band
	n = HudRiderNumbers.new()
	n.set_band(180.0, 200.0)
	n.push_power(0.0, 178.0)
	assert_eq(n.band_state(), HudRiderNumbers.IN_BAND, "not past the margin")
	n.push_power(4.0, 174.0)
	n.push_power(7.5, 174.0)
	assert_eq(n.band_state(), HudRiderNumbers.UNDER, "past the margin")
	n.push_power(12.0, 179.0)
	n.push_power(16.0, 179.0)
	assert_eq(n.band_state(), HudRiderNumbers.UNDER, "back at the edge is not back in band")
	n.push_power(20.0, 181.0)
	n.push_power(24.0, 181.0)
	assert_eq(n.band_state(), HudRiderNumbers.IN_BAND)
	n.push_power(28.0, 240.0)
	n.push_power(32.0, 240.0)
	assert_eq(n.band_state(), HudRiderNumbers.OVER)


func test_a_rider_wandering_a_five_percent_band_on_one_hertz_data_never_flickers() -> void:
	var n := HudRiderNumbers.new()
	n.set_band(180.5, 199.5)
	var changes := 0
	var last := n.band_state()
	var t := 0.0
	for i in 60:
		var w := 190.0 + (12.0 if i % 2 == 0 else -12.0)
		for k in 20:
			n.feed(_tm(t, w))
			t += 0.05
			if n.band_state() != last:
				changes += 1
				last = n.band_state()
	assert_eq(changes, 0)


func test_no_band_means_no_state() -> void:
	var n := HudRiderNumbers.new()
	n.push_power(0.0, 50.0)
	assert_false(n.in_band())
	assert_eq(n.band_state(), HudRiderNumbers.IN_BAND)
	n.set_band(100.0, 110.0)
	n.set_band(0.0, 0.0)
	assert_eq(n.band(), Vector2.ZERO)
	n.set_band(120.0, 100.0)
	assert_eq(n.band(), Vector2.ZERO, "a reversed band clears")


func test_heart_rate_has_three_states() -> void:
	var n := HudRiderNumbers.new()
	n.sensor_status_override = TrainerDevice.STATUS_DISCONNECTED
	n.feed(_tm(1.0, 100.0))
	assert_eq(n.heart_state(), HudRiderNumbers.HR_NONE, "no sensor, never seen")
	var live := _tm(2.0, 100.0)
	live.heart_rate_bpm = 151
	n.feed(live)
	assert_eq(n.heart_state(), HudRiderNumbers.HR_LIVE)
	assert_eq(n.heart_bpm(), 151)
	n.feed(_tm(3.0, 100.0))
	assert_eq(n.heart_state(), HudRiderNumbers.HR_DROPOUT, "0 after a live reading is a dropout")
	var known := HudRiderNumbers.new()
	known.sensor_status_override = TrainerDevice.STATUS_CONNECTING
	known.feed(_tm(1.0, 100.0))
	assert_eq(known.heart_state(), HudRiderNumbers.HR_DROPOUT, "a sensor at work reads 0 for now")


func test_low_cadence_warns_only_after_the_dwell_and_clears_with_a_margin() -> void:
	var n := HudRiderNumbers.new()
	n.ftp_w = 200.0
	_ride(n, 0.0, 1.0, 190.0, 62.0)
	assert_false(n.low_cadence(), "under the dwell")
	_ride(n, 1.05, 2.0, 190.0, 62.0)
	assert_true(n.low_cadence())
	_ride(n, 2.05, 2.5, 190.0, 71.0)
	assert_true(n.low_cadence(), "71 rpm is not clear yet")
	_ride(n, 2.55, 3.0, 190.0, 80.0)
	assert_false(n.low_cadence())


func test_low_cadence_needs_erg_at_sixty_percent() -> void:
	var n := HudRiderNumbers.new()
	n.ftp_w = 200.0
	var t := 0.0
	for i in 60:
		var tm := _tm(t, 100.0, 50.0)
		tm.applied_target_w = 119
		n.feed(tm)
		t += 0.05
	assert_false(n.rescue_armed(), "119 W is under 60% of 200 W")
	assert_false(n.low_cadence())
	var at := _tm(t, 100.0, 50.0)
	at.applied_target_w = 120
	n.feed(at)
	assert_true(n.rescue_armed(), "exactly 60% arms it")
	var sim := _tm(t + 0.05, 100.0, 50.0)
	sim.mode = Wl.SIM
	n.feed(sim)
	assert_false(n.rescue_armed(), "SIM never arms rescue")


func test_low_cadence_steps_aside_for_rescue_and_coasting() -> void:
	var n := HudRiderNumbers.new()
	_ride(n, 0.0, 2.0, 190.0, 50.0)
	assert_true(n.low_cadence())
	var r := _tm(2.05, 100.0, 50.0)
	r.rescue = true
	n.feed(r)
	assert_false(n.low_cadence(), "rescue has its own line")
	_ride(n, 2.1, 4.5, 190.0, 50.0)
	var c := _tm(4.55, 0.0, 0.0)
	c.coasting = true
	n.feed(c)
	assert_false(n.low_cadence(), "coasting has its own line")


func test_a_stale_cadence_raises_no_warning() -> void:
	var n := HudRiderNumbers.new()
	var t := 0.0
	for i in 60:
		var tm := _tm(t, 190.0, 0.0)
		tm.cadence_age_s = 4.0
		n.feed(tm)
		t += 0.05
	assert_true(n.cadence_stale())
	assert_false(n.low_cadence())


func test_wkg_needs_the_opt_in() -> void:
	assert_eq(HudRiderNumbers.opted_in_weight_kg(70.0), 70.0, "the override wins")
	assert_eq(HudRiderNumbers.opted_in_weight_kg(0.0), 0.0, "an override of 0 hides it")
	var s := AutoloadLookup.settings()
	if s != null and s.profile != null:
		var was := s.profile.show_wkg
		s.profile.show_wkg = false
		assert_eq(HudRiderNumbers.opted_in_weight_kg(), 0.0)
		s.profile.show_wkg = true
		assert_eq(HudRiderNumbers.opted_in_weight_kg(), s.profile.weight_kg)
		s.profile.show_wkg = was
	assert_gt(HudRiderNumbers.wprime_j(), 0.0)
