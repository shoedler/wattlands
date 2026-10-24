extends GutTest
## FishingFakes.Clock, the GameHost-like phase clock module tests drive whole sessions with:
## duration and max_s ends, end_phase after min_s taking effect at the end of the tick (refused
## before), replans validated like the DirectiveRouter and swapped in at the next phase change,
## finished skipping to the cool-down, and telemetry following ERG requests.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")


func _game(content: String = "e2e_2min", humans: int = 1) -> FishingGame:
	return autofree(F.make_game(F.make_ctx(humans, 0, content)))


func test_a_whole_e2e_workout_runs_with_the_real_rules() -> void:
	var g := _game("e2e_2min", 2)
	var c := F.clock_for(g)
	assert_true(c.run_until_done(400.0))
	assert_eq(
		c.labels(1),
		[
			"FISHING_PHASE_RIDE_OUT",
			"FISHING_PHASE_TROLL",
			"FISHING_SPECIES_MACKEREL",
			"FISHING_PHASE_LANDING",
			"Cool-down"
		]
	)
	var by: Array = (
		c
		. changes
		. filter(func(ch: Dictionary) -> bool: return ch["peer"] == 1)
		. map(func(ch: Dictionary) -> String: return ch["ended_by"])
	)
	assert_eq(by[0], Wl.ENDED_DURATION)
	assert_eq(by[1], Wl.ENDED_DURATION)
	assert_has([Wl.ENDED_END_PHASE, Wl.ENDED_MAX_S], by[2], "the fight ends by landing or max_s")
	assert_eq(by[3], Wl.ENDED_DURATION)
	assert_between(
		c.tick * Wl.SIM_DT, 15.0 + 20.0 + 36.0 + 30.0 + 180.0, 15.0 + 20.0 + 70.0 + 30.0 + 180.1
	)
	assert_eq(g.state.riders[0].action, FishingConst.A_HOME, "the rider followed every phase")
	assert_eq(g.state.riders[0].fish_landed, 1, "the scheduled mackerel was landed")


func test_end_phase_is_refused_before_min_s_and_ends_the_phase_at_the_end_of_the_tick() -> void:
	var g := _game("roam_10")
	var c := F.clock_for(g)
	var d := g.ctx.directives as F.Directives
	assert_false(d.end_phase(1), "the drive-out is fixed")
	assert_eq(d.refused_ends, [[1, Wl.REFUSE_NOT_OPEN_ENDED]])
	c.run(300.0)
	assert_eq(c.index_of(1), 1, "the open-ended Roam")
	c.run(2.0)
	assert_false(d.end_phase(1), "2 s < min_s 5")
	assert_eq(d.refused_ends[-1], [1, Wl.REFUSE_MIN_S])
	c.run(4.0)
	assert_true(d.end_phase(1))
	assert_eq(c.index_of(1), 1, "still the Roam until the tick ends")
	c.step()
	assert_eq(c.index_of(1), 2)
	assert_eq(c.changes[-1]["ended_by"], Wl.ENDED_END_PHASE)
	var f := c.frame()
	assert_eq(f.phase_of(1).index, 2)
	assert_eq(f.phase_of(1).elapsed_s, 0.0, "the next frame starts the next phase")
	assert_eq(f.phase_of(1).prev_ended_by, Wl.ENDED_END_PHASE)
	assert_false(d.end_phase(1), "the cool-down is not open-ended")


func test_an_open_ended_phase_ends_at_max_s() -> void:
	var g := _game("e2e_2min")
	var plan := EffortPlan.new()
	plan.add(PlanPhase.erg(Wl.WARMUP, 50, 10, "a"))
	plan.add(PlanPhase.erg(Wl.WORK, 60, 4, "b").with_open(2, 5))
	var c := F.clock_for(g, {1: F.with_cooldown(plan)})
	c.run(10.0)
	assert_eq(c.index_of(1), 1)
	c.run(4.95)
	assert_eq(c.index_of(1), 1, "4.95 s of 5")
	c.step()
	assert_eq(c.index_of(1), 2)
	assert_eq(c.changes[-1]["ended_by"], Wl.ENDED_MAX_S)
	assert_almost_eq(float(c.changes[-1]["t"]), 15.0, 1e-6)


func test_a_replan_swaps_in_at_the_next_phase_change() -> void:
	var g := _game("roam_10")
	var c := F.clock_for(g)
	var d := g.ctx.directives as F.Directives
	c.run(306.0)
	var slot := FishingPreroll.roam_slot(
		g.content.species["snapper"], 0.5, 0, FishingRandom.derive(1, 0, 1), 0.0
	)
	var tail := FishingPlanBuilder.fight_tail(slot, 600.0)
	assert_true(d.replan(1, tail))
	assert_eq(d.replan_warnings, [[]], "validated with no warnings")
	assert_eq(c.index_of(1), 1, "nothing changes before the phase ends")
	assert_true(d.end_phase(1))
	c.step()
	assert_eq(c.index_of(1), 2)
	assert_eq(c.frame().phase_of(1).label, "FISHING_SPECIES_SNAPPER")
	assert_eq(c.frame().phase_of(1).mode, Wl.ERG)
	assert_eq(c.tracker.plan_of(1).size(), 2 + 3 + 1, "kept phases, the tail, the cool-down")


func test_an_invalid_replan_is_refused_and_keeps_the_plan() -> void:
	var g := _game("roam_10")
	var c := F.clock_for(g)
	var d := g.ctx.directives as F.Directives
	c.run(306.0)
	var bad := EffortPlan.of([PlanPhase.erg(Wl.WORK, 120, 400, "too long").with_open(30, 400)])
	assert_false(d.replan(1, bad))
	assert_eq(d.refused_replans.size(), 1)
	assert_eq(d.replans, [])
	assert_eq(c.tracker.plan_of(1).size(), 3, "drive-out, Roam, cool-down")


func test_finished_moves_every_rider_to_the_cool_down() -> void:
	var g := _game("roam_10", 2)
	var c := F.clock_for(g)
	c.run(30.0)
	g.finished.emit("trip_over")
	assert_eq(c.index_of(1), 0, "at the end of the tick")
	c.step()
	assert_eq(c.finished_reasons, ["trip_over"])
	for peer: int in [1, 2]:
		assert_true(c.tracker.is_cooldown(peer))
	assert_eq(c.changes[-1]["ended_by"], Wl.ENDED_FINISHED)


func test_telemetry_follows_the_latest_erg_request_until_the_phase_changes() -> void:
	var g := _game("e2e_2min")
	var c := F.clock_for(g)
	var p := g.ctx.players[0]
	c.run(1.0)
	assert_eq(c.frame().telemetry(1).applied_target_w, int(50.0 / 100.0 * p.ftp))
	g.ctx.directives.request(
		1, EffortDirective.from_dict({"mode": Wl.ERG, "target_pct": 60.0, "duration_s": 0.0})
	)
	c.step()
	var tm := c.frame().telemetry(1)
	assert_eq(tm.applied_target_w, int(0.6 * p.ftp))
	assert_eq(tm.power_w, float(int(0.6 * p.ftp)))
	assert_almost_eq(tm.p_eff_w, tm.power_w * 250.0 / p.ftp, 1e-6)
	c.run(15.0)
	assert_eq(c.index_of(1), 1)
	assert_eq(c.frame().telemetry(1).applied_target_w, int(0.55 * p.ftp), "the Troll's plan")
	c.cadence[1] = 72.0
	c.power_pct = 50.0
	c.paused[1] = true
	assert_eq(c.frame().telemetry(1).cadence_rpm, 72.0)
	assert_true(c.frame().telemetry(1).paused)
	assert_almost_eq(c.frame().telemetry(1).power_w, int(0.55 * p.ftp) * 0.5, 0.001)
