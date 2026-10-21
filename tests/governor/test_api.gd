extends "res://tests/governor/gov_test_base.gd"
## The W0 stubs' frozen public API (docs/OWNERSHIP.md 1.3 "Governor" seam): every documented
## SafetyGovernor method keeps its argument count, every signal exists with its arguments,
## status() carries every documented key with the documented type, records carry every
## documented key, and status_changed fires at most once per tick. CadenceEstimator keeps its
## W0 surface too.

## name -> argument count, from the W0 stub.
const GOVERNOR_METHODS := {
	"setup": 1,
	"configure": 1,
	"set_plan": 1,
	"start_phase": 1,
	"set_game_paused": 1,
	"apply_directive": 1,
	"set_course_grade": 1,
	"set_course_distance": 1,
	"shift": 1,
	"on_sample": 1,
	"tick": 1,
	"emergency_safe": 0,
	"resume": 0,
	"shutdown": 0,
	"status": 0,
	"is_rescue": 0,
	"is_coasting": 0,
	"is_warmup_active": 0,
}
## name -> argument names, from the W0 stub.
const GOVERNOR_SIGNALS := {
	"status_changed": ["status"],
	"rescue_changed": ["active"],
	"coasting_changed": ["active"],
	"pause_requested": ["reason"],
	"afk_changed": ["afk"],
	"directive_applied": ["record"],
	"warmup_changed": ["active"],
	"panic_changed": ["active"],
}
## The W0 stub's documented status keys and their types.
const STATUS_KEYS := {
	"mode": TYPE_STRING,
	"applied_target_w": TYPE_INT,
	"applied_pct": TYPE_FLOAT,
	"applied_grade_pct": TYPE_FLOAT,
	"wind_mps": TYPE_FLOAT,
	"crr": TYPE_FLOAT,
	"cw": TYPE_FLOAT,
	"haptic_active": TYPE_BOOL,
	"clamped_by": TYPE_ARRAY,
	"rescue": TYPE_BOOL,
	"coasting": TYPE_BOOL,
	"afk": TYPE_BOOL,
	"paused": TYPE_BOOL,
	"panic": TYPE_BOOL,
	"warmup_active": TYPE_BOOL,
	"warmup_remaining_s": TYPE_FLOAT,
	"gear": TYPE_INT,
	"s_left_105": TYPE_FLOAT,
	"s_left_120": TYPE_FLOAT,
	"latched_105": TYPE_BOOL,
	"latched_120": TYPE_BOOL,
	"phase_index": TYPE_INT,
	"phase_elapsed_s": TYPE_FLOAT,
	"sim_block_active": TYPE_BOOL,
	"last_switch_t": TYPE_FLOAT,
	"profile": TYPE_STRING,
}
const RECORD_KEYS := ["id", "kind", "requested", "applied", "clamped_by", "refused", "reason", "t"]


func _methods(obj: Object) -> Dictionary:
	var out := {}
	for m: Dictionary in obj.get_method_list():
		out[str(m["name"])] = m
	return out


func _signals(obj: Object) -> Dictionary:
	var out := {}
	for s: Dictionary in obj.get_signal_list():
		out[str(s["name"])] = s
	return out


func test_governor_methods_keep_their_w0_signatures() -> void:
	var gov: SafetyGovernor = autofree(SafetyGovernor.new())
	var methods := _methods(gov)
	for name: String in GOVERNOR_METHODS:
		assert_true(methods.has(name), "SafetyGovernor.%s exists" % name)
		if methods.has(name):
			var args: Array = methods[name]["args"]
			assert_eq(
				args.size(), int(GOVERNOR_METHODS[name]), "SafetyGovernor.%s argument count" % name
			)


func test_governor_signals_keep_their_w0_arguments() -> void:
	var gov: SafetyGovernor = autofree(SafetyGovernor.new())
	var sigs := _signals(gov)
	for name: String in GOVERNOR_SIGNALS:
		assert_true(sigs.has(name), "signal %s exists" % name)
		if sigs.has(name):
			var names: Array = []
			for a: Dictionary in sigs[name]["args"]:
				names.append(str(a["name"]))
			assert_eq(names, GOVERNOR_SIGNALS[name], "signal %s arguments" % name)


func test_status_has_every_documented_key() -> void:
	var rig := make_rig({}, follower())
	_check_status(rig.s(), "before a plan")
	rig.start([erg(Wl.WORK, 70.0, 60.0), sim(Wl.GRADE_GAME, 60.0)])
	rig.run(5.0)
	_check_status(rig.s(), "in ERG")
	rig.gov.start_phase(1)
	rig.run(5.0)
	_check_status(rig.s(), "in SIM")
	rig.gov.emergency_safe()
	_check_status(rig.s(), "in panic")


func _check_status(s: Dictionary, where: String) -> void:
	for key: String in STATUS_KEYS:
		assert_true(s.has(key), "status has %s (%s)" % [key, where])
		if s.has(key):
			assert_eq(typeof(s[key]), int(STATUS_KEYS[key]), "status.%s type (%s)" % [key, where])
	assert_true(
		[Wl.ERG, Wl.SIM, Wl.OFF].has(str(s["mode"])), "mode is ERG, SIM or OFF (%s)" % where
	)
	assert_true(["normal", "ramp_test"].has(str(s["profile"])))
	assert_between(int(s["gear"]), 1, 24)


func test_status_is_a_copy() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 70.0, 60.0)])
	rig.run(2.0)
	var s := rig.s()
	(s["clamped_by"] as Array).append("tampered")
	s["applied_target_w"] = 9999
	assert_does_not_have(rig.s()["clamped_by"], "tampered")
	assert_ne(int(rig.s()["applied_target_w"]), 9999)


func test_records_have_every_documented_key() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 70.0, 60.0).with_range(60.0, 80.0), sim(Wl.GRADE_GAME, 60.0)])
	var recs: Array[Dictionary] = [
		rig.directive({"target_pct": 75.0}),
		rig.directive({"target_pct": 95.0}),
	]
	rig.gov.set_course_grade(2.0)
	rig.gov.start_phase(1)
	rig.gov.set_course_grade(2.0)
	recs.append_array(rig.records.slice(2))
	assert_eq(recs.size(), 4)
	for r: Dictionary in recs:
		for key: String in RECORD_KEYS:
			assert_true(r.has(key), "record %s has %s" % [r.get("kind"), key])
		assert_eq(typeof(r["refused"]), TYPE_BOOL)
		assert_eq(typeof(r["reason"]), TYPE_STRING)
		assert_eq(typeof(r["clamped_by"]), TYPE_ARRAY)
		assert_true(["request", "course_grade"].has(str(r["kind"])))
	assert_eq(
		rig.records.size(), 4, "every apply_directive and set_course_grade emits directive_applied"
	)


func test_status_changed_at_most_once_per_tick() -> void:
	var rig := make_rig({}, follower())
	var count := [0]
	rig.gov.status_changed.connect(func(_s: Dictionary) -> void: count[0] += 1)
	rig.start([erg(Wl.WORK, 70.0, 60.0)])
	var ticks := 200
	for i in ticks:
		var before: int = count[0]
		rig.step()
		assert_lte(int(count[0]) - before, 1, "tick %d" % i)
	assert_gt(int(count[0]), 0)


func test_defaults_before_configure() -> void:
	var gov: SafetyGovernor = autofree(SafetyGovernor.new())
	var s := gov.status()
	assert_eq(gov.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(s["mode"], Wl.OFF)
	assert_eq(int(s["gear"]), 12)
	assert_eq(s["profile"], "normal")
	assert_true(gov.is_warmup_active(), "warm-up is on until a rider skips it")
	assert_false(gov.is_rescue())
	assert_false(gov.is_coasting())
	assert_almost_eq(float(s["ftp_w"]), 200.0, 1e-9, "BRIEF 3.2 default FTP")
	assert_false(bool(s["ftp_verified"]), "unverified until typed in or tested")
	assert_eq(gov.shift(1), 12, "no SIM yet: the gear stays")


func test_cadence_estimator_keeps_its_w0_surface() -> void:
	var est := CadenceEstimator.new()
	assert_almost_eq(est.stale_s, 3.0, 1e-12)
	var methods := _methods(est)
	for name: String in ["process", "start_calibration", "is_calibrating", "ratio"]:
		assert_true(methods.has(name), "CadenceEstimator.%s" % name)
	assert_eq((methods["process"]["args"] as Array).size(), 1)
	assert_eq((methods["start_calibration"]["args"] as Array).size(), 1)
