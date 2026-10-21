extends GutTest
## W2 integration: GameSimRunner and SdkConformance over the real LocalRider, SafetyGovernor,
## MockTrainer, WlNetSession, LoopbackTransport and Protocol. In the sdk-runtime W1 worktree
## those are still W0 stubs, so this folder is excluded from the W1 test command and runs in
## W2 (full suite, -ginclude_subdirs). Each test names the BRIEF 7.1 / OWNERSHIP item it
## proves end to end.

const FIXTURES := "res://tests/fixtures/games"

var _regs: Array[WlGameRegistry] = []
var _runners: Array[GameSimRunner] = []
var _tmp: String = ""


func before_each() -> void:
	_tmp = Paths.make_temp_dir("wattlands_sdk_integration")
	Paths.set_override(_tmp)


func after_each() -> void:
	for r in _runners:
		if is_instance_valid(r):
			r.cleanup()
			r.free()
	_runners.clear()
	for reg in _regs:
		reg.clear()
		reg.free()
	_regs.clear()
	Paths.set_override("")
	_remove_tree(_tmp)


func _registry(sub: String) -> WlGameRegistry:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	reg.content_root = FIXTURES.path_join("_content")
	reg.scan(FIXTURES.path_join(sub))
	_regs.append(reg)
	return reg


func _run(args: Dictionary) -> GameSimRunner:
	var r := GameSimRunner.new()
	_runners.append(r)
	var a := {"game": "fx_conform", "content": "tiny", "registry": _registry("conform"), "seed": 5}
	for k: Variant in args.keys():
		a[k] = args[k]
	assert_eq(r.setup(a), "", "setup")
	return r


## SIM2/SIM3, GOV6: a compliant SOLO rider completes; the governor applies the plan.
func test_solo_erg_rider_completes_with_applied_targets_and_a_fit() -> void:
	var report := _tmp.path_join("solo.json")
	var r := _run({"report": report, "riders": ["erg"], "ftp": [200.0]})
	assert_eq(r.run_to_end(), "complete")
	var rep := r.build_report()
	var push_rows := 0
	for row: Dictionary in rep["trace"]["1"]:
		if int(row["phase"]) == 1 and str(row["mode"]) == Wl.ERG and float(row["t"]) >= 3.0:
			push_rows += 1
			assert_between(int(row["applied_target_w"]), 100, 130, "60% of 200 W, after slew")
	assert_gt(push_rows, 0)
	var fit := _tmp.path_join("fit/solo_slot0.fit")
	assert_true(FileAccess.file_exists(fit))
	var bytes := FileAccess.get_file_as_bytes(fit)
	assert_eq(bytes.slice(8, 12).get_string_from_ascii(), ".FIT")


## SIM2: a 0 W rider pauses in SOLO and the run ends `paused`.
func test_zero_rider_pauses_in_solo() -> void:
	var r := _run({"riders": ["zero"], "content": "short"})
	assert_eq(r.run_to_end(), "paused")
	assert_lte(r.sim_seconds(), 10.0 + 0.05 + 120.0 + 2.0, "paused 10 s after the first not_pedaling sample")


## SIM2, GM7: a 0 W rider goes AFK in HOST (two human slots) instead of pausing.
func test_zero_rider_goes_afk_in_host() -> void:
	var r := _run({"players": 2, "riders": ["erg", "zero"], "content": "short", "max_sim_seconds": 30.0})
	assert_eq(r.run_to_end(), "timeout")
	var afk := false
	for e: Dictionary in r.build_report()["events"]:
		if str(e["type"]) == "afk" and int(e["peer"]) == 2 and bool(e["afk"]):
			afk = true
	assert_true(afk)


## B7.1 loopback host + two clients: each client's governor follows its remote plan; results
## and FIT files on every human slot; SIM5 the same hash twice.
func test_host_with_two_loopback_clients() -> void:
	var hashes: Array[String] = []
	for i in 2:
		var r := _run({"players": 3, "report": _tmp.path_join("host%d.json" % i)})
		assert_eq(r.role, Wl.HOST)
		assert_eq(r.run_to_end(), "complete")
		for c in r.clients:
			assert_not_null(c.final_results())
			assert_eq(c.game.get("progress_calls"), 1)
			var rider: LocalRider = c.local_riders[c.local_peer()]
			assert_eq(int(rider.telemetry().phase_index), 4, "the client's governor reached the cool-down")
		var rep := r.build_report()
		assert_eq((rep["fit_paths"] as Array).size(), 3)
		hashes.append(str(rep["deterministic_hash"]))
	assert_eq(hashes[0], hashes[1])


## B7.3 conformance in HOST mode (bots false: Autopilot human slots over loopback).
func test_conformance_with_autopilot_human_slots() -> void:
	var reg := _registry("conform_host")
	var log: Array = []
	var errors := SdkConformance.check_game(reg, "fx_crewc", {}, log)
	for line: Variant in log:
		print(line)
	assert_eq(errors, [] as Array[String])


## GM13, PR1, C10: declared int fields survive the JSON round trip through the real Protocol.
func test_snapshot_int_fields_round_trip() -> void:
	var state := {"tick": 5, "r": [[1, 2], [3, 4]], "f": [[1, [7, 8]]], "name": "x"}
	assert_eq(SdkConformance.snapshot_errors(state, ["tick", "r[][]", "f[][]", "f[][][]"]), [] as Array[String])


static func _remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
