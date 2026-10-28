class_name TankStations
extends RefCounted
## The engine rooms' models (brief 2.4 Dynamo, Steam, Arc generator; owner: rules): the dynamo's
## capacitor bank and the gunner's hoist, the steam engine's boiler (window, Overpressure, light
## latch, breech cycle) and the arc generator (searchlights, stall). The diesel's drive is
## TankDrive, the bow guns TankBow. Every energy is the room's P_eff (reserve 60 W for an AFK
## rider, 0 when everyone is AFK; an empty seat, slot -1, has none). Pure: no random draws; time
## only through `dt`. v3 retired the Bulwark's three-way gearbox; the Secondaries seat (feed) has
## no model here yet (the v3 rules builder adds it).


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
			_arc(state, st as TankArcState, ri)
	_gunner_hoist(state, aux, dt, events)


# --- Shell loading -----------------------------------------------------------------------------


## Puts `shell` in the breech and raises the latch event; false when the breech is busy.
static func load_shell(state: TankState, shell: int, slot: int, events: Array[Dictionary]) -> bool:
	if state.hull.loaded != TankIds.SHELL_NONE or state.hull.breech_s > 0.0:
		return false
	state.hull.loaded = shell
	events.append(TankEvents.latch(slot, shell))
	return true


## The station of the gunner: the dynamo (the Gun seat), else null.
static func gunner(state: TankState) -> TankStationState:
	return state.station(TankIds.ENGINE_DYNAMO)


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


# --- Dynamo --------------------------------------------------------------------------------------


static func _dynamo(
	state: TankState, aux: TankAux, st: TankDynamoState, ri: TankRiderInput, dt: float
) -> void:
	var c := state.content
	st.stabilizing = aux.enemy_in_range and not state.all_afk
	st.stalled = in_rescue(ri) and not state.all_afk
	if state.all_afk or st.stalled:
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


## The gunner's hoist (v2's Rampart hoist; v3 interim): with the Gun seat manned and the Loader
## seat empty (or absent) it lifts a heavy shell, 10 s at a bank of 50 or more up to 20 s at 0, once
## a shot is cleared of the breech cycle and a target stands. It costs the bank 25 units when it
## starts and stops while the dynamo is stalled or the tank broke. The v3 rules builder replaces it
## (brief v3: an empty Loader seat means no reloads).
static func _gunner_hoist(
	state: TankState, aux: TankAux, dt: float, events: Array[Dictionary]
) -> void:
	var st := state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	var loader := state.station(TankIds.ENGINE_STEAM)
	if st == null or (loader != null and not loader.is_empty()) or st.slot < 0:
		return
	if state.hull.breakdown or state.all_afk or st.stalled:
		return
	var hull := state.hull
	if hull.loaded != TankIds.SHELL_NONE or hull.breech_s > 0.0:
		return
	if st.hoist_s > 0.0:
		st.hoist_s = maxf(st.hoist_s - dt, 0.0)
		if st.hoist_s == 0.0:
			load_shell(state, TankIds.SHELL_HEAVY, st.slot, events)
		return
	if TankAim.current(state, aux) == null:
		return
	var c := state.content
	st.hoist_s = by_bank(state, c.value("tanks", "dynamo.hoist_s", [20, 10]))
	drain(state, c.num("tanks", "dynamo.per_hoist", 25.0))


# --- Arc generator ------------------------------------------------------------------------------


## The arc generator (brief 2.4): a rescue stalls it (the bow guns stop, the searchlights dim:
## "Arc generator stalled"); the searchlights are lit while its rider is in band (ERG: power >= 95%
## of the applied target and cadence >= 60), which never holds on reserve or in rescue. Its load
## (`duty`) is the bow guns' share of the last 10 s firing (TankBow notes it).
static func _arc(state: TankState, st: TankArcState, ri: TankRiderInput) -> void:
	st.stalled = in_rescue(ri) and not state.all_afk
	st.lit = st.slot >= 0 and st.in_band and not st.stalled and not st.reserve and not state.all_afk


# --- Steam ---------------------------------------------------------------------------------------


static func _steam(
	state: TankState,
	aux: TankAux,
	st: TankSteamState,
	ri: TankRiderInput,
	dt: float,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	var hull := state.hull
	st.loaded = hull.loaded != TankIds.SHELL_NONE
	st.cycling = hull.breech_s > 0.0
	if ri == null:
		return
	var rule := rider_rule(state, ri)
	st.sprinting = rule != null and rule.holds()
	var able := TankDrive.ability_ok(ri)
	for n in ri.intents:
		match str(n.get("k", "")):
			TankIds.INTENT_LATCH:
				_latch(state, st, ri, events)
			TankIds.INTENT_OVER:
				if able and st.window_s > 0.0 and not st.over:
					st.over = true
					st.window_s = 0.0
					st.over_s = 0.0
					aux.over_j = 0.0
	if state.all_afk or st.loaded or st.cycling:
		return
	# Pressure holds in checkpoints and in the cool-down (no boiler grade there, brief 2.3).
	if state.seg.seg == TankIds.SEG_CHECKPOINT or state.seg.seg == TankIds.SEG_COOLDOWN:
		return
	var full_j := c.num("tanks", "steam.full_j", 6000.0)
	if st.over:
		_overpressure(state, aux, st, ri, dt, events)
		return
	if st.window_s > 0.0:
		st.window_s = maxf(st.window_s - dt, 0.0)
		if st.window_s == 0.0:
			_do_latch(state, st, ri, TankIds.SHELL_HEAVY, events)
		return
	st.pressure_pct += st.p_eff_w * dt / full_j * 100.0
	if st.pressure_pct >= 100.0:
		st.pressure_pct = 100.0
		var no_window := ri.in_warmup() or ri.in_first_window()
		var window := c.num("tanks", "steam.window_s", 5.0)
		if no_window or window <= 0.0:
			_do_latch(state, st, ri, TankIds.SHELL_HEAVY, events)
		else:
			st.window_s = window


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
	if st.pressure_pct >= top - 1e-6:
		_do_latch(state, st, ri, TankIds.SHELL_OVER, events)
	elif st.over_s >= c.num("tanks", "steam.over_max_s", 30.0):
		_do_latch(state, st, ri, TankIds.SHELL_HEAVY, events)


## The latch intent: a light shell from 40% pressure; a heavy one inside the window or the
## Overpressure build (the shell is as good as latched already).
static func _latch(
	state: TankState, st: TankSteamState, ri: TankRiderInput, events: Array[Dictionary]
) -> void:
	if st.loaded or st.cycling or state.all_afk:
		return
	if st.window_s > 0.0 or st.over:
		_do_latch(state, st, ri, TankIds.SHELL_HEAVY, events)
	elif st.pressure_pct >= state.content.num("tanks", "steam.light_latch_pct", 40.0):
		_do_latch(state, st, ri, TankIds.SHELL_LIGHT, events)


static func _do_latch(
	state: TankState, st: TankSteamState, ri: TankRiderInput, shell: int, events: Array[Dictionary]
) -> void:
	if not load_shell(state, shell, ri.slot, events):
		return
	st.pressure_pct = 0.0
	st.window_s = 0.0
	st.over = false
	st.over_s = 0.0
	st.loaded = true
	TankAux.of(state).over_j = 0.0


## The sprint rule of the rider behind `ri` (null for an unknown peer).
static func rider_rule(state: TankState, ri: TankRiderInput) -> SprintRule:
	var r := state.rider(ri.peer)
	if r == null:
		return null
	return r.sprint_rule(state.content.num("tanks", "evade.sprint_window_s", 3.0))
