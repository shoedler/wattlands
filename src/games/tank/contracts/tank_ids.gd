class_name TankIds
extends RefCounted
## Every id and wire code Diesel Domestiques uses (G0 contract; docs/games/tank.md). String ids
## are what content, intents and plan metas carry; the int codes are what snapshots and events
## carry (TankSnapshotSchema, TankEvents). Codes never change once shipped: add new ones at the end.

# --- Tanks (brief 2.2): the crew size picks the tank ------------------------------------------------
const TANK_BULWARK := "bulwark"
const TANK_RAMPART := "rampart"
const TANK_CITADEL := "citadel"
## v2: the Citadel plus an arc-generator room and a searchlight tower (crew 4).
const TANK_BASTION := "bastion"
## Index = crew size - 1.
const TANKS: Array[String] = [TANK_BULWARK, TANK_RAMPART, TANK_CITADEL, TANK_BASTION]
const TANK_CODES := {TANK_BULWARK: 1, TANK_RAMPART: 2, TANK_CITADEL: 3, TANK_BASTION: 4}

# --- Engines (stations). "bulwark" is the solo diesel with its three-way gearbox --------------------
const ENGINE_DIESEL := "diesel"
const ENGINE_DYNAMO := "dynamo"
const ENGINE_STEAM := "steam"
const ENGINE_BULWARK := "bulwark"
## v2 (the Bastion): the arc generator, steady ERG tempo that lifts while the bow guns fire; it
## lights the searchlights and powers the Bastion's bow guns (brief 2.4 Arc generator).
const ENGINE_ARC := "arc"
const ENGINES: Array[String] = [
	ENGINE_DIESEL, ENGINE_DYNAMO, ENGINE_STEAM, ENGINE_BULWARK, ENGINE_ARC
]
const ENGINE_CODES := {
	ENGINE_DIESEL: 1, ENGINE_DYNAMO: 2, ENGINE_STEAM: 3, ENGINE_BULWARK: 4, ENGINE_ARC: 5
}
## Engine name keys (TANK_ENGINE_*), for station cards and results.
const ENGINE_LABELS := {
	ENGINE_DIESEL: "TANK_ENGINE_DIESEL",
	ENGINE_DYNAMO: "TANK_ENGINE_DYNAMO",
	ENGINE_STEAM: "TANK_ENGINE_STEAM",
	ENGINE_BULWARK: "TANK_ENGINE_BULWARK",
	ENGINE_ARC: "TANK_ENGINE_ARC",
}
## The engine icon the teammate strip shows (teammate_status "icon", a res:// texture path). artqa
## may ship them (14 x 14 art px palette icons with their .import files, not art.json sprites);
## until then the kit skips the missing file and the engine name in "text" carries the meaning, which
## is an accepted state, not a bug.
const ENGINE_ICONS := {
	ENGINE_DIESEL: "res://assets/tank/icons/engine_diesel.png",
	ENGINE_DYNAMO: "res://assets/tank/icons/engine_dynamo.png",
	ENGINE_STEAM: "res://assets/tank/icons/engine_steam.png",
	ENGINE_BULWARK: "res://assets/tank/icons/engine_bulwark.png",
	ENGINE_ARC: "res://assets/tank/icons/engine_arc.png",
}

# --- Segments (brief 2.3 segment table; the drill's skirmish, 2.9) -----------------------------------
const SEG_DEPOT := "depot"
const SEG_ADVANCE := "advance"
const SEG_GUN_LINE := "gun_line"
const SEG_CHECKPOINT := "checkpoint"
const SEG_BOSS := "boss"
const SEG_SKIRMISH := "skirmish"
## v2 free roam (brief 2.10): the one open-ended WORK phase on the valley road (the drive-out before
## it is a SEG_DEPOT of WARMUP kind with no drills and no enemies).
const SEG_ROAM := "roam"
## Not a plan phase of the game's: the PlanValidator's appended cool-down.
const SEG_COOLDOWN := "cooldown"
const SEG_NONE := ""
const SEGMENTS: Array[String] = [
	SEG_DEPOT, SEG_ADVANCE, SEG_GUN_LINE, SEG_CHECKPOINT, SEG_BOSS, SEG_SKIRMISH, SEG_ROAM
]
const SEG_CODES := {
	SEG_NONE: 0,
	SEG_DEPOT: 1,
	SEG_ADVANCE: 2,
	SEG_GUN_LINE: 3,
	SEG_CHECKPOINT: 4,
	SEG_BOSS: 5,
	SEG_SKIRMISH: 6,
	SEG_COOLDOWN: 7,
	SEG_ROAM: 8,
}

# --- Contents and free roam (brief 2.9, 2.10) ------------------------------------------------------
## missions/<id>.json "kind": a mission (segments listed in the file) or a free roam (kind "roam",
## minutes; TankContent expands it into the drive-out and the roam segment).
const KIND_MISSION := "mission"
const KIND_ROAM := "roam"
## The valley's zones (content/tank/roam/valley.json), each with its terrain and near planes.
const ZONE_FOREST := "forest"
const ZONE_LAKE := "lake"
const ZONE_VILLAGE := "village"
const ZONE_QUARRY := "quarry"
const ZONE_MEADOW := "meadow"
const ZONES: Array[String] = [ZONE_FOREST, ZONE_LAKE, ZONE_VILLAGE, ZONE_QUARRY, ZONE_MEADOW]

# --- Enemies (brief 2.4 table) ----------------------------------------------------------------------
const ENEMY_LIGHT := "light"
const ENEMY_MEDIUM := "medium"
const ENEMY_DESTROYER := "destroyer"
const ENEMY_DUGIN := "dugin"
const ENEMY_HEAVY := "heavy"
const ENEMY_TYPES: Array[String] = [
	ENEMY_LIGHT, ENEMY_MEDIUM, ENEMY_DESTROYER, ENEMY_DUGIN, ENEMY_HEAVY
]
const ENEMY_CODES := {
	ENEMY_LIGHT: 1, ENEMY_MEDIUM: 2, ENEMY_DESTROYER: 3, ENEMY_DUGIN: 4, ENEMY_HEAVY: 5
}
## The Behemoth's code in kill counts and events ("kill" t, results kills by type).
const BOSS_CODE := 6
const BOSS_ID := "behemoth"

## Enemy behaviour states (TankEnemyState.mode).
const EM_ENTER := 0
const EM_HOLD := 1
const EM_TELEGRAPH := 2
const EM_MOVE := 3
const EM_BACKOFF := 4
const EM_DEAD := 5
## A raider breaking off (a light tank after its linger_s): rolls away, does not fire, leaves with no
## kill. Distinct from EM_MOVE, a destroyer's shift after a shot.
const EM_LEAVE := 6

## Where an Advance encounter enters.
const FROM_FRONT := "front"
const FROM_REAR := "rear"

# --- Obstacles and props ----------------------------------------------------------------------------
const OBST_WIRE := "wire"
const OBST_WRECK := "wreck"
## The depot's aim drill targets (no HP effect on scoring).
const OBST_DRILL_WRECK := "drill_wreck"
const OBST_TANK_TRAPS := "tank_traps"
const OBSTACLE_TYPES: Array[String] = [OBST_WIRE, OBST_WRECK, OBST_DRILL_WRECK, OBST_TANK_TRAPS]
const OBSTACLE_CODES := {OBST_WIRE: 1, OBST_WRECK: 2, OBST_DRILL_WRECK: 3, OBST_TANK_TRAPS: 4}

# --- Shells -----------------------------------------------------------------------------------------
const SHELL_NONE := 0
const SHELL_LIGHT := 1
const SHELL_HEAVY := 2
const SHELL_OVER := 3
## The bow guns' round (v2, brief 2.4 Gun; formerly the Citadel's secondaries, same code).
const SHELL_BOW := 4
## Enemy rounds (one code; the enemy type is in the shot event).
const SHELL_ENEMY := 5
const SHELL_BOSS_MAIN := 6
const SHELL_NAMES := {
	SHELL_LIGHT: "light",
	SHELL_HEAVY: "heavy",
	SHELL_OVER: "over",
	SHELL_BOW: "bow",
	SHELL_ENEMY: "enemy",
	SHELL_BOSS_MAIN: "boss_main",
}

# --- Bulwark gearbox lever --------------------------------------------------------------------------
## Drive is "Dig" at a gun line (the same position).
const LEVER_DRIVE := 0
const LEVER_TURRET := 1
const LEVER_HOIST := 2
const LEVER_NAMES: Array[String] = ["drive", "turret", "hoist"]
const LEVER_LABELS: Array[String] = ["TANK_LEVER_DRIVE", "TANK_LEVER_TURRET", "TANK_LEVER_HOIST"]
const LEVER_DIG_LABEL := "TANK_LEVER_DIG"

# --- Turret -----------------------------------------------------------------------------------------
const FACE_RIGHT := 1
const FACE_LEFT := -1

# --- Travel direction (TankHullState.dir; v2 free roam, brief 2.10) ----------------------------------
## Missions always travel right; a free-roam turn flips it.
const DIR_RIGHT := 1
const DIR_LEFT := -1

# --- Boss -------------------------------------------------------------------------------------------
const BOSS_NONE := 0
const BOSS_PHASE_1 := 1
const BOSS_PHASE_2 := 2
const BOSS_DEAD := 3
const BOSS_WITHDRAWN := 4

# --- Outcomes (finished(reason), brief 2.8) ---------------------------------------------------------
const OUTCOME_VICTORY := "victory"
const OUTCOME_WITHDRAWN := "withdrawn"
## The drill has no boss: it finishes "complete" once every rider is in the cool-down.
const OUTCOME_COMPLETE := "complete"
## v2 free roam: the session's time ran out (finished("time_up"), brief 2.8, 2.10).
const OUTCOME_TIME_UP := "time_up"

# --- Intents (brief 2.6; TankIntents) ---------------------------------------------------------------
const INTENT_LEVER := "lever"
const INTENT_AIM := "aim"
const INTENT_TARGET := "target"
const INTENT_TRAVERSE := "traverse"
const INTENT_FIRE := "fire"
const INTENT_LATCH := "latch"
const INTENT_OVER := "over"
## v2 free roam (brief 2.10): flip the travel direction (the diesel or Bulwark rider, 30 s
## cooldown; TankRoam). Refused outside free roam.
const INTENT_TURN := "turn"
const INTENT_KINDS: Array[String] = [
	INTENT_LEVER,
	INTENT_AIM,
	INTENT_TARGET,
	INTENT_TRAVERSE,
	INTENT_FIRE,
	INTENT_LATCH,
	INTENT_OVER,
	INTENT_TURN
]
## Intents that end a human's Autopilot fallback (brief 2.5); over never does. (v2: the Ram and its
## "ram" intent are gone, brief 2.4; a "ram" intent is junk to TankIntents.normalize.)
const DELIBERATE_KINDS: Array[String] = [
	INTENT_LEVER, INTENT_AIM, INTENT_TARGET, INTENT_TRAVERSE, INTENT_FIRE, INTENT_LATCH, INTENT_TURN
]

const VIA_ACTION := "action"
const VIA_SURGE := "surge"
const VIA_BUTTON := "button"
const VIA_AUTO := "auto"
const VIAS: Array[String] = [VIA_ACTION, VIA_SURGE, VIA_BUTTON, VIA_AUTO]

## Lever intent "to" words; "next" is `swap`, "left" / "right" step.
const LEVER_TO_NEXT := "next"
const LEVER_TO_LEFT := "left"
const LEVER_TO_RIGHT := "right"
const AIM_UP := 1
const AIM_DOWN := -1
const TARGET_NEXT := 1
const TARGET_PREV := -1


static func tank_for_crew(crew: int) -> String:
	return TANKS[clampi(crew, 1, TANKS.size()) - 1]


static func engine_code(engine: String) -> int:
	return int(ENGINE_CODES.get(engine, 0))


static func engine_of(code: int) -> String:
	for k: String in ENGINE_CODES:
		if int(ENGINE_CODES[k]) == code:
			return k
	return ""


static func enemy_code(type: String) -> int:
	return int(ENEMY_CODES.get(type, 0))


static func enemy_of(code: int) -> String:
	for k: String in ENEMY_CODES:
		if int(ENEMY_CODES[k]) == code:
			return k
	return ""


static func seg_code(seg: String) -> int:
	return int(SEG_CODES.get(seg, 0))


static func seg_of(code: int) -> String:
	for k: String in SEG_CODES:
		if int(SEG_CODES[k]) == code:
			return k
	return SEG_NONE


static func obstacle_code(type: String) -> int:
	return int(OBSTACLE_CODES.get(type, 0))


static func obstacle_of(code: int) -> String:
	for k: String in OBSTACLE_CODES:
		if int(OBSTACLE_CODES[k]) == code:
			return k
	return ""
