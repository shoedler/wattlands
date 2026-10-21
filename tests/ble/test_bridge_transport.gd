extends GutTest
## BridgeTransport (BRIEF 4.2, P1 backend) against an in-process WebSocket server that
## speaks the trainer bridge's JSON protocol (tests/ble/fake_bridge_server.gd): hello and
## init, scan events, connect, discovery, reads, subscriptions and notifications,
## disconnects, the bridge closing, timeouts on tick(dt), loopback-only URLs and the
## hardware lock on writes. Nothing here touches Bluetooth or leaves 127.0.0.1.

const FakeServer := preload("res://tests/ble/fake_bridge_server.gd")

const FTMS := "00001826-0000-1000-8000-00805f9b34fb"
const FEATURE := "00002acc-0000-1000-8000-00805f9b34fb"
const IBD := "00002ad2-0000-1000-8000-00805f9b34fb"
const CP := "00002ad9-0000-1000-8000-00805f9b34fb"
const ADDR := "C4:9D:A1:00:2B:7E"

var _server: FakeServer = null
var _t: BridgeTransport = null
var _events: Array = []


func before_each() -> void:
	_events = []
	_server = FakeServer.new()
	assert_gt(_server.start(), 0, "fake bridge listening")
	_t = BridgeTransport.new()
	_t.manual_poll = true
	_t.url = _server.url()
	add_child_autofree(_t)
	for sig: String in ["adapter_ready", "device_found", "device_connected", "device_disconnected",
			"services_discovered", "characteristic_read", "characteristic_written",
			"characteristic_notified", "operation_failed"]:
		_t.connect(sig, _recorder(sig))


func after_each() -> void:
	if _server != null:
		_server.stop()
	_server = null
	_t = null


func _recorder(sig: String) -> Callable:
	match sig:
		"device_found", "device_connected", "services_discovered", "characteristic_written":
			return func(a: Variant) -> void: _events.append([sig, a])
		_:
			return func(a: Variant, b: Variant) -> void: _events.append([sig, a, b])


func _named(sig: String) -> Array:
	var out: Array = []
	for e: Array in _events:
		if e[0] == sig:
			out.append(e)
	return out


## Polls both ends until cond() holds (bounded by an iteration count, not the clock).
func _pump_until(cond: Callable, rounds: int = 1500) -> bool:
	for i in rounds:
		_server.poll()
		_t.poll()
		if cond.call():
			return true
		OS.delay_msec(2)
	return false


func _pump(rounds: int = 25) -> void:
	for i in rounds:
		_server.poll()
		_t.poll()
		OS.delay_msec(2)


func _ready_bridge() -> void:
	_t.initialize()
	assert_true(_pump_until(func() -> bool: return _named("adapter_ready").size() > 0), "bridge answered")


func _connected() -> void:
	_ready_bridge()
	_t.connect_device(ADDR)
	assert_true(_pump_until(func() -> bool: return _t.is_link_up()), "link up")
	_events.clear()


# --- startup -----------------------------------------------------------------------------

func test_initialize_says_hello_then_init() -> void:
	assert_false(_t.is_available())
	_ready_bridge()
	assert_eq(_named("adapter_ready"), [["adapter_ready", true, ""]])
	assert_eq(_server.ops(), ["hello", "init"])
	assert_eq(int(_server.received[0]["proto"]), BridgeTransport.PROTO)
	assert_eq(_server.received[0]["client"], "wattlands")
	assert_true(_t.is_available())
	assert_eq(_t.bridge_info()["name"], "wattlands-trainer-bridge")
	assert_eq(_t.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_no_adapter_behind_the_bridge_is_a_warning() -> void:
	_server.adapter = false
	_ready_bridge()
	assert_eq(_named("adapter_ready"), [["adapter_ready", false, "no Bluetooth adapter"]])
	assert_push_warning("no Bluetooth adapter")
	_t.start_scan(5.0)
	assert_eq(_named("operation_failed")[0][1], "scan")


func test_unreachable_bridge_times_out_on_tick() -> void:
	_server.stop()
	_t.initialize()
	_t.tick(BridgeTransport.CONNECT_TIMEOUT_S - 0.1)
	assert_eq(_named("adapter_ready").size(), 0)
	_t.tick(0.2)
	assert_eq(_named("adapter_ready").size(), 1)
	assert_false(_named("adapter_ready")[0][1])
	assert_string_contains(_named("adapter_ready")[0][2], "not reachable")
	assert_push_warning("not reachable")
	assert_false(_t.is_available())


func test_only_loopback_urls() -> void:
	_t.url = "ws://192.168.1.20:8765"
	_t.initialize()
	assert_eq(_named("adapter_ready").size(), 1)
	assert_false(_named("adapter_ready")[0][1])
	assert_string_contains(_named("adapter_ready")[0][2], "127.0.0.1")
	assert_push_warning("127.0.0.1")
	_pump(10)
	assert_eq(_server.received.size(), 0, "nothing was opened")


## W4 (RS-1): a URL whose text before "?" or "\" is 127.0.0.1 but whose real host (after the
## "@", as Godot's URL parser reads it) is elsewhere is refused too.
func test_ambiguous_loopback_urls_are_refused() -> void:
	for u: String in ["ws://127.0.0.1?@192.168.1.20:8765", "ws://127.0.0.1\\@192.168.1.20:8765"]:
		_events.clear()
		_t.url = u
		_t.initialize()
		assert_eq(_named("adapter_ready").size(), 1, u)
		assert_false(_named("adapter_ready")[0][1], u)
		assert_push_warning("127.0.0.1", u)
	_pump(10)
	assert_eq(_server.received.size(), 0, "nothing was opened")


func test_bad_messages_are_ignored_with_a_warning() -> void:
	_ready_bridge()
	_t.handle_message("not json")
	_t.handle_message("[1, 2]")
	_t.handle_message("{\"x\": 1}")
	assert_push_warning_count(3)
	assert_true(_t.is_available())


# --- scanning and connecting ---------------------------------------------------------------

func test_scan_events_become_device_found() -> void:
	_server.devices = [
		{"address": ADDR, "name": "KICKR CORE 2B7E", "rssi": -58, "services": ["00001826-0000-1000-8000-00805F9B34FB"]},
		{"address": "11:22:33:44:55:66", "name": null, "rssi": null, "services": []},
	]
	_ready_bridge()
	_t.start_scan(5.0)
	assert_true(_pump_until(func() -> bool: return _named("device_found").size() == 2))
	assert_eq(float(_server.last("scan")["seconds"]), 5.0)
	assert_eq(_named("device_found")[0][1], {"address": ADDR, "name": "KICKR CORE 2B7E", "rssi": -58, "services": [FTMS]})
	assert_eq(_named("device_found")[1][1]["name"], "")
	_t.stop_scan()
	assert_true(_pump_until(func() -> bool: return _server.ops().has("stop_scan")))


func test_connect_and_disconnect() -> void:
	_ready_bridge()
	_t.connect_device(ADDR)
	assert_true(_pump_until(func() -> bool: return _named("device_connected").size() == 1))
	assert_eq(_server.last("connect")["address"], ADDR)
	assert_eq(_named("device_connected")[0][1], ADDR)
	_t.disconnect_device()
	assert_true(_pump_until(func() -> bool: return _named("device_disconnected").size() == 1))
	assert_eq(_named("device_disconnected")[0], ["device_disconnected", ADDR, "local"])
	assert_false(_t.is_link_up())


func test_connect_while_linked_reports_the_link_again() -> void:
	_connected()
	_t.connect_device(ADDR.to_lower())
	assert_eq(_named("device_connected"), [["device_connected", ADDR]])
	_pump(10)
	var connects := 0
	for op: String in _server.ops():
		if op == "connect":
			connects += 1
	assert_eq(connects, 1, "no second connect request")


func test_disconnect_while_connecting_cancels_the_connect() -> void:
	_server.silent_ops = ["connect", "disconnect"]
	_ready_bridge()
	_t.connect_device(ADDR)
	assert_true(_pump_until(func() -> bool: return _server.ops().has("connect")))
	_t.disconnect_device()
	assert_true(_pump_until(func() -> bool: return _server.ops().has("disconnect")), "cancel sent")
	# The bridge runs requests in order: the connect finishes, then the disconnect releases it.
	_server.reply(int(_server.last("connect")["id"]), true, {"address": ADDR, "name": "KICKR CORE"})
	_server.reply(int(_server.last("disconnect")["id"]), true, {})
	_server.send({"event": "disconnected", "address": ADDR, "reason": "local"})
	assert_true(_pump_until(func() -> bool: return _t.pending_count() == 0))
	_pump(10)
	assert_eq(_named("device_connected").size(), 0, "a cancelled connect stays down")
	assert_eq(_named("device_disconnected").size(), 0)
	assert_eq(_named("operation_failed").size(), 0)
	assert_false(_t.is_link_up())


func test_connect_timeout_asks_the_bridge_to_release_a_late_link() -> void:
	_server.silent_ops = ["connect"]
	_ready_bridge()
	_t.connect_device(ADDR)
	assert_true(_pump_until(func() -> bool: return _server.ops().has("connect")))
	_t.tick(BridgeTransport.CONNECT_REQUEST_TIMEOUT_S + 0.1)
	assert_eq(_named("operation_failed"), [["operation_failed", "connect", "timeout"]])
	assert_true(_pump_until(func() -> bool: return _server.ops().has("disconnect")), "release requested")
	_server.reply(int(_server.last("connect")["id"]), true, {"address": ADDR, "name": "KICKR CORE"})
	_pump(15)
	assert_eq(_named("device_connected").size(), 0, "the late answer is ignored")


func test_connect_error_is_operation_failed() -> void:
	_server.connect_error = "device not found"
	_ready_bridge()
	_t.connect_device(ADDR)
	assert_true(_pump_until(func() -> bool: return _named("operation_failed").size() == 1))
	assert_eq(_named("operation_failed")[0], ["operation_failed", "connect", "device not found"])
	assert_eq(_named("device_connected").size(), 0)


func test_remote_disconnect_event() -> void:
	_connected()
	_server.send({"event": "disconnected", "address": ADDR.to_lower(), "reason": "remote"})
	assert_true(_pump_until(func() -> bool: return _named("device_disconnected").size() == 1))
	assert_eq(_named("device_disconnected")[0], ["device_disconnected", ADDR, "remote"])
	_server.send({"event": "disconnected", "address": ADDR, "reason": "remote"})
	_pump(10)
	assert_eq(_named("device_disconnected").size(), 1, "reported once")


# --- GATT ----------------------------------------------------------------------------------

func test_discover_read_subscribe_notify() -> void:
	_server.services = [{"uuid": "00001826-0000-1000-8000-00805F9B34FB", "characteristics": [
		{"uuid": "2ACC", "properties": ["read"]},
		{"uuid": "2AD2", "properties": ["notify"]},
		{"uuid": "2AD9", "properties": ["write", "indicate"]},
	]}]
	_server.read_values = {FEATURE: "0b40000006e00000"}
	_connected()
	_t.discover_services()
	assert_true(_pump_until(func() -> bool: return _named("services_discovered").size() == 1))
	var svcs: Array = _named("services_discovered")[0][1]
	assert_eq(svcs[0]["uuid"], FTMS)
	assert_eq(svcs[0]["characteristics"][2], {"uuid": CP, "properties": ["indicate", "write"]})
	_t.read_characteristic("1826", "2ACC")
	assert_true(_pump_until(func() -> bool: return _named("characteristic_read").size() == 1))
	assert_eq(_server.last("read")["service"], FTMS)
	assert_eq(_server.last("read")["char"], FEATURE)
	assert_eq(_named("characteristic_read")[0], ["characteristic_read", FEATURE,
		PackedByteArray([0x0b, 0x40, 0x00, 0x00, 0x06, 0xe0, 0x00, 0x00])])
	_t.subscribe_characteristic("0x1826", "0X2AD2")
	assert_true(_pump_until(func() -> bool: return _server.ops().has("subscribe")))
	assert_eq(_server.last("subscribe")["char"], IBD)
	_server.send({"event": "notify", "char": "00002AD2-0000-1000-8000-00805F9B34FB", "data": "4402c409b4006400"})
	assert_true(_pump_until(func() -> bool: return _named("characteristic_notified").size() == 1))
	assert_eq(_named("characteristic_notified")[0], ["characteristic_notified", IBD,
		PackedByteArray([0x44, 0x02, 0xc4, 0x09, 0xb4, 0x00, 0x64, 0x00])])


func test_bad_notification_data_is_dropped() -> void:
	_connected()
	_server.send({"event": "notify", "char": IBD, "data": "zz1"})
	_pump(15)
	assert_eq(_named("characteristic_notified").size(), 0)
	assert_push_warning("bad data")


func test_gatt_calls_need_a_link() -> void:
	_ready_bridge()
	_t.read_characteristic("1826", "2ACC")
	_t.discover_services()
	assert_eq(_named("operation_failed").size(), 2)
	assert_eq(_named("operation_failed")[0][1], "read")
	assert_eq(_named("operation_failed")[1][1], "discover_services")


func test_request_timeout_on_tick() -> void:
	_server.silent_ops = ["read"]
	_connected()
	_t.read_characteristic("1826", "2ACC")
	assert_true(_pump_until(func() -> bool: return _server.ops().has("read")))
	assert_eq(_t.pending_count(), 1)
	_t.tick(BridgeTransport.REQUEST_TIMEOUT_S + 0.1)
	assert_eq(_named("operation_failed"), [["operation_failed", "read", "timeout"]])
	assert_eq(_t.pending_count(), 0)


func test_writes_honour_the_hardware_lock() -> void:
	_connected()
	_t.write_characteristic("1826", "2AD9", PackedByteArray([0x00]), true)
	if Locks.hw_locked():
		_pump(15)
		assert_false(_server.ops().has("write"), "no write reaches the bridge under the lock")
		assert_eq(_named("operation_failed"), [["operation_failed", "write", Locks.HW_MESSAGE]])
		assert_push_warning(Locks.HW_MESSAGE)
	else:
		assert_true(_pump_until(func() -> bool: return _named("characteristic_written").size() == 1))
		assert_eq(_server.last("write")["data"], "00")


func test_write_fields() -> void:
	assert_eq(BridgeTransport.write_fields("1826", "0x2AD9", PackedByteArray([0x05, 0xc8, 0x00]), true), {
		"op": "write", "service": FTMS, "char": CP, "data": "05c800", "with_response": true})


func test_decode_hex() -> void:
	assert_eq(BridgeTransport.decode_hex("0A1b"), PackedByteArray([0x0a, 0x1b]))
	assert_eq(BridgeTransport.decode_hex(""), PackedByteArray())
	assert_null(BridgeTransport.decode_hex("abc"))
	assert_null(BridgeTransport.decode_hex("zz"))


# --- the bridge going away -----------------------------------------------------------------

func test_bridge_closing_drops_the_link_and_initialize_reopens() -> void:
	_connected()
	_server.stop()
	assert_true(_pump_until(func() -> bool: return _named("adapter_ready").size() == 1))
	assert_eq(_named("device_disconnected"), [["device_disconnected", ADDR, "bridge closed"]])
	assert_eq(_named("adapter_ready")[0], ["adapter_ready", false, "bridge closed"])
	assert_push_warning("connection closed")
	assert_false(_t.is_available())
	# The manager's job: initialize() again once the bridge is back.
	_server = FakeServer.new()
	assert_gt(_server.start(), 0)
	_t.url = _server.url()
	_t.initialize()
	assert_true(_pump_until(func() -> bool: return _named("adapter_ready").size() == 2))
	assert_eq(_named("adapter_ready")[1], ["adapter_ready", true, ""])
	assert_true(_t.is_available())
