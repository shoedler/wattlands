extends "res://tests/scenarios/lib/scenario_test.gd"
## BRIEF 7.4 and 3.7: an imported sample .zwo plays with its clamps shown. The fixture has no
## warm-up of its own, a 10-minute block at 110 % FTP (above the 105 % cap for phases longer than
## 300 s), intervals, a ramp, a free ride and a tag the importer does not support. ZwoImport
## must insert a warm-up prefix, clamp to BRIEF 4.6 and the warm-up limits, list every clamp with
## its reason (what the session preview shows) and skip the unknown tag with a warning; the
## PlanValidator then accepts the plan, and the rider's stack plays it with every applied ERG
## target inside the clamped plan. Workout's own .zwo session is also played end to end through
## GameSimRunner, with its clamps in the session preview. Owned by qa; a W2 gate.

const FIXTURE := "res://tests/scenarios/workout/fixtures/qa_sample.zwo"


func _import() -> Dictionary:
	return ZwoImport.parse_zwo_file(ProjectSettings.globalize_path(FIXTURE))


func test_import_lists_clamps_and_skips_unknown_tags() -> void:
	var r := _import()
	assert_true(bool(r["ok"]), "the sample imports: %s" % str(r.get("error", "")))
	assert_eq(r["name"], "QA sample")
	var clamps: Array = r["clamps"]
	assert_gt(clamps.size(), 0, "the clamps are listed for the preview")
	var text := "\n".join(PackedStringArray(clamps))
	assert_true(
		text.contains("105") or text.contains("1.05"),
		"the 110 %% block is capped at 105 %%:\n%s" % text
	)
	for c: Variant in clamps:
		assert_true(str(c).strip_edges() != "", "each clamp names its block and reason")
	assert_string_contains(
		"\n".join(PackedStringArray(r["warnings"])),
		"MaxEffort",
		"the unsupported tag is skipped with a warning"
	)
	var blocks: Array = r["blocks"]
	assert_gte(blocks.size(), 6, "the raw blocks are kept for the preview")


func test_imported_plan_respects_the_safety_limits() -> void:
	var r := _import()
	if not bool(r["ok"]):
		fail_test("import failed: %s" % str(r.get("error", "")))
		return
	var phases: Array = r["phases"]
	assert_gt(phases.size(), 0)
	var p0: PlanPhase = phases[0]
	assert_eq(p0.kind, Wl.WARMUP, "a warm-up prefix is inserted")
	var t := 0.0
	var has_sim := false
	for ph: PlanPhase in phases:
		assert_ne(ph.kind, Wl.COOLDOWN, "the importer never writes the platform's cool-down")
		if ph.mode == Wl.SIM:
			has_sim = true
		elif ph.mode == Wl.ERG:
			assert_lte(ph.peak_pct(), 150.0 + S.EPS, "%s within 150 %%" % ph.label)
			if ph.worst_case_length_s() > 300.0:
				assert_lte(
					ph.peak_pct(),
					105.0 + S.EPS,
					"%s (%.0f s) capped at 105 %%" % [ph.label, ph.worst_case_length_s()]
				)
			if t < S.WARMUP_S:
				assert_lte(
					ph.peak_pct(),
					S.WARMUP_ERG_MAX_PCT + S.EPS,
					"%s starts inside the first 300 s, so <= 65 %%" % ph.label
				)
		t += ph.best_case_length_s()
	assert_true(has_sim, "FreeRide becomes a SIM phase")
	var plan := EffortPlan.of(phases)
	var v := PlanValidator.validate(plan)
	assert_true(bool(v["ok"]), "the PlanValidator accepts the clamped plan: %s" % str(v["errors"]))


func test_imported_plan_plays_inside_its_clamps() -> void:
	var r := _import()
	if not bool(r["ok"]):
		fail_test("import failed: %s" % str(r.get("error", "")))
		return
	var fin := PlanValidator.finalize(EffortPlan.of(r["phases"]))
	assert_not_null(fin, "finalize appends the cool-down")
	if fin == null:
		return
	assert_true(fin.cooldown_appended)
	var profile := RiderProfile.new()
	profile.ftp_w = S.FTP
	profile.ftp_verified = true
	var slot := profile.to_slot(1, Wl.FAIR_FTP)
	var device := MockTrainer.from_spec("erg", S.FTP, {"seed": 3})
	var rider := LocalRider.new()
	add_child_autofree(rider)
	rider.setup(
		1,
		profile,
		slot,
		device,
		{
			"multiplayer": false,
			"record": false,
			"game_id": S.WORKOUT,
			"content_id": "qa_sample",
			"seed": 3
		}
	)
	if device.get_parent() == null:
		add_child_autofree(device)
	rider.set_plan(fin)
	var problems: Array[String] = []
	var t := 0.0
	for i in fin.size():
		var ph := fin.phase(i)
		rider.start_phase(i)
		var steps := int(roundf(ph.duration_s / Wl.SIM_DT))
		for k in steps:
			rider.tick(Wl.SIM_DT)
			t += Wl.SIM_DT
			var st := rider.governor.status()
			if str(st.get("mode", "")) != Wl.ERG or problems.size() >= 10:
				continue
			var applied := float(st.get("applied_pct", 0.0))
			var planned := ph.planned_pct_at(k * Wl.SIM_DT) if ph.mode == Wl.ERG else 0.0
			if ph.mode == Wl.ERG and applied > maxf(planned, ph.peak_pct()) + 0.5:
				problems.append(
					(
						"t=%.1f %s: applied %.1f %% above the clamped plan's %.1f %%"
						% [t, ph.label, applied, planned]
					)
				)
			if ph.worst_case_length_s() > 300.0 and applied > 105.0 + S.EPS:
				problems.append(
					"t=%.1f %s: applied %.1f %% above the long-phase cap" % [t, ph.label, applied]
				)
			problems.append_array(S.warmup_problems(st, t))
	assert_eq(problems, [] as Array[String], first(problems))
	assert_false(rider.governor.is_rescue(), "a compliant rider ends the import without rescue")


## BRIEF 7.4 end to end: Workout plays its own .zwo session (content/workout/sessions/<id>.json
## with a "zwo" key) through GameSimRunner, a compliant verified-FTP rider finishes it, every
## applied ERG target stays inside BRIEF 4.6.1 and the warm-up limits, no duration limit
## latches, and the importer's clamps are shown (ZwoImport lists them, and Workout's
## session preview, when it has one, shows each).
func test_workout_plays_its_zwo_session_with_its_clamps_shown() -> void:
	var sessions := S.zwo_sessions()
	assert_gt(
		sessions.size(), 0, "Workout lists a .zwo session in game.json (BRIEF 3.7 Workout Director)"
	)
	if sessions.is_empty():
		return
	var content := str(sessions[0]["content"])
	var zwo := str(sessions[0]["zwo"])
	var imported := ZwoImport.parse_zwo_file(ProjectSettings.globalize_path(zwo))
	assert_true(bool(imported["ok"]), "%s imports: %s" % [zwo, str(imported.get("error", ""))])
	var clamps: Array = imported["clamps"]
	assert_gt(clamps.size(), 0, "%s needs clamps, so the preview has some to show" % zwo)

	var runner := start_runner(S.flags(content, report_path(content), ["--bots=0"]))
	if runner == null:
		return
	var peer := S.human_peer(runner)
	var rider := human_rider(runner)
	if rider == null:
		return
	var game: GameModule = runner.host.game
	if game != null and game.has_method("session_preview"):
		assert_true(
			S.ensure_game_strings(self, "WORKOUT_PREVIEW_CLAMP"), "Workout's strings are registered"
		)
		var preview: Variant = game.call("session_preview", content)
		assert_true(
			preview is Dictionary and not (preview as Dictionary).is_empty(),
			"Workout's session preview of %s" % content
		)
		var text := JSON.stringify(preview)
		for c: Variant in clamps:
			assert_string_contains(text, str(c), "the preview shows the clamp")
	runner.step()
	var plan := S.plan_phases(runner.build_report(), peer)
	assert_false(plan.is_empty(), "%s: the rider's validated plan is in the report" % content)

	var problems: Array[String] = []
	var ticks := 0
	var max_ticks := int(3.0 * 3600.0 / Wl.SIM_DT)
	while not runner.host.is_finished() and ticks < max_ticks:
		runner.step()
		ticks += 1
		if problems.size() >= 20:
			continue
		var st := rider.governor.status()
		var t := S.platform_t(runner, rider)
		var i := int(st.get("phase_index", -1))
		var length := S.phase_length_s(plan[i]) if i >= 0 and i < plan.size() else 0.0
		problems.append_array(S.cap_problems(st, length, t))
		problems.append_array(S.warmup_problems(st, t))
		if bool(st.get("latched_105", false)) or bool(st.get("latched_120", false)):
			problems.append("t=%.2f: a 4.6.1 duration limit latched" % t)
	assert_true(runner.host.is_finished(), "%s finished" % content)
	assert_eq(problems, [] as Array[String], "%s:\n%s" % [content, first(problems)])
	assert_eq(runner.run_to_end(), "complete", "%s ends after its cool-down" % content)
	var report := S.read_json(runner.write_report())
	var row := S.result_row(report, peer)
	assert_gte(
		float(row.get("time_in_band_pct", 0.0)),
		90.0,
		"%s: a compliant rider stays in band" % content
	)
	for f in S.fit_paths(report):
		var fit := S.fit_problems(
			f,
			rider.recorder.summary() if rider.recorder != null else {},
			S.expected_laps(report, peer)
		)
		assert_eq(fit, [] as Array[String], "%s: FIT\n%s" % [content, first(fit)])
