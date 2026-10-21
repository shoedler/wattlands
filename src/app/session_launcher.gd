class_name AppSessionLauncher
extends RefCounted
## Builds the GameHost config for a session (BRIEF 3.6) from the lobby (HOST, SOLO) or from
## the host's session_start (CLIENT). Shared by the session screen and the scripted peer.
##   players      NetSession.lobby_slots() (SOLO falls back to the profile's own slot)
##   local riders TrainerService.local_rider() for this machine's rider, plus one LocalRider per
##                bot on the host or in SOLO, each riding MockTrainer.from_spec(Bots.RIDER_SPEC,
##                bot FTP) with no recorder
##   net          NetSession (null in SOLO), bus EventBus, options from lobby_state.settings
## The client's GameHost is created when session_start arrives, so the config carries that
## message's players, seed, options and scaling (and the message itself as "session_start").

const SEED_MASK := 0x3FFFFFFF

var services: AppServices = null
## Bot riders and devices this launcher created (released by release()).
var bot_riders: Array[LocalRider] = []
var bot_devices: Array[TrainerDevice] = []
## A rider the launcher created because TrainerService had none (released by release()).
var own_rider: LocalRider = null
var error: String = ""


static func create(p_services: AppServices) -> AppSessionLauncher:
	var l := AppSessionLauncher.new()
	l.services = p_services
	return l


## The config for GameHost.setup(), or {} with `error` set. params: game_id, content_id, seed,
## session_start (CLIENT), sim_speed, record_rides, realtime (default true: the GameHost
## advances its SimClock from _process, also in headless app runs such as scripted peers;
## tests pass false and step it themselves).
func build_config(
	role: String, params: Dictionary, view_parent: Node, hud_parent: Node, headless: bool
) -> Dictionary:
	error = ""
	var net := services.net
	var lobby: Dictionary = net.lobby if net != null else {}
	var registry := services.registry
	var profile := services.profile()
	var game_id := ""
	var content_id := ""
	var scaling := Wl.FAIR_FTP
	var options: Dictionary = {}
	var players: Array[PlayerSlot] = []
	var seed := 0
	var ss: Dictionary = params.get("session_start", {})
	if role == Wl.CLIENT and not ss.is_empty():
		game_id = str(ss.get("game_id", ""))
		content_id = str(ss.get("content_id", ""))
		scaling = str(ss.get("scaling", Wl.FAIR_FTP))
		seed = int(ss.get("seed", 0))
		var o: Variant = ss.get("options", {})
		options = (o as Dictionary).duplicate(true) if o is Dictionary else {}
		for p: Variant in ss.get("players", []):
			if p is Dictionary:
				players.append(PlayerSlot.from_dict(p as Dictionary))
	else:
		game_id = str(params.get("game_id", lobby.get("game_id", "")))
		content_id = str(params.get("content_id", lobby.get("content_id", "")))
		scaling = str(lobby.get("scaling", _setting("scaling_mode", Wl.FAIR_FTP)))
		options = AppLobbyModel.resolve_game_options(
			registry, game_id, AppLobbyModel.game_options(lobby)
		)
		if net != null:
			players = net.lobby_slots()
		if role == Wl.CLIENT:
			seed = int(AppLobbyModel.settings_of(lobby).get("seed", 0))
		elif params.has("seed"):
			seed = int(params["seed"])
		elif CmdLine.has("seed"):
			seed = CmdLine.get_int("seed", 0)
		else:
			seed = SeededRng.derive(services.utc_now(), "%s|%s" % [game_id, content_id]) & SEED_MASK
	if not Wl.SCALING_MODES.has(scaling):
		scaling = Wl.FAIR_FTP
	if game_id == "" or registry == null or not registry.has_game(game_id):
		error = "APP_ERR_NO_GAME"
		return {}
	var manifest := registry.manifest(game_id)
	if content_id == "":
		content_id = str(manifest.get("default_content", ""))
	var local_peer := 1
	if net != null and net.local_peer > 0:
		local_peer = net.local_peer
	if players.is_empty() and role == Wl.SOLO:
		var own := profile.to_slot(local_peer, scaling)
		own.apply_look(0)
		players.append(own)
	if players.is_empty():
		error = "APP_ERR_NO_PLAYERS"
		return {}
	# ctx.players is sorted by slot_index on every peer (OWNERSHIP CTX1); indices are unique, so
	# the order is the same whatever order the lobby or session_start listed them in.
	players.sort_custom(
		func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.slot_index < b.slot_index
	)
	for slot in players:
		var lobby_opts := AppLobbyModel.player_options_of(lobby, slot.peer_id)
		var merged := lobby_opts
		for k: Variant in slot.options.keys():
			merged[k] = slot.options[k]
		slot.options = AppLobbyModel.resolve_player_options(registry, game_id, merged)
	var local_slot: PlayerSlot = null
	for slot in players:
		if slot.peer_id == local_peer and not slot.is_bot:
			local_slot = slot
	if local_slot == null:
		error = "APP_ERR_NO_LOCAL_SLOT"
		return {}
	if role == Wl.CLIENT:
		# BRIEF 3.3 ("ERG targets always come from each rider's own FTP") and 4.6.7 (each client
		# validates and clamps locally): a client's slot came from the host (session_start, or
		# lobby_state on a rejoin), so the values its governor works from are the rider's own
		# (W3 SAF-1).
		apply_own_profile(local_slot, profile)
	var device: TrainerDevice = services.trainer.device() if services.trainer != null else null
	if device == null:
		error = "APP_ERR_NO_TRAINER"
		return {}
	var utc := services.utc_now()
	var rider: LocalRider = services.trainer.local_rider()
	if rider == null:
		rider = services.make_rider()
		own_rider = rider
	(
		rider
		. setup(
			local_peer,
			profile,
			local_slot,
			device,
			{
				"multiplayer": role != Wl.SOLO,
				"scaling_mode": scaling,
				"record": bool(params.get("record_rides", true)),
				"game_id": game_id,
				"content_id": content_id,
				"utc_start_unix": utc,
				"seed": seed,
				"skip_warmup": profile.skip_warmup,
			}
		)
	)
	var riders: Dictionary = {local_peer: rider}
	if role != Wl.CLIENT:
		for slot in players:
			if slot.is_bot:
				riders[slot.peer_id] = make_bot_rider(
					slot, role, scaling, game_id, content_id, seed
				)
	_remember_last(game_id, content_id)
	var sim_speed := effective_sim_speed(
		device, float(params.get("sim_speed", CmdLine.get_float("sim-speed", 1.0)))
	)
	var config := {
		"game_id": game_id,
		"content_id": content_id,
		"seed": seed,
		"role": role,
		"players": players,
		"local_riders": riders,
		"local_peer": local_peer,
		"net": net if role != Wl.SOLO else null,
		"bus": services.bus,
		"options": options,
		"scaling_mode": scaling,
		"sim_speed": sim_speed,
		"headless": headless,
		"realtime": bool(params.get("realtime", true)),
		"view_parent": view_parent,
		"hud_parent": hud_parent,
		"record_rides": bool(params.get("record_rides", true)),
		"report": false,
	}
	if services.sfx != null:
		# The GameHost runs the metronome on rendering peers (band centre, else the preferred
		# cadence); the session screen uses the same node.
		config["sfx"] = services.sfx
	if not ss.is_empty():
		config["session_start"] = ss.duplicate(true)
	return config


## Overwrite the safety-relevant fields of this machine's own slot with the rider's profile: FTP
## (the governor's absolute watt basis), ftp_verified (the 0.85 unverified factor), haptics on/off
## and intensity (BRIEF 3.2, 4.6.6). Whatever the host sent for them is ignored.
static func apply_own_profile(slot: PlayerSlot, profile: RiderProfile) -> void:
	if slot == null or profile == null:
		return
	slot.ftp = profile.ftp_w
	slot.ftp_verified = profile.ftp_verified
	slot.haptics_on = profile.haptics_on
	slot.haptic_intensity = clampf(profile.haptic_intensity_pct / 100.0, 0.0, 1.0)


## The session clock's speed: --sim-speed (or params.sim_speed) only drives a MockTrainer. With a
## real trainer every governor time rule (slew, write rate, rescue, coasting, warm-up, haptics)
## runs on platform time, so a speed other than 1 would scale them in wall time (BRIEF 4.5,
## 4.6): the session then runs at 1 and a warning says the flag was ignored (W3 SAF-3).
## TrainerService applies the same rule to its menu clock (trainer area).
static func effective_sim_speed(device: TrainerDevice, requested: float) -> float:
	var spd := maxf(requested, 0.01)
	if device is MockTrainer or is_equal_approx(spd, 1.0):
		return spd
	push_warning(
		(
			"AppSessionLauncher: --sim-speed=%s ignored: the trainer is not a MockTrainer, so the session runs at 1"
			% str(requested)
		)
	)
	return 1.0


## The messages to re-emit on NetSession.game_message right after GameHost.start(), so the
## new GameHost sees what opened the session: a client's GameHost connects to game_message in
## setup(), after the session_start (or, on a rejoin, the plan/phase/snapshot) that made the
## shell create it was already delivered. params.replay as given, else session_start from the
## host. Each entry: {"from": int, "data": Dictionary}.
static func replay_messages(params: Dictionary, net: WlNetSession) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if net == null:
		return out
	var host_peer := net.host_peer if net.host_peer > 0 else Wl.HOST_PEER
	for r: Variant in params.get("replay", []):
		if r is Dictionary:
			var d: Variant = (r as Dictionary).get("data", {})
			out.append(
				{
					"from": int((r as Dictionary).get("from", host_peer)),
					"data": d if d is Dictionary else {}
				}
			)
	var ss: Variant = params.get("session_start", {})
	if out.is_empty() and ss is Dictionary and not (ss as Dictionary).is_empty():
		var msg := (ss as Dictionary).duplicate(true)
		if not msg.has("type"):
			msg["type"] = "session_start"
		out.append({"from": host_peer, "data": msg})
	return out


## A bot's LocalRider: MockTrainer Bots.RIDER_SPEC ("erg:compliance=1.0+band": erg at
## compliance 1.0 plus the band cadence policy) with the bot FTP, no recorder.
func make_bot_rider(
	slot: PlayerSlot, role: String, scaling: String, game_id: String, content_id: String, seed: int
) -> LocalRider:
	var n := absi(slot.peer_id)
	var bot_seed := SeededRng.derive(seed, "bot%d" % n) & SEED_MASK
	var device := MockTrainer.from_spec(Bots.RIDER_SPEC, slot.ftp, {"seed": bot_seed})
	var r := services.make_rider()
	r.is_bot = true
	(
		r
		. setup(
			slot.peer_id,
			Bots.make_profile(n, slot.ftp),
			slot,
			device,
			{
				"multiplayer": role != Wl.SOLO,
				"scaling_mode": scaling,
				"record": false,
				"game_id": game_id,
				"content_id": content_id,
				"utc_start_unix": 0,
				"seed": bot_seed,
				"skip_warmup": false,
			}
		)
	)
	bot_riders.append(r)
	bot_devices.append(device)
	return r


## Free what this launcher created and nobody adopted (riders and devices without a parent).
func release() -> void:
	for r in bot_riders:
		if is_instance_valid(r) and r.get_parent() == null:
			r.free()
	for d in bot_devices:
		if is_instance_valid(d) and d.get_parent() == null:
			d.free()
	if own_rider != null and is_instance_valid(own_rider) and own_rider.get_parent() == null:
		own_rider.free()
	bot_riders.clear()
	bot_devices.clear()
	own_rider = null


func _setting(key: String, default: Variant) -> Variant:
	if services.settings == null:
		return default
	return services.settings.get_value(key, default)


func _remember_last(game_id: String, content_id: String) -> void:
	if services.settings == null:
		return
	services.settings.set_value("last_game", game_id)
	services.settings.set_value("last_content", content_id)
	services.settings.save_settings()
