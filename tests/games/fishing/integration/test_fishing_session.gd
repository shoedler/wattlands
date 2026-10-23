extends GutTest
## The game through the real platform runtime: GameRegistry, PlanValidator and GameSimRunner
## (sdk-runtime) on top of the trainer stack.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")

var _dirs: Array[String] = []
## Runners made by a test: cleanup() deletes each one's temp root (W3 QT-4).
var _runners: Array[GameSimRunner] = []


func before_each() -> void:
	var d := Paths.make_temp_dir("fishing_session")
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


## The installed games, plus the template itself (never listed, so the GameRegistry autoload
## does not know it; the conformance test loads it the same way).
func _registry() -> WlGameRegistry:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	add_child_autofree(reg)
	reg.scan()
	if not _is_scaffolded_game():
		assert_eq(reg.add_game(F.manifest(), F.GAME_DIR, true), "")
	return reg


## The template is never listed; a game scaffolded from it must be. (The literal is split so
## tools/new_game leaves it alone.)
func _is_scaffolded_game() -> bool:
	return F.GAME_ID != "_tem" + "plate"


func test_the_manifest_validates_and_the_listing_rule_holds() -> void:
	var reg := WlGameRegistry.new()
	add_child_autofree(reg)
	reg.scan()
	assert_eq(reg.validate_manifest(F.manifest(), F.GAME_DIR.path_join("game.json")), "")
	assert_eq(reg.has_game(F.GAME_ID), _is_scaffolded_game())


func test_every_plan_passes_the_plan_validator_without_warnings() -> void:
	for content_id: String in F.manifest()["contents"]:
		for reel: int in [50, 60, 70]:
			var ctx := F.make_ctx(2, 0, content_id)
			for p in ctx.players:
				p.options["reel_pct"] = reel
			var game: FishingGame = autofree(F.make_game(ctx))
			for peer: int in [1, 2]:
				var plan: EffortPlan = game.build_effort_plans()[peer]
				var v := PlanValidator.validate(plan)
				assert_true(v["ok"], "%s %d: %s" % [content_id, reel, v["errors"]])
				assert_eq(v["warnings"], [], "%s %d" % [content_id, reel])
				var final := PlanValidator.finalize(plan)
				assert_eq(final.size(), plan.size() + 1)
				assert_eq(final.phase(final.size() - 1).kind, Wl.COOLDOWN)


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


func test_a_solo_e2e_run_completes_and_writes_one_fit() -> void:
	var r := _run(["--content=e2e_2min", "--players=1", "--rider=erg:compliance=1.0", "--seed=3"])
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("end_reason"), "complete")
	assert_true(FileAccess.file_exists(r["_path"]))
	assert_eq((r.get("fit_paths", []) as Array).size(), 1, "one FIT per human slot")
	assert_eq(r.get("plan_warnings", {}).get("1", []), [], "no plan warnings")


func test_a_host_e2e_run_with_two_humans_completes() -> void:
	var r := _run(["--content=e2e_2min", "--players=2", "--rider=erg:compliance=1.0", "--seed=5"])
	assert_eq(r["_end"], "complete")
	assert_eq((r.get("fit_paths", []) as Array).size(), 2)
	for d: Dictionary in r.get("directives", []):
		if d["kind"] == "request":
			assert_true(bool(d["accepted"]), "accepted: %s" % JSON.stringify(d))
