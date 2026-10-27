class_name TankContentSchema
extends RefCounted
## The content schemas and their validators (G0 contract; brief 2.9 "validated at load"). One
## validate_<file>(d) per file under content/tank/, each returning every problem it finds ([] when
## the file is usable). Extra keys are allowed so builders can add tuning knobs; a builder whose
## new key must be required asks the lead to extend the spec here. TankContent (content/) loads
## the files and runs these.
##
## Files:
##   tanks.json     tanks {bulwark, rampart, citadel, bastion}: {code (TankIds.TANK_CODES), crew
##                  (its index in TankIds.TANKS + 1), hull_px, engines (rooms rear to front),
##                  turrets, enemy_scale}; hull, drive, evade, berm, in_band, power_ratio, dynamo,
##                  steam, gearbox, gun, damage, bow, arc, caps (TANKS_SPEC)
##   stations.json  engines, start_engines, rotation, plans, drill_plans, terrain, bank, arc, boiler,
##                  hoist, cadence_band, haptics (STATIONS_SPEC; plan entries:
##                  {mode: ERG, target_pct, ramp_to_pct?, range_pct?} or {mode: SIM, grade_source});
##                  every engine has an entry for every segment type of TABLE_SEGMENTS; rotation rows
##                  (every tank of crew 2 and up) use their tank's start engines, start with the
##                  slot's own and man every room in every column
##   enemies.json   types {light, medium, destroyer, dugin, heavy}: {code, hp, size_px, gun {damage,
##                  every_s, hit}, light_mult, lane, flank? {telegraph_s, damage, hit}}; boss;
##                  miss_px; clamp; lanes (ENEMIES_SPEC)
##   missions/<id>.json  {id, label, rotation, segments: [{id, type, stage, kind, duration_s,
##                  min_s?, max_s?, label, name, backdrop, terrain?, length_m?, encounters?,
##                  obstacles?, enemies?, props?, drills?, teach?, boss?}], cooldown}
##   scoring.json   scale, weights, objectives, survival_per_breakdown, grades, xp (SCORING_SPEC)
##   cosmetics.json unlocks: [{id, kind, rule: finish | grade | behemoth_no_breakdown, min_grade?}]
##   validate_cross(files): what needs two files (each tank's start engines are its rooms in slot
##                  order, a permutation of tanks.json engines; the mission's plan table and its
##                  segment types, 90% ERG phases <= 180 s, warm-up terrain inside the warm-up grades)
##
## Safety envelope: besides types, the validators hold every number that carries a brief 2.3 check
## (BRIEF 4.6.1, 4.6.2, 4.6.6, 4.6.8) to the brief's bounds below, so G2's +/-50% tuning can move a
## number only inside them. A bound here is never loosened to pass a check (CLAUDE.md, BRIEF 4.6).

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
	"evade.sprint_window_s": "pos",
	"evade.hold_s": "pos",
	"evade.boss_hold_s": "pos",
	"berm.j_per_hp": "pos",
	"berm.max_hp": "nonneg",
	"in_band.sim_ftp_pct": "pair",
	"in_band.erg_power_frac": "pos",
	"in_band.erg_cadence_rpm": "pos",
	"in_band.steam_cycle_cadence_rpm": "pos",
	"in_band.recovery_cadence_rpm": "pos",
	"in_band.reserve_p_eff_w": "nonneg",
	"power_ratio.steam_loaded_pct": "pos",
	"power_ratio.warmup_sim_pct": "pos",
	"dynamo.bank_max": "pos",
	"dynamo.j_per_unit": "pos",
	"dynamo.stabilizer_per_s": "nonneg",
	"dynamo.per_degree": "nonneg",
	"dynamo.per_traverse": "nonneg",
	"dynamo.per_hoist": "nonneg",
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
	"bow.damage": "nonneg",
	"bow.every_s": "pos",
	"bow.min_px": "nonneg",
	"bow.max_px": "pos",
	"bow.per_burst_units": "nonneg",
	"bow.min_bank": "nonneg",
	"bow.under_band_rate": "frac",
	"bow.bulwark_rate": "frac",
	"bow.clear_s": "pos",
	"arc.lit_dispersion_mult": "frac",
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
	"bank.clamp_to_range": "bool",
	"arc.base_pct": "pos",
	"arc.span_pct": "nonneg",
	"arc.every_s": "pos",
	"arc.substeps": "pos",
	"arc.substep_s": "pos",
	"arc.max_step_pts": "pos",
	"boiler.grade_pct": "nonneg",
	"boiler.warmup_grade_pct": "nonneg",
	"boiler.max_rise_pct": "pos",
	"boiler.min_interval_s": "pos",
	"hoist.grade_pct": "nonneg",
	"hoist.warmup_grade_pct": "nonneg",
	"hoist.rise_pct_s": "pos",
	"hoist.step_s": "pos",
	"cadence_band.default": "pair",
	"cadence_band.loader": "pair",
	"haptics.hit.min_damage": "nonneg",
	"haptics.hit.haptic": "pos",
	"haptics.hit.duration_s": "pos",
	"haptics.boss_hit.haptic": "pos",
	"haptics.boss_hit.duration_s": "pos",
	"haptics.cooldown_s": "nonneg",
}
const ENEMY_SPEC := {
	"code": "pos",
	"hp": "pos",
	"size_px": "pair",
	"light_mult": "nonneg",
	"lane": "nonneg",
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
	"lanes.count": "pos",
	"lanes.gap_px": "nonneg",
}
## An enemy type's optional flank shot (v2, the light tank's, brief 2.4): its first shot after it
## reaches its hold distance, telegraphed.
const FLANK_SPEC := {"telegraph_s": "pos", "damage": "nonneg", "hit": "frac"}
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
## The segment types every engine needs an entry for, per plan table.
const TABLE_SEGMENTS := {
	"plans": [TankIds.SEG_DEPOT, TankIds.SEG_ADVANCE, TankIds.SEG_GUN_LINE, TankIds.SEG_BOSS],
	"drill_plans": [TankIds.SEG_DEPOT, TankIds.SEG_SKIRMISH],
}

# --- The brief's safety envelope (brief 2.3 checks, 2.7; BRIEF 4.6) ---------------------------------
## 4.6.1: every ERG target, ramp and range bound in % FTP.
const ERG_MIN_PCT := 50.0
const ERG_MAX_PCT := 100.0
## 4.6.8: ERG in WARMUP-kind segments at most 65%; SIM grades 0..+3% before difficulty.
const WARMUP_ERG_MAX_PCT := 65.0
const WARMUP_SIM_MAX_PCT := 3.0
## Checkpoints: ERG 50% for everyone.
const CHECKPOINT_PCT := 50.0
## 4.6.1: an ERG phase at or above 90% lasts at most 180 s (gun lines).
const HARD_ERG_PCT := 90.0
const HARD_ERG_MAX_S := 180.0
## The SIM in-band power band never reaches past 105% FTP (no duration counter runs).
const SIM_BAND_MAX_PCT := 105.0
## Terrain (diesel, Bulwark) in WORK segments, and in WARMUP-kind ones.
const TERRAIN_MIN_PCT := -3.0
const TERRAIN_MAX_PCT := 6.0
const WARMUP_TERRAIN_MIN_PCT := 0.0
const WARMUP_TERRAIN_MAX_PCT := 2.0
## Pattern 4 at most 2 Hz.
const TERRAIN_MIN_EVERY_S := 0.5
## Patterns 2 and 3: mode grades before difficulty, and how fast they may rise.
const BOILER_MAX_PCT := 8.0
const BOILER_WARMUP_MAX_PCT := 3.0
const BOILER_MAX_RISE_PCT := 0.5
const BOILER_MIN_INTERVAL_S := 1.0
const HOIST_MAX_PCT := 4.0
const HOIST_WARMUP_MAX_PCT := 1.0
const HOIST_MAX_RISE_PCT_S := 1.0
## 4.6.6: terrain maximum + hoist (the Bulwark's (6 + 4)%) inside the default +10% range top.
const STACK_MAX_PCT := 10.0
## Pattern 1 (4.6.2): <= 10 points per update, sub-steps >= 1 s apart, targets inside 50..100%.
const BANK_MAX_STEP_PTS := 10.0
const BANK_MIN_SUBSTEP_S := 1.0
## 4.6.2: one bank update's largest sub-step, 10 points over the 3 s the rule spreads it across (3.3%/s).
const BANK_MAX_SUBSTEP_PTS := 10.0 / 3.0
## Pattern 3: the largest single hoist step (rise_pct_s x step_s), the +1%/s rule.
const HOIST_MAX_STEP_PCT := 1.0
## 2.7: the largest haptic +3% for at most 8 s; the game's own cooldown at least 15 s.
const HAPTIC_MAX := 3.0
const HAPTIC_MAX_S := 8.0
const HAPTIC_MIN_COOLDOWN_S := 15.0
## Every stations.json number that carries a check: [path, ">=" or "<=", bound, why].
const STATION_BOUNDS: Array = [
	["terrain.send_every_s", ">=", TERRAIN_MIN_EVERY_S, "pattern 4 at most 2 Hz"],
	["terrain.warmup_grade_pct.0", ">=", WARMUP_TERRAIN_MIN_PCT, "warm-up terrain 0..+2%"],
	["terrain.warmup_grade_pct.1", "<=", WARMUP_TERRAIN_MAX_PCT, "warm-up terrain 0..+2%"],
	["bank.base_pct", ">=", ERG_MIN_PCT, "bank targets inside 50..100% (4.6.1)"],
	["bank.max_step_pts", "<=", BANK_MAX_STEP_PTS, "<= 10 points per update (4.6.2)"],
	["bank.substep_s", ">=", BANK_MIN_SUBSTEP_S, "sub-steps >= 1 s apart (4.6.2)"],
	["arc.base_pct", ">=", ERG_MIN_PCT, "arc targets inside 50..100% (4.6.1)"],
	["arc.max_step_pts", "<=", BANK_MAX_STEP_PTS, "<= 10 points per update (4.6.2)"],
	["arc.substep_s", ">=", BANK_MIN_SUBSTEP_S, "sub-steps >= 1 s apart (4.6.2)"],
	["boiler.grade_pct", "<=", BOILER_MAX_PCT, "boiler 8% x difficulty <= +8% (4.6.6)"],
	["boiler.warmup_grade_pct", "<=", BOILER_WARMUP_MAX_PCT, "warm-up SIM <= +3% (4.6.8)"],
	["boiler.max_rise_pct", "<=", BOILER_MAX_RISE_PCT, "boiler rises <= 0.5% a step"],
	["boiler.min_interval_s", ">=", BOILER_MIN_INTERVAL_S, "boiler <= once a second"],
	["hoist.grade_pct", "<=", HOIST_MAX_PCT, "hoist 4% (4.6.6)"],
	["hoist.warmup_grade_pct", "<=", HOIST_WARMUP_MAX_PCT, "warm-up hoist 1% (4.6.8)"],
	["hoist.rise_pct_s", "<=", HOIST_MAX_RISE_PCT_S, "hoist rises at +1%/s"],
	["haptics.hit.haptic", "<=", HAPTIC_MAX, "haptics <= +3% (2.7, 4.6.6)"],
	["haptics.hit.duration_s", "<=", HAPTIC_MAX_S, "haptics <= 8 s (2.7)"],
	["haptics.boss_hit.haptic", "<=", HAPTIC_MAX, "haptics <= +3% (2.7, 4.6.6)"],
	["haptics.boss_hit.duration_s", "<=", HAPTIC_MAX_S, "haptics <= 8 s (2.7)"],
	["haptics.cooldown_s", ">=", HAPTIC_MIN_COOLDOWN_S, "haptic cooldown >= 15 s (2.7)"],
]


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
			var def: Variant = tanks[t]
			if def is Dictionary and _num(def.get("code")):
				if int(def["code"]) != int(TankIds.TANK_CODES[t]):
					errors.append(
						"tanks.json tanks.%s.code: must be %d" % [t, TankIds.TANK_CODES[t]]
					)
			if def is Dictionary and _num(def.get("crew")):
				if int(def["crew"]) != TankIds.TANKS.find(t) + 1:
					errors.append(
						"tanks.json tanks.%s.crew: must be %d" % [t, TankIds.TANKS.find(t) + 1]
					)
			for e: Variant in (tanks[t] as Dictionary).get("engines", []):
				if not TankIds.ENGINES.has(str(e)):
					errors.append("tanks.json tanks.%s.engines: unknown engine %s" % [t, str(e)])
	var band: Variant = dig(d, "in_band.sim_ftp_pct")
	if band is Array and (band as Array).size() == 2 and _num(band[0]) and _num(band[1]):
		if not (
			float(band[0]) >= ERG_MIN_PCT
			and float(band[0]) <= float(band[1])
			and float(band[1]) <= SIM_BAND_MAX_PCT
		):
			errors.append(
				"tanks.json in_band.sim_ftp_pct: must lie in 50..105%% FTP (brief 2.3, 4.6.1)"
			)
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
	if errors.size() > 0:
		return errors
	for t: String in TankIds.TANKS:
		if TankIds.TANKS.find(t) > 0:
			_check_rotation(d["rotation"].get(t), d["start_engines"][t], t, errors)
	for table: String in TABLE_SEGMENTS:
		_check_table(d[table], table, errors)
	_check_station_bounds(d, errors)
	return errors


## One plan table: every engine has every segment type, each entry is well formed, WARMUP-kind
## entries stay at or below 65%, and the checkpoint is exactly ERG 50%.
static func _check_table(tbl: Dictionary, table: String, errors: Array[String]) -> void:
	for engine: String in TankIds.ENGINES:
		var per: Variant = tbl.get(engine)
		if not (per is Dictionary):
			errors.append("stations.json %s.%s: missing" % [table, engine])
			continue
		for seg: String in TABLE_SEGMENTS[table]:
			if not (per as Dictionary).has(seg):
				errors.append("stations.json %s.%s.%s: missing" % [table, engine, seg])
		for seg: String in per:
			var where := "stations.json %s.%s.%s" % [table, engine, seg]
			_check_plan_entry(per[seg], where, errors)
			if SEGMENT_KINDS.get(seg, "") == Wl.WARMUP:
				_check_warmup_entry(per[seg], where, errors)
	var cp: Variant = tbl.get("checkpoint")
	_check_plan_entry(cp, "stations.json %s.checkpoint" % table, errors)
	var exact: bool = (
		cp is Dictionary
		and str(cp.get("mode", "")) == Wl.ERG
		and _num(cp.get("target_pct"))
		and float(cp["target_pct"]) == CHECKPOINT_PCT
		and not cp.has("ramp_to_pct")
		and not cp.has("range_pct")
	)
	if not exact:
		errors.append("stations.json %s.checkpoint: must be exactly ERG 50%% (brief 2.3)" % table)


## The rotation rows of tank `t`: one per slot, [stage 1, 2, 3, boss], only the tank's engines,
## each row starting on its slot's start engine, every column manning every room once.
static func _check_rotation(rows: Variant, starts: Array, t: String, errors: Array[String]) -> void:
	var where := "stations.json rotation.%s" % t
	if not (rows is Array) or (rows as Array).size() != starts.size():
		errors.append("%s: one row per slot" % where)
		return
	for slot in (rows as Array).size():
		var row: Variant = rows[slot]
		if not (row is Array) or (row as Array).size() != 4:
			errors.append("%s: rows are [stage 1, 2, 3, boss]" % where)
			return
		for e: Variant in row:
			if not starts.has(e):
				errors.append("%s[%d]: %s is not one of the tank's engines" % [where, slot, str(e)])
		if str(row[0]) != str(starts[slot]):
			errors.append("%s[%d]: stage 1 must be the slot's start engine" % [where, slot])
	for col in 4:
		var seen := {}
		for row: Array in rows:
			seen[str(row[col])] = true
		if seen.size() != starts.size():
			errors.append("%s column %d: every room needs exactly one rider" % [where, col + 1])


## A WARMUP-kind entry (the depot, the drill's skirmish): ERG at most 65% (BRIEF 4.6.8).
static func _check_warmup_entry(e: Variant, where: String, errors: Array[String]) -> void:
	if not (e is Dictionary) or str(e.get("mode", "")) != Wl.ERG:
		return
	if _peak_pct(e) > WARMUP_ERG_MAX_PCT:
		errors.append("%s: warm-up ERG must stay at or below 65%% FTP (BRIEF 4.6.8)" % where)


## The highest ERG % an entry can ask for (target, ramp end, range top).
static func _peak_pct(e: Dictionary) -> float:
	var hi := float(e.get("target_pct", 0.0)) if _num(e.get("target_pct")) else 0.0
	if _num(e.get("ramp_to_pct")):
		hi = maxf(hi, float(e["ramp_to_pct"]))
	var r: Variant = e.get("range_pct")
	if r is Array and (r as Array).size() == 2 and _num(r[1]):
		hi = maxf(hi, float(r[1]))
	return hi


## The highest planned ERG % (target and ramp end; the range is the bank's span, which a 300 s
## Advance or the 360 s boss may reach under the 105% cap, brief 2.3 4.6.1).
static func _planned_peak_pct(e: Dictionary) -> float:
	var hi := float(e.get("target_pct", 0.0)) if _num(e.get("target_pct")) else 0.0
	if _num(e.get("ramp_to_pct")):
		hi = maxf(hi, float(e["ramp_to_pct"]))
	return hi


## Every stations.json number that carries a brief 2.3 / 2.7 check, against its bound.
static func _check_station_bounds(d: Dictionary, errors: Array[String]) -> void:
	for c: Array in STATION_BOUNDS:
		var v: Variant = dig_index(d, str(c[0]))
		if not _num(v):
			errors.append("stations.json %s: expected a number" % c[0])
			continue
		var ok := float(v) >= float(c[2]) if c[1] == ">=" else float(v) <= float(c[2])
		if not ok:
			errors.append("stations.json %s: must be %s %s (%s)" % [c[0], c[1], c[2], c[3]])
	for k: String in ["bank", "arc"]:
		var sub_pts := float(d[k]["max_step_pts"]) / maxf(float(d[k]["substeps"]), 1.0)
		if sub_pts > BANK_MAX_SUBSTEP_PTS + 1e-9:
			var why := "%s.max_step_pts / %s.substeps: must be <= 10/3, got %s (3.3%%/s, 4.6.2)"
			errors.append("stations.json " + why % [k, k, sub_pts])
	var hoist_step := float(d["hoist"]["rise_pct_s"]) * float(d["hoist"]["step_s"])
	if hoist_step > HOIST_MAX_STEP_PCT + 1e-9:
		var why := "hoist.rise_pct_s x hoist.step_s: must be <= 1, got %s (+1%%/s, 4.6.6)"
		errors.append("stations.json " + why % hoist_step)
	for k: String in ["bank", "arc"]:
		if float(d[k]["base_pct"]) + float(d[k]["span_pct"]) > ERG_MAX_PCT:
			errors.append("stations.json %s: base_pct + span_pct must be <= 100 (4.6.1)" % k)
	if not bool(d["bank"]["clamp_to_range"]):
		errors.append("stations.json bank.clamp_to_range: must be true (targets stay in range_pct)")
	var warm_hi := float(d["terrain"]["warmup_grade_pct"][1])
	if warm_hi + float(d["hoist"]["warmup_grade_pct"]) > WARMUP_SIM_MAX_PCT:
		(
			errors
			. append(
				"stations.json terrain.warmup_grade_pct + hoist.warmup_grade_pct: must be <= +3% (4.6.8)"
			)
		)
	if TERRAIN_MAX_PCT + float(d["hoist"]["grade_pct"]) > STACK_MAX_PCT:
		errors.append("stations.json hoist.grade_pct: terrain +6% + hoist must be <= +10% (4.6.6)")
	for k: String in ["default", "loader"]:
		var b: Array = d["cadence_band"][k]
		if float(b[0]) > float(b[1]):
			errors.append("stations.json cadence_band.%s: [lo, hi] with lo <= hi" % k)


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
			if (types[t] as Dictionary).has("flank"):
				check_spec(types[t]["flank"], FLANK_SPEC, "enemies.json types.%s.flank" % t, errors)
			var lanes: Variant = dig(d, "lanes.count")
			var lane: Variant = (types[t] as Dictionary).get("lane")
			if _num(lanes) and _num(lane) and int(lane) >= int(lanes):
				errors.append("enemies.json types.%s.lane: must be below lanes.count" % t)
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
## pair ([a, b] numbers), arr, obj, str, bool.
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
			"bool":
				ok = v is bool
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


## Like dig(), but a numeric path part indexes an Array ("terrain.warmup_grade_pct.1").
static func dig_index(d: Variant, path: String) -> Variant:
	var cur: Variant = d
	for part in path.split("."):
		if cur is Array and part.is_valid_int():
			var i := part.to_int()
			if i < 0 or i >= (cur as Array).size():
				return null
			cur = cur[i]
		elif cur is Dictionary and (cur as Dictionary).has(part):
			cur = cur[part]
		else:
			return null
	return cur


## What needs two files ({tanks, stations, mission}; run once each file validated alone): the
## start engines are each tank's rooms; the mission's plan table exists and holds every segment
## type it uses; an ERG phase planned at or above 90% (target or ramp, not the bank's range top)
## lasts at most 180 s at its longest; WARMUP-kind
## terrain stays inside stations.json terrain.warmup_grade_pct.
static func validate_cross(files: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var tanks: Dictionary = files.get("tanks", {})
	var st: Dictionary = files.get("stations", {})
	var m: Dictionary = files.get("mission", {})
	for t: String in TankIds.TANKS:
		var rooms: Array = (tanks["tanks"][t] as Dictionary).get("engines", []).duplicate()
		var starts: Array = st["start_engines"].get(t, []).duplicate()
		rooms.sort()
		starts.sort()
		if rooms != starts:
			(
				errors
				. append(
					(
						"stations.json start_engines.%s: must be tanks.json tanks.%s.engines (any order)"
						% [t, t]
					)
				)
			)
	var table := str(m.get("plan_table", "plans"))
	var at := "missions/%s.json" % str(m.get("id", ""))
	if not TABLE_SEGMENTS.has(table):
		errors.append("%s plan_table: one of plans, drill_plans" % at)
		return errors
	var warm: Array = st["terrain"]["warmup_grade_pct"]
	var segs: Array = m.get("segments", [])
	for i in segs.size():
		var s: Dictionary = segs[i]
		var type := str(s.get("type", ""))
		var where := "%s segments[%d]" % [at, i]
		if type != TankIds.SEG_CHECKPOINT and not (TABLE_SEGMENTS[table] as Array).has(type):
			errors.append("%s type: %s is not in stations.json %s" % [where, type, table])
			continue
		var longest := float(s.get("max_s", s.get("duration_s", 0.0)))
		for engine: String in TankIds.ENGINES:
			var e: Variant = st[table].get("checkpoint")
			if type != TankIds.SEG_CHECKPOINT:
				e = (st[table].get(engine, {}) as Dictionary).get(type)
			var hard: bool = (
				e is Dictionary
				and str(e.get("mode", "")) == Wl.ERG
				and _planned_peak_pct(e) >= HARD_ERG_PCT
			)
			if hard and longest > HARD_ERG_MAX_S:
				errors.append("%s: %s rides ERG >= 90%% for over 180 s (4.6.1)" % [where, engine])
		if str(SEGMENT_KINDS.get(type, "")) == Wl.WARMUP and s.get("terrain") is Array:
			for pt: Array in s["terrain"]:
				if float(pt[1]) < float(warm[0]) or float(pt[1]) > float(warm[1]):
					errors.append("%s terrain: outside terrain.warmup_grade_pct" % where)
					break
	return errors


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
	if type == TankIds.SEG_GUN_LINE and _num(s.get("max_s")):
		if float(s["max_s"]) > HARD_ERG_MAX_S:
			errors.append("%s max_s: a 90%% gun line lasts at most 180 s (4.6.1)" % where)
	if s.has("terrain"):
		_check_terrain(s["terrain"], str(SEGMENT_KINDS[type]) == Wl.WARMUP, where, errors)


## [[distance_m, grade_pct], ...] ascending, every grade inside -3..+6% (0..+2% in WARMUP kinds).
static func _check_terrain(pts: Variant, warm: bool, where: String, errors: Array[String]) -> void:
	var lo := WARMUP_TERRAIN_MIN_PCT if warm else TERRAIN_MIN_PCT
	var hi := WARMUP_TERRAIN_MAX_PCT if warm else TERRAIN_MAX_PCT
	var last := -1.0
	for pt: Variant in pts if pts is Array else [null]:
		var ok: bool = (
			pt is Array
			and (pt as Array).size() == 2
			and _num(pt[0])
			and _num(pt[1])
			and float(pt[0]) >= last
		)
		if not ok:
			errors.append("%s terrain: [[distance_m, grade_pct], ...] ascending" % where)
			return
		last = float(pt[0])
		if float(pt[1]) < lo or float(pt[1]) > hi:
			errors.append("%s terrain: grade %s outside %s..%s%%" % [where, pt[1], lo, hi])
			return


static func _num(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))
