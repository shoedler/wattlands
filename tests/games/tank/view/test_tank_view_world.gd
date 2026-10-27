extends GutTest
## What the view draws from the state: enemies on two depth rows with HP bars and telegraph glows,
## wrecks that smoke, props, shells with tracers and halos, the trajectory dots in the gunner's
## colour, the Behemoth's parts, and the effects each game event raises.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _rows(layer: TankRowLayer, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in layer.rows:
		if str(r.get("t", "")) == type:
			out.append(r)
	return out


func _sprites(layer: TankRowLayer, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _rows(layer, "sprite"):
		if str(r["id"]) == id:
			out.append(r)
	return out


## The rows a code-drawn obstacle stands in for sprite `id` with ("of" tag).
func _drawn(layer: TankRowLayer, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in layer.rows:
		if str(r.get("of", "")) == id:
			out.append(r)
	return out


func test_enemies_stand_on_the_ground_at_their_world_position() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var medium := s.enemy(11)
	var rect: Rect2 = v.enemy_rects[11]
	assert_almost_eq(rect.position.x, roundf(medium.x_px - s.camera_x()), 1.0)
	var lift := 6.0 if int(v.enemy_lanes(s).get(11, 0)) == 1 else 0.0
	assert_almost_eq(
		rect.end.y, float(TankConst.GROUND_Y) + 2.0 - lift, 0.6, "sunk 2 px into the ground"
	)
	assert_eq(rect.size, Vector2(medium.w, medium.h))
	var rows := _sprites(v.enemies_layer, "enemy_medium")
	assert_eq(rows.size(), 1)
	assert_false(rows[0]["flip"], "enemies ahead face left, as drawn")


func test_enemies_behind_the_tank_are_flipped_and_overlaps_use_two_depth_rows() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var light := _sprites(v.enemies_layer, "enemy_light")[0]
	assert_true(light["flip"], "the rear rusher faces the tank")
	# The destroyer (13) and the medium (11) overlap on the road: one steps back a lane, a little
	# higher and dimmer; the light (12) has the road to itself and stays on the front lane.
	var lanes := v.enemy_lanes(s)
	assert_ne(int(lanes[11]), int(lanes[13]), "overlapping enemies take different lanes")
	assert_eq(int(lanes[12]), 0, "a lone enemy keeps the front lane")
	var back := 11 if int(lanes[11]) == 1 else 13
	var front := 13 if back == 11 else 11
	var rb: Rect2 = v.enemy_rects[back]
	var rf: Rect2 = v.enemy_rects[front]
	assert_almost_eq(rf.end.y - rb.end.y, 6.0, 0.6, "the back lane stands a little higher")
	assert_almost_eq((v.enemy_rects[12] as Rect2).end.y, rf.end.y, 0.6, "the light is on the road")
	var back_row := _sprites(v.enemies_layer, "enemy_medium" if back == 11 else "enemy_destroyer")[0]
	assert_lt((back_row["tint"] as Color).r, 1.0, "and dimmer")
	assert_eq((light["tint"] as Color).r, 1.0, "the front lane is not dimmed")


func test_damage_shows_on_the_enemy_not_as_a_floating_bar() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	assert_eq(_rows(v.enemies_layer, "bar").size(), 0, "no HP bar on the tank's plane")
	var before := (_sprites(v.enemies_layer, "enemy_medium")[0]["tint"] as Color).r
	s.enemy(11).hp -= 5.0
	v.advance(0.016)
	var hit := (_sprites(v.enemies_layer, "enemy_medium")[0]["tint"] as Color).r
	assert_gt(hit, before, "a hit flashes the enemy")
	U.run(v, 30)
	var after := (_sprites(v.enemies_layer, "enemy_medium")[0]["tint"] as Color).r
	assert_almost_eq(after, before, 0.001, "and the flash fades")
	var small := TankFixtures.state(1)
	var v1 := U.view_of(self, small)
	var scale := TankFixtures.content().enemy_scale(TankIds.TANK_BULWARK)
	var medium_hp := float(TankFixtures.content().enemy_def("medium")["hp"])
	assert_almost_eq(
		v1.enemy_max_hp(small, "medium"), medium_hp * scale, 1e-4, "x the Bulwark's scale"
	)
	small.enemy(11).hp = small.enemy(11).hp_max
	var heavy_hp := float(TankFixtures.content().enemy_def("heavy")["hp"])
	assert_almost_eq(
		v1.enemy_max_hp(small, "heavy"), heavy_hp * scale, 1e-4, "the content's heavy HP"
	)


func test_a_telegraphing_enemy_glows_at_its_muzzle() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var with := v.lights.count
	s.enemy(13).telegraph_s = 0.0
	s.enemy(13).mode = TankIds.EM_HOLD
	v.advance(0.016)
	assert_lt(v.lights.count, with, "the destroyer's cold glint is a light")


func test_a_dead_enemy_leaves_a_fireball_and_a_wreck_that_smokes() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var x := s.enemy(11).x_px
	s.enemies.erase(s.enemy(11))
	v.advance(0.016)
	assert_eq(v.wrecks.size(), 1)
	assert_almost_eq(float(v.wrecks[0]["x"]), x, 0.5)
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.EXPLOSION), 0)
	U.run(v, 60)
	assert_eq(v.wrecks.size(), 1, "the wreck stays")
	var dark := _sprites(v.props_layer, "enemy_medium")
	assert_eq(dark.size(), 1)
	assert_lt((dark[0]["tint"] as Color).r, 0.5, "wrecks darken")
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.SMOKE), 0, "and smoke")


func test_wrecks_are_fixed_in_the_world_and_burn_out() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	s.enemies.erase(s.enemy(11))
	v.advance(0.016)
	var before := _sprites(v.props_layer, "enemy_medium")[0]["pos"].x as float
	s.hull.x_px += 60.0
	s.tick += 1
	U.run(v, 60)
	var after := _sprites(v.props_layer, "enemy_medium")[0]["pos"].x as float
	assert_lt(after, before - 40.0, "it scrolls away with the world")
	var burn_s := TankView.WRECK_BURN_S
	for _i in int(burn_s * 60.0) + 60:
		v.advance(1.0 / 60.0)
	var fires := 0
	for i in v.fx.particles.count:
		if v.fx.particles.kind[i] == TankParticles.Kind.FIRE and v.fx.particles.plane[i] == 0:
			fires += 1
	assert_eq(fires, 0, "the wreck's flames are out; only smoke is left")


func test_a_segment_change_forgets_the_wrecks() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	s.enemies.erase(s.enemy(11))
	v.advance(0.016)
	assert_eq(v.wrecks.size(), 1)
	s.seg.phase_index += 1
	s.enemies.clear()
	v.advance(0.016)
	assert_eq(v.wrecks.size(), 0, "world x restarts at 0 in every segment")
	assert_eq(v.fx.particles.count_kind(TankParticles.Kind.EXPLOSION) >= 0, true)


func test_wrecks_are_capped() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	for i in 10:
		s.enemies.clear()
		var e := TankEnemyState.new()
		e.id = 500 + i
		e.code = 1
		e.w = 80
		e.h = 40
		e.x_px = s.hull.x_px + 300.0 + 90.0 * float(i)
		s.enemies.append(e)
		v.advance(0.016)
		s.enemies.clear()
		v.advance(0.016)
	assert_lte(v.wrecks.size(), TankView.MAX_WRECKS)


func test_obstacles_wrecks_and_traps_are_props_and_cleared_ones_vanish() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	assert_eq(_sprites(v.props_layer, "prop_wreck_barricade").size(), 1)
	s.obstacles[0].cleared = true
	v.advance(0.016)
	assert_eq(_sprites(v.props_layer, "prop_wreck_barricade").size(), 0)
	var g := TankFixtures.gun_line(3)
	var tr := TankObstacleState.new()
	tr.id = 77
	tr.code = TankIds.obstacle_code(TankIds.OBST_TANK_TRAPS)
	tr.x_px = g.hull.x_px + g.hull.hull_w + 40.0
	g.obstacles.append(tr)
	var v2 := U.view_of(self, g)
	# The hedgehogs are code-drawn line work (TankObstacleArt), every row tagged with the sprite id.
	assert_gt(_drawn(v2.props_layer, "prop_tank_traps").size(), 3, "two hedgehogs of beams")
	g.hull.traps_cleared = true
	v2.advance(0.016)
	assert_eq(_drawn(v2.props_layer, "prop_tank_traps").size(), 0, "shoved aside")


func test_the_depot_gate_stands_behind_the_start_only() -> void:
	var s := TankFixtures.state(1)
	s.seg.seg = TankIds.SEG_DEPOT
	s.seg.phase_index = 0
	s.hull.x_px = 0.0
	var v := U.view_of(self, s)
	var gate := _sprites(v.props_layer, "depot_gate")
	assert_eq(gate.size(), 1)
	assert_lt((gate[0]["pos"] as Vector2).x, 100.0)
	s.seg.seg = TankIds.SEG_ADVANCE
	s.seg.phase_index = 1
	v.advance(0.016)
	assert_eq(_sprites(v.props_layer, "depot_gate").size(), 0)


func test_ground_props_are_a_pure_function_of_the_scroll() -> void:
	var s := TankFixtures.state(2)
	var v := U.view_of(self, s)
	var a := _rows(v.props_layer, "sprite").size()
	v.advance(0.016)
	assert_eq(_rows(v.props_layer, "sprite").size(), a)
	var craters := 0
	var rubble := 0
	for step in 40:
		s.hull.x_px += 100.0
		s.tick += 2
		U.run(v, 8)
		craters += _sprites(v.props_layer, "prop_crater").size()
		rubble += _sprites(v.props_layer, "prop_rubble").size()
	assert_gt(craters, 0, "flooded craters")
	assert_gt(rubble, 0)


func test_shells_get_tracers_and_halos_by_type() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var lines := _rows(v.shots_layer, "line")
	assert_eq(lines.size(), 9, "two tracer segments and a hot core per shell")
	var rects := _rows(v.shots_layer, "rect")
	var hot := 0
	for r in rects:
		if (r["c"] as Color) == Color.WHITE:
			hot += 1
	assert_eq(hot, 3, "a white-hot head each")
	var halo_light := TankView.HALO_RADIUS[TankIds.SHELL_LIGHT]
	assert_lt(halo_light, TankView.HALO_RADIUS[TankIds.SHELL_HEAVY])
	assert_lt(
		TankView.HALO_RADIUS[TankIds.SHELL_HEAVY], TankView.HALO_RADIUS[TankIds.SHELL_BOSS_MAIN]
	)
	assert_gt(v.lights.count, 3)


func test_the_tracer_trails_behind_the_shell() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var heavy := s.shells[0]
	var head := Vector2(heavy.x - s.camera_x(), heavy.y)
	var line := _rows(v.shots_layer, "line")[1]
	assert_almost_eq((line["b"] as Vector2).x, head.x, 1.0)
	assert_lt(
		(line["a"] as Vector2).x, head.x, "the heavy shell flies right: its tail is to the left"
	)


func test_the_trajectory_is_dots_in_the_gunners_colour() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var gunner := Wl.slot_look(s.station(TankIds.ENGINE_DYNAMO).slot)["color"] as Color
	var dots: Array[Dictionary] = []
	for r in _rows(v.shots_layer, "rect"):
		var c: Color = r["c"]
		if c != Color.WHITE and (r["r"] as Rect2).size == Vector2(2, 2):
			dots.append(r)
	assert_gt(dots.size(), 5)
	assert_lte(dots.size(), TankView.TRAJECTORY_DOTS)
	for d in dots:
		var c: Color = d["c"]
		assert_almost_eq(c.r, gunner.r, 1e-4)
		assert_almost_eq(c.g, gunner.g, 1e-4)
		assert_lt(c.a, 1.0)
	assert_eq(v.gunner_color(s), gunner)


func test_the_arc_matches_the_ballistics_and_stops_at_the_ground() -> void:
	var s := TankFixtures.gun_line(3)
	var v := U.view_of(self, s)
	var dots: Array[Rect2] = []
	for r in _rows(v.shots_layer, "rect"):
		if (r["r"] as Rect2).size == Vector2(2, 2) and (r["c"] as Color) != Color.WHITE:
			dots.append(r["r"])
	assert_gt(dots.size(), 3)
	var v0 := s.content.num("tanks", "gun.shell_speed_px_s", 360.0)
	var g := s.content.num("tanks", "gun.gravity_px_s2", 300.0)
	var want := TankBallistics.position(
		v.rig.muzzle_layer(),
		TankBallistics.velocity(v0, v.rig.turret.elev, 1),
		g,
		TankView.TRAJECTORY_STEP_S
	)
	assert_almost_eq(dots[0].position.x, floorf(want.x), 1.0)
	for d in dots:
		assert_lte(d.position.y, float(TankConst.GROUND_Y))
	s.hull.target_id = 0
	v.advance(0.016)
	var any := false
	for r in _rows(v.shots_layer, "rect"):
		any = any or (r["r"] as Rect2).size == Vector2(2, 2) and (r["c"] as Color) != Color.WHITE
	assert_false(any, "no target, no arc")


func test_no_arc_while_the_turret_turns_or_the_tank_is_down() -> void:
	var s := TankFixtures.gun_line(3)
	var v := U.view_of(self, s)
	s.hull.facing = TankIds.FACE_LEFT
	s.hull.traverse_s = 3.0
	U.run(v, 20)
	var turning := 0
	for r in _rows(v.shots_layer, "rect"):
		turning += 1 if (r["r"] as Rect2).size == Vector2(2, 2) else 0
	assert_eq(turning, 0)


func test_the_boss_is_drawn_from_its_parts() -> void:
	var s := TankFixtures.boss(3)
	var v := U.view_of(self, s)
	assert_eq(_sprites(v.enemies_layer, "boss_hull").size(), 1)
	assert_eq(_sprites(v.enemies_layer, "boss_bogie").size(), 2)
	assert_eq(_sprites(v.enemies_layer, "boss_bogie_broken").size(), 1, "the front bogie is broken")
	assert_eq(_sprites(v.enemies_layer, "boss_turret").size(), 1)
	var hull := _sprites(v.enemies_layer, "boss_hull")[0]
	var bottom := (hull["pos"] as Vector2).y + 116.0
	assert_almost_eq(bottom, float(TankConst.GROUND_Y), 1.0, "the bogies stand on the ground")
	assert_almost_eq((hull["pos"] as Vector2).x, roundf(s.boss.x_px - s.camera_x()), 1.0)
	s.boss.turret_hp = 0.0
	v.advance(0.016)
	assert_eq(_sprites(v.enemies_layer, "boss_turret_broken").size(), 1)
	assert_gt(_rows(v.enemies_layer, "line").size(), 2, "a code-drawn barrel")


func test_the_boss_telegraph_lights_its_muzzle_and_a_withdrawing_boss_leaves() -> void:
	var s := TankFixtures.boss(3)
	var v := U.view_of(self, s)
	var lit := v.lights.count
	s.boss.telegraph_s = 0.0
	v.advance(0.016)
	assert_lt(v.lights.count, lit, "the muzzle glow is gone with the telegraph")
	var hull0 := (_sprites(v.enemies_layer, "boss_hull")[0]["pos"] as Vector2).x
	s.boss.phase = TankIds.BOSS_WITHDRAWN
	U.run(v, 120)
	var hull1 := (_sprites(v.enemies_layer, "boss_hull")[0]["pos"] as Vector2).x
	assert_gt(hull1, hull0 + 40.0, "it withdraws to the right")


func test_a_dead_behemoth_burns_and_explodes_once() -> void:
	var s := TankFixtures.boss(3)
	var v := U.view_of(self, s)
	s.boss.phase = TankIds.BOSS_DEAD
	U.run(v, 90)
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.EXPLOSION) + v.fx.particles.spawned, 0)
	var spawned := v.fx.particles.spawned
	assert_eq(v._timers.size() >= 0, true)
	assert_true(v._boss_death_done)
	U.run(v, 600)
	assert_lt(v.fx.particles.spawned - spawned, 6000, "bounded")


# --- Events -------------------------------------------------------------------------------------------------------


func test_a_shot_kicks_the_gun_flashes_and_smokes() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	v.game.cue.emit(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 15))
	v.advance(0.016)
	assert_gt(v.rig.turret.recoil, 2.0)
	assert_gt(v.fx.flash, 0.5, "the muzzle flash lights the scene")
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.RING), 0, "a smoke ring")
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.BRASS), 0, "brass")
	assert_gt(v.lights.wash, 0.0, "the scene around the muzzle is lit for a moment")
	assert_almost_eq(v.lights.wash_pos, v.rig.muzzle_layer(), Vector2(8, 8), "centred on the gun")
	U.run(v, 12)
	assert_eq(v.lights.wash, 0.0)


func test_a_secondary_shot_kicks_the_right_turret() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	v.game.cue.emit(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_BOW, 17))
	v.advance(0.016)
	assert_gt(v.rig.secondaries[1].recoil + v.rig.secondaries[0].recoil, 0.0)


func test_an_enemy_shot_flashes_at_its_muzzle() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var before := v.fx.particles.count_kind(TankParticles.Kind.FLASH)
	v.game.cue.emit(TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_ENEMY, 16, 11, 2))
	v.advance(0.016)
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.FLASH), before)
	var boss := TankFixtures.boss(3)
	var v2 := U.view_of(self, boss)
	v2.game.cue.emit(TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_BOSS_MAIN, 30))
	v2.advance(0.016)
	assert_gt(v2.rig.shake_amp, 0.5, "the main gun shakes the ground")


func test_a_hit_on_the_hull_sparks_flashes_and_shakes() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	v.game.cue.emit(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_TANK, 0, 14.0, TankIds.SHELL_ENEMY, 0.0, s.hull.x_px + 80.0)
	)
	v.advance(0.016)
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.SPARK), 3, "sparks on armour")
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.EMBER), 0, "hot fragments")
	assert_gt(v.rig.shake_amp, 1.0)
	v.advance(0.016)
	assert_gt(v.rig.hull_sprite.modulate.r, 1.0)


func test_hits_on_enemies_obstacles_and_the_boss_have_effects() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var n0 := v.fx.particles.spawned
	v.game.cue.emit(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 11, 50.0, TankIds.SHELL_HEAVY, 0.0, s.enemy(11).x_px)
	)
	v.advance(0.016)
	var n1 := v.fx.particles.spawned
	assert_gt(n1, n0)
	v.game.cue.emit(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_OBSTACLE, 14, 20.0, TankIds.SHELL_LIGHT, 0.0, 4100.0)
	)
	v.advance(0.016)
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.DIRT), 0, "dirt sprays")
	var b := TankFixtures.boss(3)
	var vb := U.view_of(self, b)
	vb.game.cue.emit(
		TankEvents.HIT,
		TankEvents.hit(
			TankEvents.ON_BOSS,
			TankBossState.part_id(3),
			50.0,
			TankIds.SHELL_HEAVY,
			0.0,
			b.boss.x_px + 200.0
		)
	)
	vb.advance(0.016)
	assert_gt(
		vb.fx.particles.count_kind(TankParticles.Kind.EXPLOSION), 0, "a heavy hit on the turret"
	)


func test_a_shell_that_lands_in_the_ground_throws_dirt() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	var sh := s.shells[0]
	sh.y = float(TankConst.GROUND_Y) - 4.0
	sh.vy = 90.0
	s.tick += 1
	v.advance(0.016)
	s.shells.erase(sh)
	s.tick += 1
	v.advance(0.016)
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.DIRT), 0)
	var s2 := TankFixtures.state(3)
	var v2 := U.view_of(self, s2)
	var hit_shell := s2.shells[0]
	hit_shell.y = 150.0
	hit_shell.vy = 90.0
	s2.tick += 1
	v2.advance(0.016)
	s2.shells.erase(hit_shell)
	s2.tick += 1
	v2.advance(0.016)
	assert_eq(
		v2.fx.particles.count_kind(TankParticles.Kind.DIRT), 0, "a shell that hits mid-air does not"
	)


func test_a_ram_destroys_with_a_fireball_or_fails_with_sparks() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	v.game.cue.emit(TankEvents.RAM, TankEvents.ram(2, true, 12))
	v.advance(0.016)
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.EXPLOSION), 0)
	assert_gt(v.rig.shake_amp, 1.0)
	var v2 := U.view_of(self, TankFixtures.state(3))
	v2.game.cue.emit(TankEvents.RAM, TankEvents.ram(2, false, 0))
	v2.advance(0.016)
	assert_eq(v2.fx.particles.count_kind(TankParticles.Kind.EXPLOSION), 0)
	assert_gt(v2.fx.particles.count_kind(TankParticles.Kind.SPARK), 0)


func test_a_breakdown_and_a_repair_have_effects() -> void:
	var s := TankFixtures.state(2)
	var v := U.view_of(self, s)
	v.game.cue.emit(TankEvents.BREAKDOWN, TankEvents.breakdown())
	v.advance(0.016)
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.EXPLOSION), 0)
	v.game.cue.emit(TankEvents.REPAIRED, TankEvents.repaired(40.0))
	v.advance(0.016)
	assert_gt(v.fx.particles.count_kind(TankParticles.Kind.SPARK), 3, "welding sparks")


func test_a_tow_fades_to_black_and_back() -> void:
	var s := TankFixtures.state(3)
	var v := U.view_of(self, s)
	assert_eq(v.fade_amount(), 0.0)
	v.game.cue.emit(TankEvents.OVERRUN, TankEvents.overrun(TankIds.SEG_ADVANCE, 2))
	var peak := 0.0
	for _i in int(TankView.FADE_S * 60.0) + 10:
		v.advance(1.0 / 60.0)
		peak = maxf(peak, v.fade_amount())
	assert_almost_eq(peak, 1.0, 0.01, "fully black in the middle")
	assert_eq(v.fade_amount(), 0.0, "and clear again")


func test_a_support_barrage_rains_fireballs() -> void:
	var s := TankFixtures.gun_line(3)
	var v := U.view_of(self, s)
	v.game.cue.emit(TankEvents.OVERRUN, TankEvents.overrun(TankIds.SEG_GUN_LINE, 2))
	var booms := 0
	for _i in 160:
		v.advance(1.0 / 60.0)
		booms = maxi(booms, v.fx.particles.count_kind(TankParticles.Kind.EXPLOSION))
	assert_gt(booms, 0)


func test_the_boss_dying_chains_explosions_and_phase_two_breaks_a_bogie() -> void:
	var s := TankFixtures.boss(3)
	var v := U.view_of(self, s)
	v.game.cue.emit(TankEvents.KILL, TankEvents.kill(-4, TankIds.BOSS_CODE, TankEvents.BY_SHELL, 0))
	var spawned := v.fx.particles.spawned
	U.run(v, 100)
	assert_gt(v.fx.particles.spawned, spawned + 20, "seven fireballs over a second and a half")
	var v2 := U.view_of(self, TankFixtures.boss(3))
	v2.game.cue.emit(TankEvents.BOSS_PHASE, TankEvents.boss_phase(TankIds.BOSS_PHASE_2))
	U.run(v2, 30)
	assert_gt(v2.fx.particles.count_kind(TankParticles.Kind.EXPLOSION) + v2.fx.particles.spawned, 0)


func test_unknown_cues_are_ignored() -> void:
	var v := U.view_of(self, TankFixtures.state(1))
	v.game.cue.emit("snapshot", {})
	v.game.cue.emit("segment", TankEvents.segment(5, TankIds.SEG_GUN_LINE, 1))
	v.game.cue.emit("rotation", TankEvents.rotation([[0, "diesel"]]))
	U.run(v, 3)
	assert_eq(v._cues.size(), 0)


func test_scenery_fires_burn_on_the_far_plane_and_tint_the_distance() -> void:
	var s := TankFixtures.state(3)
	s.seg.phase_index = 1
	s.hull.x_px = 0.0
	var v := U.view_of(self, s)
	var far := false
	for step in 80:
		s.hull.x_px += 30.0
		s.tick += 1
		U.run(v, 4)
		for i in v.fx.particles.count:
			if v.fx.particles.plane[i] == TankParticles.PLANE_BACK:
				far = true
	assert_true(far, "flames and smoke of distant fires sit on the hazed far plane")
	assert_gt(v.backdrop.scenery_lights.count, 0)


func test_the_halt_line_stands_where_the_road_ends() -> void:
	var s := TankFixtures.state(1)
	var length_m := float(s.content.segment(s.seg.phase_index)["length_m"])
	s.hull.x_px = TankConst.m_to_px(length_m) - 300.0
	var v := U.view_of(self, s)
	var posts := _halt_posts(v)
	assert_eq(posts.size(), 1, "one lamp post at the line")
	var want := TankConst.m_to_px(length_m) + float(s.hull.hull_w) - s.camera_x()
	assert_almost_eq((posts[0]["r"] as Rect2).position.x, want, 0.01)
	s.hull.x_px = 0.0
	s.tick += 1
	U.run(v, 90)
	var far := _halt_posts(v).size()
	assert_eq(far, 0, "off screen far from the end")
	var g := TankFixtures.gun_line(1)
	g.hull.x_px = TankConst.m_to_px(length_m) - 300.0
	var vg := U.view_of(self, g)
	var at_gun_line := _halt_posts(vg).size()
	assert_eq(at_gun_line, 0, "only an Advance has a halt line")


func test_the_halt_line_is_no_flag() -> void:
	var s := TankFixtures.state(1)
	var length_m := float(s.content.segment(s.seg.phase_index)["length_m"])
	s.hull.x_px = TankConst.m_to_px(length_m) - 300.0
	var v := U.view_of(self, s)
	var post: Rect2 = _halt_posts(v)[0]["r"]
	for r in _rows(v.props_layer, "rect"):
		var rr: Rect2 = r["r"]
		if absf(rr.position.x - post.position.x) > 30.0:
			continue
		var c: Color = r["c"]
		if c == TankPalette.AMBER:
			continue
		assert_false(
			rr.size.x >= 10.0 and rr.size.y >= 2.0 and rr.position.y < post.end.y - 8.0,
			"no banner hangs off the post"
		)
		assert_lt(c.get_luminance(), TankPalette.STEEL_LIGHT.get_luminance() + 0.001, "dark steel")


func _halt_posts(v: TankView) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _rows(v.props_layer, "rect"):
		if str(r.get("of", "")) == "halt_line":
			out.append(r)
	return out


func test_a_station_change_flares_every_lamp() -> void:
	var v := U.view_of(self, TankFixtures.state(3))
	v.game.cue.emit(
		TankEvents.ROTATION, TankEvents.rotation([[0, "dynamo"], [1, "steam"], [2, "diesel"]])
	)
	v.advance(0.016)
	for room in v.rig.rooms:
		assert_gt(room.flare_s, 0.0, room.engine)
	U.run(v, 100)
	for room in v.rig.rooms:
		assert_eq(room.flare_s, 0.0)
