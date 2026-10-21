extends "res://tests/governor/gov_test_base.gd"
## OWNERSHIP DS15 and BRIEF 4.6.1/4.6.12: clamped_by names every rule that changed the
## value, in the order applied, with distinct names per rule; whole-watt rounding means a
## target exactly at a cap is not "clamped".


func test_rules_in_precedence_order() -> void:
	var rig := make_rig({"ftp_verified": false, "skip_warmup": false}, follower())
	rig.start([erg(Wl.WORK, 200.0, 400.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 130)
	assert_eq(rig.s()["clamped_by"], [Wl.CLAMP_UNVERIFIED, Wl.CLAMP_CEILING, Wl.CLAMP_LONG_PHASE, Wl.CLAMP_WARMUP],
		"200% x 0.85 = 340 -> ceiling 300 -> long phase 210 -> warm-up 130")


func test_target_exactly_at_the_ceiling_is_not_clamped() -> void:
	var cases := [[150.0, 300, false], [150.4, 300, false], [150.5, 300, true]]
	for c: Array in cases:
		var rig := make_rig({}, follower())
		rig.start([erg(Wl.WORK, float(c[0]), 120.0)])
		rig.run(20.0)
		assert_eq(rig.applied_w(), int(c[1]), "%s%%" % c[0])
		var cb: Array = rig.s()["clamped_by"]
		assert_eq(cb.has(Wl.CLAMP_CEILING), bool(c[2]), "%s%% clamped by the ceiling: %s" % [c[0], c[2]])


func test_floor_rounds_up() -> void:
	var rig := make_rig({"ftp_w": 167.0}, follower())
	rig.start([erg(Wl.WORK, 20.0, 120.0)])
	rig.run(5.0)
	assert_eq(rig.applied_w(), 51, "max(30% of 167 W = 50.1 W, 50 W) rounded up")
	assert_eq(rig.s()["clamped_by"], [Wl.CLAMP_FLOOR])


func test_governed_target_rounds_down() -> void:
	var rig := make_rig({"ftp_w": 203.0}, follower())
	rig.start([erg(Wl.WORK, 77.0, 120.0)])
	rig.run(10.0)
	assert_eq(rig.applied_w(), 156, "77% of 203 W = 156.31 W")


func test_record_lists_the_rules_of_its_channel() -> void:
	var rig := make_rig({"ftp_verified": false, "skip_warmup": false}, follower())
	rig.start([erg(Wl.WORK, 50.0, 280.0).with_range(50.0, 100.0)])
	rig.run(10.0)
	var rec := rig.directive({"mode": "ERG", "target_pct": 100.0, "duration_s": 5.0, "reason": "bank", "source": "tank"})
	assert_false(rec["refused"])
	assert_eq(rec["reason"], "")
	assert_eq(int(rec["applied"]["target_w"]), 130)
	assert_eq(rec["clamped_by"], [Wl.CLAMP_UNVERIFIED, Wl.CLAMP_WARMUP, Wl.CLAMP_SLEW],
		"x0.85 = 170, warm-up 130, then slewing up from 85 W")
	assert_eq(rec["requested"], {"mode": "ERG", "target_pct": 100.0, "duration_s": 5.0, "reason": "bank", "source": "tank"},
		"requested holds exactly the game's keys")
	assert_eq(rec["kind"], "request")
	assert_eq(rig.records.size(), 1, "emitted as directive_applied")


func test_refused_record_shape() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 50.0, 280.0)])
	var rec := rig.directive({"target_pct": 60.0})
	assert_true(rec["refused"])
	assert_eq(rec["reason"], Wl.REFUSE_RANGE)
	assert_eq((rec["clamped_by"] as Array).size(), 0)
	assert_eq(rec["applied"], {})
	for key: String in ["id", "kind", "requested", "applied", "clamped_by", "refused", "reason", "t", "dropped", "game_t", "phase_index"]:
		assert_true(rec.has(key), "record has %s" % key)


func test_distinct_names() -> void:
	var names: Array[String] = [
		Wl.CLAMP_UNVERIFIED, Wl.CLAMP_CEILING, Wl.CLAMP_LONG_PHASE, Wl.CLAMP_LIMIT_105, Wl.CLAMP_LIMIT_120,
		Wl.CLAMP_WARMUP, Wl.CLAMP_FLOOR, Wl.CLAMP_RESCUE, Wl.CLAMP_COASTING, Wl.CLAMP_SLEW, Wl.CLAMP_SWITCH,
		Wl.CLAMP_PANIC, Wl.CLAMP_GRADE_RANGE, Wl.CLAMP_GRADE_LIMIT, Wl.CLAMP_HAPTIC, Wl.CLAMP_HAPTIC_INTENSITY,
		Wl.CLAMP_FACTOR, Wl.CLAMP_PAUSE,
	]
	var seen := {}
	for n in names:
		assert_false(seen.has(n), "%s is unique" % n)
		seen[n] = true
