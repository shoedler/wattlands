extends GutTest
## GameHost in SOLO (BRIEF 3.6, 4.1, 4.6.4; BRIEF 7.1 "early finished", "the cool-down
## view", "phase_started per rider with differing plans"; docs/OWNERSHIP.md GM2-GM8, GM14,
## GM16, GM18-GM22, CTX1-CTX17, IF1-IF3, PL12, DS10). Riders are fake LocalRiders.

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")

## "tiny": 2 s + 3 s + 30 s SIM + open-ended 2..6 s, then the 180 s cool-down.
const TINY_TICKS := 820
const COOLDOWN_TICKS := 3600

var _root: Node = null
var _tmp: Array[String] = []


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)


func after_each() -> void:
	for d in _tmp:
		Kit.remove_tree(d)
	_tmp.clear()


func _solo(content: String = "tiny", extra: Dictionary = {}, bots: int = 0, game_id: String = "fx_solo") -> Dictionary:
	var b := Kit.solo(_root, content, extra, bots, game_id)
	_tmp.append(str(b["tmp"]))
	return b


func _host(b: Dictionary) -> GameHost:
	return b["host"]


func _game(b: Dictionary) -> GameModule:
	return (b["host"] as GameHost).game


func _rider(b: Dictionary, peer: int = 1) -> LocalRider:
	return b["riders"][peer]


## game-workout W1: a content id "<scheme>:<value>" passes through to ctx.content_id when
## the game lists the scheme in content_schemes; any other id outside `contents` is refused.
func test_a_listed_content_scheme_passes_the_content_id_through() -> void:
	var m := Kit.registry(_root).manifest("fx_solo").duplicate(true)
	m["content_schemes"] = ["zwo"]
	var b := _solo("zwo:C:/rides/my.zwo", {"manifest": m})
	assert_eq(b["err"], "")
	assert_eq(_host(b).ctx.content_id, "zwo:C:/rides/my.zwo")
	assert_string_starts_with(str(_solo("url:x", {"manifest": m})["err"]), "content_id:")
	assert_string_starts_with(str(_solo("zwo:C:/rides/my.zwo")["err"]), "content_id:", "fx_solo lists no scheme")


func test_setup_errors_name_the_problem() -> void:
	assert_string_starts_with(str(_solo("tiny", {"game_id": "nope"})["err"]), "game_id:")
	assert_string_starts_with(str(_solo("zzz")["err"]), "content_id:")
	assert_string_starts_with(str(_solo("tiny", {"local_peer": 5})["err"]), "local_peer:")
	assert_string_starts_with(str(_solo("tiny", {"role": "PEER"})["err"]), "role:")
	assert_string_starts_with(str(_solo("tiny", {"role": Wl.HOST})["err"]), "net:")


func test_a_rejected_plan_blocks_the_start_with_its_reason() -> void:
	var b := _solo("bad")
	assert_string_starts_with(str(b["err"]), "plan for peer 1")
	assert_string_contains(str(b["err"]), "65%")
	_host(b).start()
	assert_push_warning("needs a successful setup")
	assert_eq(_host(b).state, "setup")


func test_ctx_fields() -> void:
	var b := _solo("tiny", {"options": {"speed": 4}, "content_overrides": {"levels.json": {"speed_scale": 3}}}, 1)
	assert_eq(b["err"], "")
	var ctx := _host(b).ctx
	assert_eq(ctx.game_id, "fx_solo")
	assert_eq(str(ctx.manifest["title"]), "Fixture Solo")
	assert_eq(ctx.players.size(), 2)
	assert_eq(ctx.players[0].peer_id, 1)
	assert_eq(ctx.players[1].peer_id, -1, "bots after humans")
	assert_eq(ctx.content_id, "tiny")
	assert_eq(ctx.seed, 7)
	assert_eq(ctx.role, Wl.SOLO)
	assert_true(ctx.is_authority())
	assert_eq(ctx.local_peer, 1)
	assert_eq(ctx.local_player().name, "Rider 1")
	assert_eq(ctx.rng.seed, 7)
	assert_true(ctx.directives is DirectiveRouter)
	assert_eq(ctx.options, {"speed": 4, "mirror": false, "mode": "a"}, "defaults filled in")
	assert_eq(ctx.players[0].options, {"offset": 0, "reel_pct": 60, "relaxed": false})
	assert_eq(ctx.players[1].options, {"offset": 0, "reel_pct": 60, "relaxed": false}, "bots get defaults")
	assert_true(ctx.hud is HudRouter)
	assert_true(ctx.intents is IntentRouter)
	assert_true(ctx.stats is SessionStatsTracker)
	assert_eq(ctx.roster, {})
	assert_not_null(ctx.strings)
	assert_eq(ctx.strings.t("FX_SOLO_TITLE"), "Fixture solo", "the registry loaded the game's strings")
	assert_eq(ctx.events, b["bus"])
	assert_eq(ctx.scaling_mode, Wl.FAIR_FTP)
	assert_eq(ctx.game_dir, Kit.FIXTURES.path_join("runtime/fx_solo"))
	assert_eq(ctx.content_dir, Kit.FIXTURES.path_join("_content/fx_solo"))
	assert_eq(ctx.assets_dir, WlGameRegistry.ASSETS_ROOT.path_join("fx_solo"))
	assert_eq(ctx.player(-1).name, "Bot 1")
	assert_eq(ctx.peers(), [1, -1] as Array[int])
	assert_eq(ctx.content_overrides, {"levels.json": {"speed_scale": 3}})
	assert_eq(ctx.progress.game_id, "fx_solo")
	assert_string_contains(ctx.progress.path, "p1/games/fx_solo/progress.json")
	assert_eq(_game(b).get("configure_count"), 1)
	var content: Variant = _game(b).get("content")
	assert_eq(float(content["speed_scale"]), 3.0, "load_content_json honours content_overrides")


func test_bot_plans_are_built_and_finalized() -> void:
	var b := _solo("tiny", {}, 2)
	var host := _host(b)
	for peer: int in [1, -1, -2]:
		assert_true(host.plans.has(peer))
		assert_true((host.plans[peer] as EffortPlan).cooldown_appended)
	assert_eq(host.plan_warnings[1], [])


func test_start_enters_phase_zero_and_emits_phase_started() -> void:
	var b := _solo("tiny", {}, 1)
	var got: Array = []
	(b["bus"] as WlEventBus).phase_started.connect(func(peer: int, index: int) -> void: got.append([peer, index]))
	_host(b).start()
	assert_eq(got, [[1, 0], [-1, 0]])
	assert_eq(_rider(b).get("phases_started"), [0] as Array[int])
	assert_eq((_rider(b).get("plans_set") as Array).size(), 1)
	assert_eq(_host(b).state, "running")


func test_sim_step_gets_a_constant_dt_and_every_slot() -> void:
	var b := _solo("tiny", {}, 1)
	var game := _game(b)
	game.set("keep_frames", true)
	_host(b).start()
	Kit.step(b, 30)
	assert_eq(game.get("steps"), 30)
	for dt: float in game.get("dts"):
		assert_eq(dt, Wl.SIM_DT)
	var frames: Array = game.get("frames_seen")
	assert_eq(int(frames[0]["tick"]), 0)
	assert_eq(float(frames[0]["t"]), 0.0)
	assert_eq(int(frames[29]["tick"]), 29)
	assert_almost_eq(float(frames[29]["t"]), 1.45, 1e-9)
	var players: Dictionary = frames[5]["players"]
	assert_eq(players.keys(), [1, -1])
	var tm: Telemetry = players[1]
	assert_true(tm.connected)
	assert_eq(tm.age_s, 0.0)
	assert_eq(tm.peer_id, 1)
	var ps: PhaseState = (frames[5]["phase"] as Dictionary)[1]
	assert_eq(ps.index, 0)
	assert_almost_eq(ps.elapsed_s, 0.25, 1e-9)


func test_phases_per_rider_with_differing_plans() -> void:
	var b := _solo("split", {}, 1)
	var got: Array = []
	(b["bus"] as WlEventBus).phase_started.connect(func(peer: int, index: int) -> void: got.append([peer, index, _host(b).clock.game_tick]))
	_host(b).start()
	Kit.step(b, 200)
	# Rider 1 (slot 0): 2 s, 3 s, ...; the bot (slot 1): 4 s, 3 s, then the cool-down.
	assert_eq(got[0], [1, 0, 0])
	assert_eq(got[1], [-1, 0, 0])
	assert_has(got, [1, 1, 39], "rider 1's second phase starts at tick 40 (the change is emitted at the end of tick 39)")
	assert_has(got, [-1, 1, 79])
	assert_has(got, [1, 2, 99])
	assert_has(got, [-1, 2, 139], "the bot's cool-down")
	var hist := _host(b).tracker.history(-1)
	assert_eq(hist[2]["kind"], Wl.COOLDOWN)


func test_pause_stops_sim_step_and_resumes_on_pedal_start() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	var paused: Array = []
	(b["bus"] as WlEventBus).paused_changed.connect(func(p: bool, why: String) -> void: paused.append([p, why]))
	host.start()
	Kit.step(b, 10)
	_rider(b).pause_requested.emit("coasting")
	assert_true(host.is_paused())
	assert_eq(_rider(b).get("game_paused"), true)
	assert_eq(paused, [[true, "coasting"]])
	var steps_before: int = _game(b).get("steps")
	var game_tick := host.clock.game_tick
	Kit.step(b, 50)
	assert_eq(_game(b).get("steps"), steps_before, "no sim_step while paused")
	assert_eq(host.clock.game_tick, game_tick, "the game clock stops")
	assert_eq(host.clock.platform_tick, game_tick + 50, "platform time runs")
	assert_eq(int(_rider(b).get("ticks")), 60, "the trainer stack keeps ticking")
	(_rider(b).get("gesture_queue") as Array).append(Wl.G_PEDAL_START)
	Kit.step(b, 1)
	assert_false(host.is_paused())
	assert_eq(_rider(b).get("game_paused"), false)
	assert_eq(paused[1], [false, "resume"])
	assert_eq(_game(b).get("steps"), steps_before + 1)


func test_pause_and_confirm_actions() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	host.start()
	host.inject_action(&"pause")
	Kit.step(b, 1)
	assert_true(host.is_paused())
	host.inject_action(&"confirm")
	Kit.step(b, 1)
	assert_false(host.is_paused())
	host.inject_action(&"pause")
	Kit.step(b, 1)
	host.inject_action(&"pause")
	Kit.step(b, 1)
	assert_false(host.is_paused(), "pause toggles")


func test_shift_and_panic_actions() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	host.start()
	host.inject_action(&"shift_up")
	host.inject_action(&"shift_down")
	host.inject_action(&"panic")
	Kit.step(b, 1)
	assert_eq(_rider(b).get("shifts"), [1, -1] as Array[int])
	assert_eq(_rider(b).get("panics"), 1)
	(b["bus"] as WlEventBus).panic_requested.emit()
	assert_eq(_rider(b).get("panics"), 2)
	var calls: Array = _game(b).get("local_intent_calls")
	assert_eq(calls.size(), 1)
	assert_eq(calls[0]["actions"], [&"shift_up", &"shift_down"] as Array[StringName], "pause and panic are consumed")


func test_local_intents_and_ctx_intents_reach_the_frame_once() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	var game := _game(b)
	host.ctx.intents.send({"k": "summary"})
	host.start()
	Kit.step(b, 1)
	var seen: Array = game.get("intents_seen")
	assert_eq(seen.size(), 1)
	assert_eq(seen[0]["intent"], {"k": "summary"}, "sent before the first tick: the first frame")
	(_rider(b).get("gesture_queue") as Array).append(Wl.G_SURGE)
	Kit.step(b, 1)
	assert_eq(seen.size(), 2)
	assert_eq(seen[1]["intent"], {"k": "boost", "gesture": "surge"})
	assert_eq(int(seen[1]["tick"]), 1)
	game.set("on_step", func(g: GameModule, frame: InputFrame) -> void:
		if frame.tick == 3:
			g.ctx.intents.send({"k": "from_step"}))
	Kit.step(b, 3)
	var last: Dictionary = seen[seen.size() - 1]
	assert_eq(last["intent"], {"k": "from_step"})
	assert_eq(int(last["tick"]), 4, "sent during tick 3, delivered in the next frame")
	var calls: Array = game.get("local_intent_calls")
	assert_eq(calls[0]["gestures"], [Wl.G_SURGE] as Array[StringName], "gestures arrive apart from actions")
	assert_eq(calls[0]["actions"], [] as Array[StringName], "a surge never arrives as confirm")


func test_autopilot_intents_merge_order_and_only_for_autopilot_riders() -> void:
	var b := _solo("tiny", {}, 1)
	var host := _host(b)
	var game := _game(b)
	host.start()
	Kit.step(b, 39)
	var calls: Dictionary = game.get("autopilot_calls")
	assert_false(calls.has(1), "never called for an Autopilot-off human")
	assert_eq(int(calls.get(-1, 0)), 39, "every tick for a bot")
	_rider(b, -1).push_intent({"k": "own"})
	Kit.step(b, 2)
	var seen: Array = game.get("intents_seen")
	var bot_intents: Array = []
	for s: Dictionary in seen:
		if int(s["peer"]) == -1:
			bot_intents.append(s["intent"])
	assert_eq(bot_intents[0], {"k": "own"}, "the rider's own intents first")
	assert_eq(bot_intents[1]["k"], "auto", "then autopilot_intents")


func test_autopilot_human_gets_autopilot_intents() -> void:
	var slot := Kit.human(1, 0)
	slot.autopilot = true
	var b := _solo("tiny", {"players": [slot], "local_riders": {1: Kit.rider(_root, slot)}})
	assert_eq(b["err"], "")
	_host(b).start()
	Kit.step(b, 5)
	assert_eq(int((_game(b).get("autopilot_calls") as Dictionary).get(1, 0)), 5)


func test_rescue_and_afk_edges_call_the_game_once_per_transition() -> void:
	var b := _solo("tiny", {}, 1)
	var host := _host(b)
	var game := _game(b)
	var bus_rescue: Array = []
	(b["bus"] as WlEventBus).rescue_changed.connect(func(peer: int, on: bool) -> void: bus_rescue.append([peer, on]))
	host.start()
	Kit.step(b, 5)
	_rider(b).set("rescue", true)
	Kit.step(b, 5)
	_rider(b).set("rescue", false)
	Kit.step(b, 5)
	assert_eq(game.get("rescue_log"), [[1, true], [1, false]])
	assert_eq(bus_rescue, [[1, true], [1, false]])
	_rider(b, -1).set("afk", true)
	Kit.step(b, 3)
	assert_eq(game.get("afk_log"), [[-1, true]])


func test_end_phase_takes_effect_at_the_end_of_the_tick() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	var game := _game(b)
	var ended := [false]
	var after: Array = []
	game.set("on_step", func(g: GameModule, frame: InputFrame) -> void:
		var ps: PhaseState = frame.phase[1]
		if ended[0] and after.is_empty():
			after.append(ps.to_dict())
		if ps.index == 3 and ps.elapsed_s >= 2.0 and not ended[0]:
			ended[0] = g.ctx.directives.end_phase(1))
	host.start()
	Kit.step(b, 800)
	assert_true(ended[0])
	assert_eq(int(after[0]["index"]), 4, "the next frame shows the cool-down")
	assert_eq(float(after[0]["elapsed_s"]), 0.0)
	assert_eq(after[0]["prev_ended_by"], Wl.ENDED_END_PHASE)
	var hist := host.tracker.history(1)
	assert_eq(hist[3]["ended_by"], Wl.ENDED_END_PHASE)
	assert_almost_eq(float(hist[3]["end"]) - float(hist[3]["start"]), 2.05, 1e-9)


func test_open_ended_phase_ends_at_max_s() -> void:
	var b := _solo("tiny")
	_host(b).start()
	Kit.step(b, TINY_TICKS + 5)
	var hist := _host(b).tracker.history(1)
	assert_eq(hist[3]["ended_by"], Wl.ENDED_MAX_S)
	assert_almost_eq(float(hist[3]["end"]) - float(hist[3]["start"]), 6.0, 1e-9)
	assert_eq(_host(b).state, "cooldown")


func test_cooldown_keeps_sim_step_and_the_view() -> void:
	var b := _solo("tiny", {"headless": false})
	var host := _host(b)
	assert_eq(b["err"], "")
	assert_not_null(host.view_root(), "a view off headless")
	assert_true(host.view_root() is Node2D)
	assert_not_null(host.pixel_viewport(), "2D views go in a PixelViewport")
	assert_true(host.pixel_viewport().is_ancestor_of(host.view_root()))
	assert_eq(host.pixel_viewport().pixel_base, Vector2i(640, 360))
	assert_not_null(host.hud_layer())
	host.start()
	Kit.step(b, TINY_TICKS + 100)
	assert_eq(host.state, "cooldown")
	assert_gt(int(_game(b).get("cooldown_steps")), 90, "sim_step keeps running with kind COOLDOWN")
	assert_true(is_instance_valid(host.view_root()), "the view stays on screen")
	var r := host.ctx.directives.request(1, EffortDirective.from_dict({"target_pct": 50}))
	assert_eq(r.reason, Wl.REFUSE_COOLDOWN)
	assert_push_warning("cooldown")


func test_3d_view_is_added_directly() -> void:
	var b := _solo("tiny", {"headless": false}, 0, "fx_crew")
	assert_eq(b["err"], "")
	var host := _host(b)
	assert_true(host.view_root() is Node3D)
	assert_null(host.pixel_viewport())


func test_early_finished_skips_every_rider_to_the_cooldown() -> void:
	var b := _solo("tiny", {}, 1)
	var host := _host(b)
	var game := _game(b)
	var finished: Array = []
	(b["bus"] as WlEventBus).game_finished.connect(func(why: String) -> void: finished.append(why))
	game.set("on_step", func(g: GameModule, frame: InputFrame) -> void:
		if frame.tick == 50:
			g.finished.emit("complete"))
	host.start()
	Kit.step(b, 52)
	for peer: int in [1, -1]:
		assert_true(host.tracker.is_cooldown(peer))
		var hist := host.tracker.history(peer)
		assert_eq(hist[hist.size() - 2]["ended_by"], Wl.ENDED_FINISHED)
	assert_eq(host.finished_reason, "complete")
	assert_eq(finished, ["complete"])
	game.finished.emit("again")
	Kit.step(b, 2)
	assert_eq(host.finished_reason, "complete", "during the cool-down it only records")
	var phases_seen: Array = []
	for h: Dictionary in host.tracker.history(1):
		phases_seen.append(int(h["index"]))
	assert_eq(phases_seen, [0, 1, 4], "unused phases never start")


func test_results_progress_and_fit_after_the_cooldown() -> void:
	var tmp: String = Paths.make_temp_dir("wattlands_fit_test")
	_tmp.append(tmp)
	var fit_target := tmp.path_join("out/fit/run_slot0.fit")
	var b := _solo("tiny", {"fit_paths": {1: fit_target}}, 1)
	var host := _host(b)
	var game := _game(b)
	var ready: Array = []
	var unl: Array = []
	(b["bus"] as WlEventBus).results_ready.connect(func(r: GameResults) -> void: ready.append(r))
	(b["bus"] as WlEventBus).unlocks_ready.connect(func(u: Array) -> void: unl.append(u))
	watch_signals(host)
	host.start()
	Kit.step(b, TINY_TICKS + COOLDOWN_TICKS + 5)
	assert_true(host.is_finished())
	assert_eq(host.state, "results")
	assert_eq(host.end_reason, "complete")
	assert_eq(game.get("results_count"), 1)
	assert_eq(game.get("progress_calls"), 1)
	assert_signal_emitted(host, "session_finished")
	assert_eq(ready.size(), 1)
	assert_eq(unl, [["fx_badge"]])
	var res := host.final_results()
	assert_eq(res.grade, "B")
	assert_eq(res.rows.size(), 2)
	assert_gt(float(res.row(1)["kj"]), 0.0, "ctx.stats is final in results()")
	assert_string_starts_with(res.session_id, "fx_solo/tiny/7/", "game/content/seed plus the session's nonce")
	assert_eq(res.session_id, host.session_id)
	assert_true(FileAccess.file_exists(host.ctx.progress.path), "the store is saved")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(host.ctx.progress.path))
	assert_eq(float(saved["xp"]), 10.0)
	assert_eq(_rider(b).get("finished_rides"), 1)
	assert_eq(_rider(b, -1).get("finished_rides"), 0, "no FIT for bots")
	assert_eq(host.fit_paths(), {1: fit_target})
	assert_true(FileAccess.file_exists(fit_target))
	assert_true(FileAccess.file_exists(fit_target.get_basename() + ".json"), "the summary moves along")
	Kit.step(b, 10)
	assert_eq(game.get("results_count"), 1, "results once")


func test_end_session_timeout_still_gives_results_and_fit() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	host.start()
	Kit.step(b, 30)
	host.end_session("timeout")
	assert_eq(host.state, "ended")
	assert_eq(host.end_reason, "timeout")
	assert_not_null(host.final_results())
	assert_eq(_game(b).get("results_count"), 1)
	assert_eq(_rider(b).get("finished_rides"), 1)
	host.end_session("again")
	assert_eq(_game(b).get("results_count"), 1)


func test_lap_marker_and_phase_changed_are_recorded_not_acted_on() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	var game := _game(b)
	var laps: Array = []
	(b["bus"] as WlEventBus).lap_marked.connect(func(l: String) -> void: laps.append(l))
	var emitted := [0]
	game.phase_changed.connect(func(_i: int) -> void: emitted[0] += 1)
	game.set("on_step", func(g: GameModule, frame: InputFrame) -> void:
		if frame.tick == 5:
			g.lap_marker.emit("Gate")
			g.phase_changed.emit(7))
	host.start()
	Kit.step(b, 120)
	assert_eq(_rider(b).get("laps"), ["Gate"] as Array[String])
	assert_eq(laps, ["Gate"])
	assert_eq(emitted[0], 1, "the GameHost never emits phase_changed itself")
	assert_eq(host.tracker.index_of(1), 2, "and never changes phases on it")
	var types: Array = []
	for e: Dictionary in host.report.events:
		types.append(str(e["type"]))
	assert_has(types, "game_phase_changed")
	assert_has(types, "lap_marker")


func test_game_events_are_recorded_and_never_applied_on_the_host() -> void:
	var b := _solo("tiny")
	_host(b).start()
	Kit.step(b, 45)
	assert_eq((_game(b).get("events_applied") as Array).size(), 0)
	var found := 0
	for e: Dictionary in _host(b).report.events:
		if str(e["type"]) == "game_event":
			found += 1
			assert_eq(str(e["event"]["type"]), "tick")
	assert_eq(found, 2)


func test_report_data() -> void:
	var b := _solo("tiny", {}, 1)
	var host := _host(b)
	host.start()
	host.ctx.directives.request(1, EffortDirective.from_dict({"target_pct": 50}))
	Kit.step(b, 41)
	var d := host.report_data()
	for k: String in ["events", "directives", "trace", "snapshots", "max_snapshot_bytes", "oversize_snapshots", "phases", "plans", "plan_warnings", "finished_reason"]:
		assert_true(d.has(k), k)
	assert_eq((d["trace"] as Dictionary).keys(), ["1", "-1"])
	var row: Dictionary = d["trace"]["1"][0]
	for k: String in ["t", "phase", "kind", "mode", "applied_target_w", "applied_pct", "applied_grade_pct", "clamped_by", "rescue", "afk", "paused", "haptic", "power_w", "cadence_rpm"]:
		assert_true(row.has(k), "trace " + k)
	assert_eq((d["trace"]["1"] as Array).size(), 3, "1 Hz: platform ticks 0, 20, 40")
	assert_eq((d["snapshots"] as Array).size(), 21, "10 Hz")
	var snap: Dictionary = d["snapshots"][0]
	assert_eq(str(snap["sha256"]).length(), 64)
	assert_gt(int(snap["bytes"]), 0)
	var biggest := 0
	for sn: Dictionary in d["snapshots"]:
		biggest = maxi(biggest, int(sn["bytes"]))
	assert_eq(int(d["max_snapshot_bytes"]), biggest)
	assert_eq((d["directives"] as Array).size(), 1)
	assert_not_null(d["directives"][0]["applied"])
	assert_eq((_rider(b).get("ack_queue") as Array).size(), 0, "a local rider's ack queue is drained on the host")
	assert_eq((d["phases"]["1"] as Array)[0]["ended_by"], Wl.ENDED_DURATION)


func test_results_get_a_row_per_rider_when_the_game_leaves_rows_out() -> void:
	var b := _solo("tiny", {}, 1)
	var host := _host(b)
	_game(b).set("results_mode", "empty")
	host.start()
	Kit.step(b, 100)
	host.end_session("timeout")
	var res := host.final_results()
	assert_eq(res.grade, "C", "the game's own fields stay")
	assert_eq(res.rows.size(), 2, "the platform's base row for every rider")
	assert_eq(int(res.rows[0]["peer_id"]), 1)
	assert_eq(int(res.rows[1]["peer_id"]), -1)
	assert_eq(res.rows[1]["name"], "Bot 1")
	assert_almost_eq(float(res.row(1)["kj"]), host.ctx.stats.kj(1), 1e-9)
	for k: String in ["kj", "avg_power_w", "avg_ftp_pct", "np_w", "best_1m_w", "best_5m_w", "best_20m_w", "ride_s", "time_in_band_s", "time_in_band_pct", "xp", "unlocks", "stats", "slot_index", "is_bot"]:
		assert_true(res.rows[0].has(k), k)


func test_results_rows_the_game_wrote_keep_their_values() -> void:
	var b := _solo("tiny", {}, 1)
	var host := _host(b)
	_game(b).set("results_mode", "partial")
	host.start()
	Kit.step(b, 100)
	host.end_session("timeout")
	var res := host.final_results()
	assert_eq(res.rows.size(), 2)
	var mine := res.row(1)
	assert_eq(float(mine["kj"]), 999.0, "a value the game set is never changed")
	assert_eq(mine["stats"], {"custom": "yes"})
	assert_eq(mine["name"], "Rider 1", "missing base keys are filled in")
	assert_true(mine.has("avg_power_w"))
	assert_eq(int(res.rows[1]["peer_id"]), -1, "the missing rider is appended")


func test_a_confirm_that_resumes_is_not_also_a_game_confirm() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	host.start()
	Kit.step(b, 2)
	host.pause("user")
	Kit.step(b, 2)
	host.inject_action(&"confirm")
	Kit.step(b, 1)
	assert_false(host.is_paused())
	for c: Dictionary in _game(b).get("local_intent_calls"):
		assert_false((c["actions"] as Array).has(&"confirm"), "consumed by the resume")
	host.inject_action(&"confirm")
	Kit.step(b, 1)
	var calls: Array = _game(b).get("local_intent_calls")
	assert_eq(calls[calls.size() - 1]["actions"], [&"confirm"] as Array[StringName], "the next confirm is the game's")


class FakeRouter:
	extends Node
	var actions: Array[StringName] = []
	var gestures: Array[StringName] = []
	var attached: LocalRider = null
	var detached: int = 0

	func take_actions() -> Array[StringName]:
		var out := actions
		actions = []
		return out

	func take_gestures() -> Array[StringName]:
		var out := gestures
		gestures = []
		return out

	func attach_rider(rider: LocalRider) -> void:
		attached = rider

	func detach_rider() -> void:
		detached += 1


func test_rendering_takes_gestures_and_actions_from_the_input_router() -> void:
	var router := FakeRouter.new()
	_root.add_child(router)
	var b := _solo("tiny", {"headless": false, "input_router": router})
	assert_eq(b["err"], "")
	var host := _host(b)
	var game := _game(b)
	assert_eq(router.attached, _rider(b), "the own rider is attached for pedal UI")
	game.set("keep_frames", true)
	host.start()
	Kit.step(b, 2)
	router.gestures.append(Wl.G_SURGE)
	router.actions.append(&"confirm")
	Kit.step(b, 1)
	var calls: Array = game.get("local_intent_calls")
	assert_eq(calls[0]["gestures"], [Wl.G_SURGE] as Array[StringName])
	assert_eq(calls[0]["actions"], [&"confirm"] as Array[StringName])
	var frames: Array = game.get("frames_seen")
	var tm: Telemetry = (frames[frames.size() - 1]["players"] as Dictionary)[1]
	assert_eq(tm.gestures, [Wl.G_SURGE] as Array[StringName], "the frame shows the same gesture")
	(_rider(b).get("gesture_queue") as Array).append(Wl.G_COAST)
	Kit.step(b, 1)
	assert_eq(calls.size(), 1, "one source: the rider's own queue is the router's to merge")
	host.end_session("timeout")
	assert_eq(router.detached, 1)


## qa W1 (real e2e: the clients stayed in the lobby): the app gives a headless scripted peer's
## GameHost no "realtime" key, so it must still advance from _process; only GameSimRunner and
## tests, which call step() themselves, pass realtime = false.
func test_a_headless_app_session_steps_from_process() -> void:
	var reg := Kit.registry(_root)
	var tmp := Paths.make_temp_dir("wattlands_sdk_test")
	_tmp.append(tmp)
	var slot := Kit.human(1, 0)
	var host := GameHost.new()
	_root.add_child(host)
	assert_eq(host.setup({
		"game_id": "fx_solo", "content_id": "tiny", "seed": 7, "role": Wl.SOLO, "players": [slot] as Array[PlayerSlot],
		"local_riders": {1: Kit.rider(_root, slot)}, "local_peer": 1, "bus": Kit.new_bus(_root, "AppBus"),
		"registry": reg, "headless": true, "progress_path": tmp.path_join("progress.json"),
	}), "")
	host.start()
	host._process(0.5)
	assert_eq(host.clock.platform_tick, 10, "0.5 s of wall time at sim speed 1 is 10 steps")
	var stepped := GameHost.new()
	_root.add_child(stepped)
	var s2 := Kit.human(1, 0)
	stepped.setup({
		"game_id": "fx_solo", "content_id": "tiny", "seed": 7, "role": Wl.SOLO, "players": [s2] as Array[PlayerSlot],
		"local_riders": {1: Kit.rider(_root, s2)}, "local_peer": 1, "bus": Kit.new_bus(_root, "RunnerBus"),
		"registry": reg, "headless": true, "realtime": false, "progress_path": tmp.path_join("p2.json"),
	})
	stepped.start()
	stepped._process(0.5)
	assert_eq(stepped.clock.platform_tick, 0, "realtime false: only step() advances it")
	host.end_session("timeout")
	stepped.end_session("timeout")


## app-shell W1: the session screen owns pausing (it calls pause() and resume() and runs the
## pause menu), so the InputRouter's pause never toggles the GameHost, and its confirm during a
## pause belongs to the pause menu, not to a resume or the game. A user pause does not end when
## the rider pedals; a coasting pause does.
func test_the_input_routers_pause_and_confirm_belong_to_the_session_screen() -> void:
	var router := FakeRouter.new()
	_root.add_child(router)
	var b := _solo("tiny", {"headless": false, "input_router": router})
	assert_eq(b["err"], "")
	var host := _host(b)
	var game := _game(b)
	host.start()
	Kit.step(b, 2)
	router.actions.append(&"pause")
	Kit.step(b, 1)
	assert_false(host.is_paused(), "the router's pause is the screen's")
	for c: Dictionary in game.get("local_intent_calls"):
		assert_false((c["actions"] as Array).has(&"pause"), "and never reaches the game")
	host.pause("user")
	var calls_before: int = (game.get("local_intent_calls") as Array).size()
	router.actions.append(&"confirm")
	router.gestures.append(Wl.G_PEDAL_START)
	Kit.step(b, 1)
	assert_true(host.is_paused(), "neither the router's confirm nor pedalling ends a user pause")
	var calls: Array = game.get("local_intent_calls")
	for k in range(calls_before, calls.size()):
		assert_false((calls[k]["actions"] as Array).has(&"confirm"), "the pause menu's confirm is not the game's")
	host.resume()
	assert_false(host.is_paused())
	_rider(b).pause_requested.emit("coasting")
	assert_true(host.is_paused())
	router.gestures.append(Wl.G_PEDAL_START)
	Kit.step(b, 1)
	assert_false(host.is_paused(), "pedalling again ends a coasting pause")
	host.end_session("timeout")


## lead W2 round 2: config.platform_pause = false hands pausing to the app (its session screen
## pauses and resumes through AppSessionInput): the GameHost never toggles pause on `pause`,
## never resumes on `confirm` or `pedal_start`, and a `confirm` stays the game's. The SOLO
## coasting pause (LocalRider.pause_requested, BRIEF 4.6.4) still pauses.
func test_platform_pause_off_leaves_pausing_to_the_app() -> void:
	var b := _solo("tiny", {"platform_pause": false})
	assert_eq(b["err"], "")
	var host := _host(b)
	var game := _game(b)
	host.start()
	Kit.step(b, 2)
	host.inject_action(&"pause")
	Kit.step(b, 1)
	assert_false(host.is_paused(), "an injected pause does not pause")
	for c: Dictionary in game.get("local_intent_calls"):
		assert_false((c["actions"] as Array).has(&"pause"), "and never reaches the game")
	host.pause("user")
	host.inject_action(&"pause")
	Kit.step(b, 1)
	assert_true(host.is_paused(), "nor does it resume")
	host.inject_action(&"confirm")
	Kit.step(b, 1)
	assert_true(host.is_paused(), "confirm does not resume")
	var calls: Array = game.get("local_intent_calls")
	assert_eq(calls[calls.size() - 1]["actions"], [&"confirm"] as Array[StringName], "the confirm stays an ordinary action")
	host.resume()
	assert_false(host.is_paused(), "the app resumes")
	_rider(b).pause_requested.emit("coasting")
	assert_true(host.is_paused(), "the coasting pause (4.6.4) still pauses")
	(_rider(b).get("gesture_queue") as Array).append(Wl.G_PEDAL_START)
	Kit.step(b, 3)
	assert_true(host.is_paused(), "pedal_start does not resume: the app does")
	host.resume()
	assert_false(host.is_paused())
	host.end_session("timeout")


## The default (platform_pause on, every config without the key) keeps the W1 behaviour: an
## injected pause toggles and pedalling again ends a coasting pause.
func test_platform_pause_defaults_on() -> void:
	for extra: Dictionary in [{}, {"platform_pause": true}]:
		var b := _solo("tiny", extra)
		var host := _host(b)
		host.start()
		host.inject_action(&"pause")
		Kit.step(b, 1)
		assert_true(host.is_paused(), str(extra))
		host.inject_action(&"pause")
		Kit.step(b, 1)
		assert_false(host.is_paused(), str(extra))
		_rider(b).pause_requested.emit("coasting")
		(_rider(b).get("gesture_queue") as Array).append(Wl.G_PEDAL_START)
		Kit.step(b, 1)
		assert_false(host.is_paused(), str(extra))
		host.end_session("timeout")


func test_headless_takes_gestures_from_the_local_rider() -> void:
	var router := FakeRouter.new()
	_root.add_child(router)
	var b := _solo("tiny", {"input_router": router})
	var host := _host(b)
	host.start()
	router.gestures.append(Wl.G_COAST)
	(_rider(b).get("gesture_queue") as Array).append(Wl.G_SURGE)
	Kit.step(b, 1)
	var calls: Array = _game(b).get("local_intent_calls")
	assert_eq(calls[0]["gestures"], [Wl.G_SURGE] as Array[StringName])
	assert_eq(router.gestures, [] as Array[StringName], "the router's queue is drained and ignored")


class FakeSfx:
	extends Node
	var calls: Array = []

	func set_metronome(rpm: float, on: bool) -> void:
		calls.append([rpm, on])


func test_metronome_follows_the_cadence_band_au2() -> void:
	var sfx := FakeSfx.new()
	_root.add_child(sfx)
	var b := _solo("tiny", {"headless": false, "sfx": sfx})
	var host := _host(b)
	var prof := RiderProfile.new()
	prof.metronome = true
	_rider(b).profile = prof
	host.start()
	assert_eq(sfx.calls[sfx.calls.size() - 1], [90.0, true], "the preferred cadence without a band")
	host.ctx.directives.cadence_band(1, 80, 100)
	assert_eq(sfx.calls[sfx.calls.size() - 1], [90.0, true], "the band's centre")
	host.ctx.directives.cadence_band(1, 60, 70)
	assert_eq(sfx.calls[sfx.calls.size() - 1], [65.0, true])
	host.ctx.directives.cadence_band(1, 0, 0)
	assert_eq(sfx.calls[sfx.calls.size() - 1], [90.0, true], "cleared: the preferred cadence again")
	prof.metronome = false
	host.ctx.directives.cadence_band(1, 70, 80)
	assert_eq(sfx.calls[sfx.calls.size() - 1], [75.0, false], "off in the profile: silent")
	host.end_session("timeout")
	assert_eq(sfx.calls[sfx.calls.size() - 1], [0.0, false], "stopped at the end")


func test_headless_never_touches_the_metronome() -> void:
	var sfx := FakeSfx.new()
	_root.add_child(sfx)
	var b := _solo("tiny", {"sfx": sfx})
	_host(b).start()
	_host(b).ctx.directives.cadence_band(1, 80, 100)
	_host(b).end_session("timeout")
	assert_eq(sfx.calls, [])


func test_oversize_snapshots_are_counted_c9() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	_game(b).set("snapshot_pad", NetMessages.MAX_MESSAGE_BYTES + 100)
	host.start()
	Kit.step(b, 3)
	assert_eq(host.report.oversize_snapshots, 2, "platform ticks 0 and 2")
	assert_gt(host.report.max_snapshot_bytes, NetMessages.MAX_MESSAGE_BYTES)
	assert_push_warning("is over 16384 bytes")
	_game(b).set("snapshot_pad", 0)
	Kit.step(b, 2)
	assert_eq(host.report.oversize_snapshots, 2, "a small snapshot is not counted")


func test_stats_accumulate_while_riding() -> void:
	var b := _solo("tiny")
	var host := _host(b)
	host.start()
	Kit.step(b, 100)
	assert_gt(host.ctx.stats.kj(1), 0.0)
	assert_almost_eq((host.stats as SessionStatsTracker).ride_s(1), 5.0, 1e-6)


## W3 SAF-4: ctx.directives and ctx.hud are the routers that drive the riders, but no public
## property of theirs hands a game a LocalRider (whose set_plan, start_phase, resume and
## governor bypass the DirectiveSink's checks). Their rider maps are private and write-only.
func test_ctx_routers_hand_out_no_local_rider() -> void:
	var b := _solo("tiny", {}, 1)
	assert_eq(b["err"], "")
	var ctx := _host(b).ctx
	for router: Object in [ctx.directives, ctx.hud]:
		assert_false("riders" in router, "%s has no public riders map" % router.get_script().get_global_name())
		for prop: Dictionary in router.get_property_list():
			var pname := str(prop["name"])
			if pname.begins_with("_") or not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var v: Variant = router.get(pname)
			var found: Array = []
			if v is LocalRider:
				found.append(v)
			elif v is Dictionary:
				for x: Variant in (v as Dictionary).values():
					if x is LocalRider:
						found.append(x)
			elif v is Array:
				for x: Variant in v:
					if x is LocalRider:
						found.append(x)
			assert_eq(found.size(), 0, "%s.%s exposes no LocalRider" % [router.get_script().get_global_name(), pname])
	# The routers still drive the riders simulated here.
	ctx.hud.power_band(1, 120.0, 160.0)
	assert_eq(_rider(b).power_band(), Vector2(120.0, 160.0))


## W4 SAF-4 (round 2): the GameModule is the GameHost's child, so get_parent() reaches the
## GameHost without naming it. No public property of the GameHost hands a game a LocalRider
## (the rider map is private); the platform reads one rider through local_rider(peer), a name
## the no-bypass gate forbids under src/games/.
func test_the_game_host_hands_its_game_no_local_rider() -> void:
	var b := _solo("tiny", {}, 1)
	assert_eq(b["err"], "")
	var host := _host(b)
	assert_same(_game(b).get_parent(), host, "precondition: the game is the GameHost's child")
	assert_false("local_riders" in host, "GameHost has no public local_riders map")
	for prop: Dictionary in host.get_property_list():
		var pname := str(prop["name"])
		if pname.begins_with("_") or not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		assert_eq(_riders_in(host.get(pname), 3), 0, "GameHost.%s exposes no LocalRider" % pname)
	assert_false(host.config.has("local_riders"), "nor does the config it keeps")
	assert_same(host.local_rider(1), _rider(b), "the platform's accessor: the player's rider")
	assert_same(host.local_rider(-1), _rider(b, -1), "and a bot's on the host")
	assert_null(host.local_rider(7), "null for a peer simulated elsewhere")


## LocalRiders inside `v` (nested dictionaries and arrays down to `depth`).
static func _riders_in(v: Variant, depth: int) -> int:
	if v is LocalRider:
		return 1
	if depth <= 0:
		return 0
	var n := 0
	if v is Dictionary:
		for x: Variant in (v as Dictionary).values():
			n += _riders_in(x, depth - 1)
	elif v is Array:
		for x: Variant in v:
			n += _riders_in(x, depth - 1)
	return n


## W3 SDK-5 (GAME_SDK 15): results.session_id is unique per session, so a game that skips a
## repeated id (the template's apply_progress) credits a second session with the same game,
## content and seed. session_nonce "" (GameSimRunner) keeps the deterministic game/content/seed.
func test_session_ids_are_unique_per_session_even_with_the_same_seed() -> void:
	var a := _solo("tiny")
	var b := _solo("tiny")
	assert_eq(a["err"], "")
	assert_eq(b["err"], "")
	var ida := _host(a).session_id
	var idb := _host(b).session_id
	assert_string_starts_with(ida, "fx_solo/tiny/7/")
	assert_string_starts_with(idb, "fx_solo/tiny/7/")
	assert_ne(ida, idb, "two sessions with seed 7 get two ids")
	var c := _solo("tiny", {"session_nonce": ""})
	assert_eq(_host(c).session_id, "fx_solo/tiny/7", "no nonce: the deterministic id")
	var d := _solo("tiny", {"session_nonce": "room-K7QX2M-3"})
	assert_eq(_host(d).session_id, "fx_solo/tiny/7/room-K7QX2M-3")
