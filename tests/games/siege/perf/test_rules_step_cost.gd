extends GutTest
## Brief 4: a rules step takes <= 1 ms at the enemy cap, so a 55-minute shift simulates in
## <= 66 s. Measures SiegeRules.step on a mid-wave state kept at 150 enemies, as the median of
## 400 steps (a median ignores the odd hiccup of a busy machine).

const STEPS := 400
const BUDGET_US := 1000.0


func _inputs(st: SiegeState, tick: int) -> SiegeInputs:
	var inp := SiegeInputs.new()
	inp.tick = tick
	inp.t = 500.0 + tick * Wl.SIM_DT
	var ph := SiegePhaseInfo.new()
	ph.index = st.phase_index
	ph.kind = Wl.WORK
	ph.role = SiegeIds.ROLE_WAVE
	ph.number = 2
	ph.waves = 6
	ph.elapsed_s = 40.0
	ph.duration_s = 4000.0
	ph.remaining_s = 3960.0
	ph.plan_elapsed_s = inp.t
	inp.phase = ph
	for r in st.riders:
		var ri := SiegeRiderInput.new()
		ri.peer = r.peer
		ri.slot = r.slot
		ri.power_w = 230.0
		ri.p_eff_w = 280.0
		ri.cadence_rpm = 92.0
		ri.mode = Wl.ERG
		ri.planned_pct = 112.0
		ri.phase_mean_pct = 112.0
		inp.riders.append(ri)
	return inp


func test_a_rules_step_at_the_enemy_cap_takes_at_most_1_ms() -> void:
	var st := SiegeStressScene.build_state(150)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# One step to enter the phase (the wave opens), then measure.
	SiegeRules.step(st, _inputs(st, 0), Wl.SIM_DT)
	var us: Array[float] = []
	for i in STEPS:
		SiegeStressScene.refill(st, 150, rng)
		var inp := _inputs(st, i + 1)
		var t0 := Time.get_ticks_usec()
		SiegeRules.step(st, inp, Wl.SIM_DT)
		us.append(float(Time.get_ticks_usec() - t0))
	us.sort()
	var median := us[us.size() / 2]
	var p95 := us[int(us.size() * 0.95)]
	gut.p(
		(
			"rules step at the cap: median %.0f us, p95 %.0f us (budget %.0f us)"
			% [median, p95, BUDGET_US]
		)
	)
	assert_lte(median, BUDGET_US, "median step time in microseconds")
