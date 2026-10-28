extends GutTest
## The v2 kit's pieces v3 still uses (assets/tank/v2/kit.json): the enemies, the Behemoth and the
## content cards; every file it names exists at the size it says, the kit ships nothing the game does
## not use (the v2 tank variants, crewmen and planes are gone), and check() catches a broken
## manifest.

const DIR := "res://assets/tank/v2/"


func test_the_manifest_is_sound() -> void:
	var m := TankKit.load_manifest()
	assert_false(m.is_empty(), "kit.json parses")
	assert_eq(TankKit.check(m), [] as Array[String])


func test_every_texture_loads_at_the_size_the_manifest_gives() -> void:
	var m := TankKit.load_manifest()
	for kind: String in m["enemies"]:
		var e: Dictionary = m["enemies"][kind]
		var t2 := load(DIR + str(e["file"])) as Texture2D
		assert_not_null(t2, kind)
		assert_eq(Vector2(t2.get_size()), TankKit.vec(e["size"]), kind)
	for c: String in m["cards"]:
		assert_not_null(load(DIR + str(m["cards"][c])) as Texture2D, c)


func test_the_kit_ships_only_what_the_game_uses() -> void:
	var m := TankKit.load_manifest()
	var used := {}
	for kind: String in m["enemies"]:
		used[str(m["enemies"][kind]["file"])] = true
	for c: String in m["cards"]:
		used[str(m["cards"][c])] = true
	var stray: Array[String] = []
	for f in _pngs(DIR, ""):
		if f.begins_with("hud/") or f.begins_with("source/") or f.begins_with("tools_src/"):
			continue
		if not used.has(f):
			stray.append(f)
	assert_eq(stray, [] as Array[String], "PNGs nothing uses")
	for gone: String in ["planes", "crew", "zone_planes", "tank"]:
		assert_false(m.has(gone), "no %s section" % gone)


func test_check_names_a_missing_file_and_a_muzzle_outside() -> void:
	var m: Dictionary = TankKit.load_manifest().duplicate(true)
	m["enemies"]["light"]["file"] = "enemies/nope.png"
	m["enemies"]["heavy"]["muzzle"] = [900, 900]
	(m["enemies"] as Dictionary).erase("dugin")
	var errs := "\n".join(TankKit.check(m))
	assert_string_contains(errs, "missing file enemies/nope.png")
	assert_string_contains(errs, "enemy heavy muzzle outside its sprite")
	assert_string_contains(errs, "no enemy dugin")


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
