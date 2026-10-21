extends "res://tests/governor/gov_test_base.gd"
## W4r2 (W3 NET-2): SafetyGovernor.resume_phase(index, elapsed_s[, phase_distance_m]) enters a
## phase that already runs on the host (a client that rejoins, or restarts and rejoins, mid
## phase). The phase clock starts at elapsed_s, so a ramp continues; a "course" phase follows
## its profile from the distance already ridden in it; everything 4.6 counts keeps its state
## (warm-up, the duration limits, the long-phase cap); directive channels revert to the plan as
## on any phase change. W3/W4r2 proof: a restarted client's governor went from 119.9 s to 1.9 s
## into a 300 s 50 -> 65 % ramp and its target fell from 95 W to 85 W.


func _ramp() -> PlanPhase:
	return erg(Wl.WORK, 50.0, 300.0).with_ramp(65.0)


func test_the_phase_clock_starts_at_elapsed_and_the_ramp_continues() -> void:
	var rig := make_rig({}, follower())
	rig.gov.set_plan(EffortPlan.of([_ramp(), erg(Wl.RECOVERY, 50.0, 120.0)]))
	rig.gov.resume_phase(0, 120.0)
	assert_eq(int(rig.s()["phase_index"]), 0)
	assert_almost_eq(float(rig.s()["phase_elapsed_s"]), 120.0, 1e-9)
	assert_almost_eq(float(rig.s()["planned_pct"]), 56.0, 1e-9, "50 -> 65 % over 300 s is at 56 % after 120 s")
	rig.run(30.0)
	assert_almost_eq(float(rig.s()["phase_elapsed_s"]), 150.0, 1e-6)
	assert_almost_eq(float(rig.s()["planned_pct"]), 57.5, 1e-6)
	assert_eq(rig.applied_w(), 115, "57.5 % of 200 W, not the ramp's 50 % start")
	# The same rider started instead (the W3 behaviour) would ride the ramp's start.
	var fresh := make_rig({}, follower())
	fresh.start([_ramp()])
	fresh.run(30.0)
	assert_eq(fresh.applied_w(), 103, "start_phase rides 50 -> 51.5 % over the first 30 s")


func test_zero_elapsed_is_start_phase() -> void:
	var a := make_rig({}, follower())
	var b := make_rig({}, follower())
	a.gov.set_plan(EffortPlan.of([_ramp()]))
	b.gov.set_plan(EffortPlan.of([_ramp()]))
	a.gov.start_phase(0)
	b.gov.resume_phase(0, 0.0)
	a.run(20.0)
	b.run(20.0)
	assert_eq(a.s(), b.s())


func test_bad_input_changes_nothing() -> void:
	var rig := make_rig({}, follower())
	rig.gov.resume_phase(0, 10.0)
	assert_push_error("resume_phase(0) before set_plan()")
	rig.start([_ramp(), erg(Wl.RECOVERY, 50.0, 120.0)])
	rig.run(5.0)
	var before := rig.s()
	for bad: float in [-1.0, NAN, INF]:
		rig.gov.resume_phase(1, bad)
		assert_push_error("resume_phase(1) needs a finite elapsed_s >= 0")
	rig.gov.resume_phase(2, 10.0)
	assert_push_error("resume_phase(2) outside the plan (0..1)")
	assert_eq(rig.s(), before, "phase, clock and outputs unchanged")


func test_warmup_is_the_connections_and_never_skipped() -> void:
	# A rider whose app restarted rejoins 600 s into a 1200 s phase at 100 % FTP: the skipped
	# elapsed time is no warm-up, so the 65 % warm-up cap holds for the connection's 300 s.
	var rig := make_rig({"skip_warmup": false}, follower())
	rig.gov.set_plan(EffortPlan.of([erg(Wl.WORK, 100.0, 1200.0)]))
	rig.gov.resume_phase(0, 600.0)
	assert_true(rig.s()["warmup_active"])
	rig.run(60.0)
	assert_true(rig.s()["warmup_active"])
	assert_eq(rig.applied_w(), 130, "65 % of 200 W during the warm-up")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_WARMUP)
	assert_almost_eq(float(rig.s()["phase_elapsed_s"]), 660.0, 1e-6)


func test_long_phase_cap_applies_to_a_resumed_phase() -> void:
	# A 400 s phase at 110 % is longer than 300 s, so it is capped at 105 % wherever it resumes.
	var rig := make_rig({}, follower())
	rig.gov.set_plan(EffortPlan.of([erg(Wl.WORK, 110.0, 400.0)]))
	rig.gov.resume_phase(0, 350.0)
	rig.run(20.0)
	assert_eq(rig.applied_w(), 210)
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_LONG_PHASE)


func test_duration_limits_keep_counting_across_a_resume() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 110.0, 290.0), erg(Wl.WORK, 110.0, 290.0)])
	rig.run(200.0)
	var left := float(rig.s()["s_left_105"])
	assert_lt(left, 120.0, "about 190 s above 105 % so far")
	rig.gov.resume_phase(1, 100.0)
	assert_almost_eq(float(rig.s()["s_left_105"]), left, 1e-9, "a resume is no reset")
	rig.run(150.0)
	assert_true(rig.s()["latched_105"], "the 300 s still latch, counted across the resume")
	assert_eq(rig.applied_w(), 210)
	rig.gov.resume_phase(1, 200.0)
	assert_true(rig.s()["latched_105"], "and a latch stays latched")


func test_directive_channels_revert_to_the_plan() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 60.0, 600.0).with_range(60.0, 90.0), erg(Wl.WORK, 70.0, 600.0).with_range(60.0, 90.0)])
	rig.run(60.0)
	var rec := rig.directive({"target_pct": 85.0})
	assert_false(rec["refused"])
	rig.run(10.0)
	assert_eq(rig.applied_w(), 170)
	rig.gov.resume_phase(1, 30.0)
	rig.run(5.0)
	assert_eq(rig.applied_w(), 140, "phase 1's own 70 %: the directive ended with the phase")


func test_course_phase_follows_from_the_given_distance() -> void:
	var profile := [[0.0, 0.0], [1000.0, 0.0], [1100.0, 4.0], [5000.0, 4.0]]
	var rig := make_rig({"difficulty_pct": 100.0}, follower())
	rig.gov.set_plan(EffortPlan.of([PlanPhase.sim(Wl.WORK, Wl.GRADE_COURSE, 1800.0).with_course(profile)]))
	rig.gov.set_course_distance(20.0)
	rig.gov.resume_phase(0, 300.0, 1050.0)
	rig.run(1.0)
	assert_almost_eq(rig.gov.phase_distance_m(), 1050.0, 1e-6)
	assert_almost_eq(float(rig.s()["course_grade_pct"]), 2.0, 1e-9, "halfway to the 4 % point")
	rig.gov.set_course_distance(70.0)
	rig.run(1.0)
	assert_almost_eq(rig.gov.phase_distance_m(), 1100.0, 1e-6, "and on from there")
	assert_almost_eq(float(rig.s()["course_grade_pct"]), 4.0, 1e-9)


func test_course_phase_follows_from_the_governors_own_record() -> void:
	# The same governor across a socket rejoin: the host's course phase began 40 s ago while the
	# client still rode phase 0, 10 m per second; resume_phase finds the 400 m in its record.
	var profile := [[0.0, 0.0], [300.0, 0.0], [500.0, 6.0], [5000.0, 6.0]]
	var rig := make_rig({"difficulty_pct": 100.0}, follower())
	rig.start([erg(Wl.WORK, 60.0, 600.0), PlanPhase.sim(Wl.WORK, Wl.GRADE_COURSE, 1800.0).with_course(profile)])
	var d := 0.0
	for i in roundi(100.0 / DT):
		d += 10.0 * DT
		rig.gov.set_course_distance(d)
		rig.step()
	assert_almost_eq(rig.gov.distance_ridden_since(rig.gov.game_time_s() - 40.0), 400.0, 10.0 * DT + 1e-3)
	rig.gov.resume_phase(1, 40.0)
	assert_almost_eq(rig.gov.phase_distance_m(), 400.0, 10.0 * DT + 1e-3)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["course_grade_pct"]), 3.0, 0.2, "400 m into the course: halfway up to 6 %")


func test_distance_record_reaches_back_only_as_far_as_this_governor() -> void:
	var rig := make_rig({}, follower())
	assert_eq(rig.gov.distance_ridden_since(0.0), -1.0, "no distance yet")
	rig.start([erg(Wl.WORK, 60.0, 600.0)])
	for i in roundi(10.0 / DT):
		rig.gov.set_course_distance(5.0 * float(i) * DT)
		rig.step()
	assert_eq(rig.gov.distance_ridden_since(-120.0), -1.0, "a new governor knows nothing from before it")
	assert_almost_eq(rig.gov.distance_ridden_since(0.0), 50.0 - 5.0 * DT, 1e-3)
	assert_almost_eq(rig.gov.distance_ridden_since(rig.gov.game_time_s()), 0.0, 1e-3, "now: nothing ridden since")
	assert_almost_eq(rig.gov.distance_ridden_since(9.5), 2.3, 0.15, "between the last entry and now (47.5 m at 9.5 s)")
	# Without a figure a new governor's course starts at 0 (LocalRider estimates one first).
	var fresh := make_rig({}, follower())
	fresh.gov.set_plan(EffortPlan.of([PlanPhase.sim(Wl.WORK, Wl.GRADE_COURSE, 600.0).with_course([[0.0, 1.0], [100.0, 1.0]])]))
	fresh.gov.resume_phase(0, 120.0)
	assert_eq(fresh.gov.phase_distance_m(), 0.0)


func test_start_phase_and_clear_plan_drop_the_offset() -> void:
	var rig := make_rig({}, follower())
	rig.gov.set_plan(EffortPlan.of([PlanPhase.sim(Wl.WORK, Wl.GRADE_COURSE, 600.0).with_course([[0.0, 1.0], [100.0, 1.0]])]))
	rig.gov.resume_phase(0, 120.0, 800.0)
	assert_almost_eq(rig.gov.phase_distance_m(), 800.0, 1e-9)
	rig.gov.start_phase(0)
	assert_eq(rig.gov.phase_distance_m(), 0.0)
	rig.gov.resume_phase(0, 120.0, 800.0)
	rig.gov.clear_plan()
	assert_eq(rig.gov.phase_distance_m(), 0.0)
