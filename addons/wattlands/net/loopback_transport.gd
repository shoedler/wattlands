class_name LoopbackTransport
extends RelayClientTransport
## In-process transport for tests and headless multi-peer simulations (BRIEF 5.4, P0).
## Owned by net-client; public API frozen after W0. Transports created from one
## LoopbackHub share rooms that behave like the relay (codes, peer ids from 1, to: 0
## broadcast excluding the sender, non-hosts send only to the host, peer_left/host_left,
## reconnect tokens). Messages go through JSON.stringify/parse_string so tests see the
## same float/int behaviour as the network; delivery happens in poll(), in order.
## Optional fault injection: drop(peer), latency_ticks.
##
## It speaks the relay protocol (RelayClientTransport) to a LoopbackHub (RelayRooms);
## game messages travel as their encoded JSON text and are decoded with Protocol.decode()
## by the receiver, exactly like RelayTransport. Every signal fires inside poll().

## Fault injection: frames wait this many of the receiver's polls before delivery
## (order is kept).
var latency_ticks: int = 0

var _hub: LoopbackHub = null
var _conn: int = 0
# Entries: [due_poll, kind, ...]; kind "text" (control frame), "msg" (from, d_text),
# "close" (socket closed by the hub), "drop" (simulate_drop).
var _inbox: Array = []
var _polls: int = 0


## A new hub; create one transport per simulated peer with hub_transport(hub).
static func create_hub() -> RefCounted:
	return LoopbackHub.new()


static func hub_transport(hub: RefCounted) -> LoopbackTransport:
	var t := LoopbackTransport.new()
	t._hub = hub as LoopbackHub
	if t._hub == null:
		push_error("LoopbackTransport.hub_transport: not a LoopbackHub (use create_hub())")
	return t


## Simulate this peer's socket dropping (the hub sends peer_left with reason "dropped").
func simulate_drop() -> void:
	if _conn == 0 or _hub == null:
		return
	var was_in_room := _in_room
	var conn := _conn
	_conn = 0
	_socket_state = SocketState.CLOSED
	_in_room = false
	local_peer = 0
	_pending = {}
	_hub.detach(conn)
	if was_in_room and not _leaving:
		_inbox.append([_polls + latency_ticks, "drop"])


## A freed transport is a dropped socket (a restarted or killed client).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _conn != 0 and _hub != null:
		var conn := _conn
		_conn = 0
		_hub.detach(conn)


## The hub this transport talks to.
func hub() -> LoopbackHub:
	return _hub


## Frames waiting for this transport's next poll().
func pending_frames() -> int:
	return _inbox.size()


## Pump delivery: every due frame, in order.
func poll() -> void:
	_polls += 1
	while not _inbox.is_empty():
		var e: Array = _inbox[0]
		if int(e[0]) > _polls:
			break
		_inbox.pop_front()
		match str(e[1]):
			"text":
				_handle_text(str(e[2]))
			"msg":
				_deliver_msg(int(e[2]), str(e[3]))
			"close":
				_on_socket_closed("error")
			"drop":
				last_error = "dropped"
				disconnected.emit("dropped")


# --- RelayClientTransport socket layer ------------------------------------------------------

func _socket_open() -> void:
	if _hub == null:
		push_error("LoopbackTransport: no hub (create it with hub_transport(hub))")
		_inbox.append([_polls, "close"])
		return
	_conn = _hub.attach(self)
	_on_socket_open()


func _socket_send_text(text: String) -> void:
	if _conn != 0 and _hub != null:
		_hub.send_text(_conn, text)


func _send_msg_text(to: int, d_text: String) -> void:
	if _conn != 0 and _hub != null:
		_hub.send_msg(_conn, to, d_text)


func _socket_close() -> void:
	if _conn != 0 and _hub != null:
		var conn := _conn
		_conn = 0
		_hub.detach(conn)


# --- called by the hub ------------------------------------------------------------------------

func _enqueue_text(text: String) -> void:
	_inbox.append([_polls + 1 + latency_ticks, "text", text])


func _enqueue_msg(from: int, d_text: String) -> void:
	_inbox.append([_polls + 1 + latency_ticks, "msg", from, d_text])


func _enqueue_close() -> void:
	_conn = 0
	_inbox.append([_polls + 1 + latency_ticks, "close"])


func _deliver_msg(from: int, d_text: String) -> void:
	if not _in_room:
		return
	var d := Protocol.decode(d_text)
	if d.is_empty():
		if Protocol.last_error == "version_mismatch":
			protocol_mismatch.emit(from)
		return
	message.emit(from, d)
