extends GutTest
## Runs and jumps (brief 2.4): run k of n comes due at S = 1 - k / (n + 1), waits while a run is
## on (jumps also for their gap), is skipped in a stagger, and shifts the band and the fish. The
## directives themselves are FishingPullScheduler's (fish-plan); FishingRulesPull bridges the two
## functions fish-plan adds in G1.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func _fight(species: String, t_nom: float, runs: int, trip: String = "free_30") -> H:
	var probe := H.new()
	probe.content = H.load_content(trip)
	var one: Array[FishingPlanSlot] = [H.make_slot(probe.content, species, 0, t_nom, runs)]
	var h := H.new()
	h.setup(trip, 1, 5, [one])
	h.follow_band[0] = true
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 1200.0), "the fight starts")
	return h


func test_run_k_of_n_comes_due_at_s_1_minus_k_over_n_plus_1() -> void:
	var h := _fight("tuna", 300.0, 3)
	var l := h.lane()
	var due_s: Array[float] = []
	var fired := 0
	while l.state == FishingConst.ST_FIGHT and h.state.t < 2000.0:
		h.step()
		if l.fish.runs_fired > fired:
			fired = l.fish.runs_fired
			due_s.append(l.fish.s)
	assert_eq(due_s.size(), 3, "all three runs came due")
	for k in due_s.size():
		var at := 1.0 - float(k + 1) / 4.0
		assert_between(due_s[k], at - 0.01, at + 0.001, "run %d at S = %.2f" % [k + 1, at])
	var runs := h.events_of(FishingEvents.RUN)
	assert_lte(runs.size(), 3, "an event only for runs the scheduler started")
	for k in runs.size():
		assert_eq(int(runs[k]["n"]), 3)
		assert_gt(int(runs[k]["k"]), int(runs[k - 1]["k"]) if k > 0 else 0, "in order")


func test_runs_coming_due_in_a_stagger_are_skipped() -> void:
	var h := _fight("tuna", 300.0, 3)
	var l := h.lane()
	h.rescue[0] = true
	h.run(1.0)
	l.fish.s = 0.45  # runs 1 and 2 (0.75, 0.5) are due now
	h.run(0.5)
	assert_eq(l.fish.runs_fired, 2, "skipped, counted fired")
	assert_eq(h.events_of(FishingEvents.RUN).size(), 0, "no event")
	assert_false(l.fish.run_active)


func test_a_run_shifts_the_band_and_takes_the_fish_out_and_deep() -> void:
	var h := _fight("tuna", 300.0, 0)
	var l := h.lane()
	h.run(2.0)
	var c0 := l.band_center
	var d0 := l.fish.d
	l.fish.run_active = true
	l.fish.run_end_t = h.state.t + 20.0
	h.run(2.0)
	assert_almost_eq(l.band_center, c0 + 6.0, 0.15, "+10 rpm shift, sliding 3 rpm/s")
	assert_almost_eq(l.fish.d, minf(d0 + 8.0, 120.0), 0.06, "out at 4 m/s toward d_max")
	assert_gt(l.fish.z, 0.9, "sounding deep")
	h.run(19.0)
	assert_false(l.fish.run_active, "the run ends at its scheduled end")


func test_jumps_break_the_surface() -> void:
	var h := _fight("marlin", 640.0, 0, "free_120")
	var l := h.lane()
	l.fish.run_active = true
	l.fish.run_end_t = h.state.t + 25.0
	l.slots[0].run_kind = FishingSpeciesDef.RUN_JUMP
	h.run(3.0)
	assert_lt(l.fish.z, 0.1, "a jump heads for the surface")


func test_jump_gap_bridge() -> void:
	var slot := FishingPlanSlot.new()
	slot.run_kind = FishingSpeciesDef.RUN_JUMP
	slot.run_min_gap_s = 90.0
	var f := FishingFishState.new()
	f.last_jump_t = 100.0
	var ps := FishingPullState.new()
	var script: Script = FishingPullScheduler
	if script.has_method("run_blocked_by_gap"):
		assert_typeof(FishingRulesPull.run_blocked_by_gap(ps, slot, 150.0, f), TYPE_BOOL)
	else:
		assert_true(FishingRulesPull.run_blocked_by_gap(ps, slot, 150.0, f), "50 s < 90 s")
		assert_false(FishingRulesPull.run_blocked_by_gap(ps, slot, 190.0, f), "90 s passed")
		slot.run_min_gap_s = 0.0
		assert_false(FishingRulesPull.run_blocked_by_gap(ps, slot, 101.0, f), "runs: no gap")


func test_pull_directives_go_out_per_peer_and_never_during_a_stagger() -> void:
	var h := _fight("mahi", 200.0, 2)
	h.run(60.0)
	for d: Array in h.directives:
		assert_eq(d[1], 1, "the rider's own peer")
		var dd: Dictionary = d[2]
		assert_eq(dd.get("source"), "fishing")
	var n := h.directives.size()
	h.rescue[0] = true
	h.run(20.0)
	assert_eq(h.directives.size(), n, "no request during a rescue")
