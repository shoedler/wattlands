extends GutTest
## The jig (Free Roam's wait): the lure comes home to the boat over JIG_HOME_S and is recast
## there; holding the lure band at JIG_FTP_FRAC of FTP or more bites sooner (hazard 1 / 10 s after the 5 s minimum: a 15 s wait,
## else 1 / 25 s in band and a quarter of that out of it). SIM throughout: nothing here asks
## the trainer for load.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


## A human in roam_10 waiting at depth, pedaling `watts` and following the lure band.
func _waiting(watts: float, seed: int = 3) -> H:
	var h := H.new()
	h.setup("roam_10", 1, seed)
	h.follow_band[0] = true
	h.drive_w[0] = 220.0
	assert_true(h.run_until(func() -> bool: return h.rider().x_m >= 700.0, 600.0))
	h.drive_w[0] = 0.0
	assert_true(h.run_to_action(0, FishingConst.A_MENU, 60.0))
	h.drive_w[0] = watts
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_ACTION))
	h.step()
	assert_true(h.run_to_action(0, FishingConst.A_WAIT, 10.0))
	assert_true(h.run_to_phase(0, Wl.FREE, 400.0), "the Roam phase")
	return h


func _rider(ftp: float = 200.0) -> FishingRiderState:
	var r := FishingRiderState.new()
	r.ftp = ftp
	r.in_band = true
	r.power_w = FishingConst.JIG_FTP_FRAC * ftp
	return r


func test_the_jig_hazard_is_1_over_15_s_in_band_at_40_percent_ftp() -> void:
	var r := _rider()
	assert_true(FishingRules.jig_on(r), "exactly 40 % counts")
	assert_almost_eq(FishingRules.wait_hazard(r), 1.0 / FishingConst.JIG_BITE_MEAN_S, 1e-9)
	assert_eq(FishingConst.JIG_BITE_MEAN_S, 10.0)


func test_under_40_percent_the_old_hazard_stands_and_out_of_band_a_quarter() -> void:
	var r := _rider()
	r.power_w = 0.39 * r.ftp
	assert_false(FishingRules.jig_on(r))
	assert_almost_eq(FishingRules.wait_hazard(r), 1.0 / FishingConst.ROAM_BITE_MEAN_S, 1e-9)
	r.power_w = r.ftp
	r.in_band = false
	assert_false(FishingRules.jig_on(r), "out of the band the power does not count")
	assert_almost_eq(
		FishingRules.wait_hazard(r),
		FishingConst.HAZARD_OUT_OF_BAND / FishingConst.ROAM_BITE_MEAN_S,
		1e-9
	)


func test_the_jig_threshold_follows_the_riders_own_ftp() -> void:
	var r := _rider(300.0)
	r.power_w = 119.0
	assert_false(FishingRules.jig_on(r))
	r.power_w = 120.0
	assert_true(FishingRules.jig_on(r))


func test_the_lure_comes_home_over_40_s() -> void:
	var h := _waiting(100.0)
	var r := h.rider()
	r.wait_t = -100000.0  # this fish never bites
	var dx0 := absf(r.jig_dx0)
	assert_gt(dx0, 5.0, "cast out to the hint")
	h.step()
	var t0 := r.jig_t
	h.run(20.0 - t0)
	assert_almost_eq(absf(r.lure_dx), dx0 * 0.5, dx0 * 0.02, "halfway after 20 s")
	assert_eq(r.action, FishingConst.A_WAIT)
	h.run(19.0)
	assert_lt(absf(r.lure_dx), dx0 * 0.05, "at the boat by 40 s")
	assert_eq(r.action, FishingConst.A_WAIT)
	assert_eq(h.events_of(FishingEvents.BITE).size(), 0)


func test_it_recasts_at_the_boat_to_the_same_spot_and_keeps_waiting() -> void:
	var h := _waiting(100.0)
	var r := h.rider()
	r.wait_t = -100000.0
	var dx0 := r.jig_dx0
	var depth := r.lure_target_depth
	var casts := h.events_of(FishingEvents.CAST).size()
	assert_true(h.run_until(func() -> bool: return r.action == FishingConst.A_CAST, 45.0), "recast")
	assert_almost_eq(r.lure_dx, dx0, 1e-6, "back out to the cast's spot")
	assert_eq(r.lure_depth, 0.0, "it dives again")
	assert_eq(h.events_of(FishingEvents.CAST).size(), casts + 1, "the cast cue goes out again")
	var waited := r.wait_t
	assert_true(h.run_to_action(0, FishingConst.A_WAIT, 10.0), "and waits again")
	assert_almost_eq(r.lure_target_depth, depth, 1e-6)
	assert_almost_eq(r.lure_depth, depth, 1e-6)
	assert_gte(r.wait_t, waited, "the wait keeps counting toward the forced bite")
	assert_lt(r.jig_t, 1.0)


func test_confirm_reels_a_jigging_lure_in_to_the_menu() -> void:
	var h := _waiting(100.0)
	var r := h.rider()
	r.wait_t = -100000.0
	h.run(10.0)
	assert_gt(r.jig_t, 9.0)
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_ACTION))
	h.step()
	assert_eq(r.action, FishingConst.A_MENU, "confirm reels in")
	assert_eq(r.lure_dx, 0.0)


func test_a_jig_never_asks_the_trainer_for_load() -> void:
	var h := _waiting(100.0)
	var r := h.rider()
	r.wait_t = -100000.0
	var directives := h.directives.size()
	var replans := h.replans.size()
	h.run(100.0)
	assert_eq(h.directives.size(), directives, "no new directive while jigging")
	assert_eq(h.replans.size(), replans, "no replan")
	assert_eq(h.violations, [] as Array[String])


func test_holding_the_jig_bites_in_about_15_s_and_not_holding_in_about_30_s() -> void:
	var held := 0.0
	var loose := 0.0
	var n := 60
	for s in n:
		var a := _waiting(100.0, 200 + s)
		var ra := a.rider()
		ra.wait_t = 0.0
		a.run_until(func() -> bool: return ra.hook_set, 100.0)
		held += ra.wait_t
		var b := _waiting(40.0, 200 + s)
		var rb := b.rider()
		rb.wait_t = 0.0
		b.run_until(func() -> bool: return rb.hook_set, 100.0)
		loose += rb.wait_t
	held /= n
	loose /= n
	assert_between(held, 12.5, 17.5, "jigging: 5 s at depth, then 1 / 10 s: %.1f s" % held)
	assert_between(loose, 24.0, 36.0, "not jigging: 5 s, then 1 / 25 s: %.1f s" % loose)
	assert_lt(held, loose, "the jig bites sooner")


func test_the_forced_bite_still_comes_at_90_s_of_waiting_across_recasts() -> void:
	var h := _waiting(100.0, 11)
	h.follow_band[0] = false
	h.cadence[0] = 40.0
	var r := h.rider()
	r.wait_t = 0.0
	var hooked := func() -> bool: return r.hook_set
	assert_true(h.run_until(hooked, 130.0), "out of band the forced bite lands")
	assert_lte(r.wait_t, FishingConst.ROAM_FORCED_BITE_S + 0.06)
