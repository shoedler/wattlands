class_name HrSensorManager
extends Node
## Finds, connects and keeps one Bluetooth heart rate sensor (Heart Rate service 0x180D,
## measurement 0x2A37) for the local rider: chest straps and watches broadcasting heart rate
## (Garmin "Broadcast Heart Rate", Polar, Wahoo TICKR) use the same standard profile.
## WlTrainerService owns one; Settings > Sensors drives it.
##
## Subscribe only: the manager discovers the services, subscribes to 0x2A37 and parses every
## notification (HeartRateParser). It never writes to the sensor, so the hardware lock
## (WATTLANDS_NO_HW_CONTROL) does not apply to it.
##
## Transport: make_transport() is asked for a BleTransport whenever the manager needs one and
## has none (WlTrainerService hands out a transport on the trainer's backend: a GdbleTransport
## sharing the trainer transport's BluetoothManager, or a second BridgeTransport). It may
## return null (no backend yet, a mock trainer): the manager asks again every
## TRANSPORT_RETRY_S while it has something to do. A transport whose adapter goes away is
## dropped and asked for again the same way.
##
## Flow: scan(s) lists sensors (advertised 0x180D, or a heart-rate-like name, is_hr_sensor);
## connect_to(address, name) -> connect_device -> discover_services -> subscribe 0x2A37 ->
## the first measurement notification -> STATUS_READY; the sensor is saved as {address, name}
## in Paths.last_hr_sensor_path(). A subscription the transport acknowledges (the optional
## `subscribed(char_uuid)` signal of GdbleTransport and BridgeTransport) is only logged: ready
## means heart rate flows.
## Recovery: no notification for NOTIFY_TIMEOUT_S after subscribing (or while ready), or a GATT
## reset (operation_failed "gatt_reset", e.g. services changed after Windows bonded the sensor),
## discovers and subscribes again on the same link, once per link. A second miss, a failed
## discovery or subscription (also a refused Windows pairing), a link loss or a failed attempt
## reconnects with backoff_delay(n) = 1, 2, 4, 8, 15, 15, ... s, so a sensor that asks Windows
## to pair connects once the pairing is allowed. Every status change is logged once (print).
## start(true) scans in AUTO_SCAN_S windows for the remembered sensor and connects when it is
## seen; without a remembered sensor it stays idle until scan(). forget() disconnects and
## deletes the remembered sensor.
##
## current_bpm() is the latest heart rate, or 0 when there is none: not ready, no notification
## for STALE_S, a zero reading, or a sensor that reports contact detection without contact.
##
## Time: every timer advances in tick(dt); _process(delta) calls it unless manual_clock is
## set (tests drive tick() themselves). Runs with PROCESS_MODE_ALWAYS.

## {"address", "name", "rssi", "services"} of a heart rate sensor seen by the current scan.
signal device_found(info: Dictionary)
## TrainerDevice.STATUS_* (disconnected, scanning, connecting, ready) plus a detail text.
signal status_changed(status: String, detail: String)
## Every parsed measurement: current_bpm() after it (0 without contact).
signal heart_rate(bpm: int)

const HR_SERVICE_UUID := "180d"
const HR_MEASUREMENT_UUID := "2a37"
## Lower-case name fragments of common heart rate sensors and watches that broadcast.
const NAME_HINTS: Array[String] = [
	"hrm",
	"heart",
	"polar",
	"tickr",
	"rhythm",
	"whoop",
	"coospo",
	"forerunner",
	"fenix",
	"venu",
	"epix",
	"vivoactive",
	"instinct",
]
const BACKOFF_MAX_S := 15.0
const CONNECT_TIMEOUT_S := 30.0
## Service discovery must answer within this.
const SETUP_TIMEOUT_S := 15.0
## Seconds without a measurement notification, after subscribing or while ready, before the
## manager subscribes again (once per link) and then reconnects.
const NOTIFY_TIMEOUT_S := 10.0
const DEFAULT_SCAN_S := 10.0
const AUTO_SCAN_S := 30.0
## Seconds without a measurement after which current_bpm() is 0.
const STALE_S := 5.0
## How often a missing transport is asked for again.
const TRANSPORT_RETRY_S := 3.0

enum Link { IDLE, WAIT_BACKEND, CONNECTING, SETUP, READY, WAIT_RETRY }
enum Backend { NONE, STARTING, READY }

const _EPS := 1e-6

## Tests: true stops _process from ticking; call tick(dt) directly.
var manual_clock: bool = false
## () -> BleTransport or null (see the class doc).
var make_transport: Callable = Callable()

var _transport: BleTransport = null
var _backend: Backend = Backend.NONE
var _transport_retry_left: float = 0.0
var _started: bool = false
var _auto_connect: bool = false
var _last: Dictionary = {}
var _link: Link = Link.IDLE
var _target: Dictionary = {}
var _attempt: int = 0
var _retry_left: float = 0.0
var _attempt_left: float = 0.0
var _setup_left: float = 0.0
## SETUP: the subscription was sent; the deadline is now the first notification.
var _subscribe_sent: bool = false
## This link's one same-link re-subscription was used.
var _resubscribed: bool = false
var _disconnect_requested: bool = false
var _scanning: bool = false
var _scan_left: float = 0.0
var _scan_queued: float = -1.0
var _found: Dictionary = {}
var _status: String = TrainerDevice.STATUS_DISCONNECTED
var _status_detail: String = ""
var _t: float = 0.0
var _bpm: int = 0
var _bpm_t: float = -INF
var _contact_supported: bool = false
var _contact: bool = false
var _warned_unavailable: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not manual_clock:
		tick(delta)


## Start; with auto_connect, look for the remembered sensor and connect when it is seen.
func start(auto_connect: bool = true) -> void:
	_started = true
	_auto_connect = auto_connect
	_last = read_last_sensor()
	if _auto_connect and not _last.is_empty() and _link == Link.IDLE:
		scan(AUTO_SCAN_S)


## Use this transport now (tests; make_transport is the usual way).
func set_transport(t: BleTransport) -> void:
	if t == _transport:
		return
	_drop_transport()
	if t != null:
		_use_transport(t)


func scan(seconds: float = DEFAULT_SCAN_S) -> void:
	_started = true
	if _backend != Backend.READY:
		_scan_queued = seconds
		_ensure_transport()
		return
	_found.clear()
	_scanning = true
	_scan_left = maxf(seconds, 0.0)
	if _link == Link.IDLE:
		_set_status(TrainerDevice.STATUS_SCANNING, tr("BLE_HR_STATUS_SCANNING"))
	_transport.start_scan(seconds)


## Also ends auto-connect's search (start(true) resumes it).
func stop_scan() -> void:
	_auto_connect = false
	var was := _scanning
	_halt_scan()
	if was and _link == Link.IDLE and _status == TrainerDevice.STATUS_SCANNING:
		_set_status(TrainerDevice.STATUS_DISCONNECTED, "")


func connect_to(address: String, sensor_name: String = "") -> void:
	var addr := address.strip_edges()
	if addr.is_empty():
		push_error("HrSensorManager.connect_to: empty address")
		return
	_started = true
	_halt_scan()
	var same := not _target.is_empty() and _same_address(addr, String(_target["address"]))
	if same and _link != Link.IDLE and _link != Link.WAIT_RETRY:
		return
	if not same and _link != Link.IDLE and _transport != null:
		_disconnect_requested = true
		_transport.disconnect_device()
	var label := sensor_name if sensor_name != "" else _known_name(addr)
	_target = {"address": addr, "name": label}
	_attempt = 0
	_begin_attempt()


## Drop the link and stop reconnecting; the sensor stays remembered.
func disconnect_sensor() -> void:
	_auto_connect = false
	var had := _link != Link.IDLE
	_link = Link.IDLE
	_attempt = 0
	_retry_left = 0.0
	_clear_bpm()
	if had and _transport != null:
		_disconnect_requested = true
		_transport.disconnect_device()
	_set_status(TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_DISCONNECTED"))


## Disconnect and forget the remembered sensor.
func forget() -> void:
	disconnect_sensor()
	_target = {}
	_last = {}
	var path := Paths.last_hr_sensor_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## The latest heart rate in bpm, 0 when none (see the class doc).
func current_bpm() -> int:
	if _link != Link.READY or _bpm <= 0 or _t - _bpm_t > STALE_S + _EPS:
		return 0
	if _contact_supported and not _contact:
		return 0
	return _bpm


## True when the sensor reports contact detection and has no skin contact.
func no_contact() -> bool:
	return _link == Link.READY and _contact_supported and not _contact


func status() -> String:
	return _status


func status_detail() -> String:
	return _status_detail


func is_ready() -> bool:
	return _link == Link.READY


func is_scanning() -> bool:
	return _scanning


## {address, name} of the sensor being connected or kept, or {} when none.
func sensor() -> Dictionary:
	return {} if _link == Link.IDLE else _target.duplicate()


## The remembered sensor {address, name}, or {}.
func last_sensor() -> Dictionary:
	return read_last_sensor()


## Sensors seen by the current scan, sorted by address.
func found_devices() -> Array:
	var keys: Array = _found.keys()
	keys.sort()
	var out: Array = []
	for k: Variant in keys:
		out.append(_found[k])
	return out


func transport() -> BleTransport:
	return _transport


func tick(dt: float) -> void:
	_t += dt
	if _transport == null and _started and _wants_transport():
		_transport_retry_left -= dt
		if _transport_retry_left <= _EPS:
			_ensure_transport()
	if _scanning:
		_scan_left -= dt
		if _scan_left <= _EPS:
			_scanning = false
			if _auto_connect and not _last.is_empty() and _link == Link.IDLE:
				scan(AUTO_SCAN_S)
			elif _link == Link.IDLE and _status == TrainerDevice.STATUS_SCANNING:
				var detail := tr("BLE_HR_STATUS_NONE_FOUND") if _found.is_empty() else ""
				_set_status(TrainerDevice.STATUS_DISCONNECTED, detail)
	match _link:
		Link.WAIT_RETRY:
			_retry_left -= dt
			if _retry_left <= _EPS:
				_begin_attempt()
		Link.CONNECTING:
			_attempt_left -= dt
			if _attempt_left <= _EPS:
				_attempt_failed("timeout")
		Link.SETUP:
			_setup_left -= dt
			if _setup_left <= _EPS:
				if not _subscribe_sent:
					_drop_link("setup timed out")
				elif _resubscribed:
					_drop_link("no heart rate")
				else:
					_resubscribe("no heart rate")
		Link.READY:
			if _t - _bpm_t > NOTIFY_TIMEOUT_S + _EPS:
				if _resubscribed:
					_drop_link("heart rate stopped")
				else:
					_resubscribe("heart rate stopped")
		_:
			pass


static func backoff_delay(attempt: int) -> float:
	if attempt <= 0:
		return 1.0
	if attempt >= 4:
		return BACKOFF_MAX_S
	return minf(BACKOFF_MAX_S, pow(2.0, float(attempt)))


## The scan filter: advertises the Heart Rate service 0x180D, or its name looks like a heart
## rate sensor (NAME_HINTS, or "HR" as a word).
static func is_hr_sensor(info: Dictionary) -> bool:
	var services: Variant = info.get("services", [])
	if services is Array or services is PackedStringArray:
		for u: Variant in services:
			if BleTransport.same_uuid(String(u), HR_SERVICE_UUID):
				return true
	var name_v: Variant = info.get("name", "")
	if not (name_v is String):
		return false
	var n := String(name_v).to_lower()
	for h in NAME_HINTS:
		if n.contains(h):
			return true
	for word in n.replace("-", " ").replace("_", " ").split(" ", false):
		if word == "hr":
			return true
	return false


## The remembered sensor {address, name} from Paths.last_hr_sensor_path(), or {}.
static func read_last_sensor() -> Dictionary:
	var path := Paths.last_hr_sensor_path()
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("Bluetooth: ignored an unreadable heart rate sensor file (%s)" % path)
		return {}
	var addr_v: Variant = (parsed as Dictionary).get("address")
	if not (addr_v is String) or String(addr_v).strip_edges().is_empty():
		return {}
	var name_v: Variant = (parsed as Dictionary).get("name", "")
	return {
		"address": String(addr_v).strip_edges(), "name": String(name_v) if name_v is String else ""
	}


static func write_last_sensor(address: String, sensor_name: String) -> bool:
	var f := FileAccess.open(Paths.last_hr_sensor_path(), FileAccess.WRITE)
	if f == null:
		push_warning(
			(
				"Bluetooth: could not save the heart rate sensor (%s)"
				% error_string(FileAccess.get_open_error())
			)
		)
		return false
	f.store_string(JSON.stringify({"address": address, "name": sensor_name}, "\t") + "\n")
	f.close()
	return true


# --- Transport ---------------------------------------------------------------------------


func _wants_transport() -> bool:
	return (
		_scan_queued >= 0.0
		or _link == Link.WAIT_BACKEND
		or (_auto_connect and not _last.is_empty())
	)


func _ensure_transport() -> void:
	if _transport != null:
		return
	var made: Variant = make_transport.call() if make_transport.is_valid() else null
	if not (made is BleTransport):
		_transport_retry_left = TRANSPORT_RETRY_S
		if _link == Link.IDLE:
			_set_status(TrainerDevice.STATUS_DISCONNECTED, tr("BLE_HR_STATUS_UNAVAILABLE"))
		return
	_use_transport(made as BleTransport)


func _use_transport(t: BleTransport) -> void:
	_transport = t
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	if t.get_parent() == null:
		add_child(t)
	t.adapter_ready.connect(_on_adapter_ready)
	t.device_found.connect(_on_device_found)
	t.device_connected.connect(_on_device_connected)
	t.device_disconnected.connect(_on_device_disconnected)
	t.services_discovered.connect(_on_services_discovered)
	t.characteristic_notified.connect(_on_notified)
	t.operation_failed.connect(_on_operation_failed)
	if t.has_signal(&"subscribed"):
		t.connect(&"subscribed", _on_subscribed)
	_backend = Backend.STARTING
	t.initialize()


func _drop_transport() -> void:
	var t := _transport
	_transport = null
	_backend = Backend.NONE
	_transport_retry_left = TRANSPORT_RETRY_S
	if t == null or not is_instance_valid(t):
		return
	for pair: Array in [
		[t.adapter_ready, _on_adapter_ready],
		[t.device_found, _on_device_found],
		[t.device_connected, _on_device_connected],
		[t.device_disconnected, _on_device_disconnected],
		[t.services_discovered, _on_services_discovered],
		[t.characteristic_notified, _on_notified],
		[t.operation_failed, _on_operation_failed],
	]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	if t.has_signal(&"subscribed") and t.is_connected(&"subscribed", _on_subscribed):
		t.disconnect(&"subscribed", _on_subscribed)
	if t.get_parent() == self:
		t.queue_free()


func _on_adapter_ready(ok: bool, error: String) -> void:
	if not ok:
		# Out of the tree means the app is quitting: nothing to report.
		if not _warned_unavailable and is_inside_tree():
			_warned_unavailable = true
			push_warning("Bluetooth: heart rate sensor backend unavailable (%s)" % error)
		_scanning = false
		_drop_transport.call_deferred()
		_backend = Backend.NONE
		match _link:
			Link.CONNECTING, Link.SETUP, Link.READY:
				_link_lost(error)
			Link.IDLE:
				_set_status(TrainerDevice.STATUS_DISCONNECTED, tr("BLE_HR_STATUS_UNAVAILABLE"))
			_:
				pass
		return
	_backend = Backend.READY
	_warned_unavailable = false
	if _link == Link.WAIT_BACKEND:
		_begin_attempt()
	elif _link == Link.IDLE:
		if _scan_queued >= 0.0:
			var s := _scan_queued
			_scan_queued = -1.0
			scan(s)
		elif _auto_connect and not _last.is_empty():
			scan(AUTO_SCAN_S)


# --- Scanning ------------------------------------------------------------------------------


func _halt_scan() -> void:
	_scan_queued = -1.0
	if not _scanning:
		return
	_scanning = false
	_scan_left = 0.0
	if _transport != null:
		_transport.stop_scan()


func _on_device_found(info: Dictionary) -> void:
	if not is_hr_sensor(info):
		return
	var addr := String(info.get("address", "")).strip_edges()
	if addr.is_empty():
		return
	var key := addr.to_lower()
	var is_new := not _found.has(key)
	_found[key] = info
	if is_new:
		device_found.emit(info)
	if (
		_auto_connect
		and _link == Link.IDLE
		and not _last.is_empty()
		and _same_address(addr, String(_last["address"]))
	):
		var n := String(info.get("name", ""))
		connect_to(addr, n if n != "" else String(_last.get("name", "")))


# --- Link ----------------------------------------------------------------------------------


func _begin_attempt() -> void:
	if _target.is_empty():
		_link = Link.IDLE
		return
	if _backend != Backend.READY:
		_link = Link.WAIT_BACKEND
		_set_status(TrainerDevice.STATUS_CONNECTING, _fmt("BLE_STATUS_CONNECTING"))
		_ensure_transport()
		return
	_link = Link.CONNECTING
	_attempt_left = CONNECT_TIMEOUT_S
	_disconnect_requested = false
	_set_status(TrainerDevice.STATUS_CONNECTING, _fmt("BLE_STATUS_CONNECTING"))
	_transport.connect_device(String(_target["address"]))


func _on_device_connected(address: String) -> void:
	if _link != Link.CONNECTING or not _same_address(address, String(_target["address"])):
		return
	_resubscribed = false
	_begin_setup()


## Discover, then subscribe, on the current link; ready waits for the first notification.
func _begin_setup() -> void:
	_link = Link.SETUP
	_setup_left = SETUP_TIMEOUT_S
	_subscribe_sent = false
	_set_status(TrainerDevice.STATUS_CONNECTING, _fmt("BLE_HR_STATUS_WAITING"))
	_transport.discover_services()


## The link is up but no heart rate flows (or the GATT state was reset): discover and
## subscribe again on the same link, once per link.
func _resubscribe(why: String) -> void:
	print("Heart rate sensor: %s, subscribing again" % why)
	_resubscribed = true
	_clear_bpm()
	_begin_setup()


## Give the link up and reconnect with backoff.
func _drop_link(error: String) -> void:
	if _transport != null:
		_disconnect_requested = true
		_transport.disconnect_device()
	_link_lost(error)


func _on_services_discovered(services: Array) -> void:
	if _link != Link.SETUP or _subscribe_sent:
		return
	if not _has_measurement(services):
		_link = Link.IDLE
		_disconnect_requested = true
		_transport.disconnect_device()
		_set_status(TrainerDevice.STATUS_DISCONNECTED, tr("BLE_HR_STATUS_NOT_HR"))
		return
	_subscribe_sent = true
	_setup_left = NOTIFY_TIMEOUT_S
	_transport.subscribe_characteristic(HR_SERVICE_UUID, HR_MEASUREMENT_UUID)


func _on_subscribed(char_uuid: String) -> void:
	if _link == Link.SETUP and BleTransport.same_uuid(char_uuid, HR_MEASUREMENT_UUID):
		print("Heart rate sensor: subscribed, waiting for the first measurement")


## The first measurement on this link: heart rate flows.
func _enter_ready() -> void:
	_link = Link.READY
	_attempt = 0
	_resubscribed = false
	var addr := String(_target["address"])
	var n := String(_target.get("name", ""))
	if _last.get("address", "") != addr or _last.get("name", "") != n:
		write_last_sensor(addr, n)
		_last = {"address": addr, "name": n}
	_set_status(TrainerDevice.STATUS_READY, _fmt("BLE_STATUS_READY"))


func _on_notified(char_uuid: String, data: PackedByteArray) -> void:
	var waiting := _link == Link.SETUP and _subscribe_sent
	if not (waiting or _link == Link.READY):
		return
	if not BleTransport.same_uuid(char_uuid, HR_MEASUREMENT_UUID):
		return
	var m := HeartRateParser.parse(data)
	if not bool(m["ok"]):
		return
	if waiting:
		_enter_ready()
	_bpm = int(m["bpm"])
	_bpm_t = _t
	_contact_supported = bool(m["contact_supported"])
	_contact = bool(m["contact"])
	heart_rate.emit(current_bpm())


func _on_device_disconnected(address: String, _reason: String) -> void:
	if _target.is_empty() or not _same_address(address, String(_target["address"])):
		return
	if _disconnect_requested or _link == Link.IDLE:
		_disconnect_requested = false
		return
	_link_lost(tr("BLE_STATUS_DISCONNECTED"))


func _on_operation_failed(op: String, error: String) -> void:
	match _link:
		Link.CONNECTING:
			if op == "connect":
				_attempt_failed(error)
		Link.SETUP, Link.READY:
			# The manager-wide "bluetooth" and "scan" errors are not this link's.
			if op == "scan" or op == "bluetooth":
				return
			if op == GdbleTransport.OP_GATT_RESET:
				if _resubscribed:
					_drop_link(error)
				else:
					_resubscribe("GATT reset (%s)" % error)
			elif _link == Link.SETUP or op == "subscribe" or op == "notification":
				# Discovery or the subscription failed (on Windows also a refused pairing).
				_drop_link("%s: %s" % [op, error])
		_:
			pass


func _link_lost(error: String) -> void:
	_clear_bpm()
	_schedule_retry(error)


func _attempt_failed(error: String) -> void:
	if _link == Link.CONNECTING and _transport != null:
		_disconnect_requested = true
		_transport.disconnect_device()
	_schedule_retry(error)


func _schedule_retry(error: String) -> void:
	_link = Link.WAIT_RETRY
	_retry_left = backoff_delay(_attempt)
	_attempt += 1
	_set_status(
		TrainerDevice.STATUS_CONNECTING,
		tr("BLE_STATUS_RETRY").replace("{error}", error).replace(
			"{s}", str(int(ceilf(_retry_left)))
		)
	)


func _clear_bpm() -> void:
	var had := current_bpm() > 0
	_bpm = 0
	_bpm_t = -INF
	_contact_supported = false
	_contact = false
	if had:
		heart_rate.emit(0)


func _set_status(s: String, detail: String) -> void:
	if s == _status and detail == _status_detail:
		return
	_status = s
	_status_detail = detail
	print("Heart rate sensor: %s%s" % [s, "" if detail.is_empty() else " (%s)" % detail])
	status_changed.emit(s, detail)


func _fmt(key: String) -> String:
	var n := String(_target.get("name", ""))
	return tr(key).replace("{name}", n if n != "" else String(_target.get("address", "")))


func _known_name(address: String) -> String:
	var info: Variant = _found.get(address.to_lower())
	if info is Dictionary:
		return String((info as Dictionary).get("name", ""))
	if not _last.is_empty() and _same_address(address, String(_last["address"])):
		return String(_last.get("name", ""))
	return ""


static func _has_measurement(services: Array) -> bool:
	for svc: Variant in services:
		if not (svc is Dictionary):
			continue
		if not BleTransport.same_uuid(String((svc as Dictionary).get("uuid", "")), HR_SERVICE_UUID):
			continue
		for chr: Variant in (svc as Dictionary).get("characteristics", []):
			if (
				chr is Dictionary
				and BleTransport.same_uuid(
					String((chr as Dictionary).get("uuid", "")), HR_MEASUREMENT_UUID
				)
			):
				return true
	return false


static func _same_address(a: String, b: String) -> bool:
	return a.strip_edges().to_lower() == b.strip_edges().to_lower()
