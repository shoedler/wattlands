extends GutTest
## Polish round 4, the world: composed near planes without a mirror axis, no gallows silhouette,
## the sky's banks and ridge, the foreground plane's fade over the hull, telegraph poles in pairs and
## the depot yard's props.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const NP := TankBackdrop.NearPlane


func test_near_planes_are_wide_and_tile_unmirrored() -> void:
	for id in TankBackdrop.NEAR_IDS:
		var img := NP.image(id)
		assert_eq(img.get_width(), NP.W, id)
		var tex := NP.texture(id)
		assert_eq(tex.get_width(), NP.W, id)


func test_the_flanks_are_not_mirror_images_of_each_other() -> void:
	for id in TankBackdrop.NEAR_IDS:
		var img := NP.image(id)
		var m := int(NP.segment_of(id, 960)[0])
		var l0 := (NP.W - m) / 2
		var l1 := l0 + m
		var same := 0
		var n := 240
		for i in n:
			var equal := true
			for y in range(0, img.get_height(), 2):
				if not img.get_pixel(l0 - 1 - i, y).is_equal_approx(img.get_pixel(l1 + i, y)):
					equal = false
					break
			if equal:
				same += 1
		assert_lt(
			same, n / 10, "%s: the flank right of the landmark is not its left flank flipped" % id
		)


func test_the_foundry_gantry_has_nothing_hanging_under_it() -> void:
	var img := NP.image("bg_town_near")
	var m := int(NP.segment_of("bg_town_near", 960)[0])
	var l0 := (NP.W - m) / 2
	for y in range(74, 87):
		for x in range(301, 316):
			assert_lt(img.get_pixel(l0 + x, y).a, 0.5, "no cable or bucket at %d,%d" % [x, y])


func test_quarry_ridge_burns_in_more_than_one_place() -> void:
	var fires := 0
	for l in TankBackdrop.strip_lights("bg_quarry_near"):
		if bool(l["fire"]):
			fires += 1
	assert_gte(fires, 2, "the landmark's sawmill and the flank's burning timber shed")


func test_the_depot_flank_has_cold_floodlights() -> void:
	var img := NP.image("bg_depot_near")
	var cold := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).to_rgba32() == TankPalette.COLD_LIGHT.to_rgba32():
				cold += 1
	assert_gt(cold, 4, "floodlight masts with cold lamps")


func test_the_wrapping_pen_draws_across_the_seam() -> void:
	var img := Image.create(32, 4, false, Image.FORMAT_RGBA8)
	var pen := TankBackdrop.Pen.new(img)
	var src := Image.create(6, 2, false, Image.FORMAT_RGBA8)
	src.fill(Color.WHITE)
	pen.blend(src, 29, 0)
	assert_eq(img.get_pixel(30, 0), Color.WHITE)
	assert_eq(img.get_pixel(2, 1), Color.WHITE, "the part past the right edge lands at the left")
	assert_eq(img.get_pixel(4, 0).a, 0.0)
	pen.col(-1, 0, 2, Color.RED)
	assert_eq(img.get_pixel(31, 1), Color.RED)


func test_the_composed_planes_build_quickly() -> void:
	var started := Time.get_ticks_msec()
	for id in TankBackdrop.NEAR_IDS:
		NP.compose(id)
	assert_lt(Time.get_ticks_msec() - started, 3000, "five planes compose in well under 3 s")


func test_smoke_columns_differ_in_height_width_and_lean() -> void:
	var rises := {}
	var leans := {}
	for cam in range(0, 20000, 2000):
		for c in TankBackdrop.smoke_columns(float(cam)):
			rises[int(c["rise"])] = true
			leans[int(c["lean"])] = true
	assert_gt(rises.size(), 4)
	assert_gt(leans.size(), 4)


func test_the_smoke_banks_fill_the_upper_sky() -> void:
	for i in TankBackdrop.BANKS.size():
		var img := TankBackdrop.smoke_bank(i).get_image()
		assert_eq(img.get_width(), TankBackdrop.BANK_W)
		var covered := 0
		for x in range(0, img.get_width(), 8):
			for y in range(0, img.get_height(), 4):
				if img.get_pixel(x, y).a > 0.3:
					covered += 1
					break
		assert_gt(covered, img.get_width() / 8 * 6 / 10, "bank %d spans most columns" % i)


func test_the_far_ridge_rises_above_the_hills() -> void:
	var img := TankBackdrop.far_ridge_texture().get_image()
	var top := TankBackdrop.FAR_RIDGE_BOTTOM_Y - float(img.get_height())
	var highest := img.get_height()
	for x in range(0, img.get_width(), 4):
		for y in img.get_height():
			if img.get_pixel(x, y).a > 0.5:
				highest = mini(highest, y)
				break
	assert_lt(top + float(highest), 140.0, "the land climbs above y 140")


func test_the_foreground_bank_lies_under_the_hud_and_is_dark() -> void:
	# Polish round 5: the bank moved under the HUD band (its rubble along y 296 blanketed the ground
	# line); test_tank_art_world_r5 checks the ground line stays clear.
	var img := TankBackdrop.front_texture().get_image()
	var top := TankBackdrop.FRONT_BOTTOM_Y - float(TankBackdrop.FRONT_H)
	var row := int(TankBackdrop.FRONT_BANK_Y + 10.0 - top)
	var solid := 0
	for x in range(0, img.get_width(), 4):
		var c := img.get_pixel(x, row)
		if c.a > 0.5:
			solid += 1
			assert_lt(c.get_luminance(), 0.12, "near-black")
	assert_gt(solid, img.get_width() / 4 * 9 / 10, "rubble along the bank under the HUD")


func test_the_foreground_fades_over_the_hull_only() -> void:
	var bands := TankBackdrop.front_bands(Vector2(16, 210))
	var prev := -2.0
	for b in bands:
		assert_almost_eq(b.x, prev, 0.01, "contiguous")
		prev = b.y
	assert_gt(prev, float(TankConst.SCREEN_W))
	for b in bands:
		if b.x >= 16.0 and b.y <= 210.0:
			assert_almost_eq(b.z, TankBackdrop.FRONT_FADE, 0.001)
		if b.y <= 4.0 or b.x >= 222.0:
			assert_almost_eq(b.z, 1.0, 0.001)
	assert_eq(TankBackdrop.front_bands(Vector2.ZERO).size(), 1, "no hull: no fade")


func test_the_view_tells_the_backdrop_where_the_hull_is() -> void:
	var v := U.view_of(self, TankFixtures.state(1))
	U.run(v, 3)
	var span := v.backdrop.hull_span
	assert_gt(span.y - span.x, 100.0)
	assert_almost_eq(span.x, v.rig.base_pos.x - 2.0, 0.01)


func test_telegraph_poles_come_in_pairs_with_wires_tied_at_both_ends() -> void:
	var v := U.view_of(self, TankFixtures.state(1))
	var rows: Array[Dictionary] = []
	v._poles(rows, 100.0, float(TankConst.GROUND_Y), 123456)
	var posts := 0
	var wires: Array[PackedVector2Array] = []
	var insulators: Array[Vector2] = []
	for r in rows:
		if r["t"] == "line" and float(r.get("w", 1.0)) == 3.0:
			posts += 1
		elif r["t"] == "polyline":
			wires.append(r["pts"])
		elif r["t"] == "rect" and r["c"] == TankPalette.STEEL_PALE:
			insulators.append((r["r"] as Rect2).position + Vector2(0, 1))
	assert_eq(posts, 2)
	assert_eq(wires.size(), 2)
	for w in wires:
		for end: Vector2 in [w[0], w[w.size() - 1]]:
			var tied := false
			for ins in insulators:
				tied = tied or ins.distance_to(end) < 1.6
			assert_true(tied, "a wire ends on an insulator")


func test_the_depot_yard_has_props_on_the_road() -> void:
	var s := TankFixtures.state(1)
	s.seg.phase_index = 0
	s.seg.seg = TankIds.SEG_DEPOT
	var v := U.view_of(self, s)
	U.run(v, 3)
	var n := 0
	for r in v.props_layer.rows:
		if r["t"] == "rect" or r["t"] == "poly":
			n += 1
	assert_gt(n, 8, "drums, barriers, crates or floodlights in the depot yard")
