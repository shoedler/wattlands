class_name TankDrive
extends RefCounted
## The tracks (brief 2.4 Drive; owner: rules): BRIEF 3.11's speed model (SpeedModel with the driving
## rider's mass + 8 kg, CdA 0.5 m^2, the terrain grade under the tank) on the driver's P_eff, the
## world scrolling at 0.4 x game speed (8 art px per game metre), obstacles that stop the tank, the
## Ram (a 10 s window, 30 s cooldown, SIM only, sprint rule held at contact), a failed Ram's 10 HP
## and 5 s stall, and the boss dodge. Ram, dodge and Overpressure do nothing in WARMUP phases or
## in the first 300 s of the plan (TankConst.FIRST_S): ability_ok().


## Whether the rider's own phase lets Ram, dodge and Overpressure work: a WORK phase in SIM mode
## and past the first 300 s of the plan.
static func ability_ok(ri: TankRiderInput) -> bool:
	return (
		ri != null
		and ri.phase_kind == Wl.WORK
		and ri.phase_mode == Wl.SIM
		and not ri.in_first_window()
	)


static func step(
	state: TankState, inputs: TankInputs, dt: float, events: Array[Dictionary]
) -> void:
	var aux := TankAux.of(state)
	var hull := state.hull
	var d := TankHullRules.driver(state)
	var ri: TankRiderInput = inputs.rider(d.peer) if d != null and d.slot >= 0 else null
	var rule := TankStations.rider_rule(state, ri) if ri != null else null
	if d != null:
		d.sprinting = rule != null and rule.holds()
		d.sprint_s = rule.held_s() if rule != null else 0.0
	hull.evasive = d != null and d.slot >= 0 and d.in_band
	_move(state, d, ri, dt)
	if d != null:
		_ram(state, aux, d, ri, dt, events)
		_dodge(state, aux, d, ri, events)


# --- Movement ------------------------------------------------------------------------------------


## Whether the segment lets the tank roll right now.
static func _may_move(state: TankState) -> bool:
	var sg := state.seg
	match sg.seg:
		TankIds.SEG_DEPOT:
			return TankSegments.depot_driving(state)
		TankIds.SEG_ADVANCE, TankIds.SEG_SKIRMISH:
			return not sg.objective_done and state.hull.distance_m < sg.length_m
		TankIds.SEG_COOLDOWN:
			return true
	return false


static func _move(state: TankState, d: TankDieselState, ri: TankRiderInput, dt: float) -> void:
	var c := state.content
	var hull := state.hull
	var sm := hull.speed_model(
		c.num("tanks", "drive.cda_m2", 0.5), c.num("tanks", "drive.mass_offset_kg", 8.0)
	)
	if ri != null:
		sm.rider_mass_kg = ri.rider_mass_kg
	hull.grade_pct = TankTerrain.for_segment(
		c, state.seg.segment_index, hull.distance_m, state.seg.kind == Wl.WARMUP
	)
	var power := 0.0
	if d != null:
		power = d.p_eff_w
		if d is TankGearboxState:
			var g := d as TankGearboxState
			if g.lever != TankIds.LEVER_DRIVE or g.move_s > 0.0:
				power = 0.0
	if hull.stall_s > 0.0:
		hull.stall_s = maxf(hull.stall_s - dt, 0.0)
	var rolls := (
		_may_move(state) and not hull.breakdown and hull.stall_s <= 0.0 and not state.all_afk
	)
	hull.holding = not rolls and not hull.breakdown and state.seg.seg != TankIds.SEG_CHECKPOINT
	if state.seg.seg == TankIds.SEG_CHECKPOINT or state.seg.seg == TankIds.SEG_BOSS:
		hull.holding = true
	hull.blocked_by = 0
	if not rolls:
		sm.v_mps = 0.0
		hull.speed_mps = 0.0
		return
	var v := sm.step(dt, power, hull.grade_pct)
	var dist := hull.distance_m + v * dt
	var stop_at := INF
	var seg := state.seg.seg
	if seg == TankIds.SEG_ADVANCE or seg == TankIds.SEG_SKIRMISH:
		stop_at = state.seg.length_m
	var blocker := 0
	var standoff := c.num("tanks", "props.standoff_px", 260.0)
	for o in state.obstacles:
		if o.cleared or not _blocks(o):
			continue
		var limit := (o.x_px - float(hull.hull_w) - standoff) / TankConst.PX_PER_M
		if limit >= hull.distance_m - 1e-6 and limit < stop_at:
			stop_at = limit
			blocker = o.id
	if dist >= stop_at:
		dist = stop_at
		sm.v_mps = 0.0
		v = 0.0
		hull.blocked_by = blocker
	hull.speed_mps = v
	hull.distance_m = dist
	hull.x_px = TankConst.m_to_px(dist)


static func _blocks(o: TankObstacleState) -> bool:
	return (
		o.code == TankIds.obstacle_code(TankIds.OBST_WIRE)
		or o.code == TankIds.obstacle_code(TankIds.OBST_WRECK)
	)


# --- Ram -----------------------------------------------------------------------------------------


## The nearest thing a Ram can reach: a rammable (light) enemy within the reach (reach_px, plus the
## tank's lunge_px as the sprint closes in) of the hull's nearer end, or the wire / wreck the tank
## stands off from (it stops props.standoff_px short, where the gun can reach it; the Ram charges it).
## Returns the TankEnemyState or TankObstacleState, or null.
static func ram_target(state: TankState, reach: float) -> Variant:
	var hull := state.hull
	var best: Variant = null
	var best_d := INF
	for e in state.enemies:
		if not bool(TankEnemies.def_of(state, e).get("rammable", false)):
			continue
		var dist := TankEnemies.distance(state, e)
		if dist <= reach and dist < best_d:
			best_d = dist
			best = e
	var front := hull.x_px + hull.hull_w
	var standoff := state.content.num("tanks", "props.standoff_px", 260.0)
	for o in state.obstacles:
		if o.cleared or not _blocks(o) or o.x_px + o.w <= hull.x_px:
			continue
		var dist := o.x_px - front
		if dist <= standoff + 8.0 and dist < best_d:
			best_d = dist
			best = o
	return best


static func _ram(
	state: TankState,
	aux: TankAux,
	d: TankDieselState,
	ri: TankRiderInput,
	dt: float,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	var hull := state.hull
	d.ram_cd_s = maxf(d.ram_cd_s - dt, 0.0)
	var able := ability_ok(ri) and d.slot >= 0 and not hull.breakdown and not state.all_afk
	d.prompt = false
	var reach := c.num("tanks", "ram.reach_px", 120.0) + c.num("tanks", "ram.boss_lunge_px", 24.0)
	if able and d.ram_s <= 0.0 and d.ram_cd_s <= 0.0:
		for n in ri.intents:
			if str(n.get("k", "")) == TankIds.INTENT_RAM:
				d.ram_s = c.num("tanks", "ram.window_s", 10.0)
				aux.ram_contact = false
				break
	if d.ram_s > 0.0:
		if not able:
			d.ram_s = 0.0
			return
		d.ram_s = maxf(d.ram_s - dt, 0.0)
		var target: Variant = ram_target(state, reach)
		if target != null:
			aux.ram_contact = true
			if d.sprinting:
				_ram_hit(state, aux, d, target, events)
				return
		if d.ram_s <= 0.0:
			_close_window(state, d)
			if aux.ram_contact:
				TankHullRules.hurt(state, c.num("tanks", "ram.fail_damage", 10.0), events)
				hull.stall_s = c.num("tanks", "ram.fail_stall_s", 5.0)
				events.append(TankEvents.ram(d.slot, false, 0))
				aux.ram_contact = false
			return
		d.prompt = not d.sprinting
		return
	if able and d.ram_cd_s <= 0.0:
		d.prompt = _ram_prompt(state, c)


static func _ram_prompt(state: TankState, c: TankContent) -> bool:
	var seg := state.seg.seg
	if seg == TankIds.SEG_BOSS:
		return state.boss.telegraph_s > 0.0
	if seg != TankIds.SEG_ADVANCE:
		return false
	return ram_target(state, c.num("tanks", "ram.prompt_px", 300.0)) != null


static func _close_window(state: TankState, d: TankDieselState) -> void:
	d.ram_s = 0.0
	d.ram_cd_s = state.content.num("tanks", "ram.cooldown_s", 30.0)


static func _ram_hit(
	state: TankState, aux: TankAux, d: TankDieselState, target: Variant, events: Array[Dictionary]
) -> void:
	var id := 0
	if target is TankEnemyState:
		var e := target as TankEnemyState
		id = e.id
		events.append(TankEvents.ram(d.slot, true, id))
		TankShells.kill_enemy(state, aux, e, TankEvents.BY_RAM, d.slot, events)
	else:
		var o := target as TankObstacleState
		id = o.id
		o.cleared = true
		events.append(TankEvents.ram(d.slot, true, id))
	var r := state.rider_at(d.slot)
	if r != null:
		r.rams += 1
	aux.ram_contact = false
	_close_window(state, d)


# --- Boss dodge ----------------------------------------------------------------------------------


## The Behemoth's main gun is in its telegraph: a sprint held for boss_dodge_hold_s inside it makes
## that shot miss. `dodge_s` counts the held time inside the telegraph.
static func _dodge(
	state: TankState,
	aux: TankAux,
	d: TankDieselState,
	ri: TankRiderInput,
	events: Array[Dictionary]
) -> void:
	var b := state.boss
	var able := ability_ok(ri) and d.slot >= 0 and not state.hull.breakdown and not state.all_afk
	if b.telegraph_s <= 0.0 or not able:
		d.dodge_s = 0.0
		return
	if state.seg.seg == TankIds.SEG_BOSS:
		d.prompt = d.prompt or not b.dodged
	var inside := maxf(aux.boss_tele_total - b.telegraph_s, 0.0)
	d.dodge_s = minf(d.sprint_s, inside)
	var hold := state.content.num("tanks", "ram.boss_dodge_hold_s", 3.0)
	if not b.dodged and d.dodge_s >= hold:
		b.dodged = true
		var r := state.rider_at(d.slot)
		if r != null:
			r.dodges += 1
		events.append(TankEvents.dodge(d.slot))
