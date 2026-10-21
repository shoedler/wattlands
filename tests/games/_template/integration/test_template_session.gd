extends GutTest
## The game through the real platform runtime: GameRegistry, PlanValidator and GameSimRunner
## (sdk-runtime) on top of the trainer stack.

const F := preload("res://tests/games/_template/template_fakes.gd")

var _dirs: Array[String] = []
## Runners made by a test: cleanup() deletes each one's temp root (W3 QT-4).
var _runners: Array[GameSimRunner] = []


func before_each() -> void:
	var d := Paths.make_temp_dir("template_session")
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
		for offset: int in [-10, 0, 5]:
			var ctx := F.make_ctx(1, 1, content_id)
			ctx.players[0].options["work_offset"] = offset
			var game: TemplateGame = autofree(F.make_game(ctx))
			for peer: int in [1, -1]:
				var plan: EffortPlan = game.build_effort_plans()[peer]
				var v := PlanValidator.validate(plan)
				assert_true(v["ok"], "%s %d: %s" % [content_id, offset, v["errors"]])
				assert_eq(v["warnings"], [], "%s %d" % [content_id, offset])
				var final := PlanValidator.finalize(plan)
				assert_eq(final.size(), plan.size() + 1)
				assert_eq(final.phase(final.size() - 1).kind, Wl.COOLDOWN)


func _run(flags: Array[String]) -> Dictionary:
	var report := _dirs[0].path_join("report.json")
	var args := PackedStringArray(["--game=" + F.GAME_ID, "--report=" + report, "--sim-speed=1000"] + flags)
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


func test_a_solo_run_with_a_bot_completes_and_writes_one_fit() -> void:
	var r := _run(["--content=default", "--players=1", "--bots=1", "--rider=erg", "--seed=3"])
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("end_reason"), "complete")
	assert_true(FileAccess.file_exists(r["_path"]))
	assert_eq((r.get("fit_paths", []) as Array).size(), 1, "one FIT per human slot, none for bots")
	assert_eq(r.get("finished_reason"), "complete")
	for d: Dictionary in r.get("directives", []):
		var req: Dictionary = d.get("requested", {})
		if req.get("reason") == "hill":
			var keys: Array = req.keys().filter(func(k: Variant) -> bool: return k != "id")
			keys.sort()
			assert_eq(keys, ["duration_s", "reason", "source", "target_pct"], "exactly the game's fields: %s" % req)


func test_a_host_run_with_two_humans_completes() -> void:
	var r := _run(["--content=short", "--players=2", "--bots=0", "--rider=erg", "--seed=5"])
	assert_eq(r["_end"], "complete")
	assert_eq((r.get("fit_paths", []) as Array).size(), 2)
