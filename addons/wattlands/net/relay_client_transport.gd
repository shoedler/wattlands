class_name RelayClientTransport
extends Transport
## Base for transports that speak the relay protocol (BRIEF 5.3) as a client:
## RelayTransport (WebSocketPeer), LanTransport (WebSocket to a LAN host) and
## LoopbackTransport (in-process hub). Subclasses provide the "socket" (_socket_open,
## _socket_send_text, _socket_close, poll) and call _on_socket_open(), _handle_text() /
## _handle_envelope() and _on_socket_closed(); this class does hello, create/join, routing
## of relay messages to the Transport signals, error codes and reconnect tokens.
## Owned by net-client.
##
## Error codes while creating or joining (room_not_found, room_full, version_mismatch,
## rate_limited, bad_request) close the socket and emit disconnected(code). While in a room,
## rate_limited and bad_request are not fatal: push_warning plus relay_error(code).
## version_mismatch always ends the connection. host_left emits disconnected("host_left").
## An unexpected close while in a room emits disconnected("dropped") and keeps room_code
## and reconnect_token, so join(room_code, reconnect_token) reclaims the same peer id.

## A non-fatal relay error while in a room ("rate_limited", "bad_request").
signal relay_error(code: String)
## A game message from `from` was dropped because it has another schema version.
signal protocol_mismatch(from: int)
## A pong arrived for a ping this transport sent ("ts" echoed back).
signal pong_received(ts: float)

enum SocketState { CLOSED, OPENING, OPEN }

## P1: host() asks the relay for this code (the host's previous one) if it is free.
var requested_code: String = ""
## The latest relay error code (fatal or not), for logs and UI.
var last_error: String = ""
## From the latest `joined`: the other peers connected in the room (the relay's optional
## joined.peers; W3 NET-1 reconciles a reclaiming host's peer list with it), whether the relay
## sent that list, and whether the join reclaimed a peer id (joined.rejoin).
var joined_peers: Array[int] = []
var joined_peers_known: bool = false
var rejoined: bool = false

var _socket_state: SocketState = SocketState.CLOSED
var _in_room: bool = false
var _pending: Dictionary = {}
var _pending_code: String = ""
var _leaving: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Create a room; `connected` fires with the new room_code.
func host(max_peers: int = 8) -> void:
	var create := {"t": "create", "max": clampi(max_peers, 1, NetMessages.MAX_PEERS)}
	var want := RoomCode.normalize(requested_code)
	if want != "":
		create["code"] = want
	_pending = create
	_pending_code = ""
	_begin()


## Join a room by code (dashes, spaces, case and O/I/L confusions are tolerated); pass a
## saved token to reclaim a dropped peer id.
func join(code: String, token: String = "") -> void:
	var c := RoomCode.normalize(code)
	if c == "":
		push_warning('Transport: "%s" is not a room code' % code)
		last_error = "room_not_found"
		disconnected.emit("room_not_found")
		return
	_pending = {"t": "join", "code": c, "token": token if token != "" else null}
	_pending_code = c
	_begin()


## Send to a peer id, the host id, or Wl.ALL_PEERS (0: everyone except the sender).
## Non-hosts may only send to the host.
func send(to: int, data: Dictionary) -> void:
	if not _can_send(to):
		return
	_send_msg_text(to, Protocol.encode(data))


## Send an already encoded game message (Protocol.encode(data)); NetSession uses it to
## avoid encoding twice. Same rules as send().
func send_encoded(to: int, d_text: String) -> void:
	if not _can_send(to):
		return
	_send_msg_text(to, d_text)


## Leave the room explicitly (the relay sends host_left when the host leaves). Also cancels a
## create or join still in flight: the relay gets a leave (harmless outside a room) and the
## socket closes, so a late created/joined never lands.
func leave() -> void:
	var was_pending := not _pending.is_empty()
	_pending = {}
	var was_open := _in_room
	if _socket_state == SocketState.OPEN and (_in_room or was_pending):
		_send_envelope({"t": "leave"})
	_leaving = true
	_in_room = false
	local_peer = 0
	reconnect_token = ""
	room_code = ""
	if _socket_state != SocketState.CLOSED:
		_socket_state = SocketState.CLOSED
		_socket_close()
	if was_open:
		disconnected.emit("closed")


## Send a relay ping (RelayTransport sends one every 15 s by itself).
func send_ping(ts: float) -> void:
	if _socket_state == SocketState.OPEN:
		_send_envelope({"t": "ping", "ts": ts})


func in_room() -> bool:
	return _in_room


# --- for subclasses ------------------------------------------------------------------------


## Open the socket; call _on_socket_open() once it is ready (or _on_socket_closed()).
func _socket_open() -> void:
	pass


func _socket_send_text(_text: String) -> void:
	pass


func _socket_close() -> void:
	pass


## A `msg` envelope with an encoded `d`; LoopbackTransport overrides it (fast path).
func _send_msg_text(to: int, d_text: String) -> void:
	_socket_send_text('{"t":"msg","to":%d,"d":%s}' % [to, d_text])


func _on_socket_open() -> void:
	_socket_state = SocketState.OPEN
	_send_envelope({"t": "hello", "proto": Wl.PROTO, "game": Wl.RELAY_GAME, "build": Wl.BUILD})
	_send_pending()


## The socket closed. `reason_if_connecting` is used when it never got into a room.
func _on_socket_closed(reason_if_connecting: String = "error") -> void:
	var was_in_room := _in_room
	var was_pending := not _pending.is_empty()
	_socket_state = SocketState.CLOSED
	_in_room = false
	local_peer = 0
	_pending = {}
	if _leaving:
		return
	if was_in_room:
		last_error = "dropped"
		disconnected.emit("dropped")
	elif was_pending:
		last_error = reason_if_connecting
		disconnected.emit(reason_if_connecting)


## One text frame from the relay.
func _handle_text(text: String) -> void:
	var env := Protocol.decode(text)
	if env.is_empty():
		if Protocol.last_error == "version_mismatch":
			var raw: Variant = Protocol.parse_json(text)
			var from := 0
			if raw is Dictionary:
				from = int((raw as Dictionary).get("from", 0))
			protocol_mismatch.emit(from)
		return
	_handle_envelope(env)


## One decoded relay envelope ("msg" carries a decoded game message in "d").
func _handle_envelope(env: Dictionary) -> void:
	var t := str(env["t"])
	if (t == "created" or t == "joined") and (_pending.is_empty() or _leaving):
		# A late answer to a create or join that was cancelled.
		return
	match t:
		"created":
			room_code = str(env["code"])
			local_peer = int(env["peer"])
			host_peer = local_peer
			reconnect_token = str(env["token"])
			_in_room = true
			_pending = {}
			connected.emit()
		"joined":
			room_code = _pending_code
			local_peer = int(env["peer"])
			host_peer = int(env["host"])
			reconnect_token = str(env["token"])
			joined_peers.clear()
			joined_peers_known = env.get("peers") is Array
			if joined_peers_known:
				for p: Variant in env["peers"]:
					if p is int or p is float:
						joined_peers.append(int(p))
			rejoined = bool(env.get("rejoin", false))
			_in_room = true
			_pending = {}
			connected.emit()
		"error":
			_on_relay_error(str(env["code"]))
		"msg":
			if _in_room:
				message.emit(int(env.get("from", 0)), env["d"])
		"peer_joined":
			peer_joined.emit(int(env["peer"]))
		"peer_left":
			last_peer_left_reason = str(env.get("reason", "dropped"))
			peer_left.emit(int(env["peer"]))
		"host_left":
			_in_room = false
			local_peer = 0
			reconnect_token = ""
			_leaving = true
			if _socket_state != SocketState.CLOSED:
				_socket_state = SocketState.CLOSED
				_socket_close()
			last_error = "host_left"
			disconnected.emit("host_left")
		"pong":
			pong_received.emit(float(env["ts"]))
		_:
			pass


func _send_envelope(env: Dictionary) -> void:
	_socket_send_text(Protocol.encode(env))


# --- internals ---------------------------------------------------------------------------


func _begin() -> void:
	_leaving = false
	if _in_room:
		# Switching rooms: leave the current one first.
		_send_envelope({"t": "leave"})
		_in_room = false
		local_peer = 0
	match _socket_state:
		SocketState.OPEN:
			_send_pending()
		SocketState.CLOSED:
			_socket_state = SocketState.OPENING
			_socket_open()
		_:
			pass


func _send_pending() -> void:
	if _pending.is_empty() or _socket_state != SocketState.OPEN:
		return
	_send_envelope(_pending)


func _can_send(to: int) -> bool:
	if not _in_room:
		push_warning("Transport: not in a room; message to %d dropped" % to)
		return false
	if local_peer != host_peer and to != host_peer:
		push_warning("Transport: non-hosts may only send to the host (to %d dropped)" % to)
		return false
	return true


func _on_relay_error(code: String) -> void:
	last_error = code
	if _in_room and code != "version_mismatch":
		push_warning('Transport: relay error "%s"' % code)
		relay_error.emit(code)
		return
	_pending = {}
	_in_room = false
	local_peer = 0
	_leaving = true
	if _socket_state != SocketState.CLOSED:
		_socket_state = SocketState.CLOSED
		_socket_close()
	disconnected.emit(code)
