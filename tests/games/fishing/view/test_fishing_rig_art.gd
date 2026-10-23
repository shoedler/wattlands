extends GutTest
## FishingRig's mount points against the generated art (assets/fishing/sprites): the canopy
## pattern on the key-red roof, the pennant's mast on the roof, the trim cosmetic on the trim
## stripe only, the bike on the aft deck, the angler on its saddle with the rod in its hands, the
## reel on the bike's front clear of the angler, the rod over the roof, the whole rig inside a
## 4-lane lane, and the hull's PaletteSwap leaving no red on any slot's boat.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")


func _img(id: String) -> Image:
	var img := FishingSprites.texture(id).get_image()
	img.decompress()
	return img


func _opaque(img: Image, p: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, img.get_size()).has_point(p) and img.get_pixelv(p).a > 0.5


func _key(c: Color) -> bool:
	return (
		c.a > 0.5
		and (
			FishingRig.same_colour(c, FishingPalette.KEY_LIGHT)
			or FishingRig.same_colour(c, FishingPalette.KEY_DARK)
		)
	)


func test_canopy_pattern_and_pennant_sit_on_the_roof() -> void:
	var boat := _img("boat")
	var r := FishingRig.CANOPY_RECT
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			assert_true(
				_key(boat.get_pixel(x, y)), "canopy pattern px (%d, %d) on the key roof" % [x, y]
			)
	var foot := Vector2i(int(FishingRig.PENNANT_AT.x), r.position.y)
	assert_true(_key(boat.get_pixelv(foot)), "the mast stands on the roof at %s" % foot)
	assert_lt(FishingRig.PENNANT_AT.y, float(r.position.y), "the mast rises above the roof")


func test_trim_cosmetic_paints_the_trim_stripe_only() -> void:
	var boat := _img("boat")
	var trim := FishingRig.trim_pixels(boat)
	var pts: PackedVector2Array = trim[0]
	assert_gt(pts.size(), 60, "the stripe and its shading")
	var light := 0
	for p in pts:
		assert_gte(p.y, float(FishingRig.TRIM_MIN_Y), "below the roof")
		var c := boat.get_pixelv(Vector2i(p))
		var is_trim := false
		for t in FishingPalette.trim_colours():
			is_trim = is_trim or FishingRig.same_colour(c, t)
		assert_true(is_trim, "trim px %s is a trim colour" % p)
		if FishingRig.same_colour(c, FishingPalette.KEY_LIGHT):
			light += 1
	var stripe := 0
	for y in range(FishingRig.TRIM_MIN_Y, boat.get_height()):
		for x in boat.get_width():
			if FishingRig.same_colour(boat.get_pixel(x, y), FishingPalette.KEY_LIGHT):
				stripe += 1
	assert_eq(light, stripe, "every key-red stripe px is covered")
	for x in range(9, 56):
		assert_true(pts.has(Vector2(x, 20)), "the stripe's row 20 at x %d" % x)


func test_bike_stands_on_the_aft_deck_and_the_angler_on_its_saddle() -> void:
	var bike := _img("rig_bike")
	var angler := _img("rig_angler")
	var boat := _img("boat")
	var feet := 0
	for x in bike.get_width():
		if _opaque(bike, Vector2i(x, bike.get_height() - 1)):
			feet += 1
			var at := Vector2i(FishingRig.BIKE_POS) + Vector2i(x, bike.get_height() - 1)
			assert_eq(at.y, FishingRig.DECK_Y, "bike foot on the gunwale row")
			assert_true(at.x >= 9 and at.x <= 28, "bike foot x %d on the aft deck" % at.x)
			assert_true(_opaque(boat, at), "the deck is there under the foot at %s" % at)
	assert_gt(feet, 0)
	var saddle := Vector2i(FishingRig.BIKE_POS) + Vector2i(5, 3)
	var seat := saddle - Vector2i(FishingRig.ANGLER_POS)
	var on := false
	for dy in range(-2, 1):
		on = on or _opaque(angler, seat + Vector2i(0, dy))
	assert_true(on, "the angler's seat covers the saddle at %s" % saddle)
	assert_true(
		_opaque(angler, Vector2i(FishingRig.HANDS - FishingRig.ANGLER_POS)),
		"the rod butt is in the angler's hands"
	)
	assert_eq(FishingRig.ROD_BASE, FishingRig.HANDS)


func test_reel_sits_on_the_bike_clear_of_the_angler_and_the_chain_links_it() -> void:
	var bike := _img("rig_bike")
	var angler := _img("rig_angler")
	var reel := _img("rig_reel")
	var hub_in_bike := Vector2i(FishingRig.REEL_HUB - FishingRig.BIKE_POS)
	assert_true(_opaque(bike, hub_in_bike), "the reel hub is on the bike at %s" % hub_in_bike)
	var crank_in_bike := Vector2i(FishingRig.CRANK_HUB - FishingRig.BIKE_POS)
	assert_true(_opaque(bike, crank_in_bike), "the crank hub is on the bike at %s" % crank_in_bike)
	var reel_tl := Vector2i(FishingRig.REEL_HUB) - reel.get_size() / 2
	var covered := 0
	for y in reel.get_height():
		for x in reel.get_width():
			if not _opaque(reel, Vector2i(x, y)):
				continue
			if _opaque(angler, reel_tl + Vector2i(x, y) - Vector2i(FishingRig.ANGLER_POS)):
				covered += 1
	assert_eq(covered, 0, "the reel hides none of the angler")
	var gap := FishingRig.CRANK_HUB.distance_to(FishingRig.REEL_HUB)
	assert_gt(
		gap, FishingRig.CRANK_SPROCKET_R + FishingRig.REEL_R + 1.0, "a chain run between them"
	)


func test_rod_runs_from_the_hands_over_the_roof_to_lane_x_88() -> void:
	var rest := FishingRig.rod(FishingRig.ROD_BASE, FishingRig.ROD_TIP, 0.0, Vector2.DOWN, 64)
	assert_eq(FishingRig.ROD_TIP.x + FishingConst.BOAT_X0, float(FishingConst.ROD_TIP_X))
	var r := Rect2(FishingRig.CANOPY_RECT)
	for p in FishingRig.snapped(rest):
		assert_false(r.has_point(p.floor()), "the rod at %s stays off the key-red roof" % p)


func test_the_rig_stays_inside_a_four_lane_lane_clear_of_the_local_border() -> void:
	var v := FX.make_view(autofree(FX.make_game(4, 0)), self)
	autofree(v)
	v.advance(0.05)
	for i in 4:
		var lv := v.lane_view(i)
		var top := FishingRig.boat_pos(lv.sky_h).y
		assert_gte(
			top + FishingRig.ANGLER_POS.y, 3.0, "lane %d: the angler's cap clears the border" % i
		)
		assert_gte(top + FishingRig.PENNANT_AT.y - 2.5, 0.0, "lane %d: the pennant" % i)
		assert_gte(top + FishingRig.ROD_TIP.y, 0.0, "lane %d: the rod tip" % i)


func test_no_slot_shows_red_on_the_hull() -> void:
	var boat := _img("boat")
	var keys := FishingPalette.hull_keys()
	for slot in 4:
		var swaps := FishingPalette.hull_swaps(slot)
		assert_eq(swaps.size(), keys.size())
		var red := 0
		for y in boat.get_height():
			for x in boat.get_width():
				var c := boat.get_pixel(x, y)
				if c.a < 0.5:
					continue
				var shown := PaletteSwap.swap_color(c, keys, swaps)
				for k in keys:
					if FishingRig.same_colour(shown, k):
						red += 1
		assert_eq(red, 0, "slot %d: no key, coral, pink or peach px left on the hull" % slot)
	var coral := 0
	for y in boat.get_height():
		for x in boat.get_width():
			if FishingRig.same_colour(boat.get_pixel(x, y), FishingPalette.CORAL):
				coral += 1
	assert_gt(coral, 0, "the art still has the coral row the swap maps")
