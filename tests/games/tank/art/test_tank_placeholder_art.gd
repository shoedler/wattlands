extends GutTest
## TankPlaceholderArt (brief 3, 4: "a placeholder per sprite id"): every one of the 61 ids of
## assets/tank/art.json is drawn at its size from the 32 palette colours and nothing else, with
## readable silhouettes (enemies face left with the gun at the rig's muzzle, wheels are face-on
## and round, hulls are cut flat at the bottom, strips have no gap under them), cached per id,
## deterministic and never written to assets/tank/sprites/.

const ART_JSON := "res://assets/tank/art.json"
const RIGS_JSON := "res://assets/tank/rigs.json"
const ENEMIES: Array[String] = [
	"enemy_light", "enemy_medium", "enemy_heavy", "enemy_destroyer", "enemy_dugin"
]
const WHEELS: Array[String] = [
	"road_wheel",
	"drive_sprocket",
	"idler_wheel",
	"flywheel_large",
	"flywheel_small",
	"gear_large",
	"gear_medium"
]
const HULLS: Array[String] = ["hull_bulwark", "hull_rampart", "hull_citadel"]

static var _images: Dictionary = {}


func _art() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ART_JSON))


## The placeholder of `id`, drawn once per run (the dictionary is shared by every test).
func _img(id: String) -> Image:
	if not _images.has(id):
		_images[id] = TankPlaceholderArt.placeholder_image(id)
	return _images[id]


func _opaque_count(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n


## [x0, y0, x1, y1] of the opaque pixels (x1, y1 inclusive); [-1, -1, -1, -1] when none.
func _bbox(img: Image) -> Array[int]:
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return [-1, -1, -1, -1]
	return [x0, y0, x1, y1]


# --- art.json -----------------------------------------------------------------------------------------


func test_art_json_lists_61_unique_sprites_and_a_32_colour_palette() -> void:
	var art := _art()
	var sprites: Array = art["sprites"]
	assert_eq(sprites.size(), 61)
	var seen := {}
	for s: Dictionary in sprites:
		var id := str(s["id"])
		assert_false(seen.has(id), "unique id %s" % id)
		seen[id] = true
		var size: Array = s["size"]
		assert_eq(size.size(), 2, id)
		assert_gt(int(size[0]), 0, id)
		assert_gt(int(size[1]), 0, id)
		assert_true(str(s.get("prompt", "")) != "", "%s has a prompt" % id)
	var palette: Array = art["palette"]
	assert_eq(palette.size(), 32)
	var colours := {}
	for p: String in palette:
		assert_false(colours.has(p.to_lower()), "palette colour %s is unique" % p)
		colours[p.to_lower()] = true
	assert_eq(TankPlaceholderArt.ids().size(), 61)
	assert_eq(TankPlaceholderArt.palette().size(), 32)


func test_the_palette_constants_are_exactly_art_json() -> void:
	var from_consts: Array[Color] = [
		TankPlaceholderArt.G0,
		TankPlaceholderArt.G1,
		TankPlaceholderArt.G2,
		TankPlaceholderArt.G3,
		TankPlaceholderArt.G4,
		TankPlaceholderArt.G5,
		TankPlaceholderArt.G6,
		TankPlaceholderArt.G7,
		TankPlaceholderArt.G8,
		TankPlaceholderArt.G9,
		TankPlaceholderArt.G10,
		TankPlaceholderArt.G11,
		TankPlaceholderArt.B0,
		TankPlaceholderArt.B1,
		TankPlaceholderArt.B2,
		TankPlaceholderArt.B3,
		TankPlaceholderArt.B4,
		TankPlaceholderArt.B5,
		TankPlaceholderArt.O0,
		TankPlaceholderArt.O1,
		TankPlaceholderArt.O2,
		TankPlaceholderArt.R0,
		TankPlaceholderArt.R1,
		TankPlaceholderArt.R2,
		TankPlaceholderArt.F0,
		TankPlaceholderArt.F1,
		TankPlaceholderArt.F2,
		TankPlaceholderArt.F3,
		TankPlaceholderArt.C0,
		TankPlaceholderArt.C1,
		TankPlaceholderArt.C2,
		TankPlaceholderArt.C3,
	]
	var pal := TankPlaceholderArt.palette()
	assert_eq(from_consts.size(), pal.size())
	for i in mini(from_consts.size(), pal.size()):
		assert_eq(from_consts[i].to_html(false), pal[i].to_html(false), "colour %d" % i)


func test_only_the_brief_s_sprites_are_opaque() -> void:
	var opaque: Array[String] = []
	for id in TankPlaceholderArt.ids():
		if TankPlaceholderArt.is_opaque(id):
			opaque.append(id)
	opaque.sort()
	var want: Array[String] = [
		"bg_ground",
		"bg_sky",
		"picker_card",
		"room_bulwark",
		"room_diesel",
		"room_dynamo",
		"room_steam"
	]
	assert_eq(opaque, want)
	var strips: Array[String] = []
	for id in TankPlaceholderArt.ids():
		if TankPlaceholderArt.is_strip(id):
			strips.append(id)
	assert_eq(strips.size(), 8, "the strips wider than 3:1 are tile + mirror segments")


# --- Every id, at its size, in the palette -----------------------------------------------------------


func test_every_id_is_drawn_at_its_art_json_size() -> void:
	for s: Dictionary in _art()["sprites"]:
		var id := str(s["id"])
		var img := _img(id)
		assert_eq(
			Vector2i(img.get_width(), img.get_height()),
			Vector2i(int(s["size"][0]), int(s["size"][1])),
			id
		)
		assert_eq(TankPlaceholderArt.size_of(id), Vector2i(img.get_width(), img.get_height()), id)


func test_every_pixel_is_transparent_or_an_opaque_palette_colour() -> void:
	var allowed := {}
	for c in TankPlaceholderArt.palette():
		allowed[c.to_html(false)] = true
	for id in TankPlaceholderArt.ids():
		var img := _img(id)
		var bad := ""
		for y in img.get_height():
			for x in img.get_width():
				var px := img.get_pixel(x, y)
				if px.a < 0.01:
					continue
				if px.a < 0.999 or not allowed.has(px.to_html(false)):
					bad = "(%d,%d) %s a=%.2f" % [x, y, px.to_html(true), px.a]
					break
			if bad != "":
				break
		assert_eq(bad, "", "%s: only opaque palette colours" % id)


func test_every_id_is_drawn_not_a_flat_block() -> void:
	for id in TankPlaceholderArt.ids():
		var img := _img(id)
		var colours := {}
		for y in img.get_height():
			for x in img.get_width():
				var px := img.get_pixel(x, y)
				if px.a > 0.5:
					colours[px.to_html(false)] = true
		assert_gte(colours.size(), 3, "%s has shading, not a flat block" % id)


func test_opaque_sprites_have_no_hole_and_the_others_have_background() -> void:
	for id in TankPlaceholderArt.ids():
		var img := _img(id)
		var total := img.get_width() * img.get_height()
		var n := _opaque_count(img)
		if TankPlaceholderArt.is_opaque(id):
			assert_eq(n, total, "%s is fully opaque" % id)
		else:
			assert_lt(n, total, "%s is transparent around its subject" % id)
			assert_gt(n, total / 20, "%s is not nearly empty" % id)


func test_strips_leave_no_gap_at_the_bottom_and_the_sprites_fill_their_frames() -> void:
	for id in TankPlaceholderArt.ids():
		if not TankPlaceholderArt.is_strip(id) or id == "fg_debris":
			continue
		var img := _img(id)
		for x in img.get_width():
			assert_gt(
				img.get_pixel(x, img.get_height() - 1).a, 0.5, "%s bottom row at x=%d" % [id, x]
			)
	# A tile strip repeats with flipped copies: its left and right columns need not match, but the
	# hills (a periodic ridge) do, so a plain repeat is seamless too.
	var hills := _img("bg_hills_far")
	var top_l := -1
	var top_r := -1
	for y in hills.get_height():
		if top_l < 0 and hills.get_pixel(0, y).a > 0.5:
			top_l = y
		if top_r < 0 and hills.get_pixel(hills.get_width() - 1, y).a > 0.5:
			top_r = y
	assert_lte(absi(top_l - top_r), 2, "the far hills are periodic")


# --- Silhouettes ---------------------------------------------------------------------------------------


func test_hulls_are_cut_flat_at_the_bottom_with_a_sloped_front() -> void:
	for id in HULLS:
		var img := _img(id)
		var w := img.get_width()
		var h := img.get_height()
		for x in w:
			assert_gt(img.get_pixel(x, h - 1).a, 0.5, "%s skirt is flat at x=%d" % [id, x])
		# The roof is shorter than the body: the top-right corner is cut (glacis), the top row is
		# narrower than the bottom row.
		var top_n := 0
		for x in w:
			if img.get_pixel(x, 0).a > 0.5:
				top_n += 1
		assert_lt(top_n, w - 8, "%s has a sloped front and rear" % id)
		assert_lt(img.get_pixel(w - 1, 0).a, 0.5, "%s: glacis cuts the roof's front corner" % id)


func test_enemies_face_left_with_the_gun_at_the_rigs_muzzle() -> void:
	var rigs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RIGS_JSON))
	for id in ENEMIES:
		var img := _img(id)
		var mz: Array = rigs["enemies"][id]["muzzle"]
		var found := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := int(mz[0]) + dx
				var y := int(mz[1]) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					found = found or img.get_pixel(x, y).a > 0.5
		assert_true(found, "%s has barrel pixels at its muzzle %s" % [id, str(mz)])
		# The gun side (left) reaches the sprite's edge as a thin barrel; the body is far taller.
		var left := 0
		var body := 0
		for y in img.get_height():
			if img.get_pixel(1, y).a > 0.5:
				left += 1
			if img.get_pixel(int(img.get_width() * 0.55), y).a > 0.5:
				body += 1
		assert_gt(left, 0, "%s: the barrel reaches the left edge" % id)
		if id == "enemy_dugin":
			continue  # its left edge is the revetment wall under the barrel
		assert_lt(left * 2, body, "%s: a thin barrel on the left, a body behind it" % id)


func test_enemy_silhouettes_are_pairwise_distinct() -> void:
	var grids := {}
	for id in ENEMIES:
		var img := _img(id)
		var g := PackedByteArray()
		for gy in 16:
			for gx in 32:
				var x := int((gx + 0.5) / 32.0 * img.get_width())
				var y := int((gy + 0.5) / 16.0 * img.get_height())
				g.append(1 if img.get_pixel(x, y).a > 0.5 else 0)
		grids[id] = g
	for i in ENEMIES.size():
		for j in range(i + 1, ENEMIES.size()):
			var a: PackedByteArray = grids[ENEMIES[i]]
			var b: PackedByteArray = grids[ENEMIES[j]]
			var diff := 0
			for k in a.size():
				if a[k] != b[k]:
					diff += 1
			assert_gte(diff, 25, "%s and %s differ on a 32 x 16 grid" % [ENEMIES[i], ENEMIES[j]])
	# Sizes follow the brief: light < medium < heavy by area.
	var area := func(id: String) -> int: return _img(id).get_width() * _img(id).get_height()
	assert_lt(area.call("enemy_light"), area.call("enemy_medium"))
	assert_lt(area.call("enemy_medium"), area.call("enemy_heavy"))


func test_wheels_and_gears_are_face_on_and_round() -> void:
	for id in WHEELS:
		var img := _img(id)
		var bb := _bbox(img)
		var w := bb[2] - bb[0] + 1
		var h := bb[3] - bb[1] + 1
		assert_lte(absi(w - h), 1, "%s is as wide as it is tall" % id)
		assert_gte(w, img.get_width() - 3, "%s fills its frame" % id)
		var cx := (bb[0] + bb[2]) / 2.0
		var cy := (bb[1] + bb[3]) / 2.0
		assert_lte(absf(cx - (img.get_width() - 1) / 2.0), 1.5, "%s is centred in x" % id)
		assert_lte(absf(cy - (img.get_height() - 1) / 2.0), 1.5, "%s is centred in y" % id)


func test_the_boss_parts_have_their_boxes_and_the_broken_ones_differ() -> void:
	for pair: Array in [["boss_turret", "boss_turret_broken"], ["boss_bogie", "boss_bogie_broken"]]:
		var a := _img(pair[0])
		var b := _img(pair[1])
		assert_eq(Vector2i(a.get_width(), a.get_height()), Vector2i(b.get_width(), b.get_height()))
		var diff := 0
		for y in a.get_height():
			for x in a.get_width():
				if a.get_pixel(x, y) != b.get_pixel(x, y):
					diff += 1
		assert_gt(diff, a.get_width() * a.get_height() / 10, "%s is visibly damaged" % pair[1])
	var hull := _img("boss_hull")
	assert_eq(Vector2i(hull.get_width(), hull.get_height()), Vector2i(320, 100))
	# Facing left: the sloped front is on the left, so the left edge is lower than the right edge.
	var left_top := -1
	var right_top := -1
	for y in hull.get_height():
		if left_top < 0 and hull.get_pixel(1, y).a > 0.5:
			left_top = y
		if right_top < 0 and hull.get_pixel(hull.get_width() - 2, y).a > 0.5:
			right_top = y
	assert_gt(left_top, right_top, "the Behemoth's sloped front is on the left")


func test_lights_are_the_only_bright_saturated_colours() -> void:
	# Brief 3: everything else stays desaturated; only the warm and cold light colours are saturated.
	var lights := {}
	for c: Color in [
		TankPlaceholderArt.F0,
		TankPlaceholderArt.F1,
		TankPlaceholderArt.F2,
		TankPlaceholderArt.F3,
		TankPlaceholderArt.C1,
		TankPlaceholderArt.C2,
		TankPlaceholderArt.C3
	]:
		lights[c.to_html(false)] = true
	for c in TankPlaceholderArt.palette():
		if lights.has(c.to_html(false)):
			continue
		assert_lt(c.s, 0.6, "%s is desaturated" % c.to_html(false))
	# Effects are made of lights: the muzzle flash and explosions are mostly warm.
	for id in ["muzzle_flash", "explosion_large", "explosion_small", "fire_small", "firebox_flame"]:
		var img := _img(id)
		var warm := 0
		var total := 0
		for y in img.get_height():
			for x in img.get_width():
				var px := img.get_pixel(x, y)
				if px.a > 0.5:
					total += 1
					if lights.has(px.to_html(false)):
						warm += 1
		assert_gt(float(warm) / maxf(total, 1.0), 0.5, "%s is mostly light colours" % id)


# --- Texture cache, log once, determinism, no files ----------------------------------------------------


func test_texture_is_cached_per_id_and_logs_once() -> void:
	var id := "prop_rubble"
	var t1 := TankPlaceholderArt.texture(id)
	var logged_before: int = TankPlaceholderArt._logged.size()
	var t2 := TankPlaceholderArt.texture(id)
	assert_same(t1, t2, "the second request returns the cached texture")
	assert_eq(TankPlaceholderArt._logged.size(), logged_before, "no second log for a cached id")
	assert_true(TankPlaceholderArt._logged.has(id), "the missing sprite was logged once")
	assert_eq(t1.get_size(), Vector2(TankPlaceholderArt.size_of(id)))


func test_every_id_has_a_texture_of_its_size() -> void:
	for id in TankPlaceholderArt.ids():
		var tex := TankPlaceholderArt.texture(id)
		assert_not_null(tex, id)
		assert_eq(tex.get_size(), Vector2(TankPlaceholderArt.size_of(id)), id)


func test_placeholders_are_deterministic() -> void:
	for id in ["hull_citadel", "bg_village_near", "explosion_large", "enemy_heavy", "picker_card"]:
		var a := TankPlaceholderArt.placeholder_image(id)
		var b := TankPlaceholderArt.placeholder_image(id)
		assert_eq(a.get_data(), b.get_data(), "%s draws the same twice" % id)


func test_an_unknown_id_gets_a_block_and_never_crashes() -> void:
	var img := TankPlaceholderArt.placeholder_image("no_such_sprite")
	assert_eq(Vector2i(img.get_width(), img.get_height()), Vector2i(16, 16))
	assert_gt(_opaque_count(img), 0)


func test_placeholders_are_never_saved_as_sprite_files() -> void:
	# A real art pass may add PNGs; a PNG that is exactly a placeholder means one was dumped.
	var dir := DirAccess.open("res://assets/tank/sprites")
	if dir == null:
		pass_test("assets/tank/sprites does not exist")
		return
	for f in dir.get_files():
		if not f.ends_with(".png"):
			continue
		var id := f.get_basename()
		if TankPlaceholderArt.sprite_def(id).is_empty():
			continue
		var on_disk := Image.load_from_file("res://assets/tank/sprites/" + f)
		assert_ne(
			on_disk.get_data(), _img(id).get_data(), "%s on disk is not a saved placeholder" % f
		)
	assert_true(true)
