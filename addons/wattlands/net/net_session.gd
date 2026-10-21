class_name WlNetSession
extends Node
## A network session (BRIEF 5.4): owns the transport, lobby state, roles, routing, clock
## offset (from clock_ping/clock_pong), snapshot buffers and reconnect. The autoload
## `NetSession` is the app's instance; tests and in-process simulations create more (one
## per simulated peer, over LoopbackTransport). Owned by net-client; public API frozen
## after W0. Runs with PROCESS_MODE_ALWAYS; poll() pumps the transport.
##
## Lobby (host-authoritative, broadcast as `lobby_state`): players (from each peer's
## player_info and the host's own), bots (when the game allows), ready flags, game_id,
## game_version, content_id, scaling mode, settings (game options, bot_ftp, ...) and each
## player's player_options. A client lacking the game or with another version can't ready
## up and sees a clear message. Once the session started, joins without a valid reconnect
## token get `refused` {reason: "session_in_progress"}.
## Reconnect: a dropped client re-joins with its saved token (Paths.reconnect_token_path())
## and keeps its peer id; the host re-sends lobby_state, its plan, its phase and the latest
## snapshot (the GameHost provides them through rejoin_requested).

## "offline", "connecting", "hosting", "joined", "reconnecting", "error".
signal state_changed(state: String, detail: String)
signal lobby_changed(lobby: Dictionary)
## A decoded, validated game message (BRIEF 5.5) for the GameHost.
signal game_message(from: int, data: Dictionary)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int, reason: String)
## The room or host refused us or ended: "session_in_progress", "version_mismatch",
## "room_not_found", "room_full", "rate_limited", "host_left".
signal refused(reason: String)
## Host: a peer came back with its token; send it its state.
signal rejoin_requested(peer_id: int)

var transport: Transport = null
## "", Wl.HOST or Wl.CLIENT.
var role: String = ""
var local_peer: int = 0
var host_peer: int = Wl.HOST_PEER
## Room code without the dash ("K7QX2M"); display with RoomCode.format().
var room_code: String = ""
## The latest lobby_state payload.
var lobby: Dictionary = {}
var session_started: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Use this transport (RelayTransport by default; LoopbackTransport in tests).
func use_transport(_t: Transport) -> void:
	pass


## Offline lobby for SOLO play (no transport; the local rider is peer 1).
func start_offline() -> void:
	pass


func host_room(_max_peers: int = 8) -> void:
	pass


func join_room(_code: String) -> void:
	pass


func leave() -> void:
	pass


## This rider's player_info (BRIEF 5.5): name, color, ftp, ftp_verified, p_eff_per_w,
## weight_kg only if opted in, preferred_cadence_rpm, haptics_on, autopilot,
## player_options, games ({id: version}).
func set_local_player_info(_info: Dictionary) -> void:
	pass


func set_ready(_ready_flag: bool) -> void:
	pass


# --- host-side lobby control ---------------------------------------------------
func set_game(_game_id: String, _game_version: String, _content_id: String) -> void:
	pass


func set_scaling(_mode: String) -> void:
	pass


## A session setting in lobby_state.settings (game options under "options", "bot_ftp").
func set_setting(_key: String, _value: Variant) -> void:
	pass


## A rider's player_options value (host for bots; clients send theirs via player_info).
func set_player_option(_peer_id: int, _option_id: String, _value: Variant) -> void:
	pass


func add_bot() -> bool:
	return false


func remove_bot() -> bool:
	return false


## PlayerSlots in slot order from the lobby (humans and bots).
func lobby_slots() -> Array[PlayerSlot]:
	return []


## True when every human peer is ready and has the game at the host's version.
func all_ready() -> bool:
	return false


## Mark the session started (joins now need a reconnect token).
func mark_started() -> void:
	pass


# --- messaging -------------------------------------------------------------------
func send_to_host(_data: Dictionary) -> void:
	pass


func send_to(_peer_id: int, _data: Dictionary) -> void:
	pass


func broadcast(_data: Dictionary) -> void:
	pass


## Estimated host platform time now (clock offset from clock_ping/clock_pong).
func host_time() -> float:
	return 0.0


func peers() -> Array[int]:
	return []


func poll() -> void:
	pass
