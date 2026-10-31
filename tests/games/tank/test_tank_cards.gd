extends GutTest
## Tank's card art as game.json names it: every file loads, and the folder ships no PNG the game doesn't use. The paths
## come from game.json, so moving the cards changes nothing here. What the v2 kit's tests held on to, now that the kit's
## class and kit.json are gone.

const MANIFEST := "res://src/games/tank/game.json"
const TANK_ART := "res://assets/tank/"
const KIT_CLASS := "res://src/games/tank/view/tank_kit.gd"
## Subfolders of the card folder that hold other things than cards.
const NOT_CARDS: Array[String] = ["hud/", "source/", "tools_src/"]


func test_every_card_in_game_json_loads() -> void:
	var cards := _card_paths()
	assert_false(cards.is_empty(), "game.json names cards")
	for c: String in cards:
		assert_not_null(load(c) as Texture2D, c)


func test_the_picker_card_loads() -> void:
	var picker := str(_manifest().get("picker_image", ""))
	assert_ne(picker, "", "game.json names a picker image")
	assert_not_null(load(picker) as Texture2D, picker)


func test_the_card_folder_holds_only_what_game_json_names() -> void:
	var picker := str(_manifest().get("picker_image", ""))
	var dir := picker.get_base_dir() + "/"
	var used := {picker: true}
	for c: String in _card_paths():
		used[c] = true
	var stray: Array[String] = []
	for f in _pngs(dir, ""):
		if not used.has(dir + f):
			stray.append(f)
	assert_eq(stray, [] as Array[String], "PNGs nothing uses")


func test_the_v2_enemy_art_and_kit_are_gone() -> void:
	assert_false(DirAccess.dir_exists_absolute(TANK_ART + "v2/enemies"), "the v2 enemies are gone")
	assert_false(FileAccess.file_exists(TANK_ART + "v2/kit.json"), "the v2 manifest is gone")
	assert_false(ResourceLoader.exists(KIT_CLASS), "the v2 kit's class is gone")


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _card_paths() -> Array[String]:
	var out: Array[String] = []
	var cards: Dictionary = _manifest().get("content_cards", {})
	for id: String in cards:
		out.append(str(cards[id]["image"]))
	return out


static func _pngs(dir: String, rel: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir + rel)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".png"):
			out.append(rel + f)
	for sub in d.get_directories():
		if not (rel + sub + "/") in NOT_CARDS:
			out.append_array(_pngs(dir, rel + sub + "/"))
	return out
