extends GutTest
## FtpTest (BRIEF 3.2, P1) on synthetic telemetry streams: the plan, the end conditions, the
## best 1-minute power, FTP = 0.75 x best, the cool-down, the save countdown and back, plus
## run_on() driving a LocalRider with test doubles. The accuracy test against MockTrainer's
## fatigue model lives in tests/core/integration/.

const Fakes := preload("res://tests/core/helpers/fakes.gd")
const Util := preload("res://tests/core/helpers/core_test_util.gd")
const DT := Wl.SIM_DT


class HoldLog:
	extends WlTrainerService

	var holds: Array[bool] = []

	func hold_rider(on: bool) -> void:
		holds.append(on)


var _phases: Array[int] = []


func before_each() -> void:
	_phases = []


func _new_test() -> FtpTest:
	var t := FtpTest.new()
	t.phase_requested.connect(func(i: int) -> void: _phases.append(i))
	return t


## Telemetry for the test's current phase: power = `frac` x the planned ERG target.
func _tel(t: FtpTest, frac: float = 1.0, fields: Dictionary = {}) -> Telemetry:
	var tel := Telemetry.new()
	tel.mode = Wl.ERG
	var ph := t.plan.phase(t.phase_index)
	var target := floorf(ph.planned_pct_at(t.phase_elapsed_s) * t.ftp_w / 100.0)
	tel.applied_target_w = int(target)
	tel.power_w = frac * target
	tel.cadence_rpm = 90.0
	tel.cadence_age_s = 0.5
	for k: String in fields.keys():
		tel.set(k, fields[k])
	return tel


func _ride(t: FtpTest, seconds: float, frac: float = 1.0, fields: Dictionary = {}) -> void:
	for _i in roundi(seconds / DT):
		t.step(DT, _tel(t, frac, fields))


# --- the plan -------------------------------------------------------------------------------


func test_plan_follows_the_protocol() -> void:
	var plan := FtpTest.build_plan(200.0, 1800.0)
	var ramp := plan.phase(0)
	assert_eq(ramp.kind, Wl.WARMUP)
	assert_eq(ramp.mode, Wl.ERG)
	assert_eq(ramp.target_pct, 50.0)
	assert_eq(ramp.ramp_to_pct, 65.0)
	assert_eq(ramp.duration_s, 300.0)
	assert_true(ramp.lap)
	var steps := FtpTest.step_count(200.0, 1800.0)
	assert_eq(steps, 73, "up to 1000 W: 65% .. 497% of 200 W")
	assert_eq(plan.size(), steps + 2)
	for n in range(1, steps + 1):
		var ph := plan.phase(n)
		assert_eq(ph.kind, Wl.WORK)
		assert_eq(ph.mode, Wl.ERG)
		assert_eq(ph.duration_s, 60.0)
		assert_eq(ph.target_pct, 65.0 + 6.0 * (n - 1))
		assert_false(ph.has_ramp())
		assert_true(ph.lap, "each step is its own lap")
	assert_eq(plan.phase(1).label, "Step 1")
	assert_eq(plan.phase(0).label, "FTP test ramp-in")
	var cd := plan.phase(plan.size() - 1)
	assert_eq(cd.kind, Wl.COOLDOWN)
	assert_eq(cd.target_pct, 50.0)
	assert_eq(cd.duration_s, 180.0)
	assert_true(plan.cooldown_appended)
	assert_eq(plan.cooldown_index(), plan.size() - 1)
	assert_true(ramp.peak_pct() <= PlanValidator.WARMUP_MAX_PCT, "the ramp-in is the warm-up")


func test_step_count_respects_the_ceiling() -> void:
	assert_eq(FtpTest.step_count(300.0, 600.0), 23, "600 W trainer: up to 197%")
	assert_eq(FtpTest.step_count(200.0, 160.0), 3)
	assert_eq(FtpTest.step_count(1500.0, 1800.0), 1)
	assert_eq(FtpTest.step_count(2000.0, 1800.0), 1, "always at least one step")
	assert_eq(FtpTest.step_count(5.0, 1800.0), FtpTest.MAX_STEPS)
	assert_eq(FtpTest.step_pct(1), 65.0)
	assert_eq(FtpTest.step_pct(2), 71.0)
	assert_eq(FtpTest.step_pct(10), 119.0)


func test_end_reason_keys_exist() -> void:
	for r: String in [FtpTest.END_POWER, FtpTest.END_CADENCE, FtpTest.END_COASTING, FtpTest.END_RESCUE,
			FtpTest.END_BACK, FtpTest.END_COMPLETE]:
		var key := FtpTest.end_reason_key(r)
		assert_ne(TranslationServer.translate(key), key, key)


# --- end conditions -----------------------------------------------------------------------------


func test_power_below_90_percent_for_10_s_ends_the_test() -> void:
	var t := _new_test()
	watch_signals(t)
	t.start(200.0)
	assert_eq(t.state, FtpTest.RAMP_IN)
	_ride(t, 300.0 + 5 * 60.0 + 30.0)
	assert_eq(t.state, FtpTest.STEPS)
	assert_eq(t.phase_index, 6)
	_ride(t, 9.9, 0.8)
	assert_eq(t.state, FtpTest.STEPS, "not yet")
	_ride(t, 0.1, 0.8)
	assert_eq(t.state, FtpTest.COOLDOWN)
	var r := t.result()
	assert_eq(r["end_reason"], FtpTest.END_POWER)
	assert_almost_eq(float(r["test_s"]), 640.0, 1e-6)
	assert_eq(r["steps_completed"], 5)
	assert_eq(r["last_step_pct"], 95.0)
	assert_almost_eq(float(r["best_1min_w"]), 184.0, 0.01, "30 s at 178 W + 30 s at 190 W")
	assert_eq(r["ftp_w"], 138.0, "0.75 x 184")
	assert_true(r["valid"])
	assert_eq(_phases, [0, 1, 2, 3, 4, 5, 6, t.plan.cooldown_index()] as Array[int])
	assert_signal_emitted(t, "ended")
	assert_signal_emitted_with_parameters(t, "countdown", [10])


func test_short_power_dips_do_not_end_the_test() -> void:
	var t := _new_test()
	t.start(200.0)
	_ride(t, 320.0)
	_ride(t, 9.5, 0.8)
	_ride(t, 1.0)
	_ride(t, 9.5, 0.8)
	_ride(t, 1.0)
	assert_eq(t.state, FtpTest.STEPS)


func test_power_rule_needs_an_erg_target() -> void:
	var t := _new_test()
	t.start(200.0)
	_ride(t, 320.0)
	_ride(t, 30.0, 0.5, {"mode": Wl.SIM})
	assert_eq(t.state, FtpTest.STEPS, "no ERG, no power rule")
	_ride(t, 30.0, 0.5, {"applied_target_w": 0})
	assert_eq(t.state, FtpTest.STEPS, "no target, no power rule")


func test_cadence_below_50_for_5_s_ends_the_test() -> void:
	var t := _new_test()
	t.start(200.0)
	_ride(t, 400.0)
	_ride(t, 4.9, 1.0, {"cadence_rpm": 45.0})
	assert_eq(t.state, FtpTest.STEPS)
	_ride(t, 0.1, 1.0, {"cadence_rpm": 45.0})
	assert_eq(t.state, FtpTest.COOLDOWN)
	assert_eq(t.result()["end_reason"], FtpTest.END_CADENCE)


func test_stale_cadence_does_not_count() -> void:
	var t := _new_test()
	t.start(200.0)
	_ride(t, 320.0)
	_ride(t, 30.0, 1.0, {"cadence_rpm": 0.0, "cadence_age_s": 10.0})
	assert_eq(t.state, FtpTest.STEPS, "a trainer without cadence can still finish the test")


func test_coasting_ends_the_test_at_once() -> void:
	var t := _new_test()
	t.start(200.0)
	_ride(t, 330.0)
	t.step(DT, _tel(t, 1.0, {"coasting": true}))
	assert_eq(t.state, FtpTest.COOLDOWN)
	assert_eq(t.result()["end_reason"], FtpTest.END_COASTING)
	assert_eq(_phases.back(), t.plan.cooldown_index(), "straight to the cool-down")


func test_rescue_ends_the_test_with_the_best_minute_so_far() -> void:
	var t := _new_test()
	t.start(200.0)
	_ride(t, 300.0 + 2 * 60.0 + 20.0)
	t.step(DT, _tel(t, 1.0, {"rescue": true}))
	var r := t.result()
	assert_eq(r["end_reason"], FtpTest.END_RESCUE)
	assert_almost_eq(float(r["best_1min_w"]), (142.0 * 40.0 + 154.0 * 20.0) / 60.0, 0.05)
	assert_eq(_phases.back(), t.plan.cooldown_index(), "rescue's 50% never ramps back into a step")
	assert_true(r["valid"])


func test_completing_every_step() -> void:
	var t := _new_test()
	t.start(200.0, 160.0)
	_ride(t, 300.0 + 3 * 60.0 - DT)
	assert_eq(t.state, FtpTest.STEPS)
	_ride(t, DT)
	assert_eq(t.state, FtpTest.COOLDOWN)
	var r := t.result()
	assert_eq(r["end_reason"], FtpTest.END_COMPLETE)
	assert_eq(r["steps_completed"], 3)
	assert_almost_eq(float(r["best_1min_w"]), 154.0, 0.01)


# --- result, countdown, back ---------------------------------------------------------------------


func test_countdown_saves_after_10_s_and_the_cooldown_finishes() -> void:
	var t := _new_test()
	var counts: Array[int] = []
	var saved: Array[float] = []
	var finished: Array = []
	t.countdown.connect(func(s: int) -> void: counts.append(s))
	t.saved.connect(func(w: float) -> void: saved.append(w))
	t.finished.connect(func(r: Dictionary) -> void: finished.append(r))
	t.start(200.0)
	_ride(t, 330.0)
	t.step(DT, _tel(t, 1.0, {"coasting": true}))
	assert_eq(t.countdown_left(), 10.0)
	_ride(t, 9.95)
	assert_eq(saved.size(), 0)
	_ride(t, DT)
	assert_eq(counts, [10, 9, 8, 7, 6, 5, 4, 3, 2, 1] as Array[int])
	assert_eq(saved.size(), 1)
	assert_eq(saved[0], t.result()["ftp_w"])
	assert_true(t.result()["saved"])
	assert_eq(t.countdown_left(), -1.0)
	assert_eq(t.state, FtpTest.COOLDOWN)
	_ride(t, 170.0 - DT)
	assert_eq(t.state, FtpTest.COOLDOWN)
	_ride(t, DT)
	assert_eq(t.state, FtpTest.DONE)
	assert_eq(finished.size(), 1)
	_ride(t, 10.0)
	assert_eq(finished.size(), 1)
	assert_false(t.is_running())


func test_back_during_the_countdown_keeps_the_old_ftp() -> void:
	var t := _new_test()
	watch_signals(t)
	t.start(200.0)
	_ride(t, 330.0)
	t.step(DT, _tel(t, 1.0, {"coasting": true}))
	_ride(t, 4.0)
	t.back()
	_ride(t, 20.0)
	assert_signal_not_emitted(t, "saved")
	var r := t.result()
	assert_false(r["saved"])
	assert_true(r["cancelled"])
	assert_eq(t.state, FtpTest.COOLDOWN, "the cool-down still runs")


func test_back_during_the_test_gives_no_result() -> void:
	var t := _new_test()
	watch_signals(t)
	t.start(200.0)
	_ride(t, 400.0)
	t.back()
	assert_eq(t.state, FtpTest.COOLDOWN)
	var r := t.result()
	assert_eq(r["end_reason"], FtpTest.END_BACK)
	assert_false(r["valid"])
	assert_eq(t.countdown_left(), -1.0)
	_ride(t, 15.0)
	assert_signal_not_emitted(t, "saved")


func test_ending_in_the_ramp_in_is_not_a_result() -> void:
	var t := _new_test()
	watch_signals(t)
	t.start(200.0)
	_ride(t, 100.0)
	t.step(DT, _tel(t, 1.0, {"coasting": true}))
	var r := t.result()
	assert_false(r["valid"])
	assert_eq(r["steps_completed"], 0)
	assert_signal_not_emitted(t, "countdown")
	assert_eq(t.state, FtpTest.COOLDOWN)


func test_idle_test_ignores_steps() -> void:
	var t := _new_test()
	t.step(DT, Telemetry.new())
	t.back()
	assert_eq(t.state, FtpTest.IDLE)
	assert_eq(t.result(), {})
	assert_eq(_phases.size(), 0)


# --- driving a rider ---------------------------------------------------------------------------------


func _rider(gov: Fakes.FakeGovernor) -> LocalRider:
	var m := MockTrainer.from_spec("const:w=200,rpm=90", 200.0)
	autofree(m)
	var r := LocalRider.new()
	add_child_autofree(r)
	var bus := WlEventBus.new()
	autofree(bus)
	r.setup(1, RiderProfile.new(), null, m, {"governor": gov, "gestures": Fakes.FakeGestures.new(), "bus": bus})
	return r


func test_run_on_drives_the_rider_and_saves_the_profile() -> void:
	var dir := Paths.make_temp_dir("wattlands_ftp_test")
	Paths.set_override(dir)
	var settings := WlSettings.new()
	autofree(settings)
	settings.bus = WlEventBus.new()
	autofree(settings.bus)
	settings.load_all()
	var service := HoldLog.new()
	autofree(service)
	var gov := Fakes.FakeGovernor.new()
	gov.st = {"mode": Wl.ERG, "applied_target_w": 0}
	var r := _rider(gov)
	var t := FtpTest.new()
	var plan := t.run_on(r, settings, service)
	assert_eq(service.holds, [true] as Array[bool], "the menu rider is held")
	assert_eq(gov.configured.get("profile"), "ramp_test")
	assert_eq(gov.plan, plan, "the rider's governor follows the test plan")
	assert_eq(r.plan(), plan)
	for _i in roundi(330.0 / DT):
		r.tick(DT)
	assert_eq(t.state, FtpTest.STEPS)
	assert_eq(r.telemetry().phase_index, 1)
	gov.st = {"mode": Wl.ERG, "applied_target_w": 0, "coasting": true}
	r.tick(DT)
	assert_eq(t.state, FtpTest.COOLDOWN)
	assert_eq(r.telemetry().phase_index, plan.cooldown_index())
	gov.st = {"mode": Wl.ERG, "applied_target_w": 0}
	for _i in roundi(11.0 / DT):
		r.tick(DT)
	assert_eq(settings.profile.ftp_w, 150.0, "0.75 x 200 W")
	assert_eq(settings.profile.cp_w, 150.0, "CP = FTP")
	assert_true(settings.profile.ftp_verified)
	var stored: Dictionary = Util.read_json(Paths.profile_path())
	assert_eq(stored.get("ftp_w"), 150.0)
	for _i in roundi(170.0 / DT):
		r.tick(DT)
	assert_eq(t.state, FtpTest.DONE)
	assert_eq(gov.configured.get("profile"), "normal", "back to the normal profile")
	assert_eq(service.holds, [true, false] as Array[bool])
	var starts: Array = []
	for c: Array in gov.called("start_phase"):
		starts.append(c[1])
	assert_eq(starts, [0, 1, plan.cooldown_index()])
	Paths.set_override("")
	Util.remove_tree(dir)


func test_stop_mid_test_leaves_the_rider_in_the_cooldown() -> void:
	var service := HoldLog.new()
	autofree(service)
	var gov := Fakes.FakeGovernor.new()
	var r := _rider(gov)
	var t := FtpTest.new()
	var plan := t.run_on(r, null, service)
	for _i in roundi(100.0 / DT):
		r.tick(DT)
	t.stop()
	assert_eq(t.state, FtpTest.DONE)
	assert_eq(t.end_reason, FtpTest.END_BACK)
	assert_eq(r.telemetry().phase_index, plan.cooldown_index())
	assert_eq(gov.configured.get("profile"), "normal")
	assert_eq(service.holds, [true, false] as Array[bool])
	var calls := gov.called("start_phase").size()
	for _i in 100:
		r.tick(DT)
	assert_eq(gov.called("start_phase").size(), calls, "no longer driven")
