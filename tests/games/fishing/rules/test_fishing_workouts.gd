extends GutTest
## Workouts on the endless map: the ride out drives, each Troll moves the boat with the lure out,
## the plan's fish hooks, Fight and Landing, the next Troll; Base cruises once its fish are spent
## and ends with trip_over; scheduled workouts end at their last Landing.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func test_workouts_run_on_the_endless_map() -> void:
	var h := H.new()
	h.setup("threshold", 2, 3)
	assert_true(h.state.world.endless)
	assert_false(h.state.roam)
	assert_eq(h.violations, [] as Array[String])


func test_the_ride_out_drives_out_to_sea() -> void:
	var h := H.new()
	h.setup("base_60", 1, 3)
	h.run(60.0)
	assert_eq(h.rider().action, FishingConst.A_DRIVE)
	assert_gt(h.rider().x_m, 150.0)
	assert_eq(h.rider().heading, 1)


func test_ride_out_tips_go_to_humans_every_45_s() -> void:
	var h := H.new()
	h.setup("base_60", 2, 3, [], 1)
	h.run(100.0)
	var keys: Array = h.toasts.map(func(t: Array) -> String: return t[1])
	assert_eq(keys, ["FISHING_TIP_1", "FISHING_TIP_2"])
	for t: Array in h.toasts:
		assert_eq(int(t[3]), 1, "the human only")


func test_a_threshold_tuna_lands_and_the_next_troll_casts_again() -> void:
	var h := H.new()
	h.setup("threshold", 1, 3)
	h.follow_band[0] = true
	assert_true(h.run_to_action(0, FishingConst.A_LAND, 1200.0))
	assert_true(h.run_to_phase(0, Wl.RECOVERY, 40.0), "the next Troll")
	assert_eq(h.rider().action, FishingConst.A_CAST)
	assert_eq(h.events_of(FishingEvents.LANDED).size(), 1)
	assert_eq(h.rider().target_sp, FishingConst.species_index("tuna"))


func test_e2e_runs_to_its_cool_down_without_finished() -> void:
	var h := H.new()
	h.setup("e2e_2min", 2, 3)
	h.follow_band[0] = true
	h.follow_band[1] = true
	h.run(160.0)
	assert_eq(h.events_of(FishingEvents.LANDED).size(), 2)
	assert_eq(h.finished, "", "scheduled workouts end with their plan")
	assert_eq(h.rider().action, FishingConst.A_HOME)
	assert_eq(h.rider().heading, 1, "the workout boat keeps going")


func test_base_ends_with_trip_over_after_fishing_time() -> void:
	var h := H.new()
	var probe := H.new()
	probe.content = H.load_content("base_60")
	var one: Array[FishingPlanSlot] = [H.make_slot(probe.content, "mackerel", 0, 60.0)]
	h.setup("base_60", 1, 3, [one])
	h.follow_band[0] = true
	assert_true(h.run_to_action(0, FishingConst.A_LAND, 1200.0))
	assert_true(h.run_to_phase(0, Wl.RECOVERY, 40.0))
	assert_eq(h.rider().action, FishingConst.A_DRIVE, "no fish left: cruising")
	assert_eq([h.rider().pub_lo, h.rider().pub_hi], [0, 0])
	h.state.play_end_t = h.state.t + 1.0
	h.run(2.0)
	assert_eq(h.finished, "trip_over")


func test_workout_fights_score_double_hookups_but_roam_fights_do_not() -> void:
	var st := FishingState.new()
	st.roam = true
	for i in 2:
		var r := FishingRiderState.new()
		r.slot = i
		r.action = FishingConst.A_FIGHT
		r.fish.sp = 0
		st.riders.append(r)
	var out := FishingStepOut.new()
	for k in 400:
		FishingFight.team_step(st, 0.05, out)
	assert_eq(st.hookup_level, 2)
	assert_eq(st.riders[0].hookup_count, 1, "Free Roam is competitive")
	assert_eq(out.events.size(), 0)
