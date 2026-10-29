extends GutTest
## Automatic seating (v3 brief "Seat choice and switching", TankAutopilot.seat_intent): the solo
## loop (Drive with nothing in range; the Loader while the rack has room once a target comes; the
## Gun while it has shells; the Secondaries when only light targets stand in the bow guns' range),
## crews filling the most needed seats around riders who play their own, and when it asks nothing.


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
	TankStations.fill_rack(s, TankConst.RACK_MAX)
	_targets(s)
	return s


func _targets(s: TankState) -> void:
	TankTargets.build(s, TankAux.of(s))


## An enemy `dist` px off the hull's front, ahead.
func _enemy(s: TankState, type: String, dist: float, id: int = 90) -> TankEnemyState:
	var front := s.hull.x_px + s.hull.hull_w
	var e := TankFixtures._enemy(id, type, front + dist, 30.0, 1)
	s.enemies.append(e)
	_targets(s)
	return e


func _want(s: TankState, peer: int = 1) -> String:
	var out := TankAutopilot.seat_intent(s, s.rider(peer))
	return str(out.get("to", ""))


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
	var far := _enemy(s, TankIds.ENEMY_MEDIUM, 400.0)
	assert_eq(_want(s), TankIds.ENGINE_DIESEL, "past the headlight: the solo gun cannot see it")
	s.enemies.erase(far)
	_sit(s, 1, TankIds.ENGINE_DIESEL)
	_targets(s)
	assert_eq(_want(s), "", "already driving")


func test_solo_loads_then_fires_then_loads() -> void:
	var s := _state(1)
	s.seg.seg = TankIds.SEG_GUN_LINE
	_enemy(s, TankIds.ENEMY_MEDIUM, 240.0)
	TankStations.fill_rack(s, 1)
	assert_eq(_want(s), TankIds.ENGINE_STEAM, "a target, the rack not full: the Loader")
	_sit(s, 1, TankIds.ENGINE_STEAM)
	assert_eq(_want(s), "", "loading until the rack is full")
	TankStations.fill_rack(s, TankConst.RACK_MAX)
	assert_eq(_want(s), TankIds.ENGINE_DYNAMO, "full: the Gun")
	_sit(s, 1, TankIds.ENGINE_DYNAMO)
	TankStations.fill_rack(s, 1)
	assert_eq(_want(s), "", "the Gun while the rack holds shells")
	TankStations.fill_rack(s, 0)
	s.hull.loaded = TankIds.SHELL_HEAVY
	assert_eq(_want(s), "", "a chambered round is a shell too")
	s.hull.loaded = TankIds.SHELL_NONE
	assert_eq(_want(s), TankIds.ENGINE_STEAM, "empty: back to the Loader")


func test_solo_mans_the_secondaries_when_only_lights_are_near() -> void:
	var s := _state(1)
	_enemy(s, TankIds.ENEMY_LIGHT, 130.0)
	assert_eq(_want(s), TankIds.ENGINE_FEED)
	var far := _enemy(s, TankIds.ENEMY_MEDIUM, 240.0, 91)
	assert_eq(_want(s), TankIds.ENGINE_FEED, "a medium past 220 px does not count")
	s.enemies.erase(far)
	_enemy(s, TankIds.ENEMY_MEDIUM, 190.0, 92)
	assert_eq(_want(s), TankIds.ENGINE_DYNAMO, "a medium within 220 px: the main gun (rack full)")


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
	_enemy(s, TankIds.ENEMY_HEAVY, 280.0)
	TankStations.fill_rack(s, 1)
	assert_eq(_want(s, 1), "", "a fight on the road keeps the driver driving")
	# A gun line with the rack full and the heavy past the headlight (dark: out of the gun's reach):
	# the Loader's rider stays (3: the fight will need the rack), the Gun's takes the Lights (3.4
	# beats a Gun with nothing to lay on, 2), Drive stays manned (3.2: the next Advance needs it).
	s.seg.seg = TankIds.SEG_GUN_LINE
	TankStations.fill_rack(s, TankConst.RACK_MAX)
	var needs := TankAutopilot.seat_needs(s)
	assert_almost_eq(float(needs[TankIds.ENGINE_ARC]), 3.4, 1e-9)
	assert_almost_eq(float(needs[TankIds.ENGINE_STEAM]), 3.0, 1e-9)
	assert_almost_eq(float(needs[TankIds.ENGINE_DYNAMO]), 2.0, 1e-9)
	assert_eq(_want(s, 3), "", "the Loader stays")
	assert_eq(_want(s, 2), TankIds.ENGINE_ARC, "the Gun to the Lights")
	assert_eq(_want(s, 1), "", "Drive stays manned at a gun line")


func test_riders_who_play_their_own_seat_are_left_there() -> void:
	var s := _state(3)
	(s.station(TankIds.ENGINE_ARC) as TankArcState).lit = true
	_enemy(s, TankIds.ENEMY_HEAVY, 280.0)
	TankStations.fill_rack(s, 1)
	s.rider(1).fallback = false
	s.rider(1).autopilot = false
	assert_eq(_want(s, 2), "", "the autos keep the Gun and the Loader")
	assert_eq(_want(s, 3), "")
	s.rider(3).fallback = false
	s.rider(3).autopilot = false
	assert_eq(_want(s, 2), "", "the one auto rider keeps the most needed seat it has")


## In a fight with shells to fire the Lights (3.4: lit, the gun reaches the field with half the
## dark dispersion) stay manned before the Secondaries (3.5 is not 0.5 more), the brief's order.
func test_a_crew_of_4_keeps_the_lights_manned_in_a_fight() -> void:
	var s := _state(4)
	(s.station(TankIds.ENGINE_ARC) as TankArcState).lit = true
	_enemy(s, TankIds.ENEMY_MEDIUM, 240.0)
	_enemy(s, TankIds.ENEMY_LIGHT, 130.0, 91)
	assert_true(bool(TankAutopilot.situation(s)["gun"]), "the main gun lays on the medium")
	var needs := TankAutopilot.seat_needs(s)
	assert_almost_eq(float(needs[TankIds.ENGINE_ARC]), 3.4, 1e-9)
	assert_almost_eq(float(needs[TankIds.ENGINE_FEED]), 3.5, 1e-9)
	assert_eq(_want(s, 4), "", "the Lights' rider stays")
	assert_eq(_want(s, 3), TankIds.ENGINE_FEED, "the idle Loader (rack full) takes the bow guns")


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


## v3 solo balance: in an Advance the solo rider leaves Drive for one stay at most, then drives on
## to the halt line (an Advance begun on another seat has had its stay).
func test_solo_leaves_drive_once_per_advance() -> void:
	var s := _state(1)
	_enemy(s, TankIds.ENEMY_MEDIUM, 240.0)
	assert_eq(_want(s), TankIds.ENGINE_DYNAMO, "a target, shells: the Gun")
	_sit(s, 1, TankIds.ENGINE_DYNAMO)
	assert_eq(_want(s), TankIds.ENGINE_DIESEL, "the stay is spent: back to Drive")
	s.seg.seg = TankIds.SEG_GUN_LINE
	assert_eq(_want(s), "", "at a gun line the loop keeps the Gun")


## v3 solo balance: from Drive the solo rider goes straight to the Gun with SOLO_GUN_FIRST shells or
## more (rack and chamber), else to the Loader first.
func test_solo_goes_to_the_gun_first_with_two_shells() -> void:
	var s := _state(1)
	s.seg.seg = TankIds.SEG_GUN_LINE
	_enemy(s, TankIds.ENEMY_HEAVY, 230.0)
	TankStations.fill_rack(s, 1)
	assert_eq(_want(s), TankIds.ENGINE_STEAM, "1 shell: the Loader first")
	s.hull.loaded = TankIds.SHELL_HEAVY
	assert_eq(TankAutopilot.SOLO_GUN_FIRST, 2)
	assert_eq(_want(s), TankIds.ENGINE_DYNAMO, "2 shells: the Gun")


## v3 solo balance: planning a gun line, the solo rider reads what it will meet there: gun line 1's
## dug-in turrets inside the bow guns' range take it to the Secondaries, gun line 2's heavy to the
## Gun (with the shells for it).
func test_solo_plans_a_gun_line_from_its_enemy_list() -> void:
	var s := _state(1)
	s.seg.segment_index = 1
	var sit := TankAutopilot.expected(s, TankIds.SEG_GUN_LINE)
	assert_true(bool(sit["only_light"]), "gun line 1: dug-ins at 110 and 140 px")
	var r := s.rider(1)
	var gl := TankIds.SEG_GUN_LINE
	assert_eq(TankAutopilot.seat_wanted_solo(s, r, sit, gl), TankIds.ENGINE_FEED)
	s.seg.segment_index = 4
	sit = TankAutopilot.expected(s, TankIds.SEG_GUN_LINE)
	assert_false(bool(sit["only_light"]), "gun line 2: the heavy")
	assert_eq(TankAutopilot.seat_wanted_solo(s, r, sit, gl), TankIds.ENGINE_DYNAMO)


## 0.3.1: the automatic seating keeps the trainer's mode through a warm-up segment (the depot, the
## drill's skirmish: the drill allows a rider one switch, its checkpoint); a same-mode move is fine,
## and the same move outside a warm-up goes ahead.
func test_no_automatic_mode_switch_in_a_warm_up() -> void:
	var s := _state(1)
	_enemy(s, TankIds.ENEMY_MEDIUM, 240.0)
	var ri := TankRiderInput.new()
	ri.peer = 1
	ri.phase_kind = Wl.WARMUP
	ri.phase_mode = Wl.SIM
	TankAux.of(s).seat_input[1] = ri
	TankAux.of(s).trainer_mode[1] = Wl.SIM
	assert_eq(_want(s), "", "the Gun (ERG) waits for the warm-up's end")
	TankStations.fill_rack(s, 0)
	assert_eq(_want(s), TankIds.ENGINE_STEAM, "the Loader (SIM -> SIM) is no switch")
	TankStations.fill_rack(s, TankConst.RACK_MAX)
	ri.phase_kind = Wl.WORK
	assert_eq(_want(s), TankIds.ENGINE_DYNAMO, "outside a warm-up: the Gun")
