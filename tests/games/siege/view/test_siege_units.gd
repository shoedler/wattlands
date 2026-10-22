extends GutTest
## The moving pieces' own logic: enemy interpolation between states, bolt and zone visuals, chain
## layout and patterns.

var _state: SiegeState = null
var _map: SiegeMap = null


func before_each() -> void:
	_state = SiegeFixtures.mid_wave()
	_map = _state.content.map


# --- enemy positions: the state's own, or the module's snapshot history on a client ---------------


func _history(prog_a: float, prog_b: float) -> SiegeSnapHistory:
	var h := SiegeSnapHistory.new(_map)
	var e := _state.enemies[0]
	var was := e.prog_m
	e.prog_m = prog_a
	h.push(10.0, _state.enemies)
	e.prog_m = prog_b
	h.push(10.1, _state.enemies)
	e.prog_m = was
	return h


func test_without_a_history_enemies_are_drawn_at_the_state() -> void:
	for e in _state.enemies:
		assert_eq(SiegeEnemyView.drawn_prog(e, null), e.prog_m)
		assert_almost_eq(SiegeEnemyView.ground_pos(e, _map, null).distance_to(e.pos), 0.0, 1e-3)


func test_with_a_history_enemies_are_drawn_between_its_snapshots() -> void:
	var e := _state.enemies[0]
	var h := _history(20.0, 21.0)
	h.render_t = 10.05
	assert_almost_eq(SiegeEnemyView.drawn_prog(e, h), 20.5, 1e-3)
	var want := _map.point_at(e.road, 20.5, e.lat_m)
	assert_almost_eq(SiegeEnemyView.ground_pos(e, _map, h).distance_to(want), 0.0, 0.01)
	h.render_t = 10.1
	assert_almost_eq(SiegeEnemyView.drawn_prog(e, h), 21.0, 1e-3, "never past the newest")


func test_an_enemy_the_history_lacks_is_drawn_at_its_state() -> void:
	var h := _history(20.0, 21.0)
	h.render_t = 10.05
	var fresh := SiegeEnemyState.new()
	fresh.id = 9999
	fresh.prog_m = 30.0
	fresh.road = 1
	assert_eq(SiegeEnemyView.drawn_prog(fresh, h), 30.0)
	assert_almost_eq(
		SiegeEnemyView.ground_pos(fresh, _map, h).distance_to(_map.point_at(1, 30.0, 0.0)),
		0.0,
		1e-3
	)


func test_the_view_follows_the_module_history_on_a_client_and_the_state_otherwise() -> void:
	var view := SiegeViewUtil.make_view(self, _state)
	autofree(view)
	var e := _state.enemies[0]
	assert_null(view.client_history(), "no game, no history")
	assert_almost_eq(view.enemy_ground_pos(e).distance_to(e.pos), 0.0, 1e-3)
	var game := SiegeGame.new()
	autofree(game)
	view.game = game
	assert_null(view.client_history(), "an empty history is the host's or SOLO's")
	game.history = _history(20.0, 21.0)
	game.history.render_t = 10.05
	assert_eq(view.client_history(), game.history)
	var want := _map.point_at(e.road, 20.5, e.lat_m)
	assert_almost_eq(view.enemy_ground_pos(e).distance_to(want), 0.0, 0.01)
	view.refresh(1.0 / 60.0)
	assert_almost_eq(game.history.render_t, 10.0, 0.02, "the view advances the render clock")
	var drawn: Vector2 = view.enemies.drawn[e.id]
	assert_almost_eq(drawn.distance_to(_map.point_at(e.road, 20.0, e.lat_m)), 0.0, 0.2)


# --- SiegeEffectsView ------------------------------------------------------------------------------------


func _effects() -> SiegeEffectsView:
	var terrain := SiegeTerrain.from_map(_map)
	var fort := SiegeFortBuilder.new(_map)
	var towers := SiegeTowersView.new()
	towers.setup(fort)
	add_child_autofree(towers)
	var fx := SiegeEffectsView.new()
	fx.setup(terrain, towers)
	add_child_autofree(fx)
	return fx


func _drawn() -> Dictionary:
	var d := {}
	for e in _state.enemies:
		d[e.id] = e.pos
	return d


func test_a_bolt_flies_per_target_once() -> void:
	var fx := _effects()
	fx.update(_state, 0.0, _drawn())
	# pad 3: one target, pad 4: three, pad 2: one (a lob).
	assert_eq(fx.bolt_count(), 5)
	var again := fx.bolt_count()
	fx.update(_state, 0.01, _drawn())
	assert_eq(fx.bolt_count(), again, "the same tick spawns nothing new")
	_state.tick += 1
	for s in _state.shots:
		s.age_s += Wl.SIM_DT
	fx.update(_state, 0.01, _drawn())
	assert_eq(fx.bolt_count(), again, "an aged shot is the same shot")


func test_bolts_land_and_vanish() -> void:
	var fx := _effects()
	fx.update(_state, 0.0, _drawn())
	for i in 70:
		fx.update(_state, 1.0 / 60.0, _drawn())
	assert_eq(fx.bolt_count(), 0, "bolts take at most about half a second, a lob 0.9 s")


func test_a_new_shot_spawns_a_new_bolt() -> void:
	var fx := _effects()
	fx.update(_state, 0.0, _drawn())
	for i in 70:
		fx.update(_state, 1.0 / 60.0, _drawn())
	_state.tick += 8
	for s in _state.shots:
		s.age_s = 0.0
	fx.update(_state, 0.0, _drawn())
	assert_eq(fx.bolt_count(), 5)


func test_a_bolt_to_an_enemy_that_just_died_uses_its_last_position() -> void:
	var fx := _effects()
	var drawn := _drawn()
	fx.update(_state, 0.0, drawn)
	for i in 70:
		fx.update(_state, 1.0 / 60.0, drawn)
	var dead_id := int(_state.shots[0].targets[0])
	drawn.erase(dead_id)
	_state.tick += 8
	for s in _state.shots:
		s.age_s = 0.0
	fx.update(_state, 0.0, drawn)
	assert_eq(fx.bolt_count(), 5, "its last known position is still a target")


func test_zones_draw_a_ring_and_spikes_once_landed() -> void:
	var fx := _effects()
	fx.update(_state, 0.0, _drawn())
	assert_eq(fx.zone_count(), 1)
	assert_eq(fx.spikes_mm.visible_count(), SiegeEffectsView.SPIKES_PER_ZONE)
	_state.zones[0].delay_s = 0.6
	_state.zones[0].ttl_s = 4.0
	fx.update(_state, 0.0, _drawn())
	assert_eq(fx.zone_count(), 1, "a reticle while in the air")
	assert_eq(fx.spikes_mm.visible_count(), 0, "no spikes until it lands")
	_state.zones.clear()
	fx.update(_state, 0.0, _drawn())
	assert_eq(fx.zone_count(), 0)


func test_the_zone_ring_has_the_zones_radius() -> void:
	var fx := _effects()
	fx.update(_state, 0.0, _drawn())
	var t := fx.rings_mm.instance_transform(0)
	assert_almost_eq(t.basis.x.length(), _state.zones[0].radius_m, 1e-4)
	assert_almost_eq(t.origin.x, _state.zones[0].pos.x, 1e-4)


# --- SiegeChainView layout -------------------------------------------------------------------------------


func _line() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)])


func test_chain_links_sit_along_the_path_at_the_spacing() -> void:
	var links := SiegeChainView.layout(_line(), 1.0, 0.0)
	assert_eq(links.size(), 21, "20 m of path, one link a metre, both ends")
	assert_eq(links[0]["d"], 0.0)
	assert_almost_eq(float(links[12]["d"]), 12.0, 1e-4)
	var p: Vector3 = (links[12]["t"] as Transform3D).origin
	assert_almost_eq(p.x, 10.0, 1e-4)
	assert_almost_eq(p.z, 2.0, 1e-4)


func test_chain_scroll_moves_every_link_along_by_the_offset() -> void:
	var a := SiegeChainView.layout(_line(), 1.0, 0.0)
	var b := SiegeChainView.layout(_line(), 1.0, 0.4)
	assert_almost_eq(float(b[0]["d"]), 0.4, 1e-4)
	assert_almost_eq(float(b[3]["d"]) - float(a[3]["d"]), 0.4, 1e-4)
	# Link identity scrolls with its position: link n at offset 0.4 is the one that was at n.
	assert_eq(int(b[3]["i"]), int(a[3]["i"]))


func test_chain_pattern_scrolls_with_its_links() -> void:
	# Link 5 stays link 5 as the chain moves a metre, so a dash does not flicker.
	var before := SiegeChainView.layout(_line(), 1.0, 0.0)
	var after := SiegeChainView.layout(_line(), 1.0, 1.0)
	var idx_before := int(before[5]["i"])
	var found := false
	for l in after:
		if int(l["i"]) == idx_before:
			found = true
			assert_almost_eq(float(l["d"]), float(before[5]["d"]) + 1.0, 1e-4)
	assert_true(found)


func test_dashed_chain_drops_every_off_group() -> void:
	var on := 0
	for i in 12:
		if SiegeChainView.link_on("dashed", i):
			on += 1
	assert_eq(on, 8, "four on, two off, twice")
	for i in 12:
		assert_true(SiegeChainView.link_on("solid", i))
		assert_true(SiegeChainView.link_on("dotted", i))
		assert_true(SiegeChainView.link_on("double", i))
	assert_true(SiegeChainView.link_on("dashed", -6))


func test_chain_patterns_differ_in_instance_count() -> void:
	var fort := SiegeFortBuilder.new(_map)
	var c := SiegeChainView.new()
	c.setup(0, fort, Wl.slot_look(0))
	add_child_autofree(c)
	var rider := SiegeRiderState.new()
	rider.slot = 0
	rider.target = 3
	rider.p_eff_w = 200.0
	var counts := {}
	for pattern in ["solid", "dashed", "dotted", "double"]:
		c.pattern = pattern
		c.update(rider, 0.05)
		counts[pattern] = c.chain.visible_count()
	assert_lt(counts["dashed"], counts["solid"])
	assert_gt(counts["double"], counts["solid"], "two strands")
	assert_lt(counts["dotted"], counts["solid"], "beads are spaced wider")


func test_chain_lit_links_are_the_rider_color_and_the_rest_dim() -> void:
	var fort := SiegeFortBuilder.new(_map)
	var c := SiegeChainView.new()
	c.setup(0, fort, Wl.slot_look(0))
	add_child_autofree(c)
	var rider := SiegeRiderState.new()
	rider.slot = 0
	rider.target = 3
	rider.reconnect_s = 1.0
	c.update(rider, 0.05)
	var n := c.chain.visible_count()
	assert_gt(n, 10)
	assert_eq(c.chain.instance_color(0), Wl.slot_look(0)["color"], "the first link is lit")
	assert_eq(c.chain.instance_color(n - 1), SiegePalette.CHAIN_DIM, "the far end is still dark")
