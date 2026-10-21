extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.1 and OWNERSHIP GOV12: pause puts the trainer at the ERG floor or SIM flat, stops
## game time (phase elapsed, ramps, directive expiry) and keeps trainer I/O, rescue and
## coasting running on platform time.


func test_erg_floor_while_paused() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 160)
	rig.gov.set_game_paused(true)
	rig.step()
	assert_eq(rig.applied_w(), 60)
	assert_true(rig.s()["paused"])
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_PAUSE)
	rig.run(2.0)
	var dev: ScriptedDevice = rig.device
	assert_eq(dev.target_w, 60, "the trainer got the floor")
	rig.gov.set_game_paused(false)
	rig.run(5.0)
	assert_eq(rig.applied_w(), 160, "back to the plan with slew")


func test_sim_flat_while_paused() -> void:
	var rig := make_rig({}, follower())
	rig.start([sim(Wl.GRADE_GAME, 600.0)])
	rig.gov.set_course_grade(8.0)
	rig.run(5.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 4.0, 1e-9)
	rig.gov.set_game_paused(true)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 0.0, 1e-9)
	var dev: ScriptedDevice = rig.device
	assert_almost_eq(dev.grade_pct, 0.0, 1e-9)
	rig.gov.set_game_paused(false)
	rig.run(1.0)
	assert_almost_eq(dev.grade_pct, 4.0, 1e-9)


func test_phase_time_stops() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	rig.run(10.0)
	rig.gov.set_game_paused(true)
	rig.run(30.0)
	assert_almost_eq(float(rig.s()["phase_elapsed_s"]), 10.0, 1e-6)
	assert_almost_eq(rig.gov.game_time_s(), 10.0, 1e-6)
	assert_almost_eq(rig.gov.platform_time_s(), 40.0, 1e-6)


func test_trainer_io_and_coasting_continue() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	rig.run(10.0)
	rig.gov.set_game_paused(true)
	var dev: ScriptedDevice = rig.device
	var samples := dev.samples_sent
	dev.erg_follow = -1.0
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0
	rig.run(5.0)
	assert_gt(dev.samples_sent, samples)
	assert_true(rig.s()["coasting"], "coasting runs on platform time")


func test_governor_runs_with_the_tree_paused() -> void:
	# BRIEF 4.1: pause never uses SceneTree.paused for system nodes.
	var rig := make_rig({}, follower())
	assert_eq(rig.gov.process_mode, Node.PROCESS_MODE_ALWAYS)
	var ctl: Node = rig.gov.get_child(0)
	assert_true(ctl is TrainerController)
	assert_eq(ctl.process_mode, Node.PROCESS_MODE_ALWAYS)
