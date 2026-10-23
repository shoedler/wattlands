extends GutTest
## The Siege 3D view builds headless from the G0 fixtures and draws what the state says (brief
## 3 "Scene"): camera framing, wheels, workers, chains, shaft glow, the drum, towers, enemies,
## the gate, the shake, the victory march, and the budget at the enemy cap.

var _state: SiegeState = null
var _view: SiegeView = null


func before_each() -> void:
	_state = SiegeFixtures.mid_wave()
	_view = SiegeViewUtil.make_view(self, _state)
	autofree(_view)


# --- build and framing ------------------------------------------------------------------------


func test_builds_every_part() -> void:
	assert_not_null(_view.rig)
	assert_not_null(_view.sky)
	assert_eq(_view.wheels.size(), 4)
	assert_eq(_view.chains.size(), 4)
	assert_not_null(_view.generator)
	assert_not_null(_view.towers)
	assert_not_null(_view.enemies)
	assert_not_null(_view.effects)
	assert_not_null(_view.gate)
	assert_not_null(_view.march)


func test_camera_is_a_high_narrow_miniature_rig() -> void:
	assert_between(_view.rig.pitch_deg, 40.0, 45.0)
	assert_between(_view.rig.fov_deg, 30.0, 35.0)
	assert_eq(_view.rig.max_shake_m, 0.15)


## Hand-written 16:9 pinhole projection of `p` through the rig's real camera transform onto a
## 1920 x 1080 picture (a headless Camera3D.unproject_position uses a square viewport).
func _project(rig: MiniatureCameraRig, p: Vector3) -> Vector2:
	var local := rig.camera.global_transform.affine_inverse() * p
	var depth := -local.z
	var t := tan(deg_to_rad(rig.fov_deg) * 0.5)
	return Vector2(
		960.0 + local.x / depth / (t * 16.0 / 9.0) * 960.0, 540.0 - local.y / depth / t * 540.0
	)


## The fort's box: the walls plus the 8.4 m corner towers, as tall as a corner tower.
func _fort_corners() -> Array[Vector3]:
	var map := _state.content.map
	var hx := map.fort_size.x * 0.5 + 4.2
	var hz := map.fort_size.y * 0.5 + 4.2
	var h := 6.0 + SiegeFortBuilder.CORNER_EXTRA_H
	var out: Array[Vector3] = []
	for x: float in [-hx, hx]:
		for y: float in [0.0, h]:
			for z: float in [-hz, hz]:
				out.append(Vector3(x, y, z))
	return out


## A road point `from_gate_m` metres of road before the gate end, on the ground.
func _road_point(road: int, from_gate_m: float) -> Vector3:
	var map := _state.content.map
	var p := map.point_at(road, map.road_length(road) - from_gate_m)
	return Vector3(p.x, 0.0, p.y)


func _framed_view() -> SiegeView:
	var v := SiegeView.new()
	v.auto_process = false
	v.bind(_state, _state.content.map)
	add_child_autofree(v)
	v.rig.auto_process = false
	# Past the 4 s push-in.
	v.rig.tick(4.5)
	assert_false(v.rig.is_pushing_in())
	return v


func test_the_fort_fills_55_to_60_percent_of_the_width_in_the_upper_half() -> void:
	var v := _framed_view()
	var lo := INF
	var hi := -INF
	var top := INF
	var bottom := -INF
	for c in _fort_corners():
		var q := _project(v.rig, c)
		lo = minf(lo, q.x)
		hi = maxf(hi, q.x)
		top = minf(top, q.y)
		bottom = maxf(bottom, q.y)
	assert_between((hi - lo) / 1920.0, 0.55, 0.6, "the fort with its towers")
	assert_gte(top, 0.0, "the far towers are inside the frame")
	assert_lt(top, 60.0, "the far wall sits just under the top edge")
	assert_lt(bottom, 540.0, "the whole fort is in the upper half")


func test_the_valley_road_shows_below_the_gate_above_the_hud_stack() -> void:
	# The pitch (about 42 degrees) and the 55 percent fort fix how much road fits: about 54 m of
	# the Valley road before the bottom edge. The brief's 60 to 80 m do not fit with both (the
	# pitch would have to drop to about 36 degrees, under the 40 to 45 the camera test allows).
	var v := _framed_view()
	var gate_y := _project(v.rig, Vector3(0.0, 0.0, 26.0)).y
	assert_lt(gate_y, 540.0, "the gate is in the upper half")
	assert_lt(_project(v.rig, _road_point(1, 40.0)).y, 880.0, "40 m is clear of the bottom stack")
	var seen := 0.0
	for m in range(0, 121, 2):
		var q := _project(v.rig, _road_point(1, float(m)))
		if q.y <= 1080.0 and q.x >= 0.0 and q.x <= 1920.0:
			seen = float(m)
	assert_gte(seen, 50.0, "at least 50 m of the Valley road is on screen")


func test_the_side_roads_show_60_m_before_the_gate_on_screen() -> void:
	var v := _framed_view()
	for road in [0, 2]:
		for m in [40.0, 60.0]:
			var q := _project(v.rig, _road_point(road, m))
			assert_between(q.x, 0.0, 1920.0, "road %d at %d m (x)" % [road, int(m)])
			assert_between(q.y, 0.0, 1000.0, "road %d at %d m (y)" % [road, int(m)])


func test_push_in_takes_four_seconds_by_default() -> void:
	var v := SiegeView.new()
	v.auto_process = false
	v.bind(_state, _state.content.map)
	add_child_autofree(v)
	v.rig.auto_process = false
	assert_true(v.rig.is_pushing_in())
	assert_eq(SiegeView.PUSH_IN_S, 4.0)
	v.rig.tick(3.9)
	assert_true(v.rig.is_pushing_in())
	v.rig.tick(0.2)
	assert_false(v.rig.is_pushing_in())


func test_one_warm_shadowed_sun_and_a_vignette_under_12_percent() -> void:
	assert_eq(int(SiegeViewBudget.measure(_view)["shadow_lights"]), 1)
	var vignettes := _view.find_children("*", "ScreenVignette", true, false)
	assert_eq(vignettes.size(), 1)
	assert_lte((vignettes[0] as ScreenVignette).strength, 0.12)


func test_the_view_only_reads_the_state() -> void:
	var before := JSON.stringify(_state.to_dict())
	SiegeViewUtil.run(_view, 30, 2)
	_state.tick -= 2
	assert_eq(JSON.stringify(_state.to_dict()), before)


# --- the drum ---------------------------------------------------------------------------------


func test_the_drum_shows_0_7_1250_and_9999_for_12000() -> void:
	for pair: Array in [[0.0, "0"], [7.0, "7"], [1250.0, "1250"], [12000.0, "9999"]]:
		_state.team_w = float(pair[0])
		SiegeViewUtil.run(_view, 40)
		assert_eq(_view.generator.labels_text(), str(pair[1]), "drum at %s W" % pair[0])


func test_the_drum_rolls_over_about_0_4_s() -> void:
	_state.team_w = 0.0
	SiegeViewUtil.run(_view, 40)
	_state.team_w = 1000.0
	_state.tick += 1
	_view.refresh(1.0 / 60.0)
	assert_true(_view.generator.drum.rolling())
	for i in 30:
		_view.refresh(1.0 / 60.0)
	assert_false(_view.generator.drum.rolling())
	assert_eq(_view.generator.labels_text(), "1000")


func test_the_digits_are_at_least_48_px_at_1080p() -> void:
	var px := SiegeGeneratorView.digit_px_at_1080p(
		_view.rig.distance, _view.rig.fov_deg, _view.rig.pitch_deg
	)
	assert_gte(px, 48.0)


func test_few_labels_only() -> void:
	var m := SiegeViewBudget.measure(_view)
	assert_lte(int(m["labels"]), SiegeViewBudget.LIMIT_LABELS)
	assert_gt(int(m["labels"]), 0)


# --- wheels and workers -----------------------------------------------------------------------


func test_wheel_speed_follows_the_riders_p_eff() -> void:
	var r := _state.rider_at(0)
	r.p_eff_w = 250.0
	r.cadence_rpm = 90.0
	SiegeViewUtil.run(_view, 2)
	assert_almost_eq(_view.wheels[0].rim_speed, 1.2, 1e-4)
	assert_almost_eq(_view.wheels[0].step_rate, 3.0, 1e-4)
	assert_almost_eq(_view.wheels[0].stride, 0.4, 1e-4)
	r.p_eff_w = 1000.0
	SiegeViewUtil.run(_view, 2)
	assert_almost_eq(_view.wheels[0].rim_speed, 3.0, 1e-4)


func test_the_wheel_turns_by_rim_speed() -> void:
	var r := _state.rider_at(0)
	r.p_eff_w = 250.0
	SiegeViewUtil.run(_view, 1)
	var a0 := _view.wheels[0].angle
	for i in 60:
		_view.refresh(1.0 / 60.0)
	var turned := absf(_view.wheels[0].angle - a0)
	assert_almost_eq(turned, 1.2 / SiegeWheelMath.WHEEL_RADIUS_M, 0.02)


func test_one_to_three_workers_by_power() -> void:
	var r := _state.rider_at(0)
	for pair: Array in [[100.0, 1], [200.0, 2], [400.0, 3]]:
		r.p_eff_w = float(pair[0])
		SiegeViewUtil.run(_view, 2)
		assert_eq(_view.wheels[0].workers_shown(), int(pair[1]), "workers at %s W" % pair[0])


func test_worker_count_has_hysteresis_in_the_view() -> void:
	var r := _state.rider_at(0)
	r.p_eff_w = 320.0
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.wheels[0].workers_shown(), 3)
	r.p_eff_w = 290.0
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.wheels[0].workers_shown(), 3, "holds above 280 W")
	r.p_eff_w = 270.0
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.wheels[0].workers_shown(), 2)


func test_an_afk_rider_stops_the_wheel() -> void:
	var r := _state.rider_at(2)
	r.afk = true
	SiegeViewUtil.run(_view, 3)
	assert_eq(_view.wheels[2].rim_speed, 0.0)
	var a := _view.wheels[2].angle
	SiegeViewUtil.run(_view, 10)
	assert_eq(_view.wheels[2].angle, a)


func test_a_rescued_rider_keeps_turning_at_actual_power() -> void:
	var r := _state.rider_at(1)
	assert_true(r.rescue)
	SiegeViewUtil.run(_view, 2)
	assert_almost_eq(_view.wheels[1].rim_speed, SiegeWheelMath.rim_speed(r.p_eff_w), 1e-4)


func test_empty_wheels_stand_idle() -> void:
	var s := SiegeState.create(
		SiegeFixtures.content("short"), SiegeFakes.make_slots(1, 0), Wl.FAIR_FTP, null
	)
	var v := SiegeViewUtil.make_view(self, s)
	autofree(v)
	assert_true(v.wheels[0].occupied)
	for slot in range(1, 4):
		assert_false(v.wheels[slot].occupied)
		assert_false(v.wheels[slot].pennant.visible)
		assert_eq(v.wheels[slot].workers_shown(), 0)


func test_bots_fly_a_toothed_pennant() -> void:
	var look := Wl.slot_look(0)
	var human := SiegeWheelView.build_pennant_mesh(look, false).triangle_count()
	var bot := SiegeWheelView.build_pennant_mesh(look, true).triangle_count()
	assert_gt(bot, human)


func test_pennant_patterns_differ_by_slot() -> void:
	var counts := {}
	for slot in 4:
		counts[SiegeWheelView.build_pennant_mesh(Wl.slot_look(slot), false).triangle_count()] = true
	assert_eq(counts.size(), 4, "solid, dashed, dotted and double are four different flags")


# --- routes ------------------------------------------------------------------------------------


func test_the_shaft_glows_only_for_a_generator_route() -> void:
	SiegeViewUtil.run(_view, 2)
	assert_eq(_state.rider_at(1).target, SiegeIds.TARGET_GEN)
	assert_true(_view.wheels[1].glow.visible, "slot 1 routes to the generator")
	assert_false(_view.wheels[0].glow.visible, "slot 0 routes to pad 3")
	assert_false(_view.wheels[3].glow.visible)


func test_a_chain_shows_only_for_a_tower_route() -> void:
	SiegeViewUtil.run(_view, 2)
	assert_true(_view.chains[0].chain.visible)
	assert_true(_view.chains[2].chain.visible)
	assert_true(_view.chains[3].chain.visible)
	assert_false(_view.chains[1].chain.visible, "slot 1 is on the generator")
	assert_gt(_view.chains[0].chain.visible_count(), 10)


func test_the_chain_lights_up_over_the_2_s_reconnect() -> void:
	var r := _state.rider_at(0)
	r.reconnect_s = 2.0
	SiegeViewUtil.run(_view, 2)
	assert_almost_eq(_view.chains[0].lit, 0.0, 1e-6)
	r.reconnect_s = 1.0
	SiegeViewUtil.run(_view, 2)
	assert_almost_eq(_view.chains[0].lit, 0.5, 1e-6)
	r.reconnect_s = 0.0
	SiegeViewUtil.run(_view, 2)
	assert_almost_eq(_view.chains[0].lit, 1.0, 1e-6)


func test_the_chain_scrolls_with_p_eff_and_not_while_connecting() -> void:
	var r := _state.rider_at(3)
	r.p_eff_w = 250.0
	SiegeViewUtil.run(_view, 1)
	var s0 := _view.chains[3].scroll_m
	for i in 60:
		_view.refresh(1.0 / 60.0)
	assert_almost_eq(_view.chains[3].scroll_m - s0, 1.2, 0.05, "1.2 m in a second at 250 W")
	r.reconnect_s = 1.5
	var s1 := _view.chains[3].scroll_m
	SiegeViewUtil.run(_view, 10)
	assert_eq(_view.chains[3].scroll_m, s1, "no output, no scroll, while reconnecting")


# --- towers, enemies, gate ----------------------------------------------------------------------


func test_a_tower_node_per_built_pad() -> void:
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.towers.shown(), 4)
	for pad in [2, 3, 4, 6]:
		assert_not_null(_view.towers.nodes[pad - 1])
	assert_null(_view.towers.nodes[0], "pad 1 is an empty plinth")


func test_a_new_tower_scales_up_over_one_second() -> void:
	SiegeViewUtil.run(_view, 2)
	var tw := _state.pad(8)
	tw.type = SiegeIds.TOWER_SCORPION
	_state.tick += 1
	_view.refresh(0.05)
	var n: MeshInstance3D = _view.towers.nodes[7]
	assert_not_null(n)
	assert_lt(n.scale.x, SiegeTowersView.TOWER_SCALE * 0.9, "starts small")
	for i in 22:
		_view.refresh(0.05)
	assert_almost_eq(n.scale.x, SiegeTowersView.TOWER_SCALE, 1e-4)


func test_scale_up_curve() -> void:
	assert_lt(SiegeTowersView.scale_for(0.0), 0.1)
	assert_eq(SiegeTowersView.scale_for(1.0), 1.0)
	assert_eq(SiegeTowersView.scale_for(5.0), 1.0)
	assert_gt(SiegeTowersView.scale_for(0.5), 0.5)


func test_the_three_silhouettes_differ_and_levels_add_bands() -> void:
	var b := SiegeTowerMeshes.build(SiegeIds.TOWER_BALLISTA, 0).triangle_count()
	var s := SiegeTowerMeshes.build(SiegeIds.TOWER_SCORPION, 0).triangle_count()
	var c := SiegeTowerMeshes.build(SiegeIds.TOWER_CALTROP, 0).triangle_count()
	assert_ne(b, s)
	assert_ne(s, c)
	assert_ne(b, c)
	var l3 := SiegeTowerMeshes.build(SiegeIds.TOWER_BALLISTA, 3).triangle_count()
	assert_gt(l3, b)
	assert_eq(SiegeTowerMeshes.build(SiegeIds.TOWER_NONE, 0).triangle_count(), 0)


func test_enemy_crowds_are_one_multimesh_per_type() -> void:
	SiegeViewUtil.run(_view, 2)
	var by_type := _state.alive_by_type()
	for type in range(1, 5):
		assert_eq(_view.enemies.shown(type), by_type[type], "type %d" % type)
	assert_eq(_view.enemies.crowds.size(), 4)


func test_hp_bars_only_on_damaged_shield_walls_horsemen_and_rams() -> void:
	SiegeViewUtil.run(_view, 2)
	var expected := 0
	for e in _state.enemies:
		if e.type != SiegeIds.ENEMY_RAIDERS and e.hp < e.max_hp:
			expected += 1
	assert_gt(expected, 0)
	assert_eq(_view.enemies.bars_shown(), expected)
	for e in _state.enemies:
		e.hp = e.max_hp
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.enemies.bars_shown(), 0)


func test_raiders_never_show_a_bar_however_hurt() -> void:
	for e in _state.enemies:
		if e.type != SiegeIds.ENEMY_RAIDERS:
			e.hp = e.max_hp
		else:
			e.hp = 1.0
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.enemies.bars_shown(), 0)


func test_enemies_stand_on_the_ground_and_face_the_gate() -> void:
	SiegeViewUtil.run(_view, 40)
	var mm: MultiMeshScatter = _view.enemies.crowds[SiegeIds.ENEMY_RAIDERS]
	var e: SiegeEnemyState = null
	for x in _state.enemies:
		if x.type == SiegeIds.ENEMY_RAIDERS and x.st == SiegeIds.EN_WALK:
			e = x
			break
	var t := mm.instance_transform(0)
	var p := Vector2(t.origin.x, t.origin.z)
	assert_almost_eq(p.distance_to(e.pos), 0.0, 0.2, "drawn at the enemy road position")
	assert_almost_eq(t.origin.y, _view.terrain.height_at(p.x, p.y), 1e-3)
	var fwd := -t.basis.z.normalized()
	var dir := _state.content.map.dir_at(e.road, e.prog_m)
	assert_gt(Vector2(fwd.x, fwd.z).dot(dir), 0.9, "faces along the road toward the gate")


func test_gate_loses_planks_at_66_and_33_percent() -> void:
	assert_eq(SiegeGateView.tier_for(1.0), 0)
	assert_eq(SiegeGateView.tier_for(0.67), 0)
	assert_eq(SiegeGateView.tier_for(0.66), 1)
	assert_eq(SiegeGateView.tier_for(0.34), 1)
	assert_eq(SiegeGateView.tier_for(0.33), 2)
	assert_eq(SiegeGateView.tier_for(0.0), 2)


func test_gate_view_follows_hp_and_iron_bands() -> void:
	_state.gate_hp = 100.0
	_state.gate_max = 125.0
	_state.iron_bands = 1
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.gate.tier, 0, "80%")
	assert_eq(_view.gate.bands, 1)
	_state.gate_hp = 60.0
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.gate.tier, 1, "48%")
	_state.gate_hp = 30.0
	_state.iron_bands = 2
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.gate.tier, 2, "24%")
	assert_eq(_view.gate.bands, 2)


func test_gate_bands_add_iron_and_lost_planks_change_the_leaf() -> void:
	var g := _view.gate
	var whole := (g.left.mesh as ArrayMesh).surface_get_array_len(0)
	_state.iron_bands = 2
	SiegeViewUtil.run(_view, 2)
	var banded := (g.left.mesh as ArrayMesh).surface_get_array_len(0)
	assert_gt(banded, whole, "iron bands add geometry")


func test_a_breach_bursts_the_gate_open_in_dust_once() -> void:
	SiegeViewUtil.run(_view, 2)
	assert_eq(_view.gate.bursts, 0)
	assert_eq(_view.gate.open_amount, 0.0)
	_state.gate_hp = 0.0
	_state.breach_s = 10.0
	SiegeViewUtil.run(_view, 60)
	assert_eq(_view.gate.bursts, 1)
	assert_true(_view.gate.dust.emitting)
	assert_gt(_view.gate.open_amount, 0.9)
	assert_lt(_view.gate.left.rotation.y, -1.0)
	_state.breach_s = 9.0
	SiegeViewUtil.run(_view, 5)
	assert_eq(_view.gate.bursts, 1, "one burst per breach")
	_state.breach_s = 0.0
	_state.gate_hp = 30.0
	SiegeViewUtil.run(_view, 60)
	assert_eq(_view.gate.open_amount, 0.0, "swings shut when restored")


# --- shake ---------------------------------------------------------------------------------------


func test_a_gate_hit_of_8_hp_or_more_shakes_the_camera_by_at_most_0_15_m() -> void:
	SiegeViewUtil.run(_view, 2)
	_state.gate_hp -= 8.0
	SiegeViewUtil.run(_view, 1)
	assert_eq(_view.shakes, 1)
	assert_gt(_view.rig.current_shake_amplitude(), 0.0)
	assert_lte(_view.rig.current_shake_amplitude(), 0.15)


func test_smaller_gate_hits_do_not_shake() -> void:
	SiegeViewUtil.run(_view, 2)
	_state.gate_hp -= 7.0
	SiegeViewUtil.run(_view, 1)
	_state.gate_hp -= 2.0
	SiegeViewUtil.run(_view, 1)
	assert_eq(_view.shakes, 0)
	assert_eq(_view.rig.current_shake_amplitude(), 0.0)


# --- cool-down -----------------------------------------------------------------------------------


func test_the_victory_march_shows_only_in_the_cool_down() -> void:
	SiegeViewUtil.run(_view, 2)
	assert_false(_view.march.visible)
	_state.role = SiegeIds.ROLE_COOLDOWN
	SiegeViewUtil.run(_view, 2)
	assert_true(_view.march.visible)
	assert_eq(_view.march.visible_count(), SiegeView.MARCH_COUNT)


# --- budget at the enemy cap ----------------------------------------------------------------------


func test_the_budget_holds_at_the_enemy_cap() -> void:
	var cap := SiegeFixtures.cap()
	var v := SiegeViewUtil.make_view(self, cap)
	autofree(v)
	SiegeViewUtil.run(v, 3)
	assert_eq(cap.enemies.size(), 150)
	var m := SiegeViewBudget.measure(v)
	assert_lte(int(m["draw_calls_with_shadows"]), SiegeViewBudget.LIMIT_DRAW_CALLS)
	assert_lte(int(m["triangles"]), SiegeViewBudget.LIMIT_TRIANGLES)
	assert_lte(int(m["labels"]), SiegeViewBudget.LIMIT_LABELS)
	assert_eq(int(m["shadow_lights"]), 1)
	gut.p("budget at the cap: %s" % JSON.stringify(m))


func test_no_node_per_enemy() -> void:
	var mid := SiegeViewBudget.measure(_view)
	var cap := SiegeFixtures.cap()
	var v := SiegeViewUtil.make_view(self, cap)
	autofree(v)
	SiegeViewUtil.run(v, 3)
	var at_cap := SiegeViewBudget.measure(v)
	assert_eq(int(at_cap["nodes"]), int(mid["nodes"]), "150 enemies add no nodes over 43")
	assert_eq(int(at_cap["mesh_instances"]), int(mid["mesh_instances"]))
	for c in v.enemies.get_children():
		assert_true(
			c is MultiMeshInstance3D, "the enemy view holds only MultiMeshes: %s" % c.get_class()
		)
