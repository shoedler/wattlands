extends TestGameSuite
## The template's files as a package: game.json (BRIEF 3.6 fields and the option entry format),
## content files, string keys, and the static rules every game keeps (no wall clock or global RNG
## in rules, no trainer path but ctx.directives, BRIEF 4.6.11).

const F := preload("res://tests/games/_template/template_fakes.gd")


func _prefix() -> String:
	return F.GAME_ID.to_upper() + "_"


func test_manifest_has_every_required_field_and_matches_its_folder() -> void:
	var m := F.manifest()
	for k: String in REQUIRED_FIELDS:
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
		assert_eq(
			TemplateRules.content_error(JSON.parse_string(FileAccess.get_file_as_string(path))),
			"",
			path
		)


func test_option_entries_use_the_sdk_entry_format() -> void:
	check_option_entries(F.manifest())


func test_every_string_key_has_the_game_prefix_and_every_used_key_exists() -> void:
	var keys := csv_keys(F.CONTENT_DIR)
	assert_gt(keys.size(), 0)
	for k in keys:
		assert_true(k.begins_with(_prefix()), "%s starts with %s" % [k, _prefix()])
	var used := {}
	var re := RegEx.create_from_string(_prefix() + "[A-Z0-9_]+")
	var sources := files(F.GAME_DIR, ["gd", "json"]) + files(F.CONTENT_DIR, ["json"])
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


## W4r2 R31 (GAME_SDK 15): the results screen names an unlock by the key <ID>_UNLOCK_<UNLOCK ID>
## (upper case) and shows the raw id without it; every unlock the game hands out has that string.
func test_every_unlock_id_has_its_results_screen_name() -> void:
	var keys := csv_keys(F.CONTENT_DIR)
	var ctx := F.make_ctx(1)
	var g: TemplateGame = autofree(F.make_game(ctx))
	(ctx.stats as F.Stats).rows = {1: {"kj": 100.0, "time_in_band_pct": 90.0}}
	TemplateRules.rider(g.state, 1)["laps"] = 3
	var unlocks: Array = g.results().row(1)["unlocks"]
	assert_gt(unlocks.size(), 0, "3 laps unlock something")
	for id: Variant in unlocks:
		assert_has(
			keys,
			"%sUNLOCK_%s" % [_prefix(), str(id).to_upper()],
			"unlock %s has its name string" % id
		)


## Views are exempt: they only read state and may seed their own cosmetic RNG from ctx.seed.
func test_rules_and_module_use_no_wall_clock_or_global_randomness() -> void:
	var clocks := "\\bTime\\.|OS\\.get_ticks|OS\\.get_unix_time|RandomNumberGenerator\\.new\\("
	var globals := "(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize)\\("
	var re := RegEx.create_from_string(clocks + "|" + globals)
	var scanned := 0
	for path in files(F.GAME_DIR, ["gd"]):
		if path.trim_prefix(F.GAME_DIR).contains("view"):
			continue
		scanned += 1
		var hit := re.search(FileAccess.get_file_as_string(path))
		assert_null(hit, "%s: %s" % [path, hit.get_string() if hit != null else ""])
	assert_gte(scanned, 2, "the rules and the module are scanned")


func test_nothing_reaches_the_trainer_except_ctx_directives() -> void:
	for path in files(F.GAME_DIR, ["gd"]):
		var text := FileAccess.get_file_as_string(path)
		for name: String in CORE_TRAINER_NAMES:
			assert_false(text.contains(name), "%s mentions %s" % [path, name])
