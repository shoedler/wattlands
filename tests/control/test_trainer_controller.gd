extends GutTest
## TrainerController (BRIEF 4.1, 4.5, 4.6.2, 4.6.5, 4.6.9): coalescing to at most 2 control
## writes per second with superseded commands dropped and the newest always sent; slew;
## ramped ERG <-> SIM switches; immediate panic and shutdown writes; RESISTANCE (P1).

const ScriptedDevice := preload("res://tests/governor/scripted_device.gd")
const DT := Wl.SIM_DT

var _dev: ScriptedDevice = null
var _ctl: TrainerController = null


func before_each() -> void:
	_dev = autofree(ScriptedDevice.new())
	_ctl = autofree(TrainerController.new())
	_ctl.setup(_dev)


func _step(n: int = 1) -> void:
	for i in n:
		_dev.tick(DT)
		_ctl.tick(DT)


func _run(seconds: float) -> void:
	_step(roundi(seconds / DT))


func test_at_most_2_writes_per_second_newest_sent() -> void:
	var commanded: Array[int] = []
	for i in 200:
		var w := 100 + i
		commanded.append(w)
		_ctl.command_erg(w, 60, 1000.0)
		_step()
	_run(1.0)
	assert_lte(_dev.max_writes_in_window(1.0), 2, "<= 2 writes in any 1 s")
	var ergs := _dev.writes_of("erg")
	assert_between(ergs.size(), 15, 22, "about 2 per second over 10 s")
	assert_lt(ergs.size(), commanded.size() / 5, "superseded commands are dropped")
	assert_eq(int(ergs[ergs.size() - 1]["w"]), 299, "the newest command is sent")
	for i in range(1, ergs.size()):
		assert_gte(float(ergs[i]["t"]) - float(ergs[i - 1]["t"]), 0.5 - 1e-6)


func test_sim_writes_coalesce_too() -> void:
	for i in 100:
		_ctl.command_sim(0.0, float(i) * 0.1, 0.004, 0.51, 60, 0.0)
		_step()
	_run(1.0)
	assert_lte(_dev.max_writes_in_window(1.0), 2)
	assert_almost_eq(_dev.grade_pct, 9.9, 1e-9, "the newest grade")


func test_a_command_superseded_within_one_slot_is_never_written() -> void:
	_ctl.command_erg(100, 60, 1000.0)
	_step()
	var n := _dev.writes.size()
	_ctl.command_erg(150, 60, 1000.0)
	_step()
	_ctl.command_erg(90, 60, 1000.0)
	_run(0.6)
	var after := _dev.writes.slice(n)
	assert_eq(after.size(), 1)
	assert_eq(int(after[0]["w"]), 90, "150 W was superseded")


func test_no_write_without_a_change() -> void:
	_ctl.command_erg(100, 60, 1000.0)
	_run(2.0)
	var n := _dev.writes.size()
	_run(5.0)
	assert_eq(_dev.writes.size(), n)
	_ctl.command_sim(0.0, 2.0, 0.004, 0.51, 60, 100.0)
	_run(3.0)
	var m := _dev.writes.size()
	_ctl.command_sim(0.0, 2.001, 0.004, 0.51, 60, 100.0)
	_run(2.0)
	assert_eq(_dev.writes.size(), m, "below the 0.01% FTMS resolution: no write")


func test_slew_up_30_w_per_s_and_immediate_decrease() -> void:
	_ctl.command_erg(100, 60, 100.0)
	_run(1.0)
	assert_eq(_ctl.applied_target_w(), 100, "first command: entry at min(3 s power, target)")
	_ctl.command_erg(250, 60, 100.0)
	_run(1.0)
	assert_eq(_ctl.applied_target_w(), 130, "+30 W in 1 s")
	_run(4.0)
	assert_eq(_ctl.applied_target_w(), 250)
	_ctl.command_erg(120, 60, 100.0)
	_step()
	assert_eq(_ctl.applied_target_w(), 120, "decrease at once")


func test_erg_to_sim_sequence() -> void:
	_ctl.command_erg(200, 60, 1000.0)
	_run(2.0)
	var n := _dev.writes.size()
	_ctl.command_sim(0.0, 3.0, 0.004, 0.51, 60, 150.0)
	_run(2.0)
	var w := _dev.writes.slice(n)
	assert_eq(w.size(), 3)
	assert_eq([w[0]["op"], w[1]["op"], w[2]["op"]], ["erg", "sim", "sim"])
	assert_eq(int(w[0]["w"]), 150, "min(applied 200, 3 s power 150)")
	assert_almost_eq(float(w[1]["grade_pct"]), 0.0, 1e-9)
	assert_almost_eq(float(w[2]["grade_pct"]), 3.0, 1e-9)
	assert_eq(_ctl.mode(), Wl.SIM)


func test_erg_to_sim_with_low_power_steps_to_the_floor() -> void:
	_ctl.command_erg(200, 60, 1000.0)
	_run(2.0)
	var n := _dev.writes.size()
	_ctl.command_sim(0.0, 0.0, 0.004, 0.51, 60, 0.0)
	_run(2.0)
	var w := _dev.writes.slice(n)
	assert_eq(int(w[0]["w"]), 60)
	assert_eq(w.size(), 2, "then SIM flat, which is already the target state")


func test_sim_to_erg_sequence() -> void:
	_ctl.command_sim(0.0, 4.0, 0.004, 0.51, 60, 300.0)
	_run(2.0)
	var n := _dev.writes.size()
	_ctl.command_erg(180, 60, 300.0)
	_run(2.0)
	var w := _dev.writes.slice(n)
	assert_eq(w[0]["op"], "sim")
	assert_almost_eq(float(w[0]["grade_pct"]), 0.0, 1e-9, "grade 0 first")
	assert_eq(w[1]["op"], "erg")
	assert_eq(int(w[1]["w"]), 180, "min(3 s power 300, target 180)")
	assert_false(_ctl.entry_active())


func test_sim_to_erg_entry_and_entry_flag() -> void:
	_ctl.command_sim(0.0, 0.0, 0.004, 0.51, 60, 0.0)
	_run(1.0)
	_ctl.command_erg(180, 60, 100.0)
	_step()
	assert_eq(_dev.writes[_dev.writes.size() - 1]["w"], 100)
	assert_true(_ctl.entry_active())
	assert_true(_ctl.in_transition() == false)
	_run(3.0)
	assert_eq(_ctl.applied_target_w(), 180)
	assert_false(_ctl.entry_active())


func test_switch_cancelled_midway() -> void:
	_ctl.command_erg(200, 60, 1000.0)
	_run(2.0)
	_ctl.command_sim(0.0, 0.0, 0.004, 0.51, 60, 120.0)
	_step()
	assert_eq(_dev.target_w, 120, "stepped down")
	_ctl.command_erg(200, 60, 120.0)
	_run(5.0)
	assert_eq(_dev.mode, Wl.ERG)
	assert_eq(_dev.target_w, 200, "slews back up from the step")
	assert_eq(_dev.writes_of("sim").size(), 0)


func test_emergency_safe_is_immediate_and_holds() -> void:
	_ctl.command_erg(200, 60, 1000.0)
	_step()
	var n := _dev.writes.size()
	_ctl.emergency_safe(0.004, 0.51)
	assert_eq(_dev.writes.size(), n + 1, "same call, no slot wait")
	assert_eq(_dev.mode, Wl.SIM)
	assert_almost_eq(_dev.grade_pct, 0.0, 1e-9)
	assert_true(_ctl.is_safe())
	_ctl.command_erg(250, 60, 1000.0)
	_run(5.0)
	assert_eq(_dev.writes.size(), n + 1, "holds until release_safe()")
	_ctl.release_safe()
	_step()
	assert_eq(int(_dev.writes[_dev.writes.size() - 1]["w"]), 60, "resume from the floor")


func test_shutdown_sim_flat_then_stop() -> void:
	_ctl.command_erg(200, 60, 1000.0)
	_step()
	var n := _dev.writes.size()
	_ctl.shutdown(0.004, 0.51)
	var w := _dev.writes.slice(n)
	assert_eq(w.size(), 2, "both at once")
	assert_eq(w[0]["op"], "sim")
	assert_almost_eq(float(w[0]["grade_pct"]), 0.0, 1e-9)
	assert_almost_eq(float(w[0]["wind_mps"]), 0.0, 1e-9)
	assert_eq(w[1]["op"], "stop")
	assert_eq(_dev.stops, 1)
	assert_eq(_ctl.mode(), Wl.OFF)
	assert_true(_ctl.is_stopped())
	_ctl.command_erg(250, 60, 1000.0)
	_run(3.0)
	_ctl.shutdown(0.004, 0.51)
	assert_eq(_dev.writes.size(), n + 2, "nothing after shutdown, and shutdown runs once")


func test_command_off_writes_nothing() -> void:
	_ctl.command_off()
	_run(3.0)
	assert_eq(_dev.writes.size(), 0)


func test_no_device_is_safe() -> void:
	var ctl: TrainerController = autofree(TrainerController.new())
	ctl.command_erg(200, 60, 100.0)
	ctl.tick(DT)
	ctl.emergency_safe(0.004, 0.51)
	ctl.shutdown(0.004, 0.51)
	assert_eq(ctl.write_count(), 0)


func test_resistance_mode_p1() -> void:
	_ctl.command_resistance(20.0)
	_step()
	assert_eq(_dev.mode, Wl.RESISTANCE)
	assert_almost_eq(_dev.level, 20.0, 1e-9)
	for i in 40:
		_ctl.command_resistance(20.0 + i)
		_step()
	assert_lte(_dev.max_writes_in_window(1.0), 2)


func test_write_log() -> void:
	_ctl.command_erg(200, 60, 200.0)
	_step()
	var entries := _ctl.write_log()
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["op"], TrainerController.OP_ERG)
	assert_eq(_ctl.write_count(), 1)
	assert_eq(_ctl.process_mode, Node.PROCESS_MODE_ALWAYS)
