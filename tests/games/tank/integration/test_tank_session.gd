extends GutTest
## The game through the real platform runtime: GameRegistry and GameSimRunner (sdk-runtime) on
## top of the trainer stack. Session-level checks only (the plan checks are lead-owned, in
## tests/games/tank/contracts/test_tank_plans.gd). G0 version; the module builder extends it.

const F := preload("res://tests/games/tank/tank_fakes.gd")

var _dirs: Array[String] = []
## Runners made by a test: cleanup() deletes each one's temp root.
var _runners: Array[GameSimRunner] = []


func before_each() -> void:
	var d := Paths.make_temp_dir("tank_session")
	_dirs.append(d)
	Paths.set_override(d)


func after_each() -> void:
	for r in _runners:
		if is_instance_valid(r):
			r.cleanup()
	_runners.clear()
	Paths.set_override("")
	for d in _dirs:
		GameSimCli.remove_tree(d)
	_dirs.clear()


func _registry() -> WlGameRegistry:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	add_child_autofree(reg)
	reg.scan()
	return reg


func test_the_manifest_validates_and_tank_is_listed() -> void:
	var reg := WlGameRegistry.new()
	add_child_autofree(reg)
	reg.scan()
	assert_eq(reg.validate_manifest(F.manifest(), F.GAME_DIR.path_join("game.json")), "")
	assert_true(reg.has_game(F.GAME_ID))


func _run(flags: Array[String]) -> Dictionary:
	var report := _dirs[0].path_join("report.json")
	var args := PackedStringArray(
		["--game=" + F.GAME_ID, "--report=" + report, "--sim-speed=1000"] + flags
	)
	var parsed := GameSimRunner.parse_args(args)
	assert_false(parsed.has("error"), str(parsed.get("error", "")))
	parsed["headless"] = true
	parsed["registry"] = _registry()
	var runner := GameSimRunner.new()
	add_child_autofree(runner)
	_runners.append(runner)
	assert_eq(runner.setup(parsed), "")
	var reason := runner.run_to_end()
	var out := runner.build_report()
	out["_end"] = reason
	out["_path"] = runner.write_report()
	return out


func test_a_solo_drill_completes_with_one_fit_and_nothing_refused() -> void:
	var r := _run(["--content=drill", "--players=1", "--rider=erg", "--seed=3"])
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("finished_reason"), TankIds.OUTCOME_COMPLETE)
	assert_eq((r.get("fit_paths", []) as Array).size(), 1)
	for d: Dictionary in r.get("directives", []):
		assert_true(bool(d["accepted"]), "accepted: %s" % JSON.stringify(d))
	assert_eq(int(r.get("oversize_snapshots", -1)), 0)
	assert_lte(int(r.get("max_snapshot_bytes", 99999)), TankConst.SNAPSHOT_MAX_BYTES)


func test_a_host_drill_with_two_humans_completes() -> void:
	var r := _run(["--content=drill", "--players=2", "--rider=erg", "--seed=5"])
	assert_eq(r["_end"], "complete")
	assert_eq((r.get("fit_paths", []) as Array).size(), 2)
	var group: Array = []
	for e: Dictionary in r.get("events", []):
		if str(e.get("type", "")) == "game_phase_changed":
			group.append(int(e["index"]))
	assert_eq(group, [0, 1, 2, 3], "the group's phase, the cool-down included")


## Zero input (brief 0.4): a solo Bulwark plays Ashfall Road to the results with a mission
## outcome; every WORK phase ends by end_phase or at max_s (whether the crew wins without an
## overrun is T1, a G2 balance gate), every other phase by its duration.
func test_a_solo_bulwark_plays_ashfall_road_to_the_results_with_zero_input() -> void:
	var r := _run(["--content=ashfall_road", "--players=1", "--rider=erg", "--seed=1"])
	assert_eq(r["_end"], "complete")
	assert_has([TankIds.OUTCOME_VICTORY, TankIds.OUTCOME_WITHDRAWN], r.get("finished_reason"))
	var hist: Array = r["phases"]["1"]
	assert_eq(hist.size(), 12, "11 segments and the cool-down")
	for ph: Dictionary in hist:
		var at := "phase %d" % int(ph["index"])
		if str(ph["kind"]) == Wl.WORK:
			assert_has([Wl.ENDED_END_PHASE, Wl.ENDED_MAX_S], ph["ended_by"], at)
		elif str(ph["kind"]) != Wl.COOLDOWN:
			assert_eq(ph["ended_by"], Wl.ENDED_DURATION, at)
