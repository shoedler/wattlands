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
			assert_eq(
				keys,
				["duration_s", "reason", "source", "target_pct"],
				"the game's fields (id aside): %s" % req
			)


func test_a_host_run_with_two_humans_completes() -> void:
	var r := _run(["--content=short", "--players=2", "--bots=0", "--rider=erg", "--seed=5"])
	assert_eq(r["_end"], "complete")
	assert_eq((r.get("fit_paths", []) as Array).size(), 2)
	# W3 SDK-7: through the real platform, "short" replans every rider to an open-ended Finish that
	# end_phase ends, and its SIM phase takes the game's course grades; nothing is refused.
	for peer: String in ["1", "2"]:
		var hist: Array = r["phases"][peer]
		assert_eq(
			hist[2]["label"], "_TEMPLATE_PHASE_FINISH", "peer %s rode the replanned phase" % peer
		)
		assert_eq(hist[2]["ended_by"], Wl.ENDED_END_PHASE, "peer %s: end_phase ended it" % peer)
	var kinds := {}
	for d: Dictionary in r.get("directives", []):
		assert_true(bool(d["accepted"]), "accepted: %s" % JSON.stringify(d))
		kinds[d["kind"]] = int(kinds.get(d["kind"], 0)) + 1
	for kind: String in ["course_grade", "replan", "end_phase", "request", "cadence_band"]:
		assert_gt(int(kinds.get(kind, 0)), 0, "the report has %s directives" % kind)


## W4r2 R12 through the platform (the review's run): after "short"'s open-ended Finish the riders
## reach the cool-down at different times. Every human rider gets each phase banner on its own peer
## when its own phase starts, nothing goes to every peer, and the game's phase_changed for the
## cool-down comes once the last rider got there.
func test_short_with_three_riders_banners_each_riders_own_phases() -> void:
	var r := _run(
		[
			"--content=short",
			"--players=3",
			"--bots=1",
			"--rider=erg",
			"--rider=erg:compliance=0.85",
			"--rider=zero",
			"--seed=9"
		]
	)
	assert_eq(r["_end"], "complete")
	var starts := {}
	var banners: Array = []
	var group: Array = []
	for e: Dictionary in r.get("events", []):
		match str(e.get("type", "")):
			"phase_started":
				var peer := int(e["peer"])
				if peer > 0:
					if not starts.has(peer):
						starts[peer] = []
					(starts[peer] as Array).append([int(e["index"]), float(e["t"])])
			"hud":
				if (
					str(e.get("kind", "")) == "banner"
					and str(e.get("key", "")) == "_TEMPLATE_BANNER_PHASE"
				):
					banners.append([int(e["peer"]), float(e["t"])])
			"game_phase_changed":
				group.append([int(e["index"]), float(e["t"])])
	assert_eq(starts.keys().size(), 3, "three human riders")
	assert_eq(
		banners.filter(func(b: Array) -> bool: return b[0] == 0), [], "no banner to every peer"
	)
	var last_cool := 0.0
	for peer: int in starts.keys():
		var mine := banners.filter(func(b: Array) -> bool: return b[0] == peer)
		assert_eq(
			mine.size(),
			(starts[peer] as Array).size(),
			"peer %d: one banner per phase it started" % peer
		)
		for i in mine.size():
			var st: Array = starts[peer][i]
			assert_between(
				float(mine[i][1]),
				float(st[1]),
				float(st[1]) + 0.11,
				"peer %d: phase %d's banner when it starts" % [peer, int(st[0])]
			)
		last_cool = maxf(last_cool, float((starts[peer] as Array).back()[1]))
	var cool := group.filter(func(g: Array) -> bool: return g[0] == 3)
	assert_eq(cool.size(), 1, "one phase_changed for the cool-down")
	if cool.size() == 1:
		assert_gte(float(cool[0][1]), last_cool, "after the last rider reached it")
	var ends := []
	for peer: int in starts.keys():
		ends.append(snappedf(float((starts[peer] as Array).back()[1]), 0.05))
	assert_ne(
		ends.min(), ends.max(), "precondition: the riders reached the cool-down at different times"
	)
