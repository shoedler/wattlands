extends GutTest
## TankFixturesV4 (SPEC_TANK section 7): every fixture builds, is a sound snapshot, runs through the
## view and the HUD at both canvases, and its fake moves what the frames show. Plus the stubs the
## builders start from (the enemy kit and draw, the Repairs room) and SPEC_AUDIO's audio_feed.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


## A canvas that counts what it was asked to draw.
class Sketch:
	extends Node2D
	var kit := TankEnemyKit.shared()
	var calls: Array = []
	var drawn := 0

	func _draw() -> void:
		for c: Array in calls:
			TankEnemyDraw.draw(self, kit, str(c[0]), c[1], c[2])
			TankEnemyDraw.draw_light(self, kit, str(c[0]), c[1], c[2])
			drawn += 1


func test_the_fixture_list_matches_the_script() -> void:
	var script := FileAccess.get_file_as_string("res://tests/games/tank/view/render_v4.sh")
	for n in TankFixturesV4.NAMES:
		assert_true(script.contains(n), "render_v4.sh renders %s" % n)
	assert_eq(TankFixturesV4.NAMES.size(), 14)


func test_every_fixture_is_a_sound_snapshot() -> void:
	for n in TankFixturesV4.NAMES:
		var s := TankFixturesV4.make(n)
		assert_not_null(s, n)
		var snap := TankSnapshot.encode(s)
		assert_eq(TankSnapshotSchema.check(snap), "", n)
		assert_eq(int(snap["v"]), 5, n)
		assert_eq((snap["st"] as Array).size(), 6, "%s: six rooms" % n)
		assert_lte(TankSnapshotSchema.byte_size(snap), TankConst.SNAPSHOT_MAX_BYTES, n)
		for e in s.enemies:
			assert_eq(e.side, 1, "%s: nothing behind the tank" % n)
			if e.is_near():
				assert_eq(e.range_m, 0.0, n)
				assert_gt(e.x_px, s.hull.x_px + float(s.hull.hull_w), "%s: ahead of the front" % n)
			else:
				assert_gt(e.range_m, 0.0, n)
				assert_eq(e.x_px, 0.0, "%s: a far kind has no px" % n)


func test_the_fixtures_show_what_the_spec_says() -> void:
	var adv := TankFixturesV4.make("advance_far")
	assert_eq(adv.seg.seg, TankIds.SEG_ADVANCE)
	assert_eq(adv.seg.stage, 2)
	assert_eq(adv.enemies[0].range_m, 1220.0)
	assert_eq(adv.enemies[1].range_m, 1950.0)
	assert_eq(adv.enemies[1].telegraph_s, 3.0)
	assert_true(adv.shells[0].far and adv.shells[0].friendly)
	var duel := TankFixturesV4.make("far_duel")
	assert_eq(duel.enemies.size(), 3)
	assert_true(duel.shells[0].evadable and not duel.shells[0].friendly)
	assert_true(duel.riders[0].can_evade)
	var boss := TankFixturesV4.make("boss_far")
	assert_eq(boss.boss.range_m, 1100.0)
	assert_eq(boss.boss.bogie_hp[2], 0.0, "one bogie wrecked")
	var amb := TankFixturesV4.make("near_ambush")
	assert_eq(amb.enemies[0].mode, TankIds.EM_PAUSE)
	assert_eq(amb.enemies[1].mode, TankIds.EM_MOVE)
	assert_eq(str(TankFixturesV4.cues("near_ambush")[0]["type"]), TankEvents.AMBUSH)
	var bow := TankFixturesV4.make("bow_duel")
	assert_false(bow.station(TankIds.ENGINE_FEED).is_empty(), "Secondaries manned")
	assert_almost_eq(bow.enemies[0].hp / bow.enemies[0].hp_max, 0.4, 0.001)
	assert_almost_eq(TankFixturesV4.make("incoming").shells[0].left_s, 0.3, 0.001)
	var lost := TankFixturesV4.make("tank_lost")
	assert_eq([lost.difficulty, lost.hull.tow_s, lost.score.losses], ["hard", 5.0, 1])
	assert_true(lost.enemies.is_empty())
	assert_eq(TankFixturesV4.make("restart").hull.x_px, 0.0)
	var rep := TankFixturesV4.make("repair")
	assert_eq(rep.riders.size(), 4)
	assert_false(rep.station(TankIds.ENGINE_REPAIR).is_empty())
	assert_almost_eq(rep.hull.hp / rep.hull.hp_max, 0.55, 0.001)
	var bots := TankFixturesV4.make("bots")
	var who: Array = bots.riders.map(func(r: TankRiderState) -> bool: return r.is_bot)
	assert_eq(who, [false, true, true, true])
	assert_eq(TankFixturesV4.make("hard").difficulty, TankIds.DIFF_HARD)
	var easy := TankFixturesV4.make("easy_breakdown")
	assert_eq(easy.difficulty, TankIds.DIFF_EASY)
	assert_true(easy.hull.breakdown)
	var west := TankFixturesV4.make("roam_west")
	assert_eq(west.hull.dir, TankIds.DIR_LEFT)
	assert_true(west.roam.active)
	assert_eq(west.enemies.size(), 3)
	var cap := TankFixturesV4.make("cap_v4")
	var far := 0
	for e in cap.enemies:
		far += int(not e.is_near())
	assert_eq([cap.enemies.size(), far], [16, 8])
	var far_shells := 0
	for s in cap.shells:
		far_shells += int(s.far)
	assert_eq([cap.shells.size(), far_shells], [24, 12])


func test_no_rng_two_builds_agree() -> void:
	for n in TankFixturesV4.NAMES:
		assert_eq(
			TankSnapshot.encode(TankFixturesV4.make(n)),
			TankSnapshot.encode(TankFixturesV4.make(n)),
			n
		)


func test_the_fake_moves_shells_threats_and_the_tow() -> void:
	var adv := TankFixturesV4.make("advance_far")
	var shell := adv.shells[0]
	var left := shell.left_s
	var x := shell.x
	var hull_x := adv.hull.x_px
	TankFixturesV4.tick(adv, 0.5)
	assert_almost_eq(shell.left_s, left - 0.5, 0.001)
	assert_gt(shell.x, x, "ours flies out")
	assert_gt(adv.hull.x_px, hull_x, "the wheels turn")
	for _i in 400:
		TankFixturesV4.tick(adv, Wl.SIM_DT)
	assert_gt(shell.left_s, 0.0, "a landed shell starts over")
	assert_gte(shell.y, -1.0, "it stays above the ground")
	var amb := TankFixturesV4.make("near_ambush")
	var dash := amb.enemies[1].x_px - amb.hull.x_px
	var held := amb.enemies[0].x_px - amb.hull.x_px
	TankFixturesV4.tick(amb, 0.1)
	assert_gt(amb.enemies[1].x_px - amb.hull.x_px, dash, "the dash")
	assert_almost_eq(amb.enemies[0].x_px - amb.hull.x_px, held, 0.001, "the pause keeps pace")
	var lost := TankFixturesV4.make("tank_lost")
	TankFixturesV4.tick(lost, 1.0)
	assert_eq(lost.hull.tow_s, 4.0)
	assert_eq(lost.hull.x_px, 2400.0, "no movement under tow")
	var rep := TankFixturesV4.make("repair")
	TankFixturesV4.tick(rep, 2.0)
	assert_almost_eq((rep.station(TankIds.ENGINE_REPAIR) as TankRepairState).press_t, 0.1, 0.001)
	assert_eq((rep.station(TankIds.ENGINE_REPAIR) as TankRepairState).patches, 8)


func test_an_incoming_shell_flies_toward_the_hull() -> void:
	var s := TankFixturesV4.make("incoming")
	var shell := s.shells[0]
	assert_lt(shell.vx, 0.0)
	var x := shell.x
	TankFixturesV4.tick(s, 0.1)
	assert_lt(shell.x, x)
	assert_lt(shell.x, 500.0, "close to landing")
	assert_gte(shell.y, 0.0)


func test_every_fixture_runs_through_the_view_at_both_canvases() -> void:
	for n in TankFixturesV4.NAMES:
		for size: Vector2 in [Vector2(960, 540), Vector2(852, 480)]:
			var v := U.view_of(self, TankFixturesV4.make(n), Wl.SOLO, 1, size)
			for _i in 4:
				TankFixturesV4.tick(v.game.state, Wl.SIM_DT)
				v.advance(Wl.SIM_DT)
			for e: Dictionary in TankFixturesV4.cues(n):
				v.game.cue.emit(str(e["type"]), e)
			v.advance(Wl.SIM_DT)
			assert_true(v.frames > 0, "%s at %s" % [n, size])
			v.queue_free()
	await wait_physics_frames(2)


func test_every_fixture_builds_the_hud() -> void:
	for n in TankFixturesV4.NAMES:
		var s := TankFixturesV4.make(n)
		var g := U.make_game(s)
		autofree(g)
		var spec: HudSpec = g.hud_spec()
		assert_not_null(spec, n)
		var cards := TankHudModel.seat_cards(s, 1)
		assert_eq(cards.size(), 6, "%s: six cards" % n)
	assert_eq(str(TankHudModel.seat_cards(TankFixturesV4.make("repair"), 1)[5]["mech"]), "repair")


# --- The stubs builders start from ------------------------------------------------------------------


## SPEC_TANK 5.2's frozen sizes.
func test_the_enemy_kit_has_every_kind_at_its_size() -> void:
	var kit := TankEnemyKit.shared()
	assert_eq(TankEnemyKit.shared(), kit, "shared")
	var sizes := {
		"tankette": Vector2(56, 26),
		"recon": Vector2(78, 36),
		"light": Vector2(96, 44),
		"medium": Vector2(128, 58),
		"heavy": Vector2(168, 72),
		"destroyer": Vector2(150, 54),
		"behemoth": Vector2(300, 148),
	}
	for k: String in sizes:
		assert_eq(kit.kind(k)["size"], sizes[k], k)
	assert_eq(kit.kind("nothing")["size"], sizes["medium"], "size is always there")
	assert_not_null(kit.texture(), "the baked atlas")
	assert_eq(TankEnemyKit.check({"kinds": {}}).size(), 9, "7 kinds, bushes, far_ground")
	assert_eq(TankEnemyKit.check({}), ["no kinds"] as Array[String])


## SPEC_TANK 4.3 and 4.7: A's bake holds the bushes and the far ground the view draws.
func test_the_enemy_kit_has_bushes_and_far_ground() -> void:
	var kit := TankEnemyKit.shared()
	assert_not_null(kit.bushes(), "the bush sheet")
	assert_gt(kit.bush_rects().size(), 0, "bush frames")
	assert_not_null(kit.far_ground(), "the far ground")
	var kinds := {}
	for k: String in TankEnemyKit.SIZES:
		kinds[k] = {"size": [1, 1]}
	var problems := TankEnemyKit.check({"kinds": kinds})
	assert_eq(problems, ["no bushes", "no far_ground"] as Array[String])
	assert_eq(
		TankEnemyKit.check({"kinds": kinds, "bushes": {"rects": []}, "far_ground": "g.png"}).size(),
		1
	)
	var whole := {"kinds": kinds, "bushes": {"rects": [[0, 0, 8, 8]]}, "far_ground": "g.png"}
	assert_eq(TankEnemyKit.check(whole).size(), 0, "a whole manifest")


func test_the_enemy_draw_stub_draws_and_aims() -> void:
	var kit := TankEnemyKit.shared()
	var pose := {"turret_sx": 1.0, "elev_deg": 0.0, "recoil": 0.0}
	var foot := Vector2(100, 300)
	assert_lt(TankEnemyDraw.muzzle(kit, "medium", foot, pose).x, foot.x, "a far kind faces left")
	assert_gt(TankEnemyDraw.muzzle(kit, "recon", foot, pose).x, foot.x, "a near kind faces right")
	pose["turret_sx"] = -1.0
	assert_lt(TankEnemyDraw.muzzle(kit, "recon", foot, pose).x, foot.x, "traversed back at us")
	pose["turret_sx"] = 1.0
	pose["elev_deg"] = 10.0
	var flat := TankEnemyDraw.muzzle(kit, "medium", foot, {"turret_sx": 1.0})
	assert_lt(TankEnemyDraw.muzzle(kit, "medium", foot, pose).y, flat.y, "elevated")
	var sk: Sketch = add_child_autofree(Sketch.new())
	sk.calls = [
		["heavy", foot, {"haze": 0.3, "dim": 0.2, "flash": 0.1}],
		["tankette", foot, {"wrecked": true}],
		["behemoth", foot, {"flip": true, "bogies_wrecked": [true, false, false]}],
	]
	sk.queue_redraw()
	await wait_physics_frames(2)
	assert_eq(sk.drawn, sk.calls.size(), "every pose drew")


func test_the_repairs_room_paints_the_rider_in_the_second_floor_room() -> void:
	var s := TankFixturesV4.make("repair")
	var v := U.view_of(self, s)
	assert_eq(str(v.rig.seats["repair"]["room"]), "turret_drive")
	assert_eq(str(v.rig.seats["repair"]["engine"]), TankIds.ENGINE_REPAIR)
	assert_true(TankInterior.UNITS.has("repair"))
	assert_eq(v.seat_station(s, "repair"), s.station(TankIds.ENGINE_REPAIR))
	assert_eq(v.rider_on("repair"), s.riders[3])
	var room := Rect2i(v.rig.rooms["turret_drive"])
	var manned := v.interior.img.get_region(room)
	var empty := U.view_of(self, TankFixturesV4.make("advance_far"))
	var bare := empty.interior.img.get_region(room)
	assert_ne(manned.get_data(), bare.get_data(), "a rider sits in the manned room")
	# 112 x 64 card: an unknown machine falls back to the diesel until builder A.
	var card := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
	TankMech.paint(card, "repair", 0.25, 1.0, 1.0, Color.WHITE)
	assert_false(card.is_invisible(), "the sixth card paints")


# --- SPEC_AUDIO's feed (E2) -------------------------------------------------------------------------


func test_audio_feed_has_every_seat_and_follows_the_picture() -> void:
	var s := TankFixturesV4.make("repair")
	var v := U.view_of(self, s)
	U.run(v, 30)
	var feed := v.audio_feed(s)
	assert_eq(feed.keys().size(), TankRig.SEATS.size())
	var drive: Dictionary = feed["drive"]
	assert_eq(drive["revs"], v.machine_phase("drive"))
	assert_gt(float(drive["revs"]), 0.0, "the crank turned")
	assert_gt(float(drive["rpm"]), 0.0)
	assert_eq(drive["power"], v.machine_power("drive"))
	assert_true(drive["lead"], "peer 1 sits on Drive")
	assert_false(bool((feed["gun"] as Dictionary)["lead"]), "peer 2's")
	assert_eq((feed["sec"] as Dictionary)["rpm"], 0.0, "an empty seat is silent")
	s.hull.breakdown = true
	assert_eq((v.audio_feed(s)["drive"] as Dictionary)["rpm"], 0.0, "the picture stops the machine")


func test_a_clients_cranks_run_on_the_frame_not_the_render_clock() -> void:
	var s := TankFixtures.state(2)
	var v := U.view_of(self, s, Wl.CLIENT, 2)
	var before := v.machine_phase("drive")
	# The client's render clock has no newer snapshot: it stalls, the crank must not.
	for _i in 30:
		v.advance(1.0 / 60.0)
	var turned := v.machine_phase("drive") - before
	assert_almost_eq(turned, 90.0 / 60.0 * 0.5, 0.1, "half a second at 90 rpm")
