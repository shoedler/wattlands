extends GutTest
## Base for the WlNetSession suites: a LoopbackHub, sessions with their own EventBus and
## token files in a temp profile dir, and an event log per session. Not collected by GUT
## (no test_ prefix); test files extend it by path.

const U := preload("res://tests/net/net_test_util.gd")

var hub: LoopbackHub
var tmp: String = ""
var sessions: Array[WlNetSession] = []
## label -> [[event, args...], ...]
var logs: Dictionary = {}


func before_each() -> void:
	hub = LoopbackHub.new(7)
	tmp = Paths.make_temp_dir("wl_net")
	Paths.set_override(tmp)
	sessions.clear()
	logs.clear()


func after_each() -> void:
	Paths.set_override("")
	_remove_dir(tmp)


func make_session(label: String, info: Dictionary = {}) -> WlNetSession:
	var s := WlNetSession.new()
	s.name = label
	var b := WlEventBus.new()
	s.add_child(b)
	s.bus = b
	s.persist_token = true
	s.token_path = tmp.path_join(label + "_token.json")
	s.recent_rooms_file = tmp.path_join(label + "_recent.json")
	add_child_autofree(s)
	s.use_transport(LoopbackTransport.hub_transport(hub))
	var log: Array = []
	logs[label] = log
	s.state_changed.connect(
		func(st: String, detail: String) -> void: log.append(["state", st, detail])
	)
	s.game_message.connect(
		func(from: int, data: Dictionary) -> void: log.append(["msg", from, data])
	)
	s.peer_joined.connect(func(id: int) -> void: log.append(["peer_joined", id]))
	s.peer_left.connect(
		func(id: int, reason: String) -> void: log.append(["peer_left", id, reason])
	)
	s.refused.connect(func(reason: String) -> void: log.append(["refused", reason]))
	s.rejoin_requested.connect(func(id: int) -> void: log.append(["rejoin_requested", id]))
	s.ready_refused.connect(
		func(reason: String, text: String) -> void: log.append(["ready_refused", reason, text])
	)
	b.session_refused.connect(func(reason: String) -> void: log.append(["bus_refused", reason]))
	b.peer_joined.connect(func(id: int) -> void: log.append(["bus_peer_joined", id]))
	b.peer_left.connect(
		func(id: int, reason: String) -> void: log.append(["bus_peer_left", id, reason])
	)
	if not info.is_empty():
		s.set_local_player_info(info)
	sessions.append(s)
	return s


func pump(n: int = 4) -> void:
	U.pump(sessions, n)


static func rider(
	name: String, version: String = "1", ftp: int = 200, extra: Dictionary = {}
) -> Dictionary:
	var d := {
		"name": name,
		"ftp": ftp,
		"ftp_verified": false,
		"p_eff_per_w": 250.0 / ftp,
		"preferred_cadence_rpm": 90.0,
		"haptics_on": true,
		"autopilot": false,
		"player_options": {},
		"games": {"workout": version}
	}
	for k: Variant in extra.keys():
		d[k] = extra[k]
	return d


## A host ("host", FTP 250, Workout 1) and clients c1.. with the given Workout versions.
func room(versions: Array = ["1", "1"]) -> Array[WlNetSession]:
	var out: Array[WlNetSession] = []
	var h := make_session("host", rider("Hana", "1", 250))
	h.set_game("workout", "1", "easy30")
	h.host_room(8)
	pump()
	out.append(h)
	var i := 1
	for v: Variant in versions:
		var c := make_session("c%d" % i, rider("Rider %d" % i, str(v), 200 + 10 * i))
		c.join_room(h.room_code)
		pump()
		out.append(c)
		i += 1
	pump()
	return out


func events(label: String, kind: String) -> Array:
	var out: Array = []
	for e: Array in logs[label]:
		if e[0] == kind:
			out.append(e)
	return out


func messages(label: String, type: String = "") -> Array:
	var out: Array = []
	for e: Array in logs[label]:
		if e[0] == "msg" and (type == "" or (e[2] as Dictionary).get("type", "") == type):
			out.append(e)
	return out


func clear_logs() -> void:
	for k: Variant in logs.keys():
		(logs[k] as Array).clear()


func player(s: WlNetSession, peer: int) -> Dictionary:
	for p: Variant in s.lobby.get("players", []):
		if int((p as Dictionary)["peer_id"]) == peer:
			return p
	return {}


func _remove_dir(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_remove_dir(dir.path_join(d))
	DirAccess.remove_absolute(dir)
