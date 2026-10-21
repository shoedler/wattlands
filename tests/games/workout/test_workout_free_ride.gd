extends GutTest
## W4r2 R15 (BRIEF 3.7 separates "free sprints" from "FREE phases"; W3 WO-6 made the HUD and the
## rules tell them apart): the lobby preview and the ride view's interval strip agree with the HUD.
## A FREE phase longer than a sprint (an imported FreeRide) is free riding: previewed as a free
## ride, drawn low and hatched in ZONE_FREE. Only a FREE phase of at most 30 s is a "Free sprint",
## drawn tall in ZONE_SPRINT.

const U := preload("res://tests/games/workout/workout_test_util.gd")

var _tr: Translation = null


func before_all() -> void:
	_tr = U.register_strings()


func after_all() -> void:
	U.unregister_strings(_tr)


func _free(seconds: float, label: String) -> PlanPhase:
	return PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, seconds, label).with_lap()


func test_the_preview_line_calls_a_long_free_phase_a_free_ride() -> void:
	var strings := GameStrings.new()
	assert_ne(strings.t("WORKOUT_PREVIEW_FREE_RIDE"), "WORKOUT_PREVIEW_FREE_RIDE", "the string exists")
	var long_line := WorkoutSession.describe_phase(_free(600.0, "Free ride"), strings)
	assert_eq(long_line, "10:00  Free ride  " + strings.t("WORKOUT_PREVIEW_FREE_RIDE"))
	assert_false(long_line.to_lower().contains("sprint"), "not a sprint: %s" % long_line)
	var sprint_line := WorkoutSession.describe_phase(_free(30.0, "WORKOUT_LBL_SPRINT"), strings)
	assert_eq(sprint_line, "0:30  %s  %s" % [strings.t("WORKOUT_LBL_SPRINT"), strings.t("WORKOUT_PREVIEW_FREE")])
	assert_true(sprint_line.to_lower().contains("sprint"), "a 30 s FREE phase is a sprint: %s" % sprint_line)


func test_the_strip_draws_a_long_free_phase_low_and_hatched() -> void:
	assert_eq(WorkoutArt.phase_color(_free(600.0, "Free ride")), WorkoutArt.ZONE_FREE)
	assert_eq(WorkoutArt.phase_color(_free(30.0, "WORKOUT_LBL_SPRINT")), WorkoutArt.ZONE_SPRINT)
	assert_ne(WorkoutArt.ZONE_FREE, WorkoutArt.ZONE_SPRINT)
	var g := U.game("e2e", U.players(1, 0, 200.0))
	autofree(g)
	var warm := PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "WORKOUT_LBL_WARMUP").with_ramp(65.0).with_lap()
	var timeline: Array[PlanPhase] = [warm, _free(600.0, "Free ride"), _free(30.0, "WORKOUT_LBL_SPRINT")]
	g.state.set_timeline(timeline)
	g.state.plan_t = 300.0
	var view := g.make_view() as WorkoutRideView
	autofree(view)
	var blocks: Array = view._blocks(g.state)
	assert_eq(blocks.size(), 3, "warm-up, free ride and sprint on screen")
	if blocks.size() != 3:
		return
	var free_b: Dictionary = blocks[1]
	var sprint_b: Dictionary = blocks[2]
	assert_eq(free_b["color"], WorkoutArt.ZONE_FREE)
	assert_true(bool(free_b["hatched"]), "free riding has no target: hatched")
	assert_eq(sprint_b["color"], WorkoutArt.ZONE_SPRINT)
	assert_false(bool(sprint_b["hatched"]))
	var free_top := (free_b["points"] as PackedVector2Array)[0].y
	var sprint_top := (sprint_b["points"] as PackedVector2Array)[0].y
	assert_almost_eq(free_top, WorkoutRideView.STRIP_BASE - WorkoutRideView._strip_h(WorkoutRideView.FREE_STRIP_PCT), 0.001)
	assert_almost_eq(sprint_top, WorkoutRideView.STRIP_BASE - WorkoutRideView._strip_h(WorkoutRideView.SPRINT_STRIP_PCT), 0.001)
	assert_gt(free_top, sprint_top, "the free ride sits lower than a sprint")


## The built-in zwo_sample's 60 s FreeRide rides as free riding (WO-6) and is previewed so.
func test_zwo_sample_previews_its_free_ride_as_free_riding() -> void:
	var s := WorkoutSession.load_id("zwo_sample")
	assert_not_null(s)
	if s == null:
		return
	var strings := GameStrings.new()
	var found := 0
	for p in s.phases:
		if p.kind != Wl.FREE:
			continue
		found += 1
		assert_false(WorkoutSession.is_sprint(p), "%.0f s FreeRide" % p.duration_s)
		var line := WorkoutSession.describe_phase(p, strings)
		assert_false(line.to_lower().contains("sprint"), "preview: %s" % line)
		assert_has(s.preview()["lines"], line)
		assert_eq(WorkoutArt.phase_color(p), WorkoutArt.ZONE_FREE)
	assert_eq(found, 1, "the sample has one FreeRide")
