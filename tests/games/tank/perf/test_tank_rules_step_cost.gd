extends GutTest
## Brief 4: "The rules step takes <= 1 ms at the caps". Measures TankRules.step on the Citadel's cap
## fixture (16 enemies, 24 shells, three riders, a stage-2 Advance) kept at the caps every step, as
## the median of many steps (a median ignores the odd hiccup of a busy machine); the 95th
## percentile is printed. Also measures the director on the same inputs, which runs right after
## the rules every tick and must stay far below the budget.

const STEPS := 600
const BUDGET_US := 1000.0
const DIRECTOR_BUDGET_US := 250.0


func _inputs(tick: int) -> TankInputs:
	var slots := TankFixtures.slots(3)
	var plans := TankPlanBuilder.build_all(TankFixtures.content(), slots)
	var inp := TankInputs.from_frame(TankFixtures.frame(3), slots, plans, {}, {}, {})
	inp.tick = tick
	inp.t = tick * Wl.SIM_DT
	return inp


## Refills the state to the caps (what the rules killed or spent since the last step comes back).
func _refill(state: TankState, template: TankState) -> void:
	for i in TankConst.MAX_ENEMIES:
		if i >= state.enemies.size():
			state.enemies.append(
				TankEnemyState.new().load_dict(template.enemies[i].to_dict()) as TankEnemyState
			)
	for i in TankConst.MAX_SHELLS:
		if i >= state.shells.size():
			state.shells.append(
				TankShellState.new().load_dict(template.shells[i].to_dict()) as TankShellState
			)
	while state.enemies.size() > TankConst.MAX_ENEMIES:
		state.enemies.pop_back()
	while state.shells.size() > TankConst.MAX_SHELLS:
		state.shells.pop_back()


func _median_and_p95(us: Array[float]) -> Array[float]:
	us.sort()
	return [us[us.size() / 2], us[int(us.size() * 0.95)]]


func test_a_rules_step_at_the_caps_takes_at_most_1_ms() -> void:
	var template := TankFixtures.cap()
	var state := TankFixtures.cap()
	state.rng = RandomNumberGenerator.new()
	state.rng.seed = 11
	assert_eq(state.enemies.size(), TankConst.MAX_ENEMIES)
	assert_eq(state.shells.size(), TankConst.MAX_SHELLS)
	var inp := _inputs(0)
	TankRules.step(state, inp, Wl.SIM_DT)  # enter the segment, then measure
	var us: Array[float] = []
	for i in STEPS:
		_refill(state, template)
		inp.tick = i + 1
		inp.t = inp.tick * Wl.SIM_DT
		inp.phase.elapsed_s += Wl.SIM_DT
		var t0 := Time.get_ticks_usec()
		TankRules.step(state, inp, Wl.SIM_DT)
		us.append(float(Time.get_ticks_usec() - t0))
	var m := _median_and_p95(us)
	gut.p(
		(
			"rules step at the caps: median %.0f us, p95 %.0f us (budget %.0f us)"
			% [m[0], m[1], BUDGET_US]
		)
	)
	assert_lte(m[0], BUDGET_US, "median rules step in microseconds")


func test_the_director_step_stays_far_below_the_budget() -> void:
	var state := TankFixtures.cap()
	var ctx := TankFakes.make_ctx(3, 0, "ashfall_road", Wl.HOST, 1, 5)
	var content := TankFixtures.content()
	var plans := TankPlanBuilder.build_all(content, ctx.players)
	var director := TankDirector.new(ctx, content, plans)
	var inp := _inputs(0)
	var none: Array[Dictionary] = []
	director.step(state, inp, none)
	var us: Array[float] = []
	for i in STEPS:
		inp.tick = i + 1
		inp.t = inp.tick * Wl.SIM_DT
		(ctx.directives as TankFakes.Directives).t = inp.t
		(ctx.hud as TankFakes.Hud).t = inp.t
		var t0 := Time.get_ticks_usec()
		director.step(state, inp, none)
		us.append(float(Time.get_ticks_usec() - t0))
	var m := _median_and_p95(us)
	gut.p(
		(
			"director step: median %.0f us, p95 %.0f us (budget %.0f us)"
			% [m[0], m[1], DIRECTOR_BUDGET_US]
		)
	)
	assert_lte(m[0], DIRECTOR_BUDGET_US, "median director step in microseconds")


func test_the_snapshot_of_the_cap_state_encodes_within_4_kb() -> void:
	var snap := TankSnapshot.encode(TankFixtures.cap())
	assert_eq(TankSnapshotSchema.check(snap), "")
	assert_lte(TankSnapshotSchema.byte_size(snap), TankConst.SNAPSHOT_MAX_BYTES)
