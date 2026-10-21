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
##
## Time: tick(dt) advances this session's platform time and polls; poll() alone pumps I/O
## and, if tick() was never called, counts each poll as one Wl.SIM_DT (so in-process
## simulations that poll once per step get the same timing). The autoload ticks itself
## from _process (auto_poll); private instances never do.
## Messages: every decoded game message is emitted as game_message(from, data), after the
## built-in handling (lobby, ready, clock sync, refusals, snapshot buffer, int_fields).
## Messages addressed to the local peer are delivered locally on the next poll. Nothing
## over 16 384 bytes is ever sent (push_warning, counted in `stats`). Directives of kind
## course_grade, cadence_band and power_band to one peer are coalesced to at most one per
## 100 ms per kind (the latest wins, flushed before any other message to that peer), so
## `request` and `phase` are never dropped or reordered. See docs/PROTOCOL.md.

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
## Addition: our ready-up was refused ("missing_game" or "version_mismatch"), with a
## translated message for the lobby.
signal ready_refused(reason: String, message: String)

const STATE_OFFLINE := "offline"
const STATE_CONNECTING := "connecting"
const STATE_HOSTING := "hosting"
const STATE_JOINED := "joined"
const STATE_RECONNECTING := "reconnecting"
const STATE_ERROR := "error"

## Game messages a client may send to the host; every other type travels host -> clients.
const CLIENT_TO_HOST: Array[String] = ["player_info", "ready", "telemetry", "clock_ping"]
## Relay refusals that end a join or a session (Transport.disconnected reasons).
const REFUSALS: Array[String] = ["room_not_found", "room_full", "version_mismatch",
	"rate_limited", "bad_request", "session_in_progress"]
const COALESCED_KINDS: Array[String] = [NetMessages.DIRECTIVE_COURSE_GRADE,
	NetMessages.DIRECTIVE_CADENCE_BAND, NetMessages.DIRECTIVE_POWER_BAND]
const COALESCE_S := 0.1
## A coalesced directive waiting on a clock that stands still goes out after this many polls.
const FROZEN_CLOCK_POLLS := 3
## OWNERSHIP 3.1 C11: at most 32 intents per telemetry message, each <= 1 KB.
const MAX_INTENTS := 32
const MAX_INTENT_BYTES := 1024
const RECONNECT_BACKOFF_S: Array[float] = [0.0, 1.0, 2.0, 4.0, 8.0, 15.0]
const CLOCK_PING_FAST_S := 1.0
const CLOCK_PING_S := 5.0
const CLOCK_SAMPLES := 8
const RECENT_ROOMS_MAX := 10

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

# --- additions (public) ------------------------------------------------------------------
## The current connection state (see state_changed).
var state: String = STATE_OFFLINE
## True in the offline SOLO lobby (start_offline()).
var offline: bool = false
## The EventBus this session reports to (the autoload by default; in-process peers set
## their own).
var bus: WlEventBus = null
## Tick from _process with the wall-clock delta (true for the autoload instance only, by
## default). While it is on, tick(dt) from elsewhere only polls, so time never advances
## twice.
var auto_poll: bool = false
## Re-join with the reconnect token after a drop (attempts at once, then 1, 2, 4, 8 and
## every 15 s). When false the session waits in "reconnecting" for rejoin(). Either way it
## gives up 120 s after the drop (the token's life) with refused("dropped").
var auto_reconnect: bool = true
## Save the reconnect token and recent rooms under Paths.user_dir(). On by default for the
## NetSession autoload only: private instances (tests, in-process simulations with several
## sessions in one profile) keep the token in memory unless they turn this on with their
## own token_path, so two sessions never share one token file.
var persist_token: bool = false
## Reconnect token file; "" means Paths.reconnect_token_path().
var token_path: String = ""
## Recent rooms file; "" means Paths.recent_rooms_path().
var recent_rooms_file: String = ""
## Relay URL for the default RelayTransport; "" means RelayTransport.default_url().
var relay_url: String = ""
## Where installed games and their manifests come from: any Node with games() (manifests
## with "id" and "version") and manifest(id); null means the GameRegistry autoload.
var registry: Node = null
## Lobby limits (set_game_manifest() fills them from game.json).
var max_players: int = NetMessages.MAX_PEERS
var min_players: int = 1
var bots_allowed: bool = true
## Snapshots kept for interpolation (10 Hz: 8 is 0.8 s).
var snapshot_buffer_size: int = 8
## The running game's int_fields() (GameModule.int_fields()), applied to received
## snapshots and events before game_message.
var game_int_fields: Dictionary = {}
## The latest roster (`riders`, keyed by int peer id).
var latest_roster: Dictionary = {}
## Client: estimated host time minus local time, and the round trip it came from.
var clock_offset: float = 0.0
var clock_rtt: float = -1.0
## Why the latest refusal happened ("" if none).
var refusal_reason: String = ""
## Counters: sent, received, dropped_offline, oversize_dropped, oversize_snapshots,
## stale_snapshots, invalid_sends, ignored, intents_dropped, coalesced.
var stats: Dictionary = {}

var _local_info: Dictionary = {}
var _local_profile: RiderProfile = null
var _local_profile_games: Dictionary = {}
var _local_profile_trainer: String = ""
var _ready_wanted: bool = false

# Host / offline lobby model.
var _infos: Dictionary = {}
var _join_order: Array[int] = []
var _connected_peers: Dictionary = {}
var _ready_flags: Dictionary = {}
var _refused_peers: Dictionary = {}
var _session_players: Array[int] = []
var _bot_count: int = 0
var _bot_options: Dictionary = {}
var _game_id: String = ""
var _game_version: String = ""
var _content_id: String = ""
var _scaling: String = Wl.FAIR_FTP
var _settings: Dictionary = {}
var _options: Dictionary = {}
var _bot_ftp: int = 0
var _manifests: Dictionary = {}
var _lobby_seq: int = 0
var _lobby_text: String = ""

# Connection.
var _token: String = ""
var _explicit_leave: bool = false
var _ever_connected: bool = false
var _reconnect_pending: bool = false
var _reconnect_in_flight: bool = false
var _reconnect_attempts: int = 0
var _reconnect_at: float = 0.0
var _reconnect_started: float = 0.0
var _requested_code: String = ""

# Time.
var _now_s: float = 0.0
var _ticked: bool = false
var _polls: int = 0

# Clock sync (client).
var _clock_samples: Array = []
var _clock_next_at: float = 0.0

# Snapshots.
var _snapshots: Array = []
var _latest_snapshot: Dictionary = {}
# Host: the latest sent snapshot's text, decoded on demand by latest_snapshot().
var _latest_snapshot_text: String = ""

# Coalescer: "peer:kind" -> last send time / [peer, data, polls].
var _co_last: Dictionary = {}
var _co_pending: Dictionary = {}

# Messages to ourselves, delivered on the next poll.
var _self_inbox: Array[String] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_stats()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_parent() == get_tree().root and name == "NetSession":
		auto_poll = true
		persist_token = true
	_bus()


func _process(delta: float) -> void:
	if auto_poll:
		_advance(delta)
		poll()


## Use this transport (RelayTransport by default; LoopbackTransport in tests).
func use_transport(t: Transport) -> void:
	if transport == t:
		return
	if transport != null:
		_disconnect_transport(transport)
	transport = t
	if t == null:
		return
	if t.get_parent() == null:
		add_child(t)
	t.connected.connect(_on_connected)
	t.disconnected.connect(_on_disconnected)
	t.peer_joined.connect(_on_peer_joined)
	t.peer_left.connect(_on_peer_left)
	t.message.connect(_on_message)
	if t.has_signal("protocol_mismatch"):
		t.connect("protocol_mismatch", _on_protocol_mismatch)
	if t.has_signal("relay_error"):
		t.connect("relay_error", _on_relay_error)


## Offline lobby for SOLO play (no transport; the local rider is peer 1).
func start_offline() -> void:
	_explicit_leave = true
	_leave_transport()
	_reset_room_state()
	offline = true
	role = ""
	local_peer = Wl.HOST_PEER
	host_peer = Wl.HOST_PEER
	_ensure_local_info()
	_infos[local_peer] = _local_info.duplicate(true)
	_join_order = [local_peer]
	_connected_peers = {local_peer: true}
	_set_state(STATE_OFFLINE, "solo")
	_publish_lobby()


func host_room(max_peers: int = 8) -> void:
	_ensure_transport()
	_reset_room_state()
	offline = false
	role = Wl.HOST
	_explicit_leave = false
	_ensure_local_info()
	if transport is RelayClientTransport:
		(transport as RelayClientTransport).requested_code = _requested_code
	_requested_code = ""
	_set_state(STATE_CONNECTING, "host")
	transport.host(clampi(max_peers, 1, NetMessages.MAX_PEERS))


func join_room(code: String) -> void:
	var c := RoomCode.normalize(code)
	_ensure_transport()
	_reset_room_state()
	offline = false
	role = Wl.CLIENT
	_explicit_leave = false
	_ensure_local_info()
	if c == "":
		push_warning("NetSession: \"%s\" is not a room code" % code)
		_refuse("room_not_found")
		return
	room_code = c
	_token = _load_token_for(c)
	_set_state(STATE_CONNECTING, c)
	transport.join(c, _token)


func leave() -> void:
	_explicit_leave = true
	_reconnect_pending = false
	_leave_transport()
	_clear_token_file()
	_reset_room_state()
	offline = false
	_set_state(STATE_OFFLINE, "left")


## This rider's player_info (BRIEF 5.5): name, color, ftp, ftp_verified, p_eff_per_w,
## weight_kg only if opted in, preferred_cadence_rpm, haptics_on, autopilot,
## player_options, games ({id: version}).
## Optional extras: haptic_intensity, trainer (status text), p_eff_mode (the scaling
## mode p_eff_per_w was computed for) and p_eff_by_mode ({mode: value}); missing fields
## get defaults.
func set_local_player_info(info: Dictionary) -> void:
	var src := info
	if not info.has("games"):
		src = info.duplicate()
		src["games"] = _registry_games()
	_local_info = _normalize_info(src)
	if is_authority():
		if local_peer != 0:
			_infos[local_peer] = _local_info.duplicate(true)
			_publish_lobby()
	elif role == Wl.CLIENT and _in_room():
		_send_player_info()


func set_ready(ready_flag: bool) -> void:
	_ready_wanted = ready_flag
	if is_authority():
		if local_peer == 0 or session_started:
			return
		_ready_flags[local_peer] = ready_flag
		_publish_lobby()
		return
	if role != Wl.CLIENT:
		return
	if ready_flag:
		var issue := ready_block_reason()
		if issue != "":
			_ready_wanted = false
			ready_refused.emit(issue, _ready_text(issue, str(lobby.get("game_id", "")),
				_version_str(_local_info.get("games", {}).get(lobby.get("game_id", ""), "")),
				_version_str(lobby.get("game_version", ""))))
			return
	if _in_room():
		_send(host_peer, Protocol.game_msg("ready", {"ready": ready_flag}))


# --- host-side lobby control ---------------------------------------------------
func set_game(game_id: String, game_version: String, content_id: String) -> void:
	if not _require_authority("set_game"):
		return
	var changed := game_id != _game_id or _version_str(game_version) != _game_version
	if game_id != "" and not _manifests.has(game_id):
		var m := _registry_manifest(game_id)
		if not m.is_empty():
			_manifests[game_id] = m
	_game_id = game_id
	_game_version = _version_str(game_version)
	_content_id = content_id
	if changed:
		_apply_manifest_limits()
		_options = _option_defaults("options")
		for p: Variant in _ready_flags.keys():
			if int(p) != local_peer:
				_ready_flags[p] = false
	_publish_lobby()


func set_scaling(mode: String) -> void:
	if not _require_authority("set_scaling"):
		return
	if not Wl.SCALING_MODES.has(mode):
		push_error("NetSession.set_scaling: unknown scaling mode \"%s\"" % mode)
		return
	_scaling = mode
	if _local_profile != null:
		var po: Variant = _local_info.get("player_options", {})
		_local_info = _normalize_info(_info_from_local_profile())
		_local_info["player_options"] = po if po is Dictionary else {}
		if local_peer != 0:
			_infos[local_peer] = _local_info.duplicate(true)
	_publish_lobby()


## A session setting in lobby_state.settings (game options under "options", "bot_ftp").
func set_setting(key: String, value: Variant) -> void:
	if not _require_authority("set_setting"):
		return
	match key:
		"bot_ftp":
			if not (value is int or value is float):
				push_error("NetSession.set_setting: bot_ftp must be a number")
				return
			_bot_ftp = clampi(roundi(float(value)), 1, 2000)
		"options":
			if not value is Dictionary:
				push_error("NetSession.set_setting: options must be a Dictionary")
				return
			var merged := _option_defaults("options")
			for k: Variant in (value as Dictionary).keys():
				if merged.is_empty() or merged.has(k) or not _has_manifest():
					merged[k] = (value as Dictionary)[k]
			_options = merged
		_:
			_settings[key] = value
	_publish_lobby()


## A rider's player_options value (host for bots; clients send theirs via player_info).
func set_player_option(peer_id: int, option_id: String, value: Variant) -> void:
	var is_local := peer_id == local_peer and local_peer != 0
	if local_peer == 0 and is_authority() and peer_id == Wl.HOST_PEER:
		is_local = true
	if is_local:
		_ensure_local_info()
		var po: Dictionary = _local_info.get("player_options", {})
		po[option_id] = value
		_local_info["player_options"] = po
		if is_authority():
			if local_peer != 0:
				_infos[local_peer] = _local_info.duplicate(true)
				_publish_lobby()
		elif _in_room():
			_send_player_info()
		return
	if not is_authority():
		push_warning("NetSession.set_player_option: a client sets only its own options")
		return
	if peer_id < 0 and -peer_id <= _bot_count:
		var bo: Dictionary = _bot_options.get(peer_id, {})
		bo[option_id] = value
		_bot_options[peer_id] = bo
		_publish_lobby()
		return
	push_warning("NetSession.set_player_option: peer %d sets its own options" % peer_id)


func add_bot() -> bool:
	if not is_authority() or session_started or not bots_allowed:
		return false
	if _lobby_humans().size() + _bot_count >= max_players:
		return false
	_bot_count += 1
	_publish_lobby()
	return true


func remove_bot() -> bool:
	if not is_authority() or session_started or _bot_count <= 0:
		return false
	_bot_options.erase(Bots.peer_id(_bot_count))
	_bot_count -= 1
	_publish_lobby()
	return true


## PlayerSlots in slot order from the lobby (humans and bots).
func lobby_slots() -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	var players: Variant = lobby.get("players", [])
	if not players is Array:
		return out
	var popts: Variant = lobby.get("player_options", {})
	var scaling := str(lobby.get("scaling", Wl.FAIR_FTP))
	var arr: Array = (players as Array).duplicate()
	arr.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("slot_index", 0)) < int((b as Dictionary).get("slot_index", 0)))
	for p: Variant in arr:
		if not p is Dictionary:
			continue
		var s := PlayerSlot.from_dict(p)
		s.apply_look(s.slot_index)
		s.scaling_mode = scaling
		s.options = {}
		if popts is Dictionary and (popts as Dictionary).get(s.peer_id) is Dictionary:
			s.options = ((popts as Dictionary)[s.peer_id] as Dictionary).duplicate(true)
		out.append(s)
	return out


## True when every human peer is ready and has the game at the host's version.
func all_ready() -> bool:
	var players: Variant = lobby.get("players", [])
	if not players is Array or (players as Array).is_empty():
		return false
	var humans := 0
	for p: Variant in players:
		var d: Dictionary = p
		if bool(d.get("is_bot", false)):
			continue
		humans += 1
		if not bool(d.get("ready", false)) or not bool(d.get("game_ok", true)):
			return false
		if not bool(d.get("connected", true)):
			return false
	if humans == 0:
		return false
	var settings: Variant = lobby.get("settings", {})
	if settings is Dictionary:
		var n := (players as Array).size()
		if n < int((settings as Dictionary).get("min_players", 1)):
			return false
		if n > int((settings as Dictionary).get("max_players", NetMessages.MAX_PEERS)):
			return false
	return true


## Mark the session started (joins now need a reconnect token).
func mark_started() -> void:
	session_started = true
	clear_snapshots()
	if not is_authority():
		return
	_session_players = _lobby_humans()
	for p: Variant in _connected_peers.keys():
		var peer := int(p)
		if peer != local_peer and not _session_players.has(peer):
			_refuse_peer(peer, "session_in_progress")
	_publish_lobby()


# --- messaging -------------------------------------------------------------------
func send_to_host(data: Dictionary) -> void:
	if is_authority():
		_deliver_self(data)
		return
	_send(host_peer, data)


func send_to(peer_id: int, data: Dictionary) -> void:
	if peer_id == local_peer and local_peer != 0:
		_deliver_self(data)
		return
	if role == Wl.CLIENT and peer_id != host_peer:
		push_warning("NetSession: clients send only to the host (message to %d dropped)" % peer_id)
		_count("ignored")
		return
	if peer_id <= 0:
		push_warning("NetSession.send_to: no such peer %d (use broadcast)" % peer_id)
		_count("ignored")
		return
	_send(peer_id, data)


func broadcast(data: Dictionary) -> void:
	if offline:
		return
	if role != Wl.HOST:
		push_warning("NetSession.broadcast: only the host broadcasts")
		_count("ignored")
		return
	_send(Wl.ALL_PEERS, data)


## Host: broadcast the 2 Hz roster ({peer: entry}, see NetRoster.build()) and keep it as
## latest_roster, decoded exactly as clients see it (int peer keys). Emits the bus's
## roster_changed on the host; clients emit it when the roster arrives. Returns the roster.
func send_roster(riders: Dictionary) -> Dictionary:
	if not is_authority():
		push_warning("NetSession.send_roster: only the host sends the roster")
		return latest_roster
	var msg := Protocol.game_msg("roster", {"riders": riders})
	var text := Protocol.encode(msg)
	var decoded := Protocol.decode(text)
	if decoded.is_empty():
		push_error("NetSession.send_roster: the roster is not a valid message")
		return latest_roster
	latest_roster = decoded["riders"]
	if role == Wl.HOST and _in_room():
		_send_text(Wl.ALL_PEERS, "roster", text)
	_emit_bus("roster_changed", [latest_roster])
	return latest_roster


## Estimated host platform time now (clock offset from clock_ping/clock_pong).
func host_time() -> float:
	if role == Wl.CLIENT:
		return _clock_now() + clock_offset
	return _clock_now()


## The human riders of the lobby (or the started session) who are connected, this one
## included, sorted. Peers that joined but sent no player_info yet are not listed.
func peers() -> Array[int]:
	var out: Array[int] = []
	var players: Variant = lobby.get("players", [])
	if players is Array:
		for d: Variant in players:
			var pd: Dictionary = d
			if not bool(pd.get("is_bot", false)) and bool(pd.get("connected", true)):
				out.append(int(pd.get("peer_id", 0)))
	if local_peer != 0 and not out.has(local_peer):
		out.append(local_peer)
	out.sort()
	return out


func poll() -> void:
	_polls += 1
	if transport != null:
		transport.poll()
	_drain_self_inbox()
	_reconnect_step()
	_flush_coalesced(-1, true)
	if role == Wl.CLIENT and state == STATE_JOINED and _clock_now() >= _clock_next_at:
		_send_clock_ping()


# --- additions: time ---------------------------------------------------------------------

## Advance this session's platform time by dt and poll (the GameHost calls it once per
## platform step with Wl.SIM_DT). With auto_poll on (the autoload, which ticks itself from
## _process) it only polls.
func tick(dt: float) -> void:
	if not auto_poll:
		_advance(dt)
	poll()


func _advance(dt: float) -> void:
	_now_s += maxf(dt, 0.0)
	_ticked = true


## Set this session's platform time (seconds), e.g. from SimClock.platform_time().
func set_time(t: float) -> void:
	_now_s = t
	_ticked = true


## This session's platform time now.
func local_time() -> float:
	return _clock_now()


# --- additions: lobby ----------------------------------------------------------------------

## True on the host, in the offline lobby and before any room exists (lobby settings made
## then carry into host_room()); false on clients.
func is_authority() -> bool:
	return offline or role != Wl.CLIENT


## Build player_info from a RiderProfile and keep it current: p_eff_per_w follows the
## lobby's scaling mode (re-sent when the host changes it). Empty `games` means the
## registry's installed games ({id: version}).
func set_local_profile(profile: RiderProfile, games: Dictionary = {}, player_options: Dictionary = {},
		trainer: String = "") -> void:
	_local_profile = profile
	_local_profile_games = games.duplicate(true)
	_local_profile_trainer = trainer
	var info := _info_from_local_profile()
	info["player_options"] = player_options.duplicate(true)
	set_local_player_info(info)


## player_info fields from a profile for scaling `mode` (weight only if shared).
static func player_info_from_profile(profile: RiderProfile, mode: String = Wl.FAIR_FTP,
		games: Dictionary = {}, player_options: Dictionary = {}, trainer: String = "") -> Dictionary:
	var by_mode := {
		Wl.FAIR_FTP: profile.p_eff_per_w(Wl.FAIR_FTP),
		Wl.RAW: 1.0,
	}
	var info := {
		"name": profile.display_name,
		"color": profile.color.to_html(false),
		"ftp": roundi(profile.ftp_w),
		"ftp_verified": profile.ftp_verified,
		"p_eff_per_w": profile.p_eff_per_w(mode),
		"p_eff_mode": mode,
		"preferred_cadence_rpm": profile.preferred_cadence_rpm,
		"haptics_on": profile.haptics_on,
		"haptic_intensity": profile.haptic_intensity_pct / 100.0,
		"autopilot": profile.autopilot_default,
		"player_options": player_options.duplicate(true),
		"games": games.duplicate(true),
	}
	if profile.share_weight:
		info["weight_kg"] = profile.weight_kg
		by_mode[Wl.WKG] = profile.p_eff_per_w(Wl.WKG)
	info["p_eff_by_mode"] = by_mode
	if trainer != "":
		info["trainer"] = trainer
	return info


## Register a game.json manifest (Dictionary): its min/max players, bots flag and option
## defaults apply whenever that game is selected with set_game().
func set_game_manifest(manifest: Dictionary) -> void:
	var id := str(manifest.get("id", ""))
	if id == "":
		push_error("NetSession.set_game_manifest: manifest without an id")
		return
	_manifests[id] = manifest.duplicate(true)
	if id == _game_id and is_authority():
		_apply_manifest_limits()
		var keep := _options
		_options = _option_defaults("options")
		for k: Variant in keep.keys():
			if _options.has(k):
				_options[k] = keep[k]
		_publish_lobby()


## One game option (lobby_state.settings.options[id]).
func set_option(option_id: String, value: Variant) -> void:
	if not _require_authority("set_option"):
		return
	_options[option_id] = value
	_publish_lobby()


## This rider's trainer status for the lobby ("connected", "mock", "searching", ...).
func set_trainer_status(status: String) -> void:
	_local_profile_trainer = status
	_ensure_local_info()
	_local_info["trainer"] = status
	set_local_player_info(_local_info)


## Back to the lobby after a session: dropped riders leave, ready flags reset.
func mark_ended() -> void:
	session_started = false
	clear_snapshots()
	if not is_authority():
		return
	_session_players.clear()
	for p: Variant in _ready_flags.keys():
		_ready_flags[p] = false
	for p in _join_order.duplicate():
		if p != local_peer and not _connected_peers.has(p):
			_join_order.erase(p)
			_infos.erase(p)
	_publish_lobby()


## Client: why set_ready(true) would be refused ("missing_game", "version_mismatch"), or "".
func ready_block_reason() -> String:
	if is_authority():
		return ""
	var gid := str(lobby.get("game_id", ""))
	if gid == "":
		return ""
	var games: Variant = _local_info.get("games", {})
	if not games is Dictionary or not (games as Dictionary).has(gid):
		return "missing_game"
	if _version_str((games as Dictionary)[gid]) != _version_str(lobby.get("game_version", "")):
		return "version_mismatch"
	return ""


## Peers in the session other than this one, sorted.
func remote_peers() -> Array[int]:
	var out: Array[int] = []
	for p in peers():
		if p != local_peer:
			out.append(p)
	return out


## Bots in the lobby.
func bot_count() -> int:
	return _bot_count


## The lobby's bot FTP (the host's FTP unless set_setting("bot_ftp", w) was called).
func bot_ftp() -> int:
	return _effective_bot_ftp()


# --- additions: reconnect and rooms --------------------------------------------------------

## Re-join the current room with the reconnect token now (also what auto_reconnect does).
func rejoin() -> void:
	if room_code == "" or transport == null:
		return
	if not _reconnect_pending:
		_reconnect_pending = true
		_reconnect_started = _clock_now()
		_reconnect_attempts = 0
		_set_state(STATE_RECONNECTING, "rejoin")
	_reconnect_in_flight = false
	_reconnect_at = _clock_now()
	_reconnect_step()
	if not auto_reconnect:
		_reconnect_at = INF


## P1: host again with the code this profile hosted last (the relay gives a new one if it
## is taken).
func host_room_reclaim(max_peers: int = 8) -> void:
	_requested_code = last_hosted_code()
	host_room(max_peers)
	_requested_code = ""


## P1: recently used rooms, newest first: [{code, role}].
func recent_rooms() -> Array:
	var data: Variant = _read_json(_recent_rooms_path())
	if data is Array:
		return data
	return []


## P1: the code this profile hosted last ("" if none).
func last_hosted_code() -> String:
	for r: Variant in recent_rooms():
		if r is Dictionary and str((r as Dictionary).get("role", "")) == Wl.HOST:
			return RoomCode.normalize(str((r as Dictionary).get("code", "")))
	return ""


# --- additions: snapshots ----------------------------------------------------------------

## The latest snapshot message ({game_id, seq, state, ...}): received (client) or sent
## (host); {} if none.
func latest_snapshot() -> Dictionary:
	if _latest_snapshot_text != "":
		var snap := Protocol.decode(_latest_snapshot_text)
		_latest_snapshot_text = ""
		if not snap.is_empty():
			_latest_snapshot = Protocol.apply_game_int_fields(snap, game_int_fields)
	return _latest_snapshot


## Buffered snapshots, oldest first: [{seq, t (host time), msg}].
func snapshot_buffer() -> Array:
	return _snapshots.duplicate()


## The newest buffered snapshot message at or before host time `t` (the oldest one if all
## are newer; {} if none). Clients render at host_time() - 0.1 for 100 ms interpolation.
func snapshot_at(t: float) -> Dictionary:
	if _snapshots.is_empty():
		return {}
	var best: Dictionary = _snapshots[0]
	for e: Variant in _snapshots:
		var d: Dictionary = e
		if float(d["t"]) <= t:
			best = d
	return best["msg"]


## Interpolation pair around host time `t`: {"from": msg, "to": msg, "alpha": 0..1}
## ({} if no snapshot). Past the newest snapshot both are the newest and alpha is 1.
func snapshot_pair_at(t: float) -> Dictionary:
	if _snapshots.is_empty():
		return {}
	var first: Dictionary = _snapshots[0]
	if t <= float(first["t"]):
		return {"from": first["msg"], "to": first["msg"], "alpha": 0.0}
	for i in range(_snapshots.size() - 1):
		var a: Dictionary = _snapshots[i]
		var b: Dictionary = _snapshots[i + 1]
		if t >= float(a["t"]) and t < float(b["t"]):
			var span := float(b["t"]) - float(a["t"])
			var alpha := 0.0 if span <= 0.0 else clampf((t - float(a["t"])) / span, 0.0, 1.0)
			return {"from": a["msg"], "to": b["msg"], "alpha": alpha}
	var last: Dictionary = _snapshots[_snapshots.size() - 1]
	return {"from": last["msg"], "to": last["msg"], "alpha": 1.0}


func clear_snapshots() -> void:
	_snapshots.clear()
	_latest_snapshot = {}
	_latest_snapshot_text = ""


## The running game's int_fields() for snapshots and events (see game_int_fields).
func set_game_int_fields(fields: Dictionary) -> void:
	game_int_fields = fields.duplicate(true)


# --- additions: strings ------------------------------------------------------------------

## The strings key (content/strings/net.csv) for a refusal or end reason.
static func reason_key(reason: String) -> String:
	return "NET_REFUSED_" + reason.to_upper()


## A translated, human-readable text for a refusal or end reason (the reason itself if
## there is no string for it).
static func reason_text(reason: String) -> String:
	var key := reason_key(reason)
	var t := String(TranslationServer.translate(key))
	return reason if t == key or t == "" else t


# --- transport events ----------------------------------------------------------------------

func _on_connected() -> void:
	if _explicit_leave or role == "":
		# A room that arrived after leave(), a refusal or the session's end: leave it.
		_leave_transport()
		return
	local_peer = transport.local_peer
	host_peer = transport.host_peer
	room_code = transport.room_code
	_token = transport.reconnect_token
	_reconnect_pending = false
	_reconnect_in_flight = false
	_ever_connected = true
	refusal_reason = ""
	_save_token()
	_record_recent_room()
	if transport.is_host():
		role = Wl.HOST
		_connected_peers[local_peer] = true
		if not _join_order.has(local_peer):
			_join_order.insert(0, local_peer)
		_ensure_local_info()
		_infos[local_peer] = _local_info.duplicate(true)
		_set_state(STATE_HOSTING, room_code)
		_publish_lobby()
	else:
		role = Wl.CLIENT
		# After a rejoin the host sends its latest snapshot; an older buffer (or one from a
		# session that ended while we were away) must not hold it back as stale.
		clear_snapshots()
		_set_state(STATE_JOINED, room_code)
		_send_player_info()
		if _ready_wanted and not session_started:
			_send(host_peer, Protocol.game_msg("ready", {"ready": true}))
		_clock_next_at = _clock_now()
		_send_clock_ping()


func _on_disconnected(reason: String) -> void:
	if _explicit_leave:
		return
	_reconnect_in_flight = false
	if reason == "host_left":
		_end("host_left", STATE_OFFLINE)
		return
	if _reconnect_pending and reason == "rate_limited":
		# The relay throttled a rejoin attempt: try again at the next backoff step.
		return
	if REFUSALS.has(reason):
		_refuse(reason)
		return
	if _ever_connected and room_code != "" and _token != "":
		if not _reconnect_pending:
			_reconnect_pending = true
			_reconnect_started = _clock_now()
			_reconnect_attempts = 0
			_reconnect_at = _clock_now() if auto_reconnect else INF
			_set_state(STATE_RECONNECTING, reason)
		return
	if _reconnect_pending:
		return
	if _ever_connected:
		_end(reason, STATE_ERROR)
	else:
		_set_state(STATE_ERROR, "connect_failed")


func _on_peer_joined(id: int) -> void:
	if role != Wl.HOST:
		peer_joined.emit(id)
		_emit_bus("peer_joined", [id])
		return
	if session_started:
		if _session_players.has(id):
			_connected_peers[id] = true
			_publish_lobby()
			peer_joined.emit(id)
			_emit_bus("peer_joined", [id])
			rejoin_requested.emit(id)
		else:
			_refuse_peer(id, "session_in_progress")
		return
	if not _join_order.has(id) and _lobby_humans().size() >= max_players:
		_refuse_peer(id, "room_full")
		return
	_refused_peers.erase(id)
	_connected_peers[id] = true
	if not _join_order.has(id):
		_join_order.append(id)
	peer_joined.emit(id)
	_emit_bus("peer_joined", [id])
	if _infos.has(id):
		_publish_lobby()
	elif _lobby_text != "":
		_send_text(id, "lobby_state", _lobby_text)


func _on_peer_left(id: int) -> void:
	var reason := transport.last_peer_left_reason if transport != null else "dropped"
	if reason == "":
		reason = "dropped"
	if role != Wl.HOST:
		peer_left.emit(id, reason)
		_emit_bus("peer_left", [id, reason])
		return
	if _refused_peers.has(id):
		_refused_peers.erase(id)
		return
	if not _connected_peers.has(id):
		return
	_connected_peers.erase(id)
	_drop_coalesced(id)
	if not session_started:
		_ready_flags[id] = false
		if reason == "left":
			_join_order.erase(id)
			_infos.erase(id)
			_ready_flags.erase(id)
	peer_left.emit(id, reason)
	_emit_bus("peer_left", [id, reason])
	_publish_lobby()


func _on_message(from: int, data: Dictionary) -> void:
	_count("received")
	var type := str(data.get("type", ""))
	if role == Wl.HOST:
		if from != local_peer:
			if _refused_peers.has(from):
				return
			if not CLIENT_TO_HOST.has(type):
				push_warning("NetSession: host ignored \"%s\" from peer %d" % [type, from])
				_count("ignored")
				return
			if session_started and not _session_players.has(from):
				_refuse_peer(from, "session_in_progress")
				return
		match type:
			"player_info":
				_on_player_info(from, data)
			"ready":
				_on_ready(from, data)
			"clock_ping":
				_send(from, Protocol.game_msg("clock_pong", {"t0": data["t0"], "th": _clock_now()}))
			"telemetry":
				_sanitize_telemetry(from, data)
	elif role == Wl.CLIENT:
		if (from != host_peer and from != local_peer) or CLIENT_TO_HOST.has(type):
			push_warning("NetSession: client ignored \"%s\" from peer %d" % [type, from])
			_count("ignored")
			return
		match type:
			"lobby_state":
				_on_lobby_state(data)
			"refused":
				_on_refused_msg(data)
				return
			"clock_pong":
				_on_clock_pong(data)
			"session_start":
				clear_snapshots()
				session_started = true
			"snapshot":
				if not _buffer_snapshot(data):
					return
			"event":
				Protocol.apply_game_int_fields(data, game_int_fields)
			"roster":
				latest_roster = data["riders"]
				_emit_bus("roster_changed", [latest_roster])
	game_message.emit(from, data)


func _on_protocol_mismatch(from: int) -> void:
	if role == Wl.HOST and from != local_peer and from > 0:
		_refuse_peer(from, "version_mismatch")
	elif role == Wl.CLIENT and from == host_peer:
		_refuse("version_mismatch")


func _on_relay_error(code: String) -> void:
	_count("relay_" + code)


# --- host handlers ----------------------------------------------------------------------

func _on_player_info(from: int, data: Dictionary) -> void:
	if from != local_peer and not session_started and not _lobby_humans().has(from) \
			and _lobby_humans().size() >= max_players:
		# Several peers joined before any of them sent player_info: the first ones fill the
		# lobby, the rest are refused.
		_refuse_peer(from, "room_full")
		return
	var info := _normalize_info(data)
	_infos[from] = info
	if from != local_peer and not _join_order.has(from):
		_join_order.append(from)
	_publish_lobby()


func _on_ready(from: int, data: Dictionary) -> void:
	if session_started:
		return
	var want := bool(data["ready"])
	if want:
		var issue := _game_issue(from)
		if issue != "":
			_ready_flags[from] = false
			_send(from, Protocol.game_msg("refused", {"reason": issue, "scope": "ready",
				"game_id": _game_id, "game_version": _game_version}))
			_publish_lobby()
			return
	_ready_flags[from] = want
	_publish_lobby()


func _sanitize_telemetry(from: int, data: Dictionary) -> void:
	var tm: Dictionary = data["tm"]
	# A client speaks only for its own rider.
	tm["peer"] = from
	var intents: Variant = tm.get("intents", [])
	if not intents is Array:
		return
	var arr: Array = intents
	var kept: Array = []
	var dropped := 0
	for it: Variant in arr:
		if kept.size() >= MAX_INTENTS:
			dropped += 1
			continue
		if JSON.stringify(it).to_utf8_buffer().size() > MAX_INTENT_BYTES:
			dropped += 1
			continue
		kept.append(it)
	if dropped > 0:
		push_warning("NetSession: dropped %d intents from peer %d (max %d per telemetry, %d bytes each)"
			% [dropped, from, MAX_INTENTS, MAX_INTENT_BYTES])
		stats["intents_dropped"] = int(stats.get("intents_dropped", 0)) + dropped
		tm["intents"] = kept


func _refuse_peer(peer: int, reason: String) -> void:
	_refused_peers[peer] = true
	var listed := _connected_peers.has(peer) and _infos.has(peer)
	_connected_peers.erase(peer)
	_ready_flags.erase(peer)
	if not _session_players.has(peer):
		_join_order.erase(peer)
		_infos.erase(peer)
	_send(peer, Protocol.game_msg("refused", {"reason": reason}))
	if listed:
		_publish_lobby()


# --- client handlers ----------------------------------------------------------------------

func _on_lobby_state(data: Dictionary) -> void:
	lobby = data
	var started := bool(data.get("started", session_started))
	if started != session_started:
		# A session began or ended: its snapshot seqs start over.
		clear_snapshots()
	session_started = started
	if _local_profile != null and str(_local_info.get("p_eff_mode", "")) != str(data.get("scaling", Wl.FAIR_FTP)):
		var po: Variant = _local_info.get("player_options", {})
		_local_info = _normalize_info(_info_from_local_profile())
		_local_info["player_options"] = po
		_send_player_info()
	lobby_changed.emit(lobby)
	_emit_bus("lobby_changed", [lobby])


func _on_refused_msg(data: Dictionary) -> void:
	var reason := str(data.get("reason", "refused"))
	if str(data.get("scope", "")) == "ready":
		_ready_wanted = false
		var gid := str(data.get("game_id", lobby.get("game_id", "")))
		var mine := _version_str((_local_info.get("games", {}) as Dictionary).get(gid, ""))
		ready_refused.emit(reason, _ready_text(reason, gid, mine, _version_str(data.get("game_version", ""))))
		game_message.emit(host_peer, data)
		return
	game_message.emit(host_peer, data)
	_refuse(reason)


func _on_clock_pong(data: Dictionary) -> void:
	var t1 := _clock_now()
	var t0 := float(data["t0"])
	var rtt := t1 - t0
	if rtt < 0.0:
		return
	var off := float(data["th"]) + rtt * 0.5 - t1
	_clock_samples.append([rtt, off])
	while _clock_samples.size() > CLOCK_SAMPLES:
		_clock_samples.pop_front()
	var best: Array = _clock_samples[0]
	for s: Variant in _clock_samples:
		if float((s as Array)[0]) < float(best[0]):
			best = s
	clock_rtt = float(best[0])
	clock_offset = float(best[1])


func _send_clock_ping() -> void:
	if role != Wl.CLIENT or not _in_room():
		return
	var gap := CLOCK_PING_FAST_S if _clock_samples.size() < 3 else CLOCK_PING_S
	_clock_next_at = _clock_now() + gap
	_send(host_peer, Protocol.game_msg("clock_ping", {"t0": _clock_now()}))


func _buffer_snapshot(data: Dictionary) -> bool:
	var seq := int(data["seq"])
	if not _latest_snapshot.is_empty():
		if str(_latest_snapshot.get("game_id", "")) != str(data["game_id"]):
			# Another game's snapshots never mix with these in the interpolation buffer.
			clear_snapshots()
		elif seq <= int(_latest_snapshot.get("seq", -1)):
			_count("stale_snapshots")
			return false
	Protocol.apply_game_int_fields(data, game_int_fields)
	var t := float(data["t"]) if (data.get("t") is float or data.get("t") is int) else host_time()
	_snapshots.append({"seq": seq, "t": t, "msg": data})
	while _snapshots.size() > maxi(snapshot_buffer_size, 1):
		_snapshots.pop_front()
	_latest_snapshot = data
	return true


func _send_player_info() -> void:
	_ensure_local_info()
	_send(host_peer, Protocol.game_msg("player_info", _local_info))


# --- lobby model ---------------------------------------------------------------------------

func _publish_lobby() -> void:
	if not is_authority() or local_peer == 0:
		return
	var humans: Array[int] = _session_players if session_started else _lobby_humans()
	if not session_started:
		while humans.size() + _bot_count > max_players and _bot_count > 0:
			_bot_options.erase(Bots.peer_id(_bot_count))
			_bot_count -= 1
	var players: Array = []
	var popts: Dictionary = {}
	var ready_flags: Dictionary = {}
	var trainers: Dictionary = {}
	var slot := 0
	for peer in humans:
		var entry := _human_entry(peer, slot)
		players.append(entry)
		var info: Dictionary = _infos.get(peer, {})
		popts[peer] = _resolve_player_options(info.get("player_options", {}))
		ready_flags[peer] = entry["ready"]
		trainers[peer] = entry["trainer"]
		slot += 1
	var bot_w := _effective_bot_ftp()
	for n in range(1, _bot_count + 1):
		var bs := Bots.make_slot(n, slot, float(bot_w), _scaling)
		var e := bs.to_dict()
		e.erase("options")
		e["ftp"] = roundi(bs.ftp)
		e["profile_color"] = ""
		e["ready"] = true
		e["connected"] = true
		e["game_ok"] = true
		e["game_issue"] = ""
		e["trainer"] = "bot"
		players.append(e)
		popts[bs.peer_id] = _resolve_player_options(_bot_options.get(bs.peer_id, {}))
		ready_flags[bs.peer_id] = true
		trainers[bs.peer_id] = "bot"
		slot += 1
	var settings := _settings.duplicate(true)
	settings["options"] = _options.duplicate(true)
	settings["bot_ftp"] = bot_w
	settings["max_players"] = max_players
	settings["min_players"] = min_players
	settings["bots_allowed"] = bots_allowed
	_lobby_seq += 1
	var msg := Protocol.game_msg("lobby_state", {
		"seq": _lobby_seq,
		"host": host_peer,
		"started": session_started,
		"game_id": _game_id,
		"game_version": _game_version,
		"content_id": _content_id,
		"scaling": _scaling,
		"settings": settings,
		"players": players,
		"player_options": popts,
		"ready_flags": ready_flags,
		"trainers": trainers,
	})
	_lobby_text = Protocol.encode(msg)
	lobby = Protocol.decode(_lobby_text)
	lobby_changed.emit(lobby)
	_emit_bus("lobby_changed", [lobby])
	if role == Wl.HOST and _in_room():
		_send_text(Wl.ALL_PEERS, "lobby_state", _lobby_text)


func _human_entry(peer: int, slot: int) -> Dictionary:
	var info: Dictionary = _infos.get(peer, {})
	var look := Wl.slot_look(slot)
	var issue := "" if peer == local_peer else _game_issue(peer)
	var ftp := float(info.get("ftp", 200.0))
	return {
		"peer_id": peer,
		"name": str(info.get("name", "Rider")),
		"slot_index": slot,
		"color": (look["color"] as Color).to_html(false),
		"shape": look["shape"],
		"pattern": look["pattern"],
		"hollow": look["hollow"],
		"profile_color": str(info.get("color", "")),
		"ftp": roundi(ftp),
		"ftp_verified": bool(info.get("ftp_verified", false)),
		"scaling_mode": _scaling,
		"p_eff_per_w": _p_eff_for(info),
		"rider_mass_kg": _mass_for(info),
		"preferred_cadence_rpm": float(info.get("preferred_cadence_rpm", 90.0)),
		"haptics_on": bool(info.get("haptics_on", true)),
		"haptic_intensity": float(info.get("haptic_intensity", 0.7)),
		"autopilot": bool(info.get("autopilot", false)),
		"is_bot": false,
		"ready": bool(_ready_flags.get(peer, false)) and issue == "",
		"connected": peer == local_peer or _connected_peers.has(peer),
		"game_ok": issue == "",
		"game_issue": issue,
		"trainer": str(info.get("trainer", "")),
	}


func _lobby_humans() -> Array[int]:
	var out: Array[int] = []
	for p in _join_order:
		if _infos.has(p) and (p == local_peer or _connected_peers.has(p)):
			out.append(p)
	return out


func _game_issue(peer: int) -> String:
	if _game_id == "":
		return ""
	var info: Dictionary = _infos.get(peer, {})
	var games: Variant = info.get("games", {})
	if not games is Dictionary or not (games as Dictionary).has(_game_id):
		return "missing_game"
	if _version_str((games as Dictionary)[_game_id]) != _game_version:
		return "version_mismatch"
	return ""


func _p_eff_for(info: Dictionary) -> float:
	var mode := _scaling
	if str(info.get("p_eff_mode", "")) == mode and info.has("p_eff_per_w"):
		return float(info["p_eff_per_w"])
	var by: Variant = info.get("p_eff_by_mode")
	if by is Dictionary and (by as Dictionary).has(mode):
		return float((by as Dictionary)[mode])
	var ftp := float(info.get("ftp", 200.0))
	match mode:
		Wl.RAW:
			return 1.0
		Wl.WKG:
			if info.has("weight_kg"):
				return EffortScaling.p_eff_per_w(Wl.WKG, ftp, float(info["weight_kg"]))
			return float(info.get("p_eff_per_w", 1.0))
		_:
			return EffortScaling.p_eff_per_w(Wl.FAIR_FTP, ftp, EffortScaling.REFERENCE_KG)


func _mass_for(info: Dictionary) -> float:
	var shared := info.has("weight_kg")
	return EffortScaling.rider_mass_kg(_scaling, float(info.get("weight_kg", 0.0)), shared)


func _effective_bot_ftp() -> int:
	if _bot_ftp > 0:
		return _bot_ftp
	var info: Dictionary = _infos.get(local_peer, _local_info)
	return roundi(float(info.get("ftp", 200.0)))


func _has_manifest() -> bool:
	return _manifests.has(_game_id)


func _apply_manifest_limits() -> void:
	if not _has_manifest():
		max_players = NetMessages.MAX_PEERS
		min_players = 1
		bots_allowed = true
		return
	var m: Dictionary = _manifests[_game_id]
	max_players = clampi(int(m.get("max_players", NetMessages.MAX_PEERS)), 1, NetMessages.MAX_PEERS)
	min_players = clampi(int(m.get("min_players", 1)), 1, max_players)
	bots_allowed = bool(m.get("bots", true))
	if not bots_allowed:
		_bot_count = 0
		_bot_options.clear()


## {id: default} for the current game's "options" or "player_options" ({} without manifest).
func _option_defaults(field: String) -> Dictionary:
	var out: Dictionary = {}
	if not _has_manifest():
		return out
	var entries: Variant = (_manifests[_game_id] as Dictionary).get(field, [])
	if entries is Array:
		for e: Variant in entries:
			if e is Dictionary and (e as Dictionary).has("id"):
				out[str((e as Dictionary)["id"])] = (e as Dictionary).get("default")
	return out


func _resolve_player_options(values: Variant) -> Dictionary:
	var out := _option_defaults("player_options")
	if not values is Dictionary:
		return out
	var known := _has_manifest()
	for k: Variant in (values as Dictionary).keys():
		if not known or out.has(k):
			out[k] = (values as Dictionary)[k]
	return out


func _require_authority(what: String) -> bool:
	if is_authority():
		return true
	push_warning("NetSession.%s: only the host changes the lobby" % what)
	return false


# --- player info ---------------------------------------------------------------------------

func _ensure_local_info() -> void:
	if not _local_info.is_empty():
		return
	var profile := _settings_profile()
	if profile != null:
		_local_info = _normalize_info(player_info_from_profile(profile, _scaling, _registry_games()))
	else:
		_local_info = _normalize_info({"games": _registry_games()})


func _info_from_local_profile() -> Dictionary:
	var mode := _scaling if is_authority() else str(lobby.get("scaling", Wl.FAIR_FTP))
	var po: Variant = _local_info.get("player_options", {})
	var games := _local_profile_games if not _local_profile_games.is_empty() else _registry_games()
	var info := player_info_from_profile(_local_profile, mode, games,
		po if po is Dictionary else {}, _local_profile_trainer)
	return info


static func _normalize_info(info: Dictionary) -> Dictionary:
	var d := {
		"name": "Rider", "color": "d55e00", "ftp": 200, "ftp_verified": false,
		"p_eff_per_w": 1.25, "preferred_cadence_rpm": 90.0, "haptics_on": true,
		"haptic_intensity": 0.7, "autopilot": false, "player_options": {}, "games": {},
	}
	for k: Variant in info.keys():
		if k == "type" or k == "v":
			continue
		var v: Variant = info[k]
		if v is Color:
			v = (v as Color).to_html(false)
		elif v is Dictionary or v is Array:
			v = v.duplicate(true)
		d[k] = v
	if not d["player_options"] is Dictionary:
		d["player_options"] = {}
	if not d["games"] is Dictionary:
		d["games"] = {}
	for b in ["ftp_verified", "haptics_on", "autopilot"]:
		d[b] = bool(d[b])
	for f in ["ftp", "p_eff_per_w", "preferred_cadence_rpm", "haptic_intensity"]:
		if not (d[f] is int or d[f] is float):
			d[f] = float(str(d[f])) if str(d[f]).is_valid_float() else 0.0
	d["name"] = str(d["name"])
	return d


## The game registry: `registry`, else the GameRegistry autoload (null without one).
func _registry() -> Node:
	if registry != null and is_instance_valid(registry):
		return registry
	return get_node_or_null("/root/GameRegistry") if is_inside_tree() else null


## {id: version} of the games the registry lists ({} without one).
func _registry_games() -> Dictionary:
	var out: Dictionary = {}
	var reg := _registry()
	if reg == null or not reg.has_method("games"):
		return out
	var list: Variant = reg.call("games")
	if list is Array:
		for m: Variant in list:
			if m is Dictionary and (m as Dictionary).has("id"):
				out[str((m as Dictionary)["id"])] = _version_str((m as Dictionary).get("version", ""))
	return out


## A game's manifest from the registry ({} if unknown or no registry).
func _registry_manifest(game_id: String) -> Dictionary:
	var reg := _registry()
	if reg == null or not reg.has_method("manifest"):
		return {}
	var m: Variant = reg.call("manifest", game_id)
	return (m as Dictionary).duplicate(true) if m is Dictionary else {}


func _settings_profile() -> RiderProfile:
	if not is_inside_tree():
		return null
	var s := get_node_or_null("/root/Settings")
	if s == null:
		return null
	var p: Variant = s.get("profile")
	return p as RiderProfile if p is RiderProfile else null


static func _version_str(v: Variant) -> String:
	if v is float and is_finite(float(v)) and float(v) == floorf(float(v)):
		return str(int(v))
	return str(v)


static func _ready_text(reason: String, game_id: String, mine: String, theirs: String) -> String:
	var key := "NET_READY_" + reason.to_upper()
	var t := String(TranslationServer.translate(key))
	if t == key or t == "":
		t = reason
	return t.format({"game": game_id, "mine": mine, "theirs": theirs})


# --- sending -------------------------------------------------------------------------------

func _send(to: int, data: Dictionary) -> bool:
	var d := data
	if not d.has("v"):
		d = data.duplicate()
		d["v"] = NetMessages.VERSION
	var err := Protocol.check_game(d)
	if err != "":
		push_error("NetSession: refusing to send an invalid \"%s\" message (%s)" % [str(d.get("type", "")), err])
		_count("invalid_sends")
		return false
	if not _in_room():
		_count("dropped_offline")
		return false
	var type: String = d["type"]
	if type == "directive" and role == Wl.HOST and to > 0 and COALESCED_KINDS.has(str(d["kind"])):
		return _coalesce_send(to, str(d["kind"]), d)
	if to > 0:
		_flush_coalesced(to, false)
	return _send_text(to, type, Protocol.encode(d))


func _send_text(to: int, type: String, text: String) -> bool:
	if not _in_room():
		_count("dropped_offline")
		return false
	var size := text.to_utf8_buffer().size() + ("{\"t\":\"msg\",\"to\":%d,\"d\":}" % to).length()
	if size > NetMessages.MAX_MESSAGE_BYTES:
		push_warning("NetSession: \"%s\" message of %d bytes is over the %d-byte limit; dropped"
			% [type, size, NetMessages.MAX_MESSAGE_BYTES])
		_count("oversize_dropped")
		if type == "snapshot":
			_count("oversize_snapshots")
		return false
	if transport is RelayClientTransport:
		(transport as RelayClientTransport).send_encoded(to, text)
	else:
		var parsed: Variant = Protocol.parse_json(text)
		transport.send(to, parsed if parsed is Dictionary else {})
	_count("sent")
	if type == "snapshot" and role == Wl.HOST:
		_latest_snapshot_text = text
	return true


func _coalesce_send(to: int, kind: String, d: Dictionary) -> bool:
	var key := "%d:%s" % [to, kind]
	var now := _clock_now()
	if not _co_pending.has(key) and (not _co_last.has(key) or now - float(_co_last[key]) >= COALESCE_S - 1e-9):
		_co_last[key] = now
		return _send_text(to, "directive", Protocol.encode(d))
	if _co_pending.has(key):
		_count("coalesced")
		var held: Array = _co_pending[key]
		held[1] = d.duplicate(true)
		return true
	# [peer, data, poll and time when it started waiting]
	_co_pending[key] = [to, d.duplicate(true), _polls, now]
	return true


## Flush pending coalesced directives: for one peer (before another message to it), or
## all due ones (peer -1, due_only) from poll(). A pending one is due once 100 ms passed
## since the last send of its kind, or, if this private session's clock stands still (only
## polled after a set_time()), FROZEN_CLOCK_POLLS polls after it started waiting. The
## autoload's clock always moves with _process, so it never takes the fallback (several
## polls inside one frame share one time).
func _flush_coalesced(peer: int, due_only: bool) -> void:
	if _co_pending.is_empty():
		return
	var now := _clock_now()
	for key: Variant in _co_pending.keys():
		var e: Array = _co_pending[key]
		var to := int(e[0])
		if peer >= 0 and to != peer:
			continue
		if due_only:
			var last := float(_co_last.get(key, -INF))
			var frozen := not auto_poll and now <= float(e[3]) \
				and _polls - int(e[2]) >= FROZEN_CLOCK_POLLS
			if now - last < COALESCE_S - 1e-9 and not frozen:
				continue
		_co_pending.erase(key)
		_co_last[key] = now
		_send_text(to, "directive", Protocol.encode(e[1]))


func _drop_coalesced(peer: int) -> void:
	for key: Variant in _co_pending.keys():
		if int((_co_pending[key] as Array)[0]) == peer:
			_co_pending.erase(key)


func _deliver_self(data: Dictionary) -> void:
	var d := data
	if not d.has("v"):
		d = data.duplicate()
		d["v"] = NetMessages.VERSION
	if Protocol.check_game(d) != "":
		push_error("NetSession: refusing to deliver an invalid \"%s\" message" % str(d.get("type", "")))
		_count("invalid_sends")
		return
	_self_inbox.append(Protocol.encode(d))


func _drain_self_inbox() -> void:
	if _self_inbox.is_empty():
		return
	var batch := _self_inbox
	_self_inbox = []
	for text in batch:
		var d := Protocol.decode(text)
		if not d.is_empty():
			_on_message(local_peer, d)


# --- connection helpers ------------------------------------------------------------------

func _ensure_transport() -> void:
	if transport != null:
		return
	var rt := RelayTransport.new()
	rt.url = relay_url if relay_url != "" else RelayTransport.default_url(self)
	use_transport(rt)


func _disconnect_transport(t: Transport) -> void:
	if t.connected.is_connected(_on_connected):
		t.connected.disconnect(_on_connected)
	if t.disconnected.is_connected(_on_disconnected):
		t.disconnected.disconnect(_on_disconnected)
	if t.peer_joined.is_connected(_on_peer_joined):
		t.peer_joined.disconnect(_on_peer_joined)
	if t.peer_left.is_connected(_on_peer_left):
		t.peer_left.disconnect(_on_peer_left)
	if t.message.is_connected(_on_message):
		t.message.disconnect(_on_message)
	if t.has_signal("protocol_mismatch") and t.is_connected("protocol_mismatch", _on_protocol_mismatch):
		t.disconnect("protocol_mismatch", _on_protocol_mismatch)
	if t.has_signal("relay_error") and t.is_connected("relay_error", _on_relay_error):
		t.disconnect("relay_error", _on_relay_error)


func _in_room() -> bool:
	return transport != null and transport.is_open() and not offline


## Leave the room, or cancel a create/join (or a rejoin) still in flight.
func _leave_transport() -> void:
	if transport == null:
		return
	if transport.is_open() or transport is RelayClientTransport:
		transport.leave()


func _reconnect_step() -> void:
	if not _reconnect_pending or transport == null:
		return
	var now := _clock_now()
	if now - _reconnect_started > float(NetMessages.RECONNECT_TOKEN_S):
		_reconnect_pending = false
		_end("dropped", STATE_ERROR)
		return
	if _reconnect_in_flight or now < _reconnect_at:
		return
	var idx := mini(_reconnect_attempts + 1, RECONNECT_BACKOFF_S.size() - 1)
	_reconnect_attempts += 1
	_reconnect_at = now + RECONNECT_BACKOFF_S[idx] if auto_reconnect else INF
	_reconnect_in_flight = true
	transport.join(room_code, _token)


func _refuse(reason: String) -> void:
	refusal_reason = reason
	_explicit_leave = true
	_reconnect_pending = false
	_leave_transport()
	_clear_token_file()
	_reset_room_state()
	_set_state(STATE_ERROR, reason)
	refused.emit(reason)
	_emit_bus("session_refused", [reason])


## The session ended (host_left, dropped for good): graceful, like a refusal.
func _end(reason: String, end_state: String) -> void:
	refusal_reason = reason
	_explicit_leave = true
	_reconnect_pending = false
	_leave_transport()
	_clear_token_file()
	_reset_room_state()
	_set_state(end_state, reason)
	refused.emit(reason)
	_emit_bus("session_refused", [reason])


func _reset_room_state() -> void:
	role = ""
	local_peer = 0
	host_peer = Wl.HOST_PEER
	room_code = ""
	session_started = false
	lobby = {}
	_lobby_text = ""
	_token = ""
	_ever_connected = false
	_reconnect_pending = false
	_reconnect_in_flight = false
	_infos.clear()
	_join_order.clear()
	_connected_peers.clear()
	_ready_flags.clear()
	_refused_peers.clear()
	_session_players.clear()
	_snapshots.clear()
	_latest_snapshot = {}
	_latest_snapshot_text = ""
	_co_last.clear()
	_co_pending.clear()
	_self_inbox.clear()
	_clock_samples.clear()
	clock_offset = 0.0
	clock_rtt = -1.0
	latest_roster = {}
	_ready_wanted = false


func _set_state(s: String, detail: String) -> void:
	state = s
	state_changed.emit(s, detail)
	_emit_bus("net_state_changed", [s, detail])


func _bus() -> WlEventBus:
	if bus == null and is_inside_tree():
		bus = get_node_or_null("/root/EventBus") as WlEventBus
	return bus


func _emit_bus(sig: String, args: Array) -> void:
	var b := _bus()
	if b == null:
		return
	match args.size():
		1:
			b.emit_signal(sig, args[0])
		2:
			b.emit_signal(sig, args[0], args[1])
		_:
			b.emit_signal(sig)


func _clock_now() -> float:
	return _now_s if _ticked else _polls * Wl.SIM_DT


func _count(key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1


func _reset_stats() -> void:
	stats = {"sent": 0, "received": 0, "dropped_offline": 0, "oversize_dropped": 0,
		"oversize_snapshots": 0, "stale_snapshots": 0, "invalid_sends": 0, "ignored": 0,
		"intents_dropped": 0, "coalesced": 0}


# --- persistence ---------------------------------------------------------------------------

func _token_file() -> String:
	return token_path if token_path != "" else Paths.reconnect_token_path()


func _recent_rooms_path() -> String:
	return recent_rooms_file if recent_rooms_file != "" else Paths.recent_rooms_path()


func _save_token() -> void:
	if not persist_token or room_code == "" or _token == "":
		return
	_write_json(_token_file(), {"code": room_code, "token": _token, "peer": local_peer, "role": role})


func _load_token_for(code: String) -> String:
	if not persist_token:
		return ""
	var data: Variant = _read_json(_token_file())
	if data is Dictionary and RoomCode.normalize(str((data as Dictionary).get("code", ""))) == code:
		return str((data as Dictionary).get("token", ""))
	return ""


func _clear_token_file() -> void:
	if not persist_token:
		return
	var path := _token_file()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _record_recent_room() -> void:
	if not persist_token or room_code == "":
		return
	var rooms: Array = []
	for r: Variant in recent_rooms():
		if r is Dictionary and str((r as Dictionary).get("code", "")) != room_code:
			rooms.append(r)
	rooms.push_front({"code": room_code, "role": Wl.HOST if transport.is_host() else Wl.CLIENT})
	while rooms.size() > RECENT_ROOMS_MAX:
		rooms.pop_back()
	_write_json(_recent_rooms_path(), rooms)


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return Protocol.parse_json(f.get_as_text())


static func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("NetSession: can't write %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
