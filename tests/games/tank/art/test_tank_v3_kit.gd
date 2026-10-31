extends GutTest
## The v3 tank kit (assets/tank/v3/kit.json, baked by assets/tank/v3/tools_src/bake.gd from the r6
## generator): the manifest is sound, the base art is the r6 re-pixelling (475 x 216, at most 63
## colours) with its turret block, every sheet holds its frames, the rooms, windows, wheels, lamps and
## searchlights lie on the sprite where the hitbox says the body is, the planes are the moderate
## forest, the tools are .gdignore'd, and check() catches a broken manifest.

const DIR := "res://assets/tank/v3/"


func test_the_manifest_is_sound() -> void:
	var m := TankRig.load_manifest()
	assert_false(m.is_empty(), "kit.json parses")
	assert_eq(TankRig.check(m), [] as Array[String])
	var rig := TankRig.shared()
	assert_eq(rig.size, Vector2(475, 216))
	assert_eq(rig.ground, 209.0)
	for seat in TankRig.SEATS:
		assert_ne(rig.seat_room(seat), Rect2(), "seat %s has its room" % seat)
	var engines: Array = []
	for seat2 in TankRig.SEATS:
		engines.append(rig.seats[seat2]["engine"])
	assert_eq(engines, ["diesel", "dynamo", "steam", "arc", "feed", "repair"], "the six seats")


func test_the_base_is_the_r6_pixel_art_with_at_most_63_colours() -> void:
	var rig := TankRig.shared()
	var img := rig.base_img
	assert_not_null(img)
	assert_eq(Vector2(img.get_size()), rig.size)
	var cols := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				cols[c.to_html(false)] = true
			else:
				assert_eq(c.a, 0.0, "hard alpha at %d,%d" % [x, y])
	assert_lte(cols.size(), 90, "the r6 palette (63) plus the dressing's few tones")
	assert_gt(cols.size(), 30)
	var tr := rig.turret_rect
	assert_true(Rect2(Vector2.ZERO, rig.size).encloses(tr), "the turret block on the sprite")
	assert_true(tr.has_point(rig.trunnion + Vector2(-1, 0)), "the trunnion on the turret")
	assert_between(rig.turret_pivot_x, tr.position.x, tr.end.x)


func test_every_sheet_holds_its_frames() -> void:
	var rig := TankRig.shared()
	for kind in TankRig.GEAR_SHEETS:
		var s: Dictionary = rig.sheets[kind]
		var tex: Texture2D = s["tex"]
		assert_eq(tex.get_width(), int(s["frames"]) * int(s["size"]), kind)
		assert_eq(tex.get_height(), int(s["size"]), kind)
	for part: String in ["air", "ground"]:
		var b: Dictionary = rig.blast[part]
		var sz: Vector2 = b["size"]
		var rows := ceili(float(b["frames"]) / float(rig.blast_cols))
		var tex2: Texture2D = b["tex"]
		assert_eq(tex2.get_width(), int(sz.x) * rig.blast_cols, part)
		assert_eq(tex2.get_height(), int(sz.y) * rows, part)
	assert_eq(rig.track_tex.get_height(), int(rig.track["rows"]) * 2, "lit and unlit shoes")
	assert_eq(rig.bow.size(), 2, "both bow guns")
	assert_not_null(rig.barrel_tex)
	assert_not_null(rig.lit_tex, "the turret searchlight's lit lens")


func test_the_live_parts_lie_on_the_body_the_hitbox_gives() -> void:
	var rig := TankRig.shared()
	var hull := rig.hit_rect("hull").merge(rig.hit_rect("track_run")).grow(2.0)
	var turret := rig.hit_rect("turret").grow(2.0)
	for k: String in rig.rooms:
		var r: Rect2 = rig.rooms[k]
		assert_true(hull.encloses(r) or turret.intersects(r), "room %s in the hull" % k)
	for w in rig.wheels:
		assert_true(hull.has_point(Vector2(w.x, w.y)), "a road wheel under the hull")
		assert_almost_eq(w.y + w.z + float(rig.gear["T"]), rig.ground, 0.6, "on the ground row")
	var hb := rig.hitbox
	assert_almost_eq(
		TankRig.vec(hb["muzzle"]).x, rig.trunnion.x + rig.gun_len, 0.01, "the hitbox's muzzle"
	)
	for k2 in 2:
		assert_eq(rig.bow[k2]["pivot"], TankRig.vec(hb["bow_pivots"][k2]), "bow pivot %d" % k2)
	var ts := rig.detail("searchlight")
	var rs := rig.detail("searchlight_rear")
	assert_almost_eq(float(ts["ang"]), 11.0, 0.01, "the turret searchlight 11 degrees down")
	assert_almost_eq(180.0 - float(rs["ang"]), 13.0, 0.01, "the rear one aft, 13 degrees down")
	assert_true(bool(rs.get("always", false)), "the rear one always on")
	assert_eq(rig.details_of("lamp_red").size(), 2, "two red position lights")
	assert_eq(rig.details_of("lamp_green").size(), 1, "one green")


func test_the_planes_are_the_moderate_forest() -> void:
	var rig := TankRig.shared()
	var names: Array = []
	for p in rig.planes:
		names.append(p["name"])
		assert_gte(
			(p["tex"] as Texture2D).get_width(), 1704, "%s tiles the widest canvas" % p["name"]
		)
	assert_eq(names, ["far", "ridge", "forest", "verge", "near", "foreground"])
	assert_false(
		DirAccess.dir_exists_absolute("res://assets/tank/v3env"), "the other strengths gone"
	)
	assert_true(
		FileAccess.file_exists(DIR + "tools_src/.gdignore"), "the generator is not imported"
	)


func test_check_names_a_missing_file_a_room_outside_and_a_seat_without_a_room() -> void:
	var m: Dictionary = TankRig.load_manifest().duplicate(true)
	m["base"] = "nope.png"
	m["rooms"]["gun"] = [470, 10, 80, 20]
	(m["seats"] as Array).pop_back()
	(m["windows"] as Dictionary).erase("breechwin")
	var errs := "\n".join(TankRig.check(m))
	assert_string_contains(errs, "missing file nope.png")
	assert_string_contains(errs, "room gun outside the sprite")
	assert_string_contains(errs, "seat repair has no room")
	assert_string_contains(errs, "window breechwin missing")
