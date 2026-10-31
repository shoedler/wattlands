extends GutTest
## The bow guns (v3: the Secondaries seat, TankBow): exactly 2 rounds per pedal revolution of its
## rider (2 x cadence a minute), alternating guns, at the nearest near threat 4-200 px off the hull
## front (v4: never a far enemy or the Behemoth); damage per round with the armour factors; power in
## band sets the slew speed (a round hits once the guns point at the target); barricades cleared by
## rounds; kill credit; an empty
## seat, a breakdown, a rescue or a rider on reserve silences them. And the main gun's dispersion
## by the Lights seat (dark: x2).

const CHECKPOINT := 3


static func _quiet(index: int) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(
			{"encounters": [], "obstacles": []}, true
		)


## A rig in Stage 1's checkpoint (the tank stands, the main gun stays out of it) with peer 2 (or the
## solo rider) on the Secondaries.
func _rig(crew: int, feed: bool = true) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", 7, _quiet(CHECKPOINT))
	rig.no_fire = true
	if feed:
		rig.seat(2 if crew > 1 else 1, TankIds.ENGINE_FEED)
	rig.enter(CHECKPOINT, 1.0)
	return rig


## A tough near threat whose gun stays quiet, `dist` px off the hull front.
func _target(rig: TankRulesRig, type: String, dist: float) -> TankEnemyState:
	var e := rig.near(type, dist)
	TankAux.of(rig.state).enemy_age[e.id] = -1.0e6
	e.hp = 5000.0
	e.hp_max = 5000.0
	e.gun_s = 1.0e6
	return e


func test_an_empty_secondaries_seat_is_silent() -> void:
	for crew in [1, 2, 3, 4]:
		var rig := _rig(crew, false)
		assert_true(rig.feed().is_empty(), "crew %d starts with the Secondaries empty" % crew)
		var e := _target(rig, TankIds.ENEMY_RECON, 130.0)
		rig.run(5.0)
		assert_eq(rig.feed().rounds, 0, "crew %d" % crew)
		assert_eq(e.hp, 5000.0)


func test_two_rounds_per_pedal_revolution_alternating_guns() -> void:
	var rig := _rig(2)
	assert_eq(rig.feed().slot, 1, "peer 2 sits on the Secondaries")
	assert_eq(rig.rider(2).engine, TankIds.ENGINE_FEED)
	_target(rig, TankIds.ENEMY_RECON, 130.0)
	rig.run(10.0)
	assert_between(rig.feed().rounds, 29, 30, "90 rpm: 3 rounds a second")
	assert_eq(rig.feed().rpm, 180.0, "2 x cadence")
	assert_eq(rig.feed().last_gun(), (rig.feed().rounds - 1) % 2)
	assert_eq(rig.feed().fire_tick, rig.state.tick)
	rig.cadence[2] = 60.0
	var n := rig.feed().rounds
	rig.run(10.0)
	assert_between(rig.feed().rounds - n, 19, 21, "60 rpm: 2 a second")
	assert_eq(rig.feed().rpm, 120.0)
	assert_eq(rig.of_type("shot").size(), 0, "rounds raise no shot events")


func test_damage_per_round_and_the_armour() -> void:
	var c := TankFixtures.content()
	var per := c.num("tanks", "bow.damage", 0.0)
	assert_gt(per, 0.0)
	for type: String in TankIds.NEAR_KINDS:
		var rig := _rig(2)
		var e := _target(rig, type, 100.0)
		rig.run(4.0)
		var hits := rig.state.score.bow_hits
		assert_gt(hits, 0, type)
		assert_almost_eq(5000.0 - e.hp, hits * per, 1e-4, type)
		assert_eq(rig.rider(2).bow_hits, hits)


func test_power_in_band_sets_the_slew_speed() -> void:
	var c := TankFixtures.content()
	var pair: Array = c.value("tanks", "bow.slew_deg_s", [])
	assert_lt(float(pair[0]), float(pair[1]), "under band slews slower than in band")
	var rigs: Array[TankRulesRig] = []
	for _i in 2:
		# Stage 1's Advance (a SIM WORK phase: in band is 76-105% FTP), the tank held still.
		var rig := TankRulesRig.new(2, "ashfall_road", 7, _quiet(1))
		rig.no_fire = true
		rig.seat(2, TankIds.ENGINE_FEED)
		rig.p_eff[1] = 0.0
		rig.enter(1, 1.0)
		TankAux.of(rig.state).bow_deg = -30.0
		_target(rig, TankIds.ENEMY_RECON, 130.0)
		rigs.append(rig)
	var fast := rigs[0]
	var slow := rigs[1]
	slow.power_w[2] = 0.5 * 220.0
	fast.run(2.0)
	slow.run(2.0)
	assert_true(fast.feed().in_band)
	assert_false(slow.feed().in_band)
	assert_eq(fast.feed().rounds, slow.feed().rounds, "the rate is the cadence's either way")
	assert_gt(fast.state.score.bow_hits, slow.state.score.bow_hits, "in band it lays sooner")


func test_only_the_nearest_near_threat_in_4_to_200_px() -> void:
	var rig := _rig(2)
	var far := _target(rig, TankIds.ENEMY_RECON, 210.0)
	rig.run(3.0)
	assert_eq(rig.feed().rounds, 0, "210 px is out of range")
	var close := _target(rig, TankIds.ENEMY_TANKETTE, 2.0)
	rig.run(1.0)
	assert_eq(rig.feed().rounds, 0, "nearer than 4 px is too close")
	var next := _target(rig, TankIds.ENEMY_RECON, 180.0)
	var nearest := _target(rig, TankIds.ENEMY_RECON, 60.0)
	rig.run(2.0)
	assert_gt(rig.feed().rounds, 0)
	assert_lt(nearest.hp, 5000.0, "the nearest")
	assert_eq(next.hp, 5000.0)
	assert_eq([far.hp, close.hp], [5000.0, 5000.0])


## v4: the far enemies and the Behemoth are out of the bow guns' reach and take nothing from them.
func test_far_enemies_and_the_behemoth_are_not_bow_targets() -> void:
	var rig := _rig(2)
	var m := rig.far(TankIds.ENEMY_LIGHT, 900.0)
	m.gun_s = 1.0e6
	var hp := m.hp
	rig.run(3.0)
	assert_eq(rig.feed().rounds, 0, "silent with only a far enemy")
	assert_eq(m.hp, hp)
	var boss := TankRulesRig.new(2)
	boss.no_fire = true
	boss.seat(2, TankIds.ENGINE_FEED)
	boss.enter(10, 1.0)
	var aux := TankAux.of(boss.state)
	TankTargets.build(boss.state, aux)
	assert_null(TankBow.target(boss.state, aux), "the Behemoth is far")
	boss.run(3.0)
	assert_eq(boss.feed().rounds, 0)
	assert_eq(boss.state.boss.bogie_hp[0], boss.state.boss.bogie_max)


func test_rounds_that_hit_clear_a_barricade_in_range() -> void:
	var rig := _rig(2)
	var need := rig.content.num("tanks", "bow.clear_rounds", 0.0)
	assert_gt(need, 0.0)
	var front := rig.hull().x_px + rig.hull().hull_w
	var wire := TankEncounters.add_obstacle(rig.state, TankIds.OBST_WIRE, front + 150.0)
	rig.run_until(func() -> bool: return wire.cleared, 20.0)
	assert_true(wire.cleared)
	assert_eq(rig.state.score.bow_hits, int(need), "clear_rounds rounds that hit")
	var far := _rig(2)
	var w3 := TankEncounters.add_obstacle(
		far.state, TankIds.OBST_WIRE, far.hull().x_px + far.hull().hull_w + 210.0
	)
	far.run(10.0)
	assert_false(w3.cleared, "out of range")


func test_a_near_threat_in_range_comes_before_a_barricade() -> void:
	var rig := _rig(2)
	var front := rig.hull().x_px + rig.hull().hull_w
	var wire := TankEncounters.add_obstacle(rig.state, TankIds.OBST_WIRE, front + 100.0)
	var e := _target(rig, TankIds.ENEMY_RECON, 180.0)
	rig.run(8.0)
	assert_false(wire.cleared)
	assert_lt(e.hp, 5000.0)


func test_a_bow_kill_is_credited_by_bow_to_the_secondaries_rider() -> void:
	var rig := _rig(2)
	var e := rig.near(TankIds.ENEMY_RECON, 130.0)
	e.hp = 1.0
	e.gun_s = 1.0e6
	rig.run(2.0)
	var kill := rig.of_type("kill")
	assert_eq(kill.size(), 1)
	assert_eq([kill[0]["id"], kill[0]["by"], kill[0]["s"]], [e.id, TankEvents.BY_BOW, 1])
	assert_eq(rig.state.score.crew_kills, 1)


func test_nothing_fires_in_a_breakdown_a_rescue_or_on_reserve() -> void:
	var rig := _rig(2)
	_target(rig, TankIds.ENEMY_RECON, 130.0)
	rig.hull().breakdown = true
	rig.run(3.0)
	assert_eq(rig.feed().rounds, 0, "breakdown")
	rig.hull().breakdown = false
	rig.rescue[2] = true
	rig.run(3.0)
	assert_eq(rig.feed().rounds, 0, "rescue")
	rig.rescue.erase(2)
	rig.afk[2] = true
	rig.run(3.0)
	assert_eq(rig.feed().rounds, 0, "on reserve")
	assert_eq(rig.feed().rpm, 0.0)
	rig.afk.erase(2)
	rig.run(1.0)
	assert_gt(rig.feed().rounds, 0)


## Dark (the Lights seat empty or out of band) the main gun's dispersion doubles; lit it is the
## bank's own.
func test_dark_searchlights_double_the_main_guns_dispersion() -> void:
	var rig := _rig(4, false)
	rig.run(0.1)
	var arc := rig.arc()
	assert_true(arc.lit, "crew 4's Lights rider in band: lit")
	assert_true(TankGun.searchlights_lit(rig.state))
	var spread := func(lit: bool) -> float:
		arc.lit = lit
		var worst := 0.0
		for _i in 200:
			rig.state.shells.clear()
			rig.load_shell(TankIds.SHELL_LIGHT)
			rig.hull().elev_deg = 0.5
			TankGun.fire(rig.state, TankAux.of(rig.state), rig.dynamo(), true, rig.events)
			var s: TankShellState = rig.state.shells.back()
			var a := rad_to_deg(atan2(-s.vy, s.vx))
			worst = maxf(worst, absf(a - 0.5))
		return worst
	var lit_spread: float = spread.call(true)
	var dark_spread: float = spread.call(false)
	assert_almost_eq(lit_spread, 0.5, 0.05, "the full bank's 0.5 degrees")
	assert_almost_eq(dark_spread, 1.0, 0.1, "doubled")
	rig.cadence[rig.peer_of(TankIds.ENGINE_ARC)] = 40.0
	rig.run(0.1)
	assert_false(arc.lit, "under band: dark")
