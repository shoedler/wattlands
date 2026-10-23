class_name TankGun
extends RefCounted
## The main turret and the Citadel's secondaries (brief 2.4 Gun; owner: rules). The gunner is the
## dynamo (Rampart, Citadel) or the Bulwark's gearbox on Turret. Elevation -5..+30 degrees at 8
## degrees/s with a full bank (2 at 0), a traverse takes 2.5 s (8 s at 0) and flips the facing when
## it completes; the bank pays 0.5 per degree and 15 per traverse. Auto-aim (default) aims once a
## shell is in the breech and fires within 0.5 degrees; the rider's nudges pause it for 5 s.
## Shells inherit the hull's velocity, so a moving tank's shell keeps the tank's pace.


static func step(
	state: TankState, inputs: TankInputs, dt: float, events: Array[Dictionary]
) -> void:
	var aux := TankAux.of(state)
	var gs := TankStations.gunner(state)
	if gs == null or gs.slot < 0:
		return
	var c := state.content
	var hull := state.hull
	var ri := inputs.rider(gs.peer)
	hull.aim_pause_s = maxf(hull.aim_pause_s - dt, 0.0)
	var powered := not hull.breakdown and not state.all_afk
	var elev_rate := 0.0
	var trav_rate := 0.0
	var elev_pair: Array = c.value("tanks", "dynamo.elev_deg_s", [2, 8])
	if powered:
		if gs is TankDynamoState:
			if not (gs as TankDynamoState).stalled:
				elev_rate = TankStations.by_bank(state, elev_pair)
				trav_rate = 1.0
		else:
			elev_rate = float(elev_pair[1]) * aux.turret_factor
			trav_rate = aux.turret_factor
	if ri != null and powered:
		for n in ri.intents:
			_intent(state, aux, gs, n, trav_rate, events)
	var tgt := TankAim.current(state, aux)
	var drill := TankSegments.drill_targets(state)
	if tgt != null:
		if not aux.manual_target:
			hull.target_id = tgt.id
	elif not aux.manual_target:
		hull.target_id = 0
	var auto := hull.aim_pause_s <= 0.0
	if auto and tgt != null and powered and (hull.loaded != TankIds.SHELL_NONE or drill):
		hull.elev_target_deg = aux.aim_elev
		if hull.facing != aux.aim_facing and hull.traverse_s <= 0.0 and trav_rate > 0.0:
			_start_traverse(state, gs)
	# Slew.
	var lo := c.num("tanks", "gun.elev_min_deg", -5.0)
	var hi := c.num("tanks", "gun.elev_max_deg", 30.0)
	hull.elev_target_deg = clampf(hull.elev_target_deg, lo, hi)
	var step := elev_rate * dt
	var d := clampf(hull.elev_target_deg - hull.elev_deg, -step, step)
	if absf(d) > 0.0:
		hull.elev_deg += d
		if gs is TankDynamoState:
			TankStations.drain(state, c.num("tanks", "dynamo.per_degree", 0.5) * absf(d))
	if hull.traverse_s > 0.0 and trav_rate > 0.0:
		hull.traverse_s = maxf(hull.traverse_s - dt * trav_rate, 0.0)
		if hull.traverse_s <= 0.0:
			hull.facing = -hull.facing
			hull.traverse_s = 0.0
	# Auto fire.
	if auto and tgt != null and powered and can_fire(hull) and on_target(state, aux):
		if not tgt.drill or TankSegments.fire_drill(state):
			fire(state, aux, gs, tgt.drill, events)
	_secondaries(state, aux, dt, events)


## Whether a loaded shell can leave the barrel now: loaded, the breech cycle over, no traverse.
static func can_fire(hull: TankHullState) -> bool:
	return hull.loaded != TankIds.SHELL_NONE and hull.breech_s <= 0.0 and hull.traverse_s <= 0.0


## The gun faces the auto-aim's target and its elevation is within aim_tol_deg of the solution.
static func on_target(state: TankState, aux: TankAux) -> bool:
	if aux.aim_target == null:
		return false
	var hull := state.hull
	var tol := state.content.num("tanks", "gun.aim_tol_deg", 0.5)
	return (
		hull.facing == aux.aim_facing
		and hull.traverse_s <= 0.0
		and absf(hull.elev_deg - aux.aim_elev) <= tol
	)


static func _intent(
	state: TankState,
	aux: TankAux,
	gs: TankStationState,
	n: Dictionary,
	trav_rate: float,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	var hull := state.hull
	match str(n.get("k", "")):
		TankIds.INTENT_AIM:
			hull.elev_target_deg = clampf(
				hull.elev_deg + float(int(n.get("d", 0))) * c.num("tanks", "gun.nudge_deg", 1.0),
				c.num("tanks", "gun.elev_min_deg", -5.0),
				c.num("tanks", "gun.elev_max_deg", 30.0)
			)
			hull.aim_pause_s = c.num("tanks", "gun.manual_pause_s", 5.0)
		TankIds.INTENT_TARGET:
			_cycle_target(state, aux, int(n.get("d", 1)))
		TankIds.INTENT_TRAVERSE:
			if hull.traverse_s <= 0.0 and trav_rate > 0.0:
				_start_traverse(state, gs)
				# A turret turned by hand stays where it was sent for a while, like a nudge.
				hull.aim_pause_s = c.num("tanks", "gun.manual_pause_s", 5.0)
		TankIds.INTENT_FIRE:
			if can_fire(hull):
				var tgt := TankTargets.by_id(aux, hull.target_id)
				fire(state, aux, gs, tgt != null and tgt.drill, events)


## Cycles the target to the next one to the right (d = 1) or left (-1) of the current one, among
## the targets on screen the gun can reach; the choice stays until it falls.
static func _cycle_target(state: TankState, aux: TankAux, d: int) -> void:
	var cam := state.camera_x()
	var drill := TankSegments.drill_targets(state)
	var list: Array[TankTarget] = []
	for t in aux.targets:
		if (t.drill and not drill) or (not TankTargets.engageable(t, cam)):
			continue
		list.append(t)
	if list.is_empty():
		return
	list.sort_custom(func(a: TankTarget, b: TankTarget) -> bool: return a.center().x < b.center().x)
	var at := -1
	for i in list.size():
		if list[i].id == state.hull.target_id:
			at = i
	var next := (
		0 if at < 0 and d > 0 else (list.size() - 1 if at < 0 else posmod(at + d, list.size()))
	)
	state.hull.target_id = list[next].id
	aux.manual_target = true
	state.hull.aim_pause_s = 0.0


## Starts a traverse (the facing flips when it completes); the bank pays per_traverse.
static func _start_traverse(state: TankState, gs: TankStationState) -> void:
	var c := state.content
	var pair: Array = c.value("tanks", "dynamo.traverse_s", [8, 2.5])
	if gs is TankDynamoState:
		state.hull.traverse_s = TankStations.by_bank(state, pair)
		TankStations.drain(state, c.num("tanks", "dynamo.per_traverse", 15.0))
	else:
		state.hull.traverse_s = float(pair[1])


## Fires the shell in the breech from the muzzle at the current elevation plus this tick's
## dispersion (a draw from the session RNG). `drill`: a depot drill shot counts for nothing.
static func fire(
	state: TankState, aux: TankAux, gs: TankStationState, drill: bool, events: Array[Dictionary]
) -> bool:
	var c := state.content
	var hull := state.hull
	if state.shells.size() >= int(c.num("tanks", "caps.shells", 24.0)):
		return false
	var shell := hull.loaded
	var bank := 100.0
	if gs is TankDynamoState:
		bank = (gs as TankDynamoState).bank
	var disp := TankBallistics.dispersion_deg(c, bank)
	var err := state.rng.randf_range(-disp, disp) if state.rng != null else 0.0
	var v0 := c.num("tanks", "gun.shell_speed_px_s", 360.0)
	var muzzle := TankAim.muzzle_world(state, aux, hull.elev_deg, hull.facing)
	var vel := TankBallistics.velocity(v0, hull.elev_deg + err, hull.facing)
	vel.x += TankConst.m_to_px(hull.speed_mps)
	var s := TankShellState.new()
	s.id = state.take_id()
	s.type = shell
	s.x = muzzle.x
	s.y = muzzle.y
	s.vx = vel.x
	s.vy = vel.y
	s.friendly = true
	s.target_id = hull.target_id
	s.damage = TankDamage.shell_damage(c, shell)
	s.source = gs.slot
	state.shells.append(s)
	hull.loaded = TankIds.SHELL_NONE
	var cycle_key := "gearbox.breech_cycle_s" if gs is TankGearboxState else "steam.breech_cycle_s"
	hull.breech_s = c.num("tanks", cycle_key, 6.0)
	events.append(TankEvents.shot(gs.slot, shell, s.id))
	if not drill:
		state.score.shots += 1
		var r := state.rider_at(gs.slot)
		if r != null:
			r.shots += 1
			r.shells_by_type[int(TankRiderState.SHELL_INDEX[shell])] += 1
	return true


static func tick_breech(state: TankState, dt: float) -> void:
	state.hull.breech_s = maxf(state.hull.breech_s - dt, 0.0)


# --- Citadel secondaries -------------------------------------------------------------------------


## The fore (right) and aft (left) machine guns: 5 damage every 3 s at the nearest enemy within 240
## px; each shot costs the bank 2 units and they stop below 10 units, in a breakdown and when the
## dynamo is stalled. They hit at once (a tracer), armour applies.
static func _secondaries(
	state: TankState, aux: TankAux, dt: float, events: Array[Dictionary]
) -> void:
	if state.hull.tank != TankIds.TANK_CITADEL:
		return
	var hull := state.hull
	var dyn := state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	var mounts := aux.geo.secondary_muzzles(hull.tank)
	if dyn == null or dyn.slot < 0 or mounts.size() < 2:
		return
	var c := state.content
	var ok := not hull.breakdown and not state.all_afk and not dyn.stalled
	var origin := TankTargets.hull_origin(state)
	for i in 2:
		hull.secondary_cd_s[i] = maxf(hull.secondary_cd_s[i] - dt, 0.0)
		if not ok or hull.secondary_cd_s[i] > 0.0:
			continue
		if dyn.bank < c.num("tanks", "dynamo.secondary_min_bank", 10.0):
			continue
		var mount: Array = mounts[i]
		var m: Vector2 = origin + (mount[0] as Vector2)
		var t := _nearest(
			state, aux, m.x, int(mount[1]), c.num("tanks", "secondary.range_px", 240.0)
		)
		if t == null:
			continue
		hull.secondary_cd_s[i] = c.num("tanks", "secondary.every_s", 3.0)
		TankStations.drain(state, c.num("tanks", "dynamo.per_secondary", 2.0))
		var sid := state.take_id()
		events.append(TankEvents.shot(dyn.slot, TankIds.SHELL_SECONDARY, sid))
		var r := state.rider_at(dyn.slot)
		if r != null:
			r.shells_by_type[int(TankRiderState.SHELL_INDEX[TankIds.SHELL_SECONDARY])] += 1
		var dmg := TankDamage.against(c, TankIds.SHELL_SECONDARY, t)
		var on := TankEvents.ON_ENEMY
		if t.kind == TankTarget.KIND_ENEMY:
			TankShells.damage_enemy(state, aux, t.enemy, dmg, TankEvents.BY_SHELL, dyn.slot, events)
		else:
			on = TankEvents.ON_BOSS
			TankShells.damage_boss(state, aux, t.part, dmg, dyn.slot, events)
		events.append(TankEvents.hit(on, t.id, dmg, TankIds.SHELL_SECONDARY, 0.0, t.center().x))


## The nearest enemy (or Behemoth part) in front of a machine gun at world x `mx` facing `face`
## and within `range_px` of it, on screen; null if none.
static func _nearest(
	state: TankState, aux: TankAux, mx: float, face: int, range_px: float
) -> TankTarget:
	var cam := state.camera_x()
	var best: TankTarget = null
	var best_d := INF
	for t in aux.targets:
		if t.kind == TankTarget.KIND_OBSTACLE or not collidable_enemy(t):
			continue
		if not TankTargets.engageable(t, cam):
			continue
		var d := t.rect.position.x - mx if face > 0 else mx - t.rect.end.x
		if face > 0 and t.rect.end.x < mx or face < 0 and t.rect.position.x > mx:
			continue
		d = maxf(d, 0.0)
		if d <= range_px and d < best_d:
			best_d = d
			best = t
	return best


static func collidable_enemy(t: TankTarget) -> bool:
	return TankShells.collidable(t)
