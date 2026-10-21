extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.2 slew: increases at most 30 W/s, decreases immediately; slew applies last
## (4.6.12). Also S2.3's 50 -> 117% step at FTP 400 in <= 9 s.


func _trace_rig(params: Dictionary = {}) -> Rig:
	var rig := make_rig(params, follower())
	rig.keep_trace = true
	return rig


func test_increase_at_most_30_w_per_s() -> void:
	var rig := _trace_rig()
	rig.start([erg(Wl.WORK, 50.0, 60.0), erg(Wl.WORK, 100.0, 60.0)])
	rig.run(20.0)
	rig.gov.start_phase(1)
	rig.run(20.0)
	var tr := rig.trace
	var worst_1s := 0
	var worst_tick := 0
	for i in tr.size():
		var a := int(tr[i]["applied_target_w"])
		if i > 0:
			worst_tick = maxi(worst_tick, a - int(tr[i - 1]["applied_target_w"]))
		if i + 20 < tr.size():
			worst_1s = maxi(worst_1s, int(tr[i + 20]["applied_target_w"]) - a)
	assert_lte(worst_1s, 30, "never more than 30 W in any 1 s")
	assert_lte(worst_tick, 2, "1.5 W per 0.05 s tick, rounded down to whole watts")
	assert_eq(rig.applied_w(), 200, "reaches the 100% target")


func test_step_up_takes_target_difference_over_30() -> void:
	var rig := _trace_rig()
	rig.start([erg(Wl.WORK, 50.0, 60.0), erg(Wl.WORK, 100.0, 60.0)])
	rig.run(10.0)
	assert_eq(rig.applied_w(), 100)
	rig.gov.start_phase(1)
	var t0 := rig.t
	var reached := rig.run_until(func() -> bool: return rig.applied_w() >= 200, 10.0)
	assert_gt(reached, 0.0)
	# 100 W at 30 W/s: 3.33 s, i.e. on the 67th tick.
	assert_almost_eq(reached - t0, 100.0 / 30.0, DT, "100 -> 200 W takes 3.33 s")


func test_slew_reported_in_clamped_by_while_it_bites() -> void:
	var rig := _trace_rig()
	rig.start([erg(Wl.WORK, 50.0, 60.0), erg(Wl.WORK, 100.0, 60.0)])
	rig.run(10.0)
	rig.gov.start_phase(1)
	rig.run(1.0)
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_SLEW)
	assert_eq(int(rig.s()["governed_target_w"]), 200, "governed target is the unslewed 200 W")
	rig.run(4.0)
	assert_does_not_have(rig.s()["clamped_by"], Wl.CLAMP_SLEW)


func test_decrease_is_immediate() -> void:
	var rig := _trace_rig()
	rig.start([erg(Wl.WORK, 100.0, 60.0), erg(Wl.RECOVERY, 50.0, 60.0)])
	rig.run(15.0)
	assert_eq(rig.applied_w(), 200)
	rig.gov.start_phase(1)
	rig.step()
	assert_eq(rig.applied_w(), 100, "200 -> 100 W within one tick")


func test_siege_50_to_117_pct_at_ftp_400_in_9_s() -> void:
	var rig := _trace_rig({"ftp_w": 400.0})
	rig.start([erg(Wl.WORK, 50.0, 60.0), erg(Wl.WORK, 117.0, 240.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 200)
	rig.gov.start_phase(1)
	var t0 := rig.t
	var reached := rig.run_until(func() -> bool: return rig.applied_w() >= 468, 12.0)
	assert_gt(reached, 0.0)
	assert_lte(reached - t0, 9.0, "50 -> 117% at FTP 400 within 9 s (S2.3)")
	assert_gte(reached - t0, 8.9, "and no faster than 30 W/s")


func test_device_writes_climb_15_w_per_half_second() -> void:
	var rig := _trace_rig()
	rig.start([erg(Wl.WORK, 50.0, 60.0), erg(Wl.WORK, 150.0, 60.0)])
	rig.run(10.0)
	rig.gov.start_phase(1)
	var since := rig.t
	rig.run(10.0)
	var dev: ScriptedDevice = rig.device
	var ergs := dev.writes_of("erg", since)
	assert_gt(ergs.size(), 5)
	for i in range(1, ergs.size()):
		var up := int(ergs[i]["w"]) - int(ergs[i - 1]["w"])
		assert_lte(up, 15, "at most 15 W per write slot")
		assert_gte(
			float(ergs[i]["t"]) - float(ergs[i - 1]["t"]), 0.5 - 1e-6, "writes >= 0.5 s apart"
		)
	assert_eq(int(ergs[ergs.size() - 1]["w"]), 300)
