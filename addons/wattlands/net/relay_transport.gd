class_name RelayTransport
extends RelayClientTransport
## The internet transport (BRIEF 5.3, 5.4): a WebSocketPeer to server/relay (ws:// or
## wss:// URL from --relay=<url>, else Settings.relay_url(), else ws://localhost:8787/v1).
## Sends hello when the socket opens, then the pending create/join; pings every 15 s;
## maps relay error codes to disconnected(reason); an unexpected close in a room emits
## disconnected("dropped") and keeps room_code and reconnect_token, so
## join(room_code, reconnect_token) reclaims the same peer id (NetSession does this).
## All I/O happens in poll(); runs with PROCESS_MODE_ALWAYS. Owned by net-client.
##
## Timers (connect timeout, ping, silence) use the wall clock, because this is the
## real-time network driver; tests inject `time_func`. Nothing on the sim path reads it.

const DEFAULT_URL := "ws://localhost:8787/v1"
const CONNECT_TIMEOUT_S := 10.0
const PING_INTERVAL_S := float(NetMessages.CLIENT_PING_S)
## No frame at all from the relay for this long (pongs included) counts as a drop.
const SILENCE_TIMEOUT_S := 45.0
const BUFFER_BYTES := 1 << 20
## After a leave the socket stays open this long (wall clock) before it is closed, so the
## relay reads the leave frame first (Godot drops frames that arrive with the close).
const LINGER_MS := 250

## ws:// or wss:// URL of the relay's /v1 endpoint ("" = default_url() when opening).
var url: String = ""
## TLS options for wss:// (null = TLSOptions.client(), which verifies certificates).
var tls_options: TLSOptions = null
## Seconds-returning clock for timers (tests); the wall clock when invalid.
var time_func: Callable = Callable()
## Round trip of the latest ping, seconds (-1 before the first pong).
var last_rtt_s: float = -1.0

var _ws: WebSocketPeer = null
var _closing: Array[WebSocketPeer] = []
# [WebSocketPeer, close-at msec] sockets waiting to close after a leave.
var _lingering: Array = []
var _opened_at: float = 0.0
var _last_ping_at: float = 0.0
var _last_rx_at: float = 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pong_received.connect(_on_pong)


## The relay URL: --relay=<url>, else the Settings autoload's relay_url(), else the
## local default. `context` is any node in the tree (for the autoload lookup).
static func default_url(context: Node = null) -> String:
	var flag := CmdLine.get_str("relay", "")
	if flag != "":
		return flag
	if context != null and context.is_inside_tree():
		var s := context.get_node_or_null("/root/Settings")
		if s != null and s.has_method("relay_url"):
			var u := str(s.call("relay_url"))
			if u != "":
				return u
	return DEFAULT_URL


static func is_valid_url(u: String) -> bool:
	return u.begins_with("ws://") or u.begins_with("wss://")


func poll() -> void:
	for i in range(_lingering.size() - 1, -1, -1):
		var lw: WebSocketPeer = _lingering[i][0]
		lw.poll()
		while lw.get_available_packet_count() > 0:
			lw.get_packet()
		if lw.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_lingering.remove_at(i)
		elif Time.get_ticks_msec() >= int(_lingering[i][1]):
			lw.close(1000, "leave")
			_closing.append(lw)
			_lingering.remove_at(i)
	for i in range(_closing.size() - 1, -1, -1):
		var c := _closing[i]
		c.poll()
		if c.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_closing.remove_at(i)
	if _ws == null:
		return
	_ws.poll()
	var now := _now()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and _socket_state == SocketState.OPENING:
		_last_rx_at = now
		_last_ping_at = now
		_on_socket_open()
	# Frames that arrived before a close are handled first (an error or host_left, then
	# the close).
	if st != WebSocketPeer.STATE_CONNECTING:
		while _ws != null and _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			_last_rx_at = now
			if _ws.was_string_packet():
				_handle_text(pkt.get_string_from_utf8())
	if _ws == null:
		return
	match st:
		WebSocketPeer.STATE_CONNECTING:
			if now - _opened_at > CONNECT_TIMEOUT_S:
				_drop_socket()
				_on_socket_closed("timeout")
		WebSocketPeer.STATE_OPEN:
			if now - _last_ping_at >= PING_INTERVAL_S:
				_last_ping_at = now
				send_ping(roundf(now * 1000.0))
			if now - _last_rx_at > SILENCE_TIMEOUT_S:
				push_warning("RelayTransport: no frame from the relay for %.0f s; reconnecting" % SILENCE_TIMEOUT_S)
				_drop_socket()
				_on_socket_closed("timeout")
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			_ws = null
			_on_socket_closed("error")


# --- RelayClientTransport socket layer ------------------------------------------------------

func _socket_open() -> void:
	if url == "":
		url = default_url(self)
	if not is_valid_url(url):
		push_warning("RelayTransport: \"%s\" is not a ws:// or wss:// URL" % url)
		_on_socket_closed("error")
		return
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = BUFFER_BYTES
	_ws.outbound_buffer_size = BUFFER_BYTES
	_ws.max_queued_packets = 4096
	var tls: TLSOptions = null
	if url.begins_with("wss://"):
		tls = tls_options if tls_options != null else TLSOptions.client()
	var err := _ws.connect_to_url(url, tls)
	_opened_at = _now()
	if err != OK:
		push_warning("RelayTransport: can't connect to %s (error %d)" % [url, err])
		_ws = null
		_on_socket_closed("error")


func _socket_send_text(text: String) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var err := _ws.send_text(text)
	if err != OK:
		push_warning("RelayTransport: send failed (error %d)" % err)


func _socket_close() -> void:
	if _ws == null:
		return
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_lingering.append([_ws, Time.get_ticks_msec() + LINGER_MS])
	else:
		_ws.close(1000, "leave")
		_closing.append(_ws)
	_ws = null


func _drop_socket() -> void:
	if _ws == null:
		return
	_ws.close(1001, "timeout")
	_closing.append(_ws)
	_ws = null


func _on_pong(ts: float) -> void:
	last_rtt_s = maxf(_now() - ts / 1000.0, 0.0)


func _now() -> float:
	if time_func.is_valid():
		return float(time_func.call())
	return Time.get_ticks_msec() / 1000.0
