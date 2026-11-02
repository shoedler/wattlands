class_name AppLobbyModel
extends RefCounted
## Pure helpers that read the host's lobby_state (BRIEF 5.5) and build this rider's
## player_info. lobby_state: players, trainer status, ready flags, game_id, game_version,
## content_id, scaling, settings (the game's options under "options", "bot_ftp") and each
## player's player_options. Peer-keyed dictionaries have int keys after Protocol.decode(); a
## lobby built locally may use either, so every lookup accepts both.

const MISSING_GAME := "missing_game"
const VERSION_MISMATCH := "version_mismatch"


## This rider's player_info (BRIEF 5.5): name, color, FTP, ftp_verified, p_eff_per_w, weight
## only if opted in, preferred cadence, haptics, Autopilot, player_options, installed games.
## Extra keys: "trainer" (local trainer status for the lobby cards) and "haptic_intensity".
## autopilot: the lobby's per-session Autopilot toggle (BRIEF 3.5); null uses the profile default.
static func player_info(
	profile: RiderProfile,
	scaling: String,
	player_options: Dictionary,
	games: Dictionary,
	trainer_status: String = "",
	autopilot: Variant = null
) -> Dictionary:
	var info := {
		"name": profile.display_name,
		"color": profile.color.to_html(false),
		"ftp": profile.ftp_w,
		"ftp_verified": profile.ftp_verified,
		"p_eff_per_w": profile.p_eff_per_w(scaling),
		"preferred_cadence_rpm": profile.preferred_cadence_rpm,
		"haptics_on": profile.haptics_on,
		"haptic_intensity": profile.haptic_intensity_pct / 100.0,
		"autopilot": profile.autopilot_default if autopilot == null else bool(autopilot),
		"player_options": player_options.duplicate(true),
		"games": games.duplicate(true),
		"trainer": trainer_status,
		"app": WlNetSession.app_version(),
	}
	if profile.share_weight:
		info["weight_kg"] = profile.weight_kg
	return info


## {id: version} of every valid game in the registry.
static func installed_games(registry: WlGameRegistry) -> Dictionary:
	var out: Dictionary = {}
	if registry == null:
		return out
	for m: Dictionary in registry.games():
		out[str(m.get("id", ""))] = str(m.get("version", ""))
	return out


## Value of a peer-keyed dictionary field (int or string keys).
static func peer_value(
	lobby: Dictionary, field: String, peer: int, default: Variant = null
) -> Variant:
	var d: Variant = lobby.get(field, {})
	if not (d is Dictionary):
		return default
	var dict := d as Dictionary
	if dict.has(peer):
		return dict[peer]
	if dict.has(str(peer)):
		return dict[str(peer)]
	if dict.has(float(peer)):
		return dict[float(peer)]
	return default


## This peer's entry in lobby.players ({} when it has none).
static func player_entry(lobby: Dictionary, peer: int) -> Dictionary:
	var players: Variant = lobby.get("players", [])
	if players is Array:
		for e: Variant in players:
			if e is Dictionary and int((e as Dictionary).get("peer_id", 0)) == peer:
				return e as Dictionary
	return {}


static func is_ready(lobby: Dictionary, peer: int) -> bool:
	return bool(peer_value(lobby, "ready_flags", peer, false))


static func trainer_status(lobby: Dictionary, peer: int) -> String:
	var v: Variant = peer_value(lobby, "trainers", peer, "")
	return str(v) if v != null else ""


static func player_options_of(lobby: Dictionary, peer: int) -> Dictionary:
	var v: Variant = peer_value(lobby, "player_options", peer, {})
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}


static func settings_of(lobby: Dictionary) -> Dictionary:
	var s: Variant = lobby.get("settings", {})
	return s as Dictionary if s is Dictionary else {}


## The host's game options (lobby_state.settings.options).
static func game_options(lobby: Dictionary) -> Dictionary:
	var o: Variant = settings_of(lobby).get("options", {})
	return (o as Dictionary).duplicate(true) if o is Dictionary else {}


static func bot_ftp(lobby: Dictionary, default: float) -> float:
	var v: Variant = settings_of(lobby).get("bot_ftp", null)
	return float(v) if v != null else default


static func humans(slots: Array[PlayerSlot]) -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for s in slots:
		if not s.is_bot:
			out.append(s)
	return out


static func bots(slots: Array[PlayerSlot]) -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for s in slots:
		if s.is_bot:
			out.append(s)
	return out


## "" when this peer can play the lobby's game, MISSING_GAME or VERSION_MISMATCH otherwise.
static func game_problem(registry: WlGameRegistry, lobby: Dictionary) -> String:
	var gid := str(lobby.get("game_id", ""))
	if gid == "":
		return ""
	if registry == null or not registry.has_game(gid):
		return MISSING_GAME
	var want := str(lobby.get("game_version", ""))
	var have := str(registry.manifest(gid).get("version", ""))
	if want != "" and have != want:
		return VERSION_MISMATCH
	return ""


## The folder (under Paths.user_dir()) for a rider's own .zwo workouts (BRIEF 3.7 Workout
## Director): every *.zwo in it is offered as content "zwo:<absolute path>" by a game whose
## game.json lists the "zwo" content scheme.
const WORKOUTS_DIR := "workouts"
const ZWO_SCHEME := "zwo"


## The rider's .zwo folder (absolute); created when missing.
static func workouts_dir() -> String:
	var d := Paths.user_dir().path_join(WORKOUTS_DIR)
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d


## True when the game accepts "zwo:<path>" content (content_schemes in its game.json).
static func accepts_zwo(manifest: Dictionary) -> bool:
	var schemes: Variant = manifest.get("content_schemes", [])
	return schemes is Array and (schemes as Array).has(ZWO_SCHEME)


## "zwo:<absolute path>" for every *.zwo file in workouts_dir(), sorted by file name; [] for a
## game without the zwo scheme.
static func user_zwo_contents(manifest: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not accepts_zwo(manifest):
		return out
	var dir := workouts_dir()
	var files := Array(DirAccess.get_files_at(dir))
	files.sort_custom(
		func(a: Variant, b: Variant) -> bool: return str(a).naturalnocasecmp_to(str(b)) < 0
	)
	for f: Variant in files:
		if str(f).get_extension().to_lower() == ZWO_SCHEME:
			out.append(ZWO_SCHEME + ":" + dir.path_join(str(f)))
	return out


## True when `content_id` may be picked for the game in this app: one of its contents, or a
## "zwo:<path>" whose file exists here, for a game with the zwo scheme.
static func content_available(manifest: Dictionary, content_id: String) -> bool:
	if content_id == "":
		return false
	if (manifest.get("contents", []) as Array).has(content_id):
		return true
	if content_id.begins_with(ZWO_SCHEME + ":") and accepts_zwo(manifest):
		return FileAccess.file_exists(content_id.substr(ZWO_SCHEME.length() + 1))
	return false


## The content's label: <ID>_CONTENT_<CONTENT ID> if that key exists, else the bare id. A
## rider's own .zwo shows its file name (APP_CONTENT_ZWO).
static func content_label(game_id: String, content_id: String) -> String:
	if content_id.begins_with(ZWO_SCHEME + ":"):
		var file := (
			content_id.substr(ZWO_SCHEME.length() + 1).replace("\\", "/").get_file().get_basename()
		)
		return String(TranslationServer.translate("APP_CONTENT_ZWO")).format([file])
	var key := "%s_CONTENT_%s" % [game_id.to_upper(), content_id.to_upper()]
	var t := String(TranslationServer.translate(key))
	return content_id if t == key else t


## Bots may be added: the game allows bots and there is a free slot.
static func can_add_bot(manifest: Dictionary, slot_count: int) -> bool:
	return bool(manifest.get("bots", false)) and slot_count < int(manifest.get("max_players", 1))


static func max_players(manifest: Dictionary) -> int:
	return clampi(int(manifest.get("max_players", 1)), 1, Wl.MAX_SLOTS)


static func min_players(manifest: Dictionary) -> int:
	return maxi(int(manifest.get("min_players", 1)), 1)


## "1 rider", "1-8 riders", "2-4 riders".
static func player_count_text(manifest: Dictionary) -> String:
	var lo := min_players(manifest)
	var hi := max_players(manifest)
	if lo == hi:
		return String(TranslationServer.translate("APP_RIDERS_EXACT")).format([lo])
	return String(TranslationServer.translate("APP_RIDERS_RANGE")).format([lo, hi])


## The game's content to play solo with zero input (falls back to default_content).
static func zero_input_content(manifest: Dictionary) -> String:
	var c := str(manifest.get("zero_input_content", ""))
	return c if c != "" else str(manifest.get("default_content", ""))


## The content a scripted host plays: --content, else e2e_content with --e2e, else default.
static func scripted_content(manifest: Dictionary, requested: String, e2e: bool) -> String:
	if requested != "":
		return requested
	if e2e and str(manifest.get("e2e_content", "")) != "":
		return str(manifest["e2e_content"])
	return str(manifest.get("default_content", ""))


## Player options with defaults filled in for `game_id`, through the registry when it can.
static func resolve_player_options(
	registry: WlGameRegistry, game_id: String, values: Dictionary
) -> Dictionary:
	var manifest: Dictionary = registry.manifest(game_id) if registry != null else {}
	var resolved: Dictionary = (
		registry.resolve_options(game_id, values, true) if registry != null else {}
	)
	var out := AppOptionModel.defaults(game_id, manifest.get("player_options", []))
	for k: Variant in values.keys():
		if out.has(k):
			out[k] = values[k]
	for k: Variant in resolved.keys():
		out[k] = resolved[k]
	return out


## Session options with defaults filled in for `game_id`.
static func resolve_game_options(
	registry: WlGameRegistry, game_id: String, values: Dictionary
) -> Dictionary:
	var manifest: Dictionary = registry.manifest(game_id) if registry != null else {}
	var resolved: Dictionary = (
		registry.resolve_options(game_id, values, false) if registry != null else {}
	)
	var out := AppOptionModel.defaults(game_id, manifest.get("options", []))
	for k: Variant in values.keys():
		if out.has(k):
			out[k] = values[k]
	for k: Variant in resolved.keys():
		out[k] = resolved[k]
	return out
