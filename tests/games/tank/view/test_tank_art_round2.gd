extends GutTest
## The art critic's second round on the v4 frames: a real night over the far treeline, a far base that is scenery and
## not a pasted slab, enemy hatches that read as warm rooms, near threats that run and stand apart, a firing mark that
## stays a hot barrel, a shell screen that folds between shots, and tags that stay where they are.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _view(name: String, size: Vector2 = Vector2(960, 540)) -> TankView:
	return U.view_of(self, TankFixturesV4.make(name), Wl.SOLO, 1, size)


static func _luma(c: Color) -> float:
	return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0


# --- The far night ------------------------------------------------------------------------------------------


func test_a_panel_shows_eight_to_twelve_soft_stars_scattered_and_no_lattice() -> void:
	var stars := TankFarSky.stars()
	for w: float in [286.0, 330.0, 420.0]:
		var seen: Array[int] = []
		for slide in range(0, TankFarSky.W, 32):
			var n := 0
			for p in stars:
				if posmod(p.x - slide, TankFarSky.W) < int(w):
					n += 1
			seen.append(n)
		var total := 0
		for n2 in seen:
			total += n2
		var mean := float(total) / float(seen.size())
		assert_between(mean, 7.0, 13.0, "about 8-12 in a panel %d wide (%.1f)" % [int(w), mean])
	var rows := {}
	for i in stars.size():
		rows[stars[i].y] = true
		for j in i:
			var dx := absi(stars[i].x - stars[j].x)
			dx = mini(dx, TankFarSky.W - dx)
			assert_true(
				(
					dx >= TankFarSky.STAR_APART
					or absi(stars[i].y - stars[j].y) >= TankFarSky.STAR_APART
				),
				"no two side by side"
			)
	assert_gt(rows.size(), stars.size() - 3, "not on rows")


func test_the_soft_stars_are_two_px_and_quieter_than_the_near_sky() -> void:
	var img := TankFarSky.sky_image()
	var sky := TankFarPanel.SKY_LOW
	for p in TankFarSky.stars():
		var c := img.get_pixelv(p)
		assert_eq(img.get_pixelv(p + Vector2i(1, 1)), c, "a 2 x 2 core")
		var on_sky := sky.lerp(Color(c.r, c.g, c.b), c.a)
		assert_lte(_luma(on_sky), 110.0, "under the near sky's 180 (the top shade takes it to 90)")
		assert_lt(img.get_pixelv(p + Vector2i(-1, 0)).a, c.a, "a softer halo")


func test_the_mountains_stand_over_the_firs_at_a_value_just_off_the_sky() -> void:
	var foot_of_firs := TankFarPanel.FOREST_FOOT[0]
	var highest := INF
	for x in TankFarSky.W:
		highest = minf(highest, TankFarSky.back_top(float(x)))
		assert_almost_eq(
			TankFarSky.back_top(float(x)),
			TankFarSky.back_top(float(x + TankFarSky.W)),
			0.01,
			"it tiles"
		)
	assert_lt(highest, foot_of_firs - 130.0, "a peak well over the treeline")
	var sky_l := _luma(TankFarPanel.SKY_TOP.lerp(TankFarPanel.SKY_LOW, 0.5))
	assert_almost_eq(_luma(TankFarSky.BACK), sky_l, 10.0, "just off the sky")
	assert_lt(_luma(TankFarSky.FRONT), _luma(TankFarSky.BACK), "the nearer range is darker")


func test_the_ridge_runs_down_behind_the_treeline_so_no_edge_shows_over_the_ground() -> void:
	var img := TankFarSky.ridge_image()
	assert_gte(img.get_height(), int(TankFarPanel.GROUND_TOP), "it ends under the ground band")
	for x in range(0, TankFarSky.W, 40):
		assert_eq(img.get_pixel(x, img.get_height() - 1).a, 1.0, "solid to its last row")


# --- The far base -------------------------------------------------------------------------------------------


func test_a_base_is_dark_and_its_foot_stands_in_the_scrub_over_it() -> void:
	var v := _view("far_duel")
	assert_lt(v.far.layer("Base").modulate.v, 0.5, "a silhouette in the far air")
	assert_gt(v.far.layer("Scrub").get_index(), v.far.layer("Base").get_index(), "over its foot")
	assert_lt(v.far.layer("Scrub").get_index(), v.far.layer("World").get_index())


func test_a_lamp_post_never_rises_out_of_a_hull() -> void:
	var v := _view("far_duel")
	U.run(v, 2)
	var r: Rect2 = v.far.rects.values()[0]
	var over := r.get_center().x - TankForest.LAMP_X
	assert_false(v.far.lamp_clear(over), "a hull across the post")
	var free := -1000.0
	assert_true(v.far.lamp_clear(free), "clear of every hull")


# --- The firing mark ----------------------------------------------------------------------------------------


func test_a_muzzle_never_lands_on_a_nearer_turret() -> void:
	var near := {
		"id": 1, "range_m": 1200.0, "lane": 0, "half_w": 60.0, "turret": Rect2(-30, -46, 50, 20)
	}
	var back := {"id": 2, "range_m": 1300.0, "lane": 0, "half_w": 50.0}
	var plain := TankFarMap.place([near, back], 330.0)
	var foot: Vector2 = plain[2]
	var near_foot: Vector2 = plain[1]
	# a muzzle, from its foot, that would land right in the nearer turret
	var aim := near_foot + Vector2(-5, -36)
	back["muzzle"] = aim - foot
	var placed := TankFarMap.place([near, back], 330.0)
	var at: Vector2 = (placed[2] as Vector2) + (back["muzzle"] as Vector2)
	var box: Rect2 = near["turret"] as Rect2
	box.position += placed[1] as Vector2
	assert_false(box.has_point(at), "the muzzle stands clear of the turret")
	assert_gt((placed[2] as Vector2).x, foot.x, "it moves back along the field")
	assert_eq(placed[1], plain[1], "the nearer tank stays")


func test_rows_without_the_anatomy_stand_as_they_did() -> void:
	var rows := [
		{"id": 1, "range_m": 1200.0, "lane": 0, "half_w": 60.0},
		{"id": 2, "range_m": 1300.0, "lane": 0, "half_w": 50.0},
	]
	var a := TankFarMap.place(rows, 330.0)
	rows[0]["turret"] = Rect2(-300, -300, 1, 1)
	rows[1]["muzzle"] = Vector2(-50, -30)
	assert_eq(TankFarMap.place(rows, 330.0), a, "nothing in the way: nothing moves")


func test_only_the_soonest_three_shots_burn_on_a_crowded_field() -> void:
	var v := _view("cap_v4")
	U.run(v, 2)
	var s := v.game.state
	var due: Array[float] = []
	for e in s.enemies:
		if v.far.feet.has(e.id) and e.telegraph_s > 0.0:
			due.append(e.telegraph_s)
	assert_gt(due.size(), 3, "the crowd")
	due.sort()
	var burning := v.far.burning_shots(s)
	var n := TankFarPanel.SIGNAL_BURNS
	if v.far.boss_box.size != Vector2.ZERO and s.boss.telegraph_s > 0.0:
		n -= 1
	assert_eq(burning.size(), n)
	for id: int in burning:
		assert_lte(s.enemy(id).telegraph_s, due[n - 1], "the soonest")


func test_a_lone_shooter_burns() -> void:
	var v := _view("far_duel")
	U.run(v, 2)
	assert_gte(v.far.burning_shots(v.game.state).size(), 1)


# --- The shell screen ---------------------------------------------------------------------------------------


func test_the_screen_folds_to_its_ruler_between_shots_and_opens_on_a_launch() -> void:
	var s := TankFixturesV4.make("far_duel")
	var shells := s.shells.duplicate()
	s.shells.clear()
	var v := U.view_of(self, s, Wl.SOLO, 1, Vector2(960, 540))
	v.pip.puffs.clear()
	for _i in 30:
		v.pip.frame(s, 1.0 / 30.0)
	assert_eq(v.pip.open, 0.0, "folded with nothing up")
	assert_true(v.pip.busy(s), "and still a ruler: enemies stand")
	assert_false(v.pip.flying(s))
	s.shells.append(shells[0])
	assert_true(v.pip.flying(s))
	for _i in 15:
		v.pip.frame(s, 1.0 / 30.0)
	assert_eq(v.pip.open, 1.0, "open while it flies")


func test_with_no_enemy_it_is_a_tab_and_says_nothing() -> void:
	var s := TankFixturesV4.make("restart")
	var v := U.view_of(self, s, Wl.SOLO, 1, Vector2(960, 540))
	assert_false(v.pip.busy(s))
	assert_lt(TankPip.TAB.x, 20.0, "the hull's icon, no dashes")


func test_the_seam_has_no_plate_without_a_range() -> void:
	var v := _view("far_duel")
	assert_true(v.seam.shows_plate(), "a target: its range")
	v.game.state.hull.target_id = 0
	assert_false(v.seam.shows_plate(), "no dead dashes")


# --- The tags -----------------------------------------------------------------------------------------------


func test_the_halt_plate_stands_in_the_same_place_with_or_without_a_threat() -> void:
	for cv: Vector2 in [Vector2(960, 540), Vector2(852, 480), Vector2(1280, 540)]:
		var s := TankFixturesV4.make("near_ambush", 3)
		var g: TankGame = autofree(U.make_game(s))
		var v := U.make_view(self, g, cv)
		v.advance(1.0 / 60.0)
		var near: Rect2 = TankFarMap.panels(cv, false)["near"]
		var body: Array[Rect2] = v.hud_tank_rects()
		var gy := v.hud_ground_y()
		var size := TankHudTags.post_size("HALT LINE", "789 m")
		var threats: Array[Rect2] = [Rect2(600, 370, 60, 30)]
		var calm := TankHudTags.post_layout(5000.0, size, gy, near, body)
		var hot := TankHudTags.post_layout(5000.0, size, gy, near, body, threats)
		assert_eq(calm["plate"], hot["plate"], "%s: it never jumps" % cv)
		assert_true(bool(calm["pole"]), "%s: the post marks the line" % cv)
		assert_false(bool(hot["pole"]), "%s: a pinned line stands no post in their lane" % cv)
		assert_lte((calm["plate"] as Rect2).end.y, gy - 80.0, "%s: over the beam" % cv)


func test_on_a_short_canvas_the_speed_plate_stays_off_the_riders_panel() -> void:
	var cv := Vector2i(852, 480)
	var s := TankFixturesV4.make("cap_v4", 3)
	var g: TankGame = autofree(U.make_game(s))
	var v := U.make_view(self, g, Vector2(cv))
	v.advance(1.0 / 60.0)
	var body: Array[Rect2] = v.hud_tank_rects()
	var near: Rect2 = TankFarMap.panels(Vector2(cv), false)["near"]
	var mine := TankHud.anchored(TankHud.LAYOUT["mine"], cv)
	var sr := TankHudTags.speed_rect(
		v.hud_tank_point("rear"), 60.0, false, body, near, float(mine.position.y)
	)
	assert_false(sr.intersects(Rect2(mine)), "off the panel")
	assert_true(TankHudTags.clear_of(sr, body), "off the tank")
	assert_true(near.encloses(sr), "in the near panel")


# --- The near threats ---------------------------------------------------------------------------------------


func test_a_running_threat_streams_smoke_back_and_its_dust_lies_under_its_wheels() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	s.enemy(41).mode = TankIds.EM_MOVE
	s.enemy(42).mode = TankIds.EM_MOVE
	v.fx.wisps.clear()
	v.dust_fx.smoke.clear()
	for _i in 30:
		v._emit_near(s, 1.0 / 60.0)
	assert_gt(v.dust_fx.smoke.size(), 0, "the dust is on the road's own pool")
	assert_gt(v.fx.wisps.size(), 4, "a streak of wisps")
	for p: Dictionary in v.fx.wisps:
		assert_lt((p["vel"] as Vector2).x, -50.0, "running back toward us")
	for d: Dictionary in v.dust_fx.smoke:
		assert_gt((d["pos"] as Vector2).y, 340.0, "low on the road")


func test_a_threat_bursting_from_a_bush_keeps_throwing_leaves() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	v.fx.leaves.clear()
	s.enemy(41).mode = TankIds.EM_ENTER
	for _i in 60:
		v._emit_near(s, 1.0 / 60.0)
	assert_gt(v.fx.leaves.size(), 10, "leaves while it comes out")
	v.fx.leaves.clear()
	s.enemy(41).mode = TankIds.EM_PAUSE
	s.enemy(42).mode = TankIds.EM_PAUSE
	for _i in 60:
		v._emit_near(s, 1.0 / 60.0)
	assert_eq(v.fx.leaves.size(), 0, "none once it is out")


func test_the_bush_goes_on_shedding_after_the_burst_and_then_stops() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	s.enemy(41).mode = TankIds.EM_PAUSE
	s.enemy(42).mode = TankIds.EM_PAUSE
	v.apply_cue(s, TankEvents.AMBUSH, TankEvents.ambush(41, s.enemy(41).code))
	var n := v.fx.leaves.size()
	assert_gt(n, 20, "the burst")
	v.fx.leaves.clear()
	for _i in 60:
		v._emit_near(s, 1.0 / 60.0)
	assert_gt(v.fx.leaves.size(), 4, "still falling a second on")
	v.fx.leaves.clear()
	for _i in 120:
		v._emit_near(s, 1.0 / 60.0)
	var late := v.fx.leaves.size()
	v.fx.leaves.clear()
	for _i in 60:
		v._emit_near(s, 1.0 / 60.0)
	assert_eq(v.fx.leaves.size(), 0, "it stops (%d near its end)" % late)


func test_a_crowd_of_threats_shares_its_smoke() -> void:
	var v := _view("cap_v4")
	U.run(v, 2)
	v.fx.wisps.clear()
	v.fx.smoke.clear()
	for _i in 60:
		v._emit_near(v.game.state, 1.0 / 60.0)
	assert_lte(
		v.fx.wisps.size() + v.fx.smoke.size(),
		int(TankView.NEAR_EXHAUST_S) * TankView.NEAR_EMIT_MAX + 1,
		"no more than four threats' worth a second"
	)


func test_leaves_are_hard_pixels_that_flutter_down_and_go() -> void:
	var fx := TankFx.new()
	fx.seed_rng(3)
	fx.leaf(Vector2(100, 300), Vector2(-10, -20), 1.0, Color.WHITE)
	assert_eq(fx.count(), 1)
	var y0: float = (fx.leaves[0]["pos"] as Vector2).y
	for _i in 30:
		fx.step(1.0 / 60.0, 0.0)
	fx.step(0.4, 0.0)
	assert_gt((fx.leaves[0]["pos"] as Vector2).y, y0 - 20.0)
	fx.step(0.5, 0.0)
	assert_eq(fx.leaves.size(), 0, "gone at its life's end")
	fx.leaf(Vector2.ZERO, Vector2.ZERO, 1.0, Color.WHITE)
	fx.clear()
	assert_eq(fx.count(), 0)


func test_near_threats_carry_a_dark_line_and_the_far_ones_none() -> void:
	var v := _view("near_ambush")
	U.run(v, 2)
	assert_gt(float(v.near_pose(v.game.state.enemy(41))["halo"]), 0.0)
	var f := _view("far_duel")
	U.run(f, 2)
	var e := f.game.state.enemies[0]
	assert_false(f.far.pose_of(e, f.far.feet[e.id]).has("halo"))


# --- The warm cues ------------------------------------------------------------------------------------------


func test_a_hatch_is_a_ramp_of_amber_from_dark_at_the_top_to_hot_at_the_sill() -> void:
	var top := TankEnemyDraw.HATCH_TOP
	var sill := TankEnemyDraw.HATCH_SILL
	assert_lt(top.v, 0.3, "dark at its top")
	assert_gt(sill.v, 0.6, "hot at its sill")
	for c: Color in [top, sill, TankEnemyDraw.HATCH_EDGE, TankEnemyDraw.HATCH_PLATE]:
		assert_gt(c.r, c.g * 1.7, "amber: warm")
		assert_gt(c.g, c.b * 1.7, "amber, no pale grey")


func test_the_recons_hatch_is_a_shut_door_and_its_glow_is_in_the_louvre() -> void:
	var row := TankEnemyKit.shared().kind(TankIds.ENEMY_RECON)
	assert_eq((row["hatches"] as Array).size(), 0, "no orange dash on its belly")
	assert_gt((row["vents"] as Array).size(), 0, "the engine's warmth in the louvre")
