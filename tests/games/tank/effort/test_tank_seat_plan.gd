extends GutTest
## The seat switch's replan (v3, TankSeatPlan): the split's rest phase (the new seat's mode and
## targets for the rest of the segment, lap false, its offset and the segment's own min_s in the
## meta, a min_s that keeps the 60 s switch spacing, max_s the segment's), the later segments for
## the new seat, check() (the PlanValidator with no warning and every switch 60 s from the next at
## min_s and max_s), and every seat pair at legal times across every content.

const ADVANCE := 1
const GUN_LINE := 2
const BOSS := 10


func _content(mission: String = "ashfall_road") -> TankContent:
	return TankFixtures.content(mission)


func _plan(c: TankContent, slot: int) -> EffortPlan:
	return TankPlanBuilder.build(c, TankIds.TANK_LANDSHIP, slot)


func test_the_split_continues_the_segment_in_the_new_seat() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var rest := TankSeatPlan.tail(c, plan, ADVANCE, TankIds.ENGINE_DYNAMO, true, 100.0)
	assert_not_null(rest)
	assert_eq(rest.size(), c.segments().size() - ADVANCE, "the rest, then every later segment")
	var ph := rest.phase(0)
	assert_eq([ph.mode, ph.target_pct, ph.range_pct], [Wl.ERG, 55.0, [55.0, 100.0]], "the Gun's")
	assert_false(ph.lap, "the segment's lap goes on")
	assert_true(ph.open_ended)
	assert_eq(ph.max_s, 300.0 - 100.0, "the segment's own end")
	assert_eq(ph.min_s, TankSeatPlan.MODEL_GAP_S, "a mode switch, the gun line's ERG next: 30 s")
	assert_eq(ph.meta["offset_s"], 100.0)
	assert_eq(ph.meta["seg_min_s"], 90.0)
	assert_eq([ph.meta["segment"], ph.meta["engine"]], [ADVANCE, TankIds.ENGINE_DYNAMO])
	for i in range(1, rest.size()):
		assert_eq(int(rest.phase(i).meta["segment"]), ADVANCE + i)
		assert_eq(str(rest.phase(i).meta["engine"]), TankIds.ENGINE_DYNAMO)
		assert_true(rest.phase(i).lap)


## Both ends switch (the Gun's ERG to the Loader's SIM in a gun line, an ERG checkpoint next): the
## rest holds the segment's end 60 s, so the switches stay 60 s apart in real time too.
func test_a_split_between_two_switches_holds_60_s() -> void:
	var c := _content()
	var plan := _plan(c, 1)
	var rest := TankSeatPlan.tail(c, plan, GUN_LINE, TankIds.ENGINE_STEAM, true, 70.0)
	assert_eq(rest.phase(0).mode, Wl.SIM)
	assert_eq(rest.phase(1).mode, Wl.ERG, "the checkpoint")
	assert_eq(rest.phase(0).min_s, TankConst.SEAT_LOCK_S)
	assert_null(
		TankSeatPlan.tail(c, plan, GUN_LINE, TankIds.ENGINE_STEAM, true, 140.0),
		"40 s left before max_s: no room for 60"
	)


func test_a_split_with_no_mode_change_ends_with_the_segment() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	var rest := TankSeatPlan.tail(c, plan, ADVANCE, TankIds.ENGINE_STEAM, true, 100.0)
	var ph := rest.phase(0)
	assert_eq([ph.mode, ph.grade_source], [Wl.SIM, Wl.GRADE_FLAT], "the Loader's")
	assert_almost_eq(ph.min_s, TankSeatPlan.MIN_REST_S, 1e-9, "SIM to SIM holds nothing back")
	var early := TankSeatPlan.tail(c, plan, ADVANCE, TankIds.ENGINE_STEAM, true, 70.0)
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
	assert_null(TankSeatPlan.tail(c, plan, BOSS, TankIds.ENGINE_ARC, true, 340.0), "ERG, 20 s left")
	assert_not_null(TankSeatPlan.tail(c, plan, BOSS, TankIds.ENGINE_FEED, true, 340.0))


func test_check_holds_the_validator_and_the_60_s_spacing() -> void:
	var c := _content()
	var plan := _plan(c, 0)
	assert_true(TankSeatPlan.check(plan), "the built plan")
	var whole := TankSeatPlan.whole(
		plan, ADVANCE, TankSeatPlan.tail(c, plan, ADVANCE, "dynamo", true, 95.0)
	)
	assert_true(TankSeatPlan.check(whole))
	# An ERG rest phase of 20 s between the Drive's SIM phases: two switches 20 s apart, refused.
	var bad := EffortPlan.new()
	for i in ADVANCE + 1:
		bad.add(plan.phase(i).duplicate_phase())
	var squeezed := whole.phase(ADVANCE + 1).duplicate_phase()
	squeezed.min_s = 20.0
	bad.add(squeezed)
	for i in range(ADVANCE + 1, plan.size()):
		bad.add(plan.phase(i).duplicate_phase())
	assert_false(TankSeatPlan.check(bad), "two switches 20 s apart")
	assert_lt(TankSeatPlan.min_switch_gap(PlanValidator.finalize(bad), false), 60.0)


## Every seat of every slot to every other seat, splitting every open phase at its min_s and every
## 30 s after, and landing at every boundary, in every content: every move the rules would accept
## (can_move) gives a whole plan that passes check(); a second switch 60 s after the first does too.
func test_every_legal_move_passes_check_in_every_content() -> void:
	for content_id: String in TankFakes.manifest()["contents"]:
		var c := _content(content_id)
		var moves := 0
		for slot in TankIds.MAX_CREW:
			var plan := _plan(c, slot)
			var from := str(plan.phase(0).meta["engine"])
			for index in plan.size():
				var ph := plan.phase(index)
				for engine in TankIds.SEATS:
					if engine == from:
						continue
					var times: Array[float] = [0.0]
					if ph.open_ended:
						times = []
						var t := ph.min_s
						while t < minf(ph.max_s, 400.0):
							times.append(t)
							t += 30.0
					for e in times:
						var mv := TankSeatPlan.move_now(
							c, plan, index, e, 0.0, engine, ph.open_ended
						)
						if mv.is_empty():
							continue
						moves += 1
						var at := (
							"%s slot %d phase %d %s at %.0f" % [content_id, slot, index, engine, e]
						)
						var whole := TankSeatPlan.whole(plan, index, mv["plan"])
						assert_true(TankSeatPlan.check(whole), at)
						var v := PlanValidator.validate(whole)
						assert_eq(v["warnings"], [], at)
						if bool(mv["split"]):
							_second_move(c, whole, index + 1, from, at)
		assert_gt(moves, 0, content_id)


## A second move from the split's rest phase 60 s in (back to the first seat).
func _second_move(c: TankContent, plan: EffortPlan, index: int, back: String, at: String) -> void:
	var ph := plan.phase(index)
	var e := maxf(TankConst.SEAT_LOCK_S, ph.min_s)
	if e > ph.max_s:
		return
	var off := float(ph.meta.get("offset_s", 0.0))
	var mv := TankSeatPlan.move_now(c, plan, index, e, off, back, true)
	if mv.is_empty():
		return
	var whole := TankSeatPlan.whole(plan, index, mv["plan"])
	assert_true(TankSeatPlan.check(whole), at + " and back")
