class_name SiegeIds
extends RefCounted
## Castellum Rotae's shared ids and integer codes (docs/games/siege.md 2.4-2.6; the state
## interface is contracts/STATE_V2.md). Snapshots and events carry the integer codes, intents
## the string ids. Additive changes only.

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
## Spearmen and chariots only (the drill, rushes; the id is kept from v0.1.0).
const MIX_RAIDERS_HORSEMEN := "raiders_horsemen"

# --- Stations (rider targets; SiegeRiderState.target, snapshot r[1] and st[0]) ----------------
const STATION_MINE := 0
## v0.1.0's name for the economy target, kept for callers that still say "gen".
const TARGET_GEN := STATION_MINE
const STATION_BALLISTA := 1
const STATION_ONAGER := 2
const STATION_ARROWS := 3
const STATION_TAR := 4
const STATION_COUNT := 5
## Index = id. stations.json is keyed by these names.
const STATION_NAMES: Array[String] = ["mine", "ballista", "onager", "arrows", "tar"]
## The stations that shoot (simulated projectiles).
const WEAPONS: Array[int] = [STATION_BALLISTA, STATION_ONAGER, STATION_ARROWS]
## Stations with upgrades bought per station (the mine has its own levels).
const UPGRADABLE: Array[int] = [STATION_BALLISTA, STATION_ONAGER, STATION_ARROWS, STATION_TAR]
const MAX_LEVEL := 3

## Normalized route intents (SiegeIntents.normalize "to"): a station 0..4, or these.
const ROUTE_NEXT := -1
const ROUTE_PREV := -2
const ROUTE_HOT := -3
## Wire words of the route targets ({"k": "route", "to": "mine" | 0..4 | "next" | ...}); "gen"
## is accepted as "mine".
const ROUTE_WORDS := {
	"mine": STATION_MINE,
	"gen": STATION_MINE,
	"next": ROUTE_NEXT,
	"prev": ROUTE_PREV,
	"hot": ROUTE_HOT,
}

# --- Pads (unmanned, crew-wound; SiegePadState, snapshot pd[]) -------------------------------
const PAD_COUNT := 4
const PAD_NONE := 0
const PAD_SCORPION := 1
## P1 (not built in v2.0).
const PAD_CALTROP := 2
## Index = type code. stations.json "pads" is keyed by these names.
const PAD_NAMES: Array[String] = ["", "scorpion", "caltrop"]
## The pads a docked siege tower's boarders stop (brief 2.4: pads 1 and 2, on the gate towers).
const BOARDED_PADS: Array[int] = [1, 2]

# --- Enemies (enemies.json keys; snapshot e[1]) ------------------------------------------------
const ENEMY_SPEAR := 1
const ENEMY_SHIELD := 2
const ENEMY_CHARIOT := 3
const ENEMY_RAM := 4
const ENEMY_TOWER := 5
## Index = code. enemies.json is keyed by these names.
const ENEMY_NAMES: Array[String] = ["", "spear", "shield", "chariot", "ram", "tower"]
## Order of a waves.json mix row: [spear, shield, chariot] threat fractions.
const MIX_ORDER: Array[int] = [ENEMY_SPEAR, ENEMY_SHIELD, ENEMY_CHARIOT]

## SiegeEnemyState.st
const EN_WALK := 0
## A ram at the gate, battering it until destroyed or the wave ends.
const EN_BATTER := 1
## Wave end: retreating for 3 s, then gone without bounty or damage.
const EN_RETREAT := 2
## A siege tower docked at the moat edge, landing boarders on the wall.
const EN_DOCKED := 3

# --- Shots (shot event "kind" and "src") -------------------------------------------------------
const SHOT_BOLT := 0
const SHOT_STONE := 1
const SHOT_ARROW := 2
const SHOT_SCORPION := 3
## A shot's `src` is a station 1..3, or SRC_PAD + pad (11..14).
const SRC_PAD := 10

# --- Perks (team, once each; snapshot pk[]) ----------------------------------------------------
const PERK_RESERVE := 1
const PERK_AQUEDUCT := 2
const PERK_CAULDRON := 3
## Index = code.
const PERK_NAMES: Array[String] = ["", "reserve_flywheel", "aqueduct_drive", "spare_cauldron"]

# --- Shop items (buy intent "item"; buy event "item"; brief 2.4 Shop) -------------------------
## The station's next upgrade (1, 2, 3); needs "station" 1..4.
const ITEM_UPGRADE := "upgrade"
## The next mine level (1..3).
const ITEM_MINE := "mine"
## A Scorpion on an empty pad; needs "pad" 1..4.
const ITEM_SCORPION := "scorpion"
## The pad's next upgrade (1, 2, 3); needs "pad".
const ITEM_PAD_UPGRADE := "pad_upgrade"
const ITEM_IRON_BANDS := "iron_bands"
const ITEM_REPAIR := "repair"
const ITEM_RESERVE := "reserve_flywheel"
const ITEM_AQUEDUCT := "aqueduct_drive"
const ITEM_CAULDRON := "spare_cauldron"
## The shop panel's "Save gold" entry: never sent as an intent.
const ITEM_SAVE := "save"
## Items a buy intent may carry.
const ITEMS: Array[String] = [
	ITEM_UPGRADE,
	ITEM_MINE,
	ITEM_SCORPION,
	ITEM_PAD_UPGRADE,
	ITEM_IRON_BANDS,
	ITEM_REPAIR,
	ITEM_RESERVE,
	ITEM_AQUEDUCT,
	ITEM_CAULDRON,
]
## Items that need a "station" (1..4).
const STATION_ITEMS: Array[String] = [ITEM_UPGRADE]
## Items that need a "pad" (1..4).
const PAD_ITEMS: Array[String] = [ITEM_SCORPION, ITEM_PAD_UPGRADE]
## perk item -> perk code.
const PERK_ITEMS := {
	ITEM_RESERVE: PERK_RESERVE,
	ITEM_AQUEDUCT: PERK_AQUEDUCT,
	ITEM_CAULDRON: PERK_CAULDRON,
}

## Buy refusal reasons (buy event "why"; strings SIEGE_SHOP_REFUSED_<UPPER>).
const BUY_OK := ""
const BUY_CLOSED := "closed"
const BUY_FUNDS := "funds"
const BUY_PAD_TAKEN := "pad_taken"
const BUY_NO_PAD := "no_pad"
const BUY_NO_STATION := "no_station"
const BUY_MAX_LEVEL := "max_level"
const BUY_LIMIT := "limit"
const BUY_GATE_FULL := "gate_full"
const BUY_REASONS: Array[String] = [
	BUY_CLOSED,
	BUY_FUNDS,
	BUY_PAD_TAKEN,
	BUY_NO_PAD,
	BUY_NO_STATION,
	BUY_MAX_LEVEL,
	BUY_LIMIT,
	BUY_GATE_FULL,
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
const EV_RUSH := "rush"
const EV_PUSH := "push"
const EV_DOCK := "dock"
## A ram reached the gate and starts battering (ADR "reach event").
const EV_REACH := "reach"
const EV_SHOT := "shot"
const EV_KILL := "kill"
const EV_LEAK := "leak"
const EV_BREACH := "breach"
const EV_GATE_RESTORED := "gate_restored"
const EV_BUY := "buy"
const EV_ROUTE := "route"
const EV_OVERDRIVE := "overdrive"
const EVENT_TYPES: Array[String] = [
	EV_WAVE_START,
	EV_WAVE_END,
	EV_RUSH,
	EV_PUSH,
	EV_DOCK,
	EV_REACH,
	EV_SHOT,
	EV_KILL,
	EV_LEAK,
	EV_BREACH,
	EV_GATE_RESTORED,
	EV_BUY,
	EV_ROUTE,
	EV_OVERDRIVE,
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


static func enemy_code(name: String) -> int:
	return maxi(ENEMY_NAMES.find(name), 0)


static func pad_code(name: String) -> int:
	return maxi(PAD_NAMES.find(name), 0)


static func is_station(target: int) -> bool:
	return target >= 0 and target < STATION_COUNT


static func is_weapon(station: int) -> bool:
	return WEAPONS.has(station)


static func is_pad(pad: int) -> bool:
	return pad >= 1 and pad <= PAD_COUNT


static func is_engine(type: int) -> bool:
	return type == ENEMY_RAM or type == ENEMY_TOWER


## The shot kind a weapon station fires.
static func shot_kind(station: int) -> int:
	match station:
		STATION_BALLISTA:
			return SHOT_BOLT
		STATION_ONAGER:
			return SHOT_STONE
		STATION_ARROWS:
			return SHOT_ARROW
	return SHOT_SCORPION
