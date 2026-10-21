extends GutTest
## W4r2 (W3 NET-2): LocalRider.resume_phase(index, elapsed_s), which GameHost calls when a
## client rejoins a running phase (a socket rejoin after the phase changed, or a client whose
## app restarted and has a new rider). It forwards to SafetyGovernor.resume_phase, follows the
## MockTrainer's phase, laps only on a real phase change, clears the bands in the cool-down and
## estimates the distance a new rider can't know for a "course" phase.

const Fakes := preload("res://tests/core/helpers/fakes.gd")
const DT := Wl.SIM_DT

var _bus: WlEventBus = null


func before_each() -> void:
	_bus = WlEventBus.new()
	autofree(_bus)


func after_each() -> void:
	await wait_process_frames(1)


func _profile(ftp: float = 200.0) -> RiderProfile:
	var p := RiderProfile.new()
	p.ftp_w = ftp
	p.cp_w = ftp
	p.ftp_verified = true
	p.skip_warmup = true
	p.difficulty_pct = 100.0
	p.grade_min_pct = -10.0
	p.grade_max_pct = 16.0
	p.created = true
	return p


func _rider(device: TrainerDevice, opts: Dictionary = {}) -> LocalRider:
	var r := LocalRider.new()
	add_child_autofree(r)
	var o := {"bus": _bus, "skip_warmup": true}
	o.merge(opts, true)
	r.setup(2, _profile(), null, device, o)
	return r


func _mock() -> Fakes.RecordingMock:
	var m := Fakes.RecordingMock.new()
	autofree(m)
	return m


func _run(r: LocalRider, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		r.tick(DT)


## A 300 s ERG ramp 50 -> 65 % (lap), a lap work phase, a course phase and the cool-down.
func _plan() -> EffortPlan:
	var plan := (
		EffortPlan
		. of(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 300, "Warm-up").with_ramp(65).with_lap(),
				PlanPhase.erg(Wl.WORK, 80, 120, "Wave 1").with_lap(),
				(
					PlanPhase
					. sim(Wl.WORK, Wl.GRADE_COURSE, 1800, "Road")
					. with_course([[0.0, 0.0], [100000.0, 0.0]])
					. with_lap()
				),
			]
		)
	)
	plan.add(PlanPhase.erg(Wl.COOLDOWN, 50, 180, ""))
	plan.cooldown_appended = true
	return plan


func test_a_new_rider_resumes_the_ramp_without_a_lap() -> void:
	var m := _mock()
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(m, {"recorder": rec})
	r.set_plan(_plan())
	r.resume_phase(0, 120.0)
	assert_almost_eq(float(r.governor.status()["phase_elapsed_s"]), 120.0, 1e-9)
	assert_almost_eq(float(r.governor.status()["planned_pct"]), 56.0, 1e-9)
	assert_eq(r.telemetry().phase_index, 0)
	assert_eq(m.phases.back(), 0, "the MockTrainer follows the phase")
	assert_eq(rec.laps, [], "a restarted client's new FIT starts here: no extra lap")
	_run(r, 20.0)
	assert_almost_eq(float(r.governor.status()["phase_elapsed_s"]), 140.0, 1e-6)
	assert_eq(
		int(r.governor.status()["governed_target_w"]), 114, "57 % of 200 W, not the ramp's start"
	)


func test_the_same_phase_again_writes_no_lap_and_a_real_change_does() -> void:
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(_mock(), {"recorder": rec})
	r.set_plan(_plan())
	r.start_phase(0)
	_run(r, 2.0)
	assert_eq(rec.laps, [["Warm-up", 0.0]])
	r.resume_phase(0, 30.0)
	assert_eq(rec.laps.size(), 1, "re-entering the phase the rider rides is no lap")
	_run(r, 1.0)
	r.resume_phase(1, 15.0)
	assert_eq(rec.laps.size(), 2, "the phase changed while the socket was down: its lap")
	assert_eq(rec.laps[1], ["Wave 1", 3.0])
	r.resume_phase(3, 20.0)
	assert_eq(rec.laps[2], ["Cool-down", 3.0], "the cool-down is always a lap")


func test_cooldown_clears_the_bands() -> void:
	var r := _rider(_mock())
	r.set_plan(_plan())
	r.start_phase(1)
	r.set_cadence_band(70.0, 90.0)
	r.set_power_band(100.0, 200.0)
	r.resume_phase(3, 40.0)
	assert_eq(r.cadence_band(), Vector2.ZERO)
	assert_eq(r.power_band(), Vector2.ZERO)


func test_zero_elapsed_is_start_phase_and_bad_input_is_refused() -> void:
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(_mock(), {"recorder": rec})
	r.set_plan(_plan())
	r.resume_phase(0, 0.0)
	assert_eq(rec.laps, [["Warm-up", 0.0]], "elapsed 0 is start_phase: the phase's lap")
	assert_eq(float(r.governor.status()["phase_elapsed_s"]), 0.0)
	for bad: float in [-2.0, NAN, INF]:
		r.resume_phase(1, bad)
		assert_push_error("resume_phase(1) needs a finite elapsed_s >= 0")
	assert_eq(r.telemetry().phase_index, 0, "nothing changed")


## A rider without a governor has nothing to resume: it enters the phase as start_phase() does,
## through the (overridable) start_phase, so a test double that records start_phase sees it.
func test_without_a_governor_it_is_start_phase() -> void:
	var r := StartLog.new()
	add_child_autofree(r)
	r.resume_phase(2, 45.0)
	assert_eq(r.started, [2])
	assert_eq(r.telemetry().phase_index, 2)


class StartLog:
	extends LocalRider
	var started: Array[int] = []

	func start_phase(index: int) -> void:
		started.append(index)
		super.start_phase(index)


func test_forwards_to_the_governor() -> void:
	var r := _rider(_mock(), {"governor": Fakes.FakeGovernor.new()})
	r.set_plan(_plan())
	r.resume_phase(1, 30.0)
	var g := r.governor as Fakes.FakeGovernor
	assert_eq(
		g.called("resume_phase"),
		[["resume_phase", 1, 30.0, -1.0]],
		"an ERG phase needs no distance"
	)
	assert_eq(g.called("start_phase"), [])


func test_a_new_riders_course_phase_continues_from_an_estimate() -> void:
	var r := _rider(_mock())
	r.set_plan(_plan())
	_run(r, 1.0)
	r.resume_phase(2, 600.0)
	# Flat course: the speed model at 75 % FTP as P_eff (FAIR_FTP: 0.75 x 250 W) holds its steady
	# speed, so 600 s cover 600 x that speed.
	var v := SpeedModel.steady_state_speed(
		187.5, 0.0, r.slot.rider_mass_kg + SpeedModel.DEFAULT_MASS_OFFSET_KG
	)
	var est := r.estimate_course_distance(r.plan().phase(2), 600.0)
	assert_almost_eq(est, 600.0 * v, 600.0 * v * 0.01)
	assert_almost_eq(
		r.governor.phase_distance_m(), est, 1.0, "the governor follows the course from there"
	)
	assert_gt(est, 3000.0, "minutes of riding, not the course start")


func test_the_estimate_follows_the_course_grades() -> void:
	var r := _rider(_mock())
	var flat := PlanPhase.sim(Wl.WORK, Wl.GRADE_COURSE, 1800).with_course(
		[[0.0, 0.0], [50000.0, 0.0]]
	)
	var hill := PlanPhase.sim(Wl.WORK, Wl.GRADE_COURSE, 1800).with_course(
		[[0.0, 6.0], [50000.0, 6.0]]
	)
	var d_flat := r.estimate_course_distance(flat, 900.0)
	var d_hill := r.estimate_course_distance(hill, 900.0)
	assert_lt(d_hill, d_flat * 0.7, "a 6 % climb is slower")
	assert_eq(
		r.estimate_course_distance(PlanPhase.sim(Wl.WORK, Wl.GRADE_FLAT, 60), 60.0),
		0.0,
		"no course, no distance"
	)
	var t0 := Time.get_ticks_msec()
	r.estimate_course_distance(
		PlanPhase.sim(Wl.WORK, Wl.GRADE_COURSE, 21600).with_course(_long_course()), 21600.0
	)
	assert_lt(Time.get_ticks_msec() - t0, 5000, "six hours of a 200-point course estimate quickly")


func test_the_same_rider_uses_its_own_distance() -> void:
	# A socket rejoin (same rider and governor): the governor's own distance record decides.
	var r := _rider(_mock())
	r.set_plan(_plan())
	r.start_phase(1)
	_run(r, 60.0)
	var own := r.governor.distance_ridden_since(r.governor.game_time_s() - 30.0)
	assert_gt(own, 0.0, "the rider moved")
	r.resume_phase(2, 30.0)
	assert_almost_eq(r.governor.phase_distance_m(), own, 0.5)


func _long_course() -> Array:
	var out: Array = []
	for i in 200:
		out.append([float(i) * 1000.0, float(i % 7) - 2.0])
	return out
