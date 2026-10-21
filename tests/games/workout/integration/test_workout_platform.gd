extends GutTest
## Workout against the real platform pieces (W2: needs sdk-runtime's PlanValidator and
## GameRegistry, sim's WorkoutImport and net-client's Protocol). In W1 these are stubs, so
## this folder is left out of game-workout's W1 test command; the full suite runs it.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const BUILT_IN: Array[String] = ["easy_30", "sweet_spot", "threshold", "vo2", "rolling_road", "e2e"]
const TOTAL_MIN := {"easy_30": 28.0, "sweet_spot": 36.0, "threshold": 40.0, "vo2": 35.0, "rolling_road": 38.0, "e2e": 5.0}


func after_each() -> void:
	WorkoutSession.zwo_parser = Callable()


func test_every_session_passes_the_plan_validator_without_warnings() -> void:
	for id in BUILT_IN:
		var s := WorkoutSession.load_id(id)
		assert_not_null(s, id)
		if s == null:
			continue
		for opts: Dictionary in [{}, {"ramp_test": false}]:
			var v := PlanValidator.validate(s.build_plan(), opts)
			assert_true(bool(v["ok"]), "%s accepted: %s" % [id, v["errors"]])
			assert_eq((v["warnings"] as Array).size(), 0, "%s has no warnings: %s" % [id, v["warnings"]])
		var plan := PlanValidator.finalize(s.build_plan())
		assert_not_null(plan, "%s finalizes" % id)
		if plan == null:
			continue
		assert_true(plan.cooldown_appended)
		assert_eq(plan.size(), s.phases.size() + 1)
		assert_eq(plan.phases.back().to_dict(), PlanValidator.cooldown_phase().to_dict())
		assert_almost_eq(plan.nominal_length_s(), float(TOTAL_MIN[id]) * 60.0, 0.001, "%s total with the cool-down" % id)
		assert_eq(plan.phases.back().to_dict(), s.timeline().back().to_dict(), "Workout's timeline mirrors the appended cool-down")


func test_the_sample_zwo_imports_with_clamps() -> void:
	var s := WorkoutSession.load_id("zwo_sample")
	assert_not_null(s, "the real WorkoutImport parses content/workout/zwo/sample.zwo")
	if s == null:
		return
	assert_eq(s.source, "zwo")
	assert_gt(s.clamps.size(), 0, "the sample breaks limits on purpose")
	assert_gt(s.warnings.size(), 0, "MaxEffort is unsupported")
	for p in s.phases:
		assert_true(p.lap)
		assert_ne(p.label, "")
	var v := PlanValidator.validate(s.build_plan())
	assert_true(bool(v["ok"]), "clamped plan accepted: %s" % [v["errors"]])
	var g := WorkoutGame.new()
	autofree(g)
	var pv := g.session_preview("zwo_sample")
	var text := "\n".join(PackedStringArray(pv["lines"]))
	for c in s.clamps:
		assert_string_contains(text, c, "the preview lists every clamp")


func test_zwo_path_content() -> void:
	var path := ProjectSettings.globalize_path("res://content/workout/zwo/sample.zwo")
	var g := U.game("zwo:" + path, U.players(1))
	autofree(g)
	assert_not_null(g.session)
	var plans := g.build_effort_plans()
	assert_eq(plans.size(), 1)
	if plans.has(1):
		assert_not_null(PlanValidator.finalize(plans[1]))


func test_game_json_validates_in_the_registry() -> void:
	var reg := WlGameRegistry.new()
	autofree(reg)
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/games/workout/game.json"))
	assert_eq(reg.validate_manifest(m, "res://src/games/workout/game.json"), "")
	reg.scan()
	assert_true(reg.has_game("workout"))
	var g: GameModule = autofree(reg.instantiate("workout"))
	assert_true(g is WorkoutGame)
	assert_eq(reg.content_label_key("workout", "easy_30"), "WORKOUT_CONTENT_EASY_30")


func test_protocol_restores_snapshot_and_event_ints() -> void:
	var g := U.game("easy_30", U.players(2, 1))
	autofree(g)
	var events := U.ride(g, Callable(), 14000)
	var snap := g.snapshot()
	var back: Variant = Protocol.apply_int_fields(JSON.parse_string(JSON.stringify(snap)), g.int_fields()["snapshot"])
	assert_eq(JSON.stringify(back), JSON.stringify(snap))
	for e in events:
		var paths: Array = g.int_fields()[str(e["type"])]
		var eb: Variant = Protocol.apply_int_fields(JSON.parse_string(JSON.stringify(e)), paths)
		assert_eq(JSON.stringify(eb), JSON.stringify(e))
