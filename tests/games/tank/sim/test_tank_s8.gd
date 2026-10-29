extends GutTest
## S8 (brief 4): crew 3 on ashfall_road with every enemy count x 3 (in memory: the mission's
## encounter and gun-line counts are patched through GameContext.content_overrides, the same patch
## `tools/run_game_sim --override` takes), stepped through the whole GameModule with synthetic
## compliant riders (TankSyntheticRiders): never more than 16 enemies alive (the cap), never more
## than 24 shells, every snapshot at most 4 KB, and the session still reaches the cool-down.

const CAP_ENEMIES := 16
const CAP_SHELLS := 24


func test_s8_crew_3_with_tripled_enemy_counts_stays_within_the_caps() -> void:
	var cfg := {
		"crew": 3,
		"seed": 3,
		"compliance": 1.0,
		"enemy_mult": 3,
		"via_module": true,
		"snapshots": true,
	}
	var r := TankBalanceHarness.run(cfg)
	assert_false(r.has("error"), str(r.get("error", "")))
	assert_eq(int(r["enemy_mult"]), 3)
	assert_eq((r["segments"] as Array).size(), 11, "the whole mission is played")
	assert_lte(int(r["max_enemies"]), CAP_ENEMIES, "at most 16 enemies at once")
	assert_lte(int(r["max_shells"]), CAP_SHELLS, "at most 24 shells at once")
	assert_gt(int(r["snapshots"]), 1000, "a snapshot every 0.1 s of the whole session")
	assert_lte(int(r["max_snapshot_bytes"]), TankConst.SNAPSHOT_MAX_BYTES, "snapshots <= 4 KB")
	gut.p(
		(
			"S8: crew 3, x3 enemies: %d enemies, %d shells, %d B snapshots at most, %s"
			% [r["max_enemies"], r["max_shells"], r["max_snapshot_bytes"], r["outcome"]]
		)
	)


func test_s8_the_tripled_mission_really_has_three_times_the_enemies() -> void:
	var ctx := TankFakes.make_ctx(3, 0, "ashfall_road", Wl.HOST, 1, 3)
	var plain := TankContent.load_for(ctx)
	ctx.content_overrides = TankBalanceHarness.enemy_mult_overrides("ashfall_road", 3)
	var big := TankContent.load_for(ctx)
	assert_true(big.ok(), "; ".join(big.errors))
	var plain_n := 0
	var big_n := 0
	for i in plain.segments().size():
		for key in ["encounters", "enemies"]:
			for e: Dictionary in plain.segment(i).get(key, []):
				plain_n += plain.scaled_count(int(e["count"]), TankIds.TANK_LANDSHIP)
			for e: Dictionary in big.segment(i).get(key, []):
				big_n += big.scaled_count(int(e["count"]), TankIds.TANK_LANDSHIP)
	assert_gt(plain_n, 10)
	assert_eq(big_n, 3 * plain_n, "every count x 3 (scale 1.0)")
	# A tripled gun line is a real crowd: the rules must hold the line at the cap of 16.
	var worst := 0
	for i in big.segments().size():
		var total := 0
		for e: Dictionary in big.segment(i).get("enemies", []):
			total += int(e["count"])
		worst = maxi(worst, total)
	assert_gt(worst, 6, "a tripled gun line is a real crowd")
