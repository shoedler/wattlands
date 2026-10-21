extends "res://tests/scenarios/lib/scenario_test.gd"
## BRIEF 7.4 and 7.5 over every built-in Workout session (owned by qa; a W2 gate: it needs the
## integrated platform, GameSimRunner and Workout). One human slot (SOLO) with one bot, MockTrainer
## `erg` at compliance 1.0 and a verified FTP of 200 W, stepped tick by tick:
## - the compliant rider finishes with time in band >= 90 % and a grade of A or better;
## - the warm-up limits hold on every tick (ERG <= 65 % FTP, SIM grade -2..+3 %, no haptics);
## - no 4.6.1 duration limit ever latches, and the VO2 session's time above 105 % FTP never
##   reaches 300 s (nor above 120 % FTP 60 s) between 120 s resets at <= 90 % FTP, counted
##   independently of the governor from the applied targets;
## - the run writes one FIT per human slot that QaFitDecoder decodes with zero errors (CRCs,
##   cycling / virtual_activity), one record per second within 1 %, the FIT1 lap count (one per
##   lap-true phase plus the cool-down) and session totals equal to the recorder's.

const MAX_TICKS := int(3.0 * 3600.0 / 0.05)
const LIMIT_105_S := 300.0
const LIMIT_120_S := 60.0
const RESET_PCT := 90.0
const RESET_S := 120.0


func test_every_built_in_session_is_registered() -> void:
	var reg := WlGameRegistry.new()
	add_child_autofree(reg)
	reg.scan()
	assert_true(reg.has_game(S.WORKOUT), "workout is a valid registered game: %s" % str(reg.invalid_games()))
	var m := reg.manifest(S.WORKOUT)
	var contents: Array = m.get("contents", [])
	for id in S.WORKOUT_SESSIONS:
		assert_has(contents, id, "BRIEF 3.7 session %s" % id)
	assert_eq(m.get("e2e_content", ""), "e2e")
	assert_eq(m.get("default_content", ""), "easy_30")
	assert_eq(m.get("zero_input_content", ""), "easy_30")


func test_compliant_rider_finishes_every_session(p: Variant = use_parameters(S.WORKOUT_SESSIONS)) -> void:
	var content := str(p)
	var runner := start_runner(S.flags(content, report_path(content)))
	if runner == null:
		return
	var peer := S.human_peer(runner)
	var rider := human_rider(runner)
	if rider == null:
		return

	var warmup: Array[String] = []
	var latched: Array[String] = []
	var acc_105 := 0.0
	var acc_120 := 0.0
	var max_105 := 0.0
	var max_120 := 0.0
	var reset_run := 0.0
	var ticks := 0
	while not runner.host.is_finished() and ticks < MAX_TICKS:
		runner.step()
		ticks += 1
		var st := rider.governor.status()
		var t := S.platform_t(runner, rider)
		if warmup.size() < 20:
			warmup.append_array(S.warmup_problems(st, t))
		if latched.size() < 5 and (bool(st.get("latched_105", false)) or bool(st.get("latched_120", false)) or S.clamped(st, Wl.CLAMP_LIMIT_105) or S.clamped(st, Wl.CLAMP_LIMIT_120)):
			latched.append("t=%.2f: %s" % [t, str(st.get("clamped_by", []))])
		# The 4.6.1 duration counters, independently: ERG time above 105 % and 120 % FTP, reset by
		# 120 consecutive seconds of ERG at <= 90 %; SIM restarts the reset count.
		var pct := float(st.get("applied_pct", 0.0))
		if str(st.get("mode", "")) == Wl.ERG:
			if pct > 105.0 + S.EPS:
				acc_105 += Wl.SIM_DT
			if pct > 120.0 + S.EPS:
				acc_120 += Wl.SIM_DT
			reset_run = reset_run + Wl.SIM_DT if pct <= RESET_PCT + S.EPS else 0.0
			if reset_run >= RESET_S - S.EPS:
				acc_105 = 0.0
				acc_120 = 0.0
		else:
			reset_run = 0.0
		max_105 = maxf(max_105, acc_105)
		max_120 = maxf(max_120, acc_120)
	assert_true(runner.host.is_finished(), "%s finished within %d ticks" % [content, MAX_TICKS])
	assert_eq(warmup, [] as Array[String], "%s: warm-up limits\n%s" % [content, first(warmup)])
	assert_eq(latched, [] as Array[String], "%s: a 4.6.1 duration limit latched\n%s" % [content, first(latched)])
	assert_lt(max_105, LIMIT_105_S, "%s: time above 105 %% FTP stays under 300 s" % content)
	assert_lt(max_120, LIMIT_120_S, "%s: time above 120 %% FTP stays under 60 s" % content)
	if content == "vo2":
		assert_gt(max_105, 150.0, "vo2 really rides its 110 % intervals (a 180 s block above 105 %)")

	var end_reason := runner.run_to_end()
	assert_eq(end_reason, "complete", "%s ends after its cool-down" % content)
	var written := runner.write_report()
	var report := S.read_json(written)
	assert_false(report.is_empty(), "%s: the report was written to %s" % [content, written])
	if report.is_empty():
		return

	var row := S.result_row(report, peer)
	assert_false(row.is_empty(), "%s: a results row for the rider" % content)
	var tib := float(row.get("time_in_band_pct", 0.0))
	assert_gte(tib, 90.0, "%s: time in band %.1f %% >= 90 %%" % [content, tib])
	var grade := str(S.results(report).get("grade", ""))
	assert_true(grade == "S" or grade == "A", "%s: grade %s is A or better" % [content, grade])

	var fits := S.fit_paths(report)
	assert_eq(fits.size(), 1, "%s: one FIT per human slot (none for the bot)" % content)
	var summary: Dictionary = rider.recorder.summary() if rider.recorder != null else {}
	var expected := S.expected_laps(report, peer)
	assert_gt(expected, 1, "%s: laps expected (intervals plus the cool-down)" % content)
	for f in fits:
		assert_true(FileAccess.file_exists(f), "%s exists" % f)
		var problems := S.fit_problems(f, summary, expected)
		assert_eq(problems, [] as Array[String], "%s: FIT\n%s" % [content, first(problems)])
