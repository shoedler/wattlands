extends GutTest
## PhaseTracker: per-rider phase tracking on the authority (BRIEF 3.6; docs/OWNERSHIP.md
## GM20, GM22, IF2, PL12, DS10; the switch bookkeeping behind BRIEF 4.5's spacing rule).

var _tr: PhaseTracker = null
var _tick: int = 0


func before_each() -> void:
	_tr = PhaseTracker.new()
	_tick = 0


func _fin(phases: Array) -> EffortPlan:
	var p := PlanValidator.finalize(EffortPlan.of(phases))
	assert_not_null(p, "fixture plan must validate")
	return p


## Advance n ticks; returns every change.
func _run(n: int) -> Array:
	var all: Array = []
	for i in n:
		all.append_array(_tr.advance(_tick))
		_tr.update_modes(_tick + 1)
		_tick += 1
	return all


func test_start_enters_phase_zero_for_every_rider() -> void:
	_tr.add_rider(1, _fin([PlanPhase.erg(Wl.WARMUP, 50, 1)]))
	_tr.add_rider(-1, _fin([PlanPhase.erg(Wl.WARMUP, 50, 2)]))
	assert_eq(_tr.index_of(1), -1)
	var ch := _tr.start()
	assert_eq(ch.size(), 2)
	assert_eq(ch[0], {"peer": 1, "index": 0, "ended_by": Wl.ENDED_START, "plan_changed": false})
	assert_eq(_tr.index_of(-1), 0)
	assert_eq(_tr.peers(), [1, -1] as Array[int])
	assert_true(_tr.is_started())


func test_fixed_phase_ends_by_duration_on_its_tick() -> void:
	_tr.add_rider(
		1, _fin([PlanPhase.erg(Wl.WARMUP, 50, 1, "A"), PlanPhase.erg(Wl.WORK, 60, 2, "B")])
	)
	_tr.start()
	assert_eq(_run(19), [], "1 s = 20 frames")
	var s := _tr.state(1)
	assert_almost_eq(s.elapsed_s, 0.95, 1e-9)
	assert_almost_eq(s.remaining_s, 0.05, 1e-9)
	var ch := _run(1)
	assert_eq(ch, [{"peer": 1, "index": 1, "ended_by": Wl.ENDED_DURATION, "plan_changed": false}])
	s = _tr.state(1)
	assert_eq(s.index, 1)
	assert_eq(s.elapsed_s, 0.0)
	assert_eq(s.prev_ended_by, Wl.ENDED_DURATION)
	assert_almost_eq(s.plan_elapsed_s, 1.0, 1e-9)
	assert_eq(s.count, 3, "the cool-down is counted")
	var h := _tr.history(1)
	assert_eq(h[0]["ended_by"], Wl.ENDED_DURATION)
	assert_almost_eq(float(h[0]["end"]), 1.0, 1e-9)
	assert_almost_eq(float(h[1]["start"]), 1.0, 1e-9)


func test_state_fields() -> void:
	_tr.add_rider(
		1,
		_fin(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 10, "Ramp").with_ramp(60),
				PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30, "Free")
			]
		)
	)
	_tr.start()
	_run(100)
	var s := _tr.state(1)
	assert_eq(s.kind, Wl.WARMUP)
	assert_eq(s.mode, Wl.ERG)
	assert_eq(s.label, "Ramp")
	assert_almost_eq(s.planned_pct, 55.0, 1e-6, "halfway up the ramp")
	assert_eq(s.duration_s, 10.0)
	assert_eq(s.prev_ended_by, "")
	_run(100)
	s = _tr.state(1)
	assert_eq(s.mode, Wl.SIM)
	assert_eq(s.planned_pct, 0.0)


func test_open_ended_phase_ends_at_max_s() -> void:
	_tr.add_rider(
		1, _fin([PlanPhase.erg(Wl.WARMUP, 50, 0).with_open(1, 2), PlanPhase.erg(Wl.WORK, 60, 5)])
	)
	_tr.start()
	assert_eq(_run(39), [])
	assert_almost_eq(_tr.state(1).remaining_s, 0.05, 1e-9)
	var ch := _run(1)
	assert_eq(ch[0]["ended_by"], Wl.ENDED_MAX_S)


func test_end_phase_rules_and_timing() -> void:
	_tr.add_rider(
		1,
		_fin(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 5),
				PlanPhase.erg(Wl.WORK, 60, 0).with_open(1, 9),
				PlanPhase.erg(Wl.WORK, 60, 5)
			]
		)
	)
	assert_eq(_tr.request_end(1), Wl.REFUSE_NO_PHASE)
	assert_eq(_tr.request_end(9), Wl.REFUSE_UNKNOWN_PEER)
	_tr.start()
	assert_eq(_tr.request_end(1), Wl.REFUSE_NOT_OPEN_ENDED)
	_run(100)
	assert_eq(_tr.index_of(1), 1)
	_run(19)
	assert_eq(_tr.request_end(1), Wl.REFUSE_MIN_S, "0.95 s < min_s")
	_run(1)
	assert_eq(_tr.request_end(1), "", "exactly min_s")
	var ch := _run(1)
	assert_eq(ch[0]["ended_by"], Wl.ENDED_END_PHASE, "applied at the end of the tick")
	assert_eq(_tr.state(1).index, 2)
	assert_eq(_tr.state(1).elapsed_s, 0.0)


func test_finish_all_skips_to_the_cooldown() -> void:
	_tr.add_rider(
		1,
		_fin(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 5),
				PlanPhase.erg(Wl.WORK, 60, 5),
				PlanPhase.erg(Wl.WORK, 60, 5)
			]
		)
	)
	_tr.add_rider(2, _fin([PlanPhase.erg(Wl.WARMUP, 50, 1)]))
	_tr.start()
	_run(20)
	assert_true(_tr.is_cooldown(2))
	_tr.finish_all()
	var ch := _run(1)
	assert_eq(ch.size(), 1, "the rider already in the cool-down is not touched")
	assert_eq(ch[0]["peer"], 1)
	assert_eq(ch[0]["index"], 3)
	assert_eq(ch[0]["ended_by"], Wl.ENDED_FINISHED)
	assert_true(_tr.is_cooldown(1))
	var started := []
	for h: Dictionary in _tr.history(1):
		started.append(int(h["index"]))
	assert_eq(started, [0, 3], "unused phases never start")
	_tr.finish_all()
	assert_eq(_run(1), [], "idempotent")
	assert_true(_tr.all_in_cooldown())


func test_cooldown_completion_marks_done() -> void:
	_tr.add_rider(1, _fin([PlanPhase.erg(Wl.WARMUP, 50, 1)]))
	_tr.start()
	_run(20)
	assert_true(_tr.is_cooldown(1))
	assert_false(_tr.all_done())
	_run(3599)
	assert_false(_tr.is_done(1))
	_run(1)
	assert_true(_tr.is_done(1))
	assert_true(_tr.all_done())
	var s := _tr.state(1)
	assert_eq(s.kind, Wl.COOLDOWN)
	assert_eq(s.remaining_s, 0.0)
	assert_eq(_tr.history(1)[1]["ended_by"], Wl.ENDED_DURATION)
	assert_eq(_tr.request_end(1), Wl.REFUSE_COOLDOWN)


func test_pending_plan_swaps_at_the_next_change() -> void:
	var a := _fin([PlanPhase.erg(Wl.WARMUP, 50, 1, "A"), PlanPhase.erg(Wl.WORK, 60, 1, "B")])
	var b := _fin(
		[
			PlanPhase.erg(Wl.WARMUP, 50, 1, "A"),
			PlanPhase.erg(Wl.WORK, 55, 1, "C"),
			PlanPhase.erg(Wl.WORK, 55, 1, "D")
		]
	)
	_tr.add_rider(1, a)
	_tr.start()
	_tr.set_pending_plan(1, b)
	assert_true(_tr.has_pending_plan(1))
	var ch := _run(20)
	assert_true(bool(ch[0]["plan_changed"]))
	assert_eq(_tr.phase_of(1).label, "C")
	assert_eq(_tr.state(1).count, 4)
	assert_false(_tr.has_pending_plan(1))


func test_sim_block_and_switch_bookkeeping() -> void:
	_tr.add_rider(
		1,
		_fin(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 100),
				PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 40),
				PlanPhase.erg(Wl.WORK, 60, 60)
			]
		)
	)
	_tr.start()
	assert_eq(_tr.last_switch_tick(1), PhaseTracker.NO_SWITCH)
	assert_true(_tr.seconds_since_switch(1, 0) > 1e6)
	_run(100)
	_tr.open_block(1, _tick, PhaseTracker.ticks(10.0))
	assert_eq(_tr.last_switch_tick(1), 100, "the block's entry is a switch")
	assert_eq(_tr.effective_mode(1, _tick), Wl.SIM)
	assert_true(_tr.block_active(1, _tick))
	_run(199)
	assert_true(_tr.block_active(1, _tick))
	_run(1)
	assert_false(_tr.block_active(1, _tick))
	assert_eq(_tr.last_switch_tick(1), 300, "the exit at 10 s is a switch")
	assert_eq(_tr.effective_mode(1, _tick), Wl.ERG)
	_run(1700)
	assert_eq(_tr.index_of(1), 1)
	assert_eq(_tr.last_switch_tick(1), 2000, "ERG -> SIM phase change")
	assert_almost_eq(_tr.seconds_since_switch(1, 2100), 5.0, 1e-9)


func test_close_block_records_the_exit() -> void:
	_tr.add_rider(1, _fin([PlanPhase.erg(Wl.WARMUP, 50, 100)]))
	_tr.start()
	_run(10)
	_tr.open_block(1, _tick, 400)
	_run(100)
	_tr.close_block(1, _tick)
	assert_false(_tr.block_active(1, _tick))
	assert_eq(_tr.last_switch_tick(1), 110)


func test_phase_change_ends_a_block() -> void:
	_tr.add_rider(1, _fin([PlanPhase.erg(Wl.WARMUP, 50, 5), PlanPhase.erg(Wl.WORK, 60, 60)]))
	_tr.start()
	_tr.open_block(1, 0, 400)
	_run(100)
	assert_eq(_tr.index_of(1), 1)
	assert_false(_tr.block_active(1, _tick))
	assert_eq(_tr.effective_mode(1, _tick), Wl.ERG)
	assert_eq(_tr.last_switch_tick(1), 100)


func test_ticks_rounding() -> void:
	assert_eq(PhaseTracker.ticks(1.0), 20)
	assert_eq(PhaseTracker.ticks(0.06), 1)
	assert_eq(PhaseTracker.ticks(0.08), 2)
	assert_eq(PhaseTracker.ticks(30.0), 600)


func test_make_state_for_clients() -> void:
	var plan := _fin([PlanPhase.erg(Wl.WARMUP, 50, 10).with_ramp(60)])
	var s := PhaseTracker.make_state(plan, 0, 100, 0, "")
	assert_eq(s.index, 0)
	assert_almost_eq(s.planned_pct, 55.0, 1e-6)
	assert_eq(PhaseTracker.make_state(null, 0, 0).index, -1)
