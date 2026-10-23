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
## - Passive until start(): only WlApp.boot() calls it, and the App never boots in a process
##   whose main loop is not the app (GUT, check_scripts, the -s drivers of run_game_sim and
##   screenshot), so those never touch Bluetooth; with --mock-trainer, start() never creates
##   an FtmsConnectionManager at all.
## - start() is idempotent. The mock is MockTrainer.from_spec(spec, profile FTP, {seed
##   (--seed), preferred_cadence_rpm, cp_w, wprime_j, weight_kg, keyboard}); a bare
##   --mock-trainer means "erg". keyboard (BRIEF 4.2: W/S +-10 W, A/D cadence, read only while
##   the app window has focus) is on only with --mock-keyboard (W2r2); W/S/A/D then also move
##   menu focus, since they are the InputRouter's movement bindings too. The FTMS path adds
##   an FtmsConnectionManager child and calls start(true); its trainer_ready device becomes
##   device() and its last_device() is saved
##   in Settings. Tests pass connection_factory so nothing touches Bluetooth.
## - The rider is created as soon as a device exists: LocalRider.setup(1, profile,
##   profile.to_slot(1, Settings scaling_mode), device, {multiplayer false, record false}),
##   attached to the InputRouter. For a session the app shell may call setup() on the same
##   rider again with the lobby's peer id, slot and options.
## - Between sessions _process advances its own SimClock (--sim-speed, default 1) and ticks
##   the rider (which ticks the device) once per due 0.05 s step. set_external_tick(true)
##   hands ticking to a GameHost; set_external_tick(false) takes it back and turns the
##   session rider into the menu rider again (set up afresh: peer 1, the profile's slot,
##   solo, no plan, not recorded, applying any profile change made meanwhile, and attached
##   to the InputRouter again, since GameHost.end_session detaches it). While that
##   rider's ride is still recording, the menu reset waits until the ride is finished
##   (LocalRider.finish_ride), so the results screen can still save it; the session's plan
##   is dropped at once (LocalRider.clear_plan) all the same. Without a plan the governor
##   rides SIM grade 0, wind 0, so menus after a session (its cool-down, or an interval cut
##   short by End ride) ride free at SIM flat (W2r2). The reset keeps the trainer connection's
##   warm-up (SafetyGovernor.adopt_connection).
## - A profile or scaling change outside a session re-sets the rider up (and rebuilds a
##   mock whose rider parameters changed); during a session (external tick) or while
##   hold_rider(true) it waits for the hand-back or the release.
##   Switching trainers shuts the old rider down (SIM flat, then Stop) first, after saving a
##   ride it was still recording. A reconnect that hands over a new device object during a
##   session rebinds the session rider (LocalRider.rebind_device) instead, so the GameHost's
##   rider stays valid. A reconnect of the same device object (the manager's `reconnected`,
##   W2) calls LocalRider.trainer_reconnected(), so the governor restores the last safe mode
##   through its ramped path (BRIEF 4.4). EventBus.panic_requested makes the rider's governor
##   safe.
## - status_changed mirrors the device's and the manager's status, also on
##   EventBus.trainer_status_changed (and trainer_control_lost for "control_lost").
## - shutdown_all() shuts down every live LocalRider in the process (App.quit and the exit
##   paths, BRIEF 4.6.9); leaving the tree shuts down this service's own rider.
## - (W4, SAF-3) --sim-speed runs the menu clock faster or slower only with a MockTrainer:
##   with a real trainer every governor time rule (slew, write rate, rescue, coasting,
##   warm-up) must run on wall time, so effective_sim_speed() is 1 then (push_warning once).
##   The app's session launcher uses the same helper for the GameHost's clock.
## - (W4, SAF-8; BRIEF 4.6.9 "on exit, crash paths and disconnect: try SIM flat, then Stop")
##   disconnect_trainer(), connect_trainer() (a switch to another trainer) and use_mock() make
##   the trainer safe before its link drops: the rider is shut down (its governor sends SIM
##   flat, then Stop, through the controller) and released, and the link action waits until
##   the FTMS control point has sent both, or SAFE_UNLINK_TIMEOUT_S at most. Without a pending
##   control-point write (a mock, a fake manager, the hardware lock) it happens at once.
## - Heart rate sensor: the FTMS path also starts an HrSensorManager (hr_manager(), start(true):
##   it reconnects the remembered sensor). Its transport rides the trainer's backend: a
##   GdbleTransport sharing the trainer transport's BluetoothManager, or a second
##   BridgeTransport; with a mock trainer (no FTMS manager) it has none, and the mock's own
##   `hr` profile stands in. The app's rider reads heart_rate_bpm() through
##   LocalRider.heart_rate_source; bots never get it.

signal status_changed(status: String, detail: String)
signal device_changed(device: TrainerDevice)

## The longest a link action waits for the old trainer's SIM flat and Stop (W4, SAF-8): one
## 2 s control-point timeout plus a little.
const SAFE_UNLINK_TIMEOUT_S := 3.0

## Test and tool injections; null or invalid means the autoload or the real class.
var settings: WlSettings = null
var bus: WlEventBus = null
var input_router: WlInputRouter = null
## Returns the FtmsConnectionManager to use (tests return a fake; default: a new one).
var connection_factory: Callable = Callable()
## Returns extra LocalRider.setup options for each (re)setup (tests inject doubles).
var rider_options_factory: Callable = Callable()
## Returns the HrSensorManager to use (tests return one with a fake transport factory).
var hr_factory: Callable = Callable()

var _device: TrainerDevice = null
var _owns_device: bool = false
var _manager: FtmsConnectionManager = null
var _hr: HrSensorManager = null
var _rider: LocalRider = null
var _status: String = TrainerDevice.STATUS_DISCONNECTED
var _detail: String = ""
var _mock_spec: String = ""
var _mock_key: Array = []
var _external_tick: bool = false
var _held: bool = false
## The rider must be set up afresh as the menu rider (after a session or a hold).
var _menu_reset_due: bool = false
var _clock: SimClock = null
var _started: bool = false
var _settings_conn: WlSettings = null
var _bus_conn: WlEventBus = null
## Link actions waiting for a trainer's safe commands to go out (SAF-8):
## [{manager: FtmsConnectionManager, left_s: float, action: Callable}].
var _unlinks: Array[Dictionary] = []
var _sim_speed_warned: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if _rider != null and is_instance_valid(_rider):
		_rider.shutdown()


func _process(delta: float) -> void:
	_advance_unlinks(delta)
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
	# The speed follows the device (effective_sim_speed(), SAF-3); set in _set_device().
	_clock = SimClock.create(1.0)
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


## The heart rate sensor manager (null until the FTMS path started; never with --mock-trainer).
func hr_manager() -> HrSensorManager:
	return _hr


## The local rider's heart rate in bpm from the paired sensor, 0 when none.
func heart_rate_bpm() -> int:
	return _hr.current_bpm() if _hr != null and is_instance_valid(_hr) else 0


## The heart rate sensor's TrainerDevice.STATUS_* ("disconnected" without a manager).
func hr_status() -> String:
	return (
		_hr.status()
		if _hr != null and is_instance_valid(_hr)
		else TrainerDevice.STATUS_DISCONNECTED
	)


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
	# SAF-8: the real trainer goes SIM flat, then Stop, before its link drops.
	var old := _detach_manager()
	_release_device()
	if old != null:
		_unlink_after_safe(old, _retire_manager.bind(old))
	var p := _profile()
	var m := (
		MockTrainer
		. from_spec(
			s,
			p.ftp_w,
			{
				"seed": CmdLine.get_int("seed", 0),
				"preferred_cadence_rpm": p.preferred_cadence_rpm,
				"cp_w": p.cp_w,
				"wprime_j": p.wprime_j,
				"weight_kg": p.weight_kg,
				# BRIEF 4.2 keyboard control (W/S power, A/D cadence), only with the explicit flag:
				# the keys are also the menus' up/down/left/right bindings (W2r2).
				"keyboard": CmdLine.get_bool("mock-keyboard", false),
			}
		)
	)
	m.name = "MockTrainer"
	_mock_spec = m.spec
	_mock_key = _mock_params(p)
	_set_device(m, true)
	_set_status(m.status(), tr("CORE_TRAINER_MOCK").replace("{spec}", m.spec))


## Settings "Disconnect" (W4, SAF-8; BRIEF 4.6.9): the rider is shut down (its governor sends
## SIM flat, then Stop) and released, then the link drops once the control point has sent both
## (or after SAFE_UNLINK_TIMEOUT_S). device() is null until a trainer is ready again, which
## sets a new rider up. Refused during a session (push_warning), like use_mock().
func disconnect_trainer() -> void:
	if _external_tick:
		push_warning("TrainerService: can't disconnect the trainer during a session")
		return
	var m := _manager
	if m == null or not is_instance_valid(m):
		return
	_release_device()
	_unlink_after_safe(m, _manager_disconnect.bind(m))


## Settings "connect to <address>" (W4, SAF-8): switching from a linked trainer to another one
## first makes the old one safe like disconnect_trainer(), then connects; the same trainer, or
## none linked, connects at once (FtmsConnectionManager.connect_to). A switch is refused during
## a session (push_warning).
func connect_trainer(address: String) -> void:
	var m := _manager
	if m == null or not is_instance_valid(m):
		push_warning("TrainerService: no Bluetooth connection manager (a mock trainer is in use)")
		return
	var current := m.linked_address()
	var switching := (
		current != "" and not GdbleTransport.same_address(current, address.strip_edges())
	)
	if not switching or _device == null:
		m.connect_to(address)
		return
	if _external_tick:
		push_warning("TrainerService: can't switch trainers during a session")
		return
	_release_device()
	_unlink_after_safe(m, _manager_connect.bind(m, address))


## True while a disconnect, switch or mock change waits for the old trainer's SIM flat and
## Stop to go out (SAF-8).
func is_unlinking() -> bool:
	return not _unlinks.is_empty()


## The --sim-speed the trainer stack may run at (W4, SAF-3): the flag (default 1) with a
## MockTrainer, or before any device when --mock-trainer is given; 1 with a real trainer
## (push_warning once), since the governor's time rules (slew 30 W/s, 2 writes per second,
## rescue, coasting, warm-up) must hold in wall time on real hardware. The app's session
## launcher passes it to the GameHost.
func effective_sim_speed() -> float:
	var spd := CmdLine.get_float("sim-speed", 1.0)
	if not is_finite(spd) or spd <= 0.0 or is_equal_approx(spd, 1.0):
		return 1.0
	var mock := _device is MockTrainer or (_device == null and CmdLine.has("mock-trainer"))
	if mock:
		return spd
	if not _sim_speed_warned:
		_sim_speed_warned = true
		push_warning(
			(
				"TrainerService: --sim-speed=%s ignored with a real trainer; the trainer runs in real time"
				% str(spd)
			)
		)
	return 1.0


## Keep the rider as it is while something drives it outside a session (the FTP test):
## profile and scaling changes wait until hold_rider(false). Releasing applies them, or
## else sets the rider up afresh, so no plan or governor profile from the holder stays.
func hold_rider(on: bool) -> void:
	var was_held := _held
	_held = on
	if on or not was_held:
		return
	_request_menu_reset()


func is_rider_held() -> bool:
	return _held


## A GameHost ticks the rider during a session (true); the service ticks it in menus (false).
## Handing ticking back (true -> false) sets the rider up afresh as the menu rider (see the
## class doc; it waits while the rider's ride is still recording).
func set_external_tick(on: bool) -> void:
	var was_external := _external_tick
	_external_tick = on
	if on:
		return
	if _clock != null:
		_clock.reset()
	if was_external:
		_request_menu_reset()


## True while the menu reset after a session or a hold still waits (a ride still recording).
func is_menu_reset_pending() -> bool:
	return _menu_reset_due


func is_external_tick() -> bool:
	return _external_tick


## The app shell's name for the same switch (W2, app-shell request): false while a GameHost
## or the FTP test screen ticks the rider (set_external_tick(true)), true when menu time
## takes over again (set_external_tick(false), with its menu reset).
func set_menu_ticking(on: bool) -> void:
	set_external_tick(not on)


## One fixed 0.05 s step of menu time: the rider (and through it the device), or the device
## alone before a rider exists. _process calls it once per due step.
func step() -> void:
	if _menu_reset_due:
		_apply_menu_reset()
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
	var old := _detach_manager()
	_release_device()
	if old != null:
		_unlink_after_safe(old, _retire_manager.bind(old))
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
	m.reconnected.connect(_on_trainer_reconnected)
	m.start(true)
	_start_hr()


## The heart rate sensor manager (once): its transport follows the trainer's backend.
func _start_hr() -> void:
	if _hr == null or not is_instance_valid(_hr):
		var h: HrSensorManager = null
		if hr_factory.is_valid():
			h = hr_factory.call() as HrSensorManager
		if h == null:
			h = HrSensorManager.new()
			h.make_transport = _make_hr_transport
		h.name = "HrSensorManager"
		h.process_mode = Node.PROCESS_MODE_ALWAYS
		_hr = h
		add_child(h)
	_hr.start(true)


## A transport for the heart rate sensor on the trainer manager's backend, or null while it
## has none (still starting, no adapter, a mock trainer).
func _make_hr_transport() -> BleTransport:
	var m := _manager
	if m == null or not is_instance_valid(m):
		return null
	var t := m.transport()
	match m.backend_name():
		FtmsConnectionManager.BACKEND_GDBLE:
			if t is GdbleTransport:
				var g := GdbleTransport.new()
				g.share_manager_of(t as GdbleTransport)
				return g
		FtmsConnectionManager.BACKEND_BRIDGE:
			if t is BridgeTransport:
				var b := BridgeTransport.new()
				b.url = (t as BridgeTransport).url
				return b
		_:
			pass
	return null


## Stop listening to the manager and forget it; returns it (null when none) so its link can be
## dropped once the trainer is safe (_retire_manager).
func _detach_manager() -> FtmsConnectionManager:
	var m := _manager
	_manager = null
	if m == null or not is_instance_valid(m):
		return null
	if m.status_changed.is_connected(_on_manager_status):
		m.status_changed.disconnect(_on_manager_status)
	if m.trainer_ready.is_connected(_on_trainer_ready):
		m.trainer_ready.disconnect(_on_trainer_ready)
	if m.reconnected.is_connected(_on_trainer_reconnected):
		m.reconnected.disconnect(_on_trainer_reconnected)
	return m


## Drop a detached manager's link and free it (after its trainer was made safe).
func _retire_manager(m: FtmsConnectionManager) -> void:
	if m == null or not is_instance_valid(m):
		return
	m.disconnect_trainer()
	if m.get_parent() == self:
		remove_child(m)
	m.queue_free()


func _manager_disconnect(m: FtmsConnectionManager) -> void:
	if m != null and is_instance_valid(m):
		m.disconnect_trainer()


func _manager_connect(m: FtmsConnectionManager, address: String) -> void:
	if m != null and is_instance_valid(m):
		m.connect_to(address)


## Runs `action` once the manager's control point has sent what the trainer was last asked
## (the shut-down rider's SIM flat and Stop), or after SAFE_UNLINK_TIMEOUT_S; at once when
## nothing is pending.
func _unlink_after_safe(m: FtmsConnectionManager, action: Callable) -> void:
	if _control_point_idle(m):
		action.call()
		return
	_unlinks.append({"manager": m, "left_s": SAFE_UNLINK_TIMEOUT_S, "action": action})


func _advance_unlinks(dt: float) -> void:
	if _unlinks.is_empty():
		return
	var due: Array[Callable] = []
	var keep: Array[Dictionary] = []
	for e in _unlinks:
		e["left_s"] = float(e["left_s"]) - maxf(dt, 0.0)
		var timed_out := float(e["left_s"]) <= 1e-6
		if timed_out or _control_point_idle(e["manager"] as FtmsConnectionManager):
			if timed_out:
				push_warning(
					(
						"TrainerService: the trainer's safe commands did not all go out within %.1f s; dropping the link anyway"
						% SAFE_UNLINK_TIMEOUT_S
					)
				)
			due.append(e["action"] as Callable)
		else:
			keep.append(e)
	_unlinks = keep
	for a in due:
		a.call()


## Nothing more can go out or nothing is waiting: no client, a client not in control (writes
## are dropped then), or an empty control-point queue with nothing in flight.
static func _control_point_idle(m: FtmsConnectionManager) -> bool:
	if m == null or not is_instance_valid(m):
		return true
	var c := m.client()
	if c == null or not is_instance_valid(c) or not c.is_ready():
		return true
	return c.queued_count() == 0 and c.in_flight_opcode() < 0


func _set_device(d: TrainerDevice, owned: bool) -> void:
	_device = d
	_owns_device = owned
	if owned and d.get_parent() == null:
		add_child(d)
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	if not d.status_changed.is_connected(_on_device_status):
		d.status_changed.connect(_on_device_status)
	_apply_sim_speed()
	device_changed.emit(d)
	_build_rider()


## The menu clock runs at effective_sim_speed() for the current device (SAF-3).
func _apply_sim_speed() -> void:
	if _clock != null:
		_clock.sim_speed = effective_sim_speed()


func _release_device() -> void:
	_menu_reset_due = false
	if _rider != null and is_instance_valid(_rider):
		var router := _router()
		if router != null:
			router.detach_rider()
		if _rider.recorder != null and _rider.recorder.is_recording():
			push_warning("TrainerService: switching trainers while a ride records; saving it first")
			_rider.finish_ride()
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
	_attach_rider()


## Menus follow the app's rider: (re)attach it to the InputRouter. GameHost.end_session
## detaches the session's rider, so every menu reset attaches it again.
func _attach_rider() -> void:
	var router := _router()
	if router != null and _rider != null and is_instance_valid(_rider):
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
	_rider.heart_rate_source = heart_rate_bpm


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
	if _held or _external_tick or _menu_reset_due:
		# The release, the hand-back or the pending menu reset sets the rider up afresh from
		# the current profile anyway.
		return
	if _device == null:
		return
	_rebuild_menu_rider()


## The session or the hold let go of the rider: set it up afresh as the menu rider now, or,
## while its ride still records, as soon as the ride is saved. Meanwhile the session's plan is
## dropped at once (LocalRider.clear_plan), so the trainer rides SIM flat in the menus rather
## than holding the cool-down or an interrupted interval (W2r2).
func _request_menu_reset() -> void:
	_menu_reset_due = true
	_apply_menu_reset()
	if not _menu_reset_due or _held or _external_tick:
		return
	if _rider != null and is_instance_valid(_rider) and not _rider.is_shut_down():
		_rider.clear_plan()


## Sets the rider up afresh as the menu rider once nothing holds it: not during a session,
## not while held, and not while its ride is still recording (saved by finish_ride first).
## A shut-down rider (quitting) is left alone.
func _apply_menu_reset() -> void:
	if not _menu_reset_due or _held or _external_tick:
		return
	if _device == null or _rider == null or not is_instance_valid(_rider) or _rider.is_shut_down():
		_menu_reset_due = false
		return
	if _rider.recorder != null and _rider.recorder.is_recording():
		return
	_menu_reset_due = false
	_rebuild_menu_rider()


## The menu rider for the current profile: a mock whose rider parameters changed is rebuilt
## (which builds a new rider), otherwise the rider is set up again around the same device.
## Either way the rider ends up attached to the InputRouter, like _build_rider leaves it.
func _rebuild_menu_rider() -> void:
	if is_mock() and _mock_params(_profile()) != _mock_key:
		use_mock(_mock_spec)
	elif _rider != null and is_instance_valid(_rider):
		_setup_rider()
		_attach_rider()


func _on_panic() -> void:
	if _rider != null and is_instance_valid(_rider):
		_rider.panic()


func _on_trainer_ready(d: TrainerDevice) -> void:
	if d == null:
		return
	if d != _device:
		if (
			_external_tick
			and _rider != null
			and is_instance_valid(_rider)
			and _device != null
			and not _owns_device
		):
			# Mid-session reconnect with a new device object: keep the GameHost's rider.
			push_warning(
				"TrainerService: a new trainer object arrived during a session; rebinding the session rider"
			)
			if (
				_device != null
				and is_instance_valid(_device)
				and _device.status_changed.is_connected(_on_device_status)
			):
				_device.status_changed.disconnect(_on_device_status)
			_device = d
			d.process_mode = Node.PROCESS_MODE_ALWAYS
			if not d.status_changed.is_connected(_on_device_status):
				d.status_changed.connect(_on_device_status)
			_apply_sim_speed()
			_rider.rebind_device(d)
			device_changed.emit(d)
		else:
			_release_device()
			_set_device(d, false)
	var s := _settings()
	if s != null and _manager != null:
		var info := _manager.last_device()
		if not info.is_empty():
			s.set_last_device(info)
	_set_status(d.status(), d.device_name())


## The manager emits trainer_ready(d) and then reconnected(d) after every successful
## reconnect. A new device object was already rebound (or the rider rebuilt) by
## _on_trainer_ready; the governor still learns that the trainer was reset to SIM flat.
func _on_trainer_reconnected(d: TrainerDevice) -> void:
	if d == null or d != _device:
		return
	if _rider != null and is_instance_valid(_rider):
		_rider.trainer_reconnected()


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
