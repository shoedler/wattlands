extends GutTest
## Tank's files as a package: game.json (brief 2.2, BRIEF 3.6 fields and the option entry format),
## content files, string keys, and the static rules every game keeps (no wall clock or global RNG
## in rules, no trainer path but ctx.directives, BRIEF 4.6.11). Lead-owned (G0).

const F := preload("res://tests/games/tank/tank_fakes.gd")
const REQUIRED := [
	"id",
	"title",
	"summary",
	"version",
	"min_players",
	"max_players",
	"bots",
	"presentation",
	"entry",
	"contents",
	"default_content",
	"e2e_content",
	"zero_input_content"
]
## Names only the platform's trainer stack may use (BRIEF 4.6.11, tests/arch/test_no_bypass.gd).
const TRAINER_NAMES := [
	"TrainerController",
	"SafetyGovernor",
	"FtmsClient",
	"write_control",
	"set_target_power",
	"set_simulation",
	"set_resistance",
	"write_characteristic"
]


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


func test_game_json_is_exactly_the_brief() -> void:
	var m := F.manifest()
	assert_eq(m["title"], "Diesel Domestiques")
	assert_eq([int(m["min_players"]), int(m["max_players"])], [1, 3])
	assert_false(m["bots"], "no bots (brief 0.3)")
	assert_eq(m["contents"], ["ashfall_road", "drill"])
	assert_eq(
		[m["default_content"], m["e2e_content"], m["zero_input_content"]],
		["ashfall_road", "drill", "ashfall_road"]
	)
	assert_eq(int(m["first_run_priority"]), -1, "the first run never picks Tank")
	assert_eq(
		m["options"],
		[{"id": "rotation", "type": "toggle", "default": true, "label": "TANK_OPT_ROTATION"}]
	)
	assert_false(m.has("player_options"))
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
				assert_eq(
					fmod(float(e["default"]) - float(e["min"]), step),
					0.0,
					"default on the step grid: %s" % e
				)
			"choice":
				var values: Array = (e["choices"] as Array).map(
					func(c: Dictionary) -> Variant: return c["value"]
				)
				assert_has(values, e["default"], str(e))


func test_every_string_key_has_the_game_prefix_and_every_used_key_exists() -> void:
	var keys := _csv_keys()
	assert_gt(keys.size(), 0)
	for k in keys:
		assert_true(k.begins_with(_prefix()), "%s starts with %s" % [k, _prefix()])
	var used := {}
	# Keys appear as string literals in code and as JSON values; constant names such as
	# TankIds.TANK_BULWARK are not keys, so only quoted ones count.
	var re := RegEx.create_from_string('"(' + _prefix() + '[A-Z0-9_]*[A-Z0-9])"')
	var sources := _files(F.GAME_DIR, ["gd", "json"]) + _files(F.CONTENT_DIR, ["json"])
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
	var keys := _csv_keys()
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
	for path in _files(F.GAME_DIR, ["gd"]):
		var rel := path.trim_prefix(F.GAME_DIR)
		if rel.contains("view") or rel.contains("hud") or rel.contains("audio"):
			continue
		scanned += 1
		var hit := re.search(FileAccess.get_file_as_string(path))
		assert_null(hit, "%s: %s" % [path, hit.get_string() if hit != null else ""])
	assert_gte(scanned, 20, "the contracts, rules, effort, combat, net, autopilot and the module")


func test_art_json_keeps_61_sprites_32_colours_and_the_no_people_no_text_clause() -> void:
	var art: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/tank/art.json")
	)
	assert_lte((art["palette"] as Array).size(), 32)
	assert_eq((art["sprites"] as Array).size(), 61)
	var style := str(art["style"])
	for clause: String in [
		"No people, figures or faces", "no text, letters, numbers, flags, insignia"
	]:
		assert_string_contains(style, clause)
	for id: String in TankPlaceholderArt.ids():
		var img := TankPlaceholderArt.placeholder_image(id)
		assert_eq(Vector2i(img.get_width(), img.get_height()), TankPlaceholderArt.size_of(id), id)
		assert_not_null(TankPlaceholderArt.texture(id), id)


func test_nothing_reaches_the_trainer_except_ctx_directives() -> void:
	for path in _files(F.GAME_DIR, ["gd"]):
		var text := FileAccess.get_file_as_string(path)
		for name: String in TRAINER_NAMES:
			assert_false(text.contains(name), "%s mentions %s" % [path, name])
