class_name LanDiscovery
extends RefCounted
## LAN room discovery (BRIEF 5.4 P1): hosts broadcast a small UDP beacon every second;
## clients listen and learn each room's code, address and relay port. Owned by net-client.
##
## Beacon (one UDP datagram, JSON):
##   {"wattlands": "lan", "proto": 1, "code": "K7QX2M", "port": 8790, "name": "Hana",
##    "build": "0.1.0", "game": "workout"}
## "game" (the lobby's game id) is optional (W2 round 2); a beacon without it parses with
## game_id "". The sender's address comes from the datagram, never from the payload.

const MAGIC := "lan"
const DEFAULT_PORT := 8791
## A room not heard from for this long is forgotten.
const STALE_S := 5.0

var port: int = DEFAULT_PORT
## "*" listens on every interface; tests use "127.0.0.1".
var bind_address: String = "*"
## code -> {code, ip, port, name, build, game_id, seen}
var rooms: Dictionary = {}

var _udp: PacketPeerUDP = null


## Start listening for beacons. OK or the bind error.
func start() -> Error:
	stop()
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(port, bind_address)
	if err != OK:
		push_warning("LanDiscovery: can't listen on %s:%d (error %d)" % [bind_address, port, err])
		_udp = null
	return err


func stop() -> void:
	if _udp != null:
		_udp.close()
		_udp = null


func is_listening() -> bool:
	return _udp != null and _udp.is_bound()


## Read pending beacons at time `now` (seconds); returns the codes heard in this call.
func poll(now: float) -> Array[String]:
	var heard: Array[String] = []
	if _udp == null:
		return heard
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var room := parse_beacon(pkt.get_string_from_utf8())
		if room.is_empty() or ip == "":
			continue
		room["ip"] = ip
		room["seen"] = now
		rooms[room["code"]] = room
		if not heard.has(room["code"]):
			heard.append(room["code"])
	for code: Variant in rooms.keys():
		if now - float((rooms[code] as Dictionary)["seen"]) > STALE_S:
			rooms.erase(code)
	return heard


## The room announced with `code` ({} if not heard recently).
func find(code: String) -> Dictionary:
	return rooms.get(RoomCode.normalize(code), {})


## Of `addresses` (IP.get_local_addresses()), those a rider elsewhere could type to reach this PC:
## private IPv4 networks, then Tailscale's 100.64.0.0/10. No loopback, link-local or IPv6.
static func shareable_addresses(addresses: PackedStringArray) -> PackedStringArray:
	var lan: PackedStringArray = []
	var tailnet: PackedStringArray = []
	for a: String in addresses:
		var parts := a.split(".")
		if parts.size() != 4 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var first := int(parts[0])
		var second := int(parts[1])
		if (
			first == 10
			or (first == 192 and second == 168)
			or (first == 172 and second >= 16 and second <= 31)
		):
			lan.append(a)
		elif first == 100 and second >= 64 and second <= 127:
			tailnet.append(a)
	lan.append_array(tailnet)
	return lan


## A beacon's JSON text ("game" only when game_id is set).
static func beacon(
	code: String, relay_port: int, name: String = "", game_id: String = ""
) -> String:
	var b := {
		"wattlands": MAGIC,
		"proto": Wl.PROTO,
		"code": RoomCode.normalize(code),
		"port": relay_port,
		"name": name,
		"build": Wl.BUILD
	}
	if game_id != "":
		b["game"] = game_id
	return JSON.stringify(b)


## A beacon's fields {code, port, name, build, game_id}, or {} if the text is not a valid
## beacon of this protocol version.
static func parse_beacon(text: String) -> Dictionary:
	if text.length() > 512:
		return {}
	var d: Variant = Protocol.parse_json(text)
	if not d is Dictionary:
		return {}
	var b: Dictionary = d
	if str(b.get("wattlands", "")) != MAGIC:
		return {}
	var proto: Variant = b.get("proto")
	if not (proto is float or proto is int) or int(proto) != Wl.PROTO:
		return {}
	var code := RoomCode.normalize(str(b.get("code", "")))
	var p: Variant = b.get("port")
	if code == "" or not (p is float or p is int) or int(p) <= 0 or int(p) > 65535:
		return {}
	var game: Variant = b.get("game", "")
	return {
		"code": code,
		"port": int(p),
		"name": str(b.get("name", "")),
		"build": str(b.get("build", "")),
		"game_id": str(game) if game is String else ""
	}
