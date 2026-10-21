extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.1: while FTP is unverified, every ERG target (plan, ramp, directive, the
## cool-down) is multiplied by 0.85, before the caps; rescue's 50% and the floor are not.
## Rescue arms on the governed target after the factor (4.6.3).

const UNV := {"ftp_verified": false}


func test_plan_target() -> void:
	var rig := make_rig(UNV, follower())
	rig.start([erg(Wl.WORK, 100.0, 120.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 170)
	assert_eq(rig.s()["clamped_by"], [Wl.CLAMP_UNVERIFIED])


func test_ramp_and_directive() -> void:
	var rig := make_rig(UNV, follower())
	rig.start([erg(Wl.WORK, 50.0, 100.0).with_ramp(70.0).with_range(50.0, 100.0)])
	rig.run(50.0)
	assert_eq(int(rig.s()["governed_target_w"]), GovernorClamps.whole_w(0.85 * 2.0 * 60.0))
	var rec := rig.directive({"target_pct": 90.0})
	assert_eq(int(rec["applied"]["target_w"]), 153)
	assert_has(rec["clamped_by"], Wl.CLAMP_UNVERIFIED)


func test_target_w_converted_before_the_factor() -> void:
	var rig := make_rig(UNV, follower())
	rig.start([erg(Wl.WORK, 50.0, 100.0).with_range(50.0, 100.0)])
	var rec := rig.directive({"target_w": 180.0})
	assert_false(rec["refused"], "180 W = 90% is inside the range")
	assert_almost_eq(float(rec["applied"]["target_pct"]), 90.0, 1e-9)
	assert_eq(int(rec["applied"]["target_w"]), 153)


func test_cooldown_target_and_floor() -> void:
	var rig := make_rig(UNV, follower())
	rig.gov.set_plan(plan_with_cooldown([erg(Wl.WORK, 30.0, 60.0)]))
	rig.gov.start_phase(0)
	rig.run(10.0)
	assert_eq(rig.applied_w(), 60, "30% x 0.85 = 51 W, lifted to the 60 W floor")
	assert_eq(rig.s()["clamped_by"], [Wl.CLAMP_UNVERIFIED, Wl.CLAMP_FLOOR])
	rig.gov.start_phase(1)
	rig.run(2.0)
	assert_eq(rig.applied_w(), 85, "the cool-down's 50% x 0.85")


func test_rescue_50_pct_is_not_factored() -> void:
	var rig := make_rig(UNV, follower())
	rig.start([erg(Wl.WORK, 100.0, 120.0)])
	rig.run(20.0)
	var dev: ScriptedDevice = rig.device
	dev.cadence_rpm = 30.0
	rig.run(5.0)
	assert_true(rig.s()["rescue"])
	assert_eq(rig.applied_w(), 100, "50% of 200 W, not x0.85")


func test_rescue_arms_on_the_factored_target() -> void:
	# 70% x 0.85 = 59.5% (119 W): not armed. 71% x 0.85 = 60.35% (120 W): armed.
	var rig := make_rig(UNV, follower(30.0))
	rig.start([erg(Wl.WORK, 70.0, 120.0)])
	rig.run(20.0)
	assert_false(rig.s()["rescue"])
	var rig2 := make_rig(UNV, follower(30.0))
	rig2.start([erg(Wl.WORK, 71.0, 120.0)])
	rig2.run(20.0)
	assert_true(rig2.s()["rescue"])


func test_verified_rider_has_no_factor() -> void:
	var rig := make_rig({"ftp_verified": true}, follower())
	rig.start([erg(Wl.WORK, 100.0, 120.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 200)
	assert_eq((rig.s()["clamped_by"] as Array).size(), 0)
