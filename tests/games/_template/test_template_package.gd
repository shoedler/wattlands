extends GutTest
## The template's files as a package: game.json (BRIEF 3.6 fields and the option entry format),
## content files, string keys, and the static rules every game keeps (no wall clock or global RNG
## in rules, no trainer path but ctx.directives, BRIEF 4.6.11).

const F := preload("res://tests/games/_template/template_fakes.gd")
const REQUIRED := ["id", "title", "summary", "version", "min_players", "max_players", "bots",
	"presentation", "entry", "contents", "default_content", "e2e_content", "zero_input_content"]
## Names only the platform's trainer stack may use (BRIEF 4.6.11, tests/arch/test_no_bypass.gd).
const TRAINER_NAMES := ["TrainerController", "SafetyGovernor", "FtmsClient", "write_control",
	"set_target_power", "set_simulation", "set_resistance", "write_characteristic"]


func _files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	for f in da.get_files() if da != null else PackedStringArray():
		if exts.has(f.get_extension()):
			out.append(dir.path_join(f))
	for sub in da.get_directories() if da != null else PackedStringArray():
		out.append_array(_files(dir.path_join(sub), exts))
	return out


func _csv_keys() -> Array[String]:
	var keys: Array[String] = []
	var f := FileAccess.open(F.CONTENT_DIR.path_join("strings.csv"), FileAccess.READ)
	assert_eq(f.get_csv_line(), PackedStringArray(["keys", "en"]), "strings.csv header")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0] != "":
			keys.append(row[0])
	return keys


func _prefix() -> String:
	return F.GAME_ID.to_upper() + "_"


func test_manifest_has_every_required_field_and_matches_its_folder() -> void:
	var m := F.manifest()
	for k: String in REQUIRED:
		assert_true(m.has(k), "game.json has %s" % k)
	assert_eq(m["id"], F.GAME_DIR.get_file(), "id is the folder name")
	assert_eq(m["presentation"], "2d")
	assert_eq(m["pixel_base"], [640.0, 360.0])
	assert_between(int(m["min_players"]), 1, int(m["max_players"]))
	assert_lte(int(m["max_players"]), Wl.MAX_SLOTS)
	assert_typeof(m["bots"], TYPE_BOOL)
	assert_eq(float(m["first_run_priority"]), roundf(float(m["first_run_priority"])), "an integer")
	for k: String in ["default_content", "e2e_content", "zero_input_content"]:
		assert_has(m["contents"], m[k], k)


func test_entry_is_an_instantiable_game_module() -> void:
	var script: Script = load(F.manifest()["entry"])
	assert_not_null(script)
	assert_true(script.can_instantiate())
	var game: Object = autofree(script.new())
	assert_is(game, GameModule)


func test_every_content_file_loads_and_validates() -> void:
	for content_id: String in F.manifest()["contents"]:
		var path := F.CONTENT_DIR.path_join(content_id + ".json")
		assert_true(FileAccess.file_exists(path), path)
		assert_eq(TemplateRules.content_error(JSON.parse_string(FileAccess.get_file_as_string(path))), "", path)


func test_option_entries_use_the_sdk_entry_format() -> void:
	var m := F.manifest()
	var entries: Array = m.get("options", []) + m.get("player_options", [])
	assert_gt(entries.size(), 0)
	for e: Dictionary in entries:
		assert_has(["toggle", "int", "choice"], e["type"], str(e))
		match e["type"]:
			"toggle":
				assert_typeof(e["default"], TYPE_BOOL, str(e))
			"int":
				var step := float(e.get("step", 1))
				assert_between(float(e["default"]), float(e["min"]), float(e["max"]), str(e))
				assert_eq(fmod(float(e["default"]) - float(e["min"]), step), 0.0, "default on the step grid: %s" % e)
			"choice":
				var values: Array = (e["choices"] as Array).map(func(c: Dictionary) -> Variant: return c["value"])
				assert_has(values, e["default"], str(e))


func test_every_string_key_has_the_game_prefix_and_every_used_key_exists() -> void:
	var keys := _csv_keys()
	assert_gt(keys.size(), 0)
	for k in keys:
		assert_true(k.begins_with(_prefix()), "%s starts with %s" % [k, _prefix()])
	var used := {}
	var re := RegEx.create_from_string(_prefix() + "[A-Z0-9_]+")
	var sources := _files(F.GAME_DIR, ["gd", "json"]) + _files(F.CONTENT_DIR, ["json"])
	for path in sources:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			used[m.get_string()] = path
	var man := F.manifest()
	for e: Dictionary in man.get("options", []) + man.get("player_options", []):
		used[str(e.get("label", "%sOPT_%s" % [_prefix(), str(e["id"]).to_upper()]))] = "game.json option label"
	for c: String in man["contents"]:
		used["%sCONTENT_%s" % [_prefix(), c.to_upper()]] = "game.json content label"
	assert_gt(used.size(), 5)
	for k: String in used:
		assert_has(keys, k, "%s (used in %s) is in strings.csv" % [k, used[k]])


## Views are exempt: they only read state and may seed their own cosmetic RNG from ctx.seed.
func test_rules_and_module_use_no_wall_clock_or_global_randomness() -> void:
	var re := RegEx.create_from_string(
		"\\bTime\\.|OS\\.get_ticks|OS\\.get_unix_time|RandomNumberGenerator\\.new\\(|(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize)\\(")
	var scanned := 0
	for path in _files(F.GAME_DIR, ["gd"]):
		if path.trim_prefix(F.GAME_DIR).contains("view"):
			continue
		scanned += 1
		var hit := re.search(FileAccess.get_file_as_string(path))
		assert_null(hit, "%s: %s" % [path, hit.get_string() if hit != null else ""])
	assert_gte(scanned, 2, "the rules and the module are scanned")


func test_nothing_reaches_the_trainer_except_ctx_directives() -> void:
	for path in _files(F.GAME_DIR, ["gd"]):
		var text := FileAccess.get_file_as_string(path)
		for name: String in TRAINER_NAMES:
			assert_false(text.contains(name), "%s mentions %s" % [path, name])
