class_name SiegeIds
extends RefCounted
## Generator Siege's shared ids and integer codes (G0 contract, docs/games/siege.md 2.4-2.6).
## Every builder uses these names; snapshots and events carry the integer codes, intents the
## string ids. Contract: additive changes only, through the G0 architect / lead.

# --- Phase roles (PlanPhase.meta["role"], from content/siege/shifts.json; brief 2.3, 2.4) ------
const ROLE_NONE := ""
const ROLE_WARMUP_WAVE := "warmup_wave"
const ROLE_BUILD_BREAK := "build_break"
const ROLE_WAVE := "wave"
const ROLE_BREAK := "break"
## The platform's appended cool-down (no meta; SiegePlanBuilder.role_of() reports it).
const ROLE_COOLDOWN := "cooldown"
## Roles a shifts.json phase may carry (cooldown never: the PlanValidator appends it).
const SHIFT_ROLES: Array[String] = [ROLE_WARMUP_WAVE, ROLE_BUILD_BREAK, ROLE_WAVE, ROLE_BREAK]

# --- Wave mixes (shifts.json phase "mix"; waves.json "mix") ------------------------------------
const MIX_STANDARD := "standard"
const MIX_RAIDERS_HORSEMEN := "raiders_horsemen"

# --- Routing targets (SiegeRiderState.target, snapshot r[1], route event "to") ----------------
## The generator; pads are 1..PAD_COUNT.
const TARGET_GEN := 0
const PAD_COUNT := 8
## Normalized route intents (SiegeIntents.normalize "to"): a pad 1..8, TARGET_GEN, or these.
const ROUTE_NEXT := -1
const ROUTE_PREV := -2
const ROUTE_HOT := -3
## Wire form of the non-pad route targets ({"k": "route", "to": "gen" | 1..8 | "next" | ...}).
const ROUTE_WORDS := {"gen": TARGET_GEN, "next": ROUTE_NEXT, "prev": ROUTE_PREV, "hot": ROUTE_HOT}

# --- Roads (map order; SiegeEnemyState.road, snapshot e[2], z[0]) ------------------------------
const ROAD_WEST := 0
const ROAD_VALLEY := 1
const ROAD_EAST := 2
const ROAD_COUNT := 3
const ROAD_NAMES: Array[String] = ["west", "valley", "east"]

# --- Towers (towers.json keys; snapshot tw[1]) -------------------------------------------------
const TOWER_NONE := 0
const TOWER_BALLISTA := 1
const TOWER_SCORPION := 2
const TOWER_CALTROP := 3
## Index = code. towers.json is keyed by these names.
const TOWER_NAMES: Array[String] = ["", "ballista", "scorpion", "caltrop"]
const MAX_TOWER_LEVEL := 3

# --- Enemies (enemies.json keys; snapshot e[1]) ------------------------------------------------
const ENEMY_RAIDERS := 1
const ENEMY_SHIELD_WALL := 2
const ENEMY_HORSEMEN := 3
const ENEMY_RAM := 4
## Index = code. enemies.json is keyed by these names.
const ENEMY_NAMES: Array[String] = ["", "raiders", "shield_wall", "horsemen", "ram"]
## Order of a waves.json mix row: [raiders, shield_wall, horsemen] threat fractions.
const MIX_ORDER: Array[int] = [ENEMY_RAIDERS, ENEMY_SHIELD_WALL, ENEMY_HORSEMEN]

## SiegeEnemyState.st
const EN_WALK := 0
## A ram at the gate, battering it (3 HP/s) until destroyed or the wave ends.
const EN_BATTER := 1
## Wave end: retreating for 3 s, then gone without bounty or damage.
const EN_RETREAT := 2

# --- Perks (team, once each; snapshot pk[]) ----------------------------------------------------
const PERK_RESERVE := 1
const PERK_AQUEDUCT := 2
## Index = code.
const PERK_NAMES: Array[String] = ["", "reserve_flywheel", "aqueduct_drive"]

# --- Shop items (buy intent "item"; buy event "item"; brief 2.4 Shop) -------------------------
const ITEM_BUILD_BALLISTA := "build_ballista"
const ITEM_BUILD_SCORPION := "build_scorpion"
const ITEM_BUILD_CALTROP := "build_caltrop"
## The pad's next upgrade (1, then 2, then 3).
const ITEM_UPGRADE := "upgrade"
## The next generator level (1..3).
const ITEM_GENERATOR := "generator"
const ITEM_IRON_BANDS := "iron_bands"
const ITEM_REPAIR := "repair"
const ITEM_RESERVE := "reserve_flywheel"
const ITEM_AQUEDUCT := "aqueduct_drive"
## The shop panel's "Save denarii" entry: never sent as an intent.
const ITEM_SAVE := "save"
## Items a buy intent may carry.
const ITEMS: Array[String] = [
	ITEM_BUILD_BALLISTA,
	ITEM_BUILD_SCORPION,
	ITEM_BUILD_CALTROP,
	ITEM_UPGRADE,
	ITEM_GENERATOR,
	ITEM_IRON_BANDS,
	ITEM_REPAIR,
	ITEM_RESERVE,
	ITEM_AQUEDUCT,
]
## Items that need a "pad" (1..8).
const PAD_ITEMS: Array[String] = [
	ITEM_BUILD_BALLISTA, ITEM_BUILD_SCORPION, ITEM_BUILD_CALTROP, ITEM_UPGRADE
]
## build item -> tower code.
const BUILD_TOWER := {
	ITEM_BUILD_BALLISTA: TOWER_BALLISTA,
	ITEM_BUILD_SCORPION: TOWER_SCORPION,
	ITEM_BUILD_CALTROP: TOWER_CALTROP,
}

## Buy refusal reasons (buy event "why"; strings SIEGE_SHOP_REFUSED_<UPPER>).
const BUY_OK := ""
const BUY_CLOSED := "closed"
const BUY_FUNDS := "funds"
const BUY_PAD_TAKEN := "pad_taken"
const BUY_NO_TOWER := "no_tower"
const BUY_MAX_LEVEL := "max_level"
const BUY_LIMIT := "limit"
const BUY_GATE_FULL := "gate_full"
const BUY_REASONS: Array[String] = [
	BUY_CLOSED, BUY_FUNDS, BUY_PAD_TAKEN, BUY_NO_TOWER, BUY_MAX_LEVEL, BUY_LIMIT, BUY_GATE_FULL
]

# --- Intents (Telemetry.intents; brief 2.6) ----------------------------------------------------
const INTENT_ROUTE := "route"
const INTENT_BUY := "buy"
const INTENT_OVERDRIVE := "overdrive"
const INTENT_KINDS: Array[String] = [INTENT_ROUTE, INTENT_BUY, INTENT_OVERDRIVE]
## Where an intent came from (normalized "via"). VIA_AUTO: Autopilot or a PedalScanList
## auto-confirm; such intents never end a zero-input fallback and never start Overdrive.
const VIA_ACTION := "action"
const VIA_SURGE := "surge"
const VIA_BUTTON := "button"
const VIA_AUTO := "auto"
const VIAS: Array[String] = [VIA_ACTION, VIA_SURGE, VIA_BUTTON, VIA_AUTO]

# --- Events (send_event / apply_event "type"; brief 2.6) ---------------------------------------
const EV_WAVE_START := "wave_start"
const EV_WAVE_END := "wave_end"
const EV_ROADS := "roads"
const EV_RUSH := "rush"
const EV_KILL := "kill"
const EV_LEAK := "leak"
const EV_BREACH := "breach"
const EV_GATE_RESTORED := "gate_restored"
const EV_BUY := "buy"
const EV_ROUTE := "route"
const EV_OVERDRIVE := "overdrive"
## Additive to the brief's list (ADR 2026-10-22 "push event"): the ram push started.
const EV_PUSH := "push"
const EVENT_TYPES: Array[String] = [
	EV_WAVE_START,
	EV_WAVE_END,
	EV_ROADS,
	EV_RUSH,
	EV_KILL,
	EV_LEAK,
	EV_BREACH,
	EV_GATE_RESTORED,
	EV_BUY,
	EV_ROUTE,
	EV_OVERDRIVE,
	EV_PUSH,
]

# --- Overdrive (SiegeRiderState.od_state; overdrive event "st") -------------------------------
const OD_READY := 0
## Requested by the rules this tick; the module sends the directive and resolves it the same tick.
const OD_PENDING := 1
const OD_ACTIVE := 2
const OD_COOLDOWN := 3
## overdrive event "st"
const OD_EV_END := 0
const OD_EV_START := 1
const OD_EV_REFUSED := 2


static func tower_code(name: String) -> int:
	return maxi(TOWER_NAMES.find(name), 0)


static func enemy_code(name: String) -> int:
	return maxi(ENEMY_NAMES.find(name), 0)


static func perk_code(name: String) -> int:
	return maxi(PERK_NAMES.find(name), 0)


static func is_pad(target: int) -> bool:
	return target >= 1 and target <= PAD_COUNT
