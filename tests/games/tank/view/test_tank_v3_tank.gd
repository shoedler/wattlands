extends GutTest
## The v3 tank in the view (docs/games/tank.md v3 "The tank, in the view", "Terrain relief",
## "Firing", "World"): the one tank built headless for crews 1-4 with any seat empty, the rooms
## painted live (a rider on a manned seat, a bare saddle on an empty one), per-wheel suspension on
## the relief with the hull fitted to the contacts and turned as a whole, the r6 recoil, rock, jolt
## and screen shake, the firing effects spawning and expiring, the bow guns' tilt, the loader's
## picture, the light layers' order, no people outside the tank, every pixel_flex canvas.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
## The approved r6b frames' numbers (build/v3mock/tank/r6/fire_fx.json and notes.md, 30 fps): frame,
## recoil px, rock degrees, jolt px, the screen shake ((2,-1), (-2,1), (1,1) over three frames).
const FIRE_FX: Array = [
	[0, 0.0, 0.0, 2.0, Vector2i(2, -1)],
	[1, 6.11, -1.28, 2.0, Vector2i(-2, 1)],
	[2, 10.75, -1.53, 2.0, Vector2i(1, 1)],
	[3, 9.56, -1.05, 1.0, Vector2i.ZERO],
	[4, 8.44, -0.56, 1.0, Vector2i.ZERO],
]


func test_every_crew_builds_with_any_seat_empty() -> void:
	for crew in [1, 2, 3, 4]:
		var base := U.fixture("state", crew)
		for k in base.stations.size():
			var s := U.fixture("state", crew)
			var st := s.stations[k]
			st.slot = -1
			st.peer = 0
			var v := U.view_of(self, s)
			U.run(v, 10)
			var seat := v.seat_of_engine(st.engine)
			assert_ne(seat, "", "crew %d: %s works a seat" % [crew, st.engine])
			assert_null(v.rider_on(seat), "crew %d: %s empty" % [crew, seat])
			assert_eq(int(v.seat_slots[seat]), -1)
			assert_eq(v.machine_phase(seat), 0.0, "crew %d: an empty seat stands still" % crew)
			assert_gt(v.interior.paints, 0)
			assert_true(st.is_empty())


func test_a_manned_seat_shows_its_rider_and_an_empty_one_a_bare_saddle() -> void:
	var rig := TankRig.shared()
	var a := TankInterior.new(rig)
	var b := TankInterior.new(rig)
	var inp := _inputs({"drive": 0})
	a.paint_all(inp)
	b.paint_all(_inputs({}))
	var r := Rect2i(rig.rooms["drive"])
	var differ := 0
	var cap := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var ca := a.img.get_pixel(x, y)
			if not ca.is_equal_approx(b.img.get_pixel(x, y)):
				differ += 1
			if ca.is_equal_approx(TankInterior.SLOT[0]):
				cap += 1
	assert_gt(differ, 20, "the rider, the turning crank and the running diesel")
	assert_gt(cap, 0, "the rider's cap in the slot colour")
	# Outside the painted rooms the base art stays as it is.
	var q := Vector2i(10, 10)
	assert_eq(a.img.get_pixelv(q), rig.base_img.get_pixelv(q))


func test_machines_repaint_only_when_their_inputs_change() -> void:
	var it := TankInterior.new(TankRig.shared())
	var inp := _inputs({"drive": 0, "gun": 1})
	it.paint_all(inp)
	var n := it.paints
	assert_false(it.paint(inp, 1.0), "nothing changed: nothing paints")
	assert_eq(it.paints, n)
	(inp["drive"] as Dictionary)["revs"] = 0.5
	assert_true(it.paint(inp, 2.0), "the crank turned: the drive repaints")
	assert_eq(it.paints, n + 1, "only the drive")
	var before := it.img.get_region(Rect2i(TankRig.shared().rooms["drive"]))
	(inp["drive"] as Dictionary)["revs"] = 0.75
	it.paint(inp, 3.0)
	var after := it.img.get_region(Rect2i(TankRig.shared().rooms["drive"]))
	assert_ne(before.get_data(), after.get_data(), "the picture moves with the crank")


func test_each_wheel_follows_the_ground_within_its_travel() -> void:
	var rig := TankRig.shared()
	var g := rig.gear
	var t := float(g["T"])
	var up := float(g["up"])
	var droop := float(g["droop"])
	var bumpy := func(x: float) -> float: return 385.0 + 4.0 * sin(x / 30.0) + 6.0 * sin(x / 97.0)
	for cx: float in [200.0, 260.0, 333.0, 410.0]:
		var fit := TankSuspension.fit(rig.wheels, rig.size, cx, bumpy)
		var xf := TankSuspension.xform(rig.size, rig.ground, fit["at"], float(fit["rot"]), 0.0)
		var cs := TankSuspension.wheel_centres(rig.wheels, xf, bumpy, t, up, droop)
		for i in cs.size():
			var w := rig.wheels[i]
			var travel := w.y - cs[i].y
			assert_between(travel, -droop - 0.01, up + 0.01, "wheel %d within its travel" % i)
			var c := xf * cs[i]
			var bottom := c.y + w.z + t
			var gy := float(bumpy.call(c.x))
			if travel > -droop + 0.01 and travel < up - 0.01:
				assert_almost_eq(
					bottom, gy, 0.6, "wheel %d's track on the ground at %.0f" % [i, cx]
				)
		var pts: Array[Vector2] = []
		for i2 in rig.wheels.size():
			var x := cx + rig.wheels[i2].x - rig.size.x * 0.5
			pts.append(Vector2(x, float(bumpy.call(x))))
		assert_almost_eq(
			float(fit["rot"]), TankSuspension.fit_angle(pts), 1e-5, "the hull fits the contacts"
		)


func test_the_hull_turns_as_a_whole_on_a_climb_and_bobs_on_its_springs() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	U.run(v, 60)
	var flat := v.hull_rot
	# A 6 % climb under the tank: the hull turns nose up as a whole sprite.
	var prof := PackedFloat32Array()
	for i in 4000:
		prof.append(float(i) * 0.06)
	v.ground.prof = prof
	v.ground.prof_from = 0.0
	U.run(v, 3)
	var moving := v.hull_rot
	U.run(v, 120)
	assert_lt(v.hull_rot, flat - 0.01, "nose up on the climb")
	assert_ne(moving, v.hull_rot, "it swings onto the slope on its springs")
	assert_almost_eq(v.xf.get_rotation(), v.hull_rot, 1e-4, "the tank's sprite turned with it")
	assert_eq(v.layer("Tank").texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "nearest")
	for i in v.wheel_centres.size():
		var c := v.wheel_contact(i)
		var gy := v.ground_y(c.x)
		var travel := v.rig.wheels[i].y - v.wheel_centres[i].y
		if travel > -float(v.rig.gear["droop"]) + 0.01 and travel < float(v.rig.gear["up"]) - 0.01:
			assert_almost_eq(c.y, gy, 1.0, "wheel %d on the road" % i)


func test_the_relief_is_seeded_and_small() -> void:
	var a := TankGround.new(1)
	var b := TankGround.new(1)
	var c := TankGround.new(2)
	assert_eq(a.bumps(123.0), b.bumps(123.0), "the same seed, the same road")
	assert_ne(a.bumps(123.0), c.bumps(123.0), "another seed, another road")
	var top := 0.0
	for x in range(0, 4000, 7):
		top = maxf(top, absf(a.bumps(float(x))))
	assert_lt(top, 5.0, "small cosmetic bumps")
	var flat := TankGround.new(1)
	flat.frame(0.0, 300.0, 100.0, "seg", [[0, 6.0], [2000, 6.0]])
	assert_gt(flat.terrain(900.0), 1.0, "a climb rises ahead")
	assert_lt(flat.terrain(0.0), -1.0, "and falls behind")
	assert_lte(absf(flat.terrain(50000.0)), TankGround.TERRAIN_MAX + 0.01, "saturated")


func test_recoil_rock_jolt_and_shake_follow_the_approved_r6b_timeline() -> void:
	for row: Array in FIRE_FX:
		var t := float(row[0]) / 30.0
		assert_almost_eq(TankInterior.recoil(t), float(row[1]), 0.02, "recoil at %.3f" % t)
		assert_almost_eq(TankFiring.rock_at(t), float(row[2]), 0.02, "rock at %.3f" % t)
		assert_almost_eq(TankFiring.jolt_at(t), float(row[3]), 0.001, "jolt at %.3f" % t)
		assert_eq(TankFiring.shake_at(t), row[4], "shake at %.3f" % t)
	assert_eq(TankInterior.recoil(0.7), 0.0, "back home by 0.65 s")
	assert_eq(TankFiring.rock_at(1.9), 0.0, "settled by 1.8 s")
	assert_eq(TankFiring.shake_at(0.1), Vector2i.ZERO, "three frames of shake")


func test_a_shot_recoils_the_gun_rocks_the_hull_and_shakes_the_camera() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	U.run(v, 30)
	var rest_muzzle := v.muzzle()
	var rest_rot := v.xf.get_rotation()
	v.fire("main")
	v.advance(1.0 / 60.0)
	assert_ne(v.stage.position, Vector2(0, v.y_off), "the camera shakes on the shot")
	U.run(v, 3)
	assert_gt(rest_muzzle.distance_to(v.muzzle()), 5.0, "the barrel recoils")
	assert_lt(v.xf.get_rotation(), rest_rot - deg_to_rad(0.5), "the hull rocks back, nose up")
	U.run(v, 150)
	assert_eq(v.stage.position, Vector2(0, v.y_off), "the shake is over")
	assert_almost_eq(v.muzzle().distance_to(rest_muzzle), 0.0, 1.5, "the gun runs out again")
	assert_almost_eq(v.xf.get_rotation(), rest_rot, deg_to_rad(0.1), "and the hull settles")


func test_firing_effects_spawn_and_expire() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	assert_false(v.firing.active())
	v.apply_cue(s, TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 15))
	U.run(v, 1)
	assert_true(v.firing.active(), "the blast runs")
	assert_gt(v.firing.flash_k(), 0.0, "the scene flash")
	var air: Dictionary = v.rig.blast["air"]
	assert_eq(
		TankFiring.frame_at(0.0, v.rig.blast_fps, int(air["frames"])), 0, "the star flash first"
	)
	assert_eq(TankFiring.frame_at(2.5, v.rig.blast_fps, int(air["frames"])), -1, "then nothing")
	U.run(v, 12)
	assert_eq(v.firing.flash_k(), 0.0, "the flash lasts about four frames")
	(s.station(TankIds.ENGINE_FEED) as TankFeedState).rounds += 4
	U.run(v, 1)
	assert_eq(v.firing.rounds.size(), 4, "a flash, a tracer and a case per round")
	var guns := {}
	for r in v.firing.rounds:
		guns[int(r["k"])] = true
	assert_eq(guns.size(), 2, "alternating between the two bow guns")
	assert_true(v.firing.bow_kicking(0, TankView.BOW_KICK_S) or v.firing.bow_kicking(1, 0.06))
	U.run(v, 150)
	assert_false(v.firing.active(), "everything expires")
	assert_eq(v.firing.rounds.size(), 0)


func test_each_new_secondaries_round_fires_from_its_gun() -> void:
	var s := U.fixture("state", 4)
	var feed := s.station(TankIds.ENGINE_FEED) as TankFeedState
	assert_not_null(feed, "the Secondaries seat")
	feed.rounds = 10
	var v := U.view_of(self, s)
	U.run(v, 2)
	assert_eq(v.firing.rounds.size(), 0, "the rounds fired before the view came are not replayed")
	feed.rounds = 13
	feed.rpm = 180.0
	U.run(v, 1)
	assert_eq(v.firing.rounds.size(), 3, "a flash, a tracer and a case per new round")
	var guns: Array = []
	for r in v.firing.rounds:
		guns.append(int(r["k"]))
	assert_eq(guns, [0, 1, 0], "round k from gun (k - 1) mod 2: 11, 12, 13")
	feed.rounds = 40
	U.run(v, 1)
	assert_eq(v.firing.rounds.size(), 3 + TankView.MAX_ROUNDS_PER_FRAME, "a late snapshot capped")
	v.apply_cue(s, TankEvents.SHOT, TankEvents.shot(3, TankIds.SHELL_BOW, 17))
	assert_eq(
		v.firing.rounds.size(), 3 + TankView.MAX_ROUNDS_PER_FRAME, "the feed counts, not the cue"
	)


func test_the_relief_integrates_the_rules_terrain_like_tank_terrain() -> void:
	var pts := [[0, 0.0], [130, 1.5], [250, 3.0], [380, 1.0], [510, -2.0], [630, 0.0]]
	var g := TankGround.new(1)
	g.frame(0.0, 300.0, 0.0, "seg", pts)
	for m: float in [0.0, 77.0, 130.0, 333.3, 600.0, 900.0]:
		assert_almost_eq(g.height_m(m), TankTerrain.height_at(pts, m), 0.02, "at %.0f m" % m)


func test_the_bow_guns_tilt_toward_the_nearest_enemy_ahead() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	s.enemies.clear()
	U.run(v, 60)
	assert_almost_eq(v.bow_elev, TankView.BOW_REST_DEG, 0.01, "at rest without a target")
	var e := TankEnemyState.new()
	e.id = 77
	e.code = TankIds.ENEMY_CODES[TankIds.ENEMY_LIGHT]
	e.x_px = s.hull.x_px + float(s.hull.hull_w) + 60.0
	e.w = 80
	e.h = 30
	e.hp = 10.0
	e.hp_max = 10.0
	e.lane = 0
	s.enemies.append(e)
	U.run(v, 90)
	assert_ne(v.bow_elev, TankView.BOW_REST_DEG, "they lay on the target")
	assert_between(v.bow_elev, TankView.BOW_MIN_DEG, TankView.BOW_MAX_DEG)
	var d := v.bow_target - v.at_sprite(v.rig.bow[0]["pivot"])
	var want := -rad_to_deg(d.angle() - v.hull_rot)
	if want <= TankView.BOW_MIN_DEG:
		assert_eq(v.bow_elev, TankView.BOW_MIN_DEG, "as low as the box lets them")
	elif want >= TankView.BOW_MAX_DEG:
		assert_eq(v.bow_elev, TankView.BOW_MAX_DEG, "as high as the box lets them")
	else:
		assert_almost_eq(want, v.bow_elev, 0.5, "aimed at it")


func test_the_loader_picture_follows_the_rack_the_stow_and_the_chambering() -> void:
	var idle := TankFiring.from_fields(2, -1.0, -1.0, 99.0)
	assert_eq(float(idle["lt"]), -1.0, "nothing moving")
	assert_eq(int(idle["ready"]), 2, "two rounds racked")
	var stow := TankFiring.from_fields(1, 0.5, -1.0, 99.0)
	assert_eq(
		str(TankInterior.step_at(float(stow["lt"]))["step"]), "HOIST", "half way: on the hoist"
	)
	var stowed := TankFiring.from_fields(1, 0.95, -1.0, 99.0)
	assert_eq(str(TankInterior.step_at(float(stowed["lt"]))["step"]), "RESET")
	assert_eq(int(stowed["ready"]), 2, "the stowed round shows racked while the tray goes down")
	var full := TankFiring.from_fields(3, 0.5, -1.0, 99.0)
	assert_eq(float(full["lt"]), -1.0, "a full rack stows nothing")
	var steps := {}
	for k in 10:
		var ch := TankFiring.from_fields(2, -1.0, float(k) / 10.0, 0.5)
		steps[str(TankInterior.step_at(float(ch["lt"]))["step"])] = true
	for want: String in ["FEED", "BREECH OPEN", "RAM", "BREECH SHUT"]:
		assert_true(steps.has(want), "the chambering shows " + want)
	# From the contracts: TankSteamState rack, load_t, chamber_s.
	var s := U.fixture("state", 3)
	var st := s.station(TankIds.ENGINE_STEAM) as TankSteamState
	st.rack = 1
	st.load_t = 0.4
	st.chamber_s = 0.0
	var lv := TankFiring.loader_view(s, st, 99.0)
	assert_eq(int(lv["ready"]), 1, "the rack's count")
	assert_between(float(lv["lt"]), 0.0, TankFiring.STOW_TO, "stowing the next round at load_t")
	st.chamber_s = 0.5
	var ch := TankFiring.loader_view(s, st, 0.5)
	var step := str(TankInterior.step_at(float(ch["lt"]))["step"])
	assert_true(step in ["FEED", "BREECH OPEN", "RAM", "BREECH SHUT"], "chambering: " + step)
	st.chamber_s = 0.0
	st.load_t = 0.0
	assert_eq(float(TankFiring.loader_view(s, st, 99.0)["lt"]), -1.0, "idle")
	st.load_t = 0.4
	st.slot = -1
	assert_eq(
		float(TankFiring.loader_view(s, st, 99.0)["lt"]), -1.0, "an empty Loader seat: no reload"
	)
	st.rack = 3
	assert_eq(int(TankFiring.loader_view(s, st, 99.0)["ready"]), 3, "a full rack")


func test_world_lights_draw_behind_the_tank() -> void:
	var v := U.view_of(self, U.fixture("state", 3))
	var order: Array[String] = []
	for c in v.stage.get_children():
		order.append(str(c.name))
	assert_eq(order, ["Back", "World", "WorldLight", "Tank", "Light", "Front", "Post"])
	assert_lt(order.find("WorldLight"), order.find("Tank"), "the world's lamps behind the tank")
	assert_gt(order.find("Light"), order.find("Tank"), "the tank's own lights over it")
	for n: String in ["WorldLight", "Light"]:
		var m := v.layer(n).material as CanvasItemMaterial
		assert_eq(m.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, n + " is additive")


func test_little_bases_stand_at_the_depot_and_in_free_roam() -> void:
	var s := U.fixture("state", 3)
	s.seg.seg = TankIds.SEG_DEPOT
	s.hull.x_px = 0.0
	var v := U.view_of(self, s)
	var bases := TankForest.bases(v, s)
	assert_eq(bases.size(), 1, "the depot's base in view at the start")
	if bases.is_empty():
		return
	var lights := TankForest.base_lights(v, bases[0])
	assert_eq(lights.size(), 2, "its lamp and its slit")
	var adv := U.fixture("state", 3)
	adv.seg.seg = TankIds.SEG_ADVANCE
	var va := U.view_of(self, adv)
	assert_eq(TankForest.bases(va, adv).size(), 0, "none on the road between")
	var r := U.roam_state(3)
	r.roam.map_m = r.roam_map.strongpoints[0]
	var g: TankGame = autofree(U.roam_game(r))
	var vr := U.make_view(self, g)
	assert_gte(TankForest.bases(vr, r).size(), 1, "a base clearing at a strongpoint")


func test_no_people_outside_the_tank() -> void:
	assert_false(DirAccess.dir_exists_absolute("res://assets/tank/v2/crew20"), "no crewmen sprites")
	assert_false(TankKit.load_manifest().has("crew"))
	assert_false(TankRig.load_manifest().has("crew"))
	for cls: Dictionary in ProjectSettings.get_global_class_list():
		assert_ne(str(cls["class"]), "TankCrew", "no crew actors")
		assert_ne(str(cls["class"]), "TankDepotDraw", "no depot yard")
	var v := U.view_of(self, U.fixture("state", 3))
	for p in v.get_property_list():
		assert_ne(str(p["name"]), "crew", "the view has no crew")


func test_every_flex_canvas_shows_the_whole_tank_on_the_road() -> void:
	for size: Vector2 in [Vector2(852, 480), Vector2(960, 540), Vector2(1146, 480)]:
		var v := U.view_of(self, U.fixture("gun_line", 4), Wl.SOLO, 1, size)
		U.run(v, 5)
		var body := v.hud_tank_rects()
		for r in body:
			assert_true(Rect2(Vector2.ZERO, size).encloses(r), "%s: %s on the canvas" % [size, r])
		var road := TankView.GROUND + v.y_off
		assert_between(road, size.y * 0.6, size.y - 40.0, "%s: the road low on the canvas" % size)
		assert_almost_eq(body[1].end.y, road, 8.0, "%s: the tracks on the road" % size)


func _inputs(manned: Dictionary) -> Dictionary:
	var inp := {"t": 1.0}
	for seat in TankRig.SEATS:
		var on := manned.has(seat)
		inp[seat] = {"slot": int(manned.get(seat, -1)), "revs": 0.25 if on else 0.0, "on": on}
	inp["loader_seat"] = inp["loader"]
	inp["loader"] = TankFiring.from_fields(2, -1.0, -1.0, 99.0)
	inp["bow"] = {"revs": -1.0}
	return inp
