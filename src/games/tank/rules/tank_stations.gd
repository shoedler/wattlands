class_name TankStations
extends RefCounted
## The seats' machines (brief 2.4 Dynamo, Steam, Arc generator; v3 brief "One tank, five seats",
## "Combat changes"; owner: rules): the Gun's capacitor bank (dynamo), the Loader's ready rack
## (steam: the boiler fills it, Overpressure, the light latch) and the Lights (arc generator:
## searchlights, stall, the searchlight load). Drive is TankDrive, the main gun and its chambering
## TankGun, the Secondaries' bow guns TankBow. Every energy is the seat's P_eff (reserve 60 W for an
## AFK rider, 0 when everyone is AFK); an empty seat (slot -1) has none and does nothing: the bank
## holds, no shell is loaded, the searchlights are dark. Pure: no random draws; time only through
## `dt`. v3 retired the Bulwark's gearbox and the gunner's hoist.


static func step(
	state: TankState, inputs: TankInputs, dt: float, events: Array[Dictionary]
) -> void:
	var aux := TankAux.of(state)
	for st in state.stations:
		var ri: TankRiderInput = inputs.rider(st.peer) if st.slot >= 0 else null
		if st is TankDynamoState:
			_dynamo(state, aux, st as TankDynamoState, ri, dt)
		elif st is TankSteamState:
			_steam(state, aux, st as TankSteamState, ri, dt, events)
		elif st is TankArcState:
			_arc(state, aux, st as TankArcState, ri)


# --- Helpers -------------------------------------------------------------------------------------


## The station of the gunner: the dynamo (the Gun seat), else null.
static func gunner(state: TankState) -> TankStationState:
	return state.station(TankIds.ENGINE_DYNAMO)


## The Loader's station (the steam engine), or null.
static func loader(state: TankState) -> TankSteamState:
	return state.station(TankIds.ENGINE_STEAM) as TankSteamState


## Puts `n` heavy shells in the ready rack (the session start; at most TankConst.RACK_MAX).
static func fill_rack(state: TankState, n: int) -> void:
	var st := loader(state)
	if st == null:
		return
	var aux := TankAux.of(state)
	aux.rack_types.clear()
	for _i in clampi(n, 0, TankConst.RACK_MAX):
		aux.rack_types.append(TankIds.SHELL_HEAVY)
	st.rack = aux.rack_types.size()
	st.loaded = st.rack >= TankConst.RACK_MAX


## Takes the oldest shell out of the ready rack (TankIds.SHELL_NONE when it is empty).
static func take_from_rack(state: TankState) -> int:
	var st := loader(state)
	var aux := TankAux.of(state)
	if st == null or aux.rack_types.is_empty():
		return TankIds.SHELL_NONE
	var shell: int = aux.rack_types.pop_front()
	st.rack = aux.rack_types.size()
	return shell


## Takes `units` out of the dynamo's bank (never below 0). A tank without a dynamo has no bank.
static func drain(state: TankState, units: float) -> void:
	var d := state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	if d != null:
		d.bank = maxf(d.bank - units, 0.0)


## The dynamo's bank scaled to 0..1 at `full_at` units (1 for a tank without a dynamo).
static func bank_frac(state: TankState) -> float:
	var d := state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	if d == null:
		return 1.0
	return clampf(d.bank / state.content.num("tanks", "dynamo.full_at", 50.0), 0.0, 1.0)


## A value that runs from `pair[0]` at an empty bank to `pair[1]` at full_at units and more.
static func by_bank(state: TankState, pair: Array) -> float:
	return lerpf(float(pair[0]), float(pair[1]), bank_frac(state))


## True while a present rider is in a rescue hold. A rider on reserve (AFK or dropped) is not: the
## station runs on reserve under Autopilot and keeps its plan (brief 2.2), whatever rescue flag
## was left over from before the rider stopped pedaling.
static func in_rescue(ri: TankRiderInput) -> bool:
	return ri != null and ri.rescue and not ri.on_reserve()


## The sprint rule of the rider behind `ri` (null for an unknown peer).
static func rider_rule(state: TankState, ri: TankRiderInput) -> SprintRule:
	var r := state.rider(ri.peer)
	if r == null:
		return null
	return r.sprint_rule(state.content.num("tanks", "evade.sprint_window_s", 3.0))


# --- Gun (dynamo) --------------------------------------------------------------------------------


## The Gun's capacitor bank: charges on its rider's P_eff in band, the stabilizer drains it while an
## enemy is in range; full in the depot. An empty Gun seat leaves it as it is.
static func _dynamo(
	state: TankState, aux: TankAux, st: TankDynamoState, ri: TankRiderInput, dt: float
) -> void:
	var c := state.content
	var manned := st.slot >= 0
	st.stabilizing = manned and aux.enemy_in_range and not state.all_afk
	st.stalled = in_rescue(ri) and not state.all_afk
	if not manned or state.all_afk or st.stalled:
		return
	if state.seg.seg == TankIds.SEG_DEPOT:
		st.bank = c.num("tanks", "dynamo.bank_max", 100.0)
		return
	var bank := st.bank
	if st.in_band:
		bank += st.p_eff_w * dt / c.num("tanks", "dynamo.j_per_unit", 150.0)
	if st.stabilizing:
		bank -= stabilizer_per_s(state) * dt
	st.bank = clampf(bank, 0.0, c.num("tanks", "dynamo.bank_max", 100.0))


## The dynamo's stabilizer drain in units a second: the tank's own (tanks.json
## tanks.<tank>.stabilizer_per_s, where a tank has one), else dynamo.stabilizer_per_s.
static func stabilizer_per_s(state: TankState) -> float:
	var c := state.content
	var own: Variant = c.tank_def(state.hull.tank).get("stabilizer_per_s")
	if own is float or own is int:
		return float(own)
	return c.num("tanks", "dynamo.stabilizer_per_s", 1.5)


# --- Lights (arc generator) ----------------------------------------------------------------------


## The Lights seat (brief 2.4, v3): a rescue stalls it (the searchlights dim: "Arc generator
## stalled"); the searchlights are lit while its rider is in band (ERG: power >= 95% of the applied
## target and cadence >= 60), which never holds on reserve, in rescue or with the seat empty. Its
## load (`duty`, the director's ERG pattern 65 + 15 x duty) is the share of the last 10 s an enemy
## stood in range (the searchlights trained on it).
static func _arc(state: TankState, aux: TankAux, st: TankArcState, ri: TankRiderInput) -> void:
	st.stalled = in_rescue(ri) and not state.all_afk
	st.lit = st.slot >= 0 and st.in_band and not st.stalled and not st.reserve and not state.all_afk
	st.note_fire(state.tick, aux.enemy_in_range and st.slot >= 0)


# --- Loader (steam) ------------------------------------------------------------------------------


## The Loader (v3): while the rack has room its rider's P_eff in band (or the reserve's) builds the
## next shell, pressure 0 -> 100% on tanks.json steam.full_j; at 100% the shell goes into the rack
## (a heavy shell, the latch event) and, where the rider may sprint (TankDrive.ability_ok), the
## "Surge to overpressure" window opens for window_s: an `over` intent in it takes that shell back
## to the boiler and overpressures it (_overpressure). The `latch` intent stows a light shell from
## light_latch_pct. With the rack full the loader idles (`loaded`: no boiler grade, cadence band
## 50). Pressure holds in checkpoints and the cool-down. An empty Loader seat loads nothing.
static func _steam(
	state: TankState,
	aux: TankAux,
	st: TankSteamState,
	ri: TankRiderInput,
	dt: float,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	st.cycling = false
	st.chamber = state.hull.loaded != TankIds.SHELL_NONE
	st.rack = aux.rack_types.size()
	st.loaded = st.rack >= TankConst.RACK_MAX and not st.over
	if ri == null:
		st.sprinting = false
		st.window_s = 0.0
		st.load_t = clampf(st.pressure_pct / 100.0, 0.0, 1.0) if not st.loaded else 0.0
		return
	var rule := rider_rule(state, ri)
	st.sprinting = rule != null and rule.holds()
	var able := TankDrive.ability_ok(ri)
	for n in ri.intents:
		match str(n.get("k", "")):
			TankIds.INTENT_LATCH:
				_latch(state, aux, st, ri, events)
			TankIds.INTENT_OVER:
				if able and st.window_s > 0.0 and not st.over:
					_start_over(state, aux, st)
	st.window_s = maxf(st.window_s - dt, 0.0)
	if state.all_afk:
		return
	# Pressure holds in checkpoints and in the cool-down (no boiler grade there, brief 2.3).
	var seg := state.seg.seg
	if seg == TankIds.SEG_CHECKPOINT or seg == TankIds.SEG_COOLDOWN:
		return
	if st.over:
		_overpressure(state, aux, st, ri, dt, events)
		st.load_t = 1.0
		return
	st.loaded = st.rack >= TankConst.RACK_MAX
	if st.loaded:
		st.load_t = 0.0
		return
	if st.in_band or st.reserve:
		st.pressure_pct += st.p_eff_w * dt / c.num("tanks", "steam.full_j", 1750.0) * 100.0
	if st.pressure_pct >= 100.0:
		st.pressure_pct = 0.0
		_stow(aux, st, ri.slot, TankIds.SHELL_HEAVY, events)
		var window := c.num("tanks", "steam.window_s", 5.0)
		if able and window > 0.0 and not ri.in_warmup():
			st.window_s = window
	st.load_t = clampf(st.pressure_pct / 100.0, 0.0, 1.0)


## A shell of `shell` goes into the ready rack (the latch event: the view's loader stows it).
static func _stow(aux: TankAux, st: TankSteamState, slot: int, shell: int, events: Array) -> void:
	aux.rack_types.append(shell)
	st.rack = aux.rack_types.size()
	st.loaded = st.rack >= TankConst.RACK_MAX
	events.append(TankEvents.latch(slot, shell))


## `over` inside the window: the shell just stowed goes back to the boiler at 100% and the boiler
## overpressures it; the next shell's progress waits (aux.carry_pct).
static func _start_over(state: TankState, aux: TankAux, st: TankSteamState) -> void:
	if aux.rack_types.is_empty() or aux.rack_types.back() != TankIds.SHELL_HEAVY:
		return
	aux.rack_types.pop_back()
	st.rack = aux.rack_types.size()
	aux.carry_pct = st.pressure_pct
	st.pressure_pct = 100.0
	st.over = true
	st.over_s = 0.0
	st.window_s = 0.0
	st.loaded = false
	aux.over_j = 0.0
	TankAux.of(state).over_j = 0.0


## Overpressure: 100 -> over_max_pct on over_j of P_eff while the sprint rule holds (it bleeds
## over_bleed_pct_s otherwise); at the top the Overpressure shell goes into the rack, after
## over_max_s a heavy one; then the next shell's progress comes back.
static func _overpressure(
	state: TankState,
	aux: TankAux,
	st: TankSteamState,
	ri: TankRiderInput,
	dt: float,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	var over_j := c.num("tanks", "steam.over_j", 3000.0)
	var top := c.num("tanks", "steam.over_max_pct", 150.0)
	st.over_s += dt
	if st.sprinting:
		aux.over_j += st.p_eff_w * dt
		st.pressure_pct = 100.0 + (top - 100.0) * minf(aux.over_j / over_j, 1.0)
	else:
		st.pressure_pct = maxf(
			st.pressure_pct - c.num("tanks", "steam.over_bleed_pct_s", 2.0) * dt, 100.0
		)
		aux.over_j = (st.pressure_pct - 100.0) / (top - 100.0) * over_j
	var shell := TankIds.SHELL_NONE
	if st.pressure_pct >= top - 1e-6:
		shell = TankIds.SHELL_OVER
	elif st.over_s >= c.num("tanks", "steam.over_max_s", 30.0):
		shell = TankIds.SHELL_HEAVY
	if shell == TankIds.SHELL_NONE:
		return
	st.over = false
	st.over_s = 0.0
	aux.over_j = 0.0
	st.pressure_pct = aux.carry_pct
	aux.carry_pct = 0.0
	_stow(aux, st, ri.slot, shell, events)


## The latch intent: a light shell from light_latch_pct (the shell in progress goes in early).
static func _latch(
	state: TankState,
	aux: TankAux,
	st: TankSteamState,
	ri: TankRiderInput,
	events: Array[Dictionary]
) -> void:
	if st.over or state.all_afk or st.rack >= TankConst.RACK_MAX:
		return
	if st.pressure_pct >= state.content.num("tanks", "steam.light_latch_pct", 40.0):
		st.pressure_pct = 0.0
		_stow(aux, st, ri.slot, TankIds.SHELL_LIGHT, events)
