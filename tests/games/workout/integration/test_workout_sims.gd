extends GutTest
## Whole Workout sessions through GameSimRunner with MockTrainer riders (BRIEF 7.4; W2:
## needs sdk-runtime's runner, the governor and MockTrainer). Left out of game-workout's W1
## test command; the full suite runs it.
##
## Assertions: e2e stays inside the warm-up limits in HOST play; a zwo path content id reaches
## every client; the same seed gives the same report hash; the human and the bot both ride e2e
## in band; a 0 W rider grades D; rescue on a cadence collapse only at or above 60% FTP. A
## compliant rider finishing every built-in session and the sample .zwo with an A or better, in
## band, inside the warm-up limits and with no duration limit latched, is tests/scenarios/workout
## (test_workout_sessions.gd, test_zwo_import.gd), which holds the human row only.

var _tmp: String = ""
## Runners made by a test: cleanup() deletes each one's temp root (W3 QT-4).
var _runners: Array[GameSimRunner] = []


func before_each() -> void:
	_tmp = Paths.make_temp_dir("workout_sims")
	Paths.set_override(_tmp)


func after_each() -> void:
	for r in _runners:
		if is_instance_valid(r):
			r.cleanup()
	_runners.clear()
	Paths.set_override("")
	GameSimRunner._remove_tree(_tmp)


## A runner added to the tree (autofree) whose temp root after_each deletes.
func _new_runner() -> GameSimRunner:
	var runner := GameSimRunner.new()
	add_child_autofree(runner)
	_runners.append(runner)
	return runner


func _run(content: String, extra: Array[String] = []) -> Dictionary:
	var argv := PackedStringArray(
		[
			"--game=workout",
			"--content=" + content,
			"--players=1",
			"--bots=1",
			"--rider=erg:compliance=1.0",
			"--seed=11",
			"--sim-speed=100000",
			"--report=" + _tmp.path_join("%s.json" % content.replace(":", "_").replace("/", "_")),
		]
	)
	for a in extra:
		var key := a.split("=")[0]
		for i in range(argv.size() - 1, -1, -1):
			if argv[i].begins_with(key + "="):
				argv.remove_at(i)
		argv.append(a)
	var args := GameSimRunner.parse_args(argv)
	assert_false(args.has("error"), "args: %s" % args.get("error", ""))
	args["headless"] = true
	var runner := _new_runner()
	var err := runner.setup(args)
	assert_eq(err, "", "setup %s" % content)
	if err != "":
		return {}
	var end := runner.run_to_end()
	var report := runner.build_report()
	report["_end"] = end
	report["_results"] = runner.host.final_results() if runner.host != null else null
	return report


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
				assert_true(
					float(pt[key]) <= 65.0 + 0.001, "%s inside the warm-up cap: %s" % [key, pt]
				)
		for key: String in ["applied_grade_pct", "applied_grade"]:
			if pt.has(key):
				assert_true(
					float(pt[key]) >= -2.0 - 0.001 and float(pt[key]) <= 3.0 + 0.001,
					"%s inside -2..+3: %s" % [key, pt]
				)


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


## game-workout W1: "zwo:<absolute path>" is not in game.json contents; Workout lists the zwo
## scheme (content_schemes), so the runner, the host and every client pass it through as
## ctx.content_id and the imported session plays.
func test_a_zwo_path_content_id_runs_through_the_runner_and_reaches_clients() -> void:
	var content := "zwo:" + ProjectSettings.globalize_path("res://content/workout/zwo/sample.zwo")
	var args := (
		GameSimRunner
		. parse_args(
			PackedStringArray(
				[
					"--game=workout",
					"--content=" + content,
					"--players=2",
					"--bots=1",
					"--seed=4",
					"--max-sim-seconds=20",
					"--report=" + _tmp.path_join("zwo_path.json"),
				]
			)
		)
	)
	assert_false(args.has("error"), str(args.get("error", "")))
	args["headless"] = true
	var runner := _new_runner()
	assert_eq(runner.setup(args), "")
	assert_eq(runner.run_to_end(), "timeout")
	assert_eq(runner.build_report()["content_id"], content)
	for gh in runner.hosts():
		assert_eq(gh.ctx.content_id, content, "peer %d" % gh.local_peer())
		assert_true(
			gh.plans.has(gh.local_peer()), "peer %d has its imported plan" % gh.local_peer()
		)
	var bad := _new_runner()
	assert_string_starts_with(
		bad.setup(
			GameSimRunner.parse_args(PackedStringArray(["--game=workout", "--content=mp3:x"]))
		),
		"--content:"
	)


func test_same_seed_same_hash() -> void:
	var a := _run("e2e")
	var b := _run("e2e")
	if a.is_empty() or b.is_empty():
		return
	assert_eq(a["deterministic_hash"], b["deterministic_hash"])


## A compliant rider and the bot both ride e2e in band. The pinned scenario (test_workout_sessions.gd)
## holds the human row of every built-in session to 90 %; this keeps a bot's row held too.
func test_the_bot_rides_e2e_in_band_too() -> void:
	var report := _run("e2e")
	if report.is_empty():
		return
	assert_eq(report["_end"], "complete")
	var res: GameResults = report["_results"]
	assert_not_null(res, "e2e results")
	if res == null:
		return
	var bots := 0
	for row in res.rows:
		if bool(row.get("is_bot", false)):
			bots += 1
		assert_gte(
			float(row["time_in_band_pct"]),
			90.0,
			"e2e rider %s in band %s%%" % [row["peer_id"], row["time_in_band_pct"]]
		)
	assert_eq(bots, 1, "the bot has a row")


func test_a_zero_watt_rider_grades_d() -> void:
	var report := _run("e2e", ["--rider=zero", "--bots=0"])
	if report.is_empty():
		return
	assert_eq(report["_end"], "paused", "a 0 W solo rider pauses (4.6.4), and the run ends paused")
	var res: GameResults = report["_results"]
	assert_not_null(res)
	if res != null:
		assert_eq(res.grade, "D")


## BRIEF 7.4: rescue triggers on cadence collapse in an ERG phase while the applied target
## is >= 60% FTP (a WORK interval, Easy 30's main set, the warm-up ramp past 60%) and never
## below it (a RECOVERY at 50%). A verified-FTP mock rider, no bots; each run stops a little
## after the drop.
func test_rescue_on_cadence_collapse_only_at_or_above_60_pct() -> void:
	var cases := [
		["vo2", "erg+cadence_drop:rpm=30,at_phase=1,after_s=20,for_s=30", 1, 700, true],
		["easy_30", "erg+cadence_drop:rpm=30,at_phase=1,after_s=20,for_s=30", 1, 700, true],
		["vo2", "erg+cadence_drop:rpm=30,at_phase=0,at_target_pct=60,for_s=30", 0, 300, true],
		["vo2", "erg+cadence_drop:rpm=30,at_phase=2,after_s=20,for_s=30", 2, 700, false],
	]
	for c: Array in cases:
		var report := _run(
			str(c[0]), ["--rider=" + str(c[1]), "--bots=0", "--max-sim-seconds=%d" % int(c[3])]
		)
		if report.is_empty():
			continue
		var points: Array[Dictionary] = []
		_collect(report.get("traces", report.get("trace", [])), points)
		assert_gt(points.size(), 0, "%s has 1 Hz traces" % c[0])
		var rescued: Array[Dictionary] = []
		for pt in points:
			if bool(pt.get("rescue", false)):
				rescued.append(pt)
		if bool(c[4]):
			assert_gt(rescued.size(), 0, "%s: rescue in phase %d (%s)" % [c[0], c[2], c[1]])
			for pt in rescued:
				var idx := _phase_of(pt)
				if idx >= 0:
					assert_eq(
						idx,
						int(c[2]),
						"%s: rescue only in the phase with the drop: %s" % [c[0], pt]
					)
		else:
			assert_eq(
				rescued.size(), 0, "%s: no rescue below 60%% FTP: %s" % [c[0], rescued.slice(0, 3)]
			)


## The phase index of a trace point (-1 if the report names it otherwise).
func _phase_of(pt: Dictionary) -> int:
	for key: String in ["phase_index", "phase", "index"]:
		if pt.has(key) and (pt[key] is int or pt[key] is float):
			return int(pt[key])
	return -1
