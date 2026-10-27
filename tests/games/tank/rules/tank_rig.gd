class_name TankRulesRig
extends RefCounted
## A tiny driver for the pure Tank rules in tests: real content, real plans, a state, a tick counter
## and a segment clock. It builds TankInputs by hand (no platform runtime): the group's phase is
## mission segment `seg_index`, `seg_t` seconds in; every rider rides `sim_pct` of FTP in SIM phases
## (the erg mock's SIM rule) and its planned target in ERG phases, at 90 rpm, with P_eff 250 W at
## FTP. `power_w` / `p_eff` / `cadence` override a peer; `intents` go in on the next step only.
## With `auto_phase` the clock ends open phases like the platform does (the objective done and
## min_s passed, else max_s) and fixed ones at their duration, so a whole session can be played.

const OPEN_SEGS := [TankIds.SEG_ADVANCE, TankIds.SEG_GUN_LINE, TankIds.SEG_BOSS]

var content: TankContent
var mission_id: String = "ashfall_road"
var slots: Array[PlayerSlot] = []
var plans: Dictionary = {}
var state: TankState
var tick: int = 0
var events: Array[Dictionary] = []
## The group's mission segment (== phase index) and seconds into it; seg_index past the end is
## the cool-down.
var seg_index: int = 0
var seg_t: float = 0.0
var plan_t: float = 0.0
var prev_ended_by: String = ""
var auto_phase: bool = false
var rotation: bool = true
var sim_pct: float = 90.0
var power_w: Dictionary = {}
var p_eff: Dictionary = {}
var cadence: Dictionary = {}
var target_pct: Dictionary = {}
var intents: Dictionary = {}
var rescue: Dictionary = {}
var afk: Dictionary = {}
var connected: Dictionary = {}
var mass_kg: float = 75.0
## How closely the mock riders follow their targets (the erg mock's compliance): ERG riders ride
## `compliance` x the applied target, SIM riders `compliance` x `sim_pct`.
var compliance: float = 1.0
## The dynamo's ERG target follows its bank like the director's pattern 1 does:
## 55 + 45 x (1 - bank / 100), clamped to the phase's range (instantly here, not in sub-steps).
var bank_director: bool = false
## The breech never opens (nothing loads, nothing fires) and the Bulwark's lever stays where it is
## (Drive): the gun is out of the picture (tests of the drive and the Ram).
var no_fire: bool = false
## Seconds each segment ran when auto_phase moved on (index -> seconds).
var seg_len: Dictionary = {}
var ended_by: Dictionary = {}
## The number of events each step raised, in order (event-rate checks).
var event_counts: Array[int] = []


func _init(
	crew: int = 1,
	p_mission: String = "ashfall_road",
	p_rotation: bool = true,
	rng_seed: int = 7,
	patch: Callable = Callable()
) -> void:
	mission_id = p_mission
	rotation = p_rotation
	var files := TankContent.read_files(p_mission)
	if patch.is_valid():
		patch.call(files)
	content = TankContent.from_dicts(files, p_mission)
	slots = TankFixtures.slots(crew)
	plans = TankPlanBuilder.build_all(content, slots, rotation)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	state = TankRules.new_state(
		content, slots, p_mission, rotation and content.mission_rotates(), rng
	)


func segs() -> Array:
	return content.segments()


## Plan time (s) at which segment `index` starts (nominal lengths).
func seg_start(index: int) -> float:
	var t := 0.0
	for i in mini(index, segs().size()):
		t += float(content.segment(i).get("duration_s", 0.0))
	return t


## Jumps to `into_s` seconds into segment `index` (plan time follows) and steps once, so the
## state enters the segment. Pass `prev` as the previous phase's ended_by ("max_s": an overrun).
func enter(index: int, into_s: float = 0.0, prev: String = Wl.ENDED_DURATION) -> void:
	seg_index = index
	seg_t = into_s
	plan_t = seg_start(index) + into_s
	prev_ended_by = prev
	step()


func in_cooldown() -> bool:
	return seg_index >= segs().size()


## Steps `seconds` of game time (at least one tick); returns the events raised meanwhile.
func run(seconds: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for _i in maxi(roundi(seconds / Wl.SIM_DT), 1):
		out.append_array(step())
	return out


## Steps until `cond` is true or `limit_s` seconds passed; returns the seconds stepped.
func run_until(cond: Callable, limit_s: float = 600.0) -> float:
	var n := roundi(limit_s / Wl.SIM_DT)
	for i in n:
		if cond.call():
			return i * Wl.SIM_DT
		step()
	return limit_s


func step() -> Array[Dictionary]:
	if no_fire:
		state.hull.breech_s = 1.0e6
		var g := gearbox()
		if g != null:
			g.auto = false
			g.suspend_s = 1.0e9
	var out := TankRules.step(state, inputs(), Wl.SIM_DT)
	tick += 1
	seg_t += Wl.SIM_DT
	plan_t += Wl.SIM_DT
	intents = {}
	event_counts.append(out.size())
	events.append_array(out)
	if auto_phase:
		_advance_phase()
	return out


func _advance_phase() -> void:
	if in_cooldown():
		return
	var s := content.segment(seg_index)
	var open := OPEN_SEGS.has(str(s.get("type", "")))
	var by := ""
	if open:
		if state.seg.objective_done and seg_t + 1e-6 >= float(s.get("min_s", 0.0)):
			by = Wl.ENDED_END_PHASE
		elif seg_t + 1e-6 >= float(s.get("max_s", 0.0)):
			by = Wl.ENDED_MAX_S
	elif seg_t + 1e-6 >= float(s.get("duration_s", 0.0)):
		by = Wl.ENDED_DURATION
	if by != "":
		seg_len[seg_index] = seg_t
		ended_by[seg_index] = by
		seg_index += 1
		seg_t = 0.0
		prev_ended_by = by


## The group's phase info for the current clock.
func phase_info() -> TankPhaseInfo:
	var p := TankPhaseInfo.new()
	p.index = seg_index
	p.elapsed_s = seg_t
	p.plan_elapsed_s = plan_t
	p.prev_ended_by = prev_ended_by
	if in_cooldown():
		p.kind = Wl.COOLDOWN
		p.mode = Wl.ERG
		p.seg = TankIds.SEG_COOLDOWN
		p.segment = -1
		p.duration_s = 180.0
		return p
	var s := content.segment(seg_index)
	var ph: PlanPhase = (plans[slots[0].peer_id] as EffortPlan).phase(seg_index)
	p.kind = ph.kind
	p.mode = ph.mode
	p.seg = str(s["type"])
	p.stage = int(s["stage"])
	p.segment = seg_index
	p.duration_s = float(s["duration_s"])
	p.open_ended = s.has("min_s")
	p.min_s = float(s.get("min_s", 0.0))
	p.max_s = float(s.get("max_s", 0.0))
	p.remaining_s = maxf(p.duration_s - seg_t, 0.0)
	return p


func inputs() -> TankInputs:
	var inp := TankInputs.new()
	inp.tick = tick
	inp.t = tick * Wl.SIM_DT
	inp.phase = phase_info()
	for p in slots:
		inp.riders.append(_rider_input(p))
	return inp


func _rider_input(p: PlayerSlot) -> TankRiderInput:
	var ri := TankRiderInput.new()
	ri.peer = p.peer_id
	ri.slot = p.slot_index
	ri.ftp = p.ftp
	ri.ftp_verified = p.ftp_verified
	ri.rider_mass_kg = mass_kg
	ri.autopilot = p.autopilot
	ri.plan_elapsed_s = plan_t
	ri.phase_index = seg_index
	var plan: EffortPlan = plans[p.peer_id]
	if in_cooldown():
		ri.phase_kind = Wl.COOLDOWN
		ri.phase_mode = Wl.ERG
		ri.mode = Wl.ERG
		ri.applied_target_w = roundf(0.5 * p.ftp)
		ri.engine = ""
	else:
		var ph := plan.phase(seg_index)
		ri.phase_kind = ph.kind
		ri.phase_mode = ph.mode
		ri.engine = str(ph.meta.get("engine", ""))
		ri.grade_source = ph.grade_source if ph.mode == Wl.SIM else ""
		ri.mode = ph.mode
		if ph.mode == Wl.ERG:
			var pct: float = float(target_pct.get(p.peer_id, ph.planned_pct_at(seg_t)))
			if bank_director and ri.engine == TankIds.ENGINE_DYNAMO and ph.range_pct.size() == 2:
				pct = TankDirector.bank_target_pct(content, dynamo().bank, ph)
			ri.applied_target_w = roundf(pct / 100.0 * p.ftp)
			ri.planned_pct = ph.planned_pct_at(seg_t)
	if ri.mode == Wl.ERG:
		ri.power_w = float(power_w.get(p.peer_id, ri.applied_target_w * compliance))
	else:
		ri.power_w = float(power_w.get(p.peer_id, sim_pct / 100.0 * p.ftp * compliance))
	ri.p_eff_w = float(p_eff.get(p.peer_id, ri.power_w * 250.0 / p.ftp))
	ri.cadence_rpm = float(cadence.get(p.peer_id, 90.0))
	ri.ftp_pct = ri.power_w / p.ftp * 100.0
	ri.connected = bool(connected.get(p.peer_id, true))
	ri.rescue = bool(rescue.get(p.peer_id, false))
	ri.afk = bool(afk.get(p.peer_id, false)) or not ri.connected
	for n: Variant in intents.get(p.peer_id, []):
		ri.intents.append(n)
	return ri


# --- Helpers ------------------------------------------------------------------------------------


## The events of `type` raised so far (or in `list`).
func of_type(type: String, list: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events if list.is_empty() else list:
		if e["type"] == type:
			out.append(e)
	return out


## Sends one raw intent for `peer` on the next step (normalized like the module does).
func send(peer: int, raw: Dictionary) -> void:
	var list: Array = intents.get(peer, [])
	list.append(TankIntents.normalize(raw))
	intents[peer] = list


func rider(peer: int = 1) -> TankRiderState:
	return state.rider(peer)


func hull() -> TankHullState:
	return state.hull


func diesel() -> TankDieselState:
	return TankHullRules.driver(state)


func dynamo() -> TankDynamoState:
	return state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState


func steam() -> TankSteamState:
	return state.station(TankIds.ENGINE_STEAM) as TankSteamState


func gearbox() -> TankGearboxState:
	return state.station(TankIds.ENGINE_BULWARK) as TankGearboxState


## The peer working `engine` right now.
func peer_of(engine: String) -> int:
	var st := state.station(engine)
	return st.peer if st != null else 0


## An enemy placed at distance `dist` from the hull's nearer end (a held position), full HP.
func spawn(type: String, side: int = 1, dist: float = 200.0, fixed: bool = false) -> TankEnemyState:
	var aux := TankAux.of(state)
	var e := TankEnemies.spawn(state, aux, type, side, dist, fixed, false, -1)
	e.mode = TankIds.EM_HOLD
	e.hold_px = TankEnemies.clamp_hold(state, e.w, side, dist)
	TankEnemies.place(state, aux, e, e.hold_px)
	return e


## Loads a shell of `type` into the breech.
func load_shell(type: int = TankIds.SHELL_HEAVY) -> void:
	state.hull.loaded = type
	state.hull.breech_s = 0.0


## Plays the whole mission with auto_phase until every rider is in the cool-down (and `extra_s`
## more), at most `limit_s`. Returns the seconds played.
func play(extra_s: float = 1.0, limit_s: float = 3000.0) -> float:
	auto_phase = true
	var n := roundi(limit_s / Wl.SIM_DT)
	for i in n:
		if in_cooldown():
			run(extra_s)
			return (i + 1) * Wl.SIM_DT
		step()
	return limit_s
