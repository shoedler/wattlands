class_name TankState
extends TankRecord
## The whole Diesel Domestiques game state (G0 contract). The rules (TankRules.step) mutate it on
## the host; the director (TankDirector) only reads it; the module encodes it into snapshots
## (TankSnapshot) and clients rebuild the [snap] part from them; the view and HUD only read it.
## Deterministic: every random draw goes through `rng` (ctx.rng on the host), and every list keeps
## a fixed order (riders by slot, stations rear to front, enemies, shells and obstacles by id).
##
## Fields marked [snap] travel in the 10 Hz snapshot (TankSnapshotSchema); everything else is
## host-only bookkeeping (a client keeps its last value or what its events told it).

## Validated content (not serialized).
var content: TankContent = null
## The session RNG (ctx.rng on the host; null on clients, which never simulate).
var rng: RandomNumberGenerator = null

## The mission (content id); v3: every crew size rides the one tank (TankIds.tank_for_crew).
var mission: String = ""
var crew: int = 1
## [snap] Game tick of the latest step.
var tick: int = 0
## Game seconds (tick x 0.05).
var t: float = 0.0
## Nothing has power: every rider is AFK (brief 2.2: bank and pressure freeze, no gun fires).
var all_afk: bool = false
## The mission's result once the boss (the last plan phase) ended: TankIds.OUTCOME_*; "" before.
var outcome: String = ""
## The next id for enemies, shells and obstacles (never reused).
var next_id: int = 1
## v4: TankIds.DIFF_EASY/NORMAL/HARD, resolved at the session start on every peer (from ctx.options; not
## in the snapshot).
var difficulty: String = TankIds.DIFF_NORMAL

var seg: TankSegmentState = TankSegmentState.new()
var hull: TankHullState = TankHullState.new()
## One per slot, slot order.
var riders: Array[TankRiderState] = []
## The tank's rooms rear to front (tanks.json engines).
var stations: Array[TankStationState] = []
var enemies: Array[TankEnemyState] = []
var shells: Array[TankShellState] = []
var obstacles: Array[TankObstacleState] = []
var gun_line: TankGunLineState = TankGunLineState.new()
var boss: TankBossState = TankBossState.new()
var score: TankScoreState = TankScoreState.new()
## (v2) Free roam (brief 2.10): inactive in missions.
var roam: TankRoamState = TankRoamState.new()
## (v2) The free-roam valley built from roam.map_seed (TankRoam.prepare on the host, TankRoam.ensure_map on
## a client once a snapshot brought the seed); null in missions. Not serialized.
var roam_map: TankRoamMap = null


## A fresh state at the session start: the tank with its rooms, every rider on its starting seat
## (stations.json start_engines by slot; v3: a crew of n takes the first n, so the solo rider sits on
## Drive and every seat past the crew is empty, slot -1), the hull at full HP, the bank full, no
## enemies. `slots` in slot order (ctx.players); `rng` is ctx.rng on the host, null on clients.
static func create(
	p_content: TankContent,
	slots: Array[PlayerSlot],
	p_mission: String,
	p_rng: RandomNumberGenerator
) -> TankState:
	var s := TankState.new()
	s.content = p_content
	s.rng = p_rng
	s.mission = p_mission
	s.crew = clampi(slots.size(), 1, TankIds.MAX_CREW)
	var tank := TankIds.tank_for_crew(s.crew)
	var def := p_content.tank_def(tank)
	s.hull.tank = tank
	s.hull.code = int(def.get("code", 1))
	var size: Array = def.get("hull_px", [296, 65])
	s.hull.hull_w = int(size[0])
	s.hull.hull_h = int(size[1])
	s.hull.hp_max = p_content.num("tanks", "hull.hp", 100.0)
	s.hull.hp = s.hull.hp_max
	var starts := p_content.start_engines(tank)
	for p in slots:
		var r := TankRiderState.new()
		r.slot = p.slot_index
		r.peer = p.peer_id
		r.is_bot = p.is_bot
		r.autopilot = p.autopilot or p.is_bot
		r.fallback = true
		r.ftp = p.ftp
		r.ftp_verified = p.ftp_verified
		r.haptics_on = p.haptics_on
		r.rider_mass_kg = p.rider_mass_kg
		r.engine = starts[p.slot_index] if p.slot_index < starts.size() else ""
		s.riders.append(r)
	for engine: String in p_content.engines_of(tank):
		var st := TankStationState.make(engine)
		for r in s.riders:
			if r.engine == engine:
				st.slot = r.slot
				st.peer = r.peer
		if st is TankDynamoState:
			(st as TankDynamoState).bank = p_content.num("tanks", "dynamo.bank_max", 100.0)
		s.stations.append(st)
	return s


# --- Lookups -----------------------------------------------------------------------------------------


## The rider of `peer`, or null.
func rider(peer: int) -> TankRiderState:
	for r in riders:
		if r.peer == peer:
			return r
	return null


## The rider in slot index `slot`, or null.
func rider_at(slot: int) -> TankRiderState:
	for r in riders:
		if r.slot == slot:
			return r
	return null


## The room (v3: seat) of `engine`, or null.
func station(engine: String) -> TankStationState:
	for st in stations:
		if st.engine == engine:
			return st
	return null


## The room the rider in `slot` works this segment, or null (v3: null for slot -1, an empty seat).
func station_of(slot: int) -> TankStationState:
	if slot < 0:
		return null
	for st in stations:
		if st.slot == slot:
			return st
	return null


func enemy(id: int) -> TankEnemyState:
	for e in enemies:
		if e.id == id:
			return e
	return null


func obstacle(id: int) -> TankObstacleState:
	for o in obstacles:
		if o.id == id:
			return o
	return null


## A fresh id for an enemy, shell or obstacle: always > 0, so never a boss part's (negative) id.
func take_id() -> int:
	next_id += 1
	return next_id - 1


## The camera's world x: the hull's rear sits at screen x TankConst.REAR_SCREEN_X.
func camera_x() -> float:
	return hull.x_px - TankConst.REAR_SCREEN_X


func in_cooldown() -> bool:
	return seg.seg == TankIds.SEG_COOLDOWN


# --- Fixtures (TankRecord with the nested records) ---------------------------------------------------


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["seg"] = seg.to_dict()
	d["hull"] = hull.to_dict()
	d["gun_line"] = gun_line.to_dict()
	d["boss"] = boss.to_dict()
	d["score"] = score.to_dict()
	d["roam"] = roam.to_dict()
	d["riders"] = _dicts(riders)
	d["stations"] = _dicts(stations)
	d["enemies"] = _dicts(enemies)
	d["shells"] = _dicts(shells)
	d["obstacles"] = _dicts(obstacles)
	return d


func load_dict(d: Dictionary) -> TankRecord:
	super.load_dict(d)
	seg.load_dict(d.get("seg", {}))
	hull.load_dict(d.get("hull", {}))
	gun_line.load_dict(d.get("gun_line", {}))
	boss.load_dict(d.get("boss", {}))
	score.load_dict(d.get("score", {}))
	roam.load_dict(d.get("roam", {}))
	riders.clear()
	for x: Variant in d.get("riders", []):
		riders.append(TankRiderState.new().load_dict(x) as TankRiderState)
	stations.clear()
	for x: Variant in d.get("stations", []):
		stations.append(
			TankStationState.make(str(x.get("engine", ""))).load_dict(x) as TankStationState
		)
	enemies.clear()
	for x: Variant in d.get("enemies", []):
		enemies.append(TankEnemyState.new().load_dict(x) as TankEnemyState)
	shells.clear()
	for x: Variant in d.get("shells", []):
		shells.append(TankShellState.new().load_dict(x) as TankShellState)
	obstacles.clear()
	for x: Variant in d.get("obstacles", []):
		obstacles.append(TankObstacleState.new().load_dict(x) as TankObstacleState)
	return self


static func _dicts(records: Array) -> Array:
	var out: Array = []
	for r: TankRecord in records:
		out.append(r.to_dict())
	return out
