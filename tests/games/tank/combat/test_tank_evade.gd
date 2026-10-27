extends GutTest
## "Surge to evade" (brief 2.4): every telegraph type (destroyer 4 s, heavy 3 s, the light tank's
## 2.5 s flank shot; the Behemoth's 6 s is in test_tank_boss.gd), the miss rule (a rider who can
## evade holds the sprint rule 2 s inside the telegraph), who can evade (SIM WORK phases past the
## first 300 s, never ERG riders, reserve or rescue), the evade event and the results counts.

const ADVANCE := 1
const GUN_LINE := 2


static func _quiet(index: int) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(
			{"encounters": [], "obstacles": [], "terrain": [[0, 0]]}, true
		)


## A Rampart in Stage 1's Advance (peer 1 diesel in SIM, peer 2 dynamo in ERG), 400 s into the
## plan, the gun out of the picture, the hull too tough to break down.
func _rig(crew: int = 2) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", true, 7, _quiet(ADVANCE))
	rig.no_fire = true
	rig.enter(ADVANCE, 5.0)
	rig.hull().hp = 100000.0
	rig.hull().hp_max = 100000.0
	# The sprint rule averages a full 3 s window: ride on target long enough to fill it first.
	rig.run(3.5)
	return rig


## An enemy of `type` holding `dist` px ahead whose gun fires in `gun_s` seconds.
func _shooter(rig: TankRulesRig, type: String, dist: float, gun_s: float) -> TankEnemyState:
	var e := rig.spawn(type, 1, dist)
	e.hp = 5000.0
	e.hp_max = 5000.0
	e.gun_s = gun_s
	return e


func _sprint(rig: TankRulesRig, peer: int, mult: float = 1.5) -> void:
	rig.power_w[peer] = mult * rig.slots[peer - 1].ftp


func _evades(rig: TankRulesRig) -> Array[Dictionary]:
	return rig.of_type("evade")


func test_who_can_evade_sim_work_riders_past_300_s() -> void:
	var rig := _rig(2)
	rig.run(0.1)
	assert_true(rig.rider(1).can_evade, "the diesel rides SIM in the Advance")
	assert_false(rig.rider(2).can_evade, "the dynamo rides ERG")
	rig.plan_t = 250.0
	rig.run(0.1)
	assert_false(rig.rider(1).can_evade, "the first 300 s")
	rig.plan_t = 400.0
	rig.rescue[1] = true
	rig.run(0.1)
	assert_false(rig.rider(1).can_evade, "rescue")
	rig.rescue[1] = false
	rig.afk[1] = true
	rig.run(0.1)
	assert_false(rig.rider(1).can_evade, "on reserve")
	rig.afk[1] = false
	rig.run(0.1)
	assert_true(rig.rider(1).can_evade)
	var gl := TankRulesRig.new(2)
	gl.enter(GUN_LINE, 5.0)
	assert_false(gl.rider(1).can_evade, "the diesel's ERG 90% gun line")
	var depot := TankRulesRig.new(1)
	depot.enter(0, 100.0)
	assert_false(depot.rider(1).can_evade, "WARMUP")
	var drill := TankRulesRig.new(1, "drill")
	drill.enter(1, 10.0)
	assert_false(drill.rider(1).can_evade, "the drill's WARMUP skirmish")
	var citadel := _rig(3)
	citadel.run(0.1)
	assert_true(citadel.rider(3).can_evade, "the steam engine rides SIM too")


func test_a_destroyer_telegraphs_4_s_and_a_sprint_held_2_s_inside_makes_it_miss() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 150.0, 4.5)
	rig.run(0.6)
	assert_eq(td.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(td.telegraph_s, 3.95, 0.06, "a 4 s glint")
	_sprint(rig, 1)
	rig.run(3.85)
	assert_eq(_evades(rig).size(), 0, "not yet fired")
	rig.run(0.2)
	var ev := _evades(rig)
	assert_eq(ev.size(), 1)
	assert_eq([ev[0]["id"], ev[0]["e"], ev[0]["ok"], ev[0]["s"]], [td.id, 3, 1, 0])
	var shot := rig.of_type("shot").filter(func(e: Dictionary) -> bool: return e["src"] == td.id)
	assert_eq(shot.size(), 1, "the shot follows the evade event")
	assert_false(rig.state.shells.back().will_hit, "evaded: it misses")
	assert_eq([rig.rider(1).evades_ok, rig.rider(1).evades_tried], [1, 1])
	assert_eq([rig.rider(2).evades_ok, rig.rider(2).evades_tried], [0, 0], "the ERG dynamo")
	assert_eq([rig.state.score.evades_ok, rig.state.score.evades_tried], [1, 1])


func test_without_a_sprint_the_telegraphed_shot_is_rolled_and_counts_as_tried() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 150.0, 4.5)
	rig.run(5.0)
	var ev := _evades(rig)
	assert_eq(ev.size(), 1)
	assert_eq([ev[0]["id"], ev[0]["ok"], ev[0]["s"]], [td.id, 0, -1])
	assert_eq([rig.state.score.evades_ok, rig.state.score.evades_tried], [0, 1])
	assert_eq([rig.rider(1).evades_ok, rig.rider(1).evades_tried], [0, 1])


func test_a_sprint_held_only_1_5_s_inside_the_telegraph_is_not_enough() -> void:
	var rig := _rig(2)
	_shooter(rig, TankIds.ENEMY_DESTROYER, 150.0, 4.5)
	rig.run(0.5)
	rig.run(2.5)
	_sprint(rig, 1, 3.0)
	rig.run(2.0)
	assert_eq(_evades(rig)[0]["ok"], 0, "the rule held for about 1 s of the 4 s glint")


func test_a_heavy_tank_telegraphs_3_s() -> void:
	var rig := _rig(2)
	var hv := _shooter(rig, TankIds.ENEMY_HEAVY, 250.0, 3.5)
	rig.run(0.6)
	assert_eq(hv.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(hv.telegraph_s, 2.95, 0.06)
	_sprint(rig, 1, 2.5)
	rig.run(3.0)
	var ev := _evades(rig)
	assert_eq(ev.size(), 1)
	assert_eq([ev[0]["id"], ev[0]["e"], ev[0]["ok"]], [hv.id, 5, 1], "a hard 2.5 x FTP surge")


## The light tank's first shot at its hold is its flank shot: a 2.5 s telegraph, 8 damage at 70%;
## its later shots are its plain gun, untelegraphed.
func test_a_light_tanks_first_shot_at_its_hold_is_a_telegraphed_flank_shot() -> void:
	var rig := _rig(2)
	var lt := _shooter(rig, TankIds.ENEMY_LIGHT, 130.0, 3.0)
	var flank: Dictionary = rig.content.enemy_def(TankIds.ENEMY_LIGHT)["flank"]
	assert_eq([flank["telegraph_s"], flank["damage"], flank["hit"]], [2.5, 8.0, 0.7])
	rig.run(0.6)
	assert_eq(lt.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(lt.telegraph_s, 2.4, 0.06)
	rig.run(2.5)
	assert_eq(_evades(rig).size(), 1)
	var mine := rig.state.shells.filter(func(s: TankShellState) -> bool: return s.source == lt.id)
	assert_eq(mine.size(), 1)
	assert_eq(mine[0].damage, 8.0, "the flank shot")
	rig.run(4.5)
	assert_eq(_evades(rig).size(), 1, "the next shot is not telegraphed")
	assert_eq(lt.telegraph_s, 0.0)
	var shots := rig.of_type("shot").filter(func(e: Dictionary) -> bool: return e["src"] == lt.id)
	assert_eq(shots.size(), 2)


## A light rolls in from the screen edge: its countdown waits, and the flank shot gets its full
## 2.5 s telegraph once it holds, however little of the countdown was left.
func test_a_light_rolling_in_gets_its_full_flank_telegraph_at_its_hold() -> void:
	var rig := _rig(2)
	var aux := TankAux.of(rig.state)
	var lt := TankEnemies.spawn(rig.state, aux, TankIds.ENEMY_LIGHT, 1, -1.0, false, false, -1)
	lt.gun_s = 0.5
	var t := rig.run_until(func() -> bool: return lt.mode == TankIds.EM_TELEGRAPH, 30.0)
	assert_lt(t, 30.0, "it reached its hold and telegraphs")
	assert_almost_eq(lt.telegraph_s, 2.5, 0.06, "a full telegraph")


func test_an_erg_rider_sprinting_does_not_evade() -> void:
	var rig := _rig(2)
	_shooter(rig, TankIds.ENEMY_DESTROYER, 150.0, 4.5)
	_sprint(rig, 2, 2.0)
	rig.run(5.0)
	assert_eq(_evades(rig)[0]["ok"], 0, "the dynamo rides ERG")
	assert_eq(rig.state.score.evades_tried, 1, "the diesel could have")


func test_nobody_can_evade_in_the_first_300_s_and_it_is_not_an_evade_tried() -> void:
	var rig := _rig(2)
	rig.plan_t = 100.0
	_shooter(rig, TankIds.ENEMY_DESTROYER, 150.0, 4.5)
	_sprint(rig, 1, 2.0)
	rig.run(5.0)
	assert_eq(_evades(rig)[0]["ok"], 0)
	assert_eq(rig.state.score.evades_tried, 0)


func test_any_rider_who_can_evade_will_do_and_the_lowest_slot_is_credited() -> void:
	var rig := _rig(3)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 150.0, 4.5)
	_sprint(rig, 3)
	rig.run(5.0)
	var ev := _evades(rig)
	assert_eq([ev[0]["id"], ev[0]["ok"], ev[0]["s"]], [td.id, 1, 2], "the steam rider (slot 2)")
	assert_eq([rig.rider(3).evades_ok, rig.rider(1).evades_ok], [1, 0])
	assert_eq(rig.rider(1).evades_tried, 1, "the diesel could have")


func test_a_shooter_killed_inside_its_telegraph_resolves_nothing() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 150.0, 4.5)
	rig.run(1.0)
	TankShells.kill_enemy(rig.state, TankAux.of(rig.state), td, TankEvents.BY_SHELL, 1, rig.events)
	rig.run(5.0)
	assert_eq(_evades(rig).size(), 0)
	assert_true(TankAux.of(rig.state).evade.is_empty(), "its telegraph is forgotten")


## A destroyer shifting after a shot keeps counting, and its next shot still runs a full telegraph.
func test_a_destroyer_shot_after_a_shift_still_gets_a_full_telegraph() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 150.0, 4.5)
	rig.run(5.0)
	assert_eq(td.mode, TankIds.EM_MOVE)
	var longest := 0.0
	for _i in roundi(12.0 / Wl.SIM_DT):
		rig.step()
		longest = maxf(longest, td.telegraph_s)
	assert_almost_eq(longest, 4.0, 0.06)
	assert_eq(_evades(rig).size(), 2)


func test_an_evaded_shot_sends_no_hit() -> void:
	var rig := _rig(2)
	_shooter(rig, TankIds.ENEMY_DESTROYER, 150.0, 4.5)
	_sprint(rig, 1)
	rig.run(9.0)
	assert_eq(_evades(rig)[0]["ok"], 1)
	var tank_hits := rig.of_type("hit").filter(func(e: Dictionary) -> bool: return e["on"] == 0)
	assert_eq(tank_hits.size(), 0)
	assert_eq(rig.hull().hp, rig.hull().hp_max)
