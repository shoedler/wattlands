extends GutTest
## The rules-level balance harness runs (brief 4: "a GDScript tool runnable via tools/godot.sh -s,
## plus a GUT test asserting it runs"), and its T1-T5 evaluator is right on synthetic results.
## These tests check the harness, not the balance: whether the crews meet T1-T5 is the G2 tuning
## loop's question (tests/games/tank/sim/tank_balance_tool.gd prints it).


func _seg(seg: String, stage: int, dur: float, overran: bool = false) -> Dictionary:
	return {"seg": seg, "stage": stage, "dur_s": dur, "overran": overran}


## A synthetic compliant run result that meets every target.
func _good(
	crew: int = 3, seed_value: int = 1, score: float = 800.0, compliance: float = 1.0
) -> Dictionary:
	return {
		"crew": crew,
		"seed": seed_value,
		"compliance": compliance,
		"content": "ashfall_road",
		"score": score,
		"grade": "A",
		"breakdowns": 0,
		"segments":
		[
			_seg(TankIds.SEG_DEPOT, 0, 300.0),
			_seg(TankIds.SEG_ADVANCE, 1, 200.0),
			_seg(TankIds.SEG_GUN_LINE, 1, 100.0),
			_seg(TankIds.SEG_BOSS, 4, 250.0),
		],
		"dynamo":
		[
			{
				"index": 1,
				"seg": TankIds.SEG_ADVANCE,
				"stage": 1,
				"above80_s": 20.0,
				"back_to_65_s": 2.0
			},
			{
				"index": 2,
				"seg": TankIds.SEG_GUN_LINE,
				"stage": 1,
				"above80_s": 20.0,
				"back_to_65_s": 10.0
			},
			{
				"index": 3,
				"seg": TankIds.SEG_BOSS,
				"stage": 4,
				"above80_s": 80.0,
				"back_to_65_s": 20.0
			},
		],
		"shells":
		[
			{
				"t": 500.0,
				"seg": TankIds.SEG_GUN_LINE,
				"shell": TankIds.SHELL_HEAVY,
				"build_s": 26.0,
				"grade0_s": 8.0
			},
			{
				"t": 530.0,
				"seg": TankIds.SEG_DEPOT,
				"shell": TankIds.SHELL_HEAVY,
				"build_s": 5.0,
				"grade0_s": 1.0
			},
		],
		"drive_share": [{"index": 1, "stage": 1, "share": 0.7}],
	}


func test_the_harness_runs_the_drill_for_every_crew_and_is_deterministic() -> void:
	for crew in [1, 2, 3]:
		var a := TankBalanceHarness.run({"crew": crew, "seed": 5, "content": "drill"})
		assert_false(a.has("error"), str(a.get("error", "")))
		var segs: Array = a["segments"]
		assert_eq(
			segs.size(), 3, "the drill's three segments (the cool-down is not a plan segment)"
		)
		assert_eq(
			[segs[0]["seg"], segs[1]["seg"], segs[2]["seg"]],
			[TankIds.SEG_DEPOT, TankIds.SEG_SKIRMISH, TankIds.SEG_CHECKPOINT]
		)
		assert_almost_eq(float(segs[0]["dur_s"]), 30.0, 0.1)
		assert_almost_eq(float(segs[2]["dur_s"]), 30.0, 0.1)
		assert_gt(float(a["end_t"]), 130.0, "the cool-down follows")
		assert_has(["S", "A", "B", "C", "D"], a["grade"])
		assert_gt(int(a["cadence_bands"]), 0, "the director set cadence bands")
		assert_gt(int(a["snapshots"]), 0)
		assert_lte(int(a["max_snapshot_bytes"]), TankConst.SNAPSHOT_MAX_BYTES)
		var b := TankBalanceHarness.run({"crew": crew, "seed": 5, "content": "drill"})
		assert_eq(a["hash"], b["hash"], "crew %d: the same seed gives the same run" % crew)
		assert_eq(a["score"], b["score"])


func test_the_harness_reports_every_ashfall_road_segment_for_the_citadel() -> void:
	var r := TankBalanceHarness.run({"crew": 3, "seed": 1, "compliance": 1.0, "snapshots": false})
	assert_false(r.has("error"), str(r.get("error", "")))
	var segs: Array = r["segments"]
	assert_eq(segs.size(), 11, "11 mission segments")
	var total := 0.0
	for i in segs.size():
		var s: Dictionary = segs[i]
		assert_gt(float(s["dur_s"]), 0.0, "segment %d has a length" % i)
		total += float(s["dur_s"])
		if str(s["seg"]) == TankIds.SEG_DEPOT:
			assert_almost_eq(float(s["dur_s"]), 300.0, 0.1)
		if str(s["seg"]) == TankIds.SEG_CHECKPOINT:
			assert_almost_eq(float(s["dur_s"]), 60.0, 0.1)
	assert_almost_eq(float(r["end_t"]) - total, 1.0, 1.0, "the run stops 1 s into the cool-down")
	assert_has([TankIds.OUTCOME_VICTORY, TankIds.OUTCOME_WITHDRAWN], r["outcome"])
	assert_eq((r["kills"] as Array).size(), 7)
	assert_eq(int(r["crew"]), 3)
	assert_true((r["dynamo"] as Array).size() > 0, "the dynamo's phases are tracked")
	assert_true(TankBalanceHarness.format(r).contains("crew 3 seed 1"))


func test_the_solo_harness_tracks_the_bulwark_s_advances() -> void:
	var r := TankBalanceHarness.run({"crew": 1, "seed": 2, "snapshots": false})
	assert_false(r.has("error"), str(r.get("error", "")))
	assert_eq((r["drive_share"] as Array).size(), 3, "one Drive share per Advance")
	for d: Dictionary in r["drive_share"]:
		assert_between(float(d["share"]), 0.0, 1.0)


func test_the_synthetic_rider_follows_the_band_and_the_target() -> void:
	var ctx := TankFakes.make_ctx(1, 0, "drill", Wl.SOLO, 1, 1)
	var game := TankFakes.make_game(ctx)
	autofree(game)
	var clock := TankFakes.clock_of(game)
	var riders := TankSyntheticRiders.new(ctx, clock, 0.85)
	var hud := ctx.hud as TankFakes.Hud
	hud.power_band(1, 0.76 * 200.0, 1.05 * 200.0)
	var ftp := ctx.players[0].ftp
	var last: InputFrame = null
	for tick in 400:
		clock.advance(tick * Wl.SIM_DT)
		last = riders.frame(tick)
	var tm := last.telemetry(1)
	# The drill's depot is a SIM warm-up: 0.85 x the band centre, 1 s lag settled after 20 s.
	assert_eq(tm.mode, Wl.SIM)
	assert_almost_eq(tm.power_w, 0.85 * 0.5 * (0.76 + 1.05) * ftp, 2.0)
	assert_almost_eq(tm.ftp_pct, 76.9, 1.0)
	assert_eq(tm.cadence_rpm, 90.0)


func test_enemy_counts_are_tripled_in_memory_and_the_content_still_validates() -> void:
	var ctx := TankFakes.make_ctx(3, 0, "ashfall_road", Wl.HOST, 1, 1)
	var plain := TankContent.load_for(ctx)
	ctx.content_overrides = TankBalanceHarness.enemy_mult_overrides("ashfall_road", 3)
	var tripled := TankContent.load_for(ctx)
	assert_eq(plain.errors, [] as Array[String])
	assert_eq(tripled.errors, [] as Array[String], "tripled counts still pass validation")
	var n_plain := 0
	var n_three := 0
	for i in plain.segments().size():
		for e: Dictionary in (
			plain.segment(i).get("encounters", []) + plain.segment(i).get("enemies", [])
		):
			n_plain += int(e["count"])
		for e: Dictionary in (
			tripled.segment(i).get("encounters", []) + tripled.segment(i).get("enemies", [])
		):
			n_three += int(e["count"])
			if e.has("at_px"):
				assert_eq(
					(e["at_px"] as Array).size(), int(e["count"]), "a position per gun-line enemy"
				)
	assert_gt(n_plain, 10)
	assert_eq(n_three, 3 * n_plain)
	assert_eq(tripled.segments().size(), plain.segments().size(), "the segment table is untouched")


# --- The evaluator ---------------------------------------------------------------------------------------


func test_t1_to_t5_pass_on_a_run_that_meets_them() -> void:
	var results: Array = [_good(3, 1, 800.0), _good(3, 1, 700.0, 0.85), _good(3, 1, 600.0, 0.7)]
	for t in TankBalanceTargets.evaluate(results):
		assert_true(bool(t["ok"]), str(t["text"]))


func test_t1_misses_on_a_slow_advance_an_overrun_a_breakdown_or_a_low_grade() -> void:
	var slow := _good()
	slow["segments"][1]["dur_s"] = 260.0
	assert_false(bool(TankBalanceTargets.t1([slow])["ok"]), "an Advance over 240 s")
	var short := _good()
	short["segments"][2]["dur_s"] = 70.0
	assert_false(bool(TankBalanceTargets.t1([short])["ok"]), "a gun line under 80 s")
	var overran := _good()
	overran["segments"][3]["overran"] = true
	assert_false(bool(TankBalanceTargets.t1([overran])["ok"]))
	var broke := _good()
	broke["breakdowns"] = 2
	assert_false(bool(TankBalanceTargets.t1([broke])["ok"]))
	var graded := _good()
	graded["grade"] = "C"
	assert_false(bool(TankBalanceTargets.t1([graded])["ok"]))
	assert_true(
		bool(TankBalanceTargets.t1([_good(3, 1, 800.0, 0.85)])["ok"]), "only compliant runs count"
	)
	assert_string_contains(str(TankBalanceTargets.t1([])["text"]), "skipped")


func test_t2_needs_time_above_80_per_stage_and_a_fast_return() -> void:
	assert_true(bool(TankBalanceTargets.t2([_good(2)])["ok"]))
	var low := _good()
	low["dynamo"][0]["above80_s"] = 5.0
	low["dynamo"][1]["above80_s"] = 5.0
	assert_false(bool(TankBalanceTargets.t2([low])["ok"]), "stage 1 under 30 s")
	var boss := _good()
	boss["dynamo"][2]["above80_s"] = 50.0
	assert_false(bool(TankBalanceTargets.t2([boss])["ok"]), "the boss under 60 s")
	var slow_back := _good()
	slow_back["dynamo"][1]["back_to_65_s"] = 130.0
	assert_false(bool(TankBalanceTargets.t2([slow_back])["ok"]), "back to 65% after 130 s")
	assert_string_contains(str(TankBalanceTargets.t2([_good(1)])["text"]), "skipped")


func test_t3_judges_only_heavy_shells_outside_the_depot() -> void:
	assert_true(bool(TankBalanceTargets.t3([_good()])["ok"]))
	var fast := _good()
	fast["shells"][0]["build_s"] = 12.0
	assert_false(bool(TankBalanceTargets.t3([fast])["ok"]))
	var slow := _good()
	slow["shells"][0]["build_s"] = 40.0
	assert_false(bool(TankBalanceTargets.t3([slow])["ok"]))
	var none := _good()
	none["shells"] = []
	assert_false(bool(TankBalanceTargets.t3([none])["ok"]), "no heavy shell at all is a miss")
	var no_rest := _good()
	no_rest["shells"][0]["grade0_s"] = 4.0
	assert_false(bool(TankBalanceTargets.t3([no_rest])["ok"]))


func test_t4_and_t5() -> void:
	assert_true(bool(TankBalanceTargets.t4([_good(1)])["ok"]))
	var idle := _good(1)
	idle["drive_share"][0]["share"] = 0.5
	assert_false(bool(TankBalanceTargets.t4([idle])["ok"]))
	var flat := [_good(3, 1, 700.0), _good(3, 1, 700.0, 0.85), _good(3, 1, 600.0, 0.7)]
	assert_false(bool(TankBalanceTargets.t5(flat)["ok"]), "100% must beat 85% strictly")
	var rising := [_good(3, 1, 700.0), _good(3, 1, 650.0, 0.85), _good(3, 1, 660.0, 0.7)]
	assert_false(bool(TankBalanceTargets.t5(rising)["ok"]))
	assert_string_contains(str(TankBalanceTargets.t5([_good()])["text"]), "skipped")
