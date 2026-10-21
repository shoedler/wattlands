extends GutTest
## W2r2: the app's rider between sessions, with the real trainer stack (WlTrainerService,
## LocalRider, SafetyGovernor and its TrainerController, MockTrainer; only the bus is
## injected). Menus ride free at SIM grade 0, wind 0, also right after a session's cool-down
## or an interval cut short by End ride, and the step there is ramped (BRIEF 4.5). The
## BRIEF 4.6.8 warm-up belongs to the trainer connection: begun in the menus it continues into
## a session and back, a 20-minute stop resets it, a new trainer object resets it, a
## reconnect doesn't, and skipping it in the profile still works.

const Fakes := preload("res://tests/core/helpers/fakes.gd")
const Util := preload("res://tests/core/helpers/core_test_util.gd")
const DT := Wl.SIM_DT

var _dir: String = ""
var _bus: WlEventBus = null
var _settings: WlSettings = null
var _router: Fakes.FakeInputRouter = null
var _manager: Fakes.FakeConnectionManager = null


func before_each() -> void:
	CmdLine.set_args(PackedStringArray(), true)
	_dir = Paths.make_temp_dir("wattlands_menu_rider_test")
	Paths.set_override(_dir)
	_bus = WlEventBus.new()
	autofree(_bus)
	_settings = WlSettings.new()
	_settings.bus = _bus
	autofree(_settings)
	_settings.load_all()
	_router = Fakes.FakeInputRouter.new()
	autofree(_router)
	_manager = null


func after_each() -> void:
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	Util.remove_tree(_dir)
	await wait_process_frames(1)


func _args(list: Array) -> void:
	var a := PackedStringArray()
	for s: String in list:
		a.append(s)
	CmdLine.set_args(a, true)


## A service whose rider runs the real governor, gestures and cadence estimator.
func _make() -> WlTrainerService:
	var svc := WlTrainerService.new()
	svc.settings = _settings
	svc.bus = _bus
	svc.input_router = _router
	svc.connection_factory = func() -> FtmsConnectionManager:
		_manager = Fakes.FakeConnectionManager.new()
		return _manager
	svc.rider_options_factory = func() -> Dictionary: return {"bus": _bus}
	add_child_autofree(svc)
	return svc


## Menu time: the service ticks its rider.
func _menus(svc: WlTrainerService, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		svc.step()


## Session time: the GameHost ticks the rider (the service doesn't).
func _ride(r: LocalRider, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		r.tick(DT)


## What the app shell does at a session start: the menu rider becomes the session rider on the
## same device (SessionLauncher.build_config), the GameHost takes over ticking and starts phase 0.
func _session(svc: WlTrainerService, phases: Array, rec: RideRecorderApi = null) -> LocalRider:
	var r := svc.local_rider()
	svc.set_external_tick(true)
	var opts := {
		"multiplayer": false,
		"scaling_mode": Wl.FAIR_FTP,
		"bus": _bus,
		"skip_warmup": _settings.profile.skip_warmup
	}
	if rec != null:
		opts["recorder"] = rec
	r.setup(1, _settings.profile, _settings.profile.to_slot(1, Wl.FAIR_FTP), svc.device(), opts)
	var plan := EffortPlan.of(phases)
	plan.add(PlanPhase.erg(Wl.COOLDOWN, 50.0, 180.0, "Cool-down").with_lap())
	plan.cooldown_appended = true
	r.set_plan(plan)
	r.start_phase(0)
	return r


## Every control response the mock sends (one per write, on the tick after it), with the state
## the write left: [op, commanded_mode, commanded_target_w, commanded_grade_pct, wind, t].
func _watch_writes(m: MockTrainer, out: Array) -> void:
	m.control_response.connect(
		func(op: int, _result: int) -> void:
			out.append(
				[
					op,
					m.commanded_mode,
					m.commanded_target_w,
					m.commanded_grade_pct,
					m.commanded_wind_mps,
					m.platform_time_s()
				]
			)
	)


func _assert_sim_flat(svc: WlTrainerService, why: String) -> void:
	var m := svc.device() as MockTrainer
	assert_eq(m.commanded_mode, Wl.SIM, "the trainer is in SIM (%s)" % why)
	assert_almost_eq(m.commanded_grade_pct, 0.0, 1e-12, "grade 0 (%s)" % why)
	assert_almost_eq(m.commanded_wind_mps, 0.0, 1e-12, "wind 0 (%s)" % why)
	var r := svc.local_rider()
	var st := r.governor.status()
	assert_eq(st["mode"], Wl.SIM)
	assert_eq(st["desired_mode"], Wl.OFF, "nothing planned (%s)" % why)
	assert_eq(int(st["applied_target_w"]), 0)
	var tel := r.telemetry()
	assert_eq(tel.mode, Wl.SIM)
	assert_almost_eq(tel.applied_grade_pct, 0.0, 1e-12)


func _warm_left(r: LocalRider) -> float:
	return float(r.governor.status()["warmup_remaining_s"])


# --- menus ride SIM flat -------------------------------------------------------------------------


func test_menus_ride_sim_flat_from_the_start() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	_menus(svc, 3.0)
	_assert_sim_flat(svc, "menus at launch")
	var m := svc.device() as MockTrainer
	var n := m.command_count
	assert_eq(n, 1, "one write")
	_menus(svc, 20.0)
	assert_eq(m.command_count, n, "nothing more while nothing changes")


func test_end_ride_mid_interval_hands_back_to_sim_flat_through_a_ramp() -> void:
	# A rider at 80% of the ERG target, so the 4.5 step-down has something to step down to.
	_args(["--mock-trainer=erg:compliance=0.8"])
	_settings.profile.skip_warmup = true
	var svc := _make()
	svc.start()
	_menus(svc, 5.0)
	var r := _session(
		svc, [PlanPhase.erg(Wl.WARMUP, 50.0, 60.0), PlanPhase.erg(Wl.WORK, 80.0, 600.0)]
	)
	_ride(r, 60.0)
	r.start_phase(1)
	_ride(r, 30.0)
	var m := svc.device() as MockTrainer
	assert_eq(m.commanded_mode, Wl.ERG)
	assert_eq(m.commanded_target_w, 136, "80% x 0.85 (unverified FTP) of 200 W")
	var writes: Array = []
	_watch_writes(m, writes)
	# End ride mid-interval: the session ends and hands ticking back.
	svc.set_external_tick(false)
	assert_null(r.plan(), "the menu rider has no plan")
	assert_eq(r.telemetry().phase_index, -1)
	_menus(svc, 3.0)
	_assert_sim_flat(svc, "after End ride")
	assert_eq(writes.size(), 2, "the ERG step-down, then SIM flat")
	assert_eq(writes[0][1], Wl.ERG, "step 1 stays in ERG")
	assert_between(
		int(writes[0][2]), 100, 115, "at min(applied target, 3 s power): the rider's ~109 W"
	)
	assert_eq(writes[1][1], Wl.SIM)
	assert_gte(float(writes[1][5]) - float(writes[0][5]), 0.5 - 1e-6, "one write slot apart")
	var n := m.command_count
	_menus(svc, 10.0)
	assert_eq(m.command_count, n, "SIM flat holds")


func test_after_the_cooldown_menus_ride_sim_flat() -> void:
	_args(["--mock-trainer=erg"])
	_settings.profile.skip_warmup = true
	var svc := _make()
	svc.start()
	var r := _session(svc, [PlanPhase.erg(Wl.WORK, 60.0, 60.0)])
	_ride(r, 60.0)
	r.start_phase(1)
	_ride(r, 30.0)
	var m := svc.device() as MockTrainer
	assert_eq(m.commanded_mode, Wl.ERG)
	assert_eq(m.commanded_target_w, 85, "the cool-down's 50% x 0.85")
	svc.set_external_tick(false)
	_menus(svc, 2.0)
	_assert_sim_flat(svc, "after the cool-down")


func test_while_the_ride_still_records_the_plan_is_dropped_at_once() -> void:
	_args(["--mock-trainer=erg"])
	_settings.profile.skip_warmup = true
	var svc := _make()
	svc.start()
	var rec := Fakes.FakeRecorder.new()
	var r := _session(svc, [PlanPhase.erg(Wl.WORK, 90.0, 600.0)], rec)
	_ride(r, 40.0)
	var m := svc.device() as MockTrainer
	assert_eq(m.commanded_mode, Wl.ERG)
	svc.set_external_tick(false)
	assert_true(svc.is_menu_reset_pending(), "the ride still has to be saved")
	assert_null(r.plan(), "the session plan is dropped anyway")
	assert_eq(r.recorder, rec, "the ride keeps recording until it's saved")
	_menus(svc, 2.0)
	_assert_sim_flat(svc, "waiting for the ride to be saved")
	assert_true(rec.records.size() > 0)
	r.finish_ride()
	_menus(svc, 1.0)
	assert_false(svc.is_menu_reset_pending())
	_assert_sim_flat(svc, "after the menu reset")


# --- warm-up belongs to the trainer connection --------------------------------------------------


func test_warmup_begun_in_the_menus_continues_into_a_session_and_back() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	var r := svc.local_rider()
	_menus(svc, 100.0)
	var left := _warm_left(r)
	assert_between(left, 200.0, 201.5, "counting since the mock's first stroke (~1 s)")
	r = _session(svc, [PlanPhase.erg(Wl.WARMUP, 50.0, 60.0), PlanPhase.erg(Wl.WORK, 80.0, 600.0)])
	assert_almost_eq(_warm_left(r), left, 1e-9, "the session's setup keeps it")
	assert_true(r.governor.is_warmup_active())
	_ride(r, 60.0)
	r.start_phase(1)
	_ride(r, 20.0)
	assert_almost_eq(_warm_left(r), left - 80.0, 1e-6, "it kept counting in the session")
	assert_eq(int(r.governor.status()["applied_target_w"]), 130, "the 65% cap holds")
	svc.set_external_tick(false)
	assert_almost_eq(_warm_left(r), left - 80.0, 1e-6, "the menu reset keeps it")
	_menus(svc, left - 80.0 + 1.0)
	assert_false(
		r.governor.is_warmup_active(), "done 300 s after the first stroke, wherever it rode"
	)
	r = _session(svc, [PlanPhase.erg(Wl.WARMUP, 50.0, 60.0), PlanPhase.erg(Wl.WORK, 80.0, 600.0)])
	assert_false(r.governor.is_warmup_active(), "a second session gets no fresh warm-up")
	r.start_phase(1)
	_ride(r, 10.0)
	assert_eq(int(r.governor.status()["applied_target_w"]), 136, "no 65% cap")
	assert_does_not_have(r.governor.status()["clamped_by"], Wl.CLAMP_WARMUP)


func test_twenty_minutes_without_pedaling_reset_it() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	var r := svc.local_rider()
	var m := svc.device() as MockTrainer
	_menus(svc, 310.0)
	assert_false(r.governor.is_warmup_active())
	m.nudge_power(-10000.0)
	_menus(svc, 5.0)
	assert_eq(r.telemetry().power_w, 0.0, "the rider stopped")
	var last := float(r.governor.warmup_state()["last_pedal_t"])
	_menus(svc, 600.0)
	r = _session(svc, [PlanPhase.erg(Wl.WARMUP, 50.0, 60.0)])
	svc.set_external_tick(false)
	assert_false(r.governor.is_warmup_active(), "a 10-minute stop keeps it")
	assert_almost_eq(float(r.governor.warmup_state()["last_pedal_t"]), last, 1e-9)
	while float(r.governor.warmup_state()["t"]) < last + 1200.0 - DT - 1e-6:
		svc.step()
	assert_false(r.governor.is_warmup_active(), "not before 20 minutes")
	svc.step()
	assert_true(r.governor.is_warmup_active(), "reset after 20 minutes without pedaling")
	assert_almost_eq(_warm_left(r), 300.0, 1e-9, "pending until the next stroke")


func test_a_new_trainer_object_resets_it() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	_menus(svc, 305.0)
	assert_false(svc.local_rider().governor.is_warmup_active())
	svc.use_mock("erg")
	var r := svc.local_rider()
	assert_true(r.governor.is_warmup_active(), "another trainer: a new connection")
	assert_almost_eq(_warm_left(r), 300.0, 1e-9)
	_menus(svc, 10.0)
	assert_between(_warm_left(r), 290.0, 291.5, "counting from the new trainer's first stroke")


func test_a_reconnect_keeps_it_and_a_new_trainer_resets_it() -> void:
	var svc := _make()
	svc.start()
	var d1 := Fakes.FakeDevice.new()
	autofree(d1)
	_manager.make_ready(d1)
	var r := svc.local_rider()
	for i in 100:
		d1.emit_sample(150.0, 85.0, 30.0)
		_menus(svc, 1.0)
	var left := _warm_left(r)
	assert_almost_eq(left, 200.05, 1e-6, "first stroke in the first tick (0.05 s), 100 s ago")
	_manager.make_reconnected(d1)
	assert_almost_eq(_warm_left(r), left, 1e-9, "the same trainer reconnected")
	r = _session(svc, [PlanPhase.erg(Wl.WARMUP, 50.0, 60.0)])
	var d1b := Fakes.FakeDevice.new()
	autofree(d1b)
	_manager.make_ready(d1b)
	assert_push_warning("during a session")
	assert_eq(r.device, d1b)
	assert_almost_eq(
		_warm_left(r), left, 1e-9, "a reconnect with a new object of the same trainer (rebind)"
	)
	svc.set_external_tick(false)
	assert_almost_eq(
		_warm_left(svc.local_rider()), left, 1e-9, "the menu reset on that object keeps it"
	)
	var d2 := Fakes.FakeDevice.new()
	autofree(d2)
	_manager.make_ready(d2)
	r = svc.local_rider()
	assert_eq(r.device, d2)
	assert_true(r.governor.is_warmup_active())
	assert_almost_eq(_warm_left(r), 300.0, 1e-9, "another trainer in the menus: a new connection")


func test_skip_warmup_in_the_profile_still_skips_it() -> void:
	_args(["--mock-trainer=erg"])
	_settings.profile.skip_warmup = true
	var svc := _make()
	svc.start()
	_menus(svc, 20.0)
	assert_false(svc.local_rider().governor.is_warmup_active())
	var r := _session(svc, [PlanPhase.erg(Wl.WORK, 80.0, 600.0)])
	assert_false(r.governor.is_warmup_active())
	_ride(r, 10.0)
	assert_eq(int(r.governor.status()["applied_target_w"]), 136)
	_settings.profile.skip_warmup = false
	svc.set_external_tick(false)
	_menus(svc, 0.1)
	assert_true(
		svc.local_rider().governor.is_warmup_active(),
		"turning the setting off brings the remaining warm-up back"
	)
	assert_between(_warm_left(svc.local_rider()), 268.0, 271.5, "it kept counting while skipped")
