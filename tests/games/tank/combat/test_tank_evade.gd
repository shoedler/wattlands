extends GutTest
## "Surge to evade" (brief 2.4; v4: telegraph + flight at least 6 s at Hard): every telegraph type
## (the Behemoth's is in test_tank_boss.gd), the miss rule (a rider who can evade holds the sprint rule
## 2 s inside the telegraph and the shell's flight), who can evade (SIM WORK phases past the first
## 300 s, never ERG riders, reserve or rescue), the evade event at landing and the results counts.

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
	var rig := TankRulesRig.new(crew, "ashfall_road", 7, _quiet(ADVANCE))
	rig.no_fire = true
	rig.enter(ADVANCE, 5.0)
	rig.hull().hp = 100000.0
	rig.hull().hp_max = 100000.0
	# The sprint rule averages a full 3 s window: ride on target long enough to fill it first.
	rig.run(3.5)
	return rig


## A tough enemy of `type` holding at `range_m` whose gun fires in `gun_s` seconds, its flight known.
func _shooter(rig: TankRulesRig, type: String, range_m: float, gun_s: float) -> TankEnemyState:
	var e := rig.far(type, range_m)
	e.hp = 5000.0
	e.hp_max = 5000.0
	e.gun_s = gun_s
	return e


func _flight(range_m: float) -> float:
	return TankBallistics.far_flight(
		TankBallistics.far_elevation(range_m, 560.0, 70.0), 560.0, 70.0
	)


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
	gl.plan_t = 900.0
	gl.enter(GUN_LINE, 5.0)
	assert_true(gl.rider(1).can_evade, "v3: Drive digs in SIM flat at a gun line")
	assert_false(gl.rider(2).can_evade, "the Gun rides ERG")
	var depot := TankRulesRig.new(1)
	depot.enter(0, 100.0)
	assert_false(depot.rider(1).can_evade, "WARMUP")
	var drill := TankRulesRig.new(1, "drill")
	drill.enter(1, 10.0)
	assert_false(drill.rider(1).can_evade, "the drill's WARMUP skirmish")
	var citadel := _rig(3)
	citadel.run(0.1)
	assert_true(citadel.rider(3).can_evade, "the steam engine rides SIM too")


func test_the_telegraphs() -> void:
	var c := TankFixtures.content()
	assert_eq(float(c.enemy_def(TankIds.ENEMY_DESTROYER)["telegraph_s"]), 5.0)
	assert_eq(float(c.enemy_def(TankIds.ENEMY_HEAVY)["telegraph_s"]), 5.0)
	assert_eq(float(c.enemy_def(TankIds.ENEMY_LIGHT)["flank"]["telegraph_s"]), 6.5)
	assert_eq(float(c.boss_def()["main"]["telegraph_s"]), 6.0)


func test_a_destroyer_telegraphs_and_a_sprint_held_2_s_makes_it_miss_at_landing() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	rig.run(0.6)
	assert_eq(td.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(td.telegraph_s, 4.95, 0.06, "a 5 s glint")
	_sprint(rig, 1)
	rig.run(4.85)
	assert_eq(rig.of_type("shot").size(), 0, "not yet fired")
	rig.run(0.2)
	var shot := rig.of_type("shot").filter(func(e: Dictionary) -> bool: return e["src"] == td.id)
	assert_eq(shot.size(), 1, "fired")
	assert_eq(_evades(rig).size(), 0, "the evade comes at landing, after its shot")
	var s: TankShellState = rig.state.shells.back()
	assert_true(s.evadable, "still evadable in flight")
	assert_true(TankAux.of(rig.state).evade.has(TankEvade.shell_key(s.id)), "the entry moved")
	assert_false(TankAux.of(rig.state).evade.has(td.id))
	rig.run(_flight(1800.0))
	var ev := _evades(rig)
	assert_eq(ev.size(), 1)
	assert_eq([ev[0]["id"], ev[0]["e"], ev[0]["ok"], ev[0]["s"]], [td.id, 3, 1, 0])
	assert_eq(rig.of_type("hit").size(), 0, "evaded: it misses")
	assert_eq(rig.of_type("splash").size(), 1)
	assert_eq([rig.rider(1).evades_ok, rig.rider(1).evades_tried], [1, 1])
	assert_eq([rig.rider(2).evades_ok, rig.rider(2).evades_tried], [0, 0], "the ERG dynamo")
	assert_eq([rig.state.score.evades_ok, rig.state.score.evades_tried], [1, 1])


func test_without_a_sprint_the_telegraphed_shot_is_rolled_and_counts_as_tried() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	rig.run(6.0 + _flight(1800.0))
	var ev := _evades(rig)
	assert_eq(ev.size(), 1)
	assert_eq([ev[0]["id"], ev[0]["ok"], ev[0]["s"]], [td.id, 0, -1])
	assert_eq([rig.state.score.evades_ok, rig.state.score.evades_tried], [0, 1])
	assert_eq([rig.rider(1).evades_ok, rig.rider(1).evades_tried], [0, 1])


func test_a_sprint_held_too_little_of_telegraph_and_flight_is_not_enough() -> void:
	var rig := _rig(2)
	_shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	var f := _flight(1800.0)
	rig.run(5.5 + f - 1.8)
	_sprint(rig, 1, 3.0)
	rig.run(2.0)
	assert_eq(_evades(rig)[0]["ok"], 0, "the rule held for about 1 s before it landed")


## v4: accumulation runs through the telegraph and the flight: a sprint that starts as the shell leaves
## the barrel can still make it miss.
func test_the_hold_runs_across_telegraph_and_flight() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 2200.0, 5.5)
	rig.run(5.6)
	assert_eq(rig.of_type("shot").size(), 1, "fired")
	assert_almost_eq(rig.state.shells.back().left_s, _flight(2200.0) - 0.1, 0.15)
	_sprint(rig, 1, 3.0)
	rig.run(_flight(2200.0))
	var ev := _evades(rig)
	assert_eq(ev.size(), 1)
	assert_eq([ev[0]["id"], ev[0]["ok"]], [td.id, 1], "held 2 s inside the 4 s flight")


func test_a_heavy_tank_telegraphs_5_s() -> void:
	var rig := _rig(2)
	var hv := _shooter(rig, TankIds.ENEMY_HEAVY, 1500.0, 5.5)
	rig.run(0.6)
	assert_eq(hv.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(hv.telegraph_s, 4.95, 0.06)
	_sprint(rig, 1, 2.5)
	rig.run(5.0 + _flight(1500.0))
	var ev := _evades(rig)
	assert_eq(ev.size(), 1)
	assert_eq([ev[0]["id"], ev[0]["e"], ev[0]["ok"]], [hv.id, 5, 1], "a hard 2.5 x FTP surge")


## The light tank's first shot at its hold is its flank shot: telegraphed, 8 damage at 70%; its later
## shots are its plain gun, untelegraphed.
func test_a_light_tanks_first_shot_at_its_hold_is_a_telegraphed_flank_shot() -> void:
	var rig := _rig(2)
	var lt := _shooter(rig, TankIds.ENEMY_LIGHT, 900.0, 3.0)
	var flank: Dictionary = rig.content.enemy_def(TankIds.ENEMY_LIGHT)["flank"]
	assert_eq([flank["telegraph_s"], flank["damage"], flank["hit"]], [6.5, 8.0, 0.7])
	rig.run(0.6)
	assert_eq(lt.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(lt.telegraph_s, 5.95, 0.06, "the countdown ran down: a full telegraph from it")
	rig.run(6.0)
	var mine := rig.state.shells.filter(func(s: TankShellState) -> bool: return s.source == lt.id)
	assert_eq(mine.size(), 1)
	assert_eq(mine[0].damage, 8.0, "the flank shot")
	assert_true(mine[0].evadable)
	rig.run(_flight(900.0) + 0.1)
	assert_eq(_evades(rig).size(), 1, "at landing")
	rig.run(5.5)
	assert_eq(_evades(rig).size(), 1, "the next shot is not telegraphed")
	assert_eq(lt.telegraph_s, 0.0)
	var shots := rig.of_type("shot").filter(func(e: Dictionary) -> bool: return e["src"] == lt.id)
	assert_eq(shots.size(), 2)


## A light rolls in: its countdown waits, and the flank shot gets its full telegraph once it holds,
## however little of the countdown was left.
func test_a_light_rolling_in_gets_its_full_flank_telegraph_at_its_hold() -> void:
	var rig := _rig(2)
	var aux := TankAux.of(rig.state)
	var lt := TankFar.spawn(rig.state, aux, TankIds.ENEMY_LIGHT, -1.0, false, -1)
	lt.gun_s = 0.5
	var t := rig.run_until(func() -> bool: return lt.mode == TankIds.EM_TELEGRAPH, 30.0)
	assert_lt(t, 30.0, "it reached its hold and telegraphs")
	assert_almost_eq(lt.telegraph_s, 6.5, 0.06, "a full telegraph")


func test_an_erg_rider_sprinting_does_not_evade() -> void:
	var rig := _rig(2)
	_shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	_sprint(rig, 2, 2.0)
	rig.run(6.0 + _flight(1800.0))
	assert_eq(_evades(rig)[0]["ok"], 0, "the dynamo rides ERG")
	assert_eq(rig.state.score.evades_tried, 1, "the diesel could have")


func test_nobody_can_evade_in_the_first_300_s_and_it_is_not_an_evade_tried() -> void:
	var rig := _rig(2)
	rig.plan_t = 100.0
	_shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	_sprint(rig, 1, 2.0)
	rig.run(6.0 + _flight(1800.0))
	assert_eq(_evades(rig)[0]["ok"], 0)
	assert_eq(rig.state.score.evades_tried, 0)


func test_any_rider_who_can_evade_will_do_and_the_lowest_slot_is_credited() -> void:
	var rig := _rig(3)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	_sprint(rig, 3)
	rig.run(6.0 + _flight(1800.0))
	var ev := _evades(rig)
	assert_eq([ev[0]["id"], ev[0]["ok"], ev[0]["s"]], [td.id, 1, 2], "the steam rider (slot 2)")
	assert_eq([rig.rider(3).evades_ok, rig.rider(1).evades_ok], [1, 0])
	assert_eq(rig.rider(1).evades_tried, 1, "the diesel could have")


func test_a_shooter_killed_inside_its_telegraph_resolves_nothing() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	rig.run(1.0)
	TankShells.kill_enemy(rig.state, TankAux.of(rig.state), td, TankEvents.BY_SHELL, 1, rig.events)
	rig.run(5.0)
	assert_eq(_evades(rig).size(), 0)
	assert_true(TankAux.of(rig.state).evade.is_empty(), "its telegraph is forgotten")


## v4: once the shell is in the air its shooter's death changes nothing: it lands and resolves.
func test_a_dead_shooters_shell_still_resolves() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	_sprint(rig, 1)
	rig.run(5.6)
	assert_eq(rig.of_type("shot").size(), 1)
	TankShells.kill_enemy(rig.state, TankAux.of(rig.state), td, TankEvents.BY_SHELL, 1, rig.events)
	rig.run(_flight(1800.0))
	var ev := _evades(rig)
	assert_eq(ev.size(), 1, "it still raises its evade")
	assert_eq([ev[0]["id"], ev[0]["e"], ev[0]["ok"]], [td.id, 3, 1])
	assert_true(TankAux.of(rig.state).evade.is_empty())


## A destroyer shifting after a shot keeps counting, and its next shot still runs a full telegraph.
func test_a_destroyer_shot_after_a_shift_still_gets_a_full_telegraph() -> void:
	var rig := _rig(2)
	var td := _shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	rig.run(6.0)
	assert_eq(td.mode, TankIds.EM_MOVE)
	var longest := 0.0
	for _i in roundi(30.0 / Wl.SIM_DT):
		rig.step()
		longest = maxf(longest, td.telegraph_s)
	assert_almost_eq(longest, 5.0, 0.06)
	assert_eq(_evades(rig).size(), 2)


func test_an_evaded_shot_sends_no_hit() -> void:
	var rig := _rig(2)
	_shooter(rig, TankIds.ENEMY_DESTROYER, 1800.0, 5.5)
	_sprint(rig, 1)
	rig.run(6.5 + _flight(1800.0))
	assert_eq(_evades(rig)[0]["ok"], 1)
	var tank_hits := rig.of_type("hit").filter(func(e: Dictionary) -> bool: return e["on"] == 0)
	assert_eq(tank_hits.size(), 0)
	assert_eq(rig.hull().hp, rig.hull().hp_max)
