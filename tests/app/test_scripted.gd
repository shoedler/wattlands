extends "res://tests/app/app_test_base.gd"
## Scripted peers (docs/ARCHITECTURE.md "Scripted peers (end-to-end test contract)"): flag
## parsing, the stdout lines, auto ready-up, --wait-peers, Autopilot, the session through the
## GameHost, results, FIT, the Strava auto-upload, the report JSON and the exit codes, all with
## test doubles.

var lines: Array[String] = []


func before_each() -> void:
	super.before_each()
	lines.clear()


func _config(args: Array[String]) -> AppScriptedConfig:
	return AppScriptedConfig.from_args(PackedStringArray(args))


func _peer(args: Array[String]) -> AppScriptedPeer:
	var p := AppScriptedPeer.new()
	p.services = fx.services
	p.config = _config(args)
	p.install_logger = false
	p.auto_process = false
	p.out = func(line: String) -> void: lines.append(line)
	add_child(p)
	_opened.append(p)
	return p


func _report_path() -> String:
	return fx.tmp_dir.path_join("out/report.json")


func _read_report() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_report_path()))
	return parsed if parsed is Dictionary else {}


# --- flags -------------------------------------------------------------------------------------

func test_not_scripted_without_host_or_join() -> void:
	var c := _config(["--mock-trainer=erg", "--autopilot"])
	assert_false(c.enabled)


func test_host_flags() -> void:
	var c := _config(["--host", "--game=workout", "--e2e", "--wait-peers=3", "--relay=ws://127.0.0.1:8787/v1",
		"--mock-trainer=erg:compliance=0.9", "--autopilot", "--profile-dir=C:/tmp/p1", "--seed=42",
		"--sim-speed=1", "--report=C:/tmp/r.json", "--run-seconds=600"])
	assert_true(c.is_valid(), str(c.errors))
	assert_eq(c.role, Wl.HOST)
	assert_eq(c.game_id, "workout")
	assert_true(c.e2e)
	assert_eq(c.wait_peers, 3)
	assert_eq(c.relay, "ws://127.0.0.1:8787/v1")
	assert_eq(c.mock_trainer, "erg:compliance=0.9")
	assert_true(c.autopilot)
	assert_eq(c.profile_dir, "C:/tmp/p1")
	assert_true(c.has_seed)
	assert_eq(c.seed, 42)
	assert_eq(c.sim_speed, 1.0)
	assert_eq(c.report_path, "C:/tmp/r.json")
	assert_eq(c.run_seconds, 600.0)


func test_join_flags_normalise_the_code() -> void:
	var c := _config(["--join=k7q-x2m", "--strava-base=http://127.0.0.1:9100", "--strava-client-id=123",
		"--strava-client-secret=s3cret", "--strava-auto-upload"])
	assert_true(c.is_valid(), str(c.errors))
	assert_eq(c.role, Wl.CLIENT)
	assert_eq(c.join_code, "K7QX2M")
	assert_true(c.wants_strava_connect())
	assert_true(c.strava_auto_upload)
	assert_false(JSON.stringify(c.describe()).contains("s3cret"), "describe() never holds the secret")


func test_bad_flags() -> void:
	assert_false(_config(["--host"]).is_valid(), "--host needs --game")
	assert_false(_config(["--host", "--join=K7QX2M", "--game=workout"]).is_valid())
	assert_false(_config(["--join=nope"]).is_valid())
	assert_false(_config(["--host", "--game=workout", "--wait-peers=0"]).is_valid())
	assert_false(_config(["--host", "--game=workout", "--sim-speed=0"]).is_valid())
	assert_false(_config(["--host", "--game=workout", "--seed=x"]).is_valid())
	assert_false(_config(["--join=K7QX2M", "--strava-client-id=1"]).is_valid(), "id without secret")


func test_non_loopback_strava_base_is_refused_while_locked() -> void:
	if not Locks.network_locked():
		pending("network lock not set in this run")
		return
	var c := _config(["--join=K7QX2M", "--strava-base=https://www.strava.com"])
	assert_false(c.is_valid())
	assert_true(c.errors[0].contains(Locks.NET_MESSAGE))


func test_content_resolution() -> void:
	var m := FakeRegistry.workout()
	assert_eq(AppLobbyModel.scripted_content(m, "", true), "e2e")
	assert_eq(AppLobbyModel.scripted_content(m, "", false), "easy_30")
	assert_eq(AppLobbyModel.scripted_content(m, "sweet_spot", true), "sweet_spot")


func test_invalid_flags_quit_non_zero() -> void:
	var p := _peer(["--host"])
	p.start()
	assert_eq(p.exit_code, AppScriptedPeer.EXIT_ERROR)
	assert_true(lines[lines.size() - 1].begins_with("WATTLANDS_DONE error:flags"))
	assert_eq(fx.quits, [1] as Array[int])


# --- host --------------------------------------------------------------------------------------

func _host(extra: Array[String] = []) -> AppScriptedPeer:
	var args: Array[String] = ["--host", "--game=workout", "--e2e", "--autopilot", "--mock-trainer=erg",
		"--report=" + _report_path()]
	args.append_array(extra)
	var p := _peer(args)
	fx.fake_net().add_human(1, "Rider")
	p.start()
	return p


func test_host_flow_to_a_complete_report() -> void:
	var p := _host()
	assert_eq(fx.fake_net().last_call("host_room"), ["host_room", 8])
	assert_true(fx.settings.profile.created, "a profile is created when the dir has none")
	assert_true(fx.settings.profile.autopilot_default, "--autopilot")
	fx.fake_net().simulate_hosting("K7QX2M")
	assert_eq(lines.slice(0, 3), ["WATTLANDS_ROOM K7QX2M", "WATTLANDS_PEER 1", "WATTLANDS_STATE lobby"])
	assert_eq(fx.fake_net().last_call("set_game"), ["set_game", "workout", "1.0.0", "e2e"])
	assert_eq(fx.fake_net().last_call("set_ready"), ["set_ready", true], "ready automatically")
	assert_true(fx.fake_net().info["autopilot"])
	assert_eq(p.phase, "session", "alone and ready with --wait-peers=1: started")
	var h := fx.last_host()
	assert_eq(h.config_seen["role"], Wl.HOST)
	assert_eq(h.config_seen["content_id"], "e2e")
	assert_eq(h.config_seen["net"], fx.net)
	assert_true(h.started)
	assert_true(lines.has("WATTLANDS_STATE running"))
	fx.bus.phase_started.emit(1, 0)
	h.game.send_event({"type": "wave", "n": 1})
	fx.bus.directive_applied.emit(1, {"id": 3, "kind": "request", "t": 1.0, "applied": {"target_pct": 60}})
	(fx.trainer.local_rider() as FakeRider).directive_applied.emit({"id": 3, "kind": "request", "t": 1.0, "applied": {"target_pct": 60}})
	(fx.trainer.local_rider() as FakeRider).tm.mode = Wl.ERG
	(fx.trainer.local_rider() as FakeRider).tm.applied_target_w = 130
	p.step(0.5)
	p.step(1.0)
	h.fits = {1: "C:/rides/host.fit"}
	var r := GameResults.new()
	r.grade = "A"
	r.session_id = "s1"
	h.finish_with(r)
	assert_true(lines.has("WATTLANDS_STATE results"))
	assert_eq(p.phase, "closing", "the host lingers so its results reach the clients")
	p.step(1.0)
	assert_eq(p.phase, "closing")
	p.step(1.5)
	assert_eq(p.phase, "done")
	assert_eq(p.exit_code, 0)
	assert_eq(lines[lines.size() - 1], "WATTLANDS_DONE complete")
	assert_eq(fx.quits, [0] as Array[int])
	var rep := _read_report()
	assert_eq(rep["role"], Wl.HOST)
	assert_eq(int(rep["peer_id"]), 1)
	assert_eq(rep["room"], "K7QX2M")
	assert_eq(rep["game_id"], "workout")
	assert_eq(rep["content_id"], "e2e")
	assert_eq(rep["exit_reason"], "complete")
	assert_eq(rep["fit_paths"], ["C:/rides/host.fit"])
	assert_eq((rep["directives"] as Array).size(), 1, "bus and rider records deduplicated")
	assert_gte((rep["trace"] as Array).size(), 2, "1 Hz trace")
	var tr: Dictionary = rep["trace"][0]
	for k: String in ["t", "mode", "applied_target_w", "applied_pct", "applied_grade_pct", "warmup_active", "clamped_by", "rescue", "afk"]:
		assert_true(tr.has(k), "trace has %s" % k)
	assert_eq(tr["mode"], Wl.ERG)
	var types: Array = []
	for e: Variant in rep["events"]:
		types.append((e as Dictionary)["type"])
	assert_true(types.has("session_state"))
	assert_true(types.has("phase_started"))
	assert_true(types.has("game_event"))
	assert_true(types.has("results"))
	assert_eq(int(rep["desync_warnings"]), 0)
	assert_eq(int(rep["script_errors"]), 0)
	assert_eq(rep["final_state"]["grade"], "A")
	assert_eq(rep["final_state"]["snapshot"], {"tick": 7.0}, "the host's game snapshot")
	assert_eq(rep["uploads"], [])


func test_host_waits_for_peers() -> void:
	var p := _host(["--wait-peers=2"])
	var net := fx.fake_net()
	net.simulate_hosting("K7QX2M")
	assert_eq(p.phase, "lobby", "only one human")
	net.add_human(2, "Bea")
	net.lobby_changed.emit(net.lobby)
	assert_eq(p.phase, "lobby", "Bea is not ready")
	net.ready_flags[2] = true
	p.step(0.05)
	assert_eq(p.phase, "session")


func test_seed_and_sim_speed_reach_the_game_host() -> void:
	_host(["--seed=99", "--sim-speed=2"])
	fx.fake_net().simulate_hosting("K7QX2M")
	var c := fx.last_host().config_seen
	assert_eq(c["seed"], 99)
	assert_eq(c["sim_speed"], 2.0)


func test_unknown_game_fails() -> void:
	var p := _peer(["--host", "--game=kart"])
	p.start()
	assert_eq(p.exit_code, AppScriptedPeer.EXIT_ERROR)
	assert_true(p.exit_reason.begins_with("error:unknown_game"))


func test_run_seconds_hard_stop() -> void:
	var p := _host(["--run-seconds=30", "--wait-peers=2"])
	fx.fake_net().simulate_hosting("K7QX2M")
	p.step(29.9)
	assert_eq(p.phase, "lobby")
	p.step(0.2)
	assert_eq(p.exit_code, AppScriptedPeer.EXIT_TIMEOUT)
	assert_eq(lines[lines.size() - 1], "WATTLANDS_DONE run_seconds")
	assert_eq(_read_report()["exit_reason"], "run_seconds")


func test_run_seconds_mid_session_ends_it_and_keeps_the_fit() -> void:
	var p := _host(["--run-seconds=10"])
	fx.fake_net().simulate_hosting("K7QX2M")
	var h := fx.last_host()
	h.fits = {1: "C:/rides/cut.fit"}
	p.step(10.0)
	assert_eq(h.ended_reasons, ["run_seconds"] as Array[String])
	assert_eq(p.exit_code, AppScriptedPeer.EXIT_TIMEOUT)
	assert_eq(_read_report()["fit_paths"], ["C:/rides/cut.fit"])


# --- client ------------------------------------------------------------------------------------

func _client(extra: Array[String] = []) -> AppScriptedPeer:
	var args: Array[String] = ["--join=K7Q-X2M", "--autopilot", "--mock-trainer=erg", "--report=" + _report_path()]
	args.append_array(extra)
	var p := _peer(args)
	var net := fx.fake_net()
	net.add_human(1, "Host")
	net.add_human(2, "Rider")
	p.start()
	return p


static func _lobby() -> Dictionary:
	return {"game_id": "workout", "game_version": "1.0.0", "content_id": "e2e", "scaling": Wl.FAIR_FTP, "settings": {}}


static func _start_msg() -> Dictionary:
	var a := PlayerSlot.new()
	a.peer_id = 1
	var b := PlayerSlot.new()
	b.peer_id = 2
	b.apply_look(1)
	return {"type": "session_start", "v": 1, "game_id": "workout", "game_version": "1.0.0", "content_id": "e2e",
		"seed": 5, "players": [a.to_dict(), b.to_dict()], "options": {}, "scaling": Wl.FAIR_FTP, "start_tick": 0}


func test_client_flow() -> void:
	var p := _client()
	var net := fx.fake_net()
	assert_eq(net.last_call("join_room"), ["join_room", "K7QX2M"])
	net.simulate_joined(2, "K7QX2M", _lobby())
	assert_eq(lines.slice(0, 2), ["WATTLANDS_PEER 2", "WATTLANDS_STATE lobby"])
	assert_eq(net.last_call("set_ready"), ["set_ready", true])
	assert_eq(net.info["player_options"], {"offset": 0}, "player options for the host's game")
	net.receive(1, _start_msg())
	assert_eq(p.phase, "session")
	var h := fx.last_host()
	assert_eq(h.config_seen["role"], Wl.CLIENT)
	assert_eq(h.config_seen["seed"], 5)
	net.receive(1, {"type": "event", "v": 1, "seq": 1, "events": [{"type": "phase_started", "peer": 2, "index": 0}, {"type": "wave", "n": 2}]})
	net.receive(1, {"type": "snapshot", "v": 1, "game_id": "workout", "seq": 3, "state": {"tick": 40}})
	h.fits = {2: "C:/rides/client.fit"}
	h.finish_with(GameResults.new())
	assert_eq(p.exit_code, 0, "a client finishes right after its results")
	var rep := _read_report()
	assert_eq(rep["role"], Wl.CLIENT)
	assert_eq(int(rep["peer_id"]), 2)
	var game_events: Array = []
	for e: Variant in rep["events"]:
		if (e as Dictionary)["type"] == "game_event":
			game_events.append(e)
	assert_eq(game_events.size(), 1, "platform events in the batch are not game events")
	assert_eq(game_events[0]["event_type"], "wave")
	assert_eq(rep["final_state"]["snapshot"], {"tick": 40.0})


func test_client_rejoin_replays_the_session() -> void:
	var p := _client()
	var net := fx.fake_net()
	net.simulate_joined(2, "K7QX2M", _lobby())
	var seen: Array = []
	net.game_message.connect(func(from: int, data: Dictionary) -> void: seen.append(data["type"]))
	net.receive(1, {"type": "phase", "v": 1, "index": 3, "start_tick": 500, "ended_by": "duration"})
	assert_eq(p.phase, "session", "a restarted client's plan/phase/snapshot reopens the session")
	assert_eq(seen, ["phase", "phase"], "the message was replayed to the new GameHost")
	assert_eq(fx.last_host().config_seen["role"], Wl.CLIENT)


func test_client_refused_exit_codes() -> void:
	var p := _client()
	fx.fake_net().refuse("session_in_progress")
	assert_eq(p.exit_code, AppScriptedPeer.EXIT_REFUSED)
	assert_eq(lines[lines.size() - 1], "WATTLANDS_DONE refused:session_in_progress")


func test_client_missing_game_is_refused() -> void:
	var p := _client()
	var lobby := _lobby()
	lobby["game_id"] = "kart"
	fx.fake_net().simulate_joined(2, "K7QX2M", lobby)
	assert_eq(p.exit_code, AppScriptedPeer.EXIT_REFUSED)
	assert_eq(p.exit_reason, "refused:missing_game")


func test_host_left_before_results_fails() -> void:
	var p := _client()
	var net := fx.fake_net()
	net.simulate_joined(2, "K7QX2M", _lobby())
	net.receive(1, _start_msg())
	net.refuse("host_left")
	assert_eq(p.exit_code, AppScriptedPeer.EXIT_HOST_LEFT)
	assert_eq(fx.last_host().ended_reasons, ["host_left"] as Array[String])


func test_host_left_after_results_is_ignored() -> void:
	var p := _client(["--strava-client-id=1", "--strava-client-secret=x", "--strava-auto-upload"])
	fx.fake_rides().connected = true
	var net := fx.fake_net()
	net.simulate_joined(2, "K7QX2M", _lobby())
	net.receive(1, _start_msg())
	fx.last_host().fits = {2: "C:/rides/c.fit"}
	fx.last_host().finish_with(GameResults.new())
	assert_eq(p.phase, "uploading")
	net.refuse("host_left")
	assert_eq(p.phase, "uploading", "the host may quit first")


# --- Strava ----------------------------------------------------------------------------------

func test_strava_connect_at_start_and_auto_upload() -> void:
	var p := _client(["--strava-base=http://127.0.0.1:9100", "--strava-client-id=777", "--strava-client-secret=zz-secret-zz", "--strava-auto-upload"])
	assert_eq(fx.fake_rides().connects, ["777"] as Array[String])
	assert_true(fx.settings.profile.strava_auto_upload)
	fx.fake_rides().connected = true
	fx.bus.strava_state_changed.emit("connected", "")
	var net := fx.fake_net()
	net.simulate_joined(2, "K7QX2M", _lobby())
	net.receive(1, _start_msg())
	var h := fx.last_host()
	fx.bus.ride_saved.emit("C:/rides/c.fit", {"ride_id": "u-1"})
	h.fits = {2: "C:/rides/c.fit"}
	h.finish_with(GameResults.new())
	assert_eq(p.phase, "uploading")
	assert_eq(fx.fake_rides().uploads.size(), 1)
	assert_eq(fx.fake_rides().uploads[0]["fit_path"], "C:/rides/c.fit")
	fx.bus.upload_state_changed.emit("u-1", "processing", "")
	assert_eq(p.phase, "uploading")
	fx.bus.upload_state_changed.emit("u-1", "uploaded", "activity 987654")
	assert_eq(p.exit_code, 0)
	var rep := _read_report()
	assert_eq((rep["uploads"] as Array).size(), 1)
	assert_eq(rep["uploads"][0]["state"], "uploaded")
	assert_eq(int(rep["uploads"][0]["activity_id"]), 987654)
	assert_false(FileAccess.get_file_as_string(_report_path()).contains("zz-secret-zz"), "no secret in the report")
	assert_false(lines.any(func(l: String) -> bool: return l.contains("zz-secret-zz")), "no secret on stdout")


func test_upload_failure_quits_non_zero() -> void:
	var p := _client(["--strava-client-id=1", "--strava-client-secret=x", "--strava-auto-upload"])
	fx.fake_rides().connected = true
	var net := fx.fake_net()
	net.simulate_joined(2, "K7QX2M", _lobby())
	net.receive(1, _start_msg())
	fx.last_host().fits = {2: "C:/rides/c.fit"}
	fx.last_host().finish_with(GameResults.new())
	fx.bus.upload_state_changed.emit("", "failed", "500")
	assert_eq(p.exit_code, AppScriptedPeer.EXIT_ERROR)
	assert_eq(p.exit_reason, "error:upload_failed")


func test_upload_timeout() -> void:
	var p := _client(["--strava-client-id=1", "--strava-client-secret=x", "--strava-auto-upload"])
	fx.fake_rides().connected = true
	var net := fx.fake_net()
	net.simulate_joined(2, "K7QX2M", _lobby())
	net.receive(1, _start_msg())
	fx.last_host().fits = {2: "C:/rides/c.fit"}
	fx.last_host().finish_with(GameResults.new())
	p.step(AppScriptedPeer.UPLOAD_TIMEOUT_S + 1.0)
	assert_eq(p.exit_reason, "error:upload_timeout")


func test_strava_connect_error_fails() -> void:
	var p := _client(["--strava-client-id=1", "--strava-client-secret=x"])
	fx.bus.strava_state_changed.emit("error", "denied")
	assert_eq(p.exit_reason, "error:strava_connect")


func test_no_fit_is_a_failure() -> void:
	var p := _client()
	var net := fx.fake_net()
	net.simulate_joined(2, "K7QX2M", _lobby())
	net.receive(1, _start_msg())
	fx.last_host().finish_with(GameResults.new())
	assert_eq(p.exit_reason, "error:no_fit")


func test_activity_id_parsing() -> void:
	assert_eq(AppScriptedPeer.activity_id_from("12345"), 12345)
	assert_eq(AppScriptedPeer.activity_id_from("activity 777 ok"), 777)
	assert_null(AppScriptedPeer.activity_id_from("duplicate"))


func test_main_runs_the_scripted_peer() -> void:
	var cfg := _config(["--join=K7QX2M", "--mock-trainer=erg"])
	var m := open_main(cfg)
	var sp := m.get("scripted") as AppScriptedPeer
	assert_not_null(sp)
	assert_eq(fx.fake_net().last_call("join_room"), ["join_room", "K7QX2M"])
	assert_true(current_screen(m) is AppScriptedScreen)
	fx.app.goto("picker")
	assert_true(current_screen(m) is AppScriptedScreen, "no menus in scripted mode")
	sp.finish("test", 0)


func test_report_dedupes_and_keeps_order() -> void:
	var r := AppScriptedReport.new()
	assert_true(r.add_directive(1, {"id": 1, "kind": "request", "t": 2.0}))
	assert_false(r.add_directive(1, {"id": 1, "kind": "request", "t": 2.0}))
	assert_true(r.add_directive(2, {"id": 1, "kind": "request", "t": 2.0}))
	r.add_event(1.0, "a", 1)
	r.add_event(2.0, "b", 1)
	var d := r.to_dict()
	assert_eq((d["events"] as Array)[0]["type"], "a")
	assert_eq((d["directives"] as Array).size(), 2)
	r.add_fit("x.fit")
	r.add_fit("x.fit")
	assert_eq(r.fit_paths, ["x.fit"])
