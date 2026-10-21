class_name FtmsConnectionManager
extends Node
## Finds, connects and keeps a real trainer connected (BRIEF 4.2, 4.4). Owned by ble;
## public API frozen after W0. Picks a BleTransport backend (GDBLE first; the Python
## bridge as P1 fallback), scans for FTMS (advertised 0x1826 or a name containing KICKR),
## connects, hands the link to FtmsClient.begin(), and exposes a ready FtmsTrainer.
## On disconnect it reconnects with exponential backoff (1, 2, 4, 8 s, max 15 s),
## resubscribes, re-requests control and asks the governor to restore the last safe mode.
## Remembers the last device in Paths.last_device_path().
## No adapter (adapter_ready(false, ...)) is reported with push_warning, never an error.
##
## Backend choice (start()): GdbleTransport when the GDBLE library is loaded and its
## adapter initializes; otherwise BridgeTransport if the bridge on ws://127.0.0.1:8765
## answers; otherwise none: backend_name() is "" and status_changed(STATUS_DISCONNECTED,
## "No Bluetooth adapter found" or "Bluetooth is unavailable ...") says why. A backend that
## doesn't answer initialize() within INIT_TIMEOUT_S counts as unavailable. Calling start()
## again after "none" tries every backend again. Add the manager to the scene tree before
## start(): GDBLE drains its events while its node processes.
## An adapter lost while no trainer is linked (powered off, bridge closed) sets
## STATUS_DISCONNECTED "No Bluetooth adapter found"; scan() or start() initializes it again
## and then scans. connect_to() during start-up waits for the backend, then connects.
##
## Connection flow: connect_to(address) -> transport.connect_device -> device_connected ->
## FtmsClient.attach(transport) (once per transport) + FtmsClient.begin() (the 4.4 flow:
## discover, read features and ranges, subscribe, indications, Request Control, SIM flat)
## -> client_ready -> the FtmsTrainer (FtmsTrainer.create(client, name), created once per
## trainer address and kept across reconnects) -> trainer_ready(device). The device is saved
## as {address, name} in Paths.last_device_path().
##
## Reconnect: an unexpected device_disconnected (or a failed or timed-out attempt) waits
## backoff_delay(n) = 1, 2, 4, 8, 15, 15, ... s, connects again, runs FtmsClient.begin()
## again (resubscribe, re-request control), then emits trainer_ready(device) followed by
## reconnected(device): the platform hands that to the rider's governor so it restores the
## last safe mode (begin() leaves the trainer in SIM flat). A GATT reset (notification
## overflow, services changed) on a ready trainer runs begin() the same way without dropping
## the link. connect_to() for the trainer being connected sends no second request; during a
## backoff wait it tries at once and starts the backoff over.
## A setup failure (FtmsClient.failed, or no client_ready within SETUP_TIMEOUT_S) drops the
## link and retries the same way, except under the hardware lock (BRIEF 1), where it keeps
## the read-only link and stops. (W4, ftms-ble-1) FtmsClient.failed on a ready trainer (a
## control-point write unanswered after its two retries: "the link is presumed dead") or after
## a control loss is handled the same way: drop the link, back off, connect, run begin()
## again, then trainer_ready + reconnected, so the governor restores its last safe mode
## (BRIEF 4.4) and panic, rescue and the exit writes reach the trainer again.
## Control lost (Request Control 0x05 or Machine Status 0xFF, FtmsClient.control_lost):
## status STATUS_CONTROL_LOST with the "another app may hold control" detail, control_lost
## emitted, and no automatic retry (grabbing control back from a running Zwift session
## would fight the other app; a GATT reset doesn't retry either); retry_control() runs
## begin() again on request.
##
## Auto-connect: start(true) scans as soon as the backend is ready and connects to the last
## device the moment it is seen (addresses compared case-insensitively). While no trainer is
## linked it keeps scanning in AUTO_SCAN_S windows, so a trainer switched on after the app
## started is still picked up with no input (BRIEF 3.5); stop_scan() or disconnect_trainer()
## ends that search until the next start(true). (W4, ftms-ble-3) Every scan the manager
## starts after an earlier one first stops it (transport.stop_scan(), then start_scan()):
## GDBLE refuses a second start while its own timer for the first still runs (BUSY), and the
## manager's window and GDBLE's are two clocks.
##
## Trainer switch (W4, SAF-8): connect_to() another address while a trainer is linked releases
## the old FtmsTrainer from the shared FtmsClient (FtmsTrainer.release_client()) before the
## link drops, so a late write from the old trainer's rider can never reach the next trainer.
## Making the old trainer safe first (SIM flat, then Stop) is WlTrainerService's job
## (disconnect_trainer(), connect_trainer(), use_mock()).
##
## Time: every timer (backoff, backend start, attempt and setup timeouts, scan length)
## advances in tick(dt). _process(delta) calls tick(delta) unless manual_clock is set
## (tests drive tick() themselves). Runs with PROCESS_MODE_ALWAYS, and so do its transport, client and
## device children. The manager never writes to the trainer itself.

## {"address", "name", "rssi", "services"}
signal device_found(info: Dictionary)
## TrainerDevice.STATUS_* plus detail ("no adapter", "another app may hold control", ...).
signal status_changed(status: String, detail: String)
## A connected, ready trainer (also after every successful reconnect).
signal trainer_ready(device: TrainerDevice)
## Additive: the same device is ready again after a link loss, a GATT reset or
## retry_control(), emitted right after trainer_ready. The governor restores its last safe
## mode.
signal reconnected(device: TrainerDevice)
## Additive: another app may hold control (Request Control 0x05 or Machine Status 0xFF).
## `detail` is the translated BLE_STATUS_CONTROL_HELD text.
signal control_lost(detail: String)

const BACKEND_GDBLE := "gdble"
const BACKEND_BRIDGE := "bridge"
## FTMS service, advertised by the KICKR CORE (BRIEF 4.3).
const FTMS_SERVICE_UUID := "1826"
## Name filter, compared case-insensitively (BRIEF 4.4).
const NAME_HINT := "kickr"
## Backoff: 1, 2, 4, 8 s, then capped at 15 s (BRIEF 4.4).
const BACKOFF_MAX_S := 15.0
## A connect attempt (or a backend re-initialization) that takes longer fails. Longer
## than the bridge's own 25 s connect timeout, so the transport normally answers first.
const CONNECT_TIMEOUT_S := 30.0
## FtmsClient.begin() must reach client_ready within this.
const SETUP_TIMEOUT_S := 30.0
## A backend whose initialize() gets no adapter_ready within this is skipped (start()).
const INIT_TIMEOUT_S := 10.0
const DEFAULT_SCAN_S := 10.0
## start(true) scans this long when a last device is remembered.
const AUTO_SCAN_S := 30.0

enum Link { IDLE, REINIT, CONNECTING, SETUP, READY, WAIT_RETRY, CONTROL_LOST, SETUP_FAILED }
enum Backend { NONE, STARTING, READY, LOST }

const _EPS := 1e-6

## Tests: true stops _process from ticking; call tick(dt) directly.
var manual_clock: bool = false
## Test seams; empty Callables use the real classes.
## make_gdble, make_bridge: () -> BleTransport
var make_gdble: Callable = Callable()
var make_bridge: Callable = Callable()
## make_client: () -> FtmsClient
var make_client: Callable = Callable()
## make_trainer: (client: FtmsClient, name: String) -> TrainerDevice
var make_trainer: Callable = Callable()

var _transport: BleTransport = null
var _backend: Backend = Backend.NONE
var _backend_name: String = ""
var _candidates: Array[String] = []
var _backend_errors: Array[String] = []
var _adapter_missing: bool = false
var _started: bool = false
var _init_left: float = 0.0

var _client: FtmsClient = null
var _client_transport: BleTransport = null
var _device: TrainerDevice = null
var _device_address: String = ""

var _link: Link = Link.IDLE
## {"address": String, "name": String} of the trainer being connected or kept.
var _target: Dictionary = {}
var _ever_ready: bool = false
var _attempt: int = 0
var _retry_left: float = 0.0
var _attempt_left: float = 0.0
var _setup_left: float = 0.0

var _auto_connect: bool = false
var _last: Dictionary = {}
var _scanning: bool = false
## A start_scan() went to the transport and no stop_scan() since (its scan may still run).
var _scan_issued: bool = false
var _scan_left: float = 0.0
var _scan_queued: float = -1.0
## address (lower case) -> info, for the current scan
var _found: Dictionary = {}

var _status: String = TrainerDevice.STATUS_DISCONNECTED
var _status_detail: String = ""


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not manual_clock:
		tick(delta)


## Start the backend; with auto_connect, connect to the last device as soon as it is seen.
func start(auto_connect_last: bool = true) -> void:
	_auto_connect = auto_connect_last
	_last = read_last_device()
	if _started and _backend != Backend.NONE:
		# READY: scan again; LOST: scan() initializes the adapter again first.
		if (_backend == Backend.READY or _backend == Backend.LOST) and _link == Link.IDLE:
			scan(_start_scan_seconds())
		return
	_started = true
	_candidates = [BACKEND_GDBLE, BACKEND_BRIDGE]
	_backend_errors.clear()
	_adapter_missing = false
	_try_next_backend()


func scan(seconds: float = DEFAULT_SCAN_S) -> void:
	if _backend == Backend.STARTING:
		_scan_queued = seconds
		return
	if _backend == Backend.LOST and _transport != null and _link == Link.IDLE:
		# The adapter went away earlier: initialize it again, then scan (_on_adapter_ready).
		_scan_queued = seconds
		_set_status(TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_STARTING"))
		_transport.initialize()
		return
	if _transport == null or _backend != Backend.READY:
		push_warning("Bluetooth: cannot scan (%s)" % _status_detail)
		return
	_found.clear()
	_scanning = true
	_scan_left = maxf(seconds, 0.0)
	if _link == Link.IDLE:
		_set_status(TrainerDevice.STATUS_SCANNING, tr("BLE_STATUS_SCANNING"))
	if _scan_issued:
		# The previous scan may still run in the backend (ftms-ble-3): stop it first.
		_transport.stop_scan()
	_scan_issued = true
	_transport.start_scan(seconds)


## Also ends auto-connect's search for the last device (start(true) resumes it).
func stop_scan() -> void:
	var was := _scanning
	_auto_connect = false
	_halt_scan()
	if was and _link == Link.IDLE and _status == TrainerDevice.STATUS_SCANNING:
		_set_status(TrainerDevice.STATUS_DISCONNECTED, "")


func connect_to(address: String) -> void:
	var addr := address.strip_edges()
	if addr.is_empty():
		push_error("FtmsConnectionManager.connect_to: empty address")
		return
	if _transport == null or _backend == Backend.NONE:
		push_warning("Bluetooth: cannot connect to %s (%s)" % [addr, _status_detail])
		return
	_halt_scan()
	var switching := not _target.is_empty() and not _same_address(addr, String(_target["address"]))
	if not switching and not _target.is_empty():
		# The trainer already linked: nothing to do when ready or setting up; after a
		# control loss or a failed setup, run begin() again instead of reconnecting.
		if _link == Link.READY or _link == Link.SETUP:
			return
		# Already connecting (or waiting for the backend): no second request.
		if _link == Link.CONNECTING or _link == Link.REINIT:
			return
		if _link == Link.CONTROL_LOST or _link == Link.SETUP_FAILED:
			retry_control()
			return
	if switching and _link != Link.IDLE:
		_link = Link.IDLE
		_release_old_device()
		_transport.disconnect_device()
	if switching or _link == Link.IDLE:
		_ever_ready = false
	_target = {"address": addr, "name": _known_name(addr)}
	_attempt = 0
	_begin_attempt()


func disconnect_trainer() -> void:
	_auto_connect = false
	var had_link := _link != Link.IDLE
	_link = Link.IDLE
	_attempt = 0
	_retry_left = 0.0
	if had_link and _transport != null:
		_transport.disconnect_device()
	_set_status(TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_DISCONNECTED"))


## The current trainer device (null until ready).
func device() -> TrainerDevice:
	return _device


func last_device() -> Dictionary:
	return read_last_device()


## The address of the trainer being connected or kept, or "" when none (W4, additive):
## WlTrainerService tells a trainer switch from a reconnect with it.
func linked_address() -> String:
	if _link == Link.IDLE or _target.is_empty():
		return ""
	return String(_target["address"])


## "gdble", "bridge" or "" (none available).
func backend_name() -> String:
	return _backend_name if _backend == Backend.READY or _backend == Backend.LOST else ""


# --- Additive API ----------------------------------------------------------------------


## Advance every timer by dt seconds (backoff, backend start, attempt and setup timeouts,
## scan length).
func tick(dt: float) -> void:
	if _backend == Backend.STARTING:
		_init_left -= dt
		if _init_left <= _EPS:
			# Treated like adapter_ready(false): drop this backend, try the next one.
			_on_adapter_ready(false, "no answer within %d s" % int(INIT_TIMEOUT_S))
	if _scanning:
		_scan_left -= dt
		if _scan_left <= _EPS:
			_scanning = false
			if _auto_rescan():
				pass
			elif _link == Link.IDLE and _status == TrainerDevice.STATUS_SCANNING:
				var detail := tr("BLE_STATUS_NONE_FOUND") if _found.is_empty() else ""
				_set_status(TrainerDevice.STATUS_DISCONNECTED, detail)
	match _link:
		Link.WAIT_RETRY:
			_retry_left -= dt
			if _retry_left <= _EPS:
				_begin_attempt()
		Link.CONNECTING, Link.REINIT:
			_attempt_left -= dt
			if _attempt_left <= _EPS:
				var was_connecting := _link == Link.CONNECTING
				_attempt_failed("timeout")
				if was_connecting and _transport != null:
					_transport.disconnect_device()
		Link.SETUP:
			_setup_left -= dt
			if _setup_left <= _EPS:
				_setup_failed("setup timed out")
		_:
			pass


## TrainerDevice.STATUS_* of the last status_changed.
func status() -> String:
	return _status


func status_detail() -> String:
	return _status_detail


## Trainers seen by the current scan (filtered), sorted by address.
func found_devices() -> Array:
	var keys: Array = _found.keys()
	keys.sort()
	var out: Array = []
	for k: Variant in keys:
		out.append(_found[k])
	return out


## The transport in use (null before start() or when none is available).
func transport() -> BleTransport:
	return _transport


## The FtmsClient (null until the first connection).
func client() -> FtmsClient:
	return _client


## True while connected and in control.
func is_ready() -> bool:
	return _link == Link.READY


## True while waiting to reconnect, or reconnecting, after a ready trainer was lost.
func is_reconnecting() -> bool:
	return (
		_ever_ready
		and (
			_link == Link.WAIT_RETRY
			or _link == Link.CONNECTING
			or _link == Link.REINIT
			or _link == Link.SETUP
		)
	)


## Seconds until the next reconnect attempt (0 unless waiting).
func retry_in() -> float:
	return maxf(_retry_left, 0.0) if _link == Link.WAIT_RETRY else 0.0


## Run FtmsClient.begin() again after control was lost or setup failed (the link is up).
func retry_control() -> void:
	if _link != Link.CONTROL_LOST and _link != Link.SETUP_FAILED:
		return
	_enter_setup()


## Backoff before reconnect attempt n (0-based): 1, 2, 4, 8, then 15 s (BRIEF 4.4).
static func backoff_delay(attempt: int) -> float:
	if attempt <= 0:
		return 1.0
	if attempt >= 4:
		return BACKOFF_MAX_S
	return minf(BACKOFF_MAX_S, pow(2.0, float(attempt)))


## The scan filter (BRIEF 4.4): advertises the FTMS service 0x1826, or its name contains
## "KICKR" (any case).
static func is_trainer(info: Dictionary) -> bool:
	var services: Variant = info.get("services", [])
	if services is Array or services is PackedStringArray:
		for u: Variant in services:
			if BleTransport.same_uuid(String(u), FTMS_SERVICE_UUID):
				return true
	var name_v: Variant = info.get("name", "")
	return name_v is String and String(name_v).to_lower().contains(NAME_HINT)


## The remembered trainer {address, name} from Paths.last_device_path(), or {}.
static func read_last_device() -> Dictionary:
	var path := Paths.last_device_path()
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	var parsed: Variant = (
		json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	)
	if not (parsed is Dictionary):
		push_warning("Bluetooth: ignored an unreadable last device file (%s)" % path)
		return {}
	var d: Dictionary = parsed
	var addr_v: Variant = d.get("address")
	if not (addr_v is String) or String(addr_v).strip_edges().is_empty():
		push_warning("Bluetooth: ignored a last device file without an address (%s)" % path)
		return {}
	var name_v: Variant = d.get("name", "")
	return {
		"address": String(addr_v).strip_edges(), "name": String(name_v) if name_v is String else ""
	}


## Remember {address, name} as the last device. Returns false (push_warning) on failure.
static func write_last_device(address: String, device_name: String) -> bool:
	var f := FileAccess.open(Paths.last_device_path(), FileAccess.WRITE)
	if f == null:
		push_warning(
			(
				"Bluetooth: could not save the last device (%s)"
				% error_string(FileAccess.get_open_error())
			)
		)
		return false
	f.store_string(JSON.stringify({"address": address, "name": device_name}, "\t") + "\n")
	f.close()
	return true


# --- Backend selection -----------------------------------------------------------------


func _try_next_backend() -> void:
	while not _candidates.is_empty():
		var which: String = _candidates.pop_front()
		var t := _make_transport(which)
		if t == null:
			continue
		# GDBLE can only work when its library is loaded; the bridge's reachability is
		# known only after trying (initialize() reports it through adapter_ready).
		if which == BACKEND_GDBLE and not t.is_available():
			_backend_errors.append("GDBLE not loaded")
			t.free()
			continue
		_use_transport(t, which)
		_backend = Backend.STARTING
		_init_left = INIT_TIMEOUT_S
		_set_status(TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_STARTING"))
		t.initialize()
		return
	_backend = Backend.NONE
	_backend_name = ""
	var key := "BLE_STATUS_NO_ADAPTER" if _adapter_missing else "BLE_STATUS_NO_BACKEND"
	push_warning("Bluetooth: no backend available (%s)" % ", ".join(_backend_errors))
	_set_status(TrainerDevice.STATUS_DISCONNECTED, tr(key))


func _make_transport(which: String) -> BleTransport:
	var made: Variant = null
	if which == BACKEND_GDBLE:
		made = make_gdble.call() if make_gdble.is_valid() else GdbleTransport.new()
	elif which == BACKEND_BRIDGE:
		made = make_bridge.call() if make_bridge.is_valid() else BridgeTransport.new()
	return made as BleTransport if made is BleTransport else null


func _use_transport(t: BleTransport, which: String) -> void:
	_transport = t
	_backend_name = which
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	if t.get_parent() == null:
		add_child(t)
	t.adapter_ready.connect(_on_adapter_ready)
	t.device_found.connect(_on_device_found)
	t.device_connected.connect(_on_device_connected)
	t.device_disconnected.connect(_on_device_disconnected)
	t.operation_failed.connect(_on_operation_failed)


func _drop_transport() -> void:
	var t := _transport
	_transport = null
	_backend_name = ""
	if t == null:
		return
	t.adapter_ready.disconnect(_on_adapter_ready)
	t.device_found.disconnect(_on_device_found)
	t.device_connected.disconnect(_on_device_connected)
	t.device_disconnected.disconnect(_on_device_disconnected)
	t.operation_failed.disconnect(_on_operation_failed)
	# Deferred: the transport may still be inside the call that emitted the signal.
	t.queue_free()


func _on_adapter_ready(ok: bool, error: String) -> void:
	if _backend == Backend.STARTING:
		if ok:
			_backend = Backend.READY
			var queued := _scan_queued
			_scan_queued = -1.0
			if _link == Link.REINIT:
				# connect_to() arrived while the backend was starting.
				_send_connect()
			elif _link == Link.IDLE:
				scan(queued if queued >= 0.0 else _start_scan_seconds())
			return
		push_warning("Bluetooth: %s backend unavailable (%s)" % [_backend_name, error])
		_backend_errors.append("%s: %s" % [_backend_name, error])
		if _backend_name == BACKEND_GDBLE:
			_adapter_missing = true
		_drop_transport()
		_try_next_backend()
		if _backend == Backend.NONE and _link == Link.REINIT:
			# A connect waiting for start-up can't run: no backend (the status says why).
			_link = Link.IDLE
		return
	if ok:
		_backend = Backend.READY
		if _link == Link.REINIT:
			_send_connect()
		elif _link == Link.IDLE and _scan_queued >= 0.0:
			var queued := _scan_queued
			_scan_queued = -1.0
			scan(queued)
		return
	push_warning("Bluetooth: adapter lost (%s)" % error)
	_backend = Backend.LOST
	match _link:
		Link.REINIT, Link.CONNECTING:
			_attempt_failed(error)
		Link.SETUP, Link.READY, Link.CONTROL_LOST, Link.SETUP_FAILED:
			_link_lost()
		Link.IDLE:
			_scanning = false
			_scan_left = 0.0
			_scan_queued = -1.0
			_set_status(TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_NO_ADAPTER"))
		_:
			# WAIT_RETRY: the next attempt initializes the adapter first.
			pass


func _start_scan_seconds() -> float:
	return AUTO_SCAN_S if _auto_connect and not _last.is_empty() else DEFAULT_SCAN_S


## Zero-touch start (BRIEF 3.5): while auto-connect waits for the remembered trainer and no
## trainer is linked, a finished scan window starts the next one. True when it did.
func _auto_rescan() -> bool:
	if not _auto_connect or _last.is_empty() or _link != Link.IDLE or _backend != Backend.READY:
		return false
	scan(AUTO_SCAN_S)
	return true


# --- Scanning --------------------------------------------------------------------------


func _halt_scan() -> void:
	_scan_queued = -1.0
	if not _scanning:
		return
	_scanning = false
	_scan_left = 0.0
	if _transport != null:
		_transport.stop_scan()
		_scan_issued = false


func _on_device_found(info: Dictionary) -> void:
	if not is_trainer(info):
		return
	var addr := String(info.get("address", "")).strip_edges()
	if addr.is_empty():
		return
	var key := addr.to_lower()
	var prev: Variant = _found.get(key)
	_found[key] = info
	var changed := true
	if prev is Dictionary:
		var p: Dictionary = prev
		changed = (
			String(p.get("name", "")) != String(info.get("name", ""))
			or p.get("services", []) != info.get("services", [])
		)
	if changed:
		device_found.emit(info)
	if (
		_auto_connect
		and _link == Link.IDLE
		and not _last.is_empty()
		and _same_address(addr, String(_last["address"]))
	):
		connect_to(addr)


# --- Link state machine ----------------------------------------------------------------


func _begin_attempt() -> void:
	if _transport == null:
		_link = Link.IDLE
		push_warning("Bluetooth: cannot connect (%s)" % _status_detail)
		return
	_attempt_left = CONNECT_TIMEOUT_S
	_set_status(
		TrainerDevice.STATUS_CONNECTING,
		tr("BLE_STATUS_CONNECTING").format({"name": _target_label()})
	)
	if _backend != Backend.READY:
		# Wait for the backend: still starting (its adapter_ready connects), or lost
		# (initialize it again first).
		_link = Link.REINIT
		if _backend != Backend.STARTING:
			_transport.initialize()
		return
	_send_connect()


func _send_connect() -> void:
	_link = Link.CONNECTING
	_attempt_left = CONNECT_TIMEOUT_S
	_transport.connect_device(String(_target["address"]))


func _on_device_connected(address: String) -> void:
	if _target.is_empty() or not _same_address(address, String(_target["address"])):
		return
	if _link != Link.CONNECTING and _link != Link.WAIT_RETRY and _link != Link.REINIT:
		return
	_ensure_client()
	_enter_setup()


func _enter_setup() -> void:
	_link = Link.SETUP
	_setup_left = SETUP_TIMEOUT_S
	_set_status(
		TrainerDevice.STATUS_CONNECTED, tr("BLE_STATUS_SETUP").format({"name": _target_label()})
	)
	_client.begin()


func _on_device_disconnected(address: String, _reason: String) -> void:
	if _target.is_empty():
		return
	if not address.is_empty() and not _same_address(address, String(_target["address"])):
		return
	match _link:
		Link.CONNECTING:
			_attempt_failed("disconnected")
		Link.SETUP, Link.READY, Link.CONTROL_LOST, Link.SETUP_FAILED:
			_link_lost()
		_:
			# IDLE (we asked for it), WAIT_RETRY (already handled), REINIT.
			pass


func _on_operation_failed(op: String, error: String) -> void:
	if op == "connect" and _link == Link.CONNECTING:
		_attempt_failed(error)
	elif op == GdbleTransport.OP_GATT_RESET and _link == Link.READY:
		# Subscriptions are gone: begin() rediscovers and resubscribes. Not after a control
		# loss, where begin() would also take control back (retry_control() does that).
		_enter_setup()


func _link_lost() -> void:
	_schedule_retry("BLE_STATUS_LOST", "")


func _attempt_failed(error: String) -> void:
	_schedule_retry("BLE_STATUS_RETRY", error)


func _schedule_retry(key: String, error: String) -> void:
	var delay := backoff_delay(_attempt)
	_attempt += 1
	_retry_left = delay
	_link = Link.WAIT_RETRY
	_set_status(
		TrainerDevice.STATUS_DISCONNECTED, tr(key).format({"s": int(delay), "error": error})
	)


func _setup_failed(reason: String) -> void:
	var detail := tr("BLE_STATUS_SETUP_FAILED").format({"error": reason})
	if Locks.hw_locked():
		# Read-only by design under the lock: keep the link, never loop on retries.
		_link = Link.SETUP_FAILED
		_set_status(TrainerDevice.STATUS_ERROR, "%s %s" % [detail, tr("BLE_STATUS_HW_LOCKED")])
		return
	_schedule_retry("BLE_STATUS_RETRY", reason)
	if _transport != null:
		_transport.disconnect_device()


# --- FtmsClient ------------------------------------------------------------------------


func _ensure_client() -> void:
	if _client == null:
		var made: Variant = make_client.call() if make_client.is_valid() else FtmsClient.new()
		_client = made as FtmsClient
		_client.process_mode = Node.PROCESS_MODE_ALWAYS
		if _client.get_parent() == null:
			add_child(_client)
		_client.client_ready.connect(_on_client_ready)
		_client.failed.connect(_on_client_failed)
		_client.control_lost.connect(_on_client_control_lost)
	if _client_transport != _transport:
		_client.attach(_transport)
		_client_transport = _transport


func _on_client_ready() -> void:
	if _link != Link.SETUP:
		return
	_link = Link.READY
	_attempt = 0
	var address := String(_target["address"])
	var label := _target_label()
	if write_last_device(address, String(_target.get("name", ""))):
		_last = {"address": address, "name": String(_target.get("name", ""))}
	var again := _ever_ready
	_ever_ready = true
	var old: TrainerDevice = null
	if _device == null or not _same_address(_device_address, address) or _client_released(_device):
		old = _device
		var made: Variant = (
			make_trainer.call(_client, label)
			if make_trainer.is_valid()
			else FtmsTrainer.create(_client, label)
		)
		_device = made as TrainerDevice
		_device.process_mode = Node.PROCESS_MODE_ALWAYS
		if _device.get_parent() == null:
			add_child(_device)
		_device_address = address
		# The old trainer object no longer speaks for the linked trainer (the client is shared).
		_release_device_client(old)
	_set_status(TrainerDevice.STATUS_READY, tr("BLE_STATUS_READY").format({"name": label}))
	trainer_ready.emit(_device)
	if again:
		reconnected.emit(_device)
	if old != null:
		old.queue_free()


func _on_client_failed(reason: String) -> void:
	# SETUP: the 4.4 flow failed. READY or CONTROL_LOST (W4, ftms-ble-1): a control-point write
	# stayed unanswered after its retries, so the link is presumed dead; recover the same way
	# (drop, back off, reconnect, begin() again, then reconnected restores the safe mode).
	if _link == Link.SETUP:
		_setup_failed(reason)
	elif _link == Link.READY or _link == Link.CONTROL_LOST:
		# Not a setup failure: under the hardware lock a ready client is read-only and never
		# writes, so this can't come from the lock; reconnect in every case.
		push_warning("Bluetooth: the trainer stopped answering (%s); reconnecting" % reason)
		_schedule_retry("BLE_STATUS_RETRY", reason)
		if _transport != null:
			_transport.disconnect_device()


func _on_client_control_lost(_detail: String) -> void:
	if _link == Link.SETUP or _link == Link.READY:
		_link = Link.CONTROL_LOST
	var text := tr("BLE_STATUS_CONTROL_HELD")
	_set_status(TrainerDevice.STATUS_CONTROL_LOST, text)
	control_lost.emit(text)


# --- Helpers ---------------------------------------------------------------------------


func _set_status(s: String, detail: String) -> void:
	if s == _status and detail == _status_detail:
		return
	_status = s
	_status_detail = detail
	status_changed.emit(s, detail)


## The trainer object of a link being replaced by another trainer's: unbind it from the shared
## client (SAF-8) so nothing it is still asked to write reaches the next trainer.
func _release_old_device() -> void:
	_release_device_client(_device)


## True for a trainer object that was released from the client by a switch (it can't write).
static func _client_released(d: TrainerDevice) -> bool:
	return d is FtmsTrainer and (d as FtmsTrainer).client() == null


static func _release_device_client(d: TrainerDevice) -> void:
	if d != null and is_instance_valid(d) and d is FtmsTrainer:
		(d as FtmsTrainer).release_client()


func _known_name(address: String) -> String:
	var info: Variant = _found.get(address.to_lower())
	if info is Dictionary and not String(info.get("name", "")).is_empty():
		return String(info["name"])
	if not _last.is_empty() and _same_address(address, String(_last["address"])):
		return String(_last.get("name", ""))
	if not _target.is_empty() and _same_address(address, String(_target["address"])):
		return String(_target.get("name", ""))
	return ""


func _target_label() -> String:
	var n := String(_target.get("name", ""))
	return n if not n.is_empty() else String(_target.get("address", ""))


static func _same_address(a: String, b: String) -> bool:
	return GdbleTransport.same_address(a, b)
