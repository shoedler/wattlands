extends TestGameSuite
## Tank's files as a package: game.json (brief 2.2, BRIEF 3.6 fields and the option entry format),
## content files, string keys, and the static rules every game keeps (no wall clock or global RNG
## in rules, no trainer path but ctx.directives, BRIEF 4.6.11). Lead-owned (G0).

const F := preload("res://tests/games/tank/tank_fakes.gd")


func _prefix() -> String:
	return F.GAME_ID.to_upper() + "_"


func test_manifest_has_every_required_field_and_matches_its_folder() -> void:
	var m := F.manifest()
	for k: String in REQUIRED_FIELDS:
		assert_true(m.has(k), "game.json has %s" % k)
	assert_eq(m["id"], F.GAME_DIR.get_file(), "id is the folder name")
	assert_eq(m["presentation"], "2d")
	assert_eq(m["pixel_base"], [960.0, 540.0], "v2: the reference at 960 x 540 (brief 0.2)")
	assert_eq(m["pixel_flex"], {"min": [852.0, 480.0]})
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


func test_game_json_is_exactly_the_brief() -> void:
	var m := F.manifest()
	assert_eq(m["title"], "Torque Company")
	assert_eq([int(m["min_players"]), int(m["max_players"])], [1, 4])
	assert_eq(m["version"], "0.4.0")
	assert_true(m["bots"], "v4: bots fill the empty seats")
	assert_eq(
		m["contents"],
		[
			"ashfall_road",
			"ambush_15",
			"roam_30",
			"roam_10",
			"roam_20",
			"roam_45",
			"roam_60",
			"drill"
		],
		"brief 2.2's order, the short session second"
	)
	var cards: Dictionary = m.get("content_cards", {})
	assert_eq(cards.keys().size(), 8, "a card per content")
	assert_true(bool(cards["ashfall_road"]["featured"]))
	assert_true(bool(cards["ambush_15"]["featured"]), "the short session is featured")
	assert_eq(cards["ambush_15"]["detail"], "TANK_CARD_AMBUSH")
	assert_true(bool(cards["roam_30"]["featured"]), "Free Roam 30 min is featured")
	for id: String in ["roam_10", "roam_20", "roam_45", "roam_60", "drill"]:
		assert_false(bool(cards[id].get("featured", false)), id)
	for id2: String in ["roam_10", "roam_20", "roam_30", "roam_45", "roam_60"]:
		assert_eq(cards[id2]["image"], "res://assets/tank/cards/card_roam.png", id2)
		assert_eq(cards[id2]["detail"], "TANK_CARD_ROAM", id2)
	for c: String in cards:
		assert_true(ResourceLoader.exists(str(cards[c]["image"])), "%s card image exists" % c)
	assert_eq(
		[m["default_content"], m["e2e_content"], m["zero_input_content"]],
		["ashfall_road", "drill", "ashfall_road"]
	)
	assert_eq(int(m["first_run_priority"]), -1, "the first run never picks Tank")
	# v4: the one session option is the difficulty (seats replaced rotation in v3).
	assert_eq((m["options"] as Array).size(), 1, "no rotation option in v3")
	assert_eq(str(m["options"][0]["id"]), "difficulty")
	# v2 (brief 3.1): one per-rider option, the miniature (per-frame depth of field) toggle.
	assert_eq(
		m.get("player_options", []),
		[{"id": "miniature", "type": "toggle", "default": true, "label": "TANK_OPT_MINIATURE"}]
	)
	# G2 adds the picker card once its PNG exists, and only then.
	var picker := str(m.get("picker_image", ""))
	if picker != "":
		assert_true(ResourceLoader.exists(picker), "the picker card's PNG exists")


func test_every_content_file_loads_and_validates() -> void:
	for content_id: String in F.manifest()["contents"]:
		var path := F.CONTENT_DIR.path_join(TankContent.mission_path(content_id))
		assert_true(FileAccess.file_exists(path), path)
		var c := TankContent.from_dicts(TankContent.read_files(content_id), content_id)
		assert_eq(c.errors, [] as Array[String], content_id)


func test_option_entries_use_the_sdk_entry_format() -> void:
	check_option_entries(F.manifest())


func test_every_string_key_has_the_game_prefix_and_every_used_key_exists() -> void:
	var keys := csv_keys(F.CONTENT_DIR)
	assert_gt(keys.size(), 0)
	for k in keys:
		assert_true(k.begins_with(_prefix()), "%s starts with %s" % [k, _prefix()])
	var used := {}
	# Keys appear as string literals in code and as JSON values; constant names such as
	# TankIds.TANK_BULWARK are not keys, so only quoted ones count.
	var re := RegEx.create_from_string('"(' + _prefix() + '[A-Z0-9_]*[A-Z0-9])"')
	var sources := files(F.GAME_DIR, ["gd", "json"]) + files(F.CONTENT_DIR, ["json"])
	for path in sources:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			used[m.get_string(1)] = path
	var man := F.manifest()
	for e: Dictionary in man.get("options", []):
		used[str(e.get("label", "%sOPT_%s" % [_prefix(), str(e["id"]).to_upper()]))] = "game.json option label"
	for c: String in man["contents"]:
		used["%sCONTENT_%s" % [_prefix(), c.to_upper()]] = "game.json content label"
		used["%sMISSION_%s" % [_prefix(), c.to_upper()]] = "the Strava ride tag's mission"
	for t: String in TankIds.ENEMY_TYPES:
		used["%sENEMY_%s" % [_prefix(), t.to_upper()]] = "enemy name"
	for engine: String in TankIds.ENGINES:
		used[str(TankIds.ENGINE_LABELS[engine])] = "engine name"
	var c := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	for u: Variant in c.unlocks():
		used["%sUNLOCK_%s" % [_prefix(), str(u["id"]).to_upper()]] = "cosmetics.json unlock"
	assert_gt(used.size(), 5)
	for k: String in used:
		assert_has(keys, k, "%s (used in %s) is in strings.csv" % [k, used[k]])


## W4r2 R31 (GAME_SDK 15): the results screen names an unlock by the key <ID>_UNLOCK_<UNLOCK ID>
## (upper case) and shows the raw id without it; every unlock the game hands out has that string.
func test_every_unlock_id_has_its_results_screen_name() -> void:
	var keys := csv_keys(F.CONTENT_DIR)
	var ctx := F.make_ctx(1)
	var g: TankGame = autofree(F.make_game(ctx))
	(ctx.stats as F.Stats).rows = {1: {"kj": 100.0}}
	g.state.seg.seg = TankIds.SEG_COOLDOWN
	g.state.score.behemoth_killed = true
	var unlocks: Array = g.results().row(1)["unlocks"]
	assert_has(unlocks, "soot", "a finished session")
	assert_has(unlocks, "brass_machinery", "a Behemoth kill with no breakdown")
	for u: Variant in g.content.unlocks():
		var id := str(u["id"])
		assert_has(
			keys, "%sUNLOCK_%s" % [_prefix(), id.to_upper()], "unlock %s has its name string" % id
		)


## Views are exempt: they only read state and may seed their own cosmetic RNG from ctx.seed.
func test_rules_and_module_use_no_wall_clock_or_global_randomness() -> void:
	var clocks := "\\bTime\\.|OS\\.get_ticks|OS\\.get_unix_time|RandomNumberGenerator\\.new\\("
	var globals := "(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize)\\("
	var re := RegEx.create_from_string(clocks + "|" + globals)
	var scanned := 0
	for path in files(F.GAME_DIR, ["gd"]):
		var rel := path.trim_prefix(F.GAME_DIR)
		if rel.contains("view") or rel.contains("hud") or rel.contains("audio"):
			continue
		scanned += 1
		var hit := re.search(FileAccess.get_file_as_string(path))
		assert_null(hit, "%s: %s" % [path, hit.get_string() if hit != null else ""])
	assert_gte(scanned, 20, "the contracts, rules, effort, combat, net, autopilot and the module")


func test_nothing_reaches_the_trainer_except_ctx_directives() -> void:
	for path in files(F.GAME_DIR, ["gd"]):
		var text := FileAccess.get_file_as_string(path)
		for name: String in CORE_TRAINER_NAMES:
			assert_false(text.contains(name), "%s mentions %s" % [path, name])
