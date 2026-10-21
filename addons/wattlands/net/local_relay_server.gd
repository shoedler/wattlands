class_name LocalRelayServer
extends Node
## A relay (BRIEF 5.3) served by this Godot process on a local WebSocket server
## (TCPServer + WebSocketPeer) with RelayRooms semantics. LanTransport (P1) hosts LAN rooms
## with it, and the RelayTransport tests use it as an in-process relay. Owned by
## net-client. All I/O happens in poll(); runs with PROCESS_MODE_ALWAYS.
##
## Codes and tokens come from Crypto random bytes. Time for RelayRooms (token expiry,
## idle timeout, rate limits) is the wall clock unless `time_func` is set (tests).

const HANDSHAKE_TIMEOUT_S := 10.0
const BUFFER_BYTES := 1 << 20
## Sockets the relay closes (version mismatch, idle) stay open this long first, so the
## error frame is read before the close.
const LINGER_MS := 250

var rooms: RelayRooms = RelayRooms.new()
## The listening port (the OS picks one when started with port 0).
var port: int = 0
## Seconds-returning clock (tests); the wall clock when invalid.
var time_func: Callable = Callable()
## Connections accepted so far.
var accepted: int = 0

var _tcp: TCPServer = null
# conn -> {"ws": WebSocketPeer, "open": bool, "since": float}
var _peers: Dictionary = {}
var _closing: Array[WebSocketPeer] = []
# [WebSocketPeer, close-at msec]
var _lingering: Array = []
var _next_conn: int = 1
var _last_t: float = -1.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rooms.secure_random = true


## Listen on `p_port` (0 = any free port) at `bind_address` ("*" = every interface,
## "127.0.0.1" = this machine only). OK or the TCPServer error.
func start(p_port: int = 0, bind_address: String = "*") -> Error:
	stop()
	_tcp = TCPServer.new()
	var err := _tcp.listen(p_port, bind_address)
	if err != OK:
		push_warning(
			"LocalRelayServer: can't listen on %s:%d (error %d)" % [bind_address, p_port, err]
		)
		_tcp = null
		return err
	port = _tcp.get_local_port()
	_last_t = _now()
	return OK


func is_listening() -> bool:
	return _tcp != null and _tcp.is_listening()


## "ws://127.0.0.1:<port>/v1" for clients on this machine.
func local_url() -> String:
	return "ws://127.0.0.1:%d/v1" % port


func stop() -> void:
	for conn: Variant in _peers.keys():
		var ws: WebSocketPeer = (_peers[conn] as Dictionary)["ws"]
		ws.close(1001, "server stopped")
	_peers.clear()
	_closing.clear()
	_lingering.clear()
	if _tcp != null:
		_tcp.stop()
		_tcp = null


func poll() -> void:
	if _tcp == null:
		return
	for i in range(_lingering.size() - 1, -1, -1):
		var lw: WebSocketPeer = _lingering[i][0]
		lw.poll()
		while lw.get_available_packet_count() > 0:
			lw.get_packet()
		if lw.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_lingering.remove_at(i)
		elif Time.get_ticks_msec() >= int(_lingering[i][1]):
			lw.close(1000, "closed by relay")
			_closing.append(lw)
			_lingering.remove_at(i)
	for i in range(_closing.size() - 1, -1, -1):
		_closing[i].poll()
		if _closing[i].get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_closing.remove_at(i)
	var now := _now()
	if _last_t >= 0.0 and now > _last_t:
		rooms.advance(now - _last_t)
	_last_t = now
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		if stream == null:
			break
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = BUFFER_BYTES
		ws.outbound_buffer_size = BUFFER_BYTES
		ws.max_queued_packets = 4096
		if ws.accept_stream(stream) != OK:
			continue
		_peers[_next_conn] = {"ws": ws, "open": false, "since": now}
		_next_conn += 1
		accepted += 1
	for conn: Variant in _peers.keys():
		if not _peers.has(conn):
			continue
		var p: Dictionary = _peers[conn]
		var ws: WebSocketPeer = p["ws"]
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN and not p["open"]:
			p["open"] = true
			rooms.open(int(conn))
		# Frames that arrived before a close are read first (a leave followed by the close).
		if p["open"]:
			while ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet()
				if ws.was_string_packet():
					rooms.receive(int(conn), pkt.get_string_from_utf8())
				else:
					rooms.receive(int(conn), "")
		match st:
			WebSocketPeer.STATE_CONNECTING:
				if now - float(p["since"]) > HANDSHAKE_TIMEOUT_S:
					ws.close()
					_closing.append(ws)
					_peers.erase(conn)
			WebSocketPeer.STATE_CLOSED:
				if p["open"]:
					rooms.closed(int(conn))
				_peers.erase(conn)
			_:
				pass
	_flush()


## Connections currently open.
func connection_count() -> int:
	return _peers.size()


## Close a connection's socket without a leave (tests: a dropped client).
func drop_connection(conn: int) -> void:
	if not _peers.has(conn):
		return
	var ws: WebSocketPeer = (_peers[conn] as Dictionary)["ws"]
	ws.close(1001, "dropped")
	_closing.append(ws)
	rooms.closed(conn)
	_peers.erase(conn)
	_flush()


func _flush() -> void:
	for pair: Variant in rooms.take_output():
		var conn := int(pair[0])
		if not _peers.has(conn):
			continue
		var ws: WebSocketPeer = (_peers[conn] as Dictionary)["ws"]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(Protocol.encode(pair[1]))
	for conn in rooms.take_closes():
		if _peers.has(conn):
			var ws: WebSocketPeer = (_peers[conn] as Dictionary)["ws"]
			_lingering.append([ws, Time.get_ticks_msec() + LINGER_MS])
			rooms.closed(conn)
			_peers.erase(conn)


func _now() -> float:
	if time_func.is_valid():
		return float(time_func.call())
	return Time.get_ticks_msec() / 1000.0


func _exit_tree() -> void:
	stop()
