class_name TankContentSchema
extends RefCounted
## The content schemas and their validators (G0 contract; brief 2.9 "validated at load"). One
## validate_<file>(d) per file under content/tank/, each returning every problem it finds ([] when
## the file is usable). Extra keys are allowed so builders can add tuning knobs; a builder whose
## new key must be required asks the lead to extend the spec here. TankContent (content/) loads
## the files and runs these.
##
## Files:
##   tanks.json     tanks {landship} (v3: one tank, TankIds.TANKS): {code (TankIds.TANK_CODES),
##                  crew [1, TankIds.MAX_CREW], hull_px, engines (its six seats rear to front, each
##                  of TankIds.SEATS once), turrets, enemy_scale, geometry (GEOMETRY_SPEC, rules px in
##                  the hull frame; TankGeometry reads it)}; hull, drive, evade, berm, in_band,
##                  power_ratio, dynamo, steam (v3: the Loader's rack), gun, damage, bow (v3: the
##                  Secondaries' rounds), arc (v3: the Lights' dark range), caps (TANKS_SPEC)
##   stations.json  engines, start_engines, plans, drill_plans, terrain, bank, arc, boiler,
##                  cadence_band, haptics (STATIONS_SPEC; plan entries:
##                  {mode: ERG, target_pct, ramp_to_pct?, range_pct?} or {mode: SIM, grade_source});
##                  every engine has an entry for every segment type of TABLE_SEGMENTS; start_engines
##                  per tank: the seat of each slot (TankIds.MAX_CREW distinct seats; a crew of n
##                  uses the first n); v3 retired rotation (seat choice replaces it)
##   enemies.json   types {light, medium, destroyer, heavy, recon, tankette}: {code, hp, gun
##                  {damage, every_s, hit}, light_mult, flank? {telegraph_s, damage, hit}}, then by
##                  kind ENEMY_FAR_SPEC or ENEMY_NEAR_SPEC; boss; miss_px; miss_m;
##                  crew_count_scale (v3: enemy counts by crew size, one
##                  factor in (0, 1] per crew size 1..TankIds.MAX_CREW) (ENEMIES_SPEC); difficulty
##                  (v4: easy, normal, hard, DIFFICULTY_MULTS and tank_loss, nothing else)
##   missions/<id>.json  {id, label, difficulty_default?, score_stages?, hull_hp?, checkpoint_hp?,
##                  segments: [{id, type, stage,
##                  kind, duration_s, min_s?, max_s?, label, name, backdrop (TankIds.BACKDROPS),
##                  terrain?, length_m?, encounters?, near? [{at_s, enemy, count?, min_crew?}],
##                  obstacles?, enemies? [{.., hold_m?: [metres]}], props?, drills?, boss?}], cooldown}
##   missions/<id>.json with "kind": "roam" (free roam, brief 2.10): {id, kind, label, minutes}
##                  (validate_roam; TankContent.expand_roam turns it into the drive-out and the roam)
##   roam/valley.json  the free-roam valley: length, zones, terrain, strongpoints, patrols, turn,
##                  points and grades (validate_valley; VALLEY_SPEC)
##   scoring.json   scale, weights, objectives, survival_per_breakdown, grades, xp (SCORING_SPEC)
##   cosmetics.json unlocks: [{id, kind, rule: finish | grade | behemoth_no_breakdown, min_grade?}]
##   validate_cross(files): what needs two files (each tank's start engines are rooms of its own
##                  tanks.json engines, in slot order; the mission's plan table and its
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
	"hull.tow_s": "pos",
	"hull.restart_hp_frac": "frac",
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
	"dynamo.elev_deg_s": "pair",
	"dynamo.traverse_s": "pair",
	"steam.full_j": "pos",
	"steam.window_s": "nonneg",
	"steam.over_j": "pos",
	"steam.over_max_pct": "pos",
	"steam.rack_start": "nonneg",
	"steam.below_band_gain": "frac",
	"steam.below_band_cap_pct": "pos",
	"steam.chamber_s": "pos",
	"steam.light_latch_pct": "pos",
	"gun.load_elev_deg": "num",
	"gun.elev_min_deg": "num",
	"gun.elev_max_deg": "num",
	"gun.shell_speed_px_s": "pos",
	"gun.gravity_px_s2": "pos",
	"gun.aim_tol_deg": "pos",
	"gun.far.v0_mps": "pos",
	"gun.far.g_mps2": "pos",
	"gun.far.max_range_m": "pos",
	"gun.far.nudge_deg": "pos",
	"gun.far.aim_tol_deg": "pos",
	"gun.far.dispersion_deg": "pair",
	"gun.far.splash_m": "nonneg",
	"damage.light": "nonneg",
	"damage.heavy": "nonneg",
	"damage.over": "nonneg",
	"damage.splash_px": "nonneg",
	"damage.splash_frac": "nonneg",
	"bow.damage": "nonneg",
	"bow.min_px": "nonneg",
	"bow.max_px": "pos",
	"bow.slew_deg_s": "pair",
	"bow.aim_tol_deg": "pos",
	"bow.clear_rounds": "pos",
	"arc.dark_dispersion_mult": "pos",
	"arc.dark_range_px": "pos",
	"arc.dark_range_m": "pos",
	"repair.hp_per_kj": "pos",
	"repair.patch_hp": "pos",
	"caps.enemies": "pos",
	"caps.shells": "pos",
}
const TANK_SPEC := {
	"code": "pos",
	"crew": "pair",
	"hull_px": "pair",
	"engines": "arr",
	"turrets": "arr",
	"enemy_scale": "pos",
	"geometry": "obj",
}
## v3: tanks.json tanks.<id>.geometry, rules px in the hull frame (x from the hull's rear, y down,
## the hull's bottom at y hull_px[1]; negative y above the hull rect). Rects are [x, y, w, h].
const GEOMETRY_SPEC := {
	"ground_y": "num",
	"hull_rect": "arr",
	"track_rect": "arr",
	"turret_rect": "arr",
	"turret_ring": "pair",
	"trunnion": "pair",
	"barrel_px": "pos",
	"muzzle": "pair",
	"bow_guns": "arr",
	"seats": "obj",
}
const STATIONS_SPEC := {
	"engines": "arr",
	"start_engines": "obj",
	"plans": "obj",
	"drill_plans": "obj",
	"roam_plans": "obj",
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
	"repair.base_pct": "pos",
	"repair.span_pct": "nonneg",
	"repair.every_s": "pos",
	"repair.substeps": "pos",
	"repair.substep_s": "pos",
	"repair.max_step_pts": "pos",
	"boiler.grade_pct": "nonneg",
	"boiler.warmup_grade_pct": "nonneg",
	"boiler.max_rise_pct": "pos",
	"boiler.min_interval_s": "pos",
	"cadence_band.default": "pair",
	"cadence_band.loader": "pair",
	"haptics.hit.min_damage": "nonneg",
	"haptics.hit.haptic": "pos",
	"haptics.hit.duration_s": "pos",
	"haptics.boss_hit.haptic": "pos",
	"haptics.boss_hit.duration_s": "pos",
	"haptics.cooldown_s": "nonneg",
}
## What every enemy kind has.
const ENEMY_SPEC := {
	"code": "pos",
	"hp": "pos",
	"light_mult": "nonneg",
	"gun.damage": "nonneg",
	"gun.every_s": "pos",
	"gun.hit": "frac",
}
## v4: a kind of TankIds.FAR_KINDS (the far frame).
const ENEMY_FAR_SPEC := {
	"hold_m": "pair",
	"enter_m": "pos",
	"enter_mps": "pos",
	"move_mps": "pos",
	"hit_half_m": "pos",
}
## v4: a kind of TankIds.NEAR_KINDS (the near frame: bursts from the bushes, flees).
const ENEMY_NEAR_SPEC := {
	"size_px": "pair",
	"spawn_px": "pair",
	"burst_s": "pos",
	"burst_px_s": "pos",
	"dash_px": "pos",
	"dash_px_s": "pos",
	"pause_s": "pair",
	"flee_px": "pos",
	"flee_after_s": "pos",
	"flee_px_s": "pos",
}
## v4: enemies.json difficulty.<level>: these multipliers, each in DIFFICULTY_MIN..DIFFICULTY_MAX, and
## the bool tank_loss. Any other key is refused, so a retune cannot sneak an effort number in.
const DIFFICULTY_MULTS: Array[String] = ["hp", "damage", "accuracy", "count", "telegraph", "repair"]
const DIFFICULTY_MIN := 0.3
const DIFFICULTY_MAX := 3.0
const ENEMIES_SPEC := {
	"types": "obj",
	"boss.bogies": "pos",
	"boss.bogie_hp": "pos",
	"boss.turret_hp": "pos",
	"boss.hull_px": "pair",
	"boss.main.damage": "nonneg",
	"boss.main.every_s": "pair",
	"boss.main.every_s_phase2": "pair",
	"boss.main.telegraph_s": "pos",
	"boss.secondary.damage": "nonneg",
	"boss.secondary.every_s": "pos",
	"boss.secondary.hit": "frac",
	"boss.far.start_m": "pos",
	"boss.far.stop_m": "pos",
	"boss.far.creep_mps": "nonneg",
	"boss.far.pushback_m": "nonneg",
	"boss.far.part_offset_m": "arr",
	"boss.far.part_half_m": "arr",
	"miss_px": "pair",
	"miss_m": "pair",
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
	"survival_per_loss": "nonneg",
	"loss_grade_cap": "str",
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
	TankIds.SEG_HANGAR: Wl.WARMUP,
	TankIds.SEG_ROLLOUT: Wl.WARMUP,
	TankIds.SEG_SKIRMISH: Wl.WARMUP,
	TankIds.SEG_ADVANCE: Wl.WORK,
	TankIds.SEG_GUN_LINE: Wl.WORK,
	TankIds.SEG_BOSS: Wl.WORK,
	TankIds.SEG_CHECKPOINT: Wl.RECOVERY,
	TankIds.SEG_ROAM: Wl.WORK,
}
const OPEN_SEGMENTS: Array[String] = [
	TankIds.SEG_ADVANCE, TankIds.SEG_GUN_LINE, TankIds.SEG_BOSS, TankIds.SEG_ROAM
]
const UNLOCK_RULES: Array[String] = ["finish", "grade", "behemoth_no_breakdown"]
const GRADES: Array[String] = ["S", "A", "B", "C", "D"]
## The segment types every engine needs an entry for, per plan table.
const TABLE_SEGMENTS := {
	"plans":
	[
		TankIds.SEG_HANGAR,
		TankIds.SEG_ROLLOUT,
		TankIds.SEG_ADVANCE,
		TankIds.SEG_GUN_LINE,
		TankIds.SEG_BOSS
	],
	"drill_plans": [TankIds.SEG_HANGAR, TankIds.SEG_SKIRMISH],
	"roam_plans": [TankIds.SEG_DEPOT, TankIds.SEG_ROAM],
}
## valley.json (free roam, brief 2.10).
const VALLEY_SPEC := {
	"length_m": "pair",
	"start_m": "pos",
	"end_m": "pos",
	"drive_out_s": "pos",
	"overtime_s": "pos",
	"zones": "obj",
	"first_zone": "str",
	"last_zone": "str",
	"middle": "arr",
	"forest_between": "frac",
	"terrain_step_m": "pair",
	"terrain_max_step_pct": "pos",
	"terrain_pct": "pair",
	"end_flat_m": "nonneg",
	"strongpoints.zones": "arr",
	"strongpoints.min_gap_m": "nonneg",
	"strongpoints.clear_ends_m": "nonneg",
	"strongpoints.respawn_s": "pos",
	"strongpoints.spawn_m": "pos",
	"strongpoints.enemy": "str",
	"patrols.every_s": "pair",
	"patrols.max_alive": "pos",
	"patrols.heavy_after_s": "nonneg",
	"patrols.retry_s": "pos",
	"patrols.clear_ahead_m": "nonneg",
	"patrols.kinds": "arr",
	"engage_heavy_m": "pos",
	"fight_m": "pos",
	"turn.stop_s": "pos",
	"turn.cooldown_s": "pos",
	"turn.autopilot_wait_s": "nonneg",
	"turn.forced_wait_s": "nonneg",
	"points.light": "num",
	"points.medium": "num",
	"points.destroyer": "num",
	"points.recon": "num",
	"points.tankette": "num",
	"points.heavy": "num",
	"points.evade": "num",
	"points.breakdown": "num",
	"points.per_km": "num",
	"grades.S": "num",
	"grades.A": "num",
	"grades.B": "num",
	"grades.C": "num",
}
## A free roam's length in minutes (roam_10 .. roam_60; the roam phase's min_s = minutes x 60 -
## the drive-out stays > 0).
const ROAM_MINUTES_MIN := 10
const ROAM_MINUTES_MAX := 120

# --- The brief's safety envelope (brief 2.3 checks, 2.7; BRIEF 4.6) ---------------------------------
## 4.6.1: every ERG target, ramp and range bound in % FTP.
const ERG_MIN_PCT := 50.0
const ERG_MAX_PCT := 100.0
## 4.6.8: ERG in WARMUP-kind segments at most 65%; SIM grades 0..+3% before difficulty.
const WARMUP_ERG_MAX_PCT := 65.0
## The Loader's below-band trickle stops at most this far into a shell (steam.below_band_cap_pct).
const STEAM_TRICKLE_CAP_MAX_PCT := 90.0
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
## Pattern 2: mode grades before difficulty, and how fast they may rise. (v3 retired the Bulwark's
## hoist pattern and its bounds with its gearbox.)
const BOILER_MAX_PCT := 8.0
const BOILER_WARMUP_MAX_PCT := 3.0
const BOILER_MAX_RISE_PCT := 0.5
const BOILER_MIN_INTERVAL_S := 1.0
## Pattern 1 (4.6.2): <= 10 points per update, sub-steps >= 1 s apart, targets inside 50..100%.
const BANK_MAX_STEP_PTS := 10.0
const BANK_MIN_SUBSTEP_S := 1.0
## 4.6.2: one bank update's largest sub-step, 10 points over the 3 s the rule spreads it across (3.3%/s).
const BANK_MAX_SUBSTEP_PTS := 10.0 / 3.0
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
	["repair.base_pct", ">=", ERG_MIN_PCT, "repair targets inside 50..100% (4.6.1)"],
	["repair.max_step_pts", "<=", BANK_MAX_STEP_PTS, "<= 10 points per update (4.6.2)"],
	["repair.substep_s", ">=", BANK_MIN_SUBSTEP_S, "sub-steps >= 1 s apart (4.6.2)"],
	["boiler.grade_pct", "<=", BOILER_MAX_PCT, "boiler 8% x difficulty <= +8% (4.6.6)"],
	["boiler.warmup_grade_pct", "<=", BOILER_WARMUP_MAX_PCT, "warm-up SIM <= +3% (4.6.8)"],
	["boiler.max_rise_pct", "<=", BOILER_MAX_RISE_PCT, "boiler rises <= 0.5% a step"],
	["boiler.min_interval_s", ">=", BOILER_MIN_INTERVAL_S, "boiler <= once a second"],
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
	var cap: Variant = dig(d, "steam.below_band_cap_pct")
	if _num(cap) and (float(cap) > STEAM_TRICKLE_CAP_MAX_PCT or float(cap) < 0.0):
		(
			errors
			. append(
				(
					"tanks.json steam.below_band_cap_pct: at most %d (a shell is always finished in band)"
					% int(STEAM_TRICKLE_CAP_MAX_PCT)
				)
			)
		)
	var restock: Variant = dig(d, "steam.checkpoint_rack_by_crew")
	if restock != null and not _crew_list(restock, 0.0, float(TankConst.RACK_MAX), true):
		errors.append(
			(
				"tanks.json steam.checkpoint_rack_by_crew: one count 0..%d per crew size 1..%d"
				% [TankConst.RACK_MAX, TankIds.MAX_CREW]
			)
		)
	var tanks: Variant = d.get("tanks")
	if tanks is Dictionary:
		for t: String in TankIds.TANKS:
			if not (tanks as Dictionary).has(t):
				errors.append("tanks.json tanks: missing %s" % t)
				continue
			_check_tank(tanks[t], t, errors)
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


## One tank of tanks.json (v3): its spec, its code, its crew range [1, TankIds.MAX_CREW], its rooms
## (each of TankIds.SEATS exactly once, rear to front) and its geometry (GEOMETRY_SPEC: rects of
## four numbers with a positive size, the gun invariant muzzle == trunnion + [barrel_px, 0], at
## least one bow gun with a muzzle, a seat rect per room, the ground at hull_px[1]).
static func _check_tank(def: Variant, t: String, errors: Array[String]) -> void:
	var where := "tanks.json tanks.%s" % t
	check_spec(def, TANK_SPEC, where, errors)
	if not (def is Dictionary):
		return
	if _num(def.get("code")) and int(def["code"]) != int(TankIds.TANK_CODES[t]):
		errors.append("%s.code: must be %d" % [where, TankIds.TANK_CODES[t]])
	var crew: Variant = def.get("crew")
	if _pair_ok(crew) and (int(crew[0]) != 1 or int(crew[1]) != TankIds.MAX_CREW):
		errors.append("%s.crew: must be [1, %d]" % [where, TankIds.MAX_CREW])
	var rooms: Variant = def.get("engines", [])
	if rooms is Array:
		for e: Variant in rooms:
			if not TankIds.ENGINES.has(str(e)):
				errors.append("%s.engines: unknown engine %s" % [where, str(e)])
		for seat: String in TankIds.SEATS:
			if (rooms as Array).count(seat) != 1:
				errors.append("%s.engines: needs the %s seat exactly once" % [where, seat])
	var g: Variant = def.get("geometry")
	if not (g is Dictionary):
		return
	var gw := where + ".geometry"
	var before := errors.size()
	check_spec(g, GEOMETRY_SPEC, gw, errors)
	if errors.size() > before:
		return
	for k: String in ["hull_rect", "track_rect", "turret_rect"]:
		if not _rect_ok(g[k]):
			errors.append("%s.%s: [x, y, w, h] with a positive size" % [gw, k])
	var want_x := float(g["trunnion"][0]) + float(g["barrel_px"])
	var muzzle: Array = g["muzzle"]
	if (
		absf(float(muzzle[0]) - want_x) > 0.01
		or absf(float(muzzle[1]) - float(g["trunnion"][1])) > 0.01
	):
		errors.append("%s.muzzle: must equal trunnion + [barrel_px, 0]" % gw)
	if (g["bow_guns"] as Array).is_empty():
		errors.append("%s.bow_guns: at least one" % gw)
	for i in (g["bow_guns"] as Array).size():
		var bg: Variant = g["bow_guns"][i]
		if not (bg is Dictionary) or not _pair_ok(bg.get("muzzle")):
			errors.append("%s.bow_guns[%d]: {muzzle: [x, y], pivot?: [x, y]}" % [gw, i])
	if rooms is Array:
		for e: Variant in rooms:
			if not _rect_ok((g["seats"] as Dictionary).get(str(e))):
				errors.append("%s.seats.%s: [x, y, w, h] of the seat's room" % [gw, str(e)])
	var size: Variant = def.get("hull_px")
	if size is Array and (size as Array).size() == 2 and _num(size[1]):
		if absf(float(g["ground_y"]) - float(size[1])) > 0.01:
			errors.append("%s.ground_y: must be hull_px[1] (the hull stands on the ground)" % gw)


static func _rect_ok(v: Variant) -> bool:
	if not (v is Array) or (v as Array).size() != 4:
		return false
	for x: Variant in v:
		if not _num(x):
			return false
	return float(v[2]) > 0.0 and float(v[3]) > 0.0


static func _pair_ok(v: Variant) -> bool:
	return v is Array and (v as Array).size() == 2 and _num(v[0]) and _num(v[1])


static func validate_stations(d: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (d is Dictionary):
		return ["stations.json: expected an object"]
	check_spec(d, STATIONS_SPEC, "stations.json", errors)
	if errors.size() > 0:
		return errors
	for t: String in TankIds.TANKS:
		var starts: Variant = d["start_engines"].get(t)
		if not (starts is Array) or (starts as Array).size() != TankIds.MAX_CREW:
			errors.append(
				"stations.json start_engines.%s: one seat per slot (%d)" % [t, TankIds.MAX_CREW]
			)
			continue
		for i in (starts as Array).size():
			var e := str(starts[i])
			if not TankIds.ENGINES.has(e) or (starts as Array).find(e) != i:
				errors.append("stations.json start_engines.%s: distinct known seats" % t)
				break
	if errors.size() > 0:
		return errors
	if d.has("rotation"):
		errors.append("stations.json rotation: retired in v3 (seat choice replaces it)")
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


## A WARMUP-kind entry (the hangar, the roll-out, the depot, the drill's skirmish): ERG at most 65% (BRIEF 4.6.8).
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
	for k: String in ["bank", "arc", "repair"]:
		var sub_pts := float(d[k]["max_step_pts"]) / maxf(float(d[k]["substeps"]), 1.0)
		if sub_pts > BANK_MAX_SUBSTEP_PTS + 1e-9:
			var why := "%s.max_step_pts / %s.substeps: must be <= 10/3, got %s (3.3%%/s, 4.6.2)"
			errors.append("stations.json " + why % [k, k, sub_pts])
	for k: String in ["bank", "arc", "repair"]:
		if float(d[k]["base_pct"]) + float(d[k]["span_pct"]) > ERG_MAX_PCT:
			errors.append("stations.json %s: base_pct + span_pct must be <= 100 (4.6.1)" % k)
	if not bool(d["bank"]["clamp_to_range"]):
		errors.append("stations.json bank.clamp_to_range: must be true (targets stay in range_pct)")
	if float(d["terrain"]["warmup_grade_pct"][1]) > WARMUP_SIM_MAX_PCT:
		errors.append("stations.json terrain.warmup_grade_pct: must be <= +3% (4.6.8)")
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
			check_spec(types[t], _frame_spec(t), "enemies.json types.%s" % t, errors)
			if int(types[t].get("code", 0)) != TankIds.enemy_code(t):
				errors.append("enemies.json types.%s.code: must be %d" % [t, TankIds.enemy_code(t)])
			if (types[t] as Dictionary).has("flank"):
				check_spec(types[t]["flank"], FLANK_SPEC, "enemies.json types.%s.flank" % t, errors)
	_check_difficulty((d as Dictionary).get("difficulty"), errors)
	var scale: Variant = (d as Dictionary).get("crew_count_scale")
	var scale_ok: bool = scale is Array and (scale as Array).size() == TankIds.MAX_CREW
	if scale_ok:
		for f: Variant in scale:
			scale_ok = scale_ok and _num(f) and float(f) > 0.0 and float(f) <= 1.0
	if not scale_ok:
		errors.append(
			(
				"enemies.json crew_count_scale: one factor in (0, 1] per crew size 1..%d"
				% TankIds.MAX_CREW
			)
		)
	var dmg: Variant = (d as Dictionary).get("crew_damage_scale")
	if dmg != null and not _crew_list(dmg, 1e-9, 1.0, false):
		errors.append(
			(
				"enemies.json crew_damage_scale: one factor in (0, 1] per crew size 1..%d"
				% TankIds.MAX_CREW
			)
		)
	var bogies: Variant = dig(d, "boss.bogies_by_crew")
	var all: Variant = dig(d, "boss.bogies")
	if bogies != null and not _crew_list(bogies, 0.0, float(all) if _num(all) else 0.0, true):
		errors.append(
			(
				"enemies.json boss.bogies_by_crew: one count 0..boss.bogies per crew size 1..%d"
				% TankIds.MAX_CREW
			)
		)
	return errors


## The keys a kind needs besides ENEMY_SPEC.
static func _frame_spec(type: String) -> Dictionary:
	return ENEMY_FAR_SPEC if TankIds.FAR_KINDS.has(type) else ENEMY_NEAR_SPEC


## v4: enemies.json difficulty: every level, its multipliers and tank_loss, and no other key: the
## table may never carry an effort number (BRIEF 4.6; TankDifficulty).
static func _check_difficulty(table: Variant, errors: Array[String]) -> void:
	if not (table is Dictionary):
		errors.append("enemies.json difficulty: expected an object")
		return
	for level: String in TankIds.DIFFICULTIES:
		var where := "enemies.json difficulty.%s" % level
		var row: Variant = (table as Dictionary).get(level)
		if not (row is Dictionary):
			errors.append("%s: missing" % where)
			continue
		for key: String in DIFFICULTY_MULTS:
			var v: Variant = (row as Dictionary).get(key)
			if not _num(v) or float(v) < DIFFICULTY_MIN or float(v) > DIFFICULTY_MAX:
				errors.append(
					"%s.%s: expected %s..%s" % [where, key, DIFFICULTY_MIN, DIFFICULTY_MAX]
				)
		if not ((row as Dictionary).get("tank_loss") is bool):
			errors.append("%s.tank_loss: expected a bool" % where)
		for key: Variant in row:
			if str(key) != "tank_loss" and not DIFFICULTY_MULTS.has(str(key)):
				errors.append("%s: unknown key %s (only the listed ones may vary)" % [where, key])
	for level: Variant in table:
		if not TankIds.DIFFICULTIES.has(str(level)):
			errors.append("enemies.json difficulty: unknown level %s" % level)


## True for an array of one value per crew size 1..MAX_CREW, each in [lo, hi] (`ints`: whole).
static func _crew_list(v: Variant, lo: float, hi: float, ints: bool) -> bool:
	if not (v is Array) or (v as Array).size() != TankIds.MAX_CREW:
		return false
	for f: Variant in v:
		if not _num(f) or float(f) < lo or float(f) > hi:
			return false
		if ints and float(f) != floorf(float(f)):
			return false
	return true


static func validate_mission(d: Variant, mission_id: String = "") -> Array[String]:
	var errors: Array[String] = []
	var at := "missions/%s.json" % mission_id
	if not (d is Dictionary):
		return ["%s: expected an object" % at]
	if mission_id != "" and str(d.get("id", "")) != mission_id:
		errors.append("%s id: must be %s" % [at, mission_id])
	if not (d.get("label") is String):
		errors.append("%s label: expected a strings key" % at)
	if d.has("difficulty_default") and not TankIds.DIFFICULTIES.has(str(d["difficulty_default"])):
		errors.append("%s difficulty_default: one of %s" % [at, ", ".join(TankIds.DIFFICULTIES)])
	if d.has("score_stages") and not (_num(d["score_stages"]) and float(d["score_stages"]) > 0.0):
		errors.append("%s score_stages: expected > 0" % at)
	for key: String in ["hull_hp", "checkpoint_hp"]:
		if d.has(key) and not (_num(d[key]) and float(d[key]) > 0.0):
			errors.append("%s %s: expected > 0" % [at, key])
	var segs: Variant = d.get("segments")
	if not (segs is Array) or (segs as Array).is_empty():
		errors.append("%s segments: expected a non-empty array" % at)
		return errors
	for i in (segs as Array).size():
		_check_segment(segs[i], "%s segments[%d]" % [at, i], errors)
	return errors


## A free-roam file (brief 2.10): {id, kind "roam", label, minutes 10..120}.
static func validate_roam(d: Variant, mission_id: String = "") -> Array[String]:
	var errors: Array[String] = []
	var at := "missions/%s.json" % mission_id
	if not (d is Dictionary):
		return ["%s: expected an object" % at]
	if mission_id != "" and str(d.get("id", "")) != mission_id:
		errors.append("%s id: must be %s" % [at, mission_id])
	if str(d.get("kind", "")) != TankIds.KIND_ROAM:
		errors.append("%s kind: must be roam" % at)
	if not (d.get("label") is String) or str(d["label"]) == "":
		errors.append("%s label: expected a strings key" % at)
	var mins: Variant = d.get("minutes")
	if not (_num(mins) and float(mins) == floorf(float(mins))):
		errors.append("%s minutes: expected a whole number" % at)
	elif int(mins) < ROAM_MINUTES_MIN or int(mins) > ROAM_MINUTES_MAX:
		errors.append("%s minutes: must be %d..%d" % [at, ROAM_MINUTES_MIN, ROAM_MINUTES_MAX])
	if (d as Dictionary).has("segments"):
		errors.append("%s segments: a free roam lists none (TankContent.expand_roam)" % at)
	return errors


## The free-roam valley (roam/valley.json, brief 2.10): VALLEY_SPEC, every zone of TankIds.ZONES with
## its len_m and terrain_pct inside the valley's terrain_pct, which lies inside the brief's -3..+6%
## (BRIEF 4.6.6), a drive-out of at least the first 300 s (BRIEF 4.6.8: the roam's ERG ranges start
## after it), patrol kinds with known enemies and positive weights, and the grade cut-offs falling.
static func validate_valley(d: Variant) -> Array[String]:
	var errors: Array[String] = []
	var at := "roam/valley.json"
	if not (d is Dictionary):
		return ["%s: expected an object" % at]
	check_spec(d, VALLEY_SPEC, at, errors)
	if not errors.is_empty():
		return errors
	var tp: Array = d["terrain_pct"]
	if float(tp[0]) < TERRAIN_MIN_PCT or float(tp[1]) > TERRAIN_MAX_PCT or tp[0] > tp[1]:
		errors.append("%s terrain_pct: must lie in -3..+6%% (BRIEF 4.6.6)" % at)
	if float(d["drive_out_s"]) < TankConst.FIRST_S:
		errors.append("%s drive_out_s: must be >= 300 (the warm-up, BRIEF 4.6.8)" % at)
	var zones: Dictionary = d["zones"]
	for z: String in TankIds.ZONES:
		if not zones.has(z):
			errors.append("%s zones: missing %s" % [at, z])
			continue
		var where := "%s zones.%s" % [at, z]
		check_spec(
			zones[z], {"len_m": "pair", "terrain_pct": "pair", "label": "str"}, where, errors
		)
		if not TankIds.BACKDROPS.has(str((zones[z] as Dictionary).get("backdrop", ""))):
			errors.append("%s backdrop: one of %s" % [where, ", ".join(TankIds.BACKDROPS)])
		var zt: Variant = dig(zones[z], "terrain_pct")
		if zt is Array and (zt as Array).size() == 2 and _num(zt[0]) and _num(zt[1]):
			if float(zt[0]) < float(tp[0]) or float(zt[1]) > float(tp[1]):
				errors.append("%s terrain_pct: must lie inside the valley's terrain_pct" % where)
	for k: String in ["first_zone", "last_zone"]:
		if not TankIds.ZONES.has(str(d[k])):
			errors.append("%s %s: one of %s" % [at, k, ", ".join(TankIds.ZONES)])
	for z2: Variant in (d["middle"] as Array) + (d["strongpoints"]["zones"] as Array):
		if not TankIds.ZONES.has(str(z2)):
			errors.append("%s: unknown zone %s" % [at, str(z2)])
	var lo := float(d["length_m"][0])
	if lo <= 2.0 * float(d["end_m"]) or float(d["length_m"][1]) < lo:
		errors.append("%s length_m: [lo, hi] with lo > 2 x end_m" % at)
	var kinds: Array = d["patrols"]["kinds"]
	if kinds.is_empty():
		errors.append("%s patrols.kinds: expected at least one" % at)
	for k2: Variant in kinds:
		var ok: bool = k2 is Dictionary and _num(k2.get("weight")) and float(k2["weight"]) > 0.0
		ok = ok and k2.get("units") is Array and not (k2["units"] as Array).is_empty()
		if not ok:
			errors.append("%s patrols.kinds: each needs a weight > 0 and units" % at)
			continue
		for u: Variant in k2["units"]:
			if not _unit_ok(u):
				errors.append("%s patrols.kinds units: {enemy, count: [lo, hi]}" % at)
	var cut: Array[float] = []
	for g: String in ["S", "A", "B", "C"]:
		cut.append(float(d["grades"][g]))
	for i in range(1, cut.size()):
		if cut[i] > cut[i - 1]:
			errors.append("%s grades: S >= A >= B >= C" % at)
			break
	return errors


## A patrol unit {enemy: a known type, count: [lo, hi] whole, 0 <= lo <= hi}.
static func _unit_ok(u: Variant) -> bool:
	if not (u is Dictionary) or not TankIds.ENEMY_TYPES.has(str(u.get("enemy", ""))):
		return false
	var n: Variant = u.get("count")
	if not (n is Array) or (n as Array).size() != 2 or not _num(n[0]) or not _num(n[1]):
		return false
	return int(n[0]) >= 0 and int(n[0]) <= int(n[1])


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


## What needs two files ({tanks, stations, mission, enemies?}; run once each file validated alone):
## the start engines are rooms of their tank (v4: four of its six seats); the mission's plan table
## exists and holds every segment type it uses; an ERG phase planned at or above 90% (target or
## ramp, not the bank's range top) lasts at most 180 s at its longest; WARMUP-kind terrain stays
## inside stations.json terrain.warmup_grade_pct; v4: a holding force's hold_m stays at or above its
## kind's hold_m[0] (the 6 s evade floor at Hard rests on it, SPEC_TANK section 2).
static func validate_cross(files: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var tanks: Dictionary = files.get("tanks", {})
	var st: Dictionary = files.get("stations", {})
	var m: Dictionary = files.get("mission", {})
	for t: String in TankIds.TANKS:
		var rooms: Array = (tanks["tanks"][t] as Dictionary).get("engines", [])
		for e: Variant in st["start_engines"].get(t, []):
			if not rooms.has(e):
				errors.append(
					(
						"stations.json start_engines.%s: %s is not a room of tanks.json tanks.%s"
						% [t, e, t]
					)
				)
	var table := str(m.get("plan_table", "plans"))
	var at := "missions/%s.json" % str(m.get("id", ""))
	if not TABLE_SEGMENTS.has(table):
		errors.append("%s plan_table: one of %s" % [at, ", ".join(TABLE_SEGMENTS.keys())])
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
		_check_hold_m(s, files.get("enemies", {}), where, errors)
		if str(SEGMENT_KINDS.get(type, "")) == Wl.WARMUP and s.get("terrain") is Array:
			for pt: Array in s["terrain"]:
				if float(pt[1]) < float(warm[0]) or float(pt[1]) > float(warm[1]):
					errors.append("%s terrain: outside terrain.warmup_grade_pct" % where)
					break
	return errors


## v4: no entry of a segment's enemies holds nearer than its kind's hold_m[0].
static func _check_hold_m(s: Dictionary, enemies: Dictionary, where: String, errors: Array) -> void:
	for e: Variant in s.get("enemies", []) if s.get("enemies", []) is Array else []:
		if not (e is Dictionary) or not (e.get("hold_m") is Array):
			continue
		var low: Variant = dig_index(enemies, "types.%s.hold_m.0" % str(e.get("enemy", "")))
		for m: Variant in e["hold_m"]:
			if not _num(m) or (_num(low) and float(m) < float(low)):
				errors.append(
					"%s enemies: %s hold_m %s below the kind's hold_m[0]" % [where, e["enemy"], m]
				)


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
	if s.has("backdrop") and not TankIds.BACKDROPS.has(str(s["backdrop"])):
		errors.append("%s backdrop: one of %s" % [where, ", ".join(TankIds.BACKDROPS)])
	if [TankIds.SEG_ADVANCE, TankIds.SEG_SKIRMISH].has(type):
		if not _num(s.get("length_m")) or float(s["length_m"]) <= 0.0:
			errors.append("%s length_m: expected > 0" % where)
		for e: Variant in s.get("encounters", []):
			if not (e is Dictionary) or not TankIds.ENEMY_TYPES.has(str(e.get("enemy", ""))):
				errors.append("%s encounters: each needs a known enemy" % where)
			elif (e as Dictionary).has("from"):
				errors.append('%s encounters: "from" is gone: nothing comes from behind' % where)
	if type == TankIds.SEG_HANGAR:
		_check_hangar(s, where, errors)
	_check_near(s.get("near", []), where, errors)
	for key in ["encounters", "enemies", "obstacles", "near"]:
		for e: Variant in s.get(key, []) if s.get(key, []) is Array else []:
			var mc: Variant = (e as Dictionary).get("min_crew", 1) if e is Dictionary else 1
			if not _num(mc) or int(mc) < 1 or int(mc) > TankIds.MAX_CREW:
				errors.append("%s %s: min_crew is 1..%d" % [where, key, TankIds.MAX_CREW])
	if type == TankIds.SEG_GUN_LINE and _num(s.get("max_s")):
		if float(s["max_s"]) > HARD_ERG_MAX_S:
			errors.append("%s max_s: a 90%% gun line lasts at most 180 s (4.6.1)" % where)
	if s.has("terrain"):
		_check_terrain(s["terrain"], str(SEGMENT_KINDS[type]) == Wl.WARMUP, where, errors)


## v1.1.0: the Hangar's last HANGAR_COUNTDOWN_S are the countdown, so it is longer than twice that and
## each drill window ends before it.
static func _check_hangar(s: Dictionary, where: String, errors: Array[String]) -> void:
	var dur := float(s.get("duration_s", 0.0)) if _num(s.get("duration_s")) else 0.0
	var free := dur - TankConst.HANGAR_COUNTDOWN_S
	if dur < 2.0 * TankConst.HANGAR_COUNTDOWN_S:
		errors.append(
			"%s: a hangar lasts at least %d s" % [where, int(2.0 * TankConst.HANGAR_COUNTDOWN_S)]
		)
	var drills: Variant = s.get("drills", [])
	if not (drills is Array):
		errors.append("%s drills: expected a list" % where)
		return
	for d: Variant in drills:
		var ok: bool = (
			d is Dictionary
			and _num(d.get("from_s"))
			and _num(d.get("to_s"))
			and ["drive", "aim", "fire"].has(str(d.get("drill", "")))
			and float(d["from_s"]) >= 0.0
			and float(d["from_s"]) < float(d["to_s"])
		)
		if not ok:
			errors.append("%s drills: [{from_s, to_s, drill: drive|aim|fire}, ...]" % where)
			return
		if float(d["to_s"]) > free + 1e-6:
			errors.append(
				"%s drills: a drill ends before the countdown (%d s in)" % [where, int(free)]
			)


## v4: a segment's near list: [{at_s, enemy (a near kind), count?, min_crew?}], at_s ascending.
static func _check_near(list: Variant, where: String, errors: Array[String]) -> void:
	var last := -1.0
	for e: Variant in list if list is Array else [null]:
		var ok: bool = (
			e is Dictionary
			and _num(e.get("at_s"))
			and float(e["at_s"]) >= last
			and TankIds.NEAR_KINDS.has(str(e.get("enemy", "")))
		)
		if not ok:
			errors.append("%s near: [{at_s, enemy: a near kind}, ...] at_s ascending" % where)
			return
		last = float(e["at_s"])


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
