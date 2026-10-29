extends GutTest
## How a rider's trainer follows its seat (0.3.1, TankSeatPlan): the split's rest phase (the new
## seat's mode and targets for the rest of the segment, lap false, its offset and the segment's own
## min_s in the meta, a min_s that keeps the 30 s switch spacing, max_s the segment's; fixed phases
## too), the later segments for the new seat, check() (the PlanValidator with no warning, the
## current phase at the length it ran for a split), follow() (an instant same-mode move, a deferred
## ERG <-> SIM switch at 30 s, a switch held for the segment's end, back and forth), and every seat
## pair at many times across every content.

const DEPOT := 0
const ADVANCE := 1
const GUN_LINE := 2
const CHECKPOINT := 3
const BOSS := 10


func _content(mission: String = "ashfall_road") -> TankContent:
	return TankFixtures.content(mission)


func _plan(c: TankContent, slot: int) -> EffortPlan:
	return TankPlanBuilder.build(c, TankIds.TANK_LANDSHIP, slot)


## A rider input in phase `index` of `plan`, `elapsed` s into it.
func _ri(plan: EffortPlan, index: int, elapsed: float) -> TankRiderInput:
	var ri := TankRiderInput.new()
	ri.plan = plan
	ri.phase_index = index
	ri.phase_elapsed_s = elapsed
	ri.phase_kind = plan.phase(index).kind
	ri.phase_mode = plan.phase(index).mode
	return ri


## follow() for `seat` from phase `index` of `plan`, `elapsed` s in, the last switch `since` s ago.
func _follow(
	c: TankContent,
	plan: EffortPlan,
	index: int,
	elapsed: float,
	seat: String,
	since: float,
	hold_end: bool = false,
	allow_split: bool = true
) -> Dictionary:
	return TankSeatPlan.follow(
		c, _ri(plan, index, elapsed), seat, 1000.0 - since, 1000.0, hold_end, allow_split
	)


func test_the_split_continues_the_segment_in_the_new_seat() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var rest := TankSeatPlan.tail(c, plan, ADVANCE, TankIds.ENGINE_DYNAMO, true, 100.0, 100.0)
	assert_not_null(rest)
	assert_eq(rest.size(), c.segments().size() - ADVANCE, "the rest, then every later segment")
	var ph := rest.phase(0)
	assert_eq([ph.mode, ph.target_pct, ph.range_pct], [Wl.ERG, 55.0, [55.0, 100.0]], "the Gun's")
	assert_false(ph.lap, "the segment's lap goes on")
	assert_true(ph.open_ended)
	assert_eq(ph.max_s, 300.0 - 100.0, "the segment's own end")
	assert_eq(ph.min_s, TankSeatPlan.MODEL_GAP_S, "a phase that starts with a switch: 30 s")
	assert_eq(ph.meta["offset_s"], 100.0)
	assert_eq(ph.meta["seg_min_s"], 90.0)
	assert_eq([ph.meta["segment"], ph.meta["engine"]], [ADVANCE, TankIds.ENGINE_DYNAMO])
	for i in range(1, rest.size()):
		assert_eq(int(rest.phase(i).meta["segment"]), ADVANCE + i)
		assert_eq(str(rest.phase(i).meta["engine"]), TankIds.ENGINE_DYNAMO)
		assert_true(rest.phase(i).lap)


## Both ends switch (the Gun's ERG to the Loader's SIM in a gun line, an ERG checkpoint next): the
## rest holds the segment's end 30 s, so the switches stay 30 s apart in real time too.
func test_a_split_between_two_switches_holds_30_s() -> void:
	var c := _content()
	var plan := _plan(c, 1)
	var rest := TankSeatPlan.tail(c, plan, GUN_LINE, TankIds.ENGINE_STEAM, true, 70.0, 70.0)
	assert_eq(rest.phase(0).mode, Wl.SIM)
	assert_eq(rest.phase(1).mode, Wl.ERG, "the checkpoint")
	assert_eq(rest.phase(0).min_s, TankConst.SWITCH_GAP_S)
	assert_null(
		TankSeatPlan.tail(c, plan, GUN_LINE, TankIds.ENGINE_STEAM, true, 160.0, 160.0),
		"20 s left before max_s: no room for 30"
	)


## 0.3.1: a fixed phase splits too (DirectiveSink.split): the depot's rest for the Gun keeps its
## ramp from where it stands, and a checkpoint's rest is the same ERG 50% for every seat.
func test_a_fixed_phase_splits_into_a_fixed_rest() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var depot := float(c.segment(DEPOT)["duration_s"])
	var rest := TankSeatPlan.tail(c, plan, DEPOT, TankIds.ENGINE_DYNAMO, true, 100.0, 100.0)
	var ph := rest.phase(0)
	assert_false(ph.open_ended)
	assert_eq(ph.duration_s, depot - 100.0)
	assert_eq(ph.mode, Wl.ERG)
	var full := TankPlanBuilder.phase_for(c, c.segment(DEPOT), TankIds.ENGINE_DYNAMO, DEPOT)
	assert_almost_eq(ph.target_pct, full.planned_pct_at(100.0), 1e-6, "the ramp from where it is")
	assert_eq(ph.ramp_to_pct, full.ramp_to_pct)
	assert_true(TankSeatPlan.check(TankSeatPlan.whole(plan, DEPOT, rest), DEPOT, 100.0))
	var cp := TankSeatPlan.tail(c, plan, CHECKPOINT, TankIds.ENGINE_STEAM, true, 20.0, 20.0)
	assert_eq([cp.phase(0).mode, cp.phase(0).duration_s], [Wl.ERG, 40.0])


## Free roam: the rest after a move can split again (the game's time up still reads the meta's
## seg_min_s).
func test_a_roam_rest_can_split_again() -> void:
	var c := _content("roam_30")
	var plan := _plan(c, 1)
	var rest := TankSeatPlan.tail(c, plan, 1, TankIds.ENGINE_STEAM, true, 300.0, 300.0)
	assert_not_null(rest)
	assert_lt(rest.phase(0).min_s, TankConst.SWITCH_GAP_S + 1e-6, "not the roam's 25 minutes")
	assert_eq(float(rest.phase(0).meta["seg_min_s"]), float(c.segment(1)["min_s"]))
	var whole := TankSeatPlan.whole(plan, 1, rest)
	var f := _follow(c, whole, 2, 70.0, TankIds.ENGINE_DYNAMO, 70.0)
	assert_eq(int(f["action"]), TankSeatPlan.FOLLOW_SPLIT, "back to the Gun 70 s on")


func test_a_split_with_no_mode_change_ends_with_the_segment() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var rest := TankSeatPlan.tail(c, plan, ADVANCE, TankIds.ENGINE_STEAM, true, 100.0, 100.0)
	var ph := rest.phase(0)
	assert_eq([ph.mode, ph.grade_source], [Wl.SIM, Wl.GRADE_FLAT], "the Loader's")
	assert_almost_eq(ph.min_s, TankSeatPlan.MIN_REST_S, 1e-9, "SIM to SIM holds nothing back")
	var early := TankSeatPlan.tail(c, plan, ADVANCE, TankIds.ENGINE_STEAM, true, 70.0, 70.0)
	assert_almost_eq(early.phase(0).min_s, 20.0, 1e-9, "the segment's own min_s left")


func test_the_boundary_landing_is_the_later_segments_only() -> void:
	var c := _content()
	var plan := _plan(c, 1)
	var later := TankSeatPlan.tail(c, plan, 0, TankIds.ENGINE_STEAM, false, 0.0)
	assert_eq(later.size(), c.segments().size() - 1)
	assert_eq(str(later.phase(0).meta["engine"]), TankIds.ENGINE_STEAM)
	assert_true(later.phase(0).lap)
	assert_null(
		TankSeatPlan.tail(c, plan, BOSS, TankIds.ENGINE_STEAM, false, 0.0),
		"after the last segment only the cool-down is left"
	)


func test_a_split_that_cannot_fit_before_max_s_is_none() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	assert_null(
		TankSeatPlan.tail(c, plan, BOSS, TankIds.ENGINE_ARC, true, 340.0, 340.0), "20 s left"
	)
	assert_not_null(TankSeatPlan.tail(c, plan, BOSS, TankIds.ENGINE_FEED, true, 340.0, 340.0))


## check(): the PlanValidator on the split model (the current phase at the length it ran).
func test_check_holds_the_validator_and_the_30_s_spacing() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	assert_true(TankSeatPlan.check(plan), "the built plan")
	var rest := TankSeatPlan.tail(c, plan, ADVANCE, "dynamo", true, 95.0, 95.0)
	var whole := TankSeatPlan.whole(plan, ADVANCE, rest)
	assert_true(TankSeatPlan.check(whole, ADVANCE, 95.0))
	# Back to Drive (SIM) 20 s into the Gun's rest: two switches 20 s apart, refused.
	var back := TankSeatPlan.tail(c, whole, ADVANCE + 1, "diesel", true, 115.0, 20.0)
	var w2 := TankSeatPlan.whole(whole, ADVANCE + 1, back)
	assert_false(TankSeatPlan.check(w2, ADVANCE + 1, 20.0), "two switches 20 s apart")
	var later := TankSeatPlan.tail(c, whole, ADVANCE + 1, "diesel", true, 125.0, 30.0)
	var w3 := TankSeatPlan.whole(whole, ADVANCE + 1, later)
	assert_true(TankSeatPlan.check(w3, ADVANCE + 1, 30.0), "30 s apart")


# --- follow() --------------------------------------------------------------------------------------


## A move between seats of the same mode is a split at once, even a second after a switch.
func test_a_same_mode_move_splits_at_once() -> void:
	var c := _content()
	var plan := _plan(c, 1)
	var f := _follow(c, plan, GUN_LINE, 1.0, TankIds.ENGINE_ARC, 1.0)
	assert_eq(int(f["action"]), TankSeatPlan.FOLLOW_SPLIT)
	assert_eq([f["wait_s"], f["mode_to"]], [0.0, ""])
	var rest: EffortPlan = f["plan"]
	var ph := rest.phase(0)
	assert_eq([ph.mode, str(ph.meta["engine"])], [Wl.ERG, TankIds.ENGINE_ARC])
	var sim := _follow(c, _plan(c, 0), ADVANCE, 5.0, TankIds.ENGINE_FEED, 5.0)
	assert_eq(int(sim["action"]), TankSeatPlan.FOLLOW_SPLIT, "Drive to the Secondaries, SIM to SIM")


## An ERG <-> SIM move within 30 s of the rider's last switch waits; at 30 s it splits.
func test_a_cross_mode_move_waits_for_30_s_since_the_last_switch() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var f := _follow(c, plan, ADVANCE, 100.0, TankIds.ENGINE_DYNAMO, 10.0)
	assert_eq(int(f["action"]), TankSeatPlan.FOLLOW_WAIT)
	assert_almost_eq(float(f["wait_s"]), 20.0, 1e-6)
	assert_eq(f["mode_to"], Wl.ERG)
	assert_null(f["plan"])
	var due := _follow(c, plan, ADVANCE, 120.0, TankIds.ENGINE_DYNAMO, 30.0)
	assert_eq(int(due["action"]), TankSeatPlan.FOLLOW_SPLIT, "30 s since the last switch")
	var long_ago := _follow(c, plan, ADVANCE, 100.0, TankIds.ENGINE_DYNAMO, 400.0)
	assert_eq(int(long_ago["action"]), TankSeatPlan.FOLLOW_SPLIT)


## A switch that the segment's end would follow within 30 s (a gun line about to reach max_s, the
## checkpoint's ERG next) waits for the segment's end: the later segments carry the new seat.
func test_a_switch_due_near_the_boundary_waits_for_it() -> void:
	var c := _content()
	var plan := _plan(c, 1)
	var max_s := float(c.segment(GUN_LINE)["max_s"])
	var f := _follow(c, plan, GUN_LINE, max_s - 25.0, TankIds.ENGINE_STEAM, 400.0)
	assert_eq(int(f["action"]), TankSeatPlan.FOLLOW_BOUNDARY)
	assert_eq(f["wait_s"], TankSeatPlan.WAIT_SEGMENT_END)
	assert_eq(f["mode_to"], Wl.SIM)
	var later: EffortPlan = f["plan"]
	assert_eq(int(later.phase(0).meta["segment"]), GUN_LINE + 1)
	assert_eq(str(later.phase(0).meta["engine"]), TankIds.ENGINE_STEAM)
	var waits := _follow(c, plan, GUN_LINE, max_s - 45.0, TankIds.ENGINE_STEAM, 10.0)
	assert_eq(int(waits["action"]), TankSeatPlan.FOLLOW_BOUNDARY, "at 30 s only 25 s are left")
	var done := _follow(c, plan, GUN_LINE, 70.0, TankIds.ENGINE_STEAM, 400.0, true)
	assert_eq(int(done["action"]), TankSeatPlan.FOLLOW_BOUNDARY, "the objective is done")
	var ending := _follow(c, plan, GUN_LINE, 70.0, TankIds.ENGINE_ARC, 400.0, true, false)
	assert_eq(int(ending["action"]), TankSeatPlan.FOLLOW_BOUNDARY, "no split as the segment ends")


## Back and forth: back on the trainer's seat nothing waits; later segments a boundary replan gave
## another seat come back to it.
func test_moving_back_cancels_a_waiting_switch() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var wait := _follow(c, plan, ADVANCE, 100.0, TankIds.ENGINE_DYNAMO, 10.0)
	assert_eq(int(wait["action"]), TankSeatPlan.FOLLOW_WAIT)
	var back := _follow(c, plan, ADVANCE, 101.0, TankIds.ENGINE_DIESEL, 11.0)
	assert_eq(int(back["action"]), TankSeatPlan.FOLLOW_NONE)
	assert_eq([back["wait_s"], back["mode_to"]], [0.0, ""])
	var later := TankSeatPlan.tail(c, plan, ADVANCE, TankIds.ENGINE_DYNAMO, false, 0.0)
	var moved := TankSeatPlan.whole(plan, ADVANCE, later)
	var restore := _follow(c, moved, ADVANCE, 102.0, TankIds.ENGINE_DIESEL, 12.0)
	assert_eq(int(restore["action"]), TankSeatPlan.FOLLOW_BOUNDARY)
	var again: EffortPlan = restore["plan"]
	assert_eq(str(again.phase(0).meta["engine"]), TankIds.ENGINE_DIESEL)


## Every seat of every slot to every other seat at many times of every phase, in every content: every
## split follow() sends passes check() on the platform's split model, and every boundary replan on
## its replan model.
func test_every_follow_passes_check_in_every_content() -> void:
	for content_id: String in TankFakes.manifest()["contents"]:
		var c := _content(content_id)
		var sent := 0
		for slot in TankIds.MAX_CREW:
			var plan := _plan(c, slot)
			var from := str(plan.phase(0).meta["engine"])
			for index in plan.size():
				var ph := plan.phase(index)
				var end_s := minf(ph.max_s if ph.open_ended else ph.duration_s, 400.0)
				for engine in TankIds.SEATS:
					if engine != from:
						sent += _follow_all(c, plan, index, end_s, engine, content_id, slot)
		assert_gt(sent, 0, content_id)


func _follow_all(
	c: TankContent,
	plan: EffortPlan,
	index: int,
	end_s: float,
	engine: String,
	content_id: String,
	slot: int
) -> int:
	var sent := 0
	var e := 0.0
	while e < end_s:
		for since: float in [5.0, 45.0]:
			var f := _follow(c, plan, index, e, engine, since)
			var action := int(f["action"])
			var at := "%s slot %d phase %d %s at %.0f" % [content_id, slot, index, engine, e]
			if action == TankSeatPlan.FOLLOW_SPLIT:
				sent += 1
				assert_true(
					TankSeatPlan.check(TankSeatPlan.whole(plan, index, f["plan"]), index, e), at
				)
			elif action == TankSeatPlan.FOLLOW_BOUNDARY:
				sent += 1
				assert_true(TankSeatPlan.check(TankSeatPlan.whole(plan, index, f["plan"])), at)
		e += 40.0
	return sent
