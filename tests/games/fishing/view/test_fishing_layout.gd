extends GutTest
## Lane geometry (brief 3.2): rows, lane placement, the fish's and the hints' x mapping, and the
## right third left open.

const FISH_SIZES := {"mackerel": 24, "mahi": 40, "tuna": 44, "marlin": 64}
const D_MAX := {"mackerel": 40.0, "mahi": 80.0, "tuna": 120.0, "marlin": 200.0}


func test_rows_sum_to_the_lane_height_for_every_lane_count() -> void:
	for n in range(1, 5):
		var h := FishingLayout.lane_h(n)
		assert_eq(h, 336 / n, "lane height at %d lanes" % n)
		var r := FishingLayout.rows(h)
		assert_eq(
			int(r["sky"]) + int(r["surface"]) + int(r["water"]) + int(r["reef"]),
			h,
			"rows at %d" % n
		)
		assert_gte(int(r["sky"]), 30)
		assert_gte(int(r["reef"]), 12)
		assert_eq(int(r["surface"]), 4)


func test_four_lanes_have_sky_30_surface_4_water_38_reef_12() -> void:
	assert_eq(FishingLayout.rows(84), {"sky": 30, "surface": 4, "water": 38, "reef": 12})


func test_lanes_tile_the_play_area_in_slot_order() -> void:
	for n in range(1, 5):
		assert_eq(FishingLayout.lane_y(0, n), 24)
		var last := FishingLayout.lane_rect(n - 1, n)
		assert_eq(last.end.y, 360, "%d lanes end at the bottom" % n)
		for i in n - 1:
			assert_eq(FishingLayout.lane_rect(i, n).end.y, FishingLayout.lane_y(i + 1, n))


func test_the_whole_fish_stays_left_of_x_420() -> void:
	for sp: String in FISH_SIZES:
		var w: int = FISH_SIZES[sp]
		for k in 13:
			var d := float(D_MAX[sp]) * float(k) / 8.0
			var x := FishingLayout.fish_mouth_x(d, D_MAX[sp], w)
			assert_lte(x + w, 420, "%s at %.0f m" % [sp, d])
			assert_gte(x, 96)


func test_the_80_m_hint_sits_at_x_396() -> void:
	assert_eq(FishingLayout.hint_x(80.0), 396)
	assert_eq(FishingLayout.hint_x(0.0), 96)
	assert_eq(FishingLayout.hint_x(40.0), 246)
	assert_eq(FishingLayout.hint_x(200.0), 396, "clamped at 80 m")


func test_hints_and_seams_stay_out_of_the_hud_zone() -> void:
	for steps in range(1, 5):
		var x := FishingLayout.hint_x(80.0)
		assert_lt(x + FishingLaneView.SEAM_PX_PER_STEP * steps / 2, FishingConst.HUD_X)
	assert_lt(FishingLayout.hint_x(80.0) + 16, FishingConst.HUD_X, "a bait ball at 80 m")


func test_fish_depth_keeps_the_sprite_inside_the_water_rows() -> void:
	for n in range(1, 5):
		for i in n:
			for z: float in [0.0, 0.5, 1.0]:
				var y := FishingLayout.fish_y(z, i, n, 22)
				assert_gte(y, FishingLayout.water_y(i, n))
				assert_lte(y + 22, FishingLayout.water_y(i, n) + FishingLayout.water_h(n))


func test_strength_steps_run_one_to_four() -> void:
	assert_eq(FishingLaneView.strength_steps(0.0), 1)
	assert_eq(FishingLaneView.strength_steps(0.25), 1)
	assert_eq(FishingLaneView.strength_steps(0.26), 2)
	assert_eq(FishingLaneView.strength_steps(0.7), 3)
	assert_eq(FishingLaneView.strength_steps(1.0), 4)


## Toasts sit below the deck bar and left of the HUD zone: clear of every local HUD rect (the
## timeline, power, meters and cadence) for every lane count and local slot.
func test_toasts_stay_clear_of_the_local_hud_zone() -> void:
	var toast := FishingLayout.toast_rect()
	assert_gte(toast.position.y, FishingConst.DECK_H)
	assert_lte(toast.end.x, FishingConst.HUD_X, "toasts end left of the HUD zone")
	assert_gte(toast.size.x, 400, "room for the longest toast")
	for n in range(1, 5):
		for local in n:
			var r := FishingLayout.local_hud(local, n)
			for k: String in r:
				var w: Rect2i = r[k]
				if w.size == Vector2i.ZERO:
					continue
				assert_false(
					toast.intersects(w), "toast %s overlaps %s %s (n %d)" % [toast, k, w, n]
				)
			for i in n:
				assert_false(
					toast.intersects(FishingLayout.hud_zone(i, n)), "zone %d of %d" % [i, n]
				)
