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
## session_start (CLIENT), sim_speed, record_rides.
func build_config(role: String, params: Dictionary, view_parent: Node, hud_parent: Node, headless: bool) -> Dictionary:
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
		options = AppLobbyModel.resolve_game_options(registry, game_id, AppLobbyModel.game_options(lobby))
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
	var device: TrainerDevice = services.trainer.device() if services.trainer != null else null
	if device == null:
		error = "APP_ERR_NO_TRAINER"
		return {}
	var utc := services.utc_now()
	var rider: LocalRider = services.trainer.local_rider()
	if rider == null:
		rider = services.make_rider()
		own_rider = rider
	rider.setup(local_peer, profile, local_slot, device, {
		"multiplayer": role != Wl.SOLO, "scaling_mode": scaling, "record": bool(params.get("record_rides", true)),
		"game_id": game_id, "content_id": content_id, "utc_start_unix": utc, "seed": seed,
		"skip_warmup": profile.skip_warmup,
	})
	var riders: Dictionary = {local_peer: rider}
	if role != Wl.CLIENT:
		for slot in players:
			if slot.is_bot:
				riders[slot.peer_id] = make_bot_rider(slot, role, scaling, game_id, content_id, seed)
	_remember_last(game_id, content_id)
	var sim_speed := float(params.get("sim_speed", CmdLine.get_float("sim-speed", 1.0)))
	var config := {
		"game_id": game_id, "content_id": content_id, "seed": seed, "role": role,
		"players": players, "local_riders": riders, "local_peer": local_peer,
		"net": net if role != Wl.SOLO else null, "bus": services.bus, "options": options,
		"scaling_mode": scaling, "sim_speed": maxf(sim_speed, 0.01), "headless": headless,
		"view_parent": view_parent, "hud_parent": hud_parent,
		"record_rides": bool(params.get("record_rides", true)), "report": false,
	}
	if not ss.is_empty():
		config["session_start"] = ss.duplicate(true)
	return config


## A bot's LocalRider: MockTrainer erg at compliance 1.0 with the bot FTP, no recorder.
func make_bot_rider(slot: PlayerSlot, role: String, scaling: String, game_id: String, content_id: String, seed: int) -> LocalRider:
	var n := absi(slot.peer_id)
	var bot_seed := SeededRng.derive(seed, "bot%d" % n) & SEED_MASK
	var device := MockTrainer.from_spec(Bots.RIDER_SPEC, slot.ftp, {"seed": bot_seed})
	var r := services.make_rider()
	r.is_bot = true
	r.setup(slot.peer_id, Bots.make_profile(n, slot.ftp), slot, device, {
		"multiplayer": role != Wl.SOLO, "scaling_mode": scaling, "record": false,
		"game_id": game_id, "content_id": content_id, "utc_start_unix": 0, "seed": bot_seed,
		"skip_warmup": false,
	})
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
