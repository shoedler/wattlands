extends GutTest
## The v3 view built headless from fixtures (docs/games/tank.md v3, 3, 4): the one tank for crews
## 1-4, every pixel_flex canvas, the machines in sync with their riders, the depth of field
## toggling, enemies in depth lanes, wrecks aging on sim time, the effects of shots, hits and the
## evade, and a view that only reads the state.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
## The seats each fixture crew mans (stations.json start_engines.landship: the first n of Drive,
## Gun, Loader, Lights).
const SEATS_OF := {
	1: ["drive"],
	2: ["drive", "gun"],
	3: ["drive", "gun", "loader"],
	4: ["drive", "gun", "loader", "lights"],
}


func test_the_one_tank_builds_and_runs_from_every_fixture() -> void:
	for crew in [1, 2, 3, 4]:
		for kind: String in ["state", "gun_line", "boss"]:
			var v := U.view_of(self, U.fixture(kind, crew))
			U.run(v, 20)
			for n: String in ["Back", "World", "WorldLight", "Tank", "Light", "Front", "Post"]:
				assert_not_null(v.layer(n), n)
			var manned: Array = []
			for seat in TankRig.SEATS:
				if v.rider_on(seat) != null:
					manned.append(seat)
					assert_gte(int(v.seat_slots[seat]), 0, "crew %d %s" % [crew, seat])
				else:
					assert_eq(int(v.seat_slots[seat]), -1, "crew %d %s empty" % [crew, seat])
			assert_eq(
				manned, SEATS_OF[crew], "crew %d %s: a rider on every manned seat" % [crew, kind]
			)
			assert_not_null(v.body, "the tank's sprite")
			assert_gt(v.interior.paints, 0, "the rooms painted")
			assert_gt(v.frames, 20)


func test_the_lights_seat_has_its_rider_and_the_searchlights_follow_its_arc() -> void:
	var s := U.fixture("state", 4)
	var v := U.view_of(self, s)
	assert_eq(v.rider_on("lights"), s.rider_at(s.station(TankIds.ENGINE_ARC).slot), "from stations")
	assert_eq(v.rider_of("arc"), v.rider_on("lights"))
	(s.station(TankIds.ENGINE_ARC) as TankArcState).lit = true
	assert_eq(v.searchlight_k(s), 1.0, "the arc rider in band lights the searchlights")
	assert_true(v.turret_search_on(s), "the turret searchlight is on")
	var arc := s.station(TankIds.ENGINE_ARC) as TankArcState
	arc.lit = false
	assert_lt(v.searchlight_k(s), 0.5, "out of band they dim")
	assert_false(v.turret_search_on(s), "and the turret searchlight is off")
	arc.stalled = true
	assert_lt(v.searchlight_k(s), 0.2, "a stalled generator nearly kills them")
	var v3 := U.view_of(self, U.fixture("state", 3))
	assert_false(v3.turret_search_on(v3.game.state), "the Lights seat empty: the turret one off")


func test_pixel_flex_canvases_build_and_keep_the_world_on_screen() -> void:
	for size: Vector2 in [
		Vector2(852, 480), Vector2(960, 540), Vector2(1146, 480), Vector2(1280, 680)
	]:
		var s := U.fixture("state", 3)
		var v := U.view_of(self, s, Wl.SOLO, 1, size)
		U.run(v, 5)
		assert_eq(v.canvas, size)
		assert_eq(v.dof.canvas, size)
		assert_eq(v.y_off, roundf((size.y - 540.0) * 0.5))
		var rf := float(TankConst.REAR_SCREEN_X) + float(s.hull.hull_w)
		var right := v.sx(v.cam_x + rf + TankConst.NEAR_SPAN_PX)
		assert_lte(right, TankFarMap.near_end_x(size.x), "%s: the near span fits its panel" % size)
		var front := v.at_sprite(v.rig.detail("headlight")["at"]).x
		assert_lt(right, size.x, "%s: on the canvas" % size)
		assert_gt(right, front + 60.0, "%s: the tank leaves road ahead in view" % size)
		assert_gte(v.xf.origin.x, 0.0)
		var band := v.dof.band
		assert_eq(
			band, TankView.BAND + Vector2(v.y_off, v.y_off), "the sharp band moves with the stage"
		)


func test_the_near_span_runs_from_the_nose_to_the_seam_on_every_canvas() -> void:
	# SPEC_TANK section 2: canvas, the nose (front), the span's end, k.
	for row: Array in [
		[Vector2(960, 540), 471.0, 616.0, 0.725],
		[Vector2(852, 480), 471.0, 552.0, 0.405],
		[Vector2(1280, 680), 567.0, 846.0, 1.395],
	]:
		var size: Vector2 = row[0]
		var v := U.view_of(self, U.fixture("state", 3), Wl.SOLO, 1, size)
		var rf := float(TankConst.REAR_SCREEN_X) + float(v.game.state.hull.hull_w)
		assert_almost_eq(v.tank_pos.x + v.headlight_x(), float(row[1]), 1.0, "%s: nose" % size)
		assert_almost_eq(v.near_k(), float(row[3]), 0.006, "%s: k" % size)
		var nose := v.sx(v.cam_x + rf)
		assert_almost_eq(nose, v.tank_pos.x + v.headlight_x(), 0.01, "%s: from the nose" % size)
		var end := v.sx(v.cam_x + rf + TankConst.NEAR_SPAN_PX)
		assert_almost_eq(end, TankFarMap.near_end_x(size.x) - 6.0, 0.01, "%s: to the seam" % size)
		assert_almost_eq(end, float(row[2]), 1.0, "%s: the table's end" % size)


func test_a_very_wide_canvas_keeps_the_arts_own_scale_and_shows_more_road() -> void:
	var v := U.view_of(self, U.fixture("state", 3), Wl.SOLO, 1, Vector2(1920, 680))
	assert_eq(v.near_k(), TankView.NEAR_K_MAX, "capped")
	var rf := float(TankConst.REAR_SCREEN_X) + float(v.game.state.hull.hull_w)
	var end := v.sx(v.cam_x + rf + TankConst.NEAR_SPAN_PX)
	assert_lt(end, TankFarMap.near_end_x(1920.0) - 6.0, "more road past the span")


func test_the_hulls_own_span_keeps_its_mapping() -> void:
	var v := U.view_of(self, U.fixture("state", 3))
	var rear := float(TankConst.REAR_SCREEN_X)
	assert_almost_eq(v.sx(v.cam_x + rear), v.tank_pos.x + TankView.ART_REAR, 0.01, "its rear")
	var rf := rear + float(v.game.state.hull.hull_w)
	assert_almost_eq(v.sx(v.cam_x + rf), v.tank_pos.x + v.headlight_x(), 0.01, "its front")


func test_machines_turn_with_their_riders_cadence_and_stand_still_at_zero() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	for r in s.riders:
		r.cadence_rpm = 90.0
	U.run(v, 60)
	var p0 := v.machine_phase("loader")
	U.run(v, 60)
	var turned := v.machine_phase("loader") - p0
	assert_almost_eq(turned, 1.5, 0.2, "90 rpm for 1 s is 1.5 crank revolutions")
	for r in s.riders:
		r.cadence_rpm = 0.0
		r.raw_w = 0.0
	U.run(v, 3)
	var p1 := v.machine_phase("gun")
	U.run(v, 60)
	assert_eq(v.machine_phase("gun"), p1, "at 0 rpm everything stands still")
	assert_eq(v.machine_phase("sec"), 0.0, "an empty seat never turns")


func test_the_power_ratio_is_watts_over_the_target() -> void:
	var r := TankRiderState.new()
	r.ftp = 200.0
	r.ftp_pct = 90.5
	r.raw_w = 181.0
	assert_almost_eq(TankView.power_ratio(r), 1.0, 0.001)
	r.ftp_pct = 50.0
	assert_false(TankMech.in_band(TankView.power_ratio(r)), "half the band centre is under band")
	assert_eq(TankView.power_ratio(null), 0.0)


func test_the_miniature_pass_follows_the_option_and_turns_itself_off() -> void:
	var v := U.view_of(self, U.fixture("state", 3))
	assert_true(v.dof.active(), "on by default (player option miniature)")
	assert_true(v.dof.visible)
	v.set_miniature(false)
	U.run(v, 1)
	assert_false(v.dof.active())
	assert_false(v.dof.visible)
	v.set_miniature(true)
	U.run(v, 1)
	assert_true(v.dof.visible)
	var g := U.make_game(U.fixture("state", 3))
	autofree(g)
	g.ctx.local_player().options["miniature"] = false
	var v2 := U.make_view(self, g)
	assert_false(v2.dof.active())


func test_slow_frames_for_five_seconds_switch_the_pass_off() -> void:
	var d := TankDof.new()
	autofree(d)
	for _i in 600:
		d.note_frame(1.0 / 60.0, 1.0 / 60.0)
	assert_false(d.auto_off, "60 fps keeps it")
	for _i in 100:
		d.note_frame(0.5, 30.0)
	assert_false(d.auto_off, "fast-forward frames never count")
	for _i in 300:
		d.note_frame(0.022, 0.022)
	assert_true(d.auto_off, "6.6 s of 45 fps")
	assert_false(d.active())
	var d2 := TankDof.new()
	autofree(d2)
	for _i in 120:
		d2.note_frame(0.022, 0.022)
	assert_false(d2.auto_off, "under 5 s keeps it")


func test_near_threats_stand_in_the_lanes_the_rules_hold_them_in() -> void:
	var s := U.fixture("gun_line", 3)
	s.enemies.clear()
	var x := s.hull.x_px + float(s.hull.hull_w) + 60.0
	for i in 2:
		var e := TankEnemyState.new()
		e.id = 100 + i
		e.code = TankIds.ENEMY_CODES[TankIds.ENEMY_RECON]
		e.x_px = x + i * 12.0
		e.w = 52
		e.h = 24
		e.hp = 20.0
		e.hp_max = 30.0
		e.lane = 1 - i
		s.enemies.append(e)
	var v := U.view_of(self, s)
	U.run(v, 2)
	for e in s.enemies:
		assert_eq(int(v.lanes[e.id]), e.lane, "enemy %d in its rules lane" % e.id)
	var nearer: Rect2 = v.enemy_rects[101]
	var further: Rect2 = v.enemy_rects[100]
	assert_gt(nearer.end.y, further.end.y, "the front lane stands lower on the road")
	for id: int in [100, 101]:
		var foot: Vector2 = v.enemy_feet[id]
		var lane := int(v.lanes[id])
		assert_almost_eq(
			foot.y,
			TankView.lane_foot(lane) + v.ground_y(foot.x) - TankView.GROUND,
			0.01,
			"lane %d stands on the road's relief" % lane
		)
	s.enemies[0].lane = 9
	U.run(v, 1)
	assert_eq(int(v.lanes[100]), TankView.LANES - 1, "a lane past the last is drawn in the last")


## The crews whose rules hull spans the drawn tank (the v3 contracts give every crew the r6 hull,
## TankGeometry from r6_hitbox.json: all of them).
func _full_hull_crews() -> Array[int]:
	var out: Array[int] = []
	var rig := TankRig.shared()
	var art := (rig.detail("headlight")["at"] as Vector2).x - TankView.ART_REAR
	for crew in [1, 2, 3, 4]:
		var s := U.fixture("state", crew)
		if float(s.hull.hull_w) * TankView.S >= art * 0.95:
			out.append(crew)
	return out


func test_the_rules_gun_lines_are_drawn_on_the_panel_their_frame_says() -> void:
	for crew in _full_hull_crews():
		for index: int in [2, 5, 8]:
			var rig := TankRulesRig.new(crew)
			rig.enter(index, 0.5)
			var v := U.view_of(self, rig.state)
			U.run(v, 2)
			var at := "crew %d gun line %d" % [crew, index]
			var live := 0
			for e in rig.state.enemies:
				if e.mode == TankIds.EM_DEAD:
					continue
				live += 1
				if e.is_near():
					assert_eq(int(v.lanes[e.id]), e.lane, "%s: near %d" % [at, e.id])
				else:
					assert_true(v.far_rects.has(e.id), "%s: far %d" % [at, e.id])
			assert_eq(v.lanes.size() + v.far_rects.size(), live, "%s: every live enemy drawn" % at)


func test_the_behemoth_is_drawn_for_every_crew() -> void:
	assert_eq(_full_hull_crews(), [1, 2, 3, 4] as Array[int], "one tank for every crew")
	for crew in _full_hull_crews():
		var s := U.fixture("boss", crew)
		var v := U.view_of(self, s)
		U.run(v, 2)
		var br := v.hud_boss_rect()
		assert_true((v.panels["far"] as Rect2).encloses(br), "crew %d: in the far panel" % crew)
		assert_true(br.grow(1.0).has_point(v.hud_boss_muzzle()), "crew %d: its main gun" % crew)


func test_wrecks_age_on_sim_time_into_debris_heaps() -> void:
	var s := TankFixturesV4.make("near_ambush")
	var v := U.view_of(self, s)
	U.run(v, 2)
	var id := s.enemies[0].id
	s.enemies.remove_at(0)
	v.apply_cue(s, TankEvents.KILL, TankEvents.kill(id, 7, TankEvents.BY_BOW, 0))
	assert_eq(v.wrecks.size(), 1)
	var w := v.wrecks[0]
	assert_eq(v.wreck_collapse(w), 0.0, "a burning hulk at first")
	assert_eq(v.wreck_fire(w), 1.0)
	U.run(v, 120, 1.0 / 60.0, false)
	assert_eq(v.wreck_collapse(w), 0.0, "frame time does not age it")
	s.t += TankView.WRECK_HULK_S + TankView.WRECK_COLLAPSE_S + 0.5
	U.run(v, 1)
	assert_eq(v.wreck_collapse(w), 1.0, "a debris heap after the collapse")
	assert_lt(v.wreck_fire(w), 1.0, "the fire dies down")
	s.t += TankView.WRECK_BURN_S
	U.run(v, 1)
	assert_eq(v.wreck_fire(w), 0.0)
	s.t += TankView.WRECK_GONE_S
	U.run(v, 1)
	assert_eq(v.wrecks.size(), 0, "gone in the end")


func test_shots_hits_and_bursts_light_the_scene() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	v.apply_cue(s, TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 15))
	assert_eq(v.firing.fire_t, 0.0, "the main gun fires")
	assert_eq(v.firing.shots, 1)
	assert_gt(v.fx.wash, 0.0, "the flash lights the scene")
	assert_eq(v.firing.flash_k(), 1.0)
	(s.station(TankIds.ENGINE_FEED) as TankFeedState).rounds += 1
	U.run(v, 1)
	assert_eq(v.firing.rounds.size(), 1, "a Secondaries round: its flash, tracer and case")
	v.apply_cue(
		s,
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_TANK, 0, 12.0, TankIds.SHELL_ENEMY, 0.0, 3300.0)
	)
	assert_gt(v.shake, 0.0, "a hit shakes the hull")
	U.run(v, 200)
	assert_eq(v.shake, 0.0, "and settles")


func test_the_evade_lurches_the_tank_or_blows_a_smoke_screen() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	var diesel := s.station(TankIds.ENGINE_DIESEL).slot
	var steam := s.station(TankIds.ENGINE_STEAM).slot
	v.apply_cue(s, TankEvents.EVADE, TankEvents.evade(13, 3, false))
	assert_eq(v.lurch_s, -1.0, "a missed evade does nothing")
	assert_eq(v.screen_s, -1.0)
	v.apply_cue(s, TankEvents.EVADE, TankEvents.evade(13, 3, true, diesel))
	assert_gte(v.lurch_s, 0.0, "the drive's sprint lurches the tank")
	assert_eq(v.screen_s, -1.0, "no smoke screen for the drive")
	var rest := v.xf.origin.x
	U.run(v, 30)
	assert_gt(v.xf.origin.x, rest + 2.0, "forward")
	U.run(v, 60)
	assert_eq(v.lurch_s, -1.0)
	var before := v.fx.smoke.size()
	v.apply_cue(s, TankEvents.EVADE, TankEvents.evade(13, 3, true, steam))
	assert_gte(v.screen_s, 0.0, "the loader's sprint blows a smoke screen")
	assert_eq(v.lurch_s, -1.0, "and does not lurch the tank")
	assert_gt(v.fx.smoke.size(), before + 15, "the boiler blows a smoke screen")
	assert_eq(v.evade_kind(s, -1), "lurch", "an unknown slot lurches")
	var solo := U.fixture("state", 1)
	assert_eq(v.evade_kind(solo, solo.stations[0].slot), "lurch", "the drive lurches")


func test_the_turret_never_turns_and_the_barrel_holds_its_elevation() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	s.hull.elev_deg = -12.0
	U.run(v, 1)
	assert_gt(v.barrel_vector().y, 0.0, "-12 degrees points down")
	s.hull.elev_deg = 30.0
	U.run(v, 1)
	assert_almost_eq(v.barrel_vector().angle(), -deg_to_rad(30.0) + v.xf.get_rotation(), 0.001)
	s.hull.traverse_s = 1.0
	s.hull.facing = TankIds.FACE_LEFT
	U.run(v, 1)
	assert_gt(
		v.muzzle().x, v.hud_tank_point("turret_pivot").x, "nothing behind, nothing to turn to"
	)
	assert_eq(v.hud_barrel_dir(), 1.0)


func test_the_halt_line_stands_ahead_in_an_advance() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	if s.seg.seg != TankIds.SEG_ADVANCE:
		pass_test("the fixture is not an Advance")
		return
	var hx := TankWorldDraw.halt_x(s)
	assert_false(is_nan(hx))
	assert_gt(v.sx(hx), v.hud_tank_point("headlight").x, "ahead of the tank")


func test_the_view_never_writes_the_state() -> void:
	for crew in [1, 4]:
		var s := U.fixture("gun_line", crew)
		var before := JSON.stringify(s.to_dict())
		var v := U.view_of(self, s)
		v.apply_cue(s, TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 15))
		v.apply_cue(s, TankEvents.SHOT, TankEvents.shot(1, TankIds.SHELL_BOW, 17))
		v.apply_cue(s, "evade", {"e": 1, "ok": 1})
		U.run(v, 90, 1.0 / 60.0, false)
		assert_eq(JSON.stringify(s.to_dict()), before, "crew %d" % crew)


func test_a_client_view_interpolates_from_snapshots() -> void:
	var s := U.fixture("state", 3)
	var g := U.make_game(s, Wl.CLIENT, 2)
	autofree(g)
	var v := U.make_view(self, g)
	for i in 5:
		s.tick += 2
		s.t = s.tick * Wl.SIM_DT
		s.hull.x_px += 4.0
		g.snapshot_applied.emit(s.tick)
		U.run(v, 6, 1.0 / 60.0, false)
	assert_gt(v.history.mean_spacing(), 0.0)
	assert_lt(
		v.cam_x + float(TankConst.REAR_SCREEN_X), s.hull.x_px, "drawn a little behind the newest"
	)


func test_the_hud_geometry_reads_the_view() -> void:
	for size: Vector2 in [Vector2(960, 540), Vector2(1146, 480)]:
		var s := U.fixture("state", 3)
		var v := U.view_of(self, s, Wl.SOLO, 1, size)
		U.run(v, 2)
		assert_eq(v.game.get_meta(TankHudGeom.VIEW_META), v, "the view registers on the game")
		var g := TankHudGeom.make(s, v.game.get_meta(TankHudGeom.VIEW_META))
		assert_eq(g.view, v)
		var wx := s.hull.x_px + 400.0
		assert_eq(g.world_x(wx), v.sx(wx))
		assert_eq(g.ground_y(), TankView.GROUND + v.y_off)
		assert_eq(g.tank_point("muzzle"), v.muzzle() + Vector2(0, v.y_off))
		assert_eq(g.tank_point("barrel_pivot"), v.barrel_pivot() + Vector2(0, v.y_off))
		assert_almost_eq(g.tank_point("rear").y, g.ground_y(), 0.01)
		assert_eq(v.hud_bow_muzzles().size(), 2, "both bow guns' muzzles")
		assert_eq(v.hud_bow_muzzles()[0], v.bow_muzzle(0) + Vector2(0, v.y_off))
		var body := v.hud_tank_rects()
		assert_eq(body.size(), 2, "the turret and the hull from the hitbox")
		assert_true(body[0].has_point(v.barrel_pivot() + Vector2(-20, v.y_off)), "the turret")
		assert_almost_eq(v.hud_barrel_length(), v.rig.gun_len + 1.0, 0.01)
		var e := s.enemies[0]
		var r := g.enemy_rect(e)
		assert_eq(r, v.far_rects[e.id], "a far enemy: canvas px from the far panel")
		assert_eq(v.hud_enemy_rect(-999), Rect2())
		assert_eq(g.boss_rect(), Rect2(), "no Behemoth in an Advance")
	var b := U.fixture("boss", 3)
	var vb := U.view_of(self, b)
	U.run(vb, 2)
	var gb := TankHudGeom.make(b, vb)
	assert_gt(gb.boss_rect().size.x, 100.0)
	assert_true(
		gb.boss_rect().grow(1.0).has_point(vb.hud_boss_muzzle()), "the main gun on the sprite"
	)
