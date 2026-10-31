extends GutTest
## TankDirector's pattern 10, the Repairs seat's load (SPEC_TANK 3.6): {mode ERG, target_pct 55 + 15 x
## duty, reason "repair"} every 5 s in three sub-steps 1 s apart, <= 10 points an update, inside the
## phase's range_pct, never in the depot or checkpoints; and the flat grade under a tow (3.4). A crew of
## 4 with peer 4's plan set up for Repairs through every segment, as a seat move would leave it.

const H := preload("res://tests/games/tank/effort/tank_effort_harness.gd")

const DEPOT := 0
const ADV1 := 1
const GUN1 := 2
const CP1 := 3
const RATE := 10.0 / 3.0


func _h(mission: String = "ashfall_road") -> H:
	var h := H.new()
	h.build(4, mission)
	var plan := EffortPlan.new()
	var segs := h.content.segments()
	for i in segs.size():
		plan.add(TankPlanBuilder.phase_for(h.content, segs[i], TankIds.ENGINE_REPAIR, i))
	h.plans[4] = plan
	var r := h.state.rider(4)
	var ev: Array[Dictionary] = []
	TankSeats.land(h.state, r, TankIds.ENGINE_REPAIR, ev)
	return h


func _bay(h: H) -> TankRepairState:
	return h.state.station(TankIds.ENGINE_REPAIR) as TankRepairState


func test_the_target_is_55_plus_15_x_duty_inside_the_range() -> void:
	var c := TankFixtures.content()
	var ph := TankPlanBuilder.phase_for(c, c.segments()[ADV1], TankIds.ENGINE_REPAIR, ADV1)
	assert_eq(TankDirector.repair_target_pct(c, 0.0, ph), 55.0)
	assert_eq(TankDirector.repair_target_pct(c, 0.5, ph), 62.5)
	assert_eq(TankDirector.repair_target_pct(c, 1.0, ph), 70.0)
	assert_eq(TankDirector.repair_target_pct(c, 2.0, ph), 70.0, "duty is a share: 0..1")
	assert_eq(TankDirector.repair_goal_pct(c, 1.0, ph, 55.0), 65.0, "<= 10 points an update")
	var drill := TankFixtures.content("drill")
	var dp := TankPlanBuilder.phase_for(drill, drill.segments()[1], TankIds.ENGINE_REPAIR, 1)
	assert_eq(TankDirector.repair_target_pct(drill, 1.0, dp), 65.0, "the drill: 55..65")


## A full load in Stage 1's Advance: from the planned 55% to 70% in two updates, each in three
## sub-steps 1 s apart.
func test_a_full_load_climbs_in_three_sub_steps_per_update() -> void:
	var h := _h()
	_bay(h).duty = 1.0
	h.run_s(ADV1, 12.0)
	var rows := h.sent(4, "repair")
	var want := [
		55.0 + 10.0 / 3.0, 55.0 + 20.0 / 3.0, 65.0, 65.0 + 5.0 / 3.0, 65.0 + 10.0 / 3.0, 70.0
	]
	var ticks := [0, 20, 40, 100, 120, 140]
	assert_eq(rows.size(), 6)
	for i in rows.size():
		assert_eq(int(rows[i][0]), ticks[i], "sub-step %d tick" % i)
		assert_almost_eq(float(rows[i][1]["target_pct"]), want[i], 1e-9, "sub-step %d" % i)
		assert_eq(rows[i][1]["mode"], Wl.ERG)
		assert_eq(rows[i][1]["source"], "tank")
	assert_eq(h.sent(1, "repair"), [], "only the Repairs rider")


## An intact hull: the planned 55% stands and nothing is sent. The load falling: down <= 10 points an
## update.
func test_no_load_sends_nothing_and_a_falling_load_steps_down() -> void:
	var h := _h()
	_bay(h).duty = 0.0
	h.run_s(ADV1, 12.0)
	assert_eq(h.sent(4, "repair"), [])
	_bay(h).duty = 1.0
	h.run_s(ADV1, 15.0)
	_bay(h).duty = 0.0
	h.clear()
	h.run_s(ADV1, 15.0)
	var rows := h.sent(4, "repair")
	assert_almost_eq(float(rows[2][1]["target_pct"]), 60.0, 1e-9, "70 -> 60")
	assert_almost_eq(float(rows[-1][1]["target_pct"]), 55.0, 1e-9, "-> 55")


## Whatever the load does: <= 10/3 points a sub-step, sub-steps >= 1 s apart (<= 3.3% FTP/s, BRIEF
## 4.6.1), every target inside 55..70.
func test_the_slew_and_the_range() -> void:
	var h := _h()
	for i in roundi(300.0 / Wl.SIM_DT):
		_bay(h).duty = 0.5 + 0.5 * sin(float(i) * Wl.SIM_DT / 7.0)
		h.step(ADV1)
	var rows := h.sent(4, "repair")
	assert_gt(rows.size(), 20)
	var prev := 55.0
	var prev_t := -1000
	for r: Array in rows:
		var pct := float(r[1]["target_pct"])
		assert_between(pct, 55.0, 70.0)
		assert_lte(absf(pct - prev), RATE + 1e-9)
		assert_gte(int(r[0]) - prev_t, 20)
		prev = pct
		prev_t = int(r[0])


## Never in the depot or a checkpoint; in the gun line; the drill's skirmish stays in 55..65.
func test_it_only_runs_in_repair_phases_with_a_range() -> void:
	var h := _h()
	_bay(h).duty = 1.0
	h.run_s(DEPOT, 12.0)
	h.run_s(CP1, 12.0)
	assert_eq(h.sent(4, "repair"), [], "no repair load in the depot or a checkpoint")
	h.clear()
	h.run_s(GUN1, 6.0)
	assert_eq(h.sent(4, "repair").size(), 4, "the gun line: 0, 1, 2 and 5 s")
	var d := _h("drill")
	_bay(d).duty = 1.0
	d.run_s(0, 10.0)
	assert_eq(d.sent(4, "repair"), [], "drill depot")
	d.run_s(1, 20.0)
	assert_gt(d.sent(4, "repair").size(), 0)
	for r: Array in d.sent(4, "repair"):
		assert_between(float(r[1]["target_pct"]), 55.0, 65.0, "drill skirmish range")


## A refused sub-step does not move the director's idea of the target; on reserve nothing is sent, and
## back from reserve the first update starts from the plan's 55%.
func test_reserve() -> void:
	var h := _h()
	h.afk[4] = true
	_bay(h).duty = 1.0
	h.run_s(ADV1, 12.0)
	assert_eq(h.sent(4, "repair"), [], "on reserve: nothing")
	h.afk[4] = false
	h.run_s(ADV1, 6.0)
	var rows := h.sent(4, "repair")
	assert_gt(rows.size(), 0)
	assert_lte(float(rows[0][1]["target_pct"]), 55.0 + RATE + 1e-9, "from the plan's 55% again")


# --- A tow: flat ----------------------------------------------------------------------------------


func test_a_tow_sends_a_flat_grade_and_the_terrain_comes_back_after_it() -> void:
	var h := _h()
	h.state.hull.distance_m = 190.0
	h.state.hull.tow_s = 4.0
	h.run_s(ADV1, 2.0)
	var flat: Array = []
	for k in 4:
		flat.append([k * 10, 0.0])
	assert_eq(h.grades_of(1), flat, "flat every 0.5 s")
	assert_eq(h.grades_of(2), [], "only the rider on a game grade")
	h.clear()
	h.state.hull.tow_s = 0.0
	h.run_s(ADV1, 1.0)
	for row: Array in h.grades_of(1):
		assert_almost_eq(float(row[1]), 2.25, 1e-9, "the road again")


## Rules-only: a tow sends no phase change, replan, split or request of its own.
func test_a_tow_changes_nothing_else_for_the_riders() -> void:
	var quiet := _h()
	quiet.state.hull.distance_m = 190.0
	quiet.run_s(ADV1, 20.0)
	var towed := _h()
	towed.state.hull.distance_m = 190.0
	towed.state.hull.tow_s = 8.0
	towed.run_s(ADV1, 20.0)
	assert_eq(JSON.stringify(towed.requests), JSON.stringify(quiet.requests), "the same requests")
	assert_eq(towed.dirs().replans.size(), 0)
	assert_eq(towed.dirs().splits.size(), 0)
	assert_eq(towed.ended, [])
