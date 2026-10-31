extends GutTest
## The real games' picker cards, read from their game.json (the picker's own tests use a fake
## registry): every game names one, it loads as a texture at 16:9 and the Windows export ships it.

const GAMES_DIR := "res://src/games/"
const REQUIRED: Array[String] = ["fishing", "siege", "tank", "workout"]
const PRESETS := "res://export_presets.cfg"


func test_the_four_games_are_among_the_ones_checked() -> void:
	var ids := _game_ids()
	for id: String in REQUIRED:
		assert_true(ids.has(id), "%s is a game" % id)


func test_every_game_names_a_picker_image_that_loads_at_16_9() -> void:
	for id: String in _game_ids():
		var path := _picker_image(id)
		assert_true(path.begins_with("res://assets/%s/" % id), "%s: its own art: %s" % [id, path])
		var tex := AppGameCard.load_picker_image(path)
		assert_not_null(tex, "%s: %s loads as a texture" % [id, path])
		if tex != null:
			assert_eq(tex.get_width() * 9, tex.get_height() * 16, "%s: 16:9" % id)


func test_every_card_is_at_least_as_wide_as_the_slot_it_was_cut_for() -> void:
	for id: String in _game_ids():
		var tex := AppGameCard.load_picker_image(_picker_image(id))
		if tex != null:
			assert_gte(
				float(tex.get_width()), AppGameCard.IMAGE_SIZE.x, "%s: sharp in the slot" % id
			)


func test_the_export_filter_keeps_every_picker_image() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK)
	assert_eq(str(cfg.get_value("preset.0", "export_filter")), "all_resources")
	var exclude := str(cfg.get_value("preset.0", "exclude_filter")).split(",")
	for id: String in _game_ids():
		var path := _picker_image(id).trim_prefix("res://")
		for f: String in exclude:
			assert_false(path.match(f.strip_edges()), "%s is excluded by %s" % [path, f])


func _game_ids() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(GAMES_DIR)
	assert_not_null(d)
	if d != null:
		for sub in d.get_directories():
			if not sub.begins_with("_") and FileAccess.file_exists(_manifest_path(sub)):
				out.append(sub)
	return out


func _manifest_path(id: String) -> String:
	return GAMES_DIR + id + "/game.json"


func _picker_image(id: String) -> String:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(_manifest_path(id)))
	return str((m as Dictionary).get("picker_image", "")) if m is Dictionary else ""
