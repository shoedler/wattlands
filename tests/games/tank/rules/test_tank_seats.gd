extends GutTest
## Seats (0.3.1 "seats without a lock"; TankSeats): a seat intent (a named seat, next / prev over
## empty seats) lands at once on any empty seat at any time outside the cool-down (stations, the
## seat event), with no seat lock at a stage change or anywhere else; refusals (a manned seat,
## reserve, the cool-down); back and forth; the trainer's switches tracked for TankSeatPlan.follow.

const HANGAR := 0
const ROLLOUT := 1
const ADVANCE := 2
const GUN_LINE := 3
const CHECKPOINT := 4
const BOSS := 11


static func _quiet(index: int) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(
			{"encounters": [], "obstacles": []}, true
		)


func _rig(crew: int, index: int = ADVANCE, into_s: float = 1.0) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", 7, _quiet(index))
	rig.no_fire = true
	rig.enter(index, into_s)
	return rig


## The rig's seat events since `from` (index into rig.events).
func _seats(rig: TankRulesRig, from: int) -> Array[Dictionary]:
	return rig.of_type("seat", rig.events.slice(from))


func test_a_move_lands_at_once_on_any_empty_seat() -> void:
	var rig := _rig(2, ADVANCE, 0.0)
	var before := rig.events.size()
	rig.send(2, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	var r := rig.rider(2)
	assert_eq(r.engine, TankIds.ENGINE_FEED, "the segment's first tick, no lock")
	assert_eq(rig.feed().slot, r.slot)
	assert_eq(rig.feed().peer, 2)
	assert_true(rig.dynamo().is_empty(), "the Gun is empty now")
	var seat := _seats(rig, before)
	assert_eq(seat.size(), 1)
	assert_eq(
		[seat[0]["s"], seat[0]["from"], seat[0]["to"]],
		[r.slot, TankIds.engine_code(TankIds.ENGINE_DYNAMO), TankIds.engine_code("feed")]
	)


## Bug report (0.3.0): the seat lock came back at every new stage. There is none now: a rider who
## just moved moves again at once, in the same segment and right after a stage change.
func test_no_seat_lock_after_a_stage_change() -> void:
	var rig := _rig(2, GUN_LINE, 50.0)
	rig.send(1, TankIntents.seat(TankIds.ENGINE_ARC))
	rig.run(0.05)
	assert_eq(rig.rider(1).engine, TankIds.ENGINE_ARC)
	rig.enter(CHECKPOINT, 0.0)
	rig.run(0.05)
	rig.send(1, TankIntents.seat(TankIds.ENGINE_STEAM))
	rig.run(0.05)
	assert_eq(rig.rider(1).engine, TankIds.ENGINE_STEAM, "a new stage, moved at once")
	rig.enter(ADVANCE + 3, 0.0)
	rig.send(1, TankIntents.seat(TankIds.SEAT_TO_NEXT))
	rig.run(0.05)
	assert_eq(rig.rider(1).engine, TankIds.ENGINE_ARC, "and again after the next stage change")
	assert_false("seat_lock_s" in rig.rider(1), "the field is gone")


func test_only_an_empty_seat_can_be_taken() -> void:
	var rig := _rig(3, ADVANCE, 0.0)
	rig.send(1, TankIntents.seat(TankIds.ENGINE_DYNAMO))
	rig.run(0.05)
	assert_eq(rig.rider(1).engine, TankIds.ENGINE_DIESEL, "the Gun is manned")
	rig.send(1, TankIntents.seat(TankIds.ENGINE_ARC))
	rig.send(2, TankIntents.seat(TankIds.ENGINE_ARC))
	rig.run(0.05)
	assert_eq(rig.rider(1).engine, TankIds.ENGINE_ARC)
	assert_eq(rig.rider(2).engine, TankIds.ENGINE_DYNAMO, "slot 0 took the Lights first")
	rig.send(2, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	assert_eq(rig.rider(2).engine, TankIds.ENGINE_FEED)


func test_next_and_prev_step_over_manned_seats() -> void:
	var rig := _rig(3, ADVANCE, 0.0)
	# Seats in order: Drive (1), Gun (2), Loader (3), Lights, Secondaries: from the Gun, next is the
	# Lights (the Loader is manned), prev wraps to the Secondaries (Drive is manned).
	rig.send(2, TankIntents.seat(TankIds.SEAT_TO_NEXT))
	rig.run(0.05)
	assert_eq(rig.rider(2).engine, TankIds.ENGINE_ARC)
	rig.send(1, TankIntents.seat(TankIds.SEAT_TO_NEXT))
	rig.run(0.05)
	assert_eq(rig.rider(1).engine, TankIds.ENGINE_DYNAMO, "the Gun is free now, next from Drive")
	rig.send(2, TankIntents.seat(TankIds.SEAT_TO_PREV))
	rig.run(0.05)
	assert_eq(rig.rider(2).engine, TankIds.ENGINE_DIESEL, "Drive is free now, prev from the Lights")


## Back and forth: every move lands at once, both ways, each with its seat event.
func test_back_and_forth_lands_every_move() -> void:
	var rig := _rig(2, ADVANCE, 0.0)
	var before := rig.events.size()
	rig.send(2, TankIntents.seat(TankIds.ENGINE_STEAM))
	rig.run(0.05)
	rig.send(2, TankIntents.seat(TankIds.ENGINE_DYNAMO))
	rig.run(0.05)
	assert_eq(rig.rider(2).engine, TankIds.ENGINE_DYNAMO)
	assert_eq(_seats(rig, before).size(), 2)
	rig.send(2, TankIntents.seat(TankIds.ENGINE_DYNAMO))
	rig.run(0.05)
	assert_eq(_seats(rig, before).size(), 2, "asking for one's own seat does nothing")


func test_no_move_on_reserve_or_in_the_cool_down() -> void:
	var rig := _rig(2, ADVANCE, 0.0)
	rig.afk[2] = true
	rig.send(2, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	assert_eq(rig.rider(2).engine, TankIds.ENGINE_DYNAMO, "on reserve")
	rig.afk.erase(2)
	rig.enter(rig.segs().size(), 61.0)
	rig.send(2, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	assert_eq(rig.rider(2).engine, TankIds.ENGINE_DYNAMO, "the cool-down")


## TankAux.last_switch_s: the game time a rider's plan phase changed mode (its trainer's ERG <->
## SIM switch, what TankSeatPlan.follow spaces 30 s apart); a boundary without a mode change is none.
func test_the_trainer_switches_are_tracked() -> void:
	var rig := _rig(2, ADVANCE, 0.0)
	rig.run(0.05)
	var aux := TankAux.of(rig.state)
	assert_false(aux.last_switch_s.has(1), "no switch yet")
	rig.enter(GUN_LINE, 0.0)
	rig.run(0.05)
	assert_false(aux.last_switch_s.has(1), "Drive: SIM to SIM")
	rig.enter(CHECKPOINT, 0.0)
	rig.run(0.05)
	assert_almost_eq(float(aux.last_switch_s[1]), rig.state.t - 0.05, 0.06, "the checkpoint's ERG")
	assert_false(aux.last_switch_s.has(2), "the Gun: ERG all along")


func test_an_empty_seat_does_nothing() -> void:
	# Crew 1: only Drive is manned. The Loader loads nothing, the Gun neither chambers nor lays,
	# the searchlights stay dark, the bow guns stay silent.
	var rig := _rig(1, ADVANCE, 1.0)
	var e := rig.spawn(TankIds.ENEMY_LIGHT, 1, 130.0)
	e.gun_s = 1.0e6
	var elev := rig.hull().elev_deg
	var rack := rig.steam().rack
	rig.run(20.0)
	assert_eq(rig.steam().rack, rack, "no reloads")
	assert_eq(rig.steam().pressure_pct, 0.0)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE, "nothing chambered")
	assert_eq(rig.hull().elev_deg, elev, "the gun stays where it is")
	assert_false(rig.arc().lit)
	assert_eq(rig.feed().rounds, 0)
	assert_eq(rig.dynamo().p_eff_w, 0.0)
	# And an empty Drive seat stops the tank.
	var two := _rig(2, ADVANCE, 1.0)
	two.seat(1, TankIds.ENGINE_STEAM)
	two.run(5.0)
	assert_true(two.diesel().is_empty())
	assert_eq(two.hull().speed_mps, 0.0, "nobody drives")
