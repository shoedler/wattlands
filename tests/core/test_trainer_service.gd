extends GutTest
## WlTrainerService (BRIEF 3.5, 4.4): the mock path, the FTMS path through a fake
## connection manager (no Bluetooth), the menu-time rider and its ticking, trainer switches,
## profile changes, panic, status mirroring and shutdown_all.

const Fakes := preload("res://tests/core/helpers/fakes.gd")
const Util := preload("res://tests/core/helpers/core_test_util.gd")

var _dir: String = ""
var _bus: WlEventBus = null
var _settings: WlSettings = null
var _router: Fakes.FakeInputRouter = null
var _manager: Fakes.FakeConnectionManager = null


func before_each() -> void:
	CmdLine.set_args(PackedStringArray(), true)
	_dir = Paths.make_temp_dir("wattlands_trainer_service_test")
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


func _args(list: Array) -> void:
	var a := PackedStringArray()
	for s: String in list:
		a.append(s)
	CmdLine.set_args(a, true)


func _make() -> WlTrainerService:
	var svc := WlTrainerService.new()
	svc.settings = _settings
	svc.bus = _bus
	svc.input_router = _router
	svc.connection_factory = func() -> FtmsConnectionManager:
		_manager = Fakes.FakeConnectionManager.new()
		return _manager
	svc.rider_options_factory = func() -> Dictionary:
		return {"governor": Fakes.FakeGovernor.new(), "gestures": Fakes.FakeGestures.new(), "bus": _bus}
	add_child_autofree(svc)
	return svc


func _gov(svc: WlTrainerService) -> Fakes.FakeGovernor:
	return svc.local_rider().governor as Fakes.FakeGovernor


# --- mock path -----------------------------------------------------------------------------


func test_mock_trainer_flag_builds_a_mock_and_a_rider() -> void:
	_args(["--mock-trainer=const:w=150,rpm=85", "--seed=5"])
	var svc := _make()
	watch_signals(svc)
	watch_signals(_bus)
	svc.start()
	assert_eq(svc.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_true(svc.is_mock())
	assert_null(svc.connection(), "no connection manager when mocked")
	var m := svc.device() as MockTrainer
	assert_not_null(m)
	assert_eq(m.spec, "const:w=150,rpm=85")
	assert_eq(m.get_parent(), svc, "the service owns the mock")
	assert_eq(m.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(svc.status(), TrainerDevice.STATUS_READY)
	assert_string_contains(svc.status_detail(), "const:w=150,rpm=85")
	assert_signal_emitted(svc, "device_changed")
	assert_signal_emitted(svc, "status_changed")
	assert_signal_emitted(_bus, "trainer_status_changed")
	var r := svc.local_rider()
	assert_not_null(r)
	assert_eq(r.device, m)
	assert_eq(r.peer_id, 1)
	assert_eq(r.profile, _settings.profile)
	assert_false(r.is_multiplayer)
	assert_null(r.recorder, "menu riding is not recorded")
	assert_eq(_router.attached, [r], "pedal gestures drive menus")
	assert_eq(svc.local_rider(), r, "one rider")


func test_mock_rides_the_profile_ftp() -> void:
	_settings.profile.ftp_w = 250.0
	_settings.profile.cp_w = 250.0
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	for _i in 300:
		svc.step()
	var tel := svc.local_rider().telemetry()
	assert_almost_eq(tel.power_w, 225.0, 15.0, "erg outside ERG rides 90% of the profile FTP")
	assert_almost_eq(svc.local_rider().platform_time(), 15.0, 1e-9)


func test_bare_mock_flag_means_erg() -> void:
	_args(["--mock-trainer"])
	var svc := _make()
	svc.start()
	assert_eq((svc.device() as MockTrainer).spec, "erg")


func test_invalid_mock_spec_falls_back_to_erg() -> void:
	_args(["--mock-trainer=warp:speed=9"])
	var svc := _make()
	svc.start()
	assert_push_error("invalid profile spec")
	assert_eq((svc.device() as MockTrainer).spec, "erg")


func test_start_is_idempotent() -> void:
	var svc := _make()
	svc.start()
	var first := _manager
	svc.start()
	assert_eq(_manager, first)
	assert_eq(first.started, [true])


# --- FTMS path -------------------------------------------------------------------------------


func test_ftms_path_auto_connects_through_the_manager() -> void:
	var svc := _make()
	watch_signals(_bus)
	svc.start()
	assert_not_null(_manager)
	assert_eq(svc.connection(), _manager)
	assert_eq(_manager.started, [true], "auto_connect_last = true")
	assert_eq(_manager.get_parent(), svc)
	assert_eq(_manager.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(svc.is_mock())
	assert_null(svc.device())
	assert_null(svc.local_rider(), "no rider without a trainer")
	_manager.status_changed.emit(TrainerDevice.STATUS_SCANNING, "looking for a trainer")
	assert_eq(svc.status(), TrainerDevice.STATUS_SCANNING)
	assert_signal_emitted_with_parameters(_bus, "trainer_status_changed", [TrainerDevice.STATUS_SCANNING, "looking for a trainer"])
	var d := Fakes.FakeDevice.new()
	autofree(d)
	_manager.make_ready(d)
	assert_eq(svc.device(), d)
	assert_ne(d.get_parent(), svc, "the manager owns a real trainer")
	var r := svc.local_rider()
	assert_not_null(r)
	assert_eq(r.device, d)
	assert_eq(_router.attached, [r])
	assert_eq(svc.status(), TrainerDevice.STATUS_READY)
	assert_eq(_settings.get_value("last_device"), _manager.last, "the last trainer is remembered")


func test_reconnect_keeps_the_rider() -> void:
	var svc := _make()
	svc.start()
	var d := Fakes.FakeDevice.new()
	autofree(d)
	_manager.make_ready(d)
	var r := svc.local_rider()
	_manager.status_changed.emit(TrainerDevice.STATUS_DISCONNECTED, "lost")
	assert_eq(svc.status(), TrainerDevice.STATUS_DISCONNECTED)
	_manager.make_ready(d)
	assert_eq(svc.local_rider(), r)
	assert_eq(_gov(svc).shutdown_count, 0)
	assert_eq(svc.status(), TrainerDevice.STATUS_READY)


func test_another_trainer_replaces_the_rider_safely() -> void:
	var svc := _make()
	svc.start()
	var d1 := Fakes.FakeDevice.new()
	var d2 := Fakes.FakeDevice.new()
	autofree(d1)
	autofree(d2)
	_manager.make_ready(d1)
	var g1 := _gov(svc)
	_manager.make_ready(d2)
	assert_eq(g1.shutdown_count, 1, "the old trainer goes SIM flat, then Stop")
	assert_eq(svc.local_rider().device, d2)
	assert_eq(_router.detaches, 1)


func test_device_status_and_control_lost_are_mirrored() -> void:
	var svc := _make()
	svc.start()
	var d := Fakes.FakeDevice.new()
	autofree(d)
	_manager.make_ready(d)
	watch_signals(svc)
	watch_signals(_bus)
	d.set_dev_status(TrainerDevice.STATUS_CONTROL_LOST, "another app may hold control")
	assert_eq(svc.status(), TrainerDevice.STATUS_CONTROL_LOST)
	assert_signal_emitted_with_parameters(svc, "status_changed", [TrainerDevice.STATUS_CONTROL_LOST, "another app may hold control"])
	assert_signal_emitted_with_parameters(_bus, "trainer_control_lost", ["another app may hold control"])
	d.set_dev_status(TrainerDevice.STATUS_CONTROL_LOST, "another app may hold control")
	assert_signal_emit_count(svc, "status_changed", 1, "unchanged status: no repeat")


func test_use_mock_replaces_the_ftms_trainer() -> void:
	var svc := _make()
	svc.start()
	var d := Fakes.FakeDevice.new()
	autofree(d)
	_manager.make_ready(d)
	var g := _gov(svc)
	var manager := _manager
	svc.use_mock("erg:compliance=0.9")
	assert_eq(g.shutdown_count, 1, "the real trainer is made safe first")
	assert_eq(manager.disconnects, 1)
	assert_true(manager.is_queued_for_deletion())
	assert_null(svc.connection())
	assert_true(svc.is_mock())
	assert_eq((svc.device() as MockTrainer).spec, "erg:compliance=0.9")
	assert_eq(svc.local_rider().device, svc.device())


func test_use_mock_is_refused_during_a_session() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	var m := svc.device()
	svc.set_external_tick(true)
	svc.use_mock("zero")
	assert_push_warning("during a session")
	assert_eq(svc.device(), m)


# --- ticking ----------------------------------------------------------------------------------


func test_step_ticks_the_rider_and_its_device() -> void:
	_args(["--mock-trainer=const:w=180,rpm=88"])
	var svc := _make()
	svc.start()
	for _i in 40:
		svc.step()
	var r := svc.local_rider()
	assert_almost_eq(r.platform_time(), 2.0, 1e-9)
	assert_almost_eq((svc.device() as MockTrainer).platform_time_s(), 2.0, 1e-9)
	assert_eq(r.telemetry().power_w, 180.0)
	assert_eq(_gov(svc).ticks.size(), 40)


func test_process_runs_menu_time_at_sim_speed_until_a_session_takes_over() -> void:
	_args(["--mock-trainer=erg", "--sim-speed=4"])
	var svc := _make()
	svc.start()
	var r := svc.local_rider()
	svc._process(Wl.SIM_DT)
	assert_almost_eq(r.platform_time(), 4 * Wl.SIM_DT, 1e-9, "4 steps per 0.05 s of wall time")
	svc.set_external_tick(true)
	assert_true(svc.is_external_tick())
	svc._process(1.0)
	assert_almost_eq(r.platform_time(), 4 * Wl.SIM_DT, 1e-9, "the GameHost ticks during a session")
	svc.set_external_tick(false)
	svc._process(Wl.SIM_DT)
	assert_almost_eq(r.platform_time(), 8 * Wl.SIM_DT, 1e-9, "no backlog from the session")


# --- profile, panic, shutdown -------------------------------------------------------------------


func test_profile_change_rebuilds_the_mock_and_the_rider() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	var m1 := svc.device()
	var r := svc.local_rider()
	_settings.profile.display_name = "Renamed"
	_settings.save_profile()
	assert_eq(svc.device(), m1, "a name change keeps the mock")
	assert_eq(svc.local_rider(), r)
	assert_eq(r.slot.name, "Renamed", "the rider was set up again")
	_settings.profile.ftp_w = 300.0
	_settings.save_profile()
	assert_ne(svc.device(), m1, "new rider parameters rebuild the mock")
	assert_eq(svc.local_rider().ftp_w(), 300.0)
	assert_almost_eq(svc.local_rider().slot.p_eff_per_w, 250.0 / 300.0, 1e-9)


func test_scaling_change_resets_the_rider() -> void:
	_args(["--mock-trainer=erg"])
	_settings.profile.weight_kg = 60.0
	var svc := _make()
	svc.start()
	_settings.set_value("scaling_mode", Wl.WKG)
	var r := svc.local_rider()
	assert_eq(r.scaling_mode, Wl.WKG)
	assert_almost_eq(r.slot.p_eff_per_w, 75.0 / 60.0, 1e-9)


func test_profile_changes_wait_while_a_session_runs() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	var m := svc.device()
	svc.set_external_tick(true)
	_settings.profile.ftp_w = 320.0
	_settings.save_profile()
	assert_eq(svc.device(), m)
	assert_eq(svc.local_rider().ftp_w(), 200.0)


func test_panic_makes_the_rider_safe() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	_bus.panic_requested.emit()
	assert_eq(_gov(svc).called("emergency_safe").size(), 1)


func test_shutdown_all_covers_every_live_rider() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	var extra: Array[LocalRider] = []
	for i in 2:
		var m := MockTrainer.from_spec("erg", 200.0)
		autofree(m)
		var r := LocalRider.new()
		add_child_autofree(r)
		r.setup(-(i + 1), RiderProfile.new(), null, m, {"governor": Fakes.FakeGovernor.new(), "bus": _bus})
		extra.append(r)
	var n := svc.shutdown_all()
	assert_gte(n, 3)
	assert_true(svc.local_rider().is_shut_down())
	for r in extra:
		assert_true(r.is_shut_down())
		assert_eq((r.governor as Fakes.FakeGovernor).shutdown_count, 1)
	assert_eq(svc.shutdown_all(), 0, "nothing left to shut down")


func test_leaving_the_tree_shuts_the_own_rider_down() -> void:
	_args(["--mock-trainer=erg"])
	var svc := _make()
	svc.start()
	var g := _gov(svc)
	remove_child(svc)
	assert_eq(g.shutdown_count, 1)
	add_child(svc)
