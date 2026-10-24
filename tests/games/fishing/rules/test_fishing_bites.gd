extends GutTest
## Bites: Free Roam's hazard at depth (1 / 25 s in band, a quarter outside, none in the first
## 5 s, forced at 90 s, never while staggered or before the Roam phase's min_s); workouts' trolled
## lure (R_min, the hazard, the forced bite, last call) and the scheduled bite 4 s before a fixed
## Troll ends.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func _rider() -> FishingRiderState:
	var r := FishingRiderState.new()
	r.r_min_s = 120.0
	return r


func _roam_waiting(seed: int = 3) -> H:
	var h := H.new()
	h.setup("roam_10", 1, seed)
	h.follow_band[0] = true
	h.drive_w[0] = 220.0
	assert_true(h.run_until(func() -> bool: return h.rider().x_m >= 700.0, 600.0))
	h.drive_w[0] = 0.0
	assert_true(h.run_to_action(0, FishingConst.A_MENU, 60.0))
	h.drive_w[0] = 60.0
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_ACTION))
	h.step()
	assert_true(h.run_to_action(0, FishingConst.A_WAIT, 10.0))
	assert_true(h.run_to_phase(0, Wl.FREE, 400.0), "the Roam phase")
	return h


func test_the_workout_hazard_is_0_before_r_min_and_quartered_out_of_band() -> void:
	var r := _rider()
	r.in_band = true
	r.wait_t = 100.0
	assert_eq(FishingRules.bite_hazard(r), 0.0, "before R_min")
	r.wait_t = 130.0
	var h := (0.35 + 0.65 * FishingConst.TROLL_STRENGTH) / 90.0
	assert_almost_eq(FishingRules.bite_hazard(r), h, 1e-9)
	r.in_band = false
	assert_almost_eq(FishingRules.bite_hazard(r), h * 0.25, 1e-9)
	r.staggered = true
	assert_eq(FishingRules.bite_hazard(r), 0.0, "never while staggered")


func test_last_call_refuses_a_bite_whose_fight_would_overrun() -> void:
	var h := H.new()
	h.setup("base_60", 1, 3)
	var r := h.rider()
	var slot := H.make_slot(h.content, "mahi", 0, 150.0)
	var late := h.state.overtime_end_t - slot.max_s - FishingConst.SLOT_GAP_S
	assert_false(FishingRules.last_call_blocks(h.state, r, slot, late - 1.0))
	assert_true(FishingRules.last_call_blocks(h.state, r, slot, late + 1.0))
	r.fight_budget_used_s = h.state.fight_budget_s
	assert_true(FishingRules.last_call_blocks(h.state, r, slot, 400.0), "the fight budget is spent")


func test_base_trolls_until_r_min_then_bites_by_the_forced_time() -> void:
	var h := H.new()
	h.setup("base_60", 1, 3)
	h.follow_band[0] = true
	assert_true(h.run_to_phase(0, Wl.RECOVERY, 400.0), "the first Troll")
	var t0 := h.state.t
	var bit := func() -> bool: return h.events_of(FishingEvents.BITE).size() > 0
	assert_true(h.run_until(bit, 400.0))
	var waited := h.state.t - t0
	var latest := FishingConst.R_MIN_S + FishingConst.FORCED_BITE_AFTER_S + 0.1
	assert_between(waited, FishingConst.R_MIN_S, latest)
	assert_true(h.rider().hook_set, "the hook sets itself")
	assert_eq(h.violations, [] as Array[String])


func test_the_trolled_lure_runs_behind_the_moving_boat() -> void:
	var h := H.new()
	h.setup("base_60", 1, 3)
	assert_true(h.run_to_action(0, FishingConst.A_WAIT, 400.0))
	var r := h.rider()
	assert_almost_eq(r.lure_dx, -FishingConst.TROLL_DX_M, 1e-6, "behind the stern")
	assert_almost_eq(r.lure_depth, FishingConst.TROLL_DEPTH_M, 1e-6)
	assert_gt(r.v_mps, 1.0, "the boat keeps moving")


func test_scheduled_fish_bite_4_s_before_the_fixed_troll_ends() -> void:
	var h := H.new()
	h.setup("e2e_2min", 1, 3)
	var bit := func() -> bool: return h.events_of(FishingEvents.BITE).size() > 0
	assert_true(h.run_until(bit, 60.0))
	var ph := h.phase(0)
	assert_eq(ph.kind, Wl.RECOVERY)
	assert_almost_eq(ph.duration_s - h.ph_elapsed[0], FishingConst.SCHEDULED_BITE_LEAD_S, 0.06)
	assert_true(h.run_to_action(0, FishingConst.A_FIGHT, 5.0), "the Fight follows the Troll")
	assert_true(h.rider().fish.scheduled)


func test_no_roam_bite_in_the_first_5_s_at_depth() -> void:
	var h := _roam_waiting()
	var r := h.rider()
	r.wait_t = 0.0
	var bites := h.events_of(FishingEvents.BITE).size()
	h.run(FishingConst.ROAM_BITE_MIN_S - 0.1)
	assert_eq(h.events_of(FishingEvents.BITE).size(), bites)


func test_a_roam_bite_is_forced_at_90_s() -> void:
	var h := _roam_waiting(11)
	h.follow_band[0] = false
	h.cadence[0] = 40.0
	var r := h.rider()
	r.wait_t = 0.0
	var hooked := func() -> bool: return r.hook_set
	assert_true(h.run_until(hooked, FishingConst.ROAM_FORCED_BITE_S + 1.0))
	assert_lte(r.wait_t, FishingConst.ROAM_FORCED_BITE_S + 0.06)


func test_the_mean_roam_wait_is_about_25_s_in_band() -> void:
	var total := 0.0
	var n := 12
	for s in n:
		var h := _roam_waiting(100 + s)
		var r := h.rider()
		r.wait_t = 0.0
		h.run_until(func() -> bool: return r.hook_set, 100.0)
		total += r.wait_t
	assert_between(total / n, 12.0, 45.0, "mean %.1f s" % (total / n))


func test_no_roam_bite_while_paused() -> void:
	var h := _roam_waiting(4)
	var r := h.rider()
	r.wait_t = 0.0
	h.paused[0] = true
	h.run(100.0)
	assert_false(r.hook_set, "paused: no bite")
	assert_true(r.staggered)


func test_bites_open_needs_the_roam_phase_past_min_s_and_time_left() -> void:
	var st := FishingState.new()
	var r := FishingRiderState.new()
	var inp := FishingRiderInput.new()
	inp.phase_kind = Wl.FREE
	inp.phase_open_ended = true
	inp.phase_min_s = 5.0
	inp.phase_elapsed_s = 5.0
	assert_true(FishingRules.bites_open(st, r, inp))
	inp.phase_elapsed_s = 4.0
	assert_false(FishingRules.bites_open(st, r, inp), "before min_s")
	inp.phase_elapsed_s = 6.0
	inp.phase_kind = Wl.WARMUP
	assert_false(FishingRules.bites_open(st, r, inp), "the drive-out")
	inp.phase_kind = Wl.FREE
	st.time_up = true
	assert_false(FishingRules.bites_open(st, r, inp), "time is up")
