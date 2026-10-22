extends GutTest
## The moving pieces' own logic: enemy interpolation between states, bolt and zone visuals, chain
## layout and patterns.

var _state: SiegeState = null
var _map: SiegeMap = null


func before_each() -> void:
	_state = SiegeFixtures.mid_wave()
	_map = _state.content.map


# --- SiegeEnemyInterp ----------------------------------------------------------------------------------


func _advance(it: SiegeEnemyInterp, seconds: float, step: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		it.advance(step)
		t += step


func test_interp_draws_between_two_states() -> void:
	var it := SiegeEnemyInterp.new()
	var e := _state.enemies[0]
	it.observe(_state)
	var p0 := e.prog_m
	_state.tick += 2
	e.prog_m += 1.0
	it.observe(_state)
	assert_almost_eq(it.prog_of(e), p0, 0.2, "starts from the previous state")
	_advance(it, 0.5)
	assert_almost_eq(it.prog_of(e), p0 + 1.0, 0.05, "arrives at the newest")


func test_interp_never_extrapolates() -> void:
	var it := SiegeEnemyInterp.new()
	var e := _state.enemies[0]
	it.observe(_state)
	var p0 := e.prog_m
	_state.tick += 2
	e.prog_m += 1.0
	it.observe(_state)
	_advance(it, 5.0)
	assert_almost_eq(it.prog_of(e), p0 + 1.0, 1e-4)


func test_interp_spacing_follows_the_snapshot_rate() -> void:
	var it := SiegeEnemyInterp.new()
	it.observe(_state)
	# A snapshot a second apart (the 8-rider load).
	for i in 6:
		_state.tick += 20
		it.observe(_state)
	assert_gt(it.spacing_s, 0.8)
	assert_lte(it.spacing_s, SiegeEnemyInterp.MAX_SPACING_S)
	var fast := SiegeEnemyInterp.new()
	fast.observe(_state)
	for i in 10:
		_state.tick += 2
		fast.observe(_state)
	assert_almost_eq(fast.spacing_s, 0.1, 0.02)


func test_interp_new_enemies_appear_at_their_state() -> void:
	var it := SiegeEnemyInterp.new()
	it.observe(_state)
	_state.tick += 2
	var fresh := SiegeEnemyState.new()
	fresh.id = 9999
	fresh.prog_m = 30.0
	fresh.road = 1
	_state.enemies.append(fresh)
	it.observe(_state)
	assert_eq(it.prog_of(fresh), 30.0)


func test_interp_restarts_after_a_gap_or_a_clock_reset() -> void:
	var it := SiegeEnemyInterp.new()
	it.observe(_state)
	var e := _state.enemies[0]
	var old := e.prog_m
	_state.tick += 200
	e.prog_m += 40.0
	it.observe(_state)
	assert_eq(it.prog_of(e), old + 40.0, "a long gap does not tween across the jump")
	_state.tick = 3
	it.observe(_state)
	assert_eq(it.t_cur, 3 * Wl.SIM_DT)


func test_interp_positions_are_on_the_road() -> void:
	var it := SiegeEnemyInterp.new()
	it.observe(_state)
	for e in _state.enemies:
		assert_almost_eq(it.pos_of(e, _map).distance_to(e.pos), 0.0, 1e-3)


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
