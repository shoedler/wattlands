extends GutTest
## FishingFakes.Clock, the GameHost-like phase clock module tests drive whole trips with:
## duration and max_s ends, end_phase after min_s taking effect at the end of the tick (refused
## before), finished skipping to the cool-down, and telemetry following ERG requests.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")


func _game(content: String = "e2e_2min", humans: int = 1) -> FishingGame:
	return autofree(F.make_game(F.make_ctx(humans, 0, content)))


func test_a_whole_e2e_trip_runs_with_the_stub_rules() -> void:
	var g := _game("e2e_2min", 2)
	var c := F.clock_for(g)
	assert_true(c.run_until_done(400.0))
	assert_eq(
		c.labels(1),
		[
			"FISHING_PHASE_RIDE_OUT",
			"FISHING_PHASE_REEL_1",
			"FISHING_PHASE_MACKEREL_1",
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
	assert_eq(g.state.lanes[0].state, FishingConst.ST_HOME, "the lane followed every phase")


func test_end_phase_is_refused_before_min_s_and_ends_the_phase_at_the_end_of_the_tick() -> void:
	var g := _game("free_20")
	var c := F.clock_for(g)
	var d := g.ctx.directives as F.Directives
	c.run(300.0)
	assert_eq(c.index_of(1), 1, "the open-ended Reel")
	c.run(60.0)
	assert_false(d.end_phase(1), "60 s < min_s 120")
	assert_eq(d.refused_ends, [[1, Wl.REFUSE_MIN_S]])
	c.run(60.0)
	assert_true(d.end_phase(1))
	assert_eq(c.index_of(1), 1, "still the Reel until the tick ends")
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


func test_finished_moves_every_rider_to_the_cool_down() -> void:
	var g := _game("free_20", 2)
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
	c.run(15.0)
	assert_eq(c.index_of(1), 1)
	assert_eq(c.frame().telemetry(1).applied_target_w, int(0.55 * p.ftp), "the Reel's plan")
	c.cadence[1] = 72.0
	c.power_pct = 50.0
	assert_eq(c.frame().telemetry(1).cadence_rpm, 72.0)
	assert_almost_eq(c.frame().telemetry(1).power_w, int(0.55 * p.ftp) * 0.5, 0.001)
