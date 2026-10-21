extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.1: phases longer than 300 s cap at 105% FTP, where a phase's length is its
## planned duration_s or, for an open-ended phase, its max_s; the cap covers every directive
## inside it. Fishing's 104% marlin jumps (F2.3) stay below it unclamped.


func test_phase_over_300_s_caps_at_105() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 110.0, 400.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 210)
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_LONG_PHASE)


func test_phase_of_exactly_300_s_is_not_capped() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 110.0, 300.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 220)
	assert_does_not_have(rig.s()["clamped_by"], Wl.CLAMP_LONG_PHASE)


func test_open_ended_phase_uses_max_s() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 110.0, 120.0).with_open(60.0, 360.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 210, "nominal 120 s but max_s 360 s")
	var rig2 := make_rig({}, follower())
	rig2.start([erg(Wl.WORK, 110.0, 0.0).with_open(60.0, 300.0)])
	rig2.run(20.0)
	assert_eq(rig2.applied_w(), 220, "max_s 300 is not longer than 300 s")


func test_cap_covers_directives() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 0.0).with_open(120.0, 540.0).with_range(80.0, 120.0)])
	rig.run(10.0)
	var rec := rig.directive({"mode": "ERG", "target_pct": 115.0, "duration_s": 20.0, "reason": "run"})
	assert_false(rec["refused"])
	assert_eq(int(rec["applied"]["target_w"]), 210)
	assert_has(rec["clamped_by"], Wl.CLAMP_LONG_PHASE)
	rig.run(15.0)
	assert_eq(rig.applied_w(), 210)


func test_fishing_marlin_104_pct_is_not_clamped() -> void:
	# F2.3: marlin jumps stop at 104% in a 1320 s open-ended fight; clamped_by never names
	# the ceiling, the long-phase cap or a duration limit (F4.2 #1).
	for ftp: float in [100.0, 199.0, 200.0, 201.0, 333.0, 500.0]:
		var rig := make_rig({"ftp_w": ftp}, follower())
		rig.start([erg(Wl.WORK, 80.0, 0.0).with_open(300.0, 1320.0).with_range(72.0, 104.0)])
		rig.run(5.0)
		var rec := rig.directive({"mode": "ERG", "target_pct": 104.0, "duration_s": 12.0, "reason": "jump", "source": "fishing"})
		assert_false(rec["refused"], "FTP %s" % ftp)
		var cb: Array = rec["clamped_by"]
		for name: String in [Wl.CLAMP_CEILING, Wl.CLAMP_LONG_PHASE, Wl.CLAMP_LIMIT_105, Wl.CLAMP_LIMIT_120]:
			assert_does_not_have(cb, name, "FTP %s" % ftp)
		assert_eq(int(rec["applied"]["target_w"]), GovernorClamps.whole_w(1.04 * ftp), "FTP %s" % ftp)


func test_tuna_104_8_pct_at_cap_boundary() -> void:
	# 104.8% of 200 W is 209.6 W -> 209 W, under the 210 W cap.
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 85.0, 0.0).with_open(300.0, 540.0).with_range(80.0, 104.8)])
	rig.run(5.0)
	var rec := rig.directive({"target_pct": 104.8})
	assert_eq(int(rec["applied"]["target_w"]), 209)
	assert_does_not_have(rec["clamped_by"], Wl.CLAMP_LONG_PHASE)
