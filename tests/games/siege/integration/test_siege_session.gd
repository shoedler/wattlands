extends TestGameSessionSuite
## Siege through the real platform runtime: GameRegistry, PlanValidator and GameSimRunner on top
## of the trainer stack (drill SOLO with a bot, drill as HOST with a loopback client).

const F := preload("res://tests/games/siege/siege_fakes.gd")


func test_the_manifest_validates_and_siege_is_listed() -> void:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	add_child_autofree(reg)
	reg.scan()
	assert_eq(reg.validate_manifest(F.manifest(), F.GAME_DIR.path_join("game.json")), "")
	assert_true(reg.has_game(F.GAME_ID))


func test_every_module_plan_passes_the_plan_validator_without_warnings() -> void:
	for content_id: String in F.manifest()["contents"]:
		for offset: int in [-10, 0, 5]:
			var ctx := F.make_ctx(1, 1, content_id)
			ctx.players[0].options["wave_offset"] = offset
			var game := F.make_game(ctx)
			var plans := game.build_effort_plans()
			assert_eq(plans.size(), 2)
			for peer: int in [1, -1]:
				var plan: EffortPlan = plans[peer]
				var v := PlanValidator.validate(plan)
				assert_true(v["ok"], "%s %d: %s" % [content_id, offset, v["errors"]])
				assert_eq(v["warnings"], [], "%s %d" % [content_id, offset])
				var final := PlanValidator.finalize(plan)
				assert_eq(final.size(), plan.size() + 1)
				assert_eq(final.phase(final.size() - 1).kind, Wl.COOLDOWN)
			F.free_game(game)


func _run(flags: Array[String]) -> Dictionary:
	return run_session(F.GAME_ID, flags)


func _events(r: Dictionary, type: String) -> Array:
	return (r.get("events", []) as Array).filter(
		func(e: Dictionary) -> bool: return e["type"] == type
	)


func test_a_solo_drill_with_a_bot_completes() -> void:
	var r := _run(
		["--content=drill", "--players=1", "--bots=1", "--rider=erg:compliance=1.0", "--seed=1"]
	)
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("finished_reason"), "complete")
	assert_eq((r.get("fit_paths", []) as Array).size(), 1, "one FIT per human slot, none for bots")
	assert_eq(r.get("plan_warnings", {}).get("1", []), [])
	var changed := _events(r, "game_phase_changed").map(
		func(e: Dictionary) -> int: return int(e["index"])
	)
	assert_eq(changed, [0, 1, 2], "phase_changed once per phase, the cool-down included")
	assert_eq(_events(r, "lap_marker"), [], "laps come from lap: true only")
	var game_events := _events(r, "game_event").map(
		func(e: Dictionary) -> String: return str(e["event"]["type"])
	)
	assert_eq(game_events.count(SiegeIds.EV_WAVE_START), 1, "the drill's wave 1")
	assert_eq(game_events.count(SiegeIds.EV_WAVE_END), 1)
	var requests: Array = r.get("directives", []).filter(
		func(d: Dictionary) -> bool: return str(d["kind"]) != "cadence_band"
	)
	assert_eq(requests, [], "no load directive in the drill (WARMUP kind: no Overdrive)")
	assert_true(["S", "A", "B", "C", "D"].has(str(r["results"]["grade"])))
	assert_gt(int(r.get("max_snapshot_bytes", 0)), 0)
	assert_lte(int(r.get("max_snapshot_bytes", 0)), SiegeSnapshotSchema.MAX_BYTES)


func test_a_host_drill_with_two_humans_completes() -> void:
	var r := _run(
		["--content=drill", "--players=2", "--bots=1", "--rider=erg:compliance=1.0", "--seed=5"]
	)
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("role"), Wl.HOST)
	assert_eq((r.get("fit_paths", []) as Array).size(), 2)
	assert_eq(r.get("finished_reason"), "complete")
	for c: Dictionary in r.get("clients", []):
		assert_ne(str(c.get("results_grade", "")), "", "the client got the results")
