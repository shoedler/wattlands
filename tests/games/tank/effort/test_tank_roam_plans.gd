extends GutTest
## Free roam's effort plans and their safety checks (brief 2.10 Effort plan, 2.3 checks; BRIEF 4.5,
## 4.6): crews 1-4 x every roam length x FTP {80, 200, 400} x verified / unverified: the
## PlanValidator clean with no switch warning, the drive-out a 300 s WARMUP with the depot's numbers,
## one open-ended WORK phase per rider (min_s = minutes x 60 - 300, max_s + 300) on one engine, every
## roam phase longer than 300 s under its 105% cap with every bound at or below 100% (85% here), the
## dynamo's and the arc generator's patterns clamped to [55, 85] and [65, 80], the terrain inside
## -3..+5%, and two FIT laps before the cool-down.

const F := preload("res://tests/games/tank/tank_fakes.gd")
const ROAMS: Array[String] = ["roam_10", "roam_20", "roam_30", "roam_45", "roam_60"]


func _plans(content_id: String, crew: int, ftp: float, verified: bool) -> Dictionary:
	var ctx := F.make_ctx(crew, 0, content_id)
	for p in ctx.players:
		p.ftp = ftp
		p.ftp_verified = verified
	var game: TankGame = autofree(F.make_game(ctx))
	return game.build_effort_plans()


func _peak(ph: PlanPhase) -> float:
	if ph.mode != Wl.ERG:
		return 0.0
	var r := ph.effective_range()
	return maxf(maxf(ph.target_pct, ph.ramp_to_pct if ph.ramp_to_pct > 0.0 else 0.0), float(r[1]))


func test_every_roam_plan_is_valid_with_no_switch_warning() -> void:
	for id in ROAMS:
		var minutes := int(id.trim_prefix("roam_"))
		for crew in [1, 2, 3, 4]:
			for ftp: float in [80.0, 200.0, 400.0]:
				for verified in [true, false]:
					var plans := _plans(id, crew, ftp, verified)
					assert_eq(plans.size(), crew)
					for peer: int in plans:
						var at := "%s crew %d ftp %d %s peer %d" % [id, crew, ftp, verified, peer]
						var plan: EffortPlan = plans[peer]
						var v := PlanValidator.validate(plan)
						assert_true(v["ok"], "%s: %s" % [at, v["errors"]])
						assert_eq(v["warnings"], [], at)
						assert_eq(plan.size(), 2, at)
						var out := plan.phase(0)
						var roam := plan.phase(1)
						assert_eq(out.kind, Wl.WARMUP, at)
						assert_eq(out.duration_s, 300.0, at)
						assert_true(out.lap and roam.lap, "a FIT lap each: " + at)
						assert_eq(roam.kind, Wl.WORK, at)
						assert_true(roam.open_ended, at)
						assert_eq(roam.min_s, minutes * 60.0 - 300.0, at)
						assert_eq(roam.max_s, roam.min_s + 300.0, at)
						assert_gt(roam.max_s, 300.0, "longer than 300 s: the 105% cap applies")
						assert_lte(_peak(roam), 100.0, "every bound <= 100%: " + at)
						assert_lte(_peak(roam), 105.0, "under the 105% cap: " + at)
						assert_lte(_peak(out), 65.0, "the drive-out within 4.6.8: " + at)
						assert_eq(
							str(out.meta["engine"]), str(roam.meta["engine"]), "one engine: " + at
						)
						assert_eq(str(roam.meta["seg"]), TankIds.SEG_ROAM, at)
						assert_eq(
							PlanValidator.finalize(plan).size(), 3, "drive-out, roam, cool-down"
						)


func test_each_engine_rides_the_brief_table_in_the_roam() -> void:
	for crew in [1, 2, 3, 4]:
		var plans := _plans("roam_30", crew, 200.0, true)
		for peer: int in plans:
			var plan: EffortPlan = plans[peer]
			var ph := plan.phase(1)
			var out := plan.phase(0)
			var engine := str(ph.meta["engine"])
			var at := "crew %d peer %d %s" % [crew, peer, engine]
			match engine:
				TankIds.ENGINE_DIESEL:
					assert_eq(ph.mode, Wl.SIM, at)
					assert_eq(ph.grade_source, Wl.GRADE_GAME, at)
					assert_eq(out.grade_source, Wl.GRADE_GAME, at)
				TankIds.ENGINE_STEAM, TankIds.ENGINE_FEED:
					assert_eq(ph.mode, Wl.SIM, at)
					assert_eq(ph.grade_source, Wl.GRADE_FLAT, at)
				TankIds.ENGINE_DYNAMO:
					assert_eq(ph.mode, Wl.ERG, at)
					assert_eq(ph.target_pct, 55.0, at)
					assert_eq(ph.effective_range(), [55.0, 85.0], at)
					assert_eq([out.target_pct, out.ramp_to_pct], [50.0, 65.0], "the depot's: " + at)
				TankIds.ENGINE_ARC:
					assert_eq(ph.mode, Wl.ERG, at)
					assert_eq(ph.target_pct, 65.0, at)
					assert_eq(ph.effective_range(), [65.0, 80.0], at)
					assert_eq([out.target_pct, out.ramp_to_pct], [50.0, 65.0], "the depot's: " + at)
				_:
					fail_test("unknown engine " + at)
	var starts := {1: ["diesel"], 4: ["diesel", "dynamo", "steam", "arc"]}
	for crew: int in starts:
		var plans := _plans("roam_10", crew, 200.0, true)
		var got: Array = []
		for peer: int in plans:
			got.append(str((plans[peer] as EffortPlan).phase(1).meta["engine"]))
		assert_eq(got, starts[crew], "crew %d keeps its start engines (no rotation)" % crew)


func test_the_bank_and_arc_patterns_stay_inside_the_roam_ranges() -> void:
	var c := TankFixtures.content("roam_30")
	var plans := _plans("roam_30", 4, 200.0, true)
	for peer: int in plans:
		var ph := (plans[peer] as EffortPlan).phase(1)
		match str(ph.meta["engine"]):
			TankIds.ENGINE_DYNAMO:
				assert_true(TankDirector.bank_phase(TankIds.ENGINE_DYNAMO, ph))
				assert_eq(TankDirector.bank_target_pct(c, 0.0, ph), 85.0, "a drained bank: 85%")
				assert_eq(TankDirector.bank_target_pct(c, 100.0, ph), 55.0, "a full bank")
				assert_lte(TankDirector.bank_goal_pct(c, 0.0, ph, 55.0), 65.0, "10 points a step")
			TankIds.ENGINE_ARC:
				assert_true(TankDirector.arc_phase(TankIds.ENGINE_ARC, ph))
				assert_eq(TankDirector.arc_target_pct(c, 1.0, ph), 80.0)
				assert_eq(TankDirector.arc_target_pct(c, 0.0, ph), 65.0)
		var out := (plans[peer] as EffortPlan).phase(0)
		assert_false(TankDirector.bank_phase(str(out.meta["engine"]), out), "none in the drive-out")
		assert_false(TankDirector.arc_phase(str(out.meta["engine"]), out), "none in the drive-out")


func test_the_unverified_factor_only_lowers_roam_targets() -> void:
	for ftp: float in [80.0, 200.0, 400.0]:
		var plans := _plans("roam_45", 4, ftp, false)
		for peer: int in plans:
			var ph := (plans[peer] as EffortPlan).phase(1)
			if ph.mode != Wl.ERG:
				continue
			var top := float(ph.effective_range()[1])
			var applied := top * TankDirector.UNVERIFIED_FACTOR
			assert_lt(applied, top, "x0.85 lowers")
			assert_lte(applied / 100.0 * ftp, ftp, "under FTP at %d W" % ftp)


func test_power_bands_in_the_roam() -> void:
	var c := TankFixtures.content("roam_30")
	for crew in [1, 2, 3, 4]:
		var plans := _plans("roam_30", crew, 200.0, true)
		for peer: int in plans:
			var plan: EffortPlan = plans[peer]
			assert_eq(
				TankDirector.power_band_pct(c, plan.phase(0)),
				[0.0, 0.0] as Array[float],
				"never a tempo band in the drive-out"
			)
			var drives := str(plan.phase(1).meta["engine"]) == "diesel"
			var band: Array[float] = [76.0, 105.0]
			var none: Array[float] = [0.0, 0.0]
			assert_eq(TankDirector.power_band_pct(c, plan.phase(1)), band if drives else none)
