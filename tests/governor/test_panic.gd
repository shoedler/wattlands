extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.5 panic: emergency_safe() turns ERG off and sets SIM grade 0 and wind 0
## immediately (no coalescing wait), overrides every other rule (4.6.12) and stays safe until
## resume(); the plan then resumes from the floor with slew. OWNERSHIP GOV13 (panic during an
## Overdrive SIM block).


func test_immediate_sim_flat_from_erg() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 100.0, 120.0)])
	rig.run(20.0)
	var dev: ScriptedDevice = rig.device
	var n := dev.writes.size()
	rig.gov.emergency_safe()
	assert_eq(dev.writes.size(), n + 1, "written in the call itself, no tick needed")
	var w: Dictionary = dev.writes[dev.writes.size() - 1]
	assert_eq(w["op"], "sim")
	assert_almost_eq(float(w["grade_pct"]), 0.0, 1e-9)
	assert_almost_eq(float(w["wind_mps"]), 0.0, 1e-9)
	assert_eq(dev.mode, Wl.SIM, "ERG off")
	assert_true(rig.s()["panic"])
	assert_true(rig.gov.is_panic())
	assert_eq(rig.s()["clamped_by"], [Wl.CLAMP_PANIC])
	assert_eq(int(rig.s()["applied_target_w"]), 0)
	assert_eq(rig.events_named("panic_changed").size(), 1)


func test_bypasses_coalescing() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 50.0, 60.0), erg(Wl.WORK, 100.0, 60.0)])
	rig.run(10.0)
	rig.gov.start_phase(1)
	rig.step()
	var dev: ScriptedDevice = rig.device
	var last := dev.writes[dev.writes.size() - 1]
	assert_almost_eq(float(last["t"]), rig.t, 1e-9, "a write in this very tick")
	rig.gov.emergency_safe()
	assert_eq(dev.writes[dev.writes.size() - 1]["op"], "sim", "panic still writes at once")


func test_stays_safe_until_resume() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 100.0, 60.0), sim(Wl.GRADE_GAME, 60.0), erg(Wl.WORK, 120.0, 60.0)])
	rig.run(20.0)
	rig.gov.emergency_safe()
	var dev: ScriptedDevice = rig.device
	var n := dev.writes.size()
	rig.gov.start_phase(1)
	rig.gov.set_course_grade(8.0)
	rig.run(10.0)
	rig.gov.start_phase(2)
	rig.run(30.0)
	assert_eq(dev.writes.size(), n, "nothing written while panic holds")
	assert_eq(dev.mode, Wl.SIM)
	assert_almost_eq(dev.grade_pct, 0.0, 1e-9)
	assert_true(rig.s()["panic"])


func test_resume_from_the_floor_with_slew() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 100.0, 120.0)])
	rig.run(20.0)
	rig.gov.emergency_safe()
	rig.run(5.0)
	var dev: ScriptedDevice = rig.device
	var n := dev.writes.size()
	rig.gov.resume()
	assert_false(rig.s()["panic"])
	rig.step()
	assert_eq(dev.writes[n]["op"], "erg")
	assert_eq(int(dev.writes[n]["w"]), 60, "resumes from the floor")
	rig.run(1.0)
	assert_lte(rig.applied_w(), 60 + 30)
	rig.run(5.0)
	assert_eq(rig.applied_w(), 200)
	var ev := rig.events_named("panic_changed")
	assert_eq(ev.size(), 2)
	assert_eq(ev[1]["value"], false)


func test_panic_during_a_sim_block() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 65.0, 600.0)])
	rig.run(40.0)
	rig.gov.shift(6)
	var rec := rig.directive({"mode": "SIM", "duration_s": 30.0, "reason": "overdrive", "source": "siege"})
	assert_false(rec["refused"])
	rig.gov.shift(6)
	rig.run(5.0)
	var dev: ScriptedDevice = rig.device
	assert_eq(dev.mode, Wl.SIM)
	assert_gt(dev.grade_pct, 0.0, "geared up in the block")
	rig.gov.emergency_safe()
	assert_almost_eq(dev.grade_pct, 0.0, 1e-9, "grade 0 at once")
	assert_almost_eq(dev.wind_mps, 0.0, 1e-9)


func test_panic_overrides_rescue_and_coasting() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 100.0, 120.0)])
	rig.run(20.0)
	var dev: ScriptedDevice = rig.device
	dev.cadence_rpm = 30.0
	rig.run(5.0)
	assert_true(rig.s()["rescue"])
	rig.gov.emergency_safe()
	rig.run(2.0)
	assert_eq(rig.s()["clamped_by"], [Wl.CLAMP_PANIC])
	assert_eq(dev.mode, Wl.SIM)


func test_sim_block_refused_during_panic() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 65.0, 600.0)])
	rig.run(40.0)
	rig.gov.emergency_safe()
	var rec := rig.directive({"mode": "SIM", "duration_s": 20.0})
	assert_true(rec["refused"])
	assert_eq(rec["reason"], Wl.REFUSE_SIM_BLOCK_UNSAFE)
