extends GutTest
## Polish round 5 (the round 4 scene critic): the running gear shows in front of the hull's lower
## band (wheels whole, the belt's upper run resting on them under the rooms, the lower run on the
## ground), the dynamo's room stays lit by its cold arc whatever the rider's colour, the steam room
## draws its boiler as a banded drum, and the armour carries rust, grime and (on the Behemoth) its
## own lit slits.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _room(rig: TankRig, engine: String) -> TankRoomView:
	for r in rig.rooms:
		if r.engine == engine:
			return r
	return null


func test_the_running_gear_is_drawn_in_front_of_the_hull_and_behind_the_rooms() -> void:
	for tank in ["bulwark", "rampart", "citadel"]:
		var rig := U.make_rig(self, tank)
		var gi := rig.gear.get_index()
		assert_gt(gi, rig.hull_sprite.get_index(), "%s: the gear over the hull's skirt" % tank)
		assert_lt(gi, rig.cutaway.get_index(), "%s: the rooms' band over the belt's top" % tank)
		for room in rig.rooms:
			assert_gt(room.get_index(), gi, "%s: every room over the gear" % tank)


func test_the_belt_runs_under_the_rooms_and_on_the_ground() -> void:
	for tank in ["bulwark", "rampart", "citadel"]:
		var rig := U.make_rig(self, tank)
		var def := TankRigs.tank_def(tank)
		var floor_y := 0.0
		for room in rig.rooms:
			floor_y = maxf(floor_y, room.rect.end.y)
		var xs := TankRunningGear.road_xs(def)
		var top := INF
		var bottom := -INF
		for p in rig.gear.belt.points:
			if p.x >= xs[0] and p.x <= xs[xs.size() - 1]:
				top = minf(top, p.y)
			bottom = maxf(bottom, p.y)
		# The rooms' band reaches 3 px under the floor, its lit lip one more.
		assert_gt(top - 1.5, floor_y + 3.0, "%s: the upper run clears the rooms' band" % tank)
		assert_almost_eq(
			bottom, float(rig.hull_h + TankRig.GROUND_GAP) + 0.5, 0.6, "%s: on the ground" % tank
		)
		assert_almost_eq(rig.gear.ground_y, float(rig.hull_h + TankRig.GROUND_GAP), 1e-3, tank)


func test_the_upper_run_rests_on_the_road_wheels() -> void:
	for tank in ["bulwark", "rampart", "citadel"]:
		var rig := U.make_rig(self, tank)
		var def := TankRigs.tank_def(tank)
		var xs := TankRunningGear.road_xs(def)
		var line_y := float(def.get("wheel_line_y"))
		var want := line_y - rig.gear.road_r - 0.5
		var on := 0
		for p in rig.gear.belt.points:
			if p.x >= xs[0] and p.x <= xs[xs.size() - 1] and p.y < line_y:
				assert_almost_eq(p.y, want, 1e-3, "%s: the top run lies on the wheels" % tank)
				on += 1
		assert_gte(on, 2, tank)


func test_each_tank_has_its_own_wheel_size_and_more_road_wheels_than_four() -> void:
	var prev := 0.0
	for tank in ["bulwark", "rampart", "citadel"]:
		var rig := U.make_rig(self, tank)
		assert_gt(rig.gear.road_r, prev, "%s: a bigger road wheel than the last tank's" % tank)
		prev = rig.gear.road_r
		assert_gt(rig.gear.sprocket_r, rig.gear.road_r, "%s: the sprocket is the largest" % tank)
		var roads := rig.gear.kinds.count("road_wheel")
		assert_gt(roads, 4, tank)
		for w in rig.gear.wheels:
			assert_eq(w.self_modulate.a, 0.0, "%s: wheels are drawn in code" % tank)


func test_the_dynamo_lamp_lights_only_its_corner() -> void:
	var rig := U.make_rig(self, "citadel")
	var dyn := _room(rig, TankIds.ENGINE_DYNAMO)
	var diesel := _room(rig, TankIds.ENGINE_DIESEL)
	assert_lt(dyn.lamp_reach(), 0.5, "the arc's blue-white owns the dynamo room")
	assert_eq(diesel.lamp_reach(), 1.0, "other rooms keep the full lamp wash")
	assert_eq(dyn.tint(), TankPalette.COLD_LIGHT)


func test_the_rider_colour_never_tints_the_dynamo_sparks() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.state(3)
	for _i in 90:
		rig.update(s, U.feed_of(s, 260.0, 95.0), 1.0 / 60.0)
	var fx := rig.hub.fx
	var arc := rig.hub.to_layer(rig.dynamo_room.armature_hull_pos())
	var cold := 0
	for i in fx.particles.count:
		if fx.particles.kind[i] != TankParticles.Kind.SPARK:
			continue
		if fx.particles.pos[i].distance_to(arc) > 30.0:
			continue
		var c: Color = fx.particles.color[i]
		assert_gt(c.b, c.r, "a dynamo spark is cold")
		cold += 1
	assert_gt(cold, 0, "the armature throws sparks")


func test_the_boiler_is_drawn_in_code_and_the_gauge_is_a_grey_dial() -> void:
	var rig := U.make_rig(self, "citadel")
	var st := _room(rig, TankIds.ENGINE_STEAM) as TankSteamRoom
	var boiler := st.get_node("Boiler") as Sprite2D
	assert_eq(boiler.self_modulate.a, 0.0, "the generated boiler is replaced by the drum")
	assert_lt(TankSteamRoom.DIAL_FACE.s, 0.15, "a grey face, not a yellow disc")
	var ticks := int(TankSteamRoom.GAUGE_MAX_PCT / TankSteamRoom.GAUGE_TICK_PCT) + 1
	assert_between(ticks, 4, 7, "a few ticks, not a clock's twelve")


func test_weathering_streaks_rust_under_rivets_and_stops_at_seams() -> void:
	var w := 60
	var h := 40
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(1, 1, w - 2, h - 2), TankMaterial.G4)
	img.fill_rect(Rect2i(1, 30, w - 2, 1), TankMaterial.G1)
	for x in range(3, w - 4, 2):
		img.set_pixel(x, 6, TankMaterial.G7)
		img.set_pixel(x + 1, 7, TankMaterial.G1)
	var out := TankMaterial.weathered(img, "turret_weather_test")
	var warm := 0
	for y in range(8, 30):
		for x in w:
			var c := out.get_pixel(x, y)
			if c.a > 0.5 and c.r > c.b + 0.01:
				warm += 1
	assert_gt(warm, 0, "rust runs under the rivets")
	for x in range(1, w - 1):
		assert_eq(out.get_pixel(x, 30), TankMaterial.G1, "the seam stays a seam")


func test_the_behemoth_has_lit_slits_that_never_pair_up() -> void:
	if not TankSprites.has_real("boss_hull"):
		pass_test("no generated Behemoth: its placeholder is drawn elsewhere")
		return
	var img := TankSprites.tex("boss_hull").get_image()
	if img.is_compressed():
		img.decompress()
	var cores: Array[Vector2i] = []
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y) == TankPlaceholderArt.F2:
				cores.append(Vector2i(x, y))
	assert_gte(cores.size(), 2, "lit from within: at least two lit slits")
	for i in cores.size():
		for j in range(i + 1, cores.size()):
			var d := (cores[i] - cores[j]).abs()
			assert_true(
				d.y >= 6 or d.x >= 60, "no two slits side by side (they would read as eyes)"
			)
