extends GutTest
## W2 integration of one rider's whole trainer stack (BRIEF 4.1, 4.5, 4.6, 7.4), with no test
## doubles: LocalRider + SafetyGovernor (and its TrainerController) + MockTrainer profiles
## (erg, zero, band, cadence_drop, surge) + GestureRecognizer + CadenceEstimator +
## RideRecorder, ridden for several simulated minutes in fixed 0.05 s platform steps.
## A small phase driver stands in for the GameHost: it starts each plan phase when the last
## one's duration has passed and pauses the game when the rider asks (SOLO coasting).
## End to end it asserts the BRIEF 7.4 governor timings: a 0 W rider's applied target reaches
## the coasting floor no later than 3 s (+1 tick) after the first sample that meets
## not_pedaling, and pause (solo) or AFK (multiplayer) no later than 10 s (+1 tick) after it;
## rescue triggers on a cadence collapse while the applied target is >= 60% FTP and never
## below; the warm-up caps hold; a paused SceneTree doesn't stop trainer samples. It also
## rides the reconnect resync, the ERG surge gesture and a recorded ride (1 Hz records and a
## FIT file in build/core_stack_test/ for tools/fit_check).

const DT := Wl.SIM_DT
const FTP := 200.0
const EPS := 1e-6
## A fixed UTC start (2026-10-21 07:00:00 UTC) so the FIT file name is stable.
const UTC_START := 1792566000
const FIT_DIR := "res://build/core_stack_test"
const Fakes := preload("res://tests/core/helpers/fakes.gd")


## Stands in for the GameHost on one rider: plan phases by duration, the game paused on
## the rider's pause request, and a per-tick trace.
class Driver:
	extends RefCounted

	var rider: LocalRider = null
	var mock: MockTrainer = null
	var plan: EffortPlan = null
	var phase_index: int = -1
	var phase_elapsed: float = 0.0
	var phase_start_t: Array[float] = []
	var game_paused: bool = false
	var finished: bool = false
	## One entry per tick: {t, phase, mode, w, grade, warmup, rescue, coasting, afk, paused,
	## clamped_by, power, cadence}.
	var trace: Array[Dictionary] = []
	## Every trainer sample as the stack saw it: {t, phase, power_w, cadence_rpm}.
	var samples: Array[Dictionary] = []
	var pause_requests: Array[Dictionary] = []
	var afk_events: Array[Dictionary] = []
	var rescue_events: Array[Dictionary] = []
	var gestures: Array[Dictionary] = []
	## Called with (driver) after every tick, for per-test inputs (course grades, directives).
	var each_tick: Callable = Callable()

	func _init(p_rider: LocalRider, p_mock: MockTrainer, p_plan: EffortPlan) -> void:
		rider = p_rider
		mock = p_mock
		plan = p_plan
		rider.pause_requested.connect(_on_pause_requested)
		rider.afk_changed.connect(func(on: bool) -> void: afk_events.append({"t": rider.platform_time(), "on": on}))
		rider.rescue_changed.connect(func(on: bool) -> void: rescue_events.append({"t": rider.platform_time(), "on": on, "phase": phase_index}))
		mock.sample_received.connect(_on_sample)
		rider.set_plan(plan)
		_enter(0)

	func t() -> float:
		return rider.platform_time()

	func step() -> void:
		rider.tick(DT)
		var now := rider.platform_time()
		for g in rider.take_gestures():
			gestures.append({"t": now, "name": g})
		var tel := rider.telemetry()
		var st := rider.governor.status()
		trace.append({
			"t": now, "phase": phase_index, "mode": tel.mode, "w": tel.applied_target_w,
			"grade": tel.applied_grade_pct, "warmup": bool(st.get("warmup_active", false)),
			"rescue": tel.rescue, "coasting": tel.coasting, "afk": tel.afk, "paused": tel.paused,
			"clamped_by": tel.clamped_by.duplicate(), "power": tel.power_w, "cadence": tel.cadence_rpm,
		})
		if each_tick.is_valid():
			each_tick.call(self)
		if game_paused or finished:
			return
		phase_elapsed += DT
		var ph := plan.phase(phase_index)
		if phase_elapsed >= ph.duration_s - EPS:
			if phase_index + 1 < plan.size():
				_enter(phase_index + 1)
			else:
				finished = true

	func run(seconds: float) -> void:
		for i in roundi(seconds / DT):
			step()

	func run_to_end(max_s: float = 7200.0) -> void:
		var n := 0
		while not finished and n * DT < max_s:
			step()
			n += 1

	## Trace entries with from_t <= t < to_t.
	func window(from_t: float, to_t: float) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for e in trace:
			var et: float = e["t"]
			if et >= from_t - EPS and et < to_t - EPS:
				out.append(e)
		return out

	## The time of the first sample at or after `from_t` for which pred(sample) holds, or -1.
	func first_sample_t(from_t: float, pred: Callable) -> float:
		for s in samples:
			if float(s["t"]) >= from_t - EPS and pred.call(s):
				return float(s["t"])
		return -1.0

	func _enter(index: int) -> void:
		phase_index = index
		phase_elapsed = 0.0
		phase_start_t.append(rider.platform_time())
		rider.start_phase(index)

	func _on_pause_requested(reason: String) -> void:
		pause_requests.append({"t": rider.platform_time(), "reason": reason})
		if not rider.is_multiplayer and not game_paused:
			game_paused = true
			rider.set_game_paused(true)

	func _on_sample(s: TrainerSample) -> void:
		samples.append({
			"t": rider.platform_time(), "phase": phase_index, "power_w": s.power_w,
			"cadence_rpm": s.cadence_rpm if s.has_cadence() else -1.0,
		})


var _bus: WlEventBus = null
var _dirs: Array[String] = []


func before_each() -> void:
	_bus = WlEventBus.new()
	autofree(_bus)


func after_each() -> void:
	get_tree().paused = false
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	for d in _dirs:
		_remove_tree(d)
	_dirs.clear()
	await wait_process_frames(1)


func _profile(skip_warmup: bool = false, difficulty: float = 50.0) -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = "Stack"
	p.ftp_w = FTP
	p.cp_w = FTP
	p.ftp_verified = true
	p.skip_warmup = skip_warmup
	p.difficulty_pct = difficulty
	p.created = true
	return p


## A rider set up around a MockTrainer built from `spec`, with every real component.
func _driver(spec: String, plan: EffortPlan, opts: Dictionary = {}, profile: RiderProfile = null) -> Driver:
	var mock := MockTrainer.from_spec(spec, FTP, {"seed": int(opts.get("seed", 7))})
	assert_eq(mock.spec, spec, "the profile parses")
	autofree(mock)
	var r := LocalRider.new()
	add_child_autofree(r)
	var o := {"bus": _bus, "multiplayer": false, "utc_start_unix": UTC_START, "game_id": "core_stack",
		"content_id": "integration"}
	o.merge(opts, true)
	o.erase("seed")
	r.setup(1, profile if profile != null else _profile(), null, mock, o)
	return Driver.new(r, mock, plan)


func _finalized(phases: Array) -> EffortPlan:
	var plan := PlanValidator.finalize(EffortPlan.of(phases))
	assert_not_null(plan, "the plan passes the PlanValidator")
	return plan


## Warm-up ramp 50 -> 65% for 300 s, then `work` % for work_s, then the cool-down.
func _easy_plan(work: float = 60.0, work_s: float = 300.0) -> EffortPlan:
	return _finalized([
		PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up").with_ramp(65.0),
		PlanPhase.erg(Wl.WORK, work, work_s, "Work").with_lap(),
	])


static func _np(s: Dictionary) -> bool:
	return GestureRecognizer.is_not_pedaling(float(s["power_w"]), float(s["cadence_rpm"]))


# --- coasting (4.6.4, 7.4) ------------------------------------------------------------------


func test_zero_rider_reaches_the_floor_within_3_s_and_pauses_within_10_s_solo() -> void:
	var d := _driver("zero", _easy_plan())
	d.run(30.0)
	var floor_w := GovernorClamps.floor_w(FTP)
	var np_t := d.first_sample_t(0.0, _np)
	assert_between(np_t, 0.85, 1.2, "the first sample (0 W, 0 rpm) arrives after about 1 s")
	var before := d.window(np_t, np_t + 3.0 - DT)
	var above := before.filter(func(e: Dictionary) -> bool: return int(e["w"]) > floor_w)
	assert_gt(above.size(), 0, "the warm-up target (50% = 100 W) was applied before the coasting rule")
	var at_floor := d.window(np_t, 1e9).filter(func(e: Dictionary) -> bool:
		return e["mode"] == Wl.ERG and int(e["w"]) == floor_w and bool(e["coasting"]))
	assert_gt(at_floor.size(), 0)
	if at_floor.size() > 0:
		assert_lte(float(at_floor[0]["t"]), np_t + 3.0 + DT + EPS,
			"the coasting floor no later than 3 s (+1 tick) after the first not_pedaling sample")
	for e in d.window(np_t + 3.0 + DT, 1e9):
		assert_eq(int(e["w"]), floor_w, "the floor holds at t=%.2f" % float(e["t"]))
		if int(e["w"]) != floor_w:
			break
	var coasting := d.pause_requests.filter(func(p: Dictionary) -> bool: return p["reason"] == "coasting")
	assert_eq(coasting.size(), 1, "one pause request from the governor")
	if coasting.size() == 1:
		assert_between(float(coasting[0]["t"]), np_t + 10.0 - EPS, np_t + 10.0 + DT + EPS,
			"paused (solo) no later than 10 s (+1 tick) after that sample")
	assert_true(d.rider.telemetry().paused)
	assert_true(d.rider.telemetry().coasting)
	assert_eq(d.afk_events.size(), 0, "never AFK in SOLO")
	assert_true(d.game_paused)


func test_rider_who_stops_mid_ride_goes_afk_in_multiplayer_and_comes_back() -> void:
	var d := _driver("erg+cadence_drop:rpm=0,at_s=400,for_s=40", _easy_plan(60.0, 300.0), {"multiplayer": true})
	d.run(600.0)
	var floor_w := GovernorClamps.floor_w(FTP)
	var np_t := d.first_sample_t(1.0, _np)
	assert_between(np_t, 399.9, 401.2, "the rider stops at 400 s")
	var held := d.window(np_t - 5.0, np_t)
	assert_true(held.all(func(e: Dictionary) -> bool: return int(e["w"]) == 120), "riding 60% (120 W) before the stop")
	var at_floor := d.window(np_t, np_t + 30.0).filter(func(e: Dictionary) -> bool: return int(e["w"]) == floor_w)
	assert_gt(at_floor.size(), 0)
	if at_floor.size() > 0:
		assert_lte(float(at_floor[0]["t"]), np_t + 3.0 + DT + EPS, "floor within 3 s (+1 tick)")
	var on := d.afk_events.filter(func(a: Dictionary) -> bool: return a["on"])
	assert_eq(on.size(), 1)
	if on.size() == 1:
		assert_between(float(on[0]["t"]), np_t + 10.0 - EPS, np_t + 10.0 + DT + EPS,
			"AFK (multiplayer) no later than 10 s (+1 tick)")
	assert_eq(d.pause_requests.size(), 0, "multiplayer never pauses (no coasting pause, no stop_5s)")
	var off := d.afk_events.filter(func(a: Dictionary) -> bool: return not a["on"])
	assert_eq(off.size(), 1, "pedaling again clears AFK")
	if off.size() == 1:
		assert_between(float(off[0]["t"]), 440.0, 442.5)
	var end := d.window(595.0, 600.0)
	assert_true(end.all(func(e: Dictionary) -> bool: return int(e["w"]) == 120 and not bool(e["rescue"])),
		"back on the plan target after the rescue hold and its ramp")


# --- rescue (4.6.3, 7.4) --------------------------------------------------------------------


func test_rescue_on_cadence_collapse_at_or_above_60_pct_and_never_below() -> void:
	var drops := PackedStringArray()
	# [phase, after_s]: 53% (warm-up ramp, unarmed), 62.5% (ramp past 60%), 55% RECOVERY,
	# 80% WORK, exactly 60% WORK, 50% COOLDOWN.
	var windows := [[0, 60.0], [0, 250.0], [1, 30.0], [2, 30.0], [3, 30.0], [4, 30.0]]
	for w: Array in windows:
		drops.append("cadence_drop:rpm=30,at_phase=%d,after_s=%d,for_s=20" % [int(w[0]), int(w[1])])
	var spec := "erg+" + "+".join(drops)
	var plan := _finalized([
		PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up").with_ramp(65.0),
		PlanPhase.erg(Wl.RECOVERY, 55.0, 120.0, "Easy"),
		PlanPhase.erg(Wl.WORK, 80.0, 120.0, "Hard"),
		PlanPhase.erg(Wl.WORK, 60.0, 120.0, "Tempo"),
	])
	var d := _driver(spec, plan)
	d.run_to_end()
	assert_true(d.finished)
	assert_eq(d.phase_start_t.size(), 5)
	var expect_rescue := [false, true, false, true, true, false]
	var rescues := d.rescue_events.filter(func(e: Dictionary) -> bool: return e["on"])
	assert_eq(rescues.size(), 3, "rescued exactly in the three armed windows: %s" % str(rescues))
	for i in windows.size():
		var w: Array = windows[i]
		var start: float = d.phase_start_t[int(w[0])] + float(w[1])
		var low_t := d.first_sample_t(start, func(s: Dictionary) -> bool: return float(s["cadence_rpm"]) < 45.0)
		assert_between(low_t, start, start + 2.5, "window %d: the cadence collapses" % i)
		var hits := rescues.filter(func(e: Dictionary) -> bool:
			return float(e["t"]) >= start - EPS and float(e["t"]) <= start + 25.0)
		var target_w := 0
		for e in d.window(low_t - 0.5, low_t):
			target_w = int(e["w"])
		if expect_rescue[i]:
			assert_gte(target_w, int(floor(0.6 * FTP)), "window %d: armed (applied %d W >= 60%% FTP)" % [i, target_w])
			assert_eq(hits.size(), 1, "window %d: rescue" % i)
			if hits.size() == 1:
				assert_between(float(hits[0]["t"]), low_t + 3.0 - EPS, low_t + 3.0 + DT + EPS,
					"window %d: cadence < 45 rpm for 3 s" % i)
				var hold := d.window(float(hits[0]["t"]), float(hits[0]["t"]) + 2.0)
				assert_true(hold.all(func(e: Dictionary) -> bool: return int(e["w"]) == 100 and bool(e["rescue"])),
					"window %d: 50%% FTP (100 W) during the hold" % i)
		else:
			assert_lt(target_w, int(floor(0.6 * FTP)), "window %d: below 60%% (applied %d W)" % [i, target_w])
			assert_eq(hits.size(), 0, "window %d: never a rescue below 60%% FTP" % i)
	var cooldown := d.window(d.phase_start_t[4], 1e9)
	assert_false(cooldown.any(func(e: Dictionary) -> bool: return bool(e["rescue"])), "no rescue in the cool-down")


# --- warm-up (4.6.8, 7.4) -------------------------------------------------------------------


func test_warmup_caps_hold_for_erg_sim_gears_and_haptics() -> void:
	# A plan the PlanValidator would refuse (80% inside the first 300 s): the governor alone
	# holds the warm-up limits.
	var plan := EffortPlan.of([
		PlanPhase.erg(Wl.WORK, 80.0, 120.0, "Too hard"),
		PlanPhase.sim(Wl.WORK, Wl.GRADE_GAME, 60.0, "Climb"),
		PlanPhase.erg(Wl.WORK, 80.0, 120.0, "Too hard again"),
		PlanPhase.sim(Wl.WORK, Wl.GRADE_GAME, 60.0, "Climb after warm-up"),
		PlanPhase.erg(Wl.WORK, 80.0, 120.0, "Hard"),
	])
	plan.add(PlanValidator.cooldown_phase())
	plan.cooldown_appended = true
	var d := _driver("erg", plan, {}, _profile(false, 100.0))
	var haptics: Array[Dictionary] = []
	d.each_tick = func(dr: Driver) -> void:
		var ph := dr.plan.phase(dr.phase_index)
		if ph.mode == Wl.SIM:
			dr.rider.apply_course_grade(8.0)
			if dr.phase_elapsed > 10.0 - EPS and dr.phase_elapsed < 10.0 + DT - EPS:
				for i in 6:
					dr.rider.shift(1)
				haptics.append(dr.rider.apply_directive(EffortDirective.from_dict(
					{"mode": "SIM", "haptic": 2.0, "duration_s": 2.0, "reason": "hit"})))
	d.run_to_end()
	var cap := int(floor(0.65 * FTP))
	var in_warmup := d.trace.filter(func(e: Dictionary) -> bool: return e["warmup"])
	assert_gt(in_warmup.size(), int(290.0 / DT))
	for e in in_warmup:
		if e["mode"] == Wl.ERG and int(e["w"]) > cap:
			fail_test("ERG %d W > 65%% FTP in warm-up at t=%.2f" % [int(e["w"]), float(e["t"])])
			break
		if e["mode"] == Wl.SIM and (float(e["grade"]) < -2.0 - EPS or float(e["grade"]) > 3.0 + EPS):
			fail_test("SIM grade %.2f%% outside -2..+3 in warm-up at t=%.2f" % [float(e["grade"]), float(e["t"])])
			break
	var capped := in_warmup.filter(func(e: Dictionary) -> bool:
		return e["mode"] == Wl.ERG and int(e["w"]) == cap and (e["clamped_by"] as Array).has(Wl.CLAMP_WARMUP))
	assert_gt(capped.size(), 0, "80% was capped at 65% (130 W)")
	var steep := in_warmup.filter(func(e: Dictionary) -> bool: return e["mode"] == Wl.SIM and absf(float(e["grade"]) - 3.0) < EPS)
	assert_gt(steep.size(), 0, "8% (plus 6 gears) was held at +3%")
	var ended := d.trace.filter(func(e: Dictionary) -> bool: return not e["warmup"])
	assert_gt(ended.size(), 0)
	if ended.size() > 0:
		assert_between(float(ended[0]["t"]), 300.0, 302.5, "5 minutes from the first pedal stroke (~1 s)")
	assert_eq(haptics.size(), 2)
	if haptics.size() == 2:
		assert_true(bool(haptics[0]["refused"]))
		assert_eq(haptics[0]["reason"], Wl.REFUSE_HAPTIC_WARMUP, "no haptics in warm-up")
		assert_false(bool(haptics[1]["refused"]), "after warm-up the haptic applies: %s" % str(haptics[1]))
	var climb := d.window(d.phase_start_t[3], d.phase_start_t[4]).filter(func(e: Dictionary) -> bool:
		return e["mode"] == Wl.SIM and not e["warmup"])
	assert_gt(climb.map(func(e: Dictionary) -> float: return float(e["grade"])).max(), 3.0 + EPS,
		"after warm-up the climb is steeper than +3%")
	var hard := d.window(d.phase_start_t[4], d.phase_start_t[5])
	assert_true(hard.any(func(e: Dictionary) -> bool: return int(e["w"]) == 160), "80% (160 W) after warm-up")


# --- surge gesture through the stack (3.5, OWNERSHIP C30) -------------------------------------


func test_surge_profile_fires_every_erg_surge_through_the_rider() -> void:
	var plan := _finalized([
		PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up").with_ramp(65.0),
		PlanPhase.erg(Wl.WORK, 60.0, 300.0, "Work"),
		PlanPhase.erg(Wl.RECOVERY, 50.0, 120.0, "Easy"),
	])
	var d := _driver("erg+surge:every_s=60,for_s=2,lift=0.2", plan, {"seed": 11})
	d.run(650.0)
	var surges := d.gestures.filter(func(g: Dictionary) -> bool: return g["name"] == Wl.G_SURGE)
	assert_eq(surges.size(), 10, "10 surges in 650 s, 10 surge gestures: %s" % str(surges))
	assert_true(d.trace.all(func(e: Dictionary) -> bool: return e["mode"] != Wl.SIM), "all in ERG (speed rule)")
	var backs := d.gestures.filter(func(g: Dictionary) -> bool: return g["name"] == Wl.G_COAST or g["name"] == Wl.G_STOP_5S)
	assert_eq(backs.size(), 0, "never coast or stop_5s while riding")


# --- reconnect resync (4.4) -------------------------------------------------------------------


func test_reconnect_restores_erg_through_the_entry_and_slew() -> void:
	var d := _driver("erg", _easy_plan(60.0, 300.0))
	d.run(400.0)
	assert_eq(d.mock.commanded_target_w, 120)
	# The connection flow left the trainer at SIM flat; the same device object reconnected.
	d.mock.set_simulation(0.0, 0.0, 0.004, 0.51)
	var writes_before := d.mock.command_count
	var t0 := d.t()
	d.rider.trainer_reconnected()
	var commanded: Array[Dictionary] = []
	for i in roundi(10.0 / DT):
		d.step()
		commanded.append({"t": d.t(), "mode": d.mock.commanded_mode, "w": d.mock.commanded_target_w})
	assert_gt(d.mock.command_count, writes_before, "the governor wrote again")
	var first_erg := commanded.filter(func(c: Dictionary) -> bool: return c["mode"] == Wl.ERG)
	assert_gt(first_erg.size(), 0, "back in ERG")
	if first_erg.is_empty():
		return
	assert_gte(float(first_erg[0]["t"]) - t0, 0.5 - EPS, "after the flow's write slot")
	assert_lte(int(first_erg[0]["w"]), 120, "the entry never above the plan target")
	var prev_w := int(first_erg[0]["w"])
	var prev_t := float(first_erg[0]["t"])
	for c in first_erg:
		if int(c["w"]) != prev_w:
			assert_lte(float(int(c["w"]) - prev_w), 30.0 * (float(c["t"]) - prev_t) + 1.0, "slew 30 W/s")
			prev_w = int(c["w"])
			prev_t = float(c["t"])
	assert_eq(d.mock.commanded_target_w, 120, "the plan target again")
	assert_eq(d.rider.telemetry().phase_index, 1, "same phase")


# --- pause (4.1, 7.4) ---------------------------------------------------------------------------


## An ordinary node: inherits the pause.
class Pausable:
	extends Node
	var frames: int = 0

	func _process(_delta: float) -> void:
		frames += 1


func test_paused_tree_keeps_trainer_samples_flowing() -> void:
	CmdLine.set_args(PackedStringArray(), true)
	var dir := Paths.make_temp_dir("wattlands_stack_pause")
	_dirs.append(dir)
	Paths.set_override(dir)
	var settings := WlSettings.new()
	settings.bus = _bus
	settings.autosave = false
	autofree(settings)
	settings.load_all()
	var router := Fakes.FakeInputRouter.new()
	autofree(router)
	var svc := WlTrainerService.new()
	svc.settings = settings
	svc.bus = _bus
	svc.input_router = router
	add_child_autofree(svc)
	svc.use_mock("erg")
	var r := svc.local_rider()
	assert_not_null(r)
	assert_true(r.governor is SafetyGovernor and not (r.governor is Fakes.FakeGovernor), "the real governor")
	var mock := svc.device() as MockTrainer
	var pausable := Pausable.new()
	add_child_autofree(pausable)
	await get_tree().process_frame
	get_tree().paused = true
	var frames_before := pausable.frames
	var samples_before := mock.samples_emitted()
	var gov_t_before := float(r.governor.status()["t"])
	for i in 30:
		await get_tree().create_timer(0.1, true).timeout
		if mock.samples_emitted() >= samples_before + 2:
			break
	assert_true(get_tree().paused)
	assert_eq(pausable.frames, frames_before, "the tree really is paused")
	assert_gte(mock.samples_emitted(), samples_before + 2, "mock samples kept arriving")
	assert_gt(float(r.governor.status()["t"]), gov_t_before + 1.0, "the governor kept ticking on platform time")
	assert_gt(r.telemetry().power_w, 0.0, "telemetry carries the fresh samples")
	get_tree().paused = false


# --- the recorded ride (3.8, 7.5) ----------------------------------------------------------------


func test_ride_records_1_hz_with_laps_and_writes_a_valid_fit() -> void:
	var out_dir := ProjectSettings.globalize_path(FIT_DIR)
	_clear_dir(out_dir)
	var plan := _finalized([
		PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up").with_ramp(65.0),
		PlanPhase.erg(Wl.WORK, 80.0, 60.0, "Hard 1").with_lap(),
		PlanPhase.erg(Wl.RECOVERY, 50.0, 60.0, "Easy").with_lap(),
		PlanPhase.erg(Wl.WORK, 80.0, 60.0, "Hard 2").with_lap(),
	])
	var rec := RideRecorder.new()
	rec.ride_id = "core-stack-integration"
	var d := _driver("erg+band", plan, {"recorder": rec, "rides_dir": out_dir})
	var energy := {"j": 0.0}
	d.each_tick = func(dr: Driver) -> void:
		energy["j"] = float(energy["j"]) + dr.rider.telemetry().power_w * DT
	d.run_to_end()
	assert_true(d.finished)
	var ride_s := d.t()
	assert_almost_eq(ride_s, 660.0, DT * 1.5)
	var path := d.rider.finish_ride()
	assert_ne(path, "", "saved")
	assert_true(path.begins_with(out_dir), path)
	assert_true(FileAccess.file_exists(path))
	assert_true(FileAccess.file_exists(path.get_basename() + ".json"), "the JSON summary next to it")
	assert_almost_eq(float(rec.record_count()), ride_s, ride_s * 0.01 + 1.0, "one record per second from 20 Hz record() calls")
	assert_eq(rec.lap_count(), 5, "three lap-true phases, the cool-down lap and the opening lap")
	var fit := FileAccess.get_file_as_bytes(path)
	assert_true(FitCrc.file_is_valid(fit), "header and file CRCs")
	var summary := rec.summary()
	var kj := float(energy["j"]) / 1000.0
	assert_gt(kj, 50.0)
	assert_almost_eq(float(summary["kj"]), kj, kj * 0.01 + 0.5, "work equals the power the rider saw")
	assert_eq(int(summary["records"]), rec.record_count())
	assert_eq((summary["laps"] as Array).size(), 5)
	var recs := rec.records()
	var cad_absent := recs.filter(func(x: Dictionary) -> bool: return float(x.get("cadence_rpm", -1.0)) < 0.0)
	assert_lt(cad_absent.size(), 3, "the mock reports cadence from its first sample on")


func _clear_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
