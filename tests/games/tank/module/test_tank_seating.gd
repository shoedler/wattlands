extends GutTest
## Automatic seating (v3 brief "Seat choice and switching", TankAutopilot.seat_intent; v4 SPEC_TANK
## 3.7): the solo loop (Drive with nothing in range; the Loader while the rack has room once a target
## comes; the Gun while it has shells; Repairs with the hull critical; the Secondaries only when
## nothing else works), crews filling the most needed seats around riders who play their own, and when
## it asks nothing. The situations are given by hand where they hang on the gun's reach (TankAim, the
## rules builder's): this file tests the seating, not the ballistics.


## A fixture state (stage 2's Advance, 200 s in) with no enemies, every rider long on its seat (past
## the Autopilot's minimum stay); the rack full and nothing chambered.
func _state(crew: int) -> TankState:
	var s := TankFixtures.state(crew)
	s.enemies.clear()
	s.shells.clear()
	s.obstacles.clear()
	s.tick = 20 * 3000
	s.seg.elapsed_s = 200.0
	for r in s.riders:
		TankAux.of(s).seat_since[r.peer] = -1.0e9
		r.fallback = true
		r.afk = false
		r.connected = true
	s.hull.loaded = TankIds.SHELL_NONE
	s.hull.hp = s.hull.hp_max
	TankStations.fill_rack(s, TankConst.RACK_MAX)
	_targets(s)
	return s


func _targets(s: TankState) -> void:
	TankTargets.build(s, TankAux.of(s))


## The situation with a far target where the fields say so.
func _fight(rack: int, shells: int, over: Dictionary = {}) -> Dictionary:
	var sit := {
		"targets": true,
		"near": true,
		"gun": true,
		"bow": false,
		"only_light": false,
		"far": false,
		"rack": rack,
		"shells": shells,
		"far_target": true,
		"near_threat": false,
	}
	sit.merge(over, true)
	return sit


## The open road.
func _road(rack: int = TankConst.RACK_MAX) -> Dictionary:
	return _fight(rack, rack, {"targets": false, "near": false, "gun": false, "far_target": false})


func _want(s: TankState, peer: int = 1) -> String:
	var out := TankAutopilot.seat_intent(s, s.rider(peer))
	return str(out.get("to", ""))


func _solo(s: TankState, sit: Dictionary) -> String:
	return TankAutopilot.seat_wanted_solo(s, s.rider(1), sit)


## Puts the rider of `peer` on `engine` (stations follow), as if long seated there.
func _sit(s: TankState, peer: int, engine: String) -> void:
	var r := s.rider(peer)
	var ev: Array[Dictionary] = []
	TankSeats.land(s, r, engine, ev)
	TankAux.of(s).seat_since[peer] = -1.0e9


func test_solo_drives_while_nothing_is_in_range() -> void:
	var s := _state(1)
	_sit(s, 1, TankIds.ENGINE_STEAM)
	assert_eq(_want(s), TankIds.ENGINE_DIESEL)
	var past := _fight(3, 3, {"near": false, "gun": false, "far": true})
	assert_eq(
		_solo(s, past), TankIds.ENGINE_DIESEL, "past the headlight: the solo gun cannot see it"
	)
	_sit(s, 1, TankIds.ENGINE_DIESEL)
	assert_eq(_want(s), "", "already driving")


func test_solo_loads_then_fires_then_loads() -> void:
	var s := _state(1)
	s.seg.seg = TankIds.SEG_GUN_LINE
	assert_eq(
		_solo(s, _fight(1, 1)), TankIds.ENGINE_STEAM, "a target, the rack not full: the Loader"
	)
	_sit(s, 1, TankIds.ENGINE_STEAM)
	s.enemies.clear()
	var e := TankFixturesV4._far(s, 91, TankIds.ENEMY_MEDIUM, 1200.0, 0)
	e.hp = s.content.num("tanks", "damage.heavy", 35.0) * 3.0
	assert_eq(_solo(s, _fight(1, 1)), TankIds.ENGINE_STEAM, "loading while the field needs more")
	e.hp = s.content.num("tanks", "damage.heavy", 35.0)
	assert_eq(
		_solo(s, _fight(1, 1)), TankIds.ENGINE_DYNAMO, "the one shell the field needs: the Gun"
	)
	e.hp = s.content.num("tanks", "damage.heavy", 35.0) * 3.0
	var full := TankConst.RACK_MAX
	assert_eq(_solo(s, _fight(full, full)), TankIds.ENGINE_DYNAMO, "full: the Gun")
	_sit(s, 1, TankIds.ENGINE_DYNAMO)
	assert_eq(_solo(s, _fight(1, 1)), TankIds.ENGINE_DYNAMO, "the Gun while the rack holds shells")
	assert_eq(_solo(s, _fight(0, 1)), TankIds.ENGINE_DYNAMO, "a chambered round is a shell too")
	assert_eq(_solo(s, _fight(0, 0)), TankIds.ENGINE_STEAM, "empty: back to the Loader")


## v4: the solo rider never leaves for the Secondaries unless nothing else works: an empty rack, with
## something for the bow guns in range. A near threat alone does not pull it off Drive.
func test_solo_mans_the_secondaries_only_with_nothing_to_fire() -> void:
	var s := _state(1)
	s.seg.seg = TankIds.SEG_GUN_LINE
	var bow := {"bow": true, "only_light": true}
	assert_eq(_solo(s, _fight(0, 0, bow)), TankIds.ENGINE_FEED, "no round: the bow guns")
	assert_eq(_solo(s, _fight(2, 2, bow)), TankIds.ENGINE_DYNAMO, "shells: the main gun")
	assert_eq(_solo(s, _fight(1, 1, bow)), TankIds.ENGINE_STEAM, "one shell: the Loader first")
	var threat := _road()
	threat["bow"] = true
	threat["only_light"] = true
	threat["near_threat"] = true
	assert_eq(_solo(s, threat), TankIds.ENGINE_DIESEL, "only a near threat: it drives on")


## v4: Repairs when the hull is below 35% and no far target is laid; a laid gun comes first.
func test_solo_repairs_a_critical_hull_when_nothing_is_laid() -> void:
	var s := _state(1)
	s.seg.seg = TankIds.SEG_GUN_LINE
	s.hull.hp = 0.3 * s.hull.hp_max
	assert_eq(_solo(s, _road()), TankIds.ENGINE_REPAIR, "nothing in range")
	var dark := _fight(3, 3, {"near": false, "gun": false, "far": true})
	assert_eq(_solo(s, dark), TankIds.ENGINE_REPAIR, "a target, not laid")
	assert_eq(_solo(s, _fight(3, 3)), TankIds.ENGINE_DYNAMO, "a target laid: the Gun")
	s.hull.hp = 0.4 * s.hull.hp_max
	assert_eq(_solo(s, _road()), TankIds.ENGINE_DIESEL, "40%: no")
	s.hull.hp = 0.0
	s.hull.tow_s = 3.0
	assert_eq(_solo(s, _road()), TankIds.ENGINE_DIESEL, "under a tow the Repairs seat does nothing")


## In an Advance the Repairs stay is spent like any other: back to Drive for the halt line.
func test_solo_repairs_for_one_stay_in_an_advance() -> void:
	var s := _state(1)
	s.hull.hp = 0.3 * s.hull.hp_max
	assert_eq(_want(s), TankIds.ENGINE_REPAIR)
	_sit(s, 1, TankIds.ENGINE_REPAIR)
	assert_eq(_want(s), TankIds.ENGINE_DIESEL)


## 0.3.1: no seat lock; the Autopilot's minimum stay (TankSeats.auto_stay_s: 30 s solo, 60 s a crew)
## keeps it from thrashing.
func test_no_ask_inside_the_stay_on_reserve_or_off_the_second() -> void:
	var s := _state(1)
	_sit(s, 1, TankIds.ENGINE_STEAM)
	var r := s.rider(1)
	assert_eq(_want(s), TankIds.ENGINE_DIESEL)
	TankAux.of(s).seat_since[1] = s.t - 10.0
	assert_eq(_want(s), "", "10 s on the seat: inside the solo's 30 s stay")
	TankAux.of(s).seat_since[1] = s.t - TankConst.AUTO_STAY_SOLO_S
	assert_eq(_want(s), TankIds.ENGINE_DIESEL, "30 s")
	assert_eq(TankSeats.auto_stay_s(_state(3)), TankConst.AUTO_STAY_S, "a crew: 60 s")
	r.afk = true
	assert_eq(_want(s), "", "on reserve")
	r.afk = false
	s.tick += 1
	assert_eq(_want(s), "", "once a second")
	s.tick += TankAutopilot.SEAT_EVERY_TICKS - 1
	var out := TankAutopilot.seat_intent(s, r)
	assert_eq(str(out["to"]), TankIds.ENGINE_DIESEL)
	assert_true(TankIntents.normalize(out)["auto"], "tagged auto: never ends a fallback")
	assert_false(TankIntents.is_deliberate(TankIntents.normalize(out)))


func test_a_crew_fills_the_most_needed_seats() -> void:
	var s := _state(3)
	for peer in [1, 2, 3]:
		assert_eq(_want(s, peer), "", "on the road with a full rack: Drive, Gun, Loader stay")
	var road_fight := _fight(1, 1, {"near": false, "gun": false, "far": true})
	assert_eq(
		TankAutopilot.seat_wanted_crew(s, s.rider(1), road_fight),
		TankIds.ENGINE_DIESEL,
		"a fight on the road keeps the driver driving"
	)
	# A gun line with the rack full and the heavy past the headlight (dark: out of the gun's reach):
	# the Loader's rider stays (3: the fight will need the rack), the Gun's takes the Lights (3.4
	# beats a Gun with nothing to lay on, 2), Drive stays manned (3.2: the next Advance needs it).
	s.seg.seg = TankIds.SEG_GUN_LINE
	var full := TankConst.RACK_MAX
	var sit := _fight(full, full, {"near": false, "gun": false, "far": true})
	var needs := TankAutopilot.seat_needs(s, sit)
	assert_almost_eq(float(needs[TankIds.ENGINE_ARC]), 3.4, 1e-9)
	assert_almost_eq(float(needs[TankIds.ENGINE_STEAM]), 3.0, 1e-9)
	assert_almost_eq(float(needs[TankIds.ENGINE_DYNAMO]), 2.0, 1e-9)
	assert_eq(
		TankAutopilot.seat_wanted_crew(s, s.rider(3), sit), TankIds.ENGINE_STEAM, "Loader stays"
	)
	assert_eq(
		TankAutopilot.seat_wanted_crew(s, s.rider(2), sit), TankIds.ENGINE_ARC, "Gun to Lights"
	)
	assert_eq(
		TankAutopilot.seat_wanted_crew(s, s.rider(1), sit), TankIds.ENGINE_DIESEL, "Drive stays"
	)


func test_riders_who_play_their_own_seat_are_left_there() -> void:
	var s := _state(3)
	var sit := _fight(1, 1)
	s.rider(1).fallback = false
	s.rider(1).autopilot = false
	assert_eq(
		TankAutopilot.seat_wanted_crew(s, s.rider(2), sit), TankIds.ENGINE_DYNAMO, "the autos"
	)
	assert_eq(
		TankAutopilot.seat_wanted_crew(s, s.rider(3), sit), TankIds.ENGINE_STEAM, "keep theirs"
	)
	s.rider(3).fallback = false
	s.rider(3).autopilot = false
	assert_eq(
		TankAutopilot.seat_wanted_crew(s, s.rider(2), sit),
		TankIds.ENGINE_DYNAMO,
		"the one auto rider keeps the most needed seat it has"
	)


## In a fight with shells to fire and a barricade for the bow guns the Lights (3.4: lit, the gun
## reaches the field with half the dark dispersion) stay manned before the Secondaries (3.5 is not 0.5
## more), the brief's order.
func test_a_crew_of_4_keeps_the_lights_manned_in_a_fight() -> void:
	var s := _state(4)
	var full := TankConst.RACK_MAX
	var sit := _fight(full, full, {"bow": true, "only_light": true})
	var needs := TankAutopilot.seat_needs(s, sit)
	assert_almost_eq(float(needs[TankIds.ENGINE_ARC]), 3.4, 1e-9)
	assert_almost_eq(float(needs[TankIds.ENGINE_FEED]), 3.5, 1e-9)
	assert_eq(TankAutopilot.seat_wanted_crew(s, s.rider(4), sit), TankIds.ENGINE_ARC, "Lights stay")
	assert_eq(
		TankAutopilot.seat_wanted_crew(s, s.rider(3), sit),
		TankIds.ENGINE_FEED,
		"the idle Loader (rack full) takes the bow guns"
	)


## A target only the bow guns can reach (the main gun has nothing to lay on): the Secondaries (4.6)
## come before a Gun with nothing to lay on (2), and the Gun's rider takes them.
func test_the_secondaries_come_first_when_the_main_gun_has_nothing_to_lay_on() -> void:
	var s := _state(2)
	var sit := {
		"targets": true,
		"near": true,
		"gun": false,
		"bow": true,
		"only_light": true,
		"far": false,
		"rack": TankConst.RACK_MAX,
		"shells": TankConst.RACK_MAX,
	}
	var needs := TankAutopilot.seat_needs(s, sit)
	assert_almost_eq(float(needs[TankIds.ENGINE_FEED]), 4.6, 1e-9)
	assert_almost_eq(float(needs[TankIds.ENGINE_DYNAMO]), 2.0, 1e-9)
	assert_eq(TankAutopilot.seat_wanted_crew(s, s.rider(2), sit), TankIds.ENGINE_FEED)
	assert_eq(TankAutopilot.seat_wanted_crew(s, s.rider(1), sit), TankIds.ENGINE_DIESEL)
	sit["gun"] = true
	assert_almost_eq(float(TankAutopilot.seat_needs(s, sit)[TankIds.ENGINE_FEED]), 3.5, 1e-9)
	assert_eq(TankAutopilot.seat_wanted_crew(s, s.rider(2), sit), TankIds.ENGINE_DYNAMO)


## v4: a near threat: the Secondaries (4.7) take the Loader's rider of a crew; Drive and a Gun with
## something to lay on stay. The whole way: the seat intent inside the segment's opening.
func test_a_crew_mans_the_secondaries_for_a_near_threat() -> void:
	var s := _state(3)
	s.seg.elapsed_s = 40.0
	TankStations.fill_rack(s, 1)
	var sit := _fight(1, 1, {"near_threat": true, "bow": true, "only_light": true})
	assert_almost_eq(float(TankAutopilot.seat_needs(s, sit)[TankIds.ENGINE_FEED]), 4.7, 1e-9)
	assert_eq(TankAutopilot.seat_wanted_crew(s, s.rider(3), sit), TankIds.ENGINE_FEED)
	assert_eq(TankAutopilot.seat_wanted_crew(s, s.rider(2), sit), TankIds.ENGINE_DYNAMO)
	assert_eq(TankAutopilot.seat_wanted_crew(s, s.rider(1), sit), TankIds.ENGINE_DIESEL)
	assert_eq(_want(s, 2), "", "no near threat yet: the opening holds every seat")
	TankFixturesV4._near(s, 92, TankIds.ENEMY_RECON, 60.0, 0)
	_targets(s)
	assert_eq(
		_want(s, 2), TankIds.ENGINE_FEED, "the threat opens the move at 40 s: an idle Gun goes"
	)


## v3 solo balance: in an Advance the solo rider leaves Drive for one stay at most, then drives on
## to the halt line (an Advance begun on another seat has had its stay).
func test_solo_leaves_drive_once_per_advance() -> void:
	var s := _state(1)
	var sit := _fight(3, 3)
	assert_eq(_solo(s, sit), TankIds.ENGINE_DYNAMO, "a target, shells: the Gun")
	_sit(s, 1, TankIds.ENGINE_DYNAMO)
	assert_eq(_solo(s, sit), TankIds.ENGINE_DIESEL, "the stay is spent: back to Drive")
	s.seg.seg = TankIds.SEG_GUN_LINE
	assert_eq(_solo(s, sit), TankIds.ENGINE_DYNAMO, "at a gun line the loop keeps the Gun")


## v3 solo balance: from Drive the solo rider goes straight to the Gun with SOLO_GUN_FIRST shells or
## more (rack and chamber), else to the Loader first.
func test_solo_goes_to_the_gun_first_with_two_shells() -> void:
	var s := _state(1)
	s.seg.seg = TankIds.SEG_GUN_LINE
	assert_eq(_solo(s, _fight(1, 1)), TankIds.ENGINE_STEAM, "1 shell: the Loader first")
	assert_eq(TankAutopilot.SOLO_GUN_FIRST, 2)
	assert_eq(_solo(s, _fight(1, 2)), TankIds.ENGINE_DYNAMO, "2 shells: the Gun")


## Planning the next fight: a gun line or the boss is a far fight with no near threat yet, so the bow
## guns have nothing and the solo rider takes the Gun with the shells for it. An Advance is the road.
func test_the_seating_plans_the_next_segment_as_a_far_fight() -> void:
	var s := _state(1)
	var gl := TankIds.SEG_GUN_LINE
	var sit := TankAutopilot.expected(s, gl)
	assert_true(sit["far_target"])
	assert_true(sit["gun"])
	assert_false(sit["near_threat"])
	assert_false(sit["bow"])
	assert_false(sit["only_light"])
	assert_eq(TankAutopilot.seat_wanted_solo(s, s.rider(1), sit, gl), TankIds.ENGINE_DYNAMO)
	var road := TankAutopilot.expected(s, TankIds.SEG_ADVANCE)
	assert_false(road["far_target"])
	assert_false(road["targets"])


## 0.3.1: the automatic seating keeps the trainer's mode through a warm-up segment (the depot, the
## drill's skirmish: the drill allows a rider one switch, its checkpoint); a same-mode move is fine,
## and the same move outside a warm-up goes ahead.
func test_no_automatic_mode_switch_in_a_warm_up() -> void:
	var s := _state(1)
	_sit(s, 1, TankIds.ENGINE_DYNAMO)
	var ri := TankRiderInput.new()
	ri.peer = 1
	ri.phase_kind = Wl.WARMUP
	ri.phase_mode = Wl.ERG
	TankAux.of(s).seat_input[1] = ri
	TankAux.of(s).trainer_mode[1] = Wl.ERG
	assert_eq(_want(s), "", "Drive (SIM) waits for the warm-up's end")
	TankAux.of(s).trainer_mode[1] = Wl.SIM
	assert_eq(_want(s), TankIds.ENGINE_DIESEL, "SIM -> SIM is no switch")
	TankAux.of(s).trainer_mode[1] = Wl.ERG
	ri.phase_kind = Wl.WORK
	assert_eq(_want(s), TankIds.ENGINE_DIESEL, "outside a warm-up: Drive")
