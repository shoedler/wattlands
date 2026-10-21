extends GutTest
## In band (BRIEF 3.7): ERG power within +-5% of the applied target; Rolling road power
## within 76-105% FTP; FREE sprints cadence >= 60 rpm; rescue and AFK are out of band.

const U := preload("res://tests/games/workout/workout_test_util.gd")


func _rider(ftp: float = 200.0, verified: bool = true) -> WorkoutRiderState:
	var slot := U.players(1, 0, ftp)[0]
	slot.ftp_verified = verified
	return WorkoutRiderState.from_slot(slot)


func _tel(
	power: float, cadence: float = 90.0, mode: String = Wl.ERG, applied: int = 0
) -> Telemetry:
	var t := Telemetry.new()
	t.power_w = power
	t.cadence_rpm = cadence
	t.mode = mode
	t.applied_target_w = applied
	return t


func _ps(p: PlanPhase, elapsed: float = 0.0) -> PhaseState:
	var ps := PhaseState.new()
	ps.index = 0
	ps.kind = p.kind
	ps.mode = p.mode
	ps.elapsed_s = elapsed
	ps.planned_pct = p.planned_pct_at(elapsed) if p.mode == Wl.ERG else 0.0
	return ps


func test_erg_band_edges() -> void:
	assert_true(WorkoutRules.erg_in_band(200.0, 200.0))
	assert_true(WorkoutRules.erg_in_band(210.0, 200.0), "+5% inclusive")
	assert_true(WorkoutRules.erg_in_band(190.0, 200.0), "-5% inclusive")
	assert_false(WorkoutRules.erg_in_band(210.5, 200.0))
	assert_false(WorkoutRules.erg_in_band(189.5, 200.0))
	assert_false(WorkoutRules.erg_in_band(0.0, 0.0), "no target, not in band")


func test_rolling_road_band_edges() -> void:
	var band := [76.0, 105.0]
	assert_true(WorkoutRules.sim_in_band(152.0, 200.0, band), "76% inclusive")
	assert_true(WorkoutRules.sim_in_band(210.0, 200.0, band), "105% inclusive")
	assert_false(WorkoutRules.sim_in_band(151.0, 200.0, band))
	assert_false(WorkoutRules.sim_in_band(211.0, 200.0, band))


func test_sprint_cadence_edge() -> void:
	assert_true(WorkoutRules.sprint_in_band(60.0))
	assert_false(WorkoutRules.sprint_in_band(59.9))


func test_erg_uses_the_applied_target() -> void:
	var p := PlanPhase.erg(Wl.WORK, 90.0, 600.0, "x")
	var r := _rider()
	# The governor applied 150 W (for example a slew or a clamp): 150 +- 5% is in band.
	assert_true(WorkoutRules.in_band(p, _ps(p), _tel(155.0, 90.0, Wl.ERG, 150), r, [76.0, 105.0]))
	assert_false(WorkoutRules.in_band(p, _ps(p), _tel(180.0, 90.0, Wl.ERG, 150), r, [76.0, 105.0]))


func test_erg_falls_back_to_the_planned_target() -> void:
	var p := PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "x").with_ramp(65.0)
	var verified := _rider(200.0, true)
	# Halfway through the ramp: 57.5% of 200 W = 115 W.
	assert_true(WorkoutRules.in_band(p, _ps(p, 150.0), _tel(115.0), verified, []))
	assert_false(WorkoutRules.in_band(p, _ps(p, 150.0), _tel(100.0), verified, []))
	# Unverified FTP: x0.85 -> 97.75 W.
	var unverified := _rider(200.0, false)
	assert_true(WorkoutRules.in_band(p, _ps(p, 150.0), _tel(98.0), unverified, []))
	# Still in SIM during a ramped SIM->ERG switch: the planned target decides.
	assert_true(WorkoutRules.in_band(p, _ps(p, 150.0), _tel(115.0, 90.0, Wl.SIM, 0), verified, []))


func test_sim_work_and_free_phases() -> void:
	var road := PlanPhase.sim(Wl.WORK, Wl.GRADE_FLAT, 1800.0, "road").with_course([[0.0, 1.0]])
	var sprint := PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30.0, "sprint")
	var r := _rider()
	assert_true(WorkoutRules.in_band(road, _ps(road), _tel(180.0, 90.0, Wl.SIM), r, [76.0, 105.0]))
	assert_false(WorkoutRules.in_band(road, _ps(road), _tel(250.0, 90.0, Wl.SIM), r, [76.0, 105.0]))
	assert_true(
		WorkoutRules.in_band(sprint, _ps(sprint), _tel(50.0, 65.0, Wl.SIM), r, [76.0, 105.0]),
		"sprint: cadence only"
	)
	assert_false(
		WorkoutRules.in_band(sprint, _ps(sprint), _tel(400.0, 55.0, Wl.SIM), r, [76.0, 105.0])
	)


func test_rescue_afk_and_disconnects_are_out_of_band() -> void:
	var p := PlanPhase.erg(Wl.WORK, 50.0, 600.0, "x")
	var r := _rider()
	var t := _tel(100.0, 90.0, Wl.ERG, 100)
	assert_true(WorkoutRules.in_band(p, _ps(p), t, r, []))
	t.rescue = true
	assert_false(WorkoutRules.in_band(p, _ps(p), t, r, []), "rescue at 50% FTP is not compliance")
	t.rescue = false
	t.afk = true
	assert_false(WorkoutRules.in_band(p, _ps(p), t, r, []))
	t.afk = false
	t.connected = false
	assert_false(WorkoutRules.in_band(p, _ps(p), t, r, []))


func test_time_in_band_counts_per_interval_and_not_in_the_cooldown() -> void:
	var g := U.game("e2e", U.players(1))
	var half := func(slot: PlayerSlot, p: PlanPhase, ps: PhaseState, tick: int) -> Dictionary:
		var v := U.compliant(slot, p, ps)
		# Out of band for the second half of every phase.
		if ps.elapsed_s >= p.duration_s / 2.0:
			v["power_w"] = 0.0
			v["cadence_rpm"] = 0.0
		return v
	U.ride(g, half)
	var r := g.state.rider(1)
	for i in 3:
		assert_almost_eq(r.interval_fraction(i), 0.5, 0.01, "interval %d half in band" % i)
	assert_almost_eq(r.ride_s, 120.0, 0.001, "the cool-down is not counted")
	assert_almost_eq(r.tib_fraction(), 0.5, 0.01)
	assert_false(r.intervals.has(3), "no interval stats for the cool-down")
	g.free()
