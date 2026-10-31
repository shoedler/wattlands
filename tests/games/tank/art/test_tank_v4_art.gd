extends GutTest
## The v4 enemies' kit (assets/tank/v4, baked by tools_src/enemy_bake.gd; SPEC_TANK 5.1 to 5.4): the manifest
## is sound, every kind has its frozen size and its parts on the one atlas, the running gear sits on the
## ground, the palette keeps its discipline (cold, slit glows the only saturated colour, at most 40 colours a
## kind and 90 in the atlas without the wrecks), the rivets keep the tank's density, wrecks are burnt and
## torn, the bushes and the far ground are what the view expects. No test needs a display.

const DIR := "res://assets/tank/v4/"
const COLD_OUTLINE := Color("#0b0806")
const SLIT_CORE := Color("#d8fff4")
const SLIT_GLOW := Color("#7fe0d0")

var _kit: TankEnemyKit
var _atlas: Image


func before_all() -> void:
	_kit = TankEnemyKit.shared()
	_atlas = _kit.texture().get_image()
	_atlas.convert(Image.FORMAT_RGBA8)


## Every rect of a kind's row but the wrecks': {name: Rect2}.
func _live_rects(k: String) -> Dictionary:
	var row := _kit.kind(k)
	var out := {"base": row["base"], "gun": row["gun"]["rect"]}
	if row.has("front"):
		out["front"] = row["front"]
	if row.has("turret"):
		out["turret"] = row["turret"]["rect"]
	for s: String in row["sheets"]:
		out["sheet_" + s] = row["sheets"][s]["rect"]
	if row.has("track"):
		out["track"] = row["track"]["rect"]
	for b: Dictionary in row.get("bogies", []):
		out["bogie%d" % int(b["x_offset"])] = b["rect"]
	return out


func _colours_of(rects: Array, into: Dictionary) -> void:
	for r: Rect2 in rects:
		var ri := Rect2i(r)
		for y in range(ri.position.y, ri.end.y):
			for x in range(ri.position.x, ri.end.x):
				var c := _atlas.get_pixel(x, y)
				if c.a > 0.5:
					into[c.to_html(false)] = true


func test_the_manifest_is_sound() -> void:
	var m := TankEnemyKit.load_manifest()
	assert_false(m.is_empty(), "enemies.json parses")
	assert_eq(TankEnemyKit.check(m), [] as Array[String])
	assert_eq(str(m["atlas"]), "enemies.png")
	assert_lte(_atlas.get_width(), 2048)
	assert_lte(_atlas.get_height(), 2048)
	var imp := FileAccess.get_file_as_string(DIR + "enemies.png.import")
	assert_true(imp.contains("compress/mode=0"), "the atlas stays lossless")
	assert_true(imp.contains("mipmaps/generate=false"), "no mipmaps on pixel art")
	assert_true(
		FileAccess.file_exists(DIR + "tools_src/.gdignore"), "the tools stay out of the import"
	)


func test_every_kind_has_its_frozen_size_and_parts_inside_the_atlas() -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(_atlas.get_size()))
	for k: String in TankEnemyKit.SIZES:
		var frozen: Array = TankEnemyKit.SIZES[k]
		var row := _kit.kind(k)
		assert_eq(row["size"], Vector2(float(frozen[0]), float(frozen[1])), k)
		assert_eq(int(row["faces"]), int(frozen[2]), k)
		assert_eq((row["base"] as Rect2).size, row["size"], "%s base" % k)
		assert_eq((row["wreck"] as Rect2).size, row["size"], "%s wreck" % k)
		assert_eq((row["sil"] as Rect2).size, row["size"], "%s silhouette" % k)
		var rects := _live_rects(k)
		for n: String in rects:
			assert_true(bounds.encloses(rects[n]), "%s %s inside the atlas" % [k, n])
		assert_true(row.has("muzzle_at_0"), k)
		assert_true(row.has("exhaust"), k)
		assert_true(row.has("hit_centre"), k)
		assert_false((row["slits"] as Array).is_empty(), "%s has slits" % k)


## SPEC_TANK 5.2's table.
func test_the_running_gear_of_each_kind_matches_the_table() -> void:
	var table := {
		"tankette": [3, 4.0, 2.0],
		"recon": [6, 6.0, 0.0],
		"light": [4, 5.5, 2.5],
		"medium": [6, 6.0, 3.0],
		"heavy": [8, 7.0, 4.0],
		"destroyer": [7, 6.0, 3.0],
		"behemoth": [15, 7.0, 4.0],
	}
	for k: String in table:
		var row := _kit.kind(k)
		var g: Dictionary = row["gear"]
		var wheels: Array[Vector3] = g["wheels"]
		assert_eq(wheels.size(), table[k][0], "%s wheels" % k)
		assert_eq(float(g["T"]), table[k][2], "%s track" % k)
		for w in wheels:
			assert_eq(w.z, table[k][1], "%s wheel radius" % k)
			if not bool(g["far"][wheels.find(w)]):
				assert_eq(
					w.y + w.z + float(g["T"]), float(row["ground"]), "%s rests on the ground" % k
				)
	assert_false(_kit.kind("recon").has("track"), "the recon car runs on tyres")
	assert_eq((_kit.kind("behemoth")["bogies"] as Array).size(), 3, "three bogies")
	assert_false(_kit.kind("destroyer").has("turret"), "a casemate")


func test_shoes_are_real_shoes() -> void:
	for k: String in ["tankette", "light", "medium", "heavy", "destroyer", "behemoth"]:
		var tr: Dictionary = _kit.kind(k)["track"]
		var rect := Rect2i(tr["rect"])
		assert_eq(rect.size.x, int(float(tr["pitch"]) * int(tr["sub_u"])), k)
		assert_eq(rect.size.y, int(tr["rows"]) * 2, "%s: lit over unlit rows" % k)
		# the shoe has a dark gap at its joint and a lighter grouser: separate links, not a band
		var mid := rect.position.y + int(tr["rows"]) / 2
		var seen := {}
		for x in range(rect.position.x, rect.end.x):
			seen[_atlas.get_pixel(x, mid).to_html()] = true
		assert_gt(seen.size(), 1, "%s: one shoe is not one flat colour" % k)


func test_the_palette_stays_within_its_discipline() -> void:
	var atlas_all := {}
	for k: String in TankEnemyKit.SIZES:
		var one := {}
		var rects: Array = _live_rects(k).values()
		_colours_of(rects, one)
		_colours_of(rects, atlas_all)
		assert_lte(one.size(), 40, "%s: at most 40 opaque colours" % k)
		assert_gte(one.size(), 8, "%s: not a flat fill" % k)
	assert_lte(atlas_all.size(), 90, "at most 90 in the atlas without the wrecks")


func test_nothing_warm_on_a_live_enemy_and_only_the_slits_are_saturated() -> void:
	for k: String in TankEnemyKit.SIZES:
		var cols := {}
		_colours_of(_live_rects(k).values(), cols)
		for h: String in cols:
			var c := Color(h)
			if c.is_equal_approx(COLD_OUTLINE):
				continue
			assert_false(c.r > c.g + 0.012 and c.r > c.b + 0.012, "%s: %s is warm" % [k, h])
			if c.s > 0.42 and c.v > 0.3:
				assert_true(
					c.is_equal_approx(SLIT_CORE) or c.is_equal_approx(SLIT_GLOW),
					"%s: %s is saturated and no slit" % [k, h]
				)


func test_each_kind_shows_its_slit_glow() -> void:
	for k: String in TankEnemyKit.SIZES:
		var cols := {}
		_colours_of(_live_rects(k).values(), cols)
		assert_true(cols.has(SLIT_GLOW.to_html(false)), "%s: the slits glow" % k)


## One rivet per 7-9 px along a seam: the medium's long seam on the lower hull (row seam + 2).
func test_the_rivets_keep_the_tanks_density() -> void:
	var row := _kit.kind("medium")
	var base := Rect2i(row["base"])
	var y := base.position.y + 28 + 2
	var heads := 0
	var bright := Color("#8c9584")
	# the row holds details in places; count over the plates' clear span
	for x in range(base.position.x + 38, base.position.x + 104):
		for dy in range(-1, 2):
			if _atlas.get_pixel(x, y + dy).is_equal_approx(bright):
				heads += 1
				break
	var per_100 := float(heads) / 66.0 * 100.0
	assert_between(per_100, 9.0, 16.0, "%.1f rivets per 100 px of seam" % per_100)


func test_no_lone_pixel_floats_off_a_silhouette() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var rects: Array = [row["base"]]
		if row.has("turret"):
			rects.append(row["turret"]["rect"])
		for r: Rect2 in rects:
			var ri := Rect2i(r)
			var lone := 0
			for y in range(ri.position.y, ri.end.y):
				for x in range(ri.position.x, ri.end.x):
					if _atlas.get_pixel(x, y).a < 0.5:
						continue
					var n := 0
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var q := Vector2i(x + dx, y + dy)
							if (dx != 0 or dy != 0) and ri.has_point(q):
								n += int(_atlas.get_pixel(q.x, q.y).a > 0.5)
					lone += int(n == 0)
			assert_eq(lone, 0, "%s: no stray pixels" % k)


func test_plates_are_not_a_flat_fill() -> void:
	for k: String in TankEnemyKit.SIZES:
		var ri := Rect2i(_kit.kind(k)["base"])
		var hist := {}
		var total := 0
		for y in range(ri.position.y, ri.end.y):
			for x in range(ri.position.x, ri.end.x):
				var c := _atlas.get_pixel(x, y)
				if c.a > 0.5:
					hist[c.to_html(false)] = int(hist.get(c.to_html(false), 0)) + 1
					total += 1
		var top := 0
		for h: String in hist:
			top = maxi(top, int(hist[h]))
		assert_lt(float(top) / float(total), 0.5, "%s: no colour rules the hull" % k)


func test_wrecks_are_burnt_and_torn() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var w := Rect2i(row["wreck"])
		var s := Rect2i(row["sil"])
		var hist := {}
		var gone := 0
		for y in w.size.y:
			for x in w.size.x:
				var c := _atlas.get_pixel(w.position.x + x, w.position.y + y)
				if c.a > 0.5:
					hist[c.to_html(false)] = true
				elif _atlas.get_pixel(s.position.x + x, s.position.y + y).a > 0.5:
					gone += 1
		assert_lte(hist.size(), 8, "%s: the burn ramp and its lips, no more" % k)
		assert_gt(gone, 4, "%s: bites gone from the shape" % k)
		assert_false(hist.has(SLIT_GLOW.to_html(false)), "%s: dead slits" % k)
		assert_true(hist.has("0d0a08") or hist.has("1c1410"), "%s: charred" % k)
		assert_true(row.has("wreck_fire"), "%s burns somewhere" % k)


func test_the_behemoths_bogies_each_have_a_wrecked_sprite() -> void:
	var bogies: Array = _kit.kind("behemoth")["bogies"]
	var seen := {}
	for b: Dictionary in bogies:
		assert_gt((b["wrecked"] as Rect2).size.x, (b["rect"] as Rect2).size.x * 0.8)
		seen[b["x_offset"]] = true
		assert_eq((b["wheels"] as Array).size(), 5, "five road wheels")
		assert_eq((b["sprocket"] as Vector3).z, 10.0, "sprocket r 10")
	assert_eq(seen.size(), 3)
	assert_true(_kit.kind("behemoth").has("secondary_muzzle"), "the bow secondary")
	assert_true(_kit.kind("behemoth").has("furnace"), "the furnace vent")


func test_the_bushes_are_feet_down_on_their_sheet() -> void:
	assert_not_null(_kit.bushes())
	var rects := _kit.bush_rects()
	assert_gte(rects.size(), 4)
	var img := _kit.bushes().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var bounds := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	for r in rects:
		assert_true(bounds.encloses(r), "a bush inside its sheet")
		var ri := Rect2i(r)
		var low := 0
		for x in range(ri.position.x, ri.end.x):
			low += int(img.get_pixel(x, ri.end.y - 1).a > 0.5)
		assert_gt(low, 0, "its foot is on the rect's bottom row")
		var top := 0
		for x2 in range(ri.position.x, ri.end.x):
			top += int(img.get_pixel(x2, ri.position.y).a > 0.5)
		assert_lt(top, ri.size.x / 2, "a crown, not a block")


func test_the_far_ground_tiles_and_goes_soft_at_its_top() -> void:
	var tex := _kit.far_ground()
	assert_not_null(tex)
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	assert_eq(img.get_size(), Vector2i(1024, 170))
	var seam := 0.0
	var inner := 0.0
	for y in range(40, 130):
		seam += _diff(img.get_pixel(1023, y), img.get_pixel(0, y))
		inner += _diff(img.get_pixel(500, y), img.get_pixel(501, y))
	assert_lt(seam, inner * 1.6, "the band's seam is no louder than any other column pair")
	assert_lt(img.get_pixel(100, 0).a, 0.3, "its top fades out")
	assert_eq(img.get_pixel(100, 60).a, 1.0, "the enemies' band is solid")
	var band := 0.0
	var foot := 0.0
	for x in range(0, 1024, 4):
		band += img.get_pixel(x, 68).v
		foot += img.get_pixel(x, 165).v
	assert_gt(band, foot, "the moon on the enemies' band, the foreground dark")


static func _diff(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func test_a_broken_manifest_is_caught() -> void:
	assert_eq(TankEnemyKit.check({}), ["no kinds"] as Array[String])
	assert_eq(TankEnemyKit.check({"kinds": {}}).size(), 9, "7 kinds, bushes, far_ground")
	var kinds := {}
	for k: String in TankEnemyKit.SIZES:
		kinds[k] = {"size": [1, 1]}
	assert_eq(TankEnemyKit.check({"kinds": kinds}), ["no bushes", "no far_ground"] as Array[String])
