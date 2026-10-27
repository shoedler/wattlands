extends GutTest
## The free-roam view (brief 2.10, 3.1, 4): built headless for crews 1-4 in both travel directions,
## the tank and the world mirrored while it drives west (the planes behind never), the planes
## scrolled by the hull's place on the road, the zones' near planes swapped and cross-faded, the turn's
## dust cloud peaking where the frame flips, the wrecks keeping their place through the flip, the
## turning places at the road's ends, the HUD's geometry mirrored with it, and the mission look kept.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const MIRRORED := ["World", "Tank", "Light", "Front"]


func _view(s: TankState, size: Vector2 = Vector2(960, 540)) -> TankView:
	var g: TankGame = autofree(U.roam_game(s))
	return U.make_view(self, g, size)


func test_every_crew_builds_and_runs_in_both_directions() -> void:
	for crew in [1, 2, 3, 4]:
		for dir in [TankIds.DIR_RIGHT, TankIds.DIR_LEFT]:
			var s := U.roam_state(crew, dir)
			var v := _view(s)
			U.run(v, 20)
			assert_eq(v.variant, "tank_%drider" % crew)
			assert_eq(v.mirrored, dir < 0, "crew %d dir %d" % [crew, dir])
			for n: String in MIRRORED:
				var l := v.layer(n)
				assert_eq(l.scale.x, -1.0 if dir < 0 else 1.0, "%s mirrored with the tank" % n)
				assert_eq(l.position.x, v.canvas.x if dir < 0 else 0.0, n)
			for n2: String in ["Back", "Post"]:
				assert_eq(v.layer(n2).scale.x, 1.0, "%s never mirrored" % n2)
			assert_false(v.zone_mix.is_empty(), "a zone's near plane")
			assert_gt(v.frames, 20)


func test_a_mirrored_tank_stands_on_the_right_facing_left_on_every_canvas() -> void:
	for size: Vector2 in [Vector2(852, 480), Vector2(960, 540), Vector2(1146, 480)]:
		var east := _view(U.roam_state(3, TankIds.DIR_RIGHT), size)
		var west := _view(U.roam_state(3, TankIds.DIR_LEFT), size)
		var rear_e := east.hud_tank_point("rear").x
		var rear_w := west.hud_tank_point("rear").x
		assert_lt(rear_e, size.x * 0.5, "east: the hull's rear on the left")
		assert_gt(rear_w, size.x * 0.5, "west: the hull's rear on the right")
		assert_almost_eq(rear_w, size.x - rear_e, 0.5, "a mirror image")
		assert_true(west.hud_mirrored())
		var e := west.game.state.enemy(302)
		var er := west.hud_enemy_rect(302)
		assert_lt(er.position.x, rear_w, "the medium ahead is to the left of the tank going west")
		assert_not_null(e)
		var geom := TankHudGeom.make(west.game.state, west)
		west.game.state.hull.facing = TankIds.FACE_RIGHT
		assert_true(bool(geom.barrel()["left"]), "the barrel points left on screen")


func test_the_planes_scroll_with_the_road_and_the_world_with_the_direction() -> void:
	var s := U.roam_state(3, TankIds.DIR_LEFT)
	var v := _view(s)
	var before := v.plane_x
	s.roam.map_m -= 10.0
	s.hull.x_px += TankConst.m_to_px(10.0)
	for i in 40:
		s.tick += 1
		U.run(v, 1, Wl.SIM_DT)
	assert_almost_eq(v.plane_x - before, -TankConst.m_to_px(10.0), 2.0, "west: the planes run east")
	assert_almost_eq(v.plane_x, v.map_m * TankConst.PX_PER_M, 1e-3)
	var m := U.view_of(self, U.fixture("state", 3))
	assert_eq(m.plane_x, m.cam_x, "missions scroll the planes with the camera, as before")
	assert_false(m.mirrored)
	assert_true(m.zone_mix.is_empty())


func test_zones_swap_the_near_plane_and_cross_fade_at_their_edges() -> void:
	var s := U.roam_state(3)
	var map := s.roam_map
	var kit := TankKit.shared()
	for z: String in [
		TankIds.ZONE_LAKE, TankIds.ZONE_VILLAGE, TankIds.ZONE_QUARRY, TankIds.ZONE_MEADOW
	]:
		assert_true(kit.zone_planes.has(z), "a near plane for " + z)
		var row: Dictionary = kit.zone_planes[z]
		var forest := kit.plane("forest")
		assert_eq(row["parallax"], forest["parallax"], z)
		assert_eq(row["y0"], forest["y0"], z)
	assert_eq(kit.zone_plane(TankIds.ZONE_FOREST), kit.plane("forest"), "the forest keeps its own")
	for i in map.zones.size():
		var z2: Dictionary = map.zones[i]
		var mid := (float(z2["from_m"]) + float(z2["to_m"])) * 0.5
		var mix := TankView.zone_mix_at(map, mid)
		assert_eq(mix, {"a": z2["id"], "b": z2["id"], "k": 0.0}, "inside zone %d" % i)
		if i > 0:
			var at := TankView.zone_mix_at(map, float(z2["from_m"]))
			assert_eq(at["a"], map.zones[i - 1]["id"])
			assert_eq(at["b"], z2["id"])
			assert_almost_eq(float(at["k"]), 0.5, 1e-6, "half way at the edge")
			var later := TankView.zone_mix_at(map, float(z2["from_m"]) + 59.0)
			assert_gt(float(later["k"]), 0.95)


func test_the_turn_hides_the_flip_in_dust_and_the_wrecks_keep_their_place() -> void:
	var s := U.roam_state(3, TankIds.DIR_RIGHT)
	var v := _view(s)
	v.wrecks.append({"x": s.hull.x_px + 300.0, "kind": "medium", "lane": 0, "side": 1, "t": s.t})
	var cx := s.hull.x_px + float(s.hull.hull_w) * 0.5
	s.roam.turn_s = 7.95
	assert_lt(v.turn_dust(s), 0.1, "thin at the start")
	s.roam.turn_s = 4.0
	assert_almost_eq(v.turn_dust(s), 1.0, 1e-6, "thickest at the midpoint")
	s.roam.turn_s = 5.5
	assert_almost_eq(v.turn_dust(s), 1.0, 1e-6, "and thick around it")
	U.run(v, 2)
	s.hull.dir = TankIds.DIR_LEFT
	s.roam.turn_s = 3.95
	U.run(v, 2)
	assert_true(v.mirrored)
	assert_almost_eq(float(v.wrecks[0]["x"]), 2.0 * cx - (s.hull.x_px + 300.0), 0.01)
	assert_eq(int(v.wrecks[0]["side"]), -1)
	s.roam.turn_s = 0.0
	assert_eq(v.turn_dust(s), 0.0)


func test_a_turning_place_stands_at_each_end_of_the_road() -> void:
	var east_end := U.roam_state(2, TankIds.DIR_RIGHT, 0.0)
	east_end.roam.map_m = east_end.roam_map.hi_m
	var v := _view(east_end)
	assert_eq(TankWorldDraw.turn_lamps(v, east_end).size(), 1, "the east end's lamp in view")
	var lamp := TankWorldDraw.turn_lamps(v, east_end)[0]
	assert_between(lamp.x, 0.0, v.canvas.x, "on screen while the tank waits to turn")
	var west_end := U.roam_state(2, TankIds.DIR_LEFT, 0.0)
	west_end.roam.map_m = west_end.roam_map.lo_m
	var w := _view(west_end)
	assert_eq(TankWorldDraw.turn_lamps(w, west_end).size(), 1, "the west end's lamp in view")
	var middle := U.roam_state(2)
	var m := _view(middle)
	assert_eq(TankWorldDraw.turn_lamps(m, middle).size(), 0, "none in the middle of the road")


func test_the_roam_view_never_writes_the_state() -> void:
	var s := U.roam_state(4, TankIds.DIR_LEFT)
	var before := JSON.stringify(s.to_dict())
	var v := _view(s)
	U.run(v, 30, 1.0 / 60.0, false)
	assert_eq(JSON.stringify(s.to_dict()), before)
