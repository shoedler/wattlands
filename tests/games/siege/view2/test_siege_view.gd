extends GutTest
## SiegeView bound to fixture states (tests/games/siege/fixtures): it builds headless at 1 and 4
## riders and at the 150-enemy cap, and drives the primitives by the view's formulas (wheels,
## walkers, lit paths, gate stages, the tar, the crowd, the shots, the march home).

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")


func _game(state: SiegeState, humans: int = 3, bots: int = 1, role: String = Wl.SOLO) -> SiegeGame:
	var g := F.make_game(F.make_ctx(humans, bots, "vo2", role, 1))
	g.state = state
	g.content = state.content
	return g


func _view(g: SiegeGame) -> SiegeView:
	var v := g.make_view() as SiegeView
	add_child_autofree(v)
	return v


func test_view_builds_at_four_riders_from_the_fixture() -> void:
	var st := FIX.mid_wave()
	var g := _game(st)
	var v := _view(g)
	v.update(0.05)
	assert_not_null(v.world)
	assert_eq(v.machines.get_parent(), v)
	assert_eq(v.crowd.drawn, st.enemies.size())
	assert_eq(v.machines.dropped, 0)
	# every rider's wheel shows a rider; the routes follow their targets
	for slot in 4:
		assert_eq(v.machines.wheel_rider[slot], 1)
		assert_eq(v.machines.route[slot], st.rider_at(slot).target)
	assert_true(v.tilt.enabled, "tilt-shift on by the rider's default option")
	F.free_game(g)


func test_view_builds_with_one_rider_and_empty_slots_show_timber() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var g := _game(st, 1, 0)
	var v := _view(g)
	v.update(0.05)
	assert_eq(v.machines.wheel_rider[0], 1)
	for slot in [1, 2, 3]:
		assert_eq(v.machines.wheel_rider[slot], 0, "slot %d has no rider" % slot)
		assert_eq(v.machines.route[slot], -1)
		assert_eq(v.walker_count[slot], 0)
	F.free_game(g)


func test_view_draws_the_150_enemy_cap() -> void:
	var st := FIX.cap()
	var g := _game(st)
	var v := _view(g)
	var t0 := Time.get_ticks_usec()
	v.update(0.016)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_eq(v.crowd.drawn, SiegeV2Crowd.MAX_ENEMIES)
	assert_eq(v.crowd.dropped, 0)
	gut.p("view update at 150 enemies: %.2f ms" % ms)
	assert_lt(ms, 40.0)
	F.free_game(g)


func test_view_binds_without_a_game() -> void:
	var st := FIX.mid_wave()
	var v := SiegeView.new()
	v.bind(st, st.path)
	add_child_autofree(v)
	v.update(0.05)
	assert_eq(v.state, st)
	assert_eq(v.crowd.drawn, st.enemies.size())


func test_wheel_speed_and_walkers_follow_p_eff() -> void:
	assert_almost_eq(SiegeViewMath.rim_speed(250.0), 1.2, 1e-6)
	assert_almost_eq(SiegeViewMath.rim_speed(125.0), 0.6, 1e-6)
	assert_almost_eq(SiegeViewMath.rim_speed(2000.0), 3.0, 1e-6, "capped at 3 m/s")
	assert_eq(SiegeViewMath.rim_speed(-10.0), 0.0)
	assert_almost_eq(SiegeViewMath.wheel_deg_per_s(250.0, 7.0), rad_to_deg(1.2 / 7.0), 1e-4)
	assert_eq(SiegeViewMath.walkers_for(0.0, 0), 1)
	assert_eq(SiegeViewMath.walkers_for(149.0, 1), 1)
	assert_eq(SiegeViewMath.walkers_for(150.0, 1), 2)
	assert_eq(SiegeViewMath.walkers_for(300.0, 2), 3)
	# 20 W hysteresis on the way down
	assert_eq(SiegeViewMath.walkers_for(135.0, 2), 2)
	assert_eq(SiegeViewMath.walkers_for(129.0, 2), 1)
	assert_eq(SiegeViewMath.walkers_for(285.0, 3), 3)
	assert_eq(SiegeViewMath.walkers_for(279.0, 3), 2)
	assert_eq(SiegeViewMath.walkers_for(285.0, 2), 2, "no hysteresis on the way up")


func test_wheels_turn_by_watts_in_the_view() -> void:
	var st := SiegeKit.state("short", 2, 0)
	st.rider_at(0).p_eff_w = 250.0
	st.rider_at(1).p_eff_w = 0.0
	var g := _game(st, 2, 0)
	var v := _view(g)
	var a0 := v.wheel_deg[0]
	var a1 := v.wheel_deg[1]
	for _i in 10:
		v.update(0.1)
	assert_almost_eq(fposmod(v.wheel_deg[0] - a0, 360.0), rad_to_deg(1.2 / 7.0), 0.01)
	assert_almost_eq(v.wheel_deg[1], a1, 1e-6, "no watts, no turn")
	assert_eq(v.walker_count[0], 2)
	assert_eq(v.walker_count[1], 1)
	F.free_game(g)


func test_paths_light_to_the_target_through_the_reconnect() -> void:
	var st := SiegeKit.state("short", 2, 0)
	var r := st.rider_at(0)
	r.target = SiegeIds.STATION_ONAGER
	r.reconnect_s = 1.5
	assert_eq(SiegeViewMath.lit_station(st, r), SiegeIds.STATION_ONAGER, "lit while reconnecting")
	r.reconnect_s = 0.0
	assert_eq(SiegeViewMath.lit_station(st, r), SiegeIds.STATION_ONAGER)
	r.connected = false
	assert_eq(SiegeViewMath.lit_station(st, r), -1, "a dropped rider's path goes dark")
	r.connected = true
	st.role = SiegeIds.ROLE_BREAK
	assert_eq(SiegeViewMath.lit_station(st, r), SiegeIds.STATION_MINE, "breaks feed the mine")
	assert_eq(SiegeViewMath.lit_station(st, null), -1)
	st.role = SiegeIds.ROLE_WAVE
	var g := _game(st, 2, 0)
	var v := _view(g)
	v.update(0.05)
	assert_eq(v.machines.route[0], SiegeIds.STATION_ONAGER)
	assert_eq(v.machines.driver(SiegeIds.STATION_ONAGER), 0)
	assert_eq(v.machines.route[1], SiegeIds.STATION_MINE)
	F.free_game(g)


func test_gate_curtain_coat_and_rack_stages() -> void:
	assert_eq(SiegeViewMath.gate_stage(130.0, 130.0), 0)
	assert_eq(SiegeViewMath.gate_stage(80.0, 130.0), 1)
	assert_eq(SiegeViewMath.gate_stage(40.0, 130.0), 2)
	assert_eq(SiegeViewMath.gate_stage(0.0, 130.0), 3)
	assert_eq(SiegeViewMath.gate_stage(100.0, 130.0, 4.0), 3, "a Breach shows the gate broken")
	assert_eq(SiegeViewMath.fill_stage(0.0), 0)
	assert_eq(SiegeViewMath.fill_stage(0.2), 1)
	assert_eq(SiegeViewMath.fill_stage(0.5), 2)
	assert_eq(SiegeViewMath.fill_stage(1.0), 3)
	assert_eq(SiegeViewMath.rack_mask(1, 0.2), 7 & ~1, "the rack fired last shows empty")
	assert_eq(SiegeViewMath.rack_mask(0, 0.2), 7 & ~4)
	assert_eq(SiegeViewMath.rack_mask(2, 0.8), 7)
	var st := FIX.mid_wave()
	var g := _game(st)
	var v := _view(g)
	v.update(0.05)
	assert_eq(v.machines.gate_stage, SiegeViewMath.gate_stage(st.gate_hp, st.gate_max, st.breach_s))
	assert_eq(v.machines.curtain_stage, SiegeViewMath.curtain_stage(st.tar))
	assert_eq(v.machines.coat_stage, 3)
	F.free_game(g)


func test_enemies_face_their_travel_and_retreat_turns_them() -> void:
	var st := SiegeKit.state("short")
	var yaw := SiegeViewMath.enemy_yaw(st.path, 100.0, SiegeIds.EN_WALK)
	var d := st.path.dir_at(100.0)
	assert_almost_eq(yaw, rad_to_deg(atan2(d.y, d.x)), 1e-4)
	assert_almost_eq(
		SiegeViewMath.enemy_yaw(st.path, 100.0, SiegeIds.EN_RETREAT), yaw + 180.0, 1e-4
	)


func test_shot_cues_replay_in_the_view() -> void:
	var st := FIX.mid_wave()
	var g := _game(st)
	var v := _view(g)
	var o := st.path.muzzle(SiegeIds.STATION_BALLISTA, 128.0)
	var target := st.path.point_at(330.0)
	var vel := SiegeBallistics.solve_angle(o, target, 70.0, 0.0004)
	var ev := SiegeEvents.shot(
		st.tick,
		1,
		SiegeIds.SHOT_BOLT,
		SiegeEvents.quantize_o(o),
		SiegeEvents.quantize_v(vel),
		1,
		77
	)
	g.cue.emit(SiegeIds.EV_SHOT, ev)
	assert_eq(v.shots.shots.size(), 1)
	v.update(0.02)
	assert_eq(v.shots.in_flight(), 1)
	assert_true(v.audio.played.has("ballista_twang"))
	F.free_game(g)


func test_client_view_draws_enemies_from_the_history() -> void:
	var ctx := F.make_ctx(3, 1, "vo2", Wl.CLIENT, 2)
	var g := F.make_game(ctx)
	g.apply_snapshot(Protocol.apply_int_fields(FIX.snapshot(), g.int_fields()["snapshot"]))
	var v := _view(g)
	v.update(0.05)
	assert_eq(v.crowd.drawn, g.state.enemies.size())
	assert_almost_eq(v.clock_s, g.history.render_t, 1e-6, "a client draws on the history's clock")
	F.free_game(g)


func test_victory_march_in_the_cooldown() -> void:
	var st := SiegeKit.state("short", 1, 0)
	st.role = SiegeIds.ROLE_COOLDOWN
	st.enemies.clear()
	var g := _game(st, 1, 0)
	var v := _view(g)
	for _i in 30:
		v.update(0.1)
	assert_gt(v.march_s, 2.0)
	assert_gt(v.crowd.drawn, 0, "the fort's people march out")
	F.free_game(g)
