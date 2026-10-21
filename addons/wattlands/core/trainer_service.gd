class_name WlTrainerService
extends Node
## Autoload `TrainerService`: the app's trainer and its local rider (BRIEF 3.5 zero-touch
## start, 4.4). Owned by platform; public API frozen after W0.
## With --mock-trainer=<profile> it uses a MockTrainer; otherwise an FtmsConnectionManager
## auto-connects the last trainer on launch. It owns the app's LocalRider (created on demand
## for a session) and forwards its gestures to the InputRouter for pedal-scan menus.
## Runs with PROCESS_MODE_ALWAYS; ticks the device and the menu-time rider on platform time
## while no GameHost is running (the GameHost ticks it during a session).
##
## Details (W1):
## - start() is idempotent. The mock is MockTrainer.from_spec(spec, profile FTP, {seed
##   (--seed), preferred_cadence_rpm, cp_w, wprime_j, weight_kg}); a bare --mock-trainer
##   means "erg". The FTMS path adds an FtmsConnectionManager child and calls
##   start(true); its trainer_ready device becomes device() and its last_device() is saved
##   in Settings. Tests pass connection_factory so nothing touches Bluetooth.
## - The rider is created as soon as a device exists: LocalRider.setup(1, profile,
##   profile.to_slot(1, Settings scaling_mode), device, {multiplayer false, record false}),
##   attached to the InputRouter. For a session the app shell may call setup() on the same
##   rider again with the lobby's peer id, slot and options.
## - Between sessions _process advances its own SimClock (--sim-speed, default 1) and ticks
##   the rider (which ticks the device) once per due 0.05 s step. set_external_tick(true)
##   hands ticking to a GameHost; set_external_tick(false) takes it back.
## - A profile or scaling change outside a session re-sets the rider up (and rebuilds a
##   mock whose rider parameters changed); hold_rider(true) defers that until released.
##   Switching trainers shuts the old rider down (SIM flat, then Stop) first.
##   EventBus.panic_requested makes the rider's governor safe.
## - status_changed mirrors the device's and the manager's status, also on
##   EventBus.trainer_status_changed (and trainer_control_lost for "control_lost").
## - shutdown_all() shuts down every live LocalRider in the process (App.quit and the exit
##   paths, BRIEF 4.6.9); leaving the tree shuts down this service's own rider.

signal status_changed(status: String, detail: String)
signal device_changed(device: TrainerDevice)

## Test and tool injections; null or invalid means the autoload or the real class.
var settings: WlSettings = null
var bus: WlEventBus = null
var input_router: WlInputRouter = null
## Returns the FtmsConnectionManager to use (tests return a fake; default: a new one).
var connection_factory: Callable = Callable()
## Returns extra LocalRider.setup options for each (re)setup (tests inject doubles).
var rider_options_factory: Callable = Callable()

var _device: TrainerDevice = null
var _owns_device: bool = false
var _manager: FtmsConnectionManager = null
var _rider: LocalRider = null
var _status: String = TrainerDevice.STATUS_DISCONNECTED
var _detail: String = ""
var _mock_spec: String = ""
var _mock_key: Array = []
var _external_tick: bool = false
var _held: bool = false
var _pending_change: bool = false
var _clock: SimClock = null
var _started: bool = false
var _settings_conn: WlSettings = null
var _bus_conn: WlEventBus = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if _rider != null and is_instance_valid(_rider):
		_rider.shutdown()


func _process(delta: float) -> void:
	if _external_tick or _device == null or _clock == null:
		return
	var n := _clock.advance(delta)
	for _i in n:
		step()


## Start the configured backend (mock or FTMS auto-connect).
func start() -> void:
	if _started:
		return
	_started = true
	var spd := CmdLine.get_float("sim-speed", 1.0)
	_clock = SimClock.create(spd if spd > 0.0 else 1.0)
	_connect_services()
	if CmdLine.has("mock-trainer"):
		use_mock(CmdLine.get_str("mock-trainer", "erg"))
	else:
		_start_ftms()


func device() -> TrainerDevice:
	return _device


## The app's local rider (creates it around the current device on first use).
## Null while there is no trainer yet.
func local_rider() -> LocalRider:
	if _rider == null and _device != null:
		_build_rider()
	return _rider


func status() -> String:
	return _status


## The detail text of the latest status.
func status_detail() -> String:
	return _detail


func is_mock() -> bool:
	return _device is MockTrainer


## The FTMS connection manager (null when mocked).
func connection() -> FtmsConnectionManager:
	return _manager


## Switch to a MockTrainer with `spec` (settings screen "use mock trainer").
func use_mock(spec: String) -> void:
	if _external_tick:
		push_warning("TrainerService: can't switch trainers during a session")
		return
	var s := spec.strip_edges()
	if s == "" or s == "true":
		s = "erg"
	if not _started:
		_started = true
		_clock = SimClock.create(1.0)
		_connect_services()
	_release_device()
	_stop_manager()
	var p := _profile()
	var m := MockTrainer.from_spec(s, p.ftp_w, {
		"seed": CmdLine.get_int("seed", 0),
		"preferred_cadence_rpm": p.preferred_cadence_rpm,
		"cp_w": p.cp_w,
		"wprime_j": p.wprime_j,
		"weight_kg": p.weight_kg,
	})
	m.name = "MockTrainer"
	_mock_spec = m.spec
	_mock_key = _mock_params(p)
	_set_device(m, true)
	_set_status(m.status(), tr("CORE_TRAINER_MOCK").replace("{spec}", m.spec))


## Keep the rider as it is while something drives it outside a session (the FTP test):
## profile and scaling changes wait until hold_rider(false). Releasing applies them, or
## else sets the rider up afresh, so no plan or governor profile from the holder stays.
func hold_rider(on: bool) -> void:
	var was_held := _held
	_held = on
	if on or not was_held:
		return
	_pending_change = false
	if _external_tick or _device == null:
		return
	if is_mock() and _mock_params(_profile()) != _mock_key:
		use_mock(_mock_spec)
	elif _rider != null and is_instance_valid(_rider):
		_setup_rider()


func is_rider_held() -> bool:
	return _held


## A GameHost ticks the rider during a session (true); the service ticks it in menus (false).
func set_external_tick(on: bool) -> void:
	_external_tick = on
	if not on and _clock != null:
		_clock.reset()


func is_external_tick() -> bool:
	return _external_tick


## One fixed 0.05 s step of menu time: the rider (and through it the device), or the device
## alone before a rider exists. _process calls it once per due step.
func step() -> void:
	if _rider != null and is_instance_valid(_rider):
		_rider.tick(Wl.SIM_DT)
	elif _device != null and is_instance_valid(_device):
		_device.tick(Wl.SIM_DT)


## Shut down every live LocalRider's governor (SIM flat, then Stop). Returns how many.
func shutdown_all() -> int:
	var n := 0
	for r in LocalRider.live_riders():
		r.shutdown()
		n += 1
	return n


# --- internals ------------------------------------------------------------------------------


func _start_ftms() -> void:
	_release_device()
	_stop_manager()
	var m: FtmsConnectionManager = null
	if connection_factory.is_valid():
		m = connection_factory.call() as FtmsConnectionManager
	if m == null:
		m = FtmsConnectionManager.new()
	m.name = "FtmsConnectionManager"
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	_manager = m
	add_child(m)
	m.status_changed.connect(_on_manager_status)
	m.trainer_ready.connect(_on_trainer_ready)
	m.start(true)


func _stop_manager() -> void:
	if _manager == null:
		return
	if is_instance_valid(_manager):
		if _manager.status_changed.is_connected(_on_manager_status):
			_manager.status_changed.disconnect(_on_manager_status)
		if _manager.trainer_ready.is_connected(_on_trainer_ready):
			_manager.trainer_ready.disconnect(_on_trainer_ready)
		_manager.disconnect_trainer()
		if _manager.get_parent() == self:
			remove_child(_manager)
		_manager.queue_free()
	_manager = null


func _set_device(d: TrainerDevice, owned: bool) -> void:
	_device = d
	_owns_device = owned
	if owned and d.get_parent() == null:
		add_child(d)
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	if not d.status_changed.is_connected(_on_device_status):
		d.status_changed.connect(_on_device_status)
	device_changed.emit(d)
	_build_rider()


func _release_device() -> void:
	if _rider != null and is_instance_valid(_rider):
		var router := _router()
		if router != null:
			router.detach_rider()
		_rider.shutdown()
		if _rider.get_parent() == self:
			remove_child(_rider)
		_rider.queue_free()
	_rider = null
	if _device != null and is_instance_valid(_device):
		if _device.status_changed.is_connected(_on_device_status):
			_device.status_changed.disconnect(_on_device_status)
		if _owns_device:
			if _device.get_parent() == self:
				remove_child(_device)
			_device.queue_free()
	_device = null
	_owns_device = false


func _build_rider() -> void:
	if _device == null:
		return
	if _rider == null or not is_instance_valid(_rider):
		_rider = LocalRider.new()
		_rider.name = "LocalRider"
		add_child(_rider)
	_setup_rider()
	var router := _router()
	if router != null:
		router.attach_rider(_rider)


func _setup_rider() -> void:
	var p := _profile()
	var mode := _scaling_mode()
	var opts := {
		"multiplayer": false,
		"scaling_mode": mode,
		"record": false,
		"seed": CmdLine.get_int("seed", 0),
	}
	if rider_options_factory.is_valid():
		var extra: Variant = rider_options_factory.call()
		if extra is Dictionary:
			opts.merge(extra as Dictionary, true)
	_rider.setup(1, p, p.to_slot(1, mode), _device, opts)


func _connect_services() -> void:
	var s := _settings()
	if s != null and s != _settings_conn:
		s.changed.connect(_on_settings_changed)
		_settings_conn = s
	var b := _bus()
	if b != null and b != _bus_conn:
		b.panic_requested.connect(_on_panic)
		_bus_conn = b


func _on_settings_changed(key: String) -> void:
	if key != "" and key != "profile" and key != "scaling_mode":
		return
	if _held:
		_pending_change = true
		return
	if _external_tick or _device == null:
		return
	if is_mock() and _mock_params(_profile()) != _mock_key:
		use_mock(_mock_spec)
		return
	if _rider != null and is_instance_valid(_rider):
		_setup_rider()


func _on_panic() -> void:
	if _rider != null and is_instance_valid(_rider):
		_rider.panic()


func _on_trainer_ready(d: TrainerDevice) -> void:
	if d == null:
		return
	if d != _device:
		_release_device()
		_set_device(d, false)
	var s := _settings()
	if s != null and _manager != null:
		var info := _manager.last_device()
		if not info.is_empty():
			s.set_last_device(info)
	_set_status(d.status(), d.device_name())


func _on_manager_status(s: String, detail: String) -> void:
	_set_status(s, detail)


func _on_device_status(s: String, detail: String) -> void:
	_set_status(s, detail)


func _set_status(s: String, detail: String) -> void:
	if s == _status and detail == _detail:
		return
	_status = s
	_detail = detail
	status_changed.emit(s, detail)
	var b := _bus()
	if b != null:
		b.trainer_status_changed.emit(s, detail)
		if s == TrainerDevice.STATUS_CONTROL_LOST:
			b.trainer_control_lost.emit(detail)


static func _mock_params(p: RiderProfile) -> Array:
	return [p.ftp_w, p.cp_w, p.wprime_j, p.preferred_cadence_rpm, p.weight_kg]


func _profile() -> RiderProfile:
	var s := _settings()
	return s.profile if s != null else RiderProfile.new()


func _scaling_mode() -> String:
	var s := _settings()
	return s.scaling_mode() if s != null else Wl.FAIR_FTP


func _settings() -> WlSettings:
	return settings if settings != null else AutoloadLookup.settings()


func _bus() -> WlEventBus:
	return bus if bus != null else AutoloadLookup.bus()


func _router() -> WlInputRouter:
	return input_router if input_router != null else AutoloadLookup.input_router()
