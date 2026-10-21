extends GutTest
## Whole Workout sessions through GameSimRunner with MockTrainer riders (BRIEF 7.4; W2:
## needs sdk-runtime's runner, the governor and MockTrainer). Left out of game-workout's W1
## test command; the full suite runs it.
##
## Assertions: a compliant, verified rider finishes every built-in session with time in
## band >= 90% and grade A or better; e2e stays inside the warm-up limits in HOST play;
## VO2 never latches the 105% duration limit; the sample .zwo plays; the same seed gives the
## same report hash; a 0 W rider grades D.

const BUILT_IN: Array[String] = ["easy_30", "sweet_spot", "threshold", "vo2", "rolling_road", "e2e"]

var _tmp: String = ""


func before_each() -> void:
	_tmp = Paths.make_temp_dir("workout_sims")
	Paths.set_override(_tmp)


func after_each() -> void:
	Paths.set_override("")


func _run(content: String, extra: Array[String] = []) -> Dictionary:
	var argv := PackedStringArray([
		"--game=workout", "--content=" + content, "--players=1", "--bots=1",
		"--rider=erg:compliance=1.0", "--seed=11", "--sim-speed=100000",
		"--report=" + _tmp.path_join("%s.json" % content.replace(":", "_").replace("/", "_")),
	])
	for a in extra:
		var key := a.split("=")[0]
		for i in range(argv.size() - 1, -1, -1):
			if argv[i].begins_with(key + "="):
				argv.remove_at(i)
		argv.append(a)
	var args := GameSimRunner.parse_args(argv)
	assert_false(args.has("error"), "args: %s" % args.get("error", ""))
	args["headless"] = true
	var runner := GameSimRunner.new()
	add_child_autofree(runner)
	var err := runner.setup(args)
	assert_eq(err, "", "setup %s" % content)
	if err != "":
		return {}
	var end := runner.run_to_end()
	var report := runner.build_report()
	report["_end"] = end
	report["_results"] = runner.host.final_results() if runner.host != null else null
	return report


func test_compliant_riders_grade_a_or_better_in_every_session() -> void:
	for id in BUILT_IN:
		var report := _run(id)
		if report.is_empty():
			continue
		assert_eq(report["_end"], "complete", "%s ends after the cool-down" % id)
		var res: GameResults = report["_results"]
		assert_not_null(res, "%s results" % id)
		if res == null:
			continue
		assert_true(["S", "A"].has(res.grade), "%s grade %s" % [id, res.grade])
		for row in res.rows:
			assert_true(float(row["time_in_band_pct"]) >= 90.0, "%s rider %s in band %s%%" % [id, row["peer_id"], row["time_in_band_pct"]])


func test_e2e_host_play_stays_inside_the_warmup_limits() -> void:
	var report := _run("e2e", ["--players=3", "--bots=0"])
	if report.is_empty():
		return
	assert_eq(report["_end"], "complete")
	var trace: Variant = report.get("traces", report.get("trace", []))
	var points: Array[Dictionary] = []
	_collect(trace, points)
	assert_gt(points.size(), 0, "the report has 1 Hz traces")
	for pt in points:
		for key: String in ["applied_pct", "applied_ftp_pct"]:
			if pt.has(key):
				assert_true(float(pt[key]) <= 65.0 + 0.001, "%s inside the warm-up cap: %s" % [key, pt])
		for key: String in ["applied_grade_pct", "applied_grade"]:
			if pt.has(key):
				assert_true(float(pt[key]) >= -2.0 - 0.001 and float(pt[key]) <= 3.0 + 0.001, "%s inside -2..+3: %s" % [key, pt])


## Every Dictionary inside `v` that looks like a trace point.
func _collect(v: Variant, out: Array[Dictionary]) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("applied_target_w"):
			out.append(d)
		for k: Variant in d.keys():
			_collect(d[k], out)
	elif v is Array:
		for e: Variant in v:
			_collect(e, out)


func test_vo2_never_latches_the_105_limit() -> void:
	var report := _run("vo2")
	if report.is_empty():
		return
	var text := JSON.stringify(report.get("traces", report.get("trace", [])))
	assert_false(text.contains(Wl.CLAMP_LIMIT_105), "no limit_105 clamp in VO2")
	assert_false(text.contains(Wl.CLAMP_LIMIT_120))


func test_the_sample_zwo_plays() -> void:
	var report := _run("zwo_sample")
	if report.is_empty():
		return
	assert_eq(report["_end"], "complete")
	var g := WorkoutGame.new()
	autofree(g)
	assert_gt((g.session_preview("zwo_sample")["lines"] as Array).size(), 0)


func test_same_seed_same_hash() -> void:
	var a := _run("e2e")
	var b := _run("e2e")
	if a.is_empty() or b.is_empty():
		return
	assert_eq(a["deterministic_hash"], b["deterministic_hash"])


func test_a_zero_watt_rider_grades_d() -> void:
	var report := _run("e2e", ["--rider=zero", "--bots=0"])
	if report.is_empty():
		return
	var res: GameResults = report["_results"]
	assert_not_null(res)
	if res != null:
		assert_eq(res.grade, "D")
