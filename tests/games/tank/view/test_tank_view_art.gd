extends GutTest
## The world's art: enemies in depth lanes smaller, higher, darker and hazier further back, each on
## its own ground; wrecks in their lane, opaque and lit by the beams they cross; the road band
## fading in over the verge and solid under the tracks; the engine windows' room light free of the
## slot colour.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func test_back_lanes_stand_higher_smaller_darker_and_hazier() -> void:
	var v := U.view_of(self, U.fixture("gun_line", 3))
	for kind: String in TankKit.ENEMY_KINDS:
		var prev := Rect2()
		for lane in TankView.LANES:
			var r := v.lane_rect(kind, 500.0, lane)
			assert_eq(
				r.end.y, TankView.lane_foot(lane), "%s lane %d stands on its ground" % [kind, lane]
			)
			if lane > 0:
				assert_lt(r.end.y, prev.end.y, "%s: a lane further back stands higher" % kind)
				assert_lt(r.size.x, prev.size.x, "%s: and smaller" % kind)
				assert_lt(TankWorldDraw.lane_dim(lane), TankWorldDraw.lane_dim(lane - 1))
				assert_gt(TankWorldDraw.lane_fog(lane), TankWorldDraw.lane_fog(lane - 1))
			assert_almost_eq(r.get_center().x, 500.0, 1.0, "centred where the rules hold it")
			prev = r
	assert_eq(TankView.lane_foot(0), TankView.ROAD_ENEMY_Y, "the front lane on the road")
	# A heavy two lanes back is drawn no larger than a medium in the front lane.
	var heavy := v.lane_rect("heavy", 500.0, 2)
	var medium := v.lane_rect("medium", 500.0, 0)
	assert_lte(heavy.size.y, medium.size.y)


func test_every_enemy_sprite_carries_its_shading_masks() -> void:
	var kit := TankKit.shared()
	for kind: String in TankKit.ENEMY_KINDS:
		var row: Dictionary = kit.enemies[kind]
		for m: String in ["sil", "rim"]:
			assert_true(row.has(m), "%s %s" % [kind, m])
			assert_eq(
				Vector2((row[m] as Texture2D).get_size()), row["size"], "%s %s size" % [kind, m]
			)


func test_wrecks_stand_in_their_lane_and_the_beams_light_them() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	for lane in TankView.LANES:
		var w := {"x": s.hull.x_px + 420.0, "kind": "medium", "lane": lane, "side": 1, "t": s.t}
		var r := TankWorldDraw.wreck_rect(v, w)
		assert_eq(r.end.y, TankView.lane_foot(lane) + TankWorldDraw.WRECK_SINK, "lane %d" % lane)
		var hatch := TankWorldDraw.wreck_hatch(v, w)
		assert_true(r.grow(1.0).has_point(hatch), "the fire shows through the hulk's hatch")
	# The headlight lights the road ahead, not the road behind the tank.
	var ahead := v.at_sprite(v.rig.detail("headlight")["at"]) + Vector2(220, 40)
	var behind := Vector2(v.tank_pos.x - 60.0, TankView.GROUND - 20.0)
	assert_gt(TankLightDraw.beam_light(v, s, ahead), 0.2, "in the headlight's cone")
	assert_lt(
		TankLightDraw.beam_light(v, s, behind), 0.05, "the road behind: the work light's edge"
	)
	var lit := TankLightDraw.beam_light(v, s, ahead)
	s.hull.breakdown = true
	assert_lt(TankLightDraw.beam_light(v, s, ahead), lit, "a breakdown dims the headlight")


func test_the_road_band_fades_in_over_the_verge_and_is_solid_under_the_tracks() -> void:
	var tex := TankForest.road_tex()
	assert_eq(tex.get_width(), TankForest.ROAD_W)
	var img := tex.get_image()
	assert_lt(img.get_pixel(5, 0).a, 0.05, "it fades in at its far edge")
	assert_lt(img.get_pixel(5, TankForest.ROAD_H - 1).a, 0.1, "and out under the near shoulder")
	var under := TankForest.ROAD_TOP + 4
	for x in range(0, TankForest.ROAD_W, 37):
		assert_eq(img.get_pixel(x, under).a, 1.0, "solid under the tracks at x %d" % x)


func test_the_engine_windows_room_light_does_not_take_the_slot_colour() -> void:
	var a := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
	var b := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
	for kind: String in ["diesel", "steam", "dynamo", "arc"]:
		TankMech.paint_ex(a, kind, 0.3, 1.0, 1.0, Color(0.9, 0.3, 0.1), 90.0)
		TankMech.paint_ex(b, kind, 0.3, 1.0, 1.0, Color(0.2, 0.5, 1.0), 90.0)
		var differ := 0
		for y in TankMech.H:
			for x in TankMech.W:
				if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
					differ += 1
		assert_lt(differ, TankMech.W * TankMech.H / 8, "%s: only the bulb and the tag" % kind)
