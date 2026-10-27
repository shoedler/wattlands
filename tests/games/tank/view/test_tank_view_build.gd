extends GutTest
## The v2 view built headless from fixtures (docs/games/tank.md 3, 4): every tank variant for crews
## 1-4 (the Bastion's arc room included), every pixel_flex canvas, the machines in sync with their
## riders, the depth of field toggling, enemies in depth lanes, wrecks aging on sim time, the
## effects of shots, hits and the evade, and a view that only reads the state.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const VARIANT_OF := {1: "tank_1rider", 2: "tank_2rider", 3: "tank_3rider", 4: "tank_4rider"}
const ROOMS_OF := {
	1: ["diesel"],
	2: ["diesel", "dynamo"],
	3: ["diesel", "steam", "dynamo"],
	4: ["diesel", "steam", "dynamo", "arc"],
}


func test_every_variant_builds_and_runs_from_every_fixture() -> void:
	for crew in [1, 2, 3, 4]:
		for kind: String in ["state", "gun_line", "boss"]:
			var v := U.view_of(self, U.fixture(kind, crew))
			U.run(v, 20)
			assert_eq(v.variant, VARIANT_OF[crew], "crew %d %s" % [crew, kind])
			for n: String in ["Back", "World", "Tank", "Light", "Front", "Post"]:
				assert_not_null(v.layer(n), n)
			var rooms: Array = v.room_riders.keys()
			rooms.sort()
			var want: Array = (ROOMS_OF[crew] as Array).duplicate()
			want.sort()
			assert_eq(rooms, want, "crew %d: a rider in every engine room" % crew)
			assert_gt(v.frames, 20)


func test_the_bastion_has_its_arc_room_tower_and_rider() -> void:
	var s := U.fixture("state", 4)
	var v := U.view_of(self, s)
	assert_eq(v.variant, "tank_4rider")
	assert_true(v.room_rects.has("arc"))
	assert_eq(v.rider_of("arc"), s.rider_at(s.station(TankIds.ENGINE_ARC).slot), "from stations")
	assert_true(v.kit.has_anchor(v.variant, "searchlight_tower_lens"))
	(s.station(TankIds.ENGINE_ARC) as TankArcState).lit = true
	assert_eq(v.searchlight_k(s), 1.0, "the arc rider in band lights the searchlights")
	var arc := s.station(TankIds.ENGINE_ARC) as TankArcState
	arc.lit = false
	assert_lt(v.searchlight_k(s), 0.5, "out of band they dim")
	arc.stalled = true
	assert_lt(v.searchlight_k(s), 0.2, "a stalled generator nearly kills them")
	assert_eq(v.searchlight_k(U.fixture("state", 3)), 1.0, "no arc generator: always lit")


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
		var right := v.sx(v.cam_x + float(TankConst.SCREEN_W))
		assert_lte(right, size.x - 10.0, "%s: the rules' screen fits" % size)
		var front := v.anchor("headlight").x
		assert_lt(front, size.x * 0.6, "%s: the tank leaves the road ahead in view" % size)
		assert_gte(v.origin.x, 0.0)
		var band := v.dof.band
		assert_eq(
			band, TankView.BAND + Vector2(v.y_off, v.y_off), "the sharp band moves with the stage"
		)


func test_a_wider_canvas_shows_more_world_at_the_same_scale() -> void:
	var base := U.view_of(self, U.fixture("state", 3), Wl.SOLO, 1, Vector2(960, 540))
	var wide := U.view_of(self, U.fixture("state", 3), Wl.SOLO, 1, Vector2(1146, 480))
	var x0 := base.cam_x + 400.0
	var x1 := base.cam_x + 500.0
	assert_almost_eq(wide.sx(x1) - wide.sx(x0), base.sx(x1) - base.sx(x0), 0.01, "same scale")
	var beyond := wide.sx(wide.cam_x + 700.0)
	assert_lt(beyond, 1146.0, "world past the rules' screen shows on the wide canvas")
	assert_gt(base.sx(base.cam_x + 700.0), 960.0, "and is off the base canvas")


func test_machines_turn_with_their_riders_cadence_and_stand_still_at_zero() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	for r in s.riders:
		r.cadence_rpm = 90.0
	U.run(v, 60)
	var p0 := v.machine_phase("steam")
	U.run(v, 60)
	var turned := v.machine_phase("steam") - p0
	assert_almost_eq(turned, 1.5, 0.2, "90 rpm for 1 s is 1.5 crank revolutions")
	for r in s.riders:
		r.cadence_rpm = 0.0
		r.raw_w = 0.0
	U.run(v, 3)
	var p1 := v.machine_phase("dynamo")
	U.run(v, 60)
	assert_eq(v.machine_phase("dynamo"), p1, "at 0 rpm everything stands still")


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
	# The rider's option off at the start.
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


func test_enemies_stand_in_the_lanes_the_rules_hold_them_in() -> void:
	var s := U.fixture("gun_line", 3)
	s.enemies.clear()
	var x := s.hull.x_px + 420.0
	for i in 4:
		var e := TankEnemyState.new()
		e.id = 100 + i
		e.code = TankIds.ENEMY_CODES[TankIds.ENEMY_MEDIUM]
		e.x_px = x + i * 12.0
		e.w = 96
		e.h = 48
		e.hp = 40.0
		e.hp_max = 64.0
		e.lane = 3 - i
		s.enemies.append(e)
	var v := U.view_of(self, s)
	U.run(v, 2)
	for e in s.enemies:
		assert_eq(int(v.lanes[e.id]), e.lane, "enemy %d in its rules lane" % e.id)
	for i in range(1, 4):
		var nearer: Rect2 = v.enemy_rects[100 + i]
		var further: Rect2 = v.enemy_rects[100 + i - 1]
		assert_gt(nearer.end.y, further.end.y, "a nearer lane stands lower on the road")
	assert_lte(v.enemy_rects[103].end.y, TankView.ROAD_ENEMY_Y + 0.5, "enemies stand on the road")
	s.enemies[0].lane = 9
	U.run(v, 1)
	assert_eq(int(v.lanes[100]), TankView.LANES - 1, "a lane past the last is drawn in the last")


func test_the_rules_gun_lines_are_drawn_in_their_lanes_with_no_overlap_in_a_lane() -> void:
	for crew in [1, 2, 3, 4]:
		for index: int in [2, 5, 8]:
			var rig := TankRulesRig.new(crew)
			rig.enter(index, 0.5)
			var v := U.view_of(self, rig.state)
			U.run(v, 2)
			var at := "crew %d gun line %d" % [crew, index]
			var live: Array[TankEnemyState] = []
			for e in rig.state.enemies:
				if e.mode != TankIds.EM_DEAD:
					live.append(e)
					assert_eq(int(v.lanes[e.id]), e.lane, "%s: enemy %d" % [at, e.id])
			assert_eq(v.lanes.size(), live.size(), "%s: every live enemy drawn" % at)
			for i in live.size():
				for j in range(i + 1, live.size()):
					if live[i].lane != live[j].lane or live[i].side != live[j].side:
						continue
					var a: Rect2 = v.enemy_rects[live[i].id]
					var b: Rect2 = v.enemy_rects[live[j].id]
					assert_false(a.intersects(b), "%s: lane %d overlap" % [at, live[i].lane])


func test_the_behemoth_is_drawn_where_the_rules_hit_it() -> void:
	for crew in [1, 2, 3, 4]:
		var s := U.fixture("boss", crew)
		var v := U.view_of(self, s)
		U.run(v, 2)
		var br := v.boss_rect(s)
		assert_eq(br.position.x, roundf(v.sx(v.boss_x(s))), "crew %d: its left edge" % crew)
		var aux := TankAux.of(s)
		var meta: Dictionary = v.kit.enemies["behemoth"]["meta"]
		var at: Array = (meta["bogies_at"] as Array).duplicate()
		at.append(meta["turret_at"])
		for i in 4:
			var r := TankTargets.boss_rect(s, aux, i)
			var drawn := Rect2(
				Vector2(v.sx(r.position.x), v.sy(r.position.y)),
				Vector2(v.sx(r.end.x) - v.sx(r.position.x), v.sy(r.end.y) - v.sy(r.position.y))
			)
			var hit := br.position + br.size * TankKit.vec(at[i])
			assert_true(
				drawn.grow(2.0).has_point(hit),
				(
					"crew %d part %d: the view's hit at %s inside the rules box %s"
					% [crew, i, hit, drawn]
				)
			)
		var mz := TankTargets.boss_origin(s, aux) + aux.geo.boss_muzzle()
		var view_mz := br.position + v.boss_muzzle()
		assert_almost_eq(v.sx(mz.x), view_mz.x, 8.0, "crew %d: the main gun's end (x)" % crew)
		assert_almost_eq(v.sy(mz.y), view_mz.y, 4.0, "crew %d: the main gun's end (y)" % crew)


func test_wrecks_age_on_sim_time_into_debris_heaps() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	U.run(v, 2)
	var id := s.enemies[0].id
	s.enemies.remove_at(0)
	v.apply_cue(s, TankEvents.KILL, TankEvents.kill(id, 2, TankEvents.BY_SHELL, 0))
	assert_eq(v.wrecks.size(), 1)
	var w := v.wrecks[0]
	assert_eq(v.wreck_collapse(w), 0.0, "a burning hulk at first")
	assert_eq(v.wreck_fire(w), 1.0)
	# Frames without sim time change nothing.
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
	assert_eq(v.recoil, 1.0, "the barrel recoils")
	assert_gt(v.fx.flashes.size(), 0)
	assert_gt(v.fx.wash, 0.0, "the flash lights the scene")
	var tracers := v.fx.tracers.size()
	v.apply_cue(s, TankEvents.SHOT, TankEvents.shot(1, TankIds.SHELL_BOW, 17))
	assert_gt(v.fx.tracers.size(), tracers, "the bow guns throw tracers")
	assert_gt(v.fx.casings.size(), 0, "and brass")
	v.apply_cue(
		s,
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_TANK, 0, 12.0, TankIds.SHELL_ENEMY, 0.0, 3300.0)
	)
	assert_gt(v.shake, 0.0, "a hit shakes the hull")
	U.run(v, 3)
	assert_ne(v.origin, v.tank_pos, "the hull moves while it shakes")
	U.run(v, 120)
	assert_eq(v.origin, v.tank_pos, "and settles")


func test_the_evade_lurches_the_tank_or_blows_a_smoke_screen() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	var diesel := s.station(TankIds.ENGINE_DIESEL).slot
	var steam := s.station(TankIds.ENGINE_STEAM).slot
	v.apply_cue(s, TankEvents.EVADE, TankEvents.evade(13, 3, false))
	assert_eq(v.lurch_s, -1.0, "a missed evade does nothing")
	assert_eq(v.screen_s, -1.0)
	v.apply_cue(s, TankEvents.EVADE, TankEvents.evade(13, 3, true, diesel))
	assert_gte(v.lurch_s, 0.0, "the diesel's sprint lurches the tank")
	assert_eq(v.screen_s, -1.0, "no smoke screen for the diesel")
	U.run(v, 30)
	assert_gt(v.origin.x, v.tank_pos.x, "forward")
	U.run(v, 60)
	assert_eq(v.lurch_s, -1.0)
	var before := v.fx.smoke.size()
	v.apply_cue(s, TankEvents.EVADE, TankEvents.evade(13, 3, true, steam))
	assert_gte(v.screen_s, 0.0, "the steam engine's sprint blows a smoke screen")
	assert_eq(v.lurch_s, -1.0, "and does not lurch the tank")
	assert_gt(v.fx.smoke.size(), before + 15, "the boiler blows a smoke screen")
	assert_eq(v.evade_kind(s, -1), "lurch", "an unknown slot lurches")
	var solo := U.fixture("state", 1)
	assert_eq(v.evade_kind(solo, solo.stations[0].slot), "lurch", "the Bulwark lurches")


func test_the_barrel_swings_through_a_traverse_and_holds_its_elevation() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	s.hull.elev_deg = -12.0
	U.run(v, 1)
	assert_gt(v.barrel_vector().y, 0.0, "-12 degrees points down")
	s.hull.elev_deg = 30.0
	U.run(v, 1)
	assert_almost_eq(v.barrel_vector().angle(), -deg_to_rad(30.0), 0.001)
	s.hull.traverse_s = 2.0
	U.run(v, 1)
	s.hull.traverse_s = 1.0
	U.run(v, 1)
	assert_almost_eq(v.barrel_dir, 0.0, 0.01, "half way round the barrel points at the viewer")
	s.hull.traverse_s = 0.0
	s.hull.facing = TankIds.FACE_LEFT
	U.run(v, 1)
	assert_eq(v.barrel_dir, -1.0)
	assert_lt(v.muzzle().x, v.anchor("turret_pivot").x, "the muzzle faces the rear")


func test_a_breakdown_kills_the_lamps_and_the_crew_works_the_repair() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	s.hull.breakdown = true
	U.run(v, 10)
	var acts := v.crew.actors(v.kit.spec(v.variant), {"breakdown": true, "cad": v.cadences})
	var poses := {}
	for a in acts:
		poses[a["pose"]] = true
	assert_true(poses.has("engineer"))
	assert_false(poses.has("stoker"), "the stoker drops his shovel for a wrench")
	assert_false(poses.has("tech"))


func test_the_crew_follow_the_state() -> void:
	var v := U.view_of(self, U.fixture("state", 3))
	var spec := v.kit.spec(v.variant)
	var calm := v.crew.actors(spec, {"recoil": 0.0, "cad": {"steam": 90.0}})
	var fired := v.crew.actors(spec, {"recoil": 1.0, "cad": {"steam": 90.0}})
	var g0 := _pose(calm, "gunner")
	var g1 := _pose(fired, "gunner")
	assert_ne(g0["frame"], g1["frame"], "the gunner recoils with the shot")
	assert_lt((g1["at"] as Vector2).x, (g0["at"] as Vector2).x)
	assert_false(_pose(calm, "commander").is_empty(), "the commander on the turret roof")
	assert_false(_pose(calm, "stoker").is_empty(), "a stoker in the steam room")
	var solo := v.crew.actors(v.kit.spec("tank_1rider"), {"solo": true, "cad": {"diesel": 80.0}})
	assert_false(_pose(solo, "stoker").is_empty(), "the Bulwark's stoker at the diesel")


func test_the_halt_line_stands_ahead_in_an_advance() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	if s.seg.seg != TankIds.SEG_ADVANCE:
		pass_test("the fixture is not an Advance")
		return
	var hx := TankWorldDraw.halt_x(s)
	assert_false(is_nan(hx))
	assert_gt(v.sx(hx), v.anchor("headlight").x, "ahead of the tank")


func test_the_view_never_writes_the_state() -> void:
	for crew in [1, 4]:
		var s := U.fixture("gun_line", crew)
		var before := JSON.stringify(s.to_dict())
		var v := U.view_of(self, s)
		v.apply_cue(s, TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 15))
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


static func _pose(acts: Array[Dictionary], pose: String) -> Dictionary:
	for a in acts:
		if a["pose"] == pose:
			return a
	return {}


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
		var e := s.enemies[0]
		var r := g.enemy_rect(e)
		assert_eq(r.position, (v.enemy_rects[e.id] as Rect2).position + Vector2(0, v.y_off))
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
