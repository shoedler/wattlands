extends GutTest
## The v3 art fix round (2026-10-28): the main gun's smoke and dust latched where the shot left the
## muzzle and scrolled with the world, their tails thinning in alpha instead of stipple; the road's
## sparse 2 x 1 pebbles; the turret searchlight's hold and fade with a standby glow; the
## searchlights' pools kept on screen; the heavier bow rounds; the depot's base ahead of the tank;
## a gun line's base clear of its dug-ins; back-lane enemies standing level; the breech window
## filled; the aft idler inside the rear plate; the hull's silhouette without stray pixels.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")

# --- the blast ------------------------------------------------------------------------------------


func test_the_blast_smoke_and_dust_latch_where_the_shot_left_and_scroll_with_the_world() -> void:
	var f := TankFiring.new()
	f.fire_main(Vector2(500, 300), 0.1)
	assert_eq(f.latched(), Vector2(500, 300), "at the muzzle on the shot")
	f.step(0.1, 12.0)
	f.step(0.1, 12.0)
	assert_eq(f.latched(), Vector2(476, 300), "carried back with the world's scroll")
	assert_almost_eq(f.blast_ang, 0.1, 1e-6, "at the bore's angle of the shot")
	for _i in 30:
		f.step(0.1, 12.0)
	var gone := f.latched()
	f.step(0.1, 50.0)
	assert_eq(f.latched(), gone, "nothing scrolls once the blast is over")
	f.fire_main(Vector2(10, 20), -0.2)
	assert_eq(f.latched(), Vector2(10, 20), "a new shot latches afresh")


func test_the_view_latches_the_blast_at_the_muzzle_and_moves_it_with_the_road() -> void:
	var s := U.fixture("state", 4)
	var v := U.view_of(self, s)
	var m := v.muzzle()
	v.fire("main")
	assert_almost_eq(v.firing.blast_at.distance_to(m), 0.0, 0.01, "latched at the muzzle")
	assert_almost_eq(v.firing.blast_ang, v.barrel_vector().angle(), 1e-4, "along the bore")
	var x0 := v.firing.latched().x
	for _i in 20:
		s.hull.x_px += 4.0
		U.run(v, 1)
	assert_lt(v.firing.latched().x, x0 - 40.0, "the tank drives on, the smoke stays behind")
	assert_almost_eq(
		v.firing.latched().x, x0 - v.firing.blast_shift, 0.01, "by the world's scroll exactly"
	)


func test_only_the_flash_and_the_fire_ball_ride_on_the_muzzle() -> void:
	var rig := TankRig.shared()
	for part in TankRig.BLAST_PARTS:
		assert_true(rig.blast.has(part), "the %s sheet" % part)
	var air: Dictionary = rig.blast["air"]
	assert_lte(int(air["frames"]) / rig.blast_fps, 0.27, "the muzzle's part is over by 0.27 s")
	var smoke: Dictionary = rig.blast["smoke"]
	assert_gte(int(smoke["frames"]) / rig.blast_fps, 1.9, "the smoke runs about 2 s")


func test_the_smoke_and_the_dust_thin_out_without_single_pixel_stipple() -> void:
	var rig := TankRig.shared()
	for part: String in ["smoke", "ground"]:
		var b: Dictionary = rig.blast[part]
		var img := (b["tex"] as Texture2D).get_image()
		img.decompress()
		var sz: Vector2 = b["size"]
		var n := int(b["frames"])
		var soft := 0
		var lone := 0
		var opaque := 0
		for f in range(n - 15, n):
			var o := Vector2i(int(sz.x) * (f % rig.blast_cols), int(sz.y) * (f / rig.blast_cols))
			for y in int(sz.y):
				for x in int(sz.x):
					var a := img.get_pixel(o.x + x, o.y + y).a
					if a <= 0.0:
						continue
					opaque += 1
					if a < 0.99:
						soft += 1
					var nb := 0
					for d: Vector2i in [
						Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
					]:
						var q := Vector2i(x, y) + d
						if q.x >= 0 and q.y >= 0 and q.x < int(sz.x) and q.y < int(sz.y):
							if img.get_pixel(o.x + q.x, o.y + q.y).a > 0.0:
								nb += 1
					if nb == 0:
						lone += 1
		assert_gt(soft, opaque / 2, "%s: the tail fades in alpha" % part)
		assert_lt(float(lone), float(opaque) * 0.01, "%s: no single-pixel stipple" % part)


# --- the road -------------------------------------------------------------------------------------


func test_the_road_has_sparse_low_pebbles_two_pixels_wide_over_a_shadow() -> void:
	var img := TankForest.road_image()
	var peb := 0
	var px := 0
	for y in range(TankForest.ROAD_TOP, TankForest.ROAD_H):
		for x in TankForest.ROAD_W:
			px += 1
			if TankForest.pebble_at(x, y) or TankForest.pebble_at(x - 1, y):
				peb += 1
			if TankForest.pebble_at(x, y):
				assert_false(TankForest.pebble_at(x + 1, y), "pebbles never touch along a row")
	var share := float(peb) / float(px)
	assert_between(share, 0.012, 0.03, "about 2 % of the road is pebble")
	var base := TankForest.ROAD_BASE.get_luminance()
	var peb_l := TankForest.PEBBLE.get_luminance()
	assert_lt(peb_l - base, 0.1, "low contrast: no glitter under the headlight")
	assert_eq(img.get_width(), TankForest.ROAD_W, "one tile")


# --- the searchlights -----------------------------------------------------------------------------


func test_the_turret_searchlight_holds_two_seconds_and_fades_in_and_out() -> void:
	var dt := 0.05
	var lh := Vector2(1.0, TankView.SEARCH_HOLD_S)
	var t := 0.0
	while t < 1.9:
		lh = TankView.search_fade(lh.x, lh.y, false, dt)
		t += dt
	assert_eq(lh.x, 1.0, "still on 1.9 s after its rider drops out of band")
	while t < 2.2 - 1e-6:
		lh = TankView.search_fade(lh.x, lh.y, false, dt)
		t += dt
	assert_almost_eq(lh.x, 0.5, 0.06, "half way through its 0.4 s fade")
	while t < 2.45:
		lh = TankView.search_fade(lh.x, lh.y, false, dt)
		t += dt
	assert_eq(lh.x, 0.0, "off after the hold and the fade")
	lh = TankView.search_fade(lh.x, lh.y, true, 0.2)
	assert_almost_eq(lh.x, 0.5, 1e-4, "back on: it fades up over 0.4 s")
	lh = TankView.search_fade(lh.x, lh.y, true, 0.2)
	assert_eq(lh.x, 1.0)
	for i in 40:
		lh = TankView.search_fade(lh.x, lh.y, (i / 10) % 2 == 0, dt)
		assert_eq(lh.x, 1.0, "a rider wobbling at the band's edge never flickers it")


func test_the_view_holds_the_searchlight_while_the_rider_stays_and_fades_it_without_one() -> void:
	var s := U.fixture("state", 4)
	var arc := s.station(TankIds.ENGINE_ARC) as TankArcState
	arc.lit = true
	var v := U.view_of(self, s)
	assert_eq(v.search_level, 1.0, "on at the start")
	assert_true(v.body.search_lit, "its lens lit")
	arc.lit = false
	U.run(v, 60)
	assert_eq(v.search_level, 1.0, "held a second after the arc drops out")
	U.run(v, 84)
	assert_eq(v.search_level, 0.0, "faded out after the hold")
	assert_false(v.body.search_lit, "the lens dark")
	arc.lit = true
	U.run(v, 30)
	assert_eq(v.search_level, 1.0, "back on")
	var st := s.station(TankIds.ENGINE_ARC)
	st.slot = -1
	st.peer = 0
	U.run(v, 12)
	assert_lt(v.search_level, 0.5, "an empty seat fades it at once, no hold")


func test_the_searchlights_pools_lie_on_the_road_on_screen() -> void:
	var s := U.fixture("state", 4)
	(s.station(TankIds.ENGINE_ARC) as TankArcState).lit = true
	var v := U.view_of(self, s)
	var n := 0
	for b in TankLightDraw.beams(v, s):
		if bool(b["head"]):
			continue
		n += 1
		var pool := TankLightDraw.beam_pool(v, b)
		assert_false(pool.is_empty(), "every searchlight leaves a pool")
		var at: Vector2 = pool["at"]
		assert_between(
			at.x, TankLightDraw.POOL_EDGE, v.canvas.x - TankLightDraw.POOL_EDGE, "on screen"
		)
		assert_almost_eq(at.y, v.ground_y(at.x) + 4.0, 0.01, "on the road")
		var p: Vector2 = b["p"]
		var lo := absf(angle_difference((at - p).angle(), float(b["ang"])))
		assert_lt(lo, deg_to_rad(40.0), "toward the beam's side of the tank")
	assert_eq(n, 2, "the turret and the rear searchlight")


# --- the bow guns ---------------------------------------------------------------------------------


func test_the_bow_rounds_are_heavier_tracers_with_a_glow() -> void:
	assert_between(TankFiring.TRACER_LEN, 10, 12, "10-12 px tracers")
	assert_eq(TankFiring.TRACER_W, 2, "2 px wide")
	assert_almost_eq(TankFiring.FLASH_BOW_S, 0.08, 0.005, "a muzzle flash of about 0.08 s")
	var v := U.view_of(self, U.fixture("state", 4))
	v.fire("bow", 0)
	var tr := v.firing.tracers(v)
	assert_eq(tr.size(), 1, "one round, one tracer")
	assert_gt(float(tr[0]["flash"]), 0.0, "its muzzle flash burns")
	U.run(v, 6)
	assert_eq(float(v.firing.tracers(v)[0]["flash"]), 0.0, "and is out after 0.1 s")


# --- the bases ------------------------------------------------------------------------------------


func test_a_stages_base_stands_whole_in_the_far_panel_never_cut_by_the_seam() -> void:
	for seg: String in [TankIds.SEG_DEPOT, TankIds.SEG_GUN_LINE]:
		for size: Vector2 in [Vector2(960, 540), Vector2(852, 480)]:
			var s := U.fixture("state", 3)
			s.seg.seg = seg
			s.hull.x_px = 0.0
			var v := U.view_of(self, s, Wl.SOLO, 1, size)
			assert_eq(TankForest.bases(v, s).size(), 0, "%s: not on the near stage" % seg)
			var x := TankForest.far_base(v, s)
			assert_gte(x, 0.0, "%s at %s" % [seg, size])
			assert_lte(x + TankForest.BASE_W, v.far.far_w, "%s at %s: its gate too" % [seg, size])


func test_a_stages_base_slides_away_as_the_hull_drives_off() -> void:
	var s := U.fixture("state", 3)
	s.seg.seg = TankIds.SEG_DEPOT
	s.hull.x_px = 0.0
	var v := U.view_of(self, s)
	var x0 := TankForest.far_base(v, s)
	s.hull.x_px = 200.0
	U.run(v, 12)
	assert_lt(TankForest.far_base(v, s), x0, "at the far parallax")
	s.hull.x_px = 4000.0
	U.run(v, 12)
	assert_true(is_nan(TankForest.far_base(v, s)), "gone when it is out of the panel")
	s.seg.seg = TankIds.SEG_ADVANCE
	assert_true(is_nan(TankForest.far_base(v, s)), "none on the road between")


# --- enemies --------------------------------------------------------------------------------------


func test_both_near_lanes_follow_the_road_under_them() -> void:
	var v := U.view_of(self, U.fixture("state", 3))
	for i in 12:
		var x := 480.0 + i * 12.0
		assert_almost_eq(v.near_ground(x, 0), v.ground_y(x) + 11.0, 0.01, "lane 0, in front")
		assert_almost_eq(v.near_ground(x, 1), v.ground_y(x) - 5.0, 0.01, "lane 1, behind")


# --- the tank -------------------------------------------------------------------------------------


func test_the_breech_window_shows_the_tray_and_the_rammer_while_idle() -> void:
	var v := U.view_of(self, U.fixture("state", 4))
	var img := v.interior.img
	var w := Rect2i(v.rig.windows["breechwin"]).grow(-1)
	var counts := {}
	for y in range(w.position.y, w.end.y):
		for x in range(w.position.x, w.end.x):
			var c := img.get_pixel(x, y).to_html(false)
			counts[c] = int(counts.get(c, 0)) + 1
	var most := 0
	for k: String in counts:
		most = maxi(most, int(counts[k]))
	assert_lt(float(most) / float(w.get_area()), 0.3, "no big empty patch of one colour")


func test_the_aft_idler_and_its_track_stay_inside_the_rear_plate() -> void:
	var rig := TankRig.shared()
	var idl: Dictionary = rig.gear["idler"]
	var c := TankRig.vec(idl["c"])
	var outer := float(idl["r"]) + 0.5
	outer += (
		float(rig.track.get("dd0", -2.0)) + float(rig.track["rows"]) * float(rig.track["row_px"])
	)
	var img := rig.base_tex.get_image()
	img.decompress()
	var rear := INF
	for y in range(100, int(c.y)):
		for x in int(c.x):
			if img.get_pixel(x, y).a > 0.5:
				rear = minf(rear, float(x))
				break
	assert_gte(c.x - outer, rear - 1.0, "the track round the idler ends at the rear plate")


func test_the_hulls_silhouette_has_no_stray_pixels() -> void:
	var img := TankRig.shared().base_tex.get_image()
	img.decompress()
	var lone := 0
	for y in range(1, img.get_height() - 1):
		for x in range(1, img.get_width() - 1):
			if img.get_pixel(x, y).a < 0.5:
				continue
			var nb := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if (dx != 0 or dy != 0) and img.get_pixel(x + dx, y + dy).a >= 0.5:
						nb += 1
			if nb == 0:
				lone += 1
	assert_eq(lone, 0, "no lone pixels off the hull")
