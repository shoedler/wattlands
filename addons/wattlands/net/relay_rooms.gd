class_name RelayRooms
extends RefCounted
## The relay's room semantics (BRIEF 5.3) without sockets: hello and version check, room
## codes, peer ids from 1, create/join/leave, reconnect tokens (one per peer, kept while the
## peer is in the room, valid 120 s after a drop, same peer id), host drops held for 120 s, `to: 0` broadcast excluding the sender, non-hosts only to the host,
## 16 KB messages, 60 msgs/s per connection (burst 120), 60 s idle timeout and the 4 h room
## lifetime. It never looks inside `d`.
##
## Shared by LoopbackHub (tests and in-process simulations) and LocalRelayServer (LAN play
## and the RelayTransport tests). Connections are ints chosen by the owner. Feed it with
## open()/receive()/route()/closed()/advance() and drain take_output() ([conn, envelope]
## pairs, in order) and take_closes() (connections the owner must close). Time only moves
## through advance(dt), so runs are deterministic. Owned by net-client.

const HOST_PEER := Wl.HOST_PEER

## Seeded generator for codes and tokens (deterministic hubs); see secure_random.
var rng: RandomNumberGenerator = SeededRng.make(1)
## Use Crypto random bytes for tokens and codes (LAN servers) instead of `rng`.
var secure_random: bool = false
var enforce_rate_limits: bool = true
var enforce_idle_timeout: bool = true
var token_ttl_s: float = float(NetMessages.RECONNECT_TOKEN_S)
var idle_timeout_s: float = float(NetMessages.IDLE_TIMEOUT_S)
var room_lifetime_s: float = float(NetMessages.ROOM_LIFETIME_S)
var max_message_bytes: int = NetMessages.MAX_MESSAGE_BYTES
var max_peers: int = NetMessages.MAX_PEERS
var now_s: float = 0.0

# conn -> {hello: bool, code: String, peer: int, last_rx: float, bucket: float, bucket_t: float}
var _conns: Dictionary = {}
# code -> {code, max, created, next_peer, peers: {peer: conn or -1}, dropped_at: {peer: t},
#          tokens: {token: peer}}
var _rooms: Dictionary = {}
var _out: Array = []
var _closes: Array[int] = []
var _crypto: Crypto = null


func open(conn: int) -> void:
	_conns[conn] = {
		"hello": false,
		"code": "",
		"peer": 0,
		"last_rx": now_s,
		"bucket": float(NetMessages.BURST_MSGS),
		"bucket_t": now_s
	}


func is_open(conn: int) -> bool:
	return _conns.has(conn)


## One text frame from a connection.
func receive(conn: int, text: String) -> void:
	if not _conns.has(conn):
		return
	var c: Dictionary = _conns[conn]
	c["last_rx"] = now_s
	if not _take_token(c):
		_error(conn, "rate_limited")
		return
	if text.to_utf8_buffer().size() > max_message_bytes:
		_error(conn, "bad_request")
		return
	var parsed: Variant = Protocol.parse_json(text)
	if not parsed is Dictionary:
		_error(conn, "bad_request")
		return
	var msg: Dictionary = parsed
	if Protocol.check_envelope(msg) != "":
		_error(conn, "bad_request")
		return
	match str(msg["t"]):
		"hello":
			_on_hello(conn, c, msg)
		"create":
			_on_create(conn, c, msg)
		"join":
			_on_join(conn, c, msg)
		"msg":
			var tv: Variant = msg.get("to", Wl.ALL_PEERS)
			var to := int(tv) if (tv is int or tv is float) else -1
			var r := _route(conn, c, to)
			for rc: Variant in r:
				_out.append([int(rc), {"t": "msg", "from": c["peer"], "d": msg["d"]}])
		"leave":
			_on_leave(conn, c)
		"ping":
			_out.append([conn, {"t": "pong", "ts": msg["ts"]}])
		_:
			_error(conn, "bad_request")


## Fast path for in-process owners that keep `d` as text: rate, size and routing checks for
## one `msg` of `size_bytes` (the whole envelope) to `to`. Returns the recipient
## connections; errors are queued for the sender. The sender's peer id is from_peer(conn).
func route(conn: int, to: int, size_bytes: int) -> Array[int]:
	var none: Array[int] = []
	if not _conns.has(conn):
		return none
	var c: Dictionary = _conns[conn]
	c["last_rx"] = now_s
	if not _take_token(c):
		_error(conn, "rate_limited")
		return none
	if size_bytes > max_message_bytes:
		_error(conn, "bad_request")
		return none
	return _route(conn, c, to)


## The peer id a connection holds in its room (0 when not in a room).
func from_peer(conn: int) -> int:
	if not _conns.has(conn):
		return 0
	return int(_conns[conn]["peer"])


## The connection's socket is gone (a drop, not an explicit leave).
func closed(conn: int) -> void:
	if not _conns.has(conn):
		return
	var c: Dictionary = _conns[conn]
	_conns.erase(conn)
	var code: String = c["code"]
	if code == "" or not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	var peer: int = c["peer"]
	var peers: Dictionary = room["peers"]
	if int(peers.get(peer, -1)) != conn:
		return
	peers[peer] = -1
	(room["dropped_at"] as Dictionary)[peer] = now_s
	_to_room(room, {"t": "peer_left", "peer": peer, "reason": "dropped"}, peer)


## Advance relay time: idle timeouts, token expiry, held host rooms, room lifetime.
func advance(dt: float) -> void:
	now_s += maxf(dt, 0.0)
	if enforce_idle_timeout:
		for conn: Variant in _conns.keys():
			var c: Dictionary = _conns[conn]
			if now_s - float(c["last_rx"]) > idle_timeout_s:
				_closes.append(int(conn))
				closed(int(conn))
	for code: Variant in _rooms.keys():
		if not _rooms.has(code):
			continue
		var room: Dictionary = _rooms[code]
		if now_s - float(room["created"]) > room_lifetime_s:
			_close_room(room)
			continue
		var dropped: Dictionary = room["dropped_at"]
		for peer: Variant in dropped.keys():
			if now_s - float(dropped[peer]) <= token_ttl_s:
				continue
			if int(peer) == HOST_PEER:
				_close_room(room)
				break
			_forget_peer(room, int(peer))
		if (
			_rooms.has(code)
			and _live_count(room) == 0
			and (room["dropped_at"] as Dictionary).is_empty()
		):
			_rooms.erase(code)


## Queued [conn, envelope Dictionary] pairs, in order; clears the queue.
func take_output() -> Array:
	var o := _out
	_out = []
	return o


## Connections the owner must close (idle, version mismatch); clears the list.
func take_closes() -> Array[int]:
	var c := _closes
	_closes = []
	return c


func has_room(code: String) -> bool:
	return _rooms.has(RoomCode.normalize(code))


func room_codes() -> Array:
	return _rooms.keys()


## {peer: conn} of a room (conn -1 for a dropped, held peer); {} if no such room.
func room_peers(code: String) -> Dictionary:
	var c := RoomCode.normalize(code)
	if not _rooms.has(c):
		return {}
	return (_rooms[c]["peers"] as Dictionary).duplicate()


# --- handlers ----------------------------------------------------------------------------


func _on_hello(conn: int, c: Dictionary, msg: Dictionary) -> void:
	if int(msg["proto"]) != Wl.PROTO:
		_error(conn, "version_mismatch")
		_closes.append(conn)
		return
	if str(msg["game"]) != Wl.RELAY_GAME:
		_error(conn, "bad_request")
		_closes.append(conn)
		return
	c["hello"] = true


func _on_create(conn: int, c: Dictionary, msg: Dictionary) -> void:
	if not c["hello"] or c["code"] != "":
		_error(conn, "bad_request")
		return
	var max_n := clampi(int(msg["max"]), 1, max_peers)
	var code := ""
	var wanted := RoomCode.normalize(str(msg.get("code", ""))) if msg.get("code") is String else ""
	if wanted != "" and not _rooms.has(wanted):
		code = wanted
	else:
		code = _new_code()
	var room := {
		"code": code,
		"max": max_n,
		"created": now_s,
		"next_peer": HOST_PEER + 1,
		"peers": {},
		"dropped_at": {},
		"tokens": {}
	}
	_rooms[code] = room
	(room["peers"] as Dictionary)[HOST_PEER] = conn
	var token := _new_token(room, HOST_PEER)
	c["code"] = code
	c["peer"] = HOST_PEER
	_out.append([conn, {"t": "created", "code": code, "peer": HOST_PEER, "token": token}])


func _on_join(conn: int, c: Dictionary, msg: Dictionary) -> void:
	if not c["hello"] or c["code"] != "":
		_error(conn, "bad_request")
		return
	var code := RoomCode.normalize(str(msg["code"]))
	if code == "" or not _rooms.has(code):
		_error(conn, "room_not_found")
		return
	var room: Dictionary = _rooms[code]
	var peers: Dictionary = room["peers"]
	var tokens: Dictionary = room["tokens"]
	var token: Variant = msg.get("token")
	var peer := 0
	var peer_token := ""
	if token is String and tokens.has(token):
		# A peer keeps its token while it is in the room, so a rejoin whose answer is lost
		# (a second drop mid-handshake) can still come back with the token it has.
		peer = int(tokens[token])
		peer_token = token
		var old := int(peers.get(peer, -1))
		if old >= 0 and old != conn and _conns.has(old):
			# The old socket is still open (a half-open drop): it is superseded.
			(_conns[old] as Dictionary)["code"] = ""
			(_conns[old] as Dictionary)["peer"] = 0
			_closes.append(old)
		(room["dropped_at"] as Dictionary).erase(peer)
	else:
		if peers.size() >= int(room["max"]):
			_error(conn, "room_full")
			return
		peer = int(room["next_peer"])
		room["next_peer"] = peer + 1
		peer_token = _new_token(room, peer)
	var rejoin := token is String and tokens.has(token)
	peers[peer] = conn
	c["code"] = code
	c["peer"] = peer
	# As server/relay: joined.peers lists the other connected peers (a reclaiming host uses it
	# to learn who left or came while it was away) and joined.rejoin marks a reclaimed id.
	var others: Array = []
	for p: Variant in peers.keys():
		if int(p) != peer and int(peers[p]) >= 0:
			others.append(int(p))
	others.sort()
	_out.append(
		[
			conn,
			{
				"t": "joined",
				"peer": peer,
				"host": HOST_PEER,
				"token": peer_token,
				"rejoin": rejoin,
				"peers": others
			}
		]
	)
	_to_room(room, {"t": "peer_joined", "peer": peer}, peer)


func _on_leave(conn: int, c: Dictionary) -> void:
	var code: String = c["code"]
	if code == "" or not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	var peer: int = c["peer"]
	c["code"] = ""
	c["peer"] = 0
	if peer == HOST_PEER:
		(room["peers"] as Dictionary).erase(HOST_PEER)
		_close_room(room)
		return
	_forget_peer(room, peer)
	_to_room(room, {"t": "peer_left", "peer": peer, "reason": "left"}, peer)


func _route(conn: int, c: Dictionary, to: int) -> Array[int]:
	var out: Array[int] = []
	var code: String = c["code"]
	if code == "" or not _rooms.has(code):
		_error(conn, "bad_request")
		return out
	var room: Dictionary = _rooms[code]
	var from: int = c["peer"]
	if from != HOST_PEER and to != HOST_PEER:
		# Non-hosts may only send to the host.
		_error(conn, "bad_request")
		return out
	var peers: Dictionary = room["peers"]
	if to == Wl.ALL_PEERS:
		for p: Variant in peers.keys():
			var pc := int(peers[p])
			if int(p) != from and pc >= 0:
				out.append(pc)
	elif to != from and int(peers.get(to, -1)) >= 0:
		out.append(int(peers[to]))
	return out


# --- helpers -----------------------------------------------------------------------------


func _to_room(room: Dictionary, env: Dictionary, except_peer: int) -> void:
	var peers: Dictionary = room["peers"]
	for p: Variant in peers.keys():
		var pc := int(peers[p])
		if int(p) != except_peer and pc >= 0:
			_out.append([pc, env.duplicate()])


func _close_room(room: Dictionary) -> void:
	var peers: Dictionary = room["peers"]
	for p: Variant in peers.keys():
		var pc := int(peers[p])
		if pc >= 0 and _conns.has(pc):
			_out.append([pc, {"t": "host_left"}])
			(_conns[pc] as Dictionary)["code"] = ""
			(_conns[pc] as Dictionary)["peer"] = 0
	_rooms.erase(room["code"])


func _forget_peer(room: Dictionary, peer: int) -> void:
	(room["peers"] as Dictionary).erase(peer)
	(room["dropped_at"] as Dictionary).erase(peer)
	var tokens: Dictionary = room["tokens"]
	for t: Variant in tokens.keys():
		if int(tokens[t]) == peer:
			tokens.erase(t)


func _live_count(room: Dictionary) -> int:
	var n := 0
	var peers: Dictionary = room["peers"]
	for p: Variant in peers.keys():
		if int(peers[p]) >= 0:
			n += 1
	return n


func _error(conn: int, code: String) -> void:
	_out.append([conn, {"t": "error", "code": code}])


func _take_token(c: Dictionary) -> bool:
	if not enforce_rate_limits:
		return true
	var elapsed := now_s - float(c["bucket_t"])
	c["bucket_t"] = now_s
	var b := minf(
		float(NetMessages.BURST_MSGS), float(c["bucket"]) + elapsed * NetMessages.MAX_MSGS_PER_S
	)
	if b < 1.0:
		c["bucket"] = b
		return false
	c["bucket"] = b - 1.0
	return true


func _new_code() -> String:
	for _i in 1000:
		var code := ""
		if secure_random:
			var bytes := _random_bytes(NetMessages.CODE_LENGTH)
			for b in bytes:
				code += NetMessages.CODE_ALPHABET[b % NetMessages.CODE_ALPHABET.length()]
		else:
			code = RoomCode.random(rng)
		if not _rooms.has(code):
			return code
	return RoomCode.random(rng)


func _new_token(room: Dictionary, peer: int) -> String:
	var tokens: Dictionary = room["tokens"]
	for t: Variant in tokens.keys():
		if int(tokens[t]) == peer:
			tokens.erase(t)
	var token := ""
	if secure_random:
		token = _random_bytes(16).hex_encode()
	else:
		for _i in 4:
			token += "%08x" % (rng.randi() & 0xFFFFFFFF)
	tokens[token] = peer
	return token


func _random_bytes(n: int) -> PackedByteArray:
	if _crypto == null:
		_crypto = Crypto.new()
	return _crypto.generate_random_bytes(n)
