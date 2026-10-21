extends RefCounted
## In-process stand-in for tools/trainer_bridge (TCPServer + WebSocketPeer.accept_stream)
## speaking the bridge's JSON protocol on 127.0.0.1 and an ephemeral port. Tests call
## poll() alongside the transport's poll(). It never touches Bluetooth.

const FTMS := "00001826-0000-1000-8000-00805f9b34fb"

var tcp: TCPServer = TCPServer.new()
var peers: Array[WebSocketPeer] = []
## Every request received, parsed.
var received: Array[Dictionary] = []
## Reply automatically (false: tests answer with reply()).
var auto_reply: bool = true
## ops that get no automatic reply.
var silent_ops: Array[String] = []
var adapter: bool = true
var adapter_error: String = "no Bluetooth adapter"
var connect_error: String = ""
var devices: Array[Dictionary] = []
var services: Array = []
## char uuid -> hex
var read_values: Dictionary = {}
var port: int = 0


func start() -> int:
	var err := tcp.listen(0, "127.0.0.1")
	if err != OK:
		return 0
	port = tcp.get_local_port()
	return port


func url() -> String:
	return "ws://127.0.0.1:%d" % port


func poll() -> void:
	while tcp.is_listening() and tcp.is_connection_available():
		var conn := tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.accept_stream(conn)
		peers.append(ws)
	for ws: WebSocketPeer in peers:
		ws.poll()
		while (
			ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0
		):
			var parsed: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if not (parsed is Dictionary):
				continue
			var msg: Dictionary = parsed
			received.append(msg)
			if auto_reply and not (String(msg.get("op", "")) in silent_ops):
				_answer(ws, msg)


func is_open() -> bool:
	for ws: WebSocketPeer in peers:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
	return false


func ops() -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in received:
		out.append(String(m.get("op", "")))
	return out


func last(op: String) -> Dictionary:
	for i in range(received.size() - 1, -1, -1):
		if String(received[i].get("op", "")) == op:
			return received[i]
	return {}


func send(msg: Dictionary) -> void:
	for ws: WebSocketPeer in peers:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(JSON.stringify(msg))


func reply(id: int, ok: bool, result: Variant = {}, error: String = "") -> void:
	send({"id": id, "ok": ok, "result": result, "error": error})


func stop() -> void:
	for ws: WebSocketPeer in peers:
		ws.close()
		ws.poll()
	peers.clear()
	tcp.stop()


func _answer(_ws: WebSocketPeer, msg: Dictionary) -> void:
	var id := int(msg.get("id", 0))
	match String(msg.get("op", "")):
		"hello":
			reply(id, true, {"name": "wattlands-trainer-bridge", "version": "test", "proto": 1})
		"init":
			reply(id, true, {"adapter": adapter, "error": "" if adapter else adapter_error})
		"scan":
			reply(id, true, {})
			for d: Dictionary in devices:
				var ev := d.duplicate()
				ev["event"] = "device"
				send(ev)
		"stop_scan":
			reply(id, true, {})
		"connect":
			if connect_error.is_empty():
				reply(id, true, {"address": String(msg.get("address", "")), "name": "KICKR CORE"})
			else:
				reply(id, false, null, connect_error)
		"disconnect":
			reply(id, true, {})
			send({"event": "disconnected", "address": "", "reason": "local"})
		"discover":
			reply(id, true, {"services": services})
		"read":
			var chr := String(msg.get("char", ""))
			reply(id, true, {"char": chr, "data": String(read_values.get(chr, ""))})
		"write", "subscribe":
			reply(id, true, {"char": String(msg.get("char", ""))})
		_:
			reply(id, false, null, "unknown op")
