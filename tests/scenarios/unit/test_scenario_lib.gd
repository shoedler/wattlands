extends GutTest
## The pure helpers behind the BRIEF 7.4/7.5 scenario tests (tests/scenarios/lib/scenario_lib.gd):
## flags, report accessors in each allowed shape, the FIT1 lap formula, the warm-up check and the
## FIT-versus-recorder comparison (on files built with QaFitWriter).

const S := preload("res://tests/scenarios/lib/scenario_lib.gd")

var _dirs: Array[String] = []


func after_each() -> void:
	for d in _dirs:
		S.remove_tree(d)
	_dirs.clear()


func test_flags_defaults_and_overrides() -> void:
	var f := Array(S.flags("vo2", "C:/r/x.json"))
	assert_eq(f, ["--game=workout", "--content=vo2", "--players=1", "--bots=1", "--rider=erg", "--seed=7", "--sim-speed=1000", "--report=C:/r/x.json"])
	var g := Array(S.flags("e2e", "r.json", ["--bots=0", "--rider=zero", "--rider=erg", "--unverified"]))
	assert_does_not_have(g, "--bots=1")
	assert_has(g, "--bots=0")
	assert_eq(g.filter(func(a: String) -> bool: return a.begins_with("--rider=")), ["--rider=zero", "--rider=erg"], "custom riders replace the default, in slot order")
	assert_has(g, "--unverified")


func test_floor_and_not_pedaling() -> void:
	assert_eq(S.floor_w(200.0), 60)
	assert_eq(S.floor_w(120.0), 50)
	assert_eq(S.floor_w(201.0), 61, "the floor rounds up")
	assert_true(S.is_not_pedaling(TrainerSample.make(1.0, 0.0, 0.0, 0.0)))
	assert_true(S.is_not_pedaling(TrainerSample.make(1.0, 14.0)), "no cadence counts as 0 rpm")
	assert_false(S.is_not_pedaling(TrainerSample.make(1.0, 14.0, 25.0)))
	assert_false(S.is_not_pedaling(TrainerSample.make(1.0, 15.0, 0.0)))


func test_warmup_problems() -> void:
	assert_eq(S.warmup_problems({"warmup_active": true, "mode": "ERG", "applied_pct": 65.0}, 1.0), [] as Array[String])
	assert_eq(S.warmup_problems({"warmup_active": true, "mode": "ERG", "applied_pct": 65.5}, 1.0).size(), 1)
	assert_eq(S.warmup_problems({"warmup_active": true, "mode": "SIM", "applied_grade_pct": 3.5}, 1.0).size(), 1)
	assert_eq(S.warmup_problems({"warmup_active": true, "mode": "SIM", "applied_grade_pct": -2.0}, 1.0), [] as Array[String])
	assert_eq(S.warmup_problems({"warmup_active": true, "mode": "SIM", "applied_grade_pct": 0.0, "haptic_active": true}, 1.0).size(), 1)
	assert_eq(S.warmup_problems({"warmup_active": false, "mode": "ERG", "applied_pct": 110.0}, 1.0), [] as Array[String])
	assert_true(S.clamped({"clamped_by": ["warmup", "slew"]}, "slew"))
	assert_false(S.clamped({}, "slew"))


func _report_map() -> Dictionary:
	var plan := EffortPlan.of([
		PlanPhase.erg(Wl.WARMUP, 50, 300, "Warm-up").with_ramp(65).with_lap(),
		PlanPhase.erg(Wl.WORK, 110, 180, "Interval 1").with_lap(),
		PlanPhase.erg(Wl.RECOVERY, 50, 180, "Easy"),
		PlanPhase.erg(Wl.WORK, 110, 180, "Interval 2").with_lap(),
		PlanPhase.erg(Wl.COOLDOWN, 50, 180, "Cool-down").with_lap(),
	])
	return {
		"plans": {"1": plan.to_dict()},
		"phases": {"1": [{"index": 0, "start": 0}, {"index": 1, "start": 300}, {"index": 2, "start": 480}, {"index": 3, "start": 660}, {"index": 4, "start": 840}]},
		"traces": {"1": [{"t": 0, "mode": "ERG"}]},
		"events": [{"type": "lap_marker", "peer": 1}, {"type": "lap_marker", "peer": 2}, {"type": "phase_started", "peer": 1}],
		"results": {"grade": "A", "rows": [{"peer_id": 1, "time_in_band_pct": 93.0}, {"peer_id": -1}]},
		"fit_paths": ["C:/x/slot0.fit"],
	}


func test_report_accessors_on_maps_keyed_by_peer() -> void:
	var r := _report_map()
	assert_eq(S.plan_phases(r, 1).size(), 5)
	assert_eq(S.run_phases(r, 1).size(), 5)
	assert_eq(S.trace(r, 1).size(), 1)
	assert_eq(S.plan_phases(r, 2), [])
	assert_eq(S.result_row(r, 1)["time_in_band_pct"], 93.0)
	assert_eq(S.result_row(r, 5), {})
	assert_eq(S.fit_paths(r), ["C:/x/slot0.fit"] as Array[String])
	assert_eq(S.fit_paths({"fit_paths": {"0": "a.fit", "1": "b.fit"}}).size(), 2)
	assert_eq(S.lap_markers(r, 1), 1)


func test_report_accessors_on_lists_of_peers() -> void:
	var m := _report_map()
	var r := {
		"plans": [{"peer": 1, "plan": m["plans"]["1"]}],
		"phases": [{"peer_id": 1, "phases": m["phases"]["1"]}],
		"traces": [{"peer": 1, "trace": [{"t": 0}, {"t": 1}]}],
	}
	assert_eq(S.plan_phases(r, 1).size(), 5)
	assert_eq(S.run_phases(r, 1).size(), 5)
	assert_eq(S.trace(r, 1).size(), 2)
	var ints := {"plans": {1: m["plans"]["1"]}}
	assert_eq(S.plan_phases(ints, 1).size(), 5, "in-memory reports may key by int")


func test_expected_laps_follow_fit1() -> void:
	var r := _report_map()
	# lap-true phases that started (warm-up, both intervals) + 1 lap marker + the cool-down.
	assert_eq(S.expected_laps(r, 1), 5)
	var early := r.duplicate(true)
	early["phases"] = {"1": [{"index": 0}, {"index": 1}]}
	early["events"] = []
	assert_eq(S.expected_laps(early, 1), 2, "a run that ends before the cool-down has no cool-down lap")


func test_fit_problems_against_the_recorder() -> void:
	var dir := Paths.make_temp_dir("wattlands_scenario_lib")
	_dirs.append(dir)
	var path := dir.path_join("ride.fit")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(QaFitWriter.activity({"records": 300, "laps": [100, 100, 100], "power": 150, "cadence": 90, "speed_mps": 8.0}))
	f.close()
	var summary := {"duration_s": 300.0, "records": 300, "kj": 45.0, "avg_power_w": 150.0, "max_power_w": 150.0, "avg_cadence_rpm": 90.0, "max_cadence_rpm": 90.0, "distance_m": 2400.0}
	assert_eq(S.fit_problems(path, summary, 3), [] as Array[String])
	assert_eq(S.fit_problems(path, summary, 4).size(), 1, "a wrong lap count")
	var off := summary.duplicate()
	off["kj"] = 46.0
	off["avg_power_w"] = 160.0
	off["records"] = 290
	off["duration_s"] = 330.0
	var problems := S.fit_problems(path, off, 3)
	var text := "\n".join(PackedStringArray(problems))
	assert_string_contains(text, "session work")
	assert_string_contains(text, "avg_power_w")
	assert_string_contains(text, "the recorder kept 290")
	assert_string_contains(text, "one per second within 1%")
	assert_string_contains(text, "session elapsed")
