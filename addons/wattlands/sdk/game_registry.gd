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
##
## Validation (validate_manifest) names the failing field first: "<field>: <reason>", for
## example "presentation: must be \"2d\" or \"3d\"" or "options[1].default: 7 is outside
## 1..5". Rules: id matches ^[a-z][a-z0-9_]*$ (or is _template) and its folder; title, version non-empty;
## summary a String; min/max_players whole numbers 1..8 with min <= max; bots a bool;
## pixel_base [w, h] (positive whole numbers) for 2d; entry loads and extends GameModule;
## contents a non-empty list of unique ids containing default/e2e/zero_input_content;
## first_run_priority any whole number; picker_image a String (the file is only checked
## for a warning); option entries as above, an int default inside min..max and on the
## min + n * step grid, a choice default among the choice values, unknown types invalid.
##
## Translations: each valid game's content/<id>/strings.csv is imported by Godot into
## strings.<locale>.translation next to it (read from strings.csv.import); the registry adds
## those Translation resources to the TranslationServer (and removes them on a rescan).
## The resource cache hands every registry instance the same Translation object, so the
## registrations are reference-counted across instances: a private registry (a test, the
## conformance run) that clears never removes strings the GameRegistry autoload still uses.

signal games_changed

const GAMES_ROOT := "res://src/games"
const TEMPLATE_ID := "_template"
const CONTENT_ROOT := "res://content"
const ASSETS_ROOT := "res://assets"
const GAME_MODULE_SCRIPT := "res://addons/wattlands/contracts/game_module.gd"
const MAX_PLAYERS := 8
const OPTION_TYPES: Array[String] = ["toggle", "int", "choice"]
const PRESENTATIONS: Array[String] = ["2d", "3d"]

## Translation -> how many registry instances registered it with the TranslationServer.
static var _translation_refs: Dictionary = {}

## Where content/<id>/ and assets/<id>/ live (tests point them at fixtures).
var content_root: String = CONTENT_ROOT
var assets_root: String = ASSETS_ROOT
## The autoload scans GAMES_ROOT in _ready; private instances never enter the tree or set
## this to false first.
var scan_on_ready: bool = true

var _root: String = GAMES_ROOT
## id -> validated manifest (normalized: whole numbers as int, optional fields filled).
var _games: Dictionary = {}
## id -> res:// folder holding its game.json.
var _folders: Dictionary = {}
## path (or id) -> reason, for every rejected game.json.
var _invalid: Dictionary = {}
## id -> Array[String] of non-fatal warnings (picker image).
var _warnings: Dictionary = {}
## id -> Array[Translation] added to the TranslationServer.
var _translations: Dictionary = {}
var _id_regex: RegEx = null
var _content_regex: RegEx = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if scan_on_ready:
		scan()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_remove_all_translations()


## Forget every game and remove the translations this instance added.
func clear() -> void:
	_remove_all_translations()
	_games.clear()
	_folders.clear()
	_invalid.clear()
	_warnings.clear()


## Scan `root` for */game.json (default GAMES_ROOT). Replaces the current list.
func scan(root: String = GAMES_ROOT) -> void:
	_remove_all_translations()
	_root = root.trim_suffix("/")
	_games.clear()
	_folders.clear()
	_invalid.clear()
	_warnings.clear()
	var dir := DirAccess.open(_root)
	if dir == null:
		games_changed.emit()
		return
	var subs := Array(dir.get_directories())
	subs.sort()
	for sub: String in subs:
		if sub.begins_with(".") or sub == TEMPLATE_ID:
			continue
		var folder := _root.path_join(sub)
		var path := folder.path_join("game.json")
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = load_manifest_file(path)
		if not (parsed is Dictionary):
			_reject(path, "game.json: not a JSON object")
			continue
		var m: Dictionary = parsed
		if str(m.get("id", "")) == TEMPLATE_ID:
			continue
		var err := add_game(m, folder)
		if err != "":
			_reject(path, err)
	games_changed.emit()


## Valid games' manifests (Dictionary), sorted by title; `_template` excluded.
func games() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ids():
		out.append(_games[id])
	return out


func ids() -> Array[String]:
	var list: Array[String] = []
	for id: String in _games.keys():
		if id != TEMPLATE_ID:
			list.append(id)
	list.sort_custom(func(a: String, b: String) -> bool:
		var ta := str(_games[a].get("title", a))
		var tb := str(_games[b].get("title", b))
		return ta < tb if ta != tb else a < b)
	return list


func has_game(id: String) -> bool:
	return _games.has(id)


func manifest(id: String) -> Dictionary:
	return _games.get(id, {})


## {path or id: reason} for every rejected game.json (field name in the reason).
func invalid_games() -> Dictionary:
	return _invalid.duplicate()


## "" when valid, else "<field>: <reason>". Used by the scan and the conformance test.
## `path` is the game.json path (its folder must be named like the id); "" skips that check.
func validate_manifest(m: Dictionary, path: String = "") -> String:
	var id_v: Variant = m.get("id", null)
	if not (id_v is String) or not _valid_id(str(id_v)):
		return "id: must be a lower-case id matching ^[a-z][a-z0-9_]*$"
	var id := str(id_v)
	if path != "":
		var folder := path.get_base_dir().get_file()
		if folder != id:
			return "id: \"%s\" does not match its folder \"%s\"" % [id, folder]
	for f: String in ["title", "version"]:
		var v: Variant = m.get(f, null)
		if not (v is String) or str(v).strip_edges() == "":
			return "%s: must be a non-empty string" % f
	if not (m.get("summary", null) is String):
		return "summary: must be a string"
	for f: String in ["min_players", "max_players"]:
		var v: Variant = m.get(f, null)
		if not is_whole(v) or int(v) < 1 or int(v) > MAX_PLAYERS:
			return "%s: must be a whole number 1..%d" % [f, MAX_PLAYERS]
	if int(m["min_players"]) > int(m["max_players"]):
		return "max_players: must be >= min_players"
	if not (m.get("bots", null) is bool):
		return "bots: must be true or false"
	var pres: Variant = m.get("presentation", null)
	if not (pres is String) or not PRESENTATIONS.has(str(pres)):
		return "presentation: must be \"2d\" or \"3d\""
	if str(pres) == "2d":
		var pb: Variant = m.get("pixel_base", null)
		if not (pb is Array) or (pb as Array).size() != 2 or not is_whole(pb[0]) or not is_whole(pb[1]) \
				or int(pb[0]) < 1 or int(pb[1]) < 1:
			return "pixel_base: a 2d game needs [width, height] in whole pixels"
	var entry_err := _check_entry(m.get("entry", null))
	if entry_err != "":
		return entry_err
	var contents: Variant = m.get("contents", null)
	if not (contents is Array) or (contents as Array).is_empty():
		return "contents: must be a non-empty list of content ids"
	var seen := {}
	for c: Variant in contents:
		if not (c is String) or not _valid_content_id(str(c)):
			return "contents: \"%s\" is not a valid content id" % str(c)
		if seen.has(str(c)):
			return "contents: \"%s\" is listed twice" % str(c)
		seen[str(c)] = true
	for f: String in ["default_content", "e2e_content", "zero_input_content"]:
		var v: Variant = m.get(f, null)
		if not (v is String) or not seen.has(str(v)):
			return "%s: must be one of contents" % f
	if m.has("first_run_priority") and not is_whole(m["first_run_priority"]):
		return "first_run_priority: must be a whole number"
	if m.has("picker_image") and not (m["picker_image"] is String):
		return "picker_image: must be a res:// path string"
	for f: String in ["options", "player_options"]:
		if not m.has(f):
			continue
		var err := validate_option_entries(m[f], f)
		if err != "":
			return err
	return ""


## A fresh GameModule instance of game `id` (null if unknown or the entry fails to load).
func instantiate(id: String) -> GameModule:
	if not _games.has(id):
		return null
	return instantiate_manifest(_games[id])


## A fresh GameModule from a manifest's `entry` (null if it fails to load).
static func instantiate_manifest(m: Dictionary) -> GameModule:
	var entry := str(m.get("entry", ""))
	if entry == "" or not ResourceLoader.exists(entry):
		return null
	var script := load(entry) as Script
	if script == null or not _extends_game_module(script):
		return null
	var obj: Variant = script.new()
	if obj is GameModule:
		return obj
	if obj is Node:
		(obj as Node).free()
	return null


## The first-run game (BRIEF 3.5): the highest first_run_priority; ties go to "workout",
## then the lowest id.
func first_run_game() -> String:
	return pick_first_run(games())


## The first-run rule on any list of manifests (a fixture registry in tests).
static func pick_first_run(manifests: Array) -> String:
	var best := ""
	var best_prio := 0
	for mv: Variant in manifests:
		if not (mv is Dictionary):
			continue
		var m: Dictionary = mv
		var id := str(m.get("id", ""))
		if id == "" or id == TEMPLATE_ID:
			continue
		var prio := int(m.get("first_run_priority", 0))
		if best == "" or prio > best_prio:
			best = id
			best_prio = prio
		elif prio == best_prio:
			if best == "workout":
				continue
			if id == "workout" or id < best:
				best = id
	return best


## Options with defaults filled in and values validated against the manifest's `options`
## (or `player_options` when per_player). Unknown keys are dropped with a warning.
func resolve_options(id: String, values: Dictionary, per_player: bool = false) -> Dictionary:
	var m := manifest(id)
	var entries: Variant = m.get("player_options" if per_player else "options", [])
	return resolve_option_values(entries if entries is Array else [], values, id)


## resolve_options on an explicit list of option entries (no registry needed). Invalid
## values fall back to the default with a warning; unknown keys are dropped with a warning.
static func resolve_option_values(entries: Array, values: Dictionary, context: String = "") -> Dictionary:
	var out := {}
	var known := {}
	for ev: Variant in entries:
		if not (ev is Dictionary):
			continue
		var e: Dictionary = ev
		var oid := str(e.get("id", ""))
		known[oid] = true
		var def: Array = coerce_option_value(e, e.get("default", null))
		var value: Variant = def[1] if bool(def[0]) else e.get("default", null)
		if values.has(oid):
			var got: Array = coerce_option_value(e, values[oid])
			if bool(got[0]):
				value = got[1]
			else:
				push_warning("GameRegistry: %s option %s: %s; using the default" % [context, oid, str(got[1])])
		out[oid] = value
	for k: Variant in values.keys():
		if not known.has(str(k)):
			push_warning("GameRegistry: %s: unknown option \"%s\" dropped" % [context, str(k)])
	return out


## "" when every key of `values` is a known option with a valid value, else
## "<options|player_options>.<key>: <reason>" (tools/run_game_sim exits naming the field).
func check_option_values(id: String, values: Dictionary, per_player: bool = false) -> String:
	var field := "player_options" if per_player else "options"
	var entries: Variant = manifest(id).get(field, [])
	return check_option_list(entries if entries is Array else [], values, field)


static func check_option_list(entries: Array, values: Dictionary, field: String) -> String:
	var by_id := {}
	for ev: Variant in entries:
		if ev is Dictionary:
			by_id[str((ev as Dictionary).get("id", ""))] = ev
	for k: Variant in values.keys():
		var key := str(k)
		if not by_id.has(key):
			return "%s.%s: unknown option" % [field, key]
		var got: Array = coerce_option_value(by_id[key], values[k])
		if not bool(got[0]):
			return "%s.%s: %s" % [field, key, str(got[1])]
	return ""


## [true, value] with `v` converted to the option's type, or [false, reason].
static func coerce_option_value(e: Dictionary, v: Variant) -> Array:
	match str(e.get("type", "")):
		"toggle":
			if v is bool:
				return [true, v]
			return [false, "must be true or false"]
		"int":
			if not is_whole(v):
				return [false, "must be a whole number"]
			var lo := int(e.get("min", 0))
			var hi := int(e.get("max", 0))
			var step := int(e.get("step", 1))
			var iv := int(v)
			if iv < lo or iv > hi:
				return [false, "%d is outside %d..%d" % [iv, lo, hi]]
			if step > 1 and posmod(iv - lo, step) != 0:
				return [false, "%d is not on the %d + n * %d grid" % [iv, lo, step]]
			return [true, iv]
		"choice":
			var choices: Variant = e.get("choices", [])
			if choices is Array:
				for cv: Variant in choices:
					if cv is Dictionary and json_equal((cv as Dictionary).get("value", null), v):
						return [true, (cv as Dictionary)["value"]]
			return [false, "%s is not one of the choices" % JSON.stringify(v)]
	return [false, "unknown option type \"%s\"" % str(e.get("type", ""))]


## "" or "<field>[i].<key>: <reason>" for a list of option entries.
static func validate_option_entries(list: Variant, field: String) -> String:
	if not (list is Array):
		return "%s: must be a list of option entries" % field
	var ids := {}
	var i := 0
	for ev: Variant in list:
		var at := "%s[%d]" % [field, i]
		i += 1
		if not (ev is Dictionary):
			return "%s: must be an object {id, type, default}" % at
		var e: Dictionary = ev
		var oid: Variant = e.get("id", null)
		if not (oid is String) or str(oid) == "":
			return "%s.id: must be a non-empty string" % at
		if ids.has(str(oid)):
			return "%s.id: \"%s\" is declared twice" % [at, str(oid)]
		ids[str(oid)] = true
		if e.has("label") and not (e["label"] is String):
			return "%s.label: must be a string key" % at
		var type: Variant = e.get("type", null)
		if not (type is String) or not OPTION_TYPES.has(str(type)):
			return "%s.type: must be toggle, int or choice" % at
		if not e.has("default"):
			return "%s.default: missing" % at
		match str(type):
			"int":
				for k: String in ["min", "max"]:
					if not is_whole(e.get(k, null)):
						return "%s.%s: must be a whole number" % [at, k]
				if int(e["min"]) > int(e["max"]):
					return "%s.max: must be >= min" % at
				if e.has("step") and (not is_whole(e["step"]) or int(e["step"]) < 1):
					return "%s.step: must be a whole number >= 1" % at
			"choice":
				var ch: Variant = e.get("choices", null)
				if not (ch is Array) or (ch as Array).is_empty():
					return "%s.choices: must be a non-empty list of {value, label}" % at
				var values: Array = []
				for c: Variant in ch:
					if not (c is Dictionary) or not (c as Dictionary).has("value"):
						return "%s.choices: every choice needs a value" % at
					if (c as Dictionary).has("label") and not ((c as Dictionary)["label"] is String):
						return "%s.choices: labels must be string keys" % at
					for prev: Variant in values:
						if json_equal(prev, (c as Dictionary)["value"]):
							return "%s.choices: value %s is listed twice" % [at, JSON.stringify((c as Dictionary)["value"])]
					values.append((c as Dictionary)["value"])
		var got: Array = coerce_option_value(e, e["default"])
		if not bool(got[0]):
			return "%s.default: %s" % [at, str(got[1])]
	return ""


func content_label_key(id: String, content_id: String) -> String:
	return "%s_CONTENT_%s" % [id.to_upper(), content_id.to_upper()]


func option_label_key(id: String, option: Dictionary) -> String:
	if option.has("label"):
		return str(option["label"])
	return "%s_OPT_%s" % [id.to_upper(), str(option.get("id", "")).to_upper()]


# --- additive API (sdk-runtime) -------------------------------------------------------


## Validate `m` (from `folder`/game.json) and add it. Returns "" or the validation error.
## `_template` is accepted only with allow_template (the conformance test loads it
## explicitly); games()/ids() never list it.
func add_game(m: Dictionary, folder: String, allow_template: bool = false) -> String:
	var id := str(m.get("id", ""))
	if id == TEMPLATE_ID and not allow_template:
		return "id: _template is never listed"
	var err := validate_manifest(m, folder.path_join("game.json") if folder != "" else "")
	if err != "":
		return err
	var norm := normalized(m)
	_games[id] = norm
	_folders[id] = folder
	var warns: Array[String] = []
	var pw := picker_image_warning(norm)
	if pw != "":
		warns.append(pw)
		push_warning("GameRegistry: %s: %s (the picker draws a generated title card)" % [id, pw])
	_warnings[id] = warns
	_load_translations(id)
	return ""


## The `_template` manifest from GAMES_ROOT/_template/game.json ({} if absent or invalid JSON).
func template_manifest() -> Dictionary:
	var parsed: Variant = load_manifest_file(GAMES_ROOT.path_join(TEMPLATE_ID).path_join("game.json"))
	return parsed if parsed is Dictionary else {}


## Non-fatal warnings recorded for `id` (for example a missing picker_image).
func warnings(id: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(_warnings.get(id, []))
	return out


## res:// folder of game `id` (where its game.json is).
func game_dir(id: String) -> String:
	return str(_folders.get(id, GAMES_ROOT.path_join(id)))


func content_dir(id: String) -> String:
	return content_root.path_join(id)


func assets_dir(id: String) -> String:
	return assets_root.path_join(id)


## The scan root used last.
func root() -> String:
	return _root


## Parsed JSON of a game.json file (null if missing or not JSON).
static func load_manifest_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return parse_json(FileAccess.get_file_as_string(path))


## Parsed JSON, or null when `text` is not valid JSON (no engine error is logged).
static func parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## A copy with whole numbers as int and optional fields filled (first_run_priority 0,
## picker_image "", options [], player_options []).
static func normalized(m: Dictionary) -> Dictionary:
	var out := m.duplicate(true)
	for f: String in ["min_players", "max_players"]:
		out[f] = int(out[f])
	out["first_run_priority"] = int(out.get("first_run_priority", 0))
	if out.has("pixel_base") and out["pixel_base"] is Array:
		out["pixel_base"] = [int(out["pixel_base"][0]), int(out["pixel_base"][1])]
	if not out.has("picker_image"):
		out["picker_image"] = ""
	for f: String in ["options", "player_options"]:
		if not out.has(f):
			out[f] = []
		for ev: Variant in out[f]:
			var e: Dictionary = ev
			if str(e.get("type", "")) == "int":
				e["min"] = int(e["min"])
				e["max"] = int(e["max"])
				e["step"] = int(e.get("step", 1))
				e["default"] = int(e["default"])
	return out


## "" or why the picker image cannot be used (missing or unreadable).
static func picker_image_warning(m: Dictionary) -> String:
	var p := str(m.get("picker_image", ""))
	if p == "":
		return ""
	if not ResourceLoader.exists(p):
		return "picker_image %s is missing" % p
	var res: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
	if not (res is Texture2D):
		return "picker_image %s is unreadable" % p
	return ""


## True for an int, or a float with a whole value (JSON numbers parse as float).
static func is_whole(v: Variant) -> bool:
	if v is int:
		return true
	if v is float:
		var f: float = v
		return not is_nan(f) and not is_inf(f) and f == floorf(f) and absf(f) < 9.0e15
	return false


## JSON equality: numbers compare by value (1 == 1.0), containers element-wise.
static func json_equal(a: Variant, b: Variant) -> bool:
	var na := a is int or a is float
	var nb := b is int or b is float
	if na or nb:
		return na and nb and float(a) == float(b)
	if a is String or a is StringName or b is String or b is StringName:
		return (a is String or a is StringName) and (b is String or b is StringName) and str(a) == str(b)
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not json_equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k: Variant in (a as Dictionary).keys():
			if not (b as Dictionary).has(k) or not json_equal(a[k], b[k]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


func _check_entry(entry: Variant) -> String:
	if not (entry is String) or not str(entry).begins_with("res://"):
		return "entry: must be the res:// path of the GameModule script"
	var p := str(entry)
	if not ResourceLoader.exists(p):
		return "entry: %s does not exist" % p
	var script := load(p) as Script
	if script == null:
		return "entry: %s is not a script" % p
	if not script.can_instantiate():
		return "entry: %s does not load (parse error?)" % p
	if not _extends_game_module(script):
		return "entry: %s does not extend GameModule" % p
	return ""


static func _extends_game_module(script: Script) -> bool:
	var s := script
	while s != null:
		if s.resource_path == GAME_MODULE_SCRIPT:
			return true
		s = s.get_base_script()
	return false


func _valid_id(id: String) -> bool:
	if id == TEMPLATE_ID:
		return true
	if _id_regex == null:
		_id_regex = RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return _id_regex.search(id) != null


func _valid_content_id(id: String) -> bool:
	if _content_regex == null:
		_content_regex = RegEx.create_from_string("^[a-z0-9][a-z0-9_]*$")
	return _content_regex.search(id) != null


func _reject(path: String, reason: String) -> void:
	_invalid[path] = reason
	push_warning("GameRegistry: hiding %s: %s" % [path, reason])


func _load_translations(id: String) -> void:
	_remove_translations(id)
	var dir := content_dir(id)
	var paths: Array[String] = []
	var import_path := dir.path_join("strings.csv.import")
	if FileAccess.file_exists(import_path):
		var cfg := ConfigFile.new()
		if cfg.load(import_path) == OK:
			var dest: Variant = cfg.get_value("deps", "dest_files", [])
			if dest is Array or dest is PackedStringArray:
				for p: Variant in dest:
					paths.append(str(p))
	if paths.is_empty():
		var da := DirAccess.open(dir)
		if da != null:
			for f: String in da.get_files():
				if f.begins_with("strings.") and f.ends_with(".translation"):
					paths.append(dir.path_join(f))
	var added: Array = []
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var tr := ResourceLoader.load(p) as Translation
		if tr == null:
			continue
		var refs := int(_translation_refs.get(tr, 0))
		if refs == 0:
			TranslationServer.add_translation(tr)
		_translation_refs[tr] = refs + 1
		added.append(tr)
	if not added.is_empty():
		_translations[id] = added


func _remove_translations(id: String) -> void:
	for trv: Variant in _translations.get(id, []):
		var tr := trv as Translation
		var refs := int(_translation_refs.get(tr, 0)) - 1
		if refs > 0:
			_translation_refs[tr] = refs
			continue
		_translation_refs.erase(tr)
		TranslationServer.remove_translation(tr)
	_translations.erase(id)


func _remove_all_translations() -> void:
	for id: Variant in _translations.keys():
		_remove_translations(str(id))
