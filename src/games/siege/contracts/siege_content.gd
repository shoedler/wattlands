class_name SiegeContent
extends RefCounted
## Every Siege content file, loaded and validated together (brief 2.4 "Every number below lives
## in content/siege/*.json, validated at load"; BRIEF 6). G0 contract.
##
## Files under content/siege/ (each validator below lists the fields it enforces; extra fields
## are allowed, so builders may add tuning knobs and ask the lead to extend the validator):
##   shifts.json    {<content id>: {map, label, total_s, phases: [{role, kind, target_pct,
##                  ramp_to_pct?, duration_s, rushes_at_s?, mix?}]}} (SiegePlanBuilder reads it)
##   balance.json   economy, gate, shop prices, perks, Overdrive, rush, Autopilot, score, XP
##   towers.json    {ballista|scorpion|caltrop: {code, cost, range_m, interval_s, damage, targets,
##                  ...}, upgrades: [{level, cost, effect}], start: [{pad, type}]}
##   enemies.json   {raiders|shield_wall|horsemen|ram: {code, hp, armor, speed_mps, bounty, threat,
##                  gate_hp | gate_hp_per_s}, lateral_m, cap, retreat_s}
##   waves.json     group cadence, mixes, ram push, road rotation, warm-up wave, rush
##   cosmetics.json {unlocks: [{id, xp, kind}]} ascending xp
##   maps/<id>.json SiegeMap.validate()
## Load in the module with load_for(ctx) (through ctx.load_content_json, so run_game_sim
## --override reaches every file); tests and the headless sim use read_files() + from_dicts().

const FILES := {
	"shifts": "shifts.json",
	"balance": "balance.json",
	"towers": "towers.json",
	"enemies": "enemies.json",
	"waves": "waves.json",
	"cosmetics": "cosmetics.json",
}
const CONTENT_DIR := "res://content/siege"
const PHASE_KINDS: Array[String] = [Wl.WARMUP, Wl.WORK, Wl.RECOVERY]
const MIN_PCT := 50.0
const MAX_PCT := 117.0

## Paths -> kind for balance.json: "num" any number, "pos" > 0, "nonneg" >= 0, "obj", "arr".
const BALANCE_SPEC := {
	"start_denarii": "nonneg",
	"reconnect_s": "nonneg",
	"tower_ref_w": "pos",
	"m_cap": "pos",
	"bounty_scale": "nonneg",
	"c_budget": "nonneg",
	"budget_ref_w": "pos",
	"unverified_factor": "pos",
	"wkg_min_power_w": "nonneg",
	"generator.denarii_per_kj": "pos",
	"generator.level_bonus": "nonneg",
	"generator.level_costs": "arr",
	"gate.hp": "pos",
	"gate.iron_bands_hp": "nonneg",
	"gate.iron_bands_max": "nonneg",
	"gate.repair_hp": "nonneg",
	"gate.breach_s": "nonneg",
	"gate.restore_hp": "pos",
	"gate.breach_loss": "nonneg",
	"gate.warmup_floor_hp": "nonneg",
	"shop.iron_bands": "nonneg",
	"shop.repair": "nonneg",
	"shop.reserve_flywheel": "nonneg",
	"shop.aqueduct_drive": "nonneg",
	"shop.countdown_s": "nonneg",
	"perks.reserve_hold_s": "nonneg",
	"perks.aqueduct_m": "nonneg",
	"overdrive.duration_s": "pos",
	"overdrive.cooldown_s": "nonneg",
	"overdrive.refused_retry_s": "nonneg",
	"overdrive.min_left_s": "pos",
	"overdrive.od_mult": "pos",
	"overdrive.sprint_hold_s": "pos",
	"overdrive.band_lo_ftp": "pos",
	"overdrive.band_hi_ftp": "pos",
	"rush.budget_frac": "nonneg",
	"rush.duration_s": "pos",
	"rush.od_bounty_mult": "pos",
	"autopilot.route_every_s": "pos",
	"autopilot.switch_min_s": "nonneg",
	"autopilot.switch_margin": "nonneg",
	"autopilot.shop_max": "nonneg",
	"autopilot.shop_at_s": "arr",
	"autopilot.repair_below_frac": "nonneg",
	"score.gate_pts": "nonneg",
	"score.breach_pts": "nonneg",
	"score.breach_cost": "nonneg",
	"score.earn_pts": "nonneg",
	"score.par_frac": "pos",
	"score.grades.S": "num",
	"score.grades.A": "num",
	"score.grades.B": "num",
	"score.grades.C": "num",
	"xp.kj_per_xp": "pos",
	"xp.grade_bonus.S": "nonneg",
	"xp.grade_bonus.A": "nonneg",
	"xp.grade_bonus.B": "nonneg",
	"xp.grade_bonus.C": "nonneg",
	"xp.grade_bonus.D": "nonneg",
}
const TOWER_SPEC := {
	"code": "pos", "cost": "nonneg", "range_m": "pos", "interval_s": "pos", "damage": "nonneg"
}
const ENEMY_SPEC := {
	"code": "pos",
	"hp": "pos",
	"armor": "nonneg",
	"speed_mps": "pos",
	"bounty": "nonneg",
	"threat": "pos"
}
const WAVES_SPEC := {
	"group_every_s": "arr",
	"stop_before_end_s": "nonneg",
	"mix": "obj",
	"ram_push.at_left_s": "pos",
	"ram_push.enter_from_gate_m": "pos",
	"ram_push.escort_threat_per_slot": "nonneg",
	"roads.rotate_s": "arr",
	"roads.horn_s": "nonneg",
	"warmup.budget_frac": "nonneg",
	"warmup.raiders_only_s": "nonneg",
	"warmup.ram_hp_frac": "pos",
	"warmup.gate_floor_hp": "nonneg",
	"warmup.toast_every_s": "pos",
	"rush.types": "arr",
}

var shift_id: String = ""
## shifts.json[shift_id]
var shift: Dictionary = {}
var shifts: Dictionary = {}
var balance: Dictionary = {}
var towers: Dictionary = {}
var enemies: Dictionary = {}
var waves: Dictionary = {}
var cosmetics: Dictionary = {}
var map: SiegeMap = null
## Every problem found ("<file>: <field>: <reason>"); empty when the content is usable.
var errors: Array[String] = []


func ok() -> bool:
	return errors.is_empty() and map != null


## Loads and validates every file through ctx.load_content_json (overrides applied) for
## ctx.content_id. Never push_errors itself: the caller reports `errors` (the host with
## push_error, a client quietly).
static func load_for(ctx: GameContext) -> SiegeContent:
	var files := {}
	for k: String in FILES:
		files[k] = ctx.load_content_json(FILES[k])
	var sh: Variant = files["shifts"]
	var map_id := "rotae"
	if sh is Dictionary and (sh as Dictionary).get(ctx.content_id) is Dictionary:
		map_id = str(sh[ctx.content_id].get("map", map_id))
	files["map"] = ctx.load_content_json("maps/%s.json" % map_id)
	return from_dicts(files, ctx.content_id)


## Reads every file straight from res://content/siege (no overrides): tests, the headless sim.
static func read_files(map_id: String = "rotae") -> Dictionary:
	var files := {}
	for k: String in FILES:
		files[k] = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_DIR.path_join(FILES[k])))
	files["map"] = JSON.parse_string(
		FileAccess.get_file_as_string(CONTENT_DIR.path_join("maps/%s.json" % map_id))
	)
	return files


## Content from already-parsed files {shifts, balance, towers, enemies, waves, cosmetics, map}
## for shift `shift_id`, validated.
static func from_dicts(files: Dictionary, p_shift_id: String) -> SiegeContent:
	var c := SiegeContent.new()
	c.shift_id = p_shift_id
	c.errors.append_array(validate_shifts(files.get("shifts")))
	c.errors.append_array(validate_balance(files.get("balance")))
	c.errors.append_array(validate_towers(files.get("towers")))
	c.errors.append_array(validate_enemies(files.get("enemies")))
	c.errors.append_array(validate_waves(files.get("waves")))
	c.errors.append_array(validate_cosmetics(files.get("cosmetics")))
	c.errors.append_array(SiegeMap.validate(files.get("map")))
	for k: String in FILES:
		if not (files.get(k) is Dictionary):
			return c
	c.shifts = files["shifts"]
	c.balance = files["balance"]
	c.towers = files["towers"]
	c.enemies = files["enemies"]
	c.waves = files["waves"]
	c.cosmetics = files["cosmetics"]
	if not c.shifts.has(p_shift_id):
		c.errors.append("shifts.json: no shift %s" % p_shift_id)
	else:
		c.shift = c.shifts[p_shift_id]
	if files.get("map") is Dictionary:
		c.map = SiegeMap.from_dict(files["map"])
	return c


## towers.json entry for tower code 1..3 ({} for TOWER_NONE).
func tower_def(code: int) -> Dictionary:
	if code <= 0 or code >= SiegeIds.TOWER_NAMES.size():
		return {}
	return towers.get(SiegeIds.TOWER_NAMES[code], {})


## enemies.json entry for enemy code 1..4.
func enemy_def(code: int) -> Dictionary:
	if code <= 0 or code >= SiegeIds.ENEMY_NAMES.size():
		return {}
	return enemies.get(SiegeIds.ENEMY_NAMES[code], {})


## Cost of tower upgrade `level` (1..3), -1 if none.
func upgrade_cost(level: int) -> int:
	for u: Variant in towers.get("upgrades", []):
		if int(u.get("level", 0)) == level:
			return int(u.get("cost", -1))
	return -1


## A balance.json number by dotted path ("overdrive.cooldown_s"), or `default`.
func num(path: String, default: float = 0.0) -> float:
	var v: Variant = _at(balance, path)
	return float(v) if (v is float or v is int) else default


# --- validators (each returns "<file>: <problem>" lines; empty = valid) -------------------------


## shifts.json: every shift has map (String) and a non-empty phases array; each phase has role
## (SiegeIds.SHIFT_ROLES), kind (WARMUP, WORK or RECOVERY), target_pct and optional ramp_to_pct
## in 50..117, duration_s > 0; a warmup_wave is first, WARMUP and ramps; waves are WORK or
## WARMUP; breaks are RECOVERY or WARMUP; at least one wave; rushes_at_s (waves only) ascending
## and each rush ends >= 60 s before its wave; mix (waves only) is a waves.json mix id.
static func validate_shifts(d: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		errs.append("shifts.json: must be a non-empty object")
		return errs
	for id: Variant in d:
		var at := "shifts.json: %s" % id
		var sh: Variant = d[id]
		if not (sh is Dictionary) or not (sh.get("map") is String):
			errs.append("%s: needs map" % at)
			continue
		var phases: Variant = sh.get("phases")
		if not (phases is Array) or (phases as Array).is_empty():
			errs.append("%s: needs a non-empty phases array" % at)
			continue
		var waves := 0
		for i in (phases as Array).size():
			var ph: Variant = phases[i]
			var pat := "%s: phases[%d]" % [at, i]
			if not (ph is Dictionary):
				errs.append("%s: not an object" % pat)
				continue
			var role := str(ph.get("role", ""))
			var kind := str(ph.get("kind", ""))
			if not SiegeIds.SHIFT_ROLES.has(role):
				errs.append("%s: role %s unknown" % [pat, role])
			if not PHASE_KINDS.has(kind):
				errs.append("%s: kind must be WARMUP, WORK or RECOVERY" % pat)
			if not _pct_ok(ph.get("target_pct")):
				errs.append("%s: target_pct must be 50..117" % pat)
			if ph.has("ramp_to_pct") and not _pct_ok(ph.get("ramp_to_pct")):
				errs.append("%s: ramp_to_pct must be 50..117" % pat)
			if not _is_num(ph.get("duration_s")) or float(ph["duration_s"]) <= 0.0:
				errs.append("%s: duration_s must be > 0" % pat)
				continue
			match role:
				SiegeIds.ROLE_WARMUP_WAVE:
					if i != 0 or kind != Wl.WARMUP or not ph.has("ramp_to_pct"):
						errs.append(
							"%s: a warmup_wave is the first phase, WARMUP, with a ramp" % pat
						)
				SiegeIds.ROLE_WAVE:
					waves += 1
					if kind != Wl.WORK and kind != Wl.WARMUP:
						errs.append("%s: a wave is WORK or WARMUP" % pat)
				SiegeIds.ROLE_BREAK, SiegeIds.ROLE_BUILD_BREAK:
					if kind != Wl.RECOVERY and kind != Wl.WARMUP:
						errs.append("%s: a break is RECOVERY or WARMUP" % pat)
			if (
				ph.has("mix")
				and (
					role != SiegeIds.ROLE_WAVE
					or not str(ph["mix"]) in [SiegeIds.MIX_STANDARD, SiegeIds.MIX_RAIDERS_HORSEMEN]
				)
			):
				errs.append("%s: mix is standard or raiders_horsemen, waves only" % pat)
			if ph.has("rushes_at_s"):
				var last := -1.0
				var rok: bool = role == SiegeIds.ROLE_WAVE and ph["rushes_at_s"] is Array
				for r: Variant in ph["rushes_at_s"] if rok else []:
					rok = rok and _is_num(r) and float(r) > last
					rok = rok and float(r) + 30.0 <= float(ph["duration_s"]) - 60.0
					last = float(r) if _is_num(r) else last
				if not rok:
					errs.append(
						"%s: rushes_at_s: ascending wave times ending >= 60 s before its end" % pat
					)
		if waves == 0:
			errs.append("%s: needs at least one wave" % at)
	return errs


## balance.json: every path in BALANCE_SPEC with its kind; generator.level_costs has 3 numbers;
## overdrive.duration_s is exactly 30 (brief 2.3 fixes the directive's block at 30 s; a SIM block is
## 10..30, BRIEF 4.5) and min_left_s >= it; refused_retry_s and cooldown_s >= 30 (the governor's
## switch spacing: a shorter cooldown would only earn sim_block switch_spacing refusals); grades
## descend S > A > B > C.
static func validate_balance(d: Variant) -> Array[String]:
	var errs := _check_spec(d, BALANCE_SPEC, "balance.json")
	if not errs.is_empty():
		return errs
	if (d["generator"]["level_costs"] as Array).size() != 3:
		errs.append("balance.json: generator.level_costs needs 3 costs")
	var od: Dictionary = d["overdrive"]
	if not is_equal_approx(float(od["duration_s"]), 30.0):
		errs.append("balance.json: overdrive.duration_s must be 30 (brief 2.3 fixes the directive)")
	if float(od["min_left_s"]) < float(od["duration_s"]):
		errs.append("balance.json: overdrive.min_left_s must be >= duration_s")
	if float(od["refused_retry_s"]) < 30.0:
		errs.append("balance.json: overdrive.refused_retry_s must be >= 30 (switch spacing)")
	if float(od["cooldown_s"]) < 30.0:
		errs.append("balance.json: overdrive.cooldown_s must be >= 30 (switch spacing)")
	var g: Dictionary = d["score"]["grades"]
	if not (
		float(g["S"]) > float(g["A"])
		and float(g["A"]) > float(g["B"])
		and float(g["B"]) > float(g["C"])
	):
		errs.append("balance.json: score.grades must descend S > A > B > C")
	return errs


## towers.json: ballista, scorpion and caltrop each with TOWER_SPEC fields and their code;
## upgrades are levels 1, 2, 3 with a cost; start lists {pad 1..8, type (a tower name)}.
static func validate_towers(d: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not (d is Dictionary):
		errs.append("towers.json: not an object")
		return errs
	for code in range(1, SiegeIds.TOWER_NAMES.size()):
		var name: String = SiegeIds.TOWER_NAMES[code]
		var t: Variant = d.get(name)
		errs.append_array(_check_spec(t, TOWER_SPEC, "towers.json: " + name))
		if t is Dictionary and int(t.get("code", 0)) != code:
			errs.append("towers.json: %s: code must be %d" % [name, code])
	var ups: Variant = d.get("upgrades")
	var levels: Array = []
	for u: Variant in ups if ups is Array else []:
		if u is Dictionary and _is_num(u.get("cost")):
			levels.append(int(u.get("level", 0)))
	if levels != [1, 2, 3]:
		errs.append("towers.json: upgrades must be levels 1, 2, 3 with a cost")
	for s: Variant in d.get("start", []):
		if (
			not (s is Dictionary)
			or not SiegeIds.is_pad(int(s.get("pad", 0)))
			or SiegeIds.tower_code(str(s.get("type", ""))) == 0
		):
			errs.append("towers.json: bad start entry %s" % JSON.stringify(s))
	return errs


## enemies.json: raiders, shield_wall, horsemen and ram each with ENEMY_SPEC fields and their
## code; gate_hp (> 0) for the first three, gate_hp_per_s and crew for the ram; lateral_m >= 0,
## cap >= 1, retreat_s >= 0.
static func validate_enemies(d: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not (d is Dictionary):
		errs.append("enemies.json: not an object")
		return errs
	for code in range(1, SiegeIds.ENEMY_NAMES.size()):
		var name: String = SiegeIds.ENEMY_NAMES[code]
		var e: Variant = d.get(name)
		errs.append_array(_check_spec(e, ENEMY_SPEC, "enemies.json: " + name))
		if not (e is Dictionary):
			continue
		if int(e.get("code", 0)) != code:
			errs.append("enemies.json: %s: code must be %d" % [name, code])
		var gate_key := "gate_hp_per_s" if code == SiegeIds.ENEMY_RAM else "gate_hp"
		if not _is_num(e.get(gate_key)) or float(e[gate_key]) <= 0.0:
			errs.append("enemies.json: %s: %s must be > 0" % [name, gate_key])
		if (
			code == SiegeIds.ENEMY_RAM
			and (
				not _is_num(e.get("crew")) or SiegeIds.enemy_code(str(e.get("crew_type", ""))) == 0
			)
		):
			errs.append("enemies.json: ram: needs crew and crew_type")
	errs.append_array(
		_check_spec(d, {"lateral_m": "nonneg", "cap": "pos", "retreat_s": "nonneg"}, "enemies.json")
	)
	return errs


## waves.json: WAVES_SPEC; group_every_s and roads.rotate_s are [lo, hi] with lo <= hi; mix
## has standard and raiders_horsemen, each 3 rows (thirds of the shift) of 3 fractions
## [raiders, shield_wall, horsemen] summing to 1; rush.types are enemy names.
static func validate_waves(d: Variant) -> Array[String]:
	var errs := _check_spec(d, WAVES_SPEC, "waves.json")
	if not errs.is_empty():
		return errs
	for k: String in ["group_every_s", "roads.rotate_s"]:
		var r: Variant = _at(d, k)
		if (
			(r as Array).size() != 2
			or not _is_num(r[0])
			or not _is_num(r[1])
			or float(r[0]) > float(r[1])
		):
			errs.append("waves.json: %s must be [lo, hi]" % k)
	for mix: String in [SiegeIds.MIX_STANDARD, SiegeIds.MIX_RAIDERS_HORSEMEN]:
		var rows: Variant = d["mix"].get(mix)
		var ok: bool = rows is Array and (rows as Array).size() == 3
		for row: Variant in rows if ok else []:
			var sum := 0.0
			ok = ok and row is Array and (row as Array).size() == 3
			for f: Variant in row if ok else []:
				ok = ok and _is_num(f) and float(f) >= 0.0
				sum += float(f) if _is_num(f) else 0.0
			ok = ok and absf(sum - 1.0) < 1e-6
		if not ok:
			errs.append("waves.json: mix.%s needs 3 rows of 3 fractions summing to 1" % mix)
	for t: Variant in d["rush"]["types"]:
		if SiegeIds.enemy_code(str(t)) == 0:
			errs.append("waves.json: rush.types: unknown enemy %s" % t)
	return errs


## cosmetics.json: unlocks is an array of {id ([a-z0-9_]+, unique), xp > 0, kind}, xp ascending.
static func validate_cosmetics(d: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not (d is Dictionary) or not (d.get("unlocks") is Array):
		errs.append("cosmetics.json: needs an unlocks array")
		return errs
	var re := RegEx.create_from_string("^[a-z0-9_]+$")
	var seen := {}
	var last := 0.0
	for u: Variant in d["unlocks"]:
		if (
			not (u is Dictionary)
			or re.search(str(u.get("id", ""))) == null
			or seen.has(u.get("id"))
			or not _is_num(u.get("xp"))
			or float(u["xp"]) <= last
			or not (u.get("kind") is String)
		):
			errs.append(
				"cosmetics.json: bad unlock %s (id, xp ascending, kind)" % JSON.stringify(u)
			)
			continue
		seen[u["id"]] = true
		last = float(u["xp"])
	return errs


static func _check_spec(d: Variant, spec: Dictionary, file: String) -> Array[String]:
	var errs: Array[String] = []
	if not (d is Dictionary):
		errs.append("%s: not an object" % file)
		return errs
	for path: String in spec:
		var v: Variant = _at(d, path)
		var ok := true
		match str(spec[path]):
			"num":
				ok = _is_num(v)
			"pos":
				ok = _is_num(v) and float(v) > 0.0
			"nonneg":
				ok = _is_num(v) and float(v) >= 0.0
			"obj":
				ok = v is Dictionary
			"arr":
				ok = v is Array
		if not ok:
			errs.append("%s: %s must be %s" % [file, path, spec[path]])
	return errs


static func _at(d: Variant, path: String) -> Variant:
	var v: Variant = d
	for k in path.split("."):
		if not (v is Dictionary) or not (v as Dictionary).has(k):
			return null
		v = v[k]
	return v


static func _is_num(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


static func _pct_ok(v: Variant) -> bool:
	return _is_num(v) and float(v) >= MIN_PCT and float(v) <= MAX_PCT
