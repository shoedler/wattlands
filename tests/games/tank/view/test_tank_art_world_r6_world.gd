extends GutTest
## Polish round 6, the world: hill fires that never read as a crown or an icon (irregular, each
## different, blurred with the hills), placed per segment so the gun lines differ, one or two on a
## screen; the hills readable; lit cloud undersides in the upper sky; the depot's yard gates,
## workshops and compound wall for the whole roll-out; hedgerows across the fields; wire on stakes
## and flooded craters that read; more foreground wreckage; no scenery halo blooming over the
## hull; wrecks receding behind a live enemy; flipped sprites drawn where they stand.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const B := preload("res://src/games/tank/view/tank_backdrop.gd")
const NP := TankBackdrop.NearPlane


func _rows(layer: TankRowLayer, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in layer.rows:
		if str(r.get("t", "")) == type:
			out.append(r)
	return out


## The flame's height per column of a raw hill fire picture (rows of fire colour above the bed).
func _profile(img: Image) -> Array[int]:
	var out: Array[int] = []
	for x in img.get_width():
		var n := 0
		for y in B.FIRE_BED_Y:
			var c := img.get_pixel(x, y)
			if c.a > 0.3 and c.r > 0.6 and c.r > c.b + 0.3:
				n += 1
		out.append(n)
	return out


func test_hill_fires_are_irregular_lopsided_and_each_different() -> void:
	var seen := {}
	for v in B.FIRE_VARIANTS:
		var p := _profile(B.hill_fire_image(B.fire_shape(v), 0, false))
		var lo := p.size()
		var hi := -1
		for x in p.size():
			if p[x] > 0:
				lo = mini(lo, x)
				hi = maxi(hi, x)
		assert_gt(hi, lo, "variant %d burns" % v)
		# Lopsided: the mass is not mirror-symmetric about its own middle.
		var diff := 0
		for i in range(lo, hi + 1):
			diff += absi(p[i] - p[hi - (i - lo)])
		assert_gt(diff, (hi - lo) / 2, "variant %d is not symmetric" % v)
		seen[str(p)] = true
	assert_eq(seen.size(), B.FIRE_VARIANTS, "every variant has its own outline")


func test_hill_fires_never_stand_as_evenly_spaced_prongs() -> void:
	for v in B.FIRE_VARIANTS:
		var p := _profile(B.hill_fire_image(B.fire_shape(v), 1, false))
		# Peaks: columns taller than both neighbours by 2 rows or more.
		var peaks: Array[int] = []
		for x in range(1, p.size() - 1):
			if p[x] >= p[x - 1] + 2 and p[x] >= p[x + 1] + 2:
				peaks.append(x)
		var even := peaks.size() == 3 and peaks[1] - peaks[0] == peaks[2] - peaks[1]
		assert_false(even, "variant %d: three evenly spaced prongs read as a crown" % v)


func test_hill_fires_are_blurred_like_the_hills() -> void:
	var tex := B.hill_fire_textures()
	assert_eq(tex.size(), B.FIRE_VARIANTS * (B.FIRE_FRAMES + 1))
	assert_eq(int(B.FIRE_BLUR["down"]), int(TankBlur.PRESETS["hills"]["down"]), "the hills' blur")
	for t in tex:
		var img := t.get_image()
		var step := 0.0
		for y in img.get_height():
			for x in range(1, img.get_width()):
				step = maxf(step, absf(img.get_pixel(x, y).a - img.get_pixel(x - 1, y).a))
		assert_lt(step, 0.4, "no pixel-sharp edge on a blurred plane")


func test_smouldering_sites_are_a_bed_not_two_dots() -> void:
	for v in B.FIRE_VARIANTS:
		var img := B.hill_fire_image(B.fire_shape(v), 0, true)
		var row := B.FIRE_BED_Y
		var runs := 0
		var inside := false
		for x in img.get_width():
			var c := img.get_pixel(x, row)
			var on := c.a > 0.5 and c.r > 0.4 and c.r > c.b + 0.2
			if on and not inside:
				runs += 1
			inside = on
		assert_eq(runs, 1, "variant %d smoulders in one unbroken bed" % v)


func test_a_screen_shows_at_most_two_burning_hill_fires() -> void:
	var total := 0
	var frames := 0
	for salt in [0, 17, 4242, 9001, 31337]:
		for cam in range(0, 40000, 730):
			var n := 0
			for c in B.smoke_columns(float(cam), 640.0, salt, float(salt % 1920)):
				var p: Vector2 = c["pos"]
				if bool(c["burning"]) and p.x >= 0.0 and p.x < 640.0:
					n += 1
			assert_lte(n, 2, "cam %d salt %d" % [cam, salt])
			total += n
			frames += 1
	var mean := float(total) / float(frames)
	assert_between(mean, 0.6, 2.0, "about one fire on a screen")


func test_each_segment_puts_its_fires_elsewhere() -> void:
	var b := B.new()
	autofree(b)
	var layouts := {}
	for idx in range(0, 11):
		b.set_segment(idx)
		b.set_world_x(-16.0)
		var xs: Array[int] = []
		for c in b.columns():
			if bool(c["burning"]):
				xs.append(int(c["pos"].x))
		layouts[str(xs)] = true
	assert_gt(layouts.size(), 8, "the gun lines (hull x 0 every time) differ")
	b.set_segment(3)
	var off := b.hills.offset_x
	b.set_segment(3)
	assert_eq(b.hills.offset_x, off, "a segment keeps its layout")


func test_columns_still_rise_from_fire_sites_with_a_segment_layout() -> void:
	var crest := B.hill_crest()
	var w := crest.size()
	var top := B.HILLS_BOTTOM_Y - float(TankBlur.plane("bg_hills_far", "hills").get_height())
	var sites := B.hill_fire_sites()
	for cam in range(0, 20000, 1300):
		var off := 517.0
		var scroll := roundf(float(cam) * B.HILLS_FACTOR + off)
		for c in B.smoke_columns(float(cam), 640.0, 77, off):
			var p: Vector2 = c["pos"]
			var tx := posmod(roundi(p.x + scroll), w)
			var site := -1
			for s in sites:
				if tx == s or tx == w - 1 - s:
					site = s
			assert_ne(site, -1, "on a site")
			if site >= 0:
				assert_between(p.y, top + float(crest[site]), top + float(crest[site]) + 18.0)


func test_the_hills_read_with_their_rows_of_trees() -> void:
	var p: Dictionary = TankBlur.PRESETS["hills"]
	assert_lte(float(p["darken"]), 0.35, "lifted from the cloud base")
	assert_eq(int(p.get("box_r", 0)), 0, "no extra box pass: the poplar rows survive")
	var img := TankBlur.plane("bg_hills_far", "hills").get_image()
	var lums: Array[float] = []
	for x in range(0, img.get_width(), 3):
		for y in range(img.get_height() / 4, img.get_height() * 3 / 4, 3):
			var c := img.get_pixel(x, y)
			if c.a > 0.8:
				lums.append(c.get_luminance())
	lums.sort()
	var spread := lums[lums.size() * 9 / 10] - lums[lums.size() / 10]
	assert_gt(spread, 0.04, "ridges, woods and fields stand apart in tone")


func test_distant_fires_light_the_cloud_undersides() -> void:
	var v := U.view_of(self, TankFixtures.state(1))
	U.run(v, 2)
	var high := 0
	for i in v.backdrop.cloud_glow.count:
		if v.backdrop.cloud_glow._pos[i].y < 150.0:
			high += 1
	assert_gt(high, 1, "warm glows low in the bank, over the upper sky")


func test_the_depot_has_yard_gates_and_workshops_all_the_way() -> void:
	var s := TankFixtures.state(1)
	s.seg.phase_index = 0
	s.seg.seg = TankIds.SEG_DEPOT
	var v := U.view_of(self, s)
	var kinds := {}
	for step in range(1, 60):
		s.hull.x_px = float(step) * 337.0
		s.tick += 1
		U.run(v, 2)
		var right := false
		for r in v.props_layer.rows:
			var of := str(r.get("of", ""))
			if of == "compound_wall":
				kinds[of] = true
			if of != "yard_gate" and of != "workshop":
				continue
			kinds[of] = true
			var x: float = (r["pos"] as Vector2).x if r.has("pos") else (r["r"] as Rect2).position.x
			if x > 120.0 and x < 600.0:
				right = true
		assert_true(right, "a yard structure in view at hull x %d" % int(s.hull.x_px))
	assert_eq(kinds.size(), 3, "gates, workshops and the compound wall")


func test_hedgerows_cross_the_fields_on_the_flanks() -> void:
	var img := NP.image("bg_fields_near")
	var src := NP.source("bg_fields_near")
	var hz := NP.horizon(src, NP.segment_of("bg_fields_near", src.get_width()))
	# The nearest hedgerow row (field_bounds), near-black K1 against the field.
	var row := hz + 6 + (img.get_height() - hz) / 2
	var dark := 0
	var n := 0
	for x in range(0, 300):
		n += 1
		var c := img.get_pixel(x, row)
		if c.a > 0.9 and c.to_rgba32() == NP.K1.to_rgba32():
			dark += 1
	assert_gt(dark, n / 3, "a hedgerow along the near field boundary")
	assert_lt(dark, n, "broken by field gates")


func test_flooded_craters_hold_the_night_sky_without_a_lamp() -> void:
	var v := U.view_of(self, TankFixtures.state(1))
	var rows: Array[Dictionary] = []
	v.lights.begin()
	var before := v.lights.count
	v._flooded_crater(rows, 300.0, float(TankConst.GROUND_Y))
	assert_eq(v.lights.count, before + 1, "a cold sheen of the sky")


func test_wire_on_stakes_is_lighter_than_the_mud_and_barbed() -> void:
	var v := U.view_of(self, TankFixtures.state(1))
	var rows: Array[Dictionary] = []
	v._fence(rows, 200.0, float(TankConst.GROUND_Y), 12345)
	var strands := 0
	var barbs := 0
	for r in rows:
		if r["t"] == "polyline":
			strands += 1
			assert_gt((r["c"] as Color).get_luminance(), TankPalette.MUD.get_luminance())
		if r["t"] == "rect" and r["c"] == TankPalette.STEEL_PALE:
			barbs += 1
	assert_eq(strands, 2)
	assert_gt(barbs, 3, "barbs glint along the wire")


func test_more_wreckage_breaks_the_lower_frame_above_the_hud() -> void:
	var img := B.front_texture().get_image()
	var top := B.FRONT_BOTTOM_Y - float(B.FRONT_H)
	var row := int(290.0 - top)
	var runs := 0
	var inside := false
	for x in img.get_width():
		var on := img.get_pixel(x, row).a > 0.3
		if on and not inside:
			runs += 1
		inside = on
	assert_gte(runs, 5, "six wrecks rise above the HUD band")


func test_scenery_halos_behind_the_hull_stay_small() -> void:
	var s := TankFixtures.state(2)
	var v := U.view_of(self, s)
	var hull := Rect2(
		v.rig.base_pos + Vector2(-24, -84), Vector2(v.rig.hull_w + 48, v.rig.hull_h + 94)
	)
	var checked := 0
	for step in 40:
		s.hull.x_px = float(step) * 53.0
		s.tick += 1
		U.run(v, 1)
		var sl := v.backdrop.scenery_lights
		for i in sl.count:
			if hull.has_point(sl._pos[i]):
				checked += 1
				assert_lte(sl._radius[i], 12.0, "no bloom over the deck")
	assert_gt(checked, 0, "some scenery light passed behind the hull")


func test_a_wreck_recedes_while_a_live_enemy_stands_over_it() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var e := s.enemy(11)
	v._add_wreck({"x": e.x_px, "w": 104, "h": 52, "code": e.code, "side": 1, "id": 999})
	U.run(v, 40)
	var veiled: Color = Color.WHITE
	for r in _rows(v.props_layer, "sprite"):
		if r["id"] == TankSprites.enemy_id(TankIds.enemy_of(e.code)):
			veiled = r["tint"]
	assert_lt(veiled.a, 0.6, "half see-through behind the live one")
	s.enemies.clear()
	v._seen_enemies.clear()
	U.run(v, 40)
	var clear: Color = Color.WHITE
	for r in _rows(v.props_layer, "sprite"):
		if r["id"] == TankSprites.enemy_id(TankIds.enemy_of(e.code)):
			clear = r["tint"]
	assert_almost_eq(clear.a, 1.0, 0.01, "solid again on its own")
