class_name GameContext
extends RefCounted
## Everything the platform gives a game in `configure(ctx)` (BRIEF 3.6). Contract, frozen
## after W0. The GameHost builds one per peer and session.

var game_id: String = ""
## The game's game.json as a Dictionary (validated).
var manifest: Dictionary = {}
var players: Array[PlayerSlot] = []
var content_id: String = ""
var seed: int = 0
## Wl.SOLO, Wl.HOST or Wl.CLIENT.
var role: String = Wl.SOLO
## This machine's rider (the host's own in HOST and SOLO).
var local_peer: int = 0
## Seeded from `seed`. Rules use only this RNG (determinism, BRIEF 3.6).
var rng: RandomNumberGenerator = null
var directives: DirectiveSink = null
## Session-wide game options (game.json `options`, defaults filled in, set by the host).
var options: Dictionary = {}
## The local rider's progression for this game.
var progress: ProgressStore = null
var hud: HudFeed = null
var intents: IntentSink = null
## The latest 5.5 roster, keyed by int peer id: {raw_w, cadence_rpm, ftp_pct, rescue, afk,
## connected, status: {in_band, icon, text}, name, slot_index}.
var roster: Dictionary = {}
var strings: GameStrings = null
## The EventBus for this peer's session (the autoload in the app; a private instance in
## in-process multi-peer simulations).
var events: WlEventBus = null
## Per-rider ride statistics for results (host and SOLO).
var stats: SessionStats = null
## Lobby scaling mode (Wl.FAIR_FTP, Wl.WKG, Wl.RAW).
var scaling_mode: String = Wl.FAIR_FTP
## res:// folders of this game.
var game_dir: String = ""
var content_dir: String = ""
var assets_dir: String = ""
## Content patches for stress runs (tools/run_game_sim --override): rel path under
## content_dir -> RFC 7386 JSON merge patch, applied by load_content_json(). Games must load
## their content through load_content_json() so overrides work.
var content_overrides: Dictionary = {}


func is_authority() -> bool:
	return role == Wl.SOLO or role == Wl.HOST


func player(peer: int) -> PlayerSlot:
	for p in players:
		if p.peer_id == peer:
			return p
	return null


func peers() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		out.append(p.peer_id)
	return out


func local_player() -> PlayerSlot:
	return player(local_peer)


## Reads a JSON file from this game's content folder (res://content/<id>/<rel_path>).
## Returns null and push_error on a missing or invalid file.
func load_content_json(rel_path: String) -> Variant:
	var path := content_dir.path_join(rel_path)
	if not FileAccess.file_exists(path):
		push_error("GameContext: missing content %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("GameContext: invalid JSON in %s" % path)
		return null
	if content_overrides.has(rel_path):
		parsed = merge_patch(parsed, content_overrides[rel_path])
	return parsed


## RFC 7386 JSON merge patch: `patch` applied to `target` (a new value is returned).
static func merge_patch(target: Variant, patch: Variant) -> Variant:
	if not (patch is Dictionary):
		return patch
	var result: Dictionary = (target as Dictionary).duplicate(true) if target is Dictionary else {}
	for key: Variant in (patch as Dictionary).keys():
		var value: Variant = patch[key]
		if value == null:
			result.erase(key)
		else:
			result[key] = merge_patch(result.get(key, null), value)
	return result
