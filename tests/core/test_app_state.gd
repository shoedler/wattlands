extends GutTest
## WlApp (BRIEF 3.5, 4.6.9, 6): the state machine, scripted peers, the boot order, quit
## with governor shutdown, the exit paths and --run-seconds. A private App with test
## doubles; _quit_tree is overridden so nothing ends the test process.

const Fakes := preload("res://tests/core/helpers/fakes.gd")
const Util := preload("res://tests/core/helpers/core_test_util.gd")


class QuitRecordingApp:
	extends WlApp

	var quit_codes: Array[int] = []

	func _quit_tree(code: int) -> void:
		quit_codes.append(code)


class LoggingSettings:
	extends WlSettings

	var log: Array = []

	func load_all() -> void:
		log.append("load_all")
		super.load_all()


class LoggingTrainerService:
	extends WlTrainerService

	var log: Array = []
	var fake_device: TrainerDevice = null
	var mock: bool = true

	func start() -> void:
		log.append("start")

	func device() -> TrainerDevice:
		return fake_device

	func is_mock() -> bool:
		return mock

	func shutdown_all() -> int:
		log.append("shutdown_all")
		return super.shutdown_all()


class LoggingRides:
	extends WlRides

	var log: Array = []

	func process_queue() -> void:
		log.append("process_queue")


var _dir: String = ""
var _bus: WlEventBus = null
var _log: Array = []
var _settings: LoggingSettings = null
var _ts: LoggingTrainerService = null
var _rides: LoggingRides = null


func before_each() -> void:
	CmdLine.set_args(PackedStringArray(), true)
	_dir = Paths.make_temp_dir("wattlands_app_test")
	Paths.set_override(_dir)
	_bus = WlEventBus.new()
	autofree(_bus)
	_log = []
	_settings = LoggingSettings.new()
	_settings.log = _log
	_settings.bus = _bus
	autofree(_settings)
	_ts = LoggingTrainerService.new()
	_ts.log = _log
	add_child_autofree(_ts)
	_rides = LoggingRides.new()
	_rides.log = _log
	autofree(_rides)


func after_each() -> void:
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	Util.remove_tree(_dir)
	# Let replaced governors (queue_free) go before GUT counts orphans.
	await wait_process_frames(1)


func _args(list: Array) -> void:
	var a := PackedStringArray()
	for s: String in list:
		a.append(s)
	CmdLine.set_args(a, true)


func _make() -> QuitRecordingApp:
	var app := QuitRecordingApp.new()
	app.settings = _settings
	app.trainer_service = _ts
	app.rides = _rides
	app.bus = _bus
	add_child_autofree(app)
	app.state_changed.connect(func(s: String, _p: Dictionary) -> void: _log.append("state:" + s))
	return app


func _rider(recorder: RideRecorderApi = null) -> LocalRider:
	var m := MockTrainer.from_spec("erg", 200.0)
	autofree(m)
	var r := LocalRider.new()
	add_child_autofree(r)
	var opts := {"governor": Fakes.FakeGovernor.new(), "bus": _bus}
	if recorder != null:
		opts["recorder"] = recorder
	r.setup(1, RiderProfile.new(), null, m, opts)
	return r


# --- state machine ---------------------------------------------------------------------------


func test_initial_state() -> void:
	var app := _make()
	assert_eq(app.state, "boot")
	assert_eq(app.params, {})
	assert_eq(app.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(app.is_booted(), "no boot outside the real app")
	var autoload := AutoloadLookup.app()
	assert_not_null(autoload)
	assert_false(autoload.is_booted(), "the App autoload never boots under GUT (no Bluetooth)")


func test_goto_emits_state_changed_and_the_bus_event() -> void:
	var app := _make()
	watch_signals(app)
	watch_signals(_bus)
	app.goto("title")
	assert_eq(app.state, "title")
	assert_signal_emitted_with_parameters(app, "state_changed", ["title", {}])
	assert_signal_emitted_with_parameters(_bus, "app_state_changed", ["title"])
	var p := {"game_id": "workout"}
	app.goto("lobby", p)
	p["game_id"] = "changed"
	assert_eq(app.params, {"game_id": "workout"}, "params are copied")
	assert_signal_emitted_with_parameters(app, "state_changed", ["lobby", {"game_id": "workout"}])


func test_every_state_is_reachable() -> void:
	var app := _make()
	for s: String in WlApp.STATES:
		app.goto(s)
		assert_eq(app.state, s)
	assert_eq(WlApp.STATES.size(), 10)


func test_unknown_state_is_refused() -> void:
	var app := _make()
	app.goto("title")
	app.goto("disco")
	assert_push_error("unknown state")
	assert_eq(app.state, "title")


func test_quitting_is_terminal() -> void:
	var app := _make()
	app.goto("quitting")
	app.goto("title")
	assert_push_warning("quitting")
	assert_eq(app.state, "quitting")


func test_is_scripted_and_launch_options() -> void:
	var app := _make()
	assert_false(app.is_scripted())
	assert_eq(app.launch_options()["role"], "")
	_args(["--host", "--game=workout", "--content=e2e", "--seed=42", "--autopilot", "--wait-peers=3",
		"--mock-trainer=erg", "--relay=ws://127.0.0.1:8787/v1", "--run-seconds=400", "--sim-speed=1"])
	assert_true(app.is_scripted())
	var o := app.launch_options()
	assert_eq(o["role"], Wl.HOST)
	assert_eq(o["game_id"], "workout")
	assert_eq(o["content_id"], "e2e")
	assert_eq(o["seed"], 42)
	assert_eq(o["autopilot"], true)
	assert_eq(o["wait_peers"], 3)
	assert_eq(o["mock_trainer"], "erg")
	assert_eq(o["relay"], "ws://127.0.0.1:8787/v1")
	assert_eq(o["run_seconds"], 400.0)
	_args(["--join=k7q-x2m"])
	assert_true(app.is_scripted())
	o = app.launch_options()
	assert_eq(o["role"], Wl.CLIENT)
	assert_eq(o["code"], "K7QX2M")


# --- boot ---------------------------------------------------------------------------------------


func test_boot_order() -> void:
	var app := _make()
	watch_signals(app)
	app.boot()
	assert_eq(_log, ["load_all", "start", "process_queue", "state:title"])
	assert_signal_emitted(app, "booted")
	assert_true(app.is_booted())
	app.boot()
	assert_eq(_log.size(), 4, "boot runs once")


func test_scripted_boot_goes_to_the_lobby() -> void:
	_args(["--host", "--game=workout", "--content=e2e", "--mock-trainer=erg"])
	var app := _make()
	app.boot()
	assert_eq(app.state, "lobby")
	assert_eq(app.params["scripted"], true)
	assert_eq(app.params["role"], Wl.HOST)
	assert_eq(app.params["game_id"], "workout")


func test_boot_with_the_real_services() -> void:
	_args(["--mock-trainer=const:w=120,rpm=80"])
	var ts := WlTrainerService.new()
	ts.input_router = Fakes.FakeInputRouter.new()
	autofree(ts.input_router)
	ts.bus = _bus
	var s := WlSettings.new()
	s.bus = _bus
	autofree(s)
	ts.settings = s
	add_child_autofree(ts)
	var app := QuitRecordingApp.new()
	app.settings = s
	app.trainer_service = ts
	app.rides = _rides
	app.bus = _bus
	add_child_autofree(app)
	app.boot()
	assert_true(ts.is_mock())
	assert_not_null(ts.local_rider())
	assert_eq(app.state, "title")
	app.quit(0)
	assert_true(ts.local_rider().is_shut_down())
	assert_eq(app.quit_codes, [0] as Array[int])


# --- quit and exit paths ------------------------------------------------------------------------


func test_quit_shuts_the_riders_down_after_the_quitting_signal() -> void:
	var r := _rider()
	var g := r.governor as Fakes.FakeGovernor
	var app := _make()
	var seen_at_quitting: Array = []
	app.quitting.connect(func(code: int) -> void: seen_at_quitting.append([code, g.shutdown_count, app.state]))
	watch_signals(_bus)
	app.quit(3)
	assert_eq(seen_at_quitting, [[3, 0, "quitting"]], "the stack is still up for the app shell")
	assert_eq(g.shutdown_count, 1, "SIM flat, then Stop")
	assert_true(r.is_shut_down())
	assert_has(_log, "shutdown_all")
	assert_eq(app.quit_codes, [3] as Array[int])
	assert_eq(app.exit_code, 3)
	assert_true(app.is_quitting())
	assert_signal_emitted_with_parameters(_bus, "app_state_changed", ["quitting"])
	app.quit(5)
	assert_eq(app.quit_codes, [3] as Array[int], "quit runs once")


func test_quit_mid_session_shuts_the_session_rider_down_and_ticks_it_on() -> void:
	_args(["--mock-trainer=erg"])
	var ts := WlTrainerService.new()
	ts.input_router = Fakes.FakeInputRouter.new()
	autofree(ts.input_router)
	ts.bus = _bus
	ts.settings = _settings
	ts.rider_options_factory = func() -> Dictionary:
		return {"governor": Fakes.FakeGovernor.new(), "bus": _bus}
	add_child_autofree(ts)
	_settings.load_all()
	ts.start()
	var r := ts.local_rider()
	ts.set_external_tick(true)
	var g := Fakes.FakeGovernor.new()
	r.setup(2, _settings.profile, null, ts.device(), {"multiplayer": true, "governor": g, "bus": _bus})
	var app := QuitRecordingApp.new()
	app.settings = _settings
	app.trainer_service = ts
	app.rides = _rides
	app.bus = _bus
	add_child_autofree(app)
	app.quit(0)
	assert_eq(g.shutdown_count, 1, "the session governor itself goes SIM flat, then Stop")
	assert_eq(r.governor, g, "no menu rider is built while quitting")
	assert_false(ts.is_external_tick(), "the service ticks the shut-down rider from now on")
	var ticks := g.ticks.size()
	ts.step()
	assert_eq(g.ticks.size(), ticks + 1, "so the safe commands keep going out")


func test_quit_without_a_trainer_service_still_shuts_down() -> void:
	var r := _rider()
	var app := QuitRecordingApp.new()
	app.bus = _bus
	app.trainer_service = null
	add_child_autofree(app)
	# No injected service: the TrainerService autoload (W0 tree) or the live list is used.
	app.quit(0)
	assert_true(r.is_shut_down())


func test_quit_saves_a_ride_still_recording() -> void:
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(rec)
	r.tick(Wl.SIM_DT)
	var app := _make()
	app.quit(0)
	assert_eq(rec.saves.size(), 1)
	assert_false(rec.recording)


func test_quit_with_a_real_trainer_waits_for_the_safe_commands() -> void:
	var d := Fakes.FakeDevice.new()
	autofree(d)
	_ts.fake_device = d
	_ts.mock = false
	var r := _rider()
	var app := _make()
	app.quit(0)
	assert_true(r.is_shut_down(), "shut down at once")
	assert_eq(app.quit_codes.size(), 0, "the process waits a moment")
	await wait_seconds(WlApp.QUIT_GRACE_S + 0.3)
	assert_eq(app.quit_codes, [0] as Array[int])


func test_window_close_quits_cleanly() -> void:
	var r := _rider()
	var app := _make()
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_true(r.is_shut_down())
	assert_eq(app.quit_codes, [0] as Array[int])
	assert_eq(app.exit_reason, "window_closed")


func test_crash_notification_makes_the_trainers_safe() -> void:
	var r := _rider()
	var app := _make()
	app.notification(Node.NOTIFICATION_CRASH)
	assert_true(r.is_shut_down())
	assert_eq(app.quit_codes.size(), 0)


func test_leaving_the_tree_after_boot_shuts_down() -> void:
	var r := _rider()
	var app := _make()
	app.boot()
	remove_child(app)
	assert_true(r.is_shut_down())
	add_child(app)


func test_leaving_the_tree_before_boot_does_nothing() -> void:
	var r := _rider()
	var app := _make()
	remove_child(app)
	assert_false(r.is_shut_down())
	add_child(app)


# --- run-seconds and the report -------------------------------------------------------------------


func test_run_seconds_quits_on_platform_time() -> void:
	_args(["--run-seconds=2", "--sim-speed=4"])
	var app := _make()
	app.boot()
	watch_signals(app)
	app._process(0.25)
	assert_almost_eq(app.platform_time(), 1.0, 1e-9, "sim-speed aware")
	assert_eq(app.quit_codes.size(), 0)
	app._process(0.25)
	assert_signal_emitted(app, "run_seconds_reached")
	assert_eq(app.quit_codes, [0] as Array[int])
	assert_eq(app.exit_reason, "run_seconds")
	app._process(1.0)
	assert_eq(app.quit_codes.size(), 1)


func test_run_seconds_exit_code_is_configurable() -> void:
	_args(["--run-seconds=0.5"])
	var app := _make()
	app.run_seconds_exit_code = 4
	app.boot()
	for _i in 12:
		app._process(Wl.SIM_DT)
	assert_eq(app.quit_codes, [4] as Array[int])


func test_no_run_seconds_never_quits() -> void:
	var app := _make()
	app.boot()
	app._process(10000.0)
	assert_eq(app.quit_codes.size(), 0)


func test_fallback_report_is_written() -> void:
	var path := _dir.path_join("out/report.json")
	_args(["--join=K7QX2M", "--game=workout", "--report=" + path])
	var app := _make()
	app.exit_reason = "relay_unreachable"
	app.quit(2)
	var rep: Variant = Util.read_json(path)
	assert_true(rep is Dictionary)
	var d: Dictionary = rep
	assert_eq(d.get("exit_code"), 2.0)
	assert_eq(d.get("exit_reason"), "relay_unreachable")
	assert_eq(d.get("role"), Wl.CLIENT)
	assert_eq(d.get("room"), "K7QX2M")
	for key: String in ["events", "directives", "trace", "fit_paths", "uploads", "desync_warnings", "script_errors", "final_state"]:
		assert_true(d.has(key), key)


func test_report_from_the_app_shell_is_kept() -> void:
	var path := _dir.path_join("report.json")
	_args(["--host", "--report=" + path])
	var app := _make()
	app.quitting.connect(func(_c: int) -> void: Util.write_text(path, "{\"role\": \"HOST\", \"mine\": true}"))
	app.quit(0)
	assert_eq((Util.read_json(path) as Dictionary).get("mine"), true)
