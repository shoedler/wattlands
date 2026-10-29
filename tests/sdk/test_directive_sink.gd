extends GutTest
## DirectiveRouter, the host's ctx.directives (BRIEF 3.6, 4.5, 4.6.6, 4.6.7; BRIEF 7.1 "the
## DirectiveSink"; docs/OWNERSHIP.md DS1-DS13, PL6, PL20; 3.1 C4, C25, C26). Local riders
## are fake LocalRiders with a real MockTrainer; remote riders are captured sends.

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")

var _root: Node = null
var _router: DirectiveRouter = null
var _tracker: PhaseTracker = null
var _clock: SimClock = null
var _bus: WlEventBus = null
var _rider: LocalRider = null
var _sent: Array = []
var _applied: Array = []
var _bands: Array = []
var _unsafe_tm: Telemetry = null


## Phases (all inside the warm-up limits): 0 ERG 50% 60 s range [45, 60]; 1 ERG 60% 120 s
## range [55, 65]; 2 SIM game 60 s; 3 ERG 60% open-ended 10..100 s range [50, 65];
## 4 the cool-down.
func _plan() -> EffortPlan:
	return (
		PlanValidator
		. finalize(
			(
				EffortPlan
				. of(
					[
						PlanPhase.erg(Wl.WARMUP, 50, 60, "Warm").with_range(45, 60),
						PlanPhase.erg(Wl.WORK, 60, 120, "Push").with_range(55, 65),
						PlanPhase.sim(Wl.FREE, Wl.GRADE_GAME, 60, "Climb"),
						PlanPhase.erg(Wl.WORK, 60, 0, "Hold").with_range(50, 65).with_open(10, 100),
					]
				)
			)
		)
	)


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_sent = []
	_applied = []
	_bands = []
	_unsafe_tm = null
	_clock = SimClock.create()
	_tracker = PhaseTracker.new()
	_bus = Kit.new_bus(_root, "Bus")
	var s1 := Kit.human(1, 0, 200.0)
	var s2 := Kit.human(2, 1, 250.0)
	var s3 := Kit.human(3, 2, 200.0)
	s3.haptics_on = false
	_rider = Kit.rider(_root, s1)
	for peer: int in [1, 2, 3]:
		_tracker.add_rider(peer, _plan())
	_router = DirectiveRouter.new()
	_router.role = Wl.HOST
	_router.tracker = _tracker
	_router.clock = _clock
	_router.slots = {1: s1, 2: s2, 3: s3}
	_router.bind_riders({1: _rider})
	_router.bus = _bus
	_router.remote_send = func(peer: int, payload: Dictionary) -> void:
		_sent.append([peer, payload])
	_router.telemetry_of = func(_peer: int) -> Variant: return _unsafe_tm
	_bus.directive_applied.connect(
		func(peer: int, rec: Dictionary) -> void: _applied.append([peer, rec])
	)
	_bus.cadence_band_changed.connect(
		func(peer: int, lo: float, hi: float) -> void: _bands.append([peer, lo, hi])
	)


func _start() -> void:
	_tracker.start()


## Advance the session by `seconds` of game time (phase changes, grade flushes, switches).
func _advance(seconds: float) -> void:
	for i in PhaseTracker.ticks(seconds):
		_tracker.advance(_clock.game_tick)
		_router.flush(_clock.game_tick + 1)
		_tracker.update_modes(_clock.game_tick + 1)
		_clock.step()


func _req(fields: Dictionary, peer: int = 1) -> DirectiveResult:
	return _router.request(peer, EffortDirective.from_dict(fields))


func _fake() -> Object:
	return _rider


func test_refused_before_the_session_starts() -> void:
	var r := _req({"target_pct": 50})
	assert_false(r.accepted)
	assert_eq(r.reason, Wl.REFUSE_NO_PHASE)
	assert_gt(r.id, 0, "refusals get an id too")
	assert_push_warning("refused: no_phase")
	assert_eq(_applied.size(), 1)
	assert_true(bool(_applied[0][1]["refused"]))
	assert_eq(_applied[0][1]["reason"], Wl.REFUSE_NO_PHASE)


func test_unknown_peer() -> void:
	_start()
	assert_eq(_req({"target_pct": 50}, 42).reason, Wl.REFUSE_UNKNOWN_PEER)


func test_accepted_erg_target_reaches_the_local_rider_with_an_id() -> void:
	_start()
	var r := _req({"target_pct": 55, "duration_s": 5, "reason": "pull", "source": "test"})
	assert_true(r.accepted)
	assert_eq(r.id, 1)
	var dirs: Array = _fake().get("directives")
	assert_eq(dirs.size(), 1)
	assert_eq((dirs[0] as EffortDirective).id, 1)
	assert_eq((dirs[0] as EffortDirective).target_pct, 55.0)
	assert_eq(_applied.size(), 1, "the governor's record goes out as directive_applied")
	assert_false(bool(_applied[0][1]["refused"]))
	assert_eq(int(_applied[0][1]["id"]), 1)
	assert_eq(_req({"target_pct": 56}).id, 2, "ids increase")


func test_target_outside_range_pct_is_refused() -> void:
	_start()
	var r := _req({"target_pct": 61})
	assert_false(r.accepted)
	assert_eq(r.reason, Wl.REFUSE_RANGE)
	assert_push_warning("outside_range_pct")
	assert_eq((_fake().get("directives") as Array).size(), 0)
	assert_eq(_req({"target_pct": 44.9}).reason, Wl.REFUSE_RANGE)
	assert_true(_req({"target_pct": 45}).accepted, "the range is inclusive")


func test_target_w_and_wkg_are_converted_to_pct() -> void:
	_start()
	_advance(60)
	assert_eq(_tracker.index_of(1), 1)
	assert_true(_req({"target_w": 120}).accepted, "120 W of 200 W = 60%")
	assert_eq(_req({"target_w": 140}).reason, Wl.REFUSE_RANGE, "70%")
	assert_true(_req({"target_wkg": 1.6}).accepted, "1.6 W/kg x 75 kg reference = 120 W = 60%")
	assert_true(_req({"target_w": 150}, 2).accepted, "peer 2 has FTP 250: 60%")
	var wkg := Kit.human(9, 0, 300.0)
	wkg.scaling_mode = Wl.WKG
	wkg.p_eff_per_w = 75.0 / 60.0
	assert_almost_eq(DirectiveRouter.weight_of(wkg), 60.0, 1e-9)


func test_remote_rider_gets_a_directive_message() -> void:
	_start()
	var r := _req({"target_pct": 50, "reason": "bank"}, 2)
	assert_true(r.accepted)
	assert_eq(_sent.size(), 1)
	assert_eq(_sent[0][0], 2)
	var payload: Dictionary = _sent[0][1]
	assert_eq(payload["kind"], NetMessages.DIRECTIVE_REQUEST)
	assert_eq(payload["id"], r.id)
	assert_eq(
		payload["directive"], {"target_pct": 50.0, "duration_s": 0.0, "reason": "bank", "id": r.id}
	)
	assert_eq(_applied.size(), 0, "a remote rider's record arrives later as an ack")


func test_governor_refusal_is_reported_but_the_host_check_passed() -> void:
	_start()
	_fake().set("refuse_reason", Wl.REFUSE_HAPTIC_WARMUP)
	_advance(180)
	var r := _req({"haptic": 2.0, "duration_s": 1.5})
	assert_true(r.accepted, "accepted covers host-side checks only")
	assert_true(bool(_applied[0][1]["refused"]))
	assert_eq(_applied[0][1]["reason"], Wl.REFUSE_HAPTIC_WARMUP)


func test_a_block_the_governor_refuses_is_taken_back() -> void:
	_start()
	_fake().set("refuse_reason", Wl.REFUSE_SIM_BLOCK_UNSAFE)
	var r := _req({"mode": "SIM", "duration_s": 10})
	assert_true(r.accepted, "the host-side checks passed")
	assert_true(bool(_applied[0][1]["refused"]), "the governor refused it")
	assert_false(_tracker.block_active(1, _clock.game_tick), "no block runs")
	assert_eq(_tracker.last_switch_tick(1), PhaseTracker.NO_SWITCH, "and no switch happened")
	assert_eq(_tracker.mode_now(1), Wl.ERG)
	assert_eq(
		_req({"mode_grade": 2.0}).reason, Wl.REFUSE_MODE_GRADE, "no SIM block to hold a grade"
	)
	_fake().set("refuse_reason", "")
	assert_true(
		_req({"mode": "SIM", "duration_s": 10}).accepted,
		"spacing is not spent on a block that never ran"
	)
	assert_true(_tracker.block_active(1, _clock.game_tick))


func test_a_remote_block_refused_in_its_ack_is_taken_back() -> void:
	_start()
	assert_true(_req({"mode": "SIM", "duration_s": 10}, 2).accepted)
	assert_true(
		_tracker.block_active(2, _clock.game_tick), "the host assumes it runs until the ack"
	)
	var id := int(_sent[0][1]["id"])
	_router.on_ack(2, {"id": id + 99, "refused": true})
	assert_true(
		_tracker.block_active(2, _clock.game_tick), "another directive's ack changes nothing"
	)
	_router.on_ack(2, {"id": id, "refused": true})
	assert_false(_tracker.block_active(2, _clock.game_tick))
	assert_eq(_tracker.last_switch_tick(2), PhaseTracker.NO_SWITCH)
	assert_true(_req({"mode": "SIM", "duration_s": 10}, 2).accepted)
	_router.on_ack(2, {"id": int(_sent[1][1]["id"]), "refused": false})
	assert_true(_tracker.block_active(2, _clock.game_tick), "an applied block stays")


func test_sim_block_length() -> void:
	_start()
	assert_eq(_req({"mode": "SIM", "duration_s": 9.9}).reason, Wl.REFUSE_SIM_BLOCK_LENGTH)
	assert_eq(_req({"mode": "SIM", "duration_s": 30.1}).reason, Wl.REFUSE_SIM_BLOCK_LENGTH)
	assert_eq(
		_req({"mode": "SIM"}).reason, Wl.REFUSE_SIM_BLOCK_LENGTH, "duration 0 is not a block length"
	)
	assert_true(_req({"mode": "SIM", "duration_s": 10, "reason": "overdrive"}).accepted)
	assert_true(_tracker.block_active(1, _clock.game_tick))


func test_sim_block_spacing_and_the_bracketing_exemption() -> void:
	_start()
	assert_true(_req({"mode": "SIM", "duration_s": 10}).accepted)
	# W2 round 2: a second mode SIM while the block runs only confirms it (DirectiveSink
	# contract, as the governor does), so it neither switches nor counts against spacing.
	assert_true(
		_req({"mode": "SIM", "duration_s": 10}).accepted, "0 s after the entry: a confirmation"
	)
	assert_eq(_tracker.last_switch_tick(1), 0, "the confirmation is no switch")
	_advance(10)
	assert_false(
		_tracker.block_active(1, _clock.game_tick), "the block expired (its exit is exempt)"
	)
	_advance(29.95)
	assert_eq(
		_req({"mode": "SIM", "duration_s": 10}).reason,
		Wl.REFUSE_SWITCH_SPACING,
		"29.95 s after the exit"
	)
	_advance(0.05)
	assert_true(_req({"mode": "SIM", "duration_s": 10}).accepted, "30 s after the exit")
	assert_true(_req({"mode": "ERG"}).accepted, "an early exit right after the entry is exempt")
	assert_eq(
		_req({"mode": "SIM", "duration_s": 10}).reason,
		Wl.REFUSE_SWITCH_SPACING,
		"the exit was 0 s ago"
	)


## W2 round 2 (docs/TRAINER.md known difference 7): mode SIM in an ERG phase while a SIM block
## runs is a confirmation, as the DirectiveSink contract and the governor say: it is accepted
## whatever its duration_s, never extends or re-checks the block, and carries its haptic (the
## haptic rules still apply: never in ERG, never for an opted-out rider).
func test_mode_sim_during_a_running_block_confirms_it_and_carries_its_haptic() -> void:
	_start()
	assert_eq(
		_req({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5}).reason,
		Wl.REFUSE_SIM_BLOCK_LENGTH,
		"with no block running a mode SIM haptic would open a 1.5 s block"
	)
	assert_true(_req({"mode": "SIM", "duration_s": 20, "reason": "overdrive"}).accepted)
	_advance(5)
	_unsafe_tm = Telemetry.new()
	_unsafe_tm.rescue = true
	var r := _req({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5, "reason": "hit"})
	assert_true(r.accepted, "a confirmation plus its haptic, not a too-short block")
	assert_eq(r.reason, "")
	var dirs: Array = _fake().get("directives")
	assert_eq(
		(dirs[dirs.size() - 1] as EffortDirective).to_dict(),
		{"mode": "SIM", "haptic": 2.0, "duration_s": 1.5, "reason": "hit", "id": r.id},
		"the governor gets the request as sent and confirms it"
	)
	assert_true(
		_req({"mode": "SIM", "duration_s": 40, "mode_grade": 3.0}).accepted,
		"no length or safety re-check"
	)
	_unsafe_tm = null
	assert_eq(_tracker.last_switch_tick(1), 0, "no switch")
	_advance(14.95)
	assert_true(_tracker.block_active(1, _clock.game_tick), "the block still runs at 19.95 s")
	_advance(0.05)
	assert_false(
		_tracker.block_active(1, _clock.game_tick), "and ends at its own 20 s: never extended"
	)
	assert_eq(
		_req({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5}).reason,
		Wl.REFUSE_SIM_BLOCK_LENGTH,
		"after the block a mode SIM haptic is a block request again"
	)
	assert_eq(
		_req({"haptic": 2.0, "duration_s": 1.5}).reason,
		Wl.REFUSE_HAPTIC_ERG,
		"and a bare haptic is in ERG"
	)
	assert_push_warning("haptic_in_erg")


func test_a_confirmation_keeps_the_haptic_rules_and_a_remote_block() -> void:
	_start()
	assert_true(_req({"mode": "SIM", "duration_s": 20}, 3).accepted)
	assert_eq(
		_req({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5}, 3).reason,
		Wl.REFUSE_HAPTIC_OFF,
		"peer 3 opted out of haptics"
	)
	assert_true(_req({"mode": "SIM", "duration_s": 20}, 2).accepted)
	var open_id := int(_sent[_sent.size() - 1][1]["id"])
	var r := _req({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5}, 2)
	assert_true(r.accepted)
	assert_eq(
		_sent[_sent.size() - 1][1]["directive"]["mode"],
		"SIM",
		"the remote governor gets it as sent"
	)
	_router.on_ack(2, {"id": r.id, "refused": true, "reason": Wl.REFUSE_HAPTIC_COOLDOWN})
	assert_true(
		_tracker.block_active(2, _clock.game_tick),
		"a refused confirmation never takes the block back"
	)
	_router.on_ack(2, {"id": open_id, "refused": false})
	assert_true(_tracker.block_active(2, _clock.game_tick))


func test_plan_phase_changes_count_as_switches() -> void:
	_start()
	_advance(180)
	assert_eq(_tracker.index_of(1), 2, "SIM phase")
	_advance(60)
	assert_eq(_tracker.index_of(1), 3, "back to ERG at 240 s: a switch")
	_advance(10)
	assert_eq(_req({"mode": "SIM", "duration_s": 10}).reason, Wl.REFUSE_SWITCH_SPACING)
	_advance(20)
	assert_true(_req({"mode": "SIM", "duration_s": 10}).accepted)


func test_erg_request_ends_a_block_early() -> void:
	_start()
	assert_true(_req({"mode": "SIM", "duration_s": 20}).accepted)
	_advance(5)
	assert_true(_req({"mode": "ERG"}).accepted, "the exit is part of the bracketing pair")
	assert_false(_tracker.block_active(1, _clock.game_tick))


func test_sim_block_refused_while_unsafe_c26() -> void:
	_start()
	_unsafe_tm = Telemetry.new()
	_unsafe_tm.rescue = true
	assert_eq(_req({"mode": "SIM", "duration_s": 10}).reason, Wl.REFUSE_SIM_BLOCK_UNSAFE)
	_unsafe_tm.rescue = false
	_unsafe_tm.paused = true
	assert_eq(_req({"mode": "SIM", "duration_s": 10}).reason, Wl.REFUSE_SIM_BLOCK_UNSAFE)


func test_mode_sim_in_a_sim_phase_is_a_no_op_confirmation_c4() -> void:
	_start()
	_advance(180)
	var r := _req({"mode": "SIM", "mode_grade": 4.0, "reason": "boiler"})
	assert_true(r.accepted, "no block length rule in a SIM phase")
	assert_false(_tracker.block_active(1, _clock.game_tick), "no block is opened")
	assert_true(
		_req({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5, "reason": "hit"}).accepted,
		"Tank's 1.5 s hit haptic"
	)
	assert_eq(_req({"mode": "ERG"}).reason, Wl.REFUSE_ERG_IN_SIM)
	assert_eq(_req({"target_pct": 50}).reason, Wl.REFUSE_RANGE, "no ERG range in a SIM phase")


func test_mode_grade_only_in_sim() -> void:
	_start()
	assert_eq(_req({"mode_grade": 2.0}).reason, Wl.REFUSE_MODE_GRADE)
	assert_true(
		_req({"mode": "SIM", "duration_s": 15, "mode_grade": 2.0}).accepted,
		"inside the block it opens"
	)
	assert_true(_req({"mode_grade": 3.0}).accepted, "while the block runs")


func test_a_short_haptic_over_a_held_mode_grade_touches_only_its_channel_ds3() -> void:
	# BRIEF 7.1: "a 1.5 s haptic over a held mode_grade leaves the grade in place". The sink's
	# part: the haptic request carries only its own channel to the governor and never ends or
	# re-opens the SIM block that holds the grade.
	_start()
	assert_true(
		_req({"mode": "SIM", "duration_s": 20, "mode_grade": 2.0, "reason": "overdrive"}).accepted
	)
	_advance(2)
	assert_true(_req({"haptic": 2.0, "duration_s": 1.5, "reason": "hit"}).accepted)
	var dirs: Array = _fake().get("directives")
	assert_eq(
		(dirs[1] as EffortDirective).to_dict(),
		{"haptic": 2.0, "duration_s": 1.5, "reason": "hit", "id": 2},
		"no mode, no mode_grade: the governor changes only the haptic term"
	)
	_advance(1.5)
	assert_true(
		_tracker.block_active(1, _clock.game_tick), "the block and its grade hold after the haptic"
	)
	assert_eq(_tracker.last_switch_tick(1), 0, "no switch from the haptic")
	assert_true(_req({"mode_grade": 3.0}).accepted, "the grade channel is still open")
	_advance(16.5)
	assert_false(_tracker.block_active(1, _clock.game_tick), "the block expires on its own 20 s")


func test_haptics() -> void:
	_start()
	assert_eq(_req({"haptic": 2.0, "duration_s": 1.5}).reason, Wl.REFUSE_HAPTIC_ERG)
	assert_push_warning("haptic_in_erg")
	_advance(180)
	assert_true(_req({"haptic": 2.0, "duration_s": 1.5}).accepted)
	assert_eq(_req({"haptic": 2.0, "duration_s": 1.5}, 3).reason, Wl.REFUSE_HAPTIC_OFF)


func test_bad_fields() -> void:
	_start()
	assert_eq(_router.request(1, EffortDirective.new()).reason, Wl.REFUSE_BAD_FIELDS, "nothing set")
	assert_eq(_req({"target_pct": 50, "duration_s": -1}).reason, Wl.REFUSE_BAD_FIELDS)
	assert_eq(_req({"mode": "TURBO"}).reason, Wl.REFUSE_BAD_FIELDS)
	assert_eq(_router.request(1, null).reason, Wl.REFUSE_BAD_FIELDS)


func test_everything_is_refused_in_the_cooldown_ds12() -> void:
	_start()
	_advance(240)
	_advance(100)
	assert_true(_tracker.is_cooldown(1))
	_applied.clear()
	assert_eq(_req({"target_pct": 50}).reason, Wl.REFUSE_COOLDOWN)
	_router.course_grade(1, 2.0)
	assert_false(_router.end_phase(1))
	_router.cadence_band(1, 80, 90)
	assert_eq(_applied.size(), 4, "each refusal is recorded")
	for a: Array in _applied:
		assert_eq(a[1]["reason"], Wl.REFUSE_COOLDOWN)


func test_course_grade_only_in_game_grade_phases() -> void:
	_start()
	_router.course_grade(1, 3.0)
	assert_eq(_applied[0][1]["reason"], Wl.REFUSE_NOT_GAME_GRADE)
	assert_push_warning("grade_source_not_game")
	assert_eq((_fake().get("grades") as Array).size(), 0)


func test_course_grade_is_coalesced_to_2_hz() -> void:
	_start()
	_advance(180)
	_router.course_grade(1, 1.0)
	assert_eq(_fake().get("grades"), [1.0] as Array[float], "the first goes out at once")
	_router.course_grade(1, 2.0)
	_advance(0.1)
	_router.course_grade(1, 3.0)
	_advance(0.3)
	assert_eq(_fake().get("grades"), [1.0] as Array[float], "held for 0.5 s")
	_advance(0.1)
	assert_eq(_fake().get("grades"), [1.0, 3.0] as Array[float], "only the newest value")
	_router.course_grade(2, 4.0)
	assert_eq(_sent.size(), 1)
	assert_eq(_sent[0][1]["kind"], NetMessages.DIRECTIVE_COURSE_GRADE)
	assert_eq(_sent[0][1]["grade_pct"], 4.0)


func test_pending_course_grade_is_dropped_at_a_phase_change() -> void:
	_start()
	_advance(180)
	_advance(59.8)
	_router.course_grade(1, 1.0)
	_router.course_grade(1, 5.0)
	_advance(0.5)
	assert_eq(_tracker.index_of(1), 3)
	assert_eq(_fake().get("grades"), [1.0] as Array[float])


func test_end_phase() -> void:
	_start()
	assert_false(_router.end_phase(1))
	assert_eq(_applied[0][1]["reason"], Wl.REFUSE_NOT_OPEN_ENDED)
	_advance(240)
	assert_eq(_tracker.index_of(1), 3)
	assert_false(_router.end_phase(1))
	assert_eq(_applied[1][1]["reason"], Wl.REFUSE_MIN_S)
	_advance(10)
	assert_true(_router.end_phase(1))
	assert_true(_router.end_phase(2), "every rider in one step")
	_advance(0.05)
	assert_true(_tracker.is_cooldown(1))
	assert_true(_tracker.is_cooldown(2))
	assert_eq(_tracker.history(1)[3]["ended_by"], Wl.ENDED_END_PHASE)
	assert_false(_router.end_phase(42))


func test_cadence_band_reaches_rider_mock_trainer_and_hud_and_clears() -> void:
	_start()
	_router.cadence_band(1, 80, 96)
	assert_eq(_fake().get("band_cadence"), [80.0, 96.0])
	var mock: Object = _rider.device
	assert_eq(mock.call("last_cadence_band"), [80.0, 96.0], "MockTrainer's band policy gets it")
	assert_eq(_bands, [[1, 80.0, 96.0]], "the HUD's cadence widget gets it")
	_router.cadence_band(2, 60, 120)
	assert_eq(
		_sent[0][1],
		{
			"kind": NetMessages.DIRECTIVE_CADENCE_BAND,
			"id": _sent[0][1]["id"],
			"peer": 2,
			"lo_rpm": 60.0,
			"hi_rpm": 120.0
		}
	)
	_advance(60)
	assert_eq(_router.cadence_band_of(1), [80.0, 96.0], "holds across phases")
	_router.cadence_band(1, 0, 0)
	assert_eq(_fake().get("band_cadence"), [0.0, 0.0], "(0, 0) clears")
	assert_eq(mock.call("last_cadence_band"), [0.0, 0.0])
	_router.cadence_band(1, 90, 80)
	assert_eq(_applied[_applied.size() - 1][1]["reason"], Wl.REFUSE_BAD_FIELDS)


func test_cooldown_clears_the_band() -> void:
	_start()
	_router.cadence_band(1, 80, 96)
	_bands.clear()
	_router.clear_bands(1)
	assert_eq(_fake().get("band_cadence"), [0.0, 0.0])
	assert_eq(_bands, [[1, 0.0, 0.0]])
	_router.clear_bands(1)
	assert_eq(_bands.size(), 1, "nothing to clear twice")


func test_replan_between_phases() -> void:
	_start()
	var rest := EffortPlan.of([PlanPhase.erg(Wl.WORK, 60, 30, "Rotated").with_range(55, 65)])
	assert_true(_router.replan(1, rest))
	assert_eq(_tracker.phase_of(1).label, "Warm", "the current phase continues")
	_advance(60)
	assert_eq(_tracker.phase_of(1).label, "Rotated")
	assert_eq(_tracker.state(1).count, 3)


func test_replan_rejection_keeps_the_old_plan() -> void:
	_start()
	var bad := EffortPlan.of([PlanPhase.erg(Wl.WORK, 90, 30, "Too early")])
	assert_false(_router.replan(1, bad))
	assert_eq(_applied[0][1]["reason"], Wl.REFUSE_PLAN_INVALID)
	assert_push_warning("plan_invalid")
	_advance(60)
	assert_eq(_tracker.phase_of(1).label, "Push")


## split (tank 0.3.1): the current phase ends at the end of this tick whatever its min_s or kind,
## and the new remaining plan starts; the phase that ended counts as the time it ran.
func test_split_ends_the_current_phase_now() -> void:
	_start()
	_advance(10)
	var rest := EffortPlan.of([PlanPhase.erg(Wl.WARMUP, 55, 20, "Split rest").with_range(50, 60)])
	assert_true(_router.split(1, rest), "a fixed phase, 10 s into its 60")
	assert_eq(_tracker.phase_of(1).label, "Warm", "until the end of this tick")
	_advance(0.05)
	assert_eq(_tracker.phase_of(1).label, "Split rest")
	assert_eq(_tracker.history(1)[0]["ended_by"], Wl.ENDED_END_PHASE)
	assert_almost_eq(float(_tracker.history(1)[0]["end"]), 10.05, 0.06)
	assert_eq(_tracker.phase_of(2).label, "Warm", "only that rider")
	_advance(20)
	assert_true(_tracker.is_cooldown(1), "the rest, then the cool-down")


## The split is validated on the real timeline: an ERG <-> SIM switch at the split and another one
## 10 s later warns (BRIEF 4.5), a warm-up breach is rejected and changes nothing.
func test_split_validates_with_the_phase_at_its_length() -> void:
	var warned: Array = []
	_router.on_replan = func(peer: int, warnings: Array) -> void: warned.append([peer, warnings])
	_start()
	_advance(5)
	var close := (
		EffortPlan
		. of(
			[
				PlanPhase.sim(Wl.WARMUP, Wl.GRADE_GAME, 10, "Short climb"),
				PlanPhase.erg(Wl.WARMUP, 50, 60, "Back").with_range(45, 60),
			]
		)
	)
	assert_true(_router.split(1, close))
	assert_eq(warned.size(), 1)
	assert_gt((warned[0][1] as Array).size(), 0, "switches 10 s apart: a spacing warning")
	var bad := EffortPlan.of([PlanPhase.erg(Wl.WORK, 90, 30, "Too early")])
	assert_false(_router.split(2, bad))
	assert_push_warning("plan_invalid")
	_advance(0.05)
	assert_eq(_tracker.phase_of(2).label, "Warm", "a rejected split keeps the phase")


func test_split_is_refused_in_the_cooldown_and_on_a_client() -> void:
	_start()
	_advance(240)
	_advance(100)
	assert_true(_tracker.is_cooldown(1))
	assert_false(_router.split(1, EffortPlan.new()))
	assert_eq(_applied.back()[1]["reason"], Wl.REFUSE_COOLDOWN)
	_router.role = Wl.CLIENT
	assert_false(_router.split(2, EffortPlan.new()))
	assert_push_warning_count(2)


func test_split_model_closes_the_phase_at_its_length() -> void:
	var m := PlanValidator.split_model(_plan(), 3, 12.0)
	assert_false(m.phase(3).open_ended)
	assert_eq(m.phase(3).duration_s, 12.0)
	assert_true(_plan().phase(3).open_ended, "a copy")
	assert_eq(PlanValidator.split_model(_plan(), 0, 0.0).phase(0).duration_s, Wl.SIM_DT)


func test_client_calls_are_ignored_with_a_warning() -> void:
	_router.role = Wl.CLIENT
	_start()
	assert_eq(_req({"target_pct": 50}).reason, Wl.REFUSE_NOT_AUTHORITY)
	_router.course_grade(1, 1.0)
	assert_false(_router.end_phase(1))
	_router.cadence_band(1, 80, 90)
	assert_false(_router.replan(1, EffortPlan.new()))
	assert_push_warning_count(5)
	assert_eq((_fake().get("directives") as Array).size(), 0)


func test_report_keeps_requested_and_applied() -> void:
	var rep := ReportCollector.new()
	_router.report = rep
	_start()
	_req({"target_pct": 55})
	_req({"target_pct": 99})
	assert_eq(rep.directives.size(), 2)
	assert_true(bool(rep.directives[0]["accepted"]))
	assert_not_null(rep.directives[0]["applied"])
	assert_false(bool(rep.directives[1]["accepted"]))
	assert_eq(rep.directives[1]["reason"], Wl.REFUSE_RANGE)
	assert_true(bool((rep.directives[1]["applied"] as Dictionary)["refused"]))
	assert_eq(
		rep.directives[0]["requested"],
		{"target_pct": 55.0, "duration_s": 0.0, "id": 1},
		"the game's keys plus duration_s and the sink's id (GAME_SDK 8.1)"
	)
