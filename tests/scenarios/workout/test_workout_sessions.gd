extends "res://tests/scenarios/lib/scenario_test.gd"
## BRIEF 7.4 and 7.5 over every built-in Workout session (owned by qa; a W2 gate: it needs the
## integrated platform, GameSimRunner and Workout). One human slot (SOLO) with one bot, MockTrainer
## `erg` at compliance 1.0 and a verified FTP of 200 W, stepped tick by tick:
## - the compliant rider finishes with time in band >= 90 % and a grade of A or better;
## - the warm-up limits hold on every tick (ERG <= 65 % FTP, SIM grade -2..+3 %, no haptics), and
##   the governor's warm-up is on for the first 300 s after the first pedaling sample (counted
##   here from the MockTrainer's samples, less a 2 s margin);
## - every applied ERG target stays at or below 150 % FTP, and at or below 105 % FTP in phases
##   longer than 300 s;
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
	# The GameRegistry autoload, not a private instance: a freed instance would also remove the
	# game translations the autoload registered (see S.ensure_game_strings).
	var reg := S.registry(self)
	assert_not_null(reg, "the GameRegistry autoload")
	if reg == null:
		return
	assert_true(
		reg.has_game(S.WORKOUT), "workout is a valid registered game: %s" % str(reg.invalid_games())
	)
	var m := reg.manifest(S.WORKOUT)
	var contents: Array = m.get("contents", [])
	for id in S.WORKOUT_SESSIONS:
		assert_has(contents, id, "BRIEF 3.7 session %s" % id)
	assert_eq(m.get("e2e_content", ""), "e2e")
	assert_eq(m.get("default_content", ""), "easy_30")
	assert_eq(m.get("zero_input_content", ""), "easy_30")


func test_compliant_rider_finishes_every_session(
	p: Variant = use_parameters(S.WORKOUT_SESSIONS)
) -> void:
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
	var caps: Array[String] = []
	var acc_105 := 0.0
	var acc_120 := 0.0
	var max_105 := 0.0
	var max_120 := 0.0
	var reset_run := 0.0
	var warmup_seen := false
	# The warm-up counted independently of the governor's flag: the first 300 s after the first
	# pedaling sample (BRIEF 4.6.8), less a 2 s margin for the governor's own start.
	var first_pedal := {"t": -1.0}
	S.mock_of(rider).sample_received.connect(
		func(s: TrainerSample) -> void:
			if float(first_pedal["t"]) < 0.0 and not S.is_not_pedaling(s):
				first_pedal["t"] = s.t
	)
	var plan: Array = []
	var ticks := 0
	while not runner.host.is_finished() and ticks < MAX_TICKS:
		runner.step()
		ticks += 1
		if plan.is_empty() and ticks <= 20:
			plan = S.plan_phases(runner.build_report(), peer)
		var st := rider.governor.status()
		var t := S.platform_t(runner, rider)
		warmup_seen = warmup_seen or bool(st.get("warmup_active", false))
		if warmup.size() < 20:
			warmup.append_array(S.warmup_problems(st, t))
			var fp := float(first_pedal["t"])
			if fp >= 0.0 and t - fp < S.WARMUP_S - 2.0 and not bool(st.get("warmup_active", false)):
				warmup.append(
					"t=%.2f: %.1f s into the ride but the governor's warm-up is off" % [t, t - fp]
				)
		if caps.size() < 20:
			var i := int(st.get("phase_index", -1))
			caps.append_array(
				S.cap_problems(
					st, S.phase_length_s(plan[i]) if i >= 0 and i < plan.size() else 0.0, t
				)
			)
		if (
			latched.size() < 5
			and (
				bool(st.get("latched_105", false))
				or bool(st.get("latched_120", false))
				or S.clamped(st, Wl.CLAMP_LIMIT_105)
				or S.clamped(st, Wl.CLAMP_LIMIT_120)
			)
		):
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
	assert_true(warmup_seen, "%s: the governor's warm-up was active at the start" % content)
	assert_eq(warmup, [] as Array[String], "%s: warm-up limits\n%s" % [content, first(warmup)])
	assert_false(plan.is_empty(), "%s: the rider's validated plan is in the report" % content)
	assert_eq(caps, [] as Array[String], "%s: BRIEF 4.6.1 caps\n%s" % [content, first(caps)])
	assert_eq(
		latched,
		[] as Array[String],
		"%s: a 4.6.1 duration limit latched\n%s" % [content, first(latched)]
	)
	assert_lt(max_105, LIMIT_105_S, "%s: time above 105 %% FTP stays under 300 s" % content)
	assert_lt(max_120, LIMIT_120_S, "%s: time above 120 %% FTP stays under 60 s" % content)
	if content == "vo2":
		assert_gt(
			max_105, 150.0, "vo2 really rides its 110 % intervals (a 180 s block above 105 %)"
		)

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
