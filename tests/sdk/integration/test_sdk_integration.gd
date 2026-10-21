extends GutTest
## W2 integration: GameSimRunner and SdkConformance over the real LocalRider, SafetyGovernor,
## MockTrainer, WlNetSession, LoopbackTransport and Protocol. In the sdk-runtime W1 worktree
## those are still W0 stubs, so this folder is excluded from the W1 test command and runs in
## W2 (full suite, -ginclude_subdirs). Each test names the BRIEF 7.1 / OWNERSHIP item it
## proves end to end. These tests have never run: W2 must run them and, where a tolerance
## does not match the real governor or MockTrainer timing, fix the tolerance (never a 4.6 rule).

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


## qa W1: in a HOST run every loopback client joins the started session (none is refused with
## session_in_progress because its player_info was still in flight), so its rider rides and
## the host's roster shows its power, not 0 W.
func test_every_loopback_client_rides_and_reaches_the_host_roster() -> void:
	var r := _run({"players": 3, "max_sim_seconds": 40.0})
	assert_eq(r.nets[0].peers(), [1, 2, 3] as Array[int], "the host's lobby lists every rider")
	for n in r.nets:
		assert_eq(n.refusal_reason, "", "peer %d was not refused" % n.local_peer)
	assert_eq(r.run_to_end(), "timeout")
	var roster: Dictionary = r.host.ctx.roster
	for peer: int in [2, 3]:
		assert_true(roster.has(peer))
		assert_gt(float((roster[peer] as Dictionary)["raw_w"]), 50.0, "peer %d rides in the host's roster" % peer)
		assert_true(bool((roster[peer] as Dictionary)["connected"]))
	for c in r.clients:
		assert_eq(c.state, "ended")
		assert_gt(int(c.local_phase_state().index), -1, "client %d got its plan and phase" % c.local_peer())
		assert_true(c.ctx.roster.has(1), "the roster reached client %d" % c.local_peer())


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


## B7.1 "each client's governor follows ... phase changes caused by end_phase, course_grade
## and cadence_band" and "a host-side power_band reaching a client's ... MockTrainer", over the
## real LoopbackTransport (DS11, DS13, HUD7, Q10). Peer 2 rides "erg+band", so its cadence
## shows the published band; peer 3 rides "erg", which rides the power band's centre in SIM.
func test_directive_kinds_and_bands_reach_loopback_clients() -> void:
	var r := _run({"players": 3, "riders": ["erg", "erg+band", "erg"], "max_sim_seconds": 60.0})
	var c2: GameHost = r.clients[0]
	var c3: GameHost = r.clients[1]
	assert_eq(c2.local_peer(), 2)
	assert_eq(c3.local_peer(), 3)
	var bands: Array = []
	c2.bus.cadence_band_changed.connect(func(p: int, lo: float, hi: float) -> void: bands.append([p, lo, hi]))
	var ended := [false]
	r.host.game.set("on_step", func(g: GameModule, frame: InputFrame) -> void:
		var ps: PhaseState = frame.phase[2]
		if frame.tick == 10:
			g.ctx.directives.cadence_band(2, 60, 70)
		if ps.index == 2 and frame.tick % 10 == 0:
			g.ctx.directives.course_grade(2, 2.0)
		if ps.index == 2 and ps.elapsed_s >= 1.0 and ps.elapsed_s < 1.04:
			g.ctx.hud.power_band(3, 150, 170)
		if ps.index == 3 and ps.elapsed_s >= 2.0 and not ended[0]:
			for peer: int in frame.phase.keys():
				g.ctx.directives.end_phase(peer)
			ended[0] = true)
	assert_eq(r.run_to_end(), "timeout")
	assert_true(ended[0])
	assert_eq(bands[0], [2, 60.0, 70.0], "the client's HUD gets the band")
	assert_eq(bands[bands.size() - 1], [2, 0.0, 0.0], "the cool-down clears it")
	assert_eq(r.host.tracker.history(2)[3]["ended_by"], Wl.ENDED_END_PHASE)
	var phases2: Array = []
	for e: Dictionary in c2.report_data()["events"]:
		if str(e["type"]) == "phase_started" and int(e["peer"]) == 2:
			phases2.append([int(e["index"]), str(e["ended_by"])])
	assert_has(phases2, [4, Wl.ENDED_END_PHASE], "end_phase reached the client as its phase message")
	var graded := false
	var in_band := 0
	for row: Dictionary in c2.report_data()["trace"]["2"]:
		if int(row["phase"]) == 2 and absf(float(row["applied_grade_pct"])) > 0.01:
			graded = true
		if float(row["t"]) >= 8.0 and int(row["phase"]) < 4 and float(row["cadence_rpm"]) >= 58.0 and float(row["cadence_rpm"]) <= 72.0:
			in_band += 1
	assert_true(graded, "course_grade moved the client's applied SIM grade")
	assert_gt(in_band, 5, "MockTrainer's band policy rides the published cadence band")
	var near_centre := 0
	for row: Dictionary in c3.report_data()["trace"]["3"]:
		if int(row["phase"]) == 2 and float(row["t"]) >= 15.0 and absf(float(row["power_w"]) - 160.0) <= 12.0:
			near_centre += 1
	assert_gt(near_centre, 5, "peer 3's MockTrainer rides the power band's centre in SIM, not 90% FTP")


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
