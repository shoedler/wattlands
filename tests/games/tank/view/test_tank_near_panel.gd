extends GutTest
## The v4 near panel (SPEC_TANK 4.7, 4.8): the near threats in their two lanes with their turrets back at
## us, the roadside bushes, the leaf burst, a tank lost and towed, the restart's fade, the Repairs room's lamp
## and press, and all of it mirrored going west.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const SIZES: Array[Vector2] = [Vector2(960, 540), Vector2(852, 480), Vector2(1280, 680)]


func _view(name: String, size: Vector2 = Vector2(960, 540), crew: int = 3) -> TankView:
	return U.view_of(self, TankFixturesV4.make(name, crew), Wl.SOLO, 1, size)


func _roam(size: Vector2 = Vector2(960, 540)) -> TankView:
	var g: TankGame = autofree(U.roam_game(TankFixturesV4.make("roam_west")))
	return U.make_view(self, g, size)


# --- Near threats -------------------------------------------------------------------------------------


func test_near_threats_stand_inside_the_near_panel_on_every_canvas() -> void:
	for size in SIZES:
		var v := _view("near_ambush", size)
		var s := v.game.state
		var edge := TankFarMap.near_end_x(size.x)
		for e in s.enemies:
			var foot: Vector2 = v.enemy_feet[e.id]
			assert_gt(
				foot.x, v.tank_pos.x + v.headlight_x(), "%s: %d ahead of the nose" % [size, e.id]
			)
			assert_lt(foot.x, edge, "%s: %d this side of the seam" % [size, e.id])


func test_a_flight_ends_behind_the_far_panel() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	var e := s.enemy(42)
	e.x_px = s.hull.x_px + float(s.hull.hull_w) + TankConst.NEAR_SPAN_PX + 20.0
	U.run(v, 12)
	var r: Rect2 = v.enemy_rects[e.id]
	assert_gt(r.get_center().x, TankFarMap.near_end_x(960.0) - 6.0, "gone past the road's end")


func test_a_near_threat_runs_with_its_turret_back_at_us() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	for e in s.enemies:
		var pose := v.near_pose(e)
		assert_eq(float(pose["turret_sx"]), -1.0, "traversed back")
		assert_false(bool(pose["flip"]), "its hull faces away")
		assert_gt(float(pose["elev_deg"]), 0.0, "laid up at the hull")
		assert_lte(float(pose["elev_deg"]), TankView.NEAR_ELEV_MAX)
		var foot: Vector2 = v.enemy_feet[e.id]
		var g: Callable = pose["ground"]
		assert_almost_eq(float(g.call(foot.x)), foot.y, 0.01, "the ground under its foot")
		assert_lt(v.near_muzzle(e).x, foot.x, "its gun points back at the tank")
		assert_eq(v.enemy_kit.kind(v.enemy_kind(e))["faces"], 1, "near kinds face away")
	var far_pose := v.near_pose(s.enemy(41))
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
		assert_true(far_pose.has(k), k)


func test_a_near_threats_tracks_run_with_its_own_speed() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	var e := s.enemy(41)
	var t0 := float(v.near_pose(e)["travel"])
	U.run(v, 6)
	assert_eq(float(v.near_pose(e)["travel"]), t0, "at rest")
	e.x_px += 10.0
	U.run(v, 30)
	assert_almost_eq(float(v.near_pose(e)["travel"]), t0 + 10.0 * TankView.S, 0.5, "as it moved")


func test_its_shot_kicks_the_gun_and_flashes_at_the_muzzle() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	var e := s.enemy(41)
	var mz := v.near_muzzle(e)
	v.apply_cue(s, TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_ENEMY, 80, 41))
	assert_gt(float(v.near_pose(e)["recoil"]), 0.0, "recoil")
	assert_eq(v.fx.flashes.size(), 1, "a flash")
	assert_lte((v.fx.flashes[0]["pos"] as Vector2).distance_to(mz), 3.0, "at its muzzle")
	assert_eq(v.far.fx.flashes.size(), 0, "not in the far panel")
	U.run(v, 30)
	assert_eq(float(v.near_pose(e)["recoil"]), 0.0, "and back")


func test_its_round_leaves_from_its_gun() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	var e := s.enemy(41)
	var shell := TankShellState.new()
	shell.id = 90
	shell.type = TankIds.SHELL_ENEMY
	shell.source = e.id
	shell.friendly = false
	shell.x = e.x_px + float(e.w) * 0.25
	shell.y = float(TankConst.GROUND_Y) - float(e.h) * 0.8
	shell.vx = -120.0
	s.shells.append(shell)
	var rows := v.shells_drawn(s)
	assert_eq(rows.size(), 1)
	assert_lte((rows[0]["at"] as Vector2).distance_to(v.near_muzzle(e)), 1.0)


func test_they_puff_exhaust() -> void:
	var v := _view("near_ambush")
	var n := v.fx.smoke.size()
	for _i in 60:
		v._emit_near(v.game.state, 1.0 / 60.0)
	assert_gte(v.fx.smoke.size(), n + 4, "2.5 a second from each of two")
	var bare := _view("restart")
	var m := bare.fx.smoke.size()
	bare._emit_near(bare.game.state, 2.0)
	assert_eq(bare.fx.smoke.size(), m, "none without them")


func test_the_bow_guns_lay_on_the_nearest_near_threat() -> void:
	var v := _view("bow_duel")
	U.run(v, 2)
	assert_ne(v.bow_target, Vector2.ZERO)
	var nearest: Rect2 = v.enemy_rects[42]
	assert_almost_eq(v.bow_target.x, nearest.get_center().x, 1.0, "the tankette, 25 px out")
	var far_only := _view("far_duel")
	U.run(far_only, 2)
	assert_eq(far_only.bow_target, Vector2.ZERO, "a far enemy is no bow target")


func test_a_killed_near_threat_leaves_a_wreck_in_its_lane_on_the_kits_size() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	var e := s.enemy(41)
	var foot: Vector2 = v.enemy_feet[41]
	s.enemies.erase(e)
	v.apply_cue(s, TankEvents.KILL, TankEvents.kill(41, e.code, TankEvents.BY_BOW, 0))
	assert_eq(v.wrecks.size(), 1)
	var w := v.wrecks[0]
	assert_eq(str(w["kind"]), TankIds.ENEMY_RECON)
	assert_eq(int(w["lane"]), e.lane)
	assert_false(w.has("side"), "nothing behind the tank")
	var r := TankWorldDraw.wreck_rect(v, w)
	assert_eq(r.size, v.enemy_kit.kind(TankIds.ENEMY_RECON)["size"])
	assert_almost_eq(r.get_center().x, foot.x, 1.0, "where it died")
	assert_eq(v.far.wrecks.size(), 0, "not in the far panel")
	U.run(v, 2)
	assert_false(v.enemy_rects.has(41))


# --- The bushes ---------------------------------------------------------------------------------------


func test_bushes_stand_90_to_160_rules_px_apart_by_hash() -> void:
	var prev := TankWorldDraw.bush_x(-20)
	for n in range(-19, 200):
		var x := TankWorldDraw.bush_x(n)
		assert_gte(x - prev, 90.0, "gap before %d" % n)
		assert_lte(x - prev, 160.0, "gap before %d" % n)
		assert_eq(TankWorldDraw.bush_x(n), x, "the same bush every time")
		prev = x


func test_the_near_panel_has_bushes_that_stay_where_they_stand_on_the_road() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	var at := TankWorldDraw.bushes_at(v)
	var edge := TankFarMap.near_end_x(960.0)
	var ahead := 0
	for b in at:
		assert_lt(float(b["x"]), edge + 80.0, "none far past the seam")
		if float(b["x"]) > v.tank_pos.x + v.headlight_x() and float(b["x"]) < edge:
			ahead += 1
	assert_gte(ahead, 1, "at least one on the road ahead, for the threats to burst from")
	var last := int(at[at.size() - 1]["n"])
	var x0 := v.sx(TankWorldDraw.bush_x(last))
	s.hull.x_px += 10.0
	U.run(v, 12)
	assert_lt(v.sx(TankWorldDraw.bush_x(last)), x0, "they pass as the hull drives")


func test_an_ambush_throws_leaves_at_the_enemy_even_before_it_is_tracked() -> void:
	var v := _view("restart")
	var s := v.game.state
	var e := TankFixturesV4._near(s, 500, TankIds.ENEMY_RECON, 30.0, 1)
	assert_false(v.enemy_feet.has(e.id))
	v.apply_cue(s, TankEvents.AMBUSH, TankEvents.ambush(e.id, e.code))
	assert_eq(v.fx.sparks.size(), TankView.LEAF_BURST)
	var at: Vector2 = v.fx.sparks[0]["pos"]
	assert_almost_eq(at.x, v.near_foot(e).x, 1.0)
	assert_eq(v.fx.sparks[0]["c"], TankView.LEAF, "green-brown")
	v.fx.sparks.clear()
	v.apply_cue(s, TankEvents.AMBUSH, TankEvents.ambush(9999, e.code))
	assert_eq(v.fx.sparks.size(), 0, "an enemy already gone: nothing")


# --- A tank lost --------------------------------------------------------------------------------------


func test_tank_lost_booms_and_dims_for_a_moment() -> void:
	var v := _view("tank_lost")
	var s := v.game.state
	v.apply_cue(s, TankEvents.TANK_LOST, TankEvents.tank_lost(1, TankIds.SEG_ADVANCE, 2))
	assert_gt(v.fx.booms.size(), 0, "a boom")
	assert_eq(v.tow_dim_s, TankView.TOW_DIM_S, "the dim")
	assert_gt(v.shake, 0.0)
	U.run(v, 30, 1.0 / 60.0, false)
	assert_eq(v.tow_dim_s, 0.0, "over in 0.4 s")


func test_the_tow_draws_the_tank_back_with_its_tracks_reversed_under_smoke() -> void:
	var v := _view("tank_lost")
	var s := v.game.state
	var x0 := v.xf.origin.x
	var t0 := v.travel
	U.run(v, 120)
	assert_almost_eq(x0 - v.xf.origin.x, 2.0 * TankView.TOW_PX_S, 1.0, "12 art px/s")
	assert_almost_eq(t0 - v.travel, 2.0 * TankView.TOW_PX_S, 1.0, "the tracks run backward")
	assert_gt(v.fx.smoke.size(), 8, "heavy smoke")
	assert_eq(v.tank_pos, TankView.TANK_AT, "cosmetic: its rest place does not move")
	s.hull.tow_s = 0.0
	U.run(v, 1)
	assert_eq(v.tow_px, 0.0, "back with the tow over")


func test_the_tow_never_draws_the_tank_past_its_limit() -> void:
	var v := _view("tank_lost")
	for _i in 12:
		U.run(v, 60)
		v.game.state.hull.tow_s = 5.0
	assert_eq(v.tow_px, TankView.TOW_MAX_PX)


func test_the_far_panel_goes_black_during_the_tow_and_comes_back_at_the_restart() -> void:
	var v := _view("tank_lost")
	var s := v.game.state
	assert_gt(v.far.veil, 0.0, "starting")
	U.run(v, 70)
	assert_eq(v.far.veil, 1.0, "black within a second")
	assert_not_null(v.far.layer("Veil"), "over the rest")
	assert_eq(v.far.layer("Veil").get_index(), v.far.layer("Light").get_index() + 1, "last")
	s.hull.tow_s = 0.0
	v.apply_cue(s, TankEvents.STAGE_RESTART, TankEvents.stage_restart(TankIds.SEG_ADVANCE, 2, 84.0))
	U.run(v, 12)
	assert_gt(v.far.veil, 0.0, "fading")
	assert_lt(v.far.veil, 1.0)
	U.run(v, 24)
	assert_eq(v.far.veil, 0.0, "up in 0.5 s")


func test_the_restart_forgets_the_road_and_fades_up_from_black() -> void:
	var v := _view("near_ambush")
	var s := v.game.state
	var e := s.enemy(41)
	s.enemies.erase(e)
	v.apply_cue(s, TankEvents.KILL, TankEvents.kill(41, e.code, TankEvents.BY_BOW, 0))
	v.far.wrecks.append({"range": 1000.0, "lane": 0, "kind": "medium", "t": s.t})
	var before := v.travel
	s.enemies.clear()
	s.hull.x_px = 0.0
	v.apply_cue(s, TankEvents.STAGE_RESTART, TankEvents.stage_restart(TankIds.SEG_ADVANCE, 2, 84.0))
	assert_eq(v.restart_fade_s, TankView.RESTART_FADE_S)
	assert_true(v.history.is_empty(), "the old road forgotten")
	assert_false(v.clock.is_set())
	assert_eq(v.wrecks.size(), 0)
	assert_eq(v.far.wrecks.size(), 0)
	U.run(v, 3)
	assert_almost_eq(v.hull_x, 0.0, 0.01, "drawn at the start at once, no sweep back")
	assert_eq(v.scroll_px, 0.0, "the jump is no scroll")
	assert_gte(v.travel, before, "the tracks keep their place")
	assert_gt(v.restart_fade_s, 0.0)
	U.run(v, 40)
	assert_eq(v.restart_fade_s, 0.0)


func test_a_client_that_joins_mid_tow_sees_it_from_the_snapshot() -> void:
	var s := TankFixturesV4.make("tank_lost")
	var g := U.make_game(s, Wl.CLIENT, 2)
	autofree(g)
	var v := U.make_view(self, g)
	U.run(v, 30, 1.0 / 60.0, false)
	assert_gt(v.tow_px, 0.0, "the tow reads hull.tow_s, not the cue")
	assert_gt(v.far.veil, 0.0)


func test_the_tow_never_writes_the_state() -> void:
	var s := TankFixturesV4.make("tank_lost")
	var before := JSON.stringify(s.to_dict())
	var v := U.view_of(self, s)
	v.apply_cue(s, TankEvents.TANK_LOST, TankEvents.tank_lost(1, TankIds.SEG_ADVANCE, 2))
	U.run(v, 30, 1.0 / 60.0, false)
	v.apply_cue(s, TankEvents.STAGE_RESTART, TankEvents.stage_restart(TankIds.SEG_ADVANCE, 2, 84.0))
	U.run(v, 3, 1.0 / 60.0, false)
	assert_eq(JSON.stringify(s.to_dict()), before)


# --- The Repairs room ---------------------------------------------------------------------------------


func test_the_repairs_seat_has_its_rider_and_its_machine_turns_on_their_cadence() -> void:
	var v := _view("repair")
	var s := v.game.state
	var r := v.rider_on("repair")
	assert_not_null(r, "manned")
	assert_eq(r, s.rider_at(s.station(TankIds.ENGINE_REPAIR).slot))
	r.cadence_rpm = 90.0
	U.run(v, 60)
	var p0 := v.machine_phase("repair")
	U.run(v, 60)
	assert_almost_eq(v.machine_phase("repair") - p0, 1.5, 0.2, "90 rpm for 1 s")
	assert_true(v.audio_feed(s).has("repair"), "the audio reads the same phase")


func test_the_repairs_room_lamp_follows_its_rider() -> void:
	var v := _view("repair")
	assert_eq(TankLightDraw.room_rider(v, "turret_drive"), v.rider_on("repair"))
	assert_null(TankLightDraw.room_rider(v, "quarters"), "a room no seat works")
	assert_eq(TankLightDraw.room_rider(v, "gun"), v.rider_on("gun"))
	assert_true("turret_drive" in TankLightDraw.GLOW_ROOMS)
	assert_ne(TankLightDraw.REPAIR_LAMP, TankLightDraw.WARM, "its own colour")
	assert_ne(TankLightDraw.REPAIR_LAMP, TankLightDraw.COLD)
	var empty := _view("far_duel")
	assert_null(TankLightDraw.room_rider(empty, "turret_drive"), "an empty seat")


func test_the_view_feeds_the_press_to_the_room() -> void:
	var v := _view("repair")
	var s := v.game.state
	var rp := s.station(TankIds.ENGINE_REPAIR) as TankRepairState
	rp.press_t = 0.6
	rp.patches = 7
	var inp := v.paint_input(s)
	var row: Dictionary = inp["repair"]
	assert_eq(float(row["press_t"]), 0.6)
	assert_eq(int(row["patches"]), 7)
	assert_eq(int(row["slot"]), rp.slot, "its rider")
	assert_eq(float(row["revs"]), v.machine_phase("repair"), "1:1 with the crank")
	assert_true(bool(row["on"]))


# --- Going west ---------------------------------------------------------------------------------------


func test_going_west_near_threats_and_bushes_mirror_with_the_near_panel() -> void:
	var v := _roam()
	var near: Rect2 = v.panels["near"]
	assert_eq(near, Rect2(338, 0, 622, 540))
	var r := v.hud_enemy_rect(303)
	assert_ne(r, Rect2(), "the recon's rect")
	assert_true(near.encloses(r), "on the near panel, on the right")
	assert_lt(r.get_center().x, v.hud_tank_point("headlight").x, "ahead of a tank driving left")
	assert_gt(v.hud_tank_point("rear").x, v.hud_tank_point("headlight").x, "its rear to the right")
	assert_eq(v.hud_barrel_dir(), -1.0, "the barrel points the way it drives")
	assert_gt(TankWorldDraw.bushes_at(v).size(), 0)
	for size: Vector2 in SIZES:
		var w := _roam(size)
		assert_true((w.panels["near"] as Rect2).encloses(w.hud_enemy_rect(303)), "%s" % size)
		var n: Rect2 = w.panels["near"]
		assert_gte(w.hud_tank_point("headlight").x, n.position.x, "%s: the tank's whole" % size)
		assert_lte(w.hud_tank_point("rear").x, n.end.x, "%s" % size)


func test_going_west_the_tow_still_draws_the_tank_backward() -> void:
	var s := TankFixturesV4.make("roam_west")
	s.hull.tow_s = 5.0
	var g: TankGame = autofree(U.roam_game(s))
	var v := U.make_view(self, g)
	var rear0 := v.hud_tank_point("rear").x
	U.run(v, 60)
	assert_gt(v.hud_tank_point("rear").x, rear0 + 8.0, "back toward the canvas' right edge")


func test_going_west_their_shells_arrive_on_the_near_panel_from_the_seam() -> void:
	var s := TankFixturesV4.make("roam_west")
	s.shells.append(TankFixturesV4._far_shell(901, TankIds.SHELL_ENEMY, false, 1300.0, 0.175))
	s.shells[0].will_hit = true
	var g: TankGame = autofree(U.roam_game(s))
	var v := U.make_view(self, g)
	var rows := v.shells_drawn(s)
	assert_eq(rows.size(), 1)
	var at: Vector2 = rows[0]["at"]
	var canvas_x := 960.0 - at.x
	assert_gte(canvas_x, 338.0 - 8.0, "the travel frame's edge is the seam's side when mirrored")
