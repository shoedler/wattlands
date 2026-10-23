extends GutTest
## The game through the real platform runtime: GameRegistry, PlanValidator and GameSimRunner
## (sdk-runtime) on top of the trainer stack.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")

var _dirs: Array[String] = []
## Runners made by a test: cleanup() deletes each one's temp root (W3 QT-4).
var _runners: Array[GameSimRunner] = []
## The last runner _run made (its hosts stay alive until after_each).
var _runner: GameSimRunner = null
## Event types each peer's fx_event raised in the last run, by local peer (connected after setup).
var _fx: Dictionary = {}


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
		for reel: int in range(FishingConst.REEL_PCT_MIN, FishingConst.REEL_PCT_MAX + 1, 5):
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


func _run(flags: Array[String], name: String = "report") -> Dictionary:
	var report := _dirs[0].path_join(name + ".json")
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
	_runner = runner
	assert_eq(runner.setup(parsed), "")
	_fx = {}
	# A client configures from the host's session_start on its first steps: step until every
	# peer has its FishingGame (the ride out sends no events), then watch each one's fx_event.
	var waited := 0
	while waited < 200 and runner.hosts().any(_no_game):
		runner.step()
		waited += 1
	for gh in runner.hosts():
		var g := gh.game as FishingGame
		assert_not_null(g, "every peer runs FishingGame")
		if g != null:
			_fx[gh.ctx.local_peer] = []
			g.fx_event.connect(_on_fx.bind(gh.ctx.local_peer))
	var reason := runner.run_to_end()
	var out := runner.build_report()
	out["_end"] = reason
	out["_path"] = runner.write_report()
	return out


func _no_game(gh: GameHost) -> bool:
	return gh.game == null


func _on_fx(e: Dictionary, peer: int) -> void:
	(_fx[peer] as Array).append(str(e.get("type", "")))


func test_a_solo_e2e_run_completes_and_writes_one_fit() -> void:
	var r := _run(["--content=e2e_2min", "--players=1", "--rider=erg:compliance=1.0", "--seed=3"])
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("end_reason"), "complete")
	assert_true(FileAccess.file_exists(r["_path"]))
	assert_eq((r.get("fit_paths", []) as Array).size(), 1, "one FIT per human slot")
	assert_eq(r.get("plan_warnings", {}).get("1", []), [], "no plan warnings")
	assert_gt(int(r["max_snapshot_bytes"]), 0, "a recording SOLO run measures snapshots")
	assert_lte(int(r["max_snapshot_bytes"]), FishingConst.SNAPSHOT_MAX_BYTES)
	assert_eq(int(r["oversize_snapshots"]), 0)
	assert_ne(str(r.get("results", {}).get("grade", "")), "", "results were built")


func test_a_host_e2e_run_with_two_humans_completes() -> void:
	var r := _run(["--content=e2e_2min", "--players=2", "--rider=erg:compliance=1.0", "--seed=5"])
	assert_eq(r["_end"], "complete")
	assert_eq((r.get("fit_paths", []) as Array).size(), 2)
	for d: Dictionary in r.get("directives", []):
		if d["kind"] == "request":
			assert_true(bool(d["accepted"]), "accepted: %s" % JSON.stringify(d))
	assert_lte(int(r["max_snapshot_bytes"]), FishingConst.SNAPSHOT_MAX_BYTES)


func test_the_client_follows_the_host_through_snapshots_and_events() -> void:
	var r := _run(["--content=e2e_2min", "--players=2", "--rider=erg:compliance=1.0", "--seed=9"])
	assert_eq(r["_end"], "complete")
	assert_eq(_runner.clients.size(), 1)
	var host := _runner.host.game as FishingGame
	var client := _runner.clients[0].game as FishingGame
	assert_gt(client.state.tick, 0, "snapshots were applied")
	assert_false(client.history.is_empty(), "and pushed to the interpolation history")
	assert_lte(host.state.tick - client.state.tick, 2 * Wl.SIM_HZ, "close behind the host")
	for i in host.state.lanes.size():
		assert_eq(client.state.lanes[i].phase_index, host.state.lanes[i].phase_index)
		assert_eq(client.state.lanes[i].state, host.state.lanes[i].state)
	assert_eq(client.state.team_points, host.state.team_points)
	assert_eq(_fx[2], _fx[1], "the client raised every event the host sent, in order")
	var c: Dictionary = (r["clients"] as Array)[0]
	assert_eq(c["results_grade"], r["results"]["grade"], "the client got the host's results")


func test_the_same_seed_gives_the_same_deterministic_hash() -> void:
	var flags: Array[String] = [
		"--content=e2e_2min", "--players=1", "--rider=erg:compliance=1.0", "--seed=11"
	]
	var a := _run(flags, "a")
	var b := _run(flags, "b")
	assert_eq(a["_end"], "complete")
	assert_ne(str(a["deterministic_hash"]), "")
	assert_eq(a["deterministic_hash"], b["deterministic_hash"])
	assert_eq(a["snapshots"], b["snapshots"], "every snapshot's size and hash repeat")
