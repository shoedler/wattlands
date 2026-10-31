extends WlNetSession
## Test double of NetSession: records every call, keeps a lobby_state-like `lobby` and emits
## lobby_changed after host-side changes (like a real host broadcasting lobby_state). Tests drive
## the network side with simulate_hosting(), simulate_joined(), receive() and refuse().

var calls: Array = []
var slots: Array[PlayerSlot] = []
var ready_flags: Dictionary = {}
var settings_sent: Dictionary = {}
var info: Dictionary = {}
var emit_on_change: bool = true
## -1: computed from ready flags; 0/1 forced.
var all_ready_override: int = -1
## Echo each player_info as a lobby_changed (a host broadcasting lobby_state).
var echo_player_info: bool = false
var _echo_depth: int = 0


func record(call_name: String, args: Array = []) -> void:
	var c: Array = [call_name]
	c.append_array(args)
	calls.append(c)


func calls_named(call_name: String) -> Array:
	var out: Array = []
	for c: Variant in calls:
		if (c as Array)[0] == call_name:
			out.append(c)
	return out


func last_call(call_name: String) -> Array:
	var all := calls_named(call_name)
	return all[all.size() - 1] if not all.is_empty() else []


func start_offline() -> void:
	record("start_offline")
	role = ""
	local_peer = Wl.HOST_PEER


func host_room(max_peers: int = 8, preferred_code: String = "") -> void:
	record("host_room", [max_peers] if preferred_code == "" else [max_peers, preferred_code])
	role = Wl.HOST


func join_room(code: String) -> void:
	record("join_room", [code])
	role = Wl.CLIENT


func leave() -> void:
	record("leave")
	role = ""


func leave_when_flushed() -> void:
	record("leave_when_flushed")
	role = ""


func set_local_player_info(p_info: Dictionary) -> void:
	info = p_info.duplicate(true)
	record("set_local_player_info", [info])
	# Like a real host: every player_info comes back as a lobby_state broadcast. The depth guard
	# keeps a looping client from overflowing the stack, so its test fails instead of crashing.
	if echo_player_info and _echo_depth < 20:
		_echo_depth += 1
		var po: Dictionary = lobby.get("player_options", {})
		po[local_peer] = (info.get("player_options", {}) as Dictionary).duplicate(true)
		lobby["player_options"] = po
		lobby_changed.emit(lobby)
		_echo_depth -= 1


func set_ready(ready_flag: bool) -> void:
	record("set_ready", [ready_flag])
	ready_flags[local_peer] = ready_flag
	lobby["ready_flags"] = ready_flags.duplicate()
	_changed()


func set_game(game_id: String, game_version: String, content_id: String) -> void:
	record("set_game", [game_id, game_version, content_id])
	lobby["game_id"] = game_id
	lobby["game_version"] = game_version
	lobby["content_id"] = content_id
	_changed()


func set_scaling(mode: String) -> void:
	record("set_scaling", [mode])
	lobby["scaling"] = mode
	_changed()


func set_setting(key: String, value: Variant) -> void:
	record("set_setting", [key, value])
	settings_sent[key] = value
	lobby["settings"] = settings_sent.duplicate(true)
	_changed()


func set_player_option(peer_id: int, option_id: String, value: Variant) -> void:
	record("set_player_option", [peer_id, option_id, value])


func add_bot() -> bool:
	record("add_bot")
	var n := 1
	for s in slots:
		if s.is_bot:
			n += 1
	var ftp := float(settings_sent.get("bot_ftp", 200.0))
	slots.append(Bots.make_slot(n, slots.size(), ftp))
	_changed()
	return true


func remove_bot() -> bool:
	record("remove_bot")
	for i in range(slots.size() - 1, -1, -1):
		if slots[i].is_bot:
			slots.remove_at(i)
			_changed()
			return true
	return false


func lobby_slots() -> Array[PlayerSlot]:
	return slots.duplicate()


func all_ready() -> bool:
	if all_ready_override >= 0:
		return all_ready_override == 1
	var any := false
	for s in slots:
		if s.is_bot:
			continue
		any = true
		if not bool(ready_flags.get(s.peer_id, false)):
			return false
	return any


func mark_started() -> void:
	record("mark_started")
	session_started = true


func peers() -> Array[int]:
	var out: Array[int] = []
	for s in slots:
		if not s.is_bot:
			out.append(s.peer_id)
	return out


func _changed() -> void:
	if emit_on_change:
		lobby_changed.emit(lobby)


# --- network-side helpers for tests ------------------------------------------------------------


## A human slot for `peer` named `name` at the next slot index.
func add_human(peer: int, p_name: String, ftp: float = 200.0) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.peer_id = peer
	s.name = p_name
	s.ftp = ftp
	s.apply_look(slots.size())
	slots.append(s)
	return s


func simulate_hosting(code: String) -> void:
	room_code = code
	local_peer = Wl.HOST_PEER
	state_changed.emit("hosting", "")


func simulate_joined(peer: int, code: String, p_lobby: Dictionary) -> void:
	room_code = code
	local_peer = peer
	role = Wl.CLIENT
	lobby = p_lobby
	state_changed.emit("joined", "")
	lobby_changed.emit(lobby)


func receive(from: int, data: Dictionary) -> void:
	game_message.emit(from, data)


func refuse(reason: String) -> void:
	refused.emit(reason)
