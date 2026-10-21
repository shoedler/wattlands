extends "res://tests/governor/gov_test_base.gd"
## Reconnects and re-configuration (W2): BRIEF 4.4 "restore the last safe mode" after a
## reconnect, through the normal ramped path (4.5 switch rules, 4.6.2 slew); setup(device)
## again rebinds to a new device object and keeps plan, phase and warm-up; configure() again
## replaces parameters and keeps plan, phase and warm-up; status() carries haptic_pct.


## The connection flow's last step on the device (FtmsClient.begin(): SIM flat).
func _flow(dev: ScriptedDevice) -> void:
	dev.set_simulation(0.0, 0.0, 0.004, 0.51)


func test_reconnect_restores_erg_from_the_floor_with_slew() -> void:
	var dev: ScriptedDevice = follower()
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 100.0, 1200.0)])
	rig.run(30.0)
	assert_eq(dev.target_w, 200)
	# Outage: no samples for 4 s, then the flow resets the trainer to SIM flat and samples
	# resume 1 s after the reconnect.
	dev.set("_next_sample_t", rig.t + 1000.0)
	rig.run(4.0)
	_flow(dev)
	var n := dev.writes.size()
	var t0 := rig.t
	rig.gov.on_trainer_reconnected()
	dev.set("_next_sample_t", rig.t + 1.0)
	assert_eq(rig.s()["phase_index"], 0, "the phase is kept")
	rig.run(0.45)
	assert_eq(dev.writes.size(), n, "the flow's write holds the slot")
	rig.run(0.1)
	var first := dev.writes[n]
	assert_eq(first["op"], "erg", "already flat: straight to the ERG entry")
	assert_eq(int(first["w"]), 60, "the floor: the stale 3 s power was dropped")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_SLEW)
	rig.run(10.0)
	var ergs := dev.writes_of("erg", t0)
	for i in range(1, ergs.size()):
		var dw := float(int(ergs[i]["w"]) - int(ergs[i - 1]["w"]))
		var dt := float(ergs[i]["t"]) - float(ergs[i - 1]["t"])
		assert_lte(dw, 30.0 * dt + 1e-6, "30 W/s at most")
	assert_eq(dev.target_w, 200, "back at the plan target")
	assert_lte(dev.max_writes_in_window(1.0), 2)


func test_reconnect_restores_the_stacked_sim_grade() -> void:
	var dev: ScriptedDevice = follower()
	var rig := make_rig({"difficulty_pct": 100.0}, dev)
	rig.start([sim(Wl.GRADE_GAME, 1200.0)])
	rig.gov.set_course_grade(5.0)
	rig.run(10.0)
	assert_almost_eq(dev.grade_pct, 5.0, 1e-9)
	_flow(dev)
	var n := dev.writes.size()
	rig.gov.on_trainer_reconnected()
	rig.run(1.0)
	var after := dev.writes.slice(n)
	assert_eq(after.size(), 1, "one write restores SIM")
	assert_eq(after[0]["op"], "sim")
	assert_almost_eq(float(after[0]["grade_pct"]), 5.0, 1e-9, "the stacked grade")
	assert_eq(rig.s()["mode"], Wl.SIM)


func test_reconnect_keeps_warmup_rescue_limits_and_gear() -> void:
	var dev: ScriptedDevice = follower()
	var rig := make_rig({"skip_warmup": false}, dev)
	rig.start([erg(Wl.WARMUP, 50.0, 600.0)])
	rig.run(100.0)
	var before := rig.s()
	assert_true(before["warmup_active"])
	_flow(dev)
	rig.gov.on_trainer_reconnected()
	var after := rig.s()
	assert_true(after["warmup_active"], "warm-up is not restarted or ended")
	assert_almost_eq(float(after["warmup_remaining_s"]), float(before["warmup_remaining_s"]), 1e-9)
	assert_eq(after["gear"], before["gear"])
	assert_eq(after["s_left_105"], before["s_left_105"])
	assert_eq(after["last_switch_t"], before["last_switch_t"], "a reconnect is no directive switch")
	assert_eq(after["phase_elapsed_s"], before["phase_elapsed_s"])


func test_reconnect_during_panic_resends_sim_flat_and_stays_safe() -> void:
	var dev: ScriptedDevice = follower()
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 100.0, 1200.0)])
	rig.run(20.0)
	rig.gov.emergency_safe()
	_flow(dev)
	var n := dev.writes.size()
	rig.gov.on_trainer_reconnected()
	assert_eq(dev.writes.size(), n + 1, "SIM flat at once")
	assert_eq(dev.writes[n]["op"], "sim")
	assert_almost_eq(float(dev.writes[n]["grade_pct"]), 0.0, 1e-9)
	rig.run(5.0)
	assert_eq(dev.writes.size(), n + 1, "safe until resume()")
	assert_true(rig.s()["panic"])


func test_reconnect_after_shutdown_sends_nothing() -> void:
	var dev: ScriptedDevice = follower()
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 100.0, 1200.0)])
	rig.run(10.0)
	rig.gov.shutdown()
	var n := dev.writes.size()
	rig.gov.on_trainer_reconnected()
	rig.run(5.0)
	assert_eq(dev.writes.size(), n)
	assert_true(rig.s()["shut_down"])
	var lone: SafetyGovernor = autofree(SafetyGovernor.new())
	lone.on_trainer_reconnected()
	assert_eq(lone.status()["mode"], Wl.OFF, "no device: nothing happens")


func test_setup_again_rebinds_and_keeps_plan_phase_and_warmup() -> void:
	var dev: ScriptedDevice = follower()
	var rig := make_rig({"skip_warmup": false}, dev)
	rig.gov.set_plan(EffortPlan.of([erg(Wl.WARMUP, 50.0, 120.0), erg(Wl.WORK, 60.0, 600.0)]))
	rig.gov.start_phase(0)
	rig.run(120.0)
	rig.gov.start_phase(1)
	rig.run(30.0)
	var before := rig.s()
	var dev2: ScriptedDevice = follower()
	autofree(dev2)
	# LocalRider.rebind_device moves the sample feed to the new object, then rebinds.
	dev.sample_received.disconnect(rig.gov.on_sample)
	rig.gov.setup(dev2)
	dev2.sample_received.connect(rig.gov.on_sample)
	var old_writes := dev.writes.size()
	for i in roundi(20.0 / DT):
		dev2.tick(DT)
		rig.gov.tick(DT)
	var after := rig.s()
	assert_eq(after["phase_index"], 1, "the phase is kept")
	assert_almost_eq(float(after["phase_elapsed_s"]), float(before["phase_elapsed_s"]) + 20.0, 1e-6)
	assert_true(after["warmup_active"])
	assert_almost_eq(float(after["warmup_remaining_s"]), float(before["warmup_remaining_s"]) - 20.0, 1e-6,
		"warm-up keeps counting from the first pedal stroke")
	assert_eq(dev.writes.size(), old_writes, "the old device gets nothing more")
	assert_gt(dev2.writes.size(), 0)
	assert_eq(dev2.writes[0]["op"], "erg")
	assert_eq(int(dev2.writes[0]["w"]), 60, "entry at the floor on the new device")
	assert_eq(dev2.target_w, 120, "then the phase target (60%)")


func test_configure_again_replaces_parameters_and_keeps_state() -> void:
	var dev: ScriptedDevice = follower()
	var rig := make_rig({"skip_warmup": false, "ftp_verified": false}, dev)
	rig.start([erg(Wl.WARMUP, 60.0, 900.0)])
	rig.run(60.0)
	var before := rig.s()
	assert_eq(rig.applied_w(), 102, "unverified: 60% x 0.85 of 200 W")
	rig.gov.configure({"ftp_verified": true, "weight_kg": 80.0})
	rig.run(5.0)
	var after := rig.s()
	assert_eq(after["phase_index"], before["phase_index"])
	assert_almost_eq(float(after["phase_elapsed_s"]), float(before["phase_elapsed_s"]) + 5.0, 1e-6)
	assert_true(after["warmup_active"], "warm-up is kept")
	assert_almost_eq(float(after["warmup_remaining_s"]), float(before["warmup_remaining_s"]) - 5.0, 1e-6)
	assert_true(after["ftp_verified"])
	assert_eq(rig.applied_w(), 120, "the new parameter applies on the next ticks")
	rig.gov.configure({"ftp_w": 250.0})
	rig.run(5.0)
	assert_eq(rig.s()["phase_index"], 0)
	assert_eq(rig.applied_w(), 150, "60% of the new FTP")
	assert_eq(rig.s()["ftp_w"], 250.0)


func test_status_carries_haptic_pct() -> void:
	var dev: ScriptedDevice = follower()
	var rig := make_rig({"haptic_intensity": 0.5}, dev)
	rig.start([sim(Wl.GRADE_GAME, 600.0)])
	rig.run(1.0)
	assert_eq(float(rig.s()["haptic_pct"]), 0.0)
	var rec := rig.directive({"mode": "SIM", "haptic": 4.0, "duration_s": 2.0})
	assert_false(rec["refused"], str(rec))
	rig.run(0.5)
	assert_almost_eq(float(rig.s()["haptic_pct"]), 2.0, 1e-9, "after intensity")
	rig.run(3.0)
	assert_eq(float(rig.s()["haptic_pct"]), 0.0, "expired")
