extends GutTest
## The game through the real platform runtime: GameRegistry, PlanValidator and GameSimRunner
## (sdk-runtime) on top of the trainer stack. G0 version; the module builder extends it.

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


## Every plan, every crew, rotation on and off: valid, no switch warning, the first 300 s within
## 4.6.8, and per rider every ERG <-> SIM switch >= 60 s apart with each open phase at its min_s
## and at its max_s (brief 2.3, BRIEF 4.5).
func test_every_plan_passes_the_validator_with_switches_60_s_apart() -> void:
	for content_id: String in F.manifest()["contents"]:
		for crew in [1, 2, 3]:
			for rotation in [true, false]:
				var ctx := F.make_ctx(crew, 0, content_id)
				ctx.options["rotation"] = rotation
				var game: TankGame = autofree(F.make_game(ctx))
				var plans := game.build_effort_plans()
				for peer: int in plans:
					var at := "%s crew %d rotation %s peer %d" % [content_id, crew, rotation, peer]
					var plan: EffortPlan = plans[peer]
					var v := PlanValidator.validate(plan)
					assert_true(v["ok"], "%s: %s" % [at, v["errors"]])
					assert_eq(v["warnings"], [], at)
					var final := PlanValidator.finalize(plan)
					assert_eq(final.phase(final.size() - 1).kind, Wl.COOLDOWN, at)
					for use_max in [false, true]:
						assert_gte(
							_min_switch_gap(final, use_max),
							60.0,
							"%s (open at %s)" % [at, "max" if use_max else "min"]
						)
					assert_true(_warmup_ok(plan), "%s: first 300 s within 4.6.8" % at)


func _min_switch_gap(plan: EffortPlan, use_max: bool) -> float:
	var t := 0.0
	var last_switch := -INF
	var gap := INF
	var mode := ""
	for i in plan.size():
		var ph := plan.phase(i)
		if mode != "" and ph.mode != mode:
			gap = minf(gap, t - last_switch)
			last_switch = t
		mode = ph.mode
		t += (ph.max_s if use_max else ph.min_s) if ph.open_ended else ph.duration_s
	return gap


func _warmup_ok(plan: EffortPlan) -> bool:
	var t := 0.0
	for i in plan.size():
		var ph := plan.phase(i)
		if t < 300.0 and ph.mode == Wl.ERG:
			var r := ph.effective_range()
			if ph.target_pct > 65.0 or float(r[1]) > 65.0:
				return false
		t += ph.min_s if ph.open_ended else ph.duration_s
	return true


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


## Zero input (brief 0.4): a solo Bulwark plays Ashfall Road to the results; every open phase
## ends by end_phase, the boss last, and the mission is won.
func test_a_solo_bulwark_plays_ashfall_road_to_the_results_with_zero_input() -> void:
	var r := _run(["--content=ashfall_road", "--players=1", "--rider=erg", "--seed=1"])
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("finished_reason"), TankIds.OUTCOME_VICTORY)
	var hist: Array = r["phases"]["1"]
	assert_eq(hist.size(), 12, "11 segments and the cool-down")
	for ph: Dictionary in hist:
		if str(ph["kind"]) == Wl.WORK:
			assert_eq(ph["ended_by"], Wl.ENDED_END_PHASE, "phase %d" % int(ph["index"]))
