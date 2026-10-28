extends GutTest
## Seats (v3 brief "Seat choice and switching"; TankSeats): the seat lock from every plan boundary,
## seat intents (a named seat, next / prev over empty seats), refusals (lock, manned or claimed
## seat, reserve, cool-down, no legal replan), the claim (seat_target), cancelling, and the move
## landing when the plan's seat changes (stations, the seat event, the lock).

const DEPOT := 0
const ADVANCE := 1
const CHECKPOINT := 3
const BOSS := 10


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


func test_the_lock_counts_60_s_down_from_every_plan_boundary() -> void:
	var rig := _rig(2, DEPOT, 0.0)
	assert_almost_eq(rig.rider(1).seat_lock_s, TankConst.SEAT_LOCK_S, 1e-6, "the plan's start")
	rig.run(30.0)
	assert_almost_eq(rig.rider(1).seat_lock_s, 30.0, 0.06)
	rig.run(31.0)
	assert_eq(rig.rider(1).seat_lock_s, 0.0, "open after 60 s")
	rig.enter(ADVANCE, 0.0)
	assert_almost_eq(rig.rider(1).seat_lock_s, TankConst.SEAT_LOCK_S, 1e-6, "a segment boundary")
	assert_almost_eq(rig.rider(2).seat_lock_s, TankConst.SEAT_LOCK_S, 1e-6)


func test_a_seat_intent_is_refused_while_the_lock_runs() -> void:
	var rig := _rig(2, ADVANCE, 0.0)
	rig.send(1, TankIntents.seat(TankIds.ENGINE_STEAM))
	rig.run(0.05)
	assert_eq(rig.rider(1).seat_target, "", "locked")
	rig.run(60.0)
	rig.send(1, TankIntents.seat(TankIds.ENGINE_STEAM))
	rig.run(0.05)
	assert_eq(rig.rider(1).seat_target, TankIds.ENGINE_STEAM, "open: the move is pending")
	assert_eq(rig.rider(1).engine, TankIds.ENGINE_DIESEL, "the rider sits where it was")


func test_only_an_empty_unclaimed_seat_can_be_taken() -> void:
	var rig := _rig(3, ADVANCE, 0.0)
	rig.run(61.0)
	rig.send(1, TankIntents.seat(TankIds.ENGINE_DYNAMO))
	rig.run(0.05)
	assert_eq(rig.rider(1).seat_target, "", "the Gun is manned")
	rig.send(1, TankIntents.seat(TankIds.ENGINE_ARC))
	rig.send(2, TankIntents.seat(TankIds.ENGINE_ARC))
	rig.run(0.05)
	assert_eq(rig.rider(1).seat_target, TankIds.ENGINE_ARC)
	assert_eq(rig.rider(2).seat_target, "", "slot 0 claimed the Lights first")
	rig.send(2, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	assert_eq(rig.rider(2).seat_target, TankIds.ENGINE_FEED)


func test_next_and_prev_step_over_manned_and_claimed_seats() -> void:
	var rig := _rig(3, ADVANCE, 0.0)
	rig.run(61.0)
	# Seats in order: Drive (1), Gun (2), Loader (3), Lights, Secondaries: from the Gun, next is the
	# Lights (the Loader is manned), prev wraps to the Secondaries (Drive is manned).
	rig.send(2, TankIntents.seat(TankIds.SEAT_TO_NEXT))
	rig.run(0.05)
	assert_eq(rig.rider(2).seat_target, TankIds.ENGINE_ARC)
	rig.send(1, TankIntents.seat(TankIds.SEAT_TO_NEXT))
	rig.run(0.05)
	assert_eq(rig.rider(1).seat_target, TankIds.ENGINE_FEED, "the Lights are claimed by slot 1")
	rig.send(2, TankIntents.seat(TankIds.SEAT_TO_PREV))
	rig.run(0.05)
	assert_eq(rig.rider(2).seat_target, TankIds.ENGINE_ARC, "nothing else is free that way")


func test_asking_for_ones_own_seat_cancels_the_move() -> void:
	var rig := _rig(2, ADVANCE, 0.0)
	rig.run(61.0)
	rig.send(2, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	assert_eq(rig.rider(2).seat_target, TankIds.ENGINE_FEED)
	rig.send(2, TankIntents.seat(TankIds.ENGINE_DYNAMO))
	rig.run(0.05)
	assert_eq(rig.rider(2).seat_target, "")


func test_no_move_on_reserve_or_in_the_cool_down() -> void:
	var rig := _rig(2, ADVANCE, 0.0)
	rig.run(61.0)
	rig.afk[2] = true
	rig.send(2, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	assert_eq(rig.rider(2).seat_target, "", "on reserve")
	rig.afk.erase(2)
	rig.enter(rig.segs().size(), 61.0)
	rig.send(2, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	assert_eq(rig.rider(2).seat_target, "", "the cool-down")


## The boss is the last segment: a move that cannot split it before its max_s could only land in
## the cool-down, so it is refused (a mode change within 60 s of a planned one).
func test_a_move_with_no_legal_replan_is_refused() -> void:
	var rig := _rig(2, BOSS, 0.0)
	rig.run(61.0)
	var max_s := float(rig.content.segment(BOSS)["max_s"])
	rig.seg_t = max_s - 30.0
	rig.send(1, TankIntents.seat(TankIds.ENGINE_DYNAMO))
	rig.send(1, TankIntents.seat(TankIds.ENGINE_ARC))
	rig.run(0.05)
	assert_eq(rig.rider(1).seat_target, "", "Drive (SIM) to Lights (ERG) 30 s before max_s")
	rig.send(1, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	assert_eq(rig.rider(1).seat_target, TankIds.ENGINE_FEED, "SIM to SIM: no mode change")


func test_the_move_lands_when_the_plan_seat_changes() -> void:
	var rig := _rig(2, ADVANCE, 0.0)
	rig.run(61.0)
	rig.send(2, TankIntents.seat(TankIds.ENGINE_FEED))
	rig.run(0.05)
	var before := rig.events.size()
	rig.seat(2, TankIds.ENGINE_FEED)
	rig.run(0.05)
	var r := rig.rider(2)
	assert_eq(r.engine, TankIds.ENGINE_FEED)
	assert_eq(r.seat_target, "")
	assert_eq(rig.feed().slot, r.slot)
	assert_eq(rig.feed().peer, 2)
	assert_true(rig.dynamo().is_empty(), "the Gun is empty now")
	var seat := rig.of_type("seat", rig.events.slice(before))
	assert_eq(seat.size(), 1)
	assert_eq(
		[seat[0]["s"], seat[0]["from"], seat[0]["to"]],
		[r.slot, TankIds.engine_code(TankIds.ENGINE_DYNAMO), TankIds.engine_code("feed")]
	)


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
