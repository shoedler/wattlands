extends GutTest
## TrainerController.resync() (W2, BRIEF 4.4 "restore the last safe mode"): after a reconnect
## the trainer sits at SIM flat (the connection flow's last write), so the controller forgets
## what it last wrote and the newest command comes back through the ramped path (4.5 switch
## rules, 4.6.2 slew), within the 2 writes per second (4.5 coalescing).

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


## What the 4.4 connection flow does to the trainer: SIM flat (FtmsClient.begin()).
func _reconnect_flow() -> void:
	_dev.set_simulation(0.0, 0.0, 0.004, 0.51)


func test_erg_comes_back_through_the_entry_and_slew() -> void:
	_ctl.command_erg(250, 60, 250.0)
	_run(15.0)
	assert_eq(_dev.target_w, 250)
	_reconnect_flow()
	var n := _dev.writes.size()
	_ctl.resync(0.004, 0.51)
	assert_eq(_dev.writes.size(), n, "resync itself writes nothing outside a panic")
	assert_eq(_ctl.mode(), Wl.SIM, "the trainer is assumed at SIM flat")
	assert_eq(_ctl.written_target_w(), 0)
	assert_eq(_ctl.applied_target_w(), 0)
	# The rider's 3 s power is unknown after the outage: the governor passes 0, so the entry is
	# the floor, then the target rises at 30 W/s.
	_ctl.command_erg(250, 60, 0.0)
	_step()
	assert_eq(_dev.writes.size(), n, "the flow's SIM flat write holds the slot for 0.5 s")
	_run(0.5)
	var after := _dev.writes.slice(n)
	assert_eq(after.size(), 1)
	assert_eq(after[0]["op"], "erg", "SIM flat already: straight to the ERG entry")
	assert_eq(int(after[0]["w"]), 60, "entry at the floor (3 s power unknown)")
	assert_true(_ctl.entry_active())
	_run(10.0)
	assert_lte(_dev.max_writes_in_window(1.0), 2)
	var ergs := _dev.writes_of("erg", float(after[0]["t"]))
	for i in range(1, ergs.size()):
		var dw := int(ergs[i]["w"]) - int(ergs[i - 1]["w"])
		var dt := float(ergs[i]["t"]) - float(ergs[i - 1]["t"])
		assert_lte(float(dw), 30.0 * dt + 1e-6, "slew: at most 30 W/s between writes")
	assert_eq(_dev.target_w, 250, "back at the command")


func test_erg_entry_uses_the_fresh_3_s_power_but_never_above_the_command() -> void:
	_ctl.command_erg(200, 60, 200.0)
	_run(10.0)
	_reconnect_flow()
	_ctl.resync(0.004, 0.51)
	_ctl.command_erg(200, 60, 150.0)
	_run(0.6)
	var ergs := _dev.writes_of("erg", _dev.t - 0.6)
	assert_eq(int(ergs[0]["w"]), 150, "min(3 s power, command)")
	_reconnect_flow()
	_ctl.resync(0.004, 0.51)
	_ctl.command_erg(200, 60, 400.0)
	_run(0.6)
	ergs = _dev.writes_of("erg", _dev.t - 0.6)
	assert_eq(int(ergs[0]["w"]), 200, "never above the command")


func test_sim_state_is_written_again_even_when_it_equals_the_guess() -> void:
	_ctl.command_sim(0.0, 0.0, 0.004, 0.51, 60, 100.0)
	_run(2.0)
	_reconnect_flow()
	var n := _dev.writes.size()
	_ctl.resync(0.004, 0.51)
	_run(1.0)
	var after := _dev.writes.slice(n)
	assert_eq(after.size(), 1, "the flat SIM state is confirmed once")
	assert_eq(after[0]["op"], "sim")
	_run(3.0)
	assert_eq(_dev.writes.size(), n + 1, "then nothing without a change")


func test_sim_grade_comes_back_over_the_flat_trainer() -> void:
	_ctl.command_sim(0.0, 6.0, 0.004, 0.51, 60, 200.0)
	_run(2.0)
	assert_almost_eq(_dev.grade_pct, 6.0, 1e-9)
	_reconnect_flow()
	var n := _dev.writes.size()
	var t0 := _dev.t
	_ctl.resync(0.004, 0.51)
	_run(1.0)
	var after := _dev.writes.slice(n)
	assert_eq(after.size(), 1)
	assert_eq(after[0]["op"], "sim", "no ERG step: the trainer is already at SIM flat")
	assert_almost_eq(float(after[0]["grade_pct"]), 6.0, 1e-9)
	assert_gte(float(after[0]["t"]) - t0, 0.5 - 1e-6, "after the flow's slot")


func test_panic_hold_resends_sim_flat_at_once_and_stays_safe() -> void:
	_ctl.command_erg(200, 60, 200.0)
	_run(5.0)
	_ctl.emergency_safe(0.004, 0.51)
	_reconnect_flow()
	var n := _dev.writes.size()
	_ctl.resync(0.004, 0.51)
	assert_eq(_dev.writes.size(), n + 1, "SIM flat at once")
	assert_eq(_dev.writes[n]["op"], "sim")
	assert_almost_eq(float(_dev.writes[n]["grade_pct"]), 0.0, 1e-9)
	assert_true(_ctl.is_safe())
	_ctl.command_erg(250, 60, 250.0)
	_run(3.0)
	assert_eq(_dev.writes.size(), n + 1, "the panic hold continues")


func test_nothing_after_shutdown_or_without_a_device() -> void:
	_ctl.command_erg(200, 60, 200.0)
	_run(2.0)
	_ctl.shutdown(0.004, 0.51)
	var n := _dev.writes.size()
	_ctl.resync(0.004, 0.51)
	_ctl.command_erg(200, 60, 200.0)
	_run(2.0)
	assert_eq(_dev.writes.size(), n)
	assert_eq(_ctl.mode(), Wl.OFF)
	var lone: TrainerController = autofree(TrainerController.new())
	lone.resync(0.004, 0.51)
	assert_eq(lone.mode(), Wl.OFF, "no device: nothing changes")
