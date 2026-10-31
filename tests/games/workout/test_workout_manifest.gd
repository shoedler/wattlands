extends GutTest
## game.json (BRIEF 3.6, 3.7), strings.csv (BRIEF 6) and the picker card.

const GAME_JSON := "res://src/games/workout/game.json"
const STRINGS := "res://content/workout/strings.csv"
const CARD := "res://assets/workout/picker_card.png"


func _manifest() -> Dictionary:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(GAME_JSON))
	assert_true(m is Dictionary, "game.json parses")
	return m if m is Dictionary else {}


func _strings() -> Dictionary:
	var out := {}
	var f := FileAccess.open(STRINGS, FileAccess.READ)
	assert_not_null(f)
	var header := f.get_csv_line()
	assert_eq(Array(header), ["keys", "en"], "header keys,en")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0] == "":
			continue
		assert_false(out.has(row[0]), "duplicate key %s" % row[0])
		out[row[0]] = row[1]
	return out


func test_manifest_fields() -> void:
	var m := _manifest()
	assert_eq(m["id"], "workout")
	assert_eq(m["title"], "Workout")
	assert_true(str(m["summary"]).length() > 10)
	assert_eq(m["version"], "0.2.0")
	assert_eq(int(m["min_players"]), 1)
	assert_eq(int(m["max_players"]), 8)
	assert_eq(m["bots"], true)
	assert_eq(m["presentation"], "2d")
	assert_eq([int(m["pixel_base"][0]), int(m["pixel_base"][1])], [960, 540])
	assert_eq(m["pixel_flex"], {"min": [852.0, 480.0]})
	assert_eq(m["entry"], "res://src/games/workout/workout_game.gd")
	assert_eq(
		m["contents"],
		["easy_30", "sweet_spot", "threshold", "vo2", "rolling_road", "e2e", "zwo_sample"]
	)
	assert_eq(m["default_content"], "easy_30")
	assert_eq(m["e2e_content"], "e2e")
	assert_eq(m["zero_input_content"], "easy_30")
	assert_eq(
		m["content_schemes"], ["zwo"], "content zwo:<absolute path> imports any .zwo (BRIEF 3.7)"
	)
	assert_true(WlGameRegistry.content_allowed(m, "zwo:C:/rides/my.zwo"))
	assert_eq(int(m["first_run_priority"]), 0)
	assert_eq(m["picker_image"], CARD)
	assert_false(m.has("options"), "no lobby options")
	assert_false(m.has("player_options"))


func test_every_content_has_a_valid_session_file() -> void:
	for id: Variant in _manifest()["contents"]:
		var path := "res://content/workout/sessions/%s.json" % id
		assert_true(FileAccess.file_exists(path), path)
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(WorkoutSession.validate(data, str(id)).is_empty(), "%s validates" % id)


func test_entry_script_is_a_game_module() -> void:
	var script := load(_manifest()["entry"]) as GDScript
	assert_not_null(script)
	assert_true(script.can_instantiate())
	var inst: Variant = script.new()
	assert_true(inst is GameModule)
	(inst as Node).free()


func test_strings_have_the_workout_prefix_and_cover_every_key() -> void:
	var s := _strings()
	assert_gt(s.size(), 50)
	for key: String in s.keys():
		assert_true(key.begins_with("WORKOUT_"), "%s has the game prefix" % key)
		assert_ne(str(s[key]).strip_edges(), "", "%s has text" % key)
	for id: Variant in _manifest()["contents"]:
		assert_true(s.has("WORKOUT_CONTENT_%s" % str(id).to_upper()), "content label for %s" % id)
	for id: Variant in _manifest()["contents"]:
		var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://content/workout/sessions/%s.json" % id)
		)
		assert_true(s.has(data["label"]), "%s label key" % id)
		assert_true(s.has(data["summary"]), "%s summary key" % id)
		for p: Variant in data.get("phases", []):
			assert_true(s.has(p["label"]), "%s phase label %s" % [id, p["label"]])


func test_code_keys_exist() -> void:
	var s := _strings()
	var keys: Array[String] = [
		"WORKOUT_CONTENT_ZWO",
		"WORKOUT_SUMMARY_ZWO",
		"WORKOUT_LBL_BLOCK",
		"WORKOUT_PREVIEW_RAMP",
		"WORKOUT_PREVIEW_ERG",
		"WORKOUT_PREVIEW_FREE",
		"WORKOUT_PREVIEW_FREE_RIDE",
		"WORKOUT_PREVIEW_COURSE",
		"WORKOUT_PREVIEW_CLAMP",
		"WORKOUT_PREVIEW_WARNING",
		"WORKOUT_HUD_IN_BAND",
		"WORKOUT_HUD_TARGET_ERG",
		"WORKOUT_HUD_TARGET_RAMP",
		"WORKOUT_HUD_TARGET_EASY",
		"WORKOUT_HUD_HOLD_BAND",
		"WORKOUT_HUD_SPRINT",
		"WORKOUT_HUD_FREE_RIDE",
		"WORKOUT_HUD_DO_SPIN",
		"WORKOUT_HUD_DO_HOLD",
		"WORKOUT_HUD_DO_EASY",
		"WORKOUT_HUD_NEXT",
		"WORKOUT_HUD_NEXT_COOLDOWN",
		"WORKOUT_HUD_NEXT_END",
		"WORKOUT_HUD_LEFT",
		"WORKOUT_HUD_FTP",
		"WORKOUT_HUD_W",
		"WORKOUT_HUD_WKG",
		"WORKOUT_HUD_RPM",
		"WORKOUT_HUD_WPRIME",
		"WORKOUT_HUD_LOW",
		"WORKOUT_HUD_GEAR",
		"WORKOUT_HUD_CARD",
		"WORKOUT_HUD_NO_POWER",
		WorkoutHudModel.FLAG_RESCUE,
		WorkoutHudModel.FLAG_AFK,
		WorkoutHudModel.FLAG_LINK,
		"WORKOUT_HUD_BLOCK",
		"WORKOUT_HUD_GROUP",
		"WORKOUT_HUD_KMH",
		"WORKOUT_HUD_KM",
		"WORKOUT_HUD_PEAK",
		"WORKOUT_BANNER_RAMP",
		"WORKOUT_BANNER_ERG",
		"WORKOUT_BANNER_SPRINT",
		"WORKOUT_BANNER_ROLLING",
		"WORKOUT_BANNER_FREE",
		"WORKOUT_CLAMP_FLOOR",
		"WORKOUT_TOAST_INTERVAL_DONE",
		"WORKOUT_TOAST_SPRINT_HIT",
		"WORKOUT_TOAST_SPRINT_PEAK",
		"WORKOUT_TOAST_SPRINT_SOON",
		WorkoutResults.STAT_GRADE,
		WorkoutResults.STAT_TIB,
		WorkoutResults.STAT_INTERVALS,
		WorkoutResults.STAT_SPRINT_PEAK,
		WorkoutResults.STAT_SPRINTS_HIT,
		WorkoutResults.TEAM_TIB,
		WorkoutResults.TEAM_RIDERS,
		WorkoutResults.TEAM_SPRINTS,
		WorkoutResults.STAT_SPRINT_PEAKS,
	]
	for k: String in WorkoutResults.BEST_STATS.values():
		keys.append(k)
	for e: Array in WorkoutHud.HELP:
		keys.append(str(e[0]))
	for g in WorkoutProgress.GRADES:
		keys.append("WORKOUT_RESULT_" + g)
	for u in WorkoutProgress.UNLOCKS:
		keys.append("WORKOUT_UNLOCK_" + str(u["id"]).to_upper())
	for k in keys:
		assert_true(s.has(k), k)


func test_placeholders_match() -> void:
	var s := _strings()
	assert_string_contains(s["WORKOUT_BANNER_ERG"], "{pct}")
	assert_string_contains(s["WORKOUT_TOAST_SPRINT_HIT"], "{w}")
	assert_string_contains(s["WORKOUT_LBL_BLOCK"], "{n}")
	assert_string_contains(s["WORKOUT_PREVIEW_CLAMP"], "{text}")
	assert_string_contains(s["WORKOUT_PREVIEW_COURSE"], "{lo}")
	assert_string_contains(s["WORKOUT_PREVIEW_COURSE"], "{hi}")
	assert_string_contains(s["WORKOUT_BANNER_ROLLING"], "{lo}")


## The card is baked with the rest of the art: bake.mjs --check compares its pixels.
func test_picker_card_is_16_9() -> void:
	assert_true(FileAccess.file_exists(CARD))
	var img := Image.new()
	assert_eq(img.load_png_from_buffer(FileAccess.get_file_as_bytes(CARD)), OK)
	assert_eq(img.get_size(), Vector2i(960, 540), "16:9")
