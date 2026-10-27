extends GutTest
## The arc generator (brief 2.2-2.4): the Bastion's fourth room, ERG tempo whose in-band rule is the
## dynamo's (power >= 95% of the applied target, cadence >= 60), the searchlights lit while its
## rider is in band, a rescue stalling it ("Arc generator stalled": bow guns stop, lights dim), the
## arc load (duty) its bow guns write each tick, and its plans (brief 2.3 table and BRIEF 4.6).

const ADVANCE := 1


func _rig() -> TankRulesRig:
	var rig := TankRulesRig.new(4)
	rig.no_fire = true
	rig.enter(ADVANCE, 5.0)
	return rig


func _arc(rig: TankRulesRig) -> TankArcState:
	return rig.state.station(TankIds.ENGINE_ARC) as TankArcState


func test_crew_4_is_the_bastion_with_four_rooms_and_slot_3_on_the_arc() -> void:
	var rig := _rig()
	assert_eq(rig.state.hull.tank, TankIds.TANK_BASTION)
	assert_eq(rig.state.stations.size(), 4)
	assert_eq(_arc(rig).slot, 3)
	assert_eq(rig.rider(4).engine, TankIds.ENGINE_ARC)
	assert_eq(rig.content.enemy_scale(TankIds.TANK_BASTION), 1.2)


func test_in_band_lights_the_searchlights() -> void:
	var rig := _rig()
	rig.run(0.5)
	assert_true(_arc(rig).in_band, "ERG on target at 90 rpm")
	assert_true(_arc(rig).lit)
	rig.power_w[4] = 0.8 * rig.state.rider(4).ftp * 0.65
	rig.run(0.5)
	assert_false(_arc(rig).in_band, "power under 95% of the target")
	assert_false(_arc(rig).lit)
	rig.power_w.erase(4)
	rig.cadence[4] = 55.0
	rig.run(0.5)
	assert_false(_arc(rig).lit, "cadence under 60")
	rig.cadence.erase(4)
	rig.afk[4] = true
	rig.run(0.5)
	assert_true(_arc(rig).reserve)
	assert_false(_arc(rig).lit, "never on reserve")


func test_a_rescue_stalls_it_and_its_rider_back_lights_it_again() -> void:
	var rig := _rig()
	rig.rescue[4] = true
	rig.run(0.5)
	assert_true(_arc(rig).stalled)
	assert_false(_arc(rig).lit)
	assert_eq(TankBow.power_rate(rig.state, _arc(rig)), 0.0, "the bow guns stop")
	rig.rescue[4] = false
	rig.run(0.5)
	assert_false(_arc(rig).stalled)
	assert_true(_arc(rig).lit)
	assert_eq(TankBow.power_rate(rig.state, _arc(rig)), 1.0)


func test_every_tick_writes_the_fire_record() -> void:
	var rig := _rig()
	rig.state.enemies.clear()
	rig.run(3.0)
	assert_eq(_arc(rig).duty, 0.0)
	var e := rig.spawn(TankIds.ENEMY_LIGHT, 1, 130.0)
	e.hp = 1.0e6
	e.gun_s = 1.0e6
	rig.run(2.0)
	assert_almost_eq(_arc(rig).duty, 0.2, 0.01, "2 of the last 10 s")


func test_the_snapshot_carries_duty_lit_and_stalled() -> void:
	var rig := _rig()
	rig.run(0.5)
	_arc(rig).duty = 0.42
	_arc(rig).stalled = true
	var snap := TankSnapshot.encode(rig.state)
	var client := TankFixtures.state(4)
	TankSnapshot.apply(client, snap)
	var arc := client.station(TankIds.ENGINE_ARC) as TankArcState
	assert_almost_eq(arc.duty, 0.42, 0.001)
	assert_true(arc.lit)
	assert_true(arc.stalled)


## Brief 2.3: depot ERG 50 -> 65, stages ERG 65 in 65..80, checkpoints 50; the drill 50 then 55 in
## 55..65; every bound inside 50..100% (4.6.1), warm-up at most 65% (4.6.8), and the boss's range
## top far under the 105% cap of a phase over 300 s.
func test_the_arc_plans_match_the_brief() -> void:
	var c := TankFixtures.content()
	var plan := TankPlanBuilder.build(c, TankIds.TANK_BASTION, 3, false)
	for i in plan.size():
		var ph := plan.phase(i)
		assert_eq(ph.mode, Wl.ERG, "the arc rider always rides ERG (phase %d)" % i)
		var seg := str(ph.meta["seg"])
		match seg:
			TankIds.SEG_DEPOT:
				assert_eq([ph.target_pct, ph.ramp_to_pct], [50.0, 65.0])
			TankIds.SEG_CHECKPOINT:
				assert_eq(ph.target_pct, 50.0)
			_:
				assert_eq(ph.target_pct, 65.0, seg)
				assert_eq(ph.range_pct, [65.0, 80.0], seg)
	var drill := TankFixtures.content("drill")
	var dp := TankPlanBuilder.build(drill, TankIds.TANK_BASTION, 3, false)
	assert_eq(dp.phase(0).target_pct, 50.0)
	assert_eq([dp.phase(1).target_pct, dp.phase(1).range_pct], [55.0, [55.0, 65.0]])
	for crew_plan in [plan, dp]:
		var ep: EffortPlan = crew_plan
		var v := PlanValidator.validate(ep)
		assert_eq(v.get("errors", []), [] as Array[String], "the validator accepts the arc plan")
