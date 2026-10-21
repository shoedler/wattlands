extends "res://tests/governor/gov_test_base.gd"
## W4: what a rider carries from one session to the next on the same trainer connection, with
## a real LocalRider and SafetyGovernor (LocalRider.setup() builds a new governor per session
## and for the menu reset; SafetyGovernor.adopt_connection hands over the connection state).
##   - SAF-2 (BRIEF 4.6.1): a latched duration limit "stays there until the applied target has
##     been <= 90% FTP for 120 consecutive seconds of ERG"; ending a session is no release.
##   - SAF-6 (BRIEF 4.5): the menus' SIM flat into a session's first ERG phase is a switch, so a
##     directive SIM block needs 30 s after it.
## Adapted from the W3 proofs in build/w3/safety/test_w3_safety_governor.gd.


func _profile(ftp: float = 200.0) -> RiderProfile:
	var p := RiderProfile.new()
	p.ftp_w = ftp
	p.cp_w = ftp
	p.ftp_verified = true
	p.skip_warmup = true
	return p


func _setup(r: LocalRider, dev: TrainerDevice) -> void:
	var p := _profile()
	r.setup(1, p, p.to_slot(1, Wl.FAIR_FTP), dev, {"multiplayer": false, "skip_warmup": true})


func _rider_on(dev: TrainerDevice) -> LocalRider:
	var r := LocalRider.new()
	add_child_autofree(r)
	_setup(r, dev)
	return r


func _tick(r: LocalRider, seconds: float) -> void:
	for i in roundi(seconds / DT):
		r.tick(DT)


func test_duration_latch_survives_local_rider_setup_on_the_same_trainer() -> void:
	var dev: ScriptedDevice = follower()
	autofree(dev)
	var r := _rider_on(dev)
	r.set_plan(plan_with_cooldown([erg(Wl.WORK, 125.0, 60.0)]))
	r.start_phase(0)
	_tick(r, 70.0)
	var before := r.governor.status()
	assert_true(bool(before["latched_120"]), "precondition: the 120%% limit latched (s_left_120 %s)" % str(before["s_left_120"]))
	# End ride: the next session (or the menu reset) on the same trainer.
	_setup(r, dev)
	var after := r.governor.status()
	assert_true(bool(after["latched_120"]), "the 120% latch survives a new governor on the same trainer")
	assert_almost_eq(float(after["s_left_120"]), 0.0, 1e-9)
	# A plan the PlanValidator accepts: 300 s of SIM warm-up, then 60 s at 125%.
	var plan2 := EffortPlan.of([sim(Wl.GRADE_FLAT, 300.0, Wl.WARMUP), erg(Wl.WORK, 125.0, 60.0)])
	var res := PlanValidator.validate(plan2)
	assert_true(bool(res["ok"]), "precondition: the second plan validates: %s" % str(res["errors"]))
	r.set_plan(PlanValidator.finalize(plan2))
	r.start_phase(0)
	_tick(r, 300.0)
	r.start_phase(1)
	_tick(r, 30.0)
	var w := int(r.governor.status()["applied_target_w"])
	assert_eq(w, 240, "no ERG reset run happened, so the 120%% cap (240 W) holds; applied %d W" % w)


## Control: the same sequence on one governor (no setup) keeps the latch.
func test_control_same_governor_keeps_the_latch() -> void:
	var dev: ScriptedDevice = follower()
	autofree(dev)
	var r := _rider_on(dev)
	r.set_plan(plan_with_cooldown([erg(Wl.WORK, 125.0, 60.0)]))
	r.start_phase(0)
	_tick(r, 70.0)
	var plan2 := EffortPlan.of([sim(Wl.GRADE_FLAT, 300.0, Wl.WARMUP), erg(Wl.WORK, 125.0, 60.0)])
	r.set_plan(PlanValidator.finalize(plan2))
	r.start_phase(0)
	_tick(r, 300.0)
	r.start_phase(1)
	_tick(r, 30.0)
	assert_eq(int(r.governor.status()["applied_target_w"]), 240, "one governor keeps the 120% cap")


## The reset still works across the hand-over: 120 s of ERG at <= 90% FTP releases the latch.
func test_the_reset_run_releases_the_latch_in_the_next_session() -> void:
	var dev: ScriptedDevice = follower()
	autofree(dev)
	var r := _rider_on(dev)
	r.set_plan(plan_with_cooldown([erg(Wl.WORK, 125.0, 60.0)]))
	r.start_phase(0)
	_tick(r, 70.0)
	_setup(r, dev)
	r.set_plan(PlanValidator.finalize(EffortPlan.of([erg(Wl.WARMUP, 60.0, 300.0), erg(Wl.WORK, 125.0, 60.0)])))
	r.start_phase(0)
	_tick(r, 125.0)
	assert_false(bool(r.governor.status()["latched_120"]), "released by 120 s of ERG at 60%")
	r.start_phase(1)
	_tick(r, 10.0)
	assert_eq(int(r.governor.status()["applied_target_w"]), 250, "125% again")


## SAF-6, the W3 repro (test_a_sim_block_right_after_the_menu_to_erg_switch_is_refused) with a
## LocalRider: the menus leave the trainer at SIM flat, the session's first phase is ERG, and a
## directive SIM block 1 s later is refused for the 30 s spacing (was: SIM -> ERG -> SIM in 1 s).
func test_a_sim_block_right_after_the_menu_to_erg_switch_is_refused() -> void:
	var dev: ScriptedDevice = follower()
	autofree(dev)
	var r := _rider_on(dev)
	_tick(r, 5.0)
	assert_eq(dev.mode, Wl.SIM, "precondition: the menus left the trainer at SIM flat")
	_setup(r, dev)
	r.set_plan(plan_with_cooldown([erg(Wl.WARMUP, 50.0, 300.0)]))
	r.start_phase(0)
	_tick(r, 1.0)
	assert_eq(dev.mode, Wl.ERG, "precondition: the session switched the trainer to ERG")
	var d := EffortDirective.from_dict({"mode": Wl.SIM, "duration_s": 15.0})
	var rec := r.apply_directive(d)
	assert_true(bool(rec["refused"]), "a SIM block 1 s after the SIM -> ERG switch is refused; got %s" % str(rec))
	assert_eq(str(rec["reason"]), Wl.REFUSE_SWITCH_SPACING)
	assert_push_warning("switch_spacing")
	_tick(r, 2.0)
	var ops: Array = []
	for w: Dictionary in dev.writes:
		ops.append(str(w["op"]))
	assert_eq(ops.back(), "erg", "the trainer stays in ERG: %s" % str(ops))
	_tick(r, 27.0)
	assert_false(bool(r.apply_directive(d)["refused"]), "30 s after the switch the block is accepted")


func after_each() -> void:
	# Let the governors LocalRider.setup() replaced (queue_free) go before GUT counts orphans.
	await wait_process_frames(1)
