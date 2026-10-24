extends GutTest
## Polish round 5, the world: the foreground bank under the HUD band with the ground line clear,
## the hill fires under their smoke columns (no searchlight bars), the road with its puddles, the
## foundry and depot without gallows-like crossbars, flames and windows that never read as faces or
## fires, and the enemies' fire glows as hatch slits instead of round orbs.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const NP := TankBackdrop.NearPlane


func test_the_ground_line_is_clear_of_the_foreground_bank() -> void:
	var img := TankBackdrop.front_texture().get_image()
	var top := TankBackdrop.FRONT_BOTTOM_Y - float(TankBackdrop.FRONT_H)
	for y: float in [float(TankConst.GROUND_Y), float(TankConst.GROUND_Y) - 12.0]:
		var solid := 0
		var n := 0
		for x in range(0, img.get_width(), 2):
			n += 1
			if img.get_pixel(x, int(y - top)).a > 0.5:
				solid += 1
		assert_lt(solid, n / 8, "only a few wrecks rise through y %d" % int(y))
	assert_gte(TankBackdrop.FRONT_BANK_Y, 300.0, "the bank's top lies under the HUD band")


func test_a_few_wrecks_still_break_the_lower_frame() -> void:
	var img := TankBackdrop.front_texture().get_image()
	var top := TankBackdrop.FRONT_BOTTOM_Y - float(TankBackdrop.FRONT_H)
	var row := int(270.0 - top)
	var runs := 0
	var inside := false
	for x in img.get_width():
		var on := img.get_pixel(x, row).a > 0.3
		if on and not inside:
			runs += 1
		inside = on
	assert_between(runs, 2, 12, "sparse wreckage rises above y 270")


func test_no_searchlight_bars_and_the_fires_stand_in_front_of_the_haze() -> void:
	var v := U.view_of(self, TankFixtures.state(1))
	var b := v.backdrop
	assert_null(b.get_node_or_null("Searchlights"), "no hard-edged searchlight beams")
	var haze := b.get_node("HazeBand").get_index()
	var smoke := b.get_node("SkySmoke").get_index()
	assert_gt(smoke, haze, "the fires and their smoke are drawn over the haze")
	assert_gt(b.horizon_lights.get_index(), smoke, "the fires' halos over their smoke")
	assert_lt(b.horizon_lights.get_index(), b.near.get_index(), "behind the near plane")
	assert_gt(b.get_node("HorizonGlow").get_index(), b.cloud_glow.get_index())
	assert_lt(b.get_node("HorizonGlow").get_index(), b.hills.get_index(), "glow behind the hills")


func test_hill_fires_burn_on_distinct_slopes_of_each_stretch() -> void:
	var sites := TankBackdrop.hill_fire_sites()
	var w := TankBackdrop.hill_crest().size()
	assert_eq(sites.size(), TankBackdrop.HILL_FIRES)
	var span := w / TankBackdrop.HILL_FIRES
	for k in sites.size():
		assert_between(sites[k], k * span + 40, (k + 1) * span - 40, "site %d in its stretch" % k)


func test_every_smoke_column_rises_from_a_fire_on_the_hills() -> void:
	var crest := TankBackdrop.hill_crest()
	var w := crest.size()
	var top := (
		TankBackdrop.HILLS_BOTTOM_Y - float(TankBlur.plane("bg_hills_far", "hills").get_height())
	)
	var sites := TankBackdrop.hill_fire_sites()
	var seen := 0
	for cam in range(0, 30000, 1700):
		var scroll := roundf(float(cam) * TankBackdrop.HILLS_FACTOR)
		for c in TankBackdrop.smoke_columns(float(cam)):
			var p: Vector2 = c["pos"]
			var tx := posmod(roundi(p.x + scroll), w)
			var site := -1
			for s in sites:
				if tx == s or tx == w - 1 - s:
					site = s
			assert_ne(site, -1, "column at x %.0f stands on a fire site" % p.x)
			if site >= 0:
				var crest_y := top + float(crest[site])
				assert_between(p.y, crest_y, crest_y + 18.0, "on the hills' slope")
			seen += 1
	assert_gt(seen, 20)


func test_the_road_has_a_ragged_verge_ruts_and_puddles() -> void:
	assert_eq(TankBackdrop.road_style("bg_village_near"), "cobbles")
	assert_eq(TankBackdrop.road_style("bg_depot_near"), "slabs")
	assert_eq(TankBackdrop.road_style("bg_quarry_near"), "mud")
	for style: String in ["mud", "cobbles", "slabs"]:
		var img := TankBackdrop.road_texture(style).get_image()
		assert_eq(img.get_size(), Vector2i(TankBackdrop.ROAD_W, TankBackdrop.ROAD_H), style)
		var row0 := 0
		var row6 := 0
		for x in img.get_width():
			if img.get_pixel(x, 0).a > 0.5:
				row0 += 1
			if img.get_pixel(x, 6).a > 0.5:
				row6 += 1
		assert_between(row0, 1, img.get_width() * 9 / 10, "%s: no straight top edge" % style)
		assert_eq(row6, img.get_width(), "%s: solid road below the verge" % style)
		var road_y := TankBackdrop.ROAD_TOP_Y
		assert_between(float(TankConst.GROUND_Y), road_y, road_y + float(img.get_height()))
		var puddles := 0
		for cam in range(0, 6000, 500):
			for p in TankBackdrop.road_puddles(style, float(cam)):
				assert_lt(p.x, p.y)
				assert_between(p.z, road_y, road_y + float(img.get_height()))
				puddles += 1
		assert_gt(puddles, 6, "%s: water on the road" % style)


func test_the_road_draws_under_the_tank_s_plane() -> void:
	var v := U.view_of(self, TankFixtures.state(1))
	var b := v.backdrop
	assert_gt(b.road.get_index(), b.ground.get_index())
	assert_eq(b.road.get_parent(), b, "on the backdrop, under the world")


func test_puddles_and_flooded_craters_catch_the_lights() -> void:
	var v := U.view_of(self, TankFixtures.state(1))
	var rows: Array[Dictionary] = []
	var ground := float(TankConst.GROUND_Y)
	v.lights.begin()
	v.lights.add(Vector2(120, ground - 30.0), 30.0, TankPalette.AMBER, 0.9)
	var before := v.lights.count
	v._flooded_crater(rows, 100.0, ground)
	var water := 0
	for r in rows:
		if r["t"] == "poly" and r["c"] == Color("#121519"):
			water += 1
	assert_eq(water, 1, "a sheet of water in the crater")
	assert_gt(v.lights.count, before, "the lamp's reflection glows on it")


func test_the_foundry_has_no_crossbar_on_legs() -> void:
	var img := NP.image("bg_town_near")
	var m := int(NP.segment_of("bg_town_near", 960)[0])
	var l0 := (NP.W - m) / 2
	for y in range(55, 69):
		var run := 0
		var longest := 0
		for x in range(l0 + 272, l0 + 350):
			run = run + 1 if img.get_pixel(x, y).a > 0.5 else 0
			longest = maxi(longest, run)
		assert_lte(longest, 8, "row %d: only chimney stacks where the gantry was" % y)


func test_the_depot_builds_no_gantry_crane_and_parks_tanks_facing_right() -> void:
	var img := Image.create(200, 60, false, Image.FORMAT_RGBA8)
	var pen := TankBackdrop.Pen.new(img)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(NP._scene(pen, rng, "crane", 10, 50, 180), 0, "no crane scene")
	var used := NP.parked_tanks(pen, rng, 10, 50)
	assert_gt(used, 50)
	# Each turret's barrel leaves its right side: the row of a barrel has turret pixels to its left.
	var barrels := 0
	for y in range(30, 50):
		for x in range(12, 10 + used):
			if img.get_pixel(x, y) == NP.K2 and img.get_pixel(x - 1, y) == NP.K3:
				barrels += 1
	assert_gt(barrels, 0, "barrels point right")


func test_flames_have_no_dark_spots_and_windows_never_read_as_fires() -> void:
	var lights := TankPlaceholderArt.light_colours()
	for sd in 20:
		var img := Image.create(40, 20, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		NP.fire_in_roof(TankBackdrop.Pen.new(img), rng, 8, 14, 18)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					assert_true(
						lights.has(c.to_rgba32()), "flame px %d,%d is a fire colour" % [x, y]
					)
	var fire_key := TankPalette.FIRE.to_rgba32()
	var amber_key := TankPalette.AMBER.to_rgba32()
	for sd in 30:
		var img := Image.create(64, 10, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		NP._window_groups(TankBackdrop.Pen.new(img), rng, 2, 3, 60)
		for cell in 4:
			var hot := 0
			for y in img.get_height():
				for x in range(cell * 16, cell * 16 + 16):
					var k := img.get_pixel(x, y).to_rgba32()
					if k == fire_key or k == amber_key:
						hot += 1
			assert_lt(hot, 6, "a window cell is never classed as a burning building")


func test_a_burning_enemy_glows_in_a_hatch_slit_not_round_orbs() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var e := s.enemy(11)
	e.hp = v.enemy_max_hp(s, "medium") * 0.1
	U.run(v, 3)
	var slits := 0
	for r in v.enemies_layer.rows:
		if r["t"] == "rect" and r["c"] == TankPalette.AMBER and (r["r"] as Rect2).size.y == 1.0:
			slits += 1
	assert_eq(slits, 1, "one amber slit on the burning hull")


func test_the_hills_stand_dark_against_the_horizon() -> void:
	var p: Dictionary = TankBlur.PRESETS["hills"]
	assert_gt(float(p["darken"]), 0.3, "the hills are darkened toward a silhouette")
	assert_lt(float(p["haze"]), 0.3)
