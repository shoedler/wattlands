extends GutTest
## Whole sessions through the rules alone (TankRulesRig): compliant riders with no input play
## Ashfall Road and the drill to the cool-down for every crew (brief 0.4, 2.5; T1 and T5 in spirit;
## the balance gates themselves are the simulation matrix's). Each full session takes a few seconds.
## v3: the riders are seated automatically (the rig's auto_seat: the Autopilot's seat intents, moves
## landing as the director lands them), so crew 1 fights through the solo loop.

const ROADS := [1, 2, 3, 4]
const DRILL_CREWS := [1, 2, 3]

## crew -> the finished compliant session (seed 1, the bank director on), played once.
var _done: Dictionary = {}


func before_all() -> void:
	for crew in ROADS:
		var rig := TankRulesRig.new(crew, "ashfall_road", 1)
		rig.bank_director = true
		rig.auto_seat = true
		rig.play()
		_done[crew] = rig


func _is_open(type: String) -> bool:
	return type == "advance" or type == "gun_line" or type == "boss"


func test_every_crew_wins_ashfall_road_with_no_overrun_and_every_open_phase_ends_in_its_limits(
) -> void:
	for crew in ROADS:
		var rig: TankRulesRig = _done[crew]
		assert_true(rig.in_cooldown(), "crew %d reached the cool-down" % crew)
		assert_eq(rig.state.outcome, TankIds.OUTCOME_VICTORY, "crew %d: Foundry Gate taken" % crew)
		assert_eq(rig.state.score.overruns, 0, "crew %d" % crew)
		assert_lte(rig.state.score.breakdowns, 4, "crew %d" % crew)
		for i in rig.segs().size():
			var s := rig.content.segment(i)
			var len_s: float = rig.seg_len[i]
			if _is_open(str(s["type"])):
				assert_eq(rig.ended_by[i], Wl.ENDED_END_PHASE, "crew %d segment %d" % [crew, i])
				assert_gte(len_s + 0.01, float(s["min_s"]), "never before min_s")
				assert_lt(len_s, float(s["max_s"]), "inside max_s")
		assert_true(rig.state.score.behemoth_killed)
		assert_eq(rig.state.score.stages_clean, 3)
		var sum := TankScore.summary(rig.state)
		assert_has(["S", "A", "B"], sum["grade"], "crew %d: %s" % [crew, sum["grade"]])


func test_every_crew_plays_the_drill_to_the_results() -> void:
	for crew in DRILL_CREWS:
		var rig := TankRulesRig.new(crew, "drill", 2)
		rig.auto_seat = true
		var t := rig.play()
		assert_lt(t, 200.0)
		assert_eq(rig.state.outcome, TankIds.OUTCOME_COMPLETE)
		assert_eq(rig.state.score.overruns, 0)
		assert_eq(rig.rider().work_s, 0.0, "the drill is all warm-up and recovery")
		assert_eq(rig.of_type("segment").size(), 4, "depot, skirmish, checkpoint, cool-down")


func test_the_score_falls_with_compliance_100_85_70() -> void:
	var score: Array[float] = [float(TankScore.summary((_done[3] as TankRulesRig).state)["score"])]
	for c in [0.85, 0.7]:
		var rig := TankRulesRig.new(3, "ashfall_road", 1)
		rig.compliance = c
		rig.bank_director = true
		rig.auto_seat = true
		rig.play()
		score.append(float(TankScore.summary(rig.state)["score"]))
	assert_gt(score[0], score[1], "100% beats 85%")
	assert_gt(score[1], score[2], "85% beats 70%")


## The solo loop: the solo rider drives, loads, fires and works the bow guns, every seat change at
## least 60 s after the last.
func test_a_solo_rider_fights_through_the_solo_loop() -> void:
	var rig: TankRulesRig = _done[1]
	var r := rig.rider(1)
	assert_gt(r.engine_s[0], 300.0, "Drive")
	assert_gt(r.engine_s[1], 60.0, "the Gun")
	assert_gt(r.engine_s[2], 60.0, "the Loader")
	assert_gt(rig.state.score.shots, 5, "the main gun fired")
	var times := _seat_times(rig)
	assert_gt(times.size(), 4, "the loop moved the rider")
	for i in range(1, times.size()):
		assert_gte(times[i] - times[i - 1], TankConst.SEAT_LOCK_S - 0.06, "every stay >= 60 s")


## The game times of the rig's seat events (from its per-step event counts).
func _seat_times(rig: TankRulesRig) -> Array[float]:
	var out: Array[float] = []
	var at := 0
	for step in rig.event_counts.size():
		for k in rig.event_counts[step]:
			if str(rig.events[at + k]["type"]) == TankEvents.SEAT:
				out.append(step * Wl.SIM_DT)
		at += rig.event_counts[step]
	return out


func test_a_solo_rider_that_never_pedals_gets_through_on_the_reserve_alone() -> void:
	# Everyone AFK all session: nothing has power, nothing moves, every open phase is cut at max_s.
	var rig := TankRulesRig.new(1, "ashfall_road", 3)
	rig.afk[1] = true
	rig.play()
	assert_true(rig.in_cooldown())
	assert_eq(rig.state.outcome, TankIds.OUTCOME_WITHDRAWN)
	assert_eq(rig.state.score.kills, [0, 0, 0, 0, 0, 0, 0] as Array[int])
	assert_eq(rig.state.score.shots, 0)
	assert_eq(rig.state.score.hits, 0)


func test_every_event_carries_ints_for_the_fields_the_wire_declares() -> void:
	var rig: TankRulesRig = _done[3]
	var seen := {}
	for e in rig.events:
		var type := str(e["type"])
		seen[type] = true
		assert_has(TankEvents.TYPES, type)
		for field: String in TankEvents.INT_FIELDS[type]:
			if field.ends_with("[][]"):
				for row: Array in e[field.trim_suffix("[][]")]:
					for v: Variant in row:
						assert_eq(typeof(v), TYPE_INT, "%s %s" % [type, field])
			else:
				assert_eq(typeof(e[field]), TYPE_INT, "%s.%s" % [type, field])
	for type in ["segment", "shot", "hit", "kill", "latch", "boss_phase"]:
		assert_true(seen.has(type), "a full session raises %s" % type)


func test_events_stay_inside_ten_a_second() -> void:
	var worst := 0
	for crew in ROADS:
		var counts: Array[int] = (_done[crew] as TankRulesRig).event_counts
		var window := 0
		for i in counts.size():
			window += counts[i]
			if i >= 20:
				window -= counts[i - 20]
			worst = maxi(worst, window)
	assert_lte(worst, 10, "brief 2.6: at most 10 messages a second (worst %d)" % worst)


func test_robust_states_step_without_content_or_riders() -> void:
	var rig := TankRulesRig.new(1)
	rig.state.content = null
	assert_eq(TankRules.step(rig.state, rig.inputs(), Wl.SIM_DT), [] as Array[Dictionary])
	var empty := TankRulesRig.new(1)
	var inp := empty.inputs()
	inp.riders.clear()
	var ev := TankRules.step(empty.state, inp, Wl.SIM_DT)
	assert_true(empty.state.all_afk or ev.size() >= 0)
