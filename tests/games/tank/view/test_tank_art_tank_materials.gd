extends GutTest
## The armour material (brief 3 "Not chunky pixel art", the round 3 scene critic): plates are flat
## tones bounded by seams (no camouflage blotches crossing them, no per-pixel dust), the tone spread
## from plate to plate is small, the hulls and tracked enemies carry a clean code-drawn skirt instead
## of mud speckle, and the Behemoth's soot is fainter than the crew's.

const EARTH := [
	"#3a2a24",
	"#5a3a2e",
	"#7d4f3a",
	"#17130f",
	"#241d17",
	"#33291f",
	"#443628",
	"#574634",
	"#6b5842"
]


## A speckled steel test plate: every pixel a random one of two neighbouring greys, a dark seam
## column at x 30, outlined by a transparent border.
func _speckled(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var col := TankMaterial.G3 if rng.randf() < 0.5 else TankMaterial.G4
			if x == 30:
				col = TankMaterial.G1
			img.set_pixel(x, y, col)
	return img


func test_speckle_becomes_flat_plates_bounded_by_seams() -> void:
	var img := _speckled(64, 40)
	TankMaterial.tonal_patches(img, "turret_test_plate")
	var xs := TankMaterial.seams_x("turret_test_plate")
	assert_true(30 in xs, "the drawn seam is found and kept as a plate boundary")
	var worst := 0.0
	for y in range(4, 38):
		for x in range(2, 61):
			if x in xs or x + 1 in xs or x - 1 in xs:
				continue
			var a := img.get_pixel(x, y).get_luminance()
			var b := img.get_pixel(x + 1, y).get_luminance()
			worst = maxf(worst, absf(a - b))
	assert_lt(worst, 0.025, "inside a plate a row only changes softly (soot), never in speckle")


func test_plates_are_at_most_the_family_width_and_tones_stay_close() -> void:
	var img := _speckled(120, 30)
	TankMaterial.tonal_patches(img, "hull_test_wide")
	var bounds := PackedInt32Array([0])
	bounds.append_array(TankMaterial.seams_x("hull_test_wide"))
	bounds.append(120)
	for i in range(bounds.size() - 1):
		assert_lte(bounds[i + 1] - bounds[i], int(TankMaterial.MAX_PLATE_W["hull_"]))
	var lo := INF
	var hi := -INF
	for k in 20:
		var off := TankMaterial._plate_offset(Vector2i(k, k % 3), 5)
		lo = minf(lo, off)
		hi = maxf(hi, off)
	assert_lte(hi - lo, TankMaterial.PLATE_SPREAD + 1e-6, "plate to plate within the spread")
	assert_lte(TankMaterial.PLATE_SPREAD, 0.06, "about 6% at most (the scene critic)")


func test_the_behemoth_soot_is_half_the_crews() -> void:
	assert_almost_eq(TankMaterial.SOOT_A_BOSS, TankMaterial.SOOT_A * 0.5, 1e-6)


func test_crew_hulls_have_a_clean_bolted_skirt_with_no_mud_speckle() -> void:
	for tank in ["bulwark", "rampart", "citadel"]:
		var id := TankSprites.hull_id(tank)
		var img := TankSprites.tex(id).get_image()
		if img.is_compressed():
			img.decompress()
		var top := TankPlaceholderArt.skirt_row(id)
		var def := TankRigs.tank_def(tank)
		var lowest := 0
		for rd: Variant in def.get("rooms", []):
			var r := TankRigs.rect((rd as Dictionary).get("rect"))
			lowest = maxi(lowest, int(r.end.y))
		assert_gt(top, lowest + 3, "%s: the skirt starts below the cutaway band" % tank)
		var earth := 0
		var edge := 0
		var opaque := 0
		for y in range(top, img.get_height()):
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				opaque += 1
				if "#" + c.to_html(false) in EARTH:
					earth += 1
				if y == top and c.to_html(false) == "444b52":
					edge += 1
		assert_gt(opaque, 0)
		assert_eq(earth, 0, "%s: no mud or rust speckle on the skirt" % tank)
		assert_gt(edge, img.get_width() / 2, "%s: the skirt's lit top edge runs along it" % tank)


func test_tracked_enemies_get_a_skirt_and_the_dugin_a_clean_foot() -> void:
	for id in ["enemy_light", "enemy_medium", "enemy_heavy", "enemy_destroyer", "enemy_dugin"]:
		var img := TankSprites.tex(id).get_image()
		if img.is_compressed():
			img.decompress()
		var earth := 0
		var edge := 0
		for y in range(img.get_height() / 2, img.get_height()):
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				if "#" + c.to_html(false) in EARTH:
					earth += 1
				if c.to_html(false) == "444b52":
					edge += 1
		assert_eq(earth, 0, "%s: no mud speckle on the lower hull" % id)
		if id != "enemy_dugin":
			assert_gt(edge, 10, "%s: a skirt with a lit top edge" % id)
