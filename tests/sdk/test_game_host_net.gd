extends GutTest
## GameHost HOST + CLIENT over FakeNet doubles of WlNetSession (BRIEF 3.6, 5.5; BRIEF 7.1 "a
## host with two client NetSessions: each client's governor follows its remote plan, phase
## changes caused by end_phase, course_grade and cadence_band"; docs/OWNERSHIP.md GM2, GM7,
## GM10-GM12, GM17, GM21, GM22, CTX1, CTX3-CTX5, CTX11, CTX12, CTX14, DS13, IF6-IF8, NET1,
## NET3, NET6, PL21). The same flows run over the real NetSession and LoopbackTransport in
## tests/sdk/integration/ (W2).

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")
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


func _multi(humans: int = 3, content: String = "tiny", extra: Dictionary = {}, bots: int = 0) -> Dictionary:
	var b := Kit.multi(_root, humans, content, extra, bots)
	_tmp.append(str(b["tmp"]))
	assert_eq(b["err"], "", "session setup")
	return b


func _host(b: Dictionary) -> GameHost:
	return b["host"]


func _client(b: Dictionary, i: int) -> GameHost:
	return (b["clients"] as Array)[i]


func _rider(b: Dictionary, peer: int) -> LocalRider:
	return b["riders"][peer]


func test_clients_configure_from_session_start() -> void:
	var b := _multi(3, "tiny", {"options": {"mode": "b"}}, 1)
	Kit.start(b)
	assert_null(_client(b, 0).game, "a client waits for session_start")
	Kit.step(b, 1)
	var host := _host(b)
	for i in 2:
		var c := _client(b, i)
		assert_not_null(c.game)
		assert_eq(c.game.get("configure_count"), 1)
		var ctx := c.ctx
		assert_eq(ctx.role, Wl.CLIENT)
		assert_false(ctx.is_authority())
		assert_eq(ctx.local_peer, i + 2)
		assert_eq(ctx.game_id, "fx_solo")
		assert_eq(ctx.content_id, "tiny")
		assert_eq(ctx.seed, host.ctx.seed)
		assert_eq(ctx.rng.seed, host.ctx.rng.seed)
		assert_eq(ctx.peers(), host.ctx.peers(), "same slot order on every peer")
		assert_eq(ctx.options, {"speed": 2, "mirror": false, "mode": "b"})
		assert_true(ctx.events != host.ctx.events, "each peer has its own EventBus")
		assert_eq(c.session_id, host.session_id)
	assert_eq(_client(b, 0).state, "running")


func test_each_client_rider_follows_its_remote_plan_and_phases() -> void:
	var b := _multi(3, "split")
	Kit.start(b)
	Kit.step(b, 200)
	var host := _host(b)
	for peer: int in [2, 3]:
		var r := _rider(b, peer)
		var plans: Array = r.get("plans_set")
		assert_eq(plans.size(), 1, "peer %d got its plan" % peer)
		var got := (plans[0] as EffortPlan).to_dict()
		assert_eq(JSON.stringify(got), JSON.stringify((host.plans[peer] as EffortPlan).to_dict()))
		assert_true((plans[0] as EffortPlan).cooldown_appended)
		var host_seq: Array[int] = []
		for h: Dictionary in host.tracker.history(peer):
			host_seq.append(int(h["index"]))
		assert_eq(r.get("phases_started"), host_seq, "the client's governor follows the host's phases")
	assert_eq(_rider(b, 3).get("phases_started"), [0, 1, 2] as Array[int], "slot 2 rides the short plan into its cool-down")
	assert_eq((_rider(b, 2).get("phases_started") as Array).size(), 3, "slot 1 ... rides its own")


func test_end_phase_course_grade_and_cadence_band_reach_the_client() -> void:
	var b := _multi(3)
	var host := _host(b)
	var game := host.game
	var c_bands: Array = []
	(b["buses"][1] as WlEventBus).cadence_band_changed.connect(func(p: int, lo: float, hi: float) -> void: c_bands.append([p, lo, hi]))
	var done := {"band": false, "grade": 0, "end": false}
	game.set("on_step", func(g: GameModule, frame: InputFrame) -> void:
		var ps: PhaseState = frame.phase[2]
		if frame.tick == 10 and not done["band"]:
			g.ctx.directives.cadence_band(2, 82, 98)
			done["band"] = true
		if ps.index == 2 and int(done["grade"]) < 3 and frame.tick % 10 == 0:
			g.ctx.directives.course_grade(2, 1.5 + int(done["grade"]))
			done["grade"] = int(done["grade"]) + 1
		if ps.index == 3 and ps.elapsed_s >= 2.0 and not done["end"]:
			for peer: int in frame.phase.keys():
				g.ctx.directives.end_phase(peer)
			done["end"] = true)
	Kit.start(b)
	Kit.step(b, 200)
	var r2 := _rider(b, 2)
	assert_eq(r2.get("band_cadence"), [82.0, 98.0])
	assert_eq((r2.device as Object).call("last_cadence_band"), [82.0, 98.0], "the client's MockTrainer band policy")
	assert_eq(c_bands[0], [2, 82.0, 98.0], "the client's HUD")
	Kit.step(b, 560)
	assert_eq(r2.get("grades"), [1.5, 2.5, 3.5] as Array[float])
	assert_eq(r2.get("phases_started"), [0, 1, 2, 3, 4] as Array[int], "end_phase reached the client as a phase message")
	assert_eq(host.tracker.history(2)[3]["ended_by"], Wl.ENDED_END_PHASE)
	assert_eq(r2.get("band_cadence"), [0.0, 0.0], "the cool-down clears the band on the client")
	assert_eq(c_bands[c_bands.size() - 1], [2, 0.0, 0.0])
	assert_eq(_client(b, 0).state, "cooldown")


func test_remote_directive_is_applied_and_acked() -> void:
	var b := _multi(3)
	var host := _host(b)
	var acks: Array = []
	(b["buses"][0] as WlEventBus).directive_applied.connect(func(p: int, rec: Dictionary) -> void: acks.append([p, rec]))
	Kit.start(b)
	Kit.step(b, 45)
	var res := host.ctx.directives.request(3, EffortDirective.from_dict({"target_pct": 58, "reason": "bank", "source": "fx"}))
	assert_true(res.accepted)
	Kit.step(b, 1)
	var dirs: Array = _rider(b, 3).get("directives")
	assert_eq(dirs.size(), 1)
	assert_eq((dirs[0] as EffortDirective).id, res.id, "the id travels with it")
	assert_eq((dirs[0] as EffortDirective).target_pct, 58.0)
	Kit.step(b, 6)
	assert_eq(acks.size(), 1, "the client's governor record comes back in Telemetry.acks")
	assert_eq(acks[0][0], 3)
	assert_eq(int(acks[0][1]["id"]), res.id)
	var entry: Dictionary = host.report.directives[0]
	assert_eq(int(entry["id"]), res.id)
	assert_not_null(entry["applied"], "the report joins requested and applied")


func test_a_remote_governor_refusal_comes_back_and_releases_the_block() -> void:
	var b := _multi(3)
	var host := _host(b)
	Kit.start(b)
	Kit.step(b, 10)
	_rider(b, 2).set("refuse_reason", Wl.REFUSE_SIM_BLOCK_UNSAFE)
	assert_true(host.ctx.directives.request(2, EffortDirective.from_dict({"mode": "SIM", "duration_s": 12})).accepted)
	assert_true(host.tracker.block_active(2, host.clock.game_tick))
	Kit.step(b, 8)
	assert_false(host.tracker.block_active(2, host.clock.game_tick), "the refused block is taken back")
	var entry: Dictionary = host.report.directives[0]
	assert_true(bool(entry["applied"]["refused"]), "the report keeps the governor's refusal")
	assert_eq(entry["applied"]["reason"], Wl.REFUSE_SIM_BLOCK_UNSAFE)


func test_events_reach_clients_in_order_and_never_the_host() -> void:
	var b := _multi(3)
	var host := _host(b)
	Kit.start(b)
	Kit.step(b, 90)
	var e2: Array = _client(b, 0).game.get("events_applied")
	var e3: Array = _client(b, 1).game.get("events_applied")
	assert_eq(e2.size(), 4)
	assert_eq(JSON.stringify(e2), JSON.stringify(e3), "the same order on every client")
	assert_eq(float(e2[0]["n"]), 1.0)
	assert_eq(float(e2[3]["n"]), 4.0)
	assert_eq((host.game.get("events_applied") as Array).size(), 0, "apply_event never runs on the host")
	# A duplicate batch is ignored.
	var nets: Array = b["nets"]
	(nets[0] as WlNetSession).send_to(2, Protocol.game_msg("event", {"seq": 1, "events": [{"type": "tick", "n": 99}]}))
	Kit.step(b, 1)
	assert_eq((_client(b, 0).game.get("events_applied") as Array).size(), 4)


func test_snapshots_and_client_predict() -> void:
	var b := _multi(3)
	var host := _host(b)
	Kit.start(b)
	Kit.step(b, 21)
	var cg := _client(b, 0).game
	assert_eq(int(cg.get("snapshots_applied")), 11, "10 Hz")
	assert_eq(JSON.stringify(cg.get("last_snapshot_applied")), JSON.stringify(host.last_snapshot()))
	assert_eq(int(cg.get("predicts")), 21, "every client tick once configured")
	assert_eq(int(host.game.get("snapshots_applied")), 0)


func test_an_older_snapshot_is_dropped_gm10() -> void:
	var b := _multi(2)
	Kit.start(b)
	Kit.step(b, 21)
	var cg := _client(b, 0).game
	var applied: int = cg.get("snapshots_applied")
	var latest := JSON.stringify(cg.get("last_snapshot_applied"))
	(b["nets"][0] as WlNetSession).send_to(2, Protocol.game_msg("snapshot", {"game_id": "fx_solo", "seq": 3, "tick": 4, "state": {"steps": -1.0}}))
	_client(b, 0).step()
	assert_eq(int(cg.get("snapshots_applied")), applied, "seq 3 is older than the applied one")
	assert_eq(JSON.stringify(cg.get("last_snapshot_applied")), latest)


func test_a_ticks_event_batch_goes_out_before_its_snapshot_c12() -> void:
	var b := _multi(2)
	var host_net: Object = b["nets"][0]
	Kit.start(b)
	host_net.set("sent", [])
	Kit.step(b, 60)
	var types: Array[String] = host_net.call("sent_types", 2)
	var ev := types.find("event")
	assert_gt(ev, -1, "fx_game sends an event every 20 ticks")
	assert_eq(types[ev + 1], "snapshot", "the batch, then the same tick's snapshot")
	var batches := types.count("event")
	assert_lte(batches, 6, "at most one batch per 100 ms (60 ticks = 3 s, events every 1 s)")


func test_more_than_32_intents_in_one_telemetry_are_dropped_c11() -> void:
	var b := _multi(2)
	var host := _host(b)
	Kit.start(b)
	Kit.step(b, 4)
	for i in 40:
		_client(b, 0).ctx.intents.send({"k": "spam", "i": float(i)})
	Kit.step(b, 8)
	assert_push_warning("8 dropped (max 32)")
	var got: Array = []
	for s: Dictionary in host.game.get("intents_seen"):
		if int(s["peer"]) == 2:
			got.append(int(float(s["intent"]["i"])))
	assert_eq(got.size(), 32, "at most 32 per telemetry message")
	assert_eq(got[0], 0, "in order")
	assert_eq(got[31], 31)


func test_client_intents_reach_the_host_frame_once() -> void:
	var b := _multi(3)
	var host := _host(b)
	Kit.start(b)
	Kit.step(b, 3)
	(_rider(b, 2).get("gesture_queue") as Array).append(Wl.G_SURGE)
	_client(b, 1).ctx.intents.send({"k": "buy", "item": "x"})
	Kit.step(b, 12)
	var seen: Array = host.game.get("intents_seen")
	var from2: Array = []
	var from3: Array = []
	for s: Dictionary in seen:
		if int(s["peer"]) == 2:
			from2.append(s)
		elif int(s["peer"]) == 3:
			from3.append(s)
	assert_eq(from2.size(), 1, "exactly once")
	assert_eq(from2[0]["intent"], {"k": "boost", "gesture": "surge"})
	assert_eq(from3.size(), 1)
	assert_eq(from3[0]["intent"], {"k": "buy", "item": "x"})
	var gestures_seen := [0]
	host.game.set("on_step", func(_g: GameModule, frame: InputFrame) -> void:
		if (frame.players[2] as Telemetry).gestures.has(Wl.G_SURGE):
			gestures_seen[0] += 1)
	(_rider(b, 2).get("gesture_queue") as Array).append(Wl.G_SURGE)
	Kit.step(b, 10)
	assert_eq(gestures_seen[0], 1, "gestures travel in Telemetry.gestures, once")


func test_remote_age_s_every_tick() -> void:
	var b := _multi(2)
	var host := _host(b)
	var ages: Array = []
	host.game.set("on_step", func(_g: GameModule, frame: InputFrame) -> void:
		ages.append(snappedf((frame.players[2] as Telemetry).age_s, 0.001)))
	Kit.start(b)
	Kit.step(b, 12)
	assert_eq(ages.size(), 12)
	assert_true(ages.has(0.05) and ages.has(0.1), "age grows between 5 Hz messages")
	assert_lte(float(ages.max()), 0.25)
	assert_gt(float((host.game.get("distance") as Dictionary).get(2, 0.0)), 0.0, "remote power reaches the frame")


func test_drop_and_rejoin() -> void:
	var b := _multi(3)
	var host := _host(b)
	var game := host.game
	var frames: Array = []
	game.set("on_step", func(_g: GameModule, frame: InputFrame) -> void:
		frames.append((frame.players[3] as Telemetry).duplicate_telemetry()))
	Kit.start(b)
	Kit.step(b, 40)
	(b["hub"] as RefCounted).call("drop", 3)
	Kit.step(b, 1)
	assert_eq(game.get("afk_log"), [[3, true]], "on_afk(peer, true) at once")
	var tm: Telemetry = frames[frames.size() - 1]
	assert_false(tm.connected)
	assert_eq(tm.power_w, 0.0)
	assert_eq(tm.cadence_rpm, 0.0)
	assert_true(tm.afk)
	Kit.step(b, 40)
	tm = frames[frames.size() - 1]
	assert_gt(tm.age_s, 2.0, "age_s keeps counting")
	assert_eq(host.ctx.players.size(), 3, "the slot stays")
	var host_net: Object = b["nets"][0]
	host_net.set("sent", [])
	(b["hub"] as RefCounted).call("rejoin", 3)
	Kit.step(b, 1)
	var types: Array[String] = host_net.call("sent_types", 3)
	assert_eq(types.slice(0, 4), ["session_start", "plan", "phase", "snapshot"] as Array[String], "the rejoin gets its state back")
	tm = frames[frames.size() - 1]
	assert_true(tm.connected, "back on the network")
	assert_eq(tm.power_w, 0.0, "the pre-drop telemetry never shows up as live power")
	assert_eq(tm.cadence_rpm, 0.0)
	assert_true(tm.afk, "AFK until fresh telemetry shows pedaling")
	Kit.step(b, 10)
	assert_eq(game.get("afk_log"), [[3, true], [3, false]], "on_afk(false) once fresh telemetry shows pedaling")


func test_rejoin_waits_for_pedaling() -> void:
	var b := _multi(2)
	var host := _host(b)
	Kit.start(b)
	Kit.step(b, 20)
	(b["hub"] as RefCounted).call("drop", 2)
	Kit.step(b, 1)
	_rider(b, 2).set("follow_target", false)
	_rider(b, 2).set("power_w", 0.0)
	_rider(b, 2).set("cadence_rpm", 0.0)
	(b["hub"] as RefCounted).call("rejoin", 2)
	Kit.step(b, 20)
	assert_eq(host.game.get("afk_log"), [[2, true]], "still AFK while not pedaling")
	_rider(b, 2).set("power_w", 120.0)
	_rider(b, 2).set("cadence_rpm", 85.0)
	Kit.step(b, 6)
	assert_eq(host.game.get("afk_log"), [[2, true], [2, false]])


func test_results_and_apply_progress_on_every_peer() -> void:
	var b := _multi(3)
	var host := _host(b)
	Kit.start(b)
	Kit.step(b, TINY_TICKS + COOLDOWN_TICKS + 5)
	assert_eq(host.state, "results")
	for i in 2:
		var c := _client(b, i)
		assert_eq(c.state, "results")
		assert_not_null(c.final_results())
		assert_eq(c.final_results().grade, "B")
		assert_eq(c.final_results().rows.size(), 3)
		assert_eq(c.game.get("progress_calls"), 1, "apply_progress once per peer")
		assert_eq(c.game.get("results_count"), 0, "results() runs on the host only")
		assert_eq(c.unlocks, ["fx_badge"])
		assert_true(FileAccess.file_exists(c.ctx.progress.path))
		assert_ne(c.ctx.progress.path, host.ctx.progress.path, "each rider's own store")
		assert_eq(int(_rider(b, i + 2).get("finished_rides")), 1, "each client saves its own FIT")
	assert_eq(host.game.get("progress_calls"), 1)
	# A duplicate results message applies nothing twice.
	(b["nets"][0] as WlNetSession).send_to(2, Protocol.game_msg("results", {"results": host.final_results().to_dict()}))
	Kit.step(b, 1)
	assert_eq(_client(b, 0).game.get("progress_calls"), 1)


func test_restarted_client_gets_exactly_one_apply_progress() -> void:
	var b := _multi(2)
	var host := _host(b)
	Kit.start(b)
	Kit.step(b, TINY_TICKS + 100)
	# Peer 2 restarts during the cool-down: a fresh GameHost on the same net.
	var old := _client(b, 0)
	(b["hub"] as RefCounted).call("drop", 2)
	Kit.step(b, 2)
	old.end_session("restart")
	var c := GameHost.new()
	_root.add_child(c)
	var err := c.setup({
		"role": Wl.CLIENT, "local_peer": 2, "local_riders": {2: _rider(b, 2)}, "net": b["nets"][1],
		"bus": Kit.new_bus(_root, "RestartBus"), "registry": b["registry"], "headless": true, "realtime": false,
		"progress_path": str(b["tmp"]).path_join("p2/games/fx_solo/progress.json"),
	})
	assert_eq(err, "")
	(b["hub"] as RefCounted).call("rejoin", 2)
	for k in COOLDOWN_TICKS:
		host.step()
		c.step()
		if c.final_results() != null:
			break
	assert_not_null(c.final_results())
	assert_eq(c.game.get("progress_calls"), 1)
	assert_eq(int(old.game.get("progress_calls")), 0, "the killed process never applied it")


func test_a_restarted_client_catches_up_with_its_phase_clock() -> void:
	var b := _multi(2)
	var host := _host(b)
	Kit.start(b)
	Kit.step(b, 300)
	assert_eq(host.tracker.index_of(2), 2, "tiny's 30 s SIM phase, started at 5 s")
	var old := _client(b, 0)
	(b["hub"] as RefCounted).call("drop", 2)
	Kit.step(b, 2)
	old.end_session("restart")
	var c := GameHost.new()
	_root.add_child(c)
	assert_eq(c.setup({
		"role": Wl.CLIENT, "local_peer": 2, "local_riders": {2: _rider(b, 2)}, "net": b["nets"][1],
		"bus": Kit.new_bus(_root, "RestartBus"), "registry": b["registry"], "headless": true, "realtime": false,
		"progress_path": str(b["tmp"]).path_join("p2r/games/fx_solo/progress.json"),
	}), "")
	(b["hub"] as RefCounted).call("rejoin", 2)
	host.step()
	c.step()
	var mine := c.local_phase_state()
	var theirs := host.tracker.state(2)
	assert_eq(mine.index, theirs.index)
	assert_almost_eq(mine.elapsed_s, theirs.elapsed_s, 0.11, "the rejoined client's phase clock is the host's")
	assert_gt(mine.elapsed_s, 9.0)
	assert_eq(mine.prev_ended_by, Wl.ENDED_DURATION, "how the phase it rejoined into started")


func test_client_rejects_an_invalid_plan() -> void:
	var b := _multi(2)
	Kit.start(b)
	Kit.step(b, 2)
	var bad := EffortPlan.of([PlanPhase.erg(Wl.WORK, 95, 60)])
	bad.add(PlanValidator.cooldown_phase())
	bad.cooldown_appended = true
	(b["nets"][0] as WlNetSession).send_to(2, Protocol.game_msg("plan", {"peer": 2, "plan": bad.to_dict()}))
	Kit.step(b, 1)
	assert_push_warning("rejected the host's plan")
	assert_eq((_rider(b, 2).get("plans_set") as Array).size(), 1, "the governor keeps the validated plan")


func test_phase_started_on_every_bus_without_cross_talk() -> void:
	var b := _multi(3)
	var per_bus: Array = [[], [], []]
	for i in 3:
		var idx := i
		(b["buses"][i] as WlEventBus).phase_started.connect(func(p: int, ix: int) -> void: per_bus[idx].append([p, ix]))
	Kit.start(b)
	Kit.step(b, 45)
	assert_eq(per_bus[0], [[1, 0], [2, 0], [3, 0], [1, 1], [2, 1], [3, 1]], "the host sees every rider")
	for i: int in [1, 2]:
		var own := i + 1
		var count_own := 0
		for e: Array in per_bus[i]:
			if int(e[0]) == own and int(e[1]) == 1:
				count_own += 1
		assert_eq(count_own, 1, "a client's own rider once (from its phase message)")
		assert_eq((per_bus[i] as Array).size(), 6, "and the others from events")
