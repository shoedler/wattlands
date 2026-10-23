class_name TankContent
extends RefCounted
## Every Tank content file, loaded and validated together (brief 2.9; BRIEF 6). Owner: rules
## (G0 wrote a working loader; the schemas live in contracts/tank_content_schema.gd).
##
## Load in the module with load_for(ctx) (through ctx.load_content_json, so run_game_sim
## --override reaches every file); tests and the rules-level harness use read_files() +
## from_dicts(). The mission is content/tank/missions/<content id>.json.

const FILES := {
	"tanks": "tanks.json",
	"stations": "stations.json",
	"enemies": "enemies.json",
	"scoring": "scoring.json",
	"cosmetics": "cosmetics.json",
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
	c.errors.append_array(TankContentSchema.validate_mission(files.get("mission"), p_mission_id))
	if c.errors.is_empty():
		var table := c.plan_table()
		if not (c.data["stations"] as Dictionary).has(table):
			c.errors.append(
				"missions/%s.json plan_table: %s not in stations.json" % [p_mission_id, table]
			)
	return c


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


## Whether the mission plays the rotation option (the drill ignores it).
func mission_rotates() -> bool:
	return bool(mission().get("rotation", true))


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


## Starting engine by slot (stations.json start_engines).
func start_engines(tank: String) -> Array[String]:
	var out: Array[String] = []
	for e: Variant in (data["stations"].get("start_engines", {}) as Dictionary).get(tank, []):
		out.append(str(e))
	return out


## The engines of `slot` for stages 1, 2, 3 and the boss with rotation on (stations.json
## rotation; the Bulwark always "bulwark").
func rotation_row(tank: String, slot: int) -> Array[String]:
	var out: Array[String] = []
	var rows: Array = (data["stations"].get("rotation", {}) as Dictionary).get(tank, [])
	if slot >= 0 and slot < rows.size():
		for e: Variant in rows[slot]:
			out.append(str(e))
	else:
		var start := start_engines(tank)
		var e: String = start[slot] if slot >= 0 and slot < start.size() else TankIds.ENGINE_BULWARK
		for _i in 4:
			out.append(e)
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


func unlocks() -> Array:
	return data["cosmetics"].get("unlocks", [])
