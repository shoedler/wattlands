extends GutTest
## TrainerController haptic pull (BRIEF 4.6.6, v0.3.0): command_erg's pull_w rides on top of
## the slewed target, on and off at once; no pull during a SIM -> ERG entry or outside ERG;
## the write slot is kept free so the drop-back is written by the pull's end.

const ScriptedDevice := preload("res://tests/governor/scripted_device.gd")
const DT := Wl.SIM_DT

var _dev: ScriptedDevice = null
var _ctl: TrainerController = null


func before_each() -> void:
	_dev = autofree(ScriptedDevice.new())
	_ctl = autofree(TrainerController.new())
	_ctl.setup(_dev)


## `seconds` of ticks, each with command_erg(w, 60, 1000, pull, pull_left) where pull_left
## counts down from `pull_s` (no pull once it reaches 0).
func _run_erg(w: int, seconds: float, pull_w: int = 0, pull_s: float = 0.0) -> void:
	var left := pull_s
	for i in roundi(seconds / DT):
		_ctl.command_erg(w, 60, 1000.0, pull_w if left > 1e-9 else 0, left)
		_dev.tick(DT)
		_ctl.tick(DT)
		left -= DT


func test_pull_is_instant_on_top_of_the_target() -> void:
	_run_erg(200, 5.0)
	assert_eq(_ctl.applied_target_w(), 200)
	_run_erg(200, 0.05, 60, 3.0)
	assert_eq(_ctl.applied_target_w(), 260, "no slew for the pull")
	assert_eq(_ctl.applied_base_w(), 200)
	assert_eq(_ctl.applied_pull_w(), 60)
	_run_erg(200, 0.05)
	assert_eq(_ctl.applied_target_w(), 200, "off at once")


func test_no_pull_during_an_entry_or_in_sim() -> void:
	_ctl.command_sim(0.0, 2.0, 0.004, 0.51, 60, 0.0)
	_dev.tick(DT)
	_ctl.tick(DT)
	_ctl.command_erg(200, 60, 100.0, 50, 3.0)
	assert_eq(_ctl.applied_pull_w(), 0, "SIM")
	for i in 30:
		_ctl.command_erg(200, 60, 100.0, 50, 3.0)
		_dev.tick(DT)
		_ctl.tick(DT)
	assert_eq(_ctl.mode(), Wl.ERG)
	assert_true(_ctl.entry_active(), "slewing up from the entry at 100 W")
	assert_eq(_ctl.applied_pull_w(), 0, "no pull while the entry slews up")
	assert_lte(_dev.target_w, 200, "the entry never goes above the target")


func test_drop_back_is_written_by_the_end() -> void:
	# A target that keeps changing writes every 0.5 s; the slot before the end stays free.
	_run_erg(150, 5.0)
	var held := 0
	var left := 2.0
	for i in 80:
		var w := 150 + i
		_ctl.command_erg(w, 60, 1000.0, 100 if left > 1e-9 else 0, left)
		_dev.tick(DT)
		_ctl.tick(DT)
		left -= DT
		if _dev.target_w > w:
			held += 1
	assert_gt(held * DT, 1.4, "the trainer got the pull")
	assert_lte(held * DT, 2.0 + 1e-6, "and dropped it by its end")
	assert_lte(_dev.max_writes_in_window(1.0), 2)
