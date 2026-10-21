class_name BridgeTransport
extends BleTransport
## BleTransport through the Python trainer bridge (BRIEF 4.2, tools/trainer_bridge): a
## WebSocketPeer client to ws://127.0.0.1:8765. Same surface and signals as GdbleTransport.
## Reconnecting to the bridge (and to the trainer) is FtmsConnectionManager's job: when the
## socket closes this transport reports the link down and adapter_ready(false, "bridge
## closed"), and initialize() opens it again.
##
## Protocol (JSON text frames, one object each; tools/trainer_bridge/README.md has the full
## table). Byte payloads are lower-case hex strings.
##   request   {"id": int, "op": String, ...fields}
##   response  {"id": int, "ok": bool, "result": Variant, "error": String}
##   event     {"event": String, ...fields}
## Ops: hello {proto, client} -> {name, version, proto}; init -> {adapter: bool, error};
##   scan {seconds} (then "device" events); stop_scan; connect {address} -> {address, name};
##   disconnect; discover -> {services}; read {service, char} -> {char, data};
##   write {service, char, data, with_response} -> {char}; subscribe {service, char} -> {char}.
## Events: device {address, name, rssi, services}, scan_stopped, notify {char, data},
##   disconnected {address, reason}, adapter {ok, error}.
## initialize() opens the socket (CONNECT_TIMEOUT_S), sends hello, then init; the init
## result becomes adapter_ready(ok, error). "No adapter" and "bridge not reachable" are
## push_warning, never errors.
##
## Only loopback URLs are accepted (the bridge never leaves this machine). Hardware lock
## (BRIEF 1), defence in depth behind FtmsClient: while WATTLANDS_NO_HW_CONTROL=1 the write
## method refuses every write and logs "hardware control locked"; the bridge also refuses
## writes when its own environment carries the lock.
##
## Time: _process(delta) polls the socket and advances the timeouts unless manual_poll is
## set; tests call poll() and tick(dt) themselves.

const DEFAULT_URL := "ws://127.0.0.1:8765"
const PROTO := 1
const CLIENT_NAME := "wattlands"
## Seconds to open the socket and finish hello + init before "bridge not reachable".
const CONNECT_TIMEOUT_S := 3.0
## Per-request reply timeouts (connect covers bleak's own scan-and-connect).
const REQUEST_TIMEOUT_S := 10.0
const CONNECT_REQUEST_TIMEOUT_S := 25.0

enum SocketState { IDLE, OPENING, OPEN, CLOSED }

var url: String = DEFAULT_URL
## Tests: true stops _process from polling; call poll() and tick(dt) directly.
var manual_poll: bool = false

var _ws: WebSocketPeer = null
var _state: SocketState = SocketState.IDLE
var _open_left: float = 0.0
var _hello_done: bool = false
var _bridge_info: Dictionary = {}
var _next_id: int = 1
## id -> {"op": String, "char": String, "left": float}
var _pending: Dictionary = {}
var _initialized: bool = false
var _address: String = ""
var _connecting: bool = false
var _link_up: bool = false
var _disconnect_requested: bool = false
var _services: Array = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if manual_poll:
		return
	poll()
	tick(delta)


func _exit_tree() -> void:
	if _ws != null:
		_ws.close()


## True while the socket to the bridge is open and the hello exchange is done.
func is_available() -> bool:
	return _state == SocketState.OPEN and _hello_done


func initialize() -> void:
	if not Locks.is_loopback_url(url):
		var refused := "the trainer bridge must run on 127.0.0.1 (got %s)" % Locks.url_host(url)
		push_warning("trainer bridge: %s" % refused)
		adapter_ready.emit(false, refused)
		return
	if _state == SocketState.OPEN:
		if _hello_done:
			_request("init", {})
		return
	if _state == SocketState.OPENING:
		return
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail_open("bridge not reachable (%s)" % error_string(err))
		return
	_state = SocketState.OPENING
	_open_left = CONNECT_TIMEOUT_S
	_hello_done = false


func start_scan(seconds: float) -> void:
	if _require_ready("scan"):
		_request("scan", {"seconds": maxf(seconds, 0.0)})


func stop_scan() -> void:
	if is_available():
		_request("stop_scan", {})


func connect_device(address: String) -> void:
	if not _require_ready("connect"):
		return
	if _link_up and GdbleTransport.same_address(address, _address):
		# Already linked: report it again instead of a second connect request.
		device_connected.emit(_address)
		return
	_address = address
	_disconnect_requested = false
	_connecting = true
	_request("connect", {"address": address}, CONNECT_REQUEST_TIMEOUT_S)


## Also cancels a connect still in flight: its late answer is ignored, and the bridge
## (which runs requests in order) releases that link on this disconnect.
func disconnect_device() -> void:
	if not is_available() or (not _link_up and not _connecting):
		return
	_disconnect_requested = true
	_connecting = false
	_request("disconnect", {})


func discover_services() -> void:
	if _require_link("discover_services"):
		_request("discover", {})


func read_characteristic(service_uuid: String, char_uuid: String) -> void:
	if _require_link("read"):
		_request("read", {"service": expand_uuid(service_uuid), "char": expand_uuid(char_uuid)})


## Only FtmsClient calls this (BRIEF 4.6.11). Refused while the hardware lock is set.
func write_characteristic(service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool) -> void:
	if Locks.hw_locked():
		push_warning("%s: write to %s refused" % [Locks.HW_MESSAGE, expand_uuid(char_uuid)])
		operation_failed.emit("write", Locks.HW_MESSAGE)
		return
	if not _require_link("write"):
		return
	var fields := write_fields(service_uuid, char_uuid, data, with_response)
	_request(String(fields["op"]), fields)


func subscribe_characteristic(service_uuid: String, char_uuid: String) -> void:
	if _require_link("subscribe"):
		_request("subscribe", {"service": expand_uuid(service_uuid), "char": expand_uuid(char_uuid)})


# --- Additive API ----------------------------------------------------------------------

## Reads the socket and handles every complete message (call each frame, or let _process).
func poll() -> void:
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if _state == SocketState.OPENING:
		if st == WebSocketPeer.STATE_OPEN:
			_state = SocketState.OPEN
			_request("hello", {"proto": PROTO, "client": CLIENT_NAME}, CONNECT_TIMEOUT_S)
		elif st == WebSocketPeer.STATE_CLOSED:
			_fail_open("bridge not reachable at %s" % url)
			return
	if _state == SocketState.OPEN:
		while _ws != null and _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			if _ws.was_string_packet():
				handle_message(pkt.get_string_from_utf8())
		if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_on_socket_closed()


## Advances the open and request timeouts by dt seconds.
func tick(dt: float) -> void:
	if _state == SocketState.OPENING or (_state == SocketState.OPEN and not _hello_done):
		_open_left -= dt
		if _open_left <= 0.0:
			_fail_open("bridge not reachable (no answer within %d s)" % int(CONNECT_TIMEOUT_S))
			return
	if _pending.is_empty():
		return
	var expired: Array[int] = []
	for id: int in _pending:
		var req: Dictionary = _pending[id]
		req["left"] = float(req["left"]) - dt
		if float(req["left"]) <= 0.0:
			expired.append(id)
	expired.sort()
	for id: int in expired:
		if not _pending.has(id):
			continue
		var req: Dictionary = _pending[id]
		_pending.erase(id)
		_on_failure(String(req["op"]), String(req["char"]), "timeout")


## The bridge's hello result ({name, version, proto}); {} before.
func bridge_info() -> Dictionary:
	return _bridge_info


func device_address() -> String:
	return _address


func is_link_up() -> bool:
	return _link_up


func services() -> Array:
	return _services


## Requests sent and not answered yet.
func pending_count() -> int:
	return _pending.size()


## Closes the socket (no reconnect); the link, if any, is reported down.
func close() -> void:
	if _ws != null:
		_ws.close()
		_ws.poll()
	_on_socket_closed()


## Handles one JSON text message from the bridge (public for tests).
func handle_message(text: String) -> void:
	# JSON.parse_string() logs an engine error on bad input; the instance parse() doesn't.
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not (parsed is Dictionary):
		push_warning("trainer bridge: ignored a message that is not a JSON object")
		return
	var msg: Dictionary = parsed
	if msg.has("event"):
		_handle_event(msg)
	elif msg.has("id"):
		_handle_response(msg)
	else:
		push_warning("trainer bridge: ignored a message with neither id nor event")


## The fields of a write request: {"op": "write", "service", "char", "data" (hex),
## "with_response"}. Pure; the transport sends it only when the hardware lock is off.
static func write_fields(service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool) -> Dictionary:
	return {
		"op": "write",
		"service": expand_uuid(service_uuid),
		"char": expand_uuid(char_uuid),
		"data": data.hex_encode(),
		"with_response": with_response,
	}


## Lower-case hex string -> bytes; null when the text is not even-length hex.
static func decode_hex(text: String) -> Variant:
	var s := text.strip_edges().to_lower()
	if s.length() % 2 != 0:
		return null
	for i in s.length():
		if "0123456789abcdef".find(s[i]) < 0:
			return null
	return s.hex_decode()


# --- Internals -------------------------------------------------------------------------

func _require_ready(op: String) -> bool:
	if not is_available() or not _initialized:
		operation_failed.emit(op, "trainer bridge is not ready")
		return false
	return true


func _require_link(op: String) -> bool:
	if not is_available() or not _link_up:
		operation_failed.emit(op, "not connected")
		return false
	return true


func _request(op: String, fields: Dictionary, timeout_s: float = REQUEST_TIMEOUT_S) -> int:
	if _ws == null or _state != SocketState.OPEN:
		operation_failed.emit(op, "trainer bridge is not connected")
		return 0
	var id := _next_id
	_next_id += 1
	var msg := fields.duplicate()
	msg["id"] = id
	msg["op"] = op
	_pending[id] = {"op": op, "char": String(fields.get("char", "")), "left": timeout_s}
	var err := _ws.send_text(JSON.stringify(msg))
	if err != OK:
		_pending.erase(id)
		_on_failure(op, String(fields.get("char", "")), "send failed (%s)" % error_string(err))
		return 0
	return id


func _handle_response(msg: Dictionary) -> void:
	var id := int(msg.get("id", 0))
	if not _pending.has(id):
		return
	var req: Dictionary = _pending[id]
	_pending.erase(id)
	var op := String(req["op"])
	var ok := bool(msg.get("ok", false))
	var error := String(msg.get("error", "")) if msg.get("error") != null else ""
	var result_v: Variant = msg.get("result", {})
	var result: Dictionary = result_v if result_v is Dictionary else {}
	if not ok:
		_on_failure(op, String(req["char"]), error if not error.is_empty() else "failed")
		return
	match op:
		"hello":
			_hello_done = true
			_bridge_info = result
			_request("init", {}, CONNECT_TIMEOUT_S)
		"init":
			var adapter := bool(result.get("adapter", false))
			_set_adapter(adapter, String(result.get("error", "")) if not adapter else "")
		"connect":
			if not _connecting:
				# Cancelled by disconnect_device(); the queued disconnect releases it.
				return
			if not String(result.get("address", "")).is_empty():
				_address = String(result["address"])
			_link_came_up()
		"discover":
			var list_v: Variant = result.get("services", [])
			_services = GdbleTransport.normalize_services(list_v if list_v is Array else [])
			services_discovered.emit(_services)
		"read":
			var chr := String(result.get("char", req["char"]))
			var bytes: Variant = decode_hex(String(result.get("data", "")))
			if bytes == null:
				_on_failure("read", chr, "bad data from the bridge")
				return
			characteristic_read.emit(expand_uuid(chr), bytes)
		"write":
			characteristic_written.emit(expand_uuid(String(result.get("char", req["char"]))))
		_:
			pass


func _handle_event(msg: Dictionary) -> void:
	match String(msg.get("event", "")):
		"device":
			var info := GdbleTransport.normalize_device_info(msg)
			if not String(info["address"]).is_empty():
				device_found.emit(info)
		"notify":
			var bytes: Variant = decode_hex(String(msg.get("data", "")))
			if bytes == null:
				push_warning("trainer bridge: ignored a notification with bad data")
				return
			characteristic_notified.emit(expand_uuid(String(msg.get("char", ""))), bytes)
		"disconnected":
			var addr := String(msg.get("address", ""))
			if addr.is_empty() or GdbleTransport.same_address(addr, _address):
				_link_went_down(String(msg.get("reason", "")))
		"adapter":
			_set_adapter(bool(msg.get("ok", false)), String(msg.get("error", "")))
		"scan_stopped":
			pass
		_:
			pass


func _set_adapter(ok: bool, error: String) -> void:
	_initialized = ok
	if not ok:
		push_warning("trainer bridge: no Bluetooth adapter (%s)" % error)
	adapter_ready.emit(ok, error)


func _on_failure(op: String, _char_uuid: String, error: String) -> void:
	match op:
		"hello":
			_fail_open("trainer bridge did not start: %s" % error)
		"init":
			if error == "timeout":
				_fail_open("trainer bridge did not answer init")
			else:
				_set_adapter(false, error)
		"connect":
			var was_connecting := _connecting
			_connecting = false
			operation_failed.emit("connect", error)
			if was_connecting and error == "timeout" and is_available():
				# The bridge may still finish that connect: have it release the trainer.
				_disconnect_requested = true
				_request("disconnect", {})
		"discover":
			operation_failed.emit("discover_services", error)
		_:
			operation_failed.emit(op, error)


func _link_came_up() -> void:
	_connecting = false
	if _link_up:
		return
	_link_up = true
	device_connected.emit(_address)


func _link_went_down(reason: String) -> void:
	if not _link_up:
		if _connecting:
			_connecting = false
			operation_failed.emit("connect", "disconnected while connecting")
		return
	_link_up = false
	_services = []
	var why := reason
	if why.is_empty():
		why = "local" if _disconnect_requested else "remote"
	_disconnect_requested = false
	device_disconnected.emit(_address, why)


func _fail_open(reason: String) -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_state = SocketState.CLOSED
	_hello_done = false
	_initialized = false
	_pending.clear()
	if _link_up:
		_link_up = false
		_services = []
		device_disconnected.emit(_address, "bridge closed")
	push_warning("trainer bridge: %s" % reason)
	adapter_ready.emit(false, reason)


func _on_socket_closed() -> void:
	if _state == SocketState.CLOSED or _state == SocketState.IDLE:
		_ws = null
		return
	var was_open := _state == SocketState.OPEN
	var was_ready := _initialized
	_ws = null
	_state = SocketState.CLOSED
	_hello_done = false
	_initialized = false
	var dropped: Array = _pending.values()
	_pending.clear()
	for req: Dictionary in dropped:
		if String(req["op"]) == "connect":
			_connecting = false
			operation_failed.emit("connect", "bridge closed")
	if _link_up:
		_link_up = false
		_services = []
		device_disconnected.emit(_address, "bridge closed")
	if was_open or was_ready:
		push_warning("trainer bridge: connection closed")
		adapter_ready.emit(false, "bridge closed")
