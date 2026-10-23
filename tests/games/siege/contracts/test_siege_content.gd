extends GutTest
## SiegeContent: every content file loads and validates, carries the brief's numbers (2.4, 2.8),
## and each validator rejects a broken file.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FILES_OF := {
	"shifts": "shifts.json",
	"balance": "balance.json",
	"towers": "towers.json",
	"enemies": "enemies.json",
	"waves": "waves.json",
	"cosmetics": "cosmetics.json",
}

var _files: Dictionary


func before_all() -> void:
	_files = SiegeContent.read_files()


func test_every_shift_loads_without_errors() -> void:
	for id: String in F.manifest()["contents"]:
		var c := SiegeContent.from_dicts(_files, id)
		assert_eq(c.errors, [] as Array[String], id)
		assert_true(c.ok(), id)
		assert_eq(c.shift_id, id)
		assert_false(c.shift.is_empty(), id)


func test_an_unknown_shift_is_an_error() -> void:
	var c := SiegeContent.from_dicts(_files, "nope")
	assert_false(c.ok())


func test_load_for_reads_through_the_context_with_overrides() -> void:
	var ctx := F.make_ctx(1, 0, "drill")
	ctx.content_overrides = {"balance.json": {"c_budget": 30}}
	var c := SiegeContent.load_for(ctx)
	assert_true(c.ok(), str(c.errors))
	assert_eq(c.num("c_budget"), 30.0, "run_game_sim --override reaches the content")
	assert_eq(c.shift_id, "drill")
	F.free_ctx(ctx)


## The brief's numbers, with G2's tuned values where docs/decisions/siege.md records the change
## ("G2 tuning"): c_budget 13, gate 130 HP, tower costs 65 / 52 / 45, Ballista 2.2 s, Scorpion 7
## damage, ram 0.75 m/s, bounty_scale 0.3.
func test_the_brief_s_numbers() -> void:
	var c := SiegeContent.from_dicts(_files, "short")
	assert_eq(c.num("start_denarii"), 40.0)
	assert_eq(c.num("reconnect_s"), 2.0)
	assert_eq(c.num("tower_ref_w"), 250.0)
	assert_eq(c.num("m_cap"), 4.0)
	assert_eq(c.num("c_budget"), 13.0)
	assert_eq(c.num("bounty_scale"), 0.3)
	assert_eq(c.num("gate.hp"), 130.0)
	assert_eq(c.num("gate.breach_s"), 10.0)
	assert_eq(c.num("gate.restore_hp"), 30.0)
	assert_eq(c.num("gate.breach_loss"), 0.3)
	assert_eq(c.balance["generator"]["level_costs"], [60.0, 90.0, 130.0])
	assert_eq(c.num("overdrive.duration_s"), 30.0)
	assert_eq(c.num("overdrive.cooldown_s"), 90.0)
	assert_eq(c.num("rush.budget_frac"), 0.08)
	var t := {
		SiegeIds.TOWER_BALLISTA: [65, 40, 2.2, 30],
		SiegeIds.TOWER_SCORPION: [52, 18, 0.8, 7],
		SiegeIds.TOWER_CALTROP: [45, 25, 4.0, 0],
	}
	for code: int in t:
		var d := c.tower_def(code)
		assert_eq(
			[int(d["cost"]), int(d["range_m"]), float(d["interval_s"]), int(d["damage"])],
			[t[code][0], t[code][1], float(t[code][2]), t[code][3]]
		)
	assert_eq(
		[c.upgrade_cost(1), c.upgrade_cost(2), c.upgrade_cost(3), c.upgrade_cost(4)],
		[40, 50, 70, -1]
	)
	var e := {
		SiegeIds.ENEMY_RAIDERS: [20, 0, 2.2, 1, 1.0],
		SiegeIds.ENEMY_SHIELD_WALL: [160, 8, 0.9, 6, 6.0],
		SiegeIds.ENEMY_HORSEMEN: [35, 0, 4.5, 2, 2.5],
		SiegeIds.ENEMY_RAM: [600, 4, 0.75, 15, 20.0],
	}
	for code: int in e:
		var d := c.enemy_def(code)
		assert_eq(
			[
				int(d["hp"]),
				int(d["armor"]),
				float(d["speed_mps"]),
				int(d["bounty"]),
				float(d["threat"])
			],
			[e[code][0], e[code][1], e[code][2], e[code][3], e[code][4]]
		)
	assert_eq(c.enemies["cap"], 150.0)
	assert_eq(c.tower_def(SiegeIds.TOWER_NONE), {})
	assert_eq(c.enemy_def(9), {})
	assert_eq(
		c.towers["start"], [{"pad": 3.0, "type": "ballista"}, {"pad": 4.0, "type": "scorpion"}]
	)


func test_cosmetics_unlock_thresholds() -> void:
	var ids: Array = []
	var xp: Array = []
	for u: Variant in _files["cosmetics"]["unlocks"]:
		ids.append(u["id"])
		xp.append(int(u["xp"]))
	assert_eq(ids, ["swallowtail_pennant", "walnut_wheel", "bronze_chain_trim", "long_banner"])
	assert_eq(xp, [100, 250, 500, 1000])


func test_each_validator_rejects_a_broken_file() -> void:
	for k: String in FILES_OF:
		var files := _files.duplicate(true)
		_break_file(k, files[k])
		var c := SiegeContent.from_dicts(files, "short")
		assert_false(c.ok(), "%s: a broken file is refused" % k)
		assert_gt(c.errors.size(), 0)
		if c.errors.size() > 0:
			assert_string_contains(c.errors[0], FILES_OF[k])
	var missing := _files.duplicate(true)
	missing["waves"] = null
	assert_false(SiegeContent.from_dicts(missing, "short").ok())


func test_overdrive_balance_is_bounded_by_the_briefs_and_the_governor() -> void:
	var ok: Dictionary = _files["balance"].duplicate(true)
	assert_eq(SiegeContent.validate_balance(ok).size(), 0, "the shipped balance passes")
	for spec: Array in [
		["duration_s", 45.0, "duration_s"],
		["duration_s", 20.0, "duration_s"],
		["duration_s", 0.0, "duration_s"],
		["cooldown_s", 0.0, "cooldown_s"],
		["cooldown_s", 29.0, "cooldown_s"],
		["refused_retry_s", 29.0, "refused_retry_s"],
	]:
		var bad: Dictionary = _files["balance"].duplicate(true)
		bad["overdrive"][spec[0]] = spec[1]
		var errs := SiegeContent.validate_balance(bad)
		assert_gt(errs.size(), 0, "%s = %s is refused" % [spec[0], spec[1]])
		if errs.size() > 0:
			assert_string_contains(errs[0], "overdrive.%s" % spec[2])
	var edge: Dictionary = _files["balance"].duplicate(true)
	edge["overdrive"]["cooldown_s"] = 30.0
	assert_eq(SiegeContent.validate_balance(edge).size(), 0, "cooldown_s = 30 is the floor")


func test_shift_rules_are_enforced() -> void:
	var bad := {
		"x":
		{
			"map": "rotae",
			"phases": [{"role": "break", "kind": "RECOVERY", "target_pct": 50, "duration_s": 60}]
		}
	}
	assert_gt(SiegeContent.validate_shifts(bad).size(), 0, "no wave")
	bad = {
		"x":
		{
			"map": "rotae",
			"phases": [{"role": "wave", "kind": "COOLDOWN", "target_pct": 60, "duration_s": 60}]
		}
	}
	assert_gt(SiegeContent.validate_shifts(bad).size(), 0, "a game-written cool-down")
	bad = {
		"x":
		{
			"map": "rotae",
			"phases":
			[
				{
					"role": "wave",
					"kind": "WORK",
					"target_pct": 70,
					"duration_s": 600,
					"rushes_at_s": [560]
				}
			]
		}
	}
	assert_gt(SiegeContent.validate_shifts(bad).size(), 0, "a rush that ends inside the last 60 s")
	bad = {
		"x":
		{
			"map": "rotae",
			"phases":
			[{"role": "warmup_wave", "kind": "WARMUP", "target_pct": 50, "duration_s": 300}]
		}
	}
	assert_gt(SiegeContent.validate_shifts(bad).size(), 0, "a warm-up wave without its ramp")


func _break_file(k: String, d: Dictionary) -> void:
	match k:
		"shifts":
			d["short"]["phases"][2]["target_pct"] = 130
		"balance":
			d["overdrive"]["duration_s"] = 45
		"towers":
			d["ballista"].erase("range_m")
		"enemies":
			d["ram"].erase("gate_hp_per_s")
		"waves":
			d["mix"]["standard"][0] = [0.5, 0.5, 0.5]
		"cosmetics":
			d["unlocks"][1]["xp"] = 50
