class_name SiegeContent
extends RefCounted
## Every Siege content file, loaded and validated together (brief 2.4 "Every number below lives
## in content/siege/*.json, validated at load"; BRIEF 6).
##
## Files under content/siege/ (each validator below lists the fields it enforces; extra fields
## are allowed as tuning knobs):
##   shifts.json    {<content id>: {map, label, total_s, phases: [{role, kind, target_pct,
##                  ramp_to_pct?, duration_s, rushes_at_s?, mix?}]}} (SiegePlanBuilder reads it)
##   balance.json   economy, the mine, gate, shop prices, perks, Overdrive, rush, Autopilot, score,
##                  XP
##   stations.json  the five stations (caps, winding, range bands, slew, projectiles and their
##                  spread_deg / speed_spread, effects), the pads' Scorpion, upgrade costs
##   enemies.json   {spear|shield|chariot|ram|tower: {code, hp, armour, speed_mps, bounty, threat,
##                  body_r_m, body_h_m, gate_hp | gate_hp_per_s, ...}, lateral_m, cap, retreat_s}
##   waves.json     group cadence, mixes, staging, siege engines, the warm-up wave, rushes
##   cosmetics.json {unlocks: [{id, xp, kind}]} ascending xp
##   maps/<id>.json SiegePath.validate()
## Load in the module with load_for(ctx) (through ctx.load_content_json, so run_game_sim
## --override reaches every file); tests and the headless sim use read_files() + from_dicts().

const FILES := {
	"shifts": "shifts.json",
	"balance": "balance.json",
	"stations": "stations.json",
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
	"start_gold": "nonneg",
	"reconnect_s": "nonneg",
	"ref_w": "pos",
	"m_cap": "pos",
	"bounty_scale": "nonneg",
	"c_budget": "nonneg",
	"budget_ref_w": "pos",
	"unverified_factor": "pos",
	"wkg_min_power_w": "nonneg",
	"mine.gold_per_kj": "pos",
	"mine.level_bonus": "nonneg",
	"mine.level_costs": "arr",
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
	"shop.spare_cauldron": "nonneg",
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
	"autopilot.look_ahead_s": "pos",
	"autopilot.mine_score": "nonneg",
	"autopilot.tar_min_frac": "nonneg",
	"autopilot.tar_engine_m": "nonneg",
	"autopilot.tar_any_m": "nonneg",
	"autopilot.tar_scale": "nonneg",
	"autopilot.weights": "obj",
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
const STATIONS_SPEC := {
	"align_deg": "pos",
	"retarget_s": "pos",
	"lead_rounds": "pos",
	"upgrade_costs": "arr",
	"upgrade_out_mult": "pos",
	"upgrade_range_mult": "pos",
	"stations": "obj",
	"pads": "obj",
}
## Every weapon station (ballista, onager, arrows).
const WEAPON_SPEC := {
	"id": "nonneg",
	"cap": "pos",
	"range_m": "arr",
	"slew_dps": "pos",
	"k": "nonneg",
	"spread_deg": "nonneg",
	"speed_spread": "nonneg",
	"damage": "pos",
	"prefer": "obj",
}
const BALLISTA_SPEC := {
	"wind_s": "pos",
	"speed_mps": "pos",
	"aim_dz_m": "nonneg",
	"hit_r_m": "pos",
	"keep_infantry": "nonneg",
	"keep_engine": "nonneg",
	"stop_below": "nonneg",
}
const ONAGER_SPEC := {
	"wind_s": "pos",
	"elev_deg": "pos",
	"v_min": "pos",
	"v_max": "pos",
	"v_max_upgraded": "pos",
	"splash_m": "pos",
	"falloff": "nonneg",
	"engine_direct_m": "nonneg",
	"engine_mult": "pos",
	"docked_mult": "pos",
	"special_splash_m": "pos",
}
const ARROWS_SPEC := {
	"rack_s": "pos",
	"racks": "pos",
	"special_racks": "pos",
	"per_rack": "pos",
	"elev_deg": "pos",
	"v_min": "pos",
	"v_max": "pos",
	"v_max_upgraded": "pos",
	"hit_r_m": "pos",
	"testudo_block": "nonneg",
}
const TAR_SPEC := {
	"id": "nonneg",
	"cap": "pos",
	"pump_lps": "pos",
	"cauldron_l": "pos",
	"spare_cauldron_l": "nonneg",
	"reheat_lps": "nonneg",
	"curtain_max": "pos",
	"curtain_drain_hps": "nonneg",
	"coat_full_hp": "pos",
	"coat_slow": "nonneg",
	"special_coat_slow": "nonneg",
}
const SCORPION_SPEC := {
	"code": "pos",
	"cost": "nonneg",
	"interval_s": "pos",
	"range_m": "arr",
	"speed_mps": "pos",
	"k": "nonneg",
	"damage": "pos",
	"hit_r_m": "pos",
	"spread_deg": "nonneg",
	"speed_spread": "nonneg",
	"aim_dz_m": "nonneg",
	"rate_mult": "pos",
	"range_mult": "pos",
	"special_bolts": "pos",
}
const ENEMY_SPEC := {
	"code": "pos",
	"hp": "pos",
	"armour": "nonneg",
	"speed_mps": "pos",
	"bounty": "nonneg",
	"threat": "pos",
	"body_r_m": "nonneg",
	"body_h_m": "pos",
}
const WAVES_SPEC := {
	"group_every_s": "arr",
	"first_group_s": "nonneg",
	"stop_before_end_s": "nonneg",
	"group_var": "arr",
	"mix": "obj",
	"staging.reach_before_end_s": "nonneg",
	"staging.formation_gap_m": "nonneg",
	"engines.push_lead_s": "pos",
	"engines.pair_gap_m": "nonneg",
	"engines.two_rams_from_slots": "pos",
	"engines.escort_threat_per_slot": "nonneg",
	"engines.tower_min_wave_s": "pos",
	"engines.crew_back_m": "arr",
	"warmup.budget_frac": "nonneg",
	"warmup.spear_only_s": "nonneg",
	"warmup.ram_hp_frac": "pos",
	"warmup.gate_floor_hp": "nonneg",
	"warmup.toast_every_s": "pos",
	"rush.types": "arr",
	"rush.group_every_s": "pos",
}

var shift_id: String = ""
## shifts.json[shift_id]
var shift: Dictionary = {}
var shifts: Dictionary = {}
var balance: Dictionary = {}
var stations: Dictionary = {}
var enemies: Dictionary = {}
var waves: Dictionary = {}
var cosmetics: Dictionary = {}
## The battlefield (maps/<id>.json).
var path: SiegePath = null
## Every problem found ("<file>: <field>: <reason>"); empty when the content is usable.
var errors: Array[String] = []


func ok() -> bool:
	return errors.is_empty() and path != null


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


## Content from already-parsed files {shifts, balance, stations, enemies, waves, cosmetics, map}
## for shift `shift_id`, validated.
static func from_dicts(files: Dictionary, p_shift_id: String) -> SiegeContent:
	var c := SiegeContent.new()
	c.shift_id = p_shift_id
	c.errors.append_array(validate_shifts(files.get("shifts")))
	c.errors.append_array(validate_balance(files.get("balance")))
	c.errors.append_array(validate_stations(files.get("stations")))
	c.errors.append_array(validate_enemies(files.get("enemies")))
	c.errors.append_array(validate_waves(files.get("waves")))
	c.errors.append_array(validate_cosmetics(files.get("cosmetics")))
	var map_d: Variant = files.get("map")
	if map_d is Dictionary:
		for e in SiegePath.validate(map_d):
			c.errors.append("map: " + e)
	else:
		c.errors.append("map: not an object")
	for k: String in FILES:
		if not (files.get(k) is Dictionary):
			return c
	c.shifts = files["shifts"]
	c.balance = files["balance"]
	c.stations = files["stations"]
	c.enemies = files["enemies"]
	c.waves = files["waves"]
	c.cosmetics = files["cosmetics"]
	if not c.shifts.has(p_shift_id):
		c.errors.append("shifts.json: no shift %s" % p_shift_id)
	else:
		c.shift = c.shifts[p_shift_id]
	if map_d is Dictionary:
		c.path = SiegePath.from_dict(map_d)
	return c


## stations.json "stations" entry of station `id` 0..4 ({} when unknown).
func station_def(id: int) -> Dictionary:
	if not SiegeIds.is_station(id):
		return {}
	return (stations.get("stations", {}) as Dictionary).get(SiegeIds.STATION_NAMES[id], {})


## stations.json "pads" entry of pad type `code` ({} for PAD_NONE).
func pad_def(code: int) -> Dictionary:
	if code <= 0 or code >= SiegeIds.PAD_NAMES.size():
		return {}
	return (stations.get("pads", {}) as Dictionary).get(SiegeIds.PAD_NAMES[code], {})


## enemies.json entry for enemy code 1..5.
func enemy_def(code: int) -> Dictionary:
	if code <= 0 or code >= SiegeIds.ENEMY_NAMES.size():
		return {}
	return enemies.get(SiegeIds.ENEMY_NAMES[code], {})


## Cost of station upgrade `level` (1..3), -1 if none.
func station_upgrade_cost(level: int) -> int:
	var costs: Array = stations.get("upgrade_costs", [])
	return int(costs[level - 1]) if level >= 1 and level <= costs.size() else -1


## Cost of pad upgrade `level` (1..3), -1 if none.
func pad_upgrade_cost(level: int) -> int:
	var costs: Array = (stations.get("pads", {}) as Dictionary).get("upgrade_costs", [])
	return int(costs[level - 1]) if level >= 1 and level <= costs.size() else -1


## Cost of mine level `level` (1..3), -1 if none.
func mine_level_cost(level: int) -> int:
	var costs: Array = (balance.get("mine", {}) as Dictionary).get("level_costs", [])
	return int(costs[level - 1]) if level >= 1 and level <= costs.size() else -1


## A balance.json number by dotted path ("overdrive.cooldown_s"), or `default`.
func num(p_path: String, default: float = 0.0) -> float:
	var v: Variant = _at(balance, p_path)
	return float(v) if (v is float or v is int) else default


## A stations.json number by dotted path ("stations.onager.wind_s"), or `default`.
func st_num(p_path: String, default: float = 0.0) -> float:
	var v: Variant = _at(stations, p_path)
	return float(v) if (v is float or v is int) else default


## A station's range band [lo, hi] in metres (horizontal from the pivot), before upgrades.
func range_band(id: int) -> Vector2:
	var r: Variant = station_def(id).get("range_m")
	if r is Array and (r as Array).size() == 2:
		return Vector2(float(r[0]), float(r[1]))
	return Vector2.ZERO


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


## balance.json: every path in BALANCE_SPEC with its kind; mine.level_costs has 3 numbers;
## autopilot.weights has a weight >= 0 per weapon station and enemy type;
## overdrive.duration_s is exactly 30 (brief 2.3 fixes the directive's block at 30 s; a SIM block is
## 10..30, BRIEF 4.5) and min_left_s >= it; refused_retry_s and cooldown_s >= 30 (the governor's
## switch spacing: a shorter cooldown would only earn sim_block switch_spacing refusals); grades
## descend S > A > B > C.
static func validate_balance(d: Variant) -> Array[String]:
	var errs := _check_spec(d, BALANCE_SPEC, "balance.json")
	if not errs.is_empty():
		return errs
	if (d["mine"]["level_costs"] as Array).size() != 3:
		errs.append("balance.json: mine.level_costs needs 3 costs")
	for st: String in ["ballista", "onager", "arrows"]:
		var w: Variant = d["autopilot"]["weights"].get(st)
		if not (w is Dictionary):
			errs.append("balance.json: autopilot.weights.%s is missing" % st)
			continue
		for en in SiegeIds.ENEMY_NAMES.slice(1):
			if not _is_num(w.get(en)) or float(w[en]) < 0.0:
				errs.append("balance.json: autopilot.weights.%s.%s must be >= 0" % [st, en])
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


## stations.json: STATIONS_SPEC; upgrade_costs and pads.upgrade_costs are 3 costs; every station
## 0..4 with its id and a cap >= 1 (caps sum to at least 4, so four riders always fit); the
## weapons with WEAPON_SPEC and their own spec, range_m [lo, hi] with lo <= hi, a "prefer" weight
## per enemy type; the tar works with TAR_SPEC; pads.scorpion with SCORPION_SPEC and its code;
## pads.start lists {pad 1..4, type (a pad weapon name)}.
static func validate_stations(d: Variant) -> Array[String]:
	var errs := _check_spec(d, STATIONS_SPEC, "stations.json")
	if not errs.is_empty():
		return errs
	if (d["upgrade_costs"] as Array).size() != 3:
		errs.append("stations.json: upgrade_costs needs 3 costs")
	var caps := 0
	for id in SiegeIds.STATION_COUNT:
		var name: String = SiegeIds.STATION_NAMES[id]
		var at := "stations.json: stations.%s" % name
		var sd: Variant = d["stations"].get(name)
		if not (sd is Dictionary):
			errs.append("%s is missing" % at)
			continue
		if int(sd.get("id", -1)) != id:
			errs.append("%s: id must be %d" % [at, id])
		if not _is_num(sd.get("cap")) or int(sd["cap"]) < 1:
			errs.append("%s: cap must be >= 1" % at)
		else:
			caps += int(sd["cap"])
		var own := {}
		match id:
			SiegeIds.STATION_BALLISTA:
				own = BALLISTA_SPEC
			SiegeIds.STATION_ONAGER:
				own = ONAGER_SPEC
			SiegeIds.STATION_ARROWS:
				own = ARROWS_SPEC
			SiegeIds.STATION_TAR:
				errs.append_array(_check_spec(sd, TAR_SPEC, at))
		if own.is_empty():
			continue
		errs.append_array(_check_spec(sd, WEAPON_SPEC, at))
		errs.append_array(_check_spec(sd, own, at))
		errs.append_array(_pair_ok(sd.get("range_m"), at + ": range_m"))
		var pref: Variant = sd.get("prefer")
		for en in SiegeIds.ENEMY_NAMES.slice(1):
			if pref is Dictionary and (not _is_num(pref.get(en)) or float(pref[en]) < 0.0):
				errs.append("%s: prefer.%s must be >= 0" % [at, en])
	if caps < 4:
		errs.append("stations.json: the caps sum to %d (four riders need 4)" % caps)
	var pads: Dictionary = d["pads"]
	var sc: Variant = pads.get("scorpion")
	errs.append_array(_check_spec(sc, SCORPION_SPEC, "stations.json: pads.scorpion"))
	if sc is Dictionary:
		if int(sc.get("code", 0)) != SiegeIds.PAD_SCORPION:
			errs.append("stations.json: pads.scorpion: code must be %d" % SiegeIds.PAD_SCORPION)
		errs.append_array(_pair_ok(sc.get("range_m"), "stations.json: pads.scorpion: range_m"))
	if not (pads.get("upgrade_costs") is Array) or (pads["upgrade_costs"] as Array).size() != 3:
		errs.append("stations.json: pads.upgrade_costs needs 3 costs")
	for s: Variant in pads.get("start", []):
		if (
			not (s is Dictionary)
			or not SiegeIds.is_pad(int(s.get("pad", 0)))
			or SiegeIds.pad_code(str(s.get("type", ""))) != SiegeIds.PAD_SCORPION
		):
			errs.append("stations.json: bad pads.start entry %s" % JSON.stringify(s))
	return errs


## enemies.json: spear, shield, chariot, ram and tower each with ENEMY_SPEC fields and their
## code; gate_hp (> 0) for the first three, gate_hp_per_s and crew / crew_type for the ram; the
## first three have ranks [files, ranks] >= 1 and spacing_m > 0; the chariot speed_var 0..1,
## redraw_s [lo, hi] and accel_mps2 > 0; lateral_m >= 0, cap >= 1, retreat_s >= 0.
static func validate_enemies(d: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not (d is Dictionary):
		errs.append("enemies.json: not an object")
		return errs
	for code in range(1, SiegeIds.ENEMY_NAMES.size()):
		var name: String = SiegeIds.ENEMY_NAMES[code]
		var at := "enemies.json: " + name
		var e: Variant = d.get(name)
		errs.append_array(_check_spec(e, ENEMY_SPEC, at))
		if not (e is Dictionary):
			continue
		if int(e.get("code", 0)) != code:
			errs.append("%s: code must be %d" % [at, code])
		if code <= SiegeIds.ENEMY_CHARIOT:
			errs.append_array(_infantry_ok(e, at))
		if code == SiegeIds.ENEMY_CHARIOT:
			var sv: Variant = e.get("speed_var")
			if not _is_num(sv) or float(sv) < 0.0 or float(sv) >= 1.0:
				errs.append("%s: speed_var must be 0..1" % at)
			errs.append_array(_pair_ok(e.get("redraw_s"), at + ": redraw_s"))
			if not _is_num(e.get("accel_mps2")) or float(e["accel_mps2"]) <= 0.0:
				errs.append("%s: accel_mps2 must be > 0" % at)
		if code == SiegeIds.ENEMY_RAM:
			if not _is_num(e.get("gate_hp_per_s")) or float(e["gate_hp_per_s"]) <= 0.0:
				errs.append("%s: gate_hp_per_s must be > 0" % at)
			if not _is_num(e.get("crew")) or SiegeIds.enemy_code(str(e.get("crew_type", ""))) == 0:
				errs.append("%s: needs crew and crew_type" % at)
	errs.append_array(
		_check_spec(d, {"lateral_m": "nonneg", "cap": "pos", "retreat_s": "nonneg"}, "enemies.json")
	)
	return errs


## Problems of a spear, shield or chariot entry: gate_hp > 0, ranks [files, ranks] >= 1,
## spacing_m > 0.
static func _infantry_ok(e: Dictionary, at: String) -> Array[String]:
	var errs: Array[String] = []
	if not _is_num(e.get("gate_hp")) or float(e["gate_hp"]) <= 0.0:
		errs.append("%s: gate_hp must be > 0" % at)
	var rk: Variant = e.get("ranks")
	var ok: bool = rk is Array and (rk as Array).size() == 2
	ok = ok and _is_num(rk[0]) and _is_num(rk[1]) and int(rk[0]) >= 1 and int(rk[1]) >= 1
	if not ok:
		errs.append("%s: ranks must be [files, ranks] >= 1" % at)
	if not _is_num(e.get("spacing_m")) or float(e["spacing_m"]) <= 0.0:
		errs.append("%s: spacing_m must be > 0" % at)
	return errs


## waves.json: WAVES_SPEC; group_every_s, group_var and engines.crew_back_m are [lo, hi] with
## lo <= hi; mix has standard and raiders_horsemen, each 3 rows (thirds of the shift) of 3
## fractions [spear, shield, chariot] summing to 1; rush.types are enemy names; the optional
## budget_factor maps content ids to factors > 0 on B.
static func validate_waves(d: Variant) -> Array[String]:
	var errs := _check_spec(d, WAVES_SPEC, "waves.json")
	if not errs.is_empty():
		return errs
	for k: String in ["group_every_s", "group_var", "engines.crew_back_m"]:
		errs.append_array(_pair_ok(_at(d, k), "waves.json: " + k))
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
	var bf: Variant = d.get("budget_factor", {})
	if not (bf is Dictionary):
		errs.append("waves.json: budget_factor must be an object")
	else:
		for k: Variant in bf:
			if not _is_num(bf[k]) or float(bf[k]) <= 0.0:
				errs.append("waves.json: budget_factor.%s must be > 0" % k)
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
	for p: String in spec:
		var v: Variant = _at(d, p)
		var ok := true
		match str(spec[p]):
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
			errs.append("%s: %s must be %s" % [file, p, spec[p]])
	return errs


## Problems of a [lo, hi] pair of numbers with lo <= hi.
static func _pair_ok(r: Variant, at: String) -> Array[String]:
	var errs: Array[String] = []
	var ok: bool = r is Array and (r as Array).size() == 2
	ok = ok and _is_num(r[0]) and _is_num(r[1]) and float(r[0]) <= float(r[1])
	if not ok:
		errs.append("%s must be [lo, hi]" % at)
	return errs


static func _at(d: Variant, p_path: String) -> Variant:
	var v: Variant = d
	for k in p_path.split("."):
		if not (v is Dictionary) or not (v as Dictionary).has(k):
			return null
		v = v[k]
	return v


static func _is_num(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


static func _pct_ok(v: Variant) -> bool:
	return _is_num(v) and float(v) >= MIN_PCT and float(v) <= MAX_PCT
