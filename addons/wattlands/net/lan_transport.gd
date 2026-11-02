class_name LanTransport
extends RelayTransport
## LAN play without the internet relay (BRIEF 5.4, P1). The host serves the relay protocol
## itself (LocalRelayServer on `port`, every interface by default), joins it over
## ws://127.0.0.1 like any client, and announces the room with a UDP beacon every second
## (LanDiscovery). A client joins by code: it listens for that code's beacon, then connects
## to ws://<beacon sender>:<port>/v1 and joins as with RelayTransport. Set `url` to join a
## known host directly (no discovery). Drops and reconnect tokens work as with the relay.
## This is also the built-in relay: WlNetSession uses it when no relay was chosen, so a rider with
## nothing but the release can host (docs/PROTOCOL.md section 8). A busy `port` falls back to any
## free port (the beacon names it), only this machine may create rooms on the relay, and the relay
## closes SERVER_LINGER_S after the host leaves, once clients have read host_left.
## Owned by net-client; runs with PROCESS_MODE_ALWAYS; all I/O in poll().

const DEFAULT_PORT := 8790
const BEACON_INTERVAL_S := 1.0
## A join waits this long for the room's beacon before room_not_found.
const DISCOVERY_TIMEOUT_S := 5.0
## After the host leaves, the relay stays up this long so the clients read host_left.
const SERVER_LINGER_S := 2.0

## The relay port when hosting (0 = any free port).
var port: int = DEFAULT_PORT
## Where the host's relay listens ("*" = every interface; tests use "127.0.0.1").
var bind_address: String = "*"
## The discovery UDP port, where beacons go (hosts) and are heard (clients).
var discovery_port: int = LanDiscovery.DEFAULT_PORT
## Beacon destination (the LAN broadcast address; tests use "127.0.0.1").
var discovery_address: String = "255.255.255.255"
## Where a joining client listens for beacons.
var discovery_bind: String = "*"
## The name shown in this host's beacon.
var host_name: String = ""
## The game id announced in this host's beacon ("" = none; WlNetSession keeps it at the
## lobby's game).
var game_id: String = ""
## The hosting peer's relay server (null on clients).
var server: LocalRelayServer = null
## The client's discovery listener (while searching).
var discovery: LanDiscovery = null

var _beacon: PacketPeerUDP = null
var _last_beacon_at: float = -INF
var _search_code: String = ""
var _search_token: String = ""
var _search_started: float = 0.0
var _found_code: String = ""
# When the relay closes after the host left (< 0: not closing).
var _server_stop_at: float = -1.0


func _init() -> void:
	super._init()
	connected.connect(_on_lan_connected)


## Host a LAN room: start the relay server, join it, then announce the room.
func host(max_peers: int = 8) -> void:
	_search_code = ""
	_server_stop_at = -1.0
	if server == null:
		server = LocalRelayServer.new()
		server.time_func = time_func
		server.local_create_only = true
		add_child(server)
	if not server.is_listening():
		var err := server.start(port, bind_address)
		if err != OK and port != 0:
			# Another program holds the port: the beacon tells clients which one this is.
			err = server.start(0, bind_address)
		if err != OK:
			last_error = "error"
			disconnected.emit("error")
			return
	url = server.local_url()
	super.host(max_peers)


## Join a LAN room by code (found by its beacon), or the host at `url` if one is set.
func join(code: String, token: String = "") -> void:
	var c := RoomCode.normalize(code)
	if c == "" or _serving():
		# Not a code (refused by the base), or the host re-joining its own relay.
		super.join(code, token)
		return
	if url != "" and (_found_code == "" or _found_code == c):
		# A host given directly, or the room found before (a rejoin after a drop).
		super.join(c, token)
		return
	url = ""
	if discovery == null:
		discovery = LanDiscovery.new()
		discovery.port = discovery_port
		discovery.bind_address = discovery_bind
	if not discovery.is_listening() and discovery.start() != OK:
		last_error = "error"
		disconnected.emit("error")
		return
	_search_code = c
	_search_token = token
	_search_started = _now()


## The rooms heard on the LAN so far ({code: {code, ip, port, name, build, game_id, seen}}).
## Starts listening if needed; call poll() to hear more.
func lan_rooms() -> Dictionary:
	if discovery == null:
		discovery = LanDiscovery.new()
		discovery.port = discovery_port
		discovery.bind_address = discovery_bind
	if not discovery.is_listening():
		discovery.start()
	return discovery.rooms


func searching() -> bool:
	return _search_code != ""


func poll() -> void:
	if server != null:
		server.poll()
		if _server_stop_at >= 0.0 and _now() >= _server_stop_at:
			_server_stop_at = -1.0
			server.stop()
	if discovery != null and discovery.is_listening():
		discovery.poll(_now())
		if _search_code != "":
			_check_search()
	super.poll()
	if _beacon != null and in_room() and is_host():
		var now := _now()
		if now - _last_beacon_at >= BEACON_INTERVAL_S:
			_last_beacon_at = now
			var text := LanDiscovery.beacon(
				room_code, server.port if server != null else port, host_name, game_id
			)
			_beacon.put_packet(text.to_utf8_buffer())


func leave() -> void:
	_search_code = ""
	_stop_beacon()
	if discovery != null:
		discovery.stop()
	var was_serving := _serving()
	super.leave()
	if was_serving:
		_server_stop_at = _now() + SERVER_LINGER_S
		url = ""


## This transport's relay is up for a room it hosts (not closing after the host left).
func _serving() -> bool:
	return server != null and server.is_listening() and _server_stop_at < 0.0


## The relay's port while it is up, else 0.
func serving_port() -> int:
	return server.port if _serving() else 0


func _check_search() -> void:
	var room := discovery.find(_search_code)
	if not room.is_empty():
		var c := _search_code
		_search_code = ""
		_found_code = c
		url = "ws://%s:%d/v1" % [str(room["ip"]), int(room["port"])]
		discovery.stop()
		super.join(c, _search_token)
		return
	if _now() - _search_started > DISCOVERY_TIMEOUT_S:
		_search_code = ""
		discovery.stop()
		last_error = "room_not_found"
		disconnected.emit("room_not_found")


func _on_lan_connected() -> void:
	if not is_host() or server == null:
		return
	_stop_beacon()
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address(discovery_address, discovery_port)
	_last_beacon_at = -INF


func _stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
		_beacon = null


func _exit_tree() -> void:
	_stop_beacon()
	if discovery != null:
		discovery.stop()
