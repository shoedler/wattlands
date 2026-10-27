extends GutTest
## The v2 art kit (docs/games/tank.md 3.2; assets/tank/v2/kit.json, its single manifest): every file
## it names exists at the size it says, rooms and anchors lie inside their images, the rooms follow
## the brief's order per tank, the kit ships nothing the game does not use, and check() catches a
## broken manifest.

const DIR := "res://assets/tank/v2/"


func test_the_manifest_is_sound() -> void:
	var m := TankKit.load_manifest()
	assert_false(m.is_empty(), "kit.json parses")
	assert_eq(TankKit.check(m), [] as Array[String])


func test_every_texture_loads_at_the_size_the_manifest_gives() -> void:
	var m := TankKit.load_manifest()
	for vn: String in TankKit.VARIANTS:
		var v: Dictionary = m["tank"]["variants"][vn]
		var tex := load(DIR + str(v["file"])) as Texture2D
		assert_not_null(tex, vn)
		assert_eq(Vector2(tex.get_size()), TankKit.vec(v["size"]), vn)
	for kind: String in m["enemies"]:
		var e: Dictionary = m["enemies"][kind]
		var t2 := load(DIR + str(e["file"])) as Texture2D
		assert_eq(Vector2(t2.get_size()), TankKit.vec(e["size"]), kind)
	for p: Dictionary in m["planes"]:
		var t3 := load(DIR + str(p["file"])) as Texture2D
		assert_gte(t3.get_width(), 1704, "%s tiles across the widest flex canvas" % p["name"])
		assert_lte(float(p["y0"]) + t3.get_height(), 540.0, "%s inside the frame" % p["name"])
	for pose: String in m["crew"]["frames"]:
		for f: String in m["crew"]["frames"][pose]:
			var t4 := load(DIR + f) as Texture2D
			assert_eq(Vector2(t4.get_size()), TankKit.vec(m["crew"]["cell"]), f)


func test_rooms_run_rear_to_front_per_tank_with_their_plaques_inside() -> void:
	var kit := TankKit.shared()
	var want := {
		"tank_1rider": ["diesel"],
		"tank_2rider": ["diesel", "dynamo"],
		"tank_3rider": ["diesel", "steam", "dynamo"],
		"tank_4rider": ["diesel", "steam", "dynamo", "arc"],
	}
	for vn: String in want:
		var engines: Array = []
		var last_x := -1.0
		for room: Dictionary in kit.rooms(vn):
			if not room.has("engine"):
				continue
			engines.append(room["engine"])
			var r := TankKit.rect_of(room)
			assert_gt(r.position.x, last_x, "%s rooms rear to front" % vn)
			last_x = r.position.x
			var plaque := TankHullDraw.plaque_at(room)
			assert_true(
				r.grow(1.0).encloses(Rect2(plaque, Vector2(9, 9))),
				"%s %s plaque" % [vn, room["id"]]
			)
		assert_eq(engines, want[vn], vn)
	assert_true(kit.has_anchor("tank_4rider", "searchlight_tower_lens"), "the Bastion's tower")
	assert_false(kit.has_anchor("tank_3rider", "searchlight_tower_lens"))


func test_each_variant_gets_its_hull_with_the_barrel_erased_and_the_barrel() -> void:
	var kit := TankKit.shared()
	for vn: String in TankKit.VARIANTS:
		var tv := kit.variant(vn)
		assert_not_null(tv.get("hull"), vn)
		assert_not_null(tv.get("barrel"), "%s barrel" % vn)
		var img := (tv["hull"] as Texture2D).get_image()
		var piv := kit.anchor(vn, "barrel_pivot")
		var muz := kit.anchor(vn, "muzzle")
		var mid := Vector2i(roundi((piv.x + muz.x) * 0.5), roundi(piv.y))
		assert_almost_eq(img.get_pixelv(mid).a, 0.0, 0.01, "%s: the baked barrel is gone" % vn)
	assert_lt(
		(kit.variant("tank_1rider")["barrel"] as Texture2D).get_width(),
		(kit.variant("tank_3rider")["barrel"] as Texture2D).get_width(),
		"the Bulwark's turret is scaled down"
	)


func test_the_kit_ships_only_what_the_game_uses() -> void:
	var m := TankKit.load_manifest()
	var used := {}
	for p: Dictionary in m["planes"]:
		used[str(p["file"])] = true
	used[str(m["tank"]["barrel"])] = true
	for vn: String in m["tank"]["variants"]:
		used[str(m["tank"]["variants"][vn]["file"])] = true
	for pose: String in m["crew"]["frames"]:
		for f: String in m["crew"]["frames"][pose]:
			used[f] = true
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


func test_check_names_a_missing_file_a_room_outside_and_a_missing_room() -> void:
	var m: Dictionary = TankKit.load_manifest().duplicate(true)
	m["planes"][0]["file"] = "planes2/nope.png"
	m["tank"]["variants"]["tank_2rider"]["rooms"][0]["rect"] = [400, 10, 80, 20]
	var rooms: Array = m["tank"]["variants"]["tank_4rider"]["rooms"]
	for i in rooms.size():
		if str(rooms[i].get("engine", "")) == "arc":
			rooms.remove_at(i)
			break
	m["tank"]["variants"]["tank_3rider"]["anchors"].erase("headlight")
	var errs := "\n".join(TankKit.check(m))
	assert_string_contains(errs, "missing file planes2/nope.png")
	assert_string_contains(errs, "tank_2rider room diesel outside the image")
	assert_string_contains(errs, "tank_4rider engine rooms")
	assert_string_contains(errs, "tank_3rider has no anchor headlight")


func test_the_variant_follows_the_hull_and_the_crew() -> void:
	assert_eq(TankKit.variant_for("bulwark", 1), "tank_1rider")
	assert_eq(TankKit.variant_for("rampart", 2), "tank_2rider")
	assert_eq(TankKit.variant_for("citadel", 3), "tank_3rider")
	assert_eq(TankKit.variant_for("bastion", 4), "tank_4rider")
	assert_eq(TankKit.variant_for("", 4), "tank_4rider", "by crew size when the id is unknown")


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
