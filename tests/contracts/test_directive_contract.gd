extends GutTest
## EffortDirective and DirectiveResult (BRIEF 3.6, 5.5): set fields only, channels and
## channels_for_phase, is_set, JSON round trips.


func _rt(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	assert_true(parsed is Dictionary)
	return parsed if parsed is Dictionary else {}


func test_new_directive_is_empty() -> void:
	var e := EffortDirective.new()
	for f in EffortDirective.FLOAT_FIELDS:
		assert_false(e.is_set(f), f)
	assert_false(e.is_set("mode"))
	assert_eq(e.channels().size(), 0)
	assert_eq(e.to_dict(), {"duration_s": 0.0}, "only duration_s is always present")


func test_to_dict_emits_only_set_fields() -> void:
	var e := EffortDirective.from_dict(
		{"target_pct": 85, "duration_s": 20, "reason": "dig in", "source": "tank"}
	)
	assert_eq(
		e.to_dict(), {"target_pct": 85.0, "duration_s": 20.0, "reason": "dig in", "source": "tank"}
	)
	e.id = 7
	assert_eq(e.to_dict()["id"], 7)
	var sim := EffortDirective.from_dict({"mode": "SIM", "mode_grade": 4.0, "duration_s": 30.0})
	assert_eq(sim.to_dict(), {"mode": "SIM", "mode_grade": 4.0, "duration_s": 30.0})


func test_from_dict_ignores_nulls() -> void:
	var e := EffortDirective.from_dict({"target_pct": null, "haptic": 2.0})
	assert_false(e.is_set("target_pct"))
	assert_true(e.is_set("haptic"))


func test_is_set() -> void:
	var e := EffortDirective.make({"mode": "ERG", "target_w": 210.0, "cw": 0.8})
	assert_true(e.is_set("mode"))
	assert_true(e.is_set("target_w"))
	assert_true(e.is_set("cw"))
	assert_false(e.is_set("target_pct"))
	assert_false(e.is_set("crr"))
	assert_false(e.is_set("duration_s"), "not a set/unset field")
	assert_false(e.is_set("bogus"))


func test_channels() -> void:
	var cases := [
		[{"target_pct": 80.0}, ["erg_target"]],
		[{"target_wkg": 3.0}, ["erg_target"]],
		[{"target_w": 200.0}, ["erg_target"]],
		[{"mode": "SIM", "duration_s": 20.0}, ["sim_block"]],
		[{"mode": "ERG"}, ["sim_block"]],
		[{"mode_grade": 2.0}, ["mode_grade"]],
		[{"haptic": 2.0}, ["haptic"]],
		[{"haptic_wind": 3.0}, ["haptic"]],
		[{"crr": 0.8}, ["factors"]],
		[{"cw": 0.6}, ["factors"]],
		[
			{"mode": "SIM", "mode_grade": 4.0, "haptic": 1.0, "crr": 0.9, "target_pct": 90.0},
			["erg_target", "sim_block", "mode_grade", "haptic", "factors"]
		],
	]
	for c: Array in cases:
		var e := EffortDirective.from_dict(c[0])
		assert_eq(e.channels(), c[1], JSON.stringify(c[0]))


func test_helpers() -> void:
	var e := EffortDirective.from_dict({"mode": "SIM", "haptic_wind": 2.0, "crr": 0.7})
	assert_false(e.sets_erg_target())
	assert_true(e.sets_sim_block())
	assert_true(e.sets_haptic())
	assert_true(e.sets_factors())
	assert_false(
		EffortDirective.from_dict({"mode": "ERG"}).sets_sim_block(), "mode ERG ends a block"
	)


func test_channels_for_phase() -> void:
	var e := EffortDirective.from_dict({"mode": "SIM", "mode_grade": 4.0})
	assert_eq(e.channels_for_phase(Wl.ERG), ["sim_block", "mode_grade"])
	assert_eq(e.channels_for_phase(Wl.SIM), ["mode_grade"], "mode SIM in a SIM phase is a no-op")
	var erg := EffortDirective.from_dict({"mode": "ERG", "target_pct": 70.0})
	assert_eq(erg.channels_for_phase(Wl.SIM), ["erg_target"])
	assert_eq(erg.channels_for_phase(Wl.ERG), ["erg_target", "sim_block"])
	assert_eq(e.channels(), ["sim_block", "mode_grade"], "channels() is unchanged")


func test_json_round_trip() -> void:
	var e := (
		EffortDirective
		. from_dict(
			{
				"mode": "SIM",
				"target_pct": 92.5,
				"target_wkg": 3.1,
				"target_w": 240.0,
				"mode_grade": 4.0,
				"haptic": 2.5,
				"haptic_wind": 1.5,
				"crr": 0.8,
				"cw": 0.6,
				"duration_s": 25.0,
				"reason": "overdrive",
				"source": "siege",
				"id": 42,
			}
		)
	)
	var d := e.to_dict()
	var back := EffortDirective.from_dict(_rt(d))
	assert_eq(back.to_dict(), d)
	assert_eq(back.id, 42)
	assert_true(typeof(back.id) == TYPE_INT)
	assert_eq(back.mode, Wl.SIM)
	assert_eq(back.duration_s, 25.0)
	var dup := e.duplicate_directive()
	assert_eq(dup.to_dict(), d)
	dup.target_pct = 10.0
	assert_eq(e.target_pct, 92.5)


func test_directive_result() -> void:
	var ok := DirectiveResult.ok(5)
	assert_true(ok.accepted)
	assert_eq(ok.id, 5)
	assert_eq(ok.reason, "")
	var no := DirectiveResult.refused(Wl.REFUSE_ERG_IN_SIM)
	assert_false(no.accepted)
	assert_eq(no.id, 0)
	assert_eq(no.to_dict(), {"accepted": false, "id": 0, "reason": "erg_in_sim_phase"})
	assert_eq(DirectiveResult.refused(Wl.REFUSE_RANGE, 9).id, 9)
