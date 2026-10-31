extends TestGameSuite
## The fishing game's files as a package: game.json (BRIEF 3.6 fields and the option entry format),
## content files, string keys, and the static rules every game keeps (no wall clock or global RNG
## in rules, no trainer path but ctx.directives, BRIEF 4.6.11).

const F := preload("res://tests/games/fishing/fishing_fakes.gd")


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
		var ctx := F.make_ctx(1, 0, content_id)
		var c := FishingContent.load_for(ctx)
		assert_true(c.ok, "%s: %s" % [content_id, c.errors])
		assert_eq(c.trip.id, content_id, "the trip id matches its file name")


func test_free_roam_comes_first_and_is_the_default() -> void:
	var m := F.manifest()
	assert_eq(m["contents"][0], "roam_30", "the headline mode is listed first")
	assert_eq(m["default_content"], "roam_30")
	assert_eq(m["zero_input_content"], "roam_30")
	assert_true(bool(m["bots"]), "bots may fill Free Roam slots")
	for c: String in ["roam_10", "roam_20", "roam_30", "roam_45", "roam_60"]:
		assert_has(m["contents"], c)
	for c: String in m["contents"]:
		assert_false(c.begins_with("free_"), "the free trips are gone: %s" % c)


func test_the_map_and_the_species_table_cover_every_species_and_zone() -> void:
	var map: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(F.CONTENT_DIR.path_join("map.json"))
	)
	assert_eq(FishingWorld.errors(map), [])
	var world := FishingWorld.from_map(map)
	var ctx := F.make_ctx(1, 0, "roam_30")
	var c := FishingContent.load_for(ctx)
	var zones_with_fish := {}
	for id: String in FishingConst.SPECIES:
		assert_true(c.species.has(id), "species.json has %s" % id)
		var def: FishingSpeciesDef = c.species[id]
		assert_eq(def.sprite, "fish_" + id)
		for z: String in def.zones:
			zones_with_fish[z] = true
	for z: Dictionary in world.zones():
		if z["id"] != "dock":
			assert_true(zones_with_fish.has(z["id"]), "fish live in the %s" % z["id"])
	assert_true(is_inf(world.floor_depth_m(world.length_m() - 1.0)), "the abyss has no floor")


func test_option_entries_use_the_sdk_entry_format() -> void:
	check_option_entries(F.manifest())


func test_every_string_key_has_the_game_prefix_and_every_used_key_exists() -> void:
	var keys := csv_keys(F.CONTENT_DIR)
	assert_gt(keys.size(), 0)
	for k in keys:
		assert_true(k.begins_with(_prefix()), "%s starts with %s" % [k, _prefix()])
	var used := {}
	# Quoted literals only: a constant named FISHING_... is code, not a string key.
	var re := RegEx.create_from_string('"(' + _prefix() + '[A-Z0-9_]+)"')
	var sources := files(F.GAME_DIR, ["gd", "json"]) + files(F.CONTENT_DIR, ["json"])
	for path in sources:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			if not m.get_string(1).ends_with("_"):  # a format prefix ("FISHING_TIP_" + n)
				used[m.get_string(1)] = path
	var man := F.manifest()
	for e: Dictionary in man.get("options", []) + man.get("player_options", []):
		used[str(e.get("label", "%sOPT_%s" % [_prefix(), str(e["id"]).to_upper()]))] = "game.json option label"
	for c: String in man["contents"]:
		used["%sCONTENT_%s" % [_prefix(), c.to_upper()]] = "game.json content label"
	assert_gt(used.size(), 5)
	for k: String in used:
		assert_has(keys, k, "%s (used in %s) is in strings.csv" % [k, used[k]])


## GAME_SDK 15: the results screen names an unlock by <ID>_UNLOCK_<UNLOCK ID>; every cosmetic
## the game can unlock has that string.
func test_every_unlock_id_has_its_results_screen_name() -> void:
	var keys := csv_keys(F.CONTENT_DIR)
	var co: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(F.CONTENT_DIR.path_join("cosmetics.json"))
	)
	assert_gt((co["items"] as Array).size(), 0)
	for it: Dictionary in co["items"]:
		assert_has(keys, "%sUNLOCK_%s" % [_prefix(), str(it["id"]).to_upper()], str(it["id"]))


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
