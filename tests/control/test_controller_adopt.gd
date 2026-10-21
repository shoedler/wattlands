extends GutTest
## TrainerController.adopt() (W2r2, SafetyGovernor.adopt_connection): a new controller on the
## same device takes over what the old one last wrote and its write-slot timing, so the next
## command is ramped from the trainer's real state (BRIEF 4.5) and the 2 writes per second
## hold across the hand-over (4.5 coalescing).

const ScriptedDevice := preload("res://tests/governor/scripted_device.gd")
const DT := Wl.SIM_DT

var _dev: ScriptedDevice = null
var _old: TrainerController = null


func before_each() -> void:
	_dev = autofree(ScriptedDevice.new())
	_old = autofree(TrainerController.new())
	_old.setup(_dev)


func _step(ctl: TrainerController, n: int = 1) -> void:
	for i in n:
		_dev.tick(DT)
		ctl.tick(DT)


func _run(ctl: TrainerController, seconds: float) -> void:
	_step(ctl, roundi(seconds / DT))


func _new() -> TrainerController:
	var c: TrainerController = autofree(TrainerController.new())
	c.setup(_dev)
	return c


func test_erg_state_carries_and_sim_flat_is_ramped() -> void:
	_old.command_erg(180, 60, 180.0)
	_run(_old, 10.0)
	assert_eq(_dev.target_w, 180)
	var c := _new()
	var n := _dev.writes.size()
	c.adopt(_old)
	assert_eq(_dev.writes.size(), n, "adopting writes nothing")
	assert_eq(c.mode(), Wl.ERG)
	assert_eq(c.written_target_w(), 180)
	assert_eq(c.applied_target_w(), 180)
	c.command_sim(0.0, 0.0, 0.004, 0.51, 60, 120.0)
	_run(c, 2.0)
	var after := _dev.writes.slice(n)
	assert_eq(after.size(), 2)
	assert_eq(after[0]["op"], "erg", "ERG -> SIM step 1: down to min(applied, 3 s power)")
	assert_eq(int(after[0]["w"]), 120)
	assert_eq(after[1]["op"], "sim")
	assert_almost_eq(float(after[1]["grade_pct"]), 0.0, 1e-12)


func test_sim_state_carries_and_unchanged_commands_write_nothing() -> void:
	_old.command_sim(0.0, 4.0, 0.004, 0.51, 60, 0.0)
	_run(_old, 2.0)
	var c := _new()
	c.adopt(_old)
	assert_eq(c.mode(), Wl.SIM)
	assert_almost_eq(float(c.written_sim()["grade_pct"]), 4.0, 1e-9)
	var n := _dev.writes.size()
	c.command_sim(0.0, 4.0, 0.004, 0.51, 60, 0.0)
	_run(c, 2.0)
	assert_eq(_dev.writes.size(), n, "the trainer already holds it")
	c.command_erg(150, 60, 200.0)
	_run(c, 2.0)
	var after := _dev.writes.slice(n)
	assert_eq(after[0]["op"], "sim", "SIM -> ERG step 1: grade 0 first")
	assert_almost_eq(float(after[0]["grade_pct"]), 0.0, 1e-12)
	assert_eq(after[1]["op"], "erg")
	assert_eq(int(after[1]["w"]), 150)


func test_the_write_slot_carries() -> void:
	_old.command_erg(100, 60, 100.0)
	_step(_old)
	var t_write := _dev.t
	assert_eq(_dev.writes.size(), 1)
	_step(_old, 3)
	var c := _new()
	c.adopt(_old)
	c.command_sim(0.0, 0.0, 0.004, 0.51, 60, 100.0)
	_run(c, 1.0)
	var later := _dev.writes.slice(1)
	assert_eq(later.size(), 1)
	assert_almost_eq(
		float(later[0]["t"]) - t_write, 0.5, DT * 0.5, "the first write waits for the old slot"
	)


func test_a_panic_hold_or_a_stop_carries_safely() -> void:
	_old.command_erg(200, 60, 200.0)
	_run(_old, 10.0)
	_old.emergency_safe(0.004, 0.51)
	var c := _new()
	c.adopt(_old)
	assert_eq(c.mode(), Wl.SIM, "panic wrote SIM flat")
	assert_false(c.is_safe(), "the hold itself belongs to the old governor")
	c.command_erg(200, 60, 200.0)
	_run(c, 1.0)
	assert_eq(
		int(_dev.writes_of("erg", _dev.t - 1.0)[0]["w"]),
		60,
		"the next ERG entry is the floor, as after a resume"
	)
	var d := _new()
	_old.shutdown(0.004, 0.51)
	d.adopt(_old)
	assert_eq(d.mode(), Wl.OFF, "SIM flat then Stop went out")
	assert_false(d.is_stopped())


func test_adopt_ignores_null_itself_and_another_device() -> void:
	_old.command_erg(150, 60, 150.0)
	_run(_old, 3.0)
	_old.adopt(null)
	_old.adopt(_old)
	assert_eq(_old.written_target_w(), 150)
	var other: ScriptedDevice = autofree(ScriptedDevice.new())
	var c: TrainerController = autofree(TrainerController.new())
	c.setup(other)
	c.adopt(_old)
	assert_eq(c.mode(), Wl.OFF, "another trainer: nothing is assumed")
