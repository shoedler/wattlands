class_name TankIds
extends RefCounted
## Every id and wire code Diesel Domestiques uses (G0 contract; docs/games/tank.md). String ids
## are what content, intents and plan metas carry; the int codes are what snapshots and events
## carry (TankSnapshotSchema, TankEvents). Codes never change once shipped: add new ones at the end.

# --- Tank (v3, brief "v3: One tank, five seats"): every crew size rides the one tank ---------------
## v3: the reference landship rebuilt as pixel art (r6), for crews of 1 to MAX_CREW.
const TANK_LANDSHIP := "landship"
## Every tank id content may define (tanks.json tanks); v3 has one.
const TANKS: Array[String] = [TANK_LANDSHIP]
## Wire codes (TankHullState.code, the snapshot's tk column 0). Codes 1-4 were v2's Bulwark,
## Rampart, Citadel and Bastion (RETIRED_TANK_CODES): reserved, never sent again.
const TANK_CODES := {TANK_LANDSHIP: 5}
## v2's four tanks, retired in v3 (one tank for every crew size): their codes stay taken.
const RETIRED_TANK_CODES := {"bulwark": 1, "rampart": 2, "citadel": 3, "bastion": 4}
## The largest crew (game.json max_players); the smallest is 1.
const MAX_CREW := 4

# --- Engines (stations, v3: seats) -----------------------------------------------------------------
## Each engine is one seat of the tank (v3 seat table): its machine, its trainer mode and its job.
## Drive: the diesel (SIM, terrain grade); moves the tank, digs the berm in a gun line.
const ENGINE_DIESEL := "diesel"
## Gun: the dynamo (ERG, the bank pattern); traverses, elevates and fires the main gun.
const ENGINE_DYNAMO := "dynamo"
## Loader: the steam engine (SIM, boiler grade); reloads the main gun's 3-round ready rack.
const ENGINE_STEAM := "steam"
## Retired in v3 with the Bulwark's three-way gearbox: code 4 is reserved and never sent; the
## constant stays so older presentation code still compiles.
const ENGINE_BULWARK := "bulwark"
## Lights: the arc generator (ERG, the searchlight load); lights the searchlights.
const ENGINE_ARC := "arc"
## Secondaries (v3): the crank-driven twin belt feed (SIM flat) of the two bow guns, 2 rounds per
## pedal revolution (TankFeedState).
const ENGINE_FEED := "feed"
## v4: Repairs: the crank-driven rivet hammer and patch press on the upper deck (ERG 55-70 %).
const ENGINE_REPAIR := "repair"
## Every engine content and plans know (stations.json engines).
const ENGINES: Array[String] = [
	ENGINE_DIESEL, ENGINE_DYNAMO, ENGINE_STEAM, ENGINE_ARC, ENGINE_FEED, ENGINE_REPAIR
]
## Wire codes. 4 was the Bulwark's gearbox diesel: reserved.
const ENGINE_CODES := {
	ENGINE_DIESEL: 1,
	ENGINE_DYNAMO: 2,
	ENGINE_STEAM: 3,
	ENGINE_ARC: 5,
	ENGINE_FEED: 6,
	ENGINE_REPAIR: 7,
}
## Engine name keys (TANK_ENGINE_*), for station cards and results.
const ENGINE_LABELS := {
	ENGINE_DIESEL: "TANK_ENGINE_DIESEL",
	ENGINE_DYNAMO: "TANK_ENGINE_DYNAMO",
	ENGINE_STEAM: "TANK_ENGINE_STEAM",
	ENGINE_ARC: "TANK_ENGINE_ARC",
	ENGINE_FEED: "TANK_ENGINE_FEED",
	ENGINE_REPAIR: "TANK_ENGINE_REPAIR",
}
## The six seats (v4) in the seat row's order (Drive, Gun, Loader, Lights, Secondaries, Repairs; the
## HUD's seat panel, "next" / "prev" seat intents and the automatic seating's fill priority). The
## tank's rooms rear to front are tanks.json engines (diesel, steam, dynamo, arc, repair, feed).
const SEATS: Array[String] = [
	ENGINE_DIESEL, ENGINE_DYNAMO, ENGINE_STEAM, ENGINE_ARC, ENGINE_FEED, ENGINE_REPAIR
]
## Seat name keys (TANK_SEAT_*).
const SEAT_LABELS := {
	ENGINE_DIESEL: "TANK_SEAT_DRIVE",
	ENGINE_DYNAMO: "TANK_SEAT_GUN",
	ENGINE_STEAM: "TANK_SEAT_LOADER",
	ENGINE_ARC: "TANK_SEAT_LIGHTS",
	ENGINE_FEED: "TANK_SEAT_SECONDARIES",
	ENGINE_REPAIR: "TANK_SEAT_REPAIRS",
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

# --- Backdrops (v3, brief "World": the forest, mostly, and little bases) -----------------------------
## A mission segment's `backdrop` and a valley zone's (content) name what the view draws around the
## road; the view builder draws each. v3 keeps the zone ids above for the wire and the map, and gives
## every zone a forest variant or a base clearing (roam/valley.json zones.<id>.backdrop, label).
## The pine forest at night (the default).
const BACKDROP_FOREST := "forest"
## A darker, denser stand of firs.
const BACKDROP_FIRS := "forest_firs"
## A paler stand of birches among the pines.
const BACKDROP_BIRCHES := "forest_birches"
## A little base: a fenced clearing with a bunker, a lamp, crates and barrier stands (the depot,
## gun lines where it fits, free-roam strongpoints and the camp zones).
const BACKDROP_BASE := "base"
const BACKDROPS: Array[String] = [BACKDROP_FOREST, BACKDROP_FIRS, BACKDROP_BIRCHES, BACKDROP_BASE]

# --- Enemies (brief 2.4 table) ----------------------------------------------------------------------
const ENEMY_LIGHT := "light"
const ENEMY_MEDIUM := "medium"
const ENEMY_DESTROYER := "destroyer"
const ENEMY_DUGIN := "dugin"
const ENEMY_HEAVY := "heavy"
const ENEMY_RECON := "recon"
const ENEMY_TANKETTE := "tankette"
## v4: stand in the far panel (TankEnemyState.range_m).
const FAR_KINDS: Array[String] = [ENEMY_LIGHT, ENEMY_MEDIUM, ENEMY_DESTROYER, ENEMY_HEAVY]
## v4: burst from the bushes in the near panel (TankEnemyState.x_px); only the bow guns hit them.
const NEAR_KINDS: Array[String] = [ENEMY_RECON, ENEMY_TANKETTE]
const ENEMY_TYPES: Array[String] = [
	ENEMY_LIGHT,
	ENEMY_MEDIUM,
	ENEMY_DESTROYER,
	ENEMY_DUGIN,
	ENEMY_HEAVY,
	ENEMY_RECON,
	ENEMY_TANKETTE
]
## 6 is BOSS_CODE.
const ENEMY_CODES := {
	ENEMY_LIGHT: 1,
	ENEMY_MEDIUM: 2,
	ENEMY_DESTROYER: 3,
	ENEMY_DUGIN: 4,
	ENEMY_HEAVY: 5,
	ENEMY_RECON: 7,
	ENEMY_TANKETTE: 8,
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
## v4: a far enemy falling back in reverse (hull still toward us); removed past FAR_SPAWN_M with no credit.
const EM_RETIRE := 7
## v4: a near threat paused to fire (EM_MOVE is its dash, EM_LEAVE its flight).
const EM_PAUSE := 8

## Where an Advance encounter enters.
const FROM_FRONT := "front"
const FROM_REAR := "rear"

# --- Difficulty (v4, game.json option "difficulty"; TankDifficulty) ---------------------------------
const DIFF_AUTO := "auto"
const DIFF_EASY := "easy"
const DIFF_NORMAL := "normal"
const DIFF_HARD := "hard"
const DIFFICULTIES: Array[String] = [DIFF_EASY, DIFF_NORMAL, DIFF_HARD]

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
## Reserved (v3 retired the Bulwark's gearbox lever): "lever" is junk to TankIntents.normalize.
const INTENT_LEVER := "lever"
const INTENT_AIM := "aim"
const INTENT_TARGET := "target"
const INTENT_TRAVERSE := "traverse"
const INTENT_FIRE := "fire"
const INTENT_LATCH := "latch"
const INTENT_OVER := "over"
## v2 free roam (brief 2.10): flip the travel direction (the Drive rider, 30 s cooldown;
## TankRoam). Refused outside free roam.
const INTENT_TURN := "turn"
## v3 (brief "Seat choice and switching"): move to another seat, {to: an engine id, or "next" /
## "prev" in SEATS order}; deliberate. Every seat may send it; the move lands at once on an empty
## seat (0.3.1: no seat lock; refused on reserve and in the cool-down) and the trainer follows.
const INTENT_SEAT := "seat"
const INTENT_KINDS: Array[String] = [
	INTENT_AIM,
	INTENT_TARGET,
	INTENT_TRAVERSE,
	INTENT_FIRE,
	INTENT_LATCH,
	INTENT_OVER,
	INTENT_TURN,
	INTENT_SEAT
]
## Intents that end a human's Autopilot fallback (brief 2.5; v3: and its automatic seating); over
## never does. (v2: the Ram and its "ram" intent are gone, brief 2.4; v3: so is "lever".)
const DELIBERATE_KINDS: Array[String] = [
	INTENT_AIM, INTENT_TARGET, INTENT_TRAVERSE, INTENT_FIRE, INTENT_LATCH, INTENT_TURN, INTENT_SEAT
]

const VIA_ACTION := "action"
const VIA_SURGE := "surge"
const VIA_BUTTON := "button"
const VIA_AUTO := "auto"
const VIAS: Array[String] = [VIA_ACTION, VIA_SURGE, VIA_BUTTON, VIA_AUTO]

## Seat intent "to" words that step through SEATS (wrapping) instead of naming a seat.
const SEAT_TO_NEXT := "next"
const SEAT_TO_PREV := "prev"
const AIM_UP := 1
const AIM_DOWN := -1
const TARGET_NEXT := 1
const TARGET_PREV := -1


## The tank a crew of `crew` rides: the landship for every crew size (v3).
static func tank_for_crew(_crew: int) -> String:
	return TANK_LANDSHIP


## The seat `step` places from `engine` in SEATS order, wrapping ("next" +1, "prev" -1); `engine`
## itself for step 0, SEATS[0] for an unknown engine.
static func seat_step(engine: String, step: int) -> String:
	var at := SEATS.find(engine)
	if at < 0:
		return SEATS[0]
	return SEATS[posmod(at + step, SEATS.size())]


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


## v4: true for a near kind's code (recon, tankette).
static func is_near_code(code: int) -> bool:
	return code == ENEMY_CODES[ENEMY_RECON] or code == ENEMY_CODES[ENEMY_TANKETTE]


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
