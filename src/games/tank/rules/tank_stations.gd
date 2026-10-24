class_name TankStations
extends RefCounted
## The engine rooms' models (brief 2.4 Dynamo, Steam, Bulwark gearbox; owner: rules): the dynamo's
## capacitor bank and the Rampart's hoist, the steam engine's boiler (window, Overpressure, light
## latch, breech cycle) and the Bulwark's three-way gearbox with its auto-lever. The diesel's
## drive is TankDrive. Every energy is the room's P_eff (reserve 60 W for an AFK rider, 0 when
## everyone is AFK). Pure: no random draws; time only through `dt`.


static func step(
	state: TankState, inputs: TankInputs, dt: float, events: Array[Dictionary]
) -> void:
	var aux := TankAux.of(state)
	aux.turret_factor = 0.0
	for st in state.stations:
		var ri: TankRiderInput = inputs.rider(st.peer) if st.slot >= 0 else null
		if st is TankGearboxState:
			_gearbox(state, aux, st as TankGearboxState, ri, dt, events)
		elif st is TankDynamoState:
			_dynamo(state, aux, st as TankDynamoState, ri, dt)
		elif st is TankSteamState:
			_steam(state, aux, st as TankSteamState, ri, dt, events)
	_rampart_hoist(state, aux, dt, events)


# --- Shell loading -----------------------------------------------------------------------------


## Puts `shell` in the breech and raises the latch event; false when the breech is busy.
static func load_shell(state: TankState, shell: int, slot: int, events: Array[Dictionary]) -> bool:
	if state.hull.loaded != TankIds.SHELL_NONE or state.hull.breech_s > 0.0:
		return false
	state.hull.loaded = shell
	events.append(TankEvents.latch(slot, shell))
	return true


## The station of the gunner: the dynamo, else the Bulwark's gearbox, else null.
static func gunner(state: TankState) -> TankStationState:
	var d := state.station(TankIds.ENGINE_DYNAMO)
	return d if d != null else state.station(TankIds.ENGINE_BULWARK)


## Takes `units` out of the dynamo's bank (never below 0). A tank without a dynamo has no bank.
static func drain(state: TankState, units: float) -> void:
	var d := state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	if d != null:
		d.bank = maxf(d.bank - units, 0.0)


## The dynamo's bank scaled to 0..1 at `full_at` units (1 for the Bulwark, which has no bank).
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
		bank -= c.num("tanks", "dynamo.stabilizer_per_s", 1.5) * dt
	st.bank = clampf(bank, 0.0, c.num("tanks", "dynamo.bank_max", 100.0))


## The Rampart's hoist (no steam engine, no gearbox): it lifts a heavy shell, 10 s at a bank of 50
## or more up to 20 s at 0, once a shot is cleared of the breech cycle and a target stands. It
## costs the bank 25 units when it starts and stops while the dynamo is stalled or the tank broke.
static func _rampart_hoist(
	state: TankState, aux: TankAux, dt: float, events: Array[Dictionary]
) -> void:
	var st := state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	if st == null or state.station(TankIds.ENGINE_STEAM) != null or st.slot < 0:
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
	return r.sprint_rule(state.content.num("tanks", "ram.sprint_window_s", 3.0))


# --- Bulwark gearbox -----------------------------------------------------------------------------


static func _gearbox(
	state: TankState,
	aux: TankAux,
	g: TankGearboxState,
	ri: TankRiderInput,
	dt: float,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	var hull := state.hull
	if hull.breakdown and (g.lever != TankIds.LEVER_DRIVE or g.lever_to != TankIds.LEVER_DRIVE):
		g.lever = TankIds.LEVER_DRIVE
		g.lever_to = TankIds.LEVER_DRIVE
		g.move_s = 0.0
		g.dwell_s = 0.0
	if g.move_s > 0.0:
		g.move_s = maxf(g.move_s - dt, 0.0)
		if g.move_s == 0.0:
			g.lever = g.lever_to
			g.dwell_s = 0.0
	else:
		g.dwell_s += dt
	if g.suspend_s > 0.0:
		g.suspend_s = maxf(g.suspend_s - dt, 0.0)
		if g.suspend_s == 0.0:
			g.auto = true
	var slot := ri.slot if ri != null else -1
	if state.seg.seg == TankIds.SEG_ADVANCE and g.lever == TankIds.LEVER_DRIVE and g.move_s == 0.0:
		g.drive_s += dt
	if ri != null and not hull.breakdown:
		for n in ri.intents:
			match str(n.get("k", "")):
				TankIds.INTENT_LEVER:
					_manual_lever(state, g, slot, n, events)
				TankIds.INTENT_LATCH:
					_light_latch(state, g, slot, events)
	if g.auto and g.move_s == 0.0 and not hull.breakdown and not state.all_afk:
		if g.dwell_s >= c.num("tanks", "gearbox.auto_dwell_s", 3.0):
			var want := _auto_lever(state, aux)
			if want != g.lever:
				_start_move(state, g, want, slot, events)
	# Power: nothing during a move, and nothing in a gun line while the rider is in rescue.
	var power := g.p_eff_w
	if g.move_s > 0.0 or (state.seg.seg == TankIds.SEG_GUN_LINE and in_rescue(ri)):
		power = 0.0
		g.p_eff_w = 0.0
	if g.lever == TankIds.LEVER_TURRET and g.move_s == 0.0:
		var full := c.num("tanks", "gearbox.turret_full_w", 200.0)
		aux.turret_factor = clampf(power / full, 0.0, 1.0)
	elif g.lever == TankIds.LEVER_HOIST and g.move_s == 0.0:
		if hull.loaded == TankIds.SHELL_NONE and hull.breech_s <= 0.0 and not hull.breakdown:
			g.hoist_j += power * dt
			if g.hoist_j >= c.num("tanks", "gearbox.hoist_j", 4000.0):
				if load_shell(state, TankIds.SHELL_HEAVY, slot, events):
					g.hoist_j = 0.0


## Starts a lever move (it takes gearbox.move_s, 1 s, with no power anywhere).
static func _start_move(
	state: TankState, g: TankGearboxState, to: int, slot: int, events: Array[Dictionary]
) -> void:
	g.lever_to = to
	g.move_s = state.content.num("tanks", "gearbox.move_s", 1.0)
	events.append(TankEvents.lever(slot, to))


static func _manual_lever(
	state: TankState, g: TankGearboxState, slot: int, n: Dictionary, events: Array[Dictionary]
) -> void:
	if g.move_s > 0.0:
		return
	var to := int(n.get("to", -1))
	if to < 0:
		var step := int(n.get("d", 0))
		to = posmod(g.lever + step, 3) if step != 0 else g.lever
	g.auto = false
	g.suspend_s = state.content.num("tanks", "gearbox.manual_suspend_s", 15.0)
	if to != g.lever:
		_start_move(state, g, to, slot, events)


## The light shell: a hoist of 40% or more, once the breech is free.
static func _light_latch(
	state: TankState, g: TankGearboxState, slot: int, events: Array[Dictionary]
) -> void:
	var c := state.content
	var full := c.num("tanks", "gearbox.hoist_j", 4000.0)
	var need := full * c.num("tanks", "gearbox.light_latch_pct", 40.0) / 100.0
	if g.hoist_j >= need and load_shell(state, TankIds.SHELL_LIGHT, slot, events):
		g.hoist_j = 0.0


## The auto-lever's choice (brief 2.4): Drive on a breakdown; in an Advance Drive when nothing
## stands within auto_drive_clear_px; Hoist when unloaded with a target; Turret when loaded and
## the gun is not on the target (or faces away); else Drive.
static func _auto_lever(state: TankState, aux: TankAux) -> int:
	var hull := state.hull
	if hull.breakdown:
		return TankIds.LEVER_DRIVE
	var tgt := TankAim.current(state, aux)
	var seg := state.seg.seg
	if seg == TankIds.SEG_ADVANCE or seg == TankIds.SEG_SKIRMISH:
		var clear := state.content.num("tanks", "gearbox.auto_drive_clear_px", 300.0)
		if not _target_within(state, aux, clear):
			return TankIds.LEVER_DRIVE
	if tgt == null:
		return TankIds.LEVER_DRIVE
	if hull.loaded == TankIds.SHELL_NONE:
		return TankIds.LEVER_HOIST
	if not TankGun.on_target(state, aux):
		return TankIds.LEVER_TURRET
	return TankIds.LEVER_DRIVE


## Some enemy or obstacle stands on screen within `px` of the hull's nearer end.
static func _target_within(state: TankState, aux: TankAux, px: float) -> bool:
	var hull := state.hull
	var front := hull.x_px + hull.hull_w
	var cam := state.camera_x()
	for t in aux.targets:
		if t.drill or (not TankTargets.engageable(t, cam)):
			continue
		var d := t.rect.position.x - front
		if t.rect.end.x <= hull.x_px + hull.hull_w * 0.5:
			d = hull.x_px - t.rect.end.x
		if d <= px:
			return true
	return false
