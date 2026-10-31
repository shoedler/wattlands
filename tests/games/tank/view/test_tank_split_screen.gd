extends GutTest
## The v4 split screen (SPEC_TANK 4.1-4.6) from TankFixturesV4: the panels on every canvas, the far
## panel's SubViewport, far enemies and the Behemoth in metres, the shell's way across three surfaces
## from snapshot fields only, the shell screen and the seam.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
## SPEC_TANK 4.1: canvas, mirrored, near, seam, far, pip.
const LAYOUT := [
	[
		Vector2(960, 540),
		false,
		Rect2(0, 0, 622, 540),
		Rect2(622, 0, 8, 540),
		Rect2(630, 0, 330, 540),
		Rect2(707, 150, 176, 52)
	],
	[
		Vector2(852, 480),
		false,
		Rect2(0, 0, 558, 480),
		Rect2(558, 0, 8, 480),
		Rect2(566, 0, 286, 480),
		Rect2(621, 150, 176, 52)
	],
	[
		Vector2(1280, 680),
		false,
		Rect2(0, 0, 852, 680),
		Rect2(852, 0, 8, 680),
		Rect2(860, 0, 420, 680),
		Rect2(982, 150, 176, 52)
	],
	[
		Vector2(960, 540),
		true,
		Rect2(338, 0, 622, 540),
		Rect2(330, 0, 8, 540),
		Rect2(0, 0, 330, 540),
		Rect2(77, 150, 176, 52)
	],
]
const SIZES: Array[Vector2] = [Vector2(960, 540), Vector2(852, 480), Vector2(1280, 680)]

var _next_shell: int = 700


func _view(name: String, size: Vector2 = Vector2(960, 540), crew: int = 3) -> TankView:
	return U.view_of(self, TankFixturesV4.make(name, crew), Wl.SOLO, 1, size)


func _roam(size: Vector2 = Vector2(960, 540)) -> TankView:
	var g: TankGame = autofree(U.roam_game(TankFixturesV4.make("roam_west")))
	return U.make_view(self, g, size)


# --- Panels -------------------------------------------------------------------------------------------


func test_the_panels_match_the_spec_table_and_the_view_uses_them() -> void:
	for row: Array in LAYOUT:
		var p := TankFarMap.panels(row[0], row[1])
		assert_eq(p["near"], row[2], "near at %s" % row[0])
		assert_eq(p["seam"], row[3], "seam at %s" % row[0])
		assert_eq(p["far"], row[4], "far at %s" % row[0])
		assert_eq(p["pip"], row[5], "pip at %s" % row[0])
		if not bool(row[1]):
			var v := _view("far_duel", row[0])
			assert_eq(v.panels["far"], row[4])
			assert_eq(v.seam.rect, row[3])
			assert_eq(v.pip.rect, row[5])
			assert_eq(v.pip.position, (row[5] as Rect2).position)


func test_the_tank_stays_whole_and_at_its_scale_in_the_near_panel() -> void:
	for size in SIZES:
		var v := _view("far_duel", size)
		var near: Rect2 = v.panels["near"]
		assert_gte(v.tank_pos.x, near.position.x, "%s: its rear" % size)
		assert_lte(v.tank_pos.x + v.rig.size.x, near.end.x, "%s: its nose" % size)
		assert_almost_eq(v.xf.get_scale().x, 1.0, 0.001, "%s: scale untouched" % size)


func test_the_nodes_draw_in_the_spec_order_over_the_stage() -> void:
	var v := _view("far_duel")
	var order: Array[String] = []
	for c in v.get_children():
		if c is CanvasItem:
			order.append(c.name)
	assert_eq(order, ["Stage", "Dof", "FarSprite", "Seam", "Pip"] as Array[String])


func test_the_far_panel_is_an_opaque_subviewport_that_follows_the_canvas() -> void:
	var v := _view("far_duel")
	assert_true(v.far is SubViewport)
	assert_false(v.far.transparent_bg, "drawn opaque over the near stage")
	assert_eq(v.far.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	assert_eq(v.far.size, Vector2i(330, 540))
	v.set_canvas_size(Vector2(852, 480))
	v.advance(1.0 / 60.0)
	assert_eq(v.far.size, Vector2i(286, 480), "a flex canvas resizes it")
	for n: String in ["Back", "World", "Light"]:
		assert_not_null(v.far.layer(n), n)
	assert_eq(v.far.layer("World").scale.x, 1.0)


func test_the_depth_of_field_covers_only_the_near_panel() -> void:
	for size in SIZES:
		var v := _view("far_duel", size)
		assert_eq(v.dof.rect, v.panels["near"], "%s" % size)
	var west := _roam()
	assert_eq(west.dof.rect, Rect2(338, 0, 622, 540), "west: the near panel's on the right")
	var d: TankDof = autofree(TankDof.new())
	d.update(Vector2(100, 50), Vector2(1, 2))
	assert_eq(d.rect, Rect2(0, 0, 100, 50), "no rect: the whole canvas")


# --- The far field ------------------------------------------------------------------------------------


func test_far_enemies_stand_in_the_far_panel_and_near_ones_on_the_stage() -> void:
	var v := _view("cap_v4")
	var far_panel: Rect2 = v.panels["far"]
	var far_n := 0
	for e in v.game.state.enemies:
		if e.is_near():
			assert_true(v.enemy_rects.has(e.id), "near %d on the stage" % e.id)
			assert_false(v.far_rects.has(e.id))
			assert_true(v.lanes.has(e.id))
		else:
			far_n += 1
			assert_true(v.far_rects.has(e.id), "far %d in the panel" % e.id)
			assert_false(v.enemy_rects.has(e.id))
			assert_false(v.lanes.has(e.id))
			assert_true(far_panel.encloses(v.hud_enemy_rect(e.id)), "far %d whole" % e.id)
	assert_eq(far_n, 8)


func test_a_far_sprite_stands_where_range_and_lane_say_at_scale_one() -> void:
	var v := _view("far_duel")
	var fw := float(v.far.far_w)
	for e in v.game.state.enemies:
		var r: Rect2 = v.far.rects[e.id]
		var size: Vector2 = v.far.kit.kind(TankIds.enemy_of(e.code))["size"]
		assert_eq(r.size, size, "no perspective scale")
		var foot: Vector2 = v.far.feet[e.id]
		assert_eq(foot.y, TankFarMap.foot_y(e.range_m, e.lane))
		var x := TankFarMap.range_x(e.range_m, fw)
		assert_eq(foot.x, TankFarPanel.foot_x(e.range_m, size.x * 0.5, fw))
		assert_almost_eq(foot.x, x, size.x, "%d near its range's x" % e.id)
	var nearer: Rect2 = v.far.rects[22]
	var further: Rect2 = v.far.rects[23]
	assert_lt(nearer.get_center().x, further.get_center().x, "further is further from the seam")


func test_a_foot_keeps_its_sprite_whole() -> void:
	assert_eq(TankFarPanel.foot_x(700.0, 150.0, 330.0), 151.0, "no gun cut off at the near edge")
	assert_eq(TankFarPanel.foot_x(2600.0, 64.0, 330.0), 265.0, "nor a hull at the far edge")
	assert_eq(TankFarPanel.foot_x(1650.0, 48.0, 330.0), 165.0, "free in the middle")
	assert_eq(TankFarPanel.foot_x(1650.0, 200.0, 330.0), 165.0, "a wider sprite centred")


func test_haze_grows_with_range_and_an_entering_enemy_comes_out_of_the_night() -> void:
	assert_almost_eq(TankFarPanel.haze_at(700.0), 0.12, 0.001)
	assert_almost_eq(TankFarPanel.haze_at(2600.0), 0.5, 0.001)
	var s := TankFixturesV4.make("far_duel")
	var e := s.enemy(22)
	e.mode = TankIds.EM_ENTER
	e.range_m = 1500.0
	var v := U.view_of(self, s)
	var foot: Vector2 = v.far.feet[22]
	assert_almost_eq(float(v.far.pose_of(e, foot)["haze"]), 1.0, 0.05, "no pop-in")
	s.t += TankFarPanel.ENTER_S
	U.run(v, 1)
	assert_almost_eq(float(v.far.pose_of(e, foot)["haze"]), TankFarPanel.haze_at(1500.0), 0.01)


func test_an_old_frame_enemy_stands_at_the_near_end_without_error() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	for e in s.enemies:
		assert_eq(e.range_m, 0.0, "the old fixture")
		assert_true(v.far_rects.has(e.id))
		assert_eq(v.far_range_of(e), TankFarMap.RANGE_NEAR_M)


func test_a_far_range_interpolates_on_a_client() -> void:
	var s := TankFixturesV4.make("far_duel")
	var g := U.make_game(s, Wl.CLIENT, 2)
	autofree(g)
	var v := U.make_view(self, g)
	var e := s.enemy(21)
	e.range_m = 1600.0
	s.tick += 2
	s.t = s.tick * Wl.SIM_DT
	g.snapshot_applied.emit(s.tick)
	U.run(v, 6, 1.0 / 60.0, false)
	e.range_m = 1500.0
	s.tick += 2
	s.t = s.tick * Wl.SIM_DT
	g.snapshot_applied.emit(s.tick)
	U.run(v, 3, 1.0 / 60.0, false)
	assert_gt(v.far_range_of(e), 1500.0, "drawn a little behind the newest snapshot")


func test_tracks_run_with_the_range_and_with_the_hull() -> void:
	var v := _view("advance_far")
	var s := v.game.state
	var e := s.enemy(11)
	var t0 := float(v.far.pose_of(e, v.far.feet[11])["travel"])
	U.run(v, 10)
	var t1 := float(v.far.pose_of(e, v.far.feet[11])["travel"])
	assert_gt(t1, t0, "it paces the driving hull")
	s.hull.speed_mps = 0.0
	U.run(v, 2)
	var t2 := float(v.far.pose_of(e, v.far.feet[11])["travel"])
	U.run(v, 10)
	assert_almost_eq(float(v.far.pose_of(e, v.far.feet[11])["travel"]), t2, 0.001, "both at rest")


func test_the_pose_carries_the_kits_whole_contract() -> void:
	var v := _view("far_duel")
	var e := v.game.state.enemy(21)
	var pose := v.far.pose_of(e, v.far.feet[21])
	for k: String in [
		"travel",
		"turret_sx",
		"elev_deg",
		"recoil",
		"dim",
		"haze",
		"flash",
		"ground",
		"wrecked",
		"bogies_wrecked",
		"flip",
		"time"
	]:
		assert_true(pose.has(k), k)
	assert_gt(float(pose["elev_deg"]), 5.0, "the gun lays for its range")
	assert_gt(float(pose["flash"]), 0.0, "a telegraph tints it")
	var foot: Vector2 = v.far.feet[21]
	assert_almost_eq(
		(pose["ground"] as Callable).call(100.0), foot.y, 2.0, "the ground at its foot"
	)


func test_the_behemoth_stands_in_the_far_panel() -> void:
	for size in SIZES:
		var v := _view("boss_far", size)
		var box := v.hud_boss_rect()
		assert_eq(box.size, Vector2(300, 148), "%s: scale 1" % size)
		var panel: Rect2 = v.panels["far"]
		if panel.size.x >= box.size.x:
			assert_true(panel.encloses(box), "%s: whole" % size)
		else:
			assert_almost_eq(box.get_center().x, panel.get_center().x, 1.0, "%s: centred" % size)
		var mz := v.hud_boss_muzzle()
		assert_true(box.grow(1.0).has_point(mz), "%s: the main gun on the sprite" % size)
		for part in 4:
			assert_true(
				v.far.boss_box.has_point(v.far.boss_part_at(part)), "%s: part %d" % [size, part]
			)
	var v2 := _view("boss_far")
	var pose := v2.far.boss_pose(v2.game.state)
	assert_eq(pose["bogies_wrecked"], [false, false, true] as Array[bool])
	assert_gt(float(pose["flash"]), -0.01)
	assert_eq(v2.target_range_m(v2.game.state), 1100.0, "bogie 0's")


func test_cues_land_in_the_far_panel() -> void:
	var v := _view("far_duel")
	var s := v.game.state
	v.apply_cue(s, TankEvents.SPLASH, TankEvents.splash(1500.0, TankIds.SHELL_HEAVY, true))
	assert_eq(v.far.fx.booms.size(), 1, "ours lands over there")
	v.apply_cue(s, TankEvents.SPLASH, TankEvents.splash(60.0, TankIds.SHELL_ENEMY, false))
	assert_eq(v.fx.booms.size(), 1, "theirs falls on our road")
	var near: Rect2 = v.panels["near"]
	assert_true(near.has_point(v.fx.booms[0]["pos"] as Vector2), "inside the near panel")
	v.apply_cue(s, TankEvents.HIT, TankEvents.hit(TankEvents.ON_ENEMY, 21, 12.0, 2, 0.0, 1640.0))
	assert_eq(v.far.fx.booms.size(), 2, "a hit on a far enemy")
	assert_gt(v.far.shake, 0.0, "the far panel's own shake")
	assert_eq(v.firing.screen_shake(), Vector2i.ZERO, "and not the near stage's")
	v.apply_cue(
		s, TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_ENEMY, 40, 21, 3, 3.0, 1640.0)
	)
	assert_eq(v.far.fx.flashes.size(), 1, "their muzzle flash")
	assert_gt(float(v.far.pose_of(s.enemy(21), v.far.feet[21])["recoil"]), 0.0, "and recoil")
	assert_lt(TankEnemyDraw.muzzle(v.far.kit, "heavy", v.far.feet[21], {"turret_sx": 1.0}).x, 400.0)


func test_a_killed_far_enemy_leaves_a_wreck_at_its_range() -> void:
	var v := _view("far_duel")
	var s := v.game.state
	var e := s.enemy(22)
	var r0 := v.far_range_of(e)
	s.enemies.erase(e)
	v.apply_cue(s, TankEvents.KILL, TankEvents.kill(22, e.code, TankEvents.BY_SHELL, 0))
	assert_eq(v.far.wrecks.size(), 1)
	assert_eq(v.wrecks.size(), 0, "not on the near stage")
	var w := v.far.wrecks[0]
	assert_eq(float(w["range"]), r0)
	assert_eq(str(w["kind"]), TankIds.ENEMY_MEDIUM)
	assert_eq(v.far.wreck_fire(w, s.t), 1.0)
	U.run(v, 2)
	assert_false(v.far_rects.has(22), "the live sprite is gone")
	s.t += TankView.WRECK_BURN_S
	assert_eq(v.far.wreck_fire(w, s.t), 0.0, "the fire dies on sim time")
	s.t += TankView.WRECK_GONE_S
	U.run(v, 1)
	assert_eq(v.far.wrecks.size(), 0, "gone in the end")
	var stray := v.far.on_kill(s, 999)
	assert_false(stray, "never stood here")


func test_a_boss_kill_and_hits_stay_in_the_far_panel() -> void:
	var v := _view("boss_far")
	var s := v.game.state
	v.apply_cue(s, TankEvents.HIT, TankEvents.hit(TankEvents.ON_BOSS, -1, 12.0, 2, 0.0, 1100.0))
	assert_eq(v.far.fx.booms.size(), 1)
	assert_eq(v.fx.booms.size(), 0)
	v.apply_cue(s, TankEvents.KILL, TankEvents.kill(0, TankIds.BOSS_CODE, TankEvents.BY_SHELL, 0))
	assert_gt(v.far.fx.booms.size(), 3)
	assert_eq(v.fx.booms.size(), 0)


# --- The shell across three surfaces ------------------------------------------------------------------


## A shell from or to `range_m`, `left_s` before it lands, as TankFixturesV4 flies them. A new id each,
## as the rules give: the view's history keys on it.
func _flying(friendly: bool, range_m: float, left_s: float) -> TankShellState:
	var type := TankIds.SHELL_HEAVY if friendly else TankIds.SHELL_ENEMY
	_next_shell += 1
	return TankFixturesV4._far_shell(_next_shell, type, friendly, range_m, left_s)


func test_the_flight_comes_from_snapshot_fields() -> void:
	var elev := TankBallistics.far_elevation(1500.0, 560.0, 70.0)
	var flight := TankBallistics.far_flight(elev, 560.0, 70.0)
	for left: float in [flight, 1.2, 0.2]:
		var s := _flying(true, 1500.0, left)
		assert_almost_eq(TankShellPath.flight_s(s.left_s, s.vy, 70.0), flight, 0.001, "our flight")
		var age := TankShellPath.age_s(s.left_s, s.vy, 70.0)
		assert_almost_eq(age, flight - left, 0.001, "our age")
		assert_almost_eq(TankShellPath.launch_m(s.x, s.vx, age), 0.0, 0.01, "from the hull")
		var theirs := _flying(false, 1500.0, left)
		var a2 := TankShellPath.age_s(theirs.left_s, theirs.vy, 70.0)
		assert_almost_eq(TankShellPath.launch_m(theirs.x, theirs.vx, a2), 1500.0, 0.01, "from it")
	assert_eq(TankShellPath.leave_k(0.0), 0.0)
	assert_almost_eq(TankShellPath.leave_k(0.15), 0.5, 0.001)
	assert_eq(TankShellPath.leave_k(0.3), -1.0)
	assert_eq(TankShellPath.arrive_k(0.4), -1.0)
	assert_almost_eq(TankShellPath.arrive_k(0.175), 0.5, 0.001)


func test_our_shell_lands_at_x_plus_vx_left_on_a_client_with_no_impact_r() -> void:
	var s := TankFixturesV4.make("advance_far")
	var shell := s.shells[0]
	shell.impact_r = 0.0
	assert_almost_eq(TankShellPath.landing_m(shell.x, shell.vx, shell.left_s), 1220.0, 0.5)
	s.shells.clear()
	var low := _flying(true, 1220.0, 0.05)
	low.impact_r = 0.0
	s.shells.append(low)
	var g := U.make_game(s, Wl.CLIENT, 2)
	autofree(g)
	var v := U.make_view(self, g)
	var rows := v.far.shells_drawn(s)
	assert_eq(rows.size(), 1, "on the far panel for its last moments")
	var want := TankFarMap.range_x(1220.0, v.far.far_w) * TankShellPath.arrive_k(0.05)
	var at: Vector2 = rows[0]["at"]
	assert_almost_eq(at.x, want, 1.0, "dropping onto the range, not the panel's edge")
	assert_gt(at.x, 60.0)


func test_our_shell_shows_on_each_surface_in_its_time() -> void:
	var s := TankFixturesV4.make("advance_far")
	s.shells.clear()
	var elev := TankBallistics.far_elevation(1220.0, 560.0, 70.0)
	var flight := TankBallistics.far_flight(elev, 560.0, 70.0)
	var shell := _flying(true, 1220.0, flight - 0.1)
	s.shells.append(shell)
	var v := U.view_of(self, s)
	var near := v.shells_drawn(s)
	assert_eq(near.size(), 1, "leaving the near panel")
	assert_gt((near[0]["at"] as Vector2).x, v.muzzle().x - 2.0, "from the muzzle")
	assert_lte((near[0]["at"] as Vector2).x, TankFarMap.near_end_x(v.canvas.x) + 8.0)
	assert_eq(v.far.shells_drawn(s).size(), 0, "not on the far panel yet")
	assert_eq(v.pip.dots(s).size(), 1, "on the PiP all flight")
	for r in [shell]:
		s.shells.erase(r)
	var mid := _flying(true, 1220.0, 1.0)
	s.shells.append(mid)
	U.run(v, 1)
	assert_eq(v.shells_drawn(s).size(), 0, "mid flight: on the PiP only")
	assert_eq(v.far.shells_drawn(s).size(), 0)
	assert_eq(v.pip.dots(s).size(), 1)


func test_their_shell_shows_on_each_surface_in_its_time() -> void:
	var s := TankFixturesV4.make("far_duel")
	s.shells.clear()
	var elev := TankBallistics.far_elevation(1640.0, 560.0, 70.0)
	var flight := TankBallistics.far_flight(elev, 560.0, 70.0)
	var early := _flying(false, 1640.0, flight - 0.1)
	s.shells.append(early)
	var v := U.view_of(self, s)
	assert_eq(v.shells_drawn(s).size(), 0, "not here yet")
	var rows := v.far.shells_drawn(s)
	assert_eq(rows.size(), 1, "leaving the far panel")
	assert_lt((rows[0]["at"] as Vector2).x, v.far.rects[21].get_center().x, "toward the seam")
	s.shells.clear()
	var late := _flying(false, 1640.0, 0.175)
	late.will_hit = true
	s.shells.append(late)
	U.run(v, 1)
	assert_eq(v.far.shells_drawn(s).size(), 0)
	var near := v.shells_drawn(s)
	assert_eq(near.size(), 1, "arriving on the near panel")
	var at: Vector2 = near[0]["at"]
	var edge := TankFarMap.near_end_x(v.canvas.x)
	assert_lt(at.x, edge + 8.0, "in from the near edge")
	assert_gt(at.x, v.tank_pos.x + v.headlight_x() - 40.0, "half way to the tank's front")
	late.will_hit = false
	late.left_s = 0.001
	U.run(v, 1)
	var miss := v.shells_drawn(s)
	if not miss.is_empty():
		var hit: Vector2 = miss[0]["at"]
		assert_gt(hit.x, v.tank_pos.x + v.headlight_x(), "a miss falls on the road ahead")


func test_near_shells_keep_their_old_path() -> void:
	var s := TankFixturesV4.make("cap_v4")
	var v := U.view_of(self, s)
	var near := 0
	for sh in s.shells:
		near += int(not sh.far)
	assert_gte(v.shells_drawn(s).size(), near, "the bow rounds still fly the stage")


# --- The shell screen ---------------------------------------------------------------------------------


func test_the_pip_maps_range_and_height_as_the_spec_says() -> void:
	var size := Vector2(318, 60)
	assert_eq(TankPip.to_px(0.0, 0.0, size, false), Vector2(10, 51), "the hull on the left")
	assert_eq(TankPip.to_px(2600.0, 0.0, size, false), Vector2(308, 51))
	assert_eq(TankPip.to_px(2600.0, 0.0, size, true), Vector2(10, 51), "mirrored")
	assert_eq(TankPip.to_px(0.0, 0.0, size, true), Vector2(308, 51))
	assert_eq(TankPip.to_px(1200.0, 174.0, size, false).y, 16.0, "174 m is 35 px up")


func test_the_pip_shows_each_far_shell_on_its_arc() -> void:
	var v := _view("far_duel")
	var s := v.game.state
	var dots := v.pip.dots(s)
	assert_eq(dots.size(), 1)
	var d := dots[0]
	assert_false(bool(d["friendly"]))
	assert_true(bool(d["evadable"]), "theirs, Surge can still make it miss")
	assert_true(Rect2(Vector2.ZERO, v.pip.rect.size).has_point(d["p"]), "on the plate")
	var arc: PackedVector2Array = d["arc"]
	assert_gt(arc.size(), 10, "predicted dashes")
	var first := arc[0]
	var last := arc[arc.size() - 1]
	var hull_x := TankPip.to_px(0.0, 0.0, v.pip.rect.size, false).x
	assert_almost_eq(last.x, hull_x, 1.0, "it lands on us")
	assert_gt(first.x, last.x, "it comes from the far side")
	var top := INF
	for q in arc:
		top = minf(top, q.y)
	assert_lt(top, first.y - 10.0, "it arcs")


func test_the_pip_skips_near_shells_and_mirrors_going_west() -> void:
	var cap := _view("cap_v4")
	assert_eq(cap.pip.dots(cap.game.state).size(), 12, "only the far ones")
	var s := TankFixturesV4.make("roam_west")
	s.shells.append(_flying(true, 1300.0, 2.0))
	var g: TankGame = autofree(U.roam_game(s))
	var v := U.make_view(self, g)
	var d := v.pip.dots(s)[0]
	var arc: PackedVector2Array = d["arc"]
	assert_gt(arc[0].x, arc[arc.size() - 1].x, "ours flies right to left on a mirrored plate")


func test_the_pip_is_a_little_screen_inside_the_far_panel() -> void:
	for row: Array in LAYOUT:
		var p := TankFarMap.panels(row[0], row[1])
		var pip: Rect2 = p["pip"]
		assert_lte(pip.size.x, 180.0, "%s: small" % row[0])
		assert_true((p["far"] as Rect2).encloses(pip), "%s: inside the far panel" % row[0])


func test_a_tracer_trails_along_its_arc_behind_its_head() -> void:
	var s := TankFixturesV4.make("far_duel")
	s.shells.clear()
	s.shells.append(_flying(true, 1300.0, 1.0))
	var v := U.view_of(self, s, Wl.SOLO, 1, Vector2(960, 540))
	var d := v.pip.dots(s)[0]
	var trail: PackedVector2Array = d["trail"]
	assert_gt(trail.size(), 3, "a trail")
	var p: Vector2 = d["p"]
	assert_lt(trail[trail.size() - 1].x, p.x, "ours: the trail runs back toward the hull")
	assert_gte(p.x, trail[0].x, "the head leads")


func test_the_pip_says_how_long_a_shell_has_left() -> void:
	assert_eq(TankPip.flight_label(2.44), "2.4 S")
	assert_eq(TankPip.flight_label(-0.1), "0.0 S")
	var s := TankFixturesV4.make("far_duel")
	s.shells.clear()
	s.shells.append(_flying(true, 1300.0, 1.5))
	var v := U.view_of(self, s, Wl.SOLO, 1, Vector2(960, 540))
	assert_almost_eq(float(v.pip.dots(s)[0]["left"]), 1.5, 0.001)


func test_the_gun_arc_shows_while_nothing_flies() -> void:
	var v := _view("far_duel")
	var arc := v.pip.aim_arc(1640.0)
	assert_gt(arc.size(), 5, "an arc to the target")
	var top := INF
	for q in arc:
		top = minf(top, q.y)
	assert_lt(top, arc[0].y - 3.0, "it rises")
	assert_almost_eq(
		arc[0].x, TankPip.to_px(0.0, 0.0, v.pip.rect.size, false).x, 1.0, "from the hull"
	)
	assert_eq(v.pip.aim_arc(0.0).size(), 0, "no target, no arc")
	assert_eq(v.pip.aim_arc(99999.0).size(), 0, "out of the gun's reach")


func test_a_landing_shell_leaves_a_puff_that_fades() -> void:
	var s := TankFixturesV4.make("far_duel")
	s.shells.clear()
	var shell := _flying(true, 1300.0, 0.2)
	s.shells.append(shell)
	var v := U.view_of(self, s, Wl.SOLO, 1, Vector2(960, 540))
	v.pip.puffs.clear()
	v.pip.frame(s, 0.05)
	assert_eq(v.pip.puffs.size(), 0, "still flying")
	var land := TankShellPath.landing_m(shell.x, shell.vx, shell.left_s)
	s.shells.clear()
	v.pip.frame(s, 0.05)
	assert_eq(v.pip.puffs.size(), 1, "gone near its end: it landed")
	assert_almost_eq(float(v.pip.puffs[0]["r"]), land, 0.01, "where it was going to land")
	assert_true(bool(v.pip.puffs[0]["friendly"]))
	v.pip.frame(s, TankPip.PUFF_S)
	assert_eq(v.pip.puffs.size(), 0, "faded")


func test_a_cleared_field_leaves_no_puff() -> void:
	var s := TankFixturesV4.make("far_duel")
	s.shells.clear()
	s.shells.append(_flying(false, 1300.0, 2.0))
	var v := U.view_of(self, s, Wl.SOLO, 1, Vector2(960, 540))
	v.pip.frame(s, 0.05)
	s.shells.clear()
	v.pip.frame(s, 0.05)
	assert_eq(v.pip.puffs.size(), 0, "mid flight: a tow or a new stage took it, nothing landed")


func test_the_target_range_labels_the_pip_and_the_seam() -> void:
	assert_eq(TankPip.range_label(1640.4), "1640 M")
	assert_eq(TankPip.range_label(0.0), "--")
	var v := _view("far_duel")
	assert_eq(v.target_range_m(v.game.state), 1640.0)
	v.game.state.hull.target_id = 0
	assert_eq(v.target_range_m(v.game.state), 0.0, "no target")
	v.game.state.hull.target_id = 9999
	assert_eq(v.target_range_m(v.game.state), 0.0, "a barricade")


# --- The back ------------------------------------------------------------------------------------------


func test_the_far_panel_has_a_treeline_in_three_walls() -> void:
	var kit := TankEnemyKit.shared()
	assert_not_null(kit.far_forest(), "the baked treeline")
	assert_eq(kit.far_forest_rects().size(), TankFarPanel.FOREST_FOOT.size(), "one foot per wall")
	var last := -INF
	for foot: float in TankFarPanel.FOREST_FOOT:
		assert_gt(foot, last, "the nearer wall stands lower")
		last = foot
	assert_lte(
		last, TankFarPanel.GROUND_TOP + 14.0, "the ground's soft top covers the last wall's foot"
	)


func test_a_base_stands_behind_the_enemies_and_its_lamps_too() -> void:
	var v := _view("far_duel")
	var world := v.far.layer("World").get_index()
	assert_lt(v.far.layer("Base").get_index(), world, "the base under the enemies")
	assert_lt(v.far.layer("BaseLight").get_index(), world, "its lamps never shine through a hull")
	assert_gt(v.far.layer("BaseLight").get_index(), v.far.layer("Base").get_index())


# --- The seam -----------------------------------------------------------------------------------------


func test_the_range_plate_is_centred_on_the_seam_below_the_pip() -> void:
	for size in SIZES:
		var v := _view("far_duel", size)
		var p := v.seam.plate_rect()
		assert_eq(p.size, Vector2(46, 14))
		assert_almost_eq(p.get_center().x, v.seam.rect.get_center().x, 1.0, "%s" % size)
		assert_false(p.intersects(v.pip.rect), "%s: clear of the PiP" % size)
	assert_eq(_view("far_duel").seam.plate_rect().position, Vector2(603, 216))


# --- Free roam west -----------------------------------------------------------------------------------


func test_going_west_the_far_panel_is_on_the_left_and_the_tank_on_the_right() -> void:
	var v := _roam()
	assert_true(v.mirrored)
	assert_eq(v.panels["far"], Rect2(0, 0, 330, 540))
	assert_gt(v.hud_tank_point("rear").x, 480.0, "the tank on the right")
	assert_eq(v.far.layer("World").scale.x, -1.0, "the far world mirrors inside the panel")
	assert_eq(v.far.layer("World").position.x, 330.0)
	assert_eq(v.far.layer("Light").scale.x, -1.0)
	assert_eq(v.far.layer("Back").scale.x, 1.0, "the planes never mirror")
	var panel: Rect2 = v.panels["far"]
	var r := v.hud_enemy_rect(301)
	assert_true(panel.encloses(r), "a far rect in canvas px, not mirrored twice")
	var east := U.view_of(self, TankFixturesV4.make("far_duel"))
	east.game.state.enemies.clear()
	var inner: Rect2 = v.far.rects[301]
	assert_eq(r.end.x, 330.0 - inner.position.x, "further from the seam means further left")


func test_every_fixture_draws_the_split_screen_at_every_canvas() -> void:
	for n in TankFixturesV4.NAMES:
		for size in SIZES:
			var s := TankFixturesV4.make(n)
			var g: TankGame = autofree(
				U.roam_game(s) if TankFixturesV4.content_id(n) == "roam_30" else U.make_game(s)
			)
			var v := U.make_view(self, g, size)
			for _i in 4:
				TankFixturesV4.tick(s, Wl.SIM_DT)
				v.advance(Wl.SIM_DT)
			assert_eq(v.far.size.y, int(size.y), "%s at %s" % [n, size])
			v.queue_free()
	await wait_physics_frames(2)


func test_the_split_screen_never_writes_the_state() -> void:
	var s := TankFixturesV4.make("far_duel")
	var before := JSON.stringify(s.to_dict())
	var v := U.view_of(self, s)
	U.run(v, 30, 1.0 / 60.0, false)
	v.apply_cue(s, TankEvents.SPLASH, TankEvents.splash(1500.0, TankIds.SHELL_HEAVY, true))
	U.run(v, 3, 1.0 / 60.0, false)
	assert_eq(JSON.stringify(s.to_dict()), before)
