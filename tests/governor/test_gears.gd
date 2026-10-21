extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.5 virtual gears and OWNERSHIP SH6: 24 gears on shift_up / shift_down as SIM grade
## offsets, tuned so one step changes resistance at constant flywheel speed by about 6-8%;
## they work in every SIM phase and SIM block.


func test_24_gears_and_bounds() -> void:
	var g := VirtualGears.new()
	assert_eq(g.gear, 12, "starts in the neutral gear")
	assert_eq(VirtualGears.COUNT, 24)
	for i in 20:
		g.shift(1)
	assert_eq(g.gear, 24)
	for i in 30:
		g.shift(-1)
	assert_eq(g.gear, 1)
	assert_eq(g.set_gear(40), 24)
	assert_eq(VirtualGears.create(0).gear, 1)


func test_neutral_adds_nothing() -> void:
	for base: float in [-4.0, 0.0, 3.0, 8.0]:
		assert_almost_eq(VirtualGears.offset_for(12, base), 0.0, 1e-12)


func test_each_step_changes_resistance_by_6_to_8_pct() -> void:
	for base: float in [0.0, 2.0, 5.0, 8.0]:
		for gear in range(1, 24):
			var f1 := VirtualGears.resistance_n(base + VirtualGears.offset_for(gear, base))
			var f2 := VirtualGears.resistance_n(base + VirtualGears.offset_for(gear + 1, base))
			var ratio := f2 / f1
			assert_between(ratio, 1.06, 1.08, "gear %d -> %d on %s%%: %.4f" % [gear, gear + 1, base, ratio])


func test_offsets_are_monotonic_and_span_about_minus_2_5_to_plus_6_on_the_flat() -> void:
	var prev := -100.0
	for gear in range(1, 25):
		var off := VirtualGears.offset_for(gear, 0.0)
		assert_gt(off, prev, "gear %d is harder than gear %d" % [gear, gear - 1])
		prev = off
	assert_almost_eq(VirtualGears.offset_for(1, 0.0), -2.5, 0.1)
	assert_almost_eq(VirtualGears.offset_for(24, 0.0), 6.0, 0.1)


func test_grade_for_resistance_inverts_resistance() -> void:
	for grade: float in [-8.0, -2.0, 0.0, 3.5, 12.0]:
		var f := VirtualGears.resistance_n(grade)
		assert_almost_eq(VirtualGears.grade_for_resistance(f), grade, 1e-9)


func test_descents_use_the_flat_road_steps() -> void:
	var on_flat := VirtualGears.offset_for(13, 0.0)
	var on_descent := VirtualGears.offset_for(13, -4.0)
	assert_almost_eq(on_descent, on_flat, 0.01, "the step force is the flat road's")


func test_shift_works_in_sim_phases() -> void:
	var rig := make_rig({}, follower())
	rig.start([sim(Wl.GRADE_FLAT, 600.0, Wl.FREE)])
	rig.run(2.0)
	assert_eq(rig.gov.shift(1), 13)
	assert_eq(rig.gov.shift(1), 14)
	rig.run(1.0)
	assert_eq(int(rig.s()["gear"]), 14)
	var expect := VirtualGears.offset_for(14, 0.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), expect, 1e-9)
	var dev: ScriptedDevice = rig.device
	assert_almost_eq(dev.grade_pct, snappedf(expect, 0.01), 1e-9, "sent at FTMS resolution")
	assert_eq(rig.gov.shift(-3), 11)


func test_gear_survives_phase_changes() -> void:
	var rig := make_rig({}, follower())
	rig.start([sim(Wl.GRADE_FLAT, 60.0, Wl.FREE), erg(Wl.WORK, 60.0, 60.0), sim(Wl.GRADE_FLAT, 60.0, Wl.FREE)])
	rig.gov.shift(3)
	rig.gov.start_phase(1)
	assert_eq(rig.gov.shift(1), 15, "ignored in ERG")
	rig.gov.start_phase(2)
	assert_eq(rig.gov.gear(), 15)


func test_warmup_clamps_the_gears() -> void:
	# BRIEF 7.7: the e2e sprint's gears are clamped to the warm-up grade limits.
	var rig := make_rig({"skip_warmup": false}, follower())
	rig.start([sim(Wl.GRADE_FLAT, 60.0, Wl.FREE)])
	rig.gov.shift(12)
	rig.run(2.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 3.0, 1e-9)
	rig.gov.shift(-23)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), -2.0, 1e-9)
