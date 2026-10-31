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
const SessionKit := preload("res://tests/sdk/helpers/session_kit.gd")


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


## A depot split to a seat with a range_pct: the platform's own model (the phase closed at the elapsed
## time) reaches the warm-up's edge, so the split goes, and real time reaches it too (BRIEF 4.6.8).
func test_a_depot_split_reaches_the_warm_ups_edge_for_every_seat() -> void:
	for mission: String in ["ashfall_road", "ambush_15"]:
		var c := _content(mission)
		for slot: int in 3:
			var plan := _plan(c, slot)
			for seat: String in TankIds.SEATS:
				if str(plan.phase(0).meta.get("engine", "")) == seat:
					continue
				for elapsed: float in [40.0, 150.0, 290.0]:
					_depot_split(
						c, plan, seat, elapsed, "%s slot %d %.0f" % [mission, slot, elapsed]
					)


func _depot_split(
	c: TankContent, plan: EffortPlan, seat: String, elapsed: float, at: String
) -> void:
	var ri := _ri(plan, 0, elapsed)
	ri.plan_elapsed_s = elapsed
	var f := TankSeatPlan.follow(c, ri, seat, -1000.0, 1000.0, false)
	var where := "%s to %s" % [at, seat]
	assert_eq(int(f["action"]), TankSeatPlan.FOLLOW_SPLIT, where)
	if int(f["action"]) != TankSeatPlan.FOLLOW_SPLIT:
		return
	var rest: EffortPlan = f["plan"]
	var model := PlanValidator.split_model(TankSeatPlan.whole(plan, 0, rest), 0, elapsed)
	assert_true(bool(PlanValidator.validate(model)["ok"]), "the router's check " + where)
	var depot := float(c.segment(0)["duration_s"])
	assert_true(
		elapsed + Wl.SIM_DT + rest.phase(0).duration_s >= depot - 1e-6,
		"not short of the warm-up in real time " + where
	)


## The same split through the platform's own PhaseTracker and DirectiveRouter, not a model of them: every
## seat is accepted, the rest's end stays in the depot's phase, and the next segment (the first that can
## ask more than the warm-up's limit) starts at 300 s or later (BRIEF 4.6.8).
func test_the_real_router_takes_a_depot_split_and_the_warm_up_holds() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var from := str(plan.phase(0).meta["engine"])
	for seat: String in TankIds.SEATS:
		if seat != from:
			_real_depot_split(c, plan, seat, 150.0)
			_real_depot_split(c, plan, seat, 299.0)


func _real_depot_split(c: TankContent, plan: EffortPlan, seat: String, at_s: float) -> void:
	var root: Node = autofree(Node.new())
	var clock := SimClock.create()
	var tracker := PhaseTracker.new()
	tracker.add_rider(1, PlanValidator.finalize(plan))
	var router := DirectiveRouter.new()
	router.role = Wl.HOST
	router.tracker = tracker
	router.clock = clock
	router.slots = {1: SessionKit.human(1, 0, 200.0)}
	router.bind_riders({})
	router.bus = SessionKit.new_bus(root, "Bus")
	router.remote_send = func(_peer: int, _payload: Dictionary) -> void: pass
	router.telemetry_of = func(_peer: int) -> Variant: return null
	tracker.start()
	var advance := func(seconds: float) -> void:
		for _i in PhaseTracker.ticks(seconds):
			tracker.advance(clock.game_tick)
			router.flush(clock.game_tick + 1)
			tracker.update_modes(clock.game_tick + 1)
			clock.step()
	advance.call(at_s)
	var elapsed := tracker.elapsed_s(1)
	var ri := _ri(plan, 0, elapsed)
	ri.plan_elapsed_s = elapsed
	var f := TankSeatPlan.follow(c, ri, seat, -1000.0, elapsed, false)
	var where := "%s at %.0f s" % [seat, at_s]
	assert_eq(int(f["action"]), TankSeatPlan.FOLLOW_SPLIT, where)
	assert_true(router.split(1, f["plan"]), "the router takes it: " + where)
	advance.call(c.segment(0)["duration_s"] - elapsed + 1.0)
	assert_eq(tracker.index_of(1), 2, "the rest, then the next segment: " + where)
	var rest_row: Dictionary = tracker.history(1)[1]
	assert_gte(float(rest_row["end"]), 300.0, "the next segment starts past the warm-up: " + where)
	assert_lte(float(rest_row["end"]), 300.0 + 2.0 * Wl.SIM_DT, "and on time: " + where)


## Past the warm-up a split keeps the segment's real length to the tick.
func test_a_split_past_the_warm_up_ends_on_the_segments_tick() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var ri := _ri(plan, CHECKPOINT, 20.0)
	ri.plan_elapsed_s = 900.0
	var f := TankSeatPlan.follow(c, ri, TankIds.ENGINE_STEAM, -1000.0, 1000.0, false)
	assert_eq(int(f["action"]), TankSeatPlan.FOLLOW_SPLIT)
	var rest: EffortPlan = f["plan"]
	var seg_s := float(c.segment(CHECKPOINT)["duration_s"])
	assert_almost_eq(20.0 + Wl.SIM_DT + rest.phase(0).duration_s, seg_s, 1e-6)


## A whole Repairs plan runs through the validator on every mission, inside its 55-70 band.
func test_a_repairs_plan_passes_every_mission() -> void:
	for mission: String in ["ashfall_road", "ambush_15", "drill", "roam_10", "roam_30", "roam_60"]:
		var c := _content(mission)
		var whole := EffortPlan.new()
		for i in c.segments().size():
			whole.add(TankPlanBuilder.phase_for(c, c.segment(i), TankIds.ENGINE_REPAIR, i))
		assert_true(TankSeatPlan.check(whole), "%s: a whole plan on Repairs" % mission)
		for i in whole.size():
			var ph := whole.phase(i)
			if ph.mode == Wl.ERG and ph.kind == Wl.WORK:
				assert_eq(float(ph.range_pct[0]), 55.0, "%s phase %d" % [mission, i])
				assert_true(float(ph.range_pct[1]) <= 70.0, "%s phase %d" % [mission, i])


func test_repairs_follows_a_seat_move_as_the_gun_does() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var gun := _follow(c, plan, ADVANCE, 100.0, TankIds.ENGINE_DYNAMO, 45.0)
	var repair := _follow(c, plan, ADVANCE, 100.0, TankIds.ENGINE_REPAIR, 45.0)
	assert_eq(int(repair["action"]), int(gun["action"]))
	assert_eq(float(repair["wait_s"]), float(gun["wait_s"]))
	assert_eq((repair["plan"] as EffortPlan).phase(0).mode, Wl.ERG)
	assert_eq(str((repair["plan"] as EffortPlan).phase(0).meta["engine"]), TankIds.ENGINE_REPAIR)


## no_hold: a bot's split whose rest would outlast the segment's own min_s waits for the segment's end;
## while the segment's own min_s still covers it, or when the rest has no min_s of its own, it goes.
func test_a_bots_split_never_holds_the_segment() -> void:
	var c := _content("ambush_15")
	var plan := _plan(c, 0)
	var seg := int(plan.phase(1).meta["segment"])
	var seg_min := float(c.segment(seg)["min_s"])
	var seat := TankIds.ENGINE_REPAIR
	assert_eq(plan.phase(1).mode, Wl.SIM, "a SIM Advance for slot 0")
	var late := _ri(plan, 1, seg_min - 5.0)
	late.plan_elapsed_s = 400.0
	var human := TankSeatPlan.follow(c, late, seat, -1000.0, 1000.0, false, true, false)
	assert_eq(int(human["action"]), TankSeatPlan.FOLLOW_SPLIT, "a human's own move goes")
	assert_almost_eq((human["plan"] as EffortPlan).phase(0).min_s, 30.0, 1e-6)
	var bot := TankSeatPlan.follow(c, late, seat, -1000.0, 1000.0, false, true, true)
	assert_ne(int(bot["action"]), TankSeatPlan.FOLLOW_SPLIT, "a bot's waits")
	assert_eq(float(bot["wait_s"]), TankSeatPlan.WAIT_SEGMENT_END)
	var early := _ri(plan, 1, seg_min - 40.0)
	early.plan_elapsed_s = 400.0
	var soon := TankSeatPlan.follow(c, early, seat, -1000.0, 1000.0, false, true, true)
	assert_eq(int(soon["action"]), TankSeatPlan.FOLLOW_SPLIT, "inside the segment's own min_s")
	var same := TankSeatPlan.follow(
		c, late, TankIds.ENGINE_STEAM, -1000.0, 1000.0, false, true, true
	)
	assert_eq(int(same["action"]), TankSeatPlan.FOLLOW_SPLIT, "same mode, no hold")


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
