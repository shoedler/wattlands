extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.5 ramped mode switches. ERG -> SIM: ERG target min(applied, 3 s power) first,
## then SIM grade 0, then the stacked grade. SIM -> ERG: SIM grade 0 first, then ERG at
## min(3 s power, the planned or directed target), never below the floor, then slew up; an
## entry is never above the planned target (BRIEF 7.1 "ERG entered from a sprint never above
## the planned target"). OWNERSHIP GOV9.


func _writes_since(rig: Rig, since: float) -> Array[Dictionary]:
	var dev: ScriptedDevice = rig.device
	var out: Array[Dictionary] = []
	for w in dev.writes:
		if float(w["t"]) > since + 1e-9:
			out.append(w)
	return out


func test_erg_to_sim_steps_down_then_flat_then_grade() -> void:
	var dev := ScriptedDevice.new()
	dev.erg_follow = 0.8
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 100.0, 60.0), sim(Wl.GRADE_GAME, 60.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 200)
	assert_almost_eq(rig.gov.power_3s_w(), 160.0, 1e-6)
	var t0 := rig.t
	rig.gov.start_phase(1)
	rig.gov.set_course_grade(4.0)
	rig.run(3.0)
	var w := _writes_since(rig, t0)
	assert_eq(w.size(), 3)
	assert_eq(w[0]["op"], "erg")
	assert_eq(int(w[0]["w"]), 160, "min(applied 200 W, 3 s power 160 W)")
	assert_eq(w[1]["op"], "sim")
	assert_almost_eq(float(w[1]["grade_pct"]), 0.0, 1e-9, "SIM at grade 0 first")
	assert_almost_eq(float(w[1]["wind_mps"]), 0.0, 1e-9)
	assert_eq(w[2]["op"], "sim")
	assert_almost_eq(float(w[2]["grade_pct"]), 2.0, 1e-9, "then the stacked grade (4% x 50%)")
	for i in range(1, w.size()):
		assert_gte(float(w[i]["t"]) - float(w[i - 1]["t"]), 0.5 - 1e-6)
	assert_eq(rig.s()["mode"], Wl.SIM)
	assert_eq(int(rig.s()["applied_target_w"]), 0, "0 outside ERG")


func test_erg_to_sim_skips_the_step_when_power_is_higher() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 100.0, 60.0), sim(Wl.GRADE_FLAT, 60.0)])
	rig.run(20.0)
	var t0 := rig.t
	rig.gov.start_phase(1)
	rig.run(2.0)
	var w := _writes_since(rig, t0)
	assert_eq(w.size(), 1, "SIM flat only: no step-down, and flat is the stacked state")
	assert_eq(w[0]["op"], "sim")


func test_erg_to_sim_step_never_below_the_floor() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 100.0, 60.0), sim(Wl.GRADE_FLAT, 60.0)])
	rig.run(20.0)
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = -1.0
	dev.power_w = 30.0
	rig.run(3.5)
	assert_lt(rig.gov.power_3s_w(), 60.0)
	var t0 := rig.t
	rig.gov.start_phase(1)
	rig.run(2.0)
	var w := _writes_since(rig, t0)
	assert_eq(w[0]["op"], "erg")
	assert_eq(int(w[0]["w"]), 60, "the floor")


func test_sim_to_erg_flat_first_then_entry_at_the_planned_target() -> void:
	var dev := ScriptedDevice.new()
	dev.power_w = 300.0
	var rig := make_rig({}, dev)
	rig.start([sim(Wl.GRADE_GAME, 60.0), erg(Wl.WORK, 65.0, 60.0)])
	rig.gov.set_course_grade(6.0)
	rig.run(20.0)
	assert_almost_eq(dev.grade_pct, 3.0, 1e-9)
	var t0 := rig.t
	rig.gov.start_phase(1)
	rig.run(10.0)
	var w := _writes_since(rig, t0)
	assert_eq(w[0]["op"], "sim")
	assert_almost_eq(float(w[0]["grade_pct"]), 0.0, 1e-9, "grade 0 first")
	assert_eq(w[1]["op"], "erg")
	assert_eq(int(w[1]["w"]), 130, "min(3 s power 300 W, planned 130 W)")
	for x in w:
		if x["op"] == "erg":
			assert_lte(int(x["w"]), 130, "never above the planned target after a sprint")


func test_sim_to_erg_entry_at_3_s_power_then_slew() -> void:
	var dev := ScriptedDevice.new()
	dev.power_w = 100.0
	var rig := make_rig({}, dev)
	rig.keep_trace = true
	rig.start([sim(Wl.GRADE_FLAT, 60.0), erg(Wl.WORK, 90.0, 60.0)])
	rig.run(20.0)
	var t0 := rig.t
	rig.gov.start_phase(1)
	dev.erg_follow = 1.0
	rig.run(10.0)
	var w := _writes_since(rig, t0)
	assert_eq(w[0]["op"], "erg", "already flat: ERG straight away")
	assert_eq(int(w[0]["w"]), 100, "entry at the 3 s power")
	for i in range(1, w.size()):
		assert_lte(int(w[i]["w"]) - int(w[i - 1]["w"]), 15, "then slew")
	assert_eq(rig.applied_w(), 180)
	var entry_status := first_where(
		rig, func(s: Dictionary) -> bool: return float(s["rig_t"]) > t0 and s["mode"] == Wl.ERG
	)
	assert_has(
		entry_status["clamped_by"],
		Wl.CLAMP_SWITCH,
		"switch_ramp reported while slewing up from the entry"
	)


func test_sim_to_erg_entry_never_below_the_floor() -> void:
	var dev := ScriptedDevice.new()
	dev.power_w = 20.0
	dev.cadence_rpm = 60.0
	var rig := make_rig({}, dev)
	rig.start([sim(Wl.GRADE_FLAT, 60.0), erg(Wl.WORK, 90.0, 60.0)])
	rig.run(20.0)
	var t0 := rig.t
	rig.gov.start_phase(1)
	rig.run(1.0)
	var w := _writes_since(rig, t0)
	assert_eq(int(w[0]["w"]), 60, "max(floor, min(20 W, 180 W))")


func test_entry_never_above_the_unverified_target() -> void:
	var dev := ScriptedDevice.new()
	dev.power_w = 400.0
	var rig := make_rig({"ftp_verified": false}, dev)
	rig.start([sim(Wl.GRADE_FLAT, 60.0), erg(Wl.WORK, 65.0, 60.0)])
	rig.run(20.0)
	var t0 := rig.t
	rig.gov.start_phase(1)
	rig.run(10.0)
	for x in _writes_since(rig, t0):
		if x["op"] == "erg":
			assert_lte(int(x["w"]), 110, "65% x 0.85 = 110.5 W -> 110 W")


func test_first_erg_command_uses_the_entry_rule() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 100.0, 60.0)])
	rig.step()
	var dev: ScriptedDevice = rig.device
	assert_eq(dev.writes.size(), 1)
	assert_eq(int(dev.writes[0]["w"]), 60, "no power yet: the floor, then slew")


func test_switches_update_last_switch_t() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 60.0, 60.0), sim(Wl.GRADE_FLAT, 60.0), erg(Wl.WORK, 60.0, 60.0)])
	rig.run(5.0)
	assert_lt(float(rig.s()["last_switch_t"]), -1e8, "no switch yet")
	rig.gov.start_phase(1)
	assert_almost_eq(float(rig.s()["last_switch_t"]), rig.t, 1e-9)
	rig.run(5.0)
	rig.gov.start_phase(2)
	assert_almost_eq(float(rig.s()["last_switch_t"]), rig.t, 1e-9)
