extends GutTest
## FishingPullScheduler (brief 2.3 "Load changes", 4.1 Directives): the pure scheduler driven by a
## fake fight loop against a model of the governor's ERG channel (replace on request, expire to the
## planned target). Every species x 25 seeds x FTP 100, 200, 300, 400 and 500 W; rescue and AFK at
## every ramp step of a mahi run and of a marlin jump. The opt-in sweep runs them at 500 seeds.

const H := preload("res://tests/games/fishing/plan/fishing_plan_harness.gd")
const SEEDS := 25


func _sweep(trip_id: String, species: Array, seeds: int) -> void:
	var c := H.content(trip_id)
	var fails: Array[String] = []
	var pulls := 0
	var runs := 0
	var above := 0.0
	for id: String in species:
		for seed in range(1, seeds + 1):
			var slot := H.species_slot(c, id, seed)
			var staggers: Array = []
			if seed % 2 == 0:
				var r := FishingRandom.derive(seed, 5, 5)
				staggers = [[r.range_f(5.0, slot.t_nom_s * 0.7), r.range_f(3.0, 45.0)]]
			for ftp: float in H.FTPS:
				var res := H.run_fight(slot, seed, ftp, staggers)
				fails.append_array(res["fails"])
				pulls += int(res["pulls"])
				runs += int(res["runs"])
				above += float(res["above105"])
	assert_eq(fails.size(), 0, "%s: %s" % [trip_id, "\n".join(fails.slice(0, 8))])
	assert_gt(pulls, 0, "%s: pull changes were sent" % trip_id)
	if species.has("mahi") or species.has("tuna") or species.has("marlin"):
		assert_gt(runs, 0, "%s: runs fired" % trip_id)
	if species.has("mahi") and trip_id != "base_60":
		assert_gt(above, 0.0, "mahi runs pass 105 %")


func test_mackerel_directives() -> void:
	_sweep("free_30", ["mackerel"], SEEDS)


func test_mahi_directives() -> void:
	_sweep("free_30", ["mahi"], SEEDS)


func test_tuna_directives() -> void:
	_sweep("free_30", ["tuna"], SEEDS)


func test_marlin_directives() -> void:
	_sweep("free_120", ["marlin"], SEEDS)


func test_base_60_directives_stay_at_or_below_100() -> void:
	_sweep("base_60", ["mackerel", "mahi"], SEEDS)
	var c := H.content("base_60")
	for seed in range(1, SEEDS + 1):
		assert_lte(H.species_slot(c, "mahi", seed).range_hi, 100.0, "base range top")


func test_threshold_tuna_directives() -> void:
	var c := H.content("threshold")
	var fails: Array[String] = []
	for seed in range(1, 11):
		var slot := FishingPreroll.roll(c.trip, c.species, seed, 0)[seed % 4]
		fails.append_array(H.run_fight(slot, seed, H.FTPS[seed % 5])["fails"])
	assert_eq(fails.size(), 0, "\n".join(fails.slice(0, 8)))


func test_e2e_mackerel_directives_stay_in_the_warmup_band() -> void:
	var c := H.content("e2e_2min")
	for seed in range(1, 11):
		var slot := FishingPreroll.roll(c.trip, c.species, seed, 0)[0]
		var res := H.run_fight(slot, seed, 250.0)
		assert_eq((res["fails"] as Array).size(), 0, "%s" % [res["fails"]])
		assert_lte(slot.range_hi, 65.0, "inside the 65 % warm-up cap")


func _stagger_steps(species: String, trip_id: String) -> void:
	var c := H.content(trip_id)
	var fails: Array[String] = []
	var cases := 0
	for seed in [3, 11]:
		var slot := H.species_slot(c, species, seed)
		for ftp: float in [100.0, 500.0]:
			var n := H.run_step_count(slot, seed, ftp)
			assert_gte(n, 1, "%s run sends steps" % species)
			for j in range(-1, n):
				for v: Array in [["rescue", 6.0], ["rescue", 45.0], ["afk", 15.0], ["afk", 70.0]]:
					fails.append_array(H.stagger_failures(slot, seed, ftp, j, v[1], v[0]))
					cases += 1
	assert_eq(fails.size(), 0, "\n".join(fails.slice(0, 8)))
	assert_gt(cases, 40, "%d cases" % cases)


func test_rescue_and_afk_at_each_ramp_step_of_a_mahi_run() -> void:
	_stagger_steps("mahi", "free_30")


func test_rescue_and_afk_at_each_ramp_step_of_a_marlin_jump() -> void:
	_stagger_steps("marlin", "free_120")


func test_init_lane_seeds_the_pull_stream() -> void:
	var ps := FishingPullState.new()
	FishingPullScheduler.init_lane(ps, 42, 2)
	var want := FishingRandom.derive(42, 2, FishingRandom.STREAM_PULL)
	assert_eq(ps.rng.state, want.state)
	assert_false(ps.to_dict().has("rng"), "the stream is not part of to_dict")


func test_ramp_steps_stretch_to_25_w_per_s() -> void:
	assert_eq(FishingPullScheduler.ramp_steps(90.0, 95.0, 100.0), 6, "5 W in 6 steps")
	assert_eq(FishingPullScheduler.ramp_steps(95.0, 90.0, 500.0), 6, "decreases keep 6 steps")
	assert_eq(FishingPullScheduler.ramp_steps(80.0, 110.0, 500.0), 12, "150 W: 12 steps of 12.5 W")
	assert_eq(FishingPullScheduler.ramp_steps(80.0, 110.0, 100.0), 6, "30 W fits 6 steps")


func test_a_pull_change_ramps_in_six_held_steps_half_a_second_apart() -> void:
	var c := H.content("free_30")
	var slot := H.species_slot(c, "mahi", 4)
	var ps := FishingPullState.new()
	FishingPullScheduler.init_lane(ps, 4, 0)
	FishingPullScheduler.begin(ps, slot, 100.0, 200.0, ps.rng)
	assert_between(ps.next_change_t, 108.0, 116.0, "first change 8-16 s in")
	var first_change := ps.next_change_t
	var times: Array[float] = []
	for tick in range(1, 400):
		var t := 100.0 + tick * 0.05
		for d: Dictionary in FishingPullScheduler.step(ps, slot, t, 200.0, ps.rng):
			assert_eq(d["reason"], "pull")
			assert_eq(d["duration_s"], 0.0)
			times.append(t)
	assert_gte(times.size(), 6)
	for i in range(1, 6):
		assert_almost_eq(times[i] - times[i - 1], 0.5, 1e-6, "0.5 s apart")
	assert_almost_eq(times[0], first_change, 0.051, "the ramp starts when the change is due")


func test_runs_count_down_to_one_expiry_and_skip_while_staggered() -> void:
	var c := H.content("free_30")
	var slot := H.species_slot(c, "mahi", 8)
	var ps := FishingPullState.new()
	FishingPullScheduler.init_lane(ps, 8, 0)
	FishingPullScheduler.begin(ps, slot, 0.0, 250.0, ps.rng)
	FishingPullScheduler.set_staggered(ps, true, 1.0)
	assert_false(FishingPullScheduler.start_run(ps, slot, 0, 1.0, 250.0), "skipped while staggered")
	assert_eq(ps.runs_skipped, 1)
	assert_true(
		FishingPullScheduler.step(ps, slot, 1.05, 250.0, ps.rng).is_empty(),
		"nothing while staggered"
	)
	FishingPullScheduler.set_staggered(ps, false, 2.0)
	assert_almost_eq(ps.paused_until_t, 12.0, 1e-6, "clock waits 10 s after the stagger")
	assert_true(FishingPullScheduler.start_run(ps, slot, 1, 2.0, 250.0))
	assert_true(ps.run_active)
	assert_almost_eq(ps.run_end_t, 2.0 + slot.run_dur_s(1), 1e-6)
	assert_true(FishingPullScheduler.run_blocked_by_gap(ps, slot, 3.0), "one run at a time")
	var ends: Array[float] = []
	for tick in range(41, 41 + 700):
		var t := tick * 0.05
		for d: Dictionary in FishingPullScheduler.step(ps, slot, t, 250.0, ps.rng):
			if d["reason"] == "run":
				ends.append(t + float(d["duration_s"]))
		if not ps.run_active:
			break
	assert_gte(ends.size(), 6)
	for e in ends:
		assert_almost_eq(e, 2.0 + slot.run_dur_s(1), 0.051, "every step expires at the run end")
	assert_false(ps.run_active, "the run ended")
	assert_almost_eq(ps.target_pct, slot.base_pct, 1e-6, "the channel is back at base")


func test_marlin_jumps_wait_90_s_between_starts() -> void:
	var c := H.content("free_120")
	var slot := H.species_slot(c, "marlin", 2)
	var ps := FishingPullState.new()
	FishingPullScheduler.init_lane(ps, 2, 0)
	FishingPullScheduler.begin(ps, slot, 0.0, 200.0, ps.rng)
	assert_false(FishingPullScheduler.run_blocked_by_gap(ps, slot, 1.0))
	assert_true(FishingPullScheduler.start_run(ps, slot, 0, 1.0, 200.0))
	assert_true(FishingPullScheduler.run_blocked_by_gap(ps, slot, 60.0), "inside 90 s")
	for tick in range(21, 1900):
		FishingPullScheduler.step(ps, slot, tick * 0.05, 200.0, ps.rng)
	assert_true(FishingPullScheduler.run_blocked_by_gap(ps, slot, 90.95), "still under 90 s")
	assert_false(
		FishingPullScheduler.run_blocked_by_gap(ps, slot, 91.0), "90 s after the last start"
	)


func test_above_105_is_held_to_30_s_per_run_and_90_s_per_fight() -> void:
	var slot := FishingPlanSlot.new()
	slot.species = "mahi"
	slot.run_kind = FishingSpeciesDef.RUN_RUN
	slot.base_pct = 90.0
	slot.change_pct = 8.0
	slot.range_lo = 82.8
	slot.range_hi = 110.0
	slot.max_s = 270.0
	slot.t_nom_s = 200.0
	slot.runs.assign([30.0, 110.0, 30.0, 110.0, 30.0, 110.0, 30.0, 110.0, 35.0, 110.0])
	var ps := FishingPullState.new()
	FishingPullScheduler.begin(ps, slot, 0.0, 200.0, ps.rng)
	var t := 0.0
	var peaks: Array[float] = []
	for k in 4:
		t += 40.0
		assert_true(FishingPullScheduler.start_run(ps, slot, k, t, 200.0))
		peaks.append(ps.run_peak_pct)
	assert_eq(peaks, [110.0, 110.0, 110.0, 105.0] as Array[float], "the 4th would pass 90 s")
	assert_almost_eq(ps.above_105_fight_s, 90.0, 1e-6)
	var ps2 := FishingPullState.new()
	FishingPullScheduler.begin(ps2, slot, 0.0, 200.0, ps2.rng)
	assert_true(FishingPullScheduler.start_run(ps2, slot, 4, 10.0, 200.0))
	assert_almost_eq(ps2.run_peak_pct, 105.0, 1e-6, "a 35 s run stays at 105 %")


func test_the_scheduler_is_deterministic() -> void:
	var c := H.content("free_30")
	var slot := H.species_slot(c, "tuna", 12)
	assert_eq(_trace(slot, 12), _trace(slot, 12), "same seed, same directives")
	assert_ne(_trace(slot, 12), _trace(slot, 13), "another seed, another schedule")


func test_end_stops_everything() -> void:
	var c := H.content("free_30")
	var slot := H.species_slot(c, "mahi", 1)
	var ps := FishingPullState.new()
	FishingPullScheduler.begin(ps, slot, 0.0, 200.0, ps.rng)
	FishingPullScheduler.start_run(ps, slot, 0, 1.0, 200.0)
	FishingPullScheduler.end(ps)
	assert_false(ps.run_active)
	assert_true(ps.queue.is_empty())


func _trace(slot: FishingPlanSlot, seed: int) -> Array:
	var ps := FishingPullState.new()
	FishingPullScheduler.init_lane(ps, seed, 0)
	FishingPullScheduler.begin(ps, slot, 0.0, 300.0, ps.rng)
	var out := []
	for tick in range(1, 2400):
		var t := tick * 0.05
		if tick == 600:
			FishingPullScheduler.start_run(ps, slot, 0, t, 300.0)
		for d: Dictionary in FishingPullScheduler.step(ps, slot, t, 300.0, ps.rng):
			out.append([t, d["target_pct"], d["duration_s"], d["reason"]])
	return out
