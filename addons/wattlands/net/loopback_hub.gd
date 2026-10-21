class_name LoopbackHub
extends RefCounted
## The in-process "relay" behind LoopbackTransport (BRIEF 5.4): RelayRooms semantics
## (codes, peer ids from 1, to: 0 broadcast excluding the sender, non-hosts only to the
## host, peer_left/host_left, reconnect tokens) with every frame passed as JSON text into
## the receiving transport's inbox, delivered in order when that transport polls.
## Deterministic: codes and tokens come from a seeded generator and time only moves
## through advance(dt). Rate limits and the idle timeout are off by default (turn them on
## with enforce_limits(true) and drive advance()). Owned by net-client.

var rooms: RelayRooms = RelayRooms.new()
## Frames delivered so far (control and msg), for tests and budgets.
var frames_delivered: int = 0
## Errors sent to transports by code ("rate_limited": n, ...), for tests and budgets.
var error_counts: Dictionary = {}

var _transports: Dictionary = {}
var _next_conn: int = 1


func _init(seed: int = 1) -> void:
	rooms.rng = SeededRng.make(seed)
	rooms.enforce_rate_limits = false
	rooms.enforce_idle_timeout = false


## Turn the relay's rate limit (60/s, burst 120) and 60 s idle timeout on or off.
func enforce_limits(on: bool) -> void:
	rooms.enforce_rate_limits = on
	rooms.enforce_idle_timeout = on


## Advance hub time (token expiry, held host rooms, rate-limit refill, idle timeout).
func advance(dt: float) -> void:
	rooms.advance(dt)
	_flush()


## Open a "socket" for `t`; returns its connection id.
func attach(t: LoopbackTransport) -> int:
	var conn := _next_conn
	_next_conn += 1
	_transports[conn] = weakref(t)
	rooms.open(conn)
	_flush()
	return conn


## A control frame (hello, create, join, leave, ping) from a connection.
func send_text(conn: int, text: String) -> void:
	rooms.receive(conn, text)
	_flush()


## A game message from a connection, `d_text` being its encoded `d`.
func send_msg(conn: int, to: int, d_text: String) -> void:
	var size := d_text.to_utf8_buffer().size() + ('{"t":"msg","to":%d,"d":}' % to).length()
	var recipients := rooms.route(conn, to, size)
	var from := rooms.from_peer(conn)
	for rc in recipients:
		var t := _transport(rc)
		if t != null:
			t._enqueue_msg(from, d_text)
			frames_delivered += 1
	_flush()


## Fault injection: drop the socket of `peer` in room `code`, as if that peer's
## LoopbackTransport.simulate_drop() was called. False if no such live peer.
func drop_peer(code: String, peer: int) -> bool:
	var conn := int(rooms.room_peers(code).get(peer, -1))
	if conn < 0:
		return false
	var t := _transport(conn)
	if t == null:
		return false
	t.simulate_drop()
	return true


## The connection's socket closed (a drop; an explicit leave was sent before).
func detach(conn: int) -> void:
	rooms.closed(conn)
	_transports.erase(conn)
	_flush()


func _transport(conn: int) -> LoopbackTransport:
	if not _transports.has(conn):
		return null
	var w: WeakRef = _transports[conn]
	var obj: Variant = w.get_ref()
	if obj == null or not is_instance_valid(obj):
		_transports.erase(conn)
		return null
	return obj as LoopbackTransport


func _flush() -> void:
	for pair: Variant in rooms.take_output():
		var conn := int(pair[0])
		var env: Dictionary = pair[1]
		if str(env.get("t", "")) == "error":
			var code := str(env.get("code", ""))
			error_counts[code] = int(error_counts.get(code, 0)) + 1
		var t := _transport(conn)
		if t != null:
			t._enqueue_text(Protocol.encode(env))
			frames_delivered += 1
	for conn in rooms.take_closes():
		var t := _transport(conn)
		rooms.closed(conn)
		_transports.erase(conn)
		if t != null:
			t._enqueue_close()
