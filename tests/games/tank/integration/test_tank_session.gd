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


## Zero input (brief 0.4): a solo rider plays Ashfall Road to the results with a mission outcome,
## seated by the solo loop (v3: every seat move a replan the platform accepts with no warning, the
## rest of a segment a lap-false phase of its own); every WORK phase ends by end_phase or at max_s
## (whether the crew wins without an overrun is T1, a balance gate), every other by its duration.
func test_a_solo_rider_plays_ashfall_road_to_the_results_with_zero_input() -> void:
	var r := _run(["--content=ashfall_road", "--players=1", "--rider=erg", "--seed=1"])
	assert_eq(r["_end"], "complete")
	assert_has([TankIds.OUTCOME_VICTORY, TankIds.OUTCOME_WITHDRAWN], r.get("finished_reason"))
	var hist: Array = r["phases"]["1"]
	var plan: Array = r["plans"]["1"]["phases"]
	var laps := 0
	for ph: Variant in plan:
		laps += 1 if bool(ph.get("lap", false)) else 0
	assert_eq(laps, 12, "11 segments and the cool-down are the laps")
	assert_gt(hist.size(), 12, "the solo loop split segments")
	assert_eq(r.get("plan_warnings", {}).get("1", []), [], "no switch warning")
	var seats := _tank_events(r.get("events", [])).filter(
		func(e: Dictionary) -> bool: return str(e["type"]) == "seat"
	)
	assert_gt(seats.size(), 2, "the solo rider moved seats")
	for ph: Dictionary in hist:
		var at := "phase %d" % int(ph["index"])
		if str(ph["kind"]) == Wl.WORK:
			assert_has([Wl.ENDED_END_PHASE, Wl.ENDED_MAX_S], ph["ended_by"], at)
		elif str(ph["kind"]) != Wl.COOLDOWN:
			assert_eq(ph["ended_by"], Wl.ENDED_DURATION, at)


## The Tank game events of a report entry list, in order.
func _tank_events(entries: Array) -> Array:
	var out: Array = []
	for e: Variant in entries:
		if e is Dictionary and str(e.get("type", "")) == "game_event":
			out.append((e as Dictionary)["event"])
	return out


func _all_whole_numbers(node: Variant) -> bool:
	if node is Array:
		for x: Variant in node:
			if not _all_whole_numbers(x):
				return false
	elif node is Dictionary:
		for k: Variant in node:
			if str(k) != "type" and not _all_whole_numbers(node[k]):
				return false
	elif node is float:
		return is_equal_approx(float(node), roundf(float(node)))
	return true


## The e2e story in process: a host and two loopback clients play the drill as the Citadel. Every
## client applies the same Tank events in the same order as the host sent them, whole numbers all,
## the snapshots stay small, and every peer's apply_progress ran.
func test_a_host_drill_with_three_humans_keeps_every_client_in_step() -> void:
	var r := _run(["--content=drill", "--players=3", "--rider=erg", "--seed=2"])
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("finished_reason"), TankIds.OUTCOME_COMPLETE)
	assert_eq(int(r.get("oversize_snapshots", -1)), 0)
	assert_lte(int(r.get("max_snapshot_bytes", 99999)), TankConst.SNAPSHOT_MAX_BYTES)
	assert_gt(int(r.get("max_snapshot_bytes", 0)), 100, "a real snapshot, not an empty one")
	var host_events := _tank_events(r["events"])
	assert_gte(host_events.size(), 3, "the segments at least")
	var segs: Array = host_events.filter(func(e: Dictionary) -> bool: return e["type"] == "segment")
	assert_eq(segs.map(func(e: Dictionary) -> int: return int(e["i"])), [0, 1, 2, 3])
	var clients: Array = r["clients"]
	assert_eq(clients.size(), 2)
	for c: Dictionary in clients:
		var seen := _tank_events(c["events"])
		assert_eq(seen.size(), host_events.size(), "client %d" % int(c["peer"]))
		for i in seen.size():
			assert_eq(
				JSON.stringify(seen[i], "", true),
				JSON.stringify(host_events[i], "", true),
				"event %d" % i
			)
		assert_true(
			_all_whole_numbers(seen), "client %d: the numbers arrive as ints" % int(c["peer"])
		)
		assert_eq(c["results_grade"], r["results"]["grade"], "the results reach every client")
	for peer in ["1", "2", "3"]:
		assert_true((r["unlocks"] as Dictionary).has(peer), "apply_progress ran on peer %s" % peer)
		assert_has(r["unlocks"][peer], "soot", "a finished drill")


## Prompts and banners go to one peer, the host's own rider (ctx.local_peer), never to everyone.
func test_the_hosts_toasts_and_banners_are_for_the_host_only() -> void:
	var r := _run(["--content=drill", "--players=3", "--rider=erg", "--seed=4"])
	var seen := 0
	for e: Dictionary in r["events"]:
		if str(e.get("type", "")) == "hud" and ["toast", "banner"].has(str(e.get("kind", ""))):
			seen += 1
			assert_eq(int(e["peer"]), 1, "%s %s" % [e["kind"], e["key"]])
	assert_gt(seen, 0, "the segment banners at least")


## A human without the Autopilot flag is on the module's fallback: it plays the drill to the end.
func test_a_solo_drill_with_autopilot_off_still_completes() -> void:
	var r := _run(["--content=drill", "--players=1", "--autopilot=none", "--rider=erg", "--seed=6"])
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("finished_reason"), TankIds.OUTCOME_COMPLETE)


func test_the_same_seed_gives_the_same_report_hash() -> void:
	var a := _run(["--content=drill", "--players=2", "--rider=erg", "--seed=9"])
	var path_a := str(a["_path"])
	assert_ne(path_a, "")
	var hash_a := str(a["deterministic_hash"])
	for run: GameSimRunner in _runners:
		run.cleanup()
	_runners.clear()
	var b := _run(["--content=drill", "--players=2", "--rider=erg", "--seed=9"])
	assert_eq(str(b["deterministic_hash"]), hash_a, "events and snapshots repeat")


## Zero input: the Ashfall Road report's segment events come once each in order, the snapshots stay
## under the budget all the way, and the platform wrote the ride.
func test_the_solo_ashfall_road_keeps_its_snapshots_small_and_its_segments_in_order() -> void:
	var r := _run(["--content=ashfall_road", "--players=1", "--rider=erg", "--seed=2"])
	assert_eq(r["_end"], "complete")
	assert_eq(int(r.get("oversize_snapshots", -1)), 0)
	assert_lte(int(r.get("max_snapshot_bytes", 99999)), TankConst.SNAPSHOT_MAX_BYTES)
	var idx: Array = []
	for e: Dictionary in _tank_events(r["events"]):
		if e["type"] == "segment":
			idx.append(int(e["i"]))
	assert_eq(idx.slice(0, 11), range(11), "the eleven segments, once each, in order")
	assert_eq((r.get("fit_paths", []) as Array).size(), 1)
	assert_true(FileAccess.file_exists(str((r["fit_paths"] as Array)[0])), "the ride was written")


## Four riders (brief 2.2, 2.5): a crew of 4 plays the drill as a host with three loopback clients
## to the results, every peer's last snapshot carries 4 riders and 6 rooms within 4 KB, and the
## drill stays inside the warm-up limits (no ERG above 65%, nothing refused).
func test_a_host_drill_with_four_humans_completes() -> void:
	var r := _run(["--content=drill", "--players=4", "--rider=erg", "--seed=4"])
	assert_eq(r["_end"], "complete")
	assert_eq(r.get("finished_reason"), TankIds.OUTCOME_COMPLETE)
	assert_eq((r.get("fit_paths", []) as Array).size(), 4)
	assert_eq(int(r.get("oversize_snapshots", -1)), 0)
	assert_lte(int(r.get("max_snapshot_bytes", 99999)), TankConst.SNAPSHOT_MAX_BYTES)
	for d: Dictionary in r.get("directives", []):
		assert_true(bool(d["accepted"]), "accepted: %s" % JSON.stringify(d))
	for peer: String in r["trace"]:
		for row: Dictionary in r["trace"][peer]:
			if str(row.get("mode", "")) == Wl.ERG:
				assert_lte(float(row["applied_pct"]), 65.0 + 0.6, "warm-up ERG, peer %s" % peer)


## Zero input with four riders: the crew of 4 plays Ashfall Road to the results (a mission outcome),
## every WORK phase ending by end_phase or at max_s.
func test_a_host_crew_of_4_plays_ashfall_road_to_the_results_with_zero_input() -> void:
	var r := _run(["--content=ashfall_road", "--players=4", "--rider=erg", "--seed=1"])
	assert_eq(r["_end"], "complete")
	assert_has([TankIds.OUTCOME_VICTORY, TankIds.OUTCOME_WITHDRAWN], r.get("finished_reason"))
	# v3: a seat move splits a segment into plan phases; count the segments they belong to.
	var plan: Array = r["plans"]["4"]["phases"]
	var segs := {}
	for sp: Dictionary in r["phases"]["4"]:
		var meta: Dictionary = (plan[int(sp["index"])] as Dictionary).get("meta", {})
		segs[int(meta.get("segment", -1))] = true
	assert_eq(segs.size(), 12, "11 segments and the cool-down")
	assert_lte(int(r.get("max_snapshot_bytes", 99999)), TankConst.SNAPSHOT_MAX_BYTES)
	var arc := 0
	for d: Dictionary in r.get("directives", []):
		if d["kind"] == "request" and str(d["requested"].get("reason", "")) == "arc":
			arc += 1
	assert_gt(arc, 0, "the arc generator's load pattern ran")


## Brief section 4, S10: a client's own `aim` (a key on the client: the up action) reaches the host
## over Telemetry.intents, owned by its engine (the drill's dynamo, slot 1), and the host's rules
## apply it: the elevation target moves and the auto-aim pauses; the deliberate intent ends that
## rider's Autopilot fallback. Headless sims cannot press keys, so this is the network proof for
## aim.
func test_a_clients_aim_intent_is_applied_by_the_host() -> void:
	var report := _dirs[0].path_join("aim.json")
	var parsed := GameSimRunner.parse_args(
		PackedStringArray(
			[
				"--game=" + F.GAME_ID,
				"--report=" + report,
				"--content=drill",
				"--players=2",
				"--rider=erg",
				"--seed=6"
			]
		)
	)
	parsed["headless"] = true
	parsed["registry"] = _registry()
	var runner := GameSimRunner.new()
	add_child_autofree(runner)
	_runners.append(runner)
	assert_eq(runner.setup(parsed), "")
	var host_game := runner.host.game as TankGame
	for _i in 200:
		runner.step()
	var dyn := host_game.state.station(TankIds.ENGINE_DYNAMO)
	assert_eq(dyn.peer, 2, "the client works the dynamo")
	assert_true(host_game.state.rider(2).fallback, "no deliberate intent yet")
	var before := host_game.state.hull.elev_target_deg
	runner.clients[0].inject_action(&"up")
	var seen := false
	for _i in 60:
		runner.step()
		if host_game.state.hull.aim_pause_s > 0.0:
			seen = true
			break
	assert_true(seen, "the host applied the client's aim intent (auto-aim paused)")
	assert_ne(host_game.state.hull.elev_target_deg, before, "the elevation target moved")
	assert_false(host_game.state.rider(2).fallback, "a deliberate intent ends the fallback")
