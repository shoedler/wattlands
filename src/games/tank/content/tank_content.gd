class_name TankContent
extends RefCounted
## Every Tank content file, loaded and validated together (brief 2.9; BRIEF 6). Owner: rules
## (G0 wrote a working loader; the schemas live in contracts/tank_content_schema.gd).
##
## Frozen accessors (contracts/README.md "TankContent surface"): TankState.create and effort's
## TankPlanBuilder call ok, num, value, mission, segments, segment, plan_table, plan_entry,
## tank_def, engines_of, start_engines, enemy_def, boss_def, enemy_scale, scaled_count and
## unlocks. Their names, arguments and meanings never change; the rules builder may add methods
## and change the internals only. v3 retired rotation (mission_rotates and rotation_row are gone
## with it) and added crew_count (enemy counts by crew size).
##
## Load in the module with load_for(ctx) (through ctx.load_content_json, so run_game_sim
## --override reaches every file); tests and the rules-level harness use read_files() +
## from_dicts(). The mission is content/tank/missions/<content id>.json.
##
## Free roam (brief 2.10): a missions/<id>.json with "kind": "roam" and "minutes" holds no segments;
## from_dicts validates it and expands it (expand_roam) into two segments before anything else reads
## it: the drive-out (type depot, WARMUP, valley.json drive_out_s = 300 s, no drills, no enemies) and
## the roam (type roam, WORK, open-ended, min_s = minutes x 60 - drive_out_s, max_s = min_s +
## overtime_s), plan table stations.json roam_plans. v3: the roam's plan phase is open-ended from
## plan_min_s (TankConst.SWITCH_GAP_S; v3 needed it to split the phase, 0.3.1 splits any phase); the game's
## time up still reads the segment's min_s (TankPhaseInfo.min_s from the phase meta). The valley (roam/valley.json, file
## key "valley") is loaded with every content and validated when the content is a roam.

const FILES := {
	"tanks": "tanks.json",
	"stations": "stations.json",
	"enemies": "enemies.json",
	"scoring": "scoring.json",
	"cosmetics": "cosmetics.json",
	"valley": "roam/valley.json",
}
const CONTENT_DIR := "res://content/tank"

## File key -> parsed Dictionary (FILES keys plus "mission").
var data: Dictionary = {}
var mission_id: String = ""
## Every problem found; empty when the content is usable.
var errors: Array[String] = []


## Loads every file through ctx (overrides applied) and validates it.
static func load_for(ctx: GameContext) -> TankContent:
	var files := {}
	for k: String in FILES:
		files[k] = ctx.load_content_json(FILES[k])
	files["mission"] = ctx.load_content_json(mission_path(ctx.content_id))
	return from_dicts(files, ctx.content_id)


## The mission file's path under content/tank/.
static func mission_path(id: String) -> String:
	return "missions/%s.json" % id


## Reads the files straight from res://content/tank (tests and tools; no overrides).
static func read_files(p_mission_id: String) -> Dictionary:
	var files := {}
	for k: String in FILES:
		files[k] = _read(CONTENT_DIR.path_join(FILES[k]))
	files["mission"] = _read(CONTENT_DIR.path_join(mission_path(p_mission_id)))
	return files


## Validates parsed files ({tanks, stations, enemies, scoring, cosmetics, mission}).
static func from_dicts(files: Dictionary, p_mission_id: String) -> TankContent:
	var c := TankContent.new()
	c.mission_id = p_mission_id
	c.data = files.duplicate(true)
	c.errors.append_array(TankContentSchema.validate_tanks(files.get("tanks")))
	c.errors.append_array(TankContentSchema.validate_stations(files.get("stations")))
	c.errors.append_array(TankContentSchema.validate_enemies(files.get("enemies")))
	c.errors.append_array(TankContentSchema.validate_scoring(files.get("scoring")))
	c.errors.append_array(TankContentSchema.validate_cosmetics(files.get("cosmetics")))
	var m: Variant = files.get("mission")
	if m is Dictionary and str((m as Dictionary).get("kind", "")) == TankIds.KIND_ROAM:
		var roam_errors := TankContentSchema.validate_roam(m, p_mission_id)
		roam_errors.append_array(TankContentSchema.validate_valley(files.get("valley")))
		c.errors.append_array(roam_errors)
		if roam_errors.is_empty():
			c.data["mission"] = expand_roam(m, files.get("valley"))
	c.errors.append_array(TankContentSchema.validate_mission(c.data.get("mission"), p_mission_id))
	if c.errors.is_empty():
		c.errors.append_array(TankContentSchema.validate_cross(c.data))
	return c


## A free-roam file ({id, kind "roam", label, minutes}) as a mission with its two segments (brief
## 2.10 Effort plan): the drive-out and the open-ended roam phase.
static func expand_roam(roam: Dictionary, valley: Dictionary) -> Dictionary:
	var drive_s := float(valley.get("drive_out_s", 300.0))
	var min_s := float(roam.get("minutes", 30)) * 60.0 - drive_s
	var out := roam.duplicate(true)
	out["plan_table"] = "roam_plans"
	out["segments"] = [
		{
			"id": "drive_out",
			"type": TankIds.SEG_DEPOT,
			"stage": 0,
			"kind": Wl.WARMUP,
			"duration_s": drive_s,
			"label": "TANK_PHASE_DRIVE_OUT",
			"name": "TANK_PLACE_VALLEY",
		},
		{
			"id": "roam",
			"type": TankIds.SEG_ROAM,
			"stage": 1,
			"kind": Wl.WORK,
			"duration_s": min_s,
			"min_s": min_s,
			"plan_min_s": minf(TankConst.SWITCH_GAP_S, min_s),
			"max_s": min_s + float(valley.get("overtime_s", 300.0)),
			"label": "TANK_PHASE_ROAM",
			"name": "TANK_PLACE_VALLEY",
		},
	]
	out["cooldown"] = {}
	return out


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func ok() -> bool:
	return errors.is_empty()


## A number at a dotted path of a file ("tanks", "hull.hp"), or `default`.
func num(file: String, path: String, default: float = 0.0) -> float:
	var v: Variant = TankContentSchema.dig(data.get(file, {}), path)
	return float(v) if (v is int or v is float) else default


## Any value at a dotted path of a file, or `default`.
func value(file: String, path: String, default: Variant = null) -> Variant:
	var v: Variant = TankContentSchema.dig(data.get(file, {}), path)
	return default if v == null else v


func mission() -> Dictionary:
	return data.get("mission", {})


func segments() -> Array:
	return mission().get("segments", [])


## The mission segment `i` ({} out of range).
func segment(i: int) -> Dictionary:
	var segs := segments()
	return segs[i] if i >= 0 and i < segs.size() else {}


## stations.json table this mission's plans use ("plans" or "drill_plans").
func plan_table() -> String:
	return str(mission().get("plan_table", "plans"))


## The plan entry for `engine` in a segment of type `seg_type` ({mode, target_pct, ...}).
## Checkpoints use the table's "checkpoint" entry for every engine.
func plan_entry(engine: String, seg_type: String) -> Dictionary:
	var table: Dictionary = data["stations"].get(plan_table(), {})
	if seg_type == TankIds.SEG_CHECKPOINT:
		return table.get("checkpoint", {})
	return (table.get(engine, {}) as Dictionary).get(seg_type, {})


func tank_def(tank: String) -> Dictionary:
	return (data["tanks"].get("tanks", {}) as Dictionary).get(tank, {})


## The tank's rooms rear to front.
func engines_of(tank: String) -> Array[String]:
	var out: Array[String] = []
	for e: Variant in tank_def(tank).get("engines", []):
		out.append(str(e))
	return out


## Starting engine by slot (stations.json start_engines; v3: the seat of each slot, a crew of n
## takes the first n).
func start_engines(tank: String) -> Array[String]:
	var out: Array[String] = []
	for e: Variant in (data["stations"].get("start_engines", {}) as Dictionary).get(tank, []):
		out.append(str(e))
	return out


func enemy_def(type: String) -> Dictionary:
	return (data["enemies"].get("types", {}) as Dictionary).get(type, {})


func boss_def() -> Dictionary:
	return data["enemies"].get("boss", {})


func enemy_scale(tank: String) -> float:
	return float(tank_def(tank).get("enemy_scale", 1.0))


## An enemy count after the tank's scale: rounded, at least 1 (brief 2.4).
func scaled_count(count: int, tank: String) -> int:
	return maxi(1, roundi(count * enemy_scale(tank)))


## (v3) The factor on enemy counts for a crew of `crew` (enemies.json crew_count_scale: 0.5, 0.7,
## 0.85, 1.0 for crews 1-4; 1 when the file has none).
func crew_scale(crew: int) -> float:
	var f: Variant = data.get("enemies", {}).get("crew_count_scale")
	if not (f is Array) or (f as Array).is_empty():
		return 1.0
	return float(f[clampi(crew, 1, (f as Array).size()) - 1])


## (v3) An enemy count for a crew of `crew` (brief v3 "Difficulty is enemy count"): the count x
## the tank's scale (the landship's 1.0) x crew_scale(crew) x `mult` (v4: difficulty.count), rounded,
## at least 1. Enemy HP is the same for every crew size.
func crew_count(count: int, tank: String, crew: int, mult: float = 1.0) -> int:
	return maxi(1, roundi(count * enemy_scale(tank) * crew_scale(crew) * mult))


## (v3 solo balance) The factor on the damage enemy and Behemoth shells do to the tank for a crew
## of `crew` (enemies.json crew_damage_scale; 1 without it). Enemy HP stays the same for every crew.
func crew_damage_scale(crew: int) -> float:
	var f: Variant = data.get("enemies", {}).get("crew_damage_scale")
	if not (f is Array) or (f as Array).is_empty():
		return 1.0
	return float(f[clampi(crew, 1, (f as Array).size()) - 1])


## (v3 solo balance) How many of the Behemoth's bogies stand for a crew of `crew` (enemies.json
## boss.bogies_by_crew; every bogie without it): the rest come already wrecked, the far ones first
## (none standing: the Behemoth starts in phase 2, its turret alone).
func boss_bogies(crew: int) -> int:
	var b: Dictionary = boss_def()
	var all := int(b.get("bogies", 3))
	var f: Variant = b.get("bogies_by_crew")
	if not (f is Array) or (f as Array).is_empty():
		return all
	return clampi(int(f[clampi(crew, 1, (f as Array).size()) - 1]), 0, all)


func unlocks() -> Array:
	return data["cosmetics"].get("unlocks", [])


## True for a free-roam content (brief 2.10).
func is_roam() -> bool:
	return str(mission().get("kind", TankIds.KIND_MISSION)) == TankIds.KIND_ROAM


## A free roam's length in minutes (0 for a mission).
func roam_minutes() -> int:
	return int(mission().get("minutes", 0)) if is_roam() else 0


## The valley (roam/valley.json) as validated ({} when missing).
func valley() -> Dictionary:
	var v: Variant = data.get("valley", {})
	return v if v is Dictionary else {}
