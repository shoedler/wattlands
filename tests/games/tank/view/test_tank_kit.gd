extends GutTest
## What is left of the v2 kit (assets/tank/v2/kit.json): the content cards. Every file it names loads, the
## kit ships no PNG the game does not use (the v2 tank, crewmen, planes and enemies are gone), and check()
## catches a broken manifest.

const DIR := "res://assets/tank/v2/"


func test_the_manifest_is_sound() -> void:
	var m := TankKit.load_manifest()
	assert_false(m.is_empty(), "kit.json parses")
	assert_eq(TankKit.check(m), [] as Array[String])


func test_every_card_loads() -> void:
	var m := TankKit.load_manifest()
	for c: String in m["cards"]:
		assert_not_null(load(DIR + str(m["cards"][c])) as Texture2D, c)


func test_the_kit_ships_only_what_the_game_uses() -> void:
	var m := TankKit.load_manifest()
	var used := {}
	for c: String in m["cards"]:
		used[str(m["cards"][c])] = true
	var stray: Array[String] = []
	for f in _pngs(DIR, ""):
		if f.begins_with("hud/") or f.begins_with("source/") or f.begins_with("tools_src/"):
			continue
		if not used.has(f):
			stray.append(f)
	assert_eq(stray, [] as Array[String], "PNGs nothing uses")
	for gone: String in ["planes", "crew", "zone_planes", "tank", "enemies"]:
		assert_false(m.has(gone), "no %s section" % gone)
	assert_false(DirAccess.dir_exists_absolute(DIR + "enemies"), "the v2 enemies are gone")


func test_check_names_a_missing_file_and_a_returned_enemies_section() -> void:
	var m: Dictionary = TankKit.load_manifest().duplicate(true)
	m["cards"]["card_mission"] = "nope.png"
	m["enemies"] = {}
	var errs := "\n".join(TankKit.check(m))
	assert_string_contains(errs, "missing file nope.png")
	assert_string_contains(errs, "an enemies section")


static func _pngs(dir: String, rel: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir + rel)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".png"):
			out.append(rel + f)
	for sub in d.get_directories():
		out.append_array(_pngs(dir, rel + sub + "/"))
	return out
