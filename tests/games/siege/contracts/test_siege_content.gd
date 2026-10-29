extends GutTest
## SiegeContent (brief 2.4 "Every number below lives in content/siege/*.json, validated at
## load"): the shipped files are valid for every shift, the numbers are the brief's, and each
## validator rejects what it promises to.

const F := preload("res://tests/games/siege/siege_fakes.gd")


func _files() -> Dictionary:
	return SiegeContent.read_files()


func _errors_with(file: String, path: String, value: Variant) -> Array[String]:
	var files := _files()
	var d: Dictionary = files[file]
	var keys := path.split(".")
	for i in keys.size() - 1:
		d = d[keys[i]]
	if value == null:
		d.erase(keys[keys.size() - 1])
	else:
		d[keys[keys.size() - 1]] = value
	return SiegeContent.from_dicts(files, "short").errors


func test_every_shift_loads_without_errors() -> void:
	for id: String in ["short", "vo2", "sweetspot", "endurance", "drill"]:
		var c := F.content(id)
		assert_true(c.ok(), "%s: %s" % [id, c.errors])
		assert_eq(c.shift_id, id)
		assert_false(c.shift.is_empty())
		assert_not_null(c.path)


func test_an_unknown_shift_is_an_error() -> void:
	var c := SiegeContent.from_dicts(_files(), "nope")
	assert_false(c.ok())
	assert_true(str(c.errors).contains("no shift nope"))


func test_a_missing_file_is_an_error() -> void:
	for k: String in SiegeContent.FILES:
		var files := _files()
		files.erase(k)
		assert_false(SiegeContent.from_dicts(files, "short").ok(), k)


func test_a_missing_map_is_an_error() -> void:
	var files := _files()
	files.erase("map")
	var c := SiegeContent.from_dicts(files, "short")
	assert_false(c.ok())
	assert_null(c.path)


func test_station_caps_are_the_brief_s() -> void:
	var c := F.content()
	var caps: Array[int] = []
	for id in SiegeIds.STATION_COUNT:
		caps.append(int(c.station_def(id)["cap"]))
	assert_eq(caps, [2, 1, 2, 2, 1], "mine 2, ballista 1, onager 2, arrow organ 2, tar works 1")


func test_station_numbers_are_the_brief_s() -> void:
	var c := F.content()
	var b := c.station_def(SiegeIds.STATION_BALLISTA)
	assert_eq(float(b["wind_s"]), 5.0)
	assert_eq(b["range_m"], [0.0, 110.0])
	assert_eq(float(b["slew_dps"]), 25.0)
	assert_eq(float(b["speed_mps"]), 70.0)
	assert_eq(float(b["k"]), 0.0004)
	assert_eq(float(b["damage"]), 120.0)
	assert_eq(float(b["keep_infantry"]), 0.75)
	assert_eq(float(b["keep_engine"]), 0.3)
	assert_eq(float(b["stop_below"]), 10.0)
	var o := c.station_def(SiegeIds.STATION_ONAGER)
	assert_eq(float(o["wind_s"]), 7.0)
	assert_eq(o["range_m"], [30.0, 100.0])
	assert_eq(float(o["slew_dps"]), 4.0)
	assert_eq(float(o["v_max"]), 34.0)
	assert_eq(float(o["k"]), 0.0016)
	assert_eq(float(o["damage"]), 160.0)
	assert_eq(float(o["splash_m"]), 5.0)
	assert_eq(float(o["engine_mult"]), 2.5)
	assert_eq(float(o["special_splash_m"]), 6.5)
	var a := c.station_def(SiegeIds.STATION_ARROWS)
	assert_eq(float(a["rack_s"]), 1.5)
	assert_eq(int(a["racks"]), 3)
	assert_eq(int(a["per_rack"]), 12)
	assert_eq(a["range_m"], [40.0, 115.0])
	assert_eq(float(a["slew_dps"]), 30.0)
	assert_eq(float(a["v_max"]), 45.0)
	assert_eq(float(a["k"]), 0.006)
	assert_eq(float(a["spread_deg"]), 2.5)
	assert_eq(float(a["damage"]), 8.0)
	assert_eq(float(a["hit_r_m"]), 0.6)
	assert_eq(float(a["testudo_block"]), 0.7)


func test_spreads_are_the_brief_s() -> void:
	var c := F.content()
	assert_eq(float(c.station_def(SiegeIds.STATION_ARROWS)["speed_spread"]), 0.03, "+-3%")
	assert_eq(float(c.station_def(SiegeIds.STATION_ONAGER)["speed_spread"]), 0.015, "+-1.5%")
	assert_eq(float(c.station_def(SiegeIds.STATION_BALLISTA)["speed_spread"]), 0.005, "+-0.5%")
	assert_eq(float(c.station_def(SiegeIds.STATION_ONAGER)["spread_deg"]), 0.6)
	assert_eq(float(c.station_def(SiegeIds.STATION_BALLISTA)["spread_deg"]), 0.3)


func test_tar_numbers_are_the_brief_s() -> void:
	var t := F.content().station_def(SiegeIds.STATION_TAR)
	assert_eq(float(t["pump_lps"]), 6.0)
	assert_eq(float(t["cauldron_l"]), 300.0)
	assert_eq(float(t["spare_cauldron_l"]), 100.0)
	assert_eq(float(t["reheat_lps"]), 1.0)
	assert_eq(float(t["curtain_max"]), 200.0)
	assert_eq(float(t["curtain_drain_hps"]), 1.0)
	assert_eq(float(t["coat_full_hp"]), 100.0)
	assert_eq(float(t["coat_slow"]), 0.5)
	assert_eq(float(t["special_coat_slow"]), 0.65)


func test_scorpion_numbers_are_the_brief_s() -> void:
	var s := F.content().pad_def(SiegeIds.PAD_SCORPION)
	assert_eq(float(s["cost"]), 40.0)
	assert_eq(float(s["speed_mps"]), 50.0)
	assert_eq(float(s["k"]), 0.001)
	assert_eq(float(s["damage"]), 10.0)
	assert_eq(float(s["interval_s"]), 2.4)
	assert_eq(s["range_m"], [0.0, 60.0])
	assert_eq(float(s["rate_mult"]), 1.4)
	assert_eq(float(s["range_mult"]), 1.25)
	assert_eq(int(s["special_bolts"]), 2)


func test_upgrade_and_shop_prices_are_the_brief_s() -> void:
	var c := F.content()
	assert_eq(
		[c.station_upgrade_cost(1), c.station_upgrade_cost(2), c.station_upgrade_cost(3)],
		[40, 50, 70]
	)
	assert_eq([c.pad_upgrade_cost(1), c.pad_upgrade_cost(2), c.pad_upgrade_cost(3)], [40, 50, 70])
	assert_eq([c.mine_level_cost(1), c.mine_level_cost(2), c.mine_level_cost(3)], [60, 90, 130])
	assert_eq(c.station_upgrade_cost(4), -1)
	assert_eq(c.mine_level_cost(0), -1)
	assert_eq(c.num("shop.iron_bands"), 45.0)
	assert_eq(c.num("shop.repair"), 20.0)
	assert_eq(c.num("shop.reserve_flywheel"), 80.0)
	assert_eq(c.num("shop.aqueduct_drive"), 100.0)
	assert_eq(c.num("shop.spare_cauldron"), 60.0)
	assert_eq(c.num("start_gold"), 40.0)


func test_enemy_table_is_the_brief_s() -> void:
	var c := F.content()
	var want := {
		SiegeIds.ENEMY_SPEAR: [20, 0, 1.8, 1, 1],
		SiegeIds.ENEMY_SHIELD: [40, 6, 1.2, 3, 3],
		SiegeIds.ENEMY_CHARIOT: [60, 2, 6.0, 3, 3],
		SiegeIds.ENEMY_RAM: [600, 6, 0.8, 15, 20],
		SiegeIds.ENEMY_TOWER: [1800, 6, 0.5, 60, 60],
	}
	for code: int in want:
		var d := c.enemy_def(code)
		var w: Array = want[code]
		assert_eq(float(d["hp"]), float(w[0]), "%d hp" % code)
		assert_eq(float(d["armour"]), float(w[1]), "%d armour" % code)
		assert_eq(float(d["speed_mps"]), float(w[2]), "%d speed" % code)
		assert_eq(float(d["bounty"]), float(w[3]), "%d bounty" % code)
		assert_eq(float(d["threat"]), float(w[4]), "%d threat" % code)
	assert_eq(float(c.enemy_def(SiegeIds.ENEMY_SPEAR)["gate_hp"]), 2.0)
	assert_eq(float(c.enemy_def(SiegeIds.ENEMY_SHIELD)["gate_hp"]), 6.0)
	assert_eq(float(c.enemy_def(SiegeIds.ENEMY_CHARIOT)["gate_hp"]), 4.0)
	assert_eq(float(c.enemy_def(SiegeIds.ENEMY_RAM)["gate_hp_per_s"]), 3.0)
	assert_eq(int(c.enemy_def(SiegeIds.ENEMY_RAM)["crew"]), 6)
	assert_eq(float(c.enemies["lateral_m"]), 1.8)
	assert_eq(int(c.enemies["cap"]), 150)
	assert_eq(float(c.enemies["retreat_s"]), 3.0)


func test_ranks_are_the_brief_s() -> void:
	var c := F.content()
	assert_eq(c.enemy_def(SiegeIds.ENEMY_SPEAR)["ranks"], [4.0, 3.0], "blocks of 12, 4 x 3")
	assert_eq(c.enemy_def(SiegeIds.ENEMY_SHIELD)["ranks"], [3.0, 2.0], "groups of 6, 3 x 2")
	assert_eq(c.enemy_def(SiegeIds.ENEMY_CHARIOT)["ranks"], [1.0, 2.0], "pairs")
	assert_eq(float(c.enemy_def(SiegeIds.ENEMY_SPEAR)["spacing_m"]), 1.2)
	assert_eq(float(c.enemy_def(SiegeIds.ENEMY_CHARIOT)["spacing_m"]), 6.0)
	assert_eq(float(c.enemy_def(SiegeIds.ENEMY_CHARIOT)["speed_var"]), 0.3)
	assert_eq(c.enemy_def(SiegeIds.ENEMY_CHARIOT)["redraw_s"], [3.0, 6.0])
	assert_eq(float(c.enemy_def(SiegeIds.ENEMY_CHARIOT)["accel_mps2"]), 2.0)


func test_gate_and_economy_numbers_are_the_brief_s() -> void:
	var c := F.content()
	assert_eq(c.num("gate.hp"), 130.0)
	assert_eq(c.num("gate.iron_bands_hp"), 25.0)
	assert_eq(c.num("gate.iron_bands_max"), 2.0)
	assert_eq(c.num("gate.repair_hp"), 20.0)
	assert_eq(c.num("gate.breach_s"), 10.0)
	assert_eq(c.num("gate.restore_hp"), 30.0)
	assert_eq(c.num("gate.breach_loss"), 0.3)
	assert_eq(c.num("mine.gold_per_kj"), 1.0)
	assert_eq(c.num("mine.level_bonus"), 0.2)
	assert_eq(c.num("ref_w"), 250.0)
	assert_eq(c.num("m_cap"), 4.0)
	assert_eq(c.st_num("upgrade_out_mult"), 1.4)
	assert_eq(c.st_num("upgrade_range_mult"), 1.25)
	assert_eq(c.num("perks.reserve_hold_s"), 10.0)
	assert_eq(c.num("perks.aqueduct_m"), 0.25)
	assert_eq(c.num("reconnect_s"), 2.0)


func test_wave_numbers_are_the_brief_s() -> void:
	var w := F.content().waves
	assert_eq(w["group_every_s"], [6.0, 12.0])
	assert_eq(float(w["stop_before_end_s"]), 60.0)
	assert_eq(float(w["staging"]["reach_before_end_s"]), 30.0)
	assert_eq(float(w["engines"]["push_lead_s"]), 60.0)
	assert_eq(float(w["engines"]["pair_gap_m"]), 25.0)
	assert_eq(float(w["engines"]["escort_threat_per_slot"]), 10.0)
	assert_eq(float(w["engines"]["tower_min_wave_s"]), 300.0)
	assert_eq(float(w["warmup"]["budget_frac"]), 0.4)
	assert_eq(float(w["warmup"]["spear_only_s"]), 180.0)
	assert_eq(float(w["warmup"]["ram_hp_frac"]), 0.5)
	assert_eq(w["mix"]["standard"], [[0.7, 0.1, 0.2], [0.5, 0.25, 0.25], [0.4, 0.3, 0.3]])
	for row: Array in w["mix"]["raiders_horsemen"]:
		assert_eq(float(row[1]), 0.0, "spearmen and chariots only")


func test_the_overdrive_block_is_fixed_at_30_s() -> void:
	assert_true(str(_errors_with("balance", "overdrive.duration_s", 20)).contains("must be 30"))


func test_overdrive_min_left_is_at_least_the_block() -> void:
	assert_true(str(_errors_with("balance", "overdrive.min_left_s", 10)).contains("min_left_s"))


func test_overdrive_cooldowns_respect_switch_spacing() -> void:
	assert_true(str(_errors_with("balance", "overdrive.cooldown_s", 10)).contains("cooldown_s"))
	assert_true(
		str(_errors_with("balance", "overdrive.refused_retry_s", 5)).contains("refused_retry_s")
	)


func test_grades_must_descend() -> void:
	assert_true(str(_errors_with("balance", "score.grades.A", 95)).contains("descend"))


func test_balance_paths_are_checked() -> void:
	assert_true(str(_errors_with("balance", "ref_w", -1)).contains("ref_w"))
	assert_true(str(_errors_with("balance", "start_gold", null)).contains("start_gold"))
	assert_true(str(_errors_with("balance", "mine.level_costs", [1, 2])).contains("3 costs"))


func test_autopilot_weights_are_checked() -> void:
	assert_true(
		str(_errors_with("balance", "autopilot.weights.onager.ram", -2)).contains("weights.onager")
	)
	assert_true(str(_errors_with("balance", "autopilot.weights.arrows", null)).contains("arrows"))


func test_station_ids_and_caps_are_checked() -> void:
	assert_true(str(_errors_with("stations", "stations.onager.id", 7)).contains("id must be 2"))
	assert_true(str(_errors_with("stations", "stations.tar.cap", 0)).contains("cap"))
	assert_true(str(_errors_with("stations", "stations.mine", null)).contains("mine is missing"))


func test_weapon_fields_are_checked() -> void:
	assert_true(str(_errors_with("stations", "stations.ballista.wind_s", 0)).contains("wind_s"))
	assert_true(str(_errors_with("stations", "stations.onager.v_max", null)).contains("v_max"))
	assert_true(str(_errors_with("stations", "stations.arrows.per_rack", -3)).contains("per_rack"))
	assert_true(
		str(_errors_with("stations", "stations.arrows.range_m", [90, 40])).contains("range_m")
	)
	assert_true(
		str(_errors_with("stations", "stations.ballista.prefer.ram", -1)).contains("prefer.ram")
	)


func test_tar_and_pad_fields_are_checked() -> void:
	assert_true(str(_errors_with("stations", "stations.tar.pump_lps", 0)).contains("pump_lps"))
	assert_true(str(_errors_with("stations", "pads.scorpion.code", 2)).contains("code must be 1"))
	assert_true(str(_errors_with("stations", "pads.upgrade_costs", [1])).contains("3 costs"))
	assert_true(
		str(_errors_with("stations", "pads.start", [{"pad": 9, "type": "scorpion"}])).contains(
			"pads.start"
		)
	)


func test_enemy_fields_are_checked() -> void:
	assert_true(str(_errors_with("enemies", "spear.code", 3)).contains("code must be 1"))
	assert_true(str(_errors_with("enemies", "shield.gate_hp", 0)).contains("gate_hp"))
	assert_true(str(_errors_with("enemies", "spear.ranks", [0, 3])).contains("ranks"))
	assert_true(str(_errors_with("enemies", "chariot.speed_var", 1.5)).contains("speed_var"))
	assert_true(str(_errors_with("enemies", "ram.crew_type", "nobody")).contains("crew"))
	assert_true(str(_errors_with("enemies", "tower", null)).contains("tower"))
	assert_true(str(_errors_with("enemies", "cap", 0)).contains("cap"))


func test_wave_fields_are_checked() -> void:
	assert_true(str(_errors_with("waves", "group_every_s", [12, 6])).contains("group_every_s"))
	assert_true(
		str(_errors_with("waves", "mix.standard", [[0.5, 0.5, 0.5]])).contains("mix.standard")
	)
	assert_true(str(_errors_with("waves", "rush.types", ["dragon"])).contains("dragon"))
	assert_true(
		str(_errors_with("waves", "engines.push_lead_s", null)).contains("engines.push_lead_s")
	)


func test_shift_rules_are_checked() -> void:
	var files := _files()
	files["shifts"]["short"]["phases"][0]["target_pct"] = 130
	assert_true(str(SiegeContent.from_dicts(files, "short").errors).contains("50..117"))
	files = _files()
	files["shifts"]["short"]["phases"][2]["role"] = "dance"
	assert_true(str(SiegeContent.from_dicts(files, "short").errors).contains("role dance"))
	files = _files()
	files["shifts"]["short"]["phases"][3]["mix"] = "standard"
	assert_true(str(SiegeContent.from_dicts(files, "short").errors).contains("waves only"))


func test_cosmetics_ascend() -> void:
	var files := _files()
	files["cosmetics"]["unlocks"][1]["xp"] = 50
	assert_true(str(SiegeContent.from_dicts(files, "short").errors).contains("cosmetics"))


func test_number_readers_fall_back_to_defaults() -> void:
	var c := F.content()
	assert_eq(c.num("nope.nothing", 7.5), 7.5)
	assert_eq(c.st_num("stations.onager.wind_s"), 7.0)
	assert_eq(c.st_num("stations.nope", 3.0), 3.0)
	assert_eq(c.station_def(9), {})
	assert_eq(c.pad_def(0), {})
	assert_eq(c.enemy_def(0), {})
	assert_eq(c.range_band(SiegeIds.STATION_ONAGER), Vector2(30, 100))
	assert_eq(c.range_band(SiegeIds.STATION_MINE), Vector2.ZERO)
