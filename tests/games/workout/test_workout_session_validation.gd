extends GutTest
## Session files are validated at load: a bad file is rejected with push_error naming the
## problem (BRIEF 6: content is JSON, validated at load).

const U := preload("res://tests/games/workout/workout_test_util.gd")


func _valid() -> Dictionary:
	return {
		"id": "x", "label": "WORKOUT_CONTENT_X", "summary": "WORKOUT_SUMMARY_X",
		"phases": [
			{"kind": "WARMUP", "mode": "ERG", "target_pct": 50, "ramp_to_pct": 65, "duration_s": 300, "lap": true, "label": "WORKOUT_LBL_WARMUP"},
			{"kind": "WORK", "mode": "ERG", "target_pct": 80, "duration_s": 120, "lap": true, "label": "WORKOUT_LBL_STEADY"},
			{"kind": "FREE", "mode": "SIM", "grade_source": "flat", "duration_s": 30, "lap": true, "label": "WORKOUT_LBL_SPRINT"},
		],
	}


func _rejects(data: Variant, needle: String) -> void:
	var s := WorkoutSession.parse(data, "x")
	assert_null(s, "rejected: %s" % needle)
	assert_push_error(needle)


func test_a_valid_file_parses() -> void:
	var s := WorkoutSession.parse(_valid(), "x")
	assert_not_null(s)
	assert_eq(s.phases.size(), 3)
	assert_eq(s.phases[0].ramp_to_pct, 65.0)
	assert_eq(s.phases[2].mode, Wl.SIM)
	assert_true(WorkoutSession.validate(_valid(), "x").is_empty())


func test_not_an_object() -> void:
	_rejects([1, 2], "JSON object")


func test_wrong_id() -> void:
	var d := _valid()
	d["id"] = "y"
	_rejects(d, "id: must be")


func test_unknown_keys() -> void:
	var d := _valid()
	d["extra"] = 1
	_rejects(d, "extra: unknown key")
	var e := _valid()
	e["phases"][1]["power"] = 3
	_rejects(e, "phases[1].power: unknown key")


func test_label_and_summary_are_strings_keys() -> void:
	var d := _valid()
	d["label"] = "Plain"
	_rejects(d, "label: must be a WORKOUT_ strings key")


func test_game_written_cooldown_is_rejected() -> void:
	var d := _valid()
	d["phases"].append({"kind": "COOLDOWN", "mode": "ERG", "target_pct": 50, "duration_s": 180, "lap": true, "label": "WORKOUT_LBL_STEADY"})
	_rejects(d, "phases[3].kind")


func test_every_phase_needs_lap_and_label() -> void:
	var d := _valid()
	d["phases"][1]["lap"] = false
	_rejects(d, "phases[1].lap")
	var e := _valid()
	e["phases"][1]["label"] = ""
	_rejects(e, "phases[1].label")


func test_targets_and_durations() -> void:
	var d := _valid()
	d["phases"][1]["target_pct"] = 151
	_rejects(d, "phases[1].target_pct")
	var e := _valid()
	e["phases"][1]["duration_s"] = 0
	_rejects(e, "phases[1].duration_s")
	var f := _valid()
	f["phases"][1]["ramp_to_pct"] = "high"
	_rejects(f, "phases[1].ramp_to_pct")


func test_free_rides_sim_and_sim_takes_no_target() -> void:
	var d := _valid()
	d["phases"][2] = {"kind": "FREE", "mode": "ERG", "target_pct": 100, "duration_s": 30, "lap": true, "label": "WORKOUT_LBL_SPRINT"}
	_rejects(d, "FREE phases ride SIM")
	var e := _valid()
	e["phases"][2]["target_pct"] = 120
	_rejects(e, "SIM phases take no target_pct")
	var f := _valid()
	f["phases"][2]["grade_source"] = "game"
	_rejects(f, "grade_source: must be flat or course")


func test_course_phases_need_a_course() -> void:
	var d := _valid()
	d["phases"].append({"kind": "WORK", "mode": "SIM", "grade_source": "course", "duration_s": 600, "lap": true, "label": "WORKOUT_LBL_ROLLING_ROAD"})
	_rejects(d, "course: required")
	var e := _valid()
	e["course"] = {"seed": 1, "length_m": 20000, "step_m": 250, "min_grade_pct": -2, "max_grade_pct": 6}
	_rejects(e, "course: no phase uses it")
	var f := _valid()
	f["phases"].append({"kind": "WORK", "mode": "SIM", "grade_source": "course", "duration_s": 600, "lap": true, "label": "WORKOUT_LBL_ROLLING_ROAD"})
	f["course"] = {"seed": 1, "length_m": 20000, "step_m": 250, "min_grade_pct": -12, "max_grade_pct": 6}
	_rejects(f, "grades must stay within")


func test_sessions_open_with_the_warmup_ramp() -> void:
	var d := _valid()
	d["phases"][0]["ramp_to_pct"] = 70
	_rejects(d, "phases[0]: must be the 5-minute WARMUP")
	var e := _valid()
	e["phases"].remove_at(0)
	_rejects(e, "phases[0]: must be the 5-minute WARMUP")


func test_warmup_only_sessions_stay_inside_the_limits() -> void:
	var d := {
		"id": "x", "label": "WORKOUT_CONTENT_X", "summary": "WORKOUT_SUMMARY_X", "warmup_only": true,
		"phases": [{"kind": "WORK", "mode": "ERG", "target_pct": 70, "duration_s": 60, "lap": true, "label": "WORKOUT_LBL_STEADY"}],
	}
	_rejects(d, "warmup_only")
	d["phases"][0]["target_pct"] = 65
	d["phases"][0]["duration_s"] = 400
	_rejects(d, "warmup_only: the session lasts")
	d["phases"][0]["duration_s"] = 60
	assert_not_null(WorkoutSession.parse(d, "x"), "65% for 60 s is fine")


func test_phases_or_zwo_exactly_once() -> void:
	var d := _valid()
	d["zwo"] = "zwo/sample.zwo"
	_rejects(d, "exactly one of phases and zwo")
	var e := _valid()
	e.erase("phases")
	_rejects(e, "exactly one of phases and zwo")


func test_band_pct() -> void:
	var d := _valid()
	d["band_pct"] = [105, 76]
	_rejects(d, "band_pct")


func test_errors_are_reported_together() -> void:
	var d := _valid()
	d["phases"][1]["lap"] = false
	d["phases"][2]["label"] = 3
	var errs := WorkoutSession.validate(d, "x")
	assert_eq(errs.size(), 2, str(errs))
	assert_null(WorkoutSession.parse(d, "x"))
	assert_push_error_count(1, "one push_error per rejected file")


func test_unknown_content_is_an_error() -> void:
	assert_null(WorkoutSession.load_id("no_such_session"))
	assert_push_error("no session no_such_session")


func test_configure_with_a_bad_content_id_builds_no_plans() -> void:
	var g := WorkoutGame.new()
	g.configure(U.ctx("no_such_session", U.players(1)))
	assert_push_error("missing content")
	assert_eq(g.build_effort_plans(), {})
	assert_push_error("no valid session")
	g.free()
