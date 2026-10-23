class_name TankContentSchema
extends RefCounted
## The content schemas and their validators (G0 contract; brief 2.9 "validated at load"). One
## validate_<file>(d) per file under content/tank/, each returning every problem it finds ([] when
## the file is usable). Extra keys are allowed so builders can add tuning knobs; a builder whose
## new key must be required asks the lead to extend the spec here. TankContent (content/) loads
## the files and runs these.
##
## Files:
##   tanks.json     tanks {bulwark, rampart, citadel}: {code, crew, hull_px, engines, turrets,
##                  enemy_scale}; hull, drive, ram, berm, in_band, dynamo, steam, gearbox, gun,
##                  damage, secondary, caps (TANKS_SPEC)
##   stations.json  engines, start_engines, rotation, plans, drill_plans, terrain, bank, boiler,
##                  hoist, cadence_band, power_band_pct, haptics (STATIONS_SPEC; plan entries:
##                  {mode: ERG, target_pct, ramp_to_pct?, range_pct?} or {mode: SIM, grade_source})
##   enemies.json   types {light, medium, destroyer, dugin, heavy}: {code, hp, size_px, gun {damage,
##                  every_s, hit}, light_mult}; boss; miss_px; clamp (ENEMIES_SPEC)
##   missions/<id>.json  {id, label, rotation, segments: [{id, type, stage, kind, duration_s,
##                  min_s?, max_s?, label, name, backdrop, terrain?, length_m?, encounters?,
##                  obstacles?, enemies?, props?, drills?, teach?, boss?}], cooldown}
##   scoring.json   scale, weights, objectives, survival_per_breakdown, grades, xp (SCORING_SPEC)
##   cosmetics.json unlocks: [{id, kind, rule: finish | grade | behemoth_no_breakdown, min_grade?}]

const TANKS_SPEC := {
	"tanks": "obj",
	"hull.hp": "pos",
	"hull.checkpoint_hp": "nonneg",
	"hull.repair_j": "pos",
	"hull.repair_hp": "pos",
	"drive.cda_m2": "pos",
	"drive.mass_offset_kg": "nonneg",
	"drive.world_scroll": "pos",
	"drive.px_per_visual_m": "pos",
	"drive.evasive_hit_mult": "nonneg",
	"ram.window_s": "pos",
	"ram.cooldown_s": "nonneg",
	"ram.reach_px": "pos",
	"ram.sprint_ftp": "pos",
	"ram.sprint_window_s": "pos",
	"ram.fail_damage": "nonneg",
	"ram.fail_stall_s": "nonneg",
	"ram.boss_lunge_px": "nonneg",
	"ram.boss_dodge_hold_s": "pos",
	"berm.j_per_hp": "pos",
	"berm.max_hp": "nonneg",
	"in_band.sim_ftp_pct": "pair",
	"in_band.erg_power_frac": "pos",
	"in_band.erg_cadence_rpm": "pos",
	"in_band.steam_build_ftp_pct": "pos",
	"in_band.steam_cycle_cadence_rpm": "pos",
	"in_band.recovery_cadence_rpm": "pos",
	"in_band.reserve_p_eff_w": "nonneg",
	"dynamo.bank_max": "pos",
	"dynamo.j_per_unit": "pos",
	"dynamo.stabilizer_per_s": "nonneg",
	"dynamo.per_degree": "nonneg",
	"dynamo.per_traverse": "nonneg",
	"dynamo.per_hoist": "nonneg",
	"dynamo.per_secondary": "nonneg",
	"dynamo.secondary_min_bank": "nonneg",
	"dynamo.elev_deg_s": "pair",
	"dynamo.traverse_s": "pair",
	"dynamo.hoist_s": "pair",
	"steam.full_j": "pos",
	"steam.window_s": "nonneg",
	"steam.over_j": "pos",
	"steam.over_max_pct": "pos",
	"steam.breech_cycle_s": "nonneg",
	"steam.light_latch_pct": "pos",
	"gearbox.move_s": "nonneg",
	"gearbox.turret_full_w": "pos",
	"gearbox.hoist_j": "pos",
	"gearbox.auto_dwell_s": "nonneg",
	"gearbox.manual_suspend_s": "nonneg",
	"gun.elev_min_deg": "num",
	"gun.elev_max_deg": "num",
	"gun.shell_speed_px_s": "pos",
	"gun.gravity_px_s2": "pos",
	"gun.aim_tol_deg": "pos",
	"damage.light": "nonneg",
	"damage.heavy": "nonneg",
	"damage.over": "nonneg",
	"damage.splash_px": "nonneg",
	"damage.splash_frac": "nonneg",
	"secondary.damage": "nonneg",
	"secondary.every_s": "pos",
	"secondary.range_px": "pos",
	"caps.enemies": "pos",
	"caps.shells": "pos",
}
const TANK_SPEC := {
	"code": "pos",
	"crew": "pos",
	"hull_px": "pair",
	"engines": "arr",
	"turrets": "arr",
	"enemy_scale": "pos"
}
const STATIONS_SPEC := {
	"engines": "arr",
	"start_engines": "obj",
	"rotation": "obj",
	"plans": "obj",
	"drill_plans": "obj",
	"terrain.send_every_s": "pos",
	"terrain.warmup_grade_pct": "pair",
	"bank.base_pct": "pos",
	"bank.span_pct": "nonneg",
	"bank.every_s": "pos",
	"bank.substeps": "pos",
	"bank.substep_s": "pos",
	"bank.max_step_pts": "pos",
	"boiler.grade_pct": "nonneg",
	"boiler.warmup_grade_pct": "nonneg",
	"boiler.max_rise_pct": "pos",
	"boiler.min_interval_s": "pos",
	"hoist.grade_pct": "nonneg",
	"hoist.warmup_grade_pct": "nonneg",
	"hoist.rise_pct_s": "pos",
	"cadence_band.default": "pair",
	"cadence_band.loader": "pair",
	"power_band_pct": "pair",
	"haptics.hit.min_damage": "nonneg",
	"haptics.hit.haptic": "pos",
	"haptics.hit.duration_s": "pos",
	"haptics.boss_hit.haptic": "pos",
	"haptics.boss_hit.duration_s": "pos",
	"haptics.ram.haptic": "pos",
	"haptics.ram.duration_s": "pos",
	"haptics.cooldown_s": "nonneg",
	"haptics.none_before_s": "nonneg",
}
const ENEMY_SPEC := {
	"code": "pos",
	"hp": "pos",
	"size_px": "pair",
	"light_mult": "nonneg",
	"gun.damage": "nonneg",
	"gun.every_s": "pos",
	"gun.hit": "frac",
}
const ENEMIES_SPEC := {
	"types": "obj",
	"boss.bogies": "pos",
	"boss.bogie_hp": "pos",
	"boss.turret_hp": "pos",
	"boss.hull_px": "pair",
	"boss.creep_px_s": "nonneg",
	"boss.stop_px": "nonneg",
	"boss.pushback_px": "nonneg",
	"boss.main.damage": "nonneg",
	"boss.main.every_s": "pair",
	"boss.main.every_s_phase2": "pair",
	"boss.main.telegraph_s": "pos",
	"boss.secondary.damage": "nonneg",
	"boss.secondary.every_s": "pos",
	"boss.secondary.hit": "frac",
	"miss_px": "pair",
	"clamp.ahead_max_right_px": "pos",
	"clamp.behind_min_show_px": "nonneg",
}
const SCORING_SPEC := {
	"scale": "pos",
	"weights.band": "nonneg",
	"weights.accuracy": "nonneg",
	"weights.objectives": "nonneg",
	"weights.survival": "nonneg",
	"objectives.stages": "pos",
	"objectives.stage_frac": "nonneg",
	"objectives.boss_frac": "nonneg",
	"survival_per_breakdown": "nonneg",
	"grades.S": "num",
	"grades.A": "num",
	"grades.B": "num",
	"grades.C": "num",
	"xp.kj_per_xp": "pos",
	"xp.grade_bonus.S": "nonneg",
	"xp.grade_bonus.A": "nonneg",
	"xp.grade_bonus.B": "nonneg",
	"xp.grade_bonus.C": "nonneg",
	"xp.grade_bonus.D": "nonneg",
}
const SEGMENT_KINDS := {
	TankIds.SEG_DEPOT: Wl.WARMUP,
	TankIds.SEG_SKIRMISH: Wl.WARMUP,
	TankIds.SEG_ADVANCE: Wl.WORK,
	TankIds.SEG_GUN_LINE: Wl.WORK,
	TankIds.SEG_BOSS: Wl.WORK,
	TankIds.SEG_CHECKPOINT: Wl.RECOVERY,
}
const OPEN_SEGMENTS: Array[String] = [TankIds.SEG_ADVANCE, TankIds.SEG_GUN_LINE, TankIds.SEG_BOSS]
const UNLOCK_RULES: Array[String] = ["finish", "grade", "behemoth_no_breakdown"]
const GRADES: Array[String] = ["S", "A", "B", "C", "D"]


static func validate_tanks(d: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (d is Dictionary):
		return ["tanks.json: expected an object"]
	check_spec(d, TANKS_SPEC, "tanks.json", errors)
	var tanks: Variant = d.get("tanks")
	if tanks is Dictionary:
		for t: String in TankIds.TANKS:
			if not (tanks as Dictionary).has(t):
				errors.append("tanks.json tanks: missing %s" % t)
				continue
			check_spec(tanks[t], TANK_SPEC, "tanks.json tanks.%s" % t, errors)
			for e: Variant in (tanks[t] as Dictionary).get("engines", []):
				if not TankIds.ENGINES.has(str(e)):
					errors.append("tanks.json tanks.%s.engines: unknown engine %s" % [t, str(e)])
	return errors


static func validate_stations(d: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (d is Dictionary):
		return ["stations.json: expected an object"]
	check_spec(d, STATIONS_SPEC, "stations.json", errors)
	if errors.size() > 0:
		return errors
	for t: String in TankIds.TANKS:
		var starts: Variant = d["start_engines"].get(t)
		if not (starts is Array) or (starts as Array).size() != TankIds.TANKS.find(t) + 1:
			errors.append("stations.json start_engines.%s: one engine per slot" % t)
	for t: String in [TankIds.TANK_RAMPART, TankIds.TANK_CITADEL]:
		var rows: Variant = d["rotation"].get(t)
		if not (rows is Array) or (rows as Array).size() != TankIds.TANKS.find(t) + 1:
			errors.append("stations.json rotation.%s: one row per slot" % t)
			continue
		for row: Variant in rows:
			if not (row is Array) or (row as Array).size() != 4:
				errors.append("stations.json rotation.%s: rows are [stage 1, 2, 3, boss]" % t)
	for table: String in ["plans", "drill_plans"]:
		for engine: String in TankIds.ENGINES:
			var per: Variant = d[table].get(engine)
			if not (per is Dictionary):
				errors.append("stations.json %s.%s: missing" % [table, engine])
				continue
			for seg: String in per:
				_check_plan_entry(per[seg], "stations.json %s.%s.%s" % [table, engine, seg], errors)
		_check_plan_entry(d[table].get("checkpoint"), "stations.json %s.checkpoint" % table, errors)
	return errors


static func validate_enemies(d: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (d is Dictionary):
		return ["enemies.json: expected an object"]
	check_spec(d, ENEMIES_SPEC, "enemies.json", errors)
	var types: Variant = d.get("types")
	if types is Dictionary:
		for t: String in TankIds.ENEMY_TYPES:
			if not (types as Dictionary).has(t):
				errors.append("enemies.json types: missing %s" % t)
				continue
			check_spec(types[t], ENEMY_SPEC, "enemies.json types.%s" % t, errors)
			if int(types[t].get("code", 0)) != TankIds.enemy_code(t):
				errors.append("enemies.json types.%s.code: must be %d" % [t, TankIds.enemy_code(t)])
	return errors


static func validate_mission(d: Variant, mission_id: String = "") -> Array[String]:
	var errors: Array[String] = []
	var at := "missions/%s.json" % mission_id
	if not (d is Dictionary):
		return ["%s: expected an object" % at]
	if mission_id != "" and str(d.get("id", "")) != mission_id:
		errors.append("%s id: must be %s" % [at, mission_id])
	if not (d.get("label") is String):
		errors.append("%s label: expected a strings key" % at)
	var segs: Variant = d.get("segments")
	if not (segs is Array) or (segs as Array).is_empty():
		errors.append("%s segments: expected a non-empty array" % at)
		return errors
	for i in (segs as Array).size():
		_check_segment(segs[i], "%s segments[%d]" % [at, i], errors)
	return errors


static func validate_scoring(d: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (d is Dictionary):
		return ["scoring.json: expected an object"]
	check_spec(d, SCORING_SPEC, "scoring.json", errors)
	return errors


static func validate_cosmetics(d: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (d is Dictionary) or not (d.get("unlocks") is Array):
		return ["cosmetics.json: expected {unlocks: [...]}"]
	var seen := {}
	for u: Variant in d["unlocks"]:
		if not (u is Dictionary) or not (u.get("id") is String) or str(u["id"]) == "":
			errors.append("cosmetics.json unlocks: each needs an id")
			continue
		var id := str(u["id"])
		if seen.has(id):
			errors.append("cosmetics.json unlocks: %s twice" % id)
		seen[id] = true
		if not UNLOCK_RULES.has(str(u.get("rule", ""))):
			errors.append("cosmetics.json %s.rule: one of %s" % [id, ", ".join(UNLOCK_RULES)])
		if str(u.get("rule", "")) == "grade" and not GRADES.has(str(u.get("min_grade", ""))):
			errors.append("cosmetics.json %s.min_grade: one of S, A, B, C, D" % id)
	return errors


## Checks every dotted path of `spec` in `d`; kinds: num, pos (> 0), nonneg (>= 0), frac (0..1),
## pair ([a, b] numbers), arr, obj, str.
static func check_spec(d: Variant, spec: Dictionary, where: String, errors: Array[String]) -> void:
	if not (d is Dictionary):
		errors.append("%s: expected an object" % where)
		return
	for path: String in spec:
		var v: Variant = dig(d, path)
		var kind := str(spec[path])
		var ok := false
		match kind:
			"num":
				ok = _num(v)
			"pos":
				ok = _num(v) and float(v) > 0.0
			"nonneg":
				ok = _num(v) and float(v) >= 0.0
			"frac":
				ok = _num(v) and float(v) >= 0.0 and float(v) <= 1.0
			"pair":
				ok = v is Array and (v as Array).size() == 2 and _num(v[0]) and _num(v[1])
			"arr":
				ok = v is Array
			"obj":
				ok = v is Dictionary
			"str":
				ok = v is String
		if not ok:
			errors.append("%s %s: expected %s, got %s" % [where, path, kind, JSON.stringify(v)])


## The value at a dotted path, or null.
static func dig(d: Variant, path: String) -> Variant:
	var cur: Variant = d
	for part in path.split("."):
		if not (cur is Dictionary) or not (cur as Dictionary).has(part):
			return null
		cur = cur[part]
	return cur


static func _check_plan_entry(e: Variant, where: String, errors: Array[String]) -> void:
	if not (e is Dictionary):
		errors.append("%s: expected an object" % where)
		return
	match str(e.get("mode", "")):
		Wl.ERG:
			if not _num(e.get("target_pct")):
				errors.append("%s: ERG needs target_pct" % where)
				return
			var lo := float(e["target_pct"])
			var hi := lo
			if e.has("ramp_to_pct"):
				hi = maxf(hi, float(e["ramp_to_pct"]))
			if e.get("range_pct") is Array:
				lo = minf(lo, float(e["range_pct"][0]))
				hi = maxf(hi, float(e["range_pct"][1]))
			if lo < 50.0 or hi > 100.0:
				errors.append("%s: every ERG value must lie in 50..100%% FTP (brief 2.3)" % where)
		Wl.SIM:
			if not [Wl.GRADE_FLAT, Wl.GRADE_GAME].has(str(e.get("grade_source", ""))):
				errors.append("%s: SIM needs grade_source flat or game" % where)
		_:
			errors.append("%s: mode must be ERG or SIM" % where)


static func _check_segment(s: Variant, where: String, errors: Array[String]) -> void:
	if not (s is Dictionary):
		errors.append("%s: expected an object" % where)
		return
	var type := str(s.get("type", ""))
	if not TankIds.SEGMENTS.has(type):
		errors.append("%s type: one of %s" % [where, ", ".join(TankIds.SEGMENTS)])
		return
	if str(s.get("kind", "")) != str(SEGMENT_KINDS[type]):
		errors.append("%s kind: %s must be %s" % [where, type, SEGMENT_KINDS[type]])
	if not _num(s.get("duration_s")) or float(s["duration_s"]) <= 0.0:
		errors.append("%s duration_s: expected > 0" % where)
	if OPEN_SEGMENTS.has(type):
		var lo: Variant = s.get("min_s")
		var hi: Variant = s.get("max_s")
		if not (_num(lo) and _num(hi) and float(lo) > 0.0 and float(lo) <= float(hi)):
			errors.append("%s: open-ended segments need 0 < min_s <= max_s" % where)
	if not (s.get("label") is String) or str(s["label"]) == "":
		errors.append("%s label: expected a strings key" % where)
	if not _num(s.get("stage")):
		errors.append("%s stage: expected a number" % where)
	if [TankIds.SEG_ADVANCE, TankIds.SEG_SKIRMISH].has(type):
		if not _num(s.get("length_m")) or float(s["length_m"]) <= 0.0:
			errors.append("%s length_m: expected > 0" % where)
		for e: Variant in s.get("encounters", []):
			if not (e is Dictionary) or not TankIds.ENEMY_TYPES.has(str(e.get("enemy", ""))):
				errors.append("%s encounters: each needs a known enemy" % where)
	if s.has("terrain"):
		var last := -1.0
		for pt: Variant in s["terrain"]:
			if not (pt is Array) or (pt as Array).size() != 2 or float(pt[0]) < last:
				errors.append("%s terrain: [[distance_m, grade_pct], ...] ascending" % where)
				break
			last = float(pt[0])


static func _num(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))
