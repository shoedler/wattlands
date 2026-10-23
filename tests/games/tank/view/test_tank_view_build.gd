extends GutTest
## Every tank's view built headless from the fixtures (Bulwark, Rampart, Citadel) and stepped a few
## frames with no errors: the rig and its rooms, the planes, enemies, shells, the Behemoth and the
## effects; the view is a Node2D that only reads the state.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func test_every_tank_builds_and_steps_headless_from_every_fixture() -> void:
	for crew in [1, 2, 3]:
		for kind in ["state", "gun_line", "boss"]:
			var state := U.fixture(kind, crew)
			var v := U.view_of(self, state)
			U.run(v, 12)
			var label := "crew %d %s" % [crew, kind]
			assert_not_null(v.rig, label)
			assert_eq(v.rig.tank, TankIds.tank_for_crew(crew), label)
			assert_eq(v.rig.rooms.size(), crew, "%s: one room per engine" % label)
			assert_eq(v.frames, 13, label)


func test_the_view_is_a_node2d_for_the_pixel_viewport_and_keeps_the_game() -> void:
	var g := U.make_game(TankFixtures.state(3))
	autofree(g)
	var v := g.make_view()
	autofree(v)
	assert_is(v, Node2D)
	assert_eq((v as TankView).game, g)


func test_planes_are_the_brief_s_parallax_factors_and_mirror_alternate() -> void:
	var v := U.view_of(self, TankFixtures.state(2))
	var b := v.backdrop
	assert_almost_eq(b.sky.factor, 0.05, 1e-6)
	assert_almost_eq(b.hills.factor, 0.2, 1e-6)
	assert_almost_eq(b.near.factor, 0.5, 1e-6)
	assert_almost_eq(b.ground.factor, 1.0, 1e-6)
	assert_almost_eq(b.debris.factor, 1.3, 1e-6)
	for s: ParallaxStrip in [b.sky, b.hills, b.near, b.ground, b.debris]:
		assert_true(s.mirror_alternate, s.name)
		assert_false(s.auto_process, s.name)
	assert_eq(b.front.get_parent(), v, "the debris draws above the world")


func test_the_hull_stands_on_the_ground_line_with_its_rear_at_x_16() -> void:
	for crew in [1, 2, 3]:
		var v := U.view_of(self, TankFixtures.state(crew))
		var s: TankState = v.game.state
		assert_almost_eq(v.rig.base_pos.x, float(TankConst.REAR_SCREEN_X), 1e-6)
		assert_almost_eq(
			v.rig.base_pos.y + float(s.hull.hull_h),
			float(TankConst.GROUND_Y - 10),
			1e-6,
			"crew %d" % crew
		)


func test_the_camera_follows_the_hull() -> void:
	var s := TankFixtures.state(1)
	var v := U.view_of(self, s)
	assert_almost_eq(v.cam_x, s.camera_x(), 1e-3)
	s.hull.x_px += 40.0
	s.tick += 1
	U.run(v, 60)
	assert_almost_eq(v.cam_x, s.camera_x(), 0.5, "caught up with the hull after a second")


func test_a_view_without_state_does_nothing() -> void:
	var g := TankGame.new()
	autofree(g)
	var v := TankView.new()
	v.game = g
	v.auto_process = false
	add_child_autofree(v)
	v.advance(0.02)
	assert_null(v.rig)


func test_no_per_frame_texture_creation() -> void:
	var v := U.view_of(self, TankFixtures.boss(3))
	var builds := TankBlur.builds
	var cached := TankBlur.cached_count()
	U.run(v, 90)
	assert_eq(TankBlur.builds, builds, "no blur runs after load")
	assert_eq(TankBlur.cached_count(), cached)
