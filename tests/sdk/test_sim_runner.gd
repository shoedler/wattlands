extends GutTest
## GameSimRunner, the engine of tools/run_game_sim and tools/screenshot (BRIEF 3.6, 7.1 "the
## tools/run_game_sim report schema, its SOLO and HOST roles and its paused and timeout
## endings"; docs/OWNERSHIP.md SIM1-SIM7, FIT2, FIT3, CTX16, C13, C19, C29). Riders are fake
## LocalRiders through args.rider_factory and HOST runs use FakeNet sessions through
## args.net_factory; tests/sdk/integration/ runs the real stack in W2.

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")
const FakeRider := preload("res://tests/sdk/helpers/fake_rider.gd")
const FakeNetHub := preload("res://tests/sdk/helpers/fake_net_hub.gd")
const REPORT_KEYS: Array[String] = [
	"schema", "args", "game_id", "content_id", "role", "seed", "slots", "plans", "plan_warnings",
	"overrides", "end_reason", "finished_reason", "sim_seconds", "game_seconds", "max_sim_seconds",
	"events", "phases", "directives", "trace", "snapshots", "max_snapshot_bytes",
	"oversize_snapshots", "results", "unlocks", "clients", "fit_paths", "meta", "deterministic_hash",
]

var _reg: WlGameRegistry = null
var _runners: Array[GameSimRunner] = []
var _tmp: String = ""
var _made: Array = []
## FakeNet hubs stay referenced here: a Callable holds no reference to its object.
var _hubs: Array = []


func before_each() -> void:
	_reg = Kit.registry()
	_tmp = Paths.make_temp_dir("wattlands_runner_test")
	Paths.set_override(_tmp)
	_made = []


func after_each() -> void:
	for r in _runners:
		if is_instance_valid(r):
			r.cleanup()
			r.free()
	_runners.clear()
	_hubs.clear()
	Paths.set_override("")
	Kit.remove_tree(_tmp)
	_reg.clear()
	_reg.free()


func _factory() -> Callable:
	return func(slot: PlayerSlot, profile: RiderProfile, spec: String, opts: Dictionary) -> LocalRider:
		var r: LocalRider = FakeRider.new()
		var dev := MockTrainer.from_spec(spec, slot.ftp, {"seed": 3})
		r.setup(slot.peer_id, profile, slot, dev, opts)
		r.add_child(dev)
		if spec.begins_with("zero"):
			r.set("follow_target", false)
			r.set("power_w", 0.0)
			r.set("cadence_rpm", 0.0)
			r.set("coast_after_ticks", 200)
		if not slot.is_bot:
			r.set("ride_dir", Paths.user_dir().path_join("rides"))
		_made.append(r)
		return r


func _args(extra: Dictionary = {}) -> Dictionary:
	var a := {"game": "fx_solo", "content": "tiny", "registry": _reg, "rider_factory": _factory(), "seed": 3}
	for k: Variant in extra.keys():
		a[k] = extra[k]
	return a


func _runner(extra: Dictionary = {}) -> GameSimRunner:
	var r := GameSimRunner.new()
	_runners.append(r)
	var err := r.setup(_args(extra))
	assert_eq(err, "", "setup")
	return r


func _host_net() -> Callable:
	var hub: RefCounted = FakeNetHub.new()
	_hubs.append(hub)
	return Callable(hub, "factory")


# --- parse_args ---------------------------------------------------------------------------


func test_parse_args_reads_every_flag() -> void:
	var a := GameSimRunner.parse_args(PackedStringArray([
		"--game=siege", "--content=hold_the_line", "--players=2", "--bots=1", "--rider=erg:compliance=0.9",
		"--rider=zero", "--sim-speed=200", "--seed=7", "--report=build/x.json", "--autopilot=0,1",
		"--ftp=180,220", "--unverified", "--haptics-off=1", "--options={\"rotation\":true}",
		"--player-options=[{\"wave_offset\":-3},{}]", "--max-sim-seconds=900", "--at=10,20.5",
		"--screenshot-dir=build/shots",
	]))
	assert_false(a.has("error"), str(a.get("error", "")))
	assert_eq(a["game"], "siege")
	assert_eq(a["content"], "hold_the_line")
	assert_eq(a["players"], 2)
	assert_eq(a["bots"], 1)
	assert_eq(a["riders"], ["erg:compliance=0.9", "zero"] as Array[String], "--rider repeats, never comma-joined")
	assert_eq(a["sim_speed"], 200.0)
	assert_eq(a["seed"], 7)
	assert_eq(a["report"], "build/x.json")
	assert_eq(a["autopilot"], [0, 1] as Array[int])
	assert_eq(a["ftp"], [180.0, 220.0] as Array[float])
	assert_true(a["unverified"])
	assert_eq(a["haptics_off"], [1] as Array[int])
	assert_eq(a["options"], {"rotation": true})
	assert_eq((a["player_options"] as Array).size(), 2)
	assert_eq(a["max_sim_seconds"], 900.0)
	assert_eq(a["at"], [10.0, 20.5] as Array[float])
	assert_eq(a["screenshot_dir"], "build/shots")


func test_parse_args_defaults() -> void:
	var a := GameSimRunner.parse_args(PackedStringArray(["--game=workout"]))
	assert_eq(a["players"], 1)
	assert_eq(a["bots"], 0)
	assert_eq(a["autopilot"], "all")
	assert_eq(a["ftp"], [] as Array[float])
	assert_false(a["unverified"])
	assert_true(a["headless"])
	assert_eq(GameSimRunner.parse_args(PackedStringArray(["--game=x", "--windowed"]))["headless"], false)


func test_parse_args_errors_name_the_flag() -> void:
	var cases := [
		[["--nope=1"], "--nope:"],
		[["--players=0"], "--players:"],
		[["--players=two"], "--players:"],
		[["--bots=-1"], "--bots:"],
		[["--seed=1.5"], "--seed:"],
		[["--ftp=200,abc"], "--ftp:"],
		[["--ftp=0"], "--ftp:"],
		[["--autopilot=some"], "--autopilot:"],
		[["--options=[1]"], "--options:"],
		[["--options={bad"], "--options:"],
		[["--player-options={}"], "--player-options:"],
		[["--player-options=[1]"], "--player-options:"],
		[["--override=build/does_not_exist.json"], "--override:"],
		[["--max-sim-seconds=0"], "--max-sim-seconds:"],
		[["--game=a", "--game=b"], "--game:"],
		[["--sim-speed=-2"], "--sim-speed:"],
		[["--haptics-off=x"], "--haptics-off:"],
		[["players=2"], "players=2:"],
	]
	for c: Array in cases:
		var a := GameSimRunner.parse_args(PackedStringArray(c[0]))
		assert_true(a.has("error"), str(c[0]))
		assert_true(str(a.get("error", "")).begins_with(str(c[1])), "%s -> %s" % [str(c[0]), str(a.get("error", ""))])


func test_parse_args_reads_the_override_file() -> void:
	var path := _tmp.path_join("ov.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"levels.json": {"speed_scale": 9}}))
	f.close()
	var a := GameSimRunner.parse_args(PackedStringArray(["--game=fx_solo", "--override=%s" % path]))
	assert_eq(a["override"], {"levels.json": {"speed_scale": 9.0}})
	assert_eq(a["override_path"], path)


# --- setup -----------------------------------------------------------------------------


func test_setup_errors_name_the_flag() -> void:
	var cases := [
		[{"game": ""}, "--game:"],
		[{"game": "nope"}, "--game:"],
		[{"content": "zzz"}, "--content:"],
		[{"players": 5}, "--players:"],
		[{"players": 1, "bots": 4}, "--players:"],
		[{"game": "fx_crew", "bots": 1}, "--bots:"],
		[{"players": 2, "riders": ["erg", "erg", "erg"]}, "--rider:"],
		[{"ftp": [200.0, 210.0, 220.0], "players": 2, "bots": 2}, "--ftp:"],
		[{"autopilot": [3]}, "--autopilot:"],
		[{"haptics_off": [7]}, "--haptics-off:"],
		[{"options": {"nope": 1}}, "--options.nope:"],
		[{"options": {"speed": 9}}, "--options.speed:"],
		[{"player_options": [{}, {}]}, "--player-options:"],
		[{"player_options": [{"reel_pct": 62}]}, "--player-options[0].reel_pct:"],
		[{"override": {"missing.json": {}}}, "--override:"],
		[{"content": "bad"}, "plan for peer 1"],
		[{"error": "--x: bad"}, "--x: bad"],
	]
	for c: Array in cases:
		var r := GameSimRunner.new()
		_runners.append(r)
		var err := r.setup(_args(c[0]))
		assert_true(err.begins_with(str(c[1])), "%s -> %s" % [JSON.stringify(c[0]).left(80), err])


func test_invalid_rider_profile_is_a_setup_error() -> void:
	var r := GameSimRunner.new()
	_runners.append(r)
	assert_string_starts_with(r.setup(_args({"riders": ["bogus"]})), "--rider:")
	assert_push_error("invalid profile spec")


func test_one_human_with_bots_runs_solo() -> void:
	var r := _runner({"players": 1, "bots": 2, "ftp": [250.0], "unverified": true, "haptics_off": [2], "autopilot": "none"})
	assert_eq(r.role, Wl.SOLO)
	assert_eq(r.clients.size(), 0)
	assert_eq(r.host.ctx.role, Wl.SOLO)
	assert_eq(r.slots.size(), 3)
	var human := r.slots[0]
	assert_eq(human.peer_id, 1)
	assert_eq(human.ftp, 250.0)
	assert_false(human.ftp_verified, "--unverified")
	assert_false(human.autopilot, "--autopilot=none")
	assert_false(human.is_bot)
	var bot := r.slots[2]
	assert_eq(bot.peer_id, -2)
	assert_eq(bot.name, "Bot 2")
	assert_true(bot.ftp_verified, "bots stay verified")
	assert_true(bot.autopilot)
	assert_eq(bot.ftp, 250.0, "bots ride the first human's FTP")
	assert_false(bot.haptics_on, "--haptics-off=2")
	assert_eq(r.slot_specs, ["erg"] as Array[String])
	assert_eq(r.riders.size(), 3)
	assert_eq(bool((r.riders[1] as Object).get("options")["multiplayer"]), false, "SOLO riders pause when coasting")


func test_two_humans_run_host_with_loopback_clients() -> void:
	var r := _runner({"players": 2, "bots": 1, "riders": ["erg", "erg:compliance=0.9"], "net_factory": _host_net(), "autopilot": [1]})
	assert_eq(r.role, Wl.HOST)
	assert_eq(r.clients.size(), 1)
	assert_eq(r.nets.size(), 2)
	assert_eq(r.slots[1].peer_id, 2)
	assert_false(r.slots[0].autopilot)
	assert_true(r.slots[1].autopilot)
	assert_eq(r.slot_specs, ["erg", "erg:compliance=0.9"] as Array[String])
	for i in 5:
		r.step()
	assert_eq(r.clients[0].ctx.role, Wl.CLIENT)
	assert_eq(r.clients[0].ctx.local_peer, 2)
	assert_eq(bool((r.riders[2] as Object).get("options")["multiplayer"]), true)


func test_complete_end_report_and_fit_files() -> void:
	var report_path := _tmp.path_join("out/run1.json")
	var r := _runner({"players": 1, "bots": 1, "report": report_path})
	assert_almost_eq(r.max_sim_seconds, 2.0 + 3.0 + 30.0 + 6.0 + 180.0 + 600.0, 1e-6, "worst-case plan + 600 s")
	var end := r.run_to_end()
	assert_eq(end, "complete")
	var rep := r.build_report()
	for k in REPORT_KEYS:
		assert_true(rep.has(k), "report key " + k)
	assert_eq(rep["schema"], GameSimRunner.REPORT_SCHEMA)
	assert_eq(rep["end_reason"], "complete")
	assert_eq(rep["role"], Wl.SOLO)
	assert_eq((rep["slots"] as Array).size(), 2)
	assert_eq(rep["slots"][1]["rider"], Bots.RIDER_SPEC)
	assert_true((rep["plans"] as Dictionary).has("1"))
	assert_true((rep["phases"] as Dictionary).has("-1"))
	assert_eq((rep["phases"]["1"] as Array).size(), 5)
	assert_eq(rep["phases"]["1"][4]["kind"], Wl.COOLDOWN)
	assert_gt((rep["trace"]["1"] as Array).size(), 200)
	assert_gt((rep["snapshots"] as Array).size(), 2000)
	assert_eq(rep["results"]["grade"], "B")
	var fit := _tmp.path_join("out/fit/run1_slot0.fit")
	assert_eq(rep["fit_paths"], [fit], "one FIT per human slot, none for bots")
	assert_true(FileAccess.file_exists(fit))
	assert_eq(str(rep["deterministic_hash"]).length(), 64)
	var written := r.write_report()
	assert_eq(written, report_path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(written))
	assert_true(parsed is Dictionary)
	assert_eq(str(parsed["deterministic_hash"]), str(rep["deterministic_hash"]))


func _has_keys(d: Variant, keys: Array, what: String) -> void:
	assert_true(d is Dictionary, what)
	if not (d is Dictionary):
		return
	for k: String in keys:
		assert_true((d as Dictionary).has(k), "%s.%s" % [what, k])


func test_report_schema_nested_keys_sim4() -> void:
	var r := _runner({"players": 1, "bots": 1, "report": _tmp.path_join("schema.json"), "max_sim_seconds": 12.0})
	r.host.game.set("on_step", func(g: GameModule, frame: InputFrame) -> void:
		if frame.tick == 50:
			g.ctx.directives.request(1, EffortDirective.from_dict({"target_pct": 58}))
			g.ctx.directives.request(1, EffortDirective.from_dict({"target_pct": 99})))
	r.run_to_end()
	var path := r.write_report()
	var rep: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_has_keys(rep, REPORT_KEYS, "report")
	_has_keys(rep["args"], ["game", "content", "players", "bots", "riders", "seed", "autopilot", "ftp", "unverified", "haptics_off", "options", "player_options", "override", "max_sim_seconds"], "args")
	for s: Variant in rep["slots"]:
		_has_keys(s, ["slot", "peer", "name", "is_bot", "ftp", "ftp_verified", "rider", "autopilot", "haptics_on", "options"], "slots[]")
	for peer: String in ["1", "-1"]:
		assert_true((rep["plans"] as Dictionary).has(peer), "plans." + peer)
		assert_true((rep["plan_warnings"] as Dictionary).has(peer), "plan_warnings." + peer)
		for ph: Variant in rep["phases"][peer]:
			_has_keys(ph, ["index", "kind", "start", "end", "ended_by"], "phases[]")
		var trace: Array = rep["trace"][peer]
		assert_eq(trace.size(), 12, "1 Hz over 12 s")
		_has_keys(trace[0], ["t", "phase", "kind", "mode", "applied_target_w", "applied_pct", "applied_grade_pct", "clamped_by", "rescue", "afk", "paused", "haptic", "power_w", "cadence_rpm"], "trace[]")
	var dirs: Array = rep["directives"]
	assert_eq(dirs.size(), 2)
	for d: Variant in dirs:
		_has_keys(d, ["id", "peer", "t", "kind", "requested", "accepted", "reason", "applied"], "directives[]")
		_has_keys(d["applied"], ["id", "kind", "requested", "applied", "clamped_by", "refused", "reason", "t"], "directives[].applied")
	assert_eq(str(dirs[1]["reason"]), Wl.REFUSE_RANGE, "the refusal reason")
	assert_true(bool(dirs[1]["applied"]["refused"]))
	assert_push_warning("outside_range_pct")
	for s: Variant in rep["snapshots"]:
		_has_keys(s, ["seq", "tick", "sha256", "bytes"], "snapshots[]")
	var biggest := 0
	for s: Variant in rep["snapshots"]:
		biggest = maxi(biggest, int(s["bytes"]))
	assert_eq(int(rep["max_snapshot_bytes"]), biggest)
	for e: Variant in rep["events"]:
		_has_keys(e, ["t", "pt", "type"], "events[]")
	_has_keys(rep["results"], ["grade", "score", "summary_key", "rows", "team", "session_id"], "results")
	_has_keys(rep["meta"], ["wall_s", "utc_start_unix"], "meta")
	assert_eq(str(rep["deterministic_hash"]).length(), 64)


func test_timeout_end_still_writes_results_and_fit() -> void:
	var r := _runner({"max_sim_seconds": 10.0, "report": _tmp.path_join("t.json")})
	assert_eq(r.run_to_end(), "timeout")
	assert_almost_eq(r.sim_seconds(), 10.0, 1e-6)
	assert_not_null(r.host.final_results())
	assert_true(FileAccess.file_exists(_tmp.path_join("fit/t_slot0.fit")))
	assert_eq(r.build_report()["end_reason"], "timeout")


func test_zero_rider_pauses_in_solo_and_ends_paused() -> void:
	var r := _runner({"riders": ["zero"], "report": _tmp.path_join("p.json")})
	assert_eq(r.run_to_end(), "paused")
	assert_almost_eq(r.sim_seconds(), 10.0 + 120.0, 0.06, "paused at 10 s, ended 120 s of platform time later")
	assert_not_null(r.host.final_results(), "results() on every ending")
	assert_true(FileAccess.file_exists(_tmp.path_join("fit/p_slot0.fit")))
	var types: Array = []
	for e: Dictionary in r.build_report()["events"]:
		types.append(str(e["type"]))
	assert_has(types, "paused")


func test_zero_rider_goes_afk_in_host() -> void:
	var r := _runner({"players": 2, "riders": ["erg", "zero"], "net_factory": _host_net(), "max_sim_seconds": 20.0})
	assert_eq(r.run_to_end(), "timeout", "a HOST run never pauses")
	assert_has(r.host.game.get("afk_log"), [2, true])
	assert_false(r.host.is_paused())
	assert_not_null(r.clients[0].final_results(), "the client got the results")


func test_same_args_same_hash_solo_and_host() -> void:
	var h: Array[String] = []
	for i in 2:
		var r := _runner({"players": 1, "bots": 2, "max_sim_seconds": 30.0})
		r.run_to_end()
		h.append(str(r.build_report()["deterministic_hash"]))
	assert_eq(h[0], h[1], "SOLO")
	var hh: Array[String] = []
	for i in 2:
		var r := _runner({"players": 2, "net_factory": _host_net(), "max_sim_seconds": 30.0})
		r.run_to_end()
		hh.append(str(r.build_report()["deterministic_hash"]))
	assert_eq(hh[0], hh[1], "HOST")
	var other := _runner({"players": 1, "bots": 2, "max_sim_seconds": 30.0, "seed": 4})
	other.run_to_end()
	assert_ne(str(other.build_report()["deterministic_hash"]), h[0], "another seed, another hash")


func test_override_reaches_content_and_the_report() -> void:
	var r := _runner({"override": {"levels.json": {"speed_scale": 9}}})
	assert_eq(float(r.host.game.get("content")["speed_scale"]), 9.0)
	r.run_to_end()
	assert_eq(r.build_report()["overrides"], {"levels.json": {"speed_scale": 9}})


func test_runs_are_isolated_in_a_temp_profile() -> void:
	var r := _runner({"players": 2, "net_factory": _host_net(), "max_sim_seconds": 5.0})
	assert_eq(Paths.user_dir(), r.temp_root(), "every persisted file goes under the run's temp root")
	assert_ne(r.host.ctx.progress.path, r.clients[0].ctx.progress.path if r.clients[0].ctx != null else "")
	assert_string_contains(r.host.ctx.progress.path, "slot0/games/fx_solo/progress.json")
	r.run_to_end()
	assert_string_contains(r.clients[0].ctx.progress.path, "slot1/games/fx_solo/progress.json")
	r.cleanup()
	assert_eq(Paths.user_dir(), _tmp, "cleanup() restores the caller's override")


func test_fit_without_a_report_goes_to_the_temp_root() -> void:
	var r := _runner({"max_sim_seconds": 3.0})
	r.run_to_end()
	var fits: Array = r.build_report()["fit_paths"]
	assert_eq(fits.size(), 1)
	assert_string_ends_with(str(fits[0]), "fit/sim_slot0.fit")
	assert_true(FileAccess.file_exists(str(fits[0])))


func test_requested_directive_keys_round_trip_into_the_report() -> void:
	var r := _runner({"max_sim_seconds": 8.0})
	r.host.game.set("on_step", func(g: GameModule, frame: InputFrame) -> void:
		if frame.tick == 60:
			g.ctx.directives.request(1, EffortDirective.from_dict({"target_pct": 58, "duration_s": 1, "reason": "pull", "source": "fx"})))
	r.run_to_end()
	var dirs: Array = r.build_report()["directives"]
	assert_eq(dirs.size(), 1)
	assert_eq((dirs[0]["requested"] as Dictionary).keys(), ["target_pct", "duration_s", "reason", "source", "id"], "the game's keys plus duration_s and the sink's id (GAME_SDK 8.1, 19.1)")
	assert_not_null(dirs[0]["applied"])


## W3 QT-4: a runner freed without cleanup() (autofree in tests, a tool that forgot it) still
## deletes its wattlands_sim_* temp root under OS temp and restores Paths' override.
func test_freeing_a_runner_removes_its_temp_root() -> void:
	var r := GameSimRunner.new()
	var err := r.setup(_args())
	assert_eq(err, "", "setup")
	var root := r.temp_root()
	assert_ne(root, "")
	assert_true(DirAccess.dir_exists_absolute(root), "precondition: the run has its temp root")
	assert_eq(Paths.user_dir(), root, "precondition: Paths points at it")
	r.free()
	assert_false(DirAccess.dir_exists_absolute(root), "freeing the runner deleted %s" % root)
	assert_eq(Paths.user_dir(), _tmp, "and restored the previous override")
