extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.9 exit path (SIM flat, then Stop) and BRIEF 4.5 coalescing through the whole
## governor: a busy session (2 Hz ERG ramps, 20 Hz course grades, gear shifts, SIM blocks)
## never sends more than 2 control writes in any second, and the newest command wins.


func test_shutdown_from_erg() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	rig.run(10.0)
	var dev: ScriptedDevice = rig.device
	var n := dev.writes.size()
	rig.gov.shutdown()
	var w := dev.writes.slice(n)
	assert_eq(w.size(), 2)
	assert_eq(w[0]["op"], "sim")
	assert_almost_eq(float(w[0]["grade_pct"]), 0.0, 1e-9)
	assert_almost_eq(float(w[0]["wind_mps"]), 0.0, 1e-9)
	assert_almost_eq(float(w[0]["crr"]), 0.004, 1e-12)
	assert_almost_eq(float(w[0]["cw"]), 0.51, 1e-12)
	assert_eq(w[1]["op"], "stop")
	assert_eq(rig.s()["mode"], Wl.OFF)
	assert_true(rig.s()["shut_down"])
	rig.run(5.0)
	rig.gov.emergency_safe()
	rig.directive({"target_pct": 80.0})
	rig.run(5.0)
	assert_eq(dev.writes.size(), n + 2, "nothing after shutdown")


func test_shutdown_from_sim_and_before_setup() -> void:
	var rig := make_rig({}, follower())
	rig.start([sim(Wl.GRADE_GAME, 600.0)])
	rig.gov.set_course_grade(8.0)
	rig.run(3.0)
	var dev: ScriptedDevice = rig.device
	rig.gov.shutdown()
	assert_eq(dev.writes[dev.writes.size() - 2]["op"], "sim")
	assert_almost_eq(float(dev.writes[dev.writes.size() - 2]["grade_pct"]), 0.0, 1e-9)
	assert_eq(dev.writes[dev.writes.size() - 1]["op"], "stop")
	var lone: SafetyGovernor = autofree(SafetyGovernor.new())
	lone.shutdown()
	assert_true(lone.status()["shut_down"], "no device: nothing to write, no crash")


func test_setup_again_revives_after_shutdown() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	rig.run(5.0)
	rig.gov.shutdown()
	var dev2 := ScriptedDevice.new()
	dev2.erg_follow = 1.0
	autofree(dev2)
	rig.gov.setup(dev2)
	dev2.sample_received.connect(rig.gov.on_sample)
	for i in 40:
		dev2.tick(DT)
		rig.gov.tick(DT)
	assert_gt(dev2.writes.size(), 0)
	assert_eq(dev2.writes[0]["op"], "erg", "the reconnect re-enters ERG through the entry rule")
	assert_eq(int(dev2.writes[0]["w"]), 60)


func test_busy_session_never_exceeds_2_writes_per_second() -> void:
	var rig := make_rig({"haptic_intensity": 1.0}, follower())
	rig.start(
		[
			erg(Wl.WORK, 70.0, 120.0).with_range(60.0, 110.0),
			sim(Wl.GRADE_GAME, 120.0),
			erg(Wl.WORK, 65.0, 120.0)
		]
	)
	for i in 2400:
		if i % 10 == 0:
			rig.directive(
				{
					"mode": "ERG",
					"target_pct": 60.0 + float(i % 500) / 10.0,
					"duration_s": 0.0,
					"reason": "pull"
				}
			)
		rig.step()
	rig.gov.start_phase(1)
	for i in 2400:
		rig.gov.set_course_grade(sin(float(i) * 0.01) * 6.0)
		if i % 6 == 0:
			rig.gov.shift(1 if (i / 6) % 4 < 2 else -1)
		if i % 400 == 0:
			rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5})
		rig.step()
	rig.gov.start_phase(2)
	for i in 2400:
		if i % 800 == 100:
			rig.directive({"mode": "SIM", "duration_s": 15.0, "reason": "overdrive"})
		rig.step()
	var dev: ScriptedDevice = rig.device
	assert_gt(dev.writes.size(), 100, "a busy session")
	assert_lte(dev.max_writes_in_window(1.0), 2, "at most 2 control writes per second")
	assert_eq(rig.s()["mode"], Wl.ERG)
	assert_eq(dev.target_w, rig.applied_w(), "the newest target reached the trainer")
