class_name WlGameRegistry
extends Node
## Autoload `GameRegistry` (BRIEF 3.6): scans res://src/games/*/game.json at startup,
## validates each file, lists the valid games in the game picker and registers each valid
## game's imported translations (content/<id>/strings.csv) with the TranslationServer.
## An invalid game is hidden with a logged reason (push_warning), never a crash; `_template`
## is never listed. Owned by sdk-runtime; public API frozen after W0. Tests create private
## instances and scan fixture folders.
##
## game.json fields: id, title, summary, version, min_players, max_players, bots,
## presentation ("2d"/"3d"), pixel_base (2D, [w, h]), entry (res path of the GameModule
## script), contents, default_content, e2e_content, zero_input_content,
## first_run_priority (int, default 0), picker_image (optional res path; a missing or
## unreadable file logs a warning and the picker draws a generated title card), options and
## player_options (entries {id, type: "toggle"|"int"|"choice", default, label?, min, max,
## step (int, default 1), choices: [{value, label}]}). Labels default to
## <ID>_OPT_<OPTION ID>; content labels are <ID>_CONTENT_<CONTENT ID> (or the bare id).

signal games_changed

const GAMES_ROOT := "res://src/games"
const TEMPLATE_ID := "_template"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Scan `root` for */game.json (default GAMES_ROOT). Replaces the current list.
func scan(_root: String = GAMES_ROOT) -> void:
	pass


## Valid games' manifests (Dictionary), sorted by title; `_template` excluded.
func games() -> Array[Dictionary]:
	return []


func ids() -> Array[String]:
	return []


func has_game(_id: String) -> bool:
	return false


func manifest(_id: String) -> Dictionary:
	return {}


## {path or id: reason} for every rejected game.json (field name in the reason).
func invalid_games() -> Dictionary:
	return {}


## "" when valid, else "<field>: <reason>". Used by the scan and the conformance test.
func validate_manifest(_m: Dictionary, _path: String = "") -> String:
	return "not implemented"


## A fresh GameModule instance of game `id` (null if unknown or the entry fails to load).
func instantiate(_id: String) -> GameModule:
	return null


## The first-run game (BRIEF 3.5): the highest first_run_priority; ties go to "workout",
## then the lowest id.
func first_run_game() -> String:
	return ""


## Options with defaults filled in and values validated against the manifest's `options`
## (or `player_options` when per_player). Unknown keys are dropped with a warning.
func resolve_options(_id: String, _values: Dictionary, _per_player: bool = false) -> Dictionary:
	return {}


func content_label_key(id: String, content_id: String) -> String:
	return "%s_CONTENT_%s" % [id.to_upper(), content_id.to_upper()]


func option_label_key(id: String, option: Dictionary) -> String:
	if option.has("label"):
		return str(option["label"])
	return "%s_OPT_%s" % [id.to_upper(), str(option.get("id", "")).to_upper()]
