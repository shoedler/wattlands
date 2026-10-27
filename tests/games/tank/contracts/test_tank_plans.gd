extends GutTest
## Lead-owned checks of the plan shapes and the directive helpers against the brief's safety rules
## (brief 2.3, 2.7, 2.9; BRIEF 4.5, 4.6): every plan through the PlanValidator, the segment table,
## the drill, the power bands, the bank clamp, the warm-up boiler, haptic precedence, and the
## content envelope. Builders fix their code when one fails, never this file.

const F := preload("res://tests/games/tank/tank_fakes.gd")

## Brief 2.3 segment table (and 2.9 for the drill): [type, kind, duration_s, min_s, max_s].
const ASHFALL := [
	["depot", "WARMUP", 300.0, 0.0, 0.0],
	["advance", "WORK", 180.0, 90.0, 300.0],
	["gun_line", "WORK", 120.0, 60.0, 180.0],
	["checkpoint", "RECOVERY", 60.0, 0.0, 0.0],
	["advance", "WORK", 180.0, 90.0, 300.0],
	["gun_line", "WORK", 120.0, 60.0, 180.0],
	["checkpoint", "RECOVERY", 60.0, 0.0, 0.0],
	["advance", "WORK", 180.0, 90.0, 300.0],
	["gun_line", "WORK", 120.0, 60.0, 180.0],
	["checkpoint", "RECOVERY", 60.0, 0.0, 0.0],
	["boss", "WORK", 240.0, 120.0, 360.0],
]
const DRILL := [
	["depot", "WARMUP", 30.0, 0.0, 0.0],
	["skirmish", "WARMUP", 70.0, 0.0, 0.0],
	["checkpoint", "RECOVERY", 30.0, 0.0, 0.0],
]


func _plans(content_id: String, crew: int, rotation: bool = true) -> Dictionary:
	var ctx := F.make_ctx(crew, 0, content_id)
	ctx.options["rotation"] = rotation
	var game: TankGame = autofree(F.make_game(ctx))
	return game.build_effort_plans()


func _content(mission: String = "ashfall_road") -> TankContent:
	return TankFixtures.content(mission)


## Every plan, every crew, rotation on and off: valid, no switch warning, the first 300 s within
## 4.6.8, and per rider every ERG <-> SIM switch >= 60 s apart with each open phase at its min_s
## and at its max_s (brief 2.3, BRIEF 4.5).
func test_every_plan_passes_the_validator_with_switches_60_s_apart() -> void:
	for content_id: String in F.manifest()["contents"]:
		for crew in [1, 2, 3]:
			for rotation in [true, false]:
				var plans := _plans(content_id, crew, rotation)
				for peer: int in plans:
					var at := "%s crew %d rotation %s peer %d" % [content_id, crew, rotation, peer]
					var plan: EffortPlan = plans[peer]
					var v := PlanValidator.validate(plan)
					assert_true(v["ok"], "%s: %s" % [at, v["errors"]])
					assert_eq(v["warnings"], [], at)
					var final := PlanValidator.finalize(plan)
					assert_eq(final.phase(final.size() - 1).kind, Wl.COOLDOWN, at)
					for use_max in [false, true]:
						assert_gte(
							_min_switch_gap(final, use_max),
							60.0,
							"%s (open at %s)" % [at, "max" if use_max else "min"]
						)
					assert_true(_warmup_ok(plan), "%s: first 300 s within 4.6.8" % at)


func _min_switch_gap(plan: EffortPlan, use_max: bool) -> float:
	var t := 0.0
	var last_switch := -INF
	var gap := INF
	var mode := ""
	for i in plan.size():
		var ph := plan.phase(i)
		if mode != "" and ph.mode != mode:
			gap = minf(gap, t - last_switch)
			last_switch = t
		mode = ph.mode
		t += (ph.max_s if use_max else ph.min_s) if ph.open_ended else ph.duration_s
	return gap


func _switches(plan: EffortPlan) -> int:
	var n := 0
	for i in range(1, plan.size()):
		if plan.phase(i).mode != plan.phase(i - 1).mode:
			n += 1
	return n


func _warmup_ok(plan: EffortPlan) -> bool:
	var t := 0.0
	for i in plan.size():
		var ph := plan.phase(i)
		if t < 300.0 and ph.mode == Wl.ERG:
			var r := ph.effective_range()
			if ph.target_pct > 65.0 or float(r[1]) > 65.0:
				return false
		t += ph.min_s if ph.open_ended else ph.duration_s
	return true


## Each segment's type, kind, duration_s, min_s and max_s exactly as the brief's table, in the
## mission file and in every rider's plan.
func test_every_segment_matches_the_brief_table() -> void:
	for mission: String in ["ashfall_road", "drill"]:
		var want: Array = ASHFALL if mission == "ashfall_road" else DRILL
		var segs := _content(mission).segments()
		assert_eq(segs.size(), want.size(), mission)
		for i in want.size():
			var s: Dictionary = segs[i]
			var got := [
				str(s["type"]),
				str(s["kind"]),
				float(s["duration_s"]),
				float(s.get("min_s", 0.0)),
				float(s.get("max_s", 0.0))
			]
			assert_eq(got, want[i], "%s segment %d" % [mission, i])
		for crew in [1, 2, 3]:
			var plans := _plans(mission, crew)
			for peer: int in plans:
				var plan: EffortPlan = plans[peer]
				for i in want.size():
					var ph := plan.phase(i)
					var w: Array = want[i]
					var got := [ph.kind, ph.duration_s, ph.min_s, ph.max_s, ph.lap]
					assert_eq(got, [w[1], w[2], w[3], w[4], true], "%s %d.%d" % [mission, peer, i])


## The drill (brief 2.9): 130 s, at most one ERG <-> SIM switch per rider (the cool-down included),
## dynamo ERG 50% then 55% in [55, 65], every ERG inside the warm-up limit.
func test_the_drill_switches_mode_at_most_once_and_ends_at_130_s() -> void:
	for crew in [1, 2, 3]:
		var plans := _plans("drill", crew)
		for peer: int in plans:
			var plan: EffortPlan = plans[peer]
			var at := "crew %d peer %d" % [crew, peer]
			var total := 0.0
			for i in plan.size():
				total += plan.phase(i).duration_s
				var r := plan.phase(i).effective_range()
				if plan.phase(i).mode == Wl.ERG:
					assert_lte(float(r[1]), 65.0, "%s phase %d" % [at, i])
			assert_eq(total, 130.0, at)
			var final := PlanValidator.finalize(plan)
			assert_lte(_switches(final), 1, at)
			if str(plan.phase(1).meta["engine"]) == TankIds.ENGINE_DYNAMO:
				assert_eq(plan.phase(0).target_pct, 50.0, at)
				assert_eq(plan.phase(1).target_pct, 55.0, at)
				assert_eq(plan.phase(1).effective_range(), [55.0, 65.0], at)


## The power band is the tempo band only for the diesel and the Bulwark in WORK SIM phases; every
## WARMUP (the depot, the drill's depot and skirmish), RECOVERY (checkpoints) and ERG phase, and
## the steam engine, clear it.
func test_power_bands_are_cleared_outside_work_sim_drivers() -> void:
	for mission: String in ["ashfall_road", "drill"]:
		var c := _content(mission)
		for crew in [1, 2, 3]:
			var plans := _plans(mission, crew)
			for peer: int in plans:
				var plan: EffortPlan = plans[peer]
				for i in plan.size():
					var ph := plan.phase(i)
					var pb := TankDirector.power_band_pct(c, ph)
					var at := "%s crew %d peer %d phase %d" % [mission, crew, peer, i]
					var drives := ["diesel", "bulwark"].has(str(ph.meta["engine"]))
					if ph.kind == Wl.WORK and ph.mode == Wl.SIM and drives:
						assert_eq(pb, [76.0, 105.0] as Array[float], at)
					else:
						assert_eq(pb, [0.0, 0.0] as Array[float], at)


## Pattern 1: the bank target is clamped to the phase's range before any step limit: a drained
## bank in the drill's skirmish never asks above 65%, a full one never below 55%.
func test_bank_targets_stay_inside_the_phase_range() -> void:
	var drill := _content("drill")
	var skirmish := TankPlanBuilder.phase_for(drill, drill.segment(1), TankIds.ENGINE_DYNAMO, 1)
	var ashfall := _content()
	var advance := TankPlanBuilder.phase_for(ashfall, ashfall.segment(1), TankIds.ENGINE_DYNAMO, 1)
	for bank in range(-10, 111, 5):
		var b := float(bank)
		var s := TankDirector.bank_target_pct(drill, b, skirmish)
		assert_between(s, 55.0, 65.0, "drill skirmish bank %d" % bank)
		var a := TankDirector.bank_target_pct(ashfall, b, advance)
		assert_between(a, 55.0, 100.0, "advance bank %d" % bank)
	assert_eq(TankDirector.bank_target_pct(drill, 0.0, skirmish), 65.0)
	assert_eq(TankDirector.bank_target_pct(ashfall, 0.0, advance), 100.0)
	assert_eq(TankDirector.bank_target_pct(ashfall, 100.0, advance), 55.0)
	assert_almost_eq(TankDirector.bank_target_pct(ashfall, 50.0, advance), 77.5, 1e-6)


## Pattern 2: 3% x min(pressure, 1) in the warm-up (never above +3%, BRIEF 4.6.8), 8% x
## min(pressure, 1) in WORK, 0 while loaded or cycling.
func test_the_boiler_grade_never_passes_its_cap() -> void:
	var c := _content()
	assert_eq(TankDirector.boiler_grade_pct(c, 104.0, true, false), 3.0, "depot overshoot")
	assert_eq(TankDirector.boiler_grade_pct(c, 50.0, true, false), 1.5)
	assert_eq(TankDirector.boiler_grade_pct(c, 150.0, false, false), 8.0, "Overpressure")
	assert_eq(TankDirector.boiler_grade_pct(c, 50.0, false, false), 4.0)
	assert_eq(TankDirector.boiler_grade_pct(c, 80.0, false, true), 0.0, "loaded or cycling")
	for p in range(0, 151, 10):
		assert_lte(TankDirector.boiler_grade_pct(c, float(p), true, false), 3.0)


## Brief 2.7: a Behemoth main-gun hit is the boss_hit haptic, never also the hit one; one crew-wide
## haptic per tick, boss_hit first.
func test_haptic_precedence() -> void:
	var boss := TankEvents.hit(TankEvents.ON_TANK, 0, 20.0, TankIds.SHELL_BOSS_MAIN, 0.0, 0.0)
	var heavy := TankEvents.hit(TankEvents.ON_TANK, 0, 12.0, TankIds.SHELL_ENEMY, 4.0, 0.0)
	var light := TankEvents.hit(TankEvents.ON_TANK, 0, 4.0, TankIds.SHELL_ENEMY, 0.0, 0.0)
	var on_enemy := TankEvents.hit(TankEvents.ON_ENEMY, 7, 50.0, TankIds.SHELL_HEAVY, 0.0, 0.0)
	assert_false(TankEvents.is_tank_hit(boss, 8.0), "the boss gun is not the hit haptic")
	assert_true(TankEvents.is_boss_main_hit(boss))
	assert_true(TankEvents.is_tank_hit(heavy, 8.0), "pre-berm damage counts")
	assert_eq(TankDirector.crew_haptic([heavy, boss], 8.0), TankDirector.HAPTIC_BOSS_HIT)
	assert_eq(TankDirector.crew_haptic([boss, heavy], 8.0), TankDirector.HAPTIC_BOSS_HIT)
	assert_eq(TankDirector.crew_haptic([heavy, light], 8.0), TankDirector.HAPTIC_HIT)
	assert_eq(TankDirector.crew_haptic([light, on_enemy], 8.0), TankDirector.HAPTIC_NONE)
	var none: Array[Dictionary] = []
	assert_eq(TankDirector.crew_haptic(none, 8.0), TankDirector.HAPTIC_NONE)


## The content envelope: each number that carries a brief 2.3 / 2.7 check, pushed past its bound,
## is named by the validators (G2 tunes within it, never past it).
func test_the_validators_hold_the_safety_envelope() -> void:
	var cases: Array = [
		["stations", "boiler.grade_pct", 9, "boiler.grade_pct: must be <= 8"],
		["stations", "boiler.warmup_grade_pct", 3.5, "boiler.warmup_grade_pct: must be <="],
		["stations", "boiler.max_rise_pct", 1.0, "boiler.max_rise_pct"],
		["stations", "boiler.min_interval_s", 0.5, "boiler.min_interval_s"],
		["stations", "hoist.grade_pct", 4.5, "hoist.grade_pct: must be <= 4"],
		["stations", "hoist.warmup_grade_pct", 1.5, "hoist.warmup_grade_pct: must be <="],
		["stations", "hoist.rise_pct_s", 2.0, "hoist.rise_pct_s"],
		["stations", "hoist.step_s", 0, "hoist.step_s"],
		["stations", "terrain.warmup_grade_pct.1", 2.5, "terrain.warmup_grade_pct.1"],
		["stations", "terrain.warmup_grade_pct.0", -1.0, "terrain.warmup_grade_pct.0"],
		["stations", "terrain.send_every_s", 0.25, "terrain.send_every_s"],
		["stations", "haptics.hit.haptic", 3.5, "haptics.hit.haptic"],
		["stations", "haptics.boss_hit.duration_s", 9, "haptics.boss_hit.duration_s"],
		["stations", "haptics.ram.haptic", 4, "haptics.ram.haptic"],
		["stations", "haptics.cooldown_s", 10, "haptics.cooldown_s"],
		["stations", "bank.max_step_pts", 12, "bank.max_step_pts"],
		["stations", "bank.substep_s", 0.5, "bank.substep_s"],
		["stations", "bank.substeps", 1, "bank.max_step_pts / bank.substeps"],
		["stations", "bank.substeps", 2, "bank.max_step_pts / bank.substeps"],
		["stations", "bank.max_step_pts", 12, "bank.max_step_pts / bank.substeps"],
		["stations", "hoist.step_s", 4, "hoist.rise_pct_s x hoist.step_s"],
		["stations", "hoist.step_s", 2, "hoist.rise_pct_s x hoist.step_s"],
		["stations", "bank.base_pct", 45, "bank.base_pct"],
		["stations", "bank.span_pct", 50, "base_pct + span_pct"],
		["stations", "bank.clamp_to_range", false, "bank.clamp_to_range"],
		["stations", "plans.checkpoint.target_pct", 55, "plans.checkpoint: must be exactly ERG 50"],
		["stations", "drill_plans.checkpoint.mode", "SIM", "drill_plans.checkpoint: must be"],
		["stations", "drill_plans.dynamo.skirmish.range_pct", [55, 70], "skirmish: warm-up ERG"],
		["stations", "plans.dynamo.depot.ramp_to_pct", 70, "plans.dynamo.depot: warm-up ERG"],
		["stations", "plans.dynamo.boss.range_pct", [55, 105], "plans.dynamo.boss: every ERG"],
		["stations", "plans.steam.gun_line", null, "plans.steam.gun_line: missing"],
		["stations", "drill_plans.diesel.skirmish", null, "drill_plans.diesel.skirmish: missing"],
		[
			"stations",
			"rotation.citadel.0",
			["dynamo", "dynamo", "steam", "diesel"],
			"rotation.citadel[0]: stage 1"
		],
		[
			"stations",
			"rotation.rampart.1",
			["dynamo", "bulwark", "dynamo", "diesel"],
			"bulwark is not one of the tank's engines"
		],
		[
			"stations",
			"rotation.rampart.1",
			["dynamo", "diesel", "diesel", "diesel"],
			"rotation.rampart column 3"
		],
		["tanks", "in_band.sim_ftp_pct", [76, 110], "in_band.sim_ftp_pct: must lie in 50..105"],
		["mission", "segments.2.max_s", 200, "segments[2] max_s: a 90% gun line"],
		["mission", "segments.1.terrain.2", [300, 7], "segments[1] terrain: grade"],
		["mission", "segments.0.terrain.2", [400, 2.5], "segments[0] terrain: grade"],
	]
	for case: Array in cases:
		var f := TankContent.read_files("ashfall_road")
		_set_path(f[case[0]], str(case[1]), case[2])
		var c := TankContent.from_dicts(f, "ashfall_road")
		assert_false(c.ok(), "%s = %s must be refused" % [case[1], case[2]])
		assert_string_contains("\n".join(c.errors), str(case[3]))


## A number past its bound in the mission and stations together (validate_cross): a gun line
## stretched past 180 s at ERG 90%, start engines that aren't the tank's rooms.
func test_the_cross_file_checks_name_what_is_wrong() -> void:
	var f := TankContent.read_files("ashfall_road")
	f["stations"]["start_engines"]["rampart"] = ["diesel", "steam"]
	f["stations"]["rotation"]["rampart"] = [
		["diesel", "steam", "diesel", "steam"], ["steam", "diesel", "steam", "diesel"]
	]
	var c := TankContent.from_dicts(f, "ashfall_road")
	assert_string_contains("\n".join(c.errors), "start_engines.rampart: must be tanks.json")
	var order := TankContent.read_files("ashfall_road")
	order["stations"]["start_engines"]["rampart"] = ["dynamo", "diesel"]
	order["stations"]["rotation"]["rampart"] = [
		["dynamo", "diesel", "dynamo", "diesel"], ["diesel", "dynamo", "diesel", "dynamo"]
	]
	var ok := TankContent.from_dicts(order, "ashfall_road")
	assert_eq(ok.errors, [] as Array[String], "v2: slots may start in any order of the rooms")
	var g := TankContent.read_files("drill")
	g["mission"]["segments"][1]["type"] = "advance"
	g["mission"]["segments"][1]["kind"] = "WORK"
	g["mission"]["segments"][1]["min_s"] = 35
	g["mission"]["segments"][1]["max_s"] = 70
	var d := TankContent.from_dicts(g, "drill")
	assert_string_contains("\n".join(d.errors), "advance is not in stations.json drill_plans")


## Sets a dotted path (numeric parts index arrays); null erases the key.
func _set_path(d: Variant, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var cur: Variant = d
	for i in parts.size() - 1:
		cur = cur[int(parts[i])] if cur is Array else cur[parts[i]]
	var last := parts[parts.size() - 1]
	if cur is Array:
		cur[int(last)] = value
	elif value == null:
		(cur as Dictionary).erase(last)
	else:
		cur[last] = value
