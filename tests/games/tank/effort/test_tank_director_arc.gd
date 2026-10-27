extends GutTest
## TankDirector's pattern 2, the arc generator's load (brief 2.3): {mode ERG, target_pct 65 + 15 x
## duty, reason "arc"} every 5 s in three sub-steps 1 s apart, <= 10 points an update, inside the
## phase's range_pct, never in the depot or checkpoints; the drill's skirmish clamps it to 55..65.
## The Bastion (crew 4) with rotation on: in stage 1 peer 4 works the arc generator.

const H := preload("res://tests/games/tank/effort/tank_effort_harness.gd")

const DEPOT := 0
const ADV1 := 1
const GUN1 := 2
const CP1 := 3
const BOSS := 10
const RATE := 10.0 / 3.0


func _h(mission: String = "ashfall_road") -> H:
	var h := H.new()
	h.build(4, mission)
	return h


func _arc(h: H) -> TankArcState:
	return h.state.station(TankIds.ENGINE_ARC) as TankArcState


func _dict(pct: float) -> Dictionary:
	return {"mode": Wl.ERG, "target_pct": pct, "duration_s": 0.0, "reason": "arc", "source": "tank"}


func test_the_arc_rider_is_peer_4_in_stage_1() -> void:
	var h := _h()
	assert_eq(h.peer_on(TankIds.ENGINE_ARC, ADV1), 4)


func test_the_target_is_65_plus_15_x_duty_inside_the_range() -> void:
	var c := TankFixtures.content()
	var plan := TankPlanBuilder.build(c, TankIds.TANK_BASTION, 3, true)
	var ph := plan.phase(ADV1)
	assert_eq(TankDirector.arc_target_pct(c, 0.0, ph), 65.0)
	assert_eq(TankDirector.arc_target_pct(c, 0.5, ph), 72.5)
	assert_eq(TankDirector.arc_target_pct(c, 1.0, ph), 80.0)
	assert_eq(TankDirector.arc_target_pct(c, 2.0, ph), 80.0, "duty is a share: 0..1")
	assert_eq(TankDirector.arc_goal_pct(c, 1.0, ph, 65.0), 75.0, "<= 10 points an update")
	var drill := TankFixtures.content("drill")
	var dp := TankPlanBuilder.build(drill, TankIds.TANK_BASTION, 3, false).phase(1)
	assert_eq(TankDirector.arc_target_pct(drill, 1.0, dp), 65.0, "the drill: 55..65")
	assert_eq(TankDirector.arc_target_pct(drill, 0.0, dp), 65.0, "65 is inside 55..65")


## A full arc load in Stage 1's Advance: from the planned 65% to 80% in two updates, each in three
## sub-steps 1 s apart.
func test_a_full_load_climbs_in_three_sub_steps_per_update() -> void:
	var h := _h()
	_arc(h).duty = 1.0
	h.run_s(ADV1, 12.0)
	var rows := h.sent(4, "arc")
	var want := [65.0 + 10.0 / 3.0, 65.0 + 20.0 / 3.0, 75.0, 75.0 + 5.0 / 3.0, 75.0 + 10.0 / 3.0, 80.0]
	var ticks := [0, 20, 40, 100, 120, 140]
	assert_eq(rows.size(), 6)
	for i in rows.size():
		assert_eq(int(rows[i][0]), ticks[i], "sub-step %d tick" % i)
		assert_almost_eq(float(rows[i][1]["target_pct"]), want[i], 1e-9, "sub-step %d" % i)
		var got: Dictionary = rows[i][1]
		var keys := got.keys()
		keys.sort()
		assert_eq(keys, ["duration_s", "mode", "reason", "source", "target_pct"])
	assert_eq(rows[0][1]["reason"], "arc")
	assert_eq(h.sent(1, "arc"), [], "only the arc rider")


## No load: the planned 65% stands, nothing is sent. The load falling: down <= 10 points an update.
func test_no_load_sends_nothing_and_a_falling_load_steps_down() -> void:
	var h := _h()
	_arc(h).duty = 0.0
	h.run_s(ADV1, 12.0)
	assert_eq(h.sent(4, "arc"), [])
	_arc(h).duty = 1.0
	h.run_s(ADV1, 15.0)
	_arc(h).duty = 0.0
	h.clear()
	h.run_s(ADV1, 15.0)
	var rows := h.sent(4, "arc")
	assert_almost_eq(float(rows[2][1]["target_pct"]), 70.0, 1e-9, "80 -> 70")
	assert_almost_eq(float(rows[-1][1]["target_pct"]), 65.0, 1e-9, "-> 65")


## Whatever the load does: <= 10/3 points a sub-step, sub-steps >= 1 s apart (<= 3.3% FTP/s), every
## target inside 65..80 (BRIEF 4.6.1, 4.6.2).
func test_the_arc_slew_and_range() -> void:
	var h := _h()
	for i in roundi(300.0 / Wl.SIM_DT):
		_arc(h).duty = 0.5 + 0.5 * sin(float(i) * Wl.SIM_DT / 7.0)
		h.step(ADV1)
	var rows := h.sent(4, "arc")
	assert_gt(rows.size(), 20)
	var prev := 65.0
	var prev_t := -1000
	for r: Array in rows:
		var pct := float(r[1]["target_pct"])
		assert_between(pct, 65.0, 80.0)
		assert_lte(absf(pct - prev), RATE + 1e-9)
		assert_gte(int(r[0]) - prev_t, 20)
		prev = pct
		prev_t = int(r[0])


## Never in the depot or a checkpoint; in the gun line and the boss for the arc rider (rotation
## moves it: the boss's arc rider is slot 0); the drill's skirmish stays in 55..65.
func test_the_arc_load_only_runs_in_arc_phases_with_a_range() -> void:
	var h := _h()
	_arc(h).duty = 1.0
	h.run_s(DEPOT, 12.0)
	h.run_s(CP1, 12.0)
	for r: Array in h.requests:
		assert_ne(str(r[2].get("reason")), "arc", "no arc load in the depot or a checkpoint")
	h.clear()
	h.run_s(GUN1, 6.0)
	assert_eq(h.sent(4, "arc").size(), 4, "the arc gun line: 0, 1, 2 and 5 s")
	h.clear()
	h.run_s(BOSS, 6.0)
	var boss_arc := h.peer_on(TankIds.ENGINE_ARC, BOSS)
	assert_eq(boss_arc, 1, "rotation: slot 0 works the arc generator at the boss")
	assert_gt(h.sent(boss_arc, "arc").size(), 0)
	var d := _h("drill")
	_arc(d).duty = 1.0
	d.run_s(0, 10.0)
	assert_eq(d.sent(4, "arc"), [], "drill depot")
	d.run_s(1, 20.0)
	for r: Array in d.sent(4, "arc"):
		assert_between(float(r[1]["target_pct"]), 55.0, 65.0, "drill skirmish range")


## T7's shape: a load above 47% lifts the applied target past 72% within 10 s; once the fight ends
## the duty decays over 10 s and the target is back at <= 68% well within 60 s.
func test_t7_a_fight_lifts_the_target_and_its_end_brings_it_back_within_60_s() -> void:
	var h := _h()
	var arc := _arc(h)
	for i in roundi(60.0 / Wl.SIM_DT):
		arc.note_fire(h.tick, true)
		h.step(ADV1)
	var rows := h.sent(4, "arc")
	var above := rows.filter(func(r: Array) -> bool: return float(r[1]["target_pct"]) > 72.0)
	assert_lte(int(above[0][0]), roundi(10.0 / Wl.SIM_DT), "past 72% within 10 s")
	var end_tick := h.tick
	for i in roundi(60.0 / Wl.SIM_DT):
		arc.note_fire(h.tick, false)
		h.step(ADV1)
	var back := h.sent(4, "arc").filter(
		func(r: Array) -> bool: return int(r[0]) > end_tick and float(r[1]["target_pct"]) <= 68.0
	)
	assert_gt(back.size(), 0)
	assert_lte((int(back[0][0]) - end_tick) * Wl.SIM_DT, 60.0, "<= 68% within 60 s of the end")


## A refused arc sub-step does not move the director's idea of the target; on reserve nothing is sent.
func test_reserve_and_refusal() -> void:
	var h := _h()
	h.afk[4] = true
	_arc(h).duty = 1.0
	h.run_s(ADV1, 12.0)
	assert_eq(h.sent(4, "arc"), [], "on reserve: nothing")
	h.afk[4] = false
	h.run_s(ADV1, 6.0)
	var rows := h.sent(4, "arc")
	assert_gt(rows.size(), 0)
	assert_lte(float(rows[0][1]["target_pct"]), 65.0 + RATE + 1e-9, "from the plan's 65% again")
	assert_eq(_dict(70.0)["reason"], "arc")
