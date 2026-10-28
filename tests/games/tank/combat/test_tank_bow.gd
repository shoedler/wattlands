extends GutTest
## The bow guns (brief 2.4 Gun): a 5-damage burst every 2 s at the nearest enemy ahead 40-220 px
## off the hull front, the armour factors, the power by manned seat (v2's sources, a v3 interim: the
## arc generator, else the dynamo bank; an empty seat powers nothing), barricades cleared by 4 s of
## fire, kill credit, and the arc's fire record (duty).

const CHECKPOINT := 3


static func _quiet(index: int) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(
			{"encounters": [], "obstacles": []}, true
		)


## A rig in Stage 1's checkpoint: the tank stands, the main gun stays out of it.
func _rig(crew: int) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", true, 7, _quiet(CHECKPOINT))
	rig.no_fire = true
	rig.enter(CHECKPOINT, 1.0)
	return rig


## A tough enemy whose gun stays quiet, `dist` px off the hull front.
func _target(rig: TankRulesRig, type: String, dist: float, side: int = 1) -> TankEnemyState:
	var e := rig.spawn(type, side, dist)
	e.hp = 5000.0
	e.hp_max = 5000.0
	e.gun_s = 1.0e6
	return e


func _bursts(rig: TankRulesRig) -> Array[Dictionary]:
	return rig.of_type("shot").filter(
		func(e: Dictionary) -> bool: return e["sh"] == TankIds.SHELL_BOW
	)


func test_every_crew_powers_its_bow_guns_from_a_manned_seat() -> void:
	var solo := _rig(1)
	assert_null(TankBow.source(solo.state), "the solo rider on Drive powers no bow gun")
	_target(solo, TankIds.ENEMY_LIGHT, 130.0)
	solo.run(4.1)
	assert_eq(_bursts(solo).size(), 0, "empty Gun and Lights seats do nothing")
	var want := {2: TankIds.ENGINE_DYNAMO, 3: TankIds.ENGINE_DYNAMO, 4: TankIds.ENGINE_ARC}
	for crew: int in want:
		var rig := _rig(crew)
		assert_eq(TankBow.source(rig.state).engine, want[crew], "crew %d" % crew)
		var e := _target(rig, TankIds.ENEMY_LIGHT, 130.0)
		rig.run(4.1)
		assert_gt(_bursts(rig).size(), 0, "crew %d fires its bow guns" % crew)
		assert_lt(e.hp, 5000.0)


func test_a_burst_is_5_damage_every_2_seconds_and_costs_the_bank_2() -> void:
	var rig := _rig(2)
	var e := _target(rig, TankIds.ENEMY_LIGHT, 130.0)
	var bank := rig.dynamo().bank
	rig.run(0.05)
	assert_eq(_bursts(rig).size(), 1, "at once")
	assert_eq(e.hp, 4995.0)
	assert_almost_eq(rig.dynamo().bank, bank - 2.0, 0.2)
	rig.run(9.9)
	assert_eq(_bursts(rig).size(), 5, "one every 2 s")
	var hit := rig.of_type("hit").filter(func(h: Dictionary) -> bool: return h["sh"] == 4)
	assert_eq([hit[0]["on"], hit[0]["id"], hit[0]["dmg"]], [TankEvents.ON_ENEMY, e.id, 5])
	assert_eq(_bursts(rig)[0]["s"], rig.dynamo().slot, "the dynamo rider's burst")
	assert_eq(rig.rider(rig.dynamo().peer).bow_hits, 5)
	assert_eq(rig.state.score.bow_hits, 5)


func test_armour_mediums_half_heavies_destroyers_and_the_behemoth_a_quarter() -> void:
	var cases := {
		TankIds.ENEMY_LIGHT: 5.0,
		TankIds.ENEMY_DUGIN: 5.0,
		TankIds.ENEMY_MEDIUM: 2.5,
		TankIds.ENEMY_HEAVY: 1.25,
		TankIds.ENEMY_DESTROYER: 1.25,
	}
	for type: String in cases:
		var rig := _rig(2)
		var e := _target(rig, type, 100.0, 1)
		rig.run(0.05)
		assert_almost_eq(5000.0 - e.hp, float(cases[type]), 1e-6, type)
	var c := TankFixtures.content()
	assert_eq(TankDamage.boss_mult(c, TankIds.SHELL_BOW) * 5.0, 1.25, "a Behemoth part")


func test_only_the_nearest_enemy_ahead_in_40_to_220_px() -> void:
	var rig := _rig(2)
	var far := _target(rig, TankIds.ENEMY_LIGHT, 230.0)
	var behind := _target(rig, TankIds.ENEMY_LIGHT, 40.0, -1)
	rig.run(3.0)
	assert_eq(_bursts(rig).size(), 0, "230 px is out of range, behind is not ahead")
	var close := _target(rig, TankIds.ENEMY_MEDIUM, 30.0)
	close.lane = 1
	rig.run(1.0)
	assert_eq(_bursts(rig).size(), 0, "nearer than 40 px is too close")
	var near := _target(rig, TankIds.ENEMY_DUGIN, 180.0)
	var nearer := _target(rig, TankIds.ENEMY_DUGIN, 60.0)
	rig.run(0.05)
	assert_eq(_bursts(rig).size(), 1)
	assert_lt(nearer.hp, 5000.0, "the nearest")
	assert_eq(near.hp, 5000.0)
	assert_eq([far.hp, behind.hp, close.hp], [5000.0, 5000.0, 5000.0])


func test_the_dynamo_bank_powers_them_down_to_10_and_a_stall_stops_them() -> void:
	var rig := _rig(3)
	_target(rig, TankIds.ENEMY_LIGHT, 130.0)
	rig.dynamo().bank = 9.0
	rig.run(3.0)
	assert_eq(_bursts(rig).size(), 0, "none below 10 units")
	rig.dynamo().bank = 50.0
	rig.rescue[rig.dynamo().peer] = true
	rig.run(3.0)
	assert_eq(_bursts(rig).size(), 0, "the dynamo stalled")
	rig.rescue[rig.dynamo().peer] = false
	rig.run(0.1)
	assert_eq(_bursts(rig).size(), 1)


func test_the_arc_generator_full_rate_in_band_half_under_none_afk_or_stalled() -> void:
	var rig := _rig(4)
	var arc_peer := rig.peer_of(TankIds.ENGINE_ARC)
	_target(rig, TankIds.ENEMY_LIGHT, 130.0)
	rig.dynamo().bank = 5.0
	rig.run(10.0)
	assert_eq(_bursts(rig).size(), 5, "in band: every 2 s, whatever the dynamo's bank holds")
	rig.cadence[arc_peer] = 40.0
	rig.run(12.0)
	assert_false(rig.state.station(TankIds.ENGINE_ARC).in_band)
	assert_between(_bursts(rig).size(), 7, 9, "under band: every 4 s")
	rig.cadence.erase(arc_peer)
	rig.afk[arc_peer] = true
	var n := _bursts(rig).size()
	rig.run(6.0)
	assert_eq(_bursts(rig).size(), n, "the arc rider on reserve: none")
	rig.afk.erase(arc_peer)
	rig.rescue[arc_peer] = true
	rig.run(6.0)
	assert_true((rig.state.station(TankIds.ENGINE_ARC) as TankArcState).stalled)
	assert_eq(_bursts(rig).size(), n, "stalled: none")


func test_the_arc_load_is_the_share_of_the_last_10_s_the_bow_guns_fired() -> void:
	var rig := _rig(4)
	var arc := rig.state.station(TankIds.ENGINE_ARC) as TankArcState
	rig.run(5.0)
	assert_eq(arc.duty, 0.0, "nothing in range")
	var e := _target(rig, TankIds.ENEMY_LIGHT, 130.0)
	rig.run(5.0)
	assert_almost_eq(arc.duty, 0.5, 0.02, "engaged 5 of the last 10 s")
	rig.run(6.0)
	assert_almost_eq(arc.duty, 1.0, 0.001)
	rig.state.enemies.erase(e)
	rig.run(5.0)
	assert_almost_eq(arc.duty, 0.5, 0.02, "and it decays")


func test_four_seconds_of_bow_fire_clear_a_barricade_in_range() -> void:
	var rig := _rig(2)
	var front := rig.hull().x_px + rig.hull().hull_w
	var wire := TankEncounters.add_obstacle(rig.state, TankIds.OBST_WIRE, front + 150.0)
	rig.run(3.9)
	assert_false(wire.cleared)
	assert_gt(_bursts(rig).size(), 0)
	rig.run(0.2)
	assert_true(wire.cleared, "4 s of fire")
	# Half rate (v3: the Lights rider under band; v2 had the Bulwark's gearbox here): 8 s.
	var half := _rig(4)
	half.cadence[half.peer_of(TankIds.ENGINE_ARC)] = 40.0
	var w2 := TankEncounters.add_obstacle(
		half.state, TankIds.OBST_WRECK, half.hull().x_px + half.hull().hull_w + 150.0
	)
	half.run(7.9)
	assert_false(w2.cleared, "half rate: 8 s")
	half.run(0.2)
	assert_true(w2.cleared)
	var far := _rig(2)
	var w3 := TankEncounters.add_obstacle(
		far.state, TankIds.OBST_WIRE, far.hull().x_px + far.hull().hull_w + 260.0
	)
	far.run(6.0)
	assert_false(w3.cleared, "out of range")


func test_an_enemy_in_range_comes_before_a_barricade() -> void:
	var rig := _rig(2)
	var front := rig.hull().x_px + rig.hull().hull_w
	var wire := TankEncounters.add_obstacle(rig.state, TankIds.OBST_WIRE, front + 100.0)
	var e := _target(rig, TankIds.ENEMY_LIGHT, 180.0)
	rig.run(4.5)
	assert_false(wire.cleared)
	assert_lt(e.hp, 5000.0)


func test_a_bow_kill_is_credited_by_bow() -> void:
	var rig := _rig(2)
	var e := rig.spawn(TankIds.ENEMY_LIGHT, 1, 130.0)
	e.hp = 4.0
	e.gun_s = 1.0e6
	rig.run(0.05)
	var kill := rig.of_type("kill")
	assert_eq(kill.size(), 1)
	assert_eq(
		[kill[0]["id"], kill[0]["by"], kill[0]["s"]], [e.id, TankEvents.BY_BOW, rig.dynamo().slot]
	)
	assert_eq(rig.state.score.crew_kills, 1)


func test_nothing_fires_in_a_breakdown() -> void:
	var rig := _rig(2)
	_target(rig, TankIds.ENEMY_LIGHT, 130.0)
	rig.hull().breakdown = true
	rig.run(3.0)
	assert_eq(_bursts(rig).size(), 0)


## The searchlights (the arc rider in band) halve the main gun's dispersion.
func test_lit_searchlights_halve_the_main_guns_dispersion() -> void:
	var rig := _rig(4)
	rig.run(0.1)
	var arc := rig.state.station(TankIds.ENGINE_ARC) as TankArcState
	assert_true(arc.lit, "in band: lit")
	assert_true(TankGun.searchlights_lit(rig.state))
	var spread := func(lit: bool) -> float:
		arc.lit = lit
		var worst := 0.0
		for _i in 200:
			rig.state.shells.clear()
			rig.load_shell(TankIds.SHELL_LIGHT)
			rig.hull().elev_deg = 10.0
			TankGun.fire(rig.state, TankAux.of(rig.state), rig.dynamo(), true, rig.events)
			var s: TankShellState = rig.state.shells.back()
			var a := rad_to_deg(atan2(-s.vy, s.vx * float(rig.hull().facing)))
			worst = maxf(worst, absf(a - 10.0))
		return worst
	var full: float = spread.call(false)
	var half: float = spread.call(true)
	assert_almost_eq(full, 0.5, 0.05, "the full bank's 0.5 degrees")
	assert_almost_eq(half, 0.25, 0.03, "halved")
	rig.cadence[rig.peer_of(TankIds.ENGINE_ARC)] = 40.0
	rig.run(0.1)
	assert_false(arc.lit, "under band: dark")
